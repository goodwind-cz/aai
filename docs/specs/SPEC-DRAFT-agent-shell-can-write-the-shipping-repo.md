---
id: spec-agent-shell-can-write-the-shipping-repo
type: spec
number: null
status: implementing
ceremony_level: 3
links:
  requirement: docs/issues/ISSUE-0037-agent-shell-can-write-the-shipping-repo.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the agent's git writes become deliberate, instead of ambient

SPEC-FROZEN: true

## Headline: there is exactly one chokepoint an agent shell cannot route around, and it is git's own

The intake asks for a boundary rather than a reminder. Four candidate shapes were
measured against the four recorded instances before one was chosen. Three of them
lost on measurement, and the winner wins only two of the four. Both halves of that
sentence are the finding.

**The root cause is owned by the harness, not by AAI — MEASURED, this session.**
From inside a dispatched subagent, two consecutive Bash calls were run. Call 1
exported a marker and changed directory:

    call1: AAI_PROBE_MARKER=set_in_call_1
    call1 cwd: /Users/ales/Projects/aai
    (call 1 ended with `cd /tmp`)

    call2 cwd: /Users/ales/Projects/aai
    call2 marker: [UNSET]
    call2 AAI_ROLE: [UNSET]

Three facts follow, and they close three candidate designs at once. Environment
does not survive a Bash call, so no dispatch can set an ambient marker that agent
commands inherit. The working directory does not survive either — it is RESET to
the shipping checkout before every call, so "give the agent a scratch cwd" is not
something AAI can do; the harness re-establishes the hazard between every pair of
commands. And `AAI_ROLE` was UNSET in a dispatch whose text mandates
`export AAI_ROLE=subagent`, which is the third fact and the sharpest one.

**The R-GUARD precedent does not generalise, and its own polarity is why.**
`state.mjs` refuses a STATE mutation when `AAI_ROLE=subagent` is set. The marker
must therefore be present on the very command the guard exists to block. The
measurement above is that guard's own worst case observed live: a dispatched role
whose shell carries no marker at all, so every `state.mjs` mutator it ran would
have been ALLOWED. `.aai/SUBAGENT_PROTOCOL.md`'s ENV row already says the marker
is "a guardrail against the honest/accidental write, NOT a security boundary — an
agent that unsets the marker defeats it"; the honest extension is that an agent
that never sets it defeats it too, silently, which is the default state.

The design decision of this scope is that inversion. A guard whose marker arms the
REFUSAL is defeated by forgetting. A guard whose marker arms the ALLOWANCE turns
forgetting into a refusal. Same mechanism, opposite polarity, and only the second
one is a boundary.

**The Claude hook route is real but delivers nothing here — MEASURED.** The repo
already owns a PreToolUse Bash adapter (`.aai/scripts/claude-hook-gate.sh`,
`.aai/templates/hooks/settings-hooks.json`, SPEC-0029 / RFC-0010). It is the only
surface that sees EVERY agent Bash call. It is also deliberately uninstalled here:
`.claude/settings.json` does not exist, and `tests/skills/test-aai-hooks-overlay.sh`
TEST-013 PINS that it stays uninstalled. So the one chokepoint that could observe
every agent command is, by a ratified invariant, dormant on the repository where
all four incidents happened. Arming it is an owner decision about SPEC-0029's
opt-in contract, not a planner's, and it would still cover Claude Code only.

**`git` is the chokepoint that survives all of it — MEASURED on git 2.50.1.** A
`reference-transaction` hook fires for every ref update, from any process, at any
nesting depth, through any subshell, from any harness, and a non-zero exit at the
`prepared` state ABORTS the update:

    $ git commit -q -m x
    REFTX GATE: refused (no AAI_RIDE_WRITE=1)
    fatal: ref updates aborted by hook
    rc=128            log count: 0

    $ git commit -q --no-verify -m x2        # --no-verify does NOT bypass it
    fatal: ref updates aborted by hook
    rc=128            log count: 0

    $ AAI_RIDE_WRITE=1 git commit -q -m ok
    rc=0              log count: 1

This is what `pre-commit` is not: `--no-verify` skips `pre-commit`, and
`pre-commit` never sees `git branch`, `git reset --hard` or `git rebase` at all.

(The transcript above is verbatim from the feasibility probe, which used the
throwaway name `AAI_RIDE_WRITE`. The marker this spec DECIDES on is
`AAI_GIT_WRITE` — D1, D3 and every Spec-AC below use that name and it is the one
the implementation ships.)

