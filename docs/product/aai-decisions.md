---
id: aai-decisions
type: product
capability: aai-decisions
status: current
delivered_by:
  - CHANGE-0142
  - followups-cli-hardening
spec: docs/specs/SPEC-0129-spec-followup-registry.md
updated: 2026-08-18
---

# Follow-up registry on the decision ledger

## What it does

Deferred work used to disappear. When a review found something real but the
ride did not fix it, the deferral was written as free prose inside a decision
entry — 14 such clauses had accumulated against exactly one typed entry, and
nothing in the toolchain could list any of them. One lesson recorded that way
was repeated verbatim as a defect one ride later.

You can now record a deferral as a typed, queryable entry on the decision
ledger that already exists, list the open backlog with one command, filter it
by raising ref, status or age, and close an item with a command that proves
the close actually landed. The open backlog also appears as a section in the
factory performance report, which regenerates itself at every work-item close
— so an ageing follow-up becomes visible without anyone remembering to look.

Nothing here blocks anything. The registry reports; people decide.

## How to use it

Record a deferral (this is the only sanctioned way to write one — see
"Interfaces and contracts" for why a hand-written line is unsafe):

```
node .aai/scripts/follow-ups.mjs add \
  --id fu-bom-first-line-key --ref CHANGE-0137 --severity P2 \
  --what "a UTF-8 BOM hides a first-line config key from both parsers" \
  --why "must fix both parsers together, so it was not folded into this ride" \
  --source "docs/ai/reviews/review-20260813T104221Z-....md"
```

List the backlog:

```
node .aai/scripts/follow-ups.mjs list                  # open backlog, oldest first
node .aai/scripts/follow-ups.mjs list --ref CHANGE-0137
node .aai/scripts/follow-ups.mjs list --status done
node .aai/scripts/follow-ups.mjs list --age-days 14    # only items older than two weeks
node .aai/scripts/follow-ups.mjs list --json           # machine-readable, same numbers
```

Close one when it ships. This is a MANUAL step, on purpose:

```
node .aai/scripts/follow-ups.mjs close --id fu-bom-first-line-key \
  --resolved-by CHANGE-0143 --source <commit sha>
```

`close` appends the resolution, then re-reads the ledger from disk, re-folds
it, prints the item's new status, and exits 0 only when the re-read confirms
the flip. Re-closing an already-closed id is a no-op with a note, not an
error. If the ATTRIBUTION itself was wrong (not just unwanted — the fix
shipped under a different ref/commit than the one the close named), re-run
the same command with `--correct`: it appends a NEW `follow_up_status` record
that becomes the id's latest fold (the append-only ledger is never rewritten),
and refuses at exit 2 both on an item that is not yet closed and on a
`--correct` that would not actually change `resolved_by` or `status` — a
correction must be a real correction, not a second identical close. The close
ceremony (`close-work-item.mjs`) is deliberately NOT wired to
this ledger: its rollback arm truncates a telemetry file by byte length, and a
bug in a second such arm would delete decision history to save one typed
command. The compensating control is the report — an item nobody closes shows
up, and keeps ageing, on a page that refreshes itself.

See the open backlog in the report:

```
node .aai/scripts/generate-factory-report.mjs        # docs/ai/factory-report.html
node .aai/scripts/generate-factory-report.mjs --data-only --decisions <path>
```

## Data model

Two record types, both appended to `docs/ai/decisions.jsonl` (no new store),
both reusing that ledger's existing key vocabulary so every existing reader
sees a familiar shape:

```
{"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"follow_up",
 "id":"fu-<slug>","ref_id":"<ref that raised it>","severity":"P1|P2|P3",
 "finding":"<what, one line>","decision":"<why deferred, one line>",
 "source":"<evidence path, review report, or thread url>",
 "origin":"backfill",        // optional, backfill entries only
 "source_ts":"<ISO8601Z>"}   // optional, backfill entries only
```

```
{"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"follow_up_status",
 "id":"fu-<slug>","status":"done|dropped",
 "resolved_by":"<ref that resolved it, or the reason for dropped>",
 "source":"<commit sha, PR url, or evidence path>"}
```

- `status` lives ONLY on `follow_up_status`. A `follow_up` is open BY
  CONSTRUCTION — an append-only ledger cannot carry mutable state on the
  original line, and a `"status":"open"` field would invite the retro-edit
  this design exists to prevent. Nothing is ever rewritten; resolution is
  always a second appended line.
- Ids match `^fu-[a-z0-9]+(-[a-z0-9]+)*$`, at most 40 characters. They are
  slugs, not sequential numbers: dense numbering forces renumbering when two
  branches allocate at once, and a renumbered id silently invalidates every
  citation already written against it. An id is never renumbered and never
  reused, so `closes fu-bom-first-line-key` in a commit message stays true.
- The registry state is a PROJECTION, computed on every read: for each id the
  first `follow_up` is the item, then every `follow_up_status` for that id is
  applied in timestamp order, latest wins.
- Retention: none. The ledger is append-only and permanent; nothing prunes it.

Degradations are always named, never silent:

