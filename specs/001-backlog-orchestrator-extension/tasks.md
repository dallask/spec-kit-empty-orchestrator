---

description: "Task list for backlog-orchestrator-extension"
---

# Tasks: Backlog Orchestrator Extension

**Input**: Design documents from `/specs/001-backlog-orchestrator-extension/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Tests**: Test tasks are included because the plan declares a concrete testing stack (`bats` + fixture-based integration tests + JSON-Schema validation). They are NOT structured as TDD-style red-bar gates — they are concurrent deliverables of each story.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. The MVP is User Story 1 + User Story 2 together (both are P1 and the second is meaningless without the first).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks in this phase)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4, US5)
- All file paths are repo-relative (the implementer's `pwd` is the repo root)

## Path Conventions

This is a Spec Kit **extension**, not an app. There is **no `src/`**. Code lives in:

- `.specify/extensions/orchestrate/` — extension home (manifest, config, schemas, sh scripts)
- `.claude/agents/` — BA and Dev subagent definitions
- `.claude/skills/speckit-orchestrate/` — installed skill (mirror of `commands/speckit.orchestrate.md`)
- `tests/extensions/orchestrate/` — bats unit + integration fixture tests

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Bring the extension's directory layout, manifest, config template, and gitignore entries into existence so subsequent phases have somewhere to put files.

- [ ] T001 Create the extension directory tree: `.specify/extensions/orchestrate/`, `.specify/extensions/orchestrate/scripts/sh/`, `.specify/extensions/orchestrate/schemas/`, `.specify/extensions/orchestrate/commands/`, `.claude/agents/` (already exists; ensure), `.claude/skills/speckit-orchestrate/`, `tests/extensions/orchestrate/unit/`, `tests/extensions/orchestrate/integration/`, `tests/extensions/orchestrate/integration/fixtures/`, `tests/extensions/orchestrate/schemas/`
- [ ] T002 [P] Author the extension manifest at `.specify/extensions/orchestrate/extension.yml` declaring: `extension.id: orchestrate`, version `1.0.0`, the single command `speckit.orchestrate` (file `commands/speckit.orchestrate.md`), the config file `orchestrate-config.yml` (template `config-template.yml`), `requires.speckit_version: ">=0.8.0"` and `requires.tools: [git, jq]`. Mirror the structural conventions used by `.specify/extensions/git/extension.yml`.
- [ ] T003 [P] Author the config defaults at `.specify/extensions/orchestrate/config-template.yml`, populating every key listed in `specs/001-backlog-orchestrator-extension/contracts/orchestrate-config.schema.json` with its documented default value and an inline `#` comment describing it.
- [ ] T004 [P] Write the extension overview at `.specify/extensions/orchestrate/README.md` linking back to `specs/001-backlog-orchestrator-extension/spec.md`, `plan.md`, `quickstart.md`, and `contracts/`. Document the install command, the single user-facing entry point (`/speckit-orchestrate`), and where runtime state lives.
- [ ] T005 Register the extension in `.specify/extensions.yml` by appending `orchestrate` to the `installed:` list (keep the existing `installed: []` syntax — modify it to `installed: [orchestrate]`).
- [ ] T006 [P] Add gitignore entries to `.gitignore` covering `.specify/extensions/orchestrate/state.json`, `.specify/extensions/orchestrate/events.log`, `.specify/extensions/orchestrate/lock`, `.specify/extensions/orchestrate/worktrees/`, and `.specify/extensions/orchestrate/orchestrate-config.yml.local` (allow user-local override files).

**Checkpoint**: The directory skeleton, manifest, defaults config, README stub, registry entry, and gitignore are in place. Nothing executable yet, but the layout is real.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: All shared shell helpers and schemas that every user story will reuse. **No user story phase can begin until Phase 2 is complete.**

