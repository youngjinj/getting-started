#!/bin/bash
# ~/.claude 환경 복원 스크립트
# 사용법: bash restore.sh

set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"

echo "=== Claude Code 환경 복원 ==="
echo "Source: $SRC"
echo "Dest:   $DEST"
echo ""

# 1. 기본 디렉토리 생성
mkdir -p "$DEST/skills/jira"
mkdir -p "$DEST/skills/omc-learned/md2html"
mkdir -p "$DEST/skills/omc-reference"
mkdir -p "$DEST/hud"

# 2. 설정 파일 복원
cp -v "$SRC/settings.json" "$DEST/settings.json"
cp -v "$SRC/CLAUDE.md" "$DEST/CLAUDE.md"

# 3. 스킬 복원
cp -v "$SRC/skills/jira/SKILL.md" "$DEST/skills/jira/SKILL.md"
cp -v "$SRC/skills/omc-learned/md2html/SKILL.md" "$DEST/skills/omc-learned/md2html/SKILL.md"
cp -v "$SRC/skills/omc-reference/SKILL.md" "$DEST/skills/omc-reference/SKILL.md"

# 4. HUD 복원
cp -v "$SRC/hud/omc-hud.mjs" "$DEST/hud/omc-hud.mjs"

echo ""
echo "=== 복원 완료 ==="
echo ""
echo "추가 수동 작업:"
echo "  1. API 키 설정: claude config set primaryApiKey <your-key>"
echo "  2. 플러그인 설치: claude plugin install oh-my-claudecode@omc"
echo "  3. 플러그인 설치: claude plugin install clangd-lsp@claude-plugins-official"
