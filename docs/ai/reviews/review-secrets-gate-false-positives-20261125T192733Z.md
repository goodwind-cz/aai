# Code review: secrets-gate-false-positives (round 4 tree)

```yaml
review:
  scope: "git diff origin/main of the working tree of fix/secrets-gate-false-positives (86468e12 + merge f2a55bf4 + uncommitted round-4 edits)"
  spec: docs/specs/SPEC-0316-spec-secrets-gate-false-positives.md (frozen + Amendments A1, A2, A3)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "pre-commit-checks.sh:248-265,300-309 (has_space, is_wordlike, cred); TEST-4080, TEST-4081 green, replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "pre-commit-checks.sh:266-272 is_reference; TEST-4082" }
      - { ac: Spec-AC-03, call: compliant, citation: "pre-commit-checks.sh:273-291 is_placeholder, is_url; TEST-4083, TEST-4084" }
      - { ac: Spec-AC-04, call: compliant, citation: "pre-commit-checks.sh:665-702 name hit selects rules; TEST-4085" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:691-720 key-file/NUL block; TEST-4086" }
      - { ac: Spec-AC-06, call: compliant, citation: "pre-commit-checks.sh:399-433 aws/ghc/ghf, 434-474 pk; TEST-4087..4090" }
      - { ac: Spec-AC-07, call: compliant, citation: "pre-commit-checks.sh:326-378 r1/r2/r3; TEST-4091, TEST-4092" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-4093 (old regex + R4 oracle subset)" }
      - { ac: Spec-AC-09, call: compliant, citation: "pre-commit-checks.sh:704-711,747-748,799; TEST-4094" }
      - { ac: Spec-AC-10, call: compliant, citation: "pre-commit-checks.sh:315-325,755-797; TEST-4095; reviewer recomputed 5 fingerprints with the D-FP printf|hash-object command and they equal the gate's output" }
      - { ac: Spec-AC-11, call: compliant, citation: "pre-commit-checks.sh:536-557,598-650; TEST-4096" }
      - { ac: Spec-AC-12, call: compliant, citation: "pre-commit-checks.sh:573-593 (staged blob, else rev-parse --verify + cat-file blob, staged_read_fail 'secrets allowlist'); TEST-4097" }
      - { ac: Spec-AC-13, call: compliant, citation: "pre-commit-checks.sh:756-761 single hash-object behind pcc_nfind; TEST-4098" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-4099 installed-hook seam" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-4100; reviewer re-ran the gate over all 2272 tracked+modified worktree files: 25 allowed, 0 blocking; without the allowlist all 9 entries used; this suite file needs none" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-4101 (anchors, no interval/gawk-only, node shim); BWK awk on host, mawk by validator container; gawk leg = cannot_verify (hosted run)" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-4102 + validator full sweep 144/145 rc 0; reviewer suite run below" }
      - { ac: Spec-AC-18, call: compliant, citation: ".aai/system/DOCS_AI_CANON.list:57; TEST-4103" }
      - { ac: Spec-AC-19, call: compliant, citation: "CHANGELOG.md:33 exact D-DOCS heading once; product doc; USER_GUIDE.md:2427; intake user_visible: true; spec-amend list --strict rc 0 (3 D-AMEND + 4 own-spec records, all tracked)" }
      - { ac: Spec-AC-20, call: compliant, citation: "pre-commit-checks.sh:728-739 NUL->newline copy; TEST-4105" }
      - { ac: Spec-AC-21, call: compliant, citation: "R5 folded into R6 per A2 (pcc_anykey, pcc_anydata); TEST-4106" }
      - { ac: Spec-AC-22, call: compliant, citation: "pre-commit-checks.sh:603-637 literal-less glob -> '*'; TEST-4107" }
      - { ac: Spec-AC-23, call: compliant, citation: "pre-commit-checks.sh:445-474,516-530 pkscan + pending lookahead; TEST-4108" }
      - { ac: Spec-AC-24, call: compliant, citation: "pre-commit-checks.sh:475-505 r6, 395-398 r7, 679-689 data/config classification; TEST-4109" }
      - { ac: Spec-AC-25, call: compliant, citation: "pre-commit-checks.sh:610-628 bracket-expression walk; TEST-4110" }
      - { ac: Spec-AC-26, call: compliant, citation: "pre-commit-checks.sh:292-299,305 kwkey/is_label/cred kw; TEST-4111, TEST-4112" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 293,
          issue: "NB-2 (P2): kwkey does not treat a key holding the token PASS / PASSPHRASE (DB_PASS, SMTP_PASS, REDIS_PASS, GPG_PASSPHRASE) as naming a secret, so a letters-only value under it is exempt as word-like",
          failure_scenario: "a real .env staged with DB_PASS=sunshinesunny (or GPG_PASSPHRASE=correcthorsebattery) exits 0; origin/main blocked every .env by name; DB_PASSWORD=sunshinesunny in the same file blocks (repro below)" }
      - { rank: NON-BLOCKING, file: docs/ai/secrets-allowlist.txt, line: 13,
          issue: "NB-1 (P3): three whole-file path entries (.aai/scripts/secrets-preflight.mjs, docs/specs/SPEC-0045-*, tests/skills/test-aai-secrets-preflight.sh) exempt every future finding in those files, R4 tokens and private keys included, where 5 reviewed lines are the only findings",
          failure_scenario: "a later commit that pastes a real ghp_ token or a credential-shaped password into tests/skills/test-aai-secrets-preflight.sh or secrets-preflight.mjs commits with only the 'N finding(s) allowed' line" }
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 725,
          issue: "NB-3 (P3, pre-existing on origin/main): the grep prefilter runs in the user's locale, not LC_ALL=C; macOS BSD grep 2.6.0 under a UTF-8 locale counts 0 for a line holding invalid UTF-8, so a file whose only keyword lines hold Latin-1 bytes skips awk entirely",
          failure_scenario: "src/a.js holding the single line '\\xff\\xfe junk api_key = \"Zq8vW2nP4kXy\"' exits 0 under LANG=en_US.UTF-8 (origin/main also exits 0); with LC_ALL=C grep it blocks" }
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 635,
          issue: "NB-4 (P3): the two probe paths contain no c, n or v, so a one-letter glob such as '*v*', '*n*' or '*c*' is accepted although it covers nearly every path ('*v*' covers every .env)",
          failure_scenario: "allowlist 'path *v*' plus a staged .env with DB_PASSWORD=<credential> exits without a finding for .env (counted only in the allowed line); the near-catch-all class is disclosed as '*.json', but a one-letter glob is broader than that example suggests" }
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 477,
          issue: "NB-5 (P3, carried from validation round-3 NB-3): r6 re-copies the rest of the line with substr per pair, quadratic on a one-line name-hit data file",
          failure_scenario: "config/secrets.json minified on one line: 0.2 MB takes 1 s, 0.8 MB takes 10 s on this host (4x size, 10x time); a multi-MB file stalls the hook for minutes" }
      - { rank: NON-BLOCKING, file: docs/product/pre-commit-secrets-gate.md, line: 70,
          issue: "NB-6 (P3): docs say name-hit / real-dotenv pairs are 'judged by the value alone, whatever the key is called' and that 'a plain word' passes; under A3 the key decides whether a plain word blocks (CHANGELOG.md:40 and USER_GUIDE.md:2427 say the same)",
          failure_scenario: "a reader of the product doc expects DB_PASSWORD=sunshinesunny to pass as a plain word (it blocks) and DB_PASS=sunshinesunny to 'block like PASSWORD does' (it passes)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/pre-commit-checks.sh, line: 267,
          issue: "NB-7 (P3): is_reference exempts every value that begins with $, so a human password or a bcrypt hash that starts with $ is never a finding (D-VALUE c by design; not named in Residual risks)",
          failure_scenario: "src/c.js with password: \"$uperS3cret9\" exits 0; origin/main blocked it" }
  cannot_verify:
    - { claim: "Spec-AC-16 byte-identical output under gawk (and nawk) and on Windows Git Bash", closes_with: "the hosted skill-suite run on the PR head (Linux gawk/mawk); no hosted Windows leg runs this suite" }
    - { claim: "Real downstream corpora (GitHub #585 i18n repo, #576 .env.example repo) now commit without --no-verify", closes_with: "a scratch aai-sync install into the reporters' repo shapes, or the reporters' confirmation after release" }
    - { claim: "Hook wall-clock cost on large staged sets in downstream projects (NB-5 is a lower bound measured on one host)", closes_with: "timing on a representative downstream commit with large name-hit data files" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Scope: `git diff origin/main` of the working tree at
  /Users/ales/Projects/aai-worktrees/secrets-gate-false-positives (branch
  fix/secrets-gate-false-positives, HEAD f2a55bf4 = 86468e12 + merge of
  origin/main 01cd7f78, plus the uncommitted round-4 edits). STATE
  `worktree.user_decision: worktree`; 13 files, +2537/-32.
- Spec: docs/specs/SPEC-0316-spec-secrets-gate-false-positives.md, frozen, plus
  Amendments A1, A2, A3 (A3 governs where they differ).
- Process notes (anti-gaming contract):
  - The dispatch prompt named two expected findings (NB-1 whole-file allowlist
    entries, NB-2 kwkey coverage) and asked for their severity. That is
    pre-characterisation of findings. It is recorded here; the full scope was
    reviewed anyway, and five further findings (NB-3 to NB-7) came from that.
  - The dispatch cited the prompt hash 8e6aae0d…; the sha256 of
    .aai/SKILL_CODE_REVIEW.prompt.md in this worktree (identical to the main
    checkout) is 20eb1d6b1a1b478faec3508eedbc10e12bcaa4f270ff95130808a041eb26ca30.
    The prompt followed is the file on disk.

## Spec compliance (AC walk)

All 26 Spec-AC rows are compliant (YAML block above). Evidence used:
the claimed TEST-4080..TEST-4112 functions each exist once and are called
once from `main`; the validation round-4 report records suite PASS, mutation
replay 33/33 RED, mutation-gate PASS 33, spec-amend --strict rc 0 and the
full sweep 144/145 rc 0; the reviewer re-ran the pre-commit suite (result
below), `spec-amend list --strict` (rc 0) and its own probes.

Deviations from the frozen spec, all disclosed or harmless:

- D-FP is implemented as `git hash-object --no-filters --stdin-paths` over
  scratch files holding `<path>\n<trimmed line>`, not the literal
  `printf | git hash-object --stdin`. The reviewer recomputed the five
  fingerprints of NB-1 with the D-FP command; all five match the gate.
- `PRIVATE KEY` occurs once through the `pkpos` helper (A2 states it).
- The AC Status table still says `planned` with Evidence `—` on every row
  while the Test Plan says `green` (INFO; the close ceremony owns it).
- Docs wording inconsistent with A3 (NB-6).

## Code quality findings

No BLOCKING finding. Security properties checked and holding:

- Fail closed: both awk programs end with a `done` sentinel and a missing
  sentinel (awk absent, killed, write failure) is `staged_read_fail`; tr/wc,
  cat-file of the allowlist and hash-object failures block; the fingerprint
  count is cross-checked against the finding count; `grep -c` output is
  validated as a number.
- No value printed: output carries only path, line number and fingerprint;
  an unrecognised allowlist line is not echoed (only an accepted-shape glob
  is, in the catch-all error). TEST-4095 asserts no fixture value in stdout or
  stderr.
- Portability: no interval expression, no gawk-only builtin, no apostrophe in
  the awk text; `LC_ALL=C` on both awk calls and on `tr`; checked here under
  bash 3.2.57 and BWK awk 20200816 (multi-finding run, cap at 3, allowed
  count, key file, all correct).
- No pipe added to the script (TEST-3455 ratchet), no builtin redirection
  (TEST-3920); the tests use no `| head` or `grep -q` pipe under pipefail
  that could SIGPIPE.
- Allowlist: read from the index only; staged deletion means none; catch-all
  rejection works for every listed form; malformed lines block whenever a file
  is judged.

### NB-2 (P2) — keys holding PASS / PASSPHRASE do not name a secret

Repro (scratch repo, working-tree script): `.env` with
`DB_PASS=sunshinesunny` → rc 0; `SMTP_PASS=sunshinesunny` +
`GPG_PASSPHRASE=correcthorsebattery` → rc 0; `DB_PASSWORD=sunshinesunny` →
rc 1. Outside name hits origin/main never matched these keys (no regression
there); inside a real `.env` origin/main blocked by name. Spec-compliant (A3's
list is explicit and A3 residual 2 discloses letters-only values under a
non-secret key), which is why this is NON-BLOCKING; but `pass` is the most
common abbreviation of a key that names a secret and a letters-only dev
password is a common real value.

Exact fix (one line, in place, line 293; line count and numstat unchanged so
TEST-3454/TEST-3461 pins hold; no apostrophe, no interval expression; verified
under BWK awk):

```
  return (tolower(k) ~ /password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key/ || ("_" tolower(k)) ~ /[^a-z]pass(phrase)?[^a-z]/)