- [ ] T007 [P] Copy the three JSON schemas from `specs/001-backlog-orchestrator-extension/contracts/` to `.specify/extensions/orchestrate/schemas/`: `agent-payload.schema.json`, `orchestrator-state.schema.json`, `orchestrate-config.schema.json`. (`contracts/backlog-grammar.md` stays in the spec, not in the runtime extension.)
- [ ] T008 Implement the shared shell library at `.specify/extensions/orchestrate/scripts/sh/orchestrate-common.sh`. MUST expose: `jq_required` (aborts with install hint if `jq` is missing), `iso_now` (UTC ISO-8601 timestamp), `atomic_write FILE` (writes stdin to `FILE.tmp` then `mv FILE.tmp FILE`), `with_state_lock CMD` (acquires `flock` on `.specify/extensions/orchestrate/lock`, runs CMD, releases; falls back to `mkdir`-based mutex if `flock` is unavailable). POSIX `sh` only; no Bash-isms.
- [ ] T009 [P] Implement `parse-backlog.sh` at `.specify/extensions/orchestrate/scripts/sh/parse-backlog.sh`. Reads `BACKLOG.md` (path from `$1`) and emits a JSON array of `{title, original_title, description, completed, source_line}` objects to stdout. MUST implement the regex and split rules from `specs/001-backlog-orchestrator-extension/contracts/backlog-grammar.md` exactly. MUST detect duplicate canonical titles and exit `2` with a `code=duplicate_title` JSON error to stderr.
- [ ] T010 [P] Implement `state-read.sh` at `.specify/extensions/orchestrate/scripts/sh/state-read.sh`. Sources `orchestrate-common.sh`. Reads `.specify/extensions/orchestrate/state.json`, validates it against `schemas/orchestrator-state.schema.json` (using `ajv-cli` if installed, else a `jq`-based shape check that covers the required-field subset), and emits the document to stdout. On missing-file, emits an empty initial state.
- [ ] T011 [P] Implement `state-write.sh` at `.specify/extensions/orchestrate/scripts/sh/state-write.sh`. Reads a candidate state document from stdin, recomputes `counters` from `features[]`, sets `updated_at = iso_now`, sets file mode `0600` on output, and uses `atomic_write` from `orchestrate-common.sh` to persist.
- [ ] T012 [P] Implement `emit-event.sh` at `.specify/extensions/orchestrate/scripts/sh/emit-event.sh`. Accepts `feature_id phase status note` as positional args, formats one line per `specs/001-backlog-orchestrator-extension/data-model.md` §6, appends to `.specify/extensions/orchestrate/events.log`, and echoes to stdout.
- [ ] T013 [P] Author the installer at `.specify/extensions/orchestrate/install.sh`. MUST: create runtime files with mode `0600`, copy `config-template.yml` → `orchestrate-config.yml` (only if it does not exist), copy `commands/speckit.orchestrate.md` → `.claude/skills/speckit-orchestrate/SKILL.md`, ensure the `.claude/agents/orchestrate-{ba,dev}.md` files exist, idempotent on re-run.
- [ ] T014 [P] [Tests] Author bats unit tests at `tests/extensions/orchestrate/unit/parse-backlog.bats` covering: happy-path mixed checkbox styles, `- [x]` skip, empty file, missing file, duplicate-title detection, empty-title detection, the three-separator priority (` — ` vs ` -- ` vs ` - `).
- [ ] T015 [P] [Tests] Author bats unit tests at `tests/extensions/orchestrate/unit/state-rw.bats` covering: empty-state read, round-trip read→write→read, counter recomputation, atomic-write durability (kill mid-write leaves file unchanged), mode-0600 enforcement.

**Checkpoint**: The foundation is ready. Every user story can now proceed in parallel using these helpers.

---

## Phase 3: User Story 1 — Drive an entire backlog through the spec→implementation pipeline from a single command (Priority: P1) 🎯 MVP

**Goal**: A single `/speckit-orchestrate` invocation reads `BACKLOG.md`, drives every parseable item through BA and Dev subagents in isolated worktrees, and integrates successes into the configured target branch.

**Independent Test**: With a `BACKLOG.md` containing two unambiguous feature items (no clarifications needed), run `/speckit-orchestrate` against a repo with the `dev` target branch present. Verify two feature branches are produced, each with `spec.md / plan.md / tasks.md / analyze` artifacts and an implementation, and both are squash-merged into `dev`.

### Implementation for User Story 1

