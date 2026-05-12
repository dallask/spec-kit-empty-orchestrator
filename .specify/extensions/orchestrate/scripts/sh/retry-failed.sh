#!/bin/sh
# retry-failed.sh — reset every feature with status=failed back to
# (phase=ba, status=queued) and clear last_payload. Used by --retry-failed.
#
# Output: number of features reset, on stdout.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

_state="$("$_dir/state-read.sh")"
_count_before="$(printf '%s' "$_state" | jq '[.features[] | select(.status=="failed")] | length')"

_now="$(iso_now)"
printf '%s' "$_state" | jq --arg now "$_now" '
    .features |= map(
        if .status == "failed" then
            .phase = "ba"
            | .status = "queued"
            | .last_payload = null
            | .pending_clarification = null
            | .updated_at = $now
        else . end
    )
' | "$_dir/state-write.sh"

jq -n --argjson n "$_count_before" '{reset_count: $n, message: ("Reset " + ($n|tostring) + " failed features to (phase=ba, status=queued).")}'
