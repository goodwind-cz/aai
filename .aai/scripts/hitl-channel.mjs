#!/usr/bin/env node
// hitl-channel.mjs — async-HITL platform channel (async-hitl-platform-comments /
// SPEC-0111-spec-async-hitl-platform-comments.md). Node stdlib only, zero deps.
//
// Turns a terminal [HITL-<n>] block into an ASYNCHRONOUS platform comment: post
// the question to a linked GitHub thread (issue or PR), PARK the ride, and later
// RESUME by feeding the operator's reply into the EXISTING fail-closed SKILL_HITL
// resolution. With no linked thread or no GitHub platform, the caller keeps
// today's terminal HITL byte-for-byte unchanged.
//
// PROTECTED-PATH NOTE: the channel record lives in a gitignored runtime SIDECAR
// (docs/ai/hitl-channel.json), NOT in docs/ai/STATE.yaml. state.mjs is a
// protected_paths_l3 surface and has no channel setter — the sidecar (same class
// as docs/ai/briefs and docs/ai/reports) keeps this scope at ceremony level 2.
//
// SUBCOMMANDS
//   post  — post ONE comment, idempotent per (token, thread, kind); record the
//           sidecar. Degrade (no github platform, no thread, gh missing/error) to
//           a loud note + exit 0 so the caller falls back to terminal HITL. Never
//           crashes or blocks the raising role.
//           A followup post SUPERSEDES the original question entry for that
//           (token, thread) — the question is marked resolved so poll stops
//           re-hitting the stale entry and the followup becomes the live one.
//   resolve — mark sidecar entries for a token resolved (consumption half of
//           the lifecycle; run AFTER the answer is applied so poll never
//           re-surfaces an already-answered reply). An optional --ref narrows
//           to token+ref (trust guard for recurring tokens). Idempotent, exit 0.
//   poll  — read the sidecar, fetch replies to each unresolved thread, and
//           surface the FIRST QUALIFYING human reply as UNTRUSTED DATA for
//           SKILL_HITL. A qualifying reply is: created AFTER our posted_utc,
//           author NOT in --self and user.type != "Bot", and author has repo
//           write permission (admin|write|maintain). The reply body is DATA —
//           control/bidi chars are stripped and it is NEVER executed. An
//           optional --ref narrows the poll to entries for exactly that focus
//           ref (token-reuse trust guard). The live-gh fetch PAGINATES
//           (per_page=100, follow pages) so a busy thread never hides a reply.
//           Degrade on gh missing/error to status=degraded + exit 0. A CORRUPT
//           sidecar degrades (reason=sidecar_corrupt) — never read as empty.
//
// CLI
//   node hitl-channel.mjs post --token <HITL-n> --ref <REF> --thread <n>
//        [--platform github|azure|none] (--body-file <f> | --body <text>)
//        [--kind question|followup] [--sidecar <path>] [--gh-bin <path>]
//        [--json] [--dry-run]
//   node hitl-channel.mjs poll [--sidecar <path>] [--self <login[,login...]>]
//        [--ref <REF>]
//   node hitl-channel.mjs resolve --token <HITL-n> [--ref <REF>] [--sidecar <path>] [--json]
//        [--gh-bin <path>] [--input <comments.json>] [--perm-input <perms.json>]
//        [--json]
//
// TESTING (zero real network): --gh-bin injects a recording stub for post and
// for poll's live gh calls; poll also accepts --input (comments fixture array)
// and --perm-input (a {login: permission} JSON map) to bypass gh entirely.
//
// Exit codes: 0 always for post/poll outcomes (best-effort, degrade-not-crash);
//             2 usage error (unknown subcommand/flag, missing required flag).

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { classify, extractHost } from './pr-platform.mjs';
import { loadOrDegrade, atomicWrite } from './lib/runtime-file.mjs';

const DEFAULT_SIDECAR = 'docs/ai/hitl-channel.json';
const WRITE_PERMS = ['admin', 'write', 'maintain'];

