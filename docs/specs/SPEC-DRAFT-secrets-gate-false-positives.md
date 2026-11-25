---
id: spec-secrets-gate-false-positives
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 1e07ee61eb08a6caa120a51e76150177c841215d5b467a4fac6cfb0765206bbb
ceremony_level: 3
links:
  requirement: secrets-gate-false-positives
  rfc: null
  pr: []
  commits: []
---

# Pre-commit secrets gate: judge values, not file names, with a reviewed allowlist

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-secrets-gate-false-positives.md
  (GitHub #585 and #576; the pull request closes both).
- Prior scopes whose tests this one changes (closed specs, see D-AMEND):
  docs/specs/SPEC-0298-spec-pr-ceremony-friction-fixes.md (TEST-3833),
  docs/specs/SPEC-0300-spec-hook-gate-staged-content.md (TEST-3865,
  TEST-3866), docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md
  (TEST-3876). Moved pins (D-PINS): TEST-3454 and TEST-3461 of
  docs/specs/SPEC-0279-spec-pre-commit-checks-ps1-retire.md.
- Kept-native row: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md
  (`pre-commit-checks` stays bash; "the .sh checks 1 to 7 run without Node"
  stays true, D-PORT).
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites, Node stdlib
  only, no new dependencies).

## Implementation strategy

- Strategy: tdd
- Rationale: this loosens a security gate on an L3 protected surface. Every
  relaxation must be observed failing before it lands (the false-positive
  fixtures exit 1 on the unchanged tree), and every true-positive fixture
  must be proven to bite through a named mutation of the new code. The
  mutation gate (frontmatter `mutation_gate: v1`, stamped at freeze) binds
  each Test Plan row to one mutation of a D-ANCHORS string.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 protected surface (.aai/scripts/pre-commit-checks.sh)
  and the main checkout carries another session's uncommitted files.
- User decision: worktree (owner directed an own worktree for this ride)
- Base ref: origin/main at a83f7b0f
- Worktree branch/path: fix/secrets-gate-false-positives at
  /Users/ales/Projects/aai-worktrees/secrets-gate-false-positives
- Review required: true
- Review scope: origin/main...HEAD of fix/secrets-gate-false-positives.
- Merge: the owner merges (L3); the orchestrator opens the pull request only.

## Measured baseline (Planning, 2026-11-25)

- Notation: a fixture written `key ⇒ value` below stands for that key and
  value in the file format's own syntax (`key: "value"` in YAML or JS,
  `key=value` in dotenv or shell, `"key": "value"` in JSON). The notation
  keeps this spec, a name-hit path, clean under the old and the new gate.
- The old content regex matches `forgotPassword ⇒ "Forgot your password?"`
  in YAML or JS and `password ⇒ "${DB_PASSWORD}"` in shell, and does NOT match
  the JSON form `"forgotPassword": "Forgot your password?"` (the closing
  quote of the key sits between the keyword and the colon). Intake step 1
  therefore reproduces with a YAML or JS locale file, not a JSON one; the
  fixtures below use both forms.
- `git grep` of the old content regex over this repository's 2263 tracked
  files: 0 hits. Paths the old name check would block: 8 (the
  secrets-preflight files). Strings that the new R4 token rule matches:
  `AKIAABCDEFGHIJKLMNOP` in tests/skills/test-aai-feedback-upsert.sh,
  tests/skills/test-aai-friction.sh and
  docs/specs/SPEC-0203-spec-friction-issues-arrive-without-a-description.md
  (this repository's own allowlist covers them, D-SELF).

## Decisions

### D-NAME: a name hit selects the rules, it no longer blocks by itself

A name hit is the predicate CHECK 2 uses today, unchanged: the staged path
contains `.env`, `credentials` or `secret`; a path under docs/ai/reports,
docs/ai/tdd, docs/ai/validation or docs/ai/reviews is not a name hit unless
its basename is `.env`, `.env.*` or `*.env`. The name check no longer
reports `Sensitive file staged` for every name hit. A name-hit file is
content-scanned with the extended rules R2 and R3 (D-RULES) on top of the
rules every file gets. Two kinds of name hit keep the name block
(D-KEYFILE).

### D-KEYFILE: key files and binary blobs keep the name block

A name-hit file still reports `Sensitive file staged: <path>` and blocks,
whatever its content, when its basename ends in `.key`, `.pem`, `.p12`,
`.pfx`, `.jks` or `.keystore`, or when its staged blob holds a NUL byte (a
blob the text rules cannot judge). A `path` allowlist entry can exempt it;
a fingerprint entry cannot (there is no line).

### D-RULES: what a finding is

A finding is one line of a staged blob. Rules R1 and R4 apply to every
staged file; R2 and R3 only to name-hit files.

- R1 keyed assignment (today's regex, narrowed by D-VALUE): one of the
  keywords `api[_-]?key`, `api[_-]?secret`, `password`, `passwd`,
  `secret[_-]?key`, `access[_-]?token`, `private[_-]?key`
  (case-insensitive) directly followed by optional blanks, `:` or `=`,
  optional blanks and a single or double quote; the value is the text after
  that quote up to the next same quote or the end of the line. A finding
  when the value is credential-shaped (D-VALUE).
- R2 name-hit keyed assignment: the key is the identifier
  (`[A-Za-z0-9_.-]+`, optionally quoted) directly before the separator and
  it contains, case-insensitively, one of the R1 keywords or `secret`,
  `token`, `access[_-]?key`; the value may be quoted or unquoted (an
  unquoted value runs to the first blank, a trailing CR dropped). This
  covers dotenv `DB_PASSWORD ⇒ value`, `export TOKEN ⇒ value`, JSON
  `password ⇒ value` and `STRIPE_SECRET_KEY ⇒ value`. A finding when the value is credential-shaped.
- R3 name-hit URL credentials: `<scheme>://<user>:<password>@` where the
  password part is credential-shaped (e.g.
  `DATABASE_URL ⇒ postgres://app:RANDOM@db:5432/app`).
- R4 tokens, key-independent: an AWS access key id (`AKIA` or `ASIA`
  followed by 16 characters of A-Z or 0-9, not inside a longer run of
  those characters); a GitHub token (`ghp_`, `gho_`, `ghu_`, `ghs_` or
  `ghr_` followed by 36 letters or digits; `github_pat_` followed by 22
  letters or digits, `_`, and 59 letters or digits); a private key block (a
  line `-----BEGIN PRIVATE KEY-----`, `-----BEGIN <words> PRIVATE KEY-----` or `-----BEGIN PGP PRIVATE KEY
  BLOCK-----` whose next non-empty line is either 40 or more characters of
  the base64 alphabet or begins `Proc-Type:`). A token that is a placeholder
  (D-VALUE d) is not a finding (the AWS documentation key ending in
  `EXAMPLE` passes).

- R5 real-dotenv keyed assignment (amendment A1, VALIDATION round 1 V2): in a
  real dotenv file (basename `.env`, `.env.<anything>` or `<name>.env`,
  excluding the template forms `.env.example`, `.env.sample`,
  `.env.template`, `.env.dist` and `.env.defaults`) every `KEY=value` line
  (optional `export`, key `[A-Za-z_][A-Za-z0-9_.-]*`, value quoted or
  unquoted as in R2) is a finding when the value is credential-shaped,
  whatever the key is called. D-VALUE still exempts empty, placeholder,
  reference, URL, short and blank-holding values; letters-only words stay
  exempt (N2) so `NODE_ENV=production` and `LOG_LEVEL=debug` commit. A
  template form keeps R2 and R3 only.

Outside name-hit files the new gate reports no line that neither the old
regex nor R4 matches (monotonicity, Spec-AC-08). Entropy is not used: an
entropy threshold misses short human passwords (a true positive) and needs
floating-point awk; the shape rules below are deterministic and testable.

### D-VALUE: credential-shaped

A value V (bytes, `LC_ALL=C`) is credential-shaped when all of:

- a) its length is at least `PCC_VALUE_MINLEN` (8);
- b) it holds no space and no tab (`has_space`);
- c) it is not a reference (`is_reference`): it begins with `$` (covers
  `$VAR`, `$(cmd)`, `$env:VAR`, `${{ secrets.X }}`), or contains `${`, or
  begins with `{{`, or begins and ends with `%`, or begins with
  `process.env.`, `import.meta.env.`, `os.environ`, `os.getenv(`,
  `System.getenv(`, `ENV[` or `env(`;
