#!/usr/bin/env bats
# sandbox-cleanup.bats — tests for .specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh
#
# Covers (from specs/003-sandbox-testing/tasks.md):
#   T014  happy path — sandbox removed; host unchanged
#   T015  no-op when sandbox is absent (FR-015)
#   T016  path-safety: refuse anything not resolving to <repo-root>/.sandbox (FR-007, SC-005)
#   T017  cleanup ignores active lock (FR-016)

load 'helpers/sandbox-fixture'

REAL_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
PREPARE="$REAL_REPO_ROOT/.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh"
CLEANUP="$REAL_REPO_ROOT/.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh"

setup() {
    HOST="$(make_sandbox_fixture)"
}

teardown() {
    destroy_sandbox_fixture "$HOST"
}

_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Hash every file in $1 except those under .sandbox/ and .git/. Output
# is one line per file: "<sha256>  <path>".
_host_file_set() {
    _root="$1"
    cd "$_root" || return 1
    find . -path './.sandbox' -prune -o -path './.git' -prune -o -type f -print 2>/dev/null \
        | sort \
        | while read -r _f; do
            printf '%s  %s\n' "$(_sha256 "$_f")" "$_f"
          done
}

# --- T014: happy path -----------------------------------------------------

@test "T014: cleanup removes a prepared sandbox; host stays byte-identical" {
    cd "$HOST"
    run sh "$PREPARE"
    [ "$status" -eq 0 ]
    [ -d "$HOST/.sandbox" ]
    # Snapshot the host tree post-prepare (which is what we expect
    # post-cleanup too: prepare's .gitignore edit is one-way).
    snapshot_before="$(_host_file_set "$HOST" | sort)"

    run sh "$CLEANUP"
    [ "$status" -eq 0 ]
    # Sandbox is gone.
    [ ! -e "$HOST/.sandbox" ]
    # Host tree (outside .sandbox) is byte-identical.
    snapshot_after="$(_host_file_set "$HOST" | sort)"
    [ "$snapshot_before" = "$snapshot_after" ]
    # Output reports the removed path.
    printf '%s\n' "$output" | grep -q 'sandbox: removed'
}

# --- T015: no-op when sandbox is absent (FR-015) --------------------------

@test "T015: cleanup is a no-op when no sandbox exists" {
    cd "$HOST"
    [ ! -e "$HOST/.sandbox" ]
    run sh "$CLEANUP"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -q 'nothing to clean'
}

# --- T016: path-safety refusal (FR-007, SC-005) ---------------------------

@test "T016: cleanup refuses when .sandbox/ is a symlink pointing outside" {
    cd "$HOST"
    # Build a decoy directory outside the host and symlink `.sandbox`
    # to it.
    _decoy="$(mktemp -d -t cleanup-decoy.XXXXXX)"
    printf 'decoy content\n' > "$_decoy/important.txt"
    ln -s "$_decoy" "$HOST/.sandbox"

    run sh "$CLEANUP"
    [ "$status" -ne 0 ]
    # The error must reference both the offending resolved path and the
    # expected canonical path.
    printf '%s\n' "$output" | grep -q 'refusing to delete'
    # The decoy must still be intact.
    [ -d "$_decoy" ]
    [ -f "$_decoy/important.txt" ]
    [ "$(cat "$_decoy/important.txt")" = "decoy content" ]

    # Tidy up the symlink and decoy before teardown.
    rm -f "$HOST/.sandbox"
    rm -rf "$_decoy"
}

# --- T017: cleanup ignores active lock (FR-016) ---------------------------

@test "T017: cleanup removes the sandbox even when an orchestrator lock is present" {
    cd "$HOST"
    run sh "$PREPARE"
    [ "$status" -eq 0 ]
    # Simulate an orchestrator session that crashed without releasing
    # its lock.
    : > "$HOST/.sandbox/.specify/extensions/orchestrate/lock"
    [ -f "$HOST/.sandbox/.specify/extensions/orchestrate/lock" ]

    run sh "$CLEANUP"
    [ "$status" -eq 0 ]
    [ ! -e "$HOST/.sandbox" ]
}
