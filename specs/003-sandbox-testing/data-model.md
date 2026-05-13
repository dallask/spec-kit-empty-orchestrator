# Phase 1 Data Model: Sandbox Testing for Orchestrator Extension

**Plan**: [plan.md](./plan.md) — Phase 1 (Design & Contracts)
**Date**: 2026-05-13

This feature is configuration-and-scaffolding tooling; it introduces no new inter-agent payloads, no new persisted JSON state, and no new YAML configuration. The "data model" is therefore filesystem layout, lifecycle state, and one curated text asset. Each entity below describes what the layout looks like, who owns it, and the state transitions it undergoes during prepare/use/cleanup.

---

## Entity: Sandbox

The on-disk test environment produced by `/speckit-sandbox-prepare`. Single instance per host repository, hardcoded to `<repo-root>/.sandbox/`.

### Identity

- **Canonical path**: `<repo-root>/.sandbox/`. Resolved to its real path via `realpath` (see research §4) and compared against the canonical expected path before any destructive operation.
- **Ownership signal**: the sandbox is "owned" by `/speckit-sandbox-prepare` if it contains `.sandbox/.specify/extensions/orchestrate/` and a git repository at `.sandbox/.git/`. Cleanup does not rely on this signal for the deletion decision — the fixed-path safety check (research §4) is the primary defense.

### Required post-prepare layout

The contract enumeration lives in `contracts/sandbox-layout.md`. Summary:

```
.sandbox/
├── .git/                                                # initialised git repo
├── .gitignore                                           # excludes runtime files (worktrees/, state.json, events.log, lock)
├── BACKLOG.md                                           # copy of assets/sandbox-backlog.md (FR-010)
├── .specify/                                            # copy of host .specify (minus runtime state)
│   ├── extensions.yml                                   # contains `installed: [orchestrate, git]` or whatever host had
│   ├── extensions/
│   │   ├── git/                                         # git extension, intact
│   │   └── orchestrate/                                 # orchestrator extension, intact
│   │       ├── extension.yml
│   │       ├── orchestrate-config.yml                   # re-created by install.sh
│   │       ├── commands/
│   │       │   ├── speckit.orchestrate.md
│   │       │   ├── speckit.sandbox.prepare.md           # bundled but never invoked from inside the sandbox
│   │       │   └── speckit.sandbox.cleanup.md           # bundled but never invoked from inside the sandbox
│   │       ├── assets/sandbox-backlog.md
│   │       ├── scripts/                                 # all sh helpers
│   │       ├── agents/
│   │       └── schemas/
│   ├── memory/
│   │   └── constitution.md                              # carried over verbatim
│   ├── scripts/                                         # Spec Kit core scripts
│   ├── templates/                                       # Spec Kit core templates
│   └── feature.json                                     # carried over but irrelevant (orchestrator overwrites)
└── .claude/
    ├── skills/                                          # all host skills, including:
    │   ├── speckit-orchestrate/SKILL.md
    │   ├── speckit-sandbox-prepare/SKILL.md             # present but a no-op inside the sandbox
    │   ├── speckit-sandbox-cleanup/SKILL.md             # present but a no-op inside the sandbox
    │   ├── speckit-specify/SKILL.md                     # core skills needed by BA subagent
    │   ├── speckit-clarify/SKILL.md
    │   ├── speckit-plan/SKILL.md
    │   ├── speckit-tasks/SKILL.md
    │   ├── speckit-analyze/SKILL.md
    │   └── speckit-implement/SKILL.md
    ├── agents/
    │   ├── orchestrate-ba.md
    │   └── orchestrate-dev.md
    └── settings.json                                    # if present on host, carried over; otherwise omitted
```

