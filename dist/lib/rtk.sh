#!/bin/bash
# beggar RTK utilities

# 安装 RTK（仅在线安装，不阻塞初始化流程）
_install_rtk() {
    # 优先检查全局 PATH 中是否已有 rtk（含 Windows 的 rtk.exe）
    if command -v rtk &>/dev/null; then
        local rtk_path
        rtk_path=$(command -v rtk)
        local version
        version=$(rtk --version 2>/dev/null || rtk -V 2>/dev/null || echo "")
        if [[ -n "$version" ]]; then
            print_info "RTK 已安装(全局): $version"
        else
            print_info "RTK 已安装(全局): $rtk_path"
        fi
        return 0
    fi

    # Windows Git Bash/MSYS2：尝试自动下载预编译二进制，失败则引导手动安装
    if [[ -n "${MSYSTEM:-}" ]]; then
        print_info "Windows 环境，尝试自动下载 RTK 预编译二进制..."

        local rtk_zip rtk_dest
        rtk_dest="$HOME/.local/bin"

        # 检测架构，x86_64 最通用
        local win_arch="x86_64"
        local rtk_url="https://github.com/rtk-ai/rtk/releases/latest/download/rtk-${win_arch}-pc-windows-msvc.zip"

        # 尝试下载并解压
        if command -v curl &>/dev/null && command -v unzip &>/dev/null; then
            rtk_zip=$(mktemp -t rtk-download-XXXXXX.zip 2>/dev/null || mktemp -t rtk 2>/dev/null).zip
            if curl -fsSL "$rtk_url" -o "$rtk_zip" 2>/dev/null; then
                mkdir -p "$rtk_dest"
                if unzip -o "$rtk_zip" -d "$rtk_dest" 2>/dev/null; then
                    rm -f "$rtk_zip"
                    if [[ -x "$rtk_dest/rtk.exe" ]]; then
                        local version
                        version=$("$rtk_dest/rtk.exe" --version 2>/dev/null || echo "ok")
                        print_success "RTK 已安装(自动): $version"
                        print_info "  安装路径: $rtk_dest/rtk.exe"
                        return 0
                    fi
                fi
            fi
            rm -f "$rtk_zip"
        fi

        print_warning "RTK 自动下载失败，请手动安装:"
        print_info "  1. 下载: https://github.com/rtk-ai/rtk/releases → rtk-x86_64-pc-windows-msvc.zip"
        print_info "  2. 解压 rtk.exe 到任意 PATH 目录（如 %USERPROFILE%\\.local\\bin）"
        print_info "  3. 完整功能（hook 自动重写）需 WSL，原生 Windows 仅支持过滤模式"
        return 0
    fi

    print_info "正在在线安装 RTK..."

    # 方式1: 在线安装脚本
    if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh 2>/dev/null; then
        # 在线脚本通常安装到 ~/.local/bin/rtk
        local global_rtk=""
        for path in "$HOME/.local/bin/rtk" "$HOME/.cargo/bin/rtk" "$HOME/bin/rtk"; do
            if [[ -x "$path" ]]; then
                global_rtk="$path"
                break
            fi
        done
        if [[ -n "$global_rtk" ]]; then
            local version
            version=$("$global_rtk" --version 2>/dev/null || echo "unknown")
            print_success "RTK 已安装(在线): $version"
            return 0
        fi
    fi

    print_warning "RTK 在线安装失败，跳过"
    print_info "可手动安装: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
}

# stats: RTK token 节省统计 + 工作流执行摘要
do_stats() {
    print_header

    # ── 工作流执行摘要统计 ──
    local memory_dir="$CODEBUDDY_DIR/memory"
    local stats_index="$memory_dir/run-stats-index.json"
    if [[ -f "$stats_index" ]]; then
        echo -e "${CYAN}工作流执行统计：${NC}\n"
        "$PYTHON_CMD" -c "
import json, os
try:
    with open('$stats_index') as f:
        stats = json.load(f)
    print(f'  总执行次数:     {stats.get(\"total_runs\", 0)}')
    print(f'  总执行时长:     {stats.get(\"total_duration_sec\", 0)} 秒')
    print(f'  Review Gate触发: {stats.get(\"total_review_gate_triggers\", 0)} 次')
    print(f'  Coder Guard升级: {stats.get(\"total_coder_guard_escalations\", 0)} 次')
    print(f'  最近一次执行:   {stats.get(\"last_run\", \"无\")}')
except Exception as e:
    print(f'  读取统计失败: {e}')
" 2>/dev/null
        echo ""

        # 展示最近的执行记录
        local recent_count=0
        while IFS= read -r -d '' f; do
            if [[ "$recent_count" -ge 3 ]]; then break; fi
            local fname
            fname=$(basename "$f")
            if [[ "$fname" == run-summary-*.json ]]; then
                echo -e "  ${YELLOW}$fname${NC}:"
                "$PYTHON_CMD" -c "
import json
with open('$f') as fh:
    d = json.load(fh)
phases = d.get('phases', {})
for pname, pdata in phases.items():
    dur = pdata.get('duration_sec', 0)
    print(f'    {pname}: {dur}s')
rg = d.get('review_gate', {})
cg = d.get('coder_guard', {})
print(f'    Review Gate: {rg.get(\"triggers\", 0)}次, Coder Guard: {cg.get(\"escalations\", 0)}次')
" 2>/dev/null
                echo ""
                recent_count=$((recent_count + 1))
            fi
        done < <(find "$memory_dir" -name "run-summary-*.json" -print0 2>/dev/null | sort -rz)
        if [[ "$recent_count" -eq 0 ]]; then
            echo -e "  暂无执行记录\n"
        fi
    fi

    # ── RTK token 节省统计 ──
    local rtk_cmd=""
    if command -v rtk &>/dev/null; then
        rtk_cmd="rtk"
    elif [[ -x "$TOOLS_DIR/rtk" ]]; then
        rtk_cmd="$TOOLS_DIR/rtk"
    else
        if [[ ! -f "$stats_index" ]]; then
            print_error "RTK 未安装，且无工作流统计"
            print_info "安装 RTK: curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
        fi
        return 1
    fi
    echo -e "${CYAN}RTK Token 压缩统计：${NC}\n"
    "$rtk_cmd" gain
}
