# Code Review — downstream-rides-ask-no-governance-questions (round 1 of 2)

- Reviewer: claude-opus-5-5, dispatched Code Review role (AAI_ROLE=subagent, read-only on implementation files)
- Scope: working tree of /Users/ales/Projects/aai-autopilot (branch change/downstream-rides-ask-no-governance-questions, uncommitted) against base `main` (4c3d8a5d). 15 modified + 3 untracked paths: .aai/scripts/ride-select.mjs, .aai/SKILL_SHIP.prompt.md, .aai/SKILL_PR.prompt.md, .aai/system/AUTONOMOUS_LOOP.md, .aai/ROLE_COMMON.md, .aai/AGENTS.md, tests/skills/test-aai-ride-select.sh, tests/skills/test-aai-downstream-autopilot.sh (new), tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-hygiene-pack.sh, tests/skills/lib/cd-subshell-leak-baseline.tsv, docs/ai/decisions.jsonl (+2 append), docs/ai/EVENTS.jsonl (+3 append), docs/INDEX.md (timestamp), plus the intake and spec DRAFTs.
- Spec: docs/specs/SPEC-0200-spec-downstream-rides-ask-no-governance-questions.md (frozen, amended once post-freeze: decisions.jsonl ts 2026-09-30T22:48:12Z, unsigned-tracked by fu-amend-downstream-rides-ask-no-d8106d).
- Preflight: STATE worktree.user_decision=worktree, base main; `git status --porcelain` shows only in-scope paths. No coaching in the dispatch (no expected findings, severities or exclusions named).

```yaml
review:
  scope: "main (4c3d8a5d) vs working tree of change/downstream-rides-ask-no-governance-questions (uncommitted), all 18 touched paths"
  spec: docs/specs/SPEC-0200-spec-downstream-rides-ask-no-governance-questions.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/ride-select.mjs:274-284; TEST-1201 (test_005_fail_closed) + TEST-1202, test-aai-ride-select.sh exit 0" }
      - { ac: Spec-AC-02, call: compliant, citation: "ride-select.mjs:274 branch gated on cmd==='gate', loadRoadmap unchanged; TEST-1203/1204/1205 exit 0" }
      - { ac: Spec-AC-03, call: compliant, citation: "ride-select.mjs:275-277 usage checks precede the existsSync branch; TEST-1206 exit 0" }
      - { ac: Spec-AC-04, call: compliant, citation: "same fs.existsSync predicate as orchestration-dispatch.mjs:732; TEST-1207 (real buildSnapshot vs real CLI, 3 roots) exit 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "default path unchanged (ride-select.mjs:42); TEST-1208 exit 0" }
      - { ac: Spec-AC-06, call: compliant, citation: "ride-select.mjs:13-18 header; .aai/AGENTS.md:317 rule 4; TEST-1209 + prompt-diet test_769 exit 0" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_SHIP.prompt.md:39-46 (1a) and :86 (ride gate line); TEST-1210 exit 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "AUTONOMOUS_LOOP.md:95-97, SKILL_PR.prompt.md:209-210, ROLE_COMMON.md:94-95, SKILL_SHIP.prompt.md:32-33 + :87-89; TEST-1211 + test-aai-spec-amend.sh exit 0" }
      - { ac: Spec-AC-09, call: compliant, citation: "tests/skills/test-aai-downstream-autopilot.sh TEST-1212 (positive controls ADMIT + unsigned-tracked=1) and TEST-1213 (negative control) exit 0" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-1214 incl. other-ref negative control, exit 0" }
      - { ac: Spec-AC-11, call: compliant, citation: "prompt-diet-ledger.sh:228 (656 B), test-aai-prompt-diet.sh want_growth 45517 + TEST-1215, suite-map.yaml row + hygiene pins 99->100, TEST-1216; prompt-diet exit 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_SHIP.prompt.md, line: 101,
          issue: "Spec Implementation plan item 4 (a STRICT RULES clause that a post-freeze amendment is not a HITL question) was not implemented; STRICT RULES still say scope HITL questions are NEVER auto-answered while ROLE_COMMON/6a still call an amendment a scope change",
          failure_scenario: "A downstream agent mid-ride outgrows the frozen spec, reads ROLE_COMMON 'Amending a frozen spec is a scope change' plus SKILL_SHIP STRICT RULES 'HITL questions ... (scope ...) are NEVER auto-answered' and resolves the conflict toward asking — the exact behaviour this scope removes; only the more specific AUTOPILOT DEFAULT 5 says otherwise" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_SHIP.prompt.md, line: 40,
          issue: "Step 1a presents the rationale text as if it were the gate's line ('admits with a `roadmap absent` line: `roadmap absent, gate not consulted (autopilot default)`') and says nowhere where it is recorded, while STRICT RULES line 100 says every autopilot decision is written to STATE (D5 narrowing leaves no STATE field)",
          failure_scenario: "An agent following 'every autopilot decision is written to STATE with its rationale' searches for a state.mjs mutator to record the skip, finds none, and either hand-edits STATE or drops the rationale; or it greps the gate output for the literal rationale string, which the gate never prints" }
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-select.mjs, line: 280,
          issue: "In the absent posture the gate exits before the --intake/--ref id-consistency usage check (line 327), so a malformed call is no longer malformed in both postures — D3's stated principle, though D3 enumerates only the three checks it moved",
          failure_scenario: "Probed: `gate --ref cap-one --intake <doc with id other-ref> --roadmap <absent>` exits 0 ADMIT; the same call with a roadmap present exits 2. A SKILL_SHIP ride that passes the wrong primary_path gets a clean ADMIT line carried into the step 6 summary" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-downstream-autopilot.sh, line: 40,
          issue: "mk_project runs `rm -rf \"$d\"`, mkdir and cp before its HAZ-CD absolute-path guard (line 74), mktemp success is unchecked, and log_fail inside `d=\"$(mk_project ...)\"` exits only the substitution subshell",
          failure_scenario: "If mktemp -d fails (TMPDIR unwritable) TEST_DIR is empty and `rm -rf /t1207-absent` runs before the guard; a guard failure inside the command substitution does not stop the test, which then continues with d='' until in_project's guard fires" }
  cannot_verify:
    - { claim: "Downstream agents actually stop asking roadmap/amendment questions (spec R1: prose pins prove sentences exist, not agent behaviour)",
        closes_with: "The owner's next real downstream /aai-ship ride transcript showing no mid-ride governance question" }
    - { claim: "The new suite and the TEST-1208 default-roadmap arm are green on the Ubuntu CI runner (only macOS runs observed)",
        closes_with: "skill-suite.yml CI run on the PR head, headSha-matched" }
    - { claim: "Full test-framework sweep is non-regressing (validation ran SELECTED+CORE only, intermediate round)",
        closes_with: "The one full sweep owed before the close ceremony (AAI_TEST_TIMEOUT=3000)" }
    - { claim: "Behaviour when the roadmap's parent directory is unsearchable (existsSync false on EACCES) — D2 says a permission error REFUSES, but this shape admits in both readers",
        closes_with: "A probe with chmod 000 on docs/ai, or acceptance under the same residual as R2" }
  overall: pass
