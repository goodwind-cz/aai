---
id: spec-friction-capture-foundation
type: spec
number: 78
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0045-friction-capture-foundation.md
  rfc: RFC-0012
  pr:
    - 143
  commits:
    - 88232f977dec60d75ba246b760ec03af02e194a8
---

# Implementation Spec — RFC-0012 Phase 0: friction capture foundation

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0045-friction-capture-foundation.md
- Decision records: docs/rfc/RFC-0012-aai-self-improvement-feedback-loop.md
  "## Decisions (resolved 2026-07-25, project owner)" (D1-D8, binding, frozen —
  not re-litigated here) + "### Privacy reconciliation"
- Technology contract: docs/TECHNOLOGY.md

## Scope (frozen — Phase 0 only)
Deliver ONLY the offline capture foundation of RFC-0012:
1. `.aai/system/FRICTION_PROTOCOL.md` — canonical taxonomy + versioned schema v1
   + D6 allowlist + v1 fingerprint algorithm + redaction policy.
2. `.aai/scripts/aai-friction.mjs` — dependency-free (node stdlib only) offline
   `record --input <json>` CLI.
3. `docs/ai/friction/` — gitignored JSONL spool (`.gitkeep` + `.gitignore` stanza).
4. `.aai/system/PROFILES.yaml` — classification of both new `.aai/**` files.
5. `tests/skills/test-aai-friction.sh` — skill-suite coverage.

Explicitly OUT of scope (do not implement here — later RFC-0012 phases):
triage/upsert, the maintainer skill, `.aai/feedback.yaml` modes, any GitHub
write, budget/cooldown, fingerprint clustering, wiring the protocol into
`*.prompt.md` skill prompts, network/mode gating (there is no network path in
Phase 0 to gate).

## Ceremony level rationale
`ceremony_level: 2` (full pipeline), not the dispatcher's offered L1. L1 fits a
"small single-surface fix"; this scope adds a NEW production script
(`aai-friction.mjs`) plus a new frozen contract (`FRICTION_PROTOCOL.md`,
schema v1, fingerprint v1) that establishes a privacy guarantee (D6
deny-by-default, no-network) later phases build on and RFC-0012's privacy
reconciliation requires be "skill-suite-enforced." That is materially more
than a single-surface fix, and under-validating it at L1 would leave the
privacy contract's structural properties (allowlist-not-denylist, atomic
write, no-network) unverified by a full independent validation pass. L2 keeps
required full validation + required single dual-verdict code review without
paying L3's protected-surface ceremony. Confirmed: this scope touches NO path
in `protected_paths_l3` (docs/ai/docs-audit.yaml: `.aai/scripts/state.mjs`,
`.aai/scripts/lib/state-engine.mjs`, `.aai/scripts/lib/state-core.mjs`,
`.aai/scripts/allocate-doc-number.mjs`, `.aai/scripts/pre-commit-checks.sh`,
`.aai/scripts/pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`,
`docs/CONSTITUTION.md`) — so L3 is not mandatory. Because level is 2, no
`Ceremony justification:` line is required by the close gate (that applies
only to L0/L1).

## Implementation strategy
- Strategy: tdd
- Rationale: every privacy- and correctness-critical property in this scope is
  a clean, deterministic RED/GREEN pair with no external dependency — schema
  accept/reject, D6 deny-by-default allowlist filtering, fingerprint
  determinism, and atomic single-line write are pure-function-shaped behaviors
  of a brand-new script that does not exist yet (guaranteed real RED). This is
  also privacy-critical new surface (D6) and touches security/data-integrity
  concerns (Planning strategy rule: tdd for privacy/security-involved work).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single self-contained scope (one new script, one new
  system doc, one new test file, two additive config edits), fully reversible,
  touches no `protected_paths_l3` surface, and already isolated on its own
  dedicated branch (`feat/friction-capture-foundation`, branch-per-work-item
  hygiene per SPEC-0070) off `main`. No cross-cutting refactor and no parallel
  subagent fan-out is planned.
