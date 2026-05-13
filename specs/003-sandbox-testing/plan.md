# Implementation Plan: Sandbox Testing for Orchestrator Extension

**Branch**: `003-sandbox-testing` | **Date**: 2026-05-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/003-sandbox-testing/spec.md`

## Summary

Ship two new user-facing slash skills — **`/speckit-sandbox-prepare`** and **`/speckit-sandbox-cleanup`** — bundled inside the orchestrator extension (`.specify/extensions/orchestrate/`). The pair lets a maintainer create and destroy a fully-functional, byte-for-byte-faithful test environment at the fixed path **`.sandbox/`** inside the host repository, so they can run the entire `/speckit-orchestrate` pipeline (Lead → BA → Dev → merge) end-to-end against a curated 3-item sample backlog without polluting their working tree.

Implementation is deliberately thin. Each skill is a one-page `SKILL.md` that delegates to a POSIX `sh` helper (`sandbox-prepare.sh`, `sandbox-cleanup.sh`) living next to the existing orchestrator scripts. Prepare seeds the sandbox by copying the host's `.specify/` and `.claude/` trees (minus runtime state), then invokes the orchestrator's existing `install.sh` to validate the install entry point (FR-008). The sample `BACKLOG.md` ships as a versioned asset (`assets/sandbox-backlog.md`) inside the extension. Cleanup resolves its deletion target through `realpath` and refuses any path that is not exactly `<repo-root>/.sandbox/`.

No new inter-agent payloads, no new runtime state, no new schemas: this feature is configuration scaffolding for debugging the existing orchestrator and adds zero surface area to the agent contract.

## Technical Context

**Language/Version**:
- **POSIX `sh`** for `sandbox-prepare.sh` and `sandbox-cleanup.sh` (per constitution Principle V). Bash-only constructs are forbidden unless declared in the script header.
- **Markdown + YAML frontmatter** for the two `SKILL.md` files and their command sources, matching the repo convention used by `/speckit-orchestrate`.
- **Plain Markdown** for `assets/sandbox-backlog.md` (the sample `BACKLOG.md` template).

**Primary Dependencies**:
- The **Backlog Orchestrator Extension** (feature `001`) — its `install.sh` is reused as the install entry point inside the sandbox (FR-008).
- **`git`** ≥ 2.5 (for `git init`, `git checkout -b dev`, initial commit, and for the orchestrator-inside-the-sandbox to do its worktree operations).
- **`cp -R`** or `rsync` (POSIX `cp -R` chosen for portability; see research §1).
- **`realpath`** for path-safety verification (POSIX-2024); GNU `coreutils` provides it on macOS via `brew install coreutils` if absent. Fallback documented in research §4.
- No `jq` dependency for the sandbox commands themselves (they don't read JSON state); `jq` is still required by the orchestrator inside the sandbox.

**Storage**:
- **Sample `BACKLOG.md`** asset: `.specify/extensions/orchestrate/assets/sandbox-backlog.md` (versioned in source control).
- **The sandbox itself**: `.sandbox/` inside the host repo (gitignored, runtime-only).
- **No new persisted state** for the sandbox commands. (The orchestrator inside the sandbox writes its own `state.json` per feature `001`'s contract; the sandbox commands do not touch it.)

**Testing**:
- **`bats`** unit tests for `sandbox-prepare.sh` and `sandbox-cleanup.sh` under `tests/extensions/orchestrate/unit/sandbox-*.bats`.
- **`bats`** integration test under `tests/extensions/orchestrate/integration/sandbox-lifecycle.bats`: spins up a throwaway host repo via `mktemp -d`, copies the extension into it, runs prepare, asserts the sandbox layout (FR-004…FR-012), runs cleanup, asserts the sandbox is gone and the host tree is identical to the pre-prepare snapshot (SC-002, SC-005).
- **Path-safety unit test**: explicitly exercises the cleanup safety check (FR-007) with crafted paths (symlink to `/tmp`, traversal `../`, override env var) and asserts non-zero exit and no deletion.
- **No JSON Schema validation** to add — this feature introduces no JSON payloads or state.

**Target Platform**:
- **macOS** (12+) and **Linux** (any modern distro with `git ≥ 2.5` and POSIX `sh`). Same target as feature `001`.
- **Windows via WSL2** only.

**Project Type**: Increment to the existing **Spec Kit extension** (`orchestrate`). Two new commands, two new helper scripts, one new asset, two new skill manifests, three new test files. No new top-level extension and no new runtime.

**Performance Goals**:
- `/speckit-sandbox-prepare` MUST complete in **≤ 5 seconds** on a typical developer laptop with `.specify/` and `.claude/` totalling under 10 MB. Most of the time is the recursive copy.
- `/speckit-sandbox-cleanup` MUST complete in **≤ 2 seconds** for a freshly-prepared sandbox; bounded by `rm -rf` performance.
- These match SC-001's "interactive debugging" implicit budget and FR-020's "interactive iteration" requirement.

**Constraints**:
- All helpers MUST be POSIX `sh`-compatible (Principle V).
- The host repo MUST NOT be modified by `sandbox-prepare.sh` except for the gitignore entry (FR-005) and the creation of `.sandbox/` (FR-018).
- Cleanup MUST verify `realpath(.sandbox/) == realpath(<repo-root>)/.sandbox` before any `rm` call (FR-007, SC-005).
- The initial sandbox commit message MUST follow Conventional Commits format (Principle V): `chore(sandbox): initial sandbox state`.
- Both skills MUST be invokable with no arguments (FR-001, FR-002).
- Idempotent re-prepare MUST first run the cleanup logic (FR-013), and MUST refuse if a sandbox lock file exists (FR-014).

**Scale/Scope**:
- One sandbox per host repository at a time (Assumption).
- Sample backlog is **exactly 3 items** (FR-010) — one happy-path `- [ ]`, one clarification-needed `- [ ]`, one already-complete `- [x]`.
- Implementation footprint: **2 skill manifests**, **2 sh scripts**, **1 markdown asset**, **3 test files**, **2-line updates** to `extension.yml` and `install.sh`. No edits to existing orchestrator scripts.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Gate result | Evidence |
|---|-----------|-------------|----------|
| I | Claude Code Alignment (NON-NEGOTIABLE) | ✅ PASS | `/speckit-sandbox-prepare` and `/speckit-sandbox-cleanup` are plain Claude Code skills (single `SKILL.md` per skill); they do not spawn subagents, do not introduce new agent nesting rules, and do not change any inter-agent contract. The sandbox they produce hosts a faithful copy of the orchestrator, which already conforms to the Claude Code subagents documentation (cited in feature `001`'s plan). |
| II | Hub-and-Spoke Orchestration | ✅ PASS | No subagents are introduced. Both skills are user-invoked, single-process shell wrappers. The orchestrator running *inside* the sandbox is the same hub-and-spoke implementation as feature `001`; this feature does not change its delegation pattern. |
| III | Structured JSON Contracts & Typed Persistence | ✅ PASS | This feature adds zero new inter-agent payloads and zero new persisted runtime state. The sample `BACKLOG.md` is plain Markdown conforming to the orchestrator's already-versioned `backlog-grammar.md` contract. No YAML/JSON schemas are introduced. |
| IV | Specification-First Workflow with Worktree Isolation | ✅ PASS | The feature itself followed `/speckit-specify` → `/speckit-clarify` → `/speckit-plan` (this document). Inside the sandbox the orchestrator continues to use its existing worktree-per-feature isolation; sandbox creation does not bypass the BA pipeline. The sandbox lives at a single fixed path (`.sandbox/`) so it cannot accidentally share a working tree with the host. |
| V | Conventional Commits & System-Agnostic Shell Tooling | ✅ PASS | Both helper scripts are POSIX `sh` (header: `#!/bin/sh`, no Bashisms). The initial sandbox commit follows CC: `chore(sandbox): initial sandbox state`. No commits on the host repo are generated by the sandbox commands themselves (the maintainer commits their feature work normally). |

