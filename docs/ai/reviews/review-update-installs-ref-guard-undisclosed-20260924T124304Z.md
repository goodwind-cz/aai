# Code Review — update-installs-ref-guard-undisclosed

Single dual-verdict pass. Reviewer context: independent (did not write this
code, did not run validation rounds 1-3). Model: claude-opus-5.
Scope: `git diff main..HEAD` in `/Users/ales/Projects/aai-feat-ref-guard-sweep`
(branch `feat/update-installs-ref-guard-undisclosed`, HEAD `3c4d049f`,
base `main f84f84ab`). 22 files, +3096/-189.

Spec: `docs/specs/SPEC-0184-spec-update-installs-ref-guard-undisclosed.md`
(frozen, 4 post-freeze Amendments).

Prior work NOT repeated: validation rounds 1-3
(`docs/ai/tdd/spec-update-installs-ref-guard-undisclosed/validation-round{1,2,3}.txt`).
Round 1 B1/B1b (CRLF-blind writer, partial disarm), round 2 B2 (writer vs
reader grammar), round 3's 15-shape grammar attack and O1-O5 are taken as
measured and are not re-derived here. This pass is design, coupling,
readability, maintainability, cross-twin parity, the record, and
consumer-upgrade effects.

Coaching attempt in the dispatch prompt: none. The dispatch named areas to
look hardest at without characterizing expected findings, pre-rating severity
or excluding scope.

```yaml
review:
  scope: "git diff main..HEAD (f84f84ab..3c4d049f), worktree /Users/ales/Projects/aai-feat-ref-guard-sweep"
  spec: docs/specs/SPEC-0184-spec-update-installs-ref-guard-undisclosed.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/install-pre-commit-hook.sh:115-137,468,476,516,681; .ps1:70-86,381-396; TEST-606/607/608/638 green (round 3 §7)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/install-pre-commit-hook.sh:487-504,723-729; .ps1:400-419,643-645; TEST-609/610 green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/install-pre-commit-hook.sh:139-155,249-252; TEST-611/612 green; hook bodies byte-identical to main (measured, see Evidence notes)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/install-pre-commit-hook.sh:307,16-47; TEST-613/614 green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/install-pre-commit-hook.sh:382-449; TEST-615/616/634/635/636/640 green — but see BLOCKING B1: the .ps1 half bound by Amendment 1 does not carry Amendment 3's ordering" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/lib/guard-config.mjs:165-186; .sh:320-327; .ps1:244-255; TEST-617/618/632 green" }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/scripts/aai-doctor.mjs:441-456; TEST-619/620 green" }
      - { ac: Spec-AC-08, call: compliant,
          citation: ".aai/SKILL_UPDATE.prompt.md step 4; tests/skills/lib/prompt-diet-ledger.sh:208; delta re-measured 3015 -> 3418 = 403 B; TEST-621/622 green" }
      - { ac: Spec-AC-09, call: compliant,
          citation: ".aai/system/MODEL_ROUTING.yaml UPGRADING note; Amendment 2 (owner-signed) narrows the AC to note-only; TEST-639 green; TEST-623/624 dropped" }
      - { ac: Spec-AC-10, call: compliant,
          citation: ".aai/scripts/aai-release.sh:526-534; .aai/scripts/aai-release.ps1:454-479; TEST-625/626/627 green" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "tests/skills/test-aai-sync-seed.sh TEST-628/629/630 green; mutation records replayed RED 34/34 (round 3 §7)" }
    deviations:
      - { id: D-1, kind: frozen-plan-item-dropped,
          what: "Implementation plan edge case '--decline-ref-guard combined with --hooks ref-guard is contradictory and exits 2 naming the contradiction' is not implemented; measured exit 0.",
          where: ".aai/scripts/install-pre-commit-hook.sh:454-465", amendment: none }
      - { id: D-2, kind: frozen-plan-item-dropped,
          what: "Implementation plan names '-Print' as part of the .ps1 surface; the twin has no -Print at all.",
          where: ".aai/scripts/install-pre-commit-hook.ps1:56-62", amendment: "none (related registry item fu-ps1-refusal-no-manual-merge filed, but the plan deviation is not disclosed in an Amendment)" }
      - { id: D-3, kind: record-overstates-delivery,
          what: "Amendment 3 states, unqualified, that the decline now writes the declaration before removing the hook so 'a failure leaves the guard installed and armed'. Measured: true of the .sh, false of the .ps1.",
          where: "spec Amendment 3; .aai/scripts/install-pre-commit-hook.ps1:326-332" }
      - { id: D-4, kind: open-obligation,
          what: "AC Status table carries 11 'planned' rows with empty Evidence at review time (canon-carved for Validation by VALIDATION.prompt.md 8a; still owed at the close flip).",
          where: "spec ## Acceptance Criteria Status" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/install-pre-commit-hook.ps1, line: 326,
          issue: "Disable-RefGuard removes the ref-guard hook BEFORE writing the declaration — the exact ordering defect round 1 filed as B1b and fixed in the .sh twin only. No test, static or behavioural, pins the twin's ordering.",
          failure_scenario: "Measured under pwsh 7.6.3 against a real git fixture: guard armed, docs/ai/docs-audit.yaml chmod 444, then `-DeclineRefGuard` -> Set-Content throws, rc=1, hook GONE, config still 'ref_guard: armed'. The consumer is disarmed with no record of having declined, on the platform of the reporter of goodwind-cz/aai#369. The .sh twin on the same fixture: rc=0 or (round 1's shapes) rc=1 with the guard still installed." }
      - { rank: BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 384,
          issue: "write_ref_guard_policy CREATES docs/ai/docs-audit.yaml when absent (same in .ps1:284-285), and the mere EXISTENCE of that file flips the whole docs audit from report-only to enforced (lib/docs-audit-core.mjs:131,1142; hardFail at :1651). A command about a git hook silently arms an unrelated gate, with no disclosure — while the project's one existing creation site, aai-sync.sh:436, discloses exactly this consequence.",
          failure_scenario: "Measured in a scratch repo with one schema-violating doc and no docs/ai/docs-audit.yaml: `docs-audit.mjs --check` rc=0, 'Mode: report-only'. Then `install-pre-commit-hook.sh --decline-ref-guard` (creates the file with only 'ref_guard: declined'): `docs-audit.mjs --check` rc=1, 'Mode: enforced'. A consumer who declines a git hook finds their docs audit (and any CI step running it) newly red for reasons unrelated to the hook." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 454,
          issue: "Six flags resolve into a boolean lattice with no resolved MODE; three combinations are silently ignored instead of refused.",
          failure_scenario: "Measured: `--uninstall --decline-ref-guard` -> exit 0, the ref-guard is removed and declined, the AAI pre-commit hook the user asked to uninstall SURVIVES, no warning. `--hooks ref-guard --decline-ref-guard` -> exit 0 (the frozen plan says exit 2). `--print <anything-else>` -> prints and exits 0, ignoring the rest." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 710,
          issue: "WANT_REFGUARD is the SELECTION variable and is re-assigned mid-flow to mean 'was actually installed' (same in .ps1:617), so one name carries two meanings at two points in the file.",
          failure_scenario: "A maintainer adding any consumer of the selection AFTER line 714 (a summary line, a second attestation, a telemetry field) reads WANT_REFGUARD as 'the user asked for the guard' and gets 'the guard is on disk' instead — or, placing it before 707, the reverse. The attestation at :727 only works because it happens to sit after the clearing." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 383,
          issue: "Production code shaped by the mutation harness without saying so: `local write_mode=\"replace_or_append_key\"` is a constant whose only purpose is to be the --sed target of mutation-TEST-615, and the `# AC-0N ...` trailing comments at :423, :468, :476, :492, :498, :516, :681, :724, :727 are mutation anchors that read as ordinary annotations.",
          failure_scenario: "A maintainer simplifies `if [[ \"$write_mode\" == ... ]]` away (it is provably constant) or drops an 'obvious' trailing comment; the suite stays green and the failure surfaces only at the next `mutation-run.mjs --replay`, as a stale record with no explanation. aai-release.sh:528 shows the right shape: it states the harness constraint in the comment." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-doctor.mjs, line: 50,
          issue: "The new CAT-17 'DECLINED' status is absent from every place the doctor's status vocabulary is stated: the header contract says `CAT-NN <PASS|WARN|FAIL|SKIP>`, the --strict sentence at :56-58 says exit 0 'only when every category is PASS or SKIP', and .aai/SKILL_DOCTOR.prompt.md:27 tells the relaying agent the same four-value set.",
          failure_scenario: "A --json consumer (update-doctor-report.mjs passes categories through untyped) or the doctor skill meets DECLINED with no rule for it; the skill's mapping table at SKILL_DOCTOR lines 39-42 has no branch, so the relay either drops the category or reports it as an unknown state." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 43,
          issue: "Comments that the diff made untrue. The --help text (printed verbatim by `grep '^#' \"$0\"`) still claims the foreign-hook check covers 'BOTH hooks before writing either' — Spec-AC-02 deliberately scoped it to the SELECTED set. Same sentence in .ps1:14-15 (.DESCRIPTION).",
          failure_scenario: "An operator runs `--hooks index` over a repo with a foreign reference-transaction hook, reads --help, and expects a refusal; the run exits 0 and touches only the index slot (which is correct, and the opposite of what --help says)." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_UPDATE.prompt.md, line: 56,
          issue: "Step 4's success line instructs the agent to report BOTH hooks installed; after Amendment 3 a plain install honours a declared decline and installs only one.",
          failure_scenario: "A consumer who declined the guard runs /aai-update; the installer prints 'Skipped AAI reference-transaction hook ... declares ref_guard: declined', and step 4 has the agent report 'AAI git hooks installed (docs-index pre-commit, AAI:REF-GUARD reference-transaction)'. The prompt this ride rewrote for honesty now overstates the one case this ride added." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.ps1, line: 322,
          issue: "Disable-RefGuard reuses Show-ForeignReftxRefusal, whose text says 'Pass -Force to overwrite' — but the decline's foreign refusal ignores -Force, and the clarifying Write-Host at :323 is unreachable (Write-Error is terminating under $ErrorActionPreference='Stop', as the file itself documents at :78-81).",
          failure_scenario: "Measured: `-DeclineRefGuard` over a foreign reference-transaction hook -> rc=1 with only 'Pass -Force to overwrite'; `-DeclineRefGuard -Force` -> rc=1 again, hook untouched. The operator is told to pass a flag that provably changes nothing, and the sentence explaining the real rule never prints. (The terminating-Write-Error class itself is already filed as fu-ps1-writeerror-terminates-before-exit; the wrong-advice message this refactor created is not.)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 4468,
          issue: "TEST-618 extracts the shell mirror's pattern positionally — the FIRST `grep -Eq` line mentioning ref_guard in install-pre-commit-hook.sh. Two such lines now exist with DIFFERENT grammars (:322 the reader mirror, :386 the writer's gate).",
          failure_scenario: "A pure refactor that moves write_ref_guard_policy above read_ref_guard_policy silently re-points the conformance test at the writer's any-token gate; the 'armed' fixture then computes want=declined and the test fails with a drift message that names the wrong reader — or, worse, a future third pattern lands first and the conformance claim quietly covers nothing." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 23,
          issue: "No `## [unreleased]` entry for a consumer-visible change to the installer that /aai-update runs, to CAT-17's output vocabulary, and to a committed config file's schema. The three comparable sweeps on main (SPEC-0179/0180/0182) each shipped one.",
          failure_scenario: "A consumer upgrades, sees a new `ref_guard:` line appear in docs/ai/docs-audit.yaml and a CAT-17 line they have no vocabulary for, and finds nothing in the changelog to read." }
  cannot_verify:
    - { claim: "The .ps1 twin's behaviour on Windows PowerShell 5.1 (Set-Content encoding/CRLF, the exit-2-means-1 divergence, and B1's failure shape after it is fixed).",
        closes_with: "The Windows CI leg on the PR, or a Windows run recorded in the PR body." }
    - { claim: "That no downstream consumer already carries a doubled or token-less ref_guard key (round 3 O1/O2).",
        closes_with: "Nothing available in this repo; the key is new in this ride, so the expected population is zero." }
    - { claim: "Full-sweep green at HEAD. Round 2 ran the full sweep at the parent commit (94/95); round 3 ran CORE+SELECTED at HEAD with a reasoned selector argument.",
        closes_with: "AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh at 3c4d049f, once, before close (the spec's own Verification already demands it)." }
    - { claim: "That the docs-audit mode flip (B2) has bitten a real consumer.",
        closes_with: "Measured here on a scratch fixture only; the population of consumers without docs/ai/docs-audit.yaml is not observable from this repo." }
  overall: fail
