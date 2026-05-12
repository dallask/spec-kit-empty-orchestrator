---
name: speckit-orchestrate
description: Drive every BACKLOG.md item through the Spec Kit pipeline using BA + Dev subagents in isolated worktrees.
compatibility: Requires Spec Kit ≥ 0.8 with /speckit-specify ... /speckit-implement installed, git ≥ 2.5, jq ≥ 1.6.
metadata:
  author: spec-kit-empty-orchestrator
  source: orchestrate:commands/speckit.orchestrate.md
---

# /speckit-orchestrate — Backlog Orchestrator Lead

You are the **Lead** in a hub-and-spoke orchestrator. The user has invoked `/speckit-orchestrate`. Your job is to drive `BACKLOG.md` through the full Spec Kit pipeline by delegating to two subagents — `orchestrate-ba` and `orchestrate-dev` — and persisting state across runs.

You are the **only delegator**. Subagents do not spawn subagents. All Lead↔subagent communication is structured JSON validated against `agent-payload.schema.json`.

## User Input

```text
$ARGUMENTS
```

If the user typed `/speckit-orchestrate --retry-failed`, set `RETRY_FAILED=true`. Otherwise `RETRY_FAILED=false`. The flag has no value — its presence is the signal.

## Where things live

Resolve repo-relative paths to absolute paths before running any helper:

- Extension root: `.specify/extensions/orchestrate/`
- Helpers: `.specify/extensions/orchestrate/scripts/sh/`
- Config: `.specify/extensions/orchestrate/orchestrate-config.yml`
- State: `.specify/extensions/orchestrate/state.json`
- Events log: `.specify/extensions/orchestrate/events.log`
- Worktrees: `.specify/extensions/orchestrate/worktrees/<feature_id>/`
- Schemas: `.specify/extensions/orchestrate/schemas/agent-payload.schema.json` etc.

## Playbook

Execute these steps in order. Use the `Bash` tool to run helpers, the `Agent` tool to spawn subagents, and `AskUserQuestion` to surface clarification questions. Update `state.json` after every state transition by piping the new candidate JSON to `scripts/sh/state-write.sh`.

### Step 1 — Load and snapshot the config

Run:

```sh
.specify/extensions/orchestrate/scripts/sh/config-load.sh
```

