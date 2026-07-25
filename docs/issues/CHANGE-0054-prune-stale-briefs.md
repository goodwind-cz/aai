---
id: prune-stale-briefs
number: 54
type: change
status: done
links:
  spec: null
  pr:
    - 153
  commits:
    - 3d66df40050764866f9252e3a3fa0ff99a03d975
---

# AAI-level stale-brief sweep

## Summary
- A new `.aai/scripts/prune-stale-briefs.mjs` sweeps stale work-item briefs
  (`docs/ai/briefs/<REF-ID>.md`) across the whole repo in one pass, wired into
  `/aai-wrap-up` (step 6b) so **every** AAI project — not just this one — sweeps
  its own briefs at session end. Complements CHANGE-0052's per-close prune, which
  only handles the doc it closes and leaves any pre-existing backlog untouched
  (41 stale briefs had accumulated here).
- A brief is a gitignored Planning handoff. It is LIVE only while its work item is
  open; once the item is terminal (`done | deferred | rejected | superseded |
  legacy`) or its doc no longer exists (orphan), the brief is dead clutter. The
  sweep prunes exactly those and KEEPS every brief whose work item is still open.

## Type
- change (AAI-layer docs-lifecycle hygiene; best-effort, distributable)

## Motivation / Business Value
- Briefs accumulate silently and obscure which briefs are live handoffs. The
  per-close hook (CHANGE-0052) stops future accumulation but never cleans the
  backlog, and downstream AAI projects have the same problem. The fix belongs at
  the framework level (a script + wrap-up wiring that ships in the `.aai` layer),
  not a one-off local `rm` — so this ships the mechanism, then dogfoods it to clear
  this repo's 41-brief backlog.

## Scope
- In scope:
  - `.aai/scripts/prune-stale-briefs.mjs`: scans `docs/ai/briefs/*.md`, resolves
    each brief name (slug id OR numbered display id) against every scanned doc's
    status, prunes terminal + orphan briefs, keeps open ones. `--dry-run` and
    `--json`; `.gitkeep` never touched; exit 0 always (best-effort). Node stdlib.
  - `.aai/SKILL_WRAP_UP.prompt.md`: step 6b runs the sweep at session end (silent
    when clean; skip if the script is absent on an older layer).
  - `.aai/system/PROFILES.yaml`: classify the new script (extended).
  - Prompt-diet ledger true-up for the +535 B SKILL_WRAP_UP step
    (JUSTIFIED_ADDITIONS entry + TEST-012 checkpoint 24871 -> 25406).
  - `tests/skills/test-aai-prune-stale-briefs.sh`: fixture suite (TEST-001..006).
- Out of scope:
  - The per-close prune (CHANGE-0052, already shipped) — unchanged.
  - Any change to how briefs are CREATED (PLANNING step 11) — unchanged.

## Desired Behavior (To-Be)
- Running the sweep removes every brief whose matching doc is terminal, or that
  has no matching doc (orphan), and keeps every brief whose doc is open.
- `--dry-run` reports the same set but removes nothing; a clean repo is a no-op.
- Wrap-up runs it at session end so briefs never accumulate in any AAI project.

## Acceptance Criteria
- AC-001: a brief for a terminal doc — by slug id AND by numbered display id — is
  pruned; a brief for an open (implementing) doc is KEPT; an orphan brief (no
  matching doc) is pruned. Deterministic fixture test (TEST-001..004), RED without
  the script.
- AC-002: `--dry-run` removes nothing but reports the stale set; `--json` emits
  `{dry_run, pruned[], kept_open}`; `.gitkeep` is never pruned; a second run is a
  clean no-op (TEST-005..006).
- AC-003: `/aai-wrap-up` step 6b invokes the sweep; PROFILES.yaml classifies the
  script; the prompt-diet ledger is trued up (TEST-010 headroom in [0,2048],
  TEST-012 checkpoint == independent re-sum).

## Verification
- `bash tests/skills/test-aai-prune-stale-briefs.sh` (TEST-001..006 green).
- `bash tests/skills/test-aai-prompt-diet.sh` (TEST-010/012/013 green, headroom 488/2048).
- Real-repo dogfood: `node .aai/scripts/prune-stale-briefs.mjs --dry-run` reported
  41 stale / 0 live before the sweep.

## Constraints / Risks
- Best-effort by design: exit 0 always, an unlink failure never blocks a caller.
- SAFE: prunes only when a matching doc is proven terminal, or the brief is an
  orphan; a live handoff (open doc) is never removed. Briefs are gitignored, so a
  wrong prune is recoverable by a re-plan (regenerates the brief).
- `.aai/scripts/prune-stale-briefs.mjs` is NOT a protected_paths_l3 path (L2).

## Notes
- Related: close-work-item-brief-cleanup (CHANGE-0052, the per-close prune),
  PLANNING step 11 (brief emit), planning-companion-obligations (SPEC-0071, the
  PROFILES + prompt-diet true-up this change self-dogfoods).
