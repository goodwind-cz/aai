---
review_of: spec-learned-append-gate
scope: learned-append-gate
model: claude-opus-4-8
date: 2026-07-27
---

# Code Review — learned-append-gate (single dual-verdict)

```yaml
review:
  scope: "git diff main + untracked — .aai/scripts/learned-append.mjs, tests/skills/test-aai-learned-append.sh, .aai/SKILL_WRAP_UP.prompt.md, .aai/system/FRICTION_PROTOCOL.md, .aai/system/PROFILES.yaml, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, docs/issues/CHANGE-0069-learned-append-gate.md, docs/product/learned-append-gate.md, docs/specs/SPEC-0095-spec-learned-append-gate.md"
  spec: docs/specs/SPEC-0095-spec-learned-append-gate.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/learned-append.mjs:142 formatEntry + :182 buildRuleTextCandidate; TEST-001/002/003/011 green (green-20260727T105431Z)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/learned-append.mjs:202 isPureAppend + :253 reject path; TEST-004/005/006/007 green, tree byte-identity asserted" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/learned-append.mjs:259 dry-run branch AFTER the gate; TEST-008/009 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "SKILL_WRAP_UP.prompt.md step 3/6 + FRICTION_PROTOCOL.md pointer + PROFILES.yaml:110 + ledger entry; TEST-013/014/015/016 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-017 green (friction-wiring + hygiene-pack); layer-profiles + prompt-diet suites green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-learned-append.sh, line: 384,
          issue: "TEST-013 is order-blind: it greps step 3 for both 'critic' and 'learned-append.mjs' but never asserts the critic mention PRECEDES the gate invocation (validation residual #1).",
          failure_scenario: "A future edit reorders step-3 prose to 'invoke the gate, then run a critic afterward' — semantically wrong, since a post-hoc critique after an already-committed append defeats the confirm-then-review-then-write intent — yet TEST-013 stays green and the seam's ordering guarantee silently rots.",
          disposition: remediate-in-tree }
  cannot_verify:
    - { claim: "A real human/agent session actually routes a confirmed rule through the critic step before calling the gate (the discipline lives in prompt prose, not code).",
        closes_with: "Observing an actual wrap-up run; the gate only guarantees append-only IF the script is the write path — matches the spec's own recorded residual risk." }
  overall: pass
```

## Scope and spec

Reviewed the frozen spec `SPEC-0095-spec-learned-append-gate.md` against
`git diff main` plus the untracked new files. SPEC-FROZEN: true, ceremony_level 2.
No dispatch coaching to record (the dispatch named focus areas but did not
pre-rate severity or scope-exclude anything).

## Verdict 1 — spec_compliance: PASS

The AC-walk above is fully compliant. Notes per the "list every deviation"
duty:

- Spec-AC-01/02: the `isPureAppend` funnel (line 202-204) is the single
  authority both modes pass through, exactly as the spec's seam analysis
  requires. The mid-insert case (TEST-006) is genuinely constructed as a
  mid-file splice in `buildRuleTextCandidate` (line 192-197) and rejected by
  the generic gate rather than special-cased — this matches the spec's
  deliberate-construction claim and is the strongest part of the design.
- Spec-AC-03: the `--dry-run` branch sits AFTER the `isPureAppend` check
  (line 253 gate, line 259 dry-run), so dry-run structurally cannot bypass
  the gate. TEST-009 proves the reject-shaped dry-run still exits 1.
- Spec-AC-04: all four wiring edits present and grep-pinned. RED/GREEN
  evidence logs exist (red-...script-absent, red-...wiring-absent,
  green-20260727T105431Z), all 17 tests PASS in the green log.
- TEST-xxx existence/passage confirmed by reading the green log directly
  (not re-run, per the diff-only efficiency budget).

## Verdict 2 — code_quality: PASS (no BLOCKING)

### Focus-area findings

