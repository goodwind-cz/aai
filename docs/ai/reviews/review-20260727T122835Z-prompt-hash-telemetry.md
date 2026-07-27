```yaml
review:
  scope: "git diff main + untracked — .aai/scripts/lib/prompt-hash.mjs, .aai/scripts/state.mjs, .aai/scripts/metrics-flush.mjs, .aai/scripts/metrics-report.mjs, .aai/scripts/orchestration-dispatch.mjs, .aai/system/PROFILES.yaml, tests/skills/{test-aai-prompt-hash,test-aai-state,test-aai-metrics,test-aai-orchestration-dispatch}.sh, docs/product/prompt-hash-telemetry.md, docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md, docs/issues/CHANGE-0070-prompt-hash-telemetry.md"
  spec: docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md
  tier: L3 (most-capable — mandatory review, protected surface state.mjs append-run)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/prompt-hash.mjs:43-65; TEST-001 (test-aai-prompt-hash.sh); green-20260727T115839Z-TEST-001.log" }
      - { ac: Spec-AC-02, call: compliant, citation: "state.mjs:267-278 hexFlag, :727 parse, :747 conditional push; TEST-002/003/004; independently reproduced (exit 2 + byte-identical no-write)" }
      - { ac: Spec-AC-03, call: compliant, citation: "metrics-flush.mjs:470; TEST-005/006/007 (SEAM-1 real append-run->flush)" }
      - { ac: Spec-AC-04, call: compliant, citation: "metrics-report.mjs:213-246; TEST-008/009; TEST-127 proves byte-identical report when no role has >1 hash" }
      - { ac: Spec-AC-05, call: compliant, citation: "orchestration-dispatch.mjs:830-832 JSON additive (guarded on out.system_prompt), :805-807 humanBlock advisory; TEST-010/011; TEST-002 key-set extended not broken" }
      - { ac: Spec-AC-06, call: cannot-verify, citation: "green-20260727T121401Z-all-targeted-suites.log + validation PASS 7/7 attest local green; full framework CI run deferred to PR (diff-only review, no suite runs per efficiency mandate)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/system/PROFILES.yaml:116 under core:; TEST-015; green-20260727T115919Z-TEST-015.log" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Spec-AC-06 full framework suite green on CI", closes_with: "PR CI run of .aai/scripts/aai-run-tests.sh exit 0" }
    - { claim: "runtime producer wiring — the loop/orchestrator actually passing --prompt-hash to a live append-run", closes_with: "follow-on wiring scope (declared out-of-scope in spec SEAM residual risk); pipeline proven only from the append-run boundary onward" }
  overall: pass
```

# Code Review — prompt-hash-telemetry (L3, single dual-verdict)

**Scope:** `git diff main` + untracked, restricted to the declared prompt-hash-telemetry file set (STATE `code_review.scope` / dispatch handoff). Everything is inline/uncommitted on branch `feat/prompt-hash-telemetry`.
**Spec:** `docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md` (SPEC-FROZEN, ceremony_level 3).
**Anti-gaming note:** the dispatch prompt supplied focus hints (append-run minimality, separator design, additivity, doc quality, scope creep). These match the spec's own obligations and did not pre-rate severity or scope-exclude any area; the full declared scope was reviewed regardless.

## Verdict 1 — spec_compliance: PASS

AC table walk (see YAML `ac_walk` for citations):

