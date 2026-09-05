---
id: hand-authored-friction-is-second-class
number: 172
type: change
status: draft
links:
  pr: []
  commits: []
---

# A hand-authored friction observation cannot be scored, cannot carry prose, and can never reach upstream

## Summary
- The friction channel was repaired in ISSUE-0080 / SPEC-0166 and filed its first
  two issues (#338, #339). The first live run showed the remaining defect is in
  **what flows through it**, not in the pipe.
- Two owner decisions were taken on 2026-09-05 and are recorded in
  `docs/ai/decisions.jsonl` as `hitl_decision` records with `owner_signoff: true`.
  This scope implements them.

## Motivation — measured, not estimated

Against the live spool (`docs/ai/friction/observations.jsonl`, 65 records) with

```
score = max(impact + confidence + 2*reproducible) + min(recurrence-1, RECURRENCE_CAP)
IMPACT/CONFIDENCE = low 1, medium 2, high 3 | REPRODUCIBLE_BONUS = 2
RECURRENCE_CAP = 5 | review_candidate threshold = 4
```

- **56 of 65** records carry neither `impact` nor `confidence`, so their signal is
  0 and they are scored purely by recurrence.
- A single **high/high** report scores 6. **Six** **low/low** repeats also score 6.
  They tie.
- Recurrence alone can contribute **5** against a threshold of **4**, so repetition
  manufactures a candidate carrying no quality signal at all. Four of the eight
  current candidates are low-confidence `aai-run-tests` records that reached
  candidacy this way.
- The **three observations the owner dictated by hand** (backlog-drain
  standardisation, live agent dashboard, untested guard text) are schema-v1 with
  no scoring fields and recurrence 1. They score **0** — unreachable, not low.

And on the output side: with `capture.summary_enabled: false` a filed issue carries
`failure_class`, `skill`, `phase`, `impact`, `confidence`, `aai_pin`, `os_family`,
`node_major`, `recurrence`, `score`, and where present `reproducible`, `workaround`
and `evidence_ref` — but **no free-text description of what went wrong**. That list
is exact; an earlier follow-up gave a shorter one and was corrected in #341.

## Type
- change

## Impact
- Every AAI installation using the sanctioned feedback channel: the highest-signal
  observations are the ones that cannot reach it, and the ones that do reach it
  cannot say what happened.
- Severity/priority: P2. Not a broken channel any more — a miscalibrated one.

## Acceptance Criteria

- **AC-001** `RECURRENCE_CAP` drops to **3**. Recurrence can then only PROMOTE a
  record that already carries signal; it can never on its own reach the threshold
  of 4. Proved both ways: a cluster of six zero-signal records is NOT a candidate,
  and a low/low record (signal 2) with recurrence 3+ still is.
- **AC-002** A hand-authored observation can be recorded carrying `impact` and
  `confidence`, so a deliberate human report is scoreable at all. The three
  existing v1 records are NOT rewritten — that spool is append-only in spirit and
  they predate the field; the path is for new ones.
- **AC-003** An observation a human deliberately PROMOTES may carry prose the human
  wrote. `capture.summary_enabled` stays **false**: the automatic capture path
  remains prose-free, and nothing in this scope admits prose into it.
- **AC-004** The promoted prose still passes BOTH redaction passes (capture-time
  and transmit-time) before it can reach GitHub. A promoted observation whose prose
  cannot be certified is dropped exactly as an automatic one is — a human author is
  not an exemption from redaction.
- **AC-005** The two `hitl_decision` records are cited by id in the frozen spec, and
  `spec-amend.mjs list --strict` stays green.

## Verification
- `bash tests/skills/test-aai-feedback-triage.sh` and
  `bash tests/skills/test-aai-feedback-upsert.sh` green, with new cases pinning
  both arms of AC-001 and the redaction arm of AC-004.
- Re-run `aai-feedback-triage.mjs` over the live spool and report the candidate
  list before and after: the four low-confidence `aai-run-tests` clusters must
  drop out, and the two high-confidence ones must remain.

## Constraints / Risks
- **HAZ**: AC-003/AC-004 touch the one surface that can put free text into a PUBLIC
  repository. The redaction path is the same one whose test went vacuous in
  ISSUE-0080 validation round 4 — any new case here needs a positive control that
  the write actually happened, not only that nothing leaked.
- Lowering the cap makes some currently-listed candidates disappear. That is the
  intent, but the before/after list must be reported, never silently changed.
- `RECURRENCE_CAP` is a tuning constant; pin it in a test so a future edit is a
  visible decision rather than a drift.

## Notes
- Owner decisions: `hitl_decision` `friction-triage-scoring-rewards-recurrence` and
  `friction-issue-body-is-prose-free`, both `owner_signoff: true`, 2026-09-05.
- Supersedes the open follow-ups `fu-friction-scoring-rewards-recurrence` (P2) and
  `fu-friction-issue-body-is-prose-free` (P3), and their correction
  `fu-friction-prose-free-list-inexact` (P3).
- While correcting Amendment 6 of SPEC-0166 is out of scope here, note that its
  summary line says the four rounds found "3, 2, 10 and 4" findings and omits
  round 2's five. Found by the LEARNED critic pass, 2026-09-05.
