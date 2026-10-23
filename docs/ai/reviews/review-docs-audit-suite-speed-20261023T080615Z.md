```yaml
review:
  scope: "git diff 34f0cbca..c48faa68 (branch change/docs-audit-suite-speed, worktree /private/tmp/aai-docs-audit-speed)"
  spec: docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-2201 test_2201_speed_note_profile PASS rows=195 (run by reviewer); docs/analysis/docs-audit-suite-speed.md" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/lib/docs-audit-live.sh:79-108; TEST-2202/2203 PASS in reviewer full run; VAL4 shim log: 3 full real-corpus launches; TEST-2206 weaker than its name (see BLOCKING B1)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "docs-audit-live.sh:139-165 (restore before return); test-aai-docs-audit.sh setup_indexarm_snapshots + test_deterministic_index_no_clock_line; TEST-2204/2205 PASS; VAL4 shim: generator 2 + 1 pinned" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "test_histmap_corpus_equivalence worker_threads shards, per_file_entries and shard>=2 checks; PASS on Node 22 locally (Node 20 on CI: cannot_verify)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "tests/skills/lib/docs-audit-closeout.test.mjs (10 pass / 0 fail); fixture bodies byte-identical to setup_closeout_fixture output (reviewer probe, 23/23); TEST-2209 retained CLI owner; TEST-2211 PASS" }
      - { ac: Spec-AC-06, call: cannot-verify,
          citation: "row status deferred, Review-By 2026-11-06: local paired 116.5 s -> 79.3 s (31.9%) recomputed by TEST-2210; hosted after rows and suite-weights.tsv re-measure pending push (declared deviation)" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "reviewer full wrapper run rc 0 'PASS: All aai-docs-audit tests passed' (78 s); check-test-registration rc 0; TEST-2211 select-suites maps both lib files, no FULL_RUN" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8582,
          issue: "test_2206_no_direct_live_corpus_launch names a universal negative ('no direct live-corpus launch') but asserts one textual shape: a single line carrying both cd \"$PROJECT_ROOT\" and docs-audit.mjs / generate-docs-index.mjs. The >=14 call-site floor sits one below today's 15.",
          failure_scenario: "Reviewer mutation in a scratch copy: test_change0012_regression's live_audit replaced by '(cd \"$PROJECT_ROOT\" \\ <newline> && node .aai/scripts/docs-audit.mjs --check --strict --no-event > ...)'. TEST-2206 printed PASS: No direct real-corpus launch; 14 live_audit call sites. The same miss applies to 'node \"$AUDIT_SCRIPT\" ...' run from PROJECT_ROOT. The suite then makes an extra uncached real-corpus launch while TEST-2206 says none exists. Under the review contract a test whose name claims a universal negative but checks only some paths is BLOCKING." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/docs-audit-live.sh, line: 35,
          issue: "LIVE_ROOT and LIVE_CACHE_DIR are taken from the caller's environment (${LIVE_ROOT:-}, ${LIVE_CACHE_DIR:-}). The spec puts the cache under TEST_DIR and the root at PROJECT_ROOT.",
          failure_scenario: "An operator exports LIVE_CACHE_DIR to a persistent directory, for example to keep launches.log, then edits a doc without committing it and reruns. The index pair's done marker (line 143) skips generation and returns the previous run's snapshots. The audit key (HEAD + INDEX checksums) does not change, so the old audit output is returned and a new violation passes. An exported LIVE_ROOT likewise points every real-corpus check at another tree." }
  cannot_verify:
    - { claim: "Worker sharding and node:test file behave the same on CI Node 20 (os.availableParallelism, postMessage then process.exit(0) in a worker, node:test before/after)",
        closes_with: "green hosted skill-suite run of test-aai-docs-audit.sh on the pushed head (Node 20, ubuntu, 2-4 vCPU) with the 'shards=' info line showing >=2" }
    - { claim: "Suite passes under GNU Bash 5 with set -euo pipefail (only Bash 3.2 was exercised locally; no bash 5 on this host)",
        closes_with: "hosted Linux run of the suite on the pushed head" }
    - { claim: "Spec-AC-06 hosted after durations and the re-measured aai-docs-audit weight row",
        closes_with: ">=3 hosted runs whose suite blob equals the final one; suite-weights.tsv row + test-aai-suite-select.sh rc 0" }
    - { claim: "Cache equivalence on the real corpus (no test mutates a non-fingerprinted real-tree input between consumers)",
        closes_with: "already evidenced by VAL4 AAI_DOCS_AUDIT_LIVE_VERIFY=1 full run (0 mismatches); holds only for today's suite order. INDEX.audit.md, regenerated and not restored by the pair, is outside the fingerprint; docs-audit reads it only as a non-ID filename" }
  overall: fail
```

# Code review: docs-audit-suite-speed (round 1, dual verdict)

- Scope: `git diff 34f0cbca..c48faa68` in /private/tmp/aai-docs-audit-speed (worktree mode, base main). This matches the STATE `code_review.scope` path list. Ledger and INDEX telemetry in the diff (EVENTS.jsonl, decisions.jsonl, docs/INDEX.md) were read but not judged. An uncommitted `docs/ai/roadmap.yaml` edit sits in the worktree. It is outside the reviewed commits (validation NB-2).
- Spec: docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md (frozen).
- Dispatch note: the dispatch listed the focus areas and two known accepted deviations. The full scope was reviewed anyway, and the deviations are recorded below on their merits.

## BLOCKING

**B1. TEST-2206's name claims a universal negative that it does not prove** (`tests/skills/test-aai-docs-audit.sh`, `test_2206_no_direct_live_corpus_launch`).

