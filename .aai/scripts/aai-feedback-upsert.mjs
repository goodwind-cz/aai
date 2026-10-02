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
//   node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm [--description <file>] [...]
//   node .aai/scripts/aai-feedback-upsert.mjs --help
//
// A filed issue carries ONE certified human-written description as its leading
// blockquote (spec-friction-issues-arrive-without-a-description D1/D3): the
// record's own `summary` (written under `record --promote`) or a publish-time
// `--description <file>`, both certified by the same fail-closed redactor. A
// record with no certified description is NOT filed -- prepare marks it
// blocked_no_description, publish refuses with exit 2 BEFORE any gh call.
//
// Node stdlib only. `gh` is invoked via a single runGh() seam (mockable on PATH).

import { readFileSync, writeFileSync, mkdirSync, existsSync, appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { redactSummary } from './lib/aai-redact.mjs';
// telemetry-fields-not-prose D10/S7: the SAME closed set append-run and
// aai-friction.mjs assert against — a divergent private copy would show.
import { HARNESS_VALUES } from './lib/harness.mjs';

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

// A STATIC, literal, structurally-commented-out skeleton (D4). It interpolates
// NOTHING -- not the fingerprint, not the destination, not one spool field --
// so there is no value in it that redaction would ever need to certify. It is
// appended to the draft AFTER payload.body (D4/D5) and is never read by the
// publish path, which rebuilds the transmitted body from the report and spool
// instead (seam S1) -- so a placeholder here can never leak into a filed body.
const DRAFT_FOLLOWUP_SKELETON = `\n<!--\n## Analysis (reporter follow-up)\n(operator: fill in after filing -- what happened, how to reproduce, and the\nsuggested fix. This skeleton is inert: it is never read by the publish path.)\n-->\n`;

const MODES = new Set(['local', 'review', 'auto']);

const HELP = `aai-feedback-upsert — RFC-0012 Phase 2c review-mode upsert (approval-gated).

Usage:
  node .aai/scripts/aai-feedback-upsert.mjs [--report <p>] [--spool <p>] [--config <p>]
  node .aai/scripts/aai-feedback-upsert.mjs --publish <fingerprint> --confirm [--description <file>] [...]
  node .aai/scripts/aai-feedback-upsert.mjs --help

A plain run is PREPARE-ONLY: it writes transmit-redacted, deduplicated,
budget-checked issue drafts to docs/ai/friction/pending-issues/ and prints the
exact confirmed-write command. It performs NO mutating GitHub call. A GitHub issue
is filed ONLY via the explicit human-confirmed path:
  --publish <fingerprint> --confirm
which re-runs the transmit redaction + budget check immediately before the write.
'auto' mode is refused (locked). 'local' (default) prepares nothing to send.

A filed issue carries ONE certified human-written description as its leading
blockquote: one line, 1..500 characters, certified by the same fail-closed
redactor as every free-text field. Its source is the record's own summary
(written at record time under 'record --promote') or, at publish time,
--description <file> (its lines joined by one space; read from argv only --
the on-disk draft is never read). A record with no description -- no certified
summary and no --description file -- is NOT filed: prepare marks it
blocked_no_description and --publish refuses with exit 2 before any gh call,
naming the missing field (a maintainer cannot act on structured fields alone).
A description the redactor refuses is refused the same way, naming the
redactor's reason class.

On a confirmed publish the engine prints the filed issue's URL and posts the
certified description as the analysis comment. Mechanism, reproduction steps
and anything naming a path or quoting output stay a hand-written follow-up:
gh issue comment <n> --repo <destination> --body-file <file>, printed (never
run) only when the comment could not be posted.

Exit codes: 0 success / --help   2 usage error or refusal   1 internal error
`;

class UsageError extends Error {}

function parseArgs(argv) {
  const a = { report: DEFAULT_REPORT, spool: DEFAULT_SPOOL, config: DEFAULT_CONFIG };
  let i = 0;
  while (i < argv.length) {
    const t = argv[i];
    if (t === '--help' || t === '-h') { a.help = true; i += 1; continue; }
    if (t === '--confirm') { a.confirm = true; i += 1; continue; }
    if (t === '--report' || t === '--spool' || t === '--config' || t === '--publish' || t === '--description') {
      const v = argv[i + 1];
      if (v === undefined) throw new UsageError(`${t} requires an argument`);
      a[t.slice(2)] = v; i += 2; continue;
    }
    throw new UsageError(`unrecognized argument: ${t}`);
  }
  // --description supplies the publish-time description (argv-only); on a
  // prepare run it would silently do nothing, so it is a usage error there.
  if (a.description !== undefined && a.publish === undefined) {
    throw new UsageError('--description <file> is only valid together with --publish <fingerprint> --confirm');
  }
  return a;
}

// Scoped, fail-closed config read (mirrors the triage parser discipline): `mode`
// from a direct child of top-level `triage:`; `destination`/`cooldown_days` from a
// direct child of `upsert:`; `max_new_issues_per_7d` from `upsert: > budget:`.
// Any anomaly leaves the safe default (mode local, destination null).
function indentOf(l) { return l.length - l.trimStart().length; }
// Strip a YAML inline comment (whitespace + `#...` to end) from a value. A `#`
// with no preceding whitespace is left alone (part of the value). Without this,
// `destination: goodwind-cz/aai   # pinned` would fail the destination regex and
// the engine would wrongly behave as "no destination" (PR review P1).
function stripComment(v) { return v.replace(/(^|\s)#.*$/, '$1').trim(); }

function loadConfig(path) {
  const cfg = { mode: 'local', destination: null, maxNewPer7d: 3, cooldownDays: 7, labels: [] };
  let text; try { text = readFileSync(path, 'utf8'); } catch { return cfg; }
  let section = null;         // 'triage' | 'upsert' | null
  let childIndent = null;
  let sub = null; let subIndent = null;   // 'budget' | 'labels' sub-block
  for (const raw of text.split('\n')) {
    if (!raw.trim() || /^[ \t]*#/.test(raw)) continue;
    const indent = indentOf(raw); const line = raw.trim();
    if (indent === 0) {
      section = /^triage[ \t]*:/.test(line) ? 'triage'
        : /^upsert[ \t]*:/.test(line) ? 'upsert' : null;
      childIndent = null; sub = null;
      continue;
    }
    if (!section) continue;
    if (childIndent === null) childIndent = indent;
    if (indent === childIndent) {
      sub = null;
      const kv = line.match(/^([a-z_]+)[ \t]*:(.*)$/); if (!kv) continue;
      const key = kv[1]; const val = stripComment(kv[2].trim());
      if (section === 'triage' && key === 'mode' && MODES.has(val)) cfg.mode = val;
      if (section === 'upsert' && key === 'destination' && /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/.test(val)) cfg.destination = val;
      if (section === 'upsert' && key === 'cooldown_days' && /^\d+$/.test(val)) cfg.cooldownDays = parseInt(val, 10);
      if (section === 'upsert' && key === 'budget' && val === '') { sub = 'budget'; subIndent = null; }
      if (section === 'upsert' && key === 'labels' && val === '') { sub = 'labels'; subIndent = null; }
    } else if (section === 'upsert' && sub && indent > childIndent) {
      if (subIndent === null) subIndent = indent;
      if (indent === subIndent) {
        if (sub === 'budget') {
          const m = line.match(/^max_new_issues_per_7d[ \t]*:[ \t]*(\d+)[ \t]*$/);
          if (m) cfg.maxNewPer7d = parseInt(m[1], 10);
        } else if (sub === 'labels') {
          const m = line.match(/^-[ \t]+(.+)$/);
          const lab = m && stripComment(m[1].trim());
          // A label the charset gate refuses is DROPPED here, before the
          // destination is ever consulted. Saying so matters: GitHub label names
          // may contain spaces ("good first issue"), so this silently discarded
          // legitimate configuration while D2 promised every drop is named.
          if (lab && /^[A-Za-z0-9._-]{1,50}$/.test(lab)) cfg.labels.push(lab);
          else if (lab) process.stderr.write(`aai-feedback-upsert: configured label ${JSON.stringify(lab)} is not of the form [A-Za-z0-9._-]{1,50} and was dropped before the destination was consulted\n`);
        }
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
// Returns { ok, stdout, status, stderrFirst } ; never throws on a missing/
// failing gh (degrade). `status` is the process exit code (null when it could
// not be determined, e.g. gh itself is missing); `stderrFirst` is the FIRST
// non-empty line of stderr, RAW and UNTRUNCATED — callers that print it must
// run it through ghFailDetail() first (spec-friction-publish-hides-required-
// followup D6: one sanitizer decides what may be printed, never the caller).
function runGh(args, { mutating } = {}) {
  const bin = process.env.AAI_GH_BIN || 'gh';
  try {
    // maxBuffer set explicitly (remediation F1, spec-friction-publish-hides-
    // required-followup Amendment 6): execFileSync's 1 MiB default throws
    // (ENOBUFS-shaped) once gh (or a wrapper) emits more than that on either
    // stream, and the catch below then has no real e.status/e.stderr to read
    // -- collapsing this whole seam's exit-status diagnosis into a generic
    // refusal. 64 MB matches the value already used for the same class of
    // problem elsewhere in this repository (check-committed-scope.mjs,
    // orchestration-dispatch.mjs).
    const stdout = execFileSync(bin, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
    return { ok: true, stdout, status: 0, stderrFirst: '' };
  } catch (e) {
    const stderrRaw = typeof e.stderr === 'string' ? e.stderr : (e.stderr ? e.stderr.toString('utf8') : '');
    const stderrFirst = stderrRaw.split('\n').find((l) => l.trim().length > 0) || '';
    const status = typeof e.status === 'number' ? e.status : null;
    return { ok: false, stdout: '', status, stderrFirst };
  }
}

// A GitHub rate-limit-shaped 403 is diagnosed on the RAW, pre-redaction first
// stderr line (D7) -- redaction may suppress the line itself, but the
// signature check must still see it. Two real wordings are matched, both
// drawn from `goodwind-cz/aai#371`'s "Aside" (not invented, not derived from
// this regex -- TEST-042 pins the reporter's own literal line, not a string
// shaped to satisfy it):
//   "API rate limit exceeded for user ID ..." -- what `gh search issues`
//     actually printed for the reporter when the SEARCH endpoint's own
//     throttle fired, even while `gh api rate_limit` (the PRIMARY quota) read
//     full (30/30). This is the wording the ORIGINAL signature missed
//     entirely -- it matched only the wording below, so the exact case #371
//     exists to fix never fired the hint (remediation F1).
//   "You have exceeded a secondary rate limit ..." -- GitHub's own literal
//     wording for the secondary/abuse limiter.
// The first wording is ALSO GitHub's genuine primary-limit message, so this
// signature cannot and does not claim which class fired -- see
// RATE_LIMIT_HINT, which states only the fact the reporter established, not a
// guess at the class.
const RATE_LIMIT_SIGNATURE_RE = /rate limit exceeded|secondary rate limit/i;
// Fixed, non-interpolated sentence (D7): naming it is safe even when the raw
// line that triggered it is not. Deliberately does NOT assert primary or
// secondary -- asserting "secondary" on a wording that is also GitHub's
// genuine primary-limit message would be a new wrong claim on a real primary
// hit. What it states instead is the reporter's own diagnosis: `gh api
// rate_limit` does not reliably report this refusal. The reason is
// NARROWER than "gh search has its own throttle separate from the primary
// quota it shows" (validation round 3, N2) -- that clause is false: `gh api
// rate_limit` DOES report the search throttle, as `resources.search`,
// measured live in this session at 30/30 while a search 403 was in play.
// What is true and checkable instead: `gh api rate_limit` does not report
// SECONDARY limits at all, and its reading can disagree with whichever
// endpoint is actually enforcing the refusal (a read taken a moment before
// or after the call that failed).
const RATE_LIMIT_HINT = 'NOTE: this looks like a GitHub API rate-limit refusal (primary or secondary) -- `gh api rate_limit` does not reliably report this class, since it does not report secondary limits at all and its reading can disagree with the endpoint actually enforcing the refusal; it typically clears on its own within a minute, so retrying shortly may succeed.\n';

// ONE sanitizer decides what a gh stderr line may print (D6). Truncates to 200
// chars BEFORE redaction (never after -- a truncated secret prefix cannot
// survive to look like a certified value), then certifies via the same
// fail-closed redactSummary() used for free-text elsewhere. Returns:
//   null                              -- no stderr output to show at all
//   'stderr suppressed by the redactor' -- stderr existed but failed certification
//   <the certified line>              -- safe to print verbatim
function ghFailDetail(r) {
  const first = r && r.stderrFirst ? r.stderrFirst : '';
  if (!first) return null;
  const truncated = first.length > 200 ? first.slice(0, 200) : first;
  const cert = redactSummary(truncated);
  return cert.ok ? cert.value : 'stderr suppressed by the redactor';
}

// Build a one-block refusal: names the exit status either way, names the
// certified detail (or omits it entirely when stderr was empty -- never a
// bare suppression placeholder for a call that produced no stderr at all),
// and appends the fixed rate-limit hint when the RAW line matches it.
function ghRefusalLine(prefix, r) {
  const statusPart = (r && typeof r.status === 'number') ? `exit ${r.status}` : 'exit status unknown';
  const detail = ghFailDetail(r);
  const base = detail === null ? `${prefix} (${statusPart})\n` : `${prefix} (${statusPart}): ${detail}\n`;
  const hint = (r && r.stderrFirst && RATE_LIMIT_SIGNATURE_RE.test(r.stderrFirst)) ? RATE_LIMIT_HINT : '';
  return base + hint;
}

// Parse the FIRST non-empty line of `gh issue create`'s stdout against the
// issue-URL shape (D1), then CERTIFY it before it is ever handed to a caller
// -- the URL is subprocess output, not a trusted value, and printing it
// verbatim was a leak class of its own (validation probes P7/P8, remediation
// F6/F7): the bare shape admits userinfo (`user:token@host`) and any host at
// all, so a compromised or proxied `gh` could hand back a credentialed or
// foreign-host URL and have it echoed as "your filed issue". Certification
// is four checks on the PARSED pieces, never the raw line:
//   - no userinfo: the host component may not contain `@`, RAW or
//     percent-encoded (`%40`) -- decoding is attempted so `%40`/`%3A` cannot
//     walk past a literal `.includes('@')` check the way validation round 3
//     probe V3 (`aleho%3Aghp_...%40github.com`) demonstrated; a value the
//     decoder cannot even parse falls back to the RAW host string (the
//     decode failure itself is not a refusal) -- safe because a host that
//     fails to decode can never equal the literal `github.com` the exact
//     pin below requires, so it is refused there instead.
//   - the host MUST equal `github.com` exactly, case-insensitively (DNS
//     names are) -- not merely "contains no @". Validation round 3's
//     BLOCKING finding (B1) was exactly this: a foreign host whose owner/repo
//     happened to match the destination (`evil.example.com/goodwind-cz/aai`)
//     printed as "your filed issue" because nothing pinned the host at all.
//     Once host and owner/repo (below) are both pinned to exact, known
//     values inside `ISSUE_URL_RE`'s `^...$`-anchored shape, every character
//     of a certified line is either a fixed literal, a value read from the
//     ADMIN-CONFIGURED `destination`, or a digit -- with one measured
//     exception in the owner/repo portion, disclosed in spec R6 (Amendment
//     5, NB-3): `U+212A KELVIN SIGN` lowercases to ASCII `k` and can stand in
//     for a `k`/`K` in a destination that contains that letter (empty set for
//     this repository's `goodwind-cz/aai`). Outside that one disclosed
//     exception there is no reachable position left for a credential, a
//     look-alike host, a control character or an ANSI escape sequence to
//     survive certification. Length and control-character filtering are
//     therefore closed BY CONSTRUCTION for the host/owner/repo, not by a
//     separate scan (see spec Amendment 3, R6) -- validated live against
//     V1-V5/V16 in validation-2026-09-12-round2-probes.sh.
//   - the owner/repo captured MUST equal the CONFIGURED destination
//     (case-insensitive; GitHub repo slugs are), never a value read out of
//     the URL itself -- the same principle D3 already applies to the printed
//     `--repo`, applied here to the printed URL.
//   - the captured issue NUMBER is the one piece the anchored shape leaves
//     unconstrained (`\d+` has no length cap of its own): a certified host
//     and owner/repo with a digit run padded past any real GitHub issue
//     number would still print verbatim otherwise. `MAX_ISSUE_NUMBER_DIGITS`
//     closes that -- ten digits comfortably covers any real issue number
//     with room to spare.
// A shape mismatch (garbled/absent stdout) and a shape match that fails
// certification are DIFFERENT failure modes: the caller must degrade the
// first with D2's generic NOTE, and must name the second as its own refusal
// rather than silently reusing that same generic NOTE (a silent drop is
// exactly what remediation F6/F7 closes).
const ISSUE_URL_RE = /^https?:\/\/([^\s/]+)\/([^\s/]+)\/([^\s/]+)\/issues\/(\d+)$/;
const TRUSTED_ISSUE_HOST = 'github.com';
const MAX_ISSUE_NUMBER_DIGITS = 10;
// `rawNumber` (Spec-AC-06, S4): carried on every `untrusted_url` refusal, so a
// caller that wanted to (wrongly) act on the shape-matched-but-uncertified
// number could reach for `parsed.rawNumber` -- the certified-prose comment
// gate below MUST read `parsed.certified`, never this field, or an
// uncertified URL (foreign host, oversized number, wrong destination) would
// still receive the second mutating write. It is absent (not merely falsy)
// on `unparseable`: the regex never matched at all there, so there is no
// number to report either way.
function parseIssueUrl(stdout, destination) {
  const lines = (stdout || '').split('\n');
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) continue;
    const m = ISSUE_URL_RE.exec(line);
    if (!m) return { certified: false, reason: 'unparseable' };
    const [, host, owner, repo, number] = m;
    let decodedHost;
    try { decodedHost = decodeURIComponent(host); } catch { decodedHost = host; }
    if (host.includes('@') || decodedHost.includes('@')) {
      return { certified: false, reason: 'untrusted_url', detail: 'the reported URL carries embedded userinfo (a credential shape, raw or percent-encoded) and was not printed', rawNumber: number };
    }
    if (host.toLowerCase() !== TRUSTED_ISSUE_HOST) {
      return { certified: false, reason: 'untrusted_url', detail: 'the reported URL host is not github.com and was not printed', rawNumber: number };
    }
    if (number.length > MAX_ISSUE_NUMBER_DIGITS) {
      return { certified: false, reason: 'untrusted_url', detail: 'the reported URL carries an implausibly long issue number and was not printed', rawNumber: number };
    }
    const ownerRepo = `${owner}/${repo}`;
    if (!destination || ownerRepo.toLowerCase() !== destination.toLowerCase()) {
      return { certified: false, reason: 'untrusted_url', detail: 'the reported URL does not match the configured destination and was not printed', rawNumber: number };
    }
    return { certified: true, url: line, number };
  }
  return { certified: false, reason: 'unparseable' };
}

// Read-only `gh auth status` preflight so the operator gets a clear, up-front
// "run: gh auth login" instead of only a late create failure (PR review / UX).
// Never mutates. Returns 'ready' | 'unauthenticated' | 'absent'.
function ghAuthState() {
  const bin = process.env.AAI_GH_BIN || 'gh';
  try {
    execFileSync(bin, ['auth', 'status'], { stdio: ['ignore', 'ignore', 'ignore'] });
    return 'ready';
  } catch (e) {
    return e && e.code === 'ENOENT' ? 'absent' : 'unauthenticated';
  }
}
function ghAuthHint(state) {
  return state === 'absent' ? 'GitHub CLI `gh` not found — install it and run: gh auth login'
    : 'GitHub `gh` is not authenticated — run: gh auth login';
}

// Read-only dedup search for the fingerprint marker. Returns a TRI-STATE:
// { searched } is false when gh is unavailable OR its output is unparseable
// (transient error / API drift). Callers must distinguish "searched and none"
// (safe to create) from "could not search" (the confirm path fails CLOSED and
// refuses to create, so a search hiccup can never fan out into a duplicate).
// Spec-AC-07: a process that EXITS non-zero and a process that exits 0 with
// unparseable stdout are two DIFFERENT failure modes — `parseFailed: true`
// distinguishes the second, so the caller never renders a parse failure as
// "(exit 0)" (a status that reads as "gh said everything is fine").
function dedupSearch(destination, fp) {
  if (!destination) return { searched: false, exists: false, ghResult: null, parseFailed: false };
  // NO `--state`: `gh search issues` accepts only {open|closed}, and `--state all`
  // — which this call carried until 2026-09-04 — is rejected by the CLI on every
  // invocation. Omitting the flag searches ALL states, which is the semantics the
  // dedup needs. The rejection made `searched` permanently false, so the
  // fail-closed below refused every create and the channel could never file.
  const r = runGh(['search', 'issues', '--repo', destination, '--match', 'body', `aai-friction:${fp}`, '--json', 'number', '--limit', '1']);
  if (!r.ok) return { searched: false, exists: false, ghResult: r, parseFailed: false };
  try { const arr = JSON.parse(r.stdout); return { searched: true, exists: Array.isArray(arr) && arr.length > 0, ghResult: r, parseFailed: false }; }
  catch { return { searched: false, exists: false, ghResult: r, parseFailed: true }; }
}

// Labels that actually EXIST in the destination. `gh issue create` refuses an
// unknown label, so a cosmetic label the repo never defined would fail the whole
// write. TRI-STATE like dedupSearch, but the caller degrades the OPPOSITE way:
// { read:false } means "drop every label and file anyway". The asymmetry is
// deliberate — a duplicate issue is a real harm, an unlabelled issue is not.
// Spec-AC-07 (fu-existinglabels-discards-status): the `runGh` result travels
// back as `ghResult` in EVERY branch (not just the failure one), so the caller
// can always render the true refusal — exit status and certified stderr —
// through `ghRefusalLine` instead of a status-free "could not read" message.
const LABEL_LIST_LIMIT = 500;
function existingLabels(destination) {
  if (!destination) return { read: false, names: [], truncated: false, ghResult: null };
  const r = runGh(['label', 'list', '--repo', destination, '--json', 'name', '--limit', String(LABEL_LIST_LIMIT)]);
  if (!r.ok) return { read: false, names: [], truncated: false, ghResult: r };
  try {
    const arr = JSON.parse(r.stdout);
    if (!Array.isArray(arr)) return { read: false, names: [], truncated: false, ghResult: r };
    const names = arr.map((x) => (x && typeof x.name === 'string' ? x.name : '')).filter(Boolean);
    // A full page means the list MAY be cut short, so "does not exist" would be
    // a claim we cannot support. Say "not in the first N" instead of asserting
    // absence — an untrue guard message is an untrue instruction.
    return { read: true, names, truncated: arr.length >= LABEL_LIST_LIMIT, ghResult: r };
  } catch { return { read: false, names: [], truncated: false, ghResult: r }; }
}

// GitHub label names are case-insensitive for matching purposes.
function hasLabel(names, label) {
  const want = label.toLowerCase();
  return names.some((n) => n.toLowerCase() === want);
}

// Has THIS fingerprint already been filed from THIS machine? The dedup search is
// the authority, but GitHub's search index lags a fresh issue by seconds to
// minutes, so two confirmed publishes in a row could both see an empty search
// and both create. The local ledger closes that window. It is a SECOND gate, not
// a replacement: it only ever refuses, never authorizes.
// ONE read for both local gates. An unreadable ledger (a directory at the path,
// a permissions error) used to crash with an unhandled EISDIR, and the first fix
// — treating the budget as exhausted — was worse: it printed "budget reached"
// and exited 0, silently and permanently blocking a legitimate publish under a
// reason that was not true. Both gates depend on this file, so neither can
// honestly proceed without it: refuse loudly, name the path, exit non-zero.
function readLedgerOrRefuse() {
  if (!existsSync(LEDGER)) return '';
  try { return readFileSync(LEDGER, 'utf8'); }
  catch (e) {
    process.stderr.write(`aai-feedback-upsert: cannot read the local upsert ledger ${LEDGER} (${e && e.code ? e.code : 'unreadable'}) — refusing to publish: both the duplicate check and the budget check depend on it\n`);
    process.exit(1);
  }
}

function alreadyFiledLocally(fp, destination) {
  const raw = readLedgerOrRefuse();
  for (const line of raw.split('\n')) {
    if (!line.trim()) continue;
    try {
      const rec = JSON.parse(line);
      if (!rec || rec.event !== 'issue_created' || rec.fingerprint !== fp) continue;
      // The record carries the destination it was filed to, so the match must
      // use it: an issue filed to repo A is no reason to withhold one from
      // repo B, and pinning only the fingerprint would silently make the first
      // destination the only one this machine can ever publish to. A record
      // with NO destination predates that field and cannot be attributed, so it
      // matches conservatively — refusing is the safe direction here.
      if (rec.destination === undefined || rec.destination === null || rec.destination === destination) return true;
    } catch { /* a malformed ledger line cannot authorize a create */ }
  }
  return false;
}

// Representative observation for a fingerprint: a member carrying a summary is
// preferred (spec-friction-issues-arrive-without-a-description D3 -- a
// promoted record must never be shadowed by a prose-free sibling with higher
// signal); within that pool, highest v2 signal, else first.
function representative(rows, fp) {
  const members = rows.filter((o) => o.fingerprint === fp);
  if (!members.length) return null;
  const withSummary = members.filter((o) => typeof o.summary === 'string' && o.summary.length > 0);
  const pool = withSummary.length ? withSummary : members;
  const sig = (o) => (({ low: 1, medium: 2, high: 3 })[o.impact] || 0)
    + (({ low: 1, medium: 2, high: 3 })[o.confidence] || 0) + (o.reproducible === true ? 2 : 0);
  return pool.reduce((a, b) => (sig(b) > sig(a) ? b : a), pool[0]);
}

// The ONE certified human-written description a filed issue carries
// (spec-friction-issues-arrive-without-a-description D1). Precedence: the
// publish-time `--description <file>` (argv-only; lines joined by one space,
// CR stripped, trimmed) over the record's own `summary`; both go through the
// SAME fail-closed redactSummary, independently of the capture pass (RFC-0013
// D3). Returns { ok:true, value, source } or { ok:false, reason, source }:
//   source 'description' -- reason is the redactor's class, or 'unreadable'
//   source 'summary'     -- the spool summary did not certify (reason = class)
//   reason 'no_description' -- neither exists. The caller decides what to do
// with ok:false; this function never prints and never calls gh.
function certifiedDescription(rep, args) {
  if (args && args.description !== undefined) {
    let text;
    try { text = readFileSync(args.description, 'utf8'); }
    catch (e) { return { ok: false, reason: 'unreadable', source: 'description', path: args.description, code: e && e.code ? e.code : 'unreadable' }; }
    const joined = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).join(' ').trim();
    const cert = redactSummary(joined);
    if (!cert.ok) {
      return { ok: false, reason: cert.reason, source: 'description' };
    }
    return { ok: true, value: cert.value, source: 'description' };
  }
  if (rep && typeof rep.summary === 'string' && rep.summary.length) {
    const r = redactSummary(rep.summary);
    return r.ok ? { ok: true, value: r.value, source: 'summary' } : { ok: false, reason: r.reason, source: 'summary' };
  }
  return { ok: false, reason: 'no_description', source: null };
}

// The D3 refusal text for a description that is missing, unreadable or
// refused. Names the field and the flag, or the redactor's reason class --
// never the refused text itself.
function descriptionRefusal(fp, desc) {
  const prefix = `aai-feedback-upsert: refusing to file ${fp}: `;
  if (desc.source === 'description' && desc.reason === 'unreadable') {
    return `${prefix}--description ${desc.path} could not be read (${desc.code})\n`;
  }
  if (desc.source === 'description') {
    return `${prefix}the description was refused by the redactor (reason: ${desc.reason}) — rewrite it without the offending shape\n`;
  }
  const base = `${prefix}no description — the record carries no certified summary and no --description <file> was given (a maintainer cannot act on structured fields alone)`;
  if (desc.source === 'summary') {
    return `${base} — the record's own summary was refused by the redactor (reason: ${desc.reason})\n`;
  }
  return `${base}\n`;
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
  'contradictory_instructions', 'stalled_progress', 'missing_or_invalid_artifact', 'deterministic_script_failure',
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
// telemetry-fields-not-prose D10/Spec-AC-11: a spool value outside the closed
// HARNESS_VALUES set renders unknown — same shape as safeOsFamily. A spool
// line reaches a public GitHub issue body, so this closed-set sanitizer is
// the injection control (never trust the recorder, even though aai-friction.mjs
// itself only ever derives the value).
function safeHarness(v) { return HARNESS_VALUES.includes(v) ? v : 'unknown'; }
function safeInt(v) { return Number.isInteger(v) ? String(v) : '?'; }
function safePin(v) {
  if (typeof v !== 'string' || !/^[A-Za-z0-9._+-]{1,64}$/.test(v)) return REDACTED;
  return passesRedactor(v) ? v : REDACTED; // deny-list in addition to charset
}
function safeEvidenceRef(v) {
  return (typeof v === 'string' && EVIDENCE_REF_RE.test(v) && !v.split('/').includes('..')) ? v : null;
}
function safeFailureClass(v) { return FAILURE_CLASSES.has(v) ? v : REDACTED; }
// The fingerprint is the dedup key + the issue marker + part of the printed
// command; it must be the exact capture shape `v1:<32-hex>` (PR review P1). An
// off-shape fingerprint (a poisoned spool/report) could otherwise carry
// secret/identity content into a gh search, the draft, or the advertised command
// — so a cluster with an invalid fingerprint is SKIPPED entirely.
function safeFingerprint(fp) { return (typeof fp === 'string' && /^v1:[0-9a-f]{32}$/.test(fp)) ? fp : null; }

// Build a transmit-redacted issue payload. EVERY interpolated field is re-validated
// against its safe domain (double redaction, RFC-0013 D3) — the upsert never trusts
// the spool, so no field can carry a secret/path/identity into a gh argument.
function buildPayload(rep, cluster, fp, desc) {
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
    // 2026-09-12 owner hitl_decision (fu-evidence-ref-cannot-travel, P3): the
    // field stays, labelled reporter-local so a maintainer does not try to
    // follow a path that typically cannot resolve outside the reporter's own
    // (often gitignored) checkout. The value itself is unchanged (no field
    // added/removed from the transmitted record, per the reporter's #371 fence).
    evidenceRef ? `- evidence_ref (reporter-local, may not resolve for a maintainer): ${evidenceRef}` : null,
    `- os_family: ${safeOsFamily(rep.os_family)}  node_major: ${safeInt(rep.node_major)}  aai_pin: ${safePin(rep.aai_pin)}  harness: ${safeHarness(rep.harness)}`,
    `- recurrence: ${safeInt(cluster.recurrence)}  score: ${safeInt(cluster.score)}`,
  ].filter(Boolean);
  // The ONLY free-text field: the certified description `desc` (from
  // certifiedDescription -- the --description file or the record's summary,
  // transmit-redacted either way). `certifiedSummary` (SPEC-0176 Spec-AC-06)
  // is the SAME certified value the blockquote renders -- one certification,
  // two uses (the filed body and, on a certified URL, the analysis comment)
  // -- never a second independent read that could disagree with the body.
  let summaryLine = null;
  let redactionStatus = 'none';
  let certifiedSummary = null;
  if (desc && desc.ok) {
    summaryLine = `\n> ${desc.value}`; redactionStatus = 'transmit_clean'; certifiedSummary = desc.value;
  } else if (desc && desc.source === 'summary') {
    redactionStatus = 'transmit_dropped'; // the spool summary did not certify
  }
  const body = `${summaryLine ? summaryLine + '\n\n' : ''}${facts.join('\n')}\n\n${MARKER(fp)}\n`;
  return { title, body, redaction_status: redactionStatus, certifiedSummary };
}

// Rolling 7-day budget from the local ledger (created issues only).
function newIssuesLast7d(nowMs) {
  if (!existsSync(LEDGER)) return 0;
  const ledgerRaw = readLedgerOrRefuse();
  let n = 0;
  for (const l of ledgerRaw.split('\n')) {
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
  const nowMs = Number(process.env.AAI_NOW_MS) || Date.now();
  const overBudget = newIssuesLast7d(nowMs) >= cfg.maxNewPer7d;
  const prepared = [];
  for (const cluster of candidates) {
    const fp = safeFingerprint(cluster.fingerprint);
    if (!fp) continue; // skip an off-shape / poisoned fingerprint entirely
    const rep = representative(rows, fp);
    if (!rep) continue;
    // prepare takes no --description: only the record's own summary can
    // certify here. A cluster with none is written as a draft (so the operator
    // can read what is missing) but marked blocked and never offered a
    // --publish line (spec-friction-issues-arrive-without-a-description D3).
    const desc = certifiedDescription(rep, {});
    const hasDescription = desc.ok;
    const payload = buildPayload(rep, cluster, fp, desc);
    const ds = dedupSearch(cfg.destination, fp);
    // Reflect the real state in the draft status so a prepare run does not
    // advertise "new" for a candidate that is actually blocked/deferred.
    const status = !ds.searched ? 'blocked_dedup_unavailable'
      : ds.exists ? 'update_existing'
      : overBudget ? 'deferred_budget'
      : !hasDescription ? 'blocked_no_description'
      : 'new';
    // Spec-AC-12: when the dedup search could not run, say what it DID. Both
    // surfaces a prepare run produces -- the console line and the draft on
    // disk -- carry the same rendered refusal, so a file read tomorrow cannot
    // disagree with a console read today.
    const refusal = status === 'blocked_dedup_unavailable' ? dedupUnavailableLine(ds) : '';
    const draftPath = join(PENDING_DIR, `${fp.replace(/[^A-Za-z0-9]/g, '_')}.md`);
    writeFileSync(draftPath,
      `# ${payload.title}\n\n<!-- status: ${status} | redaction: ${payload.redaction_status} -->\n\n${refusal ? `${refusal}\n` : ''}${payload.body}${DRAFT_FOLLOWUP_SKELETON}`);
    prepared.push({ fingerprint: fp, status, draftPath, refusal });
  }
  return prepared;
}

// Why a prepared cluster is not offered a --publish command. Keyed by the same
// status the draft carries, so the file and the console never disagree.
const BLOCK_REASON = {
  blocked_dedup_unavailable: 'the dedup search could not run, so a create would be refused (fail-closed)',
  update_existing: 'an issue already carries this fingerprint marker',
  deferred_budget: 'the 7-day new-issue budget is exhausted',
  blocked_no_description: 'no description — write one line (expected, observed, where) and pass --description <file> to --publish',
};

// Spec-AC-12 (rider 3): `blocked_dedup_unavailable` used to render as the
// BLOCK_REASON sentence alone, which is TRUE of every cause and diagnostic of
// none -- a 60-second rate limit and a repository the token cannot read
// printed the same words. That is this ride's own defect class living inside
// this ride's own tooling, so prepare now renders the SAME one-block refusal
// the publish path has rendered since #371: the gh exit status, the certified
// stderr detail, and the fixed rate-limit hint when the raw line matches the
// signature. No new text is invented here and no new disclosure is made --
// `ghRefusalLine`/`ghFailDetail` already decide what a gh stderr line may
// print, and this reaches that decision from the prepare call site, which
// `dedupSearch` has always fed via `ds.ghResult`.
const GH_RESULT_UNKNOWN = { ok: false, status: null, stderrFirst: '' };
function dedupUnavailableLine(ds) {
  // A PARSE failure is gh exiting ZERO with output nobody can read, so it is
  // deliberately NOT routed through ghRefusalLine: that would print
  // "(exit 0)" -- a status an operator reads as "gh said everything is fine"
  // -- which is the same class of untrue answer this row removes. Say the
  // thing that actually happened instead (dedupSearch's own `parseFailed`).
  if (ds.parseFailed) {
    return `${BLOCK_REASON.blocked_dedup_unavailable}: gh exited 0 and its search output could not be parsed\n`;
  }
  return ghRefusalLine(BLOCK_REASON.blocked_dedup_unavailable, ds.ghResult || GH_RESULT_UNKNOWN);
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
    const fp = safeFingerprint(args.publish);
    if (!fp) { process.stderr.write(`aai-feedback-upsert: ${args.publish} is not a valid fingerprint (expected v1:<32-hex>)\n`); process.exit(2); }
    const rows = readSpool(args.spool);
    const report = readJson(args.report, { clusters: [] });
    const cluster = (report.clusters || []).find((c) => c.fingerprint === fp && c.decision === 'review_candidate');
    const rep = cluster && representative(rows, fp);
    if (!rep) { process.stderr.write(`aai-feedback-upsert: ${fp} is not a current review_candidate\n`); process.exit(2); }
    // THE DESCRIPTION GATE comes FIRST -- before the auth preflight, the dedup
    // search, the label read and the create -- so a record that cannot carry a
    // certified description is refused with ZERO gh invocations
    // (spec-friction-issues-arrive-without-a-description D3). It is a
    // decision about the record, not about GitHub, and it needs no network.
    const desc = certifiedDescription(rep, args);
    if (!desc.ok) {
      process.stderr.write(descriptionRefusal(fp, desc));
      process.exit(2);
    }
    // Auth preflight: fail fast with a clear message before any work if gh cannot
    // authenticate — the engine holds no token, it borrows the operator's gh session.
    const authState = ghAuthState();
    if (authState !== 'ready') {
      process.stderr.write(`aai-feedback-upsert: ${ghAuthHint(authState)}\n`);
      process.exit(1);
    }
    // Dedup FIRST, fail-closed: if we cannot CONFIRM there is no existing issue
    // (gh unavailable or unparseable output), REFUSE to create — a search hiccup
    // must never fan out into a duplicate.
    // Local-ledger gate BEFORE the network dedup: it costs nothing and it closes
    // the search-index lag window that the remote search cannot.
    if (alreadyFiledLocally(fp, cfg.destination)) {
      process.stdout.write(`this machine already filed an issue for ${fp} (see ${LEDGER}); skipping duplicate create\n`);
      process.exit(0);
    }
    const ds = dedupSearch(cfg.destination, fp);
    if (!ds.searched) {
      // Spec-AC-07: a PARSE failure (gh exited 0, stdout was not the expected
      // JSON) is a DIFFERENT cause than a process failure, and must never be
      // rendered as "(exit 0)" -- a status that reads as "gh said everything
      // is fine". The real (possibly non-zero) status is discarded here on
      // purpose; only a genuine process failure (the else branch) reports it.
      if (ds.parseFailed) {
        process.stderr.write(ghRefusalLine(
          `aai-feedback-upsert: could not verify dedup for ${fp} — refusing to create (gh search exited 0 but its output was not valid JSON: a parse failure, not a process failure)`,
          { ok: false, status: null, stderrFirst: ds.ghResult ? ds.ghResult.stderrFirst : '' },
        ));
      } else {
        process.stderr.write(ghRefusalLine(`aai-feedback-upsert: could not verify dedup for ${fp} — refusing to create`, ds.ghResult || { ok: false, status: null, stderrFirst: '' }));
      }
      process.exit(1);
    }
    if (ds.exists) {
      process.stdout.write(`existing issue carries the marker for ${fp}; skipping duplicate create\n`);
      process.exit(0);
    }
    // Re-verify budget immediately before the write (no stale payload).
    const nowMs = Number(process.env.AAI_NOW_MS) || Date.now();
    if (newIssuesLast7d(nowMs) >= cfg.maxNewPer7d) {
      process.stdout.write(`budget reached (${cfg.maxNewPer7d}/7d) — deferring ${fp}, not filed\n`);
      process.exit(0);
    }
    const payload = buildPayload(rep, cluster, fp, desc);
    const ghArgs = ['issue', 'create', '--repo', cfg.destination, '--title', payload.title, '--body', payload.body];
    // Label degrade (never fail the write over a label). Each drop is NAMED, so a
    // missing label is visible to the operator rather than silently swallowed.
    if (cfg.labels.length) {
      const ls = existingLabels(cfg.destination);
      if (!ls.read) {
        // Spec-AC-07 (fu-existinglabels-discards-status): render the real
        // refusal through ghRefusalLine -- the exit status and the certified
        // stderr detail -- instead of a status-free "could not read".
        process.stderr.write(ghRefusalLine(
          `aai-feedback-upsert: could not read the label set for ${cfg.destination} — filing without labels (${cfg.labels.join(', ')})`,
          ls.ghResult,
        ));
      } else {
        for (const label of cfg.labels) {
          if (hasLabel(ls.names, label)) ghArgs.push('--label', label);
          else if (ls.truncated) process.stderr.write(`aai-feedback-upsert: label "${label}" is not among the first ${LABEL_LIST_LIMIT} labels of ${cfg.destination} — filing without it\n`);
          else process.stderr.write(`aai-feedback-upsert: label "${label}" does not exist in ${cfg.destination} — filing without it\n`);
        }
      }
    }
    const r = runGh(ghArgs, { mutating: true });
    if (!r.ok) {
      process.stderr.write(ghRefusalLine('aai-feedback-upsert: gh issue create failed', r));
      process.exit(1);
    }
    // The issue EXISTS now. If the ledger append fails, the duplicate window this
    // ledger was added to close is reopened, so the failure must be loud and the
    // exit non-zero — a silent success here is the worst outcome available.
    try {
      ensureDir(FRICTION_DIR);
      appendFileSync(LEDGER, JSON.stringify({ event: 'issue_created', fingerprint: fp, ts_ms: nowMs, destination: cfg.destination }) + '\n');
    } catch (e) {
      process.stderr.write(`aai-feedback-upsert: FILED the issue for ${fp} in ${cfg.destination}, but could not record it in ${LEDGER} (${e && e.code ? e.code : 'write failed'}). The local duplicate guard is now blind to this fingerprint — record it by hand before publishing again.\n`);
      process.exit(1);
    }
    // Every filed issue now carries a certified description (the gate above),
    // so the SPEC-0176 Spec-AC-06 analysis comment fires on every publish
    // whose URL certifies. Parse the real issue number from gh's own stdout
    // (D1); an unparseable stdout degrades with a NOTE and a literal
    // placeholder rather than ever echoing the raw blob (D2). The advertised
    // `gh issue comment` command always names the CONFIGURED destination
    // (D3), never one parsed out of the URL, and it is only ever PRINTED
    // here -- never executed (seam S3) -- UNLESS the returned URL is itself
    // certified (Spec-AC-06): then the engine runs that comment itself, once,
    // against the CERTIFIED number (never `parsed.rawNumber`, which a
    // shape-matched-but-uncertified URL also carries -- reading it here would
    // post a certified human sentence to a host or repo that was never
    // certified as the operator's own).
    const parsed = parseIssueUrl(r.stdout, cfg.destination);
    let commentResult = null;
    if (parsed.certified && payload.certifiedSummary) {
      commentResult = runGh(
        ['issue', 'comment', parsed.number, '--repo', cfg.destination, '--body', payload.certifiedSummary],
        { mutating: true },
      );
      if (!commentResult.ok) {
        // The issue is FILED and the ledger entry is WRITTEN already (above);
        // only the follow-up comment failed. Name the real cause and exit
        // non-zero -- a silent success here would hide that the certified
        // analysis never reached the maintainer.
        process.stderr.write(ghRefusalLine('aai-feedback-upsert: gh issue comment failed', commentResult));
        process.stdout.write(`filed issue for ${fp} in ${cfg.destination}\n${parsed.url}\n`);
        process.exit(1);
      }
    }
    const followup = [];
    if (parsed.certified) {
      followup.push(parsed.url);
    } else if (parsed.reason === 'untrusted_url') {
      followup.push(`NOTE: ${parsed.detail} -- verify the filed issue directly in ${cfg.destination} and fill in <issue-number> below by hand.`);
    } else {
      followup.push('NOTE: could not read the issue number from gh\'s output -- fill in <issue-number> below by hand.');
    }
    if (commentResult) {
      followup.push('the certified description was posted as a comment on the filed issue -- mechanism, reproduction steps and anything naming a path go in a hand-written follow-up comment, if needed.');
    } else {
      followup.push('the certified description could not be posted as a comment because the issue URL was not certified -- post it by hand:');
      followup.push(`gh issue comment ${parsed.certified ? parsed.number : '<issue-number>'} --repo ${cfg.destination} --body-file <file>`);
    }
    process.stdout.write(`filed issue for ${fp} in ${cfg.destination}\n${followup.join('\n')}\n`);
    process.exit(0);
  }

  // --- prepare-only default (no mutating call) ---------------------------
  if (cfg.mode !== 'review' || !cfg.destination) {
    process.stdout.write(`mode=${cfg.mode}${cfg.destination ? '' : ' (no destination)'} — nothing prepared to send (local prepare-none)\n`);
    process.exit(0);
  }
  const prepared = prepare(args, cfg);
  if (!prepared.length) { process.stdout.write('no review_candidate clusters to prepare\n'); process.exit(0); }
  // Surface the auth prerequisite up front (prepare still works offline; the
  // eventual --confirm publish needs an authenticated gh).
  const prepAuth = ghAuthState();
  if (prepAuth !== 'ready') {
    process.stdout.write(`note: ${ghAuthHint(prepAuth)} — drafts are prepared, but publishing will need it\n`);
  }
  // Preserve any non-default --config/--report/--spool overrides in the advertised
  // confirmed-write command, so copy/paste targets the same inputs (PR review).
  const overrides = [
    args.config !== DEFAULT_CONFIG ? `--config ${args.config}` : '',
    args.report !== DEFAULT_REPORT ? `--report ${args.report}` : '',
    args.spool !== DEFAULT_SPOOL ? `--spool ${args.spool}` : '',
  ].filter(Boolean).join(' ');
  const ov = overrides ? ` ${overrides}` : '';
  process.stdout.write(`prepared ${prepared.length} issue draft(s) in ${PENDING_DIR} (mode=review, dest=${cfg.destination}):\n`);
  for (const p of prepared) {
    // Only a cluster the engine actually cleared gets a runnable command. A
    // blocked one used to be printed WITH a --publish line that was guaranteed
    // to refuse — an instruction the tool would not honour.
    if (p.status === 'new') {
      process.stdout.write(`  ${p.status.padEnd(24)} ${p.fingerprint}  -> review then: node .aai/scripts/aai-feedback-upsert.mjs${ov} --publish ${p.fingerprint} --confirm\n`);
    } else if (p.refusal) {
      // Already newline-terminated by the renderer (and multi-line when the
      // rate-limit hint fires), so it is written as-is rather than re-wrapped.
      process.stdout.write(`  ${p.status.padEnd(24)} ${p.fingerprint}  -> not offered: ${p.refusal}`);
    } else {
      process.stdout.write(`  ${p.status.padEnd(24)} ${p.fingerprint}  -> not offered: ${BLOCK_REASON[p.status] || p.status}\n`);
    }
  }
}

main();
