# Work-Item Brief — <REF-ID>

<!-- Emitted by Planning (.aai/PLANNING.prompt.md step 11) from this template
  AFTER spec freeze. Gitignored runtime artifact (docs/ai/briefs/<REF-ID>.md,
  same class as docs/ai/reports/) — regenerated on re-plan, never committed.
  Target: a self-contained 500–1,000-word handoff (RES-0001 rec 9, BMAD). -->

## Scope & Why
- Mission: <one paragraph — what this work item delivers>
- Why: <business/technical reason, from the CHANGE/requirement summary>
- Refs: <REF-ID> | Spec: <docs/specs/SPEC-...> | Strategy: <loop|tdd|hybrid>

## AC ↔ Task Map

| Spec-AC | TEST ids | Task (what to build/change) |
|---------|----------|-----------------------------|
| Spec-AC-01 | TEST-00x | <concrete task, from the frozen spec's Test Plan> |

## Constraints & Canon Pointers
Canon pointers are repo PATHS ONLY (path + section) — never paste full copies
of canon bodies into a brief (prompt-diet discipline, RES-0001 F3).
- Spec: <path + section anchors the subagent must read>
- Requirement/intake: <path>
- Technology contract: docs/TECHNOLOGY.md
- Learned rules: docs/knowledge/LEARNED.md
- Hard constraints: <caps, out-of-scope lines, protected files for this scope>

## Evidence Contract
Per Spec-AC: the verification command(s), expected exit code, and evidence
path — lifted from the spec's Verification section.
- Spec-AC-01: <command> → <expected evidence + path>

## Return Record
Fill this skeleton and return it as your result block — do not invent another
format. Single source: .aai/SUBAGENT_PROTOCOL.md section
"Result block (mandatory subagent output)"; if this skeleton and the protocol
ever diverge, the protocol wins (re-sync the template).

```yaml
subagent_result:
  scope: <scope id or path>
  role: <Implementation | Validation | Planning | Research>
  status: PASS | FAIL | BLOCKED
  started_utc: <ISO 8601 UTC captured from system clock>
  ended_utc: <ISO 8601 UTC captured from system clock>
  duration_seconds: <integer = ended_utc - started_utc>
  evidence:
    - command: <shell command or verification step>
      exit_code: <int>
      output_snippet: <first 200 chars of relevant output>
  files_changed:
    - <relative path>
  blockers:
    - <description of any blocker; empty list if none>
```
