```yaml
review:
  scope: "HEAD bd519bb381840103c040818f5a950752eb61e53a plus local diff and untracked files in /private/tmp/aai-release-fixture-current-scope.json (11 paths)"
  spec: docs/specs/SPEC-0277-spec-release-fixture-atomic-publication.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - ac: Spec-AC-01
        call: compliant
        citation: "tests/skills/test-aai-release.sh:1396,1443,1457,2007; TEST-001 mutation record; framework/aai-release.log:24-26; owner-scoped aggregate exception disclosed below"
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - claim: "Current-head hosted Linux execution at unchanged default 540/1080-second bounds"
      closes_with: "Successful Linux CI run bound to the eventual PR head SHA; required after PR opening"
    - claim: "Successful complete full-framework aggregate and 21 interrupted/unstarted sync-seed cases"
      closes_with: "A separately authorized complete aggregate; owner accepted this named gap for this ride only"
    - claim: "Windows finish runtime, arbitrary multiwriter serialization, and historical hosted kernel scheduling"
      closes_with: "Appropriate platform/runtime or scheduling evidence; none is claimed by this fixture repair"
  overall: pass
```

security_relevant: false

# Review: release fixture atomic publication

Both review verdicts pass under the owner's explicit verification exception. This does not convert independent Validation FAIL into PASS, attest the missing aggregate coverage, or establish merge readiness before current-head Linux CI.

## Scope and independence

Reviewed the actual local tracked diff against HEAD/base bd519bb381840103c040818f5a950752eb61e53a and read every untracked scope document. The explicit 11-path manifest covers tests/skills/test-aai-release.sh, docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/METRICS.jsonl, docs/ai/decisions.jsonl, docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md, the repair intake and frozen spec, and all three decision documents. No unrelated visible changes existed at preflight. STATE records the authorized worktree. HEAD still equals the supplied base; a committed-only range would miss this implementation.

Fresh reviewer context; requested model gpt-6.1-sol, implementer gpt-6-sol as dispatched. The caller supplied refs/paths, no pasted diff or expected finding severity. Its operator-dispatch authority identifies the exception; it does not prejudge this review. No coaching attempt identified. Read canonical Code Review role, contract, technology contract, frozen spec, intake, actual diff, immutable Validation report and owner decision. No implementation, STATE or ledger was modified by the reviewer.

## AC walk and TEST evidence

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | tests/skills/test-aai-release.sh:1396 writes complete serialized bytes into a unique exclusive sibling, closes, then renames over the actual path; failures propagate with best-effort sibling cleanup. Seed at 1438, generated stub entry at 1443, save at 1457, scenario helpers and MERGER at 2378 all use the same primitive. Lines 2007-2038 exercise real generated publishers in a separate process, three exact previous-snapshot reads at each held entry/save boundary and exact next-snapshot equality after completion. Lines 2040-2048 retain actual SIGKILL, same journal head, one PR/merge, claim/reclaim cleanup and foreign-host refusal. Independent full-release log lines 24-26 confirms both boundaries and SIGKILL, and this review independently reran the selected TEST-021 successfully. |

TEST-001 exists inside selected TEST-021. The stored mutation record identifies the current fixture SHA256 7bc9dec3f4f5ecd330b81933c6b11bc86bc586afe4f026722a0322e7637c1750 and restores the direct destination writer while preserving the handshake: it fails the exact entry held-boundary JSON assertion with Unexpected end of JSON input. Independent validation replay says 1/1 reddens, zero inconclusive/restamped. Read the actual mutation record, replay log, writer inventory, full release output and final selected log. This review independently reran `env -u AAI_ROLE -u AAI_GIT_WRITE RELEASE_FINISH_CASE=TEST-021 RELEASE_RECUT_CASE=none bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh test_700_one_command_finish`: exit 0; entry/save boundary and actual SIGKILL markers all present. No full-framework sweep or rehearsal was repeated.

Read the R2 rehearsal JSON directly: complete=true, pending=[], sourcePreserved=true, 58 execution records, all exitCode 0, sourceHead bd519bb381840103c040818f5a950752eb61e53a, local bounds 1800/3600. Independent validation ties it to the equivalent source fixture and final fixture hash. Registration and inventory check evidence is recorded in the Validation report. The implementation adds no nested literal CHANGELOG reader or suite, so no discovery shim or allowlist change is needed.

