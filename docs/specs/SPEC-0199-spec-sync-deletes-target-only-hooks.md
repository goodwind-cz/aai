---
id: spec-sync-deletes-target-only-hooks
type: spec
number: 199
status: done
frozen_sha256: 05f32e4633970cfb2321d741f670546db5056ca613a7d43391b8e5fed1da87e8
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0089-sync-deletes-target-only-hooks.md
  rfc: null
  pr:
    - TBD
  commits:
    - 1efec5f88d26d3d9e53b4bda36455e8c7097513c
---

# Spec — aai-sync preserves target-only hooks and reports its deletions

SPEC-FROZEN: true

## Amendment (owner-directed, relayed via coordinator instruction, 2026-09-30)

This is a FROZEN spec, amended under owner authority mid-implementation —
not a quiet rewrite. The owner's own words, as relayed: "it simply must not
overwrite the user-modified hook — you must find a way." A
`decisions.jsonl` `hitl_decision` / `spec_amendment` ledger record for this
amendment is filed by the orchestrator against this evidence (implementation
is a dispatched subagent and does not write ledgers on its own authority);
this section is the disclosure the ledger record points at.

**What changed and why.** The original Scope decision below ("the
JSON-registration half") rejected an additive JSON merge on the ground that
the sync engine has no Node dependency and adding one is a design decision,
not a hotfix — so `hooks/hooks.json` / `hooks/hooks.windows.json` stayed
source-owned and wholly overwritten, with the loss only made VISIBLE via the
advisory (Spec-AC-04, old). That justification's premise 2 is factually
wrong: an additive, non-destructive JSON-hooks merge ALREADY EXISTS in this
repository, reviewed and shipped —
`.aai/scripts/aai-bootstrap.sh`'s `install_claude_hooks` (`--with-claude-hooks`
path, RFC-0010 / spec-hook-enforced-gates). Its semantics are exactly what
this scope needs: parse template and destination JSON, refuse loudly and
touch nothing when either is malformed or `hooks` is a non-object key
(Review NB-1), add only hooks whose `command` is not already present, find
or create the matching `matcher` entry, NEVER remove or rewrite a
destination entry, write only when something was added (idempotent), and
degrade to a WARN + skip — never a destructive fallback — when `node` is
unavailable. This spec now REUSES that exact algorithm, extracted into one
shared file (`.aai/scripts/lib/merge-hooks-json.mjs`) that both
`install_claude_hooks` and `aai-sync.(sh|ps1)` call, rather than re-typing a
second dialect of the same merge.

**Consequences, stated so nothing is left implicit:**
1. `hooks/hooks.json` and `hooks/hooks.windows.json` are no longer
   source-owned-and-overwritten. They are MERGED: a source hook not already
   present in the target is appended; a TARGET-ADDED entry (one whose script
   path the source does not ship) is NEVER removed or rewritten. This is now
   a HARD requirement, not a residual risk: the reporter's
   `PreToolUse -> merge-guard.sh` registration survives. (Amendment 2 below
   narrows what "never rewritten" covers for SOURCE-OWNED entries: one the
   engine can prove it wrote is updated in place; one it cannot prove is
   left as-is.)
2. `aai-sync.sh` now calls `node` (previously zero calls — evidence 9 below
   recorded that as a measurement of the pre-change tree; it is still true
   AS A MEASUREMENT, but the conclusion drawn from it in this section's
   original justification point 2 no longer holds). Node absence degrades
   exactly like `install_claude_hooks` does: WARN, leave the target file
   untouched (create nothing on a fresh target either), name it in the
   advisory. A missing interpreter never disarms the merge by falling back
   to overwrite.
3. **Retirement is reversed, not preserved.** The original Scope decision
   ("how target-only, keep is told from source removed it, drop it") relied
   on wholesale overwrite to disarm a retired hook's registration. The merge
   never REMOVES anything — so a target's EXISTING registration for a hook
   the source has since retired now SURVIVES indefinitely, and so does the
   hook's file (file survival was already the rule; registration survival is
   new). Retirement — making a stale registration disappear — is NOT handled
   by this amendment. This is a REGRESSION relative to the pre-amendment
   implementation's disarm-via-overwrite property, accepted deliberately:
   the owner's explicit priority (never destroy a user-modified hook)
   outranks the softer, already-acknowledged-as-imperfect retirement story.
   Stated as a residual risk below, not left as a silently false sentence.
   (Amendment 2's shipped-snapshot makes retirement SOLVABLE with the same
   proof it uses for updates; it is still not DONE here — see Residual
   risks.)
4. A NEW `.aai/**` file is introduced — `.aai/scripts/lib/merge-hooks-json.mjs`
   — reversing the original "Companion obligations" claim that none would be
   added. It is classified in `.aai/system/PROFILES.yaml` `core:` (companion
   obligations, updated below).
5. `tests/skills/test-aai-hooks-overlay.sh` joins the regression set
   (Spec-AC-09 / TEST-781): `install_claude_hooks` now calls the same shared
   library this scope introduces, so that suite guards this change too.
6. The follow-up `fu-hooks-json-target-entries-lost` this spec originally
   suggested filing is SUPERSEDED — filing it would now be wrong, since the
   registration-merge gap it named is closed by this amendment.

Every AC, Test Plan row, Scope decision and citation below that depended on
the superseded overwrite-and-flag design is updated in place to describe the
additive-merge design; the original text is corrected rather than left to
stand beside contradicting new text, and each edited section says so.
Unaffected material — Spec-AC-01/02/03/05/06, the target-only FILE
preservation rule, the deletions category, the byte-identity guard for quiet
runs — is untouched by this amendment.

## Amendment 2 (owner-directed scope extension, relayed via Remediation dispatch, 2026-09-30)

Validation (report `VALIDATION-20260930T094000Z`, NB-1) measured a second
consequence of additive-ONLY merge that the first amendment did not name: a
source that CHANGES an already-registered hook's `command` string — an
ordinary release edit, far likelier than retirement — shipped the new command
as an ADDITION and left the old one registered. Measured: two `SessionStart`
entries after a v2 sync, one pointing at a file the source no longer ships,
accumulating one stale entry per edit in every downstream target. The owner's
decision, as relayed: SOLVE IT NOW by matching on a stabler key than the exact
command string — the script PATH inside the command — and updating the
source-owned entry in place. The ledger record for this amendment is filed by
the orchestrator against this section (Remediation is a dispatched subagent
and does not write ledgers).

**The rule, and the tension it resolves.** "Update the source-owned entry in
place" collides with the owner's standing priority ("a user-modified hook is
never overwritten") whenever the target's entry for a source-owned path
DIFFERS from what the source now ships: from the two files alone it is
impossible to tell whether the user edited that entry or an older source
shipped it. The rule chosen, stated once here and implemented once in
`.aai/scripts/lib/merge-hooks-json.mjs`:

1. A source hook whose exact `command` is already present in the target's
   event is skipped (idempotent; unchanged).
2. Otherwise the hook is keyed on the first path-like token inside its
   command (quotes and `${VAR}` prefixes kept as written, backslashes
   normalised to `/`; for the shipped commands this is the script path —
   Amendment 3 / Residual risk 1d state where it is not). A target hook in
   the same event with the same key but a different command is the SAME
   registration, edited by someone.
3. (CORRECTED by Amendment 3) That target hook is UPDATED IN PLACE only
   when the engine can PROVE it is unmodified engine output: the sync
   engine records, after every successful merge, a verbatim copy of the
   source file it merged — the "shipped snapshot" at
   `<target>/.aai/cache/hooks-shipped/<file>` — and the target's WHOLE
   registration must equal that snapshot's for the key: the hook object in
   every field (canonical JSON, not just `command`) AND the enclosing
   group's `matcher`. Only then does rewriting it destroy nothing anyone
   authored. If the source's `matcher` changed too, the hook moves to the
   source's matcher group. (Amendment 2 originally proved the `command`
   alone; Validation round 2 measured that this silently dropped a
   user-edited matcher or a user-added `timeout`/`async`.)
4. In EVERY other same-key-differing case — no snapshot (a target last
   synced by a pre-#414 engine, a fresh clone whose gitignored `.aai/cache/`
   is empty, another machine), a snapshot that disagrees with the target in
   ANY field or in the matcher, or more than one candidate on either side —
   the owner's priority wins: the target entry is LEFT AS-IS, the source's
   version is NOT added beside it (that is the accumulation the update
   exists to stop), and the case is named in the advisory with both
   commands quoted and the differing fields or matcher named. Never a
   silent rewrite.
5. A target entry whose path the source does not ship at all is never
   touched, in every case — the property this whole ride exists to deliver.
6. A source event carrying two hooks with the same key (the bootstrap
   overlay template: one adapter script, three argument sets) cannot be
   paired by key; those hooks fall back to exact-command matching only —
   never a guessed update.
7. A target file that does not exist yet is created as a byte-for-byte copy
   of the source file (Validation NB-4: a re-serialised copy diverged from
   the source bytes on any reformat).

Why a snapshot and not a marker inside the JSON: the harness reads
`hooks.json` as a runtime contract, and an unknown key on a hook object is
not something this spec can prove every consumer tolerates. Why not git
history: `aai-update.sh` clones the source with `--depth 1`, so the previous
source's bytes are not reachable. The snapshot is runtime state, not
vendored content: `.aai/cache/` is already gitignored by both engines,
excluded from `PROFILES.yaml` classification and from the core-profile
prune, and preserved across syncs. Its absence degrades to rule 4 (report,
never rewrite) — safe by construction. A snapshot the engine could not
WRITE after a merge that did happen is reported as exactly that (Amendment
3, NB-A): the merge stands, the run says so, and the next sync degrades to
rule 4 until the path is writable — never a "left untouched" claim for a
file that was written.

