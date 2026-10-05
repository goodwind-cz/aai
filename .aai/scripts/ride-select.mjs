#!/usr/bin/env node
// ride-select.mjs — rides come from docs/ai/roadmap.yaml, and every maintenance
// ride is paired with a capability. SPEC roadmap-driven-ride-selection-with-budget.
//
// Owner decisions (hitl_decision, 2026-09-05): capability-roadmap-drives-rides,
// maintenance-budget-one-to-one, internal-work-without-asking, review-round-cap.
//
//   node .aai/scripts/ride-select.mjs validate [--roadmap <p>]
//   node .aai/scripts/ride-select.mjs next     [--roadmap <p>] [--docs <dir>] [--json]
//        [--ledger <p>] [--events <p>]   (advisory posture only; D3..D7)
//   node .aai/scripts/ride-select.mjs gate --ref <slug> [--intake <path>] [--roadmap <p>]
//        [--docs <dir>] [--events <p>] [--override "<reason>"]
//   node .aai/scripts/ride-select.mjs show     [--roadmap <p>] [--docs <dir>] [--json]
//   node .aai/scripts/ride-select.mjs waiting  [--docs <dir>] [--ledger <p>] [--json]
//        (D8: read-only, needs no roadmap, works in every posture)
//
// The roadmap FILE is the posture switch. gate with NO roadmap file (absent path)
// ADMITS with one line, "roadmap absent ... not consulted", writing nothing:
// ungoverned downstream projects ride freely. A roadmap that is PRESENT but
// unreadable or invalid REFUSES. With a roadmap, DENY BY DEFAULT: gate exits 0
// only when the ref may start now; every refusal names ONE reason and its
// remedy. Exit: 0 admit · 1 refuse · 2 usage/invalid (validate/next unchanged).
// The maintenance budget has three postures: off (no `budget:` key, no 1:1
// pairing, no ranked refusals), on (1:1 pairing) and advisory (`next`
// PROPOSES a maintenance ride on a threshold or related trigger but never
// binds, and `gate` behaves exactly like off — SPEC
// roadmap-maintenance-budget-advisory D2/D5/D9); `show` prints which posture
// a roadmap is in.
//
// Roadmap shape is CLOSED (see docs/ai/roadmap.yaml header); a line-level
// parser for exactly that shape, no YAML library, anything else is invalid.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { parseFrontmatter, DOC_TYPE_ENUM, TERMINAL_DOC_STATUS } from './lib/docs-model.mjs';
import { SLUG, MAINT_TYPES, roadmapAbsent, loadRoadmap } from './lib/roadmap-model.mjs';
import { loadRegistry } from './follow-ups.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const STARTED = new Set(['implementing', 'done']);
// Words in a slug that mark maintenance when the intake type does not already.
const MAINT_WORDS = /(^|-)(fix|guard|harness|hygiene|tripwire|flake|refactor|cleanup|lint|chore|test|ci)(-|$)/;

// --- advisory maintenance budget (SPEC roadmap-maintenance-budget-advisory,
// D3..D6) — the roadmap PROPOSES maintenance, never requires it. These
// constants and functions are read-only: waitingMaintenance never writes the
// decisions ledger, lastClosedCapability never writes EVENTS.
const WAITING_SEVERITIES = new Set(['P1', 'P2']);
const OPEN_INTAKE_TYPES = new Set(['issue', 'techdebt']);
// D3's closed-status vocabulary (done/deferred/rejected/superseded) is the
// SAME literal lib/docs-model.mjs already owns as TERMINAL_DOC_STATUS
// (test-aai-golden-flow.sh TEST-008 pins that exact comma-separated literal
// to exactly one file, as a forked-canon guard) — restamp, measurement-class,
// disclosed in docs/ai/decisions.jsonl: a locally-declared CLOSED_INTAKE_
// STATUSES set would have reintroduced the fork TEST-008 exists to catch.
// TERMINAL_DOC_STATUS is a superset (adds 'legacy'/'current', vocabulary
// issue/techdebt intakes never carry), so behavior for D3's own cases is
// unchanged.
function openIntakes(docsDir) {
  const dir = path.join(docsDir, 'issues');
  let names; try { names = fs.readdirSync(dir); } catch { return []; }
  const out = [];
  for (const n of names) {
    if (!n.endsWith('.md')) continue;
    const p = path.join(dir, n);
    let content; try { content = fs.readFileSync(p, 'utf8'); } catch { continue; }
    const fm = parseFrontmatter(content);
    if (!fm || !OPEN_INTAKE_TYPES.has(fm.type)) continue;
    const status = fm.status || null;
    if (status !== null && TERMINAL_DOC_STATUS.has(status)) continue;
    out.push({ kind: 'intake', id: fm.id, type: fm.type, status, path: p });
  }
  out.sort((a, b) => (a.id < b.id ? -1 : (a.id > b.id ? 1 : 0)));
  return out;
}

