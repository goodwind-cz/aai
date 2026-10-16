#!/usr/bin/env node
// platform.mjs — record the git host platform (spec-git-platform-detected-at-bootstrap).
//
//   node .aai/scripts/platform.mjs record [--repo-root <dir>] [--remote-url <url>]
//                                         [--force] [--dry-run]
//   AAI_OPERATOR_MERGE=1 node .aai/scripts/platform.mjs merge --pr <n> --expect-head <sha>
//                                         [--repo-root <dir>]
//
// record classifies origin with pr-platform.mjs's classifier and keeps ONE
// column-0 `platform:` line in docs/ai/pr-config.yaml (D2). It never
// overwrites a differing value without --force, then prints one AUTH line
// (D3) that never changes the exit code or the file.
//
// merge is the Azure merge executor (D9): it compares the PR head to the owner's
// sha, completes the PR exactly once (`az repos pr update --status completed`),
// then re-reads it to prove which head was merged.
//
// Exit codes: 0 recorded / unchanged / would-record / MERGED, 2 usage,
// 3 refused (no merge happened), 4 completion_pending, 5 head_race_lost,
// 6 MISMATCH.
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { sanitize } from './pr-platform.mjs';
import {
  PR_CONFIG_REL, authStatus, azSpawnSpec, createAdapter, detectPlatform, isMismatch,
  readRecordedPlatform, resolvePlatform,
} from './lib/platform-adapter.mjs';

const USAGE = 'Usage: node platform.mjs record [--repo-root <dir>] [--remote-url <url>] [--force] [--dry-run]\n'
  + '       AAI_OPERATOR_MERGE=1 node platform.mjs merge --pr <n> --expect-head <sha> [--repo-root <dir>]';
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

function parseMergeArgs(args) {
  const opts = { pr: null, expectHead: null, repoRoot: null };
  for (let i = 0; i < args.length; i += 1) {
    const tok = args[i];
    if (tok !== '--pr' && tok !== '--expect-head' && tok !== '--repo-root') usageError(`unknown flag "${tok}"`);
    if (args[i + 1] === undefined) usageError(`${tok} requires a value`);
    if (tok === '--pr') opts.pr = args[i + 1];
    else if (tok === '--expect-head') opts.expectHead = args[i + 1];
    else opts.repoRoot = args[i + 1];
    i += 1;
  }
  if (!/^[1-9][0-9]*$/.test(opts.pr ?? '')) usageError('--pr <n> must be a positive integer');
  if (opts.expectHead === null) usageError('--expect-head <sha> is required');
  return opts;
}

function refuse(reason, detail) {
  console.error(`platform: ${reason}${detail ? ` ${detail}` : ''}`);
  exit(3);
}

// A5 (D8): the one write. Runs through azSpawnSpec so Windows gets the safe cmd.exe route.
function completePr(n, cwd) {
  const spec = azSpawnSpec(['repos', 'pr', 'update', '--id', String(n), '--status', 'completed', '--squash', 'true', '--delete-source-branch', 'false', '--detect', 'true', '--output', 'json']);
  if (spec.refused) return { ok: false, detail: spec.detail };
  const res = spawnSync(spec.cmd, spec.args, { cwd, encoding: 'utf8', timeout: 120000, env: spec.env });
  if (res.error || res.status !== 0) {
    const first = String(res.stderr || res.error?.message || '').split(/\r?\n/).find((l) => l.trim()) || `exit ${res.status}`;
    return { ok: false, detail: first.trim() };
  }
  return { ok: true };
}

function runMerge(args) {
  const opts = parseMergeArgs(args);
  const n = Number(opts.pr);
  const repoRoot = path.resolve(opts.repoRoot || gitToplevel() || process.cwd());
  if (process.env.AAI_OPERATOR_MERGE !== '1') refuse('no_operator_merge', 'set AAI_OPERATOR_MERGE=1 on the owner-directed merge command');
  if (!/^[0-9a-f]{40}$/.test(opts.expectHead)) refuse('bad_expect_head', '--expect-head must be 40 lower-case hex characters');
  const eff = resolvePlatform({ repoRoot });
  if (eff.mismatch) {
    console.log(`REFUSE platform_mismatch recorded=${eff.recorded} detected=${eff.detected} re-record: node .aai/scripts/platform.mjs record --force`);
    exit(3);
  }
  if (eff.platform !== 'azure') refuse('platform_not_azure', `effective platform is ${eff.platform}`);
  const adapter = createAdapter('azure', { cwd: repoRoot });
  const expectHead = opts.expectHead;
  const read = adapter.prView(n);
  if (!read.ok) refuse(adapter.refusalReason(read), read.detail);
  const before = read.value;
  if (before.state !== 'OPEN') refuse('not_open', `PR #${n} is ${before.state}`);
  if (before.isDraft) refuse('draft', `PR #${n} is a draft`);
  if (before.headRefOid !== expectHead) refuse('head_changed', `expected ${expectHead} found ${before.headRefOid}`);
  const done = completePr(n, repoRoot);
  if (!done.ok) refuse('merge_rejected', done.detail);
  const again = adapter.prView(n);
  if (!again.ok) { console.error(`platform: completion_pending re-read failed (${again.detail})`); exit(4); }
  const after = again.value;
  if (after.state === 'MERGED') {
    if (after.headRefOid === expectHead) {
      console.log(`MERGED PR #${n} head ${expectHead} merge ${after.mergeCommit?.oid ?? 'unknown'}`);
      exit(0);
    }
    console.error(`platform: head_race_lost expected ${expectHead} merged ${after.headRefOid}`);
    exit(5);
  }
  if (after.state === 'OPEN') { console.error(`platform: completion_pending PR #${n} is still active (branch policies or a queued completion)`); exit(4); }
  refuse('merge_rejected', `PR #${n} is ${after.state} after completion`);
}

function main() {
  const [sub, ...rest] = process.argv.slice(2);
  if (sub === '-h' || sub === '--help') { console.log(USAGE); exit(0); }
  if (sub === 'record') runRecord(rest);
  if (sub === 'merge') runMerge(rest);
  usageError(sub === undefined ? 'a subcommand is required' : `unknown subcommand "${sub}"`);
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));
if (isMain) runMain(() => main());
