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
- **Greenfield bias in THIS piece**: it addresses bootstrapping new projects
  and does not cover applying Spec Kit to an existing codebase.
  **CORRECTED by F10** — I generalized that omission into "their tool is
  greenfield-first", and the lead maintainer falsifies it directly on the
  May livestream (brownfield constitution bootstrap; 307K-line ASP.NET and
  ~400K-line Java walkthroughs). The article is greenfield; the tool is not.
  Correction kept visible rather than silently rewritten.

Consequence for us, as originally written and now narrowed: their WRITTEN
INTRODUCTORY material is greenfield-first, while this factory is
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

### F10 — Second video: the lead maintainer, current-era (2026-05-08)
The repo links TWO videos; a code search over the repo found the second in
`newsletters/2026-May.md`: "Open Source Friday with Spec-Kit", GitHub, hosted
by Andrea Griffiths with lead maintainer Manfred Riem. Captions pulled the
same way (12,070 words de-duplicated). Caveat: despite postdating the command
expansion, the stream itself never demonstrates analyze, checklist, converge
or taskstoissues; clarify appears once in passing.

- **Presets outrank the constitution for mandatory policy.** The sharpest
  transferable idea in either video: prose a human must remember to include
  is weaker than a template layer injected with priority and
  append/prepend/wrap/replace semantics — *"the constitution template would
  then actually contain that requirement and you couldn't get around it"*.
  This reframes recommendation 5: the override stack is not only a
  customization affordance, it is the enforcement surface for org policy.
- **Phase-scoped autonomy**: approvals stay on through planning and are
  released only at implementation — *"I say bypass all approvals. I did not
  say autopilot."* We express autonomy per ceremony level, not per phase.
- **Context-window utilization as telemetry, and over-specification as its
  cause.** *"the moment you start context window compaction it loses context
  which means its reliability goes down off a cliff"*; if it overflows,
  *"you probably for the models that you're using over specified"* — he
  concedes his own demo was over-specified, and reports finishing at 66
  percent of one window. We measure tokens per role but never window
  utilization, and we have never treated a long spec as a reliability risk.
- **Vocabulary independence as a cheap chaos test**: a pirate-speak preset
  renamed every artifact (spec becomes "voyage manifest") and execution was
  unaffected — *"It did not care whatsoever. It just executed it
  faithfully."* A one-off rename run would prove our dispatch keys on
  structure, not on document titles.
- **Brownfield works** (the F8 correction): *"if you have an existing
  project you are able to actually just say hey given this code base can you
  create me a set of principles … So it works for brownfield as well"*, with
  307K-line ASP.NET and ~400K Java walkthroughs. Plus a warning that lands on
  us: an inferred blanket coverage gate on legacy code *"would crunch tokens
  just to get to that point"* — gates should ramp per scope, not be constant.
- **Recursive specs**: tasks of a higher-level spec may themselves become
  specs; a maintenance plan sits *"a level higher than the spec"*. Validates
  our umbrella/child-phase pattern.
- **Community catalog is read-only by design**: *"we don't maintain them. We
  just list them here as reference"*, consumers must vet and vendor
  themselves — a deliberate supply-chain stance worth copying if we ever
  publish a skills registry.
- **Agent-neutral core, enforced by refusal**: he rejected agent-specific
  additions to core templates twice, including for the vendor's own IDE.
- Honest framing of the whole enterprise: an agent is *"a very capable intern
  and a very quick intern but it's still an intern nonetheless"*; and on
  whether SDD beats plain prompting he claims only downstream leverage, with
  regression benefit explicitly unevidenced — *"Don't quote me."*

### F11 — Project newsletters, June and July 2026
Six monthly newsletters exist (Feb–Jul); the two most recent were read.

- **They paid our exact tax and then removed it.** July ported the core
  scripts, the git extension and the agent-context updater from shell to
  Python, reason stated plainly: *"the perennial bash/PowerShell parity tax
  — every script fix previously had to be written twice and kept in sync, a
  recurring source of the Windows-parity bugs."* That is a literal
  description of our 2026-08-13: `aai-run-tests.sh` plus its `.ps1` twin,
  `aai-sync.sh` plus `.ps1`, and four CI iterations chasing WSL and 5.1
  semantics. We have mitigated the class (parity by construction, one Node
  helper called by thin twins in CHANGE-0137) without naming it; they
  eliminated it by moving the logic to one interpreter. Worth an explicit
  decision: is our remaining shell-twin surface a standing cost we accept?
