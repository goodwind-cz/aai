# Code Review (single dual-verdict) — friction-capture-default-on

- Role: Code Review (single pass, two verdicts + cannot_verify)
- Reviewer model: claude-opus-4-8
- Date (UTC): 2026-07-26
- Branch: feat/friction-capture-default-on
- Scope: `git diff main` + untracked drafts (SPEC-DRAFT / CHANGE-DRAFT)
- Spec: docs/specs/SPEC-0088-spec-friction-capture-default-on.md (ceremony_level 2)
- Efficiency mode: diff-only; suites NOT re-run (recorded green; CI binding). Cheap greps/wc used.

```yaml
review:
  scope: "git diff main + untracked SPEC-DRAFT/CHANGE-DRAFT"
  spec: docs/specs/SPEC-0088-spec-friction-capture-default-on.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/system/FRICTION_PROTOCOL.md:319-345 (hook enumeration) + VALIDATION.prompt.md:153-165, REMEDIATION.prompt.md:40-43, SKILL_PR.prompt.md:199-202; TEST-008/009/010/011; seam heading count==1, record cmd intact" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-012 (v2 record, exit0) + TEST-013 (transient_provider_failure rejected non-zero, no line); recorded green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "SKILL_WRAP_UP.prompt.md:132-143 (non-empty spool triage + proposed-intake; empty stays SILENT); TEST-014/015" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-016 (primary rc=4 preserved after capture into chmod a-w spool, non-vacuous setup-sanity assert); every hook pointer states swallow/never-mask" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "ledger re-sum==30139==pin (independently verified); per-file deltas 629/288/307/657=1881 +453 IMPL match ledger claims; TEST-012 pin bumped from 27805 not silently recomputed" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/system/FRICTION_PROTOCOL.md, line: 331,
          issue: "The 'Deterministic hook points' enumeration back-references VALIDATION/REMEDIATION/SKILL_PR (with step numbers) but omits the 5th wired owner IMPLEMENTATION.prompt.md added by R2 remediation; the human-readable canon under-lists the wiring.",
          failure_scenario: "An agent/maintainer reading the seam to learn where capture is wired will not discover the IMPLEMENTATION canon-surface hook (the feature's own motivating class); only the hooks_wired() test knows about it. Drift risk if the seam is later trusted as the authoritative hook list." }
      - { rank: NON-BLOCKING, file: docs/ai/overview-data.json, line: 12,
          issue: "overview-data.json + overview.html regenerated with UNRELATED content (current_focus flips to token-capture-canary; delivered 102->103) — outside the spec's declared inline_review_scope.",
          failure_scenario: "Bundling an unrelated dashboard refresh into the PR commit muddies the scope diff; if committed it attributes token-capture-canary/docs-rollup changes to this scope. Derived artifact, no functional impact — verify intent or drop from the in-scope commit." }
  cannot_verify:
    - { claim: "All 16 wiring cases + prompt-diet/friction/hygiene/feedback-status suites exit 0, and headroom stays 636/2048 after the +453 IMPLEMENTATION growth",
        closes_with: "PR CI full framework run (dispatch instructed no local suite re-run; validation report recorded green pre-R2, +453 added after)" }
    - { claim: "R1 residual: RED_CLASS lines added to the 3 NEW RED logs so tdd-evidence-check no longer returns UNCLASSIFIED (exit 2)",
        closes_with: "docs/ai/tdd/*RED*.log not present in this diff; re-run node tdd-evidence-check.mjs --red <logs>" }
    - { claim: "Runtime efficacy of the hooks (an agent actually fires capture at each moment)",
        closes_with: "Inherent to a prompt-only change (R3 determinism ceiling) — hooks are instruction-deterministic, not runtime-enforced; no diff-level test can close this" }
  overall: pass
```

## AC table walk (detail)

