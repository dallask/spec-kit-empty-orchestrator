# Phase 1 — Data Model: Backlog Orchestrator Extension

**Branch**: `001-backlog-orchestrator-extension` | **Date**: 2026-05-12
**Inputs**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md)

This document defines every entity the orchestrator persists, exchanges, or computes. Each entity is normative: implementation MUST match the field names, types, and invariants here. JSON Schemas in `contracts/` are the machine-readable form of this model.

---

## Entity index

| Entity | Lifetime | Persistence | Producer | Consumer |
|--------|----------|-------------|----------|----------|
| **BacklogItem** | Per parse | In-memory only | `parse-backlog.sh` | Lead, `reconcile-state.sh` |
| **Feature** | Permanent (across runs) | `state.json` array entry | Lead | Lead, all helpers |
| **OrchestratorState** | Permanent | `state.json` | Lead | Lead, user (via `jq`) |
| **OrchestrateConfig** | Per repo, edited by user | `orchestrate-config.yml` | User | Lead |
| **AgentPayload** | Per message | In-flight only; `last_payload` field in state | Lead, BA, Dev | Lead, BA, Dev |
| **StatusEvent** | Per transition | `events.log` line | Lead | User (`tail`/`grep`) |

---

## 1. BacklogItem

A single feature as parsed from `BACKLOG.md`. **Not persisted** — recomputed on every Lead run and reconciled against `OrchestratorState` by title identity.

**Source**: `BACKLOG.md` top-level checkbox line matching the grammar in [`contracts/backlog-grammar.md`](./contracts/backlog-grammar.md).

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | yes | Text from the start of the item to the first `—` / `--` / ` - ` separator, or the whole item if no separator. **Canonical identity** is this string, lowercased and whitespace-trimmed. |
| `description` | string | yes | Text after the separator. Empty string if the item has no separator. |
| `completed` | boolean | yes | `true` if the original checkbox was `- [x]` / `- [X]`. The Lead skips completed items. |
| `source_line` | integer | yes | 1-based line number in `BACKLOG.md` where the item appears (for error messages). |

**Invariants**:
- Title-after-normalisation MUST be non-empty; an empty title is a parse error.
- Within a single parse, two items with the same normalised title is a parse error (the user must disambiguate).
- Nested content under a checkbox is **not** captured as a separate item; if a deterministic concatenation rule is applied (concatenate indented bullets into `description`), it MUST be applied uniformly and documented in `parse-backlog.sh`.

---

## 2. Feature

The orchestrator's working unit. A `Feature` is created the first time a `BacklogItem` with that title is observed; from then on it persists across runs.

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Zero-padded 3-digit sequential ID matching the existing Spec Kit feature-numbering convention (e.g., `"001"`, `"042"`). Allocated by Lead via `allocate-feature.sh`. Immutable. |
| `title` | string | yes | The canonical (lowercased, trimmed) title used as identity. Immutable. |
| `original_title` | string | yes | The pre-normalisation title text, preserved for display in reports. |
| `description` | string | yes | Latest description text from `BACKLOG.md` at the time of last reconciliation. May be updated when user edits the backlog; the change does NOT trigger re-processing (per Q8). |
| `worktree_path` | string | yes | Absolute path to the worktree. Conventionally `.specify/extensions/orchestrate/worktrees/<id>/`. |
| `branch_name` | string | yes | Feature branch name, e.g., `"003-add-user-auth"`. |
| `spec_file_path` | string | yes | Path to `specs/<id>-<short-name>/spec.md` inside the worktree. |
| `phase` | enum | yes | One of `"ba"`, `"dev"`, `"merge"`, `"done"`. See state machine below. |
| `status` | enum | yes | One of `"queued"`, `"running"`, `"blocked"`, `"failed"`, `"complete"`. |
| `last_payload` | AgentPayload \| null | yes | The most recent JSON payload received from a subagent for this feature, or an error payload from a Lead-side check (e.g., gate failure). `null` only before first activity. |
| `pending_clarification` | object \| null | yes | When `status="blocked"`, the unanswered `ClarificationRequest` body. `null` otherwise. |
| `created_at` | ISO-8601 string | yes | When the feature was first allocated. |
| `updated_at` | ISO-8601 string | yes | Last time any field changed. |
| `target_commit` | string \| null | yes | The squash/merge commit SHA on the target branch once `phase=done`. `null` before merge succeeds. |

**State machine**:

```
                    queued       queued        queued        complete
                      │            │             │              │
  (new feature) ─► [ba/queued] ─► [ba/running] ─► [ba/blocked] ──┐
                      │            │             │              │
                      │            ▼             ▼              ▼
                      │         [ba/running]  [ba/running]   [ba/complete]
                      │            │             │              │
                      │            ▼             ▼              ▼
                      │         [ba/failed]    [ba/...]      [dev/queued]
                      │                                         │
                      │                                         ▼
                      │                                      [dev/running]
                      │                                         │
                      │                                         ├──► [dev/failed]
                      │                                         │
                      │                                         ▼
                      │                                      [dev/complete]
                      │                                         │
                      │                                         ▼
                      │                                      [merge/running]
                      │                                         │
                      │                                         ├──► [merge/failed]
                      │                                         │
                      │                                         ▼
                      │                                      [done/complete]
                      ▼
                  [ba/failed]  ◄── any phase × status=failed is terminal
```

