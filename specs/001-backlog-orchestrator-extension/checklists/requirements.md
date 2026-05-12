# Specification Quality Checklist: Backlog Orchestrator Extension

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-05-12
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Initial spec used Assumptions instead of `[NEEDS CLARIFICATION]` markers; `/speckit-clarify` session on 2026-05-12 promoted 5 of those defaults to explicit decisions (see `## Clarifications` in spec.md).
- "Mandatory" sections per the template (User Scenarios & Testing, Requirements, Success Criteria) are all populated. Optional sections (Key Entities, Dependencies) are included because the feature has a data model and external dependencies.

## Clarify session 2026-05-12 (first wave)

- Q1 → Backlog parsing format = single-line top-level checkboxes (`- [ ] Title — description`).
- Q2 → Per-feature state model = two orthogonal fields `phase ∈ {ba, dev, merge, done}` × `status ∈ {queued, running, blocked, failed, complete}`.
- Q3 → Merge strategy = configurable `merge.strategy: squash | merge | rebase`, default `squash`; all strategies emit Conventional-Commits-compliant commits on the target; feature branches retained.  *(Revised in same session — initially squash-only.)*
- Q4 → Default parallelism = `ba: 2, dev: 2`.
- Q5 → Dirty-tree behaviour = configurable `safety.on_dirty_tree: refuse | stash | ignore`, defaulting to `refuse`.

## Clarify session 2026-05-12 (second wave)

- Q6 → Entry-point slash command = `/speckit-orchestrate`.
- Q7 → BA→Dev gate = configurable `ba_gate.strictness: strict | trust | severity_based`, default `strict` (all 4 artifacts on disk + no open clarifications + `ba_done` payload).
- Q8 → Re-run identity rule = case-normalised, whitespace-trimmed title. Description edits do NOT trigger re-processing; removed items stay in state as history.
- Q9 → Failed-feature retry = opt-in `--retry-failed` flag that resets all `status=failed` back to `phase=ba, status=queued`.
- Q10 → Sequence numbering / worktree provisioning = Lead-owned. Lead pre-allocates IDs and creates worktrees+branches before spawning BAs (no concurrent races on the shared sequence).

## Editorial fixes applied during the second wave

- US1 Independent Test: removed phantom `auto_clarify_default: true` config (never defined elsewhere); updated to mention `/speckit-orchestrate`.
- US1 AS-1, US3 AS-1/2/3, SC-002/003/007: replaced stale `merged` / `ba_in_progress` wording with the canonical `phase=done, status=complete` / `phase=ba, status=running` terminology.
- US2/3/5 Independent Tests: now reference `/speckit-orchestrate` rather than the vague "run the Lead".

Deferred to `/speckit-plan` (low-impact for spec phase): concrete performance/latency targets, scalability ceiling on backlog size, runtime observability format (progress reporting cadence), security/privacy posture for clarification logs, subagent hang/timeout policy.
