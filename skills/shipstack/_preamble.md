# ShipStack Shared Preamble

Before executing this skill, perform these setup steps silently (do not print preamble steps to user):

## 1. Load Config

Read `~/.shipstack/config.yaml`. If it doesn't exist, use these defaults:
- `vault_path`: `~/ProductBrain/Projects` (user's knowledge vault)
- `default_scope_mode`: `HOLD`
- `guard_enabled`: `true`

## 2. Compute Project Slug

Determine `$SLUG` for the current project:
1. Try: `git remote get-url origin` → extract repo name (e.g., `github.com/user/my-app` → `my-app`)
2. Fallback: basename of current working directory

## 3. Ensure Pipeline Directory

Create if not exists:
```
~/.shipstack/projects/$SLUG/designs/
~/.shipstack/projects/$SLUG/challenges/
~/.shipstack/projects/$SLUG/plan-reviews/
~/.shipstack/projects/$SLUG/investigations/
```

## 4. Read Session State

If `~/.shipstack/projects/$SLUG/handoff.md` exists, read it. Note:
- `pipeline_stage` — where we are in the pipeline
- `scope_mode` — current gear (EXPAND/SELECTIVE/HOLD/REDUCE)
- `branch` — what branch we're working on
- Open decisions and unfinished work

## 5. Load Knowledge (from vault)

Using `vault_path` from config, project folder is `$vault_path/$SLUG/`:
1. Read `PRD.md` (if exists) in full — store as `$PRD`. This is the spec source of truth for drift checks.
2. Read `Architecture.md` (if exists) in full — store as `$ARCHITECTURE`
3. Read `Past Mistakes and Lessons.md` (if exists) in full — store as `$PAST_MISTAKES`
4. Read `Decisions.md` (the index, if exists) — store as `$DECISIONS`. Also read the single most-recently-added file it links to under `Decisions/` for full detail.
5. Read `Sessions.md` (the index, if exists) — store as `$SESSIONS`. Also read the single most-recently-added file it links to under `Sessions/` — store as `$LAST_SESSION`.

If the vault path or project folder doesn't exist, that's fine — proceed without knowledge context. Skills still work, just without accumulated knowledge.

## 6. Log Skill Usage

Append to `~/.shipstack/analytics/skill-usage.jsonl`:
```json
{"skill": "$SKILL_NAME", "project": "$SLUG", "timestamp": "ISO8601", "branch": "$BRANCH"}
```
