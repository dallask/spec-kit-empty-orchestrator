# Phase 0 Research: Sandbox Testing for Orchestrator Extension

**Plan**: [plan.md](./plan.md) — Phase 0 (Outline & Research)
**Date**: 2026-05-13

This document resolves every uncertainty surfaced in the Technical Context that, if left implicit, could push back into rework during implementation. Five questions are addressed below; each lands on a single concrete Decision, a Rationale, and the Alternatives that were explicitly rejected.

---

## §1 — Sandbox seeding strategy

**Question**: How should the sandbox at `.sandbox/` be populated so the orchestrator inside it sees the *same* Spec Kit core, the *same* slash commands, and the *same* orchestrator source code that the host repository is currently running? Two approaches compete: (a) copy the host's `.specify/` + `.claude/` trees wholesale, or (b) run a fresh `specify init` inside the sandbox and then install the orchestrator extension from the host.

**Decision**: **Copy the host's `.specify/` and `.claude/` directories wholesale into the sandbox, then run the orchestrator's existing `.specify/extensions/orchestrate/install.sh` inside the sandbox to refresh the runtime files.**

Concretely, `sandbox-prepare.sh` performs (in order):

1. `mkdir -p .sandbox && cd .sandbox`
2. `git init --quiet && git checkout -b main --quiet` (orient on `main` then add `dev` later)
3. `cp -R "$REPO_ROOT/.specify" .specify/` — full tree.
4. `cp -R "$REPO_ROOT/.claude" .claude/` — full tree.
5. Delete sandbox-internal runtime debris that may have hitchhiked: `rm -f .specify/extensions/orchestrate/state.json .specify/extensions/orchestrate/events.log .specify/extensions/orchestrate/lock`; `rm -rf .specify/extensions/orchestrate/worktrees/*`. The host's working state is irrelevant to a fresh sandbox.
6. `cp "$REPO_ROOT/.specify/extensions/orchestrate/assets/sandbox-backlog.md" BACKLOG.md`.
7. `sh .specify/extensions/orchestrate/install.sh` — re-runs the install entry point inside the sandbox. Per FR-008 this is the same entry point a real end-user invokes, so install regressions surface in sandbox runs.
8. `git add -A && git -c user.email=sandbox@local -c user.name=Sandbox commit -m "chore(sandbox): initial sandbox state" --quiet`. The `-c` inline identities avoid leaning on the maintainer's global git config (which may be absent in CI / fresh checkouts).
9. `git checkout -b dev --quiet` (creates the dev branch from the initial commit, matching the orchestrator's `merge.target_branch` default — FR-009).
10. `git checkout main --quiet` (leave the sandbox on `main` so the orchestrator can pre-allocate `001-*`, `002-*` feature branches off `main` and merge into `dev`).

**Rationale**:
- **Byte-for-byte fidelity** with the host's current working tree is what makes the sandbox a useful debug environment. If the maintainer is debugging a half-finished change to `parse-backlog.sh`, they want the *same* `parse-backlog.sh` running inside the sandbox — not a pristine pre-edit version.
- **`install.sh` is reused as required by FR-008**, so any regression in the install entry point fails sandbox prepare visibly. Running install.sh after the copy is idempotent (the script checks for existing files), so the double-step is safe.
- **No network dependency**: the sandbox can be prepared offline. `specify init` would require either a network call or a vendored copy of Spec Kit — the host's `.specify/` already *is* the vendored copy.
- **Trivial to reason about cleanup safety**: prepare's footprint is exactly `.sandbox/` + one line in the host's `.gitignore`. Nothing else on the host is touched.

**Alternatives rejected**:
- **`specify init` inside the sandbox**: would not reflect the maintainer's in-progress changes to the orchestrator (the whole point of the sandbox is to debug those). Also brings external version dependency.
- **`git clone --local` of the host repo into `.sandbox/`**: copies the host's full git history into the sandbox, which is unnecessary (the sandbox needs a fresh git history so the orchestrator inside it can create its own feature branches without colliding with the host's `001-*`, `002-*`, `003-*` history) and bloats the sandbox.
- **Symlinks (`.sandbox/.specify -> ../.specify`)**: would entangle the host's runtime state (`state.json`, `events.log`, `worktrees/`) with the sandbox's. Symlinks also break cleanup-safety guarantees in subtle ways (cleaning the sandbox could `rm -rf` the host through a symlink). Hard no.

---

## §2 — Sample `BACKLOG.md` content design

**Question**: The clarification session locked the sample to exactly three items (happy-path, clarification-needed, already-complete). What exact item titles and descriptions deterministically produce the observed orchestrator behaviors?

**Decision**: Ship the following 3-item sample, versioned as `.specify/extensions/orchestrate/assets/sandbox-backlog.md`:

