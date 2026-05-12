#!/bin/sh
# install.sh — install or refresh the Backlog Orchestrator extension into this repo.
#
# Idempotent. Safe to re-run.
#
# Effects:
#   * Copies config-template.yml → orchestrate-config.yml (only if absent)
#   * Syncs commands/speckit.orchestrate.md → .claude/skills/speckit-orchestrate/SKILL.md
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
SKILL_DST="$_repo_root/.claude/skills/speckit-orchestrate"
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

# --- 2. Sync Skill (the user-facing /speckit-orchestrate slash command) ---
_skill_src="$EXT_ROOT/commands/speckit.orchestrate.md"
if [ -f "$_skill_src" ]; then
    mkdir -p "$SKILL_DST"
    cp "$_skill_src" "$SKILL_DST/SKILL.md" || err "failed to install Skill"
    say "synced Skill: $SKILL_DST/SKILL.md"
else
    say "WARNING: no commands/speckit.orchestrate.md to sync (extension not fully built yet)"
fi

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

for _f in "$EXT_ROOT/state.json" "$EXT_ROOT/events.log"; do
    if [ ! -e "$_f" ]; then
        (umask 077 && : >"$_f")
        chmod 0600 "$_f" 2>/dev/null || true
        say "created runtime file (mode 0600): $_f"
    fi
done

say "install complete."