```

## The two blocking findings, in plain words

### B1 — the twin never got round 1's fix

Round 1 blocked this ride partly on B1b: `decline_ref_guard` removed the hook
before recording the decline, so any write failure left a consumer disarmed
with nothing written down. The `.sh` was reordered (write first, remove second,
`install-pre-commit-hook.sh:429-433`) and Amendment 3 records the fix as a
discipline — "the declaration is written first, and a failure leaves the guard
installed and armed" — with no qualification about which twin.

`install-pre-commit-hook.ps1:326-332` still does it in the old order.

Measured, pwsh 7.6.3, real git fixture:

```
armed: hook=PRESENT cfg=ref_guard: armed
chmod 444 docs/ai/docs-audit.yaml
pwsh -File .aai/scripts/install-pre-commit-hook.ps1 -DeclineRefGuard
  Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from .../reference-transaction
  Set-Content: ... Access to the path '.../docs-audit.yaml' is denied.
  rc=1   hook: ABSENT   cfg: ref_guard: armed
```

Same fixture, `.sh`: rc=0 and the declaration really written (or, in round 1's
own shapes, rc=1 with the guard still installed). Amendment 1 is the reason
this matters beyond symmetry: it pulled the twin into scope precisely because
"a decline path only POSIX consumers can take does not fix an issue reported
from Windows". The Test Plan has no `.ps1` row for TEST-635 and no static
assertion on the ordering, so nothing would have caught it.

**What I would do instead:** move `Write-RefGuardPolicy` above the
`Remove-Item` block in `Disable-RefGuard` (three lines), and add a twin arm to
TEST-635 using the pattern TEST-638 and TEST-641 already use (`command -v pwsh
&& ...`, `log_info` when absent). Cost: one function reorder, ~20 test lines,
one mutation record. The spec needs one sentence in Amendment 4 (or a new
Amendment 5) recording that Amendment 3's ordering claim was `.sh`-only until
this fix — the record should not be corrected silently, since two of the four
existing amendments exist to correct an earlier one.

### B2 — declining a git hook turns on a docs gate

`write_ref_guard_policy` creates `docs/ai/docs-audit.yaml` when it is absent
(`install-pre-commit-hook.sh:384`, `.ps1:284-285`). In this codebase the
*existence* of that file is a mode switch: `lib/docs-audit-core.mjs:131`
(`loadConfig` returns null when absent), `:1142`
(`mode = ... (config || strict) ? 'enforced' : 'report-only'`), `:1651`
(`hardFail = mode === 'enforced' && (orphansNew || violations) || ...`).
`docs-audit.mjs:50` states the contract: "report-only (absent) ... --check
always exits 0".

Measured in a scratch repo with one schema-violating doc:

```
no docs/ai/docs-audit.yaml        docs-audit --check -> rc=0, "Mode: report-only"
--decline-ref-guard (creates it)  docs-audit --check -> rc=1, "Mode: enforced"
```

The project already knows this side effect and discloses it at the one place
that previously created the file — `aai-sync.sh:436`:
`SEED docs/ai/docs-audit.yaml from .aai/templates/docs-audit.template.yaml
(dials report-only; docs-audit --check now runs enforced)`. The new writer is
a second creation path for the same file that skips both the template and the
disclosure.

This is blocking on the ride's own standard. The whole spec is an argument
that a consumer must be told when a command changes what their tools do —
D1: "what was actually wrong here was never the default, it was that the
operator learned about it from a refused commit." A consumer who declines a
git hook and finds their docs audit newly failing learns it the same way.

**What I would do instead (cheapest honest discharge):** when the config file
did not exist before the write, print one line naming the consequence, in both
twins — the same sentence `aai-sync` already prints — and add it to the spec's
Residual risks. Better, if the template ships in the target:
seed from `.aai/templates/docs-audit.template.yaml` and then set the key, so
one creation path and one disclosure serve both callers. Cost: ~6 lines per
twin plus one test arm; no mutation record is disturbed (this is new output,
not a changed matcher).

## The questions the dispatch asked

### Is the installer's control flow followable, or a lattice of flags?

It is followable today and will not be at the next addition. The file reads
top-to-bottom in one pass — parse, resolve selection, `--print` and exit,
resolve paths, define helpers, dispatch decline/arm and exit, uninstall and
exit, foreign pre-check, write index, write ref-guard, attest — and the
comments carry the reasoning rather than restating the code. That is better
than most 736-line shell scripts.

What has become a lattice is the *input space*, not the statements: six flags
(`--force`, `--uninstall`, `--print [hook]`, `--hooks <csv>`,
`--decline-ref-guard`, `--arm-ref-guard`) with exactly one refused combination
(decline + arm, `:454`) and at least three silently-ignored ones (measured
above). The single resolved variable everyone would expect — the mode — does
not exist; it is implied by the order of four early-exit blocks.

**What I would restructure:** resolve one `MODE` (`print | uninstall |
decline | arm | install`) immediately after parsing, and make any flag not
applicable to the resolved mode an exit-2 usage error naming the conflict.
That deletes the ordering dependency between the dispatch blocks, makes D-1's
frozen edge case fall out for free, and gives the twin one thing to mirror
instead of four.

**What it would cost**, honestly: the recorded `--sed` mutations for
TEST-606/607/609/610/615/616/636/638 pin the *current spelling* of the guards
they target (`want_hook ref-guard`, `replace_or_append_key`, the one-line
foreign checks). A mode refactor re-cuts about eight mutation records and
rewords their Test Plan Mutation cells, which is a post-freeze spec amendment.
That is a ride of its own, not in-tree work here. I would file it rather than
ask for it now.

### Do the twins stay in lockstep, and does anything enforce it?

Nothing enforces it beyond discipline and a growing pile of static greps.
The diff makes parity **harder in substance and easier in evidence**:

- Harder: the shared surface went from 2 flags to 6, and the `.ps1` grew a
  third implementation of the policy reader, the policy writer, the
  decline/arm dispatch and the plain-install skip. Two of the six new twin
  behaviours already diverge (B1, and the missing `-Print`), and four more
  divergences are filed as P3 registry items
  (`fu-ps1-decline-not-disclosed`, `fu-ps1-refusal-no-manual-merge`,
  `fu-ps1-symlink-config-replaced`, `fu-ps1-writeerror-terminates-before-exit`).
- Easier: before this ride there was essentially no twin-parity assertion
  beyond TEST-309/316. Now TEST-608/631/632/633/637/641 assert the twin's
  shape, and TEST-638/641 run the real `.ps1` when `pwsh` is on the host.

The honest summary is that parity is asserted by *source-text greps on the
`.ps1`*, which is exactly the class of evidence round 3's O4 measured as
defeatable. The cheap structural improvement is not a code merge (three
languages, no shared runtime) but a **single twin-parity table**: one fixture
list and one behaviour list consumed by both columns, skipped with `log_info`
where `pwsh` is absent, as TEST-638 already demonstrates. B1 is the proof that
it is needed: it is a behaviour, not a shape, so no grep on the `.ps1` was ever
going to see it.

### Three readers of one file — is one reader with two thin callers reachable?

No, and the duplication is structural rather than accidental. The constraint
is explicit and enforced: `check-vendored-script-deps.mjs` plus the installer's
own shipping contract forbid a `node` import from a script that installs into
targets where module resolution is not guaranteed
(`install-pre-commit-hook.sh:211-215`, spec Implementation plan edge cases).
That leaves three runtimes — POSIX shell, PowerShell, Node — and three regex
dialects with genuinely different definitions of `\s`. No amount of factoring
collapses them; even "share one pattern string" fails, because
`[[:space:]]` is locale-dependent, JS `\s` is Unicode, .NET `\s` is a third
set, and `Get-Content` strips line endings before any regex runs.

So the right target is not one reader but **one definition of the fixture
corpus**. Today `test_618` compares the shell mirror against the JS reader on
11 ASCII fixtures and the `.ps1` column is asserted statically; round 3's O3
(filed `fu-three-readers-three-whitespaces`, P2) measured that the three split
on U+0085, a BOM and CR-only endings. What I would do: move the fixture list
into one file under `tests/skills/lib/`, drive all three readers from it
(third column skipped where `pwsh` is absent), and add an ABSOLUTE expected
value per fixture beside the agreement check — `test_618` currently computes
its expectation *from the shell grep itself*, so it proves agreement and not
correctness. TEST-617 pins the JS column absolutely, which narrows but does not
close that hole.

### CAT-17's three states

The implementation reads exactly as intended by someone who did not write it,
and it is the cleanest part of the diff: the policy is consulted inside the
`!fs.existsSync(hookPath)` branch and nowhere else
(`aai-doctor.mjs:441-456`), with a comment that states D4 as the reason. An
armed hook and a foreign hook physically cannot reach the check. TEST-620
pins all three, and its status as a negative control whose proof is the
mutation record is disclosed in Amendment 2 rather than left to be discovered.

Two nits, both non-blocking: the config path is built twice (once for the
message at `:449`, once implicitly by `readRefGuardPolicy(path.join(root,
'docs/ai'))` at `:450`) and can drift; and the new status string is undeclared
in the doctor's own vocabulary contract (finding above). The second matters
more than it looks, because the vocabulary is what the doctor SKILL relays to
a human.

### The four amendments as a record

A maintainer *can* reconstruct what happened, and the reconstruction is
unusually good: each amendment states what changed, why, and — in Amendment 4's
case — why the earlier dismissal was wrong and what general lesson survives it
("a finding ruled harmless is only as good as its premise"). Round 3 verified
that lesson commit-by-commit and found it accurate. This is a better record
than most rides produce.

It is nevertheless drifting toward a changelog with a spec attached, for three
concrete reasons rather than a feeling:

1. **Two of four amendments correct an earlier amendment** (A4 corrects A3's
   CRLF class claim and A3's misattributed "round 1 N9" citation). A reader
   must now read all four in order, and hold a diff of A3 in their head while
   reading A4, to know what is true. The AC text itself — the thing that is
   supposed to be authoritative — has not moved since the freeze.
2. **B1 above shows the failure mode is live, not theoretical**: A3's
   unqualified ordering claim is read by everyone downstream as covering both
   twins, and it does not.
3. **The AC Status table is still eleven `planned` rows with no Evidence**, so
   the only place the delivered state is written down is the amendment prose
   plus three validation reports. This is canon-carved for Validation
   (`VALIDATION.prompt.md` 8a) but it does mean the record's centre of gravity
   is the narrative rather than the table. Note also the tension with
   `ROLE_COMMON.md` PRE-HANDOFF AC-TABLE RECONCILIATION, which says the TDD
   role reconciles covered rows to terminal *before* handing to Validation;
   this ride reached Validation three times with all rows planned.

**What I would do:** at the close flip, fill the Evidence column from the
`docs/ai/tdd/.../green-TEST-6xx-*.log` artifacts that already exist, and add
one short "Delivered state" section to the spec that states the final
behaviour in the present tense — five or six bullets — so a maintainer reads
the amendments only when they want the history. That is the difference between
a spec with amendments and a changelog with a spec attached.

### Does anything here make a FUTURE consumer's upgrade harder?

Three things, in descending order:

1. **B2** — creating `docs/ai/docs-audit.yaml` flips the docs audit to
   enforced. Measured above.
2. **The DECLINED status** enters the `--json` category vocabulary with no
   version marker and no documentation. `update-doctor-report.mjs` passes
   categories through untyped, so nothing breaks today, but a consumer with
   their own parser over `categories[].status` meets an unlisted value.
3. **Downgrade asymmetry**: a consumer who declines and then rolls the AAI
   layer BACK to a pre-ride installer gets the guard silently re-armed on the
   next `/aai-update`, because the old installer does not know the key. This is
   inherent to shipping a new declarative key and not worth engineering around,
   but it belongs in Residual risks — the ride's whole premise is that a
   consumer should not learn about an armed guard from a refused commit.

Nothing else in the diff is upgrade-hostile. The hook bodies are provably
unchanged (I re-measured: the `AAI:REF-GUARD` and `AAI:INDEX-AUTOGEN` heredocs
hash identically at `main` and at HEAD), `--print` bare and `--hooks` absent
keep their old meanings, `PROFILES.yaml` is untouched, and the
`MODEL_ROUTING.yaml` behaviour is unchanged by owner decision.

### Is `docs/ai/docs-audit.yaml` the right home for the decline?

**The file is the right home; the way this ride writes into it is not.**

The case for it is strong and was made on measurement, not taste (D2): it is
committed and therefore reviewable in a PR; `/aai-update` provably never
overwrites `docs/ai/` (`aai-sync.sh` prints `PRESERVE docs/ai/ runtime data`);
it already has a single canonical JS reader; and its column-0 grammar is
readable by a shell grep without a node dependency. Any new file invented for
`ref_guard` would have to re-earn all four properties, and a fifth surface for
a consumer to learn. The name "docs-audit.yaml" is already a misnomer for its
contents — `guard-config.mjs` calls it "the committed guard-policy file", and
it holds `doc_number_guard`, `usage_capture_gate`, `mutation_gate` and
`protected_paths_l3`, none of which are about the docs audit either.

What is wrong is narrower and fixable:

- **The file's own header still says "Docs audit policy (RFC-0002 D4)"** and
  was not amended when a git-behaviour switch moved in. One line.
- **The file's EXISTENCE is load-bearing for a different subsystem**
  (finding B2). A key-only file created by an installer is not the same object
  as a seeded config, and the code cannot tell them apart.
- **There is now a second writer with different behaviour from the first.**
  `aai-sync` seeds from a template and discloses the consequence; the installer
  writes one key and says nothing.

So: keep the location, fix the writing — seed-or-disclose on creation, and
correct the file's header to say what it now is. If the project later wants a
cleaner answer, the honest one is renaming the file to `guard-config.yaml`
with a back-compat read of the old name, which is its own ride.

## Warning dispositions (H6)

Every NON-BLOCKING finding above, with the artifact I recommend. The
orchestrator records these; a read-only reviewer files nothing itself.

| # | Finding | Disposition |
|---|---------|-------------|
| 1 | Flag lattice / silently-ignored combinations (incl. frozen D-1) | promote-to-follow-up-ref (P2) — a MODE refactor re-cuts ~8 mutation records; not in-tree here |
| 2 | `WANT_REFGUARD` / `$wantRefGuard` overloaded | remediate-in-tree if B1 is being fixed anyway (rename to `INSTALL_REFGUARD`); else follow-up (P3) |
| 3 | Mutation-anchor code and comments undisclosed | remediate-in-tree (comment-only, no matcher moves) |
| 4 | Doctor DECLINED absent from the stated vocabulary (3 sites) | remediate-in-tree (doc-only) |
| 5 | `--help` / `.DESCRIPTION` "BOTH hooks" now untrue | remediate-in-tree (comment-only; note TEST-614 greps --help, so re-run that suite) |
| 6 | SKILL_UPDATE step 4 reports both hooks after a decline skip | remediate-in-tree — but it moves prompt bytes, so it needs a diet-ledger true-up and a TEST-012 bump |
| 7 | `.ps1` decline refusal advises `-Force`, dead explanation line | remediate-in-tree alongside B1 (same function) |
| 8 | TEST-618's positional pattern extraction | remediate-in-tree (anchor on a marker comment, ~2 lines) |
| 9 | No CHANGELOG entry | remediate-in-tree at the PR commit |
| 10 | D-2 (`-Print` dropped from the `.ps1` plan) and D-4 (AC table) | D-2: one amendment sentence disclosing the drop (the registry item alone does not discharge a frozen-plan deviation). D-4: the close flip |

## Next steps

1. Fix B1 (reorder `Disable-RefGuard`, add the TEST-635 twin arm, record the
   mutation) and B2 (seed-or-disclose on config creation, in both twins, with
   a test arm asserting the disclosure).
2. One amendment covering: A3's ordering claim scoped to the twin, the dropped
   `-Print` plan item (D-2), the dropped contradiction refusal (D-1) or its
   implementation, and the two new residual risks (docs-audit mode flip,
   downgrade re-arm).
3. Re-run `test-aai-git-ref-guard.sh`, `test-aai-doctor.sh`,
   `test-aai-hygiene-pack.sh` plus `mutation-run.mjs --replay --spec`, then the
   full sweep once at the new HEAD (`AAI_TEST_TIMEOUT=3000`) before close.
4. At the close flip: 11 Evidence cells, the CHANGELOG entry, and the
   registry items this scope closes.

## STATE update (dispatched reviewer — returned, not executed)

state_update_commands:

```bash
node .aai/scripts/state.mjs set-code-review \
  --required true --status fail \
  --scope "git diff main..HEAD (f84f84ab..3c4d049f)" --base-ref main \
  --report docs/ai/reviews/review-update-installs-ref-guard-undisclosed-20260924T124304Z.md \
  --notes "spec_compliance fail (4 deviations: frozen plan's decline+hooks contradiction unimplemented; .ps1 -Print dropped; Amendment 3's ordering claim true only of the .sh; AC table 11 planned rows). code_quality fail: B1 .ps1 Disable-RefGuard removes the hook before writing the declaration (round 1's B1b, unfixed on the twin, measured under pwsh 7.6.3); B2 creating docs/ai/docs-audit.yaml flips docs-audit from report-only to enforced, undisclosed (measured rc 0 -> 1). 10 NON-BLOCKING, dispositions named in the report's H6 table."