- [ ] T016 [P] [US1] Author the Lead Skill source at `.specify/extensions/orchestrate/commands/speckit.orchestrate.md` AND its hand-synced mirror at `.claude/skills/speckit-orchestrate/SKILL.md` (treat as a paired write — `install.sh` from T013 keeps them in sync going forward). Frontmatter MUST declare `name: speckit-orchestrate`, `description`, and the tool allowlist. Body MUST be a step-by-step playbook the main Claude Code session executes; **leave the orchestration loop as a placeholder** — T025 fills it in.
- [ ] T017 [P] [US1] Author the BA subagent definition at `.claude/agents/orchestrate-ba.md`. YAML frontmatter declares `name: orchestrate-ba`, `description`, `tools: [Read, Write, Edit, Bash, Skill]`. Body is the BA system prompt: (a) cite the Claude Code Subagents page; (b) instruct the model to run the BA pipeline in order (`/speckit.specify`, `/speckit.clarify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`) inside the assignment's worktree; (c) require the **final message** to be a single JSON object matching `agent-payload.schema.json`, no prose; (d) on success emit `payload_type=result` with `ba_done: true` and the artifact paths; (e) on `/speckit-clarify` / `/speckit-analyze` needing human input, emit `payload_type=clarification_request` with a `correlation_id`.
- [ ] T018 [P] [US1] Author the Dev subagent definition at `.claude/agents/orchestrate-dev.md`. Frontmatter: `name: orchestrate-dev`, `tools: [Read, Write, Edit, Bash, Skill]`. Body: (a) cite the Subagents docs; (b) instruct the model to invoke `/speckit-implement` inside the assignment's worktree; (c) require the final message to be a single `agent-payload.schema.json` JSON, emitting `result` with `dev_done: true` on success or `error` on failure.
- [ ] T019 [P] [US1] Implement `safety-check.sh` at `.specify/extensions/orchestrate/scripts/sh/safety-check.sh`. Takes `safety.on_dirty_tree` mode (`refuse | stash | ignore`). For `refuse`: `git status --porcelain` non-empty ⇒ exit 1 with list. For `stash`: `git stash push -u -m "orchestrate:<runId>"`, record stash ref to stdout. For `ignore`: no-op. Emits a JSON status to stdout.
- [ ] T020 [P] [US1] Implement `reconcile-state.sh` at `.specify/extensions/orchestrate/scripts/sh/reconcile-state.sh`. Reads `BACKLOG.md` (parsed via `parse-backlog.sh`) and current state (via `state-read.sh`), produces an updated state document with: new title-only items appended as `(phase=ba, status=queued)`, existing-title items left untouched, removed items retained as history. Emits the new state to stdout.
- [ ] T021 [US1] Implement `allocate-feature.sh` at `.specify/extensions/orchestrate/scripts/sh/allocate-feature.sh`. Wrapped in `with_state_lock` (from T008). Scans `specs/` for the highest existing `NNN-` prefix, computes the next ID, invokes `.specify/extensions/git/scripts/bash/create-new-feature.sh --json --short-name "<derived>" "<title>"` with the explicit number to avoid race, and emits `{id, branch_name, spec_dir, short_name}` JSON.
- [ ] T022 [P] [US1] Implement `create-worktree.sh` at `.specify/extensions/orchestrate/scripts/sh/create-worktree.sh`. Given a feature ID and branch name, runs `git worktree add "$WORKTREE_ROOT/$id" "$branch"` where `WORKTREE_ROOT=.specify/extensions/orchestrate/worktrees`. Emits the worktree path on success; emits a JSON error with `code=worktree_failed` on failure.
- [ ] T023 [P] [US1] Implement `ba-gate-check.sh` at `.specify/extensions/orchestrate/scripts/sh/ba-gate-check.sh`. Given a feature record and the `ba_gate.strictness` mode, returns exit 0 if the gate passes else exit 1 with a JSON error body matching `errorBody` (`code=ba_gate_failed`). Implements all three modes per FR-010 and research §1.
- [ ] T024 [P] [US1] Implement `integrate-feature.sh` at `.specify/extensions/orchestrate/scripts/sh/integrate-feature.sh`. Given the feature branch, target branch, and `merge.strategy`, performs the strategy-specific git steps from research.md §8. On `rebase`, validates every commit on the feature branch against `^(feat|fix|docs|chore|refactor|test|ci|build|perf|revert|style)(\([^)]+\))?!?: .+`; on validation failure aborts with `code=cc_violation`. On conflict aborts with `code=merge_conflict` and runs `git merge --abort` / `git rebase --abort`. Emits the target-branch commit SHA on success.
- [ ] T025 [US1] Wire the orchestration playbook into the Lead Skill body in both files from T016. Pseudocode the playbook MUST follow: (1) call `safety-check.sh`; (2) call `parse-backlog.sh`; (3) call `reconcile-state.sh`, persist via `state-write.sh`; (4) for each `(phase=ba, status=queued)` feature up to `parallelism.ba`: call `allocate-feature.sh`, `create-worktree.sh`, then `Agent(subagent_type=orchestrate-ba, prompt=<assignment JSON>)`; (5) on BA `result` payload, run `ba-gate-check.sh`; on pass transition to `(dev, queued)`; (6) for each `(phase=dev, queued)` up to `parallelism.dev`: `Agent(subagent_type=orchestrate-dev, prompt=<assignment JSON>)`; (7) on Dev `result`, transition to `(merge, running)`, call `integrate-feature.sh`, on success transition to `(done, complete)` with `target_commit`; (8) after the loop drains, call the summary report; (9) every transition emits a status event via `emit-event.sh` and persists state via `state-write.sh`.
- [ ] T026 [P] [US1] [Tests] Author the integration fixture at `tests/extensions/orchestrate/integration/fixtures/three-clean-items/` containing: `BACKLOG.md` (three unambiguous items), `replay/<feature_id>-<phase>-<n>.json` canned subagent payloads, `expected-state.json`, and add the runner `tests/extensions/orchestrate/integration/mock-subagent.sh` (reads `ORCHESTRATE_SUBAGENT_RUNNER` env var to swap in canned responses) plus `tests/extensions/orchestrate/integration/run-fixture.bats` driving the Lead.

