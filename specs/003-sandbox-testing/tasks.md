---

description: "Task list for the Sandbox Testing feature (003-sandbox-testing)"
---

# Tasks: Sandbox Testing for Orchestrator Extension

**Input**: Design documents from `/specs/003-sandbox-testing/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. `bats` unit + integration tests are part of the plan's Technical Context (Testing section) and the constitution's Portability gate requires POSIX-shell helpers to be `bats`-tested.

**Organization**: Tasks are grouped by user story (US1–US4 from spec.md) so each can be implemented and tested independently. The two P1 user stories (prepare, cleanup) are the MVP; US3 and US4 are validation-and-ergonomics increments on top.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Different file, no dependency on incomplete prior tasks → safe to run in parallel.
- **[Story]**: `[US1]`–`[US4]` for user-story-phase tasks. Setup, Foundational, Polish phases carry no story label.
- Every task names the exact file path it touches.

## Path Conventions

All paths are repository-relative to the orchestrator project root
(`/Users/Ievgen_Kyvgyla/Projects/empty/spec-kit-empty-orchestrator/`).

This is a Spec Kit **extension** increment — no `src/`. New files live under:

- Extension source: `.specify/extensions/orchestrate/{commands,scripts/sh,assets}/`
- User-facing skills: `.claude/skills/speckit-sandbox-{prepare,cleanup}/SKILL.md` (synced from `commands/` by `install.sh`)
- Tests: `tests/extensions/orchestrate/{unit,integration}/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the directories the new files will live in and confirm the orchestrator extension is the integration point.

- [ ] T001 Create the new asset directory at `.specify/extensions/orchestrate/assets/` (empty for now)
- [ ] T002 [P] Verify the orchestrator extension's existing layout is intact (`.specify/extensions/orchestrate/{extension.yml,install.sh,commands/,scripts/sh/}` all present) — no edits, just a sanity check before Foundational work touches them

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Register the new commands in the extension manifest, teach `install.sh` to sync them, and place the canonical sample backlog asset. After this phase the orchestrator extension *knows about* the new commands, even though their implementations are still empty.

**⚠️ CRITICAL**: No user-story phase can begin until Phase 2 completes.

- [ ] T003 [P] Update `.specify/extensions/orchestrate/extension.yml` to add two new entries under `provides.commands`:
  - `speckit.sandbox.prepare` → `commands/speckit.sandbox.prepare.md`
  - `speckit.sandbox.cleanup` → `commands/speckit.sandbox.cleanup.md`
  Match the schema and indentation of the existing `speckit.orchestrate` entry.
- [ ] T004 [P] Update `.specify/extensions/orchestrate/install.sh` so the "Sync Skill" block syncs all three commands (the existing `speckit.orchestrate.md` plus the two new `speckit.sandbox.*.md` files) by iterating over a list rather than the current single-file `cp`. Sync target paths are `.claude/skills/speckit-sandbox-prepare/SKILL.md` and `.claude/skills/speckit-sandbox-cleanup/SKILL.md`. Missing-source warnings must continue to be non-fatal so install remains idempotent during partial check-ins.
- [ ] T005 Create `.specify/extensions/orchestrate/assets/sandbox-backlog.md` containing the exact byte content specified by `specs/003-sandbox-testing/contracts/sample-backlog.template.md` (trailing newline, LF endings, no BOM). After writing, verify `sha256sum` produces a stable hash that the integration test can pin.

**Checkpoint**: `extension.yml` declares two new commands; `install.sh` will sync them once their source markdown exists; the sample backlog asset is in place. User-story phases can now start.

---

## Phase 3: User Story 1 — Prepare a self-contained sandbox in one command (Priority: P1) 🎯 MVP

**Goal**: A maintainer running `/speckit-sandbox-prepare` from the host repo root gets a fully wired `.sandbox/` directory ready to accept `/speckit-orchestrate`. Single command, no arguments. Includes re-prepare wipe (FR-013) and lock-respect (FR-014) so US1 ships as a feature-complete prepare.

