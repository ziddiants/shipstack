#!/bin/bash
# shipstack v2.0: Session Stop Hook
# Fires every time Claude finishes a turn (Stop event). Blocks the stop —
# forcing Claude to continue — only when ALL of these hold:
#   1. The current project is onboarded to the vault (Projects/$SLUG exists)
#   2. Code actually changed this session (git diff, or a commit since session start)
#   3. No dated session file exists yet for today
# Otherwise it's silent. This is deliberately conditional: an earlier version
# of this idea (session-end-journal.sh, wired to Stop unconditionally) was
# removed for firing noisily after every single turn. See
# Projects/shipstack/Decisions/005-stop-hook-for-session-end-journal.md.
#
# Install: Add to ~/.claude/settings.json under "hooks.Stop"
# See: hooks/settings-snippet.json

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"

CONFIG_FILE="$HOME/.shipstack/config.yaml"
VAULT_PATH="~/ProductBrain/Projects"
if [ -f "$CONFIG_FILE" ]; then
    CONFIGURED=$(grep "^vault_path:" "$CONFIG_FILE" | sed 's/^vault_path:[[:space:]]*//')
    [ -n "$CONFIGURED" ] && VAULT_PATH="$CONFIGURED"
fi
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"

# Detect project slug the same way session-start-vault.sh does
SLUG=""
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REMOTE=$(git -C "$CWD" remote get-url origin 2>/dev/null)
    if [ -n "$REMOTE" ]; then
        SLUG=$(basename "$REMOTE" .git)
    fi
fi
if [ -z "$SLUG" ]; then
    SLUG=$(basename "$CWD")
fi

PROJECT_DIR="$VAULT_PATH/$SLUG"

# Not onboarded to the vault — nothing to enforce, stay silent.
if [ ! -d "$PROJECT_DIR" ]; then
    exit 0
fi

STATE_DIR="$HOME/.shipstack/projects/$SLUG"
TS_FILE="$STATE_DIR/.session-start-ts"
NUDGE_FILE="$STATE_DIR/.stop-nudge-count"
mkdir -p "$STATE_DIR"

# Safety valve: never block more than twice per session.
NUDGES=$(cat "$NUDGE_FILE" 2>/dev/null || echo 0)
if [ "$NUDGES" -ge 2 ]; then
    echo "shipstack: session-stop-vault gave up nudging after 2 tries — write the session journal manually (Sessions/$(date +%F).md) when you get a chance." >&2
    exit 0
fi

# Did work actually happen this session?
SESSION_START_TS=$(cat "$TS_FILE" 2>/dev/null || echo 0)
WORK_HAPPENED=false
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git -C "$CWD" status --porcelain 2>/dev/null)" ]; then
        WORK_HAPPENED=true
    else
        LAST_COMMIT_TS=$(git -C "$CWD" log -1 --format=%ct 2>/dev/null || echo 0)
        [ "$LAST_COMMIT_TS" -gt "$SESSION_START_TS" ] && WORK_HAPPENED=true
    fi
else
    # Non-git fallback: any file under cwd newer than the session-start marker.
    if [ -f "$TS_FILE" ] && find "$CWD" -type f -newer "$TS_FILE" \
        ! -path '*/.git/*' ! -path '*/node_modules/*' 2>/dev/null | grep -q .; then
        WORK_HAPPENED=true
    fi
fi

if [ "$WORK_HAPPENED" != true ]; then
    exit 0
fi

TODAY=$(date +%F)
if find "$PROJECT_DIR/Sessions" -maxdepth 1 -name "${TODAY}*.md" 2>/dev/null | grep -q .; then
    exit 0
fi

# Block: work happened, and today's session file doesn't exist yet.
echo $((NUDGES + 1)) > "$NUDGE_FILE"
REASON="Code changed this session but no session journal was written yet. Before stopping: create $PROJECT_DIR/Sessions/$TODAY.md from the session-journal template (suffix -2 if one already exists for today), prepend a one-line entry to $PROJECT_DIR/Sessions.md, and add any new Decisions/ or Past Mistakes and Lessons.md entries this session warrants. Then finish your response."

# Stop hooks block with a top-level decision/reason object.
# (hookSpecificOutput.permissionDecision is the PreToolUse shape and is ignored here.)
jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
