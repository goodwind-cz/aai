```yaml
review:
  scope: "origin/main...HEAD (ff32ec2e..15359acf) in /private/tmp/aai-adapter-slice, branch change/provider-adapter-registry-slice; r2 focus = remediation commit 15359acf"
  spec: docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unchanged since r1; sync-harness-skills.mjs --check 'OK: 6 shim(s) match the registry' rc=0; TEST-3001 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: ".github/copilot-instructions.md has zero '/aai-'; test-aai-harness-shims.sh:223-224 now asserts the whole file (stricter than the AC wording); TEST-3002 PASS; probe with a flush-left list FAILs it" }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged since r1; TEST-3003, TEST-3004 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged since r1; TEST-3005 PASS; TEST-3006 green log" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged since r1; TEST-3007/3008/3009 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged since r1; TEST-3010/3011 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "AUTONOMOUS_LOOP.md:97-104 names classify --record --signoff owner and not sign-merged; TEST-3012/3013 PASS; mutation-gate --spec 'GATE PASS: 14 row(s)' rc=0 (r1 STALE closed); spec-amend list --strict rc=0" }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged since r1; TEST-3014 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-harness-shims.sh, line: 223,
          issue: "TEST-3002 (name: lists_no_skills) now proves no '/aai-' anywhere in the shim, but a skill list in bare-name form ('aai-loop', '$aai-loop') still passes",
          failure_scenario: "a fragment edit adds 'Use aai-loop to run.' or '- aai-loop: run the loop' to the Copilot section; --check accepts it and TEST-3002 stays green (probe: appended 'Use aai-loop to run.' -> PASS). The drift that actually happened (9446fb87) used the '/aai-' form, which is now caught" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.sh, line: 191,
          issue: "r1 N2 (CRLF overrides block read empty, replaced under a false log line) — unchanged, filed",
          failure_scenario: "as in r1: CRLF target with a local block and no override file is replaced and logged 'no project overrides'" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/harness-shims.mjs, line: 172,
          issue: "r1 N3 (shipped list validated after the writes, stack trace on a bad row) — unchanged, filed",
          failure_scenario: "as in r1: malformed list row + --write writes trees and shims, then exits 2 with a stack trace" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.ps1, line: 135,
          issue: "r1 N4 (PowerShell normalisation wider than D4's N: BOM/Trim) — unchanged, accepted residual recorded below",
          failure_scenario: "as in r1: BOM-carrying historical shim -> pwsh replaces, bash merges (bash side keeps the text)" }
  cannot_verify:
    - { claim: "the owner's literal menu answer for #501 ('Mergni #501 (Recommended)'); the hitl_decision line is agent-written",
        closes_with: "owner confirmation or the session transcript (PR facts match gh pr view)" }
    - { claim: "Copilot, Cursor, Codex and Gemini read the regenerated shims as before",
        closes_with: "manual check per harness (spec Seams residual)" }
    - { claim: "aai-sync.ps1 on Windows PowerShell 5.1, and the new .gitattributes eol=lf pins on a Windows core.autocrlf=true checkout",
        closes_with: "CI Windows Pester leg green on the PR head" }
    - { claim: "the full sweep at 15359acf is green (the committed test-runs row 15:19:49Z shows 110/114 — taken before the F1 event fix)",
        closes_with: "the r2 validator's full-sweep log at 15359acf; the reviewer re-ran harness-shims, doc-numbering, deslop, docs-audit only" }
  overall: pass
```

# Code Review — provider-adapter-registry-slice (round 2)

security_relevant: false

