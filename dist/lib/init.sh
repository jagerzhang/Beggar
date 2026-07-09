#!/bin/bash
# Beggar init module
#
# Provides:
#   _check_codebuddy_workspace()  - verify environment is a CodeBuddy workspace
#   do_init()                     - full initialization workflow (Steps 1-7)
#
# Dependencies (sourced by caller):
#   colors.sh       - print_* helpers
#   utils.sh        - _global_has_beggar_hooks
#   platform.sh     - detect_platform
#   models.sh       - setup_preset, _check_leader_model
#   rtk.sh          - _install_rtk
#   notify.sh       - _configure_notify
#   CODEBUDDY_DIR, AGENTS_DIR, MODELS_FILE, PROJECT_DIR, BEGGAR_GLOBAL

# ─── Workspace detection ────────────────────────────────────────────────
# 原 setup.sh L854-933

_check_codebuddy_workspace() {
    # 全局安装模式：跳过工作区检查（安装到用户 home 目录）
    if [[ "$BEGGAR_GLOBAL" == "1" ]]; then
        print_info "全局安装模式，跳过工作区检查"
        return 0
    fi

    local project_dir="$PROJECT_DIR"
    local has_cli=false
    local has_project=false

    # 检查 1: 父目录中存在 .codebuddy/settings.*.json（CodeBuddy 已在此目录运行过）
    local parent_dir="$project_dir"
    while [[ "$parent_dir" != "/" ]]; do
        if [[ -f "$parent_dir/.codebuddy/settings.local.json" ]] || [[ -f "$parent_dir/.codebuddy/settings.json" ]]; then
            has_project=true
            break
        fi
        parent_dir="$(dirname "$parent_dir")"
    done

    # 检查 3: cbc/codebuddy CLI 命令存在
    if command -v codebuddy &>/dev/null || command -v cbc &>/dev/null; then
        has_cli=true
    fi

    # CLI 未安装时，提示用户是否安装
    if [[ "$has_cli" != "true" ]]; then
        print_warning "未检测到 CodeBuddy Code CLI (codebuddy 或 cbc 命令)"
        print_info "beggar 依赖 CodeBuddy Code 运行环境"
        echo ""
        read -p "是否安装 CodeBuddy Code? (Y/n): " install_cli
        if [[ "$install_cli" =~ ^[Yy]$ ]] || [[ -z "$install_cli" ]]; then
            echo ""
            print_info "正在执行: npm install -g @tencent-ai/codebuddy-code"
            if npm install -g @tencent-ai/codebuddy-code; then
                print_success "CodeBuddy Code 安装完成"
                has_cli=true
            else
                print_error "安装失败，请手动执行: npm install -g @tencent-ai/codebuddy-code"
            fi
            echo ""
        fi
    fi

    # 如果 CLI 和项目特征都没有，发出警告
    if [[ "$has_cli" != "true" ]] && [[ "$has_project" != "true" ]]; then
        print_warning "═══════════════════════════════════════════════════"
        print_warning "  未检测到 CodeBuddy Code 工作区特征"
        print_warning "═══════════════════════════════════════════════════"
        print_warning ""
        print_warning "  当前安装目录: $project_dir"
        print_warning ""
        print_warning "  beggar 是 CodeBuddy Code 的多 Agent 研发配置套件，"
        print_warning "  需要安装到 CodeBuddy Code 的执行工作目录中。"
        print_warning ""
        print_warning "  典型安装位置："
        print_warning "    cd your-code-project     # 你的代码项目根目录"
        print_warning "    curl ... | bash            # 在此目录执行安装脚本"
        print_warning ""
        read -p "  确认在当前目录继续安装? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo ""
            print_info "已取消安装。请切换到 CodeBuddy Code 工作目录后重试。"
            print_info "提示: 可以先运行 'codebuddy' 在目标目录进入交互模式，"
            print_info "      退出后再执行安装脚本。"
            exit 0
        fi
        echo ""
        print_info "已确认，继续在当前目录安装..."
        echo ""
    fi
}

