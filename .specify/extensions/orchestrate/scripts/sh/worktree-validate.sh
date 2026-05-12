#!/bin/sh
# worktree-validate.sh — check that a feature's worktree still exists as a
# registered git worktree.
#
# Usage:
#   worktree-validate.sh WORKTREE_PATH
#
# Output:
#   stdout: {"status":"ok", "worktree_path":"..."} on success
#   stderr: errorBody with code=worktree_missing on miss; exit 1

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

WTP="${1:-}"
[ -n "$WTP" ] || die "worktree-validate: missing WORKTREE_PATH"

# Fast disk check.
if [ ! -d "$WTP" ] || { [ ! -d "$WTP/.git" ] && [ ! -f "$WTP/.git" ]; }; then
    jq -n --arg p "$WTP" '{code:"worktree_missing", message:"worktree path does not exist or is not a git worktree", recoverable:true, details:{worktree_path:$p}}' >&2
    exit 1
fi

# Confirm git agrees it is a registered worktree.
if ! git worktree list --porcelain 2>/dev/null | grep -qxF "worktree $WTP"; then
    jq -n --arg p "$WTP" '{code:"worktree_missing", message:"path exists but git does not list it as a registered worktree", recoverable:true, details:{worktree_path:$p}}' >&2
    exit 1
fi

jq -n --arg p "$WTP" '{status:"ok", worktree_path:$p}'
exit 0
