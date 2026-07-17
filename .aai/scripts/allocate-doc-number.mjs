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
// CHANGE-0035 / SPEC-0047 — atomic doc-number RESERVATION in origin. Before
// the local rename, the allocator creates a create-only ref
// `refs/aai/docnums/<TYPE>-<NNNN>` in `origin` (D2:
// `git push --atomic --force-with-lease=<ref>: origin HEAD:<ref>`) so two
// clones racing on the same number cannot both win: the loser's push is
// rejected and it retries the next free number (cap 50). Candidate scan is a
// union of local + base ref + ALL fetched `origin/*` trees + existing
// reservation refs (D3), so a number taken on an unmerged origin branch, or
// held only by a naked reservation ref, is never re-granted. When the
// reservation push fails for a NON-collision reason (offline, no push
// permission), allocation still proceeds but stamps `number_reserved: false`
// (D4) and prints a WARNING — never a silent collision; complete later with
// `--reserve --path <numbered-doc>`. `--guard` gained two predicates (D5):
// cross-branch collision (same TYPE-NNNN on the base ref under a different
// slug id) and the unreserved marker. `coupled_families` (docs/ai/docs-audit.
// yaml, D7, parsed by lib/guard-config.mjs) lets doc families share one
// counter; allocating for one member reserves ALL members' refs in one
// atomic push.
//
// Usage:
//   node .aai/scripts/allocate-doc-number.mjs [--path <draft-file>] [--type <t>]
//        [--base-ref <ref>] [--all] [--backfill] [--dry-run] [--guard] [--reserve]
//   Default --base-ref is origin/main.
//
// Exit codes (SPEC-0015 D3, unchanged by CHANGE-0035 D8):
//   0  success (drafts numbered, backfilled, guard clean, --reserve completed,
//      or nothing to do); a provisional (D4) allocation is STILL exit 0.
//   2  usage error (unknown flag / unknown --type / --path not a DRAFT doc). No writes.
//   3  base ref unreachable (offline / fetch failed): degrade-and-report, DRAFT byte-identical.
//   4  guard failure: computed number collides on the base ref, malformed DRAFT
//      frontmatter (no slug id), a --guard predicate found a violation, the
//      reservation retry cap (50) was hit, or a --reserve completion found the
//      ref already taken (potential collision).

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { parseFrontmatter } from './lib/docs-model.mjs';
import { readCoupledFamilies, coupledGroupFor } from './lib/guard-config.mjs';

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

// --- reservation (CHANGE-0035 / SPEC-0047) ------------------------------------

// D1: one ref per reserved number. Content is irrelevant; ref EXISTENCE is
// the semaphore.
export function reservationRef(displayIdStr) {
  return `refs/aai/docnums/${displayIdStr}`;
}

// Parse "refs/aai/docnums/<PREFIX>-<NUM>" -> { prefix, num } or null.
function parseReservationRef(refName) {
  const m = String(refName ?? '').match(/^refs\/aai\/docnums\/([A-Z]+(?:-[A-Z]+)*)-(\d{1,5})$/);
  if (!m) return null;
  return { prefix: m[1], num: parseInt(m[2], 10) };
}

function hasOrigin(root) {
  const remotes = git(root, ['remote']);
  return !!(remotes && remotes.split('\n').includes('origin'));
}

// Numbers for `prefix`, scanned across ALL governed dirs (coupled-family
// members may not share the drafted doc's own directory) — local tree ∪ base
// ref tree.
function numbersForPrefixAllDirs(root, baseSha, prefix) {
  const nums = new Set();
  for (const dir of GOVERNED_DIRS) {
    for (const n of baseRefNumbers(root, baseSha, dir, prefix).keys()) nums.add(n);
    for (const n of localNumbers(root, dir, prefix).keys()) nums.add(n);
  }
  return nums;
}

