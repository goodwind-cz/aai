---
id: spec-deslop-scope-and-unrequested-engine
type: spec
number: 132
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md
  rfc: null
  pr:
    - 260
  commits:
    - c824367
---

# Spec — deslop: scope becomes a parameter, and class 4 gets an engine

SPEC-FROZEN: true

## Amendment (owner decision, 2026-08-15T08:14:24Z)

This is a FROZEN spec, amended under explicit owner authority — not a quiet
rewrite. Authority: `docs/ai/decisions.jsonl` `hitl_decision` record,
`ref_id: deslop-scope-and-unrequested-engine`, timestamp
`2026-08-15T08:14:24.000Z`, actor `ales_holubec.net`.

The class-4 detector's original premise ("does any requirement document
mention this symbol?") only holds for CONTRACT surfaces — things a human
types or sets (a flag, a config key). An internal helper is absent from
every spec BY DESIGN, so its absence carries no signal; the original D3 list
included three internal-symbol kinds (`mjs-export`, `sh-func`, `ps1-func`)
that violated this premise. Measured evidence at the time of the decision:
those three kinds accounted for 128 + 64 + 53 = 245 of 390 real-tree
candidates, matching the 245 internal helpers the round-4 code review
counted by hand; `yaml-key` (6 candidates) was the one kind where
suppression actually discriminated.

CHANGE, applied below: D3's extractor-kind set narrows from five kinds to
two — `cli-flag` and `yaml-key`, both contract surfaces. `mjs-export`,
`sh-func` and `ps1-func` are REMOVED outright (not gated behind a flag —
see D3's "Why removal, not an opt-in flag" note). `cli-flag` ALSO gets a
precision fix here, closing the separately-tracked follow-up
`fu-deslop-cliflag-kind-precision`: two syntactic (not per-flag) exclusions
— CSS custom properties and flags this code merely passes to a subprocess
it invokes — are applied before a raw regex match becomes a candidate.

Every AC, Test Plan row and citation below that depended on the five-kind
list is updated in place to describe the two-kind list; nothing about the
scope parameter (`--diff`/`--all`), the corpus resolution (D2) or the
report-only guarantee (D5/AC-05) changes. `SPEC-FROZEN: true` is preserved —
this amendment is additive-with-disclosure, not a silent rewrite of history.

## Links
- Requirement: docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md
- Source finding: docs/specs/RESEARCH-0001-spec-kit-comparative.md F3 (the one
  detection direction we lack is `unrequested`) and F1 (spec-lint is the wrong
  host: it is scoped to in-flight specs at the freeze boundary)
- Prompt rewritten: `.aai/SKILL_DESLOP.prompt.md`
- Suite that already pins that prompt: tests/skills/test-aai-advisory-skills.sh
  (TEST-004 line budget, TEST-005 slop-class table, TEST-006 rules block,
  TEST-012 advisory isolation)
- Prompt-corpus ledger: tests/skills/lib/prompt-diet-ledger.sh (TEST-012
  checkpoint -5262, headroom 1622 within cap 2048)
- Layer classification: `.aai/system/PROFILES.yaml` (enforced against the live
  tree by tests/skills/test-aai-layer-profiles.sh TEST-001)
- CI selection map: tests/skills/suite-map.yaml (row `aai-advisory-skills`
  already globs the deslop surfaces; the hygiene pin in
  tests/skills/test-aai-hygiene-pack.sh requires a row per suite file)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, zero
  dependencies; canonical test invocation
  `bash .aai/scripts/aai-run-tests.sh <command...>`)

## Ceremony level

Level 2 is the binding declaration, matching the intake's suggestion. The
scope adds a NEW executable surface (an engine other agents will run and act
on), rewrites a vendored prompt, moves four wrapper descriptions plus three
catalog surfaces, and carries three governance companions. That is neither a
docs-only edit (L0) nor a single-surface fix (L1). It is not L3 either: no
path in this scope appears in `protected_paths_l3` in docs/ai/docs-audit.yaml
(state engine, allocator, pre-commit guards, WORKFLOW.md, CONSTITUTION.md are
all untouched), so the mandatory-L3 trigger does not fire and inflating to 3
would buy an operator merge checkpoint that this advisory, report-only surface
does not warrant. Full independent validation IS warranted, because the
engine's output is a judgment artifact a human will act on, and a detector
that quietly under-reports is worse than no detector.

## Summary

`/aai-deslop` has two gaps that share one fix. Its scope is hardcoded to the
current diff, and its class-4 row ("Unrequested features: behavior, flags, or
config no AC asked for") is a table entry that no code checks — class 4
happens only when the agent notices.

This scope makes scope an explicit parameter (`--diff`, `--all`, ASK when
unspecified — no default; D4 fails closed) and gives class 4 a mechanical
detector that both scopes drive with the same code, differing only in its
input set. The wide scope IS
RESEARCH-0001 F3: every check we own asks "is the requirement covered?";
nothing asks the reverse question about accumulated surface — does this code
answer to any requirement?

Everything here is report-only. The engine never writes a byte, `--all` never
edits at all, deslop stays advisory, and nothing in the workflow dispatches
it (the advisory-isolation invariant, pinned by
tests/skills/test-aai-advisory-skills.sh TEST-012, is preserved verbatim).

## Design decisions recorded at planning time (do not re-derive)

### D1 — the engine: `.aai/scripts/deslop-unrequested.mjs`

One new file, reachable from the prompt as a plain `node` invocation with no
build step and no dependency:

```
node .aai/scripts/deslop-unrequested.mjs --diff [--base <ref>] [--json]
node .aai/scripts/deslop-unrequested.mjs --all [--json]
```

Node stdlib only (docs/TECHNOLOGY.md). It reads files, shells out to `git`
for the `--diff` input, and writes to stdout. Named for what it detects
(class 4, unrequested surface) rather than for the skill, because the skill is
the only caller today and the detector is the durable half.

PROFILES classification: `extended`, beside `.aai/SKILL_DESLOP.prompt.md`.
The core profile is the workflow engine; an advisory detector reachable only
from an advisory prompt is not part of it.

### D2 — the requirement text, per scope (narrows intake assumption A1)

MATCH UNIT: an extracted symbol is SUPPRESSED when its exact token appears as
a whole word anywhere in the body text (frontmatter stripped) of any document
in the requirement corpus. Otherwise it is a candidate.

DELIBERATE NARROWING, recorded because the intake said otherwise: A1 proposed
"AC text". This spec matches against the FULL body of each requirement
document instead. Matching only AC-table cells would report every symbol the
spec's own Implementation plan named — a spec that says "add `parseAcTable`
to docs-model.mjs" in its plan and not in an AC cell would produce a finding
that is correct by the letter and useless in triage. The first `--all` run
over roughly 8.6k lines of scripts is a triage artifact whose only enemy is
noise. The direction of this deviation is toward FEWER findings, i.e. more
false negatives, which is the risk the intake already accepted and which this
scope quantifies rather than hides (D5, the suppressed count).

CORPUS SELECTION:

- `--diff`: the two documents naming this ride — `current_focus.spec_path`
  (when non-null) and `current_focus.primary_path`, read from
  docs/ai/STATE.yaml. BOTH, not just the spec: acceptance criteria routinely
  name a flag only by pointing at the intake's Desired Behavior section, and
  dropping the intake would manufacture findings for flags a human explicitly
  requested one document away.
- `--all`: every `docs/specs/**/*.md` whose frontmatter `type` is `spec` and
  whose `status` is `accepted`, `implementing` or `done`. That is A1's "frozen
  and done" set spelled as the three statuses that mean the requirement was
  agreed. `draft` and `proposed` are not yet agreed; `rejected`, `superseded`
  and `deferred` were withdrawn or replaced. Measured 2026-08-14: 131 of the
  133 files under docs/specs/ carry `type: spec`, and every one of them is
  `status: done`, so the selector is non-empty on the real tree today.

STATE reading is READ-ONLY and best effort. docs/ai/STATE.yaml is gitignored
(RFC-0001) and absent on a fresh CI checkout; the engine never writes it
(Constitution art. 6) and never throws on its absence — see D4.

### D3 — the surface scanned (intake assumption A2, made precise; NARROWED by
the 2026-08-15 amendment above)

