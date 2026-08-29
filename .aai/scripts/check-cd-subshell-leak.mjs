#!/usr/bin/env node
/**
 * check-cd-subshell-leak.mjs — the leaked-`cd`-inside-a-command-substitution
 * guard (issue: cd-inside-command-substitution-hides-cwd, scar
 * fu-subagent-probe-hits-real-repo, P1, 2026-08-15).
 *
 * THE DEFECT CLASS
 * A `cd` that runs inside `$( ... )` or backtick command substitution
 * executes in a SUBSHELL. Its directory change is invisible to the parent
 * shell the instant the substitution closes. A line like
 *
 *     result="$(cd fixture && git commit -am "test")"
 *     git status
 *
 * looks like it scoped `git commit` to `fixture/`, but only the commit did —
 * the `git status` on the next line runs in whatever directory the PARENT
 * shell was already in. On 2026-08-15 that parent directory was the real
 * shipping repository, and the run created two commits on `main`. Nothing
 * caught it: a read-only role mutated the shipping repo and it was found by
 * luck, not by a guard. `HAZ-SCRATCH` in `.aai/SUBAGENT_CONTRACT.md` now
 * names the scar in prose, which the incident it describes already proved
 * insufficient on its own.
 *
 * WHAT THIS GUARD DOES
 * Two independent instruments over the same scan, following the same split
 * as the sibling `check-base-ref-pins.mjs`:
 *
 *   1. HARD GATE (never baselined, never waived). A `cd` inside a command
 *      substitution, where a `git` command runs at the TOP LEVEL (outside
 *      every substitution) within CD_LEAK_WINDOW_LINES lines after the
 *      substitution closes, with no intervening REAL top-level `cd` to
 *      re-scope it. This is exactly the incident's shape and fails, naming
 *      both the leaking `cd` and the offending `git` by file:line.
 *   2. RATCHET (an explicitly recorded baseline). Every `cd`-inside-a-
 *      substitution occurrence — including the SAFE ones, where nothing at
 *      the top level ever depended on the directory change — is counted per
 *      file against tests/skills/lib/cd-subshell-leak-baseline.tsv. A NEW
 *      file or a RISEN count fails; a SHRINK is reported but never lowers
 *      the bar on its own. This tracks the raw shape's surface even where it
 *      is currently harmless, the same discipline as
 *      tests/skills/lib/base-ref-pin-baseline.tsv.
 *
 * WHAT THIS DELIBERATELY DOES NOT CATCH (favor conservative over clever,
 * per the issue's own instruction — fewer false positives, some false
 * negatives):
 *   - Only `git` is treated as an "outside" command of interest. Another
 *     state-mutating command (`rm -rf`, `npm publish`, ...) following a
 *     leaked `cd` is not flagged. `git` is the verb the actual incident used
 *     and the one named in the issue's Expected Behavior.
 *   - A top-level `git -C <path> ...` is never flagged, no matter how close
 *     it sits to a leak: it names its own working directory explicitly and
 *     never reads the parent shell's cwd. Triage on this repository found
 *     the real, common, safe idiom `SRC="$(cd "$REPO" && pwd)"` followed
 *     immediately by `git -C "$SRC" fetch ...` — without this exclusion
 *     that pattern false-positives on every occurrence of it.
 *   - The window is LINES, not "reachable statements": a `git` command more
 *     than CD_LEAK_WINDOW_LINES lines after the substitution closes is not
 *     attributed to the leak (false negative, by design — see "shortly
 *     after" in the issue text).
 *   - A `cd` or `git` appearing as a literal argument (e.g. `echo "cd to the
 *     git repo"`) is excluded ONLY when it sits directly inside a bare
 *     double-quoted string with no active substitution at that exact
 *     position; a hyphenated word like `git-repo` (no space before the
 *     hyphen) can still register as a bare `git` token — a known
 *     approximation of "word boundary", not a full shell tokenizer.
 *   - A `cd` argument built entirely from an already-safe variable (no way
 *     for this scanner to know what a variable holds) is treated the same
 *     as any other `cd` — this guard reasons about SHAPE, not runtime value.
 *   - A live, ad-hoc shell command an agent types during a session (never
 *     committed to a tracked file) is out of scope for a static lint — see
 *     the issue's Constraints/Risks section; that remains process discipline
 *     (HAZ-CD, HAZ-SCRATCH).
 *   - Only `.sh` files under `tests/skills/` (recursively, including
 *     `lib/`) and `.aai/scripts/` (recursively, including `lib/`) are
 *     scanned. Unlike the sibling `check-base-ref-pins.mjs`, this DOES
 *     recurse into `lib/` subdirectories: the incident's own root cause was
 *     a "validator probe helper", exactly the kind of script that lives in
 *     a `lib/` directory, so a non-recursive scan would have missed the
 *     class it exists to catch.
 *
 * NEVER A NO-OP. Fails closed on: no files scanned, zero occurrences found,
 * an unreadable file, a missing or empty baseline. Silence is never reported
 * as cleanliness.
 *
 * USAGE
 *   node .aai/scripts/check-cd-subshell-leak.mjs                 # gate (exit 1 on failure)
 *   node .aai/scripts/check-cd-subshell-leak.mjs --json          # machine-readable report
 *   node .aai/scripts/check-cd-subshell-leak.mjs --record        # (re)write the baseline
 *   node .aai/scripts/check-cd-subshell-leak.mjs --root <dir> --baseline <tsv>
 *
 * EXIT CODES
 *   0  clean: no UNSAFE occurrence and no ratchet RISE/NEW
 *   1  a finding (UNSAFE, RISE, NEW) or a degraded scan
 *   2  usage error
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCAN_DIRS = ['tests/skills', '.aai/scripts'];
const BASELINE_REL = 'tests/skills/lib/cd-subshell-leak-baseline.tsv';

// How many lines after a leaking substitution closes a top-level `git` still
// counts as "shortly after" (the incident's own shape had it on the very
// next line). Kept small on purpose: the wider this is, the more an
// unrelated later `git` call gets blamed on an earlier, harmless `cd`.
const CD_LEAK_WINDOW_LINES = 5;

function fail(msg) {
  process.stderr.write(`check-cd-subshell-leak: ${msg}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const args = { record: false, json: false, root: process.cwd(), baseline: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--record') args.record = true;
    else if (a === '--json') args.json = true;
    else if (a === '--root') { args.root = argv[++i]; if (!args.root) fail('--root needs a directory'); }
    else if (a === '--baseline') { args.baseline = argv[++i]; if (!args.baseline) fail('--baseline needs a path'); }
    else if (a === '--help' || a === '-h') { process.stdout.write(HELP); process.exit(0); }
    else fail(`unknown argument: ${a}`);
  }
  return args;
}

const HELP = 'usage: check-cd-subshell-leak.mjs [--record] [--json] [--root <dir>] [--baseline <tsv>]\n\n'
  + 'Fails when a `cd` inside a command substitution is followed, within\n'
  + `${CD_LEAK_WINDOW_LINES} lines after the substitution closes, by a top-level\n`
  + '`git` command with no real `cd` in between (UNSAFE), or when the\n'
  + 'per-file occurrence count of the raw shape rises above the recorded baseline.\n';

/** Every *.sh file under the scan dirs in <root>, recursive, sorted by
 * relative path. A tree missing a scan dir entirely is a valid tree, not a
 * finding. */
