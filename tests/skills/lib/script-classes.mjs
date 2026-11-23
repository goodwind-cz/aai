// Shared classifier for the shipped shell and PowerShell scripts under .aai/scripts
// (docs/specs/SPEC-DRAFT-spec-node-first-phase5-closeout.md D-CLASS). One reading of the
// plan's section 1 method (docs/analysis/node-first-remaining-plan.md) and of the
// "Kept native scripts" table of RFC-0017. Test-only; Node stdlib.
//
// CLI: node tests/skills/lib/script-classes.mjs strict --root <dir> [--files-from <list>]
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export const LAUNCHER_MAX_CODE_LINES = 20;
export const POLICY_TOKENS = [/\bgit\b/, /\.gitignore/, /PROFILES/, /--profile\b|-Profile\b/];
export const KEPT_NATIVE_HEADING = '### Kept native scripts';

// Lines that are not blank and whose first non-space character is not '#'.
export function countCodeLines(text) {
  return codeLines(text).length;
}

function codeLines(text) {
  return text.split('\n').filter((l) => !/^\s*(#|$)/.test(l));
}

function namesPolicy(text) {
  return codeLines(text).some((l) => POLICY_TOKENS.some((re) => re.test(l)));
}

function isRetired(text) {
  return text.split('\n').slice(0, 3).some((l) => /^#\s*RETIRED\b/.test(l));
}

// Every table row under the heading, as { file, reason, line }; an empty reason is kept.
export function parseKeptNative(rfcText) {
  const lines = rfcText.split('\n');
  const at = lines.findIndex((l) => l === KEPT_NATIVE_HEADING);
  const rows = [];
  if (at < 0) return rows;
  for (let i = at + 1; i < lines.length && !lines[i].startsWith('#'); i += 1) {
    const m = /^\|\s*`([^`]+)`\s*\|(.*)\|\s*$/.exec(lines[i]);
    if (m) rows.push({ file: m[1], reason: m[2].trim(), line: i + 1 });
  }
  return rows;
}

function keptMap(kept) {
  const map = new Map();
  for (const r of kept || []) if (!map.has(r.file)) map.set(r.file, r);
  return map;
}

export function classify({ file, text, kept }) {
  if (isRetired(text)) return 'deprecation launcher';
  const row = keptMap(kept).get(file);
  if (row && row.reason !== '') return 'kept native';
  if (countCodeLines(text) <= LAUNCHER_MAX_CODE_LINES && !namesPolicy(text)) return 'launcher';
  return 'logic';
}

export function strictProblems({ files, read, kept }) {
  const problems = [];
  for (const file of files) {
    const text = read(file);
    const cls = classify({ file, text, kept });
    if (cls === 'logic') problems.push(`logic: ${file} (${countCodeLines(text)} code lines, not a launcher and not a kept-native row)`);
    if (cls === 'deprecation launcher') {
      const n = countCodeLines(text);
      if (n > LAUNCHER_MAX_CODE_LINES) problems.push(`deprecation launcher over ${LAUNCHER_MAX_CODE_LINES} code lines: ${file} (${n})`);
      if (namesPolicy(text)) problems.push(`deprecation launcher names a policy token: ${file}`);
    }
  }
  const seen = new Map();
  const set = new Set(files);
  for (const r of kept || []) {
    if (r.reason === '') problems.push(`kept-native row with an empty reason: ${r.file} (RFC line ${r.line})`);
    if (!set.has(r.file)) problems.push(`kept-native row names a file outside the list: ${r.file} (RFC line ${r.line})`);
    if (seen.has(r.file)) problems.push(`kept-native file named by two rows: ${r.file} (RFC lines ${seen.get(r.file)} and ${r.line})`);
    else seen.set(r.file, r.line);
  }
  return problems;
}

function listFiles(root, filesFrom) {
  if (filesFrom) return fs.readFileSync(filesFrom, 'utf8').split('\n').map((l) => l.trim()).filter(Boolean);
  const out = execFileSync('git', ['-C', root, 'ls-files', '-z', '--', '.aai/scripts'], { encoding: 'utf8' });
  return out.split('\0').filter((f) => f.endsWith('.sh') || f.endsWith('.ps1'));
}

function main(argv) {
  const [cmd, ...rest] = argv;
  const opt = {};
  for (let i = 0; i < rest.length; i += 2) opt[rest[i]] = rest[i + 1];
  if (cmd !== 'strict' || !opt['--root']) {
    process.stderr.write('usage: script-classes.mjs strict --root <dir> [--files-from <list>]\n');
    return 2;
  }
  const root = path.resolve(opt['--root']);
  const files = listFiles(root, opt['--files-from']);
  if (files.length === 0) { process.stderr.write('no script files found\n'); return 2; }
  const rfc = fs.readFileSync(path.join(root, 'docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md'), 'utf8');
  const problems = strictProblems({ files, read: (f) => fs.readFileSync(path.join(root, f), 'utf8'), kept: parseKeptNative(rfc) });
  for (const p of problems) process.stdout.write(`${p}\n`);
  return problems.length === 0 ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2));