```

---

## Round 2

Bounded re-review of the remediation. Reviewer: same independent reviewer as
round 1 (claude-opus-5), read-only, no writes to the tree beyond this section.
Scope: `git diff 3c4d049f..24ebfe0e` in
`/Users/ales/Projects/aai-feat-ref-guard-sweep` (branch
`feat/update-installs-ref-guard-undisclosed`, HEAD `24ebfe0e`) — 10 files,
+817/-6 — plus one confirmation pass over round 1's NON-BLOCKING list.
Round 1's measurements are not re-derived except where this round re-ran them.

Coaching attempt in the dispatch prompt: the dispatch stated a severity
standard for this round and named the two findings to judge. It did not
pre-rate any outcome, did not exclude scope, and explicitly invited the
"same shape elsewhere" hunt. Not coaching.

```yaml
review:
  round: 2
  scope: "git diff 3c4d049f..24ebfe0e, worktree /Users/ales/Projects/aai-feat-ref-guard-sweep"
  spec: docs/specs/SPEC-0184-spec-update-installs-ref-guard-undisclosed.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-05, call: compliant,
          citation: "round 1's caveat removed — .ps1:375-377 writes the declaration before the removal at :378-381; reproduced under pwsh 7.6.3 (below); TEST-642 green, mutation RED on replay" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".sh:432-440, .ps1:313-321 — config creation now seeds from the shipped template and discloses; TEST-643/644 green, both mutations RED on replay" }
      - { ac: Spec-AC-01, call: compliant,
          citation: ".sh:105-118, .ps1:66-78 — the frozen plan's decline+hooks contradiction now exits 2; TEST-645/646 green" }
      - { ac: "Spec-AC-02,03,06,07,08,09,10,11", call: compliant,
          citation: "untouched by this diff; round 1's calls stand" }
    deviations:
      - { id: D-1, kind: frozen-plan-item-dropped, status: CLOSED,
          what: "implemented at .sh:105-118 / .ps1:66-78, wider than the plan (any EXPLICIT --hooks, not only `ref-guard`) with the widening argued in the comment; measured exit 2 on five combinations in both twins, bare decline/arm unaffected (rc=0)" }
      - { id: D-2, kind: frozen-plan-item-dropped, status: DISCLOSED,
          what: "Amendment 5 records the `-Print` drop as dropped, not as out of scope; verified against `git show main:.aai/scripts/install-pre-commit-hook.ps1` — the twin never had it, so 'pre-existing gap, not a regression' is accurate" }
      - { id: D-3, kind: record-overstates-delivery, status: CLOSED,
          what: "Amendment 5's first paragraph corrects Amendment 3's unqualified ordering claim by name and by twin" }
      - { id: D-4, kind: open-obligation, status: STILL OPEN,
          what: "AC Status table still 11 `planned` rows with empty Evidence; Test Plan rows TEST-642..646 carry status `pending`. Canon-carved for the close flip, not for this round." }
      - { id: D-5, kind: frozen-body-now-false, status: NEW (a round-1 miss, not a round-2 regression),
          what: "Residual risks bullet 1 (spec:485-492) still states that a no-flag re-install re-arms a declined guard. Amendment 3 reversed that and TEST-636 pins the reversal. The bullet is superseded by a later amendment that names the override, which is this project's additive-with-disclosure convention, but read alone it is false.",
          where: "docs/specs/SPEC-0184-spec-update-installs-ref-guard-undisclosed.md:485-492" }
  code_quality:
    verdict: pass
    findings:
      - { rank: CLOSED, ref: "B1 (round 1)", file: .aai/scripts/install-pre-commit-hook.ps1, line: 375,
          evidence: "Reviewer's own round-1 repro re-run verbatim under pwsh 7.6.3 against a real git fixture: guard armed, `chmod 444 docs/ai/docs-audit.yaml`, `-DeclineRefGuard` -> rc=1, hook PRESENT, config still `ref_guard: armed` (line 73), stderr names `Access to the path '.../docs-audit.yaml' is denied`. Round 1's shape (hook GONE, config `armed`) is not reachable." }
      - { rank: CLOSED, ref: "B2 (round 1)", file: .aai/scripts/install-pre-commit-hook.sh, line: 432,
          evidence: "Disclosure measured on STDOUT in both twins with split redirection (stderr empty). Seeded file byte-identical between the twins (4022 B) and byte-identical to `cp -a template` + `ref_guard: declined\\n`; aai-sync.sh:436 is the same `cp -a` of the same template, so the object is equivalent, not similar. Template-absent fallback prints an identical NOTE in both twins and creates exactly `ref_guard: declined\\n` (od-verified)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 436,
          issue: "The template-absent fallback's NOTE names the docs-audit consequence but not the lane-gate one. lane-gate.mjs:340-345 probes only that docs/ai/docs-audit.yaml is readable, so a bare one-key file stops `protected_config_missing` firing while select-suites.mjs:171-178 reads zero `protected_paths_l3` from it.",
          failure_scenario: "A repo pinned to the heavy lane by a missing config takes the fast lane with an empty L3 surface after a decline. Reachability measured: the branch fires only when .aai/templates/docs-audit.template.yaml is absent, and that template is in PROFILES.yaml's `core` list (line 226) and is vendored by the same sync that vendors this installer — so no sync path reaches it; a hand-pruned .aai does." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.ps1, line: 340,
          issue: "`Set-Content` rewrites every line of the file it just seeded using the platform newline, so on Windows the 73-line template lands CRLF where aai-sync.ps1's `Copy-Item` would have left it LF.",
          failure_scenario: "A Windows consumer's first decline commits a whole-file line-ending change rather than one added key. Readers are CRLF-tolerant (TEST-634), so this is diff noise, not a behaviour defect. NOT measured — POSIX pwsh writes LF; see cannot_verify." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.ps1, line: 369,
          issue: "Enable-RefGuard installs the hook and only then records `armed`, with no counterpart of the .sh's D4 rationale comment (install-pre-commit-hook.sh:471-477) explaining why that order is safe here and not in the decline.",
          failure_scenario: "A maintainer applying B1's lesson twin-wide 'fixes' Enable-RefGuard's order too and breaks the D4 property the .sh twin deliberately relies on." }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 520,
          issue: "`--uninstall --hooks ref-guard` removes the guard and writes no record at all, so the config keeps saying `armed` while the hook is gone — the same end-state shape B1 was about, reached by a different flag.",
          failure_scenario: "Measured: guard armed, `--uninstall --hooks ref-guard` -> rc=0, hook ABSENT, `ref_guard: armed`. Safe direction (D4 makes every reader trust the file over the declaration, and the operator asked for it), but the decline and the uninstall now disagree about whether removing the guard is worth recording." }
  cannot_verify:
    - { claim: "The .ps1 twin on Windows PowerShell 5.1 / Windows pwsh: B1's failure shape, the exit-2 usage code, and the Set-Content line-ending rewrite of the seeded template.",
        closes_with: "The Windows CI leg on the PR." }
    - { claim: "That the lane-gate loosening is reachable by any real consumer.",
        closes_with: "Nothing in this repo; the precondition is a tree carrying this installer but not the template that ships with it." }
    - { claim: "Full-sweep green at 24ebfe0e.",
        closes_with: "Attestation at b511d033 accepted — see 'On the sweep attestation' below." }
  overall: pass
