```yaml
review:
  scope: "git diff main...HEAD (base main, head 3fad3552), 19 files"
  spec: docs/specs/SPEC-0264-spec-ride-status-and-resume.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/ride-status.mjs:102-165,201-221; TEST-3144, TEST-3145 (suite run, this review)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/ride-status.mjs:214; TEST-3146" }
      - { ac: Spec-AC-03, call: compliant, citation: "no write call in source (TEST-3158 grep); TEST-3147 tree hash + STATE sha over 3 fixtures x 3 calls; TEST-3154 origin refs" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/ride-status.mjs:105-109 (buildSnapshot + decide, no rule logic); TEST-3148 five fixtures vs real dispatcher CLI" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/ride-status.mjs:168-195; TEST-3149, TEST-3150" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/ride-status.mjs:153-161; TEST-3151" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/ride-status.mjs:229-240; TEST-3152" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/scripts/ride-status.mjs:242-252; TEST-3153, TEST-3154" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/scripts/ride-status.mjs:258-270; TEST-3155" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/SKILL_SHIP.prompt.md:10-12,100-101; .aai/SKILL_PR.prompt.md:297-299; .aai/SKILL_LOOP.prompt.md:458; glob +471 B (177+223+71); TEST-3156, TEST-3157, test-aai-prompt-diet.sh TEST-010/TEST-012" }
      - { ac: Spec-AC-11, call: compliant, citation: ".aai/system/PROFILES.yaml core row; suite-map aai-ride-status; 292 lines; TEST-3158" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-status.mjs, line: 110,
          issue: "An invalid STATE (buildSnapshot problems) yields ref_id null and the text line 'ride: none (no current focus)', the same signal as a genuinely empty focus; SKILL_SHIP INPUT branches on ref_id alone",
          failure_scenario: "STATE with current_focus.ref_id set but a duplicate top-level key (verified: ride-status --json prints ref_id null, blocker state_invalid). A no-argument /aai-ship reads null, runs ride-select show/next and starts a NEW ride; SKILL_INTAKE writes an intake doc and roadmap-edit ship-append may append a roadmap entry before state.mjs refuses the corrupt STATE, leaving stray artifacts for a ride nobody asked for" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_SHIP.prompt.md, line: 10,
          issue: "Resume decision ignores whether the in-flight ride is already closed; the probe's own closed fact is not consulted",
          failure_scenario: "Ride squash-merged through the GitHub UI, worktree and focus left in place (no /aai-merge cleanup). /aai-ship with no argument resumes it: dispatcher rule 14 no_action -> step 5 -> probe pushed not_done (remote branch deleted), pr_open not_done (PR merged, not open) -> SKILL_PR re-pushes the branch and opens a second PR for already-merged work. The spec Risks section accepts stale-focus resume, but not this re-open path" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_PR.prompt.md, line: 302,
          issue: "'Branch on the value the step-5 probe printed' now sits directly after a second, different 'probe' (ride-status.mjs probe), so the referent is ambiguous",
          failure_scenario: "An agent reads the ride-status probe output (pushed/pr_open/closed/flushed lines) as 'the step-5 probe', finds no github/azure/unknown/none value and, under 'NEVER guess', stalls or falls into GENERIC MODE on a github repo" }
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-status.mjs, line: 247,
          issue: "pr_open trusts gh pr list --head <branch>, which matches the head ref NAME across forks (spec D7 mandates this call)",
          failure_scenario: "Public repo, a fork PR from another contributor uses the same branch name (e.g. fix/typo). Probe reports pr_open: done with the fork's number; SKILL_PR skips gh pr create and watch-ci watches someone else's PR, so this ride never gets a PR" }
  cannot_verify:
    - { claim: "An agent following SKILL_SHIP actually resumes at RUN step 2 instead of re-intaking", closes_with: "an observed no-argument /aai-ship run with a focus in STATE (spec Seams crossed names this residual)" }
    - { claim: "pr_open against real gh / az CLIs (only a /bin/sh gh stub is exercised; azure --source-branch mapping untested here; Windows stub absent, validation NB-9)", closes_with: "one probe run on a real GitHub PR branch and one on an Azure repo" }
    - { claim: "pushed against a network remote (ssh/https auth prompts, offline) degrades to unknown within the 20 s timeout", closes_with: "probe run offline and against an ssh remote without agent" }
    - { claim: "Mutation records for the 15 Test Plan rows are valid at the current head", closes_with: "node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0264-spec-ride-status-and-resume.md exit 0 (not rerun by this review; evidence is gitignored, local-only)" }
  overall: pass
```

