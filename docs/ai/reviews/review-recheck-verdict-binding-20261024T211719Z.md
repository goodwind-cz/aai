# Code Review r1 — recheck-verdict-binding (59ee0ff2..f79fa2dc)

Intended tracked path: `docs/ai/reviews/review-recheck-verdict-binding-20261024T211719Z.md`

```yaml
review:
  scope: 59ee0ff2..f79fa2dc (intake 9981130b, spec 5d0673d6, D13 fold bbc91eb7, code 54452c56, docs d8dd2e37, SPEC-0250 amendment+close db851576, default flip f79fa2dc)
  spec: docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md (L3)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "check-binding.mjs:461-483, state.mjs:586-611, TEST-2801/2802 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "check-binding.mjs:485-509, TEST-2803/2804 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "recheck.mjs:245-255 (no check_ read), check-binding.mjs:378-397, TEST-2805/2806" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2807..2813 green under delta and default env" }
      - { ac: Spec-AC-05, call: compliant, citation: "metrics-flush.mjs:921,1008; check-binding.mjs:517-534; TEST-2814/2815" }
      - { ac: Spec-AC-06, call: compliant, citation: "orchestration-dispatch.mjs:1727-1751, canon.mjs:486, TEST-2816 (AAI_HARNESS pinned via cleanEnv)" }
      - { ac: Spec-AC-07, call: compliant, citation: "check-role-output.mjs:248-253,966-973; ORCHESTRATION 45 lines; TEST-2817" }
      - { ac: Spec-AC-08, call: compliant, citation: "recheck.mjs:182-186, TEST-2818" }
      - { ac: Spec-AC-09, call: compliant, citation: "state.mjs:593, TEST-2802; probe C (AAI_ROLE=orchestrator) rc 3" }
      - { ac: Spec-AC-10, call: compliant, citation: "SUBAGENT_PROTOCOL.md:58-72, WORKFLOW.md:68, CHANGELOG.md:25-44, TEST-2819 (literal checks pass; see B-2 for content)" }
      - { ac: Spec-AC-11, call: compliant, citation: "recheck.mjs:127-136, TEST-2820/2821; revert path db851576 suite rc 0" }
      - { ac: Spec-AC-12, call: compliant, citation: "PROFILES.yaml:174, suite-map.yaml aai-recheck, diet +309 = glob 371301-370992, TEST-2822..2824" }
      - { ac: Spec-AC-13, call: compliant, citation: "RFC-0017 row 4 links; TEST-2825 (row text stale, B-2a)" }
      - { ac: Spec-AC-14, call: compliant, citation: "decisions.jsonl 15 classification records, TEST-2826" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2827" }
      - { ac: Spec-AC-16, call: compliant, citation: "SPEC-0250 D4/TEST-2742 row, amendment 19:48:46Z tracked_by fu-amend-cheap-transitions-slice-090b38, spec-amend list --strict rc 0, TEST-2828" }
      - { ac: Spec-AC-17, call: compliant, citation: "check-binding.mjs:104-140, TEST-2829/2830" }
      - { ac: Spec-AC-18, call: compliant, citation: "recheck.mjs:390-401, TEST-2831/2832 (tested path); deviation: block-replacement path re-records spec_path, see B-1/B-3" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/lib/check-binding.mjs, line: 466,
          issue: "Any block replacement (another ref, another checkout, a parse problem) starts a fresh block with security_sticky false and re-records spec_path, so a ride's earlier security_relevant true is forgotten after one re-bound round; the spec Risks line (SPEC-DRAFT:637) says those rounds run full",
          failure_scenario: "Probe A3, state.mjs only: round 1 bound true; set-focus --ref hotfix-two; one --confirm dispatch tick; set-focus back; round 2 dispatch + set-validation fail --evidence new.md (marker false) + verdict bind; test-only change -> recheckMode Validation mode delta, reasons []" }
      - { rank: BLOCKING, file: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md, line: 307,
          issue: "Wording: false or overclaiming statements after the flip (RFC row says delta stays opt-in; CHANGELOG #498 entry line 58 says the mode is OPT-IN in present tense in the same [unreleased] section; CHANGELOG:38 'the first re-check round of every install after /aai-update can run on the slim payload'; SUBAGENT_PROTOCOL.md:65 states provenance ('the block was written in this checkout', 'no later dispatch of the role lacks a verdict') instead of the comparison",
          failure_scenario: "A reader of the RFC or of the cut release notes is told delta is opt-in while every install now runs it by default; a reader of the protocol is told a copied STATE cannot pass, while only the recorded checkout string is compared, and a dispatch made outside a --confirm tick records no pending head" }
      - { rank: BLOCKING, file: tests/skills/lib/recheck.test.mjs, line: 2314,
          issue: "TEST-2831 title (and test-aai-recheck.sh:356 pass line) claims a universal negative: 're-pointing STATE spec_path at a lower-level spec cannot lower the ceremony level'; it asserts only the same-block path",
          failure_scenario: "Probe B: L3 spec bound; focus switched to another ref and back with spec_path pointed at an L2 spec; one full round binds the new path; test-only change -> recheckMode delta with no ceremony_l3" }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 593,
          issue: "bind-check refuses any non-empty AAI_ROLE, but SUBAGENT_PROTOCOL.md:43 (ENV row) lets the orchestrator keep AAI_ROLE set to a non-subagent value; orchestration-dispatch.mjs:490-498 swallows the refusal",
          failure_scenario: "An orchestrator running with AAI_ROLE=orchestrator never writes a binding; every re-check round is full with first_round and nothing says why (safe direction, lost function)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/check-binding.mjs, line: 6,
          issue: "Comment premise 'STATE is gitignored, so no commit, amend, rebase, squash, merge or replace object carries the block' is not checked; aai-sync.sh:887 only warns when STATE is still tracked downstream",
          failure_scenario: "A downstream install that still tracks docs/ai/STATE.yaml: git checkout -- docs/ai/STATE.yaml (or a rebase) restores an older block with security_sticky false in the same checkout path; the comparisons accept it (effect is inside the D9 residual, the premise sentence is not)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-recheck.sh, line: 239,
          issue: "Stale names after the flip: test_2738_default_is_full now asserts the default is delta; recheck.test.mjs:7-10 header still says delta is opt-in",
          failure_scenario: "A reader or a selector by name learns the opposite of what the test asserts" }
  cannot_verify:
    - { claim: "A live ride's delta round after the flip behaves as the fixtures do", closes_with: "the first post-merge ride with an eligible round (D12 says none in this slice)" }
    - { claim: "Stored RED logs show delta on 59ee0ff2 for D5 shapes 1-8 and 10", closes_with: "Validation's replay on the base commit (I read the logs' existence, not their re-run)" }
    - { claim: "SPEC-0250 mutation gate", closes_with: "the #498 records are gitignored and absent; mutation-gate --spec SPEC-0250 rc 5 for 8 rows here, expected per D10" }
    - { claim: "Linux CI and a STATE-less clean clone", closes_with: "PR CI run; test-aai-state.sh exits 42 at a pre-existing log_skip in a STATE-less clone (passes rc 0 with a seeded STATE)" }
    - { claim: "Windows core.autocrlf ledger_rewritten behavior", closes_with: "native Windows run (carried from #498)" }
    - { claim: "Full sweep", closes_with: "the validator's sweep in /private/tmp/aai-recheck-binding" }
  overall: fail
```

