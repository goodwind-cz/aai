# Code Review round 2 — single-writer-canon-contradiction (adversarial, post-Remediation)

```yaml
review:
  scope: git diff 061f3a1..HEAD (HEAD = 9f96799, branch docs/single-writer-canon); focus ca90e92..HEAD
  spec: docs/specs/SPEC-0152-spec-single-writer-canon-contradiction.md
  round: 2
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/ORCHESTRATION.prompt.md:8-12 (ENV row + UNSET + 'Then run any returned state_update_commands'); wc -l = 42 (<=45); TEST-RG-PIN-04 PASS with the new imperative-shape assertion" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/REMEDIATION.prompt.md:67 carve widened to 'steps 4-6', covering :72's bare-verb set-human-input; prefix-free sweep over all .aai/*.md finds zero uncovered directives in the declared surfaces; TEST-RG-PIN-05 PASS (5 files); test-aai-state.sh TEST-014 PASS" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/SUBAGENT_CONTRACT.md:74 (D1 + sole-agent carve, cross-ref now correctly attributed to .aai/SUBAGENT_PROTOCOL.md:66-72) + :76-83 rationalization table; .aai/SUBAGENT_PROTOCOL.md:282 merge input; TEST-RG-PIN-06 PASS" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "claim at .aai/SUBAGENT_CONTRACT.md:74 now qualified and TRUE (probes A/B/C/D below); exemplar at :58-59 byte-identical to .aai/templates/BRIEF_TEMPLATE.md:55-56; TEST-RG-PIN-07 PASS (3 arms), third arm independently mutation-bite-proved" }
      - { ac: Spec-AC-05, call: cannot-verify,
          citation: "docs/ai/tdd/red-20260824T151347Z-r-guard.log carries zero PIN-07 FAIL lines (round-1 F3, unchanged); the new third PIN-07 arm has no stored RED at all. Mutation half re-proved by me for PIN-04/05/07 with controls" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "select-suites.mjs names aai-r-guard for all six declared paths AND .aai/SKILL_TDD.prompt.md (7/7); tests/skills/suite-map.yaml:569; test-aai-hygiene-pack.sh exit 0" }
      - { ac: Spec-AC-07, call: non-compliant,
          citation: "measured 314067 -> 314941 = 874 B > the AC's 700 B; THREE JUSTIFIED_ADDITIONS entries (657 + 206 + 11) vs the AC's 'a single entry'. Not remediable in-tree (requires amending a frozen spec) — close-ceremony obligation, numbers updated from round 1's 863/two" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "git diff main --name-only INTERSECT the eight protected_paths_l3 entries (.aai/templates/docs-audit.template.yaml) = empty; registry closure deferred to close by design" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0152-spec-single-writer-canon-contradiction.md, line: 0,
          issue: "Spec-AC-04's own wording ('WHEN a result block carrying a state_update_commands: list is checked ... SHALL exit 0') is unconditional, while the delivered contract is correctly conditional on the template's indentation; the AC also says 'both arms' where PIN-07 now has three",
          failure_scenario: "the close ceremony flips Spec-AC-04 to a plain done citing 'exit 0', re-minting at AC level the exact absolute claim P1-2 removed from the contract" }
  cannot_verify:
    - { claim: "the orchestrator actually executes returned state_update_commands on a live serial ride",
        closes_with: "one observed serial ride whose STATE mutations land from a returned block, or a runtime harness arm; prose pins cannot show it — the spec records this as residual risk" }
    - { claim: "Spec-AC-05's 'each arm observed FAILING against the pre-fix text' for TEST-RG-PIN-07 (all three arms)",
        closes_with: "a RED log containing PIN-07 FAIL lines, or an honest AC rewording at the close; the stored log has zero. The mutation half IS now closed for the third arm (see P1-2 evidence)" }
  overall: pass
```

