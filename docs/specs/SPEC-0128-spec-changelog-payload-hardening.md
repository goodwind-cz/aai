---
id: spec-changelog-payload-hardening
type: spec
number: 128
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0141-changelog-payload-hardening.md
  rfc: null
  pr:
    - 256
  commits:
    - a46aedb
---

# Spec — released-CHANGELOG class pin, dashboard payload embed hardening, link-form drift extraction

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0141-changelog-payload-hardening.md
- Source disposition: docs/ai/decisions.jsonl 2026-08-13T18:47 (ref CHANGE-0140, NB-1 + NB-2 + drift-anchor INFO)
- Review that proved both defects: docs/ai/reviews/review-20260813T184301Z-CHANGE-0140-reporting-docs-true-up.md
- Incident forensics: commit bc056cd (glued released heading, the damage), a69bd52 (surgical line-split fix, released region cmp-verified vs 9dc5d10)
- Closest test precedent: tests/skills/test-aai-release.sh test_024 (merge-base pin, origin/main-first base-ref resolution, honest soft-skips)
- Generator this scope hardens: `.aai/scripts/generate-dashboard.mjs` + `docs/dashboard-template.html` (the `{{METRICS_DATA}}` template-literal embed)
- Extractor this scope extends: tests/skills/test-aai-userguide-drift.sh `MENTION_RE`
- Frozen exit contracts this scope must not move: aai-release 0/1/42 (SPEC-0063 D6), generate-dashboard CLI 0/1/2 (docs/product/aai-dashboard.md)
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 (declared by the intake and kept) — the scope
adds two test functions to one existing suite, fixes one escape/substitution
block inside one deterministic generator, and widens one character class in one
existing test's extractor; nothing under `protected_paths_l3` is touched, no
exit code, CLI flag or template placeholder changes, and every acceptance
criterion below names a directly executable local command (L1 rule: the Test
Plan IS the declared validation scope).

## Summary

Three proven defects from the CHANGE-0140 ride, dispositioned as one follow-up
(decisions.jsonl 2026-08-13T18:47):

1. **CHANGELOG released-region protection is scope-luck, not a class guard.**
   bc056cd glued the released `## [v2026.08.13.2] — …` heading onto a
   CHANGE-0140 bullet — the THIRD glued/deleted-heading incident — and was
   caught only because TEST-026 (win-fallback suite) happens to pin the
   immediately-previous scope's literal with a BOL anchor. The review's
   repo-wide survey: every existing CHANGELOG pin is scope-specific; glue,
   deletion, retitle or reorder of ANY OLDER released heading is caught by
   nothing automated. Release history is immutable by definition, so the class
   guard is a byte-compare of the released region against the latest release
   tag's own copy of CHANGELOG.md.
2. **generate-dashboard.mjs payload embed is corruptible** (proven
   adversarially by the review AND flagged independently by Copilot). The
   escape chain at generate-dashboard.mjs:403-406 runs backslash-doubling LAST,
   re-exposing the backslash added by the backtick escape (`` ` `` → `` \` ``
   → `` \\` `` = escaped backslash + LIVE backtick), never escapes `${`, and
   feeds the payload to `String.replace` as a string replacement where `$&`
   patterns corrupt the substitution. A backtick or dollar-brace in any payload
   string kills the whole page (SyntaxError at load). Latent today only
   because run notes never reach the embedded payload.
3. **The userguide-drift forward extractor omits `[`**: a mention written in
   markdown-link form (`[/aai-x](…)`) evades the forward check — false
   negative only.

## Design decisions recorded at planning time (do not re-derive)

### D1 — latest-release-tag resolution (deterministic, CI-safe, never vacuous where it matters)

Resolution rule for the new release-suite pin (test_025/test_026):

1. List candidates with `git -C "$PROJECT_ROOT" tag --list 'v[0-9]*'
   --sort=-v:refname`, captured into a variable — NEVER through a pipeline
   (this suite runs `set -euo pipefail`; `… | head -1` dies of SIGPIPE on CI —
   LEARNED test-harness shell-options trap). Iterate lines via here-string.