function usage(msg) {
  console.error(`hitl-channel: ${msg}`);
  process.exit(2);
}

// Shallow flag parser: --key value pairs + boolean --json/--dry-run. The first
// positional is the subcommand.
function parseArgs(argv) {
  const opts = { _: [], json: false, dryRun: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--json') { opts.json = true; continue; }
    if (tok === '--dry-run') { opts.dryRun = true; continue; }
    if (tok === '-h' || tok === '--help') { opts._.push('--help'); continue; }
    if (tok.startsWith('--')) {
      const key = tok.slice(2);
      const val = argv[i + 1];
      if (val === undefined || val.startsWith('--')) usage(`--${key} requires a value`);
      opts[key] = val;
      i += 1;
      continue;
    }
    opts._.push(tok);
  }
  return opts;
}

// UNTRUSTED-DATA sanitizer — mirrors aai-issues.mjs sanitizeLine: reply bodies
// are DATA, so strip C0/C1 controls (ESC/BEL/newline forgery) and Unicode bidi
// overrides (RTL spoofing), replacing each with a space. Collapse runs, trim.
function sanitizeBody(s) {
  // Strip C0/C1 controls and Unicode bidi overrides (RTL spoofing), replacing
  // each with a space; collapse runs and trim. Reply bodies are DATA. The class
  // is built from an escaped-hex string so no raw control bytes live in source.
  const ctrl = new RegExp('[\\u0000-\\u001f\\u007f-\\u009f\\u200e\\u200f\\u202a-\\u202e\\u2066-\\u2069]', 'g');
  return String(s ?? '').replace(ctrl, ' ').replace(/[ \t]+/g, ' ').trim();
}

