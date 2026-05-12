#!/bin/sh
# emit-event.sh — append one status event to events.log AND echo to stdout.
#
# Usage:
#   emit-event.sh FEATURE_ID PHASE STATUS NOTE
#
# Format (per data-model.md §6):
#   <ISO-8601-UTC> feature=<id> phase=<phase> status=<status> note="<truncated-text>"
#
# Run-level events use FEATURE_ID="-" PHASE="-" STATUS="-".
# The events log is mode 0600 on first creation (per research.md §11 / FR-F1).

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"

[ "$#" -ge 4 ] || die "emit-event: usage: FEATURE_ID PHASE STATUS NOTE"

_fid="$1"
_phase="$2"
_status="$3"
_note="$4"

# Truncate note to ≤ 200 chars (data-model.md §6) and strip newlines.
_note="$(printf '%s' "$_note" | tr '\n\r' '  ' | cut -c1-200)"

_line="$(iso_now) feature=$_fid phase=$_phase status=$_status note=\"$_note\""

_log="$(orchestrate_events_path)"
mkdir -p "$(dirname "$_log")"

# Create with mode 0600 on first write. Append mode for subsequent writes.
if [ ! -e "$_log" ]; then
    (umask 077 && : >"$_log") || die "emit-event: failed to create $_log"
    chmod 0600 "$_log" 2>/dev/null || true
fi

# Append line.
printf '%s\n' "$_line" >>"$_log"
# Echo to stdout too.
printf '%s\n' "$_line"
