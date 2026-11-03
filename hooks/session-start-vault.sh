#!/bin/bash
# shipstack v2.0: Session Start Hook
# Fires when Claude Code starts a new conversation.
# Injects environment, reads pipeline state, reminds to load context.
#
# Install: Add to ~/.claude/settings.json under "hooks.SessionStart"
# See: hooks/settings-snippet.json

# Add local binaries to PATH (only when Claude Code gave us an env file to write)
[ -n "${CLAUDE_ENV_FILE:-}" ] && echo "export PATH=\$HOME/.local/bin:\$PATH" >> "$CLAUDE_ENV_FILE"

# Ensure shipstack directory exists
mkdir -p "$HOME/.shipstack/projects" "$HOME/.shipstack/analytics"

# Detect project slug from git remote or directory name
SLUG=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REMOTE=$(git remote get-url origin 2>/dev/null)
    if [ -n "$REMOTE" ]; then
        SLUG=$(basename "$REMOTE" .git)
    fi
fi
if [ -z "$SLUG" ]; then
    SLUG=$(basename "$(pwd)")
fi

# Export slug for Claude (only when an env file is present)
[ -n "${CLAUDE_ENV_FILE:-}" ] && echo "export SHIPSTACK_SLUG=$SLUG" >> "$CLAUDE_ENV_FILE"

# Stamp session-start time and reset the stop-hook nudge counter.
# session-stop-vault.sh uses these to detect "work happened this session"
# and to cap how many times it'll block a stop before giving up.
mkdir -p "$HOME/.shipstack/projects/$SLUG"
date +%s > "$HOME/.shipstack/projects/$SLUG/.session-start-ts"
rm -f "$HOME/.shipstack/projects/$SLUG/.stop-nudge-count"

# Resolve the vault project folder, the same way session-stop-vault.sh does.
VAULT_PATH="~/ProductBrain/Projects"
SS_CONFIG="$HOME/.shipstack/config.yaml"
if [ -f "$SS_CONFIG" ]; then
    CONFIGURED=$(grep "^vault_path:" "$SS_CONFIG" | sed 's/^vault_path:[[:space:]]*//')
    [ -n "$CONFIGURED" ] && VAULT_PATH="$CONFIGURED"
fi
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"
PROJECT_DIR="$VAULT_PATH/$SLUG"

# Auto-load the prior session handoff, if one exists. Its content (not just a
# reminder) is printed, so it enters the session context automatically.
HANDOFF="$HOME/.shipstack/projects/$SLUG/handoff.md"
if [ -f "$HANDOFF" ]; then
    NOW=$(date +%s)
    MT=$(stat -f %m "$HANDOFF" 2>/dev/null || echo "$NOW")
    AGE_DAYS=$(( (NOW - MT) / 86400 ))
    echo "shipstack: Prior session handoff for '$SLUG' (updated ${AGE_DAYS}d ago), loaded below."
    echo "----- BEGIN HANDOFF ($HANDOFF) -----"
    cat "$HANDOFF"
    echo "----- END HANDOFF -----"
else
    echo "shipstack: No prior handoff for '$SLUG'. Fresh session."
fi

# Auto-load this project's Past Mistakes rules, only when the vault project
# folder exists. A non-onboarded project prints nothing here and stays quiet.
PM="$PROJECT_DIR/Past Mistakes and Lessons.md"
if [ -d "$PROJECT_DIR" ] && [ -f "$PM" ]; then
    RULES=$(grep '^- ' "$PM" 2>/dev/null)
    if [ -n "$RULES" ]; then
        echo "----- PAST MISTAKES: rules to apply this session (from $PM) -----"
        echo "$RULES"
        echo "----- END PAST MISTAKES -----"
    fi
fi

# Check for active scope lock
if [ -f "$HOME/.shipstack/freeze-scope.txt" ]; then
    SCOPE_DIR=$(grep "^scope_dir=" "$HOME/.shipstack/freeze-scope.txt" | cut -d'=' -f2-)
    echo "WARNING: Scope lock active from prior /investigate session. Scope: $SCOPE_DIR"
    echo "Delete ~/.shipstack/freeze-scope.txt to clear."
fi

# Vault reminder
echo "Vault available. Remember to read vault context for the active project before starting work."
echo "Pipeline skills available: /brainstorm /challenge /review-plan /investigate /review /ship-check /retro"
