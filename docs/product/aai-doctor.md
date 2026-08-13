---
id: aai-doctor
type: product
capability: aai-doctor
status: current
delivered_by:
  - CHANGE-0079
  - spec-doctor-determinize
  - CHANGE-0135
  - spec-doctor-win-selftest
spec: docs/specs/SPEC-0122-spec-doctor-win-selftest.md
updated: 2026-08-13
---

# `/aai-doctor` diagnoses the real Windows and agent-CLI environment it runs on

## What it does

`/aai-doctor` (`node .aai/scripts/aai-doctor.mjs`) is the AAI environment
health check — a deterministic, zero-dependency script that reports one
`PASS`/`WARN`/`FAIL`/`SKIP` line per category plus an overall verdict. The
original 13 categories cover core files, role prompts, skills, knowledge
files, `STATE.yaml` health, telemetry, git status, hooks, the RFC-0001
migration matrix, docs hygiene and vendored-layer drift.

This scope adds three more categories that answer a different question:
CI proves GitHub's own Windows image, but the failures that actually cost
time surfaced on a person's own Windows machine — a sticky-escalation
incident and a case-duplicated `Path`/`PATH` environment variable that broke
the test wrapper, both found only by manually reading logs after the fact.
`/aai-doctor` now makes that diagnosis a command instead of a debugging
session:

- **CAT-14 (Windows Self-Test)** runs the REAL `.aai/scripts/aai-run-tests.ps1`
  wrapper three times, on the machine `/aai-doctor` itself is running on —
  once expecting a clean success, once expecting a timeout, and once
  deliberately inducing a spawn failure — and reports whether each of those
  three real behaviors happened as documented.
- **CAT-15 (Windows Environment)** reports the environment the wrapper
  itself actually sees: any case-colliding environment variable group (the
  `Path`/`PATH` class of bug), which PowerShell engines are installed and
  their versions, the Git Bash candidates the wrapper would consider and
  which one it would pick, and whether Windows Subsystem for Linux is
  absent, installed-with-no-distro, or fully functional.
- **CAT-16 (Agent CLI Probe)** reports which AI agent command-line tools
  (`claude`, `codex`, `gemini`) are installed and their exact version
  string, and honestly reports that four specific orchestration-capability
  questions cannot be answered from outside a running agent session — see
  "Limits and non-goals" below.

## How to use it

```
node .aai/scripts/aai-doctor.mjs
node .aai/scripts/aai-doctor.mjs --json
node .aai/scripts/aai-doctor.mjs --strict
```

No flags are required. `--json` prints one structured document instead of
the text report — CAT-14/CAT-15/CAT-16 each carry an extra `detail` object
with the full self-test/environment/CLI data, present in both text mode
(as an indented `detail:` line under the category) and `--json`.

`--strict` changes only the exit code: without it, `/aai-doctor` exits 0 on
a clean report or on warnings alone, and 1 only when something actually
FAILs — unchanged from before this scope. With `--strict`, it also exits 1
when any category reports WARN, so an automated caller (a pre-flight check,
a CI step) can treat "everything is at least PASS or a named SKIP" as the
bar instead of "nothing outright broke."

CAT-14 and CAT-15 run only on a real Windows host with `pwsh` or
`powershell.exe` available; anywhere else (macOS, Linux, or a Windows host
with neither engine installed) both report a named `SKIP` and spawn
nothing. CAT-16 runs on every host — the agent-CLI probe has no
Windows-specific dependency.

## Data model

None persisted. Every category is computed fresh on each invocation from
the live filesystem, git state, spawned subprocess output, and (on
Windows) a single JSON document `.aai/scripts/aai-win-selftest.ps1` prints
to its own stdout, which `aai-doctor.mjs` parses and never writes back to
disk.

## Interfaces and contracts

- `node .aai/scripts/aai-doctor.mjs [--root <path>] [--json] [--strict]` —
  exit 0 on a clean report or warnings-only (without `--strict`), exit 1 on
  any FAIL (or, with `--strict`, on any WARN too), exit 2 on a CLI usage
  error (unknown flag or a missing `--root` value).
- Category ids `CAT-14`, `CAT-15`, `CAT-16` are additive — the pre-existing
  `CAT-01`..`CAT-13` ids, their status values, and their reason wording are
  unchanged by this scope.
- `.aai/scripts/aai-win-selftest.ps1` is a new vendored script consumed only
  by `aai-doctor.mjs`; it is not a standalone user-facing command, though it
  can be run directly (`pwsh -File .aai/scripts/aai-win-selftest.ps1`) for
  manual inspection — it prints the same JSON document to stdout.
- Zero network access and zero LLM calls, on every platform, in both the
  Node and PowerShell halves of this feature.

## Limits and non-goals

- **What the self-test proves:** that `.aai/scripts/aai-run-tests.ps1`'s
  documented success/timeout/spawn-failure contract genuinely holds on THIS
  machine, right now — the same technique this repository's own CI proved
  once on GitHub's Windows image, now runnable anywhere.
- **What it does NOT prove:** a green self-test on one Windows machine says
  nothing about a different Windows machine — different WSL distro state,
  different Git-for-Windows install location, different PowerShell version,
  different antivirus/EDR interference are all real-world variables the
  self-test cannot see in advance. It also cannot reproduce the exact
  historical `Path`/`PATH` duplicate-casing defect in-process; CAT-15
  mitigates this by directly REPORTING a live collision if one currently
  exists, which is what actually matters for diagnosis.
- The four `SUBAGENT_PROTOCOL` capability fields (`multi_agent_backend`,
  `spawn_agent_available`, `spawn_model_catalog`, `fork_turns_supported`)
  are always reported as the literal string `UNKNOWN`, never inferred as
  true or false — they are runtime properties of the orchestrating agent
  session and are not observable from a child process that `/aai-doctor`
  spawns. `/aai-doctor` never keys any behavior on an installed CLI's name.
- CAT-14's spawn-failure arm never touches the host's real Git for Windows
  installation: it doctors only a throwaway child process's own
  `ProgramFiles`/`PATH` environment, pointed at a temp directory holding a
  non-executable decoy file, and cleans that temp directory up afterward.

## Links

- Request: docs/issues/CHANGE-0135-doctor-win-selftest.md
- Spec: docs/specs/SPEC-0122-spec-doctor-win-selftest.md
- Validation evidence: docs/ai/validation/ (gitignored runtime directory —
  reports land here per ride, not committed to the repo)
