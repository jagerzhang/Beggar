#!/usr/bin/env python3
# Beggar · 赛博乞丐 | Agent 配置表格渲染模块
#
# 从 dist/setup.sh show_config() 的 Python heredoc 提取为独立脚本。
# 所有参数通过环境变量传递，禁止 shell 字符串插值。
#
# 环境变量：
#   PLATFORM, AGENTS_DIR, MODELS_FILE, USER_MODELS_FILE, CODEBUDDY_DIR
#   CYAN, YELLOW, NC, BEGGAR_PROJECT_MODE, PERSONAS_FILE
#
# 用法：
#   CYAN="$CYAN" YELLOW="$YELLOW" NC="$NC" \
#   PLATFORM="$(detect_platform)" \
#   AGENTS_DIR="$AGENTS_DIR" \
#   MODELS_FILE="$MODELS_FILE" \
#   USER_MODELS_FILE="$USER_MODELS_FILE" \
#   CODEBUDDY_DIR="$CODEBUDDY_DIR" \
#   BEGGAR_PROJECT_MODE="$BEGGAR_PROJECT_MODE" \
#   python3 /path/to/display.py

import os
import json
import sys
import unicodedata

# Shared banner
_LIB_DIR = os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else \
    os.path.dirname(os.path.abspath(sys.argv[0]))
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import banner  # noqa: E402


# ─── CJK 显示宽度工具 ──────────────────────────────────────────────────

def display_width(s):
    """字符串终端显示宽度（CJK 占 2 列，ANSI 转义不计宽）。"""
    w = 0
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\033':
            j = s.index('m', i)
            i = j + 1
            continue
        ea = unicodedata.east_asian_width(c)
        w += 2 if ea in ('F', 'W') else 1
        i += 1
    return w


def pad_right(s, width):
    dw = display_width(s)
    return s + ' ' * max(0, width - dw)


def pad_left(s, width):
    dw = display_width(s)
    return ' ' * max(0, width - dw) + s


# ─── 主入口（模块级副作用隔离，测试可安全 import 纯函数） ────────────────

