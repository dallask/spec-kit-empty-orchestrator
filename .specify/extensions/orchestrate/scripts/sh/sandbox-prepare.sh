#!/bin/sh
# sandbox-prepare.sh — build the disposable .sandbox/ test environment.
#
# Conformance: POSIX sh. No Bash-isms. Run under /bin/sh on macOS and Linux.
#
# Exit codes:
#   0  sandbox prepared.
#   1  dependency missing, host not a git repo, filesystem error, or
#      orchestrator install.sh failed inside the sandbox.
#   2  refused: an active orchestrator lock file is present inside the
#      existing sandbox. The user must stop the running Lead session
#      first.
#
# Spec references:
#   * FR-005, FR-006, FR-008, FR-009, FR-010, FR-012, FR-013, FR-014,
#     FR-017, FR-018
#   * SC-001, SC-003
#   * research.md §1 (seeding strategy), §3 (lock signal), §5 (cp -R)
#   * contracts/sandbox-layout.md
#
# The host repo's working tree state (clean or dirty) is irrelevant per
# FR-018; this script never inspects, modifies, stages, commits, stashes,
# or restores anything in the host beyond the one-line `.gitignore` entry
# required by FR-005.

set -u

err() { printf 'sandbox-prepare: %s\n' "$1" >&2; exit "${2:-1}"; }
say() { printf 'sandbox-prepare: %s\n' "$1"; }

# --- 1. Dependency verification (FR-017) ----------------------------------
#
# Run BEFORE any git invocation so missing-git produces a clear
# "missing required dependency: git" error instead of git's own
# obscure "command not found" via the rev-parse call.

# Required commands. Each entry is `<name>:<install-hint>`.
for _dep in \
    "git:install git ≥ 2.5 with worktree support" \
    "jq:brew install jq | apt-get install jq | apk add jq"
do
    _name="${_dep%%:*}"
    _hint="${_dep##*:}"
    if ! command -v "$_name" >/dev/null 2>&1; then
        err "missing required dependency: $_name ($_hint)"
    fi
done

# git must support worktrees. Probe `git worktree --help` to confirm.
if ! git worktree --help >/dev/null 2>&1; then
    err "git is present but does not support 'git worktree' (need git ≥ 2.5)"
fi

# Path-resolution capability: realpath OR `cd && pwd -P` fallback. The
# fallback is universal so this never blocks, but emit a heads-up if
# realpath is unavailable so the user can install coreutils for sharper
# cleanup-time path-safety.
if ! command -v realpath >/dev/null 2>&1; then
    say "note: realpath(1) not on PATH; using 'cd && pwd -P' fallback for path resolution"
fi

# --- 2. Resolve host repo root --------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || err "not inside a git working tree"

# --- 3. Compute sandbox + lock paths --------------------------------------

SANDBOX="$REPO_ROOT/.sandbox"
LOCK="$SANDBOX/.specify/extensions/orchestrate/lock"
CLEANUP_HELPER="$REPO_ROOT/.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh"
ASSET_BACKLOG="$REPO_ROOT/.specify/extensions/orchestrate/assets/sandbox-backlog.md"
INSTALL_HELPER="$REPO_ROOT/.specify/extensions/orchestrate/install.sh"

[ -f "$CLEANUP_HELPER" ] || err "missing cleanup helper at $CLEANUP_HELPER"
[ -f "$ASSET_BACKLOG" ]  || err "missing sample backlog asset at $ASSET_BACKLOG"
[ -f "$INSTALL_HELPER" ] || err "missing orchestrator install.sh at $INSTALL_HELPER"

# --- 4. Refuse if an active orchestrator Lead is running (FR-014) --------

if [ -e "$LOCK" ]; then
    printf 'sandbox-prepare: refusing to recreate — lock file exists: %s\n' "$LOCK" >&2
    printf 'sandbox-prepare: stop the active /speckit-orchestrate session, then re-run.\n' >&2
    exit 2
fi

