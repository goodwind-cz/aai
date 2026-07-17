---
id: intake-secrets-preflight
type: change
number: 34
status: done
links:
  pr:
    - 97
  commits:
    - cea19d7
---

# Change — Intake Preflight Check for Referenced Local Secrets (exists/empty/missing, never the value)

## Summary
When an intake scope references a local secret (an environment variable or a
config key holding a credential), intake currently captures no signal about
whether that secret actually exists and is populated in the local
environment before implementation begins. This change adds an intake
preflight step: for each secret reference named in the scope, check whether
it exists and is non-empty WITHOUT ever reading or printing its value, and
record the check result (exists / empty / missing) in the intake document.

## Motivation / Business Value
- Direct motivation from the EEX downstream case (operator feedback cited
  in this batch's Priority-1 change): a client sFTP->API rewrite whose
  change was "move credentials from ENV to config" — the kind of scope where
  discovering LATE that a referenced credential is missing, empty, or
  differently-named than assumed derails implementation and validation
  after ceremony has already started, rather than being caught at intake
  when the cost of finding out is near zero.
- Today's intake templates (`.aai/templates/CHANGE_TEMPLATE.md`,
  `.aai/templates/ISSUE_TEMPLATE.md`) and prompts
  (`.aai/INTAKE_CHANGE.prompt.md`, `.aai/INTAKE_ISSUE.prompt.md`,
  `.aai/INTAKE_COMMON.md`) have no step that touches secret/credential
  references at all — a scope naming `DB_PASSWORD` or a config key like
  `sftp.credentials.api_key` proceeds through intake with zero signal about
  whether that value is actually available in the environment the
  implementation will run in.
- A cheap, safe (never-print) existence/non-empty check at intake time
  converts a class of "discovered late, mid-implementation" surprises into a
  recorded, up-front fact — consistent with this project's existing
  degrade-and-report discipline (Constitution art. 4) applied to secrets
  specifically.

## Scope
- In scope:
  - A preflight helper (e.g. `.aai/scripts/secrets-preflight.mjs` or a
    shell equivalent) that, given a secret reference (env var name or a
    config-key path/file), reports exactly one of `exists` (present and
    non-empty), `empty` (present but empty string), or `missing` (not set /
    key absent) — and NEVER reads the value into any log, STATE field, or
    console output beyond that three-way classification.
  - An intake prompt step (added to `.aai/INTAKE_CHANGE.prompt.md` and/or
    `.aai/INTAKE_COMMON.md`, applied by both CHANGE and ISSUE intake where
    relevant) that asks the author to name any local secret(s) the scope
    references, runs the preflight helper, and records the result in the
    saved intake document.
  - Template updates (`.aai/templates/CHANGE_TEMPLATE.md`, and
    `.aai/templates/ISSUE_TEMPLATE.md` if applicable) adding a place to
    record secret-preflight results (e.g. under Constraints/Risks or a new
    small subsection) — additive only, no existing section removed.
- Out of scope:
  - Any secret MANAGEMENT feature (rotation, storage, injection) — this is
    a read-only existence check, not a secrets manager.
  - Validating secret VALUES (correctness, format, expiry) — only
    exists/empty/missing, never content inspection.
  - Remote/cloud secret stores (this preflight is scoped to LOCAL
    environment variables and local config files per the change's own
    framing; a remote-secret-store variant is a candidate follow-up, not
    required here).

## Affected Area
- Intake prompts: `.aai/INTAKE_CHANGE.prompt.md`, `.aai/INTAKE_ISSUE.prompt.md`
  (if issues can also reference secrets), `.aai/INTAKE_COMMON.md` (shared
  policy block, if the step is common to both).
- New preflight helper script under `.aai/scripts/`.
- `.aai/templates/CHANGE_TEMPLATE.md` (and `ISSUE_TEMPLATE.md` if in scope)
  for the recorded-result field.

## Desired Behavior (To-Be)
- During CHANGE (and, where applicable, ISSUE) intake, the assistant asks
  whether the scope references any local secret (env var or config key). If
  yes, for each named reference it runs the preflight helper and records,
  per reference, one of `exists` / `empty` / `missing` in the saved intake
  document — never the value itself, never a partial/masked value, never a
  hash of the value unless explicitly designed to be irreversible and even
  then out of scope for a first pass.
- If no secret is referenced, the step is a no-op (skippable in one
  question, consistent with the existing intake token-efficiency rule:
  "ask only for missing high-impact information").
- The check result is informational at intake time — it does not block
  intake from being saved (a `missing` result is a recorded risk/finding,
  not a hard gate), preserving the existing intake flow's non-blocking
  posture while still surfacing the gap before implementation starts.

## Acceptance Criteria
- AC-001: A preflight helper exists that accepts a secret reference (env var
  name, or a config file path + key) and returns exactly one of `exists`,
  `empty`, or `missing`, with no code path that logs, prints, or returns the
  underlying value.
- AC-002: CHANGE intake (`.aai/INTAKE_CHANGE.prompt.md` /
  `.aai/INTAKE_COMMON.md`) gains a step that asks for referenced secrets,
  runs the helper, and records the exists/empty/missing result(s) in the
  saved document — verified by a sample intake run whose saved markdown
  contains the recorded result.
- AC-003: The preflight step is skippable with zero extra questions when the
  author states no secret is referenced (token-efficiency parity with the
  existing intake rules).
- AC-004: A fixture proves the never-echo guarantee: given an env var set to
  a known non-empty value, the helper's stdout/return value contains
  `exists` and does NOT contain the actual value string anywhere in its
  output.
- AC-005: `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
  stays exit 0 after the template/prompt additions.

## Verification
- Unit/fixture test for the preflight helper covering all three outcomes
  (`exists`/`empty`/`missing`) plus the never-echo guarantee (AC-004).
- `grep` of a sample saved intake document confirming the recorded
  exists/empty/missing field is present and no raw secret value appears
  anywhere in the file.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- Manual intake run (via `.aai/INTAKE_CHANGE.prompt.md`) exercising the new
  step end-to-end for a scope that names at least one secret reference.

## Constraints / Risks
- Hard constraint: the value must never be read into any persisted
  artifact (STATE.yaml, the intake doc, logs, decisions.jsonl) — only the
  three-way classification. Any accidental echo of a real credential into a
  committed doc would be a security incident, not just a bug; the helper
  and the prompt wording must both be designed so this cannot happen even
  under an LLM's normal tool-use behavior (e.g. never `cat`/print the env
  var directly — check existence/length via a narrow helper call only).
- Config-key checks (as opposed to env vars) need a defined, safe parsing
  contract per config format (YAML/JSON/.env) — scope the first
  implementation to whatever format(s) this repo's own TECHNOLOGY.md and
  common downstream project shapes already use; extend format support
  incrementally rather than trying to support every possible config syntax
  up front.
- Must not become a new hard gate that blocks intake — the EEX case's
  complaint was ABOUT excess ceremony/cost, so this feature must stay a
  cheap, optional, informational preflight, not a new blocking checkpoint.

## Notes
- Motivation citation: EEX downstream credentials-from-ENV-to-config change
  (operator feedback relayed in this same 2026-07-17 intake batch's
  Priority-1 change, `loop-ceremony-aware-dispatch`).
- Filed as part of the same 2026-07-17 intake batch; independent of the
  other five docs in the batch (no shared file-surface risk with the
  orchestration-dispatch.mjs-touching changes).
