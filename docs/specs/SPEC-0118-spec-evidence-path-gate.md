---
id: spec-evidence-path-gate
type: spec
number: 118
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0131-evidence-path-gate.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Close-time evidence-path gate: cited evidence must resolve from the main tree

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0131-evidence-path-gate.md
- Prior spec (the close ceremony this change extends): docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md
- Prior spec (the gate pattern being mirrored, dial + pre-write refuse): docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
- Guard-dial reader (the closed dial set): .aai/scripts/lib/guard-config.mjs
- Shared AC-table readers: .aai/scripts/lib/docs-model.mjs
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — one new pure-function lib under
`.aai/scripts/lib/`, one dial added to the existing closed set in
`guard-config.mjs`, one pre-write gate block in `close-work-item.mjs` that
copies the two gates already sitting beside it, one documented key in
`docs/ai/docs-audit.yaml`, and rows in the one suite that already covers all
of it. The ceremony ceiling was checked explicitly against
`protected_paths_l3` in docs/ai/docs-audit.yaml (state.mjs, lib/state-engine.mjs,
lib/state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.sh,
pre-commit-checks.ps1, .aai/workflow/WORKFLOW.md, docs/CONSTITUTION.md): NONE of
the four files this scope edits appears on that list, so L3 is not forced.
The shipped dial is report-only and fail-open, so a defect in the new code
cannot block a close that would otherwise succeed — the blast radius of the
worst realistic bug is a spurious WARNING line on stderr. Level 1 still demands
a suite re-run plus a targeted probe and a full dual-verdict code review; the
Test Plan below IS the declared validation scope and every row names a directly
executable command.

## Implementation strategy
- Strategy: tdd
- Rationale: every AC-gating test can be observed FAILING on the pre-change
  tree for a real reason, not a staged one — TEST-036/037 import a module that
  does not exist, TEST-038 asserts a dial absent from a closed set, and
  TEST-039 to TEST-043 assert an exit code and stderr lines no current code
  path can emit. The substance of the change is a pure parsing function whose
  entire risk is the shapes it must NOT match (D3), and a
  match-nothing-by-accident grammar is exactly the code that looks right and is
  wrong — it must be pinned by tests written before it exists, or the tests
  will be written to fit whatever the implementation happens to do. No
  intake-sourced strategy choice exists for CHANGE-0131 (its `## Notes` carries
  no `Implementation mode (user choice):` line and STATE holds no
  intake-sourced selection), so this is Planning's call.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: four small edits plus one new lib and one test file, all
  on a dedicated branch (`feat/evidence-path-gate`) with no parallel scope
  touching `close-work-item.mjs`. There is also a pointed reason to prefer the
  main tree HERE specifically: this scope's own TDD evidence must resolve from
  the main tree, and losing worktree-local transcripts is the precise incident
  it exists to prevent. If Implementation Preparation nonetheless chooses a
  worktree, the Test Plan's EVIDENCE-STORAGE OBLIGATION applies verbatim.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/evidence-path-gate (inline)
- Inline review scope: .aai/scripts/lib/evidence-paths.mjs, .aai/scripts/lib/guard-config.mjs, .aai/scripts/close-work-item.mjs, docs/ai/docs-audit.yaml, .aai/system/PROFILES.yaml, tests/skills/test-aai-close-work-item.sh, docs/specs/SPEC-0118-spec-evidence-path-gate.md, docs/issues/CHANGE-0131-evidence-path-gate.md, CHANGELOG.md

## Summary

On the CHANGE-0127 ride (2026-08-08) the implementer worked in an isolated
worktree and wrote TDD RED/GREEN transcripts there. The spec's AC Status
Evidence column cited `docs/ai/tdd/...` paths that resolved inside the worktree
and nowhere else. The main tree never had those files. Nothing mechanical
noticed: the close ceremony checks doc status, links, close events and the
docs-audit verdict — never whether the bytes an Evidence cell points at exist.
Only the validator's manual sweep (finding N4) caught it, and the files were
hand-copied minutes before the worktree was deleted. Had the sweep skipped that
row, the spec would today cite evidence that does not exist anywhere.

The 5-layer audit (2026-08-11) named this the one graph-failure mode the
factory does not cover mechanically: "a merge silently drops one branch's
result". Ledger LINES have `reconcile-telemetry.mjs`. Evidence FILES have
nothing.

This scope adds the missing checkpoint at the one moment that is both
deterministic and already fail-closed: `close-work-item.mjs`, running from the
main tree, before any write. Every path-shaped token cited in the closing
doc set's AC Status Evidence cells must resolve from the repo root, or the
close warns (report-only, the shipped default) or refuses (enforce, opt-in).

