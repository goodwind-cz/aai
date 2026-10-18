# Code Review: release-one-shot-finish

Target path: docs/ai/reviews/review-20261017T225414Z-release-one-shot-finish.md

```yaml
review:
  scope: git diff b0b9ab15...HEAD (HEAD 78813590, branch fix/release-one-shot-finish); paths .aai/scripts/release-finish.mjs tests/skills/test-aai-release.sh .aai/SKILL_RELEASE.prompt.md docs/product/release-command-finish.md CHANGELOG.md docs/specs/SPEC-0236-spec-release-one-shot-finish.md docs/issues/ISSUE-0103-release-one-shot-finish.md docs/INDEX.md docs/ai/EVENTS.jsonl
  spec: docs/specs/SPEC-0236-spec-release-one-shot-finish.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "release-finish.mjs:405-411,422-434,519; TEST-074 (mergedAfterLate: merge index > latePassCall, engine reads >= 4, watch reads >= 1); mutation-TEST-074 RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:395-404 (filter r.type==='required_status_checks'), union via Set at :410; TEST-075 late-ruleset + late-union; mutation-TEST-075 RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "release-finish.mjs:431 refuse required-contexts at deadline; TEST-076 exit 20, one REFUSED, resume line, merges 0, engine reads >= 5; mutation-TEST-076 RED (an earlier STAYED GREEN record led to the engine-reads assertion)" }
      - { ac: Spec-AC-04, call: compliant, citation: "release-finish.mjs:426-427; TEST-077 engine reads exactly 3, required-checks naming late-suite (fail), merges 0; mutation-TEST-077 RED" }
      - { ac: Spec-AC-05, call: compliant, citation: "release-finish.mjs:375,408-409; TEST-078 both arms (one line each, phrase only when both unreadable, protection contexts still awaited); mutation-TEST-078 RED" }
      - { ac: Spec-AC-06, call: compliant, citation: "release-finish.mjs:376-377,382,396; TEST-079 bad-json, bad-shape, rules-bad-shape; mutation-TEST-079 RED" }
      - { ac: Spec-AC-07, call: compliant, citation: "release-finish.mjs:527-538; TEST-080 policy-hold exit 8 then resume exit 0 with merges 2, merge-502 exit 20 github-command; mutation-TEST-080 RED" }
      - { ac: Spec-AC-08, call: compliant, citation: "release-finish.mjs:230; TEST-081 real hook from --print ref-guard under local core.hooksPath, armed probe, local main == merge SHA; mutation-TEST-081 RED" }
      - { ac: Spec-AC-09, call: compliant, citation: "release-finish.mjs:230 is the only AAI_GIT_WRITE site; TEST-082 dynamic (exactly one '1<TAB>update-ref --stdin') + static frontend/engine checks; mutation-TEST-082 RED" }
      - { ac: Spec-AC-10, call: compliant, citation: "release-finish.mjs:460, :516; TEST-083 both arms incl. zero create/merge after refusal; mutation-TEST-083 RED" }
      - { ac: Spec-AC-11, call: compliant, citation: "docs/product/release-command-finish.md:50-53; SKILL_RELEASE 4921 <= 4927 bytes, exit 8 line names branch policy; TEST-084; mutation-TEST-084 RED" }
      - { ac: Spec-AC-12, call: compliant, citation: "test-aai-release.sh ownSelector /^TEST-0[6-8][0-9]$/, wrappers test_718..729 registered in main; TEST-085; mutation-TEST-085 RED" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 532,
          issue: "PENDING: merge-policy cannot tell a checks lag from a block that needs a person. gh prints 'the base branch policy prohibits the merge' on the client side for every mergeStateStatus BLOCKED, which also covers missing required approvals, CODEOWNERS, unresolved conversations and required deployments.",
          failure_scenario: "The base requires one approving review and no one has approved the release PR. Every --confirm resume waits through the checks again, makes one merge attempt and exits 8 with the same generic 'resume once it is satisfied'. An operator or agent that resumes on exit 8 keeps doing this without learning that a review is the blocker. There is no infinite loop inside one run (one merge attempt per run)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 374,
          issue: "The rules endpoint is read with a bare 'gh api' (no --paginate). GET /repos/{o}/{r}/rules/branches/{b} is paginated (30 per page by default), so a required_status_checks rule on page 2 or later is dropped silently, with no named degrade line.",
          failure_scenario: "A repository with more than 30 active branch rules has its required_status_checks rule past the first page. The engine reads no ruleset contexts, does not print a '- Required contexts:' line, can merge early, and gets the gh policy refusal. That ends safely as PENDING: merge-policy, so the outcome is the pre-change behavior and not an unsafe merge. It still breaks D2's 'never silent' wording." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1428,
          issue: "No test covers degrade plus a late context end to end. In contexts-unreadable mode the stub's classicSet() returns only ['required'], so nothing proves that a fully degraded run with a late required context ends as PENDING: merge-policy. That path is the safety argument for D2. The spec's step 6 said the stub enforces the set 'even when the endpoints answer unreadable'; the enforcement code exists, but no mode uses it with a late context.",
          failure_scenario: "A later change breaks the degraded path so that a policy refusal after a degrade becomes REFUSED instead of PENDING (or the reverse). TEST-078 stays green because its merge always succeeds." }
  cannot_verify:
    - { claim: "Live GitHub response shapes: the branch endpoint 'protection.required_status_checks' as seen by a non-admin token, and the rules endpoint shape on repositories that have rulesets (measured once, with an owner token, on a repository with no rulesets)",
        closes_with: "The next live /aai-release --confirm on goodwind-cz/aai, plus one downstream run with a read-only token" }
    - { claim: "Whether rules/branches returns rules from rulesets in 'evaluate' (non-enforced) mode. If it does, the engine waits for a context GitHub does not enforce, which may never report, and refuses required-contexts after AAI_RELEASE_WAIT_SECONDS",
        closes_with: "GitHub docs confirmation or a live probe on a repository with an evaluate-mode ruleset" }
    - { claim: "The merge-policy pending detection relies on gh's client-side blockedReason text ('the base branch policy prohibits the merge'). The text has no versioned contract. If gh rewords it, the outcome falls back to REFUSED github-command (safe, but the pending UX is lost)",
        closes_with: "A pinned gh version check, or a test against the gh source string" }
    - { claim: "D2's 'degrade cannot produce an unsafe merge' when the token is an admin, enforcement is non_admins or enforce_admins is false, and mergeStateStatus is UNKNOWN (gh skips its client-side check and calls the API)",
        closes_with: "A live probe of the GraphQL mergePullRequest admin bypass behavior; note that the degraded path equals the pre-change behavior, so this is not a regression" }
    - { claim: "App-pinned required checks (app_id / integration_id) whose name collides with another app's check: matching by name lets the wrong app's pass satisfy the context (accepted residual in the spec's Seams section)",
        closes_with: "Per-app matching (out of scope)" }
  overall: pass
```

