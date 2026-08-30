#!/usr/bin/env node
// pr-platform.mjs — deterministic git-host platform probe
// (CHANGE-0085-platform-portable-pr / SPEC-0103-spec-platform-portable-pr).
//
// SKILL_PR's step 5 PLATFORM GATE runs this FIRST, before any PR-mechanics
// branch. It reads `git remote get-url origin` (or an explicit --remote-url
// override, for tests and dry-runs) and classifies the host deterministically
// into one of a CLOSED set — github | azure | unknown | none. It NEVER
// guesses: any host that is not a recognized GitHub or Azure DevOps pattern
// is `unknown`, never silently treated as either.
//
// Recognized host patterns:
//   github  — github.com (https://github.com/... and ssh git@github.com:...,
//             including ssh://git@github.com/...)
//   azure   — dev.azure.com, ssh.dev.azure.com (current Azure DevOps), and
//             *.visualstudio.com (legacy Azure DevOps hostnames)
//   none    — no `origin` remote configured at all (bare/fresh repo)
//   unknown — every other host (gitlab.com, bitbucket.org, self-hosted, ...)
//
// Read-only: never writes any file, never mutates git state.
//
// R1 GitHub-no-bots hardening (CHANGE-DRAFT-github-no-bots-hardening, follow-up
// to CHANGE-0085/SPEC-0103): the probe also reports whether reviewer bots are
// EXPECTED for this repo, from a repo-local declaration in
// docs/ai/pr-config.yaml `reviewer_bots:` (column-0 line scan, same discipline
// as docs-audit.yaml / update-config.yaml). This lets SKILL_PR's 5d bot-review
// sweep avoid waiting for Copilot/Codex comments that will NEVER arrive on a
// GitHub repo where no reviewer bots are installed. Closed tri-state:
//   expected — declared `reviewer_bots: expected`; the bot-sweep path applies.
//   none     — declared `reviewer_bots: none`, OR the file/key is ABSENT
//              (assume-none: the SAFEST default — SKILL_PR substitutes the
//              internal review rather than block on bots that may not exist).
//   unknown  — the key is present with an unrecognized value (typo); a stderr
//              warning is printed and it is treated as `none` (fail-open,
//              never a silent skip and never an infinite wait).
//
// CLI: node pr-platform.mjs [--remote-url <url>] [--pr-config <path>] [--json]
//   --remote-url <url>  use this string instead of running
//                        `git remote get-url origin` (test/dry-run override).
//                        An empty string is treated the same as no remote.
//   --pr-config <path>  read the reviewer_bots knob from this file instead of
//                        <repo-root>/docs/ai/pr-config.yaml (test/dry-run
//                        override). An absent file classifies reviewer_bots
//                        as `none` (assume-none).
//   --json               print a JSON object instead of the text line.
//
// Output (text mode, default):
//   PLATFORM <github|azure|unknown> remote=<sanitized-url> reviewer_bots=<v>
//   PLATFORM none                                  (no remote at all)
//
// Output (--json mode):
//   {"platform":"<github|azure|unknown|none>","remote":<string|null>,
//    "reviewer_bots":"<expected|none|unknown>"}
//
// Exit codes (closed set; read-only, so every classified outcome is 0):
//   0  classification printed (github / azure / unknown / none)
//   2  usage error (unknown flag / missing flag value) — nothing printed

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

function fail(msg) {
  console.error(`pr-platform: ${msg}`);
  exit(2);
}

function parseArgs(argv) {
  const opts = { remoteUrl: null, prConfig: null, json: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--remote-url') {
      const v = argv[i + 1];
      if (v === undefined) fail('--remote-url requires a value');
      opts.remoteUrl = v;
      i += 1;
    } else if (tok === '--pr-config') {
      const v = argv[i + 1];
      if (v === undefined) fail('--pr-config requires a value');
      opts.prConfig = v;
      i += 1;
    } else if (tok === '--json') {
      opts.json = true;
    } else if (tok === '-h' || tok === '--help') {
      console.log('Usage: node pr-platform.mjs [--remote-url <url>] [--pr-config <path>] [--json]');
      exit(0);
    } else {
      fail(`unknown flag "${tok}"`);
    }
  }
  return opts;
}

