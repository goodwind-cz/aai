#!/usr/bin/env node
// roadmap-edit.mjs — the one writer of docs/ai/roadmap.yaml for menu edits and
// the automatic ship/close paths. SPEC roadmap-serves-downstream-projects D5.
//
//   node .aai/scripts/roadmap-edit.mjs add         --ref <slug> [--at <n>]
//   node .aai/scripts/roadmap-edit.mjs move        --ref <slug> --to <n>
//   node .aai/scripts/roadmap-edit.mjs done        --ref <slug>
//   node .aai/scripts/roadmap-edit.mjs drop        --ref <slug>
//   node .aai/scripts/roadmap-edit.mjs budget      on|off
//   node .aai/scripts/roadmap-edit.mjs off         --confirm
//   node .aai/scripts/roadmap-edit.mjs ship-append --ref <slug> --intake <path>
//   node .aai/scripts/roadmap-edit.mjs advance     --ref <slug>
//        (every verb also takes [--roadmap <p>] [--docs <dir>])
//
// One write discipline: read the original bytes, refuse before writing on any
// usage or semantic error, write, certify by spawning the sibling
// `ride-select.mjs validate --roadmap <p> --docs <d>` (the one parser lives in
// lib/roadmap-model.mjs), and on a refused certification restore the exact
// original bytes (or remove a file this run created) and exit 1.
// Exit: 0 success or named no-op · 1 refusal (file byte-identical) · 2 usage
// (file untouched).
//
// `advance` (the close path, D8) flips a pair to done once its documents are
// done and is a NAMED NO-OP in every other case; `done` is its strict owner twin.
// `ship-append` is a NAMED NO-OP (exit 0, nothing written, one line) when the
// roadmap is absent, the budget is on, the ref is already listed, or the intake
// type is a maintenance type: ship never turns the gate on by itself.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { parseFrontmatter } from './lib/docs-model.mjs';
import { SLUG, MAINT_TYPES, roadmapAbsent, loadRoadmap } from './lib/roadmap-model.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const SELECT = path.join(HERE, 'ride-select.mjs');
const VERBS = ['add', 'move', 'done', 'drop', 'budget', 'off', 'ship-append', 'advance'];
const NO_REF = new Set(['budget', 'off']);
const DOC_DIRS = ['issues', 'specs', 'rfc', 'releases', 'requirements']; // the dirs ride-select findDoc walks

function usage(msg) { process.stderr.write(`roadmap-edit: ${msg}\n`); process.exit(2); }
function refuse(msg) { process.stderr.write(`roadmap-edit: REFUSED — ${msg}\n`); process.exit(1); }
function noop(msg) { process.stdout.write(`${msg}\n`); process.exit(0); }

function parseArgs(argv) {
  const a = { verb: argv[0], roadmap: path.join(ROOT, 'docs/ai/roadmap.yaml'), docs: path.join(ROOT, 'docs'), ref: null, at: null, to: null, intake: null, confirm: false, state: null };
  const need = (k, v) => { if (v === undefined || v.startsWith('--')) usage(`${k} requires a value`); return v; };
  let first = 1;
  if (a.verb === 'budget') {
    if (argv[1] !== 'on' && argv[1] !== 'off') usage('usage: roadmap-edit.mjs budget <on|off>');
    a.state = argv[1]; first = 2;
  }
  for (let i = first; i < argv.length; i += 1) {
    const k = argv[i]; const v = argv[i + 1];
    if (k === '--roadmap') { a.roadmap = need(k, v); i += 1; }
    else if (k === '--docs') { a.docs = need(k, v); i += 1; }
    else if (k === '--ref') { a.ref = need(k, v); i += 1; }
    else if (k === '--intake') { a.intake = need(k, v); i += 1; }
    else if (k === '--confirm') { a.confirm = true; }
    else if (k === '--to') { const n = need(k, v); if (!/^[1-9]\d*$/.test(n)) usage('--to must be a positive integer'); a.to = Number(n); i += 1; }
    else if (k === '--at') { const n = need(k, v); if (!/^[1-9]\d*$/.test(n)) usage('--at must be a positive integer'); a.at = Number(n); i += 1; }
    else usage(`unknown argument ${k}`);
  }
  if (!VERBS.includes(a.verb)) usage(`usage: roadmap-edit.mjs <${VERBS.join('|')}> [flags]`);
  if (NO_REF.has(a.verb)) { if (a.ref) usage(`${a.verb} takes no --ref`); }
  else {
    if (!a.ref) usage(`${a.verb} requires --ref <slug>`);
    if (!SLUG.test(a.ref)) usage(`--ref "${a.ref}" is neither a slug id nor a numbered display id (TYPE-0000)`);
  }
  if (a.at !== null && a.verb !== 'add') usage('--at belongs to add');
  if (a.to !== null && a.verb !== 'move') usage('--to belongs to move');
  if (a.confirm && a.verb !== 'off') usage('--confirm belongs to off');
  if (a.intake && a.verb !== 'ship-append') usage('--intake belongs to ship-append');
  return a;
}

