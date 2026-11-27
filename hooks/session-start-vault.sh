#!/bin/bash
# shipstack v2.0: Session Start Hook
# Fires when Claude Code starts a new conversation.
# Injects environment, reads pipeline state, reminds to load context.
#
# Output: one JSON object. hookSpecificOutput.additionalContext carries the
# context for Claude; systemMessage carries a "what's next" banner for the
# user (plain-text stdout reaches Claude only, never the user). Without jq,
# it falls back to plain text, as before.
#
# Install: Add to ~/.claude/settings.json under "hooks.SessionStart"
# See: hooks/settings-snippet.json

# Hook input (session JSON). Claude Code pipes it; a manual run from a terminal has none.
INPUT=""
[ ! -t 0 ] && INPUT=$(cat)

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

# Snapshot the uncommitted changes that already exist (path + content hash),
# so session-stop-vault.sh counts only changes made during this session.
# Fixes the bug where an old untracked file blocked every stop.
git_snapshot() {
    local top
    top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
    { git -C "$top" ls-files -z -m -o -d --exclude-standard; git -C "$top" diff --cached --name-only -z; } 2>/dev/null \
        | tr '\0' '\n' | sort -u | while IFS= read -r f; do
            [ -z "$f" ] && continue
            if [ -f "$top/$f" ]; then
                printf '%s\t%s\n' "$f" "$(git -C "$top" hash-object -- "$top/$f" 2>/dev/null)"
            else
                printf '%s\tDELETED\n' "$f"
            fi
        done
    printf 'INDEX\t%s\n' "$(git -C "$top" diff --cached 2>/dev/null | shasum | cut -c1-40)"
}
SNAP_FILE="$HOME/.shipstack/projects/$SLUG/.session-start-git"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_snapshot "$(pwd)" > "$SNAP_FILE"
else
    rm -f "$SNAP_FILE"
fi

# Resolve the vault project folder, the same way session-stop-vault.sh does.
VAULT_PATH="~/ProductBrain/Projects"
SS_CONFIG="$HOME/.shipstack/config.yaml"
if [ -f "$SS_CONFIG" ]; then
    CONFIGURED=$(grep "^vault_path:" "$SS_CONFIG" | sed 's/^vault_path:[[:space:]]*//')
    [ -n "$CONFIGURED" ] && VAULT_PATH="$CONFIGURED"
fi
VAULT_PATH="${VAULT_PATH/#\~/$HOME}"
PROJECT_DIR="$VAULT_PATH/$SLUG"
HANDOFF="$HOME/.shipstack/projects/$SLUG/handoff.md"

# Print one field from the handoff's YAML frontmatter (first block only).
fm_field() {
    awk -v key="$1" '
        NR == 1 && /^---$/ { f = 1; next }
        f && /^---$/ { exit }
        f && index($0, key ":") == 1 { sub("^" key ":[[:space:]]*", ""); print; exit }
    ' "$HANDOFF"
}

trim() { sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# The banner the user sees: next ticket, the model and effort it needs, and
# the current ones. Next ticket comes from the handoff's next_ticket field,
# else the first ticket ID under "## What's next". Model and effort come from
# a "## Model and effort per ticket" table in the vault project folder.
build_banner() {
    [ -f "$HANDOFF" ] || return 0
    local stage next table row model effort now_model now_effort out
    stage=$(fm_field pipeline_stage)
    next=$(fm_field next_ticket)
    if [ -z "$next" ]; then
        next=$(awk '/^## What.s next/ { f = 1; next } /^## / { f = 0 } f' "$HANDOFF" \
            | grep -oE '[A-Z]{2,}-[0-9]+' | head -1)
    fi

    if [ -n "$next" ] && [ -d "$PROJECT_DIR" ]; then
        table=$(grep -l '^## Model and effort per ticket' "$PROJECT_DIR"/*.md 2>/dev/null | head -1)
        if [ -n "$table" ]; then
            row=$(awk '/^## Model and effort per ticket/ { f = 1; next } /^## / { f = 0 } f && /^\|/' "$table" \
                | grep -E "(^|[^A-Z0-9-])${next}([^0-9]|$)" | head -1)
            model=$(printf '%s' "$row" | awk -F'|' '{ print $4 }' | tr -d '`' | trim)
            effort=$(printf '%s' "$row" | awk -F'|' '{ print $5 }' | tr -d '`' | trim)
        fi
    fi

    if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
        now_model=$(printf '%s' "$INPUT" | jq -r '.model | if type == "object" then (.id // .display_name // empty) else (. // empty) end' 2>/dev/null)
        now_effort=$(printf '%s' "$INPUT" | jq -r '.effort | if type == "object" then (.level // empty) else (. // empty) end' 2>/dev/null)
    fi

    [ -z "$next" ] && [ -z "$stage" ] && return 0
    out="▶ $SLUG"
    [ -n "$next" ] && out="$out — next: $next"
    if [ -n "$model" ]; then
        out="$out · needs /model $model"
        [ -n "$effort" ] && out="$out + /effort $effort"
        if [ -n "$now_model" ] || [ -n "$now_effort" ]; then
            out="$out (now: ${now_model:-?} / ${now_effort:-?})"
        fi
    fi
    [ -n "$stage" ] && out="$out · stage: $stage"
    printf '%s' "$out"
}

emit_context() {
    # Auto-load the prior session handoff, if one exists. Its content (not just a
    # reminder) is printed, so it enters the session context automatically.
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

    # Tell Claude what the user already sees, so the first reply leads with it.
    if [ -n "$BANNER" ]; then
        echo "shipstack: The user sees this banner at session start: \"$BANNER\""
        echo "Open your FIRST reply with the next step and the model + effort it needs (one or two lines), then answer the user."
    fi
}

BANNER=$(build_banner)
CONTEXT=$(emit_context)

if command -v jq >/dev/null 2>&1; then
    jq -n --arg ctx "$CONTEXT" --arg msg "$BANNER" '
        { hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $ctx } }
        + (if $msg == "" then {} else { systemMessage: $msg } end)'
else
    printf '%s\n' "$CONTEXT"
fi
