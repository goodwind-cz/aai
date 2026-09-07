---
id: mechanical-context-offload-to-cheap-tier
type: research
number: 2
status: done
links:
  pr:
    - 357
  commits:
    - 1a386877
    - 60912836
---

# Research — Offloading Mechanical Context Work to a Cheap Tier

## Research Question

Can AAI meaningfully cut autonomous-run token cost by keeping *mechanical
context work* off the expensive model — bulk file reading and pattern-copy code
generation — and is a **hard pre-tool block**, rather than a written
instruction, the mechanism that makes such a rule actually hold?

Sub-questions:

1. **Where does the money go?** Over the runs AAI has already recorded, how much
   of the token spend is plausibly mechanical (opening files to answer a
   question about one of them, writing a test that copies the shape of the
   twenty next to it) versus genuine judgment?
2. **Does "block, not instruct" apply here?** AAI encodes routing intent in
   `.aai/system/MODEL_ROUTING.yaml` and in prompt text. Both are *advisory* at
   the point of use. Is there an enforcement surface that can refuse an
   expensive-model tool call and reroute it, and what would it cost to gain one?
3. **What breaks, and where is the floor?** The source names three things it
   refuses to delegate on purpose. Which AAI roles fall inside that same fence?
4. **Can the routing be harness-universal?** AAI is meant to run under whichever
   agent hosts it — Claude Code, Codex, Gemini, or the next one. A routing table
   that names one vendor's model ids cannot follow it there. What shape does the
   routing contract need so that a tier resolves to the right model *for the
   harness the run is actually on*, without hardcoding a table per harness?

### Source and its standing

Primary source: Spotify Engineering, "Portal by Spotify cut my Claude Code token
usage by 90%", Dimitri Mazmanov, 2026-09-03,
`engineering.atspotify.com/2026/9/portal-by-spotify-cut-my-claude-code-token-usage-by-90`.
Read directly for this intake, not taken second-hand.

**The headline number is much narrower than its circulation suggests, and this
distinction is load-bearing for the whole spike.** The author's claim is a *mean
saving on bulk reads*, measured across *four scenarios on one Java monorepo*, by
*one author*. It is a single-author case study, not an audited company-wide
result. The author explicitly declines to quantify the code-writer saving at all,
because without the router the frontier model both reads the reference files and
emits the result as expensive output tokens, so there is no clean comparison.

**Do not repeat the adoption figures circulating in secondary coverage.**
Aggregator write-ups of this post assert things like "1,300+ engineers across
36,000+ sessions". The primary article contains **no** adoption numbers of any
kind. Those figures were checked against the source during this intake and did
not survive. Any number entering this document must come from the primary source
or from our own ledger.

The spike was prompted by an infographic post on X
(`x.com/undefinedKi/status/2095942506433089832`, 2026-09-04) which summarizes the
same architecture accurately but is titled in a way that reads as a
company-wide 90% cut. That framing is what this section exists to correct.

### The mechanism, stated concretely

Worth recording because the spike is assessing *this* design, not a paraphrase:

- **Two PreToolUse hooks are the only enforcing layer.** `check-file-size` fires
  on every Read call; `check-bash-read` catches the same read done through
  `cat`, `head`, `tail`, `less`, `more`.
- **Threshold is configurable**, `SHUNT_MIN_LINES`, default 350 lines. Over it,
  the read is refused and the block message names the alternative.
- **Targeted reads with an offset and a limit deliberately pass through.** This
  is the escape hatch that keeps editing possible.
- **Two cheap worker modes**: `bulk-reader` returns structured bullets only, no
  prose; `code-writer` matches a required reference file and writes straight to
  disk. Both run at temperature 0.2 on a cheaper model (Gemini 2.5 Flash in the
  post, configurable) — note the cheap tier is a *different vendor*.
- **Three layers, one authority.** Hooks refuse; scripts carry the transport;
  skills are advisory markdown. The author is explicit that the first version
  lived in `CLAUDE.md`, was read as advice, and was ignored often enough to
  fail. Moving the decision into a hook is described as the whole fix.
- **Public artifacts exist**: plugin `shunt`, repo `spotify/portal-ai-plugins`.

### What is already harness-neutral here, and what is not

Measured during intake, because it decides how large this work actually is.
AAI is multi-harness at both ends of the stack and single-vendor in the middle:

- **Below — `.aai/system/PRICING.yaml` is already multi-vendor.** It carries
  provider entries for anthropic, openai, google and deepseek, and prices
  concrete non-Anthropic ids including `gemini-2.5-flash` (the exact worker
  model the Spotify post uses), `gpt-5.3-codex` and `deepseek-v4-flash`. Cost
  attribution for a cross-vendor worker therefore already works.
- **Above — the harness layer already branches.** `routine-emit.mjs` emits
  per-harness invocations for `claude`, `codex` and `gemini`;
  `.aai/system/HARNESS_SKILLS.yaml` governs mirror trees including
  `.codex/skills` and `.agents/skills`; `state.mjs log-tick` records a
  `harness_version`.
