# Code review r3: reuse-split-corpus-cases (PR 528, Codex P2 delta)

security_relevant: false

```yaml
review:
  scope: "origin/main...cad7ffdb (delta 62abe33e..cad7ffdb, fix a91ea1d4)"
  spec: docs/specs/SPEC-0271-spec-reuse-split-corpus-cases.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-3330 PASS in r3 selected run test-20261104-040528; delta does not touch it" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-3331/3333 PASS r3; delta does not touch the partition" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-3332/3334 PASS r3" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-3333/3334 PASS r3" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-3335 (aai-suite-select, not in the delta selection; r2 run test-20261104-022113 PASS, delta does not touch suite-map.yaml or select-suites.mjs)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3336 PASS r3; live lint rc 0 with the two sources entries (.aai/scripts/suite-reuse.mjs:361-363)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3337/3276 PASS r3" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3339 PASS r3" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:85-86, :361-363, :485-488; TEST-3340/3341 PASS; validator replays RED; probes P2-P9 (escape clause verified by probe P7, not by a test: NB-2)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 486,
          issue: "admission follows only the files listed in sources, one hop; files a definition file (or any suite file) sources in turn, such as tests/skills/lib/assert-payload.sh and lib/pipe-safe.sh, are not followed",
          failure_scenario: "a branch edits only tests/skills/lib/assert-payload.sh; lint --admit --changed-since main prints ADMIT-NONE for aai-hygiene-pack and aai-hygiene-corpus (reproduced as probe P1 in a fixture). Same shape for every manifest suite on main before this ride; reuse at check time still misses, because the identity covers the traced lib (fixture halves) or the whole index (corpus halves)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 653,
          issue: "the TEST-3341 comment says lint refuses a sources path that escapes the root, but no assertion covers an absolute or .. path; the .. clause of :362 is load-bearing and unguarded",
          failure_scenario: "a refactor drops src.split('/').includes('..') from suite-reuse.mjs:362; sources [\"../repo/tests/skills/test-aa.sh\"] then resolves inside the root, exists and passes lint, and TEST-3340/3341 stay green" }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 362,
          issue: "lint accepts a sources entry that is a symlink; git diffs the link text, not the target",
          failure_scenario: "sources lists tests/skills/link.sh -> defs-aa.sh; an edit to defs-aa.sh prints ADMIT-NONE (probe P4). No symlink in the live manifest" }
  cannot_verify:
    - { claim: "PR CI (skill-suite) green at the new head with ADMIT-OFF ci and both corpus suites", closes_with: "gh pr checks 528 after push" }
    - { claim: "Windows lint behaviour for a backslash .. source path (path.join normalizes backslashes; split('/') does not see ..)", closes_with: "a Pester case; on POSIX it is rejected as missing, and admission stays conservative because git refuses a path outside the repo (status non-zero, so the suite reads as changed)" }
  overall: pass
```

## Scope

- Diff: `origin/main...cad7ffdb` (origin/main 6db05ffa). Rounds r1 and r2 reviewed up to 91e4e42a. 91e4e42a..62abe33e is the close ceremony (CHANGELOG, product doc, RFC row, generated overview/factory/catalog data, INDEX, ledgers). I read the human-written parts, and they match the delivered behaviour. This pass concentrates on the delta 62abe33e..cad7ffdb: fix a91ea1d4 and ledger commit cad7ffdb.
- Spec: SPEC-0271, status done, ceremony 2, Amendment 2 (contract, unsigned, tracked by `fu-amend-spec-reuse-split-corpus-cases`).
- Dispatch note: the dispatch listed attack angles for validation. It did not pre-rate severity or exclude areas.

## Delta reading

- `loadManifest` (`suite-reuse.mjs:85-86`) admits the `sources` key. It fails closed on `null`, objects, strings, non-string or empty elements, and nested lists (probe P7: every one gives `manifest-invalid`, rc 1). With an invalid manifest, `check` returns `RUN reason=manifest-invalid` (probe P9), so a malformed entry never reads as unchanged.
- `lintManifest` (`:361-363`) flags absolute paths, `..` segments and paths that do not exist (P7: `/etc/passwd`, `../repo/...`, `tests/../...`, `" "` and a glob all give rc 1). `[]` and `["."]` pass. `.` is conservative, because every edit admits the suite (P8).
- `entryChanged` (`:485-488`) checks the suite file plus each listed source. A source missing at the base ref counts as changed (`cat-file -e` fails; P6 admits). `./` prefixes work (P2), and a trailing-slash directory works and covers the files inside it (P3). If a definition file is renamed without a manifest update, lint fails closed (P5a). If the manifest is updated too, the entry differs and the suite is admitted (P5b).
- The only reader of `tests/skills/suite-reuse.json` is `suite-reuse.mjs` (`git grep`). `test-framework.sh` goes through the helper, `suite-reuse.Tests.ps1` writes its own fixture manifest, and no workflow or `.ps1` parses the file. The live-manifest readers TEST-3182 (node) and TEST-3275/3336 read only `live` and `note`, and they pass in the r3 run.
- INFO: `entryChanged` parses the manifest twice (`:483` and `:485`). This is cosmetic.
- INFO: the spec's Amendment 2 bullet says "see Decisions D5 note below", but the note sits right under the mapping list, not in D5. This is cosmetic.

## Findings and dispositions (H6)

- NB-1 (P3, `suite-reuse.mjs:486`): sourced libs are not followed. The gap is older than this ride and applies to all 13 entries. The new `sources` field could express it. Recommended disposition: (b) follow-up `fu-admit-sourced-lib-changed` (P3). Either list the shared libs, or have lint check that every `.`/`source` target of a manifest suite or its sources is covered.
- NB-2 (P3, `test-aai-suite-reuse.sh:653`): the escape clause is untested, and the comment overclaims coverage. The comment counts as a small false record, so disposition (d) does not apply. Recommended: (b) follow-up `fu-sources-lint-escape-untested` (P3). Add an absolute and a `..` case to TEST-3341 with a mutation row, or reword the comment.
- NB-3 (P3, `suite-reuse.mjs:362`): a symlink source is accepted. accepted residual: P3 unexercised edge, no symlink in the live manifest, no observed bite, no false record; lint could reject `lstat().isSymbolicLink()` if a symlink is ever listed.

## Next steps

Orchestrator: record NB-1 and NB-2 with `follow-ups.mjs add`, push, then run the PR sweep and wait for CI.
