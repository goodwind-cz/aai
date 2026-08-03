---
id: gitignore-seed
number: 115
type: change
status: done
user_visible: true
ceremony_level: 1
links:
  pr:
    - 219
  commits:
    - cbf881efabd496a79d0da111c0b17d154dfba0fa
---

# Change — bootstrap seeds the runtime-sidecar gitignore block into target projects

## Summary
- Pre-deployment gap (operator-found): `ensure_gitignore()` in
  aai-bootstrap.sh seeded only 3 skill-cache patterns into a target
  project's .gitignore — none of the AAI runtime sidecars. In a fresh
  downstream project, docs/ai/STATE.yaml, hitl-channel.json, briefs/ etc.
  sat untracked; one `git add -A` commits them, and a committed STATE.yaml
  breaks the per-developer single-writer model (RFC-0001) outright.
- Fix: the bootstrap now seeds the runtime block (STATE.yaml, LOOP_TICKS,
  hitl-channel.json, briefs/reports/tdd/friction/archive globs, loop/,
  session-context, pre-compact backup, INDEX.audit.md) under one marker
  comment — idempotent (grep-before-append per pattern; marker written
  once), pre-existing user entries respected, dry-run aware. Deliberately
  NOT ignored: factory-report/overview/dashboard HTML+JSON — committed
  artifacts regenerated at close, mirroring the AAI repo itself.

## Acceptance Criteria
- AC-001: fresh fixture bootstrap seeds all runtime patterns + marker
  (suite-asserted).
- AC-002: re-run adds nothing (idempotent); a pre-existing user pattern is
  not duplicated; user entries survive.
- AC-003: no dashboard/report artifact pattern is ever seeded as ignored.

## Verification
- tests/skills/test-aai-bootstrap.sh: extended dynamic-skills assertions +
  new test_gitignore_seed_idempotent_and_respectful; suite green.

## Constraints / Risks
- Ceremony L1, strategy direct. Bash-only surface (no ps1 twin has
  gitignore logic). Existing downstream projects get missing patterns
  appended on their next bootstrap/update run — additive only.
