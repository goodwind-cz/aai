# Code Review — cli-output-survives-a-pipe (single dual-verdict pass)

```yaml
review:
  scope: "git diff main -- .aai/scripts/follow-ups.mjs tests/skills/test-aai-follow-ups.sh docs/INDEX.md docs/ai/EVENTS.jsonl docs/ai/decisions.jsonl + untracked docs/specs/SPEC-0139-spec-cli-output-survives-a-pipe.md, docs/issues/CHANGE-0153-cli-output-survives-a-pipe.md (base main, HEAD 778b0a7)"
  spec: docs/specs/SPEC-0139-spec-cli-output-survives-a-pipe.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-018 green in my own run — synthetic 310696 bytes / 500 items, live 91794 bytes / 89 items, both parsed through a pipe; >=174080 asserted at tests/skills/test-aai-follow-ups.sh:1210" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-019 green — --json 310696 == 310696, human 87994 == 87994 through the 400 ms slow reader; above-buffer guards at tests/skills/test-aai-follow-ups.sh:1248 and :1260" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-020 green — eleven invocations, codes 0/1/2, 20 s bound; the no-handle claim independently verified (zero setTimeout/setInterval/setImmediate/process.stdin/net/http/spawn hits in .aai/scripts/follow-ups.mjs)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-021 green; leg (c) re-proved by my own mutation — installPipeGuard commented out at .aai/scripts/follow-ups.mjs:376-377 gives exit 1 in 10/10 runs, shipped gives 2 in 10/10. See NB-1 for the arm's durability, which does not affect this call." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-022 green — format pins plus per-leg byte equality above the buffer, guard at tests/skills/test-aai-follow-ups.sh:1427 inside the `for f in human json` loop; the second instrument (whole-ride before/after capture diff) is cannot-verify, see CV-1" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 1352,
          issue: "TEST-021 leg (c) has no assertion that its precondition held — that the reader was gone BEFORE the write. Its only observable (writer exit 2) is produced identically by the not-yet-closed pipe, so the arm can go green without ever invoking installPipeGuard.",
          failure_scenario: "On a loaded runner the `| true` subshell has not exited when node issues its first process.stderr.write; the ~120 bytes land in the still-open 64 KB pipe buffer, no EPIPE occurs, node exits 2 and the arm passes. Measured: with installPipeGuard commented out AND the reader replaced by an open `cat`, the writer exits 2 in 10/10 runs — byte-identical to the shipped observable. The arm bites today (mutant + `true` = 1, 10/10) but nothing in it keeps that true." }
      - { rank: NON-BLOCKING, file: docs/ai/STATE.yaml, line: 29,
          issue: "STATE still carries the PREVIOUS ride throughout: current_focus.spec_path -> SPEC-DRAFT-spec-suites-run-in-a-disposable-worktree.md (:29); worktree.branch feat/suites-run-in-a-disposable-worktree and an inline_review_scope naming 11 paths of which this ride touched none (:391,:393); code_review.head_ref feat/suites-must-not-touch-the-shipping-repo with pr: 266 and 8 stale report_paths, under notes 'new ride; gates reset' (:409-:420).",
          failure_scenario: "SKILL_PR derives the scope file-list from STATE/spec and audits staged-vs-scope. Run as-is it stages the disposable-worktree scope and omits every path this ride changed; branch-guard.mjs additionally reads current_focus.ref_id against a tree currently sitting on main, and close-work-item.mjs reads current_focus.spec_path, which points at the wrong spec." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0139-spec-cli-output-survives-a-pipe.md, line: 175,
          issue: "The ride's changed-file set is wider than every recorded scope. docs/INDEX.md, docs/ai/EVENTS.jsonl and docs/ai/decisions.jsonl are modified in the working tree and are named neither in the spec's `Inline review scope` (:175-178) nor in STATE code_review.scope (:405, which also drops the spec file itself).",
          failure_scenario: "The staged-vs-scope audit drops the regenerated docs/INDEX.md; the PR commits two new docs without it, and tests/skills/test-aai-docs-audit.sh test_issue0001_posix_paths_noop (TEST-003) — which diffs the COMMITTED real-repo INDEX against a fresh regen stripping only ^Generated: — is red on the merge commit for a reason this PR did cause. Exact precedent in docs/ai/decisions.jsonl 2026-08-13 review_nb_disposition NB-3." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 331,
          issue: "The P1 the dispatch says was filed for the docs-audit UTC-date bomb is not in the ledger. The file has exactly ONE 2026-08-21 entry (fu-orchestrator-mutated-real-file, P2) and zero entries matching midnight / 'Today (UTC)' / time bomb. The nearest existing item, fu-docsaudit-t003-red-on-new-doc (P3, 2026-08-20), names a different mechanism — a scope that ADDS a doc — not the date.",
          failure_scenario: "This PR ships a regenerated docs/INDEX.md whose `Today (UTC): 2026-08-21` line expires at the next UTC midnight, re-reddening TEST-003 with no ledger record of why. The next reader re-diagnoses it from scratch, or discounts a standing red." }
      - { rank: INFO, file: .aai/scripts/follow-ups.mjs, line: 369,
          issue: "installPipeGuard is installed on BOTH streams and both handlers call process.exit, which discards the OTHER stream's queued bytes — the exact primitive this ride removed. D4 justifies the process.exit locally ('nothing left to flush') without noting it is only local because the two streams cannot both have pending output here.",
          failure_scenario: "None today: I walked every path and none writes stdout and then stderr — usageError and both post-append re-read failures are reached before any console.log on the same invocation. Future-conditional only; a one-line comment naming the invariant would keep a later edit from re-importing the defect." }
  cannot_verify:
    - { claim: "Spec-AC-05's second instrument, the whole-ride before/after capture diff over the two capture directories",
        closes_with: "the capture directories, or a re-run of the capture against main and HEAD" }
    - { claim: "The throw-based exit contract and the EPIPE guard on Windows",
        closes_with: "a Windows run; already filed as fu-pipe-exit-contract-windows-untested (P3)" }
    - { claim: "installPipeGuard's non-EPIPE re-throw arm",
        closes_with: "fault injection producing a non-EPIPE stream error; already filed as fu-pipeguard-nonepipe-arm-unproven (P3)" }
    - { claim: "Whether installPipeGuard's persistent 'error' listener suppresses Node's Console(ignoreErrors) transient noop listener (console's write() adds it only when listenerCount('error') === 0), and therefore whether removing the stdout half would be a behaviour-neutral refactor",
        closes_with: "a harness substituting a Writable that throws synchronously for process.stdout, run with and without the guard" }
    - { claim: "The five new arms under CI load on a GitHub runner (400 ms slow reader, 20 s bounds, the TEST-021(c) race)",
        closes_with: "one ci-full run on the PR" }
  overall: pass
```

