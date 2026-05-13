#!/bin/sh
# sandbox-cleanup.sh — remove the .sandbox/ test environment created by sandbox-prepare.sh.
#
# Conformance: POSIX sh. No Bash-isms. Run under /bin/sh on macOS and Linux.
#
# Exit codes:
#   0  sandbox removed, or sandbox was already absent (idempotent no-op).
#   1  cannot proceed (not inside a git working tree; path-safety check
#      failed; or rm itself errored).
#
# Spec references:
#   * FR-007  — refuse to delete any path outside <repo-root>/.sandbox/
#   * FR-015  — no-op when sandbox is absent
#   * FR-016  — proceed even when an orchestrator lock file exists (cleanup
#               is the maintainer's escape hatch)
#   * SC-005  — never delete a file outside the documented sandbox path

set -u

err() { printf 'sandbox-cleanup: %s\n' "$1" >&2; exit "${2:-1}"; }
say() { printf 'sandbox-cleanup: %s\n' "$1"; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || err "not inside a git working tree"
SANDBOX="$REPO_ROOT/.sandbox"

# Idempotent no-op when the sandbox does not exist.
if [ ! -e "$SANDBOX" ]; then
    printf 'sandbox: nothing to clean.\n'
    exit 0
fi

# Path-safety verification (research §4). Resolve via realpath when
# available, otherwise fall back to POSIX `cd && pwd -P`. Compare the
# resolved sandbox to the canonical <repo-root>/.sandbox and refuse if
# they differ — symlinks, traversal, or any override is rejected.
if command -v realpath >/dev/null 2>&1; then
    SANDBOX_REAL="$(realpath -- "$SANDBOX" 2>/dev/null)" \
        || err "cannot resolve sandbox path: $SANDBOX"
else
    SANDBOX_REAL="$(cd -- "$SANDBOX" 2>/dev/null && pwd -P)" \
        || err "cannot resolve sandbox path: $SANDBOX"
fi
EXPECTED_REAL="$(cd -- "$REPO_ROOT" && pwd -P)/.sandbox"

if [ "$SANDBOX_REAL" != "$EXPECTED_REAL" ]; then
    err "refusing to delete: '$SANDBOX' resolved to '$SANDBOX_REAL' but the canonical sandbox path is '$EXPECTED_REAL'"
fi

# Safe to delete. `--` defeats leading-dash filename attacks; the path
# is the canonical resolved one we just verified.
rm -rf -- "$SANDBOX_REAL" || err "rm -rf failed for $SANDBOX_REAL"
printf 'sandbox: removed %s\n' "$SANDBOX"