## Quality assessment

No BLOCKING or NON-BLOCKING defect found. No warning disposition is required. Entry logging and save share the same serialized helper as parent edits and the inline MERGER publisher. The barriers are opt-in and bounded; normal fixture execution gets no added delay or parser retry. The existing real transport reader remains strict. Reviewed ownership around simultaneous confirm, owner kill/orphan completion and recut: atomic replacement solves complete-snapshot visibility; the change makes no unsupported arbitrary read-modify-write concurrency claim. The temporary siblings are fixture-owned transient outputs rather than a new persistent runtime sidecar lifecycle. Existing fixture cleanup owns their containing scratch directory.

The three changed ledgers retain byte-exact HEAD prefixes and all appended records parse as JSON. Worktree telemetry's initial wrong shape has an explicit append-only correction; it does not claim a second worktree. Lifecycle/status and amendment records match the scoped work. The deadline companion changes only 2026-11-06 to 2026-11-21, preserving deferred status and pending hosted measurements; its exact owner decision/event is retained. INDEX reflects that deadline and the UTC day without claiming deferred completion. No production engine, parser, allocator, dependency, CI gate, merge or release changed.

## Deviations and cannot_verify

The frozen verification matrix required a complete successful full aggregate and originally disallowed a waiver. Actual aggregate exit 124 remains a deviation: 125 PASS, one Hermes SKIP, interrupted TEST-790 and 20 unstarted cases. The subsequent owner decision at docs/decisions/DECISION-release-fixture-validation-exception.md explicitly supersedes that verification requirement for this ref only and authorizes review/PR preparation. It does not change fixture acceptance behavior, accept new failures or waive Linux CI. Compliance is assessed with this later owner instruction; the failed aggregate is neither silently passed nor characterized as a code defect.

Verified the immutable Validation report SHA256 dfed1cacd87bf9295d1a7b56dd78ded1f1ec20d12ff42ca1e5eaaa811a1d163d matches the decision. Its FAIL verdict and exact 21-case list remain intact. R1's environment-contaminated failures remain separate from the successful amended R2 rehearsal. No additional full sweep is authorized.

The cannot_verify list above names the incomplete aggregate, pending hosted CI and unclaimed broader platform/scheduling guarantees. Controlled boundary ordering proves this regression without reconstructing the historical remote schedule. Atomic rename is a same-filesystem visibility guarantee, not fsync durability or multiwriter serialization. These limits are accurately documented in the spec.

## Next step

Return review PASS to the orchestrator, retain the typed exception and original Validation FAIL, then prepare the authorized PR and obtain green current-head Linux CI before merge readiness. Stage this review with the scope commit per the normal PR ceremony. No merge or release is authorized by this report.


## Administrative addendum — 2026-11-07

```yaml
administrative_review:
  scope: "b27cad401e8e5490985dac8c8cf534f43179f195...ee631dbbb2f33fed6b7d0a05e5bcc4c7854d4955 plus regenerated local companions and appended follow-up at 10:06:02Z"
  spec_compliance:
    verdict: pass
    ac_walk:
      - ac: Spec-AC-01
        call: compliant
        citation: "SPEC-0277:44-55; fixture SHA256 7bc9dec3 unchanged; original TEST-001/TEST-021 evidence and scoped owner exception retained"
  code_quality:
    verdict: pass
    findings:
      - rank: NON-BLOCKING
        file: docs/INDEX.md
        line: 64
        issue: "Pre-regeneration index counted duplicate SPEC-0245 rows and inflated done count"
        failure_scenario: "Generating with unresolved index stages listed SPEC-0245 three times, showing 628 done documents rather than 626"
        disposition: "remediated-in-tree: post-rebase regeneration has one SPEC-0245 row and Done (626)"
      - rank: NON-BLOCKING
        file: docs/ai/overview-data.json
        line: 257
        issue: "The generated repair entry reports agent_minutes=0 despite measured role runs retained in STATE"
        failure_scenario: "Closed ride lacks flushed METRICS data because the scoped validation exception does not satisfy normal flush; overview displays 0 min agent time"
        disposition: "filed follow-up fu-overview-unflushed-time in docs/ai/decisions.jsonl at 2026-11-07T10:06:02Z; open P2"
  cannot_verify:
    - claim: "Current-head Linux CI and complete aggregate"
      closes_with: "Current-head hosted Linux PASS after PR opening; separately authorized aggregate for the explicitly accepted gap"
    - claim: "The cause of frozen-spec hash drift was wholly allocator-shaped"
      closes_with: "Reconstruction of the original anchored bytes; currently disclosed as unverified with unsigned contract amendment and filed owner-signoff follow-up"
  overall: pass
```

