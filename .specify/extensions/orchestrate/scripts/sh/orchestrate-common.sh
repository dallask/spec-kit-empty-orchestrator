#!/bin/sh
# orchestrate-common.sh — shared POSIX sh helpers for the Backlog Orchestrator extension.
#
# Conformance:
#   * POSIX sh only (no Bash-isms). Run under /bin/sh on macOS and Linux.
#   * Every helper is idempotent and safe to source multiple times.
#
# Exposed functions:
#   orchestrate_root          # echoes absolute path to .specify/extensions/orchestrate/
#   orchestrate_state_path    # echoes absolute path to state.json
#   orchestrate_events_path   # echoes absolute path to events.log
#   orchestrate_lock_path     # echoes absolute path to the lock file
#   orchestrate_worktree_root # echoes absolute path to the worktrees/ directory
#   orchestrate_schemas_root  # echoes absolute path to schemas/
#   jq_required               # aborts with install hint if jq is unavailable
#   iso_now                   # UTC ISO-8601 timestamp (e.g. 2026-05-12T14:03:11Z)
#   atomic_write FILE         # reads stdin, writes to FILE.tmp, then mv -f FILE.tmp FILE
#   atomic_write_0600 FILE    # like atomic_write but enforces 0600 on the destination
#   with_state_lock CMD ...   # acquire flock (or mkdir-fallback) on the lock file, run CMD ...
#   die MESSAGE [CODE]        # print MESSAGE to stderr, exit CODE (default 1)
#
# All paths are resolved against the repository root, which is the parent of .specify/.

set -u  # treat unset variables as errors (do not set -e — caller manages flow)

# --- path helpers ------------------------------------------------------------

orchestrate_root() {
    # Callers MUST export ORCHESTRATE_ROOT before sourcing this library, OR
    # set ORCHESTRATE_ROOT explicitly. The standard caller boilerplate is:
    #
    #   _dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)"
    #   ORCHESTRATE_ROOT="$(cd "$_dir/../.." 2>/dev/null && pwd -P)"
    #   . "$_dir/orchestrate-common.sh"
    #
    # This is necessary because POSIX sh has no portable way for a sourced
    # library to learn its own path.
    if [ -n "${ORCHESTRATE_ROOT:-}" ]; then
        printf '%s\n' "$ORCHESTRATE_ROOT"
        return
    fi
    die "ORCHESTRATE_ROOT is not set; caller must export it before sourcing orchestrate-common.sh"
}

orchestrate_state_path()    { printf '%s/state.json\n'  "$(orchestrate_root)"; }
orchestrate_events_path()   { printf '%s/events.log\n'  "$(orchestrate_root)"; }
orchestrate_lock_path()     { printf '%s/lock\n'        "$(orchestrate_root)"; }
orchestrate_worktree_root() { printf '%s/worktrees\n'   "$(orchestrate_root)"; }
orchestrate_schemas_root()  { printf '%s/schemas\n'     "$(orchestrate_root)"; }

# --- error helper ------------------------------------------------------------

die() {
    _msg="$1"
    _code="${2:-1}"
    printf 'orchestrate: %s\n' "$_msg" >&2
    exit "$_code"
}

# --- jq guard ----------------------------------------------------------------

jq_required() {
    if ! command -v jq >/dev/null 2>&1; then
        die "jq is required but not found on PATH.
Install:
  macOS:        brew install jq
  Debian/Ubuntu: sudo apt-get install jq
  Alpine:       apk add jq" 127
    fi
}

# --- timestamp ---------------------------------------------------------------

iso_now() {
    # Prefer GNU date / BSD date; fall back to date -u +.
    if date -u +"%Y-%m-%dT%H:%M:%SZ" >/dev/null 2>&1; then
        date -u +"%Y-%m-%dT%H:%M:%SZ"
    else
        die "date(1) does not support -u +%Y-%m-%dT%H:%M:%SZ"
    fi
}

# --- atomic write ------------------------------------------------------------

atomic_write() {
    _dest="$1"
    [ -n "$_dest" ] || die "atomic_write: missing destination"
    _tmp="$_dest.tmp.$$"
    cat >"$_tmp" || die "atomic_write: failed to write tmp file $_tmp"
    mv -f "$_tmp" "$_dest" || {
        rm -f "$_tmp"
        die "atomic_write: failed to rename $_tmp -> $_dest"
    }
}

atomic_write_0600() {
    _dest="$1"
    [ -n "$_dest" ] || die "atomic_write_0600: missing destination"
    _tmp="$_dest.tmp.$$"
    # Create with 0600 from the start. umask 077 + touch is portable.
    (umask 077 && : >"$_tmp") || die "atomic_write_0600: failed to create $_tmp"
    cat >"$_tmp" || { rm -f "$_tmp"; die "atomic_write_0600: write failed for $_tmp"; }
    chmod 0600 "$_tmp" 2>/dev/null || true
    mv -f "$_tmp" "$_dest" || {
        rm -f "$_tmp"
        die "atomic_write_0600: failed to rename $_tmp -> $_dest"
    }
    chmod 0600 "$_dest" 2>/dev/null || true
}

# --- locking -----------------------------------------------------------------
# with_state_lock CMD [ARGS...]
# Acquire an exclusive lock on the lock file, run CMD, release the lock.
# Uses flock(1) when available, otherwise an mkdir-based mutex with retry.

with_state_lock() {
    [ "$#" -ge 1 ] || die "with_state_lock: missing command"
    _lock="$(orchestrate_lock_path)"
    # Ensure the lock file's directory exists.
    mkdir -p "$(dirname "$_lock")"

    if command -v flock >/dev/null 2>&1; then
        # flock with exec on a file descriptor.
        # shellcheck disable=SC2094
        ( flock 9 || die "with_state_lock: failed to acquire flock"
          "$@"
        ) 9>"$_lock"
        return $?
    fi

    # Fallback: mkdir mutex (POSIX, atomic on every modern fs).
    _mutex_dir="$_lock.mutex"
    _waited=0
    while ! mkdir "$_mutex_dir" 2>/dev/null; do
        _waited=$((_waited + 1))
        if [ "$_waited" -gt 600 ]; then
            die "with_state_lock: timed out waiting for $_mutex_dir (>60s)"
        fi
        sleep 0.1 2>/dev/null || sleep 1
    done
    # Ensure cleanup on exit.
    trap 'rmdir "$_mutex_dir" 2>/dev/null || true' INT TERM EXIT
    "$@"
    _rc=$?
    rmdir "$_mutex_dir" 2>/dev/null || true
    trap - INT TERM EXIT
    return "$_rc"
}