## Links
- Requirement: docs/issues/ISSUE-0037-agent-shell-can-write-the-shipping-repo.md
- Decision records: docs/specs/SPEC-0155-spec-isolation-shares-the-shipping-git.md (the SUITE half of the same hazard, which this scope deliberately does not re-open), docs/specs/SPEC-0029-spec-hook-enforced-gates.md (the Claude-hook overlay and its opt-in invariant), docs/specs/SPEC-0148-spec-the-tripwire-is-permanent-not-transitional.md (the after-the-fact observer this scope does not replace)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: every arm this scope adds asserts a property that is currently FALSE
  on the shipping tree — no `reference-transaction` hook exists, no installer
  writes one, no doctor category names one — so each arm is observable red before
  the mechanism lands and green after. The central arm (Spec-AC-01) additionally
  needs a mutation proof against an unmutated control, which is exactly the tdd
  row's evidence contract. Nothing in this scope is glue.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: a git worktree SHARES the shipping repository's `.git`
  (measured and settled by SPEC-0155 D1). This scope's deliverable is a file
  written into `.git/hooks/`. Implementing it from a worktree would therefore
  install and uninstall the guard IN THE OPERATOR'S SHIPPING REPOSITORY as a side
  effect of testing it — the mechanism under test would reach outside its own
  checkout, which is the defect class this whole scope exists to remove. Inline on
  the dedicated branch `fix/agent-shell-writes-shipping-repo`, with every install
  under test targeting a `mktemp -d` fixture repository, is strictly safer.
  Spec-AC-08 exists to prove that separation rather than assert it.
- User decision: undecided
- Base ref: fix/agent-shell-writes-shipping-repo
- Worktree branch/path: n/a
- Inline review scope: `.aai/scripts/install-pre-commit-hook.sh`,
  `.aai/scripts/install-pre-commit-hook.ps1`, `.aai/scripts/aai-doctor.mjs`,
  `.aai/SUBAGENT_CONTRACT.md`, `tests/skills/test-aai-git-ref-guard.sh`,
  `docs/specs/SPEC-DRAFT-agent-shell-can-write-the-shipping-repo.md`

## The six decisions

### D1 — THE MECHANISM: an AAI-managed `reference-transaction` hook, fail-closed

`<shipping>/.git/hooks/reference-transaction`, marker `AAI:REF-GUARD`, POSIX sh.
On the `prepared` state it reads the transaction's ref lines from stdin. If ANY
line names a ref under `refs/heads/`, and `AAI_GIT_WRITE` is not exactly `1`, it
writes a named refusal to stderr and exits non-zero, which aborts the whole
transaction. Every other state (`committed`, `aborted`) and every transaction
whose lines name no `refs/heads/` ref exits 0 immediately.

The refusal text is the only teaching surface this scope needs and must therefore
be actionable on its own (constitution article 4): it names the guard, the marker,
the reason the guard exists, and the uninstall command.

### D2 — THE BLAST RADIUS, measured per operation

The scope of the refusal was not chosen by preference. Each git operation was run
against a fixture whose hook logged the exact `prepared` stdin, and the refusal set
is derived from what those lines contain:

| operation | ref lines seen at `prepared` | verdict |
|---|---|---|
| `git commit` | `<old> <new> refs/heads/main` | REFUSED |
| `git branch <n>` | `0000… <new> refs/heads/<n>` | REFUSED |
| `git branch -D <n>` | `0000… 0000… refs/heads/<n>` | REFUSED |
| `git reset --hard HEAD~1` | `ORIG_HEAD`, then `<old> <new> refs/heads/main` | REFUSED |
| `git checkout <existing branch>` | `HEAD` symref plus `AUTO_MERGE` only | ALLOWED |
| `git worktree add --detach` | `HEAD`, `ORIG_HEAD`, `AUTO_MERGE` only | ALLOWED |
| `git tag t1` | `0000… <new> refs/tags/t1` | ALLOWED (out of scope, D5) |
| `git fetch` | `refs/remotes/*` only | ALLOWED |
| `git status` / `log` / `rev-parse` / `stash list` | no transaction | ALLOWED |

Then the whole set was re-run with the scoped gate armed and the outcomes
confirmed end to end:

    checkout rc=0     worktree-add rc=0     status rc=0     fetch rc=0
    commit-no-marker    rc=128
    commit-with-marker  rc=0

Two consequences matter more than the table.

