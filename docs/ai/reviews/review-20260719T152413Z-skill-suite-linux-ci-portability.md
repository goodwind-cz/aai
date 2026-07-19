---
review_for: skill-suite-linux-ci-portability
spec: docs/specs/SPEC-DRAFT-spec-skill-suite-linux-ci-portability.md
reviewer_role: code_review
head_sha: eedea6dd698aa522382758ba95b4ef14c9e9cc17
---

# Code Review — skill-suite-linux-ci-portability

```yaml
review:
  scope: "git diff main...HEAD -- tests/skills/ (fix commits 116b1df + eedea6d; 8 suites)"
  spec: docs/specs/SPEC-DRAFT-spec-skill-suite-linux-ci-portability.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-prompt-diet.sh:392 full-template mktemp; CI skill-suite 29692170768 success" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "orchestration-mode.sh:290-303 soft-skip on absent STATE_DOC; orchestration-dispatch.sh:1125-1138 guarded check-state; tdd-evidence.sh:98-124 self-seed; TEST-003/004 green on CI" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "doc-numbering.sh:80 + doc-number-reservation.sh:92 git init -q -b main; only mk_repo/setup_iso_repo call --base-ref main" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "test-aai-update.sh:245 stat -c first, stat -f fallback" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "CI run 29692170768 conclusion=success, headSha==HEAD eedea6d; macOS non-regression per validation last_validation.status=pass" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-run-tests.sh, line: 223,
          issue: "Reaper timing test relies on a fixed 5s wall-clock margin between fresh-sibling spawn and reaper etime sampling; margin widened (2s->5s) but flake is mitigated, not eliminated.",
          failure_scenario: "A severely throttled CI runner that stalls >5s between fresh_pid spawn and the reaper's ps snapshot would let the fresh sibling read as age>=5s and be wrongly reaped, tripping the 'concurrency guard violated' assert." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-tdd-evidence.sh, line: 108,
          issue: "Self-seeded legacy fixture is a hardcoded string; if the classifier's legacy-format (pre-RED_CLASS) detection criteria change, the stand-in could drift from a real legacy log and give false confidence on fresh checkouts.",
          failure_scenario: "Classifier tightened to require a marker not present in the hardcoded stand-in; TEST-005 would pass on the seeded fixture while the real legacy-log path silently loses coverage." }
  cannot_verify:
    - { claim: "On the authoritative Linux CI, the RC1 soft-skipped sub-checks (orchestration-mode TEST-016 schema-header grep; orchestration-dispatch TEST-012 repo-wide check-state OK gate) actually execute.",
        closes_with: "They do NOT run on CI — STATE.yaml is gitignored/absent on a fresh checkout, so both take the skip branch. They run only on a local dev checkout where STATE.yaml is present. CI green does not attest these two assertions; a local macOS run does." }
  overall: pass
```

## Scope and spec

- Scope: `git diff main...HEAD -- tests/skills/`, i.e. the 8 portability fixes in commits `116b1df` and `eedea6d`. Earlier CHANGE-0042 / framework-diagnostics commits on the branch were excluded from this review (already reviewed).
- Spec: `docs/specs/SPEC-DRAFT-spec-skill-suite-linux-ci-portability.md` (SPEC-FROZEN, ceremony_level 2).
- Anti-gaming note: the dispatch prompt directed attention at specific risk areas (soft-skip weakening, BSD/GNU correctness, reaper flake). Per the anti-gaming contract these are recorded as coaching hints; the full 8-file scope was reviewed regardless and no finding was suppressed or pre-rated on their basis.

## Authoritative Linux verification (independently confirmed)

`gh run list --branch feat/test-infra-reds-and-ci-gate --workflow skill-suite --limit 3`:
- Newest run **29692170768**: `conclusion: success`, `headSha: eedea6dd698aa522382758ba95b4ef14c9e9cc17` == current HEAD. Confirmed.
- Prior runs on 116b1df and 21a0291 are `failure` — consistent with the fixes only fully landing at eedea6d.

## Spec-AC walk (detail)