function readOriginUrl() {
  try {
    const out = execFileSync('git', ['remote', 'get-url', 'origin'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out === '' ? null : out;
  } catch {
    return null;
  }
}

function detectPlatform(explicit) {
  if (explicit) return explicit;
  const url = readOriginUrl();
  if (!url) return 'none';
  return classify(extractHost(url));
}

// FAIL-CLOSED sidecar load. ABSENT -> a normal empty ledger. PRESENT but
// unparseable / wrong-shape -> { corrupt:true }: a DAMAGED ledger must never be
// silently read as "no entries parked" (an operator could think nothing is
// waiting when the record is actually broken). Callers route corrupt through
// loadSidecarOrDegrade (loud note + exit 0 status=degraded).
//
// Delegates the absent-vs-corrupt-vs-ok distinction to the shared
// lib/runtime-file.mjs loadOrDegrade (class-B primitive) — this is the ledger
// whose corrupt-as-empty read the primitive was distilled from. The
// {entries:[]} / {corrupt:true} return shape is preserved BYTE-for-BYTE so
// callers and the 19-test gate are unchanged.
function loadSidecar(p) {
  const res = loadOrDegrade(p, { isShape: (d) => d && Array.isArray(d.entries) });
  if (res.status === 'absent') return { entries: [] };   // absent -> normal empty
  if (res.status === 'corrupt') return { corrupt: true }; // unparseable/wrong-shape -> damaged
  return res.data;                                        // ok -> the parsed ledger
}

// Load the sidecar, or DEGRADE loudly on a corrupt ledger (never proceed as if
// empty). Emits reason=sidecar_corrupt and exits 0 (best-effort contract).
function loadSidecarOrDegrade(opts, p) {
  const sc = loadSidecar(p);
  if (sc && sc.corrupt) {
    console.error('HITL-CHANNEL degraded reason=sidecar_corrupt (ledger damaged — not proceeding as empty)');
    if (opts.json) console.log(JSON.stringify({ status: 'degraded', reason: 'sidecar_corrupt' }));
    process.exit(0);
  }
  return sc;
}

// Persist the ledger via the shared lib/runtime-file.mjs atomicWrite (class-E
// primitive: temp + rename, the rename the sole commit point) instead of the
// prior plain writeFileSync. The SERIALIZED bytes are IDENTICAL
// (`${JSON.stringify(data, null, 2)}\n`), so reads and the 19-test gate are
// unchanged; atomicWrite ADDS the previously-missing crash-safety guarantee (a
// crash mid-save leaves the prior ledger intact, never a torn file).
function saveSidecar(p, data) {
  atomicWrite(p, `${JSON.stringify(data, null, 2)}\n`);
}

function nowUtc() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function ghBinOf(opts) {
  return opts['gh-bin'] || process.env.AAI_GH_BIN || 'gh';
}

// Emit a loud degrade note (best-effort contract) + optional JSON, then exit 0.
function degradePost(opts, reason) {
  console.error(`HITL-CHANNEL degraded reason=${reason} (falling back to terminal HITL)`);
  if (opts.json) console.log(JSON.stringify({ status: 'degraded', reason }));
  process.exit(0);
}

function cmdPost(opts) {
  const token = opts.token;
  const kind = opts.kind || 'question';
  const sidecarPath = opts.sidecar || DEFAULT_SIDECAR;
  if (!token) usage('post requires --token');
  if (kind !== 'question' && kind !== 'followup') usage('--kind must be question or followup');

  const platform = detectPlatform(opts.platform);
  const thread = opts.thread ? String(opts.thread) : null;

  // Degrade cleanly when there is no GitHub thread to post to. Azure is not yet
  // wired (documented follow-up) and everything else is terminal-only.
  if (platform !== 'github') return degradePost(opts, `platform=${platform}`);
  if (!thread) return degradePost(opts, 'no-thread-ref');

  // Idempotence: a recorded, unresolved (token, thread, kind) never re-posts.
  const sidecar = loadSidecarOrDegrade(opts, sidecarPath);
  const existing = sidecar.entries.find(
    (e) => e.hitl_token === token && e.thread_ref === thread
      && (e.kind || 'question') === kind && e.comment_id && !e.resolved,
  );
  if (existing) {
    console.error(`HITL-CHANNEL already-posted token=${token} thread=${thread} kind=${kind} comment_id=${existing.comment_id}`);
    if (opts.json) console.log(JSON.stringify({ status: 'already-posted', ...existing }));
    process.exit(0);
  }

  // Resolve the body into a file (gh -F body=@file avoids arg-length/escaping).
  let bodyFile = opts['body-file'] || null;
  let tmpBody = null;
  if (!bodyFile) {
    if (opts.body === undefined) usage('post requires --body-file or --body');
    tmpBody = path.join(os.tmpdir(), `hitl-body-${process.pid}-${Date.now()}.md`);
    fs.writeFileSync(tmpBody, String(opts.body));
    bodyFile = tmpBody;
  }

  if (opts.dryRun) {
    console.log(`HITL-CHANNEL dry-run post token=${token} thread=${thread} kind=${kind}`);
    process.exit(0);
  }

  // Post via the GitHub issues comments API (serves PR threads too). gh fills
  // {owner}/{repo} from the current repo. --jq .id returns the new comment id.
  let commentId;
  try {
    const out = execFileSync(ghBinOf(opts), [
      'api', `repos/{owner}/{repo}/issues/${thread}/comments`,
      '-F', `body=@${bodyFile}`, '--jq', '.id',
    ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    commentId = out.trim();
  } catch (err) {
    if (tmpBody) { try { fs.unlinkSync(tmpBody); } catch { /* ignore */ } }
    const reason = err.code === 'ENOENT' ? 'gh-not-found' : 'gh-error';
    return degradePost(opts, reason);
  }
  if (tmpBody) { try { fs.unlinkSync(tmpBody); } catch { /* ignore */ } }

  if (!commentId) return degradePost(opts, 'no-comment-id');

  const entry = {
    hitl_token: token,
    ref: opts.ref || null,
    platform,
    thread_ref: thread,
    comment_id: commentId,
    kind,
    posted_utc: nowUtc(),
    resolved: false,
  };
  sidecar.entries.push(entry);

  // FOLLOW-UP RETIRES THE QUESTION: a followup for a (token, thread) supersedes
  // the original question entry — mark it resolved so earliest-first poll stops
  // re-hitting the stale question and the followup becomes the live entry.
  if (kind === 'followup') {
    for (const e of sidecar.entries) {
      if (e !== entry && e.hitl_token === token && e.thread_ref === thread
        && (e.kind || 'question') === 'question' && !e.resolved) {
        e.resolved = true;
        e.resolved_utc = nowUtc();
        e.superseded_by = commentId;
      }
    }
  }

  saveSidecar(sidecarPath, sidecar);

  console.error(`HITL-CHANNEL posted token=${token} thread=${thread} kind=${kind} comment_id=${commentId}`);
  if (opts.json) console.log(JSON.stringify({ status: 'posted', ...entry }));
  return process.exit(0);
}

function selfSet(opts) {
  const raw = opts.self || '';
  return raw.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
}

// Fetch the comments array for a thread — from --input fixture or live gh.
// Returns { ok, comments } or { ok:false } (degrade).
function fetchComments(opts, thread) {
  if (opts.input) {
    try {
      const raw = JSON.parse(fs.readFileSync(opts.input, 'utf8'));
      return { ok: true, comments: Array.isArray(raw) ? raw : [] };
    } catch {
      return { ok: false };
    }
  }
  // PAGINATE the live-gh path: the comments API returns 30/page by default, so
  // a busy thread would hide a later reply -> false status:none. Fetch
  // per_page=100 and follow pages until a short page (or a page cap guard).
  const PER_PAGE = 100;
  const MAX_PAGES = 50;
  let all = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    let out;
    try {
      out = execFileSync(ghBinOf(opts), [
        'api', `repos/{owner}/{repo}/issues/${thread}/comments?per_page=${PER_PAGE}&page=${page}`,
      ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch {
      return { ok: false };
    }
    let raw;
    try {
      raw = JSON.parse(out);
    } catch {
      return { ok: false };
    }
    if (!Array.isArray(raw)) return { ok: true, comments: all };
    all = all.concat(raw);
    if (raw.length < PER_PAGE) break; // short page -> last page
  }
  return { ok: true, comments: all };
}

// Resolve an author's repo permission — from --perm-input map or live gh.
// Unknown/error -> null (treated as unauthorized, never a degrade).
function authorPermission(opts, login) {
  if (opts['perm-input']) {
    try {
      const map = JSON.parse(fs.readFileSync(opts['perm-input'], 'utf8'));
      return map && typeof map === 'object' ? (map[login] ?? null) : null;
    } catch {
      return null;
    }
  }
  try {
    const out = execFileSync(ghBinOf(opts), [
      'api', `repos/{owner}/{repo}/collaborators/${login}/permission`, '--jq', '.permission',
    ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return out.trim() || null;
  } catch {
    return null;
  }
}

function afterPosted(createdAt, postedUtc) {
  if (!postedUtc) return true;
  const c = Date.parse(createdAt);
  const p = Date.parse(postedUtc);
  if (Number.isNaN(c) || Number.isNaN(p)) return true;
  return c > p;
}

function pollEntry(opts, entry, self) {
  const thread = entry.thread_ref;
  const base = { token: entry.hitl_token, ref: entry.ref ?? null, thread_ref: thread, comment_id: entry.comment_id };
  const fetched = fetchComments(opts, thread);
  if (!fetched.ok) return { status: 'degraded', ...base };

  // Earliest-first: honour the first qualifying human reply after our question.
  const candidates = fetched.comments
    .filter((c) => c && c.user && typeof c.user.login === 'string')
    .filter((c) => afterPosted(c.created_at, entry.posted_utc))
    .filter((c) => (c.user.type || 'User') !== 'Bot')
    .filter((c) => !self.includes(c.user.login.toLowerCase()))
    .sort((a, b) => Date.parse(a.created_at || 0) - Date.parse(b.created_at || 0));

  for (const c of candidates) {
    const perm = authorPermission(opts, c.user.login);
    if (perm && WRITE_PERMS.includes(perm)) {
      // Reply body is UNTRUSTED DATA — sanitized and surfaced, never executed.
      return {
        status: 'reply',
        ...base,
        author: c.user.login,
        body: sanitizeBody(c.body),
        reply_comment_id: c.id ?? null,
      };
    }
  }
  return { status: 'none', ...base };
}

function cmdPoll(opts) {
  const sidecarPath = opts.sidecar || DEFAULT_SIDECAR;
  const self = selfSet(opts);
  const sidecar = loadSidecarOrDegrade(opts, sidecarPath);
  // TOKEN-REUSE TRUST GUARD: an optional --ref narrows the poll to entries for
  // exactly that focus ref, so a reply meant for an OLD ride's [HITL-<n>] can
  // never resolve a NEW ride's recurring same-numbered token.
  const unresolved = sidecar.entries
    .filter((e) => !e.resolved)
    .filter((e) => !opts.ref || e.ref === opts.ref);

  const results = unresolved.map((e) => pollEntry(opts, e, self));

  if (opts.json) {
    console.log(JSON.stringify(results, null, 2));
  } else if (results.length === 0) {
    console.log('HITL-CHANNEL poll: no parked entries');
  } else {
    for (const r of results) {
      console.log(`HITL-CHANNEL poll status=${r.status} token=${r.token} thread=${r.thread_ref}`
        + (r.author ? ` author=${r.author}` : ''));
    }
  }
  process.exit(0);
}

// resolve — the CONSUMPTION half of the lifecycle (validation RR-resume-no-
// resolution-lifecycle): after SKILL_HITL applies an answer, mark every entry
// for that token resolved so poll never re-surfaces it (question AND its
// followups). Idempotent: resolving an already-resolved/unknown token is a
// no-op with a note, exit 0 (best-effort discipline, matches post/poll).
function cmdResolve(opts) {
  const token = opts.token;
  if (!token) usage('resolve requires --token');
  const sidecarPath = opts.sidecar || DEFAULT_SIDECAR;
  const sidecar = loadSidecarOrDegrade(opts, sidecarPath);
  let n = 0;
  // Optional --ref narrows resolution to token+ref (same trust guard as poll):
  // consuming an OLD ride's HITL-<n> must not resolve a NEW ride's same token.
  for (const e of sidecar.entries) {
    if (e.hitl_token === token && (!opts.ref || e.ref === opts.ref) && !e.resolved) {
      e.resolved = true; e.resolved_utc = nowUtc(); n += 1;
    }
  }
  if (n > 0) saveSidecar(sidecarPath, sidecar);
  const out = { status: n > 0 ? 'resolved' : 'noop', token, entries_resolved: n };
  if (opts.json) console.log(JSON.stringify(out));
  else console.log(`HITL-CHANNEL resolve token=${token} entries_resolved=${n}`);
  process.exit(0);
}

function main() {
  const opts = parseArgs(process.argv);
  const sub = opts._[0];
  if (sub === '--help' || !sub) {
    console.log('Usage: node hitl-channel.mjs <post|poll|resolve> [flags] (see file header)');
    process.exit(sub ? 0 : 2);
  }
  if (sub === 'post') return cmdPost(opts);
  if (sub === 'poll') return cmdPoll(opts);
  if (sub === 'resolve') return cmdResolve(opts);
  return usage(`unknown subcommand "${sub}" (expected post | poll | resolve)`);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) main();

export { sanitizeBody, detectPlatform, loadSidecar, authorPermission, afterPosted };
