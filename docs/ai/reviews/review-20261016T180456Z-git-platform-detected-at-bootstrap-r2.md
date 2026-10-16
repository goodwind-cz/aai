# Code Review — git-platform-detected-at-bootstrap, round 2

```yaml
review:
  scope: "delta git diff 886dfea5..HEAD (HEAD 2b4bf67d) plus regression check of git diff feca6e0b..HEAD, branch change/git-platform-detected-at-bootstrap"
  spec: docs/specs/SPEC-DRAFT-spec-git-platform-detected-at-bootstrap.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unchanged since r1; TEST-062 PASS (reviewer re-run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "unchanged since r1; TEST-063 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "platform-adapter.mjs:93 adds env only; TEST-064 PASS (NB-7 residual stands)" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged since r1; TEST-065 PASS (validation r2 bootstrap suite rc=0)" }
      - { ac: Spec-AC-05, call: compliant, citation: "platform-adapter.mjs:236 adds env only, argv unchanged; TEST-066 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged; TEST-067 PASS, TEST-068 PASS (validation r2)" }
      - { ac: Spec-AC-07, call: compliant, citation: "platform-adapter.mjs:75-85 win32 env NoDefaultCurrentDirectoryInExePath=1; TEST-069 PASS incl. new env assertions" }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged; TEST-070 PASS (validation r2 merge-cleanup suite rc=0)" }
      - { ac: Spec-AC-09, call: compliant, citation: "platform.mjs:160 env, :175-178 REFUSE line; TEST-071 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "unchanged; TEST-072 PASS (validation r2)" }
      - { ac: Spec-AC-11, call: compliant, citation: "merge-cleanup.mjs:149-151 toplevel; platform.mjs:175-178 now refuses 'the same way' (r1 deviation closed); TEST-073 subdirectory arm, TEST-071 PASS; reviewer probes main-subdir, worktree-subdir, submodule" }
      - { ac: Spec-AC-12, call: compliant, citation: "GitHub path untouched by the delta; TEST-074 PASS; full sweep 109/109 at 2b4bf67d (validation r2)" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-075 PASS (reviewer re-run): PLATFORM-CALLS clean; the new git rev-parse spawn is not a platform CLI" }
      - { ac: Spec-AC-14, call: compliant, citation: "SKILL_MERGE.prompt.md:16; ledger 882 <= 900 (wc -c 4377 confirms +440); TEST-076 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_MERGE.prompt.md, line: 16,
          issue: "Validation N1 confirmed: 'Exit 4 (completion_pending) stops: re-run it.' reads as re-run the platform.mjs merge line. Re-running the merge line is the wrong recovery once the queued completion finishes: A1 then sees state MERGED and platform.mjs refuses not_open (exit 3, 'platform: not_open PR #n is MERGED'), the Exit 3 rule says relay and stop, and step 2 cleanup never runs. Re-running /aai-merge <n> is right in both states: still active -> preflight READY reissues the line; completed -> already_merged -> step 2.",
          failure_scenario: "Azure PR with a branch policy that completes asynchronously: merge line exits 4; the agent re-runs it a minute later after the server completed the PR; it gets exit 3 not_open, relays a refusal for a PR that did merge, stops, and the worktree and branch leftovers stay until the owner notices." }
      - { rank: NON-BLOCKING, file: .aai/scripts/platform.mjs, line: 160,
          issue: "Validation N2 confirmed: completePr calls azSpawnSpec without a host-platform parameter, so off Windows the env: spec.env on the A5 write is never exercised. A mutant dropping it survives every suite on macOS/Linux CI (validation r2 mutant probe).",
          failure_scenario: "A later refactor drops env: spec.env from completePr; on Windows the one write path (the merge itself) again lets cmd.exe resolve a planted az.cmd from the ride checkout; no test reddens on any non-Windows runner." }
  cannot_verify:
    - { claim: "cmd.exe on a real Windows host honours NoDefaultCurrentDirectoryInExePath=1 for the /c az lookup, and az.cmd still runs from PATH with the argv intact",
        closes_with: "one run on Windows with azure-cli installed plus a planted az.cmd in the cwd (R4)" }
    - { claim: "Live Azure response shapes and A4 api-version (r1 carry-over)", closes_with: "fu-azure-live-proof-on-adoption" }
    - { claim: "Whether Azure refuses a completion against a stale source commit (r1 carry-over)", closes_with: "fu-azure-server-pinned-completion" }
    - { claim: "merge-cleanup, bootstrap, prompt-diet, pr-preflight, layer-profiles, hygiene-pack suites and the 109/109 full sweep at 2b4bf67d", closes_with: "validation r2 ran them (r2-suite-*.log, r2-full-sweep.log); this reviewer re-ran only the platform-adapter suite" }
  overall: pass
```

## Scope and spec

- Delta: `git diff 886dfea5..HEAD` (commit 2b4bf67d, 11 files, +62/-22). Regression check: `git diff feca6e0b..HEAD`; outside the delta nothing changed since r1 (HEAD 19b2f100 -> 886dfea5 was docs/telemetry only).
- Working tree: clean except the append-only ledgers the test wrapper writes (docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl).
- Spec: docs/specs/SPEC-DRAFT-spec-git-platform-detected-at-bootstrap.md, frozen; third measurement amendment (decisions.jsonl 2026-10-16T17:26:04Z).
- Reviewer runs: `aai-run-tests.sh bash tests/skills/test-aai-platform-adapter.sh` (all PASS, incl. TEST-069, 071, 075, 076); toplevel probes of merge-cleanup preflight with `platform: azure` recorded and a github origin, run without `--origin` from (a) a subdirectory of the main checkout, (b) a subdirectory of a linked worktree: both `REFUSE platform_mismatch recorded=azure detected=github re-record: ...` rc=3; (c) a subdirectory of a submodule whose own record is azure: the record is read at the submodule toplevel (azure adapter used, az read attempted; origin is a local path, so no mismatch, by design).
- Dispatch note (anti-gaming contract): the dispatch suggested probe areas (env leakage, REFUSE consumers, toplevel in odd layouts) and relayed validation N1/N2. No severity was pre-rated and no scope excluded; the full delta and the ride diff were reviewed.

