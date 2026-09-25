#!/usr/bin/env node
//
// ledger-merge.mjs — the append-only JSONL ledger merge procedure, as a
// command (spec-friction-channel-sweep Spec-AC-09, fu-learned-ledger-merge-procedure).
//
// docs/knowledge/LEARNED.md has carried the PROSE description of this
// procedure since 2026-08-24 without a command that performs it: "Merge an
// append-only ledger (docs/ai/decisions.jsonl, docs/ai/EVENTS.jsonl) by
// keeping the BASE side a byte-exact prefix and appending both branches' new
// lines after it; a union in any other order rewrites existing bytes from
// the base's point of view even when no record is lost. Never accept an
// auto-merge of these files without diffing the prefix." This script IS that
// command.
//
// ALGORITHM
//   1. Read base/ours/theirs as raw text.
//   2. Refuse (exit 1, write nothing) unless BOTH ours and theirs carry base
//      as a byte-exact PREFIX — a side whose base-covered bytes were
//      rewritten (not merely extended) can never be safely unioned; this is
//      the ONLY refusal condition.
//   3. The "new" text of each side is everything after that shared prefix,
//      split into JSONL lines (trailing blank line from a final newline
//      dropped).
//   4. The merged tail is ours' new lines, in order, followed by theirs' new
//      lines that are NOT byte-identical to any line ours already
//      contributed (an append-only ledger's own record is content-addressed
//      by its full line, so an exact duplicate line is the same event
//      counted twice, not a second one — this is the *.jsonl-only dedupe
//      LEARNED.md's "Union merge dedupe drops braces" entry draws, as
//      opposed to code/shell text, which this script never touches).
//   5. Output = base + merged tail, each line terminated with \n. Base's own
//      bytes are NEVER rewritten, reordered or dropped — only appended to.
//
// GRAMMAR
//   node .aai/scripts/ledger-merge.mjs --base <path> --ours <path> --theirs <path> --out <path>
//   node .aai/scripts/ledger-merge.mjs --help
//
// EXIT CONTRACT
//   0  merged — <out> written, per-side contributed line counts reported.
//   1  refused — ours or theirs does not carry base as a byte-exact prefix.
//      NOTHING is written to <out>.
//   2  usage error (missing/unreadable flag or file).
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const HELP = `ledger-merge — the append-only JSONL ledger merge procedure, as a command.

Usage:
  node .aai/scripts/ledger-merge.mjs --base <path> --ours <path> --theirs <path> --out <path>
  node .aai/scripts/ledger-merge.mjs --help

Keeps the base side a byte-exact PREFIX of the result and appends both
sides' new lines after it (ours' new lines, then theirs' new lines that are
not exact duplicates of a line ours already contributed). Refuses (exit 1,
nothing written) when either side does not carry base as a byte-exact
prefix — a rewritten base can never be safely unioned.

Exit codes: 0 merged   1 refused (base not a prefix)   2 usage error
`;

function usageError(msg) {
  process.stderr.write(`ledger-merge: usage error — ${msg}\n`);
  process.stderr.write(
    'usage: node .aai/scripts/ledger-merge.mjs --base <path> --ours <path> --theirs <path> --out <path>\n'
  );
  exit(2);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--help' || tok === '-h') { args.help = true; continue; }
    if (tok === '--base' || tok === '--ours' || tok === '--theirs' || tok === '--out') {
      const val = argv[++i];
      if (val === undefined || val.startsWith('--')) usageError(`${tok} requires a <path> value`);
      args[tok.slice(2)] = val;
      continue;
    }
    usageError(`unrecognized flag: ${tok}`);
  }
  return args;
}

function readRequired(label, filePath) {
  if (!existsSync(filePath)) usageError(`${label} not found: ${filePath}`);
  try {
    return readFileSync(filePath, 'utf8');
  } catch (err) {
    usageError(`${label} unreadable: ${filePath} (${err.message})`);
    return ''; // unreachable — usageError always exit()s — keeps the linter happy
  }
}

// splitNewLines(text) -> the JSONL lines of `text` (a suffix after a known
// prefix), one array entry per line, no trailing blank entry from a final
// newline. An empty suffix yields [].
function splitNewLines(text) {
  if (text.length === 0) return [];
  const withoutTrailingNewline = text.endsWith('\n') ? text.slice(0, -1) : text;
  if (withoutTrailingNewline.length === 0) return [];
  return withoutTrailingNewline.split('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { process.stdout.write(HELP); exit(0); }
  for (const flag of ['base', 'ours', 'theirs', 'out']) {
    if (!args[flag]) usageError(`missing --${flag}`);
  }

  const base = readRequired('--base', args.base);
  const ours = readRequired('--ours', args.ours);
  const theirs = readRequired('--theirs', args.theirs);

  if (!ours.startsWith(base)) {
    process.stderr.write(
      `ledger-merge: refused — ${args.ours} does not carry ${args.base} as a byte-exact prefix ` +
      '(the base side was rewritten, not merely extended); nothing written\n'
    );
    exit(1);
  }
  if (!theirs.startsWith(base)) {
    process.stderr.write(
      `ledger-merge: refused — ${args.theirs} does not carry ${args.base} as a byte-exact prefix ` +
      '(the base side was rewritten, not merely extended); nothing written\n'
    );
    exit(1);
  }

  const oursNewLines = splitNewLines(ours.slice(base.length));
  const theirsNewLinesAll = splitNewLines(theirs.slice(base.length));
  const oursSet = new Set(oursNewLines);
  const theirsNewLines = theirsNewLinesAll.filter((line) => !oursSet.has(line));

  const mergedTail = [...oursNewLines, ...theirsNewLines];
  const result = base + mergedTail.map((l) => `${l}\n`).join('');

  writeFileSync(args.out, result);
  process.stdout.write(
    `ledger-merge: merged ${args.out} — ours contributed ${oursNewLines.length} line(s), ` +
    `theirs contributed ${theirsNewLines.length} line(s) ` +
    `(${theirsNewLinesAll.length - theirsNewLines.length} duplicate line(s) from theirs dropped)\n`
  );
  exit(0);
}

runMain(() => main(), {
  onError(err) {
    process.stderr.write(`ledger-merge: internal error (${err.message})\n`);
    process.exitCode = 1;
  },
});
