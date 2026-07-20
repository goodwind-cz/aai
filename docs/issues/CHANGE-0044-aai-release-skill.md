---
id: aai-release-skill
number: 44
type: change
status: draft
links:
  pr: []
  commits: []
---

# Portable `/aai-release` skill — cut a release (self-host or any deployed project)

## Summary
- Add a portable, deterministic release-cut capability to the AAI layer: a
  `/aai-release` skill (thin wrapper) backed by a `aai-release.{sh,ps1}` script
  that rolls the root `CHANGELOG.md` `[unreleased]` section into a dated version,
  commits it, creates an annotated git tag, publishes a GitHub release with notes
  from that section, and pushes — with an operator gate and a safe dry-run. It
  works identically when releasing AAI itself and when releasing a downstream
  project that has the AAI layer deployed.

## Motivation / Business Value
- Today releasing is manual and undocumented as an executable step: the last cut
  (`v2026.07.04`) was hand-made, and there is NO release-cut script (only
  `INTAKE_RELEASE.prompt.md`, which documents a *plan*, not the cut). AAI's
  pattern is "a deterministic script owns the mechanics; the skill is a thin
  wrapper" (cf. `aai-update.sh`, `metrics-flush.mjs`, `close-work-item.mjs`).
  Every deployed project inherits the same repeatable, evidence-printing cut
  instead of re-deriving it. Consumers pull `@main`, so a disciplined,
  gated cut also protects release integrity.

## Scope
- In scope:
  - `.aai/scripts/aai-release.sh` (POSIX/bash) + `.aai/scripts/aai-release.ps1`
    (PowerShell parity) — the deterministic cut engine.
  - `.aai/SKILL_RELEASE.prompt.md` — the canonical thin-wrapper prompt.
  - `.claude/skills/aai-release/SKILL.md` (+ `.codex/`, `.gemini/` tree parity) —
    the `/aai-release` invocation wrappers.
  - `.aai/system/PROFILES.yaml` — classify every new `.aai/**` file (core).
  - `tests/skills/test-aai-release.sh` — Linux-portable suite (runs in the
    enforced skill-suite CI gate).
  - `docs/USER_GUIDE.md` + `CHANGELOG.md` — document the skill.
- Out of scope:
  - Changing the versioning scheme or forcing SemVer.
  - The git-flow release/hotfix BRANCH creation (`INTAKE_RELEASE` remains the
    planning half; this skill is the cut half — it tags the current branch).
  - Auto-releasing / CI-triggered releases (this is operator-invoked only).

## Affected Area
- The vendored AAI layer (`.aai/`, agent skill trees), the profile manifest, the
  test suite, and user docs.

## Desired Behavior (To-Be)
- `/aai-release` (→ `aai-release.sh`) cuts a release from the repo it runs in,
  operating on that repo's root `CHANGELOG.md` and its own git+`gh` remote.

## Acceptance Criteria
- AC-001 (dry-run, default-safe): `aai-release.sh --dry-run` prints the resolved
  version, the CHANGELOG rollup it WOULD write, the tag name, and the release
  notes preview — and changes NOTHING (no commit/tag/release/push). Exit 0.
- AC-002 (the cut): with an explicit confirm flag, the script (a) rewrites
  `CHANGELOG.md` — moves every `## [unreleased] — …` block under a new
  `## [<version>] — <YYYY-MM-DD>` heading and leaves a fresh empty `[unreleased]`
  scaffold on top (line-surgical, idempotent); (b) commits `chore(release):
  <version>` staging only `CHANGELOG.md`; (c) creates an ANNOTATED tag
  `<version>`; (d) `gh release create <version>` with title + body extracted from
  the just-rolled CHANGELOG section; (e) pushes commit + tag. Verified against a
  scratch repo (never the real upstream in tests).
- AC-003 (fail-closed preconditions, zero writes on refusal): the script refuses
  with a clear message and makes NO changes when — the working tree is dirty; the
  `[unreleased]` section is missing or empty; a tag for the resolved version
  already exists; `gh` is absent or unauthenticated (for the publish step only —
  dry-run must still work offline); or run outside a git repo / no `CHANGELOG.md`.
- AC-004 (portable + generic): the script has bash and PowerShell parity, uses no
  BSD-only constructs (no `mktemp -t <bare>`, no `stat -f`-first — per LEARNED
  2026-07-19), resolves the version from `--version <v>` (any scheme accepted,
  incl. SemVer) or defaults to CalVer `vYYYY.MM.DD` when omitted, and makes no
  AAI-repo-specific assumptions (repo root + `CHANGELOG.md` + a git/`gh` remote
  are its only inputs) so it runs the same in a deployed target project.
- AC-005 (layer integrity): every new `.aai/**` file is classified in
  `PROFILES.yaml` (core), `test-aai-release.sh` exists and is green on the Linux
  CI skill-suite gate, and `docs/USER_GUIDE.md` + `CHANGELOG.md` document
  `/aai-release`.

## Verification
- `bash .aai/scripts/aai-release.sh --dry-run` in a scratch repo with a seeded
  `[unreleased]` CHANGELOG → exit 0, prints plan, tree unchanged (AC-001).
- A scratch-repo cut (confirm flag, `gh` mocked/skipped or a throwaway local
  remote) → CHANGELOG rolled, `chore(release)` commit present, annotated tag
  created, notes match the section, push attempted (AC-002).
- Precondition matrix in a scratch repo: dirty tree / empty unreleased / existing
  tag / missing gh each → non-zero, zero writes (AC-003).
- `./tests/skills/test-aai-release.sh` exits 0; `./tests/skills/test-aai-layer-profiles.sh`
  exits 0 (new files classified); the skill-suite CI job stays green on Ubuntu.
- `node .aai/scripts/spec-lint.mjs` / docs-audit remain CLEAN.

## Constraints / Risks
- Tests MUST NOT publish a real release or push to the real upstream — exercise
  the engine in throwaway git repos under a temp dir, with the `gh` publish step
  stubbed or gated behind an env flag the test does not set. Creating real tags
  is destructive and outward-facing.
- Publishing a release is outward-facing: the cut must be operator-gated
  (explicit confirm), never implicit; the agent NEVER auto-publishes (mirrors the
  operator-only-merge boundary, Constitution Art. 7).
- CHANGELOG rewriting is line-surgical and must be idempotent and preserve entry
  content byte-for-byte (only headings move); a malformed `[unreleased]` must
  fail-closed, never silently drop entries.
- Cross-platform: bash + PowerShell parity kept in lockstep (like the other
  `aai-*.{sh,ps1}` pairs); the Linux CI gate is the enforcing check.
- No secret referenced — SECRETS PREFLIGHT skipped (the `gh` token is read by the
  `gh` CLI itself; the script never reads/echoes it).

## Notes
- Relationship to existing pieces: `INTAKE_RELEASE.prompt.md` documents the
  release PLAN (scope, gates, rollback, sign-off) under `docs/releases/`; this
  skill is the executable CUT. They compose but neither requires the other.
- Dogfooding: once merged, `/aai-release` can cut AAI's own next version from the
  current `[unreleased]` (CHANGE-0041/0042/0043) — a natural first use, done
  separately by the operator.