## Scope and preflight

- Worktree mode: STATE `worktree.user_decision: worktree`, base_ref b0b9ab15. I reviewed `git diff b0b9ab15...HEAD`, verified HEAD 78813590 on fix/release-one-shot-finish, and the tree was clean (`git status --porcelain` empty).
- Commits: fc539eb4 (intake + frozen spec) and 78813590 (implementation).
- Dispatch check: the dispatch listed focus areas. It did not pre-rate severity and did not exclude any area, so I found no coaching. I reviewed the whole scope, including INDEX and EVENTS.
- Read-only: no suites were run, per the dispatch (a validator runs them concurrently). Test evidence was read from docs/ai/tdd/release-one-shot-finish-{red,green,full}.log and the mutation records.

## Evidence I checked

- Mutation records for TEST-074 to TEST-085 are all RED. Their target_sha256 values match the HEAD blobs:
  - release-finish.mjs 1ef257ac
  - product doc c6667c5e
  - suite 5d84e782
- An earlier TEST-076 record STAYED GREEN. The mutant refused required-contexts on its first read, which is the same cause the test expected. The suite then gained the assertion "engine reads >= 5", and the rerun is RED. That is a legitimate strengthening, not gaming.

## Correctness walk (the dispatch's focus areas)

- **Discovery (:373-411):**
  - Classic contexts are the union of `contexts` and `checks[].context`, so duplicates collapse.
  - Rulesets contribute through the literal type filter.
  - These cases give zero contexts: `protected:false`, an absent `required_status_checks`, and `enforcement_level:'off'`.
  - `protected:true` with no `protection` object is treated as UNREADABLE.
  - `record.repo` and `encodeURIComponent(base)` are used, never the `{owner}/{repo}` placeholder.
  - App pins are ignored by design.
  - Status vs check-run: `gh pr checks` `name` is the check-run name for Actions jobs and the context for commit statuses. Both equal the protection context.
