#!/usr/bin/env node
//
// learned-append.mjs — structural append-only gate for docs/knowledge/LEARNED.md
// (CHANGE learned-append-gate, spec-learned-append-gate).
//
// PURPOSE
//   The only sanctioned path for an AUTOMATED process to grow LEARNED.md.
//   Adopts Promptbook's persist-only-if-pure-append guarantee: a write is
//   accepted ONLY when the resulting file is byte-exactly the original file
//   plus new bytes tacked on — never a rewrite, reorder, mid-file insert, or
//   deletion of anything that already exists. Any other shape is rejected
//   (exit 1, diff summary, NOTHING written). Humans editing the file by hand
//   are entirely unaffected — this gate governs only this script's own write
//   path (see spec Constraints/Risks: a guardrail, not a security boundary).
//
// TWO MODES
//   1) Rule-text mode (default, the normal wrap-up path): input is a raw rule
//      SENTENCE. --source is REQUIRED. The script formats it into the house
//      bullet (see docs/knowledge/LEARNED.md header: "- [YYYY-MM-DD] Rule
//      text (source: how this was learned)") using today's UTC date, then
//      computes where it would land:
//        --section omitted            -> insertion point = true end of file.
//        --section names the file's   -> same as omitted (appending under
//          CURRENT LAST "## " heading    the last section IS appending at EOF).
//        --section names an EXISTING  -> insertion point = just before that
//          but NOT-last heading           section's next "## " heading, i.e.
//                                         mid-file. This construction is
//                                         DELIBERATE: it is what lets the
//                                         generic structural gate below prove
//                                         its teeth on a real mid-insert
//                                         attempt (see spec TEST-006) rather
//                                         than special-casing the rejection.
//        --section names a heading    -> a brand-new "## <section>" heading
//          absent from the file          + the bullet are appended at true
//                                         EOF (still a pure tail append).
//   2) Full-content mode (--full): input is a COMPLETE proposed replacement
//      document (already formatted by the caller — e.g. a critic step that
//      assembled a full candidate). No stamping is applied; the gate simply
//      checks the candidate against the current file with the same generic
//      structural check. This is the general verifier a rewrite/reorder/
//      deletion attempt is checked against (a rule-text append can only ever
//      insert new bytes, so those three transformation classes are only
//      reachable through this mode).
//
// STRUCTURAL GATE (the one check both modes funnel through)
//   isPureAppend(original, candidate) := candidate.length >= original.length
//     AND candidate.slice(0, original.length) === original
//   This is applied to the CONSTRUCTED candidate regardless of mode or of how
//   "safe" the construction looked — the gate is the authority, not the
//   construction logic.
//
// GRAMMAR
//   node .aai/scripts/learned-append.mjs --source "<text>" \
//     [--text "<rule>" | --file <path> | (stdin)] \
//     [--section "<Heading>"] [--target <path>] [--dry-run]
//   node .aai/scripts/learned-append.mjs --full \
//     [--text "<content>" | --file <path> | (stdin)] \
//     [--target <path>] [--dry-run]
//   node .aai/scripts/learned-append.mjs --help
//
//   Input precedence: exactly one of --text / --file / stdin. Supplying more
//   than one is a usage error. `--target` defaults to docs/knowledge/LEARNED.md
//   (repo-relative, resolved against the current working directory).
//
// EXIT CONTRACT
//   0  success — a pure append was written (or, under --dry-run, would have
//      been), or --help.
//   1  the candidate is NOT a pure append of the current target file. A diff
//      summary is printed to stderr. NOTHING is written, ever (dry-run or
//      not — dry-run only ever affects the success path).
//   2  usage error (bad/missing/conflicting flags, unreadable target/input).
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import { readFileSync, writeFileSync, renameSync, existsSync, openSync, closeSync, unlinkSync, statSync, chmodSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const DEFAULT_TARGET = 'docs/knowledge/LEARNED.md';
const HEADING_RE = /^## (.+?)\s*$/;

function fail(msg, exitCode = 2) {
  console.error(`learned-append: ${msg}`);
  exit(exitCode);
}

function printHelp() {
  console.log(`learned-append.mjs — structural append-only gate for docs/knowledge/LEARNED.md

Rule-text mode (default):
  node .aai/scripts/learned-append.mjs --source "<how learned>" \\
    [--text "<rule>" | --file <path> | (stdin)] \\
    [--section "<Heading>"] [--target <path>] [--dry-run]

Full-content mode (generic verifier, e.g. for a critic-assembled candidate):
  node .aai/scripts/learned-append.mjs --full \\
    [--text "<content>" | --file <path> | (stdin)] \\
    [--target <path>] [--dry-run]

Exit codes: 0 written/would-write/help, 1 rejected (not a pure append,
nothing written), 2 usage error.`);
}

function requireValue(argv, i, flag) {
  const v = argv[i];
  if (v === undefined || v.startsWith('--')) {
    process.stderr.write(`learned-append: usage error — ${flag} requires a value\n`);
    exit(2);
  }
  return v;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    switch (tok) {
      case '--help': args.help = true; break;
      case '--text': args.text = requireValue(argv, ++i, '--text'); break;
      case '--file': args.file = requireValue(argv, ++i, '--file'); break;
      case '--source': args.source = requireValue(argv, ++i, '--source'); break;
      case '--section': args.section = requireValue(argv, ++i, '--section'); break;
      case '--target': args.target = requireValue(argv, ++i, '--target'); break;
      case '--full': args.full = true; break;
      case '--dry-run': args.dryRun = true; break;
      default: fail(`unknown flag: ${tok}`, 2);
    }
  }
  return args;
}