- d) it is not a placeholder (`is_placeholder`), case-insensitively: it
  begins with `<` and contains `>` (so `<your-api-key>` and a
  markdown-quoted `<random>` both count); or all its bytes are equal; or it
  contains `changeme`, `change_me`, `change-me`, `replaceme`, `replace_me`,
  `replace-me`, `placeholder`, `example`, `dummy`, `redacted` or `xxxx`; or
  it begins with `your_` or `your-`; or it ends with `_here` or `-here`;
- e) it is not word-like (`is_wordlike`): word-like means one or more runs
  of letters (A-Z, a-z, or any byte at or above 0x80) joined by single `-`,
  `'` or `.` characters, optionally ending in one `.`, `!`, `?` or `:`
  (`Passwort`, `Forgot-password`, `Přihlášení`);
- f) it is not a URL (`is_url`): it does not begin with
  `<letter><letters, digits, +, ., ->://` (a URL with `user:password@` is
  judged by R3 instead);
- g) it does not begin with `./`, `../` or `~/` (a relative path).

`abcdefgh1234` (TEST-3832's fixture) is credential-shaped and keeps
blocking.

### D-NUL: a blob with a NUL byte reaches awk without it (amendment A1, V1)

BWK awk cuts a record at its first NUL byte and mawk and gawk do not. For a
file that is not a name hit and whose staged blob holds a NUL byte (counted
by the existing `tr` and `wc` pair), awk reads a copy in the scratch
directory with each NUL replaced by a newline (`tr`, no pipe), so every awk
gives the same findings and a credential after a NUL on the same line is
found as on origin/main. A name-hit blob with a NUL is a D-KEYFILE block and
is not scanned.

### D-ALLOW: the allowlist file

- Path: `docs/ai/secrets-allowlist.txt`, project-owned, committed, never
  written, seeded or deleted by sync or update. Added to
  .aai/system/DOCS_AI_CANON.list so docs-audit does not report it.
- Read from the index only (D-READ). Missing or empty means no entries: the
  gate is the strict D-RULES behaviour and prints nothing extra.
- Format: UTF-8 text, LF or CRLF; leading and trailing blanks trimmed;
  blank lines and lines starting with `#` ignored. Two entry kinds, one per
  line:
  - `path <glob>`: the rest of the line is a bash pattern matched against
    the whole repo-relative staged path (`*` matches any string including
    `/`, so `**` means the same as `*`; `?` one character; `[...]` a class).
    Every finding (content or D-KEYFILE) in a matching file is allowed.
  - `fingerprint <hex>`: 40 or 64 lowercase hex digits (D-FP). The one
    finding with that fingerprint is allowed.
- Catch-all rejection: a `path` glob that matches either probe path
  `zz-aai-allowlist-probe` or `zz/aai/allowlist/probe.zz` is rejected
  (this covers `*`, `**`, `**/*`, `*.*`, `?*`, `[a-z]*`), and so is a glob
  with no literal character once its wildcards, slashes and bracket
  expressions are removed (amendment A1, N1: this covers the negated class
  `[!z]*`, `*[!z]` and `[!.]*`). A rejected glob,
  or any other line that is not a valid entry, prints an error and blocks
  the commit whenever CHECK 2 judges at least one staged file, whether or
  not any finding exists (loud, fail closed). The allowlist file is itself
  content-scanned like any other staged file.
- Allowed findings are counted and printed once (D-OUTPUT); they never pass
  silently.

### D-READ: the allowlist in effect is the index's

When the commit stages `docs/ai/secrets-allowlist.txt`, its staged blob
(already read by the batched read) is the allowlist; a staged deletion
means no allowlist. Otherwise one `git rev-parse -q --verify
":docs/ai/secrets-allowlist.txt"` resolves the index entry; when it
resolves, one `git cat-file blob <id>` reads it; when it does not resolve
(untracked or never added), there is no allowlist. An
untracked file or an unstaged working-tree edit therefore has no effect. A
resolved entry that cannot be read blocks through `staged_read_fail` with
the reason `secrets allowlist`. The batched read of TEST-3871 is not
changed: with no allowlist in the index there is still exactly one
`cat-file` invocation.

### D-FP: fingerprints

The fingerprint of a finding is the git blob id that
`printf '%s\n%s' "<path>" "<line>" | git hash-object --stdin` prints, where
`<path>` is the repo-relative staged path and `<line>` the finding line with
leading and trailing blanks and a trailing CR removed. It binds the
exemption to that file and that exact line text; editing the line or moving
the file needs a new review. All fingerprints of one CHECK 2 run come from
one `git hash-object` invocation, made only when there is at least one
content finding.

### D-OUTPUT: what CHECK 2 prints

- A file with content findings: `✗ Potential secret detected in <path>`
  (unchanged), then one line `    line <n>, fingerprint <hex>` per finding
  for the first 3 findings, then `    ... and <k> more` when there are more.
- A D-KEYFILE file: `✗ Sensitive file staged: <path>` (unchanged text).
- Allowed findings: one line `✓ Secrets allowlist: <n> finding(s) allowed
  by docs/ai/secrets-allowlist.txt`.
- Allowlist errors: `✗ Secrets allowlist line <n>: catch-all path glob
  '<glob>' rejected — commit blocked` and `✗ Secrets allowlist line <n>:
  unrecognised entry — commit blocked` (the line text is not echoed).
- The pass line `No secrets detected in staged files` is unchanged; a clean
  run prints exactly what it prints today.
- No value, token or line text of a finding is ever printed to stdout or
  stderr.

### D-PORT: bash, POSIX awk, no Node

The rules live in pre-commit-checks.sh as one awk program run under
`LC_ALL=C` (no new file under .aai/, so no PROFILES.yaml entry and no new
kept-native row). The awk program uses no interval expression (`{n}`,
`{n,m}`) and no gawk-only feature (`gensub`, `IGNORECASE`, `strtonum`,
`asort`, `PROCINFO`, `systime`), and gives identical output under BWK awk
(macOS), mawk and gawk (Git Bash). NUL detection uses external tools, not
awk. CHECK 2 starts no Node process. The existing guard lints of the
script stay clean WITHOUT any change to the lints themselves: TEST-3455
(pipe ratchet at 0), TEST-3920 (no builtin, function or compound-command
redirection, tools looked up in a subshell), TEST-4047 (seterr lint) and
check-cd-subshell-leak.

### D-ANCHORS: strings the mutations target

Each of these strings occurs exactly once in .aai/scripts/pre-commit-checks.sh,
comments included: `PCC_VALUE_MINLEN=8`,
`PCC_ALLOWLIST="docs/ai/secrets-allowlist.txt"` (the literal
`secrets-allowlist.txt` appears nowhere else in the script),
`function has_space(v) {`, `function is_wordlike(v) {`,
`function is_reference(v) {`, `function is_placeholder(v) {`,
`function is_url(v) {`, `AKIA`, `gh[pousr]_`, `github_pat_`,
`PRIVATE KEY`, `pcc_namehit=0`, `pcc_namehit=1`, `pcc_keyfile=0`,
`pcc_keyfile=1`, `pcc_catch_all=1`, `--verify ":$PCC_ALLOWLIST"`,
`, fingerprint `, `"$pcc_nfind" -gt 0`, `No secrets detected in staged files`.
`pcc_namehit=0` and `pcc_keyfile=0` are the per-file initialisations;
`pcc_namehit=1` and `pcc_keyfile=1` the only assignments that set them;
`"$pcc_nfind" -gt 0` guards the one `git hash-object` call.

### D-FIXTURES: secret-looking test data is built at runtime

Every fixture value that any rule would flag is assembled at run time from
pieces (as TEST-3832 builds its line), so tests/skills/test-aai-pre-commit-checks.sh
itself passes the new gate with no allowlist entry (Spec-AC-15 checks it).

### D-SELF: this repository's own allowlist

This repository commits its own `docs/ai/secrets-allowlist.txt`, holding
only the entries the self-corpus run needs (Spec-AC-15): every entry is
used by at least one finding, and the run over every tracked file reports
no blocking finding.

### D-PINS: moved pins

TEST-3454's numstat pin and TEST-3461's line-count pin are re-measured on
the delivered script and each gains a comment line naming this ride, as
every earlier ride did. `fu-pcc-ride-scoped-pins` stays open: replacing
ride-scoped pins is a change to the preservation tests' design, not to the
secrets gate.

### D-AMEND

One `spec-amend.mjs add --class contract --signoff none --ref
secrets-gate-false-positives` record per closed spec whose test this scope
changes, written only after the change is verified by grep or diff:

- SPEC-0298: TEST-3833: `.env`, `.env.local`, `config/credentials.json`,
  `docs/ai/validation/.env` and `docs/ai/tdd/.env.prod` holding `harmless`
  now pass; each holding a real-looking value blocks with `Potential secret
  detected in <path>`; `keys/secret.key` holding `harmless` still blocks by
  name (D-KEYFILE).
- SPEC-0300: TEST-3865: the four evidence-folder `*.env` files holding
  `harmless` now pass and holding a real-looking value block; TEST-3866: the
  non-ASCII name-check fixture becomes `secrets/clé.key`.
- SPEC-0301: TEST-3876 compares stdout after removing the D-OUTPUT detail
  lines (`    line <n>, fingerprint <hex>` and `    ... and <k> more`) from
  the new script's output only; everything else stays byte-identical to the
  03f3e6df script.

The owner's merge signs them.

### D-DOCS

- CHANGELOG.md: exactly one heading `## [unreleased] — fix: the pre-commit
  secrets gate judges values instead of file names and reads a reviewed
  allowlist`, its body naming the allowlist path, the two entry kinds, the
  catch-all rejection, the new R4 detection in every file (a commit that
  passed before can now block on an AWS key id, a GitHub token or a private
  key block) and that only key files and binary blobs still block by name
  (Constitution article 5: the boundary change is explicit and documented).
- docs/product/pre-commit-secrets-gate.md (capability
  `pre-commit-secrets-gate`, from .aai/templates/PRODUCT_TEMPLATE.md): what
  is a finding, the allowlist format and path, the catch-all rule, the
  fingerprint line and how to compute it, and the residual risks.
- docs/USER_GUIDE.md: in the git hooks section, a short "Secrets detection"
  paragraph naming the allowlist path and pointing to the product doc.
- The intake gets frontmatter `user_visible: true`.

## Acceptance Criteria Mapping

- Expected Behavior bullet 1 (name hits become content scans) maps to
  Spec-AC-04 and Spec-AC-05.
- Expected Behavior bullet 2 (value shape) maps to Spec-AC-01, Spec-AC-02,
  Spec-AC-03 and Spec-AC-08.
- Expected Behavior bullet 3 (allowlist) maps to Spec-AC-09 to Spec-AC-12.
- Expected Behavior bullet 4 (true positives) maps to Spec-AC-06 and
  Spec-AC-07.
- Verification (suite passes, parity harness passes) maps to Spec-AC-13,
  Spec-AC-14, Spec-AC-16, Spec-AC-17 and Spec-AC-18; this repository's own
  commits keep working maps to Spec-AC-15; the consumer-visible note maps to
  Spec-AC-19.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the staged files carry keyed assignments whose quoted value holds a space or tab (YAML, JS and JSON `forgotPassword ⇒ "Forgot your password?"`, shell `password ⇒ 'Enter your password'`) or a word-like value (`resetPassword ⇒ 'Passwort'`, `password ⇒ "Přihlášení"`) the run SHALL exit 0 and print no `Potential secret detected` line. | planned | — | — | D-VALUE b and e |
| Spec-AC-02 | WHEN the staged files carry keyed assignments whose value is a reference (`password ⇒ "${DB_PASSWORD}"`, `api_key ⇒ "$API_KEY"`, `password ⇒ "{{vault_db_password}}"`, `apiKey ⇒ "process.env.API_KEY"`, `password ⇒ "%DB_PASSWORD%"`) the run SHALL exit 0 and print no `Potential secret detected` line. | planned | — | — | D-VALUE c |
| Spec-AC-03 | WHEN the staged files carry keyed assignments whose value is a placeholder (`<your-api-key>`, `xxxxxxxx`, `********`, `changeme123`, `your-api-key-here`, `REPLACE_ME_LATER`) or a URL without credentials (`TOKEN_URL ⇒ https://auth.acme.io/oauth/token` in a `.env.example`) the run SHALL exit 0 and print no `Potential secret detected` line. | planned | — | — | D-VALUE d and f |
| Spec-AC-04 | WHEN `.env.example`, `.env.sample` and `.env.template` with empty or placeholder values, a `.env` with only `NODE_ENV ⇒ production` and `PORT ⇒ 3000`, `config/credentials.json` without secret keys, `docs/secret-rotation.md` prose and `docs/ai/tdd/.env.prod` with an empty value are staged the run SHALL exit 0 and print neither `Sensitive file staged` nor `Potential secret detected`. | planned | — | — | D-NAME |
| Spec-AC-05 | WHEN a name-hit file with a `.key`, `.pem`, `.p12`, `.pfx`, `.jks` or `.keystore` basename holding `harmless`, or a name-hit file whose blob holds a NUL byte, is staged the run SHALL exit 1 with exactly one `Sensitive file staged: <path>` line for it. | planned | — | — | D-KEYFILE |
| Spec-AC-06 | WHEN a file holds an AWS access key id, a GitHub classic token, a GitHub fine-grained token, or an RSA, OPENSSH or PKCS8 private key block (each built at runtime, in an ordinary non-name-hit path) the run SHALL exit 1 with exactly one `Potential secret detected in <path>` line per file; the same token ending in `EXAMPLE` or made of x characters SHALL pass. | planned | — | — | D-RULES R4 |
| Spec-AC-07 | WHEN `.env` holds `DB_PASSWORD ⇒ RANDOM`, `.env.local` holds `STRIPE_SECRET_KEY ⇒ sk_live_RANDOM`, `config/credentials.json` holds `password ⇒ "RANDOM"`, `.env` holds `DATABASE_URL ⇒ postgres://app:RANDOM@db:5432/app`, `docs/ai/tdd/.env.prod` holds a random password, or an ordinary file holds TEST-3832's `api_key ⇒ "abcdefgh1234"` (RANDOM is a credential-shaped value built at runtime) the run SHALL exit 1 with exactly one `Potential secret detected in <path>` line per file. | planned | — | — | D-RULES R1 R2 R3 |
| Spec-AC-08 | WHEN the Spec-AC-01 to Spec-AC-07 fixture corpus is placed in non-name-hit paths, one line per file, the set of files the new run reports SHALL be a subset of the files the old content regex or an R4 token matches. | planned | — | — | monotonicity |
| Spec-AC-09 | WHEN the index holds an allowlist with `path locales/*.yml` and a staged `locales/de.yml` and `locales/sub/x.yml` carry credential-shaped values the run SHALL exit 0 and print `Secrets allowlist: 2 finding(s) allowed by docs/ai/secrets-allowlist.txt` once; a finding in `config/app.yml` in the same commit SHALL still block. | planned | — | — | D-ALLOW path |
| Spec-AC-10 | WHEN a finding is reported the line after its `Potential secret detected` line SHALL be `    line <n>, fingerprint <hex>` with hex equal to the D-FP command output, at most 3 such lines per file plus `    ... and <k> more`; WHEN that fingerprint is in the indexed allowlist that one finding SHALL be allowed and another line of the same file SHALL still block; no fixture value SHALL appear in stdout or stderr. | planned | — | — | D-FP and D-OUTPUT |
| Spec-AC-11 | WHEN the indexed allowlist holds `*`, `**`, `**/*`, `*.*`, `?*` or `[a-z]*` (one fixture each), or a line `pathx a`, `fingerprint xyz` or a 39-digit fingerprint, and a clean file is staged the run SHALL exit 1 with exactly one `Secrets allowlist line <n>:` error naming catch-all or unrecognised; `locales/*.yml`, `*.json`, comments, blank and CRLF lines SHALL raise no error. | planned | — | — | D-ALLOW catch-all |
| Spec-AC-12 | WHEN the matching allowlist entry exists only untracked, only as an unstaged edit, or is deleted in the staged index the finding SHALL still block; WHEN it is staged or tracked unchanged it SHALL be allowed; WHEN the index entry resolves but `git cat-file blob` fails the run SHALL exit 1 with `Staged content could not be read completely: secrets allowlist`. | planned | — | — | D-READ |
| Spec-AC-13 | WHEN 5 and 40 clean files are staged with a tracked allowlist the run SHALL start the same number of git processes and no `hash-object`; WHEN findings exist in 3 files exactly one `git hash-object` process SHALL start; with no allowlist in the index exactly one `cat-file` process SHALL start. | planned | — | — | D-READ and D-FP budget |
| Spec-AC-14 | WHEN commits go through the hook installed by install-pre-commit-hook.sh a Spec-AC-01 to Spec-AC-04 false-positive commit SHALL move HEAD, a Spec-AC-06 or Spec-AC-07 true-positive commit SHALL leave HEAD unmoved with the finding line in the output, and the Spec-AC-09 allowlisted commit SHALL move HEAD. | planned | — | — | seam: hook template to checks to index |
| Spec-AC-15 | WHEN every tracked file of this repository's HEAD is staged in a scratch clone the run SHALL report no blocking CHECK 2 finding with the committed docs/ai/secrets-allowlist.txt; without it every `path` entry SHALL match at least one finding file and every `fingerprint` entry SHALL appear among the printed fingerprints; tests/skills/test-aai-pre-commit-checks.sh SHALL need no entry. | planned | — | — | D-SELF and D-FIXTURES |
| Spec-AC-16 | The awk program SHALL hold no interval expression and none of `gensub`, `IGNORECASE`, `strtonum`, `asort`, `PROCINFO` or `systime`; each D-ANCHORS string SHALL occur exactly once in the script; the Spec-AC-01 to Spec-AC-07 fixture run SHALL give byte-identical stdout under every awk among awk, mawk, gawk and nawk on PATH (each host runs every one it has; the macOS host and the Linux CI host differ) and with a failing `node` first on PATH. | planned | — | — | D-PORT and D-ANCHORS |
| Spec-AC-17 | env -u AAI_ROLE bash tests/skills/test-aai-pre-commit-checks.sh SHALL exit 0 with TEST-3833, TEST-3865, TEST-3866 and TEST-3876 changed only as D-AMEND states, TEST-3454 and TEST-3461 re-pinned per D-PINS, and TEST-3455, TEST-3871, TEST-3919, TEST-3920 and TEST-4047 unchanged; tests/skills/test-aai-install-parity.sh, test-aai-hook-installer-node.sh and test-aai-git-hook-templates.sh SHALL exit 0. | planned | — | — | preservation |
| Spec-AC-18 | WHEN aai-sync.sh --profile core runs into a scratch target holding a docs/ai/secrets-allowlist.txt the file SHALL be byte-identical afterwards, and into a target without one none SHALL be created; .aai/system/DOCS_AI_CANON.list SHALL list `secrets-allowlist.txt`. | planned | — | — | seam: sync and docs-audit |
| Spec-AC-20 | WHEN a non-name-hit binary blob holds a NUL byte followed on the same line by a keyed quoted credential, an AWS key id, or by a private key begin line and body, the run SHALL exit 1 with exactly one `Potential secret detected in <path>` line per file; a label after a NUL SHALL pass. | planned | — | — | D-NUL, amendment A1 (V1) |
| Spec-AC-21 | WHEN a real dotenv file (`.env`, `.env.local`, `deploy/prod.env`, `.env.production`, `docs/ai/tdd/.env.test`) holds `DB_PASS`, `MYSQL_PWD`, `ENCRYPTION_KEY`, `STRIPE_KEY` or `JWT_SIGNING_KEY` with a credential-shaped value the run SHALL exit 1 with one secret line per file; a `.env` with `NODE_ENV`, `PORT`, `LOG_LEVEL`, a credential-free URL, an empty value and a comment, and the template forms `.env.example`, `.env.sample` and `.env.defaults` SHALL pass. | planned | — | — | D-RULES R5, amendment A1 (V2) |
| Spec-AC-22 | WHEN the indexed allowlist holds `path [!z]*`, `*[!z]`, `[!.]*`, `[a-z]?*`, `*/[!z]*` or `?[!z]*` and a clean file is staged the run SHALL exit 1 with exactly one catch-all error; `locales/[!z]*.yml`, `[ab]foo/*` and `app/?.json` SHALL raise none. | planned | — | — | D-ALLOW catch-all, amendment A1 (N1) |
| Spec-AC-23 | WHEN a line holds a private key begin marker anywhere in it (`-----BEGIN PRIVATE KEY-----` or with words such as RSA before `PRIVATE KEY`) followed on the same line by a base64 run of 40 or more characters, after optional blanks, quotes and backslash-n or backslash-r escapes, or followed by nothing and the next non-empty line begins with such a run (quotes and plus signs before it ignored), the run SHALL exit 1 with one `Potential secret detected in <path>` line per file, in JS, Terraform, Python, YAML, JSON, `.env`, `.env.local` and string-concatenation forms; a marker followed by prose, by a short body or by a placeholder body SHALL pass. | planned | — | — | D-RULES R4 widened, amendment A2 (V3) |
| Spec-AC-24 | WHEN a name-hit file that is not one of the template basenames `.env.example`, `.env.sample`, `.env.template`, `.env.dist` or `.env.defaults` holds a credential-shaped value (D-VALUE) under any key, as `export KEY=value`, YAML `key: value` or `- key: value`, JSON `"key": "value"`, TOML `key = "value"` or a commented `# KEY=value`, in a data or config file (a dotenv file, `.yaml`, `.yml`, `.json`, `.toml`, `.ini`, `.cfg`, `.conf`, `.properties`, `.tfvars`, `.txt`, `.xml`, `.plist` or a name with no extension), and an `export KEY=value` line in any other name-hit file, the run SHALL exit 1 with one secret line per file; labels with spaces, references, placeholders, empty values, word-like values, URLs and prose in the same file kinds, plain assignments and comments in a documentation or code file (`.md`, `.js`, `.sh`), and any value in a template basename under a non-keyword key, SHALL pass. | planned | — | — | D-RULES R6, amendment A2 (V4) |
| Spec-AC-25 | WHEN the indexed allowlist holds `path [!]z]*`, `[![:digit:]z]*`, `[^]z]*`, `*[!]z]` or `[![:digit:][:alpha:]]*` and a clean file is staged the run SHALL exit 1 with exactly one catch-all error; `[]a]foo/*`, `[[:alpha:]]bar/*` and `docs/[![:digit:]]x.md` SHALL raise none. | planned | — | — | D-ALLOW bracket expressions, amendment A2 (N5) |
| Spec-AC-26 | WHEN a keyed value under a key that names a secret (`password`, `passwd`, `pwd`, `secret`, `token`, `api_key`, `access_key`, `private_key`) is a single plain word (letters joined by single hyphens, apostrophes or dots, as `abcdefghijklmnopqrstuvwxyz`, `correcthorsebattery`, `CorrectHorse`, `SUPERSECRET` or a word longer than 20 bytes) the run SHALL exit 1 with one secret line per file, in a free-text file, YAML and a real `.env`; WHEN the plain word is a short capitalised label (at most 20 bytes, first byte A to Z or at or above 0x80, no other A to Z: `Password`, `Heslo`, `Passwort`, `Přihlášení`, `Čeština`, `Forgot-password`), or the key does not name a secret (`NODE_ENV=production`, `LOG_LEVEL=debug`), the run SHALL exit 0 with no secret line. | planned | — | — | D-VALUE e, amendment A3 (V5) |
| Spec-AC-19 | CHANGELOG.md SHALL hold the D-DOCS heading exactly once; docs/product/pre-commit-secrets-gate.md SHALL name the allowlist path, both entry kinds and the catch-all rule; docs/USER_GUIDE.md SHALL name the allowlist path; the intake SHALL carry `user_visible: true`; spec-amend list --strict SHALL exit 0 holding the three D-AMEND records. | planned | — | — | D-DOCS and D-AMEND |

## Implementation plan

1. RED first: TEST-4080 to TEST-4084 and TEST-4085 against the unchanged
   script (each false-positive fixture exits 1 today); TEST-4086 to
   TEST-4092 are written next and their RED is observed through their named
   mutation once the code exists (a true positive that already blocks
   cannot red on the unchanged tree; record the mutation run as its RED).
2. CHECK 2 in .aai/scripts/pre-commit-checks.sh: the name-hit and key-file
   classification (D-NAME, D-KEYFILE), the awk program (D-RULES, D-VALUE),
   the allowlist read and parse (D-READ, D-ALLOW), fingerprints and output
   (D-FP, D-OUTPUT), within D-PORT and D-ANCHORS.
3. TEST-4093 to TEST-4101: monotonicity, allowlist, budget, hook seam,
   self-corpus with docs/ai/secrets-allowlist.txt (D-SELF), portability.
4. D-AMEND test edits (TEST-3833, TEST-3865, TEST-3866, TEST-3876), D-PINS
   re-pins, the suite header and `main` list; TEST-4102.
5. .aai/system/DOCS_AI_CANON.list entry, TEST-4103 (sync seam).
6. Docs (D-DOCS) after the loop completes, then TEST-4104 and the D-AMEND
   records (written last, after grep confirms each change).

Edge cases: CRLF files (a trailing CR is not part of a value), a value
running to end of line without a closing quote, two assignments on one
line (one finding line), names git would quote (TEST-3876 fixture), a 3.2
MB blob, a staged gitlink or deletion (no blob, skipped as today), cwd
inside `.git` (TEST-3876: the allowlist resolves or not, no new output).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4080 | Spec-AC-01 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4080_labels_with_blanks_pass stages the YAML, JS, JSON and shell label fixtures and requires exit 0 and no secret line | `sed:s/function has_space\(v\) \{/function has_space(v) { return 0;/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4081 | Spec-AC-01 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4081_wordlike_labels_pass stages `Passwort` and `Přihlášení` label fixtures and requires exit 0 and no secret line | `sed:s/function is_wordlike\(v\) \{/function is_wordlike(v) { return 0;/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4082 | Spec-AC-02 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4082_references_pass stages the five reference fixtures and requires exit 0 and no secret line | `sed:s/function is_reference\(v\) \{/function is_reference(v) { return 0;/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4083 | Spec-AC-03 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4083_placeholders_pass stages the six placeholder fixtures and requires exit 0 and no secret line | `sed:s/function is_placeholder\(v\) \{/function is_placeholder(v) { return 0;/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4084 | Spec-AC-03 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4084_plain_urls_pass stages `.env.example` with `TOKEN_URL ⇒ https://auth.acme.io/oauth/token` and requires exit 0 and no secret line | `sed:s/function is_url\(v\) \{/function is_url(v) { return 0;/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4085 | Spec-AC-04 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4085_name_hits_scanned_not_blocked stages the Spec-AC-04 files and requires exit 0 with no Sensitive and no secret line | `sed:s/pcc_keyfile=0/pcc_keyfile=1/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4086 | Spec-AC-05 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4086_keyfiles_and_binary_blocked stages each key-file extension and a NUL blob under name-hit paths, one fixture each, and requires exit 1 and one Sensitive line naming the path | `sed:s/pcc_keyfile=1/pcc_keyfile=0/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4087 | Spec-AC-06 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4087_aws_key_blocked stages an AKIA key id built at runtime keyed and unkeyed, plus the EXAMPLE variant, requiring 1 for the real ones and 0 for EXAMPLE | `sed:s/AKIA/AKIQ/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4088 | Spec-AC-06 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4088_github_classic_blocked stages ghp_ and gho_ tokens built at runtime plus an x-filled one, requiring one secret line per real token file and none for the x one | `sed:s/gh\[pousr\]_/gh[x]_/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4089 | Spec-AC-06 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4089_github_fine_grained_blocked stages a github_pat_ token of the 22 plus 59 shape built at runtime and requires exit 1 with one secret line | `sed:s/github_pat_/github_pax_/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4090 | Spec-AC-06 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4090_private_key_blocks_blocked stages RSA, OPENSSH and PKCS8 blocks built at runtime and a header-only mention, requiring one secret line per block file and none for the mention | `sed:s/PRIVATE KEY/PRIVATE KEX/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4091 | Spec-AC-07 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4091_name_hit_values_blocked stages the dotenv, credentials.json, URL and evidence-folder dotenv fixtures and requires exit 1 with one secret line per file | `sed:s/pcc_namehit=1/pcc_namehit=0/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4092 | Spec-AC-07 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4092_quoted_keyed_blocked stages TEST-3832's `api_key ⇒ "abcdefgh1234"` and two more quoted credential values in ordinary files and requires one secret line per file | `sed:s/PCC_VALUE_MINLEN=8/PCC_VALUE_MINLEN=80/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4093 | Spec-AC-08 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4093_monotone_outside_name_hits places the corpus one line per file in ordinary paths, runs the old regex and the R4 patterns as oracle, and requires the reported set to be a subset | `sed:s/pcc_namehit=0/pcc_namehit=1/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4094 | Spec-AC-09 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4094_allowlist_path_entries commits an allowlist with a locales glob, stages the three files and requires the allowed-count line, exit 1 for config/app.yml, then exit 0 without it | `sed:s/secrets-allowlist\.txt"/secrets-allowlist.off"/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4095 | Spec-AC-10 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4095_fingerprint_lines_and_entries checks the detail line format and hash against the D-FP command, the 3-line cap, that a listed fingerprint allows one line only, and that no fixture value is printed | `sed:s/, fingerprint /, fp /` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4096 | Spec-AC-11 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4096_catch_all_and_malformed_rejected runs each rejected and accepted allowlist line with a clean staged file | `sed:s/pcc_catch_all=1/pcc_catch_all=0/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4097 | Spec-AC-12 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4097_allowlist_read_from_index runs the untracked, unstaged, staged-deleted, staged, tracked and unreadable shapes, the last through the git wrapper failing cat-file blob | `sed:s/--verify ":/--verify ":x/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4098 | Spec-AC-13 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4098_git_process_budget logs git invocations through the TEST-3871 wrapper for 5 and 40 clean files with a tracked allowlist, for 3 finding files, and with no allowlist | `sed:s/"\$pcc_nfind" -gt 0/1 -gt 0/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4099 | Spec-AC-14 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4099_installed_hook_seam installs the hook with vendor_hook_installer and commits a false-positive set, a true-positive set and an allowlisted set, checking HEAD each time | `sed:s/function is_reference\(v\) \{/function is_reference(v) { return 0;/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4100 | Spec-AC-15 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4100_self_corpus clones HEAD into scratch, stages every tracked file and runs the delivered checks with and without the repository allowlist | `sed:s/AKIA/AKIQ/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4101 | Spec-AC-16 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_4101_portability_and_anchors lints the awk program, counts each anchor, and runs the fixture corpus under every awk found and with a failing node shim | `sed:s/function has_space\(v\) \{/function has_space(v) { IGNORECASE = 1;/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4102 | Spec-AC-17 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4102_preservation runs TEST-3454, TEST-3455, TEST-3461, TEST-3833, TEST-3865, TEST-3866, TEST-3871, TEST-3876, TEST-3919, TEST-3920 and TEST-4047 by selector, and the install-parity, hook-installer-node and git-hook-templates suites | `sed:s/No secrets detected in staged files/No secrets found in staged files/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4103 | Spec-AC-18 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4103_sync_leaves_allowlist syncs core into two scratch targets, with and without an allowlist, and checks the canon list entry | `sed:s/secrets-allowlist\.txt/secrets-allowlist.off/` on .aai/system/DOCS_AI_CANON.list | green |
| TEST-4104 | Spec-AC-19 | inspection | tests/skills/test-aai-pre-commit-checks.sh | test_4104_docs_and_amendments greps the CHANGELOG heading count, the product doc, USER_GUIDE and intake frontmatter, and runs spec-amend list --strict | `sed:s/judges values instead of file names/judges file names/` on CHANGELOG.md | green |

| TEST-4105 | Spec-AC-20 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4105_nul_blob_credentials_blocked stages ordinary binary blobs with a NUL before a keyed credential, an AWS key id and a private key block, requiring one secret line each, and a label blob that passes | `sed:s/if \[ "\$pcc_nul" -gt 0 \]; then/if false; then/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4106 | Spec-AC-21 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4106_real_dotenv_any_key_blocks stages the five key names in five real dotenv basenames and requires one secret line each, then a plain-settings dotenv and template forms that pass | `sed:s/pcc_anykey=1/pcc_anykey=0/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4107 | Spec-AC-22 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4107_negated_class_catch_all_rejected runs each negated or bracket-only glob with a clean staged file and requires one catch-all error, then accepts anchored bracket globs | `sed:s/pcc_s="\$pcc_g"/pcc_s="x.x"/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4108 | Spec-AC-23 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4108_inline_private_key_blocks stages the eight inline and multi-line key forms (built at runtime) and requires one secret line each, then a mention, a prose tail, a short body and a placeholder body that pass | `sed:s/pk = pkscan\(\$0\)/pk = 0/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4109 | Spec-AC-24 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4109_name_hit_any_key_blocks stages an `.envrc`, a Kubernetes Secret, credentials.json, a TOML, a commented `.env.staging` line and a YAML list entry under non-keyword keys and requires one secret line each, an `export` line in a shell script, then labels, references, placeholders, prose, a document with a date and a path in its front matter, a code file with plain assignments and a `.env.example` that pass | `sed:s/pcc_anykey=1/pcc_anykey=0/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4110 | Spec-AC-25 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4110_bracket_class_catch_all_rejected runs the five bracket-only globs with a clean staged file and requires one catch-all error each, then accepts three anchored bracket globs | `sed:s/'\[:'\*\)/'[:Z'*)/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4111 | Spec-AC-26 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4111_keyword_key_plain_words_block stages the 26-letter run under api_key, a lowercase word, a CamelCase word, an ALLCAPS word and a 26-byte capitalised word under password and secret_key, and a dotenv DB_PASSWORD word, requiring one secret line per file | `sed:s/kw != 1/1 == 1/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4112 | Spec-AC-26 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4112_short_labels_pass stages short capitalised and non-ASCII labels under keyword keys, a label with blanks, and a dotenv with NODE_ENV, LOG_LEVEL, APP_MODE and a capitalised DB_PASSWORD label, requiring exit 0 and no secret line | `sed:s/length\(v\) > 20/length(v) > 2/` on .aai/scripts/pre-commit-checks.sh | green |
| TEST-4113 | Spec-AC-26 | integration | tests/skills/test-aai-pre-commit-checks.sh | test_4113_pass_keys_name_a_secret stages three real dotenv files holding a plain word under DB_PASS, GPG_PASSPHRASE and export SMTP_PASS, requiring one secret line each, then BYPASS_CACHE and COMPASS_URL holding the same plain word, requiring exit 0 and no secret line | `sed:s/pass\(phrase\)\?\[\^a-z\]/pass(phrasx)?[^a-z]/` on .aai/scripts/pre-commit-checks.sh | green |

## Verification

- Canonical runner, `env -u AAI_ROLE`:
  `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pre-commit-checks.sh`,
  then aai-install-parity, aai-hook-installer-node, aai-git-hook-templates,
  aai-doc-numbering and aai-tracked-ignored (they run the checks script).
- One full sweep before the close with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/mutation-run.mjs` for every Test Plan row;
  `mutation-gate.mjs` PASS; `spec-amend.mjs list --strict` exit 0.
- Hosted: the skill-suite run on the pull request head (Linux awk differs
  from the macOS one, Spec-AC-16).

## Evidence contract

- ref_id `secrets-gate-false-positives`. RED and GREEN logs under
  `docs/ai/tdd/secrets-gate-false-positives/{red,green}/`; mutation records
  under `docs/ai/tdd/spec-secrets-gate-false-positives/`.
- Validation report
  `docs/ai/reports/VALIDATION-<ts>-secrets-gate-false-positives.md`;
  review report `docs/ai/reviews/review-secrets-gate-false-positives-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above. TEST-4080 to TEST-4085 red on the unchanged script; the other rows
record their RED as the named mutation run (a true positive or a
preservation case cannot fail on the unchanged tree).

## Registry items closed by this scope

none

## Registry items this scope leaves open

- `fu-pcc-ride-scoped-pins`: this scope moves the two pins it names (D-PINS)
  but does not redesign them.
- `fu-redact-entropy-fp-hyphen-identifier`: a different redactor
  (aai-redact.mjs), not this gate.

## Amendment A1 (VALIDATION round 1, additive with disclosure)

Post-freeze, recorded with `spec-amend.mjs add --signoff none`; the owner's
merge signs it. Adds R5 (V2), D-NUL (V1), the bracket-only catch-all rule
(N1), Spec-AC-20 to Spec-AC-22 and TEST-4105 to TEST-4107, and the
pre-commit-checks.sh line pins (TEST-3454, TEST-3461) move again. The
mutation anchors `pcc_dotenv=1`, `pcc_lit="$pcc_g"` and
`if [ "$pcc_nul" -gt 0 ]; then` each occur once. Residual N4 (a private key
inside a JSON string with `\n` escapes is not an R4 block) and N3 (the mawk
and gawk legs rest on the hosted Linux run) are unchanged.

## Residual risks

- A real `.env` value that is credential-shaped but harmless (a long digit
  string, `Europe/Prague`) blocks under R5; a `path` or `fingerprint` entry
  exempts it. A template form with a real value under a non-keyword key
  passes (R2 only).
- A private key embedded as a JSON string with `\n` escapes is not an R4
  block (not a regression: the old gate did not detect it).

- A word-like value (letters only, e.g. `hunterhunter`) and any value under
  8 bytes pass in every file, including a real `.env`; before this change
  every `.env` blocked by name. The CHANGELOG and the product doc say so.
- A credential in an unquoted value outside name-hit files (a YAML
  `password ⇒ value` without quotes in config.yml) is not detected, as
  before.
- A bare token in a name-hit text file without a key (e.g. `api-token.txt`
  holding only a random string, not a key-file extension) passes; before
  this change it blocked by name.
- R4 adds detection in every file: a consumer commit touching a file with a
  fake but well-formed AWS key or GitHub token now blocks until the file is
  allowlisted.
- A `path` glob that is narrower than the probes but still broad (e.g.
  `*.json`) is accepted; it is visible in review because the allowlist is
  committed.
- Windows Git Bash runs gawk; no hosted job runs this suite on Windows, so
  that leg rests on Spec-AC-16's gawk run on Linux.

## Amendment A2 (VALIDATION round 2, additive with disclosure)

Post-freeze, recorded with `spec-amend.mjs add --signoff none`; the owner's
merge signs it. Nothing above is edited; where A2 and the text above differ,
A2 governs. Round 3 of 3 (a recorded round extension).

- R4 private key block, widened (V3; Spec-AC-23, TEST-4108). A line that
  holds `-----BEGIN PRIVATE KEY-----` or `-----BEGIN <words> PRIVATE
  KEY-----` (or the PGP `BLOCK-----` form) anywhere in it is a finding when
  the text after the marker, once blanks, quotes, commas, plus signs,
  semicolons, closing parentheses and backslash-n or backslash-r escapes
  are skipped, is a base64 run (`A-Za-z0-9+/=`) of 40 or more characters or
  begins `Proc-Type:`. When nothing follows the marker, the next non-empty
  line decides, with leading blanks, quotes, commas and plus signs ignored,
  by the same rule. This covers a key inline in a quoted keyed value in JS,
  Terraform, Python, YAML, JSON, `.env` and `.env.local`, whatever D-VALUE b
  says about the blanks in the marker. The exempt forms are exactly: a
  marker followed by prose, a body shorter than 40 characters, or a body
  that is not base64 (a placeholder such as `<your-key-here>`); the
  whole-line form of the frozen R4 is unchanged. This supersedes the
  Residual risks line that a private key in a JSON string with backslash-n
  escapes is not an R4 block: that form is now a finding.
- R6 any-key judging in name-hit files that are not dotenv templates (V4;
  Spec-AC-24, TEST-4109). In a name-hit file whose basename is not
  `.env.example`, `.env.sample`, `.env.template`, `.env.dist` or
  `.env.defaults`, a `key` and `=` or `:` pair is judged by D-VALUE
  whatever the key is called. The key is `[A-Za-z_][A-Za-z0-9_.-]*`,
  optionally quoted, and starts the line or follows a blank, `{`, `,`, `;`,
  `(`, `[` or `#`; after `:` a blank, a quote or the end of the line must
  follow, so `http://x` is not a pair. The value is read as in R2. This
  covers `export KEY=value`, YAML `key: value` and `- key: value`, JSON,
  TOML and a commented `# KEY=value`, in `.envrc`, a Kubernetes Secret
  manifest, `credentials.json`, a file named `*secret*` or `*credentials*`
  and a real `.env`. The pair is judged in every line of a data or config
  file: a dotenv file, `.yaml`, `.yml`, `.json`, `.toml`, `.ini`, `.cfg`,
  `.conf`, `.properties`, `.tfvars`, `.txt`, `.xml`, `.plist`, or a name with
  no extension (`credentials`, `.envrc`). In any other name-hit file (code,
  shell, documentation: `.js`, `.py`, `.sh`, `.md`) only a line starting
  `export KEY=value` is judged, because plain assignments, front matter
  dates and paths there measured as prose and code (this repository's own
  `secrets-preflight.mjs`, SPEC documents and the product doc blocked on
  `const base = basename(path)`, `updated: 2026-11-25` and `spec: docs/...`).
  The true negatives are the D-VALUE classes: values with a blank,
  references, placeholders, word-like values, URLs, relative paths, short
  and empty values. A template basename keeps R2 and R3 only. Spec-AC-21
  is narrowed in one clause: a comment line without an assignment still
  passes in a real `.env`; a commented assignment is judged by R6.
- Bracket expressions in the catch-all test (N5; Spec-AC-25, TEST-4110): a
  `[` starts an expression ended by the first `]` that is not a leading
  `]` (after an optional `!` or `^`) and not inside a `[:class:]`.
- R5 is folded into R6: every real dotenv file is a data or config file for
  R6, so R5's own call, its `pcc_dotenv` flag and its awk argument are
  removed (same findings; two rules that each alone block the same lines
  could not be told apart by a mutation). The mutation cells of TEST-4106
  and TEST-4107 are re-anchored from `pcc_dotenv=1` and `pcc_lit="$pcc_g"`
  to `pcc_anykey=1` and `pcc_s="$pcc_g"`, the lines that now carry those
  behaviours; the tests themselves are unchanged apart from TEST-4106's
  comment line (a commented assignment is now judged, see above).
- Mutation anchors: `pk = pkscan($0)`, `pcc_anykey=1` and `'[:'*)` each
  occur once; `PRIVATE KEY` stays exactly once (a helper function holds it).
  The pins of TEST-3454 and TEST-3461 move again (767 added and 42 removed;
  1048 lines and 887 code lines).

Residual risks added by A2 (disclosed, not fixed):

- N6, over-blocking: a real `.env` (and, since R6, any name-hit file that is
  not a template) holds plain settings that are credential-shaped by D-VALUE
  and block: `HOST=127.0.0.1`, `DATA_DIR=/var/lib/app`, `TZ=Europe/Prague`,
  `MAX_UPLOAD=10485760`, `APP_VERSION=1.2.3-beta`, `LANG=en_US.UTF-8`, a
  date such as `2026-11-25`. A `path` or `fingerprint` allowlist entry is
  the remedy. This is not a regression: before this change every such file
  blocked by name.
- A credential under a non-keyword key in a code or documentation file
  named `*secret*` or `*credentials*` (not an `export` line, not a quoted
  keyword key) passes, as in any ordinary file.
- An unquoted YAML value followed by more words is judged by its first
  word only (as in R2), so a sentence whose first word is credential-shaped
  can block in a name-hit file.
- A private key whose base64 body starts after 40 or more characters of
  other text on the marker line, or whose body is split into lines shorter
  than 40 characters directly after the marker line, is not detected (the
  frozen whole-line R4 has the same limit).

## Amendment A3 (VALIDATION round 3, additive with disclosure)

Post-freeze, recorded with `spec-amend.mjs add --signoff none`; the owner's
merge signs it. Nothing above is edited; where A3 and the text above differ,
A3 governs. Round 4 (a recorded round extension, owner-authorised).

- D-VALUE e, narrowed (V5; Spec-AC-26, TEST-4111 and TEST-4112). The frozen
  rule exempted every word-like value, so `api_key = "abcdefghijklmnopqrstuvwxyz"`
  (the fixture of SPEC-0201 TEST-801 in tests/skills/test-aai-hygiene-pack.sh,
  which origin/main blocks) committed. That fixture is not changed. The rule
  is key-aware. A value is judged under a secret key when the key names one:
  R1 and R3 always; R2 always (its key holds a keyword); R6 and the real
  dotenv `KEY=value` rule when the key, case-insensitively, contains
  `password`, `passwd`, `pwd`, `secret`, `token`, `api_key`, `apikey`,
  `api-key`, `access_key`, `access-key`, `private_key` or `private-key`.
  Under a secret key a word-like value stays exempt only when it is a short
  capitalised label, exactly: (1) at most 20 bytes (`LC_ALL=C`, so an accented
  letter counts 2); (2) its first byte is `A` to `Z` or at or above 0x80; and
  (3) no byte after the first is `A` to `Z` (ALLCAPS and CamelCase block).
  Any other word-like value under a secret key is credential-shaped when it
  passes the other D-VALUE clauses (length at least 8, no blank, not a
  reference, placeholder, URL or path), so `correcthorsebattery`,
  `CorrectHorse`, `SUPERSECRET` and the 26-letter run block. Under a key that
  does not name a secret the frozen word-like exemption is unchanged (any
  length), so `NODE_ENV=production` and `LOG_LEVEL=debug` commit.
- The i18n labels still pass: `forgotPassword: "Forgot your password?"` (it
  has blanks, D-VALUE b), `passwordLabel: "Password"`, `password: "Heslo"`,
  `resetPassword: "Passwort"`, `password: "Přihlášení"`.
- Mutation anchors: `kw != 1` and `length(v) > 20` each occur once. The pins
  of TEST-3454 and TEST-3461 move again (777 added and 42 removed; 1058
  lines and 897 code lines).

Residual risks added by A3 (disclosed, not fixed):

- A capitalised single word under a secret key passes (`Correcthorsebattery`
  of 19 letters); a lowercase label under a secret key blocks (`password:
  "heslo"`, `"passwordHint": "enter your"` passes by its blank but
  `passwordHint: "newpassword"` blocks). A plain setting under a secret key
  (`TOKEN_TYPE=authorization`, `SECRET_STORE=production-vault`) blocks; a
  `path` or `fingerprint` allowlist entry is the remedy.
- A letters-only value of any length under a key that does not name a secret
  still passes (`FOO=abcdefghijklmnopqrstuvwxyz` in a real `.env`), as under A2.

## Amendment A4 (REVIEW non-blocking fold, additive with disclosure)

Post-freeze, recorded with `spec-amend.mjs add --class contract --signoff none`;
the owner's merge signs it. Nothing above is edited; where A4 and the text above
differ, A4 governs.

- A3 key list, widened (NB-2; Spec-AC-26, TEST-4113). A key also names a secret
  when it holds `pass` or `passphrase` as a whole word: the key, lowercased and
  prefixed with an underscore, matches a non-letter, `pass`, an optional
  `phrase`, then a non-letter. `DB_PASS`, `SMTP_PASS`, `REDIS_PASS`, `PASS` and
  `GPG_PASSPHRASE` name a secret, so a plain word under them blocks like
  `DB_PASSWORD`; `BYPASS_CACHE`, `COMPASS_URL`, `passthrough` and camelCase
  `dbPass` do not. Mutation anchor: `pass(phrase)?` occurs once.
- The prefilter `grep` of CHECK 2 runs under `LC_ALL=C` (NB-3), so a file whose
  only keyword lines hold invalid UTF-8 is still scanned.
- Allowlist (NB-1): the three whole-file `path` entries for the
  secrets-preflight script, SPEC-0045 and its test are replaced by the five
  `fingerprint` entries of the lines that were findings.
- Docs (NB-6): the product doc, CHANGELOG and USER_GUIDE say that the key
  decides whether a plain word blocks, as A3 does.

Residual risks added by A4 (disclosed, not fixed):

- A value that begins with `$` is read as a variable reference (D-VALUE c), so a
  `$`-leading literal password or bcrypt hash is never a finding; it cannot be
  told from `$VAR` by shape (NB-7, P3, accepted residual).
- A camelCase key such as `dbPass` does not name a secret under the whole-word
  rule.
