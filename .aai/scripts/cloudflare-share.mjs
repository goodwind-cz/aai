#!/usr/bin/env node
// cloudflare-share.mjs - convert one Markdown document and publish it to Cloudflare Pages.
// The .sh and .ps1 files next to this module are thin launchers (RFC-0017 phase 5).
// Usage: node cloudflare-share.mjs <document.md>
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const PUBLISH_DIR = '.cloudflare-publish';
const PROJECT_NAME = 'aai-reports';
const HISTORY_FILE = 'docs/ai/published/history.jsonl';
const URL_RE = /https:\/\/[^\s]+\.pages\.dev/;
const USAGE = 'Usage: cloudflare-share <document.md>';
const SECRET_VARS = ['CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_API_KEY'];

const ANSI_RE = /\u001b(?:\[[0-?]*[ -\/]*[@-~]|\][^\u0007\u001b]*(?:\u0007|\u001b\\)|[@-Z\\-_])/g;

export function parseArgs(argv) {
  if (argv.length === 1 && (argv[0] === '-h' || argv[0] === '--help')) return { help: true };
  if (argv.length !== 1 || argv[0] === '') return { error: USAGE };
  return { doc: argv[0] };
}

export function branchName(name) {
  return [...name.toLowerCase()].map((c) => (/[a-z0-9-]/.test(c) ? c : '-')).join('');
}

export function extractUrl(text) {
  const m = URL_RE.exec(text);
  return m ? m[0] : null;
}

export function redact(text, env) {
  const values = SECRET_VARS.map((k) => env[k]).filter((v) => typeof v === 'string' && v.length >= 8);
  values.sort((a, b) => b.length - a.length);
  return values.reduce((t, v) => t.split(v).join('[REDACTED]'), text);
}

export function historyLine({ timestamp, document, url, sizeKb }) {
  return JSON.stringify({ timestamp, document, url, size_kb: sizeKb });
}

export function findWrangler(env, platform, fsApi) {
  const win = platform === 'win32';
  const p = win ? path.win32 : path.posix;
  const pathVar = win ? (env.Path ?? env.PATH ?? env.path) : env.PATH;
  const exts = win ? (env.PATHEXT ?? '.COM;.EXE;.BAT;.CMD').split(';').filter(Boolean).map((e) => e.toLowerCase()) : [''];
  for (const raw of (pathVar ?? '').split(win ? ';' : ':')) {
    const dir = raw.replace(/^"(.*)"$/, '$1');
    if (!dir) continue;
    for (const ext of exts) {
      const candidate = p.join(dir, `wrangler${ext}`);
      try {
        const st = fsApi.statSync(candidate);
        if (st.isFile() && (win || (st.mode & 0o111) !== 0)) return candidate;
      } catch { /* not here */ }
    }
  }
  return null;
}