Two extractor kinds, a closed list, all pattern-based. Both are CONTRACT
SURFACES — things a requirement is expected to name because a human types or
sets them directly:

| kind | files | extracted |
|---|---|---|
| cli-flag | `.aai/scripts/**/*.mjs`, `**/*.sh`, `**/*.ps1` | every long-flag token of the form two dashes plus a lowercase name, MINUS two syntactic exclusions (see "cli-flag precision" below) |
| yaml-key | `.aai/system/*.yaml` | column-0 top-level keys |

REMOVED by the amendment: `mjs-export` (`export function`/`const`/`let`/
`class` names and `export { ... }` members), `sh-func` (line-leading
`name()` definitions) and `ps1-func` (line-leading `function Name`
definitions). All three extracted INTERNAL symbols — helpers absent from
every spec by design, so their absence carried no signal; the amendment note
above has the measured evidence (245 of 390 real-tree candidates, exactly
matching the review's hand count of internal helpers).

WHY REMOVAL, NOT AN OPT-IN FLAG: the owner dispatch offered either. Removal
is simpler — no new argv surface, no "reachable but off by default" code
path to keep correct and tested, and no LIMITS-block caveat explaining why a
flag exists but defaults off. The Constitution's YAGNI article (art. 2)
argues for removal unless a concrete reason to keep the three kinds
reachable exists; none was found — nothing in this repo consumes an
internal-symbol unrequested-surface report, and the corpus-matching premise
that makes class 4 meaningful (D2) does not hold for symbols a spec is never
expected to name. If a concrete future need for internal-symbol scanning
appears, it is a new, separately-justified scope, not a flag flip.

cli-flag PRECISION (closes follow-up `fu-deslop-cliflag-kind-precision`): a
raw regex match is not automatically a flag this code OWNS. Three closed,
syntactic exclusions apply before a match becomes a candidate — none is a
per-flag stoplist (still forbidden by the NO STOPLIST rule below), because
all key off CONTEXT, not off any specific flag's name:
- Comment-only occurrence (added by round-5 remediation, V5-2 — see
  addendum below): a match whose position is inside a `//` (`.mjs`) or `#`
  (`.sh`/`.ps1`) comment on its own physical line is never extracted. Quote-
  aware (a `#`/`//` inside a string literal does not start a comment);
  single physical line only.
- CSS custom property: `--name: value` (declaration) or `var(--name)`
  (usage) in a generated stylesheet — these are style tokens, not CLI
  surface. Measured on the real tree: 30 of the original 139 cli-flag
  candidates (the exact figure the round-4 review measured).
- External-tool argument: a flag this code merely PASSES to a subprocess it
  invokes (git, gh, or any other external binary) is not a contract surface
  this code owns — the owning contract, if any, belongs to that external
  tool. Measured on the real tree: 35 of the original 139 (again the
  review's exact figure), including the review's named examples
  `--exclude-standard`, `--others`, `--git-common-dir`, `--left-right` and
  `--error-unmatch`. Detection is syntactic and DIFFERS by extension:
  - `.mjs`: a call literally named `git`, `tryGit` or `runGh` (this repo's
    established local-wrapper naming convention, verified across every
    script that shells out to git/gh), or a direct/pass-through call to a
    subprocess primitive whose resolved command is not `node` (this process
    invoking one of its OWN other scripts stays internal — the
    `--total`/`--orphans`/`--hash`/`--op` flags are this repo's OWN
    event-schema field names passed to `append-event.mjs`, not external-tool
    arguments, so the extractor correctly does NOT exclude them as external.
    V6-2 correction (round-6 validation, 2026-08-15): naming all four flags
    by name in THIS sentence is itself a corpus match, so on a live `--all`
    run they are in fact suppressed from the candidate list — the disclosed
    prose-suppression property (D2, `limits[1]`) applying to this document's
    own text, not a defect in the extractor or a contradiction of D2's
    intent). Round-5
    remediation (V5-2) additionally resolves ONE level of local array
    indirection: when the call's argument is a bare identifier (e.g.
    `runGh(ghArgs, ...)` or `execFileSync('gh', ghArgs)`), the identifier's
    own `const/let/var NAME = [...]` array-literal span (plus any
    `NAME.push(...)` call sites) is external too — closes the `--body`
    finding, where the real argv array was built a line above the call and
    the call's own paren span never contained it.
  - `.sh`/`.ps1` (documented here for the first time — round-5 validation
    V5-1 found the pre-amendment implementation existed only in code, as an
    undocumented, unsound hardcoded 10-binary-name list matched as a bare
    word ANYWHERE in a joined logical line, which fired inside comments and
    quoted strings and could sweep a script's OWN flag sitting before the
    external mention on the same line): a binary word (`git`, `gh`, `cargo`,
    `rg`, `wrangler`, `tsc`, `wsl`, `sed`, `npm` or `npx`) is recognized ONLY
    outside a comment and OUTSIDE a quoted string (both masked to spaces
    first — quote-masking understands a nested `$(...)` command
    substitution even inside a double-quoted string, since bash parses that
    as real code, e.g. `"$(git rev-parse --git-path ...)"`), using the same
    dash-inclusive word boundary as the corpus's whole-word matcher (so
    "the-git-package" is never mistaken for the word "git"). Each
    recognized occurrence opens a span running FORWARD from itself to the
    next unmasked `;`/`|`/`&`/real-newline — never backward — so a flag
    occurring BEFORE the external word on the same line (this script's own
    flag, e.g. a case-label immediately followed by `git ...`) is never
    inside the span, while a local "run the external tool" idiom (`if !
    command -v git`, `pkg_exec_command tsc --noEmit`) is still recognized
    because nothing requires the word to be the line's very first token.
    Backslash-newline (bash) and backtick-newline (PowerShell) line
    continuations are both collapsed to spaces first, so a multi-line
    invocation is one span. Process-name-based, not flag-based — the same
    "not a per-flag stoplist" shape as the `.mjs` signals above.