- **Matching (:428):** exact name with bucket pass. A pending check with a duplicate name keeps the wait going (`waiting`). A failing duplicate refuses through `bad`, provided gh lists it as required.
- **Bounded wait (:422-434):**
  - The deadline starts after watch-ci, and the sleep uses Atomics.wait with `interval`, so there is no busy loop at the default settings.
  - `AAI_RELEASE_POLL_SECONDS=0` would spin gh calls until the deadline. That is the same pre-existing pattern as `boundedPoll` and `registeredChecks`, and it is not new.
  - Worst case is the grace plus watch-ci (maxWait) plus the context wait (maxWait). This matches spec D4 ("bounded by AAI_RELEASE_WAIT_SECONDS" for the loop itself).
  - The registration grace (`registeredChecks`) is unchanged.
  - Change from before: the post-watch read used to refuse on any non-pass check, including pending. A pending check now waits instead, which is the intended behavior.
- **Unreadable vs malformed:**
  - Any non-zero gh exit is UNREADABLE, including transient 5xx or rate limits. That fails open toward the pre-change behavior, and the line names it.
  - Exit 0 with bad JSON or a bad shape refuses before any merge.
  - The degrade is safe to the same extent the pre-change engine was, because GitHub (and gh's BLOCKED check) stays the final gate. See cannot_verify for the admin and UNKNOWN corner.
- **Merge outcome (:524-539):**
  - The merge argv still has the literal `--match-head-commit`.
  - After a failure the PR is always re-read. MERGED continues, which is an improvement: a gh timeout or non-zero exit after a real merge no longer refuses.
  - `queuedOrRefuse()` runs before the policy regex, which is consistent with merge-queue PENDING.
  - Only the exact gh phrase maps to pending. Anything else is `github-command` with stderr, or `merge` when gh exited 0 and the PR is not merged.
  - A resume is one bounded run with one merge attempt, so nothing loops forever. Over-breadth of BLOCKED is NB-1.
- **AAI_GIT_WRITE (:230):**
  - It is set only on the `update-ref --stdin` spawn env.
  - There is no `process.env` assignment and the frontends do not mention it.
  - The `read-tree` worker and every other git child inherit only the caller env. TEST-082 measures this through the PATH git wrapper.
  - The hook guards only `refs/heads/main`. The engine's other ref writes are remote-tracking refs and the release branch.
- **Closed PR (:460, :516):** the cause stays `identity`, and the texts match Spec-AC-10 exactly. The CLOSED check comes before the generic ambiguous refusal.
- **ownSelector:** `/^TEST-0[6-8][0-9]$/` contains no pipe. TEST-085 parses the suite and proves every in-range check id has a wrapper that `main` calls, so TEST-073 no longer runs twice.
- **Stub fidelity (vacuity check):** `pr merge` refuses with GitHub's exact text while any configured late-suite context has not passed (`policyBlocked`, :1430). An engine that merged early would therefore end as PENDING exit 8, and TEST-074/075's `status===0` assertion would fail. The late arms are not vacuous.
  - The stub shows late-suite only to engine reads (`--repo`), not to watch-ci reads. That is a simplification, and it models the real failure (watch-ci settling on the reported subset).
- **SKILL_RELEASE:** a one-line change, 4921 bytes (was 4927). No diet-ledger entry or TEST-012 bump is owed (spec D8).
- **CHANGELOG:** uses the per-entry `## [unreleased] — <title>` heading form that aai-release expects.
- **INDEX/EVENTS:** regenerated index rows plus one `doc_lifecycle` draft-to-implementing event. Both are consistent.

## Warning dispositions (recommended; the orchestrator records them)

- NB-1 (policy pending does not separate checks from reviews): promote to a follow-up, P3. Suggested id `fu-release-policy-pending-reason`: on the pending path, include `mergeStateStatus` / `reviewDecision` from the re-read in the detail.
- NB-2 (rules endpoint pagination): `accepted residual: more than 30 active branch rules is rare, and the outcome is the safe pre-change behavior ending as PENDING merge-policy; P3 assurance gap with no observed bite.` A promoted follow-up is the alternative.
- NB-3 (degrade plus late context untested): remediate in the tree if a validation round is reopened anyway (add a `contexts-unreadable-late` mode asserting exit 8 PENDING merge-policy). Otherwise `accepted residual: the D2 safety path equals the pre-change behavior and TEST-080 covers the policy-to-pending mapping; P3 coverage gap.`

## Next steps

- No blocking findings. The review passes on condition that the three NB dispositions are recorded.
- The cannot_verify items close with the next live `/aai-release --confirm`.