```

## AC table walk

All 11 Spec-ACs compliant (citations in the block above). Evidence re-run by the reviewer on the current tree (unchanged since the validation report except the EVENTS append):
- `bash tests/skills/test-aai-ride-select.sh` exit 0
- `bash tests/skills/test-aai-downstream-autopilot.sh` exit 0
- `bash tests/skills/test-aai-spec-amend.sh` exit 0
- `bash tests/skills/test-aai-prompt-diet.sh` exit 0
- `node .aai/scripts/mutation-gate.mjs --spec <spec>` GATE PASS 16 rows, uncomparable=0
- `node .aai/scripts/spec-amend.mjs list --strict` exit 0 (this ride's amendment unsigned-tracked)
- `node .aai/scripts/check-vendored-script-deps.mjs` CLEAN

TEST-xxx: all 16 rows exist, are wired into `main()`, and carry a `verdict: RED` mutation record (the three dated non-RED records for TEST-1209/1215 are superseded attempts; the gate reads the undated ones).

Deviations from the frozen spec (listed even where reasonable):
1. Implementation plan item 4's SKILL_SHIP STRICT RULES clause is absent (NB-1). Not in any Spec-AC.
2. The spec was amended post-freeze (Test Plan Mutation anchors, disclosed and tracked). The record's claims match the spec text (verified against the cells).
3. The spec's AC Status table stays `planned` — deferred to the close ceremony per VALIDATION 8a; not a deviation of this diff.

## Findings

BLOCKING: none.

NON-BLOCKING (each with recommended disposition; the orchestrator records it):
- NB-1 `.aai/SKILL_SHIP.prompt.md:101` — missing STRICT RULES carve (plan item 4). Recommended: remediate-in-tree (half sentence, e.g. "a post-freeze spec amendment is not a HITL question (default 5)", plus a matching diet-ledger byte credit), or promote to follow-up (suggested: fu-ship-strict-rules-amendment-carve). Severity P3.
- NB-2 `.aai/SKILL_SHIP.prompt.md:40` — rationale text has no stated home. Recommended: remediate-in-tree together with NB-1 (reword 1a: "carry the rationale ... on the step 6 `ride gate:` line"). P3.
- NB-3 `.aai/scripts/ride-select.mjs:280` — --intake id mismatch not refused in the absent posture. Recommended: accepted residual (P3; the gate is by design not consulted, the dispatch never calls the CLI in that posture, and D3 enumerates the checks it moved), or remediate-in-tree by moving the mismatch check above the branch.
- NB-4 `tests/skills/test-aai-downstream-autopilot.sh:40` — guard ordering in the fixture builder. Recommended: remediate-in-tree (move the guard to the top of mk_project, check TEST_DIR after mktemp). P3.

INFO (no gate): the new suite adds a row to the cd-subshell-leak ratchet (`tests/skills/lib/cd-subshell-leak-baseline.tsv`); both occurrences are the standard `SCRIPT_DIR/PROJECT_ROOT="$(cd ... && pwd)"` idiom every sibling suite carries. The ledgers (decisions.jsonl +2, EVENTS.jsonl +3) are pure appends (numstat 0 deletions).

NB-1, NB-2 and NB-4 overlap the validator's NB-1..NB-3 (same defects, found independently); NB-3 is new.

## cannot_verify
See the block above: R1 agent behaviour, Ubuntu CI, the owed full sweep, the unsearchable-parent-dir shape of D2.

## Warning dispositions (H6)
None recorded yet — the orchestrator must name one artifact per NB-1..NB-4 in code_review.notes before closeout. If NB-3 is taken as (d): accepted residual: gate is not consulted in the absent posture by design; the id mismatch there has no downstream consumer and leaves no false record beyond the ADMIT line.

## Next steps
Overall pass. Remediate NB-1/NB-2/NB-4 in tree (cheap, one prompt edit + one test edit, then re-run prompt-diet and the new suite) or record their dispositions; then the PR step. Run the full sweep before close.
