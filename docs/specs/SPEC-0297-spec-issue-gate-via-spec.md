---
id: spec-issue-gate-via-spec
type: spec
number: 297
status: done
mutation_gate: v1
frozen_sha256: 28df68c4d3f246b509cad030a24d55d4e571d4fb158813455d99b11f482eb1b9
ceremony_level: 2
links:
  requirement: issue-gate-via-spec
  rfc: null
  pr:
    - TBD
  commits: []
---

# The docs close gate reads an intake doc's verdict from its linked spec

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0120-issue-gate-via-spec.md (Codex P1 on
  PR #563, thread `discussion_r4588285498`).
- Prior scopes this one builds on (closed, not edited): SPEC-0011 (the close
  gate G1 and the staged-blob hook gate G5), CHANGE-0012 D2 (the two-pass id
  resolver `resolveDocById`), the rollout rollup (`closeoutCandidatesFor` /
  `parentProgressFor`, forward `links.spec` plus reverse `links.requirement` /
  `links.rfc`).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: a behaviour change in a gate predicate that downstream projects
  can set to enforce. Every new behaviour can be seen failing on the
  unchanged tree (the intake fixtures all exit 1 with `missing AC Status
  table`, the hook never gates a `docs/issues/` flip), so each AC gets a RED
  observation and a mutation record. The strategy was not chosen at intake
  (autopilot); Planning chose it.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the main checkout is shared with other sessions and
  holds uncommitted files of other rides; the owner placed this ride in its
  own worktree.
- User decision: worktree (owner-directed, recorded in STATE)
- Base ref: origin/main at c1034b24
- Worktree branch/path: fix/issue-gate-via-spec at
  /Users/ales/Projects/aai-worktrees/issue-gate-via-spec
- Review required: true
- Review scope (explicit paths): .aai/scripts/lib/docs-audit-core.mjs;
  .aai/scripts/docs-audit.mjs; .aai/templates/git-hooks/pre-commit-index.sh;
  tests/skills/test-aai-docs-audit.sh; CHANGELOG.md;
  docs/product/docs-close-gate.md;
  docs/issues/ISSUE-0120-issue-gate-via-spec.md;
  docs/specs/SPEC-0297-spec-issue-gate-via-spec.md.

## Ceremony

Ceremony level 2. No file in `protected_paths_l3` of docs/ai/docs-audit.yaml
is touched: the close-gate hook block lives in
`.aai/templates/git-hooks/pre-commit-index.sh`, not in the protected
`pre-commit-checks.sh`/`.ps1`; `docs-audit.mjs`, its core library and
`close-work-item.mjs` are not listed. It is not L1: it changes a shared
library predicate and a shipped git hook template, two surfaces.

Companion obligations: no `.aai/*.prompt.md` or `.aai/AGENTS.md` byte
changes (the AGENTS.md rule "before flipping a governed doc to done, run
`--gate`" stays true as written), no new `.aai/**` file. Neither applies.

## Decisions

### D1. Which docs gate through a linked spec

A doc gates through its linked specs when both hold:

1. its frontmatter `type` is not `spec` (case-insensitive; an absent type is
   not `spec`), and
2. it carries no AC table of its own: the existing gate would report
   `missing AC Status table` (or, at ceremony 0/1, the lean
   `missing AC table (...)` reason).

A table counts as the doc's own as soon as it declares a `Spec-AC-NN` row,
even when the parser cannot read that row (a raw or escaped pipe, a cell
count off): such a doc keeps the missing-table failure and never delegates
(amended after review round 2, B1). Amended after review round 3 (B1): a
row counts as declared when a `| Spec-AC-NN` table line sits under a
`## Acceptance Criteria` or `## Acceptance Criteria Status` heading,
whatever the table's header columns (no Review-By column, a lean table at
level 2, a `State` column) and whether or not the parsers accept its shape;
fenced code blocks and tables under other headings do not count. Amended
after round-4 validation (NB-F1, NB-F2): the `## Acceptance Criteria Status`
heading may carry a suffix, as `parseAcTable` reads it, and the section runs
to the next `## ` heading; the fence skip is pinned by a test.

Every other doc gates exactly as today. A spec never delegates. A non-spec
doc that has its own table is gated on that table only, even when a spec is
linked to it. Keying on "not a spec" rather than on a list of intake types
follows the intake assumption: `close-work-item.mjs` flips any resolved doc
type, so a list would drift.

### D2. Which specs are linked

The linked specs of a doc P are the union of:

- forward: each id in P's `links.spec` (scalar or list), resolved with the
  same two-pass resolver `--gate` uses (frontmatter id first, then display
  id). An id that resolves to zero or several scanned docs, or to a doc whose
  type is not `spec`, is a gate reason of its own (it fails the gate), named
  with the id;
- forward by path (amended after review round 1, NB2): a `links.spec` value
  equal to a scanned doc's repository path (for example
  `docs/specs/SPEC-0103-spec-platform-portable-pr.md`, optionally with a
  leading `./`) names that doc directly; three closed change docs in this
  repository link their spec that way;