# ─── 旧版 models.json 迁移 ──────────────────────────────────────────────
# v2.9.0 前 beggar 使用 models.json，与 CodeBuddy 官方同名配置冲突。
# 检测旧版文件并重命名为 beggar-models.json，保留用户自定义内容。
_migrate_legacy_models_json() {
    local old_file="$CODEBUDDY_DIR/models.json"
    local new_file="$CODEBUDDY_DIR/beggar-models.json"

    if [[ ! -f "$old_file" ]]; then
        return 0
    fi

    # 使用共享函数检测是否为 beggar 格式（包含 presets 或 aliases 键）
    if _is_beggar_models_json "$old_file"; then
        if [[ -f "$new_file" ]]; then
            # 新文件已存在（update 已安装），旧文件是残留，直接删除
            rm -f "$old_file"
            print_info "已清理旧版 models.json 残留（已迁移至 beggar-models.json）"
        else
            # 新文件不存在，旧文件是 beggar 的，执行迁移
            mv "$old_file" "$new_file"
            print_info "已迁移 models.json → beggar-models.json（避免与 CodeBuddy 官方配置冲突）"
        fi
    else
        # 不是 beggar 格式，是 CodeBuddy 官方配置或未知文件，不触碰
        print_info "检测到非 beggar 格式的 models.json（CodeBuddy 官方配置），保留不动"
    fi

    # 项目隔离模式：同时检查 home 目录全局 fallback 路径
    if [[ "$BEGGAR_PROJECT_MODE" == "1" ]]; then
        local home_old_file="$HOME/.codebuddy/models.json"
        local home_new_file="$HOME/.codebuddy/beggar-models.json"
        if [[ -f "$home_old_file" ]] && _is_beggar_models_json "$home_old_file"; then
            if [[ -f "$home_new_file" ]]; then
                rm -f "$home_old_file"
                print_info "已清理全局旧版 models.json 残留（~/.codebuddy/）"
            else
                mv "$home_old_file" "$home_new_file"
                print_info "已迁移全局 models.json → beggar-models.json（~/.codebuddy/）"
            fi
        fi
    fi
}

# ─── Initialization workflow ────────────────────────────────────────────
# 原 setup.sh L1056-1595 (完整)