- User decision: undecided
- Base ref: main
- Worktree branch/path: n/a (not_needed)
- Inline review scope: `.aai/system/FRICTION_PROTOCOL.md`, `.aai/scripts/aai-friction.mjs`,
  `docs/ai/friction/.gitkeep`, `.gitignore` (new stanza only), `.aai/system/PROFILES.yaml`
  (two new classification entries only), `tests/skills/test-aai-friction.sh`

## Companion obligations check (Planning step 3a)
Closed two-entry list, evaluated explicitly:
- Prompt-corpus growth (`.aai/*.prompt.md`, `.aai/AGENTS.md`)? NO file in this
  scope is a `*.prompt.md` or `AGENTS.md`. `FRICTION_PROTOCOL.md` is a SYSTEM
  doc (`.aai/system/*.md`), not a prompt. -> prompt-diet ledger true-up does
  NOT apply; no `tests/skills/lib/prompt-diet-ledger.sh` entry needed.
- New `.aai/**` file(s)? YES — TWO: `.aai/scripts/aai-friction.mjs` and
  `.aai/system/FRICTION_PROTOCOL.md`. -> `.aai/system/PROFILES.yaml`
  classification IS required and IS in scope (item 4 above; TEST-014 below).

## Acceptance Criteria Mapping
For each requirement AC (from CHANGE-0045-friction-capture-foundation
"## Verification" and "## Scope"):

- Maps to: Verification bullet "Schema validation"
- Spec-AC-01: `.aai/system/FRICTION_PROTOCOL.md` exists and documents, as
  distinct labeled sections, all of: the failure-class taxonomy with
  inclusions/exclusions, the versioned observation schema v1 field list, the
  D6 persisted-field allowlist (closed set), the v1 fingerprint algorithm
  (normalization steps + version tag), and the redaction/privacy policy.
- Verification: `test -f .aai/system/FRICTION_PROTOCOL.md`; grep the file for
  required section headers; expected evidence: file present, all five
  sections found exactly once each.

- Maps to: Verification bullet "Schema validation"
- Spec-AC-02: `node .aai/scripts/aai-friction.mjs record --input <json>`
  (path or stdin) accepts a well-formed schema-v1 observation and appends
  exactly one JSONL line to the spool; a missing required field or a
  wrong-typed field is rejected with a clean non-zero exit and NO spool write.
- Verification: run `record` with a well-formed fixture (exit 0, spool line
  count +1); run `record` with a fixture missing a required field and with a
  fixture where a field has the wrong type (each: non-zero exit, spool line
  count unchanged, stderr names the offending field).

- Maps to: Verification bullet "D6 allowlist enforced STRUCTURALLY"
- Spec-AC-03: the persisted spool line for any accepted `record` call
  contains ONLY the D6 allowlisted keys (schema_version, os_family, aai_pin,
  node_major, skill_id, skill_phase, failure_class, fingerprint) — any other
  key present in the input, WHETHER a named forbidden identity key (hostname,
  absolute path, repo remote, username, project id) OR an unrelated/unknown
  key never named anywhere in the protocol, is structurally dropped before
  the write.
- Verification: submit a well-formed input that ALSO includes forbidden
  identity keys and one wholly novel unclassified key; parse the persisted
  spool line as JSON; assert its key set is a subset of (and, for populated
  fields, equal to) the allowlist — expected evidence: none of the injected
  extra keys appear in the written line.

- Maps to: Verification bullet "No network / no token (structural)"
- Spec-AC-04: `aai-friction.mjs` performs NO network I/O and holds NO GitHub
  token; the source contains no networking primitive, and `record` succeeds
  with network access unavailable.
- Verification: `grep -inE "net|http|https|fetch|child_process|socket|gh " .aai/scripts/aai-friction.mjs`
  finds no networking call (documented false-positive terms, if any, are
  enumerated and excluded explicitly, not silently); run `record` with a
  well-formed fixture under a sandboxed/offline environment (unroutable
  proxy env vars set) — exit 0, spool line written.

