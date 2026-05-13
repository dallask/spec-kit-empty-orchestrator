---

description: "Task list for the Sandbox Testing feature (003-sandbox-testing)"
---

# Tasks: Sandbox Testing for Orchestrator Extension

**Input**: Design documents from `/specs/003-sandbox-testing/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included. `bats` unit + integration tests are part of the plan's Technical Context (Testing section) and the constitution's Portability gate requires POSIX-shell helpers to be `bats`-tested.

**Organization**: Tasks are grouped by user story (US1–US4 from spec.md) so each can be implemented and tested independently. The two P1 user stories (prepare, cleanup) are the MVP; US3 and US4 are validation-and-ergonomics increments on top.

**Revision note** (post-`/speckit-analyze`): Four remediations applied — C1 (`jq` added to T012 dependency check), C2 (T012 now writes a sandbox-root `.gitignore` for runtime exclusions), C3 (new T010 host-dirty-state test), O1 (T006 hoisted: cleanup helper script lives in Foundational so US1 has no cross-story dependency). Task IDs renumbered accordingly.

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

- [X] T001 Create the new asset directory at `.specify/extensions/orchestrate/assets/` (empty for now)
- [X] T002 [P] Verify the orchestrator extension's existing layout is intact (`.specify/extensions/orchestrate/{extension.yml,install.sh,commands/,scripts/sh/}` all present) — no edits, just a sanity check before Foundational work touches them

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Register the new commands in the extension manifest, teach `install.sh` to sync them, place the canonical sample backlog asset, and land the cleanup helper script (which `sandbox-prepare.sh` calls for the re-prepare wipe path — hoisted here so US1 has no cross-story dependency).

**⚠️ CRITICAL**: No user-story phase can begin until Phase 2 completes.

- [X] T003 [P] Update `.specify/extensions/orchestrate/extension.yml` to add two new entries under `provides.commands`:
  - `speckit.sandbox.prepare` → `commands/speckit.sandbox.prepare.md`
  - `speckit.sandbox.cleanup` → `commands/speckit.sandbox.cleanup.md`
  Match the schema and indentation of the existing `speckit.orchestrate` entry.
- [X] T004 [P] Update `.specify/extensions/orchestrate/install.sh` so the "Sync Skill" block syncs all three commands (the existing `speckit.orchestrate.md` plus the two new `speckit.sandbox.*.md` files) by iterating over a list rather than the current single-file `cp`. Sync target paths are `.claude/skills/speckit-sandbox-prepare/SKILL.md` and `.claude/skills/speckit-sandbox-cleanup/SKILL.md`. Missing-source warnings must continue to be non-fatal so install remains idempotent during partial check-ins.
- [X] T005 Create `.specify/extensions/orchestrate/assets/sandbox-backlog.md` containing the exact byte content specified by `specs/003-sandbox-testing/contracts/sample-backlog.template.md` (trailing newline, LF endings, no BOM). After writing, verify `sha256sum` produces a stable hash that the integration test can pin.
- [X] T006 [P] **(HOISTED from US2 — resolves O1)** Create `.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh` (POSIX `sh`, `set -u`). Logic:
  1. `REPO_ROOT="$(git rev-parse --show-toplevel)" || err "not inside a git working tree"`.
  2. `SANDBOX="$REPO_ROOT/.sandbox"`.
  3. If `! -e "$SANDBOX"`, print `sandbox: nothing to clean.` and `exit 0` (FR-015).
  4. Resolve canonical paths: `SANDBOX_REAL="$(realpath -- "$SANDBOX" 2>/dev/null || (cd "$SANDBOX" && pwd -P))"` and `EXPECTED_REAL="$(cd "$REPO_ROOT" && pwd -P)/.sandbox"`. If they don't match exactly, `err "refusing to delete: $SANDBOX_REAL ≠ $EXPECTED_REAL"` and `exit 1` (FR-007, SC-005).
  5. `rm -rf -- "$SANDBOX_REAL"` (leading `--` per research §4).
  6. `printf 'sandbox: removed %s\n' "$SANDBOX"` (FR-003).
  This script is a prerequisite for `sandbox-prepare.sh`'s re-prepare path (FR-013) and is the implementation behind `/speckit-sandbox-cleanup`. Tests live in US2.

**Checkpoint**: `extension.yml` declares two new commands; `install.sh` will sync them once their source markdown exists; the sample backlog asset is in place; the cleanup helper script exists (US2 tests will validate it). User-story phases can now start.

---

## Phase 3: User Story 1 — Prepare a self-contained sandbox in one command (Priority: P1) 🎯 MVP

**Goal**: A maintainer running `/speckit-sandbox-prepare` from the host repo root gets a fully wired `.sandbox/` directory ready to accept `/speckit-orchestrate`. Single command, no arguments. Includes re-prepare wipe (FR-013) and lock-respect (FR-014) so US1 ships as a feature-complete prepare.

**Independent Test**: From the host root, run `/speckit-sandbox-prepare`. Assert that `.sandbox/` exists with the layout in `contracts/sandbox-layout.md`, the host's `.gitignore` contains `.sandbox/`, and running `git status` in the sandbox prints clean working tree on branch `main` with `dev` also present. (Re-tests covered in US4.)

### Tests for User Story 1 ⚠️

> **Write these tests FIRST and confirm they fail before implementing T012.**

- [X] T007 [P] [US1] Author bats fixture helper `tests/extensions/orchestrate/unit/helpers/sandbox-fixture.sh` that builds a throwaway host repo via `mktemp -d`, copies the orchestrator's `.specify/` and `.claude/` into it, and yields its path. Reused by all sandbox-related tests.
- [X] T008 [US1] Create `tests/extensions/orchestrate/unit/sandbox-prepare.bats` with a "happy path" test case: in a throwaway host, run `sandbox-prepare.sh`, assert `.sandbox/.git` exists, `.sandbox/BACKLOG.md` is byte-equal to the asset, `.sandbox/.specify/extensions/orchestrate/extension.yml` exists, host `.gitignore` contains `.sandbox/`, and the sandbox `git log -1 --format=%s` equals `chore(sandbox): initial sandbox state`.
- [X] T009 [US1] Add a "missing dependency" test case to `tests/extensions/orchestrate/unit/sandbox-prepare.bats`: stub `PATH` to hide `git` (and separately to hide `jq`), run `sandbox-prepare.sh`, assert non-zero exit, the missing tool name in stderr, and that `.sandbox/` was NOT created (FR-017).
- [X] T010 [US1] **(NEW — resolves C3)** Add a "dirty host invariant" test case to `tests/extensions/orchestrate/unit/sandbox-prepare.bats`: in the fixture host, dirty the working tree by writing a tracked file (e.g., `HOST_DIRTY_SENTINEL.tmp`), capture `git status --porcelain` and a SHA-256 of every host file outside `.sandbox/`, run `sandbox-prepare.sh`, assert exit 0, assert `.sandbox/` was created, and assert `git status --porcelain` plus the host-file SHA-256 set are unchanged (FR-018). This locks the "host MUST NOT be inspected, modified, staged, committed, stashed, or restored by prepare" guarantee.

### Implementation for User Story 1

- [X] T011 [P] [US1] Create `.specify/extensions/orchestrate/commands/speckit.sandbox.prepare.md` as the source for the `/speckit-sandbox-prepare` skill. Header (YAML frontmatter) declares the skill name; body instructs Claude Code to invoke `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh` via the Bash tool and surface its stdout/stderr to the user. Mirror the structure of the existing `commands/speckit.orchestrate.md`.
- [X] T012 [US1] Create `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh` (POSIX `sh`, `set -u`, no Bashisms). Logic in order:
  1. Resolve `REPO_ROOT` via `git rev-parse --show-toplevel` (abort if not in a git tree).
  2. **(resolves C1)** Verify dependencies: `git` (presence + `git worktree --help` confirms worktree support), `jq` (required by the orchestrator that the sandbox will host — fail fast here per FR-017), and `realpath` with `pwd -P` fallback. On any missing dep, print missing name and `exit 1` (FR-017). Do **not** inspect host git tree state (FR-018).
  3. Compute `SANDBOX="$REPO_ROOT/.sandbox"` and `LOCK="$SANDBOX/.specify/extensions/orchestrate/lock"`.
  4. If `LOCK` exists, print refusal message naming the lock and `exit 2` (FR-014).
  5. If `SANDBOX` exists, invoke `sandbox-cleanup.sh` (already implemented in T006) to wipe it; print a "discarded previous sandbox" notice (FR-013). The cleanup helper enforces the path-safety check before any `rm`.
  6. Ensure host `.gitignore` contains a line matching `^\.sandbox/?$`; append `.sandbox/` if not present (FR-005). Never duplicate.
  7. `mkdir -p "$SANDBOX" && cd "$SANDBOX"`.
  8. `git init --quiet && git checkout -b main --quiet`.
  9. `cp -R "$REPO_ROOT/.specify" .specify` and `cp -R "$REPO_ROOT/.claude" .claude` (POSIX `-R` per research §5).
  10. Remove runtime debris that hitchhiked: `rm -f .specify/extensions/orchestrate/state.json .specify/extensions/orchestrate/events.log .specify/extensions/orchestrate/lock`; `find .specify/extensions/orchestrate/worktrees -mindepth 1 -delete 2>/dev/null || true`.
  11. **(resolves C2)** Write `.sandbox/.gitignore` so the sandbox-internal `.git` ignores orchestrator runtime files. Content (verbatim, LF endings, trailing newline):
       ```gitignore
       .specify/extensions/orchestrate/worktrees/
       .specify/extensions/orchestrate/state.json
       .specify/extensions/orchestrate/events.log
       .specify/extensions/orchestrate/lock
       ```
      This satisfies the row in `contracts/sandbox-layout.md` that requires a sandbox-root `.gitignore` excluding the runtime files.
  12. `cp "$REPO_ROOT/.specify/extensions/orchestrate/assets/sandbox-backlog.md" BACKLOG.md` (FR-010).
  13. Run `sh .specify/extensions/orchestrate/install.sh` to validate the install entry point inside the sandbox (FR-008). Pass through stdout; on non-zero exit, fail prepare with the install output captured.
  14. `git add -A`, then commit with `-c user.email=sandbox@local -c user.name=Sandbox` and message `chore(sandbox): initial sandbox state` (Principle V).
  15. `git checkout -b dev --quiet && git checkout main --quiet` (FR-009, dev branch present but HEAD on main).
  16. `printf 'sandbox: prepared at %s\n' "$SANDBOX"` (FR-003).
- [X] T013 [US1] Verify tests in `tests/extensions/orchestrate/unit/sandbox-prepare.bats` (T008, T009, T010) pass against the implemented `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh`. Confirm before moving to US2.

**Checkpoint**: `/speckit-sandbox-prepare` works end-to-end, including the dirty-host invariant. The MVP slice for prepare ships.

---

## Phase 4: User Story 2 — Tear down the sandbox completely in one command (Priority: P1)

**Goal**: `/speckit-sandbox-cleanup` removes `.sandbox/` entirely, with path-safety hardening so it can never delete anything else. Idempotent no-op when the sandbox is absent.

**Implementation note**: The cleanup helper script itself was hoisted into Phase 2 Foundational (T006) so US1's prepare could call it. This phase delivers the user-facing skill manifest and the tests that lock in cleanup's behavior.

**Independent Test**: From the host root, after a prepare, run `/speckit-sandbox-cleanup`. Assert `.sandbox/` no longer exists, `git status` on the host is identical to before prepare (modulo the `.gitignore` entry, which is one-way), and a second cleanup is a clean no-op.

### Tests for User Story 2 ⚠️

> **Write these tests FIRST and confirm they fail or pass deterministically against the T006 helper.**

- [X] T014 [P] [US2] Create `tests/extensions/orchestrate/unit/sandbox-cleanup.bats` with a "happy path" test: in a throwaway host that has a prepared sandbox, run `sandbox-cleanup.sh`, assert `.sandbox/` is gone and the rest of the host tree is byte-identical to its pre-prepare snapshot (compute via `find <host> -path '*/.sandbox' -prune -o -type f -print | xargs sha256sum`).
- [X] T015 [US2] Add a "no-op when absent" test to `tests/extensions/orchestrate/unit/sandbox-cleanup.bats`: in a throwaway host with no `.sandbox/`, run `sandbox-cleanup.sh`, assert exit 0 and stdout contains `nothing to clean` (FR-015).
- [X] T016 [US2] Add a "path-safety" test to `tests/extensions/orchestrate/unit/sandbox-cleanup.bats`: in a throwaway host, create `.sandbox` as a symlink to a separate `mktemp -d` decoy directory; run `sandbox-cleanup.sh`, assert non-zero exit, stderr names the resolved decoy path, and the decoy is **not** deleted (FR-007, SC-005). Repeat with a `.sandbox` regular dir whose `realpath` differs from `<repo-root>/.sandbox` (e.g., if `<repo-root>` itself is a symlink).
- [X] T017 [US2] Add a "cleanup ignores lock" test to `tests/extensions/orchestrate/unit/sandbox-cleanup.bats`: in a throwaway host with a prepared sandbox, manually `touch .sandbox/.specify/extensions/orchestrate/lock`, run `sandbox-cleanup.sh`, assert exit 0 and `.sandbox/` is gone (FR-016 — cleanup is the escape hatch).

### Implementation for User Story 2

- [X] T018 [P] [US2] Create `.specify/extensions/orchestrate/commands/speckit.sandbox.cleanup.md` as the source for the `/speckit-sandbox-cleanup` skill. Same shape as T011: frontmatter + body invoking the helper via Bash.
- [X] T019 [US2] Verify tests in `tests/extensions/orchestrate/unit/sandbox-cleanup.bats` (T014–T017) pass against `.specify/extensions/orchestrate/scripts/sh/sandbox-cleanup.sh` (implemented in T006). Confirm before moving to US3.
- [X] T020 [US2] Verify in `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh` that the re-prepare path (T012 step 5) invokes `sandbox-cleanup.sh` rather than `rm -rf`-ing the sandbox directly, so the path-safety check always runs.

**Checkpoint**: Both P1 stories shipping. The MVP — prepare + cleanup — is functional and tested. The maintainer can iterate `/speckit-sandbox-prepare` → `/speckit-orchestrate` → `/speckit-sandbox-cleanup` end-to-end.

---

## Phase 5: User Story 3 — Sample backlog covers the orchestrator's key behaviors out of the box (Priority: P2)

**Goal**: Validate that the sample backlog placed by prepare matches the byte-pinned contract and that the orchestrator's `parse-backlog.sh` (feature `001`) classifies it as 2 actionable + 1 skipped item.

**Independent Test**: After prepare in a throwaway host, run the orchestrator's `parse-backlog.sh` (already shipped) against `.sandbox/BACKLOG.md`. Assert it emits exactly 2 actionable JSON items (`add pi calculator`, `add notifications`) and 1 skipped item (`setup project scaffolding`).

### Tests for User Story 3 ⚠️

- [X] T021 [P] [US3] Create `tests/extensions/orchestrate/integration/sandbox-lifecycle.bats`. Test layout: prepare in a throwaway host → assert every required entry from `contracts/sandbox-layout.md` (the table, including the sandbox-root `.gitignore` from T012 step 11) → assert byte-equality of `.sandbox/BACKLOG.md` with the asset (via `sha256sum`) → invoke `parse-backlog.sh` against the sandbox backlog → assert it returns 2 actionable items and 1 skipped item with the expected canonical titles → cleanup → assert host tree identical to pre-prepare snapshot.
- [X] T022 [US3] Add a "byte-stability" sub-test to `tests/extensions/orchestrate/integration/sandbox-lifecycle.bats`: run prepare twice (with cleanup in between if needed) on the same host, assert the resulting `.sandbox/BACKLOG.md` SHA-256 is identical across runs (SC-003).

### Implementation for User Story 3

- [X] T023 [US3] Verify `tests/extensions/orchestrate/integration/sandbox-lifecycle.bats` (T021 + T022) passes against the asset at `.specify/extensions/orchestrate/assets/sandbox-backlog.md`. No production code change expected — if it fails because `.specify/extensions/orchestrate/scripts/sh/parse-backlog.sh` (from feature `001`) doesn't return the expected 2 + 1 split, escalate as a feature `001` bug rather than patching here.

**Checkpoint**: The sample backlog is provably correct and stable across runs.

---

## Phase 6: User Story 4 — Repeatable prepare for rapid iteration (Priority: P3)

**Goal**: Lock in the FR-013 (re-prepare wipes) and FR-014 (re-prepare refuses on lock) behaviors with dedicated regression tests so future refactors of `sandbox-prepare.sh` don't silently break the debug loop.

**Independent Test**: Run prepare twice; assert the second prepare wipes and recreates. Run prepare with a lock file present; assert refusal.

### Tests for User Story 4 ⚠️

- [X] T024 [US4] Add a "re-prepare wipes existing sandbox" test to `tests/extensions/orchestrate/unit/sandbox-prepare.bats`: prepare; touch a sentinel file inside `.sandbox/` (e.g., `.sandbox/SENTINEL`); prepare again; assert exit 0, the sentinel is gone, and stdout contains a notice that the previous sandbox was discarded (FR-013, US4 AS1).
- [X] T025 [US4] Add a "re-prepare refuses on active lock" test to `tests/extensions/orchestrate/unit/sandbox-prepare.bats`: prepare; `touch .sandbox/.specify/extensions/orchestrate/lock`; prepare again; assert non-zero exit (code 2 per T012 step 4), stderr names the lock path, and `.sandbox/` is **untouched** — the sentinel file from T024's setup must still be present after the refused prepare (FR-014, US4 AS2).

### Implementation for User Story 4

- [X] T026 [US4] Verify tests T024 and T025 in `tests/extensions/orchestrate/unit/sandbox-prepare.bats` pass against the existing `.specify/extensions/orchestrate/scripts/sh/sandbox-prepare.sh`. If either fails, fix the existing helper rather than adding new code paths.

**Checkpoint**: All four user stories are tested and shipping. The debug loop is durable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, manual smoke test, and a final constitution check after the implementation lands.

- [X] T027 [P] Update `.specify/extensions/orchestrate/README.md` to mention `/speckit-sandbox-prepare` and `/speckit-sandbox-cleanup` and link to `specs/003-sandbox-testing/quickstart.md`. Keep the addition to one paragraph plus the two skill references; do not rewrite the README.
- [X] T028 [P] Re-run the Constitution Check from `specs/003-sandbox-testing/plan.md` against the landed implementation. Confirm all five gates still PASS (no new subagents, no new JSON payloads, no new YAML config, all helpers POSIX `sh`, initial sandbox commit is Conventional Commits). Record the result in a one-paragraph note appended to `plan.md`'s Constitution Check section (or leave as-is if already accurate).
- [ ] T029 Manually walk through `specs/003-sandbox-testing/quickstart.md` from a clean checkout: run `/speckit-sandbox-prepare`, `cd .sandbox/`, run `/speckit-orchestrate`, observe at least one feature complete + one feature block on clarification, exit, run `/speckit-sandbox-cleanup`. This is the SC-001 + SC-004 + SC-006 smoke test and cannot be automated (requires real Claude Code subagents).
- [X] T030 [P] Verify that running `.specify/extensions/orchestrate/install.sh` in the orchestrator project itself (host) is still idempotent after T004 — re-running it should sync all three skills without error and without overwriting unmodified files.

---

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Setup)** — no dependencies, trivial.
- **Phase 2 (Foundational)** — T003/T004 are `[P]` against each other (different files). T005 has no dependencies. T006 (cleanup helper) is `[P]` against T003–T005 (different file). All four block all user-story phases.
- **Phase 3 (US1 Prepare)** — blocked by Phase 2. T007 stands alone in `helpers/`; T008 creates the test file and must precede T009/T010 (which extend it). T011 (SKILL.md) is independent and `[P]`. T012 (helper script) is independent of T011 (different file) and `[P]` against it; depends on T006 (calls cleanup). T013 is a verification gate.
- **Phase 4 (US2 Cleanup)** — blocked by Phase 2. Implementation (T006) already landed; this phase delivers tests and the SKILL.md. T014 creates the test file; T015–T017 extend it (sequential within file). T018 (SKILL.md) is independent. T019/T020 are verifications.
- **Phase 5 (US3)** — blocked by Phase 3 (uses prepare) + Phase 4 (uses cleanup).
- **Phase 6 (US4)** — blocked by Phase 3 (uses prepare) + Phase 4 (uses cleanup via re-prepare).
- **Phase 7 (Polish)** — blocked by Phases 3–6.

### User story independence

- **US1 (Prepare)** is now fully self-contained: T012 depends on T006 which is in Foundational, not US2. The cross-story coupling identified by `/speckit-analyze` (O1) is resolved.
- **US2 (Cleanup)** delivers the user-facing skill manifest and the regression tests for the helper that Foundational shipped.
- **US3, US4** are independent of each other; both depend on US1 + US2.

### Parallel opportunities

- T003 ∥ T004 ∥ T006 (different files).
- T007 ∥ T011 ∥ T012 (different files; once T006 exists, T012 can be written in parallel with T011 since they touch different files). T008/T009/T010 share a `.bats` file so they're sequential additions to that file.
- T014 ∥ T018 (different files); T015/T016/T017 share `sandbox-cleanup.bats` so sequential.
- T021 stands alone (new file); T022 extends it sequentially.
- T024 ∥ T025 — both extend `sandbox-prepare.bats`, sequential.
- T027 ∥ T028 ∥ T030 (different files).

### Within each user story

- Tests authored first, asserted to fail.
- Helper script lands (or is already in Foundational).
- Tests re-run, asserted to pass.

---

## Parallel Example: User Story 1

```bash
# After Foundational completes, US1 can split work across files:
Task: "Author bats fixture helper in tests/extensions/orchestrate/unit/helpers/sandbox-fixture.sh"     # T007
Task: "Author commands/speckit.sandbox.prepare.md"                                                      # T011
Task: "Author scripts/sh/sandbox-prepare.sh"                                                            # T012