**Consequences, stated so nothing is left implicit:**
1. "An existing target entry is NEVER rewritten" (Amendment 1, consequence
   1) is narrowed: a SOURCE-OWNED entry that is byte-equal to what this
   engine last shipped IS rewritten when the source changes it. Every other
   entry keeps the first amendment's guarantee. Spec-AC-04 and Spec-AC-08
   are unaffected (target-added and retired entries are never touched).
2. The first amendment's claim that "target-added needs no identity
   tracking because nothing is ever removed" is superseded: identity is now
   the (event, script path) key plus the shipped snapshot as provenance. No
   identity marker is written into the JSON itself.
3. `aai-bootstrap.sh`'s `--with-claude-hooks` overlay shares the library and
   therefore the rule, but passes NO snapshot (`.claude/settings.json` is
   user-owned), so it never updates: a same-key-differing entry there is
   left as-is and named on stdout instead of being added beside — the
   shipped template's three same-script hooks are ambiguous under rule 6
   and keep today's exact-command behaviour, so the shipped overlay is
   unchanged in practice.
4. A missing merge library under an EXPLICIT `--with-claude-hooks` now
   FAILS bootstrap (exit 3, nothing written) instead of warn-and-succeeding
   — the Review-NB-1 rule the refusal branch already followed (Validation
   NB-3). The older missing-template / missing-node guards keep their
   warn-and-succeed shape: changing them is a separate decision, named in
   Residual risks rather than slipped in.
5. The `WARN node unavailable` / `WARN merge library missing` / merge-refused
   lines are on STDOUT in both engines (Validation NB-2: bash wrote them to
   stderr while Spec-AC-11 and the .ps1 engine said stdout); the test now
   captures the two streams separately so it can tell.
6. Advisory text for the two JSON files names paths relative to the target
   and source roots, never the machine's absolute layout (Validation NB-5).
7. `tests/skills/test-aai-layer-profiles.sh` TEST-002's old-vs-new tree diff
   now excludes `.aai/cache/` (the snapshot the old engine never wrote), the
   same exclusion its own `aai_files_of` already applied — a test-filter
   change in scope, disclosed here.
8. The merge summary line changed shape to carry the two new counters:
   `<n> hook(s) added, <u> updated, <m> already present, <k> left as-is ->
   <path>`; `aai-bootstrap.sh`'s idempotence classification reads the first
   two counters.

## Amendment 3 (Validation round 2 findings, applied by Remediation round 2, 2026-09-30)

Validation round 2 (report `VALIDATION-20260930T141839Z`) reproduced on
both engines that Amendment 2's update path proved provenance on the
`command` string ONLY and then replaced the WHOLE hook object — relocating
it into the source's matcher group — so a user who had narrowed the shipped
hook's `matcher` (to `startup`), or added `timeout: 120` / flipped
`async: true` on it, lost that edit silently on the next source-side
command change, reported as `1 updated` with no advisory entry
(BLOCKING-3). That contradicted Spec-AC-13's own words and the owner's
standing invariant. This amendment makes the guarantee TRUE rather than
re-wording it; the ledger record is filed by the orchestrator against this
section (Remediation is a dispatched subagent and does not write ledgers).

