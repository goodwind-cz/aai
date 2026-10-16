#!/usr/bin/env node
// platform-direct-calls.mjs — static check that a consumer never reaches a git
// host CLI directly (spec-git-platform-detected-at-bootstrap, D12). Every host
// operation goes through .aai/scripts/lib/platform-adapter.mjs; a consumer file
// that names gh or az itself bypasses the platform record.
//
// Usage: node tests/skills/lib/platform-direct-calls.mjs <consumer-file>...
// Exit 0 "PLATFORM-CALLS clean <n> files"; exit 1 listing file:line: text;
// exit 2 usage or unreadable file.
//
// Comment-only lines and block comments are skipped; every other line is
// matched against the patterns below. The adapter and platform.mjs are not
// consumers and are never passed here.
import fs from 'node:fs';

// A quoted token that is exactly the CLI name, or a command-line fragment.
const QUOTED_CLI = /(['"`])(gh|az)\1/;
const FRAGMENTS = ['gh pr ', 'gh api', 'az repos', 'az devops'];
// Exempt pairs, each 'file:line:trimmed line text'. Empty on purpose.
const ALLOW = [];

export function scan(text) {
  const hits = [];
  let inBlock = false;
  text.split(/\r?\n/).forEach((raw, i) => {
    let line = raw;
    if (inBlock) {
      const end = line.indexOf('*/');
      if (end < 0) return;
      line = line.slice(end + 2);
      inBlock = false;
    }
    line = line.replace(/\/\*.*?\*\//g, ' ');
    const open = line.indexOf('/*');
    if (open >= 0) { line = line.slice(0, open); inBlock = true; }
    if (/^\s*\/\//.test(line) || line.trim() === '') return;
    if (QUOTED_CLI.test(line) || FRAGMENTS.some((f) => line.includes(f))) hits.push({ line: i + 1, text: raw.trim() });
  });
  return hits;
}

function main(files) {
  if (files.length === 0) { console.error('usage: platform-direct-calls.mjs <consumer-file>...'); return 2; }
  const found = [];
  for (const f of files) {
    let text;
    try { text = fs.readFileSync(f, 'utf8'); } catch (e) { console.error(`cannot read ${f}: ${e.message}`); return 2; }
    for (const h of scan(text)) {
      if (!ALLOW.includes(`${f}:${h.line}:${h.text}`)) found.push(`${f}:${h.line}: ${h.text}`);
    }
  }
  if (found.length === 0) { console.log(`PLATFORM-CALLS clean ${files.length} files`); return 0; }
  console.log(`PLATFORM-CALLS ${found.length} direct call(s) outside the adapter`);
  for (const l of found) console.log(l);
  return 1;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('platform-direct-calls.mjs')) {
  process.exitCode = main(process.argv.slice(2));
}