- reverse: every scanned doc of type `spec` whose `links.requirement` or
  `links.rfc` names P by its frontmatter id or by its display id (for
  example `ISSUE-0118`).

The reverse test is the one `closeoutCandidatesFor` and `parentProgressFor`
already apply; it moves into one exported helper, `linksBackTo(fm,
parentRefs)`, which all three callers use. The scan and the two-pass match
move out of `resolveDocById` into `scanGateEntries(root)` and
`matchDocId(entries, id)`, so `--gate`, `--ac-flip-check` and the linked-spec
lookup read one resolver. `resolveDocById`'s reason strings stay
byte-identical.

### D3. The verdict and what it prints

- At least one linked spec: every linked spec is gated with the unchanged
  spec gate. The doc passes when every linked spec passes, every forward link
  resolves, and the doc's own reasons other than the missing table (for
  example an invalid `ceremony_level`) are empty. Each spec reason is printed
  prefixed with the spec's display id (`SPEC-0295: Spec-AC-01 is
  non-terminal ...`).
- PASS prints `GATE PASS via linked spec(s) <ID> (<path>)[, ...]: ...`.
- FAIL keeps the existing header `GATE FAIL — the AC Status table is not
  reconciled:` and its reason lines, then adds `Decided by linked spec(s):
  <ID> pass|fail (<path>)[, ...]` whenever at least one spec was gated.
- No linked spec: the gate fails with the existing missing-table reason plus
  `no linked spec: ...`, which names the ids a spec would have to link
  (`links.requirement` or `links.rfc`) and the `links.spec` alternative.

Exit codes are unchanged: 0 pass, 1 fail, 2 unresolvable id or file.

### D4. `--gate-file` and the pre-commit hook

`--gate-file <path>` applies D1 to D3 to the file's content. The doc's
identity is its frontmatter `id`; when exactly one scanned doc carries the
same `id`, that doc's display id is added, so a spec linking back by display
id is found even when the gated file is a temporary copy (the hook's staged
blob). Linked specs are read from the working tree, not from the index: in a
close commit the spec is staged in the same commit and is gated by its own
staged blob in the same hook loop.

The hook's close-gate block (`.aai/templates/git-hooks/pre-commit-index.sh`)
gated only staged `docs/specs/*.md` done-flips, so the intake doc that
`close-work-item.mjs --ref` flips in the same close commit was never gated
there. It now gates a staged done-flip under `docs/issues/`, `docs/rfc/`,
`docs/specs/` and `docs/requirements/`. Amended after review round 1 (NB1):
`docs/releases/` is not gated, because a release plan carries no acceptance
table and no spec links to it, so under enforce it could never be closed. The enforce/report-only dial, the
staged-blob materialisation and the messages are unchanged. Under the
default report-only dial this adds warnings only; under `close_gate:
enforce` it blocks a done-flip of an intake doc that has neither a table nor
a linked spec, which is the documented gate's verdict.

`close-work-item.mjs` does not call the close gate at all (it self-verifies
with `runAudit`), so there is no call site to align there; it is not edited
(its hash pin covers four suites). Recorded as follow-up
`fu-gate-not-called-by-close-item` (P3), not silently dropped.

### D5. An unfinished Rollout Status keeps its own reason (amendment)

Added after review round 1 (B1). A doc that gates through its linked specs
and whose own body has a `## Rollout Status` table with a phase row not
`done` (the existing `hasUnfinishedRolloutPhases`, the predicate
`closeoutCandidatesFor` already uses to refuse closing such a parent) keeps
the reason `Rollout Status declares an unfinished phase: ...`, so an
umbrella RFC or PRD is not passed because the specs written so far pass.
The linked specs are still gated and reported in the Decided-by line.

## Acceptance Criteria Mapping

- Intake Expected (1) maps to Spec-AC-01, Spec-AC-02, Spec-AC-07.
- Intake Expected (2) maps to Spec-AC-03.
- Intake Expected (3) maps to Spec-AC-04.
- Intake Expected (4) maps to Spec-AC-05, Spec-AC-06.
- Consumer-visible change (vendored script and hook template) maps to
  Spec-AC-08.
- Review round 1 (B1, NB2, NB3) maps to Spec-AC-09 and Spec-AC-10
  (amendment).
- Review round 2 (B1, NB2) maps to Spec-AC-11 and the docs/releases/ arm of
  TEST-3806 (amendment).
- Review round 3 (B1) maps to Spec-AC-12 (amendment).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN docs-audit.mjs --gate runs on an issue doc with no AC table of its own whose frontmatter id is named by the links.requirement of one spec with a reconciled AC Status table, it SHALL exit 0 and print a line starting GATE PASS via linked spec(s) that names the spec display id and its path; WHEN that spec is the only link and names the issue by its display id instead, the result SHALL be the same | done | TEST-3801 green docs/ai/tdd/issue-gate-via-spec/green-test-3801.log, RED docs/ai/tdd/issue-gate-via-spec/red-test-3801.log, mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3801.txt | — | D1, D2, D3 |
| Spec-AC-02 | WHEN an issue doc with no AC table of its own is linked to two specs, one reconciled and one with a non-terminal row, --gate SHALL exit 1, print the reason line prefixed with the failing spec display id and naming its Spec-AC row, and print a Decided by linked spec(s) line naming the failing spec with fail and the other with pass | done | TEST-3802 green docs/ai/tdd/issue-gate-via-spec/green-test-3802.log, RED docs/ai/tdd/issue-gate-via-spec/red-test-3802.log, mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3802.txt | — | D3 |
| Spec-AC-03 | WHEN an issue doc has no AC table of its own and no spec links to it, --gate SHALL exit 1 printing missing AC Status table and a reason starting no linked spec that names its frontmatter id; WHEN its links.spec names an id that resolves to no scanned doc, --gate SHALL exit 1 naming that id; WHEN its links.spec names a change doc, --gate SHALL exit 1 naming that id and not a spec | done | TEST-3803 green docs/ai/tdd/issue-gate-via-spec/green-test-3803.log, RED docs/ai/tdd/issue-gate-via-spec/red-test-3803.log, mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3803.txt | — | D2, D3 |
| Spec-AC-04 | WHEN a spec with no AC table is named by another reconciled spec's links.rfc, --gate on it SHALL still exit 1 with missing AC Status table and print no via line; WHEN a change doc carries its own AC Status table with a non-terminal row and a reconciled spec links to it, --gate SHALL exit 1 naming that row and print no Decided by line | done | TEST-3804 green docs/ai/tdd/issue-gate-via-spec/green-test-3804.log, no pre-change RED (pins unchanged behaviour; control green docs/ai/tdd/issue-gate-via-spec/red-test-3804-control-green.log), mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3804.txt | — | D1 |
| Spec-AC-05 | WHEN docs-audit.mjs --gate-file runs on a copy of an issue doc placed outside docs/ whose frontmatter id equals a scanned issue doc's id, and the only linked spec names that issue by its display id, it SHALL exit 0 with the GATE PASS via linked spec(s) line naming the spec; the same copy with the spec link removed SHALL exit 1 with no linked spec | done | TEST-3805 green docs/ai/tdd/issue-gate-via-spec/green-test-3805.log, RED docs/ai/tdd/issue-gate-via-spec/red-test-3805.log, mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3805.txt | — | D4 |
| Spec-AC-06 | WHEN the installed pre-commit hook sees a staged done-flip of a docs/issues/ doc with no AC table and no linked spec, under close_gate enforce it SHALL abort the commit naming the doc id and under close_gate report-only it SHALL commit and print a close-gate warning; WHEN a reconciled spec links to the flipped issue doc, under enforce the commit SHALL succeed | done | TEST-3806 green docs/ai/tdd/issue-gate-via-spec/green-test-3806.log, RED docs/ai/tdd/issue-gate-via-spec/red-test-3806.log, mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3806.txt | — | D4 |
| Spec-AC-07 | WHEN the real ISSUE-0115, ISSUE-0116, ISSUE-0117, ISSUE-0118 and SPEC-0292 to SPEC-0295 files are copied into a fixture docs tree, --gate on each issue display id SHALL exit 0 with a GATE PASS via linked spec(s) line naming SPEC-0292, SPEC-0293, SPEC-0294 and SPEC-0295 respectively | done | TEST-3807 green docs/ai/tdd/issue-gate-via-spec/green-test-3807.log, RED docs/ai/tdd/issue-gate-via-spec/red-test-3807.log, mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3807.txt | — | Owner measurement on the real corpus; the live-tree run is recorded in Verification |
| Spec-AC-08 | CHANGELOG.md SHALL hold exactly one heading in the form unreleased or a rolled vYYYY.MM.DD, then an em dash and fix: the docs close gate reads an intake doc's verdict from its linked spec; docs/product/docs-close-gate.md SHALL state that an intake doc with no table of its own gates through its linked spec and that the pre-commit hook gates done-flips under docs/issues/ | done | TEST-3808 green docs/ai/tdd/issue-gate-via-spec/green-test-3808.log, RED docs/ai/tdd/issue-gate-via-spec/red-test-3808.log, mutation docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3808.txt | — | Consumer-visible; the library and the hook template ship downstream |
| Spec-AC-09 | WHEN an rfc doc with no AC table whose Rollout Status table has a phase row with status planned is named by one reconciled spec's links.rfc, --gate SHALL exit 1 with a reason starting Rollout Status declares an unfinished phase and a Decided by linked spec(s) line naming that spec with pass; the same doc with every phase done SHALL exit 0 | done | TEST-3809 green docs/ai/tdd/issue-gate-via-spec/green-test-3809.log, RED observation is its mutation record docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3809.txt (written after the round-1 code existed) | — | D5; amendment after review round 1 (B1) |
| Spec-AC-10 | WHEN a change doc's links.spec is a spec's repository path, --gate SHALL exit 0 naming that spec; WHEN a ceremony_level 1 change doc with a Ceremony justification line and no AC table is linked by a reconciled spec, --gate SHALL exit 0; WHEN the same doc lacks the justification line, --gate SHALL exit 1 naming the justification and reporting the spec with pass | done | TEST-3810 green docs/ai/tdd/issue-gate-via-spec/green-test-3810.log, RED observation is its mutation record docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3810.txt (written after the round-1 code existed) | — | D2 amended, D3; amendment after review round 1 (NB2, NB3) |
| Spec-AC-11 | WHEN a change doc's own Acceptance Criteria Status table, or its ceremony 1 lean Acceptance Criteria table, declares a Spec-AC row that does not parse because of an escaped pipe in a cell, and a reconciled spec links to it, --gate SHALL exit 1 and print neither a via line nor a Decided by line | done | TEST-3811 green docs/ai/tdd/issue-gate-via-spec/green-test-3811.log, RED observation is its mutation record docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3811.txt (written after the round-2 code existed) | — | D1 amended; amendment after review round 2 (B1) |
| Spec-AC-12 | WHEN a change doc linked by a reconciled spec carries its own Spec-AC row with status implementing under an Acceptance Criteria Status heading whose table has no Review-By column, or under an Acceptance Criteria heading at implicit level 2, or under an Acceptance Criteria heading at level 1 whose table names its status column State, --gate SHALL exit 1 and print neither a via line nor a Decided by line; the same SHALL hold for an Acceptance Criteria Status heading with a suffix whose every row fails to parse; WHEN the only Spec-AC row sits under another heading or inside a fenced block, --gate SHALL exit 0 via the linked spec | done | TEST-3812 green docs/ai/tdd/issue-gate-via-spec/green-test-3812.log, RED observation is its mutation record docs/ai/tdd/spec-issue-gate-via-spec/mutation-TEST-3812.txt (written after the round-3 code existed) | — | D1 amended; amendment after review round 3 (B1) |

## Implementation plan

Components:
- `.aai/scripts/lib/docs-audit-core.mjs`:
  - `linksBackTo(fm, parentRefs)` (exported), used by
    `closeoutCandidatesFor`, `parentProgressFor` and the new lookup;
  - `gateContent` also returns `missingTable` (the missing-table reason
    string, or null);
  - `scanGateEntries(root)` and `matchDocId(entries, id)` extracted from
    `resolveDocById`, which also returns `entries`;
  - `gateViaLinkedSpecs(entries, parent, own, extraMethods)` returning
    `{ ok, reasons, via }`;
  - `gateDoc` and `gateFile` call it under D1.
- `.aai/scripts/docs-audit.mjs` `emitGate`: the via PASS line and the
  Decided-by line (D3).
- `.aai/templates/git-hooks/pre-commit-index.sh`: the staged-path filter of
  the close-gate block (D4).

Edge cases: a list-valued `links.requirement`; a spec that links back by
display id; duplicate forward and reverse link to the same spec (gated
once, keyed by path); a DRAFT spec with no display id (named by its
frontmatter id); a gated file with no frontmatter `id` (only `links.spec`
can link it; disclosed as R1).

Seams:
- S1, docs-audit gate to the hook: the hook materialises the staged blob and
  calls `--gate-file`; TEST-3806 commits through the real installed hook.
- S2, the real corpus: TEST-3807 gates copies of the real issue and spec
  files, not synthetic ones.
- S3, the reverse-link helper shared with the closeout and rollup reports:
  the existing closeout and rollout tests in the docs-audit suite cover the
  refactor; the full sweep covers the rest.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3801 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | iso repo with ISSUE-5801 (no table, id issue-5801) and SPEC-5801 (reconciled, links.requirement issue-5801): --gate ISSUE-5801 exit 0, PASS via line names SPEC-5801 and its path; second pair linked by display id ISSUE-5802 passes the same way | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/if \(own\.missingTable && docTypeOf\(res\.entry\.fm\) !== 'spec'\)/if (false)/` stops the delegation and the case must fail | green |
| TEST-3802 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | ISSUE-5803 linked by two specs, SPEC-5803 reconciled and SPEC-5804 with an implementing row: exit 1, reason line SPEC-5804: Spec-AC-01 is non-terminal, Decided by line names SPEC-5804 fail and SPEC-5803 pass | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/for \(const r of sres\.reasons\)/for (const r of [])/` drops the spec reasons, the gate passes and the case must fail | green |
| TEST-3803 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | ISSUE-5805 with no table and no link: exit 1, missing AC Status table and no linked spec naming issue-5805; ISSUE-5806 with links.spec spec-missing: exit 1 naming spec-missing; ISSUE-5807 with links.spec naming CHANGE-5807: exit 1 naming it and not a spec | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/if \(linked\.size === 0\) \{/if (linked.size < 0) {/` lets the unlinked doc through and the case must fail | green |
| TEST-3804 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | SPEC-5808 with no table named by reconciled SPEC-5809 links.rfc: exit 1, missing AC Status table, no via line; CHANGE-5810 with its own implementing row and a reconciled spec linking to it: exit 1 naming the row, no Decided by line | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/own\.missingTable && docTypeOf\(res\.entry\.fm\) !== 'spec'/own.missingTable/` lets the spec delegate and the case must fail | green |
| TEST-3805 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | copy of ISSUE-5811 (id issue-5811) placed outside docs/; SPEC-5811 links.requirement ISSUE-5811: --gate-file on the copy exit 0 with the via line; spec link removed: exit 1, no linked spec | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/fileIds: self\.length === 1 \? self\[0\]\.fileIds : \[\]/fileIds: []/` drops the display id and the case must fail | green |
| TEST-3806 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | hook repo: ISSUE-5812 (no table, no spec) staged draft to done under enforce: commit aborts naming issue-5812; under report-only: commits with a close-gate warning; ISSUE-5813 with reconciled SPEC-5813 linking back flipped under enforce: commit succeeds; REL-5815 under docs/releases/ flipped under enforce commits ungated (amendment after review round 2) | target `.aai/templates/git-hooks/pre-commit-index.sh`; `sed:s/grep -E '\^docs\/\(issues/grep -E '^docs\/(xissues/` stops gating docs/issues and the case must fail | green |
| TEST-3807 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | copy the real ISSUE-0115 to ISSUE-0118 and SPEC-0292 to SPEC-0295 into an iso repo; --gate ISSUE-0115 to ISSUE-0118 each exit 0 with the via line naming SPEC-0292 to SPEC-0295 | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/if \(docTypeOf\(e\.fm\) === 'spec' && linksBackTo\(e\.fm, parentRefs\)\)/if (false)/` stops the reverse lookup and the case must fail | green |
| TEST-3808 | Spec-AC-08 | unit | tests/skills/test-aai-docs-audit.sh | CHANGELOG.md holds exactly one unreleased or vYYYY.MM.DD heading with an em dash and fix: the docs close gate reads an intake doc's verdict from its linked spec; docs/product/docs-close-gate.md names linked spec and docs/issues/ | target `CHANGELOG.md`; `sed:s/— fix: the docs close gate reads an intake doc's verdict/— fix: x reads/` removes the named heading and the case must fail | green |
| TEST-3809 | Spec-AC-09 | integration | tests/skills/test-aai-docs-audit.sh | RFC-5809 with rollout phase 2 planned and reconciled SPEC-5809 links.rfc rfc-5809: exit 1, Rollout Status reason, Decided by SPEC-5809 pass; control RFC-5810 all phases done passes via SPEC-5810 | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/if \(hasUnfinishedRolloutPhases\(parent\.content\)\) \{/if (false) {/` drops the rollout reason and the case must fail | green |
| TEST-3810 | Spec-AC-10 | integration | tests/skills/test-aai-docs-audit.sh | CHANGE-5811 links.spec docs/specs/SPEC-5811-by-path.md passes via SPEC-5811; ceremony 1 CHANGE-5812 with justification passes via SPEC-5812; CHANGE-5813 without justification fails naming it with Decided by SPEC-5813 pass | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/const byPath = entries\.filter/const byPath = [].filter/` stops the path lookup and the case must fail | green |
| TEST-3811 | Spec-AC-11 | integration | tests/skills/test-aai-docs-audit.sh | CHANGE-5816 canonical table and CHANGE-5817 lean table each with one escaped-pipe implementing row, each linked by a reconciled spec: exit 1, no via line, no Decided by line | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/if \(!declaresOwnAcRows\(content\)\) missingTable = 'missing AC Status table'/missingTable = 'missing AC Status table'/` lets the canonical doc delegate (cell re-targeted after review round 3) and the case must fail | green |
| TEST-3812 | Spec-AC-12 | integration | tests/skills/test-aai-docs-audit.sh | CHANGE-5818 Status table without Review-By, CHANGE-5819 lean heading at L2, CHANGE-5820 L1 table with a State column, CHANGE-5822 suffixed Status heading with an escaped-pipe row, each with an implementing own row and a reconciled linked spec: exit 1, no via line, no Decided by line; controls CHANGE-5821 (example table under another heading) and CHANGE-5823 (row in a fence under the AC heading) pass via their specs | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/function declaresOwnAcRows\(content\) \{/function declaresOwnAcRows(content) { return false;/` stops counting declared rows and the case must fail | green |

TDD batches (about three ACs each): A = Spec-AC-01, 02, 03; B = Spec-AC-04,
05, 07; C = Spec-AC-06, 08; D (review round 1 remediation) = Spec-AC-09, 10;
E (review round 2 remediation) = Spec-AC-11; F (review round 3
remediation) = Spec-AC-12.

## Verification

All runs: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`
from the worktree root; new test code must pass under the suite's
`set -euo pipefail` (no `printf | grep -q`, no bare `rc=$?`).

1. RED before GREEN: `docs/ai/tdd/issue-gate-via-spec/red-*.log` and
   `green-*.log`. Expected RED on the unchanged tree: TEST-3801, 3802, 3805,
   3807 exit 1 with `missing AC Status table` and no via line; TEST-3803
   lacks the `no linked spec` reason; TEST-3804 has no RED of its own (it
   pins behaviour that does not change; its RED observation is its mutation
   record); TEST-3806 the enforce flip of the issue doc commits; TEST-3808
   the heading is missing.
2. `bash tests/skills/test-aai-docs-audit.sh` exits 0, and so do the suites
   that call the gate: `test-aai-ceremony-levels.sh`,
   `test-aai-git-hook-templates.sh`, `test-aai-hygiene-pack.sh`.
3. Mutation records for every Test Plan row under
   `docs/ai/tdd/spec-issue-gate-via-spec/` via `mutation-run.mjs`.
4. Live tree measurement, recorded in the validation report: `--gate
   ISSUE-0115` to `ISSUE-0118` exit 0 naming SPEC-0292 to SPEC-0295; the
   count of `status: done` docs under `docs/issues/` that pass `--gate-file`
   (5 of 349 on c1034b24) after the change.
5. `node .aai/scripts/spec-amend.mjs list --strict` exits 0 on the worktree.
6. One full sweep before close with `AAI_TEST_TIMEOUT=4500`.
7. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## Evidence contract

Each artifact records ref_id issue-gate-via-spec, its Spec-AC and TEST
links, the command, the exit code and the evidence path, plus the commit SHA
once one exists. RED and GREEN logs under docs/ai/tdd/issue-gate-via-spec/,
mutation records under docs/ai/tdd/spec-issue-gate-via-spec/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Residual risks

- R1: a gated file with no frontmatter `id` can only be linked through its
  own `links.spec`; a spec linking back to it cannot be found. Every intake
  template writes an `id`.
- R2: in a close commit the hook gates the intake doc's staged blob against
  the working-tree spec. When the spec's staged blob differs from the working
  tree, the spec's own staged gate in the same loop is the authority.

## Out of scope

- `close-work-item.mjs` calling the close gate itself (follow-up).
- Prompt text that describes the gate (`VALIDATION.prompt.md` step 8b,
  `SKILL_WRAP_UP` 4b): still true as written.

## Registry items closed by this scope

From `node .aai/scripts/follow-ups.mjs list` (341 open, run 2026-11-16):
none. The defect was raised as a PR review thread (Codex P1 on PR #563), not
filed in the registry.
