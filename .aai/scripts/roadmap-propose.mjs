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
// THIS FILE now also owns `write` and `bind` (Spec-AC-12..15, D10/D13): both
// APPEND to docs/ai/roadmap.yaml and then certify the result by spawning the
// REAL `ride-select.mjs validate` as a child process — never a second copy
// of the roadmap parser (D10). A refused certification restores the exact
// prior bytes (or removes the file this run created) before exiting 1.
//
//   node .aai/scripts/roadmap-propose.mjs harvest [--direction "<sentence>"]
//        [--roadmap <path>] [--docs <dir>] [--ledger <path>] [--spool <path>]
//        [--json]
//   node .aai/scripts/roadmap-propose.mjs write --pick <n[,n...]>
//        --direction "<sentence>" [--roadmap <path>] [--docs <dir>]
//        [--ledger <path>] [--spool <path>]
//        (--direction is REQUIRED on write, not optional: --pick is an index
//        into the ranking that sentence produces, and write re-runs that
//        ranking itself rather than trusting a caller-supplied selection —
//        see BLOCKING-1 / F2 in validation-round1.txt.)
//   node .aai/scripts/roadmap-propose.mjs bind --capability <slug>
//        --ref <maintenance-ref> [--roadmap <path>] [--docs <dir>]
//        [--ledger <path>]
//
// Exit: 0 success (an empty harvest slate is still success — D6/D12 belong
// to write, not harvest) · 1 refusal (nothing harvested, certification
// failed, bind's backlog check failed) · 2 usage. Node stdlib only
// (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { parseFrontmatter, walk, TERMINAL_DOC_STATUS } from './lib/docs-model.mjs';
import { readSpoolRowsDetailed } from './lib/friction-spool.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const FOLLOW_UPS_SCRIPT = path.join(HERE, 'follow-ups.mjs');
const TRIAGE_SCRIPT = path.join(HERE, 'aai-feedback-triage.mjs');
// D10: the certification authority — resolved as a SIBLING of this file (by
// import.meta.url, exactly like FOLLOW_UPS_SCRIPT/TRIAGE_SCRIPT above), so a
// test that runs an argv-recording shim under a copied .aai/scripts tree
// invokes ITS OWN sibling, never a hardcoded production path.
const RIDE_SELECT_SCRIPT = path.join(HERE, 'ride-select.mjs');

// D8: the roadmap now carries capabilities only — these are the intake
// `type` values a draft may harvest as one. Maintenance types (issue,
// techdebt, hotfix, chore, test, ci) are excluded on purpose.
const CAPABILITY_TYPES = new Set(['change', 'prd', 'requirement', 'rfc', 'research']);

function usage(msg) {
  process.stderr.write(`roadmap-propose: ${msg}\n`);
  process.exit(2);
}

