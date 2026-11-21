// aai-update-fixtures.mjs - the fixture data and builders of the update-on-node ride's differential corpora
// (docs/specs/SPEC-DRAFT-update-on-node.md, D-CORPUS, cases U01 to U23). No update entry point is started here;
// only git is run, in scratch directories the caller created.
//
// A source is a scratch git repository (branches main and dev, a fixed identity and fixed dates so that a
// rebuilt copy has the same commit ids) whose two sync stubs do the same thing: print FX-SYNC, FX-GTP and
// FX-RUNNER lines, copy a pin variant, two conflict reports with fixed mtimes, the doctor helper and a stub
// doctor into the target, and exit with FX_SYNC_EXIT (the PowerShell stub throws on FX_SYNC_THROW). The knobs
// are environment variables without the AAI_ prefix: FX_PIN (plain|bom|none), FX_REPORTS (two|tie|none),
// FX_HELPER (real|broken|none), FX_SYNC_EXIT, FX_SYNC_THROW.

import { spawnSync } from 'node:child_process';
import { chmodSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

export const GIT_IDENTITY = {
  GIT_AUTHOR_NAME: 'fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid', GIT_AUTHOR_DATE: '2026-01-01T00:00:00Z',
  GIT_COMMITTER_NAME: 'fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid', GIT_COMMITTER_DATE: '2026-01-01T00:00:00Z',
};
export const TARGET_ORIGIN = 'https://github.com/acme/target.git';

export function git(cwd, args, env) {
  const r = spawnSync('git', args, { cwd, env: { ...env, ...GIT_IDENTITY }, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} in ${cwd}: exit ${r.status}: ${r.stderr}`);
  return r.stdout;
}

const SYNC_SH = `#!/usr/bin/env bash
set -u
target="$1"
src="$(cd "$(dirname "$0")/../.." && pwd)"
data="$src/fx-data"
echo "FX-SYNC target=$target"
echo "FX-GTP=\${GIT_TERMINAL_PROMPT-unset}"
echo "FX-RUNNER=\${AAI_UPDATE_SYNC_RUNNER-unset}"
mkdir -p "$target/.aai/scripts" "$target/.aai/system" "$target/docs/ai"
cp "$data/aai-doctor.mjs" "$target/.aai/scripts/aai-doctor.mjs"
case "\${FX_HELPER:-real}" in
  real) cp "$data/helper-real.mjs" "$target/.aai/scripts/update-doctor-report.mjs" ;;
  broken) cp "$data/helper-broken.mjs" "$target/.aai/scripts/update-doctor-report.mjs" ;;
esac
case "\${FX_PIN:-plain}" in
  plain) cp "$data/pin-plain.md" "$target/.aai/system/AAI_PIN.md" ;;
  bom) cp "$data/pin-bom-crlf.md" "$target/.aai/system/AAI_PIN.md" ;;
esac
case "\${FX_REPORTS:-two}" in
  two|tie)
    mkdir -p "$target/docs/ai/reports"
    cp "$data/report-a.md" "$target/docs/ai/reports/sync-conflicts-20260101-000000.md"
    cp "$data/report-b.md" "$target/docs/ai/reports/sync-conflicts-20260102-000000.md"
    if [ "\${FX_REPORTS:-two}" = two ]; then
      touch -t 202601020000.00 "$target/docs/ai/reports/sync-conflicts-20260101-000000.md"
      touch -t 202601030000.00 "$target/docs/ai/reports/sync-conflicts-20260102-000000.md"
    else
      touch -t 202601030000.00 "$target/docs/ai/reports/sync-conflicts-20260101-000000.md"
      touch -t 202601030000.00 "$target/docs/ai/reports/sync-conflicts-20260102-000000.md"
    fi
    ;;
