#!/usr/bin/env bats
# T015: state-read.sh + state-write.sh unit tests.
# Uses a per-test ORCHESTRATE_ROOT pointing at a fresh tmp dir so we never
# touch the real extension state file.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
    ORCH_DIR="$REPO_ROOT/.specify/extensions/orchestrate"
    READ="$ORCH_DIR/scripts/sh/state-read.sh"
    WRITE="$ORCH_DIR/scripts/sh/state-write.sh"

    TMP="$(mktemp -d -t orchestrate-state-test.XXXXXX)"
    # Provide a fresh schemas dir + a fake "orchestrate root" so callers don't
    # touch the real state file.
    mkdir -p "$TMP/schemas" "$TMP/scripts/sh"
    cp "$ORCH_DIR/scripts/sh/orchestrate-common.sh" "$TMP/scripts/sh/"
    cp "$ORCH_DIR/scripts/sh/state-read.sh" "$TMP/scripts/sh/"
    cp "$ORCH_DIR/scripts/sh/state-write.sh" "$TMP/scripts/sh/"
    cp "$ORCH_DIR/schemas/"*.json "$TMP/schemas/"
    chmod +x "$TMP/scripts/sh/"*.sh

    READ="$TMP/scripts/sh/state-read.sh"
    WRITE="$TMP/scripts/sh/state-write.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "read on missing state returns valid initial state" {
    run "$READ"
    [ "$status" -eq 0 ]
    sv="$(printf '%s' "$output" | jq -r .schema_version)"
    feat="$(printf '%s' "$output" | jq '.features | length')"
    [ "$sv" = "1.0" ]
    [ "$feat" -eq 0 ]
}

@test "round-trip: read → write produces a 0600 state.json" {
    "$READ" | "$WRITE"
    [ -e "$TMP/state.json" ]
    mode="$(stat -f %Lp "$TMP/state.json" 2>/dev/null || stat -c %a "$TMP/state.json")"
    [ "$mode" = "600" ]
}

@test "counters are recomputed from features array on write" {
    state="$(jq -n '
        {
            schema_version: "1.0",
            run_id: "test",
            created_at: "2026-05-12T00:00:00Z",
            updated_at: "2026-05-12T00:00:00Z",
            config_snapshot: {},
            features: [
                {id:"001", title:"a", original_title:"A", description:"", worktree_path:"/x/1", branch_name:"001-a", spec_file_path:"/x/1/spec.md", phase:"ba", status:"queued", last_payload:null, pending_clarification:null, created_at:"2026-05-12T00:00:00Z", updated_at:"2026-05-12T00:00:00Z", target_commit:null},
                {id:"002", title:"b", original_title:"B", description:"", worktree_path:"/x/2", branch_name:"002-b", spec_file_path:"/x/2/spec.md", phase:"ba", status:"running", last_payload:null, pending_clarification:null, created_at:"2026-05-12T00:00:00Z", updated_at:"2026-05-12T00:00:00Z", target_commit:null},
                {id:"003", title:"c", original_title:"C", description:"", worktree_path:"/x/3", branch_name:"003-c", spec_file_path:"/x/3/spec.md", phase:"done", status:"complete", last_payload:null, pending_clarification:null, created_at:"2026-05-12T00:00:00Z", updated_at:"2026-05-12T00:00:00Z", target_commit:"deadbeef"}
            ],
            counters: {queued: 99, running: 99, blocked: 99, failed: 99, complete: 99},
            events_log_path: "events.log"
        }
    ')"
    printf '%s' "$state" | "$WRITE"
    [ "$status" -eq 0 ]
    q="$(jq -r '.counters.queued' "$TMP/state.json")"
    r="$(jq -r '.counters.running' "$TMP/state.json")"
    c="$(jq -r '.counters.complete' "$TMP/state.json")"
    [ "$q" = "1" ]
    [ "$r" = "1" ]
    [ "$c" = "1" ]
}

@test "atomic-write durability: state file is intact even after a tmp file exists" {
    "$READ" | "$WRITE"
    # Simulate a stale tmp from a previous interrupted run.
    : > "$TMP/state.json.tmp.9999"
    "$READ" | "$WRITE"
    # Real state still parses.
    jq . "$TMP/state.json" >/dev/null
    [ "$?" -eq 0 ]
}

@test "write rejects malformed JSON input" {
    run bash -c 'printf "not json" | '"$WRITE"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q 'not valid JSON'
}
