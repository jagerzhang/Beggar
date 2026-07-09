#!/usr/bin/env python3
"""
Beggar quickstart wizard — Interactive guided setup for beggar configuration.

Provides a step-by-step walkthrough covering preset selection, notification
configuration, and persona theme selection. Zero third-party dependencies.

Usage (via setup.sh):
    beggar quickstart

Environment variables (provided by setup.sh):
    CODEBUDDY_DIR   - target .codebuddy directory
    PERSONAS_FILE   - path to personas.json
    MODELS_FILE     - path to beggar-models.json
    PLATFORM        - detected platform (cli/ide)
    BEGGAR_GLOBAL   - "1" for global install
"""

import json
import os
import subprocess
import sys
import tempfile

# Enable line editing in input() — optional, not available on all Python builds
try:
    import readline  # noqa: F401
except ImportError:
    pass

# ─── Shared banner ──────────────────────────────────────────────────────

# Ensure lib directory is on path for banner import
_LIB_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else \
    os.path.dirname(os.path.abspath(sys.argv[0]))
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import banner  # noqa: E402


# ─── ANSI colors ────────────────────────────────────────────────────────

CRIMSON = '\033[0;31m'
GREEN = '\033[0;32m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
BOLD = '\033[1m'
NC = '\033[0m'

import re
import unicodedata

_RE_ANSI = re.compile(r'\x1b\[[0-9;]*m')


def _vis_width(s):
    """Display width (CJK=2, others=1), ignoring ANSI escape codes."""
    w = 0
    stripped = _RE_ANSI.sub('', s)
    for c in stripped:
        w += 2 if unicodedata.east_asian_width(c) in ('F', 'W') else 1
    return w


def _box_line(text, color=CYAN, width=62, left=0):
    """Generate a padded line inside ║...║, with automatic CJK-aware alignment."""
    tw = _vis_width(text) + left
    pad = max(0, width - tw)
    return f'{color}║{NC}{" " * left}{text}{" " * pad}{color}║{NC}'


