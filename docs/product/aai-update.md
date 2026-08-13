---
id: aai-update
type: product
capability: aai-update
status: current
delivered_by:
  - CHANGE-0137
  - update-doctor-field-report
  - CHANGE-0138
  - spec-doctor-honesty-batch
  - doctor-honesty-batch
spec: docs/specs/SPEC-0124-spec-update-doctor-field-report.md
updated: 2026-08-13
---

# `/aai-update` refreshes the vendored AAI layer and ends with a doctor field report

## What it does

`/aai-update` is the one-command refresh of a project's vendored AAI layer:
it materializes the canonical AAI repository's `main` (or a chosen ref),
runs the layer sync into the current project, and prints concise post-sync
evidence — changed files, the updated AAI pin, and any conflict advisory.
It never commits; the user reviews the diff and commits manually.

As of CHANGE-0137, every successful update also closes the fleet-evidence
loop: after the sync, the update runs the freshly vendored environment
doctor and persists a provenance-stamped **doctor field report** on the
machine where the update ran. CI can never cover every platform — the
downstream fleet is the real test bed, and the update is the one moment
every fleet machine reliably passes through. The report is an ordinary
markdown file the user can attach when filing an issue, so "what exactly
does this machine look like" is a file, not a debugging session.

## How to use it

```bash
/aai-update                      # sync from the canonical repo's main
/aai-update --dry-run            # print the plan, change nothing
/aai-update --repo OWNER/NAME    # alternate upstream (slug, URL, or local path)
/aai-update --ref BRANCH         # non-default ref
```

Under the hood the skill runs `.aai/scripts/aai-update.sh` (bash/macOS/Linux)
or `.aai/scripts/aai-update.ps1` (Windows). After a successful, non-dry-run
sync the update tail prints a `## Doctor field report` section with exactly
one line — either the verdict and where the report landed:

```
DOCTOR CLEAN - full report: docs/ai/reports/doctor-20260813T101500Z-myhost.md
```

or a named skip (`DOCTOR-REPORT SKIP <reason> - update unaffected`). When
filing an issue about a broken or odd environment, attach the newest
`docs/ai/reports/doctor-*.md` file.

The dial lives in `docs/ai/update-config.yaml`:

```yaml
post_update_doctor: on   # default; "off" prints a named disabled-by-config line
```

An absent file or key means on. An unknown value warns on stderr and behaves
as on. A dry-run never runs the doctor.

As of CHANGE-0138 the config handling is honest about degraded shapes:

- **BOM tolerance.** A UTF-8 byte-order mark (BOM) at the very start of
  `docs/ai/update-config.yaml` no longer hides a first-line key from the
  column-0 parsers — both `update-doctor-report.mjs` and `update-check.mjs`
  strip exactly one BOM at index 0 (a BOM byte sequence on any later line is
  ordinary content, not a BOM). The two parsers carry a byte-identical strip
  and are pinned together — neither side can be fixed or reverted alone.
- **Exists-but-unreadable config.** A config path that exists but cannot be
  read (any read error other than not-found, e.g. a directory at the config
  path) emits exactly one named stderr `WARNING` carrying the path and the
  error code, and still behaves as on — never a silent default. An absent
  file stays silent (that is the documented default, not a degradation).
- **Prune failures.** When retention pruning cannot delete one or more
  shaped reports, the run emits at most ONE stderr line —
  `update-doctor-report: WARNING retention prune failed for <path> (<code>)`
  with ` and <n> more` appended when several failed — never one line per
  file and never silence. The budget is one prune line plus one config line
  per run, so a fully degraded run adds at most two stderr lines while
  stdout keeps its exactly-one-line contract and the exit code stays 0.

## Data model

- `docs/ai/reports/doctor-<yyyymmdd>T<HHMMSS>Z-<machine>.md` — the field
  report: a provenance header (UTC timestamp; AAI version and commit from
  `.aai/system/AAI_PIN.md`, falling back to `docs/ai/AAI_VERSION.md`, else
  the literal `UNKNOWN`; platform string with the node version; sanitized
  hostname tag; the doctor's exit code, verdict and issue count) followed by
  the doctor's full `--json` document verbatim in one fenced block, so
  reports from multiple machines are directly comparable. The directory is
  runtime-ignored by the vendored `.gitignore` — a report never dirties the
  project tree. Retention: only the newest 10 files of exactly that name
  shape are kept; sync-conflict advisories and validation reports in the
  same directory are never touched.
- `docs/ai/update-config.yaml` gains the `post_update_doctor: on|off` key
  (column-0 scan, same discipline as the existing `mode:`/`throttle_hours:`
  keys, which are unaffected).

## Interfaces and contracts

- `.aai/scripts/aai-update.sh` / `.aai/scripts/aai-update.ps1` — exit codes
  unchanged by this feature (0 success, 2 refused inside the canonical repo,
  3 upstream fetch failed, 4 malformed source). The doctor postamble can
  never change the update's exit code: any failure in it degrades to exactly
  one named `DOCTOR-REPORT SKIP <reason>` line.
- `node .aai/scripts/update-doctor-report.mjs [--root <path>] [--config
  <path>] [--doctor <path>] [--timeout-ms <n>] [--max-reports <n>]` — the
  one shared engine both entrypoints call. Exit 0 for every runtime outcome,
  2 only for a CLI usage error. Prints exactly one stdout line per run. The
  doctor spawn is bounded (default 240 s); a doctor exit 1 (FAIL findings)
  still writes the report — that is exactly the machine the fleet wants a
  report from.
- Zero network, zero LLM calls, no dependency beyond node (which the doctor
  itself already requires).

## Limits and non-goals

- Rollout lag is inherent: the update executes the pre-update copy of the
  entrypoint, so the first update that vendors this feature does not yet run
  it — the first report appears on that machine's second update.
- The report captures the machine at update time; a machine that breaks
  later is invisible until its next update.
- Nothing is uploaded anywhere: the report is a local file, and attaching it
  to an issue is a deliberate human act.
- Two updates within the same second on one machine overwrite one report
  file (whole-file write, no interleaving).

## Links

- Request: docs/issues/CHANGE-0137-update-doctor-field-report.md
- Spec: docs/specs/SPEC-0124-spec-update-doctor-field-report.md
- Validation evidence: docs/ai/reports/ (gitignored runtime directory —
  evidence lands per ride, not committed)
- Doctor engine: docs/product/aai-doctor.md
