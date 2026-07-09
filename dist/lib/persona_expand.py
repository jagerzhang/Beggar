#!/usr/bin/env python3
"""
Beggar persona theme management utility.

Operates on CodeBuddy persona files to list, validate, expand, and set themes.

All paths are passed via environment variables:
  PERSONAS_FILE   - path to personas.json (themes catalog)
  ACTIVE_PERSONA  - path to persona-active.json (current active theme)
  TARGET_THEME    - theme key to operate on

Actions (via ACTION env var):
  list                - list all available themes
  expand              - expand a theme into persona-active.json
  validate            - validate a theme name exists (outputs yes/no)
  get_current         - get current active theme key
  set                 - set (expand + write) a theme
  get_greeting        - get greeting from current active theme
  show_current_config - check if persona-active has full role expansion (outputs yes/no)
"""

import json
import os
import sys
import tempfile


def _get_personas_file():
    pf = os.environ.get('PERSONAS_FILE', '')
    if not pf or not os.path.isfile(pf):
        print('ERROR: PERSONAS_FILE not set or not found', file=sys.stderr)
        sys.exit(1)
    return pf


def _get_active_file():
    af = os.environ.get('ACTIVE_PERSONA', '')
    return af


def _atomic_write_json(path, data):
    """Write JSON to path atomically via temp file + rename."""
    dir_name = os.path.dirname(path)
    tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                      prefix='.', suffix='.tmp', delete=False)
    try:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    finally:
        tmp.close()
    os.replace(tmp.name, path)


# ─── list ───────────────────────────────────────────────────────────────

def action_list():
    """List all themes with role mappings. Mark current active with '← 当前'.
    (setup.sh L2507-L2523)
    """
    personas_file = _get_personas_file()
    active_file = os.environ.get('ACTIVE_PERSONA', '')

    with open(personas_file) as f:
        data = json.load(f)

    # Determine currently active theme
    active = ''
    if active_file:
        try:
            with open(active_file) as af:
                active = json.load(af).get('theme', '')
        except Exception:
            pass
    if not active:
        active = data.get('_meta', {}).get('default_theme', 'beggar-gang')

    for key, theme in data.get('themes', {}).items():
        marker = ' ← 当前' if key == active else ''
        print(f'  {key:16s} {theme["name"]} ({theme["name_en"]}){marker}')
        for role, info in theme.get('roles', {}).items():
            print(f'                    {role:16s} → {info["name"]} '
                  f'({info.get("motto", "")})')
        print()


# ─── expand ─────────────────────────────────────────────────────────────

def action_expand():
    """Expand a theme into persona-active.json. Fallback to 'beggar-gang'.
    (setup.sh L1523-L1543)
    """
    personas_file = _get_personas_file()
    active_file = _get_active_file()
    theme_name = os.environ.get('TARGET_THEME', 'beggar-gang')

    with open(personas_file) as f:
        data = json.load(f)

    if theme_name not in data.get('themes', {}):
        theme_name = 'beggar-gang'

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

    _atomic_write_json(active_file, active)


# ─── validate ───────────────────────────────────────────────────────────

def action_validate():
    """Validate that TARGET_THEME exists. Outputs 'yes' or 'no'.
    (setup.sh L2531-L2539)
    """
    personas_file = _get_personas_file()
    target_theme = os.environ.get('TARGET_THEME', '')

    with open(personas_file) as f:
        data = json.load(f)

    if target_theme in data.get('themes', {}):
        print('yes')
    else:
        sys.exit(1)


# ─── get_current ────────────────────────────────────────────────────────

def action_get_current():
    """Print the currently active theme key.
    (setup.sh L1494-L1498)
    """
    active_file = _get_active_file()
    with open(active_file) as f:
        print(json.load(f).get('theme', 'unknown'))


# ─── set ────────────────────────────────────────────────────────────────

def action_set():
    """Set (expand and write) a theme to persona-active.json.
    (setup.sh L2553-L2570)
    """
    personas_file = _get_personas_file()
    active_file = _get_active_file()
    target_theme = os.environ['TARGET_THEME']

    with open(personas_file) as f:
        data = json.load(f)

    theme_data = data['themes'][target_theme]
    roles = {}
    for role, info in theme_data.get('roles', {}).items():
        roles[role] = info.get('name', role)

    active = {
        'theme': target_theme,
        'greeting': theme_data.get('greeting', ''),
        'roles': roles,
        'report_templates': theme_data.get('report_templates', {})
    }

    _atomic_write_json(active_file, active)


# ─── get_greeting ───────────────────────────────────────────────────────

def action_get_greeting():
    """Print greeting from current active persona.
    """
    active_file = os.environ.get('ACTIVE_PERSONA', '')

    if active_file:
        try:
            with open(active_file) as f:
                active = json.load(f)
            greeting = active.get('greeting', '')
            if greeting:
                print(greeting)
                return
        except Exception:
            pass

    # Fallback to default theme
    personas_file = _get_personas_file()
    with open(personas_file) as f:
        data = json.load(f)
    default_theme = data.get('_meta', {}).get('default_theme', 'beggar-gang')
    theme_data = data['themes'].get(default_theme, {})
    print(theme_data.get('greeting', ''))


# ─── show_current_config ────────────────────────────────────────────────

def action_show_current_config():
    """Check if persona-active.json has full expansion (has 'roles' key).
    Outputs 'yes' or 'no'.
    (setup.sh L1486-L1491)
    """
    active_file = _get_active_file()
    with open(active_file) as f:
        data = json.load(f)
    print('yes' if 'roles' in data else 'no')


# ─── Dispatch ───────────────────────────────────────────────────────────

ACTIONS = {
    'list': action_list,
    'expand': action_expand,
    'validate': action_validate,
    'get_current': action_get_current,
    'set': action_set,
    'get_greeting': action_get_greeting,
    'show_current_config': action_show_current_config,
}


def main():
    action = os.environ.get('ACTION', '')
    if not action:
        print('ERROR: ACTION environment variable is required', file=sys.stderr)
        print('Valid actions: ' + ', '.join(sorted(ACTIONS.keys())), file=sys.stderr)
        sys.exit(1)

    handler = ACTIONS.get(action)
    if handler is None:
        print(f'ERROR: Unknown action: {action}', file=sys.stderr)
        print('Valid actions: ' + ', '.join(sorted(ACTIONS.keys())), file=sys.stderr)
        sys.exit(1)

    try:
        handler()
    except Exception as e:
        print(f'error: {e}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
