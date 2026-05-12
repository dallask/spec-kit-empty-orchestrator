#!/usr/bin/env bats
# T039: config-load.sh unit tests.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
    ORCH_DIR="$REPO_ROOT/.specify/extensions/orchestrate"
    LOADER="$ORCH_DIR/scripts/sh/config-load.sh"
    TMPL="$ORCH_DIR/config-template.yml"
    TMP="$(mktemp -d -t orchestrate-cfg-test.XXXXXX)"
}

teardown() {
    rm -rf "$TMP"
}

@test "empty user config falls back to all defaults" {
    : > "$TMP/empty.yml"
    run "$LOADER" "$TMP/empty.yml" "$TMPL"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .parallelism.ba)" = "2" ]
    [ "$(printf '%s' "$output" | jq -r .merge.strategy)" = "squash" ]
    [ "$(printf '%s' "$output" | jq -r .safety.on_dirty_tree)" = "refuse" ]
    [ "$(printf '%s' "$output" | jq -r .ba_gate.strictness)" = "strict" ]
}

@test "partial override: parallelism.ba=4 overrides default" {
    cat > "$TMP/cfg.yml" <<EOF
parallelism:
  ba: 4
EOF
    run "$LOADER" "$TMP/cfg.yml" "$TMPL"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .parallelism.ba)" = "4" ]
    [ "$(printf '%s' "$output" | jq -r .parallelism.dev)" = "2" ]
}

@test "type-invalid value (ba=two) is rejected with a JSON error" {
    cat > "$TMP/cfg.yml" <<EOF
parallelism:
  ba: two
EOF
    run "$LOADER" "$TMP/cfg.yml" "$TMPL"
    [ "$status" -ne 0 ]
    printf '%s' "$output" | grep -q '"code":"config_invalid"'
    printf '%s' "$output" | grep -q 'parallelism.ba'
}

@test "out-of-range value (ba=99) is rejected" {
    cat > "$TMP/cfg.yml" <<EOF
parallelism:
  ba: 99
EOF
    run "$LOADER" "$TMP/cfg.yml" "$TMPL"
    [ "$status" -ne 0 ]
    printf '%s' "$output" | grep -q 'must be in 1..16'
}

@test "invalid enum (merge.strategy=cherry) is rejected" {
    cat > "$TMP/cfg.yml" <<EOF
merge:
  strategy: cherry
EOF
    run "$LOADER" "$TMP/cfg.yml" "$TMPL"
    [ "$status" -ne 0 ]
    printf '%s' "$output" | grep -q 'merge.strategy'
}

@test "missing user file → treat as empty (pure defaults)" {
    run "$LOADER" "$TMP/no-such-file.yml" "$TMPL"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .parallelism.ba)" = "2" ]
}

@test "merge.target_branch override survives" {
    cat > "$TMP/cfg.yml" <<EOF
merge:
  target_branch: integration
EOF
    run "$LOADER" "$TMP/cfg.yml" "$TMPL"
    [ "$status" -eq 0 ]
    [ "$(printf '%s' "$output" | jq -r .merge.target_branch)" = "integration" ]
}
