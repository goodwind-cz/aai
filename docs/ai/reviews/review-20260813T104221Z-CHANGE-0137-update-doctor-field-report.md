# Code Review — CHANGE-0137 / spec-update-doctor-field-report

- Reviewer: Code Review role (single dual-verdict pass per .aai/SKILL_CODE_REVIEW.prompt.md)
- Date: 2026-08-13T10:42:21Z
- Branch: feat/update-doctor-field-report (verified via `git branch --show-current`)
- Scope: `git diff db4717a..HEAD` (commits 5308e9e, f8f583c, 5f36dd7; 17 files, +1258/−24)
- Frozen spec: docs/specs/SPEC-0124-spec-update-doctor-field-report.md (frozen at db4717a)
- Intake: docs/issues/CHANGE-0137-update-doctor-field-report.md
- Prior validation: docs/ai/validation/validation-20260813T103126Z-CHANGE-0137-update-doctor-field-report.md (PASS, one LOW F-1) — read; every claim I rely on below was independently re-executed.
- STATE.yaml: not touched (read-only reviewer; orchestrator records the verdict).

```yaml
review:
  scope: db4717a..HEAD (feat/update-doctor-field-report)
  spec: docs/specs/SPEC-0124-spec-update-doctor-field-report.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "test-aai-update.sh 17/17 exit 0 (0137-TEST-001/002/003/009); helper .aai/scripts/update-doctor-report.mjs:103-106 emitSkip = one line + exit 0; sh guard aai-update.sh:157-170 every arm ends in echo; ps1 guard aai-update.ps1:158-178 try/catch + $LASTEXITCODE; dry-run exits at aai-update.sh:120-128 / aai-update.ps1:118-125 before the postamble; independent probes: reports-dir-as-file and chmod-555 dir each yield exactly 1 named SKIP line, exit 0" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "0137-TEST-004 green; test-aai-update-check.sh exit 0; independent probes: duplicate keys first-wins both directions, CRLF off honored, BOM'd first-line key invisible to BOTH parsers identically (helper resolvePostUpdateDoctor :110-127 vs update-check resolveConfig :135-172 — same column-0/first-wins discipline)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "0137-TEST-005/006/012 green; helper imports node:fs/os/path/child_process/url only (:53-57); spawnSync timeout+SIGKILL (:203-205); timeout probe returns bounded with the named SKIP; SKIP categories pass through byte-verbatim (cmp in 0137-TEST-006)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "0137-TEST-007/008/010 green; provenance :146-155 pin -> AAI_VERSION -> UNKNOWN with placeholder tolerance :131-140; prune regex ^doctor-\\d{8}T\\d{6}Z-[a-z0-9-]+\\.md$ (:61) case-sensitive exact shape, prune :173-183; docs diffs read (USER_GUIDE.md:252-262, docs/product/aai-update.md, aai-doctor.md:60-64, CHANGELOG.md:14-36); release suite incl. TEST-024 exit 0" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "check-test-registration exit 0; layer-profiles/suite-select/hygiene-pack/prompt-diet suites all exit 0 (re-run this review); ledger +66 B re-measured (git show db4717a:SKILL_UPDATE = 2949, HEAD = 3015); TEST-012 pin -7144 green; PROFILES core x1; suite-map aai-update row names the helper" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/update-doctor-report.mjs, line: 260,
          issue: "final DOCTOR line emitted via console.log immediately followed by process.exit(0); on Windows, stdout through a PowerShell pipeline is an async pipe and process.exit can drop the unflushed line (nodejs stdout-flush footgun)",
          failure_scenario: "Windows update run: ps1 postamble '& node $helper' succeeds (exit 0), the one DOCTOR line is lost in the async pipe -> section prints with NO line and the wrapper fallback does not fire ($LASTEXITCODE -eq 0) -> silent postamble, violating the never-silence contract; POSIX unaffected (probed: piped stdout keeps the line). Severity LOW: single small write, usually flushed; sits inside RR-3's unexecuted-Windows-run residual" }
      - { rank: NON-BLOCKING, file: .aai/scripts/update-doctor-report.mjs, line: 117,
          issue: "a UTF-8 BOM at file start makes a first-line 'post_update_doctor: off' invisible (column-0 anchor does not strip \\uFEFF) — the doctor runs although the user dialed off",
          failure_scenario: "downstream user recreates docs/ai/update-config.yaml in Windows Notepad (UTF-8-with-BOM) with the key on line 1 -> off ignored, doctor runs. Mitigations: identical behavior in update-check resolveConfig (parity preserved — probed both), the seeded config starts with comment lines so the key is never on line 1, and the miss degrades to the read-only default. Fix belongs in BOTH parsers in one scope, never the helper alone" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0124-spec-update-doctor-field-report.md, line: 232,
          issue: "inline_review_scope (15 paths) omits two files the diff actually changes: docs/ai/update-config.yaml (edited per D2 — clearly intended) and docs/INDEX.md (auto-generated index refresh)",
          failure_scenario: "a scope-driven stager (SKILL_PR stages ONLY in-scope paths) drops docs/ai/update-config.yaml from the commit set -> the shipped default config lacks the documented active key; metadata slip only, both files reviewed here" }
    info:
      - ">1 MiB doctor stdout hits spawnSync's default maxBuffer -> named 'doctor spawn failed' SKIP (probed: one line, exit 0, no report). Reason string imprecise but contract intact; real doctor JSON is a few KB."
      - "Non-object-shaped JSON that is still an object (e.g. an array) passes the parse gate -> 'DOCTOR ISSUES(?)' with 'verdict undefined' in the header (probed). Only a broken doctor produces this; the payload still lands verbatim as field evidence."
      - "RR-5 acceptance is truthful for its named scenario (two sequential same-second updates: second whole-file write wins). Genuinely CONCURRENT writers have no POSIX atomicity guarantee, but concurrent same-machine updates are outside the recorded scenario."
      - "Windows timeout arm: SIGKILL on spawnSync kills the direct child only, not a process tree — a hung doctor grandchild (CAT-14 powershell) could orphan on a pathological Windows host. The helper still returns bounded; doctor's own 170 s internal bound is the second net."
      - "0137-TEST-010's CHANGELOG pin greps '^## \\[unreleased\\] .*CHANGE-0137' — rots after the release roll; identical convention in test-aai-doctor.sh:1086 and test-aai-win-fallback.sh:605, so repo-accepted lifecycle, not a defect."
  cannot_verify:
    - { claim: "an EXECUTED Windows update run of the ps1 postamble (5.1 -File exit-code behavior with a failing native command, and the stdout-flush NB-1 above)",
        closes_with: "the first real Windows-machine /aai-update after this ships — exactly the telemetry this scope creates (RR-3). pwsh probe on this host: trailing native exit 7 does NOT leak into -File exit (0)" }
    - { claim: "Windows timeout kill-tree semantics (orphaned grandchildren on a hung doctor)",
        closes_with: "a Windows-host run with a deliberately hung doctor under --timeout-ms" }
    - { claim: "a real downstream machine (esp. the WSL-functional host) producing and attaching a field report",
        closes_with: "one attached report; decisions.jsonl 2026-08-13 residual stays open until then (RR-2)" }
    - { claim: "rollout lag RR-1 (first downstream update runs the OLD postamble)",
        closes_with: "inherent to self-updating entrypoints; observed on the fleet, not locally" }
    - { claim: "pre-merge full-suite CI proof (ci-full label forcing mode=full on this PR)",
        closes_with: "the label applied at PR creation per skill-suite.yml — an orchestrator action outside this tree" }
  overall: pass
```