## Scope and preflight

`docs/ai/STATE.yaml` has `worktree.user_decision: inline`, but its `inline_review_scope`
is the previous ride's 11 paths and matches none of the seven changed paths (NB-2).
Rather than stop, I established the scope from the caller's explicit refs plus the
spec's own list, which the prompt permits, and verified independently that every
changed path belongs to this ride: `git status --short` shows five modified and two
untracked files; the EVENTS append is one `doc_lifecycle` row for this spec, the
decisions append is five rows all carrying `ref_id: cli-output-survives-a-pipe`, and
docs/INDEX.md changes only in the two rows the new documents create plus the two
generated date lines. No unrelated change is in the tree. The STATE drift is reported
as NB-2 instead.

Coaching attempt, recorded per the anti-gaming contract: the dispatch pre-scoped
severity ("anything real outside Spec-AC-001..005 is a filing, not a blocker") and
framed three named questions. I reviewed the full diff first and formed the findings
before answering them; two of the four NON-BLOCKING findings (NB-2, NB-3) are outside
all three questions, and one (NB-4) contradicts a factual premise of question 3.

## Evidence

Run by me, on the working tree at HEAD 778b0a7:

- `bash tests/skills/test-aai-follow-ups.sh` — exit 0, all arms including TEST-018..022.
  TEST-018 printed synthetic 310696 bytes / 500 items and live 91794 bytes / 89 items;
  TEST-019 printed `--json 310696 and human 87994`.
