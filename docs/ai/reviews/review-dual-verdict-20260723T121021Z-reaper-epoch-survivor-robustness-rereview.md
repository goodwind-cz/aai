---
review:
  scope: "RE-REVIEW (stale-PASS delta). git diff main...HEAD (unchanged from prior pass) plus new uncommitted working-tree changes: tests/skills/test-aai-run-tests.sh test_006 + test_013 sleep-3->sleep-6 widen (2nd/3rd audited sites) and docs/specs/SPEC-0072-*.md '## Scope extension (post-freeze, 2026-07-23)' section + broadened Spec-AC-01 row. Supersedes docs/ai/reviews/review-dual-verdict-20260723T114559Z-reaper-epoch-survivor-robustness.md (kept, not deleted)."
  spec: docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-run-tests.sh:225-236 (test_006) and :423-430 (test_013 dash/epoch branch) now sleep 6 with the same GRACE(2)+truncation(+quantization) arithmetic and DO-NOT-NARROW language as test_017's precedent (lines 569-581). The amended AC-01 row's claim is accurate FOR THE AUDITED SIGNATURE (bare `sleep N` immediately preceding a `step_start=$(date +%s)` capture) — verified by re-running the audit's own awk with NO 12-line cutoff: only 3 sites match the signature file-wide, all now sleep 6. See code_quality NON-BLOCKING finding below: a 4th site (test_015) has a DIFFERENT-shaped but related pre-step-gap risk the signature-scoped 'EVERY' claim does not cover; recommend the AC-01 wording be read as scoped to the audited signature, not literally every pre-step-gap-adjacent line in the file." }
      - { ac: Spec-AC-02, call: compliant, citation: "test_021 untouched by this delta; still registered in ALL_TESTS, still passing (re-run below)" }
      - { ac: Spec-AC-03, call: compliant, citation: "test_017 untouched by this delta (unchanged since prior review)" }
      - { ac: Spec-AC-04, call: compliant, citation: "git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh -> empty; git diff --stat -- .aai/scripts/aai-reap-tests.sh (working tree) -> empty; GRACE=2 confirmed intact" }
      - { ac: Spec-AC-05, call: cannot-verify, citation: "CI status changed since the prior review: a THIRD CI run (30004519613, 11:48:30Z) failed on test_006 exactly as the coordinator described (`reaper failed to reap the pre-step matching proc 136983`), confirming the post-freeze audit's premise was a real, CI-observed defect, not a hypothetical. No CI run has yet exercised the test_006+test_013 fix (still uncommitted/unpushed at review time) — Spec-AC-05's repeated-green evidence remains open, honestly still deferred." }
      - { ac: Spec-AC-06, call: compliant, citation: "diff still touches only tests/skills/test-aai-run-tests.sh + docs/specs/SPEC-0072-*.md + the review report; no .aai/*.prompt.md, no AGENTS.md, no new .aai/** path" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: "tests/skills/test-aai-run-tests.sh", line: 500,
          issue: "test_015's pre-step gap (`sleep 4` before `step_start=$(date +%s)` at line 513, a 13-line span) relies entirely on the wall-clock cost of two `pgrep -P` forks + one `ps -o args=` fork + conditionals as its only margin beyond the raw `sleep 4` — and `sleep 4` alone is EXACTLY the conservative-model minimum this same PR just proved insufficient with zero slack elsewhere (test_006/013/017 all needed `sleep 6`, not `sleep 4`, for comfortable margin). The line's own comment ('comfortably beyond default GRACE(2)') is the SAME reasoning error the original defect family had (comparing only to GRACE, not to the full GRACE+truncation+quantization threshold this spec derives). The post-freeze audit's own awk (12-line window) structurally cannot see this site: sleep-to-capture distance here is 13 lines, one over the cutoff — reproduced independently below.",
          failure_scenario: "Under CI load where pgrep/ps fork overhead happens to be unusually small (fast container, warm cache) rather than the more common case where load INFLATES it, the true gap between p_pid's spawn and step_start capture could sit at or barely above 4s, which per this spec's own conservative-model derivation is the zero-slack boundary — producing an intermittent 'reaper failed to kill the matched launcher $p_pid' failure, the same failure category as the three sites just fixed in this PR (TEST-006/013/017), just not yet observed because it has not been stress-tested under load the way test_006 just was." }
    dispositions:
      - { finding: "tests/skills/test-aai-run-tests.sh:500 (test_015 thin pre-step margin)", recommended: "remediate-in-tree — same one-line `sleep N` widen + arithmetic/anti-tuning comment already established 3x in this PR (test_006/013/017), cheapest and most consistent option; alternatively promote to a named fast-follow ISSUE if the coordinator wants to keep this PR strictly scoped to the CI-confirmed failure. Orchestrator to record whichever is chosen." }
  cannot_verify:
    - { claim: "Spec-AC-05's repeated-CI-green evidence for the now-3-site fix", closes_with: "a push of the test_006/test_013 working-tree fix + the spec amendment, followed by >=2 green skill-suite CI runs; CI run 30004519613 already independently corroborates the test_006 half of the defect (failed exactly as described), which strengthens confidence the fix targets the right thing, but does not itself constitute the required repeated-green evidence" }
    - { claim: "Whether test_015's thin margin (sleep 4 + fork overhead) has ever actually flaked in CI", closes_with: "no direct evidence either way — CI run 30004519613 exited at test_006 (index 6 of 21) before reaching test_015 (index 15), since the suite exits on first failure; a future CI run with test_006/013 fixed would need to run clean through test_015 several times (or under artificial load) to positively confirm or refute the theoretical risk" }
  overall: pass