| Input | Behavior |
|---|---|
| `#` comment line, blank line | Skipped (the ledger opens with a comment header) |
| Malformed JSON line | Counted, named in a note that also states the counts above may therefore be UNDERSTATED, skipped — never fatal on the read path |
| `follow_up` with no `id` | Folded under a derived `fu-<ref-slug>-<yyyymmddThhmm>` id, named in a note; the original line is never rewritten |
| Same id twice | First occurrence wins, the duplicate is named in a note |
| `follow_up_status` with no matching `follow_up` | Counted as dangling, named, never listed as an item |
| Unparseable or future timestamp | Age reported as n/a, never a negative number and never a fabricated 0 |
| Empty registry | `open_count: 0`, oldest age `null` (never 0) |
| An id that does not match the id grammar | Named `MALFORMED-ID` on the `list` row and `id_malformed: true` in JSON, counted in `counts.malformed_ids`; still counted in `open`/`closed`/`total` — a mistyped id must never make a real item disappear from the backlog |
| `--ledger` names a path that exists but is not a readable file (a directory, a permission error) | On the CLI: refused at exit 2, naming the path and the reason — never reported as an empty registry |

## Interfaces and contracts

- `node .aai/scripts/follow-ups.mjs list [--ledger <path>] [--ref <ref>]
  [--status open|done|dropped|all] [--age-days <n>] [--json]` — prints the
  folded registry, oldest first, deterministically (same input, byte-identical
  output). Default view is the open backlog; the header always reports
  `open`, `closed` and `total` so nothing is hidden by the filter.
- `node .aai/scripts/follow-ups.mjs add --id --ref --severity --what --why
  --source [--ledger] [--actor] [--origin backfill] [--source-ts]` — appends
  one machine-serialized `follow_up` line. This exists instead of a
  hand-authored JSON line for a safety reason, not a tidiness one:
  `routine-emit.mjs` reads this same ledger fail-closed over its ENTIRE
  contents, so one malformed hand-written line silently revokes merge
  authorization for every scheduled routine, with no error anywhere near the
  cause. Going through the tool makes that failure class unreachable.
- `node .aai/scripts/follow-ups.mjs close --id --resolved-by [--source]
  [--status done|dropped] [--ledger] [--actor] [--correct]` — appends one
  `follow_up_status` line and proves the flip by re-reading from disk.
  `--correct` re-closes an ALREADY-closed id to fix a wrong attribution
  (requires the id to be closed already, and requires the new
  `resolved_by`/`status` to differ from the current projection — otherwise
  exit 2).
- `node .aai/scripts/follow-ups.mjs --help` — the grammar and this contract.
- Exit codes (stable): `0` success, including a NON-EMPTY backlog (never an
  error), an empty backlog, a skipped malformed line and an idempotent
  re-close. `1` write path only — the post-append re-read did not show the
  expected state (for example a later-dated status record for the same id
  shadows the append). The read path can never return 1. `2` usage error —
  unknown flag or subcommand, missing required flag, bad id shape, duplicate
  id on `add`, unknown id on `close`, an unreadable `--ledger` path (a
  directory, a permission error) — refused loudly, never folded into the
  absent-ledger case, and never reported as an empty registry.
- A flag value may itself begin with two dashes (for example
  `--what "--decisions is undocumented"`) as long as it is not EXACTLY a flag
  token the subcommand knows. When it is (for example the literal value
  `--why`), write it as `--flag=value` instead (`--what=--why`) — the escape
  hatch for the one case bare argv cannot otherwise resolve.
- `node .aai/scripts/generate-factory-report.mjs [--decisions <path>]` — the
  report reads this registry through the SAME fold the CLI uses (one
  implementation, two consumers) and renders a read-only "Open follow-ups"
  section plus a `follow_ups` block in `docs/ai/factory-report-data.json`
  (`open_count`, `oldest_age_days`, `items[]` with id, ref, severity,
  age_days, what). The report's exit contract is unchanged: always 0 on a
  readable, absent OR unreadable ledger — an unreadable path is named in the
  data honesty notes, never in the exit code (the CLI's own `--ledger` path
  is the one surface that refuses at exit 2; see the degradation table above).
- Zero network, no LLM, Node standard library only.

## Limits and non-goals

- Nothing FORCES a close. A resolved follow-up can linger as open until
  someone runs the command; the compensating control is the ageing report
  section, not a gate. This scope adds no gate anywhere.
- `severity` is author-assigned with no calibration. The report and the CLI
  order by AGE, never by severity, so a mis-assigned P-level cannot hide an
  item.
- Emission depends on a reviewer following the one clause in
  `.aai/SKILL_CODE_REVIEW.prompt.md` that names this tool. If typed entries do
  not grow over the next few rides, the next move is a deterministic reminder
  inside a script that already reads the ledger — not more prompt text.
- The backfill reconstructed history from the prose clauses that existed on
  2026-08-13. It only appended; every pre-existing byte is untouched.
- Downstream projects without `docs/ai/decisions.jsonl` degrade to a named
  note in the report rather than a crash, but they are not exercised by this
  repository's CI.

## Links

- Request: docs/issues/CHANGE-0142-followup-registry.md
- Spec: docs/specs/SPEC-0129-spec-followup-registry.md
- Hardening: docs/issues/CHANGE-0149-followups-cli-hardening.md,
  docs/specs/SPEC-0135-spec-followups-cli-hardening.md
- Ledger: docs/ai/decisions.jsonl
- Report surface: docs/product/factory-performance-report.md