**Independent Test**: From the host root, run `/speckit-sandbox-prepare`. Assert that `.sandbox/` exists with the layout in `contracts/sandbox-layout.md`, the host's `.gitignore` contains `.sandbox/`, and running `git status` in the sandbox prints clean working tree on branch `main` with `dev` also present. (Re-tests covered in US4.)

### Tests for User Story 1 ⚠️

> **Write these tests FIRST and confirm they fail before implementing T009.**

- [ ] T006 [P] [US1] Author bats fixture helper `tests/extensions/orchestrate/unit/helpers/sandbox-fixture.sh` that builds a throwaway host repo via `mktemp -d`, copies the orchestrator's `.specify/` and `.claude/` into it, and yields its path. Reused by all sandbox-related tests.
- [ ] T007 [P] [US1] Create `tests/extensions/orchestrate/unit/sandbox-prepare.bats` with a "happy path" test: in a throwaway host, run `sandbox-prepare.sh`, assert `.sandbox/.git` exists, `.sandbox/BACKLOG.md` is byte-equal to the asset, `.sandbox/.specify/extensions/orchestrate/extension.yml` exists, host `.gitignore` contains `.sandbox/`, and the sandbox `git log -1 --format=%s` equals `chore(sandbox): initial sandbox state`.
- [ ] T008 [P] [US1] Extend `tests/extensions/orchestrate/unit/sandbox-prepare.bats` with a "missing dependency" test: stub `PATH` to hide `git`, run `sandbox-prepare.sh`, assert non-zero exit, the missing tool name in stderr, and that `.sandbox/` was NOT created (FR-017).

### Implementation for User Story 1

- [ ] T009 [US1] Create `.specify/extensions/orchestrate/commands/speckit.sandbox.prepare.md` as the source for the `/speckit-sandbox-prepare` skill. Header (YAML frontmatter) declares the skill name; body instructs Claude Code to invoke `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh` via the Bash tool and surface its stdout/stderr to the user. Mirror the structure of the existing `commands/speckit.orchestrate.md`.
- [ ] T010 [US1] Create `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh` (POSIX `sh`, `set -u`, no Bashisms). Logic in order:
  1. Resolve `REPO_ROOT` via `git rev-parse --show-toplevel` (abort if not in a git tree).
  2. Verify dependencies (`git`, `realpath` or `pwd -P` fallback). On missing dep, print missing name and `exit 1` (FR-017).
  3. Compute `SANDBOX="$REPO_ROOT/.sandbox"` and `LOCK="$SANDBOX/.specify/extensions/orchestrate/lock"`.
  4. If `LOCK` exists, print refusal message naming the lock and `exit 2` (FR-014).
  5. If `SANDBOX` exists, invoke `sandbox-cleanup.sh` to wipe it and print a "discarded previous sandbox" notice (FR-013). The cleanup helper handles the path-safety check.
  6. Ensure host `.gitignore` contains a line matching `^\.sandbox/?$`; append `.sandbox/` if not present (FR-005). Never duplicate.
  7. `mkdir -p "$SANDBOX" && cd "$SANDBOX"`.
  8. `git init --quiet && git checkout -b main --quiet`.
  9. `cp -R "$REPO_ROOT/.specify" .specify` and `cp -R "$REPO_ROOT/.claude" .claude` (POSIX `-R` per research §5).
  10. Remove runtime debris that hitchhiked: `rm -f .specify/extensions/orchestrate/state.json .specify/extensions/orchestrate/events.log .specify/extensions/orchestrate/lock`; `find .specify/extensions/orchestrate/worktrees -mindepth 1 -delete 2>/dev/null || true`.
  11. `cp "$REPO_ROOT/.specify/extensions/orchestrate/assets/sandbox-backlog.md" BACKLOG.md` (FR-010).
  12. Run `sh .specify/extensions/orchestrate/install.sh` to validate the install entry point inside the sandbox (FR-008). Pass through stdout but on non-zero exit, fail prepare with the install output captured.
  13. `git add -A`, then commit with `-c user.email=sandbox@local -c user.name=Sandbox` and message `chore(sandbox): initial sandbox state` (Principle V).
  14. `git checkout -b dev --quiet && git checkout main --quiet` (FR-009, dev branch present but HEAD on main).
  15. `printf 'sandbox: prepared at %s\n' "$SANDBOX"` (FR-003).
