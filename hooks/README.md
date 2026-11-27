# Hooks

Hooks are shell commands that Claude Code executes automatically at specific lifecycle events. They're the **wiring** that makes shipstack's knowledge system automatic rather than manual.

## Available Hooks

### `session-start-vault.sh` — Boot Hook
**When**: Every time Claude Code starts a new conversation.
**What it does**:
1. Adds `~/.local/bin` to PATH (for CLI tools)
2. Sets project-specific environment variables
3. Stamps a session-start timestamp and resets the stop-hook nudge counter (used by `session-stop-vault.sh`)
4. Saves a snapshot of the uncommitted changes that already exist (path + content hash), so the stop hook counts only changes made in this session
5. Loads the prior handoff and the project's Past Mistakes rules into the session context
6. Shows a "what's next" banner (next ticket, and the model and effort it needs) when the handoff names one
7. Prints a vault reminder so Claude loads context

Output is one JSON object: `additionalContext` for Claude, `systemMessage` for the banner. Without `jq` it falls back to plain text.

### `session-stop-vault.sh` — Journal Enforcement Hook
**When**: Every time Claude finishes a turn (`Stop` event) — but it only acts, and only blocks, when all of these hold:
1. The current project is onboarded to the vault (`Projects/$SLUG/` exists)
2. Code actually changed this session: an uncommitted change that is new since the session-start snapshot, or a commit since session start. Old uncommitted changes do not count. If the project has no session-start stamp (the session started in another folder), no work is known and the hook stays silent.
3. No dated session file exists yet for today (`Projects/$SLUG/Sessions/YYYY-MM-DD.md`)

If all three hold, it denies the stop and tells Claude exactly what to write before finishing — the session journal, the index entry, and any Decisions/Past Mistakes entries the session warrants. Capped at 2 nudges per session as a safety valve. Otherwise it's completely silent — this conditional design is deliberate; an earlier unconditional version fired after every single turn and was removed for being too noisy (see the vault's own `Projects/shipstack/Decisions/005-*.md`).

### `handoff-stale-check.sh` — Handoff Truth Check
**When**: Every `Stop`, after `session-stop-vault.sh`.
**What it does**: Blocks the stop once when `~/.shipstack/projects/$SLUG/handoff.md` names a `last_commit` or `branch` that is not the repo's real HEAD. Claude must then rewrite the handoff to match the live git state. It never loops (it skips a stop that a Stop hook already forced), and it is silent outside a git repo or when no handoff exists.

**Note**: `SessionEnd` cannot influence agent behavior (Claude Code ignores its exit code — it's cleanup-only, firing after the session is already over). `Stop` is the only event that can actually force Claude to act before yielding control back to the user, which is why this hook uses `Stop`, not `SessionEnd`.

## Installation

### 1. Copy hooks to your Claude config directory
```bash
cp hooks/session-start-vault.sh ~/.claude/hooks/
cp hooks/session-stop-vault.sh ~/.claude/hooks/
cp hooks/guard.sh ~/.claude/hooks/
cp hooks/handoff-stale-check.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

### 2. Add hooks to settings.json
Open `~/.claude/settings.json` and merge the contents of `settings-snippet.json` into your existing hooks configuration.

If you don't have a `settings.json` yet:
```bash
cp hooks/settings-snippet.json ~/.claude/settings.json
```

### 3. Customize
Edit `session-start-vault.sh` to:
- Add your own CLI tools to PATH
- Set project-specific env vars
- Customize the vault reminder message

## How Hooks Work

Claude Code hooks fire at lifecycle events:
- **SessionStart**: When a new conversation begins
- **Stop**: When Claude finishes responding to a turn — can still block/redirect Claude (`permissionDecision: "deny"`), since control hasn't returned to the user yet
- **SessionEnd**: When a conversation actually terminates — cleanup only, cannot influence behavior
- **PreToolUse**: Before a tool is executed
- **PostToolUse**: After a tool completes

Each hook entry has:
- `matcher`: Glob pattern to match (empty = match all)
- `hooks`: Array of commands to run

Commands can:
- Write to `$CLAUDE_ENV_FILE` to inject environment variables
- Print to stdout to send messages to Claude
- Exit with non-zero, or emit `{"hookSpecificOutput": {"permissionDecision": "deny", ...}}`, to block the action (`PreToolUse`) or force continuation (`Stop`)

## Writing Custom Hooks

```bash
#!/bin/bash
# Example: Pre-commit hook that reminds about past mistakes
echo "Check past-mistakes.md before committing. Any new lessons?"
```

For more on Claude Code hooks: https://docs.anthropic.com/en/docs/claude-code/hooks