// refuse(msg) — exit 1, the same "named refusal" shape ride-select.mjs uses:
// a decision the caller can act on (nothing harvested, certification
// failed, ref not in the backlog), never a usage mistake.
function refuse(msg) {
  process.stderr.write(`roadmap-propose: REFUSED — ${msg}\n`);
  process.exit(1);
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
    pick: null,
    capability: null,
    ref: null,
  };
  const need = (k, v) => { if (v === undefined || v.startsWith('--')) usage(`${k} requires a value`); return v; };
  for (let i = 1; i < argv.length; i += 1) {
    const k = argv[i]; const v = argv[i + 1];
    if (k === '--direction') { a.direction = need(k, v); i += 1; }
    else if (k === '--roadmap') { a.roadmap = need(k, v); i += 1; }
    else if (k === '--docs') { a.docs = need(k, v); i += 1; }
    else if (k === '--ledger') { a.ledger = need(k, v); i += 1; }
    else if (k === '--spool') { a.spool = need(k, v); i += 1; }
    else if (k === '--pick') { a.pick = need(k, v); i += 1; }
    else if (k === '--capability') { a.capability = need(k, v); i += 1; }
    else if (k === '--ref') { a.ref = need(k, v); i += 1; }
    else if (k === '--json') { a.json = true; }
    else usage(`unknown argument ${k}`);
  }
  if (!['harvest', 'write', 'bind'].includes(a.cmd)) {
    usage('usage: roadmap-propose.mjs <harvest|write|bind> ...\n' +
      '  harvest [--direction "<sentence>"] [--roadmap <p>] [--docs <dir>] [--ledger <p>] [--spool <p>] [--json]\n' +
      '  write --pick <n[,n...]> --direction "<sentence>" [--roadmap <p>] [--docs <dir>] [--ledger <p>] [--spool <p>]\n' +
      '  bind --capability <slug> --ref <maintenance-ref> [--roadmap <p>] [--docs <dir>] [--ledger <p>]');
  }
  if (a.cmd === 'write' && !a.pick) usage('write requires --pick <n[,n...]>');
  // BLOCKING-1 (validation round 1, F2): `write` used to re-run harvest's own
  // ranking with `--direction` OPTIONAL, defaulting to "" — an owner who
  // picked row N off a DIRECTED harvest could silently get a DIFFERENT
  // candidate written, because the un-directed re-ranking sorted differently
  // and picks.map((i) => candidates[i - 1]) then indexed into that other
  // order. `--pick` is only ever a safe index into "the ranking the owner
  // just looked at" when write is handed the EXACT SAME sentence — so write
  // now refuses (usage, exit 2, nothing written) unless `--direction` is
  // given, the same way it already refuses a missing `--pick`. (The
  // alternative the finding names — pick by id instead of index — was
  // rejected: an id-based pick still needs a stable id-per-row, which is
  // strictly more surface for the same guarantee this one flag already buys.)
  if (a.cmd === 'write' && !a.direction) usage('write requires --direction "<sentence>" (the SAME sentence the harvest ranking being picked from was run with — Spec-AC-12/F2)');
  if (a.cmd === 'bind') {
    if (!a.capability) usage('bind requires --capability <slug>');
    if (!a.ref) usage('bind requires --ref <maintenance-ref>');
  }
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

// normalizeToken(tok) -> a CONSERVATIVE, suffix-only English-plural fold —
// no dictionary, no dependency (docs/TECHNOLOGY.md: Node stdlib only). Fixes
// the live-corpus defect an owner sentence in ordinary prose ("decisions as
// menus") scored 0 against a candidate label written in the singular
// ("decision-menu-options-parser"), because matching was exact-token
// equality: the whole premise of a ONE-SENTENCE direction is that the owner
// never has to already know the candidate's own slug words.
// Rules, applied in order, first match wins:
//   - boxes/glasses/watches -> box/glass/watch  (…sses/…ches/…shes/…xes/…zes)
//   - categories -> category                    (…ies -> …y)
//   - options -> option, decisions -> decision  (a single trailing s, not ss)
// DISCLOSED LIMITS (D7 amendment): this is a suffix rule, not morphology —
// it does not fold irregular plurals (child/children), derivational forms
// (decide/decision) or verb inflection (-ing/-ed), so those still need the
// owner to share the candidate's own word; and it over-stems a handful of
// singular nouns that themselves end in one "s" (status, campus, bonus),
// folding them to a non-word that then simply fails to match anything real —
// a false NEGATIVE, never a false positive, and the same shape of trade-off
// D7 already accepted for the 4-character token floor.
function normalizeToken(tok) {
  if (tok.length > 5 && /(sses|ches|shes|xes|zes)$/.test(tok)) return tok.slice(0, -2);
  if (tok.length > 4 && /ies$/.test(tok)) return `${tok.slice(0, -3)}y`;
  if (tok.length > 4 && /s$/.test(tok) && !/ss$/.test(tok)) return tok.slice(0, -1);
  return tok;
}

