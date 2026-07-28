# Test Skills — AAI Skill Testing Framework

## Goal
Discover installed AAI skills and run their test suites via the real
framework, `tests/skills/test-framework.sh`. Do NOT hand-roll a skill count,
a dependency table, or a report format — the framework computes all of it.

## Usage
```bash
bash tests/skills/test-framework.sh                # all skills
bash tests/skills/test-framework.sh --skill aai-share
bash tests/skills/test-framework.sh --fix           # accepted but a NO-OP today (see step 7)
bash tests/skills/test-framework.sh --verbose
```
Prefer `.aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh ...`
when running under a loop/orchestrator — it wraps the same invocation in a
killable process group with a timeout watchdog (SPEC-0009), so a hung suite
cannot strand the run.

## Instructions
1. Discover the current fleet — do not assume a fixed count:
   ```bash
   ls tests/skills/test-aai-*.sh | wc -l
   ```
   Each `tests/skills/test-aai-<name>.sh` maps to skill `aai-<name>` (e.g.
   `test-aai-share.sh` -> `aai-share`). The count changes as skills are added
   or retired; never hardcode a number from a prior run.
2. Run `test-framework.sh` (see Usage). It sets up an isolated
   `RUN_DIR=tests/skills/results/test-<UTC-timestamp>/`, runs each
   `test-aai-*.sh`, and writes one `<skill>.result` + `<skill>.log` pair per
   skill into that directory.
3. Exit-code contract per individual suite (and relayed by the framework):
   - `0` — all tests in that suite passed
   - `1` — at least one test in that suite failed
   - `42` — suite SKIPPED (a required dependency was missing); this is not a
     failure — do not report it as one
4. Framework-level exit codes: `0` all suites passed, `1` some suite failed,
   `2` framework error (bad arguments, setup failed).
5. Relay the framework's own summary (total/passed/failed/skipped, results
   dir path) verbatim. Do not recompute percentages by hand.
6. On failure, read the specific log named in the summary:
   `cat tests/skills/results/<run-id>/<skill>.log`, and report the actual
   error text — do not guess at a cause.
7. `--fix` is accepted but repair actions are NOT implemented (the flag is
   currently a no-op) — never claim repairs happened; if repairs are
   needed, do them explicitly and say what you did.

## Test Isolation
Every suite runs against isolated fixtures/temp dirs and cleans up on exit
(success or failure) via `trap ... EXIT`. No suite is expected to mutate the
main repository's tracked state.

## Safety
- Read-only against the main repository's tracked files.
- No network calls to production services.
- Automatic cleanup of temp directories on success and failure.

BEGIN NOW.
