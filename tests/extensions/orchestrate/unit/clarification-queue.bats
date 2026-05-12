#!/usr/bin/env bats
# T031: clarification-queue.sh unit tests.
# Uses a per-test ORCHESTRATE_ROOT pointing at a fresh tmp dir.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
    ORCH_DIR="$REPO_ROOT/.specify/extensions/orchestrate"
    TMP="$(mktemp -d -t orchestrate-cq-test.XXXXXX)"
    mkdir -p "$TMP/schemas" "$TMP/scripts/sh"
    cp "$ORCH_DIR/scripts/sh/"*.sh "$TMP/scripts/sh/"
    cp "$ORCH_DIR/schemas/"*.json "$TMP/schemas/"
    chmod +x "$TMP/scripts/sh/"*.sh
    CQ="$TMP/scripts/sh/clarification-queue.sh"
    WRITE="$TMP/scripts/sh/state-write.sh"
}

teardown() {
    rm -rf "$TMP"
}

# Helper: seed a state file with three features in known phases.
seed_state() {
    jq -n --arg now "2026-05-12T00:00:00Z" '
        {
            schema_version: "1.0",
            run_id: "test",
            created_at: $now,
            updated_at: $now,
            config_snapshot: {},
            features: [
                {id:"001", title:"a", original_title:"A", description:"", worktree_path:"/x/1", branch_name:"001-a", spec_file_path:"/x/1/spec.md", phase:"ba", status:"running", last_payload:null, pending_clarification:null, created_at:$now, updated_at:$now, target_commit:null},
                {id:"002", title:"b", original_title:"B", description:"", worktree_path:"/x/2", branch_name:"002-b", spec_file_path:"/x/2/spec.md", phase:"ba", status:"running", last_payload:null, pending_clarification:null, created_at:$now, updated_at:$now, target_commit:null},
                {id:"003", title:"c", original_title:"C", description:"", worktree_path:"/x/3", branch_name:"003-c", spec_file_path:"/x/3/spec.md", phase:"ba", status:"running", last_payload:null, pending_clarification:null, created_at:$now, updated_at:$now, target_commit:null}
            ],
            counters: {queued: 0, running: 3, blocked: 0, failed: 0, complete: 0},
            events_log_path: "events.log"
        }
    ' | "$WRITE"
}

@test "list returns empty when no features are blocked" {
    seed_state
    run "$CQ" list
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq 'length')" -eq 0 ]
}

@test "enqueue transitions a feature to (ba, blocked) and saves pending_clarification" {
    seed_state
    body='{"question":"foo?","context":"ctx","options":["a","b"],"correlation_id":"002-clarify-x"}'
    printf '%s' "$body" | "$CQ" enqueue 002
    [ "$?" -eq 0 ]
    phase="$(jq -r '.features[] | select(.id=="002") | .phase' "$TMP/state.json")"
    status="$(jq -r '.features[] | select(.id=="002") | .status' "$TMP/state.json")"
    pending_q="$(jq -r '.features[] | select(.id=="002") | .pending_clarification.question' "$TMP/state.json")"
    [ "$phase" = "ba" ]
    [ "$status" = "blocked" ]
    [ "$pending_q" = "foo?" ]
}

@test "list returns blocked features ordered by feature id ascending" {
    seed_state
    body3='{"question":"q3","context":"c","correlation_id":"003-x"}'
    body1='{"question":"q1","context":"c","correlation_id":"001-x"}'
    printf '%s' "$body3" | "$CQ" enqueue 003
    printf '%s' "$body1" | "$CQ" enqueue 001
    run "$CQ" list
    [ "$status" -eq 0 ]
    first_id="$(printf '%s' "$output" | jq -r '.[0].feature_id')"
    second_id="$(printf '%s' "$output" | jq -r '.[1].feature_id')"
    [ "$first_id" = "001" ]
    [ "$second_id" = "003" ]
}

@test "peek returns the lowest-id blocked feature" {
    seed_state
    printf '%s' '{"question":"q","context":"c","correlation_id":"002-x"}' | "$CQ" enqueue 002
    printf '%s' '{"question":"q","context":"c","correlation_id":"001-x"}' | "$CQ" enqueue 001
    run "$CQ" peek
    [ "$status" -eq 0 ]
    id="$(printf '%s' "$output" | jq -r '.feature_id')"
    [ "$id" = "001" ]
}

@test "dequeue emits a clarification_answer body and clears the pending slot" {
    seed_state
    printf '%s' '{"question":"What channels?","context":"c","correlation_id":"002-cl-1"}' | "$CQ" enqueue 002
    run "$CQ" dequeue 002 "in-app + email"
    [ "$status" -eq 0 ]
    ans="$(printf '%s' "$output" | jq -r '.answer')"
    q="$(printf '%s' "$output" | jq -r '.original_question')"
    [ "$ans" = "in-app + email" ]
    [ "$q" = "What channels?" ]
    # State should now show 002 back to (ba, running) with null pending_clarification.
    phase="$(jq -r '.features[] | select(.id=="002") | .phase' "$TMP/state.json")"
    status="$(jq -r '.features[] | select(.id=="002") | .status' "$TMP/state.json")"
    pending="$(jq -r '.features[] | select(.id=="002") | .pending_clarification' "$TMP/state.json")"
    [ "$phase" = "ba" ]
    [ "$status" = "running" ]
    [ "$pending" = "null" ]
}

@test "dequeue on a feature with no pending clarification fails" {
    seed_state
    run "$CQ" dequeue 002 "x"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "no pending_clarification"
}

@test "dequeue on an unknown feature id fails" {
    seed_state
    run "$CQ" dequeue 999 "x"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "not found"
}
