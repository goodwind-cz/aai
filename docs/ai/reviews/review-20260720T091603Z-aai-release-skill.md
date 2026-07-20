```yaml
review:
  scope: main...HEAD (feat/aai-release-skill, HEAD 7219f2d) — /aai-release skill
  spec: docs/specs/SPEC-DRAFT-spec-aai-release-skill.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "aai-release.sh:218-246 plan-only branch (CONFIRM!=1); TEST-001/002 green; independent dry-run on real CHANGELOG rc=0, tree clean" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "aai-release.sh:262-283 cut sequence; TEST-003..008 green; independent full cut on real 35-block CHANGELOG — 35 rolled, bodies byte-identical (diff empty), 1 scaffold, single-path commit" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "aai-release.sh:68-77,202-260 fail-closed gates BEFORE mv(263); TEST-009..015 green; probes confirm zero writes on refusal" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "bash -n clean; no mktemp -t bare / no stat -f-first; version resolution TEST-017; ps1 twin present; TEST-016..019 green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "PROFILES.yaml core: +3 files (exactly aai-release.{sh,ps1}+SKILL_RELEASE.prompt.md); TEST-020 layer-profiles green; USER_GUIDE.md+CHANGELOG.md grep TEST-021; CI skill-suite 29729735223 success @ headSha==HEAD" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.sh, line: 156,
          issue: "A pre-existing bare '## [unreleased]' scaffold sitting ABOVE the entry blocks is preserved verbatim while a fresh scaffold is also inserted, yielding two consecutive empty '## [unreleased]' headings after a cut.",
          failure_scenario: "Manually-authored CHANGELOG with a bare '## [unreleased]' line then stacked '## [unreleased] — …' entries → after --confirm the file carries two adjacent bare scaffolds. Cosmetic only: no entry dropped/duplicated, bodies byte-preserved, next run correctly refuses (EMPTY). Does NOT occur with the repo's actual convention (entries stacked directly, no bare scaffold — verified on the live 35-block CHANGELOG: result had exactly 1 scaffold)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.ps1, line: 182,
          issue: "The .ps1 twin always re-joins output with LF ('`n'); a CRLF-lineended CHANGELOG would be silently normalized to LF (line-ending byte change), whereas the bash awk path carries the trailing CR through and preserves CRLF.",
          failure_scenario: "Windows operator with a CRLF CHANGELOG runs aai-release.ps1 --confirm → every line ending rewritten LF. RR-2 residual (pwsh functional parity is manual-only); repo CHANGELOG is LF so no impact on AAI itself. Bash gate unaffected." }
  cannot_verify:
    - { claim: "A real 'gh release create' + 'git push' to github.com succeeds end-to-end",
        closes_with: "Operator manual dogfood on first real cut (RR-1) — inherently unautomatable without an outward side effect; tests use only file:// bare remote + stub gh + --no-remote" }
    - { claim: "aai-release.ps1 is behaviorally equivalent to aai-release.sh at runtime",
        closes_with: "pwsh/Pester functional run (RR-2); current coverage is parse + static flag-parity grep (TEST-019) only" }
  overall: pass
