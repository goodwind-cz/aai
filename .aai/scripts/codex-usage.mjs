#!/usr/bin/env node
// codex-usage.mjs — read-only Codex rollout usage CLI
// (spec-codex-usage-missing-from-run-budgets). Subcommands: observe, attribute, budget.
//
//   observe   --thread <id|auto> [--from <ISO>] [--to <ISO>] [--descendants] [--json]
//   attribute --parent <id> --from <ISO> --to <ISO> [--json]
//   budget    --thread <id|auto> --since <ISO> --max-run-tokens <N> [--json]
//   probe     [--thread <id|auto>] [--json]
//
// Exit codes: 0 ok / within, 2 usage error, 3 budget exhausted, 4 usage unavailable (D5, D10).
// observe and attribute also print the exact flag lists for state.mjs append-run and
// log-tick (D9). Never prints message content; writes nothing.

import { observe, attribute, listRollouts, resolveThread } from './lib/codex-rollout.mjs';

const EXIT_OK = 0;
const EXIT_USAGE = 2;
const EXIT_EXHAUSTED = 3;
const EXIT_UNAVAILABLE = 4;
const BOOLEAN_FLAGS = new Set(['json', 'descendants']);
const LOG_TICK_KEYS = ['--tokens-in', '--tokens-out'];
const USAGE = 'usage: codex-usage.mjs observe --thread <id|auto> [--from <ISO>] [--to <ISO>] [--descendants] [--json]\n'
  + '       codex-usage.mjs attribute --parent <id> --from <ISO> --to <ISO> [--json]\n'
  + '       codex-usage.mjs budget --thread <id|auto> --since <ISO> --max-run-tokens <N> [--json]\n'
  + '       codex-usage.mjs probe [--thread <id|auto>] [--json]\n';

function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--') && BOOLEAN_FLAGS.has(a.slice(2))) opts[a.slice(2)] = true;
    else if (a.startsWith('--') && i + 1 < argv.length) { opts[a.slice(2)] = argv[++i]; }
    else return { error: `unexpected argument: ${a}` };
  }
  return opts;
}

function usageError(msg) {
  process.stderr.write(`codex-usage: ${msg}\n${USAGE}`);
  process.exit(EXIT_USAGE);
}

const val = (x) => (x === null ? 'null' : String(x));

function humanLine(obs) {
  if (obs.status !== 'ok') return `codex usage unavailable (${obs.reason})`;
  const u = obs.usage;
  const deg = obs.degraded.length ? ` degraded=${obs.degraded.join(',')}` : '';
  return `codex usage thread=${obs.thread} basis=${obs.basis} input=${val(u.input_tokens)} output=${val(u.output_tokens)} total=${val(u.total_tokens)}${deg}`;
}

// D9: the argument lists the orchestrator passes to state.mjs append-run and log-tick.
function attachFlags(obs, attribution) {
  if (obs.status !== 'ok') {
    obs.append_run_flags = ['--harness', 'codex', '--note', `usage_capture=none usage_source=codex_rollout usage_unavailable=${obs.reason}`];
    obs.log_tick_flags = [];
    return obs;
  }
  const usage = obs.usage;
  const flags = ['--harness', 'codex'];
  if (usage.input_tokens !== null) flags.push('--tokens-in', String(usage.input_tokens));
  if (usage.output_tokens !== null) flags.push('--tokens-out', String(usage.output_tokens));
  if (usage.total_tokens !== null) flags.push('--tokens-total', String(usage.total_tokens));
  const note = [];
  if (usage.total_tokens !== null) note.push(`usage_total_tokens=${usage.total_tokens}`);
  note.push('usage_source=codex_rollout', `codex_thread=${obs.thread}`,
    `usage_interval=${obs.interval.from === null ? 'start' : obs.interval.from}/${obs.interval.to}`,
    `usage_attribution=${attribution}`, `usage_basis_detail=${obs.basis}`);
  if (obs.degraded.length) note.push(`usage_degraded=${obs.degraded.join(',')}`);
  flags.push('--note', note.join(' '));
  obs.append_run_flags = flags;
  obs.log_tick_flags = [];
  const tickValues = { '--tokens-in': usage.input_tokens, '--tokens-out': usage.output_tokens };
  for (const key of LOG_TICK_KEYS) {
    if (tickValues[key] !== null) obs.log_tick_flags.push(key, String(tickValues[key]));
  }
  return obs;
}

