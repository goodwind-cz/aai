#!/usr/bin/env node
// aai-live-serve.mjs — a locally served live dashboard: what every agent does,
// what waits on the owner, and for how long. SPEC live-agent-dashboard-served-locally.
//
// Loopback only. Node stdlib only. Zero LLM tokens. The ONE file it writes under
// the repository is the gitignored answer ledger docs/ai/hitl-answers.jsonl
// (POST /answer); its other writes go to os.tmpdir(). It never writes
// docs/ai/STATE.yaml, a protected L3 surface.
//
// Sources, each REUSED through its own CLI so there is one parser per truth:
//   roles    heartbeat.mjs read --json   (slots: role, ref_id, message, updated_at, age_seconds)
//   waiting  docs/ai/STATE.yaml human_input block (required / question / blocking_reason)
//   sweep    tests/skills/results/test-<stamp>/ — the framework writes one
//            *.result per finished suite, so the longest job in the factory
//            (~30 min) already publishes its progress; the page just reads it.
//   answer   POST /answer -> docs/ai/hitl-answers.jsonl (gitignored). The page is
//            a SECOND TRANSPORT for the existing async-HITL channel: hitl-channel
//            poll surfaces the record in the same shape a GitHub reply produces,
//            so SKILL_HITL needs no change. STATE.yaml is protected L3 and is
//            NEVER written here — clearing human_input stays SKILL_HITL's job.
//   live     generate-live-status.mjs --data-only (harnesses, live_sessions, spend), cached
//
// Usage:
//   node .aai/scripts/aai-live-serve.mjs [--port 7331] [--host 127.0.0.1]
//     [--heartbeat-dir <dir>] [--state <STATE.yaml>] [--answers <path>]
//     [--results-dir <dir>] [--no-live-status]
//     [--live-status-interval <seconds, default 30>]
// Exit: 0 on SIGINT/SIGTERM · 1 port busy · 2 usage / non-loopback host.

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { sanitizeBody as sanitizeAnswer } from './hitl-channel.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const HEARTBEAT = path.join(HERE, 'heartbeat.mjs');
const LIVE_STATUS = path.join(HERE, 'generate-live-status.mjs');
const STALE_AFTER_S = 120;      // a heartbeat older than this is shown as stale, never hidden
const POLL_MS = 5000;           // the page's own refresh; Spec-AC-04
const ANSWER_MAX_BYTES = 4096;  // D4: a decision is a sentence, not an upload
const DEFAULT_ANSWERS = 'docs/ai/hitl-answers.jsonl';
const SWEEP_RESULTS_DIR = 'tests/skills/results';

// SPLIT (validation round 2, under the owner's two-round cap). The option
// parser left this scope and ships as its own ride. Round 1 caught it
// fabricating buttons out of prose; the round-1 anchor fix then silently
// DROPPED real options phrased as questions — and the operator contract's own
// shape is "a question is a menu". Two rounds is the cap, so the page serves
// the free-text box here, which is D5's documented no-options fallback and
// needs no new code.

// AC-004 says the SAME predicate as the GitHub path, so `sanitizeAnswer` is
// IMPORTED (top of file) rather than re-typed: a copy is two predicates that
// can drift, and the AC would be false the day they did.

function parseArgs(argv) {
  const a = { port: 7331, host: '127.0.0.1', heartbeatDir: null, state: path.join(ROOT, 'docs/ai/STATE.yaml'), answers: path.join(ROOT, DEFAULT_ANSWERS), results: path.join(ROOT, SWEEP_RESULTS_DIR), liveStatus: true, liveInterval: 30 };
  // A flag that takes a value must HAVE one: `--state` as the last token used to
  // become the string "undefined" and read a file of that name.
  const need = (k, v) => { if (v === undefined || v.startsWith('--')) { process.stderr.write(`aai-live-serve: ${k} requires a value\n`); process.exit(2); } return v; };
  for (let i = 0; i < argv.length; i += 1) {
    const k = argv[i]; const raw = argv[i + 1];
    const v = ['--port', '--host', '--heartbeat-dir', '--state', '--live-status-interval', '--answers', '--results-dir'].includes(k) ? need(k, raw) : raw;
    if (k === '--port') { a.port = Number(v); i += 1; }
    else if (k === '--host') { a.host = String(v); i += 1; }
    else if (k === '--heartbeat-dir') { a.heartbeatDir = v; i += 1; }
    else if (k === '--state') { a.state = v; i += 1; }
    else if (k === '--no-live-status') { a.liveStatus = false; }
    else if (k === '--live-status-interval') { a.liveInterval = Number(v); i += 1; }
    else if (k === '--answers') { a.answers = need(k, raw); i += 1; }
    else if (k === '--results-dir') { a.results = need(k, raw); i += 1; }
    else if (k === '--help' || k === '-h') { a.help = true; }
    else { process.stderr.write(`aai-live-serve: unknown argument ${k}\n`); process.exit(2); }
  }
  if (!Number.isFinite(a.liveInterval) || a.liveInterval < 1) { process.stderr.write(`aai-live-serve: --live-status-interval must be a number of seconds >= 1\n`); process.exit(2); }
  if (!Number.isInteger(a.port) || a.port < 1 || a.port > 65535) { process.stderr.write(`aai-live-serve: --port must be 1..65535\n`); process.exit(2); }
  return a;
}

