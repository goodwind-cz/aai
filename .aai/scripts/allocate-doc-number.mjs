#!/usr/bin/env node
// Merge-time sequential doc-number allocator (RFC-0007 Option C / SPEC-0015).
//
// Durable doc identity is the slug `id`, assigned at intake on the DRAFT file
// `docs/<type>/<TYPE>-DRAFT-<slug>.md` with `number: null`. The sequential
// `TYPE-000N` DISPLAY number is assigned HERE, at the merge serialization point:
// the next number is derived from the BASE REF (read via git, not the working
// tree) unioned with any locally-numbered-but-unmerged docs, so two branches
// minted off one main can never both merge the same number — the second
// re-derives the next (the exact bug RFC-0007 fixes).
//
// Node stdlib only (zero deps, plain `node` invocation, per docs/TECHNOLOGY.md).
//
// Usage:
//   node .aai/scripts/allocate-doc-number.mjs [--path <draft-file>] [--type <t>]
//        [--base-ref <ref>] [--all] [--backfill] [--dry-run] [--guard]
//   Default --base-ref is origin/main.
//
// Exit codes (SPEC-0015 D3):
//   0  success (drafts numbered, backfilled, guard clean, or nothing to do)
//   2  usage error (unknown flag / unknown --type / --path not a DRAFT doc). No writes.
//   3  base ref unreachable (offline / fetch failed): degrade-and-report, DRAFT byte-identical.
//   4  guard failure: computed number collides on the base ref, malformed DRAFT
//      frontmatter (no slug id), or a --guard predicate found a violation.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { parseFrontmatter } from './lib/docs-model.mjs';

// --- doc-type map ------------------------------------------------------------
// Intake-facing type -> (directory, id prefix). The directory is not 1:1 with a
// prefix (docs/issues hosts ISSUE, CHANGE, DEBT), so the DISPLAY prefix for an
// already-named file is always read from the filename leading token; this map is
// only for creating a fresh DRAFT path from an intake `type`.
export const TYPE_MAP = {
  rfc: { dir: 'rfc', prefix: 'RFC' },
  spec: { dir: 'specs', prefix: 'SPEC' },
  issue: { dir: 'issues', prefix: 'ISSUE' },
  change: { dir: 'issues', prefix: 'CHANGE' },
  techdebt: { dir: 'issues', prefix: 'DEBT' },
  debt: { dir: 'issues', prefix: 'DEBT' },
  prd: { dir: 'requirements', prefix: 'PRD' },
  requirement: { dir: 'requirements', prefix: 'PRD' },
  release: { dir: 'releases', prefix: 'REL' },
};

// Directories that hold governed, numberable docs (index/guard scope).
export const GOVERNED_DIRS = ['rfc', 'specs', 'issues', 'requirements', 'releases'];

// --- pure helpers (unit-testable without git) --------------------------------

// Slug = kebab-case of the topic (SPEC-0015 D1). lowercase; transliterate to
// ASCII (NFKD + strip diacritics); replace any run of non-[a-z0-9] with a single
// hyphen; strip leading/trailing hyphens; collapse repeats; truncate to at most
// 48 characters at a hyphen boundary (never mid-word). Empty-reduced -> ''.
export function deriveSlug(topic) {
  const ascii = String(topic ?? '')
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '') // strip combining diacritics
    .toLowerCase();
  let slug = ascii
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (slug.length > 48) {
    slug = slug.slice(0, 48);
    const lastHyphen = slug.lastIndexOf('-');
    if (lastHyphen > 0) slug = slug.slice(0, lastHyphen);
    slug = slug.replace(/-+$/g, '');
  }
  return slug;
}

// Deterministic 4-char lowercase base36 collision-defeating suffix derived from
// a seed (branch name, or author + intake timestamp). Same seed -> same suffix;
// different seeds -> (with overwhelming probability) different suffixes.
export function collisionSuffix(seed) {
  const h = crypto.createHash('sha256').update(String(seed ?? '')).digest();
  const n = h.readUInt32BE(0);
  return n.toString(36).padStart(4, '0').slice(-4);
}

// Resolve an intake `type` to its (dir, prefix). Throws on an unknown type.
export function resolveType(type) {
  const t = String(type ?? '').toLowerCase();
  const m = TYPE_MAP[t];
  if (!m) throw new Error(`unknown --type "${type}"`);
  return m;
}

