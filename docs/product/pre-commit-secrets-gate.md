---
id: pre-commit-secrets-gate
type: product
capability: pre-commit-secrets-gate
status: current
delivered_by:
  - secrets-gate-false-positives
spec: docs/specs/SPEC-DRAFT-secrets-gate-false-positives.md
updated: 2026-11-25
---

# Pre-commit secrets gate

## What it does

Before a commit, the AAI pre-commit checks read every staged file, as the
commit records it, and block the commit when a line looks like a credential.
The gate judges the value, not the file name and not the word next to it. A
translated label such as `Forgot your password?`, a variable reference such as
`${DB_PASSWORD}`, a placeholder such as `<your-api-key>` and a plain URL are
not credentials and commit. A real-looking value behind a key such as
`api_key`, `password`, `secret_key`, `access_token` or `private_key` blocks.
A project exempts a reviewed false positive in one committed allowlist file
instead of passing `git commit --no-verify`, which would switch off every
other check as well.

## How to use it

A finding is one line of a staged blob.

- Keyed value (every file): one of the keywords `api_key`, `api_secret`,
  `password`, `passwd`, `secret_key`, `access_token`, `private_key`
  (case-insensitive, an optional `-` or `_` inside the name), then `:` or `=`,
  then a quote, then a credential-shaped value.
- Credential-shaped value: at least 8 bytes, no space or tab, and none of: a
  reference (starts with `$`, contains `${`, starts with `{{`, wrapped in `%`,
  or starts with `process.env.`, `import.meta.env.`, `os.environ`,
  `os.getenv(`, `System.getenv(`, `ENV[` or `env(`), a placeholder (starts
  with `<` and holds `>`, one repeated character, or holds `changeme`,
  `replaceme`, `placeholder`, `example`, `dummy`, `redacted` or `xxxx`, starts
  with `your_` or `your-`, ends with `_here` or `-here`), a plain word, a URL,
  or a relative path. A plain word (letters joined by single `-`, an apostrophe or `.`)
  passes under a key that names a secret (`password`, `passwd`, `pwd`, `secret`, `token`, `api_key`, `access_key`, `private_key`, or `pass` or `passphrase` as a whole word of the key, as `DB_PASS`, `GPG_PASSPHRASE`; `BYPASS_CACHE` does not) only as a short
  capitalised label: at most 20 bytes, the first byte `A-Z` or a non-ASCII
  byte, no other `A-Z` (`Password`, `Heslo`, `Passwort`, `Přihlášení`,
  `Forgot-password`). `correcthorsebattery`, `CorrectHorse`, `SUPERSECRET` and
  `abcdefghijklmnopqrstuvwxyz` under such a key block. Under any other key a
  plain word of any length still passes.