2. Pick the FIRST candidate for which `git merge-base --is-ancestor <tag> HEAD`
   holds. That tag T is "the latest release this branch's history has
   incorporated".
3. Soft-skip (log_pass with a NAMED reason, test_024 discipline) only when:
   no tag matches `v[0-9]*`; no matching tag is an ancestor of HEAD;
   `git show T:CHANGELOG.md` fails; or T's CHANGELOG contains no `^## [v`
   heading. A live CHANGELOG missing T's headings is NEVER a skip — it is the
   FAIL this pin exists for.

Why this rule and not the two obvious alternatives:
- `git describe --tags --abbrev=0` selects by graph distance over ALL tag
  names; it coincides with "latest release" only on linear history and cannot
  be pattern-scoped without extra flags. Rejected for implicitness.
- `git tag --sort=-creatordate` depends on tag-object timestamps (retagging,
  backfilled tags, clock skew scramble it). `-v:refname` version sort is
  intrinsic to the name and CalVer-correct where lexical sort is not:
  v2026.08.13.2 sorts newer than v2026.08.13, and v2026.08.13.10 newer than
  v2026.08.13.2.
- The ancestor filter is what keeps the pin honest on branches forked BEFORE a
  newer release: the branch is compared against the newest release its own
  history contains, so the pin neither false-fails nor silently compares
  against unreachable content.

Where the pin has teeth (the TEST-024 origin/main lesson, restated for tags):
all three skill-suite CI jobs (`.github/workflows/skill-suite.yml`
select/skills-selected/skills-full) run `actions/checkout@v4` with
`fetch-depth: 0`, which fetches full history AND all tags — so on every CI run
of this repo the tag resolves and the compare executes. The pass message MUST
name the resolved tag (`… byte-identical vs v2026.08.13.2`), making every
green CI log a non-vacuity witness distinguishable from the skip messages.
The soft-skip arm exists for downstream/template repos without CalVer tags,
and test_026 proves the skip is named, not silent.

### D2 — escaping fix shape and scope (fix-at-cause in the ONLY generator that has the pattern)

Generator survey (this planning pass, repo-wide grep): the
`.replace('{{…}}', string)` template-embed pattern exists in EXACTLY ONE
script — `.aai/scripts/generate-dashboard.mjs` (five calls, lines 415-419;
the payload feeds a page-side JS template literal
`const rawMetricsData = \`{{METRICS_DATA}}\`` at docs/dashboard-template.html:423).
generate-factory-report.mjs, generate-overview.mjs, generate-live-status.mjs
and generate-docs-hub.mjs all build their HTML in-generator with
entity-escaping (`escapeHtml`) and write their data as sidecar JSON files —
a different, safe class. The fix is therefore LOCAL to generate-dashboard.mjs;
no shared helper is extracted (one call site — Constitution art. 2), and the
structural pin (TEST-004) guards the one real instance.

The fix, replacing generate-dashboard.mjs:403-406 + the :415 substitution:

1. Escape chain in THIS order (backslash first, `<` last):
   `JSON.stringify(data)` → `.replace(/\\/g, '\\\\')` → escape backticks →
   escape `${` → `.replace(/</g, '\u003c'-form)`. The `<` step inserts a
   SINGLE backslash after doubling, so the template literal decodes `\u003c`
   as a unicode escape back to `<` (keeping `</script>` out of the HTML byte
   stream) and JSON.parse sees the raw character. The old order (`<`, backtick,
   then backslash-doubling) is exactly what re-exposed the backtick.
2. Non-interpolating substitution: `.replace('{{METRICS_DATA}}', () => payload)`
   — a FUNCTION replacement disarms `$&`, `` $` ``, `$'` and `$n` replacement
   patterns in the payload. The four `{{PANEL_*}}` substitutions take the same
   function form for uniformity (their markup is generator-owned constant
   strings; this is hygiene, not a fix).
3. Truth criterion (what the tests assert, beyond any structural pin): the
   embedded payload, decoded by the template literal and `JSON.parse`, is
   deep-equal to the sidecar `dashboard-data.json` — for the hostile fixtures
   AND for the real ledger. `dashboard-data.json` itself is written BEFORE the
   escape chain and must be byte-identical pre/post fix (the fix touches only
   the HTML embed).