---

# Code Review (RE-REVIEW) — reaper-epoch-survivor-robustness (SPEC-0072 / ISSUE-0026)

Supersedes `docs/ai/reviews/review-dual-verdict-20260723T114559Z-reaper-epoch-survivor-robustness.md`
(kept, not deleted) — that PASS went stale when `test_006` failed on CI after
the review, revealing the intake's "test_017 is the only boundary-hugging
assertion" claim was false. This pass reviews the delta: the `test_006` /
`test_013` fixes and the SPEC-0072 post-freeze amendment.

## 1. Are the two new edits correct and consistent with the `test_017` precedent?

**Yes, both.**

- `test_006` (`tests/skills/test-aai-run-tests.sh:218-248`): the pre-step
  `old_pid`'s gap is now `sleep 6` (was `sleep 3`), with an inline comment
  (lines 225-235) stating the identical GRACE(2)+1s-truncation=3s /
  +1s-quantization=4s arithmetic as `test_017`'s comment, the same
  "flaked under CI load" citation (now pointing at the real PR #131
  observation instead of a hypothetical), and the same explicit
  "DO NOT NARROW... re-derive the slack from GRACE first" warning. It also
  adds a sentence `test_017`'s comment doesn't need: "Only the PRE-step side
  needs the margin — the fresh sibling below is spawned after step_start, so
  it is unambiguously post-boundary" — a correct, useful clarification (see
  §2).
- `test_013` (`tests/skills/test-aai-run-tests.sh:417-445`, the
  `command -v dash` epoch-extension block): same treatment — `sleep 6`,
  same arithmetic comment, same DO-NOT-NARROW language, plus a note that
  this branch "effectively ran on CI alone" (since it needs `dash`,
  typically absent on macOS dev hosts) — an honest, useful explanation for
  why this second zero-slack site never surfaced locally.

Both comments are consistent in structure and content with `test_017`'s
established precedent; no drift or shortcut in either.

## 2. `test_006` — did the post-step sibling assertion get weakened?

**No — verified untouched and still correctly positioned.** The edit is
scoped entirely to the `sleep 3 -> sleep 6` line and its preceding comment,
both of which sit BEFORE `step_start="$(date +%s)"` (line 239). The fresh
sibling (`fresh_pid`) is spawned at line 240, strictly AFTER `step_start` is
captured, and its assertion (line 246:
`alive "$fresh_pid" || log_fail "reaper killed a FRESH sibling..."`) is
byte-identical to before the edit. Since the widened sleep only extends the
time BEFORE `step_start`, it has zero effect on `fresh_pid`'s post-boundary
timing or on the "spare the post-boundary sibling" property. Confirmed by
running `bash tests/skills/test-aai-run-tests.sh 006` locally (PASS,
multiple runs).

## 3. `test_013` — is the edit in the right place, dash contract unchanged, non-dash path unaffected?

**Yes to all three.**

- **Right place**: the edit sits inside the epoch-path extension block
  (`tests/skills/test-aai-run-tests.sh:417-444`), which itself is nested
  inside `if command -v dash >/dev/null 2>&1; then` (line 402) — i.e., the
  SAME conditional the coordinator described, confirmed by reading the
  full function body end-to-end.
- **Dash invocation contract unchanged**: line 436 still reads
  `AAI_REAP_STEP_START_EPOCH="$step_start" dash "$REAP_SCRIPT" 2>"$err2"` —
  same interpreter, same env-var wiring, same stderr-capture pattern as
  before the edit; the widened sleep is the only change in this span.
- **Non-dash path unaffected**: the `else` branch (line 446-448,
  `log_pass "reaper contains no bash-only [[ ]] in code (W1); dash absent..."`)
  is untouched — confirmed via diff (no hunk touches those lines) and via
  the static guard above the `if` (lines 393-395), which also runs
  unconditionally and is untouched.

## 4. Independent re-audit — did the coordinator's signature search MISS anything?