- Maps to: Verification bullet "Fingerprint determinism"
- Spec-AC-05: the v1 fingerprint is a pure, documented, deterministic
  function of a normalized observation — the SAME normalized observation
  yields the SAME fingerprint string across independent `record` invocations
  (including across simulated different machines, i.e. no environment-derived
  entropy), and the fingerprint string is version-tagged (`v1:` prefix).
- Verification: run `record` twice with byte-identical input (fresh spool
  each run); assert the two persisted `fingerprint` values are equal and both
  start with `v1:`; run once more with a semantically-identical but
  differently-whitespaced/cased input in the fields the algorithm normalizes
  — assert the fingerprint is unchanged (proves normalization, not raw
  string hashing).

- Maps to: Verification bullet "Atomic write"
- Spec-AC-06: `record` writes exactly one complete JSONL line per accepted
  call via a concurrency-safe O_APPEND append (`appendFileSync`); no
  interrupted, rejected, OR concurrent call ever leaves a partial/truncated
  line or silently drops a line in the spool. O_APPEND atomicity holds only
  for a line strictly under PIPE_BUF (4096 bytes), so that bound is ENFORCED,
  not assumed: the persisted string fields (`skill_id`, `skill_phase`,
  `failure_class`) are capped at 128 chars each, and `record` rejects (clean
  non-zero exit, no spool write) any serialized line that would reach
  PIPE_BUF — a line at or above the bound is never appended. (Correction,
  post-Validation: the atomic mechanism is an O_APPEND per-line append, NOT a
  read-modify-write temp-file-then-rename which loses lines under concurrent
  writers; and the sub-PIPE_BUF invariant rests on the caps plus the hard
  line-length guard, not on an unverified size assumption.)
- Verification: three sequential accepted `record` calls against one spool
  file -> exactly 3 lines, each independently `JSON.parse`-able; a rejected
  (schema-invalid) call leaves the line count unchanged; N concurrent
  `record` calls against one spool -> exactly N well-formed lines (no loss);
  an over-cap record whose serialized line would reach PIPE_BUF is rejected
  with no spool write; source review confirms an `appendFileSync` (O_APPEND)
  write path with no read-modify-write of the spool, plus the per-field caps
  and the pre-append line-length guard.

- Maps to: Verification bullet "Capture-does-not-mask"
- Spec-AC-07: `aai-friction.mjs record` is a side-effect-isolated standalone
  process — a bad input exits non-zero with a clean, single-purpose error on
  stderr, never a false success signal, and never an uncaught-exception stack
  trace that a wrapper script could misinterpret.
- Verification: run `record` with malformed input inside a wrapper
  (`... && echo WRAPPER_OK`) — `WRAPPER_OK` never printed; exit code is a
  specific documented non-zero value (not an unhandled-exception default);
  stdout is empty on rejection.

- Maps to: Scope item 3 (spool)
- Spec-AC-08: the spool directory `docs/ai/friction/` is gitignored except for
  a tracked `.gitkeep`; JSONL files written into it by `record` are never
  tracked by git.
- Verification: `.gitignore` contains a `docs/ai/friction/**` stanza
  mirroring the existing `docs/ai/briefs/**`/`docs/ai/reports/**` pattern;
  `git check-ignore -q docs/ai/friction/<generated-file>.jsonl` exits 0 after
  a real `record` run; `git status --porcelain` shows no untracked/modified
  entry for the generated spool file.

- Maps to: Scope item 4 / Companion obligations check
- Spec-AC-09: `.aai/system/PROFILES.yaml` classifies BOTH new `.aai/**` files
  (`.aai/scripts/aai-friction.mjs`, `.aai/system/FRICTION_PROTOCOL.md`) into
  exactly one of `core`/`extended`; `tests/skills/test-aai-layer-profiles.sh`
  stays green (100% classification of the live `.aai` tree, no stale/duplicate
  entries).
