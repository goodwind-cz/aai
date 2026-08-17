# Code Review — docs-model-nul-escape (CHANGE-0147) — PR #262

**Internal review substituted for an absent external bot layer.** Copilot's
workflow errored and posted only "Copilot encountered an error and was unable to
review this pull request"; Codex never posted. GitHub's API is degraded ("No
server is currently available to service your request"), so review could not be
re-requested. Under `.aai/SKILL_PR.prompt.md` step 5d's reviewer-fallback
contract this internal pass on the final diff IS the gate, not a second opinion.

```yaml
review:
  scope: origin/main...HEAD on fix/docs-model-nul-escape (PR #262, head 5049a65)
  spec: none (ceremony_level 1, direct strategy) — reviewed against the
        CHANGE-0147 intake's AC-001..AC-004
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: AC-001, call: compliant,
          citation: "tr -dc '\\000' < .aai/scripts/lib/docs-model.mjs | wc -c = 0; repo-wide tracked-file sweep finds no NUL in any tracked file" }
      - { ac: AC-002, call: compliant,
          citation: "probe.mjs extracted the `const key = ...` template verbatim from BOTH blobs and evaluated each: codes 65,85,84,72,0,120 on both; values identical; separator is one char, code 0" }
      - { ac: AC-003, call: compliant,
          citation: "perl -pe 's/\\x00/\\\\u0000/g' on origin/main's blob is byte-identical (cmp) to HEAD's blob — no edit smuggled anywhere in the file" }
      - { ac: AC-004, call: compliant,
          citation: "spec-lint, docs-audit, delta-stage1, delta-stage2, doc-numbering suites green; docs-audit --check --strict --no-event CLEAN; spec-lint.mjs 133 specs / 0 findings; select-suites.mjs returns FULL_RUN reason=shared-lib so CI runs the whole framework" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-spec-lint.sh, line: 1690,
          issue: "TEST-011's log_pass still claims 'now 14 paths across 4 scopes'; the allowlist this diff edits is now 15 paths across 5 scopes",
          failure_scenario: "The suite prints a PASS line asserting a false count. An agent or operator auditing allowlist growth from suite output — exactly what this self-documenting counter is for, and exactly how the previous scope's reviewer used it — reads 14/4 and concludes docs-model.mjs is not listed." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 195,
          issue: "the durable prevention (a repo-wide no-NUL-in-tracked-text check) exists only as prose inside the `decision` field of fu-escape-literals-self-inflict, a P3 whose finding line is about a writing habit",
          failure_scenario: "Triage reads finding lines and severities. A P3 titled 'writing about a control-character escape reliably inserts the control character itself' will never be picked up as 'add a CI guard' — yet that guard is what would have caught the original defect and all three re-inflictions. The prevention is filed where it cannot be found." }
      - { rank: NON-BLOCKING, file: docs/issues/CHANGE-0147-docs-model-nul-escape.md, line: 26,
          issue: "the blast-radius claim is wrong in both directions: overstated for tooling, understated for tests",
          failure_scenario: "'Every agent sweep over .aai/scripts/ has been silently missing this file' is false for git grep and ripgrep (both find the symbol in the old blob, verified). Meanwhile the writeup never mentions the one thing that WAS provably broken: tests/skills/test-aai-delta-stage2.sh:210's negative taxonomy guard was silently inert on the old bytes. Future readers inherit a mis-scoped severity model for this defect class." }
  cannot_verify:
    - { claim: "runtime equivalence of all 40 exports, not just parseDeltasSection's key path",
        closes_with: "not needed — byte identity after the mechanical substitution (AC-003) implies runtime identity for the whole module; recorded for completeness, not as open risk" }
    - { claim: "green on Linux for the full framework this change triggers in CI",
        closes_with: "the PR's own CI run; all local runs were macOS/BSD" }
    - { claim: "that specific past agent sweeps actually missed this file",
        closes_with: "unfalsifiable historically; the MECHANISM is proven (see NB-3), the history is not" }
  overall: pass
```

## Scope and method

Branch diff `origin/main...HEAD`, working tree clean, head `5049a65`. Eight
files: the two code/test files under review plus the intake, CHANGELOG,
decisions.jsonl and three regenerated artifacts (INDEX, overview\*).

I did not accept the author's evidence. Every claim below was re-derived from
`git show origin/main:<path>` and `git show HEAD:<path>` in a scratchpad copy.
No probe or mutation touched this repository.

## The substitution is exactly what it claims to be

The strongest available proof, and stronger than the author's: apply the
mechanical substitution to the *old* blob and compare bytes.

```
perl -pe 's/\x00/\\u0000/g' old.mjs  ==  new.mjs      → IDENTICAL (cmp)
```

That single result subsumes AC-003 and rules out any unrelated edit hidden in a
1000-line file. Old NULs 2, new NULs 0.

On the doubled-backslash trap the author hit: I re-tested it the way that
catches it, pulling the `const key = ...` template literal verbatim out of each
source file and evaluating it rather than retyping it.

```
old key codes: 65,85,84,72,0,120   (A U T H NUL x)
new key codes: 65,85,84,72,0,120
key values identical: true   separator: one char, code 0
```

A doubled backslash would read `92,117,48,48,48,48`. It does not. Six
`parseDeltasSection` fixtures — duplicate, case-folded duplicate, cross-domain,
an `AUTHX`+`Y` vs `AUTH`+`XY` boundary case a weak separator would false-collide,
a mixed op block and an empty-title pair — return identical violation sets from
both modules. Export surface identical (40 exports).

