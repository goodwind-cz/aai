---
id: spec-kit-comparative
number: 1
type: research
status: done
links:
  pr: []
  commits: []
---

# Research — github/spec-kit compared against the AAI factory

## Research Question
- Owner ask 2026-08-13: what should the AAI factory learn from GitHub's
  Spec Kit? Specifically: its methodology, its GitHub issues (field
  evidence), its constitution concept, and its installation/upgrade model.

## Scope
- In scope: README, `spec-driven.md`, command templates (`analyze.md`,
  `converge.md`), `docs/upgrade.md`, `docs/guides/evolving-specs.md`, and
  the open issue tracker sorted by discussion volume.
- Out of scope: running Spec Kit; agent-integration bugs specific to
  Copilot/Cursor/Zed (irrelevant to a factory that owns its own dispatch);
  their opinionated architecture articles (library-first, max 3 projects,
  CLI text-in/text-out) — those are product dogma, not transferable rules.
- NOT INGESTED (honest gap): the README's video overview
  <https://www.youtube.com/watch?v=a9eR1xsfvHg>. WebFetch returned only the
  YouTube page footer — no title, description, chapters or transcript. No
  claim in this document derives from the video. Re-open this research if
  the video is later summarized by a human or a transcript becomes
  reachable.

## Success Criteria
- A ranked, evidence-backed list of mechanisms worth adopting, each with a
  cost note; an explicit list of what NOT to adopt and why; and every claim
  about AAI's current behavior verified against this repo, not assumed.

## Constraints
- Timebox: one session, alongside an in-flight ride (CHANGE-0142).
- Consumption: owner-stated — adopted mechanisms must not raise per-ride
  token cost.
- STATE.yaml deliberately untouched: `current_focus` belongs to
  CHANGE-0142; this research took no focus and mutated no ride state.

## Method
- Source reading (README, methodology doc, two command templates, upgrade
  and evolving-specs guides), plus `gh api` over the open issue tracker
  sorted by comment count.
- Every "we already have this" claim verified by executing against this
  repo: `spec-lint` rule inventory, `docs/CONSTITUTION.md` + its test,
  `aai-sync.sh` copy/hash behavior, `decisions.jsonl` entry-type census.

## Findings

### F1 — Their coverage check we already have, stronger
Their `/analyze` marks "requirement with zero tasks / task with no
requirement" as CRITICAL. Verified: `spec-lint.mjs` already implements this
bidirectionally (`ac-without-test`, `test-ac-unknown`, CHANGE-0113 D2),
scoped to in-flight specs at the freeze boundary, plus
`done-without-evidence` — which they lack entirely: their gate is a
checkbox, ours demands an executable evidence cell.

### F2 — Ambiguity detection: a real gap
Their template mandates *"Mark all ambiguities: Use [NEEDS CLARIFICATION:
specific question] … Don't guess"* and blocks phase progression while any
marker remains; `/analyze` flags vague adjectives without measurable
criteria as HIGH. Our spec-lint has no equivalent rule. Field evidence from
this repo: intake CHANGE-0140 asserted a factually false claim about which
`aai-feedback-*` scripts exist; it survived into a committed intake and was
caught only by Planning reading the code.

### F3 — `unrequested` is the one detection direction we lack
Their `converge` classifies gaps as `missing` / `partial` / `contradicts` /
`unrequested`. Every check we own asks "is the requirement covered?"; none
asks "does this code answer to any requirement?". `aai-deslop` looks only at
the current diff, never at accumulated surface.

### F4 — Constitution: our design is the better bet
Verified locally: `docs/CONSTITUTION.md` is 36 lines (test-capped at 60),
each numbered article carrying a `(see: …)` pointer to the mechanism that
actually enforces it (branch-guard, tdd-evidence-check, state.mjs), with a
`## Constitution deviations` section in SPEC_TEMPLATE, an article check at
PLANNING step 10, and `test-aai-constitution.sh` pinning the shape. Theirs
is prose that `/analyze` re-reads, with conflicts auto-rated CRITICAL.
Signal worth recording from issue #860 (2-month non-technical user report):
that user wrote a 454-line constitution with 7 measurable principles and
spent a whole feature reaching 100 percent compliance — users want the
constitution to be living and measurable. We bet the opposite way (tiny
constitution, enforcement in code). Keep our bet; prose nobody executes is
not a gate.