- Reviewer: Code Review role, fresh independent subagent (round 2, after Remediation `9f96799`)
- Branch: `docs/single-writer-canon` (verified with `git branch --show-current`; not switched, not pushed, no PR)
- Started (UTC): 2026-08-24T17:20:01Z / Ended (UTC): 2026-08-24T17:31:40Z
- Coaching check (anti-gaming): the dispatch named per-finding verification targets and one expected measurement (314941 / 874 / 2284), but pre-rated no severity, excluded no area, and pasted no diff. It also instructed "do not re-block" on P2-4 — I treated that as routing guidance, re-measured P2-4 independently anyway (and found the round-1 numbers had moved), and record it here. No coaching that suppressed a finding.

## Verdict

**PASS.** Both round-1 P1s are genuinely fixed — not papered over — and I re-attacked
each with a mutation or a fixture of my own rather than re-reading the diff. The four
remediate-in-tree P2s are closed as specified. P2-4 was correctly left alone.

Nothing new blocks. The residuals below are P3 assurance-strength items and one
close-ceremony bookkeeping duty whose numbers moved since round 1.

## Round-1 findings — adversarial verification

### P1-1 (`.aai/REMEDIATION.prompt.md:72`) — CLOSED

Read the whole file as an executing Remediation agent. The carve now reads:

```
67:   Dispatched, steps 4-6: return these as `state_update_commands:` instead of running
68:   them (.aai/SUBAGENT_CONTRACT.md). Sole agent: run them.
69:6) STOP after the reset + your agent-run append (METRICS below). Do NOT loop:
...
72:   explicit human decisions, record them via set-human-input and stop.
```

Genuinely covered. The carve sits at the tail of step 5 and is read **before**
step 6, "steps 4-6" now names step 6 explicitly, and "these" resolves to the
`set-human-input` command literally spelled out two lines above at `:65` — the
same command `:72` names by bare verb. The reflow is correct English and, as
claimed, byte-neutral: `"of\n   running them"` (18 B) -> `"of running\n   them"`
(18 B). Independently confirmed by the corpus arithmetic — total in-corpus delta
is exactly `657 + 206 + 11 = 874`, with no unaccounted byte from this edit.

**Prefix-free mutator sweep, repeated from scratch.** Mutator verb list taken from
`.aai/scripts/state.mjs` itself (`set-focus|set-phase|set-validation|set-code-review|
set-strategy|set-worktree|set-tdd-cycle|set-human-input|append-run|log-tick|reset-block`),
swept over **every** `.md` under `.aai/` (19 files carry hits), then filtered to
lines that do NOT contain the `state.mjs` literal — the exact hole that hid `:72`
through four rounds. 39 bare-verb lines. Every one adjudicated:

| Site | Call |
|---|---|
| `REMEDIATION:72` | **covered now** by the `steps 4-6` carve |
| `IMPLEMENTATION:105` (`adjust set-focus/set-phase flags`) | parenthetical inside step 10, carve at :108-109 |
| `IMPLEMENTATION:160`, `VALIDATION:273`, `REMEDIATION:82`, `SKILL_TDD:374/377` | `append-run` pointers into `.aai/ROLE_COMMON.md`, which carries its own D5 subagent carve-out |
| `INTAKE_COMMON:90` | a prohibition ("do NOT run set-strategy") |
| `ORCHESTRATION:28/33`, `ORCHESTRATION_PARALLEL:154` | orchestrator-side; the orchestrator IS the writer |
| `REMEDIATION:17`, `:76` | scope-of-authority / output-description prose, not directives (round-1 P3-2, unchanged) |
| `SKILL_LOOP:228-298, :360` | the carved sole-agent no-subagent lane |
| `SKILL_TDD:66` | the carve itself |
| `SUBAGENT_PROTOCOL:167-188` | orchestrator-side usage-capture flags |
| `STATE_FALLBACK.md:20-68` | the hand-edit fallback document (see P3-N4) |

