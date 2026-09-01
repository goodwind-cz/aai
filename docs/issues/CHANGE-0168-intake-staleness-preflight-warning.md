---
id: intake-staleness-preflight-warning
number: 168
type: change
status: done
links:
  pr:
    - 327
  commits:
    - 019e96a
---

# Warn about a stale repo/submodules before intake starts

## Summary
- Every `.aai/INTAKE_*.prompt.md` currently starts asking questions
  immediately, with no check on whether the checkout it is running in is
  actually current. On a project that installs/syncs the AAI layer (or any
  project using its own intake), a developer can draft an intake artifact
  against stale code and stale docs — including a submodule pinned to an old
  commit — without any signal that the tree is behind.
- Add a lightweight, read-only staleness PRE-FLIGHT to the shared intake
  entry point: before the first question, check whether the current branch
  is behind its upstream and whether any submodule is behind its remote, and
  print a named warning if so. Never block, never mutate the working tree.

## Motivation / Business Value
- An intake artifact (bug report, change request, etc.) is only as good as
  the state of the code/docs it was written against. Drafting against a
  stale tree risks: re-reporting an issue already fixed upstream, describing
  "current behavior" that has since changed, or missing a relevant recent
  doc/decision. This is a correctness/trust problem for the intake corpus,
  not a cosmetic one.
- Requested by the operator: "Jak zajistit aby před intake si to
  aktualizovalo celé repository kde to je instalováno a nevznikaly tak
  intake nad starym kódem a docs, včetně submodules."

## Scope
- In scope: a read-only staleness check (current branch vs its upstream;
  every initialized submodule's checked-out commit vs its remote) run once
  at the start of the shared intake entry point (`.aai/SKILL_INTAKE.prompt.md`
  and/or the `.aai/INTAKE_COMMON.md` shared blocks all eight `INTAKE_*`
  prompts already reference), printed as a single named warning line (or a
  short block, one line per stale ref) before the first intake question.
- Out of scope: automatically running `git pull`, `git submodule update`, or
  any other command that mutates the working tree, index, or local branch
  refs. Out of scope: blocking or refusing intake on a stale tree (decided:
  soft warning, not a hard gate — see Decisions below). Out of scope:
  changing `/aai-update`'s own sync behavior (that is a separate, existing
  mechanism); this is only about intake's own preflight visibility.

## Affected Area
- `.aai/SKILL_INTAKE.prompt.md` (the shared intake router all eight
  `INTAKE_*.prompt.md` are dispatched through) and/or
  `.aai/INTAKE_COMMON.md` (the shared policy blocks already referenced by
  every per-type intake prompt) — whichever is the correct single place to
  add a sixth shared block so all eight intake types get it without each
  restating the check. Planning decides the exact placement; this intake
  intentionally does not prescribe implementation.

## Desired Behavior (To-Be)
- Before the shared intake router asks its first question (type detection
  or the per-type prompt's own opening question), it performs ONE
  network operation: `git fetch` (refs-only — this updates remote-tracking
  refs, never the working tree, index, or local branch pointer) against the
  current repo, plus `git submodule foreach` equivalent for each initialized
  submodule's own remote.
- It then compares, read-only:
  - current branch HEAD vs. its configured upstream (`@{u}`) — behind-by-N
    commits, if any;
  - each submodule's currently checked-out commit vs. the latest commit on
    its remote's default branch (or its recorded/tracked branch, if
    configured) — behind-by-N commits, if any.
- If nothing is behind: no output, proceed straight to the first question
  (silent success — never adds noise to the common case).
- If something is behind: print ONE named warning block, e.g.:
  ```
  ⚠ repo is 3 commit(s) behind origin/main — consider `git pull` before
    continuing, so this intake is not drafted against stale code/docs.
  ⚠ submodule <path> is 2 commit(s) behind its remote — consider
    `git submodule update --remote <path>`.
  ```
  then proceeds to the first question regardless — the operator decides
  whether to stop and update first or continue anyway (soft warning, not a
  gate; see Decisions).
- Degrades SILENTLY to no warning (never an error, never a block) when:
  network/fetch fails or times out (offline environment); the current
  branch has no configured upstream (e.g. a detached HEAD or a local-only
  branch); there are no submodules; git itself is unavailable. The
  degradation is silent specifically because a failed connectivity check is
  not itself informative to the intake author — it must never be confused
  with the "everything is current" silent-success case in a way that
  matters, since in both cases the correct action (proceed) is identical.