The whole risk of this change is FALSE POSITIVES. Evidence cells are free
prose: they carry commands, run IDs, sha256 digests, test-id ranges, slash
commands and URLs alongside real paths. An extraction that mistakes prose for a
path would refuse legitimate closes — a gate that cries wolf is worse than no
gate, because the factory would learn to flip it off. So the grammar was not
designed from imagination: it was measured against the live corpus first (see
D2), and it is deliberately biased to skip rather than to guess.

## Design decisions

- D1 — Extraction lives in a NEW pure lib, `.aai/scripts/lib/evidence-paths.mjs`;
  the warn-vs-refuse decision lives in `close-work-item.mjs`. Same split the
  two sibling gates already use (`lib/product-doc.mjs` +
  `evaluateProductDocGate`, `lib/usage-note.mjs` + `evaluateUsageCaptureGate`).
  The extraction grammar is the part that needs hostile unit testing with no
  git fixture, no repo and no close — a pure function over a string is the only
  shape that allows that. A NEW `.aai/**` file owes a
  `.aai/system/PROFILES.yaml` classification entry (Planning companion
  obligation; mechanically enforced by `tests/skills/test-aai-layer-profiles.sh`,
  which fails on any UNCLASSIFIED vendored file) — folded into scope as
  Spec-AC-09.

- D2 — The extraction grammar, measured before it was written. A token inside
  an Evidence cell is a candidate path only when ALL of these hold, in this
  order:
  1. after stripping surrounding markdown punctuation (leading backtick,
     quote, paren, bracket, brace; trailing backtick, quote, paren, comma,
     period, semicolon, colon, bracket, brace) it still contains at least
     one `/`;
  2. it contains no ellipsis (`...` or the single-character `…`);
  3. every remaining character is in `[A-Za-z0-9._/-]`;
  4. it does not begin with `/`;
  5. no segment is exactly `..`;
  6. its FIRST segment names an existing DIRECTORY at the repo root.
  Rules 2 to 6 are not defensive decoration. Each one was derived from a real
  rejection observed in this repo (D3), and rule 3 subsumes globs, brace
  expansions, line-number suffixes, URLs and inline-code joins in one stroke.

- D3 — The grammar's evidence base. A throwaway probe ran the rules above over
  every `## Acceptance Criteria Status` Evidence cell in `docs/specs/` (697
  cells) and `docs/issues/` (21 cells). It extracted 752 path tokens and
  produced ZERO false positives — every extracted token is a genuine repo path.
  The rejected slash-bearing tokens fall into exactly four families, all real:
  - 142 distinct no-root-dir rejections: `TEST-001/002`, `TEST-105/106/305`,
    `A/B`, `PASS/1`, `before/after`, `RFC-0030/RFC-0032/RFC-0034`. This is the
    prose family the intake demands can never trip the gate, and rule 6 alone
    removes it.
  - 4 absolute rejections: `/`, `/tmp`, `/bin/bash`, and the slash-command
    mention `/aai-release`.
  - 18 charset rejections: `.aai/scripts/lib/docs-audit-core.mjs:591` (a
    line-number citation), `docs/ai/reports/test-canon-coverage-*.md` (a glob),
    `docs/ai/tdd/green-...-TEST-00{1..5}.log` (a brace expansion), `.aai/**`,
    `https://github.com/goodwind-cz/aai/actions/runs/30289358425`, `file://`,
    and backtick-glued joins such as
    `` `test-aai-state.sh`/`test-aai-layer-profiles.sh` ``.
  - 1 ellipsis rejection, and it is the one that would have hurt:
    `docs/ai/tdd/red-...test_011/012/014...log` in
    SPEC-0114. It is root-anchored, it is charset-clean, and it is an author's
    ABBREVIATION of four filenames, not a path. Without rule 2 the gate would
    have refused a legitimate close on its first real ride.

- D4 — Existence, not tracking. The check is `fs.existsSync(join(ROOT, token))`
  and a directory counts as resolvable. `docs/ai/tdd/**` is gitignored by
  design (`.gitignore:35`) and currently holds 331 files; a tracking-based
  check would reject the single most common evidence location in this repo.
  An absent path is the only failure.

