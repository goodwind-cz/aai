# Code Review — CHANGE-0129 / spec-scryer-mcp-and-shallow

```yaml
review:
  scope: git diff main...HEAD (branch feat/scryer-mcp-and-shallow @ a9b88be, 8 files)
  spec: docs/specs/SPEC-DRAFT-spec-scryer-mcp-and-shallow.md (frozen, ceremony_level 2, strategy hybrid)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/routines/SCRYER.routine.md:39-44 (read ladder + 4 MCP literals + never-invent, outside markers), :69-71 (merge ladder inside markers 55/72), :101-103 (Cesta nástrojů); TEST-035/001/002 PASS (own run); six CHANGE-0128 elements greppable (own grep); placeholder set = 4 tokens" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-036 PASS; own independent render of decisions-unauthorized.jsonl: merge_enabled=false, '## Merge gates'/'gh pr merge'/'merge_pull_request'/'MERGE-GATES' = 0 occurrences each; authorized render carries all three; both exit 0" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-037 PASS; own report-only render carries all five pins (is-shallow-repository x2, fetch --unshallow, RE-PROBED state, false-done, never crashes)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "own re-render diff vs tests/fixtures/routines/scryer-claude-merge.golden.txt = identical; 0 surviving '{{'; test-aai-routine.sh / layer-profiles / prompt-diet / hygiene-pack all exit 0; git diff --name-only main...HEAD contains none of PROFILES.yaml, prompt-diet-ledger.sh, test-aai-prompt-diet.sh" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-routine.sh, line: 1017,
          issue: "TEST-035's `grep -qF \"get_pull_request\" \"$outside\"` is satisfied by the longer literals `get_pull_request_status` / `get_pull_request_comments`, so the bare `get_pull_request` literal that Spec-AC-01 pins is not actually pinned.",
          failure_scenario: "MUTATION RUN (this review): deleted `get_pull_request` from the ladder sentence in a copy of the template, ran `AAI_ROUTINE_TEMPLATE=<mut> bash tests/skills/test-aai-routine.sh 035` -> PASS. A future edit dropping that rung ships a silently weaker read ladder with a green suite. Fix: grep the backticked literal or `grep -qE 'get_pull_request[^_]'`." }
      - { rank: NON-BLOCKING, file: .aai/routines/SCRYER.routine.md, line: 84,
          issue: "\"Run `docs-audit` for the health check the digest reports.\" is the only non-runnable command in a step otherwise built from exact strings. `docs-audit` is not on PATH anywhere; the real invocation is `node .aai/scripts/docs-audit.mjs --check --strict`.",
          failure_scenario: "07:00 unattended run on the cloud container (no `gh`, shallow clone — the exact host this change exists for). Agent executes `docs-audit`, gets command-not-found, and per the resilience contract correctly marks the health section degraded — so the run that this change was written to make honest silently loses its docs-audit report instead of producing it. The 'the live runs resolved it empirically' argument does not transfer: per D4 the pre-change template had no health step at all, so the wording the live runs resolved is not this wording." }
      - { rank: NON-BLOCKING, file: .aai/routines/SCRYER.routine.md, line: 101,
          issue: "**Cesta nástrojů** and **Degradováno** overlap without a precedence rule: Cesta nástrojů asks for \"which sections degraded if both rungs of a ladder were unavailable\", Degradováno asks for \"any section this run could not populate, and why\". The same degradation is instructed into two sections with no statement of which is authoritative.",
          failure_scenario: "Host with neither `gh` nor GitHub MCP: PR sections are lost. The contract tells the agent to name that loss in Cesta nástrojů AND in Degradováno; a deterministic agent duplicates it, a less literal one picks one arbitrarily and the operator's habitual scan of **Degradováno** may miss it. One-line fix: Cesta nástrojů names the path only; **Degradováno** stays the single place degraded sections are listed." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 46,
          issue: "\"Full suite: 37 tests, all green\" — the suite registers 34 test functions (`ALL_TESTS` count = 34; IDs 001-022 + 026-037). 37 is the highest test ID, not the count. The same error is in the spec's Spec-AC-04 evidence cell (\"full suite (37 tests)\", docs/specs/SPEC-DRAFT-spec-scryer-mcp-and-shallow.md:232).",
          failure_scenario: "Release-visible text. A maintainer reading \"37 tests\" in the shipped CHANGELOG looks for TEST-023/024/025 in this suite; the SPEC-0115 Test Plan deliberately allocated those IDs to other suites, and the suite header comment says so — the changelog contradicts it. Fix: \"34 tests (IDs to 037)\"." }
  cannot_verify:
    - { claim: "That a sonnet-5 cloud agent actually re-probes and SKIPs the history-based classes instead of reporting them (spec R3).",
        closes_with: "The R1 live fire: re-arm the trigger from this template and read the next digest — the 24-phantom-findings symptom is loud and immediate." }
    - { claim: "That `get_pull_request`, `get_pull_request_status`, `get_pull_request_comments` and `merge_pull_request` are the real GitHub MCP tool names (only `list_pull_requests` is field-proven; spec R2).",
        closes_with: "The R1 disposable-probe-PR run, or a tool listing from the live MCP server. The D6 degrade rule bounds a wrong name to a named degraded section." }
    - { claim: "That the MCP merge path works end-to-end (CHANGE-0129 AC-004, deliberately mapped to no Spec-AC).",
        closes_with: "The R1 probe PR merged via `merge_pull_request`, recorded in docs/ai/decisions.jsonl with the trigger id." }
    - { claim: "Downstream behavior of this template after aai-sync into a non-Czech project.",
        closes_with: "A sync into a real downstream project and one rendered prompt read end to end. See Observation O-1." }
  overall: pass