**Checkpoint**: At this point, User Story 1 should be fully functional and testable end-to-end with mocked subagents. A clean backlog with no clarifications fully drains.

---

## Phase 4: User Story 2 — Pause for clarification without losing other parallel work (Priority: P1)

**Goal**: When one BA subagent emits a `clarification_request`, the Lead surfaces it (feature-id-ordered, one at a time, tagged with feature) without cancelling other in-flight features.

**Independent Test**: With a backlog of three items where one is intentionally vague, run `/speckit-orchestrate`. Verify the user is prompted exactly once for the vague item (with its feature ID in the prompt), the other two items reach `phase=done, status=complete` independently, and answering the prompt resumes only the paused feature.

### Implementation for User Story 2

- [ ] T027 [P] [US2] Implement `clarification-queue.sh` at `.specify/extensions/orchestrate/scripts/sh/clarification-queue.sh`. Operates on state directly. Exposes subcommands: `list` (emits feature_id-ordered list of `(phase=ba, status=blocked)` records with their `pending_clarification`), `enqueue FEATURE_ID PAYLOAD_JSON` (sets `status=blocked`, stores the clarification body), `dequeue FEATURE_ID ANSWER_TEXT` (returns the clarification_answer body matching the saved `correlation_id` and resets `status=running`).
- [ ] T028 [US2] Extend the Lead Skill body in both T016 files to: (a) after each subagent result, check for `payload_type=clarification_request` and route through `clarification-queue.sh enqueue`; (b) before scheduling the next round of BA work, present pending clarifications to the user via `AskUserQuestion`, feature-id-ordered, one at a time; (c) on user answer, call `clarification-queue.sh dequeue`, build a `clarification_answer` body, re-spawn the BA subagent with `assignment.retry_with` populated.
- [ ] T029 [US2] Extend the BA subagent body in `.claude/agents/orchestrate-ba.md` (file from T017) with the exact `clarification_request` payload shape: MUST set `correlation_id` to a UUID, MUST populate `body.question`, `body.context` (≤500 chars), and optional `body.options[]`. Add explicit examples for `/speckit-clarify` and `/speckit-analyze` clarification surfaces.
- [ ] T030 [P] [US2] [Tests] Author integration fixture at `tests/extensions/orchestrate/integration/fixtures/one-blocked-clarification/` with three items, canned BA payloads where item 002 returns a `clarification_request`, then a `result` after a canned `clarification_answer` is delivered. Verify items 001 and 003 complete independently while 002 is blocked.
- [ ] T031 [P] [US2] [Tests] Author bats unit test at `tests/extensions/orchestrate/unit/clarification-queue.bats` covering: empty queue, multiple blocked features ordered by id, enqueue→dequeue round trip with correlation_id preserved, attempting to dequeue with mismatched correlation_id (error).