// Read `git remote get-url origin` from the current working directory. git
// itself walks up from cwd to the repo root, so this is cwd-independent —
// no --show-toplevel resolution needed. Returns null on any failure (not a
// git repo, no `origin` remote, git not installed): all fold into `none`.
function readOriginUrl() {
  try {
    const out = execFileSync('git', ['remote', 'get-url', 'origin'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out === '' ? null : out;
  } catch {
    return null;
  }
}

// Resolve the git repo root (`git rev-parse --show-toplevel`) so the default
// pr-config path is cwd-independent, mirroring readOriginUrl. Returns null on
// any failure (not a git repo, git missing); the caller then falls back to cwd.
function readRepoRoot() {
  try {
    const out = execFileSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out === '' ? null : out;
  } catch {
    return null;
  }
}

// Read the repo-local reviewer_bots knob (R1 GitHub-no-bots hardening). A
// COLUMN-0 line scan of docs/ai/pr-config.yaml — NOT a general YAML parser —
// exactly the discipline of guard-config.mjs / update-check.mjs. Returns the
// closed tri-state 'expected' | 'none' | 'unknown':
//   - absent file / absent key  -> 'none' (assume-none, the safest default)
//   - `reviewer_bots: expected` -> 'expected'
//   - `reviewer_bots: none`     -> 'none'
//   - any other value           -> 'unknown' + a stderr warning (fail-open:
//                                   behaves like 'none' downstream, so a typo
//                                   never silently waits for bots nor skips
//                                   review)
function readReviewerBots(cfgPath, warn = (m) => console.error(m)) {
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return 'none'; // absent file: assume-none, silently
  }
  for (const line of raw.split(/\r?\n/)) {
    // column-0 key only (an indented or commented key is never a dial); the
    // value is the ENTIRE rest of the line, trimmed, and must EXACTLY equal a
    // closed-set token — trailing garbage ("expected extra", a glued or
    // trailing comment) must NOT silently enable the bot-only path, so any
    // non-exact value falls open to unknown WITH a warning (internal review).
    const m = line.match(/^reviewer_bots:(.*)$/);
    if (!m) continue;
    const v = m[1].trim();
    if (v === 'expected') return 'expected';
    if (v === 'none') return 'none';
    warn(`pr-platform: WARNING reviewer_bots value "${v}" in ${cfgPath} is `
      + 'not "expected" or "none" — treating as unknown (fail-open: internal '
      + 'review substituted, sweep never waits for bots)');
    return 'unknown';
  }
  return 'none'; // key absent: assume-none
}

// Extract the lowercase hostname from an SSH scp-like URL (`[user@]host:path`,
// no `://`) or any URL with an explicit scheme (`scheme://[user[:pass]@]host
// [:port]/path`, including bare `host:port/path` treated as ssh). Returns
// null when no host can be determined.
function extractHost(remoteUrl) {
  if (!remoteUrl) return null;
  const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(remoteUrl);
  if (!hasScheme) {
    // scp-like syntax: [user@]host:path — host is before the FIRST colon,
    // and there must be no '/' before that colon (a bare relative/absolute
    // filesystem path has neither).
    const m = remoteUrl.match(/^(?:[^@/:]+@)?([^:/]+):(.+)$/);
    if (m) return m[1].toLowerCase();
    return null;
  }
  try {
    const u = new URL(remoteUrl);
    return u.hostname ? u.hostname.toLowerCase() : null;
  } catch {
    return null;
  }
}

// Deterministic, closed classification. Anything not explicitly matched is
// `unknown` — never a guess.
function classify(host) {
  if (!host) return 'unknown';
  if (host === 'github.com' || host.endsWith('.github.com')) return 'github';
  if (
    host === 'dev.azure.com' ||
    host === 'ssh.dev.azure.com' ||
    host === 'visualstudio.com' ||
    host.endsWith('.visualstudio.com')
  ) {
    return 'azure';
  }
  return 'unknown';
}

// Mask HTTPS basic-auth credentials (`https://user:pass@host/...`) without
// touching SSH `user@host:` forms (that "user" — typically `git` — is a
// public identity, not a secret).
function sanitize(remoteUrl) {
  if (!remoteUrl) return null;
  // Strip the ENTIRE userinfo, including passwords containing unescaped '@'
  // (https://u:p@ss@host parses; a first-@ regex would leak 'ss@host…' —
  // PR #185 Codex P1): greedy [^/]*@ consumes through the LAST @ before the
  // first path slash.
  return remoteUrl.replace(/^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/)[^/]*@/, '$1');
}

function main() {
  const opts = parseArgs(process.argv);
  const remoteUrl = opts.remoteUrl !== null ? (opts.remoteUrl || null) : readOriginUrl();

  if (!remoteUrl) {
    // No remote -> GENERIC MODE, no PR ceremony, so no bot layer either: the
    // text line stays bare (byte-stable contract), --json reports reviewer_bots
    // as 'none' (internal review is mandatory in GENERIC MODE regardless).
    if (opts.json) {
      console.log(JSON.stringify({ platform: 'none', remote: null, reviewer_bots: 'none' }, null, 2));
    } else {
      console.log('PLATFORM none');
    }
    exit(0);
  }

  const host = extractHost(remoteUrl);
  const platform = classify(host);
  const sanitizedRemote = sanitize(remoteUrl);
  const prConfigPath = opts.prConfig !== null
    ? opts.prConfig
    : path.join(readRepoRoot() ?? process.cwd(), 'docs/ai/pr-config.yaml');
  const reviewerBots = readReviewerBots(prConfigPath);

  if (opts.json) {
    // NEVER emit the raw remote: an https origin routinely carries embedded
    // credentials (x-access-token:ghp_... from credential helpers/CI) and
    // --json output lands in ceremony/CI logs (PR review finding).
    console.log(JSON.stringify({ platform, remote: sanitizedRemote, reviewer_bots: reviewerBots }, null, 2));
  } else {
    console.log(`PLATFORM ${platform} remote=${sanitizedRemote} reviewer_bots=${reviewerBots}`);
  }
  exit(0);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) runMain(() => main());

export { classify, extractHost, sanitize, readReviewerBots };