**The provenance rule, corrected (replaces Amendment 2 rule 3's proof).**
A target entry is provably unmodified engine output — and therefore may be
rewritten or relocated — only when its WHOLE registration equals the shipped
snapshot's for that key: the hook object in every field, compared as
canonical JSON (key order ignored; `command`, `type`, `async`, `timeout`
and any other key all count), AND the enclosing group's `matcher`. Any
difference in any field or in the matcher, a missing snapshot, or an
ambiguous candidate set falls to rule 4: left as-is, not added beside,
named in the advisory with the differing fields or the user's matcher
quoted. Why the whole object and not a widened field list: the harness reads
`hooks.json` as a runtime contract and this spec cannot enumerate every key
a consumer honours, so the only proof that "rewriting destroys nothing
anyone authored" is that NOTHING in the registration differs from what the
engine itself wrote. Cost: none in the shipped case — the engine writes the
entry verbatim, so an untouched entry still compares equal.

**Two non-blocking findings fixed in the same round, disclosed here:**
1. (NB-A) A shipped snapshot the engine could not WRITE after a merge that
   DID write the target (its path was a directory, its parent a file,
   EACCES) made the library throw, and both engines then reported "merge
   refused (target left untouched)" for a target that was written — a
   control stating the opposite of what happened. The destination merge is
   the act; the snapshot is bookkeeping whose only failure consequence is
   that the next run has no proof and degrades to rule 4 (already "safe by
   construction"). So the library now returns the snapshot failure instead
   of throwing (`SNAPSHOT-NOT-RECORDED <path>: <error>` on stdout, exit 0),
   both engines print the true MERGE line plus a WARN naming the unrecorded
   snapshot, and the advisory entry says the merge was applied and the
   snapshot was not recorded (Spec-AC-17, TEST-792). The alternative —
   writing the snapshot BEFORE the destination — was rejected: it would
   refuse a legitimate merge (and refuse to create `hooks.json` on a fresh
   target) because a cache directory is unwritable, and a snapshot written
   ahead of a destination write that then failed would make the target look
   user-edited forever. The remaining refusal paths all throw BEFORE any
   write, so "left untouched" is true wherever it is still printed.
2. (NB-B) The bash engine's two `hooks/` loops globbed without `dotglob`,
   so a source `hooks/.hidden-hook.sh` was silently dropped and a
   target-only `hooks/.local-only.sh` was kept but never named — where the
   pre-#414 `cp -a` and the `.ps1` engine (`Get-ChildItem -Force`) both
   handle dotfiles. `aai-sync.sh` now sets `dotglob` around exactly those
   two loops and restores the caller's setting afterwards (Spec-AC-16,
   TEST-791).

**Disclosed, not changed (NB-C):** the pairing key is the FIRST path-like
token in the command, not "the script path" — see Residual risks 1d. Its
measured error direction is safe (left-as-is or add beside, never a
rewrite), and narrowing the regex would widen this round's scope.

**Consequences:** Spec-AC-12 and Spec-AC-13 are re-worded to the whole-
registration proof and Spec-AC-13 gains arms (c) and (d); Spec-AC-07 gains
Spec-AC-17; Spec-AC-16 and Spec-AC-17 are new; TEST-789..792 are new rows,
each RED against `1936b504` by replay; Amendment 2's rules 2–4 and its
snapshot paragraph, the Scope decision summary, the Implementation plan,
Edge cases, Seams and Residual risks are corrected in place below and say so.
No file outside the already-declared review scope changes.

## Links
- Requirement / intake: docs/issues/ISSUE-0089-sync-deletes-target-only-hooks.md
- Upstream report: https://github.com/goodwind-cz/aai/issues/414 (pin v2026.09.30, commit beb6a248)
- Decision records: pending — orchestrator records a `hitl_decision` /
  `spec_amendment` entry in `docs/ai/decisions.jsonl` against this Amendment
  section (implementation does not write ledgers)
- Technology contract: docs/TECHNOLOGY.md

## Measured current behaviour (pre-change, this session)

Every claim below was re-measured against the tree at `beb6a248`, not taken
from the intake.

1. `.aai/scripts/aai-sync.sh:548-552` — `hooks/` is copied with
   `copy_replace "$SRC_ROOT/hooks" "$DST_ROOT/hooks"`.
2. `.aai/scripts/aai-sync.sh:146-152` — `copy_replace` is `rm -rf "$dst"`
   then `cp -a "$src" "$dst"`. Target-only content under `hooks/` is therefore
   destroyed by construction.
3. `.aai/scripts/aai-sync.ps1:557-562` — the PowerShell engine has the same
   shape: `Copy-Replace $hooksDir (Join-Path $TargetRoot "hooks")`. The defect
   is cross-engine.
4. Reproduction (scratch fixture, real engine, no network): a target carrying
   `hooks/merge-guard.sh` plus a marker line appended to `hooks/hooks.json` was
   synced once. Result: `merge-guard.sh` absent after the run, marker count in
   `hooks/hooks.json` = 0, stdout line `  SYNC hooks/` and no `PRESERVE` line
   for `hooks/`.
5. The advisory produced by that same run named `.codex/skills/` and
   `.gemini/skills/` and nothing about `hooks/` — six lines of unrelated
   overwrite noise while the safety control was being removed.
6. `.aai/scripts/aai-sync.sh:741-751` — the advisory is generated from the
   single `OVERWRITE_CONFLICTS` array, under the heading
   "The following target files/directories had local content that differed
   from sync source and were overwritten." There is no deletions array.
   `aai-sync.ps1:781-802` is the same generator in PowerShell.
7. `.aai/scripts/aai-sync.sh:742` — the advisory is written only when
   `${#OVERWRITE_CONFLICTS[@]} -gt 0`. Measured consequence: a second sync of
   the same fixture with `.aai/zz-target-only/` present printed
   `CLEAN removed stale: .aai/zz-target-only`, deleted the directory, and
   wrote NO advisory at all. A purely destructive run is currently silent.
8. The precedent for the fix is in the same script: `.aai/scripts/`
   (`aai-sync.sh:360-372`) and `.claude/skills` (`aai-sync.sh:377-395`) both do
   a file-by-file merge and log `PRESERVE target-only ...`.
9. `aai-sync.sh` calls `node` zero times (`grep -n 'node ' .aai/scripts/aai-sync.sh`
   returns nothing). The sync engine has no JSON parser and no Node dependency.
10. `tests/skills/test-aai-layer-profiles.sh:121-129` — `tree_manifest`
    excludes `docs/ai/reports/*`, so a new advisory file cannot break the
    byte-identity (TEST-002) or prune-idempotence (TEST-004) assertions there.

## Scope decision — the JSON-registration half (SUPERSEDED — see Amendment)

**This section's original decision is REVERSED by the Amendment above.** Kept
verbatim below for the historical record of what was decided at freeze and
why; do not implement against it. The corrected decision:

**Decision (amended twice): `hooks/hooks.json` and `hooks/hooks.windows.json`
are MERGED, not overwritten.** A source hook not already present in the
target is appended; a target-added entry is never removed or rewritten; a
source-owned entry is updated in place only when its whole registration —
every field of the hook object and its matcher — equals what this engine
last shipped (Amendment 2 rules 1–7 as corrected by Amendment 3), otherwise
left as-is and named in the advisory. The algorithm is REUSED, not re-typed, from
`.aai/scripts/aai-bootstrap.sh`'s `install_claude_hooks`, extracted into
`.aai/scripts/lib/merge-hooks-json.mjs` and called by both. The three open
questions original justification point 3 raised are answered there, not
re-litigated: identity is the (event, script path) key with the shipped
snapshot as provenance (Amendment 2 — the first amendment's "no identity
tracking" answer is superseded); a same-event registration dedupes on exact
`command` equality first and pairs by key second; idempotence follows from
"write only when something was added or updated"; `.sh` and `.ps1` parity is
proven by both calling the one shared script. `node` availability gates the
merge (WARN + leave untouched when absent — aai-sync.sh now calls `node`,
superseding this section's original justification point 2 and the "Hard
constraints" note below).

Follow-up `fu-hooks-json-target-entries-lost`, originally suggested here, is
SUPERSEDED — do not file it; the gap it named is what this amendment closes.

<details>
<summary>Original text (superseded, kept for the record)</summary>

The reporter lost two different things: three target-only FILES under `hooks/`,
and a target-added `PreToolUse` -> `Bash` registration block inside the
SOURCE-OWNED `hooks/hooks.json` and `hooks/hooks.windows.json`.

**Decision: the file half is fixed here; merging target-added ENTRIES inside
the source-owned hook JSONs is OUT of scope and split to a follow-up. This
hotfix instead makes that loss VISIBLE, which it is not today.**

Justification:

1. The two halves are different problems. The file half is the existing,
   twice-precedented file-by-file merge idiom applied to one more directory
   (evidence 8). The JSON half is a structural merge of a source-owned
   document with target-added entries.
2. The sync engine cannot parse JSON. It has no Node dependency at all
   (evidence 9) and runs at bootstrap time, before any project tooling is
   assumed. Adding one would either take a hard `node` dependency inside the
   installer or hand-roll JSON merging in `awk` in two languages. Choosing
   between those is a design decision, not a hotfix.
3. The merge SEMANTICS are undecided and cannot be guessed: what identifies a
   "target-added" entry across re-syncs, what happens when source and target
   register the same event plus matcher, how the result stays byte-idempotent,
   and how the `.sh` and `.ps1` engines are proven to produce the same bytes.
4. Shipping the file half alone already returns the safety-critical majority of
   the reported damage: the three `merge-guard.*` scripts survive, and the
   manual workaround shrinks from five paths to two.
5. Coupling a two-lines-per-engine fix to that design would delay the
   file-preservation fix for every downstream project that syncs.

What this hotfix DOES owe the JSON half, and delivers (Spec-AC-04): today the
two JSONs are overwritten with no advisory entry whatsoever (evidence 5). This
scope adds them to `OVERWRITE_CONFLICTS` whenever the target copy differs, with
a recommendation that names the registration loss by name. The loss stops being
silent, which is exactly the intake's second requirement — "any destructive
sync action has a review surface even where preserve does not apply."

Follow-up to file at close (suggested, not yet filed):
`fu-hooks-json-target-entries-lost` (P2) — a target-added registration inside
`hooks/hooks.json` / `hooks/hooks.windows.json` is still overwritten; the
advisory now names it, but nothing merges it back.

</details>

## Scope decision — how "target-only, keep" is told from "source removed it, drop it" (SUPERSEDED — see Amendment)

**This section's retirement mechanism is REVERSED by the Amendment above.**
Kept verbatim below for the historical record; do not implement against it.
The corrected decision:

**Decision (amended): retirement is explicitly OUT OF SCOPE.** The merge
never removes an existing target entry — so a target's existing registration
for a hook the source has since retired now SURVIVES indefinitely (previously
it was disarmed by wholesale overwrite), and the hook's file survives too
(unchanged — file survival was always the rule for target-only files). This
is a deliberate regression in the narrow dimension of "a retired hook
eventually stops running everywhere"; it is the accepted cost of the owner's
higher-priority requirement that a target's own modification is never
destroyed. No tombstone or retirement manifest is introduced (the reasoning
against one, below, still holds). Amendment 2 DOES introduce a provenance
record — the shipped snapshot under `<target>/.aai/cache/hooks-shipped/` —
for the update case, and the same proof ("this entry is byte-equal to what
the engine last shipped, and the source no longer ships it") is exactly what
safe retirement would need. It is deliberately NOT applied to removal here:
removal is a further owner decision, not a corollary of the update the owner
directed (suggested follow-up in Residual risks).

<details>
<summary>Original text (superseded, kept for the record)</summary>

**Decision: the source-owned set for `hooks/` is the set of entries present in
the SOURCE `hooks/` tree at sync time. Everything else in the target's `hooks/`
is target-only and is preserved. A hook the source deliberately retires is
disarmed by the overwritten REGISTRATION, not by deleting its file.**

Mechanism, stated so it can be tested (Spec-AC-08): a hook only runs when a
source-owned `hooks/hooks.json` or `hooks/hooks.windows.json` entry invokes it.
Those two JSONs stay source-owned and are still overwritten wholesale by this
spec. So when the source retires `foo.sh`, the source's registration for it
disappears from the target on the next sync and the hook stops firing, even
though the target's copy of `foo.sh` lingers as an inert orphan.

Why no tombstone or retirement manifest:

- It is the rule `.aai/scripts/` and `.claude/skills` have used since the merge
  branch existed (evidence 8). Neither can retire a file either, and no defect
  has been filed against either in that time. Giving `hooks/` a retirement
  mechanism that the two precedent directories do not have would make `hooks/`
  the inconsistent one.
- A retirement list would be a new vendored `.aai/**` file plus a reader in two
  languages plus a `PROFILES.yaml` classification, and it would ship EMPTY —
  nothing is retired today. Constitution article 2 (YAGNI) rules it out until a
  requirement exists.
- The safety property the intake is actually protecting is "a stale hook must
  not keep firing". Deregistration delivers that. Deletion of the file is
  cosmetic by comparison.

Honest residual, stated rather than hidden: the intake's wording is "a stale
hook the source deliberately removed must still disappear", and after this
change its FILE does not disappear — it is disarmed and left on disk. If the
owner wants literal deletion, that is a tombstone mechanism and a separate
scope.

</details>

## Scope decision — what feeds the new deletions category

Deletions are recorded at every site where this engine deletes content in the
target `.aai` tree: `CLEAN removed stale` (`aai-sync.sh:353-357`) and
`PROFILE prune (not in core)` (`aai-sync.sh:336-338`), plus any deletion the
new `hooks/` merge performs. The profile prune is included rather than filtered
so that the rule stays "every deletion this engine performs is listed", with no
judgement call for a future reader to re-litigate. Measured: a prune only fires
on an extended-to-core downgrade or on genuinely stale files, and a repeated
core sync is idempotent (`test-aai-layer-profiles.sh:509-537`), so the advisory
does not grow on steady-state runs.

Disclosed residual (not wired here): `copy_replace` on a DIRECTORY still does
`rm -rf` for `.codex/skills`, `.gemini/skills` and each `.claude/skills/<entry>`,
so target-only files under those three surfaces are still destroyed and are not
routed into the deletions category. Follow-up to file at close (suggested):
`fu-sync-rmrf-dirs-outside-deletions` (P3).

## Implementation strategy
- Strategy: direct
- Rationale: recorded at intake by the owner (`docs/ai/STATE.yaml`
  `implementation_strategy.source: intake`, `ref_id:
  sync-deletes-target-only-hooks`) — implement first, then targeted regression
  tests. Planning does NOT override a recorded human choice. Planning's own
  assessment agrees: the change is a small, twice-precedented edit to an
  existing idiom, and the RED observation is already recorded above as
  evidence 4, 5 and 7 from the pre-change tree.

Evidence this spec may demand under `direct` (see the template's
`### Evidence by strategy`): targeted regression tests green with exit codes,
plus the scoped diff. No stored RED artifact is required and none is demanded
below.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the change edits the installer every downstream project
  runs, in two languages, and the regression suites run the real engine against
  the LIVE tree (`test-aai-layer-profiles.sh:33` reads
  `$PROJECT_ROOT/.aai/scripts/aai-sync.sh`). An isolated tree keeps a
  half-applied engine out of any other session's sync. Not `required`: the sync
  engine is not in `protected_paths_l3`.
- User decision: undecided — the `worktree` block in STATE currently holds a
  STALE decision from ride `original-request-outcome-backcheck` (branch
  `feat/original-request-outcome-backcheck`, a path that no longer exists per
  `git worktree list`). Implementation Preparation must re-ask; the returned
  `set-worktree` command resets it to `undecided`.
- Base ref: main (`beb6a248`)
- Worktree branch/path: to be decided by Implementation Preparation
- Inline review scope: if inline is chosen — `.aai/scripts/aai-sync.sh`
  `.aai/scripts/aai-sync.ps1` `.aai/scripts/aai-bootstrap.sh` (AMENDED, added)
  `.aai/scripts/lib/merge-hooks-json.mjs` (AMENDED, new file)
  `.aai/system/PROFILES.yaml` (AMENDED, added) `tests/skills/test-aai-sync-seed.sh`
  `tests/skills/test-aai-layer-profiles.sh` (AMENDED 2, TEST-002 filter)
  `docs/specs/SPEC-0199-spec-sync-deletes-target-only-hooks.md`
  `docs/issues/ISSUE-0089-sync-deletes-target-only-hooks.md` `CHANGELOG.md`

## Acceptance Criteria Mapping

- Spec-AC-01 — WHEN a sync runs against a target holding a file under `hooks/`
  that the source `hooks/` does not contain, the engine SHALL leave that file
  in place byte-identical.
  Verification: create a fixture target, write `hooks/merge-guard.sh`, record
  its bytes, run `bash .aai/scripts/aai-sync.sh <target>`, then
  `cmp <recorded> <target>/hooks/merge-guard.sh` exits 0.
  Evidence: the fixture path, the sync stdout, the `cmp` exit code.

- Spec-AC-02 — WHEN the engine preserves a target-only entry under `hooks/`,
  it SHALL print one stdout line naming that entry's path relative to the
  target root.
  Verification: the same run's stdout contains the literal
  `PRESERVE target-only hook: hooks/merge-guard.sh`
  (`grep -qF` exits 0). A blanket directory-level line like the
  `.claude/skills` one does NOT satisfy this AC — the intake requires the file
  to be named.
  Evidence: the captured stdout.

- Spec-AC-03 — WHEN a target's copy of a SOURCE-OWNED hook file differs from
  the source, the engine SHALL replace it with the source bytes, and
  `hooks/session-start.sh` SHALL remain executable afterwards.
  Verification: seed the target's `hooks/session-start.sh` with different
  bytes and `chmod -x` it, sync, then `cmp <src>/hooks/session-start.sh
  <target>/hooks/session-start.sh` exits 0 and `test -x
  <target>/hooks/session-start.sh` exits 0.
  Evidence: both exit codes.

- Spec-AC-04 (AMENDED — see Amendment) — WHEN the target's `hooks/hooks.json`
  or `hooks/hooks.windows.json` carries a registration entry the source does
  not (a valid, differing JSON), that entry SHALL survive the sync via an
  additive merge — never overwritten — and the engine SHALL print one stdout
  line `MERGE hooks/<file>: <n> hook(s) added, <m> already present -> <path>`.
  No advisory entry is written for an ordinary successful merge (nothing was
  lost). Original text: "the advisory SHALL carry one `- Path:` entry ...
  whose Recommendation contains `registration`" — superseded; see Spec-AC-10
  for the case that DOES still produce an advisory entry (a refused merge).
  Verification: seed the target's `hooks/hooks.json` with a valid, additional
  `PreToolUse -> merge-guard.sh` entry, sync, then `grep -qF 'merge-guard.sh'
  <target>/hooks/hooks.json` exits 0 and the sync stdout contains `MERGE
  hooks/hooks.json:` (`grep -qF` exits 0).
  Evidence: the merged `hooks/hooks.json` contents and the captured stdout.

- Spec-AC-05 — WHEN at least one deletion was performed, the advisory SHALL
  contain a `## Deleted items` section listing one `- Path:` line per deleted
  path, and the advisory SHALL be written even when the overwrite list is
  empty.
  Verification: sync a fixture once, then create
  `<target>/.aai/zz-target-only/x.txt` and sync again; the newest advisory
  exists, `grep -qF '## Deleted items'` exits 0, and
  `grep -qF '- Path: .aai/zz-target-only'` exits 0. Measured pre-change
  baseline for this exact fixture: no advisory file at all (evidence 7).
  Evidence: the advisory file contents and the sync stdout.

- Spec-AC-06 — WHEN a run performs no deletion and triggers no new-in-this-scope
  overwrite entry, the advisory SHALL be byte-identical to the one the
  pre-change engine writes for the same inputs, except for the
  `- Generated at (UTC):` line.
  Verification: build one fixture SOURCE tree; copy it twice, swapping only
  `.aai/scripts/aai-sync.sh` for the pre-change version in one copy; sync both
  into identical fixture targets seeded to produce a non-empty overwrite list,
  no deletion and no hook-JSON divergence; then
  `diff <(grep -v '^- Generated at (UTC):' old_advisory) <(grep -v '^- Generated at (UTC):' new_advisory)`
  produces no output and exits 0. No empty `## Deleted items` heading appears,
  and the existing section order is unchanged.
  Scope note, stated because it deviates from the intake's literal phrasing:
  the intake asks for byte-identity on any run with no deletions. Spec-AC-04 is
  itself an intake requirement and DOES add an overwrite entry for a diverging
  hook JSON, so byte-identity is asserted for inputs that trigger neither a
  deletion nor a hook-JSON divergence. That is the guard the intake bullet
  exists for — it protects quiet runs from the advisory change.
  Evidence: the two advisory files and the diff exit code.

- Spec-AC-07 (AMENDED three times — see Amendments) — The PowerShell engine
  `aai-sync.ps1` SHALL exhibit the behaviours of Spec-AC-01, Spec-AC-02,
  Spec-AC-04 (amended), Spec-AC-05, Spec-AC-12, Spec-AC-13 (all four arms)
  and Spec-AC-17.
  Verification: when `pwsh` is on PATH, run
  `pwsh -NoProfile -File .aai/scripts/aai-sync.ps1 <target>` over the same
  fixtures and assert the same observables (the AC-04 observable is the
  merge survival + `MERGE hooks/hooks.json:` stdout line; the AC-12/AC-13
  observables are the `1 updated` / `1 left as-is` counters, the entry
  counts, the user's registration byte-unchanged and the advisory entry,
  over a fixture source tree; the AC-17 observable is the true MERGE line
  plus the snapshot WARN). When `pwsh` is
  absent, the suite sets its documented `PWSH_ARM_SKIPPED` flag and exits 42
  rather than reporting a full pass (existing discipline,
  `tests/skills/test-aai-sync-seed.sh:42-51`).
  Evidence: the pwsh run stdout, the preserved file, the merged `hooks.json`,
  or the recorded skip.

- Spec-AC-08 (AMENDED — see Amendment) — WHEN the target already carries a
  `hooks/hooks.json` (or `hooks/hooks.windows.json`) registration entry for a
  hook the source no longer ships, that entry SHALL survive the sync
  unchanged (additive merge never removes an existing target entry), AND the
  hook's own file SHALL also survive. Original text ("the target's
  `hooks/hooks.json` SHALL be byte-identical to the source's, carrying no
  reference to it" — disarmed via overwrite) is superseded: additive merge
  cannot disarm anything, so retirement is out of scope (residual risk,
  stated in the Amendment and below).
  Verification: seed the target with `hooks/retired-hook.sh` AND a
  `hooks/hooks.json` entry registering it (simulating a hook the source
  shipped in a prior sync and has since retired), sync, then
  `test -f <target>/hooks/retired-hook.sh` exits 0 and
  `grep -qF retired-hook.sh <target>/hooks/hooks.json` exits 0 (the
  registration SURVIVES — the opposite of the pre-amendment assertion).
  Evidence: the two results, plus the target `hooks/hooks.json` contents.

- Spec-AC-09 (AMENDED — see Amendment, suite added) — The sync-engine suites
  named by the intake, PLUS `test-aai-hooks-overlay.sh` (added: it now
  exercises the same shared merge library), SHALL exit 0 on the changed tree.
  Verification: each of
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-drift.sh`,
  `... tests/skills/test-aai-layer-profiles.sh`,
  `... tests/skills/test-aai-sync-seed.sh`,
  `... tests/skills/test-aai-bootstrap.sh`,
  `... tests/skills/test-aai-hooks-overlay.sh`
  exits 0 (exit 42 counts only for `test-aai-sync-seed.sh` when `pwsh` is
  absent, per Spec-AC-07).
  Evidence: the five exit codes and stdout tails.

- Spec-AC-10 (NEW — Amendment) — WHEN the target's `hooks/hooks.json` or
  `hooks/hooks.windows.json` does not parse as the expected JSON shape
  (malformed JSON, or a non-object `hooks` key), the merge SHALL be refused,
  the target file SHALL be left byte-untouched, and the advisory SHALL carry
  one `- Path:` entry for that file whose `- Recommendation:` text says the
  merge was refused.
  Verification: write `NOT JSON {` into the target's `hooks/hooks.json`, sync,
  then the file's bytes are unchanged (`before == after`) and the newest
  advisory's `hooks/hooks.json` entry's Recommendation matches
  `grep -q 'refused'`.
  Evidence: the before/after bytes and the advisory contents.

- Spec-AC-11 (NEW — Amendment) — WHEN `node` is unavailable, the target's
  `hooks/hooks.json` / `hooks/hooks.windows.json` SHALL be left untouched (not
  created on a fresh target either), the sync SHALL print a `WARN node
  unavailable` line, and the advisory SHALL name the file.
  Verification: run the sync with a `PATH` excluding every directory that
  could contain a `node` binary, capturing stdout and stderr to SEPARATE
  files, then `hooks/hooks.json` does not exist in the target, the STDOUT
  capture contains `WARN node unavailable` (`grep -qF` exits 0 — a `2>&1`
  capture cannot tell the streams apart, Validation NB-2), and the newest
  advisory names `hooks/hooks.json`.
  Evidence: the absence check, the captured stdout, and the advisory contents.

- Spec-AC-12 (NEW — Amendment 2; proof corrected by Amendment 3) — WHEN the
  source changes the `command` of a hook it already shipped (same script
  path, different command) AND the target's WHOLE registration for that
  path — the hook object in every field and its enclosing matcher — equals
  what this engine last shipped there (the shipped snapshot), the engine
  SHALL replace that entry
  in place — the target ends with exactly one entry for the path, carrying
  the new command — SHALL print `MERGE hooks/<file>: 0 hook(s) added, 1
  updated, ...`, SHALL leave every target-added entry untouched, and a
  repeated sync of the same source SHALL be a no-op.
  Verification: build a fixture source tree, sync it once (the snapshot is
  written), add a target-added `PreToolUse -> merge-guard.sh` entry, change
  the fixture source's `SessionStart` command (same path, new flag), sync
  again; then the `SessionStart` event holds exactly 1 command and it is the
  new one, the merge-guard entry is present verbatim, stdout carries `1
  updated`, and a third sync reports `0 hook(s) added, 0 updated, 1 already
  present`.
  Evidence: the before/after `hooks/hooks.json` and the three stdout lines.

- Spec-AC-13 (NEW — Amendment 2; arms (c)/(d) added by Amendment 3) — WHEN
  the source changes the `command` of a hook for a script path the target
  also registers, BUT the target's registration is NOT provably unmodified
  engine output (its hook object differs from the shipped snapshot's in ANY
  field — `command`, `timeout`, `async` or any other key — or it sits
  under a different `matcher`, or no snapshot exists), the engine SHALL
  leave the target's registration unchanged in every field and under its
  own matcher, SHALL NOT add the source's version beside it, SHALL print
  `... 1 left as-is ...`, and the advisory SHALL carry a `- Path:
  hooks/<file>` entry whose Recommendation says `left as-is`, quotes the
  target's kept command, names the differing field(s) or the user's
  matcher, and contains no absolute filesystem path.
  Verification: (a) sync a fixture source once, edit the target's
  `SessionStart` command locally, change the source's command, sync; (b)
  sync once, delete `<target>/.aai/cache/hooks-shipped/`, change the
  source's command, sync; (c) sync once, set the target's `SessionStart`
  matcher to `startup` (command untouched), change the source's command,
  sync; (d) sync once, add `"timeout": 120` and set `"async": true` on
  the target's shipped `SessionStart` hook (command untouched), change the
  source's command, sync. In all four arms the `SessionStart` event still
  holds exactly 1 command and it is the target's own; in (c)/(d) the
  event's JSON is identical before and after the sync; in (a) the newest
  advisory entry matches `left as-is` and the kept command; in (c) it
  quotes `matcher "startup"`; in (d) it names `timeout`; none contains
  the fixture's absolute path; in (b) the snapshot exists again afterwards.
  Evidence: the targets' `hooks/hooks.json` before/after, the stdout
  lines, the advisory entries.

- Spec-AC-14 (NEW — Amendment 2, Validation NB-4) — WHEN the target has no
  `hooks/hooks.json` yet, the engine SHALL create it as a byte-for-byte copy
  of the source file, whatever the source's formatting.
  Verification: reformat a fixture source's `hooks/hooks.json` (4-space
  indent plus a `_comment` key), sync into a fresh target, then `cmp` exits
  0. This pins a PRE-CHANGE property (the `beb6a248` engine copied the file
  verbatim; this ride's first pass regenerated it): its replay is GREEN at
  `beb6a248` by construction and RED at `ac042706`.
  Evidence: the `cmp` exit code.

- Spec-AC-15 (NEW — Amendment 2, Validation NB-3) — WHEN
  `aai-bootstrap.sh --with-claude-hooks` is EXPLICITLY requested and
  `.aai/scripts/lib/merge-hooks-json.mjs` is missing, bootstrap SHALL exit 3,
  SHALL write no `.claude/settings.json`, and SHALL name the missing library
  in an `ERROR` line — never warn-and-succeed.
  Verification: sync a target, delete the library from the target's own
  `.aai/scripts/lib/`, run the target's bootstrap with `--with-claude-hooks`;
  exit code 3, no settings file, output matches `merge-hooks-json.mjs` and
  `ERROR`.
  Evidence: the exit code and captured output.

- Spec-AC-16 (NEW — Amendment 3, Validation NB-B) — WHEN `hooks/` carries a
  dotfile, the bash engine SHALL treat it exactly as any other entry: a
  source `hooks/.hidden-hook.sh` SHALL be synced byte-identical into the
  target, and a target-only `hooks/.local-only.sh` SHALL be preserved AND
  named on stdout as `PRESERVE target-only hook: hooks/.local-only.sh` —
  parity with the `.ps1` engine and with the pre-#414 `cp -a`.
  Verification: build a fixture source, add `hooks/.hidden-hook.sh` to it,
  seed a target with `hooks/.local-only.sh`, run `aai-sync.sh`; then
  `cmp` on the hidden hook exits 0, the local-only file is unchanged, and
  stdout contains the PRESERVE line. When `pwsh` is present the same
  assertions run against `aai-sync.ps1`.
  Evidence: the `cmp` exit code, the file contents, the captured stdout.

- Spec-AC-17 (NEW — Amendment 3, Validation NB-A) — WHEN a hooks-JSON merge
  writes the target but the shipped snapshot cannot then be written (its
  path is a directory, its parent is a file, or EACCES), the engine SHALL
  exit 0, SHALL print the true `MERGE hooks/<file>: ...` line for what it
  did, SHALL print a WARN on stdout saying the shipped snapshot could not
  be recorded, SHALL NOT print or write "left untouched" for that file, and
  the advisory SHALL carry a `- Path: hooks/<file>` entry whose
  Recommendation says the merge was applied and the engine could not record
  what it shipped.
  Verification: sync a fixture source once, replace
  `<target>/.aai/cache/hooks-shipped/hooks.json` with a DIRECTORY, add a
  `Stop` event to the source's `hooks/hooks.json`, sync; then stdout
  contains `MERGE hooks/hooks.json: 1 hook(s) added` and `shipped snapshot
  could not be recorded` and not `target left untouched`, the target's
  `hooks/hooks.json` contains the new hook, and the newest advisory's
  `hooks/hooks.json` Recommendation matches `could not record what it
  shipped` and not `left untouched`. Same on `aai-sync.ps1` when
  `pwsh` is present.
  Evidence: the captured stdout, the target file, the advisory entry.

## Constitution deviations

None, including after the Amendment.

Checked article by article against this scope (original assessment; items
marked AMENDED re-checked against the amended design): (1) evidence before
claims — the pre-change observations above were produced and read in this
session, and every AC names a command and an observable; (2) simplicity
(AMENDED) — the retirement tombstone is still explicitly rejected as
speculative (Amendment point 3), but the JSON merge is no longer split out —
it REUSES an already-shipped algorithm (`install_claude_hooks`) via one
shared file rather than inventing a new one, which is the simpler path once
the reuse opportunity is known, not a complexity increase; (3) portability
(AMENDED) — `aai-sync.sh` now calls `node`, reversing evidence 9's
conclusion, but this is not a NEW class of dependency: it follows the
already-accepted, already-shipped precedent of `aai-bootstrap.sh`'s optional
`--with-claude-hooks` node call (RFC-0010), degrades to WARN + skip exactly
the same way, and touches no binary store; (4) degrade and report — the node-
unavailable and merge-refused paths both degrade to a named WARN plus an
advisory entry, never a silent skip or a destructive fallback; (5) additive
first — the `## Deleted items` section appears only when non-empty, Spec-
AC-06 pins that quiet runs are unchanged, and the hooks.json merge adds or
updates in place but never removes, and updates only an entry it can prove
it wrote (Amendment 2); (6) single-writer state — no STATE write in this
scope, and Implementation returns its commands to the orchestrator; the
amendment's `decisions.jsonl` record is written by the orchestrator against
this spec's Amendment section, not by a dispatched subagent; (7) operator-
only merge — unaffected.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                      | Status  | Evidence | Review-By | Notes                                        |
|------------|----------------------------------------------------------------------------------|---------|----------|-----------|----------------------------------------------|
| Spec-AC-01 | WHEN a sync runs the engine SHALL leave a target-only file under hooks unchanged | done | tests/skills/test-aai-sync-seed.sh TEST-773 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | precedent: .aai/scripts merge |
| Spec-AC-02 | WHEN a target-only hook is preserved the engine SHALL name it on stdout | done | tests/skills/test-aai-sync-seed.sh TEST-774 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | per-file line, not a blanket directory line |
| Spec-AC-03 | WHEN a source-owned hook file differs the engine SHALL overwrite and keep +x | done | tests/skills/test-aai-sync-seed.sh TEST-775 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | guards the chmod at aai-sync.sh:551 (already true pre-change; this pins the property under the new per-file merge) |
| Spec-AC-04 | AMENDED: a target-added hooks JSON registration SHALL survive the merge | done | tests/skills/test-aai-sync-seed.sh TEST-776 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | reuses install_claude_hooks merge algorithm; target-added path never touched (re-asserted inside TEST-784/785) |
| Spec-AC-05 | WHEN a deletion occurs the advisory SHALL carry a Deleted items section | done | tests/skills/test-aai-sync-seed.sh TEST-777 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | advisory now written on deletions alone |
| Spec-AC-06 | WHEN nothing is deleted the advisory SHALL stay byte-identical to today | done | tests/skills/test-aai-sync-seed.sh TEST-778 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | modulo the generated-at line |
| Spec-AC-07 | AMENDED three times: ps1 SHALL match AC-01, 02, 04, 05, 12, 13 and 17 | done | tests/skills/test-aai-sync-seed.sh TEST-779; TEST-788; TEST-790; TEST-792 green; run log docs/ai/tdd/test-773-792-sync-hooks-remediation2-20260930T150135Z.log (direct: green suite log, no RED artifact demanded) | — | pwsh-absent arm exits 42, never a silent pass |
| Spec-AC-08 | AMENDED: an existing target registration for a retired hook SHALL survive | done | tests/skills/test-aai-sync-seed.sh TEST-780 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | reverses the pre-amendment disarm-via-overwrite claim |
| Spec-AC-09 | AMENDED: the five named sync suites SHALL exit 0 on the changed tree | done | tests/skills/test-aai-sync-seed.sh TEST-781 green; run log docs/ai/tdd/test-773-788-sync-hooks-remediation-20260930T115214Z.log (direct: green suite log, no RED artifact demanded) | — | test-aai-hooks-overlay.sh added (shared lib) |
| Spec-AC-10 | NEW: a malformed target hooks JSON SHALL refuse the merge, stay untouched | done | tests/skills/test-aai-sync-seed.sh TEST-782 green; run log docs/ai/tdd/test-773-783-sync-hooks-amendment-20260930T015645Z.log (direct: green suite log, no RED artifact demanded) | — | mirrors install_claude_hooks NB-1 refusal |
| Spec-AC-11 | NEW: node unavailable SHALL leave the target hooks JSON untouched, WARN on stdout | done | tests/skills/test-aai-sync-seed.sh TEST-783 green; run log docs/ai/tdd/test-773-788-sync-hooks-remediation-20260930T115214Z.log (direct: green suite log, no RED artifact demanded) | — | stdout/stderr captured separately (Validation NB-2) |
| Spec-AC-12 | NEW (Amendment 2, proof corrected by Amendment 3): a provably-unmodified source-owned entry SHALL be updated in place | done | tests/skills/test-aai-sync-seed.sh TEST-784 green; run log docs/ai/tdd/test-773-792-sync-hooks-remediation2-20260930T150135Z.log (direct: green suite log, no RED artifact demanded) | — | whole hook object + matcher vs the shipped snapshot is the proof; target-added entry untouched |
| Spec-AC-13 | NEW (Amendment 2, arms c/d by Amendment 3): an unprovable same-path entry SHALL be left as-is and named | done | tests/skills/test-aai-sync-seed.sh TEST-785; TEST-789 green; run log docs/ai/tdd/test-773-792-sync-hooks-remediation2-20260930T150135Z.log (direct: green suite log, no RED artifact demanded) | — | never rewritten, never duplicated; four arms (edited command, no record, edited matcher, added timeout/async) |
| Spec-AC-14 | NEW (Amendment 2): a fresh target hooks JSON SHALL be the source bytes verbatim | done | tests/skills/test-aai-sync-seed.sh TEST-786 green; run log docs/ai/tdd/test-773-788-sync-hooks-remediation-20260930T115214Z.log (direct: green suite log, no RED artifact demanded) | — | pin of a pre-change property: GREEN at beb6a248, RED at ac042706 |
| Spec-AC-15 | NEW (Amendment 2): explicit --with-claude-hooks with the merge library missing SHALL fail | done | tests/skills/test-aai-sync-seed.sh TEST-787 green; run log docs/ai/tdd/test-773-788-sync-hooks-remediation-20260930T115214Z.log (direct: green suite log, no RED artifact demanded) | — | exit 3, nothing written (Validation NB-3) |
| Spec-AC-16 | NEW (Amendment 3): dotfiles under hooks SHALL be synced and preserved+named by the bash engine like ps1 | done | tests/skills/test-aai-sync-seed.sh TEST-791 green; run log docs/ai/tdd/test-773-792-sync-hooks-remediation2-20260930T150135Z.log (direct: green suite log, no RED artifact demanded) | — | dotglob around the two hooks loops, restored after (Validation NB-B) |
| Spec-AC-17 | NEW (Amendment 3): a merge whose snapshot cannot be written SHALL be reported as applied, never as untouched | done | tests/skills/test-aai-sync-seed.sh TEST-792 green; run log docs/ai/tdd/test-773-792-sync-hooks-remediation2-20260930T150135Z.log (direct: green suite log, no RED artifact demanded) | — | SNAPSHOT-NOT-RECORDED line, exit 0, WARN + advisory on both engines (Validation NB-A) |

## Implementation plan

Components affected (AMENDED — see Amendment for what changed since freeze):

- `.aai/scripts/lib/merge-hooks-json.mjs` (NEW) — the JSON-hooks merge
  algorithm, extracted from `aai-bootstrap.sh`'s `install_claude_hooks`
  inline `node -e` script and extended by Amendment 2: parse template and
  destination, refuse (throw, exit 1, destination untouched) when the
  destination does not parse as a JSON object or carries a non-object
  `hooks` key (Review NB-1); a missing destination becomes a byte copy of
  the template (rule 7); otherwise skip an exactly-present command, pair the
  rest by (event, path key), update in place only an entry whose WHOLE hook
  object (canonical JSON) and enclosing matcher equal the `--shipped`
  snapshot's for that key (Amendment 3), leave any other same-key entry
  as-is (reported, naming the differing fields or matcher), and add the
  unclaimed rest, creating the `matcher` entry if needed; write the
  destination only when something was added or updated; then rewrite the
  snapshot (verbatim template bytes) — a snapshot write failure is RETURNED
  (`snapshotError`), never thrown, because the destination is already
  written (Amendment 3, NB-A). Exports `mergeHooksJson()`, `hookPathKey()`
  and `canonicalJson()` for reuse and runs as a CLI (`node
  merge-hooks-json.mjs <template> <dest> [--shipped <snapshot>]`) printing
  `<n> hook(s) added, <u> updated, <m> already present, <k> left as-is ->
  <dest>`, one `LEFT-AS-IS <event> <key>: ...` line per left entry, and
  one `SNAPSHOT-NOT-RECORDED <path>: <error>` line when the snapshot could
  not be written (still exit 0). Classified in `.aai/system/PROFILES.yaml`
  `core:` (new entry).
- `.aai/scripts/aai-bootstrap.sh` — `install_claude_hooks` calls the shared
  library (`$HOOKS_JSON_MERGE_LIB`, resolved from `$BOOTSTRAP_SCRIPT_DIR`, the
  script's own directory computed ONCE and shared with `GITIGNORE_BLOCK_LIB`
  — Validation BLOCKING-2: a second `$(cd ... && pwd)` copy of that idiom
  raised the cd-in-substitution ratchet, so the resolution was hoisted
  instead of re-recording the baseline) instead of its former inline
  `node -e` script, with no snapshot (so it never updates). A missing
  library under the explicit `--with-claude-hooks` sets
  `HOOKS_MERGE_FAILED=1` (exit 3, `ERROR` line naming the library) —
  Validation NB-3. Stdout wording (`hooks overlay: <merge_out>`) is
  preserved; the idempotence classification now reads `0 hook(s) added, 0
  updated`. `test-aai-hooks-overlay.sh` TEST-011 needed no changes.
- `.aai/scripts/aai-sync.sh`
  - Replace the single `copy_replace "$SRC_ROOT/hooks" "$DST_ROOT/hooks"` at
    `:550` with a file-by-file merge modelled on `:360-372`: copy each source
    entry over the target, then walk the target and print
    `PRESERVE target-only hook: hooks/<rel>` for each entry absent from source.
    Both loops run under `shopt -s dotglob` (the caller's setting restored
    afterwards) so dotfiles are synced and preserved like `cp -a` and the
    `.ps1` engine do (Amendment 3, NB-B). Keep the `chmod +x` on
    `session-start.sh`.
  - For `hooks.json` / `hooks.windows.json` specifically: skip the generic
    copy_replace; instead, when `node` is available and the shared merge
    library exists, call it (`node "$HOOKS_JSON_MERGE_LIB" "$src_hook"
    "$dst_hook" --shipped "$DST_ROOT/.aai/cache/hooks-shipped/<file>"`) — on
    success print `MERGE hooks/<file>: <out>` and append one
    `OVERWRITE_CONFLICTS` entry per `LEFT-AS-IS` line the library printed,
    plus one entry and a stdout WARN per `SNAPSHOT-NOT-RECORDED` line
    (merge applied, snapshot not recorded — Amendment 3, NB-A); on refusal
    (nonzero exit — which the library now raises only BEFORE any write)
    append an `OVERWRITE_CONFLICTS` entry whose recommendation says the
    merge was refused and names the target as untouched. When `node` is unavailable, or the library is missing, append
    an `OVERWRITE_CONFLICTS` entry naming that and leave the target file
    untouched (created or not). All three WARN lines go to stdout. The
    library's output has `$DST_ROOT/` stripped and `$SRC_ROOT/` replaced by
    `<source>/` before it reaches stdout or the advisory (Validation NB-5;
    the prefixes are held in variables so the bash 3.2 `${var//"$p"/}`
    scrub is literal even for a `[ ]` in a root path).
  - Add a `DELETIONS=()` array beside `OVERWRITE_CONFLICTS` (`:144`), append to
    it at `CLEAN removed stale` (`:353-357`) and `PROFILE prune` (`:336-338`).
  - Change the advisory guard to fire when EITHER array is non-empty,
    and emit `## Deleted items` after `## Overwritten items` only when
    `DELETIONS` is non-empty. (bash-3.2 nounset note: the `for conflict in
    "${OVERWRITE_CONFLICTS[@]}"` loop must itself be guarded by a `[[
    ${#OVERWRITE_CONFLICTS[@]} -gt 0 ]]` check — an empty array reference
    under `set -u` throws "unbound variable" on bash 3.2/macOS, reachable
    once the guard can fire on `DELETIONS` alone.)
- `.aai/scripts/aai-sync.ps1` — the same shape: `$deletions`, the merge-or-
  degrade branch for the two JSON files (calling the identical
  `.aai/scripts/lib/merge-hooks-json.mjs` via `node` with the same
  `--shipped` snapshot path, parsing the same `LEFT-AS-IS` and
  `SNAPSHOT-NOT-RECORDED` lines, scrubbing the same root prefixes), and the
  advisory guard/`## Deleted items` block,
  keeping the two engines' advisory output byte-equivalent for everything
  except the two JSON files' own handling.
- `.aai/system/PROFILES.yaml` — one new `core:` line for the shared library.
  The shipped snapshot lives under `.aai/cache/`, which PROFILES excludes by
  rule and both engines already gitignore and preserve; no new vendored file.
- `tests/skills/test-aai-sync-seed.sh` — twenty TEST rows below
  (TEST-773..792). Chosen over the other suites because it already builds
  temp targets, runs the REAL engines with no network (`:19`), asserts
  PRESERVED-byte-for-byte semantics, and carries the `PWSH_ARM_SKIPPED`
  exit-42 discipline that Spec-AC-07 needs. TEST-784..792 (bar 787) build a
  fixture SOURCE tree (the TEST-778 builder) because they must edit the
  source's `hooks/hooks.json` or `hooks/` between syncs.
- `tests/skills/test-aai-layer-profiles.sh` — TEST-002's old-vs-new `diff -rq`
  filter excludes `.aai/cache/` (the shipped snapshot the old engine never
  wrote), matching the suite's own `aai_files_of` exclusion.

Data flows: source tree -> per-entry copy decision (hooks.json/hooks.windows.json
routed through the shared merge library instead, which reads and rewrites
the shipped snapshot under `<target>/.aai/cache/hooks-shipped/`) -> two
in-memory arrays (`OVERWRITE_CONFLICTS`, `DELETIONS`) -> one advisory file
under `<target>/docs/ai/reports/`.

Edge cases:

- A target `hooks/` subdirectory that the source lacks — the walk must treat it
  as target-only and not descend destructively.
- A target-only entry whose name later appears in the source: the source wins
  from that sync on, which is the same rule `.aai/scripts/` uses.
- `hooks/` absent in the target entirely (fresh install) — the file merge must
  `mkdir -p` and behave exactly as the old wholesale copy did; the JSON merge
  treats a missing destination as `{}` and creates it fresh (unless `node` is
  unavailable, in which case nothing is created — see Spec-AC-11).
- A path containing spaces or `[ ]` — the fixture at
  `test-aai-layer-profiles.sh:562` already pins this class for the engine; the
  new loops must quote every expansion.
- Advisory ordering: `## Overwritten items` keeps its position; `## Deleted
  items` is appended after it, so Spec-AC-06's diff sees no reordering.
- A merge that adds zero hooks (target already carries everything source
  does) must not rewrite the destination file (idempotence) and must not be
  treated as a refusal (exit 0, not added to `OVERWRITE_CONFLICTS`).
- (Amendment 2) Two spellings of one script (`${CLAUDE_PLUGIN_ROOT}/hooks/x.sh`
  vs an absolute path) are two keys: the engine adds rather than pairs —
  it errs toward "never a wrong update", at the cost of a possible
  duplicate the advisory does not name. Stated in Residual risks.
- (Amendment 2) A command with no path-like token (`echo hi`) has no key
  and is exact-command only, exactly as before.
- (Amendment 2) A snapshot that is unreadable or malformed is treated as
  absent — rule 4, never a guessed update — and is rewritten after the run.
- (Amendment 2) The snapshot is rewritten only when its bytes changed, so a
  steady-state re-sync leaves `.aai/cache/` byte-identical (layer-profiles
  idempotence).
- (Amendment 3) A shipped hook whose `command` the user left alone but
  whose `matcher` they narrowed, or to which they added `timeout`/flipped
  `async`, is NOT provably engine output: the whole-object proof fails and
  the entry is left as-is and named (the exact case the command-only proof
  rewrote). A user-added SIBLING hook in the shipped hook's matcher group
  does not block the shipped hook's own update (the proof is per hook
  object, and a group is deleted only when it empties).
- (Amendment 3) A snapshot path that is a directory, or a `hooks-shipped`
  that is a file, after a merge that wrote the target: exit 0, true MERGE
  line, WARN + advisory "could not record what it shipped"; the next sync
  degrades to rule 4 until the path is writable.
- (Amendment 3) A dotfile under `hooks/` on either side is an ordinary
  entry to both engines (bash: `dotglob` scoped to the two loops).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                                  | Mutation            | Status  |
|----------|------------|-------------|-------------------------------------|----------------------------------------------------------------------------------------------|---------------------|---------|
| TEST-773 | Spec-AC-01 | integration | tests/skills/test-aai-sync-seed.sh  | target-only hooks/merge-guard.sh survives a real sync byte-identical                          | n/a — direct        | green   |
| TEST-774 | Spec-AC-02 | integration | tests/skills/test-aai-sync-seed.sh  | sync stdout carries PRESERVE target-only hook naming hooks/merge-guard.sh                     | n/a — direct        | green   |
| TEST-775 | Spec-AC-03 | integration | tests/skills/test-aai-sync-seed.sh  | a differing hooks/session-start.sh is replaced by source bytes and stays executable           | n/a — direct        | green   |
| TEST-776 | Spec-AC-04 | integration | tests/skills/test-aai-sync-seed.sh  | (AMENDED) a target-added hooks/hooks.json registration (PreToolUse -> merge-guard.sh) survives an additive-merge sync; sync prints a MERGE line | n/a — direct | green |
| TEST-777 | Spec-AC-05 | integration | tests/skills/test-aai-sync-seed.sh  | a deletion-only re-sync writes an advisory with a Deleted items section naming the path       | n/a — direct        | green   |
| TEST-778 | Spec-AC-06 | integration | tests/skills/test-aai-sync-seed.sh  | old-engine and new-engine advisories match for a quiet run, generated-at line excluded        | n/a — direct        | green   |
| TEST-779 | Spec-AC-07 | integration | tests/skills/test-aai-sync-seed.sh  | (AMENDED) pwsh engine preserves+names a target-only hook, additively merges a target-added hooks.json registration, reports a deletion-only advisory; absent pwsh exits 42 | n/a — direct | green |
| TEST-780 | Spec-AC-08 | integration | tests/skills/test-aai-sync-seed.sh  | (AMENDED) a target's existing hooks.json registration for a source-retired hook SURVIVES the merge, and so does the hook's file | n/a — direct | green |
| TEST-781 | Spec-AC-09 | integration | tests/skills/test-aai-sync-seed.sh  | (AMENDED, suite added) the five named sync suites (incl. test-aai-hooks-overlay.sh) exit 0 on the changed tree | n/a — direct | green |
| TEST-782 | Spec-AC-10 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW) a malformed target hooks/hooks.json refuses the merge, stays byte-untouched, and is named in the advisory | n/a — direct | green |
| TEST-783 | Spec-AC-11 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW; AMENDED 2) with node unavailable, hooks/hooks.json is left untouched (not created), the WARN is on STDOUT (streams captured separately), and the advisory names it | n/a — direct | green |
| TEST-784 | Spec-AC-12 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 2) a source-changed command for a shipped script path is updated in place when the target entry equals the shipped snapshot; 1 SessionStart entry, target-added merge-guard untouched, third sync a no-op | n/a — direct | green |
| TEST-785 | Spec-AC-13 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 2) an unprovable same-path entry (edited locally; or no snapshot) is left as-is, not duplicated, named in the advisory with no absolute path; snapshot re-recorded | n/a — direct | green |
| TEST-786 | Spec-AC-14 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 2, NB-4) a fresh target's hooks/hooks.json is the source's bytes even when the source is not in stringify shape — pin: GREEN at beb6a248, RED at ac042706 | n/a — direct | green |
| TEST-787 | Spec-AC-15 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 2, NB-3) bootstrap --with-claude-hooks with the merge library missing exits 3, writes nothing, names the library | n/a — direct | green |
| TEST-788 | Spec-AC-07 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 2) the ps1 engine updates a provably-unmodified entry in place and leaves an unprovable one as-is with an advisory entry; absent pwsh exits 42 | n/a — direct | green |
| TEST-789 | Spec-AC-13 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 3) arms (c)/(d): a user-edited matcher and a user-added timeout/async on the shipped hook (command untouched) survive a source command change byte-for-byte, 1 left as-is, advisory names the matcher/field — RED at 1936b504 (rewritten as 1 updated) | n/a — direct | green |
| TEST-790 | Spec-AC-07, Spec-AC-13 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 3) the ps1 engine preserves the same two user edits (matcher, fields) with 1 left as-is and an advisory entry; absent pwsh exits 42 — RED at 1936b504 | n/a — direct | green |
| TEST-791 | Spec-AC-16 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 3) a source hooks/.hidden-hook.sh is synced and a target-only hooks/.local-only.sh is preserved and named by the bash engine; ps1 parity arm when pwsh is present — RED at 1936b504 (bash dropped the dotfile) | n/a — direct | green |
| TEST-792 | Spec-AC-17, Spec-AC-07 | integration | tests/skills/test-aai-sync-seed.sh  | (NEW, Amendment 3) a merge whose shipped snapshot cannot be written (directory in its place) is reported as applied + snapshot not recorded on both engines, never as refused/untouched — RED at 1936b504 | n/a — direct | green |