security_relevant: true

## Scope and preflight

- Scope: `59ee0ff2..f79fa2dc` (seven commits), branch `change/recheck-verdict-binding`, worktree `/private/tmp/aai-recheck-binding` (`worktree.user_decision: worktree`). Reviewed in a scratch clone checked out at `f79fa2dc`, plus a second clone at `db851576` for the revert path. The worktree was not written.
- Spec: `docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md` (L3, frozen, amended D13 and D14).
- `AAI_RECHECK_MODE=full` was exported for every run of mine, so this round ran on the full payload. The spec probes set the variable explicitly where they test the default.
- Coaching check: the dispatch named focus areas and asked for overclaims to be ranked BLOCKING, which is the owner's standing instruction for this ride. I reviewed the full scope regardless.

## Evidence I ran

| Command | rc |
|---|---|
| `env -u AAI_ROLE AAI_RECHECK_MODE=full bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-recheck.sh` at f79fa2dc | 0 |
| same at db851576 (the revert path of D7) | 0 |
| test-aai-prompt-diet.sh, test-aai-role-output.sh | 0, 0 |
| test-aai-state.sh (clone with STATE seeded from template; without STATE it stops at a pre-existing `log_skip`, rc 42) | 0 |
| `node .aai/scripts/spec-amend.mjs list --strict` (rc read directly) | 0 |
| `node .aai/scripts/check-test-registration.mjs tests/skills` | 0 |
| `node .aai/scripts/spec-lint.mjs --path <spec>` | 0 findings |
| `node .aai/scripts/canon.mjs claims` | 0 |
| `mutation-gate.mjs --spec <this spec>` on copied evidence | GATE PASS 32 rows |
| `wc -l .aai/ORCHESTRATION.prompt.md` | 45 |
| `.aai/*.prompt.md` glob: f79fa2dc 371301, 59ee0ff2 370992 | +309 = the ledger credit |
| Probes A, A3, B, C (node:test cases in a scratch copy, below) | see findings |