// D1 — loopback or refuse. There is no flag that widens this.
const LOOPBACK = new Set(['127.0.0.1', 'localhost', '::1']);
function refuseUnlessLoopback(host) {
  if (LOOPBACK.has(host)) return;
  process.stderr.write(`aai-live-serve: refusing to bind ${host} — this page shows live agent state and is loopback only (127.0.0.1)\n`);
  process.exit(2);
}

// --- roles: heartbeat slots through heartbeat.mjs, never a second parser ------
function readRoles(heartbeatDir) {
  const args = [HEARTBEAT, 'read', '--json'];
  if (heartbeatDir) args.push('--dir', heartbeatDir);
  const r = spawnSync(process.execPath, args, { encoding: 'utf8', timeout: 5000 });
  if (r.status !== 0) return { roles: [], degraded: [`heartbeat read failed: ${(r.stderr || '').trim() || `exit ${r.status}`}`] };
  let parsed; try { parsed = JSON.parse(r.stdout); } catch { return { roles: [], degraded: ['heartbeat read produced no JSON'] }; }
  const roles = (parsed.slots || []).map((s) => ({
    role: s.role, ref_id: s.ref_id, message: s.message, updated_at: s.updated_at,
    age_seconds: s.age_seconds, stale: Number(s.age_seconds) > STALE_AFTER_S, worktree: s.worktree,
  })).sort((x, y) => x.age_seconds - y.age_seconds);
  return { roles, degraded: parsed.degraded || [] };
}

// --- waiting: the human_input block of STATE.yaml, line-level, no YAML lib ------
// Only the three keys the block defines are read; anything else is ignored.
function focusRef(stateText) {
  const m = /^current_focus:\n(?:[ \t]+.*\n)*?[ \t]+ref_id:[ \t]*(.+)$/m.exec(stateText);
  return m ? m[1].trim().replace(/^["']|["']$/g, '') : null;
}
function readWaiting(statePath) {
  let text; let stat;
  try { text = fs.readFileSync(statePath, 'utf8'); stat = fs.statSync(statePath); } catch { return { waiting: null, degraded: [`STATE not readable: ${statePath}`] }; }
  // CRLF-tolerant: a Windows-edited STATE must not silently read as "no wait".
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const start = lines.findIndex((l) => /^human_input:\s*$/.test(l));
  if (start < 0) return { waiting: null, degraded: [] };
  const block = {};
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^\S/.test(line)) break;                       // next top-level key
    const m = /^  ([a-z_]+):\s*(.*)$/.exec(line);
    if (!m) continue;
    let v = m[2].trim();
    // Block scalars. `state.mjs set-human-input` writes `question: >-` (folded,
    // strip) and the continuation lines carry the text; reading only the header
    // line rendered every real HITL as ">-". `>`/`>-` fold with spaces, `|`/`|-`
    // keep newlines; the chomping indicator only affects a trailing newline.
    const bm = /^([>|])([+-]?)$/.exec(v);
    if (bm) {
      const parts = [];
      let j = i + 1;
      while (j < lines.length && (/^    /.test(lines[j]) || lines[j].trim() === '')) { parts.push(lines[j].replace(/^    /, '')); j += 1; }
      while (parts.length && parts[parts.length - 1].trim() === '') parts.pop();
      v = bm[1] === '>' ? parts.join(' ').replace(/ {2,}/g, ' ').trim() : parts.join('\n');
      i = j - 1;
    } else if (v === 'null' || v === '') v = null;
    else if (v === 'true') v = true; else if (v === 'false') v = false;
    else if (/^".*"$/.test(v) || /^'.*'$/.test(v)) v = v.slice(1, -1);
    block[m[1]] = v;
  }
  if (block.required !== true) {
    const unparsed = block.required === undefined && lines.slice(start + 1).some((l) => /^  \S/.test(l));
    return { waiting: null, degraded: unparsed ? ['human_input block present but its `required` key could not be read — treated as no wait'] : [] };
  }
  return {
    waiting: {
      question: block.question, blocking_reason: block.blocking_reason,
      options: [],   // see the SPLIT note above
      // ORCHESTRATION_HITL stamps the token into blocking_reason as [HITL-<n>];
      // the ref is the focus the block belongs to. Both may be absent (a
      // hand-written block), and POST /answer only ENFORCES a match when the
      // live block actually carries one.
      token: ((/\[(HITL-\d+)\]/.exec(`${block.blocking_reason || ''} ${block.question || ''}`) || [])[1]) || null,
      ref: focusRef(text),
      since: stat.mtime.toISOString(), since_source: 'STATE.yaml mtime (rewritten by every tick — an upper bound on the wait, not the wait itself)',
    },
    degraded: [],
  };
}