Mutation column note: the Mutation gate applies to `tdd`/`hybrid` specs only
(`spec-lint.mjs` `mutationGateApplicability`). This spec's strategy is
`direct`, recorded at intake by the owner, so no mutation cell is demanded.

## Seams this scope crosses

1. `aai-sync.sh` <-> `aai-sync.ps1`. Two independent implementations of one
   advisory format. Crossed by TEST-779, which runs the PowerShell engine over
   the same fixtures rather than asserting a static text match between the two
   sources.
2. The sync engine <-> the advisory consumer. The advisory is the human review
   surface; a change to its shape is what Spec-AC-06 guards. TEST-778 runs both
   engine versions and diffs real output rather than reasoning about the
   generator.
3. The sync engine <-> `tests/skills/test-aai-layer-profiles.sh`, which runs the
   LIVE engine from `$PROJECT_ROOT` and compares whole trees. Measured: that
   suite's `tree_manifest` excludes `docs/ai/reports/*` (`:121-129`), so the new
   advisory cannot perturb its byte-identity or idempotence assertions.
   TEST-781 keeps that measurement honest.
4. The sync engine <-> `hooks/hooks.json` as a runtime contract read by the
   harness. Spec-AC-08 (amended) asserts the survival contract directly
   rather than reasoning about it.