esac
if [ -n "\${FX_SYNC_EXIT:-}" ]; then exit "$FX_SYNC_EXIT"; fi
exit 0
`;

const SYNC_PS1 = `param([string]$TargetRoot)
$src = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$data = Join-Path $src 'fx-data'
Write-Host "FX-SYNC target=$TargetRoot"
$gtp = $env:GIT_TERMINAL_PROMPT; if ($null -eq $gtp) { $gtp = 'unset' }
Write-Host "FX-GTP=$gtp"
$rn = $env:AAI_UPDATE_SYNC_RUNNER; if ($null -eq $rn) { $rn = 'unset' }
Write-Host "FX-RUNNER=$rn"
foreach ($d in '.aai/scripts', '.aai/system', 'docs/ai') { New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot $d) | Out-Null }
Copy-Item -LiteralPath (Join-Path $data 'aai-doctor.mjs') -Destination (Join-Path $TargetRoot '.aai/scripts/aai-doctor.mjs')
$helper = $env:FX_HELPER; if (-not $helper) { $helper = 'real' }
if ($helper -eq 'real') { Copy-Item -LiteralPath (Join-Path $data 'helper-real.mjs') -Destination (Join-Path $TargetRoot '.aai/scripts/update-doctor-report.mjs') }
if ($helper -eq 'broken') { Copy-Item -LiteralPath (Join-Path $data 'helper-broken.mjs') -Destination (Join-Path $TargetRoot '.aai/scripts/update-doctor-report.mjs') }
$pin = $env:FX_PIN; if (-not $pin) { $pin = 'plain' }
if ($pin -eq 'plain') { Copy-Item -LiteralPath (Join-Path $data 'pin-plain.md') -Destination (Join-Path $TargetRoot '.aai/system/AAI_PIN.md') }
if ($pin -eq 'bom') { Copy-Item -LiteralPath (Join-Path $data 'pin-bom-crlf.md') -Destination (Join-Path $TargetRoot '.aai/system/AAI_PIN.md') }
$reports = $env:FX_REPORTS; if (-not $reports) { $reports = 'two' }
if ($reports -eq 'two' -or $reports -eq 'tie') {
  $dir = Join-Path $TargetRoot 'docs/ai/reports'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $a = Join-Path $dir 'sync-conflicts-20260101-000000.md'
  $b = Join-Path $dir 'sync-conflicts-20260102-000000.md'
  Copy-Item -LiteralPath (Join-Path $data 'report-a.md') -Destination $a
  Copy-Item -LiteralPath (Join-Path $data 'report-b.md') -Destination $b
  $new = [DateTime]::new(2026, 1, 3, 0, 0, 0, [DateTimeKind]::Utc)
  $old = [DateTime]::new(2026, 1, 2, 0, 0, 0, [DateTimeKind]::Utc)
  if ($reports -eq 'tie') { $old = $new }
  [System.IO.File]::SetLastWriteTimeUtc($a, $old)
  [System.IO.File]::SetLastWriteTimeUtc($b, $new)
}
if ($env:FX_SYNC_THROW) { throw 'fx sync threw' }
if ($env:FX_SYNC_EXIT) { exit [int]$env:FX_SYNC_EXIT }
`;

const DOCTOR_STUB = `console.log(JSON.stringify({
  root: 'stub', generatedAt: '2026-01-01T00:00:00.000Z',
  categories: [{ id: 'CAT-01', name: 'Core Files', status: 'PASS', reason: 'stub' }],
  verdict: 'CLEAN', issues: 0, exit: 0,
}, null, 2));
`;

const PIN_LINES = [
  '# AAI Pin version file', '', '- Template version: 0.1.0', '- Source: acme/aai', '- Commit: abc1234', '- Canonical: yes', '- Ref: main',
  '- Synced at (UTC): 2026-01-01T00:00:00Z', '- Notes: nothing to see here',
];
const REPORT = (name) => `# Sync conflicts ${name}\n\n- Generated at (UTC): 2026-01-01T00:00:00Z\n- Conflicts: 1\n`;

