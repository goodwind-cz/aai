---
id: spec-intake-secrets-preflight
type: spec
number: 45
status: done
ceremony_level: 2
links:
  change: intake-secrets-preflight
  rfc: null
  pr:
    - 97
  commits:
    - cea19d7
---

# SPEC — Intake Secrets Preflight: exists/empty/missing, never the value

SPEC-FROZEN: true

## Links
- Change: intake-secrets-preflight
  (docs/issues/CHANGE-0034-intake-secrets-preflight.md)
- Precedent (helper-script shape, closed exit contract, byte discipline):
  SPEC-0044 (`.aai/scripts/tdd-evidence-check.mjs`)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` — full pipeline. Honestly considered L1 per the dispatch
invitation and rejected on two grounds:
1. NOT single-surface: the scope adds one NEW executable helper, edits THREE
   prompt-diet corpus files (`.aai/INTAKE_COMMON.md`,
   `.aai/INTAKE_CHANGE.prompt.md`, `.aai/INTAKE_ISSUE.prompt.md`), two
   templates, and one NEW bash test suite — four distinct surface classes,
   beyond the WORKFLOW.md L1 definition ("small single-surface fix").
2. Security class: the never-echo guarantee is the heart of the change — the
   intake itself states an accidental credential echo into a committed doc is
   a security incident, not a bug. That warrants L2's full independent
   validation and mandatory review, not the L1 declared-scope-only lane.
It touches NO `protected_paths_l3` entry (verified against
docs/ai/docs-audit.yaml), so L3 is not forced.

## Problem statement (verified facts)
1. `.aai/INTAKE_CHANGE.prompt.md`, `.aai/INTAKE_ISSUE.prompt.md`,
   `.aai/INTAKE_COMMON.md`, and both templates contain no step, wording, or
   field that touches secret/credential references (verified by read,
   2026-07-17): a scope naming `DB_PASSWORD` or `sftp.credentials.api_key`
   passes intake with zero signal about local availability.
2. Without a narrow helper, an LLM's natural tool-use for "check whether
   DB_PASSWORD is set" is `echo $DB_PASSWORD` or `cat config.json` — which
   puts the value into the transcript. Node's own `JSON.parse` SyntaxError
   messages can quote file content, so even a naive helper leaks on the
   error path. Safety must be by construction, not by prompt discipline.
3. Budget constraints (measured 2026-07-17 on main):
   - `tests/skills/test-aai-prompt-diet.sh` TEST-003 caps the 8 INTAKE_*
     prompts at 240 combined lines; current total is 232 → 8 lines of
     headroom. `.aai/INTAKE_COMMON.md` lines do NOT count against this cap.
   - TEST-010 (corpus byte floor) ALREADY FAILS on clean main (net reduction
     24341 < 28672 required; known pre-existing, DEBT-0002, recorded in
     docs/knowledge/LEARNED.md). Corpus bytes (`.aai/*.prompt.md` +
     `INTAKE_COMMON.md`) must grow minimally; verbose text belongs in the
     script header and templates (both outside the corpus).
4. docs/TECHNOLOGY.md constraints: Node stdlib only, plain `node`
   invocation, no YAML library exists in-repo — YAML config parsing cannot
   be supported without violating the zero-dependency rule.
5. No docs/canonical/ layer exists → no `## Deltas` section applies.

## Design decisions
- D1 (helper + CLI grammar): NEW `.aai/scripts/secrets-preflight.mjs`
  (Node stdlib only, plain `node` invocation). Closed grammar:
  `node .aai/scripts/secrets-preflight.mjs --env NAME [--env NAME2 ...]
  [--file <path> --key <dotted.key> [--key ...]] [--file <path2> --key ...]`
  Each `--env NAME` is one check; each `--key` binds to the most recent
  `--file`. Supported file formats by extension: `.json` (JSON.parse +
  dotted-path walk) and `.env` / basenames starting with `.env` (line-scan
  `KEY=` / `export KEY=`, first match wins, one pair of matching surrounding
  quotes stripped before the length test). Any other extension (including
  `.yaml`/`.yml`) is a usage error with a fixed message naming the supported
  formats — YAML is explicitly out of scope v1 (fact 4; recorded limitation,
  extend incrementally per the intake's own constraint).
- D2 (output contract): stdout carries exactly one line per requested check:
  `env:<NAME> <status>` or `file:<path>#<key> <status>` where `<status>` is
  exactly one of the closed set `exists` (present and non-empty), `empty`
  (present, zero-length after quote-strip), `missing` (unset / key absent /
  file absent). Nothing else is written to stdout. References (names, paths,
  keys) are not secret and may be echoed; VALUES never.
- D3 (exit contract — informational, non-blocking): 0 = every requested
  check classified (regardless of statuses — `missing` is a recorded fact,
  not an error; preserves the intake's non-blocking posture); 2 = usage
  error (no checks requested, `--key` without a preceding `--file`, unknown
  flag, unsupported file format) with a fixed-string message; 1 = unexpected
  internal error, printing ONLY the fixed string
  `secrets-preflight: internal error (details suppressed)` — never
  `err.message`, never a stack trace.
- D4 (never-echo by construction — the heart): NO code path may place a
  secret value into stdout, stderr, an exception message, a tempfile, or any
  persisted artifact:
  - values are only ever tested for `undefined`/absence and `length === 0`;
    no value is interpolated into any output string;
  - unreadable file (ENOENT/EACCES/any read error) → every key against that
    file classifies `missing`, plus a fixed stderr note
    `note: <path>: unreadable (content not shown)`;
  - unparseable JSON → every key against that file classifies `missing`,
    plus the fixed stderr note `note: <path>: parse failed (content not
    shown)` — the caught error object is NEVER printed (fact 2: Node
    SyntaxError can quote file content);
  - a top-level try/catch enforces D3's exit-1 fixed string for anything
    unexpected;
  - no tempfile copies, no environment dumps, no debug mode that prints
    values.
- D5 (intake wiring, lean): `.aai/INTAKE_COMMON.md` gains one new block
  `## SECRETS PREFLIGHT (CHANGE-0034)` (lean, ~10 lines): when the scope
  references a local secret (env var or config key), never print/cat/echo
  it — run the helper and record one `ref → exists|empty|missing` line per
  reference in the saved doc's Constraints/Risks section; if the author
  states no secret is referenced, skip with zero extra questions; results
  are informational and never block saving the intake. The existing
  SHARED POLICY line in `.aai/INTAKE_CHANGE.prompt.md` and
  `.aai/INTAKE_ISSUE.prompt.md` is EDITED IN PLACE (no added lines —
  TEST-003 cap, fact 3) to also name the SECRETS PREFLIGHT block; the
  INTAKE_COMMON header sentence is adjusted so the four universal blocks
  stay universal and the new block applies where the dispatching prompt
  names it. The other six intake prompts are untouched. Guard rails from
  the prompt-diet suite honored: exactly one `Read .aai/INTAKE_COMMON.md`
  line per intake prompt (TEST-001), no moved-block markers reintroduced
  (TEST-002), verbose contract text lives in the script header (D9 of
  SPEC-0044, same discipline).
- D6 (templates, additive only): `.aai/templates/CHANGE_TEMPLATE.md` and
  `.aai/templates/ISSUE_TEMPLATE.md` each gain ONE bullet under the existing
  `## Constraints / Risks` section: a place to record per-reference
  preflight results (statuses only, never values). No heading added, no
  existing line removed (docs-audit checks are frontmatter/body-lint based,
  but a new required-looking heading would invite drift on every legacy
  doc — bullet stays inside an existing section).
- D7 (forward-looking additive): existing intake docs are never flagged or
  re-processed; a doc without preflight results stays valid. Repo-wide
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event` must stay
  exit 0 (intake AC-005).
- D8 (byte discipline, DEBT-0002): corpus additions (INTAKE_COMMON block +
  two edited SHARED POLICY lines) are capped at ≤ 1000 bytes total,
  measured at validation; intake line total stays ≤ 240 (zero added lines
  to the 8 INTAKE_* files). TEST-010's pre-existing failing floor worsens
  only by this recorded delta (same handling as SPEC-0044 R2).

## Implementation strategy
- Strategy: hybrid
- Rationale: the helper is security-class new behavior (PLANNING step 7:
  security/privacy involved → tdd) — TEST-001..003 get per-test RED-GREEN
  discipline, with the never-echo matrix (TEST-002) written and observed
  RED first. The canon/template wiring (TEST-004..006) is mechanical
  line-editing where loop implementation suffices; their grep-wired tests
  still satisfy the RED-proof obligation by being observed failing against
  unedited canon before the edits land.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive scope — one new script, one new test suite,
  lean edits to three prompts and two templates; no protected paths, no
  migrations, no cross-cutting refactor. The operator has ALREADY recorded
  `user_decision: inline` for this scope ("operator-approved: inline on
  feat/intake-secrets-preflight" in STATE); Planning does not override that
  recorded decision.
- User decision: inline (pre-recorded by operator)
- Base ref: main
- Inline review scope: see Code review scope below.
- Code review required: true (new executable with a security contract +
  workflow-prompt + template + test changes)
- Code review scope (explicit paths):
  `.aai/scripts/secrets-preflight.mjs`, `.aai/INTAKE_COMMON.md`,
  `.aai/INTAKE_CHANGE.prompt.md`, `.aai/INTAKE_ISSUE.prompt.md`,
  `.aai/templates/CHANGE_TEMPLATE.md`, `.aai/templates/ISSUE_TEMPLATE.md`,
  `tests/skills/test-aai-secrets-preflight.sh`,
  `docs/specs/SPEC-0045-spec-intake-secrets-preflight.md`,
  `docs/issues/CHANGE-0034-intake-secrets-preflight.md`, `docs/INDEX.md`

## Acceptance Criteria Mapping
- Maps to: CHANGE-0034 AC-001
  - Spec-AC-01: `.aai/scripts/secrets-preflight.mjs` exists implementing the
    closed CLI grammar (D1), the one-line-per-check output contract with the
    three-way closed status set (D2), and the 0/2/1 exit contract (D3), with
    no code path that logs, prints, returns, or persists an underlying value
    (D4).
  - Verification: TEST-001 (classification matrix), TEST-003 (usage/exit
    contract).
- Maps to: CHANGE-0034 AC-004 (never-echo guarantee)
  - Spec-AC-02: fixture proof over EVERY output path: with a known sentinel
    value planted in (a) an env var, (b) a JSON config value, (c) a `.env`
    value, and (d) a MALFORMED JSON file containing the sentinel (parse-error
    path), the combined stdout+stderr of each helper invocation contains the
    correct classification and does NOT contain the sentinel anywhere; the
    parse-error and unreadable-file paths emit only the fixed-string notes
    (D4).
  - Verification: TEST-002 (security fixture matrix, RED-first).
- Maps to: CHANGE-0034 AC-002
  - Spec-AC-03: `.aai/INTAKE_COMMON.md` carries the SECRETS PREFLIGHT block
    (names the script path, the three statuses, the never-print rule, the
    skip rule, and the non-blocking rule) and the SHARED POLICY lines of
    `.aai/INTAKE_CHANGE.prompt.md` and `.aai/INTAKE_ISSUE.prompt.md` name it
    (D5); a sample intake run's saved markdown records per-reference
    statuses (proven by the TEST-005 e2e dry-run constructing a DRAFT doc
    per the block's instructions, passing strict audit, containing the
    recorded statuses and no sentinel).
  - Verification: TEST-004 (canon grep contract), TEST-005 (e2e dry-run).
- Maps to: CHANGE-0034 AC-003
  - Spec-AC-04: skippability and non-blocking posture: the block's text
    states zero extra questions when no secret is referenced and that
    results never block saving (D5); mechanically, a `missing` result still
    exits 0 (D3).
  - Verification: TEST-004 (text pins), TEST-003 (missing → exit 0 arm).
- Maps to: CHANGE-0034 AC-005 (+ budget guards, fact 3)
  - Spec-AC-05: additive safety: repo-wide
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0
    after all edits; the 8 INTAKE_* prompts total ≤ 240 lines (zero added
    lines); template edits are additive (no existing section or line
    removed); corpus byte delta ≤ 1000 bytes recorded in validation notes
    (D8).
  - Verification: TEST-006 (regression + budget probes).

## Constitution deviations

None.

(Checked at freeze: art. 1 — every AC verified by executable fixtures; art. 2
— three-way classification only, no speculative YAML support or secrets
management; art. 3 — plain stdlib-only script, git-diffable prompt/template
lines; art. 4 — unreadable/unparseable inputs degrade to `missing` with an
explicit fixed-string report, usage errors fail fast, and the deliberate
suppression of error detail on secret-adjacent paths is the security design,
reported as such rather than silent; art. 5 — additive at every boundary
(templates, prompts, existing intake docs stay valid); art. 6 — STATE
untouched by the helper, writes only via state.mjs; art. 7 — not applicable.)

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Helper: closed grammar, 3-way status, 0/2/1 exit contract, no value output path | done | TEST-001/TEST-003 green; docs/ai/tdd/green-20260717T150502Z-intake-secrets-preflight-test001-006.log | — | .aai/scripts/secrets-preflight.mjs |
| Spec-AC-02 | Never-echo fixture proof incl. parse-error path        | done | TEST-002 green; docs/ai/tdd/red-20260717T150316Z-intake-secrets-preflight-test002-security-first.log (RED-first); docs/ai/tdd/green-20260717T150502Z-intake-secrets-preflight-test001-006.log | — | sentinel absent from combined stdout+stderr across 5 invocation shapes |
| Spec-AC-03 | Intake wiring: COMMON block + CHANGE/ISSUE policy lines + recorded results | done | TEST-004/TEST-005 green; docs/ai/tdd/red-20260717T150345Z-intake-secrets-preflight-test004-canon.log (RED on unedited canon); docs/ai/tdd/green-20260717T150502Z-intake-secrets-preflight-test001-006.log | — | .aai/INTAKE_COMMON.md, .aai/INTAKE_CHANGE.prompt.md, .aai/INTAKE_ISSUE.prompt.md |
| Spec-AC-04 | Skippable with zero questions; results never block     | done | TEST-004/TEST-003 green; docs/ai/tdd/green-20260717T150502Z-intake-secrets-preflight-test001-006.log | — | — |
| Spec-AC-05 | Additive: strict audit 0, line cap 240, byte delta ≤1000B | done | TEST-006 green; `docs-audit --check --strict --no-event` exit 0; intake total unchanged (232≤240, zero added lines); corpus byte delta 791B (≤1000B: INTAKE_COMMON +641B, INTAKE_CHANGE +75B, INTAKE_ISSUE +75B) | — | templates additive-only, headings intact |

## Implementation plan
Edit points (all additive; corpus edits lean per D5/D8):
1. `.aai/scripts/secrets-preflight.mjs` — NEW (~140 lines): argv parse per
   D1 closed grammar; env checks via `process.env[NAME]` (undefined →
   missing, '' → empty, else exists); `.json` via readFile + JSON.parse in
   try/catch (catch → all keys `missing` + fixed note, error object never
   printed); `.env` via line-scan; dotted-path walk for JSON keys (absent
   node at any hop → missing; non-string terminal → String-coerce for the
   length test only); top-level try/catch → exit 1 fixed string. Header
   comment carries the full verbose contract (grammar, statuses, exit codes,
   never-echo rules, YAML-unsupported note) — SPEC-0044 precedent.
2. `.aai/INTAKE_COMMON.md` — new `## SECRETS PREFLIGHT (CHANGE-0034)` block
   (~10 lines) per D5; header sentence adjusted (four universal blocks +
   the conditional block where the dispatching prompt names it).
3. `.aai/INTAKE_CHANGE.prompt.md` + `.aai/INTAKE_ISSUE.prompt.md` — edit the
   existing SHARED POLICY line in place to name the SECRETS PREFLIGHT block
   (zero added lines).
4. `.aai/templates/CHANGE_TEMPLATE.md` + `.aai/templates/ISSUE_TEMPLATE.md`
   — one bullet each under `## Constraints / Risks` per D6.
5. `tests/skills/test-aai-secrets-preflight.sh` — NEW bash-3.2-compatible
   suite (pattern: tests/skills/test-aai-tdd-evidence.sh; scratch fixtures
   under a mktemp dir, cleaned on EXIT; runnable via
   `.aai/scripts/aai-run-tests.sh` per the LEARNED wrapper rule).
Edge cases pinned: env var set to whitespace → exists (non-zero length; no
trimming — length semantics only); JSON key whose value is `null` → empty
(String(null) is not the value's content; classify by explicit rule: null →
empty); dotted key traversing a non-object → missing; `.env` line with
`export KEY=""` → empty; duplicate `--env NAME` → two independent lines
(idempotent); file path with `#` in it is unambiguous because output joins
path and key with `#` only for display.

## Seam analysis
- Seam 1: the invocation INTAKE_COMMON documents ↔ the argv grammar the
  script accepts. Crossed end-to-end by TEST-005 (the documented invocation
  form is executed verbatim against real fixtures) and pinned textually by
  TEST-004 (the block names the literal script path).
- Seam 2: the recorded-results wording in the templates/INTAKE_COMMON ↔ the
  strict docs-audit over saved intake docs. Crossed by TEST-005: a DRAFT
  intake doc constructed per the block's instructions (results bullet under
  Constraints/Risks) passes `docs-audit --check --strict --no-event --path`
  (precedent: prompt-diet TEST-004 e2e dry-run).
- Seam 3: prompt-diet budget suite ↔ corpus edits. TEST-006 re-computes the
  TEST-003 line-cap predicate directly (≤ 240) instead of re-running the
  prompt-diet suite, because that suite's TEST-010 already fails on clean
  main (fact 3; running it would mask results — LEARNED 2026-07-17). The
  TEST-010 byte-floor worsening is not automatable as a pass and is handled
  as a recorded delta in validation notes (R2).
- Residual seam risk: whether a live intake AGENT actually runs the helper
  is LLM behavior, not mechanically forceable — text pinned by TEST-004,
  recorded as R1.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                        | Description                                                                                                    | Status  |
|----------|------------|-------------|---------------------------------------------|----------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-secrets-preflight.sh  | Classification matrix: env set/empty/unset → exists/empty/missing; JSON dotted key present/""/absent-key/absent-file → exists/empty/missing/missing; .env KEY=v / KEY= / absent → exists/empty/missing; every classification run exits 0; output is exactly one `ref status` line per check | green  |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-secrets-preflight.sh  | Never-echo matrix (security): sentinel planted in env, JSON value, .env value, and a MALFORMED JSON containing the sentinel; combined stdout+stderr of every invocation (success, parse-error, unreadable-file, usage-error) never contains the sentinel; parse/unreadable paths emit only the fixed-string notes | green  |
| TEST-003 | Spec-AC-01, Spec-AC-04 | unit | tests/skills/test-aai-secrets-preflight.sh  | Exit contract: no args → 2; `--key` without `--file` → 2; unknown flag → 2; `.yaml` file → 2 with fixed unsupported-format message; a run whose statuses include `missing` still exits 0 (non-blocking posture) | green  |
| TEST-004 | Spec-AC-03, Spec-AC-04 | unit | tests/skills/test-aai-secrets-preflight.sh  | Canon grep contract: INTAKE_COMMON block names the script path, all three statuses, the never-print rule, zero-extra-questions skip, and never-blocks-saving; CHANGE/ISSUE SHARED POLICY lines name the block; prompt-diet guard rails hold (exactly one `Read .aai/INTAKE_COMMON.md` per intake prompt) — REDs on unedited canon | green  |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-secrets-preflight.sh  | E2e dry-run (Seams 1+2): execute the documented invocation verbatim against fixtures; construct a DRAFT intake doc per the block's instructions with the recorded statuses; `docs-audit --check --strict --no-event --path` exits 0 on it; doc contains `exists`/`missing` statuses and does NOT contain the sentinel; fixture doc deleted on exit | green  |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-secrets-preflight.sh  | Additive/budget regression: repo-wide `docs-audit --check --strict --no-event` exits 0; the 8 INTAKE_* files total ≤ 240 lines; both templates still contain every pre-change section heading; `bash tests/skills/test-aai-intake.sh` still exits 0 | green  |

RED-proof: TEST-001..003 MUST be observed failing before the script exists
(invocation fails); TEST-002 in particular is written FIRST (security class).
TEST-004 MUST be observed failing against unedited canon; TEST-005 fails
until both the script and the canon block exist. TEST-006 is a
baseline-green regression guard BY DESIGN (recorded RED-waiver, SPEC-0044
TEST-005 precedent: it pins pre-existing behavior; the anti-tautology
obligation for the change itself is carried by TEST-001..005).

## Verification
- `bash tests/skills/test-aai-secrets-preflight.sh` → exit 0 (TEST-001..006),
  run via `.aai/scripts/aai-run-tests.sh` per the LEARNED wrapper rule.
- `bash tests/skills/test-aai-intake.sh` → exit 0 (regression).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0
  (intake AC-005).
- Manual dry run (intake Verification): a CHANGE intake naming one env var
  exercised end-to-end via `.aai/INTAKE_CHANGE.prompt.md`; the saved doc
  records the status line and no value.
- Byte delta probe (D8): corpus bytes (`cat .aai/*.prompt.md | wc -c` plus
  `wc -c .aai/INTAKE_COMMON.md .aai/STATE_FALLBACK.md`) measured before/after;
  delta ≤ 1000 bytes recorded in validation notes.
- Known pre-existing failures (NOT gates for this scope, verified on clean
  main 2026-07-17: prompt-diet suite output re-confirmed this session):
  `test-aai-prompt-diet.sh` TEST-010 byte floor (net reduction 24341 <
  28672 pre-change; this change adds ≤ 1000 corpus bytes — re-record the
  delta); `test-aai-worktree.sh` scratch-git fixture;
  `test-aai-ceremony-levels.sh` test_010_seam_survival (transitively
  re-runs prompt-diet).

## Residual risks
- R1: Whether a live intake agent actually invokes the helper (instead of
  echoing a value) is LLM behavior — the canon text pins the duty and the
  never-print rule, but adherence is not mechanically enforced (same
  accepted class as SPEC-0043/0044 R1).
- R2: Prompt-diet TEST-010 net-reduction worsens by the ≤ 1000-byte corpus
  delta (already failing pre-existing, DEBT-0002; D8 caps and records it).
- R3: YAML config files are unsupported in v1 (zero-dependency rule) — a
  scope whose secret lives in a YAML config gets a usage error, not a
  classification; the helper's fixed message names the supported formats so
  the gap is explicit, and format extension is an incremental follow-up per
  the intake's own constraint.
- R4: The three-way classification is local-environment truth only — it
  says nothing about value correctness/expiry (explicitly out of scope per
  the intake).

## Evidence contract
For each implementation, validation, TDD, and code review artifact record:
ref_id `intake-secrets-preflight`, Spec-AC + TEST-xxx links, command or
review scope, exit code or verdict, evidence path, commit SHA/diff range.
