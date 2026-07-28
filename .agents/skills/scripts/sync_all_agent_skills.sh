#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Master Multi-Agent Skill Sync Script
# Syncs Ruby/Rails Engineering & Architecture Skills to 5 AI Agent Target Systems:
#   1. Claude Code (~/.claude/skills)
#   2. Cursor CLI & IDE (~/.cursor/skills & ~/.cursor/skills-cursor)
#   3. Google Antigravity / AGY (~/.agents/skills, ~/.agent/skills, ~/.gemini/skills)
#   4. OpenCode (~/.opencode/skills)
#   5. Hermes Agent (~/.hermes/skills)
# ─────────────────────────────────────────────────────────────────────────────

SOURCE_DIR="$HOME/.agents/skills"

TARGET_DIRS=(
  "$HOME/.claude/skills"
  "$HOME/.cursor/skills"
  "$HOME/.cursor/skills-cursor"
  "$HOME/.agent/skills"
  "$HOME/.gemini/skills"
  "$HOME/.opencode/skills"
  "$HOME/.hermes/skills"
)

SKILLS=(
  "ruby-design-patterns"
  "rails-design-patterns"
  "ruby-code-smells"
  "ruby-refactoring"
  "rails-architecture-review"
  "rails-refactor"
  "rails-repo-intelligence"
)

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}═══ Syncing Ruby/Rails Architecture Skills Across All 5 AI Agents ═══${NC}"
echo ""

for target_parent in "${TARGET_DIRS[@]}"; do
  echo -e "${CYAN}→ Syncing to:${NC} $target_parent"
  mkdir -p "$target_parent"

  # Sync individual skills
  for skill in "${SKILLS[@]}"; do
    src_skill="$SOURCE_DIR/$skill"
    dst_skill="$target_parent/$skill"
    if [ -d "$src_skill" ]; then
      rm -rf "$dst_skill"
      cp -r "$src_skill" "$dst_skill"
      echo -e "  ${GREEN}✓${NC} $skill"
    else
      echo -e "  ${YELLOW}⚠${NC} Source skill $skill not found in $SOURCE_DIR"
    fi
  done

  # Sync scripts directory
  if [ -d "$SOURCE_DIR/scripts" ]; then
    mkdir -p "$target_parent/scripts"
    cp -r "$SOURCE_DIR/scripts"/* "$target_parent/scripts/" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} scripts/ (5 executable Ruby/Bash analyzers)"
  fi
  echo ""
done

echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}✓ Sync Complete across all 5 Agent Systems!${NC}"
echo -e "Target platforms updated:"
echo -e "  1. Claude Code      (~/.claude/skills)"
echo -e "  2. Cursor CLI / IDE (~/.cursor/skills & ~/.cursor/skills-cursor)"
echo -e "  3. AGY / Antigravity (~/.agents/skills, ~/.agent/skills, ~/.gemini/skills)"
echo -e "  4. OpenCode         (~/.opencode/skills)"
echo -e "  5. Hermes Agent     (~/.hermes/skills)"
echo -e "${GREEN}================================================================${NC}"
