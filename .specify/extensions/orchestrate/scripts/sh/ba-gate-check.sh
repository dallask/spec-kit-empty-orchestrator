#!/bin/sh
# ba-gate-check.sh — verify a feature's BA pipeline meets ba_gate.strictness.
#
# Usage (reads feature record from stdin as JSON):
#   echo "$FEATURE_JSON" | ba-gate-check.sh STRICTNESS
#     STRICTNESS = strict | trust | severity_based
#
# Exit 0 if the gate passes; exit 1 with an errorBody JSON on stderr otherwise.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

STRICTNESS="${1:-strict}"
case "$STRICTNESS" in
    strict|trust|severity_based) : ;;
    *) die "ba-gate-check: unknown strictness '$STRICTNESS'" ;;
esac

_feat="$(cat)"
if ! printf '%s' "$_feat" | jq . >/dev/null 2>&1; then
    die "ba-gate-check: stdin is not valid JSON"
fi

_fid="$(printf '%s' "$_feat" | jq -r '.id')"
_pending="$(printf '%s' "$_feat" | jq -r '.pending_clarification == null')"
_last_type="$(printf '%s' "$_feat" | jq -r '.last_payload.payload_type // "missing"')"
_ba_done="$(printf '%s' "$_feat" | jq -r '.last_payload.body.ba_done // false')"
_spec_path="$(printf '%s' "$_feat" | jq -r '.spec_file_path // ""')"
_worktree="$(printf '%s' "$_feat" | jq -r '.worktree_path // ""')"

emit_gate_failure() {
    _code="$1"
    _msg="$2"
    jq -n --arg fid "$_fid" --arg code "$_code" --arg msg "$_msg" --arg s "$STRICTNESS" '
        {code:$code, message:$msg, recoverable:true, details:{feature_id:$fid, strictness:$s}}
    ' >&2
    exit 1
}

case "$STRICTNESS" in
    trust)
        if [ "$_last_type" != "result" ] || [ "$_ba_done" != "true" ]; then
            emit_gate_failure "ba_gate_failed" "trust gate: BA must emit result with ba_done=true (got payload_type=$_last_type, ba_done=$_ba_done)"
        fi
        ;;
    strict)
        if [ "$_pending" != "true" ]; then
            emit_gate_failure "ba_gate_failed" "strict gate: feature has an open clarification"
        fi
        if [ "$_last_type" != "result" ] || [ "$_ba_done" != "true" ]; then
            emit_gate_failure "ba_gate_failed" "strict gate: BA must emit result with ba_done=true"
        fi
        # All four artifacts must exist on disk.
        _spec_dir="$(dirname "$_spec_path")"
        for _f in spec.md plan.md tasks.md; do
            if [ ! -f "$_spec_dir/$_f" ]; then
                emit_gate_failure "ba_gate_failed" "strict gate: missing artifact $_f at $_spec_dir/$_f"
            fi
        done
        # Analyze artifact: accept either analysis.md or analyze.md (Spec Kit
        # implementations have varied).
        if [ ! -f "$_spec_dir/analysis.md" ] && [ ! -f "$_spec_dir/analyze.md" ]; then
            emit_gate_failure "ba_gate_failed" "strict gate: missing analyze report in $_spec_dir/"
        fi
        ;;
    severity_based)
        if [ "$_last_type" != "result" ]; then
            emit_gate_failure "ba_gate_failed" "severity_based gate: BA must emit a result payload"
        fi
        _critical="$(printf '%s' "$_feat" | jq -r '.last_payload.body.artifacts.analyze_severity_summary.critical // 0')"
        _high="$(printf '%s' "$_feat" | jq -r '.last_payload.body.artifacts.analyze_severity_summary.high // 0')"
        if [ "$_critical" -gt 0 ] || [ "$_high" -gt 0 ]; then
            emit_gate_failure "ba_gate_failed" "severity_based gate: analyze report has $_critical CRITICAL + $_high HIGH findings"
        fi
        ;;
esac

# Pass: emit a single OK line on stdout.
jq -n --arg fid "$_fid" --arg s "$STRICTNESS" '{status:"pass", feature_id:$fid, strictness:$s}'
exit 0