// docs/<dir>/<PREFIX>-DRAFT-<slug>[-<suffix>].md
export function draftFilename(type, slug, suffix) {
  const { dir, prefix } = resolveType(type);
  const tail = suffix ? `${slug}-${suffix}` : slug;
  return `docs/${dir}/${prefix}-DRAFT-${tail}.md`;
}

// Zero-padded display id from a prefix + integer number. Width defaults to 4
// (this repo's universal practice) but callers that know the type's existing
// convention pass it explicitly (ISSUE per-type-digit-width: PRD is 3-digit).
export function displayId(prefix, number, width = 4) {
  return `${prefix}-${String(number).padStart(width, '0')}`;
}

// Digit-width of the number token in a numbered basename, else null
// (PRD-001-x.md -> 3, RFC-0007-x.md -> 4).
export function numberWidthFromBasename(basename) {
  const m = String(basename).match(/^[A-Z]+(?:-[A-Z]+)*-(\d{1,5})(?=[-.])/);
  return m ? m[1].length : null;
}

// Default widths for types with NO existing numbered docs. PRD keeps the
// original documented convention (PRD-001 examples across the canon); every
// other prefix follows this repo's practice (RFC-0001, SPEC-0001, ...).
export const DEFAULT_WIDTHS = { PRD: 3 };

// Display width for a prefix — cascade (ISSUE per-type-digit-width +
// ISSUE project-dominant-width):
//   1. the width recorded on the type's HIGHEST-numbered existing doc
//      (base ref preferred over local on a tie);
//   2. else the PROJECT's dominant width across all numbered governed docs
//      (a vendored project with an all-3-digit convention mints 3-digit for
//      its first doc of a new type);
//   3. else the per-type greenfield default.
// Maps are number -> digit-width as produced by baseRefNumbers/localNumbers.
export function deriveWidth(prefix, baseMap, localMap, projectWidth = null) {
  let bestNum = -1;
  let bestWidth = null;
  for (const m of [localMap, baseMap]) { // base last so it wins ties
    for (const [num, width] of m) {
      if (num >= bestNum) { bestNum = num; bestWidth = width; }
    }
  }
  return bestWidth ?? projectWidth ?? DEFAULT_WIDTHS[prefix] ?? 4;
}

// Dominant (modal) digit-width across ALL numbered governed docs on the base
// ref ∪ local working tree; null when the project has no numbered docs.
// Tie-break: 4 if 4 is among the tied widths, else the smallest tied width
// (deterministic).
export function projectDominantWidth(root, baseSha) {
  const counts = new Map(); // width -> occurrences
  const bump = (basename) => {
    const w = numberWidthFromBasename(basename);
    if (w != null) counts.set(w, (counts.get(w) ?? 0) + 1);
  };
  for (const dir of GOVERNED_DIRS) {
    if (baseSha) {
      const listing = git(root, ['ls-tree', '-r', '--name-only', baseSha, '--', `docs/${dir}`]);
      if (listing) for (const line of listing.split('\n')) bump(path.basename(line));
    }
    const abs = path.join(root, 'docs', dir);
    if (fs.existsSync(abs)) for (const f of fs.readdirSync(abs)) bump(f);
  }
  if (counts.size === 0) return null;
  let best = null;
  let bestCount = -1;
  for (const [w, c] of counts) {
    if (c > bestCount || (c === bestCount && (w === 4 || (best !== 4 && w < best)))) {
      best = w; bestCount = c;
    }
  }
  return best;
}

// Leading id-prefix token from a basename: RFC, SPEC, CHANGE, DECISION-RFC, ...
export function prefixFromBasename(basename) {
  const m = String(basename).match(/^([A-Z]+(?:-[A-Z]+)*)-(?:DRAFT|\d{1,5})(?=[-.])/);
  return m ? m[1] : null;
}

// Numeric TYPE-000N number encoded in a basename, else null.
export function numberFromBasename(basename) {
  const m = String(basename).match(/^[A-Z]+(?:-[A-Z]+)*-(\d{1,5})(?=[-.])/);
  return m ? parseInt(m[1], 10) : null;
}

// Next number = max(existing) + 1 over a set/array of integers (1 when empty).
export function nextNumber(existingNumbers) {
  let max = 0;
  for (const n of existingNumbers) {
    const v = Number(n);
    if (Number.isInteger(v) && v > max) max = v;
  }
  return max + 1;
}