# Code review: ride-status-and-resume

- Scope: `git diff main...HEAD` in worktree `/Users/ales/Projects/aai-worktrees/ride-status-and-resume`, branch `feat/ride-status-and-resume`, head `3fad3552`, all 19 files (matches STATE `code_review.scope`; validation NB-6 satisfied).
- Spec: `docs/specs/SPEC-0264-spec-ride-status-and-resume.md` (frozen, ceremony 2).
- Working tree: only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (append-only telemetry from runs), outside the reviewed range.

security_relevant: false

## Dispatch note (anti-gaming contract)

The dispatch prompt named prior validation NBs (NB-4, NB-7, NB-8, NB-9) as already known and stated the D9 narrowing is owner-accepted and "not a finding", and named focus areas. Recorded here as a mild scope characterization. The full scope was reviewed anyway; NB-4/7/8/9 were re-judged independently and none is blocking (NB-4 and NB-7 match the frozen spec text literally; NB-8 is ledger hygiene tracked under `fu-amend-spec-ride-status-and-resume`; NB-9 is a test-portability gap listed under cannot_verify). D9 is a disclosed spec decision with a recorded HITL answer (decisions.jsonl type hitl), so it is not a compliance deviation.

## Verdict 1: spec_compliance = pass

AC walk is in the YAML block. Test evidence: see "Suites run by this review" below.

Deviations from the frozen spec (all judged reasonable, none changes a Spec-AC outcome):

1. D2: with an invalid STATE, text mode prints `ride: none (no current focus)` and JSON `ref_id: null`. D2 defines that line only for a null focus; the invalid case is unspecified. The blocker line does say `state_invalid`. This feeds NON-BLOCKING finding 1.
2. D7: with an invalid STATE, `closed` and `flushed` read `unknown` (detail `STATE invalid`); the spec table names only `not_applicable` (no focus). On a detached HEAD, `pr_open` reads `unknown` (spec names that only for `pushed`). Both are safe degrades.
3. Implementation plan: the suite-map row omits `.aai/scripts/lib/platform-adapter.mjs` and adds `.aai/system/PROFILES.yaml` and `tests/skills/lib/prompt-diet-ledger.sh`. No gap: any `lib/` change already forces `FULL_RUN reason=shared-lib` (checked with select-suites.mjs).
4. D1 imports also include `exit` from lib/cli-pipe-guard.mjs (the plan names `runMain` from the same module).

