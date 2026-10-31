# Code review — provider-adapter-surfaces-closing-slice

security_relevant: true

```yaml
review:
  scope: "git diff 34b44269..08d6555f (branch feat/provider-adapter-surfaces-closing-slice); STATE code_review.scope path list"
  spec: docs/specs/SPEC-0263-spec-provider-adapter-surfaces-closing-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/skills-catalog.mjs:41-87, sync-harness-skills.mjs:411-423,556-566; TEST-3130 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "skills-catalog.mjs:31-37,72-88; TEST-3131, TEST-3132 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "SKILLS.md:54-58; live --check prints OK 42; TEST-3133 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "suite-map.yaml:609-612, PROFILES.yaml:184; caps 95/<=590; TEST-3134 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/aai-sync.sh:199; TEST-3135, TEST-3136 PASS (pwsh present)" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/spec-amend.mjs:474-508,660-669; TEST-3137 PASS (pre-merge fold-signed arm proven by TEST-3138 c, see NB-3)" }
      - { ac: Spec-AC-07, call: compliant, citation: "spec-amend.mjs:395,466-469,475,501,661-664; TEST-3138 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "a90cdce977d5 reads unsigned-tracked/open; list --strict rc 0; AUTONOMOUS_LOOP.md:102-104; TEST-3139, TEST-3140, TEST-3012, TEST-3025 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "tests/skills/test-aai-harness-shims.sh:708-727,746-773; TEST-3141 PASS (see NB-4)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 475,
          issue: "merge time is read from the CURRENT ride doc path without rename following, so a done doc moved after its merge (docs-canon archive to docs/_archive, a post-merge renumber) gets the move commit as its merge time",
          failure_scenario: "ride merged 2026-10-01 (#5); doc git-mv'd to docs/_archive on 2026-10-20; an unsigned contract amendment ts 2026-10-10 reads signed by the fold. Reproduced on a scratch repo: bucket signed. Same defect class D6 closes, fail-open direction (no regression vs baseline, which signed it too)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/skills-catalog.mjs, line: 19,
          issue: "any table line in the section whose first cell is a lowercase name-shaped token counts as a skill row, so a non-skill row is reported as orphan and deleted by --write",
          failure_scenario: "a second small table in the Quick Reference section with a lowercase header (| tier | meaning |) or a row | name | ... |: --check exits 1 'orphan row name', --write silently drops that line. Reproduced via planCatalog on a scratch SKILLS.md. No bite on the live file (header cell is 'Skill')." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-spec-amend.sh, line: 2501,
          issue: "TEST-3137's 'an earlier one stays signed' arm is satisfied by the fixture's owner overlay on the pre-merge record, not by the fold",
          failure_scenario: "a mutation that makes the fold never sign (e.g. '<= mergeTime' -> '< \"0\"') leaves TEST-3137 green; only TEST-3138 (c), the glob arm, catches it. The property is covered, but TEST-3137's pass line overstates what it proves." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-harness-shims.sh, line: 763,
          issue: "comment says 'negative control: the second follow-up closed still fails' but the code re-runs the open ledger and expects pass — a no-op control under a misleading label",
          failure_scenario: "a predicate edit that stops checking fu-shim-prompt-file-flag-unverified's status passes TEST-3141 (TEST-3014 on the live ledger would still catch it only while that item is open)." }
  cannot_verify:
    - { claim: "downstream shallow clones (actions/checkout default depth 1) now read every implied-signed record unsigned, including links.pr rides that read signed before D6; impact on downstream CI consumers of spec-amend/follow-ups",
        closes_with: "a scratch aai-sync install cloned --depth 1 running spec-amend list --strict and follow-ups list; this repo's workflows all use fetch-depth 0, and nothing-left-behind excludes fu-amend-* structurally" }
    - { claim: "record ts (local wall clock) vs GitHub committer time ordering under clock skew; rebase-merge / local ff-merge committer dates",
        closes_with: "observation on a real GitHub squash, rebase-merge and local ff merge; fixtures only cover synthetic GIT_COMMITTER_DATE" }
    - { claim: "a downstream project with its own .claude/skills wrappers running sync-harness-skills --check/--write against the sync-managed SKILLS.md (catalog section now ships in HARNESS_SKILLS.yaml)",
        closes_with: "scratch aai-sync install plus one extra wrapper: --check exits 1 'missing row', --write edits SKILLS.md which the next aai-sync flags as a local-change conflict; spec M1 states no shipped path runs the generator downstream" }
    - { claim: "ledger records with a non-Z or fractional ts compare correctly against mergeTime",
        closes_with: "all 593 live spec_amendment ts values are YYYY-MM-DDTHH:MM:SSZ and the writer is nowIso; a hand-written negative-offset ts would compare wrong (str compare), not exercised" }
  overall: pass
```

