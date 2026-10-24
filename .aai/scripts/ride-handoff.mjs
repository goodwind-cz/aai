#!/usr/bin/env node
// ride-handoff.mjs — carry exactly ONE ride's STATE from the origin checkout
// into its worktree (`out`), and clean a stale origin STATE after the merge
// (`reconcile`). Spec: spec-ride-state-handoff-to-worktree.
//
//   node .aai/scripts/ride-handoff.mjs out --ref <R> --worktree <abs path>
//        [--state <origin STATE path>] [--base-ref <ref>] [--dry-run]
//   node .aai/scripts/ride-handoff.mjs reconcile --ref <R>
//        [--state <origin STATE path>] [--metrics <METRICS.jsonl path>]
//        [--branch <ride branch>] [--dry-run]
//
// The ride-bound content of R (the partition) is: current_focus (when R),
// R's active work item, R's metrics.work_items entry, implementation_strategy /
// code_review / last_validation / tdd_cycle when they name R, and the
// recommendation + rationale of the worktree block when R is the focus.
// Everything else is foreign and is never copied, edited or reordered.
//
// STATE is written through lib/state-engine.mjs (atomic tmp+rename with the
// pre-rename content recheck), never re-serialised: block lines are spliced.
// Exit: 0 done / resumed / no-op, 1 refusal (`REFUSE <reason> <detail>` on
// stdout, nothing written), 2 usage, 3 the single-writer refusal.
// Node stdlib only (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { duplicateKeys, inlineChildConflicts } from './lib/state-core.mjs';
import { putStickyRaise, readBindingBlock, readStickyRecords } from './lib/check-binding.mjs';
import {
  bumpUpdatedAt, editBlock, ensureBlock, fieldRe, fieldSpan, findBlock, loadState, metricsEntrySpan,
  readScalar, scalarLine, setEngineFailPrefix, setField, unquoteScalar, writeState, yq,
} from './lib/state-engine.mjs';

setEngineFailPrefix('ride-handoff');

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATE_PATH = path.join(SCRIPT_DIR, '..', 'templates', 'STATE_TEMPLATE.yaml');
const STATE_REL = 'docs/ai/STATE.yaml';
const ARCHIVE_REL = 'docs/ai/archive/handoffs';

const HELP = `ride-handoff.mjs out --ref <R> --worktree <abs path> [--state <path>] [--base-ref <ref>] [--dry-run]
ride-handoff.mjs reconcile --ref <R> [--state <path>] [--metrics <path>] [--branch <name>] [--dry-run]
`;

function usage(msg) {
  process.stderr.write(`ride-handoff: ${msg}\n${HELP}`);
  exit(2);
}

function refuse(reason, detail = '') {
  process.stdout.write(`REFUSE ${reason}${detail ? ` ${detail}` : ''}\n`);
  exit(1);
}

function say(line) {
  process.stdout.write(`${line}\n`);
}

function parseArgs(argv) {
  const sub = argv[0];
  if (!['out', 'reconcile'].includes(sub)) usage(`unknown or missing subcommand: ${sub ?? '(none)'}`);
  const valueFlags = sub === 'out'
    ? ['ref', 'worktree', 'state', 'base-ref']
    : ['ref', 'state', 'metrics', 'branch'];
  const f = { sub };
  for (let i = 1; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--dry-run') { f.dryRun = true; continue; }
    const name = a.startsWith('--') ? a.slice(2) : null;
    if (name && valueFlags.includes(name)) {
      if (i + 1 >= argv.length) usage(`${a} requires a value`);
      f[name] = argv[i += 1];
      continue;
    }
    usage(`unknown argument: ${a}`);
  }
  if (!f.ref) usage('--ref is required');
  if (sub === 'out') {
    if (!f.worktree) usage('--worktree is required');
    if (!path.isAbsolute(f.worktree)) usage('--worktree must be an absolute path');
  }
  return f;
}

// --- single-writer guard (same two arms as state.mjs; state.mjs is not edited) ---

function realpathDirTarget(resolved) {
  try {
    return path.join(fs.realpathSync(path.dirname(resolved)), path.basename(resolved));
  } catch {
    return resolved;
  }
}

