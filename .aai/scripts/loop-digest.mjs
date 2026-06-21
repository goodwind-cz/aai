#!/usr/bin/env node
// AAI loop digest — a human-readable "wake-up" summary of the last autonomous run.
//
// Turns docs/ai/LOOP_TICKS.jsonl (machine telemetry) into one short report you can
// read in ten seconds: how many ticks ran, what moved, whether recovery fired, how
// it stopped, cost if recorded, and the branch left for review. This is the
// "chat-as-dashboard" outcome — you review pre-completed work instead of babysitting.
//
// Usage:
//   node .aai/scripts/loop-digest.mjs            # print markdown digest of the last run
//   node .aai/scripts/loop-digest.mjs --write    # also save to docs/ai/reports/loop-digest-<stamp>.md
//   node .aai/scripts/loop-digest.mjs --json      # emit structured JSON instead of markdown
//
// Read-only except for --write. Safe to run any time, including from a scheduler.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const ROOT = process.cwd();
const TICK_LOG = path.join(ROOT, 'docs/ai/LOOP_TICKS.jsonl');

const args = process.argv.slice(2);
const WRITE = args.includes('--write');
const JSON_OUT = args.includes('--json');

function git(cmdArgs) {
  try {
    return execFileSync('git', cmdArgs, { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

function readEvents() {
  if (!fs.existsSync(TICK_LOG)) return [];
  return fs
    .readFileSync(TICK_LOG, 'utf8')
    .split('\n')
    .filter((l) => l.trim())
    .map((l) => {
      try {
        return JSON.parse(l);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

// The last "run" = everything from the final tick numbered 1 onward. Tick numbers
// reset to 1 each run, so that boundary delimits the most recent run cleanly.
function lastRun(events) {
  let start = 0;
  for (let i = events.length - 1; i >= 0; i -= 1) {
    if (events[i].type === 'tick' && Number(events[i].tick) === 1) {
      start = i;
      break;
    }
  }
  return events.slice(start);
}

function summarize(run) {
  const ticks = run.filter((e) => e.type === 'tick');
  const recoveries = run.filter((e) => e.type === 'recovery');
  const pause = [...run].reverse().find((e) => e.type === 'human_pause');

  // State-bearing events (ticks and recoveries both carry *_after fields); the
  // last one reflects the true final state — a recovery tick often advances it
  // after the final numbered tick.
  const stateful = run.filter((e) => e.type === 'tick' || e.type === 'recovery');
  const first = ticks[0] || run[0] || {};
  const last = stateful[stateful.length - 1] || run[run.length - 1] || {};

  const duration = ticks.reduce((s, t) => s + (Number(t.duration_seconds) || 0), 0);
  const harness = (ticks.find((t) => t.harness_version) || {}).harness_version || 'unknown';

  // Distinct scopes touched, in first-seen order.
  const scopes = [];
  for (const t of ticks) {
    for (const v of [t.focus_ref_id_before, t.focus_ref_id_after]) {
      if (v && v !== 'null' && v !== '' && !scopes.includes(v)) scopes.push(v);
    }
  }

  const finalValidation = last.validation_status_after || last.validation_status_before || 'unknown';

  // Cost is optional/best-effort — only present if the runtime exposed real usage.
  const cost = ticks.reduce(
    (acc, t) => {
      acc.input += Number(t.input_tokens) || 0;
      acc.output += Number(t.output_tokens) || 0;
      acc.cacheRead += Number(t.cache_read_tokens) || 0;
      acc.usd += Number(t.est_cost_usd) || 0;
      acc.any = acc.any || t.input_tokens != null || t.output_tokens != null || t.est_cost_usd != null;
      return acc;
    },
    { input: 0, output: 0, cacheRead: 0, usd: 0, any: false }
  );

  let stopReason;
  if (pause && pause.stop_reason) stopReason = pause.stop_reason;
  else if (finalValidation === 'pass') stopReason = 'validation PASS';
  else stopReason = 'max iterations / manual stop';

  const recoveryOutcomes = recoveries.map((r) => {
    const progressed =
      r.focus_ref_id_after !== r.focus_ref_id_before ||
      r.validation_status_after !== r.validation_status_before;
    return progressed ? 'recovered' : 'failed';
  });

  return {
    ticks: ticks.length,
    durationSeconds: duration,
    harnessVersion: harness,
    startedUtc: first.started_utc || null,
    endedUtc: last.ended_utc || (pause && pause.paused_utc) || null,
    scopes,
    finalValidation,
    recoveries: recoveries.length,
    recoveryOutcomes,
    stopReason,
    cost,
    git: {
      branch: git(['rev-parse', '--abbrev-ref', 'HEAD']),
      uncommitted: (git(['status', '--porcelain']) || '').split('\n').filter((l) => l.trim()).length,
      recentCommits: (git(['log', '--oneline', '-n', '5']) || '').split('\n').filter(Boolean),
    },
  };
}

function toMarkdown(s) {
  const L = [];
  L.push('# AAI loop digest — last run');
  L.push('');
  if (s.ticks === 0) {
    L.push('No ticks recorded in `docs/ai/LOOP_TICKS.jsonl`. Nothing to report.');
    return L.join('\n');
  }
  L.push(`- **Window:** ${s.startedUtc || '?'} → ${s.endedUtc || '?'}`);
  L.push(`- **Ticks:** ${s.ticks} (${s.durationSeconds}s total)`);
  L.push(`- **Stopped because:** ${s.stopReason}`);
  L.push(`- **Final validation:** ${s.finalValidation}`);
  L.push(`- **Scopes touched:** ${s.scopes.length ? s.scopes.join(', ') : '(none)'}`);
  if (s.recoveries > 0) {
    L.push(`- **Fresh-context recovery:** ${s.recoveries} attempt(s) — ${s.recoveryOutcomes.join(', ')}`);
  }
  L.push(`- **Harness version:** ${s.harnessVersion}`);
  if (s.cost.any) {
    L.push(
      `- **Cost:** in ${s.cost.input} / out ${s.cost.output} / cache-read ${s.cost.cacheRead} tokens` +
        (s.cost.usd ? ` (~$${s.cost.usd.toFixed(4)})` : '')
    );
  }
  L.push('');
  L.push('## Working tree');
  L.push(`- Branch: \`${s.git.branch || '?'}\``);
  L.push(`- Uncommitted changes: ${s.git.uncommitted}`);
  if (s.git.recentCommits.length) {
    L.push('- Recent commits:');
    for (const c of s.git.recentCommits) L.push(`  - ${c}`);
  }
  L.push('');
  L.push('_Review the work above, then merge/push when ready. Nothing was shipped automatically._');
  return L.join('\n');
}

const events = readEvents();
const run = lastRun(events);
const summary = summarize(run);

if (JSON_OUT) {
  process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
} else {
  const md = toMarkdown(summary);
  process.stdout.write(md + '\n');
  if (WRITE && summary.ticks > 0) {
    const stamp = (summary.endedUtc || new Date().toISOString()).replace(/[:]/g, '').replace(/[.].*/, '').replace(/-/g, '');
    const dir = path.join(ROOT, 'docs/ai/reports');
    fs.mkdirSync(dir, { recursive: true });
    const out = path.join(dir, `loop-digest-${stamp}.md`);
    fs.writeFileSync(out, md + '\n', 'utf8');
    process.stdout.write(`\nSaved: ${path.relative(ROOT, out)}\n`);
  }
}
