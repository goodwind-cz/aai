// platform-adapter.mjs — the one seam between AAI's git-host consumers and the
// host CLIs (spec-git-platform-detected-at-bootstrap, ride 1). Node stdlib only.
//
// This file currently carries the platform RECORD side (D1, D3, D5): the
// column-0 `platform:` key of docs/ai/pr-config.yaml, the resolution rule
// every consumer shares, and the CLI authentication probe. The host
// operations (PR reads, dependents, review threads, merge command) join in
// later batches of the same ride.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { classify, extractHost, readOriginUrl } from '../pr-platform.mjs';

export const PLATFORM_VALUES = ['github', 'azure', 'unknown', 'none'];
const KNOWN_DETECTED = ['github', 'azure', 'none'];
export const PR_CONFIG_REL = 'docs/ai/pr-config.yaml';
const AUTH_TIMEOUT_MS = 30000;

// D1: column-0 line scan, same discipline as reviewer_bots. The value is the
// ENTIRE rest of the line, trimmed, and must equal a closed-set token.
// Returns null (file or key absent), one of PLATFORM_VALUES, or 'invalid'.
export function readRecordedPlatform(repoRoot) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(repoRoot, PR_CONFIG_REL), 'utf8');
  } catch {
    return null;
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^platform:(.*)$/);
    if (!m) continue;
    const v = m[1].trim();
    return PLATFORM_VALUES.includes(v) ? v : 'invalid';
  }
  return null;
}

// Closed-set classification of the origin remote; none when there is none.
export function detectPlatform({ repoRoot, remoteUrl } = {}) {
  const url = remoteUrl !== undefined ? (remoteUrl || null) : readOriginUrl(repoRoot);
  if (!url) return 'none';
  const c = classify(extractHost(url));
  return KNOWN_DETECTED.includes(c) ? c : 'unknown';
}

// D5: a mismatch is an invalid record, or a record that differs from a
// detected github, azure or none. A detected unknown never contradicts.
export function isMismatch(recorded, detected) {
  if (recorded === null) return false;
  return recorded === 'invalid' || (KNOWN_DETECTED.includes(detected) && recorded !== detected);
}

// D5 resolution, shared by every consumer.
export function resolvePlatform({ repoRoot, remoteUrl } = {}) {
  const recorded = readRecordedPlatform(repoRoot);
  const detected = detectPlatform({ repoRoot, remoteUrl });
  const mismatch = isMismatch(recorded, detected);
  if (recorded !== null && recorded !== 'invalid') {
    return { platform: recorded, recorded, detected, mismatch, legacy: false };
  }
  if (recorded === null && KNOWN_DETECTED.includes(detected)) {
    return { platform: detected, recorded, detected, mismatch, legacy: false };
  }
  if (recorded === null) {
    return { platform: 'github', recorded, detected, mismatch, legacy: true };
  }
  return { platform: null, recorded, detected, mismatch, legacy: false };
}

function runTool(cmd, args, runner) {
  const res = (runner || spawnSync)(cmd, args, { stdio: 'ignore', timeout: AUTH_TIMEOUT_MS });
  if (res.error) return res.error.code === 'ENOENT' ? 'cli_missing' : 'unauthenticated';
  return res.status === 0 ? 'ok' : 'unauthenticated';
}

// D3: one result token per platform; the exact argv is part of the contract.
export function authStatus(platform, { runner } = {}) {
  if (platform === 'github') return runTool('gh', ['auth', 'status'], runner);
  if (platform === 'azure') {
    const account = runTool('az', ['account', 'show', '--output', 'json'], runner);
    if (account !== 'ok') return account;
    const ext = runTool('az', ['extension', 'show', '--name', 'azure-devops', '--output', 'json'], runner);
    return ext === 'ok' ? 'ok' : (ext === 'cli_missing' ? 'cli_missing' : 'extension_missing');
  }
  return 'skipped';
}