5. Residual seam no automated test in this scope crosses: an actual downstream
   project's `/aai-update` run. The fixtures approximate it; nothing here
   proves the reporter's own tree recovers. That verification belongs to the
   reporter after the release.
6. (NEW, Amendment) `aai-sync.(sh|ps1)` <-> `aai-bootstrap.sh` <->
   `.aai/scripts/lib/merge-hooks-json.mjs`. Three callers/one algorithm; a
   change to the shared library now risks both the sync engine's hooks.json
   handling AND the `--with-claude-hooks` overlay. Crossed by TEST-781's
   inclusion of `test-aai-hooks-overlay.sh` and by TEST-776/779/780/782/783/
   784/785/786/788 exercising the library through the sync engine directly
   — not merely a reading of the extraction.
7. (NEW, Amendment 2) The engine <-> its own previous run, through the
   shipped snapshot under `<target>/.aai/cache/hooks-shipped/`. The update
   rule is only as sound as that record; a snapshot written by run N and
   read by run N+1 is what TEST-784 (present, agreeing), TEST-785(a)
   (present, disagreeing) and TEST-785(b) (absent) each cross in a
   different state, and TEST-789/790 (present, agreeing on the command but
   not on the matcher or the fields) cross it where the command-only proof
   was blind. TEST-792 crosses the snapshot WRITE, not just its read. The
   snapshot's absence on a fresh clone is a declared residual, not an
   untested branch.

