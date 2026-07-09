#!/bin/bash
# beggar - CodeBuddy 多 Agent 省钱开发方案 - 打包发布脚本 (GitHub Releases)
# 用法: bash scripts/build-release.sh [--changelog-only]
#
# 依赖: gh (GitHub CLI) 已登录认证
# 环境变量: GITHUB_REPO (默认: jagerzhang/beggar)

set -euo pipefail

CHANGELOG_ONLY=false
if [[ "${1:-}" == "--changelog-only" ]]; then
    CHANGELOG_ONLY=true
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${CYAN}[i]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# 项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GITHUB_REPO="${GITHUB_REPO:-jagerzhang/beggar}"

# --changelog-only 模式不需要 gh CLI
if [[ "$CHANGELOG_ONLY" != true ]]; then
    # 检查 gh CLI
    if ! command -v gh &>/dev/null; then
        print_error "未找到 gh (GitHub CLI)，请安装: https://cli.github.com/"
    fi
    # 检查 gh 登录状态
    if ! gh auth status &>/dev/null 2>&1; then
        print_error "gh 未登录，请运行: gh auth login"
    fi
fi

# 读取版本
VERSION_FILE="$PROJECT_DIR/dist/VERSION"
if [[ ! -f "$VERSION_FILE" ]]; then
    print_error "未找到版本文件: $VERSION_FILE"
fi

VERSION=$(cat "$VERSION_FILE" | tr -d '\n')
if [[ -z "$VERSION" ]]; then
    print_error "VERSION 文件为空"
fi

print_info "打包版本: v${VERSION}"
if [[ "$CHANGELOG_ONLY" == true ]]; then
    print_info "CHANGELOG-only 模式：跳过打包和上传"
fi

# 创建 releases 目录
mkdir -p "$PROJECT_DIR/releases"

TAR_FILE="$PROJECT_DIR/releases/beggar-v${VERSION}.tar.gz"
SKILL_ZIP="$PROJECT_DIR/releases/beggar-skill.zip"
SHA256_FILE="$PROJECT_DIR/releases/beggar-v${VERSION}.tar.gz.sha256"

# 打包 dist/
if [[ "$CHANGELOG_ONLY" != true ]]; then

