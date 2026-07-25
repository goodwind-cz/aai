---
review:
  scope: "working tree (uncommitted) — delta since review-dual-verdict-20260725T005236Z-friction-capture-foundation.md: .aai/scripts/aai-friction.mjs (MAX_ID_LEN/PIPE_BUF caps + guard), .aai/system/FRICTION_PROTOCOL.md (rationale correction), docs/specs/SPEC-DRAFT-spec-friction-capture-foundation.md (Spec-AC-06 + Edge-cases correction, TEST-019 row), tests/skills/test-aai-friction.sh (TEST-019 added, TEST-011 header comment fixed). Full scope otherwise unchanged from the prior review's file list."
  spec: docs/specs/SPEC-DRAFT-spec-friction-capture-foundation.md
  prior_report: docs/ai/reviews/review-dual-verdict-20260725T005236Z-friction-capture-foundation.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unchanged from prior review; TEST-001 re-run green." }
      - { ac: Spec-AC-02, call: compliant, citation: "unchanged; TEST-002/003/004 re-run green." }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged; TEST-005/006 re-run green; independently re-ran the same forbidden-keys+forged-derived-fields+novel/nested/array-keys fixture from the prior review -> byte-identical persisted line, still exactly the 8 allowlist keys." }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged; TEST-007/008 re-run green; grep still shows only the two documented 'network' prose matches." }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged; TEST-009 re-run green." }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-010/011/018/019 all green. Independently reproduced: (a) the prior BLOCKING repro (6000-char skill_id) is now rejected, exit 3, 'exceeds the maximum length of 128 characters', spool directory created but no observations.jsonl written at all; (b) boundary at exactly 128 chars accepted (349-byte line), 129 chars rejected; (c) worst-case caller-controlled line (skill_id AND skill_phase both at the 128-char cap simultaneously) serializes to 463 bytes, nowhere near PIPE_BUF's 4096; (d) 25 independently spawned concurrent at-cap (128+128 char) records -> exactly 25 parseable lines, no loss/corruption. Spec-AC-06's row and TEST-019's row in the spec are both pipe-count-safe (recounted, 0 mismatches across both tables)." }
      - { ac: Spec-AC-07, call: compliant, citation: "unchanged; TEST-012 re-run green; the new PIPE_BUF guard's rejection also goes through the same ValidationError -> exit 3 -> stderr path, so capture-never-masks holds for the new rejection reason too (verified in the skill_id-over-cap repro above: exit 3, not an uncaught exception)." }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged; TEST-013 re-run green." }
      - { ac: Spec-AC-09, call: compliant, citation: "unchanged; TEST-014 re-run green; test-aai-layer-profiles.sh independently re-run, ALL TESTS PASSED." }
      - { ac: Spec-AC-10, call: compliant, citation: "unchanged; TEST-015 re-run green (no --help wording change was needed or made)." }
      - { ac: Spec-AC-11, call: compliant, citation: "unchanged; TEST-016 re-run green." }
      - { ac: Spec-AC-12, call: compliant, citation: "18/18 runnable functions in tests/skills/test-aai-friction.sh pass (TEST-017 remains the full-runner meta-assertion); test-aai-layer-profiles.sh green; git status confirms no *.prompt.md/AGENTS.md touched; full 43-suite runner not executed per dispatch instruction, listed in cannot_verify as before." }
  code_quality:
    verdict: pass
    findings: []
    closed_from_prior:
      - { rank: BLOCKING (prior), file: .aai/scripts/aai-friction.mjs, line: 262, issue: "False PIPE_BUF safety-margin claim; skill_id/skill_phase unbounded.", disposition: "REMEDIATED — verified closed by construction, not just by the specific repro. See 'Trace of the persist path' below for the exhaustive check across all 8 allowlisted fields, not only the two originally named." }
  cannot_verify:
    - { claim: "The full 43-suite project test runner is green after this change.", closes_with: "CI run of the project's documented full runner; dispatch explicitly instructs the reviewer not to block on this, CI is authoritative (unchanged from prior review)." }
    - { claim: "The PIPE_BUF guard's threshold (>= 4096) exactly matches the real kernel PIPE_BUF on every CI/target platform (Linux, macOS, Windows/Git-Bash).", closes_with: "PIPE_BUF is a POSIX pipe/FIFO constant (traditionally 4096 on Linux/macOS); Windows has no direct equivalent concept for regular-file O_APPEND atomicity, so this guard is a conservative, portable, single hardcoded threshold rather than a platform-queried value — reasonable given the caps make normal lines ~463 bytes max (9x headroom), but the exact number 4096 is not queried from the OS. Not a blocking concern (the guard is a backstop, and the real safety comes from the caps holding the line ~9x under the threshold on every platform), noting for completeness." }
  overall: pass
