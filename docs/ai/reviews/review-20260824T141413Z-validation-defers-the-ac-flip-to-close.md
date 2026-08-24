# Code Review — validation-defers-the-ac-flip-to-close

```yaml
review:
  scope: "528d1d6..01cf8a3 (docs/ac-flip-belongs-to-close)"
  spec: docs/specs/SPEC-0151-spec-validation-defers-the-ac-flip-to-close.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/VALIDATION.prompt.md:203 — AC-FLIP DEFERRAL rule; grep -c \"EXCEPTION:\" .aai/VALIDATION.prompt.md == 0 (reproduced)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/SKILL_PR.prompt.md:224 (FLIP THE AC TABLE FIRST) precedes :231 (close-work-item.mjs --ref); TEST-050 pins the ordering" }
      - { ac: Spec-AC-03, call: compliant, citation: "independently re-measured: base(528d1d6)=312564B, head=313693B, delta=1129B; TEST-010 headroom 0/2048; TEST-012 pin=1036=independent re-sum; no duplication (grep table below)" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-050 in tests/skills/test-aai-close-work-item.sh:2329; mutation bite independently reproduced in a disposable detached worktree (real exit code 1, not piped)" }
      - { ac: Spec-AC-05, call: compliant, citation: "git diff 528d1d6..HEAD --name-only over docs-audit.mjs/lib//close-work-item.mjs/test-aai-doc-numbering.sh is empty; test-aai-doc-numbering.sh 31/31 PASS" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "The MECHANICAL CHECKS carve stays decidable if a future change edits docs-audit-core.mjs's Rule-1 reason string (\"is non-terminal (status ...)\")", closes_with: "no test pins that exact substring against the VALIDATION.prompt.md carve's assumption; would need a golden-string test wiring the two files together (out of this scope's stated deliverables)" }
  overall: pass
```

## Scope and method

Base `main` @ `528d1d6`, head `01cf8a3` (2 commits: `c3d9f7d` round-1 remediation,
`01cf8a3` round-2 remediation). Diff: `.aai/VALIDATION.prompt.md`,
`.aai/SKILL_PR.prompt.md`, `tests/skills/test-aai-close-work-item.sh`,
`tests/skills/test-aai-prompt-diet.sh`, `tests/skills/lib/prompt-diet-ledger.sh`,
plus the two intake docs and generated INDEX/EVENTS/overview artifacts.

Two validation rounds already ran and are not re-litigated here except where
independent reproduction was needed to trust a claim as *this diff's* property
rather than the reports' say-so. Round 1 filed and closed `fu-ac-flip-gate-timing-contradiction`
(P1); round 2 filed and closed `fu-test012-message-stale-859` (P2). Both
fixes are in this head. This review re-derived the load-bearing numbers itself
rather than trusting either report, per the anti-gaming contract.

## Attack 1 — the carve as prose that must be executed

Ran the gate live against this scope's own (still-`implementing`) spec and
against a recently-closed one, to see both printed shapes directly rather than
trust the reports' pasted output:

```
$ node .aai/scripts/docs-audit.mjs --gate spec-validation-defers-the-ac-flip-to-close
GATE FAIL — the AC Status table is not reconciled:
- Spec-AC-01 is non-terminal (status "implementing")
...
exit 1

$ node .aai/scripts/docs-audit.mjs --gate spec-the-tripwire-is-permanent-not-transitional
GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).
exit 0
```

Traced the actual reason strings in `.aai/scripts/lib/docs-audit-core.mjs`
`gateContent()` (lines 1626-1692): Rule-1 non-terminal rows print
`` `${specAc} is non-terminal (status "...")` ``, structurally distinct from
Rule 2 (`is done but Evidence is empty`), Rule 4 (`has schema-invalid
Review-By`), and the structural reasons (`missing AC Status table`, lean-shape
variants, unparseable-row). No overlap exists among these four shapes today,
so "every printed reason is a Rule-1 non-terminal row" is decidable from the
current output, and the carve's own worked example (round 2 Check 1) matches
what this review reproduced independently.

