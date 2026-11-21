// guard-config.mjs — the SINGLE JS reader of the committed guard-policy file
// docs-audit.yaml (CHANGE-0009 D8, promoted from SPEC-0018 review W2).
//
// Before this module, docs-audit.yaml was parsed by three independent
// implementations (state.mjs readIndependencePolicy, the pre-commit-checks.sh
// grep, the shell grep in the pre-commit hook template
// .aai/templates/git-hooks/pre-commit-index.sh) plus an
// undocumented file-presence coupling in docs-audit.mjs — drift-prone. The
// SHELL greps stay as deliberate thin greps (hooks must not grow importable-
// module plumbing) but a conformance test (tests/skills/test-aai-hygiene-pack.sh
// test_031) feeds the same fixture configs to this reader and the grep patterns
// and asserts they agree — drift now fails a test instead of diverging silently.
//
// Semantics (fail-open, per the pre-refactor state.mjs behavior):
// - a COLUMN-0 line scan (same discipline as the STATE line engine — an
//   indented or commented key is never a dial);
// - dial values: `enforce` | `report-only`; a present-but-INVALID value falls
//   open to report-only AND says so on stderr (CHANGE-0010 review W1 — an
//   operator who typoed `enforced` must not believe enforcement is on);
// - absent file / absent key: report-only, silently.

import fs from 'node:fs';
import path from 'node:path';

export const GUARD_CONFIG_BASENAME = 'docs-audit.yaml';

// The closed set of enforce/report-only guard dials this reader owns.
// `product_doc_gate` (spec-product-docs-enforced D3) mirrors `close_gate`:
// same grammar, same fail-open default, consulted by close-work-item.mjs to
// choose warn-vs-refuse for its pre-write product-doc gate.
// `usage_capture_gate` (spec-telemetry-completeness) mirrors product_doc_gate:
// same grammar and fail-open default, consulted by close-work-item.mjs to
// choose warn-vs-refuse for its pre-write close-time usage-capture gate. Like
// product_doc_gate it is a close-only dial (NOT a pre-commit-hook concern), so
// the shell greps in pre-commit-checks.sh deliberately do not cover it.
// `evidence_path_gate` (CHANGE-0131 / spec-evidence-path-gate) mirrors both:
// same grammar and fail-open default, consulted by close-work-item.mjs to
// choose warn-vs-refuse when a closing doc's AC Status Evidence cells cite a
// path-shaped token that does not resolve from the repo root. Close-only —
// the shell greps deliberately do not cover it either.
// `mutation_gate` (spec-mutation-gate-for-tests D12) is the sixth dial of the
// same shape: consulted by close-work-item.mjs to choose warn-vs-refuse when
// a closing ride's spec is applicable (mutation_gate: v1 marker + tdd/hybrid
// strategy) and mutation-gate.mjs exits non-zero for it. Unlike the other
// five, AAI core SHIPS this one `enforce` (this repository is the one making
// the mutation-evidence claim) rather than report-only — readGuardConfig's
// own fail-open DEFAULT below stays report-only regardless (an absent key in
// a vendored project must still fail open), only the shipped
// docs/ai/docs-audit.yaml line differs.
export const GUARD_DIALS = ['independence', 'close_gate', 'doc_number_guard', 'product_doc_gate', 'usage_capture_gate', 'evidence_path_gate', 'mutation_gate'];

// Presence probe shared with docs-audit.mjs mode detection (enforced vs
// report-only hangs off this file's existence — documented coupling, D8).
export function guardConfigPresent(dir) {
  return fs.existsSync(path.join(dir, GUARD_CONFIG_BASENAME));
}

