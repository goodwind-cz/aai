// state-engine.mjs — the shared STATE.yaml structural LINE ENGINE
// (CHANGE-0009 / spec-mechanize-deterministic-ticks D5).
//
// Extracted VERBATIM from state.mjs (CHANGE-0006 / SPEC-0012 D2/D3) so the
// transactional CLI, metrics-flush.mjs, and orchestration-dispatch.mjs share
// ONE implementation of the block/line machinery: no YAML library — a target
// top-level block is located by its column-0 key and ONLY the lines inside it
// are edited; comments, key order, and every other line survive byte-identical
// by construction. The commented schema header can never be mistaken for a real
// field (column-0 match — the CHANGE-0005 timestamp-regex mishap class).
//
// The engine NEVER re-serializes a whole file: writeState re-emits the exact
// line array (atomic tmp + optimistic concurrency recheck + rename).
//
// Error posture: every refusal goes through engineFail(), which prints
// `<prefix>: <message>` and exits — callers set their own prefix via
// setEngineFailPrefix('state' | 'metrics-flush' | ...) so stderr text stays
// byte-identical to the pre-extraction behavior (the 50+-test state suite
// guards this refactor).

import fs from 'node:fs';
import { BLOCK_SCALAR_REST_RE, TOP_KEY_RE, duplicateKeys, inlineChildConflicts, joinLines, splitLines } from './state-core.mjs';

// --- failure channel ----------------------------------------------------------

let FAIL_PREFIX = 'state-engine';

export function setEngineFailPrefix(prefix) {
  FAIL_PREFIX = prefix;
}

export function engineFail(msg, code = 2) {
  console.error(`${FAIL_PREFIX}: ${msg}`);
  process.exit(code);
}

const fail = (msg, code = 2) => engineFail(msg, code);

export function nowIso() {
  return new Date().toISOString().replace(/\.\d+Z$/, 'Z');
}

// --- load / atomic write (SPEC-0012 D3) ----------------------------------------

export function loadState(statePath) {
  if (!fs.existsSync(statePath)) fail(`STATE file not found: ${statePath}`);
  const raw = fs.readFileSync(statePath, 'utf8');   // exact bytes for the pre-rename concurrency recheck
  const { lines, trailingNewline } = splitLines(raw);
  const dups = duplicateKeys(lines);
  if (dups.length > 0) {
    fail(`refusing to edit ${statePath}: it ALREADY has duplicate top-level key(s) `
      + `[${dups.map(d => `${d.key} x${d.count}`).join(', ')}] — repair first with: `
      + `node .aai/scripts/check-state.mjs --repair ${statePath}`, 1);
  }
  return { lines, trailingNewline, raw, statePath };
}

export function injectCrash(point) {
  if (process.env.AAI_STATE_INJECT_CRASH === point) {
    // Die UNCLEANLY at exactly this point (deterministic kill-mid-write tests).
    process.kill(process.pid, 'SIGKILL');
  }
}

export function writeState(statePath, lines, trailingNewline, expectedRaw) {
  const dups = duplicateKeys(lines);
  if (dups.length > 0) {
    fail(`refusing to write ${statePath}: the mutation would create duplicate top-level key(s) `
      + `[${dups.map(d => d.key).join(', ')}] — original file preserved`, 1);
  }
  const conflicts = inlineChildConflicts(lines);
  if (conflicts.length > 0) {
    fail(`refusing to write ${statePath}: the mutation would splice child lines under an `
      + `inline-valued top-level header [${conflicts.map(c => c.key).join(', ')}] (invalid YAML) `
      + '— original file preserved', 1);
  }
  const content = joinLines(lines, trailingNewline);
  const tmp = `${statePath}.tmp-${process.pid}`;
  if (process.env.AAI_STATE_INJECT_CRASH === 'during-write') {
    // Simulate a crash mid-write: partial tmp content, then die. The TARGET is
    // untouched — rename below is the sole commit point.
    fs.writeFileSync(tmp, content.slice(0, Math.floor(content.length / 2)));
    process.kill(process.pid, 'SIGKILL');
  }
  fs.writeFileSync(tmp, content);
  injectCrash('before-rename');
  if (process.env.AAI_STATE_INJECT_CONCURRENT === 'before-rename') {
    // Test-only fault hook: simulate a SECOND writer committing between our
    // load and our rename (deterministic lost-update race).
    fs.appendFileSync(statePath, '# concurrent-writer marker (test injection)\n');
  }
  // Optimistic concurrency recheck (single-writer posture, W4): if the target
  // no longer matches the bytes captured at load, another writer committed in
  // between — renaming our stale copy over it would silently LOSE that write.
  if (expectedRaw !== undefined && fs.readFileSync(statePath, 'utf8') !== expectedRaw) {
    fs.rmSync(tmp, { force: true });
    fail(`concurrent modification detected: ${statePath} changed after it was read `
      + '— no write performed; re-run the command to retry on the fresh file', 1);
  }
  fs.renameSync(tmp, statePath);   // atomic on same-filesystem POSIX
}