- **Middle — the routing contract is harness-blind, and this is the gap.**
  `MODEL_ROUTING.yaml` binds `tiers` and `roles` to Anthropic model ids only,
  and `suggestModel()` in `orchestration-dispatch.mjs` resolves
  `roles[role@lane] ?? roles[role] ?? tiers[tier]` with no harness dimension.
  `orchestration-dispatch.mjs` takes no harness flag at all.

So the layer that must change is narrow and identified. The tier abstraction
(`mechanical` / `standard` / `premium`) is already the right seam — it is the
binding from tier to a concrete id that wrongly assumes one vendor.

The project already holds a rule that constrains the fix: **never hardcode
harness capability tables; detect capability at runtime and record requested
versus actual model in telemetry.** A static per-harness matrix would violate it.

## Scope

- In scope:
  - Measurement over the local ledgers: `docs/ai/METRICS.jsonl` and
    `docs/ai/EVENTS.jsonl`.
  - Audit of the current routing contract, `.aai/system/MODEL_ROUTING.yaml` —
    tier defaults, per-role pins, lane-scoped keys, advisory effort hints — and
    where its intent is honored versus merely suggested.
  - Audit of the enforcement surface available to this repository, including
    the fact that no `.claude/settings.json` and no hooks exist today.
  - Reading the public `shunt` plugin source for the actual hook contract,
    rather than reasoning from the article's prose.
  - **Design (not implementation) of a harness-universal routing contract**: how
    a tier resolves to a concrete model under whichever agent hosts the run,
    how the harness is detected rather than declared, and what the fallback is
    when a harness offers no cheap tier at all.
  - Prioritized recommendations, each sized S/M/L with expected impact and the
    follow-up type (RFC or CHANGE) it should become.
- Out of scope:
  - Implementing any hook, subagent, or routing change. Research only; every
    action item leaves as a follow-up intake.
  - Redesigning MODEL_ROUTING semantics or the dispatch model.
  - Reproducing Spotify's benchmark or producing our own 90%-style headline.
  - Adopting Portal itself. Portal is Spotify's internal platform; the routing
    pattern is what transfers, not the product.
  - Any change to the harness or to paid-run configuration.

## Success Criteria

- Findings captured in the Findings and Recommendations sections of this
  document. This document is the deliverable; `done` means findings captured.
- A quantified baseline from real recorded data: token totals grouped by role
  and by model id across the runs the ledger holds.
- An estimate of the share attributable to mechanical context work, stated
  together with its method and its error bars. An honest "cannot be attributed
  from current data, here is what instrumentation would be needed" is an
  acceptable and expected outcome for part of this.
- A verdict on enforcement: whether a pre-tool block is available here, what it
  would cost, and what it would break.
- An explicit do-not-delegate list for AAI roles, argued rather than inherited.
- Named follow-ups, each sized S/M/L, ordered by expected saving per unit of
  effort.

## Constraints

- Timebox: 2 days.
- Access, data, tools: local repository and its ledgers, plus the public article
  and plugin source. No paid benchmark runs.
- **Measured data limit (established during intake, not assumed).** In
  `docs/ai/METRICS.jsonl`: `tokens_in`, `tokens_out`, and `cost_usd` are null in
  every record — zero records carry a structured token count. The only usable
  signal is `usage_total_tokens=N` embedded in the free-text `note` field of
  `agent_runs` entries, present 384 times. Consequently **no per-tool-call
  attribution exists**: the ledger can say what a role's run cost in total, but
  not how much of that went to reading a large file. Any per-Read figure in this
  spike is an approximation whose method must be stated, or a proposal for new
  instrumentation.
- `model_id` is recorded per run but is the literal string `unknown` on 26
  runs, and one value carries a harness suffix (`claude-opus-4-8[1m]`). Grouping
  must normalize and must report the unattributable remainder rather than
  silently dropping it.
- Ledger scale is modest: 167 lines in METRICS.jsonl. Conclusions are directional
  for this project, not statistically strong, and must be stated as such.
- **Transport is not free and not inherited.** Spotify's implementation delegates
  through an internal Portal instance. AAI has no equivalent; any adoption needs
  its own way to invoke a cheap worker. The pattern is portable, the plumbing is
  not.
- **Latency floor.** Each delegation is a network round trip of 10 to 30 seconds,
  capped at 30. The 350-line threshold exists precisely because below it the
  overhead costs more than the tokens saved. Any AAI threshold must be derived
  from our own numbers, never copied.
- No secrets are referenced by this scope; the secrets preflight does not apply.

## Method

- Extract `usage_total_tokens` from the note field across all `agent_runs`,
  normalize `model_id`, and group spend by role and by model. Report the
  `unknown` remainder explicitly.
- Cross-read the routing contract against that grouping: for each role, compare
  the tier MODEL_ROUTING intends against the model actually recorded, and
  quantify the gap. A role routed to premium that is doing mechanical work is
  the primary finding this spike is hunting.