function readInput(args) {
  const sources = ['text', 'file'].filter((k) => args[k] !== undefined);
  if (sources.length > 1) fail('give exactly one of --text or --file (or pipe stdin), not more than one', 2);
  if (args.text !== undefined) return args.text;
  if (args.file !== undefined) {
    if (!existsSync(args.file)) fail(`--file not found: ${args.file}`, 2);
    return readFileSync(args.file, 'utf8');
  }
  try {
    return readFileSync(0, 'utf8');
  } catch {
    fail('no input: supply --text, --file, or pipe stdin', 2);
  }
}

function todayUTC() {
  return new Date().toISOString().slice(0, 10);
}

function formatEntry(text, source, dateStr) {
  // A rule entry is exactly one line: embedded line breaks would let one
  // "entry" smuggle arbitrary extra lines past the format (PR #169 P2).
  if (/[\r\n]/.test(text) || /[\r\n]/.test(source)) {
    process.stderr.write('learned-append: usage error — rule text and source must be single-line (no line breaks)\n');
    exit(2);
  }
  return `- [${dateStr}] ${text} (source: ${source})`;
}

// Character offsets of the start of each line, indices aligned with
// text.split('\n') (so join('\n') round-trips exactly, including a trailing
// empty element when text ends with '\n').
function lineOffsets(text) {
  const lines = text.split('\n');
  const offsets = [];
  let acc = 0;
  for (const l of lines) {
    offsets.push(acc);
    acc += l.length + 1;
  }
  return { lines, offsets };
}

// Resolve where a rule-text-mode bullet would land. Returns
// { offset, newHeading } — offset is the char index in `original` to splice
// the entry in before; newHeading is true when a brand-new "## <section>"
// heading must be synthesized (section absent from the file entirely).
function resolveInsertion(original, section) {
  if (!section) return { offset: original.length, newHeading: false };
  const { lines, offsets } = lineOffsets(original);
  let targetLine = -1;
  for (let li = 0; li < lines.length; li += 1) {
    const m = lines[li].match(HEADING_RE);
    if (m && m[1].trim().toLowerCase() === section.trim().toLowerCase()) {
      targetLine = li;
      break;
    }
  }
  if (targetLine === -1) return { offset: original.length, newHeading: true };
  for (let li = targetLine + 1; li < lines.length; li += 1) {
    if (HEADING_RE.test(lines[li])) return { offset: offsets[li], newHeading: false };
  }
  return { offset: original.length, newHeading: false };
}

function buildRuleTextCandidate(original, entryLine, insertion, section) {
  const { offset, newHeading } = insertion;
  const atEOF = offset === original.length;
  let insertText;
  if (newHeading) {
    const sep = original.length === 0 || original.endsWith('\n') ? '' : '\n';
    insertText = `${sep}\n## ${section}\n${entryLine}\n`;
  } else if (atEOF) {
    const sep = original.length === 0 || original.endsWith('\n') ? '' : '\n';
    insertText = `${sep}${entryLine}\n`;
  } else {
    // Mid-file insertion (section named is not the file's last section).
    // Deliberately constructed so the generic structural gate below rejects
    // it — see the file header "TWO MODES" note.
    insertText = `${entryLine}\n`;
  }
  return original.slice(0, offset) + insertText + original.slice(offset);
}

// The one structural authority both modes funnel through.
function isPureAppend(original, candidate) {
  return candidate.length >= original.length && candidate.slice(0, original.length) === original;
}

