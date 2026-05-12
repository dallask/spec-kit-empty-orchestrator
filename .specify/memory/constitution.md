<!--
SYNC IMPACT REPORT
==================
Version change: (uninitialized template) → 1.0.0
Bump rationale: MAJOR — initial ratification of the project constitution; first
concrete codification of governance and non-negotiable principles.

Modified principles: N/A (initial ratification — no prior named principles)
Added principles:
  - I. Claude Code Alignment (NON-NEGOTIABLE)
  - II. Hub-and-Spoke Orchestration
  - III. Structured JSON Contracts & Typed Persistence
  - IV. Specification-First Workflow with Worktree Isolation
  - V. Conventional Commits & System-Agnostic Shell Tooling
Added sections:
  - Additional Constraints (Stack & Authoritative References)
  - Development Workflow & Quality Gates
  - Governance
Removed sections: N/A (template scaffolding replaced)

Templates / runtime docs reviewed:
  - .specify/templates/plan-template.md            ✅ reviewed — Constitution Check
                                                    section uses dynamic
                                                    "[Gates determined based on
                                                    constitution file]" placeholder;
                                                    no edit required, but /speckit-plan
                                                    MUST now derive gates from the
                                                    five principles below.
  - .specify/templates/spec-template.md            ✅ reviewed — generic; no
                                                    principle-specific references.
  - .specify/templates/tasks-template.md           ✅ reviewed — generic; constitution
                                                    does not add/remove principle-driven
                                                    task categories beyond what already
                                                    exists.
  - .specify/templates/checklist-template.md       ✅ reviewed — generic.
  - .specify/templates/commands/*.md               ✅ N/A — directory does not exist;
                                                    .claude/skills/ serves the command
                                                    role and contains no outdated
                                                    agent-specific references.
  - README.md                                      ✅ reviewed — already mandates
                                                    Claude Code alignment; consistent.
  - CLAUDE.md                                      ✅ reviewed — stub only; no
                                                    principle references.

Follow-up TODOs: none.
-->

# Spec Kit Empty Orchestrator Constitution

## Core Principles

### I. Claude Code Alignment (NON-NEGOTIABLE)

The official **Claude Code agents architecture** documentation is the authoritative
source for everything this extension does: subagent definitions, delegation
mechanics, nesting rules, tool access, permission modes, parallel/background
execution, and how results return to the main session.

- The extension MUST NOT invent orchestration patterns, nesting rules, or
  delegation mechanics that contradict the documented Claude Code agent model.
- When Spec Kit guidance or this repository's flow conflicts with Claude Code
  docs, **Claude Code docs win**; the extension MUST be adjusted, not the docs
  worked around.
- Implementations MUST cite the relevant Claude Code page (Subagents, Agent view,
  Agent teams) in design notes when introducing or changing agent behavior, so
  reviewers can verify alignment.

**Rationale**: This extension is a thin orchestrator over a vendor-owned agent
runtime. Drift from the upstream model is the single largest source of
behavioral bugs and unportable code; treating the docs as binding contracts
keeps the extension upgradeable as Claude Code evolves.

### II. Hub-and-Spoke Orchestration

The Lead, running in the **main Claude Code session**, is the only coordinator
that delegates work. BA and Dev subagents are spokes; they execute, report
back, and terminate.

- Subagents MUST NOT spawn other subagents. Only the parent (Lead) session
  delegates. This mirrors Claude Code's documented limit and is non-negotiable.
- The Lead MUST own all backlog reading, worktree creation, parallelism caps,
  feature merge decisions, and final acceptance.
- BA and Dev subagents MUST be addressable independently and MUST be capable of
  pausing for user input (BA during `/speckit.clarify` and `/speckit.analyze`)
  and resuming without losing context.

**Rationale**: A single delegation point is the only structure that stays legal
under Claude Code's nesting rules and remains debuggable; any mesh or peer-to-peer
pattern collapses into untraceable state.

### III. Structured JSON Contracts & Typed Persistence

All data exchanged between the Lead and subagents, and all persisted runtime
state, MUST use machine-checkable formats.

- Inter-agent payloads (Lead ↔ BA, Lead ↔ Dev) MUST be **structured JSON**, not
  free-form prose. Payload shape is an extension contract and MUST be versioned.
- Configuration MUST be **YAML**.
- Runtime state MUST be persisted as **JSON**.
- Free-form prose, screen-scraped output, or implicit conventions are forbidden
  as primary data exchange or storage formats.

**Rationale**: Free-form prose between agents is not testable, not diffable, and
silently regresses. Constraining contracts and storage to typed formats makes
the orchestrator's behavior reproducible and the state inspectable.

### IV. Specification-First Workflow with Worktree Isolation

No Dev work begins on a feature until its BA pipeline has completed and produced
a verified specification, and every feature MUST execute in its own isolated
worktree.

- The BA pipeline order MUST be:
  `/speckit.specify` → `/speckit.clarify` → `/speckit.plan` → `/speckit.tasks`
  → `/speckit.analyze`. The Lead MUST verify the spec is complete before
  delegating to Dev.
- Each feature MUST run in its own Git worktree; cross-feature work in a shared
  working tree is forbidden.
- Parallelism (worktree count and concurrent BA/Dev subagents) MUST be bounded
  by the configured cap; the Lead MUST refuse to exceed it.
- Merging a completed feature into the configured dev branch is the Lead's
  responsibility and MUST occur only after Dev returns a successful structured
  result.

**Rationale**: Skipping spec steps or sharing a working tree across features is
how parallel orchestrators corrupt state and ship under-specified work. Worktree
isolation plus a strict spec-before-code gate is what makes parallelism safe.

### V. Conventional Commits & System-Agnostic Shell Tooling

All commits that drive versioning and changelog generation MUST follow
[Conventional Commits](https://www.conventionalcommits.org/) so
[semantic-release](https://semantic-release.gitbook.io/) can classify them, and
all helper automation MUST stay portable.

- Commit prefixes MUST classify intent: `fix:` (patch), `feat:` (minor),
  `BREAKING CHANGE:` in body/footer or `!` after type (major). Other recognized
  types (`docs:`, `chore:`, `refactor:`, `test:`, `ci:`) MUST be used for
  non-release-driving work. Scopes (`feat(orchestrator): …`) SHOULD be used
  when they clarify the area.
- Merge commits and non-conventional messages MUST be squashed or amended
  before merge so semantic-release can produce reliable releases.
- Helper scripts MUST be `sh`-compatible and MUST avoid OS-specific assumptions
  where possible. Any unavoidable OS-specific dependency MUST be documented in
  the script header and in the relevant feature spec.

**Rationale**: Semantic-release has no judgment beyond commit metadata; broken
commit hygiene silently breaks releases. Likewise, the extension targets
heterogeneous developer machines, so portability is a hard requirement, not a
preference.

## Additional Constraints (Stack & Authoritative References)

The following are binding constraints on technology choices and reference
material. Changes require an amendment under the Governance section.

- **Runtime**: Claude Code (CLI, desktop, web, IDE extensions). The orchestrator
  is built as a Claude Code extension; it MUST NOT assume any other runtime.
- **Workflow framework**: [github/spec-kit](https://github.com/github/spec-kit).
  The BA pipeline phases are defined by Spec Kit and MUST NOT be reordered or
  silently skipped.
- **Helper scripts**: `sh` (POSIX shell). Bash-only constructs are discouraged
  unless declared in the script header.
- **Configuration format**: YAML. **State format**: JSON. **Inter-agent
  payload format**: JSON.
- **Authoritative external references** (treat as load-bearing; consult before
  changing agent behavior):
  - Claude Code — Subagents: <https://code.claude.com/docs/en/sub-agents>
  - Claude Code — Agent view: <https://code.claude.com/en/agent-view>
  - Claude Code — Agent teams: <https://code.claude.com/en/agent-teams>
  - Claude Code docs index: <https://code.claude.com/docs> (use
    <https://code.claude.com/docs/llms.txt> for discovery).
  - Conventional Commits: <https://www.conventionalcommits.org/>
  - semantic-release: <https://semantic-release.gitbook.io/>

## Development Workflow & Quality Gates

The following gates apply to every change merged to the configured dev branch.
They are enforced by reviewers and, where automatable, by CI.

- **Spec completeness gate**: A feature MUST have a spec produced by the full
  BA pipeline (Principle IV) before any Dev task is implemented. PRs that
  introduce code without a corresponding completed spec MUST be rejected.
- **Constitution Check gate**: `/speckit-plan` MUST run a Constitution Check
  derived from the five principles above before Phase 0 research and again
  after Phase 1 design. Violations MUST be recorded in the plan's Complexity
  Tracking table with a justified rationale or the plan MUST be revised.
- **Conventional Commits gate**: Every commit on a feature branch MUST follow
  Principle V's commit format. Squash-merge titles MUST also be conventional.
- **Agent contract gate**: Any change to Lead↔BA or Lead↔Dev payloads MUST be
  expressed as a versioned JSON schema change, MUST update consumers, and MUST
  cite the Claude Code docs section that authorizes the new behavior.
- **Portability gate**: New helper scripts MUST run under `sh` on macOS and
  Linux. OS-specific exceptions MUST be declared in the script header and in
  the feature spec.
- **PR review**: Every PR MUST be reviewed against this constitution. Reviewers
  MUST link any violation to the specific principle or section breached.

## Governance

This constitution supersedes other practices, conventions, or ad-hoc decisions
within this repository. Where a guideline elsewhere conflicts with this
document, this document wins until amended.

- **Amendment procedure**: Amendments are proposed by PR that (a) edits this
  file, (b) updates `Version`, `Last Amended`, and the Sync Impact Report at
  the top, and (c) updates every dependent template or runtime doc affected by
  the change. Amendments require approval from a project maintainer.
- **Versioning policy** (semantic versioning of the constitution itself):
  - **MAJOR**: Backward-incompatible governance changes, principle removals,
    or principle redefinitions that invalidate prior compliance assumptions.
  - **MINOR**: A new principle or section is added, or an existing principle is
    materially expanded.
  - **PATCH**: Clarifications, wording, typo fixes, or non-semantic refinements
    that do not change what is required, prohibited, or allowed.
- **Compliance review**: At least once per release cycle, the maintainer team
  MUST confirm that templates (`plan-template.md`, `spec-template.md`,
  `tasks-template.md`, `checklist-template.md`), runtime guidance docs
  (`README.md`, `CLAUDE.md`), and skill definitions under `.claude/skills/`
  remain consistent with the principles above. Drift MUST be corrected by
  amendment, not by silently diverging implementations.
- **Runtime guidance**: Day-to-day implementation guidance for agents lives in
  `CLAUDE.md` and the per-feature plan. Those documents MUST defer to this
  constitution on any conflict.

**Version**: 1.0.0 | **Ratified**: 2026-05-12 | **Last Amended**: 2026-05-12