## Focus 1: the binding trust model

- **Writer.** Only `state.mjs bind-check` writes the block (`cmdBindCheck`, state.mjs:588). It takes no head, report, digest or marker from its caller: `planBindCheck` reads STATE, the files STATE names, and git. `BIND_ROLE_GUARD` refuses any non-empty `AAI_ROLE` before STATE is read (state.mjs:593), whatever the `--state` path. Probe C (`AAI_ROLE=orchestrator`) gave rc 3, as TEST-2802 does for `subagent`, a space and a tab.
- **check-role-output.** `bind-check` is not in `STATE_UPDATE_SUBCOMMANDS` or in any role's set (check-role-output.mjs:507-518), so a returned `state.mjs bind-check` fails with E-STATE-UPDATE-COMMAND. INFO: the Validation role may still return `orchestration-dispatch.mjs --human --confirm` (check-role-output.mjs:536-538). That tick now runs `bind-check` in orchestrator context. This is harmless: the values come from STATE, and the effect equals the orchestrator's next tick. The protocol sentence is accurate for the direct form only.
- **Checkout.** `checkout` is the realpath of `git rev-parse --show-toplevel`, compared to the same value for the root being decided (check-binding.mjs:385). It compares a path string, nothing more (see B-2d).
- **Report digests.** These are the sha256 of each bound report at bind time. A bind with an unreadable report writes nothing (line 506). An edit or deletion after the bind gives `binding_report_changed` (TEST-2805, TEST-2813).
- **Sticky security flag.** The flag is never lowered inside one block (line 494), and the partial flush keeps it (line 522). It is lost on every block replacement: **B-1**.
- **GIT_* and replace refs.** `gitEnv()` drops every inherited `GIT_*` variable and sets `GIT_NO_REPLACE_OBJECTS=1`. All recheck and binding git calls go through `gitOut`/`gitBytes`, and no other `execFileSync` remains in recheck.mjs. `refs/replace/` and `info/grafts` give `replace_refs_present`, and git failing to answer gives the same reason. TEST-2810 covers the object replace, the graft, `GIT_REPLACE_REF_BASE` and grafts.
- **D14 `ownDispatch`.** I find this benign. The exception applies only to a pending list of exactly one head that equals the current HEAD, only in canon. The base stays the last *bound* head. Take shape 10 at the same head (a crashed check followed by a re-record): canon would build a delta from the last real verdict, which is exactly the delta the dispatched round would have judged. The re-record still binds nothing, and the tick's own decision keeps `binding_pending`. A commit between the tick and the build makes the head differ, so canon gives exit 11 and the round runs full. It cannot hide a pending check that would move the base.

## Focus 2: default flip safety

| Binding state | Result |
|---|---|
| No block | `first_round` |
| Partial or malformed block | `binding_ambiguous` |
| Block of another ref | `first_round` |
| Pending dispatch | `binding_pending` |
| Handoff to a worktree | No block, `first_round` (TEST-2814) |
| Partial flush | Verdicts cleared, `first_round` (TEST-2815) |
| Full flush | Block removed |
| merge-cleanup | Archives the block; it is never read |
| Dispatch without `--confirm` | Nothing pending is recorded and nothing is bound, so the base stays the older bound head (more delta, safe) |
| `AAI_RECHECK_MODE` misspelt | `recheck_disabled` |
| Escalation without `--recheck-mode` | An ordinary BLOCKED, which stops the ride (safe) |