function diffSummary(original, candidate) {
  const minLen = Math.min(original.length, candidate.length);
  let i = 0;
  while (i < minLen && original[i] === candidate[i]) i += 1;
  const CTX = 40;
  const origCtx = original.slice(Math.max(0, i - CTX), i + CTX);
  const candCtx = candidate.slice(Math.max(0, i - CTX), i + CTX);
  const lines = [
    `not a pure append: original length ${original.length}, candidate length ${candidate.length}, first divergence at byte offset ${i}`,
  ];
  if (candidate.length < original.length) {
    lines.push('  candidate is a strict prefix of the original (a deletion/truncation)');
  }
  lines.push(`  original ...${JSON.stringify(origCtx)}...`);
  lines.push(`  candidate...${JSON.stringify(candCtx)}...`);
  return lines.join('\n');
}

function atomicWrite(targetPath, content) {
  const tmp = path.join(path.dirname(targetPath), `.${path.basename(targetPath)}.tmp-${process.pid}-${randomBytes(4).toString('hex')}`);
  writeFileSync(tmp, content);
  // Preserve the target's permission bits across replacement (PR #169 P2).
  try { chmodSync(tmp, statSync(targetPath).mode & 0o7777); } catch { /* new file: default mode */ }
  renameSync(tmp, targetPath);
}

// Exclusive advisory lock serializing concurrent append writers (PR #169
// Codex P1): two overlapping wrap-ups could both pass isPureAppend against
// the same original and the later rename would discard the earlier accepted
// rule. wx-create; stale after 30s is reclaimed; 3 retries with backoff.
const LOCK_STALE_MS = 30_000;
function withAppendLock(targetPath, fn) {
  const lock = `${targetPath}.lock`;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const fd = openSync(lock, 'wx');
      try {
        writeFileSync(lock, String(process.pid));
        return fn();
      } finally {
        closeSync(fd);
        try { unlinkSync(lock); } catch { /* already gone */ }
      }
    } catch (err) {
      if (err && err.code === 'EEXIST') {
        try {
          if (Date.now() - statSync(lock).mtimeMs > LOCK_STALE_MS) { unlinkSync(lock); continue; }
        } catch { continue; }
        const waitMs = 150 * (attempt + 1);
        const end = Date.now() + waitMs;
        while (Date.now() < end) { /* brief sync backoff */ }
        continue;
      }
      throw err;
    }
  }
  process.stderr.write(`learned-append: rejected — could not acquire ${lock} (concurrent writer); retry later\n`);
  exit(1);
}

function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    exit(0);
  }

  const targetPath = path.resolve(process.cwd(), args.target || DEFAULT_TARGET);
  if (!existsSync(targetPath)) fail(`target not found: ${targetPath}`, 2);
  const original = readFileSync(targetPath, 'utf8');

  let candidate;
  if (args.full) {
    if (args.source || args.section) fail('--full cannot be combined with --source or --section', 2);
    candidate = readInput(args);
  } else {
    if (!args.source) fail('rule-text mode requires --source', 2);
    const text = readInput(args);
    const entryLine = formatEntry(text.trim(), args.source, todayUTC());
    const insertion = resolveInsertion(original, args.section);
    candidate = buildRuleTextCandidate(original, entryLine, insertion, args.section);
  }

  if (!isPureAppend(original, candidate)) {
    console.error(`learned-append: rejected — ${diffSummary(original, candidate)}`);
    exit(1);
  }

  const appended = candidate.slice(original.length);
  if (args.dryRun) {
    if (appended.length === 0) {
      console.log('learned-append: dry-run — candidate is identical to the current file (no-op, nothing to append)');
    } else {
      console.log('learned-append: dry-run — would append:');
      process.stdout.write(appended);
    }
    exit(0);
  }

  withAppendLock(targetPath, () => {
    // Re-read under the lock: another writer may have appended since our
    // initial read; re-verify the pure-append invariant against the CURRENT
    // content and re-base the candidate when it still holds (P1 fix).
    const current = existsSync(targetPath) ? readFileSync(targetPath, 'utf8') : '';
    let toWrite = candidate;
    if (current !== original) {
      if (!isPureAppend(original, current)) {
        process.stderr.write('learned-append: rejected — target changed non-appendingly under our feet; re-run against the current file\n');
        exit(1);
      }
      toWrite = current + candidate.slice(original.length);
      if (!isPureAppend(current, toWrite)) {
        process.stderr.write('learned-append: rejected — re-based candidate is not a pure append of the current file\n');
        exit(1);
      }
    }
    atomicWrite(targetPath, toWrite);
  });
  console.log(appended.length === 0
    ? `learned-append: no-op — ${targetPath} already matched the candidate`
    : `learned-append: appended ${appended.length} bytes to ${targetPath}`);
}

runMain(() => main());