- D5 — Scope is the CLOSING doc set, never a repo-wide sweep, and it is
  selected by SHAPE, not by directory. The gate evaluates every doc
  `close-work-item.mjs` already resolved (`--ref` and, when given, `--spec`)
  that exposes an AC Status table with an `Evidence` column. Two reasons not to
  hardcode `docs/specs/`: an L0 ride keeps its AC table in the CHANGE doc
  (WORKFLOW ceremony table: "tech-note in the CHANGE doc"), so a directory
  filter would leave the lightest lane ungated; and a doc with no Evidence
  column yields zero tokens and is a silent no-op anyway. A repo-wide sweep is
  explicitly NOT this scope — see R2.

- D6 — The AC table is read through the SHARED parsers, never a fourth regex.
  `parseAcTable(content)` from `lib/docs-model.mjs` returns rows keyed by
  header name, so the Evidence cell is `row['Evidence']`; when `hasGate` is
  false the lib falls back to `parseLeanAcTable(content)` (L0/L1 lean tables,
  where the Evidence column is optional). This is the same dual path
  `spec-lint.mjs` itself takes. Three implementations of "what the AC table is"
  already existed once in this repo and drifted; a fourth is not being created
  (S2, pinned by a grep contract).

- D7 — Dial and exit code. `evidence_path_gate` joins the closed `GUARD_DIALS`
  set AND the line-parser alternation in `lib/guard-config.mjs` (both, or the
  dial reads as its default forever — S3), with the same grammar as its two
  siblings: `enforce` | `report-only`, absent file / absent key / invalid value
  falls open to report-only, an invalid value additionally warns on stderr.
  `docs/ai/docs-audit.yaml` ships the documented key at `report-only`; the flip
  to enforce is a later, separately-evidenced KPI decision, exactly as
  `usage_capture_gate` was flipped only after 26/26 observed coverage. The
  refusal exit code is **5** (3 = product-doc gate, 4 = usage-capture gate),
  documented in the script's EXIT CONTRACT header block.

- D8 — Placement: immediately after `evaluateUsageCaptureGate`, before
  `readEvents` and before the idempotency short-circuit's INDEX regeneration.
  That short-circuit calls `selfVerify` -> `regenerateIndex`, which WRITES
  `docs/INDEX.md`; a gate placed after it would violate "refuses before any
  write" on the already-closed path. `--dry-run` reports the verdict in its
  JSON under `evidencePathGate` and never exits 5, matching both siblings.

- D9 — The WARNING and the REFUSAL name every unresolvable path, the doc it was
  cited in, and the Spec-AC row id. "Some evidence is missing" is not
  actionable; "SPEC-DRAFT-x.md Spec-AC-03 cites docs/ai/tdd/red-....log which
  does not exist" is a copy-paste instruction for the operator (Constitution
  article 4).

- D10 — Node stdlib only, no new dependency, no network, no git invocation. The
  gate does not shell out to `git ls-files` — that would make it a tracking
  check (D4) and would add a subprocess to a path that must stay fast.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0131 AC-001
- Spec-AC-01: WHEN `extractEvidencePaths(cell, root)` is given an Evidence cell
  THEN it returns exactly the tokens satisfying the six D2 rules, and in
  particular returns nothing for a cell containing only prose, a test-id range
  such as `TEST-001/002`, a slash command such as `/aai-release`, an absolute
  path, a URL, a `file.mjs:591` line-number citation, a glob or brace
  expansion, a sha256 digest, a run ID, or the real-world ellipsis
  abbreviation `docs/ai/tdd/red-...test_011/012/014...log`.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_036_evidence_path_extraction_grammar`.
    Evidence: suite stdout plus the stored RED transcript.

- Maps to: CHANGE-0131 AC-001
- Spec-AC-02: WHEN the lib reads a doc THEN it obtains AC rows only through
  `parseAcTable` with a `parseLeanAcTable` fallback imported from
  `lib/docs-model.mjs`, declares no `Acceptance Criteria Status` heading regex
  of its own, and returns zero tokens for a doc with no AC table or no
  `Evidence` column.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_037_evidence_paths_shared_parser_contract`
    — greps the lib source for the two imports and for the absence of a local
    heading regex, then asserts the empty result on a table-less doc and a
    non-empty result on a lean L1 table. Evidence: suite stdout.