```

It matches `DB_PASS=`, `export SMTP_PASS=`, `GPG_PASSPHRASE:`, `PASS=`,
`"db_pass":`, `my-pass:` and not `BYPASS_CACHE=`, `COMPASS_URL=`,
`passthrough=` or camelCase `dbPass:`. With it: `DB_PASS=sunshinesunny` and
`GPG_PASSPHRASE=correcthorsebattery` block, `BYPASS_CACHE=disabled`,
`NODE_ENV=production`, `LOG_LEVEL=debug` and `smtp_pass: Heslo` pass, and the
full self-corpus run stays at 25 allowed / 0 blocking. It changes the script
sha (33 mutation records re-run) and the A3 key list (needs an A4 record,
`spec-amend.mjs add --class contract --signoff none`); add `DB_PASS=<letters>`
and `GPG_PASSPHRASE=<letters>` to TEST-4111 and `BYPASS_CACHE=disabled` to
TEST-4112.

Recommended disposition: (a) remediate in tree with an A4 amendment if any
further script change is made this ride; otherwise (b) follow-up
`fu-sg-kwkey-pass-suffix`, P2.

### NB-1 (P3) — whole-file allowlist entries where fingerprints suffice

The three round-4 `path` entries cover exactly 5 findings. Replacement lines
for docs/ai/secrets-allowlist.txt (replace the three `path` lines after the
"Prose and fixtures naming the secrets-preflight script" comment):

```
fingerprint 50e642b3ff2601a867d0e049fe81745e9729ef47
fingerprint bbb40928d70977b6326d29f47b66e27163e9b542
fingerprint ecfdaeba7011c95ae08bbe568a6861c40d5d0f00
fingerprint cb75db3fd32591ab08759fbcbcfc9ea35567011e
fingerprint 980231beb9a2ad1490d75192a6aa614cc297e29a
```

(.aai/scripts/secrets-preflight.mjs lines 67 and 340,
docs/specs/SPEC-0045-spec-intake-secrets-preflight.md line 98,
tests/skills/test-aai-secrets-preflight.sh lines 233 and 479.) Each was
printed by the gate and recomputed with the D-FP command. A full-corpus run
with this allowlist (and with the NB-2 line) gives 25 allowed, 0 blocking.
TEST-4100 checks a fingerprint entry against the printed fingerprints; each
file has at most 2 findings, so all print (the cap is 3). No script change,
so no mutation re-run. Recommended disposition: (a) remediate in tree.

### NB-3 (P3) — prefilter grep not under LC_ALL=C

Pre-existing on origin/main (same grep, same locale). Exact fix, line 725:
`hits=$(LC_ALL=C grep -cEi "$pcc_pre" < "$blob" || true)`. Verified: the
Latin-1 repro blocks, the Czech UTF-8 label fixture still passes, line count
unchanged. Recommended disposition: fold into the NB-2 script change if made;
otherwise (b) follow-up `fu-sg-prefilter-lc-all-c`, P3.

### NB-4 (P3) — one-letter near-catch-all globs accepted

Repro: `path *v*` allows the `.env` finding; `*n*` allows `.env` and
`config/secrets.yml`; `*c*` allows `config/secrets.yml` and `src/app.js`… (all
counted in the allowed line, so not silent). Within D-ALLOW as written.
Recommended disposition: (b) follow-up `fu-sg-allowlist-near-catch-all`, P3
(for example, reject a glob whose literal part is shorter than 3 characters,
or add probes made of the other letters).

### NB-5 (P3) — R6 quadratic scan on one-line name-hit files

Measured above. Recommended disposition: (b) follow-up
`fu-sg-r6-linear-scan`, P3 (already carried by validation as round-3 NB-3;
reuse that ref if one exists).

### NB-6 (P3) — docs wording vs A3

Exact text changes (no test greps these phrases; TEST-4104's anchors are
untouched):

- docs/product/pre-commit-secrets-gate.md lines 70-71: `pair is judged by the
  value alone, whatever` / `the key is called.` → `pair is judged whatever the
  key is called (a plain word blocks only under a key that names a secret,
  as above).`
- same file lines 77-78: `a plain word, a URL` → `a plain word under a key
  that names no secret, a URL`.
- same file lines 82-85: `is judged by the value alone, whatever the key is`
  → `is judged whatever the key is`, and after `block like `PASSWORD` does.`
  add `A plain word blocks there only under a key that names a secret.`
- CHANGELOG.md line 40: `placeholders, plain words, URLs and empty values
  pass` → `placeholders, plain words under a key that names no secret, URLs
  and empty values pass`.
- docs/USER_GUIDE.md line 2427: `placeholders, plain words, labels with
  blanks` → `placeholders, plain words under a key that names no secret,
  labels with blanks`.

Recommended disposition: (a) remediate in tree (docs only).

### NB-7 (P3) — a value starting with $ is always a reference

By design (D-VALUE c); the product doc states the `$` rule, so no false
record. A real `$`-leading password cannot be told from `$VAR` by shape.
Recommended disposition: (d) accepted residual.

accepted residual: NB-7 — a value that begins with `$` is read as a variable reference (D-VALUE c, documented in the product doc); a `$`-leading literal password is indistinguishable from `$VAR` by shape, P3, no observed bite in this repository.

## cannot_verify

See the YAML block: gawk / Windows Git Bash leg of Spec-AC-16, real
downstream corpora of #585/#576, downstream hook wall-clock cost.

## Reviewer test run

`env -u AAI_ROLE bash tests/skills/test-aai-pre-commit-checks.sh` on the
round-4 working tree: rc 0, 81 PASS lines, 0 FAIL ("All
aai-pre-commit-checks tests passed"). `git status --porcelain` was the same
before and after, apart from this report. Reviewer probes ran in scratch repos
under the session scratchpad: a full-corpus run (2272 files) with and without
the allowlist, the NB-1 and NB-2 variants, bash 3.2.57 + BWK awk 20200816, and
the origin/main script as the oracle for regressions.

## Next steps

1. Orchestrator records a disposition per NB (NB-1 and NB-6 remediate in
   tree; NB-2 remediate with A4 or follow-up; NB-3, NB-4, NB-5 follow-ups;
   NB-7 accepted residual above).
2. Any edit to pre-commit-checks.sh (NB-2, NB-3) re-runs the 33 mutation
   records, the pre-commit suite and the targeted suites before PR.
3. Hosted run on the PR head closes the gawk leg.
