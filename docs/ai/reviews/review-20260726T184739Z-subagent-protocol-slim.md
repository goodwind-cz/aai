```yaml
review:
  scope: "git diff main + untracked (.aai/SUBAGENT_CONTRACT.md, docs/specs/SPEC-0087-spec-subagent-protocol-slim.md, docs/issues/CHANGE-0061-subagent-protocol-slim.md); diff-only per efficiency direction"
  spec: docs/specs/SPEC-0087-spec-subagent-protocol-slim.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/SUBAGENT_CONTRACT.md (wc -l = 58 ≤ 60); tokens verified: subagent_result: fence, duration_seconds MUST match, MUST NOT write STATE.yaml, sole writer, docs/ai/tdd/, append-event.mjs, rationalization table, self-report prohibition; TEST-080" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "5-phrase dedup verified: subagent_result:/MUST NOT write STATE.yaml/duration_seconds MUST match all 0-count in PROTOCOL; self-report + characterize-findings 0-count in CONTRACT; TEST-081" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "payload refs → CONTRACT: IMPLEMENTATION:78,121 / VALIDATION:206 / ORCH_PARALLEL:42,137,139 / SKILL_LOOP:259 / SKILL_TDD:176 / BRIEF_TEMPLATE:35; orchestrator refs stay PROTOCOL: IMPLEMENTATION:120,146 / ORCH_PARALLEL:110,141 / VALIDATION:235; no full-protocol-to-unit; TEST-082 extended to pin IMPLEMENTATION+SKILL_TDD" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/system/PROFILES.yaml core += SUBAGENT_CONTRACT.md; corpus = 345010 at relocation time, byte-neutral renames; post-review SKILL_LOOP:18 clause fix adds an itemized +32 B ledger entry (TEST-012 pin 27805); TEST-006/007" }
      - { ac: Spec-AC-05, call: cannot-verify,
          citation: "targeted suites recorded green post-remediation (validation report + AC table); not re-run locally per efficiency/operator direction — PR CI is the binding gate" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_LOOP.prompt.md, line: 18,
          issue: "AUTHORITATIVE SOURCES entry still labels SUBAGENT_PROTOCOL.md as carrying 'result block format' — that format relocated to CONTRACT; the parenthetical is now stale.",
          failure_scenario: "A loop orchestrator reading AUTHORITATIVE SOURCES for the result-block format opens PROTOCOL and no longer finds it there; PROTOCOL's new head pointer redirects to CONTRACT, so it degrades rather than breaks. Left on PROTOCOL by spec design (token-capture TEST-001 needs a PROTOCOL mention here), but the 'result block format' clause should read 'merge protocol' only." }
      - { rank: NON-BLOCKING, file: .aai/EXPERT_RESOLVE.prompt.md, line: 76,
          issue: "'Return results in SUBAGENT_PROTOCOL.md format (see below)' — the canonical result-block format now lives in CONTRACT, not PROTOCOL; label is stale.",
          failure_scenario: "A reader who follows the PROTOCOL name instead of the inline '(see below)' block finds no format in PROTOCOL. Mitigated because the format is inlined immediately below in the same file, so the reference resolves locally. Pre-existing wording, outside the frozen Spec-AC-03 enumeration; validator already noted it lowest-severity/mitigated." }
  cannot_verify:
    - { claim: "Targeted suites (docs-lock, hygiene-pack incl. TEST-080/081/082, layer-profiles, prompt-diet, token-capture, state) exit 0 after remediation",
        closes_with: "PR CI full-framework run (operator direction: do not run full framework locally); suites recorded green in the re-validation PASS" }
  overall: pass
```

# Code Review — subagent-protocol-slim (post-remediation re-review)

**Scope:** `git diff main` + untracked contract/spec/change docs, diff-only per the efficiency direction (suites not re-run; recorded green post-remediation, CI owns the binding run).
**Spec:** `docs/specs/SPEC-0087-spec-subagent-protocol-slim.md` (SPEC-FROZEN: true, ceremony_level 2).
**Prior verdict:** FAIL (`docs/ai/reports/VALIDATION-subagent-protocol-slim-20260726T184217Z.md`) — IMPLEMENTATION:121 leaked the full protocol into every parallel Implementation unit payload + 2 dangling result-block refs (IMPLEMENTATION:78, SKILL_TDD:176).

## (a) The remediation closes the validator's blockers

The validator's primary blocker and its two secondary dangling refs are all closed, with the payload-vs-orchestrator split landing correctly on the four IMPLEMENTATION lines named in the dispatch:

