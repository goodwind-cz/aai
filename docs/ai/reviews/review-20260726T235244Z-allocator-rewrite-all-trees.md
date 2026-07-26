```yaml
review:
  scope: "git diff main -- .aai/scripts/allocate-doc-number.mjs tests/skills/test-aai-doc-number-reservation.sh (+ untracked spec/intake drafts; regenerated telemetry)"
  spec: docs/specs/SPEC-0090-spec-allocator-rewrite-all-trees.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "allocate-doc-number.mjs:602-664 (recursive walk over REWRITE_TREES) + TEST-101/TEST-102" }
      - { ac: Spec-AC-02, call: compliant, citation: "isExcludedTree allocate-doc-number.mjs:591-597 + REWRITE_TREES allowlist:82-89; TEST-103 (byte-identity)" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-104 (run1==run2 sha, 2nd run 'nothing to do'); idempotence by no-DRAFT-left" }
      - { ac: Spec-AC-04, call: compliant, citation: "runAllocate dry-run branch allocate-doc-number.mjs:953-962; TEST-105" }
      - { ac: Spec-AC-05, call: compliant, citation: "REWRITE_TREES/EXCLUDED_TREES exported :82,:96; matcher byte-identical to main (main:564-566 == working:668-670); TEST-106" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-107 doc-numbering suite green (recorded)" }
      - { ac: Spec-AC-07, call: cannot-verify, citation: "deferred by design — local targeted suites green; PR CI full framework not yet run (Review-By 2026-08-10)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-doc-number-reservation.sh, line: 745,
          issue: "Shipped TEST-103 does not exercise the isExcludedTree nesting path: docs/ai/reports is byte-identical simply because it is not under any REWRITE_TREES root, so the test passes identically even if isExcludedTree always returned false. The guard's real protective behavior (skipping an excluded subtree discovered DURING a walk of a scanned root) has no committed regression coverage — only validation's throwaway mutation (adding docs/ai as a scanned root) proved it load-bearing.",
          failure_scenario: "A future edit adds a scanned root that nests an excluded spool (e.g. adds docs/ai to REWRITE_TREES, or nests an excluded subtree under docs/ai/reviews) and simultaneously breaks isExcludedTree; the committed suite stays green while a runtime spool gets mutated." }
      - { rank: NON-BLOCKING, file: .aai/scripts/allocate-doc-number.mjs, line: 669,
          issue: "RR-1 (verbatim substring matcher) blast radius is widened by this change: the same over-rewrite now reaches product/knowledge/sessions/README/CHANGELOG, not just governed dirs. Documented + accepted per the L3 conservative directive, but the widened exposure is not tracked as a follow-up.",
          failure_scenario: "Two same-prefix DRAFT slugs in one batch (e.g. RFC-DRAFT-foo and RFC-DRAFT-foo-bar); processing foo first rewrites the 'RFC-DRAFT-foo' substring inside a 'RFC-DRAFT-foo-bar.md' reference living in any newly-scanned tree, corrupting the foo-bar link." }
  cannot_verify:
    - { claim: "Spec-AC-07 — full framework green on PR CI", closes_with: "PR CI run green after push (Review-By 2026-08-10)" }
    - { claim: "Symlink no-escape and exclusion-guard-load-bearing behavior", closes_with: "Verified by validation report external evidence (VALIDATION-20260726T234752Z sections c/f: mutation test + outside-repo symlink fixtures), not by committed tests in this diff" }
  overall: pass
```

# Code Review — allocator-rewrite-all-trees (L3, single dual-verdict)

**Scope reviewed:** `git diff main` on `.aai/scripts/allocate-doc-number.mjs` and
`tests/skills/test-aai-doc-number-reservation.sh`, plus the untracked spec/intake
drafts. Ancillary regenerated artifacts (`docs/INDEX.md`, `docs/ai/EVENTS.jsonl`,
`docs/ai/overview*.{json,html}`, the project-session journal) are process
byproducts (INDEX/overview regeneration, docs_audit events) — no hand-authored
scope creep, no code changes outside the allocator + its suite.

**Spec:** docs/specs/SPEC-0090-spec-allocator-rewrite-all-trees.md (SPEC-FROZEN, ceremony_level 3).

## Verdict 1 — spec_compliance: PASS

Every in-scope Spec-AC is met (see AC walk above). Spec-AC-07 is an honest
CI-authoritative deferral (`deferred` in the AC-status table, Review-By
2026-08-10), not a non-compliance — the local half (targeted suites) is green and
the full-framework half is explicitly owned by PR CI.

Independently confirmed the load-bearing L3 requirement: the inner match/replace
is byte-identical to main —
- main:564-566 `if (!content.includes(oldBase)) continue; const updated = content.split(oldBase).join(newBase); if (updated !== content) …`
- working:668-670 same three expressions (the write is now guarded by `!dryRun`, the matcher expressions themselves unchanged).