```

# Code Review — Portable `/aai-release` skill (aai-release-skill)

**Scope:** `git diff main...HEAD` on `feat/aai-release-skill` (HEAD `7219f2d`).
**Spec:** `docs/specs/SPEC-DRAFT-spec-aai-release-skill.md` (SPEC-FROZEN, L2, hybrid).
**Reviewer context:** read-only on code/tests/config; wrote only this report.

## Diff scope preflight
STATE `worktree.user_decision: inline`; branch `feat/aai-release-skill` isolates the
work. Established scope = `main...HEAD` (2 commits). Working tree carries only the two
untracked DRAFT intake/spec docs (expected). Files reviewed: `.aai/scripts/aai-release.sh`,
`.aai/scripts/aai-release.ps1`, `.aai/SKILL_RELEASE.prompt.md`,
`.claude/.codex/.gemini/skills/aai-release/SKILL.md`, `.aai/system/PROFILES.yaml`,
`tests/skills/test-aai-release.sh`, `tests/skills/lib/prompt-diet-ledger.sh`,
`tests/skills/test-aai-prompt-diet.sh`, `docs/USER_GUIDE.md`, `CHANGELOG.md`,
`docs/INDEX.md`.

No dispatch coaching to record (the dispatch listed scrutiny areas but did not
pre-rate severity, characterize expected findings, or scope-exclude — full scope
reviewed).

## Verdict 1 — spec_compliance: PASS
Every Spec-AC row is compliant (see ac_walk). Independently re-verified beyond the
suite:
- **Byte-preservation on the real target.** A full `--confirm --no-remote` cut on a
  copy of the live 35-block `CHANGELOG.md`: all non-heading bodies **byte-identical**
  (`diff` empty), 35 `[unreleased] — …` → `[v1.0.0] — …`, 0 leftover entries, exactly
  **1** fresh scaffold, final `0a` newline preserved.
- **No-trailing-newline fidelity.** A CHANGELOG ending without `\n` rolled with the
  last byte still `62` ('b') — the `printf '%s' "$(cat OUT)"` idiom reproduces the
  missing-newline state (D1 step 5). The command-substitution-before-redirection
  ordering makes the in-place `> "$OUT"` safe (no truncation-before-read data loss).
- **Fail-closed ordering.** All D6 gates (dirty tree snapshotted at :82 before the
  script's own temp is created; existing tag; gh auth) run **before** the `mv`/commit/
  tag at :263-268, so every refusal leaves the tracked tree byte-identical — confirmed
  by TEST-009..015 and probes (CHANGELOG sha unchanged, no commit/tag).
- **CI evidence.** `skill-suite` run 29729735223 = success, `headSha==HEAD`,
  status completed (the enforcing Linux gate for AC-04/AC-05). Local
  `bash tests/skills/test-aai-release.sh` = all 21 PASS.

## Verdict 2 — code_quality: PASS
No BLOCKING findings. The outward-facing path is well-guarded:
- **Operator gate airtight.** The cut is reachable only when `CONFIRM==1 && DRY_RUN==0`
  (:52-54 force `--dry-run` to win; :218 gate). Bare invocation = plan-only. Unknown
  flags → exit 1 (no fallthrough that could set CONFIRM). The agent-facing prompt +
  wrappers explicitly forbid passing `--confirm` on the agent's initiative.
- **Remote never touched in tests.** `gh` is stubbed (records argv, never contacts
  github.com); push targets a local `file://` bare repo; `--no-remote`/env twin used
  elsewhere. TEST-007b is a real negative control (asserts the bare remote received
  nothing and gh was never invoked). SEAM-1 (TEST-006) is a genuine end-to-end
  assertion — the exact rolled-section bytes must arrive at the stub's `--notes-file`
  (re-derived independently), not a mock of the boundary.
- **Two NON-BLOCKING findings** (see block above): the double-scaffold cosmetic edge
  (does not arise under the repo's CHANGELOG convention) and the ps1 CRLF→LF
  normalization (RR-2 manual-parity residual). Neither drops/duplicates/corrupts an
  entry; neither gates.

## cannot_verify
- **RR-1** real `gh release create` + `git push` to github.com — manual operator
  dogfood; unautomatable without a real side effect.
- **RR-2** pwsh runtime parity — only parse + flag-grep covered.

## WARNING dispositions (H6)
Both NON-BLOCKING findings are advisory cosmetic/manual-residual items. Recommended
disposition: **promote-to-follow-up-ref** (a single low-priority ISSUE covering
"aai-release: dedupe stray pre-existing scaffold + ps1 line-ending preservation") OR
accept-as-known via `docs/ai/decisions.jsonl`. The orchestrator records the chosen
artifact; a read-only reviewer does not file it. Neither blocks merge/PR readiness.

## Observations (non-gating)
- `docs/INDEX.md` (auto-generated, "DO NOT EDIT") was regenerated (timestamp + the two
  new DRAFT rows) and is outside the declared `inline_review_scope`, but it is a benign
  mechanical regen reflecting the new intake/spec drafts — no code impact.
- Prompt-diet ledger true-up is consistent: `JUSTIFIED_GROWTH_BYTES` 9239→12339
  (+3100) matches the new `SKILL_RELEASE.prompt.md` ledger row and the independent
  re-sum guard (TEST-012); enforced green on the CI skill-suite.

## Next steps
- PASS both verdicts → review status **pass**. Safe to proceed to PR.
- Orchestrator: record the two NON-BLOCKING WARNINGs per H6 (follow-up ref or decision).
- Operator: on first real cut, run `--dry-run` first, review the plan, then `--confirm`
  (RR-1 is the only unverified real-publish path).
```