Measured effect of the round-5 remediation fix (V5-1 + V5-2) on the real
tree: candidates 75 -> 70, suppressed 444 -> 398 (baseline
`docs/ai/tdd/deslop-real-repo-all-baseline-20260815-round5-remediation.json`).
Six candidates that were pure noise (a flag named only in a comment, or
excluded only because the array holding it was one call away) are gone;
five candidates that the pre-fix bare-word-anywhere shell heuristic was
over-suppressing (a real `cargo`/`git` mention that only ever appeared
inside a quoted string) now correctly surface. Every one of the resulting
70 candidates is adjudicated — a one-sentence defense or an explicit
indefensible-and-why admission — in
`docs/ai/reports/deslop-candidate-adjudication-20260815.md`.

ADJUDICATION SUMMARY: moved out of this frozen spec into
`docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md` (2026-08-15
REMEDIATION dispatch, round-6 validation V6 disposition item 1 — the
PREFERRED option validation itself recommended). Rationale: that document is
`type: change`, `status: draft`, under `docs/issues/`, so it sits outside the
`--all` requirement corpus (D2 above is `docs/specs/**` with `type: spec`
only) on three independent grounds, at zero engine change. Keeping the table
folded into THIS document was itself an instance of the prose-suppression
property `limits[1]` discloses — corpus membership, not matcher logic,
suppressed the 10 rows it names; moving it restores them to `--all` output.
The table remains tracked content, just relocated; the underlying untracked
per-candidate walk is unchanged at
`docs/ai/reports/deslop-candidate-adjudication-20260815.md`.

NUMBER RECONCILIATION (V6-1, 2026-08-15 remediation). The round-5-remediation
baseline above (70/398,
`docs/ai/tdd/deslop-real-repo-all-baseline-20260815-round5-remediation.json`)
was measured BEFORE the ADJUDICATION SUMMARY table existed as tracked prose.
Folding the table into this frozen spec then suppressed 12 candidates, not
10 — the 10 rows the table named, plus 2 more (`hitl-channel.mjs:216 --body`,
`expert-fetch.sh:121 --body`) suppressed by a DIFFERENT sentence (the
array-indirection fix note above, which documents the fix by naming the flag
it closed) — dropping the live count to 58/410 (measured by round-6
validation and reconfirmed at the start of this remediation). Moving the
table out per this remediation measures 68/400 against the real tree
(`node .aai/scripts/deslop-unrequested.mjs --all --json`, run after the move
and after every other edit in this remediation, not predicted — 58 -> 68 is
exactly the 10 named rows returning, row-for-row verified): the 10 named rows
return; the 2 `--body` residuals stay suppressed by the separate sentence
above, which this remediation's scope did not touch.

NOT scanned, and named in the output so the omission is never silent:
`tests/**` (test code answers to a Test Plan, not to an AC), `docs/**`, the
four agent wrapper trees, and anything outside `.aai/`.

NO STOPLIST. Generic flags such as the ones meaning help, json or dry-run will
appear as candidates wherever no requirement document names them. A curated
exemption list is a whitelist mechanism with no measurement behind it
(Constitution art. 2), it would be the first thing to rot, and suppressing
rows is exactly the failure mode this detector exists to expose. Triage owns
that call once the number exists.

The `--diff` file set is the paths changed in the diff, intersected with the
globs above; a symbol counts only when its DEFINING line is an ADDED line in
`git diff --unified=0`. A symbol merely present on a context line was not
introduced by this change and is out of bounds — class 5's rule, applied
mechanically.

### D4 — asking for a scope, and the empty diff

TWO LAYERS, so a forgetful agent cannot turn "ask" into "assume":

1. MECHANICAL (the teeth). Invoked with no scope flag, the engine exits 2,
   prints a usage line naming both `--diff` and `--all`, and scans nothing —
   no git call, no file read, no candidate line. Fail-closed: the absence of a
   decision can never be silently resolved into one.
2. PROMPT. `.aai/SKILL_DESLOP.prompt.md` gains a `## Scope` section: when the
   invocation carried no scope, ASK the operator one question offering the two
   scopes and STOP until answered. Never assume, never default silently.

EMPTY DIFF. Today the prompt says "report nothing to deslop and stop", which
is a dead end. The engine instead exits 0 with zero candidates and the literal
line `NOTE: empty diff — rerun with --all to scan accumulated surface.`, and
the prompt is rewritten to OFFER the wide scope on that note.

DEGRADES, each named in the output rather than swallowed (Constitution art. 4,
and the AGENTS.md degrade-with-NOTE convention):

- docs/ai/STATE.yaml absent or unparseable, or both focus paths null under
  `--diff`: `NOTE: requirement corpus EMPTY (<reason>) — every extracted
  symbol is reported; treat this run as an inventory, not a finding list.`
  Exit stays 0.
- `--base` ref missing, or HEAD equal to the base: fall back to the
  working-tree diff and print which input was used (`Diff input: main...HEAD`
  or `Diff input: working tree`). `--base` defaults to `main`.
- A file that cannot be read is counted and named; it never aborts the scan.
- `--diff` in a directory where git itself is unusable (not a repository, or
  no git binary): documented here per round-4 code-review finding NB-1
  (originally an undocumented gap — the engine swallowed the failure and
  reported an ordinary clean empty-diff scan, indistinguishable from a
  genuinely empty diff). The engine prints an explicit `NOTE: git failed
  (not a git repository, or git is not installed)` and never emits the
  ordinary empty-diff note in the same run. Exit stays 0. TEST-017.

### D5 — the output, and how it discloses its own false negatives

Human form:

```
DESLOP class-4 scan — scope: all
  Requirement corpus: 131 documents (type spec, status accepted/implementing/done)
    excluded: 0 draft, 0 proposed, 0 rejected, 0 superseded, 0 deferred
  Surface scanned: 107 files, 2 extractor kinds, 0 unreadable
  Candidates: <N>
    <path>:<line>  <kind>  <symbol>
LIMITS (read before acting)
  - Pattern-based extraction, not a parser: dynamically created exports,
    computed names and generated flags are invisible to this scan.
  - FALSE NEGATIVES: a symbol named ANYWHERE in a requirement document,
    including prose, is suppressed. Suppressed this run: <M>.
  - Report only. No file was written. Nothing here is a verdict.
  - TEXT, NOT A FLAG: some candidates are flag-shaped TEXT rather than a
    flag this code owns — a string comparison, a printf/suggestion
    message, a regex pattern, or a flag naming a separately configured
    external agent CLI. Distinguishing those needs semantics, not syntax,
    so this pattern-based scan does not attempt it — read each candidate
    before acting.
```

A FOURTH limits line, unconditional (present in every run, both scopes),
discloses the residual class this remediation round's candidate adjudication
found (`docs/ai/reports/deslop-candidate-adjudication-20260815.md`, summary
tracked in `docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md`
since the 2026-08-15 remediation moved it out of D3 above — see D3's
pointer): 10 of the real tree's 70 candidates are flag-shaped
TEXT — a string literal, printf/suggestion message, PowerShell regex pattern,
or a flag naming a configured external agent CLI's own surface rather than
this repo's. Distinguishing those from a genuine owned flag needs semantics,
not syntax — a structural limit on what a pattern-based scan can attempt, not
a tuning gap (round-6 code review, NB-5: most of the 10 are not a
dependency-shaped gap — no library tells you whether a string describes a
flag or invokes one). No per-run count is
asserted for this line (unlike the suppressed count above): the 10-of-70
figure is a point-in-time measurement from the adjudication walk, not
something the engine can recompute correctly without the same semantic
judgment a human adjudicator applied, and a recomputed-but-wrong number would
be worse than an honest qualitative disclosure. TEST-008 pins the line's
presence (and its position, `limits[3]`) in both output forms; removing it
turns that arm red.

