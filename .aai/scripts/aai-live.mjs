#!/usr/bin/env node
// aai-live.mjs - generate the live-status dashboard, then open it in the platform browser
// (SPEC-0114; RFC-0017 small-pairs slice). aai-live.sh and aai-live.ps1 are thin launchers.
// Every argument goes to generate-live-status.mjs. AAI_LIVE_OPENER (one executable path)
// overrides the opener. Exit: the generator's code, 1 when a part is missing. Reads no stdin.
import { realpathSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn, spawnSync } from 'node:child_process';

const DEFAULT_OUTPUT = 'docs/ai/live-status.html';
const CANDIDATES = ['open', 'xdg-open'];
const WIN_OPENER = 'explorer.exe';
const OPENER_TIMEOUT_MS = 10000;
const isFile = (p) => { try { return statSync(p).isFile(); } catch { return false; } };
const real = (p) => { try { return realpathSync(p); } catch { return path.resolve(p); } };
const refuse = (msg) => { process.stderr.write('aai-live: refused - ' + msg + '\n'); return 1; };

export function resolveOutputPath(args, root) {
  let out = DEFAULT_OUTPUT;
  args.forEach((a, i) => { if (args[i - 1] === '--output') out = a; });
  return path.isAbsolute(out) ? out : path.join(root, out);
}

export function warmupArgs(args) {
  const warm = args.filter((a) => a !== '--watch');
  return warm;
}

export function resolveOpener({ env, platform, pathEnv }) {
  const override = env.AAI_LIVE_OPENER;
  if (override) return platform === 'win32' && /\.(cmd|bat)$/i.test(override) ? { cmd: '"' + override + '"', shell: true } : { cmd: override, shell: false };
  if (platform === 'win32') return { cmd: WIN_OPENER, shell: false };
  const dirs = (pathEnv || '').split(path.delimiter).filter(Boolean);
  const cmd = CANDIDATES.find((c) => dirs.some((d) => isFile(path.join(d, c))));
  return cmd ? { cmd, shell: false } : null;
}

function openTarget(opener, target) {
  const io = { stdio: 'ignore', timeout: OPENER_TIMEOUT_MS };
  if (opener.shell) spawnSync(opener.cmd + ' "' + target + '"', [], { ...io, shell: true });
  else spawnSync(opener.cmd, [target], io);
}

export async function main(argv) {
  const args = argv;
  const here = path.dirname(real(fileURLToPath(import.meta.url)));
  const root = path.resolve(here, '..', '..');
  const gen = path.join(here, 'generate-live-status.mjs');
  if (!isFile(gen)) return refuse('generator not found: ' + gen);
  const opener = resolveOpener({ env: process.env, platform: process.platform, pathEnv: process.env.PATH });
  if (!opener) return refuse("no browser opener found on PATH (expected 'open' on macOS or 'xdg-open' on Linux; set AAI_LIVE_OPENER to override)");
  const dataOnly = args.includes('--data-only');
  const run = (a, stdio) => spawnSync(process.execPath, [gen, ...a], { cwd: root, stdio });
  if (!args.includes('--watch')) {
    const code = run(args, 'inherit').status ?? 1;
    if (code === 0 && !dataOnly) openTarget(opener, resolveOutputPath(args, root));
    return code;
  }
  run(warmupArgs(args), 'ignore');
  if (!dataOnly) openTarget(opener, resolveOutputPath(args, root));
  const child = spawn(process.execPath, [gen, ...args], { cwd: root, stdio: 'inherit' });
  for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => child.kill(sig));
  return new Promise((resolve) => child.on('exit', (code) => resolve(code ?? 1)));
}

if (process.argv[1] && real(process.argv[1]) === real(fileURLToPath(import.meta.url))) process.exitCode = await main(process.argv.slice(2));