The revert path also holds: `db851576` (= `git revert f79fa2dc`) passes the recheck suite, and TEST-2820/2821 leave with the flip commit. **The exception is B-1**: once a block has been replaced, the flag and the recorded spec path no longer carry the ride's history, and the default-on mode then gives delta.

## Findings

### B-1 BLOCKING: block replacement forgets `security_sticky` (and the recorded spec path)

**Where.** check-binding.mjs:466-468 (`usable` requires the same ref and the same checkout) and 405-413 (`carry` on an empty prior). The prior block is dropped whole, `securitySticky` restarts at false, and `specPath` is re-read from the current STATE.

**Probe A3** (scratch copy of recheck.test.mjs; the switch uses only `state.mjs set-focus`, `set-validation` and `bind-check`, with no hand edit):
```
r1 sticky= true
set-focus away rc= 0 ; dispatch bind for hotfix-two
set-focus back rc= 0 ; dispatch bind, set-validation fail --evidence VALIDATION-t2.md (false), verdict bind
after r2 block= {... "security_sticky":"false", "validation_security":"false" ...}
PROBE-A3 mode= delta reasons=
```
**Probe B**: an L3 spec is bound, the focus moves away and back, and `spec_path` now names an L2 spec. One full round binds the L2 path, and the next round gives `delta` with no `ceremony_l3`. In my fixture the work item `spec_path` was changed by hand, which the D9 residual covers. Through `set-focus --spec_path` alone, the same result needs a work item that has no `spec_path`.

**Why it matters.**
- Under SPEC-0250 the earlier `true` kept every later round full. The RECHECK_DELTA and Code Review prompts rely on "once any report of the ref says true, every later report says true", but `set-validation --evidence` replaced the evidence list, so the true report is no longer among the prior reports. Nothing carries the `true` forward.
- The same loss follows a worktree handoff (D6 only says the first round is full) and a moved checkout.
- The spec's Risks line (SPEC-DRAFT:637), "two scopes that alternate in one STATE replace each other's binding, so their rounds run full", understates this: once the alternation stops, the round after the next bind runs delta with the `true` forgotten.
- This is a shape found now, and it is reachable without tampering. The owner's condition ("every known shape gives full") is therefore not met.

