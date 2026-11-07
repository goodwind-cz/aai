---
id: release-fixture-atomic-publication
type: issue
number: 110
status: done
links:
  pr:
    - 538
  commits: []
---

# Release fixture transport publication race

## Summary

The release test fixture publishes transport snapshots through in-place truncating writes while TEST-021 reads the same JSON from another process. Publish complete snapshots atomically and prove the concurrent seam deterministically.

## Type

bug

## Impact

Internal CI reliability: the release dry-run blocks PR #535 despite an unchanged release suite. Priority P2. Failure: https://github.com/goodwind-cz/aai/actions/runs/42317483792.

## Current Behavior

The fixture entry log and save() rewrite transport.json with writeFileSync. After SIGKILL of the release owner, the parent releases pr-go and polls the orphan transport. It can parse zero bytes between truncate and write. CI reports Unexpected end of JSON input at extracted Node lines215 and601. One instrumented scratch reproduction captured zero bytes at that boundary with the identical stack.

## Expected Behavior

- AC-001: Every fixture transport publication uses a complete atomic snapshot; a concurrent reader observes valid prior or next JSON, never a truncated payload.
- AC-002: A deterministic regression exercises the real fixture writer/reader seam and fails without atomic publication. The existing TEST-021 SIGKILL, journal recovery and single create/merge assertions remain enforced.
- AC-003: Existing release tests pass and the rolled release-dry-run executes actual changelog readers successfully. No JSON parse retries, sleeps masking errors, or weaker CI gate substitutes for a repair.

## Steps to Reproduce (if applicable)

1. Run release TEST-021 with a scratch-only barrier after the hold-pr writer opens transport.json with mode w but before writing its unchanged payload.
2. Release pr-go and allow the unchanged parent transport() reader to poll.
3. Observe zero-byte JSON and Unexpected end at transport line215, caller601.

## Verification

Use existing release suite and selected TEST-021 through the canonical wrapper with AAI_ROLE and AAI_GIT_WRITE unset. Record failing-first deterministic coverage, green recovery assertions, independent validation/review and current-head CI. No new suite is expected; Planning must check registration and nested-reader wiring if needed.

## Constraints / Risks

Only test-fixture publication and its regression are in scope; no production release engine or allocator change, new dependency, waiver expansion, merge or release. Audit all fixture writers for concurrent read-modify-write assumptions. Atomic replacement prevents partial reads; it does not itself serialize concurrent writers. The separately approved SPEC-0245 deadline-only metadata correction is included to obey the independent base's global gate; deferred evidence remains pending. No secret is referenced.

## Notes

Owner authorized separate worktree/PR on 2026-11-07. Original failed run and reproducible diagnosis are retained. Human intake time is null under aai-ship; Planning chooses implementation strategy. Product docs may be skipped as pure internal scope. Do not touch the shared main checkout or cloudflare worktree.
