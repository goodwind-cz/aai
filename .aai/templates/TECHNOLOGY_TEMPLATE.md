# Technology Contract Template

<!-- AAI-TEMPLATE: TECHNOLOGY_TEMPLATE v1 -->

- Generated from: `.aai/templates/TECHNOLOGY_TEMPLATE.md`
- Status: template-seed
- Ownership: project-generated
- Regenerate with: `.aai/TECH_EXTRACT.prompt.md`
- Notes:
  - Replace placeholders only with evidence-backed facts.
  - Keep `UNKNOWN` or `UNCERTAIN` where evidence is missing.
  - Promote durable architectural conclusions into decisions/specs when needed.

## Evidence Basis
- Generated at (UTC): <ISO 8601 UTC>
- Repository root: <path or repo name>
- Evidence sources:
  - package manifests / lockfiles
  - Dockerfiles / container images
  - CI configs
  - runtime configs
  - tests
  - ADR / RFC / PRD references

## Runtime / Platform
- OS / platform:
- Runtime(s):
- Deployment target(s):
- Containers / orchestration:

## Backend
- Languages:
- Frameworks:
- Data / persistence:
- Messaging / jobs:
- Auth / identity:

## Frontend (if any)
- Languages:
- Frameworks:
- Rendering model:
- State / data fetching:

## Testing
- Test invocation (contract): ONE canonical, allowlist-stable command shape
  per platform, run from the repository root (the wrapper is vendored to
  every AAI project):
  - Windows: `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 <command...>`
  - POSIX: `bash .aai/scripts/aai-run-tests.sh <command...>`

  Run it from the repository root; when elsewhere, cd to the repo root first - never rewrite the script path relative to the current directory.
  Never invoke bash.exe, sh, or wsl directly for test runs, and never via CWD-relative paths from a subdirectory - the dispatcher owns interpreter routing.
- Unit:
- Integration:
- E2E:
- Contract / smoke:

## Tooling
- Package manager(s):
- Build tooling:
- Lint / format:
- Local developer tooling:

## Constraints
- Required:
- Preferred:
- Operational:

## Forbidden / Discouraged
- Forbidden:
- Discouraged:

## Open Questions / Uncertainties
- <question or UNKNOWN area>

## Version Matrix
| Technology | Version | Status | Evidence |
|------------|---------|--------|----------|
| <name>     | UNKNOWN | uncertain | <file/path> |

## Change Log
- <append-only summary of added/updated/deprecated/removed facts>
