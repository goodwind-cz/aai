```yaml
review:
  scope: 2f13ad79..4833ed55 (delta since r2; cumulative ride scope b6f740783f6df8885bfc49a56fb3b4225f7538e5..4833ed55)
  spec: docs/specs/SPEC-0233-spec-release-command-finish.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "release-finish.mjs audit unchanged in delta; TEST-001..003 (validation r8/r10)" }
      - { ac: Spec-AC-02, call: compliant, citation: "unchanged in delta; TEST-004/005" }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged in delta; TEST-006" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged engine; direct-run guard now proven on hosted win32 (ps1-quality.yml:274-283, run 39030229655); TEST-702" }
      - { ac: Spec-AC-05, call: compliant, citation: "hosted ps1-quality 39030229655 @4833ed55 success: Linux 156/0/0 + TEST033 completed=20 skips=0; Windows 5.1/pwsh7 152/0/4" }
      - { ac: Spec-AC-06, call: compliant, citation: "docs/product/release-command-finish.md:16,29,50,60 describe authorization, resume, skips, snapshot/race limits; claims checked against release-finish.mjs:23,119-185" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.sh, line: 73,
          issue: "Front-end origin detection now diverges: bash uses 'remote get-url origin', ps1 (aai-release.ps1:286) uses 'config --get remote.origin.url'",
          failure_scenario: "Repo whose origin has only remote.origin.pushurl (or only a fetch refspec, or a legacy .git/remotes/origin file) with gh authenticated: bash preview adds --online, ls-remote origin fails (rc 128) and preview refuses; ps1 preview runs the offline audit and reports ready to cut. Confirm refuses identically in both (engine identity() uses config --get)." }
      - { rank: NON-BLOCKING, file: docs/product/release-command-finish.md, line: 16,
          issue: "Hosted-proof sentence cites runs at d9b1648b/cbf0cdcd/ab70289e only; none is at the shipped head",
          failure_scenario: "A reader auditing the shipped aai-release.ps1 (origin check changed in e3b02a0d) and the direct-run proof follows the cited runs and finds neither; the run that covers the shipped bytes (39030229655 @4833ed55) is not named." }
  cannot_verify:
    - { claim: "PS 5.1 no-origin -DryRun now exits 0 (config --get writes no stderr, so no NativeCommandError)", closes_with: "Hosted 5.1 run of the no-origin preview; tracked fu-release-ps1-origin-check-ps51-test (P3). Locally verified only: config --get rc 1 with empty stderr; pwsh 7 under Stop does not throw" }
    - { claim: "Live GitHub semantics (required-check registration latency, gh run list --commit, squash title feeding release.yml)", closes_with: "First live /aai-release --confirm; fu-release-checks-registration-grace tracks the latency risk" }
    - { claim: "External race between final base observation and GitHub merge", closes_with: "Not closable client-side; disclosed spec limitation (product doc :58)" }
  overall: pass
```

# Independent Code Review r3 - release-command-finish

**Verdict: PASS.** Both r2 recommendations (NB-R2-1, NB-R2-2) are resolved in-tree and the delta introduces no BLOCKING defect. Two NON-BLOCKING P3 items, dispositions below.

## Scope

- Worktree `/Users/ales/Projects/aai-change-release-finish-one-command`, HEAD `4833ed55`, branch `change/release-finish-one-command`.
- Delta reviewed: `git diff 2f13ad79..4833ed55` (commits `e3b02a0d`, `4833ed55`): `.aai/scripts/aai-release.ps1` (+2 comment, 1 changed), `.github/workflows/ps1-quality.yml` (CR-3 step), `docs/product/release-command-finish.md`, r2 report, two `follow_up` appends in `docs/ai/decisions.jsonl`.
- Spec: `docs/specs/SPEC-0233-spec-release-command-finish.md`. Validation r10 PASS: `docs/ai/reports/VALIDATION-20261017T120212Z-release-command-finish.md`.
- Dispatch note: the prompt named areas to examine but did not pre-rate severity or exclude areas; no coaching recorded.

