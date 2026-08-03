---
id: validation-runtime-ignore
number: null
type: change
status: draft
user_visible: true
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — validation run evidence is per-dev runtime: docs/ai/validation ignored + canonicalized

## Summary
- Operator-found in a downstream project: a Validation role emitted run
  logs/transcripts into a self-invented `docs/ai/validation/` and the files
  leaked as untracked noise (no canonical ignored home exists for
  validation RUN output; VALIDATION.prompt.md names none, so the agent
  improvised — same failure shape as any missing-canonical-location gap).
- Fix: `docs/ai/validation/**` joins the runtime-ignore class (mirroring
  `docs/ai/tdd/**`): AAI .gitignore (+.gitkeep), bash bootstrap seed, ps1
  migrate-state parity — canonicalizing the dir as the legal ignored home
  for validation run evidence. The class boundary stays: VERDICTS live in
  EVENTS + spec AC tables (committed); curated review reports in
  docs/ai/reviews/ stay committed per the H4 contract; raw run output never
  commits.

## Acceptance Criteria
- AC-001: bootstrap seeds `docs/ai/validation/**` (suite-asserted, exact
  line match).
- AC-002: AAI repo ignores the dir live (`git check-ignore` verified),
  .gitkeep kept.
- AC-003: ps1 migrate list parity.

## Verification
- test-aai-bootstrap.sh extended arm green; live check-ignore; docs-audit
  strict CLEAN.

## Constraints / Risks
- Ceremony L1, direct. Downstreams pick the pattern up on next
  bootstrap/update run (additive).