- **The criticism they publish about themselves applies to us.** July:
  *"documentation proliferation and cognitive load remain the single
  most-cited concern"*; one user finished a 108-task build but flagged
  *"~15,000 lines of generated documentation"*, another named
  *"over-production of docs, and single-source-of-truth collapse."* This
  repo carries 345 docs. Our docs-canon and delta-spec machinery exist
  precisely for this, but nothing measures whether the corpus is still
  navigable by a human.
- **Their engine became programmable**: gate verdicts bind to typed workflow
  inputs (`verdict_input`), shell stdout parses to `output.data` via
  `output_format: json`, and a `from_json` filter turns step outputs into
  typed values. Prose-chaining became data-passing — the same direction our
  deterministic dispatch already took.
- **Runtime events layer with per-agent adapters** (v0.15.0): canonical
  snake_case lifecycle events dispatched from one zero-dependency script,
  translated per harness (`.claude`, `.cursor`, `.codex`, `.github`), with
  four-tier resolution and multiple extensions allowed on one event. Reason:
  extension authors *"declare events once and never learn agent-specific
  names"*. Directly comparable to our hooks overlay, but generalized.
- **"Fail loudly, don't crash"** was a named July campaign: dozens of PRs
  replaced raw exceptions with validation errors on malformed input, unknown
  fan-in step names became validation failures, unknown expression filters
  now fail loudly. Same instinct as our fail-closed ledger reads.
- **Converge's append-only invariant** is stricter than I recorded in F3:
  its only write is a new `## Phase N: Convergence` section at the bottom of
  tasks.md; it never modifies spec or plan, never renumbers, never touches
  code, and when clean leaves the file byte-for-byte unchanged. Adopt that
  invariant verbatim if we build the unrequested sweep.
- **Adoption and its shadow**: ~124k stars, 144 extensions, 29 presets by
  July. Named adopter SNCF Connect claims 2–4× velocity *"while candidly
  flagging token-cost and governance concerns"*. An independent scoring put
  Spec-Kit at 2.77 versus OpenSpec 4.00 for brownfield and developer
  experience.
- **They measure nothing themselves.** All cost signal is external —
  community extensions for token economy and model right-sizing. Our
  telemetry is the single largest capability gap in their favor, i.e. ours.
- **Agentic triage pipeline**, label-driven: `bug-assess` → `bug-test` →
  `bug-fix`. And a pre-spec `assess` extension ending in an explicit **go /
  clarify / kill** decision — the "should this be built at all" gate we lack
  (aai-scout scores readiness but never recommends killing a scope).

### F12 — The eight remaining command templates (mechanism only)
- **Anti-theater clause, repeated verbatim in every template**: after emitting
  a hook block, *"you MUST actually invoke the hook and wait for it to finish
  before continuing… Emitting the block alone does not run the hook."* A
  one-sentence defence against an agent describing an action instead of
  performing it — the exact class this factory keeps catching by hand.
- **The LLM is forbidden from evaluating gate predicates**: *"do not attempt
  to interpret or evaluate hook `condition` expressions… leave condition
  evaluation to the HookExecutor implementation."* Independent confirmation
  of our own split (scripts own gates, judgement never does).
- **`specify` caps ambiguity markers**: *"Maximum 3 [NEEDS CLARIFICATION]
  markers total"*, prioritized scope > security/privacy > UX > technical, and
  — the part that matters — an explicit DON'T-ASK default list (retention,
  performance, error handling, auth, integration patterns). Directly reshapes
  recommendation 3: a vagueness lint without a don't-ask list produces noise.
  Also a bounded repair loop: *"Re-run validation until all items pass (max 3
  iterations)"*, then warn rather than spin.
- **`clarify`**: 11-category coverage taxonomy scored Clear/Partial/Missing,
  top 5 by impact times uncertainty, hard cap *"Maximum of 5 total questions"*,
  strictly one at a time, answers bounded (2-5 mutually exclusive options or
  5 words), every question carries a **Recommended** default acceptable with
  "yes", and write-back must *"replace that statement instead of
  duplicating; leave no obsolete contradictory text"* with an atomic save
  after each integration. Question-quality grammar is pinned: a real
  interrogative, *"NEVER use a topic label, section heading, or requirement
  id as the question itself"*.
- **`checklist` is not a test plan** — it is *"UNIT TESTS FOR REQUIREMENTS
  WRITING"*, validating prose, with a prohibition list (no Verify/Test/Check
  plus behavior, no click/navigate/render). Bounds: IDs append-only, *"≥80%
  of items MUST include at least one traceability reference"*, soft cap at 40
  items. **Ownership rule worth stealing**: the command *"MUST NOT mark
  generated items [x]"* — a `[x]` means a human reviewer judged it. An
  explicit agent-maintained vs reviewer-owned split on gate artifacts.