**Yes — one related site, `test_015` (line 500), structurally excluded by the
audit's own 12-line window, not by design.**

Re-ran the coordinator's exact awk against the CURRENT file (with the
`sleep 6` fixes already applied) to confirm it now finds only the 3 expected
sites:
```
$ awk '/sleep [0-9]+/ {s=$0; gsub(/[^0-9]/,"",s); pend=s; pl=NR}
       /step_start="\$\(date \+%s\)"/ && pend!="" && NR-pl<=12 {print pl": sleep "pend; pend=""}' \
  tests/skills/test-aai-run-tests.sh
236: sleep 6
430: sleep 6
582: sleep 6
```
Then re-ran WITHOUT the 12-line cutoff to see everything the window
excludes:
```
236: sleep 6 -> step_start at 239 (gap 3 lines)
430: sleep 6 -> step_start at 431 (gap 1 lines)
500: sleep 4  -> step_start at 513 (gap 13 lines)   # test_015 — MISSED, 1 line over cutoff
519: sleep 1 -> step_start at 546 (gap 27 lines)     # test_016 — false pairing, not a real site (see below)
582: sleep 6 -> step_start at 583 (gap 1 lines)
```
Independently walked every one of the file's 5 `step_start="$(date +%s)"`
sites by hand (grep `step_start=` -> lines 239, 431, 513, 546, 583, plus
`test_021`'s 2 arithmetic-derived `step_start=$((...))` assignments which
need no real-time margin at all and were already reviewed in the prior
pass):

- **Line 513 (`test_015`, function starts 492)**: `old`-tree processes
  (`p_pid`, `o_pid`) are spawned, then `sleep 4` (line 500, comment:
  "comfortably beyond default GRACE(2)"), then TWO `pgrep -P` forks, ONE
  `ps -o args=` fork, and conditionals (lines 502-509), THEN `step_start` is
  captured (line 513). `p_pid` is later asserted REAPED (line 520). This
  matches the SAME underlying risk model as the three fixed sites — a
  pre-step gap feeding an epoch-mode REAP assertion — but does NOT match the
  audit's literal signature ("`sleep N` **immediately** preceding" the
  capture), because of the intervening pgrep/ps calls, AND those calls
  provide real (if unquantified) positive margin beyond the raw `sleep 4`
  that the three broken sites never had (their `sleep 3` was followed
  directly by the `date +%s` capture on the very next line, with no
  intervening fork). This is why it is a NON-BLOCKING finding, not a
  confirmed defect — see the structured finding above for the precise
  arithmetic and failure scenario.