- Maps to: CHANGE-0131 AC-002
- Spec-AC-03: WHEN `readGuardConfig` reads a config directory THEN
  `evidence_path_gate` returns `enforce` for `enforce`, `report-only` for
  `report-only`, `report-only` plus one stderr warning for an invalid value,
  and `report-only` for an absent key and an absent file; `GUARD_DIALS`
  includes `evidence_path_gate`; and the shipped
  `docs/ai/docs-audit.yaml` carries the key at `report-only` with a comment
  block naming the consumer and the fail-open default.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_038_guard_config_evidence_path_gate_dial`
    plus `grep -c '^evidence_path_gate: report-only$' docs/ai/docs-audit.yaml`
    equal to 1. Evidence: suite stdout and the grep output.

- Maps to: CHANGE-0131 AC-002
- Spec-AC-04: WHEN a closing spec cites one resolvable and one absent path and
  the dial is absent or `report-only` THEN the close exits 0, the doc reaches
  `status: done`, and stderr carries one `WARNING (evidence-path gate)` line
  naming the absent path, the doc, and the Spec-AC row id, and NOT naming the
  resolvable path.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_039_evidence_gate_report_only_warns`.
    Evidence: suite stdout, captured stderr.

- Maps to: CHANGE-0131 AC-002
- Spec-AC-05: WHEN the same spec closes under `evidence_path_gate: enforce`
  THEN the process exits 5, stderr carries one `REFUSED (evidence-path gate)`
  line naming the absent path, the primary doc is byte-identical to its
  pre-run copy, `docs/ai/EVENTS.jsonl` has its pre-run byte length, and
  `docs/INDEX.md` was never created.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_040_evidence_gate_enforce_refuses_pre_write`.
    Evidence: suite stdout, the exit code, the `diff -q` result, the two size
    comparisons.

- Maps to: CHANGE-0131 AC-003
- Spec-AC-06: WHEN a closing spec cites a path that exists on disk but is
  matched by the fixture repo's `.gitignore`, and a second path that is an
  existing DIRECTORY, and the dial is `enforce` THEN the close exits 0 with no
  gate line on stderr; and WHEN the same fixture deletes only the gitignored
  file THEN the same close exits 5.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_041_evidence_gate_existence_not_tracking`.
    Evidence: suite stdout, both exit codes, `git check-ignore -v` output for
    the fixture file.

- Maps to: CHANGE-0131 AC-001
- Spec-AC-07: WHEN a closing spec's Evidence cells contain ONLY the hostile
  non-path shapes of Spec-AC-01 and the dial is `enforce` THEN the close exits
  0 and stderr carries no `evidence-path gate` line at all.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_042_evidence_gate_prose_never_refuses`.
    Evidence: suite stdout, the exit code, the empty grep.

- Maps to: CHANGE-0131 AC-002
- Spec-AC-08: WHEN the close runs with `--dry-run` under `enforce` against an
  unresolvable citation THEN it exits 0, prints an `evidencePathGate` object in
  its JSON carrying the severity and the unresolvable path list, and writes
  nothing.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh test_043_evidence_gate_dry_run_noop`.
    Evidence: suite stdout, the parsed JSON key, the unchanged doc bytes.

- Maps to: CHANGE-0131 AC-004
- Spec-AC-09: WHEN the suites re-run THEN `tests/skills/test-aai-close-work-item.sh`
  exits 0 with TEST-001 through TEST-035 still registered and running,
  `tests/skills/test-aai-state.sh` (the other `readGuardConfig` consumer) exits
  0, `tests/skills/test-aai-hygiene-pack.sh` (the grep-versus-reader dial
  conformance) exits 0, `tests/skills/test-aai-layer-profiles.sh` exits 0 with
  the new lib listed in `.aai/system/PROFILES.yaml`, and
  `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0118-spec-evidence-path-gate.md`
  reports zero findings.
  - Verification: the five commands above. Evidence: the five stdouts.

## Constitution deviations