function emit(obs, opts) {
  process.stdout.write((opts.json ? JSON.stringify(obs) : humanLine(obs)) + '\n');
  process.exit(obs.status === 'ok' ? EXIT_OK : EXIT_UNAVAILABLE);
}

function checkInterval(obs) {
  if (obs.status === 'unavailable' && obs.reason === 'invalid_interval') usageError('--from/--to must be ISO timestamps');
}

function runBudget(opts) {
  if (!opts.thread) usageError('--thread is required');
  if (!opts.since || Number.isNaN(Date.parse(opts.since))) usageError('--since must be an ISO timestamp');
  if (!/^[1-9][0-9]*$/.test(opts['max-run-tokens'] || '')) usageError('--max-run-tokens must be a positive integer');
  const limit = Number(opts['max-run-tokens']);
  const obs = observe({ thread: opts.thread, from: opts.since, descendants: true, env: process.env });
  checkInterval(obs);
  const cumulative = obs.status === 'ok' ? obs.usage.total_tokens : null;
  const verdict = { enforcement: 'unavailable', cumulative_total_tokens: null, limit, verdict: 'unknown', degraded: [] };
  let code = EXIT_UNAVAILABLE;
  if (cumulative === null) {
    verdict.reason = obs.status === 'ok' ? 'total_tokens_missing' : obs.reason;
    verdict.message = `RUN BUDGET: token budget NOT enforced (${verdict.reason})`;
  } else {
    const exhausted = cumulative >= limit;
    verdict.enforcement = obs.degraded.length ? 'degraded' : 'active';
    verdict.cumulative_total_tokens = cumulative;
    verdict.verdict = exhausted ? 'exhausted' : 'within';
    verdict.degraded = obs.degraded;
    verdict.message = `RUN BUDGET: ${verdict.verdict} cumulative=${cumulative} limit=${limit} enforcement=${verdict.enforcement}`;
    code = exhausted ? EXIT_EXHAUSTED : EXIT_OK;
  }
  process.stdout.write((opts.json ? JSON.stringify(verdict) : verdict.message) + '\n');
  process.exit(code);
}

// D13: capability discovery. App Server token events are documented upstream but never consumed here.
function runProbe(opts) {
  const listing = listRollouts(process.env);
  const ident = resolveThread(opts.thread || 'auto', process.env);
  const report = {
    rollout_logs: listing.readable.length > 0
      ? { status: 'available', dirs: listing.readable }
      : { status: 'unavailable', reason: 'source_unreadable' },
    thread_identity: ident ? { status: 'resolved', source: ident.source } : { status: 'unresolved', source: null },
    app_server_token_events: 'not_integrated',
  };
  const line = `codex probe rollout_logs=${report.rollout_logs.status} thread_identity=${report.thread_identity.status} app_server_token_events=not_integrated`;
  process.stdout.write((opts.json ? JSON.stringify(report) : line) + '\n');
  process.exit(EXIT_OK);
}

function main(argv) {
  const [cmd, ...rest] = argv;
  if (!['observe', 'attribute', 'budget', 'probe'].includes(cmd)) usageError(cmd ? `unknown subcommand: ${cmd}` : 'missing subcommand');
  const opts = parseArgs(rest);
  if (opts.error) usageError(opts.error);
  if (cmd === 'budget') runBudget(opts);
  if (cmd === 'probe') runProbe(opts);
  if (cmd === 'attribute') {
    if (!opts.parent || !opts.from || !opts.to) usageError('--parent, --from and --to are required');
    const obs = attribute({ parent: opts.parent, from: opts.from, to: opts.to, env: process.env });
    checkInterval(obs);
    emit(attachFlags(obs, obs.attribution), opts);
  }
  if (!opts.thread) usageError('--thread is required');
  const obs = observe({ thread: opts.thread, from: opts.from, to: opts.to, descendants: Boolean(opts.descendants), env: process.env });
  checkInterval(obs);
  emit(attachFlags(obs, 'run'), opts);
}

main(process.argv.slice(2));
