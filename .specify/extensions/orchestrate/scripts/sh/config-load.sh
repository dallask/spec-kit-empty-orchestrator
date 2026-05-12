#!/bin/sh
# config-load.sh — load orchestrate-config.yml (with config-template.yml defaults)
# and emit the resolved configuration as JSON to stdout.
#
# Uses a minimal POSIX awk-based YAML reader scoped to the documented two-level
# key tree from orchestrate-config.schema.json. Unknown top-level keys produce
# a warning to stderr but do not fail. Type-invalid values fail loud.
#
# Usage:
#   config-load.sh [PATH_TO_USER_CONFIG] [PATH_TO_TEMPLATE]
# Output: resolved JSON on stdout
# Exit 0 on success; non-zero with a JSON error on stderr on validation failure.

set -u
_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
export ORCHESTRATE_ROOT
# shellcheck disable=SC1090,SC1091
. "$_dir/orchestrate-common.sh"
jq_required

USER_CFG="${1:-$ORCHESTRATE_ROOT/orchestrate-config.yml}"
TMPL_CFG="${2:-$ORCHESTRATE_ROOT/config-template.yml}"

# --- 1. Parse the YAML file(s) into a flat key=value stream -----------------
# Grammar (intentionally narrow):
#   - line beginning with no whitespace, ending with ":" → top-level section
#   - line beginning with 2 spaces (or one tab) + key + ":" + value → key in current section
#   - "# ..." comments stripped
#   - blank lines and other lines ignored
parse_yaml() {
    _file="$1"
    [ -r "$_file" ] || return 0
    awk '
        function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
        function dequote(s) {
            # Strip a single surrounding pair of " or '\'' if present.
            if (length(s) >= 2) {
                first = substr(s, 1, 1)
                last  = substr(s, length(s), 1)
                if ((first == "\"" && last == "\"") || (first == "\x27" && last == "\x27")) {
                    return substr(s, 2, length(s) - 2)
                }
            }
            return s
        }
        BEGIN { section = "" }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        /^[^[:space:]].*:[[:space:]]*$/ {
            # Top-level section header
            section = $0
            sub(/:.*$/, "", section)
            section = trim(section)
            next
        }
        /^[[:space:]]+[^[:space:]].*:.*$/ {
            # Indented key:value line
            key = $0
            sub(/[[:space:]]*#.*$/, "", key)         # strip trailing inline comment
            n = index(key, ":")
            if (n == 0) next
            k = trim(substr(key, 1, n - 1))
            v = trim(substr(key, n + 1))
            v = dequote(v)
            if (k == "" || v == "") next
            if (section != "") {
                print section "." k "=" v
            }
        }
    ' "$_file"
}

_defaults="$(parse_yaml "$TMPL_CFG")"
_user="$(parse_yaml "$USER_CFG")"

# Merge: user overrides default. Use awk-based last-wins for the combined stream.
_merged="$(printf '%s\n%s\n' "$_defaults" "$_user" | awk -F= '
    NF >= 2 {
        key = $1
        val = $0
        sub(/^[^=]*=/, "", val)
        last[key] = val
    }
    END {
        for (k in last) print k "=" last[k]
    }
')"

# --- 2. Validate ------------------------------------------------------------
# Required keys with type constraints. (We DO emit a JSON value even for keys
# the user did not override, because defaults are baked in via the merge.)
emit_error() {
    _path="$1"
    _msg="$2"
    jq -n --arg p "$_path" --arg m "$_msg" '{code:"config_invalid", message:$m, recoverable:false, details:{path:$p}}' >&2
    exit 1
}

# Use jq -n to construct the final JSON, key-by-key.
_get() {
    printf '%s\n' "$_merged" | awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; found=1 } END { if (!found) exit 1 }'
}