### D3 — released-region definition

The released region of a CHANGELOG.md is: from the FIRST line matching
`^## [v` (BOL-anchored, literal `## [v` prefix) through end-of-file.
Everything above it — the file preamble, the bare `## [unreleased]` scaffold,
and every per-entry `## [unreleased] — <title>` heading — is the unreleased
zone and never enters the compare, so unreleased-section edits (the normal
life of a PR) cannot trip the pin.

The pin: the live region must be BYTE-IDENTICAL (cmp, not line-diff) to the
same region extracted from `git show T:CHANGELOG.md` with T resolved per D1.
This works because at the moment tag T was cut, aai-release wrote T's own
heading as the first released heading with all prior history below it, and
release history is immutable: any later commit in T's descendants must carry
that exact byte range. Glue (heading absorbed into a bullet line — the bc056cd
shape) moves the region's start or bytes; deletion, retitle, reorder and
bullet edits at ANY depth change bytes; all FAIL naming T and the first
divergence (cmp byte/line output; the awk region extraction and cmp both run
without pipelines). A live file with NO `^## [v` line while T's region is
non-empty FAILS (never skips). The boundary case "unreleased scaffold
directly above the first released heading" is inherently handled: the
scaffold's heading does not match `^## [v`.

### D4 — everything locally provable

Every verification below is a local command: bash suites via
`bash .aai/scripts/aai-run-tests.sh …` (canonical invocation, CHANGE-0139),
the generator run against fixture METRICS.jsonl files under mktemp, node
one-liners for parse/deep-equal probes, and scratch git repos / scratch clones
for the RED replays. The one CI-side claim (tags present under
`fetch-depth: 0`) is not load-bearing for any AC verdict — it is the recorded
reason the soft-skip arm will not fire on this repo's CI, and the
tag-naming pass message makes any single CI log a checkable witness.

## Implementation strategy
- Strategy: hybrid
- Rationale: The three behavior arms get TDD with stored RED artifacts —
  each has a cheap deterministic RED available today: (AC-001) replaying the
  bc056cd glue and a deep-history mutation of the v2026.08.08-era heading in
  a scratch clone makes the new pin fire, and the pre-change tree has no such
  pin at all (RED = planted damage passes the whole suite); (AC-002) the
  hostile payload fixture kills the pre-change embedded script
  (`node --check` SyntaxError — the review already reproduced this); (AC-003)
  the pre-change `MENTION_RE` extracts nothing from the planted link-form
  control. The CHANGELOG entry and any doc touch-ups are loop-lane glue
  pinned by the same suites. No intake-recorded strategy choice exists for
  CHANGE-0141 (STATE's current `implementation_strategy` still carries the
  previous scope, source SPEC-DRAFT-spec-reporting-docs-true-up.md).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: work already lives on the dedicated branch
  feat/changelog-payload-hardening; no parallel scope shares these files
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/changelog-payload-hardening (existing branch, inline)
- Inline review scope: tests/skills/test-aai-release.sh,
  .aai/scripts/generate-dashboard.mjs, tests/skills/test-aai-dashboard.sh,
  tests/skills/test-aai-userguide-drift.sh,
  docs/specs/SPEC-0128-spec-changelog-payload-hardening.md,
  docs/issues/CHANGE-0141-changelog-payload-hardening.md, CHANGELOG.md

Code review required: true (code + test changes); scope = the explicit path
list above as a diff against main.

## Companion obligations check (closed list)
- Prompt corpus bytes move: NO — no `.aai/*.prompt.md` or `.aai/AGENTS.md`
  byte changes in scope.
- New `.aai/**` file: NO — generate-dashboard.mjs is edited in place; all new
  code lands in existing files under tests/skills/.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0141 AC-001