None. Article 1 (evidence before claims) is the article this scope MECHANIZES —
it turns "the evidence cited exists" from a manual sweep into a deterministic
check. Article 2 (simplicity): one pure lib plus a copy of an existing gate
block; the grammar is six rules, each traced to an observed rejection, and
nothing speculative (no glob support, no git integration, no repo-wide sweep).
Article 3 (portability): plain Node stdlib over plain files. Article 4 (degrade
and report): absent config, absent AC table, absent Evidence column and absent
STATE all degrade to a silent no-op, and every failure names the path, the doc
and the AC row. Article 5 (additive first): the dial ships report-only and
fail-open, so every existing close behaves byte-identically until an operator
opts in.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN an Evidence cell is extracted THEN only tokens passing the six D2 rules are returned and every hostile prose shape yields nothing | done | docs/ai/tdd/red-20260811T223442Z-test_036_evidence_path_extraction_grammar.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log | — | the whole false-positive risk lives here |
| Spec-AC-02 | WHEN the lib reads a doc THEN AC rows come only from the shared parseAcTable with a parseLeanAcTable fallback and a table-less doc yields zero tokens | done | docs/ai/tdd/red-20260811T223442Z-test_037_evidence_paths_shared_parser_contract.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log | — | seam S2, no fourth table parser |
| Spec-AC-03 | WHEN readGuardConfig reads a config dir THEN evidence_path_gate resolves enforce report-only invalid-fail-open and absent-default and the shipped yaml carries the documented key | done | docs/ai/tdd/red-20260811T223442Z-test_038_guard_config_evidence_path_gate_dial.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log | — | seam S3, closed set plus line regex |
| Spec-AC-04 | WHEN an absent path is cited under an absent or report-only dial THEN the close exits 0 and warns naming the path the doc and the AC row | done | docs/ai/tdd/red-20260811T223442Z-test_039_evidence_gate_report_only_warns.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log | — | shipped default arm |
| Spec-AC-05 | WHEN the same spec closes under enforce THEN exit 5 and the doc EVENTS and INDEX are all untouched | done | docs/ai/tdd/red-20260811T223442Z-test_040_evidence_gate_enforce_refuses_pre_write.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log | — | pre-write refusal, D8 placement |
| Spec-AC-06 | WHEN a gitignored-but-present file and an existing directory are cited under enforce THEN the close exits 0 and deleting the file alone makes it exit 5 | done | docs/ai/tdd/red-20260811T223442Z-test_041_evidence_gate_existence_not_tracking.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log | — | existence not tracking, D4 |
| Spec-AC-07 | WHEN Evidence cells hold only prose commands run IDs and test-id ranges under enforce THEN the close exits 0 with no gate line | done | docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log (negative control test_042; passes trivially pre-implementation by construction, no RED obligation, see Notes) | — | the intake hard requirement; no gate exists pre-change so this assertion cannot RED for a real reason — verified GREEN only, same as TEST-044 |
| Spec-AC-08 | WHEN dry-run runs under enforce against an unresolvable citation THEN exit 0 with an evidencePathGate JSON verdict and no write | done | docs/ai/tdd/red-20260811T223442Z-test_043_evidence_gate_dry_run_noop.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log | — | mirrors both sibling gates |
| Spec-AC-09 | WHEN the suites re-run THEN close-work-item state hygiene-pack and layer-profiles exit 0 with the new lib classified and spec-lint reports zero findings | done | docs/ai/tdd/red-20260811T223527Z-test_045_layer_profiles_unclassified.log then docs/ai/tdd/green-20260811T223939Z-close-work-item-full.log, docs/ai/tdd/green-20260811T223939Z-state-full.log, docs/ai/tdd/green-20260811T223939Z-hygiene-pack-full.log, docs/ai/tdd/green-20260811T223939Z-layer-profiles-full.log, docs/ai/tdd/green-20260811T223939Z-spec-lint.log | — | PROFILES companion obligation; corpus tripwire (Verification step 7): 751 tokens / 370 unresolved over docs/specs+docs/issues (D3 measured 752/370 — exact match on unresolved, 1-token drift on total from ordinary corpus churn since planning) |

## Implementation plan

Components:

- `.aai/scripts/lib/evidence-paths.mjs` (NEW, ~80 lines, Node stdlib only):
  - `extractEvidencePaths(cell, root)` — the D2 grammar over one cell string,
    returning a deduped array of candidate tokens in first-appearance order.
    The root-directory probe (rule 6) is memoized per call site so a 9-row
    table costs a handful of `statSync` calls, not one per token.
  - `evidenceCitations(content, root)` — reads a doc's AC table via
    `parseAcTable` with the `parseLeanAcTable` fallback (D6), and returns
    `[{ acId, token }]` for every candidate across every row's `Evidence`
    cell. Returns `[]` when there is no table or no `Evidence` column.
  - `unresolvedCitations(content, root)` — `evidenceCitations` filtered by
    `!fs.existsSync(path.join(root, token))`.
- `.aai/scripts/lib/guard-config.mjs` (EDIT, three touch points that MUST move
  together): the `GUARD_DIALS` array, the `out` defaults object, and the
  line-parser alternation regex.
- `docs/ai/docs-audit.yaml` (EDIT): `evidence_path_gate: report-only` plus a
  comment block in the house style of the two dials above it — what it gates,
  who consults it, the fail-open default, and that it is close-only so the
  pre-commit shell greps deliberately do not mirror it.
