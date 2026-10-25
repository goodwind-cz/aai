# Code Review r2: implied-signing-without-links-pr

```yaml
review:
  scope: origin/main...HEAD (72a8c2ea...5e34e7b8), worktree /private/tmp/aai-implied-sign, branch change/implied-signing-without-links-pr; focus on r1 closure (d9c5d193)
  spec: docs/specs/SPEC-0254-spec-implied-signing-without-links-pr.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/spec-amend.mjs:390-398,462-473; TEST-3017 + TEST-3023 green (scratch clone run rc=0)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/spec-amend.mjs:393-394 shallow guard, :387 SQUASH_PR_SUFFIX; TEST-3018..3021 + TEST-3026 green; TEST-3026 mutation RED (mutation-TEST-3026.txt)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-3022 green: 10 keys signed, totals 400/142/2/0/0 against 72a8c2ea" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "docs/ai/decisions.jsonl hitl_decision + 4 owner classifications + follow_up_status done; TEST-3024 green; list --strict rc 0" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/system/AUTONOMOUS_LOOP.md 6a; TEST-3025 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 395,
          issue: "The shallow guard is the only history-completeness check. git log also honours local replace refs (git replace, git replace --graft) and the legacy .git/info/grafts file, which can make a commit look parentless or rewrite its subject while --is-shallow-repository still prints false.",
          failure_scenario: "Fixture A (done doc by direct push, then tip `chore: tip (#5)`): `git replace --graft HEAD` reads signed (full clone without it reads unsigned); writing the tip sha to .git/info/grafts reads signed; `git replace <doc-commit> <copy with subject feat: forged (#9)>` reads signed. All three need local write access to the repository's .git; none travels through clone/fetch with default refspecs (actions/checkout fetches heads and tags only), and the same actor could append an owner_signoff:true record directly. Severity P3." }
  cannot_verify:
    - { claim: "No CI or downstream checkout fetches refs/replace/* or carries an info/grafts file, so the NB above cannot bite in a gate run.",
        closes_with: "a survey of downstream CI fetch refspecs, or `git --no-replace-objects` on the log spawn plus a grafts check, which makes the question moot for replace refs" }
    - { claim: "The owner actually answered 'Mergni #502 (Recommended)' (carried from r1; the hitl_decision line is written by the orchestrator).",
        closes_with: "the orchestrator transcript or session journal entry showing the owner's menu answer" }
    - { claim: "The two post-freeze contract amendments of this ride (shallow guard, TEST-3026 anchor) are owner-acceptable; they read unsigned-tracked under fu-amend-implied-signing-without-5734a3 and owe the owner's sign-off at merge.",
        closes_with: "the owner's merge of the PR with the amendments disclosed in the PR body (the seam under review then signs them)" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Range `origin/main...HEAD`, 9 commits, 11 files. Remediation commit `d9c5d193`, telemetry `5e34e7b8`. Worktree has one unrelated modification (`docs/ai/EVENTS.jsonl`, uncommitted telemetry); the review reads the committed range only.
- Spec: `docs/specs/SPEC-0254-spec-implied-signing-without-links-pr.md`, frozen, amended (frozen_sha256 restamped in d9c5d193).
- Dispatch coaching check: the dispatch named probe ideas for the false-signature question and asked for focus on r1 closure. It did not pre-rate severity or predict findings. The full range was walked; the AC table walk covers every row.

## r1 closure

| r1 item | Status | Evidence |
|---|---|---|
| BLOCKING 1 (shallow boundary commit read as the merge) | closed | `squashPrFromBase` returns null unless `git rev-parse --is-shallow-repository` exits 0 and prints exactly `false` (spec-amend.mjs:393-394). TEST-3026 covers full and depth-1 clones of a direct-push repo plus a positive control. RED log `red-TEST-3026.log` shows `got 'signed true done'` on the pre-fix tree; the mutation record removes the guard and reads RED. The guard fails closed on old git (unknown flag echoes, not `false`), on an error, and on a worktree of a shallow repository. |
| Spec disclosure of the new arm | closed | D1, D2, Spec-AC-02 row and Verify line, residual-risk line and TEST-3026 row amended; two contract `spec_amendment` records (`--signoff none`) tracked by `fu-amend-implied-signing-without-5734a3`. D1 states only what the guard compares and adds one caveat, which matches the guard. |
| F2 `$(cd …)` in three fixtures | closed | rewritten as `( cd … > file )`; `check-cd-subshell-leak.mjs` reports UNSAFE 0. |
| NON-BLOCKING 2 (record order vs merge) | recorded | `fu-implied-sign-ignores-record-order` (P2) is in `docs/ai/decisions.jsonl`, source the r1 report. |
| r1 report staging | done | the r1 report is committed in d9c5d193. |

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | spec-amend.mjs:462-473 (`checkRideMerged`) with :390-398. TEST-3017, TEST-3023 pass. |
| Spec-AC-02 | compliant | Every enumerated arm reads unsigned, including the new shallow arm. TEST-3018 to TEST-3021 and TEST-3026 pass. |
| Spec-AC-03 | compliant | TEST-3022 passes on the real history at 72a8c2ea. |
| Spec-AC-04 | compliant | TEST-3024 passes; `list --strict` exits 0 in the scratch clone. |
| Spec-AC-05 | compliant | TEST-3025 passes. |

TEST evidence: every TEST-3017 to TEST-3026 has a green log; red logs exist where the RED plan says they do; mutation records exist for all ten rows; `mutation-gate.mjs` prints `GATE PASS: 10 row(s) satisfied`. `spec-lint --path` on the spec: LINT PASS (the TEST-3026 mutation cell's `\|` does not break the table parser).

Deviations from the frozen spec. All are disclosed through amendment records:
- The shallow guard (D1/D2/Spec-AC-02, contract class, unsigned-tracked).
- The TEST-3026 mutation cell re-spelled with escaped parentheses (contract class, unsigned-tracked). This edit only touches a test-plan cell; classing it `contract` is conservative and costs one more owner sign-off line.
- The r1 deviations (TEST-3023 measurement re-anchor, D4 step flags) stand as recorded in r1.

## False-signature probes (real git fixtures, scratch only)

Fixture A: done doc with empty `links.pr` landed by direct push (`chore: direct`), then tip `chore: tip (#5)` touching another file. Correct reading: unsigned. Fixture B: doc committed as `feat: ride (#77)`. Correct reading: signed.

| Probe | Result | Verdict |
|---|---|---|
| A full clone | unsigned | correct |
| A `--depth 1`, `--depth 2` | unsigned | correct (r1 F1 closed) |
| A `--depth 1`, then `fetch --unshallow` | unsigned | correct |
| A `--depth 1` with `.git/shallow` deleted by hand | unsigned (`git log` exits 128, cannot read parent) | fail closed |
| Worktree of a depth-1 clone of A | unsigned (`--is-shallow-repository` prints true in the worktree) | correct |
| A `--filter=blob:none` partial clone | unsigned, not shallow | correct: trees are present, path diff needs no blobs |
| A `--filter=tree:0` partial clone | unsigned | correct (trees fetched lazily from the promisor) |
| `GIT_DIR` pointing at a shallow clone from a full checkout, and the reverse | unsigned | consistent: every spawn inherits the same env, so the guard and the log read the same repository |
| `GIT_DIR=/nonexistent` | unsigned | fail closed |
| `log.follow=true` in config | unsigned | correct; `-1` picks the newest touching commit either way |
| B squash, then a direct-push rename of the doc | unsigned | fail closed (newest touching commit is the rename) |
| Draft by direct push, PR `(#8)` renames and flips to done | signed | correct |
| Direct-push done doc, later PR `(#12)` only renames it | signed | declared residual ("a later PR that touches an older done ride doc") |
| A + `git replace --graft HEAD` (tip parentless) | **signed** | NON-BLOCKING finding |
| same with `GIT_NO_REPLACE_OBJECTS=1` | unsigned | `--no-replace-objects` would close this one |
| A + tip sha in `.git/info/grafts` | **signed**, even with `GIT_NO_REPLACE_OBJECTS=1` | NON-BLOCKING finding |
| A + `git replace` of the doc commit with a forged `(#9)` subject | **signed** | NON-BLOCKING finding |

## Findings

### NON-BLOCKING 1 (P3): local replace refs and grafts can fake a parentless commit or a subject
`.aai/scripts/spec-amend.mjs:395`. The guard checks shallowness only. A local `git replace --graft`, a legacy `.git/info/grafts` entry or a `git replace` of the doc commit makes `git log -1 --first-parent -- <rel>` return a subject that the real history does not have, while `--is-shallow-repository` prints `false`. The scenarios are in the probe table.

The bite needs write access to the repository's `.git`. Replace refs and grafts do not travel through clone or fetch with default refspecs, and an actor with that access could append an `owner_signoff: true` record directly. The spec's D1 says the guard covers shallowness only. So this is a guard weaker than ideal, with no observed bite and no false record left behind.

Recommended disposition: (d) `accepted residual: local replace refs and info/grafts can fake the subject read by squashPrFromBase; they need write access to .git, do not travel through clone/fetch with default refspecs, and that actor can already write an owner record directly`. An optional cheap remediation: spawn the log as `git --no-replace-objects log …`, which closes replace refs and `replace --graft` but not `info/grafts`. If that is done, D1/D2 need one more disclosed amendment, so accepting the residual costs less.

### INFO
- `isDone` in the index entry is still unused by `checkRideMerged` (carried from r1).
- `_sq_read` writes `.sq-read.json` into the fixture clone. It is harmless; the fixture is disposable.
- This ride's amendment records use ref_id `spec-implied-signing-without-links-pr`, while the TEST-3023 measurement record uses `implied-signing-without-links-pr`. Both resolve to the same doc through the index keys. The tracker is open, as it should be before merge.

## Warning dispositions (H6)
- NON-BLOCKING 1: recommended (d), with the `accepted residual:` line quoted above. The orchestrator records it in `code_review.notes`; this reviewer files nothing.

## Next steps
1. The orchestrator copies this report to `docs/ai/reviews/review-implied-signing-without-links-pr-r2-20261025T210133Z.md` and stages it with the next commit.
2. The PR body discloses the two post-freeze contract amendments so that the owner's merge signs them (`fu-amend-implied-signing-without-5734a3`).
3. No re-review needed unless the optional `--no-replace-objects` remediation is taken.

## Evidence run by the reviewer
- `git clone --no-local /private/tmp/aai-implied-sign <scratch>/clone && env -u AAI_ROLE bash tests/skills/test-aai-spec-amend.sh`: rc=0, 81 PASS lines, `All aai-spec-amend tests passed`, TEST-3017 to TEST-3026 PASS.
- In the scratch clone (tdd evidence copied in): `mutation-gate.mjs --spec <spec>` printed GATE PASS with 10 rows; `spec-lint.mjs --path <spec>` printed LINT PASS; `check-cd-subshell-leak.mjs` reported UNSAFE 0; `spec-amend.mjs list --strict` exited 0.
- Probe script: `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/is-cr-r2/probe.sh`. Its results are in the table above.
