---
review:
  scope: "working tree (uncommitted) — git diff main...HEAD + untracked: .aai/scripts/aai-friction.mjs (new), .aai/system/FRICTION_PROTOCOL.md (new), docs/ai/friction/.gitkeep (new, staged), .gitignore (+stanza), .aai/system/PROFILES.yaml (+2 entries), tests/skills/test-aai-friction.sh (new), docs/specs/SPEC-DRAFT-spec-friction-capture-foundation.md, docs/issues/CHANGE-DRAFT-friction-capture-foundation.md"
  spec: docs/specs/SPEC-DRAFT-spec-friction-capture-foundation.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-001 green; .aai/system/FRICTION_PROTOCOL.md has all five required section headers exactly once (verified independently: grep -cF each heading == 1)." }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-002/003/004 green; independently ran record with well-formed / missing-field / wrong-typed fixtures — exit 0 +1 line, exit 3 naming skill_id, exit 3 naming impact, spool unchanged on rejection." }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-005/006 green; independently crafted a fixture with hostname/absolute_path/repo_remote/username/project_id + forged os_family/aai_pin/node_major + 3 novel keys (incl. nested object and array) — persisted line: {schema_version,os_family:macos,aai_pin:unknown,node_major:22,skill_id,skill_phase,failure_class,fingerprint} — exactly the 8 allowlist keys, derived fields carry REAL local values (darwin->macos, process.versions.node major 22, AAI_PIN.md placeholder->unknown), all forbidden/novel/nested/array keys absent." }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-007/008 green; grep -inE 'net|http|https|fetch|child_process|socket|gh ' aai-friction.mjs -> only the two documented 'network' prose matches (lines 8, 73), no real primitive; no token/secret env read (grep for GH_TOKEN/GITHUB_TOKEN/SECRET -> none); ran record under HTTP(S)_PROXY pointed at 192.0.2.1:9 -> exit 0, line written." }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-009 green; fingerprint v1:-tagged, byte-identical inputs equal, case/whitespace-variant input normalizes to the same fingerprint." }
      - { ac: Spec-AC-06, call: "compliant (see BLOCKING code_quality finding for a caveat on the stated safety margin, not the AC's literal 3-way / N-way test text)", citation: "TEST-010/011/018 green; independently ran 20 concurrent record processes -> exactly 20 lines, all JSON.parse-able; source confirmed appendFileSync only, no readFileSync(target)/renameSync in the append path. See code_quality finding 1 — the doc/comment claim that a record is bounded to ~200 bytes 'well under PIPE_BUF' is falsifiable: skill_id/skill_phase are unbounded strings up to the 65536-byte input cap, and an accepted record with a 6000-byte skill_id produces a 6221-byte persisted line, >1.5x PIPE_BUF. AC-06's own literal verification text (3 sequential, N concurrent, source review) is satisfied; the Edge-cases note's supporting rationale is not." }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-012 green; independently ran `node aai-friction.mjs record --input bad.json && echo WRAPPER_OK` -> WRAPPER_OK never printed, exit 3, stdout empty; separately confirmed exit 2 for a missing --input arg and for an unknown subcommand, exit 3 for empty/unparsable JSON input — no code path returns 0 or an uncaught-exception default." }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-013 green; .gitignore stanza mirrors docs/ai/briefs//docs/ai/reports pattern (docs/ai/friction/**, !docs/ai/friction/, !docs/ai/friction/.gitkeep)." }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-014 green; `bash tests/skills/test-aai-layer-profiles.sh` independently re-run -> ALL TESTS PASSED; PROFILES.yaml grep confirms both new paths appear exactly once, both under `extended`." }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-015 green; `node .aai/scripts/aai-friction.mjs --help` exit 0, stdout contains record/--input/allowlist/network." }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-016 green; all 4 imports are node:-prefixed (node:fs, node:crypto, node:url, node:path); test file uses a full mktemp -d ...XXXXXX template." }
      - { ac: Spec-AC-12, call: compliant, citation: "17/17 runnable functions in tests/skills/test-aai-friction.sh pass (TEST-017 is the full-runner meta-assertion, not a function in this file, per the file's own header note); test-aai-layer-profiles.sh green; no *.prompt.md/AGENTS.md file touched by this scope (git status confirms only .aai/scripts/aai-friction.mjs, .aai/system/FRICTION_PROTOCOL.md, docs/ai/friction/.gitkeep, .gitignore, .aai/system/PROFILES.yaml, tests/skills/test-aai-friction.sh, plus intake/spec docs). Full 43-suite runner not executed here per dispatch instruction (CI is authoritative) — listed in cannot_verify." }
  code_quality:
    verdict: fail
    findings:
      - rank: BLOCKING
        file: .aai/scripts/aai-friction.mjs
        line: 262
        issue: "The atomicity rationale in the appendLine comment block (lines 262-271) and the spec's Edge-cases note both assert 'the D6 8-key allowlist bounds a record to ~200 bytes, well under PIPE_BUF' as the reason concurrent O_APPEND writes never interleave. This is false: the allowlist bounds the KEY SET, not the byte size. `skill_id` and `skill_phase` (both persisted, both allowlisted) are validated only for non-empty-string type (requireString, lines 132-144) with no per-field length cap — the only ceiling is the whole-input 65536-byte MAX_INPUT_BYTES check (line 45/115-117), which is >16x PIPE_BUF (4096 bytes)."
        failure_scenario: "Independently crafted a schema-valid input with skill_id = 6000 repeated 'A' characters (total input 6160 bytes, well under the 65536-byte cap) and ran `record` against a fresh spool: it was accepted (exit 0) and produced a 6221-byte persisted JSONL line — 1.5x PIPE_BUF. Under concurrent writers (the documented common case: 'the COMMON case under AAI parallel agents'), a write this large is not covered by the PIPE_BUF atomicity argument the code and spec both cite; whether Node's appendFileSync issues it as a single write(2) syscall (atomic on most local filesystems) or splits it (not atomic) is filesystem/kernel/Node-version-dependent and untested here — the code's own stated safety margin does not hold for accepted, in-spec inputs. A local 15-concurrent-writer stress test with this 6000-byte skill_id did not reproduce corruption on this machine/filesystem in one run, but that is not proof of safety on other platforms (e.g. NFS-backed CI runners, Windows/Git-Bash on NTFS) and contradicts the documented ~200-byte bound Spec-AC-06's Edge-cases note relies on. TEST-018's concurrency proof only exercises the small well-formed fixture (~260-byte line), never a large allowlisted field, so it does not actually test the boundary condition the code comments claim is safe."
    reranked_from: []
  cannot_verify:
    - { claim: "The full 43-suite project test runner is green after this change (part of Spec-AC-12's stated evidence).", closes_with: "CI run of the project's documented full runner (docs/TECHNOLOGY.md '## Testing'); dispatch explicitly instructs the reviewer not to block on this, CI is authoritative." }
    - { claim: "Concurrent writes of large (>PIPE_BUF) allowlisted-field records never interleave/corrupt the spool on Linux CI, Windows/Git-Bash, or NFS-backed filesystems (the specific platforms Spec-AC-11 requires portability on).", closes_with: "A targeted stress test with a large skill_id/skill_phase (e.g. 6000+ bytes) run under N>=20 concurrent writers on each target platform/filesystem, checked for corrupted/interleaved JSONL lines; alternatively, close by adding an explicit length cap that restores the documented PIPE_BUF margin, which would make this claim moot." }
    - { claim: "aai_pin cannot itself become large enough to threaten the PIPE_BUF margin in practice.", closes_with: "AAI_PIN.md is a project-controlled file (not caller input), so this is low-risk today, but nothing in the code enforces a length cap on the Template version line either — noted for completeness, not required to close this review." }
  overall: fail