Zero uncovered directives remain inside the spec's seven declared surfaces.
Intake AC-001 ("no surface simultaneously forbids and directs direct subagent
STATE mutation") now holds against a sweep that no longer requires the prefix.

### P1-2 (`.aai/SUBAGENT_CONTRACT.md:74`) — CLOSED, all three sub-checks

**(a) Is the qualified claim TRUE?** The claim now reads "ignores unrecognized
top-level extension keys **and their indented nested lines** ... never invalidates
an otherwise-clean block **written in the template's indentation** — a flush-left
rendering of the list is refused (`E-MALFORMED-LINE`)". I built four fixtures of my
own and ran the real checker:

| Probe | Rendering | Exit | Result |
|---|---|---|---|
| **A** | the template **verbatim, including its inline `# optional (D1): ...` comment**, two items, one carrying a colon inside a quoted arg (`--question "why: this?"`) | **0** | claim holds for the exact text a subagent copies |
| **B** | list items dedented to base indent (2 sp) | **1** | `E-MALFORMED-LINE unparseable block line: - node .aai/scripts/state.mjs set-phase ...` |
| **C** | items at 3 sp (deeper than base, shallower than template) | **0** | consistent with "deeper than base is consumed" |
| **D** | items at 4 sp with `--notes "a: b"` | **0** | colon-bearing payload is inert at depth |

Probe A matters most and the PIN-07 fixture does **not** cover it — the fixture omits
the inline comment. It is covered anyway, and by a stronger test than PIN-07:
`tests/skills/test-aai-role-output.sh` TEST-014 (SEAM-1) extracts the **first fenced
yaml block from `.aai/SUBAGENT_CONTRACT.md` itself**, fills the core fields by sed,
and asserts exit 0 — so the shipped exemplar, comment and placeholder included, is
checked verbatim on every run. `test-aai-role-output.sh` exits 0.

**Third PIN-07 arm — bite-proved by me, not taken on trust.** In a disposable
detached worktree at HEAD I mutated `.aai/scripts/check-role-output.mjs:432` to
tolerate flush-left list items
(`&& !body[i].content.startsWith('- ')`). Control: suite exit 0. Mutated: suite
**exit 1** with both new assertions firing —
`TEST-RG-PIN-07: a flush-left state_update_commands list ... must exit 1, not exit 0 (got 0)`
and the `E-MALFORMED-LINE` needle. The arm is a real guard on real behavior, not a
tautology. Worktree removed with a targeted `git worktree remove --force`.

**(b) Exemplar indentation + byte-identity.** `  state_update_commands:` (2 sp) with
`    - <fully-substituted ...>` (4 sp) — correct, and the shape probe A proves valid.
Byte-identity into the template:

```
$ cmp <(grep -A1 '^  state_update_commands:' .aai/SUBAGENT_CONTRACT.md) \
      <(grep -A1 '^  state_update_commands:' .aai/templates/BRIEF_TEMPLATE.md)   # exit 0, 206 B each
$ diff <fenced yaml block of CONTRACT> <fenced yaml block of BRIEF_TEMPLATE>     # identical, 17 lines each
```

Not just the two added lines — the **entire** result-block skeleton is byte-identical
across the two files. `test-aai-hygiene-pack.sh` (test_060) exits 0.

**(c) "Dropped purely-cosmetic blank line" — zero content-word loss.** Word multiset,
`18c7957` vs `HEAD`, under `/bin/bash` with `/usr/bin/grep`:

```
words base=796 head=848
comm -23 (present in 18c7957, absent in HEAD):  block.  contract  own  this
```

All four are the intended P3-1 correction — "or **this contract's own** review rule 2"
became "or `.aai/SUBAGENT_PROTOCOL.md`'s review rule 2" — plus the token `block.`
losing its period to `block written in the template's indentation`. `block` reappears
in the added set. **No content word was lost to the blank-line drop.** Line count
83 -> 84 (-1 blank, +2 exemplar). The removed blank sat between the `## Result block`
ATX heading and its paragraph, where CommonMark needs none.

**P3-1 cross-reference now resolves.** `.aai/SUBAGENT_PROTOCOL.md:66-72` review rule 2
does say the reviewer records via `state.mjs set-code-review` when it is the sole agent.

### P2-1 (ORCHESTRATION exit-4 lane) — CLOSED

`:20` now reads `dispatch Validation / Code Review per step 2.` Step 2 (`:7-12`) names
the ENV row, `append-run`, **and** "Then run any returned state_update_commands. Then
step 5." The reference resolves to exactly the two things the lane was missing. File is
42 lines (test_060 ceiling 45). Ledgered honestly at the measured +11 B.

(Nit, INFO only: step 2 opens "Exit 0 (dispatch): relay the JSON dispatch", and the
exit-4 lane has no JSON dispatch to relay. "per step 2" plainly scopes to the
procedure, so no reader is misled.)

### P2-2 (PIN-04/05 pinned tokens, not the rule) — CLOSED as specified; a weaker residual remains

The fix implements precisely what round 1 asked for: `instead of running` +
`Sole agent: run them` on every PIN-05 file, and the literal
`run any returned state_update_commands` for PIN-04's opposite polarity.

**Round-1 decoy re-run, now caught.** Replacing the PLANNING carve with
`NOTE: see .aai/SUBAGENT_CONTRACT.md for state_update_commands background.`
(exit 0 in round 1) now fails:

```
FAIL: TEST-RG-PIN-05: PLANNING.prompt.md does not direct RETURNING state_update_commands instead of running them (imperative shape missing, decoy-satisfiable)
FAIL: TEST-RG-PIN-05: PLANNING.prompt.md does not carry the sole-agent imperative counterpart 'Sole agent: run them'
```

**New decoys of my own design** (negation / superseded framing — the class round 1
did not try), disposable detached worktree at HEAD, `cp` restore from a pristine copy,
never a restoring git command:

| # | Mutation | Suite |
|---|---|---|
| control | none | exit 0 |
| **N1** | PLANNING carve -> `SUPERSEDED 2026-08-25 — the old rule said to return these as \`state_update_commands:\` instead of running them (.aai/SUBAGENT_CONTRACT.md). Sole agent: run them. Dispatched agents now run them directly as well.` | **exit 0 — rule inverted, suite green** |
| **M-B** | ORCHESTRATION `Then run any returned state_update_commands` -> `Historically you would run any returned state_update_commands; that is no longer required` | **exit 0** |
| M-A | delete SKILL_TDD's clause (P2-3 check) | exit 1, PIN-05 |
| control 2 | restored, `git status --porcelain` empty | exit 0 |

So substring pins remain defeatable by an author who deliberately keeps the phrases
inside a negation. That is a different threat model from round 1's: N1 and M-B are not
plausible tidy-ups, they are knowing rule changes. See **P3-N1**.

### P2-3 (SKILL_TDD unpinned and unselectable) — CLOSED

- PIN-05's loop now covers `SKILL_TDD`; deleting the clause fails the suite (M-A above,
  three assertions fire), control green.
