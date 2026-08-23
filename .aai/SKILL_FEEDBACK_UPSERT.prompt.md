# SKILL: /aai-feedback-upsert — review-mode issue upsert (RFC-0012 Phase 2c)

This is step 2 of the sanctioned channel for reporting AAI-layer problems/bugs/friction UPSTREAM to the canonical repo (the `upsert.destination` in `.aai/feedback.yaml`).

Thin wrapper over `.aai/scripts/aai-feedback-upsert.mjs`. It turns the triage
report's `review_candidate` clusters into transmit-redacted, deduplicated,
budget-checked GitHub issue drafts. THE DEFAULT RUN WRITES NOTHING TO GITHUB.

## Safety model (RFC-0012 D7/D8)
- A plain run is **PREPARE-ONLY**: it writes drafts to
  `docs/ai/friction/pending-issues/<fp>.md` and prints the exact confirmed-write
  command. No mutating GitHub call is made.
- An issue is filed ONLY via an explicit, human-confirmed step:
  `node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm`
  which re-runs the transmit redaction + budget check immediately before the write.
- `auto` mode is refused (locked). `local` (default) prepares nothing.

## Run
```
# prepare (no write) — active only when feedback.yaml triage.mode is `review`:
node .aai/scripts/aai-feedback-upsert.mjs
# inspect docs/ai/friction/pending-issues/<fp>.md, then, only if you approve:
node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm
```

## Guarantees
- Transmit-pass redaction: any free-text (the optional summary) is re-run through
  `.aai/scripts/lib/aai-redact.mjs` and DROPPED if it cannot be certified — the
  second half of RFC-0013's double redaction.
- Dedup: an existing issue carrying `<!-- aai-friction:<fingerprint> -->` is not
  duplicated. Budget: at most `upsert.budget.max_new_issues_per_7d` new issues per
  rolling 7 days (local ledger `docs/ai/friction/upsert-ledger.jsonl`).
- Destination is the pinned `upsert.destination` repo. The engine holds no token —
  it shells to an authenticated `gh`; missing/unauthenticated `gh` degrades to
  prepare-nothing.

## When to run
Explicitly, after reviewing the triage report — and only after the operator has
decided to file. Never a daemon; never without `--confirm` for a write.
