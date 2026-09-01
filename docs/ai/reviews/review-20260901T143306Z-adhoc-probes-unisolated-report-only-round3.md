# Code Review (round 3) — adhoc-probes-unisolated-report-only

```yaml
review:
  scope: "git diff main...HEAD (worktree /Users/ales/Projects/aai-fix-adhoc-probes-unisolated-report-only, branch fix/adhoc-probes-unisolated-report-only; 8 commits 569320d, 41df498, 5699eef, bd1efd2, de3fec6, 393e32a, d5ccb67, faf497d)"
  spec: docs/specs/SPEC-0159-spec-adhoc-probes-unisolated-report-only.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:778 — the ONLY `echo \"AAI-ADHOC: ...\"` in the tree, inside `case dirty` + `AAI_INVOCATION_KIND = 'ad-hoc'` (:766-786); AAI_TW_ROOT is AAI_REPO_ROOT (:141). TEST-301 at tests/skills/test-aai-suite-isolation.sh:2200. OWN PROBE in a scratch fixture repo: exactly one `AAI-ADHOC: <fixture root>` stderr line, exit 0." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "the banner and the escalation both sit inside `case dirty` (aai-run-tests.sh:766-786), so a clean run reaches neither; AAI_ISO_STATUS stays `not-applicable` for a non-suite invocation and the `case` at :603-610 prints nothing for that value. TEST-302 at :2228. OWN PROBE: clean ad-hoc run, stderr EMPTY (zero AAI-ADHOC, zero AAI-ISOLATION)." }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/repo-tripwire.sh:167 (`tw_remediation=\"${5:-A suite must run against a fixture, never against PROJECT_ROOT.}\"`) + :202 (`printf '%s   %s\\n'`). INDEPENDENTLY PROVED, not inferred: I sourced main's repo-tripwire.sh and HEAD's in turn over the same before/after snapshot pair and `cmp -s` reports the 4-arg output BYTE-IDENTICAL. All four callers other than the ad-hoc arm pass exactly 4 args (tests/skills/test-framework.sh:1274, :1605; tests/skills/test-aai-repo-tripwire.sh:409; aai-run-tests.sh:788), so every one takes the default by construction. TEST-303(a)/(b) at :2248 (suite leg), TEST-306(a) at :2370 (framework leg). LIVE CONFIRMATION: my own full sweep ran `aai-run-tests.sh bash tests/skills/test-framework.sh`, the framework dirtied docs/ai/tests/test-runs.jsonl, and the outer wrapper printed the SUITE sentence with NO AAI-ADHOC line." }
      - { ac: Spec-AC-04, call: compliant,
          citation: "aai-run-tests.sh:784 gates on `${AAI_SHIPPING_WRITE_FATAL:-0}` = 1, so unset changes nothing. TEST-304 at :2290. OWN PROBES: flag unset, dirty ad-hoc exiting 0 -> wrapper 0; exiting 7 -> wrapper 7." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "aai-run-tests.sh:784-786 (`STATUS=12` only when the wrapped status is 0, only in the ad-hoc arm); TIMED_OUT is still tested first at :815 so 124 outranks 12. TEST-305(a)-(e) at :2310; the `nor of test-framework.sh` clause is carried by TEST-306(a)/(b) at :2370. OWN PROBES: flag set + dirty + 0 -> 12; flag set + dirty + 7 -> 7; flag set + clean -> 0. I did not re-probe the framework clause by hand; TEST-306 covers it and passed in my full sweep." }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/follow-ups.mjs:733 extractHeadingClaims, :775 extractInlineClaims, :792 extractClaims (union, deduplicated). TEST-024 at tests/skills/test-aai-follow-ups.sh:1547. OWN RUNS on scratch fixtures of both shapes: each reports the claimed ids with their folded status." }
      - { ac: Spec-AC-07, call: compliant,
          citation: "follow-ups.mjs:745-766 — labelled segments, the `none` sentinel short-circuit at :751, the any-other-unlabelled fallthrough at :753. TEST-025 asserts all four branches by EXACT set, not count. Two authoring shapes OUTSIDE the AC's own four-branch wording are silently dropped (N3, N4 below); neither contradicts the AC as written." }
      - { ac: Spec-AC-08, call: compliant,
          citation: "follow-ups.mjs:896-918 (MISS for absent/non-done, ATTRIBUTION for done-but-textually-unrelated) and :940 (only MISS, only under --strict, moves the exit code). TEST-026. OWN real-corpus run: miss=3, attribution=10, ok=20, exit 0." }
      - { ac: Spec-AC-09, call: compliant,
          citation: "OWN RUNS against the live ledger: report-only with 3 MISSes -> exit 0; bare `--strict` -> exit 1; `--path` at a nonexistent file -> exit 2. TEST-027. I checked specifically that `exit()` (lib/cli-pipe-guard.mjs) THROWS an ExitSignal rather than returning, so the `if (!st.isFile()) usageError(...)` sites with no `return` cannot fall through into the later `exit(0)`. The `--strict=<value>` spelling silently means report-only (N1), a form this AC does not enumerate." }
      - { ac: Spec-AC-10, call: compliant,
          citation: "follow-ups.mjs:872-876 (union of docs/specs and docs/issues, recursive) and :884-887 (an unreadable individual doc contributes zero claims, never an error). TEST-028. OWN real-corpus run: docs_scanned=410, claims=33, exit 0; a fixture doc with no closure statement contributes nothing." }
      - { ac: Spec-AC-11, call: compliant,
          citation: "allowlist at tests/skills/test-aai-follow-ups.sh:1523 (exactly three entries), lower-bound floor at :1755-1761, subset check at :1764, exact-contents pin at :1767-1771, negative control at :1780-1791. OWN real-corpus run reports exactly the three declared ids as MISS and nothing else. See N6 on the pin's permanence." }
      - { ac: Spec-AC-12, call: compliant,
          citation: "tests/skills/suite-map.yaml:289-290. OWN RUNS: `select-suites.mjs` over docs/specs/SPEC-9999-x.md and over docs/issues/CHANGE-9999-x.md each print `SELECTED aai-follow-ups`. TEST-030." }
      - { ac: Spec-AC-13, call: compliant,
          citation: "OWN `follow-ups.mjs list --ref registry-audit-20260820 --status all --json`: both ids status=done, resolved_by=adhoc-probes-unisolated-report-only. The decisions.jsonl hunk adds exactly 2 follow_up_status lines, so no other item is closed. OWN `git diff --name-status main...HEAD`: exactly one docs/specs path, this scope's own SPEC-DRAFT — no other scope's frozen document. The AC is MET by the delivery; the arm that encodes its second half stops checking at the close ceremony (N5)." }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 433,
          issue: "`--strict` is listed in FLAG_SPECS['verify-closures'] (the VALUE-flag table) while being consumed as a boolean at :492-496, so the `--flag=value` escape hatch at :500-507 accepts `--strict=1`, stores the STRING '1', and `opts.strict === true` at :927 rejects it — the gate is silently off. CARRIED from rounds 1/2, already filed.",
          failure_scenario: "REPRODUCED this round on a fixture with 2 MISSes: `verify-closures --path <doc> --strict=1` prints both MISS lines and exits 0; bare `--strict` on the same input exits 1. `--strict=1` is a spelling the CLI's own USAGE documents as general grammar, so a CI step written that way is a gate that can never fail." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 874,
          issue: "Corpus mode resolves both roots against `process.cwd()` and says nothing when both resolve to nothing: it prints `docs=0 claims=0 miss=0` and `strict && counts.miss > 0` at :940 is false, so it exits 0 even under `--strict`. CARRIED from round 2 (N3), where disposition (b) was recommended — but `fu-verify-closures-corpus-cwd-silent` is NOT in docs/ai/decisions.jsonl (own grep: 0 hits; own `follow-ups.mjs list --ref adhoc-probes-unisolated-report-only` shows only 2 items). The round-2 H6 obligation is still open.",
          failure_scenario: "An operator or CI step runs the documented `verify-closures --strict` from anywhere other than the repository root and gets a live-looking gate that reports zero claims and exits 0. The in-repo ratchet is protected by TEST-029's new floor (docs>100, claims>10); the operator-facing CLI is not." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 762,
          issue: "extractHeadingClaims scans only the segments AFTER each label match (`body.slice(labels[i].end, segEnd)`), so every fu- id stated in the section body BEFORE the first CLOSED FULLY / CLOSED QUALIFIEDLY / NOT CLOSED label is silently dropped — not disclaimed, not reported, absent from the claim set entirely. CARRIED from rounds 1/2, already filed.",
          failure_scenario: "REPRODUCED this round: a section reading `- \\`fu-alpha-claimed-before-any-label\\` (P2) — fully closed by this scope.` above a `NOT CLOSED, deliberately:` block yields `claims: []`. The headline claim is unverified behind a green gate — fu-spec-closes-claim-unverified reintroduced in a narrower shape." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 782,
          issue: "NEW this round — the same false-negative direction in the OTHER scanner. extractInlineClaims cuts the claim list at the first blank line (`after.search(/\\n[ \\t]*\\n/)`), so the very common markdown shape `Registry items closed by this scope:` on its own line, a blank line, then a bullet list of ids yields ZERO claims. Neither round 1 nor round 2 names this shape (own grep over both reports).",
          failure_scenario: "REPRODUCED this round: a doc reading `Registry items closed by this scope:` / blank line / `- \\`fu-gamma-claimed-in-sublist\\`` yields `claims: []`. Combined with N3, the two most natural ways to write a claim list — above the label block, or under a colon on its own line — are both invisible to the checker. Not in today's corpus (own probe over all 410 docs found no pre-label ids, and every inline label in the corpus is same-line), so no bite today." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 1859,
          issue: "NEW this round. The round-2 B1 remediation gates TEST-031's delivery-diff guard on `grep -F 'SPEC-0159-spec-adhoc-probes-unisolated-report-only.md'` matching the live `$BASE_REF...HEAD` docs/specs diff. The close ceremony renames that file to `SPEC-0NNN-spec-adhoc-probes-unisolated-report-only.md`; because the file is NEW on this branch there is no deletion relative to main, so the diff then lists only the destination path, the literal `SPEC-DRAFT-` grep stops matching, the guard skips itself — and `log_pass` at :1872 still prints `no other frozen spec document is touched (TEST-013)`.",
          failure_scenario: "PROVED, not reasoned: I cloned the worktree, `git mv`'d the spec to SPEC-0159-…, committed, and ran the arm's own git command. `git diff origin/main...HEAD -- 'docs/specs/*.md'` returns ONLY `docs/specs/SPEC-0159-spec-adhoc-probes-unisolated-report-only.md` (identical under `-c diff.renames=false`). own_spec_touched is empty, the `else` INFO branch fires, and the arm's green line claims a negative it never checked — at this scope's own close ceremony, i.e. the next commit, and permanently thereafter. Round 2's B1 IS genuinely fixed: I also simulated a post-merge future branch adding an unrelated spec and the guard correctly skips instead of failing. This finding is the opposite failure mode — a guard that goes quiet, not one that misfires." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 1767,
          issue: "NEW this round. Spec-AC-11's `at delivery SHALL contain exactly the three measured entries` is encoded as two PERMANENT assertions — a count pin (`-eq 3`) and an exact-contents pin against a hardcoded sorted string at :1769 — inside a shared suite that now runs on every sweep AND on every docs-only diff (suite-map.yaml:289-290). The ratchet's subset check is drainable; the allowlist array is not.",
          failure_scenario: "Someone genuinely closes `fu-tdd-skips-full-sweep` and does the obvious hygiene — removes it from KNOWN_UNVERIFIED_CLOSURE_CLAIMS. The subset check still passes (the MISS set shrank), but `[[ ${#KNOWN_UNVERIFIED_CLOSURE_CLAIMS[@]} -eq 3 ]]` fails and log_fail hard-exits the whole aai-follow-ups suite with `the allowlist must hold exactly the three measured entries at delivery, got 2`. The guard punishes exactly the improvement D10 says it exists to encourage." }
      - { rank: NON-BLOCKING, file: .aai/scripts/follow-ups.mjs, line: 740,
          issue: "The claim-section boundary is `rest.search(/\\n##[ \\t]+/)`, which does not match `###`, so a nested sub-section stays inside the claim body and every fu- id in it becomes a claim. CARRIED from rounds 1/2, accepted residual there.",
          failure_scenario: "REPRODUCED this round: a `### Something` sub-section under the claim heading contributed `fu-epsilon-after-h3` as a claim alongside the real one. False-MISS direction, so Spec-AC-11's subset ratchet contains the blast radius — TEST-029 reds and forces a reviewed allowlist update rather than passing silently." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 778,
          issue: "`echo \"AAI-ADHOC: $AAI_TW_ROOT ...\"` in a `#!/bin/sh` script. On a dash /bin/sh — the Linux CI leg — `echo` interprets backslash escapes in the interpolated repository path. CARRIED from rounds 1/2, accepted residual there.",
          failure_scenario: "A repository path containing a backslash renders a mangled banner on the Linux CI leg. Identical shape to the pre-existing AAI-TRIPWIRE NOTE line at :808; `printf '%s\\n'` would be strictly safer." }
  cannot_verify:
    - { claim: "RR-1 — the ad-hoc banner and the AAI_SHIPPING_WRITE_FATAL opt-in on the Windows legs (aai-run-tests.ps1 -> WSL, and the Git-Bash degraded leg), including whether the new AAI-ADHOC stderr line displaces `AAI-BRANCH: WSL` across the WSL1 boundary the way the tripwire NOTE line once did (aai-run-tests.sh:800-806 records that exact history).",
        closes_with: "A run of TEST-301..306 on the WSL leg plus a field-verified Git-Bash capture, recorded in the SPEC-0046 platform matrix. Every probe I ran was macOS." }
    - { claim: "That the close ceremony will restore correct per-AC Evidence atomically with the frontmatter flip. bd1efd2 deliberately reverted all 13 Status cells to `implementing` and all 13 Evidence cells to `—` so docs-audit stays CLEAN on an open document, so the frozen spec's own PASS criteria (`all Spec-AC in a terminal status`) is not met at review time and the AC table carries zero evidence citations.",
        closes_with: "The close-ceremony commit showing 13 `done` rows whose Evidence cells carry the TEST ids and the commit SHA, together with the frontmatter status flip and a `docs-audit --check --strict` that stays CLEAN afterwards." }
    - { claim: "Per-arm RED proof for TEST-025..031 and any RED/GREEN proof for TEST-306. The stored RED log (docs/ai/tdd/red-20260901T072000Z-follow-ups-verify-closures.log) stops at TEST-024 because that suite runs `set -euo pipefail` with `log_fail` = `exit 1`; TEST-306 was added in round 3 as a preservation arm and has no RED artifact; and both stored GREEN logs predate d5ccb67/faf497d and TEST-306, so no GREEN artifact exists at HEAD outside the sweeps.",
        closes_with: "Per-arm RED runs against the pre-change tree (or an explicit statement that a preservation arm has no meaningful RED), plus a GREEN log captured at HEAD. The RED-by-construction argument is strong — the subcommand did not exist, so every arm calling it exits 2 — but it is inference, not observation." }
    - { claim: "That TEST-029's real-corpus ratchet will not red during the ordinary window between a future scope's spec freeze and its ledger close step. By D10's own design a NEW unverified claim reds, and a spec states its CLOSED FULLY claim before `follow-ups.mjs close` runs.",
        closes_with: "One future scope run end to end, with sweep results recorded at spec-freeze time and again after the close step. Spec-intended (Spec-AC-11 + D10), so a named gap rather than a finding." }
    - { claim: "The aggregate CI cost of routing every docs/specs/** and docs/issues/** change through the aai-follow-ups suite (suite-map.yaml:289-290), whose TEST-029 and TEST-031 arms both hit the live repository.",
        closes_with: "A few sweeps' worth of selected-suite counts and wall-clock in docs/ai/tests/test-runs.jsonl against the pre-change baseline. Intended by Spec-AC-12; noted, not disputed." }
    - { claim: "Stability of the full-sweep result across runs. My own sweep (run_id test-20260901-141129) measured 84 total / 83 passed / 1 failed; the failure is aai-run-tests TEST-005 (reaper), which I reproduced standalone on THIS branch and again on a clean `main` clone at 787c7d2 — pre-existing, not branch-introduced. One sweep still cannot distinguish a stable 83/84 from a run that happened to hit or miss other load-sensitive arms.",
        closes_with: "Two or three consecutive sweeps at the same head with nothing else writing to the worktree." }
  overall: pass