```

### B1 — closed, reproduced

Repro re-run verbatim, pwsh 7.6.3, real git fixture, worktree HEAD:

```
arm:            hook=PRESENT  cfg=ref_guard: armed
chmod 444 docs/ai/docs-audit.yaml
pwsh -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1 -DeclineRefGuard
  rc=1
  stdout: (empty)
  stderr: Set-Content: ...install-pre-commit-hook.ps1:340:3
          Access to the path '.../docs-audit.yaml' is denied.
  hook:   PRESENT
  cfg:    ref_guard: armed      (line 73, unchanged)
```

The guard survives, nothing is recorded that did not happen, and the message
names the real file and the real reason. TEST-642 carries both halves the
amendment claims — a source-order assertion that bites on a host with no pwsh,
and the behavioural arm (it exercises the *append* branch with
`close_gate: enforce` + chmod 444; my repro exercises the *replace* branch with
an existing `ref_guard:` key — both fail at the same `Set-Content`).

One wording nit, not a defect: the comment at `.ps1:365-368` says a failed
write "returns `$false` with the guard still installed". Under
`$ErrorActionPreference = 'Stop'` neither failure path returns — `Set-Content`
throws and the verify path's `Write-Error` is terminating (the already-filed
`fu-ps1-writeerror-terminates-before-exit` class). The *outcome* the sentence
promises is exactly what I measured; only the mechanism named is wrong.

**The same shape elsewhere.** I walked every destructive operation in both
twins (`.sh` 281/322/430-446/479/518/526/568/723; `.ps1` 317/340/379/398/432/
440/637/680) against the record that justifies it. There is no second place
where an irreversible effect precedes its record in a way that produces a
silent-harm state. Three places order effect-before-record deliberately, and
two of the three say so:

- `arm_ref_guard` / `Enable-RefGuard` install the hook before recording
  `armed`. The `.sh` states the reason (D4: every reader trusts an installed
  hook over the declaration, so a stale `declined` surviving a failed record
  is read as armed anyway). The `.ps1` does not state it — finding above.
- `--force` past a decline installs the hook and leaves the declaration
  `declined`; argued at length in `.sh:742-754`.
- `--uninstall --hooks ref-guard` removes the guard and records nothing at
  all — finding above.

The seed itself creates the file before printing the disclosure, but that is
one command's own output; the operator sees it in the same run.

### B2 — closed, and the answer to the question it implied

Measured at HEAD, both twins, fresh git fixtures, streams split:

```
template present, .sh   rc=0  STDOUT: SEED docs/ai/docs-audit.yaml from .aai/templates/... (dials
                                      report-only; docs-audit --check now runs enforced)
                              STDERR: (empty)
