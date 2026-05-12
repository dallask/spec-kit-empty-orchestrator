#!/bin/sh
# allocate-feature.sh — pre-allocate the next sequential feature ID and create
# the underlying branch + spec directory via the existing speckit.git.feature
# helper.
#
# Usage:
#   allocate-feature.sh "<original_title>" "<description>"
#
# Output (stdout): JSON object
#   {
#     "id": "003",
#     "branch_name": "003-add-user-login",
#     "spec_dir": "/abs/path/to/specs/003-add-user-login",
#     "short_name": "add-user-login"
#   }
#
# Serialised across concurrent calls via with_state_lock (constitution Principle II
# — Lead owns shared sequence allocation).

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

ORIGINAL_TITLE="${1:-}"
[ -n "$ORIGINAL_TITLE" ] || die "allocate-feature: missing original_title"
DESCRIPTION="${2:-}"

REPO_ROOT="$(cd "$ORCHESTRATE_ROOT/../../.." 2>/dev/null && pwd -P)"
SPECKIT_GIT_FEATURE="$REPO_ROOT/.specify/extensions/git/scripts/bash/create-new-feature.sh"
[ -x "$SPECKIT_GIT_FEATURE" ] || die "allocate-feature: $SPECKIT_GIT_FEATURE not executable (is the git extension installed?)"

# Derive a short-name from the original title:
#   - lowercase
#   - replace whitespace with hyphens
#   - strip everything that isn't [a-z0-9-]
#   - collapse repeated hyphens
#   - trim leading/trailing hyphens
#   - cap at 50 chars
_short_name="$(printf '%s' "$ORIGINAL_TITLE" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[[:space:]]\{1,\}/-/g' \
          -e 's/[^a-z0-9-]//g' \
          -e 's/--*/-/g' \
          -e 's/^-//' \
          -e 's/-$//' \
    | cut -c1-50)"
[ -n "$_short_name" ] || die "allocate-feature: derived short_name is empty for title '$ORIGINAL_TITLE'"

# Allocate the next sequential ID under a state lock so two callers cannot grab
# the same number.
_combined_description="$ORIGINAL_TITLE"
[ -n "$DESCRIPTION" ] && _combined_description="$ORIGINAL_TITLE — $DESCRIPTION"

# Run the existing helper under the lock. It outputs JSON on its last line.
allocate_under_lock() {
    "$SPECKIT_GIT_FEATURE" --json --short-name "$_short_name" "$_combined_description" \
        | grep -E '^\{' \
        | head -n 1
}

_raw="$(with_state_lock allocate_under_lock)"
[ -n "$_raw" ] || die "allocate-feature: speckit.git.feature returned no JSON"

# Validate.
if ! printf '%s' "$_raw" | jq . >/dev/null 2>&1; then
    die "allocate-feature: speckit.git.feature returned non-JSON: $_raw"
fi

_branch="$(printf '%s' "$_raw" | jq -r '.BRANCH_NAME')"
_num="$(printf '%s' "$_raw" | jq -r '.FEATURE_NUM')"
_spec_dir="$REPO_ROOT/specs/$_branch"

jq -n \
    --arg id "$_num" \
    --arg branch "$_branch" \
    --arg spec_dir "$_spec_dir" \
    --arg short "$_short_name" \
    '{id:$id, branch_name:$branch, spec_dir:$spec_dir, short_name:$short}'