- Scope: `git diff origin/main...HEAD` in `/private/tmp/aai-adapter-slice` (ff32ec2e..15359acf, 12 commits, 25 files, +2020/-69). The r2 delta is commit 15359acf. Its other changed files (r1 report, EVENTS, decisions, test-runs) are ledger and evidence only.
- Spec: `docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md` (frozen, L2, tdd).
- Reviewer: claude-opus-5-5 (implementer: claude-sonnet-5-5). I only read the worktree. Every command ran in disposable clones at 15359acf under `.../scratchpad/pa-cr-r2/{repo,probe}`, with the worktree's `docs/ai/tdd/` evidence and EVENTS copied in.
- Dispatch note (anti-gaming): the dispatch asked me to focus on whether the r1 findings were closed, and it described the remediation as the orchestrator sees it. It did not pre-rate severity or exclude any area. I re-walked every AC and the whole delta.

## Commands run (scratch clone at 15359acf)

| Command | Result |
|---|---|
| `mutation-gate.mjs --spec <spec>` | `GATE PASS: 14 row(s) satisfied degraded=0 unstamped=0 uncomparable=0`, rc 0 |
| `sync-harness-skills.mjs --check` | both OK lines, rc 0 |
| `docs-audit.mjs --check --strict` | `Verdict: CLEAN` |
| `spec-amend.mjs list --strict` | rc 0 |
| `spec-lint.mjs --path <spec>` | `LINT PASS`, rc 0 |
| `check-test-registration.mjs tests/skills` | rc 0 |
| `env -u AAI_ROLE bash tests/skills/test-aai-harness-shims.sh` | 13 PASS, rc 0 (run twice) |
| `test-aai-doc-numbering.sh`, `test-aai-deslop.sh`, `test-aai-docs-audit.sh` | rc 0 each (all three were red at r1 validation F1) |
| `follow-ups.mjs list --status open` | the three new ids are open, with the severities filed |
| `git ls-files --eol` on the six shims, `HARNESS_SHIMS.md` and `.aai/AGENTS.md` | all `i/lf w/lf attr/text eol=lf` |

## Closure of r1 findings

- **F1 (validation, BLOCKING): closed.** The `doc_lifecycle draft->draft` event is committed. docs-audit reads CLEAN, and the three formerly red suites pass in my clone.
- **B1 (BLOCKING): closed.** `test-aai-harness-shims.sh:223-224` counts `/aai-` over the whole file (`grep -c -F … || true`; a no-match gives `0`). Probe: appending ``- `/aai-loop` -> run the loop`` makes TEST-3002 FAIL ("still names a skill (/aai-) on 1 line(s)"). If the file is missing, grep prints nothing and the check passes, but the fragment loop that follows then fails, so the test still fails. One residual remains (R1 below).
- **AC-07 evidence gap: closed.** The mutation-gate exits 0, and the TEST-3013 record has been re-stamped.
- **N1: closed.** The new wording in `AUTONOMOUS_LOOP.md:97-101` matches `spec-amend.mjs:583-601`. A contract-class record with `owner_signoff:false` reads as signed once its ride is done and merged with `links.pr`. merge-cleanup writes no signature. The text no longer contradicts ROLE_COMMON or SKILL_SHIP.
- **N2: filed.** `fu-sync-sh-crlf-override-block` (P2, open). The disposition is (b).
- **N3: filed.** `fu-shim-list-validated-after-write` (P3, open). The disposition is (b).
- **N4: accepted residual** (see the line below).
- **Validation NB1 (CRLF): addressed.** `.gitattributes` pins the six shims and `HARNESS_SHIMS.md`. The bare patterns `AGENTS.md`/`CLAUDE.md`/… match at any depth, so `.aai/AGENTS.md` is pinned too. That file is already LF in the index, so nothing renormalises. This is harmless and consistent with the pins already in place.

## Spec compliance: PASS

All 8 Spec-AC are compliant (see the walk above).