template present, .ps1  rc=0  same line, STDOUT, STDERR empty
                              -> the two files are BYTE-IDENTICAL (4022 B) and
                                 byte-identical to `cp -a template` + "ref_guard: declined\n"
template absent, .sh    rc=0  STDOUT: NOTE: creating docs/ai/docs-audit.yaml -- this switches
                                      docs-audit from report-only to enforced mode ...
template absent, .ps1   rc=0  the SAME NOTE text (diff-clean), file = "ref_guard: declined\n"
```

So: the disclosure reaches the operator on stdout, not stderr, and is not
swallowed (`Write-Host` under pwsh 7.6.3 lands on stdout under redirection —
verified, not assumed). The seeded object is *equivalent* to the sync path's,
not merely similar: `aai-sync.sh:436` is `cp -a` of the same template, and the
installer's result is that file plus one appended key. The fallback does not
create a silent file — but its NOTE is narrower than the file's real effect
(the lane-gate finding above), and that branch is not reachable through any
sync path, because the template it looks for ships in the same `core` profile
as the installer.

**Is `docs-audit --check` still report-only for a consumer who declines?**
No. Re-measured at HEAD in a scratch repo:

```
before  docs-audit.mjs --check -> "- Mode: report-only"
--decline-ref-guard (seeds the template, prints the SEED line)
after   docs-audit.mjs --check -> "- Mode: enforced"
```

The seeding does not soften it. `docs-audit-core.mjs:1141-1142` makes the mode
a function of the file's *existence* — `loadConfig` returns non-null for any
parsed file, however sparse — and the template's dials govern other guards
entirely; its `legacy_until_date` ships commented out, so pre-existing docs get
no soft-warn from it either. There is no flag that declines the guard without
creating the file.

So the honest answer is: **the ride has made the flip visible, not avoidable.**
That is a defensible place to stop — the disclosure is now byte-for-byte the
one the project's only other creation path prints, and inventing an
"avoid the flip" mode would mean a second file or a deferred write, which is a
ride of its own. But it should be *said* rather than implied, and the spec's
Residual risks section (spec:484-498) is where round 1 asked for it and is the
one place it did not land — Amendment 5's prose carries it instead. That is the
structural drift round 1 already described, now with a concrete instance.

### D-1 — both twins, measured

```
                                                    .sh                  .ps1
