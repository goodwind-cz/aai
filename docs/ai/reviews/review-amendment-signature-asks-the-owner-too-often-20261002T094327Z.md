---
review:
  scope: "working tree (uncommitted) vs 1ffc03de on change/amendment-signature-asks-the-owner-too-often in /Users/ales/Projects/aai-amend — .aai/scripts/spec-amend.mjs, .aai/ROLE_COMMON.md, .aai/system/AUTONOMOUS_LOOP.md, tests/skills/test-aai-spec-amend.sh, tests/skills/test-aai-prompt-diet.sh, tests/skills/lib/prompt-diet-ledger.sh, docs/ai/decisions.jsonl, docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl, plus untracked docs/issues/CHANGE-0202-amendment-signature-asks-the-owner-too-often.md and docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md"
  spec: docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md
  round: 2 (remediation of round-1 BLOCKING finding on cmdClassify/foldAmendments disagreement)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-1354 PASS (full suite run, see Evidence below)" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-1355 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-1356 PASS; .aai/scripts/spec-amend.mjs:975-980 (CLASS_NOTE printed only when declaredClass===null)" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-1357 PASS; .aai/scripts/spec-amend.mjs:818-823 requireAmendmentClass" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-1358 PASS; .aai/scripts/spec-amend.mjs:826-841 refuseMeasurementSignedByOwner" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-1359 PASS; .aai/scripts/spec-amend.mjs:424-432 (signed tested first and alone)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-1360/TEST-1361 PASS (both negative controls green); STRICT_VIOLATION_BUCKETS unchanged" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-1362 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-1363 PASS — FOLD-IDENTICAL total=218 cohort=25 compared=193 moved=0" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-1364 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-1365 PASS; .aai/scripts/spec-amend.mjs:1283-1322 cmdRestamp hardcodes MEASUREMENT_CLASS" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-1366 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-1367/TEST-1368 PASS" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-1369 PASS" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-1370 PASS" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-1371/TEST-1372 PASS (prompt-diet suite green, amendment-class-partition entry present)" }
      - { ac: Spec-AC-17, call: compliant, citation: ".aai/scripts/spec-amend.mjs:1118-1162 (trial fold read via foldAmendments(reg.records.concat([entry])), refusal on projected.amendment_class !== amendmentClass); TEST-1373 PASS on the fixed tree AND independently reproduced-RED by this reviewer against a reconstructed pre-remediation cmdClassify (see code_quality note 1 below) — the arm genuinely discriminates, not a strawman" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: ".aai/scripts/spec-amend.mjs", line: "1118-1162 (cmdClassify trial-fold preflight)",
          issue: "The preflight 'trial = foldAmendments(reg.records.concat([entry]))' is computed from a read-before-write snapshot of the ledger. It correctly guarantees no disagreement for a SINGLE sequential classify call, but two classify invocations racing on the SAME (ts, ref) overlay key can each read the ledger before the other has appended, each validate successfully against its own entry-only trial, and both land. The REAL post-hoc fold then picks whichever overlay has the later `ts` as the resolved class — which is not necessarily the one each process's preflight assumed would win — so one of the two writers can end up creating (or skipping) a tracked `fu-amend-*` item based on a class the final fold does not actually adopt. This reopens the same disagreement class Spec-AC-17 closes, just via a race instead of a direct miscomputation.",
          failure_scenario: "Legacy class-absent record R (classOnRecord=null). Process A runs `classify --ts T --ref r --class measurement --signoff none` and Process B runs `classify --ts T --ref r --class contract --signoff none` concurrently, both reading the ledger before either appends. A's trial (records+entryA only) resolves measurement, matches its flag, owes=false, proceeds with no tracked item. B's trial (records+entryB only) resolves contract, matches its flag, owes=true, proceeds to pickAmendItemId and creates/attaches an open fu-amend-<spec> item. Both appends land (order on disk does not matter; foldAmendments sorts overlays by `ts`). If entryA's `ts` (assigned via nowIso() before A's trial ran) ends up later than entryB's `ts`, the real merged fold resolves the record's class to `measurement` — but B's open fu-amend-<spec> item already exists, now orphaned beside a `measurement`-bucket row with no outflow (the drain route reads the bucket, per the file's own header). The mirror (A's class loses, B's wins) instead leaves a contract/unsigned-tracked row whose tracked item was skipped because A believed `measurement` would win." }
    note_1_independent_verification: >
      To settle whether TEST-1373's arms actually catch the round-1 defect (rather than asserting against a
      strawman), I copied the full working tree to a scratch location and reconstructed the pre-remediation
      cmdClassify exactly as round 1 described it: removed the `trial`/`projected` fold-read and the new
      refusal block, and computed `owes = owesOwnerObligation(amendmentClass ?? target.amendment_class, signed)`
      directly from the flag (ignoring what the fold would actually resolve). Running
      `test_1373_class_flag_cannot_disagree_with_the_fold` against that reconstruction: arm 1 failed exactly as
      the test's own comment predicts — `classify --class contract` over a `measurement`-stamped record exited
      0 and printed "bucket measurement" together with "tracked by fu-amend-spec-t1373a-fixture". I also drove
      the mirror scenario by hand (arm 2's shape) against the same reconstruction: `classify --class measurement`
      over a `contract`-stamped record exited 0 and printed "measurement-class — disclosed and counted, owing no
      owner signature and no tracked item" directly beneath "bucket unsigned-tracked" — the exact contradiction
      the comment block names. Both arms are therefore real regression tests, not strawmen. Arms 3 and 4 are
      positive controls (agreeing --class; class-absent legacy record) and are correctly expected to PASS on
      both the fixed and the buggy tree — confirmed passing on the real (fixed) tree via the full suite run.
  cannot_verify:
    - { claim: "The concurrency/race scenario in the NON-BLOCKING finding above is operationally reachable in this project.",
        closes_with: "A grep/survey of every spec-amend.mjs classify call site (migration loops, CI steps, downstream vendored copies) confirming all are invoked sequentially by a single orchestrator process, per the single-writer convention named in .aai/SUBAGENT_PROTOCOL.md — or, if any site dispatches classify concurrently, a fixture test that drives two real child processes against one ledger file and observes the outcome." }
    - { claim: "No other real caller in this or a downstream-vendored project passes `classify --class` on a target whose own amendment_class is already live-writer-stamped to a DIFFERENT value than the caller intends (which this remediation now refuses).",
        closes_with: "A repo-wide / downstream-fleet grep for `spec-amend.mjs classify` invocations carrying `--class`, confirmed against each target's current ledger state; I grepped this repo (clean: only test fixtures and the SPEC-DRAFT's own prose use `classify --class`) but cannot see vendored downstream copies." }
  overall: pass
---

# Code Review — amendment-signature-asks-the-owner-too-often (round 2)

## Scope and method

Reviewed the uncommitted working-tree diff in `/Users/ales/Projects/aai-amend`
(branch `change/amendment-signature-asks-the-owner-too-often`, HEAD
`1ffc03de`, same as `main`) against the frozen
`docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md`.
This is round 2, scoped to the remediation of round 1's single BLOCKING
finding (`cmdClassify` derived the owner-obligation decision from the
caller's `--class` while `foldAmendments` lets a record's own stamped class
beat a later overlay). Per the dispatch, I did not re-run the independent
validation's eight checks (docs/ai/reports/VALIDATION-amendment-signature-asks-the-owner-too-often-20261002T082902Z.md)
and treated the headline-defect fix as already confirmed gone.

Verification performed beyond reading the diff:
- Ran the full `tests/skills/test-aai-spec-amend.sh` suite (all TEST-1354..1373 green, plus the pre-existing TEST-001..014) and the full `tests/skills/test-aai-prompt-diet.sh` suite (green, including TEST-1372) against the real worktree.
- Copied the working tree to a scratch location and reconstructed the exact pre-remediation `cmdClassify` logic (flag-driven `owes`, no trial-fold refusal) to confirm TEST-1373's arms 1 and 2 are genuine regression tests that go RED against that reconstruction — not strawmen. Details in code_quality note_1 above.
- Traced every `--class` call site in the repo (`grep -rn -- "--class"`) to check whether the new refusal could block a legitimate caller: the `list --strict` remedy line never emits `--class` on its printed `classify` command (spec-amend.mjs:1584), and the documented migration loop drains the backlog one record at a time via `classify --class measurement` against class-absent legacy records — the one population the fold lets an overlay move. No real caller found that would be refused.
- Confirmed `loadLedger`'s new `records` field is additive and non-breaking: it has no callers outside `spec-amend.mjs` itself, and `cmdList --json` builds its output object field-by-field (never spreads `reg`), so the raw records are never leaked onto that surface.
- Confirmed the restored exec bit on `tests/skills/test-aai-prompt-diet.sh` (100755) matches `main`'s tree mode exactly (`git ls-tree main` vs `git ls-files -s`).

## Findings, most severe first

**NON-BLOCKING** — `.aai/scripts/spec-amend.mjs:1118-1162`. The fix's
trial-fold preflight (`foldAmendments(reg.records.concat([entry]))`)
guarantees the obligation decision and the bucket agree for one sequential
`classify` call, by construction. It does not cover two `classify` calls
racing on the same `(ts, ref)` overlay key: each reads the ledger before
either has written, so each one's preflight only ever sees its own
prospective overlay, never the other's. If both land, the real fold (which
breaks ties on `ts`, not file-write order) can resolve the class to the
overlay that LOST the process that created or skipped the tracked item,
reopening the exact disagreement class Spec-AC-17 closes — concrete scenario
given in the structured block above. I rate this NON-BLOCKING / low-severity
given this project's documented single-writer convention
(`.aai/SUBAGENT_PROTOCOL.md`'s "single-writer rule" and the spec's own
statement that the backlog migration drains "one at a time") — I found no
call site in this repo that would actually race. Recommended disposition:
**(d) accepted residual** (P3, assurance-strength/unexercised-edge, no
observed bite) — unless the orchestrator knows of a concurrent/parallel
dispatch path for `spec-amend.mjs classify` I didn't find, in which case this
should be (b)/(c) instead.