(See T037 — it merges defaults from `config-template.yml` with the user's `orchestrate-config.yml` and emits resolved config as JSON to stdout.)

Stash the resolved config object in your working memory and into the in-flight state as `config_snapshot`. The fields you reference throughout: `safety.on_dirty_tree`, `parallelism.ba`, `parallelism.dev`, `merge.target_branch`, `merge.strategy`, `ba_gate.strictness`, `worktree.retain_on_failure`, `worktree.prune_on_success`, `limits.max_features`.

Emit event:

```sh
.specify/extensions/orchestrate/scripts/sh/emit-event.sh - - - "run start"
```

### Step 2 — Safety check

Run safety-check.sh with the configured mode:

```sh
.specify/extensions/orchestrate/scripts/sh/safety-check.sh "$ON_DIRTY_TREE" "$RUN_ID"
```

- If the script exits non-zero: STOP. Show the user the JSON it printed. Do not proceed.
- If `status="stashed"`: remember the `stash_ref` in working memory for step 10.

### Step 3 — Parse backlog

```sh
.specify/extensions/orchestrate/scripts/sh/parse-backlog.sh BACKLOG.md
```

- Exit 0 + empty array `[]` → no items to process. Skip to step 10 (summary + exit clean).
- Exit 2 (`duplicate_title`) or exit 3 (`empty_title`) → surface the JSON error to the user and stop. Do not modify state.
- Enforce the `limits.max_features` cap. If the parsed array length exceeds it: stop with a clear error.

### Step 4 — Reconcile state

```sh
parse-backlog.sh BACKLOG.md | reconcile-state.sh | state-write.sh
```

Identity is by canonical title (Q8). New items append as `(phase=ba, status=queued)`; existing items keep their phase/status; removed items remain historical. Persist via `state-write.sh`.

### Step 5 — `--retry-failed` (optional)

If `RETRY_FAILED=true`:

```sh
.specify/extensions/orchestrate/scripts/sh/retry-failed.sh
```

This script resets every `status=failed` feature back to `(phase=ba, status=queued)` and clears `last_payload`.

### Step 6 — Resume preamble

Read the current state. For every feature with a non-terminal `(phase, status)`:

1. If `phase ∈ {ba, dev}` and `status ∈ {queued, running}`:
   - Validate its worktree via `worktree-validate.sh <feature_id>` (T033).
   - On hit: set `status=queued` (treat any prior `running` as interrupted/restartable).
   - On miss: mark `(phase=ba, status=failed)` with payload `{code:"worktree_missing", recoverable:true}`.

2. If `(phase=ba, status=blocked)`:
   - Restore the saved `pending_clarification` to the in-memory queue (step 7 handles UI).

3. If `(phase=merge, status=running)` — **mid-merge crash recovery (T034 (d))**:
   - If the feature record has a non-null `target_commit`: advance straight to `(phase=done, status=complete)` and skip integration — the merge succeeded; only the state-persist crashed.
   - Else: queue the feature for a re-attempt at step 9's integration.

Persist after every change.

### Step 7 — Drain pending clarifications

Before launching any new work, surface any features in `(ba, blocked)` to the user via `AskUserQuestion`. Use the helper for ordering and bookkeeping:

```sh
# Peek the next blocked feature (returns null if none).
.specify/extensions/orchestrate/scripts/sh/clarification-queue.sh peek
```

The helper returns features in feature-id ascending order (FR-014). For each peeked feature:

1. Surface the question through `AskUserQuestion`. The question text is `pending_clarification.question`; include the feature ID and `original_title` in the prompt header so the user knows which feature they're answering. If `pending_clarification.options[]` is non-empty, present them as discrete options (still allow free-form via the standard "Other" affordance).
2. After the user answers, call:

   ```sh
   .specify/extensions/orchestrate/scripts/sh/clarification-queue.sh dequeue "<feature_id>" "<the user's answer>"
   ```

   The helper:
   - Emits a `clarification_answer` body JSON to stdout (carrying the saved `correlation_id` and the original question text).
   - Persists the state transition `(ba, blocked) → (ba, running)` and clears `pending_clarification`.

3. Take the JSON the helper emitted and attach it as `retry_with` in the BA's next `assignment` payload, then re-spawn the BA via the same code path as step 8a (with `body.retry_with` populated).

Repeat until `clarification-queue.sh peek` returns `null`. Only then proceed to step 8.

### Step 8 — Main scheduler loop

Loop until no feature has `status ∈ {queued, running, blocked}`:

#### 8a. Promote BA work

Find features in `(phase=ba, status=queued)`. Up to `parallelism.ba` of them (counting any already `running`):

For each:

1. If `worktree_path` is empty: call `allocate-feature.sh "<original_title>" "<description>"` → get `{id, branch_name, spec_dir, short_name}`. Update the record's `id`, `branch_name`, `spec_file_path` (= `<spec_dir>/spec.md`).
2. If `worktree_path` is empty: call `create-worktree.sh "<id>" "<branch_name>"` → get `{worktree_path}`. Update the record.
3. Persist state.
4. Build an `assignment` payload:

   ```json
   {
     "schema_version": "1.0",
     "feature_id": "<id>",
     "agent_role": "lead",
     "phase": "ba",
     "payload_type": "assignment",
     "timestamp": "<iso>",
     "body": {
       "feature_summary": {"id": "<id>", "title": "<canonical>", "description": "<text>"},
       "worktree_path": "<abs path>",
       "config_snapshot": <the resolved config>,
       "retry_with": <only if resuming after clarification — else omit>
     }
   }
   ```

5. Spawn the BA subagent:

   ```
   Agent(subagent_type="orchestrate-ba", description="BA for feature <id>", prompt="<the JSON above as text>")
   ```

6. Transition `(ba, queued) → (ba, running)`. Emit event. Persist state.

#### 8b. Handle BA returns (validate, gate, advance)

When a spawned BA returns, the `Agent` tool result is the subagent's final message. **Validate it against `schemas/agent-payload.schema.json`** (use `jq` with a shape check or just parse the JSON and verify the required envelope fields).

If validation fails: synthesise an `error` payload with `code=subagent_invalid_json`, attach to `last_payload`, transition `(ba, running) → (ba, failed)`.

Otherwise dispatch on `payload_type`:

| payload_type | Action |
|--------------|--------|
| `result` | Save to `last_payload`. Run `ba-gate-check.sh "<strictness>"` piping the feature record. On pass: `(ba, running) → (ba, complete) → (dev, queued)`. On fail: `(ba, running) → (ba, failed)` with the gate's error payload. |
| `clarification_request` | Save to `last_payload`. Pipe `body` to `clarification-queue.sh enqueue "<feature_id>"` (which persists `pending_clarification` + transitions `(ba, running) → (ba, blocked)`). After this loop iteration, control returns to step 7. |
| `error` | Save to `last_payload`. Transition `(ba, running) → (ba, failed)`. |
| `progress` | Log the note via `emit-event.sh`; do not transition state. |
| anything else | Treat as `subagent_invalid_json`. |

Emit event for every transition. Persist state after every transition.

#### 8c. Promote Dev work

Find features in `(phase=dev, status=queued)`. Up to `parallelism.dev` of them:

For each:

1. Build an `assignment` payload (agent_role="lead", phase="dev", body.feature_summary + worktree_path + config_snapshot).
2. Spawn the Dev subagent:

   ```
   Agent(subagent_type="orchestrate-dev", description="Dev for feature <id>", prompt="<JSON>")
   ```

3. Transition `(dev, queued) → (dev, running)`. Emit event. Persist state.

#### 8d. Handle Dev returns

Validate the returned message exactly as in 8b. On success:

| payload_type | Action |
|--------------|--------|
| `result` with `dev_done=true` | `(dev, running) → (dev, complete) → (merge, running)`. Drop into 8e. |
| `error` | `(dev, running) → (dev, failed)`. Emit event. Do not integrate. |
| anything else | Treat as `subagent_invalid_json` → `(dev, running) → (dev, failed)`. |

#### 8e. Integrate a feature

For each `(phase=merge, status=running)`:

```sh
.specify/extensions/orchestrate/scripts/sh/integrate-feature.sh \
    "<branch_name>" "<target_branch>" "<strategy>" "<original_title>"
```

On stdout (`status="merged"`):
1. Record `target_commit` from the JSON on the feature.
2. **If `config_snapshot.worktree.prune_on_success === true`** (the default): run
   ```
   git worktree remove "<worktree_path>" && git worktree prune
   ```
   to clean up the per-feature worktree (per FR-006 / C1 remediation).
3. Transition `(merge, running) → (done, complete)`. Emit event. Persist.

On stderr (errorBody with `code` in `{merge_conflict, cc_violation, ...}`):
1. Save the error payload to `last_payload`.
2. Leave the feature branch and worktree untouched.
3. Transition `(merge, running) → (merge, failed)`. Emit event. Persist.

### Step 9 — Repeat scheduler until drained

Loop step 8 until: no feature has `status ∈ {queued, running, blocked}` AND there are no in-flight subagents. Then drop to step 10.

### Step 10 — Stop & summarise

1. Call:

   ```sh
   .specify/extensions/orchestrate/scripts/sh/summary-report.sh
   ```

   (See T040.) Display its Markdown table output to the user.

2. **Stash recovery** (per FR-023a + C4 remediation): if step 2 emitted a `stash_ref`, run:

   ```sh
   .specify/extensions/orchestrate/scripts/sh/safety-check.sh --pop "<stash_ref>"
   ```

   - On `status="popped"`: clean exit, return success.
   - On `status="pop_conflict"`: surface the JSON to the user via an informational `AskUserQuestion` (the only choice is acknowledgement) and exit non-zero.

3. Emit run-end event:

   ```sh
   .specify/extensions/orchestrate/scripts/sh/emit-event.sh - - - "run end"
   ```

## Failure handling

- If any helper script returns an unexpected non-zero exit, capture its stderr, synthesise a Lead-side error payload `{code:"helper_failed", message:"<name>: <stderr>", recoverable:false}`, attach to the relevant feature's `last_payload` (or omit feature scope if it's run-level), persist state, and stop the run.
- NEVER attempt destructive recovery (force-push, branch deletion, force-clean worktree) on the user's behalf.

## What this Skill does NOT do

- Does not run BA pipeline phases itself — they belong to the BA subagent.
- Does not run `/speckit-implement` itself — it belongs to the Dev subagent.
- Does not push to a remote, open PRs, or touch GitHub.
- Does not modify `BACKLOG.md` — the user owns it.
