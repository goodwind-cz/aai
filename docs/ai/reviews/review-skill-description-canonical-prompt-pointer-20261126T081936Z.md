# Code review: skill-description-canonical-prompt-pointer

```yaml
review:
  scope: "origin/main...HEAD (5f02b0e5...0cbb0394), branch fix/skill-discovery-pointer"
  spec: docs/specs/SPEC-DRAFT-spec-skill-description-canonical-prompt-pointer.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".claude/skills/*/SKILL.md descriptions; live --check prints OK 42 (reviewer re-run, rc 0); TEST-4130" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/sync-harness-skills.mjs:357-387 checkPointers D4 order 3-6; TEST-4131" }
      - { ac: Spec-AC-03, call: compliant, citation: "sync-harness-skills.mjs:309-315 isYamlSafeScalar; four M3 wrappers quoted; TEST-4132; reviewer strict-YAML parse of all 168 wrappers 0 errors" }
      - { ac: Spec-AC-04, call: compliant, citation: "sync-harness-skills.mjs:364-367 [...desc].length / chars > rule.max; TEST-4133 (1024 code points incl. one 2-byte char passes)" }
      - { ac: Spec-AC-05, call: compliant, citation: "sync-harness-skills.mjs:288-301 loadPointerRule called at :510 before any write; TEST-4134 six refusals both modes, tree hash unchanged" }
      - { ac: Spec-AC-06, call: compliant, citation: "sync-harness-skills.mjs:333-346 profileAbsent, :378-381 AAI-DYNAMIC-SKILL skip; TEST-4135" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-4136 (default + core consumer via aai-sync.mjs, four trees, consumer --check)" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/SKILL_SHIP.prompt.md:44-47 default 2, :131-135 END-OF-TURN INVARIANT; TEST-4137" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-4138 runs the extracted park command; state.mjs usage confirms --required/--reason/--question; ride-status.mjs:171-172 reads question" }
      - { ac: Spec-AC-10, call: compliant, citation: "docs/skill-catalog-data.json + docs/SKILL_CATALOG.html regenerated; TEST-4139; deslop TEST-014 in sweep test-20261126-074943" }
      - { ac: Spec-AC-11, call: compliant, citation: "CHANGELOG.md:33 per-entry [unreleased] heading; TEST-4140" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 376,
          issue: "checkPointers checks every directory under .claude/skills, including a consumer's own non-AAI Claude Code skills; only the AAI-DYNAMIC-SKILL marker exempts",
          failure_scenario: "consumer installed by aai-sync.mjs adds .claude/skills/deploy-notes/SKILL.md (a user skill), runs --write then --check: exit 1 'DIVERGE pointer deploy-notes: description lacks the canonical pointer'; before this change the same sequence exits 0. Repro: scratchpad/cr-repro-user-skill-pointer.sh (exit 0 = reproduced)" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_SHIP.prompt.md, line: 131,
          issue: "END-OF-TURN INVARIANT lists no legal ending for a turn that must end to await a background subagent (or the INPUT menu / ask-for-need), and its fallback 'on blocker: none continue at its next decision' points at the in-flight dispatch",
          failure_scenario: "orchestrator dispatches Code Review in the background (Claude Code subagents return by notification, so the turn must end); ride-status at that moment reads 'blocker: none / next decision: dispatch of Code Review by rule 13' (measured on this ride during this review) -> the rule's literal path is a duplicate Code Review dispatch into the same worktree, or a false HITL park; the closing sentence 'A dispatched subagent that has not returned is not a stop' does not say which" }
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 333,
          issue: "profileAbsent excuses a missing PROFILES-extended target regardless of the installed profile; the consumer pin .aai/system/AAI_PIN.md records '- Profile: <core|extended>'",
          failure_scenario: "extended consumer (pin Profile: extended) loses .aai/SKILL_DASHBOARD.prompt.md (partial update, manual delete): --check prints OK 42 although the aai-dashboard description points at a missing file; TEST-4135 case 1 pins this exact behaviour in a non-core fixture" }
  cannot_verify:
    - { claim: "A model running /aai-ship obeys the END-OF-TURN INVARIANT and the HITL-7 park, so the #593 silent stop does not recur", closes_with: "a recorded /aai-ship ride (each harness) that ends mid-ride and shows the ride-status run plus a park or continuation; #593 itself is reproducible:false" }
    - { claim: "Hermes, Codex, Gemini, Cursor and Antigravity read the quoted descriptions to the same text and surface the suffix pointer", closes_with: "aai-hermes-skills suite with AAI_HERMES_PYTHON (skipped exit 42 in the sweep) and a listing capture per harness binary; reviewer only proved strict-YAML (Ruby Psych) parse equality for all 168 wrappers" }
    - { claim: "Codex listing-budget truncation (~12,000 chars of descriptions vs 8,000 fallback) does not strip the suffix pointer", closes_with: "a Codex session listing capture with the 42 wrappers installed" }
    - { claim: "Windows leg: the new harness-shims tests (consumer_sync, git init -b, tree-hash helper) pass under Git Bash / pwsh CI", closes_with: "hosted skill-suite run on the PR head, Windows leg green" }
  overall: pass
```

