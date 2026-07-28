---
id: learned-append-gate
type: product
capability: learned-append-gate
status: current
delivered_by:
  - CHANGE-0069
spec: docs/specs/SPEC-0095-spec-learned-append-gate.md
updated: 2026-07-27
---

# Learned-append gate: structurally enforced append-only self-learning

## What it does

`docs/knowledge/LEARNED.md` is the project's running list of corrections and
learnings, loaded into every session to avoid repeating mistakes. Until now,
anything writing to it — human or automated — was a free-form file edit, so
an automated "self-improvement" step could in principle rewrite or delete an
existing rule while adding a new one. This change adds a small,
dependency-free gate that a write MUST pass: the resulting file has to be
byte-exactly the current file plus new content appended at the end — any
rewrite, reordering, mid-file insertion, or deletion is refused outright,
with nothing written. The end-of-session wrap-up flow now routes every
confirmed rule through a short review pass and then this gate, instead of
editing the file directly.

## How to use it

Typical use (append a reviewed rule, house date+source stamping applied
automatically):

```
node .aai/scripts/learned-append.mjs --source "how this was learned" --text "the rule text"
```

Target under a specific section heading (only safe when that heading is
already the last section in the file — otherwise the append is rejected, by
design):

```
node .aai/scripts/learned-append.mjs --source "..." --text "..." --section "Workflow"
```

Preview without writing:

```
node .aai/scripts/learned-append.mjs --source "..." --text "..." --dry-run
```

Generic verifier for an already-assembled candidate document (used for
defense-in-depth, not the normal path):

```
node .aai/scripts/learned-append.mjs --full --file <candidate-path>
```

Default target is `docs/knowledge/LEARNED.md`; override with `--target <path>`.
This tool governs only its own write path — a human editing the file by hand
is entirely unaffected.

## Data model

No new persistent record type. The gate's only output is the target Markdown
file itself, grown by exactly the appended bytes on success. Nothing is
written on rejection or under `--dry-run`.

## Interfaces and contracts

- CLI: `.aai/scripts/learned-append.mjs` — flags `--source`, `--text`,
  `--file`, `--section`, `--target`, `--full`, `--dry-run`, `--help`.
  Exit 0 on success/help, 1 when the candidate is not a pure append (nothing
  written), 2 on a usage error (nothing written).
- Prompt wiring: `.aai/SKILL_WRAP_UP.prompt.md` step 3 ("PROPOSE NEW LEARNED
  RULES") routes a user-confirmed rule through a compact critic pass and then
  this exact CLI invocation. Step 6 carries a one-line cross-reference back
  to that flow for a future triage-surfaced rule proposal.
  `.aai/system/FRICTION_PROTOCOL.md` carries a one-line pointer to the gate.

## Limits and non-goals

- This is a guardrail on the automated write path, not a security boundary —
  a human (or any process editing the file outside this script) is
  unaffected.
- Appending under a named section only works when that section is currently
  the last one in the file, or is brand new; targeting an earlier, non-last
  section is refused (a mid-file change can never be a pure append).
- No auto-generation of rules from friction clusters — this change stays
  proposal-only, out of scope per the originating request.

## Links

- Request: docs/issues/CHANGE-0069-learned-append-gate.md
- Spec: docs/specs/SPEC-0095-spec-learned-append-gate.md
- Validation evidence: docs/ai/tdd/green-20260727T105431Z-learned-append.log
