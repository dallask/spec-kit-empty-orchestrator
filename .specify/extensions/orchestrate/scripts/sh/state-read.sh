#!/bin/sh
# state-read.sh — read orchestrator state.json with a jq-based shape check.
#
# Usage: state-read.sh
# Output: JSON state document on stdout. If state.json is missing, emits an
#         initial empty state.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"

jq_required

_path="$(orchestrate_state_path)"
_run_id="${ORCHESTRATE_RUN_ID:-orchestrate-$(iso_now)}"

_emit_initial_state() {
    jq -n --arg now "$(iso_now)" --arg runid "$_run_id" '
        {
            schema_version: "1.0",
            run_id: $runid,
            created_at: $now,
            updated_at: $now,
            config_snapshot: {},
            features: [],
            counters: {queued: 0, running: 0, blocked: 0, failed: 0, complete: 0},
            events_log_path: "events.log"
        }
    '
}

# Missing OR zero-byte → emit initial state.
if [ ! -r "$_path" ] || [ ! -s "$_path" ]; then
    _emit_initial_state
    exit 0
fi

# Whitespace-only files are also treated as "no state yet" — they
# happen in practice when install.sh from older revisions produced an
# empty file, or when an interrupted write left an empty placeholder.
_state="$(cat "$_path")"
if [ -z "$(printf '%s' "$_state" | tr -d '[:space:]')" ]; then
    _emit_initial_state
    exit 0
fi
if ! printf '%s' "$_state" | jq . >/dev/null 2>&1; then
    die "state-read: $_path is not valid JSON"
fi

# Shape check using jq.
_missing="$(printf '%s' "$_state" | jq -r '
    [
        if has("schema_version")  then empty else "schema_version"  end,
        if has("run_id")          then empty else "run_id"          end,
        if has("features") and (.features | type == "array") then empty else "features" end,
        if has("counters")        then empty else "counters"        end
    ] | .[]
')"
if [ -n "$_missing" ]; then
    die "state-read: $_path is missing required fields: $_missing"
fi

# Schema version compatibility.
_sv="$(printf '%s' "$_state" | jq -r .schema_version)"
if [ "$_sv" != "1.0" ]; then
    die "state-read: $_path has schema_version=$_sv but this extension expects 1.0; run a migration first"
fi

printf '%s\n' "$_state"
