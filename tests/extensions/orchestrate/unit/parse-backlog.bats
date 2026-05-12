#!/usr/bin/env bats
# T014: parse-backlog.sh unit tests

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
    PARSE="$REPO_ROOT/.specify/extensions/orchestrate/scripts/sh/parse-backlog.sh"
    TMP="$(mktemp -d -t orchestrate-test.XXXXXX)"
}

teardown() {
    rm -rf "$TMP"
}

# --- happy path ---

@test "parses mixed checkbox separator styles" {
    cat > "$TMP/BACKLOG.md" <<'EOF'
# Sprint backlog

Random intro prose.

- [ ] Add user login — Support email+password and OAuth2.
- [ ] Profile page
- [x] Onboarding flow -- Already shipped.
- [ ] Search bar - Header-mounted typeahead.
EOF
    run "$PARSE" "$TMP/BACKLOG.md"
    [ "$status" -eq 0 ]
    count="$(printf '%s' "$output" | jq 'length')"
    [ "$count" -eq 4 ]
    completed="$(printf '%s' "$output" | jq '[.[] | select(.completed)] | length')"
    [ "$completed" -eq 1 ]
}

@test "title is canonical (lowercased, trimmed) while original_title preserves case" {
    cat > "$TMP/BACKLOG.md" <<'EOF'
- [ ]   Add USER Login   — Support email.
EOF
    run "$PARSE" "$TMP/BACKLOG.md"
    [ "$status" -eq 0 ]
    title="$(printf '%s' "$output" | jq -r '.[0].title')"
    orig="$(printf '%s' "$output" | jq -r '.[0].original_title')"
    [ "$title" = "add user login" ]
    [ "$orig" = "Add USER Login" ]
}

@test "separator priority: em-dash beats -- beats - " {
    cat > "$TMP/BACKLOG.md" <<'EOF'
- [ ] Title A — desc with -- inside and - too
EOF
    run "$PARSE" "$TMP/BACKLOG.md"
    [ "$status" -eq 0 ]
    title="$(printf '%s' "$output" | jq -r '.[0].title')"
    desc="$(printf '%s' "$output" | jq -r '.[0].description')"
    [ "$title" = "title a" ]
    [ "$desc" = "desc with -- inside and - too" ]
}

@test "item with no separator has empty description" {
    cat > "$TMP/BACKLOG.md" <<'EOF'
- [ ] Standalone title
EOF
    run "$PARSE" "$TMP/BACKLOG.md"
    [ "$status" -eq 0 ]
    desc="$(printf '%s' "$output" | jq -r '.[0].description')"
    [ "$desc" = "" ]
}

# --- empty / missing handling (FR-003) ---

@test "missing file returns empty array, exit 0" {
    run "$PARSE" "$TMP/does-not-exist.md"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "empty file returns empty array, exit 0" {
    : > "$TMP/empty.md"
    run "$PARSE" "$TMP/empty.md"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "file with no checkbox items returns empty array" {
    cat > "$TMP/prose.md" <<'EOF'
# A document

This file has no top-level checkbox items.

## A section

Just prose.
EOF
    run "$PARSE" "$TMP/prose.md"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# --- error paths ---

@test "duplicate canonical titles among incomplete items exits 2" {
    cat > "$TMP/dup.md" <<'EOF'
- [ ] Search bar — Header search.
- [ ] search bar — Sidebar search.
EOF
    run "$PARSE" "$TMP/dup.md"
    [ "$status" -eq 2 ]
    printf '%s' "$output" | grep -q duplicate_title
}

@test "completed and incomplete sharing a title is NOT a duplicate" {
    cat > "$TMP/mixed.md" <<'EOF'
- [x] Search bar — Done version.
- [ ] Search bar — Active version.
EOF
    run "$PARSE" "$TMP/mixed.md"
    [ "$status" -eq 0 ]
    count="$(printf '%s' "$output" | jq 'length')"
    [ "$count" -eq 2 ]
}

@test "non-checkbox lines are ignored for segmentation" {
    cat > "$TMP/mixed.md" <<'EOF'
# Heading

- [ ] Feature one — desc
  - [ ] Nested checkbox (should be ignored)
- not a checkbox
- [ ] Feature two
EOF
    run "$PARSE" "$TMP/mixed.md"
    [ "$status" -eq 0 ]
    count="$(printf '%s' "$output" | jq 'length')"
    [ "$count" -eq 2 ]
}

@test "uppercase X is also treated as completed" {
    cat > "$TMP/upX.md" <<'EOF'
- [X] Done item — completed
- [ ] Open item
EOF
    run "$PARSE" "$TMP/upX.md"
    [ "$status" -eq 0 ]
    done_count="$(printf '%s' "$output" | jq '[.[] | select(.completed)] | length')"
    [ "$done_count" -eq 1 ]
}