def _box_center(text, color=CYAN, width=62):
    """Centered box line."""
    tw = _vis_width(text)
    left = max(0, (width - tw) // 2)
    return _box_line(text, color, width, left=left)


def _box_top(color=CYAN, width=62):
    return f'{color}╔{"═" * width}╗{NC}'


def _box_bottom(color=CYAN, width=62):
    return f'{color}╚{"═" * width}╝{NC}'


def _box_empty(color=CYAN, width=62):
    return _box_line('', color, width)


# ─── Environment ────────────────────────────────────────────────────────

CODEBUDDY_DIR = os.environ.get('CODEBUDDY_DIR', '')
PERSONAS_FILE = os.environ.get('PERSONAS_FILE', '')
MODELS_FILE = os.environ.get('MODELS_FILE', '')
PLATFORM = os.environ.get('PLATFORM', '')
BEGGAR_GLOBAL = os.environ.get('BEGGAR_GLOBAL', '0')

# Determine setup.sh path
_SETUP_SCRIPT = ''
if CODEBUDDY_DIR:
    candidate = os.path.join(CODEBUDDY_DIR, 'setup.sh')
    if os.path.isfile(candidate):
        _SETUP_SCRIPT = candidate
if not _SETUP_SCRIPT:
    # Fallback: sibling of lib/
    lib_dir = os.path.dirname(os.path.abspath(__file__))
    candidate = os.path.join(os.path.dirname(lib_dir), 'setup.sh')
    if os.path.isfile(candidate):
        _SETUP_SCRIPT = candidate
# If still not found, try project-level fallback
if not _SETUP_SCRIPT:
    for candidate in [
        '/data/workspace/agenthub-portal/beggar/dist/setup.sh',
        os.path.expanduser('~/.codebuddy/setup.sh'),
    ]:
        if os.path.isfile(candidate):
            _SETUP_SCRIPT = candidate
            break


# ─── Persona theme metadata ────────────────────────────────────────────

PERSONA_THEMES = [
    ('tech-legends',    '技术传奇 — Linus、Jeff Dean 等顶级工程师阵容（默认推荐）'),
    ('beggar-gang',     '丐帮 — 金庸武侠丐帮体系，致敬 beggar 项目名'),
    ('sanguo',          '三国 — 三国军师+五虎将体系，运筹帷幄决胜千里'),
    ('shuihu',          '水浒 — 梁山好汉体系，替天行道聚义堂协作'),
    ('genshin',         '原神 — 提瓦特大陆体系，契约之神统御七国'),
    ('default',         '专业模式 — 标准专业命名，无角色扮演'),
]


# ─── Helper functions ──────────────────────────────────────────────────

def _detect_platform():
    """Detect if running in CLI or IDE environment."""
    p = PLATFORM.lower() if PLATFORM else ''
    if p in ('cli', 'ide'):
        return p
    # Fallback detection
    if os.environ.get('TERM_PROGRAM', '') == 'CodeBuddy':
        return 'ide'
    if os.environ.get('TERM', '') in ('xterm-256color', 'xterm'):
        return 'cli'
    return 'unknown'


def _print_step(step_num, title):
    """Print a step header."""
    print()
    print(f'{CYAN}═══ 步骤 {step_num}: {title} ═══{NC}')
    print()


def _prompt_yes_no(prompt_text, default=True):
    """Ask a yes/no question and return boolean."""
    default_str = 'Y/n' if default else 'y/N'
    hint = '默认是' if default else '默认否'
    full_prompt = f'{prompt_text} ({default_str}，{hint}): '
    try:
        answer = input(full_prompt).strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return default
    if not answer:
        return default
    return answer.lower() in ('y', 'yes')


def _prompt_choice(prompt_text, options, default_index=0):
    """Show a numbered list of options and return the selected index.

    Args:
        prompt_text: Text displayed before the options.
        options: List of (key, description) tuples.
        default_index: Default selected index (0-based).

    Returns:
        Selected index (0-based).
    """
    print(prompt_text)
    print()
    for i, (key, desc) in enumerate(options):
        marker = ' ← 推荐' if i == default_index else ''
        print(f'  {GREEN}{i + 1}{NC}) {YELLOW}{key}{NC} — {desc}{marker}')
    print()
    try:
        choice = input(f'请选择 [1-{len(options)}] (默认 {default_index + 1}): ').strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return default_index
    if not choice:
        return default_index
    try:
        idx = int(choice) - 1
        if 0 <= idx < len(options):
            return idx
    except ValueError:
        pass
    print(f'{CRIMSON}无效输入，使用默认选项 {default_index + 1}{NC}')
    return default_index


def _run_setup_command(args):
    """Run setup.sh with given arguments and stream output."""
    if not _SETUP_SCRIPT or not os.path.isfile(_SETUP_SCRIPT):
        print(f'{CRIMSON}[✗] 找不到 setup.sh: {_SETUP_SCRIPT}{NC}')
        return False
    env = os.environ.copy()
    try:
        result = subprocess.run(
            ['bash', _SETUP_SCRIPT] + args,
            env=env,
            capture_output=False,
        )
        return result.returncode == 0
    except FileNotFoundError:
        print(f'{CRIMSON}[✗] 无法执行 bash{NC}')
        return False


def _detect_shell_rc():
    """Detect user's shell rc file path."""
    shell = os.environ.get('SHELL', '/bin/bash')
    shell_name = os.path.basename(shell)
    home = os.path.expanduser('~')
    if shell_name == 'zsh':
        return os.path.join(home, '.zshrc')
    elif shell_name == 'bash':
        return os.path.join(home, '.bashrc')
    return ''


def _find_existing_cbc_alias(rc_file):
    """Check if rc_file already has a cbc/codebuddy alias."""
    if not os.path.isfile(rc_file):
        return None
    try:
        with open(rc_file) as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith('alias cbc='):
                    return stripped
    except Exception:
        pass
    return None


def _find_existing_codebuddy_alias(rc_file):
    """Check if rc_file already has a codebuddy alias."""
    if not os.path.isfile(rc_file):
        return None
    try:
        with open(rc_file) as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith('alias codebuddy='):
                    return stripped
    except Exception:
        pass
    return None


def _write_aliases_to_rc(rc_file, alias_lines):
    """Write or replace both cbc and codebuddy aliases in rc file."""
    try:
        with open(rc_file) as f:
            lines = f.readlines()
        removed_cbc = False
        removed_codebuddy = False
        with open(rc_file, 'w') as f:
            for line in lines:
                stripped = line.strip()
                if stripped.startswith('alias cbc='):
                    if not removed_cbc:
                        f.write(f'{alias_lines[0]}\n')
                        removed_cbc = True
                elif stripped.startswith('alias codebuddy='):
                    if not removed_codebuddy:
                        f.write(f'{alias_lines[1]}\n')
                        removed_codebuddy = True
                else:
                    f.write(line)
            # Append any not yet written
            if not removed_cbc:
                f.write('\n# CodeBuddy CLI alias (configured by beggar)\n')
                f.write(f'{alias_lines[0]}\n')
            if not removed_codebuddy:
                f.write(f'{alias_lines[1]}\n')
    except Exception:
        pass


# ─── Steps ──────────────────────────────────────────────────────────────

def step1_welcome():
    """Step 1: Welcome & introduction."""
    banner.print_banner()


def step2_platform_detection():
    """Step 2: Platform detection & explanation."""
    platform_name = _detect_platform()
    print(f'当前运行环境: {CYAN}{platform_name}{NC}')
    print()

    if platform_name == 'cli':
        print(f'你正在使用 {CYAN}CodeBuddy CLI{NC} 模式。')
        print(f'CLI 模式下，所有 Agent 通过命令行终端运行，模型选择更灵活。')
        print(f'推荐使用 {YELLOW}balanced{NC} 预设方案，GLM-5.2 架构 + V4 代码，兼顾质量与成本。')
    elif platform_name == 'ide':
        print(f'你正在使用 {CYAN}CodeBuddy IDE{NC} 扩展模式。')
        print(f'IDE 模式下，部分模型可能受限于 IDE 提供的模型列表。')
        print(f'推荐使用 {YELLOW}balanced{NC} 预设方案，兼容性好且节约成本。')
    else:
        print(f'{YELLOW}[!] 未能完全确定运行环境{NC}')
        print(f'将使用通用配置。')

    print()
    print(f'环境差异说明：')
    print(f'  {CYAN}CLI 环境{NC} — 支持所有模型，适合深度开发场景')
    print(f'  {CYAN}IDE 环境{NC} — 依赖 IDE 内置模型列表，部分高级模型可能不可用')
    print(f'  beggar 会自动检测平台兼容性，并提示不支持的模型')
    print()


def step3_preset_selection():
    """Step 3: Preset recommendation."""
    presets = [
        ('balanced', 'GLM-5.2 架构 + V4 代码 + 三厂商覆盖 — 质量与成本兼顾（推荐）'),
        ('economic', 'V4-Pro 架构+代码 + Hy3 审查 — 极低成本，适合轻量开发'),
        ('extreme',  'economic 预设 + 免费 Leader — 零成本体验'),
    ]
    idx = _prompt_choice('请选择模型预设方案：', presets, default_index=0)
    return presets[idx][0]


def _detect_existing_notify():
    """Detect if notify.json already exists and return its summary."""
    # Check project-level first, then global
    for check_dir in [CODEBUDDY_DIR, os.path.expanduser('~/.codebuddy')]:
        if not check_dir:
            continue
        nf = os.path.join(check_dir, 'notify.json')
        if os.path.isfile(nf):
            try:
                with open(nf) as f:
                    d = json.load(f)
                channel = d.get('channel', 'wecom')
                has_webhook = bool(d.get('webhook_url', ''))
                return nf, channel, has_webhook
            except Exception:
                pass
    return None, '', False


def step4_notification_config():
    """Step 4: Notification configuration (optional)."""
    # 检测已有通知配置，避免重复输入
    existing_file, existing_channel, existing_has_webhook = _detect_existing_notify()

    if existing_file:
        print(f'{CYAN}[i]{NC} 检测到已有通知配置:')
        print(f'    文件: {existing_file}')
        print(f'    渠道:   {existing_channel}')
        print(f'    Webhook: {"已配置" if existing_has_webhook else "未配置"}')
        print()
        if not _prompt_yes_no('是否修改通知配置？', default=False):
            print(f'{CYAN}[i]{NC} 保留现有通知配置。')
            print()
            return None, existing_channel if existing_channel else None

    print('群机器人通知可以在工作流关键节点（阻塞、完成、决策）发送消息到企业微信或飞书群。')
    print()

    if not _prompt_yes_no('是否配置工作流消息通知？', default=False):
        print(f'{CYAN}[i]{NC} 跳过通知配置，可后续通过 beggar notify 命令配置。')
        print()
        return None, None

    print()
    # 选择通知渠道
    channel_options = [
        ('wecom', '企业微信群机器人（推荐）'),
        ('feishu', '飞书群机器人'),
    ]
    channel_idx = _prompt_choice('请选择通知渠道：', channel_options, default_index=0)
    notify_channel = channel_options[channel_idx][0]

    print()
    if notify_channel == 'wecom':
        print(f'提示：在企业微信群中添加「群机器人」，获取 Webhook 地址。')
        print(f'格式：{CYAN}https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxxxxxxx{NC}')
    else:
        print(f'提示：在飞书群中添加「自定义机器人」，获取 Webhook 地址。')
        print(f'格式：{CYAN}https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx{NC}')
    print()

    try:
        webhook_url = input('请输入 Webhook 地址: ').strip()
    except (EOFError, KeyboardInterrupt):
        print()
        print(f'{CYAN}[i]{NC} 跳过通知配置。')
        return None, None

    if not webhook_url:
        print(f'{YELLOW}[!]{NC} Webhook 地址为空，跳过通知配置。')
        return None, None

    return webhook_url, notify_channel


def step5_persona_selection():
    """Step 5: Persona theme selection."""
    idx = _prompt_choice('请选择角色主题：', PERSONA_THEMES, default_index=0)
    return PERSONA_THEMES[idx][0]


def step6_shell_alias():
    """Step 6: Shell alias configuration for cbc CLI."""
    print('配置 CodeBuddy CLI 快速启动别名，让你输入 cbc 或 codebuddy 时自动带上权限参数。')
    print()
    print(f'  {YELLOW}可用参数速览：{NC}')
    print(f'    -y                           跳过安全权限检查')
    print(f'    --dangerously-skip-permissions  绕过所有权限检查（仅限沙箱）')
    print(f'    --permission-mode <mode>        面板权限模式')
    print(f'    --permission-mode-before-plan   退出计划模式后的权限模式')
    print(f'    --subagent-permission-mode      子 Agent 权限模式')
    print()

    options = [
        ('auto', '全程自动 — -y + auto（低风险放行，高风险询问，智能判断，推荐）'),
        ('acceptEdits', '跳过安全确认 — -y + acceptEdits（自动接受文件编辑，保留高风险确认）'),
        ('dontAsk', '静默拦截 — -y + dontAsk + --dangerously-skip-permissions（不询问用户，未授权操作直接拦截，仅限沙箱/信任环境）'),
        ('custom', '自定义 — 逐项选择所有参数'),
        ('skip', '跳过 — 稍后手动配置（可通过 beggar setup shell 配置）'),
    ]
    idx = _prompt_choice('请选择 codebuddy (cbc) 的启动模式：', options, default_index=0)

    if idx == 4:  # skip
        print(f'{CYAN}[i]{NC} 已跳过，可稍后运行 {CYAN}beggar setup shell{NC} 配置。')
        print()
        return None

    # Build alias flags
    perm_mode = 'auto'
    subagent_perm = 'auto'
    before_plan_perm = ''
    use_y = True
    skip_permissions = False

    if idx == 0:  # auto — 全程自动（推荐）
        perm_mode = 'auto'
        subagent_perm = 'auto'
    elif idx == 1:  # acceptEdits — 跳过安全确认
        perm_mode = 'acceptEdits'
        subagent_perm = 'acceptEdits'
    elif idx == 2:  # dontAsk — 静默拦截
        perm_mode = 'dontAsk'
        subagent_perm = 'acceptEdits'
        skip_permissions = True
    elif idx == 3:  # custom
        # Panel permission mode
        print()
        perm_options = [
            ('acceptEdits', '自动接受编辑 — 自动接受文件编辑操作（推荐）'),
            ('dontAsk', '静默拦截 — 不询问用户，未授权操作直接拦截'),
            ('auto', '自动判断 — 低风险放行，高风险询问'),
            ('bypassPermissions', '绕过权限 — 绕过所有权限检查'),
        ]
        perm_idx = _prompt_choice('面板权限模式 (--permission-mode)：', perm_options, default_index=0)
        perm_mode = perm_options[perm_idx][0]

        # Sub-agent permission mode
        print()
        subagent_options = [
            ('acceptEdits', '自动接受子 Agent 编辑（推荐）'),
            ('dontAsk', '静默拦截子 Agent'),
            ('auto', '自动判断'),
        ]
        sub_idx = _prompt_choice('子 Agent 权限模式 (--subagent-permission-mode)：', subagent_options, default_index=0)
        subagent_perm = subagent_options[sub_idx][0]

        # Permission mode before plan
        print()
        before_plan_options = [
            ('default', 'default — 恢复默认行为（不设置此参数）'),
            ('acceptEdits', 'acceptEdits — 退出计划模式后自动接受编辑'),
            ('dontAsk', 'dontAsk — 退出计划模式后静默拦截'),
            ('auto', 'auto — 退出计划模式后自动判断'),
        ]
        bp_idx = _prompt_choice('退出计划模式后的权限 (--permission-mode-before-plan)：', before_plan_options, default_index=0)
        if bp_idx != 0:
            before_plan_perm = before_plan_options[bp_idx][0]

        # -y flag
        use_y = _prompt_yes_no('是否添加 -y 参数（跳过安全权限检查）？', default=True)

        # --dangerously-skip-permissions
        skip_permissions = _prompt_yes_no('是否添加 --dangerously-skip-permissions（绕过所有权限检查，仅限沙箱）？', default=False)

    # Build shell alias lines (both cbc and codebuddy)
    flags = ''
    if use_y:
        flags += ' -y'
    if skip_permissions:
        flags += ' --dangerously-skip-permissions'
    flags += f' --permission-mode {perm_mode} --subagent-permission-mode {subagent_perm}'
    if before_plan_perm:
        flags += f' --permission-mode-before-plan {before_plan_perm}'

    alias_lines = [
        f"alias cbc='cbc{flags}'",
        f"alias codebuddy='codebuddy{flags}'",
    ]

    print()
    print(f'  生成的 alias：')
    print(f'  {CYAN}{alias_lines[0]}{NC}')
    print(f'  {CYAN}{alias_lines[1]}{NC}')
    print()

    # Detect shell rc file
    rc_file = _detect_shell_rc()
    if not rc_file:
        print(f'{YELLOW}[!]{NC} 未检测到 shell 配置文件，请手动将上述 alias 添加到你的 shell rc 文件。')
        print()
        return '\n'.join(alias_lines)

    # Check for existing aliases
    existing_cbc = _find_existing_cbc_alias(rc_file)
    existing_codebuddy = _find_existing_codebuddy_alias(rc_file)

    if existing_cbc or existing_codebuddy:
        print(f'{YELLOW}[!]{NC} 已存在 codebuddy/cbc alias，将覆盖写入。')
        if existing_cbc:
            print(f'  旧 cbc: {existing_cbc}')
        if existing_codebuddy:
            print(f'  旧 codebuddy: {existing_codebuddy}')
        if not _prompt_yes_no('是否覆盖？', default=True):
            print(f'{CYAN}[i]{NC} 保留现有 alias，跳过写入。')
            print(f'{CYAN}[i]{NC} 如需生效，执行 {CYAN}source {rc_file}{NC} 或重新打开终端。')
            print()
            return existing_cbc or existing_codebuddy
    elif not _prompt_yes_no(f'是否写入 {rc_file}？', default=True):
        print(f'{CYAN}[i]{NC} 已跳过，可手动执行上述命令。')
        print(f'{CYAN}[i]{NC} 如需生效，执行 {CYAN}source {rc_file}{NC} 或重新打开终端。')
        print()
        return '\n'.join(alias_lines)

    # Write aliases to rc file
    try:
        _write_aliases_to_rc(rc_file, alias_lines)
        print(f'{GREEN}[✓]{NC} 已写入 {rc_file}')
        print(f'{CYAN}[i]{NC} 执行 {CYAN}source {rc_file}{NC} 或重新打开终端使其生效。')
        print()
    except (IOError, OSError) as e:
        print(f'{CRIMSON}[✗] 写入失败: {e}{NC}')
        return None

    return '\n'.join(alias_lines)


def step7_summary_and_execute(preset, notify_webhook, notify_channel, persona, alias_result=None):
    """Step 7: Summary + execution."""
    # notify_webhook=None + notify_channel=已配置 → 保留现有通知配置
    _notify_existing = (notify_webhook is None and notify_channel)

    print(f'{CYAN}═══ 配置总结 ═══{NC}')
    print()
    print(f'  模型预设:  {YELLOW}{preset}{NC}')
    if notify_webhook and notify_channel:
        masked = notify_webhook[:30] + '****' + notify_webhook[-8:] \
            if len(notify_webhook) > 38 else '****'
        print(f'  通知配置:  {CYAN}已配置{NC} (渠道: {notify_channel}, Webhook: {masked})')
    elif _notify_existing:
        print(f'  通知配置:  {CYAN}保留现有{NC} (渠道: {notify_channel})')
    else:
        print(f'  通知配置:  {CYAN}未配置{NC} (可后续通过 beggar notify 设置)')
    persona_name = dict(PERSONA_THEMES).get(persona, persona)
    print(f'  角色主题:  {YELLOW}{persona_name}{NC}')
    if alias_result:
        alias_display = alias_result if len(alias_result) < 50 else alias_result[:47] + '...'
        print(f'  Shell 别名: {CYAN}{alias_display}{NC}')
    else:
        print(f'  Shell 别名: {CYAN}未配置{NC} (可后续通过 beggar setup shell 设置)')
    print()

    if not _prompt_yes_no('确认应用以上配置？', default=True):
        print()
        print(f'{YELLOW}[!]{NC} 已取消配置。你可以随时运行 {CYAN}beggar quickstart{NC} 重新配置。')
        return False

    print()
    print(f'{CYAN}[i]{NC} 正在应用配置...')
    print()

    # ── Apply preset ──
    preset_map = {
        'balanced': 'balanced',
        'economic': 'economic',
        'extreme': 'economic',
    }
    actual_preset = preset_map.get(preset, 'balanced')
    print(f'{CYAN}[i]{NC} 应用模型预设: {YELLOW}{actual_preset}{NC}')

    if preset == 'extreme':
        print(f'  {YELLOW}[!] 说明{NC}: extreme 模式使用 economic 预设 + 免费 Leader 模型。')
        print(f'  请手动将主面板模型切换为免费模型（如 hy3 或 kimi-k2.5）。')

    if not _run_setup_command(['preset', actual_preset]):
        print(f'{CRIMSON}[✗] 预设应用失败{NC}')
        return False
    print(f'{GREEN}[✓]{NC} 模型预设已应用')
    print()

    # ── Apply notification config ──
    if notify_webhook and notify_channel:
        _apply_notification(notify_webhook, notify_channel)
    elif _notify_existing:
        print(f'{CYAN}[i]{NC} 通知配置: 保留现有 (渠道: {notify_channel})')
        print()

    # ── Apply persona theme ──
    print(f'{CYAN}[i]{NC} 应用角色主题: {YELLOW}{persona}{NC}')
    if not _run_setup_command(['persona', persona]):
        print(f'{YELLOW}[!]{NC} 角色主题应用失败（可后续手动配置）')
    else:
        print(f'{GREEN}[✓]{NC} 角色主题已应用')
    print()

    return True


def _apply_notification(webhook_url, notify_channel):
    """Write notification config to notify.json."""
    # Determine the target directory
    if BEGGAR_GLOBAL == '1' or not CODEBUDDY_DIR:
        target_dir = os.path.expanduser('~/.codebuddy')
    else:
        target_dir = CODEBUDDY_DIR

    notify_file = os.path.join(target_dir, 'notify.json')
    notify_config = {
        '_comment': 'beggar 通知配置 — 群机器人 webhook 渠道',
        'enabled': True,
        'channel': notify_channel,
        'webhook_url': webhook_url,
        'events': {
            'N1': {'enabled': True},
            'N2': {'enabled': True},
            'N3': {'enabled': True},
            'N4': {'enabled': True},
            'N5': {'enabled': True},
            'N6': {'enabled': True},
            'N7': {'enabled': True},
            'N8': {'enabled': True},
            'N9': {'enabled': True},
        },
    }
    try:
        # Atomic write via temp file + rename
        dir_name = os.path.dirname(notify_file)
        tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                          prefix='.', suffix='.tmp', delete=False)
        try:
            json.dump(notify_config, tmp, indent=2, ensure_ascii=False)
            tmp.flush()
            os.fsync(tmp.fileno())
        finally:
            tmp.close()
        os.replace(tmp.name, notify_file)
        os.chmod(notify_file, 0o600)
        print(f'{GREEN}[✓]{NC} 通知配置已保存 ({notify_file})')

        # Update .gitignore for project mode
        if BEGGAR_GLOBAL != '1' and CODEBUDDY_DIR:
            project_dir = os.path.dirname(CODEBUDDY_DIR)
            gitignore_file = os.path.join(project_dir, '.gitignore')
            if os.path.isfile(gitignore_file):
                with open(gitignore_file) as f:
                    content = f.read()
                if '.codebuddy/notify.json' not in content:
                    with open(gitignore_file, 'a') as f:
                        f.write('\n# beggar 通知配置\n.codebuddy/notify.json\n')
                    print(f'{GREEN}[✓]{NC} notify.json 已加入 .gitignore')

    except (IOError, OSError) as e:
        print(f'{CRIMSON}[✗] 通知配置写入失败: {e}{NC}')