// --- live: the existing live-status generator, cached, written only to tmpdir --
const liveCache = { at: 0, data: null, degraded: [] };
// The generator's index cache defaults to <repo>/.aai/cache/live-status-index.json.
// It is gitignored, but D4 says the server writes NOTHING under the repository,
// so the cache is redirected to os.tmpdir(); it still persists across refreshes.
// One cache per repository: a fixed name would let two checkouts (or two
// concurrent servers of different repos) clobber each other's index.
const LIVE_CACHE_FILE = path.join(os.tmpdir(), `aai-live-status-index-${crypto.createHash('sha1').update(ROOT).digest('hex').slice(0, 12)}.json`);
const LIVE_SPAWN_TIMEOUT_MS = 20000;
// spend.today / spend.seven_day are arrays of per-project rows in live-status
// data; rendering them raw printed "[object Object]" (validation F4). Summarise
// to counts and, where a numeric field exists, a total.
function summariseSpend(spend) {
  if (!spend || typeof spend !== 'object') return null;
  const one = (v) => {
    if (Array.isArray(v)) {
      const num = v.map((r) => (r && typeof r === 'object' ? Number(r.tokens ?? r.total ?? r.usage ?? NaN) : Number(r))).filter((n) => Number.isFinite(n));
      return { entries: v.length, total: num.length ? num.reduce((a, b) => a + b, 0) : null };
    }
    if (typeof v === 'number') return { entries: 1, total: v };
    return null;
  };
  return { today: one(spend.today), seven_day: one(spend.seven_day) };
}
function readLive(intervalS) {
  const now = Date.now();
  // A failed run is cached for the same interval: without that, a broken scan
  // would be re-run on every 5 s poll instead of every 30 s.
  if ((liveCache.data || liveCache.degraded.length) && now - liveCache.at < intervalS * 1000) return liveCache;
  liveCache.at = now;
  let outDir = null;
  try {
    outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-live-'));
    const html = path.join(outDir, 'live-status.html');
    const r = spawnSync(process.execPath, [LIVE_STATUS, '--data-only', '--output', html, '--cache', LIVE_CACHE_FILE],
      { encoding: 'utf8', cwd: ROOT, timeout: LIVE_SPAWN_TIMEOUT_MS });
    const d = JSON.parse(fs.readFileSync(path.join(outDir, 'live-status-data.json'), 'utf8'));
    const sessions = d.live_sessions || [];
    liveCache.data = {
      generated_at: d.generatedAt,
      harnesses: (d.harnesses || []).map((h) => ({ id: h.id, available: h.available, sessions_total: h.sessions_total })),
      sessions_total: sessions.length,
      sessions_active: sessions.filter((s) => !/finished|idle/i.test(String(s.state))).length,
      spend: summariseSpend(d.spend),
    };
    liveCache.degraded = [...(d.degraded || []), ...(r.error ? [`live-status: ${r.error.code === 'ETIMEDOUT' ? 'timed out' : r.error.message}`] : [])];
  } catch (e) {
    liveCache.data = null;
    liveCache.degraded = [`live-status unavailable: ${e && e.code ? e.code : (e && e.message) || 'unknown'}`];
  } finally {
    if (outDir) { try { fs.rmSync(outDir, { recursive: true, force: true }); } catch { /* tmp only */ } }
  }
  return liveCache;
}