A FIFTH limits line appears only for `--diff` in range mode (a diverged
`<base>...HEAD`, D4's `range` mode): `RANGE MODE + DIRTY WORKTREE` — added-
line numbers come from the committed range but file content is read from
the worktree, so uncommitted edits on top of that range can produce a false
positive or a false negative. This is round-3 finding F17, tracked open as
`fu-deslop-range-mode-dirty-worktree` and deliberately NOT fixed by this
amendment — only disclosed, per round-4 validation finding V4-1 (the LIMITS
block did not mention it). TEST-002's range-mode arm proves the line appears
in range mode (`limits[4]`) and is absent in working-tree mode (`limits.length
=== 4`).

`<M>`, the suppressed count, is the point of the block: it is the measured
upper bound on false negatives from prose suppression specifically (NOT a
bound on total false negatives — pattern-extraction blindness and the
unscanned parts of `.aai/` contribute false negatives this count never
sees), printed every time, so nobody reads a short candidate list as a clean
bill of health.

`--json` carries the same information as data — `scope`, `requirement_corpus`,
`surface`, `candidates[]` (path, line, kind, symbol), `suppressed`, `notes[]`
and `limits[]`. The limits are NEVER human-arm-only; a machine consumer that
skips them is a consumer that believes the tool.

### D6 — which classes each scope runs

- `--diff`: all five slop classes, exactly as today. Classes 1, 2, 3 and 5
  stay the agent's judgment over the diff; class 4 is now the engine's list.
- `--all`: class 4 ONLY, and never an edit. The other four are judgments about
  lines a change introduced and have no meaning against settled code.

### D7 — the prompt rewrite lives inside pins that already exist

`.aai/SKILL_DESLOP.prompt.md` is 57 lines / 2933 B today and is pinned by four
arms of tests/skills/test-aai-advisory-skills.sh. The rewrite MUST keep all of
them true, and this spec budgets accordingly:

- at most 90 lines (the pinned ceiling is 100 — TEST-004 — and leaving 10
  lines of headroom is deliberate, since a later one-line canon addition
  breaking a zero-headroom ceiling is a failure this repo has already had);
- the slop-class table keeps at least 5 data rows and the five class keywords
  comment / try/catch / abstraction / unrequested / untouched (TEST-005);
- the behavior-unchanged rule, the literal `aai-run-tests.sh`, the
  `.aai/SKILL_VERIFY.prompt.md` cross-link and the exact ADVISORY disclaimer
  sentence survive verbatim (TEST-006, TEST-012);
- byte growth at most 1800 B, credited 1:1 in the diet ledger (D8).

The "Diff-scoped only" rule is REWRITTEN, not deleted: it becomes a rule that
names the scope it binds ("under `--diff`, a line not touched by this change
is out of bounds"), so the sentence stops reading as an absolute prohibition
on ever looking wider. The wide scope is safe here precisely because nothing
dispatches deslop: the original rule was written to stop an implementation
agent from wandering mid-ride, not to cap a deliberately invoked pass.

### D8 — companion obligations (closed list, both entries apply)

- PROMPT CORPUS BYTES MOVE: YES. `.aai/SKILL_DESLOP.prompt.md` is inside
  TEST-010's live `.aai/*.prompt.md` glob (budget 1800 B, D7).
  `.aai/AGENTS.md` line 115 also loses its "diff-scoped" claim; AGENTS.md sits
  OUTSIDE that glob and is credited manually at its exact measured delta, the
  precedent set by the friction-shadow-capture-wiring and
  canonical-test-invocation entries. One `JUSTIFIED_ADDITIONS` entry credited
  1:1 at the measured total G (both files summed, at most 1900 B), and the
  TEST-012 pin in tests/skills/test-aai-prompt-diet.sh moves from -5262 to
  -5262 + G. Measured G = 1210 B (1140 B initial + 70 B round-4 code-review
  remediation), pin -4052. V4-3 (round-4 validation): this row originally
  predicted "headroom stays 1622" — the actual measured headroom across the
  whole ledger is 1665/2048 (other entries besides this one also move
  headroom; this row's own contribution is a 1:1 credit at the measured
  delta, never padding), corrected here.
- NEW `.aai/**` FILE: YES. `.aai/scripts/deslop-unrequested.mjs` gets an
  `extended:` entry in `.aai/system/PROFILES.yaml` (D1).

Two more mechanical obligations that are not on that closed list but are
enforced by suites in this repo, so they are in scope: the new suite
`tests/skills/test-aai-deslop.sh` needs its own `suites.aai-deslop` row in
tests/skills/suite-map.yaml (hygiene pin), and every test function in it must
be wired into `main()` (`.aai/scripts/check-test-registration.mjs`).

### D9 — everything is locally provable, offline

Every verification below is a local command: `node
.aai/scripts/deslop-unrequested.mjs` against mktemp fixture trees, its exit
code and its stdout; a sha256 manifest compared with `cmp` for the no-write
proof; the two bash suites through the canonical wrapper `bash
.aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`; `grep` contracts
over the prompt, the wrapper descriptions and the catalogs; `wc -l` and
`wc -c` for the prompt budgets. No network, no service.

Fixture rules taken from LEARNED: build fixture repos with `git init -b main`
(a fresh CI checkout has no local `main`); use a full `.XXXXXX` mktemp
template (GNU rejects a bare prefix); no `bare rc=$?` and no `grep | head`
under the suite's `set -euo pipefail`; bash-3.2 only, no `declare -A`, no
`mapfile`; and every fixture helper refuses an empty or relative target
directory before any `git -C` call.

Non-vacuity: the fixture arms are the primary witnesses, and one arm runs
`--all` against the REAL repository asserting only exit 0 plus a well-formed
LIMITS block. The real-tree candidate COUNT is deliberately not asserted — it
moves with every merge, and pinning it would produce a test that fails for
reasons unrelated to this detector.

## Implementation strategy
- Strategy: hybrid
- Rationale: the engine's behaviors (scope refusal, both extractions, the
  no-write proof, the exit-code contract, the empty-diff note, the limits
  block) each have a cheap deterministic RED, and the implementer creates the
  engine FIRST as a stub that prints its usage and exits 2 for every
  invocation, so each RED is a `product_red` (the planted input reaches the
  assertion) rather than an `infra_fail` on a missing file — TDD lane with a
  stored RED artifact per AC-gating test. The prompt rewrite, the four wrapper
  descriptions, the three catalog surfaces and the three governance companions
  are grep-and-pin glue whose RED is a grep returning zero hits or an existing
  suite going red on the measured byte growth — loop lane, RED observed and
  recorded. STATE carries no intake-sourced strategy for this scope (the
  intake `## Notes` has no `Implementation mode (user choice):` line), so this
  is Planning's call.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: no protected surface, no parallel scope touches the
  deslop prompt, `.aai/scripts/` gains a new file rather than editing a shared
  one, and the tree is clean on main. A dedicated branch is still required by
  the one-branch-per-work-item rule that branch-guard.mjs enforces at PR.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/deslop-scope-and-unrequested-engine (branch to be
  created by Implementation Preparation; main is currently checked out and
  clean)
- Inline review scope: .aai/scripts/deslop-unrequested.mjs,
  .aai/SKILL_DESLOP.prompt.md, .aai/AGENTS.md, .aai/system/PROFILES.yaml,
  .claude/skills/aai-deslop/SKILL.md, .codex/skills/aai-deslop/SKILL.md,
  .gemini/skills/aai-deslop/SKILL.md, .agents/skills/aai-deslop/SKILL.md,
  SKILLS.md, docs/USER_GUIDE.md, docs/SKILL_CATALOG.html,
  docs/skill-catalog-data.json, tests/skills/test-aai-deslop.sh,
  tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh,
  docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md,
  docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md,
  docs/INDEX.md, CHANGELOG.md

Code review required: true (new script, prompt, test and catalog changes);
scope = the explicit path list above as a diff against main.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
- Spec-AC-01: WHEN the engine is invoked with no scope flag THEN it exits 2,
  prints a usage line naming both `--diff` and `--all`, and performs no scan
  (no candidate line on stdout, no git subprocess, no requirement document
  read), AND `.aai/SKILL_DESLOP.prompt.md` instructs the agent to ask the
  operator for a scope and stop until answered.
- Verification: `node .aai/scripts/deslop-unrequested.mjs; echo $?` == 2 with usage text naming both flags and zero candidate lines; grep contracts over the prompt for the ask-and-stop instruction and both scope tokens.

- Maps to: CHANGE AC-002
- Spec-AC-02: WHEN `--diff` runs over a fixture repository whose diff adds one
  exported symbol that the fixture requirement documents name and one that
  they do not THEN exactly the unnamed symbol is reported, with its path, its
  1-based line and its extractor kind, AND a symbol whose defining line is a
  context line rather than an added line is never reported.
- Verification: `node .aai/scripts/deslop-unrequested.mjs --diff --base main --json` inside the fixture repo; the candidates array has exactly one entry with the expected path, line, kind and symbol.

- Maps to: CHANGE AC-004
- Spec-AC-03: WHEN `--all` runs over a fixture tree THEN every symbol of the
  two extractor kinds of D3 that no requirement document mentions is listed
  and no mentioned symbol is listed, AND a file present in both a `--diff` run
  and an `--all` run yields byte-identical candidate rows for that file,
  proving one shared extraction and matching path rather than two.
- Verification: `--all --json` over the fixture asserts the exact expected candidate set per extractor kind; a second fixture whose diff contains the same file is run under both scopes and the two candidate row sets for that path are compared with `cmp`.

- Maps to: CHANGE AC-004 (corpus half) and the D2 narrowing
- Spec-AC-04: WHEN the requirement corpus is resolved THEN `--all` includes
  exactly the `type: spec` documents whose status is accepted, implementing or
  done and reports the included count plus the excluded count per status,
  AND `--diff` reads `current_focus.spec_path` and `current_focus.primary_path`
  from docs/ai/STATE.yaml without writing it, AND an absent or unparseable
  STATE, or both focus paths null, produces the named EMPTY-corpus note at
  exit 0 instead of an exception.
- Verification: fixture corpora carrying each excluded status assert the counts in the header; a fixture run with docs/ai/STATE.yaml deleted and one with a truncated STATE both exit 0 and print the EMPTY-corpus note; `cmp` proves STATE unchanged where it exists.

- Maps to: CHANGE AC-005
- Spec-AC-05: WHEN either scope runs to completion THEN the fixture tree is
  byte-identical before and after, proven by a sha256 manifest of every file
  compared with `cmp`, and no new path exists under the fixture root.
- Verification: build the manifest, run `--diff` then `--all`, rebuild the manifest, `cmp` the two; `find <root> -newer <marker>` returns nothing.

- Maps to: CHANGE AC-006
- Spec-AC-06: WHEN a scan completes THEN the exit code is 0 for a run with no
  candidates, for a run with candidates, and for a run over an empty input
  set, AND the only nonzero exit the engine can produce is 2 for a usage error
  (unknown flag, or no scope), which performs no scan.
- Verification: four invocations, `echo $?` after each — 0, 0, 0, and 2 for an unknown flag; grep of the engine source shows no other nonzero exit path.

- Maps to: CHANGE AC-003
- Spec-AC-07: WHEN `--diff` finds an empty diff THEN the engine exits 0 with
  zero candidates and prints the literal note offering `--all`, AND the prompt
  offers the wide scope at that point instead of the current terminal nothing
  to deslop wording, which no longer appears as a stopping instruction.
- Verification: `--diff` in a fixture repo with no changes exits 0 and stdout contains the literal `rerun with --all`; grep contracts over the prompt for the offer and against the terminal stop wording.

- Maps to: CHANGE Constraints (false negatives named in the output)
- Spec-AC-08: WHEN either scope produces output THEN both the human form and
  the `--json` form carry four disclosures — that extraction is pattern-based
  and not a parser, that a symbol named anywhere in a requirement document
  including prose is suppressed together with the numeric suppressed count for
  that run, that the run is report-only, and (EXTENDED by the round-5
  remediation candidate-adjudication pass, 2026-08-15 — see D3/D5) that some
  candidates are flag-shaped TEXT rather than an owned flag, disclosed
  qualitatively with no invented per-run count — AND the suppressed count
  equals the number of extracted symbols that matched the corpus, verified
  against a fixture with a known match count.
- Verification: a fixture with 3 matched and 2 unmatched symbols asserts `suppressed` == 3 in `--json` and the same number in the human LIMITS block; both forms are grepped for all four disclosure sentences, including the TEXT-NOT-A-FLAG residual-class line.

- Maps to: CHANGE AC-007
- Spec-AC-09: WHEN the prompt rewrite lands THEN the Diff-scoped only rule
  names the scope it binds rather than reading as absolute, the file is at
  most 90 lines, and every pre-existing pin holds — the slop-class table keeps
  at least 5 data rows and the five class keywords, and the
  behavior-unchanged rule, the `aai-run-tests.sh` literal, the SKILL_VERIFY
  cross-link and the exact ADVISORY disclaimer sentence survive verbatim.
- Verification: `wc -l .aai/SKILL_DESLOP.prompt.md` <= 90; grep contracts for the scope-bound rule wording; `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-advisory-skills.sh` exits 0.

- Maps to: CHANGE AC-008
- Spec-AC-10: WHEN the scope is complete THEN no surface still describes the
  pass as diff-only — the four wrapper descriptions
  (.claude, .codex, .gemini, .agents), the SKILLS.md row, the .aai/AGENTS.md
  Follow line and the docs/USER_GUIDE.md mentions all name the two scopes —
  AND docs/SKILL_CATALOG.html plus docs/skill-catalog-data.json are
  regenerated from the new descriptions rather than left stale.
- Verification: grep over each of the seven surfaces shows the two scopes and no diff-only claim; `node .aai/scripts/generate-docs-hub.mjs` then `git diff --exit-code -- docs/SKILL_CATALOG.html docs/skill-catalog-data.json` (idempotent, no drift).

- Maps to: CHANGE Constraints (governance checklist)
- Spec-AC-11: WHEN the scope is complete THEN the three governance companions
  are in place — the engine has an `extended:` entry in
  `.aai/system/PROFILES.yaml`, the diet ledger carries one
  `JUSTIFIED_ADDITIONS` entry credited 1:1 at the measured total G of at most
  1900 bytes with the TEST-012 pin at exactly -5262 + G, and
  tests/skills/suite-map.yaml carries a `suites.aai-deslop` row whose globs
  cover the engine and the new suite — AND every test function in the new
  suite is registered in its `main()`.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`, `... tests/skills/test-aai-layer-profiles.sh`, `... tests/skills/test-aai-hygiene-pack.sh` all exit 0; `node .aai/scripts/check-test-registration.mjs` exits 0.

## Constitution deviations

None. (Checked v1 articles 1-7. Article 1: every AC above names an executable
local command and a read observable, and the hybrid strategy stores each RED
before its GREEN. Article 2: one new file, no shared abstraction, no stoplist
or whitelist mechanism, no auto-deletion, no triage machinery — the closed
two-kind extractor list (narrowed from five by the 2026-08-15 amendment,
which removed three internal-symbol kinds per the same YAGNI article rather
than gating them behind an opt-in flag) is the whole detector, and `--all`
deliberately runs one slop class rather than five. Article 3: the engine is a plain Node script with
no dependency, every artifact is a git-diffable file, and the output is text
plus JSON. Article 4: the engine degrades and reports on an absent STATE, an
absent base ref, an unreadable file and an empty diff, each with a named note
on stdout rather than an exception or a silent zero; the usage error fails
fast with an actionable line. Article 5: the prompt is a public boundary and
its behavior does change — an invocation with no scope now ASKS where it
previously assumed the diff — so the change is recorded explicitly here, in
the prompt itself, in all seven description surfaces and in CHANGELOG.md;
`--diff` reproduces today's five-class behavior, so the change is additive for
every scoped invocation. Article 6: this planning pass writes no STATE; the
orchestrator records phase and strategy through state.mjs, and the engine only
ever READS docs/ai/STATE.yaml. Article 7: no merge is performed.)

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN no scope flag is given the engine exits 2 with a usage line naming both scopes and scans nothing, and the prompt asks the operator and stops | done | TEST-001+009 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log | — | fail-closed: absence of a decision is never resolved into one |
| Spec-AC-02 | WHEN the diff scope runs over a fixture the unnamed added symbol is reported with path, line and kind, and a context-line symbol never is | done | TEST-002 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log | — | defining line must be an added line under git diff --unified=0 |
| Spec-AC-03 | WHEN the wide scope runs over a fixture every unmentioned symbol of the two extractor kinds is listed and no mentioned one is, and both scopes emit identical rows for a shared file | done | TEST-003 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log | — | the identical-rows arm is the one-engine proof |
| Spec-AC-04 | WHEN the requirement corpus resolves it is the accepted or implementing or done spec set with per-status excluded counts, STATE is read and never written, and an absent STATE gives a named empty-corpus note at exit 0 | done | TEST-004+010 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log; real-repo baseline docs/ai/tdd/deslop-real-repo-all-baseline-20260814.json (historical, PRE-amendment, five kinds, 390/751); docs/ai/tdd/deslop-real-repo-all-baseline-20260815-amendment.json (historical, POST-amendment PRE-round5-remediation, two kinds, 75/444); re-baselined POST-round5-remediation docs/ai/tdd/deslop-real-repo-all-baseline-20260815-round5-remediation.json (two kinds, 70/398) | — | narrows intake A1 to full body text, see D2 |
| Spec-AC-05 | WHEN either scope completes the fixture tree is byte-identical, proven by a sha256 manifest compared with cmp, and no new path exists | done | TEST-005 green; docs/ai/tdd/green-20260814T112849Z-deslop-engine-and-companions.log | — | read-only by construction, not by convention |
| Spec-AC-06 | WHEN a scan completes the exit code is 0 with no candidates, with candidates and over an empty input set, and the only nonzero exit is 2 for a usage error | done | TEST-006 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log | — | advisory means advisory |
| Spec-AC-07 | WHEN the diff is empty the engine exits 0 with the literal note offering the wide scope, and the prompt offers it instead of stopping | done | TEST-007 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log | — | replaces today's terminal nothing-to-deslop dead end |
| Spec-AC-08 | WHEN either scope produces output both the human and json forms carry the not-a-parser limit, the prose-suppression limit with its numeric suppressed count, the report-only statement, and (round-5 remediation, 2026-08-15) the TEXT-NOT-A-FLAG residual-class disclosure | done | TEST-008 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log | — | the suppressed count is the measured upper bound on false negatives from prose suppression only, not total false negatives; the 4th disclosure is qualitative (no invented per-run count) per docs/ai/reports/deslop-candidate-adjudication-20260815.md, summarized in docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md (moved from D3 by 2026-08-15 remediation) |
| Spec-AC-09 | WHEN the prompt rewrite lands the diff-scoped rule names the scope it binds, the file is at most 90 lines, and all four pre-existing advisory-skills pins hold | done | TEST-009+011 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; docs/ai/tdd/red-20260814T112933Z-test011-converse-guard-overlong-draft.log (converse-guard proof); green-20260814T112849Z-deslop-engine-and-companions.log | — | pinned ceiling is 100 lines, 10 left as headroom |
| Spec-AC-10 | WHEN the scope is complete no description surface still claims the pass is diff-only and the generated catalog is regenerated rather than stale | done | TEST-014 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log | — | four wrapper trees plus SKILLS.md, AGENTS.md, USER_GUIDE |
| Spec-AC-11 | WHEN the scope is complete the PROFILES entry, the diet-ledger entry with the TEST-012 pin at -5262 plus G, the suite-map row and full test registration are all in place | done | TEST-012+013 green; docs/ai/tdd/red-20260814T112750Z-deslop-engine-and-companions.log; green-20260814T112849Z-deslop-engine-and-companions.log; G=1210 (pin -5262 -> -4052, round-4 code-review remediation B1/NB-4 added 70 B to G) | — | G is the measured total, budget 1900 bytes |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.aai/scripts/deslop-unrequested.mjs` (NEW) — argv parsing that fails closed
  without a scope; requirement-corpus resolution (D2) split into a
  STATE-reading arm and a spec-directory arm feeding one shared matcher; two
  extractors (D3) feeding one shared candidate builder; a diff-input resolver
  that produces the added-line set for the `--diff` arm and the full file set
  for the `--all` arm; one reporter with a human form and a `--json` form that
  both emit the LIMITS block. Stdlib only: `node:fs`, `node:path`,
  `node:child_process` for git.
- `.aai/SKILL_DESLOP.prompt.md` — a `## Scope` section (the two scopes, the
  ask-and-stop rule, the empty-diff offer), the class-4 row pointing at the
  engine invocation, the rewritten "Diff-scoped only" rule, and an output
  section covering both scopes. Budget 90 lines / +1800 B (D7).
- `.aai/AGENTS.md` — line 115's Follow-line comment loses "diff-scoped".
- `.aai/system/PROFILES.yaml` — one `extended:` entry for the engine.
- Four wrapper `SKILL.md` descriptions, `SKILLS.md`, `docs/USER_GUIDE.md`,
  and the regenerated `docs/SKILL_CATALOG.html` plus
  `docs/skill-catalog-data.json`.
- `tests/skills/test-aai-deslop.sh` (NEW) — the engine arms and the prompt
  grep contracts.
- `tests/skills/suite-map.yaml` — a `suites.aai-deslop` row globbing the
  engine and the prompt.
- `tests/skills/lib/prompt-diet-ledger.sh` and
  `tests/skills/test-aai-prompt-diet.sh` — the ledger entry and the pin.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading (per-entry heading
  form, never bullets under the scaffold).

Data flows and seams, each crossed by a named test:

- SEAM-1 engine to docs/ai/STATE.yaml. The file is gitignored and absent on a
  fresh CI checkout, and it has exactly one writer that is not this engine. A
  reader that throws on absence would make `--diff` unusable in CI; a reader
  that writes would breach Constitution art. 6. Crossed by TEST-004, which
  runs the real engine against a fixture with STATE deleted, with STATE
  truncated mid-document, and with STATE present, and `cmp`s the present case.
- SEAM-2 engine to git. `--diff` shells out; a fixture repo built without
  `git init -b main` has no `main`, and the base-ref fallback is exactly the
  path that then executes. Crossed by TEST-002's two `--base` arms (real
  fixture repo, explicit `--base`; missing base ref, fallback path named in
  output) — both folded into TEST-002. Correction: this row, before the fold,
  named the missing-base-ref arm TEST-008; TEST-008 is actually the
  suppressed-count test, and is unrelated to this seam.