**The suite harness is untouched.** `git clone --local --no-hardlinks` from a
guarded source exited 0 with empty output, the destination did NOT inherit the
hook, and a marker-less `git commit` inside the clone exited 0 and produced commit
number 2. SPEC-0155 gives every one of the 81 suites its own clone, so every suite
keeps its full git freedom inside its own checkout while the shipping checkout is
guarded. The two mechanisms compose without either one knowing about the other.

**No AAI script is broken.** A sweep of `.aai/scripts` for ref-moving git verbs
returns zero writers: `close-work-item.mjs` runs only `symbolic-ref`, `rev-parse`,
`merge-base` and `worktree list`; `aai-update.{sh,ps1}` clone into a temp dir and
state in their own output that they never auto-commit; and
`allocate-doc-number.mjs` builds its reservation with `git commit-tree` (an object,
no local ref) and PUSHES it to `origin refs/aai/docnums/*`, which updates no local
`refs/heads/`. Spec-AC-03 pins the allocator seam rather than trusting this reading.

### D3 — THE POLARITY: what the marker arms, and why the difference is the whole design

`AAI_GIT_WRITE=1` arms the ALLOWANCE. The consequences are asymmetric on purpose:

- A probe helper that `cd`s inside a command substitution, a fixture path that
  computes empty so `cd ""` stays put, a harness that resolves the wrong root — all
  of them reach `git commit` through a shell that carries no marker, because
  nothing typed one. They refuse, loudly, at exit 128, with nothing written.
- A ride's own commit carries the marker because the agent typed it on that
  command, having decided to commit. That is the intake's own requirement in its
  own words: "Where a write is legitimate (the ride's own commits), it should be
  the deliberate, narrow exception rather than the ambient default."

The marker cannot go sticky. Environment does not survive a Bash call (measured
above), so `AAI_GIT_WRITE=1` cannot be exported once and left armed for the rest of
a session. The harness property that causes the defect is the same property that
bounds the exception to one command.

HONESTY, stated where it cannot be missed: this is not a security boundary either.
`git -c core.hooksPath=/dev/null`, an `--uninstall`, or deleting the hook file all
defeat it. Every one of those is a deliberate act that appears in the transcript.
The class this scope closes is the honest/accidental write, which is the class all
four instances belong to.

### D4 — ARMING, and the SPEC-0029 trap

SPEC-0029 shipped a correct mechanism that has never fired, because opting in was
left to a step nobody takes. An unarmed guard is not a partial boundary; it is
none. This scope therefore treats arming as deliverable, not as advice:

1. `.aai/scripts/install-pre-commit-hook.{sh,ps1}` — the EXISTING pair — gains the
   second hook. It is not renamed: it already owns `.git/hooks` installation with
   idempotence, `--force` and `--uninstall`, it already has a Windows twin, it is
   already classified in `.aai/system/PROFILES.yaml`, and it is already checked by
   `aai-doctor` CAT-12. A rename would ripple into two prompt-corpus files
   (`SKILL_INTAKE`, `SKILL_UPDATE`) and cost bytes this repo does not have. The
   header and usage text are reworded to say the script installs the AAI hook SET.
   Adding a new `.aai/**` file is avoided deliberately, which is also why the
   PLANNING companion-obligations check has nothing to fire on.
2. `aai-doctor.mjs` gains a named category reporting the guard as armed or not
   armed; the not-armed line names the exact install command. Doctor runs often;
   a template in a directory does not.
3. The ride arms it in this repository (Spec-AC-07) and its own remaining commits
   run through it. Dogfooding is the only evidence that distinguishes this from
   SPEC-0029.

Arming changes how `git commit` behaves for the OPERATOR in this checkout, not only
for agents. That cost is priced, not hidden: see `## Constitution deviations`.

### D5 — THE SCOPE FENCE

Deliberately OUT, each with its reason:

- `refs/tags/*`. Including it would add a marker to `/aai-release`, which is already
  operator-gated behind an explicit `--confirm`, and no recorded instance involved a
  tag. A narrower gate is a gate that stays armed. The measurement is in D2 so a
  later scope can widen it on evidence.
- `refs/remotes/*` and `git push`. Not a local history mutation, and the doc-number
  reservation depends on the push path.