## Verification

Commands, run from the repository root (5th command added by the Amendment):

1. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-sync-seed.sh`
2. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-drift.sh`
3. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh`
4. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-bootstrap.sh`
5. `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hooks-overlay.sh`

Evidence artifacts: the five exit codes and stdout tails; the fixture advisory
files quoted in the validation report; the scoped diff over
`.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`,
`.aai/scripts/aai-bootstrap.sh`, `.aai/scripts/lib/merge-hooks-json.mjs`,
`.aai/system/PROFILES.yaml`, `tests/skills/test-aai-sync-seed.sh` and
`tests/skills/test-aai-layer-profiles.sh`.

PASS criteria: TEST-773..TEST-792 green (TEST-779/788/790/791/792 may record
the documented pwsh skip) AND every Spec-AC in a terminal status.

## Evidence contract

- ref_id: `sync-deletes-target-only-hooks`
- Spec-AC and TEST links: as mapped in the Test Plan table above
- Command or review scope: the five commands under `## Verification`; review
  scope is `.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`,
  `.aai/scripts/aai-bootstrap.sh`, `.aai/scripts/lib/merge-hooks-json.mjs`,
  `.aai/system/PROFILES.yaml`, `tests/skills/test-aai-sync-seed.sh`,
  `tests/skills/test-aai-layer-profiles.sh` (TEST-002 filter), this spec,
  the intake and `CHANGELOG.md`
