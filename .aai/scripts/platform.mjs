#!/usr/bin/env node
// platform.mjs — record the git host platform (spec-git-platform-detected-at-bootstrap).
//
//   node .aai/scripts/platform.mjs record [--repo-root <dir>] [--remote-url <url>]
//                                         [--force] [--dry-run]
//
// record classifies origin with pr-platform.mjs's classifier and keeps ONE
// column-0 `platform:` line in docs/ai/pr-config.yaml (D2). It never
// overwrites a differing value without --force, then prints one AUTH line
// (D3) that never changes the exit code or the file.
//
// Exit codes: 0 recorded / unchanged / would-record, 2 usage, 6 MISMATCH.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { sanitize } from './pr-platform.mjs';
import {
  PR_CONFIG_REL, authStatus, detectPlatform, isMismatch, readRecordedPlatform,
} from './lib/platform-adapter.mjs';

const USAGE = 'Usage: node platform.mjs record [--repo-root <dir>] [--remote-url <url>] [--force] [--dry-run]';
const NEW_FILE_HEADER = [
  '# AAI PR-ceremony policy (docs/ai/pr-config.yaml). Parsed by a COLUMN-0 line scan; keep keys at column 0.',
  '# platform: github | azure | unknown | none -- the git host, recorded by',
  '# `node .aai/scripts/platform.mjs record` (re-record a changed origin with --force).',
];

function usageError(msg) {
  console.error(`platform: ${msg}`);
  console.error(USAGE);
  exit(2);
}

function parseRecordArgs(args) {
  const opts = { repoRoot: null, remoteUrl: undefined, force: false, dryRun: false };
  for (let i = 0; i < args.length; i += 1) {
    const tok = args[i];
    if (tok === '--repo-root' || tok === '--remote-url') {
      if (args[i + 1] === undefined) usageError(`${tok} requires a value`);
      if (tok === '--repo-root') opts.repoRoot = args[i + 1]; else opts.remoteUrl = args[i + 1];
      i += 1;
    } else if (tok === '--force') opts.force = true;
    else if (tok === '--dry-run') opts.dryRun = true;
    else usageError(`unknown flag "${tok}"`);
  }
  return opts;
}

function gitToplevel() {
  try {
    const out = execFileSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out || null;
  } catch {
    return null;
  }
}

function eolOf(text) {
  return text.includes('\r\n') ? '\r\n' : '\n';
}

// Replace only the first column-0 `platform:` line, keeping its line ending.
function rewritePlatformLine(text, value) {
  const parts = text.split(/(\r?\n)/);
  for (let i = 0; i < parts.length; i += 2) {
    if (/^platform:/.test(parts[i])) {
      parts[i] = `platform: ${value}`;
      break;
    }
  }
  return parts.join('');
}

function appendPlatformLine(text, value) {
  const eol = eolOf(text);
  const sep = text === '' || text.endsWith('\n') ? '' : eol;
  return `${text}${sep}platform: ${value}${eol}`;
}

function runRecord(args) {
  const opts = parseRecordArgs(args);
  const repoRoot = path.resolve(opts.repoRoot || gitToplevel() || process.cwd());
  const cfg = path.join(repoRoot, PR_CONFIG_REL);
  const detected = detectPlatform({ repoRoot, remoteUrl: opts.remoteUrl });
  const recorded = readRecordedPlatform(repoRoot);
  const mismatch = isMismatch(recorded, detected);
  let after = detected;
  let code = 0;
  let line;

  if (mismatch && !opts.force) {
    line = `MISMATCH recorded=${recorded} detected=${detected} re-record: node .aai/scripts/platform.mjs record --force`;
    code = 6;
    after = detected;
  } else if (recorded !== null && !mismatch) {
    line = `UNCHANGED platform=${recorded}`;
    after = recorded;
  } else if (opts.dryRun) {
    const remote = sanitize(opts.remoteUrl !== undefined ? opts.remoteUrl : null);
    line = `WOULD-RECORD platform=${detected}${recorded !== null ? ` (was ${recorded})` : ''}${remote ? ` remote=${remote}` : ''}`;
  } else if (recorded === null) {
    const exists = fs.existsSync(cfg);
    if (exists) {
      fs.writeFileSync(cfg, appendPlatformLine(fs.readFileSync(cfg, 'utf8'), detected));
      line = `RECORDED platform=${detected}`;
    } else {
      fs.mkdirSync(path.dirname(cfg), { recursive: true });
      fs.writeFileSync(cfg, `${NEW_FILE_HEADER.join('\n')}\nplatform: ${detected}\n`);
      line = `RECORDED platform=${detected} (new file)`;
    }
  } else {
    fs.writeFileSync(cfg, rewritePlatformLine(fs.readFileSync(cfg, 'utf8'), detected));
    line = `RECORDED platform=${detected} (was ${recorded})`;
  }

  console.log(line);
  console.log(`AUTH ${after} ${authStatus(after)}`);
  exit(code);
}

function main() {
  const [sub, ...rest] = process.argv.slice(2);
  if (sub === '-h' || sub === '--help') { console.log(USAGE); exit(0); }
  if (sub === 'record') runRecord(rest);
  usageError(sub === undefined ? 'a subcommand is required' : `unknown subcommand "${sub}"`);
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));
if (isMain) runMain(() => main());