- The Claude PreToolUse route. Blocked by the SPEC-0029 opt-in invariant that
  TEST-013 pins, Claude-only, and worth zero prevention (D6's table).
- The SUITE path. Closed by SPEC-0155; this scope must not re-open it, and D2's
  clone measurement is the proof that it does not.
- The repo tripwire's own reporting defects, filed separately.

### D6 — THE COVERAGE COUNT, honestly

Four instances, four candidate shapes. `prevent` means the write cannot happen;
`detect` means it happened and something named it; `miss` means neither.

| candidate | I1 two commits on main (P1) | I2 stray file from a relative redirect | I3 `rm -rf` in `.git/worktrees` | I4 `cd ""` then commit | prevented |
|---|---|---|---|---|---|
| (a) tripwire on every agent Bash call, via the Claude hook | detect | detect | miss (work-tree surface only) | detect | 0 of 4 |
| (b) a sanctioned scratch mechanism given by default | miss | miss | miss | miss | 0 of 4 |
| (c) a verb guard on the hook's command TEXT | miss (verbs live inside a helper script) | miss (a redirect is not a verb) | detect and prevent | miss (verbs live inside a fixture) | 1 of 4 |
| (d) prose made enforceable some other way | miss | miss | miss | miss | 0 of 4 |
| (e) THIS SCOPE — fail-closed `refs/heads` gate at git | prevent | miss | miss | prevent | 2 of 4 |

Candidate (a) is the strongest DETECTOR and prevents nothing; it also cannot arm
here. Candidate (c) is the shape the dispatch warned about and the measurement
confirms it: the dangerous verbs in I1 and I4 were inside a helper script and a
fixture, so the top-level command text a hook sees never contained them.

(e) wins 2 of 4, and the two it wins are the two that MUTATED HISTORY — the P1 whose
repair needed a hand-run `git reset --mixed 5116c36` (which the guard would also
have refused), and the P2 where a harness committed into the shipping repository.
The two it loses cost a stray file and no damage at all.

**This is a partial boundary and the spec says so in its own acceptance criteria.**
No complete structural boundary is reachable from inside AAI: preventing I2 needs a
filesystem chokepoint and preventing I3 needs one inside `.git`, and neither exists
below the OS. Naming that is the point of `## Registry items closed by this scope`.

## Acceptance Criteria Mapping

- Maps to: ISSUE-0037 "Expected Behavior" — a boundary rather than a reminder, with
  the ride's own commits kept possible as a deliberate narrow exception.
- Spec-AC-01: WHEN a ref transaction touching `refs/heads/` is prepared in a
  guarded checkout and `AAI_GIT_WRITE` is not `1` THEN git aborts it and no ref
  moves.
  - Verification: TEST-301 — in a fixture repository with the guard installed,
    `git commit`, `git branch`, `git branch -D` and `git reset --hard` each exit
    non-zero, `git rev-list --count HEAD` and `git for-each-ref refs/heads` are
    byte-identical before and after, and stderr names `AAI_GIT_WRITE`. TEST-302 is
    the mutation proof, TEST-303 the unmutated control.
- Spec-AC-02: WHEN the same transaction is prepared with `AAI_GIT_WRITE=1` THEN it
  completes exactly as in an unguarded repository.
  - Verification: TEST-304 — the same four operations exit 0 in the guarded
    fixture, and `git log --format=%T%P%s` over the result is byte-identical to the
    same sequence run in an unguarded control fixture.
- Spec-AC-03: WHEN a read or a non-`refs/heads` operation runs in a guarded
  checkout THEN it is unaffected.
  - Verification: TEST-305 — `status`, `log`, `rev-parse`, `diff`,
    `checkout <existing branch>`, `worktree add --detach`, `fetch` and `tag` each
    exit 0 with no refusal string on stderr. TEST-306 is the allocator seam: with a
    bare origin and the guard armed, `allocate-doc-number.mjs` exits 0 and its
    `refs/aai/docnums/` reservation is present on the origin.
- Spec-AC-04: WHEN a suite runs in its own disposable clone of a guarded checkout
  THEN the clone carries no guard and a marker-less commit inside it succeeds.
  - Verification: TEST-307 — after `git clone --local --no-hardlinks` from the
    guarded fixture, `<clone>/.git/hooks/reference-transaction` does not exist, a
    marker-less `git commit` in the clone exits 0, and the clone command itself
    exited 0 with empty stderr.
- Spec-AC-05: WHEN the installer runs THEN it writes the guard idempotently under
  the `AAI:REF-GUARD` marker, refuses a foreign hook without `--force`, removes only
  the AAI-managed one on `--uninstall`, and leaves the INDEX-AUTOGEN pre-commit
  behavior byte-unchanged.
  - Verification: TEST-308 — in a fixture, a first run installs, a second run is a
    byte-identical no-op, a pre-planted foreign hook makes it exit non-zero without
    modifying that file, `--force` overwrites, `--uninstall` removes the AAI hook
    and leaves a foreign one, and the installed `pre-commit` is byte-identical to
    the one the pre-change installer produced. TEST-309 pins the twin: the `.ps1`
    writes the same marker and the same refusal predicate as the `.sh`.
- Spec-AC-06: WHEN `aai-doctor` runs THEN it reports the guard as armed or not
  armed in a named category, and the not-armed line names the exact install command.
  - Verification: TEST-310 — `node .aai/scripts/aai-doctor.mjs` run against a
    fixture without the hook prints the category with a not-armed status and the
    literal `install-pre-commit-hook`, and against a fixture with the hook prints
    the same category as armed.
- Spec-AC-07: WHEN the guard is armed in this repository THEN a marker-less commit
  attempt in the shipping checkout is refused and the shipping tree is unchanged.
  - Verification: TEST-313 — a degrade-and-report arm on the LIVE
    `$PROJECT_ROOT`: when `$PROJECT_ROOT/.git/hooks/reference-transaction` carries
    the `AAI:REF-GUARD` marker it asserts that `git commit --allow-empty` exits
    non-zero with the refusal on stderr, `git rev-parse HEAD` is unchanged and
    `git status --porcelain=v1` is byte-identical before and after; when the hook is
    absent it reports a NAMED skip (`ref-guard not armed on this checkout`) instead
    of passing silently. Plus the live transcript recorded under `docs/ai/tdd/`,
    which is what evidences the AC on the operator host — no CI checkout has the
    hook, so the arm alone can never be the whole proof.
- Spec-AC-08: WHEN the new suite runs THEN the shipping repository's own
  `.git/hooks` directory is byte-unchanged by it.
  - Verification: TEST-311 — a digest of every file under
    `$PROJECT_ROOT/.git/hooks` taken at suite start equals the digest taken at suite
    exit, and every installer invocation in the suite named a path under the suite's
    own `mktemp -d`.
- Spec-AC-09: WHEN the canon surface is updated THEN HAZ-SCRATCH names the guard
  and the marker, and the prompt-corpus byte budget is unchanged.
  - Verification: TEST-312 — `.aai/SUBAGENT_CONTRACT.md` contains both
    `AAI_GIT_WRITE` and `AAI:REF-GUARD`, the five `HAZ_IDS` anchors and five
    `HAZ_SCARS` citations that `tests/skills/test-aai-hygiene-pack.sh` pins are all
    still present, and `bash tests/skills/test-aai-prompt-diet.sh` exits 0 with
    `JUSTIFIED_GROWTH_BYTES` still 2392.

## Constitution deviations

- Article 5 (additive first). Arming the guard CHANGES the behavior of `git commit`,
  `git branch` and `git reset --hard` for every actor in a guarded checkout,
  including the operator working by hand. Article 5 permits a breaking change at a
  public boundary when it is explicit and documented, and this one is: it is inert
  until an explicit install step runs, it is fully reversible with one
  `--uninstall`, its refusal text names the marker and the uninstall command,
  `aai-doctor` reports its armed state on every run, and D2 bounds the affected
  operation set by measurement rather than by claim. Recorded here rather than left
  implicit because the operator, not only the agents, pays the friction.

Articles 1, 2, 3, 4, 6 and 7: no deviation. The guard is a plain POSIX-sh file
(article 3), it degrades by exiting 0 on every state and ref class it does not own
(article 4), it touches no STATE writer (article 6), and it neither performs nor
enables a merge (article 7).

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                     | Status  | Evidence | Review-By | Notes                                                                                     |
|------------|-------------------------------------------------------------------------------------------------|---------|----------|-----------|---------------------------------------------------------------------------------------------|
| Spec-AC-01 | A marker-less refs/heads transaction in a guarded checkout is aborted and no ref moves           | planned | —        | —         | the central arm; needs the TEST-302 mutation proof and the TEST-303 unmutated control        |
| Spec-AC-02 | The same transaction with AAI_GIT_WRITE=1 completes exactly as in an unguarded repository        | planned | —        | —         | compared against a control fixture, not against a remembered expectation                     |
| Spec-AC-03 | Reads and non-refs/heads operations in a guarded checkout are unaffected                         | planned | —        | —         | includes the allocator seam TEST-306; says nothing about submodules or LFS                   |
| Spec-AC-04 | A disposable clone of a guarded checkout carries no guard and stays freely writable              | planned | —        | —         | the SPEC-0155 seam; proves the two mechanisms compose                                        |
| Spec-AC-05 | The installer is idempotent, refuses a foreign hook, uninstalls cleanly, and leaves pre-commit intact | planned | —        | —         | TEST-309 is a STATIC twin check; nothing is executed on Windows                          |
| Spec-AC-06 | aai-doctor names the guard and reports armed or not armed with the install command               | planned | —        | —         | the anti-SPEC-0029 arm; a dormant mechanism must at least be visible                         |
| Spec-AC-07 | The guard is armed in this repository and refuses a marker-less commit there                     | planned | —        | —         | TEST-313 asserts only where armed and reports a NAMED skip elsewhere; the live transcript is what evidences it on the operator host |
| Spec-AC-08 | The new suite leaves the shipping repository's .git/hooks byte-unchanged                         | planned | —        | —         | HAZ-SCRATCH applied to a scope whose deliverable is a file inside .git                       |
| Spec-AC-09 | HAZ-SCRATCH names the guard and the marker at zero prompt-corpus cost                            | planned | —        | —         | SUBAGENT_CONTRACT.md sits outside TEST-010's glob AND its extra accounting, so the cost is 0 |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

1. `.aai/scripts/install-pre-commit-hook.sh` — a second hook body and a second
   marker (`AAI:REF-GUARD`) alongside the existing `AAI:INDEX-AUTOGEN` one. The
   existing pre-commit body, its idempotence branch, its foreign-hook refusal and
   its `--uninstall` branch are extended per hook, never rewritten; the header and
   usage text say "hook set" instead of "pre-commit hook".
2. `.aai/scripts/install-pre-commit-hook.ps1` — the same two additions in the twin.
   MEASURED, not assumed: unlike `aai-run-tests.ps1`, this `.ps1` is a real
   independent implementation (it computes `$hookPath` and writes the body itself,
   line 36), so it does NOT inherit the change by delegation and must be edited.
3. `.aai/scripts/aai-doctor.mjs` — one new category next to CAT-12, reporting the
   guard's armed state and naming the install command when it is absent.
4. `.aai/SUBAGENT_CONTRACT.md` — HAZ-SCRATCH gains one sentence naming the guard,
   the `AAI_GIT_WRITE=1` allowance and the refusal it produces. The `HAZ_IDS` and
   `HAZ_SCARS` arrays that `tests/skills/test-aai-hygiene-pack.sh` pins are NOT
   changed: this is an allowance, not a sixth hazard.
5. `tests/skills/test-aai-git-ref-guard.sh` — new suite, TEST-301..TEST-312. Every
   `test_*` function must be wired into `main()` or
   `.aai/scripts/check-test-registration.mjs` fails the deslop suite.

Data flows: one new value crosses a process boundary — the `AAI_GIT_WRITE`
environment variable, read by the hook, set per command by the caller, never
persisted anywhere.

Edge cases, each with a decided behavior:

- the hook is absent (a fresh clone, a CI checkout, an unarmed host) — git runs
  nothing and the repository behaves exactly as today. The boundary is per checkout
  and this is the honest limit, surfaced by Spec-AC-06 rather than hidden.
- a transaction mixes a `refs/heads/` line with others — one matching line refuses
  the whole transaction. Git has no partial abort and this spec does not invent one.
- stdin cannot be read — the hook exits 0. Fail-open on its OWN failure, matching
  `claude-hook-gate.sh`'s ratified contract: a broken guard must not brick a
  checkout, and the class it addresses is accidental, not adversarial.
- `AAI_GIT_WRITE` is set to anything other than the literal `1` — refuse. Exact
  match only, mirroring `AAI_OPERATOR_MERGE`.
- an operator's `git pull` that fast-forwards `refs/heads/main` — refused without
  the marker. Deliberate: `git pull` moving a local branch is exactly the
  main-pollution shape the repo already carries a scar for.
- the repository has a foreign `reference-transaction` hook — the installer refuses
  and prints the manual-merge instruction, exactly as the pre-commit branch does.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                                                                              | Status  |
|----------|------------|-------------|-----------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-301 | Spec-AC-01 | integration | tests/skills/test-aai-git-ref-guard.sh  | commit, branch, branch -D and reset --hard each exit non-zero in a guarded fixture; HEAD count and refs/heads listing byte-identical; stderr names AAI_GIT_WRITE | pending |
| TEST-302 | Spec-AC-01 | integration | tests/skills/test-aai-git-ref-guard.sh  | THE MUTATION PROOF — the fixture's byte COPY of the installed hook is mutated to exit 0 unconditionally; the marker-less commit then succeeds and TEST-301's assertions fail | pending |
| TEST-303 | Spec-AC-01 | integration | tests/skills/test-aai-git-ref-guard.sh  | THE UNMUTATED CONTROL — the same fixture, hook unmutated, refuses and records zero ref movement                                              | pending |
| TEST-304 | Spec-AC-02 | integration | tests/skills/test-aai-git-ref-guard.sh  | with AAI_GIT_WRITE=1 the same four operations exit 0 and git log --format=%T%P%s is byte-identical to an unguarded control fixture           | pending |
| TEST-305 | Spec-AC-03 | integration | tests/skills/test-aai-git-ref-guard.sh  | status, log, rev-parse, diff, checkout of an existing branch, worktree add --detach, fetch and tag each exit 0 with no refusal on stderr      | pending |
| TEST-306 | Spec-AC-03 | integration | tests/skills/test-aai-git-ref-guard.sh  | SEAM — with a bare origin and the guard armed, allocate-doc-number.mjs exits 0 and the refs/aai/docnums reservation is present on the origin  | pending |
| TEST-307 | Spec-AC-04 | integration | tests/skills/test-aai-git-ref-guard.sh  | SEAM — clone --local --no-hardlinks from the guarded fixture exits 0, the clone has no reference-transaction hook, and a marker-less commit inside it exits 0 | pending |
| TEST-308 | Spec-AC-05 | integration | tests/skills/test-aai-git-ref-guard.sh  | installer contract in a fixture: install, byte-identical re-run, foreign-hook refusal, --force, --uninstall, and a pre-commit byte-identical to the pre-change installer's | pending |
| TEST-309 | Spec-AC-05 | unit        | tests/skills/test-aai-git-ref-guard.sh  | the .ps1 twin carries the AAI:REF-GUARD marker, the refs/heads predicate and the AAI_GIT_WRITE check, and still writes .git/hooks itself      | pending |
| TEST-310 | Spec-AC-06 | integration | tests/skills/test-aai-git-ref-guard.sh  | aai-doctor.mjs reports the guard category as not armed with the install command on a hookless fixture, and as armed on a guarded one          | pending |
| TEST-311 | Spec-AC-08 | integration | tests/skills/test-aai-git-ref-guard.sh  | a digest of every file under PROJECT_ROOT/.git/hooks is equal at suite start and suite exit                                                  | pending |
| TEST-312 | Spec-AC-09 | unit        | tests/skills/test-aai-git-ref-guard.sh  | SUBAGENT_CONTRACT.md names AAI_GIT_WRITE and AAI:REF-GUARD, the five HAZ_IDS and five HAZ_SCARS survive, and the prompt-diet suite exits 0    | pending |
| TEST-313 | Spec-AC-07 | integration | tests/skills/test-aai-git-ref-guard.sh  | LIVE, degrade-and-report — when PROJECT_ROOT carries the AAI:REF-GUARD hook, a marker-less commit there exits non-zero with HEAD and porcelain byte-unchanged; when it does not, a NAMED skip instead of a silent pass | pending |

RED-first requirements, per arm:

- TEST-301, TEST-303, TEST-304, TEST-305, TEST-307, TEST-308, TEST-309, TEST-310 and
  TEST-312 must each be observed FAILING on the pre-change tree — nothing installs a
  `reference-transaction` hook today, so every assertion about one is currently
  false. Record each red transcript under `docs/ai/tdd/`.
- TEST-302 is the mutation proof for Spec-AC-01 and TEST-303 is its required
  unmutated control on the SAME fixture. HAZ-RESTORE applies: the mutation is
  applied to the fixture's byte COPY of the installed hook, never to
  `.aai/scripts/install-pre-commit-hook.sh` and never to a hook in
  `$PROJECT_ROOT/.git/hooks`.
- TEST-306 and TEST-311 are expected GREEN before the change — the allocator already
  works and the suite does not yet exist to dirty anything. They are regression pins,
  not discoveries, and this spec says so rather than manufacturing a red for them.
- TEST-313 is expected to report its NAMED SKIP on the pre-change tree and on every
  CI checkout, and to ASSERT only where the guard is armed. It is deliberately not a
  red-first arm: manufacturing a red for it would mean arming the operator's
  shipping checkout before the mechanism is reviewed. Its red is the live transcript
  taken at arming time, which is the same observation made once by hand.

## Verification

Commands, in order:

1. `env -u AAI_ROLE bash tests/skills/test-aai-git-ref-guard.sh` — exit 0, with
   TEST-301..TEST-312 present in the output.
2. `env -u AAI_ROLE bash tests/skills/test-aai-suite-isolation.sh` — exit 0. The
   SPEC-0155 mechanism must be provably unaffected by a guarded shipping checkout.
3. `env -u AAI_ROLE bash tests/skills/test-aai-hooks-overlay.sh` — exit 0, TEST-013
   still passing. This scope must not install anything into `.claude/settings.json`.
4. `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh` — exit 0. The
   HAZ-SCRATCH edit must not break the hazard-anchor arm.
5. `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` — exit 0 with
   `JUSTIFIED_GROWTH_BYTES` unchanged at 2392.
6. `env -u AAI_ROLE bash tests/skills/test-aai-doctor.sh` and
   `env -u AAI_ROLE bash tests/skills/test-aai-deslop.sh` — exit 0 (the new doctor
   category, and `check-test-registration.mjs` over the new suite).
7. `sh -n`, `dash -n` and `bash -n` over the installed hook body and over
   `.aai/scripts/install-pre-commit-hook.sh` — all exit 0.
8. `env -u AAI_ROLE bash tests/skills/test-framework.sh` — exit 0, `Failed: 0`, and
   the isolation summary line still reporting every suite isolated.
9. The Spec-AC-07 live transcript in `/Users/ales/Projects/aai`, captured to
   `docs/ai/tdd/`.
10. `node .aai/scripts/spec-lint.mjs --path <spec>` and
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <spec>` —
    both exit 0.

Evidence artifacts: `docs/ai/tdd/` for the red transcripts, the TEST-302 mutation
transcript and the Spec-AC-07 live transcript; `tests/skills/results/<run>/` for the
sweep log.

PASS criteria: every TEST-xxx green AND every Spec-AC in a terminal status.

## Evidence contract

- ref_id: agent-shell-can-write-the-shipping-repo
- Spec-AC and TEST links: as tabulated above.
- Commands and exit codes: section `## Verification`, in order.
- Evidence paths: `docs/ai/tdd/` for the RED artifacts, the mutation transcript and
  the Spec-AC-07 live transcript; `tests/skills/results/<run>/` for the suite logs.
- Commit SHA or diff range: `main...fix/agent-shell-writes-shipping-repo` at review
  time.

Per `### Evidence by strategy` in `.aai/templates/SPEC_TEMPLATE.md`, the `tdd` row
applies: a stored RED artifact is owed for each AC-gating test, plus the full
verification matrix above.

## Registry items closed by this scope

Read from `node .aai/scripts/follow-ups.mjs list` at planning time (98 open).

CLOSED FULLY: none. This scope prevents two of the four recorded instances and says
so; claiming a full close on any of them would be the defect class this project
spends its days removing.

CLOSED QUALIFIEDLY:

- `fu-subagent-probe-hits-real-repo` (P1) — its words are "a validator probe helper
  ran git commands against the real repository and created two commits on main". The
  NAMED HARM is prevented: in a guarded checkout the probe's `git commit` aborts at
  exit 128 with nothing written, and the hand-run `git reset --mixed 5116c36` used to
  repair it would abort too. What is NOT closed is the broader phrase "ran git
  commands": a probe can still run every read, and can still write files. The
  qualification is also per checkout — an unarmed host has no guard at all
  (Spec-AC-06 is what makes that state visible instead of silent).
- `fu-empty-path-cd-stays-in-shipping-repo` (P2) — its committing consequence is
  prevented; the `cd ""` defect itself is untouched. A fixture path that computes
  empty still leaves the shell in the shipping repository, and everything that
  follows which is not a `refs/heads/` transaction still lands there. HAZ-CD stays
  exactly as load-bearing as it was.

NOT CLOSED, deliberately, with the reason:

- `fu-probe-redirect-lands-in-shipping-cwd` (P2) — a relative redirect creating a
  stray file is not a ref transaction. Preventing it needs a filesystem chokepoint,
  which does not exist below the OS, and the measurement in D6 is that only the
  Claude PreToolUse hook could even DETECT it — a route this repo has pinned shut.
- `fu-orchestrator-probe-touched-git` (P3) — `rm -rf` against `.git/worktrees` is a
  filesystem operation inside the git directory; git runs no hook for it. Same
  reason, same absence of a chokepoint.
- `fu-adhoc-probes-unisolated-report-only` (P2, context) — the canonical wrapper's
  suite-only isolation is a different mechanism and a different scope.

A scope that touches an open item's subject either closes the item or says why not
(docs/analysis/registry-growth-diagnosis.md). The two NOT CLOSED entries above are
that statement, and they are the honest residual of a P1 that has no complete
structural answer.
