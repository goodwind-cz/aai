// aai-feedback-upsert.mjs — RFC-0012 Phase 2c / Slice C review-mode upsert.
//
// Consumes the offline triage report's `review_candidate` clusters and, in
// `review` mode, PREPARES a transmit-redacted, deduplicated, budget-checked GitHub
// issue per cluster. A plain run is PREPARE-ONLY: it writes local drafts and
// prints the exact confirmed-write command, and performs NO mutating GitHub call.
// The ONLY mutating write happens on the explicit, human-confirmed path
// `--publish <fingerprint> --confirm`, which re-verifies redaction + budget first.
// `auto` mode is refused (locked until a later slice); `local` prepares nothing.
//
// Network: read-only `gh` (dedup search) may run while preparing; a MUTATING `gh`
// (issue create) runs ONLY under --confirm. The engine holds no token — it shells
// to `gh`, which the operator has authenticated. Missing/unauthenticated `gh`
// degrades to prepare-nothing-to-send.
//
// Usage:
//   node .aai/scripts/aai-feedback-upsert.mjs [--report <p>] [--spool <p>] [--config <p>]
//   node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm [...]
//   node .aai/scripts/aai-feedback-upsert.mjs --help
//
// Node stdlib only. `gh` is invoked via a single runGh() seam (mockable on PATH).

