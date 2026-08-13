---
id: spec-update-doctor-field-report
type: spec
number: 124
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0137-update-doctor-field-report.md
  rfc: null
  pr:
    - 252
  commits:
    - 2a4795c
---

# Spec — aai-update ends every successful downstream update with a doctor field report

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0137-update-doctor-field-report.md
- Update entrypoints this scope EXTENDS (never rewrites): `.aai/scripts/aai-update.sh`, `.aai/scripts/aai-update.ps1`
- Doctor engine this scope CONSUMES read-only (never edits): `.aai/scripts/aai-doctor.mjs` (SPEC-0100 / SPEC-0122 — `--json` shape, exit 0 clean or WARN-only, 1 on FAIL, 2 on usage)
- Config precedent this scope FOLLOWS: `docs/ai/update-config.yaml` + `.aai/templates/update-config.template.yaml` + `.aai/scripts/update-check.mjs` resolveConfig (SPEC-0106 — column-0 line scan, absent == defaults, unknown value rejected to the default with a stderr note)
- Report-location precedent: `docs/ai/reports/sync-conflicts-*.md` written by `.aai/scripts/aai-sync.sh` (runtime-ignored via `.gitignore` `docs/ai/reports/**`; `reports` is in `.aai/system/DOCS_AI_CANON.list`)
- Provenance stamp source: `.aai/system/AAI_PIN.md` (`Template version:` / `Template commit:`, written by the sync immediately before this scope's hook runs); fallback `docs/ai/AAI_VERSION.md` (written by the release engines at each cut, PR #222 / commit 147d428)
- Residual this loop exists to close: docs/ai/decisions.jsonl 2026-08-13T02:26:00Z (CHANGE-0135) — "WSL-branch marker translation is proven by payload-shape pin ... first downstream /aai-doctor run on one is the real proof"
- Product doc created by this scope: docs/product/aai-update.md (intake capability: aai-update)
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — the intake declared level 1 and this scope
keeps it. The scope adds one new zero-dependency Node helper plus a short
guarded postamble to the two update entrypoints; the doctor engine, the sync
engine, and every protected surface (see the L3 check below) are untouched; a
failure anywhere in the new path degrades to one named SKIP line and can never
change the update's own exit code; and every acceptance criterion names a
directly executable command. The file count (about thirteen, half of them docs
and registration) sits near the top of what level 1 covers, so an operator may
legitimately raise it to 2 — Planning does not do that silently.

## Summary

CI will never be "all platforms" — the downstream fleet is (owner ask
2026-08-13, option 5 of the platform-coverage proposal). `/aai-doctor` can
already diagnose a machine in one command; this scope adds the loop that runs
it where the evidence lives: after a successful `/aai-update`, the update
entrypoint runs the freshly-vendored doctor with `--json` and persists a
provenance-stamped field report under `docs/ai/reports/`, printing one line
with the DOCTOR verdict and the report path. Any failure in that postamble —
node missing, doctor missing, doctor timeout, unparseable output — degrades to
exactly one named SKIP line; the update itself can never fail because of it.

The first concrete payoff is the WSL-functional-host residual recorded in
decisions.jsonl on 2026-08-13: no CI runner has a functional WSL distro, so
one field report from such a downstream machine is the real proof CI cannot
produce.

## Design decisions recorded at planning time (do not re-derive)

### D1 — the hook is ONE Node helper both entrypoints call, not twin shell implementations

The behavior (config read, doctor spawn with timeout, provenance assembly,
report write, retention prune, single-line emission) lives once in a NEW
`.aai/scripts/update-doctor-report.mjs`. `aai-update.sh` and `aai-update.ps1`
each gain a short postamble (a `## Doctor field report` section after the
post-sync evidence) whose only responsibilities are: locate `node` and the
TARGET's helper, invoke it, and print the named
`DOCTOR-REPORT SKIP <reason> - update unaffected` fallback line when either is
missing or the invocation itself fails. The sh arm is `|| echo`-guarded
(the script runs under `set -euo pipefail`); the ps1 arm is try/catch-wrapped.
Rejected alternatives:

1. Twin bash/PowerShell implementations of the whole behavior. REJECTED — two
   config parsers, two pruning implementations, two provenance assemblers: the
   exact parity-drift class CHANGE-0136 just paid to close on the CI surface.
   Node is already a hard prerequisite of the thing being run (the doctor), so
   requiring it here adds no new dependency (AC-003); a host without node gets
   the honest SKIP, which is also the honest doctor answer on that host.
2. A `--report` flag folded into `aai-doctor.mjs` itself. REJECTED — the
   doctor is a diagnosis engine with a frozen output and exit contract
   (SPEC-0122 Spec-AC-04); report persistence, config gating and update-flow
   line formats are update policy, not diagnosis. The helper spawns the doctor
   as a child exactly the way any other consumer would.

Rollout lag is inherent and accepted (RR-1): the sh entrypoint self-relocates
and the ps1 engine pre-parses, so a downstream machine executes the
PRE-update postamble on the run that first vendors this feature — the first
report appears on that machine's SECOND update.

### D2 — on by default; the dial is `post_update_doctor:` in docs/ai/update-config.yaml

The project-local AAI config precedent is `docs/ai/update-config.yaml`
(SPEC-0106): committed, seeded-when-missing from
`.aai/templates/update-config.template.yaml`, parsed by a column-0 line scan,
absent file == defaults, unknown value rejected to the default with a stderr
note. This scope adds the key `post_update_doctor: on | off` to that same file
and template. Default ON, for three recorded reasons: the intake and the owner
ask say "produces that evidence by default"; the step is read-only,
zero-network, bounded, and its output is runtime-ignored, so the safe
direction and the default direction coincide (unlike SPEC-0106's `auto` mode,
which mutates the tree and is therefore opt-in); and the fleet-telemetry value
exists only if the default produces reports — an off-by-default knob can never
close the WSL residual. `off` yields the named line
`DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off)` — never
silence (intake AC-002). An unknown value gets a stderr warning and behaves as
`on` (the default — mirroring resolveConfig, where a typo lands on the
default; here the default is additionally non-destructive). Existing
downstream configs lack the key entirely == on; the seed is when-missing only,
so no downstream file is rewritten.

### D3 — report path, naming, provenance, and dirty-tree safety

Path: `docs/ai/reports/doctor-<UTCSTAMP>-<machine>.md`, where UTCSTAMP is
`yyyymmddTHHMMSSZ` and `<machine>` is `os.hostname()` lowercased, sanitized to
`[a-z0-9-]`, capped at 40 chars, `unknown-host` when empty. This is the
update flow's existing report home (sync-conflicts advisories), it is
runtime-ignored by the vendored `.gitignore` (`docs/ai/reports/**` with the
`.gitkeep` carve-out) so the report can NEVER dirty the target's tree, break
its next `git status` review, or trip docs-audit (`reports` is canonical in
DOCS_AI_CANON.list) — and it is still an ordinary on-disk file the downstream
user can open and attach to an issue.

Provenance header (markdown list, ASCII only), then the doctor JSON verbatim
in one fenced block:

- `Generated at (UTC):` ISO 8601
- `AAI version:` the `Template version:` value from `.aai/system/AAI_PIN.md`
  (stamped by the sync seconds earlier — the freshest possible stamp);
  fallback: the `Version:` line of `docs/ai/AAI_VERSION.md`; else the literal
  `UNKNOWN` — never invented
- `AAI commit:` the pin's `Template commit:`; else `UNKNOWN`
- `Platform:` `<process.platform>-<os.arch()> (<os.release()>), node <process.version>`
- `Machine:` the sanitized machine tag
- `Doctor exit:` the child's exit code and the JSON `verdict` and `issues`

Retention: after a successful write, files matching
`^doctor-\d{8}T\d{6}Z-[a-z0-9-]+\.md$` in `docs/ai/reports/` beyond the newest
10 are deleted. Only that exact shape is ever pruned — sync-conflicts and
validation reports are untouchable by construction. This bounds accumulation
on a machine that updates daily (intake "avoid unbounded accumulation").

ASCII discipline: every string the ps1 postamble carries and every line the
helper emits is ASCII-only (LEARNED 2026-08-13: a UTF-8 em-dash mojibakes
under Windows PowerShell 5.1's BOM-less ANSI read).

### D4 — failure semantics: one named line per outcome, the update exit code untouchable

The helper's exit contract mirrors `update-check.mjs`: exit 0 for EVERY
runtime outcome, exit 2 only for a CLI usage error. It prints exactly one
stdout line per run:

- doctor ran, JSON parsed (child exit 0 or 1):
  `DOCTOR <CLEAN|ISSUES(n)> - full report: docs/ai/reports/doctor-<...>.md`.
  Doctor exit 1 is NOT a failure of this step — a FAIL-bearing machine is
  exactly the machine the fleet wants a report from.
- disabled: `DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off)`
- degraded, one reason named per line: doctor script missing, doctor spawn
  failed, doctor timed out after Ns, doctor usage error (exit 2), doctor
  output unparseable, report write failed. Format:
  `DOCTOR-REPORT SKIP <reason> - update unaffected`.

The doctor spawn is bounded by a 240000 ms default (`--timeout-ms` override
for tests): POSIX runs finish in seconds; on Windows CAT-14 alone may burn up
to its 170 s internal bound (decisions 2026-08-13, undocumented real-Windows
wall-clock), so a pathological host exceeds the budget and gets the named
timeout SKIP rather than a hang. The wrapper postambles add the second guard
layer (D1): even a helper crash yields the wrapper's own named SKIP line, and
the update's exit code is byte-identical in every arm.

### D5 — what is locally testable vs what only a real downstream run proves

Locally provable (bash suite `tests/skills/test-aai-update.sh`, reusing its
existing file:// fixture-repo pattern, plus direct helper invocations against
fixture roots with a `--doctor <path>` stub override): the report written on
the success path with full provenance; every named SKIP arm (missing doctor,
exit 2, garbage stdout, timeout, config off, helper crash); the update exit
code unchanged under every induced failure; the retention cap; JSON
passthrough of honestly-SKIPped Windows categories; the seam with
update-check's parser; and the ps1 postamble's structural parity. NOT locally
provable, and deliberately not an acceptance criterion (SPEC-0122/0123 honest
e2e pattern — an AC no local run can decide would freeze the spec open
forever): a real downstream machine producing and attaching a report, and in
particular the WSL-functional-host report that closes the decisions.jsonl
residual. Those are recorded as RR-2/RR-3 with the follow-up path, not as
rows this spec's PASS depends on.

## L3 check (recorded)

`protected_paths_l3` in docs/ai/docs-audit.yaml lists `state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`,
`pre-commit-checks.sh`, `pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`
and `docs/CONSTITUTION.md`. Verified against the live file: none of them is in
this scope.

## Companion obligations (closed list, checked)

- Prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`): TOUCHED —
  `.aai/SKILL_UPDATE.prompt.md` step 2 gains one relay clause so the agent
  surfaces the DOCTOR verdict line and report path instead of dropping them
  under the "surface only" list. Budget: at most 120 bytes, ASCII. Owed and in
  scope (Spec-AC-05, TEST-011): one `JUSTIFIED_ADDITIONS` append in
  `tests/skills/lib/prompt-diet-ledger.sh` with the measured byte delta, plus
  the TEST-012 checkpoint bump in `tests/skills/test-aai-prompt-diet.sh`
  (current pin: JUSTIFIED_GROWTH_BYTES == -7210).
- New `.aai/**` file: YES — `.aai/scripts/update-doctor-report.mjs`. A
  classification entry under `core:` in `.aai/system/PROFILES.yaml` is owed
  and in scope (Spec-AC-05, TEST-011); core because it rides the distribution
  and health class (sync / update / doctor) and a core-only sync must not
  lose it.

## Implementation strategy
- Strategy: hybrid
- Rationale: the helper's behavior matrix (Spec-AC-01 failure semantics,
  Spec-AC-02 config, Spec-AC-03 timeout and passthrough, Spec-AC-04
  provenance and retention) has cheap deterministic REDs on this host today —
  the helper does not exist, so every pin fails on the pre-change tree, and
  all fixtures are pure local stub-doctor runs. Those rows take the TDD lane
  with stored REDs under `docs/ai/tdd/`. The postamble wiring, ps1 structural
  parity, docs and registration rows (TEST-001/009/010/011) take the loop
  lane with the RED observation recorded. No intake-sourced implementation
  mode choice exists for CHANGE-0137 — its intake carries no
  `Implementation mode (user choice):` line.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: about thirteen files, no protected surface, and the
  scope already sits on its own branch `feat/update-doctor-field-report`.
  Isolation pays only if another ride touches the update scripts or
  `test-aai-update.sh` concurrently. Implementation Preparation asks and
  decides.
- User decision: undecided
- Base ref: feat/update-doctor-field-report
- Worktree branch/path: not selected
- Inline review scope: .aai/scripts/update-doctor-report.mjs .aai/scripts/aai-update.sh .aai/scripts/aai-update.ps1 .aai/templates/update-config.template.yaml .aai/SKILL_UPDATE.prompt.md .aai/system/PROFILES.yaml tests/skills/test-aai-update.sh tests/skills/suite-map.yaml tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh docs/USER_GUIDE.md docs/product/aai-update.md docs/product/aai-doctor.md docs/specs/SPEC-0124-spec-update-doctor-field-report.md CHANGELOG.md docs/ai/update-config.yaml docs/INDEX.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0137 AC-001 (post-update doctor run, never fails the update)
  - Spec-AC-01: after a successful non-dry-run update the entrypoint invokes
    the target's `update-doctor-report.mjs`, which runs the vendored doctor
    with `--json`, writes the timestamped machine-tagged report under
    `docs/ai/reports/`, and prints one line with the DOCTOR verdict and the
    report path; every failure anywhere in that path yields exactly one named
    SKIP line and leaves the update's exit code unchanged.
  - Verification: `bash tests/skills/test-aai-update.sh` (fixture update runs
    plus the direct failure matrix).
- Maps to: CHANGE-0137 AC-002 (config)
  - Spec-AC-02: `post_update_doctor:` in `docs/ai/update-config.yaml`,
    column-0 scan, absent == on, `off` yields the named disabled-by-config
    line, unknown values warn and behave as on; the template documents the
    key; update-check's own parser is unaffected by the new key.
  - Verification: `bash tests/skills/test-aai-update.sh` (config matrix) and
    `bash tests/skills/test-aai-update-check.sh` (parser seam).
- Maps to: CHANGE-0137 AC-003 (zero surprise, bounded)
  - Spec-AC-03: no network or LLM primitive, no dependency beyond node, the
    doctor spawn timeout-bounded, and honestly-SKIPped doctor categories land
    verbatim in the report.
  - Verification: `bash tests/skills/test-aai-update.sh` (zero-network pin,
    timeout fixture, passthrough pin).
- Maps to: CHANGE-0137 AC-004 (fleet-comparable report and docs)
  - Spec-AC-04: provenance header (AAI version and commit from the pin with
    the AAI_VERSION fallback, UTC timestamp, platform string, machine tag)
    plus the full doctor JSON; retention cap 10; USER_GUIDE and product docs
    state the update-report-attach loop.
  - Verification: `bash tests/skills/test-aai-update.sh` (provenance,
    retention and docs pins).
- Maps to: CHANGE-0137 AC-005 (tests and governance)
  - Spec-AC-05: new test functions registered, suite-map covers the helper,
    PROFILES classifies it, the prompt-diet ledger and TEST-012 checkpoint
    are trued up for the SKILL_UPDATE bytes.
  - Verification: `node .aai/scripts/check-test-registration.mjs`,
    `bash tests/skills/test-aai-layer-profiles.sh`,
    `bash tests/skills/test-aai-suite-select.sh`,
    `bash tests/skills/test-aai-prompt-diet.sh`,
    `bash tests/skills/test-aai-hygiene-pack.sh`.

## Constitution deviations

None.

- Article 1 (Evidence before claims) — every AC names one command and one
  observable; the downstream-fleet proof is explicitly a residual risk, not a
  claimable AC.
- Article 2 (Simplicity) — one new helper, no abstraction over the doctor or
  sync engines; the rejected twin-implementation and doctor-flag alternatives
  are recorded in D1 rather than built.
- Article 3 (Portability) — the helper is plain zero-dependency Node behaving
  identically tri-platform; the report is a plain markdown file; the ps1
  postamble must parse under Windows PowerShell 5.1 and stay ASCII-only.
- Article 4 (Degrade and report) — every unavailable input is a NAMED
  degradation line (node missing, doctor missing, timeout, unparseable
  output, config off); none is silent and none fails the update.
- Article 5 (Additive first) — the update scripts' existing output sections,
  flags and exit codes are unchanged; the postamble, the config key and the
  report are purely additive.
- Articles 6 and 7 — untouched (no STATE writes on this path; nothing merges).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a non-dry-run aai-update.sh or aai-update.ps1 run completes its sync successfully THEN the entrypoint prints a Doctor field report section and invokes node with the TARGET's .aai/scripts/update-doctor-report.mjs, which runs the target's vendored .aai/scripts/aai-doctor.mjs with --json, writes docs/ai/reports/doctor-UTCSTAMP-machine.md, and prints exactly one line carrying the DOCTOR verdict token (CLEAN or ISSUES(n)) plus the report's repo-relative path; AND WHEN node is missing, the helper is missing, the doctor script is missing, the doctor spawn fails, times out, exits 2, or emits unparseable JSON, or the helper itself crashes THEN exactly one line starting DOCTOR-REPORT SKIP and naming that single reason is printed instead and the update's own exit code is byte-identical to the same run without the induced failure; AND WHEN the doctor exits 1 THEN the report is still written and the line carries the ISSUES verdict, never a SKIP; AND a dry-run never invokes the helper | done | bash tests/skills/test-aai-update.sh exit 0 (0137-TEST-001/002/003/009 PASS); RED docs/ai/tdd/red-20260813T100639Z-update-doctor-field-report.log, GREEN docs/ai/tdd/green-20260813T100639Z-update-doctor-field-report.log | — | wrapper guards: sh postamble or-guarded under set -euo pipefail, ps1 postamble try/catch, per D1 and D4 |
| Spec-AC-02 | WHEN docs/ai/update-config.yaml is absent, or present without a column-0 post_update_doctor key THEN the helper runs (default on); WHEN the file carries post_update_doctor: off at column 0 THEN the helper prints the single line DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off), writes no report, and exits 0; WHEN the value is neither on nor off THEN a stderr warning names the bad value and the helper behaves as on; an indented or commented key is never a dial; AND .aai/templates/update-config.template.yaml documents the key with an active post_update_doctor: on line; AND update-check.mjs resolveConfig over a config containing both mode: and post_update_doctor: still resolves mode and throttle_hours unchanged | done | bash tests/skills/test-aai-update.sh exit 0 (0137-TEST-004 PASS incl. SEAM-3 update-check arm); bash tests/skills/test-aai-update-check.sh exit 0; same RED/GREEN logs | — | precedent and default-on rationale recorded in D2 |
| Spec-AC-03 | WHEN the source of update-doctor-report.mjs and the two postamble diffs are scanned THEN they contain no network or LLM primitive (token set: fetch, node http, node https, Invoke-WebRequest, Invoke-RestMethod, curl, wget, git fetch, git ls-remote, git clone) and the helper imports only node built-ins; AND WHEN the doctor child exceeds the timeout (default 240000 ms, --timeout-ms override) THEN the helper returns within the bound plus grace and prints the named timeout SKIP line; AND WHEN the doctor JSON carries categories with status SKIP (the non-Windows CAT-14 and CAT-15 shape) THEN the report embeds that JSON byte-verbatim inside its fenced block, no category rewritten | done | bash tests/skills/test-aai-update.sh exit 0 (0137-TEST-005 timeout+zero-network, 0137-TEST-006 passthrough, 0137-TEST-012 real engine); same RED/GREEN logs | — | Windows CAT-14 wall-clock note from decisions 2026-08-13 recorded in D4 |
| Spec-AC-04 | WHEN a report is written THEN it begins with a provenance header listing Generated at (UTC) in ISO 8601, AAI version equal to the Template version value in .aai/system/AAI_PIN.md falling back to the Version line of docs/ai/AAI_VERSION.md and else the literal UNKNOWN, AAI commit from the pin's Template commit else UNKNOWN, Platform as process.platform-arch with os.release() and the node version, Machine as the sanitized hostname tag, and Doctor exit with the child exit code plus verdict and issues, followed by the full doctor JSON in one fenced block; AND WHEN more than 10 files matching doctor-UTCSTAMP-tag.md exist after the write THEN only the oldest beyond 10 are deleted and no file of any other name shape is ever touched; AND docs/USER_GUIDE.md states the update-report-attach loop in the /aai-update section, docs/product/aai-update.md exists with the required product sections filled (capability aai-update), docs/product/aai-doctor.md points at the field report, and CHANGELOG.md carries one unreleased heading entry for this scope | done | bash tests/skills/test-aai-update.sh exit 0 (0137-TEST-007 provenance, 0137-TEST-008 retention, 0137-TEST-010 docs pins); same RED/GREEN logs | — | report is runtime-ignored by the vendored .gitignore, so it can never dirty the downstream tree (D3) |
| Spec-AC-05 | WHEN the repository hygiene commands run THEN check-test-registration.mjs reports every new test function registered, tests/skills/suite-map.yaml's aai-update row names .aai/scripts/update-doctor-report.mjs, .aai/system/PROFILES.yaml classifies that file exactly once under core, the prompt-diet ledger carries one JUSTIFIED_ADDITIONS entry for the SKILL_UPDATE.prompt.md relay clause with the TEST-012 checkpoint bumped from -7210 to the new re-summed value, and the layer-profiles, suite-select, prompt-diet and hygiene-pack suites are green | done | node .aai/scripts/check-test-registration.mjs exit 0; test-aai-layer-profiles/suite-select/prompt-diet (TEST-012 pin -7144)/hygiene-pack all exit 0; 0137-TEST-011 PASS | — | both companion obligations from the closed list are in this AC |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.aai/scripts/update-doctor-report.mjs` — NEW, zero-dependency Node. Flags:
  `--root <path>` (default: two levels up from its own location, doctor
  precedent), `--config <path>`, `--doctor <path>` (test override),
  `--timeout-ms <n>`, `--max-reports <n>` (default 10). Reads the config
  (column-0 scan, first occurrence wins, mirroring resolveConfig), spawns
  `process.execPath <doctor> --root <root> --json` with the timeout, assembles
  the provenance header from the pin with the AAI_VERSION fallback, writes the
  report, prunes, prints the one line. Exit 0 on every runtime outcome, 2 on
  usage.
- `.aai/scripts/aai-update.sh` — after the AAI_PIN block and before `## Next`:
  a `## Doctor field report` section that checks `command -v node` and the
  helper's existence, invokes it `|| echo` the wrapper SKIP line; skipped
  entirely on `--dry-run` (the dry-run path exits earlier already).
- `.aai/scripts/aai-update.ps1` — same postamble, try/catch, ASCII-only
  strings, before the `## Next` block.
- `.aai/templates/update-config.template.yaml` — key documentation block plus
  the active `post_update_doctor: on` line.
- `.aai/SKILL_UPDATE.prompt.md` — one relay clause in step 2 (max 120 B).
- `.aai/system/PROFILES.yaml` — one `core:` entry for the helper.
- `tests/skills/test-aai-update.sh` — new `test_006`..`test_0NN` functions per
  the Test Plan, each registered in `main()`; stub doctors are tiny node
  scripts the fixtures write (fixed CLEAN JSON, fixed ISSUES JSON, exit 2,
  garbage stdout, sleep).
- `tests/skills/suite-map.yaml` — the `aai-update` row gains
  `.aai/scripts/update-doctor-report.mjs`.
- `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`
  — ledger entry + TEST-012 checkpoint bump.
- `docs/USER_GUIDE.md` — `/aai-update` section gains the field-report
  paragraph and the attach-when-filing-an-issue loop.
- `docs/product/aai-update.md` — NEW from `.aai/templates/PRODUCT_TEMPLATE.md`
  (capability `aai-update`; the close gate resolves the product doc from the
  intake capability).
- `docs/product/aai-doctor.md` — one pointer line at the field report.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading entry (per the
  release engine's per-entry-heading contract).

Data flows:

- SEAM-1: the doctor's `--json` document crosses from `aai-doctor.mjs` into
  the helper (verdict, issues, categories) and then byte-verbatim into the
  report file. Stub tests on one side test the stub, so TEST-012 runs the
  helper over the REAL vendored doctor engine against a fixture root.
- SEAM-2: the helper's stdout line crosses into the update scripts' output
  stream under `set -euo pipefail` (sh) and `$ErrorActionPreference = "Stop"`
  (ps1); a helper crash must surface as the wrapper's own SKIP line, never as
  an update failure. Crossed by TEST-003's crash arm.
- SEAM-3: `docs/ai/update-config.yaml` is written by the sync seed and read
  by BOTH `update-check.mjs` and the helper; the new key must be invisible to
  the old parser. Crossed by TEST-004's combined-file arm.
- SEAM-4: the report lands in a directory the vendored `.gitignore`
  runtime-ignores and docs-audit classifies as canonical; a report must never
  appear in `git status --porcelain`. Crossed by TEST-001's clean-status
  assertion inside the fixture target.

Edge cases:

- Target without a git repo or without a pin (partial vendoring): provenance
  degrades to UNKNOWN fields, the report still lands.
- `docs/ai/reports/` missing in the target: the helper `mkdir -p`s it (the
  sync only creates it on a conflict).
- Two updates inside one second on one machine: same filename — second write
  wins whole-file; acceptable, recorded here, not defended.
- A hostname that sanitizes to empty (non-ASCII hostname): `unknown-host`.
- The relocated sh self-copy runs the OLD postamble on the first update that
  vendors this feature (RR-1).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)            | Description | Status |
|----------|------------|-------------|---------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-update.sh | Full fixture update run: a file:// fixture source whose aai-sync.sh installs a stub doctor emitting fixed CLEAN JSON plus the real helper; the update exits 0, prints the Doctor field report section with exactly one DOCTOR CLEAN line naming the report path, the report file exists in the target's docs/ai/reports matching the doctor-UTCSTAMP-tag.md shape, and git status --porcelain in the git-initialized target (vendored .gitignore present) does not list it; a --dry-run arm never creates a report. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-update.sh | Direct helper failure matrix: --doctor pointing at a missing path, at a stub exiting 2, and at a stub printing non-JSON each yield helper exit 0 with exactly one DOCTOR-REPORT SKIP line naming that single reason, and no report file is written in any arm. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-update.sh | Induced-failure update runs: with a stub doctor exiting 1 with ISSUES JSON the update still exits 0, the line carries ISSUES and the report is written; with a stub doctor that crashes and with the helper file replaced by one that throws, the update still exits 0 and exactly one named SKIP line appears (the second arm proving the wrapper-level guard, SEAM-2); the update exit code equals the no-failure arm's in every case. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-update.sh | Config matrix: absent config runs the doctor; post_update_doctor: off yields the named disabled-by-config line and no report; an unknown value warns on stderr and runs; an indented and a commented key are ignored (column-0 discipline); and a combined file carrying mode: notify plus post_update_doctor: off still resolves mode notify through node .aai/scripts/update-check.mjs --config (SEAM-3). Commands: bash tests/skills/test-aai-update.sh and bash tests/skills/test-aai-update-check.sh | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-update.sh | Timeout and zero-network: a sleeping stub doctor under --timeout-ms 1000 returns within a bounded wall-clock with the named timeout SKIP line and helper exit 0; and neither .aai/scripts/update-doctor-report.mjs nor the two update entrypoints reference a network or LLM primitive from the pinned token set. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-006 | Spec-AC-03 | unit        | tests/skills/test-aai-update.sh | SKIP passthrough: a stub doctor emitting JSON whose CAT-14 and CAT-15 carry status SKIP produces a report whose fenced JSON block is byte-identical to the stub's stdout document — no category rewritten, no SKIP converted. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-007 | Spec-AC-04 | unit        | tests/skills/test-aai-update.sh | Provenance matrix: a fixture root with a stamped AAI_PIN.md yields a header carrying that pin's Template version and Template commit; a root with no pin but a docs/ai/AAI_VERSION.md yields the fallback Version value; a root with neither yields the literal UNKNOWN; every report carries Generated at (UTC), Platform with the node version, and the sanitized Machine tag. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-008 | Spec-AC-04 | unit        | tests/skills/test-aai-update.sh | Retention: a reports dir pre-seeded with 12 doctor-shape files plus one sync-conflicts file and one validation file ends the run with exactly 10 doctor-shape files (the newest, including the just-written one) and both foreign files untouched. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-009 | Spec-AC-01 | unit        | tests/skills/test-aai-update.sh | ps1 parity structural pin: aai-update.ps1 contains the Doctor field report section invoking the same helper path inside try/catch with the DOCTOR-REPORT SKIP fallback string, its postamble bytes are ASCII-only, and the sh postamble's helper invocation is or-guarded so set -e cannot propagate a helper failure. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-010 | Spec-AC-04 | unit        | tests/skills/test-aai-update.sh | Documentation pins: docs/USER_GUIDE.md's /aai-update section names the field report and the attach-when-filing-an-issue loop, docs/product/aai-update.md exists with the required product sections non-placeholder and capability aai-update, docs/product/aai-doctor.md mentions the field report, and CHANGELOG.md carries one unreleased heading entry for this scope. Command: bash tests/skills/test-aai-update.sh | green |
| TEST-011 | Spec-AC-05 | integration | tests/skills/test-aai-update.sh | Governance set: check-test-registration reports no orphan for the update suite, the suite-map aai-update row names the helper, PROFILES.yaml lists .aai/scripts/update-doctor-report.mjs exactly once under core, the prompt-diet ledger entry and TEST-012 checkpoint are trued up, and the named suites are green. Commands: node .aai/scripts/check-test-registration.mjs and bash tests/skills/test-aai-layer-profiles.sh and bash tests/skills/test-aai-suite-select.sh and bash tests/skills/test-aai-prompt-diet.sh and bash tests/skills/test-aai-hygiene-pack.sh | green |
| TEST-012 | Spec-AC-03 | e2e         | tests/skills/test-aai-update.sh | SEAM-1 real-engine crossing: the helper runs the REAL vendored .aai/scripts/aai-doctor.mjs (no stub) against a minimal fixture root and produces a report whose JSON parses, whose verdict token matches the emitted line, and whose categories array carries the real CAT-01..CAT-16 ids with CAT-14 and CAT-15 honestly SKIPped on this POSIX host. Command: bash tests/skills/test-aai-update.sh | green |

Test status values: pending -> red -> green

## Seams crossed

Enumerated with their crossing tests in the Implementation plan's Data flows
section: SEAM-1 (doctor JSON into helper into report — TEST-012 real engine,
TEST-006 shape), SEAM-2 (helper stdout and failure into the set -e wrapper —
TEST-003), SEAM-3 (one config file, two parsers — TEST-004), SEAM-4 (report
into the gitignored, canon-listed reports dir — TEST-001).

## Residual risks (accepted)

- RR-1 — rollout lag: the postamble executes from the pre-update script copy,
  so each downstream machine's FIRST update after this ships vendors the
  feature without running it; the first report lands on the second update.
  Inherent to self-updating entrypoints; not defended.
- RR-2 — the fleet loop's real value needs a real downstream run: no local
  test proves a WSL-functional host's report. The decisions.jsonl 2026-08-13
  residual stays open until one such report is attached; this spec only
  builds the pipe (D5).
- RR-3 — the ps1 postamble is proven by structural pin and the ps1-quality
  parse gates locally, not by an executed Windows update run; first real
  proof is the next Windows-machine update, which is exactly the telemetry
  this scope creates.
- RR-4 — the report says what the machine looked like AT update time; a
  machine that breaks later is invisible until its next update. Accepted: the
  update is the one moment every fleet machine reliably passes through.
- RR-5 — same-second double update on one machine overwrites one report file
  (whole-file write, no interleaving). Recorded, not defended.

## Verification

Commands to run:

- `bash tests/skills/test-aai-update.sh`
- `bash tests/skills/test-aai-update-check.sh`
- `bash tests/skills/test-aai-doctor.sh` (doctor engine untouched — regression)
- `bash tests/skills/test-aai-layer-profiles.sh`
- `bash tests/skills/test-aai-suite-select.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `bash tests/skills/test-ps1-quality.sh` (parse and analyzer gates over the
  edited aai-update.ps1)
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0124-spec-update-doctor-field-report.md`

Evidence artifacts: stored RED logs under `docs/ai/tdd/` for the TDD-lane
AC-gating tests (TEST-002, TEST-004, TEST-005, TEST-007, TEST-008); the
recorded RED observation for the loop-lane rows (each pin fails on the
pre-change tree because neither the helper nor the postamble exists); full
stdout with exit codes for every command above.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract

For each implementation, validation, TDD, and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

Strategy is `hybrid`: a stored RED artifact under `docs/ai/tdd/` per AC-gating
test on the TDD lane (TEST-002, TEST-004, TEST-005, TEST-007, TEST-008), plus
the full verification matrix above. For the loop-lane rows the RED observation
is the pin failing on the pre-change tree, recorded but not necessarily
stored.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
