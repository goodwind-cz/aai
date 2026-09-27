#!/usr/bin/env node
// roadmap-propose.mjs — gives docs/ai/roadmap.yaml an INPUT (SPEC-DRAFT
// spec-roadmap-takes-direction). ride-select.mjs only ever refuses or
// proposes from what is already written; this sibling script harvests
// capability candidates from three sources that already exist (draft
// intakes, the roadmap's own wave_2 list, review_candidate friction
// clusters), ranks them against ONE sentence of owner direction with every
// ranking component PRINTED (D6 — never a hidden score), and (write/bind,
// later slice of this scope) writes a roadmap the SHIPPED
// `ride-select.mjs validate` accepts.
//
// THIS FILE, THIS SLICE: `harvest` only (Spec-AC-06..11). `write` and `bind`
// (Spec-AC-12..15) are a later run of this same spec — see the spec's
// Implementation plan; D1 already fixes the two-surface split so no later
// change here disturbs ride-select.mjs's hot refusal path.
//
//   node .aai/scripts/roadmap-propose.mjs harvest [--direction "<sentence>"]
//        [--roadmap <path>] [--docs <dir>] [--ledger <path>] [--spool <path>]
//        [--json]
//
// Exit: 0 success (an empty slate is still success — D6/D12 belong to
// write, not harvest) · 2 usage. Node stdlib only (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { parseFrontmatter, walk, TERMINAL_DOC_STATUS } from './lib/docs-model.mjs';
import { readSpoolRows } from './lib/friction-spool.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const FOLLOW_UPS_SCRIPT = path.join(HERE, 'follow-ups.mjs');
const TRIAGE_SCRIPT = path.join(HERE, 'aai-feedback-triage.mjs');

// D8: the roadmap now carries capabilities only — these are the intake
// `type` values a draft may harvest as one. Maintenance types (issue,
// techdebt, hotfix, chore, test, ci) are excluded on purpose.
const CAPABILITY_TYPES = new Set(['change', 'prd', 'requirement', 'rfc', 'research']);

