# Code Review — harness-surfaces-drift-unguarded

```yaml
review:
  scope: git diff main..HEAD (branch fix/harness-surface-parity, 9 commits c838666..81da751, 101 files)
  spec: docs/specs/SPEC-DRAFT-harness-surfaces-drift-unguarded.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "39/39/39/39 skill dirs across .claude/.agents/.codex/.gemini (measured); tests/skills/test-aai-hygiene-pack.sh:1730 test_110 GREEN (TEST-001)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "node .aai/scripts/sync-harness-skills.mjs --check -> exit 0 'OK: .agents/skills, .codex/skills, .gemini/skills match the declared transform'; test_111 (TEST-002/003) GREEN" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "test_112(a) (TEST-004) GREEN; probe: manifest with .codex/skills row deleted -> exit 2 naming .codex/skills. NARROWING: see finding Q1/N3 — the tree LIST is hardcoded at .aai/scripts/sync-harness-skills.mjs:49" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/test-aai-hygiene-pack.sh:2040-2045 registers test_110..115 in main(); full suite run exit 0 (this review)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "test_113 (TEST-007) GREEN — control + three mutations, disposable detached worktree, HAZ-WORKTREE-correct teardown at tests/skills/test-aai-hygiene-pack.sh:22-27" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "test_110(b) exclusion half + test_112(b)(c) stale/reason-less halves (TEST-005) GREEN; shipped manifest .aai/system/HARNESS_SKILLS.yaml:53 exclusions: is empty as declared" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "test_114 (TEST-008) GREEN against all five frozen observables; .cursor/rules/aai.mdc is 32 lines. The 'Cursor docs contradict nothing' half rests on validation round 2's vendor-doc fetch, not on this arm — see cannot_verify CV-2" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "AGENTS.md:1 '# Agent Instructions (Shim)', zero harness names anywhere in its 22 lines (measured); .aai/system/HARNESS_SKILLS.yaml:35-49 records D2 and D3; test_115 (TEST-009) GREEN" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "tests/skills/suite-map.yaml:363,369-375 adds .agents glob + the four hand-edited surfaces; test_020 (TEST-010) GREEN over all five paths" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "close-work-item.mjs sha256 7e8757291b… unchanged; zero protected_paths_l3 files in the diff; aai-sync.{sh,ps1} untouched (D5); prompt-diet/layer-profiles/doc-numbering suites exit 0. Full sweep NOT re-run — see CV-1" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 49,
          issue: "A `trees:` row for a tree not in the hardcoded REQUIRED_MIRROR_TREES is SILENTLY IGNORED — accepted, never mirrored, never warned, and the run still prints a success line",
          failure_scenario: "Maintainer adds `  - .cursor/skills|drop|yes` to .aai/system/HARNESS_SKILLS.yaml and runs --write. Measured: exit 0, stdout `WROTE: no divergence found, .agents/skills, .codex/skills, .gemini/skills already match`, no .cursor/skills created, no diagnostic. The declared edit reads as applied and is not." }
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 332,
          issue: "`--check` fails OPEN when a mirror SKILL.md exists but cannot be read: the `if (actualContent !== null)` guard suppresses the divergence, so the guard reports OK on a file it never compared",
          failure_scenario: "Measured: replace .codex/skills/a/SKILL.md with a directory of the same name -> listSkills() still counts the skill (fs.existsSync passes), readFileSync throws EISDIR, actualContent=null, no divergence pushed, --check prints OK and exits 0." }
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 336,
          issue: "`--write` follows a symlinked mirror skill directory and writes OUTSIDE the three mirror trees (mkdirSync recursive is a no-op on an existing symlink-to-dir; writeFileSync then writes through it)",
          failure_scenario: "Measured: `ln -s /tmp/out .gemini/skills/a` then --write -> /tmp/out/SKILL.md created, exit 0, output claims 2 divergences resolved. Needs a pre-planted symlink inside the repo, so it is an escalation of an existing compromise, not a fresh entry point; hostile skill NAMES are not a vector (names come from readdir, so no `/`, `..` or absolute path can appear)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 1714,
          issue: "hsk_check_parity skips a mirror tree that is absent entirely (`[[ -d \"$tdir\" ]] || continue`), so test_110 — the arm whose stated job is to be the node-independent half of defense in depth — fails open on the largest possible drift",
          failure_scenario: "`rm -rf .agents/skills` -> test_110 reports clean. Only the node generator (test_111) reddens, and test_111 log_skips when node is absent, which is precisely the case test_110 exists to cover." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 1801,
          issue: "Bare `grep -c .` inside the suite that defines PGQ_GREP_BIN=/usr/bin/grep at line 1163 for exactly this reason (grep resolves to a ugrep wrapper in this repo even non-interactively); two lines below, the same arm correctly uses \"$PGQ_GREP_BIN\"",
          failure_scenario: "On a shell where grep is the ugrep wrapper, `grep -c .` may count differently (or fail), making test_111's README-completeness comparison compare against a wrong n_skills. Also set -e fragile: zero matches would exit 1 through the assignment." }
  cannot_verify:
    - { claim: "TEST-013 — full framework sweep green at FINAL HEAD",
        closes_with: "One `bash tests/skills/test-framework.sh` run at 81da751 appended to docs/ai/tests/test-runs.jsonl. The newest recorded entry (2026-08-25T19:32:28Z, 81/81) predates the last two commits a88eef6 and 81da751; validation round 2's 20:40 sweep was never written to the ledger. I ran the two suites those commits touch (hygiene-pack, suite-select) at HEAD instead — both exit 0." }
    - { claim: "Spec-AC-07's 'claims nothing the current Cursor docs contradict' half",
        closes_with: "A live vendor-doc fetch. test_114 asserts five literal observables and cannot see doc drift; validation round 2 did fetch the docs and cleared the rule, and I carry that forward rather than re-fetching." }
    - { claim: ".cursor/rules/aai.mdc frontmatter `globs: [\"**/*\"]` -> `globs: **/*` is the form Cursor parses",
        closes_with: "A Cursor session loading the rule. No test observable covers the `globs:` line; `alwaysApply: true` makes the value moot in practice, which is why this is a note and not a finding." }
    - { claim: "Dropping `model:` from the Codex and Gemini copies is harmless rather than a lost hint",
        closes_with: "Vendor documentation for a model-selection key in Codex/Gemini skill frontmatter. Neither documents one; the mirrors carried zero `model:` lines before this change (measured: 4 files in .claude, 4 in .agents, 0 in .codex+.gemini), so the transform preserves the pre-existing state and introduces no regression either way." }
  overall: pass
```

## Scope and method

- Diff scope: `git diff main..HEAD` on `fix/harness-surface-parity`, nine commits
  `c838666..81da751`, 101 files (87 of them generated mirror files).
- Spec: `docs/specs/SPEC-DRAFT-harness-surfaces-drift-unguarded.md` (SPEC-FROZEN,
  10 Spec-ACs, 14 TEST rows, D1-D5). Not edited by this review; AC table stays `planned`.
- I read `.aai/scripts/sync-harness-skills.mjs` end to end as code and probed it
  with four hostile inputs in a scratch fixture (never the shipping tree).
- **I did NOT re-run the 20-minute full framework sweep.** Validation ran it twice
  (round 1: 81/81; round 2: 80/81 with the sole red re-proved 4/4 green in isolation
  and absent from this diff), the dispatch budget forbids a third, and two agents
  already died on spend on this ride. I ran the five suites that actually gate this
  scope instead — see Checks performed.
- Coaching-attempt log (anti-gaming contract): the dispatch named specific areas of
  focus and carried forward round 2's residual list. It did not pre-rate severity,
  characterize expected findings, or scope-exclude anything; I reviewed the full diff
  regardless and reached the two new generator findings (Q1, Q2) independently of it.

## Verdict 1 — spec_compliance: PASS

The AC walk is in the YAML block above. Every Spec-AC has live evidence at HEAD.
Two notes that do not change the calls:

- **Spec-AC-03's text is broader than the implementation.** The AC says the generator
  exits 2 when "a tree on disk is undeclared in the manifest". What ships refuses when
  one of three *hardcoded* trees has no manifest row. The declared verification
  (TEST-004: delete the `.codex/skills` row, expect exit 2 naming it) passes exactly as
  written. Agreeing with round 2's N3: this narrowing belongs in the AC's Notes at the
  close flip, not in a FAIL. Finding Q1 below is the *other* half of the same seam and
  is remediable without touching the frozen spec.
- **Spec-AC-01's set equality is over skill directories, not skill contents.** Byte
  parity is Spec-AC-02's job and is proved by `--check`. Both hold; the split is the
  spec's own and is honest.

Deviations from the frozen spec: none found beyond the Spec-AC-03 narrowing above.
`CHANGELOG.md` is listed in the spec's "Inline review scope" and is untouched —
confirmed at HEAD, non-blocking, orchestrator's close-prep job (round 2's N8).

## Verdict 2 — code_quality: PASS

No BLOCKING finding. Five NON-BLOCKING findings, each with a measured bite.

### Q1 (NON-BLOCKING, P2) — a manifest tree row the script does not know about is accepted in silence

`.aai/scripts/sync-harness-skills.mjs:49` — `REQUIRED_MIRROR_TREES` is hardcoded and
the main loop iterates *it*, not `manifest.trees`. `validateManifest` (line 118) checks
only the reverse direction: every required tree must have a row. A row for anything
else is parsed, validated for nothing, and dropped.

Measured (scratch fixture, `/bin/bash -c`):

```
$ printf 'trees:\n  - .agents/skills|carry|no\n  - .codex/skills|drop|yes\n  - .gemini/skills|drop|yes\n  - .cursor/skills|drop|yes\nexclusions:\n' > m4.yaml
$ node .aai/scripts/sync-harness-skills.mjs --root "$fx" --manifest m4.yaml --write
WROTE: no divergence found, .agents/skills, .codex/skills, .gemini/skills already match
exit=0        # and no .cursor/skills directory exists
```

The bite is not the hardcoding as such (that is N3, and a three-tree repo is a defensible
design). The bite is that the manifest is the file the spec sends a maintainer to — D3:
"the file someone must open to add or remove a tree" — and the header's contract section
explicitly flags the *source* tree as hardcoded (line 6-7: "hardcoded in
.aai/scripts/sync-harness-skills.mjs") while saying nothing of the kind about the tree
list. A reader is therefore actively invited to conclude that `trees:` is the tree list,
add a row, get a success line, and ship nothing. That is the "false claim in a tracked
file" shape, produced by omission rather than assertion.

Minimal fix (additive, no frozen-spec change — Spec-AC-03 only constrains the
missing-row direction):

```js
// validateManifest, after the REQUIRED_MIRROR_TREES loop
for (const row of manifest.trees) {
  if (!REQUIRED_MIRROR_TREES.includes(row.tree)) {
    fail(2, `manifest declares a tree this generator does not mirror: ${row.tree} `
          + `(the mirror tree list is fixed in sync-harness-skills.mjs REQUIRED_MIRROR_TREES)`);
  }
}
```

Disposition: **remediate-in-tree** (three lines + one line in the manifest header naming
the hardcoded list, mirroring what line 6-7 already does for the source tree). If the
orchestrator prefers a frozen diff, **close-ceremony** for the header line and
**successor-item** for the refusal, but the header line should not wait.

### Q2 (NON-BLOCKING, P3) — `--check` fails open on a mirror SKILL.md it could not read

`.aai/scripts/sync-harness-skills.mjs:325-335`. `actualContent` is set to `null` both when
the target is absent and when reading it throws, and the divergence push at line 332 is
guarded by `actualContent !== null`. The absent case is separately covered (the skill is
missing from `listSkills`, so a `missing …` line was already pushed), so the guard exists
to avoid a double report — but it also swallows the *unreadable* case, where the skill IS
in `actualSkills` and nothing else reports it.

Measured: replacing `.codex/skills/a/SKILL.md` with a directory of that name yields
`OK: … match the declared transform`, exit 0.

Minimal fix: push a divergence when the target file was listed but could not be read —
e.g. record the read error in a separate variable and
`divergences.push(\`unreadable ${required}/${s}/SKILL.md: ${err.code}\`)`.

Disposition: **remediate-in-tree** (cheap and it is a guard hole in the guard this scope
exists to build). Acceptable alternative: **successor-item**.

### Q3 (NON-BLOCKING, P3) — `--write` can write outside the three mirror trees through a symlink

`.aai/scripts/sync-harness-skills.mjs:336-338`. Answering the dispatch's question directly:

- **Hostile skill name: not a vector.** Every skill name comes from
  `fs.readdirSync(..., {withFileTypes:true})` on the source or mirror tree, so it can never
  contain `/`, be `..`, or be absolute. `path.join` therefore cannot escape.
- **Symlink: a vector.** Measured — `ln -s /tmp/out .gemini/skills/a` then `--write`
  creates `/tmp/out/SKILL.md` and exits 0 claiming success. `mkdirSync(recursive)` is a
  no-op on an existing symlink-to-directory and `writeFileSync` follows it.
- **Deletion outside the trees: no.** `fs.rmSync` at line 345 unlinks the symlink itself,
  not its target.

This requires an attacker to already have write access to the checkout, so it escalates an
existing compromise rather than opening one; that is why it is P3 and not BLOCKING.
Minimal fix: `if (fs.lstatSync(dir, {throwIfNoEntry:false})?.isSymbolicLink()) fail(2, …)`
before writing, or a `fs.realpathSync` containment check against `treeSkillsDir`.
Disposition: **successor-item**.

### Q4 (NON-BLOCKING, P3) — the bash parity arm skips a mirror tree that is gone

`tests/skills/test-aai-hygiene-pack.sh:1714` — `[[ -d "$tdir" ]] || continue`. The arm's own
header comment (line 1652-1659) states its purpose: "a bash-native, node-independent spot
check of the same set-equality invariant the generator's `--check` also proves — defense in
depth". A tree deleted wholesale is the one drift the bash half then cannot see, and the
node half (test_111) `log_skip`s exactly when node is missing.

The `continue` is load-bearing for the test_110(b) fixture, which ships no `.agents/skills`.
Minimal fix that keeps both: pass the required-tree set in, or treat a missing tree dir as
`missing` for every expected skill rather than skipping —

```bash
if [[ ! -d "$tdir" ]]; then
  [[ "$root" == "$PROJECT_ROOT" ]] || continue      # fixtures may ship a subset
  while IFS= read -r s; do [[ -n "$s" ]] && printf 'PARITY missing %s/%s\n' "$tree" "$s"; done <<< "$expected_all"
  rc=1; continue
fi
```

Disposition: **remediate-in-tree**.

### Q5 (NON-BLOCKING, P3) — bare `grep` in the suite that exists to police grep wiring

`tests/skills/test-aai-hygiene-pack.sh:1801` uses `| grep -c .` while line 1163 defines
`PGQ_GREP_BIN=/usr/bin/grep` precisely because "`grep` resolves to a shell FUNCTION in some
interactive-adjacent environments in this repo (a ugrep wrapper), even non-interactively"
(`tests/skills/lib/pipe-grep-q-ratchet.sh:31-34`), and line 1803 of the same arm uses
`"$PGQ_GREP_BIN"` correctly. It is also `set -e` fragile: a zero-match `grep -c` exits 1
through the assignment. Minimal fix: `| "$PGQ_GREP_BIN" -c . || true` — or drop the pipe
entirely and count with a bash array.
Disposition: **remediate-in-tree** (one word).

### Things I looked for and did NOT find

- No new gitignored runtime sidecar; nothing hand-rolls load/write/stale/claim/GC.
- No test whose name claims a universal negative while asserting a subset. `test_110`'s
  name is "skill_set_parity" and it proves set parity; `test_113`'s `log_pass` enumerates
  exactly the three mutations it ran.
- No banned `printf|grep -q` pipe shape in the new arms (the one new pipe is `grep -c`,
  which reads its whole input and cannot SIGPIPE its writer). `test_020` documents its
  `case`-glob choice for the same reason (`tests/skills/test-aai-suite-select.sh:373-374`).
- No `git restore`/`checkout --`/`reset --hard`/`stash` on the shipping tree. `test_113`'s
  two `git -C "$wt" checkout --` calls are inside the disposable detached worktree that
  HAZ-WORKTREE mandates, and the arm ends by asserting the real checkout is unchanged
  (line 1789-1790). The `HSK_ACTIVE_WORKTREE` EXIT-trap teardown at lines 22-27 uses a
  targeted `git worktree remove`, never `prune` — correct per HAZ-WORKTREE.
- Append-only ledgers: `main` is a byte-exact prefix of HEAD for all three
  (`EVENTS.jsonl` 358770→358954, `decisions.jsonl` 414230→414953,
  `tests/test-runs.jsonl` 22763→23495; `cmp` clean on the prefix).
- Commit messages match their contents: `a7abfc2` "two … telemetry entries" adds exactly 2
  test-run lines, `a88eef6` "three hand-fixed harness surfaces" adds test_114, test_115 and
  test_020.

## The normalization (87 files)

Independent spot-check of three skills against the declared transform:
`aai-loop`, `aai-docs-hub`, `aai-wrap-up` — `.agents` copy byte-identical to `.claude`;
`.codex` and `.gemini` copies byte-identical to `.claude` with `^model:` filtered. All nine
comparisons IDENTICAL. `model:` line counts: `.claude` 4 files, `.agents` 4, `.codex`+`.gemini` 0 —
matching D1's table and matching what those trees already carried on `main`, so the drop is
preservation, not a new decision (see cannot_verify).

What a byte comparison cannot see, checked by hand:

- **Claude-specific instructions carried into other harnesses:** zero occurrences of
  "Claude Code" anywhere in `.codex/skills/*/SKILL.md`. The only `.claude/` path references
  are the two in `aai-auto-trigger`, and both are *correct*: they name
  `.claude/triggers.json`, the real path, replacing the `.Codex/triggers.json` corruption the
  spec's headline is built on. This is the change doing exactly what it claimed.
- **Restored `<SUBAGENT-STOP>` blocks:** now 15 files in each of the four trees (was 15/3/…
  before). Sampled `.codex/skills/aai-loop/SKILL.md:6-8` — the text is harness-neutral
  ("If you were dispatched as a subagent to execute a specific role…"), names no
  Claude-specific tool, mechanism or path, and reads correctly for a Codex subagent (Codex
  has native subagents) and harmlessly for a Gemini session that has none — it is a
  conditional whose antecedent is simply false there.
- **Companion assets:** exactly one exists repo-wide,
  `.claude/skills/aai-docs-hub/README.md`. It is not mirrored and `--check` does not notice
  (round 2's N7). Nothing references it, and the mirrors never carried it on `main` either
  (`git log --all -- .codex/skills/aai-docs-hub/README.md` is empty), so this is a
  pre-existing gap the generator inherits rather than creates. Agreeing with N7:
  **accepted residual**, with a **successor-item** if vendored skills ever gain real assets.

## The three hand-edited surfaces

**`.cursor/rules/aai.mdc` (32 lines), read as an instruction its reader must execute.**
End to end it works: "read `.aai/AGENTS.md` first" matches `CLAUDE.md`'s own shim; the skill
section names the three trees this repo actually ships and the `/skill-name` invocation form;
`docs/ai/STATE.yaml` is now the full path rather than a bare `STATE.yaml`, which is strictly
more executable. A Cursor user following it reaches `.aai/AGENTS.md` and can invoke any
shipped skill. No contradiction with `.aai/AGENTS.md` or `CLAUDE.md` on any rule.

The one wrinkle is round 2's N10 and I **agree with the disposition but sharpen the reason**:
the rule says "invoke one with `/skill-name` rather than reading a prompt file by hand", then
points at `.aai/AGENTS.md` "for the full skill catalog" — and that catalog
(`.aai/AGENTS.md:78-136`) is 30 lines of `Follow .aai/SKILL_X.prompt.md`. The *claim* is true
(the catalog is there and is complete), so this is not a false record; the *idiom* of the
destination is the one the rule just deprecated, and the `SKILL_LOOP` → `/aai-loop` mapping is
left to the reader to infer. Accepted residual; harmonizing `.aai/AGENTS.md` is outside this
scope's file list. **successor-item** if anyone touches that section.

**Root `AGENTS.md`.** `git diff main..HEAD -- AGENTS.md` shows the title line and nothing
else — verified. I went one step further than test_115, which only pins the first line and the
absence of `# Codex Instructions`: the file's remaining 21 lines contain **zero** occurrences
of "Codex", "Claude", "Gemini" or "Cursor" (case-insensitive), so the harness-neutral title is
not sitting on top of a harness-specific body. Spec-AC-08 is honestly met, not just literally.

**Suite-map rows.** `tests/skills/suite-map.yaml:363` adds the `.agents` glob to the pattern
already carrying `.claude`/`.codex`/`.gemini`; lines 369-375 add the generator, the manifest,
the Cursor rule and root `AGENTS.md` under a comment naming the change. `aai-hygiene-pack` is a
`core:` suite, so these rows widen an always-on suite — they cannot narrow selection for
anything else, since suite selection is additive. Correct.

**N9 — does `test_114` oversell itself?** No, and I overrule nothing here, but I want the
reason on the record because "a false claim in a tracked file is this repo's worst defect
class". I read every string the arm emits. Its `log_info` enumerates the five checks it is
about to run; its `log_pass` reads "Cursor rule contract holds — no stale prompt-file claim,
no enumerated SKILL_ paths, single alwaysApply/description line, 32 lines (TEST-008)". Both
sentences list precisely the observables asserted and claim nothing beyond them. The word
"contract" in the function name is the only loose token, and the immediately following clause
defines it. The *spec* is where the wider claim lives (Spec-AC-07's "claims nothing the
current Cursor docs contradict"), and the spec's own Notes column already says "five grep
observables". So the arm is faithful and the gap is named in the frozen spec — that is honest
recording, not overselling. Where it matters is the close flip: Spec-AC-07's Evidence must
cite the vendor-doc check alongside TEST-008, not TEST-008 alone. Carried as **CV-2**.

## Round 2 residuals N3-N11 — carried forward with my own judgement

| Ref | My call | Note |
|---|---|---|
| N3 hardcoded `REQUIRED_MIRROR_TREES` / Spec-AC-03 text broader than implementation | **Agree, and split** | The AC-text half is close-ceremony as round 2 says. The other half — a *declared but unmirrored* row accepted in silence — is my Q1, is not constrained by the frozen spec, and IS remediable in tree. Round 2 called the whole item "not remediable in-tree without reopening a frozen spec"; I overrule that for the Q1 half. |
| N4 raw node stack on malformed source frontmatter | **Agree** | Re-measured: exit **2**, stderr is a full stack whose first line does name the offending path. Article 4 (degrade and report) holds; only the presentation is wrong. successor-item. |
| N5 `test_111` runs `--write` against the real checkout | **Agree** | Confirmed the gate: `--write` is only reached after `--check` exits 0, and the generator writes nothing when content already matches, so zero bytes move on a clean tree. Bounded. successor-item, natural home SPEC-0137. |
| N6 an excluded-but-present skill is reported `extra` and DELETED by `--write` | **Agree** | Verified by reading `main`'s loop: `expected` is filtered by exclusions, so `extra` covers it and `rmSync` removes it. Undeclared second direction; the declared direction is correct and tested. close-ceremony (one manifest-header line). |
| N7 companion assets not mirrored, `--check` silent | **Agree** | Independently measured: exactly one such file exists, never mirrored on `main` either. accepted residual + successor-item. |
| N8 no `CHANGELOG.md` entry | **Agree** | Re-confirmed at HEAD: zero CHANGELOG paths in `git diff --name-only main..HEAD`. close-ceremony, orchestrator's job, needs a `## [unreleased] — <title>` heading (not a bullet). Does not gate this verdict. |
| N9 arms are literal-string shaped, blind to semantic rewording | **Agree** | With the reasoning above: the arms' own text claims only what they assert, so nothing false is recorded. accepted residual. |
| N10 rule steers away from prompt files, then points at a prompt-file catalog | **Agree** | Sharpened above: true claim, mismatched idiom. accepted residual. |
| N11 rule omits `.cursor/skills/` from the discovery list | **Agree** | Deliberate under D2, and an omission cannot be a claim the vendor docs contradict. accepted residual. |
| — | **NEW Q2, Q3, Q4, Q5** | Not in either validation report. Q2 and Q4 are guard holes in the guard; Q3 answers the dispatch's explicit `--write` containment question; Q5 is a one-word wiring slip. |

## `--check` as a guard's evidence

Stable enough. The tree order is a fixed constant, the skill order is `listSkills`'s
`.sort()`, and every divergence line is a fixed prefix plus paths. The only variable text is
`firstDiffHint`'s 140-char clipped `JSON.stringify` of the offending line, which is
deterministic given the inputs and cannot inject a newline. `exit 1` on dirty / `exit 0` on
clean is honoured. The two ways it can be wrong are Q2 (unreadable target swallowed) and the
companion-asset blind spot (N7) — both named above.

## Checks performed

| Command | Exit | Snippet |
|---|---|---|
| `git branch --show-current` | 0 | `fix/harness-surface-parity` |
| `node .aai/scripts/sync-harness-skills.mjs --check` | 0 | `OK: .agents/skills, .codex/skills, .gemini/skills match the declared transform` |
| `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh` | 0 | `All aai-hygiene-pack tests passed` (includes test_110..115) |
| `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh` | 0 | includes test_020 (TEST-010) |
| `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` | 0 | TEST-012 corpus/growth pins hold (TEST-012) |
| `env -u AAI_ROLE bash tests/skills/test-aai-layer-profiles.sh` | 0 | live-tree PROFILES conformance (TEST-011) |
| `env -u AAI_ROLE bash tests/skills/test-aai-doc-numbering.sh` | 0 | close-work-item content-hash pin (TEST-014) |
| `shasum -a 256 .aai/scripts/close-work-item.mjs` | 0 | `7e8757291b7b5e61d9aef3005f193361ff91f49575f3cb1ee4072a86ad696060` — allowlisted value, unchanged |
| `git diff main..HEAD --name-only -- .aai/scripts/aai-sync.sh .aai/scripts/aai-sync.ps1 \| wc -l` | 0 | `0` (D5 honoured) |
| `git diff main..HEAD -- AGENTS.md` | 0 | title line only |
| ledger prefix `cmp` for the three append-only ledgers | 0 | `PREFIX-OK` on all three |
| generator hostile probes 1-4 (scratch fixture, `/bin/bash -c`) | — | see Q1-Q3 |
| byte spot-check 3 skills × 3 trees vs the declared transform | 0 | 9/9 `IDENTICAL` |

Not run, deliberately: `tests/skills/test-framework.sh` (the ~20-minute full sweep).
Validation executed it twice on this scope — round 1 81/81 clean, round 2 80/81 with the
single red re-proved 4/4 green in isolation and not present in this diff — and the dispatch
budget forbids a third pass. I substituted per-suite runs at HEAD for the five suites this
scope actually touches, which is stronger evidence for the two commits the last recorded
sweep predates. Recorded as **CV-1**.

## Next steps

1. **Q1** — remediate in tree (3-line refusal + one manifest-header line naming the
   hardcoded tree list). This is the finding I would most want closed before merge, because
   it is the one that can leave a maintainer believing a declared edit shipped.
2. **Q4, Q5, Q2** — remediate in tree; all are ≤ 5 lines and all harden the guard this scope
   exists to build.
3. **Q3** — successor-item (symlink containment in `--write`).
4. **Close-ceremony:** `CHANGELOG.md` `## [unreleased] — <title>` entry (N8); Spec-AC-03
   Notes recording the tree-list narrowing (N3); one manifest-header line on the
   excluded-and-present direction (N6); Spec-AC-07 Evidence citing the vendor-doc check
   alongside TEST-008 (CV-2); a full-sweep entry at final HEAD in
   `docs/ai/tests/test-runs.jsonl` (CV-1).
5. **Accepted residuals** (P3, assurance-strength only, nothing false recorded anywhere):
   N7 companion assets, N9 literal-string arms, N10 catalog idiom, N11 `.cursor/skills/`
   omission.
6. **successor-items:** N3 (move the tree list into the manifest), N4 (map the parse error
   to `fail(2, …)`), N5 (move the idempotence half into `test_113`'s worktree), N7 (if
   skills gain assets), N10 (if `.aai/AGENTS.md`'s catalog is rewritten), Q3.

Overall: **PASS**. The generator does what the spec says, the 87-file normalization is
byte-exact under the declared transform and fixes a real five-week-old corruption, the guard
is always-on and bites, and the three hand-edited surfaces are honest about what they assert.
