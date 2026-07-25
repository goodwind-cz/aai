// aai-feedback-status.mjs — RFC-0012 friction feedback DISCOVERY surface.
//
// Tells a human operator, in plain terms, the state of the local friction
// feedback loop so the built machinery is actually reachable:
//   - how many friction observations are captured in the local spool,
//   - how many prepared issue drafts await their `--confirm`,
//   - whether GitHub `gh` is present and authenticated (read-only check),
//   - the exact next command to run.
//
// Offline for the counts (pure filesystem reads of the untracked spool). The ONLY
// external call is a READ-ONLY `gh auth status` — it never mutates and degrades
// cleanly if gh is absent/unauthenticated. Wired into /aai-wrap-up as an
// end-of-session nudge (silent when there is nothing to surface).
//
// Usage:
//   node .aai/scripts/aai-feedback-status.mjs [--json]
//   node .aai/scripts/aai-feedback-status.mjs --help
//
// Node stdlib only.

import { readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..');
const FRICTION_DIR = process.env.AAI_FRICTION_DIR || join(REPO_ROOT, 'docs', 'ai', 'friction');
const SPOOL = join(FRICTION_DIR, 'observations.jsonl');
const PENDING_DIR = join(FRICTION_DIR, 'pending-issues');

const HELP = `aai-feedback-status — RFC-0012 friction feedback discovery.

Usage:
  node .aai/scripts/aai-feedback-status.mjs [--json]
  node .aai/scripts/aai-feedback-status.mjs --help

Reports the local feedback-loop state: observations captured, drafts pending your
--confirm, and whether GitHub \`gh\` is authenticated — plus the next command. The
counts are offline filesystem reads; the only external call is a read-only
\`gh auth status\`. No mutation, no issue writes.
`;

function countObservations() {
  try {
    return readFileSync(SPOOL, 'utf8').split('\n').filter((l) => l.trim()).length;
  } catch { return 0; }
}
function countDrafts() {
  try {
    return readdirSync(PENDING_DIR).filter((f) => f.endsWith('.md')).length;
  } catch { return 0; }
}
// Read-only auth probe. Returns 'ready' | 'unauthenticated' | 'absent'. Never
// throws, never mutates — `gh auth status` performs no write.
function ghState() {
  const bin = process.env.AAI_GH_BIN || 'gh';
  try {
    execFileSync(bin, ['auth', 'status'], { stdio: ['ignore', 'ignore', 'ignore'] });
    return 'ready';
  } catch (e) {
    // execFileSync throws ENOENT (gh absent) or a non-zero exit (unauthenticated).
    return e && e.code === 'ENOENT' ? 'absent' : 'unauthenticated';
  }
}

function parseArgs(argv) {
  const a = {};
  for (const t of argv) {
    if (t === '--help' || t === '-h') a.help = true;
    else if (t === '--json') a.json = true;
    else { process.stderr.write(`aai-feedback-status: unrecognized argument: ${t}\n`); process.exit(2); }
  }
  return a;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) { process.stdout.write(HELP); process.exit(0); }

  const observations = countObservations();
  const drafts = countDrafts();
  const gh = ghState();
  const ghReady = gh === 'ready';
  const ghHint = gh === 'absent' ? 'install & run: gh auth login'
    : gh === 'unauthenticated' ? 'run: gh auth login'
    : 'ready';

  // Next actionable command for the operator.
  let next = null;
  if (drafts > 0) next = 'review docs/ai/friction/pending-issues/, then: node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm';
  else if (observations > 0) next = 'node .aai/scripts/aai-feedback-triage.mjs   # review clusters, then prepare with aai-feedback-upsert.mjs';

  if (args.json) {
    process.stdout.write(JSON.stringify({ observations, drafts, gh, gh_ready: ghReady, next: next || '' }, null, 2) + '\n');
    process.exit(0);
  }

  // Silent when there is nothing to surface (shadow mode is quiet by design):
  // the human nudge writes NOTHING on an empty loop so /aai-wrap-up can include
  // its output verbatim only when non-silent. --json above always emits the
  // object (a programmatic caller wants the zeros); this silence is human-only.
  if (observations === 0 && drafts === 0) {
    process.exit(0);
  }
  process.stdout.write(
    `friction feedback: ${observations} observation(s) captured · ${drafts} draft(s) pending your --confirm · gh: ${ghHint}\n`
  );
  if (next) process.stdout.write(`  next: ${next}\n`);
}

main();
