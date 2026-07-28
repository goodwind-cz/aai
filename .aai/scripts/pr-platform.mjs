#!/usr/bin/env node
// pr-platform.mjs — deterministic git-host platform probe
// (CHANGE-DRAFT-platform-portable-pr / SPEC-DRAFT-spec-platform-portable-pr).
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
// CLI: node pr-platform.mjs [--remote-url <url>] [--json]
//   --remote-url <url>  use this string instead of running
//                        `git remote get-url origin` (test/dry-run override).
//                        An empty string is treated the same as no remote.
//   --json               print a JSON object instead of the text line.
//
// Output (text mode, default):
//   PLATFORM <github|azure|unknown> remote=<sanitized-url>
//   PLATFORM none                                  (no remote at all)
//
// Output (--json mode):
//   {"platform":"<github|azure|unknown|none>","remote":<string|null>,
//    "sanitizedRemote":<string|null>}
//
// Exit codes (closed set; read-only, so every classified outcome is 0):
//   0  classification printed (github / azure / unknown / none)
//   2  usage error (unknown flag / missing flag value) — nothing printed

import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(msg) {
  console.error(`pr-platform: ${msg}`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { remoteUrl: null, json: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--remote-url') {
      const v = argv[i + 1];
      if (v === undefined) fail('--remote-url requires a value');
      opts.remoteUrl = v;
      i += 1;
    } else if (tok === '--json') {
      opts.json = true;
    } else if (tok === '-h' || tok === '--help') {
      console.log('Usage: node pr-platform.mjs [--remote-url <url>] [--json]');
      process.exit(0);
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
  return remoteUrl.replace(/^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/)[^@/]*@/, '$1');
}

function main() {
  const opts = parseArgs(process.argv);
  const remoteUrl = opts.remoteUrl !== null ? (opts.remoteUrl || null) : readOriginUrl();

  if (!remoteUrl) {
    if (opts.json) {
      console.log(JSON.stringify({ platform: 'none', remote: null, sanitizedRemote: null }, null, 2));
    } else {
      console.log('PLATFORM none');
    }
    process.exit(0);
  }

  const host = extractHost(remoteUrl);
  const platform = classify(host);
  const sanitizedRemote = sanitize(remoteUrl);

  if (opts.json) {
    // NEVER emit the raw remote: an https origin routinely carries embedded
    // credentials (x-access-token:ghp_... from credential helpers/CI) and
    // --json output lands in ceremony/CI logs (PR review finding).
    console.log(JSON.stringify({ platform, remote: sanitizedRemote }, null, 2));
  } else {
    console.log(`PLATFORM ${platform} remote=${sanitizedRemote}`);
  }
  process.exit(0);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) main();

export { classify, extractHost, sanitize };
