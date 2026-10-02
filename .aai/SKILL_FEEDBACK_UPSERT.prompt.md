# SKILL: /aai-feedback-upsert — review-mode issue upsert (RFC-0012 Phase 2c)

This is step 2 of the sanctioned channel for reporting AAI-layer problems/bugs/friction UPSTREAM to the canonical repo (the `upsert.destination` in `.aai/feedback.yaml`).

Thin wrapper over `.aai/scripts/aai-feedback-upsert.mjs`. It turns the triage
report's `review_candidate` clusters into transmit-redacted, deduplicated,
budget-checked GitHub issue drafts. THE DEFAULT RUN WRITES NOTHING TO GITHUB.

## Safety model (RFC-0012 D7/D8, SPEC-0176 D4/D5, spec-friction-issues-arrive-without-a-description D1/D3)
- A plain run is **PREPARE-ONLY**: it writes drafts to
  `docs/ai/friction/pending-issues/<fp>.md` and prints the exact confirmed-write
  command. No mutating GitHub call is made.
- A filed issue carries ONE certified human-written description as its leading
  blockquote (one line, 1..500 chars, the same fail-closed redactor as every
  free-text field): the record's own `--promote`d summary, or a publish-time
  `--description <file>` (lines joined by one space, argv-only; the draft is
  never read). A record with **no description** is NOT filed: prepare marks it
  `blocked_no_description` and offers no publish line; publish refuses with
  exit 2 BEFORE any `gh` call. A description the redactor refuses is refused
  naming its reason class. Never ask an agent to write that line — it is the
  human's sentence, read by the human who types `--confirm`.
- An issue is filed ONLY via the explicit, human-confirmed step, which re-runs
  the transmit redaction + budget check immediately before the write. Under the
  SAME `--confirm` the engine posts the certified description as one
  `gh issue comment` on the filed issue when the returned URL certifies (no
  second approval); a failed comment never unfiles the issue — the ledger entry
  still writes and the process exits non-zero naming the comment's failure.
- `auto` mode is refused (locked). `local` (default) prepares nothing.

## Run
```
# prepare (no write) — active only when feedback.yaml triage.mode is `review`:
node .aai/scripts/aai-feedback-upsert.mjs
# inspect docs/ai/friction/pending-issues/<fp>.md, then, only if you approve
# (add the one-line description when the draft says blocked_no_description):
node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm [--description <file>]
```

## Guarantees
- Transmit-pass redaction: the description is re-run through
  `.aai/scripts/lib/aai-redact.mjs` and REFUSED if it cannot be certified — the
  second half of RFC-0013's double redaction.
- Dedup: an existing issue carrying `<!-- aai-friction:<fingerprint> -->` is not
  duplicated. Budget: at most `upsert.budget.max_new_issues_per_7d` new issues per
  rolling 7 days (local ledger `docs/ai/friction/upsert-ledger.jsonl`).
- Destination is the pinned `upsert.destination` repo. The engine holds no token —
  it shells to an authenticated `gh`; missing/unauthenticated `gh` degrades to
  prepare-nothing.

## After a confirmed publish
The filed issue carries the description; the mechanism, reproduction steps and
anything naming a path or quoting output stay a hand-written comment (the
redactor cannot certify those). The draft in `pending-issues/<fp>.md` carries a
static, commented-out `## Analysis (reporter follow-up)` skeleton for that
shape. Only when the issue URL could not be certified does the engine print,
and never run, `gh issue comment <n> --repo <destination> --body-file <file>`
for you to post the description by hand.

## When to run
Explicitly, after reviewing the triage report — and only after the operator has
decided to file. Never a daemon; never without `--confirm` for a write.