// readGuardConfig(dir) -> { present, cfgPath, raw,
//                           independence, close_gate, doc_number_guard }
// `dir` is the directory CONTAINING docs-audit.yaml (docs/ai for the real
// repo; state.mjs passes dirname(statePath) so fixtures isolate for free).
// opts.warnPrefix prefixes the invalid-value stderr notice (state.mjs passes
// 'state' to keep its pre-refactor wording byte-identical); opts.warn
// overrides the sink (tests).
export function readGuardConfig(dir, opts = {}) {
  const warnPrefix = opts.warnPrefix ?? 'guard-config';
  const warn = opts.warn ?? (m => console.error(m));
  const cfgPath = path.join(dir, GUARD_CONFIG_BASENAME);
  const out = {
    present: false,
    cfgPath,
    raw: null,
    independence: 'report-only',
    close_gate: 'report-only',
    doc_number_guard: 'report-only',
    product_doc_gate: 'report-only',
    usage_capture_gate: 'report-only',
    evidence_path_gate: 'report-only',
    mutation_gate: 'report-only',
  };
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return out;   // absent file: fail-open defaults, silently
  }
  out.present = true;
  out.raw = raw;
  const seen = new Set();
  for (const line of raw.split(/\r?\n/)) {
    // Value = the full non-whitespace token (review CHANGE-0009 W2): a glued
    // comment ("enforce# note") therefore yields the token "enforce#", which
    // fails the closed-set check below and falls open WITH a warning — the
    // same verdict the hooks' grep boundary (enforce([[:space:]]|$)) reaches.
    const m = line.match(/^(independence|close_gate|doc_number_guard|product_doc_gate|usage_capture_gate|evidence_path_gate|mutation_gate):\s*(\S+)/);
    if (!m || seen.has(m[1])) continue;   // column-0 only; first occurrence wins
    seen.add(m[1]);
    if (m[2] !== 'enforce' && m[2] !== 'report-only') {
      warn(`${warnPrefix}: WARNING ${m[1]} value "${m[2]}" in ${cfgPath} is not `
        + '"enforce" or "report-only" — treating as report-only (fail-open default)');
    }
    out[m[1]] = m[2] === 'enforce' ? 'enforce' : 'report-only';
  }
  return out;
}