- SEAM-3 prompt to tests/skills/test-aai-advisory-skills.sh. Four arms pin the
  file this scope rewrites — a 100-line ceiling, the table shape, the rules
  block, the isolation invariant. A rewrite is exactly how those go red.
  Crossed by TEST-011, which runs that whole suite rather than re-asserting
  its contents.
- SEAM-4 prompt corpus to the diet ledger. The added bytes are inside
  TEST-010's live `.aai/*.prompt.md` glob and AGENTS.md is credited manually
  outside it. Crossed by TEST-012.
- SEAM-5 new `.aai/**` file to `.aai/system/PROFILES.yaml`, new suite file to
  tests/skills/suite-map.yaml, new test functions to `main()`. Three
  independent live-tree pins in three different suites. Crossed by TEST-013.
- SEAM-6 wrapper descriptions to the generated catalog. `generate-docs-hub.mjs`
  reads SKILL.md frontmatter; editing a description without regenerating
  leaves docs/SKILL_CATALOG.html asserting the old diff-only claim. Crossed by
  TEST-014.

Edge cases:

- A CSS custom property declared inside a generated `<style>` block
  (`--accent: #0b62d6;`) or referenced via `var(--accent)`: excluded, never a
  candidate — the amendment's CSS exclusion (D3) applies at every occurrence,
  not only the first, so neither the declaration nor any later usage of the
  same name survives dedupe into a reported row.