### F5 — Installation and upgrade: the largest structural difference
Verified in our tree: `aai-sync.sh` copies the vendored layer (profile
`core` via PROFILES.yaml, or `extended` = everything), compares hashes, and
overwrites anything that differs; only files existing *solely* in the target
survive. There is no override layer, no manifest of managed-file hashes, and
no precedence stack — so a downstream project that edits a vendored file
loses the edit on the next `/aai-update`, with nowhere to put it.

Theirs, by contrast:
- Four-tier runtime resolution, first match wins: `overrides/` → `presets/`
  → `extensions/` → core templates.
- An install manifest recording each managed file's hash: *"If a managed
  integration file was modified after install, the command stops and asks
  you to inspect the change or rerun with `--force`."*
- `specs/` is "completely excluded from template packages and will never be
  modified during upgrades".
- Removal restores the next-highest-priority version automatically; `info`
  shows exactly what `install` will add.
- The tool itself installs GLOBALLY (`uv tool install specify-cli`,
  `specify self upgrade`) while the project holds only state and artifacts.
  Their issue #2612 pushes this further: *"Global installation mode —
  tooling at IDE level, project state at repo level."*

This is the root of a failure class we hit today: downstream machines ran
old vendored wrapper scripts because each project must be updated
separately, and today's CHANGE-0139 existed only because downstream
behavior had diverged.

### F6 — Spec evolution: they name three models, we practice one
`docs/guides/evolving-specs.md` distinguishes Flow-Forward (new feature
directory per change; history preserved), Living Spec (spec.md is the
contract; re-derive plan and tasks, then `/analyze`), and Flow-Back (change
may originate anywhere, with the non-negotiable rule *"Do not leave a
lower-level change in `tasks.md` or code if `spec.md` still says something
different"*). We are Flow-Forward with in-flight amendment, plus the
delta-spec lifecycle (RFC-0011 `## Deltas`) and docs-canon consolidation —
ahead of their tooling, but their vocabulary and that Flow-Back rule are
worth borrowing verbatim as review language.

### F7 — Field issues worth knowing
- #620 (13 comments) specs go stale as later features amend earlier ones —
  our docs-canon plus delta-spec lifecycle already answers this.
- #1059 re-planning overwrites the existing plan from template — our specs
  are frozen and amended deliberately; not our failure mode.
- #464 `/implement` silently substituted a textarea for the specified
  WYSIWYG library — caught in our flow by independent Validation and the
  review's spec_compliance verdict.
- #4065 dense sequential IDs (FR-###, T###) force renumbering that
  invalidates every citation. We are exposed in principle: `spec-lint` has
  an `ac-id-gap` rule that forbids gaps, i.e. it mandates the dense scheme.
  Not yet painful (small specs, append-only growth), but the escape hatch is
  currently illegal by rule.
- #641 deferring a suggestion for later review with no place to put it —
  the direct trigger for CHANGE-0142; measured locally as 1 typed
  `follow_up` entry against 14 prose FOLLOW-UP clauses in 11 entries.

## Recommendations
1. **Typed follow-up registry** — adopted, in flight as CHANGE-0142.
2. **Regenerate-after-allocate wired into the close ceremony** — local
   defect repeated twice today; queued.
3. **Ambiguity and unresolved-marker lint at freeze (F2)** — cheap, zero
   runtime cost, changes how intakes get written; queued.
4. **`unrequested` sweep (F3)** — report-only, periodic, per capability;
   queued.
5. **RFC: split the vendored layer into globally installed tooling versus
   per-project state, plus a precedence stack and a managed-file hash
   manifest (F5)** — the highest-value structural change, and materially
   broader than the "add an override layer" framing this research started
   with. Must consider `aai-update`, `aai-sync`, PROFILES.yaml and the
   prompt-diet ledger.
6. **Do not adopt**: their constitution articles (product dogma), the
   `tasks.md` artifact (STATE plus roles is richer), the checklist generator
   (fights prompt-diet discipline), and the "keep spec.md high-level, push
   detail into implementation-details/" split (our deterministic dispatch
   depends on the detail living in the frozen spec).

## Open Questions
- What does the video overview contain that the written docs do not? Not
  ingested; see Scope.
- Should `ac-id-gap` be relaxed to permit intentional gaps once specs grow
  past append-only editing (#4065 class)? No local pain yet; revisit if a
  mid-spec AC insertion is ever needed after freeze.
