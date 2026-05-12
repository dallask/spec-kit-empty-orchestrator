#!/bin/sh
# parse-backlog.sh — parse BACKLOG.md into a JSON array per contracts/backlog-grammar.md.
#
# Usage:  parse-backlog.sh PATH_TO_BACKLOG
# Output: JSON array on stdout — [{title, original_title, description, completed, source_line}, ...]
# Exit codes:
#   0  : success (may be empty array)
#   2  : duplicate canonical title detected (error JSON on stderr)
#   3  : empty canonical title detected (error JSON on stderr)
#   4  : file unreadable in a non-recoverable way (empty array on stdout, exit 0 per FR-003)
#
# Per FR-003: missing/empty/no-checkbox files exit 0 with an empty array.

set -u

# Find this script's directory; export ORCHESTRATE_ROOT, then source common.
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"

jq_required

BACKLOG_PATH="${1:-BACKLOG.md}"

# Missing or empty file → empty array, exit 0 (FR-003).
if [ ! -r "$BACKLOG_PATH" ]; then
    printf '[]\n'
    exit 0
fi

# Use awk to extract top-level checkbox items.
# The regex (POSIX BRE-equivalent): line begins with "- [", a single char in space/X/x, "] ", and at least one more char.
# We capture: the completed flag (space or X), and the rest of the line after "] ".

# Emit a TSV stream "<lineno>\t<completed>\t<rest>" then turn into JSON via jq.
_tsv="$(awk '
    /^- \[[ xX]\] .+$/ {
        # Extract the checkbox char (position 4, 0-indexed: index 3 == position 4)
        ch = substr($0, 4, 1)
        # rest of the line begins at position 7 (after "- [_] ")
        rest = substr($0, 7)
        # Strip trailing whitespace
        sub(/[[:space:]]+$/, "", rest)
        if (rest == "") next
        completed = (ch == "x" || ch == "X") ? "true" : "false"
        # Output TSV: line\tcompleted\trest
        printf "%d\t%s\t%s\n", NR, completed, rest
    }
' "$BACKLOG_PATH")"

if [ -z "$_tsv" ]; then
    printf '[]\n'
    exit 0
fi

# Now convert TSV to a JSON array, splitting each "rest" on the first separator.
# Separator priority: " — " (em-dash) > " -- " > " - ".
# title = pre-separator text, description = post-separator text. Both trimmed.
# canonical title = lowercased, trimmed title.

_json="$(printf '%s\n' "$_tsv" | awk -F'\t' '
    BEGIN {
        printf "["
        first = 1
    }
    {
        line = $1
        completed = $2
        rest = $3

        # Find separator (precedence order). We use a custom find for multi-byte em-dash.
        sep_idx = 0
        sep_len = 0
        # " — "
        s = index(rest, " \xe2\x80\x94 ")
        if (s > 0) { sep_idx = s; sep_len = 5 }
        if (sep_idx == 0) {
            s = index(rest, " -- ")
            if (s > 0) { sep_idx = s; sep_len = 4 }
        }
        if (sep_idx == 0) {
            s = index(rest, " - ")
            if (s > 0) { sep_idx = s; sep_len = 3 }
        }

        if (sep_idx > 0) {
            title = substr(rest, 1, sep_idx - 1)
            desc  = substr(rest, sep_idx + sep_len)
        } else {
            title = rest
            desc  = ""
        }

        # Trim
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", title)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", desc)

        if (title == "") {
            printf "{\"__error__\":\"empty_title\",\"source_line\":%d}", line
            exit 3
        }

        # Canonical = lowercase title. POSIX awk lacks tolower for multi-byte safe handling,
        # but we are operating on UTF-8 byte stream; for ASCII this is correct, and the
        # checked-in grammar treats non-ASCII titles case-sensitively.
        canon = tolower(title)

        if (!first) printf ","
        first = 0
        # JSON-escape the strings. `title` carries the CANONICAL identity (lowercased+trimmed);
        # `original_title` preserves the user-authored casing for display.
        printf "{\"title\":\"%s\",\"original_title\":\"%s\",\"description\":\"%s\",\"completed\":%s,\"source_line\":%d}", \
            jescape(canon), jescape(title), jescape(desc), completed, line
    }
    END { printf "]" }

    function jescape(s,    out, i, c) {
        # Minimal JSON escape: \\, \", \n, \r, \t, control chars.
        gsub(/\\/, "\\\\", s)
        gsub(/"/,  "\\\"", s)
        gsub(/\n/, "\\n",  s)
        gsub(/\r/, "\\r",  s)
        gsub(/\t/, "\\t",  s)
        return s
    }
')"

_awk_rc=$?

if [ "$_awk_rc" -eq 3 ]; then
    printf '{"code":"empty_title","message":"A backlog item has an empty title (item line is `- [ ]   ` with nothing after the marker)."}\n' >&2
    exit 3
fi

# Verify the resulting JSON parses, and detect duplicates by canonical title via jq.
if ! _check="$(printf '%s' "$_json" | jq . 2>/dev/null)"; then
    die "parse-backlog: produced invalid JSON (internal error)"
fi

# Look for duplicate canonical titles among incomplete items.
_dups="$(printf '%s' "$_json" | jq -r '[.[] | select(.completed == false) | .title] | group_by(.) | map(select(length > 1) | .[0]) | .[]')"
if [ -n "$_dups" ]; then
    _dup_line="$(printf '%s\n' "$_dups" | head -n 1)"
    printf '{"code":"duplicate_title","message":"Two or more incomplete backlog items share the canonical title %s. Disambiguate them or mark one - [x].","details":{"canonical_title":"%s"}}\n' \
        "$_dup_line" "$_dup_line" >&2
    exit 2
fi

# Re-emit the JSON cleanly via jq.
printf '%s\n' "$_json" | jq .
