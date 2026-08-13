---
id: spec-canonical-test-invocation
type: spec
number: 126
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0139-canonical-test-invocation.md
  rfc: null
  pr: []
  commits: []
---

# Spec — canonical test-invocation contract: one allowlist-stable command shape per platform, wrapper never bypassed

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0139-canonical-test-invocation.md
- Technology contract (authoritative statement lands here): docs/TECHNOLOGY.md
- Vendored template downstream contracts inherit from: .aai/templates/TECHNOLOGY_TEMPLATE.md
- Agent-facing vendored guidance (the echo surface): .aai/AGENTS.md
- The dispatchers whose invocation this contracts: .aai/scripts/aai-run-tests.ps1, .aai/scripts/aai-run-tests.sh (SPEC-0009 / SPEC-0046 / SPEC-0120 — behavior UNCHANGED by this scope)
- Doctor engine extended read-only: .aai/scripts/aai-doctor.mjs (SPEC-0100, CAT-16 shape per SPEC-0122 / CHANGE-0138)
- Prompt-diet governance: tests/skills/lib/prompt-diet-ledger.sh + tests/skills/test-aai-prompt-diet.sh (TEST-012 checkpoint currently -7144)
- Doc-pin precedent: tests/skills/test-aai-win-fallback.sh test_018/test_022/test_023
- Product doc updated truthfully: docs/product/windows-test-wrapper.md
- Operator guide: docs/USER_GUIDE.md ("Leak-safe test execution")

Ceremony justification: level 1 (intake-declared, kept) — the scope is guidance
text plus doc pins plus ONE additive detail field on the doctor's PASS-only
CAT-16; no wrapper behavior changes, no protected L3 path is touched (checked
against the live `protected_paths_l3` list: state engine, allocator, pre-commit
checks, WORKFLOW.md, CONSTITUTION.md — none in scope), and every Test Plan row
names a directly executable local command.

## Summary