Deviations from the frozen spec:
1. **Still undisclosed (carried from r1, deviation 3).** b0f8b4ab and 15359acf rewrote more of `AUTONOMOUS_LOOP.md` than D6 step 4 named. D6 step 4 replaces only the `sign-merged` sentence. The branch also removed the base text about `/aai-merge` step `sign-amendments` and "a lane or standing merge … signs nothing", and added the SPEC-0226 read-time sentence. The edit is correct: the old text described a step that no longer exists, and that error was the subject of N1. No AC is violated, because AC-07 only pins `classify --record --signoff owner` present and `sign-merged` absent. But `decisions.jsonl` has no amendment record for the wider edit. Recommendation: the orchestrator records it with `spec-amend.mjs add … --signoff none` (additive-with-disclosure) before the last pr_sweep.
2. The TEST-3002 assertion is stricter than the Spec-AC-02 wording (whole file vs. lines with two-space indent). It is a superset, so no amendment is needed. The Test Plan row text ("zero inline skill lines") still reads true.
3. Carried from r1 and unchanged, all disclosed: D6 step 3 `close` appended nothing (the trackers read done through the fold), and the edits to `test-aai-sync-seed.sh` and the hygiene-pack pins.

## Code quality: PASS (0 BLOCKING, 4 NON-BLOCKING)

**R1 — NON-BLOCKING (P3) — tests/skills/test-aai-harness-shims.sh:223.**
- The name `lists_no_skills` is now backed for the `/aai-` invocation form across the whole file. A bare-name list is not caught.
- Probe: appending `Use aai-loop to run.` gives TEST-3002 PASS.
- The check cannot simply forbid `aai-`, because line 27 legitimately says "use `aai-` prefix".
- This is an assurance-strength gap. It has not bitten: the 9446fb87 drift used the `/aai-` form.
- Disposition: `accepted residual: P3 TEST-3002 proves no '/aai-' token in the Copilot shim, not the absence of a bare-name skill list; no observed bite, the historical drift form is caught`. The alternative is a follow-up that counts `aai-[a-z]+` tokens other than the documented prefix sentence.

**N2, N3:** unchanged from r1. Both are filed as follow-ups (see closure above).

**N4 — NON-BLOCKING (P3) — .aai/scripts/aai-sync.ps1:121-151.** Unchanged.
`accepted residual: P3 PowerShell normalisation wider than N (BOM/Trim), conservative on the bash side, no false record`

INFO:
- The comment in the PowerShell twin still says it only deletes CR and trailing LFs. The comment fix that r1 offered as an alternative to N4 was not done. This is covered by the residual above.
- The committed `test-runs.jsonl` row (2026-10-25T15:19:49Z, 110/114) was recorded before the F1 event fix took effect. It is append-only telemetry, so it is correct to leave it as is.

## cannot_verify
1. The owner's literal menu answer for #501. The hitl line is agent-written; the PR facts match.
2. Whether each harness reads the regenerated shims as before (Seams residual).
3. Windows PowerShell 5.1, and the new eol=lf pins on a Windows autocrlf checkout. The CI Windows leg closes this.
4. A full sweep at 15359acf. I ran only the four suites listed above. The r2 validator's sweep closes this.

## Warning dispositions (H6)
- R1: (d) `accepted residual: P3 TEST-3002 proves no '/aai-' token in the Copilot shim, not the absence of a bare-name skill list; no observed bite, the historical drift form is caught`
- N2: (b) `fu-sync-sh-crlf-override-block` (filed, P2).
- N3: (b) `fu-shim-list-validated-after-write` (filed, P3).
- N4: (d) `accepted residual: P3 PowerShell normalisation wider than N (BOM/Trim), conservative on the bash side, no false record`

## Next steps
1. Orchestrator: record the deviation-1 amendment (the wider AUTONOMOUS_LOOP.md edit) with `spec-amend.mjs add`. Then re-run `spec-amend list --strict`.
2. Copy this report to `docs/ai/reviews/review-provider-adapter-registry-slice-r2-20261025T155447Z.md`, stage it with the next commit, and run the state command.
3. Do the r2 validation full sweep, the last pr_sweep, and the CI Windows leg.