- [ ] T011 [US1] Verify tests in `tests/extensions/orchestrate/unit/sandbox-prepare.bats` (T007 and T008) pass against the implemented `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh`. Confirm before moving to US2.

**Checkpoint**: `/speckit-sandbox-prepare` works end-to-end. A maintainer can invoke it and inside the produced sandbox can manually run `/speckit-orchestrate` (the MVP slice).

---

## Phase 4: User Story 2 — Tear down the sandbox completely in one command (Priority: P1)

**Goal**: `/speckit-sandbox-cleanup` removes `.sandbox/` entirely, with path-safety hardening so it can never delete anything else. Idempotent no-op when the sandbox is absent.

**Independent Test**: From the host root, after a prepare, run `/speckit-sandbox-cleanup`. Assert `.sandbox/` no longer exists, `git status` on the host is identical to before prepare (modulo the `.gitignore` entry, which is one-way), and a second cleanup is a clean no-op.

### Tests for User Story 2 ⚠️

> **Write these tests FIRST and confirm they fail before implementing T015.**

- [ ] T012 [P] [US2] Create `tests/extensions/orchestrate/unit/sandbox-cleanup.bats` with a "happy path" test: in a throwaway host that has a prepared sandbox, run `sandbox-cleanup.sh`, assert `.sandbox/` is gone and the rest of the host tree is byte-identical to its pre-prepare snapshot (compute via `find <host> -path '*/.sandbox' -prune -o -type f -print | xargs sha256sum`).
- [ ] T013 [P] [US2] Extend `sandbox-cleanup.bats` with a "no-op when absent" test: in a throwaway host with no `.sandbox/`, run `sandbox-cleanup.sh`, assert exit 0 and stdout contains `nothing to clean` (FR-015).
- [ ] T014 [P] [US2] Extend `sandbox-cleanup.bats` with a "path-safety" test: in a throwaway host, create `.sandbox` as a symlink to a separate `mktemp -d` decoy directory; run `sandbox-cleanup.sh`, assert non-zero exit, stderr names the resolved decoy path, and the decoy is **not** deleted (FR-007, SC-005). Repeat with a `.sandbox` regular dir whose `realpath` differs from `<repo-root>/.sandbox` (e.g., if `<repo-root>` itself is a symlink).
- [ ] T015 [P] [US2] Extend `sandbox-cleanup.bats` with a "cleanup ignores lock" test: in a throwaway host with a prepared sandbox, manually `touch .sandbox/.specify/extensions/orchestrate/lock`, run `sandbox-cleanup.sh`, assert exit 0 and `.sandbox/` is gone (FR-016 — cleanup is the escape hatch).

### Implementation for User Story 2

- [ ] T016 [US2] Create `.specify/extensions/orchestrate/commands/speckit.sandbox.cleanup.md` as the source for the `/speckit-sandbox-cleanup` skill. Same shape as T009: frontmatter + body invoking the helper via Bash.
- [ ] T017 [US2] Create `.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh` (POSIX `sh`, `set -u`). Logic:
  1. `REPO_ROOT="$(git rev-parse --show-toplevel)" || err "not inside a git working tree"`.
  2. `SANDBOX="$REPO_ROOT/.sandbox"`.
  3. If `! -e "$SANDBOX"`, print `sandbox: nothing to clean.` and `exit 0` (FR-015).
  4. Resolve canonical paths: `SANDBOX_REAL="$(realpath -- "$SANDBOX" 2>/dev/null || (cd "$SANDBOX" && pwd -P))"` and `EXPECTED_REAL="$(cd "$REPO_ROOT" && pwd -P)/.sandbox"`. If they don't match exactly, `err "refusing to delete: $SANDBOX_REAL ≠ $EXPECTED_REAL"` and `exit 1` (FR-007, SC-005).
  5. `rm -rf -- "$SANDBOX_REAL"` (leading `--` per research §4).
  6. `printf 'sandbox: removed %s\n' "$SANDBOX"` (FR-003).