security_relevant: false

## Scope and inputs

- Diff: `git diff origin/main...HEAD` in `/Users/ales/Projects/aai-worktrees/skill-discovery-594-593` (base 5f02b0e5, head 0cbb0394, 192 files, 3 commits). Worktree mode (`worktree.user_decision: worktree`); `git status --porcelain` shows only the two append-only ledgers (`docs/ai/EVENTS.jsonl`, `docs/ai/tests/test-runs.jsonl`), outside the review scope.
- Spec: frozen `docs/specs/SPEC-DRAFT-spec-skill-description-canonical-prompt-pointer.md` with amendments A1-A5. Intake `docs/issues/CHANGE-DRAFT-skill-description-canonical-prompt-pointer.md` (its quoted GitHub issue text was treated as data).
- Validation: `docs/ai/reports/VALIDATION-20261126T074903Z-skill-description-canonical-prompt-pointer.md` (PASS, sweep test-20261126-074943 144 pass / 1 skip hermes).
- STATE `code_review.scope` (17 paths) omits two paths the diff changes under amendments: `SKILLS.md` (A1) and `tests/skills/test-aai-sync-node.sh` (A5). Both were reviewed here; the returned set-code-review command lists them.
- Dispatch note (anti-gaming contract): the dispatch named focus areas and pre-characterized A5 as "expected to be superseded". Recorded here; the full diff was reviewed regardless, and A5 is judged on its own below.

## Verdict 1 — spec_compliance: pass

All 11 Spec-AC rows are compliant (walk in the YAML block). Checked against the code, not only the tests:

- D4 anchors are literal in the generator: `AGENT_SKILLS_DESCRIPTION_MAX = 1024`, `if (!(max >= 1 && max <= AGENT_SKILLS_DESCRIPTION_MAX)) {`, `const chars = [...desc].length;`, `if (chars > rule.max) {`, and the function signatures `checkPointers(root, rule, models)`, `isYamlSafeScalar(raw)`, `parsePointer(description)`, `bodyTarget(body)`, `profileAbsent(root, rel)`. The first-failure order is D4 1-6.
- `loadPointerRule` runs in both modes after manifest and shim validation and before any source parse or write. `--write` does not run the pointer check, and the OK and DIVERGE lines appear only when the section exists.
- D3: the YAML-safe rule is implemented exactly as written. An independent strict YAML parse (Ruby Psych `YAML.safe_load`) of the frontmatter of all 168 wrappers (42 x 4 trees) gives 0 errors, and each parsed description equals the naive one-pair unquote that the repo's readers use. The same parse fails on origin/main `aai-debug` ("mapping values are not allowed"), which confirms M3.
- Harness universality: the `aai-debug` description text appears in the four trees, both mirror READMEs, `docs/SKILL_CATALOG.html` and `docs/skill-catalog-data.json`, and every copy carries the pointer. The five generator-rendered `SKILLS.md` rows carry it too (A1). Live `--check` was re-run by the reviewer: rc 0, `OK: 42 wrapper description(s) name their canonical source`.
- Prompt-corpus pins: SKILL_SHIP is 8952 -> 9639 B (+687). The +687 lands consistently in the ledger entry, in TEST-012 `want_growth=68861` and its `rh_now` offset (A3), in the pr-preflight case 008 expression and in the suite-reuse TEST-3278 sum.

