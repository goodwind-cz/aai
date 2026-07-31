# Shared intake policy blocks (CHANGE-0011)

Applies to every `.aai/INTAKE_*.prompt.md` intake assistant. Each intake prompt
references this file with a single SHARED POLICY line; apply the four
universal blocks below exactly as written, plus the SECRETS PREFLIGHT block
where the dispatching prompt names it.

## LANGUAGE POLICY
- Accept user responses in any language.
- Keep follow-up questions in the user's language.
- Output the final saved markdown in English only.

## DURABLE DOC IDENTITY (SPEC-0015 / RFC-0007)
Create the artifact at docs/<type>/<TYPE>-DRAFT-<slug>.md (the literal DRAFT token
marks an unnumbered doc) with frontmatter: id: <slug> (the durable PRIMARY KEY,
never changed), number: null, status: draft. The slug is kebab-case of the topic
(lowercase, ASCII, at most 48 chars). Do NOT scan-and-mint a TYPE-000N number at
intake — the sequential display number is assigned at MERGE by
.aai/scripts/allocate-doc-number.mjs (invoked by /aai-pr), and the human-facing
TYPE-000N display id is derived from type + number by the index generator.
The zero-padding WIDTH follows the type's existing convention (inherited from
the highest-numbered doc of that type; an empty type follows the project's
dominant width across all numbered docs; greenfield defaults: PRD 3-digit,
e.g. PRD-001, all other prefixes 4-digit, e.g. RFC-0001).
NEVER predict the eventual TYPE-000N number in any text (docs, commit messages,
changelog entries, PR titles) before the allocator assigns it — use the slug id.
FALLBACK (allocator absent, older AAI layer): scan-and-mint the next free
TYPE-000N from existing docs and name the file docs/<type>/<TYPE>-000N-<slug>.md
directly; the CI/pre-commit duplicate-number guard is the backstop.

## POST-SAVE CHECK (RFC-0002)
After saving the document, verify template compliance:
  node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <saved-file>
If the check fails, fix the frontmatter per the template and re-run until it
passes. Do not report the artifact as saved while the check fails. If the
script does not exist (older AAI layer), note that and continue.

## METRICS (after saving the document)
Ask the user (in their language):
"How many minutes did you spend on this intake? (Enter a number or press Enter to skip)"
If the user provides a number N, append or update in docs/ai/STATE.yaml:
  metrics:
    work_items:
      <ref_id>:
        human_time_minutes:
          intake: N
If the user skips or ref_id is not yet known, leave intake: null.

## IMPLEMENTATION MODE CHOICE (end of intake, spec-implementation-mode-choice)
After the artifact is saved (the LAST step of intake), PRESENT the user a 4-way
implementation-mode choice WITH a recommendation, in their language:
1. Full TDD loop — RED-GREEN-REFACTOR per test (highest rigor, highest token cost).
2. Direct + targeted tests — implement first, then targeted regression tests
   (no RED-first ceremony).
3. Direct without tests — implement only, NO tests (e.g. a tuning/run script).
4. Let Planning decide — the default; record nothing. ALWAYS list this as an
   explicit numbered option (never rely on detecting silence/enter); an empty
   or ambiguous reply is treated as option 4.
RECOMMENDATION (derive from deterministic signals, state which fired):
- script-only / tuning / config-only / docs-only scope -> recommend option 3
  (direct without tests);
- small single-surface change, low risk -> recommend option 2 (direct + tests);
- behavioral, multi-surface, core/state/security/data-integrity, or a declared
  ceremony_level 2/3 -> recommend option 1 (full TDD).
If the user CHOOSES, record it before planning:
  node .aai/scripts/state.mjs set-strategy --selected <tdd|direct|untested> \
    --source intake --rationale "<the user's own words>"
  (`untested` REQUIRES a non-empty --rationale or the CLI exits 2.)
  FRESH CHECKOUT: if docs/ai/STATE.yaml does not exist yet (orchestration
  initializes it later), do NOT run set-strategy — record the choice verbatim
  in the saved intake artifact under `## Notes` as
  `Implementation mode (user choice): <tdd|direct|untested> — <rationale>`;
  Planning treats that note exactly like an intake-sourced record.
If the user does NOT choose, do nothing here — behavior is UNCHANGED: Planning
decides the strategy (back-compat). Never silently downgrade rigor: the cheap
lane must be the user's explicit choice or an explicit recommendation they accept.

## SECRETS PREFLIGHT (CHANGE-0034)
If the scope references a local secret (an env var or a config key holding a
credential), never print, cat, or echo it. For each reference, run
`node .aai/scripts/secrets-preflight.mjs --env NAME` (env var) or
`--file PATH --key dotted.key` (config file) and record one
`ref -> exists|empty|missing` line per reference under the saved doc's
Constraints/Risks section. If the author states no secret is referenced,
skip this block with zero extra questions. Results are informational only
and never block saving the intake.
