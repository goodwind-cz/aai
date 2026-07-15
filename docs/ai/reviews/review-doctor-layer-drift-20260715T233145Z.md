# Code Review — CHANGE doctor-vendored-layer-drift

- Scope: worktree `feat/doctor-layer-drift` (uncommitted) @ /Users/ales/Projects/aai-feat-layer-drift
- Base ref: main
- Head ref: WORKTREE (uncommitted)
- Reviewer model: claude-fable-5 (independent review role)
- Reviewed: 2026-07-15T23:31:45Z
- Verdict: **FAIL** (one BLOCKING defect — false-green under paths containing a space/URL-reserved char)

## Model independence note
The Implementation run recorded in STATE was `claude-fable-5`; this reviewer is
also `claude-fable-5`. Validation was independent (`claude-sonnet-5`). The
maker≈checker overlap on THIS review reduces model diversity — the BLOCKING
finding below was nonetheless reproduced by direct execution, not left to code
reading.

## Diff scope reviewed
Modified (git diff): `.aai/SKILL_DOCTOR.prompt.md`, `.aai/scripts/aai-sync.sh`,
`.aai/scripts/aai-sync.ps1`, `.aai/scripts/aai-update.sh`,
`.aai/system/AAI_PIN.md`, `docs/INDEX.md` (generated), `docs/ai/EVENTS.jsonl`
(append-only).
New (read in full): `.aai/scripts/layer-drift.mjs` (283 L),
`tests/skills/test-aai-layer-drift.sh` (354 L),
`docs/specs/SPEC-DRAFT-doctor-vendored-layer-drift.md`,
`docs/issues/CHANGE-DRAFT-doctor-vendored-layer-drift.md`.

---

## STAGE 1 — Spec compliance & scope

Verdict: **COMPLIANT** on all 6 Spec-AC; D1 amendment sound; no over/under-build.

- Spec-AC-01..06 each map to green tests; full suite re-run here = 13/13 PASS,
  exit 0 (TEST-001..011 + no-network self-check).
- D1 pin-contract extension: the CHANGE draft (Scope, lines 32-36) was amended
  to bring the AAI_PIN `Canonical repo` field and the sync-script pin-writer
  block IN scope, while keeping sync/update *behavior* out of scope. The
  amendment is internally consistent and correctly narrow: the sync change is
  purely additive (one derived var + one heredoc line in each of sh/ps1), and
  `aai-update.sh` only widens an evidence grep (`canonical` added). No behavior
  change to sync/update beyond the stamp/evidence line. The amendment is sound.
- Resolution order (D2), distance tiers (D3), degrade-and-report (D4),
  fixture-only tests (D5) all implemented as specified.
- No over-build: no hardcoded upstream fallback (deliberate, per D2), no fetch,
  read-only. No under-build: both sync scripts stamp; ps1 parity is asserted
  (static grep) and update-evidence parity asserted.

---

## STAGE 2 — Defects (ranked)

### BLOCKING

**B1 — False "up-to-date" (silent no-op) when the project path contains a
space or any URL-reserved char.** `.aai/scripts/layer-drift.mjs:281`

```
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
```

`new URL(import.meta.url).pathname` stays **percent-encoded**
(`/Users/.../space%20dir/layer-drift.mjs`), whereas `process.argv[1]` is the
**decoded** path (`/Users/.../space dir/layer-drift.mjs`). `path.resolve` does
NOT decode `%20`, so the two never compare equal and `main()` never runs.

Reproduced (this review, not theory):
```
$ node "/tmp/ld-probe/space dir/layer-drift.mjs" --pin <equal-pin>
# stdout: (empty)   rc=0
$ node "/Users/.../aai-feat-layer-drift/.aai/scripts/layer-drift.mjs" --pin <same-pin>
# stdout: layer up-to-date (pin f742678 == canonical main)   rc=0
```

Failure scenario: a vendored project at a path containing a space (common on
macOS/Windows — `~/Documents/My Project`, `Application Support`, non-ASCII user
names) runs `node .aai/scripts/layer-drift.mjs`. The script prints **nothing**
and exits **0**. SKILL_DOCTOR CAT-13 maps exit 0 → "✓ layer up-to-date". The
doctor reports the layer GREEN while having verified nothing — i.e. it silently
masks real drift. That is precisely the "vendored layer silently ages" failure
this entire change exists to eliminate; the guard defeats the feature for a
whole class of install paths.

Fix (trivial, matches repo convention): use `fileURLToPath(import.meta.url)` —
every other script in `.aai/scripts/` already does this
(`orchestration-mode.mjs:338`, `orchestration-dispatch.mjs:538`,
`metrics-flush.mjs:68`, `docs-audit.mjs:151`). Import it from `node:url`.
Regression coverage: the suite runs the script only from its no-space repo path,
so it cannot catch this — add a case that copies the script under a
`"dir with space"` and asserts a verdict line is emitted.

### NON-BLOCKING

