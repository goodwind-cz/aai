---
id: watch-ci-cancelled-runs-and-release-gate-docs
type: issue
number: null
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# watch-ci fails on a superseded cancelled run, and the release-notes gate exempts user-facing documentation

## Summary

Two defects found on 2026-10-29, both in CI/release tooling that every ride
uses:

1. `.aai/scripts/watch-ci.mjs --required` reports FAILED when a duplicate run
   of the same workflow on the same head was cancelled, even though the newer
   run of that workflow for that head is still in progress or later passes.
2. `.aai/scripts/release-notes-gate.mjs` `isShipped` (line 8) treats only
   `.aai|.github|.claude|.codex|.agents|.gemini/` paths and root scripts as
   shipped. A pull request that changes only user-facing documentation
   (`SKILLS.md`, `docs/USER_GUIDE.md`, `docs/product/**`) passes as
   "exempt (no shipped surfaces)" and needs neither a CHANGELOG entry nor a
   `no-notes:` reason, so it ships without a release note.

## Reproduction

1. watch-ci (PR #515, head `1edc4a54`, 2026-10-29): two `skill-suite` runs
   were created for the same head; run 40878601419 was cancelled by the
   concurrency group and run 40878615745 continued. `node
   .aai/scripts/watch-ci.mjs --pr 515 --required` printed `watch-ci: FAILED —
   skill test suite (tests/skills/, via test-framework.sh), self-hosting
   smoke` (exit 0 from the pipeline tail, verdict FAILED). The jobs it named
   belonged to the cancelled run; run 40878615745 later passed every job.
   The same pattern blocked a merge decision on PR #516 the same day.
2. Release gate (PR #513, "docs(hermes): expose and verify native AAI skill
   discovery"): changed `SKILLS.md`, `docs/USER_GUIDE.md`,
   `docs/product/hermes-agent-skill-discovery.md`, tests and docs/ai; no
   CHANGELOG entry, no `no-notes:` line. The gate printed `PASS:
   release-notes exempt (no shipped surfaces)`. Release v2026.10.29 shipped
   it with no note; the owner noticed and the note was backfilled by hand
   (PR #515 and `gh release edit`).

## Expected Behavior

1. watch-ci judges each required check by the newest run of that check for
   the current head; a cancelled run that a newer run of the same workflow
   and head supersedes is ignored. A cancellation that is NOT superseded
   still reports as not passed, and ambiguous data still degrades (exit 3)
   rather than guessing PASS.
2. The release-notes gate counts user-facing documentation as a shipped
   surface: at least `SKILLS.md`, `docs/USER_GUIDE.md` and `docs/product/**`
   (Planning confirms the exact list against what downstream users read).
   Such a pull request needs a new `[unreleased]` entry or an explicit
   `no-notes: <reason>`. Internal docs (specs, issues, RFCs, analysis,
   docs/ai) stay exempt.

## Acceptance Criteria

- AC-001: Given a fixture where a required check has a cancelled run and a
  newer in-progress run of the same workflow on the same head, watch-ci keeps
  waiting (pending), and when the newer run passes it exits 0.
- AC-002: Given a cancelled run with no newer run of the same workflow and
  head, watch-ci does not report PASS for that check.
- AC-003: The superseded-run rule matches the one release required-check
  observation already uses (current-head-ci-reader, v2026.10.29), or the
  spec states why it differs; one shared reader is preferred over a second
  copy.
- AC-004: A diff that changes only `docs/USER_GUIDE.md` (or `SKILLS.md`, or a
  `docs/product/` file) with no new `[unreleased]` entry and no `no-notes:`
  fails the release-notes gate naming the path; the same diff with an
  entry, or with `no-notes: <reason>`, passes.
- AC-005: A diff that changes only internal docs (`docs/specs/**`,
  `docs/issues/**`, `docs/rfc/**`, `docs/analysis/**`, `docs/ai/**`) still
  passes as exempt.
- AC-006: The CHANGELOG preamble or the release skill text states which
  documentation paths count as shipped.

## Verification

- Suite tests for watch-ci and the release-notes gate cover AC-001..005 with
  fixtures (no live GitHub calls).
- `node .aai/scripts/release-notes-gate.mjs` on the PR #513 diff shape
  refuses; on an internal-docs diff it passes.
- Selected suites plus one full sweep before close.

## Constraints / Risks

- Both scripts live under `.aai/` and ship downstream; the release gate is a
  release-safety surface. Planning checks whether either is a protected
  (L3) surface and sets ceremony accordingly.
- Widening the gate makes some currently-green doc PRs need a note; that is
  the intended behavior change and goes in the CHANGELOG.
- Node stdlib only (docs/TECHNOLOGY.md).
- Secrets preflight: no secret referenced.

## Notes

- Owner direction 2026-10-29: chose "watch-ci + release gate" as the next
  `/aai-ship` ride.
- Out of scope: the optional Hermes trust hint in `aai-update`; the
  `fu-docs-split-a1n-attribution` correction.
- Intake metrics: autopilot default, human_time_minutes null.