The one real gap: nothing pins that exact substring to the prose carve. If a
future change to `docs-audit-core.mjs` reworded the Rule-1 reason (e.g. to
drop "non-terminal"), nothing would fail loudly — an LLM validator would still
likely re-derive the mapping from the Rule-1 prose description one paragraph
above (it isn't a literal grep in the validator's own execution, only in
`test_050`'s canon-wiring pin), but no test enforces that continuity. This is
a pre-existing structural property of the whole MECHANICAL CHECKS section
(it already relied on prose describing script output before this diff); this
diff adds one more sentence riding the same coupling, it does not introduce a
new one. Recorded as `cannot_verify` above, not a finding — no bite observed,
and filing a P3/no-bite assurance concern is exactly what the registry policy
says stays out of the tracker.

## Attack 2 — the two prompts as a pair

Traced every case where 8a's "already-done doc (re-validation) moves an AC
terminal here" branch and 5c's "flip every row terminal" step could apply to
the same doc in the same moment:

- **Already-done doc reached by both rules in one ride.** 5c's flip bullet is
  unconditional prose ("set every Spec-AC row ... terminal"), so if the ride's
  own doc were already done and fully terminal (the case 8a's tail branch
  covers), 5c's instruction is a no-op restatement of already-true state —
  idempotent, not contradictory. `close-work-item.mjs` itself documents the
  same idempotency for its own invocation ("Exit 0 = closed (or already closed
  — idempotent)").
- **`ac_evidence` emission granularity.** 8a's re-validation branch emits a
  per-`Spec-AC` ref (`SPEC-XXXX/Spec-AC-YY`); `close-work-item.mjs`'s internal
  emission (`close-work-item.mjs:1232`) is per-doc (`fmId`). Checked
  `falseOpenEvidence()`'s `idRef()` matcher (`docs-audit-core.mjs:497`): both
  granularities satisfy the same `ref === cand || ref.startsWith(cand + '/')`
  test, by design predating this diff (the D2(b) comment cites "same roll-up
  boundary as probable-false-done"). Not a new inconsistency.
- **"immediately before `close-work-item.mjs`" for "the deferred emission."**
  8a says the flip *and* the emission happen "at the close ceremony,
  immediately before `close-work-item.mjs`." The flip is literally a separate,
  prior bullet in 5c. The emission is not hand-run before the script — it is
  emitted *by* the script itself (`needsAcEvidence` branch,
  `close-work-item.mjs:1232`), i.e. during, not strictly before, the
  invocation. Functionally correct (the emission happens, at the right time,
  automatically), but the sentence's "immediately before" reads as applying to
  both actions when only the flip is literally pre-script. Wording-only,
  no functional gap, no failure scenario — below the finding bar.

No ride shape found where the two files' instructions actually conflict for
the same actor at the same moment.

## Attack 3 — `test_050` as shell

Ran the full suite under `/bin/bash` explicitly (not the default zsh):
`ALL TESTS PASSED`, including `test_050_ac_flip_deferral_canon`. Traced the
hazards named in the dispatch against the actual code:
- File is `set -euo pipefail` (line 80); `log_fail` calls `exit 1` directly —
  no bare `$?` after a pipe anywhere in `test_050`.
- The `grep -qF`/`if grep -qF ... ; then log_fail` calls run direct, not
  through `$(...)|head`.
- `flip_line=$(awk '/PATTERN/{print NR; exit}' "$SKILL_PR")`: on no match,
  `awk` reaches EOF without an explicit non-zero `exit`, so the substitution
  itself never fails `set -e`; the empty-string case is caught by
  `[[ -n "$flip_line" ]] || log_fail` before the `-lt` comparison. Independently
  reproduced (not trusted from the reports): built a disposable detached
  worktree at head, mutated `AC-FLIP DEFERRAL` -> `XYZ DEFERRAL`, ran the
  suite with output redirected to a file and read `$?` directly afterward
  (not piped) — real exit code **1**, `FAIL: t050: VALIDATION.prompt.md must
  carry the AC-FLIP DEFERRAL rule`. Worktree removed with a targeted
  `git worktree remove --force <path>` per HAZ-WORKTREE; `git worktree list`
  and `git status --porcelain` confirmed the real repo untouched.
- Vacuous pass on missing files ruled out: `check_deps()` (lines 109-115)
  `log_fail`s if either `$VALIDATION_PROMPT` or `$SKILL_PR` is absent, before
  `test_050` (or any test) runs.

## Attack 4 — the ledger and pin history as truth

Independently re-measured rather than trusting either validation report's
numbers:
```
base (528d1d6, disposable worktree)  .aai/*.prompt.md = 312564 B
head (01cf8a3, working tree)         .aai/*.prompt.md = 313693 B
delta = 1129 B
```
`bash tests/skills/test-aai-prompt-diet.sh`: 21/21 PASS. `TEST-010`: "strict
audit clean, net reduction 28672 bytes (headroom 0/2048)". `TEST-012`:
"JUSTIFIED_GROWTH_BYTES == 1036 == independent re-sum" (message strings now
interpolate `$want_growth` — the round-2 P2 fix, confirmed live, no stale
"859" anywhere in the PASS output).

The 177 B ledger entry's arithmetic: total scope delta 1129 B split into the
implementation's 815 B (fit inside the prior 952 B headroom, correctly no
ledger entry per round 1) and round-1's own remediation contributing a
further 314 B against a remaining 137 B headroom, i.e. a **177 B deficit**
(314 − 137), matching the ledger's own stated convention ("deficit, not raw
growth") used by every other entry in the file. No double-counting: the
817 B initial delta and the 177 B deficit are not both charged.

The pin-comment history paragraph is accurate but reads awkwardly at one
seam — a `then 859 -> 1036,` clause is spliced mid-sentence into the *old*
133→859 paragraph rather than getting its own sentence (`tests/skills/test-aai-prompt-diet.sh:415`
area). Truthful (no contradiction with the actual numbers, which are all
independently confirmed above), just clumsy prose. Not a finding — no bite,
nothing misleading in effect, below even the P3/accepted-residual bar (that
bar is for assurance-strength gaps, not typography).

No cross-file rule-sentence duplication: `AC-FLIP DEFERRAL` appears twice in
`VALIDATION.prompt.md` (the rule statement + the MECHANICAL CHECKS
forward-pointer, same file) and zero times in `SKILL_PR.prompt.md`;
`FLIP THE AC TABLE` appears once in `SKILL_PR.prompt.md` and zero times in
`VALIDATION.prompt.md` — each file names the other by pointer, never copies
its rule text.

## Attack 5 — the disposition record

`docs/ai/decisions.jsonl` (verified append-only: `git diff` shows only
trailing `+` lines) carries both findings filed and both closed:
- `fu-ac-flip-gate-timing-contradiction` (P1, round 1) → `follow_up_status:
  done`, `resolved_by: validation-defers-the-ac-flip-to-close`, resolution
  text matches the actual fix (MECHANICAL CHECKS carve + ledger entry).
- `fu-test012-message-stale-859` (P2, round 2) → `follow_up_status: done`,
  same ride, resolution text matches the actual fix (constant
  interpolation, confirmed live above).

Both bit (reproduced, not hypothetical) and both went through the tracked
registry (a) remediate path, not laundered as an "accepted residual." The
one item recorded as an accepted residual (round 1's Attack 2, the widened
carve-out's delayed-`EVENTS.jsonl`-visibility tradeoff for a stalled
numbered-but-open doc) has no observed bite and is disclosed in the spec's
own "Edge cases" note — correctly at disposition (d), not filed. Nothing
found that bit or lied and was recorded only as a residual.

## Test suites run (this review, independently)

| Command | Exit | Result |
|---|---|---|
| `/bin/bash tests/skills/test-aai-close-work-item.sh` | 0 | ALL TESTS PASSED, incl. TEST-050 |
| `/bin/bash tests/skills/test-aai-prompt-diet.sh` | 0 | 21/21 PASS, TEST-010 headroom 0/2048, TEST-012 == 1036 |
| `/bin/bash tests/skills/test-aai-doc-numbering.sh` | 0 | 31/31 PASS |
| `node .aai/scripts/check-test-registration.mjs` | 0 | clean |
| `node .aai/scripts/docs-audit.mjs --gate spec-validation-defers-the-ac-flip-to-close` | 1 | GATE FAIL, all 5 rows Rule-1 (expected — this scope's own dogfooding of its own new rule) |
| `node .aai/scripts/docs-audit.mjs --gate spec-the-tripwire-is-permanent-not-transitional` | 0 | GATE PASS (comparison shape) |
| Mutation bite in disposable worktree (real, un-piped exit code) | 1 | `FAIL: t050: VALIDATION.prompt.md must carry the AC-FLIP DEFERRAL rule` |

## Standing-hazards compliance

- HAZ-RESTORE: no `git checkout --`/`restore`/`stash`/`reset --hard` used on
  any tracked file; all mutation was inside disposable detached worktrees.
- HAZ-SCRATCH: both worktrees created under the dispatch's scratch root
  (`.../9a8e6960-b8be-4819-a998-725da0d91525/scratchpad/`).
- HAZ-CD: no `cd` performed into an unverified path; all commands used
  explicit absolute paths or `-C`/`git -C`.
- HAZ-LEDGER: no ledger writes made by this review (read-only reviewer per
  the anti-gaming contract); confirmed `docs/ai/EVENTS.jsonl` and
  `docs/ai/decisions.jsonl` diffs are trailing-append-only.
- HAZ-WORKTREE: both scratch worktrees removed with targeted
  `git worktree remove --force <path>`; `git worktree list` confirms only
  the real repo remains.

## Verdict

**PASS**, both verdicts. Spec-AC-01..05 verified compliant with independent
re-derivation (not trusting either validation report's numbers or reproduced
output verbatim). No BLOCKING or NON-BLOCKING code-quality findings — the
one open item is a `cannot_verify` (future-drift decidability of the carve's
reason-string matching), which has no observed bite and is exactly the shape
the registry policy keeps out of the tracker. No new registry findings filed
by this review.
