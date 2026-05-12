#!/bin/sh
# safety-check.sh — guard the main working tree per safety.on_dirty_tree.
#
# Two forms:
#   safety-check.sh MODE [RUN_ID]
#       MODE = refuse | stash | ignore
#       Emits JSON status to stdout.
#       For `refuse` with a dirty tree: exit 1 with a list of dirty paths.
#       For `stash`: pushes a stash and emits its ref.
#       For `ignore`: no-op.
#
#   safety-check.sh --pop STASH_REF
#       Runs `git stash pop <ref>`. On conflict, emits JSON + exit 1 without auto-resolving.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

# --- --pop subcommand (run-end recovery) -------------------------------------

if [ "${1:-}" = "--pop" ]; then
    _ref="${2:-}"
    [ -n "$_ref" ] || die "safety-check --pop: missing stash ref"
    if git stash pop "$_ref" 2>/tmp/orchestrate-stash-pop.err; then
        jq -n --arg ref "$_ref" '{status:"popped", stash_ref:$ref}'
        rm -f /tmp/orchestrate-stash-pop.err
        exit 0
    fi
    _err="$(cat /tmp/orchestrate-stash-pop.err 2>/dev/null)"
    rm -f /tmp/orchestrate-stash-pop.err
    jq -n --arg ref "$_ref" --arg err "$_err" '{
        status: "pop_conflict",
        stash_ref: $ref,
        hint: "Resolve the conflict in the main working tree, then `git stash drop` the entry.",
        git_error: $err
    }'
    exit 1
fi

# --- default (startup) form --------------------------------------------------

MODE="${1:-refuse}"
RUN_ID="${2:-orchestrate-$(iso_now)}"

case "$MODE" in
    refuse|stash|ignore) : ;;
    *) die "safety-check: unknown mode '$MODE'; expected refuse|stash|ignore" ;;
esac

# Verify we are inside a git repo.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    jq -n '{status:"skipped", reason:"not a git repository"}'
    exit 0
fi

_dirty="$(git status --porcelain 2>/dev/null)"

if [ -z "$_dirty" ]; then
    jq -n --arg mode "$MODE" '{status:"clean", mode:$mode}'
    exit 0
fi

case "$MODE" in
    refuse)
        # Build a JSON array of dirty paths.
        _paths="$(printf '%s\n' "$_dirty" | awk '{print substr($0,4)}' | jq -R . | jq -s .)"
        jq -n --argjson paths "$_paths" '{
            status: "refused",
            reason: "main working tree has uncommitted changes",
            dirty_paths: $paths,
            hint: "Commit or stash your changes, then re-run; or set safety.on_dirty_tree=stash."
        }'
        exit 1
        ;;
    stash)
        if git stash push -u -m "orchestrate:$RUN_ID" >/tmp/orchestrate-stash.out 2>&1; then
            # The most-recent stash is stash@{0}.
            jq -n --arg run "$RUN_ID" '{status:"stashed", stash_ref:"stash@{0}", message:("orchestrate:" + $run)}'
            rm -f /tmp/orchestrate-stash.out
            exit 0
        fi
        _err="$(cat /tmp/orchestrate-stash.out 2>/dev/null)"
        rm -f /tmp/orchestrate-stash.out
        jq -n --arg err "$_err" '{status:"stash_failed", git_error:$err}'
        exit 1
        ;;
    ignore)
        jq -n '{status:"ignored", reason:"safety.on_dirty_tree=ignore — user accepted the risk"}'
        exit 0
        ;;
esac