Focus checks:
- No reimplemented rule logic: the current action comes only from `buildSnapshot` + `decide(snapshot)`. Without `--confirm`, the dispatcher CLI calls `decide(snapshot, { confirm: false })`, which matches the default `opts = {}`, and on problems it emits `needsLlm(snapshot, problems)` with `rule: null, role: null`, which ride-status mirrors at line 108. D3/D4 are mappings over the dispatcher output, in spec order.
- No writes: no fs write call, no `shell: true`; child processes are `git` (argument arrays, `GIT_TERMINAL_PROMPT=0`, 20 s timeout, stdin ignored) and the adapter's `listDependents(branch, 'head')` only (gh has its own read timeout).
- Missing STATE: `state_file_missing` problem, then `needs_llm` and blocker `state_invalid`, exit 0. Git/gh failure: caught, giving `unknown`. An uncaught throw (for example in `resolvePlatform`) exits 1 through `runMain`.
- Prompt edits: SHIP INPUT calls status before ride-select, and step 5 calls the probe; SKILL_PR calls the probe immediately before `git push -u origin`; LOOP prints the status after LOOP SUMMARY. No dispatcher/decision logic is changed; the edits only skip effects that already happened, and `unknown`/`skipped` proceed as before.
- Pins: prompt-diet TEST-012 `want_growth` 64396 -> 64867 (+471, equals the ledger entry). The ride-state-handoff TEST-013 subtraction of 177 B (SHIP growth) and the TEST-2936 `base_bytes + 223` (PR growth) exclude this slice's bytes from older entries' own-growth checks, with the measured per-file deltas matching (SHIP 8383->8560, PR 32905->33128, LOOP 32171->32242). pr-preflight `laterPrGrowth +223` and `want_growth` term `+471`. hygiene-pack row-count pin 119 -> 120 for the new suite row (the stale "pin moved for aai-docs-content" wording in the message is pre-existing text, INFO).
- Test hermeticity: each case runs in its own mktemp git repo with its own identity, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `AAI_ROLE` removed, and a gh stub first on PATH for every status/probe call (validation NB-5 sentinel check). The adapter resolves `gh` from PATH (no `AAI_GH_BIN` path to escape through). Temp dirs are removed in `after`.

## Verdict 2: code_quality = pass

No BLOCKING findings. Four NON-BLOCKING findings, each with a failure scenario in the YAML block.

INFO (no gate):
- `docs/INDEX.md` gains 4 "broken references" from fixture path strings inside `tests/skills/lib/ride-status.test.mjs` (533 -> 537). Cosmetic.
- `probePushed` resolves `git rev-parse <branch>` (spec-literal); a tag with the same name would take precedence and report `not_done`, which only degrades to pushing as before.

## Warning dispositions (H6), recommended for the orchestrator to record

| # | Finding | Recommended disposition |
|---|---|---|
| NB-1 | invalid STATE reads as "no focus" for /aai-ship | (a) remediate-in-tree: SHIP INPUT also stops (prints the status, points at /aai-check-state) when `blocker.kind` is `state_invalid`. Alternative (b) follow-up P3 |
| NB-2 | resume ignores an already-closed ride | (b) promote to follow-up P3 (`fu-ship-resume-skips-closed-ride`): SHIP resumes only when probe `closed` is not `done` |
| NB-3 | ambiguous "step-5 probe" referent in SKILL_PR | (a) remediate-in-tree: say "the step-5 platform probe (pr-platform.mjs)"; a few bytes, credited to this slice's ledger entry |
| NB-4 | `--head` matches fork branches of the same name | (b) promote to follow-up P3: filter `listDependents` by head repository owner (adapter change, out of this spec's D7) |

## Suites run by this review

Each suite was run as `env -u AAI_ROLE AAI_TEST_TIMEOUT=1800 bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh` at head `3fad3552`:

- test-aai-ride-status.sh: rc=0 (TEST-3144..3158 all PASS, TEST-3157 471 B, TEST-3158 292 lines)
- test-aai-prompt-diet.sh: rc=0 (TEST-010 PASS headroom 0/2048; TEST-012 PASS 64867; TEST-2936 PASS)
- test-aai-pr-preflight.sh: rc=0
- test-aai-hygiene-pack.sh: rc=0 (row-count pin 120)

Live run in the worktree: `node .aai/scripts/ride-status.mjs` and `... probe` both exit 0 and print the six D2 lines and the five D7 lines.

## Next steps

- Orchestrator records the four NB dispositions, then proceeds with the close-out steps in the spec (fu-worktree-decision-not-ref-bound, product doc, RFC-0017 row, CHANGELOG, INDEX) and re-runs `set-code-review` with the close-out file list.
- Run `mutation-gate.mjs --spec` before close (cannot_verify item 4).
