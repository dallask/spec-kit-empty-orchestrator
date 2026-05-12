#!/usr/bin/env bats
# Integration fixtures — structure-validate each fixture and confirm replay
# JSONs are schema-valid AgentPayload envelopes.
#
# This bats suite does NOT drive the actual Lead Skill end-to-end (that
# requires a live Claude Code session). It validates the fixture is well-formed
# and is ready to be consumed when the Lead grows ORCHESTRATE_SUBAGENT_RUNNER
# support (research.md §13).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    SCHEMAS="$REPO_ROOT/.specify/extensions/orchestrate/schemas"
    MOCK="$BATS_TEST_DIRNAME/mock-subagent.sh"
}

@test "every fixture directory has the required files" {
    for f in "$FIXTURES"/*/; do
        [ -f "$f/BACKLOG.md" ]
        [ -d "$f/replay" ]
        [ -f "$f/expected-state.json" ]
    done
}

@test "every replay JSON is valid JSON" {
    for j in "$FIXTURES"/*/replay/*.json; do
        jq . "$j" >/dev/null
    done
}

@test "every replay JSON has the AgentPayload required envelope fields" {
    for j in "$FIXTURES"/*/replay/*.json; do
        for field in schema_version feature_id agent_role phase payload_type body timestamp; do
            if ! jq -e ". | has(\"$field\")" "$j" >/dev/null; then
                echo "MISSING $field in $j" >&2
                return 1
            fi
        done
    done
}

@test "replay file naming matches its declared envelope" {
    for j in "$FIXTURES"/*/replay/*.json; do
        _base="$(basename "$j" .json)"
        _expected_fid="$(printf '%s' "$_base" | cut -d- -f1)"
        _expected_role="$(printf '%s' "$_base" | cut -d- -f2)"
        _real_fid="$(jq -r .feature_id "$j")"
        _real_role="$(jq -r .agent_role "$j")"
        [ "$_expected_fid" = "$_real_fid" ]
        [ "$_expected_role" = "$_real_role" ]
    done
}

@test "mock-subagent.sh returns the canned payload for a known (id,role,1) tuple" {
    ORCHESTRATE_FIXTURE_DIR="$FIXTURES/three-clean-items" \
    FEATURE_ID="001" \
    AGENT_ROLE="ba" \
    INVOCATION_COUNT="1" \
    "$MOCK" | jq .feature_id | grep -q '"001"'
}