do_init() {
    _check_codebuddy_workspace

    "$PYTHON_CMD" "$LIB_DIR/banner.py"

    # 迁移旧版 models.json → beggar-models.json（避免与 CodeBuddy 官方同名配置冲突）
    _migrate_legacy_models_json

    # Step 1: 安装 RTK（非阻塞，仅尝试在线安装）
    print_info "Step 1/7: 安装 RTK Token 压缩工具（可选）"
    _install_rtk
    echo ""

    # Step 2: 应用默认 Agent 预设（自动选择适合平台的预设）
    local init_platform
    init_platform=$(detect_platform)
    print_info "Step 2/7: 应用默认 Agent 预设（检测平台: $init_platform）"
    setup_preset "balanced" 2>/dev/null
    # 检测 Leader 模型一致性并询问自动切换
    _check_leader_model "balanced" --auto-switch
    echo ""

    # 项目隔离模式：全局已处理 hooks/superpowers/settings，项目只需 persona + notify
    if [[ "$BEGGAR_PROJECT_MODE" == "1" ]]; then
        print_info "项目隔离模式 — 模型/规则/hooks 均复用全局 ~/.codebuddy/"
        print_info "如需自定义:"
        print_info "  模型: ${CYAN}beggar --project agent preset <name>${NC}"
        print_info "  角色: ${CYAN}beggar --project persona <theme>${NC}"
        echo ""

        # 检查全局通知配置
        local global_notify="$HOME/.codebuddy/notify.json"
        if [[ -f "$global_notify" ]]; then
            local global_sendto
            global_sendto=$(GLOBAL_NOTIFY_FILE="$global_notify" "$PYTHON_CMD" -c "
import json, os
with open(os.environ['GLOBAL_NOTIFY_FILE']) as f:
    d = json.load(f)
print(d.get('sendTo', '未知'))
" 2>/dev/null)
            print_info "检测到全局通知配置，接收人: $global_sendto"
            if [[ ! -f "$CODEBUDDY_DIR/notify.json" ]]; then
                echo -n "是否使用项目独立通知配置？(y/N): "
                if read -r choice </dev/tty 2>/dev/null && [[ "$choice" =~ ^[Yy]$ ]]; then
                    _configure_notify
                fi
            fi
        else
            _configure_notify
        fi

        echo ""
        echo -e "${GREEN}════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  初始化完成！${NC}"
        echo -e "${GREEN}════════════════════════════════════════════${NC}"
        echo ""
        echo -e "  配置目录:  $CODEBUDDY_DIR"
        echo -e "  全局配置:  ~/.codebuddy/"
        echo ""
        echo -e "  后续操作:"
        echo -e "    运行 ${CYAN}beggar --project show${NC} 查看项目配置"
        echo -e "    运行 ${CYAN}beggar --project agent preset economic${NC} 切换预设"
        echo -e "    运行 ${CYAN}beggar --project persona <theme>${NC} 切换角色"
        echo ""
        return 0
    fi

    # Step 3: 检测 Superpowers 插件配置
    echo ""
    print_info "Step 3/7: 检测 Superpowers 插件"
    local superpowers_enabled=false
    local settings_file="$CODEBUDDY_DIR/settings.json"
    if [[ -f "$settings_file" ]]; then
        superpowers_enabled=$(SETTINGS_FILE="$settings_file" "$PYTHON_CMD" -c "
import json, sys, os
try:
    with open(os.environ['SETTINGS_FILE']) as f:
        data = json.load(f)
    plugins = data.get('enabledPlugins', {})
    print('true' if plugins.get('superpowers@codebuddy-plugins-official', False) else 'false')
except Exception:
    print('false')
" 2>/dev/null)
    fi

    if [[ "$superpowers_enabled" == "true" ]]; then
        print_info "Superpowers 插件: 已在 settings.json 中启用 ✓"
        print_info "重启 CodeBuddy Code 后即可加载 Superpowers skills"
    else
        print_warning "Superpowers 插件未在 settings.json 中启用"
        print_info "已自动配置：$settings_file"
        print_info "请重启 CodeBuddy Code 加载插件，或手动执行：${YELLOW}/plugin superpowers${NC}"
        # 智能注入：如果文件存在则修改，不存在则创建
        if [[ -f "$settings_file" ]]; then
            # 记录文件原本存在
            local checksums_file="$CODEBUDDY_DIR/.beggar-checksums"
            if [[ -f "$checksums_file" ]]; then
                _sed_inplace "/^settings.json /d" "$checksums_file" 2>/dev/null || true
            fi
            echo "settings.json EXISTED" >> "$checksums_file"
            SETTINGS_FILE="$settings_file" "$PYTHON_CMD" -c "
import json, sys, os, tempfile
try:
    settings_path = os.environ['SETTINGS_FILE']
    with open(settings_path, 'r') as f:
        data = json.load(f)
    if 'enabledPlugins' not in data:
        data['enabledPlugins'] = {}
    data['enabledPlugins']['superpowers@codebuddy-plugins-official'] = True
    # Atomic write via temp file + rename
    dir_name = os.path.dirname(settings_path)
    tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                      prefix='.', suffix='.tmp', delete=False)
    try:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    finally:
        tmp.close()
    os.replace(tmp.name, settings_path)
    print('injected')
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && print_info "已注入 Superpowers 配置到现有 settings.json"
        else
            cat > "$settings_file" << 'EOF'
{
  "enabledPlugins": {
    "superpowers@codebuddy-plugins-official": true
  }
}
EOF
            print_info "已创建默认 settings.json"
            _record_manifest "settings.json"
        fi
    fi

    # Step 3.5: 注入 Beggar hooks 通知配置
    print_info "注入 Beggar hooks 通知配置"
    if [[ -f "$settings_file" ]]; then
        local hooks_enabled
        hooks_enabled=$(SETTINGS_FILE="$settings_file" "$PYTHON_CMD" -c "
import json, sys, os
try:
    with open(os.environ['SETTINGS_FILE']) as f:
        data = json.load(f)
    hooks = data.get('hooks', {})
    # 检查是否已包含 beggar-notify-hook.py
    has_beggar_hook = False
    for event_name, matchers in hooks.items():
        for matcher in (matchers if isinstance(matchers, list) else []):
            for hook in matcher.get('hooks', []):
                if 'beggar-notify-hook.py' in hook.get('command', ''):
                    has_beggar_hook = True
    print('true' if has_beggar_hook else 'false')
except Exception:
    print('false')
" 2>/dev/null)
        if [[ "$hooks_enabled" == "true" ]]; then
            print_info "Beggar hooks: 已配置 ✓"
            # 检测并修复旧版/错误 hook 路径
            local needs_fix
            needs_fix=$(SETTINGS_FILE="$settings_file" "$PYTHON_CMD" -c "
import json, os
with open(os.environ['SETTINGS_FILE']) as f:
    data = json.load(f)
hooks = data.get('hooks', {})
for event_name, matchers in hooks.items():
    for matcher in (matchers if isinstance(matchers, list) else []):
        for hook in matcher.get('hooks', []):
            cmd = hook.get('command', '')
            if 'beggar-notify-hook.py' in cmd and ('\$CODEBUDDY_PROJECT_DIR' in cmd or '/.codebuddy/hooks' in cmd or ' \.codebuddy/hooks' in cmd):
                print('true')
                exit()
print('false')
" 2>/dev/null)
            if [[ "$needs_fix" == "true" ]]; then
                # 根据安装模式选择修复目标路径
                local fix_target_prefix
                if [[ "$BEGGAR_GLOBAL" == "1" ]]; then
                    fix_target_prefix="\$HOME/.codebuddy/hooks"
                else
                    fix_target_prefix="\$CODEBUDDY_PROJECT_DIR/.codebuddy/hooks"
                fi
                SETTINGS_FILE="$settings_file" FIX_TARGET="$fix_target_prefix" "$PYTHON_CMD" -c "
import json, os, tempfile
settings_path = os.environ['SETTINGS_FILE']
fix_target = os.environ['FIX_TARGET']
with open(settings_path, 'r') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
for event_name, matchers in hooks.items():
    for matcher in (matchers if isinstance(matchers, list) else []):
        for hook in matcher.get('hooks', []):
            hook['command'] = hook['command'].replace('\$CODEBUDDY_PROJECT_DIR/.codebuddy/hooks', fix_target)
            # Also fix old broken path: \/.codebuddy/hooks or /.codebuddy/hooks parsed as absolute root
            cmd = hook['command']
            if ' /.codebuddy/hooks/beggar-notify-hook.py' in cmd:
                cmd = cmd.replace(' /.codebuddy/hooks/beggar-notify-hook.py', ' \"' + fix_target + '/beggar-notify-hook.py\"')
            if '\"/\"/.codebuddy/hooks/beggar-notify-hook.py' in cmd:
                cmd = cmd.replace('\"/\"/.codebuddy/hooks/beggar-notify-hook.py', '\"/\"' + fix_target + '/beggar-notify-hook.py\"')
            if ' \.codebuddy/hooks/beggar-notify-hook.py' in cmd:
                cmd = cmd.replace(' \.codebuddy/hooks/beggar-notify-hook.py', ' \"' + fix_target + '/beggar-notify-hook.py\"')
            hook['command'] = cmd
# Atomic write via temp file + rename
dir_name = os.path.dirname(settings_path)
tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                  prefix='.', suffix='.tmp', delete=False)
try:
    json.dump(data, tmp, indent=2, ensure_ascii=False)
    tmp.flush()
    os.fsync(tmp.fileno())
finally:
    tmp.close()
os.replace(tmp.name, settings_path)
" 2>/dev/null && print_info "已修复 Hook 路径：旧版路径 / 错误路径 → $fix_target_prefix"
            fi
        else
            # 全局安装模式：hook 脚本路径用 $HOME/.codebuddy/
            # 项目安装模式：用 $CODEBUDDY_PROJECT_DIR/.codebuddy/
            if [[ "$BEGGAR_GLOBAL" == "1" ]]; then
                hook_cmd='test -f "$HOME/.codebuddy/hooks/beggar-notify-hook.py" && '"$PYTHON_CMD"' "$HOME/.codebuddy/hooks/beggar-notify-hook.py" || exit 0'
            else
                hook_cmd='test -f .codebuddy/hooks/beggar-notify-hook.py && '"$PYTHON_CMD"' .codebuddy/hooks/beggar-notify-hook.py || exit 0'
            fi
            SETTINGS_FILE="$settings_file" HOOK_CMD="$hook_cmd" BEGGAR_GLOBAL="$BEGGAR_GLOBAL" "$PYTHON_CMD" -c "
import json, sys, os, tempfile
try:
    settings_path = os.environ['SETTINGS_FILE']
    with open(settings_path, 'r') as f:
        data = json.load(f)
    if 'hooks' not in data:
        data['hooks'] = {}
    hooks = data['hooks']
    cmd = os.environ['HOOK_CMD']
    changed = False
    # 注入 Notification hooks
    hooks['Notification'] = hooks.get('Notification', [])
    has_perm = any(
        'beggar-notify-hook.py' in hook.get('command', '')
        for m in hooks['Notification'] if isinstance(m, dict)
        for hook in m.get('hooks', [])
    )
    if not has_perm:
        hooks['Notification'].append({
            'matcher': 'permission_prompt',
            'hooks': [{'type': 'command', 'command': cmd, 'timeout': 10}]
        })
        changed = True
    # 注入 PreToolUse hooks
    hooks['PreToolUse'] = hooks.get('PreToolUse', [])
    has_bash = any(
        'beggar-notify-hook.py' in hook.get('command', '')
        for m in hooks['PreToolUse'] if isinstance(m, dict)
        for hook in m.get('hooks', [])
    )
    if not has_bash:
        hooks['PreToolUse'].append({
            'matcher': 'Bash',
            'hooks': [{'type': 'command', 'command': cmd, 'timeout': 10}]
        })
        changed = True
    # 注入 SubagentStop hooks
    hooks['SubagentStop'] = hooks.get('SubagentStop', [])
    has_stop = any(
        'beggar-notify-hook.py' in hook.get('command', '')
        for m in hooks['SubagentStop'] if isinstance(m, dict)
        for hook in m.get('hooks', [])
    )
    if not has_stop:
        hooks['SubagentStop'].append({
            'hooks': [{'type': 'command', 'command': cmd, 'timeout': 10}]
        })
        changed = True
    if not changed:
        print('no_change')
        sys.exit(0)
    # Atomic write via temp file + rename
    dir_name = os.path.dirname(settings_path)
    tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                      prefix='.', suffix='.tmp', delete=False)
    try:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    finally:
        tmp.close()
    os.replace(tmp.name, settings_path)
    print('injected')
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && print_info "已注入 Beggar hooks 通知配置到现有 settings.json"
        fi
    fi

    # Step 4: 检测 OpenSpec CLI
    echo ""
    print_info "Step 4/7: 检测 OpenSpec CLI"
    if command -v openspec &>/dev/null; then
        local opspec_version
        opspec_version=$(openspec --version 2>/dev/null | head -1 || echo "unknown")
        print_info "OpenSpec CLI: $opspec_version"
    else
        print_warning "OpenSpec CLI 未安装（beggar-workflow 全流程依赖此工具）"
        print_info "安装方式：${YELLOW}npm install -g @fission-ai/openspec${NC}"
        print_info "        或：${YELLOW}npx @fission-ai/openspec --help${NC}（按需调用）"
    fi

    # Step 5: 注入 Beggar hooks（含 RTK hook）
    echo ""
    print_info "Step 5/7: 注入 Beggar hooks"

    # 项目安装时，如果全局已有 beggar hooks，跳过注入避免重复
    if [[ "$BEGGAR_GLOBAL" != "1" ]]; then
        if _global_has_beggar_hooks; then
            print_info "检测到全局 beggar hooks 已配置，跳过项目 hooks 注入"
            print_info "CodeBuddy 会自动合并全局 hooks，无需项目级重复配置"
            return_from_step5=true
        fi
    fi

    if [[ "${return_from_step5:-false}" == "true" ]]; then
        : # 跳过 Step 5
    else
    local settings_file="$CODEBUDDY_DIR/settings.json"

    # 确保 settings.json 存在（不存在时创建；已存在时读→改→写保留所有字段）
    if [[ ! -f "$settings_file" ]]; then
        cat > "$settings_file" << 'EOF'
{
  "enabledPlugins": {
    "superpowers@codebuddy-plugins-official": true
  }
}
EOF
        _record_manifest "settings.json"
    fi

    # 注入 hooks（通知 + RTK）— 使用环境变量传参
    SETTINGS_FILE="$settings_file" BEGGAR_GLOBAL="$BEGGAR_GLOBAL" \
    CODEBUDDY_DIR="$CODEBUDDY_DIR" \
    "$PYTHON_CMD" -c "
import json, sys, os, tempfile
try:
    settings_path = os.environ['SETTINGS_FILE']
    with open(settings_path, 'r') as f:
        data = json.load(f)
    if 'hooks' not in data:
        data['hooks'] = {}
    hooks = data['hooks']

    # 根据安装模式选择 hook 脚本路径
    is_global = os.environ.get('BEGGAR_GLOBAL') == '1'
    py_cmd = os.environ.get('PYTHON_CMD', 'python3')
    hook_cmd = (
        f'test -f "$HOME/.codebuddy/hooks/beggar-notify-hook.py" && {py_cmd} "$HOME/.codebuddy/hooks/beggar-notify-hook.py" || exit 0'
        if is_global
        else f'test -f .codebuddy/hooks/beggar-notify-hook.py && {py_cmd} .codebuddy/hooks/beggar-notify-hook.py || exit 0'
    )

    # 注入 Notification hooks（通知）
    hooks['Notification'] = hooks.get('Notification', [])
    has_notify = any(
        'beggar-notify-hook.py' in hook.get('command', '')
        for m in hooks['Notification'] if isinstance(m, dict)
        for hook in m.get('hooks', [])
    )
    changed = False
    if not has_notify:
        hooks['Notification'].append({
            'matcher': 'permission_prompt',
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        hooks['Notification'].append({
            'matcher': 'idle_prompt',
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        changed = True

    # 注入 PreToolUse hooks（通知 + RTK）
    hooks['PreToolUse'] = hooks.get('PreToolUse', [])

    # 5a: beggar 通知 hook
    has_bash_notify = any(
        'beggar-notify-hook.py' in hook.get('command', '')
        for m in hooks['PreToolUse'] if isinstance(m, dict)
        for hook in m.get('hooks', [])
    )
    if not has_bash_notify:
        hooks['PreToolUse'].append({
            'matcher': 'Bash',
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        changed = True

    # 5b: RTK hook（如 rtk 在 PATH 中或常见安装路径存在）
    import subprocess, shutil
    rtk_path = shutil.which('rtk')
    if not rtk_path:
        for candidate in [
            os.path.expanduser('~/.local/bin/rtk'),
            os.path.expanduser('~/.cargo/bin/rtk'),
            os.path.expanduser('~/bin/rtk'),
        ]:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                rtk_path = candidate
                break
    if rtk_path:
        has_rtk = any(
            'rtk hook claude' in hook.get('command', '')
            for m in hooks['PreToolUse'] if isinstance(m, dict)
            for hook in m.get('hooks', [])
        )
        if not has_rtk:
            hooks['PreToolUse'].append({
                'matcher': 'Bash',
                'hooks': [{
                    'type': 'command',
                    'command': 'rtk hook claude'
                }]
            })
            changed = True
            print('rtk_hook_injected')
        # 无论 settings.json 中是否已有 hook，都执行 rtk init -g 确保全局配置完整
        try:
            subprocess.run([rtk_path, 'init', '-g'], capture_output=True, timeout=10)
            print('rtk_init_global')
        except Exception:
            pass
    else:
        print('rtk_not_found')

    # 注入 SubagentStop hooks（通知）
    hooks['SubagentStop'] = hooks.get('SubagentStop', [])
    has_stop = any(
        'beggar-notify-hook.py' in hook.get('command', '')
        for m in hooks['SubagentStop'] if isinstance(m, dict)
        for hook in m.get('hooks', [])
    )
    if not has_stop:
        hooks['SubagentStop'].append({
            'hooks': [{'type': 'command', 'command': hook_cmd, 'timeout': 10}]
        })
        changed = True

    if not changed:
        print('no_change')
        sys.exit(0)

    # Atomic write via temp file + rename
    dir_name = os.path.dirname(settings_path)
    tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                      prefix='.', suffix='.tmp', delete=False)
    try:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    finally:
        tmp.close()
    os.replace(tmp.name, settings_path)
    print('injected')
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            injected)
                print_info "Beggar hooks 已注入 settings.json"
                ;;
            no_change)
                ;;
            rtk_hook_injected)
                print_info "RTK hook 已注入 settings.json（自动转换 bash 命令）"
                ;;
            rtk_init_global)
                print_info "RTK 全局配置已初始化（rtk init -g）"
                ;;
            rtk_not_found)
                print_info "RTK 未安装，跳过 RTK hook 注入"
                print_info "如后续安装 RTK，可手动注入: rtk init -g"
                ;;
        esac
    done
    fi  # 结束 "跳过 Step 5" 条件块

    # Step 6: 设置默认角色主题
    echo ""
    print_info "Step 6/7: 设置角色主题"
    local active_persona="$CODEBUDDY_DIR/persona-active.json"
    local needs_expand=false

    if [[ -f "$active_persona" ]]; then
        # 检查是否为完整展开格式（有 roles 字段）
        local has_roles
        has_roles=$(ACTIVE_PERSONA="$active_persona" "$PYTHON_CMD" -c "
import json, os
with open(os.environ['ACTIVE_PERSONA']) as f:
    data = json.load(f)
print('yes' if 'roles' in data else 'no')
" 2>/dev/null)
        if [[ "$has_roles" == "yes" ]]; then
            local current_theme
            current_theme=$(ACTIVE_PERSONA="$active_persona" "$PYTHON_CMD" -c "
import json, os
with open(os.environ['ACTIVE_PERSONA']) as f:
    print(json.load(f).get('theme', 'unknown'))
" 2>/dev/null)
            print_info "角色主题: $current_theme（已设置）"
        else
            # 旧格式，需要重新展开
            needs_expand=true
            print_info "检测到旧格式 persona-active.json，重新展开..."
        fi
    else
        needs_expand=true
    fi

    if [[ "$needs_expand" == true ]]; then
        # 自动设置/展开默认主题 tech-legends
        local personas_src="$CODEBUDDY_DIR/personas.json"
        [[ -f "$personas_src" ]] || personas_src="$HOME/.codebuddy/personas.json"
        if [[ -f "$personas_src" ]]; then
            local expand_theme="tech-legends"
            # 如果已有旧文件，保留用户选择的 theme
            if [[ -f "$active_persona" ]]; then
                expand_theme=$(ACTIVE_PERSONA="$active_persona" "$PYTHON_CMD" -c "
import json, os
with open(os.environ['ACTIVE_PERSONA']) as f:
    print(json.load(f).get('theme', 'tech-legends'))
" 2>/dev/null)
            fi
            PERSONAS_SRC="$personas_src" ACTIVE_PERSONA="$active_persona" EXPAND_THEME="$expand_theme" "$PYTHON_CMD" -c "
import json, os, tempfile
personas_file = os.environ['PERSONAS_SRC']
active_file = os.environ['ACTIVE_PERSONA']
theme_name = os.environ['EXPAND_THEME']
with open(personas_file) as f:
    data = json.load(f)
if theme_name not in data.get('themes', {}):
    theme_name = 'tech-legends'
theme_data = data['themes'][theme_name]
roles = {}
for role, info in theme_data.get('roles', {}).items():
    roles[role] = info.get('name', role)
active = {
    'theme': theme_name,
    'greeting': theme_data.get('greeting', ''),
    'roles': roles,
    'report_templates': theme_data.get('report_templates', {})
}
# Atomic write via temp file + rename
dir_name = os.path.dirname(active_file)
tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                  prefix='.', suffix='.tmp', delete=False)
try:
    json.dump(active, tmp, indent=2, ensure_ascii=False)
    tmp.flush()
    os.fsync(tmp.fileno())
finally:
    tmp.close()
os.replace(tmp.name, active_file)
" 2>/dev/null
            print_success "角色主题: tech-legends（技术传奇 — 默认）"
            print_info "切换主题: .codebuddy/setup.sh persona list"
            _record_manifest "persona-active.json"
        else
            print_warning "personas.json 不存在，跳过角色设置"
        fi
    fi

    # 询问是否进入 QuickStart 交互式向导（替代 Step 7 通知 + 完成提示）
    echo ""
    local entered_wizard=false
    echo -n "是否进入 QuickStart 交互式配置向导？(Y/n): "
    if read -r wizard_choice </dev/tty 2>/dev/null && [[ -z "$wizard_choice" || "$wizard_choice" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "启动 QuickStart 向导..."
        PLATFORM="$(detect_platform)" BEGGAR_GLOBAL="$BEGGAR_GLOBAL" \
            "$PYTHON_CMD" "$LIB_DIR/quickstart.py" < /dev/tty
        entered_wizard=true
    else
        echo ""
        print_info "跳过向导，使用默认配置"
    fi

    if [[ "$entered_wizard" != "true" ]]; then
        # Step 7: 配置通知（未进入向导时走原流程）
        echo ""
        print_info "Step 7/7: 配置工作流消息通知"
        if ! _configure_notify; then
            print_warning "通知配置失败，可后续手动运行: begdar init"
        fi
    fi

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  初始化完成！${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  项目目录:  $PROJECT_DIR"
    echo -e "  配置目录:  $CODEBUDDY_DIR"
    if [[ "$entered_wizard" != "true" ]]; then
        echo -e "  角色主题:  丐帮（洪七公 编排 → 乔峰/段誉/虚竹 开发 → 扫地僧/王语嫣 审查）"
    fi
    echo ""
    echo -e "  后续操作:"
    echo -e "    运行 ${CYAN}beggar show${NC} 查看 Agent 配置（任意目录）"
    if [[ "$BEGGAR_GLOBAL" != "1" ]]; then
        echo -e "    运行 ${CYAN}.codebuddy/setup.sh persona list${NC} 查看/切换角色主题"
        echo -e "    运行 ${CYAN}.codebuddy/setup.sh agent preset economic${NC} 切换省钱模式"
    else
        echo -e "    运行 ${CYAN}beggar persona list${NC} 查看/切换角色主题"
        echo -e "    运行 ${CYAN}beggar agent preset economic${NC} 切换省钱模式"
        echo ""
        echo -e "  ${YELLOW}⚠ 全局安装注意事项：${NC}"
        echo -e "    首次进入项目目录时，CLI 可能触发重新初始化并重置面板模型。"
        echo -e "    请在进入项目后手动切换面板模型：${YELLOW}/model glm-5.2${NC}（或你需要的模型）"
        echo -e "    beggar 仅管理子 Agent 模型，面板（Leader）模型需开发者自行切换。"
    fi
    echo -e "    运行 ${CYAN}beggar quickstart${NC} 重新进入配置向导"
    echo -e "    运行 ${CYAN}beggar setup shell${NC} 配置 CLI 一键启动别名"
    echo ""

    # 安装 beggar 全局命令 wrapper（项目和全局模式均安装）
    # 注意：必须先删除旧文件再写入，防止旧版软链接（ln -sf setup.sh → beggar）
    # 导致 cat > 跟随链接覆盖 ~/.codebuddy/setup.sh 本体
    {
        mkdir -p "$HOME/.local/bin"
        rm -f "$HOME/.local/bin/beggar"
        local wrapper="$HOME/.local/bin/beggar"
        cat > "$wrapper" << 'WRAPPER_EOF'
#!/bin/bash
# BEGGAR_WRAPPER_MARKER: this is the beggar dispatch wrapper, not setup.sh
# beggar wrapper — auto-detect project setup.sh, fallback to global
_detect() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.codebuddy/setup.sh" ]]; then
            # 防止 wrapper 误覆盖 setup.sh 本体时自递归：跳过含 wrapper marker 的文件
            if head -2 "$dir/.codebuddy/setup.sh" 2>/dev/null | grep -q "BEGGAR_WRAPPER_MARKER"; then
                dir="$(dirname "$dir")"
                continue
            fi
            echo "$dir/.codebuddy/setup.sh"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    if [[ -f "$HOME/.codebuddy/setup.sh" ]]; then
        if head -2 "$HOME/.codebuddy/setup.sh" 2>/dev/null | grep -q "BEGGAR_WRAPPER_MARKER"; then
            return 1
        fi
        echo "$HOME/.codebuddy/setup.sh"
        return 0
    fi
    return 1
}
target="$(_detect)"
if [[ -z "$target" ]]; then
    echo "beggar: no .codebuddy/setup.sh found (try running 'beggar install' first)" >&2
    exit 1
fi
exec bash "$target" "$@"
WRAPPER_EOF
        chmod +x "$wrapper"
    }
    print_success "全局命令已就绪: $HOME/.local/bin/beggar"

    if ! echo "$PATH" | tr ':' '\n' | grep -qF "$HOME/.local/bin"; then
        local rc_file=""
        # Windows Git Bash 优先使用 ~/.bashrc
        if [[ -n "${MSYSTEM:-}" && -f "$HOME/.bashrc" ]]; then
            rc_file="$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
            rc_file="$HOME/.zshrc"
        elif [[ -f "$HOME/.bashrc" ]]; then
            rc_file="$HOME/.bashrc"
        fi
        if [[ -n "$rc_file" ]]; then
            if ! grep -qF '$HOME/.local/bin' "$rc_file" 2>/dev/null; then
                echo '' >> "$rc_file"
                echo '# beggar global command' >> "$rc_file"
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
                print_info "已追加 PATH 到 $rc_file，新终端窗口生效"
            else
                print_info "PATH 已包含 $HOME/.local/bin ✓"
            fi
        fi
    else
        print_info "PATH 已包含 $HOME/.local/bin ✓"
    fi

    # 注入 beggar() shell 函数作为 PATH fallback
    # 新终端窗口 PATH 生效前，source rc 后 shell 函数立即可用
    _inject_beggar_func
    print_info "已注入 ${YELLOW}beggar${NC} shell 函数到 rc 文件（PATH fallback）"

    echo -e "  直接使用 ${CYAN}beggar show${NC} 查看配置（项目根目录或子目录均可）"
}