- Verification: `tests/skills/test-aai-layer-profiles.sh` exits 0; grep
  `PROFILES.yaml` for both new paths — each appears exactly once, under
  exactly one profile list.

- Maps to: Scope item 2 ("Include --help documenting the contract")
- Spec-AC-10: `aai-friction.mjs --help` (and no/invalid args) documents the
  `record --input <path|-> ` contract, the D6 allowlist guarantee, and the
  no-network guarantee, and exits 0.
- Verification: `node .aai/scripts/aai-friction.mjs --help` exits 0; stdout
  mentions `record`, `--input`, and the words `allowlist` and `network`.

- Maps to: Verification bullet "Portability"
- Spec-AC-11: `aai-friction.mjs` is Node-stdlib-only (no non-`node:`-prefixed
  imports) and cross-platform; `tests/skills/test-aai-friction.sh` uses full
  `mktemp` templates and POSIX-safe constructs, green on Linux CI and macOS.
- Verification: `grep -n "^import\|require(" .aai/scripts/aai-friction.mjs`
  — every import target starts with `node:`; grep the test file for
  `mktemp -d` usage with a full `XXXXXX` template (not a bare `mktemp`).

- Maps to: Verification bullet "Full skill suite green"
- Spec-AC-12: the full skill test suite is green after this change, including
  `tests/skills/test-aai-layer-profiles.sh`, with no prompt-diet regression
  (no `*.prompt.md`/`AGENTS.md` file is touched by this scope).
- Verification: run the project's full test runner (`.aai/scripts/aai-run-tests.sh`
  or documented equivalent per docs/TECHNOLOGY.md) — exit 0 across all
  suites; `tests/skills/test-aai-prompt-diet.sh` unaffected (no diff in its
  ledger-required inputs).

## Seam analysis (cross-feature integration)
- Seam 1 — `.aai/system/PROFILES.yaml` is READ by both
  `tests/skills/test-aai-layer-profiles.sh` (classification-completeness
  gate) AND `.aai/scripts/aai-sync.sh`/`aai-sync.ps1` (the real distribution
  engine, `--profile core|extended`, consumed by every downstream project's
  `/aai-update`). Adding two entries here without a real end-to-end assertion
  would risk a classification that passes the completeness check but is
  wrong for sync. TEST-014 below runs the EXISTING
  `test-aai-layer-profiles.sh` suite, which already exercises real
  `aai-sync.sh`/`.ps1` fixture copies against the manifest — this crosses the
  seam end-to-end (classification -> real sync copy), not two isolated unit
  checks.
- Seam 2 — `.aai/system/AAI_PIN.md` is READ (not written) by
  `aai-friction.mjs` to derive the persisted `aai_pin` field; it is also read
  by `SKILL_DOCTOR` and the sync scripts elsewhere. This is a read-only
  consumption of an existing frozen contract; TEST-002's assertion that the
  persisted `aai_pin` equals the value stamped in `AAI_PIN.md` at test time
  (not a caller-supplied value) covers this without needing a new shared
  fixture.
- Seam 3 (considered, no seam) — `docs/ai/friction/*.jsonl` is NOT read by
  any existing consumer in Phase 0 (triage/upsert is explicitly out of
  scope); docs-audit and test-canon scan governed `docs/**/*.md`, not the
  gitignored JSONL spool, so no drift/classification risk exists there.
  Recorded as a residual note, not a test obligation, since there is nothing
  on the other side of this "seam" yet.

## Constitution deviations

