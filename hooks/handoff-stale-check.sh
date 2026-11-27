#!/bin/bash
# handoff-stale-check: Stop hook. Warns Claude, once per stop, when the project handoff names a
# commit or a branch that is not the repo's real HEAD.
#
# Why: a handoff can still name an old commit after Claude says it updated the handoff. A grep
# proves that a line exists, never that no other line contradicts it. This hook compares the
# two facts that must always be true: the handoff's last_commit/branch and the real HEAD.
#
# It blocks the stop (so Claude must fix the handoff) only when ALL of these hold:
#   1. the cwd is inside a git repo, and ~/.shipstack/projects/<slug>/handoff.md exists
#   2. this stop is not already a continuation forced by a Stop hook (stop_hook_active), so it
#      can never loop
#   3. the first word of `last_commit:` is not a commit id that HEAD starts with, OR the first
#      word of `branch:` is not the current branch (skipped when HEAD is detached)
# A handoff with no readable last_commit counts as stale: a silent pass would hide it.
#
# Output: the Stop-event shape, a top-level {"decision":"block","reason":...} (the same shape
# session-stop-vault.sh uses, which works). Install: see README.md next to this file.

INPUT=$(cat)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$(pwd)"
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)

git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# The project slug, the same way session-stop-vault.sh finds it.
SLUG=""
REMOTE=$(git -C "$CWD" remote get-url origin 2>/dev/null)
[ -n "$REMOTE" ] && SLUG=$(basename "$REMOTE" .git)
[ -z "$SLUG" ] && SLUG=$(basename "$(git -C "$CWD" rev-parse --show-toplevel)")

HANDOFF="$HOME/.shipstack/projects/$SLUG/handoff.md"
[ -f "$HANDOFF" ] || exit 0

HEAD=$(git -C "$CWD" rev-parse HEAD 2>/dev/null) || exit 0
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)

# The first word after "key:" on the first line that starts with it.
field() {
    grep -m1 "^$1:" "$HANDOFF" | sed "s/^$1:[[:space:]]*//" | awk '{print $1}'
}
NAMED_COMMIT=$(field last_commit)
NAMED_BRANCH=$(field branch)

PROBLEMS=""
if ! printf '%s' "$NAMED_COMMIT" | grep -Eiq '^[0-9a-f]{7,40}$'; then
    PROBLEMS="last_commit does not start with a commit id (it says \"${NAMED_COMMIT:-nothing}\"); HEAD is ${HEAD:0:7}."
else
    case "$HEAD" in
        "$(printf '%s' "$NAMED_COMMIT" | tr 'A-F' 'a-f')"*) ;;
        *) PROBLEMS="last_commit names $NAMED_COMMIT, but HEAD is ${HEAD:0:7}." ;;
    esac
fi
if [ -n "$BRANCH" ] && [ "$NAMED_BRANCH" != "$BRANCH" ]; then
    PROBLEMS="$PROBLEMS branch names \"${NAMED_BRANCH:-nothing}\", but the current branch is $BRANCH."
fi
PROBLEMS=$(printf '%s' "$PROBLEMS" | sed 's/^ //')

[ -z "$PROBLEMS" ] && exit 0

if [ "$ACTIVE" = "true" ]; then
    # Already continuing because of a Stop hook: warn only, never loop.
    echo "handoff-stale-check: the handoff is still stale: $PROBLEMS" >&2
    exit 0
fi

REASON="The handoff is stale: $PROBLEMS Before stopping: update $HANDOFF. Rewrite its frontmatter (branch, last_commit, pipeline_stage, last_run) and section 0 (the facts to check, what is done, the next step) to match the live git state; do not only append a bullet. Then read section 0 and the frontmatter top to bottom, and remove every statement that is no longer true."
jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