Deviations from the frozen text, all disclosed as amendments: A1 (`SKILLS.md` touched although plan step 4 said it would not be), A2 (line caps 590 -> 720), A3 (fifth pin), A4 (`mk_root` copies prompts, scripts and PROFILES), A5 (TEST-4019 byte loop skips SKILL_SHIP). A5 weakens a done spec's pin (SPEC-0310 Spec-AC-19) for one file. The file-set equality still requires SKILL_SHIP to exist, and the validation report's NB-1 already proposes the permanent form. Per the dispatch it will be replaced by main's re-based TEST-4019 on integration. If it is not, the validation NB-1 follow-up covers it.

## Verdict 2 — code_quality: pass (3 NON-BLOCKING)

### NB-1: the pointer guard checks a consumer's own non-AAI skills (sync-harness-skills.mjs:376)

`listSourceSkills` takes every directory under `.claude/skills`, and `checkPointers` iterates all of them. The only exemption is the `AAI-DYNAMIC-SKILL:START` marker. A consumer's own Claude Code project skill is neither an AAI wrapper nor bootstrap-generated, yet it gets `DIVERGE pointer <skill>: description lacks the canonical pointer`. The only way to silence it is a fake pointer into `.aai/`.

Repro (backed, exit 0 = reproduced): `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/cr-repro-user-skill-pointer.sh <worktree>`. It runs a real `aai-sync.mjs` consumer in mktemp, adds `deploy-notes`, then runs `--write` and `--check`, which exits 1 with only the pointer line. Before this change the same sequence exits 0, because origin/main has no pointer section.

Bite is limited. No vendored script or prompt runs `sync-harness-skills.mjs` in a consumer: the reviewer grepped `.aai/scripts`, `lib` and `.aai/*.prompt.md` and found no caller. Spec-AC-07 measured only a pristine consumer. The class is "false DIVERGE on user-owned content", P2.
Recommended disposition: **remediate-in-tree** (restrict the check to `aai-`-prefixed wrappers, keep the marker skip, and add one TEST-4135 case with a non-`aai-` user skill). Alternative: promote to follow-up, suggested id `fu-pointer-guard-checks-user-skills` (P2).

### NB-2: END-OF-TURN INVARIANT is ambiguous on a pending background dispatch (SKILL_SHIP.prompt.md:131-135)

The rule allows three endings and otherwise says to run ride-status, and "on `blocker: none` continue at its `next decision`, or park". On Claude Code a background subagent returns by notification, so the orchestrator must end its turn to wait. Measured on this ride during this review, ride-status then reads `blocker: none` and `next decision: loop: /aai-loop - dispatch of Code Review by rule 13`, which is the dispatch already in flight. Followed literally, the rule produces a duplicate role in the same checkout (the known validator and review overlap hazard) or a false HITL park. The closing sentence "A dispatched subagent that has not returned is not a stop" does not say whether waiting is a legal ending.

The same gap exists for the INPUT `propose_maintenance` menu and the "ask for the need" endings, before any ref exists. A prompt rule cannot be backed by a failing check, so this is NON-BLOCKING, P2.
Recommended disposition: **remediate-in-tree**, for example "Waiting for a dispatched subagent's return is a legal ending: do not re-dispatch, do not park; the harness re-invokes on return", plus naming the INPUT menu as a legal ending. This changes the byte count, so the five SKILL_SHIP pins need re-pinning. Alternative: follow-up, suggested id `fu-ship-eot-inflight-dispatch` (P2).