- [ ] T018 [US2] Verify tests in `tests/extensions/orchestrate/unit/sandbox-cleanup.bats` (T012–T015) pass against the implemented `.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh`. Confirm before moving to US3.
- [ ] T019 [US2] Verify in `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh` that the re-prepare path (T010 step 5) invokes `sandbox-cleanup.sh` rather than `rm -rf`-ing the sandbox directly, so the path-safety check always runs.

**Checkpoint**: Both P1 stories shipping. The MVP — prepare + cleanup — is functional and tested. The maintainer can already iterate `/speckit-sandbox-prepare` → `/speckit-orchestrate` → `/speckit-sandbox-cleanup` end-to-end.

---

## Phase 5: User Story 3 — Sample backlog covers the orchestrator's key behaviors out of the box (Priority: P2)

**Goal**: Validate that the sample backlog placed by prepare matches the byte-pinned contract and that the orchestrator's `parse-backlog.sh` (feature `001`) classifies it as 2 actionable + 1 skipped item.

**Independent Test**: After prepare in a throwaway host, run the orchestrator's `parse-backlog.sh` (already shipped) against `.sandbox/BACKLOG.md`. Assert it emits exactly 2 actionable JSON items (`add pi calculator`, `add notifications`) and 1 skipped item (`setup project scaffolding`).

### Tests for User Story 3 ⚠️

- [ ] T020 [P] [US3] Create `tests/extensions/orchestrate/integration/sandbox-lifecycle.bats`. Test layout: prepare in a throwaway host → assert every required entry from `contracts/sandbox-layout.md` (the table) → assert byte-equality of `.sandbox/BACKLOG.md` with the asset (via `sha256sum`) → invoke `parse-backlog.sh` against the sandbox backlog → assert it returns 2 actionable items and 1 skipped item with the expected canonical titles → cleanup → assert host tree identical to pre-prepare snapshot.
- [ ] T021 [P] [US3] In `sandbox-lifecycle.bats`, add a "byte-stability" sub-test: run prepare twice (with cleanup in between if needed) on the same host, assert the resulting `.sandbox/BACKLOG.md` SHA-256 is identical across runs (SC-003).

### Implementation for User Story 3

- [ ] T022 [US3] Verify `tests/extensions/orchestrate/integration/sandbox-lifecycle.bats` (T020 + T021) passes against the asset at `.specify/extensions/orchestrate/assets/sandbox-backlog.md`. No production code change expected — if it fails because `.specify/extensions/orchestrate/scripts/sh/parse-backlog.sh` (from feature `001`) doesn't return the expected 2 + 1 split, escalate as a feature `001` bug rather than patching here.

**Checkpoint**: The sample backlog is provably correct and stable across runs.

---

## Phase 6: User Story 4 — Repeatable prepare for rapid iteration (Priority: P3)

**Goal**: Lock in the FR-013 (re-prepare wipes) and FR-014 (re-prepare refuses on lock) behaviors with dedicated regression tests so future refactors of `sandbox-prepare.sh` don't silently break the debug loop.

**Independent Test**: Run prepare twice; assert the second prepare wipes and recreates. Run prepare with a lock file present; assert refusal.

### Tests for User Story 4 ⚠️

- [ ] T023 [P] [US4] Add a "re-prepare wipes existing sandbox" test to `sandbox-prepare.bats`: prepare; touch a sentinel file inside `.sandbox/` (e.g., `.sandbox/SENTINEL`); prepare again; assert exit 0, the sentinel is gone, and stdout contains a notice that the previous sandbox was discarded (FR-013, US4 AS1).
- [ ] T024 [P] [US4] Add a "re-prepare refuses on active lock" test to `sandbox-prepare.bats`: prepare; `touch .sandbox/.specify/extensions/orchestrate/lock`; prepare again; assert non-zero exit (code 2 per T010 step 4), stderr names the lock path, and `.sandbox/` is **untouched** — the sentinel file from T023's setup must still be present after the refused prepare (FR-014, US4 AS2).

