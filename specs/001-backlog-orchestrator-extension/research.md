# Phase 0 Research: Backlog Orchestrator Extension

**Branch**: `001-backlog-orchestrator-extension` | **Date**: 2026-05-12
**Inputs**: [spec.md](./spec.md), [plan.md](./plan.md), `.specify/memory/constitution.md`

This document resolves the technical unknowns from `plan.md` Technical Context and the four areas the spec deferred to planning: Performance, Scalability, Observability, Security & Privacy, plus subagent timeout. Each section follows the **Decision / Rationale / Alternatives considered** format.

---

## 1. Claude Code subagent definition format

**Decision**: Each subagent is a Markdown file under `.claude/agents/<name>.md` with YAML frontmatter that declares `name`, `description`, `tools` (allowlist), and an optional `model`. The body of the file is the subagent's system prompt — the persistent instructions it sees every time the Lead invokes it via the `Agent` tool. Concretely we ship `.claude/agents/orchestrate-ba.md` and `.claude/agents/orchestrate-dev.md`. The Lead does not need its own subagent file — the Lead is the main Claude Code session and is configured by the `SKILL.md` invoked via `/speckit-orchestrate`.

**Rationale**: This is the format documented in the Claude Code Subagents page (<https://code.claude.com/docs/en/sub-agents>). The existing repo already adopts the convention (empty `.claude/agents/` directory, populated `.claude/skills/`). It matches constitution Principle I (Claude Code Alignment) — we do not invent a new format. The frontmatter-allowed `tools` field gives us the natural place to scope each subagent's permissions (e.g., the BA gets `Read, Write, Edit, Bash, Skill`; the Dev additionally needs file-modification breadth across its worktree).

**Alternatives considered**:
- *Single "agent" file with role-switching prompts.* Rejected: violates the documented one-subagent-per-file model and makes tool-scope per-role impossible.
- *Encoding BA/Dev as separate Skills and having Lead "call" them.* Rejected: Skills are user-invocable surface area, not internal delegation primitives. Using subagents is what the Claude Code docs prescribe.

---

## 2. Enforcing structured JSON return values from subagents

**Decision**: The Lead's invocation prompt to a subagent ends with: *"Return your entire final message as a single JSON object that validates against `agent-payload.schema.json`. Emit no prose before or after. Do not wrap in code fences."* The Lead validates the returned message against the schema in `contracts/agent-payload.schema.json`; non-JSON or schema-invalid responses are treated as `error` payloads (per FR-017). The subagent system prompts (`.claude/agents/orchestrate-ba.md`, `.claude/agents/orchestrate-dev.md`) embed the schema inline as a reference for the model.

**Rationale**: Claude Code subagents return a single final message to the parent; that message is the only data channel. Enforcing JSON-only output is straightforward via instruction + post-hoc validation, and constitution Principle III ("Structured JSON Contracts") makes prose responses non-negotiable. The Lead's robustness against malformed output (catch-and-treat-as-error) prevents a misbehaving subagent from corrupting state.

**Alternatives considered**:
- *Schema injection via the prompt only, no Lead-side validation.* Rejected: violates Principle III's "machine-checkable" requirement; one drift event silently corrupts state.
- *Tool-use return values instead of final message.* Rejected: Claude Code's documented data path from subagent to parent is the final message, not arbitrary tool returns. Going off-path is exactly what Principle I forbids.

---

## 3. Pause-for-clarification round-trip pattern

**Decision**: When the BA's `/speckit.clarify` or `/speckit.analyze` phase needs human input, the BA returns a `clarification_request` payload to the Lead and terminates. The Lead persists the request to state (`status=blocked`), surfaces the question to the user (one feature at a time, feature-id-ordered per FR-014), captures the answer, and **re-invokes the same subagent** with a prompt that includes the original feature context, the saved BA progress, and the user's answer as a `clarification_answer` payload. The subagent resumes from the paused phase.

**Rationale**: Claude Code subagents are not long-lived processes — each `Agent` invocation is a fresh session. So "resume" is implemented as "re-spawn with enough context to continue", which fits the stateless-subagent model exactly. The state file + the JSON `last_payload` together carry the durable resume state. This is the only resume pattern compatible with the documented subagent lifecycle (Principle I).

**Alternatives considered**:
- *Keep the BA subagent alive between phases.* Rejected: not supported by Claude Code's subagent model. Re-spawning is the official pattern.
- *Have the BA write a "pause" file and the Lead poll it.* Rejected: the message-return path already delivers structured data; adding a file-polling layer is redundant and racy.

---

## 4. Git worktree lifecycle (create, claim, prune)

**Decision**: All worktrees live under `.specify/extensions/orchestrate/worktrees/<feature-id>/` (gitignored), created via `git worktree add -b <branch-name> <path> <target_branch>`. Branch names follow the existing `speckit.git.feature` convention (`NNN-<short-name>`). On clean success (`phase=done, status=complete`) and `worktree.prune_on_success: true`, the Lead runs `git worktree remove <path>` and `git worktree prune`. On failure (`status=failed`) and `worktree.retain_on_failure: true` (default), the Lead leaves the worktree intact for inspection. The branch is **always retained** regardless of strategy (per Q3 clarification).

**Rationale**: `git worktree` is the standard isolation primitive (constitution Principle IV). Putting worktrees inside `.specify/extensions/orchestrate/` keeps them out of the user's main tree and out of source control. Branch retention even on success is what makes the spec/plan/tasks/implement commit history auditable after the squash-merge target commit lands.

**Alternatives considered**:
- *Sibling-directory worktrees (`../<repo>-worktrees/<id>`).* Rejected: pollutes the parent directory and breaks portability for `cd`-based scripts.
- *Always-prune-on-success even when retain_on_failure=true.* Already the default — but we make both behaviours configurable.
- *Auto-delete branches after squash merge.* Rejected: explicitly disallowed by the Q3 clarification ("feature branch is retained for audit").

---

## 5. POSIX-shell JSON manipulation: `jq` vs alternatives

**Decision**: Require `jq ≥ 1.6` as a soft dependency. The `orchestrate-common.sh` helper exposes `jq_required` and `json_read` / `json_write` wrappers; if `jq` is missing the Lead aborts at startup with an actionable install hint (`brew install jq` / `apt-get install jq` / `apk add jq`). No fallback to `python -m json.tool` because that would split the script-test matrix.

**Rationale**: All the existing Spec Kit shell helpers in this repo already assume `jq`. Standardising on it keeps the script surface tight, the tests deterministic, and the dependency story simple. `jq` is available on all our target platforms (macOS, Linux, WSL) via standard package managers. Constitution Principle V's "system-agnostic" clause is preserved: `jq` is not OS-specific.

**Alternatives considered**:
- *Hand-rolled `awk`/`sed` JSON parsing.* Rejected: fragile, hard to maintain, can't handle nested payloads.
- *Python (`json.tool`) fallback.* Rejected: doubles the testing burden for marginal portability gain on machines that are anyway expected to have `jq`.
- *Bundling `jq` binaries.* Rejected: bloats the repo, requires platform-specific binaries, conflicts with Principle V's portability.

---

## 6. Pre-allocating sequential feature numbers without race

**Decision**: The Lead owns sequence allocation. Before any subagent spawn, the Lead runs `scripts/sh/allocate-feature.sh` which: (a) takes a lock on `.specify/extensions/orchestrate/lock` via `flock` (or, on systems without `flock`, an `mkdir`-based mutex with a short retry loop), (b) scans `specs/` for the highest existing `NNN-` prefix, (c) allocates the next ID, (d) invokes the existing `.specify/extensions/git/scripts/bash/create-new-feature.sh` with `--number <id>` and `--short-name <derived>` to materialise the branch + spec directory, (e) releases the lock. Because only the Lead invokes this helper and the helper itself is serialised by the lock, the race the spec was worried about (two BAs scanning at the same time) is structurally impossible.

**Rationale**: The Q10 clarification ("Lead pre-allocates") combined with constitution Principle II ("Lead owns all worktree creation") means we can serialise allocation cheaply. Using the existing `create-new-feature.sh` rather than reinventing it satisfies Principle IV (the spec directory must be created the way Spec Kit expects).

**Alternatives considered**:
- *Each BA invokes `speckit.git.feature` itself with a file-lock around the next-number scan.* Rejected by the Q10 clarification.
- *Timestamp-based prefixes to dodge the sequence entirely.* Rejected by the existing project config (`init-options.json` → `branch_numbering: sequential`) and by user preference.

---

## 7. Stash semantics for `safety.on_dirty_tree: stash`

**Decision**: When `safety.on_dirty_tree` is `stash`, the Lead runs `git stash push -u -m "orchestrate:<runId>"` at startup. The Lead records the stash ref in the in-memory run context (not in `state.json`, because the stash is only meaningful for the active session). On clean exit the Lead runs `git stash pop "stash@{...}"` using the recorded ref. If pop fails (conflict), the Lead **does not auto-resolve**: it prints the stash ref and a recovery hint and exits non-zero. Worktrees do not interact with this stash — `git stash` is bound to the main checkout, which is what we want to protect.

**Rationale**: `git stash` is the standard "I have local changes I want to safely set aside" primitive. Auto-resolving conflicts would violate the principle of doing the least-surprising thing with user changes. Constitution Principle IV's worktree isolation already keeps subagent work away from the main tree, so the stash protects only the small window where the Lead itself runs on the main tree.

**Alternatives considered**:
- *Auto-merge / auto-resolve.* Rejected: too risky.
- *Refuse silently.* Rejected: `refuse` is the explicit default; users who pick `stash` have asked for the auto-stash behaviour.

---

## 8. Squash / merge / rebase mechanics with branch retention

**Decision** (per `merge.strategy`):
- **`squash`** (default): `git checkout <target>`, `git merge --squash <feature-branch>`, `git commit -m "<conventional>"`. Feature branch is left untouched. `last_payload.body.target_commit` records the squash commit SHA.
- **`merge`**: `git checkout <target>`, `git merge --no-ff <feature-branch> -m "<conventional>"`. Merge commit's first parent is target, second is the feature branch tip.
- **`rebase`**: A two-step gate: (a) **validate every commit** on the feature branch against the Conventional Commits regex (a small `sh` validator in `scripts/sh/integrate-feature.sh`); if any commit fails, integration aborts with `phase=merge, status=failed`. (b) `git rebase <feature-branch> --onto <target> <merge-base>` then `git checkout <target>` and `git merge --ff-only <feature-branch>`. The feature branch is reset back to its original tip after the fast-forward so it remains an audit record of the un-rebased history.

For all three: if any step fails (conflict, validation failure), the Lead runs `git merge --abort` / `git rebase --abort` as appropriate, leaves the target branch untouched, and records `phase=merge, status=failed`. Constitution Principle V's commit-hygiene gate is enforced at this step.

**Rationale**: Three strategies, one gate function — keeps the spec's three-way configuration honest while making non-CC commits in `rebase` mode fail closed instead of silently breaking semantic-release. The branch-retention rule from the Q3 clarification is honored across all three.

**Alternatives considered**:
- *Implement only `squash` in v1.* Rejected: the user explicitly revised Q3 to require all three.
- *Skip CC validation in `rebase` mode and trust the Dev subagent.* Rejected: violates Principle V; a single bad commit would break the release pipeline silently.

---

## 9. Extension registration: `extension.yml` + `extensions.yml`

**Decision**: The extension manifest lives at `.specify/extensions/orchestrate/extension.yml` and mirrors the structure of the existing `git` extension manifest. It declares one command (`speckit.orchestrate`) and one config file (`orchestrate-config.yml` from template `config-template.yml`). It registers **no Spec Kit hooks** — the orchestrator does not hook into other Spec Kit commands; it is itself the orchestrator. On install, the user (or an installer script) appends an entry to the root `.specify/extensions.yml` under `installed:` and runs the existing skill-sync to materialise `.claude/skills/speckit-orchestrate/SKILL.md` from `commands/speckit.orchestrate.md`.

**Rationale**: Matching the established extension pattern is the cheapest, most maintainable choice and keeps the user's mental model consistent. Adding hooks elsewhere is unnecessary — the Lead drives Spec Kit commands *as a user would*, by invoking them inside the BA/Dev subagents.

**Alternatives considered**:
- *Hook into `before_specify` etc. to inject orchestrator logic into every Spec Kit command.* Rejected: invasive, fragile, breaks single-feature workflows; not aligned with how the maqa-extension reference works.

---

## 10. Observability resolution (deferred from spec)

**Decision**: A single status-event stream is the v1 observability surface.
- **Format**: one line per state transition, ISO-8601 timestamp, structured key=value pairs. Example: `2026-05-12T14:03:11Z feature=003 phase=ba status=running note=spawned-ba-subagent`.
- **Sinks**: stdout (visible in the Lead session) **and** `.specify/extensions/orchestrate/events.log` (append-only, gitignored).
- **Emitted on**: every `phase` or `status` change; subagent spawn / return; merge commit SHA; clarification request / answer.
- **What we explicitly skip in v1**: progress bars, TUIs, web dashboards, OpenTelemetry exporters, JSON-Lines event format. The text log is `grep`/`awk`-friendly and that's enough.

**Rationale**: Low-cost, ships with the smallest plausible surface area, can be parsed by any downstream tooling. Constitution Principle III (typed persistence) is preserved: this is a log, not a contract.

**Alternatives considered**: JSON-Lines event log (deferred to v2 — adds schema burden for no v1 user value), full progress UI (deferred — out of scope for a developer tool that runs in a terminal session).

---

## 11. Security & privacy resolution (deferred from spec)

**Decision**:
- The state file (`state.json`) and the events log (`events.log`) MAY contain user-typed clarification answers verbatim. Both are created with permissions `0600` (owner read/write only) and the entire `.specify/extensions/orchestrate/` runtime subtree (`state.json`, `events.log`, `lock`, `worktrees/`) is added to `.gitignore` by the installer.
- The `quickstart.md` README documents this clearly: *"Do not paste secrets in clarification answers; they will be persisted to disk and inspectable by anyone with read access to your repo checkout."*
- No automatic redaction in v1. No encryption of the state file. No clarification-answer expiry.

**Rationale**: This is a developer-local tool, not a multi-tenant service. The threat model is "another local user on the same machine reads my checkout" — `0600` + gitignore covers that. Going further (encryption, redaction) is design-by-FUD without a real attacker.

**Alternatives considered**: Regex-based secret scrubbing of payloads (rejected — false-positive prone, false-negative dangerous), per-run encryption key (rejected — operationally complex; user can use full-disk encryption instead).

---

## 12. Subagent hang / timeout resolution (deferred from spec)

**Decision**: No automatic timeout in v1. The user retains the Ctrl-C / kill-session escape hatch. On the next `/speckit-orchestrate` invocation, the Lead reads the state file, finds the half-completed feature with `phase=<X>, status=running`, and re-spawns its subagent — fulfilling the resume path (FR-026). A configurable `timeout.ba_phase_seconds` / `timeout.dev_phase_seconds` is documented as an explicit v2 enhancement in `quickstart.md`.

**Rationale**: LLM workflows have wide latency distributions; a naive timeout would fire spuriously and force unnecessary retries that burn tokens. The persisted-state resume path already covers the legitimate "I killed it because it was hung" recovery flow. Adding a knob nobody asked for fails the constitution's spirit ("don't add features beyond what the task requires").

**Alternatives considered**: Fixed 30-minute per-phase timeout (rejected — too short for real implements, too long for diagnostic value), heartbeat-style liveness ping (rejected — Claude Code subagents return only a final message; there is no heartbeat channel without re-inventing the agent protocol).

---

## 13. Mocked-subagent integration testing approach

**Decision**: Integration tests live in `tests/extensions/orchestrate/integration/`. Each fixture directory contains a `BACKLOG.md`, a `expected-state.json`, and a `replay/` subdirectory of canned JSON payload responses keyed by `(feature_id, phase, invocation_count)`. The `mock-subagent.sh` helper shadows the real `Agent` invocation: when the Lead would normally invoke a BA or Dev subagent, the test harness substitutes `mock-subagent.sh`, which reads the canned response and prints it. This is wired via an `ORCHESTRATE_SUBAGENT_RUNNER` env var the Lead consults at startup; in production it defaults to "real Claude Code".

**Rationale**: Determinism, zero token cost in CI, fast tests. The real LLM workflows are tested manually in dev-loop, not in CI. Constitution Principle III's "JSON contracts" make the boundary mockable for free: payloads in and out are typed.

**Alternatives considered**:
- *Hit real Claude Code in CI.* Rejected: non-deterministic, expensive, requires API keys in CI secrets.
- *Don't write integration tests at all, rely on unit tests.* Rejected: the unit tests cover the helper scripts; the integration tests cover the Lead's state machine, which is where most behavioural bugs will live.

---

## Summary of resolutions

| Topic | Decision in one line |
|-------|----------------------|
| Subagent format | Markdown + YAML frontmatter under `.claude/agents/` (BA, Dev). |
| JSON I/O enforcement | Prompt-level constraint + Lead-side schema validation; non-JSON ⇒ error payload. |
| Clarification pause/resume | Subagent returns + re-spawn with carried context — no long-lived subagents. |
| Worktree layout | `.specify/extensions/orchestrate/worktrees/<id>/`, gitignored, prune on success. |
| JSON tooling | `jq ≥ 1.6` required; abort at startup if missing. |
| ID allocation | Lead-driven, `flock`-serialised, uses existing `create-new-feature.sh`. |
| Dirty-tree stash | `git stash push -u`; pop on clean exit; on conflict print ref + exit non-zero. |
| Merge strategies | `squash` / `merge` / `rebase`; `rebase` validates every commit against CC. |
| Extension registration | Mirror existing `git` extension manifest pattern; no hooks. |
| Observability | One-line key=value status events to stdout + `events.log`. |
| Security | `0600` + gitignore; no redaction or encryption; documented in quickstart. |
| Timeout | None in v1; resume-on-restart is the recovery path. |
| Integration tests | Fixture-driven, canned JSON payloads via `mock-subagent.sh`. |

All **NEEDS CLARIFICATION** markers from `plan.md` Technical Context are now resolved. Ready for Phase 1.