**Result**: All 5 gates PASS. Complexity Tracking is empty. Re-evaluated post-Phase-1 design — no new violations.

## Project Structure

### Documentation (this feature)

```text
specs/003-sandbox-testing/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 output — seeding strategy, lock signal, path safety
├── data-model.md        # Phase 1 output — sandbox layout, sample backlog, lock entity
├── quickstart.md        # Phase 1 output — maintainer-facing usage
├── contracts/           # Phase 1 output
│   ├── sandbox-layout.md             # Required post-prepare filesystem layout
│   └── sample-backlog.template.md    # Versioned source of the 3-item BACKLOG.md
├── checklists/
│   └── requirements.md  # Carried over from /speckit-specify + /speckit-clarify
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

This feature adds two skills, two helper scripts, one asset, and three test files to the existing `orchestrate` extension. It also extends `extension.yml` and `install.sh` to advertise/install the new skills.

```text
.specify/extensions/orchestrate/
├── extension.yml                       # MODIFY — declare the two new commands
├── install.sh                          # MODIFY — sync the two new skills
├── commands/
│   ├── speckit.orchestrate.md          # unchanged
│   ├── speckit.sandbox.prepare.md      # NEW — source for /speckit-sandbox-prepare SKILL.md
│   └── speckit.sandbox.cleanup.md      # NEW — source for /speckit-sandbox-cleanup SKILL.md
├── assets/                              # NEW directory
│   └── sandbox-backlog.md              # NEW — versioned 3-item sample BACKLOG.md
└── scripts/
    └── sh/
        ├── orchestrate-common.sh       # unchanged
        ├── sandbox-prepare.sh          # NEW — does seed + install + commit + dev branch
        ├── sandbox-cleanup.sh          # NEW — path-safety check + rm -rf .sandbox/
        └── (all other orchestrator scripts unchanged)