# Within sandbox-prepare.bats, T008 → T009 → T010 are sequential additions to one file.
# All three test cases (happy-path, missing-deps, dirty-host) target the same bats file.
```

---

## Implementation Strategy

### MVP First (US1 + US2 together)

The P1 prepare/cleanup pair is the MVP. Until both ship, the debug loop is broken (you can prepare but can't reliably clean up, or vice versa). With the O1 remediation, the cleanup helper is in Foundational, so US1 is technically deliverable alone — but the user-facing `/speckit-sandbox-cleanup` skill needs US2's SKILL.md to be discoverable.

1. Complete Phase 1 + Phase 2 (including T006 cleanup helper).
2. Complete Phase 3 (US1) and Phase 4 (US2) — they're now independent.
3. **STOP and VALIDATE**: Manually run prepare → orchestrate → cleanup. If the loop works, MVP is shipped.

### Incremental Delivery After MVP

1. Phase 5 (US3): lock in sample backlog correctness — protects against silent regressions in `parse-backlog.sh`.
2. Phase 6 (US4): lock in re-prepare ergonomics — protects against future refactors breaking the iteration loop.
3. Phase 7: polish, docs, smoke test.

### One-Person Strategy

- Day 1: T001–T006 (Setup + Foundational, including cleanup helper).
- Day 2: T007–T013 (US1 prepare with all three test cases).
- Day 3: T014–T020 (US2 cleanup tests + SKILL.md + verifications).
- Day 4: T021–T026 (US3 + US4 tests).
- Day 5: T027–T030 (polish + smoke test).

### Parallel Team Strategy

- Dev A: T003 + T011 + T012 (US1 implementation path).
- Dev B: T004 + T005 + T006 + T018 (Foundational + US2 SKILL.md).
- Dev C: T007 + T008–T010 + T014–T017 + T021–T025 (all test authoring).
- Merge gate before T013: T006 + T012 both landed.

---

## Notes

- `[P]` tasks = different files, no completion-order dependency. Same-file additions (multiple bats test cases in one `.bats` file) are sequential.
- Helper script T007 (fixture) is the single most reused piece — get it right early.
- The cross-story coupling from the original draft is gone: T006 (cleanup helper) sits in Foundational, so T012 (prepare) doesn't depend on US2.
- After each US-phase completion, commit with a Conventional-Commits-compliant message (e.g., `feat(sandbox): add /speckit-sandbox-prepare helper`).
- Avoid: editing existing orchestrator scripts beyond `install.sh` (T004) and `extension.yml` (T003); cleanup logic that doesn't run path-safety first; bats tests that pollute the host repo (always use `mktemp -d`).
- Per the constitution's Portability gate, every helper script must run unchanged on macOS and Linux. The bats tests must too — don't introduce GNU-only `sed`/`grep` flags or `coreutils`-only `realpath` semantics without a POSIX fallback.
