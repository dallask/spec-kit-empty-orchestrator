#!/bin/sh
# mock-subagent.sh — fixture-replay test helper that imitates a Claude Code
# subagent invocation by returning a canned JSON payload from disk.
#
# Usage in an integration test:
#   ORCHESTRATE_SUBAGENT_RUNNER="$PWD/mock-subagent.sh" \
#   ORCHESTRATE_FIXTURE_DIR="$PWD/fixtures/three-clean-items" \
#   sh some-test-driver.sh
#
# The runner is called with environment:
#   ORCHESTRATE_FIXTURE_DIR     — fixture directory containing replay/
#   FEATURE_ID                  — e.g. "001"
#   AGENT_ROLE                  — "ba" or "dev"
#   INVOCATION_COUNT            — 1, 2, 3 ... (for re-spawns after clarification)
#
# It locates and prints the file replay/<FEATURE_ID>-<AGENT_ROLE>-<N>.json.
# Exits 0 on hit, 1 if no canned response exists for that key.
#
# NOTE: This helper is reference-grade for now. The actual Lead Skill body does
# not yet read ORCHESTRATE_SUBAGENT_RUNNER — that wiring is a future enhancement
# (documented as v2 in research.md §13). Until then, the fixture is documentation
# of the expected payload sequence + a target for schema-validation in CI.

set -u

FIXTURE_DIR="${ORCHESTRATE_FIXTURE_DIR:-}"
FEATURE_ID="${FEATURE_ID:-}"
AGENT_ROLE="${AGENT_ROLE:-}"
N="${INVOCATION_COUNT:-1}"

[ -n "$FIXTURE_DIR" ] || { echo "mock-subagent: ORCHESTRATE_FIXTURE_DIR not set" >&2; exit 2; }
[ -n "$FEATURE_ID"  ] || { echo "mock-subagent: FEATURE_ID not set" >&2;  exit 2; }
[ -n "$AGENT_ROLE"  ] || { echo "mock-subagent: AGENT_ROLE not set" >&2;  exit 2; }

_file="$FIXTURE_DIR/replay/${FEATURE_ID}-${AGENT_ROLE}-${N}.json"
if [ ! -r "$_file" ]; then
    echo "mock-subagent: no canned response at $_file" >&2
    exit 1
fi

cat "$_file"
