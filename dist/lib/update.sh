#!/bin/bash
# Beggar · update | diff + 从 mirrors 下载并干净重装 beggar

# diff: 显示当前配置 vs 指定预设的差异
do_diff() {
    local preset_name="${1:-balanced}"
    print_header
    echo -e "当前配置 vs 预设 ${YELLOW}${preset_name}${NC}：\n"

    "$PYTHON_CMD" -c "
import json
with open('$MODELS_FILE') as f:
    data = json.load(f)
preset = data.get('presets', {}).get('$preset_name')
if not preset:
    print('错误：预设不存在')
    exit(1)

import re, os
agents = ['architect', 'coder-senior', 'coder-standard', 'coder-lite', 'reviewer', 'tester', 'recorder']
print(f'  {\"Agent\":<12} │ {\"Current\":<28} │ {\"Preset\":<28} │ Diff')
print('  ' + '─' * 86)
for agent in agents:
    f = '$AGENTS_DIR/' + agent + '.md'
    cur = '?'
    if os.path.exists(f):
        for line in open(f):
            m = re.match(r'^model:\s*(.+)\$', line.strip())
            if m:
                cur = m.group(1)
                break
    target = preset['config'].get(agent, '?')
    diff = '✓ same' if cur == target else '✗ DIFF'
    print(f'  {agent:<12} │ {cur:<28} │ {target:<28} │ {diff}')
"
    echo ""
}