// D3(b): numbers taken on ALL fetched `origin/*` branch trees, for `prefix`
// (any governed dir). Caller is responsible for a prior best-effort
// `git fetch origin` (done once per runAllocate/runGuard call, not per draft).
function originBranchNumbersAllDirs(root, prefix) {
  const nums = new Set();
  const refs = git(root, ['for-each-ref', '--format=%(refname)', 'refs/remotes/origin']);
  if (!refs) return nums;
  for (const ref of refs.split('\n')) {
    if (!ref) continue;
    for (const dir of GOVERNED_DIRS) {
      const listing = git(root, ['ls-tree', '-r', '--name-only', ref, '--', `docs/${dir}`]);
      if (!listing) continue;
      for (const line of listing.split('\n')) {
        const base = path.basename(line);
        if (prefixFromBasename(base) === prefix) {
          const n = numberFromBasename(base);
          if (n != null) nums.add(n);
        }
      }
    }
  }
  return nums;
}

// D3(c): numbers claimed by reservation refs in `remote`, for `prefix`. A
// live `git ls-remote` call (no prior fetch needed). On failure, when an
// `origin` remote IS configured, this is a genuine degrade: fall back to any
// locally-known `refs/aai/docnums/*` and report (never silent). No `origin`
// configured at all is the ordinary D9 back-compat path — no warning.
function reservationRefNumbers(root, remote, prefix) {
  const nums = new Set();
  const out = git(root, ['ls-remote', remote, `refs/aai/docnums/${prefix}-*`]);
  if (out != null) {
    if (out !== '') {
      for (const line of out.split('\n')) {
        const refName = line.split(/\s+/)[1];
        const parsed = refName && parseReservationRef(refName);
        if (parsed && parsed.prefix === prefix) nums.add(parsed.num);
      }
    }
    return nums;
  }
  if (hasOrigin(root)) {
    console.error(`WARNING: git ls-remote ${remote} unreachable — degrading refs/aai/docnums/${prefix}-* scan to locally-known refs (D3c)`);
    const local = git(root, ['for-each-ref', '--format=%(refname)', 'refs/aai/docnums']);
    if (local) {
      for (const line of local.split('\n')) {
        const parsed = parseReservationRef(line);
        if (parsed && parsed.prefix === prefix) nums.add(parsed.num);
      }
    }
  }
  return nums;
}

// Git's well-known empty-tree object — valid in every repository without
// needing to be written first (`git commit-tree <empty-tree> -m ...` always
// succeeds, even in a brand-new repo with zero commits).
const EMPTY_TREE_SHA = '4b825dc642cb6eb9a060e54bf8d69288fbee4904';

