# Backlog Orchestrator Extension

A Spec Kit extension that drives an entire `BACKLOG.md` through the full Spec Kit pipeline using a hub-and-spoke agent architecture.

- **Entry point**: `/speckit-orchestrate` (a Claude Code skill — see `commands/speckit.orchestrate.md`)
- **Subagents**: `orchestrate-ba` and `orchestrate-dev` (see `agents/`)
- **Config**: `orchestrate-config.yml` (defaults in `config-template.yml`)
- **State**: `state.json` (runtime; gitignored)
- **Schemas**: `schemas/` (versioned JSON Schemas for state and agent payloads)
- **Helpers**: `scripts/sh/*.sh` (POSIX `sh` only — see project constitution Principle V)

## Debugging the orchestrator end-to-end

`/speckit-sandbox-prepare` builds a disposable test environment at `.sandbox/` inside the host repo — a fresh git repo with this extension installed, a curated 3-item `BACKLOG.md`, and a `dev` branch — ready to accept `/speckit-orchestrate` without polluting your working tree. `/speckit-sandbox-cleanup` wipes the sandbox completely. See [`/specs/003-sandbox-testing/quickstart.md`](../../../specs/003-sandbox-testing/quickstart.md) for the full debug loop.

## Quick install

```sh
sh .specify/extensions/orchestrate/install.sh
```

This will:
- Create `orchestrate-config.yml` from the template (if absent).
- Sync `commands/speckit.orchestrate.md` → `.claude/skills/speckit-orchestrate/SKILL.md`.
- Sync `agents/orchestrate-{ba,dev}.md` → `.claude/agents/`.
- Ensure runtime files (`state.json`, `events.log`) are mode `0600` on first creation.

## Documentation

Full spec, plan, research, data model, and contracts:

- Spec: [`/specs/001-backlog-orchestrator-extension/spec.md`](../../../specs/001-backlog-orchestrator-extension/spec.md)
- Plan: [`/specs/001-backlog-orchestrator-extension/plan.md`](../../../specs/001-backlog-orchestrator-extension/plan.md)
- Research: [`/specs/001-backlog-orchestrator-extension/research.md`](../../../specs/001-backlog-orchestrator-extension/research.md)
- Data model: [`/specs/001-backlog-orchestrator-extension/data-model.md`](../../../specs/001-backlog-orchestrator-extension/data-model.md)
- Contracts: [`/specs/001-backlog-orchestrator-extension/contracts/`](../../../specs/001-backlog-orchestrator-extension/contracts/)
- Quickstart (user-facing): [`/specs/001-backlog-orchestrator-extension/quickstart.md`](../../../specs/001-backlog-orchestrator-extension/quickstart.md)

## Runtime state location

```
.specify/extensions/orchestrate/
├── orchestrate-config.yml          # user-edited config
├── state.json                      # persisted run state (mode 0600, gitignored)
├── events.log                      # human-readable event log (mode 0600, gitignored)
├── lock                            # flock file for state serialisation (gitignored)
└── worktrees/                      # per-feature git worktrees (gitignored)
    ├── 001/
    ├── 002/
    └── ...
```

## Privacy note

`state.json` and `events.log` MAY contain user-typed clarification answers verbatim. Both files are created with mode `0600` and gitignored. Do not paste secrets into clarification answers — there is no redaction in v1.

## Constitution alignment

This extension implements:

- **Principle I — Claude Code Alignment**: subagents follow the documented `.claude/agents/<name>.md` format; nesting rule (subagents cannot spawn subagents) is honored.
- **Principle II — Hub-and-Spoke Orchestration**: Lead = main Claude Code session, BA and Dev are subagents addressed only via the `Agent` tool.
- **Principle III — Structured JSON Contracts & Typed Persistence**: every Lead↔subagent message validates against `schemas/agent-payload.schema.json`; state is JSON; config is YAML.
- **Principle IV — Specification-First Workflow with Worktree Isolation**: BA pipeline must complete and pass `ba_gate.strictness` before Dev spawn; each feature gets its own `git worktree`.
- **Principle V — Conventional Commits & System-Agnostic Shell Tooling**: integration commits emit Conventional Commits; helpers are POSIX `sh`.
