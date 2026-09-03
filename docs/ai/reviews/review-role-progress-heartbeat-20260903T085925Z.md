# Code Review — role-progress-heartbeat, ROUND 2 (single dual-verdict pass)

```yaml
review:
  scope: "git diff 4774e90..0947c3a (branch change/role-progress-heartbeat, worktree /Users/ales/Projects/aai-change-heartbeat)"
  spec: docs/specs/SPEC-DRAFT-spec-role-progress-heartbeat.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-001/TEST-002 green in my own full sweep (results/test-20260903-083237/aai-heartbeat.log); real `git worktree add`, --git-common-dir observed as '.git' / '../.git' / an absolute path, all three path.resolve to one location; heartbeat.mjs:126,198 use path.resolve for the git output" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-003 green; heartbeat.mjs:344-347 prints exactly `heartbeat: none recorded` and exit 0; --json prints {slots:[],degraded:[]}" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-004 green; heartbeat.mjs:269 one path per slot, no cross-process read-modify-write anywhere in the file" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-005/006/007 green; sanitizeMessage heartbeat.mjs:171-178 (C0/C1 -> space, control+bidi dropped, slice 200); usage refusals heartbeat.mjs:218-233" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-008/009/018 green; degrade() heartbeat.mjs:133-136 writes stderr and exits 0; all three named branches (git absent :192, sweep failure :254, write failure :273) reached before or without a write" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-010 green; heartbeat.mjs:314-321 names the damaged slot in both stdout and the JSON `degraded` array and continues" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-011 green AND independently reproduced by me — see 'B1 closure' below. The AC now states the mechanism that exists (prefix bound, symmetric window) and TEST-011 asserts both halves including the uncomfortable one" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-012 green over 118 files with a 60-file floor (live corpus 119) and a one-file allowlist; TEST-013 green; my own mutation in close-before-push-guard.mjs FAILED the arm. Residual basename hole recorded as N1 — narrower than the AC's own words, which say 'the gate-script corpus', and the corpus is enumerated by path" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-014 green; .aai/VALIDATION.prompt.md c3 carries the runnable invocation plus 'exits 0 on every runtime failure' and 'an absent heartbeat is silence, never a finding'; my own corpus grep confirms VALIDATION.prompt.md is the ONLY .aai/*.prompt.md naming heartbeat" }
      - { ac: Spec-AC-10, call: compliant, citation: "re-measured by me under plain bash with /usr/bin/wc -c: VALIDATION.prompt.md 19993 -> 20372 = +379 B; live .aai/*.prompt.md glob 321332 -> 321711 = +379 B; ledger sum JUSTIFIED_GROWTH_BYTES=10324 == want_growth 10324. PROFILES.yaml core: row present, suite-map.yaml aai-heartbeat row present, cd-subshell-leak baseline row present. TEST-015/016/017 green in their own suites" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-heartbeat.sh, line: 698,
          issue: "TEST-012's allowlist matches on BASENAME (`case \"$allow\" in *\" $base \"*`), not on the repo-relative path, so ANY file anywhere under .aai/scripts/ named heartbeat.mjs is exempt from the deny-by-default sweep. This is the same class as the finding that drove the inversion — a corpus member the check cannot see — one directory level down.",
          failure_scenario: "REPRODUCED. I created .aai/scripts/lib/heartbeat.mjs containing `// gate reads heartbeat` and ran the suite: TEST-012 PASSED and its own count dropped 119 -> 118, i.e. the file was silently skipped, not cleared. `lib/heartbeat.mjs` is a plausible name for a shared helper extracted from this very script. Fix is one line: compare `${f#\"$PROJECT_ROOT/\"}` against an allowlist of `.aai/scripts/heartbeat.mjs`." }
      - { rank: NON-BLOCKING, file: .aai/scripts/heartbeat.mjs, line: 300,
          issue: "`read` lists entries matching `hb-` AND `.json` (:300); the GC sweeps entries matching `hb-` ALONE (:253). The set of files an operator can SEE through this tool is therefore strictly narrower than the set the tool will DELETE.",
          failure_scenario: "REPRODUCED. An hb-notes.txt placed in the heartbeat directory is invisible to `heartbeat read` (output showed only the one real slot) yet sits inside the sweep's reach. An operator aiming --dir at a shared directory runs `read` to check what is at risk, sees only their own slot, and concludes the directory is otherwise untouched; a 25-hour-old hb-inventory.csv is then deleted by the next write at exit 0 with a success line. Note the obvious fix is the WRONG one: narrowing the GC to `.json` would strand the `<slot>.tmp.<pid>.<seq>` temps the sweep exists to collect. The coherent fix is to widen `read` to name non-.json `hb-` entries as degraded, so what the GC can delete is what the operator can see." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 0,
          issue: "`fu-layer-profiles-suite-load-fragile` and `fu-reaper-epoch-export-fails-test005` are NOT on this branch. Both exist only as an UNCOMMITTED working-tree modification to docs/ai/decisions.jsonl in the primary checkout at /Users/ales/Projects/aai, on `main` (git status reports `MM`).",
          failure_scenario: "A PR from this branch lands without either record. The attribution that keeps the layer-profiles flake off this ride's ledger is stored nowhere durable — a `git restore docs/ai/decisions.jsonl` or a branch switch in the primary checkout drops both, and the next sweep failure has no prior art to point at. This is the failure mode LEARNED already records for EVENTS.jsonl, applied to decisions.jsonl. Not a defect in the reviewed diff; an orchestrator close-ceremony action." }
  cannot_verify:
    - { claim: "That an LLM role actually emits the heartbeat at each round boundary at runtime",
        closes_with: "a manual multi-round observation; TEST-014 pins the INSTRUCTION, not the behaviour, and the spec records this as R3 rather than papering over it" }
    - { claim: "Behaviour on Windows / PowerShell — the suite is bash-only, there is no .ps1 or Pester arm, and both the git probe (execFileSync) and the chmod-000 degrade arm are POSIX-shaped",
        closes_with: "a Windows CI leg exercising heartbeat.mjs; no Spec-AC claims Windows, so this is an unclaimed gap rather than a deviation" }
    - { claim: "That the aai-layer-profiles TEST-004 flake Validation hit is pre-existing rather than change-caused",
        closes_with: "corroborated but not independently proven by me — my own full sweep on this tree was 85/85 with aai-layer-profiles PASS, so I could not reproduce the failure at all; I did not re-run Validation's controlled 8-way base-vs-change comparison" }
  overall: pass
