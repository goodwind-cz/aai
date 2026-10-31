// lib/harness-shims.mjs — render the six root instruction shims from one registry
// (SPEC spec-provider-adapter-registry-slice D1, D3, D4; RFC-0017 phase 4).
//
// REGISTRY. The `shims:` section of .aai/system/HARNESS_SKILLS.yaml holds one
// row per generated file, `<path>|<fragments>|<name>|<cli>`: `<fragments>` is
// a `+`-joined ordered list of fragment ids, `<name>` and `<cli>` are the
// values of the only two placeholders (`-` when the fragments use none). The
// fragment text lives in .aai/system/HARNESS_SHIMS.md: a fragment starts at a
// line that is exactly `<!-- fragment: <id> -->` and runs to the next such
// line or the end of the file; bytes before the first fragment line are a
// header and are ignored. A shim is its row's fragments concatenated in order
// with `{{name}}` and `{{cli}}` replaced. The six allowed paths are hardcoded
// here (as REQUIRED_MIRROR_TREES is in sync-harness-skills.mjs).
//
// WHAT THE GATE COMPARES. For every declared path, the bytes on disk under
// the root against the rendered bytes; and the normalized hash of the rendered
// Copilot shim against the rows of .aai/system/COPILOT_SHIM_SHIPPED.list. It
// does not judge whether the text is right for the harness that reads it.
//
// COPILOT_SHIM_SHIPPED.list holds one lowercase 64-hex sha256 per line (`#`
// comments and blank lines ignored): the hash of N(text), where N deletes
// every CR and then the trailing LF characters. aai-sync reads it to tell an
// unmodified older shim from a real project override.
//
// Node stdlib only (docs/TECHNOLOGY.md). Errors are ShimError (the caller maps
// them to exit 2); nothing here exits.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export class ShimError extends Error {}

export const SHIM_PATHS = [
  'CLAUDE.md',
  'AGENTS.md',
  'CODEX.md',
  'GEMINI.md',
  '.github/copilot-instructions.md',
  '.cursor/rules/aai.mdc',
];
const PLACEHOLDERS = ['name', 'cli'];
const FRAGMENTS_REL = '.aai/system/HARNESS_SHIMS.md';
const SHIPPED_LIST_REL = '.aai/system/COPILOT_SHIM_SHIPPED.list';
const COPILOT_REL = '.github/copilot-instructions.md';
const FRAGMENT_LINE = /^<!-- fragment: ([a-z0-9-]+) -->$/;
const ID_RE = /^[a-z0-9-]+$/;
const HASH_RE = /^[0-9a-f]{64}$/;

export const NONE_LINE = 'SHIMS: none declared';
export const okLine = (n) => `OK: ${n} shim(s) match the registry`;

export function normalizedHash(text) {
  const n = text.replace(/\r/g, '').replace(/\n+$/, '');
  return crypto.createHash('sha256').update(n).digest('hex');
}

function readOrNull(abs) {
  try {
    return fs.readFileSync(abs, 'utf8');
  } catch (err) {
    if (err && (err.code === 'ENOENT' || err.code === 'ENOTDIR' || err.code === 'EISDIR')) return null;
    throw err;
  }
}

// --- parsing -------------------------------------------------------------------

export function parseFragments(raw) {
  const fragments = new Map();
  let current = null;
  for (const piece of raw.split(/(?<=\n)/)) {
    const m = piece.replace(/\r?\n$/, '').match(FRAGMENT_LINE);
    if (m) {
      if (fragments.has(m[1])) throw new ShimError(`duplicate fragment id in ${FRAGMENTS_REL}: ${m[1]}`);
      current = m[1];
      fragments.set(current, '');
    } else if (current !== null) {
      fragments.set(current, fragments.get(current) + piece);
    }
  }
  return fragments;
}

export function parseRows(rawRows) {
  const rows = [];
  const seen = new Set();
  for (const raw of rawRows) {
    const parts = raw.split('|').map((p) => p.trim());
    if (parts.length !== 4 || parts.some((p) => p === '')) {
      throw new ShimError(`malformed shims row (want path|fragments|name|cli): ${raw}`);
    }
    const [file, frags, name, cli] = parts;
    const ids = frags.split('+');
    if (ids.some((id) => !ID_RE.test(id))) {
      throw new ShimError(`malformed shims row (fragment ids are [a-z0-9-]+ joined by +): ${raw}`);
    }
    if (!SHIM_PATHS.includes(file)) {
      throw new ShimError(`shims path is not an allowed shim path: ${file} (allowed: ${SHIM_PATHS.join(', ')})`);
    }
    if (seen.has(file)) throw new ShimError(`duplicate shims path: ${file}`);
    seen.add(file);
    rows.push({ file, ids, values: { name, cli } });
  }
  const missing = SHIM_PATHS.filter((p) => !seen.has(p));
  if (missing.length > 0) throw new ShimError(`shims section missing path(s): ${missing.join(', ')}`);
  return rows;
}

// --- rendering -----------------------------------------------------------------

