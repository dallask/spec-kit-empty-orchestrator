#!/bin/sh
# reconcile-state.sh — merge parsed BACKLOG items against the on-disk state by
# canonical title identity.
#
# Reads:
#   stdin            : JSON array of BacklogItem objects (from parse-backlog.sh)
#   $1               : path to current state.json (defaults to orchestrate state path)
#
# Writes to stdout:
#   Updated JSON state with `features` augmented:
#     * new items (canonical title not in state) → appended as
#       `(phase=ba, status=queued)` records with allocated id="" placeholder.
#       The Lead's allocate-feature.sh assigns the real id later.
#     * existing items → kept as-is (only `description` and `original_title` are
#       refreshed from the backlog, since Q8 says edits don't trigger reprocessing).
#     * state-only items (in state but missing from backlog) → retained as
#       historical records, untouched.
#
# Exit 0 on success.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

STATE_PATH="${1:-$(orchestrate_state_path)}"

# Read backlog from stdin and load state. Always delegate to state-read.sh
# (it handles missing files, empty files, whitespace-only files, and
# performs the schema shape check). Reading the file directly here would
# bypass validation and crash downstream jq if state.json was empty or
# corrupted.
_backlog="$(cat)"
_state="$("$_dir/state-read.sh")" || die "reconcile-state: state-read.sh failed"

# Reconcile via jq.
jq --argjson backlog "$_backlog" --arg now "$(iso_now)" '
    # Helper: produce the new feature record for a backlog item.
    def new_feature($item; $now):
        {
            id: "",                       # Lead pre-allocates via allocate-feature.sh
            title: $item.title,
            original_title: $item.original_title,
            description: $item.description,
            worktree_path: "",
            branch_name: "",
            spec_file_path: "",
            phase: "ba",
            status: "queued",
            last_payload: null,
            pending_clarification: null,
            created_at: $now,
            updated_at: $now,
            target_commit: null
        };

    # Build a map from canonical title -> existing feature record.
    (.features // []) as $existing
    | ($existing | map({key: .title, value: .}) | from_entries) as $by_title
    | ($backlog | map(select(.completed == false))) as $active_items
    | ($active_items
        | map(
            if $by_title[.title] then
                # Existing: refresh description + original_title only.
                $by_title[.title]
                | .description = ($active_items | map(select(.title == .title))[0].description // .description)
                | .updated_at = $now
            else
                new_feature(.; $now)
            end
          )
      ) as $matched_or_new
    # Determine which existing features are NOT in the current backlog (historical).
    | ($existing | map(select(.title as $t | ($active_items | map(.title) | index($t)) == null))) as $historical
    | .features = ($matched_or_new + $historical)
    | .updated_at = $now
' <<EOF
$_state
EOF
