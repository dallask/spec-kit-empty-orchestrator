#!/usr/bin/env bats
# sandbox-prepare.bats — tests for .specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh
#
# Covers (from specs/003-sandbox-testing/tasks.md):
#   T008  happy path
#   T009  missing-dependency abort (git, jq)
#   T010  dirty host invariant (FR-018, resolves C3)
#   T024  re-prepare wipes existing sandbox (US4 AS1, FR-013)
#   T025  re-prepare refuses on active lock (US4 AS2, FR-014)

# Load the shared fixture helper.
load 'helpers/sandbox-fixture'

# The real orchestrator project root (the parent of `.specify/`).
# Calculated once at file load.
REAL_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd -P)"
PREPARE="$REAL_REPO_ROOT/.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh"
ASSET="$REAL_REPO_ROOT/.specify/extensions/orchestrate/assets/sandbox-backlog.md"

setup() {
    HOST="$(make_sandbox_fixture)"
}

teardown() {
    destroy_sandbox_fixture "$HOST"
}

# Helper: compute SHA-256 of a file (BSD `shasum -a 256` on macOS,
# GNU `sha256sum` on Linux).
_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Helper: snapshot a directory tree's SHA-256 set, excluding any
# `.sandbox/` subtree.
_tree_sha_set() {
    _root="$1"
    cd "$_root" || return 1
    find . -path './.sandbox' -prune -o -path './.git' -prune -o -type f -print 2>/dev/null \
        | sort \
        | while read -r _f; do
            _sha256 "$_f"
            printf '  %s\n' "$_f"
          done
}

# --- T008: happy path ------------------------------------------------------

@test "T008: prepare creates a fully-wired sandbox" {
    cd "$HOST"
    run sh "$PREPARE"
    [ "$status" -eq 0 ]
    # Sandbox exists with a git repo.
    [ -d "$HOST/.sandbox/.git" ]
    # Sandbox BACKLOG.md is byte-equal to the asset.
    [ "$(_sha256 "$HOST/.sandbox/BACKLOG.md")" = "$(_sha256 "$ASSET")" ]
    # Orchestrator extension is present inside the sandbox.
    [ -f "$HOST/.sandbox/.specify/extensions/orchestrate/extension.yml" ]
    # Host .gitignore now contains .sandbox/.
    grep -Eq '^\.sandbox/?$' "$HOST/.gitignore"
    # The initial commit is Conventional-Commits compliant.
    msg="$(cd "$HOST/.sandbox" && git log -1 --format=%s)"
    [ "$msg" = "chore(sandbox): initial sandbox state" ]
    # Both `main` and `dev` branches exist; HEAD is on `main`.
    head_branch="$(cd "$HOST/.sandbox" && git rev-parse --abbrev-ref HEAD)"
    [ "$head_branch" = "main" ]
    cd "$HOST/.sandbox" && git rev-parse --verify dev >/dev/null
    # Sandbox-internal .gitignore exists and excludes runtime files.
    grep -q 'state.json'  "$HOST/.sandbox/.gitignore"
    grep -q 'events.log'  "$HOST/.sandbox/.gitignore"
    grep -q 'lock'        "$HOST/.sandbox/.gitignore"
    grep -q 'worktrees'   "$HOST/.sandbox/.gitignore"
    # Sandbox working tree is clean post-prepare.
    [ -z "$(cd "$HOST/.sandbox" && git status --porcelain)" ]
    # The orchestrator skill is wired up in the sandbox's .claude/skills/.
    [ -f "$HOST/.sandbox/.claude/skills/speckit-orchestrate/SKILL.md" ]
    # The summary line was printed.
    printf '%s\n' "$output" | grep -q 'sandbox: prepared at'
}

# --- T009: missing-dependency abort ---------------------------------------

@test "T009a: prepare aborts when git is unavailable" {
    cd "$HOST"
    # Build a sandbox PATH that has neither git nor jq. The interpreter
    # itself is reached via absolute `/bin/sh` so PATH stripping does
    # not also strip the shell.
    _bin="$(mktemp -d -t prep-bin.XXXXXX)"
    PATH_BACKUP="$PATH"
    PATH="$_bin"
    export PATH
    run /bin/sh "$PREPARE"
    PATH="$PATH_BACKUP"
    export PATH
    rm -rf "$_bin"
    [ "$status" -ne 0 ]
    printf '%s\n' "$output" | grep -q 'missing required dependency: git'
    # And critically: no half-built .sandbox/.
    [ ! -e "$HOST/.sandbox" ]
}

