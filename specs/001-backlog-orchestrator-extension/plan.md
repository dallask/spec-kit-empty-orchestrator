# Implementation Plan: Backlog Orchestrator Extension

**Branch**: `001-backlog-orchestrator-extension` | **Date**: 2026-05-12 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-backlog-orchestrator-extension/spec.md`

## Summary

Build a Spec Kit extension named **`orchestrate`** that drives an entire `BACKLOG.md` through the full Spec Kit pipeline (`/speckit.specify` → … → `/speckit.implement`) using a hub-and-spoke agent architecture. The main Claude Code session ("Lead") owns backlog parsing, sequential feature-ID allocation, worktree provisioning, subagent spawning, clarification fan-in/fan-out, state persistence, and final integration into the dev branch. Two Claude Code subagents — **BA** (runs the specify→analyze pipeline) and **Dev** (runs implement) — execute inside per-feature worktrees and communicate with the Lead exclusively through versioned JSON payloads. The user-facing entry point is a single slash command, `/speckit-orchestrate`.

The implementation is deliberately small in surface area: one Skill (the Lead playbook), two subagent definitions, ~8 POSIX-shell helper scripts, a YAML config, a JSON state file, and a set of JSON Schemas. All "hard" coordination logic lives in deterministic shell scripts driven by the Lead; the LLM-side responsibility is strictly to interpret prompts and emit valid JSON.

## Technical Context

**Language/Version**:
- **POSIX `sh`** for all helper automation (per constitution Principle V). Bash-only constructs are forbidden unless declared in the script header.
- **Markdown + YAML frontmatter** for the Skill (`SKILL.md`) and subagent definitions, matching the Claude Code docs and the existing repo convention.
- **JSON Schema (Draft 2020-12)** for all payload, state, and config schemas.

**Primary Dependencies**:
- **Claude Code** runtime with the subagents feature (cf. <https://code.claude.com/docs/en/sub-agents>).
- **Spec Kit core** ≥ 0.8 with the existing `/speckit.specify`, `/speckit.clarify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`, `/speckit.implement` commands installed in the host project.
- **`git`** ≥ 2.5 with `worktree` support.
- **`jq`** ≥ 1.6 for JSON manipulation in shell scripts (declared as a soft dependency; install instructions documented in `quickstart.md`).
- The existing **`git`** Spec Kit extension (this repo's own `.specify/extensions/git/`), for branch creation (`speckit.git.feature`) and commit hygiene (`speckit.git.commit`).

**Storage**:
- **YAML** config file: `.specify/extensions/orchestrate/orchestrate-config.yml` (per-repo, copied from `config-template.yml` on install).
- **JSON** state file: `.specify/extensions/orchestrate/state.json` (runtime; gitignored).
- **JSON Schemas**: `.specify/extensions/orchestrate/schemas/*.json` (versioned, in source control).

**Testing**:
- **`bats`** (Bash Automated Testing System) for unit testing the POSIX shell helper scripts (run via `bats --pretty tests/extensions/orchestrate/unit/`).
- **Fixture-based integration tests** in `tests/extensions/orchestrate/integration/`: each fixture is a `BACKLOG.md` + expected state-transition trace. The Lead is exercised end-to-end with **mocked** subagents (canned JSON payloads served by a small `sh` mock-agent that reads pre-recorded fixtures). This keeps integration tests deterministic and avoids burning LLM tokens in CI.
- **JSON Schema validation** in CI: every payload fixture in `tests/` is validated against its schema as a pre-commit / CI step.
- **Conventional Commits** validation on PRs via an off-the-shelf linter (declared in `quickstart.md`, not bundled).

**Target Platform**:
- **macOS** (12+) and **Linux** (any modern distro with `git ≥ 2.5` and POSIX `sh`). Primary developer machines and CI runners.
- **Windows**: supported via **WSL2** only (POSIX shell required). Native Windows shells (cmd / PowerShell) are out of scope for v1 — documented in `quickstart.md`.

**Project Type**: Spec Kit **extension**. This is *not* an application or a service; it is a layered set of scripts, agent definitions, and a skill that plug into an existing Spec Kit + Claude Code installation.

**Performance Goals** (resolves the spec's deferred Performance / Scalability questions):
- A 5-item backlog with no clarifications and `parallelism.ba=2, parallelism.dev=2` SHOULD complete in **strictly less wall-clock time** than running the same items sequentially by hand (SC-001 already mandates this).
- Worktree creation overhead per feature MUST be **≤ 5 seconds** on a typical developer laptop (clean repo, ≤ 10 k files).
- State file writes MUST be atomic (write-to-tmp + `mv`) and MUST stay **≤ 50 ms per write** on local disk, even for backlogs of 100 items.
- The Lead MUST cap a single backlog run at **200 features** (configurable via `limits.max_features`; documented hard ceiling to prevent runaway). Exceeding the cap fails fast at startup with a clear error.

**Constraints** (resolves the deferred Observability / Security / Reliability-timeout questions):
- All helper scripts MUST be POSIX `sh`-compatible.
- All inter-agent messages MUST be JSON, schema-validated by the Lead on receive.
- All persisted state MUST be JSON; the state file MUST be safe to inspect with `jq` while the Lead is running (atomic-replace semantics).
- All YAML config keys MUST have documented defaults; missing-key MUST never crash the Lead.
- **Observability** (deferred from spec): the Lead MUST emit a one-line **status event** to stdout (and append to `.specify/extensions/orchestrate/events.log`) on every `phase` or `status` transition. Format: `[ISO8601] feature=<id> phase=<phase> status=<status> note=<short>`. No fancy dashboard in v1.
- **Security / Privacy** (deferred from spec): the state file MAY contain user-typed clarification answers verbatim. The state file MUST be created with mode `0600`; the state directory MUST be gitignored. Documented in `quickstart.md`. No redaction in v1; users with sensitive content are warned in the README to keep `BACKLOG.md` non-secret.
- **Subagent timeout** (deferred from spec): no hard timeout in v1. The user retains the Ctrl-C / kill-session escape hatch; the next `/speckit-orchestrate` invocation resumes from the persisted state. Adding a configurable per-phase timeout is explicitly out of scope and documented as a future enhancement.

**Scale/Scope**:
- Designed for **1–50** backlog items per run (typical product backlog slice).
- Hard cap: **200** features per state file (configurable; see `limits.max_features` above).
- Concurrent worktrees in practice: **2–8** (`parallelism.ba + parallelism.dev`).
- **One Lead session per `BACKLOG.md`**; concurrent Leads on the same backlog are explicitly out of scope (the state file is single-writer).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Five principles in the constitution, each treated as a gate:

| # | Principle | Gate result | Evidence |
|---|-----------|-------------|----------|
| I | Claude Code Alignment (NON-NEGOTIABLE) | ✅ PASS | Subagent definitions live under `.claude/agents/`; behaviours cite specific Claude Code docs in design notes (see `research.md` §1). Lead is the only delegator; subagents do not spawn subagents (matches the documented nesting rule). |
| II | Hub-and-Spoke Orchestration | ✅ PASS | Lead = main Claude Code session, owns backlog/worktree/parallelism/merge. BA and Dev are addressable independently. Pause-for-clarification is the BA returning a `clarification_request` payload to Lead and being re-invoked with the answer — no peer-to-peer messaging. (FR-007, FR-008, FR-011–FR-014.) |
| III | Structured JSON Contracts & Typed Persistence | ✅ PASS | All Lead↔subagent messages are versioned JSON validated against `contracts/agent-payload.schema.json`. Config is YAML; state is JSON (FR-015–FR-017, FR-021–FR-026). |
| IV | Specification-First Workflow with Worktree Isolation | ✅ PASS | Lead refuses to spawn Dev until the configured `ba_gate.strictness` passes (FR-010). Each feature gets its own worktree pre-provisioned by the Lead (FR-004, FR-004a). Parallelism is bounded (FR-005). Merge is Lead-owned (FR-018). |
| V | Conventional Commits & System-Agnostic Shell Tooling | ✅ PASS | All helper scripts are POSIX `sh` under `scripts/sh/`. Merge-step commits are generated from the backlog title via a CC-emitting helper; `rebase` strategy validates each commit and fails-closed on non-CC commits (FR-018, FR-019, FR-020). |

**Result**: All gates PASS. No entries in Complexity Tracking. Re-evaluated after Phase 1 design — no new violations.

## Project Structure

### Documentation (this feature)

```text
specs/001-backlog-orchestrator-extension/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output — JSON Schemas
│   ├── agent-payload.schema.json     # Envelope + all payload subtypes
│   ├── orchestrator-state.schema.json
│   ├── orchestrate-config.schema.json
│   └── backlog-grammar.md            # Formal BACKLOG.md grammar
├── checklists/
│   └── requirements.md  # Carried over from /speckit-specify + /speckit-clarify
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

The extension follows the existing Spec Kit convention used by `.specify/extensions/git/`. There is **no `src/`** — this is a configuration-and-script extension, not an app.

```text
.specify/extensions/orchestrate/
├── extension.yml                # Manifest (id, provides.commands, hooks, config)
├── orchestrate-config.yml       # Per-repo runtime config (copy of config-template.yml)
├── config-template.yml          # Defaults (parallelism, merge, safety, ba_gate, limits)
├── README.md                    # Extension docs (links back to spec + research)
├── commands/
│   └── speckit.orchestrate.md   # Source of truth for the Lead Skill; surfaced as
│                                # .claude/skills/speckit-orchestrate/SKILL.md on install
├── schemas/
│   ├── agent-payload.schema.json     # Imported from contracts/ on install
│   ├── orchestrator-state.schema.json
│   └── orchestrate-config.schema.json
└── scripts/
    └── sh/
        ├── orchestrate-common.sh    # Shared helpers (jq wrappers, logging, state lock)
        ├── parse-backlog.sh         # BACKLOG.md → JSON array of items
        ├── reconcile-state.sh       # Match items vs state by title identity
        ├── allocate-feature.sh      # Pre-allocate next sequential ID + worktree+branch
        ├── create-worktree.sh       # `git worktree add` + initialise feature dir
        ├── integrate-feature.sh     # squash | merge | rebase + Conventional-Commits validate
        ├── state-read.sh            # Read state.json, jq-validate against schema
        ├── state-write.sh           # Atomic write (tmp + mv) with mode 0600
        ├── safety-check.sh          # safety.on_dirty_tree (refuse | stash | ignore)
        ├── retry-failed.sh          # Reset status=failed records back to queued
        └── emit-event.sh            # Status-line + events.log writer

.claude/
├── agents/                          # Per-Claude-Code subagent specification
│   ├── orchestrate-ba.md            # BA subagent (specify→analyze)
│   └── orchestrate-dev.md           # Dev subagent (implement)
└── skills/
    └── speckit-orchestrate/         # Installed from commands/speckit.orchestrate.md
        └── SKILL.md

tests/extensions/orchestrate/
├── unit/                            # bats tests, one per sh helper
│   ├── parse-backlog.bats
│   ├── reconcile-state.bats
│   ├── allocate-feature.bats
│   ├── integrate-feature.bats
│   └── safety-check.bats
├── integration/                     # End-to-end with mocked subagents
│   ├── fixtures/
│   │   ├── three-clean-items/       # BACKLOG.md + canned BA/Dev payloads
│   │   ├── one-blocked-clarification/
│   │   ├── dev-failure-then-retry/
│   │   └── resume-after-kill/
│   ├── mock-subagent.sh             # Reads a fixture's canned JSON and replays it
│   └── run-fixture.bats             # Runs the Lead against each fixture
└── schemas/                         # JSON-Schema validation tests (run in CI)
    └── validate-fixtures.sh

# Runtime state (created by Lead at run time — gitignored):
.specify/extensions/orchestrate/state.json
.specify/extensions/orchestrate/events.log
.specify/extensions/orchestrate/lock
```

**Structure Decision**: Single-project Spec Kit extension layout, mirroring `.specify/extensions/git/`. No `src/` because there is no compiled or interpreted application — the "program" is a Skill plus shell helpers. Subagent definitions live in `.claude/agents/` per the Claude Code subagents documentation. The Lead Skill source is `.specify/extensions/orchestrate/commands/speckit.orchestrate.md` and is surfaced to Claude Code as `.claude/skills/speckit-orchestrate/SKILL.md` (matching every other `/speckit-*` skill in this repo). `tests/extensions/orchestrate/` is the standard Spec Kit test home for extension tests.

## Complexity Tracking

> No constitution gates were violated; this table is intentionally empty.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| _(none)_  | _(none)_   | _(none)_                            |