- `git status --short` before and after the suite run — byte-identical; the suite left
  no write in the shipping tree.
- `node .aai/scripts/spec-lint.mjs` — 139 specs scanned, 0 findings, exit 0.
- `node .aai/scripts/check-test-registration.mjs` — exit 0.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — `Verdict: CLEAN`,
  orphans 0, missing close telemetry 0, body lint 0; the two new docs listed under
  "Pending commit".
- Purely-additive proof for the suite file:
  `diff <(git show main:tests/skills/test-aai-follow-ups.sh) tests/skills/test-aai-follow-ups.sh`
  yields **zero** `<` lines; `git diff --numstat` = `396 0`.
- Mutation, on a scratchpad copy only (`.../scratchpad/probe/fu-noguard.mjs`), both
  `installPipeGuard(...)` calls commented out:
  reader `true` -> exit **1** in 10/10; shipped -> exit **2** in 10/10;
  mutant with an OPEN reader (`cat`) -> exit **2** in 10/10.
- Closed-fd probe (a regression I hypothesised and disproved): `bogus 2>&-` exits 2 on
  both the main and the HEAD version; `list >&-` exits 0 on both with 0 bytes of stderr.
- Exported-surface probe: `loadRegistry`, `readDecisionsLedger`, `foldFollowUps`,
  `deriveLegacyId` contain no `exit(` / `usageError` reference, so the one real importer
  (`.aai/scripts/generate-factory-report.mjs:42`) cannot receive a thrown `ExitSignal`.
  The `isMain` guard is unchanged. No public-boundary break.
- Handle probe: zero `setTimeout|setInterval|setImmediate|process.stdin|node:net|node:http|spawn|exec`
  hits in `.aai/scripts/follow-ups.mjs`, confirming the D3 no-handle claim by measurement
  rather than by reading the comment that asserts it.

## The three questions

**1. Is the EPIPE guard's justification sound, and is it scoped to what it protects?**

Sound, and keep it as shipped. I re-derived the load-bearing half myself rather than
taking the 6/6: with both `installPipeGuard` calls removed the usage error into an
already-closed pipe exits 1 in 10/10 runs, and 2 in 10/10 with them. The guard is
broader than that measurement — the stdout half is not falsifiable today, because
Node's global console already swallows EPIPE — but three things make the breadth right
rather than speculative. It is one line per stream with no measured cost. D4 states the
asymmetry explicitly instead of claiming both halves are load-bearing, which is the
opposite of the usual failure. And removing the stdout half is not the behaviour-neutral
refactor it looks like: Node's `Console` only installs its own transient noop error
listener when the stream has no `error` listener, so the two mechanisms interact, and
"delete the unproven half" is a change whose blast radius is itself unmeasured. I have
listed that interaction as cannot-verify rather than asserting it.

The one thing D4 does not say is INFO above: the guard's own `process.exit` is the
primitive this ride removed, and it is safe here only because no path in this file has
output pending on both streams at once.

**2. Is the suite file in the state you think it is?**

