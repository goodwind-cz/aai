#!/usr/bin/env node
// triage.mjs - AAI L1 triage snapshot (read-only; safe to schedule), moved to one
// Node module by spec-node-first-second-slice (RFC-0017 phase 3).
// Reports state presence, working-tree cleanliness, the last loop tick and the
// docs-audit verdict. With --check it exits 1 when the audit output holds
// NEEDS-TRIAGE. It reads no standard input and writes no file. The repo root
// is two directories above THIS module, so the caller's cwd is irrelevant.
// triage.sh and triage.ps1 are thin launchers of this file.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

export const ATTENTION_MARKER = 'NEEDS-TRIAGE';
const BOM = String.fromCharCode(0xfeff);
const UNKNOWN_STATUS = 'unknown';
const NO_STATE = '- State: not present yet (docs/ai/STATE.yaml) - orchestrator will init, or run /aai-check-state';
const NO_AUDIT = '- Docs audit: skipped (node or docs-audit.mjs unavailable)';
const SHOWN = /^- (Mode|Scanned|Tracked):|^### Verdict:/;
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

const stripCr = (s) => (s.endsWith('\r') ? s.slice(0, -1) : s);

export function parseArgs(argv) {
  const check = argv.includes('--check');
  return { check };
}

export function stampUtc(now) {
  return now.toISOString().replace(/\.\d+Z$/, 'Z');
}

export function stateLine(stateText) {
  const match = (stateText ?? '').split('\n').map(stripCr).find((l) => l.startsWith('project_status:'));
  if (match === undefined) return NO_STATE;
  const value = match.split(/\s+/)[1] ?? '';
  return '- State: present (project_status=' + (value || UNKNOWN_STATUS) + ')';
}

export function treeLine(porcelain) {
  const n = (porcelain ?? '').split('\n').filter((l) => l !== '').length;
  return n === 0 ? '- Working tree: clean' : '- Working tree: ' + n + ' uncommitted change(s)';
}

export function tickLine(ticksText) {
  if (ticksText === null || ticksText === undefined || ticksText === '') return '- Last tick: none recorded';
  const rows = ticksText.split('\n');
  if (rows[rows.length - 1] === '') rows.pop();
  const last = rows.length ? rows[rows.length - 1] : '';
  const tick = stripCr(last);
  return '- Last tick: ' + tick;
}

export function auditSection(output) {
  if (output === null || output === undefined) return { lines: [NO_AUDIT], attention: false };
  const shown = output.split('\n').filter((l) => SHOWN.test(l));
  const attention = output.includes(ATTENTION_MARKER);
  return { lines: shown.length ? shown : ['- Docs audit: (no output)'], attention };
}

export function buildReport({ now, check, stateText, porcelain, ticksText, auditOutput }) {
  const header = '## AAI L1 Triage - ' + stampUtc(now);
  const lines = [header, '', stateLine(stateText), treeLine(porcelain), tickLine(ticksText), ''];
  const audit = auditSection(auditOutput);
  const issues = audit.attention ? 1 : 0;
  lines.push(...audit.lines, '');
  lines.push(issues === 0 ? '### Triage verdict: CLEAN' : '### Triage verdict: NEEDS-ATTENTION (' + issues + ' area(s))');
  const exitCode = issues > 0 && check ? 1 : 0;
  return { text: lines.join('\n') + '\n', exitCode };
}

function readText(file) {
  try {
    const text = fs.readFileSync(file, 'utf8');
    return text.startsWith(BOM) ? text.slice(BOM.length) : text;
  } catch { return null; }
}

function childOutput(cmd, args, root) {
  const r = spawnSync(cmd, args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 1 << 26 });
  return r.error ? { status: null, stdout: '' } : { status: r.status, stdout: r.stdout ?? '' };
}

export function runTriage({ argv = [], root = ROOT, now = new Date(), stdout = process.stdout } = {}) {
  const git = childOutput('git', ['status', '--porcelain'], root);
  const auditFile = path.join(root, '.aai', 'scripts', 'docs-audit.mjs');
  const auditOutput = fs.existsSync(auditFile) ? childOutput(process.execPath, [auditFile, '--quick'], root).stdout : null;
  const { text, exitCode } = buildReport({
    now,
    check: parseArgs(argv).check,
    stateText: readText(path.join(root, 'docs', 'ai', 'STATE.yaml')),
    porcelain: git.status === 0 ? git.stdout : null,
    ticksText: readText(path.join(root, 'docs', 'ai', 'LOOP_TICKS.jsonl')),
    auditOutput,
  });
  stdout.write(text);
  return exitCode;
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
const isMain = process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url));

if (isMain) {
  process.exitCode = runTriage({ argv: process.argv.slice(2) });
}
