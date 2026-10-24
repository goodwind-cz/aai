# Code Review r6 (post-PR delta): node-first-third-slice

Target path: `docs/ai/reviews/review-node-first-third-slice-20261024T104222Z.md`
Reviewer: Code Review role (dispatched, `AAI_ROLE` set by the caller). The STATE write is returned, not run.
Started 2026-10-24T10:38:40Z. Ended 2026-10-24T10:42:22Z.

```yaml
review:
  scope: "8c1b9f4f..015a2b45 (delta, commit 015a2b45); full range 4d4566bc..015a2b45, where rounds 1-5 passed"
  spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01..05, call: compliant, citation: "unchanged in delta. The Spec-AC-05 cache-hit path now uses isFile (expert-fetch.mjs:144). regular_hit probe: hit, 0 runGh calls" }
      - { ac: Spec-AC-06, call: compliant, citation: "expert-fetch.mjs:189 isFile(c.file); TEST-2636 (expert-fetch.test.mjs:399-413, test-aai-expert-fetch.sh test_2636) PASS; D-24 row; AC row cites D-24 and TEST-2636" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2612 wantFs now has statSync instead of existsSync; test_2612 PASS in the copy" }
      - { ac: Spec-AC-08..11, call: compliant, citation: "launchers unchanged in delta" }
      - { ac: Spec-AC-12, call: compliant, citation: "wc -l total 230 = RFC-0017 row 'expert-fetch pair 444 to 230 lines'; test_2622 PASS" }
      - { ac: Spec-AC-13..15, call: compliant, citation: "unchanged in delta; earlier rounds passed" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/expert-fetch.mjs, line: 161,
          issue: "A FIFO at .sha_<key> is now a miss, but the refetch then blocks forever in writeFileSync(shaFile) when it opens the FIFO for writing. Before the fix the same state blocked in readText(shaFile). The hang has moved, not been removed.",
          failure_scenario: "mkfifo .aai/cache/experts/.sha_typescript next to a regular typescript.md, then expert-fetch typescript: the process hangs and never prints the D-23 line. Probe: timeout 8 gave rc 124 on both 015a2b45 and 8c1b9f4f. The old sh (echo > $SHA_FILE) behaves the same. Disposition: accepted residual (P3)." }
  cannot_verify:
    - { claim: "The Windows/pwsh launcher path for a directory cache, run end to end", closes_with: "The Windows Pester leg in CI. The ps1 is a thin launcher over the same module, so the risk is low" }
  overall: pass
```

## Scope and preflight

The scope is one commit, `015a2b45`, on top of `8c1b9f4f`. It changes five files: `.aai/scripts/expert-fetch.mjs`, the SPEC-0249 spec, `docs/ai/decisions.jsonl`, `tests/skills/lib/expert-fetch.test.mjs` and `tests/skills/test-aai-expert-fetch.sh`. The worktree was only read. All probes ran in archive copies under `scratchpad/cr18-work`, `cr18-base` (8c1b9f4f) and `cr18-mut`. The dispatch listed areas to check but did not pre-rate any finding, so no coaching is recorded. The full delta was reviewed.

## Correctness probes (fix tree 015a2b45 vs base 8c1b9f4f, via main() with injected runGh)

| Case at cache path | --body (fix) | fetch (fix) | base behaviour |
|---|---|---|---|
| directory (empty / non-empty) | not-cached, exit 1 | runGh x1, D-23 Cannot-write line, exit 1 | body EISDIR throw; fetch exit 0 serving dir path |
| FIFO at `<key>.md` | not-cached, exit 1 | runGh x1, rename replaces FIFO, exit 0 | body HANG; fetch false hit |
| FIFO at `.sha_<key>` | serves body (does not read SHA) | **HANG** (writeFileSync) | fetch HANG (readText) |
| directory at `.sha_<key>` | serves body | D-23 line, exit 1 | fetch EISDIR throw |
| symlink to regular file | served (same as `-f`) | hit | same |
| dangling / dir / loop symlink | not-cached | refetch, rename replaces the link itself (no write-through) | dir-symlink body EISDIR throw |
| ENOTDIR (`.aai/cache` is a file) | not-cached | D-23 line | same |
| registry is a directory / FIFO | "Registry not found", exit 1 | same | EISDIR throw / HANG |

Summary: no stack trace remains on any cache or registry path that was probed. Three base hangs and four base throws are gone. The one remaining hang (FIFO SHA, fetch) was there before the fix and is shared with the old sh; it is listed below as a residual. The symlink handling matches `-f` parity, and a rename never writes through a link.

The timeout inlining changed nothing. `spawnSync(..., timeout: 60000, killSignal: 'SIGKILL', ...)` at line 172 has the same value as the removed `GH_TIMEOUT_MS = 60000`, and the constant had no other user.

## Tests and mutation

- `node --test --test-name-pattern 'TEST-26(36|12|31|32|10)'`: 5/5 pass.
- `bash tests/skills/test-aai-expert-fetch.sh test_2636_cache_path_not_a_file`: PASS. `test_2612_...`: PASS. `test_2622_...`: PASS (230 <= 230).
- The mutation from the TEST-2636 row, `s/statSync\(p\)\.isFile\(\)/statSync(p)/`, matched only line 39. It makes test_2636 go red with "a directory must not serve as a cache hit" (rc 1). A full revert to `existsSync` would also turn TEST-2612 red through the import pin.
- `spec-amend list --strict`: rc 0. The new record lists as `unsigned-tracked` (fu-amend-spec-node-first-third-slice, open). `spec-lint`: LINT PASS. mutation-gate: exempt (terminal spec).
- I checked the D-24 claim about the old ps1 with pwsh 7: `Test-Path <dir>` returns `True`. The old sh used `-f` at lines 22, 127 and 186. Both match the D-24 text.

## Spec and record vs diff

- The D-24 row, the traceability line, the Spec-AC-06 row, the TEST-2612 row (fs name set) and the new TEST-2636 row all match the diff.
- The 10:24:27Z record names D-24, TEST-2636, the statSync import, the TEST-2612 pin, the Spec-AC-06 citation and the unchanged 230 budget. INFO: it has no `from/to_frozen_sha256` fields for the restamp (dd5d3a4d.. to 2664d54c..), and it does not mention that GH_TIMEOUT_MS was inlined. The inlining is a code change and does not touch the spec contract. The strict gate passes, so neither omission is a defect.

## Warning dispositions (H6)

- NB-1 (FIFO SHA path hangs the refetch): `accepted residual: P3 edge reachable only by planting a FIFO in the gitignored cache dir. It was already there before this delta, the old sh behaves the same, nothing has been observed to bite, and no false record results. D-24's "a non-file path is a miss" still holds.` If the orchestrator prefers to track it instead, the suggested id is `fu-expert-fetch-fifo-sha-write-hang` (suggested, not filed).

## No new hazard

The delta adds no new sidecar, ledger rewrite, write path or import beyond `statSync`. `isFile` catches every stat error and turns it into a miss, and none of those errors can widen what is served. The `--body` key guard (D-22) still runs before `isFile`.

## Next steps

The orchestrator records the NB-1 disposition in `code_review.notes` and runs the set-code-review command below.
