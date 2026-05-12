# spec-kit-empty-orchestrator

Extension for [github/spec-kit](https://github.com/github/spec-kit) that drives the full Spec Kit flow from a backlog: orchestrates BA and Dev agents across isolated worktrees.

## Overview

This Spec Kit extension reads `BACKLOG.md`, treats each item as a separate feature, and runs the pipeline:

`/speckit.specify` → `/speckit.clarify` → `/speckit.plan` → `/speckit.tasks` → `/speckit.analyze` → `/speckit.implement`

Reference implementation pattern: [GenieRobot/spec-kit-maqa-ext](https://github.com/GenieRobot/spec-kit-maqa-ext).

## Claude Code alignment

**Mandatory.** Everything this extension does—how the Lead delegates work, how BA and Dev roles are modeled, tool access, permissions, context boundaries, parallel or background work, and how results return to the main session—**must** follow the official **Claude Code agents architecture** documentation. Do not invent orchestration patterns, nesting rules, or delegation mechanics that contradict those docs.

Start from:

- [Subagents](https://code.claude.com/docs/en/sub-agents) — custom subagents, configuration (Markdown + YAML frontmatter, scopes, tools, models, permissions), delegation from the main conversation, and documented limits (for example, **subagents cannot spawn other subagents**; only the parent session delegates).
- [Agent view / background agents](https://code.claude.com/en/agent-view) — when parallel independent sessions are part of the design.
- [Agent teams](https://code.claude.com/en/agent-teams) — when coordinated multi-session behavior is in scope.

If Spec Kit or this repo’s flow ever conflicts with Claude Code’s documented agent model, **Claude Code docs win**; adjust the extension design accordingly.

## Architecture

Architecture below is a **product-level** description. Its concrete realization (subagent definitions, tool lists, permission modes, hooks, skills, CLI flags, etc.) must map **strictly** to the Claude Code docs linked above.

- **Hub-and-spoke**: the Lead runs in the **main Claude Code session** and coordinates work; only the Lead delegates to subagents, matching Claude Code’s delegation and nesting rules.
- **BA subagent**: specification path — specify, clarify, plan, tasks, analyze. Pauses during clarify/analyze when user input is required, then resumes.
- **Dev subagent**: implements from the completed spec (`/speckit.implement`).
- **Data between agents**: structured JSON, not free-form prose (payload shape is an extension contract; transport and lifecycle still follow Claude Code agent behavior).
- **Configuration**: YAML (same idea as the maqa extension).
- **State**: JSON persistence (same idea as the maqa extension).

## Flow (high level)

1. User runs Claude Code; the **Lead** is the main session that orchestrates the backlog (per [Claude Code alignment](#claude-code-alignment)).
2. Lead reads `BACKLOG.md`.
3. Lead creates as many worktrees as allowed by settings (parallelism cap).
4. Lead delegates to **BA** subagents (per feature / worktree); each runs the full BA flow until done, blocked for clarification, or error.
5. BA returns structured results to Lead; Lead verifies the feature spec is complete.
6. Lead delegates to **Dev** subagents (count per settings); each dev works one feature from its spec in its worktree.
7. Dev returns results to Lead; Lead merges completed features into the configured dev branch.

## Requirements

- **Claude Code agents** — behavior and implementation stay strictly aligned with [Claude Code alignment](#claude-code-alignment) (see section above).
- **System-agnostic** — avoid OS-specific assumptions where possible; document any exceptions.
- **Shell helpers** — use `sh` scripts for helper/automation tasks where appropriate.
- **Commit messages (semantic release)** — all commits that should drive versioning and changelog **must** follow [Conventional Commits](https://www.conventionalcommits.org/) so [semantic-release](https://semantic-release.gitbook.io/) can classify them:

  | Prefix | Release impact |
  |--------|----------------|
  | `fix:` | patch |
  | `feat:` | minor |
  | `BREAKING CHANGE:` in body/footer, or `!` after type (e.g. `feat!: …`) | major |

  Examples:

  - `feat(orchestrator): spawn BA agents from backlog slice`
  - `fix(worktree): clean up stale branch on failure`
  - `docs(readme): document agent JSON contract`
  - `chore(ci): pin action versions`

  Use scopes in parentheses when they clarify the area (`feat(ba): …`, `fix(lead): …`). Merge commits and non-conventional messages will not produce reliable releases; squash or amend before merge when needed.

## References

- [github/spec-kit](https://github.com/github/spec-kit)
- [Claude Code documentation](https://code.claude.com/docs) — index; use [llms.txt](https://code.claude.com/docs/llms.txt) to discover pages.
- [Claude Code — Subagents](https://code.claude.com/docs/en/sub-agents)
- [Claude Code — Agent view](https://code.claude.com/en/agent-view)
- [Claude Code — Agent teams](https://code.claude.com/en/agent-teams)
- [Spec Kit community extensions](https://speckit-community.github.io/extensions/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [semantic-release](https://semantic-release.gitbook.io/)