| Line | Kind | Target | Correct? |
|------|------|--------|----------|
| IMPLEMENTATION:78 | expert result-block payload ref | `SUBAGENT_CONTRACT.md` | ✓ (was dangling) |
| IMPLEMENTATION:120 | "see …" spawn/decompose criteria (orchestrator) | `SUBAGENT_PROTOCOL.md` | ✓ stays |
| IMPLEMENTATION:121 | per-unit dispatch **payload** | `SUBAGENT_CONTRACT.md` | ✓ (primary blocker) |
| IMPLEMENTATION:146 | merge protocol (orchestrator) | `SUBAGENT_PROTOCOL.md` | ✓ stays |
| SKILL_TDD:176 | expert result-block payload ref | `SUBAGENT_CONTRACT.md` | ✓ (was dangling) |

No remaining reference passes the full `SUBAGENT_PROTOCOL.md` as a dispatched-unit payload. Orchestrator-only refs (validator spawning ORCH:110, merge protocol ORCH:141 / VALIDATION:235 / IMPLEMENTATION:146, harness-usage SKILL_LOOP:187/267/346) correctly remain on PROTOCOL.

## (b) Rule-relocation fidelity

- CONTRACT is **58 lines** (≤ 60). ✓
- Result-block YAML in CONTRACT is **byte-identical** to the pre-change PROTOCOL fence (`diff` empty against `main:.aai/SUBAGENT_PROTOCOL.md`). ✓
- No rule lost: single-writer subagent core (MUST-NOT-write STATE.yaml, allowed-write list, the 2 subagent rationalization rows) moved intact to CONTRACT; PROTOCOL keeps the orchestrator serialization note + a pointer to CONTRACT for the subagent-facing core; the PROTOCOL table was correctly renamed "Orchestrator lock-serialization rationalization table" retaining only its 2 lock rows.
- No duplication: 5-phrase spot-grep confirmed each phrase in exactly one file (subagent_result:/MUST-NOT-write/duration_seconds → CONTRACT-only, 0 in PROTOCOL; self-report/characterize-findings → PROTOCOL-only, 0 in CONTRACT).
- Byte-neutral at review time: corpus = **345010**; the post-review SKILL_LOOP:18 clause fix (disposition of NB-1 below) added +32 B with its own itemized ledger entry (TEST-012 pin 27805).

## (c) TEST-082 pins the leak permanently

`tests/skills/test-aai-hygiene-pack.sh::test_082` now asserts IMPLEMENTATION unit-payload → CONTRACT, IMPLEMENTATION + SKILL_TDD expert result-block → CONTRACT, and IMPLEMENTATION merge-protocol stays PROTOCOL — the exact regression the FAIL report requested. The docs-lock TEST-010 retarget (`$CONTRACT_DOC`) and the hygiene TEST-002/004 result-block byte-diff retarget to CONTRACT are also in place. The blind spot that let the suite stay green while the requirement was unmet is now covered.

## (d) Scope creep

None of concern. Beyond the classified in-scope files, the diff carries only auto-generated workflow telemetry companions — `docs/INDEX.md` (regen timestamp), `docs/ai/EVENTS.jsonl` (5 `ac_status` planned→done appends for this ref), and `docs/ai/overview-data.json`/`overview.html` (regenerated overview). No stray behavioral or source edits.

## Findings (both NON-BLOCKING — see YAML for failure scenarios)

1. **SKILL_LOOP:18** — AUTHORITATIVE SOURCES still credits `SUBAGENT_PROTOCOL.md` with "result block format"; that format moved to CONTRACT. The line legitimately stays on PROTOCOL (token-capture TEST-001), but the "result block format" clause is now inaccurate — trim it to "merge protocol". Disposition: **promote-to-follow-up-ref** (byte-changing, outside the frozen byte-neutral scope; orchestrator-facing source list, not a unit payload, so Spec-AC-03 is unaffected).
2. **EXPERT_RESOLVE:76** — "SUBAGENT_PROTOCOL.md format (see below)" label is stale post-relocation; mitigated by the inlined format right below in the same file. Validator already logged this lowest-severity/mitigated. Disposition: **promote-to-follow-up-ref** (pre-existing wording, outside Spec-AC-03 enumeration).

## Verdict

**PASS** — both verdicts pass. spec_compliance: pass (Spec-AC-01..04 compliant; Spec-AC-05 cannot-verify-locally, recorded green, PR CI is the binding gate). code_quality: pass (no BLOCKING; 2 NON-BLOCKING staleness items, each with a named disposition). The remediation cleanly closes the validation FAIL and the leak is now test-pinned.

Next steps: orchestrator records the two NON-BLOCKING dispositions (follow-up ref or decisions.jsonl) per the H6 warnings policy before closeout; PR CI is the binding no-regression gate.
