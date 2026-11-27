#!/bin/bash
# shipstack v2.0 setup — Stateful Sprint Engine + Knowledge OS
# https://github.com/shravan-swagwalapm/shipstack

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SHIPSTACK_DIR="$HOME/.shipstack"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  shipstack v2.0 — Stateful Sprint Engine"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: CLAUDE.md
mkdir -p "$CLAUDE_DIR"
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    echo "Found existing CLAUDE.md — backing up to CLAUDE.md.backup"
    cp "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md.backup"
fi

cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
echo "[1/7] CLAUDE.md installed"

# Step 2: Templates
TEMPLATE_DIR="$CLAUDE_DIR/templates/shipstack"
mkdir -p "$TEMPLATE_DIR/memory"
cp "$SCRIPT_DIR/templates/"*.md "$TEMPLATE_DIR/" 2>/dev/null || true
cp "$SCRIPT_DIR/templates/memory/"*.md "$TEMPLATE_DIR/memory/" 2>/dev/null || true
echo "[2/7] Templates installed"

# Step 3: Hooks
HOOKS_DIR="$CLAUDE_DIR/hooks"
mkdir -p "$HOOKS_DIR"
cp "$SCRIPT_DIR/hooks/session-start-vault.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/session-stop-vault.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/guard.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/handoff-stale-check.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR/"*.sh
echo "[3/7] Hooks installed (session-start, session-stop, guard, handoff-stale-check)"

# Step 4: Skills (symlink)
SKILLS_DIR="$CLAUDE_DIR/skills/shipstack"
if [ -L "$SKILLS_DIR" ]; then
    rm "$SKILLS_DIR"  # Remove old symlink
fi
if [ -d "$SKILLS_DIR" ]; then
    echo "Found existing skills dir — backing up to skills-shipstack.backup"
    mv "$SKILLS_DIR" "$CLAUDE_DIR/skills/shipstack.backup"
fi
mkdir -p "$CLAUDE_DIR/skills"
ln -s "$SCRIPT_DIR/skills/shipstack" "$SKILLS_DIR"
echo "[4/7] Skills symlinked ($SKILLS_DIR → $SCRIPT_DIR/skills/shipstack)"

# Step 5: Commands (~/.claude/commands/)
# A skill's typed command name comes from the folder directly inside
# ~/.claude/skills/. ShipStack's skills sit one folder deeper than that
# (skills/shipstack/<name>/SKILL.md), which hides them from typing and
# from Claude's own skill search. A per-skill link in ~/.claude/commands/
# takes its name from the file itself, not folder depth, so it works.
COMMANDS_DIR="$CLAUDE_DIR/commands"
mkdir -p "$COMMANDS_DIR"
command_count=0
for skill_path in "$SKILLS_DIR"/*/SKILL.md; do
    [ -e "$skill_path" ] || continue
    skill_name="$(basename "$(dirname "$skill_path")")"
    ln -sf "$skill_path" "$COMMANDS_DIR/$skill_name.md"
    command_count=$((command_count + 1))
done
echo "[5/7] Commands linked ($command_count skills → $COMMANDS_DIR)"

# Step 6: Pipeline directory (~/.shipstack/)
mkdir -p "$SHIPSTACK_DIR/projects" "$SHIPSTACK_DIR/analytics"

# Create default config if none exists
if [ ! -f "$SHIPSTACK_DIR/config.yaml" ]; then
    cat > "$SHIPSTACK_DIR/config.yaml" << 'YAML'
# shipstack v2.0 configuration
# See: https://github.com/shravan-swagwalapm/shipstack

# Path to your knowledge vault (Obsidian, plain markdown, etc.)
# Skills read past mistakes, decisions, and session journals from here.
vault_path: ~/ProductBrain/Projects

# Default scope mode for new sessions (EXPAND, SELECTIVE, HOLD, REDUCE)
default_scope_mode: HOLD

# Enable PreToolUse guard hook for scope enforcement
guard_enabled: true
YAML
    echo "[6/7] Pipeline directory created with default config"
else
    echo "[6/7] Pipeline directory exists — config preserved"
fi

# Step 7: Summary
echo "[7/7] Setup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Next steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  1. Edit ~/.shipstack/config.yaml:"
echo "     Set vault_path to your knowledge folder"
echo "     (e.g., ~/ProductBrain/Projects or ~/my-project/knowledge)"
echo ""
echo "  2. Add hooks to ~/.claude/settings.json:"
echo "     Merge the contents of hooks/settings-snippet.json"
echo ""
echo "  3. Start a session and try the pipeline:"
echo "     /brainstorm → /challenge → /review-plan → [build] → /review → /ship-check → /retro"
echo ""
echo "  Skills available: /brainstorm /challenge /review-plan /investigate /review /ship-check /ship-feature /retro"
echo ""
echo "For more: https://github.com/shravan-swagwalapm/shipstack"
echo ""