// SWEEP PROGRESS. The full test sweep is the longest-running job here and the
// page could not see it: it lists heartbeat slots, and aai-run-tests.sh writes
// none. The operator asked three times in one session whether anything was
// running and had to be answered with `pgrep`. No new plumbing is needed — the
// framework already writes one `<suite>.result` per finished suite into
// tests/skills/results/test-<stamp>/, so this reads what is already there.
// A run counts as ACTIVE while its newest file is younger than the stale
// window; older than that it is reported as finished-or-abandoned, never hidden.
const SWEEP_STALE_S = 300;
// Returns { data, degraded } — the same shape every other reader on this page
// uses. An earlier version returned a bare null on four different paths, so a
// single stray FILE named `test-…` in the results directory made the panel say
// "No sweep run on disk." with nothing in `degraded` to say why. A panel added
// to end blindness must not be the one reader that goes quiet (code review,
// 2026-09-06).
// A read that cannot hang. `readFileSync` on a FIFO or a character device
// blocks forever, and this runs inside every /data.json request — round-two
// review wedged the server with a `mkfifo`'d summary.txt and with a symlink to
// /dev/zero, which also grew memory without bound. Anything that is not a
// regular file, or is larger than the cap, is refused and NAMED.
const SWEEP_READ_CAP = 1 << 20;
function readSmallFile(f, degraded, label) {
  let st;
  try { st = fs.lstatSync(f); }
  catch (e) { if (e && e.code !== 'ENOENT') degraded.push(`sweep: ${label} unreadable (${(e && e.code) || 'error'})`); return null; }
  if (!st.isFile()) { degraded.push(`sweep: ${label} is not a regular file — ignored`); return null; }
  if (st.size > SWEEP_READ_CAP) { degraded.push(`sweep: ${label} is ${st.size} B, over the ${SWEEP_READ_CAP} B cap — ignored`); return null; }
  try { return fs.readFileSync(f, 'utf8'); }
  catch (e) { degraded.push(`sweep: ${label} unreadable (${(e && e.code) || 'error'})`); return null; }
}

