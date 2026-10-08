# Integrated-source mutation evidence repair

Scope: parent SPEC-0210 and closed child SPEC-0211 after linear integration at 8701da75a29e76e5a7897a9e327ad07f9ab38345. This is a Remediation evidence repair, not an independent Validation or Code Review verdict.

## Root cause and action

The shared `.aai/scripts/pr-preflight.mjs` source changed during the child2 ASCII case repair while the parent and child1 mutation records retained earlier `target_sha256` values. Initial current-tree mutation gates refused six parent records and two child1 records as STALE (exit 5). Exact original live record and patch bytes for those eight rows were copied to `original/` before modification, with hashes in `pre-replay-manifest.json`.

The canonical parent replay confirmed RED for TEST-001 through TEST-006 and TEST-008, and automatically restamped the five stale applicable target records. Historical parent TEST-007 patch could not apply because it removed a strict `nameWithOwner` comparison that is now ASCII case comparison. The scratch adaptation removed that same provider identity check from the integrated source while retaining the current URL-path check. `git apply --check` succeeded. A canonical normal mutation run produced RED (`FAIL: TEST-007 exit PROVIDER_RESULT_INVALID`), a fresh record pinned to 8701da75, and a copied live patch. The runner's first replay exit 4 and its exact inconclusive message remain in `parent-replay-attempt.log`; the original historical bytes remain in `original/` and the runner's rotation.

Canonical child1 replay confirmed 2/2 RED with zero inconclusive and restamped both records. Final canonical parent replay confirmed 8/8 RED with zero inconclusive and zero additional restamps. Parent, child1 and child2 mutation gates each exit 0 with no degraded, unstamped, uncomparable or offending rows. Child2 live records were read and checked, not rewritten.

## Boundary checks

The current source SHA-256 is `e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf`; the test suite SHA-256 is `239206e806eff008083c8c1b081587760aa0ec9f4094fe7336a7404dc169df7c`. Original preservation copies match their pre-replay hashes. All live record base commits are ancestors of HEAD, target hashes match their actual target files, and all live patches pass `git apply --check`. The pre-replay hashes for source, suite, index, STATE, and all three specs remain unchanged. The pre-existing root edits to `docs/ai/decisions.jsonl` and parent SPEC-0210 were left untouched. The append-only ledgers were not written in this role.

This evidence closes only the integrated mutation prerequisite. Final assembly Code Review, metadata close, native/full CI, and fresh independent parent Validation remain pending in the root sequence. No human decision is required for this repair. Reset only the failed parent `last_validation` block at merge; leave `code_review: not_run` untouched.