**Remedy (Implementation's choice).** Options:
- Keep a per-ref sticky record that survives replacement, for example a `sticky_refs` list that only the full flush removes, and treat the recorded spec path the same way.
- Or refuse delta with a named reason for any block that replaced a block whose sticky was true.

Add the A3 shape as a test, and correct the Risks line.

### B-2 BLOCKING: wording that no longer states what is true, or does not state what is compared

- (a) RFC-0017:307, row 4: "delta stays opt-in until that comparison is proven". This is false at f79fa2dc. TEST-2825 checks only the links.
- (b) CHANGELOG.md:58-60, the #498 entry in the same `[unreleased]` section: "The mode is OPT-IN: it applies only when `AAI_RECHECK_MODE` normalises to `delta`; unset, empty and every other value give full". This is present tense and false after the flip. The release cut publishes both entries side by side. The first-bullet parenthetical does not cover this sentence.
- (c) CHANGELOG.md:38: "the first re-check round of every install after `/aai-update` can run on the slim payload". A ride in flight at update time has no block, so its round gives `first_round`. Only a round that follows a round bound after the update can run delta. The second half of the same sentence contradicts the first.
- (d) SUBAGENT_PROTOCOL.md:65 says "the block was written in this checkout (`binding_other_checkout`)". What is compared is the recorded `checkout` string against the realpath of the current toplevel. The same line says "no later dispatch of the role lacks a verdict (`binding_pending` ...)". What is compared is that `<role>_pending_heads` is empty, and a dispatch made outside a `--confirm` tick records nothing. Under D9 these must name the comparison.

### B-3 BLOCKING: TEST-2831 names a universal negative

The title at recheck.test.mjs:2314 reads "re-pointing STATE spec_path at a lower-level spec cannot lower the ceremony level", and the pass line at test-aai-recheck.sh:356 says "cannot lower". The test asserts only the same-block path, and Probe B is a counterexample. Rename it to the path it asserts, or prove the negative once B-1 is fixed. Note that `fu-recheck-specpath-repoint-gives-delta` was closed done while this path stays open.

### NB-1 (P3): the AAI_ROLE posture does not match the ENV row

SUBAGENT_PROTOCOL.md:43 allows the orchestrator to keep `AAI_ROLE` "set to a non-`subagent` value". `bind-check` refuses any non-empty value, and the dispatch swallows the failure. Such an orchestrator therefore never binds, and every round runs full with no diagnostic. This fails safe.

Recommended disposition: promote to a follow-up (suggested `fu-bind-check-role-posture-mismatch`). Either let the ENV row require unset, or have the tick print a one-line stderr notice when `bind-check` exits 3.

### NB-2 (P3): the "STATE is gitignored" premise is unchecked

check-binding.mjs:6-7 states this premise, and the spec's Problem section does too. aai-sync.sh:887 only warns when a downstream install still tracks STATE. In such an install git can restore an older block in the same checkout path. The effect falls inside the D9 residual, but no comparison checks the premise.

Recommended disposition: follow-up (suggested `fu-recheck-state-tracked-premise`). Add a `state_tracked` reason (`git ls-files --error-unmatch docs/ai/STATE.yaml`), or qualify the sentence.

### NB-3 (P3): stale test names after the flip

`test_2738_default_is_full` (test-aai-recheck.sh:239) now asserts that the default is delta. The header at recheck.test.mjs:7-10 says "delta is opt-in". The function name is a false record, so this is not eligible for disposition (d).

Recommended disposition: remediate in tree. Renaming needs a restamp of the SPEC-0250 TEST-2738 row and its mutation selector. Otherwise file a follow-up.

### INFO

- The SPEC-0250 binding-part mutation records (TEST-2705, 2706, 2734, 2735, 2742; run at 20:21Z with `base_commit: bbc91eb7`) carry recheck.mjs `target_sha256` `732a5093…`. That is the f79fa2dc blob (post-flip), not 54452c56 (`08ce5233…`). These tests pin `DELTA_ENV`, so the kills are unaffected. Still, the records were taken on a working tree that already held the flip, which is not the "binding proven, then flip" order D7 describes.
- I checked the amendment records against the diff:
  - 19:48:46Z: TEST-2705, 2706, 2734 and 2735 are re-anchored, and D4/D5/AC-16/TEST-2742 point at this spec. ✓
  - 20:28:12Z: the flip covers D1, AC-17, TEST-2731 and TEST-2738. ✓
  - 19:14:43Z (D13) and 19:48:47Z (D14) are both tracked by `fu-amend-spec-recheck-verdict-binding`. ✓
  - 20:21:07Z: the TEST-2818 measurement re-anchor. ✓
- The diet credit is exactly the measured growth: 77 + 230 + 1 + 1 = 309 B, and the TEST-012 pin moves 62785 to 63094. There is no padding. SUBAGENT_PROTOCOL.md and WORKFLOW.md are correctly left uncredited.
- Large JSON travels on stdout or stdin, never argv (TEST-2826/2823). `cleanEnv` and `unsetEnv` pin `AAI_HARNESS=claude` for every dispatch that compares routing.
- The six follow-ups are closed by code and test: escalation (TEST-2817), merge wording (the literal phrase is in all three files), the comment (TEST-2818), fenced marker (TEST-2829/2830), binding (TEST-2801..2816). Spec-path repoint (TEST-2831/2832) holds only on the same-block path; see B-3.

## Warning dispositions (H6)

- NB-1: recommend (b) follow-up `fu-bind-check-role-posture-mismatch` (P3).
- NB-2: recommend (b) follow-up `fu-recheck-state-tracked-premise` (P3).
- NB-3: recommend (a) remediate in tree, with a restamp of the SPEC-0250 row.

All ids are suggestions; the orchestrator files them.

## Next steps

Remediation fixes B-1 and adds the A3 shape (and the Probe B shape) as tests. It corrects the B-2 texts and renames, or makes true, the TEST-2831 title. Then a full-mode re-review (the ride is L3, so `ceremony_l3` keeps it full).
