#!/usr/bin/env node
// ride-status.mjs - read-only status view and already-done probe of the
// current ride (spec-ride-status-and-resume, RFC-0017 section 5 phase 4).
//
//   node .aai/scripts/ride-status.mjs [--json] [--state <p>] [--root <dir>]
//   node .aai/scripts/ride-status.mjs probe [--json] [--branch <b>] [--state <p>] [--root <dir>]
//
// Status prints six labelled lines (or one JSON object): ride, current action,
// evidence, blocker, next decision, decisions. The current action is copied
// from orchestration-dispatch.mjs buildSnapshot() + decide(); no rule logic is
// re-implemented here. Probe reports whether four external effects of the ride
// (pushed, pr_open, closed, flushed) already happened; it performs none.
//
// This file writes nothing in either mode. Child processes are `git` and the
// platform adapter only, always with argument arrays. Exit: 0 report printed,
// 2 usage error, 1 internal error. Node stdlib only (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { buildSnapshot, decide } from './orchestration-dispatch.mjs';
import { loadState, findBlock, readScalar, unquoteScalar } from './lib/state-engine.mjs';
import { parseFrontmatter } from './lib/docs-model.mjs';
import { resolvePlatform, createAdapter } from './lib/platform-adapter.mjs';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

function usage(msg) {
  process.stderr.write(`${msg ? `ride-status: ${msg}\n` : ''}Usage: ride-status [probe] [--json] [--state <path>] [--root <dir>] [--branch <b>]\n`);
  exit(2);
}

function parseArgs(argv) {
  const o = { probe: false, json: false, state: null, root: process.cwd(), branch: null };
  for (let i = 0; i < argv.length; i += 1) {
    const t = argv[i];
    if (t === 'probe' && i === 0) o.probe = true;
    else if (t === '--json') o.json = true;
    else if (t === '--state' || t === '--root' || (t === '--branch' && o.probe)) {
      const v = argv[i + 1];
      if (!v || v.startsWith('--')) usage(`${t} requires a value`);
      o[t.slice(2)] = v;
      i += 1;
    } else usage(`unknown argument "${t}"`);
  }
  return o;
}

// --- STATE readers (read-only; the engine's own scalar reader plus two shapes it lacks) ---

function readList(lines, blockKey, field) {
  const b = findBlock(lines, blockKey);
  if (!b) return [];
  for (let i = b.start + 1; i < b.end; i += 1) {
    const m = lines[i].match(new RegExp(`^  ${field}:\\s*(.*)$`));
    if (!m) continue;
    const inline = m[1].trim();
    if (inline.startsWith('[')) return inline.slice(1, -1).split(',').map((s) => unquoteScalar(s.trim())).filter(Boolean);
    const items = [];
    for (let j = i + 1; j < b.end; j += 1) {
      const it = lines[j].match(/^ {4}-\s+(.*)$/);
      if (!it) { if (lines[j].trim() === '' || lines[j].startsWith('#')) continue; break; }
      items.push(unquoteScalar(it[1].trim()));
    }
    return items;
  }
  return [];
}

function readText(lines, blockKey, field) {
  const b = findBlock(lines, blockKey);
  if (!b) return null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const m = lines[i].match(new RegExp(`^  ${field}:\\s*(.*)$`));
    if (!m) continue;
    const v = m[1].trim();
    if (/^[>|]/.test(v)) {
      const parts = [];
      for (let j = i + 1; j < b.end && (lines[j].trim() === '' || /^ {3,}/.test(lines[j])); j += 1) parts.push(lines[j].trim());
      return parts.join(' ').trim() || null;
    }
    return v === '' || v === 'null' ? null : unquoteScalar(v);
  }
  return null;
}

const asList = (v) => (Array.isArray(v) ? v.map(String) : (v == null || v === '' ? [] : [String(v)]));

