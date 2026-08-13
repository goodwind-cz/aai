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
- INGESTED after the owner's "install it yourself" (see F9): the README's
  video overview
  <https://www.youtube.com/watch?v=a9eR1xsfvHg> — "The ONLY guide you'll
  need for GitHub Spec Kit" by Den Delimarsky (@DenDev), a spec-kit
  maintainer. First pass failed — WebFetch returns only the YouTube page
  shell and the public timedtext caption endpoint returns empty — so the
  early revision of this document recorded the video as an explicit gap.
  Resolved on the owner's instruction to install the tooling: yt-dlp
  (2026.07.04) pulled the auto-captions, de-duplicated to a 7012-word
  transcript, digested in F9 under its early-release dating caveat. The
  same author's long-form written treatment is folded in as F8 (den.dev
  returned HTTP 403, so the Microsoft Developer Blog copy was used).

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

### F8 — The maintainer's own framing (written substitute for the video)
Source: Den Delimarsky, "Diving Into Spec-Driven Development With GitHub
Spec Kit", Microsoft Developer Blog. Distinctive claims worth keeping:
- *"Code is inherently a binding artifact — once you write an
  implementation, it's very hard to decouple from it."* Left unspecified,
  *"the codebase becomes the de-facto specification — a collection of
  seemingly disjoint components that can work together but are hard to
  maintain, evolve, and debug."*
- SDD is explicitly *"not about writing exhaustive, dry requirements
  documents that nobody reads"* and *"not about waterfall planning"*; specs
  are *"living documents that evolve alongside your code"* and *"active
  tools that help you think through edge cases, coordinate across teams,
  and onboard new people."*
- Honest self-assessment: the toolkit is *"an experiment"* with *"a lot of
  questions that we still want to answer."*
- Practice note: *"having a very detailed first prompt will produce a much
  better specification"* — quality is front-loaded into the human's opening
  statement.
- **Greenfield bias, stated by omission**: the piece addresses bootstrapping
  new projects and does not cover applying Spec Kit to an existing codebase.

Consequence for us: their tool is greenfield-first, while this factory is
brownfield-native — it runs against a live repo of 344 docs with its own
history, telemetry and gates. That difference explains most of the delta
found in F1-F7: they optimize the first mile (get a good spec out of a vague
prompt), we optimize the long tail (keep hundreds of artifacts honest as
they age). Their front-loading insight still lands on us as F2: the cheapest
place to catch a bad scope is the intake sentence, not the review.

### F9 — The video, actually ingested (yt-dlp auto-captions)
Owner instruction "install it yourself": `brew install yt-dlp` (2026.07.04),
auto-captions pulled and de-duplicated to a 7012-word transcript.
**Dating caveat that governs every quote below**: the video was recorded
about a week after release, when the flow was only `/specify`, `/plan`,
`/tasks` — no `clarify`, `analyze`, `constitution` or `implement` command
existed. What he does by hand there is largely command-ified today, so read
it as pre-history, not as current practice. Auto-captions are unpunctuated
and garble names.

Signal worth keeping:
- **Governance artifacts get edited by the agent.** He reports Sonnet going
  *"off the rail"* at the constitution step: *"it starts editing the
  constitution file and then it starts creating more files."* Checked
  against this repo: `docs/CONSTITUTION.md` IS listed under
  `protected_paths_l3` in docs/ai/docs-audit.yaml, so the failure mode is
  already fenced here. Recorded as a validated design choice, no action.
- **Fabricated research presented as research.** *"copilot in this case did
  not do the actual research it used its training data to come up with this
  research."* Same class as our own 2026-08-13 defect where intake
  CHANGE-0140 asserted a false fact about which scripts exist. Independent
  corroboration for recommendation 3 (mark, do not assert).
- **The checklist is the real gate**, not the prose: *"you got to make sure
  that the acceptance checklist is actually filled out"*, and he ticks the
  no-needs-clarification box explicitly before moving on. Corroborates F2.
- **Model routing by phase**: GPT-5 through spec/plan/tasks, Sonnet for
  code — *"GBD5 is good at setting up the spec scaffolding for us but for
  creative output Sonnet 4 is still unbeatable to me."* We hold a
  MODEL_ROUTING doc but currently run every role on one model; with TDD
  Implementation measured as our most expensive role (median ~220k tokens),
  phase-differentiated routing is a live cost lever, not a theory.
- **Spec is the durable asset, code is regenerable**: *"You can just delete
  the source. The spec is still there and then use a different model"*. A
  prototype-scale stance — we remediate rather than regenerate — but it is
  the sharpest statement of why the spec outranks the code.
- **Humans should hand-edit the artifacts**: *"People make the mistake of
  thinking that oh the LM produced this I can only manage this with [an
  LLM]. No, it's a markdown file. Go in with your hands and start typing."*
- **He does not claim SDD improves first-pass output.** Asked whether this
  beats vibe coding, the answer is entirely downstream leverage: the spec
  becomes reusable context for additive features. Honest, and it matches
  what our own telemetry shows — the payoff is in the long tail.
- **No token or cost discussion anywhere in the video.** Their material has
  no economics; ours is instrumented end to end. Nothing to learn, worth
  knowing.
- Brownfield: still only an aside (the `.specify` folder exists so an
  existing project is not littered at root). Confirms F8's greenfield bias.

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
6. **Interactive CLI installer/configurator (OPTIONAL, owner-flagged
   2026-08-13: "for less skilled users")** — their `specify init` is a
   guided provisioning step; ours is a file copy plus tribal knowledge.
   Verified: the settings a newcomer would want already exist and already
   work — `docs/ai/update-config.yaml` carries `mode: notify|auto`
   (CHANGE-0091, fired from the SessionStart hook as a side effect of normal
   use), `throttle_hours`, and `post_update_doctor` (CHANGE-0137). Nothing
   discovers them for you: you must know the keys exist and hand-edit YAML.
   An `init`/`config` command would ask the few real questions (notify vs
   auto update, throttle, post-update doctor, profile core vs extended,
   which agent harnesses to provision) and write the answers.
   Design constraints to carry into the RFC, non-negotiable in this repo:
   the interactive path must be a thin layer over deterministic flags with a
   non-interactive twin (`--yes` plus explicit flags), because CI, agents
   and every test in tests/skills must never depend on a prompt; and it must
   print exactly what it will write BEFORE writing, mirroring their
   `info` shows exactly what `install` adds guarantee. Scope it as optional
   UX on top of recommendation 5, never as a required entry point — the
   existing non-interactive paths stay first-class.
7. **Do not adopt**: their constitution articles (product dogma), the
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