function render(rows, fragments) {
  for (const [id, text] of fragments) {
    for (const m of text.matchAll(/\{\{([^}]*)\}\}/g)) {
      if (!PLACEHOLDERS.includes(m[1])) {
        throw new ShimError(`unknown placeholder {{${m[1]}}} in fragment ${id} (allowed: ${PLACEHOLDERS.join(', ')})`);
      }
    }
  }
  const used = new Set();
  for (const row of rows) {
    for (const id of row.ids) {
      if (!fragments.has(id)) throw new ShimError(`undefined fragment ${id} named by ${row.file}`);
      used.add(id);
    }
  }
  for (const id of fragments.keys()) {
    if (!used.has(id)) throw new ShimError(`unused fragment ${id}: no shims row names it`);
  }
  return rows.map((row) => {
    const text = row.ids.map((id) => fragments.get(id)).join('');
    const expected = text.replace(/\{\{(name|cli)\}\}/g, (_, key) => {
      if (row.values[key] === '-') {
        throw new ShimError(`${row.file} uses {{${key}}} but its ${key} value is '-'`);
      }
      return row.values[key];
    });
    return { rel: row.file, expected };
  });
}

// assertRealPath(root, rel) — lstat each existing component of rel below root:
// a symlink anywhere, a non-directory parent or a non-file leaf refuses, so a
// write can never follow a link out of --root. A missing component ends the walk.
// escapesRoot(root, rel) — true when rel is absolute, holds a '..' segment under either
// separator (a Windows manifest may say ..\\x), or resolves outside root.
export function escapesRoot(root, rel) {
  if (path.isAbsolute(rel) || path.win32.isAbsolute(rel) || rel.split(/[\\/]/).includes('..')) return true;
  const back = path.relative(path.resolve(root), path.resolve(root, rel));
  return back === '..' || back.startsWith('..' + path.sep) || path.isAbsolute(back);
}

export function assertRealPath(root, rel) {
  if (escapesRoot(root, rel)) throw new ShimError(`refusing ${rel}: path escapes the root`);
  const parts = rel.split('/');
  for (let i = 0; i < parts.length; i++) {
    const sub = parts.slice(0, i + 1).join('/');
    let st;
    try {
      st = fs.lstatSync(path.join(root, sub));
    } catch (err) {
      if (err && err.code === 'ENOENT') return;
      throw err;
    }
    if (st.isSymbolicLink()) throw new ShimError(`refusing ${rel}: ${sub} is a symlink`);
    const last = i === parts.length - 1;
    if (!last && !st.isDirectory()) throw new ShimError(`refusing ${rel}: ${sub} is not a directory`);
    if (last && !st.isFile()) throw new ShimError(`refusing ${rel}: not a regular file`);
  }
}

// loadShims(root, rawRows) — null when the manifest has no `shims:` section.
// Every shim path and the shipped list are checked by assertRealPath here,
// before any write.
export function loadShims(root, rawRows) {
  if (rawRows === null) return null;
  const rows = parseRows(rawRows);
  const raw = readOrNull(path.join(root, FRAGMENTS_REL));
  if (raw === null) throw new ShimError(`cannot read the fragment file ${FRAGMENTS_REL}`);
  const outputs = render(rows, parseFragments(raw));
  for (const { rel } of outputs) assertRealPath(root, rel);
  assertRealPath(root, SHIPPED_LIST_REL);
  return { outputs };
}

// --- check / write ---------------------------------------------------------------

function firstDifference(actual, expected) {
  const a = actual.split('\n');
  const e = expected.split('\n');
  for (let i = 0; i < Math.max(a.length, e.length); i++) {
    if (a[i] !== e[i]) {
      const shown = a[i] === undefined ? '(end of file)' : JSON.stringify(a[i].slice(0, 80));
      return `line ${i + 1}: ${shown}`;
    }
  }
  return '(content differs)';
}

function readShippedRows(listAbs) {
  const raw = readOrNull(listAbs);
  const rows = new Set();
  if (raw === null) return { raw: null, rows };
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    if (!HASH_RE.test(t)) throw new ShimError(`malformed row in ${SHIPPED_LIST_REL} (want lowercase sha256): ${t}`);
    rows.add(t);
  }
  return { raw, rows };
}

// applyShims(root, plan, { write }) — compares (and with write, restores) every
// declared shim and the Copilot hash row. Returns { drift: [line], written: n }.
export function applyShims(root, plan, { write }) {
  const drift = [];
  let written = 0;
  for (const { rel, expected } of plan.outputs) {
    const abs = path.join(root, rel);
    const actual = readOrNull(abs);
    if (actual !== expected) drift.push(
      `DIVERGE shim ${rel}: ${actual === null ? 'absent' : firstDifference(actual, expected)}`
    );
    if (write && actual !== expected) {
      fs.mkdirSync(path.dirname(abs), { recursive: true });
      fs.writeFileSync(abs, expected);
      written++;
    }
  }
  const copilot = plan.outputs.find((o) => o.rel === COPILOT_REL);
  const hash = normalizedHash(copilot.expected);
  const listAbs = path.join(root, SHIPPED_LIST_REL);
  const shipped = readShippedRows(listAbs);
  if (!shipped.rows.has(hash)) {
    drift.push(`DIVERGE shim ${COPILOT_REL}: unrecorded ${hash}`);
    if (write) {
      fs.mkdirSync(path.dirname(listAbs), { recursive: true });
      const lead = shipped.raw !== null && shipped.raw !== '' && !shipped.raw.endsWith('\n') ? '\n' : '';
      fs.appendFileSync(listAbs, `${lead}${hash}\n`);
      written++;
    }
  }
  return { drift, written };
}