**N1 — Garbage / unparseable pin sha is reported as "drift" (exit 3), not
"unverifiable".** `layer-drift.mjs:201-206` (local tier) and `:245-254`
(remote tier). A pin `Template commit: deadbeefgarbage` yields
`layer drift: pin deadbee not found in canonical 'main' history (unknown
distance) — run /aai-update`, exit 3. This is defensible (conservative: an
unrecognizable pin can't be confirmed up-to-date, so nudging /aai-update is
safe) and matches spec D3 ("pin unknown to canonical history → drift"). Flagged
only because a corrupt pin is arguably `unverifiable` rather than `behind`.
No action required.

**N2 — Quoted URL value is not unquoted.** `parsePin` keeps surrounding double
quotes verbatim: `- Canonical repo: "https://x/y.git"` parses to
`"\"https://x/y.git\""`, which git ls-remote then rejects → clean
`unverifiable`. The sync scripts never emit quotes, so this only bites a
hand-edited pin, and it degrades safely (no crash). Optional hardening: strip a
single matched pair of surrounding quotes.

**N3 — Pin marker is case-sensitive** (`layer-drift.mjs:103`). `- canonical
repo:` (lowercase) is ignored. The sync scripts always write the exact
`Canonical repo:` casing, so no real-world impact; noted for completeness.

## Explicitly cleared (probed, NOT defects)

- **Shell-injection via pin-supplied URL:** none. All git calls go through
  `spawnSync('git', argsArr, …)` (args array, no shell). An SSH-form
  `git@github.com:org/repo.git` pin is correctly NOT treated as a local dir
  (regex `:135`), routed to `ls-remote`, and with `GIT_TERMINAL_PROMPT=0` it
  fails fast to `unverifiable` exit 4 — verified.
- **Unrelated local repo via stale `Source path` → false BEHIND:** cannot
  happen. A pin sha absent from the unrelated repo → "not found in history,
  unknown distance" exit 3 (distance null). "BEHIND by N" requires the pin to
  be a genuine `merge-base --is-ancestor` of that repo's ref; unrelated
  histories are never ancestors → diverged/unknown, never a fabricated N.
  Verified with an independent-history fixture (relation `unknown`,
  `distance: null`).
- **CRLF pins (Windows sync):** handled — `parsePin` strips trailing `\r`
  (`:102`). Verified.
- **`Canonical repo: UNKNOWN` round-trip (local-only template with no origin):**
  sync stamps `UNKNOWN`; `parsePin` treats `UNKNOWN` and `<...>` placeholders
  as absent (`:106`); D2 then falls back to `Source path`, else degrades to
  `unverifiable`. Verified.
- **`mkdir -p` hardening:** both sync scripts create the pin's parent dir
  before writing (`aai-sync.sh` `mkdir -p "$DST_ROOT/.aai/system"`;
  `aai-sync.ps1` `New-Item -Force`) — matches validation's reproduced fix.
- **SKILL_DOCTOR CAT-13 wording vs exit codes:** consistent. exit 0→✓,
  3→⚠+/aai-update, 4→⚠ info, 2/missing→⚠ unavailable. Documented
  informational/never-BROKEN; OUTPUT FORMAT line present. Network bound (one
  ls-remote, 10s) is stated; the script self-bounds every git subprocess via
  `timeout` — no unbounded hang.
- **Tests — tautology / scratch leak:** no tautologies (each asserts exit code
  + a substring of the verdict, and TEST-010 crosses the sync→drift seam
  end-to-end with a real `aai-sync.sh` run). `trap cleanup EXIT` with
  `rm -rf "$TMP_ROOT"` cleans fixtures even on `log_fail` (which `exit 1`s and
  fires the trap). No leak.

## Cross-stream / merge-collision check
This diff's code files (`SKILL_DOCTOR.prompt.md`, `aai-sync.sh`, `aai-sync.ps1`,
`aai-update.sh`, `AAI_PIN.md`, `layer-drift.mjs`,
`tests/skills/test-aai-layer-drift.sh`, the CHANGE/SPEC drafts) do **not**
overlap either sibling stream:
- `feat/dual-verdict-review` touches `SKILL_CODE_REVIEW.prompt.md`,
  `SUBAGENT_PROTOCOL.md`, `AGENTS.md`, `ROLES.md`, aai-code-review SKILL.md
  mirrors, `test-aai-hygiene-pack.sh`, and its own drafts — disjoint.
- `fix/issue-0007-list-append` touches `check-state.mjs`, `state-engine.mjs`,
  `metrics-flush.mjs`, `STATE_FALLBACK.md`, its own tests/draft — disjoint.
- Shared collisions at merge time: `docs/INDEX.md` (all three regenerate — heal
  by re-running `generate-docs-index.mjs`) and `docs/ai/EVENTS.jsonl` (this
  stream + issue-0007 append; append-only, union-merge). Both mechanical,
  non-blocking.

---

## Overall: FAIL
One BLOCKING defect (B1) — resolve by switching the main-guard to
`fileURLToPath(import.meta.url)` and adding a space-in-path regression case,
then re-review. Everything else is compliant and robust.
