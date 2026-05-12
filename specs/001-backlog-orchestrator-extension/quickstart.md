# Quickstart: Backlog Orchestrator Extension

**Status**: Phase 1 design output. The commands below describe the **target** user experience; concrete scripts are produced in `/speckit-tasks` and `/speckit-implement`.

## What this extension gives you

You point Claude Code at a `BACKLOG.md` and run one command. The orchestrator splits each backlog item into its own git worktree, drives the full Spec Kit pipeline (`specify` → `clarify` → `plan` → `tasks` → `analyze` → `implement`) per feature, and integrates completed features into your dev branch. You only get prompted when a feature genuinely needs human clarification.

## Prerequisites

Before running `/speckit-orchestrate`, check that:

1. **Spec Kit installed in this repo** with all of: `/speckit-specify`, `/speckit-clarify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze`, `/speckit-implement`. (The Lead drives them via subagents.)
2. **`git` ≥ 2.5** with worktree support: `git --version`.
3. **`jq` ≥ 1.6** for JSON manipulation in the helper scripts:
   - macOS: `brew install jq`
   - Debian/Ubuntu: `sudo apt-get install jq`
   - Alpine: `apk add jq`
   The Lead aborts at startup if `jq` is missing, so install it before your first run.
4. **A configured dev branch** (default name `dev`). The branch must exist locally before the orchestrator tries to merge into it.
5. **A clean main working tree** — or pick a non-`refuse` value for `safety.on_dirty_tree` (see Configuration below).

## Install the extension

> v1 install flow is a single shell step from the repo root. Concrete script name lands in `/speckit-tasks`.

```sh
# Install the orchestrate extension into this repo's .specify/.claude
sh .specify/extensions/orchestrate/install.sh
```

After install:
- `.claude/skills/speckit-orchestrate/SKILL.md` exists.
- `.claude/agents/orchestrate-ba.md` and `.claude/agents/orchestrate-dev.md` exist.
- `.specify/extensions/orchestrate/orchestrate-config.yml` is copied from the template — review and edit if needed.
- `.specify/extensions.yml`'s `installed:` list contains `orchestrate`.
- `.gitignore` gains entries for `state.json`, `events.log`, `lock`, and `worktrees/` under `.specify/extensions/orchestrate/`.

## Write your BACKLOG.md

Top-level checkbox items are features; everything else is ignored. See [`contracts/backlog-grammar.md`](./contracts/backlog-grammar.md) for the full grammar.

```markdown
# Sprint 12 backlog

- [ ] Add user login — Email/password and OAuth2 against Google.
- [ ] Profile page — Display user data and allow avatar upload.
- [ ] Search bar — Header-mounted type-ahead from the product catalogue.
- [x] Onboarding flow — Already shipped; will be skipped automatically.
```

The orchestrator runs **only** on `- [ ]` items; `- [x]` items are skipped.

## Run

From the Claude Code session in this repo:

```
/speckit-orchestrate
```

That's it. The Lead:

1. Reads `BACKLOG.md`, parses items by the grammar, reconciles them against `state.json`.
2. Pre-allocates feature IDs and creates worktrees + branches up to `parallelism.ba` of them.
3. Spawns BA subagents into the prepared worktrees.
4. As BAs complete and pass the configured `ba_gate.strictness`, the Lead spawns Dev subagents (up to `parallelism.dev` of them).
5. On Dev success, the Lead integrates the feature branch into the target branch using `merge.strategy` (default `squash`).
6. Emits a per-feature summary on exit.

You will only be prompted when a BA reaches `/speckit-clarify` or `/speckit-analyze` and needs an answer. The prompt is delivered through the Lead, **tagged with the feature ID**, and other features keep running in parallel while you answer.

### Retry failed features

```
/speckit-orchestrate --retry-failed
```

Every feature with `status=failed` is reset to `phase=ba, status=queued` and `last_payload` cleared. Then the normal run loop proceeds. **Failed features are not retried automatically on a plain re-run** — you have to opt in.

### Resume after interruption

Just re-run `/speckit-orchestrate`. The Lead reads `state.json`, skips terminal features (`phase=done` or `status=failed`), respawns subagents for any `running` features (treating the interrupted phase as restartable), and represents the saved pending clarification to you for any `blocked` features.