function readSweep(base) {
  const degraded = [];
  const none = (why) => { if (why) degraded.push(why); return { data: null, degraded }; };
  let entries;
  try { entries = fs.readdirSync(base); } catch (e) {
    // A missing results directory is the ordinary state of a fresh checkout,
    // not a degrade; anything else is.
    return none(e && e.code === 'ENOENT' ? null : `sweep results unreadable at ${base} (${(e && e.code) || 'error'})`);
  }
  // WHICH RUN. The newest directory is the obvious choice and it is wrong on
  // its own: running one selected suite while a full sweep is in flight creates
  // a NEWER directory that finishes in seconds and publishes its own summary,
  // and the panel would then report "finished · 1 suite done" while the
  // thirty-minute sweep it was built to show carried on unseen (round-two
  // review). A run still in flight therefore wins over a finished one; among
  // equals, the newest.
  let newest = null; let newestLive = null;
  for (const r of entries) {
    if (!r.startsWith('test-')) continue;
    // A run is a DIRECTORY. statSync succeeds on a file too, and the readdir
    // below then throws ENOTDIR — which used to blank the whole panel.
    let st; try { st = fs.statSync(path.join(base, r)); } catch { continue; }
    if (!st.isDirectory()) { degraded.push(`sweep: ${r} is not a run directory — ignored`); continue; }
    const cand = { name: r, mtimeMs: st.mtimeMs };
    if (!newest || st.mtimeMs > newest.mtimeMs) newest = cand;
    const sum = readSmallFile(path.join(base, r, 'summary.txt'), degraded, `${r}/summary.txt`);
    const done = sum !== null && /^Total:\s+\d+/m.test(sum);
    const fresh = (Date.now() - st.mtimeMs) / 1000 < SWEEP_STALE_S;
    if (!done && fresh && (!newestLive || st.mtimeMs > newestLive.mtimeMs)) newestLive = cand;
  }
  if (newestLive) newest = newestLive;
  if (!newest) return none(null);
  const dir = path.join(base, newest.name);
  let names;
  try { names = fs.readdirSync(dir); }
  catch (e) { return none(`sweep: run ${newest.name} could not be read (${(e && e.code) || 'error'})`); }
  const results = names.filter((n) => n.endsWith('.result'));
  // The framework opens `<suite>.log` when a suite STARTS and writes
  // `<suite>.result` when it ends, so started-minus-done is the number in
  // flight right now. This is measured, not the expected total, which nothing
  // on disk states — during the first minutes of a parallel sweep it is the
  // only thing that distinguishes "running hard" from "wedged".
  const started = names.filter((n) => n.endsWith('.log')).length;
  let last = null; let lastAt = 0; let failed = 0;
  for (const n of results) {
    const f = path.join(dir, n);
    let st; try { st = fs.statSync(f); } catch { continue; }
    if (st.mtimeMs > lastAt) { lastAt = st.mtimeMs; last = n.replace(/\.result$/, ''); }
    // The framework writes exactly one verdict word (PASS | SKIP | FAIL) into
    // each file, so the verdict is compared exactly: a substring match would
    // count a SKIP whose text merely mentions failure, or any future log line.
    const body = readSmallFile(f, degraded, `${newest.name}/${n}`);
    if (body !== null && (body.split('\n')[0] || '').trim() === 'FAIL') failed += 1;
  }
  const ageS = lastAt ? Math.round((Date.now() - lastAt) / 1000) : null;
  // Liveness is measured from the newest THING the run produced, and for the
  // first minutes of a sweep that is the run directory itself: no suite has
  // finished yet, so there is no .result to date it by. Found by running this
  // against a real sweep — a run 40 seconds old reported `active: false`, which
  // is the exact blindness this panel exists to remove.
  const freshestMs = Math.max(lastAt, newest.mtimeMs);
  const activeAgeS = Math.round((Date.now() - freshestMs) / 1000);
  // A FINISHED run is finished the moment it says so, not five minutes later.
  // The framework writes the full summary (with its `Total:` line) only when the
  // run ends, so this is a fact on disk rather than a guess from timing — which
  // matters because a run whose last suite finished 30 seconds ago would
  // otherwise keep reading `running` for the rest of the stale window.
  const summary = readSmallFile(path.join(dir, 'summary.txt'), degraded, `${newest.name}/summary.txt`);
  const complete = summary !== null && /^Total:\s+\d+/m.test(summary);
  // The expected total is not published anywhere WHILE a run is in flight, so
  // it is NOT invented: the page reports started, done and failed — all
  // measured — and lets the reader judge.
  return { data: { run: newest.name, started, done: results.length, failed, last, last_age_seconds: ageS, complete, active: !complete && activeAgeS < SWEEP_STALE_S }, degraded };
}

function buildData(a) {
  const roles = readRoles(a.heartbeatDir);
  const waiting = readWaiting(a.state);
  const live = a.liveStatus ? readLive(a.liveInterval) : { data: null, degraded: [] };
  const sweep = readSweep(a.results);
  return {
    generated_at: new Date().toISOString(),
    waiting: waiting.waiting,
    roles: roles.roles,
    live: live.data,
    sweep: sweep.data,
    stale_after_seconds: STALE_AFTER_S,
    degraded: [...roles.degraded, ...waiting.degraded, ...live.degraded, ...sweep.degraded],
  };
}