The scan reads one line at a time. It requires `cd "$PROJECT_ROOT"` and the script name on the same line. A reviewer mutation in a scratch copy split one consumer's launch over two lines. TEST-2206 still passed ("14 live_audit call sites"), because the floor of 14 is one below today's 15 sites. Validation flagged this twice as NB-3. The review contract makes it BLOCKING: a test whose name claims "no X" but checks only some paths.

The cost of a miss today is speed, not correctness (an uncached launch). The recorded claim is still false.

Fix, either of these:
- (a) Rename the function so its name states the checked shape, for example `test_2206_no_inline_live_corpus_launch`. Record this as a spec amendment (additive-with-disclosure), because D5 and the Test Plan name the function.
- (b) Prove the negative. Join `\`-continued lines before scanning. Also match `"$AUDIT_SCRIPT"` and `"$PROJECT_ROOT/.aai/scripts/(docs-audit|generate-docs-index).mjs"` forms. Raise the floor to the exact current count (15). Add a mutation row for the multi-line shape.

(b) still leaves some shapes uncovered, so (a) is needed in any case, or both together.

## NON-BLOCKING

**N1. The helper takes its state from the environment** (`tests/skills/lib/docs-audit-live.sh:35-36`). `LIVE_ROOT="${LIVE_ROOT:-}"` and `LIVE_CACHE_DIR="${LIVE_CACHE_DIR:-}"` inherit whatever the caller exported. If `LIVE_CACHE_DIR` survives between runs, the next run:
- skips the index pair through the `done` marker, and
- returns old audit output when only uncommitted docs changed, because the fingerprint covers HEAD and the two INDEX files only.

Recommended disposition: **remediate-in-tree**. Initialise both to empty at source time; tests already set them through `live_test_enter`. The fix is two lines and needs no new test, but rerun TEST-2202 to 2205. Fallback: (d) `accepted residual:` P3, because no observed bite and no false record.

## Focus-area findings (no defect)

- **Cache keying.** The key is the argument list plus root, HEAD and the cksum of `INDEX.md` and `INDEX.violations.md`. A full-key `.key` file guards against cksum collisions. Exit codes are stored and replayed, and TEST-2202 covers a nonzero code (exit 2). Invalidation on index rewrite, a new companion and a moved HEAD is tested. VAL4's verify-mode full run on the real corpus found 0 mismatches.
- **set -euo pipefail.** Every consumer calls `live_audit … || …`. That disables errexit inside the helper, so a failed `cp` or `mv` there would not abort. The consumer's next assertion would then fail on a missing log, which is loud, not silent.
  - `log_fail` exits even in that context. Inside `rc="$(silence_live_audit …)"` the subshell exits with no stdout, so the assignment fails and errexit aborts the parent.
  - There are no new early-closing pipe readers: `cksum`, `tr` and `awk` read to EOF, and the existing `| qgrep -qF` uses the pipe-safe wrapper.
  - `live_test_repo` inside `$(…)` always gets a non-empty absolute `d`, because `TEST_DIR` is set in the parent first. So no `cd ""` path exists (HAZ-CD).
- **Index pair restore order.** Both runs are snapshotted, then `INDEX.md` and the companion are restored before return. `setup_indexarm_snapshots` takes the committed snapshot before the pair and restores after the pinned run. The trap's restore floor covers interrupts. `INDEX.audit.md` is gitignored and was never restored by the baseline either. The reviewer's full run left the tree clean.
- **Histmap sharding.**
  - Determinism: results go into a Map keyed by file, and the comparison iterates `files`.
  - Worker failures propagate: `error` and a nonzero exit reject, and the top-level await rejects, giving rc != 0 and log_fail.
  - The size check turns a lost message into a loud failure. A reviewer stress probe (100 x 8 workers, postMessage then process.exit) lost nothing on Node 22.23.1.
  - `os.availableParallelism` exists since Node 18.14, so it is fine on CI Node 20, with a `cpus()` fallback.
  - A 2-core runner gives 2 shards.
- **Node closeout file.** The 23 fixture bodies are byte-identical to what `setup_closeout_fixture` writes (reviewer probe). Candidate ids are display ids, so the negative checks are not vacuous: RFC-0080, also a slug-id parent, resolves by display id. 10 pass, 0 fail.
- **suite-map.** Both lib files and the analysis note map to aai-docs-audit. select-suites shows no FULL_RUN (TEST-2211).

## Deviations from the frozen spec

1. Spec-AC-06 is deferred, with Review-By 2026-11-06. The hosted after rows are pending, and the note carries `Hosted after status: pending`, an escape hatch in TEST-2210.
2. The `suite-weights.tsv` row is unchanged until a hosted re-measure after push. D5 and the Implementation plan step 5 require it before close.
3. D1 says the cache directory lives under TEST_DIR. The lib also honours an inherited `LIVE_CACHE_DIR` (N1).

## Reviewer evidence

| Command | Result |
|---|---|
| `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` | rc 0, 78 s, tree clean afterwards (except the pre-existing roadmap.yaml) |
| single dispatch of TEST-2201, 2206, 2208, 2210, 2211 | all PASS |
| `node --test tests/skills/lib/docs-audit-closeout.test.mjs` via wrapper | pass 10, fail 0 |
| `check-test-registration.mjs tests/skills` | rc 0 |
| `mutation-gate.mjs --spec <spec>` | GATE PASS 11 rows |
| `git diff --quiet 34f0cbca -- .aai/` | rc 0 (production unchanged) |
| TEST-2206 multi-line bypass mutation (scratch copy) | PASS, which is the bite miss (B1) |

## Next steps

1. Fix B1 by (a), or by (a) and (b) together, then re-review.
2. Remediate N1 in the tree, or record it as an accepted residual.
3. After push, close the cannot_verify items with the hosted Node 20 / Bash 5 run, then fill in Spec-AC-06 and the weights row.