---

# Code Review — RFC-0012 Phase 0: friction capture foundation

**Role:** Code Review (L2 full lane, one pass, independent reviewer)
**Branch:** feat/friction-capture-foundation
**Ref:** friction-capture-foundation
**Started (UTC):** 2026-07-25T00:49:33Z
**Report written (UTC):** 2026-07-25T00:52:36Z

## Scope preflight
Working tree is the scope per dispatch (nothing committed yet). `git status --porcelain=v1 -uall`:
```
 M .aai/system/PROFILES.yaml
 M .gitignore
A  docs/ai/friction/.gitkeep
?? .aai/scripts/aai-friction.mjs
?? .aai/system/FRICTION_PROTOCOL.md
?? docs/issues/CHANGE-DRAFT-friction-capture-foundation.md
?? docs/specs/SPEC-DRAFT-spec-friction-capture-foundation.md
?? tests/skills/test-aai-friction.sh
```
Matches the dispatch's declared in-scope file list exactly. No later-phase code
(triage/upsert/maintainer/network/`.aai/feedback.yaml`) present anywhere in the
diff — confirmed by reading the full `aai-friction.mjs` source and grepping for
network/gh/child_process primitives (none beyond documented prose).

## Verdict 1 — spec_compliance: PASS

All 12 Spec-AC rows walked against independently reproduced evidence (not just
re-reading the "done"/green cells in the spec table). Full walk in the
structured block above. Every AC's literal verification text is satisfied.
Spec-AC-06 is marked compliant against its literal test text (3 sequential + N
concurrent + source review, all independently reproduced), but the Edge-cases
note's supporting *rationale* ("~200 bytes, well under PIPE_BUF") is
demonstrably false for schema-valid inputs — carried into code_quality finding
1 below rather than failing this verdict outright, since the AC's literal
pass/fail test criteria (line counts, parseability, appendFileSync-not-rename)
were met in every run performed.