```

## Scope and preflight

Reviewed `git diff 4774e90..0947c3a` in the dedicated worktree
`/Users/ales/Projects/aai-change-heartbeat` on `change/role-progress-heartbeat`.
Working tree carried one pre-existing modification (`docs/ai/tests/test-runs.jsonl`),
to which my own sweep appended a row. Sixteen files in the diff; the review
covered all of them plus `.aai/scripts/lib/runtime-file.mjs`, which is not in the
diff but whose semantics the corrected claims now rest on.

Protected L3 confirmed untouched (empty diff for `state.mjs`, `lib/state-engine.mjs`,
`lib/state-core.mjs`, `allocate-doc-number.mjs`, both `pre-commit-checks` files,
`.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`).

`--ac-flip-check spec-role-progress-heartbeat` exits 0 ("no done row claims delivery
ahead of the close flip"). `--gate` exits 1 on ten `planned` rows, which is the
CORRECT state per VALIDATION step 8a and not a finding.

## Coaching attempt, recorded per the anti-gaming contract

The dispatch pre-characterized findings in several ways the contract forbids: it
named the two observations Validation left open and labelled them "non-blocking"
in advance, reported which of Validation's judgements were "correctly rejected",
told me "the last two FAILs were about wording, not behaviour", and closed with
"if the code and the claims are now sound, say PASS". I reviewed the full scope
independently anyway. Of the three NON-BLOCKING findings below, one (N1) was
handed over as a hypothetical and is recorded here because I reproduced it, and
one (N3) is not in the dispatch's list at all.

## B1 closure — verified by my own reproduction, not by the claim

My round-1 BLOCKING finding was `reapAsides(dir, '', …)`: an unbounded 24-hour GC
over any caller-named directory. Both halves of the fix I recommended landed, and
both hold under my own probes.

| probe (my run, this tree) | result |
|---|---|
| `hb-foreign.json`, 30 h old, this script never wrote it | REAPED |
| `hb-someone-else.txt`, 30 h old | REAPED |
| `hb-future.json`, mtime +48 h | REAPED (symmetric window) |
| `operator.txt`, `other.json`, unprefixed, 30 h old | SURVIVE |
| `hb-a-directory/` stale directory | not reaped, silently, and not counted as reaped |
| `hb-link.json` -> a real stale target | link removed, target survives |
| dangling `hb-` symlink | skipped at statSync |
| `--dir ""` from a directory holding a stale `important.mjs` | exit 2, `heartbeat: --dir is empty`, file survives |
| `AAI_HEARTBEAT_DIR=""` from the same directory | falls through to the git probe (truthiness-guarded env read), does NOT resolve to cwd; file survives |

The last row is worth naming: the cwd hazard is closed on the environment path as
well as the flag path, which the AC does not claim and no arm pins, but which is
the behaviour that actually ships.

My second round-1 finding — TEST-012 blind to `lane-gate.mjs` — is closed by the
inversion. I re-planted, this time in `close-before-push-guard.mjs`, a gate the
old enumerated list also never named: the arm FAILED with the offender named.
Corpus is 119 files against a floor of 60; the single allowlist entry is
necessary (heartbeat.mjs carries 29 self-references); the only file under
`.aai/scripts/` outside the three globs is `PSScriptAnalyzerSettings.psd1`, a
settings file with no executable path. The residual is N1 below.

## 1 — Is the narrowed AC-07 true, and is the narrowing honest?

True. Every clause of the new AC-07 matched my own reproduction, including the
symmetric window, which is the clause most likely to have been asserted from the
library header rather than measured — I measured it.

Honest, and I want to be specific about why, because "we narrowed the claim after
being caught" is exactly the shape that can hide a retreat. Three things separate
this from one:

- **The mechanism is the one my own round-1 report recommended.** That report said
  the cleanest fix was "to give slot files a common prefix (`hb-<ref>__<role>.json`)
  and sweep with that prefix". What round 2 falsified was the *sentence written
  about* the delivered mechanism, not the mechanism. Round 3 moved the sentence to
  the mechanism. The alternative direction — keeping the ownership claim and
  building an ownership bound — would require a manifest of written files with its
  own load/write/stale lifecycle, which is precisely the bespoke sidecar lifecycle
  D7 and `runtime-file.mjs`'s CONVENTION PIN exist to forbid. Narrowing the claim
  was the only move that did not make the design worse.
- **TEST-011's new arms are the honest test, not an accommodation.** The
  distinction I applied: an accommodation asserts only what is comfortable and
  leaves the cost unpinned. These arms assert the COST — that a prefixed foreign
  file IS deleted — and the failure message says so in the imperative: "if the
  sweep is ever narrowed to files it owns, this fails and Spec-AC-07's third clause
  has to be re-widened in the same commit". That makes the weaker bound
  load-bearing in the suite, so it can be neither silently strengthened nor
  silently weakened. A test that planted only unprefixed foreign files would have
  stayed green under either mechanism, which is the arm's own stated reason for
  existing.
- **The rejection of shape-gating is recorded with a reason I checked, not
  asserted.** I read `atomicWrite`: temps are `<slot-file>.tmp.<pid>.<seq>`, so they
  inherit the prefix but are not slot-shaped by filename. A temp abandoned after
  `writeFileSync` but before `renameSync` holds a complete valid payload and would
  pass `isSlotShape`; one abandoned mid-write would fail it and be kept forever.
  So a pure `isSlotShape` gate genuinely cannot cover the temps, and Validation's
  reasoning is sound. One caveat for the record: a gate of "slot shape OR temp
  name pattern" *could* cover them. The spec gives a second, independent reason for
  declining ("more machinery than the risk warrants") which carries the case, so
  the recorded rationale is not load-bearing on the slightly over-stated half.

## 2 — Did the three PROVES surfaces converge?

Yes, and mechanically so. Round 2's failure mode was three different strengths in
three places, so I re-tested it as a set rather than reading each in isolation.
All four causes of an absent slot — never-made dispatch, pre-round-boundary,
separate clone, degraded write — appear in the spec bullet, the `heartbeat.mjs`
header (lines 19-28) and the CHANGELOG entry. All three carry the same
which-process narrowing ("corroboration, never proof"), the same prefix bound,
and the same symmetric-window statement. `.aai/VALIDATION.prompt.md` c3 ("an
absent heartbeat is silence, never a finding") agrees with D4's every-degrade-
exits-0 rule, which I verified in code: the sweep-failure degrade at :254 sits
before the write at :271, so a degrade never leaves a partial slot.

## 3 — The one-file allowlist

Verified biting (`close-before-push-guard.mjs` mutation), verified necessary
(29 self-references), verified non-vacuous (119 files, floor 60). Two exemption
routes checked: the `find` glob misses only `PSScriptAnalyzerSettings.psd1`, which
carries no executable path and is a non-issue; the basename match is a real hole
and I reproduced it — see N1. Dropping `generate-live-status.mjs` is the right
call and is justified in three places with the same reason (zero references
today, the seam is explicitly unbuilt, and a planted read passed silently), so the
cost of building the panel later is one allowlist line with a reason attached.

## 4 — "Extension, not a sixth"

My read: honest, and the disclosure is complete on every axis a reader could be
misled on — with one format limitation the entry itself names.

- It does not hide from a tally. The entry keeps `type: spec_amendment` and
  `owner_signoff: false`. I ran the tally: 10 unsigned `spec_amendment` records
  repo-wide, 3 for this ref, and this entry is counted in both. An owner counting
  amendments gets the higher number, not the lower one, which is the direction
  that matters.
- The grouping is the more readable record, not the cheaper one. These corrections
  retract claims that the line-647 record itself made, about the same spec surfaces
  that record named. Filing them as a new item would present retractions as fresh
  scope movement.
- Both superseded sentences are quoted verbatim, in the entry and again beside the
  corrected text in the spec, under dated EXTENDED / NARROWED annotations. I
  checked that no original sentence was rewritten in place and that
  `SPEC-FROZEN: true` survives. A spec reader cannot take the old wording as
  standing, and can still see what it said.
- "Falsified by reproduction, not merely improved on" is accurate, not rhetoric —
  I reproduced the prefixed-foreign reap and the +48 h reap myself.

The limitation: `extends` is consumed by no tooling in `.aai/scripts` and is not
in the schema documented in `decisions.jsonl`'s own header, and the append-only
format gives line 647 no forward pointer, so the supersession is discoverable only
by reading forward. The entry names this explicitly and mitigates it by putting the
durable record in the spec annotations, which is the right place. INFO, not a
finding.

## Code quality after three rounds

**Header volume.** The header grew 81 -> 91 -> 109 lines across the three commits
while executable code stayed roughly flat. That is the shape of
justification-by-volume, so I measured it against the codebase rather than against
taste: 172 comment lines of 391 total is 43%, inside the repo's own range —
`generate-live-status.mjs` 20%, `hitl-channel.mjs` 25%, `follow-ups.mjs` 28%, and
`runtime-file.mjs`, the library this file is explicitly modelled on, 49%. By the
house convention it is not an outlier. Every header section still earns its place
by naming a defect that bit (the path.join trap, the empty prefix, the
un-narratable over-claim) rather than restating what the code does.

**Degrade discipline.** Still coherent. Two grades, cleanly separated, with the
usage grade correctly extended to `--dir ''` (:372) rather than degraded — a
caller passing an unset shell variable has a wiring bug. Every runtime branch
exits 0 and writes nothing, and I verified the ordering that makes that true. The
`read` path never reaches `resolved.dir` when the probe failed, because `names`
stays empty; safe by construction rather than by a guard, but safe.

**Rejected alternatives.** Recorded rather than asserted, and checkable: no
`import.meta.url` main-guard with the open follow-up named (:386-390); shape-gating
declined with the temp-naming reason I verified; STATE.yaml declined in the intake
with the SUBAGENT_CONTRACT citation; the shared-file design declined in D2.

**The suite.** 15 arms in 850 lines against a 540-line median across 62 suites,
covering 8 ACs — above median, well below the large suites, and not accreted:
five log helpers plus `run_hb` / `make_repo` / `count_slots` / `check_deps` /
`cleanup` serve all 15. Shell discipline is right for this harness: `set -uo
pipefail` without `-e` so an arm can fail without killing the run, `|| RC=$?`
guarded at every one of the four capture sites (never a bare `rc=$?`), the
pipefail/SIGPIPE trap documented at :765, and the `cd` in TEST-011 in a plain
subshell rather than a command substitution. `bash -n` clean.

**Diet accounting.** Re-measured independently under plain bash with
`/usr/bin/wc -c` and `/usr/bin/grep`: +379 B on VALIDATION.prompt.md
(19993 -> 20372), +379 B on the live glob (321332 -> 321711), ledger sum 10324
matching `want_growth` exactly, 88 ledger entries. Headroom 4/2048 unchanged, and
the entry correctly declines to re-name the earlier ride's ledger key that those
4 bytes came from, since TEST-023 counts by key.

## The sweep — what I actually got

I ran the full sweep myself in this worktree,
`bash tests/skills/test-framework.sh`, without exporting
`AAI_REAP_STEP_START_EPOCH`.

```
Total:   85
Passed:  85 (100%)
Tripwire: 85/85 attested clean
Isolation: 85/85 isolated; 0 degraded
Seeding:  85/85 fully seeded
Concurrency: width 8; 0 wave(s) re-run serially
```

Run id `test-20260903-083237`, ledger row appended to
`docs/ai/tests/test-runs.jsonl`. All 15 heartbeat arms green; the three companion
arms green in their own suites (prompt-diet TEST-012 "JUSTIFIED_GROWTH_BYTES ==
10324 == independent re-sum", layer-profiles TEST-001 manifest conformance
core=162 extended=72 total=234, hygiene-pack suite-map row).

On the `aai-layer-profiles` TEST-004 flake: I did not reproduce it — that suite
PASSED in my run. That is consistent with Validation's pre-existing attribution
and, being a second green from a different run under different load, adds
independent weight to it. I did not re-run their base-vs-change comparison and am
not re-litigating it; the cannot_verify list records the limit of what my own run
proves.

## Warning dispositions (H6)

| # | finding | recommended disposition |
|---|---|---|
| N1 | TEST-012 allowlist matches basename, so a nested `heartbeat.mjs` is silently exempt | **(a) remediate-in-tree** — one line, `${f#"$PROJECT_ROOT/"}` against `.aai/scripts/heartbeat.mjs`. No spec movement: Spec-AC-08 already says "the gate-script corpus" and the corpus is enumerated by path, so this makes the arm match its own AC rather than changing it. If the orchestrator prefers not to touch the suite again this late, (b) promote-to-follow-up at P3 is defensible — the hole needs a name collision to bite and no such file exists today. |
| N2 | `read` filters `.json`, the GC does not — the visible set is narrower than the deletable set | **(b) promote-to-follow-up at P3** — `node .aai/scripts/follow-ups.mjs add --id fu-heartbeat-read-narrower-than-gc --ref role-progress-heartbeat --severity P3 --what "<one line>" --why "<one line>" --source "code review 2026-09-03, reproduced"`. Not a one-liner: the correct fix widens `read`, and narrowing the GC to `.json` would strand the temps. The bound itself is documented in four places, so this leaves no false record. |
| N3 | two follow-ups exist only as an uncommitted change on `main` in the primary checkout | **(c) orchestrator action before close** — commit them in the primary checkout, or re-file them on this branch so they travel with the PR. Nothing to change in this diff. |

## Next steps

1. Decide N1 (remediate or promote) and N2 (promote); record the artifact for each
   in the review notes and STATE per H6.
2. Commit or re-file the two follow-ups in N3 before the close ceremony.
3. Nothing else blocks. Both round-1 findings are closed against my own
   reproductions, the claim chain now matches the mechanism on every surface I
   checked, and my own full sweep is 85/85.
