# Code Review — docs-history-is-one-git-call-per-doc

```yaml
review:
  scope: "git diff e0223a7..688ac60 -- .aai/scripts/lib/docs-audit-core.mjs tests/skills/test-aai-docs-audit.sh docs/specs/SPEC-0142-spec-docs-history-is-one-git-call-per-doc.md docs/issues/CHANGE-0154-docs-history-is-one-git-call-per-doc.md"
  spec: docs/specs/SPEC-0142-spec-docs-history-is-one-git-call-per-doc.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-001 test_histmap_corpus_equivalence — suite run 2026-08-21: documents=538 mismatches=0 both_null=0 dated=538 bite=ok; .aai/scripts/lib/docs-audit-core.mjs:334-364" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-002 test_histmap_one_git_call_per_audit — 1 add-history walk, 0 per-file calls for 4 docs (18 git calls total), --quick 0 of 0; docs-audit-core.mjs:989. DEVIATION: the AC's Verification line names an arm `test_histmap_quick_spawns_no_git` that does not exist" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-003 test_histmap_rename_needs_no_renames — numbered=2026-03-05 draft=2026-01-10 per_file_numbered=2026-03-05, raw_without_has_numbered=false; docs-audit-core.mjs:339" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-004 test_histmap_no_history_yields_null — no_history_map=null, untracked_present=false, per_file_untracked=null, both audits render a Verdict; docs-audit-core.mjs:349-350,1047" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-005 test_histmap_first_commit_date_still_exported — single=2026-07-15 from_map=2026-07-15 ghost=null; docs-audit-core.mjs:301-308 body unchanged in the diff" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/docs-audit-core.mjs, line: 989,
          issue: "The hoisted gate ignores `scopePath`: a single-document scoped audit now pays a whole-corpus history walk instead of one per-file call.",
          failure_scenario: "`docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-DRAFT-<slug>.md` — the intake post-save gate named in SPEC-0013/SPEC-0019 and .aai prompts. Measured here: whole walk 49.9 ms vs one per-file call 27.6 ms (+22 ms on a 170 ms run). The walk scales with the number of add records under docs/ across all history, the per-file call with one file's history, so the ratio grows without bound on a larger docs corpus while the scoped work stays at one document. Recommended disposition: promote-to-follow-up (guard is one token: `files.length > 1`)." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0142-spec-docs-history-is-one-git-call-per-doc.md, line: 238,
          issue: "Spec evidence citations do not resolve against the shipped suite: Spec-AC-02 names arm `test_histmap_quick_spawns_no_git` (shipped name is `test_histmap_one_git_call_per_audit`), and the Implementation plan (:325) and Test Plan prose say four new arms / four main() calls where five shipped.",
          failure_scenario: "A future reader (or the close ceremony populating the Evidence column) greps the suite for the named arm, finds nothing, and either records empty evidence or concludes the AC is unimplemented. Recommended disposition: remediate-in-tree at close — text-only." }
  cannot_verify:
    - { claim: "Spec-AC-02's wall-clock claim (>=3x, 13569 -> 3875 ms / 12155 -> 3667 ms).",
        closes_with: "A timed before/after pair on one machine in one session. No arm asserts it; validation round 1 measured 12155 -> 3667 ms = 3.31x and I did not re-measure." }
    - { claim: "The mid-parse abort (`ADD_DATE_RE` fails on a header-position token, docs-audit-core.mjs:355) reaches the D3 fallback rather than a half-built map.",
        closes_with: "A fixture that makes git emit a non-date header. Established by inspection only — `return null` discards the partially built local `map` and `firstCommitMap?.has()` at :1047 then falls back for every document; the throw path IS covered end-to-end by TEST-004(a)." }
    - { claim: "Behaviour on git older than 2.50.1 and on Windows.",
        closes_with: "A run on those platforms. The `-z` + `%x00` record shape is version-dependent; a shape change degrades safely (see Attack 3) but is unverified. Key SHAPE on Windows is fine — `scanAuditDocs` POSIX-normalizes `rel` (:733)." }
    - { claim: "Behaviour under non-default git config that alters log output (`log.showSignature`, `log.diffMerges`).",
        closes_with: "Runs with those set. Not exercised." }
  overall: pass
```

## Scope and method

Base `e0223a7`, head `688ac60`, tree clean at start and end, `git rev-parse HEAD` unchanged. Ceremony level 1. Validation round 1
(`docs/ai/validation/validation-20260821T143917Z-...-round1.md`) was read first
and is not repeated: the 538-document equivalence, the git-call census, the
non-ASCII fixture, the git-failure shim, the subdirectory `runAudit`, and the
add/delete/re-add ordering are all its work and I did not redo them. This pass
judges the code as code and the engine change for blast radius.