function readDoc(root, rel) {
  if (!rel) return null;
  try { return parseFrontmatter(fs.readFileSync(path.resolve(root, rel), 'utf8')); } catch { return null; }
}

function countMutationRecords(root, specId) {
  if (!specId) return 0;
  try {
    return fs.readdirSync(path.resolve(root, 'docs/ai/tdd', specId)).filter((n) => /^mutation-TEST-.*\.txt$/.test(n)).length;
  } catch { return 0; }
}

// --- gather: one object holding everything both renderers need ---

function gather(o) {
  const root = path.resolve(o.root);
  const statePath = path.resolve(o.state ?? path.join(root, 'docs/ai/STATE.yaml'));
  const { snapshot, problems } = buildSnapshot(statePath, root);
  const lines = problems.length === 0 ? loadState(statePath).lines : [];
  let d;
  if (problems.length > 0) d = { verdict: 'needs_llm', rule: null, role: null, reasons: problems };
  else d = decide(snapshot);
  const focusRef = snapshot?.focus?.ref_id ?? null;
  const specPath = focusRef ? (snapshot.spec.path ?? null) : null;
  const fm = focusRef ? readDoc(root, specPath) : null;

  const vStatus = focusRef ? (readScalar(lines, 'last_validation', 'status') ?? 'none') : 'none';
  const vRef = focusRef ? readScalar(lines, 'last_validation', 'ref_id') : null;
  const review = focusRef
    ? { required: snapshot.review.required === true, status: snapshot.review.status ?? 'none', report_paths: readList(lines, 'code_review', 'report_paths') }
    : { required: false, status: 'none', report_paths: [] };
  const tddSpec = focusRef ? readScalar(lines, 'tdd_cycle', 'spec_path') : null;
  const tddOn = focusRef && tddSpec != null && tddSpec === specPath;
  let pr = [];
  if (focusRef) {
    pr = asList(fm?.links?.pr);
    if (pr.length === 0) pr = asList(readDoc(root, snapshot.focus.primary_path)?.links?.pr);
  }
  const stratRef = readScalar(lines, 'implementation_strategy', 'ref_id');
  return {
    root, statePath, snapshot, problems, lines, d, focusRef,
    view: {
      ref_id: focusRef,
      focus_type: focusRef ? snapshot.focus.type : null,
      spec_path: specPath,
      ceremony_level: focusRef ? snapshot.spec.ceremony_level : null,
      current_action: {
        phase: snapshot?.work_item?.phase ?? null, status: snapshot?.work_item?.status ?? null,
        verdict: d.verdict, rule: d.rule ?? null, role: d.role ?? null, reasons: d.reasons ?? [],
      },
      evidence: {
        validation: {
          status: vStatus, ref_id: vRef, for_focus: focusRef != null && vRef === focusRef,
          evidence_paths: focusRef ? readList(lines, 'last_validation', 'evidence_paths') : [],
        },
        code_review: review,
        tdd: {
          status: tddOn ? (readScalar(lines, 'tdd_cycle', 'status') ?? 'none') : 'none',
          test_id: tddOn ? readScalar(lines, 'tdd_cycle', 'test_id') : null,
          mutation_records: focusRef ? countMutationRecords(root, fm?.id) : 0,
        },
        pr,
      },
      blocker: blocker(problems, d, lines, vStatus, review.status),
      next_decision: nextDecision(problems, d, snapshot),
      decisions: {
        strategy: {
          selected: readScalar(lines, 'implementation_strategy', 'selected'), ref_id: stratRef,
          reused: focusRef != null && stratRef === focusRef,
        },
        worktree: {
          recommendation: readScalar(lines, 'worktree', 'recommendation'),
          user_decision: readScalar(lines, 'worktree', 'user_decision'), ref_binding: 'none',
        },
      },
    },
  };
}

