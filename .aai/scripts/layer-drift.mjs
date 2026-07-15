#!/usr/bin/env node
// Vendored-layer drift check (CHANGE doctor-vendored-layer-drift /
// SPEC spec-doctor-vendored-layer-drift) — compares the AAI pin's
// `Template commit` against the canonical repo's tip and reports drift with
// HONEST distance tiers. Read-only; never modifies anything; strictly
// degrade-and-report (offline / no pin -> info verdict, never a crash).
//
// Canonical remote resolution order (D2 — first hit wins):
//   1. --remote <url-or-path>              (tests / CI / operator override)
//   2. pin "- Canonical repo: <url>"       (stamped by aai-sync going forward)
//   3. pin "- Source path: <dir>"          (pre-contract pins; used when the
//                                           directory exists and is a git repo)
//   4. nothing -> unverifiable (run /aai-update to restamp the pin)
// Placeholder values (`<set by sync script>`, `UNKNOWN`) are treated as absent.
// There is deliberately NO hardcoded upstream fallback: a fork-vendored
// project must never be compared against the wrong repo.
//
// Distance tiers (D3 — never lie about N):
//   LOCAL  (resolved target is an existing local git dir): full verdict —
//          equal / BEHIND by N (rev-list --count) / ahead / diverged.
//   REMOTE (resolved target is a URL): git ls-remote proves only (in)equality
//          -> equal, or drift with UNKNOWN distance. No fetch is performed.
//   OFFLINE: ls-remote failure/timeout -> unverifiable.
//
// Usage:
//   layer-drift [--pin <path>] [--remote <url-or-path>] [--ref <name>]
//               [--timeout-ms <n>] [--json]
//   --pin defaults to .aai/system/AAI_PIN.md under the current directory.
//   --ref defaults to "main". --timeout-ms bounds each git call (default 10000).
//
// Exit codes (callers branch; doctor maps ALL of them to non-blocking lines):
//   0  up-to-date (or pin ahead of canonical — synced from unmerged work)
//   2  usage error (unknown flag / missing value)
//   3  drift detected (behind by N / behind unknown distance / diverged)
//   4  unverifiable (no pin, placeholder pin, no canonical remote, offline)
//
// --json prints one object:
//   { status: "up_to_date"|"behind"|"unverifiable",
//     relation: "equal"|"behind"|"ahead"|"diverged"|"unknown",
//     pin_commit, canonical_head, ref, remote,
//     source: "cli"|"pin_canonical_repo"|"pin_source_path"|"none",
//     distance: <int|null>, message: "<human verdict line>" }

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const DEFAULT_TIMEOUT_MS = 10_000;
const PLACEHOLDER_RE = /^<.*>$/;

function usage() {
  console.error(
    'Usage: layer-drift [--pin <path>] [--remote <url-or-path>] [--ref <name>]\n' +
    '                   [--timeout-ms <n>] [--json]\n' +
    '  Compares the AAI pin commit against the canonical repo tip.\n' +
    '  Exit: 0 up-to-date/ahead | 3 drift | 4 unverifiable | 2 usage.',
  );
}

function fail(msg) {
  console.error(`layer-drift: ${msg}`);
  usage();
  process.exit(2);
}

function parseArgs(argv) {
  const args = {
    pin: path.join(process.cwd(), '.aai/system/AAI_PIN.md'),
    remote: null,
    ref: 'main',
    timeoutMs: DEFAULT_TIMEOUT_MS,
    json: false,
  };
  const toks = argv.slice(2);
  for (let i = 0; i < toks.length; i++) {
    const tok = toks[i];
    const need = (name) => {
      const v = toks[++i];
      if (v === undefined || v.startsWith('--')) fail(`${name} needs a value`);
      return v;
    };
    if (tok === '--pin') args.pin = path.resolve(need('--pin'));
    else if (tok === '--remote') args.remote = need('--remote');
    else if (tok === '--ref') args.ref = need('--ref');
    else if (tok === '--timeout-ms') {
      const n = Number.parseInt(need('--timeout-ms'), 10);
      if (!Number.isInteger(n) || n <= 0) fail('--timeout-ms must be a positive integer');
      args.timeoutMs = n;
    } else if (tok === '--json') args.json = true;
    else fail(`unknown flag: ${tok}`);
  }
  return args;
}