- Characterize mechanical work concretely for AAI rather than by analogy: which
  roles read many files to answer a narrow question, and which produce code or
  docs that copy an adjacent pattern. Sweep for evidence in the notes and in
  EVENTS.jsonl rather than reasoning from the prompt text alone.
- Read the `shunt` hook implementation for the real contract: what a PreToolUse
  hook can refuse, what the block message can carry, and how the offset-and-limit
  escape hatch is expressed.
- Assess the enforcement surface for this repo: what adding a
  `.claude/settings.json` would commit us to maintaining, and how a block would
  interact with AAI's dispatch and with the no-mid-session-flip rule already
  written into MODEL_ROUTING.
- Derive our own threshold candidate from our own file-size and run-duration
  distribution, and test it against the latency floor.
- Locate the AAI analogues of the three never-delegated cases, in particular the
  missed thread-safety bug, against the `validation_alternate` backstop already
  in the routing contract.
- Establish what each harness actually offers as a cheap tier and as a
  delegation primitive, and how the running harness becomes known to dispatch.
  Requested versus actual model goes into telemetry either way. No hardcoded
  per-harness capability table.
- Where measurement is impossible with current data, specify the smallest
  instrumentation change that would make it possible, and size it.

### Leading hypothesis — harness scoping by suffix key

Stated up front so the spike can attack it rather than wander. This is a
**candidate to falsify, not a conclusion**; it earns a place in Recommendations
only if the checks below pass.

**The claim.** Harness-universal routing needs no new mechanism, no capability
probe in the resolver, and no per-harness adapter. It needs one more key form in
the existing flat map, resolved by an extended lookup chain:

```
mechanical: claude-haiku-4-5
mechanical@codex: gpt-5.3-codex
```

with resolution order:

```
roles[role@harness] ?? roles[role@lane] ?? roles[role]
  ?? tiers[tier@harness] ?? tiers[tier] ?? null
```

Harness is the outer dimension (what the host *can* do); lane is the inner one
(what the ceremony *warrants*). The composite `role@lane@harness` is
deliberately excluded until a real case demands it.

**Why this shape, in evidence gathered during intake.**

- The parser needs no change. `loadModelRouting()` matches
  `^ {2}([^:#]+):\s*(\S+)\s*$` one level deep, and the file header pins that
  depth on purpose. A key containing `@` is just a string to that regex —
  verified by running `mechanical@codex: gpt-5.3-codex` through the unchanged
  pattern during intake.
- The form already exists in this very file. `Validation@lightweight` introduced
  suffix-key scoping for the ceremony lane, additively, with configs lacking the
  suffix resolving byte-identically. This extends a proven pattern rather than
  inventing one.
- `orchestration-dispatch.mjs` is the only code consumer; the other hits are
  prompts and docs. The blast radius is one function.
- The tier names are already semantic (`mechanical` / `standard` / `premium`)
  rather than vendor-shaped, which is precisely what lets a tier mean something
  under a harness that has no Anthropic model at all.
- Cost attribution is not a blocker: `PRICING.yaml` already prices
  `gemini-2.5-flash`, `gpt-5.3-codex` and `deepseek-v4-flash`.

**Why the two alternatives are expected to lose.**

- *A nested per-harness section* breaks the one-level parse discipline the file
  header pins deliberately, for a gain the suffix form already delivers.
- *A capability probe inside `suggestModel()`* would destroy the property that
  makes that function testable: it is pure today, taking `(out, routing)` and
  touching neither disk nor network. A probe adds latency to the dispatch path
  and a new failure mode. Capability detection belongs at the boundary where the
  harness is identified, and in telemetry as requested-versus-actual — not in
  the resolver.
- *Late resolution in a per-harness adapter* is the hardcoded harness table the
  project already forbids, merely distributed across N adapters instead of one
  auditable file, and it empties `suggested_model` from the dispatch verdict.

**How the harness becomes known.** Declared, not sniffed. `--harness` is already
the established channel (`SKILL_LOOP`, `SKILL_ROUTINE`, `state.mjs log-tick`).
An environment hint (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `GEMINI_HOME`, already
trusted by `generate-live-status.mjs`) may inform a default. An unknown harness
resolves to the plain unsuffixed tier and says so; it never guesses.

**The failure mode this must not ship with.** When `tier@harness` misses while
the harness is *known*, resolution falls through to the plain tier — possibly a
frontier model. That is a silent cost regression wearing the word "universal".
The verdict must therefore carry an explicit fallback marker so the miss is
measurable rather than invisible.

**What would falsify this hypothesis.**

- A harness whose cheap tier cannot be named as a static id at all, because the
  model is chosen by the host at call time. Then a static map cannot express the
  binding and late resolution wins.
- Evidence that the harness is genuinely unknowable at dispatch time in a real
  lane, making the declared `--harness` channel unreliable rather than merely
  manual.
- A measured cost where the fallback marker shows the plain-tier fallthrough
  firing often enough that per-harness completeness, not the key form, is the
  actual problem.

