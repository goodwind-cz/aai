---
id: drain-pipe-grep-q-ratchet
type: issue
number: 53
status: draft
---

# P2 backlog cluster: assertions-must-not-die-on-their-own-payload (5 items)

## Summary
- Consolidated registry intake for 5 open P2 follow-up(s) filed against `assertions-must-not-die-on-their-own-payload`: `fu-drain-pipe-grep-q-ratchet`, `fu-ceremony-levels-nearest-miss-30kb`, `fu-ratchet-not-selected-on-rise`, `fu-fixture-arg-exceeds-linux-argstrlen`, `fu-sigpipe-code-differs-by-platform`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-drain-pipe-grep-q-ratchet`**: Drain the 390-occurrence pipe-into-grep-q ratchet in tests/skills to zero, file by file
  - Measured: The ratchet stops the count RISING but every one of the 390 recorded occurrences is still a latent CI red the day its fixture passes 64 KiB. The drop-in replacement (assert_payload_contains) now exists, so draining is mechanical; it was left out of this scope because a 390-site blanket rewrite is a large diff with real risk of changing what an assertion means.
  - Source: tests/skills/lib/pipe-grep-q-baseline.tsv (390 occurrences across 38 files, measured 2026-08-21)

- **`fu-ceremony-levels-nearest-miss-30kb`**: test-aai-ceremony-levels.sh TEST-019 pipes a 30048 B flattened spec into grep -q three times — the corpus nearest miss, 46 percent of the pipe buffer
  - Measured: Runtime census of the full framework (13091 recorded grep -q pipe payloads, 81 suites): this is the single largest real payload, and the next largest is 12604 B. It sits below the 32768 B at-risk floor Spec-AC-01 declared BEFORE the measurement, so this scope correctly did not convert it — but it is the one site whose payload grows every time docs specs validation-cost-calibration grows, and it will cross 64 KiB first. Convert it to assert_payload_contains before it reddens CI.
  - Source: runtime grep -q census 2026-08-21, tests/skills/test-aai-ceremony-levels.sh lines 1147 1149 1151, 30048 B each

- **`fu-ratchet-not-selected-on-rise`**: select-suites does not run aai-hygiene-pack when an ordinary suite file gains a pipe-grep-q occurrence, so the new ratchet never gates the PR that violates it
  - Measured: the RISE case is the ratchet's main purpose; measured: select-suites --files-from tests/skills/test-aai-doctor.sh yields SELECTED aai-doctor + 3 CORE and DROPPED 77, hygiene-pack among them. Only a brand-new suite file (unmapped -> FULL_RUN) is caught pre-merge; a rise inside a baselined file is caught at merge-to-main or the nightly, post-merge. Fix: give aai-hygiene-pack a tests/skills/*.sh glob or make it CORE
  - Source: validation round1 2026-08-21, node .aai/scripts/select-suites.mjs --files-from <one changed suite>

- **`fu-fixture-arg-exceeds-linux-argstrlen`**: an oversize test payload passed as a single argv entry fails on Linux with exit 126: MAX_ARG_STRLEN caps ONE argument at 131072 bytes even though ARG_MAX is far larger, and darwin has no such cap
  - Measured: green locally red on CI with an exit code that names nothing; the same fixture shape is used wherever a suite builds a payload larger than 128 KiB, and the pipe-buffer work makes such fixtures more common not less
  - Source: PR 272 CI run 32523365858 job 96900265051; test_100(c) got 126, fixed by reading the payload from a file

- **`fu-sigpipe-code-differs-by-platform`**: a writer killed by EPIPE exits 141 on macOS but 1 on Linux when the writer is a bash BUILTIN, because bash reports the builtin's write error instead of dying by the signal
  - Measured: any arm that pins 141 as the signature of the pipe hazard is red on Linux while the hazard reproduces perfectly; and exit 1 is indistinguishable from a needle that was simply absent, so such an arm cannot say which happened without a small-payload control running FIRST
  - Source: PR 272 CI run 32525580619; test_101 CONTROL A got 1 where darwin gives 141

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `assertions-must-not-die-on-their-own-payload`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