# update: 从 mirrors 下载并干净重装 beggar（解决增量更新残留问题）
do_update() {
    print_header
    print_info "检查系统依赖..."
    local missing_deps=()
    if ! command -v curl &>/dev/null; then missing_deps+=("curl"); fi
    if ! command -v tar &>/dev/null; then missing_deps+=("tar"); fi
    if command -v sha256sum &>/dev/null; then
        local sha256_cmd="sha256sum"
    elif command -v shasum &>/dev/null; then
        local sha256_cmd="shasum -a 256"
    else
        missing_deps+=("sha256sum 或 shasum")
    fi
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "缺少必要的依赖: ${missing_deps[*]}"
    fi
    print_success "依赖检查通过"

    # 获取本地版本
    local local_version="unknown"
    if [[ -f "$CODEBUDDY_DIR/VERSION" ]]; then
        local_version=$(cat "$CODEBUDDY_DIR/VERSION" | head -1 | tr -d '\n')
        print_success "当前版本: $local_version"
    else
        print_warning "未找到 VERSION 文件"
    fi

    # 获取远程最新版本
    print_info "获取远程最新版本..."
    local latest_json
    latest_json=$(curl -fsSL "https://api.github.com/repos/jagerzhang/beggar/releases/latest") || \
        print_error "无法获取远程版本信息"

    local remote_version download_url expected_sha256 release_date
    remote_version=$(echo "$latest_json" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"v\([^"]*\)"/\1/')
    download_url=$(echo "$latest_json" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*beggar-v[^"]*\.tar\.gz"' | head -1 | cut -d'"' -f4)
    expected_sha256=$(echo "$latest_json" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.sha256"' | head -1 | cut -d'"' -f4)
    if [[ -n "$expected_sha256" ]]; then
        expected_sha256=$(curl -fsSL "$expected_sha256" | cut -d' ' -f1)
    fi
    release_date=$(echo "$latest_json" | grep -o '"published_at"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$remote_version" || -z "$download_url" || -z "$expected_sha256" ]]; then
        print_error "远程版本信息格式错误"
    fi
    print_success "远程最新版本: $remote_version (发布于 $release_date)"

    # 语义化版本比较（纯数字，忽略 pre-release 后缀）
    _semver_cmp() {
        local a="${1%%-*}" b="${2%%-*}"
        [[ "$a" == "$b" ]] && return 0
        local IFS=.
        local i=1
        for v in $a; do
            local bv
            bv=$(echo "$b" | cut -d. -f$i)
            [[ "$v" -gt "$bv" ]] && return 2
            [[ "$v" -lt "$bv" ]] && return 1
            ((i++))
        done
        return 0
    }

    # 检查是否需要更新
    if [[ "$local_version" == "$remote_version" ]]; then
        print_success "当前已是最新版本 ($local_version)，无需更新"
        return 0
    fi

    local cmp_rc=0
    _semver_cmp "$local_version" "$remote_version" || cmp_rc=$?
    if [[ "$cmp_rc" == "2" ]]; then
        print_warning "当前版本 ($local_version) 已高于远程最新版本 ($remote_version)"
        print_info "远程版本已回退，更新将安装 v$remote_version"
    else
        print_info "发现新版本: $local_version → $remote_version"
    fi

    # 确认更新
    cat << EOF

更新信息:
  - 当前版本:  $local_version
  - 最新版本:  $remote_version
  - 发布日期:  $release_date

更新策略:
  - 备份用户文件（local/、memory/、user-models.json、persona-active.json、settings.json）
  - 删除所有 beggar 管理文件（彻底清除残留）
  - 安装新版本 → 恢复用户文件 → 重新初始化
  - 等价于"重装"，不会留下重命名/删除后残留的旧文件

EOF
    echo -n "是否继续更新？(y/N): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "更新已取消"
        return 0
    fi

    # 下载并校验
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t beggar)
    # Windows Git Bash/MSYS2: 转换路径格式供 curl 等原生 Windows 程序使用
    if [[ -n "${MSYSTEM:-}" ]] && command -v cygpath &>/dev/null; then
        tmp_dir=$(cygpath -m "$tmp_dir")
    fi
    local temp_download="$tmp_dir/beggar-v$remote_version.tar.gz"
    local temp_extract="$tmp_dir/extract"

    print_info "下载 beggar v$remote_version..."
    if ! curl -fL --progress-bar --retry 3 --retry-delay 2 -o "$temp_download" "$download_url"; then
        rm -rf "$tmp_dir"
        print_error "下载失败"
    fi
    print_success "下载完成"

    print_info "验证文件完整性..."
    local actual_sha256
    if [[ "$sha256_cmd" == "sha256sum" ]]; then
        actual_sha256=$(sha256sum "$temp_download" | cut -d' ' -f1)
    else
        actual_sha256=$(shasum -a 256 "$temp_download" | cut -d' ' -f1)
    fi
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        rm -rf "$tmp_dir"
        print_error "SHA256 校验失败"
    fi
    print_success "SHA256 校验通过"

    # 解压
    mkdir -p "$temp_extract"
    if ! tar xzf "$temp_download" -C "$temp_extract"; then
        rm -rf "$tmp_dir"
        print_error "解压失败"
    fi

    # 干净重装：备份用户文件 → 清理旧版本 → 解压新版本 → 恢复用户文件
    print_info "备份用户自定义文件..."
    local user_backup
    user_backup=$(mktemp -d 2>/dev/null || mktemp -d -t beggar)
    if [[ -n "${MSYSTEM:-}" ]] && command -v cygpath &>/dev/null; then
        user_backup=$(cygpath -m "$user_backup")
    fi
    local user_dirs=("local" "memory")
    local user_files=("user-models.json" "persona-active.json" "notify.json")

    # 备份 settings.json（如存在，用户可能对其有自定义修改）
    if [[ -f "$CODEBUDDY_DIR/settings.json" ]]; then
        cp -p "$CODEBUDDY_DIR/settings.json" "$user_backup/settings.json"
    fi

    for dir in "${user_dirs[@]}"; do
        if [[ -d "$CODEBUDDY_DIR/$dir" ]]; then
            cp -r "$CODEBUDDY_DIR/$dir" "$user_backup/$dir" 2>/dev/null || true
        fi
    done
    for file in "${user_files[@]}"; do
        if [[ -f "$CODEBUDDY_DIR/$file" ]]; then
            cp -p "$CODEBUDDY_DIR/$file" "$user_backup/$file" 2>/dev/null || true
        fi
    done
    print_success "备份完成"

    print_info "清理旧版本文件..."
    # 只删除 beggar 管理的文件/目录，保护用户自定义内容
    # 匹配 do_uninstall() 的分类逻辑

    # agents/ — 只删除 beggar 定义的 agent 文件
    local beggar_agents=("architect" "coder-senior" "coder-standard" "coder-lite" "reviewer" "reviewer-b" "tester" "recorder" "goal-evaluator")
    for agent in "${beggar_agents[@]}"; do
        rm -f "$CODEBUDDY_DIR/agents/${agent}.md"
    done
    # 清理空的 agents 目录
    rmdir "$CODEBUDDY_DIR/agents" 2>/dev/null || true

    # rules/ — 只删除 beggar- 前缀的规则文件
    if [[ -d "$CODEBUDDY_DIR/rules" ]]; then
        for rule_file in "$CODEBUDDY_DIR/rules"/beggar-*; do
            [[ -e "$rule_file" ]] || continue
            rm -f "$rule_file"
        done
    fi

    # commands/ — 只删除 beggar 管理的子目录
    for cmd_dir in beggar dev opsx; do
        rm -rf "$CODEBUDDY_DIR/commands/$cmd_dir"
    done
    # 清理空的 commands 目录
    rmdir "$CODEBUDDY_DIR/commands" 2>/dev/null || true

    # skills/ — 只删除 beggar 管理的 skill 目录
    for skill_dir in beggar-notify beggar-workflow dev-workflow openspec-apply-change openspec-archive-change openspec-explore openspec-propose; do
        rm -rf "$CODEBUDDY_DIR/skills/$skill_dir"
    done
    # 清理空的 skills 目录
    rmdir "$CODEBUDDY_DIR/skills" 2>/dev/null || true

    # tools/ — 删除旧版 rtk 二进制（新版本不再打包本地 rtk）
    if [[ -d "$CODEBUDDY_DIR/tools" ]]; then
        find "$CODEBUDDY_DIR/tools" -maxdepth 1 -name 'rtk-*' -type f -delete 2>/dev/null || true
        # 清理空的 tools 目录（仅保留 .gitkeep）
        find "$CODEBUDDY_DIR/tools" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
        rmdir "$CODEBUDDY_DIR/tools" 2>/dev/null || true
    fi

    # 删除 beggar 管理的顶层文件
    local managed_files=(
        "beggar-models.json" "personas.json" "setup.sh"
        "PERSONAS.md" "MODEL_SELECTION.md"
        "VERSION" "latest.json" ".gitignore" ".beggar-checksums"
    )
    for file in "${managed_files[@]}"; do
        rm -f "$CODEBUDDY_DIR/$file"
    done

    # 清理旧版 models.json 残留（v2.9.0 前的文件名，已改为 beggar-models.json）
    # 仅当文件存在且为 beggar 格式时删除，避免误删 CodeBuddy 官方配置
    local legacy_models="$CODEBUDDY_DIR/models.json"
    if _is_beggar_models_json "$legacy_models"; then
        rm -f "$legacy_models"
        print_info "已清理旧版 models.json（已迁移至 beggar-models.json）"
    fi

    print_success "清理完成"

    print_info "安装新版本文件..."
    cp -r "$temp_extract"/* "$CODEBUDDY_DIR/"

    # 同步 beggar-state.py 到 skills 目录（保持 lib/ 和 skills/ 副本一致）
    if [[ -f "$CODEBUDDY_DIR/lib/beggar_state.py" ]]; then
        cp -p "$CODEBUDDY_DIR/lib/beggar_state.py" "$CODEBUDDY_DIR/skills/beggar-workflow/beggar-state.py" 2>/dev/null || true
    fi

    print_success "安装完成"

    # 重建 .beggar-checksums 文件清单（从解压目录遍历，确保只记录包内文件）
    local _checksums_file="$CODEBUDDY_DIR/.beggar-checksums"
    : > "$_checksums_file"
    local _find_manifest
    _find_manifest=$(mktemp 2>/dev/null || mktemp -t beggar_manifest)
    find "$temp_extract" -type f -print0 > "$_find_manifest"
    while IFS= read -r -d '' _src_file; do
        local _rel_path="${_src_file#"$temp_extract"/}"
        if ! _is_biz_only_on_missing "$_rel_path"; then
            echo "file:$_rel_path INSTALLED" >> "$_checksums_file"
        fi
    done < "$_find_manifest"
    rm -f "$_find_manifest"

    print_info "恢复用户自定义文件..."
    for dir in "${user_dirs[@]}"; do
        if [[ -d "$user_backup/$dir" ]]; then
            rm -rf "${CODEBUDDY_DIR:?}/${dir}" 2>/dev/null || true
            cp -r "$user_backup/$dir" "$CODEBUDDY_DIR/$dir"
        fi
    done
    for file in "${user_files[@]}"; do
        if [[ -f "$user_backup/$file" ]]; then
            cp -p "$user_backup/$file" "$CODEBUDDY_DIR/$file"
        fi
    done
    # 恢复 settings.json：保持用户原有的配置内容，init 会处理 superpowers 注入
    if [[ -f "$user_backup/settings.json" ]]; then
        cp -p "$user_backup/settings.json" "$CODEBUDDY_DIR/settings.json"
    fi

    rm -rf "$user_backup"
    print_success "用户文件已恢复"

    # 迁移旧 hy3 模型 ID → hy3（v2.8.4 统一 CLI/IDE 模型 ID）
    if [[ -f "$CODEBUDDY_DIR/beggar-models.json" ]]; then
        sed -i.bak 's/hy3-preview-agent/hy3/g' "$CODEBUDDY_DIR/beggar-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/beggar-models.json.bak" 2>/dev/null
    fi
    if [[ -d "$CODEBUDDY_DIR/agents" ]]; then
        for md_file in "$CODEBUDDY_DIR/agents"/*.md; do
            [[ -e "$md_file" ]] || continue
            sed -i.bak 's/hy3-preview-agent/hy3/g' "$md_file" 2>/dev/null
            rm -f "${md_file}.bak" 2>/dev/null
        done
    fi
    # user-models.json 中可能有旧 ID 覆盖
    if [[ -f "$CODEBUDDY_DIR/user-models.json" ]]; then
        sed -i.bak 's/hy3-preview-agent/hy3/g' "$CODEBUDDY_DIR/user-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/user-models.json.bak" 2>/dev/null
    fi

    # 迁移 kimi-k2.6 → kimi-k2.7（v2.8.5 编程专用强化版）
    if [[ -f "$CODEBUDDY_DIR/beggar-models.json" ]]; then
        sed -i.bak 's/kimi-k2.6/kimi-k2.7/g' "$CODEBUDDY_DIR/beggar-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/beggar-models.json.bak" 2>/dev/null
    fi
    if [[ -d "$CODEBUDDY_DIR/agents" ]]; then
        for md_file in "$CODEBUDDY_DIR/agents"/*.md; do
            [[ -e "$md_file" ]] || continue
            sed -i.bak 's/kimi-k2.6/kimi-k2.7/g' "$md_file" 2>/dev/null
            rm -f "${md_file}.bak" 2>/dev/null
        done
    fi
    if [[ -f "$CODEBUDDY_DIR/user-models.json" ]]; then
        sed -i.bak 's/kimi-k2.6/kimi-k2.7/g' "$CODEBUDDY_DIR/user-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/user-models.json.bak" 2>/dev/null
    fi

    # 设置执行权限
    chmod +x "$CODEBUDDY_DIR/setup.sh" 2>/dev/null || true

    # 运行初始化
    print_info "运行初始化脚本..."
    if cd "$CODEBUDDY_DIR" && BEGGAR_GLOBAL="$BEGGAR_GLOBAL" ./setup.sh init; then
        print_success "初始化完成"
    else
        print_warning "初始化脚本执行失败"
    fi

    cat << EOF

${GREEN}════════════════════════════════════════════${NC}
${GREEN}  更新成功！${NC}
${GREEN}════════════════════════════════════════════${NC}

版本:    beggar v$local_version → v$remote_version
目录:    $CODEBUDDY_DIR

用户自定义内容已保留:
  - local/          （用户自定义扩展）
  - memory/         （用户记忆）
  - user-models.json（用户模型覆盖）

后续操作:
  1. 查看配置:   ${CYAN}.codebuddy/setup.sh show${NC}
  2. 验证配置:   ${CYAN}.codebuddy/setup.sh validate${NC}
  3. 切换角色:   ${CYAN}.codebuddy/setup.sh persona list${NC}

EOF
    print_success "更新完成"

    # 必须 exit：update 过程中 setup.sh 自身已被新版覆盖，
    # 旧 shell 进程继续执行会遇到新代码的语法不兼容问题。
    exit 0
}

# reinstall: 强制重新安装当前版本（跳过版本检查，等价于"就地重装"）
# 适用于：配置损坏修复、排查问题、强制刷新文件等场景
do_reinstall() {
    print_header
    print_info "强制重新安装（跳过版本检查）..."

    # 获取本地版本
    local local_version="unknown"
    if [[ -f "$CODEBUDDY_DIR/VERSION" ]]; then
        local_version=$(cat "$CODEBUDDY_DIR/VERSION" | head -1 | tr -d '\n')
        print_success "当前版本: $local_version"
    else
        print_warning "未找到 VERSION 文件，将安装远程最新版本"
    fi

    # 获取远程版本信息（直接使用，不做版本比较）
    print_info "获取远程版本信息..."
    local latest_json
    latest_json=$(curl -fsSL "https://api.github.com/repos/jagerzhang/beggar/releases/latest") || \
        print_error "无法获取远程版本信息"

    local remote_version download_url expected_sha256 release_date
    remote_version=$(echo "$latest_json" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"v\([^"]*\)"/\1/')
    download_url=$(echo "$latest_json" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*beggar-v[^"]*\.tar\.gz"' | head -1 | cut -d'"' -f4)
    expected_sha256=$(echo "$latest_json" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.sha256"' | head -1 | cut -d'"' -f4)
    if [[ -n "$expected_sha256" ]]; then
        expected_sha256=$(curl -fsSL "$expected_sha256" | cut -d' ' -f1)
    fi
    release_date=$(echo "$latest_json" | grep -o '"published_at"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$remote_version" || -z "$download_url" || -z "$expected_sha256" ]]; then
        print_error "远程版本信息格式错误"
    fi
    print_success "远程版本: $remote_version (发布于 $release_date)"

    cat << EOF

重装信息:
  - 当前版本:  $local_version
  - 重装版本:  $remote_version
  - 发布日期:  $release_date

重装策略:
  - 备份用户文件（local/、memory/、user-models.json、persona-active.json、settings.json）
  - 删除所有 beggar 管理文件（彻底清除残留）
  - 安装版本 → 恢复用户文件 → 重新初始化
  - 跳过版本检查，强制重装

EOF
    echo -n "是否继续重装？(y/N): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "重装已取消"
        return 0
    fi

    # 下载并校验
    local tmp_dir
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t beggar)
    if [[ -n "${MSYSTEM:-}" ]] && command -v cygpath &>/dev/null; then
        tmp_dir=$(cygpath -m "$tmp_dir")
    fi
    local temp_download="$tmp_dir/beggar-v$remote_version.tar.gz"
    local temp_extract="$tmp_dir/extract"

    print_info "下载 beggar v$remote_version..."
    if ! curl -fL --progress-bar --retry 3 --retry-delay 2 -o "$temp_download" "$download_url"; then
        rm -rf "$tmp_dir"
        print_error "下载失败"
    fi
    print_success "下载完成"

    print_info "验证文件完整性..."
    local sha256_cmd
    if command -v sha256sum &>/dev/null; then
        sha256_cmd="sha256sum"
    else
        sha256_cmd="shasum -a 256"
    fi
    local actual_sha256
    if [[ "$sha256_cmd" == "sha256sum" ]]; then
        actual_sha256=$(sha256sum "$temp_download" | cut -d' ' -f1)
    else
        actual_sha256=$(shasum -a 256 "$temp_download" | cut -d' ' -f1)
    fi
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
        rm -rf "$tmp_dir"
        print_error "SHA256 校验失败"
    fi
    print_success "SHA256 校验通过"

    # 解压
    mkdir -p "$temp_extract"
    if ! tar xzf "$temp_download" -C "$temp_extract"; then
        rm -rf "$tmp_dir"
        print_error "解压失败"
    fi

    # 干净重装：备份用户文件 → 清理旧版本 → 解压新版本 → 恢复用户文件
    print_info "备份用户自定义文件..."
    local user_backup
    user_backup=$(mktemp -d 2>/dev/null || mktemp -d -t beggar)
    if [[ -n "${MSYSTEM:-}" ]] && command -v cygpath &>/dev/null; then
        user_backup=$(cygpath -m "$user_backup")
    fi
    local user_dirs=("local" "memory")
    local user_files=("user-models.json" "persona-active.json" "notify.json")

    if [[ -f "$CODEBUDDY_DIR/settings.json" ]]; then
        cp -p "$CODEBUDDY_DIR/settings.json" "$user_backup/settings.json"
    fi

    for dir in "${user_dirs[@]}"; do
        if [[ -d "$CODEBUDDY_DIR/$dir" ]]; then
            cp -r "$CODEBUDDY_DIR/$dir" "$user_backup/$dir" 2>/dev/null || true
        fi
    done
    for file in "${user_files[@]}"; do
        if [[ -f "$CODEBUDDY_DIR/$file" ]]; then
            cp -p "$CODEBUDDY_DIR/$file" "$user_backup/$file" 2>/dev/null || true
        fi
    done
    print_success "备份完成"

    print_info "清理旧版本文件..."
    local beggar_agents=("architect" "coder-senior" "coder-standard" "coder-lite" "reviewer" "reviewer-b" "tester" "recorder" "goal-evaluator")
    for agent in "${beggar_agents[@]}"; do
        rm -f "$CODEBUDDY_DIR/agents/${agent}.md"
    done
    rmdir "$CODEBUDDY_DIR/agents" 2>/dev/null || true

    if [[ -d "$CODEBUDDY_DIR/rules" ]]; then
        for rule_file in "$CODEBUDDY_DIR/rules"/beggar-*; do
            [[ -e "$rule_file" ]] || continue
            rm -f "$rule_file"
        done
    fi

    for cmd_dir in beggar dev opsx; do
        rm -rf "$CODEBUDDY_DIR/commands/$cmd_dir"
    done
    rmdir "$CODEBUDDY_DIR/commands" 2>/dev/null || true

    for skill_dir in beggar-notify beggar-workflow dev-workflow openspec-apply-change openspec-archive-change openspec-explore openspec-propose; do
        rm -rf "$CODEBUDDY_DIR/skills/$skill_dir"
    done
    rmdir "$CODEBUDDY_DIR/skills" 2>/dev/null || true

    if [[ -d "$CODEBUDDY_DIR/tools" ]]; then
        find "$CODEBUDDY_DIR/tools" -maxdepth 1 -name 'rtk-*' -type f -delete 2>/dev/null || true
        find "$CODEBUDDY_DIR/tools" -mindepth 1 ! -name '.gitkeep' -delete 2>/dev/null || true
        rmdir "$CODEBUDDY_DIR/tools" 2>/dev/null || true
    fi

    local managed_files=(
        "beggar-models.json" "personas.json" "setup.sh"
        "PERSONAS.md" "MODEL_SELECTION.md"
        "VERSION" "latest.json" ".gitignore" ".beggar-checksums"
    )
    for file in "${managed_files[@]}"; do
        rm -f "$CODEBUDDY_DIR/$file"
    done

    local legacy_models="$CODEBUDDY_DIR/models.json"
    if _is_beggar_models_json "$legacy_models"; then
        rm -f "$legacy_models"
        print_info "已清理旧版 models.json"
    fi

    print_success "清理完成"

    print_info "安装新版本文件..."
    cp -r "$temp_extract"/* "$CODEBUDDY_DIR/"

    # 同步 beggar-state.py 到 skills 目录（保持 lib/ 和 skills/ 副本一致）
    if [[ -f "$CODEBUDDY_DIR/lib/beggar_state.py" ]]; then
        cp -p "$CODEBUDDY_DIR/lib/beggar_state.py" "$CODEBUDDY_DIR/skills/beggar-workflow/beggar-state.py" 2>/dev/null || true
    fi

    print_success "安装完成"

    # 重建 .beggar-checksums 文件清单（从解压目录遍历，确保只记录包内文件）
    local _checksums_file="$CODEBUDDY_DIR/.beggar-checksums"
    : > "$_checksums_file"
    local _find_manifest
    _find_manifest=$(mktemp 2>/dev/null || mktemp -t beggar_manifest)
    find "$temp_extract" -type f -print0 > "$_find_manifest"
    while IFS= read -r -d '' _src_file; do
        local _rel_path="${_src_file#"$temp_extract"/}"
        if ! _is_biz_only_on_missing "$_rel_path"; then
            echo "file:$_rel_path INSTALLED" >> "$_checksums_file"
        fi
    done < "$_find_manifest"
    rm -f "$_find_manifest"

    print_info "恢复用户自定义文件..."
    for dir in "${user_dirs[@]}"; do
        if [[ -d "$user_backup/$dir" ]]; then
            rm -rf "${CODEBUDDY_DIR:?}/${dir}" 2>/dev/null || true
            cp -r "$user_backup/$dir" "$CODEBUDDY_DIR/$dir"
        fi
    done
    for file in "${user_files[@]}"; do
        if [[ -f "$user_backup/$file" ]]; then
            cp -p "$user_backup/$file" "$CODEBUDDY_DIR/$file"
        fi
    done
    if [[ -f "$user_backup/settings.json" ]]; then
        cp -p "$user_backup/settings.json" "$CODEBUDDY_DIR/settings.json"
    fi

    rm -rf "$user_backup"
    print_success "用户文件已恢复"

    # 迁移旧 hy3 模型 ID
    if [[ -f "$CODEBUDDY_DIR/beggar-models.json" ]]; then
        sed -i.bak 's/hy3-preview-agent/hy3/g' "$CODEBUDDY_DIR/beggar-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/beggar-models.json.bak" 2>/dev/null
    fi
    if [[ -d "$CODEBUDDY_DIR/agents" ]]; then
        for md_file in "$CODEBUDDY_DIR/agents"/*.md; do
            [[ -e "$md_file" ]] || continue
            sed -i.bak 's/hy3-preview-agent/hy3/g' "$md_file" 2>/dev/null
            rm -f "${md_file}.bak" 2>/dev/null
        done
    fi
    if [[ -f "$CODEBUDDY_DIR/user-models.json" ]]; then
        sed -i.bak 's/hy3-preview-agent/hy3/g' "$CODEBUDDY_DIR/user-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/user-models.json.bak" 2>/dev/null
    fi

    # 迁移 kimi-k2.6 → kimi-k2.7（v2.8.5 编程专用强化版）
    if [[ -f "$CODEBUDDY_DIR/beggar-models.json" ]]; then
        sed -i.bak 's/kimi-k2.6/kimi-k2.7/g' "$CODEBUDDY_DIR/beggar-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/beggar-models.json.bak" 2>/dev/null
    fi
    if [[ -d "$CODEBUDDY_DIR/agents" ]]; then
        for md_file in "$CODEBUDDY_DIR/agents"/*.md; do
            [[ -e "$md_file" ]] || continue
            sed -i.bak 's/kimi-k2.6/kimi-k2.7/g' "$md_file" 2>/dev/null
            rm -f "${md_file}.bak" 2>/dev/null
        done
    fi
    if [[ -f "$CODEBUDDY_DIR/user-models.json" ]]; then
        sed -i.bak 's/kimi-k2.6/kimi-k2.7/g' "$CODEBUDDY_DIR/user-models.json" 2>/dev/null
        rm -f "$CODEBUDDY_DIR/user-models.json.bak" 2>/dev/null
    fi

    rm -rf "$tmp_dir"

    chmod +x "$CODEBUDDY_DIR/setup.sh" 2>/dev/null || true

    print_info "运行初始化脚本..."
    if cd "$CODEBUDDY_DIR" && BEGGAR_GLOBAL="$BEGGAR_GLOBAL" ./setup.sh init; then
        print_success "初始化完成"
    else
        print_warning "初始化脚本执行失败"
    fi

    cat << EOF

${GREEN}════════════════════════════════════════════${NC}
${GREEN}  重装成功！${NC}
${GREEN}════════════════════════════════════════════${NC}

版本:    beggar v$local_version → v$remote_version (reinstall)
目录:    $CODEBUDDY_DIR

用户自定义内容已保留:
  - local/          （用户自定义扩展）
  - memory/         （用户记忆）
  - user-models.json（用户模型覆盖）

EOF
    print_success "重装完成"

    exit 0
}