## Acceptance Criteria
- AC-001: on a project checkout whose current branch is behind its upstream
  by at least one commit, starting any `.aai/INTAKE_*.prompt.md` prints a
  named staleness warning naming the branch and the commit count BEFORE the
  first intake question, and still proceeds to ask it.
- AC-002: on a project checkout that is fully up to date with its upstream
  and carries no submodules (or all submodules current), starting intake
  produces NO staleness output at all — the common case stays silent.
- AC-003: on a project with at least one initialized submodule whose checked
  -out commit is behind its remote, starting intake prints a named warning
  identifying that submodule's path and how far behind it is, independent
  of whether the superproject branch itself is current.
- AC-004: the preflight check never mutates the working tree, the index, or
  any local branch ref — provable by `git status --porcelain` and `git
  rev-parse HEAD` being byte-identical before and after the check runs (a
  `git fetch` only touches `refs/remotes/*`).
- AC-005: with network access disabled/unreachable, the preflight degrades
  to silent no-op — intake proceeds to its first question with no error,
  no hang beyond a bounded timeout, and no warning (since staleness truly
  cannot be determined).
- AC-006: a repo with no configured upstream for the current branch (e.g.
  a fresh local branch, or a detached HEAD) degrades to silent no-op for the
  branch check specifically, without suppressing a genuine submodule
  warning if one applies.

## Verification
- Command(s) and expected results:
  - Fixture A (branch behind): clone a scratch repo, make one commit on the
    remote copy only (simulate upstream advancing), then run the intake
    entry point locally — expect the named warning naming the branch and
    commit count, question still asked.
  - Fixture B (fully current, no submodules): run intake on an up-to-date
    checkout — expect zero staleness output.
  - Fixture C (submodule behind): a scratch repo with one submodule pinned
    one commit behind its remote — expect the submodule-specific warning,
    independent of the superproject branch's own state.
  - Fixture D (no network): run with the remote unreachable (e.g. an
    invalid remote URL or `GIT_TERMINAL_PROMPT=0` against a blocked host)
    — expect silent no-op, no error, no hang past a bounded timeout, first
    question still asked.
  - Fixture E (before/after tree-mutation proof): `git status --porcelain`
    and `git rev-parse HEAD` captured immediately before and immediately
    after the preflight check runs, on a repo with real staleness to
    detect — must be byte-identical.

## Constraints / Risks
- Directly modifies the shared intake entry point
  (`.aai/SKILL_INTAKE.prompt.md` and/or `.aai/INTAKE_COMMON.md`), which is
  `.aai/*.prompt.md` corpus subject to this repo's prompt-diet byte-budget
  governance (diet-ledger entry + a TEST-012 `want_growth` pin bump are
  needed alongside any prompt text growth — do not skip this bookkeeping).
  If the check is implemented as a script (e.g.
  `.aai/scripts/intake-staleness-check.mjs`) invoked from the prompt rather
  than described inline in prose, the prompt-level byte cost shrinks to one
  invocation line, and the script itself must be classified in
  `.aai/system/PROFILES.yaml` (100% coverage requirement).
- A bounded timeout on the `git fetch` is required — an intake author must
  never be stuck waiting on a hung network call before they can even start
  typing. Planning/Implementation must pick and justify a concrete timeout.
- `git fetch` still requires credentials/auth to succeed against a private
  remote in some environments; a failed auth attempt must degrade the same
  as "network unreachable" (silent no-op), never surface a credential
  prompt or error that looks like it's blocking intake.
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Decisions made during intake (recorded here per the operator's own
  answers, since this predates a frozen spec):
  - Soft warning, not a hard gate: intake never refuses to start or forces
    an update; it only makes staleness VISIBLE and lets the operator decide.
  - Staleness detection uses a lightweight `git fetch` (refs-only, never a
    `git pull`/merge) rather than a purely-offline comparison against
    whatever remote-tracking refs happen to already be cached locally — the
    operator explicitly chose "real current truth over local cache" while
    keeping the no-working-tree-mutation guarantee.
- Applies to the shared intake entry point so all eight intake types
  (prd/change/issue/hotfix/techdebt/research/rfc/release) get the same
  preflight without each `INTAKE_*.prompt.md` needing its own copy.
