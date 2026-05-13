# Quickstart: Sandbox Testing for Orchestrator Extension

**Status**: Phase 1 design output. Concrete scripts ship via `/speckit-tasks` and `/speckit-implement`.

## What this feature gives you

You point Claude Code at the orchestrator's repo, run one slash command, and end up with a `.sandbox/` directory containing a real git repository with the orchestrator extension installed, a curated 3-item `BACKLOG.md`, and a `dev` branch — ready to run `/speckit-orchestrate` end-to-end against. Another slash command wipes the entire sandbox when you're done.

The sandbox is intentionally byte-for-byte faithful to your current working tree: it copies `.specify/` and `.claude/` from your host repo wholesale, so any in-progress orchestrator change you're debugging is the version running inside the sandbox.

## Prerequisites

You already have these if you can run `/speckit-orchestrate` on the host:

1. **`git`** ≥ 2.5.
2. **`jq`** ≥ 1.6 — required by the orchestrator inside the sandbox (not by the sandbox commands themselves).
3. **POSIX `sh`** (every modern macOS / Linux ships this; Windows users need WSL2).
4. **`realpath`** is preferred for cleanup's path-safety check, but a POSIX `pwd -P` fallback handles older systems.

The sandbox commands abort with a named missing dependency before creating any partial state (FR-017).

## Use

From the orchestrator project's repo root in a Claude Code session:

```text
/speckit-sandbox-prepare
```

Prints `sandbox: prepared at .sandbox/`. Your repository now has:

- `.sandbox/` — fresh git repo on branch `main`, with `dev` branch created from the initial commit.
- `.sandbox/BACKLOG.md` — the canonical 3-item sample (see [contracts/sample-backlog.template.md](./contracts/sample-backlog.template.md)).
- `.sandbox/.specify/` and `.sandbox/.claude/` — exact copies of your host's trees.
- `<repo-root>/.gitignore` — an entry `.sandbox/` added if it wasn't already there.

Now run the orchestrator inside the sandbox:

```text
cd .sandbox/
```

Then in Claude Code:

```text
/speckit-orchestrate
```

You'll see:
- Item 1 (Pi calculator) progress all the way through `(phase=done, status=complete)`.
- Item 2 (notifications) pause in `(status=blocked)` with a clarification question presented through the Lead. Answer it or interrupt; either way the orchestrator's clarification fan-in/out path is exercised.
- Item 3 (scaffolding `- [x]`) skipped, observable in the orchestrator's final summary.

### Iterate fast

Each debug iteration is two commands:

```text
/speckit-sandbox-prepare           # wipes any prior sandbox, recreates a fresh one
# (cd .sandbox/ and exercise)
/speckit-sandbox-cleanup           # wipes the sandbox
```

Re-prepare auto-wipes the existing sandbox (FR-013). If you want to inspect a sandbox before wiping it, copy `.sandbox/` aside manually first — there is no built-in archive (per the Assumptions section of the spec).

### When you stop debugging

```text
/speckit-sandbox-cleanup
```

Prints `sandbox: removed .sandbox/` (or `sandbox: nothing to clean.` if there was no sandbox). The host repository's working tree and git index are unchanged from before you ran prepare, except for the `.gitignore` entry (which is one-way — cleanup does not remove it; FR-005).

## Locked sandbox

If an orchestrator session is actively running against the sandbox (or crashed without cleanup), `<repo-root>/.sandbox/.specify/extensions/orchestrate/lock` exists. In that case:

- `/speckit-sandbox-prepare` **refuses** and tells you to stop the Lead session first.
- `/speckit-sandbox-cleanup` **proceeds anyway** (FR-016) — cleanup is your escape hatch. Use it to recover from a wedged orchestrator session.

## Inspecting a sandbox run

Same tools as a real orchestrator run; just point them inside `.sandbox/`:

```sh
jq .counters .sandbox/.specify/extensions/orchestrate/state.json
jq '.features[] | {id, title, phase, status}' .sandbox/.specify/extensions/orchestrate/state.json
tail -f .sandbox/.specify/extensions/orchestrate/events.log
```

## Cleanup safety

`/speckit-sandbox-cleanup` will not delete anything outside `<repo-root>/.sandbox/`. Specifically:

- It resolves `.sandbox/` to its canonical absolute path via `realpath` and string-compares it against `<repo-root>/.sandbox/`. If they don't match (e.g., `.sandbox/` is a symlink to `/home/you/projects`), cleanup refuses non-zero and prints the offending path.
- It runs from outside `.sandbox/` — never `cd`-ing into it before deletion.
- It uses `rm -rf -- "$path"` with explicit `--` to defeat leading-dash filename attacks.
- `set -u` at script top catches uninitialized variables that could expand to empty.

See [research.md §4](./research.md) for the full safety design.

## Limitations (v1)

- **One sandbox per host repo** at `.sandbox/`. No alternate paths.
- **No archive/quarantine before cleanup**. Copy `.sandbox/` aside manually if you want a forensic copy.
- **Sample backlog is fixed** (one happy, one clarify, one skip). Failure-injection scenarios (Dev failure, merge conflict) are explicitly out of scope for v1; hand-edit `.sandbox/BACKLOG.md` between prepare and orchestrate if you want to test those.
- **POSIX shell only**. Native Windows shells unsupported; use WSL2.
- **No automatic resume of a partially-prepared sandbox** after a prepare crash. Re-running prepare wipes whatever's there and starts fresh.

## What's next

- `/speckit-tasks` converts this plan into dependency-ordered tasks.
- `/speckit-implement` creates the two `SKILL.md` files, the two `.sh` scripts, the asset, the three test files, and the updates to `extension.yml` + `install.sh`.
