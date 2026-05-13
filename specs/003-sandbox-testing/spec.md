# Feature Specification: Sandbox Testing for Orchestrator Extension

**Feature Branch**: `003-sandbox-testing`
**Created**: 2026-05-13
**Status**: Draft
**Input**: User description: "Sandbox testing feature that allows create fully functional test environment in a separate sandbox folder to go through all agentic flow that extension implements to debug existing functionality. Feature should include command to prepare and clean up sandbox."

## Clarifications

### Session 2026-05-13

- Q: Where exactly does the sandbox directory live on disk? → A: `.sandbox/` inside the host repository root, added to the host's `.gitignore` by prepare. Cleanup operates exclusively on this fixed relative path.
- Q: What scenarios must the sample `BACKLOG.md` cover? → A: Three items — one happy-path (completes without prompts), one clarification-needed (intentionally vague to trigger `/speckit-clarify` or `/speckit-analyze`), and one already-complete `- [x]` item to exercise the orchestrator's skip behavior. Failure-injection (Dev or merge) is out of scope for v1 because it is brittle to engineer deterministically.
- Q: How should the prepare and cleanup commands be exposed? → A: Two distinct slash skills, `/speckit-sandbox-prepare` and `/speckit-sandbox-cleanup`. Matches the existing one-verb-per-skill convention used by `/speckit-orchestrate`, `/speckit-git-feature`, etc.; each skill appears separately in the skill list and has its own SKILL.md.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prepare a self-contained sandbox in one command (Priority: P1)

A maintainer working on the Backlog Orchestrator Extension wants a disposable, fully-wired test environment so they can exercise the entire `/speckit-orchestrate` pipeline (Lead → BA → Dev → merge) without touching their main repository or other real projects. They run a single prepare command and immediately have a sandbox that is ready to accept `/speckit-orchestrate`.

**Why this priority**: This is the core value proposition. Without a one-shot prepare command, every debug session starts with a 10-minute manual setup ritual — initializing git, installing the extension, writing a backlog, creating the dev branch, etc. — which discourages testing and leaves bugs unreproduced. This is the smallest slice that delivers value.

**Independent Test**: From a clean checkout of the orchestrator project, run `/speckit-sandbox-prepare` and verify that the resulting `.sandbox/` directory contains a working git repository with the orchestrator extension installed, a sample `BACKLOG.md`, a `dev` branch, and that running `/speckit-orchestrate` inside the sandbox starts the Lead without setup errors.

**Acceptance Scenarios**:

1. **Given** no sandbox exists yet, **When** the maintainer runs the prepare command, **Then** a sandbox directory is created at a documented, well-known location, contains a fully initialised git repository on its default branch with the configured dev branch present, has the orchestrator extension installed exactly as a real user installation would produce, includes a sample `BACKLOG.md` that exercises the full pipeline, and finishes with a printed pointer to the sandbox path.
2. **Given** the sandbox has just been prepared, **When** the maintainer changes into the sandbox directory and runs `/speckit-orchestrate`, **Then** the Lead starts, parses the sample backlog, and begins driving features through the pipeline using the same code paths as a real user invocation — no test stubs, no mocks.
3. **Given** the prepare command is invoked in an environment that lacks a required dependency (e.g., `git`, `jq`, or the orchestrator extension's source files), **When** prepare runs, **Then** it stops before partial setup, names the missing dependency, leaves no half-built sandbox behind, and exits non-zero.

---

### User Story 2 - Tear down the sandbox completely in one command (Priority: P1)

After a debug session the maintainer wants to wipe every trace of the sandbox — directory, worktrees, branches, state files, log files — so the next prepare starts from a known-clean baseline and so nothing about the sandbox leaks into the host repository's git tree.

**Why this priority**: Without a deterministic cleanup, sandbox debris (stale worktrees, orphan branches, leftover state JSON) accumulates across runs and corrupts later debug sessions — the very problem the sandbox is supposed to avoid. Cleanup is the other half of the prepare/use/cleanup lifecycle.

**Independent Test**: After a sandbox run that has produced worktrees, branches, and a populated `state.json`, run `/speckit-sandbox-cleanup` and verify the `.sandbox/` directory no longer exists, the host repository's working tree is unchanged (`git status` on the host is identical to before `/speckit-sandbox-prepare` ran), and re-running `/speckit-sandbox-cleanup` is a clean no-op.

**Acceptance Scenarios**:

1. **Given** a sandbox exists with any combination of worktrees, feature branches, state files, and log files, **When** the maintainer runs the cleanup command, **Then** the entire sandbox directory is removed and the host repository's tracked tree and git index are unchanged.
2. **Given** no sandbox currently exists, **When** the maintainer runs the cleanup command, **Then** it exits successfully without errors and prints a message confirming there was nothing to clean.
3. **Given** the cleanup command receives a target path that is not the documented sandbox path (e.g., via misconfiguration or environment override), **When** cleanup is asked to remove it, **Then** cleanup refuses, prints the unexpected path, and exits non-zero so no path outside the sandbox can ever be deleted.

---

### User Story 3 - Sample backlog covers the orchestrator's key behaviors out of the box (Priority: P2)

The maintainer wants the sandbox's sample `BACKLOG.md` to exercise the pipeline's interesting paths — at minimum a happy-path item that completes without intervention and an item that intentionally pauses for clarification — so a single prepare-and-run cycle observes the orchestrator's most important behaviors without the maintainer writing test data.

**Why this priority**: Without a curated sample, every maintainer hand-rolls their own backlog, which causes uneven coverage across debug sessions and makes "did anyone test the clarification path recently?" unanswerable. P2 because the P1 prepare/cleanup slice is usable even with a single trivial item — the curated backlog is an ergonomic uplift.

**Independent Test**: Prepare a sandbox, run `/speckit-orchestrate` inside it, and verify that during one run the maintainer observes (a) at least one feature transitioning all the way to `phase=done, status=complete` without prompts and (b) at least one feature pausing in `status=blocked` with a clarification question presented through the Lead.

**Acceptance Scenarios**:

1. **Given** a freshly prepared sandbox, **When** the sample `BACKLOG.md` is parsed, **Then** it contains exactly three top-level items: one happy-path `- [ ]`, one deliberately-vague `- [ ]` designed to trigger a clarification during `/speckit-clarify` or `/speckit-analyze`, and one `- [x]` already-complete item.
2. **Given** the sample backlog is executed end-to-end, **When** the orchestrator finishes its run, **Then** the final per-feature summary classifies the happy-path item as `(phase=done, status=complete)`, the vague item as `(status=blocked)` with the clarification question visible, and the `- [x]` item as skipped (absent from the active feature set or recorded with a "skipped-already-complete" payload).

---

### User Story 4 - Repeatable prepare for rapid iteration (Priority: P3)

While iterating on a bug fix, the maintainer wants to call prepare repeatedly and always land on the same starting state — no leftover artifacts from the previous run, no manual cleanup step in between — so each debug iteration starts identical to the last.

**Why this priority**: Quality-of-life for active debugging. The maintainer can already chain cleanup + prepare manually, so this is a nice-to-have that smooths the loop, not a blocker for the core feature.

**Independent Test**: Run prepare, run `/speckit-orchestrate` to completion or partial completion, then run prepare again without an intervening explicit cleanup. Verify that the sandbox is reset to the same initial state and that no prior run's worktrees, branches, or state files remain.

**Acceptance Scenarios**:

1. **Given** a sandbox already exists from a previous run (clean or messy), **When** the maintainer runs prepare again, **Then** prepare first removes the existing sandbox exactly as cleanup would, then creates a fresh sandbox, and prints a clear notice that the previous sandbox was discarded.
2. **Given** a sandbox is currently locked because a Lead session is actively running against it (a state lock file is present), **When** the maintainer runs prepare again, **Then** prepare refuses to recreate the sandbox, names the active lock, instructs the maintainer to stop the Lead session first, and leaves the existing sandbox untouched.

---

### Edge Cases

- **Host repository is dirty**: The sandbox lives outside the host's tracked tree, so prepare must succeed regardless of the host's uncommitted state and must not stage, commit, or stash anything in the host repo.
- **Sandbox path is on a filesystem with limited permissions**: Prepare reports the OS-level error verbatim and exits non-zero before creating any partial state.
- **`BACKLOG.md` sample is hand-edited by the maintainer between runs**: The maintainer's edits are wiped on the next prepare; the sandbox is by definition disposable, and there is no merge of edits.
- **Cleanup is interrupted partway**: A subsequent cleanup completes the removal idempotently; partial sandbox state is detected and finished off rather than treated as an error.
- **Sandbox is opened in another Claude Code session or editor while cleanup runs**: Cleanup proceeds; the maintainer is responsible for closing handles. OS-level "file in use" errors are surfaced with the offending path.
- **Disk full during prepare**: Prepare aborts, removes any partial sandbox state it created, and reports the failure.
- **Sandbox directory exists but is not a sandbox produced by prepare (e.g., the maintainer manually put files there)**: Cleanup refuses to operate on the path because it cannot prove ownership; the maintainer must move the directory aside manually. This is the same safety check as scenario 3 of User Story 2.

## Requirements *(mandatory)*

### Functional Requirements

#### Commands

- **FR-001**: Extension MUST expose `/speckit-sandbox-prepare` as a distinct slash skill that prepares the sandbox. It MUST be invokable from the host repository's root without arguments and MUST appear in the Claude Code skill list alongside the orchestrator's other skills (`/speckit-orchestrate`, etc.).
- **FR-002**: Extension MUST expose `/speckit-sandbox-cleanup` as a distinct slash skill that removes the sandbox. It MUST be invokable from the host repository's root without arguments and MUST appear in the Claude Code skill list. The two sandbox skills MUST NOT be folded into a single skill with sub-arguments; each lifecycle action has its own SKILL.md so the verb is visible in the skill list.
- **FR-003**: Both `/speckit-sandbox-prepare` and `/speckit-sandbox-cleanup` MUST print a one-line summary of what they did on exit (path created / path removed / nothing to do), so the maintainer never has to inspect the filesystem to know the result.

#### Sandbox location and isolation

- **FR-004**: Sandbox MUST live at the fixed path `.sandbox/` relative to the host repository root. No configuration, environment variable, or argument overrides this location in v1; the path is hardcoded so cleanup's deletion target is unambiguous.
- **FR-005**: Prepare MUST ensure the host repository's `.gitignore` contains an entry that excludes `.sandbox/` from git tracking. If `.gitignore` does not exist, prepare creates it; if it already excludes `.sandbox/` (directly or via a broader rule), prepare leaves it untouched.
- **FR-006**: Sandbox MUST be a fully-initialised git repository in its own right (not a subdirectory of the host's git tree, not a worktree of the host) so that the orchestrator inside the sandbox can create its own worktrees and branches against an independent git history.
- **FR-007**: Cleanup MUST verify its deletion target resolves to `<host-repo-root>/.sandbox/` and refuse to delete anything else. Even if invoked with a manipulated working directory, symlink target, or future configuration override, cleanup MUST exit non-zero and print the offending path rather than delete it.

#### Sandbox contents

- **FR-008**: Prepare MUST install the orchestrator extension into the sandbox using the same installation entry point that real end-users invoke, so installation regressions are caught by sandbox runs.
- **FR-009**: Prepare MUST create the orchestrator's configured default target branch (named per the orchestrator's `merge.target_branch` default) inside the sandbox before the maintainer runs `/speckit-orchestrate`, so the merge step does not fail on missing target.
- **FR-010**: Prepare MUST place a sample `BACKLOG.md` at the sandbox root containing exactly three top-level checkbox items, in this order:
  1. A `- [ ]` happy-path item with a description specific enough that the BA pipeline completes without surfacing a clarification request.
  2. A `- [ ]` clarification-needed item with a description deliberately vague on a scope-significant detail so that `/speckit-clarify` or `/speckit-analyze` raises a question and the feature pauses in `(status=blocked)`.
  3. A `- [x]` already-complete item that the orchestrator MUST skip per its `FR-003a` skip-on-checked behavior; presence of this item in the parsed-but-skipped state is observable in the orchestrator's state file.
  Failure-injection items (Dev-failure, merge-conflict) are explicitly out of scope for v1 because they are brittle to engineer deterministically.
- **FR-011**: Prepare MUST NOT pre-run `/speckit-orchestrate`; it produces a ready-to-run sandbox and stops. The maintainer is the one who starts the Lead.
- **FR-012**: Prepare MUST commit the initial sandbox state (extension installation, sample backlog, dev branch creation) so that the orchestrator's `safety.on_dirty_tree` default of `refuse` does not block the first `/speckit-orchestrate` invocation.

#### Lifecycle behavior

- **FR-013**: When prepare runs and a sandbox already exists, it MUST first remove the existing sandbox (equivalent to running cleanup) and then create a fresh one. The action MUST be announced in the command output so the maintainer is never surprised by the destruction.
- **FR-014**: When prepare detects that the existing sandbox has an active orchestrator lock file indicating a running Lead session, it MUST refuse to recreate the sandbox, name the lock, instruct the maintainer to stop the Lead first, and leave the existing sandbox untouched.
- **FR-015**: When cleanup runs and no sandbox exists, it MUST exit successfully with a message stating there was nothing to clean.
- **FR-016**: When cleanup runs and a sandbox exists, it MUST remove the entire sandbox directory regardless of whether internal worktrees, branches, or files are tracked, dirty, locked from prior interrupted runs, or unknown to the orchestrator's state file. The sandbox is by definition disposable.

#### Dependency and prerequisite handling

- **FR-017**: Prepare MUST verify the required external tools (`git` with worktree support, `jq`, plus any others the orchestrator requires) and the required orchestrator source files are present before creating any sandbox state. Missing dependencies MUST cause prepare to abort with the missing item named and no partial sandbox left behind.
- **FR-018**: Prepare MUST run successfully regardless of the host repository's working tree state — clean, dirty, with stashes, with uncommitted files — because the sandbox is fully external to the host's tree. The host's git state MUST NOT be inspected, modified, staged, committed, stashed, or restored by prepare.

#### Coverage of the agentic flow

- **FR-019**: A single end-to-end run of `/speckit-orchestrate` inside a freshly prepared sandbox MUST exercise every orchestrator phase that exists in production — BA pipeline (specify, clarify, plan, tasks, analyze), Dev phase (implement), and the merge phase — without test-only code paths, mocks, or shortcuts.
- **FR-020**: The sample backlog MUST be small enough that a sandbox run completes in a time bounded for interactive debugging (so a maintainer can iterate within a typical Claude Code session) yet still covers the behaviors named in FR-019.

### Key Entities *(include if feature involves data)*

- **Sandbox**: A self-contained, disposable test environment produced by `/speckit-sandbox-prepare`. Consists of an isolated git repository at `.sandbox/` inside the host repo, the orchestrator extension installed, a sample `BACKLOG.md`, and a configured dev branch. Owned and entirely controlled by `/speckit-sandbox-prepare` and `/speckit-sandbox-cleanup`; the maintainer interacts with the sandbox only by running orchestrator commands inside it.
- **Sample Backlog**: The `BACKLOG.md` file placed inside the sandbox by prepare. Designed to cover happy-path and clarification scenarios within a single run.
- **Sandbox Lock**: A signal (presence of an active orchestrator state lock file inside the sandbox) that an orchestrator Lead is currently running against the sandbox. Read-only to the sandbox commands; consulted by prepare to decide whether re-prepare is safe.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A maintainer with a clean checkout of the orchestrator project can go from "no sandbox" to a running `/speckit-orchestrate` session against the sample backlog using exactly two slash commands (`/speckit-sandbox-prepare`, then `/speckit-orchestrate` inside the sandbox) and zero manual filesystem edits.
- **SC-002**: After running cleanup, comparing the host repository before prepare to after cleanup shows zero new tracked files, zero modified tracked files, zero new ignored files outside the sandbox path, and zero new git branches in the host repository.
- **SC-003**: Re-running prepare on an existing sandbox always reaches an identical post-prepare state — same files present, same sample `BACKLOG.md` contents, same dev branch — regardless of what the previous sandbox contained.
- **SC-004**: A single end-to-end run of `/speckit-orchestrate` inside the freshly prepared sandbox visits at least one feature in every phase the orchestrator implements (BA, Dev, merge) and produces exactly: one feature in `(phase=done, status=complete)` (the happy-path item), one feature in `(status=blocked)` awaiting clarification (the vague item), and one item not processed at all because it was marked `- [x]` in the sample backlog. All three outcomes are observable in the orchestrator's `state.json` and final summary.
- **SC-005**: Cleanup never deletes any file or directory outside the documented sandbox path, even when invoked with deliberately mis-set configuration; an automated audit comparing host-tree filesystem snapshots before prepare and after cleanup reports a non-sandbox delta of exactly zero entries.
- **SC-006**: 100% of orchestrator commands a real user can invoke (`/speckit-orchestrate`, `/speckit-orchestrate --retry-failed`) are runnable inside a freshly prepared sandbox without additional setup.

## Assumptions

- **Audience is the extension maintainer, not the end-user**: This feature exists to debug the orchestrator itself. The sandbox commands are not part of the orchestrator's user-facing surface; they are developer tooling shipped alongside the extension's source tree.
- **Sandbox path is fixed**: The sandbox lives at the hardcoded path `.sandbox/` inside the host repository root, added to the host's `.gitignore` by prepare. There is no configuration knob, environment variable, or CLI flag for the path in v1; making the location fixed is what makes cleanup's deletion target trivially safe to verify.
- **Real agentic flow, no mocks**: The sandbox runs the same Claude Code subagents, the same Spec Kit commands, and the same hook scripts that real users run. Mocks would defeat the purpose (debugging the *real* functionality), so the sandbox does not simulate the agentic loop.
- **Sample backlog is small but representative**: The sample `BACKLOG.md` contains a handful of items chosen to exercise the orchestrator's important paths in one short run. It is not a comprehensive test corpus and does not aim to replace dedicated test suites.
- **One sandbox at a time**: A single sandbox per host repository is supported. Concurrent sandboxes (parallel debug sessions on the same host checkout) are out of scope for v1.
- **Cleanup is destructive**: Cleanup removes the sandbox without quarantine, backup, or undo. Maintainers who want to preserve a sandbox for post-mortem inspection must copy the directory aside themselves before running cleanup.
- **Dependencies are the user's responsibility**: Prepare verifies and reports missing dependencies but does not attempt to install them. Maintainers install `git`, `jq`, and other prerequisites themselves per the orchestrator's quickstart guide.
- **Sandbox commands live with the orchestrator extension**: `/speckit-sandbox-prepare` and `/speckit-sandbox-cleanup` are part of the orchestrator extension's deliverables (alongside `/speckit-orchestrate`), not a separate extension. They share the extension's directory layout, version, and configuration conventions; each gets its own `SKILL.md` so the skill list shows the verb directly.

## Dependencies

- The extension depends on the Backlog Orchestrator Extension (feature `001-backlog-orchestrator-extension`) being implemented, since the sandbox is built around testing that extension. Sandbox prepare reuses the orchestrator's documented installation entry point.
- Sandbox prepare depends on the same external tools the orchestrator depends on: `git` with `worktree` support and `jq` ≥ 1.6.
- The sample `BACKLOG.md` depends on the orchestrator's documented backlog grammar (one top-level Markdown checkbox per feature) so it parses correctly inside the sandbox.
- The dev-branch setup inside the sandbox depends on the orchestrator's `merge.target_branch` default; a change to that default in the orchestrator would propagate here.