// Parse the frontmatter `number:` as an integer, else null.
export function numberFromFrontmatter(fm) {
  if (!fm) return null;
  const raw = fm.number;
  if (raw == null) return null;
  const s = String(raw).trim();
  return /^\d+$/.test(s) ? parseInt(s, 10) : null;
}

// Stamp `number: N` into a doc's frontmatter, preserving all other bytes.
// Replaces an existing `number:` line, else inserts one right after `id:`.
// EOL-agnostic: detects whether the frontmatter block uses LF or CRLF and
// preserves the file's existing line endings byte-for-byte (a CRLF `---\r\n…`
// draft is stamped exactly like an LF one — SPEC-0015 CRLF preservation).
export function stampNumber(content, n) {
  const open = content.match(/^---(\r?\n)/);
  if (!open) return null;
  const eol = open[1]; // '\n' or '\r\n'
  const fmEnd = content.indexOf(`${eol}---`, open[0].length);
  if (fmEnd < 0) return null;
  const head = content.slice(0, fmEnd);
  const rest = content.slice(fmEnd);
  if (/(\r?\n)[ \t]*number:[^\r\n]*/.test(head)) {
    return head.replace(/((\r?\n)[ \t]*number:)[^\r\n]*/, `$1 ${n}`) + rest;
  }
  if (/(\r?\n)[ \t]*id:[^\r\n]*/.test(head)) {
    return head.replace(/(\r?\n[ \t]*id:[^\r\n]*)/, `$1${eol}number: ${n}`) + rest;
  }
  return null;
}

// --- git plumbing ------------------------------------------------------------