Suite executed (serially, nothing else against this checkout):
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
-> **rc 0, 156 PASS**, all five new arms green. `docs/INDEX.md` byte-identical
to the backup taken before the run; `git status --porcelain` 0 lines after.

## Attacks attempted

### 1. The parser, against a real stream (failed to break)

Read `od -c` of the shipped argv on the real corpus. The record shape is
`\0 <date> \0 \n path1 \0 path2 \0` — the commit terminator NUL is emitted by
`-z` in ADDITION to the `%x00` header NUL, so splitting yields exactly one empty
token before each date. The `expectDate` / `firstPath` state machine consumes
that shape correctly. Case by case:

| Case | Can it occur? | Parser behaviour |
|---|---|---|
| commit with an EMPTY name list | **No** — proved by fixture, see below | (would desync; see the note) |
| first record | yes | leading `''` arms `expectDate` — correct |
| last record / trailing separator | yes | trailing `''` sets `expectDate` and the loop ends — no spurious entry |
| path that is a prefix of another | yes | NUL-terminated, no ambiguity |
| `--allow-empty` commit | **No** — pathspec-TREESAME, pruned | n/a |
| root commit | yes | diffed against the empty tree, full name list, parsed normally |
| merge, `--diff-filter=A` | **No** — see below | n/a |

The empty-name-list case is the only shape that could hurt, and it cannot
arrive. Fixture at `<scratch>/fx`: root commit, a `--allow-empty` commit, a
side branch, a main add, and a real merge whose `docs/specs/t.md` is TREESAME to
NEITHER parent. Stream contains exactly the four dated non-merge records; the
merge and the empty commit are absent. `--diff-filter` clears
`always_show_header`, and with the default `--diff-merges=off` a merge produces
no diff, so such commits are suppressed rather than emitted headerless.
Corroborated on the real repository: 251 records scanned, **0 with an empty name
list**, and 0 map keys that are date-shaped, contain a newline, or fall outside
`docs/` (641 keys).

Note for the record, not a finding: IF such a record ever appeared AND git
emitted the header-to-diff newline for it (`\0d1\0\n\0d2\0\n p...`), the
`'\n'` token would clear `firstPath` without setting `expectDate`, and the next
date would be consumed as a path — one commit's files mis-dated plus one garbage
key, resynchronising at the following record. Unreachable today; I mention it
only because the state machine's resync depends on the empty token and not on
the date guard.

Two things the parser does right that are easy to get wrong: a first-path token
whose filename itself starts with a newline is handled (`'\n' + '\nname'` ->
`'\nname'`), and a first-path token WITHOUT the separator newline is also
handled (the strip is conditional, not assumed).

### 2. The abort path (failed to break)

- **`maxBuffer` exceeded** — executed, not reasoned. Node v22.23.1,
  `maxBuffer: 1024` against the real walk: **throws `ENOBUFS`**. It does not
  return truncated output. The `catch` at :349 therefore returns `null` and no
  half-built map can escape.
- **Non-zero git exit** — covered end-to-end by TEST-004(a) (repository with no
  commits): `no_history_map=null`, and the full audit still renders a Verdict.
- **Unparseable token** — `return null` at :355 is executed before `map` is
  read by anyone; the local is discarded. Inspection only (listed in
  `cannot_verify`). Design credit: if a future git changes the record shape, the
  header-position token stops matching `^\d{4}-\d{2}-\d{2}$` and the whole walk
  degrades to the shipped per-file path instead of producing plausible-looking
  wrong dates.

All three reach `firstCommitMap === null`, and `firstCommitMap?.has(f.rel)` at
:1047 is then `undefined` for every document -> `firstCommitDate` per document,
i.e. exactly pre-change behaviour and pre-change cost.

### 3. The gate hoist, D4 (failed to break)

`if (!quick && legacyUntil)` at :1042 is byte-unchanged; only the RHS of `first`
moved. The hoisted `(!quick && legacyUntil && files.length)` at :989 differs by
the single extra conjunct `files.length`, and when `files.length === 0` the
`for (const f of files)` loop body never executes, so no lookup is ever made —
equivalent. `legacyUntil` is the same binding (`:979`) in both places, evaluated
before either, and `files` is not reassigned or mutated between :982 and :1009.
The `else if (quick || !legacyUntil)` branch at :1050 is the exact logical
complement of the `if`, is untouched, and is unreachable from the hoist. The
`doc.legacy` / `doc.softLegacy` assignments in it are therefore unaffected.
Type parity holds: the map only ever stores a `YYYY-MM-DD` string, and
`firstCommitDate` returns a string or `null`, so `doc.firstCommit` and the
`first != null && first < legacyUntil` comparison see the same value space as
before.

