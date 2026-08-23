# Subagent Contract

The per-dispatch payload every spawned subagent (Implementation, Validation,
Planning, Research) receives. Orchestrator-only material (decomposition, MODEL
contract table, review anti-gaming, validator spawning, usage capture, merge
protocol, delivery gate, platform fallback) stays in `.aai/SUBAGENT_PROTOCOL.md`.
The Standing hazards below bind the dispatched unit's own hands, so they live here rather than in per-dispatch prose.

## Standing hazards (HARD — each rule is a measured incident, not a style note)

These bind YOU on every dispatch whether or not the dispatch text repeats them; a dispatch may ADD a hazard, never waive one.

- HAZ-RESTORE — no restoring git command on a tracked file (`git checkout --`,
  `git restore`, `git stash`/`pop`, `git reset --hard`): mutate a COPY instead.
  Scar `fu-orchestrator-mutated-real-file` (P2, 2026-08-21): a bite-proof
  mutation went into the tracked suite file itself and its restore silently
  failed on a mis-anchored `sed`.
- HAZ-SCRATCH — experiments live in ONE reused copy under the absolute scratch
  path the dispatch names, never in the shipping tree. Scar
  `fu-subagent-probe-hits-real-repo` (P1, 2026-08-15): a probe `cd`-ed inside a
  command substitution, so the parent shell stayed in the real repository and
  the run created two commits on `main`.
- HAZ-CD — verify a path is non-empty AND absolute immediately before every
  `cd`. Scar `fu-empty-path-cd-stays-in-shipping-repo` (2026-08-22): a
  `local a=1 b=$a` chain left the fixture path empty, `cd ""` stayed put, and
  the harness committed into the shipping repository.
- HAZ-LEDGER — append-only ledgers (`EVENTS.jsonl`, `decisions.jsonl`,
  `tests/test-runs.jsonl` under `docs/ai/`): only ever add at the end, and a
  merge must leave the base a byte-exact prefix. About the BYTES, not the tool —
  a raw append is fine where no CLI owns the file. Scar
  `fu-append-only-merge-needs-prefix-order`: a union merge ordered the branch's
  appends first and CI caught `DIVERGES at byte offset 248943`.
- HAZ-WORKTREE — remove a scratch worktree with a targeted
  `git worktree remove <path>`, never `git worktree prune`. Scar
  `fu-prune-repair-error-string-misquoted` (2026-08-20, git 2.50.1): `prune -v`
  deregistered an unreachable-but-alive worktree that `git worktree repair`
  could not then restore.

## Result block (mandatory subagent output)

Every subagent MUST return a result block in this exact YAML format:

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

Timing capture rules:
- Capture `started_utc`/`ended_utc` from the system clock (`date -u` /
  `Get-Date ...ToUniversalTime()`), never model estimation; UTC ISO-8601, `Z`/`+00:00`.
- `duration_seconds` MUST match `ended_utc - started_utc` (tolerance +/-1s).

Usage-note honesty: a subagent MUST NOT self-report token usage — it cannot
observe its own; the orchestrator captures usage from the harness at merge time.

## Single-writer rule (HARD — RFC-0004 / SPEC-0004 D7)

A dispatched subagent **MUST NOT write `docs/ai/STATE.yaml`**; the orchestrator
is the **SOLE STATE writer** that merges each returned result block and performs
every STATE mutation. What a subagent MAY write: its own scoped source/test
files, append-only evidence under `docs/ai/tdd/`, and `docs/ai/EVENTS.jsonl` via
`append-event.mjs` (the append-only, commutative audit log).

### Single-writer rationalization table (stop and correct any of these)

| Rationalization                                          | Reality                                                                 |
|-----------------------------------------------------------|-------------------------------------------------------------------------|
| "My update to STATE.yaml is tiny, I'll just write it"   | Subagents MUST NOT write `docs/ai/STATE.yaml`. Return a result block; the orchestrator is the sole writer. |
| "I'll write STATE so the orchestrator doesn't have to"  | Direct subagent STATE writes race and lose updates at K >= 2. That is exactly the bug this rule removes. |

EXPECT: the result block above is validated by `.aai/scripts/check-role-output.mjs` against six deterministic postconditions (docs/specs/SPEC-0094-spec-role-output-contracts.md) before merge.