```markdown
# Sandbox Debug Backlog

This is the canonical sample backlog used by the sandbox test environment.
The orchestrator should process exactly three items: one completes cleanly,
one pauses for clarification, and one is skipped because it is already
checked.

- [ ] Add Pi calculator — Implement a CLI command `pi` that prints the value of mathematical pi truncated to four decimal places (3.1415) on stdout and exits 0. No flags, no input.
- [ ] Add notifications — Wire up notifications.
- [x] Setup project scaffolding — Already shipped in the initial commit; the orchestrator must skip this item.
```

**Rationale**:
- **Item 1 (happy-path)** is *over-specified on purpose*. The description names the exact command (`pi`), the exact output (`3.1415`), the exit code (`0`), and explicitly states "no flags, no input". An LLM running `/speckit-clarify` finds no scope-significant ambiguity to question, so the BA pipeline proceeds straight through. The implementation is trivial (a one-line `printf "3.1415\n"`-equivalent), so Dev cannot get stuck either.
- **Item 2 (clarification-needed)** is *deliberately under-specified*. "Wire up notifications" carries every clarification trigger in the book: which channel (email/push/in-app)? which events? which users? recipient management? `/speckit-clarify` reliably surfaces at least one scope-significant question, and the BA pauses in `(status=blocked)`.
- **Item 3 (already-complete)** uses the `- [x]` checkbox so the orchestrator's `FR-003a` skip-on-checked code path is exercised. The description ("Already shipped in the initial commit") is human-readable and reminds the maintainer this is intentional.
- **Title styles avoid `fix:` prefix** so the orchestrator's commit-message generator (feature `001` FR-020) defaults to `feat:` and the sandbox exercises that default path. A future test can swap one title for a `fix:`-prefixed variant to exercise the `fix:` branch.

**Alternatives rejected**:
- **Generative samples (different content each prepare)**: breaks SC-003 (re-running prepare must produce identical sandbox state) and makes test assertions impossible.
- **Items with intentionally fragile descriptions ("add foo, but only sometimes")**: too easy for LLM nondeterminism to flip happy→clarification or vice versa. Over-specification is safer than cleverness.
- **5+ items including failure-injection (Dev failure, merge conflict)**: explicitly out of scope per the clarification session — deferred to a later iteration.

---

## §3 — Sandbox lock signal source

**Question**: FR-014 says prepare must refuse to recreate the sandbox when an orchestrator Lead is actively running against it. What file signals "Lead is running"?

**Decision**: **The presence of `.sandbox/.specify/extensions/orchestrate/lock`**. This file is created by the orchestrator's `state-write.sh` at Lead startup (feature `001`'s contract) and removed at clean exit. If it exists, an orchestrator session either *is* running or crashed without cleanup.

`sandbox-prepare.sh` checks for it before doing anything destructive:

```sh
LOCK="$REPO_ROOT/.sandbox/.specify/extensions/orchestrate/lock"
if [ -e "$LOCK" ]; then
    printf 'sandbox-prepare: refusing to recreate — lock file exists: %s\n' "$LOCK" >&2
    printf 'sandbox-prepare: stop the active /speckit-orchestrate session, then re-run.\n' >&2
    exit 2
fi
```

`sandbox-cleanup.sh` deliberately **does not** check the lock — per FR-016 cleanup removes the sandbox regardless of internal state. Cleanup is the maintainer's escape hatch when an orchestrator session is wedged; making it refuse on a stale lock would create a deadlock where the maintainer can't recover.

**Rationale**:
- The lock file is a contract feature `001` already owns. Reusing it costs nothing and keeps the sandbox commands ignorant of orchestrator internals beyond the documented signal.
- Stale locks after a crash should not block cleanup; they *should* block re-prepare, so the maintainer is forced to investigate before erasing forensic state.

**Alternatives rejected**:
- **`pgrep` for an orchestrator process**: brittle across shells and PID-namespace boundaries (Docker, WSL), and doesn't survive a process crash that leaves stale state on disk.
- **Reading `state.json` and checking `counters.active_workers > 0`**: requires parsing JSON in `sh` (or a `jq` dep just for sandbox commands). The lock file is a one-bit signal that needs no parsing.

---

## §4 — Cleanup path-safety verification

**Question**: FR-007 and SC-005 require cleanup to never delete anything outside `<repo-root>/.sandbox/`. How does `sandbox-cleanup.sh` *prove* its target is safe before `rm -rf`?

**Decision**: **Resolve both the host repo root and the sandbox path with `realpath -- ...` (or POSIX fallback) and compare strings. Refuse if they don't match exactly.**

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)" || \
    err "not inside a git working tree"
