#!/usr/bin/env node
//
// merge-policy.mjs — the ONE deterministic evaluator for a project-owned,
// owner-signed merge policy (docs/ai/merge-policy.yaml), SPEC-DRAFT
// spec-configurable-merge-policy-lanes.
//
// THIS IS A PARTIAL BUILD (batch 2 of a multi-batch TDD ride). Batch 1
// implemented Spec-AC-01 (no_policy), Spec-AC-03 (base-only reads) and
// Spec-AC-04 (GUARD_PATHS). This batch adds Spec-AC-05 (classifyFiles
// order: guard, then architecture, then kind), Spec-AC-06 (globToRegExp
// semantics, proven through --classify) and Spec-AC-07 (requesterApproved).
// Every other predicate (CI green, the sweep-check spawn, lane `requires`
// conditions, ceremony, deploy-consistency/opt-in validation, marker
// validation) is still a deliberately permissive STUB, each marked `TODO:
// Spec-AC-<n>` — a later batch replaces the stub body with the real
// predicate and its own RED/GREEN evidence. The file's PUBLIC CONTRACT
// (exported names, CLI modes, exit codes, printed line shapes) is written
// to the full spec so later batches build ON this skeleton rather than
// restructure it.
//
// Modes:
//   --check --pr <n> [--repo-root <dir>] [--debug-inputs]
//   --validate [--path <file>] [--repo-root <dir>]
//   --classify --path <policy> --files-from <path|-> [--repo-root <dir>]
//
// Node stdlib only (docs/TECHNOLOGY.md) — no YAML library; the policy file
// is a closed-shape, line-level parse (same discipline as
// .aai/scripts/lib/roadmap-model.mjs).

import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const SELF_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = resolve(SELF_DIR, '..', '..');

export const POLICY_PATH = 'docs/ai/merge-policy.yaml';
export const DECISIONS_PATH = 'docs/ai/decisions.jsonl';

// P4 — GUARD_PATHS: the policy file, this evaluator, the hook adapter,
// lane-gate.mjs, and every lib module either this file or lane-gate.mjs
// imports (TEST-1507 proves this set is a superset of that real import
// closure, read via a live `import`, not restated by hand elsewhere).
export const GUARD_PATHS = [
  'docs/ai/merge-policy.yaml',
  '.aai/scripts/merge-policy.mjs',
  '.aai/scripts/claude-hook-gate.sh',
  '.aai/scripts/lane-gate.mjs',
  '.aai/scripts/lib/cli-pipe-guard.mjs',
  '.aai/scripts/lib/pr-sweep.mjs',
];

export const MARKER_RE = /^AAI_[A-Z0-9_]+_MERGE$/;
export const DEFAULT_MAX_CEREMONY = 2;

export const EXIT_ALLOWED = 0;
const EXIT_USAGE = 2;
export const EXIT_DENIED = 3;
export const EXIT_NO_POLICY = 4;

// ---------------------------------------------------------------------------
// Closed-shape, line-level policy parsing (P1). No YAML library — a
// deliberately narrow parser for the exact schema the spec documents.
// ---------------------------------------------------------------------------

function stripComment(line) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === "'" && !inDouble) inSingle = !inSingle;
    else if (c === '"' && !inSingle) inDouble = !inDouble;
    else if (c === '#' && !inSingle && !inDouble) {
      if (i === 0 || /\s/.test(line[i - 1])) return line.slice(0, i);
    }
  }
  return line;
}

function tokenizeLines(text) {
  return text
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((raw) => {
      const stripped = stripComment(raw);
      if (!stripped.trim()) return null;
      const indent = stripped.length - stripped.replace(/^ */, '').length;
      return { indent, content: stripped.trim() };
    })
    .filter(Boolean);
}

function splitKV(content) {
  const idx = content.indexOf(':');
  if (idx === -1) return null;
  return { key: content.slice(0, idx).trim(), rest: content.slice(idx + 1).trim() };
}

function parseScalar(raw) {
  const s = String(raw).trim();
  if (s === 'true') return true;
  if (s === 'false') return false;
  if (/^-?\d+$/.test(s)) return Number(s);
  if ((s.startsWith('"') && s.endsWith('"') && s.length >= 2)
      || (s.startsWith("'") && s.endsWith("'") && s.length >= 2)) {
    return s.slice(1, -1);
  }
  return s;
}

