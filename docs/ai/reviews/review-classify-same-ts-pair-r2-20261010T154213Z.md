# Code Review — classify-same-ts-pair, round 2 (PR #449 bot-sweep delta)

```yaml
review:
  scope: "2590c3d2..171e013d (commit 171e013d), worktree /Users/ales/Projects/aai-change-classify-same-ts-pair, branch change/classify-same-ts-pair, base origin/main cf39c58f"
  spec: docs/specs/SPEC-0219-spec-classify-same-ts-pair.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "delta does not touch cmdClassify or the fold (hunks at spec-amend.mjs:332-341, 1139-1151, 1684-1693, 1728-1741, 2002-2005 only); round-1 evidence stands" }
      - { ac: Spec-AC-02, call: compliant, citation: "classify refusal paths unchanged; the new notes route users away from the exit-2 indistinguishable branch rather than into it" }
      - { ac: Spec-AC-03, call: compliant, citation: "foldAmendments (spec-amend.mjs:377-568) untouched by the delta, so TEST-004 fold byte-equality vs cf39c58f is not affected; live ledger list --strict exit 0, 383 items, 0 identical (ts,ref,key) triples" }
      - { ac: Spec-AC-04, call: compliant, citation: "spec-amend.mjs:1139-1151 (add), 1684-1693 (restamp); TEST-010 + mutation-TEST-010.txt RED under if(false). Deviation D-1 below (byte-identical sub-case no longer appends)" }
      - { ac: Spec-AC-05, call: compliant, citation: "spec-amend.mjs:2002-2005 (list --strict), 1728-1734 (restamp); TEST-011 + mutation-TEST-011.txt. Byte-identical records get a named note; unshared lines unchanged (TEST-011 asserts no --record on the solo line)" }
      - { ac: Spec-AC-06, call: compliant, citation: "live ledger untouched except one appended measurement amendment (decisions.jsonl:1764); TEST-009 row unaffected" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 1764,
          issue: "The amendment for this delta is classed measurement and says 'AC rows and contract unchanged', but the delta changes writer behaviour that frozen Spec-AC-04 states as 'SHALL append it' for a colliding pair: a byte-identical collision now appends nothing. The AC text was not amended, so the spec and the code disagree on that sub-case and the ledger record describes the change as test-plan-only.",
          failure_scenario: "An owner or a later Validation reads list output: the record is bucket measurement (owes no signature, no tracked item), so nobody is asked to accept that AC-04's 'SHALL append' no longer holds for identical records; a future implementer reading AC-04 literally could 'fix' the no-op back into an append and reopen Codex thread 4238154338." }
    info:
      - "spec-amend.mjs:1145 dedupes on the 12-hex record key, not on the bytes; a 48-bit prefix collision between a genuinely new record and any ledger record would be dropped as a no-op. Probability ~N/2^48 (N~400 amendments), no realistic bite; a byte compare of JSON.stringify(entry) against the matched raw record would make the 'byte-identical only' claim exact."
      - "spec-amend.mjs:2010 the trailer still says each command above takes its record to unsigned-tracked and the gate to exit 0, also when some violations got only the indistinguishable note; for such a ledger --strict has no tool path to green. Writers can no longer mint the shape and the live ledger has none (0 identical triples), so this only concerns hand-appended/legacy ledgers."
  cannot_verify:
    - { claim: "restamp skips the append for a byte-identical record and still re-anchors the spec (spec-amend.mjs:1687-1693, 1736-1737)",
        closes_with: "a test that drives restamp twice to an identical record (needs the spec reverted to its prior bytes within one second) plus a mutation row for the duplicateRecord branch; today no test or mutation covers it (known gap named by the dispatch)" }
    - { claim: "TEST-010/011 green in the full suite and on Linux CI at 171e013d",
        closes_with: "Validation's concurrent suite run and the CI run for the pushed head (head not pushed; this round was told not to run suites)" }
  overall: pass
```

## Scope and method