SANDBOX="$REPO_ROOT/.sandbox"
[ -d "$SANDBOX" ] || { say "nothing to clean."; exit 0; }
# Resolve to canonical absolute path, following any symlinks.
SANDBOX_REAL="$(realpath -- "$SANDBOX" 2>/dev/null || \
    cd "$SANDBOX" && pwd -P)" || err "cannot resolve sandbox path"
EXPECTED="$REPO_ROOT/.sandbox"
EXPECTED_REAL="$(cd "$REPO_ROOT" && pwd -P)/.sandbox"
case "$SANDBOX_REAL" in
    "$EXPECTED_REAL") : ;;  # OK
    *) err "refusing to delete: $SANDBOX resolved to $SANDBOX_REAL, expected $EXPECTED_REAL" ;;
esac
rm -rf -- "$SANDBOX_REAL"
```

Two layers of defense:
1. **Path resolution**: `realpath` (or `cd ... && pwd -P` as POSIX fallback) follows symlinks and `..` traversal to a canonical form, so a `.sandbox` that is a symlink to `/` or `/home/user` is caught.
2. **String comparison**: the resolved path must equal the canonical `<repo-root>/.sandbox`. Even one byte off → refuse.

Additional defenses:
- `set -u` at script top — catches uninitialized variables that could expand to empty.
- Always `rm -rf -- "$path"` with `--` to defeat any leading-dash filename attacks.
- Cleanup MUST be invoked from `sh` only; the SKILL.md instructs Claude Code to run the helper via the bash tool, never a direct `rm` from the prompt.

**Rationale**:
- The single biggest risk in this feature is a cleanup script that misinterprets its target and deletes the host. Defense-in-depth (resolve + compare + `--` + `set -u`) keeps the blast radius bounded to `.sandbox/` even under adversarial input.
- `realpath` is POSIX-2024 and present on modern Linux distros and macOS (since Catalina). The `cd ... && pwd -P` fallback covers older systems.

**Alternatives rejected**:
- **`rm -rf .sandbox/` from the repo root without resolution**: a `.sandbox` symlink to `/` deletes the host's filesystem. Unacceptable.
- **`find .sandbox/ -mindepth 1 -delete` then `rmdir .sandbox`**: still vulnerable to symlinks unless paired with `realpath`. No advantage over `rm -rf` once resolution is correct.
- **Refuse to operate if `.sandbox/` is a symlink at all**: cleaner in spirit but contradicts FR-016 (cleanup removes the sandbox regardless of internal state). A user who manually created `.sandbox/` as a symlink has done something weird; the safer move is to resolve and check rather than blanket-refuse.

---

## §5 — POSIX-portable recursive directory copy

**Question**: Step 3–4 of the seeding strategy (§1) copies `.specify/` and `.claude/` from host to sandbox. `cp -R` vs `cp -r` vs `rsync` — what's portable and correct?

**Decision**: **`cp -R "$src" "$dst"`** is the portable choice; POSIX-2024 mandates `-R`.

```sh
# Both .specify and .claude may not yet exist in the sandbox; cp -R handles that.
cp -R "$REPO_ROOT/.specify" "$SANDBOX/.specify"
cp -R "$REPO_ROOT/.claude"  "$SANDBOX/.claude"
```

**Rationale**:
- `-R` is the POSIX flag for recursive copy; `-r` is a GNU/BSD synonym with subtly different symlink semantics across implementations. `-R` is unambiguous.
- `rsync` is not POSIX-standard; treating it as optional means accepting a soft dependency, which violates Principle V's "system-agnostic shell tooling" stance for a feature that has no reason to need rsync's flexibility.
- The trees being copied are small (under 10 MB combined for a typical host), so the performance difference between `cp -R` and `rsync` is negligible.

**Alternatives rejected**:
- **`rsync -a`**: faster on huge trees, but unnecessary at this scale and adds a non-POSIX dep.
- **`tar c ... | tar x ...`**: portable but obscure and adds a process pipeline for no benefit.
- **`cp -a`**: GNU extension; not POSIX.

---

## Summary

| § | Question | Decision |
|---|----------|----------|
| 1 | Sandbox seeding strategy | Copy host's `.specify/` + `.claude/` wholesale, then re-run `install.sh` inside sandbox |
| 2 | Sample backlog content | Three over/under-specified items: Pi calculator (happy), notifications (clarify), scaffolding (`- [x]` skip) |
| 3 | Lock signal source | `.sandbox/.specify/extensions/orchestrate/lock` — prepare refuses if present; cleanup ignores |
| 4 | Cleanup path-safety | `realpath` resolve + string-compare against canonical `<repo-root>/.sandbox`; `rm -rf -- $path` with `set -u` |
| 5 | Recursive copy | `cp -R` (POSIX); reject `-a`/`rsync`/`tar` pipelines |

No NEEDS CLARIFICATION markers remain.