- `.aai/scripts/close-work-item.mjs` (EDIT):
  - header EXIT CONTRACT block gains code 5;
  - `evaluateEvidencePathGate(docs)` next to the two sibling evaluators,
    returning `{ severity, dial, unresolved, reason }` where `severity` is
    `none` when nothing is unresolvable;
  - the warn/refuse block immediately after the usage-capture block (D8);
  - `evidencePathGate` added to the `--dry-run` JSON payload.
- `.aai/system/PROFILES.yaml` (EDIT): the new lib joins the core
  `.aai/scripts/lib/*` list, alphabetically between `docs-model.mjs` and
  `pricing.mjs`.
- `tests/skills/test-aai-close-work-item.sh` (EDIT): a
  `set_evidence_path_gate_dial` helper mirroring the two existing dial helpers,
  and eight test functions TEST-036 through TEST-043 registered in `main()`.
  The existing `write_spec_doc` helper already takes the Evidence cell as its
  fifth argument, so no fixture rewrite is needed.
- `CHANGELOG.md`: one `## [unreleased] — <title>` heading carrying this entry.

Data flows:

`close-work-item --ref/--spec` -> `resolveDoc` -> resolved doc `content` ->
`unresolvedCitations(content, ROOT)` -> per-doc unresolved list ->
`readGuardConfig(docs/ai).evidence_path_gate` -> WARN on stderr or exit 5,
before `readEvents` and before any `regenerateIndex`.

Edge cases:

- A doc resolved as `--spec` and a primary doc that BOTH carry AC tables: both
  are scanned; the message groups unresolved paths per doc.
- The same path cited by three AC rows: reported once per (doc, acId) pair but
  deduped per token within a cell, so a cell repeating a path does not triple
  the message.
- An Evidence cell that is the em dash `—` or empty: zero tokens.
- A token that resolves to a directory: resolvable (D4).
- A closing doc with a `## Acceptance Criteria Status` heading but a malformed
  table (`hasGate` false, lean fallback also empty): zero tokens, silent no-op.
  Malformed AC tables are `spec-lint`'s job, not this gate's.
- Windows path separators: a backslash fails rule 3 and is skipped.

## Seams

- S1 — the new gate <-> `close-work-item.mjs`'s pre-write transaction. The
  idempotency short-circuit further down calls `regenerateIndex()`, which
  writes `docs/INDEX.md`. A gate that refuses AFTER that point has already
  written a file while claiming it wrote nothing. Crossed by TEST-040, which
  asserts `docs/INDEX.md` does not exist after an exit-5 refusal — the same
  assertion the usage-capture gate's TEST-031 already makes, so a regression on
  either gate's placement is caught by both.
- S2 — `evidence-paths.mjs` <-> `lib/docs-model.mjs`'s AC-table readers. Four
  independent implementations of "what the AC table is" is the exact drift
  CHANGE-0009 D8 removed from `docs-audit.yaml` parsing. A forked heading regex
  here would silently disagree with docs-audit, the index generator and
  spec-lint about which rows exist. Crossed by TEST-037, a grep contract on the
  lib source plus a lean-table behavioral arm.
- S3 — `GUARD_DIALS` <-> the line-parser alternation <-> the shipped
  `docs-audit.yaml` <-> the pre-commit shell greps. Adding a dial to the closed
  array but not to the regex yields a dial that silently reads as its default
  forever, and every test that only checks `GUARD_DIALS.includes(...)` passes.
  Crossed by TEST-038, which drives all four value arms through the REAL reader
  rather than inspecting the array, and by re-running
  `test-aai-hygiene-pack.sh` (its test_031 asserts the shell greps and this
  reader agree on fixtures) under Spec-AC-09.
- S4 — the gate <-> a spec authored in a worktree. This is the incident seam
  and it is crossed by construction, not by a test: the check runs in
  `close-work-item.mjs`, which runs from the main tree at PR ceremony. A test
  cannot easily simulate "another worktree deleted after the fact", so the
  behavior under test is its observable equivalent — a cited path that is not
  present in the tree the close runs in (TEST-040).
