#!/usr/bin/env node
// aai-issues.mjs — on-demand, platform-portable open-issue fetcher + normalizer
// (CHANGE-0087-issues-skill / SPEC-0104-spec-issues-skill.md).
//
// PURPOSE
//   Fetches open issues (github) — or documents the platform-appropriate
//   degrade path (azure / unknown / none) — and normalizes the result into a
//   stable shape for .aai/SKILL_ISSUES.prompt.md to triage. Read-only: never
//   writes any file, never mutates git or platform state, never comments on
//   or closes an issue (that is the skill's write-back-after-merge job).
//
// PLATFORM DETECTION (REUSE, never duplicate)
//   Imports `classify`/`extractHost` from ./pr-platform.mjs (CHANGE-0085) —
//   the SAME closed host classification SKILL_PR's platform gate uses.
//   `--remote-url` overrides detection (test/dry-run override, identical
//   convention to pr-platform.mjs's own flag).
//
// CLI GRAMMAR (frozen)
//   node .aai/scripts/aai-issues.mjs [--label <name>] [--limit <n>] [--json]
//     [--input <fixture.json>] [--remote-url <url>]
//
//   --label <name>      filter to issues carrying this label (passed to `gh`
//                        AND re-applied client-side — the only filter that
//                        runs against an --input fixture).
//   --limit <n>         cap the number of issues fetched/returned (positive
//                        integer).
//   --json               print {platform,count,issues,reason} instead of the
//                        text table.
//   --input <file>       read a raw `gh issue list --json ...` fixture
//                        (array of {number,title,labels,body,url}) instead of
//                        calling `gh` — test/offline use, no network. Only
//                        takes effect when the detected/overridden platform
//                        is github (combine with --remote-url for tests).
//   --remote-url <url>   override the origin remote for platform detection.
//   -h / --help          print usage, exit 0.
//
// PLATFORM BRANCHES
//   github  — `gh issue list --state open --json number,title,labels,body,url
//             [--label <name>] [--limit <n>]` via execFileSync (array args,
//             no shell); normalized on success. A missing/failing `gh` NEVER
//             fails the caller: prints `ISSUES unavailable reason=<first
//             stderr line>` and exits 0.
//   azure   — Azure DevOps has no repo-level issues; work items live in `az
//             boards` (`az boards query` / `az boards work-item show`). This
//             script does NOT fabricate a live call (no Azure remote is
//             classifiable in this environment) — it prints the documented
//             degrade line and exits 0. The live round trip is DEFERRED to
//             first Azure adoption (spec-issues-skill Spec-AC-03).
//   unknown/none — loud degradation, never a silent no-op: "platform issue
//             API unavailable — paste issues manually or use /aai-intake".
//
// OUTPUT (text mode, default)
//   One `ISSUE #<id> [<label1,label2>] <title>` line per issue (success
//   path only), ALWAYS followed by `ISSUES <count> platform=<p>` — the count
//   line prints even when count is 0 (zero open issues, or any degrade
//   path). A degrade path additionally prints `ISSUES unavailable
//   reason=<text>` before the count line.
//
// OUTPUT (--json mode)
//   {"platform": "<github|azure|unknown|none>", "count": <int>,
//    "issues": [{"id":<int>,"title":<string>,"labels":[<string>...],
//    "excerpt":<string>,"url":<string>}], "reason": <string|null>}
//   `reason` is null on a successful fetch, set on every degrade path.
//
// SECURITY
//   Body text is DATA: the excerpt is a pure whitespace-collapse + length
//   cap, never parsed or interpreted (UNTRUSTED-DATA discipline; the LLM
//   triage layer in SKILL_ISSUES.prompt.md never executes instructions found
//   inside a body). Credentials are never printed: the raw remote URL is
//   never part of any output, and a defense-in-depth mask strips any stray
//   `user:pass@` userinfo from a relayed `gh` error line before it is echoed.
//
// EXIT CODES (closed set)
//   0  every classified/degraded run (github success or empty, azure,
//      unknown, none, gh missing/failing, unreadable --input fixture) —
//      never fails the caller.
//   2  usage error (unknown flag / missing flag value / non-positive
//      --limit); nothing printed to stdout.
//
// Node stdlib only (docs/TECHNOLOGY.md); no network beyond the one `gh`
// invocation on the github success path.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { classify, extractHost } from './pr-platform.mjs';