function isShippingState(statePath) {
  const resolved = realpathDirTarget(path.resolve(statePath));
  const ownRoot = fs.realpathSync(path.resolve(SCRIPT_DIR, '..', '..'));
  const rel = path.relative(ownRoot, resolved);
  if (rel === '' || (!rel.startsWith(`..${path.sep}`) && rel !== '..' && !path.isAbsolute(rel))) return true;
  const segs = resolved.split(path.sep);
  if (segs.length >= 3 && segs.slice(-3).join('/') === STATE_REL) {
    const otherRoot = path.dirname(path.dirname(path.dirname(resolved)));
    if (otherRoot !== ownRoot && fs.existsSync(path.join(otherRoot, '.aai', 'scripts', 'state.mjs'))) return true;
  }
  return false;
}

function guardSingleWriter(...statePaths) {
  if (process.env.AAI_ROLE !== 'subagent') return;
  for (const p of statePaths) {
    if (isShippingState(p)) {
      process.stderr.write('ride-handoff: single-writer rule refusal (AAI_ROLE=subagent): the orchestrator is the SOLE '
        + `writer of docs/ai/STATE.yaml (.aai/SUBAGENT_CONTRACT.md) and "${p}" resolves to a SHIPPING STATE. `
        + 'Return a result block instead. Nothing was written.\n');
      exit(3);
    }
  }
}

// --- small line helpers -----------------------------------------------------------

const unq = (v) => (v === null || v === undefined ? null : unquoteScalar(String(v).trim()));
const scalarOf = (lines, block, field) => unq(readScalar(lines, block, field));

function blockOf(lines, key) {
  const b = findBlock(lines, key);
  return b ? lines.slice(b.start, b.end) : null;
}

// Trailing blank and column-0 comment lines belong to the gap before the next
// key, not to the block's content.
function contentOf(block) {
  let n = block.length;
  while (n > 1 && (block[n - 1].trim() === '' || block[n - 1].startsWith('#'))) n -= 1;
  return block.slice(0, n);
}

function replaceBlock(lines, key, newBlock) {
  const b = findBlock(lines, key);
  if (b) {
    const old = lines.slice(b.start, b.end);
    const gap = old.slice(contentOf(old).length);
    lines.splice(b.start, b.end - b.start, ...contentOf(newBlock), ...gap);
    return;
  }
  let at = lines.length;
  for (let i = 0; i < lines.length; i += 1) if (/^updated_at_utc:/.test(lines[i])) { at = i; break; }
  lines.splice(at, 0, ...contentOf(newBlock), '');
}

function templateBlock(key) {
  if (!fs.existsSync(TEMPLATE_PATH)) usage(`STATE template missing: ${TEMPLATE_PATH}`);
  const tl = fs.readFileSync(TEMPLATE_PATH, 'utf8').replace(/\r\n/g, '\n').split('\n');
  const b = findBlock(tl, key);
  if (!b) usage(`STATE template has no ${key} block`);
  return contentOf(tl.slice(b.start, b.end));
}

const IDLE_TDD = [
  'tdd_cycle:', '  status: IDLE', '  test_id: null', '  spec_path: null', '  test_path: null',
  '  evidence:', '    red: null', '    green: null', '    refactor: null',
];

function fieldLines(block, name) {
  const idx = block.findIndex((l) => fieldRe(2, name).test(l));
  return idx < 0 ? null : block.slice(idx, idx + fieldSpan(block, idx, 2));
}

// --- active work items --------------------------------------------------------------

function parseItems(lines) {
  const b = findBlock(lines, 'active_work_items');
  const items = [];
  if (!b) return { b: null, items };
  let cur = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (/^ {2}- /.test(l)) {
      cur = { start: i, end: i + 1, ref: null };
      items.push(cur);
      const m = l.match(/^ {2}- ref_id:\s*(.*)$/);
      if (m) cur.ref = unq(m[1]);
    } else if (cur && /^ {3,}\S/.test(l)) {
      cur.end = i + 1;
      const m = l.match(/^ {4}ref_id:\s*(.*)$/);
      if (m && cur.ref === null) cur.ref = unq(m[1]);
    }
  }
  return { b, items };
}

function removeItem(lines, ref) {
  const { b, items } = parseItems(lines);
  const it = items.find((x) => x.ref === ref);
  if (!it) return;
  if (items.length === 1) {
    const old = lines.slice(b.start, b.end);
    lines.splice(b.start, b.end - b.start, 'active_work_items: []', ...old.slice(contentOf(old).length));
    return;
  }
  lines.splice(it.start, it.end - it.start);
}