Table pipe-safety (SPEC-0072 hazard, explicitly named in the dispatch given the
concurrency-remediation edit touched TEST-018 and Spec-AC-06): independently
recounted `|` per row for both the Acceptance Criteria Status table and the
Test Plan table — every row matches its header's column count (7 pipes) with
no drift.

Companion-obligations / PROFILES.yaml / no-prompt-diet checks: both new
`.aai/**` files (`aai-friction.mjs`, `FRICTION_PROTOCOL.md`) are classified
exactly once each, both under `extended`; `bash tests/skills/test-aai-layer-profiles.sh`
independently re-run, green (`=== ALL TESTS PASSED: aai-layer-profiles ===`).
No `*.prompt.md` or `AGENTS.md` file appears anywhere in the scope.

## Verdict 2 — code_quality: FAIL

**Finding 1 (BLOCKING) — false atomicity safety-margin claim; no length cap on
allowlisted string fields.** See the structured block for the full citation
and failure scenario. Summary: `aai-friction.mjs` lines 262-271 (and the
spec's Edge-cases note, and FRICTION_PROTOCOL.md's redaction-policy framing of
"coarse by design") all lean on a claim that a persisted record is bounded to
roughly 200 bytes, safely under the 4096-byte PIPE_BUF concurrent-write
atomicity threshold. That claim conflates "the KEY SET is a fixed 8-key
allowlist" with "the record's BYTE SIZE is bounded" — it is not. `skill_id`
and `skill_phase` are validated only as non-empty strings (no max length);
the only ceiling on them is the 65536-byte whole-input cap, 16x larger than
PIPE_BUF. I independently proved this is reachable with a fully schema-valid,
accepted input (a 6000-byte `skill_id`, 6160-byte total input, well inside the
64KB cap) that produced a 6221-byte persisted spool line. This is exactly the
class of finding the dispatch asked to hunt for ("if an allowlisted string
field is unbounded, a >4096B line could interleave — assess and flag if
real") — it is real. I could not force observable corruption in a single
local 15-writer stress run on this machine's filesystem, so I am not claiming
demonstrated data loss; I am flagging that the code's own stated safety
argument for why concurrent large writes are safe is false, which fails
Verdict 2's "concrete failure scenario" bar via the failure mode itself
(unproven/unbounded write atomicity for an accepted input), independent of
whether I could reproduce corruption in one run. **Recommended remediation:**
add an explicit per-field length cap on `skill_id`/`skill_phase` (e.g. 200-256
bytes, matching the "coarse by design" spirit already stated for `os_family`/
`aai_pin`/`node_major`) enforced as a schema-v1 validation rejection (exit 3,
naming the field, no spool write) — this both closes the gap and makes the
existing PIPE_BUF rationale in the code comment and spec actually true again.
Alternatively, if the safety argument is meant to rest on O_APPEND's general
POSIX atomicity for local filesystems regardless of size (a defensible but
different argument), the code comment and spec text should be corrected to
say that instead of citing a numeric bound that is not enforced.

No other code_quality findings survived verification. Specifically checked
and found sound:
- **D6 construction:** `persisted = { ...8 literal keys... }` (lines 308-317)
  is a fresh object literal built from named locals (`SCHEMA_VERSION`,
  `deriveOsFamily()`, `deriveAaiPin()`, `deriveNodeMajor()`,
  `fields.skillId/skillPhase/failureClass`, `computeFingerprint(fields)`) —
  never a spread of the caller's object, never delete-from-copy. Hunted for
  alternate paths: no nested object, array, error branch, or fallback reaches
  the spool with caller-supplied keys — `validate()` returns a fixed
  5-field object (`{skillId, skillPhase, failureClass, expected, observed}`)
  that itself never carries extra caller keys forward, and only 3 of those 5
  fields (`skillId`, `skillPhase`, `failureClass`) are copied into `persisted`;
  `expected`/`observed` feed only `computeFingerprint`, never the spool line
  directly — confirmed by reading `record()` end to end and by the TEST-005/
  006 fixtures above (nested object + array injected keys, both absent from
  output).
- **Concurrency mechanism:** `appendFileSync` only; no `readFileSync(target)`
  or `renameSync` anywhere in the file (grep confirmed); 20 independently
  spawned concurrent `record` processes against one spool -> exactly 20
  parseable lines, matching TEST-018.
- **No network / no token:** confirmed by grep and by an offline run under
  unroutable `HTTP_PROXY`/`HTTPS_PROXY`.
- **Schema validation / capture-never-masks / fingerprint versioning:**
  reproduced independently (missing-field, wrong-type, malformed-JSON,
  empty-input, missing-`--input`, unknown-subcommand cases; exit codes 0/1/2/3
  each land where documented; fingerprint `v1:`-tagged and
  normalization-stable).
- **Zero deps / portability:** all 4 imports are `node:`-prefixed; no
  `require()`; no platform-specific path construction beyond
  `path.join`/`resolve` (cross-platform by construction).

## Protocol doc quality (advisory, folded into code_quality context)

`FRICTION_PROTOCOL.md` accurately documents the taxonomy, schema v1, the D6
allowlist, the fingerprint v1 algorithm, and the redaction policy, and matches
the CLI's actual behavior in every respect checked — **except** it repeats the
same "well under PIPE_BUF"/size-bound framing question implicitly via the
"coarse by design" language in the Redaction section, which is accurate for
the three *derived* fields (`os_family`/`aai_pin`/`node_major`) but does not
mention that the two *caller-supplied* persisted fields (`skill_id`,
`skill_phase`) carry no such bound. Not a separate finding — same root cause
as code_quality finding 1.

**Minor doc drift (not filed as a ranked finding — no failure scenario, purely
informational):** `tests/skills/test-aai-friction.sh` lines 24 and 31 (header
comment / test map) still describe TEST-011 as "static: temp-file + rename
write path present," a leftover from before the O_APPEND concurrency
remediation. The actual `test_011_atomic_append_static` function (lines
471-485) correctly asserts the opposite (appendFileSync present,
readFileSync/renameSync absent) and passes. Since this is a comment-only
mismatch with no behavioral or verification impact, it is INFO, not a
BLOCKING/NON-BLOCKING finding — noted here for the implementer to fix in the
same pass as finding 1, not tracked separately.

## Evidence log (commands run, independent of the spec's own TEST-xxx claims)

```
bash tests/skills/test-aai-friction.sh          # 17/17 runnable tests PASS
bash tests/skills/test-aai-layer-profiles.sh    # ALL TESTS PASSED

# D6 independent fixture (forbidden identity keys + forged derived fields +
# novel scalar/nested/array keys):
$ AAI_FRICTION_SPOOL_DIR=.../d6/spool node .aai/scripts/aai-friction.mjs record --input .../d6/input.json
recorded v1:1fe3dda5862f44b821c403a5ee6f38d4
$ cat .../d6/spool/observations.jsonl
{"schema_version":1,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"implementation","failure_class":"deterministic_script_failure","fingerprint":"v1:1fe3dda5862f44b821c403a5ee6f38d4"}
# real local values for cross-check: darwin/22 ; AAI_PIN.md Template version = "<set by sync script>" -> unknown

# Concurrency (20 concurrent writers, small fixture):
PASS: Concurrent records: 20 concurrent writers -> exactly 20 well-formed lines, no loss (TEST-018)

# Large allowlisted-field probe (the finding):
$ wc -c .../bigfield/input.json
    6160 .../bigfield/input.json    # skill_id = 6000x'A', schema-valid, accepted
$ AAI_FRICTION_SPOOL_DIR=.../bigfield/spool node .aai/scripts/aai-friction.mjs record --input .../bigfield/input.json
recorded v1:95bcec2b6ace4669387a956f5766814a
$ wc -c .../bigfield/spool/observations.jsonl
    6221 .../bigfield/spool/observations.jsonl   # > PIPE_BUF (4096), contradicts code/spec's stated ~200-byte bound

# No network / no token:
$ grep -inE 'net|http|https|fetch|child_process|socket|gh ' .aai/scripts/aai-friction.mjs
8://   tool holds no token and performs no network I/O.
73:  - Offline: no token and no network access is ever used.
   (both are the documented 'network' prose false positive; no real primitive)

# Exit-code contract spot checks:
empty --input file       -> exit 3 (input is not valid JSON)
missing --input arg      -> exit 2 (record requires --input <path|->)
unknown subcommand       -> exit 2 (unknown subcommand: bogus)
```

## Next steps
1. Remediate code_quality finding 1 (BLOCKING): add a length cap on
   `skill_id`/`skill_phase` (or otherwise restore/correct the PIPE_BUF safety
   argument in both the code comment and the spec's Edge-cases note), with a
   RED-proofed regression test (e.g. an oversized-`skill_id` fixture ->
   clean rejection, exit 3, field named).
2. Optionally fix the stale TEST-011 header-comment description in
   `tests/skills/test-aai-friction.sh` (INFO, not blocking).
3. Re-request review after remediation; this report's overall verdict is
   `fail` solely on finding 1 — spec_compliance already passes.