function parseFlowList(raw) {
  const s = String(raw).trim();
  if (!s.startsWith('[') || !s.endsWith(']')) return null;
  const inner = s.slice(1, -1).trim();
  if (inner === '') return [];
  return inner.split(',').map((x) => parseScalar(x.trim()));
}

const TOP_KEYS = new Set(['version', 'deploy', 'architecture', 'kinds', 'lanes']);
const DEPLOY_KEYS = new Set(['preview', 'production_on_merge']);
const LANE_SCALAR_KEYS = [
  'decision_ref', 'decision_match', 'signed_by', 'kinds', 'merge_reaches',
  'allow_public_side_effect', 'max_ceremony', 'marker', 'requester_logins',
];

// parsePolicy(text) -> { policy } | { errors }. Closed shape, P1. Only the
// errors this batch owns (parse_error, unknown_key, empty_globs) are
// actively detected; the remaining Validate codes that belong to other
// Spec-ACs (duplicate_lane, undefined_kind, bad_marker, duplicate_marker,
// bad_ceremony, requester_missing, missing_key) are intentionally NOT
// enforced here yet — TODO: Spec-AC-12/13 (later batches).
export function parsePolicy(text) {
  let lines;
  try {
    lines = tokenizeLines(String(text));
  } catch {
    return { errors: [{ lane: '-', code: 'parse_error' }] };
  }
  const policy = {
    version: null,
    deploy: { preview: 'none', production_on_merge: false },
    architecture: [],
    kinds: [],
    lanes: [],
  };
  let i = 0;
  try {
    while (i < lines.length) {
      const { indent, content } = lines[i];
      if (indent !== 0) return { errors: [{ lane: '-', code: 'parse_error' }] };
      const kv = splitKV(content);
      if (!kv) return { errors: [{ lane: '-', code: 'parse_error' }] };
      const { key, rest } = kv;
      if (!TOP_KEYS.has(key)) return { errors: [{ lane: '-', code: 'unknown_key' }] };

      if (key === 'version') {
        policy.version = parseScalar(rest);
        i += 1;
        continue;
      }

      if (key === 'deploy') {
        i += 1;
        const block = {};
        while (i < lines.length && lines[i].indent === 2) {
          const kv2 = splitKV(lines[i].content);
          if (!kv2 || !DEPLOY_KEYS.has(kv2.key)) return { errors: [{ lane: '-', code: 'unknown_key' }] };
          block[kv2.key] = parseScalar(kv2.rest);
          i += 1;
        }
        policy.deploy = {
          preview: block.preview ?? 'none',
          production_on_merge: block.production_on_merge ?? false,
        };
        continue;
      }

      if (key === 'architecture' || key === 'kinds') {
        i += 1;
        const list = [];
        while (i < lines.length && lines[i].indent === 2 && lines[i].content.startsWith('- ')) {
          const first = lines[i].content.slice(2).trim();
          const kvId = splitKV(first);
          if (!kvId || kvId.key !== 'id') return { errors: [{ lane: '-', code: 'parse_error' }] };
          const item = { id: parseScalar(kvId.rest), globs: [] };
          i += 1;
          while (i < lines.length && lines[i].indent === 4) {
            const kv3 = splitKV(lines[i].content);
            if (!kv3 || kv3.key !== 'globs') return { errors: [{ lane: item.id, code: 'unknown_key' }] };
            const g = parseFlowList(kv3.rest);
            if (g === null) return { errors: [{ lane: item.id, code: 'parse_error' }] };
            if (g.length === 0 || g.some((x) => x === '')) {
              return { errors: [{ lane: item.id, code: 'empty_globs' }] };
            }
            item.globs = g;
            i += 1;
          }
          list.push(item);
        }
        policy[key] = list;
        continue;
      }

      if (key === 'lanes') {
        i += 1;
        const lanes = [];
        while (i < lines.length && lines[i].indent === 2 && lines[i].content.startsWith('- ')) {
          const first = lines[i].content.slice(2).trim();
          const kvId = splitKV(first);
          if (!kvId || kvId.key !== 'id') return { errors: [{ lane: '-', code: 'parse_error' }] };
          const lane = { id: parseScalar(kvId.rest) };
          i += 1;
          while (i < lines.length && lines[i].indent === 4) {
            const kv3 = splitKV(lines[i].content);
            if (!kv3) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
            if (kv3.key === 'requires') {
              i += 1;
              const requires = {};
              while (i < lines.length && lines[i].indent === 6) {
                const kv4 = splitKV(lines[i].content);
                if (!kv4) return { errors: [{ lane: lane.id, code: 'parse_error' }] };
                requires[kv4.key] = kv4.rest.trim().startsWith('[')
                  ? parseFlowList(kv4.rest)
                  : parseScalar(kv4.rest);
                i += 1;
              }
              lane.requires = requires;
              continue;
            }
            if (!LANE_SCALAR_KEYS.includes(kv3.key)) return { errors: [{ lane: lane.id, code: 'unknown_key' }] };
            lane[kv3.key] = kv3.rest.trim().startsWith('[') ? parseFlowList(kv3.rest) : parseScalar(kv3.rest);
            i += 1;
          }
          if (!Array.isArray(lane.kinds)) lane.kinds = lane.kinds != null ? [lane.kinds] : [];
          if (!Array.isArray(lane.requester_logins)) {
            lane.requester_logins = lane.requester_logins != null ? [lane.requester_logins] : [];
          }
          lanes.push(lane);
        }
        policy.lanes = lanes;
        continue;
      }
    }
  } catch {
    return { errors: [{ lane: '-', code: 'parse_error' }] };
  }
  return { policy };
}