- Tokens (every file, whatever the key): an AWS access key id, a GitHub token
  (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_` or `github_pat_`) and a private key
  block. A private key block is a `-----BEGIN ... PRIVATE KEY-----` marker
  anywhere in a line, followed by a base64 body of 40 or more characters on
  the same line (also after a `\n` escape, inside a quoted string, as in a
  JS, Terraform, Python, YAML, JSON or `.env` value) or on the next non-empty
  line, or by a `Proc-Type` line. A marker in prose, with a short body or a
  placeholder body passes. A token ending in `EXAMPLE` or made of x
  characters passes.
- Name hits: a staged path containing `.env`, `credentials` or `secret` (an
  AAI evidence folder under `docs/ai/reports`, `docs/ai/tdd`,
  `docs/ai/validation` or `docs/ai/reviews` counts only for a `.env` or
  `*.env` basename) is also read for an unquoted `KEY=value` whose key names a
  secret, and for `scheme://user:pass@host` URL credentials. Only a key file
  (`.key`, `.pem`, `.p12`, `.pfx`, `.jks`, `.keystore`) or a blob holding a NUL
  byte still blocks by name, printing `Sensitive file staged: <path>`.
- Any key in name-hit files: in a name hit that is not a dotenv template and
  is a data or config file (a dotenv file, `.yaml`, `.yml`, `.json`, `.toml`,
  `.ini`, `.cfg`, `.conf`, `.properties`, `.tfvars`, `.txt`, `.xml`, `.plist`
  or a name with no extension such as `.envrc` or `credentials`), a
  `key = value` or `key: value` pair is judged whatever the key is called (a plain word blocks only under a key that names a secret, as above). In any other name hit (code, shell, documentation) only
  a line starting `export KEY=value` is judged that way, so a document with
  `updated: 2026-11-25` in its front matter or a script with
  `const base = basename(path)` commits. Examples that block:
  `export DB_PASS=...`, YAML `DB_PASS: ...` or `- stripe: ...`, JSON
  `"stripe": "..."`, TOML and a commented `# STRIPE_KEY=...` block when
  the value is credential-shaped. A label with a space, a reference, a
  placeholder, a plain word under a key that names no secret, a URL, an empty value and prose pass.
- Real dotenv files (basename `.env`, `.env.<anything>` or `<name>.env`, but
  not the template forms `.env.example`, `.env.sample`, `.env.template`,
  `.env.dist` and `.env.defaults`): every `KEY=value` line (an `export`
  prefix and quotes allowed) is judged whatever the key is called, so `DB_PASS`, `MYSQL_PWD`, `ENCRYPTION_KEY`, `STRIPE_KEY` and
  `JWT_SIGNING_KEY` holding a credential-shaped value block like `PASSWORD` does. A plain word blocks there only under a key that names a secret. Plain settings (`NODE_ENV=production`, `PORT=3000`, `LOG_LEVEL=debug`,
  a URL without credentials), empty values, placeholders and references still
  pass. A commented assignment (`# STRIPE_KEY=...`) is judged like any other
  line; a comment without an assignment passes. A template form keeps the
  keyword-key rule only.
- Binary blobs: a NUL byte is replaced by a newline before the rules run, so a
  credential on the same line after a NUL byte is found under every awk.

The allowlist is the project-owned, committed file
`docs/ai/secrets-allowlist.txt`. It is never written, seeded or deleted by
sync or update. One entry per line; blank lines and lines starting with `#`
are ignored:

- `path <glob>`: a bash pattern matched against the whole repo-relative path
  (`*` also matches `/`, `?` one character, `[...]` a class). Every finding in
  a matching file is allowed, key files included.
- `fingerprint <hex>`: 40 or 64 lowercase hex digits. Only the one finding with
  that fingerprint is allowed.

A catch-all `path` glob (one that matches every path, such as `*`, `**`,
`**/*`, `*.*`, `?*` or `[a-z]*`, or one with no literal character outside
wildcards, slashes and bracket expressions, such as the negated class
`[!z]*` or `[!]z]*`; a `]` right after `[` or `[!`, and a `[:digit:]` class,
belong to the same bracket expression) and any line that is not a valid entry block
the commit with `Secrets allowlist line <n>: ...`, so a mistake is loud. The
file is read from the index: an untracked file or an unstaged edit has no
effect, and a commit that stages the file uses the staged version. Allowed
findings are counted in one line, `Secrets allowlist: <n> finding(s) allowed
by docs/ai/secrets-allowlist.txt`.

Every finding prints its line number and a fingerprint, never the value:

```
✗ Potential secret detected in config/app.yml
    line 12, fingerprint 8d0f35c0f15c4363306e1927a9dda8278105b2c8
```

At most 3 lines are shown per file, then `... and <k> more`. To compute the
fingerprint of a line yourself, run
`printf '%s\n%s' <path> <line> | git hash-object --stdin`, where `<line>` is
the line with leading and trailing blanks and a trailing carriage return
removed. It binds the exemption to that file and that exact text, so editing
the line or moving the file needs a new review. To exempt a whole file, add a
`path` entry and review it in the pull request like any other change.

## Data model

One project-owned text file, `docs/ai/secrets-allowlist.txt`, UTF-8, LF or
CRLF, no size limit. It is listed in `.aai/system/DOCS_AI_CANON.list` so the
docs audit does not report it. Nothing else is stored.

## Interfaces and contracts

- Exit code: `bash .aai/scripts/pre-commit-checks.sh` exits 1 when CHECK 2
  finds a secret or the allowlist is malformed, as before.
- Output lines: `Potential secret detected in <path>` (followed by the detail
  lines above), `Sensitive file staged: <path>`, `Secrets allowlist: <n>
  finding(s) allowed by docs/ai/secrets-allowlist.txt` and `Secrets allowlist
  line <n>: ...`. A clean run prints `No secrets detected in staged files`
  exactly as before.
- The rules run in bash and one POSIX awk program (no Node, no new
  dependency), under `LC_ALL=C`, with one `git hash-object` process only when
  a finding needs a fingerprint.

## Limits and non-goals

- A value that begins with `$` is read as a variable reference (`$VAR`), so a literal password that starts with `$` (a bcrypt hash, a human password) is never a finding; the shape cannot tell the two apart.
- A word-like value (letters only) under a non-keyword key, and any value
  shorter than 8 bytes, pass in every file, including a real `.env`; they stay
  exempt there so that `NODE_ENV=production` and `LOG_LEVEL=debug` commit.
  Under a keyword key a lowercase word such as `correcthorsebattery` blocks;
  a plain setting under a keyword key (a token type named `authorization`)
  blocks too and needs an allowlist entry.
  Before this change every `.env` blocked by name.
- Over-blocking of plain settings: a real `.env`, and any other name-hit
  file that is not a template, blocks a line whose value is credential-shaped
  but harmless, for example `HOST=127.0.0.1`, `DATA_DIR=/var/lib/app`,
  `TZ=Europe/Prague`, `MAX_UPLOAD=10485760`, `APP_VERSION=1.2.3-beta`,
  `LANG=en_US.UTF-8` or a date. The remedy is a `path` or `fingerprint`
  allowlist entry. Before this change every such file blocked by name. A
  template form (`.env.example` and the like) holding a real value under a key
  that names no secret passes.
- A private key whose base64 body begins after more than 40 characters of
  other text on the marker line, or is split into lines shorter than 40
  characters right after the marker line, is not found.
- An unquoted value followed by more words is judged by its first word only.
- A credential under a non-keyword key in a code or documentation file named
  `*secret*` or `*credentials*`, other than an `export` line, passes.
- The awk program is portable POSIX awk, but this host test runs it under the
  awks on its PATH; the mawk and gawk legs rest on the hosted Linux run.
- A credential in an unquoted value outside a name-hit file (a YAML key
  without quotes) is not detected, as before.
- A bare token in a name-hit text file without a key, and not a key-file
  extension, passes; before this change it blocked by name.
- A fake but well-formed AWS key or GitHub token now blocks until its file is
  allowlisted.
- A `path` glob narrower than a catch-all but still broad, for example
  `*.json`, is accepted; it is visible in review because the allowlist is
  committed.
- In a name-hit file a key name followed by a colon and a long unbroken
  string reads as a keyed value, for example a documentation line that cites a
  script name and a line range; such a file needs a `path` entry.
- No entropy scoring; no scan of the history or the working tree.

## Links

- Request: docs/issues/ISSUE-DRAFT-secrets-gate-false-positives.md
- Spec: docs/specs/SPEC-DRAFT-secrets-gate-false-positives.md
- Validation evidence: docs/ai/reports/ (written by the validation role)