// --- Pin parsing (pure) -------------------------------------------------------

// Extract "- <Key>: <value>" fields from the pin body. CRLF-tolerant.
// Placeholder ("<set by sync script>") and "UNKNOWN" values -> undefined.
export function parsePin(text) {
  const fields = {};
  for (const rawLine of text.split('\n')) {
    const line = rawLine.replace(/\r$/, '');
    const m = line.match(/^-\s*(Source path|Template version|Template commit|Canonical repo|Synced at \(UTC\))\s*:\s*(.*)$/);
    if (!m) continue;
    const value = m[2].trim();
    if (!value || value === 'UNKNOWN' || PLACEHOLDER_RE.test(value)) continue;
    fields[m[1]] = value;
  }
  return {
    sourcePath: fields['Source path'],
    version: fields['Template version'],
    commit: fields['Template commit'],
    canonicalRepo: fields['Canonical repo'],
    syncedAt: fields['Synced at (UTC)'],
  };
}

// --- git plumbing (bounded, prompt-free) --------------------------------------

function git(argsArr, timeoutMs) {
  const res = spawnSync('git', argsArr, {
    encoding: 'utf8',
    timeout: timeoutMs,
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
  });
  return {
    ok: res.status === 0 && !res.error,
    stdout: (res.stdout || '').trim(),
    timedOut: res.error?.code === 'ETIMEDOUT',
  };
}

