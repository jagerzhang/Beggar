#!/usr/bin/env python3
"""
Beggar shared banner — unified header used across wizard, show, help, and init.

Usage:
    from banner import print_banner
    print_banner()          # print as-is

    # or run directly:
    python3 banner.py
"""

BOLD = '\033[1m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
NC = '\033[0m'


def print_banner():
    """Print the unified beggar banner box."""
    print()
    print(f'{CYAN}╔══════════════════════════════════════════════════════╗')
    print(f'{CYAN}║  {BOLD}Beggar{CYAN} · {YELLOW}赛博乞丐{CYAN} | CodeBuddy 多 Agent 省钱开发方案 ║')
    print(f'{CYAN}╠══════════════════════════════════════════════════════╣')
    print(f'{CYAN}║  - 项目源码: https://github.com/jagerzhang/beggar    ║')
    print(f'{CYAN}║  - 项目作者: 江湖人称假哥                            ║')
    print(f'{CYAN}║  - 开源协议: MIT License                             ║')
    print(f'{CYAN}╚══════════════════════════════════════════════════════╝{NC}')
    print()


if __name__ == '__main__':
    print_banner()
