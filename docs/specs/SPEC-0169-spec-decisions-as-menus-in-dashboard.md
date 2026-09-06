---
id: spec-decisions-as-menus-in-dashboard
type: spec
number: 169
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0175-decisions-as-menus-in-dashboard.md
  rfc: null
  pr:
    - 346
  commits:
    - b9c70aca
---

# Spec — a pending decision is answerable from the dashboard, through the channel that already exists

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/CHANGE-0175-decisions-as-menus-in-dashboard.md`
- Roadmap: wave 1 pair 2, capability half; paired maintenance `canon-one-line-report-and-downstream-rules`
- Extends: `.aai/scripts/aai-live-serve.mjs` (CHANGE-0173 / SPEC-0167, #344)
- Reuses unchanged: `.aai/SKILL_HITL.prompt.md` STEP 0/3/4, `.aai/scripts/hitl-channel.mjs` `poll` (`{status:'reply', token, ref, body, …}`) and `resolve`, its `sanitizeBody`
- Not touched: `docs/ai/STATE.yaml` (protected L3) — clearing `human_input` stays SKILL_HITL's job
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero deps, bash 3.2 suites)

Registry items closed by this scope: none. `follow-ups.mjs list --status open` names `fu-dispatch-gate-spawn-seam-untested` and 123 others; none names the dashboard, the HITL channel or the answer path.

## Design decisions
- **D1 — a second transport, not a second resolution path.** The dashboard writes an answer; `poll` surfaces it in the shape STEP 0 already consumes. No new prompt wiring, no change to STEP 3/4, no new consumer.
- **D2 — the sidecar is append-only JSONL, gitignored.** `docs/ai/hitl-answers.jsonl`, one record per answer `{v,ts,token,ref,answer,source:'local-dashboard'}`. Same class as `docs/ai/hitl-channel.json` (runtime sidecar, never STATE).
- **D3 — earliest qualifying answer wins, and the source is named.** When both a GitHub reply and a local answer exist for one token, `poll` compares timestamps and returns the earlier with `source: 'github' | 'local'`. Naming the source is what lets an operator tell where a decision came from.
- **D4 — the write surface refuses more than it accepts.** `POST /answer` is loopback-only (the server binds nowhere else), rejects a body over 4 KB, an empty answer, a malformed JSON body, a token/ref that does not match the live `human_input`, and any request when nothing is pending (409). It writes exactly one gitignored file and nothing else.
- **D5 — options are parsed, never invented.** Buttons come from lines in the question text shaped `- x`, `1) x` or `1. x`; `(recommended)` at the end marks one. No options parsed means the free-text box alone — never an empty menu, never a fabricated default.
- **D6 — the answer is data.** It goes through the same `sanitizeBody` the GitHub path uses before it is stored and again before it is surfaced; it is never interpolated into a shell command, and the page renders it escaped.

## Implementation strategy
- Strategy: tdd
- Rationale: the value is in the refusals (D4) and in not disturbing the 19-case gate (`hitl-channel.mjs` TEST-001..019); a suite that only proves the happy click would pass while any refusal or the GitHub path was broken.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | With a pending `human_input` the page always offers a free-text field and, in THIS scope, no parsed options at all (`waiting.options` is empty and the rendered block carries no button) — D5's documented no-options fallback; the parser ships as its own ride | done | TEST-008, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/decisions-as-menus-in-dashboard-green.log; the rendered block asserted under a stub DOM, not grepped from the template | tdd:2026-09-06 | narrowed by Amendment 1: the parser is its own ride; this is D5's free-text fallback |
| Spec-AC-02 | `POST /answer {token,ref,answer}` appends exactly ONE record to the sidecar and returns 200 echoing it; a malformed body, an empty answer and a 5 KB answer each return 400 and append NOTHING | done | TEST-009, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/decisions-as-menus-in-dashboard-green.log; the 200 echo pinned after a mutation emptied it; refusals cksum-checked | tdd:2026-09-06 | AC-002; every refusal proven to append nothing |
| Spec-AC-03 | `hitl-channel.mjs poll --json` with only a local answer returns `status:'reply'`, `source:'local'`, the token, the ref and the sanitized body; with a GitHub reply AND a local answer the EARLIER timestamp wins and `source` names it | done | TEST-020/021, tests/skills/test-aai-hitl-channel.sh; docs/ai/tdd/decisions-as-menus-in-dashboard-green.log; RED in docs/ai/tdd/decisions-as-menus-in-dashboard-red.log; both orders, and gh-unreachable re-probed in docs/ai/validation/decisions-as-menus-in-dashboard-round2.md | tdd:2026-09-06 | D3; source named on every reply |
| Spec-AC-04 | An answer carrying control and bidi characters is stored and surfaced sanitized by the SAME `sanitizeBody` the GitHub path uses; the stored record contains no raw control byte | done | TEST-009 and TEST-021, tests/skills/test-aai-hitl-channel.sh; docs/ai/tdd/decisions-as-menus-in-dashboard-green.log; sanitizeAnswer is the channel's exported sanitizeBody, imported not copied | tdd:2026-09-06 | D6; the copy was round 2's non-blocking, fixed so the AC is literally true |
| Spec-AC-05 | After `resolve --token <t>`, a second `poll` does not re-surface the local answer; `resolve` stays idempotent and exits 0 | done | TEST-022/023, tests/skills/test-aai-hitl-channel.sh; docs/ai/tdd/decisions-as-menus-in-dashboard-green.log; RED in docs/ai/tdd/decisions-as-menus-in-dashboard-red.log; resolve appends a marker, never rewrites | tdd:2026-09-06 | AC-005; the rewrite lost a concurrent answer (code review B2) |
| Spec-AC-06 | With `human_input.required: false`, `POST /answer` returns 409 and appends nothing; with a token or ref that does not match the live block it returns 400 and appends nothing | done | TEST-009 and TEST-011, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/decisions-as-menus-in-dashboard-green.log; 28 cross-origin header combinations re-probed in docs/ai/validation/decisions-as-menus-in-dashboard-round2.md | tdd:2026-09-06 | AC-006 plus the CSRF guards loopback alone did not provide ({V1} B1) |
| Spec-AC-07 | A full answer cycle leaves `git status --porcelain` unchanged; the only file created is the gitignored sidecar; the existing `hitl-channel` suite stays green (its 19 pre-change cases, TEST-001..019) and the existing live-serve suite stays green | done | TEST-010, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/decisions-as-menus-in-dashboard-green.log; full sweep 88/88; the real ledger cksum-checked across a suite run in docs/ai/validation/decisions-as-menus-in-dashboard-round2.md | tdd:2026-09-06 | AC-007; STATE byte-identical across a full answer cycle |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                        | Description | Status |
|----------|------------|------|---------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-live-serve.sh | the rendered waiting block carries the free-text box and NO option button; `waiting.options` is empty | pending |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-live-serve.sh | one record appended and echoed; malformed, empty and oversized bodies each 400 with an unchanged sidecar | pending |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-hitl-channel.sh | local-only answer surfaces as reply with source local; github+local, both orders, earlier wins and source is named | pending |
| TEST-004 | Spec-AC-04 | unit | tests/skills/test-aai-hitl-channel.sh | control and bidi characters stripped on store and on surface; stored line has no raw control byte | pending |
| TEST-005 | Spec-AC-05 | int  | tests/skills/test-aai-hitl-channel.sh | resolve consumes the local answer; second poll returns none; resolve twice exits 0 | pending |
| TEST-006 | Spec-AC-06 | int  | tests/skills/test-aai-live-serve.sh | nothing pending returns 409; mismatched token and mismatched ref each 400; sidecar untouched in all three | pending |
| TEST-007 | Spec-AC-07 | int  | tests/skills/test-aai-live-serve.sh | full cycle leaves the repo unchanged (marker + find); hitl-channel and live-serve suites green | pending |

## Implementation plan
- **EDIT** `.aai/scripts/aai-live-serve.mjs` — `POST /answer` (body cap, JSON parse, live-block match, 409/400 refusals), sidecar append, option parsing into `/data.json.waiting.options`, page buttons + free-text + POST.
- **EDIT** `.aai/scripts/hitl-channel.mjs` — a LOCAL source in `poll` (read the answers sidecar, unresolved entries only), `source` on the reply shape, `resolve` marks local answers consumed. The GitHub path is not restructured.
- **EDIT** `.gitignore` — `docs/ai/hitl-answers.jsonl`.
- **EDIT** suites above; prompt-diet only if `.aai/SKILL_LIVE.prompt.md` grows.

## Constraints / Risks
- First write surface on the dashboard: loopback only, one gitignored file, refuses when nothing is pending.
- `hitl-channel.mjs`'s 19 pre-change cases (TEST-001..019) must stay green; the
  local source is additive.
- An operator answering from two places at once is resolved by D3 (earlier wins), not by silently preferring one.

## Amendment 1 (unsigned, 2026-09-06) — the menu is split off

Validation round 2 returned FAIL with two blocking findings, and under the
owner's two-round cap (`hitl_decision` `review-round-cap`) a third
finding-bearing round means the ride is SPLIT, not verified again.

**What leaves this scope.** `parseOptions`, the page's button block, D5, the
`(recommended)` marker, and Spec-AC-01's menu half. The history is why: round 1
caught the parser fabricating buttons out of prose ("…the reaper flake - a
CI-load artefact, not a bug - should we…" became two options); the round-1
anchor fix stopped that and then silently DROPPED real options phrased as
questions ("Choose: - is it a? - b - c" lost the first). Both failures are in
the same heuristic, and the operator contract's own shape — "a question is a
menu" — is exactly the case it gets wrong. It needs its own ride, not a third
patch.

**What ships.** Everything the two rounds proved: the write surface with its
CSRF, size, type, token, ref and nothing-pending refusals; the local transport
in `hitl-channel.mjs` with the earlier-answer rule, the append-only resolve and
the `--ref` trust guard; and the free-text box, which is D5's own documented
behaviour when no options are parsed — no new code, no unproven surface.

**Also fixed from round 2.** A tokenless block now returns 409 instead of
recording an answer that `poll` could never return (a success message over a
silent loss), and `sanitizeAnswer` is now the channel's exported `sanitizeBody`
rather than a re-typed copy, which is what Spec-AC-04 said all along.

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.
