# Technology Contract

<!-- AAI-TEMPLATE: TECHNOLOGY_TEMPLATE v1 -->

- Generated from: `.aai/templates/TECHNOLOGY_TEMPLATE.md`
- Status: generated
- Ownership: project-generated
- Regenerate with: `.aai/TECH_EXTRACT.prompt.md`
- Notes:
  - Replace placeholders only with evidence-backed facts.
  - Keep `UNKNOWN` or `UNCERTAIN` where evidence is missing.
  - Promote durable architectural conclusions into decisions/specs when needed.

## Evidence Basis

- Generated at (UTC): 2026-07-06
- Repository root: aai (the AAI framework repository, self-hosted)
- Evidence sources:
  - repository file inventory (`.aai/scripts/`, `tests/`, `.github/workflows/`)
  - script headers and SPEC references in `.aai/scripts/*.mjs`
  - CI config: `.github/workflows/ps1-quality.yml`
  - `CHANGELOG.md`, `docs/specs/`, `docs/rfc/`
  - absence checks: no `package.json`, no lockfiles, no Dockerfiles, no
    container or deployment configs found in the repository

## Runtime / Platform

- OS / platform: cross-platform developer tooling — macOS/Linux via POSIX
  shell, Windows via PowerShell mirrors (Windows PowerShell 5.1 and pwsh 7)
- Runtime(s): Node.js for all `.mjs` tooling, invoked as plain `node`
  (`#!/usr/bin/env node`); no minimum version is pinned anywhere (UNKNOWN
  floor — scripts use only `node:` stdlib imports and modern ESM)
- Deployment target(s): none — this repository is a vendored documentation and
  workflow layer, not a deployed service. Optional report publishing to
  Cloudflare Pages via the Wrangler CLI (`.aai/scripts/cloudflare-share.sh`/
  `.ps1`, `/aai-share`).
- Containers / orchestration: none detected

## Backend

- Languages:
  - JavaScript (Node ESM, `.mjs`) — all CLI tooling in `.aai/scripts/*.mjs`
    (`state.mjs`, `docs-audit.mjs`, `check-state.mjs`, `generate-docs-index.mjs`,
    and others); no TypeScript anywhere in the repository
  - POSIX shell / bash — installers, loop runners, hooks, and test suites
    (`.aai/scripts/*.sh`, `tests/**/*.sh`); test suites carry a hard bash-3.2
    compatibility rule (the macOS default bash — see
    `tests/skills/test-aai-state.sh` header)
  - PowerShell — 5.1-compatible mirrors of the installers/hooks/runners
    (`.aai/scripts/*.ps1`)
  - Markdown prompt files (`.aai/*.prompt.md`) are the agent-facing "source
    code" of the workflow itself
- Frameworks: none — dependency-free by design (Node stdlib only)
- Data / persistence:
  - `docs/ai/STATE.yaml` — runtime state; written only through the
    transactional `state.mjs` CLI (SPEC-0012), which uses a structural
    line-edit engine with no YAML library; hand-edits are forbidden
  - Append-only JSONL ledgers: `docs/ai/METRICS.jsonl`, `docs/ai/EVENTS.jsonl`,
    `docs/ai/LOOP_TICKS.jsonl`, `docs/ai/decisions.jsonl`
- Messaging / jobs: none
- Auth / identity: none in-repo (gh CLI and Wrangler authentication are
  external operator concerns)

## Frontend (if any)

- Languages: static, self-contained HTML/CSS/JS artifacts only (generated
  catalogs and dashboards, e.g. `docs/SKILL_CATALOG.html` and the output of
  `generate-dashboard.mjs`)
- Frameworks: none (vanilla JS, single-file pages)
- Rendering model: static pages, data inlined at generation time
- State / data fetching: none

## Testing

- Unit: bash test suites in `tests/skills/` (bash-3.2 compatible), executed
  through the `.aai/scripts/aai-run-tests.sh` process-group wrapper
  (SPEC-0009 — killable process group, inline timeout watchdog)
- Integration: self-hosting suites in `tests/self-hosting/` (the framework
  validates itself); shared fixtures in `tests/fixtures/`