## Findings

Elapsed effort on this spike, measured against `docs/ai/STATE.yaml`'s
`agent_runs` ledger for this ref as of the code-review dispatch
(2026-09-07T12:21:42Z): six recorded dispatches (Planning, Implementation,
Validation, Remediation, Validation, Code Review) totaling 5564 seconds
(1.55h) of summed agent time and 908,861 harness-reported tokens, against the
2-day timebox. This is a floor, not a final total: `agent_runs` grows with
every further dispatch this ride makes (this remediation among them), so a
reader should sum the list at `docs/ai/STATE.yaml` directly for the current
count rather than treat the figure above as closed. All figures below are
taken at commit `8d967f47` (the base of this worktree), reproduced by
`node docs/analysis/mechanical-context-offload/ledger-token-attribution.mjs --path <snapshot of docs/ai/METRICS.jsonl at 8d967f47>`.

### Baseline: token totals by normalized role and normalized model id

Full stdout, unedited, from the measurement script against the pinned snapshot:

```
snapshot=<scratch>/metrics-at-base.jsonl
work_items=135 (missing_agent_runs_field=3, empty_agent_runs_array=2)
agent_runs=611
with_usage_marker=384
without_usage_marker=227
tokens_total=59685340
multi_marker_records=0 (first occurrence taken when a note carries more than one usage_total_tokens= marker)

--- tokens by normalized role (marker-bearing runs only) ---
role=TDD Implementation tokens=14857259 no_marker_runs=21
role=Validation tokens=12938846 no_marker_runs=46
role=Remediation tokens=10420497 no_marker_runs=28
role=Code Review tokens=10016256 no_marker_runs=47
role=Planning tokens=8749635 no_marker_runs=47
role=Implementation tokens=2702847 no_marker_runs=38
role_row_sum=59685340 (equals tokens_total: true)
role_folded_count=7 (free-text role variants folded onto a canonical prefix)
role_unfolded_remainder=none

--- tokens by normalized model_id (marker-bearing runs only) ---
model_id=claude-sonnet-5 tokens=26028773 no_marker_runs=62
model_id=claude-opus-4-8 tokens=18276754 no_marker_runs=71
model_id=claude-fable-5 tokens=7953415 no_marker_runs=41
model_id=claude-opus-5 tokens=7426398 no_marker_runs=0
model_row_sum=59685340 (equals tokens_total: true)
model_suffix_folded_count=63 (runs whose raw model_id carried a bracket suffix, e.g. [1m])
model_unknown_count=26 (raw model_id missing or literal "unknown")

--- no-usage-marker remainder, by normalized role and by normalized model_id ---
without_usage_marker total=227
no_marker role=Planning count=47
no_marker role=Code Review count=47
no_marker role=Validation count=46
no_marker role=Implementation count=38
no_marker role=Remediation count=28
no_marker role=TDD Implementation count=21
no_marker model_id=claude-opus-4-8 count=71
no_marker model_id=claude-sonnet-5 count=62
no_marker model_id=claude-fable-5 count=41
no_marker model_id=unknown count=26
no_marker model_id=claude-sonnet-4-6 count=18
no_marker model_id=deepseek-v4-flash count=5
no_marker model_id=gpt-5.6-sol count=3
no_marker model_id=gpt-5.5 count=1
```

Both role-row and model-row sums reconcile exactly to `tokens_total=59685340`.
The denominator for any share stated below is **611 runs**, not the 384 that
carry a marker — the 227 without one (37%) are a real gap in coverage, not
zero-cost runs, and are printed above rather than dropped.

Two normalization facts the raw ledger hides: the role axis folds 7 hand-written
singletons (`Implementation (loop)`, `Remediation (E1 over-kill)`,
`Code Review (re-review)`, `Remediation (W1 POSIX)`,
`Remediation (P1+P2 Codex)`, `Remediation (WARNING-1 firstCommitDate)`,
`Remediation (Copilot nits + Codex P2 inline-agent_runs)`) onto their
canonical prefix, all 7 folding cleanly with zero unfolded remainder; the model
axis folds 63 harness-suffixed ids (`claude-opus-4-8[1m]` onto
`claude-opus-4-8`) and keeps 26 `unknown` runs as their own visible bucket
rather than merging them into any concrete model.

Cross-vendor runs are real today, not hypothetical: `deepseek-v4-flash`,
`gpt-5.6-sol` and `gpt-5.5` runs already exist among the 227 no-marker rows -
all nine of them, meaning their token spend is precisely what is not
recorded; cross-vendor spend is exactly the quantity the ledger cannot show.
A routing contract that assumes one vendor is a contract this ledger has
already been run against and violated, on the runs axis if not (yet,
measurably) on the spend axis.

### Estimated mechanical share

