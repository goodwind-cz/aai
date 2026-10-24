```yaml
review:
  scope: "delta b14ab7e3..296fed35 (round 3); full range 4d4566bc..296fed35 passed r1 and r2"
  spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "delta does not touch it; r2 walk stands; TEST-2601 green (26/26 node cases at HEAD in a scratch copy)" }
      - { ac: Spec-AC-02, call: compliant, citation: "delta does not touch it; TEST-2602 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "delta does not touch it; TEST-2603 green" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/expert-fetch.mjs:65-76 implements D-1 as amended (heads loop, union, empty-item drop, col-0 terminator, global blockedBroken with any [] exempt); TEST-2627/2628/2633 green; mutation-TEST-2633.txt RED; reviewer mutants for union, empty-item drop and stray-line truncation all fail TEST-2633" }
      - { ac: Spec-AC-05, call: compliant, citation: "expert-fetch.mjs:162 best-effort rmSync, original e.code still reported; TEST-2632 green and RED when the try is removed (reviewer mutant plus mutation-TEST-2632.txt)" }
      - { ac: Spec-AC-06, call: compliant, citation: "delta does not touch it; TEST-2629 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "tests/skills/test-aai-expert-fetch.sh:188-190 adds /dev/fd/0 and widens the specifier capture; mutation-TEST-2612.txt RED for import net from \"net\"" }
      - { ac: Spec-AC-08, call: compliant, citation: "launchers unchanged in delta; sh 9 lines and ps1 19 lines" }
      - { ac: Spec-AC-09, call: compliant, citation: "unchanged in delta; r2 walk stands" }
      - { ac: Spec-AC-10, call: compliant, citation: "unchanged in delta; r2 walk stands" }
      - { ac: Spec-AC-11, call: compliant, citation: "unchanged in delta; r2 walk stands" }
      - { ac: Spec-AC-12, call: compliant, citation: "RFC-0017 phase-3 row now reads 444 to 230; wc: 202+9+19 = 230" }
      - { ac: Spec-AC-13, call: compliant, citation: "unchanged in delta; r2 walk stands" }
      - { ac: Spec-AC-14, call: compliant, citation: "unchanged in delta; r2 walk stands" }
      - { ac: Spec-AC-15, call: compliant, citation: "unchanged in delta; r2 walk stands" }
      - { ac: Spec-AC-16, call: compliant, citation: "unchanged in delta; r2 walk stands" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2284,
          issue: "Amendment record (and commit message) says the new list rule makes fail-closed 'match the old ps1 regex'. It does not: the module is strictly narrower than ps1 in two shapes. The code follows frozen D-1, so the fault is in the record's wording, not the code.",
          failure_scenario: "(1) 'blocked_categories:\\n  - 08-business-product\\nallowed_tools:\\n  - 09-meta-orchestration' -> ps1 blocks 09 (match anywhere after the heading), the module does not. (2) A duplicate second heading in compact style ('blocked_categories:\\n- 09-meta-orchestration') after a good first heading -> ps1 blocks 09; the module unions nothing from it, and blockedBroken stays false because the first heading yielded an item. Both need non-canonical YAML (a dash under a different key, or a duplicate key), so nothing bites on the real registry. An owner signing the record would still be signing an overstated parity claim." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-expert-fetch.sh, line: 190,
          issue: "The commit claims TEST-2612 'collects every import specifier'. The widened regex still requires the form 'import X from \"Y\";' on a single line.",
          failure_scenario: "Prepending any of these to the module leaves TEST-2612 CLEAN (reviewer probe): 'import \"node:net\";', 'import { connect } from \"node:net\"' (no semicolon), a multi-line 'import {\\n connect } from \"node:net\";', or 'export { x } from \"node:net\";'. The spec row's own wording ('bare specifiers such as net counted too') is accurate, so no spec text is false." }
  cannot_verify:
    - { claim: "TEST-2632 'experts is a file' and 'cache is a file' shapes behave the same on Windows (rmSync/mkdirSync error codes differ: ENOTDIR vs EEXIST/EPERM)", closes_with: "the native Windows CI job running the node:test file" }
    - { claim: "the full suite sweep at 296fed35 is green", closes_with: "the validation agent's sweep currently running in the worktree (only the node:test file, 26/26, was re-run here, in a scratch copy)" }
  overall: pass
```

# Code Review r3 (delta): node-first-third-slice

- Scope: `git diff b14ab7e3..296fed35`, in the read-only worktree `/private/tmp/aai-node-first-3`, at HEAD `296fed35458c1423cfbf33016bcc8e23a4f38db8`.
- Spec: `docs/specs/SPEC-0249-spec-node-first-third-slice.md`.
- Probes ran only in `cr15-work/tree`, which is a `git archive HEAD` copy.
- Coaching note (anti-gaming contract): the dispatch suggested specific adversarial angles, such as "a category listed after another top-level key" and "list ends only at column 0". It did not pre-rate severity or exclude any area. I reviewed the whole delta anyway, and the suggested angles were checked like any other.

## What the delta does (verified against the diff)

**NB-A**
- `expert-fetch.mjs:162` wraps the `rmSync(tmp)` in `try {} catch {}`.
- The returned line still carries the original write error's `e.code`. The cleanup swallows only its own failure, so no real error is hidden.
- A directory at the `.tmp_` path is left in place rather than recursively removed. That is correct, because the directory was not ours.
- A failure of the SHA write after the rename (cache file present, SHA file absent) behaves as before; the delta does not change it.