export function scanFiles(root) {
  const out = [];
  function walk(dir) {
    let entries;
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries.sort((a, b) => (a.name < b.name ? -1 : 1))) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { walk(p); continue; }
      if (e.isFile() && e.name.endsWith('.sh')) out.push(p);
    }
  }
  for (const rel of SCAN_DIRS) walk(path.join(root, rel));
  return out.sort();
}

/**
 * scanText(text) -> [{cdLine, cdText, cls: 'UNSAFE'|'SAFE', gitLine, gitText}]
 *
 * A single left-to-right pass tracking: single/double quote state, a stack of
 * open command-substitution frames (`$(` / backtick), and pending "leaks" — a
 * `cd` word seen while ANY substitution frame was open, recorded the instant
 * the OUTERMOST frame closes (stack depth returns to 0 — the point at which
 * control genuinely returns to the parent shell).
 *
 * A pending leak resolves UNSAFE the moment a top-level `git` word is seen
 * within the window; it is cleared (never flagged) the moment a genuine
 * top-level `cd` is seen first — that is a deliberate, real directory change
 * governing what follows, not an accident.
 */
export function scanText(text) {
  const lines = text.split('\n');
  const n = text.length;
  let i = 0;
  let line = 1;
  let inSingle = false;
  let inDouble = false;
  const stack = []; // 'paren' | 'backtick'
  let runSawCd = false;
  let runCdLine = null;
  const pendingLeaks = []; // {cdLine, closeLine, ref: <leak object also in allLeaks>}
  const allLeaks = [];

  const isWordChar = (ch) => ch !== undefined && /[A-Za-z0-9_]/.test(ch);
  const boundaryBefore = (idx) => idx <= 0 || !isWordChar(text[idx - 1]);
  const matchWord = (idx, word) => {
    if (text.slice(idx, idx + word.length) !== word) return false;
    if (!boundaryBefore(idx)) return false;
    return !isWordChar(text[idx + word.length]);
  };

  while (i < n) {
    const c = text[i];

    if (c === '\n') { line += 1; i += 1; continue; }

    if (inSingle) {
      if (c === "'") inSingle = false;
      i += 1;
      continue;
    }

    if (c === '\\') {
      if (text[i + 1] === '\n') { line += 1; i += 2; continue; }
      i += 2;
      continue;
    }

    if (c === '#' && !inDouble) {
      while (i < n && text[i] !== '\n') i += 1;
      continue;
    }

    // A `'` is only a quote DELIMITER outside a double-quoted string — bash
    // treats it as a plain literal character inside "...". Missing this
    // guard was a real bug found while writing this guard's own tests: a
    // contraction inside a double-quoted message (`"...cd's line..."`)
    // flipped inSingle and desynced quote-tracking for the rest of the file.
    if (c === "'" && !inDouble) { inSingle = true; i += 1; continue; }
    if (c === '"') { inDouble = !inDouble; i += 1; continue; }

    // A double-quote that opened BEFORE this substitution started (e.g. the
    // outer quote of `X="$(cd "$dir" && pwd)"`) must not make a literal `)`
    // INSIDE the substitution look closed, nor make the substitution's OWN
    // closing `)` look like it is "inside a quote" once a nested pair (like
    // "$dir" above) has toggled inDouble an even number of times. Bash parses
    // each $()/`` level with its own independent quoting context, so each
    // frame saves the enclosing inDouble and starts fresh at false; popping
    // restores it. Without this, `$(echo ")")` desynced: the `)` closing the
    // echo's own double-quoted argument was read as closing the substitution
    // itself (Copilot review, PR #312).
    if (c === '$' && text[i + 1] === '(') {
      stack.push({ type: 'paren', outerInDouble: inDouble });
      inDouble = false;
      if (stack.length === 1) { runSawCd = false; runCdLine = null; }
      i += 2;
      continue;
    }

    // Backtick nesting inside its OWN quoted text is a genuinely rare and
    // famously quirky corner of bash grammar (unlike $(...), a bare backtick
    // cannot be nested without escaping at all) — this models only the
    // common case, symmetric with the $() fix above: a backtick closes the
    // innermost open backtick frame when not inside a quote NESTED WITHIN
    // that frame; any other backtick opens a new frame. A backtick used in
    // some more exotic escaped-nesting shape is not modelled precisely —
    // conservative-detector tradeoff, same posture as the rest of this file.
    if (c === '`') {
      const top = stack[stack.length - 1];
      if (top && top.type === 'backtick' && !inDouble) {
        stack.pop();
        inDouble = top.outerInDouble;
        if (stack.length === 0 && runSawCd) {
          const leak = { cdLine: runCdLine, closeLine: line, cls: 'SAFE', gitLine: null };
          pendingLeaks.push(leak);
          allLeaks.push(leak);
          runSawCd = false; runCdLine = null;
        }
      } else {
        stack.push({ type: 'backtick', outerInDouble: inDouble });
        inDouble = false;
        if (stack.length === 1) { runSawCd = false; runCdLine = null; }
      }
      i += 1;
      continue;
    }

    if (c === ')' && !inDouble && stack[stack.length - 1] && stack[stack.length - 1].type === 'paren') {
      const top = stack.pop();
      inDouble = top.outerInDouble;
      if (stack.length === 0 && runSawCd) {
        const leak = { cdLine: runCdLine, closeLine: line, cls: 'SAFE', gitLine: null };
        pendingLeaks.push(leak);
        allLeaks.push(leak);
        runSawCd = false; runCdLine = null;
      }
      i += 1;
      continue;
    }

    if (stack.length > 0 && matchWord(i, 'cd')) {
      if (!runSawCd) { runSawCd = true; runCdLine = line; }
      i += 2;
      continue;
    }

    if (stack.length === 0 && !inDouble && matchWord(i, 'cd')) {
      // A REAL top-level directory change. Whatever follows is intentionally
      // scoped by it, not an accident of a subshell whose effect never
      // reached here — clear every leak still waiting on this file.
      pendingLeaks.length = 0;
      i += 2;
      continue;
    }

    if (stack.length === 0 && !inDouble && matchWord(i, 'git')) {
      // `git -C <path>` names its own working directory explicitly and never
      // reads the parent shell's cwd, so it cannot be the victim of a leaked
      // `cd` no matter how close it sits — a real occurrence found in triage
      // (`SRC="$(cd "$REPO" && pwd)"` followed by `git -C "$SRC" fetch ...`)
      // would otherwise false-positive on exactly the safe, common idiom of
      // resolving a path via a subshell `pwd` and passing it to `-C`.
      const lineText = lines[line - 1] || '';
      const scoped = /(^|[^A-Za-z0-9_-])-C(\s|$)/.test(lineText);
      if (!scoped) {
        for (let k = pendingLeaks.length - 1; k >= 0; k -= 1) {
          if (line - pendingLeaks[k].closeLine > CD_LEAK_WINDOW_LINES) pendingLeaks.splice(k, 1);
        }
        if (pendingLeaks.length > 0) {
          const leak = pendingLeaks.shift();
          leak.cls = 'UNSAFE';
          leak.gitLine = line;
        }
      }
      i += 3;
      continue;
    }

    i += 1;
  }

  return allLeaks.map((l) => ({
    cdLine: l.cdLine,
    cdText: (lines[l.cdLine - 1] || '').trim(),
    cls: l.cls,
    gitLine: l.gitLine,
    gitText: l.gitLine ? (lines[l.gitLine - 1] || '').trim() : null,
  }));
}