## Remediated r1 findings

| r1 finding | Closed? | Evidence |
|---|---|---|
| NB-1 SKILL_MERGE exit 4/5 and `platform:` refusals | Closed, with a wording defect (r2 NB-1 below) | SKILL_MERGE.prompt.md:16 names exit 4, exit 5 with the direction rule, and `platform: <reason>`; matches platform.mjs:186-201. TEST-076 asserts each phrase. |
| NB-3 cmd.exe current-directory lookup | Closed in code; Windows behaviour cannot-verify | platform-adapter.mjs:83 env on the win32 spec; all three spawn sites pass it (:93, :236, platform.mjs:160). No caller passes `env` in `extra`, so the spread at :236 cannot override it. Off Windows the spec has no env, so `env: undefined` and the parent environment is inherited (TEST-069 asserts). No new env leakage: the copy is the same environment the child inherited before. The A5 site is untested off Windows (r2 NB-2). |
| NB-4 platform.mjs mismatch text | Closed | platform.mjs:175-178 prints the same `REFUSE platform_mismatch recorded=<a> detected=<b> re-record: node .aai/scripts/platform.mjs record --force` line as merge-cleanup.mjs:153 on stdout, exit 3, before createAdapter. The only consumer is SKILL_MERGE ("relayed with its command"), which now matches. Other platform.mjs refusals keep `platform: <reason>` on stderr, which SKILL_MERGE now states. |
| NB-5 record read relative to cwd | Closed | merge-cleanup.mjs:150-151 uses `git rev-parse --show-toplevel`, falling back to cwd on failure (bare repo, `.git` dir, no git). Correct in a linked worktree (worktree root) and in a submodule (submodule root). TEST-073 subdirectory arm, RED-proven in validation r2. |
| NB-2 GHE recorded as unknown | Follow-up filed | decisions.jsonl fu-platform-record-ghe-unknown (P2). |
| NB-6, NB-7 | Accepted residuals stand | Unchanged code. |

Measurement amendment: only the description cells of TEST-069, 071, 073, 076 and `frozen_sha256` changed; every edit appends an assertion clause; ID, AC, type, file and mutation columns are byte-identical. Correctly classed as measurement.

## New findings (r2)

- NB-1 (P3), SKILL_MERGE.prompt.md:16 — "re-run it" for exit 4. See the YAML block. Fix: "Exit 4 (completion_pending) stops: re-run `/aai-merge <n>`." (+12 B, ledger 882 -> 894 within the 900 cap; TEST-012 pin and pr-preflight test_008 sum move with it; TEST-076's 'Exit 4 (completion_pending)' grep still matches).
- NB-2 (P3), platform.mjs:160 — completePr env unexercised off Windows. See the YAML block.

INFO (no failure mode in this delta): platform.mjs now splits its refusals across streams (mismatch on stdout as REFUSE, others on stderr as `platform:`); SKILL_MERGE describes both, so it is consistent. When ComSpec is unset the `cmd.exe` fallback itself is resolved by libuv, which also searches the cwd; this predates r1, needs a planted binary cmd.exe, and ComSpec is set on every normal Windows host.

## Warning dispositions (H6, recommended; the orchestrator records them)

| Finding | Severity | Recommended disposition |
|---|---|---|
| r2 NB-1 (validation N1) exit 4 "re-run it" | P3 | remediate-in-tree: "re-run `/aai-merge <n>`" (fits the cap); otherwise promote to a follow-up. Not an accepted residual: the instruction tells the agent to do the wrong thing |
| r2 NB-2 (validation N2) completePr win32 env untested | P3 | accepted residual: a guard weaker than ideal with no observed bite; the env comes from the same azSpawnSpec object TEST-069 pins, and the line is visible at the single A5 call site. Cheap upgrade if wanted: let completePr take the host platform (or add a static assertion in TEST-069 that every azSpawnSpec spawn passes `env: spec.env`) |
| r1 NB-2 | P2 | follow-up fu-platform-record-ghe-unknown (recorded) |
| r1 NB-6, NB-7 | P3 | accepted residuals (r1), unchanged |

accepted residual: r2 NB-2 — completePr's win32 env on the A5 write is untestable off Windows; same spec object as the tested routes, no observed bite.

## Regression check (whole ride diff)

r1's BLOCKING-free verdict holds. The delta adds one git spawn in openPlatform (before any platform read, not a gh/az call, so D11 ordering and TEST-075 are intact), one env key on the win32 spawn spec, one stdout line in platform.mjs, and prompt/ledger/test text. The GitHub path (merge-cleanup refusal text, gh argv, legacy notice) is untouched. Validation r2 reports all eight suites rc=0, a 109/109 full sweep at 2b4bf67d, and 15/15 mutation records still reddening.

## Next steps

Both verdicts pass. Before closeout: remediate r2 NB-1 (one phrase plus the three byte-accounting pins) or file it as a follow-up, and record the r2 NB-2 accepted residual in code_review.notes.
