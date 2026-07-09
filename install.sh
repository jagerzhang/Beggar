#!/bin/bash
# beggar - CodeBuddy 多 Agent 省钱开发方案 - 在线安装脚本
# 用法: curl -fsSL <url> | bash

set -euo pipefail

# 颜色定义
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

print_info() { echo -e "${CYAN}[i]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# 显示帮助
show_help() {
    cat << 'EOF'
用法: curl -fsSL <url> | bash
      bash install.sh [选项]

选项:
  --global     直接全局安装到 ~/.codebuddy/（跳过交互式选择）
  --version    显示版本信息
  --help       显示此帮助信息

安装模式:
  无参数       交互式选择：项目安装 或 全局安装
  --global     直接进入全局安装（所有项目共享）

环境变量:
  BEGGAR_GLOBAL=1      等价于 --global 标志（非交互模式也生效）
  BEGGAR_INSTALL_DIR   自定义安装目录（默认: 当前目录）
EOF
}

show_version() {
    echo "beggar install script v1.0.0"
}

# 解析参数
BEGGAR_GLOBAL="${BEGGAR_GLOBAL:-0}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ "${1:-}" == "--version" || "${1:-}" == "-v" ]]; then
    show_version
    exit 0
fi

if [[ "${1:-}" == "--global" ]]; then
    BEGGAR_GLOBAL=1
    shift
fi

# 无 --global 标志 → 交互式选择（从 /dev/tty 读取，管道安装也支持）
# 如果 /dev/tty 不可用（纯非交互环境），默认项目安装
if [[ "$BEGGAR_GLOBAL" != "1" ]]; then
    echo ""
    echo -e "${CYAN}请选择安装模式:${NC}"
    echo "  1) 项目安装 — 安装到当前目录 .codebuddy/（默认）"
    echo "  2) 全局安装 — 安装到 ~/.codebuddy/（所有项目共享）"
    echo ""
    echo -n "请输入 (1/2，默认 1): "
    if read -r choice < /dev/tty 2>/dev/null && [[ "$choice" == "2" ]]; then
        BEGGAR_GLOBAL=1
    fi
    echo ""
fi

# 检查依赖
check_dependencies() {
    print_info "检查系统依赖..."

    local missing_deps=()

    if ! command -v curl &>/dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v tar &>/dev/null; then
        missing_deps+=("tar")
    fi

    # 检查 SHA256 计算工具
    if command -v sha256sum &>/dev/null; then
        SHA256_CMD="sha256sum"
    elif command -v shasum &>/dev/null; then
        SHA256_CMD="shasum -a 256"
    else
        missing_deps+=("sha256sum 或 shasum")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "缺少必要的依赖: ${missing_deps[*]}\n请安装后重试"
    fi

    print_success "依赖检查通过"
}

# 解析 JSON 字段
parse_json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | cut -d'"' -f4
}

