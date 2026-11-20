# Decision: SPEC-0046/Spec-AC-10 overdue Review-By (repo-wide Rule 3 interrupt)

Date: 2026-11-20T20:00:42Z
Blocking ref: SPEC-0046/Spec-AC-10 (raised as [HITL-6] during the bootstrap-on-node ride, Validation r1)
Decided by: human (owner)

## Question
SPEC-0046/Spec-AC-10 (manual Windows MV-1..MV-3 checks, tracked on ISSUE-0009) is overdue since 2026-11-17 and blocks every Validation PASS in the repository. Choose: (1) extend Review-By 30 days to 2026-12-17; (2) mark done (the checks were run); (3) reject (drop the manual checks, residual risk RR-1 stays recorded).

## Decision
"3" — reject. The manual Windows checks MV-1..MV-3 are dropped; residual risk RR-1 stays recorded in SPEC-0046.

## Assumptions
- The Spec-AC-10 row moves to rejected with its Review-By cleared, disclosed in a post-freeze Amendment section of SPEC-0046 (precedent: SPEC-0104 Spec-AC-03, 2026-09-12).
- The MV protocol section and RR-1 text in SPEC-0046 stay unchanged.