### Implementation for User Story 4

- [ ] T025 [US4] Verify tests T023 and T024 in `tests/extensions/orchestrate/unit/sandbox-prepare.bats` pass against the existing `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh`. If either fails, fix the existing helper rather than adding new code paths.

**Checkpoint**: All four user stories are tested and shipping. The debug loop is durable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, manual smoke test, and a final constitution check after the implementation lands.

- [ ] T026 [P] Update `.specify/extensions/orchestrate/README.md` to mention `/speckit-sandbox-prepare` and `/speckit-sandbox-cleanup` and link to `specs/003-sandbox-testing/quickstart.md`. Keep the addition to one paragraph plus the two skill references; do not rewrite the README.
- [ ] T027 [P] Re-run the Constitution Check from `plan.md` against the landed implementation. Confirm all five gates still PASS (no new subagents, no new JSON payloads, no new YAML config, all helpers POSIX `sh`, initial sandbox commit is Conventional Commits). Record the result in a one-paragraph note appended to `plan.md`'s Constitution Check section (or leave as-is if already accurate).
- [ ] T028 Manually walk through `specs/003-sandbox-testing/quickstart.md` from a clean checkout: run `/speckit-sandbox-prepare`, `cd .sandbox/`, run `/speckit-orchestrate`, observe at least one feature complete + one feature block on clarification, exit, run `/speckit-sandbox-cleanup`. This is the SC-001 + SC-004 smoke test and cannot be automated (requires real Claude Code subagents).
- [ ] T029 [P] Verify that running `install.sh` in the orchestrator project itself (host) is still idempotent after T004 — re-running it should sync all three skills without error and without overwriting unmodified files.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)** — no dependencies, but is trivial.
- **Phase 2 (Foundational)** — T003/T004 are `[P]` against each other (different files). T005 has no dependencies. All three block all user-story phases.
- **Phase 3 (US1 Prepare)** — blocked by Phase 2. T006 can begin in parallel with T007/T008 (different file). T009 and T010 can begin in parallel with each other (different files). T011 is a verification gate, runs after T010.
- **Phase 4 (US2 Cleanup)** — blocked by Phase 2. Functionally independent of US1, but **US1's T010 calls `sandbox-cleanup.sh` for the re-prepare path** — so US1's T010 can land without US2 only if T010 conditionally degrades (e.g., calls the script if present, otherwise emits a warning). Cleanest order: ship US2's T017 in parallel with US1's T010 so both lock in together; or ship US2 before US1's T010. Document this explicitly: **T010 depends on T017** (the cleanup helper must exist) — even though the stories are otherwise independent.
- **Phase 5 (US3)** — blocked by Phase 4 (uses cleanup). T020 depends on `parse-backlog.sh` existing in the host's orchestrator extension (already true).
- **Phase 6 (US4)** — blocked by Phase 4 (uses cleanup via re-prepare).
- **Phase 7 (Polish)** — blocked by Phases 3–6.

### User story independence

- **US1 (Prepare)** and **US2 (Cleanup)** are P1 — both must ship for the MVP. They share one code coupling: `sandbox-prepare.sh` invokes `sandbox-cleanup.sh` for the re-prepare wipe path. This is the only cross-story dependency in the feature.
- **US3 (Sample backlog)** and **US4 (Repeatable prepare)** are independent of each other and depend only on US1 + US2.

### Cross-story integration points

- **T010 → T017**: prepare invokes cleanup. T017 must land before T010 can call it, OR T010 ships first with cleanup-call gated behind `command -v` (less clean). Recommended: parallel development with explicit merge gate.
- All other tasks within a story phase are file-scoped and don't cross story lines.

### Parallel opportunities