- Spec-AC-01: WHEN the release suite runs in a repo whose latest ancestor
  release tag is T (resolved per D1) THEN the live CHANGELOG's released
  region (per D3) is byte-compared against the same region of
  `git show T:CHANGELOG.md`; glue, deletion, retitle and reorder of ANY
  released heading at any age FAIL naming T and the first divergence;
  unreleased-zone edits never trip it; absence of a usable tag produces a
  soft-skip with a named reason (never a silent pass), and the pass message
  names the resolved tag.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` exits 0 with the test_025 pass line naming the resolved tag (v2026.08.13.2 today) and the test_026 scratch matrix proving FAIL-on-glue, FAIL-on-deep-mutation, PASS-on-unreleased-edit and named-skip-on-tagless; RED replay per the RED plan stored under docs/ai/tdd/.

- Maps to: CHANGE-0141 AC-002
- Spec-AC-02: WHEN generate-dashboard.mjs embeds the data payload THEN the
  D2 chain (backslash-first ordering, backtick and dollar-brace escaping,
  `<` neutralization) and a function-replacement substitution make the embed
  corruption-proof: for hostile payload strings containing backticks,
  dollar-brace sequences, backslash runs, replacement patterns such as `$&`,
  and a closing script tag, the generated page's embedded script parses and
  the decoded payload deep-equals the sidecar dashboard-data.json; the real
  ledger's dashboard-data.json is byte-identical pre/post fix and its
  embedded payload round-trips equal.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh` exits 0 (hostile-fixture arm + structural pin + real-ledger round-trip); pre-change RED (embedded script SyntaxError on the hostile fixture) stored under docs/ai/tdd/.

- Maps to: CHANGE-0141 AC-003
- Spec-AC-03: WHEN docs/USER_GUIDE.md carries a skill mention in
  markdown-link form (slash preceded by `[`) THEN the forward drift check
  extracts it: `MENTION_RE` admits `[` as an anchor and the extractor
  self-check gains a link-form positive control that a regressed extractor
  fails before ever touching the guide.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-userguide-drift.sh` exits 0 with the widened anchor and the new self-check control; RED (pre-change regex extracts nothing from the planted link-form control) stored under docs/ai/tdd/.

- Maps to: CHANGE-0141 AC-004
- Spec-AC-04: WHEN the scope completes THEN the release, dashboard,
  userguide-drift and metrics suites are green (metrics test_120
  single-occurrence lib pin untouched), every stored RED log carries a
  `RED_CLASS:` stamp on line 1 written at capture time, no exit contract
  moved (aai-release 0/1/42, generate-dashboard CLI 0/1/2, template
  placeholder set unchanged), and docs that describe the touched behavior
  remain truthful (docs/product/aai-dashboard.md template-contract and
  exit-code statements still hold).
- Verification: the four suite commands under `## Verification` all exit 0; `head -1` of each new docs/ai/tdd/red-*changelog-payload-hardening*.log equals a `RED_CLASS:` line; `git diff main` shows no change to aai-release.sh exit paths, generate-dashboard.mjs parseArgs/exit codes, or the template placeholder names.

## Constitution deviations

