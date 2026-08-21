---
id: cli-output-survives-a-pipe
number: 153
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-followups
links:
  pr:
    - 268
  commits:
    - 13130bb3b9b6cf1cda0b730e9230b806cef336c0
---

# Change — CLI output must survive being piped

## Summary
- `.aai/scripts/follow-ups.mjs` writes its output with `console.log` and then calls
  `process.exit(0)` immediately. To a file that is fine — stdout is synchronous. To
  a **pipe** it is not: the write is asynchronous, `process.exit` discards whatever
  is still buffered, and the reader gets a prefix.
- Measured 2026-08-20 on the live ledger: `list --json` is **87012 bytes** to a file
  and exactly **65536 bytes** through a pipe. `JSON.parse` fails at position 65522.
  Any caller that pipes the registry into a parser is silently reading a truncated
  ledger and every count it derives is wrong.

## Motivation / Business Value
- This is not a display defect, it is **silent data corruption at the read side**.
  The failure is invisible when the payload is small and appears without warning the
  day it crosses 64 KB — which happened one day after the defect was filed as
  "measured 56549 bytes, does not bite yet".
- The registry is the input to every prioritisation decision. A tool that returns a
  prefix of it, with no error, makes those decisions wrong and gives no sign.
- The human-readable listing has the identical shape and is **35101 bytes today** —
  under the limit, so it works, and it will break the same way on the same threshold.

## Scope
- In scope: every exit path in `.aai/scripts/follow-ups.mjs` that prints before
  exiting (there are ten `process.exit` calls).
- Out of scope: other scripts. If the same pattern exists elsewhere it is filed, not
  fixed here — a repo-wide sweep is its own scope.
- Out of scope: changing the output format, the schema, or any command's behaviour.

## Affected Area
- `.aai/scripts/follow-ups.mjs:509-510` — the `--json` branch, measured broken.
- `.aai/scripts/follow-ups.mjs:512-517` — the human branch, same shape, latent.
- The eight remaining `process.exit` sites, which print short strings today.

## Desired Behavior (To-Be)
- D1 — output is complete regardless of whether stdout is a file, a pipe, a terminal
  or a closed descriptor, at any payload size.
- D2 — the process still exits with the code it means. Fixing the flush must not
  turn a usage error into a success, and must not hang waiting on a reader.
- D3 — a reader that closes the pipe early (`| head -1`) does not turn into a crash
  or a non-zero exit that a caller would misread as a tool failure.

## Acceptance Criteria
- AC-001: `list --json` piped into a parser yields valid JSON at a payload above
  64 KB, demonstrated against the live ledger and against a synthetic ledger at
  least twice that size.
- AC-002: the byte count through a pipe equals the byte count to a file, for both
  `--json` and the human listing, at a payload above 64 KB.
- AC-003: every subcommand still exits with the code it did before — `0` on success,
  `1` on a failed post-append re-read, `2` on a usage error. Demonstrated per code.
- AC-004: `list --json | head -1` neither hangs nor reports a tool failure.
- AC-005: no output format changes. The bytes written to a file are byte-identical
  before and after the change, for `list`, `list --json`, `add` and `close`.

## Verification
- measure both directions at both sizes; a claim about a pipe is only evidence if it
  was produced through a pipe
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns
- prove each new assertion **bites** by mutation, with an unmutated green control;
  an assertion verified only by reading is not accepted on this repository

## Constraints / Risks
- The obvious fix — drop `process.exit` and let the event loop drain — changes when
  the process ends. Check nothing depends on the immediate exit, and that no handle
  keeps it alive.
- Node stdlib only, zero dependencies.
- `docs/ai/decisions.jsonl` is append-only and is this tool's data. Do not rewrite it;
  build large fixtures in a scratch ledger passed with `--ledger`.
- No secret is referenced by this scope.

## Notes
- Registry item this scope closes: `fu-followups-json-truncated-on-pipe` (P2), whose
  escalation from latent to live is recorded as a `process_finding` on 2026-08-20.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: the repo-wide `grep` alias, zsh word-splitting and
  `find -newermt` are all measurement traps here. Measure under `bash` with
  `/usr/bin/grep` by absolute path, and never send a measurement's stderr to
  `/dev/null` — a suppressed error once read as a zero and cost a working agent.
