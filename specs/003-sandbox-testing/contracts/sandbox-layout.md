# Contract: Post-Prepare Sandbox Layout

**Plan**: [../plan.md](../plan.md) — Phase 1 (Design & Contracts)
**Status**: Normative. `sandbox-prepare.sh` MUST produce this exact layout; `sandbox-lifecycle.bats` MUST assert each point.

This contract enumerates the filesystem state that `<repo-root>/.sandbox/` MUST be in immediately after `/speckit-sandbox-prepare` exits with code 0. Anything not enumerated below is unspecified and SHOULD NOT be asserted by tests (the host's `.specify/` and `.claude/` trees contain many files that are irrelevant to sandbox correctness).

## Directory presence

| Path (relative to `<repo-root>/.sandbox/`) | Required | Type |
|---|---|---|
| `.git/` | yes | directory (a git repository) |
| `.gitignore` | yes | file (excludes orchestrator runtime files inside the sandbox) |
| `BACKLOG.md` | yes | file (byte-equal to `assets/sandbox-backlog.md`) |
| `.specify/extensions/orchestrate/extension.yml` | yes | file |
| `.specify/extensions/orchestrate/orchestrate-config.yml` | yes | file (created by `install.sh` from the template) |
| `.specify/extensions/orchestrate/scripts/sh/orchestrate-common.sh` | yes | file |
| `.specify/extensions/orchestrate/scripts/sh/parse-backlog.sh` | yes | file |
| `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh` | yes | file (carried over; never invoked from inside the sandbox) |
| `.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh` | yes | file (carried over; never invoked from inside the sandbox) |
| `.specify/extensions/orchestrate/assets/sandbox-backlog.md` | yes | file |
| `.specify/extensions/orchestrate/state.json` | yes | file, mode `0600`, empty or `{}` |
| `.specify/extensions/orchestrate/events.log` | yes | file, mode `0600`, empty |
| `.specify/extensions/orchestrate/worktrees/` | yes | directory, empty |
| `.specify/extensions/orchestrate/lock` | **no** (MUST be absent) | — |
| `.specify/extensions/git/` | yes | directory (git extension, intact) |
| `.specify/scripts/bash/check-prerequisites.sh` | yes | file |
| `.specify/scripts/bash/setup-plan.sh` | yes | file |
| `.specify/scripts/bash/create-new-feature.sh` | yes | file |
| `.specify/templates/spec-template.md` | yes | file |
| `.specify/memory/constitution.md` | yes | file |
| `.claude/skills/speckit-orchestrate/SKILL.md` | yes | file |
| `.claude/skills/speckit-specify/SKILL.md` | yes | file (required by the BA subagent) |
| `.claude/skills/speckit-clarify/SKILL.md` | yes | file |
| `.claude/skills/speckit-plan/SKILL.md` | yes | file |
| `.claude/skills/speckit-tasks/SKILL.md` | yes | file |
| `.claude/skills/speckit-analyze/SKILL.md` | yes | file |
| `.claude/skills/speckit-implement/SKILL.md` | yes | file (required by the Dev subagent) |
| `.claude/skills/speckit-sandbox-prepare/SKILL.md` | yes | file (carried over; harmless inside the sandbox) |
| `.claude/skills/speckit-sandbox-cleanup/SKILL.md` | yes | file (carried over; harmless inside the sandbox) |
| `.claude/agents/orchestrate-ba.md` | yes | file |
| `.claude/agents/orchestrate-dev.md` | yes | file |

Note: `feature.json` MAY be present (carried over from host) but is irrelevant — the orchestrator overwrites it on its first feature.

## Git repository state

| Property | Required value |
|---|---|
| `git rev-parse --is-inside-work-tree` | exits 0 |
| `git status --porcelain` | empty (working tree clean) |
| `git rev-parse --abbrev-ref HEAD` | `main` |
| Branches present (`git branch --format='%(refname:short)'`) | exactly `main`, `dev` (order-insensitive) |
| Commits on `main` | exactly 1 |
| Commits on `dev` | exactly 1 (the same commit as `main` HEAD) |
| Commit message (`git log -1 --format=%s`) | `chore(sandbox): initial sandbox state` |

## Host-side side effects

After `/speckit-sandbox-prepare` exits with code 0, the host repository at `<repo-root>` MUST satisfy:

| Property | Required value |
|---|---|
| `git status --porcelain` (excluding `.gitignore` line if just added) | unchanged from pre-prepare snapshot |
| `<repo-root>/.gitignore` contains a line matching `^\.sandbox/?$` | yes (added by prepare if not already present; FR-005) |
| Any other tracked file on host | unchanged |
| Any other untracked file on host (outside `.sandbox/`) | unchanged |

After `/speckit-sandbox-cleanup` exits with code 0, the host MUST satisfy:

| Property | Required value |
|---|---|
| `<repo-root>/.sandbox/` | does not exist |
| `<repo-root>/.gitignore` (and its `.sandbox/` line) | unchanged from before cleanup (cleanup does NOT remove the gitignore entry; FR-005 is one-way) |
| Any other tracked/untracked file on host outside `.sandbox/` | unchanged from pre-prepare snapshot (SC-002, SC-005) |

## Exit code matrix

| Scenario | `/speckit-sandbox-prepare` exit | `/speckit-sandbox-cleanup` exit |
|---|---|---|
| Sandbox absent, all deps present | 0 (sandbox created) | 0 (printed "nothing to clean") |
| Sandbox absent, missing dep (e.g., `git`) | non-zero, dep named, no partial sandbox left behind (FR-017) | n/a |
| Sandbox present, no lock | 0 (existing sandbox removed, fresh sandbox created; FR-013) | 0 (sandbox removed) |
| Sandbox present, lock file exists | non-zero (FR-014); sandbox untouched | 0 (sandbox removed regardless of lock; FR-016) |
| Cleanup invoked with sandbox path resolving outside `<repo-root>/.sandbox` | n/a | non-zero (FR-007); offending path printed; nothing deleted |
| Run from outside a git working tree | non-zero (FR-017 spirit) | non-zero |

## Out-of-scope assertions

Tests SHOULD NOT assert on:
- The exact content of carried-over `.specify/` and `.claude/` files (changes to those propagate naturally).
- Anything inside `.git/` beyond the high-level state shown above.
- The orchestrator's later runtime artifacts (worktrees, populated `state.json`, etc.) — those are the orchestrator's contract, not the sandbox commands'.