// D3 — waiting maintenance (W): open P1/P2 follow-ups (read-only fold over
// --ledger) plus open issue/techdebt intakes. P3 never counts; a follow-up
// with a missing/unknown severity never counts (WAITING_SEVERITIES.has is
// false for both). An unreadable ledger (not ENOENT) is reported, never
// silently folded into "empty" (D7); an absent ledger IS an empty registry
// (intakes still count).
function waitingMaintenance(docsDir, ledgerPath) {
  const reg = loadRegistry(ledgerPath);
  if (reg.unreadable) return { unreadable: reg.unreadable, count: 0, followUps: [], intakes: [] };
  const followUps = reg.items.filter((i) => !i.closed && WAITING_SEVERITIES.has(i.severity));
  const intakes = openIntakes(docsDir);
  return { unreadable: null, count: followUps.length + intakes.length, followUps, intakes };
}

// D4 — most recently closed capability (C). Among the roadmap's pair
// capabilities, the one with the latest `ts` of a `work_item_closed` record
// in --events whose `ref` equals the capability EXACTLY (a `spec-<slug>` ref
// never matches, by construction of the exact-equality lookup below); a tie
// goes to the pair listed later in the roadmap (the tie-break index below
// compares ROADMAP PAIR POSITION, not event line order). Falls back to the
// last `done` pair in roadmap order when no pair capability has such a
// record (or the events file is absent/unreadable/malformed-only). Returns
// null — not an object with null fields — when C cannot be decided at all,
// so a caller can write `closed ? ... : fallback` instead of null-checking
// capability on every read.
function lastClosedCapability(rm, eventsPath) {
  let raw; try { raw = fs.readFileSync(eventsPath, 'utf8'); } catch { raw = ''; }
  const closedTs = new Map();
  for (const line of raw.split(/\r?\n/)) {
    const t0 = line.trim();
    if (t0 === '') continue;
    let rec; try { rec = JSON.parse(t0); } catch { continue; }
    if (!rec || rec.event !== 'work_item_closed' || typeof rec.ref !== 'string' || typeof rec.ts !== 'string') continue;
    const t = Date.parse(rec.ts);
    if (Number.isNaN(t)) continue;
    const prev = closedTs.get(rec.ref);
    if (prev === undefined || t > prev) closedTs.set(rec.ref, t);
  }
  let best = null;
  for (const [i, pr] of rm.pairs.entries()) {
    const t = closedTs.get(pr.capability);
    if (t === undefined) continue;
    if (!best || t > best.t || (t === best.t && i > best.i)) best = { cap: pr.capability, t, i };
  }
  if (best) return { capability: best.cap, source: 'events' };
  const done = rm.pairs.filter((p) => p.status === 'done');
  if (done.length) return { capability: done[done.length - 1].capability, source: 'roadmap_order' };
  return null;
}

// D5 — triggers. `related` wins over `threshold` when both fire (the more
// specific reason). `closed` is the lastClosedCapability() result (null or
// { capability, source }).
function adviseMaintenance(rm, w, closed) {
  const related = closed ? w.followUps.filter((f) => f.ref_id === closed.capability) : [];
  const thresholdFired = w.count >= rm.advisory.maintenance_threshold;
  const reason = related.length ? 'related' : (thresholdFired ? 'threshold' : null);
  return { reason, related, thresholdFired };
}

function followUpCandidate(f) {
  return { kind: 'follow_up', id: f.id, severity: f.severity, ref: f.ref_id, finding: f.finding };
}
function intakeCandidate(it) {
  return { kind: 'intake', id: it.id, type: it.type, status: it.status, path: it.path };
}
// D6 — candidate ordering: P1 follow-ups, then P2 follow-ups (each in the
// fold's own order — oldest first, id tiebreak, since Array#sort is stable
// and w.followUps/related already carry that order from loadRegistry), then
// intakes (already id-ordered by openIntakes). Capped at CANDIDATE_CAP.
const SEVERITY_RANK = { P1: 0, P2: 1 };
const CANDIDATE_CAP = 5;
// D6 — candidates: for `related`, only the related follow-ups; for
// `threshold`, every counted item.
function buildCandidates(reason, related, w) {
  const followUps = reason === 'related' ? related : w.followUps;
  const rankedFollowUps = [...followUps].sort((a, b) => SEVERITY_RANK[a.severity] - SEVERITY_RANK[b.severity]);
  const items = reason === 'related'
    ? rankedFollowUps.map(followUpCandidate)
    : [...rankedFollowUps.map(followUpCandidate), ...w.intakes.map(intakeCandidate)];
  return items.slice(0, CANDIDATE_CAP);
}