The addendum covers all 16 final branch paths, including generated JSON/HTML, the original report, numbered ISSUE-0110/SPEC-0277, decisions, all changed ledgers, INDEX and the fixture. Reviewed the actual branch diff against updated main plus the subsequent dirty regenerated artifacts; no source-runtime change was introduced by numbering, closure or rebase. The original report prefix before this addendum had SHA256 9af1beda0f62c5c2bbc2d00f37fe26952a5e430f1b727e74049b24bd5513ff96 and remains byte-for-byte intact.

Fixture SHA256 remains 7bc9dec3f4f5ecd330b81933c6b11bc86bc586afe4f026722a0322e7637c1750. Immutable Validation report remains dfed1cacd87bf9295d1a7b56dd78ded1f1ec20d12ff42ca1e5eaaa811a1d163d. The original behavioral AC walk and test results therefore still apply. No tests or full sweeps were rerun for this administrative addendum. Read-only structural verification independently checked hashes, JSON contents, main ledger byte prefixes and the final generated rows.

Numbering changes paths and frontmatter; closure explicitly retains the failed aggregate, successful 58/58 rehearsal, scoped owner exception and required current-head Linux CI. The restamp is accurately disclosed as unverified, unsigned and tracked by filed P2 fu-amend-release-fixture-atomic-p-8f6434, rather than mislabeled as a proven mechanical rewrite. No owner sign-off is inferred. The appended close-event corrections replace default PASS claims with explicit exception semantics without rewriting history; all three changed ledgers preserve main's exact byte prefixes. The original historical deadline decision now explains supersession by independently completed main evidence. SPEC-0245 itself is byte-identical to main, whose Spec-AC-06 is done; this branch does not revert that delivery. Original report statements about the deadline companion describe the original pre-rebase review scope and are superseded here.

Generated companion inspection found the transient duplicate index and the zero-time claim listed above. After regeneration, INDEX lists one SPEC-0245 row and Done (626), exactly the two new numbered documents above main's 624. The overview adds one delivered issue with proper numbered links; its false 0-minute display remains an open P2, explicitly promoted to filed follow-up fu-overview-unflushed-time, not accepted as accurate. The generated factory report consistently counts two distinct new closed refs and folds their latest close corrections; common follow-up contents are unchanged except elapsed-day ages, the signed main Cloudflare amendment leaves the open list, and new follow-ups appear. The separate filed P2 fu-factory-report-waiver-history already covers the pre-existing inaccurate waiver caption/default-close semantics. No production reporting source was changed in this fixture repair.

Warning dispositions: duplicated INDEX rows remediated in tree; zero-time display promoted to filed fu-overview-unflushed-time. Related already-filed follow-ups are fu-amend-release-fixture-atomic-p-8f6434 (unsigned restamp) and fu-factory-report-waiver-history (reporting exception semantics). The orchestrator must retain these dispositions in code_review.notes and disclose the open reporting limitation at PR/checkpoint. Both administrative verdicts pass; this is conditional on those explicit recorded dispositions and the unchanged post-open Linux CI requirement. No merge or release is authorized.

The final split-decision shared-page coordination paragraph was also inspected: it records the six generated-page overlaps with PR #535, owner-directed repair-first ordering, and later rebase/regeneration/reverification of #535 after the owner merges the repair. It does not copy another branch's pages or authorize either merge. The all-open-PR probe result is caller-observed coordination evidence, not independently re-queried by this read-only local addendum.