import { readFileSync, writeFileSync, mkdirSync, existsSync, appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { redactSummary } from './lib/aai-redact.mjs';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..');
// Friction dir (spool + drafts + ledger). Overridable for tests via env, same
// pattern as capture's AAI_FRICTION_SPOOL_DIR, so a suite can isolate its writes.
const FRICTION_DIR = process.env.AAI_FRICTION_DIR || join(REPO_ROOT, 'docs', 'ai', 'friction');
const DEFAULT_REPORT = join(FRICTION_DIR, 'triage-report.json');
const DEFAULT_SPOOL = join(FRICTION_DIR, 'observations.jsonl');
const DEFAULT_CONFIG = join(REPO_ROOT, '.aai', 'feedback.yaml');
const PENDING_DIR = join(FRICTION_DIR, 'pending-issues');
const LEDGER = join(FRICTION_DIR, 'upsert-ledger.jsonl');
// The fingerprint field already carries its `v1:` version tag, so the stable
// dedup marker is `<!-- aai-friction:<fingerprint> -->` (e.g. aai-friction:v1:abc).
const MARKER = (fp) => `<!-- aai-friction:${fp} -->`;
const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

const MODES = new Set(['local', 'review', 'auto']);

const HELP = `aai-feedback-upsert — RFC-0012 Phase 2c review-mode upsert (approval-gated).

Usage:
  node .aai/scripts/aai-feedback-upsert.mjs [--report <p>] [--spool <p>] [--config <p>]
  node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm [...]
  node .aai/scripts/aai-feedback-upsert.mjs --help

A plain run is PREPARE-ONLY: it writes transmit-redacted, deduplicated,
budget-checked issue drafts to docs/ai/friction/pending-issues/ and prints the
exact confirmed-write command. It performs NO mutating GitHub call. A GitHub issue
is filed ONLY via the explicit human-confirmed path:
  --publish <fingerprint> --confirm
which re-runs the transmit redaction + budget check immediately before the write.
'auto' mode is refused (locked). 'local' (default) prepares nothing to send.

Exit codes: 0 success / --help   2 usage error   1 internal error
`;

class UsageError extends Error {}

function parseArgs(argv) {
  const a = { report: DEFAULT_REPORT, spool: DEFAULT_SPOOL, config: DEFAULT_CONFIG };
  let i = 0;
  while (i < argv.length) {
    const t = argv[i];
    if (t === '--help' || t === '-h') { a.help = true; i += 1; continue; }
    if (t === '--confirm') { a.confirm = true; i += 1; continue; }
    if (t === '--report' || t === '--spool' || t === '--config' || t === '--publish') {
      const v = argv[i + 1];
      if (v === undefined) throw new UsageError(`${t} requires an argument`);
      a[t.slice(2)] = v; i += 2; continue;
    }
    throw new UsageError(`unrecognized argument: ${t}`);
  }
  return a;
}

// Scoped, fail-closed config read (mirrors the triage parser discipline): `mode`
// from a direct child of top-level `triage:`; `destination`/`cooldown_days` from a
// direct child of `upsert:`; `max_new_issues_per_7d` from `upsert: > budget:`.
// Any anomaly leaves the safe default (mode local, destination null).
function indentOf(l) { return l.length - l.trimStart().length; }
function loadConfig(path) {
  const cfg = { mode: 'local', destination: null, maxNewPer7d: 3, cooldownDays: 7 };
  let text; try { text = readFileSync(path, 'utf8'); } catch { return cfg; }
  let section = null;         // 'triage' | 'upsert' | null
  let childIndent = null;
  let inBudget = false; let budgetIndent = null;
  for (const raw of text.split('\n')) {
    if (!raw.trim() || /^[ \t]*#/.test(raw)) continue;
    const indent = indentOf(raw); const line = raw.trim();
    if (indent === 0) {
      section = /^triage[ \t]*:/.test(line) ? 'triage'
        : /^upsert[ \t]*:/.test(line) ? 'upsert' : null;
      childIndent = null; inBudget = false;
      continue;
    }
    if (!section) continue;
    if (childIndent === null) childIndent = indent;
    if (indent === childIndent) {
      inBudget = false;
      const kv = line.match(/^([a-z_]+)[ \t]*:(.*)$/); if (!kv) continue;
      const key = kv[1]; const val = kv[2].trim();
      if (section === 'triage' && key === 'mode' && MODES.has(val)) cfg.mode = val;
      if (section === 'upsert' && key === 'destination' && /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/.test(val)) cfg.destination = val;
      if (section === 'upsert' && key === 'cooldown_days' && /^\d+$/.test(val)) cfg.cooldownDays = parseInt(val, 10);
      if (section === 'upsert' && key === 'budget') { inBudget = true; budgetIndent = null; }
    } else if (section === 'upsert' && inBudget && indent > childIndent) {
      if (budgetIndent === null) budgetIndent = indent;
      if (indent === budgetIndent) {
        const m = line.match(/^max_new_issues_per_7d[ \t]*:[ \t]*(\d+)[ \t]*$/);
        if (m) cfg.maxNewPer7d = parseInt(m[1], 10);
      }
    }
  }
  if (!MODES.has(cfg.mode)) cfg.mode = 'local';
  return cfg;
}

function readJson(path, fallback) {
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return fallback; }
}
function readSpool(path) {
  let text; try { text = readFileSync(path, 'utf8'); } catch { return []; }
  const rows = [];
  for (const l of text.split('\n')) {
    if (!l.trim()) continue;
    try { const o = JSON.parse(l); if (o && typeof o === 'object' && !Array.isArray(o)) rows.push(o); } catch { /* skip */ }
  }
  return rows;
}

// The single `gh` seam. `mutating:true` is asserted ONLY on the confirmed path.
// Returns { ok, stdout } ; never throws on a missing/failing gh (degrade).
function runGh(args, { mutating } = {}) {
  const bin = process.env.AAI_GH_BIN || 'gh';
  try {
    const stdout = execFileSync(bin, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return { ok: true, stdout };
  } catch {
    return { ok: false, stdout: '' };
  }
}

// Read-only dedup search for the fingerprint marker. Returns a TRI-STATE:
// { searched } is false when gh is unavailable OR its output is unparseable
// (transient error / API drift). Callers must distinguish "searched and none"
// (safe to create) from "could not search" (the confirm path fails CLOSED and
// refuses to create, so a search hiccup can never fan out into a duplicate).
function dedupSearch(destination, fp) {
  if (!destination) return { searched: false, exists: false };
  const r = runGh(['search', 'issues', '--repo', destination, '--match', 'body', `aai-friction:${fp}`, '--state', 'all', '--json', 'number', '--limit', '1']);
  if (!r.ok) return { searched: false, exists: false };
  try { const arr = JSON.parse(r.stdout); return { searched: true, exists: Array.isArray(arr) && arr.length > 0 }; }
  catch { return { searched: false, exists: false }; }
}

// Representative observation for a fingerprint: highest v2 signal, else first.
function representative(rows, fp) {
  const members = rows.filter((o) => o.fingerprint === fp);
  if (!members.length) return null;
  const sig = (o) => (({ low: 1, medium: 2, high: 3 })[o.impact] || 0)
    + (({ low: 1, medium: 2, high: 3 })[o.confidence] || 0) + (o.reproducible === true ? 2 : 0);
  return members.reduce((a, b) => (sig(b) > sig(a) ? b : a), members[0]);
}

// TRANSMIT-pass field sanitizers (RFC-0013 D3 double redaction): the upsert must
// NOT trust the spool — EVERY field interpolated into a gh argument is re-validated
// here, independently of the capture pass. A value that does not match its safe
// domain is replaced with a placeholder / dropped, so no secret/path/identity in
// any field (not just `summary`) can reach a GitHub issue title or body.
const IMPACT = new Set(['low', 'medium', 'high']);
const CONFIDENCE = new Set(['low', 'medium', 'high']);
const WORKAROUND = new Set(['none', 'manual', 'automatic']);
const OS_FAMILY = new Set(['linux', 'macos', 'windows', 'unknown']);
const FAILURE_CLASSES = new Set([
  'contradictory_instructions', 'missing_or_invalid_artifact', 'deterministic_script_failure',
  'abstraction_leak_recovery', 'human_corrected_defect', 'contract_violation',
]);
const EVIDENCE_REF_RE = /^(?:docs\/[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)*|(?:SPEC|CHANGE|ISSUE|RFC|PRD|RES|DEBT)-\d{4})$/;
const REDACTED = '<redacted>';
// An AAI identifier (skill id / phase): must match the identifier charset AND
// pass the aai-redact deny-list. Charset alone is INSUFFICIENT — real secret
// tokens (ghp_…, sk_live_…, AKIA…) are themselves identifier-shaped (alnum +
// underscore), so they must also be caught by the secret detectors reused via
// redactSummary (which applies the same deny-list). Fails -> redacted placeholder.
function passesRedactor(v) { return redactSummary(v).ok; }
function safeIdent(v) {
  if (typeof v !== 'string' || !/^[A-Za-z0-9_.-]{1,128}$/.test(v)) return REDACTED;
  return passesRedactor(v) ? v : REDACTED; // catches charset-clean secret tokens
}
function safeEnum(v, set) { return (typeof v === 'string' && set.has(v)) ? v : null; }
function safeOsFamily(v) { return OS_FAMILY.has(v) ? v : 'unknown'; }
function safeInt(v) { return Number.isInteger(v) ? String(v) : '?'; }
function safePin(v) {
  if (typeof v !== 'string' || !/^[A-Za-z0-9._+-]{1,64}$/.test(v)) return REDACTED;
  return passesRedactor(v) ? v : REDACTED; // deny-list in addition to charset
}
function safeEvidenceRef(v) {
  return (typeof v === 'string' && EVIDENCE_REF_RE.test(v) && !v.split('/').includes('..')) ? v : null;
}
function safeFailureClass(v) { return FAILURE_CLASSES.has(v) ? v : REDACTED; }

// Build a transmit-redacted issue payload. EVERY interpolated field is re-validated
// against its safe domain (double redaction, RFC-0013 D3) — the upsert never trusts
// the spool, so no field can carry a secret/path/identity into a gh argument.
function buildPayload(rep, cluster) {
  const fclass = safeFailureClass(rep.failure_class);
  const skill = safeIdent(rep.skill_id);
  const phase = safeIdent(rep.skill_phase);
  const impact = safeEnum(rep.impact, IMPACT);
  const confidence = safeEnum(rep.confidence, CONFIDENCE);
  const workaround = safeEnum(rep.workaround, WORKAROUND);
  const evidenceRef = safeEvidenceRef(rep.evidence_ref);
  const impactPart = impact ? ` (${impact} impact)` : '';
  const title = `[${fclass}] ${skill}/${phase}${impactPart}`;
  const facts = [
    `- failure_class: ${fclass}`,
    `- skill: ${skill} / ${phase}`,
    impact ? `- impact: ${impact}` : null,
    confidence ? `- confidence: ${confidence}` : null,
    rep.reproducible === true || rep.reproducible === false ? `- reproducible: ${rep.reproducible}` : null,
    workaround ? `- workaround: ${workaround}` : null,
    evidenceRef ? `- evidence_ref: ${evidenceRef}` : null,
    `- os_family: ${safeOsFamily(rep.os_family)}  node_major: ${safeInt(rep.node_major)}  aai_pin: ${safePin(rep.aai_pin)}`,
    `- recurrence: ${safeInt(cluster.recurrence)}  score: ${safeInt(cluster.score)}`,
  ].filter(Boolean);
  // Transmit redaction of the ONLY free-text field: summary. Dropped if unsafe.
  let summaryLine = null;
  let redactionStatus = 'none';
  if (typeof rep.summary === 'string' && rep.summary.length) {
    const r = redactSummary(rep.summary);
    if (r.ok) { summaryLine = `\n> ${r.value}`; redactionStatus = 'transmit_clean'; }
    else redactionStatus = 'transmit_dropped';
  }
  const body = `${summaryLine ? summaryLine + '\n\n' : ''}${facts.join('\n')}\n\n${MARKER(rep.fingerprint)}\n`;
  return { title, body, redaction_status: redactionStatus };
}

// Rolling 7-day budget from the local ledger (created issues only).
function newIssuesLast7d(nowMs) {
  if (!existsSync(LEDGER)) return 0;
  let n = 0;
  for (const l of readFileSync(LEDGER, 'utf8').split('\n')) {
    if (!l.trim()) continue;
    try { const e = JSON.parse(l); if (e.event === 'issue_created' && typeof e.ts_ms === 'number' && nowMs - e.ts_ms < WEEK_MS) n += 1; } catch { /* skip */ }
  }
  return n;
}

function ensureDir(d) { if (!existsSync(d)) mkdirSync(d, { recursive: true }); }

function prepare(args, cfg) {
  const report = readJson(args.report, { clusters: [] });
  const rows = readSpool(args.spool);
  const candidates = (report.clusters || []).filter((c) => c.decision === 'review_candidate');
  ensureDir(PENDING_DIR);
  const prepared = [];
  for (const cluster of candidates) {
    const rep = representative(rows, cluster.fingerprint);
    if (!rep) continue;
    const payload = buildPayload(rep, cluster);
    const ds = dedupSearch(cfg.destination, cluster.fingerprint);
    const draftPath = join(PENDING_DIR, `${cluster.fingerprint.replace(/[^A-Za-z0-9]/g, '_')}.md`);
    const status = ds.exists ? 'update_existing' : 'new';
    writeFileSync(draftPath,
      `# ${payload.title}\n\n<!-- status: ${status} | redaction: ${payload.redaction_status} -->\n\n${payload.body}`);
    prepared.push({ fingerprint: cluster.fingerprint, status, draftPath });
  }
  return prepared;
}

function main() {
  const argv = process.argv.slice(2);
  let args; try { args = parseArgs(argv); }
  catch (e) { process.stderr.write(`aai-feedback-upsert: ${e.message}\n`); process.exit(2); }
  if (args.help) { process.stdout.write(HELP); process.exit(0); }

  const cfg = loadConfig(args.config);
  if (cfg.mode === 'auto') { process.stderr.write('aai-feedback-upsert: mode=auto is refused (locked until a later slice)\n'); process.exit(2); }

  // --- confirmed publish path: the ONLY mutating write --------------------
  if (args.publish) {
    if (!args.confirm) {
      process.stdout.write(`refusing to publish ${args.publish} without --confirm (prepared drafts are in ${PENDING_DIR})\n`);
      process.exit(0);
    }
    if (cfg.mode !== 'review' || !cfg.destination) {
      process.stderr.write('aai-feedback-upsert: publish requires mode=review and a configured destination\n');
      process.exit(2);
    }
    const rows = readSpool(args.spool);
    const report = readJson(args.report, { clusters: [] });
    const cluster = (report.clusters || []).find((c) => c.fingerprint === args.publish && c.decision === 'review_candidate');
    const rep = cluster && representative(rows, args.publish);
    if (!rep) { process.stderr.write(`aai-feedback-upsert: ${args.publish} is not a current review_candidate\n`); process.exit(2); }
    // Dedup FIRST, fail-closed: if we cannot CONFIRM there is no existing issue
    // (gh unavailable or unparseable output), REFUSE to create — a search hiccup
    // must never fan out into a duplicate.
    const ds = dedupSearch(cfg.destination, args.publish);
    if (!ds.searched) {
      process.stderr.write(`aai-feedback-upsert: could not verify dedup for ${args.publish} (gh search unavailable) — refusing to create\n`);
      process.exit(1);
    }
    if (ds.exists) {
      process.stdout.write(`existing issue carries the marker for ${args.publish}; skipping duplicate create\n`);
      process.exit(0);
    }
    // Re-verify budget immediately before the write (no stale payload).
    const nowMs = Number(process.env.AAI_NOW_MS) || Date.now();
    if (newIssuesLast7d(nowMs) >= cfg.maxNewPer7d) {
      process.stdout.write(`budget reached (${cfg.maxNewPer7d}/7d) — deferring ${args.publish}, not filed\n`);
      process.exit(0);
    }
    const payload = buildPayload(rep, cluster);
    const r = runGh(['issue', 'create', '--repo', cfg.destination, '--title', payload.title, '--body', payload.body], { mutating: true });
    if (!r.ok) { process.stderr.write('aai-feedback-upsert: gh issue create failed (is gh authenticated?)\n'); process.exit(1); }
    ensureDir(FRICTION_DIR);
    appendFileSync(LEDGER, JSON.stringify({ event: 'issue_created', fingerprint: args.publish, ts_ms: nowMs, destination: cfg.destination }) + '\n');
    process.stdout.write(`filed issue for ${args.publish} in ${cfg.destination}\n`);
    process.exit(0);
  }

  // --- prepare-only default (no mutating call) ---------------------------
  if (cfg.mode !== 'review' || !cfg.destination) {
    process.stdout.write(`mode=${cfg.mode}${cfg.destination ? '' : ' (no destination)'} — nothing prepared to send (local prepare-none)\n`);
    process.exit(0);
  }
  const prepared = prepare(args, cfg);
  if (!prepared.length) { process.stdout.write('no review_candidate clusters to prepare\n'); process.exit(0); }
  process.stdout.write(`prepared ${prepared.length} issue draft(s) in ${PENDING_DIR} (mode=review, dest=${cfg.destination}):\n`);
  for (const p of prepared) {
    process.stdout.write(`  ${p.status.padEnd(15)} ${p.fingerprint}  -> review then: node .aai/scripts/aai-feedback-upsert.mjs --publish ${p.fingerprint} --confirm\n`);
  }
}

main();