/** All occurrences in <root>. Throws on an unreadable file — never skips it. */
export function occurrences(root) {
  const files = scanFiles(root);
  const out = [];
  for (const file of files) {
    let text;
    try {
      text = fs.readFileSync(file, 'utf8');
    } catch (e) {
      throw new Error(`unreadable file ${path.relative(root, file)}: ${e.message}`);
    }
    const rel = path.relative(root, file).split(path.sep).join('/');
    for (const o of scanText(text)) {
      out.push({ file: rel, ...o });
    }
  }
  return { files, out };
}

/** Per-file occurrence counts (ALL leaks, UNSAFE and SAFE alike), sorted. */
export function countsOf(occ) {
  const m = new Map();
  for (const o of occ) m.set(o.file, (m.get(o.file) || 0) + 1);
  return [...m.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

export function readBaseline(file) {
  const text = fs.readFileSync(file, 'utf8');
  const rows = [];
  for (const raw of text.split('\n')) {
    const l = raw.trim();
    if (!l || l.startsWith('#')) continue;
    const [n, name] = l.split('\t');
    if (!name || !/^\d+$/.test(n)) throw new Error(`malformed baseline row: ${raw}`);
    rows.push([name, Number(n)]);
  }
  return rows;
}

/** RISE / NEW (failing) and SHRINK / GONE (reported only). */
export function compare(baseRows, nowRows) {
  const base = new Map(baseRows);
  const now = new Map(nowRows);
  const verdicts = [];
  for (const [name, n] of now) {
    const b = base.get(name) || 0;
    if (b === 0) verdicts.push({ kind: 'NEW', name, base: 0, now: n });
    else if (n > b) verdicts.push({ kind: 'RISE', name, base: b, now: n });
    else if (n < b) verdicts.push({ kind: 'SHRINK', name, base: b, now: n });
  }
  for (const [name, b] of base) {
    if (!now.has(name)) verdicts.push({ kind: 'GONE', name, base: b, now: 0 });
  }
  return verdicts;
}

export function renderBaseline(rows) {
  return [
    '# tests/skills/lib/cd-subshell-leak-baseline.tsv',
    '#',
    '# GENERATED, never hand-edited:',
    '#   node .aai/scripts/check-cd-subshell-leak.mjs --record',
    '#',
    '# One `<occurrences>\\t<file>` row per scanned shell file that carries a',
    '# `cd` inside a command substitution (SAFE or UNSAFE alike — this ratchets',
    '# the raw shape\'s surface, not just the incident-shaped subset). The count',
    '# may FALL, never RISE: a rise (or a file not listed here) fails',
    '# tests/skills/test-aai-hygiene-pack.sh and names the file. A SHRINK keeps',
    '# its recorded number until someone re-records on purpose, so that',
    '# lowering the bar is a visible act.',
    '#',
    '# Being listed here is NOT a waiver of the hard gate: a `cd` inside a',
    '# substitution followed by an unguarded top-level `git` shortly after',
    '# fails whether or not this file mentions it.',
    '#',
    ...rows.map(([name, n]) => `${n}\t${name}`),
    '',
  ].join('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.root);
  const baselineFile = args.baseline ? path.resolve(args.baseline) : path.join(root, BASELINE_REL);

  let files;
  let occ;
  try {
    ({ files, out: occ } = occurrences(root));
  } catch (e) {
    process.stderr.write(`DEGRADED SCAN (failing closed): ${e.message}\n`);
    process.exit(1);
  }

  const rows = countsOf(occ);
  const total = occ.length;

  if (args.record) {
    fs.writeFileSync(baselineFile, renderBaseline(rows), 'utf8');
    process.stdout.write(
      `recorded ${total} occurrence(s) across ${rows.length} file(s) from ${root} -> ${baselineFile}\n`,
    );
    return;
  }

  const problems = [];
  const notes = [];

  if (files.length === 0) {
    problems.push(
      `no shell file was scanned under ${root} (looked in: ${SCAN_DIRS.join(', ')}, recursively) — `
      + 'an empty corpus can never contradict a baseline, so this fails rather than passing',
    );
  } else if (total === 0) {
    problems.push(
      `the scanner found 0 occurrence(s) across ${files.length} scanned file(s) — `
      + 'the corpus is known to carry some, so a zero here is a broken scanner, not a clean tree',
    );
  }

  let baseRows = null;
  try {
    baseRows = readBaseline(baselineFile);
  } catch (e) {
    problems.push(
      `the baseline ${path.relative(root, baselineFile)} is missing or unreadable (${e.message}) — `
      + 'record it: node .aai/scripts/check-cd-subshell-leak.mjs --record',
    );
  }
  if (baseRows && baseRows.length === 0) {
    problems.push(
      `the baseline ${path.relative(root, baselineFile)} has no data rows — `
      + 'record it: node .aai/scripts/check-cd-subshell-leak.mjs --record',
    );
  }

  const unsafe = occ.filter((o) => o.cls === 'UNSAFE');
  for (const o of unsafe) {
    problems.push(
      `UNSAFE cd-subshell leak ${o.file}:${o.cdLine} — a \`cd\` inside a command substitution has no `
      + `effect on the parent shell; an unguarded top-level \`git\` at ${o.file}:${o.gitLine} runs in `
      + `whatever directory the parent shell was already in, not the one the substitution changed to. `
      + `\n      cd:  ${o.cdText}\n      git: ${o.gitText}`,
    );
  }

  if (baseRows && baseRows.length > 0) {
    for (const v of compare(baseRows, rows)) {
      if (v.kind === 'NEW' || v.kind === 'RISE') {
        problems.push(
          `${v.kind} ${v.name} ${v.base} -> ${v.now} — a new \`cd\`-inside-a-substitution occurrence. `
          + 'If it is genuinely safe (nothing outside the substitution depends on the directory change), '
          + 're-record the baseline on purpose: node .aai/scripts/check-cd-subshell-leak.mjs --record',
        );
      } else {
        notes.push(`${v.kind} ${v.name} ${v.base} -> ${v.now} (the bar is not lowered automatically)`);
      }
    }
  }

  const byClass = { UNSAFE: 0, SAFE: 0 };
  for (const o of occ) byClass[o.cls] += 1;

  if (args.json) {
    process.stdout.write(`${JSON.stringify({
      root, scanned_files: files.length, total, by_class: byClass,
      occurrences: occ, counts: rows, notes, problems,
    }, null, 2)}\n`);
  } else {
    process.stdout.write(
      `cd-subshell leaks: ${total} occurrence(s) in ${rows.length} of ${files.length} scanned file(s) `
      + `(UNSAFE ${byClass.UNSAFE}, SAFE ${byClass.SAFE})\n`,
    );
    for (const nt of notes) process.stdout.write(`NOTE: ${nt}\n`);
    for (const p of problems) process.stderr.write(`FAIL: ${p}\n`);
  }

  process.exit(problems.length > 0 ? 1 : 0);
}

// fileURLToPath, never new URL(...).pathname: a repo checked out under a path
// with a space would otherwise never match and this script would exit 0
// having done nothing (the same anti-no-op reasoning as the sibling
// check-base-ref-pins.mjs).
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main();
}
