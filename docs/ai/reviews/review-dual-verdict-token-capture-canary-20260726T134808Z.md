---
review_of: token-capture-canary
role: Code Review (single dual-verdict)
reviewer_model: claude-opus-4-8
generated_utc: 2026-07-26T13:48:08Z
---

```yaml
review:
  scope: "git diff main (working tree) — inline_review_scope: .aai/scripts/metrics-flush.mjs, .aai/scripts/state.mjs, .aai/SUBAGENT_PROTOCOL.md, .aai/SKILL_LOOP.prompt.md, tests/skills/test-aai-metrics.sh, tests/skills/test-aai-token-capture.sh, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-hitl-propagation.sh, tests/skills/test-aai-tdd-evidence.sh, docs/specs/SPEC-DRAFT-spec-token-capture-canary.md, docs/issues/CHANGE-DRAFT-token-capture-canary.md, docs/INDEX.md"
  spec: docs/specs/SPEC-DRAFT-spec-token-capture-canary.md (ceremony_level 3, SPEC-FROZEN:true)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/metrics-flush.mjs:420-436 (3-way classifier); TEST-001/002/003 (test_117/118/119, test-aai-metrics.sh) + TEST-004 (test_005 seam, test-aai-token-capture.sh) — all run green by reviewer" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/state.mjs:923-930 (post-append stderr WARNINGs, exit stays 0, tick still appended); TEST-005/006/007 (test_006/007/008, test-aai-token-capture.sh incl. negative control) — run green by reviewer" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/SUBAGENT_PROTOCOL.md:141-152,203-209 (D3 reclassified to INFO + MANDATORY note) + .aai/SKILL_LOOP.prompt.md:267,335-341; ledger true-up prompt-diet-ledger.sh:50 (+912 B verified) / test-aai-prompt-diet.sh TEST-012 pinned 29802 == independent re-sum (verified); TEST-008/009 + TEST-010/012 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "validator test-framework.sh 49/49 exit 0 (validation-token-capture-canary-20260726T131158Z.md); reviewer re-ran affected suites metrics/token-capture/prompt-diet/hitl-propagation/tdd-evidence — all exit 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hitl-propagation.sh, line: 445-462,
          issue: "reframed TEST-014 authorizer accepts ANY changed frozen ceremony_level:3 spec in the tree as authorizing ANY touched protected_paths_l3 path — there is no binding between the spec's declared scope (inline_review_scope / in-scope path list) and the specific L3 path touched. Same pattern in test-aai-tdd-evidence.sh TEST-005:310-333.",
          failure_scenario: "a future branch makes an unrelated/unauthorized edit to .aai/scripts/state.mjs while ALSO including any frozen L3 spec (even one for a different feature) in the same tree; both self-check tests pass, so the anti-drive-by teeth these tests exist to provide no longer bite for that case. Runtime WORKFLOW ceremony gate + review + operator-merge remain, so it is a weakened self-check, not an open runtime hole." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-tdd-evidence.sh, line: 340,
          issue: "stale log_pass message still reads 'state.mjs zero-diff' after the assertion was reframed to AUTHORIZE a non-empty diff — the success line now states the opposite of what was asserted.",
          failure_scenario: "a maintainer reading a green run is told state.mjs had zero diff when it in fact had an authorized non-empty diff; no functional impact, misleading evidence only. (Also flagged by validator as cosmetic.)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 924-925,
          issue: "duration-0 WARNING text asserts 'started==ended' but the guard is `duration === 0`, and duration = Math.max(0, Math.round(delta/1000)) — so it also fires for any sub-second tick (delta < 0.5 s).",
          failure_scenario: "a legitimately fast tick (~0.3 s) fires a WARNING whose text claims started==ended, which is false; warn-not-block so no functional harm, only a slightly inaccurate operator signal. Firing on a sub-second tick is itself defensible (real role ticks take minutes); only the message wording over-claims." }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 907-927,
          issue: "the missing-harness canary keys on `harness === undefined`; an explicit empty value (`--harness \"\"`) yields harness=\"\" (not undefined), so no WARNING fires AND harness_version becomes \"\" (empty) since `harness ?? 'unknown'` only substitutes for null/undefined — the tick records an empty harness_version with no canary.",
          failure_scenario: "a caller passes `--harness \"\"` (contrived): the tick silently records harness_version:\"\" and the canary stays quiet. The common/real failure mode (flag omitted) IS caught; this is a narrow edge only." }
  cannot_verify:
    - { claim: "the change actually reverses the real-world regression the intake cites (0 non-null tokens across 255 runs; 2026-07-25 ticks all duration 0 / harness unknown)",
        closes_with: "observing recorded tokens_in/out or usage_total_tokens notes AND non-zero duration + real harness_version in future live loop flushes/ticks — behavioral over subsequent runs, not derivable from this diff" }
    - { claim: "RR-2 — a downstream analyst/CI step consumes the new log-tick stderr WARNING",
        closes_with: "an integration test asserting a consumer acts on the stderr signal; spec-accepted as a human/CI-only signal (only the produce side — tick still appended — is machine-verified)" }
    - { claim: "full test-framework.sh 49/49 including the load-sensitive reaper suite (test-aai-run-tests.sh TEST-005)",
        closes_with: "a local full test-framework.sh run; reviewer verified the affected suites individually (all exit 0) and relied on the validator's 49/49 for the complete framework. The reaper flake is a documented, load-dependent, out-of-scope pre-existing issue (aai-run-tests.sh untouched by this branch)" }
  overall: pass
