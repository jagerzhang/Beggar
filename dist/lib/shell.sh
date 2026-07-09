#!/bin/bash
# beggar shell integration utilities

# 检测当前 shell 类型
_detect_shell_rc() {
    # Windows Git Bash/MSYS2 环境优先使用 ~/.bashrc
    if [[ -n "${MSYSTEM:-}" ]]; then
        if [[ -f "$HOME/.bashrc" ]]; then
            echo "$HOME/.bashrc"
            return
        fi
    fi
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        *)    echo "" ;;
    esac
}

# 交互式配置 cbc alias
_setup_shell_alias() {
    print_header
    echo -e "配置 CodeBuddy CLI 快速启动别名"
    echo ""
    echo -e "  ${YELLOW}可用参数速览：${NC}"
    echo -e "    -y                           跳过安全权限检查"
    echo -e "    --dangerously-skip-permissions  绕过所有权限检查（仅限沙箱）"
    echo -e "    --permission-mode <mode>        面板权限模式"
    echo -e "    --permission-mode-before-plan   退出计划模式后的权限模式"
    echo -e "    --subagent-permission-mode      子 Agent 权限模式"
    echo ""
    echo -e "选择 codebuddy (cbc) 的启动模式："
    echo ""
    echo -e "  ${GREEN}1)${NC} ${YELLOW}全程自动${NC}     — -y + auto（低风险放行，高风险询问，智能判断，${BOLD}推荐${NC}）"
    echo -e "  ${GREEN}2)${NC} ${YELLOW}跳过安全确认${NC} — -y + acceptEdits（自动接受文件编辑，保留高风险确认）"
    echo -e "  ${GREEN}3)${NC} ${YELLOW}静默拦截${NC}     — -y + dontAsk + --dangerously-skip-permissions（不询问用户，未授权操作直接拦截，仅限沙箱/信任环境）"
    echo -e "  ${GREEN}4)${NC} ${YELLOW}自定义${NC}       — 逐项选择所有参数"
    echo -e "  ${GREEN}0)${NC} ${YELLOW}跳过${NC}         — 稍后手动配置"
    echo ""

    local choice
    read -r -p "  请选择 [1/2/3/4/0] (默认 1): " choice

    local perm_mode subagent_perm before_plan_perm="" use_y="true" skip_perms="false"
    case "${choice:-1}" in
        1)
            perm_mode="auto"
            subagent_perm="auto"
            ;;
        2)
            perm_mode="acceptEdits"
            subagent_perm="acceptEdits"
            ;;
        3)
            perm_mode="dontAsk"
            subagent_perm="acceptEdits"
            skip_perms="true"
            ;;
        4)
            # 自定义选择
            echo ""
            echo -e "  面板权限模式 (--permission-mode)："
            echo -e "    ${GREEN}a)${NC} acceptEdits      — 自动接受编辑（推荐）"
            echo -e "    ${GREEN}b)${NC} dontAsk          — 静默拦截"
            echo -e "    ${GREEN}c)${NC} auto             — 自动判断（低风险放行，高风险询问）"
            echo -e "    ${GREEN}d)${NC} bypassPermissions — 绕过所有权限检查"
            read -r -p "  请选择 [a/b/c/d] (默认 a): " pm_choice
            case "${pm_choice:-a}" in
                a|A) perm_mode="acceptEdits" ;;
                b|B) perm_mode="dontAsk" ;;
                c|C) perm_mode="auto" ;;
                d|D) perm_mode="bypassPermissions" ;;
                *)   perm_mode="acceptEdits" ;;
            esac

            echo ""
            echo -e "  子 Agent 权限模式 (--subagent-permission-mode)："
            echo -e "    ${GREEN}a)${NC} acceptEdits — 自动接受子 Agent 编辑（推荐）"
            echo -e "    ${GREEN}b)${NC} dontAsk     — 静默拦截子 Agent"
            echo -e "    ${GREEN}c)${NC} auto        — 自动判断"
            read -r -p "  请选择 [a/b/c] (默认 a): " sp_choice
            case "${sp_choice:-a}" in
                a|A) subagent_perm="acceptEdits" ;;
                b|B) subagent_perm="dontAsk" ;;
                c|C) subagent_perm="auto" ;;
                *)   subagent_perm="acceptEdits" ;;
            esac

            echo ""
            echo -e "  退出计划模式后的权限 (--permission-mode-before-plan)："
            echo -e "    ${GREEN}a)${NC} 不设置       — 恢复默认行为（推荐）"
            echo -e "    ${GREEN}b)${NC} acceptEdits  — 退出计划模式后自动接受编辑"
            echo -e "    ${GREEN}c)${NC} dontAsk      — 退出计划模式后静默拦截"
            echo -e "    ${GREEN}d)${NC} auto         — 退出计划模式后自动判断"
            read -r -p "  请选择 [a/b/c/d] (默认 a): " bp_choice
            case "${bp_choice:-a}" in
                b|B) before_plan_perm="acceptEdits" ;;
                c|C) before_plan_perm="dontAsk" ;;
                d|D) before_plan_perm="auto" ;;
                *)   before_plan_perm="" ;;
            esac

            echo ""
            read -r -p "  是否添加 -y 参数（跳过安全权限检查）? [Y/n] " y_choice
            if [[ "$y_choice" =~ ^[Nn]$ ]]; then
                use_y="false"
            fi

            echo ""
            read -r -p "  是否添加 --dangerously-skip-permissions（绕过所有权限检查，仅限沙箱）? [y/N] " ds_choice
            if [[ "$ds_choice" =~ ^[Yy]$ ]]; then
                skip_perms="true"
            fi
            ;;
        0)
            print_info "已跳过，可稍后运行 ${YELLOW}beggar setup shell${NC} 配置"
            return 0
            ;;
    esac

    # 构建 aliases (同时覆盖 cbc 和 codebuddy)
    local flags=""
    if [[ "$use_y" == "true" ]]; then
        flags="$flags -y"
    fi
    if [[ "$skip_perms" == "true" ]]; then
        flags="$flags --dangerously-skip-permissions"
    fi
    flags="$flags --permission-mode $perm_mode --subagent-permission-mode $subagent_perm"
    if [[ -n "$before_plan_perm" ]]; then
        flags="$flags --permission-mode-before-plan $before_plan_perm"
    fi

    local cbc_line="alias cbc='cbc $flags'"
    local codebuddy_line="alias codebuddy='codebuddy $flags'"

    echo ""
    echo -e "  生成的 alias："
    echo -e "  ${CYAN}$cbc_line${NC}"
    echo -e "  ${CYAN}$codebuddy_line${NC}"
    echo ""

    local rc_file
    rc_file=$(_detect_shell_rc)
    if [[ -z "$rc_file" ]]; then
        print_warning "未检测到 shell 配置文件，请手动将上述 alias 添加到你的 shell rc 文件"
        return 0
    fi

    read -r -p "  是否写入 $rc_file ? [Y/n] " confirm
    if [[ -z "$confirm" || "$confirm" =~ ^[Yy]$ ]]; then
        local has_cbc has_codebuddy
        has_cbc=$(grep "^alias cbc=" "$rc_file" 2>/dev/null || true)
        has_codebuddy=$(grep "^alias codebuddy=" "$rc_file" 2>/dev/null || true)
        if [[ -n "$has_cbc" || -n "$has_codebuddy" ]]; then
            print_warning "已存在 codebuddy/cbc alias，将覆盖写入"
            [[ -n "$has_cbc" ]] && echo -e "  旧 cbc: $has_cbc"
            [[ -n "$has_codebuddy" ]] && echo -e "  旧 codebuddy: $has_codebuddy"
            _sed_inplace '/^alias cbc=/d' "$rc_file" 2>/dev/null || true
            _sed_inplace '/^alias codebuddy=/d' "$rc_file" 2>/dev/null || true
            rm -f "${rc_file}.bak" 2>/dev/null || true
        fi
        cat >> "$rc_file" <<EOF