**Checkpoint**: User Stories 1 AND 2 both work — the MVP is complete.

---

## Phase 5: User Story 3 — Resume a partially completed backlog run after interruption (Priority: P2)

**Goal**: A second invocation of `/speckit-orchestrate` (with no flags, or with `--retry-failed`) picks up where the previous run left off, skipping terminal features, respawning interrupted ones, and re-presenting saved clarifications.

**Independent Test**: Start a backlog run, kill the Lead session after at least one feature has reached `(dev, running)` and at least one is still in `(ba, running)`. Re-run `/speckit-orchestrate` with the same backlog. Verify terminal features are skipped, in-progress features pick up where they left off, and the run concludes identically to an uninterrupted run.

### Implementation for User Story 3

- [ ] T032 [P] [US3] Implement `retry-failed.sh` at `.specify/extensions/orchestrate/scripts/sh/retry-failed.sh`. Reads state via `state-read.sh`, sets every feature with `status=failed` to `(phase=ba, status=queued, last_payload=null)`, persists via `state-write.sh`. Emits the count of reset records.
- [ ] T033 [P] [US3] Implement `worktree-validate.sh` at `.specify/extensions/orchestrate/scripts/sh/worktree-validate.sh`. Given a feature record, verifies `worktree_path` exists as a registered git worktree (`git worktree list --porcelain`). On miss, emits an `errorBody` with `code=worktree_missing` and `recoverable=true` (the user can re-create via a future `--rebuild-worktrees` flag).
- [ ] T034 [US3] Extend the Lead Skill body in both T016 files (after T028) with: (a) `--retry-failed` flag parsing — if set, invoke `retry-failed.sh` before the main loop; (b) the resume preamble — for each non-terminal feature, run `worktree-validate.sh`; on miss, mark the feature `(phase=ba, status=failed)` with the worktree-missing payload; on hit, requeue at the recorded `phase` with `status=running` reset to `queued` (per FR-026); (c) on `(ba, status=blocked)`, restore the saved `pending_clarification` to the UI prompt cycle.
- [ ] T035 [P] [US3] [Tests] Author integration fixture at `tests/extensions/orchestrate/integration/fixtures/resume-after-kill/` simulating: run a fixture to completion of one feature, simulate kill (truncate replay early), re-run, assert state matches a full uninterrupted run.
- [ ] T036 [P] [US3] [Tests] Author integration fixture at `tests/extensions/orchestrate/integration/fixtures/dev-failure-then-retry/` simulating: run with one canned Dev `error` payload; first run leaves that feature `(dev, failed)`; second run without `--retry-failed` leaves it failed; third run with `--retry-failed` resets and completes successfully.

**Checkpoint**: User Story 3 works on top of US1+US2. The orchestrator is robust to interruption.

---

## Phase 6: User Story 4 — Configure parallelism and merge target without editing code (Priority: P2)

**Goal**: Users override any documented config key by editing `orchestrate-config.yml`; the next run reflects the change. All keys have validated defaults.

**Independent Test**: Edit `orchestrate-config.yml` to set `parallelism.ba: 1`, `parallelism.dev: 1`, `merge.target_branch: integration`. Run `/speckit-orchestrate` on a 3-item backlog. Verify: only one BA and one Dev subagent are active at any time; merges target `integration` (and fail with a clear error if that branch does not exist).

### Implementation for User Story 4

- [ ] T037 [P] [US4] Implement `config-load.sh` at `.specify/extensions/orchestrate/scripts/sh/config-load.sh`. POSIX `awk`-based YAML parser (limited to the documented two-level key tree from `orchestrate-config.schema.json`). MUST: merge user file over `config-template.yml` defaults; emit the resolved config as JSON to stdout; validate the JSON against `schemas/orchestrate-config.schema.json` (via `jq`-based shape check); abort with the offending key path on type-invalid values; warn but proceed on unknown keys.
- [ ] T038 [US4] Extend the Lead Skill body in both T016 files (after T034) to call `config-load.sh` first thing in the playbook, set `OrchestratorState.config_snapshot` from the resolved JSON, and route all subsequent decisions through that snapshot (do not re-read the YAML mid-run).
- [ ] T039 [P] [US4] [Tests] Author bats unit test at `tests/extensions/orchestrate/unit/config-load.bats` covering: empty user config (pure defaults), partial overrides (e.g., only `parallelism.ba: 4`), type-invalid value (`parallelism.ba: "two"`), out-of-range value (`parallelism.ba: 99`), unknown-key soft warn, missing target_branch override pre-flight.