function git(root, args, { allowFail = true } = {}) {
  try {
    return execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch (e) {
    if (allowFail) return null;
    throw e;
  }
}

// Best-effort fetch (when base ref is <remote>/<branch>), then resolve to a
// commit SHA. Returns null when the ref is unreachable (offline / bad ref).
function resolveBaseRef(root, baseRef) {
  const slash = baseRef.indexOf('/');
  if (slash > 0) {
    const remote = baseRef.slice(0, slash);
    const branch = baseRef.slice(slash + 1);
    git(root, ['fetch', remote, branch]); // best-effort; ignore failure
  }
  return git(root, ['rev-parse', '--verify', `${baseRef}^{commit}`]);
}

// Numbers for a given prefix present under docs/<dir> ON the base ref (read via
// git, NEVER the working tree). Union with locally-numbered-but-unmerged docs.
// Both return Map<number, digit-width> so allocation can inherit the type's
// existing zero-padding convention (ISSUE per-type-digit-width). Map.has(n)
// keeps the previous Set-style membership checks working.
function baseRefNumbers(root, baseRef, dir, prefix) {
  const nums = new Map();
  const listing = git(root, ['ls-tree', '-r', '--name-only', baseRef, '--', `docs/${dir}`]);
  if (listing) {
    for (const line of listing.split('\n')) {
      const base = path.basename(line);
      if (prefixFromBasename(base) === prefix) {
        const n = numberFromBasename(base);
        if (n != null) nums.set(n, numberWidthFromBasename(base));
      }
    }
  }
  return nums;
}

function localNumbers(root, dir, prefix) {
  const nums = new Map();
  const abs = path.join(root, 'docs', dir);
  if (!fs.existsSync(abs)) return nums;
  for (const f of fs.readdirSync(abs)) {
    if (!f.endsWith('.md')) continue;
    if (prefixFromBasename(f) === prefix) {
      const n = numberFromBasename(f);
      if (n != null) nums.set(n, numberWidthFromBasename(f));
    }
  }
  return nums;
}

// --- draft selection ---------------------------------------------------------

function isDraftBasename(base) {
  return /-DRAFT-/.test(base);
}

// True when `root` is inside a git work tree.
function isGitWorkTree(root) {
  return git(root, ['rev-parse', '--is-inside-work-tree']) === 'true';
}

// Governed doc files to evaluate for the guards (SPEC-0015 D6: the STAGED/MERGED
// tree). Inside a git work tree we enumerate the git-tracked + staged-add set via
// `git ls-files` so purely-untracked local drafts never trip the guard; content
// is still read from the working tree. Not a git repo -> fs walk (degrade-and-report).
function guardDocFiles(root) {
  if (isGitWorkTree(root)) {
    const specs = GOVERNED_DIRS.map((d) => `docs/${d}`);
    const listing = git(root, ['ls-files', '--', ...specs]);
    const files = [];
    if (listing) {
      for (const line of listing.split('\n')) {
        if (line.endsWith('.md')) files.push(line);
      }
    }
    return files;
  }
  const files = [];
  for (const dir of GOVERNED_DIRS) {
    const abs = path.join(root, 'docs', dir);
    if (!fs.existsSync(abs)) continue;
    for (const f of fs.readdirSync(abs)) {
      if (f.endsWith('.md')) files.push(`docs/${dir}/${f}`);
    }
  }
  return files;
}

function findAllDrafts(root) {
  const out = [];
  for (const dir of GOVERNED_DIRS) {
    const abs = path.join(root, 'docs', dir);
    if (!fs.existsSync(abs)) continue;
    for (const f of fs.readdirSync(abs)) {
      if (f.endsWith('.md') && isDraftBasename(f)) out.push(`docs/${dir}/${f}`);
    }
  }
  return out.sort();
}

// Rewrite in-repo references to the old DRAFT basename -> the new numbered
// basename across governed docs (path/link references; the slug `id` is
// unchanged so cross-references keyed on `id` need no rewrite).
function rewriteReferences(root, oldBase, newBase) {
  for (const dir of GOVERNED_DIRS) {
    const abs = path.join(root, 'docs', dir);
    if (!fs.existsSync(abs)) continue;
    for (const f of fs.readdirSync(abs)) {
      if (!f.endsWith('.md')) continue;
      const p = path.join(abs, f);
      const content = fs.readFileSync(p, 'utf8');
      if (!content.includes(oldBase)) continue;
      const updated = content.split(oldBase).join(newBase);
      if (updated !== content) fs.writeFileSync(p, updated);
    }
  }
}

function regenerateIndex(root) {
  const gen = path.join(root, '.aai/scripts/generate-docs-index.mjs');
  if (!fs.existsSync(gen)) return;
  try {
    execFileSync('node', [gen], { cwd: root, stdio: 'ignore' });
  } catch { /* degrade-and-report: index regen is best-effort */ }
}

function moveFile(root, fromRel, toRel) {
  const tracked = git(root, ['ls-files', '--error-unmatch', fromRel]) !== null;
  if (tracked) {
    const ok = git(root, ['mv', fromRel, toRel]);
    if (ok !== null) return;
  }
  fs.renameSync(path.join(root, fromRel), path.join(root, toRel));
  git(root, ['add', toRel]);
}

// --- CLI ---------------------------------------------------------------------

function parseArgs(argv) {
  const opts = { path: null, type: null, baseRef: 'origin/main', all: false, backfill: false, dryRun: false, guard: false };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    switch (tok) {
      case '--path': opts.path = argv[++i]; break;
      case '--type': opts.type = argv[++i]; break;
      case '--base-ref': opts.baseRef = argv[++i]; break;
      case '--all': opts.all = true; break;
      case '--backfill': opts.backfill = true; break;
      case '--dry-run': opts.dryRun = true; break;
      case '--guard': opts.guard = true; break;
      case '-h': case '--help': opts.help = true; break;
      default:
        if (tok.startsWith('--')) { opts._badFlag = tok; }
        else { (opts._extra ||= []).push(tok); }
    }
  }
  return opts;
}

function die(code, msg) {
  if (msg) console.error(msg);
  process.exit(code);
}