def main():
    cyan = os.environ.get('CYAN', '')
    yellow = os.environ.get('YELLOW', '')
    nc = os.environ.get('NC', '')
    platform = os.environ.get('PLATFORM', 'unknown')
    agents_dir = os.environ.get('AGENTS_DIR', '')
    models_file = os.environ.get('MODELS_FILE', '')
    user_models_file = os.environ.get('USER_MODELS_FILE', '')
    codebuddy_dir = os.environ.get('CODEBUDDY_DIR', '')
    beggar_project_mode = os.environ.get('BEGGAR_PROJECT_MODE', '0')

    # ─── 读取 beggar-models.json ──────────────────────────────────────

    cost_map = {}
    platform_map = {}
    presets = {}
    models_data = {}

    if os.path.exists(models_file):
        with open(models_file) as f:
            models_data = json.load(f)
        for section_key in ('paid', 'free'):
            section = models_data.get('models', {}).get(section_key, {})
            items = section if isinstance(section, list) else []
            if isinstance(section, dict):
                for family_models in section.values():
                    if isinstance(family_models, list):
                        items.extend(family_models)
            for m in items:
                mid = m.get('id', '')
                if mid:
                    cost_map[mid] = str(m.get('cost', '—'))
                    platform_map[mid] = m.get('platform', ['cli', 'ide'])
        presets = models_data.get('presets', {})

    # ─── 读取角色主题 ──────────────────────────────────────────────────

    persona_theme = ''
    persona_greeting = ''
    persona_roles = {}
    persona_file = os.path.join(codebuddy_dir, 'persona-active.json')
    if not os.path.exists(persona_file):
        persona_file = os.path.join(os.path.expanduser('~'), '.codebuddy', 'persona-active.json')
    if os.path.exists(persona_file):
        with open(persona_file) as f:
            data = json.load(f)
        persona_theme = data.get('theme', '')
        persona_greeting = data.get('greeting', '')
        persona_roles = data.get('roles', {})

    # ─── 构建数据行 ────────────────────────────────────────────────────

    rows = []
    agents_order = [
        ('leader',        True),
        ('architect',     False),
        ('coder-senior',  False),
        ('coder-standard', False),
        ('coder-lite',    False),
        ('reviewer',      False),
        ('tester',        False),
        ('recorder',      False),
        ('director',      False),
    ]

    for agent, is_special in agents_order:
        if is_special:
            model = '(主面板模型)'
            cost = '0'
            compat = '✓'
            display_name = agent
            if persona_theme and persona_theme != 'default':
                rn = persona_roles.get('leader', '')
                if rn and rn != 'leader':
                    display_name = f'{rn}·leader'
            rows.append((display_name, model, cost, compat))
            continue

        agent_file = os.path.join(agents_dir, f'{agent}.md')
        if not os.path.exists(agent_file):
            # 项目隔离模式：从全局 ~/.codebuddy/agents/ 读取
            global_agent = os.path.join(os.path.expanduser('~'), '.codebuddy', 'agents', f'{agent}.md')
            if os.path.exists(global_agent):
                agent_file = global_agent
            else:
                continue

        model = 'inherit'
        with open(agent_file) as f:
            for line in f:
                if line.startswith('model:'):
                    model = line.split(':', 1)[1].strip()
                    break

        cost = cost_map.get(model, '0')
        if cost == '—':
            cost = '0'
        compat = '✓'
        if model not in ('inherit', '') and platform not in platform_map.get(model, ['cli', 'ide']):
            compat = '⚠'

        display_name = agent
        if persona_theme and persona_theme != 'default':
            rn = persona_roles.get('reviewer-a' if agent == 'reviewer' else agent, '')
            if rn and rn != 'reviewer-a' and rn != agent:
                display_name = f'{rn}·reviewer' if agent == 'reviewer' else f'{rn}·{agent}'

        rows.append((display_name, model, cost, compat))

        # 如果是 reviewer，顺便寻找并展示第二个 reviewer (reviewer-b)
        if agent == 'reviewer':
            reviewer_model = model
            reviewer_b_model = None

            # 1. 优先从 user-models.json 中获取
            if os.path.exists(user_models_file):
                try:
                    with open(user_models_file) as f:
                        ud = json.load(f)
                    overrides = ud.get('overrides', {})
                    if overrides.get('reviewer-b-model'):
                        reviewer_b_model = overrides.get('reviewer-b-model')
                    elif overrides.get('reviewer-b'):
                        reviewer_b_model = overrides.get('reviewer-b')
                    else:
                        based_preset = ud.get('_meta', {}).get('based_on', 'balanced')
                        preset_cfg = presets.get(based_preset, {})
                        reviewer_b_model = preset_cfg.get('config', {}).get('reviewer-b-model')
                except Exception:
                    pass

            # 2. 如果依然为空，通过当前 reviewer 的实际模型匹配 preset 中的 config
            if not reviewer_b_model and reviewer_model not in ('inherit', '', '?'):
                for preset_name, preset_cfg in presets.items():
                    preset_config = preset_cfg.get('config', {})
                    if preset_config.get('reviewer') == reviewer_model:
                        reviewer_b_model = preset_config.get('reviewer-b-model')
                        break

            if reviewer_b_model:
                rn = ''
                if persona_theme and persona_theme != 'default':
                    rn = persona_roles.get('reviewer-b', '')
                display_name_b = f'{rn}·reviewer' if rn else 'reviewer'
                cost_b = cost_map.get(reviewer_b_model, '0')
                if cost_b == '—':
                    cost_b = '0'
                compat_b = '✓'
                if reviewer_b_model not in ('inherit', '') and platform not in platform_map.get(reviewer_b_model, ['cli', 'ide']):
                    compat_b = '⚠'
                rows.append((display_name_b, reviewer_b_model, cost_b, compat_b))

    # ─── 计算列宽 ──────────────────────────────────────────────────────

    col_widths = [8, 8, 4, 6]
    for row in rows:
        col_widths[0] = max(col_widths[0], display_width(row[0]))
        col_widths[1] = max(col_widths[1], display_width(row[1]))
        col_widths[2] = max(col_widths[2], display_width(row[2]))

    # ─── 输出表格 ──────────────────────────────────────────────────────

    # 统一表头
    banner.print_banner()

    # 项目隔离模式提示（bash wrapper 的输出通过这里统一渲染）
    if beggar_project_mode == '1':
        print(f"{cyan}[项目隔离模式]{nc} 配置目录: {codebuddy_dir} （覆盖全局 ~/.codebuddy/）")
        print()

    print(f"当前 Agent 模型配置（平台: {cyan}{platform}{nc}）：")

    if persona_theme and persona_theme != 'default':
        name = persona_theme
        if persona_greeting:
            name += f' (向「{persona_greeting}」汇报)'
        print(f"角色主题: {cyan}{name}{nc}")

    total_width = 2 + sum(col_widths) + 3 * 3
    sep = '─' * total_width
    print(sep)
    print(f"  {cyan}{pad_right('Agent', col_widths[0])}{nc} │ {pad_right('Model', col_widths[1])} │ {pad_right('Cost', col_widths[2])} │ Compat")
    print(sep)

    for row in rows:
        cells = [
            pad_right(row[0], col_widths[0]),
            pad_right(row[1], col_widths[1]),
            pad_left(row[2], col_widths[2]),
            row[3],
        ]
        print(f"  {cells[0]} │ {cells[1]} │ {cells[2]} │ {cells[3]}")

    print()

    # ─── 用户自定义配置检查 ────────────────────────────────────────────

    if os.path.exists(user_models_file):
        try:
            with open(user_models_file) as f:
                ud = json.load(f)
            preset = ud.get('_meta', {}).get('based_on', 'unknown')
            overrides = list(ud.get('overrides', {}).keys())
            if len(overrides) > 0:
                print(f"{yellow}[!] 检测到用户自定义配置（基于 {preset}），{len(overrides)} 个 agent 已覆盖{nc}")
                print(f"    编辑: {cyan}beggar agent user edit{nc}")
        except Exception:
            pass

    # ─── beggar 全局命令提示 ──────────────────────────────────────────
    print(f"{nc}[i] 提示: 可在任意目录使用 {cyan}beggar show{nc}、{cyan}beggar agent{nc} 等命令管理 beggar")


if __name__ == "__main__":
    main()