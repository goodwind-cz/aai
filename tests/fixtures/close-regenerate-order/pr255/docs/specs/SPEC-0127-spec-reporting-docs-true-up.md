Existence-only stand-in for the numbered counterpart that made PR #255's tree a
violation. The detection predicate tests only that this path EXISTS on disk next
to the stale token in the generated pages above; its contents are never read.
Real file at that commit: docs/specs/SPEC-0127-spec-reporting-docs-true-up.md
(created by 00bdd03, the same commit that produced the three stale pages).