None. (Article 3 "Portability": node-stdlib-only, plain JSONL/Markdown files,
tri-platform — satisfied by design. Article 6 "Single-writer state": does not
apply to `docs/ai/STATE.yaml` — a SEPARATE append-only spool whose writer
(`aai-friction.mjs`) uses a concurrency-safe O_APPEND per-line append is in
the same spirit (many concurrent writers, none lost). Article 5
"Additive first": every edit in scope is a pure addition — new files, new
`.gitignore` stanza, new `PROFILES.yaml` entries — no existing behavior is
modified.)

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | FRICTION_PROTOCOL.md canonical contract | done | TEST-001; green log | — | GREEN 2026-07-25 |
| Spec-AC-02 | Schema-v1 accept/reject | done | TEST-002/003/004; green log | — | GREEN 2026-07-25 |
| Spec-AC-03 | D6 deny-by-default allowlist enforcement | done | TEST-005/006; green log | — | GREEN 2026-07-25 |
| Spec-AC-04 | No network I/O, no token | done | TEST-007/008; green log | — | GREEN 2026-07-25 |
| Spec-AC-05 | Fingerprint v1 determinism + version tag | done | TEST-009; green log | — | GREEN 2026-07-25 |
| Spec-AC-06 | Atomic write, one JSONL line per call | done | TEST-010/011/018/019; green log | — | GREEN 2026-07-25 (O_APPEND + per-field caps + PIPE_BUF line guard) |
| Spec-AC-07 | Capture never masks the caller | done | TEST-012; green log | — | GREEN 2026-07-25 |
| Spec-AC-08 | Gitignored spool + tracked .gitkeep | done | TEST-013; green log | — | GREEN 2026-07-25 |
| Spec-AC-09 | PROFILES.yaml classifies both new files | done | TEST-014; green log | — | GREEN 2026-07-25 |
| Spec-AC-10 | --help documents the contract | done | TEST-015; green log | — | GREEN 2026-07-25 |
| Spec-AC-11 | Node-stdlib-only, cross-platform, portable test | done | TEST-016; green log | — | GREEN 2026-07-25 |
| Spec-AC-12 | Full skill suite green, no prompt-diet regression | done | TEST-014/017; green log | — | GREEN 2026-07-25 |

## Implementation plan
- Components/modules affected: `.aai/system/FRICTION_PROTOCOL.md` (new),
  `.aai/scripts/aai-friction.mjs` (new), `docs/ai/friction/.gitkeep` (new),
  `.gitignore` (additive stanza), `.aai/system/PROFILES.yaml` (two additive
  entries), `tests/skills/test-aai-friction.sh` (new).
- Data flow: caller (future phases; in Phase 0, exercised only by tests/manual
  invocation) builds a schema-v1 JSON observation -> `aai-friction.mjs record`
  validates it -> computes the v1 fingerprint from normalized input fields ->
  derives os_family/node_major from the running process and aai_pin from
  `.aai/system/AAI_PIN.md` -> structurally filters to the D6 allowlist ->
  atomically appends one JSONL line to `docs/ai/friction/<date-or-fixed-name>.jsonl`.
  Nothing downstream reads the spool yet (Phase 1+).
- Edge cases: empty/absent `--input`; input given via stdin vs. file path;
  oversized input (documented 65536-byte ceiling, rejected cleanly); spool
  directory absent on first run (created, not an error); concurrent `record`
  invocations — the COMMON case under AAI parallel agents — are lossless
  because the spool is written with an O_APPEND per-line append
  (`appendFileSync`): the kernel atomically advances each writer's offset to
  end-of-file, and a single write of one line under PIPE_BUF (4096 bytes on
  Linux/macOS) is never interleaved. That sub-PIPE_BUF bound is ENFORCED, not
  assumed: the persisted string fields (`skill_id`, `skill_phase`,
  `failure_class`) are capped at 128 chars, and `record` rejects any
  serialized line that would reach PIPE_BUF before appending. (Correction,
  post-Validation, in two steps: first, an earlier read-modify-write
  temp-file-then-rename was NOT concurrency-safe — two processes read the same
  snapshot and the later rename dropped the earlier line, reproduced as 20
  concurrent records yielding 18 lines; the O_APPEND append replaced it
  [TEST-018]. Second, the "line is ~200 bytes, well under PIPE_BUF"
  justification was FALSE — the allowlisted strings had no length cap, so a
  schema-valid 6000-char `skill_id` produced a 6221-byte line (1.5x PIPE_BUF)
  that could still interleave; the per-field caps plus the hard pre-append
  line-length guard make the bound true by construction [TEST-019].); non-UTF8
  or truncated JSON input (schema parse failure, clean non-zero exit).