// coupled_families (CHANGE-0035 / SPEC-0047 D7) — an OPTIONAL list-shaped key,
// read separately from the enforce/report-only dials above (a genuinely
// different grammar: a YAML block list, not a scalar). Line-parser-friendly:
//   coupled_families:
//     - CHANGE+SPEC-CHANGE
// Each list item is a '+'-joined group of prefixes sharing one counter (D7).
// Absent key / absent file / a group with fewer than 2 members -> ignored
// (fail-open: no coupling). AAI core ships this key ABSENT.
export function readCoupledFamilies(dir) {
  const cfgPath = path.join(dir, GUARD_CONFIG_BASENAME);
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return [];
  }
  const groups = [];
  let inKey = false;
  for (const line of raw.split(/\r?\n/)) {
    if (/^coupled_families:\s*(#.*)?$/.test(line)) { inKey = true; continue; }
    if (!inKey) continue;
    const item = line.match(/^[ \t]+-\s*([A-Za-z0-9+_-]+)\s*(#.*)?$/);
    if (item) {
      const members = item[1].split('+').map((s) => s.trim().toUpperCase()).filter(Boolean);
      if (members.length > 1) groups.push(members);
      else console.error(`WARNING: coupled_families item "${item[1]}" has fewer than 2 members — ignored (coupling OFF for it)`);
      continue;
    }
    if (/^[^\s#]/.test(line)) inKey = false; // next column-0 key ends the block
    else if (/^[ \t]+-/.test(line) && line.trim() !== '-') {
      // list item that did NOT match the member grammar (spaces, bad chars):
      // silent ignore here would silently disable coupling (review-20260717T181026Z NB-2)
      console.error(`WARNING: coupled_families item ${JSON.stringify(line.trim())} does not match TYPE+TYPE grammar — ignored (coupling OFF for it)`);
    }
  }
  return groups;
}

// ref_guard: armed | declined (spec-update-installs-ref-guard-undisclosed D2/
// D3) — a SEPARATE closed vocabulary from GUARD_DIALS, deliberately NOT added
// to that array: the grammar differs (armed/declined, not enforce/report-
// only) and, more importantly, the FAIL DIRECTION differs. GUARD_DIALS is
// grep-mirrored by pre-commit-checks.sh; ref_guard's mirror lives in
// install-pre-commit-hook.sh (D5's own thin shell grep — no node import
// there, per check-vendored-script-deps.mjs), conformance-tested by
// tests/skills/test-aai-hygiene-pack.sh test_618.
export const REF_GUARD_POLICY = ['armed', 'declined'];
const REF_GUARD_KEY_LINE = /^ref_guard:/;
const BOM = '\uFEFF';

// readRefGuardPolicy(dir) -> 'armed' | 'declined'
// Column-0 `ref_guard: <value>` line scan in docs-audit.yaml, same line
// discipline as readGuardConfig (indented/commented lines are never a dial;
// the value is the full non-whitespace token, so a glued comment fails the
// closed-set check). UNLIKE every enforce/report-only dial above, this FAILS
// CLOSED to 'armed': an absent file, an absent key, an indented or commented
// key, and any value outside {armed, declined} all mean 'armed' (D3). Falling
// open on the OTHER dials degrades a REPORT; falling open here would
// silently disarm a SAFEGUARD on a typo — the asymmetry is deliberate. An
// out-of-vocabulary value is named on stderr, mirroring the other dials'
// invalid-value notice.
export function readRefGuardPolicy(dir, opts = {}) {
  const warnPrefix = opts.warnPrefix ?? 'guard-config';
  const warn = opts.warn ?? (m => console.error(m));
  const cfgPath = path.join(dir, GUARD_CONFIG_BASENAME);
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return 'armed';   // absent file: fail-CLOSED default (D3)
  }
  // A single leading BOM is not part of line 1 (DR-16: an editor-saved file reads as the editor meant it).
  if (raw.startsWith(BOM)) raw = raw.slice(BOM.length);
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^ref_guard:\s*(\S+)/);
    if (!m) continue;   // column-0 only; first occurrence wins
    if (m[1] === 'armed' || m[1] === 'declined') {
      return m[1];
    }
    warn(`${warnPrefix}: WARNING ref_guard value "${m[1]}" in ${cfgPath} is not `
      + '"armed" or "declined" — treating as armed (fail-CLOSED default)');
    return 'armed';   // invalid value: fail-CLOSED default (D3)
  }
  return 'armed';   // absent key: fail-CLOSED default (D3)
}

// --- Ref-guard interpreter lookup (spec-a-check-cannot-tell-silence-from-a-
// verdict D3) ----------------------------------------------------------------
//
// aai-doctor's CAT-17 probe runs the reference-transaction hook FILE itself.
// On POSIX the OS loader honours the shebang, so there is exactly one
// launcher: exec the file. Windows has no OS-level shebang support, so the
// probe must name an interpreter — and the one it used to name was bare `sh`
// then bare `bash`. On a PowerShell host without Git Bash on PATH that is
// ENOENT followed by `C:\Windows\system32\bash.exe`, i.e. WSL: a different
// filesystem, a different environment, and a hook that cannot refuse what it
// cannot see (GitHub #369, spec M4).
//
// Git for Windows ships its own POSIX shell beside its exec-path, and that is
// the interpreter Git ITSELF would use to run this hook. So: derive it, and
// put it FIRST. This function is PURE and fully injectable (`platform`,
// `gitExecPath`, `exists`) so the win32 branch is testable on any OS —
// what that CANNOT prove is that a real Git for Windows install has this
// layout (residual risk R1; the behavioural evidence is the windows-wsl1 CI
// step, not a local green).

// `…/Git/mingw64/libexec/git-core` -> `…/Git/usr/bin/sh.exe`, or null when the
// exec-path is empty or not absolute. win32 semantics explicitly, so the
// derivation is identical whether this runs on Windows or on a POSIX host
// evaluating a synthetic path; `path.win32` accepts both separators.
function gitForWindowsShell(gitExecPath) {
  const w = path.win32;
  const core = String(gitExecPath || '').trim().replace(/[\\/]+$/, '');
  if (core === '' || !w.isAbsolute(core)) return null;
  // Three levels up from git-core: libexec, then mingw64/mingw32, then the
  // installation root. A relative resolve would silently borrow this
  // process's cwd, which is why the isAbsolute guard above is not optional.
  const root = w.resolve(core, '..', '..', '..');
  return w.join(root, 'usr', 'bin', 'sh.exe');
}

// resolveRefGuardLaunchers({ platform, hookPath, gitExecPath, exists })
// -> [[command, args], …] in the order the probe should try them.
export function resolveRefGuardLaunchers({
  platform,
  hookPath,
  gitExecPath = '',
  exists = () => false,
} = {}) {
  if (platform !== 'win32') {
    return [[hookPath, ['prepared']]];
  }
  const launchers = [];
  const gitShell = gitForWindowsShell(gitExecPath);
  // `exists` gates it: an exec-path of an unexpected shape must degrade to
  // the bare-name search, never to a spawn of a path nobody confirmed.
  if (gitShell && exists(gitShell)) launchers.push([gitShell, [hookPath, 'prepared']]);
  launchers.push(['sh', [hookPath, 'prepared']]);
  launchers.push(['bash', [hookPath, 'prepared']]);
  return launchers;
}

// The full coupled group containing `prefix` (including `prefix` itself), or
// the singleton [prefix] when it is in no configured group (the default,
// uncoupled case — D7 "AAI core ships the key absent").
export function coupledGroupFor(groups, prefix) {
  const p = String(prefix).toUpperCase();
  for (const g of groups) {
    if (g.includes(p)) return g;
  }
  return [p];
}

// writeRefGuardPolicy(dir, value, { seedFrom, dryRun, rename, readBack }) -> { path, seeded, changed, removed } (a dry run adds keyLines)
// The single writer of the ref_guard line in <dir>/docs-audit.yaml (hook installer port, D-POLICY, DR-15 to DR-17).
// `value` is armed or declined. The first column-0 `ref_guard:` line (valued or not) becomes `ref_guard: <value>`
// with its own terminator, every later one is removed (their 1-based line numbers are returned in `removed`), and
// with none the line is appended using the file's terminator. The file is read and written as bytes (latin1), so
// every other byte, each line's own terminator and a leading BOM survive. A symbolic link is followed and kept; the
// bytes go to a temp sibling of the real target and are renamed over it, so the target's permission bits stay.
// `seeded` is 'template' (an absent file started from the bytes of `seedFrom`), 'empty' (an absent file started
// empty) or null. `dryRun` reports `keyLines` and `removed` and writes nothing. `rename` and `readBack` are test seams.
const refusedWrite = (cfgPath) => new Error(`${cfgPath} is not writable; nothing was written`);

function resolveWriteTarget(cfgPath) {
  let st;
  try {
    st = fs.lstatSync(cfgPath);
  } catch {
    return { target: cfgPath, exists: false };
  }
  if (!st.isSymbolicLink()) return { target: cfgPath, exists: true };
  const refused = () => new Error(`${cfgPath} is a symbolic link to ${fs.readlinkSync(cfgPath)}; nothing was written`);
  let target;
  try {
    target = fs.realpathSync(cfgPath);
  } catch {
    throw refused();
  }
  if (!fs.statSync(target).isFile()) throw refused();
  return { target, exists: true };
}

function composePolicy(current, value) {
  const bomBytes = Buffer.from(BOM, 'utf8').toString('latin1');
  const bom = current.startsWith(bomBytes) ? bomBytes : '';
  const lines = current.slice(bom.length).match(/[^\n]*\n|[^\n]+$/g) ?? [];
  const terminator = (line) => (line.endsWith('\r\n') ? '\r\n' : line.endsWith('\n') ? '\n' : '');
  const keyLines = [];
  lines.forEach((line, i) => { if (REF_GUARD_KEY_LINE.test(line)) keyLines.push(i + 1); });
  const removed = keyLines.slice(1);
  if (keyLines.length === 0) {
    const last = lines.length ? lines[lines.length - 1] : '';
    const eol = lines.find((l) => terminator(l) !== '') ? terminator(lines.find((l) => terminator(l) !== '')) : '\n';
    const head = lines.length && terminator(last) === '' ? [...lines.slice(0, -1), last + eol] : lines;
    return { text: bom + [...head, `ref_guard: ${value}${eol}`].join(''), keyLines, removed };
  }
  const out = [];
  lines.forEach((line, i) => {
    if (i + 1 === keyLines[0]) out.push(`ref_guard: ${value}${terminator(line)}`);
    else if (!removed.includes(i + 1)) out.push(line);
  });
  return { text: bom + out.join(''), keyLines, removed };
}

export function writeRefGuardPolicy(dir, value, opts = {}) {
  if (!REF_GUARD_POLICY.includes(value)) throw new Error(`ref_guard value must be armed or declined, got ${JSON.stringify(value)}`);
  const cfgPath = path.join(dir, GUARD_CONFIG_BASENAME);
  const { target, exists } = resolveWriteTarget(cfgPath);
  let seeded = null;
  let current = null;
  let seedBytes = null;
  if (exists) {
    current = fs.readFileSync(target);
  } else if (opts.seedFrom && fs.existsSync(opts.seedFrom) && fs.statSync(opts.seedFrom).isFile()) {
    seedBytes = fs.readFileSync(opts.seedFrom);
    seeded = 'template';
  } else {
    seeded = 'empty';
  }
  const base = current ?? seedBytes ?? Buffer.alloc(0);
  const { text, keyLines, removed } = composePolicy(base.toString('latin1'), value);
  if (opts.dryRun) return { path: cfgPath, seeded: null, changed: false, removed, keyLines };
  const next = Buffer.from(text, 'latin1');
  if (current && current.equals(next)) {
    const same = (opts.readBack ?? readRefGuardPolicy)(dir, { warn: () => {} });
    if (same !== value) throw new Error(`wrote ref_guard: ${value} to ${cfgPath} but reading it back gives ${same}`);
    return { path: cfgPath, seeded: null, changed: false, removed };
  }
  if (exists) {
    try {
      fs.accessSync(target, fs.constants.W_OK);
    } catch {
      throw refusedWrite(cfgPath);
    }
  } else {
    fs.mkdirSync(dir, { recursive: true });
  }
  const mode = exists ? fs.statSync(target).mode & 0o777 : 0o666;
  const tmp = `${target}.aai-tmp.${process.pid}`;
  let fd;
  try {
    try {
      fd = fs.openSync(tmp, 'wx', mode);
    } catch (e) {
      if (e && (e.code === 'EACCES' || e.code === 'EPERM' || e.code === 'EROFS')) throw refusedWrite(cfgPath);
      throw e;
    }
    if (exists) fs.fchmodSync(fd, mode);
    fs.writeSync(fd, next);
    fs.closeSync(fd);
    fd = undefined;
    (opts.rename ?? fs.renameSync)(tmp, target);
  } catch (e) {
    if (fd !== undefined) fs.closeSync(fd);
    fs.rmSync(tmp, { force: true });
    throw e;
  }
  const got = (opts.readBack ?? readRefGuardPolicy)(dir, { warn: () => {} });
  if (got !== value) throw new Error(`wrote ref_guard: ${value} to ${cfgPath} but reading it back gives ${got}`);
  return { path: cfgPath, seeded, changed: true, removed };
}