function putItem(lines, ref, itemLines) {
  removeItem(lines, ref);
  const { b, items } = parseItems(lines);
  if (!b) {
    ensureBlock(lines, 'active_work_items', itemLines);
    return;
  }
  if (items.length === 0) {
    lines.splice(b.start, 1, 'active_work_items:', ...itemLines);
    return;
  }
  const last = items[items.length - 1];
  lines.splice(last.end, 0, ...itemLines);
}

// --- metrics entries ----------------------------------------------------------------

// The R entry span without its trailing blank lines, or null.
function entrySpan(lines, ref) {
  const s = metricsEntrySpan(lines, ref);
  if (!s) return null;
  let end = s.end;
  while (end > s.start + 1 && lines[end - 1].trim() === '') end -= 1;
  return { start: s.start, end };
}

function entryRuns(lines, ref) {
  const s = entrySpan(lines, ref);
  const runs = [];
  if (!s) return runs;
  let inRuns = false;
  let cur = null;
  const field = (item, text) => {
    const m = text.match(/^(role|started_utc):\s*(.*)$/);
    if (!m) return;
    const v = unq(m[2]);
    if (m[1] === 'role') item.role = v; else item.started = v;
  };
  for (let i = s.start + 1; i < s.end; i += 1) {
    const l = lines[i];
    if (/^ {6}\S/.test(l)) { inRuns = /^ {6}agent_runs:/.test(l); cur = null; continue; }
    if (!inRuns) continue;
    const it = l.match(/^ {8}- (.*)$/);
    if (it) { cur = { role: null, started: null }; runs.push(cur); field(cur, it[1]); continue; }
    if (/^ {8}-\s*$/.test(l)) { cur = { role: null, started: null }; runs.push(cur); continue; }
    const kv = l.match(/^ {10}(\S.*)$/);
    if (kv && cur) field(cur, kv[1]);
  }
  return runs;
}

