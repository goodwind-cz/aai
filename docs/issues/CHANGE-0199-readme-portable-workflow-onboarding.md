---
id: readme-portable-workflow-onboarding
type: change
number: 199
status: done
frozen_sha256: 379c7142f2293ad99b1fdc47a13eaa7cdff3bbd8692a7c59c1b3c116703d9e96
ceremony_level: 0
links:
  pr:
    - TBD
  commits:
    - 5cc010c7
---

# README onboarding for a portable, evidence-backed workflow

Ceremony justification: Documentation and a static illustration only; no runtime behavior, API, or protected AAI workflow file changes.

## Technical note

SPEC-FROZEN: true

The README and linked User Guide are the specification surface for this documentation-only change. Keep the introductory path accurate for installation, `/aai-intake`, `/aai-ship`, updates, and harness support. Antigravity CLI is the default Google recommendation for free and AI Pro/Ultra plans; Gemini CLI remains available only for its supported access paths. Do not change executable AAI behavior.

## Summary

Refresh the root README and add a hero image that explain AAI's development loop, portability, and repository-owned knowledge, then guide a new user through installation and a first run.

## Motivation / Business Value

The current README leads with workflow detail and mixes shell installation commands with agent-chat commands. A newcomer should quickly understand the value of AAI and know exactly how to try it.

## Scope

- In scope: Root README structure and copy; one repository-hosted hero image derived from the existing AAI visual; review and targeted correction of onboarding content in docs linked from the README.
- Out of scope: Changes to the AAI workflow, installers, model routing, or published website.

## Affected Area

- Repository landing page and onboarding instructions.

## Desired Behavior (To-Be)

- The opening explains the production development loop and independent validation, supported portability across agent clients and models, durable project artifacts, and documentation status in the repository.
- Installation and first use are short, distinct, and accurate for shell versus agent chat. The primary path shows `/aai-intake` followed by `/aai-ship` with the returned draft path.
- The image depicts an autonomous development loop with planning, building, testing, validation, review, and documentation, plus durable output to the repository, without overstating universal compatibility.
- The quick start shows how to preview and apply `/aai-update`, while advanced install and sync instructions remain available without dominating the landing page.
- Harness guidance mentions Cursor and Antigravity accurately, distinguishing shared skill discovery from dedicated model routing; Gemini CLI is framed as a supported but plan-limited path, not the default for Google users.

## Acceptance Criteria

- AC-001: The README opens with a clear value proposition, the new hero image, and a concise path to installation, `/aai-intake`, and `/aai-ship` from the saved draft.
- AC-002: The README accurately describes supported harnesses, model selection, validation limits, document status and audit, product docs, and the difference between durable repository artifacts and local runtime files.
- AC-003: All new links and image paths resolve in the repository; the image clearly shows the autonomous loop and its repository output, and its text is legible and spelled correctly.
- AC-004: The README explains the `/aai-update` preview/apply path and points to detailed update guidance, with advanced installation and manual sync instructions collapsed below the quick start.
- AC-005: Linked onboarding docs are checked for broken links and drift; the User Guide's first workflow matches the intake-to-ship path and explains harness-specific limits.

## Verification

- Review the README's first screen and commands against the current installer and skill documentation.
- Check Markdown links and image path; inspect the saved image.
- Run `git diff --check` and the relevant docs audit for this intake.

| Test | Command | Covers |
|---|---|---|
| TEST-001 | `node .aai/scripts/docs-audit.mjs` | AC-001, AC-002, AC-004, AC-005; tracked docs remain healthy |
| TEST-002 | `node .aai/scripts/sync-harness-skills.mjs --check` | AC-002; claimed shared skill mirrors exist |
| TEST-003 | `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-antigravity-project-skills.sh` | AC-002; Antigravity project skill path works |
| TEST-004 | `git diff --check` | AC-001 through AC-005; Markdown patch hygiene |

The image legibility and the linked document claims also require human-readable inspection; the commands above do not claim to automate those judgments.

## Constraints / Risks

- Preserve the detailed installation and synchronization reference or provide clear links to it.
- Do not claim that every harness, model, report, or runtime file is portable or committed.

## Notes

- Requested in Czech; repository documentation remains in English.
- Implementation mode: documentation and image only; no behavior or test changes.