## Commands executed (all exit 0 unless noted)

- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-update.sh` -> 17/17 PASS, ALL TESTS PASSED
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-update-check.sh` -> 0
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-prompt-diet.sh` -> 0 (TEST-012 pin -7144 green)
- `bash tests/skills/test-aai-release.sh` -> 0 (incl. TEST-024 heading discipline; note: file mode 644, so the aai-run-tests wrapper exec path returns 126 — invoke via bash)
- `bash tests/skills/test-aai-layer-profiles.sh` / `test-aai-suite-select.sh` / `test-aai-hygiene-pack.sh` / `test-ps1-quality.sh` -> all 0
- `node .aai/scripts/check-test-registration.mjs` -> 0
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0124-spec-update-doctor-field-report.md` -> LINT PASS, 0 findings
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> 0; NEEDS-TRIAGE (2) = this scope's own expected pre-close false-open pair (flipped by close-work-item at the PR step)
- `pwsh [Parser]::ParseFile(aai-update.ps1)` -> 0 errors; byte-level `LC_ALL=C grep '[^ -~]'` over the postamble region (lines 157-180) -> ASCII clean
- Independent helper probes (scratchpad, never the repo tree): BOM config x2 parsers, duplicate keys both orders, CRLF, reports-dir-as-a-file, chmod-555 reports dir, 2 MiB doctor stdout, JSON-array output, piped-stdout line retention, pwsh -File trailing-native-exit probe — every arm: exit 0, exactly one line, contract line text exact.

## Focused-hunt answers (dispatch items)