function entryKeys(lines) {
  const b = findBlock(lines, 'metrics');
  const keys = [];
  if (!b) return keys;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const m = lines[i].match(/^ {4}([^\s#][^:]*):\s*$/);
    if (m) keys.push(unq(m[1]));
  }
  return keys;
}

function removeEntry(lines, ref) {
  const s = entrySpan(lines, ref);
  if (s) lines.splice(s.start, s.end - s.start);
}

function putEntry(lines, ref, entryLines) {
  const s = entrySpan(lines, ref);
  if (s) { lines.splice(s.start, s.end - s.start, ...entryLines); return; }
  ensureBlock(lines, 'metrics', ['  work_items:']);
  const b = findBlock(lines, 'metrics');
  let wi = -1;
  for (let i = b.start + 1; i < b.end; i += 1) if (/^ {2}work_items:/.test(lines[i])) { wi = i; break; }
  let last = b.end;
  while (last > b.start + 1 && lines[last - 1].trim() === '') last -= 1;
  if (wi === -1) {
    lines.splice(last, 0, '  work_items:', ...entryLines);
    return;
  }
  if (/^ {2}work_items:\s*(\{\}|\[\]|null|~)\s*$/.test(lines[wi])) lines[wi] = '  work_items:';
  lines.splice(last, 0, ...entryLines);
}

// --- the partition -------------------------------------------------------------------

function ridePartition(lines, ref) {
  const focusIsRide = scalarOf(lines, 'current_focus', 'ref_id') === ref;
  const item = parseItems(lines).items.find((x) => x.ref === ref) ?? null;
  const spanned = entrySpan(lines, ref);
  const rideSpec = focusIsRide ? scalarOf(lines, 'current_focus', 'spec_path') : (item ? unq((lines.slice(item.start, item.end).join('\n').match(/^ {4}spec_path:\s*(.*)$/m) ?? [])[1]) : null);
  const parts = {
    focusIsRide,
    focus: focusIsRide ? contentOf(blockOf(lines, 'current_focus')) : null,
    item: item ? lines.slice(item.start, item.end) : null,
    entry: spanned ? lines.slice(spanned.start, spanned.end) : null,
    strategy: scalarOf(lines, 'implementation_strategy', 'ref_id') === ref ? contentOf(blockOf(lines, 'implementation_strategy')) : null,
    codeReview: scalarOf(lines, 'code_review', 'scope_ref_id') === ref ? contentOf(blockOf(lines, 'code_review')) : null,
    lastValidation: scalarOf(lines, 'last_validation', 'ref_id') === ref ? contentOf(blockOf(lines, 'last_validation')) : null,
    tdd: null,
    rideSpec,
    worktreeRec: null,
    worktreeRationale: null,
  };
  const tdd = blockOf(lines, 'tdd_cycle');
  if (tdd && rideSpec && scalarOf(lines, 'tdd_cycle', 'spec_path') === rideSpec) parts.tdd = contentOf(tdd);
  const wtb = blockOf(lines, 'worktree');
  if (wtb && focusIsRide) {
    parts.worktreeRec = fieldLines(wtb, 'recommendation');
    parts.worktreeRationale = fieldLines(wtb, 'rationale');
  }
  return parts;
}

const hasTrace = (p) => Boolean(p.focus || p.item || p.entry || p.strategy || p.codeReview || p.lastValidation || p.tdd);

// Reset every ride-bound block of the origin STATE; `namesWorktree(block)` decides
// whether its worktree block belongs to this ride. Foreign lines are untouched.
function resetOrigin(lines, ref, parts, namesWorktree) {
  if (parts.focus) replaceBlock(lines, 'current_focus', templateBlock('current_focus'));
  removeItem(lines, ref);
  removeEntry(lines, ref);
  if (parts.strategy) replaceBlock(lines, 'implementation_strategy', templateBlock('implementation_strategy'));
  if (parts.codeReview) replaceBlock(lines, 'code_review', templateBlock('code_review'));
  if (parts.lastValidation) replaceBlock(lines, 'last_validation', templateBlock('last_validation'));
  if (parts.tdd) replaceBlock(lines, 'tdd_cycle', IDLE_TDD);
  const wtb = blockOf(lines, 'worktree');
  if (wtb && namesWorktree(wtb)) replaceBlock(lines, 'worktree', templateBlock('worktree'));
  bumpUpdatedAt(lines);
}

// --- archive --------------------------------------------------------------------------

function utcStamp() {
  return new Date().toISOString().replace(/\.\d+Z$/, 'Z').replace(/[-:]/g, '');
}

function newArchiveDir(originRoot, name) {
  const base = path.join(originRoot, ARCHIVE_REL);
  fs.mkdirSync(base, { recursive: true });
  let dir = path.join(base, name);
  for (let n = 2; fs.existsSync(dir); n += 1) dir = path.join(base, `${name}-${n}`);
  fs.mkdirSync(dir);
  return dir;
}

function writeJson(file, obj) {
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, `${JSON.stringify(obj, null, 2)}\n`);
  fs.renameSync(tmp, file);
}

const posix = (p) => p.split(path.sep).join('/');

function moveFile(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  try {
    fs.renameSync(src, dest);
  } catch (e) {
    if (e.code !== 'EXDEV') throw e;
    fs.copyFileSync(src, dest);
    fs.unlinkSync(src);
  }
}

// --- git -------------------------------------------------------------------------------

function git(cwd, args) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  return { status: r.status ?? 1, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

function realOr(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}

// --- out ---------------------------------------------------------------------------------

function safeRel(rel) {
  return typeof rel === 'string' && rel !== '' && !path.isAbsolute(rel) && !rel.split(/[\\/]/).includes('..');
}

function planDrafts(originRoot, wtRoot, ref, parts) {
  const rels = [];
  if (parts.focusIsRide) {
    const p = scalarOfPlan(parts, 'primary_path');
    if (p) rels.push(p);
  }
  if (parts.rideSpec) rels.push(parts.rideSpec);
  rels.push(`docs/ai/briefs/${ref}.md`);
  const plan = [];
  const conflicts = [];
  for (const rel of [...new Set(rels)]) {
    if (!safeRel(rel)) refuse('unsafe_draft_path', `${rel} (absolute or contains ..); nothing was written`);
    const src = path.join(originRoot, rel);
    if (!fs.existsSync(src) || !fs.statSync(src).isFile()) continue;
    const tracked = git(originRoot, ['ls-files', '--error-unmatch', '--', rel]).status === 0;
    const dst = path.join(wtRoot, rel);
    const exists = fs.existsSync(dst);
    if (!tracked && exists && !fs.readFileSync(src).equals(fs.readFileSync(dst))) conflicts.push(rel);
    plan.push({ rel, src, dst, tracked, copy: !exists });
  }
  return { plan, conflicts };
}

function scalarOfPlan(parts, field) {
  const m = (parts.focus ?? []).find((l) => fieldRe(2, field).test(l));
  return m ? unq(m.slice(m.indexOf(':') + 1)) : null;
}

function findStartedRecord(originRoot, ref, wtReal) {
  const base = path.join(originRoot, ARCHIVE_REL);
  if (!fs.existsSync(base)) return null;
  for (const name of fs.readdirSync(base).sort().reverse()) {
    const file = path.join(base, name, 'record.json');
    if (!fs.existsSync(file)) continue;
    let rec;
    try { rec = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { continue; }
    if (rec.ref === ref && rec.status === 'started' && rec.kind !== 'reconcile' && realOr(rec.worktree) === wtReal) {
      return { dir: path.join(base, name), file, rec };
    }
  }
  return null;
}

function checkFresh(wLines, ref, originEntry) {
  const focus = scalarOf(wLines, 'current_focus', 'ref_id');
  if (focus !== null && focus !== ref) return `focus names ${focus}`;
  for (const it of parseItems(wLines).items) if (it.ref !== ref) return `active work item ${it.ref}`;
  for (const key of entryKeys(wLines)) {
    const s = entrySpan(wLines, key);
    const text = wLines.slice(s.start, s.end).join('\n');
    if (key === ref) {
      if (originEntry && text === originEntry.join('\n')) continue;
      if (entryRuns(wLines, key).length === 0) continue;
      return `metrics entry ${key} differs from the origin's`;
    }
    return `foreign metrics entry ${key}`;
  }
  return null;
}

// The check_sticky entry of the ride is copied origin to worktree: the worktree STATE gets the
// origin's entry for the ref (flag and spec paths, through putStickyRaise). An origin record that
// does not parse, or a check_binding block of the ref with no record, is carried as flag raised.
// Nothing copies an entry from a worktree STATE back to the origin STATE.
function carrySticky(lines, originLines, ref) {
  const rec = readStickyRecords(originLines);
  const e = rec.entries.get(ref);
  const bind = readBindingBlock(originLines);
  const bindNamesRef = bind.present && (bind.problems.length > 0 || bind.refId === ref);
  if (rec.problems.length > 0 || (e === undefined && bindNamesRef)) putStickyRaise(lines, ref, { security: true });
  else if (e !== undefined) putStickyRaise(lines, ref, { security: e.security, specPaths: e.specPaths });
}

function buildWorktreeLines(wLines, ref, parts, info, originLines) {
  const lines = wLines.slice();
  if (parts.focus) replaceBlock(lines, 'current_focus', parts.focus);
  if (parts.item) putItem(lines, ref, parts.item);
  if (parts.entry) putEntry(lines, ref, parts.entry);
  if (parts.strategy) replaceBlock(lines, 'implementation_strategy', parts.strategy);
  if (parts.codeReview) replaceBlock(lines, 'code_review', parts.codeReview);
  if (parts.lastValidation) replaceBlock(lines, 'last_validation', parts.lastValidation);
  if (parts.tdd) replaceBlock(lines, 'tdd_cycle', parts.tdd);
  editBlock(lines, 'worktree', (bl) => {
    setField(bl, 2, 'user_decision', [scalarLine(2, 'user_decision', 'worktree')]);
    setField(bl, 2, 'base_ref', [scalarLine(2, 'base_ref', yq(info.baseRef))]);
    setField(bl, 2, 'branch', [scalarLine(2, 'branch', info.branch ? yq(info.branch) : 'null')]);
    setField(bl, 2, 'path', [scalarLine(2, 'path', yq(info.path))]);
    if (parts.worktreeRec) setField(bl, 2, 'recommendation', parts.worktreeRec);
    if (parts.worktreeRationale) setField(bl, 2, 'rationale', parts.worktreeRationale);
    return bl;
  });
  carrySticky(lines, originLines, ref);
  return lines;
}

const withoutStamp = (lines) => lines.filter((l) => !/^updated_at_utc:/.test(l)).join('\n');

function cmdOut(f) {
  const ref = f.ref;
  const statePath = path.resolve(f.state ?? STATE_REL);
  const originRoot = path.dirname(path.dirname(path.dirname(statePath)));
  const wtRoot = path.resolve(f.worktree);
  const wtState = path.join(wtRoot, STATE_REL);
  guardSingleWriter(statePath, wtState);

  const o = loadState(statePath);
  const parts = ridePartition(o.lines, ref);
  if (!parts.focusIsRide && !parts.item) refuse('ref_not_in_origin', `${ref} is neither the origin focus nor an active work item`);

  const wtReal = realOr(wtRoot);
  const listed = git(originRoot, ['worktree', 'list', '--porcelain']).stdout.split('\n')
    .filter((l) => l.startsWith('worktree ')).map((l) => realOr(l.slice('worktree '.length)));
  if (!listed.includes(wtReal) || wtReal === realOr(originRoot)) {
    refuse('worktree_not_registered', `${wtRoot} is not a linked worktree of ${originRoot}`);
  }
  if (!fs.existsSync(wtState)) {
    refuse('worktree_state_not_fresh', `${wtState} does not exist; create it with check-state.mjs --repair`);
  }
  const w = loadState(wtState);
  const stale = checkFresh(w.lines, ref, parts.entry);
  if (stale) refuse('worktree_state_not_fresh', stale);
  if (parts.focusIsRide && scalarOf(o.lines, 'human_input', 'required') === 'true') {
    refuse('hitl_pending', `${ref} waits for a human decision`);
  }
  const { plan, conflicts } = planDrafts(originRoot, wtRoot, ref, parts);
  if (conflicts.length > 0) refuse('draft_conflict', conflicts.join(', '));

  const baseRef = f['base-ref'] ?? scalarOf(o.lines, 'worktree', 'base_ref');
  if (!baseRef) usage('no base ref: pass --base-ref (the origin worktree.base_ref is empty)');
  const branchRes = git(wtRoot, ['branch', '--show-current']);
  const info = { baseRef, branch: branchRes.status === 0 ? branchRes.stdout.trim() : '', path: wtReal };
  const moved = entryRuns(o.lines, ref).length;
  const toMove = plan.filter((d) => !d.tracked);

  const prior = findStartedRecord(originRoot, ref, wtReal);
  const alreadyThere = Boolean(scalarOf(w.lines, 'current_focus', 'ref_id') === ref
    || parseItems(w.lines).items.some((x) => x.ref === ref) || entrySpan(w.lines, ref));
  const resumed = Boolean(prior && alreadyThere);

  if (f.dryRun) {
    say(`HANDOFF ${ref} (dry-run) moved=${moved} drafts=${toMove.length} blocks=${[parts.focus && 'focus', parts.item && 'item', parts.entry && 'metrics', parts.strategy && 'strategy', parts.codeReview && 'code_review', parts.lastValidation && 'last_validation', parts.tdd && 'tdd_cycle'].filter(Boolean).join(',')}`);
    exit(0);
  }

  const candidate = buildWorktreeLines(w.lines, ref, parts, info, o.lines);
  const originNext = o.lines.slice();
  const wtBlockNamesThis = (bl) => {
    const branch = unq((bl.find((l) => fieldRe(2, 'branch').test(l)) ?? '').split(':').slice(1).join(':'));
    const p = unq((bl.find((l) => fieldRe(2, 'path').test(l)) ?? '').split(':').slice(1).join(':'));
    return (info.branch && branch === info.branch) || (p !== null && p !== 'null' && realOr(p) === wtReal);
  };
  resetOrigin(originNext, ref, parts, wtBlockNamesThis);
  for (const [target, next] of [[wtState, candidate], [statePath, originNext]]) {
    const bad = duplicateKeys(next).map((d) => d.key).concat(inlineChildConflicts(next).map((c) => c.key));
    if (bad.length > 0) refuse('worktree_state_not_fresh', `${target} cannot take the handoff (inline-valued or duplicate top-level key: ${bad.join(', ')}); nothing was written`);
  }

  let dir;
  let recFile;
  let rec;
  if (resumed) {
    ({ dir, file: recFile, rec } = prior);
  } else {
    dir = newArchiveDir(originRoot, `${ref}-${utcStamp()}`);
    fs.copyFileSync(statePath, path.join(dir, 'STATE.pre-handoff.yaml'));
    recFile = path.join(dir, 'record.json');
    rec = {
      ref, worktree: wtReal, branch: info.branch, base_ref: baseRef, at_utc: new Date().toISOString(),
      runs_moved: moved, drafts_moved: 0, origin_archive: posix(path.relative(originRoot, path.join(dir, 'STATE.pre-handoff.yaml'))),
      status: 'started',
    };
    writeJson(recFile, rec);
  }

  for (const d of plan) {
    if (d.copy) {
      fs.mkdirSync(path.dirname(d.dst), { recursive: true });
      fs.copyFileSync(d.src, d.dst);
    }
  }
  if (!(resumed && withoutStamp(candidate) === withoutStamp(w.lines))) {
    bumpUpdatedAt(candidate);
    writeState(wtState, candidate, w.trailingNewline, w.raw);
  }
  if (process.env.AAI_RIDE_HANDOFF_INJECT_CRASH === 'after-worktree-write') process.kill(process.pid, 'SIGKILL');

  let draftsMoved = 0;
  for (const d of toMove) {
    if (fs.existsSync(d.src)) { moveFile(d.src, path.join(dir, 'drafts', d.rel)); draftsMoved += 1; }
  }
  writeState(statePath, originNext, o.trailingNewline, o.raw);
  writeJson(recFile, { ...rec, drafts_moved: Math.max(rec.drafts_moved ?? 0, draftsMoved), status: 'done' });
  say(`${resumed ? 'RESUMED' : 'HANDOFF'} ${ref} moved=${moved} drafts=${draftsMoved} archive=${posix(path.relative(originRoot, dir))}`);
  exit(0);
}

// --- reconcile -----------------------------------------------------------------------------

function ledgerKeys(metricsPath, ref) {
  const keys = new Set();
  if (!fs.existsSync(metricsPath)) return keys;
  for (const line of fs.readFileSync(metricsPath, 'utf8').split('\n')) {
    if (line.trim() === '') continue;
    let j;
    try { j = JSON.parse(line); } catch { continue; }
    if (j && j.ref_id === ref && Array.isArray(j.agent_runs)) {
      for (const r of j.agent_runs) keys.add(`${r.role}\u0000${r.started_utc}`);
    }
  }
  return keys;
}

function cmdReconcile(f) {
  const ref = f.ref;
  const statePath = path.resolve(f.state ?? STATE_REL);
  const originRoot = path.dirname(path.dirname(path.dirname(statePath)));
  guardSingleWriter(statePath);
  if (!fs.existsSync(statePath)) { say(`NOOP no_state ${ref}`); exit(0); }
  const o = loadState(statePath);
  const parts = ridePartition(o.lines, ref);
  if (!hasTrace(parts)) { say(`NOOP no_trace ${ref}`); exit(0); }

  const runs = entryRuns(o.lines, ref);
  if (runs.length > 0) {
    const metricsPath = path.resolve(f.metrics ?? path.join(originRoot, 'docs', 'ai', 'METRICS.jsonl'));
    const held = ledgerKeys(metricsPath, ref);
    for (const r of runs) {
      if (r.role === null || r.started === null || !held.has(`${r.role}\u0000${r.started}`)) {
        refuse('origin_runs_not_in_ledger', `${ref}: ${r.role ?? '?'} ${r.started ?? 'no started_utc'} is not in ${metricsPath}`);
      }
    }
  }
  if (f.dryRun) { say(`RECONCILED ${ref} (dry-run) cleared=${runs.length}`); exit(0); }

  const next = o.lines.slice();
  const branchGiven = f.branch ?? null;
  resetOrigin(next, ref, parts, (bl) => branchGiven !== null
    && unq((bl.find((l) => fieldRe(2, 'branch').test(l)) ?? '').split(':').slice(1).join(':')) === branchGiven);
  const dir = newArchiveDir(originRoot, `${ref}-reconcile-${utcStamp()}`);
  fs.copyFileSync(statePath, path.join(dir, 'STATE.pre-reconcile.yaml'));
  writeJson(path.join(dir, 'record.json'), {
    ref, kind: 'reconcile', at_utc: new Date().toISOString(), runs_cleared: runs.length, branch: branchGiven,
    origin_archive: posix(path.relative(originRoot, path.join(dir, 'STATE.pre-reconcile.yaml'))), status: 'done',
  });
  writeState(statePath, next, o.trailingNewline, o.raw);
  say(`RECONCILED ${ref} cleared=${runs.length} archive=${posix(path.relative(originRoot, dir))}`);
  exit(0);
}

function main(argv) {
  if (argv.includes('--help') || argv.includes('-h')) { process.stdout.write(HELP); exit(0); }
  const f = parseArgs(argv);
  if (f.sub === 'out') cmdOut(f);
  cmdReconcile(f);
}

runMain(() => main(process.argv.slice(2)));