- Exit code or review verdict: recorded per command
- Evidence path: the validation report under `docs/ai/reports/`
- Commit SHA or diff range: recorded at hand-off

Under strategy `direct` this spec demands targeted regression tests green with
exit codes plus the scoped diff. It does NOT demand a stored RED artifact and
does not demand a verification matrix beyond the five commands listed above.

## Registry items closed by this scope

none — `node .aai/scripts/follow-ups.mjs list` reports no open item whose
subject is the sync engine's `hooks/` handling or the conflict advisory. The
`fu-hooks-json-target-entries-lost` follow-up this spec originally suggested
filing (never actually filed) is now SUPERSEDED by the Amendment — do not
file it.

## Companion obligations

Both entries of the closed list in `.aai/PLANNING.prompt.md`, re-checked
after the Amendment:

- Prompt corpus: this scope adds no bytes to `.aai/*.prompt.md` or
  `.aai/AGENTS.md`, so no prompt-diet ledger true-up and no TEST-012 bump.
  Unaffected by the Amendment.
- New `.aai/**` file (AMENDED — now applies): `.aai/scripts/lib/merge-hooks-json.mjs`
  is a new vendored file, added because it is REUSED by two callers rather
  than re-typed. Classified in `.aai/system/PROFILES.yaml` `core:` (done,
  one new line). The rejected retirement manifest is still rejected — this
  is not that file; it carries no retirement/tombstone logic. Amendment 2's
  shipped snapshot is RUNTIME state written into the TARGET under
  `.aai/cache/` (gitignored, PROFILES-excluded by rule), not a vendored
  file — no classification line is owed.