## Configuration

Edit `.specify/extensions/orchestrate/orchestrate-config.yml`. All keys have sensible defaults — change only what you need.

```yaml
backlog:
  path: BACKLOG.md            # Where to find the backlog

parallelism:
  ba: 2                       # Concurrent BA subagents (1–16)
  dev: 2                      # Concurrent Dev subagents (1–16)

merge:
  target_branch: dev          # Where to integrate completed features
  strategy: squash            # squash | merge | rebase
                              #   squash : --squash + one CC commit (default)
                              #   merge  : --no-ff merge commit
                              #   rebase : rebase + validate each commit is CC

worktree:
  retain_on_failure: true     # Keep failed-feature worktrees for debugging
  prune_on_success: true      # Remove worktree after successful merge

safety:
  on_dirty_tree: refuse       # refuse | stash | ignore
                              #   refuse : abort if main tree is dirty (default)
                              #   stash  : auto-stash, restore on clean exit
                              #   ignore : YOLO

ba_gate:
  strictness: strict          # strict | trust | severity_based
                              #   strict         : all 4 artifacts on disk + no
                              #                    open clarifications + ba_done
                              #                    payload
                              #   trust          : just the ba_done payload
                              #   severity_based : analyze report has zero
                              #                    CRITICAL/HIGH findings

limits:
  max_features: 200           # Hard cap to prevent runaway runs (1–1000)
```

## Inspect a run

The state file is JSON; just look at it.

```sh
# Summary counters
jq .counters .specify/extensions/orchestrate/state.json

# Status of every feature
jq '.features[] | {id, title: .original_title, phase, status}' .specify/extensions/orchestrate/state.json

# Open clarification questions
jq '.features[] | select(.status=="blocked") | .pending_clarification' \
   .specify/extensions/orchestrate/state.json
```

Or tail the human-readable log:

```sh
tail -f .specify/extensions/orchestrate/events.log
```

## Privacy note

Clarification answers you type are persisted verbatim into `state.json`, which lives under `.specify/extensions/orchestrate/` with file mode `0600` and is gitignored. **Do not paste secrets** (passwords, tokens, PII) into clarification answers — anyone with read access to your checkout can read them. There is no redaction in v1.

## Troubleshooting

| Symptom | Likely cause | Action |
|--------|--------------|--------|
| Lead aborts at startup: "main working tree dirty" | `safety.on_dirty_tree: refuse` (default) and you have uncommitted changes | Commit or stash, or set `safety.on_dirty_tree: stash` |
| Lead aborts at startup: "jq not found" | `jq` not on `PATH` | Install `jq` per the Prerequisites section |
| A feature is stuck in `(ba, blocked)` | BA returned a clarification question; you haven't answered yet | The Lead presents pending questions on its next prompt cycle. Answer it. |
| All Dev subagents stay queued | `ba_gate` rejected every BA result — check `state.json` for `last_payload.body.code` | Investigate the gate violation. Lower `ba_gate.strictness` if appropriate. |
| Merge fails repeatedly with `merge_conflict` | Two features touched the same files | Resolve manually on each feature branch and re-run with `--retry-failed` |
| A feature has `target_commit=null` but `phase=done` | Bug — should be impossible | File an issue; attach `state.json` and the relevant slice of `events.log` |
| A subagent hung and the Lead is unresponsive | No automatic timeout in v1 | `Ctrl-C` the Claude Code session; re-run `/speckit-orchestrate` to resume |

## Limitations (v1)

- **POSIX shell only**. Native Windows shells are unsupported; use WSL.
- **No automatic subagent timeouts**. Manual interruption is the recovery path.
- **No remote push or PR creation**. All integration is local.
- **Single Lead per repo**. Concurrent Leads on the same `BACKLOG.md` are unsafe.
- **No automatic clarification-answer redaction**. The state file is plaintext.

## What's next

- `/speckit-tasks` will convert this plan into concrete, dependency-ordered tasks.
- `/speckit-implement` will execute those tasks (creating the helper scripts, subagent files, skill, and tests).