## r2 findings

| Finding | Status | Evidence |
|---|---|---|
| NB-R2-1 no win32 direct-run proof | **Resolved** | ps1-quality.yml CR-3 step runs `node .aai/scripts/release-finish.mjs --root $PWD --version v1 2>&1`, throws unless rc 20 and `REFUSED: confirmation`. Hosted run 39030229655 @4833ed55 success, printed `PASS: release-finish runs directly on win32`. Relative path vs r2's `Join-Path` suggestion is equivalent: Node path-resolves argv[1] before the guard; verified locally from repo root and from `.aai/` with `./scripts/...` (both rc 20 `REFUSED: confirmation`). Optional ps1 "rc 0 without complete line" hardening not taken; acceptable now that the guard is proven. |
| NB-R2-2 PS 5.1 stderr promotion | **Resolved (runtime proof pending, tracked)** | aai-release.ps1:286 `git -C $Root config --get remote.origin.url *> $null`. Verified: absent origin -> rc 1, empty stderr; present -> rc 0. Mirrors engine identity() at release-finish.mjs:330. No test pins it; filed `fu-release-ps1-origin-check-ps51-test` (P3), ledger-readable via `follow-ups.mjs list`. |

## `config --get remote.origin.url` vs bash `remote get-url origin`

Measured on git 2.54 in scratch fixtures (rc of get-url / config --get / `ls-remote --tags origin`):

| Origin shape | get-url | config --get | ls-remote |
|---|---|---|---|
| none | 2 | 1 | 128 |
| url | 0 | 0 | 0 |
| url via `url.<x>.insteadOf` | 0 | 0 | 0 |
| multi-valued url | 0 | 0 | 0 |
| empty url `""` | 0 | 0 | 128 |
| pushurl only | 0 | 1 | 128 |
| fetch refspec only | 0 | 1 | 128 |
| legacy `.git/remotes/origin` | 0 | 1 | 0 |

- `insteadOf` does not change the rc of either form (config returns the raw value, get-url the rewritten one; only rc is consumed). Multi-valued url returns rc 0 with no stderr, so no 5.1 promotion.
- Divergence exists only in degenerate shapes (pushurl-only, fetch-only, legacy remotes file). There the ps1 choice is the more coherent one (it matches what `--online`'s `ls-remote` can actually reach in the first two cases and matches the engine's identity check in all three); the bash front end is the odd one out. Confirm behaves identically through the engine. See NB-R3-1.
- The empty-url case goes `--online` in both front ends and refuses identically.

## CI step failure modes (ps1-quality.yml:274-283)

- Probe failure: explicit `if ($LASTEXITCODE -ne 0) { exit 1 }` (pwsh 7.4+ does not throw on native nonzero by default) - fails closed.
- Guard false on win32: rc 0, no output -> `throw` - fails closed.
- rc 20 for another cause (e.g. rev-parse failure): message mismatch -> `throw` - fails closed.
- `node` missing: CommandNotFound terminates under the template's `$ErrorActionPreference='stop'`.
- Success leaves `$LASTEXITCODE=20`; GitHub's pwsh epilogue would exit 20, hence `exit 0` (4833ed55). Correct and minimal; validation r10 reproduced the pre-fix failure and the negative controls in a template-wrapped local sim.
- Workflow triggers include `.github/workflows/ps1-quality.yml`, `aai-release.ps1` (`.aai/scripts/**.ps1`) and `release-finish.mjs`, so edits to any proven artifact re-run the step.

## Product doc accuracy (docs/product/release-command-finish.md)

