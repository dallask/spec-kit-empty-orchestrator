#!/bin/sh
# install.sh — install or refresh the Backlog Orchestrator extension into this repo.
#
# Idempotent. Safe to re-run.
#
# Effects:
#   * Copies config-template.yml → orchestrate-config.yml (only if absent)
#   * Syncs commands/speckit.orchestrate.md → .claude/skills/speckit-orchestrate/SKILL.md
#   * Syncs commands/speckit.sandbox.prepare.md → .claude/skills/speckit-sandbox-prepare/SKILL.md
#   * Syncs commands/speckit.sandbox.cleanup.md → .claude/skills/speckit-sandbox-cleanup/SKILL.md
#   * Syncs agents/orchestrate-{ba,dev}.md → .claude/agents/orchestrate-{ba,dev}.md
#   * Pre-creates runtime files (state.json, events.log) with mode 0600
#   * Ensures runtime dirs exist (worktrees/, schemas/)
#
# This script does NOT register the extension in .specify/extensions.yml —
# that is a separate concern handled by the Spec Kit installer.

set -u

_self_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
_repo_root="$(cd "$_self_dir/../../.." 2>/dev/null && pwd -P)"
EXT_ROOT="$_self_dir"
SKILLS_DST_ROOT="$_repo_root/.claude/skills"
AGENTS_DST="$_repo_root/.claude/agents"

err() { printf 'install: %s\n' "$1" >&2; exit "${2:-1}"; }
say() { printf 'install: %s\n' "$1"; }

# --- 1. orchestrate-config.yml ---
_cfg="$EXT_ROOT/orchestrate-config.yml"
_tmpl="$EXT_ROOT/config-template.yml"
if [ -f "$_cfg" ]; then
    say "orchestrate-config.yml exists; leaving as-is."
else
    [ -f "$_tmpl" ] || err "missing config-template.yml at $_tmpl"
    cp "$_tmpl" "$_cfg" || err "failed to copy config template"
    say "wrote $_cfg from template"
fi

# --- 2. Sync Skills (the user-facing slash commands) ---
# Each entry: "<command-source-basename>:<destination-skill-dir-basename>".
# Missing-source warnings are non-fatal so install stays idempotent during
# partial check-ins (e.g., the orchestrator skill exists but a sandbox
# skill source hasn't landed yet on this branch).
for _entry in \
    "speckit.orchestrate.md:speckit-orchestrate" \
    "speckit.sandbox.prepare.md:speckit-sandbox-prepare" \
    "speckit.sandbox.cleanup.md:speckit-sandbox-cleanup"
do
    _src_basename="${_entry%%:*}"
    _dst_basename="${_entry##*:}"
    _skill_src="$EXT_ROOT/commands/$_src_basename"
    _skill_dst_dir="$SKILLS_DST_ROOT/$_dst_basename"
    if [ -f "$_skill_src" ]; then
        mkdir -p "$_skill_dst_dir"
        cp "$_skill_src" "$_skill_dst_dir/SKILL.md" || err "failed to install Skill $_dst_basename"
        say "synced Skill: $_skill_dst_dir/SKILL.md"
    else
        say "WARNING: no commands/$_src_basename to sync (extension not fully built yet)"
    fi
done

# --- 3. Sync subagent definitions ---
mkdir -p "$AGENTS_DST"
for _a in orchestrate-ba orchestrate-dev; do
    _src="$EXT_ROOT/agents/$_a.md"
    _dst="$AGENTS_DST/$_a.md"
    if [ -f "$_src" ]; then
        cp "$_src" "$_dst" || err "failed to install subagent $_a"
        say "synced agent: $_dst"
    else
        say "WARNING: missing source agent $_src"
    fi
done

# --- 4. Pre-create runtime files with mode 0600 ---
mkdir -p "$EXT_ROOT/worktrees" "$EXT_ROOT/schemas"

# events.log starts empty — it's an append-only log.
_events="$EXT_ROOT/events.log"
if [ ! -e "$_events" ]; then
    (umask 077 && : >"$_events")
    chmod 0600 "$_events" 2>/dev/null || true
    say "created runtime file (mode 0600): $_events"
fi

# state.json starts with a canonical empty state, not a 0-byte file. A
# zero-byte file is technically "present" but is not valid JSON, which
# crashes downstream jq-based readers (reconcile-state.sh etc.) that
# read the file directly. Writing a valid empty document keeps every
# read path well-defined from install onward. State-read.sh's own
# initial-state shape is the single source of truth for the schema.
_state="$EXT_ROOT/state.json"
if [ ! -e "$_state" ] || [ ! -s "$_state" ]; then
    (umask 077 && cat >"$_state" <<'EOF'
{
  "schema_version": "1.0",
  "run_id": "",
  "created_at": "",
  "updated_at": "",
  "config_snapshot": {},
  "features": [],
  "counters": {"queued": 0, "running": 0, "blocked": 0, "failed": 0, "complete": 0},
  "events_log_path": "events.log"
}
EOF
    )
    chmod 0600 "$_state" 2>/dev/null || true
    say "created runtime file (mode 0600): $_state"
fi

say "install complete."