Yes. `diff` against `main`'s version produces zero removed lines, so the file is main's
file plus 396 inserted lines in order — no pre-existing line was lost, reordered or
altered. That check matters more than `--stat` here: the mutated fixture lives inside
NEWLY ADDED code, so a surviving mutation would have shown up as an insertion and left
the deletion count at 0 regardless. Checking the added text directly: all four big
fixtures read `500` (lines 1201, 1241, 1321, 1408), the string `t022big` occurs exactly
once, and no `5`-entry artefact exists anywhere in the file. The hand-added guard is at
line 1427, inside the `for f in human json` loop and therefore applied per leg, placed
after the bound check and before the equality assertion — same shape as TEST-019's
guards at 1248 and 1260. The suite is green end-to-end and left the tree unmodified.

The one thing to carry forward from that near-miss is not in the file: TEST-021(c) is
the same class of hazard one arm over, and it is the finding I rank first (NB-1).

**3. Is shipping the regenerated docs/INDEX.md right?**

Yes, ship it — but the stated reason and the stated filing both need correcting.

Not because docs-audit needs it: `.aai/scripts/docs-audit.mjs` never reads
`docs/INDEX.md` (zero occurrences), so `--check --strict` is CLEAN with or without the
regeneration. The real reason is `tests/skills/test-aai-docs-audit.sh`
`test_issue0001_posix_paths_noop` (labelled TEST-003), which snapshots the COMMITTED
real-repo INDEX, regenerates, and diffs the two while stripping only `^Generated:`. The
generated file also carries `Today (UTC): <date>`, so the diagnosis is confirmed: that
arm is a genuine daily UTC bomb, and it is separately red for the whole life of any
scope that adds a doc — which this scope does, twice. Committing the regenerated INDEX
in the same commit as the two new docs is what makes the arm pass at all; leaving it
stale would make it red for a reason this PR caused, on top of the one it did not.

Two corrections. First, the claimed P1 does not exist (NB-4) — file it before closeout,
or the expiry ships unrecorded. Second, `docs/INDEX.md` is in no scope list anywhere
(NB-3), so the PR ceremony may well not stage the file this answer depends on.

And yes, the PR should say so: one line naming docs/INDEX.md as a regenerated artifact
required by the two new docs, and naming the follow-up id for the UTC bomb so the next
red TEST-003 is recognised rather than re-diagnosed.

## Where the remaining risk is

Not in the production diff. `.aai/scripts/follow-ups.mjs` is the smallest correct
version of this fix: one throw, one catch, one listener per stream, ten mechanical call
sites, no format change, no new handle, no public-boundary change. I attacked it four
ways (closed fds, exported surface, cross-stream truncation, stray handles) and it held
each time.

The risk is in the ceremony around it. Three of my four NON-BLOCKING findings are
bookkeeping that the PR step reads as input — a STATE block belonging to the previous
ride, a scope list that omits three of the seven changed paths, and a filing that was
reported as done and was not made. Each is individually trivial and each is positioned
exactly where a mis-staged or under-recorded PR gets produced. NB-1 is the one genuine
test-quality defect, and it is the same failure class as the near-miss this ride already
caught by hand.

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-1 TEST-021(c) unasserted precondition | promote-to-follow-up-ref, P2 — a new assertion that can pass for the wrong reason |
| NB-2 STATE carries the previous ride | remediate-in-tree before SKILL_PR (STATE write is the orchestrator's) |
| NB-3 scope lists omit INDEX + both ledgers | remediate-in-tree — add the three paths to the spec scope line and STATE code_review.scope |
| NB-4 UTC-bomb P1 not actually filed | promote-to-follow-up-ref, P1, before closeout; plus the PR-body line |
| INFO guard's process.exit is cross-stream | no action required; a comment naming the invariant is cheap |

## Next steps

1. Orchestrator records this verdict via `node .aai/scripts/state.mjs set-code-review`
   (this reviewer is read-only on STATE).
2. Remediate NB-2 and NB-3, file NB-1 and NB-4.
3. Flip the five AC rows to `done` BEFORE `close-work-item.mjs`
   (`fu-ac-flip-must-precede-close`).
4. The PR must carry the `ci-full` label at creation — `labeled` is not a trigger type
   and the selector returns `mode=selected`.
