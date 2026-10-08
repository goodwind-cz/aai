# Child mutation proof remediation handoff

Scope: `pr-generic-url-validity` / SPEC-0211. Maker repair only; independent recheck remains pending.

## Cause and repair

The close dry-run refused TEST-001 and TEST-007 because their original mutation records named private base `3deb0568a7206ff3aa603324ded7668c50910118`, which is absent from shipping HEAD ancestry. The source and suite stayed at SHA-256 `a69e20c313a1d34c2b8e0095545b63e98337cd7e7b2fa825f9bcf69fd715d958` and `7de8c1cb5460254a314e8df2232296e18e007e5b109da42e5ef78ec35326331c` throughout this repair.

The original records and zero-context patches are byte-exact copies under `docs/ai/tdd/spec-pr-generic-url-validity/ancestry-history/`. Both original patches hash to `57d110a45d57883f517da8eabecacfc497b9592e934b642753cec335729b8b62`; original record hashes are `202e1e4ac396a11c7e1f2d6cfc4ff19b394a94107bc78dfec7c09d707ee573e1` (TEST-001) and `42a9302fddbf5dfb0860397e060d12a6548a3d4e1cdb0b956b69b83c421ca616` (TEST-007). These match the original files in Git commit `6d3f616a96337ff1580968467fadfa9756a87a52` before remediation. The original maker manifest and reports were not edited.

The original patches expressed deletion of `validateExplicitUrl(remote);` but did not apply to committed source with ordinary `git apply`. A patch generated from a disposable copy of the same committed source deletes only that line and includes surrounding context. Its SHA-256 is `faae797215ef14974008e857c55bac0d880d6b7497a59ff6e5f02e7d482dfbec`. The canonical mutation runner copied these patch bytes into each live patch path and measured both rows afresh, deriving `base_commit`, `tree_hash`, `run_at_utc`, verdict and target hash itself. No provenance field was hand-edited.

## Maker checks

- `mutation-run.mjs` patch runs: TEST-001 RED and TEST-007 RED, both exit 0; logs `ancestry-patch-TEST-001.log` and `ancestry-patch-TEST-007.log` in the same TDD directory.
- `mutation-run.mjs --replay`: 2/2 still RED, 0 inconclusive, 0 restamped; `ancestry-patch-replay.log`.
- `mutation-gate.mjs --spec docs/specs/SPEC-0211-spec-pr-generic-url-validity.md --json`: `GATE PASS: 2 row(s) satisfied degraded=0 unstamped=0 uncomparable=0`.
- HEAD is `6d3f616a96337ff1580968467fadfa9756a87a52`; both new records name it as `base_commit`, and it is an ancestor of HEAD. The current source and suite hashes match the dispatch. The Git index is unchanged.

This maker check does not update an independent Validation or Review verdict. Root should reset only the failed `last_validation` block and set the child phase to validation; the next tick performs the independent proof and close prerequisite check. Existing child Review PASS stays untouched. Parent assembly and separate case-identity work remain outside this handoff.