.claude/skills/
├── speckit-orchestrate/                # unchanged
├── speckit-sandbox-prepare/            # NEW (created by install.sh from commands/)
│   └── SKILL.md
└── speckit-sandbox-cleanup/            # NEW (created by install.sh from commands/)
    └── SKILL.md

tests/extensions/orchestrate/
├── unit/
│   ├── (existing bats files unchanged)
│   ├── sandbox-prepare.bats            # NEW — path-safety, seeding correctness, idempotency
│   └── sandbox-cleanup.bats            # NEW — path-safety, no-op-when-absent, lock-respect
└── integration/
    └── sandbox-lifecycle.bats          # NEW — prepare → assert layout → cleanup → assert host unchanged

# Runtime (created by /speckit-sandbox-prepare at run time — gitignored):
.sandbox/                                # The sandbox itself
├── .git/
├── .specify/                            # Copy of host .specify (sans runtime state)
├── .claude/                             # Copy of host .claude
├── BACKLOG.md                           # Copy of assets/sandbox-backlog.md
└── (one initial CC-compliant commit on dev branch)
```

**Structure Decision**: The two sandbox skills live inside the existing `orchestrate` extension because the spec's Assumption "Sandbox commands live with the orchestrator extension" was re-confirmed in the clarification session. No new top-level extension; no new `src/`. The asset (`sandbox-backlog.md`) is versioned alongside the orchestrator's other source files. Runtime state (the `.sandbox/` directory) lives at a single fixed path inside the host repo and is excluded from host git tracking by an entry in the host's `.gitignore` (added by prepare).

## Complexity Tracking

> No constitution gates were violated; this table is intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _(none)_  | _(none)_   | _(none)_                            |