--decline-ref-guard --hooks ref-guard               rc=2 stderr          rc=2 stderr
--hooks ref-guard --decline-ref-guard               rc=2 stderr          rc=2 stderr
--arm-ref-guard --hooks all                         rc=2 stderr          rc=2 stderr
--decline-ref-guard --hooks index                   rc=2 stderr          rc=2 stderr
--decline-ref-guard --hooks bogus                   rc=2 stderr          rc=2 stderr
--decline-ref-guard            (bare)               rc=0, SEED + declared
--arm-ref-guard                (bare)               rc=0, hook installed
```

The bare decline and the bare arm are genuinely unaffected: the gate keys on
`HOOKS_ARG_EXPLICIT` / `$PSBoundParameters.ContainsKey('Hooks')`, not on the
resolved value, so the unconsulted `all` default never trips it. Both twins
exit 2 and both write to stderr. The message body is identical
(`is contradictory with ... (these act on the reference-transaction hook
alone).`); the `.sh` prefixes `ERROR: ` and the `.ps1` does not, which matches
each twin's own convention for every other usage error it already had
(`.sh` 87/98/133/150, `.ps1` 96/417). I read that as parity, not drift.

Two things the gate does that the frozen plan did not name, both identical in
the twins and both argued in the comment: it refuses *any* explicit `--hooks`
including `all`, and it runs before the closed-set validation, so
`--decline-ref-guard --hooks bogus` reports the contradiction rather than the
unknown token. The argument holds — the decline and arm dispatch-and-exit
before the `--hooks` flow, so an explicit selection provably cannot do
anything.

### Amendment 5, sentence by sentence

Checked against the diff and against the artifacts each sentence cites.

| Claim | Verdict |
|---|---|
| "Amendment 3's ordering claim was true of one twin only, and this corrects it." | Accurate. Amendment 3's paragraph 2 is unqualified; the `.sh` had the fix, the `.ps1` did not. |
| "Code review reproduced the consequence under pwsh against an unwritable config: the hook gone, the configuration still saying `armed`, a non-zero exit." | Accurate — that is round 1's measured result verbatim. |
| "Three validation rounds missed it because each exercised the twin behaviourally for a different property and took the ordering on the record's word." | Accurate and specific. Round 1 §5e ran the real `.ps1` decline (against a *writable* config, so the order was invisible); round 2 ran it on real fixtures for the cross-twin grammar; round 3 for the widened replace gate. None mentions `Disable-RefGuard` ordering (`grep` over all three: zero hits). This is an honest admission of the right failure, not a soft one. |
| "TEST-642, whose static half catches the regression on a host with no pwsh and whose behavioural half reproduces the reviewer's case where pwsh exists." | Accurate — both halves present, `log_info` skip when pwsh is absent. |
| "`docs-audit --check` returns 0 before a decline ... and 1 after." | Accurate as round 1's measurement. Re-measured at HEAD the mode flip still occurs (report-only -> enforced); my HEAD fixture's orphans were all legacy-soft so its rc stayed 0, which does not contradict round 1's fixture. |
| "Both twins now seed the file from the shipped template — the same object the sync path would create — and print the sync path's own disclosure." | Accurate and stronger than "similar": byte-identical, verified. |
| "with an equivalent note when the template is absent" | Accurate; "equivalent" is the right word — the note names the same consequence, and does not claim to be the same line. |
| "A decline or arm combined with an EXPLICIT hooks selection now exits 2 ... (a bare decline is unaffected)." | Accurate, measured above. |
| "The plan's `-Print` for the PowerShell twin is NOT delivered and is recorded here as dropped: the twin never had `--print`, so this is a pre-existing gap rather than a regression, and emitting a heredoc body from PowerShell is feature work of its own." | **Honest, not reframed.** It says "NOT delivered" and "recorded here as dropped" in the same sentence before it mitigates, and the mitigation is checkable: `git show main:.aai/scripts/install-pre-commit-hook.ps1 \| grep -i Print` is empty, so "pre-existing gap" is true. The frozen plan does name it (spec:368). This is a disclosure, not an out-of-scope reclassification. |
| "The remaining AC-table rows still read `planned`; that flip is owed at the close and is carved by canon, not an omission." | Accurate. |
| "Two structural findings filed rather than fixed" (`fu-installer-flag-lattice-no-mode`, `fu-docs-audit-yaml-misnamed-guard-config`) | Both exist in `docs/ai/decisions.jsonl:1210,1211` with the reviewer's reasoning carried across, including the measured `--uninstall --decline-ref-guard` case. Verified by reading the ledger, not the amendment. |

One omission worth naming: Amendment 5 does not mention that Residual risks
bullet 1 (spec:485-492) has been false since Amendment 3. That is a round-1
miss of mine, not a round-2 regression — see D-5 and the registry list.

### Round 1's NON-BLOCKING list — what this remediation closed

| # (round 1 H6) | Status after `3c4d049f..24ebfe0e` |
|---|---|
| 1 Flag lattice / silently-ignored combos, incl. frozen D-1 | **Partly closed and fully discharged.** D-1 implemented (TEST-645/646); the rest filed as `fu-installer-flag-lattice-no-mode` (P2) with the measurement intact. Nothing left to hand back. |
| 2 `WANT_REFGUARD` overloaded | Open — `.sh:137,147,148,758` unchanged. |
| 3 Mutation-anchor code/comments undisclosed | Open — `write_mode="replace_or_append_key"` still at `.sh:420` with no comment. |
| 4 Doctor `DECLINED` absent from the stated vocabulary | Open — `aai-doctor.mjs:49` and `SKILL_DOCTOR.prompt.md:27` still say `PASS\|WARN\|FAIL\|SKIP`. |
| 5 `--help` / `.DESCRIPTION` "BOTH hooks" untrue | Open — `.sh:43`, `.ps1:15`. |
| 6 SKILL_UPDATE step 4 reports both hooks after a decline | Open — `SKILL_UPDATE.prompt.md` step 4 still says "report one line naming both hooks". |
| 7 `.ps1` decline refusal advises `-Force`, dead explanation line | Open, re-measured: `-DeclineRefGuard` over a foreign hook -> rc=1, "Pass -Force to overwrite"; `-DeclineRefGuard -Force` -> rc=1 again, hook untouched; the clarifying `Write-Host` never prints. |
| 8 TEST-618 positional pattern extraction | Open — `test-aai-hygiene-pack.sh:4468` still takes the first `grep -Eq` mentioning `ref_guard:`. |
| 9 No CHANGELOG entry | Open — `CHANGELOG.md` has only the bare `## [unreleased]` scaffold. Its round-1 disposition was "at the PR commit", so it is an obligation rather than a defect until then. |
| 10 D-2 / D-4 | D-2 **closed** by Amendment 5. D-4 open, owed at the close flip. |

