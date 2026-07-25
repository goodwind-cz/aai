---
id: feedback-upsert-review
number: 49
type: change
status: done
links:
  rfc: RFC-0012
  spec: null
  pr:
    - 148
  commits:
    - a35afd5241e934716765fc5009c2f87a445ffbcf
---

# RFC-0012 Phase 2c / Slice C — review-mode GitHub upsert (approval-gated)

## Summary
- The FIRST network slice. Consumes the offline triage report's `review_candidate`
  clusters and, in `review` mode, PREPARES an exact, transmit-redacted GitHub issue
  per cluster (title templated from structured fields; body + a
  `<!-- aai-friction:v1:<fingerprint> -->` dedup marker), searches upstream for an
  existing issue by that marker, and enforces a reporting budget — but **never
  writes to GitHub without an explicit human confirmation**. `auto` stays locked
  (Slice D); `local` stays prepare-nothing/summarize-only.

## Type
- change (feature — RFC-0012 Phase 2c, first network surface; privacy/safety critical)

## Motivation / Business Value
- Slices A/B established capture + offline triage. Slice C is the bridge to the
  upstream: it turns a `review_candidate` into a ready-to-file, redaction-certified,
  deduplicated issue that a maintainer approves and files. This is what makes the
  feedback loop actually reach the framework — with a human in the loop on every
  external write, exactly as RFC-0012 D7/D8 require.

## Scope
- In scope:
  - `.aai/scripts/aai-feedback-upsert.mjs` (new) — reads the triage report,
    selects `review_candidate` clusters, and for each:
    - builds an issue TITLE templated from structured fields (RFC-0013 D2:
      `[<failure_class>] <skill_id>/<skill_phase> (<impact> impact)`); a summary is
      included ONLY if it is present in the record (already capture-redacted) AND
      passes the TRANSMIT redaction pass;
    - builds an issue BODY from the leak-free structured fields + the stable
      `<!-- aai-friction:v1:<fingerprint> -->` marker;
    - runs the TRANSMIT-pass redactor (`.aai/scripts/lib/aai-redact.mjs`, the SAME
      module as capture — RFC-0013 D3 double redaction) over every free-text field
      before the payload is finalized; a field that cannot be certified is dropped;
    - DEDUP: searches the pinned destination repo for an existing issue carrying
      the same `v1:<fingerprint>` marker (open or closed). Existing -> prepare an
      "add materially-new evidence" update (version/platform/recurrence delta only)
      or skip; absent -> prepare a NEW issue.
    - BUDGET: at most `budget.max_new_issues_per_7d` (default 3) NEW issues per
      rolling 7 days, tracked in a local ledger `docs/ai/friction/upsert-ledger.jsonl`;
      over budget -> prepared but marked deferred, never filed.
  - APPROVAL GATE: a plain engine run (even in `review` mode) is PREPARE-ONLY — it
    writes the prepared issues to `docs/ai/friction/pending-issues/<fingerprint>.md`
    and prints the exact `gh` command(s), but performs NO GitHub write. An actual
    write happens ONLY via an explicit, separate, human-confirmed step
    (`--publish <fingerprint> --confirm`), and even then re-runs the transmit
    redaction + budget check immediately before the write.
  - Degrade: missing/unauthenticated `gh`, missing config, or `mode: local` ->
    local-only (prepare nothing to send); never errors a caller.
  - Config: `.aai/feedback.yaml` gains `destination` (repo pin, default
    goodwind-cz/aai — D1), `budget.max_new_issues_per_7d`, `cooldown_days`,
    `labels`. `mode: review` enables preparation; `local` (default) does not.
  - Companion: classify new `.aai/**` files in PROFILES.yaml; wrapper prompt ->
    prompt-diet ledger true-up.
  - Tests: dedup marker search (mocked gh), transmit redaction of the payload,
    budget enforcement, approval-gate (a plain run writes NO issue / makes NO
    network call), template correctness, config pin, fail-closed/degrade.
- Out of scope (later slices):
  - `auto` mode / the D8 auto-gate (Slice D). Automatic fix-PR preparation (Slice E).
  - Any write that is not explicitly human-confirmed.

## Affected Area
- `.aai/scripts/aai-feedback-upsert.mjs` (new), `.aai/scripts/lib/aai-redact.mjs`
  (reused, transmit pass), `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` (new),
  `.aai/feedback.yaml` (destination/budget/labels), `.aai/system/PROFILES.yaml`,
  `docs/ai/friction/` (pending-issues/ + upsert-ledger.jsonl, gitignored),
  `tests/skills/`.

## Desired Behavior (To-Be)
- In `review` mode, a plain engine run prepares transmit-redacted, deduplicated,
  budget-checked issue drafts locally and prints the exact confirmed-write command
  — and writes NOTHING to GitHub. A human inspects the draft and, only if they
  approve, runs the explicit `--publish ... --confirm` step, which re-verifies
  redaction + budget and then files exactly that issue.
- `local` (default) prepares nothing to send. `auto` is refused (locked).
- No GitHub write ever occurs without an explicit human `--confirm`.

## Acceptance Criteria
- AC-001: a plain engine run (review mode) performs NO GitHub write and NO network
  mutation — it only writes local drafts + prints commands (asserted: no `gh
  issue create`/`gh api ... -X POST` executed without `--confirm`).
- AC-002: the issue TITLE/BODY are templated from structured fields; a summary is
  included only if present AND it passes the TRANSMIT redaction pass; a payload
  free-text field that fails redaction is dropped.
- AC-003: the transmit redaction reuses `.aai/scripts/lib/aai-redact.mjs` (the same
  module as capture) — a poisoned free-text field in a prepared payload is dropped
  (double redaction).
- AC-004: dedup — given an existing issue carrying `v1:<fingerprint>`, the engine
  prepares an update/skip, not a duplicate NEW issue (verified with a mocked search).
- AC-005: budget — with `max_new_issues_per_7d` already reached in the ledger,
  further NEW issues are prepared-but-deferred, never filed.
- AC-006: config — destination repo pin is read from feedback.yaml; `auto` mode is
  refused; `local`/missing config/missing gh degrade to prepare-nothing.
- AC-007: the `--publish <fp> --confirm` path re-runs transmit redaction + budget
  immediately before the write (no stale-payload write), and appends to the ledger.
- AC-008: companion — new `.aai/**` files classified; prompt-diet trued up; suites green.

## Verification
- `bash tests/skills/test-aai-feedback-upsert.sh` (new; RED first). GitHub calls are
  mocked (a stub `gh` on PATH) so the suite is offline and deterministic; a real
  network write is NEVER made by the test.
- `bash tests/skills/test-aai-layer-profiles.sh` + `test-aai-prompt-diet.sh` green.
- `node .aai/scripts/docs-audit.mjs` CLEAN.

## Constraints / Risks
- NETWORK + PRIVACY CRITICAL: this is the first slice that can leave the machine.
  Mitigations: transmit-pass redaction (double), human `--confirm` on every write,
  prepare-only default, budget + cooldown, dedup marker, destination pin,
  independent adversarial validation + bot review before merge.
- The write path uses `gh` (assumed authenticated); the engine holds no token
  itself. Missing/unauthenticated `gh` degrades to local prepare-only.
- No protected_paths_l3 surface (keep L2). RFC-0012 D7/D8 require human approval at
  implementation time — this intake IS that gate; the frozen spec is presented for
  owner approval BEFORE the network code is written.

## Notes
- Operationally, review mode should run only after the >=2-week shadow window has
  produced real observations; this slice delivers the CODE, gated so nothing is
  filed without a human. Auto-enable is Slice D (D8 acceptance metrics).
