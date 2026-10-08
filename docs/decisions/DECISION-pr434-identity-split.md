# Decision: split remaining PR434 identity repairs

Date: 2026-10-08
Blocking ref: pr-capability-preflight review-round-cap
Decided by: human

## Question

Split the two independently confirmed remaining identity repairs into separately scoped changes, or leave PR434 parked. Concrete proposal: ORCHESTRATION-20261008T024844Z-pr434-park.md.

## Decision

The owner answered: “Oprav to snad to nebude na dlouho”. Continue and fix both confirmed cases.

## Assumptions and scope

Treat this answer as approval of the recommended concrete split, with minimal source changes and focused evidence: pr-generic-url-validity (malformed scheme refusal before generic fallback) and pr-github-case-identity (GitHub case-equivalent identity comparison). These are separate work items with dedicated branches and independent checks, not a third implicit raw-ssh-path package iteration. Existing worktree reuse is authorized; no new worktree is required. Preserve all historical failures/manifests and staged parent evidence. Root owns Git/STATE/lifecycle. After reviewed split changes are integrated into PR434, owner-approved final assembly Review, metadata-only closure, native/full CI, independent Validation and external sweep remain required. No capability expansion, review waiver, fake PASS or merge authorization.
