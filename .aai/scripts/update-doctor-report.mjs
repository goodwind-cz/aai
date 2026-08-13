#!/usr/bin/env node
// update-doctor-report.mjs — post-update doctor field report (CHANGE-0137 /
// spec-update-doctor-field-report).
//
// The ONE implementation both update entrypoints call after a SUCCESSFUL,
// non-dry-run sync (D1 — never twin shell implementations): reads the
// project-local config dial, runs the freshly-vendored doctor with --json
// under a hard timeout, writes a provenance-stamped field report under
// docs/ai/reports/ (runtime-ignored by the vendored .gitignore, so it can
// never dirty the target's tree), prunes old reports, and prints exactly ONE
// stdout line per run:
//
//   DOCTOR <CLEAN|ISSUES(n)> - full report: docs/ai/reports/doctor-<...>.md
//   DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off)
//   DOCTOR-REPORT SKIP <reason> - update unaffected
//
// Named degrade reasons (D4 — one per line, never silence, never a crash):
// doctor script missing / doctor spawn failed / doctor timed out after Ns /
// doctor usage error (exit 2) / doctor output unparseable / report write
// failed. Doctor exit 1 is NOT a failure of this step — a FAIL-bearing
// machine is exactly the machine the fleet wants a report from: the report
// is still written and the line carries ISSUES.
//
// Exit contract (mirrors update-check.mjs): exit 0 for EVERY runtime
// outcome; exit 2 only for a CLI usage error. The wrapper postambles add a
// second guard layer: even a crash here degrades to the wrapper's own named
// SKIP line and the update's exit code is untouched.
//
// Config (SPEC-0106 precedent — column-0 line scan, NOT a YAML lib):
//   post_update_doctor: on | off   in docs/ai/update-config.yaml
//   absent file or absent key == on; off prints the named disabled line;
//   an unknown value warns on stderr and behaves as on (the default is
//   read-only and non-destructive, so a typo lands on the safe direction).
//
// Usage:
//   node update-doctor-report.mjs [--root <path>] [--config <path>]
//     [--doctor <path>] [--timeout-ms <n>] [--max-reports <n>]
//   --root        target project root (default: two levels up from this
//                 script's own location — doctor precedent).
//   --config      config path (default <root>/docs/ai/update-config.yaml).
//   --doctor      doctor script path (default <root>/.aai/scripts/aai-doctor.mjs;
//                 test override).
//   --timeout-ms  doctor spawn bound, default 240000 (Windows CAT-14 alone
//                 may burn up to its 170 s internal bound — decisions
//                 2026-08-13).
//   --max-reports retention cap, default 10. Only files matching the exact
//                 shape doctor-<yyyymmdd>T<HHMMSS>Z-<tag>.md are ever pruned
//                 — sync-conflicts and validation reports are untouchable by
//                 construction.
//
// Zero network, zero LLM, zero dependencies beyond node built-ins.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const DEFAULT_TIMEOUT_MS = 240_000;
const DEFAULT_MAX_REPORTS = 10;
const REPORT_SHAPE = /^doctor-\d{8}T\d{6}Z-[a-z0-9-]+\.md$/;

function usageFail(msg) {
  console.error(`update-doctor-report: ${msg}`);
  console.error(
    'Usage: update-doctor-report [--root <path>] [--config <path>] '
    + '[--doctor <path>] [--timeout-ms <n>] [--max-reports <n>]',
  );
  process.exit(2);
}

function parseArgs(argv) {
  const args = {
    root: null, config: null, doctor: null,
    timeoutMs: DEFAULT_TIMEOUT_MS, maxReports: DEFAULT_MAX_REPORTS,
  };
  const toks = argv.slice(2);
  for (let i = 0; i < toks.length; i++) {
    const tok = toks[i];
    const need = (name) => {
      const v = toks[++i];
      if (v === undefined) usageFail(`${name} needs a value`);
      return v;
    };
    if (tok === '--root') args.root = path.resolve(need('--root'));
    else if (tok === '--config') args.config = path.resolve(need('--config'));
    else if (tok === '--doctor') args.doctor = path.resolve(need('--doctor'));
    else if (tok === '--timeout-ms') {
      const n = Number.parseInt(need('--timeout-ms'), 10);
      if (!Number.isInteger(n) || n <= 0) usageFail('--timeout-ms must be a positive integer');
      args.timeoutMs = n;
    } else if (tok === '--max-reports') {
      const n = Number.parseInt(need('--max-reports'), 10);
      if (!Number.isInteger(n) || n <= 0) usageFail('--max-reports must be a positive integer');
      args.maxReports = n;
    } else usageFail(`unknown flag: ${tok}`);
  }
  return args;
}

