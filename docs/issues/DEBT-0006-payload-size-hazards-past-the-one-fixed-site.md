---
id: payload-size-hazards-past-the-one-fixed-site
type: techdebt
number: 6
status: draft
links:
  pr: []
  commits: []
---

# 389 assertions still pipe their payload into grep, the ratchet does not gate the rise, and two exit codes differ by platform

## Debt Summary
- An assertion that pipes a large payload into `grep -q` dies on its own payload once that
  payload passes the 64 KiB pipe buffer. One site was converted; a ratchet now stops the
  count RISING. Five registry items describe what is left: the drain itself, the site that
  will cross first, a gap that lets the ratchet miss the rise it exists to catch, and two
  platform-dependent exit codes that make such arms unreliable on Linux.

## Root Cause
- `printf '%s' "$payload" | grep -qF ...` is the idiom the suites were written in. It is
  correct until the payload grows, and the payload grows because the corpus grows. The
  drop-in replacement exists (`tests/skills/lib/assert-payload.sh`,
  `assert_payload_contains` at `:81`), so the remaining work is mechanical volume, not
  design.

## Current Cost / Risk
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-drain-pipe-grep-q-ratchet` (P2). Measured today from
  `tests/skills/lib/pipe-grep-q-baseline.tsv`: 38 suite files, 389 recorded occurrences
  (the entry recorded 390 across 38, so one has drained since). The file's own header says
  it plainly: "Every row is a latent CI red waiting for its fixture to pass 64 KiB." The
  ratchet stops the count rising; it does not remove a single existing hazard. The drain
  was left out of the originating scope because a 389-site blanket rewrite is a large diff
  with real risk of changing what an assertion MEANS.
- `fu-ceremony-levels-nearest-miss-30kb` (P2). Measured at
  `tests/skills/test-aai-ceremony-levels.sh:1147,1149,1151`: TEST-019 pipes a flattened
  spec into `grep -qF` three times, 30048 B each — 46 percent of the pipe buffer. A runtime
  census of the full framework (13091 recorded `grep -q` pipe payloads across 81 suites)
  found this to be the single largest real payload, with the next largest at 12604 B. It
  sits below the 32768 B at-risk floor the originating spec declared BEFORE the
  measurement, so that scope correctly did not convert it — but its payload grows every
  time `docs/specs/.../validation-cost-calibration` grows, and it will cross 64 KiB first.
- `fu-ratchet-not-selected-on-rise` (P2). The RISE case is the ratchet's main purpose, and
  it is not gated pre-merge. Measured today: `/usr/bin/grep -n hygiene-pack
  .aai/scripts/select-suites.mjs` returns NOTHING, so an ordinary suite file gaining a
  pipe-into-`grep -q` occurrence does not select `aai-hygiene-pack`. Measured at filing:
  `select-suites --files-from tests/skills/test-aai-doctor.sh` yields the doctor suite plus
  3 CORE and DROPS 77, hygiene-pack among them. Only a brand-new suite file (unmapped, so
  FULL_RUN) is caught pre-merge; a rise inside a baselined file is caught at merge-to-main
  or by the nightly, post-merge.
- `fu-fixture-arg-exceeds-linux-argstrlen` (P2, PR 272 CI run 32523365858 job
  96900265051). An oversize test payload passed as a single argv entry fails on Linux with
  exit 126: `MAX_ARG_STRLEN` caps ONE argument at 131072 bytes even though `ARG_MAX` is far
  larger, and darwin has no such cap. Green locally, red on CI, with an exit code that
  names nothing. The same fixture shape is used wherever a suite builds a payload larger
  than 128 KiB — and the pipe-buffer work makes such fixtures MORE common, not less.
- `fu-sigpipe-code-differs-by-platform` (P2, PR 272 CI run 32525580619). A writer killed by
  EPIPE exits 141 on macOS but 1 on Linux when the writer is a bash BUILTIN, because bash
  reports the builtin's write error instead of dying by the signal. Any arm that pins 141
  as the signature of the pipe hazard is red on Linux while the hazard reproduces
  perfectly; and exit 1 is indistinguishable from a needle that was simply absent, so such
  an arm cannot say which happened without a small-payload control running FIRST.

## Target State
- The baseline file reaches zero, file by file, with each conversion proved to preserve the
  assertion's meaning.
- A rise inside a baselined file selects the ratchet suite pre-merge.
- No fixture passes a payload larger than 128 KiB as a single argv entry.
- No arm pins a bare 141 as the EPIPE signature without a platform-aware control.

## Scope
- In scope: draining the 389 occurrences; converting the ceremony-levels nearest miss
  ahead of the others; giving `aai-hygiene-pack` a `tests/skills/*.sh` glob or CORE status;
  the argv-length and SIGPIPE-code portability rules.
- Out of scope: the ONE site already converted, and the ratchet mechanism itself, which
  works as designed for what it claims.
- Out of scope: the general CLI `console.log`-then-`process.exit` truncation sweep, filed
  with its own cluster. That is producers truncating their own output; this is consumers
  dying on input.

## Plan / Migration
- Convert `test-aai-ceremony-levels.sh` TEST-019 first — it is the measured nearest miss.
- Make the ratchet selectable on a suite-file change, so the drain cannot regress while it
  is in progress.
- Drain file by file, largest recorded count first, each with a before/after proof that the
  arm still bites.
- Add the argv and exit-code rules to the payload helper so new arms inherit them.

## Verification
- `awk -F'\t' '{s+=$1} END {print s}'` over the non-comment rows of
  `tests/skills/lib/pipe-grep-q-baseline.tsv` trends to 0.
- `node .aai/scripts/select-suites.mjs --files-from <any tests/skills/*.sh>` includes
  `aai-hygiene-pack`.
- Each converted arm is bite-proved in a disposable copy: mutate the thing it asserts,
  observe red, restore, observe green.

## Constraints / Risks
- A 389-site rewrite can silently change what an assertion means; that risk is the reason
  the drain was deferred, and it does not go away by being scheduled.
- Making `aai-hygiene-pack` CORE adds its cost to every selection.

## Notes
- Registry ids covered: `fu-drain-pipe-grep-q-ratchet`,
  `fu-ceremony-levels-nearest-miss-30kb`, `fu-ratchet-not-selected-on-rise`,
  `fu-fixture-arg-exceeds-linux-argstrlen`, `fu-sigpipe-code-differs-by-platform`.
