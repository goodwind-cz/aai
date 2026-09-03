---
id: spec-unsigned-spec-amendment-has-no-outflow
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-unsigned-spec-amendment-has-no-outflow.md
  rfc: null
  pr: []
  commits: []
---

# Spec — an unsigned post-freeze spec amendment files a tracked item, not just a sentence

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/CHANGE-DRAFT-unsigned-spec-amendment-has-no-outflow.md`
- Decision records: `docs/ai/decisions.jsonl` (see "Registry items closed by this scope")
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero deps, bash-3.2 in suites)
- Prior art this scope reuses rather than duplicates: `.aai/scripts/follow-ups.mjs`
  (the `follow_up` / `follow_up_status` two-record fold, the `add` / `list` /
  `close` grammar, the one-appendFileSync discipline, `DEFAULT_LEDGER`)
- HITL canon this scope makes drainable: `.aai/system/AUTONOMOUS_LOOP.md` section 2
  ("Resolves disputed decisions, scope changes, and high-impact risk decisions")
- Durable doc identity (why the tracked id keys on the frontmatter slug, not the
  filename): `.aai/templates/SPEC_TEMPLATE.md` RFC-0007 comment block

Registry items closed by this scope: none. `node .aai/scripts/follow-ups.mjs list`
returns four open items (`fu-reaper-epoch-export-fails-test005`,
`fu-heartbeat-slot-name-not-injective`, `fu-layer-profiles-suite-load-fragile`,
`fu-heartbeat-read-narrower-than-gc`); none names an amendment, a sign-off or the
decisions.jsonl amendment shape, so this scope touches no open item's subject.

## THE MEASURED SITUATION (the intake's framing is stale)

The intake was written when three unsigned amendments stood and named
`SPEC-0153`, `SPEC-0161` and `spec-ac-table-premature-flip-recurs`. Measured on
this branch at `be0c8ed`, that list is wrong in both directions. Counted by
parsing `docs/ai/decisions.jsonl` as JSON (not by grep — see the FORMAT TRAP
below):

- **10** records carry `type: spec_amendment`, at lines 551, 552, 570, 633, 638,
  642, 644, 645, 647, 648.
- **1** is owner-authorized: line 570, `actor: owner`, ref
  `agent-shell-can-write-the-shipping-repo`, authority beginning "owner decision,
  asked because the mechanism changes the owner git commit".
- **9** are unsigned: lines 551, 552, 633, 638, 642, 644, 645, 647, 648.
- Of those 9, **four** (644, 645, 647, 648) already carry an explicit
  `owner_signoff: false` key; **five** (551, 552, 633, 638, 642) carry no such key
  and are unsigned only by prose inside their `authority` string.
- The unsigned records span **5 distinct specs**: SPEC-0153, SPEC-0161, SPEC-0162,
  SPEC-0163, SPEC-0164.

`SPEC-0132` is NOT one of the ten. Its amendment predates the record type: the
spec body carries `## Amendment (owner decision, 2026-08-15T08:14:24Z)` and cites
a `hitl_decision` record, `ref_id: deslop-scope-and-unrequested-engine`, actor
`ales_holubec.net`. It is genuinely signed. Five frozen spec bodies nonetheless
cite it as the precedent that establishes the convention
(SPEC-0153:24, SPEC-0155:258, SPEC-0161:24, SPEC-0162:24, SPEC-0163:32) — the
laundering the intake's AC-005 was written from.

Three further measurements shape the design:

1. **FORMAT TRAP.** `/usr/bin/grep -c '"type":"spec_amendment"'` returns 4;
   parsing each line as JSON returns 10. Six records serialize the key with a
   space (`"type": "spec_amendment"`). Any query in this scope MUST parse JSON
   per line. A grep-based query would have under-reported the population by 60%
   and is forbidden by Spec-AC-03.