# --- 5. Wipe any existing sandbox via the cleanup helper (FR-013) --------

if [ -e "$SANDBOX" ]; then
    say "discarding previous sandbox at $SANDBOX"
    sh "$CLEANUP_HELPER" || err "cleanup of previous sandbox failed; aborting"
fi

# --- 6. Ensure host .gitignore excludes .sandbox/ (FR-005) ---------------

_host_gitignore="$REPO_ROOT/.gitignore"
if [ ! -f "$_host_gitignore" ]; then
    printf '.sandbox/\n' > "$_host_gitignore"
    say "wrote host .gitignore with .sandbox/ exclusion"
elif ! grep -Eq '^\.sandbox/?$' "$_host_gitignore"; then
    # Append, ensuring there's a newline before our entry if the file
    # doesn't end with one.
    if [ -s "$_host_gitignore" ] && [ "$(tail -c 1 "$_host_gitignore" 2>/dev/null || printf '')" != "$(printf '\n')" ]; then
        printf '\n' >> "$_host_gitignore"
    fi
    printf '.sandbox/\n' >> "$_host_gitignore"
    say "appended .sandbox/ to host .gitignore"
fi

# --- 7. mkdir + cd into the sandbox --------------------------------------

mkdir -p "$SANDBOX" || err "failed to create $SANDBOX"
cd "$SANDBOX" || err "failed to cd into $SANDBOX"

# --- 8. git init on branch 'main' ----------------------------------------

git init --quiet --initial-branch=main 2>/dev/null \
    || { git init --quiet && git checkout -B main --quiet; } \
    || err "git init failed"

# --- 9. Copy host's .specify/ and .claude/ into the sandbox (research §5) -

cp -R "$REPO_ROOT/.specify" .specify || err "failed to copy .specify into sandbox"
cp -R "$REPO_ROOT/.claude"  .claude  || err "failed to copy .claude into sandbox"

# --- 10. Remove orchestrator runtime debris that hitchhiked --------------

rm -f .specify/extensions/orchestrate/state.json \
      .specify/extensions/orchestrate/events.log \
      .specify/extensions/orchestrate/lock
# Empty worktrees/ contents but keep the directory; install.sh recreates if absent.
if [ -d .specify/extensions/orchestrate/worktrees ]; then
    find .specify/extensions/orchestrate/worktrees -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
fi

# --- 11. Write sandbox-internal .gitignore (resolves C2 from /speckit-analyze) -

cat > .gitignore <<'EOF'
.specify/extensions/orchestrate/worktrees/
.specify/extensions/orchestrate/state.json
.specify/extensions/orchestrate/events.log
.specify/extensions/orchestrate/lock
EOF

# --- 12. Drop the sample BACKLOG.md (FR-010) -----------------------------

cp "$ASSET_BACKLOG" BACKLOG.md || err "failed to copy sample BACKLOG.md"

# --- 13. Re-run install.sh inside the sandbox (FR-008) -------------------

# Run the orchestrator's own install.sh against the sandbox copy of itself.
# This validates the install entry point the same way a real user invokes
# it. install.sh is idempotent — files copied in step 9 will be re-synced
# from their command sources, runtime files will be (re-)created with 0600.
sh ".specify/extensions/orchestrate/install.sh" \
    || err "orchestrator install.sh failed inside sandbox; aborting"

# --- 14. Commit the initial sandbox state with Conventional Commits (Principle V) -

# Use inline -c flags so the commit works even when the maintainer has no
# global git identity configured (e.g., fresh CI runner).
git add -A
git \
    -c user.email='sandbox@local' \
    -c user.name='Sandbox' \
    commit -m 'chore(sandbox): initial sandbox state' --quiet \
    || err "initial sandbox commit failed"

# --- 15. Create dev branch (FR-009), leave HEAD on main ------------------

git branch dev || err "failed to create dev branch"

# --- 16. Print summary (FR-003) ------------------------------------------

printf 'sandbox: prepared at %s\n' "$SANDBOX"