function usage(msg) { process.stderr.write(`ride-select: ${msg}\n`); process.exit(2); }
function refuse(msg) { process.stderr.write(`ride-select: REFUSED — ${msg}\n`); process.exit(1); }

function parseArgs(argv) {
  const a = { cmd: argv[0], roadmap: path.join(ROOT, 'docs/ai/roadmap.yaml'), docs: path.join(ROOT, 'docs'), events: path.join(ROOT, 'docs/ai/EVENTS.jsonl'), ledger: path.join(ROOT, 'docs/ai/decisions.jsonl'), ref: null, intake: null, override: null, json: false };
  const need = (k, v) => { if (v === undefined || v.startsWith('--')) usage(`${k} requires a value`); return v; };
  for (let i = 1; i < argv.length; i += 1) {
    const k = argv[i]; const v = argv[i + 1];
    if (k === '--roadmap') { a.roadmap = need(k, v); i += 1; }
    else if (k === '--docs') { a.docs = need(k, v); i += 1; }
    else if (k === '--events') { a.events = need(k, v); i += 1; }
    else if (k === '--ledger') { a.ledger = need(k, v); i += 1; }
    else if (k === '--ref') { a.ref = need(k, v); i += 1; }
    else if (k === '--intake') { a.intake = need(k, v); i += 1; }
    else if (k === '--override') { a.override = need(k, v); i += 1; }
    else if (k === '--json') { a.json = true; }
    else usage(`unknown argument ${k}`);
  }
  if (!['validate', 'next', 'gate', 'show', 'waiting'].includes(a.cmd)) usage('usage: ride-select.mjs <validate|next|gate|show|waiting> [flags]');
  return a;
}

