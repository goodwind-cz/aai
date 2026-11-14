---
id: consumer-config
type: product
capability: consumer-config
status: current
delivered_by:
  - consumer-config-routing-override
spec: docs/specs/SPEC-0290-spec-consumer-config-routing-override.md
updated: 2026-11-13
---

# A project-owned config that keeps a routing exception across updates

## What it does

`/aai-update` replaces the shipped model routing table
(`.aai/system/MODEL_ROUTING.yaml`) on every update, by design. A project that
needs a different model for one role on one harness now puts that exception in
`docs/ai/project-config.yaml`, a file that belongs to the project and that no
sync or update writes, seeds or deletes. The orchestration dispatch applies the
exception on top of the shipped table for the running harness only, and
`/aai-doctor` reports it as CAT-22 Project Config. A project without the file
sees no change at all.

## How to use it

Create `docs/ai/project-config.yaml` and commit it like any project file:

```yaml
routing_override@claude:
  Code Review: claude-sonnet-5-5
```

The next dispatch under Claude suggests that model for Code Review and adds a
`model_override` key to its JSON. Run `/aai-doctor` to see the active
overrides, ignored sections and any error. Remove the file or the row to go back
to the shipped table.

## Data model

- File: `docs/ai/project-config.yaml`, outside `.aai/`, tracked by the project.
  Comments, a BOM and CRLF line ends are accepted.
- Section: `routing_override@<harness>:` where the harness is one of `claude`,
  `codex`, `gemini` or `cursor`. A section with no harness suffix or another
  suffix is ignored with one NOTE; other sections still apply.
- Rows: `  <Role>: <model-id>` (two-space indent), with the role names the
  dispatch already uses (Planning, Code Review, TDD Implementation and so on).
- Malformed is all-or-nothing: if any line of the file is malformed, no override from the
  file is applied and the doctor says why.
- The unpriced rule: a model id that `PRICING.yaml` cannot cost is still applied,
  with a NOTE that metrics cannot cost the run.
- Effort is not overridable: `suggested_effort` and `harness_effort` are the
  shipped values with or without the file.
- Absence means no change: dispatch output is byte-identical without the file.

## Interfaces and contracts

- Dispatch: `orchestration-dispatch.mjs` adds an additive key
  `model_override: { file, harness, role, model }` only when a row applied, and
  sets `suggested_model` to that model; the validator-independence backstop
  still runs after the override. Notes go to stderr as
  `orchestration-dispatch: NOTE — docs/ai/project-config.yaml ...`.
- Doctor: category `CAT-22 Project Config` (WARN-only, absent file not
  reported); see `docs/product/aai-doctor.md`.
- Ownership: no sync or update writes `docs/ai/project-config.yaml` (bash or
  PowerShell twin): none seeds or removes it; a test runs both twins of update and
  sync against a file with a BOM and CRLF and checks its bytes are unchanged.

## Limits and non-goals

- Only the model id of a role on one harness can be overridden; nothing else
  is configurable here yet.
- It does not make an unknown or retired model id work; the vendor decides.
- The file is not created by any command; the project writes it.
- All or nothing includes unknown sections. A file that carries a section a
  newer AAI added, read by an older AAI, applies no override at all until that
  project updates AAI (the dispatch NOTE and the CAT-22 WARN say so). This is
  deliberate: a mistyped section name must never be silently skipped.
- A path that exists but cannot be read (a directory, no read permission) is
  treated as malformed, not as absent: NOTE and WARN, no override applied.

## Links

- Request: docs/issues/CHANGE-0257-consumer-config-routing-override.md
- Spec: docs/specs/SPEC-0290-spec-consumer-config-routing-override.md
- Validation evidence: docs/ai/reports/VALIDATION-20261114T0123Z-consumer-config-routing-override.md (round 3 PASS; local evidence, gitignored)