No per-tool-call attribution exists in either ledger. `docs/ai/EVENTS.jsonl`
was swept for a file-count or tool-name signal (`grep`-based classification
over its `event` field) and carries none: its ten event types
(`ac_evidence`, `ac_status`, `code_review_completed`, `doc_lifecycle`,
`docs_audit`, `metric_retired`, `phase_confirmed`, `ride_gate_override`,
`validation_verdict`, `work_item_closed`) record document and gate
transitions, never a tool call or a file path read - every record's key set
is `actor / event / payload / ref / ts / v`, with no field carrying a tool
name or a file path. The only resolution available is a role-level proxy,
stated as an explicit bound over the roles it covers, never as a measurement
of what actually happened inside a run.

Method: the do-not-delegate table below (Spec-AC-05) classifies
`Implementation` and `TDD Implementation` as `delegable` — the two role keys
whose core output includes pattern-copy code generation and bulk reference
reads, the shapes this spike is assessing. Those two roles account for, under
this document's own role-axis normalization above (which folds
`Implementation (loop)` onto `Implementation`), 48 + 84 = 132 of the 611
recorded runs. That is an upper bound only: it treats every token in a
`delegable`-classified run as potentially mechanical, when in fact each such
run also contains the judgment step (deciding what to implement, wiring,
correctness) that stays on the expensive model regardless. The lower bound is
0%, because no data in either ledger can confirm that any token within those
132 runs actually went to a bulk read or a pattern-copy write rather than
judgment.

Estimated mechanical share: 0% to 21% of 611 runs

That run-count share answers the shape of Spec-AC-03's template
(`<low>% to <high>% of <denominator> runs`) but not, by itself, the intake's
sub-question 1 ("how much of the token spend is plausibly mechanical") - that
question is about tokens, not runs, and this document's own baseline table
holds the token-weighted answer: `Implementation` (2,702,847) + `TDD
Implementation` (14,857,259) = 17,560,106 of the 59,685,340 marker-bearing
tokens = **29.4%**, the token-weighted upper bound. The two figures diverge
because run count and token count are not proportional across roles; the
run-count figure is what Spec-AC-03 requires verbatim and stays above
unchanged, and the token-weighted figure is what answers sub-question 1.

**What these two figures do NOT bound, and in which direction.** Both are
upper bounds *for the two roles the do-not-delegate table classifies
`delegable`*. Neither is an upper bound on mechanical work across the
factory, because a role classified `never` can still perform mechanical work
that this arithmetic excludes outright - `.aai/SKILL_CODE_REVIEW.prompt.md`
requires Code Review to read the full diff, which is bulk reading by any
definition, and Code Review alone carries 10,016,256 marker-bearing tokens.
So as a statement about the two delegable roles these figures are ceilings;
as a statement about the factory's total mechanical spend they are a
**floor**, and the real opportunity is larger by an amount this data cannot
resolve. Read them as a safely-delegable-role share, not as the global
mechanical share, and treat the recommendation ordering below as ordered on
that narrower basis. Closing this gap needs per-tool attribution, which is
exactly what Recommendation 2 proposes.

Instrumentation that would replace this proxy with a measurement: extending
`.aai/scripts/state.mjs`'s `append-run` capture so a run records a coarse
tool-call histogram (count of Read/Bash-read calls above a line threshold
versus Edit/Write calls) alongside `usage_total_tokens`, sourced from
whatever per-tool detail the hosting harness already exposes in its own
transcript. That is a schema change plus a new capture point, not a one-line
addition, and its size is bounded by "extend one script's capture path," not
by any change to STATE.yaml's own contract.

Instrumentation: .aai/scripts/state.mjs - size M

### Enforcement verdict

Surface evidence, measured at the base commit: `.claude/settings.json` does
not exist in this repository (`ls .claude/settings.json` returns not found).
`.claude/` today holds only `skills/`. There is no `PreToolUse` hook
registered anywhere in this project.

The hook contract this verdict reasons from is source-verified, not
article-derived: `plugins/shunt/hooks/check-file-size`,
`plugins/shunt/hooks/check-bash-read` and `plugins/shunt/hooks/hooks.json`
were fetched directly from `spotify/portal-ai-plugins` (branch `main`) on
2026-09-07 via the GitHub API, not reasoned from the blog post's prose. The
mechanism is exactly as simple as the intake described: a `PreToolUse` hook
matched on `Read` and on `Bash` receives the tool call as JSON on stdin, runs
`wc -l` against the target file, and returns `{"decision": "block", "reason":
"..."}` when the file exceeds `SHUNT_MIN_LINES` (default 350) and there is no
`offset`/`limit` on the call (the escape hatch that keeps editing possible)
and no pipe or redirection on the `Bash` command.

This mechanism could be replicated here — `.claude/settings.json` accepting an
`env` block and a `PreToolUse` hooks array is a Claude Code primitive, not a
Portal-specific one. Two costs make it more than "add a file," though:

1. **It is a mid-session model flip by construction.** MODEL_ROUTING.yaml's
   own header pins a hard rule, stated there as no mid-session flip: never
   flip a role's effort or model inside one running session/context, because
   prompt cache read pricing depends on the model/effort key staying
   byte-identical for the life of the session. A `PreToolUse` block-and-reroute
   does exactly what that rule forbids: it intercepts one tool call
   mid-dispatch and answers it on a different model, inside the same running
   Implementation (or TDD Implementation) session. Every delegated call is a
   small, deliberate violation of AAI's own no mid-session flip guard, traded
   for a token saving on that one call. The trade may still be worth it, but
   it is a real cost, not a free win, and it sits directly on top of the
   prompt cache discipline this project already depends on.
2. **It is not harness-universal.** `.claude/settings.json` and its
   `PreToolUse` hooks are a Claude Code-specific mechanism. AAI runs under
   Codex and Gemini as well (`routine-emit.mjs` emits per-harness invocations
   for four named harnesses - `claude`, `codex`, `gemini`, and a `generic`
   fallback). A hook-based block would silently do nothing
   under a harness that has no equivalent surface, and this project's own
   rule forbids papering over that with a hardcoded per-harness capability
   table — the gap would need to be visible in telemetry (requested versus
   actual enforcement), not assumed away.

There is also an ordinary maintenance surface: a `jq` dependency (the shunt
hooks are `jq`-based shell scripts, not Node — AAI's own zero-dependency rule
in `docs/TECHNOLOGY.md` binds production Node code, not necessarily harness
hook scripts, but a new external binary dependency is still a new thing to
keep installed and working), a transport script equivalent to `bulk-read` /
`code-write` that AAI does not have today (Spotify's goes through the Portal
CLI; AAI has no analogous cheap-worker invocation path), and an eval suite to
keep green (`shunt` ships 51 hook-and-transport tests it maintains
specifically because a block-and-redirect that misfires breaks the calling
session, not just the delegated one).

Pre-tool block verdict: available-with-cost

### Do-not-delegate table