- S5 — `write_spec_doc` fixtures <-> the new gate. Every pre-existing close
  test that builds a spec fixture passes `commit-abc` or `—` as the Evidence
  cell; neither contains a `/`, so the new gate is a no-op for all 35 existing
  tests. That non-regression is asserted wholesale by Spec-AC-09 rather than
  assumed.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-036 | Spec-AC-01 | unit | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_036_evidence_path_extraction_grammar` — drives extractEvidencePaths over a hostile corpus: a real docs/ai/tdd citation with trailing comma and parenthesis extracts clean, and TEST-001/002, A/B, /aai-release, /bin/bash, https URLs, file.mjs:591, a star glob, a brace expansion, a sha256 digest, a run ID, backtick-glued joins and the docs/ai/tdd/red-...test_011/012/014...log ellipsis all yield nothing | green |
| TEST-037 | Spec-AC-02 | unit | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_037_evidence_paths_shared_parser_contract` — greps evidence-paths.mjs for the parseAcTable and parseLeanAcTable imports and for the absence of a local Acceptance-Criteria-Status regex, then asserts zero citations from a doc with no AC table and non-zero from a lean L1 table with an Evidence column | green |
| TEST-038 | Spec-AC-03 | unit | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_038_guard_config_evidence_path_gate_dial` — GUARD_DIALS includes evidence_path_gate and readGuardConfig returns enforce, report-only, report-only-plus-warning for an invalid value, and report-only for absent key and absent file; plus the shipped docs/ai/docs-audit.yaml carries exactly one column-0 evidence_path_gate report-only line | green |
| TEST-039 | Spec-AC-04 | int  | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_039_evidence_gate_report_only_warns` — spec fixture citing one present and one absent path with no dial line: exit 0, doc flips to done, one WARNING evidence-path gate line naming the absent path plus the doc plus Spec-AC-01, and the present path absent from the message | green |
| TEST-040 | Spec-AC-05 | int  | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_040_evidence_gate_enforce_refuses_pre_write` — same fixture under enforce: exit 5, REFUSED evidence-path gate on stderr naming the path, doc byte-identical via diff -q, EVENTS.jsonl size unchanged, docs/INDEX.md never created | green |
| TEST-041 | Spec-AC-06 | int  | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_041_evidence_gate_existence_not_tracking` — fixture .gitignore covering docs/ai/tdd, an untracked log present there plus a cited existing directory, enforce: exit 0 and no gate line; then rm the log and re-run: exit 5 | green |
| TEST-042 | Spec-AC-07 | int  | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_042_evidence_gate_prose_never_refuses` — spec fixture whose three Evidence cells hold only the Spec-AC-01 hostile shapes, enforce: exit 0, doc done, and grep of stderr for evidence-path gate finds nothing | green |
| TEST-043 | Spec-AC-08 | int  | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh test_043_evidence_gate_dry_run_noop` — enforce plus --dry-run against an unresolvable citation: exit 0, stdout JSON carries evidencePathGate with severity refuse and the unresolvable path listed, doc bytes and EVENTS size unchanged, docs/INDEX.md never created | green |
| TEST-044 | Spec-AC-09 | int  | tests/skills/test-aai-close-work-item.sh | run `bash tests/skills/test-aai-close-work-item.sh` then `bash tests/skills/test-aai-state.sh` then `bash tests/skills/test-aai-hygiene-pack.sh` — all three exit 0, and the close suite still registers and runs test_001 through test_035 | green |
| TEST-045 | Spec-AC-09 | int  | tests/skills/test-aai-layer-profiles.sh | run `bash tests/skills/test-aai-layer-profiles.sh` and `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0118-spec-evidence-path-gate.md` — profiles union equals the live .aai tree with evidence-paths.mjs classified core, and spec-lint reports zero findings | green |

RED discipline (strategy tdd). TEST-036 through TEST-043 are the AC-gating
tests and MUST each be observed FAILING on the PRE-change tree before any
production line is written. Their RED is real rather than staged: TEST-036 and
TEST-037 import a module that does not exist (a resolution error is the RED),
TEST-038 asserts a dial that is not in the closed set, and TEST-039 through
TEST-043 assert stderr lines and an exit code that no code path can currently
produce. Store every transcript under `docs/ai/tdd/` as
`red-<ISO8601>-<test_name>.log`, and the GREEN run as
`green-<ISO8601>-close-work-item-full.log`.

TEST-045 is the one row whose RED must be sequenced deliberately: create
`.aai/scripts/lib/evidence-paths.mjs` FIRST and run
`tests/skills/test-aai-layer-profiles.sh` before touching
`.aai/system/PROFILES.yaml` — it fails with `UNCLASSIFIED vendored files`
naming the new lib. That transcript is the RED; adding the PROFILES entry is
the GREEN. TEST-044 is a pure regression row and carries no RED obligation.