No other code_quality defects found. Specifically clean, checked and ruled
out rather than assumed:
- **Over-broad refusal**: none of the real callers I could find (`list
  --strict`'s printed remedy, the documented migration loop, the two writers'
  own usage text) pass a `--class` that the new refusal would block.
- **Under-broad refusal (single-call case)**: the only way class and bucket
  can still disagree after a single `classify` call is the race above; every
  non-concurrent path I traced (second corrective overlay dated later,
  overlay on a live-writer-stamped record, overlay on a legacy record) is
  resolved consistently by construction, because `owes` is now read off the
  same `foldAmendments` call that assigns the bucket.
- **Trial-fold fidelity**: `reg.records.concat([entry])` uses the exact same
  `entry` object later passed to `appendLine`, so the trial projects
  precisely what lands (modulo the race above, which is about what ELSE
  lands concurrently, not about the trial misrepresenting this call's own
  write).
- **TEST-1373's four arms**: empirically confirmed discriminating (not a
  strawman) — see note_1 in the structured block.
- **USAGE text**: `.aai/scripts/spec-amend.mjs:678-684` accurately describes
  the refusal ("a record's OWN amendment_class outranks every overlay... the
  flag cannot re-classify a record a live writer already stamped") and
  matches the implemented behavior.
- **`loadLedger`'s new return shape**: additive, non-breaking, not leaked to
  `--json`.

## cannot_verify

See the structured block above — two items, both about operational reach
(whether the race condition and the blocked-caller scenario are reachable
anywhere outside this repo, e.g. in downstream-vendored copies), neither
closeable from the diff alone.

## Next steps

Nothing blocks. The one NON-BLOCKING finding needs a disposition recorded
per H6 before closeout (recommend accepted-residual unless a concurrent
dispatch path is known to exist).
