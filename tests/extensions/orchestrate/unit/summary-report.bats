#!/usr/bin/env bats
# T042: summary-report.sh unit tests.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
    ORCH_DIR="$REPO_ROOT/.specify/extensions/orchestrate"
    TMP="$(mktemp -d -t orchestrate-sr-test.XXXXXX)"
    mkdir -p "$TMP/schemas" "$TMP/scripts/sh"
    cp "$ORCH_DIR/scripts/sh/"*.sh "$TMP/scripts/sh/"
    cp "$ORCH_DIR/schemas/"*.json "$TMP/schemas/"
    chmod +x "$TMP/scripts/sh/"*.sh
    SR="$TMP/scripts/sh/summary-report.sh"
    WRITE="$TMP/scripts/sh/state-write.sh"
}

teardown() {
    rm -rf "$TMP"
}

@test "empty state produces a graceful 'nothing to report' message" {
    run "$SR"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Nothing to report"
}

@test "mixed states show all rows + counters" {
    jq -n --arg now "2026-05-12T00:00:00Z" '
        {
            schema_version: "1.0",
            run_id: "test",
            created_at: $now,
            updated_at: $now,
            config_snapshot: {},
            features: [
                {id:"001", title:"a", original_title:"A", description:"", worktree_path:"/wt/1", branch_name:"001-a", spec_file_path:"/x/1/spec.md", phase:"done", status:"complete", last_payload:null, pending_clarification:null, created_at:$now, updated_at:$now, target_commit:"abcdef1234567890"},
                {id:"002", title:"b", original_title:"B", description:"", worktree_path:"/wt/2", branch_name:"002-b", spec_file_path:"/x/2/spec.md", phase:"ba",   status:"blocked",  last_payload:null, pending_clarification:{question:"What channels?", context:"ctx", correlation_id:"002-cl"}, created_at:$now, updated_at:$now, target_commit:null},
                {id:"003", title:"c", original_title:"C", description:"", worktree_path:"/wt/3", branch_name:"003-c", spec_file_path:"/x/3/spec.md", phase:"dev",  status:"failed",   last_payload:null, pending_clarification:null, created_at:$now, updated_at:$now, target_commit:null}
            ],
            counters: {queued: 0, running: 0, blocked: 1, failed: 1, complete: 1},
            events_log_path: "events.log"
        }
    ' | "$WRITE"
    run "$SR"
    [ "$status" -eq 0 ]
    # All three IDs appear in the table.
    echo "$output" | grep -q "| 001 |"
    echo "$output" | grep -q "| 002 |"
    echo "$output" | grep -q "| 003 |"
    # The blocked feature's question is quoted.
    echo "$output" | grep -q "What channels?"
    # Target commit is shortened.
    echo "$output" | grep -q "abcdef1"
    echo "$output" | grep -vq "abcdef1234567890"
}

@test "counter mismatch surfaces a WARNING" {
    # Use jq to seed inconsistent counters that state-write.sh would normally
    # recompute. Bypass state-write.sh by writing directly.
    cat > "$TMP/state.json" <<EOF
{
  "schema_version":"1.0","run_id":"test","created_at":"2026-05-12T00:00:00Z","updated_at":"2026-05-12T00:00:00Z",
  "config_snapshot":{},
  "features":[{"id":"001","title":"a","original_title":"A","description":"","worktree_path":"","branch_name":"","spec_file_path":"","phase":"ba","status":"queued","last_payload":null,"pending_clarification":null,"created_at":"2026-05-12T00:00:00Z","updated_at":"2026-05-12T00:00:00Z","target_commit":null}],
  "counters":{"queued":99,"running":0,"blocked":0,"failed":0,"complete":0},
  "events_log_path":"events.log"
}
EOF
    chmod 0600 "$TMP/state.json"
    run "$SR"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "WARNING"
}