---

# Code Review Re-review — RFC-0012 Phase 0: friction capture foundation

**Role:** Code Review (L2 full lane, re-review of remediation delta, independent reviewer)
**Branch:** feat/friction-capture-foundation
**Ref:** friction-capture-foundation
**Prior report:** `docs/ai/reviews/review-dual-verdict-20260725T005236Z-friction-capture-foundation.md` (verdict: fail, kept, not overwritten — D5 no-self-append)
**Re-review started (UTC):** 2026-07-25T01:03:14Z
**Report written (UTC):** 2026-07-25T01:05:34Z

## Scope preflight
Working tree remains the review scope (still nothing committed). `git status --porcelain=v1 -uall` shows the same file set as the prior review plus the prior review report itself (untracked, expected — reports are staged with the scope's eventual commit per SPEC-0013 H4, not part of the reviewed diff). No protected-path (`docs/ai/docs-audit.yaml` `protected_paths_l3`) file appears anywhere in the change.

## The finding, re-verified

### 1. Trace of the persist path — is every field now short-by-construction?

| Persisted field | Source | Bound |
|---|---|---|
| `schema_version` | fixed constant `1` | 1 char, fixed |
| `os_family` | `deriveOsFamily()` — one of 4 fixed enum strings | <= 7 chars, fixed set |
| `node_major` | `deriveNodeMajor()` — parsed integer | small integer, fixed shape |
| `fingerprint` | `computeFingerprint()` — `v1:` + 32 hex chars | 35 chars, fixed length regardless of input size (SHA-256 truncated) |
| `skill_id` | caller input, `requireString` + `capField(..., MAX_ID_LEN=128)` | <= 128 chars, enforced at validation, BEFORE the persisted object is built |
| `skill_phase` | same | <= 128 chars, enforced |
| `failure_class` | caller input, `requireString` + `capField` + enum check | <= 128 chars enforced (redundant with the 6-value enum, which is already <= 27 chars, but capped anyway) |
| `aai_pin` | `deriveAaiPin()` — read from `.aai/system/AAI_PIN.md`, a project-controlled frozen contract file, never caller input | **not explicitly length-capped**, but not caller-reachable either |

Five of eight fields are fixed-length or fixed-enum by construction. Three
(`skill_id`/`skill_phase`/`failure_class`) are capped at validation time,
before `record()` ever builds the `persisted` object — confirmed by reading
`validate()` (lines 183-220): `capField` is called immediately after each
`requireString`, so a violation throws `ValidationError` and `record()`
never reaches line 333 (the `persisted = {...}` construction) at all. This
directly answers "does the cap introduce a copy-then-mutate path" — no: the
cap is a pure validation gate that either passes a short string through
unmodified or throws before any object is built; `persisted` is still built
by the same fresh-object-literal-with-8-named-keys pattern as before (lines
333-342), unchanged in shape.

The one field with no explicit per-field cap is `aai_pin` — it is derived
from a local, project-controlled file, not caller input, so it is not
independently exploitable by a `record --input` caller. But the review
explicitly asked "is there ANY remaining allowlisted field that could push
the line over PIPE_BUF and reach appendFileSync" — the honest answer for
`aai_pin` specifically is "not capped, but not the caller's to control." The
code does not rely on that argument alone, though: the **hard pre-append
line-length guard** (lines 344-355) computes `Buffer.byteLength(line + '\n')`
against the FULL serialized `persisted` object — every field, unconditionally
— and throws before calling `appendLine()` if the total is `>= PIPE_BUF`,
regardless of which field(s) contributed the size. This closes the gap for
`aai_pin` (and for any future allowlist addition) structurally: there is no
path from `validate()`/`record()` to `appendFileSync()` that skips this
check. Read `record()` end to end (lines 325-358): `line` is computed once,
checked once, and only `appendLine(line)` — which itself does nothing but
`appendFileSync` — is reachable afterward. **No 4th path found.**

### 2. Reproduction of the original finding — now rejected

```
$ node -e '... skill_id = "A".repeat(6000) ...' > input.json   # same 6221-byte-line repro as the FAIL report
$ AAI_FRICTION_SPOOL_DIR=.../spool node .aai/scripts/aai-friction.mjs record --input input.json
aai-friction: field 'skill_id' exceeds the maximum length of 128 characters
exit=3
$ ls .../spool/
(empty — no observations.jsonl ever created)
```

Boundary probes (not in the prior report, added for this re-review):
```
skill_id = 128 'B' chars  -> exit 0, line = 349 bytes         (at cap: accepted)
skill_id = 129 'C' chars  -> exit 3, "exceeds the maximum..."  (one over cap: rejected)
skill_id = skill_phase = 128 chars each, failure_class at its real enum value
                          -> exit 0, line = 463 bytes           (worst caller-controlled case, 9x under PIPE_BUF)
```

### 3. D6 deny-by-default — still sound

Re-ran the exact fixture from the original FAIL report (hostname,
absolute_path, repo_remote, username, project_id, forged os_family/aai_pin/
node_major, a novel scalar key, a nested object, an array) against the
current code: byte-identical persisted line to the prior run
(`{"schema_version":1,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"implementation","failure_class":"deterministic_script_failure","fingerprint":"v1:1fe3dda5862f44b821c403a5ee6f38d4"}`)
— the caps did not touch the D6 construction path at all, as expected since
`capField` only validates already-extracted short-path locals and the
`persisted` object literal is unchanged.

### 4. Concurrency at the cap boundary

Independently spawned 25 concurrent `record` processes (not the spec's 20)
against one spool, `skill_id` AND `skill_phase` both at the 128-char cap
(worst-case caller-controlled line, 463 bytes) -> exactly 25 lines, all
independently `JSON.parse`-able. TEST-019's own at-cap concurrency check (20
writers) reproduced green as well.

### 5. Suite / static checks

```
bash tests/skills/test-aai-friction.sh        -> 18/18 runnable tests PASS (incl. new TEST-019)
bash tests/skills/test-aai-layer-profiles.sh  -> ALL TESTS PASSED
grep -inE 'net|http|https|fetch|child_process|socket|gh ' aai-friction.mjs
  -> only the 2 documented 'network' prose lines (8, 81); no real primitive (unchanged)
git status --porcelain=v1 -uall vs. docs/ai/docs-audit.yaml protected_paths_l3
  -> no overlap
```

**Doc/code drift check (rationale correction, all three places):**
- `aai-friction.mjs` `appendLine()` comment (lines 284-296) now states the
  sub-PIPE_BUF bound is "ENFORCED, not assumed" via the caps + guard —
  matches the actual code below it.
- `FRICTION_PROTOCOL.md` gained an explicit "Atomic-append size guard"
  paragraph (lines 142-150) in the D6 allowlist section, and the schema
  table/prose (lines 66-78) documents the 128-char cap on the three
  persisted string fields — matches the code's `MAX_ID_LEN`/`capField`.
- The spec's Spec-AC-06 row and Edge-cases note (lines 158-176, 300-319) both
  carry the corrected two-step history (O_APPEND replacing read-modify-write,
  then the caps+guard replacing the false ~200-byte assumption) and cite the
  same 6221-byte/1.5x-PIPE_BUF repro this re-review independently
  reconfirmed is now rejected. No drift found between doc, spec, and code.

**TEST-011 header-comment nit (INFO in the prior report):** fixed — line 31
now reads "static: O_APPEND (appendFileSync) write path, no read-modify-write
of the spool," matching the function body. Confirmed via grep.

## Verdict 2 — code_quality: PASS (finding closed)

The prior BLOCKING finding is remediated and independently reverified sound
by construction, not merely patched for the exact reported repro: I traced
every one of the 8 persisted fields (not just the two originally named,
`skill_id`/`skill_phase`) to confirm each is either fixed-length/fixed-enum,
capped at validation before the persisted object is built, or — for the one
field with no explicit cap (`aai_pin`, project-controlled not caller-input)
— covered by the unconditional pre-append total-line-length guard that runs
before every `appendFileSync` call with no bypass path. No new findings
surfaced in this delta.

## Verdict 1 — spec_compliance: PASS

Unchanged from the prior review except Spec-AC-06, which now cites TEST-019
in addition to TEST-010/011/018 and whose supporting Edge-cases rationale is
corrected and independently confirmed accurate. All 12 Spec-AC rows
compliant.

## Overall: PASS

Both verdicts pass. No BLOCKING or NON-BLOCKING findings remain open from
this review. `cannot_verify` carries forward the full-suite-runner item
(unchanged, non-blocking per dispatch) and adds one INFO-level note (PIPE_BUF
threshold is a hardcoded conservative constant, not OS-queried — not a
concern given the caps hold real lines ~9x under it).