**Checkpoint**: Configuration knobs work. Defaults are sane.

---

## Phase 7: User Story 5 — Get a clear post-run report of what shipped and what didn't (Priority: P3)

**Goal**: At end of run (clean exit or interruption), the Lead prints a per-feature summary table with terminal `(phase, status)`, feature branch name, worktree path, spec file path, and — for blocked features — the open clarification question verbatim.

**Independent Test**: Run a backlog containing one clean item, one item with an unanswered clarification, and one item designed to fail in Dev. Verify the final report enumerates all three with correct status and the blocked item's question text quoted.

### Implementation for User Story 5

- [ ] T040 [P] [US5] Implement `summary-report.sh` at `.specify/extensions/orchestrate/scripts/sh/summary-report.sh`. Reads state, emits a Markdown-friendly table to stdout: columns `ID | Title | Phase | Status | Branch | Worktree | Spec | Target Commit | Open Question`. Truncate long fields with ellipsis. Cross-check totals against `state.counters`; warn on mismatch.
- [ ] T041 [US5] Extend the Lead Skill body in both T016 files (after T038) to invoke `summary-report.sh` (a) on clean drain of the state, AND (b) on Ctrl-C / interrupted exit via a trap-like signal handler in the playbook's "Stop & Summarise" step.
- [ ] T042 [P] [US5] [Tests] Author bats unit test at `tests/extensions/orchestrate/unit/summary-report.bats` covering: empty state, all-complete, mixed (some blocked / failed / complete), and counter-mismatch warning.

**Checkpoint**: All five user stories are independently functional.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, CI hooks, and the cross-cutting smoke test.

- [ ] T043 [P] Update the repository root `README.md` to mention the new extension, link to `specs/001-backlog-orchestrator-extension/quickstart.md`, and document the install command from `T013`.
- [ ] T044 [P] [Tests] Author the CI validator at `tests/extensions/orchestrate/schemas/validate-fixtures.sh`. Iterates every JSON file under `tests/extensions/orchestrate/integration/fixtures/**/replay/` and `tests/extensions/orchestrate/integration/fixtures/**/expected-state.json`, validates each against the matching schema in `.specify/extensions/orchestrate/schemas/`. Used by the `bats` integration suite and by any future CI workflow.
- [ ] T045 [P] Execute the quickstart smoke test described in `specs/001-backlog-orchestrator-extension/quickstart.md` end-to-end against this very repo: run `install.sh`, write a two-item `BACKLOG.md`, run `/speckit-orchestrate` with the `ORCHESTRATE_SUBAGENT_RUNNER` env var pointed at `mock-subagent.sh` and a one-shot fixture, verify `state.json` and `events.log` reflect both items completed, and capture observed wall-clock to confirm SC-001.
- [ ] T046 Final pass: run the full bats suite (`bats tests/extensions/orchestrate/unit/ tests/extensions/orchestrate/integration/`) and `validate-fixtures.sh`; fix any failures before declaring the feature done.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)**: no dependencies — start immediately.
- **Phase 2 (Foundational)**: depends on Phase 1. **Blocks every user story**.
- **Phase 3 (US1)**: depends on Phase 2. MVP gate.
- **Phase 4 (US2)**: depends on Phase 3 (extends T016's Lead skill and T017's BA subagent files).
- **Phase 5 (US3)**: depends on Phases 3 + 4 (extends the same Lead skill files).
- **Phase 6 (US4)**: depends on Phases 3-5 (extends the same Lead skill body; comes after US3 to keep config-snapshot semantics consistent across resume).
- **Phase 7 (US5)**: depends on Phases 3-6.
- **Phase 8 (Polish)**: depends on all user stories.

### User story dependencies

- **US1 (P1)** is the MVP foundation; **all** other stories extend its Lead skill file.
- **US2 (P1)** is mandatory for the MVP-of-the-MVP — the second P1 — and runs *after* US1 because it modifies the BA subagent file US1 creates.
- **US3 (P2)** depends on US1+US2 (resume includes re-presenting saved clarifications).
- **US4 (P2)** is logically independent but ordered after US3 to keep the Lead skill body edits sequential and conflict-free.
- **US5 (P3)** depends on all earlier stories so the report covers every state.