// directionMatch(sentence, label) -> { direction, direction_tokens } — the
// count of DISTINCT normalized tokens shared between the owner's sentence and
// the candidate's own label, and the matched (normalized) tokens themselves
// (D7: printed, not hidden). Normalizing BOTH sides through the same fold
// (normalizeToken) is what lets "decisions" reach a label written as
// "decision" without the owner ever typing the candidate's exact word.
function directionMatch(sentence, label) {
  const sentenceTokens = new Set(tokenize(sentence).map(normalizeToken));
  const labelTokens = new Set(tokenize(label).map(normalizeToken));
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
// capability set. F4 (non-blocking, validation round 1): `pairSlugs` is
// applied here too, mirroring wave2Candidates below — without it, harvest
// kept re-offering a capability that a prior `write` had already paired
// (the intake doc itself stays `status: draft`, so nothing else ever
// retires it), which is the STEADY STATE after the very first write.
function intakeCandidates(docsDir, pairSlugs) {
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
    if (pairSlugs.has(fm.id)) continue;
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
//
// F2 (PR #399 Codex review, D18 amendment): readSpoolRowsDetailed's own
// `malformed` count is surfaced as a NOTE whenever it is non-zero — a spool
// that is PARTIALLY malformed used to get no note at all (the valid rows
// still made candidates, but nothing said any row had been skipped), and a
// spool that is ALL malformed used to reach the empty-spool branch below and
// describe a healthy read ("0 friction candidates", no different from a
// spool that was never written at all) for what is actually a corrupt one.
// Both cases now name the count, so friction observations that MIGHT be
// understated are never reported as if the read were complete.
function frictionCandidates(spoolPath, notes) {
  const { rows, malformed } = readSpoolRowsDetailed(spoolPath);
  if (malformed > 0) {
    notes.push(`${malformed} malformed friction spool line(s) skipped at ${spoolPath} — friction observations may therefore be UNDERSTATED`);
  }
  if (rows.length === 0) {
    notes.push(malformed > 0
      ? 'the friction spool has no readable rows — every non-blank line was malformed — 0 friction candidates'
      : 'the friction spool is empty or absent — 0 friction candidates');
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

// F1 (PR #399 Codex review, D18 amendment): `follow-ups.mjs list --json`
// SUCCEEDS over a ledger with malformed lines and says so in its own
// `parsed.notes` (an "EXCLUDED … the counts above may therefore be
// UNDERSTATED" line — see loadRegistry in follow-ups.mjs). This reader used
// to keep only `parsed.items` and throw the notes away, so `observations`
// could come out low with nothing anywhere to say so. Every note containing
// UNDERSTATED is now folded into the harvest's own `notes` (attributed to
// follow-ups so it reads distinctly from the friction/wave_2 sources below).
// A ledger that does not exist yet is the same lenient "no evidence" state
// every other harvest source treats an absent input as (D11/D12: no
// roadmap; frictionCandidates above: no spool) — follow-ups.mjs itself
// refuses (usage, exit 2) a missing ledger, and that refusal is swallowed
// here into an empty list exactly as before this amendment, never a note. A
// ledger that DOES exist but still could not be read (permissions, a
// directory, an unexpected crash) is a real degradation, not an empty
// project, and is now named rather than silently discarded.
function readFollowUps(ledgerPath, notes) {
  try {
    const raw = execFileSync(process.execPath, [FOLLOW_UPS_SCRIPT, 'list', '--ledger', ledgerPath, '--status', 'all', '--json'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    const parsed = JSON.parse(raw);
    for (const n of (parsed && Array.isArray(parsed.notes)) ? parsed.notes : []) {
      if (/UNDERSTATED/.test(n)) notes.push(`follow-ups: ${n}`);
    }
    return Array.isArray(parsed.items) ? parsed.items : [];
  } catch (e) {
    if (fs.existsSync(ledgerPath)) {
      notes.push(`follow-ups.mjs list --json could not be read at ${ledgerPath} — observations may therefore be UNDERSTATED (${e.message})`);
    }
    return [];
  }
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

// SOURCE_PRIORITY — the tie-break order for a merged candidate's OWN source
// field and for choosing which duplicate's label/path wins on an exact
// richness tie: intake (a real drafted doc) before wave_2 (a bare slug)
// before friction (a synthesized label), matching D8's own listing order.
const SOURCE_PRIORITY = { intake: 0, wave_2: 1, friction: 2 };

// richness(c) -> a comparable score for "which duplicate record is worth
// keeping": a candidate with a resolved doc path outranks one without (more
// can be measured from it — age_days is real, not "age unknown"), and among
// two with the same path-presence the one with the longer, more descriptive
// label wins (an intake candidate's `id # title` beats a wave_2 candidate's
// bare slug for the same id).
function richness(c) {
  return (c.path ? 1 : 0) * 1000 + c.label.length;
}

// mergeDuplicateCandidates(raw) -> raw with every duplicate `id` collapsed to
// ONE record — the live-corpus defect this closes: `decision-menu-options-parser`
// reached the printed menu twice, once `[intake]` (a draft doc) and once
// `[wave_2]` (the same slug, unpaired), because nothing here ever asked
// whether two sources named the SAME capability. The richest duplicate's
// label/path is kept (never silently dropped in favour of whichever source
// happened to run first), and `source` becomes every contributing source,
// comma-joined in SOURCE_PRIORITY order — "intake,wave_2" is disclosed
// signal (the owner sees a candidate came from two places), not noise.
// F3 (PR #399 Codex review, D18 amendment): `recurrence` lives ONLY on a raw
// friction candidate (frictionCandidates never sets it on an intake/wave_2
// row), and `richness()` ties whenever neither duplicate has a resolved doc
// path — which a friction row never does — so a friction id that collides
// with a wave_2 slug of equal label length keeps whichever raw record was
// inserted FIRST as `best` (wave_2, by SOURCE_PRIORITY's own listing order in
// rawAll) and silently drops the friction record's `recurrence` on the floor.
// `recurrence` is therefore folded across every duplicate HERE, independent
// of which raw record `best` ends up being, so the merged candidate always
// carries it forward when any contributing source is friction.
function mergeDuplicateCandidates(raw) {
  const byId = new Map();
  for (const c of raw) {
    const entry = byId.get(c.id);
    if (!entry) {
      byId.set(c.id, {
        best: c,
        sources: new Set([c.source]),
        recurrence: typeof c.recurrence === 'number' ? c.recurrence : null,
      });
      continue;
    }
    entry.sources.add(c.source);
    if (typeof c.recurrence === 'number') entry.recurrence = (entry.recurrence ?? 0) + c.recurrence;
    if (richness(c) > richness(entry.best)) entry.best = c;
  }
  return [...byId.values()].map(({ best, sources, recurrence }) => ({
    ...best,
    source: [...sources]
      .sort((x, y) => (SOURCE_PRIORITY[x] ?? 99) - (SOURCE_PRIORITY[y] ?? 99))
      .join(','),
    recurrence,
  }));
}

function evaluateCandidate(c, ctx) {
  const { direction, direction_tokens } = directionMatch(ctx.direction, c.label);
  let observations = openFollowUpCount(ctx.followUps, c.id);
  // F3 (PR #399 Codex review, D18 amendment): after mergeDuplicateCandidates
  // a friction-contributed id's `source` is a comma-joined list (e.g.
  // "wave_2,friction"), never the bare string "friction" — an exact-equality
  // check here skipped the recurrence bump for every friction candidate that
  // also collided with a wave_2 slug or intake draft, understating its
  // observations with no note anywhere.
  if (c.source.split(',').includes('friction') && typeof c.recurrence === 'number') observations += c.recurrence;
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
  const rawAll = [
    ...intakeCandidates(a.docs, roadmapInfo.pairSlugs),
    ...wave2Candidates(roadmapInfo, a.docs),
    ...frictionCandidates(a.spool, notes),
  ];
  const raw = mergeDuplicateCandidates(rawAll);
  const followUps = readFollowUps(a.ledger, notes);
  const repoRoot = findRepoRoot(a.docs);
  const ctx = { direction: a.direction, docsDir: a.docs, followUps, repoRoot };
  const candidates = raw.map((c) => evaluateCandidate(c, ctx));
  candidates.sort(compareCandidates);
  // BLOCKING-1 (validation round 1, F2): `write --pick <n>` takes a 1-based
  // INDEX into exactly this ranked order, and harvest used to print no
  // number at all — the owner had nothing to type. The index is stamped
  // onto the candidate record itself (not just the text formatter) so
  // --json carries it too, and so it is the SAME number cmdWrite's
  // parsePickList/selection logic (below) is keyed against — one source of
  // truth for "row N", never a formatter-only decoration a JSON consumer
  // could miss.
  candidates.forEach((c, i) => { c.index = i + 1; });
  return { candidates, notes };
}

function formatRow(c) {
  const tokens = c.direction_tokens.length ? c.direction_tokens.join(',') : 'none';
  const age = c.age_note ? `${c.age_days} (${c.age_note})` : String(c.age_days);
  return `${c.index}. ${c.id} [${c.source}] direction=${c.direction} (${tokens}) observations=${c.observations} blocks_in=${c.blocks_in} age_days=${age}`;
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

// --- write / bind: D10, D12, D13 --------------------------------------------
//
// certify(targetPath, docsDir) -> { ok, stderr } — D10's whole point: the
// appended roadmap is accepted or refused by the REAL `ride-select.mjs
// validate`, spawned as a child process, never a second copy of the roadmap
// parser. Resolved via RIDE_SELECT_SCRIPT (a sibling-of-this-file path), so
// a test that copies .aai/scripts/ elsewhere and drops an argv-recording
// shim in place of ride-select.mjs exercises exactly this call (TEST-739).
// docsDir is passed through as --docs so validate resolves refs against the
// SAME docs tree write/bind were given, never the live repo's docs/ by
// default.
function certify(targetPath, docsDir) {
  try {
    execFileSync(process.execPath, [RIDE_SELECT_SCRIPT, 'validate', '--roadmap', targetPath, '--docs', docsDir], { stdio: ['ignore', 'pipe', 'pipe'] });
    return { ok: true, stderr: '' };
  } catch (e) {
    const stderr = e.stderr ? e.stderr.toString('utf8') : String(e.message || e);
    return { ok: false, stderr };
  }
}

// rollback(target, original, existed) — a certification refusal restores the
// EXACT prior bytes when the file already existed, or removes the file this
// run created when it did not (D10, D13 both call this the same way).
function rollback(target, original, existed) {
  if (existed) {
    fs.writeFileSync(target, original);
  } else {
    try { fs.unlinkSync(target); } catch { /* nothing to remove */ }
  }
}

// formatAppendedPair(id) — the capability-only pair block write appends: no
// maintenance: line (D2 — the slot is unbound until bind), status PLANNED
// (a harvested candidate has not been picked up yet).
function formatAppendedPair(id) {
  return `  - capability: ${id}\n    status: planned\n`;
}

// parsePickList(raw, max) -> sorted, de-duplicated 1-based indices into the
// candidates array `harvest` itself prints (same ranked order) — usage error
// (exit 2), nothing written, on an out-of-range or duplicated pick.
function parsePickList(raw, max) {
  const parts = String(raw).split(',').map((s) => s.trim()).filter((s) => s !== '');
  if (!parts.length) usage(`--pick "${raw}" names no index`);
  const seen = new Set();
  const out = [];
  for (const p of parts) {
    if (!/^\d+$/.test(p)) usage(`--pick "${raw}" is not a comma-separated list of positive integers`);
    const n = Number(p);
    if (n < 1 || n > max) usage(`--pick ${n} is out of range — harvest returned ${max} candidate(s)`);
    if (seen.has(n)) usage(`--pick "${raw}" names ${n} twice`);
    seen.add(n);
    out.push(n);
  }
  return out;
}

// buildWriteContent(originalText, appendedBlock) -> the new roadmap text.
// originalText === null means no file existed yet (D12's own edge case: an
// absent roadmap gets the header/budget block created before the first
// pair). Otherwise the block is inserted immediately before the `wave_2:`
// section header when one exists (so the closed-shape parser still reads
// the appended lines as MORE pairs, not stray wave_2 entries), or appended
// at the true end of the file when there is none — every existing byte's
// VALUE is unchanged either way, only its position may shift.
function buildWriteContent(originalText, appendedBlock) {
  if (originalText === null) {
    return `budget:\n  maintenance_per_capability: 1\npairs:\n${appendedBlock}`;
  }
  const m = /^wave_2:[ \t]*$/m.exec(originalText);
  if (!m) {
    const sep = originalText.endsWith('\n') ? '' : '\n';
    return `${originalText}${sep}${appendedBlock}`;
  }
  return originalText.slice(0, m.index) + appendedBlock + originalText.slice(m.index);
}

// removeWave2Entries(text, ids) -> text with any `  - <id>` line inside the
// wave_2: section removed, for every id in `ids`. D10 amendment (post-freeze,
// run 3): a picked candidate sourced (wholly or partly) from wave_2 is being
// PROMOTED into a real pair, and leaving its old wave_2 listing in place
// makes the SAME ref appear in both `pairs` and `wave_2` — the closed-shape
// validator refuses that as a duplicate ref. Measured live-corpus defect:
// `write --pick` against a scratch copy of the shipped roadmap, promoting
// `standardized-backlog-drain` (a wave_2 slug), reddened
// `wave_2: "standardized-backlog-drain" appears twice in the roadmap` —
// found by running against the LIVE corpus, not by this ride's own fixtures.
// This narrows Spec-AC-12's "every pre-existing byte is unchanged" to the
// PREFIX the AC's own verification actually checks (`head -n <N>`, which
// never reaches the wave_2 section that follows the pairs list); the wave_2
// TAIL may legitimately lose exactly the promoted slug's own line. See
// spec_amendment (docs/ai/decisions.jsonl, ref roadmap-takes-direction).
function removeWave2Entries(text, ids) {
  if (!ids.size) return text;
  const lines = text.split('\n');
  const out = [];
  let section = null;
  for (const line of lines) {
    const m = /^([a-z_0-9]+):\s*$/.exec(line);
    if (m) { section = m[1]; out.push(line); continue; }
    if (section === 'wave_2') {
      const wm = /^  - (.+?)\s*$/.exec(line);
      if (wm && ids.has(wm[1])) continue;
    }
    out.push(line);
  }
  return out.join('\n');
}

// F1 (validation round 1) asks whether `write`/`bind` should append an
// EVENTS.jsonl line the way `gate --override` does. Decision: NO, and here
// is why. `--override` bypasses a REFUSAL — its only trace, absent an
// EVENTS line, would be the ride that follows it; the owner has no other way
// to COUNT how often the gate's own judgment was overruled. `write` and
// `bind` are the opposite shape: they are not a bypass of anything, they are
// THE way this scope's whole feature is meant to be used, and their effect
// is a byte-diffable change to docs/ai/roadmap.yaml itself — a tracked file
// under normal code review (D1's rationale: this stays a sibling script
// precisely so the shared roadmap keeps being reviewed like any other
// change). An EVENTS line here would duplicate strictly less information
// than `git log -p -- docs/ai/roadmap.yaml` already carries (who, when, and
// the padded ranking rationale printed to stdout, none of which EVENTS'
// single-line JSON shape has room for), while adding a second success path
// that certify()/rollback() would have to keep in lock-step (an EVENTS
// append that survives a rolled-back write would be a false positive worse
// than the silence F1 found). If this changes — e.g. bind starts mutating a
// SHARED roadmap outside of a reviewed PR — it should gain its own Spec-AC
// and mutation-pinned test, not a bolt-on here.
function cmdWrite(a) {
  const { candidates } = buildCandidates(a);
  if (!candidates.length) refuse('nothing harvested');
  const picks = parsePickList(a.pick, candidates.length);
  const selected = picks.map((i) => candidates[i - 1]);

  const existed = fs.existsSync(a.roadmap);
  const original = existed ? fs.readFileSync(a.roadmap, 'utf8') : null;
  const promotedFromWave2 = new Set(
    selected.filter((c) => c.source.split(',').includes('wave_2')).map((c) => c.id)
  );
  const baseText = original === null ? null : removeWave2Entries(original, promotedFromWave2);
  const appendedBlock = selected.map((c) => formatAppendedPair(c.id)).join('');
  const newContent = buildWriteContent(baseText, appendedBlock);
  fs.mkdirSync(path.dirname(a.roadmap), { recursive: true });
  fs.writeFileSync(a.roadmap, newContent);

  const cert = certify(a.roadmap, a.docs);
  if (!cert.ok) {
    rollback(a.roadmap, original, existed);
    process.stderr.write(cert.stderr);
    refuse(`the appended roadmap did not validate — original bytes restored (${a.roadmap})`);
  }
  // F7 (non-blocking, validation round 1): writing into a project that had NO
  // docs/ai/roadmap.yaml yet (D12's own edge case) CREATES one — and
  // orchestration-dispatch.mjs's roadmapGate() reads "file present" as
  // "consult the gate" (D11: "a project with no docs/ai/roadmap.yaml sees no
  // file, no gate ... exactly as today"). That is a real, intended
  // side-effect (the whole point of `write`), but the success line used to
  // say nothing about it, so an owner who ran `write` once could be
  // surprised every ride afterwards. Disclosed on the one line this run
  // prints, only when it is actually true (`!existed`).
  const gateNote = existed ? '' : ` — this project had no roadmap: the ride gate is now ON for every ride from here (${a.roadmap})`;
  process.stdout.write(`wrote ${selected.length} capability pair(s) to ${a.roadmap}: ${selected.map((c) => c.id).join(', ')}${gateNote}\n`);
  process.exit(0);
}

// readPairsForBind(text) -> [{ capability, maintenance, lineIndex }] — a
// read-only, best-effort locator (same precedent as readWave2AndPairSlugs
// above): it finds WHERE a pair's capability line sits and whether a
// maintenance: line already follows it, never validates the roadmap's shape
// (D10's certify() after the edit is the one authority for that).
function readPairsForBind(text) {
  const lines = text.split('\n');
  const pairs = [];
  let cur = null;
  let section = null;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    let m;
    if ((m = /^([a-z_0-9]+):\s*$/.exec(line))) { section = m[1]; cur = null; continue; }
    if (section !== 'pairs') continue;
    if ((m = /^  - capability:\s*(.+?)\s*$/.exec(line))) {
      cur = { capability: m[1], maintenance: null, lineIndex: i };
      pairs.push(cur);
      continue;
    }
    if (cur && (m = /^    maintenance:\s*(.+?)\s*$/.exec(line))) { cur.maintenance = m[1]; continue; }
  }
  return pairs;
}

// resolveDoc(docsDir, id) -> { path, type } for a document whose frontmatter
// id matches, or null — the same walk+parseFrontmatter authority the harvest
// sources above already use, never a second frontmatter parser. Carries
// `type` (not just the path) so cmdBind's CAPABILITY_TYPES check below can
// classify the resolved document without a second walk of the tree.
function resolveDoc(docsDir, id) {
  for (const p of walk(docsDir)) {
    let content;
    try { content = fs.readFileSync(p, 'utf8'); } catch { continue; }
    const fm = parseFrontmatter(content);
    if (fm && fm.id === id) return { path: p, type: fm.type || null };
  }
  return null;
}

function cmdBind(a) {
  let text;
  try { text = fs.readFileSync(a.roadmap, 'utf8'); } catch { return refuse(`roadmap not readable: ${a.roadmap}`); }
  const pairs = readPairsForBind(text);
  const pair = pairs.find((p) => p.capability === a.capability);
  if (!pair) refuse(`"${a.capability}" is not a capability pair in ${a.roadmap}`);
  if (pair.maintenance !== null) refuse(`"${a.capability}"'s maintenance slot is already bound to "${pair.maintenance}"`);

  // D13: the ref must come from the backlog — either an OPEN follow-up id,
  // or a document that resolves under --docs.
  const followUps = readFollowUps(a.ledger);
  const openIds = new Set(followUps.filter((it) => it.status === 'open').map((it) => it.id));
  const doc = resolveDoc(a.docs, a.ref);
  if (!openIds.has(a.ref) && !doc) {
    refuse(`"${a.ref}" is neither an open follow-up id in ${a.ledger} nor a resolvable document under ${a.docs}`);
  }
  // BLOCKING-2 (validation round 1, F1) / B1+B2 (validation round 2): D13
  // proved only that the ref comes "from the backlog" — it never asked
  // whether the ref is ITSELF already a roadmap capability. Round 1's fix
  // asked the wrong question (a document `type:` check) and validation
  // round 2 measured it against the owner's own data: 8 of the 11
  // maintenance halves on the SHIPPED roadmap are `type: change` documents
  // (the CAPABILITY_TYPES set's own majority member), so that check refused
  // the commonest real shape in this repo (B1); and the check was a 5-value
  // denylist over an open set — 197 live doc ids outside both
  // CAPABILITY_TYPES and ride-select.mjs's own MAINT_TYPES, a trailing YAML
  // comment on the type line, or a typeless intake all defeated it outright
  // (B2). `type:` is not where this factory records the capability/
  // maintenance distinction — the ROADMAP is: a slug is a capability because
  // the OWNER put it in a `capability:` slot. Refuse a ref that already
  // holds one of those slots, read from the very pairs `readPairsForBind`
  // just parsed — a closed set drawn from the file `gate` itself reads, not
  // a guess about an intake's frontmatter. This also fixes NB-4 (the old
  // check's answer depended on `resolveDoc`'s first-walk-match order for a
  // duplicated id): the decision no longer consults `doc.type` at all, so
  // which of two same-id documents `resolveDoc` happens to return can no
  // longer change it.
  const roadmapCapabilities = new Set(pairs.map((p) => p.capability));
  if (roadmapCapabilities.has(a.ref)) {
    refuse(`"${a.ref}" is already a roadmap CAPABILITY (${a.roadmap}) — bind only accepts a MAINTENANCE ref, and a ref already ranked as a capability cannot also be bound as another capability's maintenance half: it would consume the 1:1 budget slot without ever being ranked (mirrors D8's exclusion on the intake side, decided by the roadmap itself rather than by document type)`);
  }
  // Also refuse a ref already bound as some OTHER pair's maintenance half:
  // the same ref serving two capabilities at once defeats the 1:1 budget
  // exactly as a duplicate roadmap ref would (ride-select.mjs's own
  // loadRoadmap refuses that as "appears twice in the roadmap" — certify()
  // below would catch it too, but bind names the reason itself here rather
  // than surfacing the roadmap parser's generic duplicate-ref error).
  const boundElsewhere = pairs.find((p) => p.maintenance === a.ref);
  if (boundElsewhere) {
    refuse(`"${a.ref}" is already bound as the maintenance half of "${boundElsewhere.capability}" (${a.roadmap}) — one ref cannot serve two capabilities under the 1:1 budget`);
  }

  const lines = text.split('\n');
  lines.splice(pair.lineIndex + 1, 0, `    maintenance: ${a.ref}`);
  const newContent = lines.join('\n');
  fs.writeFileSync(a.roadmap, newContent);

  const cert = certify(a.roadmap, a.docs);
  if (!cert.ok) {
    rollback(a.roadmap, text, true);
    process.stderr.write(cert.stderr);
    refuse(`the bound roadmap did not validate — original bytes restored (${a.roadmap})`);
  }
  process.stdout.write(`bound ${a.ref} as the maintenance half of ${a.capability}\n`);
  process.exit(0);
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  if (a.cmd === 'harvest') return cmdHarvest(a);
  if (a.cmd === 'write') return cmdWrite(a);
  if (a.cmd === 'bind') return cmdBind(a);
  usage(`unknown command ${a.cmd}`);
}

main();