export function deployCommand(wranglerPath, branch, platform) {
  const args = ['pages', 'deploy', PUBLISH_DIR, `--project-name=${PROJECT_NAME}`, `--branch=${branch}`];
  if (platform === 'win32' && /\.(cmd|bat)$/i.test(wranglerPath)) {
    if (/["%!]/.test(wranglerPath)) return null;
    return { command: [`"${wranglerPath}"`, ...args].join(' '), args: [], shell: true };
  }
  return { command: wranglerPath, args, shell: false };
}

function sizeOf(fsApi, dir) {
  let bytes = 0;
  for (const e of fsApi.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    bytes += e.isDirectory() ? sizeOf(fsApi, p) : fsApi.statSync(p).size;
  }
  return bytes;
}

const lines = (text) => text.replace(/\n$/, '').split('\n');

export function run(opts, deps) {
  const { cwd, env, platform, fs: fsApi, out, err } = deps;
  const at = (rel) => path.resolve(cwd, rel);
  const doc = opts.doc;
  const isFile = (p) => { try { return fsApi.statSync(p).isFile(); } catch { return false; } };
  if (!isFile(at(doc))) { err(`ERROR: Document not found: ${doc}`); return 1; }
  const wrangler = findWrangler(env, platform, fsApi);
  if (!wrangler) {
    for (const l of ['ERROR: wrangler not found', 'Install: npm install -g wrangler', 'Then run: wrangler login']) err(l);
    return 1;
  }
  let top = { status: 1, stdout: '' };
  try { top = deps.gitToplevel(cwd); } catch { /* not a git repository */ }
  const branch = branchName(path.basename(top.status === 0 && top.stdout.trim() ? top.stdout.trim() : cwd));
  if (!branch) { err('ERROR: cannot derive a branch name from the current directory'); return 1; }
  const cmd = deployCommand(wrangler, branch, platform);
  if (!cmd) { err(`ERROR: wrangler path cannot be run safely: ${wrangler}`); return 1; }
  const publish = at(PUBLISH_DIR);
  try {
    fsApi.rmSync(publish, { recursive: true, force: true });
    fsApi.mkdirSync(publish, { recursive: true });
    out('Converting Markdown to HTML...');
    const conv = deps.convert(doc, PUBLISH_DIR);
    for (const l of lines(conv.stdout ?? '')) if (l) out(l);
    if (conv.status !== 0) {
      for (const l of lines(conv.stderr ?? '')) if (l) err(l);
      err(`ERROR: conversion failed (share-convert.mjs exited ${conv.status})`);
      return 1;
    }
    out(`Deploying to Cloudflare Pages (branch: ${branch})...`);
    let dep;
    try { dep = deps.deploy(cmd, env); } catch (e) { err(`ERROR: wrangler could not be run: ${e.message}`); return 1; }
    const stdout = dep.stdout ?? '';
    const stderr = dep.stderr ?? '';
    const url = dep.status === 0 ? (extractUrl(stdout) ?? extractUrl(stderr)) : null;
    if (!url) {
      err('ERROR: Deployment failed or URL not found');
      err(redact(redact(`${stdout}${stderr}`, env).replace(ANSI_RE, '').replace(/\n+$/, ''), env));
      return 1;
    }
    const sizeKb = Math.round((sizeOf(fsApi, publish) / 1024) * 100) / 100;
    fsApi.rmSync(publish, { recursive: true, force: true });
    const timestamp = deps.now().toISOString().replace(/\.\d{3}Z$/, 'Z');
    fsApi.mkdirSync(path.dirname(at(HISTORY_FILE)), { recursive: true });
    fsApi.appendFileSync(at(HISTORY_FILE), `${historyLine({ timestamp, document: doc, url, sizeKb })}\n`, 'utf8');
    for (const l of ['', 'Document published successfully!', '', `Document: ${path.parse(doc).name}`, `URL: ${url}`, '', `Click to open: ${url}`, '']) out(l);
    return 0;
  } catch (e) {
    err(`ERROR: ${e.message}`);
    return 1;
  } finally {
    fsApi.rmSync(publish, { recursive: true, force: true });
  }
}

const HERE = path.dirname(fileURLToPath(import.meta.url));
const capture = (r) => {
  if (r.error) throw r.error;
  return { status: r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
};

export function main(argv = process.argv.slice(2)) {
  const opts = parseArgs(argv);
  if (opts.error) { process.stderr.write(`${opts.error}\n`); return 1; }
  if (opts.help) { process.stdout.write(`${USAGE}\n`); return 0; }
  const spawn = (cmd, args, extra) => capture(spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: 64 << 20, ...extra }));
  return run(opts, {
    cwd: process.cwd(),
    env: process.env,
    platform: process.platform,
    fs,
    convert: (doc, dir) => spawn(process.execPath, [path.join(HERE, 'share-convert.mjs'), doc, dir]),
    deploy: (cmd, env) => spawn(cmd.command, cmd.args, { env, shell: cmd.shell }),
    gitToplevel: (cwd) => { try { return spawn('git', ['rev-parse', '--show-toplevel'], { cwd }); } catch { return { status: 1, stdout: '', stderr: '' }; } },
    now: () => new Date(),
    out: (l) => process.stdout.write(`${l}\n`),
    err: (l) => process.stderr.write(`${l}\n`),
  });
}

const realOrResolve = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) process.exitCode = main();