- E2E: not applicable (no deployed surface)
- Contract / smoke: Pester suites for PowerShell
  (`tests/skills/aai-update.Tests.ps1`) and PSScriptAnalyzer static analysis
  (settings: `.aai/scripts/PSScriptAnalyzerSettings.psd1`)

## Tooling

- Package manager(s): none — no `package.json` or lockfile exists; zero npm
  dependencies (verified by absence check, 2026-07-06)
- Build tooling: none — scripts run directly, no build or transpile step
- Lint / format: PSScriptAnalyzer for `.ps1`; docs body lint for governed
  Markdown (`node .aai/scripts/docs-audit.mjs --lint-body` /
  `--lint-body-file`, SPEC-0013)
- CI/CD: GitHub Actions — `.github/workflows/ps1-quality.yml` (parse-checks
  every `.ps1` under Windows PowerShell 5.1 and pwsh 7, plus PSScriptAnalyzer
  and Pester on Linux)
- Local developer tooling: git + gh CLI (PR ceremony via `/aai-pr`; the agent
  never merges), installable pre-commit hook
  (`.aai/scripts/install-pre-commit-hook.sh`/`.ps1`), optional Wrangler CLI
  for `/aai-share`

## Constraints

- Required:
  - Zero runtime dependencies: Node stdlib only; nothing may introduce a
    package manifest or lockfile
  - `.mjs` scripts must run with a plain `node` invocation
  - Shell test suites must remain bash-3.2 compatible (no `${var^^}`, no
    `declare -A`, no `mapfile`)
  - `.ps1` scripts must parse under both Windows PowerShell 5.1 and pwsh 7
    (enforced by the ps1-quality CI workflow)
  - `docs/ai/STATE.yaml` is written only through `state.mjs`; JSONL ledgers
    are append-only
- Preferred:
  - Conventional-commit style messages (`feat:`/`fix:`/`docs:`/`chore:` —
    see git history)
  - Keep a Changelog format for `CHANGELOG.md`
- Operational:
  - PRs are opened via `/aai-pr`; merging is an operator-only action
  - Pre-commit quality gates run via `.aai/scripts/pre-commit-checks.sh`/`.ps1`
    and the installed hook; docs close gate and body lint are controlled by the
    `close_gate` / `body_lint` keys in `docs/ai/docs-audit.yaml`
    (report-only by default, SPEC-0011/SPEC-0013)

## Forbidden / Discouraged

- Forbidden:
  - Adding npm/pip/gem/etc. dependencies or package manifests
  - Hand-editing `docs/ai/STATE.yaml`
  - Bash-4+ features in test suites
- Discouraged:
  - Duplicating counts or lists across docs — defer to a single canonical
    source instead (they rot)

## Open Questions / Uncertainties

- Minimum supported Node.js version is not pinned or documented anywhere
  (developed and tested against current Node releases; floor is UNKNOWN)

## Version Matrix

| Technology | Version | Status | Evidence |
|------------|---------|--------|----------|
| Node.js | UNKNOWN (no pin) | confirmed in use | `#!/usr/bin/env node` in `.aai/scripts/*.mjs` |
| bash | 3.2 compatibility floor (tests) | confirmed | `tests/skills/test-aai-state.sh` header |
| PowerShell | 5.1 and 7.x | confirmed | `.github/workflows/ps1-quality.yml` |
| PSScriptAnalyzer | UNKNOWN (PSGallery latest) | confirmed in CI | `.github/workflows/ps1-quality.yml` |
| Pester | 5.x | confirmed in CI | `.github/workflows/ps1-quality.yml` cache key |
| gh CLI | UNKNOWN | confirmed in use | `/aai-pr` skill (`gh pr create`) |
| Wrangler CLI | UNKNOWN | optional | `SKILLS.md` (`/aai-share` prerequisites) |

## Change Log

- 2026-07-06: Full rewrite. Replaced the 2026-03-06 PowerShell-generated stub
  ("Unknown" / "Not detected") with an evidence-based contract produced by
  manual repository inspection following `.aai/TECH_EXTRACT.prompt.md`
  (structure: `.aai/templates/TECHNOLOGY_TEMPLATE.md`). Verified by direct
  checks: no package manifest exists; CI workflow present; test suites and
  wrappers present; `state.mjs` transactional CLI present.