- **Spec-AC-01 (RC2 mktemp) — compliant.** `mktemp "${TMPDIR:-/tmp}/aai-wrapper-ceiling-fixture.XXXXXX"` uses the full-template form recommended by the spec; identical semantics on BSD and GNU (no `-t` prefix/template divergence). No residual `mktemp -t` remains in any scoped suite. `$fixture` is non-empty on Linux; downstream `> "$fixture"` / `wc -l` / `grep` succeed.
- **Spec-AC-02 (RC1 seed preconditions) — compliant.**
  - orchestration-mode TEST-016: `if [[ ! -f "$STATE_DOC" ]]; then log_info SKIP; return 0; fi` — the full grep block still runs when STATE.yaml is present. Assertion is NOT weakened for the present-file case; skip fires only on genuine absence. STATE_DOC resolves to the real gitignored repo path (`$PROJECT_ROOT/docs/ai/STATE.yaml`, line 30).
  - orchestration-dispatch TEST-012: `if [[ -f .../STATE.yaml ]]` guards the check-state gate; full check + `grep OK` run when present, skip only when absent. Same non-weakening property.
  - tdd-evidence: `check_deps` no longer hard-fails on `LEGACY_RED_LOG`; `ensure_legacy_red_log` (called after `setup_fixture`, so `$TEST_DIR` exists) self-seeds a representative legacy-format stand-in under `$TEST_DIR` only when the real file is absent, and uses the real file unchanged when present. Cleaned up by the existing TEST_DIR trap. No canonical-initializer/Constitution-Art.6 violation (no hand-written STATE stub).
- **Spec-AC-03 (RC3 resolvable main) — compliant.** `git init -q -b main` in the two local-fixture builders (`setup_iso_repo` doc-numbering:80, `mk_repo` reservation:92). Verified these are the ONLY builders whose repos are targeted by `allocate --base-ref main`; the remaining `git init -q` repos (reservation push_raw_ref:147, other-t003:217) build throwaway commits pushed to explicit refs and never allocate `--base-ref main` locally, and bare origins receive `main` via push. `-b main` requires git >= 2.28, satisfied on both ubuntu-latest and the macOS host (macOS non-regression + CI both green). RC3 fix is complete.
- **Spec-AC-04 (RC4 stat -c first) — compliant.** `stat -c '%u' ... 2>/dev/null || stat -f '%u' ... || true`. GNU `stat -c` yields the real uid on Linux; on BSD `stat -c` fails and falls through to `-f`. Correct on both platforms; fixes the prior ordering bug where GNU parsed `-f` as `--file-system`.
- **Spec-AC-05 (aggregate green) — compliant.** CI `skills` job `success` at HEAD (above); macOS non-regression recorded PASS by validation (`last_validation.status: pass`, CI 39/39 green, headSha match).

TEST-001..009 evidence: TEST-002..007 and TEST-009 attested by the CI `skills` job `conclusion: success`; TEST-001/TEST-008 additionally covered by the recorded macOS non-regression run. All claimed TEST-xxx map to real suites in the diff.

## Reaper margin — both assertions confirmed live

TEST-006 and TEST-015 each still assert BOTH directions after the 3s->8s sleep / 2s->5s threshold widening:
- old/matched tree (`~8s > 5s`): `alive ... && log_fail "reaper failed to reap ..."` — still fails if the old process survives.
- fresh sibling (`~0s < 5s`): `alive ... || log_fail "reaper killed a FRESH sibling ..."` — still fails if the fresh process is reaped.
The change widens headroom on both sides symmetrically; it strengthens robustness rather than weakening either assertion. Residual flake risk is captured as NON-BLOCKING finding #1 (inherent to a wall-clock timing test; the spec itself records this as an accepted residual risk). Minor added cost: ~10s extra runtime across the two tests.

## Warning dispositions (SPEC-0013 H6)

Both findings are NON-BLOCKING. Recommended disposition for the ORCHESTRATOR to record (a read-only reviewer does not file refs):
- Finding #1 (reaper residual flake): promote-to-follow-up-ref OR record as a `decisions.jsonl` accepted-residual-risk entry — it restates the spec's already-documented residual risk (Seam analysis / Residual risk section). Lowest-friction: a decisions.jsonl note referencing the spec's residual-risk clause.
- Finding #2 (tdd-evidence self-seed drift): record as a `decisions.jsonl` note or a low-priority techdebt follow-up ref; no action needed unless the classifier's legacy-format criteria change.

The `cannot_verify` entry (RC1 soft-skips are no-ops on CI) is not a defect — it is an honest coverage boundary the spec accepts (degrade-and-report, Spec-AC-02). It does not block, but merge readiness should acknowledge that the schema-header and repo-wide check-state sub-assertions are exercised only on a local dev checkout, never by the Linux gate.

## Overall

Both verdicts PASS. No BLOCKING findings. No assertion was weakened to pass: every soft-skip runs the full check when the (genuinely gitignored) file is present and skips only on real absence; both reaper directions remain live. BSD/GNU correctness of the mktemp/stat/git-init fixes holds on both platforms (CI Linux green + recorded macOS non-regression). Two NON-BLOCKING findings and one cannot_verify coverage note recorded for orchestrator disposition.