// D4: closed, first match.
function blocker(problems, d, lines, vStatus, reviewStatus) {
  if (problems.length > 0) return { kind: 'state_invalid', detail: problems.join(',') };
  if (readScalar(lines, 'human_input', 'required') === 'true') {
    return { kind: 'human_input', detail: readText(lines, 'human_input', 'question') ?? readText(lines, 'human_input', 'blocking_reason') };
  }
  if (d.verdict === 'needs_llm') return { kind: 'needs_llm', detail: (d.reasons ?? []).join(',') };
  if (vStatus === 'fail') return { kind: 'failing_gate', detail: 'validation' };
  if (reviewStatus === 'fail') return { kind: 'failing_gate', detail: 'code_review' };
  return { kind: 'none', detail: null };
}

// D3: closed table, first match. The next action itself is the dispatcher's verdict.
function nextDecision(problems, d, snapshot) {
  const row = (actor, command, why) => ({ actor, command, why });
  if (problems.length > 0) return row('loop', '/aai-loop', 'the loop repairs STATE before its first tick');
  if (d.verdict === 'no_action' && d.rule === '1') return row('owner', '/aai-loop', 'project_status is paused; unpause it first');
  if (d.verdict === 'no_action' && d.rule === '2') return row('owner', '/aai-hitl', 'the recorded human question');
  if (d.verdict === 'dispatch' && d.rule === '8'
    && (snapshot.worktree?.recommendation === 'required' || snapshot.spec?.ceremony_level === 3)) {
    return row('owner', '/aai-worktree gate', 'protected isolation keeps its human gate');
  }
  if (d.verdict === 'no_action' && d.rule === '14') return row('loop', '/aai-pr', 'validation and review satisfied, metrics flushed: open the pull request');
  if (d.verdict === 'no_action' && (d.reasons ?? []).includes('scope_complete_no_open_intake')) {
    return row('owner', '/aai-ship', 'nothing open: state the next need');
  }
  if (d.verdict === 'dispatch') return row('loop', '/aai-loop', `dispatch of ${d.role} by rule ${d.rule}`);
  return row('loop', '/aai-loop', 'the loop takes the named edge');
}

// --- renderers ---

const orNone = (v) => (v == null || v === '' ? 'none' : v);

function renderStatus(v) {
  const a = v.current_action;
  const e = v.evidence;
  const reasons = a.reasons.length > 0 ? ` reasons=${a.reasons.join(',')}` : '';
  const val = e.validation;
  const valPart = `validation=${val.status}${val.ref_id && v.ref_id ? ` for ${val.ref_id}` : ''}${val.evidence_paths.length > 0 ? ` ${val.evidence_paths.join(',')}` : ''}`;
  const rev = e.code_review;
  const revPart = `review=${rev.status} required=${rev.required}${rev.report_paths.length > 0 ? ` ${rev.report_paths.join(',')}` : ''}`;
  const b = v.blocker;
  const n = v.next_decision;
  const s = v.decisions.strategy;
  const w = v.decisions.worktree;
  return [
    v.ref_id ? `ride: ${v.ref_id} (${orNone(v.focus_type)}) spec=${orNone(v.spec_path)} ceremony=${orNone(v.ceremony_level)}` : 'ride: none (no current focus)',
    `current action: phase=${orNone(a.phase)} status=${orNone(a.status)}; dispatcher: ${a.verdict} rule ${orNone(a.rule)} -> ${orNone(a.role)}${reasons}`,
    `evidence: ${valPart}; ${revPart}; tdd=${e.tdd.status} mutation_records=${e.tdd.mutation_records}; pr=${e.pr.length > 0 ? e.pr.join(',') : 'none'}`,
    `blocker: ${b.kind}${b.detail ? `: ${b.detail}` : ''}`,
    `next decision: ${n.actor}: ${n.command} - ${n.why}`,
    `decisions: strategy=${orNone(s.selected)} ref=${orNone(s.ref_id)} reused=${s.reused}; worktree=${orNone(w.recommendation)}/${orNone(w.user_decision)} ref_binding=${w.ref_binding}`,
  ].join('\n');
}

