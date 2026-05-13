# Contract: Sample Backlog Template

**Plan**: [../plan.md](../plan.md) — Phase 1 (Design & Contracts)
**Status**: Normative. The asset at `.specify/extensions/orchestrate/assets/sandbox-backlog.md` MUST be byte-equal to the block below.

This contract pins the *exact bytes* of the sample backlog so:
- SC-003 (re-prepare produces identical sandbox state) is byte-verifiable.
- SC-004 (run exercises happy/clarify/skip in one go) is reproducible across maintainer machines and across orchestrator versions.

## Canonical content

The file `.specify/extensions/orchestrate/assets/sandbox-backlog.md` MUST contain exactly the following Markdown (trailing newline included, no BOM, LF line endings):

```markdown
# Sandbox Debug Backlog

This is the canonical sample backlog used by the sandbox test environment.
The orchestrator should process exactly three items: one completes cleanly,
one pauses for clarification, and one is skipped because it is already
checked.

- [ ] Add Pi calculator — Implement a CLI command `pi` that prints the value of mathematical pi truncated to four decimal places (3.1415) on stdout and exits 0. No flags, no input.
- [ ] Add notifications — Wire up notifications.
- [x] Setup project scaffolding — Already shipped in the initial commit; the orchestrator must skip this item.
```

## Item contract

| # | Title (canonical identity, case-normalised, trimmed) | Checkbox | Required orchestrator behavior on a single fresh run |
|---|---|---|---|
| 1 | `add pi calculator` | `- [ ]` | BA pipeline runs to completion without surfacing a clarification request. Dev implements per the spec. Lead merges into `dev`. Final state: `(phase=done, status=complete)`. |
| 2 | `add notifications` | `- [ ]` | `/speckit-clarify` or `/speckit-analyze` MUST surface at least one scope-significant clarification question. BA pauses; feature state: `(status=blocked)` with the question in `pending_clarification`. |
| 3 | `setup project scaffolding` | `- [x]` | Orchestrator MUST skip the item per FR-003a (feature `001`). The item is parseable but is NOT spawned as an active feature. Its state representation is implementation-defined by feature `001` (likely "not present in `state.json` features array" or "recorded with a skipped-already-complete marker"). |

## Title-identity rules (inherited from feature `001`)

- Title is the text between the checkbox and the first separator `—` (em-dash) / `--` / ` - ` (space-hyphen-space).
- Title identity is case-normalised (`tr '[:upper:]' '[:lower:]'`) and whitespace-trimmed.
- The three canonical title identities (above) MUST NOT collide with each other.

## Stability guarantees

- **Byte stability**: re-running `/speckit-sandbox-prepare` on any machine produces a `.sandbox/BACKLOG.md` whose SHA-256 matches the asset's SHA-256. This is the byte-level guarantee behind SC-003.
- **Identity stability**: changes to the sample backlog that alter the canonical identity of any of the three items are a *breaking change* to this contract. A non-breaking change (e.g., rewording a description) is allowed only if the identity stays the same and the orchestrator's expected outcome (happy / clarify / skip) is unchanged.
- **No version bumping in the asset itself**: the asset is single-versioned alongside the orchestrator extension. A breaking change to this contract requires updating the integration test fixtures in lockstep.

## Test obligations

The integration test `sandbox-lifecycle.bats` MUST assert:

1. The byte content of `<repo-root>/.sandbox/BACKLOG.md` after prepare equals the byte content of the asset.
2. The parsed items (via `parse-backlog.sh` inside the sandbox) produce exactly 2 actionable items (the first two `- [ ]`) and 1 skipped item (the `- [x]`).

The integration test SHOULD NOT exercise the full `/speckit-orchestrate` end-to-end run — that would require live Claude Code subagents and burn LLM tokens. End-to-end validation is the maintainer's job and is the entire reason this feature exists.
