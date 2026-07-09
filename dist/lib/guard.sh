#!/bin/bash
# beggar Coder Guard export/import utilities
#
# Allows team members to share coder-guard.json failure mode data.
#
# Usage:
#   beggar guard export [-o file]
#   beggar guard import [-f file]
#   beggar guard show

# Coder Guard 文件路径
_guard_file() {
    local guard_file="$CODEBUDDY_DIR/memory/coder-guard.json"
    if [[ ! -f "$guard_file" ]]; then
        guard_file="$HOME/.codebuddy/memory/coder-guard.json"
    fi
    echo "$guard_file"
}

# 导出 coder-guard.json
_guard_export() {
    local output_file=""
    # 支持 "-o file" 和 "file" 两种参数形式
    if [[ "${1:-}" == "-o" || "${1:-}" == "--output" ]]; then
        output_file="${2:-}"
    else
        output_file="${1:-}"
    fi
    if [[ -z "$output_file" ]]; then
        output_file="coder-guard-export-$(date +%Y%m%d).json"
    fi

    local guard_file
    guard_file=$(_guard_file)

    if [[ ! -f "$guard_file" ]]; then
        print_warning "未找到 coder-guard.json（$guard_file）"
        print_info "coder-guard.json 在工作流执行后自动生成"
        return 1
    fi

    cp "$guard_file" "$output_file"
    print_success "已导出 Coder Guard 数据到: $output_file"
    print_info "文件大小: $(wc -c < "$output_file") bytes"
    print_info "团队成员可通过以下命令导入: beggar guard import -f $output_file"
}

# 导入 coder-guard.json
_guard_import() {
    local input_file=""
    # 支持 "-f file" 和 "file" 两种参数形式
    if [[ "${1:-}" == "-f" || "${1:-}" == "--file" ]]; then
        input_file="${2:-}"
    else
        input_file="${1:-}"
    fi
    # 去掉残留的 -f / --file 前缀（防御性）
    input_file="${input_file#-f }"
    input_file="${input_file#--file }"

    if [[ -z "$input_file" ]]; then
        print_error "请指定导入文件: beggar guard import -f <file>"
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        print_error "文件不存在: $input_file"
        return 1
    fi

    # 验证 JSON 格式
    if ! "$PYTHON_CMD" -c "import json; json.load(open('$input_file'))" 2>/dev/null; then
        print_error "文件不是有效的 JSON: $input_file"
        return 1
    fi

    local guard_dir="$CODEBUDDY_DIR/memory"
    mkdir -p "$guard_dir"
    local guard_file="$guard_dir/coder-guard.json"

    # 如果已有文件，合并数据而非覆盖
    if [[ -f "$guard_file" ]]; then
        print_info "检测到已有 coder-guard.json，将合并数据..."
        "$PYTHON_CMD" -c "
import json, os, sys

old_file = '$guard_file'
new_file = '$input_file'

with open(old_file) as f:
    old = json.load(f)
with open(new_file) as f:
    new = json.load(f)

# 合并 history（追加去重）
old_history = old.get('history', [])
new_history = new.get('history', [])
# 简单追加（按 timestamp+coder+tags 去重）
seen = set()
merged_history = []
for entry in old_history + new_history:
    key = (entry.get('timestamp', ''), entry.get('coder', ''), tuple(entry.get('tags', [])))
    if key not in seen:
        seen.add(key)
        merged_history.append(entry)

# 合并 summary（累加 total/success/failure）
old_summary = old.get('summary', {})
new_summary = new.get('summary', {})
merged_summary = old_summary.copy()
for coder, tags in new_summary.items():
    if coder not in merged_summary:
        merged_summary[coder] = tags
    else:
        for tag, stats in tags.items():
            if tag not in merged_summary[coder]:
                merged_summary[coder][tag] = stats
            else:
                old_s = merged_summary[coder][tag]
                old_s['total'] = old_s.get('total', 0) + stats.get('total', 0)
                old_s['success'] = old_s.get('success', 0) + stats.get('success', 0)
                old_s['failure'] = old_s.get('failure', 0) + stats.get('failure', 0)

result = {
    'history': merged_history,
    'summary': merged_summary
}
print(json.dumps(result, indent=2, ensure_ascii=False))
" > "${guard_file}.tmp" 2>/dev/null && mv "${guard_file}.tmp" "$guard_file"
        print_success "已合并导入 Coder Guard 数据到: $guard_file"
    else
        cp "$input_file" "$guard_file"
        print_success "已导入 Coder Guard 数据到: $guard_file"
    fi
}

# 显示 coder-guard 摘要
_guard_show() {
    local guard_file
    guard_file=$(_guard_file)

    if [[ ! -f "$guard_file" ]]; then
        print_info "未找到 coder-guard.json（尚无 Coder Guard 数据）"
        print_info "coder-guard.json 在工作流执行后自动生成"
        return 0
    fi

    print_info "Coder Guard 数据: $guard_file"
    echo ""
    "$PYTHON_CMD" -c "
import json, os
with open('$guard_file') as f:
    data = json.load(f)
summary = data.get('summary', {})
if not summary:
    print('  暂无统计数据')
else:
    for coder, tags in sorted(summary.items()):
        print(f'  {coder}:')
        for tag, stats in sorted(tags.items()):
            total = stats.get('total', 0)
            success = stats.get('success', 0)
            failure = stats.get('failure', 0)
            rate = f'{success/total*100:.0f}%' if total > 0 else 'N/A'
            print(f'    {tag:20s} total={total:3d} success={success:3d} failure={failure:3d} rate={rate}')
history = data.get('history', [])
print(f'\n  历史记录: {len(history)} 条')
" 2>/dev/null
}

# guard 命令路由
setup_guard() {
    local action="${1:-show}"
    case "$action" in
        export)  shift; _guard_export "$@" ;;
        import)  shift; _guard_import "$@" ;;
        show)    _guard_show ;;
        *)       print_error "未知操作: $action"; print_info "用法: beggar guard [show|export|import]" ;;
    esac
}