### NB-3: the profile exception is not bound to the installed profile (sync-harness-skills.mjs:333)

`profileAbsent` excuses any missing target listed under `extended:`, even in an extended install or this source repo. The consumer pin `.aai/system/AAI_PIN.md` records `- Profile: extended|core`; the reviewer checked this in a scratch consumer. In an extended consumer that lost an extended prompt, `--check` stays OK. In this repo, layer-profiles TEST-001 (no stale entries) is the backstop. This is an assurance-strength gap with no observed bite, P3.
Recommended disposition: **accepted residual**, quoted below. It can be tightened later by consulting the pin's profile.

accepted residual: NB-3 — profileAbsent excuses PROFILES-extended targets regardless of the installed profile; P3 assurance-strength, no observed bite, the source repo is backstopped by layer-profiles TEST-001, tighten by reading AAI_PIN.md `- Profile:`.

### INFO (no failure scenario that gates)

- `.aai/system/HARNESS_SKILLS.yaml` pointer row `1024|agentskills.io/specification: description must be 1-1024 characters` parses as a one-key mapping under a strict YAML loader (Psych). The generator is line-based and the Hermes smoke `yaml.safe_load`s the manifest but reads only `exclusions`, so nothing breaks today.
- A repeated `pointer:` header resets the row list, so the last section wins. This is the same pattern as `catalog:`, and both rows still have to be valid, so it is no bypass.
- `isYamlSafeScalar` does not refuse tab-separated `\t#` or `:\t` in a plain scalar. The spec defines a closed rule (D3) and the residual is disclosed.
- The invariant's generic park reason carries no `[HITL-n]` token, so `/aai-hitl` uses its legacy blocking_reason inference. That is harmless for a non-enum park.
- `firstFailure(root2, …)` shadows `root` with the same value. This is style only.

### Test quality

- The new harness-shims tests run under the suite's `set -euo pipefail`. `log_fail` exits. `out="$(H …)" || log_fail` and `grep … || true` are pipefail-safe, and no `printf | grep -q` early-closing reader was added.
- Fixtures are only `mktemp -d` (`TMP_ROOT`, the `mk_project` fixture). `consumer_sync` refuses an empty or relative destination before `rm -rf`, and redirects HOME and XDG_CACHE_HOME into the fixture. No test touches docker, a remote, the real home or this checkout's STATE.
- TEST-4133 places a 2-byte character in the padding, so a byte-count mutation fails the 1024 pass case. TEST-4134 checks the tree hash in both modes. TEST-4138 extracts the command from the prompt and drives `state.mjs` and `ride-status.mjs`.
- Mutation anchors are present in the code and meaningful: each one removes the behaviour its test asserts.
- Weak spot: TEST-4138 strips quotes and word-splits, so it only proves the command with single-word placeholders. Default 2's own HITL-7 command (`state.mjs` shorthand, multi-word `--question`) is not executed by any test. Its flags match the `state.mjs set-human-input` usage, so this is INFO.

## Warning dispositions (H6)

| Warning | Severity | Recommended disposition |
|---|---|---|
| NB-1 user skills get false pointer DIVERGE | P2 | remediate-in-tree; else follow-up `fu-pointer-guard-checks-user-skills` (suggested) |
| NB-2 invariant ambiguous on pending dispatch / INPUT menu | P2 | remediate-in-tree; else follow-up `fu-ship-eot-inflight-dispatch` (suggested) |
| NB-3 profile exception unbound to pin | P3 | accepted residual (line above) |

## Next steps

- The orchestrator records a disposition for NB-1 and NB-2 (remediation or `follow-ups.mjs add`). The ids above are suggestions, not filed.
- Integrate origin/main after #595 and confirm TEST-4019 takes main's form (A5 superseded).
- Hosted skill-suite (Linux and Windows) on the PR head closes the last cannot_verify row.