- **`constitution` has a Scope Guard**: writes only the constitution file,
  *"You MUST NOT create, modify, or delete application source files"*, and
  *"Dependent templates and commands read the constitution at runtime and are
  not modified here"* — confirming the July removal of write-fanout.
  Principles get semver bump rules and a Sync Impact Report prepended as an
  HTML comment.
- **`implement` is the cautionary read, not a source**: against mid-flight
  deviation there is nothing but prose. The known field defect (#464, a
  library silently swapped for a textarea) is unaddressed in the template.
  On failure: halt non-parallel, continue parallel, no retry budget, no
  rollback. Our independent validation is precisely the missing organ.
- `taskstoissues` refuses hard on remote mismatch (*"UNDER NO CIRCUMSTANCES
  EVER CREATE ISSUES IN REPOSITORIES THAT DO NOT MATCH THE REMOTE URL"*) and
  is re-run-safe via word-boundary task-id matching.

### F13 — Concepts, community and installation: the anti-fork primitive
This is the layer that answers our actual downstream problem, and it is more
mechanical than the README suggests.

- **Resolution is PER FILE, not per package**: overrides → presets →
  extensions → core, and *"Each file name is evaluated independently against
  the priority stack, so different files can come from different layers."*
  A downstream can override one template without pinning everything else.
- **`wrap` is the anti-fork primitive.** Composition is not only replace:
  `prepend`, `append`, and `wrap`, where the override *"replaces
  `{CORE_TEMPLATE}` with lower-priority content"* (scripts use
  `$CORE_SCRIPT`). The downstream wrapper CONTAINS the upstream body instead
  of copying it, so upstream edits keep flowing through the wrapper. This is
  the single most important mechanism in the whole research: it is how you
  customize without forking, and we have nothing like it.
- **Overlays are diffs with fail-closed anchors**: `extends: <base>` plus
  `edits: [insert_after: <step-id> | replace: <step-id>]`, stored outside the
  installed directory so a refresh preserves them — and an overlay naming a
  step id that no longer exists *"will raise a validation error when the
  workflow is resolved"*. Overrides that break loudly when upstream renames
  something are the difference between an override layer and silent drift.
  Limits are explicit too: overlays cannot change metadata or inputs and
  *"Overlays cannot target steps added by other overlays."*
- **A managed-path manifest is what makes edits survive**: *"the file is
  tracked in the shared-infrastructure manifest: your edits are preserved on
  re-init"*. Combined with the hash manifest from F5, this is the complete
  answer to `aai-sync` overwriting local work.
- **A trace command exists**: `specify preset resolve <name>` *"shows which
  file will be used… by tracing the full resolution stack."* Any precedence
  stack we build needs its own explain-why command from day one.
- **Config layering** for extensions: defaults → version-controlled
  `<ext>-config.yml` → gitignored `<ext>-config.local.yml` → environment.
  Maps cleanly onto our update-config plus a future machine-local file.
- **Their own pin enforcement is weaker than advertised** — a warning we
  should design against, not copy: *"Pin enforcement is install-time only.
  Idempotency checks are id-based, not version-aware: a component that is
  already present is skipped during install without comparing its on-disk
  version to the manifest pin."* Id-based idempotency silently keeps stale
  layers. Our sync must compare versions, not presence.
- **Write-permission grades per phase, stated as contracts**: `analyze` is
  read-only and must *"fix them at the source"*; `converge` is append-only,
  *"its only possible write is adding tasks to `tasks.md`"*. We enforce the
  same shape by role prompt and review culture; stating it as a per-phase
  permission grade is tighter.
- **Definition of done as a fixpoint**: *"Converged — no gaps found.
  `tasks.md` is left byte-for-byte unchanged."* Byte-identity as the
  done-oracle is a cheap, forgery-resistant evidence idea.
- **Checklist ownership invariant, repeated across docs**: `[x]` means a
  human reviewer judged the criterion satisfied, and `/speckit.implement`
  *"must not change checklist markers"* — only the built-in
  `checklists/requirements.md` is agent-maintained.
- **Their trust signal is not a trust signal.** Maintainers *"do not review,
  audit, endorse, or support the extension code itself"*; `verified` is a
  formatting badge. Community catalogs are discovery-only by default and
  installing requires explicitly adding an install-allowed catalog. If we
  ever publish a registry, copy the posture, not the badge.
- **Their docs drift too**, found deliberately: two mutually exclusive
  preset-submission paths in one file, `verified` described two
  contradictory ways, a documented command name that does not exist
  (`extension add-catalog` vs the real `extension catalog add`), and a
  "coming in Phase 4" FAQ for a shipped feature. Independent argument for the
  anti-drift suite we built in CHANGE-0140.