Field evidence (owner transcript 2026-08-13, downstream Codex on Windows): the
agent invoked tests as `& 'C:\Program Files\Git\bin\bash.exe'
..\..\.aai\scripts\aai-run-tests.sh ...` — bypassing the vendored ps1
dispatcher entirely (no environment canonicalization, no watchdog, no exit
contract; the run produced no output) AND re-triggering the approval dialog on
every call, because the command shape varied per call (CWD-relative `..\..\`
paths, ad-hoc quoting, direct `bash.exe`). No allowlist prefix can match an
unstable shape.

The verified root gap: NOTHING authoritative states how tests must be invoked.
As of this planning pass, `.aai/AGENTS.md` contains ZERO mention of
`aai-run-tests`; `docs/TECHNOLOGY.md` names the wrappers but never states an
invocation shape; six `.aai` prompts and `.aai/system/DYNAMIC_SKILLS.md` say
only the POSIX-shaped `.aai/scripts/aai-run-tests.sh <cmd>` (no `bash` prefix,
no Windows shape, no repo-root rule, no prohibition); the `.ps1` header's Usage
says `pwsh -File ...` while the product doc repeats it — but `pwsh` does not
exist on 5.1-only corporate hosts (the shape CI explicitly proves). Each
downstream agent therefore improvises an invocation.

This scope makes the shape a CONTRACT, stated verbatim on the authoritative and
agent-facing vendored surfaces, echoed for operators as a two-prefix allowlist
note, made self-observable through a cheap doctor content probe, and governed
through the prompt-diet ledger for every corpus byte it adds. The wrapper
itself is byte-unchanged except for comment-only Usage-header alignment.

## The contract (fixed literals — ASCII only, pinned verbatim by tests)

Canonical invocation, from the repository root, one per platform:

- Windows: `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 <command...>`
- POSIX (macOS/Linux/WSL shells): `bash .aai/scripts/aai-run-tests.sh <command...>`

Allowlist prefixes (what an operator approves once):

- `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1`
- `bash .aai/scripts/aai-run-tests.sh`

Pinned sentences (grep -F targets; plain ASCII hyphens, no pipes, no unicode):

- Prohibition: "Never invoke bash.exe, sh, or wsl directly for test runs, and
  never via CWD-relative paths from a subdirectory - the dispatcher owns
  interpreter routing."
- Repo-root rule: "Run it from the repository root; when elsewhere, cd to the
  repo root first - never rewrite the script path relative to the current
  directory."
- Allowlist rationale (intake AC-002, one sentence): "The fixed repo-root
  literal prefix is what approval allowlists match - a stable command shape is
  approved once, a varying one re-prompts forever."

## Design decisions recorded at planning time (do not re-derive)

### D1 — which surfaces carry the contract, and why

1. AUTHORITATIVE STATEMENT: `docs/TECHNOLOGY.md` "## Testing" gains a
   "Test invocation (contract)" block carrying both canonical literals, the
   prohibition, the repo-root rule and the allowlist rationale.
   `.aai/templates/TECHNOLOGY_TEMPLATE.md` "## Testing" gains the same block,
   because downstream projects author their own TECHNOLOGY.md from this
   vendored template and the wrapper is vendored to every one of them.
   Both surfaces are non-prompt and non-ledgered — the intake AC-004
   preference — so the contract BODY costs zero diet bytes.
2. AGENT-FACING ECHO: `.aai/AGENTS.md` gains a minimal
   "### Canonical test invocation" subsection under "## How to run
   (recommended)" carrying the two literals, the repo-root rule and the
   prohibition (target under 600 bytes). This surface is unavoidable: it is
   the ONE vendored file every downstream agent reads at session start, and
   the field agent improvised precisely because it said nothing. AGENTS.md is
   prompt corpus (PLANNING step 3a), sits outside TEST-010's live
   `.aai/*.prompt.md` glob, and is credited manually at the exact byte delta —
   the established friction-shadow-capture-wiring precedent in the ledger.
3. PROMPT-LITERAL ALIGNMENT: the six prompt mentions
   (`.aai/VALIDATION.prompt.md` L159, `.aai/SKILL_LOOP.prompt.md` L78,
   `.aai/SKILL_VERIFY.prompt.md` L28, `.aai/SKILL_TEST_SKILLS.prompt.md` L15,
   `.aai/SKILL_BOOTSTRAP.prompt.md` L56, `.aai/SKILL_DESLOP.prompt.md` L33)
   plus `.aai/system/DYNAMIC_SKILLS.md` L34 change `.aai/scripts/
   aai-run-tests.sh` to the canonical `bash .aai/scripts/aai-run-tests.sh`
   (+5 bytes each). Without this, the factory's own prompts instruct a
   non-canonical shape that the two-prefix allowlist would re-prompt on.
   DYNAMIC_SKILLS.md is system/, not corpus — no ledger cost.
4. OPERATOR NOTE: `docs/USER_GUIDE.md` "## Leak-safe test execution" gains a
   short "Approval allowlist: two stable prefixes" subsection — allowlist
   exactly the two prefixes once, plus the rationale sentence.
5. WRAPPER HEADERS: the Usage blocks of both dispatchers state the canonical
   shape (`.ps1` currently says `pwsh -File ...`; `.sh` says a bare relative
   path). COMMENT-ONLY edits: a bypassing agent that opens the script is the
   last chance to show it the contract. Wrapper BEHAVIOR is unchanged; the
   parse/PSSA/Pester gates prove it.
6. PRODUCT DOC: `docs/product/windows-test-wrapper.md` "How to use it"
   replaces `pwsh -File ...` with the canonical Windows literal (truthful for
   5.1-only hosts) and names the allowlist stability rationale.

Rejected: stating the contract ONLY in prompts (maximum ledger cost, invisible
to operators, and TECHNOLOGY.md is the declared authoritative contract);
stating it ONLY in TECHNOLOGY.md (downstream agents demonstrably did not
derive an invocation from it, and downstream TECHNOLOGY.md files are
project-authored so an outdated one would carry nothing).

### D2 — exact canonical strings, engine choice, and the not-at-repo-root rule

- `powershell` (Windows PowerShell 5.1) over `pwsh`: powershell.exe exists on
  every Windows host; pwsh does not (the 5.1-only corporate shape is exactly
  what the ps1-quality `windows-5_1` job proves). `-NoProfile` makes startup
  deterministic and profile-proof. ONE canonical shape per platform is the
  point — `pwsh -NoProfile -File ...` runs identically but is recorded as
  non-canonical and not covered by the two-prefix allowlist.
- `-File` pass-through verified against the live dispatcher: the script
  deliberately has no `param()` block and its entry point is
  `exit (Invoke-Dispatch -Command $args)` behind the
  `$MyInvocation.InvocationName -ne '.'` guard — with
  `powershell -NoProfile -File <script> <tok...>` every following token lands
  in `$args` exactly as with `& <script> <tok...>`. Forward-slash paths are
  accepted by both engines. No wrapper change is needed for the canonical
  shape to work today.
- `bash` prefix on POSIX: an explicit interpreter makes the literal
  executable-bit-proof and gives the allowlist a stable first token; the .sh
  wrapper is `#!/bin/sh` but bash-3.2-safe by contract (its suites already run
  it under bash).
- NOT at repo root: cd (POSIX) / Set-Location (Windows) to the repository root
  FIRST (where `.aai/` lives; `git rev-parse --show-toplevel`), then run the
  canonical literal UNCHANGED. Never relativize the script path — the field
  failure's `..\..\` shape is the anti-pattern this rule bans.

### D3 — doctor probe design (intake AC-003)

Placement: a `canonical_invocation` field inside CAT-16's existing `detail`
object, plus one short appended segment on the CAT-16 reason line. NOT a new
category (the intake's closed choice is an existing CAT or CAT-16 detail), and
NOT CAT-01: SPEC-0122's live pin requires CAT-01..CAT-13 to keep their exact
clean-fixture reason wording, while CAT-16's detail is the established home
for honest tri-states (CHANGE-0138) and `test-aai-doctor.sh` already pins
"CAT-16 must stay PASS-only on every fixture" — which this scope preserves.

- Probed file: `.aai/AGENTS.md` under the doctor's `--root` — the vendored,
  agent-facing surface that exists on every healthy install (its ABSENCE is
  already CAT-01 FAIL territory, not this probe's job).
- Token: BOTH allowlist prefix literals present as fixed substrings
  (`powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1` and
  `bash .aai/scripts/aai-run-tests.sh`) — the doctor probes exactly the
  strings an allowlist would match, not prose that can drift.
- Tri-state `carried`: `true` when the file is readable and both literals
  present; `false` when readable and either literal missing (an outdated
  vendored layer — the /aai-update hint goes in the reason); the literal
  `'UNKNOWN'` when the file is absent or unreadable (honest degrade — never a
  fabricated false). Shape: `{ file, carried, reason }`.
- Text mode stays one CAT-16 line (segment appended to the reason); detail
  only under `--json`; CAT-16 stays PASS-only; no new exit codes; zero
  network; cheap (one readFileSync plus two includes() — no spawn).

### D4 — prompt-diet ledger impact (intake AC-004): measured, small, not zero

Zero was the preference and is NOT achievable: the agent-facing echo surface
IS prompt corpus. The contract BODY lives on non-ledgered surfaces (D1.1,
D1.4, D1.5, D1.6), so the corpus pays only for the echo and the literal
alignment. Movers: `.aai/AGENTS.md` (new subsection, target under 600 B,
manual credit at the exact `wc -c` delta — outside TEST-010's live glob) and
six `.aai/*.prompt.md` files (+5 B each, approximately +30 B, inside the live
glob). Procedure at implementation time: measure every file before/after with
`wc -c`; append ONE self-documenting JUSTIFIED_ADDITIONS entry crediting the
exact measured sum; bump the TEST-012 checkpoint from -7144 to
(-7144 + credit) so the pinned value equals the independent re-sum; TEST-010's
floor and the 2048 B headroom cap arbitrate the in-glob deficit per the
ledger's own comments. Estimated figures never enter the ledger — only
measured ones.

### D5 — everything is locally provable; no planned rows survive to PASS

Every deliverable is a committed text artifact or deterministic Node behavior:
doc pins are `grep -F` over files in this repo; doctor probes run against
fixture roots on any host (macOS included). No Spec-AC waits on Windows
hardware or a CI job to reach terminal status — unlike SPEC-0120/0122 there is
no field-only arm. The Windows CI lanes still run as regression insurance for
the comment-only wrapper edits, but no AC's evidence DEPENDS on them.

## Companion obligations (closed list, checked)

- Adds bytes to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`):
  YES — D1.2 and D1.3. The prompt-diet ledger true-up (new JUSTIFIED_ADDITIONS
  entry + bumped TEST-012 checkpoint) is IN scope: Spec-AC-04 / TEST-006.
- Adds a NEW `.aai/**` file: NO — every touched `.aai` file already exists;
  no PROFILES.yaml entry owed.

## Implementation strategy
- Strategy: hybrid
- Rationale: the doctor probe (Spec-AC-03) is real cross-platform Node
  behavior with cheap deterministic REDs on this host today (the detail key
  does not exist, so every fixture pin fails on the pre-change tree) — TDD
  lane with stored RED under docs/ai/tdd/ for TEST-004/TEST-005. The doc pins,
  ledger true-up and hygiene rows (TEST-001/002/003/006/007) are loop-lane
  glue: their RED is the pin failing on the pre-change tree (the literals are
  verifiably absent today), observed and recorded but not necessarily stored.
  No intake-sourced implementation-mode choice exists for CHANGE-0139 (no
  "Implementation mode (user choice):" line in the intake).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: small multi-file docs+tests scope already isolated on
  its own branch `feat/canonical-test-invocation`; no protected surface.
  Isolation pays only if another ride touches AGENTS.md, the doctor or the
  win-fallback suite concurrently. Implementation Preparation asks and
  decides.
- User decision: undecided
- Base ref: feat/canonical-test-invocation
- Worktree branch/path: not selected
- Inline review scope: docs/TECHNOLOGY.md .aai/templates/TECHNOLOGY_TEMPLATE.md .aai/AGENTS.md .aai/VALIDATION.prompt.md .aai/SKILL_LOOP.prompt.md .aai/SKILL_VERIFY.prompt.md .aai/SKILL_TEST_SKILLS.prompt.md .aai/SKILL_BOOTSTRAP.prompt.md .aai/SKILL_DESLOP.prompt.md .aai/system/DYNAMIC_SKILLS.md .aai/scripts/aai-run-tests.sh .aai/scripts/aai-run-tests.ps1 .aai/scripts/aai-doctor.mjs tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-win-fallback.sh tests/skills/test-aai-doctor.sh docs/USER_GUIDE.md docs/product/windows-test-wrapper.md docs/issues/CHANGE-0139-canonical-test-invocation.md docs/specs/SPEC-0126-spec-canonical-test-invocation.md CHANGELOG.md

Code review: required (code, tests and vendored-guidance changes).

## Acceptance Criteria Mapping

- Maps to: CHANGE-0139 AC-001 (the contract)
  - Spec-AC-01: the authoritative and agent-facing vendored guidance states
    the one canonical invocation per platform verbatim, the repo-root rule
    and the prohibition; both wrapper Usage headers state the same canonical
    shapes (comment-only).
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 024` and
    `bash tests/skills/test-aai-win-fallback.sh 025`; RED = both fail on the
    pre-change tree (literals absent — verified during planning).
- Maps to: CHANGE-0139 AC-002 (allowlist stability)
  - Spec-AC-02: docs/TECHNOLOGY.md carries the one-sentence allowlist
    rationale; docs/USER_GUIDE.md carries the operator note naming exactly
    the two prefixes, approved once.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 026`.
- Maps to: CHANGE-0139 AC-003 (self-observability)
  - Spec-AC-03: aai-doctor CAT-16 detail reports `canonical_invocation` with
    tri-state `carried` per D3; PASS-only, one text line, detail under
    `--json` only, no new exit codes, zero network.
  - Verification: `bash tests/skills/test-aai-doctor.sh` (new fixture tests);
    `node .aai/scripts/aai-doctor.mjs --json` on the post-change repo shows
    `carried: true`.
- Maps to: CHANGE-0139 AC-004 (governance)
  - Spec-AC-04: one JUSTIFIED_ADDITIONS entry crediting the exact measured
    corpus delta; TEST-012 checkpoint moves from -7144 to the new independent
    re-sum; the diet suite is green.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh`.
- Maps to: CHANGE-0139 AC-005 (tests, truthful docs, wrapper unchanged)
  - Spec-AC-05: new tests registered; product doc and USER_GUIDE truthful
    (canonical shape, no stale `pwsh -File` claim as THE way to invoke);
    CHANGELOG entry as its own unreleased heading; wrapper behavior unchanged
    (full wrapper and ps1-quality suites green on the comment-only diffs).
  - Verification: `node .aai/scripts/check-test-registration.mjs`,
    `bash tests/skills/test-aai-win-fallback.sh`,
    `bash tests/skills/test-ps1-quality.sh`,
    `bash tests/skills/test-aai-doctor.sh`.

## Constitution deviations

None.

- Article 1 (Evidence before claims) — every AC names one command and one
  observable; every row is locally executable (D5).
- Article 2 (Simplicity) — no new script, no new doctor category, no wrapper
  flag; the contract is text plus one detail field; rejected alternatives
  recorded in D1/D3.
- Article 3 (Portability) — the canonical Windows shape targets the engine
  every Windows host has (5.1); the probe literals are ASCII; the doctor
  change is pure Node fs, identical on macOS/Linux/Windows; bash-3.2-safe
  test code.
- Article 4 (Degrade and report) — the probe's UNKNOWN is a named degrade
  with a reason, never a fabricated false; a missing contract names the
  /aai-update remedy.
- Article 5 (Additive first) — CAT-16 keeps its id, status posture (PASS-only)
  and detail keys; wrapper edits are comment-only; all guidance additions are
  new blocks, no existing contract line is removed except the two stale
  `pwsh -File` usage claims being ALIGNED, not deleted.
- Articles 6 and 7 — untouched.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a reader opens docs/TECHNOLOGY.md Testing, .aai/templates/TECHNOLOGY_TEMPLATE.md Testing, or the .aai/AGENTS.md "Canonical test invocation" subsection THEN each carries verbatim BOTH canonical literals (Windows powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 with command tokens following; POSIX bash .aai/scripts/aai-run-tests.sh with command tokens following), the pinned repo-root sentence, and the pinned prohibition sentence banning direct bash.exe or sh or wsl invocation and CWD-relative paths from subdirectories; AND both dispatcher Usage headers state the same canonical shapes as comment-only edits; AND the six prompt-corpus invocation mentions plus .aai/system/DYNAMIC_SKILLS.md carry the bash-prefixed POSIX literal with no remaining bare-path invocation instruction in those seven mentions | done | test-aai-win-fallback.sh 024 + 025 green, exit 0 (RED first: docs/ai/tdd/red-20260813T151116Z-canonical-test-invocation-pins-024.log and -025.log; GREEN: green-20260813T151116Z-canonical-test-invocation-pins.log); Parser::ParseFile on the edited ps1: 0 errors | — | fixed literals and pinned sentences are defined in "The contract" section above; ASCII only inside the ps1 header |
| Spec-AC-02 | WHEN an operator reads docs/TECHNOLOGY.md THEN it states the pinned one-sentence allowlist rationale; AND WHEN an operator reads the docs/USER_GUIDE.md Leak-safe test execution section THEN a subsection instructs allowlisting exactly the two prefix literals once, naming both prefixes verbatim | done | test-aai-win-fallback.sh 026 green, exit 0 (RED first: docs/ai/tdd/red-20260813T151116Z-canonical-test-invocation-pins-026.log) | — | rationale sentence pinned verbatim in "The contract" above |
| Spec-AC-03 | WHEN node .aai/scripts/aai-doctor.mjs --json runs against a root whose .aai/AGENTS.md contains both prefix literals THEN CAT-16 detail.canonical_invocation reports carried true with file .aai/AGENTS.md; WHEN the file is readable but either literal is missing THEN carried is false with a reason naming the missing contract and the /aai-update remedy; WHEN the file is absent or unreadable THEN carried is the literal UNKNOWN with the reason, never a fabricated false; AND CAT-16 stays PASS-only on every fixture, text mode still prints exactly one CAT-16 line with a short appended contract segment, detail appears under --json only, the exit map is unchanged and the probe performs no spawn and no network access | done | TDD lane: test-aai-doctor.sh test_038/test_039 RED (docs/ai/tdd/red-20260813T151116Z-canonical-test-invocation-doctor-fixtures.log, -doctor-shape.log) then GREEN (green-20260813T151116Z-*, exit 0); full doctor suite green; real-repo node .aai/scripts/aai-doctor.mjs --json reports carried true, CAT-16 PASS | — | placement per D3: existing CAT-16 detail, not a new category; tri-state precedent CHANGE-0138 |
| Spec-AC-04 | WHEN tests/skills/test-aai-prompt-diet.sh runs after the guidance edits THEN the JUSTIFIED_ADDITIONS ledger carries one new self-documenting entry whose credited bytes equal the exact measured wc -c deltas of the touched corpus files (AGENTS.md credited manually at its exact delta per the outside-live-glob precedent), the TEST-012 checkpoint equals -7144 plus that credit and equals the independent re-sum, and the TEST-010 floor stays green within the 2048-byte headroom cap | done | measured wc -c deltas: AGENTS.md 19168 to 19640 (+472), six prompts +5 each (+30); one +502 ledger entry; TEST-012 checkpoint -7144 to -6642 == independent re-sum; test-aai-prompt-diet.sh exit 0, headroom 1622/2048 | — | measured, never estimated (intake AC-004); AGENTS.md block 472 B, under the 600 B target |
| Spec-AC-05 | WHEN the hygiene commands run THEN every new test function is registered and reported clean by check-test-registration.mjs, docs/product/windows-test-wrapper.md How-to-use states the canonical Windows literal instead of pwsh -File as THE invocation and names the allowlist rationale, CHANGELOG.md carries this scope as its own unreleased heading entry, and the full test-aai-win-fallback.sh, test-ps1-quality.sh and test-aai-doctor.sh suites pass — proving the comment-only wrapper edits changed no behavior and broke no existing header-parity pin | done | check-test-registration.mjs exit 0; test-aai-win-fallback.sh FULL suite exit 0 (test_009/015/018 parity pins unmodified and green); test-ps1-quality.sh exit 0; test-aai-doctor.sh exit 0; product-doc + CHANGELOG pins inside test_026 | — | wrapper behavior unchanged is an explicit constraint; pre-existing test_023 CHANGELOG pin had already rotted at the v2026.08.13 release cut (verified failing on the pre-change tree) and was made release-tolerant |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `docs/TECHNOLOGY.md` — "## Testing" gains a "Test invocation (contract)"
  block: two canonical literals, repo-root sentence, prohibition sentence,
  allowlist-rationale sentence.
- `.aai/templates/TECHNOLOGY_TEMPLATE.md` — same block added to its
  "## Testing" skeleton (project-agnostic wording; the wrapper is vendored to
  every downstream project).
- `.aai/AGENTS.md` — new "### Canonical test invocation" subsection under
  "## How to run (recommended)": both literals, repo-root rule, prohibition.
  Target under 600 bytes.
- Six prompts + DYNAMIC_SKILLS.md — the seven invocation mentions gain the
  `bash ` prefix (D1.3); no other prompt text changes.
- `.aai/scripts/aai-run-tests.ps1` — Usage header comment: canonical
  `powershell -NoProfile -File ...` line (ASCII only); `pwsh -File` may remain
  as a noted variant. NO code change.
- `.aai/scripts/aai-run-tests.sh` — Usage header comment: canonical
  `bash .aai/scripts/aai-run-tests.sh <command> [args...]` line. NO code
  change.
- `.aai/scripts/aai-doctor.mjs` — `catAgentCliProbe` gains the
  `canonical_invocation` detail computation (readText + two includes) and the
  reason-line segment; nothing else moves.
- `tests/skills/test-aai-win-fallback.sh` — new test_024 (guidance trio +
  prompt alignment pins), test_025 (wrapper Usage headers), test_026
  (rationale + USER_GUIDE operator note + product doc + CHANGELOG pins),
  registered in ALL_TESTS.
- `tests/skills/test-aai-doctor.sh` — new tests for the three probe fixtures
  and the shape/PASS-only/one-line invariants.
- `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`
  — one JUSTIFIED_ADDITIONS entry; TEST-012 pin bumped to the new re-sum.
- `docs/USER_GUIDE.md`, `docs/product/windows-test-wrapper.md`, `CHANGELOG.md`
  — operator note, truthful product doc, per-entry unreleased heading.

Data flows: none at runtime beyond the doctor reading one file. The contract
flows through TEXT surfaces into (a) downstream agents via /aai-update
vendoring of .aai/**, (b) operators via USER_GUIDE, (c) the doctor's probe.

Edge cases:

- A downstream machine with a pre-contract vendored layer: probe reports
  carried false with the /aai-update hint — that is the designed signal, not
  an error.
- AGENTS.md present but truncated/unreadable: UNKNOWN with reason.
- The ps1 header edit must not introduce non-ASCII (PSSA/parse gates under
  5.1 and 7) or touch any executable line (Pester + parity pins prove it).
- The AC-table and pinned sentences contain no pipe characters; bash pins use
  here-strings or grep -qF with single-quoted literals (spec-table and
  test-harness LEARNED rules).
- The prompt alignment must not break test_012 prompt-corpus governance pins
  or ORCHESTRATION line caps (no ORCHESTRATION file is touched).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description | Status |
|----------|------------|-------------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-win-fallback.sh   | test_024: docs/TECHNOLOGY.md, .aai/templates/TECHNOLOGY_TEMPLATE.md and .aai/AGENTS.md each contain both canonical literals, the pinned repo-root sentence and the pinned prohibition sentence (grep -qF per file); and the six prompt files plus DYNAMIC_SKILLS.md carry the bash-prefixed literal in their invocation mentions. Command: bash tests/skills/test-aai-win-fallback.sh 024 | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-win-fallback.sh   | test_025: the aai-run-tests.ps1 Usage header contains the canonical powershell -NoProfile -File literal and stays ASCII-clean in the edited lines; the aai-run-tests.sh Usage header contains the canonical bash-prefixed literal. Command: bash tests/skills/test-aai-win-fallback.sh 025 | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-win-fallback.sh   | test_026: docs/TECHNOLOGY.md carries the pinned allowlist-rationale sentence; docs/USER_GUIDE.md Leak-safe section carries the operator subsection naming exactly the two prefix literals and the word once. Command: bash tests/skills/test-aai-win-fallback.sh 026 | green |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-doctor.sh         | Fixture matrix for the probe: a fixture root whose .aai/AGENTS.md carries both literals yields detail.canonical_invocation.carried === true; a fixture whose AGENTS.md lacks the Windows literal yields carried === false with a reason naming /aai-update; a fixture with no .aai/AGENTS.md yields the literal UNKNOWN with a reason; all under node .aai/scripts/aai-doctor.mjs --json --root fixture. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-doctor.sh         | Shape invariants on every probe fixture AND the real repo root: CAT-16 status stays PASS, text mode prints exactly one CAT-16 line whose reason carries the contract segment, detail appears only under --json, the real post-change repo reports carried true (crossing the docs-to-doctor seam for real), and neither the probe path nor the new code spawns a process or references a network primitive. Command: bash tests/skills/test-aai-doctor.sh | green |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-prompt-diet.sh    | Ledger true-up: JUSTIFIED_ADDITIONS carries the new entry, JUSTIFIED_GROWTH_BYTES equals the bumped TEST-012 checkpoint and the independent re-sum, and the TEST-010 byte floor stays green after the measured corpus deltas. Command: bash tests/skills/test-aai-prompt-diet.sh | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-win-fallback.sh   | Hygiene and no-behavior-change set: check-test-registration.mjs reports the new test functions registered; the FULL win-fallback suite (including the pre-existing header/TECHNOLOGY/product-doc parity pins test_009/015/018) passes; test-ps1-quality.sh passes proving the ps1 header edit parses under both engines with zero Pester regressions; the product doc canonical-shape pin and the CHANGELOG unreleased-heading pin pass. Commands: node .aai/scripts/check-test-registration.mjs and bash tests/skills/test-aai-win-fallback.sh and bash tests/skills/test-ps1-quality.sh and bash tests/skills/test-aai-doctor.sh | green |

Test status values: pending -> red -> green

## Seams crossed

- SEAM-1 — guidance text to doctor probe: the docs pin the literals, the
  doctor greps for the SAME literals; a wording drift in AGENTS.md silently
  flips the probe. Crossed for real by TEST-005 running the actual doctor
  over the actual repo root and asserting carried true (not a fixture mock).
- SEAM-2 — corpus bytes to ledger arithmetic: AGENTS.md and six prompts are
  written by this scope, summed by prompt-diet-ledger.sh, pinned by TEST-012's
  checkpoint and re-summed independently. Crossed by TEST-006 (equality of
  three independently computed numbers).
- SEAM-3 — the wrapper headers already participate in the SPEC-0046 parity
  class (header text pinned against TECHNOLOGY.md and the product doc by
  test_009/015/018). The Usage edit must not break those pins. Crossed by
  TEST-007 running the FULL pre-existing suite unmodified.
- SEAM-4 — CAT-16's detail object is consumed by existing doctor tests
  (PASS-only pin, detail-under-json pin, line-count pin). The new field must
  be additive. Crossed by TEST-005 plus the full doctor suite in TEST-007.

## Residual risks (accepted)

- RR-1 — a contract stated in guidance cannot FORCE a downstream harness to
  obey it; it makes the correct shape discoverable, allowlist-stable and
  doctor-observable. The next field bypass will at least be diagnosable with
  one command.
- RR-2 — the probe checks the vendored AGENTS.md, not the downstream
  project's own TECHNOLOGY.md; a project that overwrote its TECHNOLOGY.md
  testing section keeps a true `carried` as long as the vendored layer is
  current. Accepted: AGENTS.md is the surface agents actually read, and
  CAT-13 already owns vendored-layer drift generally.
- RR-3 — CAT-16 stays PASS-only, so a missing contract never trips `--strict`.
  Accepted to preserve the pinned PASS-only posture from SPEC-0122/CHANGE-0138;
  the signal lives on the line and in the detail.
- RR-4 — operator allowlist syntax differs per harness (Claude Code, Codex,
  Copilot); the USER_GUIDE note names the two PREFIXES, not per-harness
  config syntax. Accepted as out of scope.

## Verification

Commands to run:

- `bash tests/skills/test-aai-win-fallback.sh` (includes new 024/025/026 and
  the pre-existing parity pins)
- `bash tests/skills/test-aai-doctor.sh`
- `bash tests/skills/test-ps1-quality.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/aai-doctor.mjs --json` (post-change repo: carried true)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0126-spec-canonical-test-invocation.md`

Evidence artifacts: stored RED under `docs/ai/tdd/` for the TDD-lane doctor
tests (TEST-004, TEST-005); recorded RED observations (pre-change pin
failures) for the loop-lane rows; full stdout with exit codes for every
command above; the measured `wc -c` before/after table for Spec-AC-04 in the
implementation report.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status. All
evidence is local (D5); no row may cite a pending CI run as its only proof.

## Evidence contract

For each implementation, validation, TDD, and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

Strategy is `hybrid`: stored RED artifact under `docs/ai/tdd/` per AC-gating
test on the TDD lane (TEST-004, TEST-005), plus the full verification matrix
above. For the loop-lane rows (TEST-001/002/003/006/007) the RED observation
is the pin failing on the pre-change tree, recorded but not necessarily
stored.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