Delta 2590c3d2..171e013d only, read in full (spec-amend.mjs, test-aai-spec-amend.sh,
SPEC-0219 Test Plan rows + frozen_sha256, decisions.jsonl append, INDEX.md). Both
Codex threads read verbatim. No suites or mutation-run executed (dispatch); scratch
probes ran against a copy of `.aai/` under the session scratchpad
(`cr-f2/proj`), and read-only `list` calls ran against the worktree ledger.

No coaching detected in the dispatch: it named the delta, the threads and one known
gap, and asked open questions; it did not pre-rate findings.

## Thread-by-thread judgement

**Thread 4238154338 (add mints an indistinguishable duplicate).** Fixed. `cmdAdd`
builds the complete entry (including `tracked_by` and `authority`) before computing
its key, then refuses to append when `reg.byRecord` already holds that key, exiting 0
and printing the existing key. Because `recordKey` hashes `JSON.stringify` of the
record and the fold hashes the parsed ledger line, a match means the same
serialisation, `ts` included, so only a same-second identical record is skipped. Probe:
three identical `add --class measurement` in one second -> 1 line on the ledger, rc 0
each time, the printed key `4485003647cd` addresses one record. Two identical
`add --class contract --signoff none` -> one record plus one tracked item; the
no-op reuses the open `fu-amend-spec-probe` (pickAmendItemId returns the same open
id, so the entry is identical); `list --strict` exit 0. If the base item had been
closed in between, pickAmendItemId picks a fresh id, the entry differs, and it
appends; fail-open, as intended.

**Can the idempotent add hide a genuinely new amendment?** Only when every field
matches byte for byte, including the second-precision `ts`. A different `what`, `why`,
class, signoff, authority, actor, spec or tracked item gives a different key and still
appends (TEST-010 positive control asserts this). The only gap between "same key"
and "same bytes" is a 48-bit hash-prefix collision (INFO above).

**Thread 4238154342 (list --strict prints unrunnable --record remedies).** Fixed.
`indistinguishableInPair` fires only when two or more records of the pair share the
key; those records get the named note instead of a classify line, and other records
of the same pair still get their `--record` line. The restamp remedy uses the same
check. TEST-011 pins the note count (2) and that the unshared line carries no `--record`.

## Spec deviations

- **D-1 (Spec-AC-04).** The frozen text says that when add/restamp hits an existing
  pair the system "SHALL append it". For a byte-identical record it now does not. This
  matches what AC-04 is for (the record is addressable, nothing is refused) and is what
  the bot asked for, but the AC text was not amended and the ledger record
  (decisions.jsonl:1764) calls the change measurement-only. See the NON-BLOCKING finding.

## Regression check

- The fold is untouched by the delta, so TEST-004's byte-equality vs cf39c58f cannot move
  through this commit (its run is Validation's).
- Unshared-pair remedy lines: the new branch is reached only when `indistinguishableInPair`
  is true, which needs two records with the same pair, so unshared lines stay byte-identical.
- Live ledger: `list --strict` exit 0; 0 identical (ts, ref_id, record_key) triples out of 383.

## Warning dispositions (H6)

- **NB-1 (decisions.jsonl:1764, AC-04 sub-case described as measurement-only).** The
  recommended disposition is (a) remediate in tree: append (never edit) a contract-class
  amendment, `spec-amend.mjs add --class contract --signoff none`, disclosing that AC-04's
  "SHALL append" now excludes byte-identical records. That files the owner-owed tracked
  item, and the owner can sign it. The alternative is (c), a tracked follow-up ref. This
  is not eligible for (d): left alone, the record stays false. The orchestrator records
  the disposition; this reviewer files nothing.

## Next steps

1. Orchestrator: choose NB-1's disposition and record it in `code_review.notes`.
2. Validation: confirm TEST-010/011 and TEST-004 green in the concurrent run; CI on the
   pushed head.
3. Optional: add a restamp-identical test plus a mutation row (cannot_verify item 1).