- **Spec-AC-01** compliant. `computeEffectivePromptHash(rolePromptPath, root)` hashes role prompt + `SUBAGENT_CONTRACT.md` + `LEARNED.md` in fixed order, each framed by a `\n--- <basename> ---\n` separator; `readOrNull` swallows all read errors so a missing input yields the `ABSENT` marker and the function never throws; `shortHash` returns the first 12 hex. TEST-001 exercises determinism, per-input sensitivity (role/CONTRACT/LEARNED), ABSENT-on-missing (LEARNED and role), and short form.
- **Spec-AC-02** compliant. New `hexFlag` validates `/^[0-9a-f]{12,64}$/`; absent → `undefined` → field omitted; invalid → `fail()` (exit 2, usage error naming the flag + hex rule) before any write; valid → pushed onto `runLines` AFTER the conditional `tdd_tests` push. I reproduced all three branches independently in a throwaway state tree: valid appends `prompt_hash` after `cost_usd`; absent omits the key; `--prompt-hash ABCXYZ` exits 2 with `"must be 12-64 lowercase hex characters"` and leaves STATE byte-identical (`cmp` clean).
- **Spec-AC-03** compliant. One additive `if (typeof r.prompt_hash === 'string') out.prompt_hash = r.prompt_hash;` line in `buildEntry`. TEST-005 (present passthrough + sibling-without-key omission) and TEST-007 (SEAM-1: real append-run → real flush → exact hash) cover it.
- **Spec-AC-04** compliant. `metrics-report.mjs` builds a per-role map of short-hash counts and emits the `### Prompt versions` table only for roles with `hashes.size > 1`. TEST-126 asserts grouping + counts and that a single-hash role (Validation) is excluded; TEST-127 diffs report output with vs. without the `prompt_hash` field and requires byte-identical output when no role qualifies — a real additivity proof, not just an absence check.
- **Spec-AC-05** compliant. `prompt_hash` added to dispatch JSON only inside `if (out.system_prompt)`, so `no_action`/`needs_llm` verdicts (no role, no system_prompt) are untouched; advisory line added in `humanBlock`. The pre-existing TEST-002 key-set `.every(k => k in o)` assertion was extended with `prompt_hash` (the sanctioned extension), and TEST-028 re-verifies additivity plus a paused/no_action fixture that must NOT carry the key.
- **Spec-AC-06** cannot-verify (local green attested, CI deferred). Per the efficiency mandate this was a diff-only review with no suite runs. All six named green TDD logs exist under `docs/ai/tdd/` and validation recorded PASS 7/7; the full framework CI run is the remaining evidence.
- **Spec-AC-07** compliant. `.aai/scripts/lib/prompt-hash.mjs` is listed under `core:` in `PROFILES.yaml` (correct — it is in the import closure of `orchestration-dispatch.mjs`), keeping the 100%-classified invariant. TEST-015 covers it.

TEST-xxx existence check: all 15 declared tests are present in the four suites with the claimed IDs; the append-run/dispatch key-set assertions were extended rather than replaced. No deviation from the frozen spec found.

## Verdict 2 — code_quality: PASS

No BLOCKING or NON-BLOCKING findings. Real-defect classes checked:

- **Protected-surface minimality (state.mjs):** the append-run hunk is exactly a flag-list entry, a new isolated `hexFlag` validator, one parse call, and one conditional push placed after `tdd_tests` — nothing else in `cmdAppendRun` moved. Validator reuses the established `strFlag`/`fail` path, so absent → zero delta and present-with-tdd_tests → existing lines unmoved. Independently reproduced byte-identical-when-absent and no-write-on-bad-value.
- **Additivity elsewhere:** flush (single typeof-guarded copy), report (fully new trailing block, guarded on `promptRows.length > 0`), dispatch (guarded on `out.system_prompt`, inside the existing try) are all additive; no existing output path is altered.
- **Error handling:** `computeEffectivePromptHash` cannot throw (all reads via `readOrNull`), and it is called inside dispatch's try/catch regardless.
- **Correctness of grouping:** `slice(0,12)` normalizes stored 12- or 64-char hashes to a common prefix before counting, so mixed-length storage of the same hash still groups together.

### INFO (non-gating — no realistic failure scenario)
- **Separator / ABSENT ambiguity.** The digest could theoretically be confused by content that embeds the literal section separator `\n--- SUBAGENT_CONTRACT.md ---\n`, or by a file whose entire content is exactly `ABSENT` (indistinguishable from a missing file). Neither has a realistic trigger: this is a content-addressed observability fingerprint with no adversary and no security/enforcement decision keyed on it (spec "Honest limitation" + "Observability only"). An empty file (`""`) is correctly distinct from a missing file (`ABSENT`). Recorded as INFO; does not gate.

## Out-of-scope observations (process, not code_quality)
Three working-tree files are modified outside the declared review scope: `docs/ai/overview.html`, `docs/ai/overview-data.json` (dashboard artifacts), and `docs/project-sessions/2026-07-26-independent-audit-autonomy-pack.md`. They are unrelated to this change and were not reviewed. The PR skill stages only in-scope paths, so this is a staging-hygiene note for closeout — confirm these are intentionally excluded (or belong to a different work item) before opening the PR.

## Warning dispositions (H6)
No NON-BLOCKING findings → no dispositions required. The single INFO note never gates and needs no decision/ref.

## Overall: PASS
Both verdicts pass. Merge-readiness caveats: (1) Spec-AC-06 full-framework CI must be green on the PR; (2) exclude the three out-of-scope working-tree files from PR staging; (3) L3 operator final-diff sign-off is required at PR ceremony per the spec Evidence Contract.

## STATE
Per dispatch constraint (read-only, NO STATE writes), the reviewer did NOT run `state.mjs set-code-review`. The orchestrator should record `code_review.status: pass`, scope, this report path, and the notes above.