None. (Checked v1 articles 1-7: every claim rides an executable local command
and stored RED evidence (1, D4); the fix is local to the one generator that
has the broken pattern, no shared helper extracted for one call site, no
speculative class framework (2); all artifacts are plain git-diffable files
and scratch fixtures (3); the class pin degrades to a NAMED soft-skip when no
tag is usable and fails fast naming tag + first divergence otherwise (4);
changes are additive at every public boundary — no exit code, flag, template
placeholder or heading-format change (5); STATE.yaml is not written by this
planning pass — this session is explicitly barred from it and the orchestrator
records phase/strategy through state.mjs (6); no merge is performed (7).)

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Released-region class pin vs latest ancestor release tag; named skips; pass names tag | done | release suite exit 0; test_025 pass line names v2026.08.13.2; test_026 scratch matrix green; RED docs/ai/tdd/red-20260813T193830Z-changelog-payload-hardening-released-region-pin.log (both mutations passed the entire pre-change suite) | — | scratch-clone GREEN replay: glue and retitle both FAIL naming tag + first divergence |
| Spec-AC-02 | Payload embed corruption-proof: D2 chain + function replacement; round-trip equality  | done | dashboard suite exit 0 (test_012 hostile fixture EMBED-OK; test_013 order + function-form pin + real-ledger round-trip); RED docs/ai/tdd/red-20260813T193830Z-changelog-payload-hardening-hostile-embed.log (pre-change SyntaxError); real-ledger sidecar byte-identical pre/post (generatedAt-normalized cmp) | — | — |
| Spec-AC-03 | Forward drift extractor admits markdown-link-form mentions; self-check control added  | done | userguide-drift suite exit 0 with widened anchor + link-form control; RED docs/ai/tdd/red-20260813T193830Z-changelog-payload-hardening-linkform-extractor.log (zero hits pre-change) | — | — |
| Spec-AC-04 | Four suites green, RED_CLASS stamped at capture, exit contracts and docs truthful     | done | release, dashboard, userguide-drift, metrics suites all exit 0 via aai-run-tests.sh; head -1 of each new RED log is RED_CLASS: product_red; git diff main shows no exit-path, CLI-flag or placeholder change | — | metrics test_120 single-occurrence lib pin untouched |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:
- `tests/skills/test-aai-release.sh` — NEW test_025 (real-repo released-region
  pin, D1 resolution + D3 compare, pass message names the tag) and NEW
  test_026 (scratch-repo matrix: build a throwaway repo with a released
  CHANGELOG + annotated CalVer tag via the suite's existing fixture builders,
  then drive the shared region-compare helper through glue, deep-mutation,
  unreleased-edit and tagless arms). The compare logic is factored as a
  helper taking a repo dir so both tests exercise the SAME code path (the
  scratch matrix is the in-suite negative control that keeps the guard
  bite-proven on every run, not only in the one-off RED replay).
- `.aai/scripts/generate-dashboard.mjs` — replace lines 403-406 escape chain
  with the D2 ordered chain; replace the five `.replace('{{…}}', string)`
  calls with function-replacement form.
- `tests/skills/test-aai-dashboard.sh` — NEW hostile-payload test (fixture
  ledger whose skill/role/worktree strings carry backtick, `${boom}`,
  backslash runs, `$&`, `</script>`; assert the extracted embedded script
  parses via node and the decoded payload deep-equals the sidecar JSON) and
  NEW structural pin (backslash escape ordered first; METRICS_DATA
  substitution is function-form; real-ledger embed round-trips). Fixture
  style follows the suite's existing mktemp + here-string discipline.
- `tests/skills/test-aai-userguide-drift.sh` — widen `MENTION_RE` anchor
  class with `[`; add link-form positive control to the extractor self-check
  probe.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading per the release-cut
  convention (per-entry heading, never bullets under the scaffold).

Data flows / seams (each crossed by a named test):
- SEAM-1 release history ↔ live CHANGELOG: the tag namespace written by
  aai-release.sh is read back by test_025 as the immutable reference for the
  file aai-release.sh itself rolls — crossed by TEST-001 (real repo) and
  TEST-002 (scratch repo where the suite itself cuts the tag).
- SEAM-2 generator payload → template literal → browser JS: crossed by
  TEST-003 asserting the RENDERED HTML's script parses and decodes, not the
  generator's internal state.
- SEAM-3 sidecar dashboard-data.json vs embedded payload (two projections of
  one dataset): crossed by TEST-003/TEST-004 deep-equal round-trip.
- SEAM-4 extractor regex ↔ USER_GUIDE bytes: crossed by TEST-005 via the
  self-check probe controls (positive link-form, existing negative script-path
  and URL controls stay).

Edge cases:
- Tag sort traps: v2026.08.13.2 vs v2026.08.13 (version sort, not lexical or
  creatordate — D1); tagless repo, non-ancestor tag, tag without CHANGELOG,
  tag CHANGELOG without released headings (all named soft-skips — D1.3).
- Live CHANGELOG with zero `^## [v` lines while the tag has them: FAIL, not
  skip (the total-glue/total-deletion case — D3).
- Pipeline-free discipline throughout test_025/026 (tag list capture, awk
  region extraction, cmp) — the suite runs `set -euo pipefail` and CI kills
  SIGPIPE pipelines (LEARNED).