- `tests/skills/suite-map.yaml:569` adds `.aai/SKILL_TDD.prompt.md` to `aai-r-guard`.
  Verified per-path, not in aggregate:

```
$ node .aai/scripts/select-suites.mjs --files-from <one path per run>
.aai/SUBAGENT_CONTRACT.md  -> aai-r-guard   .aai/VALIDATION.prompt.md   -> aai-r-guard
.aai/ORCHESTRATION.prompt.md -> aai-r-guard .aai/REMEDIATION.prompt.md  -> aai-r-guard
.aai/PLANNING.prompt.md    -> aai-r-guard   .aai/SKILL_TDD.prompt.md    -> aai-r-guard
.aai/IMPLEMENTATION.prompt.md -> aai-r-guard
```

7/7. Spec-AC-06 is satisfied with one file to spare.

### P2-5 (SPEC-0026 misdescribed a live test) — CLOSED, correctly as dated corrections

Both rows preserve the delivery-time fact and append a dated correction rather than
overwriting history:

- Spec-AC-02 Evidence: `ORCHESTRATION 40 lines at delivery (corrected 2026-08-24: cap
  raised 40->45 by DEBT-0002, 2026-07-17; wrapper now 42 lines, still under the raised cap)`
- TEST-006: `ORCHESTRATION.prompt.md <=40 lines at delivery (corrected 2026-08-24:
  test_060's private cap now reads <=45, DEBT-0002, 2026-07-17) AND still routes ...`

