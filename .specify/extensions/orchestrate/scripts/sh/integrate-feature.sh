#!/bin/sh
# integrate-feature.sh — integrate a completed feature branch into the target
# branch using one of: squash | merge | rebase.
#
# Usage:
#   integrate-feature.sh FEATURE_BRANCH TARGET_BRANCH STRATEGY ORIGINAL_TITLE
#
# Behaviour per research.md §8:
#   * squash  : git merge --squash + one Conventional-Commits commit
#   * merge   : git merge --no-ff with a Conventional-Commits commit message
#   * rebase  : validate every commit on the feature branch is CC-compliant;
#               rebase onto target, then fast-forward.
#
# Output (stdout, JSON):
#   {"status":"merged", "target_commit":"<sha>", "strategy":"<s>"}
# On conflict / CC violation:
#   stderr emits an errorBody with code in {merge_conflict, cc_violation},
#   exit 1, and the script runs `git merge --abort` / `git rebase --abort`
#   so the target branch is unchanged.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

FEATURE_BRANCH="${1:-}"
TARGET_BRANCH="${2:-}"
STRATEGY="${3:-squash}"
ORIGINAL_TITLE="${4:-}"

[ -n "$FEATURE_BRANCH" ] || die "integrate-feature: missing FEATURE_BRANCH"
[ -n "$TARGET_BRANCH" ]  || die "integrate-feature: missing TARGET_BRANCH"
[ -n "$ORIGINAL_TITLE" ] || die "integrate-feature: missing ORIGINAL_TITLE"
case "$STRATEGY" in
    squash|merge|rebase) : ;;
    *) die "integrate-feature: unknown strategy '$STRATEGY' (expected squash|merge|rebase)" ;;
esac

# Verify both branches exist.
if ! git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    jq -n --arg b "$TARGET_BRANCH" '{code:"target_branch_missing", message:"target branch does not exist locally", recoverable:false, details:{branch:$b}}' >&2
    exit 1
fi
if ! git show-ref --verify --quiet "refs/heads/$FEATURE_BRANCH"; then
    jq -n --arg b "$FEATURE_BRANCH" '{code:"feature_branch_missing", message:"feature branch does not exist locally", recoverable:false, details:{branch:$b}}' >&2
    exit 1
fi

# Derive Conventional-Commits type from the title (per FR-020):
# titles starting with "fix" (case-insensitive, word-boundaried) → fix:
# everything else → feat:
_ttype="feat"
_first_word="$(printf '%s' "$ORIGINAL_TITLE" | awk '{print tolower($1)}')"
if [ "$_first_word" = "fix" ]; then
    _ttype="fix"
fi
_cc_subject="$_ttype(orchestrator): $ORIGINAL_TITLE"

# Conventional Commits regex (POSIX ERE).
_cc_re='^(feat|fix|docs|chore|refactor|test|ci|build|perf|revert|style)(\([^)]+\))?!?: .+'

# --- rebase: validate every commit first --------------------------------------
if [ "$STRATEGY" = "rebase" ]; then
    _bad="$(git log --format="%H%x09%s" "$TARGET_BRANCH..$FEATURE_BRANCH" \
        | awk -F'\t' -v re="$_cc_re" '$2 !~ re { print $1 ":" $2 }')"
    if [ -n "$_bad" ]; then
        _bad_json="$(printf '%s\n' "$_bad" | jq -R . | jq -s .)"
        jq -n --arg b "$FEATURE_BRANCH" --argjson bad "$_bad_json" '
            {code:"cc_violation", message:"rebase strategy requires every feature commit to be Conventional-Commits compliant", recoverable:false, details:{branch:$b, non_conforming:$bad}}
        ' >&2
        exit 1
    fi
fi

# --- checkout target branch ---------------------------------------------------
if ! git checkout "$TARGET_BRANCH" >/tmp/orchestrate-co.out 2>&1; then
    _err="$(cat /tmp/orchestrate-co.out 2>/dev/null)"
    rm -f /tmp/orchestrate-co.out
    jq -n --arg b "$TARGET_BRANCH" --arg err "$_err" '
        {code:"checkout_failed", message:"could not check out target branch (is the main tree clean?)", recoverable:true, details:{target:$b, git_error:$err}}
    ' >&2
    exit 1
fi
rm -f /tmp/orchestrate-co.out

case "$STRATEGY" in
    squash)
        if git merge --squash "$FEATURE_BRANCH" >/tmp/orchestrate-m.out 2>&1 \
            && git commit -m "$_cc_subject" >>/tmp/orchestrate-m.out 2>&1; then
            _sha="$(git rev-parse HEAD)"
            jq -n --arg s "$_sha" --arg t "squash" '{status:"merged", target_commit:$s, strategy:$t}'
            rm -f /tmp/orchestrate-m.out
            exit 0
        fi
        _err="$(cat /tmp/orchestrate-m.out 2>/dev/null)"
        rm -f /tmp/orchestrate-m.out
        # Abort any in-progress squash (reset the index).
        git reset --hard "$TARGET_BRANCH" >/dev/null 2>&1 || true
        jq -n --arg err "$_err" '{code:"merge_conflict", message:"squash merge produced a conflict; target branch unchanged", recoverable:true, details:{git_error:$err}}' >&2
        exit 1
        ;;
    merge)
        if git merge --no-ff "$FEATURE_BRANCH" -m "$_cc_subject" >/tmp/orchestrate-m.out 2>&1; then
            _sha="$(git rev-parse HEAD)"
            jq -n --arg s "$_sha" --arg t "merge" '{status:"merged", target_commit:$s, strategy:$t}'
            rm -f /tmp/orchestrate-m.out
            exit 0
        fi
        _err="$(cat /tmp/orchestrate-m.out 2>/dev/null)"
        rm -f /tmp/orchestrate-m.out
        git merge --abort >/dev/null 2>&1 || true
        jq -n --arg err "$_err" '{code:"merge_conflict", message:"non-ff merge produced a conflict; target branch unchanged", recoverable:true, details:{git_error:$err}}' >&2
        exit 1
        ;;
    rebase)
        # Rebase the feature commits onto the target, then fast-forward.
        if git checkout "$FEATURE_BRANCH" >/tmp/orchestrate-m.out 2>&1 \
            && git rebase "$TARGET_BRANCH" >>/tmp/orchestrate-m.out 2>&1 \
            && git checkout "$TARGET_BRANCH" >>/tmp/orchestrate-m.out 2>&1 \
            && git merge --ff-only "$FEATURE_BRANCH" >>/tmp/orchestrate-m.out 2>&1; then
            _sha="$(git rev-parse HEAD)"
            jq -n --arg s "$_sha" --arg t "rebase" '{status:"merged", target_commit:$s, strategy:$t}'
            rm -f /tmp/orchestrate-m.out
            exit 0
        fi
        _err="$(cat /tmp/orchestrate-m.out 2>/dev/null)"
        rm -f /tmp/orchestrate-m.out
        git rebase --abort >/dev/null 2>&1 || true
        git checkout "$TARGET_BRANCH" >/dev/null 2>&1 || true
        jq -n --arg err "$_err" '{code:"merge_conflict", message:"rebase produced a conflict; target branch unchanged", recoverable:true, details:{git_error:$err}}' >&2
        exit 1
        ;;
esac