**Allowlist/exclusion completeness (focus b).** Independently inventoried every
git-tracked `*.md` tree. The only committed-class trees carrying a DRAFT-basename
reference today are the governed dirs + product/reviews/sessions/knowledge +
root README/CHANGELOG — exactly REWRITE_TREES. The one other match,
`docs/INDEX.md`, is regenerated by `regenerateIndex`, so it correctly needs no
rewrite entry. No runtime tree is in the scanned set (docs/ai/reviews is
committed-class and docs-audit-excluded by construction). The allowlist is
empirically complete for the current repo. Note (INFO, not a defect): the
allowlist is empirical, not exhaustive — committed trees like `docs/workflow`,
`docs/roles`, `docs/templates`, `docs/ai/compliance`, and root
`AGENTS.md`/`CLAUDE.md`/`CODEX.md` are unlisted and would silently miss a DRAFT
reference if one ever lands there; that is a documented scope bound (Spec-AC-05
pins the two constants), not a compliance gap.

**Walker correctness (focus a).** Recursion is unbounded-depth over the named
roots; `entry.isFile() && endsWith('.md')` is the file filter; symlink dirents
are neither `isDirectory()` nor `isFile()` so they are skipped (no traversal, no
read/write — validation confirmed no-escape empirically). Missing roots are
`existsSync`-guarded; unreadable subdirs are try/caught (degrade-and-report). The
root-file case (README/CHANGELOG) is handled by the `treeRoot.endsWith('.md')`
branch. Dedup via a `Set`. One INFO: `readdirSync` order is not sorted, so the
dry-run per-tree file list is filesystem-ordered (non-deterministic across
platforms); the writes are order-independent so correctness holds and TEST-105
asserts by substring, not order — no failure scenario that bites.

**Dry-run accuracy (focus c).** `runAllocate` calls `rewriteReferences(…,{dryRun:true})`
per plan and prints the per-tree set; no writes occur (TEST-105 sha-checks the
whole fixture incl. the retained DRAFT). One INFO cosmetic gap: for a
self-reference, dry-run reports the file at its pre-rename DRAFT path while the
real run touches the post-rename numbered path (same logical file) — acceptable
for a preview.

## Verdict 2 — code_quality: PASS

No BLOCKING findings. Two NON-BLOCKING (see YAML): (1) the shipped suite does not
regression-guard the exclusion nesting path — TEST-103 passes because the
excluded fixture is never under a scanned root, so it would pass even if
`isExcludedTree` were a no-op; the guard's real value was proven only by
validation's throwaway mutation. (2) RR-1's over-rewrite blast radius is widened
to all newly-scanned trees — accepted per the L3 conservative directive but the
widened exposure is not tracked as a follow-up.

## Focus (d) — RR-1 acceptance vs a guard now

Deferral is justified. A real fix needs a boundary-aware matcher, which is
explicitly out of scope under the L3 "reuse the verbatim matcher" directive, and
validation confirmed the behavior is byte-identical to main (no NEW corruption
vector). The realistic trigger (two same-prefix DRAFT slugs merged in one batch)
is low-probability. Recommendation: do not add a guard in this scope; do record
the widened blast radius as a tracked follow-up (below), since the whole purpose
of the change is to retire the manual `sed` patching — the same class of silent
corruption should be visible in the backlog.

## Focus (e) — TEST-101..108 quality

Strong. TEST-101 covers all six newly-scanned trees + a negative control
(unchanged-guard file stays byte-identical). TEST-102 pins seam S2 (self-ref in
the renamed body). TEST-103 asserts excluded byte-identity (but see NB-1 —
doesn't exercise the nesting path). TEST-104 idempotence via sha compare + "nothing
to do". TEST-105 dry-run no-write + DRAFT retained + report content. TEST-106 the
exported-constants probe (namespace import so a missing export is a product_red
assert, not an infra SyntaxError — good RED hygiene). TEST-107 regression guard;
TEST-108 is a wiring/syntax meta-check that avoids self-recursion. The
`BASH_SOURCE`/`$0` guard enabling per-test sourcing for RED/GREEN isolation is a
clean addition. Gap: no committed test for the exclusion guard's nesting/separator
behavior (NB-1).

## WARNING dispositions (H6)

- NB-1 (exclusion nesting coverage gap): **promote-to-follow-up-ref** — a small
  test-hardening ISSUE to add a committed regression that makes `isExcludedTree`
  load-bearing in-suite (mirror validation's docs/ai-as-scanned-root mutation, or
  assert the separator guard on `reports` vs `reports-extra`).
- NB-2 (RR-1 widened blast radius): **promote-to-follow-up-ref** — track a
  boundary-aware-matcher ISSUE; already characterized as RR-1 in the spec, but the
  widened exposure warrants an explicit backlog item.

Orchestrator records the disposition artifact per H6 (a read-only reviewer does
not file refs).

## cannot_verify

- Spec-AC-07 full-framework CI green — not yet run (deferred by design).
- Symlink no-escape and the exclusion guard being load-bearing — substantiated by
  the validation report's external mutation + hostile-fixture evidence
  (VALIDATION-20260726T234752Z, sections c and f), not by the shipped diff/tests
  alone.

## Overall: PASS

Both verdicts pass. Merge-ready subject to (i) PR CI full-framework green closing
Spec-AC-07, and (ii) the two NON-BLOCKING dispositions being recorded by the
orchestrator before closeout.
