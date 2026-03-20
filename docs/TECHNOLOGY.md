# Technology Contract

Generated at (UTC): 2026-03-06T15:35:23.6130438Z
Generator: .aai/scripts/aai-canonicalize.ps1

## Languages
- TypeScript (Node.js, ESM)

## Package/Dependency Managers
- npm-compatible package metadata in `apps/control-plane/package.json`

## Test Tooling (Detected by Files)
- Bash integration test suite under `tests/remote-orchestration/`
- Node.js built-in `node:sqlite` runtime

## Build/Runtime Tooling (Detected by Files)
- Node.js 24 with `--experimental-strip-types`
- SQLite WAL mode

## CI/CD Signals
- Not detected

## Notes
- The remote-orchestration MVP intentionally avoids external npm runtime dependencies.
- Current execution model is a host CLI plus manifest-first worker preparation.