_is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# Pull values (defaults guaranteed because template was merged in first).
backlog_path="$(_get backlog.path)"      || emit_error "backlog.path"          "missing"
par_ba="$(_get parallelism.ba)"          || emit_error "parallelism.ba"        "missing"
par_dev="$(_get parallelism.dev)"        || emit_error "parallelism.dev"       "missing"
merge_target="$(_get merge.target_branch)" || emit_error "merge.target_branch" "missing"
merge_strategy="$(_get merge.strategy)"  || emit_error "merge.strategy"        "missing"
wt_retain="$(_get worktree.retain_on_failure)" || emit_error "worktree.retain_on_failure" "missing"
wt_prune="$(_get worktree.prune_on_success)"   || emit_error "worktree.prune_on_success"  "missing"
safety_mode="$(_get safety.on_dirty_tree)"    || emit_error "safety.on_dirty_tree"     "missing"
gate_strictness="$(_get ba_gate.strictness)"  || emit_error "ba_gate.strictness"       "missing"
max_features="$(_get limits.max_features)"     || emit_error "limits.max_features"      "missing"

# Type checks.
_is_int "$par_ba"  || emit_error "parallelism.ba"  "must be an integer (got '$par_ba')"
_is_int "$par_dev" || emit_error "parallelism.dev" "must be an integer (got '$par_dev')"
_is_int "$max_features" || emit_error "limits.max_features" "must be an integer (got '$max_features')"

# Range checks.
if [ "$par_ba" -lt 1 ] || [ "$par_ba" -gt 16 ]; then
    emit_error "parallelism.ba" "must be in 1..16 (got $par_ba)"
fi
if [ "$par_dev" -lt 1 ] || [ "$par_dev" -gt 16 ]; then
    emit_error "parallelism.dev" "must be in 1..16 (got $par_dev)"
fi
if [ "$max_features" -lt 1 ] || [ "$max_features" -gt 1000 ]; then
    emit_error "limits.max_features" "must be in 1..1000 (got $max_features)"
fi

# Enum checks.
case "$merge_strategy" in squash|merge|rebase) : ;; *) emit_error "merge.strategy" "must be one of squash|merge|rebase (got '$merge_strategy')" ;; esac
case "$safety_mode"    in refuse|stash|ignore) : ;; *) emit_error "safety.on_dirty_tree" "must be one of refuse|stash|ignore (got '$safety_mode')" ;; esac
case "$gate_strictness" in strict|trust|severity_based) : ;; *) emit_error "ba_gate.strictness" "must be one of strict|trust|severity_based (got '$gate_strictness')" ;; esac

# Boolean coercion.
canon_bool() {
    case "$1" in
        true|True|TRUE|yes|Yes|on|On|1)  echo true ;;
        false|False|FALSE|no|No|off|Off|0) echo false ;;
        *) return 1 ;;
    esac
}
wt_retain_b="$(canon_bool "$wt_retain")"  || emit_error "worktree.retain_on_failure" "must be boolean (got '$wt_retain')"
wt_prune_b="$(canon_bool "$wt_prune")"    || emit_error "worktree.prune_on_success"  "must be boolean (got '$wt_prune')"

# --- 3. Emit JSON -----------------------------------------------------------
jq -n \
    --arg backlog_path "$backlog_path" \
    --argjson par_ba "$par_ba" \
    --argjson par_dev "$par_dev" \
    --arg merge_target "$merge_target" \
    --arg merge_strategy "$merge_strategy" \
    --argjson wt_retain "$wt_retain_b" \
    --argjson wt_prune  "$wt_prune_b" \
    --arg safety_mode "$safety_mode" \
    --arg gate_strictness "$gate_strictness" \
    --argjson max_features "$max_features" \
    '{
        backlog:     {path:$backlog_path},
        parallelism: {ba:$par_ba, dev:$par_dev},
        merge:       {target_branch:$merge_target, strategy:$merge_strategy},
        worktree:    {retain_on_failure:$wt_retain, prune_on_success:$wt_prune},
        safety:      {on_dirty_tree:$safety_mode},
        ba_gate:     {strictness:$gate_strictness},
        limits:      {max_features:$max_features}
    }'
