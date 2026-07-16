# Debug Skill - Systematic-Debugging Gate (Root-Cause-First)

## Goal
Stop symptom-patching. No fix is written until the failure is understood at
its cause. This is the single source of truth for the debugging protocol and
rationalization table referenced by `.aai/REMEDIATION.prompt.md`.

Source: RES-0001 P2 recommendation 7b — Superpowers systematic-debugging
pattern (4-phase root-cause-first protocol). Motivating example from this
repo: the fieldSpan finding (ISSUE-0007/SPEC-0022), where the surface bug
(list append indent) nearly masked the deeper span bug — only the
validator's probe forced the root cause out.

## Iron Law
NO FIXES WITHOUT ROOT CAUSE. A fix written before the failure is reproduced
and traced to its origin is a guess wearing a fix's clothes — it moves the
defect, it does not remove it.

## Protocol
Every defect fix passes through this exact chain, in this order, with no
phase skipped:

READ → REPRODUCE → ISOLATE → FIX-AT-CAUSE

1. READ the full error output — every line, top to bottom. Not just the
   tail: the first error in a log is usually the cause, the last is its
   echo. Collect stack traces, exit codes, and the exact failing assertion
   before forming any theory.
2. REPRODUCE the failure minimally, BEFORE any edit. Strip the trigger down
   to the smallest command/input that still fails, and run it to see the
   failure with your own eyes. A bug you cannot reproduce is a bug you
   cannot prove fixed.
3. ISOLATE the cause, working from evidence, not intuition:
   - Recent changes first: `git log`/`git diff` over the touched area — most
     regressions live in the last few edits.
   - Instrument component boundaries: log/assert what actually crosses each
     seam, instead of assuming the interface holds.
   - Trace the data flow BACKWARD from the failing symptom to where the bad
     value or state was born. The birthplace is the cause; the crash site
     is only the address of the symptom.
4. FIX-AT-CAUSE — never at the symptom. The fix goes where the defect was
   born, and it must make the phase-2 reproduction pass. If the repro still
   fails, or the fix only pads the crash site, you have not fixed anything.

## Rationalization table
Stop and correct if you catch yourself thinking any of these:

| Rationalization | Counter |
|---|---|
| "Just add a null check where it crashes" | The crash site is the symptom's address, not the cause's. Trace where the null was born; a guard at the crash hides the defect and ships it downstream. |
| "The test is flaky — rerun until green" | Flaky means not understood. Reproduce the failure mode (loop the test, pin the seed/order) before touching anything; rerun-green without a cause is a latent regression. |
| "Works on my run" | Then your run differs from the failing one — in input, state, or ordering. Diff the two until the difference has a name; that difference is your isolation lead. |
| "The error is obvious from the last line" | Tails lie. Read the full output top to bottom (protocol phase 1); the first error is usually the cause, the last is its echo. |
| "It's probably the framework/library" | It is almost always your code. Instrument your own boundary first; blame a dependency only after a minimal repro that removes your code. |
| "My surface fix makes the report green — ship it" | Green-at-symptom nearly buried this repo's fieldSpan span bug behind an append-indent fix (ISSUE-0007/SPEC-0022). Ask what upstream state made the symptom possible, and fix there. |

## Completion side
Root cause found and fixed is still only a claim. Hand the completion side
to `.aai/SKILL_VERIFY.prompt.md`: the fix passes the
IDENTIFY → RUN → READ → VERIFY → CLAIM gate (fresh evidence from the current
tree — starting with the phase-2 reproduction now passing) before any
"fixed" is reported.

## Applicability
This gate binds the Remediation fix step (`.aai/REMEDIATION.prompt.md` —
wired before "Apply fixes in order"). Implementation/TDD RED discipline
already owns new-behavior work; when an unexpected failure appears anywhere,
the same four phases apply before the first corrective edit.