Population enumerated from `.aai/scripts/orchestration-dispatch.mjs`'s `TIERS`
map (10 role keys at the base commit, verified by
`/usr/bin/grep -cE "^  '[^']+': '(premium|standard|mechanical)',$" .aai/scripts/orchestration-dispatch.mjs`
returning 10). The source article names three things it refuses to delegate
on purpose (Spotify Engineering, same post): debugging, architectural
decisions, and safety-critical code ("you can't delegate reasoning... the
worker model found surface-level patterns but missed a subtle thread-safety
bug"). Each AAI role below is classified against that same fence.

| Role key (TIERS) | Classification | Argument |
|---|---|---|
| Planning | never | Its entire output is an architectural decision (scope, spec design, AC shape) - exactly the source's second excluded category. |
| Code Review | never | Issuing a spec-compliance and correctness verdict is a safety-critical judgment; a summary-based worker reproduces the source's own failure mode of finding surface patterns while missing the subtle bug. |
| Implementation | delegable | Its mechanical substeps - reading N reference files to answer a narrow question, writing new code that copies an adjacent file's shape - are exactly the bulk-reader and code-writer use cases. The wiring/correctness judgment stays on the dispatching role; only the substep is delegable. |
| TDD Implementation | delegable | Writing a new test that copies the shape of the twenty next to it is pattern-copy code generation by definition. Deciding what to assert and why a case is RED before GREEN is the judgment step that stays. |
| Remediation | never | Root-causing a review or validation finding is debugging by AAI's own definition (READ, REPRODUCE, ISOLATE, then FIX-AT-CAUSE per `aai-debug`) - the source's first excluded category by name. |
| Validation | never | Issuing a PASS/FAIL verdict is safety-critical adjudication; MODEL_ROUTING.yaml's own `validation_alternate` backstop already treats Validation's judgment as something that must not silently degrade to the implementer's own blind spots, let alone to a cheaper summary. |
| Technology extraction | delegable | Already tiered `mechanical`. Scanning a repo and extracting structured technology facts into a doc is the bulk-reader shape verbatim: read many files, emit structured bullets, no judgment call. |
| Bootstrap | delegable | Already tiered `mechanical`. Generating shortcut/template files from detected repo conventions is pattern-copy generation. |
| Implementation Preparation / Worktree decision | delegable | Already tiered `mechanical`. A worktree-or-inline decision from a small set of fixed inputs carries no safety-critical or architectural weight. |
| Metrics Flush | delegable | Already tiered `mechanical`. Pure transcription from STATE.yaml into METRICS.jsonl; the closest thing this project has to boilerplate. |

The finding this table exists to surface: `Implementation` and
`TDD Implementation` are tiered `standard` today, not `mechanical`, yet both
are classified `delegable` here on the same fence the source itself draws.
That gap - not the four roles already tiered `mechanical`, which this table
confirms are correctly placed - is the primary target of Recommendation 1
below.

### Harness-scoping hypothesis adjudication

Harness-scoping hypothesis: undecided

The claim (MODEL_ROUTING.yaml gaining `role@harness` key forms such as
`mechanical@codex: gpt-5.3-codex`, resolved alongside the existing `role@lane`
form) is not falsified by any of the three falsifiers the intake named, on
evidence read directly from `.aai/scripts/orchestration-dispatch.mjs` and
`.aai/system/MODEL_ROUTING.yaml` during this spike - not assumed from the
intake's own prose. That is weaker than "upheld," and deliberately so: of the
three falsifiers, only Falsifier 2 was actually tested against live code;
Falsifier 3 is declared untestable until the mechanism it would measure
exists; and Falsifier 1's "not triggered" rests on an absence-of-evidence
argument (no harness lacking a static cheap-tier id shows up in this
project's own data), not on a test that could have gone the other way. A
verdict of "upheld" would claim the hypothesis survived three real attempts
at falsification; only one attempt was real. `undecided` is the honest
summary of that mix, and the per-falsifier findings below are unchanged and
carry the actual evidence.

#### Falsifier 1 - a harness whose cheap tier has no static id

Not triggered. The ledger already records concrete, statically-nameable
non-Anthropic ids in production (`deepseek-v4-flash`, `gpt-5.6-sol`,
`gpt-5.5`), and `.aai/system/PRICING.yaml` prices `gemini-2.5-flash`,
`gpt-5.3-codex` and `deepseek-v4-flash` by exact id today. A harness whose
cheap tier truly cannot be named statically is not evidenced anywhere in this
project's own data.

#### Falsifier 2 - the harness genuinely unknowable at dispatch time

Not triggered, but the wiring gap it would need is real and unclosed today.
`--harness` is an established, working channel elsewhere in this project -
`node .aai/scripts/state.mjs log-tick ... --harness <harness_version>` (per
`.aai/SKILL_LOOP.prompt.md`) and `routine-emit.mjs --routine <NAME> --harness
<harness>` both take and use it. But `orchestration-dispatch.mjs` itself takes
no `--harness` flag anywhere - confirmed by reading the file: the only match
for the string `harness` in it is a comment about prompt-cache behavior, not a
parameter. That is an unwired integration gap a follow-up must close, not
evidence that the harness is unknowable; the channel exists, it simply does
not yet reach the function that would consume it.

#### Falsifier 3 - a measured fallback-fallthrough cost

Untestable with current data, and stays untestable until the mechanism exists.
No `tier@harness` key form exists in `MODEL_ROUTING.yaml` today and no
fallback marker is emitted anywhere in `orchestration-dispatch.mjs`, so there
is nothing in either ledger to measure a fallthrough rate against. This
falsifier can only be checked after a follow-up implements the mechanism with
its required fallback marker (see Recommendation 3) - it is an open
verification obligation on that follow-up, not a resolved question here.

#### Rejected alternative: a nested per-harness section

Loses on the same evidence the intake cited, re-verified here - and the
evidence is worse than "does not parse," which makes the case against
nesting stronger, not weaker. `loadModelRouting()`'s row parser is
`^ {2}([^:#]+):\s*(\S+)\s*$`. A 4-space-indented row does not reset `section`
to null (it fails the `/^\S/` check that only column-0 lines trigger), and it
*does* clean-parse as a `tiers`/`roles` row: `[^:#]+` swallows the two extra
leading spaces into the captured key, e.g. `"    mechanical: gpt-5.3-codex"`
captures key `"  mechanical"`, and `routing[section][kv[1].trim()] = kv[2]`
then `.trim()`s that key back down to the same flat string `"mechanical"`
already used by the top-level tier row. A nested per-harness block would not
fail to parse; it would parse and silently overwrite the top-level tier's
value with whatever the nested row's value is, keyed on the harness that
happens to sort last. A nested per-harness section is rejected not because it
fails to parse under the current file discipline but because it parses into a
silent same-name collision - a parser change would be required to make
nesting safe, which the flat suffix-key form does not need.

#### Rejected alternative: a capability probe

Loses on purity grounds, verified by reading `suggestModel(out, routing)`
itself: it touches neither `fs` nor a network call anywhere in its body today,
taking only `(out, routing)` and returning a string or null. A capability
probe inside that function would add a disk or network round trip to every
single dispatch and a new failure mode (a probe that hangs or errors),
destroying the property that makes `suggestModel()` trivially unit-testable
today. Capability detection belongs at the boundary where the harness is
identified (the same declared `--harness` channel Falsifier 2 names), with
requested-versus-actual recorded in telemetry - never inside the pure
resolver.

## Recommendations

Every action item here leaves as a follow-up intake, none implemented by this
spike (Spec-AC-08). No id below has been filed via
`node .aai/scripts/follow-ups.mjs add` - each is labeled `suggested:` only,
per this spike's own honesty rule (a `suggested:` id is not checked against
the registry; presenting it as `filed:` without a real CLI exit 0 would be).
Ordering key is a 1-10 priority score (expected saving weighted against
effort), rows sorted non-increasing.

| # | Type | Size | Expected saving | Effort | Ordering key | Follow-up | Recommendation |
|---|---|---|---|---|---|---|---|
| 1 | CHANGE | L | High - targets the 132-of-611-run (21%) population this spike classifies delegable-but-standard-tiered (Implementation, TDD Implementation); the largest measured gap between current tiering and this spike's own fence. | L - a bulk-read/pattern-copy delegation script plus its skill and an enforcement point, analogous in shape to `bulk-read`/`code-write`, needs building from nothing since AAI has no cheap-worker transport today. | 9 | suggested: fu-mechanical-delegation-script | Build a mechanical-tier delegation path for Implementation and TDD Implementation's bulk-reference-read and pattern-copy substeps, gated so the expensive model still owns the judgment step. |
| 2 | RFC | M | Medium - unlocks replacing the 0% to 21% proxy above with an actual measurement, and separately narrows the 227-of-611 no-marker coverage gap this spike had to work around. | M - a schema change to `state.mjs`'s `append-run` capture plus a new capture point reading whatever per-tool detail the hosting harness exposes. | 7 | suggested: fu-per-tool-usage-instrumentation | Extend the usage-capture path with a coarse tool-call histogram (bulk-read-shaped calls versus edit/write calls) per run, so the mechanical share becomes measurable rather than proxied. |
| 3 | RFC | S | Medium - unblocks a harness-universal mechanical tier without which Recommendation 1's delegation path stays Claude-Code-specific by default. | S - one function (`suggestModel()`), one new key form, no parser change (verified this spike); wiring `--harness` into `orchestration-dispatch.mjs` and adding the fallback marker Falsifier 3 requires. | 5 | suggested: fu-harness-scoped-suffix-routing | Add `role@harness` / `tier@harness` key resolution to `MODEL_ROUTING.yaml` and `suggestModel()`, wire the already-established `--harness` channel into `orchestration-dispatch.mjs`, and emit an explicit fallback marker when a `tier@harness` miss falls through to the plain tier. |
| 4 | CHANGE | S | Low - a data-hygiene fix, not a token saving; removes the need for this script's own role/model_id normalization going forward. | S - write canonical role strings and suffix-free model ids at the point `append-run` records them, instead of normalizing after the fact. | 4 | suggested: fu-normalize-ledger-role-model-at-write | Write canonical `role` and `model_id` values into `METRICS.jsonl` at append time so future grouping needs no post-hoc normalization pass. |
| 5 | RFC | M | Uncertain/conditional - only realizable under harnesses offering an equivalent hook surface (Claude Code today; not evidenced for Codex or Gemini), and it trades a real mid-session-cache cost per delegated call (Enforcement verdict above) for a token saving whose net is unmeasured for AAI's own shape. | M - a harness-conditional hook design plus the transport Recommendation 1 already needs, evaluated against the no-mid-session-flip cost before any decision to build. | 3 | suggested: fu-pretool-block-harness-conditional | Design (not implement) a harness-conditional enforcement layer: a `PreToolUse`-equivalent block where the harness supports one, an explicit degrade-and-report (Article 4) where it does not, with requested-versus-actual enforcement recorded in telemetry rather than assumed. |

Directional caveat: every figure above comes from 132 to 135 work-item records
on one self-hosting repository, not a sample from which a general rule
follows for other projects. The ordering key is this spike's own estimate; a
reviewer who disagrees with the arithmetic can say so against the printed
number rather than against a feeling.

## Open Questions

- Can a pre-tool block be expressed at all in this project's harness
  configuration, given that no `.claude/settings.json` exists today, and is
  adding one a surface the owner wants to carry and maintain?
- Does the latency floor sink this for AAI? Adding 10 to 30 seconds per
  delegation is cheap against a multi-hour autonomous run but expensive against
  a short interactive one. Which AAI lanes can absorb it?
- What is the right *shape* for harness-universal routing — a per-harness
  section in MODEL_ROUTING, a capability probe at dispatch time, or a tier that
  resolves late in the harness adapter? The owner's requirement is that routing
  follow the agent the run is on; the mechanism is open. (The cross-vendor
  pricing question is already settled: PRICING.yaml prices the non-Anthropic
  ids, so cost attribution is not the blocker.)
- What happens when the host harness exposes no cheap tier, or no subagent
  spawn at all? Degrade to the expensive model and report, or refuse the
  delegation? Article 4 says degrade and report, but it must be measured, not
  silent.
- If token attribution requires new instrumentation, is that instrumentation
  worth its cost at this project's run volume, or does the modest ledger size
  argue for accepting directional estimates?
- Does a cheap summarizer actually save money in AAI's shape, where the
  expensive model frequently needs the *exact* file to make an edit? The author
  concedes this residual cost and keeps targeted reads unblocked because of it.
- Where is the safety floor? Which AAI roles must never be downgraded regardless
  of measured saving, and is that list already implied by the `effort_roles` and
  `validation_alternate` rows in MODEL_ROUTING?
- Does a hard block conflict with the existing prompt-cache discipline, since a
  refused-and-rerouted call changes what enters the stable prefix?