- A flag passed to `git`/`gh` (or any other external binary) via this repo's
  local `git`/`tryGit`/`runGh` wrapper convention, or directly to
  `execFileSync`/`spawnSync`/`spawn`/`execSync` with a non-`node` command:
  excluded as an external-tool argument (D3). A flag passed to `node` (this
  process re-invoking one of its OWN other `.aai/scripts/**` files) stays a
  candidate — that flag is still this repo's OWN contract surface, just
  observed at a call site rather than at its owning script's definition.
- A flag appearing in a usage string but never parsed: still extracted. The
  detector reads text, not behavior, and D5's first limit says so.
- A requirement document that mentions a symbol only inside a fenced code
  block: still a match. The corpus is body text; excluding code fences would
  suppress the most literal form of "the spec asked for this".
- A one-character or two-character symbol name: extracted like any other; the
  whole-word matcher makes short names match more, which is a suppression
  (safe direction), never a spurious finding.
- A binary or unreadable file inside a scanned glob: counted as unreadable and
  named in the header, never fatal.
- `--diff` where the diff touches only paths outside the scanned globs: an
  empty input set, exit 0, the empty-diff note.
- `--all` on a repository with no `docs/specs/` directory: the EMPTY-corpus
  note, every symbol reported, exit 0.

Residual risks, written down rather than silently accepted:

- The first `--all` run over the real repo will surface legitimate code, and
  no triage of that list is in scope. A detector whose first run is noisy is
  still useful; a gate whose first run is noisy is a blocker. This one is not
  a gate.
- Pattern extraction is blind to dynamically created or computed names, so the
  candidate list is a lower bound on unrequested surface, never a census.
- Whole-body matching (D2) suppresses more than AC-only matching would. The
  suppressed count quantifies it every run, but the count does not say which
  suppressions were prose-only.
- `--diff` corpus resolution depends on docs/ai/STATE.yaml, which is
  per-developer and gitignored, so the diff scope's requirement set is not
  reproducible across machines. CI exercises fixture arms only.
- No stoplist means generic flags recur in the candidate list until a human
  triage decides otherwise. That decision is deliberately deferred.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description | Status  |
|----------|------------|-------------|--------------------------------------------|-------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-deslop.sh            | no scope flag exits 2 with a usage line naming both scopes, emits zero candidate lines, and reads no requirement document | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-deslop.sh            | diff scope over a git-init-b-main fixture reports exactly the added unnamed symbol with path, line and kind, and never a context-line symbol | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-deslop.sh            | wide scope over a fixture reports every unmentioned symbol of both extractor kinds and none of the mentioned ones, and a shared file yields identical rows under both scopes | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-deslop.sh            | corpus selection by status with per-status excluded counts; STATE present is read and cmp-proven unchanged; STATE absent and STATE truncated each give the named empty-corpus note at exit 0 | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-deslop.sh            | sha256 manifest of the fixture tree is identical after both scopes and no new path exists under the fixture root | green |
| TEST-006 | Spec-AC-06 | unit        | tests/skills/test-aai-deslop.sh            | exit 0 for clean, for findings and for an empty input set; exit 2 for an unknown flag; no other nonzero exit path exists in the engine source | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-deslop.sh            | empty diff exits 0 with the literal rerun-with-all note, and the prompt offers the wide scope with no terminal stop wording left; SECOND arm (round-4 code-review B2, not in the original frozen row — listed here per the round-3 F12 precedent that every arm must appear): a non-empty diff whose only changed file sits outside the scanned globs must never read as "empty diff" and gets its own honest out-of-scope note instead; THIRD arm (round-4 validation V4-6, same B2 conflation residual): a deletion-only change to an existing scanned file must never read as "empty diff" either — it touched a file, it just added nothing | green |
| TEST-008 | Spec-AC-08 | unit        | tests/skills/test-aai-deslop.sh            | a fixture with 3 matched and 2 unmatched symbols reports suppressed equal to 3 in both output forms, and both carry all four disclosure sentences; EXTENDED by round-5 remediation (2026-08-15) with a regression arm asserting `limits.length === 4` and `limits[3]` is the TEXT-NOT-A-FLAG residual-class line in both forms, so deleting the line turns this arm red | green |
| TEST-009 | Spec-AC-09 | unit        | tests/skills/test-aai-deslop.sh            | prompt grep contracts, also covering the prompt half of Spec-AC-01: the ask-and-stop rule, both scope tokens, the scope-bound rewrite of the diff-scoped rule, the engine invocation line, and at most 90 lines | green |
| TEST-010 | Spec-AC-04 | integration | tests/skills/test-aai-deslop.sh            | wide scope against the REAL repository exits 0 with a well-formed header and LIMITS block; the candidate count is reported, never asserted | green |
| TEST-011 | Spec-AC-09 | integration | tests/skills/test-aai-advisory-skills.sh   | the four pre-existing deslop pins still pass after the rewrite: line ceiling, slop-class table shape, rules block, advisory isolation | green |
| TEST-012 | Spec-AC-11 | unit        | tests/skills/test-aai-prompt-diet.sh       | TEST-012 pin equals -5262 plus the measured G and equals the independent re-sum of JUSTIFIED_ADDITIONS, and the new entry names both files and their measurements | green |
| TEST-013 | Spec-AC-11 | integration | tests/skills/test-aai-deslop.sh            | the engine has a PROFILES extended entry, suite-map carries a suites.aai-deslop row globbing the engine and this suite, and check-test-registration exits 0 | green |
| TEST-014 | Spec-AC-10 | unit        | tests/skills/test-aai-deslop.sh            | none of the seven description surfaces claims diff-only and each names both scopes; regenerating the docs hub leaves the catalog and its data file byte-unchanged | green |
| TEST-015 | Spec-AC-03 | integration | tests/skills/test-aai-deslop.sh            | REPURPOSED by the 2026-08-15 amendment (its original mjs-export brace-list coverage no longer applies — that kind is removed), then EXTENDED by round-5 remediation (V5-1/V5-2): the cli-flag precision fix — a CSS custom-property declaration and its var() usage are excluded, a flag passed to git via the git/tryGit/runGh wrapper convention or a direct execFileSync('git', ...)-shaped call (including one level of local array indirection) is excluded, a flag passed to node (this repo's own other script) stays a candidate, a comment-only occurrence is now excluded everywhere, and a genuine own-flag in real code still matches (mjs arm); a new shell arm proves the sh/ps1 external-tool exclusion is command-word/position-based, not line-wide, and is mutation-guarded | green |
| TEST-016 | Spec-AC-06 | integration | tests/skills/test-aai-deslop.sh            | --all invoked from the wrong working directory sees an empty input set (0 files matched) and exits 0 while emitting the surface-EMPTY note rather than a silent clean bill | green |
| TEST-017 | Spec-AC-07 | integration | tests/skills/test-aai-deslop.sh            | round-4 code-review NB-1, not in the original frozen table (listed here per the round-3 F12 precedent): --diff in a non-git working directory (or where git itself is unusable) surfaces an explicit git-failure NOTE rather than reading as an ordinary empty-diff clean scan | green |
| TEST-018 | Spec-AC-07 | integration | tests/skills/test-aai-deslop.sh            | PR #260 external review (Codex, engine line 713), not in the original frozen table (round-3 F12 precedent): a --base range diff whose two refs both resolve but share no merge base (two unrelated histories) surfaces an explicit git-failure NOTE naming the no-merge-base cause, rather than reading as an ordinary empty-diff clean scan | green |
| TEST-019 | Spec-AC-07 | integration | tests/skills/test-aai-deslop.sh            | PR #260 external review (Codex, engine line 748), not in the original frozen table (round-3 F12 precedent): a diff whose only change is a COMPLETE file deletion (git emits +++ /dev/null, never +++ b/path) is preserved as touched with zero candidates, never misread as an empty diff — the V4-6 partial-deletion fix's residual, one level up (whole file, not just its content) | green |
| TEST-020 | Spec-AC-04 | integration | tests/skills/test-aai-deslop.sh            | PR #260 external review (Codex, engine line 241), not in the original frozen table (round-3 F12 precedent): a stale/unreadable STATE.yaml spec_path or primary_path is never silently dropped — a fully-stale corpus degrades to the named EMPTY-corpus note (mirroring resolveAllCorpus's own degrade), and a partially-stale corpus names the skipped path in a NOTE while the readable document still suppresses the symbol it names | green |
| TEST-021 | Spec-AC-06 | unit        | tests/skills/test-aai-deslop.sh            | PR #260 external review (Codex, engine line 93), not in the original frozen table (round-3 F12 precedent): a flag-shaped token following --base (e.g. --json, --all) is rejected at exit 2 as a usage error rather than silently consumed as the ref, which would drop the requested flag and fall back to the working-tree diff | green |

RED plan (hybrid; every RED observed and STORED before its GREEN work, with
`RED_CLASS:` written as line 1 AT CAPTURE — `product_red` when the planted
input reaches the assertion, `infra_fail` otherwise, per SKILL_TDD):

- Step zero, so the engine REDs are honest: create
  `.aai/scripts/deslop-unrequested.mjs` as a stub that prints its usage and
  exits 2 for every invocation, and commit it before any test is written. Each
  engine RED is then a real observation against a real program
  (`product_red`), not a missing-file `infra_fail`.
- TEST-002/003/004/005/007/008/010 RED against the stub: every scoped
  invocation exits 2 with usage text instead of scanning — no candidates, no
  header, no LIMITS block. Captured verbatim per arm.
- TEST-001/006 RED: the stub already exits 2 for a missing scope, so their RED
  is the CONVERSE arm — a valid `--diff` or `--all` invocation must exit 0 and
  does not. Recorded that way so neither test can pass vacuously against the
  stub.
- TEST-009 RED: grep the pre-change prompt for the ask-and-stop rule, the
  `--all` token and the engine invocation — zero hits, plus the absolute
  "Diff-scoped only" sentence and the terminal nothing-to-deslop instruction
  still present.
- TEST-011 RED is the converse guard: it passes on the pre-change tree by
  construction, so its value is regression-only. Recorded as such, and the
  implementer must observe it going RED at least once by running it against an
  intentionally over-long draft of the rewritten prompt before trimming to
  budget.
- TEST-012 RED arises mechanically: the pin is -5262 before the prompt grows,
  and the suite fails on the measured growth until the ledger entry lands.
- TEST-013 RED: layer-profiles goes red the moment the engine file exists
  without its PROFILES entry; the suite-map hygiene pin goes red the moment
  the new suite file exists without its row.
- TEST-014 RED: grep the four wrapper descriptions and the three catalog
  surfaces for the diff-only claim — all seven still carry it.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-advisory-skills.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/deslop-unrequested.mjs --all --json` over the real
  repository, recording the raw candidate count and the suppressed count as
  the triage baseline (a recorded number, not an asserted one)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` and
  `node .aai/scripts/spec-lint.mjs` both clean
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD and code review artifact, record:
- ref_id: deslop-scope-and-unrequested-engine
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ for RED artifacts per the hybrid strategy;
  `RED_CLASS:` stamped as line 1 at capture)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