function parseJsonl(text) {
  const out = [];
  for (const line of String(text || '').split('\n')) {
    const t = line.trim();
    if (!t) continue;
    try {
      out.push(JSON.parse(t));
    } catch {
      // malformed line — ignored, same as every other JSONL ledger reader
      // in this repo (append-event.mjs's own readers).
    }
  }
  return out;
}

// P2 decision binder. The mandated `if (hits.length > 1)` line disambiguates
// the wave-2-roadmap shape (three hitl_decision records sharing one ts) —
// decision_match is part of the filter, not an afterthought.
function resolveDecision(lane, decisionsText) {
  const ref = String(lane.decision_ref || '');
  const atIdx = ref.indexOf('@');
  const refId = atIdx === -1 ? ref : ref.slice(0, atIdx);
  const ts = atIdx === -1 ? '' : ref.slice(atIdx + 1);
  const records = parseJsonl(decisionsText);
  const hits = records.filter((r) => r
    && r.type === 'hitl_decision'
    && r.ref_id === refId
    && r.ts === ts
    && typeof r.decision === 'string'
    && r.decision.includes(String(lane.decision_match || '')));
  if (hits.length === 0) return { code: 'decision_missing' };
  if (hits.length > 1) return { code: 'decision_ambiguous' };
  const rec = hits[0];
  if (rec.owner_signoff !== true) return { code: 'decision_unsigned' };
  if (rec.actor !== lane.signed_by) return { code: 'signer_mismatch' };
  return { ok: true, record: rec };
}

// validatePolicy(policy, decisionsText) — P2 (decision binding, implemented)
// and P7 (deploy consistency + opt-ins). TODO: Spec-AC-10/12 (later batch)
// implement the P7 half (reaches_inconsistent, public_effect_not_opted_in)
// — not enforced yet, so a deploy-inconsistent fixture validates here until
// that batch lands.
export function validatePolicy(policy, decisionsText) {
  const errors = [];
  for (const lane of policy.lanes || []) {
    const res = resolveDecision(lane, decisionsText);
    if (!res.ok) errors.push({ lane: lane.id, code: res.code });
  }
  return errors.length ? { errors } : { ok: true };
}