// One line, one outcome (D4). SKIP lines are the ONLY output of a degraded
// run; the success line is the ONLY output of a good one.
function emitSkip(reason) {
  // fs.writeSync to fd 1 is synchronous even on an async pipe (the Windows
  // PS pipeline), so the line can never be dropped by the process.exit that
  // callers rely on for never-returns control flow (review NB-1 class).
  fs.writeSync(1, `DOCTOR-REPORT SKIP ${reason} - update unaffected\n`);
  process.exit(0);
}

// --- Config (column-0 scan; first occurrence wins — resolveConfig precedent)

function resolvePostUpdateDoctor(cfgPath) {
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch (e) {
    // CHANGE-0138: only ENOENT is the silent absent==on default. A config
    // that EXISTS but cannot be read (EISDIR, EACCES, ...) is named on
    // stderr — never a silent default — and still behaves as on (the step
    // is read-only and bounded, so degradation lands on the safe direction).
    if (e && e.code !== 'ENOENT') {
      console.error(`update-doctor-report: WARNING config ${cfgPath} exists but `
        + `could not be read (${(e && e.code) || 'unknown error'}) - treating as on `
        + '(the default; this step is read-only and bounded)');
    }
    return 'on'; // absent file == on (D2)
  }
  // CHANGE-0138 (NB-2/D3): a UTF-8 BOM must not hide a FIRST-LINE column-0
  // key from the parser (`^` anchors at the BOM character). Only index 0 is
  // stripped, exactly once — a BOM sequence on a later line is content
  // (ZWNBSP), not a BOM. This statement is byte-identical to its twin in
  // update-check.mjs resolveConfig (SEAM-3 parity invariant; deliberately
  // vendored twice, never a shared import — both files are standalone).
  if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^post_update_doctor:\s*(\S+)/);
    if (!m) continue; // column-0 only; indented/commented keys are never a dial
    if (m[1] === 'on' || m[1] === 'off') return m[1];
    console.error(`update-doctor-report: WARNING post_update_doctor value "${m[1]}" `
      + `in ${cfgPath} is not "on" or "off" - treating as on (the default; this `
      + 'step is read-only and bounded)');
    return 'on';
  }
  return 'on'; // key absent == on
}

// --- Provenance (D3) --------------------------------------------------------

function readLineValue(text, key) {
  if (!text) return null;
  const m = text.match(new RegExp(`^-\\s*${key}:\\s*(.+)$`, 'm'));
  if (!m) return null;
  const v = m[1].trim();
  // A template placeholder ("<set by sync script>") is not a stamp — mirror
  // aai-doctor.mjs readProfileFromPin's tolerance.
  if (!v || /^<.*>$/.test(v)) return null;
  return v;
}

function readTextIfAny(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

function resolveProvenance(root) {
  const pin = readTextIfAny(path.join(root, '.aai/system/AAI_PIN.md'));
  let version = readLineValue(pin, 'Template version');
  const commit = readLineValue(pin, 'Template commit') || 'UNKNOWN';
  if (!version) {
    const versionFile = readTextIfAny(path.join(root, 'docs/ai/AAI_VERSION.md'));
    version = readLineValue(versionFile, 'Version');
  }
  return { version: version || 'UNKNOWN', commit };
}

function machineTag() {
  let tag = '';
  try { tag = String(os.hostname() || ''); } catch { /* fall through */ }
  tag = tag.toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '');
  if (!tag) tag = 'unknown-host';
  return tag.slice(0, 40);
}