# 运行 shellcheck 静态分析
if command -v shellcheck &>/dev/null; then
    print_info "运行 shellcheck 静态分析..."
    local_lint_errors=0
    for script in "$PROJECT_DIR/install.sh" "$PROJECT_DIR/dist/setup.sh" "$PROJECT_DIR/dist/lib"/*.sh "$PROJECT_DIR/scripts"/*.sh; do
        if [[ -f "$script" ]]; then
            if ! shellcheck -x "$script" 2>/dev/null; then
                print_warning "shellcheck 发现问题: $(basename "$script")"
                local_lint_errors=1
            fi
        fi
    done
    if [[ "$local_lint_errors" -eq 0 ]]; then
        print_success "shellcheck 检查通过"
    else
        print_warning "shellcheck 发现问题，请检查后继续（不阻断发布）"
    fi
else
    print_info "shellcheck 未安装，跳过静态分析"
fi

# 运行 Python 单元测试
if "${PYTHON_CMD:-python3}" -c "import pytest" 2>/dev/null; then
    print_info "运行 Python 单元测试..."
    if "${PYTHON_CMD:-python3}" -m pytest "$PROJECT_DIR/dist/lib/tests/" -q --tb=short 2>/dev/null; then
        print_success "Python 单元测试通过"
    else
        print_error "Python 单元测试未通过，发布已阻断。请修复测试后重新发布。"
    fi
else
    print_info "pytest 未安装，跳过单元测试"
fi

# 跨平台兼容打包
cd "$PROJECT_DIR/dist"
export COPYFILE_DISABLE=1
if tar --version 2>&1 | grep -qi 'bsdtar\|libarchive'; then
    tar czf "$TAR_FILE" --no-xattrs --no-fflags --exclude='tools/rtk-*' --exclude='__pycache__' --exclude='*.pyc' .
else
    tar czf "$TAR_FILE" --exclude='tools/rtk-*' --exclude='__pycache__' --exclude='*.pyc' .
fi
unset COPYFILE_DISABLE
print_success "打包完成: $TAR_FILE"

# 打包 skill/
print_info "打包 skill/ → $SKILL_ZIP ..."
cd "$PROJECT_DIR/skill" && zip -r "$SKILL_ZIP" .
print_success "打包完成: $SKILL_ZIP"

# 计算 SHA256
sha256_cmd() { command -v sha256sum &>/dev/null && sha256sum "$@" || shasum -a 256 "$@"; }
print_info "计算 SHA256..."
SHA256=$(sha256_cmd "$TAR_FILE" | cut -d' ' -f1)
echo "$SHA256  beggar-v${VERSION}.tar.gz" > "$SHA256_FILE"
print_success "tar.gz SHA256: $SHA256"

# 生成 latest-version.txt（供 install.sh 静态重定向获取版本，不依赖 GitHub API）
VERSION_INFO_FILE="$PROJECT_DIR/releases/latest-version.txt"
echo "$VERSION" > "$VERSION_INFO_FILE"
print_success "latest-version.txt 已生成: v${VERSION}"
fi

# ============================================================
# 生成 Release Notes
# ============================================================
RELEASE_DATE=$(date +%Y-%m-%d)

print_info "查找上一个版本标签..."
PREV_TAG=$(git -C "$PROJECT_DIR" tag --sort=-v:refname 2>/dev/null | grep -v "^v${VERSION}$" | head -1 || true)

if [[ -z "$PREV_TAG" ]]; then
    print_warning "未找到上一个版本标签，这是首次发布"
    RELEASE_NOTES_MD="Initial release."
else
    print_success "上一个版本标签: $PREV_TAG"
    COMMITS=$(git -C "$PROJECT_DIR" log "${PREV_TAG}..HEAD" --oneline --no-decorate -- dist/ ':!dist/VERSION' 2>/dev/null || true)
    if [[ -z "$COMMITS" ]]; then
        RELEASE_NOTES_MD="No significant changes."
    else
        ADDED=$(echo "$COMMITS" | grep -iE '^[a-f0-9]+ feat(:|\()' || true)
        FIXED=$(echo "$COMMITS" | grep -iE '^[a-f0-9]+ fix(:|\()' || true)
        DOCS=$(echo "$COMMITS" | grep -iE '^[a-f0-9]+ docs(:|\()' || true)
        REFACTOR=$(echo "$COMMITS" | grep -iE '^[a-f0-9]+ refactor(:|\()' || true)
        CHORE=$(echo "$COMMITS" | grep -iE '^[a-f0-9]+ chore(:|\()' || true)
        OTHER=$(echo "$COMMITS" | grep -ivE '^[a-f0-9]+ (feat|fix|docs|refactor|chore)(:|\()' || true)
        RELEASE_NOTES_MD=""
        build_section() {
            local title="$1" commits="$2"
            if [[ -n "$commits" ]]; then
                RELEASE_NOTES_MD+="### ${title}"$'\n\n'
                while IFS= read -r line; do
                    local desc; desc=$(echo "$line" | sed 's/^[a-f0-9]\+ //')
                    RELEASE_NOTES_MD+="- ${desc}"$'\n'
                done <<< "$commits"
                RELEASE_NOTES_MD+=$'\n'
            fi
        }
        build_section "Added" "$ADDED"
        build_section "Fixed" "$FIXED"
        build_section "Documentation" "$DOCS"
        build_section "Changed" "$REFACTOR"
        build_section "Chore" "$CHORE"
        build_section "Other" "$OTHER"
        [[ -z "$RELEASE_NOTES_MD" ]] && RELEASE_NOTES_MD="No significant changes."
    fi
fi

# ============================================================
# 更新 CHANGELOG.md
# ============================================================
CHANGELOG_FILE="$PROJECT_DIR/CHANGELOG.md"
if [[ ! -f "$CHANGELOG_FILE" ]]; then
    cat > "$CHANGELOG_FILE" << 'CHEOF'
# Changelog

All notable changes to the Beggar project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---
CHEOF
fi

print_info "更新 CHANGELOG.md..."
if grep -q "^## \[v${VERSION}\]" "$CHANGELOG_FILE"; then
    print_warning "CHANGELOG.md 中已存在 v${VERSION} 的条目，跳过追加"
else
    NEW_ENTRY="## [v${VERSION}] - ${RELEASE_DATE}"$'\n\n'
    if [[ "$RELEASE_NOTES_MD" == "No significant changes." ]]; then
        NEW_ENTRY+="_${RELEASE_NOTES_MD}_"$'\n'
    else
        NEW_ENTRY+="${RELEASE_NOTES_MD}"
    fi
    CHANGELOG_CONTENT=$(cat "$CHANGELOG_FILE")
    CHANGELOG_TITLE_LINE=$(echo "$CHANGELOG_CONTENT" | grep -n "^# Changelog" | head -1 | cut -d: -f1)
    if [[ -n "$CHANGELOG_TITLE_LINE" ]]; then
        FIRST_VERSION_LINE=$(echo "$CHANGELOG_CONTENT" | tail -n +"$((CHANGELOG_TITLE_LINE + 1))" | grep -n "^## \[" | head -1 | cut -d: -f1)
        if [[ -n "$FIRST_VERSION_LINE" ]]; then
            INSERT_AFTER=$((CHANGELOG_TITLE_LINE + FIRST_VERSION_LINE - 2))
        else
            INSERT_AFTER=$(echo "$CHANGELOG_CONTENT" | wc -l)
        fi
        HEAD_CONTENT=$(echo "$CHANGELOG_CONTENT" | head -n "${INSERT_AFTER:-0}") || true
        TAIL_START=$((INSERT_AFTER + 1))
        TAIL_CONTENT=$(echo "$CHANGELOG_CONTENT" | tail -n +"${TAIL_START}") || true
        { echo "$HEAD_CONTENT"; echo ""; echo "$NEW_ENTRY"; echo "$TAIL_CONTENT"; } > "${CHANGELOG_FILE}.tmp"
        mv "${CHANGELOG_FILE}.tmp" "$CHANGELOG_FILE"
        print_success "CHANGELOG.md 已更新"
    else
        echo "" >> "$CHANGELOG_FILE"; echo "$NEW_ENTRY" >> "$CHANGELOG_FILE"
        print_success "CHANGELOG.md 已追加"
    fi
fi

if [[ "$CHANGELOG_ONLY" == true ]]; then
    print_success "CHANGELOG.md 已更新，跳过打包和上传"
    exit 0
fi

# ============================================================
# GitHub Release 发布
# ============================================================
print_info "创建 git tag v${VERSION}..."
if git -C "$PROJECT_DIR" rev-parse "v${VERSION}" &>/dev/null 2>&1; then
    print_warning "tag v${VERSION} 已存在，跳过创建"
else
    git -C "$PROJECT_DIR" tag "v${VERSION}"
    print_success "tag v${VERSION} 已创建"
fi

RN_FILE=$(mktemp)
echo "$RELEASE_NOTES_MD" > "$RN_FILE"

print_info "创建 GitHub Release v${VERSION}..."
if gh release create "v${VERSION}" \
    --repo "$GITHUB_REPO" \
    --title "Beggar v${VERSION}" \
    --notes-file "$RN_FILE" \
    "$TAR_FILE" "$SHA256_FILE" "$SKILL_ZIP" "$VERSION_INFO_FILE" \
    2>/dev/null; then
    print_success "GitHub Release 创建成功"
else
    print_warning "GitHub Release 创建失败（可能已存在），尝试更新 assets..."
    gh release upload "v${VERSION}" \
        --repo "$GITHUB_REPO" \
        "$TAR_FILE" "$SHA256_FILE" "$SKILL_ZIP" "$VERSION_INFO_FILE" \
        --clobber 2>/dev/null || print_warning "assets 上传失败"
fi
rm -f "$RN_FILE"

cat << EOF

${GREEN}════════════════════════════════════════════${NC}
${GREEN}  发布成功！${NC}
${GREEN}════════════════════════════════════════════${NC}

版本:      beggar v${VERSION}
日期:      ${RELEASE_DATE}
tar.gz:    ${SHA256}
仓库:      github.com/${GITHUB_REPO}

用户安装:
  curl -fsSL https://github.com/${GITHUB_REPO}/raw/main/install.sh | bash

EOF
print_success "发布完成"