// F1 remediation (post-implementation validation defect): a ref pointing at
// the SAME sha as the pusher's HEAD is the COMMON case (two clones sharing
// an unmodified base commit), and it makes
// `--force-with-lease=<ref>:<expect-absent>` a silent "Everything
// up-to-date" no-op — git only evaluates the lease when the push would
// actually MOVE the ref. Pushing a per-attempt, globally-unique dangling
// commit (empty tree + a random nonce message) instead of HEAD guarantees
// the pushed object can never coincide with whatever a peer already pushed,
// so ANY pre-existing ref is a genuine update the lease evaluates and (when
// the ref truly pre-exists) rejects. Ref CONTENT is irrelevant (D1: ref
// EXISTENCE is the semaphore) — only the sha's uniqueness matters. Returns
// null on failure (extremely unlikely: commit-tree has no network I/O).
function createReservationCommit(root) {
  const nonce = `${process.pid}-${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
  try {
    return execFileSync('git', ['commit-tree', EMPTY_TREE_SHA, '-m', `aai-docnum-reservation ${nonce}`],
      { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch {
    return null;
  }
}

// D2: one create-only atomic push of `refNames` (>1 for a coupled family).
// `--force-with-lease=<ref>:` (empty expected value) requires each ref be
// ABSENT; `--atomic` makes the set all-or-nothing. Returns { ok: true } on
// success, { ok:false, collision:true } on a create-only rejection (retry-
// worthy), or { ok:false, collision:false, error } for any other failure
// (D4 provisional-fallback territory).
function pushReservation(root, remote, refNames) {
  const sha = createReservationCommit(root);
  if (!sha) {
    return { ok: false, collision: false, error: 'failed to create a reservation commit object (git commit-tree)' };
  }
  const leases = refNames.map((r) => `--force-with-lease=${r}:`);
  const refspecs = refNames.map((r) => `${sha}:${r}`);
  try {
    execFileSync('git', ['push', '--atomic', ...leases, remote, ...refspecs],
      { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return { ok: true };
  } catch (e) {
    const out = `${e.stdout ?? ''}${e.stderr ?? ''}`.trim();
    // F2 remediation: the ONLY retry-worthy signal is the create-only lease
    // rejection itself ("stale info" — git's message when a
    // `--force-with-lease=<ref>:<expect-absent>` finds the ref already
    // present). Everything else (unpacker error, permission denied, hook
    // rejection, offline) is a non-collision failure and must fall through
    // to the D4 provisional-marker path — never a 50-attempt retry storm.
    // (Matching bare "rejected" was over-broad: `! [remote rejected] ...
    // (unpacker error)` on a permission failure also contains "rejected".)
    const collision = /stale info/i.test(out);
    return { ok: false, collision, error: out || e.message };
  }
}

// D2/D8: attempt to reserve `startNumber` for every member (a singleton for
// the uncoupled case, D7's full group otherwise), retrying the NEXT number on
// a create-only rejection up to `capAttempts` (default 50). Exported for
// direct unit testing of the atomic/retry primitive (TEST-002, TEST-010) and
// used internally by runAllocate/runReserveCompletion.
export function reserveAtomic(root, remote, members, startNumber, capAttempts = 50) {
  let n = startNumber;
  for (let attempt = 0; attempt < capAttempts; attempt += 1) {
    const refNames = members.map((m) => reservationRef(displayId(m.prefix, n, m.width)));
    const res = pushReservation(root, remote, refNames);
    if (res.ok) return { ok: true, number: n, refNames };
    if (!res.collision) return { ok: false, collision: false, number: n, refNames, error: res.error };
    n += 1;
  }
  return { ok: false, exhausted: true, number: n };
}

// D4: stamp `number_reserved: false` (provisional marker), inserted right
// after `number:` when present (it always is by the time GREEN calls this —
// stampNumber runs first), else after `id:`. EOL-agnostic, same discipline
// as stampNumber.
export function stampProvisionalMarker(content) {
  const open = content.match(/^---(\r?\n)/);
  if (!open) return null;
  const eol = open[1];
  const fmEnd = content.indexOf(`${eol}---`, open[0].length);
  if (fmEnd < 0) return null;
  const head = content.slice(0, fmEnd);
  const rest = content.slice(fmEnd);
  if (/(\r?\n)[ \t]*number_reserved:[^\r\n]*/.test(head)) {
    return head.replace(/((\r?\n)[ \t]*number_reserved:)[^\r\n]*/, `$1 false`) + rest;
  }
  if (/(\r?\n)[ \t]*number:[^\r\n]*/.test(head)) {
    return head.replace(/(\r?\n[ \t]*number:[^\r\n]*)/, `$1${eol}number_reserved: false`) + rest;
  }
  if (/(\r?\n)[ \t]*id:[^\r\n]*/.test(head)) {
    return head.replace(/(\r?\n[ \t]*id:[^\r\n]*)/, `$1${eol}number_reserved: false`) + rest;
  }
  return null;
}