2. **THE HEADING IS NOT A LOCATOR EITHER.** SPEC-0164 carries three of the nine
   unsigned amendments and has **no** `## Amendment` heading at all — it records
   them as inline `CORRECTED post-freeze (2026-09-03, amendment item N)`
   annotations. Heading text cannot classify what heading text does not exist.
   This is the concrete proof behind requirement AC-003.
3. **THE CONVENTION IS NOWHERE IN CANON.** `/usr/bin/grep -rn "amend" .aai/
   --include="*.md"` returns **zero** hits. No role prompt, no system doc and no
   template mentions post-freeze amendment. Each ride reconstructs the convention
   by copying the previous ride's `authority` string out of the ledger. That copy
   chain is the transmission mechanism for the defect, and it is why writing the
   convention into canon is in scope.

## Implementation strategy
- Strategy: hybrid
- Rationale: the classifier fold, the two refusals and the `--strict` exit code
  are the deliverable's whole value and each must be observed failing before the
  accepting shape exists (five rides this session shipped guard prose that
  contradicted their own predicate because only accepting inputs were tested);
  the canon text, the PROFILES/suite-map rows and the append-only backfill are
  loop work already covered by existing suite arms.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound; edits the shared prompt corpus and the
  prompt-diet ledger pin (whose headroom is at zero, so a concurrent corpus edit
  in the primary checkout would corrupt the measurement), and appends to
  `docs/ai/decisions.jsonl`, which every other ride also appends to.
- User decision: undecided
- Base ref: main @ be0c8ed
- Worktree branch/path: `change/unsigned-spec-amendment-has-no-outflow` at
  `/Users/ales/Projects/aai-change-amendment` (already created by dispatch)
- Inline review scope: n/a — worktree

## THE DESIGN

### D1 — The tracked artifact is a follow-up registry item, not `human_input`

`.aai/scripts/follow-ups.mjs` is the mechanism. Three reasons, and the rejection
of the alternative is load-bearing enough to state:

**Why `state.mjs set-human-input` is rejected.**
(a) `.aai/scripts/state.mjs` is on `protected_paths_l3` in
`docs/ai/docs-audit.yaml`. Making the writer set `human_input` requires no
state.mjs change, but making it *required* — the AC-001 obligation — would, and
that is a HITL blocker this scope refuses to route around.
(b) `human_input` is a SINGLE slot (`editBlock(state.lines, 'human_input', …)`):
one `required`, one `question`, one `blocking_reason`. Nine standing obligations
across five specs cannot occupy one slot. A single slot is not a drainable queue,
and AC-004 needs a list.
(c) Setting `human_input.required: true` HALTS the autonomous loop. That is
precisely the "hard block that strands an autonomous ride mid-remediation" the
requirement's Constraints section forbids. The rejected option is not merely
awkward; it implements the exact failure mode the requirement rules out.

**Why a new `amendments.jsonl` plus its own CLI is rejected.** The defect under
repair is "a ledger no role is obliged to read". A second ledger with a second
drain surface reproduces that defect one level up, and costs its own
PROFILES/suite-map/docs-audit wiring for no gain.

**Why follow-ups.mjs wins.** It appends to the SAME `docs/ai/decisions.jsonl`; it
already has the append-only two-record fold (`follow_up` item plus
`follow_up_status` overlay) this design needs twice; `list --status open` is
literally "a list to drain"; `close --id … --resolved-by …` is the sign-off
record; and — decisively — `.aai/PLANNING.prompt.md`'s existing REGISTRY CONSUMER
step already makes every Planning role run `follow-ups.mjs list` and scan it.
Filing into that registry gives the disclosure an outflow that a role is *already
obliged to read*, at a cost of zero new prompt bytes and zero new reading habits.

### D2 — Resolving AC-001 against the Constraints section