- **Security note worth keeping**: their workflows reference states plainly
  that there is *"no shell-escaping filter"* and *"no sandbox around a
  `shell` step"*, that *"Quoting is not a security boundary"*, and that gates
  *"do not inspect the next step"* so *"approval never neutralises an
  injectable interpolation."* If we ever interpolate agent output into a
  shell step behind a human gate, that is the failure mode, stated better
  than anywhere in their corpus.
- Monorepo constitutions have *"no built-in base/inheritance mechanism"* —
  duplicate or sync per project. Our vendored layer already beats that.

### F14 — Project history, February to May 2026 (the most instructive read)
- **They paid our parity tax for four months before paying it off.** The fix
  log runs: PowerShell 5.1 compatibility restored (March), BSD-portable sed
  escaping, PowerShell positional binding, CRLF warnings, UTF-8 BOM stripping
  (April), PowerShell UTF-8 BOM and a Windows gate-step crash (May) — then
  July ports the scripts to Python. Every one of those has a twin in our own
  2026-08 log. April also replaced shell-based context updates with
  marker-based upsert *"eliminating accidental context file bloat"* — the
  first admission the shell approach was structurally wrong, three months
  before the port. Reading their arc, the question for us is not whether the
  shell-twin surface costs us, but whether we keep paying monthly.
- **Windows entered their CI matrix only in month three**, after the breakage
  above. We added real Windows coverage in CHANGE-0134/0136 for the same
  reason, independently. Two projects, same lesson, both late.
- **Constitution propagation peaked in May and was removed in June/July.**
  May explicitly added constitution loading to `/implement` *"to enforce
  governance during code generation"*; six weeks later template propagation
  was deleted in favour of runtime read. Anyone tempted to make governance
  text fan out into other artifacts should read that reversal first — our
  pointer-based articles are already on the surviving side of it.
- **Bundles were killed in April and rebuilt in June.** The April removal of
  template zips is justified as *"the CLI itself now handling all scaffolding.
  This ensured CLI and templates stay in sync."* That is a live caution for
  our recommendation 5: a distribution layer decoupled from the tool drifts
  from it, and they deleted theirs for exactly that reason before
  reintroducing it with version pinning. The RFC must answer how the
  precedence stack stays in sync with the tool that reads it.
- **Deprecation discipline worth copying**: every removal is announced with a
  target version gate (`--no-git` announced April, removed at v0.10.0 in
  June). Our vendored layer changes downstream behavior with no such runway.
- **The only adversarial measurement in the entire corpus** (March, Isoform
  controlled test): SDD took *"33 min / 689 lines vs 8 min iterative
  prompting"* with *"no measured quality improvement"*. It was never rebutted
  with counter-data. That is the honest ceiling on this whole paradigm for
  small scopes, and it is the strongest external argument for our ceremony
  levels — and against adding ceremony to L0/L1 lanes.
- **Ceremony overkill for small tasks is a complaint in all four months**,
  answered with a lean preset, never with a core change. **Spec drift is the
  top roadmap item four months running, still unsolved in core** — March
  notes *"native real-time drift detection is not yet in core"*. Their
  community solved phantom completions (*"tasks marked done with no real
  code"*) with an extension; we solved it in core with
  `done-without-evidence`.
- **Independent verification is named but not built**: May quotes an analyst
  — *"verification at each checkpoint cannot be deferred to the agent
  producing it"*. That sentence describes our Validation role, which their
  pipeline still lacks.
- Supply-chain posture arrived only after the catalog passed 100 entries
  (SHA-pinned Actions, URL scheme validation, labeled-event-only submissions,
  confirmation on URL installs), and two community extensions were already
  removed as dead repositories — the open catalog rots.

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
   prompt-diet ledger. **Concrete design inputs now available (F13):**
   per-file resolution rather than per-package; `wrap` with a `$CORE_SCRIPT`
   / `{CORE_TEMPLATE}` placeholder as the anti-fork primitive so a downstream
   override contains the upstream body instead of copying it; overrides
   stored outside the managed directory so refresh preserves them; anchors
   that FAIL CLOSED when upstream renames the thing they target; a
   managed-path manifest as the mechanism that makes edits survive; a
   `resolve`-style trace command from day one; and config layering
   (defaults → tracked → machine-local → env). **Two cautions from their own
   history:** they deleted the distribution layer in April because it drifted
   from the tool (*"the CLI itself now handling all scaffolding. This ensured
   CLI and templates stay in sync"*) before rebuilding it in June — the RFC
   must answer how the stack stays in sync with the tool that reads it; and
   their pin enforcement is install-time only with id-based idempotency, so
   ours must compare versions, not presence.
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
