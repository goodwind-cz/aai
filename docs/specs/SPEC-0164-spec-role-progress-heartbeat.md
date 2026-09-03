---
id: spec-role-progress-heartbeat
type: spec
number: 164
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0170-role-progress-heartbeat.md
  rfc: null
  pr:
    - TBD
  commits:
    - b66c3f4
---

# Spec — a long-running role writes a progress heartbeat the observer can read without asking the orchestrator

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/CHANGE-0170-role-progress-heartbeat.md`
- Decision records: `docs/ai/decisions.jsonl` (see "Registry items closed by this scope")
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero deps, bash-3.2 in suites)
- Adjacent surface this scope deliberately does NOT extend:
  `.aai/scripts/generate-live-status.mjs` (SPEC-0114 / CHANGE-0127) — see `## Positioning against generate-live-status.mjs`
- Convention this scope is bound by: `.aai/scripts/lib/runtime-file.mjs` header,
  "CONVENTION PIN" — a new runtime sidecar MUST use the shared primitives.
- Storage decision (owner-approved 2026-09-03, NOT re-opened here):
  `docs/issues/CHANGE-0170-role-progress-heartbeat.md` "Why not STATE.yaml".

## Problem this solves, stated honestly

The operator repeatedly asked "stav?" during long autonomous rides and the only
truthful answer was "still running, no more detail". The sharper motivation is
narrower: on three occasions in one session the orchestrator announced a
dispatch it had not actually made, and the only reason it surfaced was the
operator asking. So the value of this signal is that it does not come from the
orchestrator's narration.

What the heartbeat therefore does and does not prove (an honest boundary, kept
here so no later reader over-claims it):
- PROVES, machine-written: SOME process existed, ran in worktree `<w>` at pid
  `<p>`, and wrote at time `<t>`. That POSITIVE half is the whole of what the
  mechanism surfaces.
- DOES NOT PROVE WHICH PROCESS.
  CORRECTED post-freeze (2026-09-03, amendment item 2): the word
  "un-narratable" above over-read what the payload establishes, and this
  bullet did not exist. `pid` and `worktree` identify A writer, not the
  DISPATCHED writer — nothing stops the orchestrator writing a slot itself, so
  a PRESENT slot is corroboration rather than proof of a dispatch. The claim is
  narrowed here, in `heartbeat.mjs`'s header and in `CHANGELOG.md` together; no
  delivered behaviour changes.