The post-prepare git state:
- One commit on `main` with message `chore(sandbox): initial sandbox state` (Conventional Commits, Principle V).
- One branch `dev` created from that commit (FR-009, satisfies orchestrator's `merge.target_branch` default).
- HEAD on `main` (so the orchestrator's worktree-create code path creates feature branches off `main` and merges into `dev`, matching real-user behavior).
- Working tree clean (FR-012, so the orchestrator's `safety.on_dirty_tree: refuse` default does not block first `/speckit-orchestrate`).

### State transitions

```
                       /speckit-sandbox-prepare
   ┌─────────────────────────────────────────────────────┐
   │                                                     ▼
   ┌──────────┐                                  ┌────────────────┐
   │  absent  │                                  │    prepared    │
   └──────────┘                                  └────────────────┘
        ▲                                                 │
        │                                                 │  user runs /speckit-orchestrate
        │                                                 │  inside .sandbox/
        │                                                 ▼
        │                                        ┌────────────────┐
        │                                        │    in-use      │
        │                                        │  (lock file    │
        │                                        │   present)     │
        │                                        └────────────────┘
        │                                                 │
        │                                                 │  orchestrator exits (clean
        │                                                 │  or crashed); lock file
        │                                                 │  cleared (or stale)
        │                                                 ▼
        │                                        ┌────────────────┐
        │  /speckit-sandbox-cleanup              │  prepared      │
        └────────────────────────────────────────┤  (potentially  │
                                                 │   stale state) │
                                                 └────────────────┘
```

- **absent**: `<repo-root>/.sandbox/` does not exist.
- **prepared**: `<repo-root>/.sandbox/` exists, contains the required layout above, no lock file.
- **in-use**: `<repo-root>/.sandbox/.specify/extensions/orchestrate/lock` exists. Prepare refuses re-creation in this state (FR-014). Cleanup proceeds anyway (FR-016).

### Invariants

- `realpath(<repo-root>/.sandbox/) == realpath(<repo-root>)/.sandbox` at all times when the sandbox exists. Cleanup refuses if violated (FR-007, SC-005).
- The host repo's `.gitignore` contains a line that excludes `.sandbox/` (added by prepare per FR-005). Once added, prepare does not duplicate.
- The host repo is never modified by sandbox commands beyond the `.gitignore` entry and the creation/deletion of `.sandbox/`.

---

## Entity: Sample Backlog

A versioned 3-item Markdown asset shipped inside the orchestrator extension.

### Source location

`<repo-root>/.specify/extensions/orchestrate/assets/sandbox-backlog.md`

Versioned in source control (Git). Updates require a code change to the extension.

### Runtime location

`<repo-root>/.sandbox/BACKLOG.md` — placed there by prepare via `cp`. The orchestrator inside the sandbox reads this exactly as a real user's `BACKLOG.md`.

### Required structure

Exactly **3 top-level items** in this order (contract enumeration in `contracts/sample-backlog.template.md`):

| # | Marker | Purpose | Expected orchestrator outcome |
|---|--------|---------|-------------------------------|
| 1 | `- [ ]` | Happy-path; description is over-specified | `(phase=done, status=complete)` after merge |
| 2 | `- [ ]` | Clarification-needed; description is deliberately vague | `(status=blocked)` with a clarification question surfaced |
| 3 | `- [x]` | Already-complete; orchestrator must skip per FR-003a | Not processed; recorded in state as skipped |

Concrete titles and descriptions are locked in `contracts/sample-backlog.template.md` so SC-003 (re-prepare produces identical state) is verifiable byte-for-byte.

### Lifecycle

- Created on disk by `sandbox-prepare.sh` (single `cp` call).
- Read by the orchestrator's `parse-backlog.sh` during `/speckit-orchestrate`.
- Wiped by `sandbox-cleanup.sh` together with the rest of `.sandbox/`.
- The maintainer may hand-edit `.sandbox/BACKLOG.md` between runs; the next `/speckit-sandbox-prepare` reverts to the canonical sample (no merge of edits — Assumption).

---

## Entity: Sandbox Lock

A single zero-byte file used as a binary signal that an orchestrator Lead session is active against the sandbox.

### Path

`<repo-root>/.sandbox/.specify/extensions/orchestrate/lock`

Owned by the orchestrator (feature `001`'s `state-write.sh` creates/removes it). Sandbox commands only *read* its presence; they never create or delete it.

### Semantics

- **Present**: a Lead is running, or crashed without removing the lock. `sandbox-prepare.sh` refuses to recreate the sandbox (FR-014). `sandbox-cleanup.sh` ignores it and proceeds (FR-016).
- **Absent**: safe to re-prepare. Safe to cleanup.

### Cross-feature contract

This entity is shared with feature `001`. A change to the lock file's path or semantics in feature `001` must be reflected here. If feature `001` ever versions the lock format (e.g., adds JSON content), `sandbox-prepare.sh`'s presence-check still works as-is (presence is what matters, not content).

---

## Non-entities (explicit non-additions)

The following are explicitly *not* introduced by this feature, to keep the surface area honest:

- **No new JSON Schemas.** This feature touches no inter-agent payloads.
- **No new YAML config.** The orchestrator's `orchestrate-config.yml` is reused unchanged inside the sandbox.
- **No new persisted runtime state.** The sandbox commands are stateless between invocations; their effect is entirely visible on the filesystem.
- **No new `extensions.yml` hooks.** The sandbox commands are user-invoked, not hook-triggered.