**NB-B**
- `expert-fetch.mjs:65-76` changes the list parser:
  - It loops over every column-0 `blocked_categories:` heading.
  - It drops empty items.
  - It keeps scanning while a line starts with whitespace or `#`, or is blank, so the list ends at the first column-0 content line.
- `blockedBroken` is computed globally, and any `[]` heading exempts the whole registry. This matches frozen D-1 ("A registry whose headings yield no item at all (and none is `[]`) fails closed").

**NB-C**
- TEST-2612 now rejects `/dev/fd/0`.
- It captures any quoted specifier in single-line `import ... from '...';` statements.

**NB-D**
- `decisions.jsonl` gains one appended, unsigned contract record. It is append-only: the diff shows exactly one added line.
- Its list of text changes matches the spec diff:
  - the D-1 and D-23 cells;
  - the new Spec-AC-04 and Spec-AC-05 clauses;
  - the TEST-2612 row;
  - the new TEST-2632 and TEST-2633 rows;
  - the TEST-2628 anchor rename;
  - the RFC change from 228 to 230.
- The only inaccuracy is its parity wording (finding 1).

**Budget**
- `wc -l` gives 202 + 9 + 19 = 230, which is the budget exactly. The RFC row reads 444 to 230.

## Adversarial checks

### Over-block oracle on the real registry
I ran the old ps1 regex, `blocked_categories:[\s\S]*?- <cat>` (case-insensitive, as with `-match`), against `blockedRefusal` for all 110 keys:
- Zero differences.
- Zero blocked under either: no expert in the real registry sits in `08-` or `09-`.
- The module parses exactly `["09-meta-orchestration","08-business-product"]`.
- `experts:` at column 0 ends the list, so no later key is swallowed.

### Shape matrix: old ps1 vs the module

| Shape | ps1 | Module |
|---|---|---|
| stray indented line, then an item | blocks | blocks (fixed) |
| col-0 `#` comment inside the list | blocks | blocks |
| tab indent | blocks | blocks |
| compact single list (`- x` at column 0) | blocks | fails closed: refuses all |
| multi-line flow `[\n ...]` | no | fails closed |
| dash under a later top-level key | blocks | **no** (finding 1) |
| duplicate compact second heading | blocks | **no** (finding 1) |
| `[]` plus a second heading with only a comment | blocks (matches inside the comment) | no; I judge the comment as intent, not a defect |
| case-different category | blocks | no |
| `"x#y"` quoted | no | no |

Notes on the last two rows:
- The case-different row comes from D-1 "compare exactly", which was decided in r1/r2 and is outside the delta. It is INFO only.
- The `"x#y"` row is an existing `unq` edge and is INFO only.

### Does each fix fail its test when reverted? (reviewer mutants on the scratch copy)

| Mutant | Result |
|---|---|
| remove the try around `rmSync` | TEST-2632 RED |
| first heading only | TEST-2633 RED |
| keep empty items | TEST-2633 RED |
| stray line breaks the list | TEST-2633 RED |
| column-0 terminator removed | TEST-2604 and TEST-2633 RED |
| `&& !emptyFlow` removed | TEST-2628 RED |

- The committed mutation records for TEST-2612, TEST-2628, TEST-2632 and TEST-2633 are all `verdict: RED`.
- Their `target_sha256` equals the HEAD module's sha256, `ce54859d…af5e`.

### Line-budget squeeze
- Lines 69 and 162 now put several statements on one line, for example `try {…} catch {…} return {…}`.
- They are dense but correct. This is INFO, not a finding, because there is no failure mode.

## Findings

### 1. NON-BLOCKING (P3): the amendment's parity wording overstates (`docs/ai/decisions.jsonl:2284`)
- **Problem:** the claim "fail-closed matches the old ps1 regex" is false for two non-canonical YAML shapes (see the matrix). The code is per frozen D-1.
- **Recommended disposition:** this leaves a mildly false record, so (d) does not apply. Track it under the existing `fu-amend-spec-node-first-third-slice`, choosing either option:
  - (a) remediate in tree: append a corrective amendment record that narrows the claim to "matches ps1 for every shape a YAML reader treats as the list", before the owner signs;
  - (c) carry the correction to owner signoff under that follow-up.
- **Optional hardening:** make fail-closed per heading.

### 2. NON-BLOCKING (P3): TEST-2612's import pin is still single-line-shape only (`tests/skills/test-aai-expert-fetch.sh:190`)
- **Problem:** a side-effect import, a re-export, a multi-line import, or an import with no semicolon passes the check.
- **Why it does not bite:** no such import exists, and the spec row's wording is accurate.
- **Recommended disposition:** (d) `accepted residual: P3 assurance-strength gap in an inspection guard; no bite, spec text accurate`. A cheap in-tree alternative is to count `/\b(?:from|import)\s*['"]([^'"]+)['"]/g`.

## cannot_verify
- **Windows behaviour of the TEST-2632 shapes.** Error codes differ by platform. This closes with the native Windows CI job.
- **Full sweep at 296fed35.** It is still running in the validation agent. The only thing re-run here was the node:test file, 26/26, in a scratch copy.

## Next steps
- Overall result: **pass**.
- The orchestrator records dispositions for findings 1 and 2.
- Validation's sweep closes the second cannot_verify item.
