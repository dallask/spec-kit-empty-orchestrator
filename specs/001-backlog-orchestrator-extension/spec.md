# Feature Specification: Backlog Orchestrator Extension

**Feature Branch**: `001-backlog-orchestrator-extension`
**Created**: 2026-05-12
**Status**: Draft
**Input**: User description: "Create a new specify extension. It reads BACKLOG.md file, goes through the full flow (/speckit.specify -> /speckit.clarify -> /speckit.plan -> /speckit.tasks -> /speckit.analyze -> /speckit.implement). Extension should treat every item in the BACKLOG.md as a separate feature and work with it in the separate worktree. Extension should implement hub-and-spoke agent architecture with the Lead agent as an orchestrator, BA subagent as a speck creator (/speckit.specify -> /speckit.clarify -> /speckit.plan -> /speckit.tasks -> /speckit.analyze) and Dev subagent as developer (/speckit.implement). All coordination between agents should go through orchestrator. Agents should pass the data in the structured JSON format (not prose). Only Orchestrator can spawn subagents. Use the https://github.com/GenieRobot/spec-kit-maqa-ext as an example. Extension should have configuration in yaml format, and state storage in json format (just like maqa extension does). Flow should look like this: User start Lead agent -> Lead reads BACKLOG.md -> Lead spins as many worktrees as many parallel agents it can spawn according settings -> Lead spawns BA subagents -> each BA subagent works with its own feature in its own worktree and runs full flow (/speckit.specify -> /speckit.clarify -> /speckit.plan -> /speckit.tasks -> /speckit.analyze) only stops when it needs clarification from user during clarify and analyze phase -> BA subagent return results to Lead as soon as full feature flow done or errors -> Lead check that feature speck is completed -> Lead spawn Dev subagents for each feature separately (amount of subagents according settings) -> Each dev proceed with feature development according speck -> Dev returns result to LEad -> lead merges feature to dev branch. Use README.md file as a guidline."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Drive an entire backlog through the spec→implementation pipeline from a single command (Priority: P1)

A product owner or tech lead has a `BACKLOG.md` file containing multiple feature ideas. They start a Lead session, point it at the backlog, and the extension drives every item all the way from "raw idea" to "merged feature branch" by orchestrating BA and Dev subagents in isolated worktrees. The user only has to intervene when a BA agent genuinely needs human clarification.

**Why this priority**: This is the core value proposition of the extension. Without it, the extension does not exist; it is the smallest slice that justifies building anything.

**Independent Test**: With a `BACKLOG.md` containing two unambiguous feature items and `auto_clarify_default: true` configured, run the Lead end-to-end. Verify that two feature branches are produced, each contains a complete spec/plan/tasks set plus an implementation, and both are merged into the configured dev branch without the user being prompted.

**Acceptance Scenarios**:

1. **Given** a `BACKLOG.md` with N parseable feature items and a configured parallelism cap of P, **When** the user starts the Lead, **Then** the Lead creates at most P worktrees concurrently, processes all N items through the full BA→Dev pipeline, and reports a final summary listing each item's terminal status (merged, blocked, failed).
2. **Given** a feature whose BA pipeline completes without errors, **When** BA reports success, **Then** the Lead spawns a Dev subagent against that feature's worktree and spec; on Dev success, the Lead merges that feature branch into the configured dev branch.
3. **Given** an empty or missing `BACKLOG.md`, **When** the user starts the Lead, **Then** the Lead exits cleanly with a message explaining that no actionable items were found and makes no git changes.

---

### User Story 2 - Pause for clarification without losing other parallel work (Priority: P1)

While the Lead is driving several backlog items in parallel, one BA subagent reaches `/speckit.clarify` or `/speckit.analyze` and needs a human answer. The user expects to be asked the question, give an answer, and have that single feature resume — without the other in-flight features being cancelled or losing progress.

**Why this priority**: Parallel execution is meaningless if a single ambiguous backlog item halts the whole run. This behavior is what makes the orchestrator usable on real backlogs, which always contain some under-specified items.

**Independent Test**: With a backlog of three items where one is intentionally vague (e.g., "add notifications"), run the Lead. Verify the user is presented with that one item's clarification question via the Lead, that the other two items continue progressing while the question is open, and that answering the question resumes only the paused feature.

**Acceptance Scenarios**:

1. **Given** a BA subagent reaches a clarification point, **When** it surfaces a question, **Then** the question is delivered to the user through the Lead session (never directly from the subagent), tagged with the feature it belongs to, while other BA subagents continue working.
2. **Given** the user provides an answer to a clarification question, **When** the Lead receives it, **Then** the Lead returns the answer to the originating BA subagent and that subagent resumes from where it paused; no other subagent is disturbed.
3. **Given** more than one BA subagent has questions pending at the same time, **When** the user is prompted, **Then** the Lead surfaces them one at a time in a deterministic order (feature-id ascending), each clearly labelled with its feature.