Worth noting for the record: while writing the probe I very nearly reproduced
the same self-inflicted NUL in my own heredoc, which the tool layer rejected.
`fu-escape-literals-self-inflict` is not an author-specific failure — it is a
property of the task, and it is the reason NB-2 matters.

## The defect was worse than the writeup says, in a way the writeup missed

The intake attributes the harm to agent greps. The verifiable harm is to this
repo's own test suites, which use plain `grep`/`grep -qF` throughout.

```
grep -c "parseDeltasSection" old.mjs   → (no output) rc=1
grep -c "parseDeltasSection" new.mjs   → 2           rc=0
git grep / ripgrep on the old blob     → both find it
```

BSD/POSIX grep silently reports *no match* for a symbol occurring twice. `git
grep` and `ripgrep` are unaffected — so the intake's "every agent sweep" is too
broad, while the real exposure went unnamed. I planted a `stage-1` canary in
each blob and ran `tests/skills/test-aai-delta-stage2.sh:210`'s negative
taxonomy guard against both:

```
grep -rnE 'stage[ -][123]' probe-old.mjs → (nothing) rc=1   ← guard INERT
grep -rnE 'stage[ -][123]' probe-new.mjs → line 924  rc=0   ← guard ARMED
```

TEST-005's taxonomy guard has been asserting nothing about `docs-model.mjs` for
as long as the NUL bytes existed, and logging PASS. **This PR re-arms it**, and
the suite is green with it armed — so nothing latent is uncovered. That is a
genuine correctness win this change should be credited with, not the cosmetic
spelling fix it is currently described as.

## Risk I went looking for and did not find

- **Content-hash pins.** `tests/skills/lib/close-work-item-pin.sh` freezes
  `close-work-item.mjs` by sha256; a comparable pin on `docs-model.mjs` would
  have been broken by any byte change. There is none.
- **Duplicate/vendored copies.** One tracked copy only.
- **Byte-budget gates.** `prompt-diet-ledger.sh` scores `.aai/*.prompt.md` prose
  and explicitly records that `.aai/scripts/` engines "carry NO ledger cost".
  The +10 bytes are unbudgeted by design.
- **Thin CI selection.** `suite-map.yaml` maps `docs-model.mjs` to exactly one
  suite (`aai-product-docs`), which would be alarming — except
  `full_run_triggers.shared_lib_globs` catches `.aai/scripts/lib/**` first.
  Verified live: `select-suites.mjs --base-ref origin/main` →
  `FULL_RUN reason=shared-lib`. CI runs the complete framework on this PR.
- **Other NUL-carrying tracked files.** Swept every tracked file; this was the
  only one. The repo is now NUL-clean.

## Findings and dispositions

Reviewer is read-only; the orchestrator records these.

- **NB-1 — stale allowlist count, `tests/skills/test-aai-spec-lint.sh:1690`.**
  Counted mechanically: 3 + 2 + 4 + 5 + 1 = 15 paths across 5 scopes; the
  message says 14 across 4. Precedent matters here: the deslop review
  (`review-20260815T114500Z...md:216`) audited this exact claim and rated it
  INFO *because it was then arithmetically true*. This diff makes it false.
  **Smallest fix:** `14 paths across 4 scopes` → `15 paths across 5 scopes`.
  **Disposition: remediate-in-tree** — one token, in the same scope that
  invalidated it.

- **NB-2 — the prevention is filed where triage will not find it.**
  Confirmed no test or CI job asserts tracked text files are NUL-free.
  **Smallest fix:** a separate follow-up whose *finding line* is the missing
  guard — `node .aai/scripts/follow-ups.mjs add --id fu-no-nul-guard --ref
  docs-model-nul-escape --severity P2 ...`. A three-line repo sweep
  (`git ls-files -z | xargs -0 grep -lIP '\x00'`) would have caught the original
  defect and all three re-inflictions. **Disposition:
  promote-to-follow-up-ref.**

- **NB-3 — mis-scoped blast radius, `CHANGE-0147...md:26` and the matching
  CHANGELOG bullet.** **Smallest fix:** replace "every agent sweep" with "plain
  `grep` (git grep and ripgrep are unaffected)" and add one sentence crediting
  the re-armed `test-aai-delta-stage2.sh` TEST-005 guard.
  **Disposition: remediate-in-tree** — the CHANGELOG is the durable record.

- **INFO** — the intake's Constraints section says the byte was reintroduced
  once; CHANGELOG and decisions.jsonl say three times. The latter are correct.
- **INFO** — the comment above the allowlist ("the two scripts plus ONE
  prompt") is four scopes out of date. Pre-existing, untouched here, belongs to
  `fu-test011-branch-diff-allowlist-tax`.

## Verdict

**PASS — both verdicts.** No BLOCKING finding. The claim under review holds
under independent re-derivation: byte-identical modulo the substitution,
runtime-identical key, file is text again. The change is also worth slightly
more than it claims, having re-armed a test guard that had been silently inert.

Per the H6 warnings policy this PASS is conditional: NB-1 and NB-3 are one-line
in-tree edits and NB-2 is a follow-up filing. None gates merge, but each must
carry a named artifact in `code_review.notes` before closeout. Merge-readiness
otherwise rests on the PR's CI run, which will execute the full framework.