No `|` characters inside the AC cells (the `40->45` arrow form, not a pipe), so the
table parser is safe — `test-aai-spec-lint.sh` exits 0. `SPEC-0026` frontmatter
(`status: done`, `number: 26`) untouched. The correction is also mirrored in the test
itself at `tests/skills/test-aai-hygiene-pack.sh:702-708`, so code and spec now agree.

### P2-4 (Spec-AC-07 budget) — correctly NOT remediated; its numbers MOVED

Re-measured independently, `/bin/bash -c` throughout:

```
$ /bin/bash -c 'cat .aai/*.prompt.md | wc -c'    @061f3a1 = 314067
$ /bin/bash -c 'cat .aai/*.prompt.md | wc -c'    @HEAD    = 314941      delta = 874
$ source tests/skills/lib/prompt-diet-ledger.sh  -> JUSTIFIED_GROWTH_BYTES=2284, stderr silent
```

Ledger chain, every hop measured and paid 1:1, no padding:
`314067 -> 314724` (657, the base scope) `-> 314930` (206, F2 SKILL_TDD)
`-> 314941` (11, P2-1). `657 + 206 + 11 = 874`. Pin `1410 + 874 = 2284`; TEST-012's
independent re-sum passes; TEST-010 headroom within 0..2048.

**No new unledgered growth.** But the close-ceremony note round 1 drafted is now stale:
the breach is **874 B against a 700 B budget across THREE entries**, not 863 across two.

## New findings

### P3-N1 — the strengthened pins still fall to a negation-framed rewrite

`tests/skills/test-aai-r-guard.sh:149,165-176`. Demonstrated, not theorised (N1 and M-B
above): text that keeps `instead of running`, `Sole agent: run them` and
`run any returned state_update_commands` inside "SUPERSEDED" / "Historically ... no
longer required" framing deletes the rule with the suite green.