EVIDENCE-STORAGE OBLIGATION (this scope's own subject matter). If
implementation runs in a worktree, every `docs/ai/tdd/` transcript cited in the
AC Status table MUST be copied into the MAIN tree before the worktree is
removed. This spec exists because that step was once missed; a ride that
repeats the incident while implementing its fix would be caught by its own gate
only once the dial is flipped, and by the validator's read of this line before
then.

## Verification

Commands, in order:

1. `bash tests/skills/test-aai-close-work-item.sh` — the eight new tests plus
   the 35 pre-existing ones, zero FAIL lines.
2. `bash tests/skills/test-aai-state.sh` — the other `readGuardConfig` consumer.
3. `bash tests/skills/test-aai-hygiene-pack.sh` — the grep-versus-reader dial
   conformance (test_031).
4. `bash tests/skills/test-aai-layer-profiles.sh` — the new lib is classified.
5. `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0118-spec-evidence-path-gate.md`
   — zero findings.
6. `node .aai/scripts/docs-audit.mjs --check` — exit 0 (one expected false-open
   on this spec while the ride is in flight).
7. Targeted probe (L1 requirement, run from the repo root against the REAL
   tree, not a fixture):
   `node -e "import('./.aai/scripts/lib/evidence-paths.mjs').then(m => { const fs = require('fs'); let n = 0, bad = 0; for (const f of fs.readdirSync('docs/specs')) { const c = fs.readFileSync('docs/specs/' + f, 'utf8'); for (const x of m.evidenceCitations(c, process.cwd())) { n++; if (!fs.existsSync(x.token)) bad++; } } console.log(n, bad); })"`
   — the extracted count must be within a few tokens of the 752 measured in D3,
   and every extracted token must be a plausible repo path on visual
   inspection. This is the false-positive tripwire the unit test cannot give,
   because it runs against the whole real corpus rather than a curated one.

PASS criteria: all TEST-036 through TEST-045 green, all nine Spec-AC in a
terminal status, commands 1 to 6 exit 0.

## Evidence contract

For each artifact record: ref_id `evidence-path-gate`; the Spec-AC and TEST-xxx
it serves; the command; the exit code; the evidence path; the commit SHA.

Strategy `tdd` demands (per SPEC_TEMPLATE `### Evidence by strategy`): a stored
RED artifact under `docs/ai/tdd/` for every AC-gating test — TEST-036 through
TEST-043, plus the sequenced TEST-045 RED — and the full verification matrix
above. Evidence cells in the AC Status table must cite those transcript paths
BY PATH, from the main tree.

## Residual risks

- R1 — A cited path whose FIRST segment is not an existing repo-root directory
  is not gated (D2 rule 6). The realistic shape is a worktree-prefixed path
  such as `wt-CHANGE-0127/docs/ai/tdd/red.log`. Zero such tokens appear in the
  718-cell corpus, and the alternative (dropping rule 6) reintroduces the
  142-strong `TEST-001/002` false-positive family, which is strictly worse.
  Accepted.
- R2 — Historical decay is real and deliberately out of scope. Of the 752
  tokens the grammar extracts from today's `docs/specs/` corpus, 370 no longer
  resolve, because `docs/ai/tdd/**` is gitignored and rotates. A repo-wide
  sweep would therefore be permanently red and is NOT what this gate does: it
  reads only the doc set of the close in progress, whose evidence was written
  minutes earlier. Anyone later building a repo-wide audit on this lib must
  reckon with this number first.
- R3 — A placeholder that is charset-clean and root-anchored (for example
  `docs/specs/SPEC-XXXX.md` written into an Evidence cell) would be extracted
  and reported unresolvable. No instance exists in the corpus, and the
  report-only shipped default means the cost is a warning, not a blocked close.
- R4 — `fs.existsSync` is case-insensitive on macOS APFS and case-sensitive on
  Linux CI. A citation whose case does not match the file on disk passes the
  gate locally and would fail it on CI. Not gated here (a case-exact check
  needs a directory listing per segment); recorded so a future CI-side
  divergence reads as this, not as a flake.
- R5 — The gate sees the doc as it exists on disk at close time. A ride that
  closes and only THEN writes its evidence files (or renames them) is
  unaffected by the gate and still ends with dangling citations. The close
  ordering makes this unlikely; no mechanism prevents it.
- R6 (validation finding F2) — a LEAN AC table inside a CHANGE doc is
  silently un-gated when the doc carries an earlier `## Acceptance Criteria`
  heading (the CHANGE_TEMPLATE bullet list): `parseLeanAcTable` anchors on
  the FIRST such heading and yields zero citations. Live-corpus impact
  today: zero docs. Shared-parser behavior (D6/S2) — fixing it means fixing
  `lib/docs-model.mjs` for every consumer, a separate scope.
