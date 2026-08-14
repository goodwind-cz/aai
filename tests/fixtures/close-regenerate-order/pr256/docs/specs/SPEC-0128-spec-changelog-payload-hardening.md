Existence-only stand-in for the numbered counterpart that made PR #256's tree a
violation. The detection predicate tests only that this path EXISTS on disk next
to the stale token in the generated pages above; its contents are never read.
Real file at that commit: docs/specs/SPEC-0128-spec-changelog-payload-hardening.md
(created by ff8208e, the same commit that produced the two stale pages).