---

### User Story 3 - Resume a partially completed backlog run after interruption (Priority: P2)

A backlog run was interrupted (process killed, machine slept, transient error). The user restarts the Lead; the extension reads its JSON state and continues from where it left off rather than redoing completed work.

**Why this priority**: Long backlog runs are realistic. Without resumability, any interruption forces a costly restart that re-runs Spec Kit phases already paid for. It is not P1 because a happy-path single run already delivers value.

**Independent Test**: Start a backlog run, kill the Lead session after at least one feature has reached the Dev phase and at least one is still in BA. Restart the Lead with the same backlog; verify that already-merged features are skipped, in-progress features pick up where they left off, and the final outcome matches an uninterrupted run.

**Acceptance Scenarios**:

1. **Given** a state file recording feature X as `merged`, **When** the Lead restarts, **Then** feature X is not re-processed and is reported as already complete.
2. **Given** a state file recording feature Y as `ba_in_progress` with its worktree intact, **When** the Lead restarts, **Then** the Lead respawns a BA subagent against that worktree and the JSON state advances normally on success.
3. **Given** a state file references a worktree that no longer exists on disk, **When** the Lead restarts, **Then** the Lead reports the corruption for that feature, leaves the rest of the run untouched, and exits non-zero only after attempting the remaining features.

---

### User Story 4 - Configure parallelism and merge target without editing code (Priority: P2)

Different teams need different concurrency profiles (a laptop might run 2 BA + 1 Dev; a CI runner might run 8 + 8). Different repos use different long-lived integration branches (`dev`, `develop`, `integration`). The user expects to change these via a YAML config, not by patching the extension.

**Why this priority**: Required for adoption beyond a single environment. Not P1 because a sensible hardcoded default lets the P1 stories pass.

**Independent Test**: Set `parallelism.ba: 1`, `parallelism.dev: 1`, `merge.target_branch: dev` in the YAML config; run a 3-item backlog. Verify exactly one BA and one Dev run at any time and that all merges target `dev`.

**Acceptance Scenarios**:

1. **Given** a YAML config with a parallelism cap of 1, **When** the Lead runs, **Then** at most one BA subagent and one Dev subagent are active concurrently regardless of backlog size.
2. **Given** a YAML config naming a merge target branch that does not exist, **When** the Lead reaches the merge step for any feature, **Then** the Lead fails that feature's merge with a clear error and leaves the feature branch intact for manual recovery.
3. **Given** no YAML config is present, **When** the Lead runs, **Then** documented defaults are applied and the run proceeds.

---

### User Story 5 - Get a clear post-run report of what shipped and what didn't (Priority: P3)

After the orchestrator finishes, the user wants a single human-readable summary: which backlog items were merged, which are blocked on clarification (and the open question), which failed and why, and where their artifacts live.

**Why this priority**: Nice-to-have for human review and stakeholder reporting; not on the critical path because the JSON state file already contains everything.

**Independent Test**: Run the Lead on a backlog containing a mix of clean items, an item with an unanswered clarification, and an item designed to fail in Dev. Verify the final report enumerates all three with the correct status and points to the spec file and feature branch for each.

**Acceptance Scenarios**:

1. **Given** a finished or aborted run, **When** the Lead exits, **Then** it prints a per-feature summary table with terminal status, feature branch name, worktree path, and spec file path.
2. **Given** a feature is blocked on clarification when the user stops the run, **When** the report is emitted, **Then** that feature's open question is included verbatim in the report.

---

### Edge Cases