The requirement's AC-001 ("cannot be recorded without a tracked item existing")
and its Constraints section ("must not become a hard block that strands an
autonomous ride mid-remediation") pull against each other only if the writer is
assumed to be a *checker*. It is not. The resolution is:

> **A fail-OPEN writer that co-creates, plus a fail-CLOSED detector at a gate.**

- `spec-amend.mjs add` never refuses an amendment for want of a tracked item. It
  **manufactures** the tracked item in the same invocation. AC-001 is satisfied by
  CONSTRUCTION — after any successful `add` of an unsigned amendment, a tracked
  item naming it and the sign-off it defers provably exists — and satisfied
  without a single refusal path that could strand a ride. The only refusals are
  usage errors (a missing required flag, an unreadable ledger, `--signoff owner`
  with no `--authority`), and every one of them is a defect in the invocation, not
  a state of the world the ride cannot fix.
- Enforcement that nobody bypassed the writer by hand-appending raw JSON lives in
  `spec-amend.mjs list --strict`, which exits 1 on any untracked or unclassified
  amendment. That is wired at the PR/close gate, where stopping costs a re-run and
  not a stranded remediation round.

The honest residual: a role can still hand-append a raw line to
`docs/ai/decisions.jsonl` and skip the writer entirely. The detector catches it,
but only at the gate, not at the moment of the write. Closing that would need a
write-guard over `decisions.jsonl` itself — a materially larger scope, and one
that would have to argue with `follow-ups.mjs`'s own append path. Recorded as R1,
not solved here.

### D3 — `owner_signoff` is the field; an absent field is `unclassified`

The classifier is the boolean key `owner_signoff`, never heading text and never
prose inside `authority`. The fold has **three** outcomes, not two:

| effective value | bucket |
|---|---|
| `owner_signoff === true` | `signed` |
| `owner_signoff === false` | `unsigned` |
| key absent, no overlay | `unclassified` |

`unclassified` is a distinct bucket on purpose. Treating an absent field as
"unsigned" would be a guess, and treating it as "signed" would launder exactly
the way SPEC-0132 was laundered. `--strict` fails on `unclassified` for the same
reason it fails on untracked: the mechanism must never silently decide which of
the two an old record was.

### D4 — Back-classification is by APPEND (HAZ-LEDGER)

`docs/ai/decisions.jsonl` is append-only. The ten existing records are never
edited. A new overlay record type carries the classification:

```
{"v":1,"ts":"<ISO8601Z>","actor":"<slug>","type":"spec_amendment_classification",
 "classifies_ts":"<target record ts>","classifies_ref":"<target ref_id>",
 "owner_signoff":<bool>,"why":"<one line>","origin":"backfill","source":"<evidence>"}
```

The target is addressed by the `(ts, ref_id)` pair, **not** by line number: line
numbers are not stable identifiers and shift under any future ledger operation.
The pair is unique across all ten existing records (verified: the three
`role-progress-heartbeat` records differ at 05:40 / 07:15 / 12:40, the two
`close-leaves-state-stale` and the two `metrics-flush-…` likewise). `classify`
refuses an ambiguous or unmatched target with exit 2.

The fold takes the LATEST overlay per target, else the record's own
`owner_signoff` key, else `unclassified` — the same latest-wins shape
`follow-ups.mjs` already uses for `follow_up_status`.

### D5 — One tracked item per spec per open obligation, keyed on the durable slug

The owner's decision is per spec ("do I accept the amended SPEC-0161, or reverse
it?"), not per ledger line. So the item id is `fu-amend-<spec frontmatter id>`,
one item per spec, and a second amendment on a spec whose item is still open
attaches to it (the writer reports "tracked item fu-amend-<id> already open" and
exits 0) rather than filing a duplicate. If the item was already CLOSED — the
owner signed off once — a new amendment reopens the obligation under the
disambiguated id `fu-amend-<spec-id>-<yyyymmddThhmm>`, mirroring
`follow-ups.mjs`'s own derived-id shape.

The id keys on the spec's **frontmatter `id`**, never on its filename. This is
SEAM-1: `allocate-doc-number.mjs` renames `SPEC-DRAFT-<slug>.md` to
`SPEC-000N-<slug>.md` at merge, so a path-keyed id would silently fork into two
items across the rename — and every one of the nine standing amendments was
written against a `SPEC-DRAFT-…` path that no longer exists on disk.

### D6 — Discharging AC-005 without editing frozen `status: done` specs

Measured: **no file under `.aai/**` mentions SPEC-0132, or the word "amend", at
all.** The precedent-chain prose lives only in the bodies of five frozen
`status: done` specs. Editing those would mean amending five frozen specs to fix
a defect about amending frozen specs, and the requirement puts "retroactively
invalidating the standing amendments" out of scope. AC-005 is therefore
discharged forward, not backward:

1. The NEW canon text in `.aai/system/AUTONOMOUS_LOOP.md` states the convention
   and classifies SPEC-0132 explicitly as an OWNER decision (naming the
   `hitl_decision` record, `2026-08-15T08:14:24Z`, actor `ales_holubec.net`) and
   states in terms that it is NOT precedent for proceeding unsigned.
2. A guard test pins that no file under `.aai/**` cites SPEC-0132 as precedent for
   an unsigned amendment — deny-by-default, matched on the repo-relative path.
3. The five frozen spec bodies are surfaced to the owner through their tracked
   items (D5), which is the requirement's own instruction: surfaced for a
   decision, not reversed by default.

### D7 — Where the canon text lives, and what it costs

The convention BODY goes in `.aai/system/AUTONOMOUS_LOOP.md`. `.aai/system/**` is
outside the prompt-diet corpus (established by the friction-shadow-capture-wiring
and friction-capture-default-on ledger entries: "the seam BODY lives in
`.aai/system/…` — system/, not corpus, no ledger cost"), so the body carries no
ledger obligation. Exactly two in-glob pointers are added, and no more:

- `.aai/ROLE_COMMON.md` — one short block pointing at the writer. ROLE_COMMON is
  shared role canon and IS inside TEST-010's extra accounting. Chosen over a
  per-role edit because the nine unsigned amendments were filed by THREE different
  roles (planning 1, remediation 7, orchestrator 1); a REMEDIATION-only pointer
  would have missed two of them.
- `.aai/SKILL_PR.prompt.md` — one bullet running the `--strict` detector at the
  close gate.

Both are inside the ledger corpus. **Headroom is at zero** (the last
`JUSTIFIED_ADDITIONS` entry, `operator-waiver-unblocks-pr`, records "credited 1:1
at zero headroom so headroom stays 0/2048"), so the credit must equal the growth
EXACTLY. Implementation MEASURES `wc -c` before and after on each of the two
files and credits the true sum 1:1, with a matching `want_growth` bump. **No byte
count appears in this spec on purpose** — a number written here would be a guess
the ledger then has to be bent to match.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to requirement AC-001 → Spec-AC-01, Spec-AC-02
- Maps to requirement AC-002 → Spec-AC-03, Spec-AC-05
- Maps to requirement AC-003 → Spec-AC-04
- Maps to requirement AC-004 → Spec-AC-06, Spec-AC-07
- Maps to requirement AC-005 → Spec-AC-08
- Companion obligations (canon closed list) → Spec-AC-09

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN `spec-amend.mjs add --signoff none` succeeds against a fixture ledger THEN that same ledger gains BOTH one `spec_amendment` record carrying `owner_signoff: false` AND one open `follow_up` whose `what` names the spec and the sign-off still owed, from the ONE invocation | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-001 and TEST-004 green | — | AC-001 satisfied by co-creation, not refusal |
| Spec-AC-02 | WHEN `add --signoff none` is invoked and no tracked item pre-exists THEN it exits 0 and never refuses; the ONLY non-zero exits are usage errors, and `--signoff owner` without `--authority` exits 2 with a message naming `--authority` | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-red.log TEST-002 RED then docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-002 green | — | the fail-OPEN half of D2; pins one REJECTED input and its message text |
| Spec-AC-03 | `node .aai/scripts/spec-amend.mjs list --json` reports every `spec_amendment` in the live ledger with a `bucket` of `signed`, `unsigned-tracked`, `unsigned-untracked` or `unclassified`, computed from parsed JSON per line and never from a grep or from heading text; run against the live ledger it reports exactly 10 records | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-003 green, live parsed=10 tight-grep=4 | — | AC-002; the 10-vs-4 format trap is the reason JSON parsing is required |
| Spec-AC-04 | The bucket is decided by the `owner_signoff` key alone. A record with the key absent lands in `unclassified` and in neither of the other two, and a record whose `authority` prose says "NOT an owner decision" but which carries `owner_signoff: true` is reported `signed` | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-red.log TEST-005 RED then docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-005 and TEST-006 green | — | AC-003; the field outranks the prose, and absence is its own bucket |
| Spec-AC-05 | `list --strict` exits 1 when at least one record is `unsigned-untracked` or `unclassified`, exits 0 when every record is `signed` or `unsigned-tracked`, and prints a line naming each offending record; without `--strict` it exits 0 in both cases | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-red.log TEST-007 RED then docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-007 green | — | the fail-CLOSED half of D2; both arms pinned, not just the failing one |
| Spec-AC-06 | After the backfill, `git diff` shows `docs/ai/decisions.jsonl` gained ONLY appended lines: the first 651 lines of the post-change file are byte-identical to the pre-change file | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-008 green, base_lines=651 byte-exact prefix, git diff --numstat 18 insertions 0 deletions (15 at the scope commit plus 3 later disposition records; remeasured at code review) | — | HAZ-LEDGER; append-only proved by byte comparison, not by claim |
| Spec-AC-07 | After the backfill, `list --strict` over the live ledger exits 0, all 10 records carry an effective classification, and `follow-ups.mjs list --status open` names one open item per unsigned spec — SPEC-0153, SPEC-0161, SPEC-0162, SPEC-0163, SPEC-0164 — with no spec body edited and no amendment reversed | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-009 green, list --strict exit 0 over the live ledger | — | AC-004; surfaced for decision, not reversed |
| Spec-AC-08 | `.aai/system/AUTONOMOUS_LOOP.md` states the convention and names SPEC-0132's amendment as an owner decision citing its `hitl_decision` record; and a guard reports zero files under `.aai/**` citing SPEC-0132 as precedent for an unsigned amendment, deny-by-default on repo-relative paths | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log TEST-010 green, 235 files swept under .aai | — | AC-005 discharged forward; five frozen done specs untouched |
| Spec-AC-09 | `.aai/scripts/spec-amend.mjs` has a `.aai/system/PROFILES.yaml` classification entry, `tests/skills/suite-map.yaml` has an `aai-spec-amend` row, and `bash tests/skills/test-aai-prompt-diet.sh` is green with a new `JUSTIFIED_ADDITIONS` entry equal to the MEASURED corpus growth and a matching TEST-012 pin bump | implementing | docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-green.log test-aai-prompt-diet.sh and test-aai-hygiene-pack.sh green, credit 1621 B, pin 10324 to 11945 (remeasured at remediation round 1) | — | companion obligations, closed list; the byte count is measured by Implementation, never copied from this spec |

## Implementation plan

### Components

- **NEW** `.aai/scripts/spec-amend.mjs` — Node ESM, `node:` stdlib only, zero deps.
  Subcommands `add`, `classify`, `list`. Reuses `follow-ups.mjs`'s append
  discipline (one `fs.appendFileSync` of one serialized line, newline-terminated,
  a leading `\n` when the ledger's last line lacks one) and its `DEFAULT_LEDGER`
  constant. It does NOT import follow-ups.mjs's internals; it writes the same
  documented `follow_up` shape.
- **NEW** `tests/skills/test-aai-spec-amend.sh` — bash-3.2, fixture-ledger based.
- **EDIT** `.aai/system/AUTONOMOUS_LOOP.md` — the convention body (D6, D7). No
  ledger cost.
- **EDIT** `.aai/ROLE_COMMON.md`, `.aai/SKILL_PR.prompt.md` — the two in-glob
  pointers (D7). Ledger cost, measured.
- **EDIT** `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `tests/skills/lib/prompt-diet-ledger.sh` — companion obligations.
- **APPEND** `docs/ai/decisions.jsonl` — 10 classification overlays plus 5
  backfill follow-ups. Never an in-place edit.

### CLI grammar

```
node .aai/scripts/spec-amend.mjs add --spec <path> --ref <ref_id>
     --what "<one line>" --why "<one line>" --signoff owner|none
     [--authority "<evidence>"]  (REQUIRED when --signoff owner)
     [--actor <slug>] [--ledger <path>]

node .aai/scripts/spec-amend.mjs classify --ts <ISO8601Z> --ref <ref_id>
     --signoff owner|none --why "<one line>" --source "<evidence>"
     [--origin backfill] [--actor <slug>] [--ledger <path>]

node .aai/scripts/spec-amend.mjs list [--status unsigned|signed|unclassified|all]
     [--json] [--strict] [--ledger <path>]
```

Exit codes: 0 success (and, on `list`, no `--strict` violation); 1 a `--strict`
violation or a post-append re-read that did not confirm the write; 2 usage error,
unreadable ledger, or an ambiguous/unmatched `classify` target.

### Record shapes

```
{"v":1,"ts":"…","actor":"…","type":"spec_amendment","ref_id":"…",
 "spec":"<repo-relative path>","spec_id":"<frontmatter id>",
 "owner_signoff":<bool>,"what":"…","why":"…",
 "authority":"…",            // present iff owner_signoff true
 "tracked_by":"fu-amend-…"}  // present iff owner_signoff false
```

`owner_signoff` is REQUIRED and boolean on every record the writer emits. The
`spec_amendment_classification` overlay shape is in D4; the `follow_up` shape is
`follow-ups.mjs`'s documented one, unchanged.

### Data flows

`add --signoff none` → read the spec's frontmatter `id` → derive
`fu-amend-<id>` → fold the ledger for an existing item under that id → append the
`spec_amendment` line carrying `tracked_by` → append the `follow_up` line (or, if
the item is already open, skip it and say so) → re-read and confirm both writes.

`list` → read the ledger → JSON.parse each non-comment line → collect
`spec_amendment` items keyed `(ts, ref_id)` → apply the latest
`spec_amendment_classification` overlay per key → resolve `tracked_by` against
the folded `follow_up` / `follow_up_status` state → bucket → render.

### Edge cases

- A malformed (non-JSON) line already in the ledger: counted and reported as a
  NOTE, never fatal to `list`, and never silently dropped from the totals. One
  malformed line breaks `routine-emit`'s authorization reader, which reads the
  whole ledger — so the writer must never be the source of one (SEAM-4).
- The ledger's leading `# Decision Log` comment line: skipped, not parsed.
- A spec file that is missing or has no frontmatter `id`: exit 2 naming the file.
  The id is the tracked item's key (D5) and must never be guessed from the path.
- Two amendments on the same spec in the same minute: the disambiguated id
  `fu-amend-<spec-id>-<yyyymmddThhmm>` collides. The writer detects the collision
  and appends a `-2` suffix rather than tripping follow-ups' duplicate-id rule.
- `--what` / `--why` values beginning with `--`: the `--flag=value` escape hatch,
  identical to `follow-ups.mjs`'s documented rule.

### Seams this scope crosses

- **SEAM-1 — draft-to-numbered spec rename.** `allocate-doc-number.mjs` renames
  the spec at merge. The tracked id keys on the frontmatter `id`, so it survives.
  Crossed by TEST-006, which renames the fixture spec and asserts the same item.
- **SEAM-2 — shared ledger with `follow-ups.mjs`.** `spec-amend.mjs` PRODUCES a
  `follow_up` line that `follow-ups.mjs` CONSUMES. Crossed by TEST-004, which
  writes via `spec-amend add` and then asserts the item through
  `follow-ups.mjs list --status open` — the real reader, not a mock of it.
- **SEAM-3 — append-only ledger (HAZ-LEDGER).** Crossed by TEST-008's byte
  comparison of the pre-change prefix.
- **SEAM-4 — whole-ledger readers.** `routine-emit.mjs` and
  `generate-factory-report.mjs` parse the entire ledger. Crossed by TEST-009,
  which runs `follow-ups.mjs list` and `spec-lint`/`docs-audit` clean after the
  backfill.
- **SEAM-5 — the prompt-diet corpus.** Crossed by TEST-010 (the existing
  `test-aai-prompt-diet.sh`), not by a new assertion of our own.

### Test-design traps that apply to this plan

- **A guard's test plan must pin a REJECTED input and the guard's own message
  text.** Applied at Spec-AC-02 (`--signoff owner` with no `--authority`: exit 2,
  message names the flag) and Spec-AC-05 (both the exit-1 and the exit-0 arm).
  Testing only accepting shapes is what shipped five contradicted guards this
  session.
- **An exemption list is matched on the repo-relative PATH, deny-by-default.**
  Applied to the Spec-AC-08 guard: it scans `.aai/**` and denies by default; any
  exemption is a repo-relative path, never a basename. An enumerated list's
  forgotten member is the hole.
- **`git init --bare` takes HEAD from the per-machine `init.defaultBranch`.** NOT
  APPLICABLE — no test in this plan creates or clones a bare repository; the
  fixtures are plain files in a temp directory. Recorded so the omission is a
  decision rather than an oversight.

### DO NOT LET THIS RIDE BECOME ITS OWN WORST CASE

This spec is about unsigned post-freeze amendments. If implementing it outgrows
this frozen spec, **stop and ask the owner.** Do not file a tenth unsigned
amendment against this document. Set `human_input.required: true` with the
question, or return the blocker to the orchestrator, and wait. An amendment filed
here would be the mechanism disproving itself in its own delivery, and Validation
is instructed to treat one as BLOCKING.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                | Description | Status |
|----------|------------|------|-------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-spec-amend.sh | one `add --signoff none` against a fixture ledger appends BOTH a `spec_amendment` with `owner_signoff` false AND an open `follow_up` whose `what` names the spec and the sign-off owed; both parse as JSON | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-spec-amend.sh | REJECTED input — `add --signoff owner` with no `--authority` exits 2 and stderr contains the literal `--authority`; and `add --signoff none` against a ledger holding no tracked item exits 0, proving the writer never refuses for a missing item | green |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-spec-amend.sh | `list --json` over the LIVE ledger reports exactly 10 `spec_amendment` records, including the six whose `type` key is serialized with a space — the arm that fails if the query is grep-based | green |
| TEST-004 | Spec-AC-01 | int  | tests/skills/test-aai-spec-amend.sh | SEAM-2 — after `spec-amend add --signoff none`, `node .aai/scripts/follow-ups.mjs list --status open` names the item; produced by one tool, asserted through the other, no mock | green |
| TEST-005 | Spec-AC-04 | unit | tests/skills/test-aai-spec-amend.sh | field-over-prose — three fixture records (key true, key false, key absent) bucket as `signed`, `unsigned-*`, `unclassified`; a fourth whose `authority` prose reads "NOT an owner decision" but whose key is true buckets `signed` | green |
| TEST-006 | Spec-AC-04 | unit | tests/skills/test-aai-spec-amend.sh | SEAM-1 — renaming the fixture spec from `SPEC-DRAFT-<slug>.md` to `SPEC-0999-<slug>.md` leaves `list` folding the amendment to the SAME `fu-amend-<frontmatter id>` item | green |
| TEST-007 | Spec-AC-05 | int  | tests/skills/test-aai-spec-amend.sh | BOTH strict arms — a fixture with one untracked record exits 1 and prints its ref; the same fixture after `classify` plus its follow-up exits 0; without `--strict` both exit 0 | green |
| TEST-008 | Spec-AC-06 | int  | tests/skills/test-aai-spec-amend.sh | append-only — capture the ledger before the backfill, run `classify` and the backfill adds, then assert the first 651 lines are byte-identical by comparing `head -651` of each with `cmp` | green |
| TEST-009 | Spec-AC-07 | int  | tests/skills/test-aai-spec-amend.sh | post-backfill live state — `list --strict` exits 0, all 10 records classified, and `follow-ups.mjs list --status open` names one item for each of SPEC-0153/0161/0162/0163/0164; SEAM-4 co-asserted by `follow-ups.mjs list` staying clean | green |
| TEST-010 | Spec-AC-08 | int  | tests/skills/test-aai-spec-amend.sh | canon guard — `.aai/system/AUTONOMOUS_LOOP.md` names SPEC-0132 as an owner decision and cites its `hitl_decision` record; the deny-by-default sweep over `.aai/**` on repo-relative paths reports zero files citing it as unsigned precedent; a planted violation file FAILS the sweep by name | green |
| TEST-011 | Spec-AC-09 | int  | tests/skills/test-aai-hygiene-pack.sh | existing hygiene pin — the new suite has its `aai-spec-amend` row in `tests/skills/suite-map.yaml` and `spec-amend.mjs` has its `.aai/system/PROFILES.yaml` entry | green |
| TEST-012 | Spec-AC-09 | int  | tests/skills/test-aai-prompt-diet.sh | existing ledger pin — the new `JUSTIFIED_ADDITIONS` entry equals the MEASURED growth of `.aai/ROLE_COMMON.md` plus `.aai/SKILL_PR.prompt.md`, the TEST-012 checkpoint is bumped 1:1, and headroom stays within the 2048 cap | green |

RED observation: TEST-002, TEST-005 and TEST-007 are the hybrid strategy's
TDD-first tests — the refusal, the three-bucket classifier and the strict exit
code. Each is written and observed FAILING on the pre-change tree before the
engine exists, and the failing output is stored at
`docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-red.log`. TEST-003's
10-vs-4 arm is also RED-proofable today: a grep-based implementation reports 4.

## Verification

- `bash tests/skills/test-aai-spec-amend.sh` — all arms green
- `bash tests/skills/test-aai-prompt-diet.sh` — green with the new ledger entry
- `bash tests/skills/test-aai-hygiene-pack.sh` — green with the suite-map row
- `node .aai/scripts/spec-amend.mjs list --strict` — exit 0 over the live ledger
- `node .aai/scripts/follow-ups.mjs list --status open` — five `fu-amend-*` items
- `git diff --stat docs/ai/decisions.jsonl` — insertions only, zero deletions
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-unsigned-spec-amendment-has-no-outflow.md`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status

## Evidence contract

- ref_id: `unsigned-spec-amendment-has-no-outflow`
- Spec-AC and TEST-xxx links as tabled above
- Stored RED artifact (hybrid strategy):
  `docs/ai/tdd/unsigned-spec-amendment-has-no-outflow-red.log` covering TEST-002,
  TEST-005, TEST-007
- Green run directory under `tests/skills/results/`
- Exit codes recorded per command in the Verification list
- Commit SHA / diff range recorded at hand-off

## Residual risks

- **R1 — the writer is bypassable.** A role can hand-append a raw
  `spec_amendment` line and skip `spec-amend.mjs`. The `--strict` detector catches
  it at the gate, not at the write. Closing it needs a write-guard over
  `decisions.jsonl`, which is a separate and larger scope. Accepted, per D2.
- **R2 — the tracked item can be closed without an owner.** `follow-ups.mjs close`
  is not owner-authenticated; any role could close a `fu-amend-*` item. This scope
  does not add authentication. The `close` record does name its `resolved_by`, so
  a wrongly-closed item is auditable after the fact but not prevented.
- **R3 — the five frozen spec bodies still cite SPEC-0132 as precedent.** By
  design (D6): correcting them means amending five frozen `status: done` specs,
  which the requirement puts out of scope. The canon text and the guard prevent
  the chain from extending; they do not retract it.
- **R4 — three roles must actually call the writer.** The two prompt pointers make
  it discoverable, not mandatory. If a role writes the record by hand anyway, R1
  applies. The `--strict` gate is the backstop.
