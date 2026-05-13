---
name: speckit-sandbox-cleanup
description: Remove the .sandbox/ test environment created by /speckit-sandbox-prepare.
compatibility: Requires POSIX sh.
metadata:
  author: spec-kit-empty-orchestrator
  source: orchestrate:commands/speckit.sandbox.cleanup.md
---

# /speckit-sandbox-cleanup — Remove the orchestrator sandbox

The user has invoked `/speckit-sandbox-cleanup`. Your job is to run a single shell helper that deletes `<repo-root>/.sandbox/` after verifying it is the canonical sandbox path.

## What this does

The helper script `sandbox-cleanup.sh`:

1. Resolves the host repo root via `git rev-parse --show-toplevel`.
2. If `.sandbox/` does not exist, prints `sandbox: nothing to clean.` and exits 0.
3. Resolves the canonical path of `.sandbox/` (following symlinks) and refuses to proceed if it doesn't match `<repo-root>/.sandbox/` exactly. Even one byte off → refuse.
4. Removes the entire resolved sandbox directory regardless of internal state — stale worktrees, orphan branches, lock files, dirty files. Cleanup is the maintainer's escape hatch.
5. Prints `sandbox: removed <path>`.

The host repository is never modified (the `.gitignore` entry that prepare added is one-way; cleanup does not remove it).

## How to invoke

Run the helper via the Bash tool with the absolute path:

```sh
.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh
```

The script takes no arguments. Surface its stdout and stderr to the user verbatim. Report the exit code:

- **0** — sandbox removed, or there was nothing to clean. Both are success.
- **1** — path-safety check failed (the sandbox path resolves outside the canonical location) or the underlying `rm` errored. Surface the message verbatim and do not retry.

Do not retry on failure; defer to the user.