// --guard: scan the working tree for (a) any DRAFT / number:null governed doc and
// (b) two governed docs of the same prefix resolving to the same TYPE-000N.
function runGuard(root) {
  const drafts = [];
  const byDisplay = new Map(); // "PREFIX-000N" -> [{rel, id}]
  for (const rel of guardDocFiles(root)) {
    const abs = path.join(root, rel);
    if (!fs.existsSync(abs)) continue; // read content from the working tree
    const f = path.basename(rel);
    const content = fs.readFileSync(abs, 'utf8');
    const fm = parseFrontmatter(content);
    const prefix = prefixFromBasename(f);
    const fmNum = numberFromFrontmatter(fm);
    // no-DRAFT-at-merge predicate
    if (isDraftBasename(f) || (fm && 'number' in fm && fmNum == null && prefix)) {
      drafts.push(rel);
      continue;
    }
    // duplicate-number predicate
    const num = fmNum ?? numberFromBasename(f);
    if (prefix && num != null) {
      const key = displayId(prefix, num);
      if (!byDisplay.has(key)) byDisplay.set(key, []);
      byDisplay.get(key).push({ rel, id: fm?.id ?? path.basename(f, '.md') });
    }
  }
  let violations = 0;
  if (drafts.length > 0) {
    violations += drafts.length;
    console.error('GUARD FAIL (no-DRAFT-at-merge): unnumbered draft(s) present at the merge point:');
    for (const d of drafts) console.error(`  - ${d} — run /aai-pr or node .aai/scripts/allocate-doc-number.mjs`);
  }
  for (const [key, members] of byDisplay) {
    if (members.length > 1) {
      violations += 1;
      console.error(`GUARD FAIL (duplicate-number): ${members.length} docs resolve to ${key}:`);
      for (const m of members) console.error(`  - ${m.rel} (id: ${m.id})`);
    }
  }
  if (violations > 0) die(4, `Doc-numbering guard found ${violations} violation(s).`);
  console.log('Doc-numbering guard: clean (no DRAFT / number:null, no duplicate numbers).');
}

// --backfill: stamp `number:` from the TYPE-000N filename prefix. No rename, no
// fetch. Idempotent: a doc already carrying the correct number is byte-untouched.
function runBackfill(root, opts) {
  const targets = opts.path ? [opts.path] : findNumberedDocs(root);
  let stamped = 0;
  for (const rel of targets) {
    const abs = path.join(root, rel);
    if (!fs.existsSync(abs)) die(2, `--backfill: path not found: ${rel}`);
    const base = path.basename(rel);
    const n = numberFromBasename(base);
    if (n == null) {
      if (opts.path) die(2, `--backfill: ${rel} has no TYPE-000N filename number to stamp`);
      continue;
    }
    const content = fs.readFileSync(abs, 'utf8');
    const fm = parseFrontmatter(content);
    if (numberFromFrontmatter(fm) === n) continue; // already correct — untouched
    const updated = stampNumber(content, n);
    if (updated == null) {
      if (opts.path) die(4, `--backfill: ${rel} has malformed frontmatter (cannot stamp)`);
      continue;
    }
    if (!opts.dryRun) fs.writeFileSync(abs, updated);
    stamped += 1;
    console.log(`backfill: ${rel} -> number: ${n}${opts.dryRun ? ' (dry-run)' : ''}`);
  }
  console.log(`backfill complete: ${stamped} doc(s) stamped.`);
}

function findNumberedDocs(root) {
  const out = [];
  for (const dir of GOVERNED_DIRS) {
    const abs = path.join(root, 'docs', dir);
    if (!fs.existsSync(abs)) continue;
    for (const f of fs.readdirSync(abs)) {
      if (f.endsWith('.md') && !isDraftBasename(f) && numberFromBasename(f) != null) {
        out.push(`docs/${dir}/${f}`);
      }
    }
  }
  return out;
}

