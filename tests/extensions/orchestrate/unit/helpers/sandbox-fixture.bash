#!/bin/sh
# sandbox-fixture.sh — bats helper to construct a throwaway "host" repo for
# sandbox-prepare / sandbox-cleanup tests.
#
# Usage from a bats test:
#
#   load 'helpers/sandbox-fixture.sh'
#
#   setup() {
#       FIXTURE_HOST="$(make_sandbox_fixture)"
#   }
#
#   teardown() {
#       destroy_sandbox_fixture "$FIXTURE_HOST"
#   }
#
# What it does:
#   * `mktemp -d` a fresh directory.
#   * `git init` inside it on branch 'main', set sandbox identity, make
#     one empty commit so HEAD exists (sandbox-prepare uses
#     `git rev-parse --show-toplevel` which needs a tree).
#   * `cp -R` the real host's `.specify/` and `.claude/` so the fixture
#     has the orchestrator extension under test plus all Spec Kit core
#     skills the BA pipeline would later need.
#   * Strip runtime debris that should not appear in a fresh fixture.
#   * Echo the fixture root path on stdout.
#
# Conformance: POSIX sh. No Bash-isms.

# Real host repo root (the orchestrator project itself).
__sandbox_fixture_host_root() {
    # The helper lives at tests/extensions/orchestrate/unit/helpers/.
    # The real repo root is four levels up.
    _h="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd -P)"
    # When sourced from a bats test, $0 may be the bats runner. Fall
    # back to BATS_TEST_DIRNAME if set, then back to a hardcoded climb.
    if [ -z "${_h:-}" ] || [ ! -d "$_h/.specify" ]; then
        if [ -n "${BATS_TEST_DIRNAME:-}" ]; then
            _h="$(cd "$BATS_TEST_DIRNAME/../../../.." 2>/dev/null && pwd -P)"
        fi
    fi
    printf '%s\n' "$_h"
}

make_sandbox_fixture() {
    _host="$(__sandbox_fixture_host_root)"
    [ -d "$_host/.specify" ] || {
        printf 'sandbox-fixture: cannot locate real host .specify (looked under %s)\n' "$_host" >&2
        return 1
    }
    _fix="$(mktemp -d -t sandbox-fixture.XXXXXX)" || {
        printf 'sandbox-fixture: mktemp -d failed\n' >&2
        return 1
    }
    cd "$_fix" || return 1
    git init --quiet --initial-branch=main 2>/dev/null \
        || { git init --quiet && git checkout -B main --quiet; } \
        || return 1
    cp -R "$_host/.specify" .specify || return 1
    cp -R "$_host/.claude"  .claude  || return 1
    # Strip runtime debris from the carried-over .specify so the fixture
    # starts in the same state a fresh checkout would (no stale state,
    # no leftover lock).
    rm -f .specify/extensions/orchestrate/state.json \
          .specify/extensions/orchestrate/events.log \
          .specify/extensions/orchestrate/lock
    if [ -d .specify/extensions/orchestrate/worktrees ]; then
        find .specify/extensions/orchestrate/worktrees -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    fi
    # An initial empty commit lets `git rev-parse --show-toplevel`
    # work and gives the fixture a HEAD before any test runs.
    git \
        -c user.email='fixture@local' \
        -c user.name='Fixture' \
        commit --allow-empty -m 'fixture: initial' --quiet \
        || return 1
    printf '%s\n' "$_fix"
}

destroy_sandbox_fixture() {
    _fix="${1:-}"
    if [ -n "$_fix" ] && [ -d "$_fix" ]; then
        # Belt-and-braces: refuse to rm anything that doesn't look like a
        # fixture mktemp dir (must contain 'sandbox-fixture.' in its
        # basename).
        case "$_fix" in
            */sandbox-fixture.*) rm -rf -- "$_fix" ;;
            *) printf 'destroy_sandbox_fixture: refusing to remove %s (not a fixture path)\n' "$_fix" >&2 ;;
        esac
    fi
}