function utcStamp(d) {
  const p = (n, w = 2) => String(n).padStart(w, '0');
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}T`
    + `${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`;
}

// --- Retention (D3): prune ONLY the exact doctor-report shape ---------------

// CHANGE-0138 (D4): prune stays best-effort — a failure never degrades the
// run, the stdout line, or the exit code — but stops being silent: AT MOST
// ONE stderr line per run names the first failed path plus the count of
// additional failures. An unreadable reports directory produces the same
// single line naming the directory. Zero failures emit zero prune stderr.
function pruneReports(reportsDir, maxReports) {
  const failed = [];
  try {
    const shaped = fs.readdirSync(reportsDir)
      .filter((f) => REPORT_SHAPE.test(f))
      .sort() // the UTC stamp is the sortable prefix: ascending == oldest first
      .reverse();
    for (const f of shaped.slice(maxReports)) {
      const p = path.join(reportsDir, f);
      try { fs.unlinkSync(p); } catch (e) { failed.push({ path: p, code: (e && e.code) || 'unknown error' }); }
    }
  } catch (e) {
    failed.push({ path: reportsDir, code: (e && e.code) || 'unknown error' });
  }
  if (failed.length > 0) {
    const extra = failed.length > 1 ? ` and ${failed.length - 1} more` : '';
    console.error(`update-doctor-report: WARNING retention prune failed for `
      + `${failed[0].path} (${failed[0].code})${extra}`);
  }
}

// --- Main --------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv);
  const selfDir = path.dirname(fileURLToPath(import.meta.url));
  const root = args.root || path.resolve(selfDir, '..', '..');
  const cfgPath = args.config || path.join(root, 'docs/ai/update-config.yaml');
  const doctor = args.doctor || path.join(root, '.aai/scripts/aai-doctor.mjs');

  if (resolvePostUpdateDoctor(cfgPath) === 'off') {
    fs.writeSync(1, 'DOCTOR-REPORT SKIP disabled by config (post_update_doctor: off)\n');
    process.exit(0);
  }

  if (!fs.existsSync(doctor)) emitSkip('doctor script missing');

  let res;
  try {
    res = spawnSync(process.execPath, [doctor, '--root', root, '--json'], {
      encoding: 'utf8', timeout: args.timeoutMs, killSignal: 'SIGKILL',
    });
  } catch (e) {
    res = { error: e };
  }
  if (res.error) {
    const timedOut = res.error.code === 'ETIMEDOUT' || res.error.killed === true;
    if (timedOut) emitSkip(`doctor timed out after ${Math.round(args.timeoutMs / 1000)}s`);
    emitSkip('doctor spawn failed');
  }
  // A SIGKILLed child can also surface as signal-with-null-status.
  if (res.status === null) {
    if (res.signal) emitSkip(`doctor timed out after ${Math.round(args.timeoutMs / 1000)}s`);
    emitSkip('doctor spawn failed');
  }
  if (res.status === 2) emitSkip('doctor usage error (exit 2)');

  const stdout = res.stdout || '';
  let doc;
  try {
    doc = JSON.parse(stdout);
  } catch {
    doc = null;
  }
  if (!doc || typeof doc !== 'object') emitSkip('doctor output unparseable');

  // Provenance header + the doctor JSON byte-verbatim in ONE fenced block.
  const prov = resolveProvenance(root);
  const now = new Date();
  const tag = machineTag();
  const relPath = `docs/ai/reports/doctor-${utcStamp(now)}-${tag}.md`;
  const verdict = doc.verdict === 'CLEAN' ? 'CLEAN' : `ISSUES(${doc.issues ?? '?'})`;
  const embedded = stdout.endsWith('\n') ? stdout : `${stdout}\n`;
  const body = '# Doctor field report\n'
    + '\n'
    + `- Generated at (UTC): ${now.toISOString()}\n`
    + `- AAI version: ${prov.version}\n`
    + `- AAI commit: ${prov.commit}\n`
    + `- Platform: ${process.platform}-${os.arch()} (${os.release()}), node ${process.version}\n`
    + `- Machine: ${tag}\n`
    + `- Doctor exit: ${res.status} (verdict ${doc.verdict}, issues ${doc.issues})\n`
    + '\n'
    + '```json\n'
    + embedded
    + '```\n';

  const reportsDir = path.join(root, 'docs/ai/reports');
  try {
    fs.mkdirSync(reportsDir, { recursive: true });
    // Atomic publish (PR #252 bot sweep, torn-write class): write the whole
    // body to a same-directory temp name, then rename into the final name —
    // the repo's learned-append.mjs pattern. A reader (or a crash mid-write)
    // can never observe a half-written report under the canonical name.
    const finalPath = path.join(root, relPath);
    const tmpPath = finalPath + '.tmp';
    fs.writeFileSync(tmpPath, body);
    fs.renameSync(tmpPath, finalPath);
  } catch {
    emitSkip('report write failed');
  }

  pruneReports(reportsDir, args.maxReports);

  console.log(`DOCTOR ${verdict} - full report: ${relPath}`);
  // Review NB-1 (PR round): process.exit(0) can drop the line above
  // unflushed when stdout is an async pipe (the Windows PS pipeline) —
  // a silent postamble at exit 0 that no fallback would catch. Setting
  // exitCode and returning lets Node drain stdout before exiting.
  process.exitCode = 0;
}

main();