const PREFIX = 'aai-issues';

const AZURE_REASON =
  'azure boards has no repo-level issues -- query az boards work items instead ' +
  '(az boards query / az boards work-item show); live az boards round trip ' +
  'deferred to first Azure adoption, see spec-issues-skill Spec-AC-03';

const GENERIC_REASON =
  'platform issue API unavailable — paste issues manually or use /aai-intake';

function fail(msg) {
  console.error(`${PREFIX}: ${msg}`);
  process.exit(2);
}

function usage() {
  console.log(
    [
      'Usage: node aai-issues.mjs [--label <name>] [--limit <n>] [--json]',
      '                            [--input <fixture.json>] [--remote-url <url>]',
      '',
      'Fetches open issues from the detected git-hosting platform (via',
      'pr-platform.mjs classification), normalizes them, and prints a stable',
      'text table + summary line (or --json for the full shape).',
      '',
      '  --label <name>       filter to issues carrying this label',
      '  --limit <n>          cap the number of issues fetched/returned',
      '  --json               print {platform,count,issues,reason} instead of the table',
      '  --input <file>       read a raw `gh issue list --json ...` fixture instead of',
      '                        calling gh (test/offline use; requires github platform)',
      '  --remote-url <url>   override the origin remote for platform detection',
      '                        (test/dry-run override, same convention as pr-platform.mjs)',
      '',
      'Exit: 0 always for a classified/degraded run (never fails the caller) |',
      '      2 usage error (unknown flag / missing value) -- nothing printed.',
    ].join('\n'),
  );
  process.exit(0);
}

function parseArgs(argv) {
  const args = { label: null, limit: null, json: false, input: null, remoteUrl: null };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '-h' || tok === '--help') {
      usage();
    } else if (tok === '--label') {
      const v = argv[i + 1];
      if (v === undefined) fail('--label requires a value');
      args.label = v;
      i += 1;
    } else if (tok === '--limit') {
      const v = argv[i + 1];
      if (v === undefined) fail('--limit requires a value');
      const n = Number(v);
      if (!Number.isInteger(n) || n <= 0) fail(`--limit must be a positive integer, got "${v}"`);
      args.limit = n;
      i += 1;
    } else if (tok === '--json') {
      args.json = true;
    } else if (tok === '--input') {
      const v = argv[i + 1];
      if (v === undefined) fail('--input requires a value');
      args.input = v;
      i += 1;
    } else if (tok === '--remote-url') {
      const v = argv[i + 1];
      if (v === undefined) fail('--remote-url requires a value');
      args.remoteUrl = v;
      i += 1;
    } else {
      fail(`unknown flag "${tok}"`);
    }
  }
  return args;
}