- **Line 546 (`test_016`)**: a false pairing from the naive awk (the
  preceding `sleep 1` at line 519 belongs to a DIFFERENT, already-completed
  test — `test_014`'s regression check — not to `test_016`). `test_016`
  itself has NO pre-step `old_pid` at all: it captures `step_start`
  FIRST (line 546, inside a `for delay in 0 7` loop), THEN spawns
  `fresh_pid` (line 547), THEN sleeps `$delay` — the opposite order from the
  defect pattern, and it asserts the fresh sibling is SPARED, not that an
  old one is reaped. Confirmed not a real site.
- **Lines 239, 431, 583**: the three sites now fixed with `sleep 6` (see
  §1-3, and the prior review for `test_017`/583).

**Conclusion**: the audit's 3-site list is complete FOR THE SIGNATURE AS
DEFINED (bare `sleep N` immediately before the capture) — no other bare
sleep-then-capture pair remains under 6s anywhere in the file. But the
signature itself is narrower than "every pre-step gap in the suite," and
`test_015` is a genuine, related, currently-unaudited site that the amended
Spec-AC-01's literal "EVERY pre-step gap" wording does not actually cover.
Recorded as a NON-BLOCKING finding with a disposition recommendation (see
structured block), not a BLOCKING one — it has no confirmed CI occurrence
(CI run 30004519613 exited at `test_006`, index 6, before ever reaching
`test_015`, index 15, since the suite exits on first failure) and it does
carry real, if thin and undocumented, positive margin from subprocess-fork
overhead that the three now-fixed sites never had.

## 5. Reaper unchanged / no protected path / no retry loop

- `.aai/scripts/aai-reap-tests.sh`: `git diff --stat main...HEAD --
  .aai/scripts/aai-reap-tests.sh` and the working-tree equivalent both
  empty. `GRACE=2` confirmed intact.
- Full changed-file list (`git diff --name-only main...HEAD` +
  `git diff --name-only`): `CHANGELOG.md`, `docs/INDEX.md`,
  `docs/ai/EVENTS.jsonl`, `docs/ai/reviews/*` (this review's own artifacts),
  `docs/issues/ISSUE-0026-*.md`, `docs/specs/SPEC-0072-*.md`,
  `tests/skills/test-aai-run-tests.sh`. None intersect
  `protected_paths_l3` (`.aai/scripts/state.mjs`,
  `.aai/scripts/lib/state-engine.mjs`, `.aai/scripts/lib/state-core.mjs`,
  `.aai/scripts/allocate-doc-number.mjs`,
  `.aai/scripts/pre-commit-checks.sh`, `.aai/scripts/pre-commit-checks.ps1`,
  `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`).
- No retry/loop-until-pass in either edit: both `test_006` and `test_013`
  invoke the reaper exactly once per case and assert directly, same as
  before.

## 6. Is the post-freeze amendment honest and adequate — or does it warrant a separate work item?

**Honest: yes, unambiguously.** The "Scope extension (post-freeze,
2026-07-23)" section plainly states the original claim was false, names the
falsifying CI evidence, shows the actual audit command used, and records a
generalizable lesson ("must be audited by signature... never fixed one
reported site at a time"). This is exactly the transparency the spec
template's honest-amendment convention calls for — no scope creep is hidden,
no claim is inflated beyond what was checked.

**Adequate: mostly, with one gap now surfaced.** The amendment's own stated
signature (bare `sleep N` immediately before the capture) was audited
completely and correctly for that signature. But the broadened Spec-AC-01
row's plain-English claim — "EVERY pre-step gap ... widened" — reads as a
stronger, file-wide guarantee than what was actually checked, and §4 above
shows a real (if lower-confidence) 4th site sitting just outside the audit
tool's own window. This isn't dishonesty — the amendment is transparent
about its method — but the METHOD had a blind spot that a `NR-pl<=12`
literal-search cannot see, and "EVERY" is a claim that comment can't back
without also examining the (much smaller) set of pre-step-gap sites that
don't match the literal grep. Recommend either finding-remediation
(cheapest — extend the same `sleep 6` + comment pattern to `test_015`, still
inside this same PR) or softening AC-01's wording to name its actual
scope ("every site matching the audited signature") plus filing `test_015`
explicitly as a fast-follow, rather than leaving it implicitly covered by an
"every" that a literal reading contradicts.

**Separate work item: no, not warranted, for either the amendment already
made OR (if chosen) the `test_015` follow-up.** All of this — the 2
newly-fixed sites, and the 1 additionally-flagged site — is the SAME
single file, the SAME defect family, the SAME one-line-`sleep`-plus-comment
fix shape, reversible, no protected surface, no new mechanism. Re-litigating
through a fresh intake/spec cycle for what is fundamentally "the same fix,
applied to 1-2 more call sites in the file already in scope" would be
disproportionate ceremony for a ceremony_level-1, single-file, test-fixture
change. The honest-amendment pattern already used is the right tool for
this; it should simply be used once more (or explicitly deferred with a
named follow-up ref) for `test_015` rather than silently left uncovered by
an overclaiming "every."

## Evidence log
```
$ git diff --stat -- .aai/scripts/aai-reap-tests.sh
(empty)
$ git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh
(empty)

$ bash tests/skills/test-aai-run-tests.sh 006 013 015 017 021
... 5/5 PASS (repeated 3x total, all green; one repeat run hit the review
    harness's own 2-min timeout mid-3rd-iteration, not a test failure)

$ bash tests/skills/test-aai-run-tests.sh   # full 21/21
PASS: All selected aai-run-tests tests passed

$ node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md
LINT PASS: no structural findings.

$ node .aai/scripts/docs-audit.mjs --gate spec-reaper-epoch-survivor-robustness
GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).

$ gh run list --workflow skill-suite.yml --branch fix/reaper-epoch-survivor-robustness --limit 10
30004519613  FAILURE  11:48:30Z   <- test_006 failure confirmed (see below)
30002328595  FAILURE  11:13:42Z   <- pre-dates test_006/013 fix; aai-run-tests job itself passed
30002216044  FAILURE  11:11:56Z   <- same as above

$ gh run view 30004519613 --log | grep -E "aai-run-tests|TEST-006|reaper failed"
[30/42] aai-run-tests        FAIL (21.0s)
15:FAIL: reaper failed to reap the pre-step matching proc 136983
INFO: TEST-006: epoch guard — a post-step-boundary matching proc is NOT reaped; a pre-step one IS...
FAIL: reaper failed to reap the pre-step matching proc 136983
```

## Next steps
- Coordinator to decide + record disposition on the `test_015` NON-BLOCKING
  finding (remediate-in-tree now, or file a named fast-follow ISSUE) per the
  H6 warnings-with-teeth policy.
- Commit + push the `test_006`/`test_013` fix (and `test_015`'s, if chosen)
  so a fresh CI run can produce the Spec-AC-05 repeated-green evidence.