- **Empty or malformed `BACKLOG.md`**: Lead exits cleanly without creating worktrees and reports zero processable items.
- **Duplicate or near-duplicate backlog items**: Each parsed item is treated as a distinct feature (deduplication is the user's responsibility); branch/worktree names disambiguate via the sequential feature prefix produced by the existing `speckit.git.feature` hook.
- **A BA subagent errors mid-pipeline (e.g., during `/speckit.plan`)**: Lead marks that feature as `ba_failed` with the captured error payload, does not spawn a Dev for it, and continues with other features.
- **A Dev subagent errors during `/speckit.implement`**: Lead marks the feature `dev_failed`, leaves the feature branch and worktree intact for human inspection, and does not merge.
- **Merge conflict against the dev branch**: Lead aborts that one merge, marks the feature `merge_conflict`, leaves the feature branch intact, and continues with remaining features.
- **More backlog items than the parallelism cap**: Lead queues the surplus and dispatches the next item as soon as a slot frees.
- **Subagent attempts to spawn another subagent**: Forbidden by Claude Code's documented agent model; the extension contract reflects this and the Lead is the only delegator.
- **Worktree creation fails (disk full, branch name collision)**: That single feature is marked `worktree_failed`; other features proceed.
- **User stops the Lead while subagents are running**: The Lead persists current state to the JSON state file before exit so a later run can resume.
- **Backlog item references shared files that two parallel features both modify**: Both Devs succeed in their own worktrees, but at merge time the second feature hits the merge-conflict path above.

## Requirements *(mandatory)*

### Functional Requirements

#### Backlog ingestion

- **FR-001**: Extension MUST read a `BACKLOG.md` file from the project root and parse it into an ordered list of feature items.
- **FR-002**: Extension MUST treat each parsed item as an independent feature with its own identity (id, title, raw description).
- **FR-003**: Extension MUST report an empty-or-missing `BACKLOG.md` as a clean, non-error end state.

#### Worktree isolation

- **FR-004**: Extension MUST execute each feature inside its own git worktree, separate from the user's main working tree.
- **FR-005**: Extension MUST limit the number of concurrently active worktrees to the configured parallelism cap.
- **FR-006**: Extension MUST clean up or clearly preserve worktrees on failure according to a documented, configurable policy (default: preserve on failure for inspection, prune on successful merge).

#### Hub-and-spoke orchestration

- **FR-007**: Only the Lead (the main Claude Code session) MUST delegate work to subagents; no subagent may spawn or delegate to another subagent. This aligns with Claude Code's documented subagent model.
- **FR-008**: All cross-agent communication MUST flow through the Lead; BA and Dev subagents MUST NOT communicate with each other directly.
- **FR-009**: Lead MUST spawn a BA subagent per feature to run the full BA pipeline (`/speckit.specify`, `/speckit.clarify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`) inside that feature's worktree.
- **FR-010**: Lead MUST spawn a Dev subagent per feature, only after the BA pipeline for that feature has completed successfully, to run `/speckit.implement` inside that feature's worktree.

#### Pause-for-clarification behavior

- **FR-011**: BA subagents MUST pause and surface a clarification request to the Lead whenever `/speckit.clarify` or `/speckit.analyze` requires human input.
- **FR-012**: Lead MUST relay pending clarification questions to the user, labelled with the originating feature, without cancelling or pausing unrelated subagents.
- **FR-013**: Lead MUST deliver the user's answer back to the originating BA subagent so it can resume from the paused phase.
- **FR-014**: When multiple subagents have pending clarifications simultaneously, Lead MUST present them to the user in a deterministic, feature-id-ordered sequence, one at a time.

#### Structured agent contract

- **FR-015**: All messages exchanged between the Lead and subagents (task assignments, status updates, results, errors, clarification requests/answers) MUST be structured JSON payloads, not free-form prose.
- **FR-016**: Each JSON payload MUST carry at minimum: a feature id, the phase it relates to, a payload type (e.g., `assignment`, `progress`, `result`, `clarification_request`, `clarification_answer`, `error`), and a typed body.
- **FR-017**: Subagents MUST treat any non-JSON or schema-invalid instruction from the Lead as an error and surface it to the Lead.

#### Merge and integration

- **FR-018**: On Dev success, Lead MUST merge the feature branch into the configured dev branch.
- **FR-019**: On merge conflict, Lead MUST abort that single merge, mark the feature with a conflict status, and continue processing other features.
- **FR-020**: Merge commit messages MUST follow Conventional Commits so semantic-release can classify them.

#### Configuration

- **FR-021**: Extension MUST read its configuration from a YAML file located within the extension's directory.
- **FR-022**: Configuration MUST expose at minimum: backlog file path, BA parallelism cap, Dev parallelism cap, target dev branch name, and worktree cleanup policy.
- **FR-023**: Extension MUST apply documented defaults for every config key so it runs with no user-supplied config.

#### State persistence

- **FR-024**: Extension MUST persist run state to a JSON file (per-feature status, current phase, worktree path, branch name, spec file path, pending clarification if any).
- **FR-025**: Extension MUST update the state file at every phase transition so a crashed or killed run can be resumed.
- **FR-026**: On restart, Lead MUST read the state file, skip features already in a terminal status (`merged`, `dev_failed`, `merge_conflict`, etc. per policy), and resume in-progress features from the last recorded phase.

#### Observability and reporting

- **FR-027**: Lead MUST produce a final per-feature summary at end-of-run (interactive or post-mortem), listing each feature's terminal status and key artifact paths.
- **FR-028**: Lead MUST surface subagent errors to the user with enough context (feature id, phase, captured error body) to act on them, without exposing internal prompt text.

#### Claude Code alignment

- **FR-029**: Subagent definitions, tool grants, permission modes, and delegation patterns MUST conform to Claude Code's documented subagents architecture. When Spec Kit conventions and Claude Code documentation disagree, the extension MUST follow Claude Code.

### Key Entities *(include if feature involves data)*

- **BacklogItem**: One parsed entry from `BACKLOG.md`. Has an id (sequential), a short title, a raw description, and a source-range pointer back into the backlog file.
- **Feature**: The orchestrator's working unit corresponding to one BacklogItem. Has an id, a worktree path, a feature branch name, a spec directory path, a current phase, a current status, and accumulated payloads (latest BA result, latest Dev result, open clarification if any).
- **AgentPayload**: A typed JSON envelope exchanged between Lead and a subagent. Carries: feature id, agent role (`ba` | `dev`), phase, payload type, body, timestamp.
- **OrchestratorState**: The full JSON state document persisted to disk. Holds the run-level config snapshot, the list of Feature records, and global counters (start time, active worktrees, completed count).
- **ClarificationRequest / ClarificationAnswer**: Two payload subtypes that travel between BA→Lead and Lead→BA respectively. Each is tied to a specific feature id and phase (`clarify` or `analyze`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An unattended run on a 5-item, fully-specified backlog produces 5 merged feature branches on the configured dev branch with zero user prompts, in less wall-clock time than running the same items sequentially through the Spec Kit flow by hand.
- **SC-002**: On a backlog where exactly one item needs a clarification, the user is prompted exactly once for that one item and the other items reach `merged` status without being blocked by the pending question.
- **SC-003**: When a Lead session is killed mid-run and restarted, no feature that had already reached `merged` status is re-processed, and the run continues to completion of the remaining items.
- **SC-004**: 100% of Lead↔subagent messages observed in a run conform to the documented JSON schema; any non-conforming message is reported as an error rather than silently consumed.
- **SC-005**: The user can change parallelism caps and the merge target branch by editing the YAML config alone — no code edits and no command-line flags — and the next run reflects the change.
- **SC-006**: At end-of-run, the printed summary correctly classifies 100% of backlog items into one of the documented terminal statuses, and the JSON state file matches the printed summary.
- **SC-007**: A failed Dev or merge step affects only that one feature; in a 5-item backlog where one item is forced to fail, the other four still reach `merged`.

## Assumptions

- **Backlog format**: Each top-level item in `BACKLOG.md` corresponds to one feature. The default parser recognises top-level Markdown headings (`#` / `##`) and top-level checkbox list items (`- [ ] ...`) as item delimiters; the body until the next delimiter is the feature description. Users with a different convention can override the parser via configuration in a later iteration.
- **Sequential feature numbering**: The existing `speckit.git.feature` hook handles branch creation and numeric prefixes; the orchestrator reuses it rather than inventing parallel numbering.
- **Claude Code agents model is authoritative**: Subagents cannot spawn other subagents and only the main session delegates. The extension's contract is built on top of this — it does not try to work around it.
- **Worktree backend**: Standard `git worktree` is the isolation primitive; the project is assumed to be a git repository with a clean enough state to support multiple concurrent worktrees.
- **Single user, single Lead**: Exactly one Lead session is active per backlog at a time. Concurrent Leads on the same `BACKLOG.md` are out of scope for v1.
- **Merge strategy**: Merges to the dev branch use a non-fast-forward merge with a Conventional-Commits-compliant merge message so semantic-release picks up the change. Squash and rebase strategies are not the v1 default.
- **No remote push**: The orchestrator operates locally — it does not push to a remote, open PRs, or interact with GitHub on its own. Remote integration is out of scope for v1.
- **`/speckit.implement` is the implementation entry point**: The Dev subagent is responsible for invoking it and reacting to its output; the orchestrator does not duplicate `/speckit.implement`'s logic.
- **State and config locations follow the maqa-extension pattern**: YAML config lives inside the extension's own directory under `.specify/extensions/`; the JSON state file lives next to it.
- **Reference implementation**: The shape, layout, and patterns from `GenieRobot/spec-kit-maqa-ext` are a guideline, not a contract. Where the maqa pattern conflicts with Claude Code agent docs, Claude Code wins.

## Dependencies

- The extension depends on Claude Code's subagent feature being available in the user's environment.
- The extension depends on the existing core Spec Kit slash commands (`/speckit.specify`, `/speckit.clarify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.analyze`, `/speckit.implement`) being installed and functional in the host project.
- The extension depends on the existing `speckit.git.feature` and `speckit.git.commit` hooks for branch creation and commits.
- The extension requires `git` with `worktree` support available on the user's `PATH`.