- DOES NOT PROVE ANYTHING BY ITS ABSENCE, and that is BY CONSTRUCTION.
  EXTENDED post-freeze (2026-09-03, amendment item 2, round 3): the first
  correction above narrowed WHICH PROCESS correctly and then over-corrected in
  the other direction, asserting that "an announced dispatch that never happened
  leaves NO slot file at all — that absence is the real detection, and it is the
  load-bearing half". That was falsified against this same spec and the wiring
  it ships, not merely improved on: an absent slot is produced identically by an
  announced-but-never-made dispatch, by a role that has not yet reached a round
  boundary, by a role in a separate CLONE (R1), and by ANY role that called
  `write` and hit a degrade — every degrade exits 0 and writes nothing (D4).
  Absence is therefore the one observable this design deliberately REFUSES to
  interpret, which is what R2 ("absence degrades to today's silence, never to a
  new failure mode"), `.aai/VALIDATION.prompt.md` c3 ("an absent heartbeat is
  silence, never a finding") and D5's refusal to define a threshold all already
  said. Corrected in this spec, in `heartbeat.mjs`'s header and in
  `CHANGELOG.md` together; no delivered behaviour changes.
- DOES NOT PROVE: that the `message` text is accurate. The message is still the
  role's self-report. The timestamp is the trustworthy field; the prose is not.

## Positioning against generate-live-status.mjs

DECISION: the heartbeat lives **beside** `generate-live-status.mjs`. It does not
feed it in this scope, does not replace any part of it, and adds no second HTML
renderer.

Why, on the merits:
- Different producer. `generate-live-status.mjs` reads HARNESS session
  transcripts through `.aai/scripts/live-parsers/registry.mjs` — an OUTSIDE
  observer of the CLI process. The heartbeat is written by the ROLE about its
  own ride semantics. Nothing in a harness transcript knows what "sweep round 2
  of 3" means.
- Different question. That generator answers "what is running NOW and what did
  it cost"; its header states it deliberately never reads `docs/ai/STATE.yaml`
  and it shows no ride phase, no HITL state, no pending question. The heartbeat
  answers "how far along is the role", which is the gap the intake names.
- Different consumption shape. The operator's need is a second terminal and one
  command that prints text — the exact thing that does NOT depend on the
  orchestrator. Rendering an HTML page to answer "stav?" adds a generation step
  and a file-watch to a question answered in one line. The intake also puts a
  UI/dashboard explicitly out of scope.
- Cost of coupling now. `generate-live-status.mjs` is 674 lines with its own
  incremental cache, `degraded` array contract and XSS-escaping discipline;
  bolting an advisory panel onto it would put this scope's blast radius inside a
  file this scope has no reason to touch.

Deliberately cheap future seam (NOT built here, NOT a follow-up obligation):
`heartbeat.mjs read --json` emits a stable `{slots: [...], degraded: [...]}`
shape, which is the same `degraded`-array convention `generate-live-status.mjs`
already uses. If a heartbeat panel is ever wanted there, it is one read of one
JSON payload — no reshaping of this scope's output. That seam is NOT
pre-authorised in Spec-AC-08's allowlist: `generate-live-status.mjs` was
dropped from it in amendment item 2 round 3, so building the panel costs one
allowlist line on the day it is built (see D6).

## Design

### D1 — Location: one directory under the git COMMON dir

`<git-common-dir>/aai/heartbeat/<slot>.json`

Resolution, cwd-independent: the script resolves the repo root from its own
`import.meta.url` (`../..`, the `live-spool.sh` discipline), runs
`git -C <root> rev-parse --git-common-dir`, and resolves the result against
`<root>`.

Why this location, against the two disqualifying facts the intake recorded:
- **Worktree-independent by construction.** MEASURED on this machine (git
  2.50.1): from the main checkout `--git-common-dir` prints `.git`, from a
  subdirectory of it `../.git`, and from a LINKED WORKTREE the absolute
  `/Users/ales/Projects/aai/.git`. All three resolve to one absolute path. A
  role writing inside its worktree and an observer reading from the main
  checkout therefore hit the same file. This is exactly the defect that ruled
  out `docs/ai/STATE.yaml`.
- **The relative/absolute split is a real trap**, not a hypothetical:
  `path.resolve(root, out)` is correct in both cases; a naive
  `path.join(root, out)` is not. Spec-AC-01 pins it with a REAL linked
  worktree, not a fixture stand-in.
  CORRECTED post-freeze (2026-09-03, amendment item 1): this bullet and the
  Edge-cases line below originally named the failing case BACKWARDS. Measured
  independently twice (Implementation, then Validation, git 2.50.1): the raw
  output is relative in the main checkout (`.git`, or `../.git` from a
  subdirectory) and ABSOLUTE in a linked worktree, so `path.join` is CORRECT
  in the main checkout and WRONG in the worktree, where it glues the absolute
  path onto the worktree root and yields a path that does not exist. The code,
  the `heartbeat.mjs` header, `CHANGELOG.md` and TEST-002 all state the
  measured direction; only these two spec lines were inverted, so no delivered
  behaviour changes. A spec that teaches a trap backwards is worse than one
  that omits it, hence the correction rather than a silent carry.
- **Structurally never committed.** Nothing under `.git/` can be added to the
  index. This satisfies the intake's AC-004 without a `.gitignore` line, so
  this scope adds NO entry to `.gitignore`, `.aai/system/RUNTIME_IGNORE.list`,
  or `.aai/system/DOCS_AI_CANON.list`, and cannot appear in a diff, in
  `docs/INDEX.md` regeneration, or in an append-only ledger.
- Not a protected L3 surface, and it needs no carve-out in
  `.aai/SUBAGENT_CONTRACT.md`: a dispatched subagent writing this file is not
  writing `docs/ai/STATE.yaml`, so the single-writer rule is untouched.

`AAI_HEARTBEAT_DIR` overrides the directory absolutely (tests, and any host
where the git probe cannot run). Precedent: `AAI_LIVE_SPOOL_DIR`.

### D2 — One file per slot, never one shared JSON

Each writer owns exactly ONE path and rewrites only that path. There is no
cross-process read-modify-write anywhere in this design, so class-A TOCTOU
(named in `runtime-file.mjs`'s header as a recurring sidecar defect) cannot
occur even under `K >= 2` parallel dispatch, where a shared-file design would
silently lose one role's entry at every collision.

Slot name: `hb-<ref>__<role>[__<slot>].json`, each component passed through
`[^A-Za-z0-9._-] -> '-'` and capped at 64 characters. A component that
sanitizes to the empty string is a usage error (D4), never a nameless file.
CORRECTED post-freeze (2026-09-03, amendment item 2): the frozen text omitted
the `hb-` prefix, which did not exist at freeze time. It is load-bearing, not
cosmetic. `AAI_HEARTBEAT_DIR`/`--dir` is a first-class override, so the
directory is CALLER-NAMED and may hold files this feature does not own; the
prefix is what the class-D GC sweep and the `read` listing are bounded BY.
Without it the sweep ran with an empty prefix — an unbounded 24-hour GC over
whatever directory the caller named, which deleted an operator's own files
while exiting 0 with a success line (code review, BLOCKING). Abandoned
`atomicWrite` temps are named `<slot-file>.tmp.<pid>.<seq>` and so inherit the
prefix, which is why the sweep still reaches them.

### D3 — Payload

```json
{
  "ref_id": "role-progress-heartbeat",
  "role": "Validation",
  "message": "full sweep round 2 of 3",
  "updated_at": "2026-09-03T05:41:12.123Z",
  "pid": 12345,
  "worktree": "/Users/ales/Projects/aai-change-heartbeat"
}
```

The four fields the intake's AC-001 names, plus `pid` and `worktree` — the two
fields that tie the signal to a real process rather than to narration. They
identify A writer, not the dispatched one; see the corrected boundary in the
D-problem statement above.

### D4 — Two failure grades, deliberately separated

- **USAGE (exit 2, loud).** A caller that cannot identify itself is a wiring
  bug and must surface at implementation/test time, not degrade into silence:
  missing `--ref`, `--role`, or `--message`; a component that sanitizes empty;
  a `--message` that is empty after sanitization; an EMPTY `--dir`
  (`path.resolve("")` is the current directory, so accepting it aims the write
  and its GC at wherever the caller stands — added post-freeze, amendment
  item 2).
- **RUNTIME DEGRADE (exit 0, named note on stderr).** No git, no repo,
  unwritable directory, GC failure. The role's own outcome must never move
  because of a heartbeat, so every runtime condition exits 0 with
  `heartbeat: degraded — <reason>` and writes nothing. Absence degrades to
  today's silence, which is precisely the intake's constraint.

`read` is exit 0 in every case including a corrupt slot, per Constitution
article 4 (degrade AND report): a corrupt slot is NAMED in the output, never
dropped silently and never read as "nothing there" (class B).

### D5 — No stale/stuck verdict

`read` prints each slot's `age_seconds`, a fact. It does NOT label a slot
"stale" or "stuck" and defines no threshold: the intake explicitly defers
stuck-detection ("this change only needs to make the raw signal available").
Inventing a threshold here would also be the first step toward something a gate
could learn to read.

### D6 — Never gates anything

The intake cites the Metrics-Flush/SKILL_PR collision (SPEC-0163, PR #334) as
the anti-pattern: an advisory signal a gate learned to read became a blocker
nobody intended. Spec-AC-08 makes "no gate reads this" a MECHANICAL, failable
check, not a promise in prose. CORRECTED post-freeze (2026-09-03, amendment
item 2): it was first written as a NAMED LIST of gate scripts, and a planted
reference in `lane-gate.mjs` — a gate the list did not name — left it green
(code review, mutation-proved). The check is now DENY-BY-DEFAULT over every
`.mjs`/`.sh`/`.ps1` under `.aai/scripts/` with a ONE-file allowlist
(`heartbeat.mjs` itself), so a gate added tomorrow is covered without anyone
remembering to extend a list.
NARROWED post-freeze (2026-09-03, amendment item 2 round 3): the allowlist was
two files, the second being `generate-live-status.mjs`. It is dropped. That file
has zero heartbeat references today, this spec's own "Positioning" section calls
the panel seam "NOT built here, NOT a follow-up obligation", and it is a
674-line `core:` script — the file in the corpus most likely to grow one. A
gate-shaped read planted in it left the suite green (validation, mutation-proved),
so pre-authorising the unbuilt seam bought nothing and cost the only coverage
that would have caught it. If the panel is ever built, the allowlist gains one
line that day, with a reason attached.

### D7 — Shared primitives, not a bespoke lifecycle

`heartbeat.mjs` uses `.aai/scripts/lib/runtime-file.mjs`: `atomicWrite` (class
E, torn write), `loadOrDegrade` (class B, corrupt-read-as-empty) and
`reapAsides` (class D, orphan GC). Its header names a bespoke re-implementation
a code-review BLOCKING finding; this sidecar complies. `claimExclusive` and
`isStale` are NOT used — there is no lease and no staleness verdict here (D5).

### D8 — Exactly one role prompt is wired

`.aai/VALIDATION.prompt.md` only, at step 5's per-round boundary (`c2 SUITE
SCOPE PER ROUND`), because its full-sweep rounds are the most reproducibly long
operation observed. Wiring every role prompt at once would multiply the
prompt-diet cost across a corpus with almost no headroom while proving nothing
the one wiring does not already prove. The other role prompts are a later,
separately-priced decision.

## Implementation strategy
- Strategy: hybrid
- Rationale: `heartbeat.mjs` is a new writer/reader whose whole value is in its
  REFUSED and DEGRADED paths (empty-after-sanitization message, unwritable dir,
  absent git, corrupt slot) — each needs its RED before the accepting case
  exists, or the component ships prose that contradicts its own code. The
  companion wiring (PROFILES.yaml classification, suite-map row, prompt-diet
  ledger true-up, the VALIDATION prompt sentence) is loop work whose failure is
  already caught by existing suite arms, and has no meaningful RED to stage.
- STATE currently records `implementation_strategy.selected: tdd` with
  `source: docs/specs/SPEC-DRAFT-spec-metrics-flush-invalidates-pr-precondition.md`
  — that is the PREVIOUS scope's spec-sourced choice, not an intake choice for
  this ref, and the intake's `## Notes` carries no
  `Implementation mode (user choice):` line. It is therefore re-decided here
  rather than inherited.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound; touches the shared prompt corpus and the
  prompt-diet ledger whose byte pin reddens other suites, and adds rows to
  `PROFILES.yaml` and `suite-map.yaml` that other suites assert against.
  Isolation keeps that blast radius off the main checkout.
- User decision: undecided
- Base ref: main @ 4774e90
- Worktree branch/path: `change/role-progress-heartbeat` @ `/Users/ales/Projects/aai-change-heartbeat` (already created)
- Inline review scope: n/a

## Acceptance Criteria Mapping

- Spec-AC-01 (intake AC-001, AC-003): WHEN a heartbeat is written from a LINKED
  WORKTREE the system SHALL make it readable by a single `read` invocation run
  from the MAIN worktree of the same repository.
  Verification: fixture repo with a real `git worktree add`; write from the
  worktree, `read` from the main checkout; stdout names the slot.
- Spec-AC-02 (intake AC-003): WHEN `read` runs against a repository where no
  heartbeat has ever been written the system SHALL print exactly
  `heartbeat: none recorded` and exit 0.
  Verification: `node .aai/scripts/heartbeat.mjs read` on a fresh fixture;
  `echo $?` is 0 and stdout matches the literal.
- Spec-AC-03 (intake AC-001): WHEN two different roles write concurrently the
  system SHALL preserve both slots, and a second write for the same slot SHALL
  replace only that slot.
  Verification: two backgrounded writes, then `read --json`; `.slots` length 2.
- Spec-AC-04: WHEN `--message` carries control or bidi characters the system
  SHALL store a sanitized message, SHALL truncate at 200 characters, and WHEN
  the message is empty after sanitization SHALL refuse with exit 2 and the
  literal text `heartbeat: --message is empty after sanitization`.
- Spec-AC-05 (intake AC-004 best-effort clause): WHEN the heartbeat directory
  is unwritable, or git is unavailable, `write` SHALL exit 0 and print
  `heartbeat: degraded — <reason>` on stderr and write nothing.
- Spec-AC-06: WHEN one slot file is corrupt `read` SHALL name it in its output
  and still print every readable slot, exiting 0.
- Spec-AC-07: WHEN `write` runs it SHALL reap every file carrying this
  feature's `hb-` prefix whose mtime is more than 24 hours from now, SHALL keep
  prefixed files inside that window, and SHALL leave untouched every file that
  does not carry the prefix.
  (Third clause added post-freeze, amendment item 2: only the reap/keep halves
  were testable as written, and the gap shipped as a BLOCKING defect.
  NARROWED post-freeze, amendment item 2 round 3: it read "leave untouched
  every file in the directory it did not itself write", which validation
  FALSIFIED by reproduction five ways — `--dir .`, `--dir ..`, a relative dir, a
  symlinked dir and `AAI_HEARTBEAT_DIR` each deleted an `hb-`-named file this
  script never wrote, at exit 0 with a success line. The mechanism is bounded by
  PREFIX, not by ownership, and the AC now says so. Shape-gating the reap on
  `isSlotShape` was considered as the alternative fix and rejected: it cannot
  cover the `<slot>.tmp.<pid>.<seq>` temps the sweep exists to collect, and is
  more machinery than the risk warrants. The operational consequence is stated
  in R6.
  FIRST CLAUSE likewise corrected in the same round: it said "older than 24
  hours", but `reapAsides` delegates to `isStale`, whose window is SYMMETRIC
  (stale iff `|now - mtime| > window`) so a FUTURE-dated `hb-` file is reaped
  too — reproduced at +48 h. That is deliberate library semantics, not a defect:
  `runtime-file.mjs` classes C+F exist so a far-future mtime can never wedge a
  GC. It was simply undocumented.)
  Verification: TEST-011 asserts all four outcomes together — a 25-hour-old slot
  reaped, a 1-hour-old slot kept, an UNPREFIXED foreign file surviving, and a
  PREFIXED foreign file (30 h old) plus a prefixed future-dated file (+48 h)
  both reaped.
- Spec-AC-08 (intake Constraints, anti-SPEC-0163): the gate-script corpus SHALL
  contain zero references to the heartbeat outside a named allowlist, and this
  scope SHALL add no `.gitignore` / `RUNTIME_IGNORE.list` /
  `DOCS_AI_CANON.list` entry.
- Spec-AC-09 (intake AC-002): `.aai/VALIDATION.prompt.md` SHALL carry a live,
  greppable `heartbeat.mjs write` invocation at its per-round boundary together
  with wording that its outcome never changes the verdict, and SHALL be the
  ONLY role prompt so wired.
- Spec-AC-10: the three companion obligations SHALL be satisfied — prompt-diet
  ledger entry at the MEASURED byte growth plus the TEST-012 pin bump,
  `PROFILES.yaml` classification of the new file, and a `suite-map.yaml` row
  for the new suite.

## Constitution deviations

None.

Article 3 (Portability) reading, recorded so nobody has to re-derive it: the
heartbeat is plain JSON written by Node stdlib and is tri-platform, but it is
NOT git-diffable because it lives under `.git/`. That is not a deviation —
article 3 governs DURABLE artifacts, and this is ephemeral runtime state of the
same class as `docs/ai/locks/` and `docs/ai/hitl-channel.json`, both of which
are likewise unreadable from git history by design. Article 4 (degrade and
report) is honoured by D4 and Spec-AC-05/06. Article 6 (single-writer STATE) is
untouched: this scope writes no STATE.yaml and needs no carve-out in
`.aai/SUBAGENT_CONTRACT.md`.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                                                                | Status  | Evidence | Review-By | Notes                                                        |
|------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------|-----------|--------------------------------------------------------------|
| Spec-AC-01 | WHEN a heartbeat is written from a linked worktree the system SHALL make it readable by one read invocation run from the main worktree of the same repository | done | TEST-001/002, tests/skills/test-aai-heartbeat.sh; real git worktree add; re-derived independently in validation rounds 1 and 3 | tdd:2026-09-03 | the load-bearing seam; real git worktree, never a stand-in     |
| Spec-AC-02 | WHEN read runs where no heartbeat was ever written the system SHALL print exactly heartbeat: none recorded and exit 0                                        | done | TEST-003, tests/skills/test-aai-heartbeat.sh; cold read reproduced by hand under a git-less PATH | tdd:2026-09-03 | cold-start; an error here would be the intake's named defect   |
| Spec-AC-03 | WHEN two roles write concurrently the system SHALL preserve both slots and a repeat write SHALL replace only its own slot                                    | done | TEST-004, tests/skills/test-aai-heartbeat.sh; one file per slot, no cross-process read-modify-write | tdd:2026-09-03 | per-slot files, so no cross-process read-modify-write exists   |
| Spec-AC-04 | WHEN --message carries control or bidi characters the system SHALL sanitize and truncate at 200, and WHEN it is empty after sanitization SHALL refuse exit 2 | done | TEST-005/006/007, tests/skills/test-aai-heartbeat.sh; traversal and bidi probes in validation round 1 | tdd:2026-09-03 | the REJECTED input plus the component's own literal message    |
| Spec-AC-05 | WHEN the heartbeat directory is unwritable or git is unavailable write SHALL exit 0, print a named degrade note, and write nothing                            | done | TEST-008/009/018, tests/skills/test-aai-heartbeat.sh; TEST-018 mutation-proved non-tautological in validation round 2 | tdd:2026-09-03 | best-effort clause; absence degrades to today's silence        |
| Spec-AC-06 | WHEN one slot file is corrupt read SHALL name it in its output, still print every readable slot, and exit 0                                                  | done | TEST-010, tests/skills/test-aai-heartbeat.sh; loadOrDegrade plus isSlotShape | tdd:2026-09-03 | class B; a damaged slot is never read as nothing there         |
| Spec-AC-07 | WHEN write runs it SHALL reap every hb- prefixed file more than 24 hours from now, keep prefixed files inside that window, and leave untouched every file without the prefix | done | TEST-011, tests/skills/test-aai-heartbeat.sh; all four GC outcomes plus temp, directory and symlink third-bound probes reproduced in validation round 3 | tdd:2026-09-03 | class D orphan GC via reapAsides; the bound is the hb- prefix and NOT ownership, and the window is symmetric so a future-dated prefixed file is reaped too |
| Spec-AC-08 | The gate-script corpus SHALL contain zero heartbeat references outside a named allowlist and this scope SHALL add no gitignore, RUNTIME_IGNORE or DOCS_AI_CANON entry | done | TEST-012/013, tests/skills/test-aai-heartbeat.sh; deny-by-default over 118 of 119 entries, allowlist path-bound at 64718ad after a nested plant passed the basename form | tdd:2026-09-03 | anti-SPEC-0163, deny-by-default rather than an enumerated list |
| Spec-AC-09 | .aai/VALIDATION.prompt.md SHALL carry a greppable heartbeat write invocation plus never-changes-the-verdict wording and SHALL be the only role prompt wired  | done | TEST-014, tests/skills/test-aai-heartbeat.sh; VALIDATION.prompt.md step 5 c3 | tdd:2026-09-03 | one proof wiring; other role prompts priced separately later   |
| Spec-AC-10 | The prompt-diet ledger, PROFILES.yaml and suite-map.yaml companion obligations SHALL be satisfied with the MEASURED byte growth                             | done | TEST-015/016/017, tests/skills/test-aai-prompt-diet.sh and the layer-profiles and hygiene-pack suites; 379 B credited 1:1, pin 10324, headroom 4 of 2048 | tdd:2026-09-03 | measured by Implementation; no byte number is written here     |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components:
- NEW `.aai/scripts/heartbeat.mjs` — Node stdlib only, imports
  `./lib/runtime-file.mjs` (`atomicWrite`, `loadOrDegrade`, `reapAsides`) and
  `./lib/cli-pipe-guard.mjs` (`exit`, `runMain` — the CLI-output-survives-a-pipe
  convention `hitl-channel.mjs` already follows). Subcommands:
  - `write --ref <R> --role <Role> --message <text> [--slot <token>] [--dir <path>]`
  - `read [--json] [--ref <R>] [--dir <path>]`
  No third subcommand: no `clear`, no lease, no staleness verdict (D5). A role
  signals completion by writing a terminal message; `read`'s age column then
  reads honestly, and the 24 h GC removes the rest.
- EDIT `.aai/VALIDATION.prompt.md` — one short block at step 5 after `c2`.
- EDIT `.aai/system/PROFILES.yaml` — `.aai/scripts/heartbeat.mjs` into `core:`.
  Rationale for `core` rather than `extended`: it is wired into
  `.aai/VALIDATION.prompt.md`, itself a `core` prompt, and PROFILES' own
  classification rule puts a core prompt's import closure in `core`. A core
  prompt naming a file absent from the core profile would be drift even though
  the heartbeat's own absence is harmless.
- EDIT `tests/skills/suite-map.yaml` — new `suites.aai-heartbeat` row with
  globs `.aai/scripts/heartbeat.mjs` and `.aai/VALIDATION.prompt.md` (the
  selector matches `tests/skills/test-aai-heartbeat.sh` implicitly).
- EDIT `tests/skills/lib/prompt-diet-ledger.sh` — one `JUSTIFIED_ADDITIONS`
  entry, and `tests/skills/test-aai-prompt-diet.sh` — the TEST-012 pin, both at
  the MEASURED growth (see "Companion obligations" below).
- NEW `tests/skills/test-aai-heartbeat.sh`.
- EDIT `CHANGELOG.md` — one `## [unreleased] — <title>` heading entry.

Data flow:
`role (in worktree W)` -> `heartbeat.mjs write` -> `git -C <W> rev-parse
--git-common-dir` -> `<main>/.git/aai/heartbeat/<slot>.json` (atomicWrite)
-> `heartbeat.mjs read` run in main checkout M or in any worktree of the same
repo -> stdout.

### Edge cases

- `--git-common-dir` is RELATIVE in the main worktree (`.git`, or `../.git`
  from a subdirectory) and ABSOLUTE in a linked worktree. MEASURED, git 2.50.1.
  Always `path.resolve(root, out)`; a `path.join` is wrong in a LINKED
  WORKTREE (see the corrected D1 bullet — this line was inverted at freeze).
- Repo reached through a symlink: `fu-ismain-symlink-realpath` is an open
  registry item about `path.resolve(process.argv[1]) === fileURLToPath(...)`
  main-guards failing under a symlinked checkout. `heartbeat.mjs` must not
  reintroduce it; use the `runMain` helper from `./lib/cli-pipe-guard.mjs`
  rather than hand-rolling the guard.
- Not a git repository, or `git` absent from PATH: runtime degrade (D4),
  exit 0, nothing written; `read` prints `heartbeat: none recorded`.
- Separate CLONE (not a worktree): a different `.git`, so a heartbeat written
  there is invisible here. Accepted — see Residual risks R1.
- A `--message` longer than 200 characters is truncated, not refused: a chatty
  role must not become a failing role.
- FIXTURE TRAP (cost a full CI cycle this session, pin it in the suite): a bare
  repo created with `git init --bare` takes its HEAD from the PER-MACHINE
  `init.defaultBranch`, so anything later cloned from it is green locally and
  red on CI. This suite creates NON-bare fixtures, and must still run
  `git -C "$repo" symbolic-ref HEAD refs/heads/main` immediately after every
  `git init` so `git worktree add` has a deterministic branch on every machine.
- SUITE SHELL TRAP: the suite runs under the framework's own `set -euo
  pipefail`. A bare `rc=$?` after a command, and a `grep | head` pipeline, both
  die on CI only. Capture as `cmd; rc=$?` inside an `if` or with `|| rc=$?`,
  and never pipe into `head` on the assertion path.
- The suite must not write the shipping repository — build every fixture under
  the suite's own `TEST_DIR` and set `AAI_HEARTBEAT_DIR` for any case that is
  not specifically exercising the git resolution.

### Companion obligations (measured by Implementation, NOT stated here)

1. `.aai/VALIDATION.prompt.md` grows the prompt corpus. Implementation MUST
   measure the growth of the live `.aai/*.prompt.md` glob with `wc -c` before
   and after, add ONE `JUSTIFIED_ADDITIONS` entry whose leading `<bytes>` field
   equals that MEASURED delta 1:1, and bump the `TEST-012` pin in
   `tests/skills/test-aai-prompt-diet.sh` by exactly the same amount so
   headroom is unchanged. Headroom is currently a handful of bytes against
   `HEADROOM_CAP=2048`; a copied or estimated number will fail TEST-010/012.
   NO BYTE NUMBER IS WRITTEN IN THIS SPEC on purpose — a number frozen here
   would be wrong by the time the prose is final.
2. `.aai/scripts/heartbeat.mjs` is a NEW `.aai/**` file:
   `.aai/system/PROFILES.yaml` `core:` list. `test-aai-layer-profiles.sh`
   TEST-001 asserts 100% classification against the LIVE tree.
3. `tests/skills/test-aai-heartbeat.sh` is a NEW suite file:
   `tests/skills/suite-map.yaml` needs a `suites.aai-heartbeat` row.
   `test-aai-hygiene-pack.sh` asserts one row per `test-aai-*.sh` on disk.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description                                                                                                                | Status  |
|----------|------------|-------------|---------------------------------------|----------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-heartbeat.sh    | real fixture repo plus real git worktree add; write from the worktree, read from the main checkout, stdout names the slot     | green   |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-heartbeat.sh    | git-common-dir resolves to one absolute path from the main root, from a subdirectory of it, and from the linked worktree      | green   |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-heartbeat.sh    | read on a fresh fixture prints exactly heartbeat: none recorded, exit 0; read --json prints empty slots and empty degraded    | green   |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-heartbeat.sh    | two backgrounded writes for different ref-role pairs; read --json shows both, then a repeat write replaces only its own slot  | green   |
| TEST-005 | Spec-AC-04 | unit        | tests/skills/test-aai-heartbeat.sh    | a message with C0, C1 and bidi bytes stores sanitized text; a 300-character message stores exactly 200                        | green   |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-heartbeat.sh    | REJECTED input: a control-characters-only message exits 2 and stderr matches the literal empty after sanitization message     | green   |
| TEST-007 | Spec-AC-04 | unit        | tests/skills/test-aai-heartbeat.sh    | REJECTED input: a missing --ref and a --ref that sanitizes empty each exit 2 with their own literal message                   | green   |
| TEST-008 | Spec-AC-05 | unit        | tests/skills/test-aai-heartbeat.sh    | DEGRADED input: an unwritable AAI_HEARTBEAT_DIR makes write exit 0, print the named degrade note, and create no file          | green   |
| TEST-009 | Spec-AC-05 | unit        | tests/skills/test-aai-heartbeat.sh    | DEGRADED input: with git absent from a stubbed PATH and no AAI_HEARTBEAT_DIR, write exits 0 and read prints none recorded     | green   |
| TEST-010 | Spec-AC-06 | unit        | tests/skills/test-aai-heartbeat.sh    | one slot file of invalid JSON plus one valid slot; read exits 0, names the corrupt slot, and still prints the valid one       | green   |
| TEST-011 | Spec-AC-07 | unit        | tests/skills/test-aai-heartbeat.sh    | a slot touched to 25 hours old is reaped by the next write, a 1-hour-old slot is kept, two 30-hour-old UNPREFIXED foreign files in the same caller-named directory survive, two 30-hour-old hb- PREFIXED foreign files and one hb- prefixed file dated +48 h are REAPED (the honest bound, extended round 3), and an empty --dir is refused exit 2 before it can sweep the cwd | green   |
| TEST-012 | Spec-AC-08 | integration | tests/skills/test-aai-heartbeat.sh    | zero heartbeat references across every .mjs, .sh and .ps1 under .aai/scripts outside the ONE-file allowlist heartbeat.mjs (generate-live-status.mjs dropped from it in round 3), with a corpus-size floor so an empty sweep cannot pass vacuously | green   |
| TEST-013 | Spec-AC-08 | unit        | tests/skills/test-aai-heartbeat.sh    | git diff of .gitignore, .aai/system/RUNTIME_IGNORE.list and .aai/system/DOCS_AI_CANON.list against the base ref is empty      | green   |
| TEST-014 | Spec-AC-09 | unit        | tests/skills/test-aai-heartbeat.sh    | VALIDATION.prompt.md carries a live heartbeat.mjs write line with --ref, --role and --message plus never-changes-the-verdict wording, and it is the only .aai/*.prompt.md that names heartbeat.mjs | green   |
| TEST-015 | Spec-AC-10 | integration | tests/skills/test-aai-prompt-diet.sh  | existing TEST-010 and TEST-012 arms re-pinned to the measured growth; the ledger sum equals the pin                           | green   |
| TEST-016 | Spec-AC-10 | integration | tests/skills/test-aai-layer-profiles.sh | existing TEST-001 arm: .aai/scripts/heartbeat.mjs is classified, union equals the live tree                                 | green   |
| TEST-017 | Spec-AC-10 | integration | tests/skills/test-aai-hygiene-pack.sh | existing arm: suites.aai-heartbeat row exists for tests/skills/test-aai-heartbeat.sh                                          | green   |
| TEST-018 | Spec-AC-05 | unit        | tests/skills/test-aai-heartbeat.sh    | DEGRADED input: an AAI_HEARTBEAT_DIR pointing at a regular file makes the orphan sweep fail ENOTDIR, so write exits 0 with its own orphan sweep failed note and writes nothing (added post-freeze, amendment item 2 — D4 named GC failure as a degrade branch but no arm covered it) | green   |

Test status values: pending -> red -> green

### RED observation plan (hybrid)

RED-first applies to TEST-001 through TEST-014 (the `heartbeat.mjs` behaviour,
including every REJECTED and DEGRADED arm). Each is observed FAILING against a
tree where `.aai/scripts/heartbeat.mjs` does not exist or where the specific
refusal is not yet implemented, and the run is recorded at
`docs/ai/tdd/role-progress-heartbeat-red.log` with a `RED_CLASS` line
(`node .aai/scripts/tdd-evidence-check.mjs --red <log>` must not classify it
`infra_fail`; a suite failing only because the script is missing is exactly the
`infra_fail` shape, so stage each arm against a stub that EXISTS and returns
the wrong answer, not against an absent file).

TEST-015 through TEST-017 are loop-lane arms in pre-existing suites: their RED
is the natural failure of the untouched pin (a diet pin that no longer matches
the ledger sum, an unclassified file, a missing suite row). Observed, exit codes
recorded, storage optional per the `loop` row of `### Evidence by strategy`.

### Seams this plan crosses

| Seam | Producer | Consumer | Crossing test |
|---|---|---|---|
| worktree boundary | write in a linked worktree | read in the main checkout | TEST-001, real worktree, no stand-in |
| heartbeat outcome to role verdict | heartbeat write failure | Validation's own verdict | TEST-008 plus TEST-014's wording pin |
| new .aai file to layer profile | heartbeat.mjs | PROFILES.yaml classification | TEST-016 |
| prompt bytes to diet ledger | VALIDATION.prompt.md edit | TEST-012 pin | TEST-015 |
| new suite file to selector map | test-aai-heartbeat.sh | suite-map.yaml hygiene pin | TEST-017 |
| advisory signal to gates (NEGATIVE seam) | heartbeat file | any gate script | TEST-012 asserts the crossing does not exist |

## Verification

- `bash tests/skills/test-aai-heartbeat.sh` -> exit 0
- `bash tests/skills/test-aai-prompt-diet.sh` -> exit 0
- `bash tests/skills/test-aai-layer-profiles.sh` -> exit 0
- `bash tests/skills/test-aai-hygiene-pack.sh` -> exit 0
- `node .aai/scripts/select-suites.mjs --files-from <changed files>` for the
  intermediate rounds; ONE `bash tests/skills/test-framework.sh` full sweep
  before the close ceremony (`.aai/VALIDATION.prompt.md` step 5 c2).
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0164-spec-role-progress-heartbeat.md`
- `node .aai/scripts/docs-audit.mjs --gate <SPEC-ID>` -> exit 0 at close
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract

- ref_id: `role-progress-heartbeat`
- RED log: `docs/ai/tdd/role-progress-heartbeat-red.log` (TEST-001..014)
- Green runs: `tests/skills/results/<run>` per suite, with exit codes
- Review scope: the explicit path list in `## Isolation and review` above
- Commit SHA / diff range recorded at hand-off

### Evidence by strategy

Strategy is `hybrid`, so the `tdd / hybrid` row applies: a stored RED artifact
per AC-gating test plus the full verification matrix, for the TDD-lane tests
named above. The three companion arms run in the loop lane (green runs plus
observed RED, storage optional).

## Residual risks

- R1 — A separate CLONE of the repository has its own `.git`, so a heartbeat
  written in clone A is invisible in clone B. ACCEPTED: the intake's
  requirement is worktree-independence, which this design meets exactly; a
  cross-clone signal would need a machine-global path outside any repository
  and was not asked for.
- R2 — A role that never calls `write` produces no signal at all. ACCEPTED and
  intended: absence degrades to today's silence, never to a new failure mode.
  Only `.aai/VALIDATION.prompt.md` is wired in this scope (D8), so the other
  long roles remain silent until separately priced.
- R3 — No automated test can prove an LLM role actually emits the heartbeat at
  runtime; TEST-014 pins the INSTRUCTION, not the behaviour. This is the same
  residual every prompt-wiring scope in this repo carries, and the intake's own
  verification section proposes a manual multi-round observation. Recorded here
  rather than papered over.
- R4 — The `message` text is the role's self-report and can be wrong or stale;
  only `updated_at`, `pid` and `worktree` are machine-written. Stated in
  "Problem this solves, stated honestly" so no consumer over-trusts the prose.
- R5 — `fu-orchestrator-monitor-uses-gnu-find` remains open: the orchestrator's
  existing liveness probe is still a fragile `find -newermt` call. This scope
  gives it a better signal but does not rewrite the probe.
- R6 (added post-freeze, amendment item 2 round 3) — THE GC IS BOUNDED BY
  PREFIX, NOT BY OWNERSHIP. A file named `hb-*` that this feature never wrote,
  living in a directory the caller named via `--dir` / `AAI_HEARTBEAT_DIR` and
  whose mtime is more than 24 hours from now in either direction, is DELETED by
  the next `write`, at exit 0 with a success line. Reproduced five ways
  (`--dir .`, `--dir ..`, a relative dir, a symlinked dir, `AAI_HEARTBEAT_DIR`).
  ACCEPTED, with the mitigation being that Spec-AC-07, the `heartbeat.mjs`
  header, `CHANGELOG.md` and TEST-011 now all state the prefix bound plainly
  instead of promising an ownership bound the code does not implement: anyone
  pointing this feature at a shared directory must keep `hb-` free there. The
  stronger mechanism (shape-gating the reap on `isSlotShape`) was priced and
  declined — it cannot cover the `<slot>.tmp.<pid>.<seq>` temps the sweep exists
  to collect, so it would trade a documented bound for an undocumented hole.
- R7 (added post-freeze, amendment item 2 round 3) — PRE-RELEASE ORPHANS. Slot
  files written by the UNPREFIXED build of `heartbeat.mjs` (before the `hb-`
  prefix landed) are, in the real default directory
  `<git-common-dir>/aai/heartbeat/`, now invisible to `read` AND outside their
  own GC's prefix bound, so nothing will ever collect them. IMMATERIAL in
  practice and recorded as a choice rather than left as an accident: no merged
  tree ever ran the unprefixed version, so the only directories that can hold
  such files are the development checkouts of this ride. Sweeping them is a
  one-line `rm` an operator may run; no code compensates for a state no released
  version could produce.

## Registry items closed by this scope

None.

Scanned `node .aai/scripts/follow-ups.mjs list` (97 open, 300 total) for this
scope's subjects. Two open items TOUCH the subject and are deliberately NOT
closed, with reasons:

- `fu-orchestrator-monitor-uses-gnu-find` (P2, `suites-run-in-a-disposable-worktree`)
  — the orchestrator's liveness check for running agents used GNU `find`
  syntax that this host rejects, so a silent command failure was reported as
  "zero writes". Same subject: the orchestrator has no trustworthy way to see
  whether a dispatched role is alive. NOT closed, because closing it means
  editing the orchestrator's probe, and this scope's declared surface is one
  role prompt plus one new script (D8). The heartbeat makes the eventual fix
  cheaper by giving that probe a first-class signal to read instead of mtimes.
- `fu-orchestrator-does-not-watch-ci` (P2, `ride-cost-readout`) — the
  orchestrator stops after pushing a PR instead of watching CI. Adjacent in
  spirit (an operator waiting blind) but a different subject: CI polling, not
  in-role progress. NOT closed and not touched.

## Notes

This document defines HOW, not WHAT/WHY. It does not define workflow.
