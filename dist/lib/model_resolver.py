#!/usr/bin/env python3
"""
Beggar model resolver — extracted from inline Python in models.sh and preset.sh.

Provides model alias resolution, preset config retrieval, and leader model
recommendation as CLI-callable functions, eliminating the last Shell/Python
inline heredoc patterns.

Usage:
    python3 model_resolver.py resolve --input "sonnet" --models /path/to/beggar-models.json
    python3 model_resolver.py preset --name balanced --models /path/to/beggar-models.json
    python3 model_resolver.py leader --name balanced --models /path/to/beggar-models.json
    python3 model_resolver.py validate --models /path/to/beggar-models.json --schema /path/to/schema.json

Exit codes:
    0  — success
    1  — error (invalid args, file not found, parse error)
    2  — not found (alias/preset not found, but no error)
"""

import argparse
import json
import os
import sys


def load_json(path):
    """Load JSON file, exit on error."""
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        print(f'error: file not found: {path}', file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f'error: invalid JSON in {path}: {e}', file=sys.stderr)
        sys.exit(1)


def resolve_alias(input_str, models_data):
    """Resolve a model alias to its standard ID.

    Tries:
    1. Exact alias match (case-insensitive)
    2. Direct model ID match (case-insensitive)
    3. Fallback: return original input
    """
    if not input_str:
        return ''

    input_lower = input_str.strip().lower()
    aliases = models_data.get('aliases', {})

    # 1. Exact alias match
    for alias, model_id in aliases.items():
        if alias == '_note':
            continue
        if alias.lower() == input_lower:
            return model_id

    # 2. Direct model ID match
    all_ids = {}
    for family in models_data.get('models', {}).get('paid', {}).values():
        for m in family:
            all_ids[m['id'].lower()] = m['id']
    for m in models_data.get('models', {}).get('free', []):
        all_ids[m['id'].lower()] = m['id']

    if input_lower in all_ids:
        return all_ids[input_lower]

    # 3. Fallback
    return input_str.strip()


def get_preset_config(preset_name, models_data):
    """Get preset configuration as list of 'agent=model' lines."""
    preset = models_data.get('presets', {}).get(preset_name)
    if not preset:
        return None

    lines = []
    for agent, model in preset.get('config', {}).items():
        if agent == 'reviewer-b-model':
            lines.append(f'reviewer-b={model}')
        elif not agent.endswith('-model'):
            lines.append(f'{agent}={model}')
    return lines


def get_leader_model(preset_name, models_data):
    """Get the recommended leader model for a preset."""
    preset = models_data.get('presets', {}).get(preset_name, {})
    return preset.get('leader_model', '')


def get_user_overrides(user_models_file):
    """Get user override pairs as list of 'agent=model' lines."""
    if not user_models_file or not os.path.isfile(user_models_file):
        return []
    try:
        with open(user_models_file) as f:
            data = json.load(f)
        lines = []
        for agent, model in data.get('overrides', {}).items():
            lines.append(f'{agent}={model}')
        return lines
    except Exception:
        return []


def validate_schema(models_file, schema_file):
    """Validate beggar-models.json against JSON Schema."""
    try:
        import jsonschema
    except ImportError:
        print('error: jsonschema module not installed. Run: pip install jsonschema', file=sys.stderr)
        sys.exit(1)

    data = load_json(models_file)
    schema = load_json(schema_file)

    try:
        jsonschema.validate(instance=data, schema=schema)
        print('valid')
        return 0
    except jsonschema.ValidationError as e:
        print(f'invalid: {e.message}', file=sys.stderr)
        print(f'  path: {" → ".join(str(p) for p in e.absolute_path)}', file=sys.stderr)
        return 1
    except jsonschema.SchemaError as e:
        print(f'schema error: {e.message}', file=sys.stderr)
        return 1


def main():
    parser = argparse.ArgumentParser(description='Beggar model resolver')
    parser.add_argument('--models', required=True, help='Path to beggar-models.json')

    subparsers = parser.add_subparsers(dest='action', required=True)

    # resolve
    p_resolve = subparsers.add_parser('resolve', help='Resolve model alias')
    p_resolve.add_argument('--input', required=True, help='Input string (alias, shorthand, or model ID)')

    # preset
    p_preset = subparsers.add_parser('preset', help='Get preset config as agent=model lines')
    p_preset.add_argument('--name', required=True, help='Preset name')

    # leader
    p_leader = subparsers.add_parser('leader', help='Get recommended leader model for preset')
    p_leader.add_argument('--name', required=True, help='Preset name')

    # overrides
    p_overrides = subparsers.add_parser('overrides', help='Get user override pairs')
    p_overrides.add_argument('--user-models', required=True, help='Path to user-models.json')

    # validate
    p_validate = subparsers.add_parser('validate', help='Validate beggar-models.json against schema')
    p_validate.add_argument('--schema', required=True, help='Path to JSON Schema file')

    args = parser.parse_args()
    models_data = load_json(args.models)

    if args.action == 'resolve':
        result = resolve_alias(args.input, models_data)
        print(result)

    elif args.action == 'preset':
        lines = get_preset_config(args.name, models_data)
        if lines is None:
            print(f'error: preset "{args.name}" not found', file=sys.stderr)
            sys.exit(1)
        for line in lines:
            print(line)

    elif args.action == 'leader':
        result = get_leader_model(args.name, models_data)
        if result:
            print(result)
        else:
            sys.exit(2)

    elif args.action == 'overrides':
        lines = get_user_overrides(args.user_models)
        for line in lines:
            print(line)

    elif args.action == 'validate':
        code = validate_schema(args.models, args.schema)
        sys.exit(code)


if __name__ == '__main__':
    main()