export function bumpUpdatedAt(lines, stampIso) {
  const stamp = `updated_at_utc: ${stampIso ?? nowIso()}`;
  for (let i = 0; i < lines.length; i += 1) {
    if (/^updated_at_utc:/.test(lines[i])) { lines[i] = stamp; return; }
  }
  lines.push(stamp);
}

// --- block engine (SPEC-0012 D2) ------------------------------------------------

export function findBlock(lines, key) {
  for (let i = 0; i < lines.length; i += 1) {
    const m = lines[i].match(TOP_KEY_RE);
    if (!m || m[1] !== key) continue;
    let end = lines.length;
    for (let j = i + 1; j < lines.length; j += 1) {
      const l = lines[j];
      if (l.startsWith('#') || l.startsWith('---')) continue;
      if (TOP_KEY_RE.test(l)) { end = j; break; }
    }
    return { start: i, end };
  }
  return null;
}

// Ensure a top-level block exists; create it (header + defaultLines) before the
// real `updated_at_utc:` line (or at EOF) when missing.
export function ensureBlock(lines, key, defaultLines = []) {
  let b = findBlock(lines, key);
  if (b) return b;
  let insertAt = lines.length;
  for (let i = 0; i < lines.length; i += 1) {
    if (/^updated_at_utc:/.test(lines[i])) { insertAt = i; break; }
  }
  lines.splice(insertAt, 0, `${key}:`, ...defaultLines, '');
  return findBlock(lines, key);
}

// Edit one top-level block in place: fn(blockLines) returns the new block lines.
// Refuses (exit 1) when the block header carries an inline value (`metrics: {}`,
// `metrics: null`, ...): splicing nested lines under it would write invalid YAML
// (mapping value given twice) — refuse rather than corrupt (D2 posture; review
// W2). `opts.allowInline` whitelists a header rest the caller converts itself
// (e.g. set-phase handles `active_work_items: []`).
export function editBlock(lines, key, fn, defaultLines = [], opts = {}) {
  const b = ensureBlock(lines, key, defaultLines);
  const header = lines[b.start];
  const rest = header.slice(header.indexOf(':') + 1).trim();
  if (rest !== '' && !rest.startsWith('#') && !(opts.allowInline && opts.allowInline.test(rest))) {
    fail(`refusing to edit top-level block "${key}": its header carries an inline value `
      + `(\`${header.trim()}\`) that the line engine cannot safely splice nested lines under `
      + `— convert it to block form (bare \`${key}:\` header) by hand first; file preserved`, 1);
  }
  const blockLines = lines.slice(b.start, b.end);
  const next = fn(blockLines) ?? blockLines;
  lines.splice(b.start, b.end - b.start, ...next);
}

export function indentOf(line) {
  const m = line.match(/^ */);
  return m ? m[0].length : 0;
}

// Number of lines the field starting at blockLines[idx] occupies (the field
// line plus any more-indented continuation lines: `>-` scalars, list items).
// Blank lines are legal INSIDE block scalars (YAML spec): a blank run belongs
// to the span only when a MORE-indented continuation follows it — stopping at
// the first blank orphaned post-blank paragraphs of hand-edited `>-` fields on
// clear/overwrite (review-20260707T081303Z W2). Otherwise the field ends there.
export function fieldSpan(blockLines, idx, indent) {
  let n = 1;
  for (let j = idx + 1; j < blockLines.length; j += 1) {
    const l = blockLines[j];
    if (l.trim() === '') {
      let k = j;
      while (k < blockLines.length && blockLines[k].trim() === '') k += 1;
      if (k < blockLines.length && indentOf(blockLines[k]) > indent) {
        n = k - idx + 1;   // the blank run + its continuation join the span
        j = k;
        continue;
      }
      break;
    }
    if (indentOf(l) > indent) n += 1;
    else break;
  }
  return n;
}

