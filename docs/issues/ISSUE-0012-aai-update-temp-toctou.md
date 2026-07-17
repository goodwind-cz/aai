---
id: aai-update-temp-toctou
type: issue
number: 12
status: done
links:
  pr:
    - 104
  commits:
    - dfa9b10
---

# Issue: aai-update reuses a wiped mktemp path (TOCTOU → code execution on shared hosts)

## Summary
- `.aai/scripts/aai-update.sh` (and the `.ps1` analog) creates a securely-owned
  temp dir with `mktemp -d`, then `rm -rf`s it and recreates the SAME path
  non-atomically via `gh`/`git clone`. This discards mktemp's ownership
  guarantee: on a shared host a local attacker can win the rm→clone window,
  own the recreated dir, and substitute the cloned `aai-sync.sh` — which the
  script subsequently EXECUTES (`bash "$SYNC" "$TARGET"`), yielding arbitrary
  code execution.

## Root Cause
- The temp dir is treated as a reusable fixed path across retry attempts: it is
  wiped and re-created at the mktemp path itself, rather than mktemp's dir being
  retained as a secure parent with clones going into a fresh subdirectory.

## Current Cost / Risk
- Real local code-execution vector on shared multi-user Linux hosts with a
  world-writable `/tmp`. Mitigated on macOS and single-user machines (per-user
  `$TMPDIR`), so low reachability on typical dev laptops — but the cloned source
  is EXECUTED, so the impact is severe where reachable. Found in PR #67
  post-merge review (review-20260716-120448.md NB-2), dispositioned as a
  follow-up.

## Steps to Reproduce
- Shared host, world-writable `$TMPDIR`; a watcher recreates the freed mktemp
  path as an attacker-owned empty dir in the `rm`→`clone` window; the clone
  lands in the attacker's dir; `aai-update.sh` then executes the swapped
  `aai-sync.sh` from it.

## Expected vs Actual
- Expected: the `mktemp -d` dir is never freed/recreated; clones go into a fresh
  subdirectory (`"$TMP/src"`) of the retained, securely-owned parent, and only
  that subdirectory is wiped between attempts — ownership guarantee preserved
  end to end.
- Actual: the mktemp path itself is `rm -rf`'d and recreated by the clone.

## Acceptance Criteria
| AC | Status | Evidence |
|---|---|---|
| AC-001: aai-update.sh retains the `mktemp -d` dir as a secure parent for the whole run; every clone/retry targets a fresh subdirectory of it (never the mktemp path itself); only the subdirectory is wiped between attempts. The mktemp path is never `rm -rf`'d-and-recreated. | pending | |
| AC-002: aai-update.ps1 gets the parity fix (same retain-parent / clone-into-subdir shape). | pending | |
| AC-003: behavior unchanged on the happy path and the anonymous-clone fallback — update still succeeds; `--keep-temp` still works; `bash -n` / pwsh parse clean; any existing aai-update test stays green. | pending | |

Ceremony justification: security correctness fix to two sibling updater scripts
(sh + ps1) + parity; no engine/protected-path change (L1). `.aai/scripts/`
updaters are not on protected_paths_l3.

## Verification
- Test/assert the clone target is a subdirectory of the retained mktemp dir and
  the mktemp path is never removed mid-run (grep the script for `rm -rf "$TMP"`
  patterns; assert the new subdir shape); `bash -n aai-update.sh` OK; pwsh parse
  OK; happy-path dry-run if feasible.

## Notes
- Source: docs/ai/reviews/review-20260716-120448.md NB-2; decisions.jsonl
  disposition (pr-67-post-merge-review). Fix shape named by the reviewer:
  "keep the mktemp dir as parent, clone into $TMP/src and wipe only the subdir".
