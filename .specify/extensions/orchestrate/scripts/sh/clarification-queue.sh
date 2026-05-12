#!/bin/sh
# clarification-queue.sh — manage the pending-clarification queue inside state.json.
#
# Subcommands:
#   list                          → JSON array of {feature_id, original_title, question, context, options, correlation_id}
#                                   ordered by feature_id ascending (FR-014).
#   enqueue FEATURE_ID < BODY     → save BODY (a clarification_request body JSON
#                                   read from stdin) into the feature's
#                                   pending_clarification slot and set
#                                   (phase=ba, status=blocked).
#   dequeue FEATURE_ID ANSWER     → emit a clarification_answer body JSON
#                                   matching the saved correlation_id, clear the
#                                   pending_clarification slot, and transition the
#                                   feature back to (ba, running).
#   peek                          → JSON of the SINGLE next feature awaiting an
#                                   answer (feature_id-ascending), or null if none.
#
# All subcommands operate against state.json via state-read.sh + state-write.sh.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

CMD="${1:-list}"

case "$CMD" in
    list)
        "$_dir/state-read.sh" | jq '
            [.features[]
                | select(.status == "blocked")
                | {feature_id: .id, original_title, question: .pending_clarification.question, context: .pending_clarification.context, options: (.pending_clarification.options // []), correlation_id: .pending_clarification.correlation_id}
            ] | sort_by(.feature_id)
        '
        ;;
    peek)
        "$_dir/state-read.sh" | jq '
            ([.features[] | select(.status == "blocked")] | sort_by(.id) | .[0] // null)
            | if . == null then null else
                {feature_id: .id, original_title, question: .pending_clarification.question, context: .pending_clarification.context, options: (.pending_clarification.options // []), correlation_id: .pending_clarification.correlation_id}
            end
        '
        ;;
    enqueue)
        _fid="${2:-}"
        [ -n "$_fid" ] || die "clarification-queue enqueue: missing FEATURE_ID"
        _body="$(cat)"
        if ! printf '%s' "$_body" | jq . >/dev/null 2>&1; then
            die "clarification-queue enqueue: stdin is not valid JSON"
        fi
        _state="$("$_dir/state-read.sh")"
        _now="$(iso_now)"
        printf '%s' "$_state" | jq --arg fid "$_fid" --arg now "$_now" --argjson body "$_body" '
            .features |= map(
                if .id == $fid then
                    .pending_clarification = $body
                    | .phase = "ba"
                    | .status = "blocked"
                    | .updated_at = $now
                else . end
            )
        ' | "$_dir/state-write.sh"
        ;;
    dequeue)
        _fid="${2:-}"
        _answer="${3:-}"
        [ -n "$_fid" ] || die "clarification-queue dequeue: missing FEATURE_ID"
        [ -n "$_answer" ] || die "clarification-queue dequeue: missing ANSWER"
        _state="$("$_dir/state-read.sh")"
        _feat="$(printf '%s' "$_state" | jq --arg fid "$_fid" '.features[] | select(.id == $fid)')"
        if [ -z "$_feat" ] || [ "$_feat" = "null" ]; then
            die "clarification-queue dequeue: feature $_fid not found"
        fi
        _saved_qid="$(printf '%s' "$_feat" | jq -r '.pending_clarification.correlation_id // empty')"
        _orig_q="$(printf '%s' "$_feat" | jq -r '.pending_clarification.question // empty')"
        if [ -z "$_saved_qid" ]; then
            die "clarification-queue dequeue: feature $_fid has no pending_clarification"
        fi
        _now="$(iso_now)"
        # Emit the clarification_answer body to stdout so the Lead can attach it
        # to the BA assignment.retry_with field.
        jq -n --arg ans "$_answer" --arg q "$_orig_q" '{answer:$ans, original_question:$q}'
        # Clear the pending_clarification + transition back to (ba, running).
        printf '%s' "$_state" | jq --arg fid "$_fid" --arg now "$_now" '
            .features |= map(
                if .id == $fid then
                    .pending_clarification = null
                    | .phase = "ba"
                    | .status = "running"
                    | .updated_at = $now
                else . end
            )
        ' | "$_dir/state-write.sh"
        ;;
    *)
        die "clarification-queue: unknown subcommand '$CMD' (expected list|peek|enqueue|dequeue)"
        ;;
esac
