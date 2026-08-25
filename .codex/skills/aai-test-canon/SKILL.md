---
name: aai-test-canon
description: Use when tests are fragmented per-change/issue with no single "current state" suite per feature — to consolidate them into a canonical per-domain layer in tests/canonical/ (anchored on the canonical docs domain map) while preserving and back-linking originals in tests/_archive/. Two phases — Phase 1 builds a traceability matrix + coverage-gap report and proposes a per-domain test map gated by human approval; Phase 2 consolidates the tests, archives originals, scaffolds failing/pending RED stubs for uncovered acceptance criteria (handing off to aai-tdd), and reports drift on re-run.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_TEST_CANON.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-test-canon`.

If `.aai/SKILL_TEST_CANON.prompt.md` does not exist, say: "SKILL_TEST_CANON not found — are you in an AAI project? Expected: .aai/SKILL_TEST_CANON.prompt.md"