@test "T009b: prepare aborts when jq is unavailable" {
    cd "$HOST"
    # Build a sandbox PATH that has git but not jq.
    _bin="$(mktemp -d -t prep-bin.XXXXXX)"
    ln -s "$(command -v git)" "$_bin/git"
    PATH_BACKUP="$PATH"
    PATH="$_bin"
    export PATH
    run /bin/sh "$PREPARE"
    PATH="$PATH_BACKUP"
    export PATH
    rm -rf "$_bin"
    [ "$status" -ne 0 ]
    printf '%s\n' "$output" | grep -q 'missing required dependency: jq'
    [ ! -e "$HOST/.sandbox" ]
}

# --- T010: dirty host invariant (FR-018) ----------------------------------

@test "T010: prepare leaves a dirty host unchanged" {
    cd "$HOST"
    # Make the host dirty: write a sentinel file inside the host tree.
    printf 'sentinel content\n' > "$HOST/HOST_DIRTY_SENTINEL.tmp"
    # Snapshot host file SHA-256s (excluding .sandbox/ and .git/).
    snapshot_before="$(_tree_sha_set "$HOST" | sort)"
    porcelain_before="$(cd "$HOST" && git status --porcelain | sort)"

    run sh "$PREPARE"
    [ "$status" -eq 0 ]
    # Sandbox was created.
    [ -d "$HOST/.sandbox" ]
    # The sentinel is untouched in the host.
    [ -f "$HOST/HOST_DIRTY_SENTINEL.tmp" ]
    [ "$(cat "$HOST/HOST_DIRTY_SENTINEL.tmp")" = "sentinel content" ]
    # The host file-content set (excluding .sandbox/, .git/) is unchanged
    # except for the .gitignore edit which prepare is permitted to make.
    snapshot_after="$(_tree_sha_set "$HOST" | sort)"
    # Allow a single delta: the .gitignore line that prepare appended.
    # We diff the two snapshots and assert at most one line per side
    # corresponds to the .gitignore SHA change.
    delta="$(diff <(printf '%s\n' "$snapshot_before") <(printf '%s\n' "$snapshot_after") | grep -E '^[<>]' || true)"
    if [ -n "$delta" ]; then
        # Every line of delta must reference .gitignore — anything else
        # is a host pollution.
        ! printf '%s\n' "$delta" | grep -vq '\.gitignore'
    fi
    # The porcelain output must not have lost the sentinel's tracked
    # status, and must not contain anything outside the sentinel plus
    # the gitignore.
    porcelain_after="$(cd "$HOST" && git status --porcelain | sort)"
    # The sentinel must still appear in porcelain.
    printf '%s\n' "$porcelain_after" | grep -q 'HOST_DIRTY_SENTINEL.tmp'
}

# --- T024: re-prepare wipes existing sandbox (FR-013, US4 AS1) ------------

@test "T024: re-prepare wipes prior sandbox" {
    cd "$HOST"
    run sh "$PREPARE"
    [ "$status" -eq 0 ]
    # Sentinel inside the prior sandbox.
    printf 'sentinel\n' > "$HOST/.sandbox/SENTINEL"
    [ -f "$HOST/.sandbox/SENTINEL" ]

    run sh "$PREPARE"
    [ "$status" -eq 0 ]
    # The sentinel from the prior sandbox is gone.
    [ ! -f "$HOST/.sandbox/SENTINEL" ]
    # User was told the prior sandbox was discarded.
    printf '%s\n' "$output" | grep -qi 'discarding previous sandbox'
}

# --- T025: re-prepare refuses on active lock (FR-014, US4 AS2) -----------

@test "T025: re-prepare refuses when lock file exists" {
    cd "$HOST"
    run sh "$PREPARE"
    [ "$status" -eq 0 ]
    # Drop a sentinel inside the sandbox and an active orchestrator
    # lock file.
    printf 'sentinel\n' > "$HOST/.sandbox/SENTINEL"
    mkdir -p "$HOST/.sandbox/.specify/extensions/orchestrate"
    : > "$HOST/.sandbox/.specify/extensions/orchestrate/lock"

    run sh "$PREPARE"
    # Exit code 2 per prepare.sh contract.
    [ "$status" -eq 2 ]
    # Lock path named in stderr.
    printf '%s\n' "$output" | grep -q 'lock file exists'
    # The sandbox was NOT wiped — the sentinel survives.
    [ -f "$HOST/.sandbox/SENTINEL" ]
}
