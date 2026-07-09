#!/bin/bash
# Beggar · uninstall | 卸载 beggar（二次确认 + 智能分类删除）

# uninstall: 卸载 beggar（二次确认 + 智能分类删除）
do_uninstall() {
    print_header

    # 全局安装模式警告
    if [[ "$BEGGAR_GLOBAL" == "1" ]]; then
        print_info "全局卸载：只删除 beggar 管理的文件，保留您的自定义配置"
    fi

    # 确认是 beggar 安装的目录
    if [[ ! -f "$CODEBUDDY_DIR/VERSION" ]]; then
        print_warning "未检测到 beggar VERSION 文件，可能不是 beggar 安装的目录"
        echo -n "仍要继续卸载吗？(y/N): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_info "卸载已取消"
            return 0
        fi
    fi

    local core_items=()
    local biz_items=()
    local openspec_items=()
    local unknown_items=()
    local has_manifest=false

    # 优先读取新版 file: 清单（精确卸载）
    if [[ -f "$CODEBUDDY_DIR/.beggar-checksums" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == file:*\ INSTALLED ]]; then
                local fpath="${line#file:}"
                fpath="${fpath% INSTALLED}"
                core_items+=("$fpath")
                has_manifest=true
            fi
        done < <(grep "^file:" "$CODEBUDDY_DIR/.beggar-checksums" 2>/dev/null)
    fi

    # 如果存在新版清单，直接按清单展示并跳过旧版扫描逻辑
    if [[ "$has_manifest" == true ]]; then
        echo -e "即将卸载 beggar，以下文件将被处理：\n"

        echo -e "${GREEN}以下 beggar 核心文件将自动删除（基于安装清单）：${NC}"
        for item in "${core_items[@]}"; do
            echo "  - $item"
        done
        echo ""

        # 扫描不在清单中的文件作为 unknown_items（用户自定义）
        local _find_tmp1
        _find_tmp1=$(mktemp 2>/dev/null || mktemp -t beggar_find1)
        find "$CODEBUDDY_DIR" -mindepth 1 -maxdepth 1 -print0 > "$_find_tmp1"
        while IFS= read -r -d '' item; do
            local basename
            basename=$(basename "$item")
            [[ "$basename" == ".beggar-checksums" ]] && continue

            local in_manifest=false
            for f in "${core_items[@]}"; do
                if [[ "$f" == "$basename" || "$f" == "$basename"/* ]]; then
                    in_manifest=true
                    break
                fi
            done
            if [[ "$in_manifest" == false ]]; then
                unknown_items+=("$basename")
            fi
        done < "$_find_tmp1"
        rm -f "$_find_tmp1"
    else
        # 旧版回退：读取 beggar 安装的业务 skill 目录
        local beggar_installed_dirs=()
        if [[ -f "$CODEBUDDY_DIR/.beggar-checksums" ]]; then
            while IFS= read -r line; do
                if [[ "$line" == dir:*\ INSTALLED ]]; then
                    local dir_path="${line#dir:}"
                    dir_path="${dir_path% INSTALLED}"
                    beggar_installed_dirs+=("$dir_path")
                fi
            done < <(grep "^dir:" "$CODEBUDDY_DIR/.beggar-checksums" 2>/dev/null)
        fi

        # 扫描 .codebuddy/ 下的条目（旧版硬编码分类）
        local _find_tmp2
        _find_tmp2=$(mktemp 2>/dev/null || mktemp -t beggar_find2)
        find "$CODEBUDDY_DIR" -mindepth 1 -maxdepth 1 -print0 > "$_find_tmp2"
        while IFS= read -r -d '' item; do
            local basename
            basename=$(basename "$item")

            case "$basename" in
                agents|tools|VERSION|latest.json|.gitignore|.beggar-checksums|docs|persona-active.json)
                    core_items+=("$basename")
                    ;;
                rules)
                    for sub in "$item"/*; do
                        [[ -e "$sub" ]] || continue
                        local subname
                        subname=$(basename "$sub")
                        if [[ "$subname" == beggar-* ]]; then
                            core_items+=("rules/$subname")
                        else
                            unknown_items+=("rules/$subname")
                        fi
                    done
                    ;;
                commands)
                    if [[ -d "$item/dev" ]]; then
                        core_items+=("commands/dev")
                    fi
                    if [[ -d "$item/opsx" ]]; then
                        openspec_items+=("commands/opsx")
                    fi
                    for sub in "$item"/*; do
                        [[ -e "$sub" ]] || continue
                        local subname
                        subname=$(basename "$sub")
                        if [[ "$subname" != "dev" && "$subname" != "opsx" ]]; then
                            unknown_items+=("commands/$subname")
                        fi
                    done
                    ;;
                skills)
                    for sub in "$item"/*; do
                        [[ -e "$sub" ]] || continue
                        local subname
                        subname=$(basename "$sub")
                        case "$subname" in
                            beggar-notify|beggar-workflow)
                                core_items+=("skills/$subname")
                                ;;
                            openspec-apply-change|openspec-archive-change|openspec-explore|openspec-propose)
                                openspec_items+=("skills/$subname")
                                ;;
                            *)
                                unknown_items+=("skills/$subname")
                                ;;
                        esac
                    done
                    ;;
                local|memory)
                    biz_items+=("$basename")
                    ;;
                beggar-models.json)
                    core_items+=("$basename")
                    ;;
                models.json)
                    # 检测是否为 beggar 旧版格式（v2.9.0 前的文件名）
                    if _is_beggar_models_json "$item"; then
                        core_items+=("$basename")
                    else
                        unknown_items+=("$basename")
                    fi
                    ;;
                setup.sh)
                    core_items+=("$basename")
                    ;;
                *)
                    unknown_items+=("$basename")
                    ;;
            esac
        done < "$_find_tmp2"
        rm -f "$_find_tmp2"

        echo -e "即将卸载 beggar，以下文件将被处理：\n"

        echo -e "${GREEN}以下 beggar 核心文件将自动删除：${NC}"
        for item in "${core_items[@]}"; do
            echo "  - $item"
        done
        echo ""

        if [[ ${#openspec_items[@]} -gt 0 ]]; then
            echo -e "${YELLOW}以下 openspec 相关文件将打包确认：${NC}"
            for item in "${openspec_items[@]}"; do
                echo "  - $item"
            done
            echo ""
        fi

        if [[ ${#biz_items[@]} -gt 0 ]]; then
            echo -e "${YELLOW}以下业务/用户自定义文件将逐个确认：${NC}"
            for item in "${biz_items[@]}"; do
                echo "  - $item"
            done
            echo ""
        fi
    fi

    if [[ ${#unknown_items[@]} -gt 0 ]]; then
        echo -e "${CYAN}以下未识别文件将保留（不动）：${NC}"
        for item in "${unknown_items[@]}"; do
            echo "  - $item"
        done
        echo ""
    fi

    # 二次确认
    echo -n "确认卸载 beggar？请输入 'uninstall' 确认: "
    read -r confirm
    if [[ "$confirm" != "uninstall" ]]; then
        print_info "卸载已取消"
        return 0
    fi

    # 删除核心文件（setup.sh 和 .beggar-checksums 放最后）
    print_info "删除 beggar 核心文件..."
    for item in "${core_items[@]}"; do
        if [[ "$item" == "setup.sh" || "$item" == ".beggar-checksums" ]]; then
            continue
        fi
        local target="$CODEBUDDY_DIR/$item"
        if [[ -e "$target" ]]; then
            rm -rf "$target"
            print_info "已删除: $item"
        fi
    done

    # 清单模式下，清理因文件删除而产生的空目录
    # 只清理 beggar 管理的目录白名单，不触碰 projects/、plugins/ 等 CodeBuddy 系统目录
    if [[ "$has_manifest" == true ]]; then
        print_info "清理空目录..."
        local beggar_managed_roots=(
            "agents"
            "commands/beggar"
            "rules"
            "skills"
            "hooks"
            "lib"
        )
        local dirs_to_check=()
        for managed_root in "${beggar_managed_roots[@]}"; do
            local root_path="$CODEBUDDY_DIR/$managed_root"
            [[ -d "$root_path" ]] || continue
            # 从下往上遍历，先清理深层空目录
            local _find_tmp3
            _find_tmp3=$(mktemp 2>/dev/null || mktemp -t beggar_find3)
            find "$root_path" -mindepth 1 -type d -print0 | sort -z -r > "$_find_tmp3"
            while IFS= read -r -d '' d; do
                dirs_to_check+=("$d")
            done < "$_find_tmp3"
            rm -f "$_find_tmp3"
            # 最后检查 managed_root 本身
            dirs_to_check+=("$root_path")
        done
        for d in "${dirs_to_check[@]}"; do
            if [[ -d "$d" && -z "$(ls -A "$d" 2>/dev/null)" ]]; then
                local dir_name="${d#"$CODEBUDDY_DIR"/}"
                rmdir "$d" 2>/dev/null && print_info "已删除空目录: ${dir_name}"
            fi
        done
    fi

    # 清理 setup.sh init 创建的软链接
    print_info "清理 beggar 创建的入口软链接..."
    if [[ -L "$PROJECT_DIR/.claude" ]] && [[ "$(readlink "$PROJECT_DIR/.claude")" == ".codebuddy" ]]; then
        rm -f "$PROJECT_DIR/.claude"
        print_info "已删除: .claude → .codebuddy"
    fi

    # openspec 相关：打包确认
    if [[ ${#openspec_items[@]} -gt 0 ]]; then
        echo -n "删除 openspec 相关文件？(y/N): "
        read -r opsx_confirm
        if [[ "$opsx_confirm" == "y" || "$opsx_confirm" == "Y" ]]; then
            for item in "${openspec_items[@]}"; do
                local target="$CODEBUDDY_DIR/$item"
                if [[ -e "$target" ]]; then
                    rm -rf "$target"
                    print_info "已删除: $item"
                fi
            done
        else
            print_info "保留 openspec 相关文件"
        fi
    fi

    # settings.json：取消 superpowers + beggar hooks 注入（而非删除整个文件）
    local settings_file="$CODEBUDDY_DIR/settings.json"
    if [[ -f "$settings_file" ]]; then
        echo -n "是否取消 settings.json 中的 superpowers 插件和 beggar hooks 注入？(y/N): "
        read -r sp_confirm
        if [[ "$sp_confirm" == "y" || "$sp_confirm" == "Y" ]]; then
            if "$PYTHON_CMD" -c "
import json, sys, os, tempfile
try:
    with open('$settings_file', 'r') as f:
        data = json.load(f)
    plugins = data.get('enabledPlugins', {})
    if 'superpowers@codebuddy-plugins-official' in plugins:
        del plugins['superpowers@codebuddy-plugins-official']
        if not plugins:
            del data['enabledPlugins']
    # 移除 beggar hooks
    hooks = data.get('hooks', {})
    for event_name in list(hooks.keys()):
        matchers = hooks[event_name]
        if isinstance(matchers, list):
            filtered = []
            for m in matchers:
                if isinstance(m, dict):
                    hs = m.get('hooks', [])
                    has_beggar = any('beggar-notify-hook.py' in h.get('command','') for h in hs)
                    if not has_beggar:
                        filtered.append(m)
            if filtered:
                hooks[event_name] = filtered
            else:
                del hooks[event_name]
    if not hooks:
        if 'hooks' in data:
            del data['hooks']
    # Atomic write via temp file + rename
    dir_name = os.path.dirname('$settings_file')
    tmp = tempfile.NamedTemporaryFile(mode='w', dir=dir_name,
                                      prefix='.', suffix='.tmp', delete=False)
    try:
        json.dump(data, tmp, indent=2, ensure_ascii=False)
        tmp.flush()
        os.fsync(tmp.fileno())
    finally:
        tmp.close()
    os.replace(tmp.name, '$settings_file')
    print('removed')
except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null | grep -q "removed"; then
                :
            else
                print_warning "取消注入失败，请手动检查 settings.json"
            fi

            # 检查是否为用户原有文件
            local settings_existed=false
            if [[ -f "$CODEBUDDY_DIR/.beggar-checksums" ]]; then
                if grep -q "^settings.json EXISTED" "$CODEBUDDY_DIR/.beggar-checksums" 2>/dev/null; then
                    settings_existed=true
                fi
            fi
            if [[ "$settings_existed" == true ]]; then
                print_info "settings.json 为用户原有文件，已取消 superpowers 注入（保留文件）"
            else
                local content
                content=$(cat "$settings_file" | tr -d '[:space:]')
                if [[ "$content" == "{}" || "$content" == "" ]]; then
                    rm -f "$settings_file"
                    print_info "settings.json 已为空，已删除"
                fi
            fi
        else
            print_info "保留 settings.json 不变"
        fi
    fi

    # 逐个确认业务/用户文件（仅旧版模式使用）
    if [[ "$has_manifest" != true && ${#biz_items[@]} -gt 0 ]]; then
        print_info "处理业务/用户自定义文件..."
        for item in "${biz_items[@]}"; do
            local target="$CODEBUDDY_DIR/$item"
            if [[ -e "$target" ]]; then
                echo -n "删除 $item？(y/N): "
                read -r biz_confirm
                if [[ "$biz_confirm" == "y" || "$biz_confirm" == "Y" ]]; then
                    rm -rf "$target"
                    print_info "已删除: $item"
                else
                    print_info "保留: $item"
                fi
            fi
        done
    fi

    # 检查并清理空目录（仅旧版模式使用；清单模式已在上面统一清理）
    if [[ "$has_manifest" != true ]]; then
        for dir in commands skills; do
            local dir_path="$CODEBUDDY_DIR/$dir"
            if [[ -d "$dir_path" ]]; then
                for sub in "$dir_path"/*; do
                    [[ -e "$sub" ]] || continue
                    if [[ -d "$sub" && -z "$(ls -A "$sub" 2>/dev/null)" ]]; then
                        rmdir "$sub" 2>/dev/null && print_info "已删除空子目录: $dir/$(basename "$sub")"
                    fi
                done
            fi
        done
    fi

    # 询问是否删除 .codebuddy/ 目录
    local remaining
    remaining=$(find "$CODEBUDDY_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
    if [[ "$remaining" -eq 0 ]]; then
        print_info ".codebuddy/ 目录已空"
        echo -n "是否删除 .codebuddy/ 目录本身？(y/N): "
        read -r dir_confirm
        if [[ "$dir_confirm" == "y" || "$dir_confirm" == "Y" ]]; then
            rm -f "$CODEBUDDY_DIR/setup.sh"
            rm -f "$CODEBUDDY_DIR/.beggar-checksums"
            rmdir "$CODEBUDDY_DIR" 2>/dev/null
            print_success ".codebuddy/ 目录已删除，beggar 卸载完成"
            _print_cleanup_hints
            exit 0
        fi
    else
        print_info ".codebuddy/ 中仍有保留的文件，目录未删除"
    fi

    # 删除 .beggar-checksums
    if [[ -f "$CODEBUDDY_DIR/.beggar-checksums" ]]; then
        rm -f "$CODEBUDDY_DIR/.beggar-checksums"
        print_info "已删除: .beggar-checksums"
    fi

    # 最后删除 setup.sh 自身
    rm -f "$CODEBUDDY_DIR/setup.sh"

    # 提示手动清理不在 .codebuddy/ 内的 beggar 残留文件
    _print_cleanup_hints

    print_success "卸载完成（.codebuddy/ 中保留的文件请手动清理）"
}

# 提示用户手动清理不在 .codebuddy/ 内的 beggar 残留文件
_print_cleanup_hints() {
    local wrapper="$HOME/.local/bin/beggar"
    local hints=()
    if [[ -f "$wrapper" ]]; then
        hints+=("rm -f $wrapper")
    fi
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]] && grep -q "beggar" "$rc" 2>/dev/null; then
            hints+=("手动编辑 $rc，删除 beggar 添加的行")
        fi
    done
    if [[ ${#hints[@]} -gt 0 ]]; then
        echo ""
        echo -e "${CYAN}[i]${NC} 以下文件不在 .codebuddy/ 内，需要手动清理："
        for h in "${hints[@]}"; do
            echo "  - $h"
        done
    fi
}
