---
id: simple-and-friendly-to-use
type: product
capability: simple-and-friendly-to-use
status: current
delivered_by:
  - simple-and-friendly-to-use
spec: docs/specs/SPEC-0172-spec-simple-and-friendly-to-use.md
updated: 2026-09-06
---

# A ride that finishes, measurably

## What it does

Three things now hold on every ride, and each of them is measured rather than
promised.

**A ride leaves nothing behind.** When work is pushed, a gate checks four
things: no uncommitted files, no document still open for work that shipped, no
outstanding audit finding, and no follow-up the ride filed about its own
ceremony. If any of them is true the push stops and names what is left. The
check runs on the real path, before the push, not only in tests.

**The whole journey is scripted and timed.** One command drives a fresh
throwaway project from intake through freeze, commit, merge, close and audit,
with input closed so nothing can wait on a person. It reports how many steps
ran, how many failed, and how many times something asked a question. The
current answer is 40 steps, 0 failures, 0 questions.

**Documentation changes stop paying for a full test run.** Two file families
were not listed in the map that decides which tests a change needs, so any
change touching them escalated to the ~25-minute full sweep. They are now
mapped to the suites that actually read them, and replaying two real past pull
requests through the map selects real suites and never escalates.

## What you will notice

- A pull request whose diff is documentation or ledgers finishes in minutes
  instead of tens of minutes.
- A push that would have left a draft document behind now stops and says so.
- Each release run records a comparable measurement of the journey, so "it
  behaves worse than it used to" becomes a difference between two numbers
  instead of an impression.

## Limits

- The gate trusts the reference it is given. Pointed at the wrong one it
  reports a clean result, so it protects an honest ride rather than defending
  against a dishonest argument.
- The measured journey runs against a throwaway project, not against yours. It
  proves the path works; it does not prove your repository is healthy.
- The reduced pull-request time is measured against past runs. The first real
  documentation-only pull request after this ships is what confirms it.
- A requirement-only pull request still escalates to the full sweep; that file
  family remains unmapped and is tracked separately.

## Data model

- New record file `docs/ai/tests/golden-flow.jsonl`, append-only, one line per
  measured journey. Each line carries when the journey ran, on which version
  and platform, how many steps it took, how many failed, how many questions it
  had to ask, and the four counts of the nothing-left-behind check, plus the
  recent token median and its ceiling.
- No existing file changes shape. The record file is additive, and every
  earlier line stays byte-identical when a new one is appended.

## Interfaces and contracts

- Two new commands: one drives and measures the journey, one checks that
  nothing was left behind. Both are local, read no network, and write only the
  record file named above.
- The nothing-left-behind check answers with a plain report or, with a flag, a
  single machine-readable object; it exits 0 when clean, 1 when something was
  left behind, 2 when it was called wrong.
- The journey command needs a scratch directory of its own. It rebuilds that
  directory on every run, so it refuses one it did not create rather than
  deleting somebody's project.
- The release step now names a missing, stale, or unreadable journey record
  instead of blocking on it.