- T003 ∥ T004 (different files).
- T006 ∥ T007 ∥ T008 (different files; T006 is a helper, T007 and T008 are tests using it — T006 should land first or be developed in lockstep).
- T009 ∥ T010 (different files; T009 is the SKILL source, T010 is the helper).
- T012 ∥ T013 ∥ T014 ∥ T015 (all in same `.bats` file — actually, they can be parallel test cases inside one file but cannot be parallel tasks; treat as sequential additions to one file).
- T020 ∥ T021 (different sub-tests of one integration file; can be authored in parallel by different contributors).
- T023 ∥ T024 (additions to `sandbox-prepare.bats`; sequential within one file).
- T026 ∥ T027 ∥ T029 (different files).

### Within each user story

- Tests authored first, asserted to fail.
- Helper script lands.
- Tests re-run, asserted to pass.

---

## Parallel Example: User Story 1

```bash
# After Foundational completes, US1 tests can be drafted in parallel:
Task: "Author bats fixture helper in tests/extensions/orchestrate/unit/helpers/sandbox-fixture.sh"     # T006
Task: "Write happy-path test in tests/extensions/orchestrate/unit/sandbox-prepare.bats"                # T007
Task: "Write missing-deps test in tests/extensions/orchestrate/unit/sandbox-prepare.bats"              # T008

# Once T006 lands, implementation can begin in parallel:
Task: "Author commands/speckit.sandbox.prepare.md"                                                      # T009
Task: "Author scripts/sh/sandbox-prepare.sh"                                                            # T010

# T010 requires T017 (cleanup helper) to call. Coordinate the merge between US1 and US2.
```

---

## Implementation Strategy

### MVP First (US1 + US2 together)

The P1 prepare/cleanup pair is the MVP. Until both ship, the debug loop is broken (you can prepare but can't reliably clean up, or vice versa). Treat them as a single deliverable.

1. Complete Phase 1 + Phase 2.
2. Complete Phase 3 (US1) and Phase 4 (US2) in parallel; coordinate the T010 ↔ T017 dependency.
3. **STOP and VALIDATE**: Manually run prepare → orchestrate → cleanup. If the loop works, MVP is shipped.

### Incremental Delivery After MVP

1. Phase 5 (US3): lock in sample backlog correctness — protects against silent regressions in `parse-backlog.sh`.
2. Phase 6 (US4): lock in re-prepare ergonomics — protects against future refactors breaking the iteration loop.
3. Phase 7: polish, docs, smoke test.

### One-Person Strategy

- Day 1: T001–T005 (Setup + Foundational).
- Day 2: T006–T011 + T017 (US1 prepare with US2 cleanup helper available).
- Day 3: T012–T019 (US2 cleanup tests + verify).
- Day 4: T020–T025 (US3 + US4 tests).
- Day 5: T026–T029 (polish + smoke test).

### Parallel Team Strategy

- Dev A: T003 + T009 + T010 (US1 implementation path).
- Dev B: T004 + T005 + T017 + T016 (Foundational + US2 implementation path).
- Dev C: T006–T008 + T012–T015 + T020–T024 (all test authoring).
- Merge gate before T011: T010 + T017 both landed.

---

## Notes

- `[P]` tasks = different files, no completion-order dependency.
- Helper script T006 (fixture) is the single most reused piece — get it right early.
- The lone cross-story coupling (T010 needs T017) is documented; don't introduce others.
- After each US-phase completion, commit with a Conventional-Commits-compliant message (e.g., `feat(sandbox): add /speckit-sandbox-prepare helper`).
- Avoid: editing existing orchestrator scripts beyond `install.sh` (T004) and `extension.yml` (T003); cleanup logic that doesn't run path-safety first; bats tests that pollute the host repo (always use `mktemp -d`).
- Per the constitution's Portability gate, every helper script must run unchanged on macOS and Linux. The bats tests must too — don't introduce GNU-only `sed`/`grep` flags or `coreutils`-only `realpath` semantics without a POSIX fallback.
