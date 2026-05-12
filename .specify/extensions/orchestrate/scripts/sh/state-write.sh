#!/bin/sh
# state-write.sh — atomic mode-0600 write of state.json from stdin.
#
# Reads a candidate state document from stdin, recomputes `counters` from
# `features[]`, refreshes `updated_at`, and atomically writes to state.json
# with file mode 0600.
#
# Usage:  state-write.sh < new-state.json

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"

jq_required

_path="$(orchestrate_state_path)"
_in="$(cat)"

# Validate JSON.
if ! printf '%s' "$_in" | jq . >/dev/null 2>&1; then
    die "state-write: stdin is not valid JSON"
fi

# Recompute counters and updated_at via jq.
_out="$(printf '%s' "$_in" | jq --arg now "$(iso_now)" '
    .updated_at = $now
    | .counters = {
        queued:   ([.features[]? | select(.status=="queued")]   | length),
        running:  ([.features[]? | select(.status=="running")]  | length),
        blocked:  ([.features[]? | select(.status=="blocked")]  | length),
        failed:   ([.features[]? | select(.status=="failed")]   | length),
        complete: ([.features[]? | select(.status=="complete")] | length)
    }
')"

# Sanity check: counters sum to features length.
_total_counters="$(printf '%s' "$_out" | jq '[.counters[]] | add // 0')"
_total_features="$(printf '%s' "$_out" | jq '.features | length')"
if [ "$_total_counters" != "$_total_features" ]; then
    die "state-write: counter sum ($_total_counters) does not match features length ($_total_features)"
fi

# Ensure parent directory exists (orchestrate root).
mkdir -p "$(dirname "$_path")"

# Atomic write with mode 0600.
printf '%s\n' "$_out" | atomic_write_0600 "$_path"