// --- the page: one file, inline CSS + JS, polls /data.json -------------------
function page() {
  return `<!doctype html><html><head><meta charset="utf-8"><title>AAI live</title>
<style>
body{font:14px/1.4 system-ui,sans-serif;margin:0;padding:16px 20px;background:#f7f7f5;color:#222}
h1{font-size:16px;margin:0 0 12px}h2{font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:#666;margin:18px 0 6px}
#status{font-size:12px;color:#666}#status.stale{color:#b30000;font-weight:600}
.card{background:#fff;border:1px solid #e3e3df;border-radius:6px;padding:10px 12px;margin:6px 0}
.wait{border-color:#e0a000;background:#fff8e1}.wait b{display:block;font-size:15px;margin-bottom:4px}
#opts{margin:8px 0 4px}button{font:inherit;padding:5px 10px;margin:0 6px 6px 0;border:1px solid #c9c9c4;border-radius:5px;background:#fff;cursor:pointer}
button.rec{border-color:#2a7;box-shadow:inset 0 0 0 1px #2a7}.recmark{color:#2a7;font-size:11px}
#freeform input{font:inherit;padding:5px 8px;border:1px solid #c9c9c4;border-radius:5px;width:min(420px,60%)}
table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:5px 8px;border-bottom:1px solid #eee;font-size:13px}
th{color:#666;font-weight:600}tr.stale td{color:#999}tr.stale td.age{color:#b30000}
.muted{color:#888}.small{font-size:12px}
</style></head><body>
<h1>AAI live <span id="status" class="small">connecting…</span></h1>
<section id="waiting"><h2>Waits on you</h2><div id="waiting-body" class="card muted">loading…</div></section>
<section id="roles"><h2>Agents</h2><div id="roles-body" class="card muted">loading…</div></section>
<section id="sweep"><h2>Test sweep</h2><div id="sweep-body" class="card muted small">loading…</div></section>
<section id="live"><h2>Sessions &amp; spend</h2><div id="live-body" class="card muted small">loading…</div></section>
<section id="degraded" hidden><h2>Degraded</h2><div id="degraded-body" class="card small"></div></section>
<script>
const POLL_MS=${POLL_MS};let lastOk=null;
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const ago=s=>s<60?s+' s':s<3600?Math.round(s/60)+' min':Math.round(s/360)/10+' h';
function render(d){
  const w=document.getElementById('waiting-body');
  if(d.waiting){const since=Math.max(0,Math.round((Date.now()-Date.parse(d.waiting.since))/1000));
    const opts=(d.waiting.options||[]);
    w.className='card wait';
    w.innerHTML='<b>'+esc(d.waiting.question)+'</b>'+(d.waiting.blocking_reason?esc(d.waiting.blocking_reason)+' · ':'')+'waiting '+ago(since)+' <span class="muted">(since '+esc(d.waiting.since_source)+')</span>'
      +(opts.length?'<div id="opts">'+opts.map((o,i)=>'<button class="opt'+(o.recommended?' rec':'')+'" data-i="'+i+'">'+esc(o.text)+(o.recommended?' <span class="recmark">recommended</span>':'')+'</button>').join('')+'</div>':'')
      +'<div id="freeform"><input id="answer-text" type="text" placeholder="or type an answer…" maxlength="4000"><button id="answer-send">Send</button></div>'
      +'<div id="answer-status" class="small muted"></div>';
    const post=async(text)=>{
      const st=document.getElementById('answer-status');st.textContent='sending…';
      try{const r=await fetch('/answer',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({token:d.waiting.token,ref:d.waiting.ref,answer:text})});
        const j=await r.json();
        st.textContent=r.ok?('recorded — the loop picks it up on its next poll: '+esc(j.recorded.answer)):('refused: '+esc(j.error));
        st.className='small'+(r.ok?'':' stale');}
      catch(e){st.className='small stale';st.textContent='could not reach the server';}};
    opts.forEach((o,i)=>{const b=w.querySelector('button.opt[data-i="'+i+'"]');if(b)b.onclick=()=>post(o.text);});
    const send=document.getElementById('answer-send'),inp=document.getElementById('answer-text');
    if(send)send.onclick=()=>{const v=(inp.value||'').trim();if(v)post(v);};
    if(inp)inp.onkeydown=(e)=>{if(e.key==='Enter'){const v=(inp.value||'').trim();if(v)post(v);}};}
  else{w.className='card muted';w.textContent='Nothing waits on you.';}
  const r=document.getElementById('roles-body');
  if(!d.roles.length){r.className='card muted';r.textContent='No agent has a live heartbeat.';}
  else{r.className='card';r.innerHTML='<table><tr><th>Role</th><th>Ride</th><th>Last message</th><th>Age</th></tr>'+d.roles.map(x=>'<tr class="'+(x.stale?'stale':'')+'"><td>'+esc(x.role)+'</td><td>'+esc(x.ref_id)+'</td><td>'+esc(x.message)+'</td><td class="age">'+ago(x.age_seconds)+(x.stale?' · stale':'')+'</td></tr>').join('')+'</table>';}
  const sw=document.getElementById('sweep-body');
  if(!d.sweep){sw.className='card muted small';sw.textContent='No sweep run on disk.';}
  else{sw.className='card small';
    const inflight=Math.max(0,(d.sweep.started||0)-d.sweep.done);
    sw.innerHTML=(d.sweep.active?'<b>running</b> · ':(d.sweep.complete?'finished · ':'last run · '))+esc(d.sweep.done)+' suite(s) done'
      +(inflight?' · '+esc(inflight)+' in flight':'')
      +(d.sweep.failed?' · <span class="stale">'+esc(d.sweep.failed)+' failed</span>':'')
      +(d.sweep.last?' · newest '+esc(d.sweep.last)+' '+ago(d.sweep.last_age_seconds)+' ago':'')
      +' <span class="muted">('+esc(d.sweep.run)+')</span>';}
  const l=document.getElementById('live-body');
  if(!d.live){l.className='card muted small';l.textContent='Live-status scan disabled or unavailable.';}
  else{l.className='card small';l.innerHTML=esc(d.live.sessions_active)+' active of '+esc(d.live.sessions_total)+' sessions · harnesses: '+d.live.harnesses.map(h=>esc(h.id)+(h.available?'':' (absent)')).join(', ')+(d.live.spend&&d.live.spend.today?' · spend today: '+esc(d.live.spend.today.entries)+' project(s)'+(d.live.spend.today.total!=null?', '+esc(d.live.spend.today.total.toLocaleString())+' tokens':''):'');}
  const g=document.getElementById('degraded');
  if(d.degraded&&d.degraded.length){g.hidden=false;document.getElementById('degraded-body').innerHTML=d.degraded.map(esc).join('<br>');}else{g.hidden=true;}
}
async function poll(){
  const st=document.getElementById('status');
  try{const res=await fetch('/data.json',{cache:'no-store'});if(!res.ok)throw new Error(res.status);
    render(await res.json());lastOk=new Date();st.className='small';st.textContent='last refresh '+lastOk.toLocaleTimeString();}
  catch(e){st.className='small stale';st.textContent=lastOk?'stale since '+lastOk.toLocaleTimeString()+' (server not answering)':'server not answering — stale since page load';}
}
poll();setInterval(poll,POLL_MS);
</script></body></html>`;
}