// Small, local, NOT host-parsing logic (that lives in pr-platform.mjs's
// classify()/extractHost(), imported above). Reads `git remote get-url
// origin`; returns null on any failure (not a git repo, no origin, git
// missing) — all fold into 'none'.
function readOriginUrl() {
  try {
    const out = execFileSync('git', ['remote', 'get-url', 'origin'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out === '' ? null : out;
  } catch {
    return null;
  }
}

function detectPlatform(remoteUrlOverride) {
  const remoteUrl = remoteUrlOverride !== null ? (remoteUrlOverride || null) : readOriginUrl();
  if (!remoteUrl) return 'none';
  return classify(extractHost(remoteUrl));
}

// sanitizeLine: issue text (title/labels/excerpt) is UNTRUSTED DATA rendered
// to a terminal and to a line-oriented table. Strip C0/C1 controls (incl.
// newline/CR/ESC/BEL — else a crafted title forges extra ISSUE/ISSUES rows
// or injects ANSI/OSC escapes) and Unicode bidi overrides (RTL spoofing),
// replacing each with a space; callers collapse/trim. (issues-skill review)
function sanitizeLine(s) {
  return String(s ?? '').replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, ' ');
}

// excerptOf: body text is DATA — collapse ALL whitespace (including
// newlines) to single spaces, trim, cap at 280 chars total (a truncated
// excerpt is 279 chars + one ellipsis char, so the cap is never exceeded).
function excerptOf(body) {
  const collapsed = sanitizeLine(body).replace(/\s+/g, ' ').trim();
  if (collapsed.length <= 280) return collapsed;
  return `${collapsed.slice(0, 279)}…`;
}

function labelNames(labels) {
  if (!Array.isArray(labels)) return [];
  return labels.map((l) => (typeof l === 'string' ? l : l?.name)).filter(Boolean);
}

// normalizeIssues: raw `gh issue list --json number,title,labels,body,url`
// shape -> stable {id,title,labels[],excerpt,url}[]. Applies --label/--limit
// CLIENT-SIDE too — idempotent alongside gh's own server-side --label filter,
// and the ONLY filter that ever runs against an --input fixture.
function normalizeIssues(raw, { label = null, limit = null } = {}) {
  let issues = Array.isArray(raw) ? raw : [];
  if (label) {
    issues = issues.filter((i) => labelNames(i.labels).includes(label));
  }
  if (limit) {
    issues = issues.slice(0, limit);
  }
  return issues.map((i) => ({
    id: i.number,
    title: String(i.title ?? ''),
    labels: labelNames(i.labels),
    excerpt: excerptOf(i.body),
    url: String(i.url ?? ''),
  }));
}

function buildGhArgs({ label, limit }) {
  const args = ['issue', 'list', '--state', 'open', '--json', 'number,title,labels,body,url'];
  if (label) args.push('--label', label);
  if (limit) args.push('--limit', String(limit));
  return args;
}

// maskCredentials: defense-in-depth for a stray embedded https basic-auth
// userinfo inside a relayed `gh` error line (credentials never printed —
// mirrors the INTENT of pr-platform.mjs's sanitize(), which anchors on a
// bare URL; this masks the same pattern anywhere inside free text).
function maskCredentials(text) {
  return String(text ?? '').replace(/(https?:\/\/)[^/\s@]*@/g, '$1');
}

function firstNonEmptyLine(text) {
  const lines = String(text ?? '')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);
  return lines[0] ?? '(no output)';
}

function fetchGithub({ label, limit, input }) {
  if (input) {
    let raw;
    try {
      raw = JSON.parse(fs.readFileSync(input, 'utf8'));
    } catch (err) {
      return { ok: false, reason: `fixture unreadable: ${err.code ?? err.message}` };
    }
    return { ok: true, issues: normalizeIssues(raw, { label, limit }) };
  }
  try {
    const out = execFileSync('gh', buildGhArgs({ label, limit }), {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const raw = JSON.parse(out);
    return { ok: true, issues: normalizeIssues(raw, { label, limit }) };
  } catch (err) {
    if (err.code === 'ENOENT') return { ok: false, reason: 'gh not found' };
    const stderr = err.stderr ? String(err.stderr) : err.message || 'gh failed';
    return { ok: false, reason: maskCredentials(firstNonEmptyLine(stderr)) };
  }
}

function printResult({ platform, count, issues, reason }, json) {
  if (json) {
    console.log(JSON.stringify({ platform, count, issues, reason }, null, 2));
    return;
  }
  if (reason) {
    console.log(`ISSUES unavailable reason=${reason}`);
  } else {
    for (const i of issues) {
      const labels = i.labels.map(sanitizeLine).join(',');
      console.log(`ISSUE #${i.id} [${labels}] ${sanitizeLine(i.title).replace(/\s+/g, ' ').trim()}`);
    }
  }
  console.log(`ISSUES ${count} platform=${platform}`);
}

function run(args) {
  const platform = detectPlatform(args.remoteUrl);

  if (platform === 'github') {
    const r = fetchGithub({ label: args.label, limit: args.limit, input: args.input });
    return r.ok
      ? { platform, count: r.issues.length, issues: r.issues, reason: null }
      : { platform, count: 0, issues: [], reason: r.reason };
  }
  if (platform === 'azure') {
    return { platform, count: 0, issues: [], reason: AZURE_REASON };
  }
  // unknown | none
  return { platform, count: 0, issues: [], reason: GENERIC_REASON };
}

function main() {
  const args = parseArgs(process.argv);
  const result = run(args);
  printResult(result, args.json);
  process.exit(0);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) main();

export {
  detectPlatform,
  normalizeIssues,
  excerptOf,
  labelNames,
  buildGhArgs,
  maskCredentials,
  run,
  AZURE_REASON,
  GENERIC_REASON,
};