// buildSource(dir, opts): the fixture source repository at dir. opts.head is the checked-out branch ('main' or 'dev'),
// opts.omit names a sync stub left out ('sh' or 'ps1'), opts.helperReal is the text of the real doctor helper.
export function buildSource(dir, { head = 'main', omit = '', helperReal, env }) {
  const put = (rel, body, mode) => {
    const p = path.join(dir, rel);
    mkdirSync(path.dirname(p), { recursive: true });
    writeFileSync(p, body);
    if (mode) chmodSync(p, mode);
  };
  if (omit !== 'sh') put('.aai/scripts/aai-sync.sh', SYNC_SH, 0o755);
  if (omit !== 'ps1') put('.aai/scripts/aai-sync.ps1', SYNC_PS1, 0o644);
  put('fx-data/aai-doctor.mjs', DOCTOR_STUB);
  put('fx-data/helper-real.mjs', helperReal);
  put('fx-data/helper-broken.mjs', 'throw new Error("broken fixture helper");\n');
  put('fx-data/pin-plain.md', `${PIN_LINES.join('\n')}\n`);
  put('fx-data/pin-bom-crlf.md', `﻿${PIN_LINES.join('\r\n')}\r\n`);
  put('fx-data/report-a.md', REPORT('a'));
  put('fx-data/report-b.md', REPORT('b'));
  put('README.md', 'fixture source\n');
  git(dir, ['init', '-q', '-b', 'main'], env);
  git(dir, ['add', '-A'], env);
  git(dir, ['-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'fixture source'], env);
  git(dir, ['checkout', '-q', '-b', 'dev'], env);
  put('dev.txt', 'dev branch\n');
  git(dir, ['add', '-A'], env);
  git(dir, ['-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'dev commit'], env);
  git(dir, ['checkout', '-q', head], env);
}

// buildTarget(dir, opts): the fixture target; a git repository with origin and one commit unless opts.repo is false.
export function buildTarget(dir, { origin = TARGET_ORIGIN, repo = true, env }) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(path.join(dir, 'README.md'), 'fixture target\n');
  if (!repo) return;
  git(dir, ['init', '-q', '-b', 'main'], env);
  git(dir, ['add', '-A'], env);
  git(dir, ['-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'target baseline'], env);
  if (origin) git(dir, ['remote', 'add', 'origin', origin], env);
}

const CANON = 'https://github.com/goodwind-cz/aai.git';
const E = '—';

// The corpus cases. sides: which reference runs it. args(c): the arguments, c = { src, target, root }. rw: the
// registered DR rewrites per side (each must change at least one byte). diverge: per side, the asserted divergence
// (checked in the test file by name). tmp: 'empty' or 'one-kept' expects the TMPDIR listing; gh: 'none' expects no
// gh log line. omit: per side, the sync stub the source lacks.
const ALL = ['sh', 'ps1'];
const PS_REAL = ['DR-13', 'DR-14', 'DR-15'];
export const U_CASES = [
  { id: 'U01', sides: ALL, args: () => ['--repo', '../src'], rw: { sh: [], ps1: PS_REAL } },
  { id: 'U02', sides: ALL, args: (c) => ['--repo', `file://${c.src}`], tmp: 'empty', rw: { sh: [], ps1: PS_REAL } },
  { id: 'U03', sides: ALL, args: (c) => ['--repo', `file://${c.root}/fx/missing`], tmp: 'empty', rw: { sh: [], ps1: [] } },
  { id: 'U03k', sides: ALL, args: (c) => ['--repo', `file://${c.root}/fx/missing`, '--keep-temp'], tmp: 'one-kept', rw: { sh: [], ps1: [] } },
  { id: 'U04', sides: ALL, srcHead: 'dev', args: () => ['--repo', '../src', '--ref', 'main', '--dry-run'], diverge: { sh: 'branch', ps1: 'branch' }, rw: { sh: [], ps1: ['DR-13', 'DR-16'] } },
  { id: 'U05', sides: ALL, args: () => ['--repo', 'acme/foo', '--ref', 'dev', '--dry-run'], tmp: 'empty', gh: 'none', rw: { sh: [], ps1: ['DR-13', 'DR-16'] } },
  { id: 'U06', sides: ALL, origin: CANON, args: () => [], tmp: 'empty', rw: { sh: ['DR-6'], ps1: ['DR-6'] } },
  { id: 'U07', sides: ALL, origin: CANON, args: () => ['--force', '--dry-run'], rw: { sh: [], ps1: ['DR-13', 'DR-16'] } },
  { id: 'U08', sides: ALL, origin: `https://GITHUB.COM/Goodwind-CZ/AAI.GIT`, args: () => ['--dry-run'], diverge: { sh: 'not-refused' }, rw: { sh: [], ps1: ['DR-6'] } },
  { id: 'U09', sides: ['sh'], args: () => ['-h'], rw: { sh: ['DR-1'] } },
  { id: 'U10', sides: ALL, args: () => ['--bogus', '--dry-run', '--force'], diverge: { ps1: 'warn' }, rw: { sh: ['DR-1'], ps1: [] } },
  { id: 'U11', sides: ALL, args: () => ['--dry-run', '--repo'], diverge: { sh: 'needs-value', ps1: 'needs-value' }, rw: { sh: [], ps1: [] } },
  { id: 'U12', sides: ALL, args: () => ['--repo', '../src'], omit: { sh: 'sh', ps1: 'ps1' }, rw: { sh: [], ps1: [] } },
  { id: 'U13', sides: ALL, args: () => ['--repo', '../src'], env: { FX_SYNC_EXIT: '5' }, diverge: { ps1: 'evidence-after-failure' }, rw: { sh: [], ps1: ['DR-13'] } },
  { id: 'U13t', sides: ['ps1'], args: () => ['--repo', '../src'], env: { FX_SYNC_THROW: '1' }, rw: { ps1: ['DR-13'] } },
  { id: 'U14', sides: ALL, targetRepo: false, args: () => ['--repo', '../src'], rw: { sh: [], ps1: PS_REAL } },
  { id: 'U15', sides: ALL, args: () => ['--repo', '../src'], env: { FX_HELPER: 'none' }, rw: { sh: [], ps1: PS_REAL } },
  { id: 'U16', sides: ALL, args: () => ['--repo', '../src'], env: { FX_HELPER: 'broken' }, rw: { sh: [], ps1: PS_REAL } },
  { id: 'U17', sides: ALL, args: () => ['--repo', '../src'], env: { FX_PIN: 'none', FX_REPORTS: 'none' }, rw: { sh: [], ps1: ['DR-13', 'DR-15'] } },
  { id: 'U18', sides: ALL, args: () => ['--repo', '../src'], env: { FX_PIN: 'bom' }, rw: { sh: ['DR-17'], ps1: PS_REAL } },
  { id: 'U19', sides: ALL, args: () => ['--repo', '../src'], env: { FX_REPORTS: 'tie' }, rw: { sh: [], ps1: PS_REAL } },
  { id: 'U20', sides: ALL, args: (c) => [`--repo=${c.src}`, '--ref=main', '--dry-run', '--force'], diverge: { sh: 'long-equals-form' }, rw: { sh: [], ps1: ['DR-13', 'DR-16'] } },
  { id: 'U21', sides: ALL, args: (c) => ['-Repo', c.src, '-Ref', 'main', '-DryRun', '-Force'], diverge: { sh: 'powershell-names' }, rw: { sh: [], ps1: ['DR-13', 'DR-16'] } },
  { id: 'U22', sides: ALL, targetName: 'target dir', args: () => ['--repo', '../src'], rw: { sh: [], ps1: PS_REAL } },
  { id: 'U23', sides: ALL, gitWrapper: true, args: (c) => ['--repo', `file://${c.src}`], tmp: 'empty', diverge: { ps1: 'prompt-setting' }, rw: { sh: [], ps1: PS_REAL } },
];
export const EM_DASH = E;