// --- text edits (line level; the certification is the correctness authority) ----
const TOP_KEY = /^([a-z_0-9]+):\s*$/;
function toLines(buf) {
  const lines = buf.toString('utf8').replace(/\r\n?/g, '\n').split('\n');
  if (lines[lines.length - 1] === '') lines.pop();
  return lines;
}
function sectionRange(lines, key) { // [start, end) of the lines AFTER `key:`; null when absent
  const h = lines.findIndex((l) => TOP_KEY.test(l) && TOP_KEY.exec(l)[1] === key);
  if (h < 0) return null;
  let end = lines.length;
  for (let i = h + 1; i < lines.length; i += 1) if (TOP_KEY.test(lines[i])) { end = i; break; }
  return [h + 1, end];
}
// Insert a pair block so it becomes the pair at 0-based index `at` (>= count = last).
function insertPair(lines, at, block) {
  const [start, end] = sectionRange(lines, 'pairs');
  const starts = [];
  for (let i = start; i < end; i += 1) if (/^  - capability:/.test(lines[i])) starts.push(i);
  let where;
  if (at >= starts.length) {
    where = start;
    for (let i = start; i < end; i += 1) if (lines[i].trim() !== '' && !/^\s*#/.test(lines[i])) where = i + 1;
  } else where = starts[at];
  return [...lines.slice(0, where), ...block, ...lines.slice(where)];
}
function removeWave2(lines, ref) {
  const r = sectionRange(lines, 'wave_2');
  if (!r) return lines;
  return lines.filter((l, i) => !(i >= r[0] && i < r[1] && new RegExp(`^  - ${ref.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`).test(l)));
}
const render = (lines) => `${lines.join('\n')}\n`;
const toText = (buf) => render(toLines(buf));

// The pairs section split into its parts: head (through `pairs:` and any lead
// comments), one line array per pair block, tail (what follows the last block's
// content). Comment/blank lines between two blocks travel with the block above.
function pairLayout(lines) {
  const [start, end] = sectionRange(lines, 'pairs');
  const starts = [];
  for (let i = start; i < end; i += 1) if (/^  - capability:/.test(lines[i])) starts.push(i);
  let last = starts.length ? starts[0] : start;
  for (let i = start; i < end; i += 1) if (lines[i].trim() !== '' && !/^\s*#/.test(lines[i])) last = i + 1;
  const blocks = starts.map((s, k) => lines.slice(s, k + 1 < starts.length ? starts[k + 1] : last));
  return { head: lines.slice(0, starts[0]), blocks, tail: lines.slice(last) };
}
const joinLayout = (l) => [...l.head, ...l.blocks.flat(), ...l.tail];
const blockRef = (block) => /^  - capability:\s*(.+?)\s*$/.exec(block[0])[1];
function setPairStatus(text, ref, status) {
  const layout = pairLayout(toLines(text));
  const block = layout.blocks.find((b) => blockRef(b) === ref);
  const at = block.findIndex((l) => /^    status:/.test(l));
  block[at] = `    status: ${status}`;
  return render(joinLayout(layout));
}
function removeBudget(text) { // the `budget:` header plus its indented body, nothing else
  const lines = toLines(text);
  const h = lines.findIndex((l) => TOP_KEY.test(l) && TOP_KEY.exec(l)[1] === 'budget');
  let e = h + 1;
  while (e < lines.length && /^ {2}\S/.test(lines[e])) e += 1;
  return render([...lines.slice(0, h), ...lines.slice(e)]);
}
function addBudget(text) { // the block goes directly before `pairs:`
  const lines = toLines(text);
  const p = lines.findIndex((l) => TOP_KEY.test(l) && TOP_KEY.exec(l)[1] === 'pairs');
  return render([...lines.slice(0, p), 'budget:', '  maintenance_per_capability: 1', ...lines.slice(p)]);
}
function docStatus(docsDir, ref) { // frontmatter status of the document whose id is ref, or null
  for (const sub of DOC_DIRS) {
    const dir = path.join(docsDir, sub);
    let names; try { names = fs.readdirSync(dir); } catch { continue; }
    for (const n of names) {
      if (!n.endsWith('.md')) continue;
      let fm; try { fm = parseFrontmatter(fs.readFileSync(path.join(dir, n), 'utf8')); } catch { continue; }
      if (fm && fm.id === ref) return fm.status ? String(fm.status).trim() : null;
    }
  }
  return null;
}

// --- write discipline ------------------------------------------------------------
function certify(a) {
  const r = spawnSync(process.execPath, [SELECT, 'validate', '--roadmap', a.roadmap, '--docs', a.docs], { encoding: 'utf8' });
  return { ok: r.status === 0, stderr: r.stderr || String(r.error || '') };
}
function restore(p, original, existed) {
  if (existed) fs.writeFileSync(p, original);
  else fs.rmSync(p, { force: true });
}
function topMissingDir(p) { // the first directory of p's chain that does not exist yet, or null
  let d = path.dirname(path.resolve(p)); let top = null;
  while (!fs.existsSync(d)) { top = d; d = path.dirname(d); }
  return top;
}
function commitEdit(a, original, existed, newText, okLine) {
  const created = existed ? null : topMissingDir(a.roadmap);
  fs.mkdirSync(path.dirname(a.roadmap), { recursive: true });
  fs.writeFileSync(a.roadmap, newText);
  const cert = certify(a);
  if (!cert.ok) {
    restore(a.roadmap, original, existed);
    if (created) fs.rmSync(created, { recursive: true, force: true });
    process.stderr.write(cert.stderr);
    refuse(`the edited roadmap did not validate — ${existed ? 'original bytes restored' : 'nothing left behind'} (${a.roadmap})`);
  }
  process.stdout.write(`${okLine}\n`);
  process.exit(0);
}
function loadCurrent(a) { // the CURRENT file must already be valid, or no edit is attempted
  if (roadmapAbsent(a.roadmap)) refuse(`there is no roadmap at ${a.roadmap} — create one with: roadmap-edit.mjs add --ref <slug>`);
  const original = fs.readFileSync(a.roadmap);
  const loaded = loadRoadmap(a.roadmap);
  if (loaded.error) refuse(`${loaded.error} (${a.roadmap}) — fix or remove the roadmap before editing it`);
  return { original, rm: loaded.roadmap };
}
const listed = (rm, ref) => rm.pairs.some((p) => p.capability === ref || p.maintenance === ref);

// --- verbs -----------------------------------------------------------------------
function cmdAdd(a) {
  if (roadmapAbsent(a.roadmap)) {
    if (a.at !== null && a.at !== 1) usage('--at must be 1 for a roadmap that does not exist yet');
    const created = `pairs:\n  - capability: ${a.ref}\n    status: planned\n`;
    return commitEdit(a, null, false, created, `roadmap: created ${a.roadmap} with ${a.ref} — the ride gate is now ON for every ride from here`);
  }
  const { original, rm } = loadCurrent(a);
  if (listed(rm, a.ref)) refuse(`${a.ref} is already a pair on the roadmap`);
  const count = rm.pairs.length;
  if (a.at !== null && a.at > count + 1) usage(`--at ${a.at} is out of range (1..${count + 1})`);
  const at = a.at === null ? count : a.at - 1;
  const lines = insertPair(removeWave2(toLines(original), a.ref), at, [`  - capability: ${a.ref}`, '    status: planned']);
  return commitEdit(a, original, true, render(lines), `roadmap: added ${a.ref} at position ${at + 1}`);
}

function cmdShipAppend(a) {
  if (!a.intake) usage('ship-append requires --intake <path>');
  let content;
  try { content = fs.readFileSync(a.intake, 'utf8'); } catch { usage(`--intake ${a.intake} is not readable`); }
  const fm = parseFrontmatter(content);
  if (!fm || !fm.id) usage(`--intake ${a.intake} carries no frontmatter id`);
  if (fm.id !== a.ref) usage(`--intake ${a.intake} has id "${fm.id}", not --ref ${a.ref}`);
  const intake = { id: fm.id, type: fm.type || null };
  if (roadmapAbsent(a.roadmap)) return noop('roadmap absent, nothing appended');
  const { original, rm } = loadCurrent(a);
  if (rm.budget) return noop('roadmap budget is on, nothing appended (an owner adds capabilities with /aai-roadmap add)');
  if (listed(rm, a.ref)) return noop(`${a.ref} is already on the roadmap, nothing appended`);
  if (MAINT_TYPES.has(intake.type)) return noop(`${a.ref} is a maintenance intake (type ${intake.type}), nothing appended`);
  const SHIP_STATUS = 'active';
  const lines = insertPair(removeWave2(toLines(original), a.ref), rm.pairs.length, [`  - capability: ${a.ref}`, `    status: ${SHIP_STATUS}`]);
  return commitEdit(a, original, true, render(lines), `roadmap: appended ${a.ref}`);
}

function cmdMove(a) {
  if (a.to === null) usage('move requires --to <n>');
  const { original, rm } = loadCurrent(a);
  const from = rm.pairs.findIndex((p) => p.capability === a.ref);
  if (from < 0) refuse(`${a.ref} is not a pair capability on the roadmap`);
  if (a.to > rm.pairs.length) usage(`--to ${a.to} is out of range (1..${rm.pairs.length})`);
  const to = a.to - 1;
  if (to === from) return noop(`${a.ref} is already at position ${a.to}, nothing moved`);
  const layout = pairLayout(toLines(original));
  const [moved] = layout.blocks.splice(from, 1);
  layout.blocks.splice(to, 0, moved);
  return commitEdit(a, original, true, render(joinLayout(layout)), `roadmap: moved ${a.ref} to position ${a.to}`);
}

function cmdDone(a) { // owner twin of advance: strict, no document-status check beyond certification
  const { original, rm } = loadCurrent(a);
  const pair = rm.pairs.find((p) => p.capability === a.ref);
  if (!pair) refuse(`${a.ref} is not a pair capability on the roadmap`);
  if (pair.status === 'done') refuse(`${a.ref} is already marked done`);
  const text = toText(original);
  return commitEdit(a, original, true, setPairStatus(text, a.ref, 'done'), `roadmap: marked ${a.ref} done`);
}

function cmdDrop(a) {
  const { original, rm } = loadCurrent(a);
  const lines = toLines(original);
  if (rm.pairs.some((p) => p.capability === a.ref)) {
    const layout = pairLayout(lines);
    layout.blocks = layout.blocks.filter((b) => blockRef(b) !== a.ref);
    return commitEdit(a, original, true, render(joinLayout(layout)), `roadmap: dropped ${a.ref}`);
  }
  if (rm.wave_2.includes(a.ref)) {
    const [start, end] = sectionRange(lines, 'wave_2');
    const kept = lines.filter((l, i) => !(i >= start && i < end && l.trim() === `- ${a.ref}`));
    return commitEdit(a, original, true, render(kept), `roadmap: dropped ${a.ref} from wave_2`);
  }
  if (listed(rm, a.ref)) refuse(`${a.ref} is only a maintenance half — drop its capability to remove the pair`);
  return refuse(`${a.ref} is neither a pair capability nor a wave_2 entry`);
}

function cmdBudget(a) {
  const { original, rm } = loadCurrent(a);
  if (a.state === 'on') {
    if (rm.budget) refuse('the maintenance budget is already on');
    return commitEdit(a, original, true, addBudget(toText(original)), 'roadmap: maintenance budget on — the gate now enforces the 1:1 pairing');
  }
  if (!rm.budget) refuse('the maintenance budget is already off');
  const text = toText(original);
  const stripped = removeBudget(text);
  return commitEdit(a, original, true, stripped, 'roadmap: maintenance budget off — maintenance: lines stay but are inert');
}

function cmdOff(a) {
  if (!a.confirm) usage('off removes the roadmap file — pass --confirm');
  loadCurrent(a);
  fs.unlinkSync(a.roadmap);
  process.stdout.write(`roadmap: removed ${a.roadmap} — rides are no longer gated\n`);
  process.exit(0);
}

function cmdAdvance(a) {
  if (roadmapAbsent(a.roadmap)) return noop('roadmap absent, nothing advanced');
  const { original, rm } = loadCurrent(a);
  const pair = rm.pairs.find((p) => p.capability === a.ref || (rm.budget && p.maintenance === a.ref));
  if (!pair) return noop(`${a.ref} is not a pair${rm.budget ? '' : ' capability'} on the roadmap, nothing advanced`);
  if (pair.status === 'done') return noop(`${pair.capability} is already done, nothing advanced`);
  const capStatus = docStatus(a.docs, pair.capability);
  if (capStatus !== 'done') return noop(`${pair.capability} document is ${capStatus || 'missing'}, not done — pair stays`);
  if (rm.budget) {
    if (pair.maintenance === null) return noop(`${pair.capability} has no bound maintenance half yet — pair stays`);
    const maintStatus = docStatus(a.docs, pair.maintenance);
    if (maintStatus !== 'done') return noop(`maintenance half ${pair.maintenance} is ${maintStatus || 'missing'}, not done — pair stays`);
  }
  return commitEdit(a, original, true, setPairStatus(toText(original), pair.capability, 'done'), `roadmap: advanced ${pair.capability} to done`);
}

const HANDLERS = { add: cmdAdd, move: cmdMove, done: cmdDone, drop: cmdDrop, budget: cmdBudget, off: cmdOff, 'ship-append': cmdShipAppend, advance: cmdAdvance };
function main() {
  const a = parseArgs(process.argv.slice(2));
  return HANDLERS[a.verb](a);
}

main();