- Runs 39016764123 (d9b1648b), 39020377328 (cbf0cdcd), 39022783097 (ab70289e): all `success` per `gh run view`. Claims true; none is at the shipped head (NB-R3-2).
- `#N`/title/rolled-heading accept paths match release-finish.mjs:168,177-178; `v?[0-9]` boundary filter matches :129; "tags that do not peel to a commit are ignored" matches :135 (present non-commit objects; missing objects still refuse, consistent with "unavailable history refuses").
- Version line matches `validTagVersion` and its placement before any `gh` call (:327-328).
- Follow-up ids cited in the limits paragraph exist and are open in the ledger.
- Removal of "hosted proof pending" text is justified by the hosted runs; the doc still states no live end-to-end release has run.

## Code-quality findings

No BLOCKING findings.

### NB-R3-1 - NON-BLOCKING (P3) - bash/ps1 origin detection diverge in degenerate origin shapes

- **Where:** `.aai/scripts/aai-release.sh:73` (`remote get-url origin`) vs `.aai/scripts/aai-release.ps1:286` (`config --get remote.origin.url`).
- **Failure scenario:** origin with only `remote.origin.pushurl` and gh authenticated: `aai-release.sh --dry-run` goes `--online`, `ls-remote origin` fails and the preview refuses; `aai-release.ps1 -DryRun` audits offline against local tags and reports ready to cut. `--confirm` refuses `identity` in both.
- **Recommended disposition: (d) accepted residual** - accepted residual: P3 front-end parity in pushurl-only/fetch-only/legacy-remotes origin shapes; preview-only, confirm path identical via engine identity(), no observed bite, no false record. If aai-release.sh:73 is touched later, align it to `config --get remote.origin.url`.

### NB-R3-2 - NON-BLOCKING (P3) - product doc hosted proof omits the head run

- **Where:** `docs/product/release-command-finish.md:16`.
- **Failure scenario:** the cited runs predate e3b02a0d/4833ed55 (ps1 origin check, direct-run proof); a reader cannot reach the run that covers the shipped bytes.
- **Recommended disposition: (a) remediate-in-tree** at the PR/product-docs step: append run 39030229655 (head 4833ed55) and the direct-run proof to the sentence. If skipped: accepted residual: P3 documentation precision; the cited runs are real and successful, no false record.

### INFO (no gate)

- CI step uses a cwd-relative script path rather than the ps1's `Join-Path $PSScriptRoot`; equivalent for the guard (argv[1] is resolved by Node).
- `decisions.jsonl` appends: ids 37/34 chars, shape matches existing follow_ups, both read back by `follow-ups.mjs list`.

## cannot_verify

1. PS 5.1 no-origin preview exits 0 - closes with a hosted 5.1 run of that case; tracked `fu-release-ps1-origin-check-ps51-test`.
2. Live GitHub semantics - closes with the first live `/aai-release --confirm`; `fu-release-checks-registration-grace`.
3. External base race at merge - not closable client-side; disclosed.

## Warning dispositions

- NB-R3-1: accepted residual (report line above).
- NB-R3-2: remediate-in-tree at product-docs/PR step; fallback accepted residual (report line above).

## Next steps

Orchestrator records the code_review block (command below), applies NB-R3-2 at the product-docs step if taken, then proceeds to PR.

```bash
node .aai/scripts/state.mjs set-code-review --required true --status pass \
  --scope "b6f740783f6df8885bfc49a56fb3b4225f7538e5..4833ed55" --base-ref b6f740783f6df8885bfc49a56fb3b4225f7538e5 \
  --report docs/ai/reviews/review-20261017T120447Z-release-command-finish-r3.md \
  --notes "r3 PASS on 2f13ad79..4833ed55; NB-R2-1/NB-R2-2 resolved. NB-R3-1 P3 bash/ps1 origin-detection parity: accepted residual: P3 front-end parity in pushurl-only/fetch-only/legacy-remotes origin shapes; preview-only, confirm path identical via engine identity(), no observed bite, no false record. NB-R3-2 P3 product doc omits head run 39030229655: remediate-in-tree at product-docs step (fallback accepted residual: P3 documentation precision; cited runs real and successful, no false record)."
```