This is the irreducible limit of substring pinning, and the round-1 finding it descends
from is genuinely closed — the realistic threat (an editor tidying a clause into a
cross-reference) is now caught. An author writing "SUPERSEDED, dispatched agents now run
them directly" is not making a maintenance slip; they are changing canon, which the diff
and code review are the gate for. No observed bite, and the arms' PASS line makes no
universal-negative claim ("All five prompts ... name state_update_commands +
SUBAGENT_CONTRACT.md, primary path and fallback marker intact" is exactly what it checks).

**Disposition: accepted residual** (H6 (d)) — P3 assurance-strength, no bite, no false
record left anywhere. If the close wants it queued instead, the cheap durable form is a
negation-adjacency assertion (`SUPERSEDED|no longer|Historically` within N lines of the
pinned phrase), which is itself defeatable; the honest ceiling here is a semantic check
this repo does not have.

### P3-N2 — `.aai/SUBAGENT_CONTRACT.md` is at exactly 84/84 lines, zero slack

`tests/skills/test-aai-role-output.sh:463` caps the contract at 84 to keep >=6 lines of
headroom under the hard 90 cap (`test-aai-hygiene-pack.sh` test_080). HEAD is at 84. The
remediation bought its two exemplar lines by spending the blank line and one line of the
condensation margin. The guard is satisfied and the drop was harmless (verified above),
but the **next** normative line added to the contract fails TEST-020 and forces a
condensation pass — which is how the last two rounds' churn started.

**Disposition: accepted residual** — a cost, not a defect, and the guard will announce it.

### P3-N3 — the close-ceremony obligation for Spec-AC-07 and Spec-AC-04 must be restated

Two bookkeeping duties, both live at the AC-flip step (the table is still `planned`, so
the gate holds):

1. **Spec-AC-07** must not flip to a plain `done`. The reality is 874 B / three entries
   against a 700 B / one-entry AC. Round 1's promoted note says 863 / two.
2. **Spec-AC-04** must not flip to a plain `done` citing unconditional exit 0. Its own
   text says "WHEN a result block carrying a `state_update_commands:` list is checked
   ... SHALL exit 0"; probe B shows a YAML-legal rendering exiting 1. The **contract**
   is now honest; the **AC's phrasing** is not, and flipping it verbatim re-mints at AC
   level the absolute claim P1-2 just removed. It also says "both arms" where PIN-07 now
   has three.

**Disposition: close-ceremony** (both). This is the single NON-BLOCKING finding in the
`code_quality` block above; it is recorded here and must be named in
`code_review.notes`.

### P3-N4 — `.aai/STATE_FALLBACK.md` directs a hand-edit that R-GUARD cannot refuse

Every carved role step ends `FALLBACK — if .aai/scripts/state.mjs is absent: read
.aai/STATE_FALLBACK.md and follow it`, and that document (`:20-36`) instructs editing
`docs/ai/STATE.yaml` **by hand**. For a dispatched subagent that is the forbidden write
in its purest form, and unlike the CLI path there is no chokepoint to exit 3.

Mitigating, and why this is not P2: the carve line sits **after** the FALLBACK line in
all five files and says "return these ... instead of running them", so the carve is the
reader's last word; the lane only fires on an older vendored layer with no `state.mjs`;
`STATE_FALLBACK.md` is not in the spec's declared surface list; and this is pre-existing,
not a regression from any commit in this range.

**Disposition: successor-item** — same successor that must reconcile F7a
(`.aai/SKILL_CODE_REVIEW.prompt.md:9-14`'s "or an explicit instruction" grant, broader
than D1's sole-agent-only carve), F7b (`.aai/SKILL_WORKTREE.prompt.md:166-167`, which
provably cannot be fixed by copying the clause), and F7c
(`.aai/METRICS_FLUSH.prompt.md:42`). All four are the same question — what the
single-writer rule means outside the seven surfaces this scope declared.

## Round-1 P3s carried forward

- **P3-1** — **fixed** in `9f96799` (cross-reference now names `.aai/SUBAGENT_PROTOCOL.md`).
- **P3-2** `.aai/REMEDIATION.prompt.md:17` "Your only legal status **write** is the
  `reset-block` transition" still reads as an authorization to write. Scope-of-authority
  prose, not a directive; the `steps 4-6` carve governs the actual command.
  **Accepted residual.**
- **P3-3** PIN-04's `grep -qiE 'unset|non-`?subagent`?|not carry|MUST NOT carry'` still
  matches bare `unset` anywhere in the file (one occurrence today, at `:9`).
  **Accepted residual** — same class as P3-N1.
- **INFO** the new arms still end `[[ "$FAILED" == 0 ]] && log_pass ... || true`,
  coupling each arm's PASS line to the global `FAILED`. No bite while green; a failing
  arm still silences later PASS lines and makes triage read as a cascade.

## Checks performed

| Command | Exit | Note |
|---|---|---|
| `git branch --show-current` | 0 | `docs/single-writer-canon`, HEAD `9f96799` |
| `env -u AAI_ROLE bash tests/skills/test-aai-role-output.sh` | 0 | incl. TEST-014 SEAM-1 (contract skeleton verbatim) and TEST-020 at 84/84 |
| `env -u AAI_ROLE bash tests/skills/test-aai-r-guard.sh` | 0 | PIN-01..07, PIN-07 now 3 arms |
| `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` | 0 | TEST-010/011/012 green, pin 2284 |
| `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh` | 0 | test_060 byte-identity + <=45 ceiling |
| `env -u AAI_ROLE bash tests/skills/test-aai-spec-lint.sh` | 0 | SPEC-0026 corrections lint clean |
| `env -u AAI_ROLE bash tests/skills/test-aai-state.sh` | 0 | TEST-014 nine prompts intact (Spec-AC-02) |
| `node .aai/scripts/check-test-registration.mjs` | 0 | — |
| `/bin/bash -c 'cat .aai/*.prompt.md \| wc -c'` @061f3a1 / @HEAD | 0 | 314067 / **314941** -> 874 B |
| `source tests/skills/lib/prompt-diet-ledger.sh` | 0 | **2284**, stderr silent; 657+206+11=874 |
| `wc -l` ORCHESTRATION / SUBAGENT_CONTRACT | 0 | **42**/45, **84**/84 |
| prefix-free bare-verb mutator sweep, all `.aai/**/*.md` | 0 | 39 bare-verb lines, **zero** uncovered directives |
| checker probes A/B/C/D (own fixtures) | 0/1/0/0 | qualified claim TRUE; B names `E-MALFORMED-LINE` |
| `cmp` exemplar CONTRACT vs BRIEF_TEMPLATE; `diff` whole fenced block | 0 / 0 | 206 B each, byte-identical; blocks identical |
| word-multiset `comm -23` 18c7957 vs HEAD, SUBAGENT_CONTRACT.md | 0 | 4 removals, all the intended P3-1 edit; **zero** content loss |
| decoys N1 / M-B / M-A / round-1 decoy + 2 controls | 0 / 0 / 1 / 1, 0/0 | **P3-N1**; P2-2 and P2-3 fixes confirmed |
| checker-mutation bite proof of PIN-07 arm 3 + control | 1 / 0 | the new arm is a real guard |
| `node .aai/scripts/select-suites.mjs`, 7 single-path runs | 0 | `aai-r-guard` selected 7/7 |
| `git diff main --name-only` INTERSECT `protected_paths_l3` | 0 | empty (Spec-AC-08) |
| `node .aai/scripts/docs-audit.mjs --check --strict --no-event` | 0 | NEEDS-TRIAGE(1) = this scope's own `probable-false-open` draft, cleared by the close |
| `git worktree remove` x2, `git worktree list` | 0 | only the shipping tree remains |

Hazards honored: both probe worktrees were disposable detached worktrees under the
dispatch's absolute scratch path (HAZ-SCRATCH, HAZ-CD), mutations were applied to the
worktree copy and undone by `cp` from a pristine copy — no restoring git command on any
tracked file (HAZ-RESTORE) — and each was removed with a targeted
`git worktree remove`, never `prune` (HAZ-WORKTREE). All measurement ran under
`/bin/bash -c` with `/usr/bin/grep`. No ledger was rewritten (HAZ-LEDGER).
`docs/ai/STATE.yaml` was NOT written — the state commands are returned in the result
block. Only this report was committed.

## Next steps

1. Orchestrator: record `code_review.status = pass` from the returned
   `state_update_commands`, with the P3-N3 obligations quoted in `notes`.
2. Close ceremony (next phase):
   - flip Spec-AC-01..08 with evidence; **Spec-AC-07 with the 874 B / three-entry
     reality**, **Spec-AC-04 with the indentation qualifier and three arms**,
     **Spec-AC-05 with the honest RED gap** (mutation half closed, RED half not);
   - close `fu-subagent-state-write-contradiction` with `resolved_by`, qualified for
     the surfaces outside the declared seven;
   - file the P3-N4 successor item covering STATE_FALLBACK / SKILL_CODE_REVIEW /
     SKILL_WORKTREE / METRICS_FLUSH (id <= 40 chars, per
     `fu-report-ids-exceed-registry-cap`).