// Is `target` a local directory git accepts as a repository?
function localGitDir(target, timeoutMs) {
  if (!target || /^[a-z][a-z0-9+.-]*:\/\//i.test(target) || /^[^/@:]+@[^/:]+:/.test(target)) return null;
  const dir = path.resolve(target);
  if (!fs.existsSync(dir)) return null;
  return git(['-C', dir, 'rev-parse', '--git-dir'], timeoutMs).ok ? dir : null;
}

// --- Verdict construction (pure over probe results) ---------------------------

function verdict(overrides) {
  return {
    status: 'unverifiable',
    relation: 'unknown',
    pin_commit: null,
    canonical_head: null,
    ref: null,
    remote: null,
    source: 'none',
    distance: null,
    message: '',
    exit: 4,
    ...overrides,
  };
}

export function decide({ pinExists, pin, cliRemote, ref, probe }) {
  if (!pinExists) {
    return verdict({
      message: 'layer drift unverifiable (no .aai/system/AAI_PIN.md — not a vendored project, or never synced)',
    });
  }
  if (!pin.commit) {
    return verdict({
      message: 'layer drift unverifiable (pin not stamped — template repo or never synced; run /aai-update in a vendored project)',
    });
  }
  // D2 resolution order.
  let remote = null;
  let source = 'none';
  if (cliRemote) { remote = cliRemote; source = 'cli'; }
  else if (pin.canonicalRepo) { remote = pin.canonicalRepo; source = 'pin_canonical_repo'; }
  else if (pin.sourcePath) { remote = pin.sourcePath; source = 'pin_source_path'; }
  if (!remote) {
    return verdict({
      pin_commit: pin.commit,
      message: 'layer drift unverifiable (pin lacks a canonical remote — run /aai-update to restamp the pin)',
    });
  }
  return probe(remote, source, pin.commit, ref);
}

function probeCanonical(remote, source, pinCommit, ref, timeoutMs) {
  const short = (sha) => (sha || '').slice(0, 7);
  const localDir = localGitDir(remote, timeoutMs);

  if (localDir) {
    // Tier LOCAL — full verdict.
    const head = git(['-C', localDir, 'rev-parse', `${ref}^{commit}`], timeoutMs);
    if (!head.ok) {
      return verdict({
        pin_commit: pinCommit, ref, remote, source,
        message: `layer drift unverifiable (canonical ref '${ref}' not found in ${localDir})`,
      });
    }
    const base = {
      pin_commit: pinCommit, canonical_head: head.stdout, ref, remote, source,
    };
    const pinResolved = git(['-C', localDir, 'rev-parse', `${pinCommit}^{commit}`], timeoutMs);
    if (!pinResolved.ok) {
      return verdict({
        ...base, status: 'behind', relation: 'unknown', exit: 3,
        message: `layer drift: pin ${short(pinCommit)} not found in canonical '${ref}' history (unknown distance) — run /aai-update`,
      });
    }
    const pinSha = pinResolved.stdout;
    if (pinSha === head.stdout) {
      return verdict({
        ...base, status: 'up_to_date', relation: 'equal', distance: 0, exit: 0,
        message: `layer up-to-date (pin ${short(pinSha)} == canonical ${ref})`,
      });
    }
    if (git(['-C', localDir, 'merge-base', '--is-ancestor', pinSha, head.stdout], timeoutMs).ok) {
      const count = git(['-C', localDir, 'rev-list', '--count', `${pinSha}..${head.stdout}`], timeoutMs);
      const n = count.ok ? Number.parseInt(count.stdout, 10) : null;
      return verdict({
        ...base, status: 'behind', relation: 'behind', distance: Number.isInteger(n) ? n : null, exit: 3,
        message: `layer BEHIND canonical ${ref} by ${Number.isInteger(n) ? n : '?'} commit(s) — run /aai-update`,
      });
    }
    if (git(['-C', localDir, 'merge-base', '--is-ancestor', head.stdout, pinSha], timeoutMs).ok) {
      return verdict({
        ...base, status: 'up_to_date', relation: 'ahead', exit: 0,
        message: `layer pin ${short(pinSha)} is AHEAD of canonical ${ref} (synced from unmerged work) — no update needed`,
      });
    }
    return verdict({
      ...base, status: 'behind', relation: 'diverged', exit: 3,
      message: `layer drift: pin ${short(pinSha)} DIVERGED from canonical ${ref} (unknown distance) — run /aai-update`,
    });
  }

  // Tier REMOTE — ls-remote proves only (in)equality.
  const ls = git(['ls-remote', remote, `refs/heads/${ref}`, ref], timeoutMs);
  const headSha = ls.ok ? (ls.stdout.split('\n')[0] || '').split('\t')[0] : '';
  if (!ls.ok || !/^[0-9a-f]{40,64}$/.test(headSha)) {
    return verdict({
      pin_commit: pinCommit, ref, remote, source,
      message: `layer drift unverifiable (offline or canonical unreachable: ${remote})${ls.timedOut ? ' [timeout]' : ''}`,
    });
  }
  const base = { pin_commit: pinCommit, canonical_head: headSha, ref, remote, source };
  if (headSha === pinCommit) {
    return verdict({
      ...base, status: 'up_to_date', relation: 'equal', distance: 0, exit: 0,
      message: `layer up-to-date (pin ${short(pinCommit)} == canonical ${ref})`,
    });
  }
  return verdict({
    ...base, status: 'behind', relation: 'unknown', exit: 3,
    message: `layer differs from canonical ${ref} (unknown distance — canonical not locally reachable) — run /aai-update`,
  });
}

// --- CLI -----------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv);
  const pinExists = fs.existsSync(args.pin);
  const pin = pinExists ? parsePin(fs.readFileSync(args.pin, 'utf8')) : {};
  const result = decide({
    pinExists,
    pin,
    cliRemote: args.remote,
    ref: args.ref,
    probe: (remote, source, pinCommit, ref) =>
      probeCanonical(remote, source, pinCommit, ref, args.timeoutMs),
  });
  if (args.json) {
    const { exit, ...jsonOut } = result;
    console.log(JSON.stringify(jsonOut, null, 2));
  } else {
    console.log(result.message);
  }
  process.exit(result.exit);
}

// Allow `import { parsePin, decide }` from tests without running the CLI.
// Review B1: compare DECODED, SYMLINK-RESOLVED paths. Two failure layers were
// found here: (1) `new URL(...).pathname` is percent-encoded, so a project
// path containing a space never matched argv; (2) node resolves symlinks for
// import.meta.url but argv keeps the invoked spelling (macOS /tmp ->
// /private/tmp), so even decoded paths can differ. Either way the CLI
// silently exited 0, which doctor CAT-13 would read as "up-to-date".
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main();
}
