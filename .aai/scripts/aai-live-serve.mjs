#!/usr/bin/env node
// aai-live-serve.mjs — a locally served live dashboard: what every agent does,
// what waits on the owner, and for how long. SPEC live-agent-dashboard-served-locally.
//
// Loopback only. Node stdlib only. Zero LLM tokens. Writes nothing under the
// repository — its only writes go to os.tmpdir() (the cached live-status run).
//
// Sources, each REUSED through its own CLI so there is one parser per truth:
//   roles    heartbeat.mjs read --json   (slots: role, ref_id, message, updated_at, age_seconds)
//   waiting  docs/ai/STATE.yaml human_input block (required / question / blocking_reason)
//   live     generate-live-status.mjs --data-only (harnesses, live_sessions, spend), cached
//
// Usage:
//   node .aai/scripts/aai-live-serve.mjs [--port 7331] [--host 127.0.0.1]
//     [--heartbeat-dir <dir>] [--state <STATE.yaml>] [--no-live-status]
//     [--live-status-interval <seconds, default 30>]
// Exit: 0 on SIGINT/SIGTERM · 1 port busy · 2 usage / non-loopback host.

import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const HEARTBEAT = path.join(HERE, 'heartbeat.mjs');
const LIVE_STATUS = path.join(HERE, 'generate-live-status.mjs');
const STALE_AFTER_S = 120;      // a heartbeat older than this is shown as stale, never hidden
const POLL_MS = 5000;           // the page's own refresh; Spec-AC-04

function parseArgs(argv) {
  const a = { port: 7331, host: '127.0.0.1', heartbeatDir: null, state: path.join(ROOT, 'docs/ai/STATE.yaml'), liveStatus: true, liveInterval: 30 };
  for (let i = 0; i < argv.length; i += 1) {
    const k = argv[i]; const v = argv[i + 1];
    if (k === '--port') { a.port = Number(v); i += 1; }
    else if (k === '--host') { a.host = String(v); i += 1; }
    else if (k === '--heartbeat-dir') { a.heartbeatDir = v; i += 1; }
    else if (k === '--state') { a.state = v; i += 1; }
    else if (k === '--no-live-status') { a.liveStatus = false; }
    else if (k === '--live-status-interval') { a.liveInterval = Number(v); i += 1; }
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
const LIVE_CACHE_FILE = path.join(os.tmpdir(), 'aai-live-status-index.json');
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

function buildData(a) {
  const roles = readRoles(a.heartbeatDir);
  const waiting = readWaiting(a.state);
  const live = a.liveStatus ? readLive(a.liveInterval) : { data: null, degraded: [] };
  return {
    generated_at: new Date().toISOString(),
    waiting: waiting.waiting,
    roles: roles.roles,
    live: live.data,
    stale_after_seconds: STALE_AFTER_S,
    degraded: [...roles.degraded, ...waiting.degraded, ...live.degraded],
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
table{border-collapse:collapse;width:100%}td,th{text-align:left;padding:5px 8px;border-bottom:1px solid #eee;font-size:13px}
th{color:#666;font-weight:600}tr.stale td{color:#999}tr.stale td.age{color:#b30000}
.muted{color:#888}.small{font-size:12px}
</style></head><body>
<h1>AAI live <span id="status" class="small">connecting…</span></h1>
<section id="waiting"><h2>Waits on you</h2><div id="waiting-body" class="card muted">loading…</div></section>
<section id="roles"><h2>Agents</h2><div id="roles-body" class="card muted">loading…</div></section>
<section id="live"><h2>Sessions &amp; spend</h2><div id="live-body" class="card muted small">loading…</div></section>
<section id="degraded" hidden><h2>Degraded</h2><div id="degraded-body" class="card small"></div></section>
<script>
const POLL_MS=${POLL_MS};let lastOk=null;
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const ago=s=>s<60?s+' s':s<3600?Math.round(s/60)+' min':Math.round(s/360)/10+' h';
function render(d){
  const w=document.getElementById('waiting-body');
  if(d.waiting){const since=Math.max(0,Math.round((Date.now()-Date.parse(d.waiting.since))/1000));
    w.className='card wait';w.innerHTML='<b>'+esc(d.waiting.question)+'</b>'+(d.waiting.blocking_reason?esc(d.waiting.blocking_reason)+' · ':'')+'waiting '+ago(since)+' <span class="muted">(since '+esc(d.waiting.since_source)+')</span>';}
  else{w.className='card muted';w.textContent='Nothing waits on you.';}
  const r=document.getElementById('roles-body');
  if(!d.roles.length){r.className='card muted';r.textContent='No agent has a live heartbeat.';}
  else{r.className='card';r.innerHTML='<table><tr><th>Role</th><th>Ride</th><th>Last message</th><th>Age</th></tr>'+d.roles.map(x=>'<tr class="'+(x.stale?'stale':'')+'"><td>'+esc(x.role)+'</td><td>'+esc(x.ref_id)+'</td><td>'+esc(x.message)+'</td><td class="age">'+ago(x.age_seconds)+(x.stale?' · stale':'')+'</td></tr>').join('')+'</table>';}
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

function main() {
  const a = parseArgs(process.argv.slice(2));
  if (a.help) { process.stdout.write('usage: node .aai/scripts/aai-live-serve.mjs [--port 7331] [--host 127.0.0.1] [--heartbeat-dir <dir>] [--state <STATE.yaml>] [--no-live-status] [--live-status-interval <s>]\n'); process.exit(0); }
  refuseUnlessLoopback(a.host);
  const srv = http.createServer((req, res) => {
    const url = (req.url || '/').split('?')[0];
    if (url === '/data.json') {
      let body; try { body = JSON.stringify(buildData(a)); } catch (e) { res.writeHead(500, { 'content-type': 'application/json' }); res.end(JSON.stringify({ error: String(e && e.message) })); return; }
      res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(body); return;
    }
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
