---
name: speckit-sandbox-prepare
description: Create a disposable test environment at .sandbox/ inside the host repo for debugging the orchestrator end-to-end.
compatibility: Requires git ≥ 2.5 with worktree support, jq ≥ 1.6, POSIX sh.
metadata:
  author: spec-kit-empty-orchestrator
  source: orchestrate:commands/speckit.sandbox.prepare.md
---

# /speckit-sandbox-prepare — Prepare the orchestrator sandbox

The user has invoked `/speckit-sandbox-prepare`. Your job is to run a single shell helper that creates a fully-wired test environment at `<repo-root>/.sandbox/` so the maintainer can exercise the entire `/speckit-orchestrate` pipeline against a curated sample backlog.

## What this does

The helper script `sandbox-prepare.sh`:

1. Verifies dependencies (`git` with worktree support, `jq`, `realpath` or POSIX fallback).
2. Refuses to recreate the sandbox if an orchestrator lock file is present inside it (an active Lead session is running).
3. Removes any existing `.sandbox/` (via the cleanup helper so the path-safety check runs).
4. Ensures the host's `.gitignore` excludes `.sandbox/`.
5. Initialises a fresh git repository inside `.sandbox/` on branch `main`.
6. Copies the host's `.specify/` and `.claude/` trees into the sandbox.
7. Wipes runtime debris (`state.json`, `events.log`, `lock`, `worktrees/*`) carried over from the host's working state.
8. Writes a sandbox-internal `.gitignore` for orchestrator runtime files.
9. Drops the curated sample `BACKLOG.md` from `assets/sandbox-backlog.md`.
10. Re-runs the orchestrator's own `install.sh` inside the sandbox to validate the install entry point.
11. Commits the initial sandbox state with a Conventional Commits message.
12. Creates a `dev` branch from that commit; leaves HEAD on `main`.
13. Prints `sandbox: prepared at <path>`.

You should not interpret or modify any of this. Just run the helper and surface its output.

## How to invoke

Run the helper via the Bash tool with the absolute path:

```sh
.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh
```

The script takes no arguments. Surface its stdout and stderr to the user verbatim. Report the exit code:

- **0** — sandbox prepared. Tell the user the printed sandbox path and suggest `cd .sandbox/ && /speckit-orchestrate`.
- **2** — refused because of an active orchestrator lock. Surface the lock path from stderr.
- **non-zero (other)** — a dependency or filesystem error. Surface the error.

Do not retry on failure; defer to the user.

## After the script returns

If the sandbox was prepared successfully, hand control back to the user with the next-step suggestion. Do not automatically run `/speckit-orchestrate`; the maintainer drives that themselves.