The one thing the hoist does NOT account for is `scopePath` — filed as the
first NON-BLOCKING finding above.

### 4. Shell correctness in the five new arms (failed to break)

Checked against `set -euo pipefail` (line 12) and
`log_fail() { echo ...; exit 1; }` (line 67):

- **`rc=$?` after a pipe** — not present. Every occurrence is
  `out="$(node ... 2>&1)" || rc=$?`, where `$?` is the assignment's status, i.e.
  the command substitution's. Correct.
- **`grep | head` / SIGPIPE** — no pipeline into a head-like consumer in the new
  arms. `wc -l < "$gitlog" | tr -d ' '` is a pipe but its status is never read.
- **`grep -c` returning 1 on zero matches** — every count is wrapped
  `|| true`. If the log file were missing, `grep` exits 2, the variable is empty,
  and `[[ "" -eq 1 ]]` is false, so the arm fails rather than passes.
- **`local x=$(...)` status masking** — avoided: `local d; d="$(setup_histmap_repo …)"`
  is correctly split, so a failing setup subshell trips `set -e`.
- **`log_fail` inside a subshell / command substitution** — none. Every
  `log_fail` is at function top level and therefore exits the suite.
- **A `sed` anchor that matches nothing** — no `sed` in the new arms.
- **`local -a x=()` with `${#x[@]}` under bash 3.2.57** — no arrays introduced.
- **Unquoted expansion** — none; every `$d`, `$out`, `$gitlog`, `$walk_shape` is
  quoted. Patterns are passed through `-e` (the comment's BSD-grep reason is
  correct).
- **Shim heredoc** — `<<EOF` unquoted so `$gitlog`/`$realgit` interpolate, with
  `\$*` / `\$@` escaped. `realgit` is captured before the PATH override, so the
  shim cannot exec itself.

### 5. Vacuity (failed to break)

Every new arm fails rather than passes when its subject is empty.

- **TEST-001, the AC-001 corpus arm — the dispatch's specific question.** If the
  corpus enumeration returned zero documents it goes **RED**, not green:
  `files.length < 100` and `clean.dated < 100` are explicit FINDINGs, and the
  in-arm mutation (`victim` rewritten to `1970-01-01`, must produce exactly one
  mismatch naming that file) cannot be satisfied by a comparator with nothing to
  compare — `if (!victim) … bad = true`. Three independent guards.
- TEST-002: `total -gt 0` (the shim intercepted something) and
  `grep -qF "Scanned: 4 docs"` (the audit actually saw four documents) — a
  no-op audit cannot produce `walks == 1 && perfile == 0` for the right reason.
- TEST-003: the unmutated walk is the green control and the `--no-renames`-less
  walk must lose the path; both directions asserted.
- TEST-004: `map.size < 1` and `map.has(tracked)` make "absent key"
  discriminating rather than the only answer available.
- TEST-005: the `ghost` path must be `null`, so a hardcoded date fails.

### 6. Fixture hygiene (clean)

`setup_histmap_repo` writes only `$TEST_DIR/iso-histmap-<name>`; the four Node
helpers are written to `$TEST_DIR`. The `PATH` shim is created under `$d` and
exported only inside a `( … )` subshell. Nothing in the new arms writes outside
`$TEST_DIR`. TEST-001 and TEST-005 touch `$PROJECT_ROOT` but only through
`git ls-files`, `git log` and the two read-only engine functions — verified by
reading, and by `git status --porcelain` being 0 lines and `docs/INDEX.md`
byte-identical after the suite.

### 7. Blast radius

Consumers of the changed seam: `docs-audit.mjs:368` (`runAudit`),
`close-work-item.mjs:981` (`runAudit(ROOT, {})`), `generate-docs-index.mjs:531`
(`runAudit`) and `generate-docs-index.mjs:266` (`firstCommitDate`, per-violation,
explicitly out of scope per D8 — unchanged, so no regression there). Key shape
matches on every OS because `scanAuditDocs` POSIX-normalizes `rel` (:733) and
git emits forward slashes. `firstCommitDate`'s body, signature and export are
untouched in the diff.

### 8. The two spec claims corrected mid-ride