function usage(msg) {
  process.stderr.write(`roadmap-propose: ${msg}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const a = {
    cmd: argv[0],
    direction: '',
    roadmap: path.join(ROOT, 'docs/ai/roadmap.yaml'),
    docs: path.join(ROOT, 'docs'),
    ledger: path.join(ROOT, 'docs/ai/decisions.jsonl'),
    spool: path.join(ROOT, 'docs/ai/friction/observations.jsonl'),
    json: false,
  };
  const need = (k, v) => { if (v === undefined || v.startsWith('--')) usage(`${k} requires a value`); return v; };
  for (let i = 1; i < argv.length; i += 1) {
    const k = argv[i]; const v = argv[i + 1];
    if (k === '--direction') { a.direction = need(k, v); i += 1; }
    else if (k === '--roadmap') { a.roadmap = need(k, v); i += 1; }
    else if (k === '--docs') { a.docs = need(k, v); i += 1; }
    else if (k === '--ledger') { a.ledger = need(k, v); i += 1; }
    else if (k === '--spool') { a.spool = need(k, v); i += 1; }
    else if (k === '--json') { a.json = true; }
    else usage(`unknown argument ${k}`);
  }
  if (a.cmd !== 'harvest') usage('usage: roadmap-propose.mjs harvest [--direction "<sentence>"] [--roadmap <p>] [--docs <dir>] [--ledger <p>] [--spool <p>] [--json]');
  return a;
}

// --- D7: direction is counted, printed token overlap -----------------------
// A closed 40-word stopword list: common function words of 4+ characters
// that would otherwise "match" a candidate's label by coincidence rather
// than by the owner's actual direction. The partition assertion below is the
// anti-drift pin (same shape as docs-model.mjs's own IN_FLIGHT/TERMINAL
// check) — an edit that silently drops below 40 entries throws at import
// rather than quietly weakening D7's "closed" claim.
const STOPWORDS = new Set([
  'this', 'that', 'with', 'from', 'into', 'onto', 'have', 'will', 'shall',
  'would', 'could', 'should', 'been', 'being', 'were', 'when', 'where',
  'which', 'while', 'about', 'after', 'before', 'their', 'there', 'those',
  'these', 'only', 'also', 'than', 'then', 'some', 'such', 'more', 'most',
  'much', 'many', 'just', 'over', 'under', 'between',
]);
if (STOPWORDS.size !== 40) {
  throw new Error(`roadmap-propose: STOPWORDS must be the closed 40-word list D7 names, got ${STOPWORDS.size}`);
}

function tokenize(text) {
  return (String(text).toLowerCase().match(/[a-z0-9]+/g) || [])
    .filter((tok) => tok.length >= 4 && !STOPWORDS.has(tok));
}

// directionMatch(sentence, label) -> { direction, direction_tokens } — the
// count of DISTINCT tokens shared between the owner's sentence and the
// candidate's own label, and the matched tokens themselves (D7: printed, not
// hidden).
function directionMatch(sentence, label) {
  const sentenceTokens = new Set(tokenize(sentence));
  const labelTokens = new Set(tokenize(label));
  const shared = new Set([...sentenceTokens].filter((t) => labelTokens.has(t)));
  return { direction: shared.size, direction_tokens: [...shared].sort() };
}

// --- D6: the comparator is a printed lexicographic tuple, never a hidden ---
// score. (direction DESC, observations DESC, blocks_in DESC, age_days DESC,
// id ASC) — the id tail makes the order total and deterministic (Spec-AC-10).
function compareCandidates(a, b) {
  return b.direction - a.direction ||
    b.observations - a.observations ||
    b.blocks_in - a.blocks_in ||
    b.age_days - a.age_days ||
    (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

// --- sources -----------------------------------------------------------------

// D8 intake source: docs/issues/*.md (direct children only — never a
// recursive walk) whose frontmatter carries status: draft and a type in the
// capability set.
function intakeCandidates(docsDir) {
  const dir = path.join(docsDir, 'issues');
  let names;
  try { names = fs.readdirSync(dir); } catch { return []; }
  const out = [];
  for (const n of names.sort()) {
    if (!n.endsWith('.md')) continue;
    const p = path.join(dir, n);
    let content;
    try { content = fs.readFileSync(p, 'utf8'); } catch { continue; }
    const fm = parseFrontmatter(content);
    if (!fm || !fm.id || fm.status !== 'draft') continue;
    if (!CAPABILITY_TYPES.has(fm.type)) continue;
    const heading = (content.split('\n').find((l) => /^# /.test(l)) || '').trim();
    out.push({ id: fm.id, source: 'intake', label: `${fm.id} ${heading}`.trim(), path: p });
  }
  return out;
}

// A read-only, best-effort scan of the roadmap for two lists harvest needs —
// NOT the closed-shape validator. ride-select.mjs's own loadRoadmap is the
// one authority that decides validity (D10: write/bind spawn it unchanged
// for certification); this reader never admits or refuses anything, tolerates
// an absent or unparseable roadmap as "nothing to exclude" (Spec-AC-15: no
// roadmap means wave_2 contributes nothing), and exists only so harvest knows
// which wave_2 slugs are not already paired.
function readWave2AndPairSlugs(roadmapPath) {
  const pairSlugs = new Set();
  const wave2 = [];
  let text;
  try { text = fs.readFileSync(roadmapPath, 'utf8'); } catch { return { pairSlugs, wave2 }; }
  const lines = text.replace(/\r\n?/g, '\n').split('\n').filter((l) => !/^\s*#/.test(l) && l.trim() !== '');
  let section = null;
  for (const line of lines) {
    let m;
    if ((m = /^([a-z_0-9]+):\s*$/.exec(line))) { section = m[1]; continue; }
    if (section === 'pairs' && (m = /^  - capability:\s*(.+?)\s*$/.exec(line))) { pairSlugs.add(m[1]); continue; }
    if (section === 'wave_2' && (m = /^  - (.+?)\s*$/.exec(line))) { wave2.push(m[1]); continue; }
  }
  return { pairSlugs, wave2 };
}

// D8 wave_2 source: every roadmap wave_2 slug that is not already a pair.
function wave2Candidates(roadmapInfo, docsDir) {
  const { pairSlugs, wave2 } = roadmapInfo;
  return wave2
    .filter((slug) => !pairSlugs.has(slug))
    .map((slug) => ({ id: slug, source: 'wave_2', label: slug, path: resolveDocPath(docsDir, slug) }));
}

// Best-effort id -> path resolution for age_days only (never for validity).
function resolveDocPath(docsDir, id) {
  for (const p of walk(docsDir)) {
    let content;
    try { content = fs.readFileSync(p, 'utf8'); } catch { continue; }
    const fm = parseFrontmatter(content);
    if (fm && fm.id === id) return p;
  }
  return null;
}

function slugify(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

// D8: friction-<skill_id>-<failure_class>, slugified — NEVER a bare
// fingerprint (Spec-AC-11).
function frictionLabel(row) {
  return slugify(`friction-${row.skill_id || 'unknown'}-${row.failure_class || 'unknown'}`);
}

// D8 friction source: only clusters aai-feedback-triage.mjs decides
// review_candidate, joined back to the spool by fingerprint (the shared
// lib/friction-spool.mjs reader, never a second spool parser) to recover
// skill_id/skill_phase/failure_class — a triage cluster itself carries none
// of those (measurement 7). An empty or absent spool contributes zero
// candidates and one printed NOTE, never an error.
function frictionCandidates(spoolPath, notes) {
  const rows = readSpoolRows(spoolPath);
  if (rows.length === 0) {
    notes.push('the friction spool is empty or absent — 0 friction candidates');
    return [];
  }
  const outPath = path.join(os.tmpdir(), `roadmap-propose-triage-${process.pid}-${Date.now()}.json`);
  let report;
  try {
    execFileSync(process.execPath, [TRIAGE_SCRIPT, '--spool', spoolPath, '--out', outPath], { stdio: ['ignore', 'pipe', 'pipe'] });
    report = JSON.parse(fs.readFileSync(outPath, 'utf8'));
  } catch (e) {
    notes.push(`friction triage could not run — 0 friction candidates (${e.message})`);
    return [];
  } finally {
    try { fs.unlinkSync(outPath); } catch { /* best-effort cleanup */ }
  }
  const byFingerprint = new Map();
  for (const row of rows) {
    if (row && typeof row.fingerprint === 'string' && !byFingerprint.has(row.fingerprint)) {
      byFingerprint.set(row.fingerprint, row);
    }
  }
  const byLabel = new Map();
  for (const c of report.clusters || []) {
    if (c.decision === 'review_candidate') {
      const row = byFingerprint.get(c.fingerprint) || {};
      const id = frictionLabel(row);
      if (byLabel.has(id)) {
        byLabel.get(id).recurrence += c.recurrence;
      } else {
        byLabel.set(id, { id, source: 'friction', label: id, path: null, recurrence: c.recurrence });
      }
    }
  }
  return [...byLabel.values()];
}

// --- evidence (D9) ------------------------------------------------------------

function readFollowUps(ledgerPath) {
  try {
    const raw = execFileSync(process.execPath, [FOLLOW_UPS_SCRIPT, 'list', '--ledger', ledgerPath, '--status', 'all', '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed.items) ? parsed.items : [];
  } catch { return []; }
}

// observations: OPEN follow-ups whose ref_id equals the candidate id.
function openFollowUpCount(followUps, candidateId) {
  return followUps.filter((it) => it.ref_id === candidateId && it.status === 'open').length;
}

// blocks_in: documents under docsDir whose frontmatter blocks: names the
// candidate id and whose own status is not terminal.
function blocksInCount(docsDir, candidateId) {
  let count = 0;
  for (const p of walk(docsDir)) {
    let content;
    try { content = fs.readFileSync(p, 'utf8'); } catch { continue; }
    const fm = parseFrontmatter(content);
    if (!fm || !fm.blocks || fm.blocks !== candidateId) continue;
    const st = fm.status || '';
    if (!TERMINAL_DOC_STATUS.has(st)) count += 1;
  }
  return count;
}

// The repo whose history age_days reads is wherever --docs actually lives —
// a fixture tree in its OWN git checkout under tests, or this project's own
// ROOT for the live corpus (git -C docs rev-parse --show-toplevel resolves
// to ROOT either way). Never hardcoded to ROOT: a candidate path outside
// whatever repo ROOT names would silently read as untracked forever.
function findRepoRoot(dir) {
  try {
    return execFileSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch { return null; }
}

// age_days: whole days between today and the candidate's first-commit date
// (git log --diff-filter=A --format=%cs -- <path>, LAST line — git prints
// most-recent-first, so the oldest add is the last line). An untracked,
// path-less, or non-git candidate reports age_days 0 and a note that its
// age is not known (R5: a shallow clone or unborn branch degrades the same
// way) — the literal note text lives ONLY at each return site below.
function ageDays(candidatePath, repoRoot) {
  if (!candidatePath || !repoRoot) return { age_days: 0, note: 'age unknown' };
  let out;
  try {
    out = execFileSync('git', ['-C', repoRoot, 'log', '--diff-filter=A', '--format=%cs', '--', candidatePath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch { out = ''; }
  const lines = out.split('\n').filter(Boolean);
  if (!lines.length) return { age_days: 0, note: 'age unknown' };
  const first = new Date(`${lines[lines.length - 1]}T00:00:00Z`);
  if (Number.isNaN(first.getTime())) return { age_days: 0, note: 'age unknown' };
  const today = new Date(`${new Date().toISOString().slice(0, 10)}T00:00:00Z`);
  const days = Math.round((today.getTime() - first.getTime()) / 86400000);
  return { age_days: Math.max(days, 0), note: null };
}

// --- assembly ------------------------------------------------------------------

function evaluateCandidate(c, ctx) {
  const { direction, direction_tokens } = directionMatch(ctx.direction, c.label);
  let observations = openFollowUpCount(ctx.followUps, c.id);
  if (c.source === 'friction' && typeof c.recurrence === 'number') observations += c.recurrence;
  const blocksIn = blocksInCount(ctx.docsDir, c.id);
  const age = ageDays(c.path, ctx.repoRoot);
  return {
    id: c.id,
    source: c.source,
    label: c.label,
    direction,
    direction_tokens,
    observations,
    blocks_in: blocksIn,
    age_days: age.age_days,
    age_note: age.note,
  };
}

function buildCandidates(a) {
  const notes = [];
  const roadmapInfo = readWave2AndPairSlugs(a.roadmap);
  const raw = [
    ...intakeCandidates(a.docs),
    ...wave2Candidates(roadmapInfo, a.docs),
    ...frictionCandidates(a.spool, notes),
  ];
  const followUps = readFollowUps(a.ledger);
  const repoRoot = findRepoRoot(a.docs);
  const ctx = { direction: a.direction, docsDir: a.docs, followUps, repoRoot };
  const candidates = raw.map((c) => evaluateCandidate(c, ctx));
  candidates.sort(compareCandidates);
  return { candidates, notes };
}

function formatRow(c) {
  const tokens = c.direction_tokens.length ? c.direction_tokens.join(',') : 'none';
  const age = c.age_note ? `${c.age_days} (${c.age_note})` : String(c.age_days);
  return `${c.id} [${c.source}] direction=${c.direction} (${tokens}) observations=${c.observations} blocks_in=${c.blocks_in} age_days=${age}`;
}

function cmdHarvest(a) {
  const { candidates, notes } = buildCandidates(a);
  if (a.json) {
    process.stdout.write(`${JSON.stringify({ candidates, notes })}\n`);
  } else {
    for (const note of notes) process.stdout.write(`NOTE: ${note}\n`);
    for (const c of candidates) process.stdout.write(`${formatRow(c)}\n`);
    process.stdout.write(`${candidates.length} candidate(s)\n`);
  }
  process.exit(0);
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  if (a.cmd === 'harvest') return cmdHarvest(a);
  usage(`unknown command ${a.cmd}`);
}

main();
