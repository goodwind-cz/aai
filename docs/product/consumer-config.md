---
id: consumer-config
type: product
capability: consumer-config
status: current
delivered_by:
  - consumer-config-routing-override
spec: docs/specs/SPEC-0290-spec-consumer-config-routing-override.md
updated: 2026-11-14
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

The same file can price the models you route to. The `pricing:` section gives
metrics a rate for a model id the shipped `PRICING.yaml` does not list, so a
runner or a cross-vendor override is costed instead of reported as unpriced:

```yaml
routing_override@codex:
  Code Review: acme-model-1
routing_override@gemini:
  Planning: acme-model-2
pricing:
  acme-model-1:
    input_usd_per_m: 2.00
    output_usd_per_m: 8.00
    source_url: https://acme.example/pricing
    last_verified_utc: "2026-11-14T06:00:00Z"
    provider: anthropic
```

`routing_override@codex:` and `routing_override@gemini:` work exactly like the
claude section above; each applies only on its own harness.

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
- Section `pricing:`: one entry per model id, with `input_usd_per_m`,
  `output_usd_per_m`, `source_url` and `last_verified_utc` (all required) and
  optional `provider` and `unverified_utc`. It follows the same all-or-nothing
  rule as the routing rows.
- Precedence: the shipped table wins. A model id the shipped `PRICING.yaml`
  already prices is costed from it and the project entry is ignored (CAT-22
  names it shadowed); the project entry is only a fallback for ids the shipped
  table lacks.
- Freshness: a project price older than the `PRICING.yaml` cadence (or
  `AAI_TABLES_HORIZON_DAYS`) makes CAT-22 print a freshness WARN naming the id,
  its date and its age; it never fails the run.
- Cross-vendor rule: an override whose model belongs to another vendor than the
  running harness is still applied, with one dispatch NOTE and a cross-vendor
  mention in CAT-22. Same-vendor overrides, cursor and models of unknown vendor
  print no such NOTE; add `provider:` to a project price to make the check
  apply to it.
- Effort is not overridable: `suggested_effort` and `harness_effort` are the
  shipped values with or without the file.
- Absence means no change: dispatch output is byte-identical without the file.

## Interfaces and contracts

- Dispatch: `orchestration-dispatch.mjs` adds an additive key
  `model_override: { file, harness, role, model }` only when a row applied, and
  sets `suggested_model` to that model; the validator-independence backstop
  still runs after the override. Notes go to stderr as
  `orchestration-dispatch: NOTE — docs/ai/project-config.yaml ...`.
- Routine: in a project whose `.aai/` is not tracked, the owner-instantiated
  `ROUTING_REFRESH` routine runs in downstream mode: it reads CAT-22 from
  `aai-doctor.mjs --json`, prices only override ids the shipped table lacks, edits
  only the `pricing:` section and opens a pull request; see
  `docs/product/universal-routines.md`.
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
