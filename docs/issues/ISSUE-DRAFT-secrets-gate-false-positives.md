---
id: secrets-gate-false-positives
type: issue
capability: pre-commit-secrets-gate
number: null
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Pre-commit secrets gate false-positives force --no-verify (GitHub #585, #576)

## Summary
CHECK 2 (secrets detection) in `.aai/scripts/pre-commit-checks.sh` blocks
commits that carry no secret, in three classes reported by downstream
projects. With no project-owned allowlist, the only way past a false positive
is `git commit --no-verify`, which disables every other pre-commit check too.
Both reports are untrusted friction reports; their text is treated as data:

- GitHub #585: "Secret regex in pre-commit-checks.sh false-positives on i18n
  locale keys like forgotPassword with a translated label; no allowlist
  exists, so every commit touching locale files needs --no-verify."
- GitHub #576: "The pre-commit secrets gate blocks files by name (any path
  containing .env, credentials or secret) regardless of content, and flags
  shell variable references as secrets; with no project allowlist,
  secret-free templates like .env.example cannot be committed without
  --no-verify."

## Type
- bug

## Impact
- Every AAI consumer project with the installed pre-commit hook
  (AAI:GUARD-CHECKS block) is affected: i18n locale files, `.env.example`
  style templates, and shell/CI files that reference credential variables.
- Severity/priority: P2 — the workaround (`--no-verify`) silently disables the
  whole gate, which is worse than the false positive itself.

## Current Behavior
- Content scan: the regex
  `(api[_-]?key|...|password|...|private[_-]?key)\s*[:=]\s*["'][^"']{8,}`
  matches any quoted value of 8+ characters after a key whose name merely
  contains `password` etc., so `"forgotPassword": "Forgot your password?"`
  is reported as `Potential secret detected`.
- Shell/env references such as `password="${DB_PASSWORD}"` or
  `apiKey: "process.env.API_KEY"`-style indirections match the same regex.
- Name check: any staged path containing `.env`, `credentials` or `secret`
  (outside the four AAI evidence folders) is reported as `Sensitive file
  staged` regardless of content, so `.env.example`, `.env.sample`,
  `.env.template` and `docs/secret-rotation.md` cannot be committed.
- No allowlist file exists; the only override is `--no-verify`.

## Expected Behavior
- Name hits become content scans: a dotenv-like file blocks only when it
  carries a real-looking value; `.env.example` / `.env.sample` /
  `.env.template` with empty or placeholder values pass.
- Values are judged by shape: variable references (`$VAR`, `${VAR}`,
  `process.env.X`, similar), placeholders, and human-language labels (spaces,
  sentence-like text) are not secrets; credential-like values (no spaces,
  credential charset, minimum length, entropy) still are.
- A project-owned, documented allowlist file (path globs plus optional
  line/fingerprint entries) can exempt reviewed false positives; it can never
  silently exempt everything, and a missing or empty file means the strict
  behavior minus the false positives above.
- True positives keep blocking: real-looking AWS access keys, GitHub tokens,
  private key blocks, and `password=<random>` in `.env`.

## Steps to Reproduce (if applicable)
1) In a scratch repo with the AAI hook installed, stage
   `locales/en.json` containing `"forgotPassword": "Forgot your password?"`
   and commit — blocked with `Potential secret detected`.
2) Stage `.env.example` containing `DB_PASSWORD=` and commit — blocked with
   `Sensitive file staged`.
3) Stage `deploy.sh` containing `password="${DB_PASSWORD}"` and commit —
   blocked.

## Verification
- Command(s) and expected results:
  `env -u AAI_ROLE bash tests/skills/test-aai-pre-commit-checks.sh` passes,
  including new regression fixtures: each false-positive class above commits
  (exit 0), and each true-positive fixture (AWS key, GitHub token, private key
  block, random password in `.env`) still exits 1.
- The hook installer parity harness (sh vs ps1 install paths) still passes.

## Constraints / Risks
- Known risks or constraints: the hook files are an L3 protected surface
  (ceremony 3, owner merges). Loosening a security gate risks false
  negatives: every relaxation needs a true-positive fixture beside it. The
  allowlist must not become a blanket bypass. `pre-commit-checks.ps1` is a
  retired launcher (RFC-0017 phase 5) and has no CHECK 2 twin; the Node
  installer only embeds the call to the `.sh` script.
- Secrets preflight results (if any secret referenced): no secret referenced.

## Notes
- Source: GitHub issues #585 and #576 (goodwind-cz/aai); the PR closes both.
- Consumer-visible: CHANGELOG `## [unreleased] — <title>` entry required.