```

## Scope and independence

- Branch `feat/scryer-mcp-and-shallow` (verified with `git branch --show-current`), never switched, never pushed, no implementation file written by this reviewer.
- Diff scope: `main...HEAD`, 5 commits (`152c124..a9b88be`), 8 files. `docs/ai/EVENTS.jsonl` also carries 2 uncommitted `docs_audit` appends in the working tree (validation's own runs) — orchestrator's to commit.
- The spec's declared inline review scope lists 6 paths; the actual diff is 8, the extra two being `docs/INDEX.md` (auto-generated, regenerated by docs-audit) and `docs/ai/EVENTS.jsonl` (append-only telemetry). Both are standard generated companions, not scope creep.
- No dispatch coaching to record: the dispatch named the surface and the prior evidence but did not pre-rate severity, characterize expected findings, or exclude any area; the diff was handed off by ref, not inline.

## Verdict 1 — spec_compliance: PASS

Every Spec-AC re-verified from the artifacts, not from the validation report.

**Spec-AC-01 — compliant.** Read ladder at `.aai/routines/SCRYER.routine.md:39-44`, textually before `<!-- MERGE-GATES:START -->` (line 55), naming all four read literals plus "If a named tool is unavailable, degrade that section — never invent one." Merge ladder at lines 69-71, inside the marker pair (55/72), naming `gh pr merge` and `merge_pull_request`. Digest gains **Cesta nástrojů** (101-103). Own greps confirm the six CHANGE-0128 elements survive (`Merge is the ONLY write action`, `UNTRUSTED DATA`, `[L3]`, `CI is green`, `Shrnutí`, `merge-allowed`) and the declared placeholder set is still exactly the four tokens. TEST-035/001/002 PASS in my own suite run. Caveat: the *test's* pin on one of the four literals is weaker than the AC text implies (NB-1) — the literal is present in the template, so the AC is met; only the guard is soft.

**Spec-AC-02 — compliant.** I rendered the report-only variant myself through the real emitter and counted occurrences in the `.prompt` field: `## Merge gates` 0, `gh pr merge` 0, `merge_pull_request` 0, `MERGE-GATES` 0, `merge-allowed: false` 1, exit 0. The authorized render carries all three and `merge-allowed: true`. This is the S2 seam and it holds on rendered output, which is the only place it can hold.