```

# Code Review — token-capture-canary (dual verdict)

- Scope: uncommitted working tree on `feat/token-capture-canary` vs `main` (inline mode per STATE `worktree.user_decision: inline`, scope list above).
- Spec: `docs/specs/SPEC-DRAFT-spec-token-capture-canary.md` (ceremony_level 3, SPEC-FROZEN:true, hybrid).
- Intake: `docs/issues/CHANGE-DRAFT-token-capture-canary.md`.
- Anti-gaming note: the dispatch supplied scope + spec + the validation report only; it did not pre-characterize findings or pre-rate severity beyond flagging the L3 protected surface (state.mjs) and asking for correctness-not-style focus, which is compatible with the anti-gaming contract. Full scope reviewed.

## Verdict 1 — spec_compliance: PASS

AC-table walk (every Spec-AC row):

- **Spec-AC-01 — compliant.** `metrics-flush.mjs` `buildEntry` (lines 420-436) implements the exact 3-way rule from the spec: numeric `tokens_in` AND `tokens_out` -> no line; else a `note` matching `/usage_total_tokens=(\d+)/` -> one INFO line (`undecomposed total <N> observed; cost unattributable by design`) naming ref/role/N; else -> one WARNING (`cost unattributable — tokens not recorded`) naming ref/role. Malformed/non-numeric `usage_total_tokens=` falls through to capture-missing exactly as the spec's edge case requires. INFO and WARNING are mutually exclusive per run (single `if` branch), un-aggregated (one push per run in the run loop). Reviewer ran TEST-001/002/003 (`test_117/118/119`) and the SEAM-1 end-to-end TEST-004 (`test_005`) — all green.
- **Spec-AC-02 — compliant.** `state.mjs` `cmdLogTick` (lines 923-930) emits, on stderr, AFTER the successful `fs.appendFileSync`, a WARNING containing `duration` when `duration === 0` and a WARNING containing `harness` when `harness === undefined`; both may fire together; exit stays 0 and the tick line is still appended (verified by TEST-005/006 asserting the JSONL line + TEST-008 negative control asserting a healthy tick emits nothing). Placement matches the spec (the `log-tick` branch returns before the `postWriteWarnings` mutator loop, so emitting inline is required and done). Reviewer ran TEST-005/006/007 — green.
- **Spec-AC-03 — compliant.** `SUBAGENT_PROTOCOL.md` D3 line reworded so it no longer claims the flush WARNING fires for an undecomposed total (now states INFO reclassification), and the `usage_total_tokens=<N>` note is made MANDATORY in both "Harness-reported usage capture" and "Merge protocol"; `SKILL_LOOP.prompt.md` step 4 + step 6 carry the MANDATORY note + `--started`/`--harness` wiring prose. Ledger trued up: `prompt-diet-ledger.sh` new 912 B entry — reviewer independently verified `SKILL_LOOP.prompt.md` net delta is exactly 912 B (25941 -> 26853) and `JUSTIFIED_GROWTH_BYTES` re-sums to 29802, matching the bumped TEST-012 pin. TEST-008/009/010/012 green. (`SUBAGENT_PROTOCOL.md` is correctly excluded from the `.aai/*.prompt.md` glob, so it carries no measured deficit — spec's companion-obligation reasoning holds.)
- **Spec-AC-04 — compliant.** Validator recorded full `test-framework.sh` 49/49 exit 0. Reviewer re-ran the five affected suites (metrics, token-capture, prompt-diet, hitl-propagation, tdd-evidence) individually — all exit 0. The `test-aai-run-tests.sh` reaper TEST-005 flake is load-dependent, documented (LEARNED.md / project memory `reaper-test-ci-load-flake`), and out of this scope's diff (`aai-run-tests.sh` untouched) — not a regression.

TEST-xxx existence/pass: all spec-declared tests exist at the cited physical stanzas and pass under reviewer execution. The two reconciled legacy stanzas (token-capture `test_005`, metrics `test_009` capture-missing wording keeps the `cost unattributable` substring) were handled as the spec's Regression note directed. No deviation from the frozen spec found.

## Verdict 2 — code_quality: PASS

No BLOCKING findings. Four NON-BLOCKING findings (see YAML `findings` for file:line + failure scenario):

1. **Coarse L3 authorizer in the two reframed self-check tests** (hitl-propagation TEST-014, tdd-evidence TEST-005): any frozen ceremony_level:3 spec in the tree authorizes any touched L3 path — no scope binding. Weakened anti-drive-by teeth (runtime gates unaffected). Disposition: **promote-to-follow-up-ref** — a tracked follow-up to bind the authorizer to the spec's declared in-scope path list / `inline_review_scope`.
2. **Stale `log_pass` text** "state.mjs zero-diff" at tdd-evidence:340 after the reframe. Disposition: **remediate-in-tree** (one-line message fix; also independently flagged by the validator).
3. **duration-0 WARNING wording over-claims `started==ended`** while the guard also fires sub-second (state.mjs:924-925). Disposition: **remediate-in-tree** (tighten wording) or accept.
4. **`--harness ""` edge** slips the missing-harness canary and writes an empty harness_version (state.mjs:907,927). Disposition: **promote-to-follow-up-ref** or accept (contrived input; omission — the real mode — is caught).

Positive correctness checks performed:
- INFO and WARNING lines both flow through the existing `warnings` array and are only `console.log`'d (metrics-flush.mjs:929); they do NOT affect the flush exit code and are printed one-per-run. (Minor pre-existing cosmetic: the `--dry-run` JSON lists them under a key literally named `warnings` — now includes INFO lines; harmless, not a finding.)
- log-tick warnings are strictly warn-not-block: emitted after the append, exit unchanged, entry shape unchanged (`harness_version` stays "unknown" on omission).
- Reframed authorizer negative arm preserved: it greps file CONTENT for `^ceremony_level:\s*3$` AND `^SPEC-FROZEN:\s*true$` (not a filename convention); an L3 touch with no frozen L3 spec still `log_fail`s (independently corroborated by the validator's adversarial-fixture check).

## Verdict 3 — cannot_verify

See YAML `cannot_verify` — three items: (1) the real-world regression reversal is behavioral over future runs; (2) RR-2 downstream consumer of the log-tick stderr signal (spec-accepted human/CI signal); (3) the complete `test-framework.sh` 49/49 including the load-sensitive reaper suite (reviewer verified affected suites individually + relied on validator for the full framework).

## Warning dispositions (H6) — for the orchestrator to record
- NB-1 (coarse L3 authorizer): promote-to-follow-up-ref.
- NB-2 (stale log_pass text): remediate-in-tree.
- NB-3 (duration-0 wording): remediate-in-tree or accept.
- NB-4 (`--harness ""` edge): promote-to-follow-up-ref or accept.

None block merge. A follow-up ref covering NB-1 (and optionally NB-4) plus the two in-tree message fixes would clear the conditional-PASS obligation.

## Overall: PASS
Both verdicts pass; no BLOCKING findings; cannot_verify items are named and non-blocking.