// D4 — the one write surface. It refuses more than it accepts: loopback only
// (the server binds nowhere else), a 4 KB cap read as it streams, JSON only, a
// non-empty answer, a token/ref that matches the LIVE block, and 409 when
// nothing is pending — the page must not be able to manufacture a decision
// nobody asked for. On success it appends exactly one line to one gitignored
// file and writes nothing else, ever.
function handleAnswer(req, res, a) {
  const send = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(obj)); };

  // CSRF / DNS-REBINDING GUARDS. "Loopback only" is NOT a guard against the
  // browser: any page the operator has open can POST to 127.0.0.1, and a
  // `content-type: text/plain` body (CORS-safelisted, no preflight — also a
  // plain <form enctype="text/plain">) reaches this handler cross-site. Code
  // review proved it: 200 and a recorded answer from `Origin: https://evil…`.
  // Four checks, none of which the page's own fetch can fail:
  //   1. content-type must be application/json (a safelisted type cannot be)
  //   2. Origin, when sent, must be this very server
  //   3. Sec-Fetch-Site, when sent, must be same-origin
  //   4. Host must be loopback — a rebound DNS name is not this server
  const hdr = (n) => { const v = req.headers[n]; return Array.isArray(v) ? v[0] : (v || ''); };
  const ctype = hdr('content-type').split(';')[0].trim().toLowerCase();
  if (ctype !== 'application/json') return send(415, { error: `content-type must be application/json, got ${ctype || '(none)'}` });
  const hostOk = (h) => /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/i.test(h);
  const host = hdr('host');
  if (!hostOk(host)) return send(403, { error: `Host ${host || '(none)'} is not loopback — refusing (DNS rebinding)` });
  const origin = hdr('origin');
  if (origin) {
    let oh = '';
    try { oh = new URL(origin).host; } catch { oh = 'x'; }
    if (!hostOk(oh)) return send(403, { error: `cross-site request from ${origin} refused` });
  }
  const sfs = hdr('sec-fetch-site').toLowerCase();
  if (sfs && sfs !== 'same-origin' && sfs !== 'none') return send(403, { error: `Sec-Fetch-Site ${sfs} refused` });

  let size = 0; const chunks = [];
  let aborted = false;
  req.on('data', (c) => {
    if (aborted) return;
    size += c.length;
    if (size > ANSWER_MAX_BYTES) { aborted = true; send(400, { error: `answer body exceeds ${ANSWER_MAX_BYTES} bytes` }); req.destroy(); return; }
    chunks.push(c);
  });
  req.on('end', () => {
    if (aborted) return;
    let body;
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { return send(400, { error: 'body must be JSON' }); }
    if (!body || typeof body !== 'object') return send(400, { error: 'body must be a JSON object' });
    if (typeof body.answer !== 'string') return send(400, { error: `answer must be a string, got ${Array.isArray(body.answer) ? 'array' : typeof body.answer}` });
    const answer = sanitizeAnswer(body.answer);
    if (!answer) return send(400, { error: 'answer must be a non-empty string' });
    const w = readWaiting(a.state).waiting;
    if (!w) return send(409, { error: 'nothing waits on you — the dashboard cannot record a decision nobody asked for' });
    const token = typeof body.token === 'string' ? body.token : null;
    const ref = typeof body.ref === 'string' ? body.ref : null;
    if (token && w.token && token !== w.token) return send(400, { error: `token ${token} does not match the pending decision` });
    if (ref && w.ref && ref !== w.ref) return send(400, { error: `ref ${ref} does not match the pending decision` });
    // A record with no token can never be polled back (readLocalAnswers requires
    // a string token), so accepting it would tell the operator "recorded" and
    // then lose the decision in silence. Refuse instead — validation round 2.
    const finalToken = token || w.token || null;
    if (!finalToken) return send(409, { error: 'this pending decision carries no [HITL-n] token, so an answer could not be routed back to the loop — answer it in the terminal' });
    const rec = { v: 1, ts: new Date().toISOString(), token: finalToken, ref: ref || w.ref || null, answer, source: 'local-dashboard' };
    try {
      fs.mkdirSync(path.dirname(a.answers), { recursive: true });
      fs.appendFileSync(a.answers, `${JSON.stringify(rec)}\n`);
    } catch (e) {
      return send(500, { error: `could not record the answer: ${(e && e.code) || 'write failed'}` });
    }
    send(200, { recorded: rec });
  });
  req.on('error', () => { if (!aborted) send(400, { error: 'request failed' }); });
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  if (a.help) { process.stdout.write('usage: node .aai/scripts/aai-live-serve.mjs [--port 7331] [--host 127.0.0.1] [--heartbeat-dir <dir>] [--state <STATE.yaml>] [--answers <path>] [--results-dir <dir>] [--no-live-status] [--live-status-interval <s>]\n'); process.exit(0); }
  refuseUnlessLoopback(a.host);
  const srv = http.createServer((req, res) => {
    const url = (req.url || '/').split('?')[0];
    if (url === '/data.json') {
      let body; try { body = JSON.stringify(buildData(a)); } catch (e) { res.writeHead(500, { 'content-type': 'application/json' }); res.end(JSON.stringify({ error: String(e && e.message) })); return; }
      res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(body); return;
    }
    if (url === '/answer' && (req.method || 'GET').toUpperCase() === 'POST') { return handleAnswer(req, res, a); }
    if (url === '/') { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' }); res.end(page()); return; }
    res.writeHead(404, { 'content-type': 'text/plain' }); res.end('not found\n');
  });
  srv.on('error', (e) => {
    if (e && e.code === 'EADDRINUSE') { process.stderr.write(`aai-live-serve: port ${a.port} is busy — pick another with --port\n`); process.exit(1); }
    process.stderr.write(`aai-live-serve: ${e && e.message}\n`); process.exit(1);
  });
  const stop = () => { srv.close(() => process.exit(0)); setTimeout(() => process.exit(0), 1500).unref(); };
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
  srv.listen(a.port, a.host, () => { const shown = a.host === '::1' ? '[::1]' : a.host; process.stdout.write(`http://${shown}:${a.port}/\n`); });
}

main();
