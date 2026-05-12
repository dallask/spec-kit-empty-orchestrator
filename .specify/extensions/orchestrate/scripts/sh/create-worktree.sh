#!/bin/sh
# create-worktree.sh — provision a git worktree for one feature.
#
# Usage:
#   create-worktree.sh FEATURE_ID BRANCH_NAME
#
# Creates: .specify/extensions/orchestrate/worktrees/<FEATURE_ID>
# Output (stdout): JSON {"worktree_path": "...", "branch_name": "..."}
#                 OR an errorBody JSON on failure (then exit 1).

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

FEATURE_ID="${1:-}"
BRANCH_NAME="${2:-}"

[ -n "$FEATURE_ID" ]  || die "create-worktree: missing FEATURE_ID"
[ -n "$BRANCH_NAME" ] || die "create-worktree: missing BRANCH_NAME"

_worktree_root="$(orchestrate_worktree_root)"
_worktree_path="$_worktree_root/$FEATURE_ID"

mkdir -p "$_worktree_root"

# If the worktree already exists, return its path (idempotent).
if [ -d "$_worktree_path/.git" ] || [ -f "$_worktree_path/.git" ]; then
    jq -n --arg p "$_worktree_path" --arg b "$BRANCH_NAME" \
        '{worktree_path:$p, branch_name:$b, status:"already_exists"}'
    exit 0
fi

# `git worktree add` requires a non-existent path. Refuse if the path is busy.
if [ -e "$_worktree_path" ]; then
    jq -n --arg p "$_worktree_path" --arg b "$BRANCH_NAME" \
        '{code:"worktree_failed", message:"target path exists and is not a worktree", recoverable:false, details:{worktree_path:$p, branch_name:$b}}' >&2
    exit 1
fi

# The branch is created by allocate-feature.sh via speckit.git.feature, so it
# already exists. Attach a worktree to it.
if git worktree add "$_worktree_path" "$BRANCH_NAME" >/tmp/orchestrate-wt.out 2>&1; then
    jq -n --arg p "$_worktree_path" --arg b "$BRANCH_NAME" \
        '{worktree_path:$p, branch_name:$b, status:"created"}'
    rm -f /tmp/orchestrate-wt.out
    exit 0
fi

_err="$(cat /tmp/orchestrate-wt.out 2>/dev/null)"
rm -f /tmp/orchestrate-wt.out
jq -n --arg p "$_worktree_path" --arg b "$BRANCH_NAME" --arg err "$_err" \
    '{code:"worktree_failed", message:"git worktree add failed", recoverable:true, details:{worktree_path:$p, branch_name:$b, git_error:$err}}' >&2
exit 1
