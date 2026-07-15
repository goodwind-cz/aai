# Shared intake policy blocks (CHANGE-0011)

Applies to every `.aai/INTAKE_*.prompt.md` intake assistant. Each intake prompt
references this file with a single SHARED POLICY line; apply all four blocks
below exactly as written.

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