### Within each user story

- Helper scripts that touch **different** files: `[P]` (run in parallel).
- Anything that modifies the **Lead Skill body** (T016's two files): sequential — only one task at a time.
- Tests are concurrent deliverables, not red-bar gates; mark `[P]` whenever in their own file.

### Parallel opportunities

- **Phase 1**: T002, T003, T004, T006 in parallel after T001.
- **Phase 2**: T007–T015 are nearly all `[P]` after T008 lands. T008 is the one sequential pin.
- **Phase 3 (US1)**: T016, T017, T018, T019, T020, T022, T023, T024, T026 are all `[P]`. T021 and T025 are the sequential pins (T021 needs T008's `with_state_lock`; T025 modifies the Lead skill).
- **Phase 4 (US2)**: T027, T030, T031 in parallel; T028 and T029 sequential.
- **Phase 5 (US3)**: T032, T033, T035, T036 in parallel; T034 sequential.
- **Phase 6 (US4)**: T037 and T039 in parallel; T038 sequential.
- **Phase 7 (US5)**: T040 and T042 in parallel; T041 sequential.
- **Phase 8**: T043, T044, T045 in parallel; T046 sequential (it depends on all previous tests existing).

---

## Parallel Example: User Story 1

```bash
# After Phase 2 completes, the following nine tasks can run in parallel:
Task: "Author Lead Skill source + mirror in commands/speckit.orchestrate.md and .claude/skills/speckit-orchestrate/SKILL.md"  # T016
Task: "Author BA subagent in .claude/agents/orchestrate-ba.md"                          # T017
Task: "Author Dev subagent in .claude/agents/orchestrate-dev.md"                        # T018
Task: "Implement safety-check.sh"                                                       # T019
Task: "Implement reconcile-state.sh"                                                    # T020
Task: "Implement create-worktree.sh"                                                    # T022
Task: "Implement ba-gate-check.sh"                                                      # T023
Task: "Implement integrate-feature.sh"                                                  # T024
Task: "Author integration fixture three-clean-items + mock-subagent.sh"                 # T026

# Then sequentially:
Task: "Implement allocate-feature.sh (depends on T008)"                                 # T021
Task: "Wire the Lead Skill playbook (modifies T016 files)"                              # T025
```

---

## Implementation Strategy

### MVP scope

The MVP is **User Story 1 + User Story 2** together. US1 alone is meaningless in practice — any real backlog will contain ambiguous items, and parallel execution that halts on the first ambiguity defeats the value proposition. Treat US1+US2 as a single shippable increment.

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational.
3. Complete Phase 3: US1.
4. Complete Phase 4: US2.
5. **STOP and VALIDATE**: run the two integration fixtures (`three-clean-items`, `one-blocked-clarification`). If both green, the MVP is real.
6. Optional ship-now point — US3/4/5 can ship as 1.1, 1.2, 1.3.

### Incremental delivery after MVP

- Add **US3** → unattended resilience.
- Add **US4** → adoption beyond a single environment.
- Add **US5** → executive/PR-readable post-run report.

### Parallel team strategy

With multiple developers:

1. One developer drives Phase 2 (T007–T015) to unblock everyone.
2. Once Phase 2 lands, three developers can split US1 between them:
   - Developer A: scripts (T019, T020, T021, T022, T023, T024).
   - Developer B: agent / skill markdown (T016, T017, T018, T025).
   - Developer C: tests (T026).
3. US2 follows on the same Lead skill file — one developer at a time on T028/T029/T034/T038/T041.

---

## Notes

- `[P]` = different files, no dependencies on incomplete in-phase tasks.
- `[Story]` labels (US1–US5) trace each task to its spec story for review.
- The Lead Skill file (T016's source + mirror pair) is the **single most edited file** in this feature — every story extends it. Plan accordingly; do not parallelise T025/T028/T034/T038/T041 with each other.
- Per the constitution Principle V, every commit on this branch MUST be Conventional-Commits compliant.
- Each test fixture under `tests/extensions/orchestrate/integration/fixtures/` is canon — payload JSON in the fixture is validated against the schemas by `T044` in CI.
- Avoid: cross-story dependencies that break independence — every user story must be runnable end-to-end without code from later stories.