### Registry items to file verbatim

| id | severity | what | why |
|---|---|---|---|
| `fu-installer-want-refguard-overloaded` | P3 | `WANT_REFGUARD`/`$wantRefGuard` is the hook SELECTION variable until `.sh:758` and "was actually installed" after it. | Any new consumer of the selection placed on the wrong side of line 758 silently reads the other meaning; the attestation at :775 is correct only by placement. |
| `fu-mutation-anchors-undisclosed` | P3 | `local write_mode="replace_or_append_key"` (`.sh:420`) is a provably-constant variable, and nine `# AC-0N ...` trailing comments are `--sed` mutation targets, none of them saying so. | A maintainer simplifies the constant or drops an "obvious" comment, the suite stays green, and the break surfaces only at the next `mutation-run --replay` as a stale record with no explanation. `aai-release.sh:528` shows the right shape. |
| `fu-doctor-declined-vocab-undeclared` | P3 | CAT-17's new `DECLINED` status is absent from `aai-doctor.mjs:49`'s header contract, from the `--strict` sentence at :56-58, and from `SKILL_DOCTOR.prompt.md:27`. | A `--json` consumer or the doctor skill meets a status value with no mapping rule; the skill's relay table has no branch for it. |
| `fu-installer-help-both-hooks-untrue` | P3 | `--help` (`.sh:43`) and `.DESCRIPTION` (`.ps1:15`) still say the foreign-hook check covers "BOTH hooks before writing either"; Spec-AC-02 deliberately scoped it to the SELECTED set. | An operator reads `--help`, runs `--hooks index` over a repo with a foreign reference-transaction hook, and expects a refusal that correctly does not come. Note TEST-614 greps `--help`. |
| `fu-skill-update-step4-both-hooks` | P3 | SKILL_UPDATE step 4's success line has the agent report both hooks installed; after Amendment 3 a plain install honours a declared decline and installs one. | The prompt this ride rewrote for honesty overstates the one case this ride added. Moving prompt bytes needs a diet-ledger true-up and a TEST-012 bump. |
| `fu-ps1-decline-force-advice-wrong` | P3 | `Disable-RefGuard`'s foreign refusal reuses `Show-ForeignReftxRefusal` ("Pass -Force to overwrite"), but the decline ignores `-Force`, and the clarifying `Write-Host` at `.ps1:372` is unreachable under `'Stop'`. | Re-measured at HEAD: both `-DeclineRefGuard` and `-DeclineRefGuard -Force` exit 1 with the same advice; the operator is told to pass a flag that provably changes nothing and never sees the real rule. |
| `fu-test618-positional-pattern` | P3 | TEST-618 extracts the shell mirror's pattern as the FIRST `grep -Eq` line mentioning `ref_guard` in the installer; two such lines now exist with different grammars (`.sh:322` reader mirror, `.sh:425` writer gate). | A pure refactor reordering the two functions re-points the conformance test at the writer's gate, and the drift message then names the wrong reader. Anchor on a marker comment (~2 lines). |
| `fu-refguard-changelog-entry-missing` | P2 | No `## [unreleased]` entry for a consumer-visible change to the installer `/aai-update` runs, to CAT-17's output vocabulary, and to a committed config file's schema. | The three comparable sweeps on main each shipped one; a consumer who sees a new `ref_guard:` line and a CAT-17 status finds nothing to read. Due at the PR commit. |
| `fu-bare-config-satisfies-lane-gate` | P3 | The template-absent fallback creates a one-key `docs/ai/docs-audit.yaml`, which satisfies `lane-gate.mjs:340-345`'s existence probe while `select-suites.mjs:171-178` reads zero `protected_paths_l3` from it; the NOTE discloses only the docs-audit consequence. | A repo pinned to the heavy lane by `protected_config_missing` can take the fast lane with an empty L3 surface. Measured reachability: only when `.aai/templates/docs-audit.template.yaml` is absent, and that template is in PROFILES `core` (line 226) and vendors with this installer — no sync path reaches it. Cheapest fix is one extra clause in the NOTE. |
| `fu-ps1-setcontent-rewrites-seed-eol` | P3 | `.ps1:340`'s `Set-Content` rewrites every line of the template it just seeded with the platform newline, so on Windows a 73-line LF template is committed as CRLF where `aai-sync.ps1`'s `Copy-Item` would leave it LF. | The twins produce byte-identical files on POSIX (measured) but diverge on Windows; the first decline commits a whole-file line-ending change instead of one added key. Readers are CRLF-tolerant (TEST-634), so this is diff noise, not behaviour. Not measured on Windows. |
| `fu-spec-residual-risk-1-superseded` | P2 | Residual risks bullet 1 (spec:485-492) states that a no-flag re-install re-arms a declined guard; Amendment 3 reversed that and TEST-636 pins the reversal. | The frozen body, read alone, is false about the shipped product. One "superseded by Amendment 3" marker on the bullet closes it. Also the place to land the docs-audit mode flip and the downgrade re-arm as stated residuals. |
| `fu-ps1-enable-refguard-no-rationale` | P3 | `Enable-RefGuard` (`.ps1:389-408`) installs the hook before recording `armed` with no counterpart of the `.sh`'s D4 rationale comment (`.sh:471-477`). | A maintainer applying B1's lesson twin-wide "fixes" the arm order too and breaks the property the `.sh` deliberately relies on. Comment-only. |
| `fu-uninstall-refguard-leaves-armed` | P3 | `--uninstall --hooks ref-guard` removes the guard and writes no record; the config keeps saying `armed`. Measured: rc=0, hook ABSENT, `ref_guard: armed`. | The decline and the uninstall now disagree about whether removing the guard is worth recording. Safe direction under D4 and operator-initiated, but it is the same end-state shape B1 was about, reached by another flag. Belongs with `fu-installer-flag-lattice-no-mode`. |