- **Spec-AC-01 — compliant.** FRICTION_PROTOCOL.md gains a `### Deterministic hook points` subsection *inside* the existing `## Skill wiring (shadow capture)` seam (h3, so it stays within the seam extractor's range), enumerating the three required hooks: validation FAIL, remediation dispatch, canon-file gate/lint/CI failure. Owning prompts each carry a grep-verifiable `FRICTION HOOK` pointer naming `FRICTION_PROTOCOL.md` and `(schema v2)`: VALIDATION step 5h + step 8, REMEDIATION step 2, SKILL_PR step 5d. Existing pins intact — seam heading appears exactly once; record command `node .aai/scripts/aai-friction.mjs record --input` present. Guarded by TEST-008..011 (incl. teeth: mutation strips each side).
- **Spec-AC-02 — compliant.** TEST-012 records a v2 fixture via the documented command → exactly one spool line, exit 0, asserting the v2 keys impact/confidence/reproducible. TEST-013 offers `transient_provider_failure` (excluded) → rejected non-zero, zero spool lines. Taxonomy remains the ownership gate; the seam text explicitly states hooks do not widen ownership.
- **Spec-AC-03 — compliant.** SKILL_WRAP_UP step 6 now ALWAYS runs `aai-feedback-triage.mjs` on a non-empty spool and lists each `review_candidate` cluster as a proposed-intake one-liner; empty spool stays SILENT (contract explicitly restated). TEST-015 greps the wiring; TEST-014 crosses SEAM B end-to-end (spool → triage → ≥1 cluster).
- **Spec-AC-04 — compliant.** TEST-016 simulates the documented best-effort pattern: primary step exits 4, capture into an unwritable spool fails, final rc stays 4. Non-vacuous — a setup-sanity assertion requires the capture to actually fail first. All five hook pointers carry the swallow / never-mask / never-block clause.
- **Spec-AC-05 — compliant (ledger verified independently).** Re-summed `JUSTIFIED_GROWTH_BYTES` = 30139 == the bumped TEST-012 pin. Measured per-file prompt-corpus deltas: VALIDATION +629, REMEDIATION +288, SKILL_PR +307, SKILL_WRAP_UP +657 (= +1881), IMPLEMENTATION +453 — each matches its ledger entry's leading-byte claim exactly. FRICTION_PROTOCOL.md is in `.aai/system/` (not the prompt-diet glob) → correctly zero ledger cost. Pin bumped from 27805 (→ 29686 → 30139), not silently recomputed.

## R1 / R2 disposition check (dispatch focus a)

- **R1 (spec RED-claims wrong) — CLOSED in-tree.** The spec Test Plan Notes now carry the "RED status correction (validation R1, 2026-07-26)": it corrects the earlier over-claim that spec TEST-005/006/007/009 (suite TEST-012/013/014/016) failed pre-change, stating green-only-pre-change is correct for those arms and the RED-proof obligation applies only to the NEW wiring guards. The second R1 ask (add RED_CLASS lines to the 3 RED logs) is not in this diff → cannot_verify.
- **R2 (2/4 friction classes uncaptured) — PARTIALLY CLOSED.** The IMPLEMENTATION.prompt.md hook directly closes the headroom-cap-trap class — its wording explicitly names "the prompt-diet ledger/headroom guard" as the canon-surface check whose failure triggers capture, i.e. the feature's own motivating case that was provably uncaptured this session. The validator-monitor-stall gap remains unaddressed (no stall/timeout hook wired); the delivered ACs required only the three named hooks, so this is an acknowledged residual efficacy gap, not an AC violation.

## Hook wording consistency (dispatch focus b)

All five wired pointers share the same contract with no drift: each carries the `FRICTION HOOK` marker, `default-on`, `best-effort`, a `FRICTION_PROTOCOL.md ... Deterministic hook points` reference, `(schema v2)`, `swallow any capture failure`, and a never-mask/never-block clause tuned to its context (never change the verdict / never block the fix / never block the sweep / never affect the step's outcome). VALIDATION 5h and IMPLEMENTATION give the fuller `"Skill wiring (shadow capture)" -> "Deterministic hook points"` path; the other three abbreviate to `"Deterministic hook points"` — cosmetic, not a contract difference.

## Pinned-token integrity (dispatch focus d) — INTACT

- SEAM_HEADING `## Skill wiring (shadow capture)` — count == 1.
- RECORD_CMD `node .aai/scripts/aai-friction.mjs record --input` — present.
- No-Phase-2 pin: extracted seam (now including the new subsection, which the extractor captures to EOF) has zero hits for `aai-feedback-triage | feedback.yaml | upsert | gh issue/pr/api`. The triage wiring correctly lives in SKILL_WRAP_UP, not the seam.

## Scope (dispatch focus e)

- In-scope and clean: the 5 prompts, FRICTION_PROTOCOL.md, the two test files, the ledger, the drafts. EVENTS.jsonl additions (docs_audit telemetry + ac_status transitions for this spec) are expected workflow telemetry (per project memory: never restore EVENTS.jsonl).
- Out-of-declared-scope: `docs/ai/overview-data.json` + `docs/ai/overview.html` were regenerated with content about token-capture-canary / docs-rollup-userguide, not this feature. Derived dashboard artifact, no functional impact — flagged NON-BLOCKING (verify the dashboard refresh is intended for this PR or exclude it from the in-scope commit).

## Warning dispositions (H6)

- NB-1 (seam omits IMPLEMENTATION owner): recommended disposition **remediate-in-tree** — add one bullet to the enumeration naming `.aai/IMPLEMENTATION.prompt.md` (canon-surface check failure), mirroring the SKILL_PR back-reference. One line, keeps the canon self-describing. Orchestrator records.
- NB-2 (overview dashboard out of scope): recommended disposition **orchestrator decision** — either confirm the refresh belongs in this PR or unstage overview-data.json/overview.html from the scope commit.
- R2 residual (monitor-stall hook) and R1 residual (RED_CLASS lines): recommended disposition **promote-to-follow-up-ref** if not remediated before close.

## Overall: PASS

Both verdicts pass: spec_compliance PASS (all five Spec-AC compliant, AC table terminal + evidenced), code_quality PASS (no BLOCKING; two NON-BLOCKING with named dispositions). cannot_verify items are the CI-binding suite run and the R1 RED_CLASS residual — neither blocks by itself, but each must be visible at merge-readiness.