**Allowed transitions** (enforced by Lead's reducer in `orchestrate-common.sh`):

| From `(phase, status)` | To `(phase, status)` | Trigger |
|------------------------|----------------------|---------|
| (—, —) | `(ba, queued)` | New `BacklogItem` reconciled into state |
| `(ba, queued)` | `(ba, running)` | Lead spawns BA subagent |
| `(ba, running)` | `(ba, complete)` | BA returns `result` payload AND BA gate passes |
| `(ba, running)` | `(ba, blocked)` | BA returns `clarification_request` payload |
| `(ba, blocked)` | `(ba, running)` | User answers; Lead re-spawns BA with `clarification_answer` |
| `(ba, running)` | `(ba, failed)` | BA returns `error` payload OR BA gate fails |
| `(ba, complete)` | `(dev, queued)` | Auto-advance after gate pass |
| `(dev, queued)` | `(dev, running)` | Lead spawns Dev subagent |
| `(dev, running)` | `(dev, complete)` | Dev returns `result` payload |
| `(dev, running)` | `(dev, failed)` | Dev returns `error` payload |
| `(dev, complete)` | `(merge, running)` | Lead invokes `integrate-feature.sh` |
| `(merge, running)` | `(done, complete)` | Integration succeeds; `target_commit` recorded |
| `(merge, running)` | `(merge, failed)` | Integration aborts (conflict or non-CC commit) |
| any `failed` | `(ba, queued)` | `--retry-failed` invocation; `last_payload` cleared |
| `(done, complete)` | — | Terminal; never re-processed |

**Invariants**:
- `id` is unique within a state file.
- `title` is unique within a state file (canonical-form comparison).
- `(phase, status)` MUST be in the table above; the reducer rejects any other tuple.
- If `status = "blocked"`, `pending_clarification` is non-null and `phase ∈ {ba}`.
- If `phase = "done"`, `status` MUST be `"complete"` and `target_commit` MUST be non-null.

---

## 3. OrchestratorState

The top-level JSON document persisted at `.specify/extensions/orchestrate/state.json`. Single-writer; the Lead is the only mutator.

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | string | yes | `"1.0"` — bumped on any backwards-incompatible state-file change. |
| `run_id` | string | yes | Stable UUID for the most recent Lead invocation; rotated each `/speckit-orchestrate`. |
| `created_at` | ISO-8601 string | yes | First time state was created. |
| `updated_at` | ISO-8601 string | yes | Last successful write. |
| `config_snapshot` | OrchestrateConfig | yes | Resolved config (defaults + user overrides) at run start. Immutable for the run. |
| `features` | array<Feature> | yes | All features ever observed, ordered by `id` ascending. |
| `counters` | object | yes | `{ "queued": N, "running": N, "blocked": N, "failed": N, "complete": N }` — denormalised for cheap reporting. Recomputed on every write. |
| `events_log_path` | string | yes | Relative path to the human-readable event log (default `events.log`). |

**Invariants**:
- The file is written via temp-file + atomic `mv` (POSIX-portable). Concurrent writers would violate the single-writer assumption and ARE NOT supported.
- `counters` MUST sum to `len(features)`.
- `schema_version` mismatches abort the Lead at startup; users must run a documented migration script before continuing.

---

## 4. OrchestrateConfig

User-editable YAML at `.specify/extensions/orchestrate/orchestrate-config.yml`. The Lead reads this once at startup, fills in defaults, and writes the snapshot into `OrchestratorState.config_snapshot`.

**Keys (all have defaults; users override selectively)**:

| Key | Type | Default | Validation |
|-----|------|---------|------------|
| `backlog.path` | string | `"BACKLOG.md"` | File path relative to repo root. |
| `parallelism.ba` | integer | `2` | `1 ≤ N ≤ 16`. |
| `parallelism.dev` | integer | `2` | `1 ≤ N ≤ 16`. |
| `merge.target_branch` | string | `"dev"` | Must be a non-empty branch name. |
| `merge.strategy` | enum | `"squash"` | `"squash"` \| `"merge"` \| `"rebase"`. |
| `worktree.retain_on_failure` | boolean | `true` | — |
| `worktree.prune_on_success` | boolean | `true` | — |
| `safety.on_dirty_tree` | enum | `"refuse"` | `"refuse"` \| `"stash"` \| `"ignore"`. |
| `ba_gate.strictness` | enum | `"strict"` | `"strict"` \| `"trust"` \| `"severity_based"`. |
| `limits.max_features` | integer | `200` | `1 ≤ N ≤ 1000`. Hard cap for runaway protection. |

**Invariants**:
- Unknown keys at the top of the tree are a soft error (warning only — to keep forward compatibility with config additions).
- Type-invalid values abort the Lead at startup with the offending key path.

---

## 5. AgentPayload

The single JSON envelope all Lead↔subagent messages MUST conform to. The schema is in [`contracts/agent-payload.schema.json`](./contracts/agent-payload.schema.json).

**Common envelope fields** (every payload):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | string | yes | `"1.0"`. Bumped on any breaking change. |
| `feature_id` | string | yes | The Feature this payload concerns. |
| `agent_role` | enum | yes | `"lead"` \| `"ba"` \| `"dev"`. |
| `phase` | enum | yes | `"ba"` \| `"dev"` \| `"merge"`. Reflects the producer's current phase. |
| `payload_type` | enum | yes | See table below. |
| `body` | object | yes | Type-specific contents (see subtypes). |
| `timestamp` | ISO-8601 string | yes | UTC. |
| `correlation_id` | string | no | Optional ID for matching a request to its later answer (e.g., `clarification_request` ↔ `clarification_answer`). |

**Payload subtypes** (`body` shape varies per `payload_type`):

| `payload_type` | Direction | `body` shape (informal) | Lead state effect |
|----------------|-----------|--------------------------|--------------------|
| `assignment` | Lead → subagent | `{ feature: Feature, worktree_path, config_snapshot, retry_with?: ClarificationAnswer }` | none — outbound |
| `progress` | subagent → Lead | `{ note: string, step: string }` | Optional log; no state change unless emitted. |
| `result` | subagent → Lead | `{ artifacts: { spec, plan, tasks, analyze }, ba_done?: true, dev_done?: true }` | Advances state through the success transition for the producer's phase. |
| `clarification_request` | BA → Lead | `{ question: string, context: string, options?: string[] }` | `(ba, running) → (ba, blocked)`; `pending_clarification` set. |
| `clarification_answer` | Lead → BA | `{ answer: string, original_question: string }` | Carried via `assignment.retry_with`; on re-spawn, BA transitions `(ba, blocked) → (ba, running)`. |
| `error` | subagent → Lead | `{ code: string, message: string, recoverable: boolean, details?: object }` | Advances state to `(producer_phase, failed)`. |

**Invariants**:
- The schema validator rejects unknown `payload_type` values and any envelope missing a required field. Validation failures from a subagent result are treated as an `error` payload from Lead's perspective (FR-017).
- `clarification_request` MUST set `correlation_id`; the matching `clarification_answer` MUST echo the same value.
- `result` from a BA MUST carry `ba_done: true` for the strict gate; `severity_based` mode requires an `analyze` artifact with a parseable severity field.

---

## 6. StatusEvent

A single line in `events.log` (also echoed to stdout). Not a JSON payload — a plaintext log line for human + `grep` consumption.

**Format**:
```
<ISO-8601-UTC> feature=<id> phase=<phase> status=<status> note=<short-quoted-string>
```

**Examples**:
```
2026-05-12T14:00:01Z feature=- phase=- status=- note="run start; backlog=5 items config=defaults"
2026-05-12T14:00:03Z feature=001 phase=ba status=queued note="allocated; worktree=.../worktrees/001"
2026-05-12T14:00:05Z feature=001 phase=ba status=running note="ba subagent spawned"
2026-05-12T14:03:11Z feature=001 phase=ba status=blocked note="clarification needed: <truncated>"
2026-05-12T14:05:42Z feature=001 phase=ba status=running note="resumed with clarification answer"
2026-05-12T14:10:08Z feature=001 phase=ba status=complete note="ba_gate=strict passed"
2026-05-12T14:18:30Z feature=001 phase=dev status=complete note="dev_done=true"
2026-05-12T14:18:32Z feature=001 phase=merge status=running note="strategy=squash target=dev"
2026-05-12T14:18:34Z feature=001 phase=done status=complete note="target_commit=ab12cd3"
2026-05-12T14:25:00Z feature=- phase=- status=- note="run end; summary={complete:4 failed:1}"
```

**Rules**:
- One line per state transition, plus run-start / run-end markers.
- `note` is single-quoted-and-truncated to ≤ 200 chars (events.log is not a payload archive).
- Run-level events use `feature=-` `phase=-` `status=-` placeholders for grep-friendly columnar layout.
- The events log is append-only; the Lead never rewrites past lines.

---

## Relationships

```
BACKLOG.md  ──parse──►  BacklogItem[]
                            │ (title identity)
                            ▼
            reconcile-state.sh  ◄──read──  state.json
                            │
                            ▼
                        Feature[]  ◄── created or matched
                            │
                            ▼
            (per-feature lifecycle drives every other entity)
                            │
                            ├──► AgentPayload (Lead ↔ subagents)
                            ├──► StatusEvent (per transition)
                            └──► OrchestratorState (atomic persist)
```

---

## What is *not* in the data model (deliberate omissions)

- **User accounts / multi-tenancy**: single-user developer tool.
- **Database schema**: state is a single JSON file; no SQLite, no Postgres.
- **Network resources**: the orchestrator does not push, does not call GitHub APIs, does not contact a remote service.
- **A `BacklogChange` audit entity**: description edits are intentionally not tracked (per Q8 — they don't trigger re-processing); no need to audit them.
- **Per-subagent metrics** (token counts, latency): out of scope for v1; the events log captures coarse timing.

This is enough to drive the contracts and quickstart with no remaining ambiguity.