def step8_completion():
    """Step 8: Completion tips."""
    w = 62
    print()
    print(_box_top(GREEN, w))
    print(_box_empty(GREEN, w))
    print(_box_center(f'{BOLD}🎉 配置完成！欢迎使用 Beggar！{NC}', GREEN, w))
    print(_box_empty(GREEN, w))
    print(_box_bottom(GREEN, w))
    print()
    print(f'下一步建议：')
    print()
    rc_file = _detect_shell_rc()
    if rc_file:
        print(f'  {GREEN}1.{NC} 运行 {CYAN}source {rc_file}{NC} 或重新打开终端使 alias 生效')
    else:
        print(f'  {GREEN}1.{NC} 重新打开终端使 alias 生效（或手动 source 你的 shell rc 文件）')
    print(f'  {GREEN}2.{NC} 运行 {CYAN}beggar show{NC} 查看当前配置详情')
    print(f'  {GREEN}3.{NC} 运行 {CYAN}beggar persona{NC} 随时切换角色主题')
    print(f'  {GREEN}4.{NC} 重启 {YELLOW}CodeBuddy Code{NC} 加载新配置')
    print(f'  {GREEN}5.{NC} 运行 {CYAN}beggar validate{NC} 检查配置是否正确')
    print()
    print(f'常用命令速查：')
    print(f'  {CYAN}beggar init{NC}                — 初始化或更新环境')
    print(f'  {CYAN}beggar agent preset <name>{NC}  — 切换模型预设')
    print(f'  {CYAN}beggar persona <theme>{NC}      — 切换角色主题')
    print(f'  {CYAN}beggar notify <message>{NC}     — 发送通知')
    print(f'  {CYAN}beggar setup shell{NC}          — 配置 cbc 启动别名')
    print(f'  {CYAN}beggar show{NC}                 — 查看当前配置')
    print(f'  {CYAN}beggar update{NC}               — 更新到最新版本')
    print()
    print(f'需要帮助？运行 {CYAN}beggar help{NC} 查看完整帮助文档。')
    print()


# ─── Main ───────────────────────────────────────────────────────────────

def main():
    """Run the quickstart wizard."""
    try:
        step1_welcome()

        _print_step(2, '平台检测')
        step2_platform_detection()

        _print_step(3, '预设推荐')
        preset = step3_preset_selection()

        _print_step(4, '通知配置')
        notify_webhook, notify_channel = step4_notification_config()

        _print_step(5, '角色主题')
        persona = step5_persona_selection()

        _print_step(6, 'Shell 别名')
        alias_result = step6_shell_alias()

        _print_step(7, '总结与执行')
        success = step7_summary_and_execute(
            preset, notify_webhook, notify_channel, persona, alias_result,
        )
        if not success:
            print(f'{CRIMSON}[✗] 配置应用过程中出现错误。请检查后重试。{NC}')
            return

        _print_step(8, '完成')
        step8_completion()

    except KeyboardInterrupt:
        print()
        print()
        print(f'{YELLOW}[!]{NC} 用户中断。你可以随时运行 {CYAN}beggar quickstart{NC} 重新开始配置。')
        sys.exit(1)


if __name__ == '__main__':
    main()
