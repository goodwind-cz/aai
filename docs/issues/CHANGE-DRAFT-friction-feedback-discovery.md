---
id: friction-feedback-discovery
type: change
status: draft
links:
  rfc: RFC-0012
  spec: null
  pr: []
  commits: []
---

# RFC-0012 — friction feedback discovery + gh auth preflight + user docs

## Summary
- Makes the friction feedback loop VISIBLE and USABLE for a human operator. Today
  capture is silent (shadow) and the triage/upsert engines are agent-invocable,
  but nothing tells a user that observations are accumulating, that drafts are
  waiting for their `--confirm`, or that they must `gh auth login` before any
  upstream write. This slice adds an offline status/discovery surface, a `gh auth`
  preflight, an end-of-session nudge, and the missing USER_GUIDE documentation.

## Type
- change (feature — operability/UX + docs for the RFC-0012 feedback loop)

## Motivation / Business Value
- The whole loop is invisible to users: a friction report never reaches upstream
  because the operator has no idea there is anything to review/file. This closes
  the discovery gap so the built machinery is actually reachable.

## Scope
- In scope:
  - `.aai/scripts/aai-feedback-status.mjs` (new, offline for counts): reports
    (a) N observations in the spool, (b) M prepared drafts in
    `docs/ai/friction/pending-issues/`, (c) whether `gh` is present and
    authenticated (`gh auth status`, read-only), and (d) the exact next command to
    run. Human summary to stdout + `--json` for wiring. No mutation, no network
    beyond the read-only `gh auth status` (degrades cleanly if gh absent).
  - `.aai/scripts/aai-feedback-upsert.mjs`: a `gh auth status` PREFLIGHT on the
    prepare and publish paths — if gh is missing/unauthenticated, print a clear
    up-front `run: gh auth login` message (instead of only failing reactively at
    create time). No change to the no-write-without-confirm / redaction invariants.
  - `.aai/SKILL_WRAP_UP.prompt.md`: a one-line step that runs the status script and
    surfaces a nudge at session end ("N observations captured · M drafts pending
    your --confirm · gh: <ready|run gh auth login>"). Skipped silently when both
    counts are 0.
  - `docs/USER_GUIDE.md`: a "Friction feedback loop" section — what it is, that
    capture is silent/offline, the `gh auth login` prerequisite, how to review
    (`/aai-feedback-triage`, then inspect `pending-issues/`), and how to file
    (`--publish <fp> --confirm`). Documents the human-in-the-loop safety model.
  - Companion: classify the new `.aai/**` file in PROFILES.yaml; the SKILL_WRAP_UP
    prompt growth trues up the prompt-diet ledger.
  - Tests: `tests/skills/test-aai-feedback-status.sh` (counts, gh-absent/auth
    states via a mock gh, offline, JSON shape); the upsert auth preflight.
- Out of scope:
  - The auto-gate (Slice D), fix-PRs (Slice E). No change to triage/upsert logic
    beyond the auth preflight. `USER_GUIDE.md` is user docs, not prompt corpus.

## Desired Behavior (To-Be)
- Running the status script (or `/aai-wrap-up`) tells the operator, in plain terms,
  how many friction observations are captured, how many drafts await their
  `--confirm`, whether GitHub auth is ready, and the exact next command.
- Attempting to publish without `gh auth` gives an immediate, clear
  `run: gh auth login` message rather than a late create failure.
- USER_GUIDE documents the full workflow incl. the auth prerequisite.

## Acceptance Criteria
- AC-001: `aai-feedback-status.mjs` reports the spool observation count and the
  pending-draft count correctly (fixtures), and emits valid `--json`.
- AC-002: it reports gh state — `ready` when a mock `gh auth status` succeeds,
  and a `run: gh auth login` hint when gh is absent or `gh auth status` fails —
  without ever failing the caller (degrades cleanly).
- AC-003: the status script performs no mutation and no network beyond the
  read-only `gh auth status` (static + a run with a mock gh recording no mutating call).
- AC-004: the upsert engine's prepare + publish paths run a `gh auth` preflight
  and emit a clear `gh auth login` message when unauthenticated; the
  no-write-without-confirm invariant is unchanged (a plain run still writes nothing).
- AC-005: SKILL_WRAP_UP surfaces the nudge (grep-assertable wiring) and is silent
  when both counts are 0.
- AC-006: USER_GUIDE has a "Friction feedback loop" section covering the workflow +
  the gh auth login prerequisite (grep-assertable).
- AC-007: companion — new `.aai/**` file classified in PROFILES.yaml; prompt-diet
  trued up for the SKILL_WRAP_UP growth; layer-profiles + prompt-diet green.

## Verification
- `bash tests/skills/test-aai-feedback-status.sh` (new; RED first).
- `bash tests/skills/test-aai-feedback-upsert.sh` (auth preflight; still green).
- `node .aai/scripts/aai-feedback-status.mjs --help`.
- `bash tests/skills/test-aai-layer-profiles.sh` + `test-aai-prompt-diet.sh` green.
- `node .aai/scripts/docs-audit.mjs` CLEAN.

## Constraints / Risks
- The status script's ONLY external call is the read-only `gh auth status`; it must
  never mutate or leak. The counts are pure filesystem reads of the untracked spool.
- No protected_paths_l3 surface (keep L2).

## Notes
- Discovery via /aai-wrap-up matches RFC-0012 section 2 ("triage can run … from
  /aai-wrap-up … or at another safe session boundary"). This wires that surface.
- The gh auth model is unchanged: the engine holds no token; it borrows the
  operator's `gh` session. This slice only makes the prerequisite visible.