**Spec-AC-03 — compliant.** All five pins present in the *report-only* render (the harder branch): `git rev-parse --is-shallow-repository` x2, `git fetch --unshallow`, `RE-PROBED state`, `false-done`, `never crashes`. TEST-037 PASS.

**Spec-AC-04 — compliant.** I re-ran the exact TEST-003 emitter invocation and diffed against the committed golden: identical. Zero surviving `{{`. Four suites exit 0 (`test-aai-routine.sh` all-pass, `test-aai-layer-profiles.sh`, `test-aai-prompt-diet.sh`, `test-aai-hygiene-pack.sh`), `spec-lint --strategy hybrid` 0 findings. `git diff --name-only main...HEAD` contains none of the three governance paths and adds no new `.aai/**` file.

Test Plan rows: TEST-035/036/037 exist, are registered in `ALL_TESTS`, and pass; TEST-001/002/003/004/005/011/012 pass as regressions; TEST-038/039 are satisfied by the two companion suites exiting 0. RED transcripts for 035/036/037 and the golden RED are present under `docs/ai/tdd/`. **No deviation from the frozen spec found** — D1 (split ladder), D2 (no new placeholder), D3 (no emitter change: `git diff main...HEAD -- .aai/scripts/` empty), D4, D5 and D7 are all honored as written. CHANGE-0129 AC-004 is correctly carried as R1 rather than claimed.

## Verdict 2 — code_quality: PASS (4 NON-BLOCKING, 0 BLOCKING)

The four findings are in the YAML block above. None gates merge. All four are remediable in one small bundle: one test line, two template lines (+ golden regeneration, which is mechanical and proven), one changelog word plus the matching spec evidence cell.

### The template as a production prompt contract

Judged as the thing a sonnet-5 agent reads unattended at 07:00, this is a good edit. The three failure modes it targets are closed with observable conditions rather than judgement calls:

- **Ladder order is conditioned on the Step 0 probe result**, not on the agent's assessment of "availability" — the one wording choice that makes the ladder deterministic. Both ladders use the same conditional shape, so the pattern is learnable from one reading.
- **"A failed `gh` probe alone no longer degrades the PR sections — only losing both rungs does"** directly overrides the paragraph immediately above it ("Any probe that fails is named in the digest as a degraded section"). Placing the override adjacent to the rule it narrows is correct; a reader who stops at line 37 gets the wrong answer, a reader who continues seven lines gets the right one. Acceptable, and the alternative (rewording line 36-37) would touch a TEST-001 pin.
- **Shallow handling branches on the re-probe, explicitly not on the fetch's exit code.** I confirmed the D5 case is real: `git fetch --unshallow` on this complete clone exits non-zero with `fatal: --unshallow on a complete repository does not make sense`. An agent branching on exit code here would conclude "repair failed → still shallow → skip everything" on a perfectly healthy clone. The contract forecloses that. This is the single best line in the change.
- **SKIP-not-report is spelled out with the class names** (`false-done`, `false-open`, `stale`) rather than gestured at, and the never-crash pointer routes back to an existing contract instead of restating it.

Step ordering after the insert: in the report-only render the flow is Step 0 → Resilience → Step 1 → Digest → Safety, which is clean. In the merge-enabled render the Merge-gates block sits between Step 0 and Step 1. Both steps self-anchor in their first sentence ("Before anything else" / "Before producing the digest"), so execution order stays derivable and nothing functional depends on it (merging does not depend on history depth). See INFO-A for the cosmetic improvement.

### Downstream-sync consequences

`.aai/routines/SCRYER.routine.md` is in `PROFILES.yaml` under the **extended** profile, so it ships to downstream projects on a full `aai-sync` and is pruned under `core`. Audit of the **new** text for anything aai-repo-specific: nothing. MCP tool names are the GitHub MCP server's, `false-done`/`false-open`/`stale` are docs-audit classes present in every AAI install, `[L3]` is an AAI-wide convention, and `docs-audit.mjs` is in the **core** profile list, so even the fix recommended in NB-2 (`node .aai/scripts/docs-audit.mjs --check --strict`) is portable — more portable than the bare `docs-audit` it would replace. Two pre-existing properties inherited from CHANGE-0128 are worth naming but are **not** findings against this scope:

- **O-1 (observation, inherited).** The provenance preamble at `.aai/routines/SCRYER.routine.md:3-7` renders verbatim into every prompt — I confirmed it is the first thing after the title in `tests/fixtures/routines/scryer-claude-merge.golden.txt`. A downstream project's 07:00 agent therefore opens with seven lines about *this* repo's `trig_01XpMxioptoJ7j32YKzzaKnR`, CHANGE-0128, and "spec residual risk R1" — none of which exist there. Harmless (it instructs no action) but it is repo-internal meta at the top of a production prompt. Untouched by this diff; recommended disposition: **follow-up ref**, not this scope.
- **O-2 (observation, inherited).** The digest is hardcoded Czech, and this change adds one more Czech literal (**Cesta nástrojů**) to that surface. This is *consistent with* the template's placeholder design rather than a violation of it: the four-token set is closed by D2 and machine-enforced by TEST-002 and the emitter's post-render check, so a `{{LANG}}` token cannot be added without an engine change (D3's explicit non-goal). Downstream non-Czech consumers get a Czech digest today; if that ever matters it is a placeholder-set change, i.e. a new scope.

### Disposition of validation's five INFOs (my call)

| Validation INFO | My call | Disposition |
|---|---|---|
| INFO-1 `docs-audit` not a runnable command | **Escalate to NON-BLOCKING (NB-2)** — the empirical "live runs resolved it" defence does not apply, because per D4 the live runs ran different, unseen health wording | remediate-in-tree |
| INFO-2 "never invent one" not restated in the merge block | Agree, INFO, **no remediation**. It is fail-closed by construction: an agent with no `gh` and no `merge_pull_request` simply cannot merge, and the Safety rules already bar the only invented alternative ("never pushes") | record only |
| INFO-3 section order Step 0 → … → Step 1 | Agree, INFO (see INFO-A) — cosmetic, but free if NB-2 is remediated in the same edit | fold into NB-2's edit, else record |
| INFO-4 singular "this run" vs "each merge" | Agree, INFO — same sentence as NB-3's fix; correct the number agreement while there | fold into NB-3's edit, else record |
| INFO-5 `--check --strict` NEEDS-TRIAGE (2) | Agree, **no action**. Both are this scope's own pre-close `probable-false-open`, the expected shape while frontmatter is `implementing` with delivery commits; `close-work-item.mjs` at the PR step resolves them and the authoritative `--gate` exits 0 | no action |

### INFO notes (never block, no disposition duty)

- **INFO-A** — moving `## Step 1 — Repository health` to just *before* `<!-- MERGE-GATES:START -->` still satisfies D1 (outside the markers, survives report-only), gives Step 0 → Step 1 adjacency in both variants, and puts the merge instruction after the health check rather than before it. Cosmetic; requires a golden regeneration, so only worth doing bundled with NB-2.
- **INFO-B** — the numbering scheme now reads as a sequence that stops at 1: there is no numbered step for the actual digest gathering or for the merge sweep. Not introduced as a defect by this change, but the insert makes the gap more visible. Either number the remaining sections or drop the "Step N" prefixes — a whole-file editorial pass, not this scope.
- **INFO-C** — **Cesta nástrojů** is placed between **Otevřené položky** and **Blokováno na člověku**, i.e. a diagnostic section in the middle of the operator-actionable ones, while the other diagnostic section (**Degradováno**) is last. For a digest whose stated goal is "triage in under a minute", the two diagnostics read better adjacent. Cosmetic.

## Docs truthfulness

The CHANGELOG entry is otherwise accurate against the diff: the merge ladder is inside the markers, the three gates are byte-unchanged, the report-only render genuinely carries none of the three literals (independently confirmed), the golden was regenerated rather than hand-patched (my re-render matches), the RED transcripts exist under `docs/ai/tdd/`, and D2/D3 are truthfully claimed. The heading form is `## [unreleased] — <title>` under the existing bare `## [unreleased]` scaffold, matching the shape `aai-release` expects. The one inaccuracy is the test count (NB-3).

## Merge fitness

The cumulative diff is clean and coherent: five commits in intake → freeze → RED → GREEN → docs order, no stray files, no engine change, no governance drift, no unrelated edits. The whole change is prose plus a machine-regenerated fixture plus three tests, which is the smallest possible blast radius for the problem. **Merge-fit as-is.** The four NON-BLOCKING findings are cheap enough that bundling them into one remediation commit before the PR is the better ride; none of them justifies holding the change.

## Next steps for the orchestrator

1. Record a disposition for each of NB-1..NB-4 (remediate-in-tree recommended for all four; decisions.jsonl or a follow-up ref otherwise) and name it in `code_review.notes`.
2. If remediating: one commit touching `tests/skills/test-aai-routine.sh` (NB-1), `.aai/routines/SCRYER.routine.md` (NB-2 + NB-4, optionally INFO-A/INFO-C in the same edit), `CHANGELOG.md` + the spec's Spec-AC-04 evidence cell (NB-3), then regenerate the golden with the TEST-003 invocation (never by hand — D7) and re-run `tests/skills/test-aai-routine.sh`.
3. Consider a follow-up ref for O-1 (provenance preamble ships into every rendered prompt, including downstream).
4. R1 remains the post-merge obligation and is correctly not claimed as delivered.
5. Stage this report with the scope's commit (SPEC-0013 H4) — it is currently untracked by design.

```yaml
subagent_result:
  scope: CHANGE-0129 / spec-scryer-mcp-and-shallow
  role: Review
  status: PASS
  started_utc: 2026-08-09T10:29:30Z
  ended_utc: 2026-08-09T10:38:10Z
  duration_seconds: 520
  evidence:
    - command: bash tests/skills/test-aai-routine.sh
      exit_code: 0
      output_snippet: "PASS: TEST-035 ... PASS: TEST-036 ... PASS: TEST-037 ... All tests passed!"
    - command: "AAI_ROUTINE_TEMPLATE=<template copy with bare get_pull_request removed> bash tests/skills/test-aai-routine.sh 035"
      exit_code: 0
      output_snippet: "PASS: TEST-035 tool ladder correctly split ... — mutation NOT caught (NB-1)"
    - command: "routine-emit.mjs --decisions decisions-unauthorized.jsonl | count merge literals in .prompt"
      exit_code: 0
      output_snippet: "merge_enabled=false; '## Merge gates' 0; 'gh pr merge' 0; 'merge_pull_request' 0; 'MERGE-GATES' 0; braces 0"
    - command: "routine-emit.mjs (TEST-003 invocation) | diff -q - golden"
      exit_code: 0
      output_snippet: "GOLDEN MATCHES"
    - command: bash tests/skills/test-aai-layer-profiles.sh; test-aai-prompt-diet.sh; test-aai-hygiene-pack.sh
      exit_code: 0
      output_snippet: "=== ALL TESTS PASSED: aai-layer-profiles === / All tests passed! / PASS: All aai-hygiene-pack tests passed"
    - command: node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-scryer-mcp-and-shallow.md --strategy hybrid
      exit_code: 0
      output_snippet: "Findings: 0 — LINT PASS: no structural findings."
  files_changed:
    - docs/ai/reviews/review-20260809T103602Z-CHANGE-0129-scryer-mcp-and-shallow.md
  blockers: []
```

Note on timing: `ended_utc` is a system-clock reading; `started_utc` is the clock-derived lower bound (the dispatch arrived immediately after validation ended at 10:28:55Z) — the review began before the first `date -u` call of this session, so the start is bounded, not estimated from model judgement.

STATE not written — subagent single-writer rule. Orchestrator to record:
`code_review.status: pass`, scope `main...HEAD`, base-ref `main`, report = this file,
notes naming the disposition chosen for each of NB-1..NB-4.