// readAtBase(root, oid, relPath) -> text | null. `git show <oid>:<relPath>`;
// null when the path is genuinely absent at that commit; throws a
// base_unavailable-coded error when the commit object itself cannot be
// resolved (P3, P6).
export function readAtBase(root, oid, relPath) {
  try {
    return execFileSync('git', ['show', oid + ':' + relPath], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (err) {
    const stderr = String((err && err.stderr) || '');
    if (/invalid object name|bad object|unknown revision|bad revision/i.test(stderr)) {
      const e = new Error('base_unavailable');
      e.code = 'base_unavailable';
      throw e;
    }
    return null; // path absent at this commit
  }
}

// ---------------------------------------------------------------------------
// P5 — glob classification.
// ---------------------------------------------------------------------------

const ESCAPE_RE = /[.+^${}()|[\]\\]/;

// globToRegExp(glob) — `*` within one segment (never `/`), `**` spans zero
// or more whole segments, `?` one non-`/` character, full anchored match
// (no implicit basename matching).
export function globToRegExp(glob) {
  let re = '';
  let i = 0;
  const s = String(glob);
  while (i < s.length) {
    if (s[i] === '*' && s[i + 1] === '*') {
      i += 2;
      if (s[i] === '/') {
        re += '(?:.*/)?';
        i += 1;
      } else {
        re += '.*';
      }
      continue;
    }
    if (s[i] === '*') {
      re += '[^/]*';
      i += 1;
      continue;
    }
    if (s[i] === '?') {
      re += '[^/]';
      i += 1;
      continue;
    }
    const c = s[i];
    re += ESCAPE_RE.test(c) ? '\\' + c : c;
    i += 1;
  }
  return new RegExp(`^${re}$`);
}

// classifyFiles(files, policy) — guard paths first, then architecture, then
// kinds (P5, Spec-AC-05). Returns { denyReason, path } on the first
// PR-level deny, or { kinds: Set<kindId> } naming every kind at least one
// changed file matched. Architecture always overrides a kind match on the
// same path (the `if (archHit) return` below runs before the kind lookup).
// The glob engine itself (globToRegExp, Spec-AC-06) is proven through the
// --classify authoring aid's 10-row glob table.
export function classifyFiles(files, policy) {
  for (const f of files) {
    if (GUARD_PATHS.includes(f)) return { denyReason: 'policy_touched', path: f };
  }
  const kinds = new Set();
  for (const f of files) {
    let archHit = false;
    for (const a of policy.architecture) {
      if ((a.globs || []).some((g) => globToRegExp(g).test(f))) { archHit = true; break; }
    }
    if (archHit) return { denyReason: 'architecture', path: f };
    let kindId = null;
    for (const k of policy.kinds || []) {
      if ((k.globs || []).some((g) => globToRegExp(g).test(f))) { kindId = k.id; break; }
    }
    if (kindId === null) return { denyReason: 'unclassified', path: f };
    kinds.add(kindId);
  }
  return { kinds };
}

// ---------------------------------------------------------------------------
// Predicates not owned by this batch — permissive stubs, each named after
// the Spec-AC whose later batch replaces the body. None of these may ever
// turn a FUTURE batch's genuine denial into a false allow; they only ever
// avoid blocking THIS batch's own (unrelated) fixtures.
// ---------------------------------------------------------------------------

// requesterApproved(reviews, logins, headOid) — P6, Spec-AC-07. Only
// APPROVED, CHANGES_REQUESTED and DISMISSED reviews decide anything;
// COMMENTED never overrides. For each listed login, take that login's
// latest deciding review by submittedAt. Satisfied when at least one
// listed login's latest deciding review is APPROVED at headOid.
const DECIDING_REVIEW_STATES = new Set(['APPROVED', 'CHANGES_REQUESTED', 'DISMISSED']);

export function requesterApproved(reviews, logins, headOid) {
  const list = Array.isArray(reviews) ? reviews : [];
  const loginList = Array.isArray(logins) ? logins : [];
  for (const login of loginList) {
    let latest = null;
    for (const rev of list) {
      if (!rev || !rev.author || rev.author.login !== login) continue;
      if (!DECIDING_REVIEW_STATES.has(rev.state)) continue;
      if (!latest || String(rev.submittedAt || '') > String(latest.submittedAt || '')) latest = rev;
    }
    const r = latest;
    if (r && r.state === 'APPROVED' && r.commit && r.commit.oid === headOid) {
      return true;
    }
  }
  return false;
}

// TODO: Spec-AC-08 (later batch) — the real per-entry COMPLETED/SUCCESS|
// NEUTRAL|SKIPPED (CheckRun) / SUCCESS (StatusContext) predicate. The two
// defensive lines are real and mandated; the substantive classification is
// stubbed permissive until that batch lands.
export function ciGreen(rollup) {
  if (!Array.isArray(rollup)) return false;
  if (rollup.length === 0) return false;
  return true;
}

// TODO: Spec-AC-09 (later batch) — spawn `lane-gate.mjs --sweep-check` and
// map its exit 5 to `sweep_check_failed`. Stubbed to never block.
export function runSweepCheck(_root, _pr, _rideOpts) {
  return { ok: true };
}

// evaluateLane(lane, ctx) — lane-level codes in P10 order. `kind_not_in_lane`
// and `requester_approval_missing` (Spec-AC-07) are real. The rest
// (intake_type, roadmap_capability, ceremony_exceeds, validation_not_pass,
// review_not_pass, pr_body_missing) are TODO: Spec-AC-11/15 (later
// batches); they slot into P10 order between these two checks and never
// deny in this batch. A lane with no requester_logins skips the requester
// check (it is only "WHEN a lane lists requester_logins", Spec-AC-07).
export function evaluateLane(lane, ctx) {
  const kinds = Array.isArray(lane.kinds) ? lane.kinds : [];
  if (!kinds.some((k) => ctx.kinds.has(k))) {
    return { ok: false, reason: 'kind_not_in_lane' };
  }
  const logins = Array.isArray(lane.requester_logins) ? lane.requester_logins : [];
  if (logins.length > 0 && !requesterApproved(ctx.reviews, logins, ctx.headOid)) {
    return { ok: false, reason: 'requester_approval_missing' };
  }
  return { ok: true };
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const out = {
    mode: null, pr: null, path: null, repoRoot: null, filesFrom: null, debugInputs: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') out.mode = 'check';
    else if (a === '--validate') out.mode = 'validate';
    else if (a === '--classify') out.mode = 'classify';
    else if (a === '--pr') out.pr = argv[++i];
    else if (a === '--path') out.path = argv[++i];
    else if (a === '--repo-root') out.repoRoot = argv[++i];
    else if (a === '--files-from') out.filesFrom = argv[++i];
    else if (a === '--debug-inputs') out.debugInputs = true;
  }
  return out;
}

function getPrJson(root, pr) {
  const fields = 'number,state,isDraft,baseRefName,baseRefOid,headRefOid,reviews,statusCheckRollup,body';
  const raw = execFileSync('gh', ['pr', 'view', String(pr), '--json', fields], {
    cwd: root, encoding: 'utf8',
  });
  return JSON.parse(raw);
}

function getChangedFiles(root, base, head) {
  const out = execFileSync('git', ['diff', '--name-only', '--no-renames', `${base}...${head}`], {
    cwd: root, encoding: 'utf8',
  });
  const files = out.split('\n').map((s) => s.trim()).filter(Boolean);
  return files.length ? files : ['-'];
}

function printLaneErrors(errors) {
  for (const e of errors) console.log(`lane=${e.lane ?? '-'} reason=${e.code}`);
}

function runCheck(opts) {
  const pr = Number(opts.pr);
  if (!Number.isInteger(pr) || pr <= 0) {
    process.stderr.write(`merge-policy: --check requires a positive integer --pr, got ${JSON.stringify(opts.pr)}\n`);
    exit(EXIT_USAGE);
  }
  const root = opts.repoRoot;

  let prJson;
  try {
    prJson = getPrJson(root, pr);
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=api_unavailable`);
    exit(EXIT_DENIED);
  }

  const base = prJson.baseRefOid;
  const head = prJson.headRefOid;

  // GUARD_PATHS wins over EVERYTHING, including whether a policy exists at
  // all at the base (P4: "even when every other condition holds") — so the
  // changed-file diff and its guard check run before the no_policy decision.
  let files;
  try {
    files = getChangedFiles(root, base, head);
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=base_unavailable`);
    exit(EXIT_DENIED);
  }
  const guardCheck = classifyFiles(files, { architecture: [], kinds: [] });
  if (guardCheck.denyReason === 'policy_touched') {
    console.log(`MERGE-POLICY denied pr=${pr} reason=policy_touched path=${guardCheck.path}`);
    exit(EXIT_DENIED);
  }

  let policyText;
  try {
    policyText = readAtBase(root, base, POLICY_PATH);
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=base_unavailable`);
    exit(EXIT_DENIED);
  }
  if (policyText == null) {
    console.log(`MERGE-POLICY no_policy pr=${pr}`);
    exit(EXIT_NO_POLICY);
  }

  const parsed = parsePolicy(policyText);
  if (parsed.errors) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=policy_invalid`);
    printLaneErrors(parsed.errors);
    exit(EXIT_DENIED);
  }
  const policy = parsed.policy;

  let decisionsText;
  try {
    decisionsText = readAtBase(root, base, 'docs/ai/decisions.jsonl');
  } catch {
    console.log(`MERGE-POLICY denied pr=${pr} reason=base_unavailable`);
    exit(EXIT_DENIED);
  }

  const validation = validatePolicy(policy, decisionsText || '');
  if (validation.errors) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=policy_invalid`);
    printLaneErrors(validation.errors);
    exit(EXIT_DENIED);
  }

  if (prJson.state !== 'OPEN' || prJson.isDraft === true) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=pr_not_open`);
    exit(EXIT_DENIED);
  }

  const classification = classifyFiles(files, policy);
  if (classification.denyReason) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=${classification.denyReason} path=${classification.path}`);
    exit(EXIT_DENIED);
  }

  if (!ciGreen(prJson.statusCheckRollup)) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=ci_not_green`);
    exit(EXIT_DENIED);
  }

  const sweep = runSweepCheck(root, pr, opts);
  if (!sweep.ok) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=${sweep.denyReason || 'sweep_check_failed'}`);
    exit(EXIT_DENIED);
  }

  if (opts.debugInputs) {
    // TODO: Spec-AC-11 (later batch) — resolve the real ceremony/intake/ref
    // ride inputs (lane-gate.mjs seam, S2). Stubbed placeholder for now.
    console.log(`ceremony=${DEFAULT_MAX_CEREMONY} intake_type=- ref=-`);
  }

  const ctx = { kinds: classification.kinds, reviews: prJson.reviews, headOid: head, body: prJson.body || '' };
  const laneLines = [];
  let allowedLane = null;
  for (const lane of policy.lanes) {
    const verdict = evaluateLane(lane, ctx);
    if (verdict.ok) { allowedLane = lane; break; }
    laneLines.push(`lane=${lane.id} reason=${verdict.reason}`);
  }

  if (!allowedLane) {
    console.log(`MERGE-POLICY denied pr=${pr} reason=no_lane_matched`);
    for (const l of laneLines) console.log(l);
    exit(EXIT_DENIED);
  }

  console.log(`MERGE-POLICY allowed pr=${pr} lane=${allowedLane.id} marker=${allowedLane.marker} `
    + `decision_ref=${allowedLane.decision_ref} merge_reaches=${allowedLane.merge_reaches}`);
  exit(EXIT_ALLOWED);
}

function runValidate(opts) {
  const root = opts.repoRoot;
  const policyPath = opts.path ? resolve(opts.path) : resolve(root, POLICY_PATH);
  if (!existsSync(policyPath)) {
    exit(EXIT_NO_POLICY);
  }
  const text = readFileSync(policyPath, 'utf8');
  const parsed = parsePolicy(text);
  if (parsed.errors) {
    for (const e of parsed.errors) console.log(`INVALID lane=${e.lane ?? '-'} code=${e.code}`);
    exit(1);
  }
  const decisionsPath = resolve(root, DECISIONS_PATH);
  const decisionsText = existsSync(decisionsPath) ? readFileSync(decisionsPath, 'utf8') : '';
  const validation = validatePolicy(parsed.policy, decisionsText);
  if (validation.errors) {
    for (const e of validation.errors) console.log(`INVALID lane=${e.lane ?? '-'} code=${e.code}`);
    exit(1);
  }
  console.log(`VALID lanes=${parsed.policy.lanes.length}`);
  exit(EXIT_ALLOWED);
}

function runClassify(opts) {
  const root = opts.repoRoot;
  const policyPath = opts.path ? resolve(opts.path) : resolve(root, POLICY_PATH);
  if (!existsSync(policyPath)) {
    process.stderr.write(`merge-policy: --classify policy not found: ${policyPath}\n`);
    exit(EXIT_USAGE);
  }
  const parsed = parsePolicy(readFileSync(policyPath, 'utf8'));
  if (parsed.errors) {
    for (const e of parsed.errors) console.log(`INVALID lane=${e.lane ?? '-'} code=${e.code}`);
    exit(1);
  }
  let listText;
  if (!opts.filesFrom) {
    process.stderr.write('merge-policy: --classify requires --files-from\n');
    exit(EXIT_USAGE);
  }
  listText = opts.filesFrom === '-' ? readFileSync(0, 'utf8') : readFileSync(opts.filesFrom, 'utf8');
  const files = listText.split('\n').map((s) => s.trim()).filter(Boolean);
  for (const f of files) {
    const single = classifyFiles([f], parsed.policy);
    const cls = single.denyReason ? single.denyReason : [...single.kinds][0];
    console.log(`${f} ${cls}`);
  }
  exit(EXIT_ALLOWED);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  opts.repoRoot = resolve(opts.repoRoot || DEFAULT_REPO_ROOT);
  if (opts.mode === 'check') return runCheck(opts);
  if (opts.mode === 'validate') return runValidate(opts);
  if (opts.mode === 'classify') return runClassify(opts);
  process.stderr.write('merge-policy: one of --check --pr <n> | --validate | --classify is required\n');
  exit(EXIT_USAGE);
}

// Guard the CLI entry so this module can be `import()`ed for its exported
// functions/constants (TEST-1507's import-closure probe does exactly that)
// without the side effect of actually running main() and calling exit().
if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  runMain(() => main());
}
