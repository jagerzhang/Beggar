#!/usr/bin/env python3
"""
Beggar run summary generator — produces execution metrics after workflow completion.

Generates memory/run-summary-{timestamp}.json with:
  - Per-phase timing (design, coding, testing, review, archive)
  - Review Gate trigger count
  - Coder Guard escalation count
  - Estimated token usage (if provided)
  - Model roster used

Usage:
    python3 run_summary.py \
        --memory-dir /path/to/memory \
        --phase-design 120 \
        --phase-coding 600 \
        --phase-testing 180 \
        --phase-review 240 \
        --phase-archive 30 \
        --review-gate-triggers 1 \
        --coder-guard-escalations 0 \
        --models "architect=glm-5.2,coder-senior=deepseek-v4-pro"

    # Or read from a JSON file:
    python3 run_summary.py --memory-dir /path/to/memory --input /path/to/metrics.json
"""

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime


def _atomic_write_json(path, data):
    """Write JSON to path atomically via temp file + rename."""
    dir_name = os.path.dirname(path)
    os.makedirs(dir_name, exist_ok=True)
    tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                      prefix='.', suffix='.tmp', delete=False)
    try:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    finally:
        tmp.close()
    os.replace(tmp.name, path)


def generate_summary(args):
    """Generate and write the run summary."""
    timestamp = datetime.now().strftime('%Y-%m-%dT%H-%M-%S')

    # Parse models string
    models_used = {}
    if args.models:
        for pair in args.models.split(','):
            if '=' in pair:
                k, v = pair.split('=', 1)
                models_used[k] = v

    # Calculate totals
    phases = {
        'design': args.phase_design or 0,
        'coding': args.phase_coding or 0,
        'testing': args.phase_testing or 0,
        'review': args.phase_review or 0,
        'archive': args.phase_archive or 0,
    }
    total_duration = sum(phases.values())

    summary = {
        'timestamp': timestamp,
        'phases': {
            name: {'duration_sec': dur}
            for name, dur in phases.items()
        },
        'total_duration_sec': total_duration,
        'review_gate': {
            'triggers': args.review_gate_triggers or 0,
            'max_rounds': 3,
        },
        'coder_guard': {
            'escalations': args.coder_guard_escalations or 0,
        },
        'models_used': models_used,
        'token_usage': {
            'input': args.token_input or 0,
            'output': args.token_output or 0,
            'total': (args.token_input or 0) + (args.token_output or 0),
        },
    }

    # Write to memory dir
    if args.memory_dir:
        filename = f'run-summary-{timestamp}.json'
        output_path = os.path.join(args.memory_dir, filename)
        _atomic_write_json(output_path, summary)
        print(f'written: {output_path}')
    else:
        print(json.dumps(summary, indent=2, ensure_ascii=False))

    # Also update stats index if memory dir exists
    if args.memory_dir and os.path.isdir(args.memory_dir):
        stats_file = os.path.join(args.memory_dir, 'run-stats-index.json')
        stats = {}
        if os.path.isfile(stats_file):
            try:
                with open(stats_file) as f:
                    stats = json.load(f)
            except Exception:
                stats = {}

        stats['total_runs'] = stats.get('total_runs', 0) + 1
        stats['total_duration_sec'] = stats.get('total_duration_sec', 0) + total_duration
        stats['total_review_gate_triggers'] = stats.get('total_review_gate_triggers', 0) + (args.review_gate_triggers or 0)
        stats['total_coder_guard_escalations'] = stats.get('total_coder_guard_escalations', 0) + (args.coder_guard_escalations or 0)
        stats['last_run'] = timestamp

        _atomic_write_json(stats_file, stats)

    return 0


def main():
    parser = argparse.ArgumentParser(description='Beggar run summary generator')

    parser.add_argument('--memory-dir', help='Path to memory directory for output')
    parser.add_argument('--input', help='Read metrics from JSON file instead of CLI args')

    # Phase timing (seconds)
    parser.add_argument('--phase-design', type=int, help='Design phase duration (sec)')
    parser.add_argument('--phase-coding', type=int, help='Coding phase duration (sec)')
    parser.add_argument('--phase-testing', type=int, help='Testing phase duration (sec)')
    parser.add_argument('--phase-review', type=int, help='Review phase duration (sec)')
    parser.add_argument('--phase-archive', type=int, help='Archive phase duration (sec)')

    # Metrics
    parser.add_argument('--review-gate-triggers', type=int, default=0, help='Review Gate trigger count')
    parser.add_argument('--coder-guard-escalations', type=int, default=0, help='Coder Guard escalation count')

    # Token usage
    parser.add_argument('--token-input', type=int, default=0, help='Input token count')
    parser.add_argument('--token-output', type=int, default=0, help='Output token count')

    # Models
    parser.add_argument('--models', help='Models used (comma-separated agent=model pairs)')

    args = parser.parse_args()

    # If input file provided, override args from it
    if args.input:
        try:
            with open(args.input) as f:
                data = json.load(f)
            for key, val in data.items():
                setattr(args, key, val)
        except Exception as e:
            print(f'error: cannot read input file: {e}', file=sys.stderr)
            sys.exit(1)

    sys.exit(generate_summary(args))


if __name__ == '__main__':
    main()