- **The intake's "99.1% is firstCommitDate"** — now retracted in the spec
  (:53-62) and in the intake (`CHANGE-DRAFT…:74-79`). The replacement text is
  accurate and matches validation's independent census: 581 -> 211 git calls,
  203 survivors are the `git log -1 --grep=<id>` id-mention probe, present in
  identical number before and after. The claim the change now makes — one git
  process instead of N — is exactly what it owns.
- **D6's reason for dropping `--full-history`** (:165-180) — the correction is
  accurate as it now stands: it states plainly that the original rationale was
  wrong, names the real cause (history simplification computed per pathspec),
  reproduces validation's numbers, and keeps the conclusion on the honest ground
  of parity with the per-file call. Nothing else in the spec rests on the
  retracted reasoning: D2, D5, D7, D8 and Spec-AC-01/03/04/05 are independent of
  it, and the Edge-cases list (:331-337) makes no `--full-history` claim.
  Residual imprecision only: the Summary quotes validation's pair
  (12155 -> 3667 ms, 3.31x) while the Spec-AC-02 Notes quote the implementer's
  (13569 -> 3875 ms, 3.5x). Both are labelled with their source; not a defect.

### 9. Testing the `fu-histmap-merge-pathspec-divergence` argument (it holds)

The argument is that the shape landing turns the suite red rather than the audit
silently wrong. I tested it rather than accepting it:

- **Does the arm run often enough?** `node .aai/scripts/select-suites.mjs
  --files-from <(echo docs/specs/SPEC-0001-x.md)` -> `CORE aai-docs-audit
  reason=core`. The suite is a CORE suite: it is selected by EVERY change, not
  only by changes to the audit's own files. The claim "runs against the real
  repository every suite run" is stronger than stated.
- **Is the failure loud?** Yes. A divergence produces
  `FINDING: <file>: per-file=<a> bulk=<b>` on stdout, a non-zero exit from the
  helper, and `log_fail "the bulk map is not equivalent to the shipped per-file
  firstCommitDate: $out"`, which exits the whole suite 1. The in-arm mutation
  proof exercises exactly that path on every run (`bite=ok mutated=docs/CONSTITUTION.md`
  in today's log), so the red path is proven, not assumed.
- **Does it name the right thing?** Partly. It names the symptom precisely — the
  exact document and both dates — which is the right localisation. It does not
  name the CAUSE, and neither the arm nor the code comment points at the filed
  follow-up, so whoever hits it re-derives the merge/pathspec explanation from
  scratch. That is a diagnosability cost, not a correctness one, and the spec's
  D6 correction is where the explanation lives. I concur with P3 and do not
  refile.

## Concurrence with known items (not refiled)

- `fu-docsaudit-idmention-probe-per-doc` (P2) — concur. 203 of the 211 residual
  git calls; independently visible in this pass's blast-radius read.
- `fu-ceremony-guard-reds-on-dirty-core` (P3) — concur; not reachable here, the
  change is committed and the tree is clean.
- `fu-histmap-merge-pathspec-divergence` (P3) — concur, and its
  leave-open argument survives the test above.

## What I attacked and failed to break

The NUL record grammar against a real `od -c` stream and against a purpose-built
merge/empty-commit repository; the empty-name-list desync (unreachable);
`maxBuffer`, non-zero exit and unparseable-token abort paths (all reach D3, the
first two executed); the D4 hoist for logical equivalence including
`files.length === 0` and the `else if` complement; six named shell hazards in
the five new arms; vacuity of all five arms including the specific
zero-document question; fixture writes outside `$TEST_DIR`; key-shape drift on
Windows; and the leave-open argument for the P3 follow-up.

## Filed

Nothing. Per the anti-gaming contract the reviewer is read-only and names
dispositions rather than filing them. Both NON-BLOCKING findings carry a named
recommended disposition above; the orchestrator records them (H6).

## Next steps

1. Close ceremony must flip all five Spec-AC rows and populate Evidence
   (`fu-ac-flip-must-precede-close`), and fix the arm-name / arm-count citations
   while it is in the file (NON-BLOCKING #2).
2. Decide NON-BLOCKING #1 (scoped-audit walk) — remediate with
   `files.length > 1` or promote to a follow-up ref.
3. `spec-lint` half-frozen advisory on this spec (SPEC-FROZEN true vs
   frontmatter `draft`), carried over from validation — fix before close.
4. `select-suites.mjs` returns `FULL_RUN reason=shared-lib`; the PR needs the
   `ci-full` label so `mode=full` runs on it.
