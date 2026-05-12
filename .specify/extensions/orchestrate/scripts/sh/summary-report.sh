#!/bin/sh
# summary-report.sh — emit a human-readable Markdown table of every feature's
# terminal status + key artifact paths, plus a counters footer and a
# cross-check against state.counters (warn on mismatch).
#
# Usage: summary-report.sh
# Output: Markdown table to stdout.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

_state="$("$_dir/state-read.sh")"
_count="$(printf '%s' "$_state" | jq '.features | length')"

# Header.
printf '# Orchestrator run summary\n\n'
printf 'Run ID: `%s`  \n' "$(printf '%s' "$_state" | jq -r '.run_id')"
printf 'Updated: `%s`  \n' "$(printf '%s' "$_state" | jq -r '.updated_at')"
printf 'Features tracked: **%d**\n\n' "$_count"

if [ "$_count" = "0" ]; then
    printf '_No features in state. Nothing to report._\n'
    exit 0
fi

# Feature table.
printf '| ID | Title | Phase | Status | Branch | Worktree | Spec | Target Commit | Open Question |\n'
printf '|----|-------|-------|--------|--------|----------|------|---------------|---------------|\n'

# Build each row via jq -r so we can include conditional logic.
printf '%s' "$_state" | jq -r '
    def trunc($n): if . == null then "—" elif (. | length) > $n then (.[0:$n] + "…") else . end;

    .features | sort_by(.id)[] | [
        .id,
        (.original_title // .title) | trunc(40),
        .phase,
        .status,
        (.branch_name // "—"),
        ((.worktree_path // "—") | trunc(48)),
        ((.spec_file_path // "—") | trunc(48)),
        (.target_commit // "—" | if . == "—" then . else .[0:7] end),
        ((.pending_clarification.question // "") | trunc(60) | if . == "" then "—" else . end)
    ] | "| " + (map(tostring) | join(" | ")) + " |"
'

# Counters footer.
_c="$(printf '%s' "$_state" | jq .counters)"
_q="$(printf '%s' "$_c" | jq -r .queued)"
_r="$(printf '%s' "$_c" | jq -r .running)"
_b="$(printf '%s' "$_c" | jq -r .blocked)"
_f="$(printf '%s' "$_c" | jq -r .failed)"
_cmp="$(printf '%s' "$_c" | jq -r .complete)"

printf '\n## Counters\n\n'
printf '| Queued | Running | Blocked | Failed | Complete |\n'
printf '|--------|---------|---------|--------|----------|\n'
printf '|   %s   |    %s   |    %s   |   %s   |    %s    |\n' "$_q" "$_r" "$_b" "$_f" "$_cmp"

# Cross-check: counter sum vs feature count.
_sum=$((_q + _r + _b + _f + _cmp))
if [ "$_sum" -ne "$_count" ]; then
    printf '\n> **WARNING:** counters sum to %d but state has %d features. Possible corruption.\n' "$_sum" "$_count"
fi