- PROFILES.yaml classification decision: BOTH new files classified as
  `extended`. Rationale — per the manifest's own classification rule, `core`
  is "the workflow engine" (orchestration/role/intake prompts, state/docs/
  index/events scripts and their import closure, gates, loop/HITL/flush,
  distribution/health, templates the flows instantiate, canon); `extended`
  covers "reporting & publishing... integrations... one-off maintenance...
  self-hosting QA." Phase 0's capture CLI is explicitly NOT wired into any
  skill prompt or gate yet (wiring is Phase 1, out of scope here) — it is not
  invoked by, and does not block, any part of the core loop today. It is
  closest in kind to the existing `extended` self-improvement/telemetry
  tooling (`metrics-report.mjs`, `SKILL_DASHBOARD`, `SKILL_PROFILE`) rather
  than to a `core` gate like `tdd-evidence-check.mjs` or `branch-guard.mjs`,
  which actively block the loop today. Re-classification to `core` is
  expected at the Phase 1 wiring change, when a skill prompt begins invoking
  it in the default path — noted here so it is not lost.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)               | Description                                                                                                                                                                                                                                                    | Status  |
|----------|------------|-------------|-------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-friction.sh   | Grep FRICTION_PROTOCOL.md for the five required section labels (taxonomy, schema v1, D6 allowlist, fingerprint v1, redaction policy) — each found exactly once. RED (pre-fix): file does not exist, `test -f` exits 1. GREEN (post-fix): file exists, all five sections found.               | green   |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-friction.sh   | Well-formed schema-v1 fixture via `record --input` -> exit 0, spool line count +1, persisted `aai_pin` equals the value read directly from `.aai/system/AAI_PIN.md` at test time. RED (pre-fix): script absent, node exits non-zero, spool line count +0 (expected +1). GREEN (post-fix): exit 0, +1 line, aai_pin matches.        | green   |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-friction.sh   | Fixture missing a required field (e.g. skill_id) -> exit non-zero, stderr names `skill_id`, spool line count unchanged. RED (pre-fix): script absent -> generic module-not-found stderr, does NOT name the field (assertion on stderr content fails). GREEN (post-fix): specific field-naming rejection message.                     | green   |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-friction.sh   | Fixture with a wrong-typed field (e.g. `impact` given as an object instead of the documented enum/string) -> exit non-zero, stderr names `impact`, spool unchanged. RED (pre-fix): script absent, generic stderr, does not name `impact`. GREEN (post-fix): specific type-rejection message.                                          | green   |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-friction.sh   | Well-formed fixture that ALSO includes hostname, absolute_path, repo_remote, username, project_id -> `record` exits 0; parsed persisted line contains NONE of those five keys. RED (pre-fix): script absent, no line is ever written (0 lines, assertion over a non-existent line fails). GREEN (post-fix): 1 line written, forbidden keys absent.        | green   |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-friction.sh   | Same well-formed fixture PLUS one wholly novel key never named anywhere in the protocol (e.g. extra_debug_note) -> persisted line lacks that key too, proving deny-by-default (allowlist), not a denylist of known-bad names. RED (pre-fix): script absent, no line written. GREEN (post-fix): line written, novel key absent.       | green   |
| TEST-007 | Spec-AC-04 | unit        | tests/skills/test-aai-friction.sh   | Static grep of aai-friction.mjs source for networking tokens (net, http, https, fetch, child_process, socket) finds zero matches (documented allowed false positives, if any, excluded explicitly by name). RED (pre-fix): file does not exist, grep finds nothing to check (test fails on missing-file precondition, not a vacuous pass). GREEN (post-fix): file exists, zero real matches.    | green   |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-friction.sh   | `record` run with unroutable proxy env vars set (HTTP_PROXY/HTTPS_PROXY pointed at an unreachable address) on a well-formed fixture -> exit 0, spool line written (proves no network dependency). RED (pre-fix): script absent, exit non-zero, no line. GREEN (post-fix): exit 0, line written.   | green   |
| TEST-009 | Spec-AC-05 | integration | tests/skills/test-aai-friction.sh   | Same normalized observation submitted in two separate `record` invocations -> both persisted `fingerprint` values equal and both start with the literal prefix `v1:`; a third invocation whose normalized-away fields differ only in case/whitespace yields the SAME fingerprint. RED (pre-fix): script absent, no fingerprint values to compare (test fails on missing output). GREEN (post-fix): equal, version-tagged, normalization-stable.   | green   |
| TEST-010 | Spec-AC-06 | integration | tests/skills/test-aai-friction.sh   | Three sequential accepted `record` calls against one spool -> exactly 3 lines, each independently JSON-parseable; a 4th, schema-invalid call leaves the count at 3. RED (pre-fix): script absent, 0 lines after 3 calls (expected 3). GREEN (post-fix): 3, then still 3 after the rejected call.   | green   |
| TEST-011 | Spec-AC-06 | unit        | tests/skills/test-aai-friction.sh   | Source review assertion (corrected post-Validation): aai-friction.mjs appends via O_APPEND (`appendFileSync`) and does NOT read-modify-write the spool (grep confirms appendFileSync present, and no readFileSync-of-target / renameSync in the append path). RED (pre-fix): file does not exist, grep precondition fails. GREEN (post-fix): appendFileSync present, read-modify-write absent.       | green   |
| TEST-012 | Spec-AC-07 | integration | tests/skills/test-aai-friction.sh   | Malformed input run inside `... && echo WRAPPER_OK` -> WRAPPER_OK never printed; exit code is a specific documented non-zero value, not a language-default uncaught-exception code; stdout empty. RED (pre-fix): script absent — exit code is the shell's module-not-found default, not the documented value (assertion on the SPECIFIC code fails). GREEN (post-fix): documented code, no WRAPPER_OK, empty stdout.       | green   |
| TEST-013 | Spec-AC-08 | integration | tests/skills/test-aai-friction.sh   | After a real `record` run inside a throwaway git-tracked fixture copy of the repo's `.gitignore` rules, `git check-ignore -q docs/ai/friction/<generated>.jsonl` exits 0 and `git status --porcelain` shows no entry for it; `.gitkeep` itself IS tracked. RED (pre-fix): no `.gitignore` stanza exists yet, `git check-ignore` exits 1 (not ignored). GREEN (post-fix): exits 0.   | green   |
| TEST-014 | Spec-AC-09 | integration | tests/skills/test-aai-layer-profiles.sh | Full existing suite run (unmodified) after the two PROFILES.yaml entries land -> exit 0; grep PROFILES.yaml confirms both new paths present exactly once. Seam 1 coverage (real aai-sync fixture copy, not a mock). RED (pre-fix): suite fails today — the two new `.aai/**` files exist on disk but are unclassified, so TEST-001's completeness check in that suite fails. GREEN (post-fix): 100% classified, suite exits 0.       | green   |
| TEST-015 | Spec-AC-10 | unit        | tests/skills/test-aai-friction.sh   | `node .aai/scripts/aai-friction.mjs --help` exits 0; stdout contains `record`, `--input`, `allowlist`, and `network`. RED (pre-fix): script absent, non-zero exit, no stdout. GREEN (post-fix): exit 0, all four terms present.       | green   |
| TEST-016 | Spec-AC-11 | unit        | tests/skills/test-aai-friction.sh   | Every import in aai-friction.mjs is `node:`-prefixed (no bare package name); the test file itself uses full `mktemp -d ... XXXXXX` templates (grep confirms no bare `mktemp` call). RED (pre-fix): script absent, grep precondition fails. GREEN (post-fix): all imports node:-prefixed.        | green   |
| TEST-017 | Spec-AC-12 | e2e         | tests/skills/ (full runner)         | Full project test runner (per docs/TECHNOLOGY.md) exits 0 across all suites after this change, including test-aai-layer-profiles.sh (TEST-014) and an unaffected test-aai-prompt-diet.sh (no prompt file touched by this scope). RED (pre-fix): test-aai-layer-profiles.sh alone fails (see TEST-014), so the full runner is non-zero. GREEN (post-fix): full runner exits 0.       | green   |
| TEST-018 | Spec-AC-06 | integration | tests/skills/test-aai-friction.sh   | Concurrency (added post-Validation): spawn N (20) `record` processes in the background against ONE spool, `wait`, then assert the spool holds EXACTLY N well-formed JSON-parseable lines — no loss, no interleave. RED (against the pre-fix read-modify-write appendLine): fewer than N lines (reproduced 20 concurrent -> 15). GREEN (O_APPEND appendFileSync): exactly N lines.       | green   |
| TEST-019 | Spec-AC-06 | integration | tests/skills/test-aai-friction.sh   | Atomic-append size bound (added post-Code-Review): a record whose serialized line would reach PIPE_BUF (an over-cap 6000-char `skill_id`) is REJECTED with a clean non-zero exit and NO spool write; a normal record still records; N concurrent records whose `skill_id` is AT the 128-char cap yield EXACTLY N lines. RED (against pre-fix code with no caps/guard): the 6000-char `skill_id` is accepted, writing a 6221-byte line (1.5x PIPE_BUF). GREEN (per-field caps + pre-append line-length guard): rejected, no write; at-cap concurrency lossless.       | green   |