### On the sweep attestation at `b511d033`

**Accepted for this HEAD.** The post-sweep delta is `b511d033..24ebfe0e` = 4
files, none of them code: the spec, `docs/INDEX.md`, one `decisions.jsonl`
line and one `test-runs.jsonl` line. I did not take that on the record's word —
I re-ran, at `24ebfe0e`, everything that delta could reach:

```
spec-lint.mjs                                          LINT PASS, 0 findings, rc=0
contractHash(spec) vs frontmatter frozen_sha256        bd8baf7c... == bd8baf7c...
mutation-run.mjs --replay --spec <this spec>           39/39 records still redden, 0 inconclusive
  (including TEST-642/643/644/645/646)
docs-audit.mjs --check                                 Verdict: CLEAN, rc=0
tests/skills/test-aai-git-ref-guard.sh                 All tests passed (TEST-642..646 green), rc=0
tests/skills/test-aai-follow-ups.sh                    one FAIL: TEST-029, misses = exactly this
                                                       ride's six own fu- ids vs a 3-entry allowlist
```

TEST-029's miss set is the attested red and the attested cause — six registry
ids this scope closes at the close ceremony, not a broken closure claim. The
`decisions.jsonl` line added after the sweep is one of those ids, so it can only
have lengthened that same miss list, not created a new class of failure.

### Would I merge this now

Yes — nothing in the code or the record blocks it. Both round-1 BLOCKING
findings are closed with reproductions rather than assertions, the amendment
that records them is accurate sentence by sentence including the part that
admits a miss, and the twins now agree behaviourally where round 1 measured
them apart. What remains is close-ceremony work — the `## [unreleased]` entry
in the PR commit (`fu-refguard-changelog-entry-missing`), the 11 Evidence cells
and the AC/Test-Plan status flips (D-4) — plus the registry list above, which
is observation-grade by this round's own standard.

### STATE update (dispatched reviewer — returned, not executed)

state_update_commands:

```bash
node .aai/scripts/state.mjs set-code-review \
  --required true --status pass \
  --scope "git diff 3c4d049f..24ebfe0e (round 2, bounded remediation re-review)" --base-ref main \
  --report docs/ai/reviews/review-update-installs-ref-guard-undisclosed-20260924T124304Z.md \
  --notes "Round 2: spec_compliance pass, code_quality pass. B1 closed (round-1 repro re-run under pwsh 7.6.3: guard PRESENT, cfg still armed, rc=1, honest error). B2 closed (disclosure on stdout in both twins; seeded file byte-identical to cp -a template + key and identical across twins; fallback NOTE identical). D-1 implemented in both twins, bare decline unaffected. Amendment 5 accurate sentence by sentence; -Print recorded as dropped, not reframed. 13 registry items handed back; new D-5: frozen Residual risks bullet 1 superseded by Amendment 3 (a round-1 miss). Sweep attestation at b511d033 accepted after re-running spec-lint, contract hash, mutation replay 39/39 RED, docs-audit CLEAN and test-aai-git-ref-guard.sh at 24ebfe0e."
```