// D4 completion: remove the `number_reserved:` line entirely (confirmed).
export function removeProvisionalMarker(content) {
  const open = content.match(/^---(\r?\n)/);
  if (!open) return null;
  const eol = open[1];
  const fmEnd = content.indexOf(`${eol}---`, open[0].length);
  if (fmEnd < 0) return null;
  const head = content.slice(0, fmEnd);
  const rest = content.slice(fmEnd);
  const lineRe = new RegExp(`${eol}[ \\t]*number_reserved:[^\r\n]*`);
  if (!lineRe.test(head)) return null;
  return head.replace(lineRe, '') + rest;
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
  const opts = { path: null, type: null, baseRef: 'origin/main', all: false, backfill: false, dryRun: false, guard: false, reserve: false };
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
      case '--reserve': opts.reserve = true; break;
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

// Governed docs on `baseSha` for prefix/dir -> Map<num, id> (frontmatter id,
// else the filename stem). Used by the D5(a) cross-branch collision predicate.
function baseRefDocIds(root, baseSha, dir, prefix) {
  const ids = new Map();
  const listing = git(root, ['ls-tree', '-r', '--name-only', baseSha, '--', `docs/${dir}`]);
  if (!listing) return ids;
  for (const line of listing.split('\n')) {
    if (!line) continue;
    const base = path.basename(line);
    if (prefixFromBasename(base) !== prefix) continue;
    const num = numberFromBasename(base);
    if (num == null) continue;
    const content = git(root, ['show', `${baseSha}:${line}`]);
    if (content == null) continue;
    const fm = parseFrontmatter(content);
    ids.set(num, fm?.id ?? path.basename(base, '.md'));
  }
  return ids;
}

// --guard: scan the working (STAGED) tree for (a) any DRAFT / number:null
// governed doc, (b) two governed docs of the same prefix resolving to the
// same TYPE-000N, (c) CHANGE-0035 D5(a) — a staged doc's TYPE-000N already
// exists on the base ref under a DIFFERENT slug id (cross-branch collision),
// and (d) D5(b) — any governed doc carrying `number_reserved: false`
// (unreserved marker). `--base-ref` (previously ignored in guard mode) now
// gates predicate (c); an unreachable base ref degrades to skipping ONLY
// that predicate, with a WARNING (D5 degrade-and-report) — (a)/(b)/(d) are
// unaffected.
function runGuard(root, opts) {
  const drafts = [];
  const byDisplay = new Map(); // "PREFIX-000N" -> [{rel, id}]
  const stagedDocs = [];       // {rel, dir, prefix, num, id}
  const markerHits = [];       // rel[] carrying number_reserved: false
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
    const id = fm?.id ?? path.basename(f, '.md');
    if (prefix && num != null) {
      const key = displayId(prefix, num);
      if (!byDisplay.has(key)) byDisplay.set(key, []);
      byDisplay.get(key).push({ rel, id });
      stagedDocs.push({ rel, dir: path.basename(path.dirname(rel)), prefix, num, id });
    }
    // D5(b) unreserved-marker predicate
    if (fm && String(fm.number_reserved) === 'false') markerHits.push(rel);
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

  // D5(a) cross-branch collision
  const baseRef = opts?.baseRef ?? 'origin/main';
  const baseSha = resolveBaseRef(root, baseRef);
  if (baseSha) {
    const idsCache = new Map(); // "dir/prefix" -> Map<num,id>
    for (const doc of stagedDocs) {
      const cacheKey = `${doc.dir}/${doc.prefix}`;
      if (!idsCache.has(cacheKey)) idsCache.set(cacheKey, baseRefDocIds(root, baseSha, doc.dir, doc.prefix));
      const baseId = idsCache.get(cacheKey).get(doc.num);
      if (baseId != null && baseId !== doc.id) {
        violations += 1;
        console.error(`GUARD FAIL (cross-branch collision): ${displayId(doc.prefix, doc.num)} is staged as id "${doc.id}" (${doc.rel}) but already exists on ${baseRef} under a different id "${baseId}"`);
      }
    }
  } else {
    console.error(`WARNING: guard base ref "${baseRef}" is unreachable — skipping the cross-branch collision predicate (D5 degrade-and-report; other predicates unaffected)`);
  }

  // D5(b) unreserved marker
  if (markerHits.length > 0) {
    violations += markerHits.length;
    console.error('GUARD FAIL (unreserved marker): doc(s) carry number_reserved: false — complete the reservation before merge:');
    for (const rel of markerHits) console.error(`  - ${rel} — run node .aai/scripts/allocate-doc-number.mjs --reserve --path ${rel}`);
  }

  if (violations > 0) die(4, `Doc-numbering guard found ${violations} violation(s).`);
  console.log('Doc-numbering guard: clean (no DRAFT / number:null, no duplicate numbers, no cross-branch collision, no unreserved marker).');
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

  // CHANGE-0035 D3(b): widen the fetch once per batch (not per draft) so
  // refs/remotes/origin/* trees are current for the union scan below.
  // Best-effort — a failure here just leaves origin/* scanning at whatever
  // was already locally known (degrade-and-report happens per-prefix below).
  git(root, ['fetch', 'origin']);
  const coupledGroups = readCoupledFamilies(path.join(root, 'docs/ai'));

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
    // CHANGE-0035 D3(b)/(c)/D7: fold in origin/* branch trees, existing
    // reservation refs, and any coupled-family peers' taken numbers (union
    // over every group member — D7; a singleton [prefix] when uncoupled).
    const group = coupledGroupFor(coupledGroups, prefix);
    for (const member of group) {
      for (const n of numbersForPrefixAllDirs(root, baseSha, member)) nums.add(n);
      for (const n of originBranchNumbersAllDirs(root, member)) nums.add(n);
      for (const n of reservationRefNumbers(root, 'origin', member)) nums.add(n);
    }
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
    plan.push({ rel, dir, prefix, slug, n, width, oldBase: base, newBase, newRel: `docs/${dir}/${newBase}.md` });
  }

  if (opts.dryRun) {
    for (const p of plan) console.log(`${p.rel} -> ${p.newRel} (number ${p.n})`);
    console.log(`dry-run: ${plan.length} draft(s) would be numbered.`);
    return;
  }

  for (const p of plan) {
    // CHANGE-0035 D2: reserve BEFORE rename. Per-draft, sequential (a batch's
    // drafts each get their own atomic push — never one push across drafts).
    const group = coupledGroupFor(coupledGroups, p.prefix);
    const members = group.map((pfx) => ({ prefix: pfx, width: p.width }));
    const reserved = reserveAtomic(root, 'origin', members, p.n, 50);
    let provisional = false;
    if (reserved.ok) {
      if (reserved.number !== p.n) {
        // Retried past the plan's candidate — recompute the display id.
        p.n = reserved.number;
        p.newBase = `${displayId(p.prefix, p.n, p.width)}-${p.slug}`;
        p.newRel = `docs/${p.dir}/${p.newBase}.md`;
      }
    } else if (reserved.exhausted) {
      die(4, `GUARD FAIL: could not reserve a doc number for ${p.rel} after 50 attempts (refs/aai/docnums/${p.prefix}-* exhausted). No further writes.`);
    } else {
      // D4: non-collision push failure (offline, no permission, no origin
      // configured) -> provisional fallback. Fail-open with a visible tax,
      // never a silent collision.
      provisional = true;
      console.error(`WARNING: reservation push failed for ${displayId(p.prefix, p.n, p.width)} (${reserved.error || 'origin unreachable'}) — allocating provisionally with number_reserved: false. Complete later: node .aai/scripts/allocate-doc-number.mjs --reserve --path ${p.newRel}`);
    }
    const abs = path.join(root, p.rel);
    const content = fs.readFileSync(abs, 'utf8');
    let stamped = stampNumber(content, p.n);
    if (stamped == null) die(4, `GUARD FAIL: ${p.rel} frontmatter could not be stamped. No further writes.`);
    if (provisional) {
      stamped = stampProvisionalMarker(stamped);
      if (stamped == null) die(4, `GUARD FAIL: ${p.rel} frontmatter could not be marked provisional. No further writes.`);
    }
    fs.writeFileSync(abs, stamped);
    moveFile(root, p.rel, p.newRel);
    rewriteReferences(root, p.oldBase, p.newBase);
    console.log(`allocated ${p.rel} -> ${p.newRel} (number ${p.n}, id ${p.slug}${provisional ? ', number_reserved: false' : ''})`);
  }
  regenerateIndex(root);
  console.log(`allocate complete: ${plan.length} draft(s) numbered; docs/INDEX.md regenerated.`);
}