Notes:
- Every Spec-AC has at least one TEST-xxx entry (Spec-AC-02 has three,
  Spec-AC-03 has two by design per the deny-by-default proof obligation,
  Spec-AC-04/05 have two each covering static + behavioral properties, and
  Spec-AC-06 has four — TEST-010 sequential, TEST-011 static, TEST-018
  concurrent, TEST-019 the enforced PIPE_BUF size bound — after the
  post-Validation O_APPEND fix and the post-Code-Review atomicity-bound fix).
- RED-proof obligation: every row above is genuinely discriminating — either
  the target script/doc does not exist yet (structural RED: file-not-found,
  zero lines written, grep precondition failure) or the assertion targets a
  SPECIFIC value (a named field in an error message, a specific exit code,
  an exact prefix) that a generic pre-fix failure mode does not coincidentally
  satisfy. TEST-003/004/012 specifically assert message/exit-code CONTENT,
  not mere non-zero-ness, so an absent-script ENOENT/module-not-found failure
  does not vacuously pass them.
- No cell in this table (or elsewhere in this spec) contains a literal `|`
  character (SPEC-0072 pipe-table-drop hazard); env var pairs and command
  chains are written with `/` or spelled out, never `|`.
- Portability (docs/knowledge/LEARNED.md, 2026-07-19): `test-aai-friction.sh`
  spawns throwaway dirs via full `mktemp` templates
  (`mktemp -d "${TMPDIR:-/tmp}/aai-friction.XXXXXX"`), POSIX-safe, honors its
  own `#!/usr/bin/env bash` shebang; `aai-friction.mjs` is Node-stdlib-only —
  both green on Linux CI and macOS (TEST-016).
- All 19 TEST-xxx entries live in the single new file
  `tests/skills/test-aai-friction.sh`, except TEST-014 which re-runs the
  EXISTING, unmodified `tests/skills/test-aai-layer-profiles.sh` (no new test
  code there — the classification entries are the change under test) and
  TEST-017 which is the full-suite runner invocation.

## Verification
- Commands: `bash tests/skills/test-aai-friction.sh`;
  `bash tests/skills/test-aai-layer-profiles.sh`; the project's full skill
  test runner per docs/TECHNOLOGY.md "## Testing".
- Evidence artifacts: TDD red/green logs per TEST-xxx under `docs/ai/tdd/`;
  full-suite run log as validation evidence.
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in status done
  with non-empty Evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: friction-capture-foundation
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
