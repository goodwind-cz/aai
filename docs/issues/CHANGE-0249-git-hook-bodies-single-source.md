---
id: git-hook-bodies-single-source
type: change
number: 249
status: done
capability: git-hook-bodies-single-source
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Move the git hook bodies both installers embed to shared templates

## Summary
- Ride 4 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5).
- `.aai/scripts/install-pre-commit-hook.sh` and
  `.aai/scripts/install-pre-commit-hook.ps1` each embed their own copy of the
  three git hook bodies they write: pre-commit (the AAI:GUARD-CHECKS block
  plus the AAI:INDEX-AUTOGEN body), reference-transaction (AAI:REF-GUARD) and
  pre-push (AAI:CLOSE-GATE). Move the bodies to shared template files under
  `.aai/templates/` that both installers read, so a hook written by either
  installer is byte-identical.
- Fix the four `cmd | grep -q` sites under `set -o pipefail` in the pre-commit
  body the `.ps1` writes (the `.sh` copy already uses here-strings since
  PR #381); the same body also carries a fifth early-closing reader,
  `sed ... | head -1`.

## Motivation / Business Value
- The two copies have drifted. Measured on main `244ef0bf` (bash,
  `/usr/bin/grep`): the `.ps1` pre-commit body still pipes into an
  early-closing reader at four `grep -q` sites and one `head -1` site, so on a
  large staged set the producer can take SIGPIPE and, under `pipefail`, the
  hook skips the index regeneration or the close gate even though the reader
  found its match. The `.sh` copy was fixed in PR #381 and the `.ps1` copy
  was not.
- Other drift between the copies: the "Installed by" lines, the
  reference-transaction refusal text (POSIX-only fix line in the `.sh`,
  PowerShell-only in the `.ps1`), an em dash versus a hyphen in the
  AAI:INDEX-AUTOGEN header line, one extra comment block in the `.ps1`, and
  the bytes on disk: the `.ps1` writes with `Set-Content -NoNewline`, which
  drops the final newline and, under Windows PowerShell 5.1, encodes the
  non-ASCII characters of the body in the ANSI code page.
- Duplicated embedded hook-body lines (bash, `/usr/bin/grep -cvE
  '^[[:space:]]*(#|$)'` for code lines): the `.sh` embeds 312 lines (217
  code), the `.ps1` 308 lines (216 code).

## Scope
- In scope:
  - New template files under `.aai/templates/` holding each hook body once:
    the AAI:GUARD-CHECKS block, the AAI:INDEX-AUTOGEN pre-commit body, the
    AAI:REF-GUARD reference-transaction body and the AAI:CLOSE-GATE pre-push
    body. ASCII-only, LF line endings, one wording that fits both installers.
  - Both installers read the templates and write their bytes unchanged (the
    `.ps1` writes bytes, not `Set-Content`), compose the fresh pre-commit hook
    the same way, and refuse with exit 1 and the missing path when a
    template is absent. `--print` keeps emitting each body, now from the
    template.
  - The early-closing readers fixed once in the shared pre-commit body
    (here-strings, as the `.sh` copy already does).
  - Upgrade paths keep working: the guard-block insert and refresh compare
    against the template block, and a plain re-run over an AAI-managed hook
    stays a no-op.
  - Tests: a bash suite proving both installers write byte-identical hooks
    from the templates and that the written pre-commit survives an
    early-closing reader under `pipefail`; Pester for the `.ps1` under
    Windows PowerShell 5.1 and pwsh 7; a scratch `aai-sync` install proving
    the templates are vendored (`.aai/system/PROFILES.yaml` core).
  - Existing source-shape pins in the suites that read the installers
    updated to the templates.
  - Before/after line measurement with the plan's method.
  - CHANGELOG `## [unreleased] — <title>` per-entry heading.
- Out of scope:
  - Porting either installer to Node (ride 11, behind the ride 8 parity
    harness).
  - `pre-commit-checks.sh` / `.ps1` (L3, ride 5) and `claude-hook-gate.sh`
    (ride 7).
  - Any change to what the hooks decide (dials, markers, ranges, exit codes).

## Affected Area
- `.aai/scripts/install-pre-commit-hook.sh`,
  `.aai/scripts/install-pre-commit-hook.ps1`
- `.aai/templates/` (new hook template files), `.aai/system/PROFILES.yaml`,
  `.gitattributes`
- `tests/skills/` (new suite, Pester file, wiring files, existing pins)
- `.github/workflows/ps1-quality.yml`
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- `bash .aai/scripts/install-pre-commit-hook.sh` and
  `pwsh .aai/scripts/install-pre-commit-hook.ps1` (and Windows PowerShell
  5.1) write the same three hook files, byte for byte, into the effective
  hooks directory; the bytes are the template bytes.
- The written pre-commit hook regenerates `docs/INDEX.md` and runs the close
  gate and the body lint on a staged set large enough to outrun an
  early-closing reader, under `set -o pipefail`.

## Acceptance Criteria
- AC-001: Each of the three hook bodies (and the guard block) exists once, in
  a template file under `.aai/templates/`; neither installer embeds a hook
  body any more.
- AC-002: Both installers write byte-identical pre-commit, reference-
  transaction and pre-push hooks from the templates, proven in bash and
  under Windows PowerShell 5.1 and pwsh 7 (Pester); every intentionally
  platform-specific byte, if any, is listed in the spec.
- AC-003: The written pre-commit body has no pipe into an early-closing
  reader, and a test under `set -o pipefail` with a large staged set proves
  the index is regenerated.
- AC-004: `--print`, the guard-block upgrade and refresh, and the idempotent
  plain re-run keep their current behaviour; a missing template makes the
  installer refuse with exit 1 naming the path.
- AC-005: A scratch `aai-sync` install vendors the templates and runs both
  installers there; wiring is complete and the before and after line counts
  are measured and recorded.

## Verification
- The new suite and the touched suites pass (rc 0), run with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`.
- The Windows CI job passes on the pull request under both engines.

## Constraints / Risks
- Consumer-visible: every downstream project runs these installers on
  `/aai-update`. A hook already installed keeps its old bytes until a
  `--force` run, because a plain run leaves an AAI-managed hook alone; the
  CHANGELOG says so. The owner merges.
- Changing the guard-block interior would make every existing install
  refresh it on the next plain run; the block's bytes stay unchanged.
- Secrets preflight: no local secret is referenced by this scope.
- Windows parity is proven only by the hosted Windows job.

## Notes
- Source: roadmap item `git-hook-bodies-single-source`; plan ride 4 (owner
  sign-off: yes, given on the plan 2026-11-05).
- Pattern precedent: CHANGE-0248 (cloudflare-share port, ride 3).
- Assumption (autopilot default): neither installer is an L3 protected
  surface (`protected_paths_l3` in `docs/ai/docs-audit.yaml` and the
  WORKFLOW.md defaults name neither); they sit in the merge policy's
  `consumer-facing` architecture glob, so no lane merge applies.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).
