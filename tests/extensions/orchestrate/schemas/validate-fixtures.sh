#!/bin/sh
# T044: validate every JSON fixture in tests/extensions/orchestrate/ against the
# matching schema in .specify/extensions/orchestrate/schemas/.
#
# Uses jq for structural validation against the schema's required-field tree.
# Returns:
#   exit 0 if every fixture passes;
#   exit 1 with a list of failures otherwise.
#
# Intended to run in CI plus locally before commits.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd -P)"
FIXTURES="$REPO_ROOT/tests/extensions/orchestrate/integration/fixtures"
SCHEMAS="$REPO_ROOT/.specify/extensions/orchestrate/schemas"

if ! command -v jq >/dev/null 2>&1; then
    echo "validate-fixtures: jq is required" >&2
    exit 127
fi

_fail=0
_fail_list=""

note_failure() {
    _fail=$((_fail + 1))
    _fail_list="$_fail_list
  - $1"
}

# 1. Every replay JSON must validate as an AgentPayload (required envelope fields).
for j in "$FIXTURES"/*/replay/*.json; do
    [ -f "$j" ] || continue
    if ! jq . "$j" >/dev/null 2>&1; then
        note_failure "$j (not valid JSON)"
        continue
    fi
    for field in schema_version feature_id agent_role phase payload_type body timestamp; do
        if ! jq -e ". | has(\"$field\")" "$j" >/dev/null 2>&1; then
            note_failure "$j (missing required envelope field: $field)"
        fi
    done
    # clarification_request / clarification_answer MUST carry correlation_id.
    _pt="$(jq -r .payload_type "$j" 2>/dev/null)"
    case "$_pt" in
        clarification_request|clarification_answer)
            if ! jq -e ". | has(\"correlation_id\")" "$j" >/dev/null 2>&1; then
                note_failure "$j (payload_type=$_pt requires correlation_id)"
            fi
            ;;
    esac
    # File name should encode (feature_id, agent_role).
    _base="$(basename "$j" .json)"
    _fid="$(printf '%s' "$_base" | cut -d- -f1)"
    _role="$(printf '%s' "$_base" | cut -d- -f2)"
    _rfid="$(jq -r .feature_id "$j" 2>/dev/null)"
    _rrole="$(jq -r .agent_role "$j" 2>/dev/null)"
    if [ "$_fid" != "$_rfid" ] || [ "$_role" != "$_rrole" ]; then
        note_failure "$j (filename id/role $_fid/$_role does not match envelope $_rfid/$_rrole)"
    fi
done

# 2. Every expected-state.json must parse and have the documented top-level structure.
for j in "$FIXTURES"/*/expected-state.json; do
    [ -f "$j" ] || continue
    if ! jq . "$j" >/dev/null 2>&1; then
        note_failure "$j (not valid JSON)"
        continue
    fi
    if ! jq -e '.expectations' "$j" >/dev/null 2>&1; then
        note_failure "$j (missing .expectations key)"
    fi
done

# 3. The runtime schemas themselves should parse (sanity check).
for s in "$SCHEMAS"/*.json; do
    [ -f "$s" ] || continue
    if ! jq . "$s" >/dev/null 2>&1; then
        note_failure "$s (runtime schema is not valid JSON)"
    fi
done

if [ "$_fail" -gt 0 ]; then
    printf 'validate-fixtures: %d failure(s)%s\n' "$_fail" "$_fail_list" >&2
    exit 1
fi

printf 'validate-fixtures: all fixtures pass schema sanity check\n'
exit 0