// --reserve: complete a provisional (D4) reservation for an already-numbered
// doc. Re-attempts the SAME create-only push (no retry — the number is
// already committed to the filename/frontmatter); success removes the
// marker, an already-taken ref exits 4 naming the potential collision
// (operator renumbers via re-allocation), any other failure leaves the doc
// provisional with a WARNING (still exit 0 — never silent, never a false
// success).
function runReserveCompletion(root, opts) {
  if (!opts.path) die(2, '--reserve requires --path <numbered-doc>');
  const rel = opts.path;
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) die(2, `--reserve: path not found: ${rel}`);
  const content = fs.readFileSync(abs, 'utf8');
  const fm = parseFrontmatter(content);
  if (!fm || String(fm.number_reserved) !== 'false') {
    die(2, `--reserve: ${rel} carries no number_reserved: false marker to complete`);
  }
  const base = path.basename(rel, '.md');
  const prefix = prefixFromBasename(base);
  const num = numberFromFrontmatter(fm) ?? numberFromBasename(base);
  if (!prefix || num == null) die(4, `--reserve: ${rel} carries no resolvable TYPE-NNNN (malformed). No writes.`);
  const width = numberWidthFromBasename(base) ?? 4;
  const coupledGroups = readCoupledFamilies(path.join(root, 'docs/ai'));
  const group = coupledGroupFor(coupledGroups, prefix);
  const members = group.map((pfx) => ({ prefix: pfx, width }));
  const refNames = members.map((m) => reservationRef(displayId(m.prefix, num, m.width)));
  const res = pushReservation(root, 'origin', refNames);
  if (res.ok) {
    const updated = removeProvisionalMarker(content);
    if (updated == null) die(4, `--reserve: ${rel} frontmatter could not be updated. No writes.`);
    fs.writeFileSync(abs, updated);
    console.log(`reserve complete: ${rel} -> number_reserved marker removed (${refNames.join(', ')})`);
    return;
  }
  if (res.collision) {
    die(4, `--reserve: ${refNames.join(', ')} already exists — potential collision for ${rel} (${displayId(prefix, num, width)}). Re-run allocation to renumber (operator decision).`);
  }
  console.error(`WARNING: --reserve: push still failing for a non-collision reason (${res.error || 'origin unreachable'}) — ${rel} remains provisional (number_reserved: false).`);
}

const USAGE = 'Usage: allocate-doc-number.mjs [--path <draft>] [--type <t>] [--base-ref <ref>] [--all] [--backfill] [--dry-run] [--guard] [--reserve]';

function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    console.log(USAGE);
    process.exit(0);
  }
  if (opts._badFlag) die(2, `unknown flag "${opts._badFlag}"`);
  if (opts._extra && opts._extra.length) {
    die(2, `unexpected positional argument(s): ${opts._extra.join(' ')}\n${USAGE}`);
  }
  if (opts.type != null) { try { resolveType(opts.type); } catch (e) { die(2, e.message); } }
  const root = process.cwd();
  if (opts.guard) return runGuard(root, opts);
  if (opts.reserve) return runReserveCompletion(root, opts);
  if (opts.backfill) return runBackfill(root, opts);
  return runAllocate(root, opts);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