- Hostile payload adjacencies: backslash immediately before backtick
  (`` C:\tmp\` ``), `${` split across JSON escapes, `$&` at string start/end,
  `</script>` mid-string — all in one fixture ledger; plus the real-ledger
  arm (70 `usage_total_tokens` markers today) proving no regression on
  benign data.
- The `<` step must insert a SINGLE backslash post-doubling so the template
  literal's unicode-escape decoding yields `<` (D2.1) — the structural pin
  (TEST-004) locks the order so a future "cleanup" cannot silently restore
  the broken ordering.

Residual risks (written down, not silently accepted):
- The class pin protects descendants of the latest ancestor release tag; a
  branch with NO ancestor v-tag (fresh downstream adoption) is soft-skip
  territory until its first release cut. Named skip output keeps this honest.
- CI tag availability rides actions/checkout `fetch-depth: 0` semantics
  (D4); if a future workflow edit drops fetch-depth, the pin degrades to the
  named skip on CI — visible in any CI log because the pass line names the
  tag, but not itself gated. Accepted for this scope.
- Copies of dashboard-template.html vendored into downstream projects keep
  the template-literal embed; they are regenerated from this repo by
  aai-update/aai-bootstrap and inherit the fixed generator on their next
  sync. No downstream remediation is in scope.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                 | Status  |
|----------|------------|-------------|------------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh         | test_025 real-repo pin: released region byte-identical vs latest ancestor release tag (D1+D3); pass message names the tag; FAIL names tag + first divergence | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh         | test_026 scratch matrix: glue of newest heading FAILS; deep-history retitle FAILS; unreleased-only edit PASSES; tagless repo yields the named soft-skip | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-dashboard.sh       | hostile-payload fixture (backtick, dollar-brace, backslash runs, replacement patterns, closing script tag): embedded script parses (node) and decoded payload deep-equals sidecar JSON | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-dashboard.sh       | structural pin: backslash escape first in the chain, METRICS_DATA substitution function-form; real-ledger embed round-trips equal to dashboard-data.json | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-userguide-drift.sh | extractor self-check gains link-form positive control; forward reconcile extracts markdown-link-form mentions; existing negative controls still hold | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/ (four suites)              | release, dashboard, userguide-drift and metrics suites all exit 0 via aai-run-tests.sh; metrics test_120 single-occurrence pin untouched | green |
| TEST-007 | Spec-AC-04 | unit        | docs/ai/tdd/ (new RED logs)              | every stored RED log for this scope carries RED_CLASS on line 1, stamped at capture time (head -1 check) | green |

RED plan (hybrid; every RED observed and stored BEFORE its GREEN work,
`RED_CLASS:` stamped as line 1 AT capture — product_red when the planted
damage reaches the assertion, infra_fail otherwise, per SKILL_TDD):
- TEST-001/002 RED: in a scratch `git clone` of this repo (clones carry
  tags), (a) replay the exact bc056cd damage shape — glue the newest released
  heading `## [v2026.08.13.2] — …` onto the preceding bullet's line — and
  (b) mutate deep history — retitle the `## [v2026.08.08]`-era heading. On
  the pre-change tree both mutations pass the ENTIRE release suite (the class
  gap itself); with the new tests present both FAIL naming the divergence.
  Both observations captured to docs/ai/tdd/.
- TEST-003 RED: run the pre-change generator over the hostile fixture and
  `node --check` (or `new Function`) the extracted embedded script — observed
  SyntaxError (the review's reproduction, re-captured on this branch).
- TEST-004 RED arises mechanically with TEST-003 (pre-change source lacks the
  function-form substitution and has backslash-doubling last).
- TEST-005 RED: run the pre-change `extract_mentions` against the planted
  `[/aai-probe-link](…)` control — zero hits captured.
- TEST-006/007 are green-side matrix/discipline checks; their RED is the
  respective arm's RED above.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-dashboard.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-userguide-drift.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-metrics.sh`
- `node .aai/scripts/generate-dashboard.mjs --data-only` (real ledger; sidecar byte-identical pre/post fix)
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0128-spec-changelog-payload-hardening.md`
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: changelog-payload-hardening
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ for RED artifacts per the hybrid strategy;
  RED_CLASS stamped at capture)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