## Scope and spec

- Scope: `git diff 34b44269..HEAD` at HEAD 08d6555f in the worktree (worktree.user_decision = worktree). Working tree dirty only in `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` (orchestrator telemetry, outside review scope).
- Spec: frozen SPEC-0263-spec-provider-adapter-surfaces-closing-slice.md plus two disclosed contract amendments (2026-10-30T20:26:39Z, 22:00:47Z; both unsigned-tracked under fu-amend-provider-adapter-surface-3fe0a2).
- Dispatch note (anti-gaming contract): the dispatch named focus areas with "look for" hints and stated that close-out items (RFC-0017 row, CHANGELOG, product docs) are not findings. Recorded here; the full scope was reviewed anyway. The close-out items are absent and are close-ceremony work per spec "Close-out steps"; not graded.

## Evidence run by the reviewer

- `env -u AAI_ROLE bash tests/skills/test-aai-spec-amend.sh` -> "All aai-spec-amend tests passed", rc 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-harness-shims.sh` (pwsh present) -> "All aai-harness-shims tests passed", 23 PASS lines, no FAIL/SKIP, rc 0.
- `node .aai/scripts/sync-harness-skills.mjs --check` -> `OK: 42 skill(s) listed in the SKILLS.md Quick Reference`.
- `node .aai/scripts/spec-amend.mjs list --strict` rc 0; a90cdce977d5 = unsigned-tracked, tracker fu-amend-directed-merge-and-post-c0b910 open.
- `spec-lint --path <spec>` rc 0.
- Performance: `time node .aai/scripts/spec-amend.mjs list` on the ~600-record ledger: 0.67 s / 0.77 s real. Merge time is cached per ride doc (`info.mergeTime`); `isShallowRepo` spawns once per unsigned contract record whose ride is done (not cached) — measured cost negligible.
- ts format: all 593 spec_amendment ts values on the live ledger match `YYYY-MM-DDTHH:MM:SSZ`; mergeTime is rendered in the same shape from `%ct`, so the string comparison is sound for writer-produced records.
- Catalog probes (scratch roots, planCatalog direct): mixed LF/CRLF lines keep their own terminators after --write; second --write changes 0; file without trailing newline gains one before appended rows; duplicate rows are not reported (INFO).
- Rename probe: done doc moved after merge -> merge time = move commit (NB-1).

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | skills-catalog.mjs:41-87 (drift lines, OK line), sync-harness-skills.mjs:411-423 (catalog planned before any write; exit 2 on CatalogError), 556-566; TEST-3130 |
| Spec-AC-02 | compliant | skills-catalog.mjs:31-37 (codex cell), 72-88 (append in codepoint order, orphan drop, pipe refusal, eol preservation); TEST-3131, TEST-3132 (pipe, no-command, symlinked file, symlinked parent) |
| Spec-AC-03 | compliant | SKILLS.md:54-58; TEST-3133 (42 once each, 37 baseline rows byte-identical, rows equal scratch --write) |
| Spec-AC-04 | compliant | suite-map.yaml, PROFILES.yaml core; lib 95 lines; TEST-3134 |
| Spec-AC-05 | compliant | aai-sync.sh:199 `{ sub(/\r$/, "") }`; ps1 unchanged (D4); TEST-3135 (e)(f), TEST-3136 parity |
| Spec-AC-06 | compliant | spec-amend.mjs:666 `str(rec.ts) <= mergeTime`; TEST-3137 (post-merge unsigned-tracked/open in --json, text list, follow-ups.mjs; --strict 0) |
| Spec-AC-07 | compliant | spec-amend.mjs:501 shallow guard before any git log, 661-664 note once; `--literal-pathspecs` at 395 and 475; TEST-3138 (a)(b)(b2)(c) |
| Spec-AC-08 | compliant | live ledger: only a90cdce977d5 changes among 34b44269 records (TEST-3139 incl. later-classify arm); AUTONOMOUS_LOOP.md:102-104; TEST-3140, TEST-3025, TEST-3012 |
| Spec-AC-09 | compliant | followup_problems (harness-shims.sh:708-727); TEST-3141 three ledgers pass/pass/fail; D8 record on ledger |

Deviations from the frozen spec (none change behaviour):
- Implementation plan asked to "update the header comment that describes the implied fold" (spec-amend.mjs:644-649) and the BASE_DOCS_CACHE entry comment (378-381); neither mentions the merge-time binding. INFO.
- Plan item "aai-sync.sh: a one-rule awk change plus a header comment line": no comment line added. INFO.
- `checkRideMerged` (exported, spec-amend.mjs:510, 2247) now returns the unbound reading; no in-repo consumer, but its name suggests the signing predicate. INFO.
- TEST-3022 totals re-pinned 400/2 -> 399/3 and merge-cleanup test exempts a90cdce977d5: both are the measured D6 consequence (M3), consistent.

## Findings

### NB-1 — merge time ignores renames after merge (spec-amend.mjs:475)
`git log --first-parent -- <current path>` without rename following makes the oldest commit at the current path the merge time. When a done doc is moved after the merge (docs-canon Phase 2 archives originals into docs/_archive; post-merge renumbering), every amendment written between the real merge and the move reads implied-signed. Reproduced (scratch repo: merge 10-01, move 10-20, record 10-10 -> `signed`). Allocator DRAFT -> numbered at squash is unaffected (that commit is the merge). The spec's D6 definition is implemented literally, so this is a gap in the definition, not non-compliance; baseline signed these too.
Recommended disposition: promote to follow-up ref (P3) — e.g. `fu-merge-time-ignores-doc-rename`; fix candidate: stop at the commit where the path was added by rename (`--diff-filter`/`--name-status`) and continue on the old path, or refuse (no fold) when the oldest commit is a rename-add of a doc that already read done.

### NB-2 — non-skill table rows count as orphans (skills-catalog.mjs:19, 62)
NAME_RE accepts any lowercase token, so a lowercase first cell that is not a skill becomes an orphan row and `--write` deletes it. No bite on the live file.
Recommended disposition: (d) accepted residual (P3 assurance edge, no observed bite, no false record) or remediate-in-tree by restricting orphans to cells shaped like the wrapper set (e.g. `aai-` prefix or an existing `.claude/skills` naming rule).

### NB-3 — TEST-3137 pre-merge arm is carried by the overlay (test-aai-spec-amend.sh:2501)
The fixture's classifies_record overlay signs the pre-merge record, so "pre=signed" holds without the fold. TEST-3138 (c) runs without the overlay and proves the fold-signs-earlier property, so coverage exists; the TEST-3137 pass line overstates.
Recommended disposition: remediate-in-tree (assert `classified_by` null on a no-overlay read in TEST-3137) or (d) accepted residual: "fold-signs-pre-merge proven by TEST-3138 (c)".

### NB-4 — TEST-3141 mislabelled no-op control (test-aai-harness-shims.sh:763-764)
The "second follow-up closed still fails" control re-runs the open ledger. Remediate-in-tree: build a fourth ledger closing fu-shim-prompt-file-flag-unverified and expect a non-empty problem list, or delete the comment and line.

### INFO
- Duplicate Quick Reference rows are not reported by --check (Map keeps the last); D1 does not require it, TEST-3133 checks the live tree once.
- `isShallowRepo` result is not cached; negligible at current ledger size.
- Record ts compared as strings: correct for nowIso output; a hand-written negative-offset ts would compare wrong (fail-open). Listed under cannot_verify.

## cannot_verify
See the YAML block: downstream shallow-clone behaviour change, clock skew and non-squash merge committer dates, downstream projects with their own wrappers vs the shipped catalog section, non-Z ts values.

## Warning dispositions (H6) — recommended, orchestrator records
- NB-1: promote to follow-up (P3).
- NB-2: accepted residual (P3) or remediate.
- NB-3: remediate-in-tree or accepted residual citing TEST-3138 (c).
- NB-4: remediate-in-tree.

## Next steps
Record NB dispositions, then close-out per spec (RFC-0017 row, CHANGELOG with the shallow-clone caveat, follow-up closures), then aai-pr.