// Normal allocation: number the selected DRAFT(s) from the base ref.
function runAllocate(root, opts) {
  // Selection (SPEC-0015 D3): the explicit --path, else (--all) every
  // docs/*/*-DRAFT-*.md. Neither given is a usage error — a path-less call must
  // opt into the blanket rename with --all (so it can never silently sweep in
  // out-of-scope drafts left behind by an inline run).
  let drafts;
  if (opts.path) {
    const base = path.basename(opts.path);
    if (!isDraftBasename(base)) die(2, `--path is not a DRAFT doc (needs <TYPE>-DRAFT-<slug>.md): ${opts.path}`);
    if (!fs.existsSync(path.join(root, opts.path))) die(2, `--path not found: ${opts.path}`);
    drafts = [opts.path];
  } else if (opts.all) {
    drafts = findAllDrafts(root);
    if (drafts.length === 0) {
      console.log('allocate: no DRAFT docs present — nothing to do.');
      return; // clean no-op (exit 0)
    }
  } else {
    die(2, 'nothing selected: specify --path <draft> or --all (SPEC-0015 D3). No writes.');
  }

  // Resolve the base ref (best-effort fetch + rev-parse). Unreachable -> exit 3,
  // leaving every DRAFT byte-identical (degrade-and-report).
  const baseSha = resolveBaseRef(root, opts.baseRef);
  if (!baseSha) {
    die(3, `WARNING: base ref "${opts.baseRef}" is unreachable (offline / fetch failed). No draft numbered; files left byte-identical. The no-DRAFT-at-merge guard remains the backstop.`);
  }

  // Validate + plan every draft BEFORE writing anything (no partial rename).
  const plan = [];
  const claimed = new Map(); // prefix -> next running number within this batch
  const widths = new Map();  // prefix -> derived display width (stable within the batch)
  let projWidth;             // lazily-computed project-dominant width (once per batch)
  for (const rel of drafts) {
    const abs = path.join(root, rel);
    const content = fs.readFileSync(abs, 'utf8');
    const fm = parseFrontmatter(content);
    const slug = fm && fm.id ? String(fm.id).trim() : '';
    if (!slug) die(4, `GUARD FAIL: ${rel} has malformed frontmatter (no slug id). No rename performed.`);
    const base = path.basename(rel, '.md');
    const prefix = prefixFromBasename(base);
    if (!prefix) die(4, `GUARD FAIL: ${rel} filename carries no TYPE prefix. No rename performed.`);
    const dir = path.basename(path.dirname(rel));
    // union: base-ref numbers ∪ local numbers ∪ numbers already claimed in this batch
    const baseMap = baseRefNumbers(root, baseSha, dir, prefix);
    const localMap = localNumbers(root, dir, prefix);
    const nums = new Set([...baseMap.keys(), ...localMap.keys()]);
    // Width follows the type's existing convention (ISSUE per-type-digit-width):
    // inherit from the highest-numbered existing doc, else the project's
    // dominant width (ISSUE project-dominant-width), else per-type defaults.
    if (projWidth === undefined) projWidth = projectDominantWidth(root, baseSha);
    const width = widths.get(prefix) ?? deriveWidth(prefix, baseMap, localMap, projWidth);
    widths.set(prefix, width);
    const start = claimed.get(prefix) ?? nextNumber(nums);
    const n = Math.max(start, nextNumber(nums));
    claimed.set(prefix, n + 1);
    // collision guard: the computed target must not already exist on the base ref.
    if (baseMap.has(n)) {
      die(4, `GUARD FAIL: computed ${displayId(prefix, n, width)} already exists on ${opts.baseRef}. No rename performed.`);
    }
    const newBase = `${displayId(prefix, n, width)}-${slug}`;
    plan.push({ rel, dir, prefix, slug, n, oldBase: base, newBase, newRel: `docs/${dir}/${newBase}.md` });
  }

  if (opts.dryRun) {
    for (const p of plan) console.log(`${p.rel} -> ${p.newRel} (number ${p.n})`);
    console.log(`dry-run: ${plan.length} draft(s) would be numbered.`);
    return;
  }

  for (const p of plan) {
    const abs = path.join(root, p.rel);
    const content = fs.readFileSync(abs, 'utf8');
    const stamped = stampNumber(content, p.n);
    if (stamped == null) die(4, `GUARD FAIL: ${p.rel} frontmatter could not be stamped. No further writes.`);
    fs.writeFileSync(abs, stamped);
    moveFile(root, p.rel, p.newRel);
    rewriteReferences(root, p.oldBase, p.newBase);
    console.log(`allocated ${p.rel} -> ${p.newRel} (number ${p.n}, id ${p.slug})`);
  }
  regenerateIndex(root);
  console.log(`allocate complete: ${plan.length} draft(s) numbered; docs/INDEX.md regenerated.`);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log('Usage: allocate-doc-number.mjs [--path <draft>] [--type <t>] [--base-ref <ref>] [--all] [--backfill] [--dry-run] [--guard]');
    process.exit(0);
  }
  if (opts._badFlag) die(2, `unknown flag "${opts._badFlag}"`);
  if (opts._extra && opts._extra.length) {
    die(2, `unexpected positional argument(s): ${opts._extra.join(' ')}\n` +
      'Usage: allocate-doc-number.mjs [--path <draft>] [--type <t>] [--base-ref <ref>] [--all] [--backfill] [--dry-run] [--guard]');
  }
  if (opts.type != null) { try { resolveType(opts.type); } catch (e) { die(2, e.message); } }
  const root = process.cwd();
  if (opts.guard) return runGuard(root);
  if (opts.backfill) return runBackfill(root, opts);
  return runAllocate(root, opts);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