# 主安装流程
main_install() {
    print_info "beggar - CodeBuddy 多 Agent 省钱开发方案"
    print_info "=========================================="

    local project_dir
    local codebuddy_dir

    if [[ "$BEGGAR_GLOBAL" == "1" ]]; then
        project_dir="${HOME}"
        codebuddy_dir="${HOME}/.codebuddy"
        print_info "安装模式: 全局安装 → ${codebuddy_dir}"
    else
        project_dir="${BEGGAR_INSTALL_DIR:-$(pwd)}"
        codebuddy_dir="$project_dir/.codebuddy"
        print_info "安装模式: 项目安装 → ${codebuddy_dir}"
    fi

    check_dependencies

    # 获取最新版本信息（使用 GitHub 静态重定向，不依赖 API，避免 403 速率限制）
    print_info "获取最新版本信息..."
    local version
    local download_url
    local expected_sha256

    version=$(curl -fsSL "https://github.com/jagerzhang/beggar/releases/latest/download/latest-version.txt" 2>/dev/null) || \
        print_error "无法获取远程版本信息，请检查网络连接"

    # 去除可能的空白字符
    version=$(echo "$version" | tr -d '[:space:]')

    if [[ -z "$version" ]]; then
        print_error "远程版本信息为空，请稍后重试"
    fi

    # 直接使用 releases/download 静态 URL（不经过 API）
    download_url="https://github.com/jagerzhang/beggar/releases/download/v${version}/beggar-v${version}.tar.gz"
    local sha256_url="https://github.com/jagerzhang/beggar/releases/download/v${version}/beggar-v${version}.tar.gz.sha256"

    # 尝试获取 SHA256（可选，失败不阻塞）
    expected_sha256=$(curl -fsSL "$sha256_url" 2>/dev/null | cut -d' ' -f1 || true)

    print_success "最新版本: v${version}"

    # 下载 tar.gz
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t beggar)
    # Windows Git Bash/MSYS2: 转换路径格式供 curl 等原生 Windows 程序使用
    if [[ -n "${MSYSTEM:-}" ]] && command -v cygpath &>/dev/null; then
        tmp_dir=$(cygpath -m "$tmp_dir")
    fi
    # 兜底清理：如果脚本因 exit/INT/TERM 中断，确保临时目录不泄漏
    # 注意：用双引号让 $tmp_dir 在此立即展开成实际路径并固化进 trap 命令，
    # 避免 EXIT trap 在函数返回后触发时 local tmp_dir 已脱离作用域，
    # 在 set -u 下报 "tmp_dir: unbound variable"
    trap "rm -rf -- \"$tmp_dir\"" EXIT
    local tar_file="$tmp_dir/beggar-v${version}.tar.gz"

    print_info "下载 beggar v${version}..."
    if ! curl -fL --progress-bar --retry 3 --retry-delay 2 -o "$tar_file" "$download_url"; then
        rm -rf "$tmp_dir"
        print_error "下载失败，请检查网络连接或 URL"
    fi
    print_success "下载完成"

    # 校验 SHA256（如果远程提供了）
    if [[ -n "$expected_sha256" ]]; then
        print_info "验证文件完整性..."
        local actual_sha256
        if [[ "$SHA256_CMD" == "sha256sum" ]]; then
            actual_sha256=$(sha256sum "$tar_file" | cut -d' ' -f1)
        else
            actual_sha256=$(shasum -a 256 "$tar_file" | cut -d' ' -f1)
        fi

        if [[ "$actual_sha256" != "$expected_sha256" ]]; then
            rm -rf "$tmp_dir"
            print_error "SHA256 校验失败\n  期望: $expected_sha256\n  实际: $actual_sha256\n文件可能已损坏，请重试"
        fi
        print_success "SHA256 校验通过"
    else
        print_warning "远程未提供 SHA256，跳过校验"
    fi

    # 解压 tar.gz 到临时子目录
    print_info "解压安装包..."
    local extract_dir="$tmp_dir/extract"
    mkdir -p "$extract_dir"
    if ! tar xzf "$tar_file" -C "$extract_dir"; then
        rm -rf "$tmp_dir"
        print_error "解压失败，请检查磁盘空间或文件权限"
    fi
    rm -f "$tar_file"

    # 计算文件 SHA256
    _file_hash() {
        if [[ "$SHA256_CMD" == "sha256sum" ]]; then
            sha256sum "$1" | cut -d' ' -f1
        else
            shasum -a 256 "$1" | cut -d' ' -f1
        fi
    }

    # 业务自定义 skill：只在目标不存在时安装，存在则跳过
    # openspec 相关：不存在时先尝试 npm 安装最新版，失败才复制
    _is_biz_only_on_missing() {
        local rel_path="$1"
        local biz_paths=(
            "commands/opsx"
            "skills/openspec-apply-change"
            "skills/openspec-archive-change"
            "skills/openspec-explore"
            "skills/openspec-propose"
        )
        for prefix in "${biz_paths[@]}"; do
            if [[ "$rel_path" == "$prefix" || "$rel_path" == "$prefix"/* ]]; then
                return 0
            fi
        done
        return 1
    }

    # 增量复制：如果 .codebuddy/ 已存在，按 SHA256 智能同步
    if [[ -d "$codebuddy_dir" ]]; then
        print_info "检测到已有目录: $codebuddy_dir"
        print_info "采用增量同步模式（SHA256 对比，beggar 官方文件有变更则覆盖）..."

        local added=0
        local updated=0
        local unchanged=0
        local biz_skipped=0

        local _find_tmp1
        _find_tmp1=$(mktemp 2>/dev/null || mktemp -t beggar_find1)
        find "$extract_dir" -type f -print0 > "$_find_tmp1"
        while IFS= read -r -d '' src_file; do
            local rel_path="${src_file#"$extract_dir"/}"
            local dst_file="$codebuddy_dir/$rel_path"

            # 业务自定义 skill：按文件判断，文件已存在则跳过，缺失则拷贝
            if _is_biz_only_on_missing "$rel_path"; then
                if [[ -e "$dst_file" ]]; then
                    biz_skipped=$((biz_skipped + 1))
                    continue
                fi
                mkdir -p "$(dirname "$dst_file")"
                cp -p "$src_file" "$dst_file"
                added=$((added + 1))
                continue
            fi

            if [[ -e "$dst_file" ]]; then
                local src_hash dst_hash
                src_hash=$(_file_hash "$src_file")
                dst_hash=$(_file_hash "$dst_file")

                if [[ "$src_hash" == "$dst_hash" ]]; then
                    unchanged=$((unchanged + 1))
                else
                    # 安装包内的文件属于 beggar 官方文件，内容不同则覆盖
                    cp -p "$src_file" "$dst_file"
                    updated=$((updated + 1))
                fi
            else
                mkdir -p "$(dirname "$dst_file")"
                cp -p "$src_file" "$dst_file"
                added=$((added + 1))
            fi
        done < "$_find_tmp1"
        rm -f "$_find_tmp1"

        print_success "增量同步完成: 新增 ${added} 个, 更新 ${updated} 个, 跳过 ${unchanged} 个无变化文件, 保留 ${biz_skipped} 个业务自定义文件"

        # 清理 beggar 管理的遗留文件（新版 tar.gz 中已删除的文件，如旧 rtk 二进制）
        print_info "清理遗留文件..."
        local removed=0
        local _find_tmp2
        _find_tmp2=$(mktemp 2>/dev/null || mktemp -t beggar_find2)
        find "$codebuddy_dir" -type f -print0 > "$_find_tmp2"
        while IFS= read -r -d '' dst_file; do
            local rel_path="${dst_file#"$codebuddy_dir"/}"
            local src_file="$extract_dir/$rel_path"
            # 如果目标文件存在但源文件不存在，且是 beggar 管理的路径，则删除
            if [[ ! -e "$src_file" ]]; then
                local is_beggar_managed=false
                case "$rel_path" in
                    tools/rtk-*|agents/*|rules/beggar-*|commands/beggar/*|commands/dev/*|commands/opsx/*|skills/beggar-*|skills/dev-workflow/*|skills/openspec-*)
                        is_beggar_managed=true
                        ;;
                esac
                if [[ "$is_beggar_managed" == true ]]; then
                    rm -f "$dst_file"
                    removed=$((removed + 1))
                fi
            fi
        done < "$_find_tmp2"
        rm -f "$_find_tmp2"
        # 清理空目录
        find "$codebuddy_dir" -type d -empty -print0 | while IFS= read -r -d '' empty_dir; do
            rmdir "$empty_dir" 2>/dev/null || true
        done
        if [[ "$removed" -gt 0 ]]; then
            print_success "已清理 ${removed} 个遗留文件"
        fi

        # 增量同步后，更新 .beggar-checksums 文件清单
        local checksums_file="$codebuddy_dir/.beggar-checksums"
        # 保留已有的 dir: 记录（旧版兼容），重建 file: 清单
        local old_dirs=""
        if [[ -f "$checksums_file" ]]; then
            old_dirs=$(grep "^dir:" "$checksums_file" 2>/dev/null || true)
        fi
        : > "$checksums_file"
        if [[ -n "$old_dirs" ]]; then
            echo "$old_dirs" >> "$checksums_file"
        fi
        local _find_tmp3
        _find_tmp3=$(mktemp 2>/dev/null || mktemp -t beggar_find3)
        find "$extract_dir" -type f -print0 > "$_find_tmp3"
        while IFS= read -r -d '' src_file; do
            local rel_path="${src_file#"$extract_dir"/}"
            # 业务自定义 skill 不进入清单（由用户决定是否保留）
            if ! _is_biz_only_on_missing "$rel_path"; then
                echo "file:$rel_path INSTALLED" >> "$checksums_file"
            fi
        done < "$_find_tmp3"
        rm -f "$_find_tmp3"
    else
        # 目标不存在，直接移动
        print_info "创建目录 $codebuddy_dir 并安装..."
        mkdir -p "$(dirname "$codebuddy_dir")"
        mv "$extract_dir" "$codebuddy_dir"
        # 记录 beggar 官方文件完整清单（用于卸载时精确删除）
        local checksums_file="$codebuddy_dir/.beggar-checksums"
        : > "$checksums_file"
        local _find_tmp4
        _find_tmp4=$(mktemp 2>/dev/null || mktemp -t beggar_find4)
        find "$codebuddy_dir" -type f -print0 > "$_find_tmp4"
        while IFS= read -r -d '' src_file; do
            local rel_path="${src_file#"$codebuddy_dir"/}"
            echo "file:$rel_path INSTALLED" >> "$checksums_file"
        done < "$_find_tmp4"
        rm -f "$_find_tmp4"
        print_success "安装完成"
    fi

    rm -rf "$tmp_dir"

    # 执行 setup.sh init
    print_info "运行初始化脚本..."
    if [[ -f "$codebuddy_dir/setup.sh" ]]; then
        chmod +x "$codebuddy_dir/setup.sh"
        if cd "$codebuddy_dir" && BEGGAR_GLOBAL="$BEGGAR_GLOBAL" ./setup.sh init; then
            print_success "初始化完成"
        else
            print_warning "初始化脚本执行失败，请手动运行: cd $codebuddy_dir && ./setup.sh init"
        fi
    else
        print_warning "未找到 setup.sh，请检查安装包"
    fi

    # 完成提示
    if [[ "$BEGGAR_GLOBAL" == "1" ]]; then
        cat << EOF

${GREEN}════════════════════════════════════════════${NC}
${GREEN}  beggar 全局安装成功！${NC}
${GREEN}════════════════════════════════════════════${NC}

版本:    beggar v${version}
目录:    ${codebuddy_dir}（所有项目共享）

后续操作:
  1. 查看配置:   ${CYAN}cd ~ && .codebuddy/setup.sh show${NC}
  2. 验证配置:   ${CYAN}cd ~ && .codebuddy/setup.sh validate${NC}
  3. 切换预设:   ${CYAN}cd ~ && .codebuddy/setup.sh agent preset economic${NC}

EOF
    else
        cat << EOF

${GREEN}════════════════════════════════════════════${NC}
${GREEN}  beggar 安装成功！${NC}
${GREEN}════════════════════════════════════════════${NC}

版本:    beggar v${version}
目录:    ${codebuddy_dir}

后续操作:
  1. 查看配置:   ${CYAN}cd ${codebuddy_dir} && ./setup.sh show${NC}
  2. 验证配置:   ${CYAN}cd ${codebuddy_dir} && ./setup.sh validate${NC}
  3. 切换预设:   ${CYAN}cd ${codebuddy_dir} && ./setup.sh agent preset economic${NC}

EOF
    fi

    print_success "安装完成"
}

# 异常处理
trap 'print_error "安装过程被中断"; exit 1' INT TERM

main_install "$@"