// --- probe (D7) ---

function gitOut(root, args) {
  return execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 20000, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' } }).trim();
}

function probePushed(root, branch) {
  if (!branch) return { state: 'unknown', detail: 'no branch (detached HEAD)' };
  try { gitOut(root, ['remote', 'get-url', 'origin']); } catch { return { state: 'unknown', detail: 'no origin remote' }; }
  let remote;
  try { remote = gitOut(root, ['ls-remote', 'origin', `refs/heads/${branch}`]); } catch { return { state: 'unknown', detail: 'git ls-remote origin failed' }; }
  if (remote === '') return { state: 'not_done', detail: `remote branch ${branch} absent` };
  const remoteSha = remote.split(/\s+/)[0];
  let localSha;
  try { localSha = gitOut(root, ['rev-parse', branch]); } catch { return { state: 'unknown', detail: `local branch ${branch} does not resolve` }; }
  if (remoteSha === localSha) return { state: 'done', detail: remoteSha };
  return { state: 'not_done', detail: `remote ${remoteSha} local ${localSha}` };
}

function probePrOpen(root, branch) {
  if (!branch) return { state: 'unknown', detail: 'no branch (detached HEAD)', prs: [] };
  const { platform } = resolvePlatform({ repoRoot: root });
  if (!platform) return { state: 'skipped', detail: 'platform unknown or invalid', prs: [] };
  let r;
  try { r = createAdapter(platform, { cwd: root }).listDependents(branch, 'head'); } catch (err) { return { state: 'unknown', detail: String(err.message ?? err), prs: [] }; }
  if (r.skip) return { state: 'skipped', detail: r.reason ?? 'platform_generic', prs: [] };
  if (!r.ok) return { state: 'unknown', detail: r.reason ?? 'read_failed', prs: [] };
  if (r.value.length === 0) return { state: 'not_done', detail: 'no open pull request for the branch', prs: [] };
  return { state: 'done', detail: `listed ${r.value.join(',')}`, prs: r.value };
}

function probe(o) {
  const g = gather(o);
  let branch = o.branch;
  if (branch == null) { try { branch = gitOut(g.root, ['branch', '--show-current']) || null; } catch { branch = null; } }
  const snap = g.snapshot;
  let closed;
  let flushed;
  if (g.problems.length > 0) {
    closed = { state: 'unknown', detail: 'STATE invalid' };
    flushed = { state: 'unknown', detail: 'STATE invalid' };
  } else if (!g.focusRef) {
    closed = { state: 'not_applicable', detail: 'no focus' };
    flushed = { state: 'not_applicable', detail: 'no focus' };
  } else {
    closed = { state: snap.close_event_present && !snap.close_event_superseded_by_reopen ? 'done' : 'not_done', detail: null };
    flushed = { state: snap.flushed ? 'done' : 'not_done', detail: null };
  }
  return { ref_id: g.focusRef, branch, effects: { pushed: probePushed(g.root, branch), pr_open: probePrOpen(g.root, branch), closed, flushed } };
}

function renderProbe(p) {
  const out = [`probe: ${orNone(p.ref_id)} branch=${orNone(p.branch)}`];
  for (const [name, e] of Object.entries(p.effects)) out.push(`${name}: ${e.state}${e.detail ? ` ${e.detail}` : ''}`);
  return out.join('\n');
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  if (o.probe) {
    const p = probe(o);
    process.stdout.write(`${o.json ? JSON.stringify(p) : renderProbe(p)}\n`);
  } else {
    const { view } = gather(o);
    process.stdout.write(`${o.json ? JSON.stringify(view) : renderStatus(view)}\n`);
  }
  exit(0);
}

runMain(() => main(), { onError(err) { process.stderr.write(`ride-status: ${err.stack}\n`); process.exitCode = 1; } });