```

## Scope and spec

- Diff scope: `git diff main...HEAD` inside the worktree
  `/Users/ales/Projects/aai-fix-adhoc-probes-unisolated-report-only`,
  branch `fix/adhoc-probes-unisolated-report-only`, 8 commits
  (569320d, 41df498, 5699eef, bd1efd2, de3fec6, 393e32a, d5ccb67, faf497d).
- Preflight, run by me: `docs/ai/STATE.yaml` read directly —
  `worktree.user_decision: worktree`, `base_ref: main`,
  `path: /Users/ales/Projects/aai-fix-adhoc-probes-unisolated-report-only`,
  `inline_review_scope: null`. `git status --porcelain` was EMPTY at review
  start and after every probe (every fixture lived under a scratch directory).
  Two exceptions, both disclosed: I copied
  `tests/skills/lib/cd-subshell-leak-baseline.tsv` aside, re-ran
  `check-cd-subshell-leak.mjs --record` to prove the committed baseline is
  byte-identical to a fresh record, then restored it and re-verified clean;
  and my own full sweep appended one telemetry row to
  `docs/ai/tests/test-runs.jsonl` (the framework's own ledger write — the
  worktree carries that single modified file now, and it belongs with this
  report at staging time, exactly as faf497d did).
- Spec: `docs/specs/SPEC-0159-spec-adhoc-probes-unisolated-report-only.md`,
  SPEC-FROZEN: true, ceremony_level 2, read in full including D1-D10, the
  four Seams, the Edge cases, RR-1..RR-3 and both tables.
- 16 files changed, +2125 / -22.

## Dispatch note (ANTI-GAMING CONTRACT)

The dispatch briefing told me two prior rounds each found "exactly one
BLOCKING code_quality finding" and named their subject matter (a
friction-capture false-record bug; a branch-agnostic test assertion). That is
a characterization of expected findings, which the contract asks the
orchestrator not to make. The same briefing also, to its credit, instructed
me to re-derive everything and not to treat prior dispositions as settled.
I record the coaching attempt here and reviewed the full scope from the code:
every finding below was re-derived and re-reproduced this round from the diff
and from my own probes. I read the prior reports only AFTER forming my own
list, to check whether the H6 artifacts they promised were actually filed —
one was not (N2).

## Verdict 1 — spec_compliance: PASS

All 13 Spec-AC rows compliant; per-row citations in the YAML block. What I
actually ran, rather than read:

| Check | Result |
|---|---|
| Own fixture probe: ad-hoc dirty, flag unset | exit 0; exactly 1 `AAI-ADHOC:` line naming the fixture root; tripwire block carries the NEW remediation sentence and zero occurrences of the suite sentence |
| Own fixture probe: ad-hoc clean | exit 0, stderr EMPTY |
| Own fixture probe: ad-hoc dirty exit 7, flag unset | exit 7 |
| Own fixture probes: flag set — dirty+0 / dirty+7 / clean+0 | 12 / 7 / 0 |
| Own fixture probe: flag set, dirty+0, friction capture ON at a fixture spool | exit 12, spool 0 lines; positive control (dirty+7) spools exactly 1 `deterministic_script_failure` |
| Own library-level byte-identity proof (main's `aai_tripwire_report` vs HEAD's, same snapshots, 4 args) | `cmp -s` identical |
| Own enumeration of every `aai_tripwire_report` call site | 4 sites; all but the ad-hoc arm pass exactly 4 args |
| `follow-ups.mjs verify-closures --json` (real corpus) | exit 0; docs=410, claims=33, miss=3, attribution=10, ok=20; the MISS set is EXACTLY the three declared allowlist ids |
| `verify-closures --strict` / report-only / bad `--path` | exit 1 / 0 / 2 |
| Own fixture runs for the four D9 parse branches | each yields the exact expected claim set |
| `select-suites.mjs` on `docs/specs/SPEC-9999-x.md` and `docs/issues/CHANGE-9999-x.md` | both print `SELECTED aai-follow-ups` |
| `follow-ups.mjs list --ref registry-audit-20260820 --status all --json` | both ids `done`, `resolved_by=adhoc-probes-unisolated-report-only` |
| `git diff --name-status main...HEAD` | exactly one `docs/specs/` path (this scope's own); decisions.jsonl adds exactly 2 `follow_up_status` lines |
| `docs-audit.mjs --check --strict --no-event` | exit 0, Verdict CLEAN (Drifted 0, False-open 0) |
| `spec-lint.mjs` | exit 0; 159 specs scanned, 0 findings |
| `check-cd-subshell-leak.mjs` | exit 0, UNSAFE 0; baseline byte-identical to a fresh `--record` (deltas +3 follow-ups / +7 suite-isolation, no lowered row) |
| Full sweep `aai-run-tests.sh bash tests/skills/test-framework.sh` (`AAI_TEST_TIMEOUT=3000`), run_id test-20260901-141129 | 84 total / 83 passed / 1 failed / 0 skipped; 84/84 isolated; 84/84 fully seeded; 0 waves re-attributed |
| The single sweep failure, `aai-run-tests` TEST-005 (reaper) | reproduced standalone on this branch AND on a clean `main` clone at 787c7d2 → pre-existing, not branch-introduced |

Incidental live evidence for Spec-AC-03/05's framework clause: the sweep
itself was an `aai-run-tests.sh bash tests/skills/test-framework.sh`
invocation, the framework dirtied `docs/ai/tests/test-runs.jsonl`, and the
outer wrapper printed the tripwire block with the SUITE sentence and no
`AAI-ADHOC` line, exiting with the framework's own 1 rather than 12.

### Guardrails

- `protected_paths_l3` (docs/ai/docs-audit.yaml:74-82): none of the eight
  paths appears in the diff.
- `.aai/*.prompt.md`: `git diff --name-only main...HEAD -- '.aai/*.prompt.md'`
  is empty — zero prompt-corpus bytes, exactly as D10 promises, so the
  prompt-diet companion obligation does not apply.
- New `.aai/scripts/` file: none. `git diff --name-status main...HEAD --
  .aai/scripts/` is three `M` lines and nothing else.
- Scope creep: the 16 changed files are exactly the spec's own component list
  plus the two review reports, the docs index, the two append-only ledgers and
  the run telemetry. Nothing foreign.

### Deviations from the frozen spec (named, all reasonable)

1. **"No new registry items are filed by this scope."** — the spec's own
   `## Registry items closed by this scope` section says exactly that. The
   delivery diff files two (`fu-verify-closures-strict-value-off` P2,
   `fu-verify-closures-claim-before-label` P3), both round-1 review H6
   dispositions. Filing is not closing, so Spec-AC-13 stands; the frozen
   document's prose is now false and was not amended.
2. **PASS criteria not met at review time.** The spec's Verification section
   says "all TEST-xxx green AND all Spec-AC in a terminal status". bd1efd2
   deliberately reverted all 13 Status cells to `implementing` and all 13
   Evidence cells to `—` so `docs-audit --check --strict` stays CLEAN on an
   open document, deferring the flip to the close ceremony. I confirmed the
   audit is CLEAN with that shape. Real deviation; recorded in the validation
   record; see cannot_verify #2.
3. **Local TEST-id renumbering.** The Test Plan names TEST-001..013; the
   isolation suite lands them as TEST-301..305 (disclosed in a header comment
   at test-aai-suite-isolation.sh:2190, to avoid colliding with that file's
   pre-existing SPEC-0138 TEST-001..006) and the follow-ups suite as
   TEST-024..031. Traceable and disclosed.
4. **One arm beyond the frozen Test Plan.** TEST-306 (framework-kind pin) was
   added in round 3 as a review remediation. Additive, in-scope, no AC moved.

## Verdict 2 — code_quality: PASS (no BLOCKING; 8 NON-BLOCKING)

Three of the eight reproduce findings the prior rounds recorded (N1, N3, N7),
one reproduces a round-2 finding whose promised artifact was never filed (N2),
one is a carried residual (N8), and three are new this round (N4, N5, N6).
Reproduction detail is in the YAML block.

Where I looked and found nothing worth a finding:

- **Security.** No new external input reaches a shell. The `AAI-ADHOC` line
  interpolates only `AAI_REPO_ROOT`. `verify-closures` reads and never writes;
  `listMarkdownFiles` uses `withFileTypes` Dirents, so a symlinked directory
  is `isSymbolicLink()` and never `isDirectory()` — the recursion cannot loop.
- **Exit-contract fidelity (SEAM-2).** `STATUS` is mutated in exactly one
  place (:785), inside the ad-hoc + dirty arm, behind an unset-by-default
  flag; `TIMED_OUT` is still tested first, so 124 outranks 12. Probed for all
  four D5 branches.
- **The friction false-record class (round 1's B1).** `AAI_CMD_REAL_STATUS`
  is captured at :722 immediately after `wait`, before any mutation, and the
  tail at :819-820 judges by it. I proved BOTH directions: the escalated
  success spools nothing, and a genuinely failing command still spools exactly
  one `deterministic_script_failure`. The fix did not disable capture.
- **The classification refactor (SEAM-1).** `aai_iso_is_framework_script` is a
  pure extract of code that was inline in `aai_iso_is_suite_run`; the old
  `ai_exec`/`ai_d` variables had no other reader. The second call at :593 is
  guarded by `AAI_INVOCATION_KIND != 'suite'`, and the only `set --` retarget
  loop (:576) is nested three `fi`s deep inside the suite branch, so `"$@"` is
  provably unmodified at that point. The isolated SET is unchanged; my sweep
  reports 84/84 isolated, matching main's shape.
- **Ledger fold.** `verify-closures` reuses `loadRegistry`, so a dangling
  `follow_up_status` with no `follow_up` folds to `absent` → MISS, and a
  `dropped` id folds to MISS. Both match Spec-AC-08.

### INFO (never gates)

- `AAI_SHIPPING_WRITE_FATAL` is compared with `= "1"` exactly (:784). I probed
  `AAI_SHIPPING_WRITE_FATAL=true` over a dirty ad-hoc success: exit 0,
  silently no teeth. Documented as `=1` in the wrapper header, the CHANGELOG
  and the product doc, and it is an opt-in — a spelling-ergonomics note rather
  than a defect, but the same "looks on, is off" shape as N1, one file over.
- The tripwire `unavailable` state never reaches the ad-hoc arm, so
  `AAI_SHIPPING_WRITE_FATAL=1` over a command that makes the repository
  unreadable still exits 0. D5 scopes the teeth to `dirty` by design, and
  escalating on `unavailable` would be a false-positive generator; the case is
  loudly reported by the pre-existing NOTE at :808.
- Mis-numbered decision cross-references in comments that name this spec by
  id: `aai_iso_is_framework_script`'s header (:337) calls the framework
  opt-out "D5's", but D5 is the fatal opt-in and the classification is D1;
  `follow-ups.mjs`'s new header (:75, :86) cites "D6-D9" (D6 is the declined
  friction spool) and "D5 forbids extending its snapshot/rollback transaction"
  (that is SPEC-0129's D5, while THIS spec's D7 is the decision in question).
  Comments are this repo's durable record, so a wrong pointer costs a future
  reader a wrong lookup.
- `--help`'s `Usage:` synopsis block still lists only `list`, `add` and
  `close`; `verify-closures` appears only in the prose below it, so its
  `--path` / `--strict` / `--json` grammar never shows in the synopsis.

## WARNINGS POLICY dispositions (H6)

The reviewer NAMES the recommended disposition; the ORCHESTRATOR records it.

| # | Finding | Recommended disposition | Artifact |
|---|---|---|---|
| N1 | `--strict=<value>` silently report-only | (b) typed follow_up — ALREADY FILED | decision id `fu-verify-closures-strict-value-off` (P2) |
| N2 | corpus mode silent from a foreign cwd, even under `--strict` | (b) promote to a typed follow_up, P3 — recommended id `fu-verify-closures-corpus-cwd-silent`. Round 2 already recommended this and it was never filed (own check: 0 hits in decisions.jsonl). Outstanding H6 obligation. | to be filed by the orchestrator (I am read-only on the ledger) |
| N3 | claim stated before the first label is dropped | (b) typed follow_up — ALREADY FILED | decision id `fu-verify-closures-claim-before-label` (P3) |
| N4 | inline label + blank line + bullet list yields zero claims (NEW) | (b) promote to a typed follow_up, P3 — recommended id `fu-verify-closures-inline-blankline-drops-claims`. Same root-cause family as N3 and cheapest to fix together. | to be filed by the orchestrator |
| N5 | TEST-031's delivery-diff guard self-disables at the close ceremony while `log_pass` still claims the negative (NEW) | (a) remediate-in-tree, cheapest form: move the "no other frozen spec document is touched" clause onto the guarded branch so the green line states only what was checked, or match this scope's spec by slug rather than by the `SPEC-DRAFT-` filename. If not remediated: (b) typed follow_up, P2 — recommended id `fu-test031-guard-dies-at-rename`. | orchestrator's choice |
| N6 | `KNOWN_UNVERIFIED_CLOSURE_CLAIMS` pinned by exact count and contents forever (NEW) | (b) promote to a typed follow_up, P3 — recommended id `fu-closure-allowlist-pin-blocks-draining`. Spec-AC-11 mandates the "exactly three at delivery" fact; encoding it as a permanent assertion is the implementation's own choice and is what blocks the drain. | to be filed by the orchestrator |
| N7 | `###` sub-section swallowed into the claim body | (d) accepted residual: P3 assurance-strength only — the false-MISS direction is contained by Spec-AC-11's subset ratchet, which reds and forces a reviewed allowlist update rather than passing silently; no bite observed, no false record left anywhere | this report |
| N8 | `echo` instead of `printf` in a `#!/bin/sh` script | (d) accepted residual: P3 maintenance only — identical shape to the pre-existing AAI-TRIPWIRE NOTE line at :808, needs a backslash in the repository path to bite, and no realistic Linux CI path carries one | this report |

## Next steps

1. Record N2, N4 and N6 as typed follow_ups via `follow-ups.mjs add` (never
   hand-written), and decide N5 between a one-line in-tree fix and a
   follow_up. N2 is a re-run of an obligation round 2 already recorded and the
   orchestrator did not discharge.
2. At the close ceremony: flip the 13 AC rows terminal WITH evidence in the
   same commit as the frontmatter flip, and re-run `docs-audit --check
   --strict` afterwards (cannot_verify #2). Expect TEST-031's delivery-diff
   guard to go quiet at that same commit (N5).
3. Either amend the spec's "No new registry items are filed by this scope."
   sentence under the additive-with-disclosure convention, or accept it as a
   disclosed review-driven deviation.
4. Stage this report and the one telemetry row it produced
   (`docs/ai/tests/test-runs.jsonl`) with the scope's commit, per the
   report-staging rule.