## Residual risks

1. (AMENDED — no longer a defect, replaced) Retirement is out of scope:
   the merge never removes an existing target entry, so a target's
   registration for a hook the source has since retired now SURVIVES
   indefinitely (previously "disarmed via overwrite" — see the Amendment and
   the superseded Scope decision above). The hook's FILE also survives,
   unchanged from before. This is a deliberate, owner-accepted regression in
   one narrow dimension (a retired hook keeps firing in a target that
   already registered it) traded for the higher-priority property the owner
   required (a target's own modification is never destroyed). Amendment 2's
   shipped snapshot now makes safe retirement PROVABLE (an entry byte-equal
   to the snapshot that the new source no longer ships is unmodified engine
   output the source retired); it is not applied to removal here because
   removal is a further owner decision. Suggested follow-up (not filed):
   `fu-hooks-retire-via-shipped-snapshot` (P3).
1a. (NEW, Amendment 2) The update capability depends on the shipped
   snapshot, which is gitignored runtime state: a fresh clone, another
   machine, or a target last synced by a pre-#414 engine has none, so the
   FIRST sync there can only report a changed source-owned entry as left
   as-is (advisory), never update it; the snapshot is written by that run
   and every later sync can update. A same-path entry left as-is is
   reported on EVERY sync while it differs from the source, like any other
   overwrite conflict — the noise is the price of never guessing.
1b. (NEW, Amendment 2) Two spellings of one script are two keys (edge
   cases above): a target that registered the source's hook under a
   different path spelling gets the source's version ADDED beside it, the
   pre-amendment-2 accumulation, and the advisory does not name it.
1c. (NEW, Amendment 2) `aai-bootstrap.sh`'s missing-template and
   missing-node guards under an explicit `--with-claude-hooks` still
   warn-and-succeed (exit 0), while the missing-library guard now fails
   (exit 3) — an inconsistency this ride names rather than widens; aligning
   the two older guards is a separate decision.
1d. (NEW, Amendment 3, Validation NB-C) The pairing key is the FIRST
   path-like token in the command, not "the script path": `cat /etc/a.txt
   | x.sh` keys on `/etc/a.txt`, `FOO=/tmp/x.log cmd x.sh` keys on the
   assignment, and a path containing spaces keys on its last whitespace-free
   segment (so two different space-containing paths can share a key). For
   every command this repository ships the key IS the script path. The
   measured error direction of a mis-key is SAFE — it can only produce
   left-as-is or an add beside, never a rewrite or a user entry paired for
   update — but a user's target-added pipeline hook sharing a first token
   with a source hook permanently blocks that source hook's update, and the
   advisory then calls the two "the same script". Not changed here:
   narrowing the regex is a key-semantics change outside this round's scope.
1e. (NEW, Amendment 3) A source that changes ONLY a shipped hook's
   `matcher` (command unchanged) is not propagated: rule 1 sees the exact
   command already present and skips it, so the target keeps the old
   matcher. Pre-existing under Amendment 2; the whole-object proof makes it
   visible, and propagating it is a further decision.
1f. (NEW, Amendment 3) A snapshot the engine cannot write leaves the target
   permanently in the rule-4 regime for that file — every changed
   source-owned entry is reported, never updated — until the path is fixed;
   the run says so on every sync (Spec-AC-17), so it is loud, not silent.
2. `.codex/skills`, `.gemini/skills` and each `.claude/skills/<entry>` are still
   replaced wholesale, so target-only files there are still destroyed and are
   not in the deletions category.
3. Nothing in this scope proves the reporter's own downstream tree recovers;
   the fixtures approximate their setup.