# CodeBuddy CLI alias (configured by beggar)
$cbc_line
$codebuddy_line
EOF
        print_success "已写入 $rc_file"
        print_info "执行 ${YELLOW}source $rc_file${NC} 或重新打开终端使其生效"
    else
        print_info "已跳过，可手动执行："
        echo -e "  echo \"$cbc_line\" >> $rc_file"
        echo -e "  echo \"$codebuddy_line\" >> $rc_file"
        print_info "如需生效，执行 ${YELLOW}source $rc_file${NC} 或重新打开终端"
    fi
}

# 向 shell rc 文件注入 beggar() 函数作为 PATH fallback
# 当 ~/.local/bin 不在 PATH 中时（如新安装后当前 session、受限环境），
# shell 函数仍可找到 wrapper 并执行
_inject_beggar_func() {
    local rc_file
    rc_file=$(_detect_shell_rc)
    if [[ -z "$rc_file" ]]; then
        return 0
    fi

    # 幂等：先删除旧的 beggar 函数块（从起始标记到结束标记）
    if grep -q "# beggar shell function (fallback)" "$rc_file" 2>/dev/null; then
        local tmp_rc="${rc_file}.tmp.$$"
        awk '/^# beggar shell function \(fallback\)/{skip=1} skip && /^# end beggar shell function/{skip=0; next} !skip' "$rc_file" > "$tmp_rc" && mv "$tmp_rc" "$rc_file"
    fi

    # 注入新的 beggar 函数
    cat >> "$rc_file" << 'BEGGAR_FUNC_EOF'

# beggar shell function (fallback)
# 当 ~/.local/bin 不在 PATH 中时，通过 shell 函数调用 wrapper
beggar() {
    if [[ -x "$HOME/.local/bin/beggar" ]]; then
        "$HOME/.local/bin/beggar" "$@"
        return $?
    fi
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.codebuddy/setup.sh" ]]; then
            bash "$dir/.codebuddy/setup.sh" "$@"
            return $?
        fi
        dir="$(dirname "$dir")"
    done
    if [[ -f "$HOME/.codebuddy/setup.sh" ]]; then
        bash "$HOME/.codebuddy/setup.sh" "$@"
        return $?
    fi
    echo "beggar: no .codebuddy/setup.sh found (try running 'beggar install' first)" >&2
    return 1
}
# end beggar shell function
BEGGAR_FUNC_EOF
}