(a) **isPureAppend correctness — clean.** `candidate.length >= original.length
&& candidate.slice(0, original.length) === original` is a correct prefix check.
It operates in JS string space; `writeFileSync` serializes the same string to
UTF-8, so the comparison space and the write space are consistent — encoding
never breaks the guarantee. The separator injection in `buildRuleTextCandidate`
is sound in every branch: for `newHeading` and `atEOF`, `offset === original.length`
so `original.slice(0, offset) === original` and the result is a pure append by
construction; `sep` correctly suppresses/adds the joining newline based on
`original.endsWith('\n')`. The mid-file branch intentionally produces a
non-append that the gate then rejects. Empty-file and no-op (`appended.length
=== 0`) paths are handled. No defect.

(b) **--full vs rule-text split — no confusion risk.** The modes are mutually
guarded: `--full` with `--source`/`--section` is a hard usage error (line 243,
exit 2), and rule-text mode requires `--source` (line 246). Help text, the
script header, and the product doc all distinguish them clearly ("generic
verifier … not the normal path"). No finding.

(c) **Validation residual #1 (TEST-013 order-blind grep) — NON-BLOCKING,
remediate-in-tree.** See the finding above. The current prose ("route it
through a compact critic pass first … and ONLY THEN append it — never a direct
edit") is correct today; the gap is that the test would not catch a future
reordering. It is cheap to pin. Recommended exact fix — append inside
`test_013_wrapup_step3_wired`, reusing the already-extracted `$step3`:

```bash
  crit_ln="$(printf '%s\n' "$step3" | grep -ni "critic" | head -1 | cut -d: -f1)"
  gate_ln="$(printf '%s\n' "$step3" | grep -nF "learned-append.mjs" | head -1 | cut -d: -f1)"
  [ -n "$crit_ln" ] && [ -n "$gate_ln" ] && [ "$crit_ln" -lt "$gate_ln" ] \
    || log_fail "TEST-013: the critic pass must be documented BEFORE the gate invocation (got critic@$crit_ln, gate@$gate_ln)"
```

(d) **Product doc quality — good, self-gating honored.** `docs/product/
learned-append-gate.md` has correct frontmatter (id/type/status/spec/updated),
accurate CLI surface, and an honest Limits section that names the
guardrail-not-security-boundary framing and the last-section-only constraint.
Matches the implementation. No finding.

(e) **Scope creep — none in code.** Implementation touches exactly the spec's
declared inline_review_scope. The out-of-declared-scope tracked changes
(`docs/ai/EVENTS.jsonl` docs_audit lines, `docs/ai/overview*.{json,html}`,
`docs/project-sessions/...`) are generated workflow telemetry, not code — see
INFO-2.

### INFO (non-gating)

- **INFO-1 (byte vs char labeling).** The header comment, the "appended N
  bytes" message (line 270-272), and `diffSummary`'s "first divergence at byte
  offset" (line 214) report JS string `.length`/indices (UTF-16 code units)
  but call them bytes. For ASCII rules these coincide; for multibyte content
  (accented text, emoji) the counts/offset would misreport. Purely cosmetic —
  the gate decision itself is unaffected. Optional: relabel as "chars" or
  compute `Buffer.byteLength`.
- **INFO-2 (generated telemetry drift).** `docs/ai/overview-data.json` lists
  the work item with `"status": "draft"` while the CHANGE frontmatter is
  `status: implementing`; the generator derives "draft" from the `CHANGE-DRAFT-`
  filename prefix. Benign generator behavior, not this change's concern.

## Warning dispositions (H6)

- NB-1 (TEST-013 ordering pin): recommended **remediate-in-tree** (fix above is
  trivial and cheap). If the orchestrator defers, it must instead promote to a
  `decisions.jsonl` entry or a tracked follow-up ref before closeout.

## Next steps

1. Apply the NB-1 test pin (or record its deferral per H6).
2. Optional INFO-1 relabel.
3. Overall verdict is **pass**; the scope is merge-ready once NB-1 is
   remediated or explicitly dispositioned.
