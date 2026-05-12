# Contract: `BACKLOG.md` grammar

**Status**: Normative. The parser MUST implement exactly this grammar.

This document is the single source of truth for what counts as a "feature item" in `BACKLOG.md`. It implements the decision recorded in `spec.md` `## Clarifications` Q1 and refined by Q8.

---

## Item definition

A **backlog item** is a top-level Markdown checkbox list item whose marker matches one of:

- `- [ ]` (incomplete — processed by the orchestrator)
- `- [x]` or `- [X]` (complete — skipped per FR-003a)

"Top-level" means the line is **not indented** — column-0 hyphen, then a space, then the checkbox marker.

A line that does not match the top-level checkbox pattern (heading, paragraph, blockquote, fenced code, nested list item, blank line) is **ignored for item segmentation**.

### Formal regex (parser MUST use exactly this)

```
^- \[(?:[ xX])\] (?P<rest>.+)$
```

Anchored. Single line. No multi-line items in v1.

---

## Title and description extraction

For a matched item line, the `rest` capture group is split on the **first** occurrence (left-to-right) of one of these separators, in this priority order:

1. ` — ` (space + em-dash + space, U+2014)
2. ` -- ` (space + double hyphen + space)
3. ` - ` (space + single hyphen + space)

- If a separator is found: `title = rest[: separator_start]`, `description = rest[separator_end :]`. Both are then whitespace-trimmed.
- If no separator is found: `title = trim(rest)`, `description = ""`.

The **canonical identity** of the item is `lowercase(trim(title))`. This is the value the Lead uses to match against `Feature.title` on re-run (per Q8).

---

## Parse-time errors

| Error condition | Lead action |
|-----------------|-------------|
| Two parsed items share the same canonical title | Abort with `code=duplicate_title` listing both source line numbers. |
| A parsed item has empty canonical title (e.g., `- [ ]    `) | Abort with `code=empty_title` listing the source line. |
| Total parsed items exceeds `limits.max_features` | Abort with `code=too_many_features` (recoverable: raise the limit). |
| File missing or unreadable | Treat as zero items — clean, non-error exit per FR-003. |
| File contains zero top-level checkbox items | Treat as zero items — clean, non-error exit per FR-003. |

---

## Nested content (NOT items)

Nested checkbox or list content beneath a top-level item is **not** parsed as a separate feature. The default behaviour is to **ignore** nested content entirely (it is not appended to the parent description). If a future version chooses to concatenate, that change MUST be a documented opt-in behind a new config key.

---

## Examples

### Accepted backlog

```markdown
# My Backlog

This is intro prose. Ignored.

- [ ] Add user login — Support email+password and OAuth2 against Google.
- [ ] Profile page
- [x] Onboarding flow -- Already shipped; will be skipped.
- [ ] Search bar - Header-mounted with type-ahead from the product catalogue.

## Section heading, also ignored

- [ ] Notifications — In-app and email digest.
```

Parse output:

| id (allocated at run time) | title (canonical) | description |
|---|---|---|
| 001 | `add user login` | `Support email+password and OAuth2 against Google.` |
| 002 | `profile page` | `` |
| (skipped) | (`onboarding flow`) | (item is `- [x]`, skipped) |
| 003 | `search bar` | `Header-mounted with type-ahead from the product catalogue.` |
| 004 | `notifications` | `In-app and email digest.` |

### Rejected: duplicate canonical title

```markdown
- [ ] Search bar — Header search.
- [ ] search bar — Sidebar search.
```

Aborts: `duplicate_title` (case-insensitive collision).

### Rejected: empty title

```markdown
- [ ]   
```

Aborts: `empty_title`.

---

## What the parser does NOT do

- Does **not** infer features from headings.
- Does **not** infer features from prose paragraphs.
- Does **not** infer commit type (`feat:` / `fix:`) from the item text — that mapping is the integrator's concern (FR-020).
- Does **not** support Markdown link references, emphasis, or HTML inside the title for identity purposes — they are taken verbatim as part of the title text.
- Does **not** support multi-line item descriptions in v1. A line break ends the item.

This grammar is intentionally narrow. Constitutional Principle V's portability concern is satisfied because every POSIX `awk` / `sed` implementation can handle the regex.