1. **Helper failure semantics** — no path found that changes the update's exit code or emits >1 SKIP line. The helper is fully synchronous (spawnSync; no promises to reject); `emitSkip` is print-then-`process.exit(0)` so exactly one line per run by construction; ENOBUFS, dir-as-file, unwritable-dir, spawn-error, signal-with-null-status all probed to one named line + exit 0. The wrapper adds the second net (sh `|| echo` under `set -euo pipefail`; ps1 try/catch + `$LASTEXITCODE`), proven end-to-end by 0137-TEST-003's broken-helper arm. Windows-only residuals: NB-1 (flush) and the kill-tree INFO note, both inside RR-3.
2. **Retention prune** — regex is anchored, case-sensitive, exact-shape; readdir returns stored case so `Doctor-*`/uppercase-tag files never match even on case-insensitive filesystems; prefix collisions can't match (`^doctor-` + fixed digit counts + `[a-z0-9-]+` + `\.md$`). Only a user file deliberately named in the exact shape inside the runtime-ignored reports dir could ever be pruned — documented by construction. RR-5's acceptance is truthful for its stated scenario (see INFO).
3. **Config parsing** — both parsers: column-0 anchor, `\r?\n` split (CRLF safe), first-occurrence-wins (helper returns on first match; resolveConfig uses a `seen` set — probed identical). BOM behavior identical in both (NB-2). No divergence found.
4. **ps1 postamble** — parses clean, ASCII-clean byte-level, no Start-Process (0135 Handle footgun N/A), `&` invocation with explicit `$LASTEXITCODE` check; probe shows a trailing failing native command does not contaminate `-File` exit under pwsh; 5.1 execution itself remains RR-3.
5. **Bash pins** — the new tests use file-redirect + `grep`-on-file or here-strings (`<<<"$json"`); the only pipes (`basename | grep -q`, `tr | grep -q` over a ~25-line region) carry inputs far below the 64 KB cliff. No `echo | grep` pin on unbounded content.
6. **Test quality** — no vacuous asserts found: every arm pins the exact line text, line COUNT, report existence/absence, and exit code; fixtures are isolated mktemp roots; the only real-repo reads (test_015/016) are read-only pins; 0137-TEST-012 crosses the REAL doctor engine; RED log shows all 12 rows failing on the pre-change tree with named reasons (validator replayed independently; I read both logs).
7. **Governance truth** — ledger 66 B re-measured (2949 -> 3015, wc -c), not estimated; TEST-012 -7210 -> -7144 arithmetic checks (+66); CHANGELOG entry is one per-entry `## [unreleased] — <title>` heading (TEST-024 green); all five Spec-AC rows terminal `done` with evidence that re-executes (this review re-ran every named command). **F-1 disposition recommendation: promote to a decisions.jsonl entry accepting the stored RED log's legacy shape (no RED_CLASS stamp; 2 of 5 recent logs share it), citing the validator's independent RED replay as the substance — do NOT retro-edit the stored log (rewriting stored evidence is worse than recording the acceptance).**
8. **Ceremony level 1** — appropriate: no protected path (L3 list re-checked against the diff — none present), one additive helper plus guarded postambles, every AC names an executable command; the spec itself flags the file count as near L1's top and leaves raising it to the operator, which is the honest shape.

Anti-gaming note: the dispatch supplied a focus list and relayed validation's F-1 severity; treated as additive hunt targets — the full 17-file diff was reviewed and all findings/severities above are this review's own.

## Warning dispositions (H6)

- NB-1 (Windows stdout flush): recommend **remediate-in-tree** (mechanical: in `main()`, replace the final `process.exit(0)` at update-doctor-report.mjs:261 with `process.exitCode = 0; return;` so node flushes naturally; `emitSkip`'s exits can stay — same theoretical exposure, but the success line is the high-value one) — or promote to a follow-up ref folded into the RR-3 Windows-telemetry loop.
- NB-2 (BOM-blind first line, both parsers): recommend **promote-to-follow-up-ref** (one scope stripping a leading BOM in BOTH resolveConfig and resolvePostUpdateDoctor with a shared pin; fixing one side alone would create the parity drift D1 exists to prevent).
- NB-3 (inline_review_scope omissions): recommend **remediate-in-tree** (add docs/ai/update-config.yaml — and docs/INDEX.md if convention includes generated files — to the spec's inline review scope line before PR staging).

## Merge gate

- spec_compliance: **pass** (all five Spec-AC rows compliant, every claimed TEST re-executed green)
- code_quality: **pass** (zero BLOCKING; 3 NON-BLOCKING above, each with a named disposition to be recorded by the orchestrator)
- overall: **pass** — conditional on the H6 duty: each NB gets its disposition recorded (in-tree fix or decisions.jsonl/follow-up ref) before closeout, plus the F-1 decision entry. cannot_verify items are named residuals the spec already accepts (RR-1/2/3), not gaps this review can close.
