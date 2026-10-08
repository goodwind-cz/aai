# Disposition: split raw SSH path identity repair for PR434

Date: 2026-10-08
Parent ref: pr-capability-preflight
Bounded repair: raw-ssh-path-identity
Recorded by: orchestrator

## Authority and completed boundary

The owner again instructed "Pokracuj" (continue). This continues the authorized internal repair of PR434. It does not waive any review, Validation, CI or merge gate. The existing owner decision DECISION-pr-capability-preflight-test008-followup.md permits provider implementation changes only where actual evidence establishes an existing requirement defect.

The TEST008/replay-budget follow-up has completed two finding-bearing independent review rounds: review-20261008T004441Z-pr434.md at ebbd0eaeaebfa9015f550193df6f0b54afc338c3, then review-20261008T012048Z-pr434-replay.md at 5685e3625bc94f00ade55d9cf491158dde058177. Their failures remain truthful and immutable. Neither review remains pending and neither verdict is reset to imply a PASS.

## Split and rationale

The second review independently demonstrates that WHATWG URL normalization erases raw SSH dot segments before the CLI validates identity. Real Git sends the literal remote path, while the preflight can attest a transformed repository. Its isolated upload-pack negative and positive controls establish an existing Spec-AC-01 defect without claiming a live GitHub server result.

Treat this as a separate bounded internal remediation package, raw-ssh-path-identity, within the already open PR434 and authorized worktree. Do not run a third remediation/review cycle of the replay-budget package. This is the orchestrator's implementation split under .aai/AGENTS.md operator contract rules1 and3 (internal fixes proceed without asking; "A third finding-bearing round means the ride was cut wrong: split it, do not re-verify it."). It creates no capability or acceptance criterion, no new worktree, no scope-excluded review and no numerical cap waiver. Parent ref/branch and the existing PR retain their identity; explicit role scope/timing and source hashes distinguish the new package.

Only the demonstrated raw-path identity cause, affected regression controls and source-bound evidence may change. Preserve all historical failures, reports, stamps, byte transports, aliases and append-only ledger prefixes. Existing replay-budget and SSH443 repairs must remain proved.

## Gates and stopping rule

The maker runs canonical Debug/TDD/Remediation and returns a checked result with exact scope. A fresh independent reviewer reviews the complete base-to-new-head PR scope, including this repair. Its first finding-bearing round belongs to this new package; a further finding requires a second explicitly scoped round, and any exhausted package is split or parked rather than silently reverified. This record does not authorize unlimited relabeling of unrelated findings.

Only an actual fresh Review PASS authorizes the previously approved metadata-only closure. Final source-bound green native/full CI and independent Validation remain required, followed by the external review sweep. Frozen-spec signoff debt remains owed. Merging stays operator-only.