// --- doc status by frontmatter id, from the docs tree ----------------------------
function findDoc(docsDir, ref) {
  const dirs = ['issues', 'specs', 'rfc', 'releases', 'requirements'].map((d) => path.join(docsDir, d));
  for (const d of dirs) {
    let names; try { names = fs.readdirSync(d); } catch { continue; }
    for (const n of names) {
      if (!n.endsWith('.md')) continue;
      const p = path.join(d, n);
      let head; try { head = fs.readFileSync(p, 'utf8').split('\n').slice(0, 30); } catch { continue; }
      const idLine = head.find((l) => /^id:\s*/.test(l));
      if (!idLine || idLine.replace(/^id:\s*/, '').trim() !== ref) continue;
      const fm = {};
      for (const l of head) { const m = /^([a-z_]+):\s*(.*)$/.exec(l); if (m) fm[m[1]] = m[2].trim(); }
      return { path: p, status: fm.status || null, type: fm.type || null, blocks: fm.blocks || null };
    }
  }
  return null;
}
function readIntake(p) {
  let content; try { content = fs.readFileSync(p, 'utf8'); } catch { return null; }
  // NB-3 (validation-round2): "resolves to a real document" must mean the
  // file PARSES as an intake document -- frontmatter carrying an id AND a
  // type the corpus type map recognizes -- not merely "the file is
  // readable". `gate --intake junk.txt` was admitting because readIntake
  // returned an object for ANY readable file, and the id-mismatch usage
  // error only fires when the file HAS an `id:` line. Uses the SAME
  // frontmatter authority docs-audit already reads with (lib/docs-model.mjs
  // parseFrontmatter + DOC_TYPE_ENUM), never a second parser: a junk file
  // with no frontmatter, or an id with no recognized type, is not a
  // document, so readIntake returns null exactly like a findDoc() miss and
  // gate's `if (!intake) return deny(...)` (Spec-AC-29) covers it too.
  const fm = parseFrontmatter(content);
  if (!fm || !fm.id || !fm.type || !DOC_TYPE_ENUM.has(fm.type)) return null;
  const head = content.split('\n').slice(0, 30);
  const title = (head.find((l) => /^# /.test(l)) || '').replace(/^# /, '');
  return { path: p, id: fm.id, status: fm.status || null, type: fm.type, blocks: fm.blocks || null, title };
}
function statusOf(docsDir, ref) { const d = findDoc(docsDir, ref); return d ? d.status : null; }

// --- next -------------------------------------------------------------------------
// D13 command text lives here too (D4/D5), so nextRide and gate's off-roadmap
// refusal (below) never drift on the exact command an owner is told to run.
function bindCommand(capability) {
  return `node .aai/scripts/roadmap-propose.mjs bind --capability ${capability} --ref <maintenance-ref>`;
}
function nextRide(rm, docsDir) {
  for (const pr of rm.pairs) {
    if (pr.status === 'done') continue;
    const cs = statusOf(docsDir, pr.capability);
    // D2: the capability comes first UNLESS it has already started; proposing a
    // ride that is already implementing is proposing to start it twice.
    if (!STARTED.has(cs || '')) {
      // NB-1 (validation round 3): the SAME livelock NB-6/D16 closed on the
      // maintenance half (below) was still open here — this ride's own
      // `write` promotes a wave_2 or friction candidate straight into a
      // pair's `capability:` slot with no document filed yet far more often
      // than it binds a documentless maintenance ref, so this was the FIRST
      // thing an owner met, not a rare edge. Same resolution authority
      // (findDoc) gate's off-roadmap check already uses, so `next` and
      // `gate` never disagree about what "resolves" means.
      const cdoc = findDoc(docsDir, pr.capability);
      if (!cdoc) {
        return { action: 'file-intake', ref: pr.capability, capability: pr.capability, half: 'capability', pair: pr };
      }
      return { ref: pr.capability, half: 'capability', pair: pr, path: cdoc.path };
    }
    // D4: a started capability whose maintenance slot is UNBOUND (no
    // `maintenance:` line) used to fall through to `statusOf(docs, null)` and
    // return `{ ref: null }` — a latent defect the D2 relaxation activates.
    // Propose the bind instead of ever emitting a null/empty ref.
    if (pr.maintenance === null) {
      return { action: 'bind', capability: pr.capability, command: bindCommand(pr.capability), pair: pr };
    }
    // NB-6 (validation round 2): a maintenance ref bound from an open
    // follow-up id (D13's first backlog arm) has no DOCUMENT under --docs to
    // resolve to until an intake is filed for it. Proposing it as `next`
    // anyway hands an autonomous loop a ref `gate` immediately refuses ("no
    // document resolves for ..."), forever — a LIVELOCK, not merely an
    // un-closeable pair (R7 described the refusal but not this). Use the
    // SAME resolution authority `gate`'s own off-roadmap check already uses
    // (findDoc) so `next` and `gate` never disagree about what "resolves"
    // means, and propose filing the intake instead of a ref nothing can act
    // on.
    const mdoc = findDoc(docsDir, pr.maintenance);
    if (!mdoc) {
      return { action: 'file-intake', ref: pr.maintenance, capability: pr.capability, half: 'maintenance', pair: pr };
    }
    if (mdoc.status !== 'done') return { ref: pr.maintenance, half: 'maintenance', pair: pr, path: mdoc.path };
  }
  return null;
}
// D7 — without a budget the roadmap is an ordered capability list: skip a done
// pair and a pair whose capability DOCUMENT is done (a hand-run close that never
// flipped the pair), name a capability with no document as file-intake, and
// otherwise name the capability — also while it is already implementing. Never
// a bind, never a maintenance half.
function nextNoBudget(rm, docsDir) {
  for (const pr of rm.pairs) {
    if (pr.status === 'done') continue;
    const doc = findDoc(docsDir, pr.capability);
    const capStatus = doc ? doc.status : null;
    if (capStatus === 'done') continue;
    if (!doc) return { action: 'file-intake', ref: pr.capability, capability: pr.capability, half: 'capability', pair: pr };
    return { ref: pr.capability, half: 'capability', pair: pr, path: doc.path };
  }
  return null;
}
function pickNext(rm, docsDir) {
  if (!rm.budget) return nextNoBudget(rm, docsDir);
  return nextRide(rm, docsDir);
}

// --- gate --------------------------------------------------------------------------
// isFirstUnfinished (CHANGE-0184 / Spec-AC-29) — the roadmap's ranking is
// enforced HERE, not merely documented: a pair is admissible only when it is
// the FIRST pair, in roadmap order, whose OWN roadmap-level status is not
// "done". Walks pairs in order; the first not-done pair encountered decides
// the answer for every pair (true for itself, false for every later one).
function isFirstUnfinished(pair, roadmap) {
  for (const p of roadmap.pairs) {
    if (p.status !== 'done') return p === pair;
  }
  return false;
}
function isMaintenance(ref, intake) {
  if (intake && intake.type && MAINT_TYPES.has(intake.type)) return true;
  if (intake && intake.title && /\b(fix|guard|harness|hygiene|tripwire|flake|refactor|cleanup|lint)\b/i.test(intake.title)) return true;
  return MAINT_WORDS.test(ref);
}
// House shape of docs/ai/EVENTS.jsonl records (append-event.mjs): actor is the
// git identity slug, never a role word. append-event.mjs itself has a CLOSED
// event set and no ledger-path flag, so the record is written here in the same
// shape rather than by widening that set.
function actorSlug() {
  try {
    const email = execFileSync('git', ['config', 'user.email'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return email.toLowerCase().replace(/[^a-z0-9._-]+/g, '_') || 'unknown';   // exactly append-event.mjs actorSlug()
  } catch { /* fall through */ }
  return 'unknown';
}
function appendOverride(eventsPath, ref, reason) {
  const rec = { v: 1, ts: new Date().toISOString(), actor: actorSlug(), event: 'ride_gate_override', ref, payload: { reason } };
  fs.mkdirSync(path.dirname(eventsPath), { recursive: true });
  fs.appendFileSync(eventsPath, `${JSON.stringify(rec)}\n`);
}

// noBudgetGate (D3) — no `budget:` block: the roadmap ORDER drives `next`, not a
// refusal of an explicitly requested ride. Refuse a ref in a done pair and a ref
// that resolves to no document; admit everything else. (A ref whose own document
// is done was refused by the caller before this point.)
function noBudgetGate(ctx) {
  const { a, pair } = ctx;
  if (pair && pair.status === 'done') return ctx.deny(`${a.ref} belongs to a pair already marked done in the roadmap`);
  if (!ctx.intake) return ctx.deny(`no document resolves for "${a.ref}" under ${a.docs} — file its intake before gating this ref (gate admits only refs that exist)`);
  return ctx.admit(`${pair ? 'a roadmap item' : 'off the roadmap'}; no maintenance budget, so roadmap order does not gate a requested ride`);
}

// show — read-only view of the roadmap posture (D12). Absent = one line, exit 0.
function nextView(n) {
  if (!n) return null;
  const v = {};
  for (const k of ['action', 'ref', 'half', 'capability', 'path']) if (n[k] !== undefined) v[k] = n[k];
  return v;
}
function cmdShow(a, loaded) {
  if (roadmapAbsent(a.roadmap)) {
    process.stdout.write(a.json ? JSON.stringify({ roadmap: null, note: 'no roadmap' }) + '\n' : `no roadmap (${a.roadmap}) — rides are not gated\n`);
    process.exit(0);
  }
  if (loaded.error) usage(`invalid roadmap ${a.roadmap}: ${loaded.error}`);
  const rm = loaded.roadmap;
  const n = pickNext(rm, a.docs);
  if (a.json) {
    // D9: the advisory key is inserted right after `budget` only when the
    // roadmap IS advisory — on/off keep the exact shape they always had.
    const payload = { roadmap: a.roadmap, budget: Boolean(rm.budget) };
    if (rm.advisory) payload.advisory = { maintenance_threshold: rm.advisory.maintenance_threshold };
    payload.next = nextView(n);
    payload.pairs = rm.pairs;
    payload.wave_2 = rm.wave_2;
    process.stdout.write(JSON.stringify(payload) + '\n');
    process.exit(0);
  }
  const open = rm.pairs.filter((p) => p.status !== 'done');
  const lines = [
    rm.budget
      ? 'maintenance budget: on'
      : (rm.advisory ? `maintenance budget: advisory (threshold ${rm.advisory.maintenance_threshold})` : 'maintenance budget: off'),
    `next: ${n ? (n.action ? `${n.action} ${n.ref || n.capability}` : n.ref) : 'none (wave 1 complete)'}`,
    `done: ${rm.pairs.length - open.length} of ${rm.pairs.length}`,
    `planned/active: ${open.map((p) => `${p.capability} (${p.status})`).join(', ') || 'none'}`,
    `wave 2: ${rm.wave_2.join(', ') || 'none'}`,
  ];
  process.stdout.write(`${lines.join('\n')}\n`);
  process.exit(0);
}

// D8 — `waiting`: a read-only query over the SAME waitingMaintenance() the
// advisory `next` branch uses, so the two can never disagree about W. Needs
// no roadmap (works in every posture, and with none at all); writes nothing.
// recommended_threshold is "five more than are waiting today", so advisory
// does not fire on the very first call over an existing backlog.
function cmdWaiting(a) {
  const w = waitingMaintenance(a.docs, a.ledger);
  if (w.unreadable) usage(`ledger not readable: ${a.ledger} (${w.unreadable.code}: ${w.unreadable.message})`);
  const p1 = w.followUps.filter((f) => f.severity === 'P1').length;
  const p2 = w.followUps.filter((f) => f.severity === 'P2').length;
  const issue = w.intakes.filter((i) => i.type === 'issue').length;
  const techdebt = w.intakes.filter((i) => i.type === 'techdebt').length;
  const recommended_threshold = Math.max(5, w.count + 5);
  if (a.json) {
    process.stdout.write(`${JSON.stringify({ count: w.count, follow_ups: { P1: p1, P2: p2 }, intakes: { issue, techdebt }, recommended_threshold })}\n`);
  } else {
    process.stdout.write(`waiting maintenance: ${w.count} (follow-ups P1 ${p1}, P2 ${p2}; intakes issue ${issue}, techdebt ${techdebt}) — recommended threshold ${recommended_threshold}\n`);
  }
  process.exit(0);
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  if (a.cmd === 'waiting') cmdWaiting(a);
  const loaded = loadRoadmap(a.roadmap);
  if (a.cmd === 'show') cmdShow(a, loaded);

  if (a.cmd === 'validate') {
    if (loaded.error) usage(`invalid roadmap ${a.roadmap}: ${loaded.error}`);
    // A STARTED pair (active/done) names refs that must already be real
    // documents; a still-planned pair may legitimately be named ahead of its
    // own intake, so it is exempt (fu-ride-select-validate-ref-exists).
    // DISCLOSED narrowing of Spec-AC-29's literal text (which states no
    // status carve-out): the live docs/ai/roadmap.yaml names two planned
    // capabilities (friction-channel-sweep, canon-is-a-build-artifact) with
    // no document yet — the roadmap's whole purpose is to name future work
    // ahead of intake (wave_2 is the same shape, entirely unvalidated), so
    // requiring a document before a pair even starts would force a stub
    // intake to be filed for no reason but to satisfy this gate. RESIDUAL
    // RISK (spec Amendment 16, R6), NOT mitigated elsewhere: a typo in a
    // still-planned pair's slug is caught by neither this check nor `gate`
    // below — `gate`'s own capability-admission arm
    // (`if (pair.capability === a.ref) return admit(...)`) matches by
    // STRING EQUALITY against the roadmap's own text, so a slug that is
    // internally consistent but never resolves to a document is admitted
    // once its pair becomes first-unfinished, exactly like a correctly
    // spelled one. The typo is only caught downstream, when Planning/intake
    // cannot find a document to work from. Reported, not fixed here — out
    // of Spec-AC-29's own `validate` scope.
    for (const [i, pr] of loaded.roadmap.pairs.entries()) {
      if (pr.status === 'planned') continue;
      for (const ref of [pr.capability, pr.maintenance]) {
        // Spec-AC-01/D2: an unbound maintenance slot (no `maintenance:` line)
        // has nothing to resolve yet — binding happens later, at ride time,
        // from the backlog (D3). Skip the document-existence check for that
        // slot alone; the capability half of the SAME pair is still checked.
        if (ref === null) continue;
        if (!findDoc(a.docs, ref)) usage(`pair ${i + 1} (${pr.capability}): "${ref}" matches no document id under ${a.docs}`);
      }
    }
    process.stdout.write(`roadmap OK: ${loaded.roadmap.pairs.length} pair(s), ${loaded.roadmap.wave_2.length} wave-2 item(s)\n`);
    process.exit(0);
  }
  if (a.cmd === 'gate') {
    if (!a.ref) usage('gate requires --ref <id> (a slug id like live-agent-dashboard-served-locally, or a numbered display id like CHANGE-0173)');
    if (!SLUG.test(a.ref)) usage(`--ref "${a.ref}" is neither a slug id nor a numbered display id (TYPE-0000)`);
    if (a.override !== null && a.override.trim() === '') usage('--override requires a reason');
    // An --intake whose id disagrees with --ref is a usage error in EITHER
    // posture (code review NB-3): checked here, before the absent admit.
    if (a.intake) { const early = readIntake(a.intake); if (early && early.id && early.id !== a.ref) usage(`--intake ${a.intake} has id "${early.id}", not --ref ${a.ref}`); }
    // The roadmap file is the posture switch: absent = ungoverned, admit without
    // consulting anything and write nothing (no override event: nothing overridden).
    if (!fs.existsSync(a.roadmap)) {
      // existsSync is false for EACCES too: only a real not-found admits (fail closed).
      if (!roadmapAbsent(a.roadmap)) refuse(`roadmap not readable: ${a.roadmap} (${a.roadmap}) — a gate that cannot read its roadmap admits nothing`);
      process.stdout.write(`ride-select: ADMIT ${a.ref} — roadmap absent (${a.roadmap}): gate not consulted\n`);
      process.exit(0);
    }
  }
  if (loaded.error) refuse(`${loaded.error} (${a.roadmap}) — a gate that cannot read its roadmap admits nothing`);
  const rm = loaded.roadmap;

  if (a.cmd === 'next') {
    const n = pickNext(rm, a.docs);
    // D5: an exhausted roadmap (no unfinished pair) offers the harvest
    // instead of only naming wave_2 — still exit 0, never a prompt or write.
    const harvestCommand = 'node .aai/scripts/roadmap-propose.mjs harvest --direction "<one sentence of owner direction>"';
    // D4: a started capability with an unbound maintenance slot proposes the
    // bind instead of ever printing a null/empty ref. Checked first: `bind`
    // only ever comes from nextRide (the 1:1-budget posture), never from
    // nextNoBudget (off/advisory), so it is unrelated to the advisory branch
    // below and never appears inside offJson.
    if (n && n.action === 'bind') {
      process.stdout.write(a.json
        ? JSON.stringify({ action: 'bind', capability: n.capability, command: n.command }) + '\n'
        : `${n.capability}: maintenance slot unbound — ${n.command}\n`);
      process.exit(0);
    }
    // The exact object/line the OFF posture (and, structurally, the advisory
    // posture when neither trigger fires — D5) prints for these same inputs.
    // Shared by (a) the plain print path below and (b) the advisory
    // proposal's `alternative` field, so the two can never drift (D6).
    const offJson = !n
      ? { next: null, wave_1: 'complete', wave_2: rm.wave_2, harvest_command: harvestCommand }
      : (n.action === 'file-intake'
          ? { action: 'file-intake', ref: n.ref, capability: n.capability, half: n.half }
          : { next: n.ref, half: n.half, pair: n.pair, path: n.path });
    const offText = !n
      ? `wave 1 complete — wave 2 candidates: ${rm.wave_2.join(', ') || 'none'} — harvest a new slate: ${harvestCommand}`
      : (n.action === 'file-intake'
          ? (n.half === 'capability'
              ? `${n.ref}: this pair's capability has no document yet — file its intake before this pair can be ridden`
              : `${n.ref}: bound as the maintenance half of ${n.capability} but no document resolves for it yet — file its intake before this pair's maintenance half can be ridden`)
          : n.ref);

    if (rm.posture === 'advisory') {
      const w = waitingMaintenance(a.docs, a.ledger);
      if (w.unreadable) {
        process.stderr.write(`ride-select: advisory not evaluated — ${w.unreadable.code}: ${w.unreadable.message} (${a.ledger})\n`);
      } else {
        const closed = lastClosedCapability(rm, a.events);
        const { reason, related } = adviseMaintenance(rm, w, closed);
        if (reason) {
          const proposal = {
            action: 'propose_maintenance',
            reason,
            capability: closed ? closed.capability : null,
            capability_source: closed ? closed.source : null,
            waiting: { count: w.count, threshold: rm.advisory.maintenance_threshold },
            candidates: buildCandidates(reason, related, w),
            alternative: offJson,
          };
          if (a.json) { process.stdout.write(`${JSON.stringify(proposal)}\n`); process.exit(0); }
          // Non-json text form (D6's three lines) lands with Spec-AC-07
          // (TEST-1625) — not yet exercised by Spec-AC-04/05/06, which only
          // assert the --json path when a trigger fires.
          const ids = proposal.candidates.map((c) => c.id).join(', ');
          process.stdout.write(`maintenance proposed (${reason}): ${ids}\nwaiting: ${w.count} of threshold ${rm.advisory.maintenance_threshold}; most recently closed capability: ${closed ? closed.capability : 'none'}\nor continue with: ${offText}\n`);
          process.exit(0);
        }
      }
    }

    // off posture, OR advisory with no trigger (or an unreadable --ledger,
    // D7), OR on posture past the `bind` check above — same print path.
    process.stdout.write(a.json ? `${JSON.stringify(offJson)}\n` : `${offText}\n`);
    process.exit(0);
  }

  // gate
  const intake = a.intake ? readIntake(a.intake) : findDoc(a.docs, a.ref);
  const pair = rm.pairs.find((p) => p.capability === a.ref || p.maintenance === a.ref);
  const status = intake ? intake.status : statusOf(a.docs, a.ref);

  const admit = (why) => { process.stdout.write(`ride-select: ADMIT ${a.ref} — ${why}\n`); process.exit(0); };
  const deny = (why) => {
    if (a.override) { appendOverride(a.events, a.ref, a.override); process.stdout.write(`ride-select: OVERRIDE ${a.ref} — ${why}; owner reason logged to ${a.events}: "${a.override}"\n`); process.exit(0); }
    refuse(why);
  };

  if (status === 'done') return deny(`${a.ref} is already done — nothing to ride`);
  if (!rm.budget) return noBudgetGate({ a, rm, pair, intake, admit, deny });
  if (pair) {
    if (pair.status === 'done') return deny(`${a.ref} belongs to a pair already marked done in the roadmap`);
    // AC-004: a ref already in flight is never refused by ranking, whichever
    // pair it belongs to — a roadmap edit must not refuse a ride mid-flight.
    if (status === 'implementing') return admit(`${a.ref} is already implementing — in flight`);
    if (!isFirstUnfinished(pair, rm)) {
      const ahead = rm.pairs.find((p) => p.status !== 'done');
      // F6 (non-blocking, validation round 1): a capability-only pair (D2 —
      // `maintenance:` optional) has `maintenance === null`; printing that
      // straight into the template literal renders the literal word "null",
      // not a sentence an owner can act on. `unbound` matches the vocabulary
      // D2/D4 already use for this exact state.
      return deny(`pair ahead — ${a.ref} is not the first unfinished pair; ${ahead.capability} (and its maintenance ${ahead.maintenance || 'unbound'}) must be done first (ranked roadmap order, 1:1 budget); override with --override "<reason>" if the owner really wants it out of order`);
    }
    // Spec-AC-29's own text: "on refs that exist" — the SAME authority
    // `validate` uses (`intake`, resolved above via `findDoc`/`readIntake`,
    // never a second copy of that resolution), applied here too. `validate`
    // exempts a still-`planned` pair (B5, Amendment 16, R6) because a
    // roadmap may legitimately name future work before its own intake
    // exists; `gate` does NOT carry that exemption, planned or not — gate is
    // the moment a ref is about to be WORKED ON (every real call site names
    // `--intake <primary_path>` for a document that was just created), so a
    // missing document here is exactly the defect this check exists to
    // catch, not a legitimate ahead-of-intake naming. This closes Amendment
    // 16's R6 residual (validation-round1 B5/R6): a typo'd-but-internally-
    // consistent roadmap slug — capability OR maintenance half — no longer
    // reaches an ADMIT.
    // F6 (non-blocking, validation round 1): same "unbound" substitution as
    // the pair-ahead refusal above — a capability-only pair's maintenance
    // slot is null, not the string "null".
    if (!intake) return deny(`${a.ref} matches roadmap pair "${pair.capability}"/"${pair.maintenance || 'unbound'}" but no document resolves for "${a.ref}" under ${a.docs} — file its intake before gating this ref (Spec-AC-29: gate admits only refs that exist)`);
    if (pair.capability === a.ref) return admit('a roadmap capability');
    const cs = statusOf(a.docs, pair.capability);
    if (!STARTED.has(cs || '')) return deny(`pair first — ${a.ref} is the maintenance half of a pair whose capability ${pair.capability} is ${cs || 'not filed'}; start ${pair.capability} before it (1:1 budget)`);
    return admit(`the maintenance half of a pair whose capability ${pair.capability} is ${cs}`);
  }
  // off-roadmap
  if (intake && intake.blocks) {
    const b = intake.blocks;
    const target = rm.pairs.find((p) => p.capability === b || p.maintenance === b);
    if (!target) return deny(`blocks: names ${b}, which is not on the roadmap`);
    if (target.status === 'done' || statusOf(a.docs, b) === 'done') return deny(`blocks: names ${b}, which is already done`);
    return admit(`off-roadmap but blocks roadmap item ${b}`);
  }
  if (isMaintenance(a.ref, intake)) {
    // D3: the gate stays side-effect-free — it is NOT taught to admit an
    // unbound maintenance ride on the fly. The refusal now also names the
    // bind command (D4/D13), alongside the pre-existing backlog remedy.
    return deny(`${a.ref} is maintenance and not on the roadmap — file it to the backlog: node .aai/scripts/follow-ups.mjs add --id fu-<slug> --ref <roadmap-ref> --severity P3 --what "…" --why "…" --source "…"; or add "blocks: <roadmap ref>" to its intake if it blocks one; or bind it to a roadmap capability whose maintenance slot is unbound: node .aai/scripts/roadmap-propose.mjs bind --capability <roadmap-ref> --ref ${a.ref}`);
  }
  return deny(`${a.ref} is not on the roadmap — add it to docs/ai/roadmap.yaml (an owner decision) or mark its intake "blocks: <roadmap ref>"`);
}

main();