export function fieldRe(indent, name) {
  return new RegExp(`^ {${indent}}${name}:(\\s|$)`);
}

export function scalarLine(indent, name, value) {
  return `${' '.repeat(indent)}${name}: ${value}`;
}

// A plain scalar YAML could misparse: `: ` / trailing `:` (second mapping
// value), ` #` (comment opener), leading indicator characters, or leading/
// trailing whitespace. Already-safe values (paths, refs, timestamps, enums)
// never match, so they stay unquoted and diffs stay minimal (review W3).
export function needsQuoting(v) {
  if (v === '') return true;
  if (/^[\s#\[\]{}&*!|>%@`"',]/.test(v)) return true;   // leading indicator char
  if (/^[?:-](\s|$)/.test(v)) return true;              // `- x` / `? x` / `: x` / bare
  if (/:(\s|$)/.test(v)) return true;                   // `k: v` inside, or trailing colon
  if (/\s#/.test(v)) return true;                       // opens a comment mid-value
  if (/\s$/.test(v)) return true;                       // trailing whitespace
  return false;
}

// Quote a USER-SUPPLIED plain-scalar value when needed (single-quoted, `'`
// doubled). Newlines/control chars cannot live on a single plain-scalar line at
// all — reject exit 2 before any write (free-text belongs in `>-` fields).
export function yq(value) {
  const s = String(value);
  if (/[\r\n\t\0]/.test(s)) {
    fail(`value ${JSON.stringify(s)} contains a newline/control character — not representable `
      + 'as a plain scalar field (use a free-text --notes/--rationale style field)');
  }
  return needsQuoting(s) ? `'${s.replace(/'/g, "''")}'` : s;
}

// Free-text values are always written as `>-` block scalars (D2 normalization).
export function textFieldLines(indent, name, text) {
  const sp = ' '.repeat(indent);
  const out = [`${sp}${name}: >-`];
  const segs = String(text).split(/\r?\n/).map(s => s.trim()).filter(s => s !== '');
  if (segs.length === 0) return [scalarLine(indent, name, 'null')];
  for (const seg of segs) out.push(`${sp}  ${seg}`);
  return out;
}

export function listFieldLines(indent, name, items) {
  if (!items || items.length === 0) return [scalarLine(indent, name, '[]')];
  const sp = ' '.repeat(indent);
  const out = [`${sp}${name}:`];
  for (const it of items) out.push(`${sp}  - ${yq(it)}`);
  return out;
}

// Replace (or create at end of block) the field `name` at `indent` inside a
// top-level block's lines. `newLines` is the full replacement line array.
export function setField(blockLines, indent, name, newLines) {
  const re = fieldRe(indent, name);
  for (let i = 1; i < blockLines.length; i += 1) {
    if (re.test(blockLines[i])) {
      const n = fieldSpan(blockLines, i, indent);
      blockLines.splice(i, n, ...newLines);
      return blockLines;
    }
  }
  let at = blockLines.length;
  while (at > 1 && (blockLines[at - 1].trim() === '' || blockLines[at - 1].startsWith('#'))) at -= 1;
  blockLines.splice(at, 0, ...newLines);
  return blockLines;
}

// Null a field only when it already exists (used by set-human-input false).
export function nullFieldIfPresent(blockLines, indent, name) {
  const re = fieldRe(indent, name);
  for (let i = 1; i < blockLines.length; i += 1) {
    if (re.test(blockLines[i])) {
      const n = fieldSpan(blockLines, i, indent);
      blockLines.splice(i, n, scalarLine(indent, name, 'null'));
      return blockLines;
    }
  }
  return blockLines;
}

// Append items to a list field; converts an inline `name: []` to block form;
// creates the field when missing.
export function appendListItems(blockLines, indent, name, items) {
  const sp = ' '.repeat(indent);
  const itemLines = items.map(it => `${sp}  - ${yq(it)}`);
  const re = fieldRe(indent, name);
  for (let i = 1; i < blockLines.length; i += 1) {
    if (!re.test(blockLines[i])) continue;
    const rest = blockLines[i].slice(blockLines[i].indexOf(':') + 1).trim();
    if (rest === '[]' || rest === '') {
      const n = fieldSpan(blockLines, i, indent);
      const existing = rest === '' ? blockLines.slice(i + 1, i + n) : [];
      blockLines.splice(i, n, `${sp}${name}:`, ...existing, ...itemLines);
      return blockLines;
    }
    fail(`cannot append to non-empty inline list "${name}: ${rest}" — convert it to block form first`);
  }
  let at = blockLines.length;
  while (at > 1 && (blockLines[at - 1].trim() === '' || blockLines[at - 1].startsWith('#'))) at -= 1;
  blockLines.splice(at, 0, `${sp}${name}:`, ...itemLines);
  return blockLines;
}

// Read a direct scalar field value from a top-level block ('null' -> null).
export function readScalar(lines, blockKey, field, indent = 2) {
  const b = findBlock(lines, blockKey);
  if (!b) return null;
  const re = fieldRe(indent, field);
  for (let i = b.start + 1; i < b.end; i += 1) {
    if (re.test(lines[i])) {
      const v = lines[i].slice(lines[i].indexOf(':') + 1).trim();
      return v === '' || v === 'null' ? null : v;
    }
  }
  return null;
}

// Strip one layer of single/double quoting from a scalar read off a YAML line.
export function unquoteScalar(v) {
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
    return v.slice(1, -1).replace(/''/g, "'");
  }
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) return v.slice(1, -1);
  return v;
}

// --- metrics.work_items agent_runs scan (read-only) ----------------------------
//
// One scan shared by state.mjs (validator independence), metrics-flush.mjs and
// orchestration-dispatch.mjs (validator_independence payload / forensics) — the
// "same scan as lastImplementerModel" mandate (CHANGE-0009 D2).

// Locate the `    <ref>:` entry span inside the metrics block (exact string
// compare — a ref may be an arbitrary scalar read back from
// last_validation.ref_id, never regex it). Returns { start, end } or null.
export function metricsEntrySpan(lines, ref) {
  const b = findBlock(lines, 'metrics');
  if (!b) return null;
  let e0 = -1;
  for (let i = b.start + 1; i < b.end; i += 1) {
    if (lines[i].replace(/\s+$/, '') === `    ${ref}:`) { e0 = i; break; }
  }
  if (e0 === -1) return null;
  let e1 = b.end;
  for (let j = e0 + 1; j < b.end; j += 1) {
    const l = lines[j];
    if (l.trim() === '' || l.trim().startsWith('#')) continue;
    if (indentOf(l) < 6) { e1 = j; break; }   // next work_items key or dedent
  }
  return { start: e0, end: e1 };
}

// Parse the agent_runs of a metrics.work_items entry into [{ role, model_id }]
// in file order. Returns [] when metrics/ref/agent_runs is missing or inline.
export function agentRunsFor(lines, ref) {
  const span = metricsEntrySpan(lines, ref);
  if (!span) return [];
  const { start: e0, end: e1 } = span;
  let arIdx = -1;
  for (let i = e0 + 1; i < e1; i += 1) {
    if (/^ {6}agent_runs:\s*$/.test(lines[i])) { arIdx = i; break; }
    if (/^ {6}agent_runs:\s*\S/.test(lines[i])) return [];   // inline [] / scalar
  }
  if (arIdx === -1) return [];
  const runs = [];
  let current = null;
  for (let i = arIdx + 1; i < e1; i += 1) {
    const l = lines[i];
    if (l.trim() === '') continue;
    if (indentOf(l) < 8) break;
    let m = l.match(/^ {8}- role:\s*(.*)$/);
    if (m) {
      current = { role: unquoteScalar(m[1].trim()), model_id: null };
      runs.push(current);
      continue;
    }
    m = l.match(/^ {10}model_id:\s*(.*)$/);
    if (m && current) {
      const v = unquoteScalar(m[1].trim());
      if (v !== '' && v !== 'null') current.model_id = v;
    }
  }
  return runs;
}

// model_id of the LAST run whose role is Implementation or TDD Implementation
// under metrics.work_items[<ref>].agent_runs. Returns null when metrics/ref/
// agent_runs/implementer-run is missing — callers treat null as "skip safely"
// (never block honest work).
export function lastImplementerModel(lines, ref) {
  let lastImplModel = null;
  for (const run of agentRunsFor(lines, ref)) {
    if ((run.role === 'Implementation' || run.role === 'TDD Implementation') && run.model_id !== null) {
      lastImplModel = run.model_id;
    }
  }
  return lastImplModel;
}
