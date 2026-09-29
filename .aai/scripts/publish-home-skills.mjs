#!/usr/bin/env node
//
// publish-home-skills.mjs — copy .claude/skills/*/SKILL.md into the two
// Antigravity CLI home trees. The project mirror stays with
// sync-harness-skills.mjs. Home trees are install targets, never committed.
//
// USAGE
//   node .aai/scripts/publish-home-skills.mjs --home <dir> (--check | --write)
//        [--root <repo>]
//
// EXIT
//   0  --check found no divergence, or --write finished
//   1  --check found a divergence
//   2  usage error
//
// --home is required. HOME, GEMINI_HOME, CLAUDE_CONFIG_DIR and CODEX_HOME
// are never read.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const SELF_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = path.resolve(SELF_DIR, '..', '..');

const DEST_GLOBAL = '.gemini/antigravity-cli/skills';
const DEST_SHARED = '.gemini/skills';
const TREES = [DEST_GLOBAL, DEST_SHARED];
const SOURCE = '.claude/skills';

function fail(code, message) {
  process.stderr.write(`publish-home-skills: ${message}\n`);
  exit(code);
}

function parseArgs(argv) {
  const out = { root: DEFAULT_ROOT, home: null, check: false, write: false };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--check') out.check = true;
    else if (tok === '--write') out.write = true;
    else if (tok === '--root') {
      const v = argv[++i];
      if (!v || v.startsWith('--')) fail(2, '--root requires a path');
      out.root = path.resolve(v);
    } else if (tok === '--home') {
      const v = argv[++i];
      if (!v || v.startsWith('--')) fail(2, '--home requires a path');
      out.home = path.resolve(v);
    } else fail(2, `unknown argument ${tok}`);
  }
  if (!out.home) fail(2, '--home is required');
  if (out.check === out.write) fail(2, 'pass exactly one of --check or --write');
  return out;
}

function listSourceSkills(root) {
  const dir = path.join(root, SOURCE);
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (err) {
    fail(2, `source tree missing: ${SOURCE} (${err.code || err.message})`);
  }
  const skills = [];
  for (const ent of entries) {
    if (!ent.isDirectory()) continue;
    const skillMd = path.join(dir, ent.name, 'SKILL.md');
    if (!fs.existsSync(skillMd) || !fs.statSync(skillMd).isFile()) continue;
    skills.push(ent.name);
  }
  skills.sort();
  return skills;
}

function skillTarget(home, treeRel, skill) {
  return path.join(home, treeRel, skill, 'SKILL.md');
}

function keepExisting(dest) {
  return dest;
}

function writeSkill(src, dest) {
  const raw = fs.readFileSync(src);
  if (fs.existsSync(dest) && fs.statSync(dest).isFile()) {
    const cur = fs.readFileSync(dest);
    if (cur.equals(raw)) {
      keepExisting(dest);
      return;
    }
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
}

function listSkillDirs(treeDir) {
  if (!fs.existsSync(treeDir)) return [];
  const st = fs.lstatSync(treeDir);
  if (!st.isDirectory()) return null;
  return fs.readdirSync(treeDir, { withFileTypes: true })
    .filter((ent) => ent.isDirectory() || ent.isSymbolicLink())
    .map((ent) => ent.name)
    .sort();
}

function main(argv) {
  const args = parseArgs(argv);
  const skills = listSourceSkills(args.root);
  const expected = new Set(skills);
  const divergences = [];

  for (const treeRel of TREES) {
    const treeDir = path.join(args.home, treeRel);
    const actual = listSkillDirs(treeDir);
    if (actual === null) divergences.push(`non-directory ${treeRel}`);
    if (!fs.existsSync(treeDir)) divergences.push(`missing ${treeRel}`);
    const names = actual || [];
    for (const skill of skills) {
      if (!names.includes(skill)) divergences.push(`missing ${treeRel}/${skill}`);
      const src = path.join(args.root, SOURCE, skill, 'SKILL.md');
      const dest = skillTarget(args.home, treeRel, skill);
      let same = false;
      try {
        same = fs.existsSync(dest) && fs.readFileSync(dest).equals(fs.readFileSync(src));
      } catch {
        same = false;
      }
      if (!same) divergences.push(`content ${treeRel}/${skill}/SKILL.md`);
      if (args.write) writeSkill(src, dest);
    }
    for (const name of names) {
      if (!expected.has(name)) {
        divergences.push(`extra ${treeRel}/${name}`);
        if (args.write) fs.rmSync(path.join(treeDir, name), { recursive: true, force: true });
      }
    }
  }

  if (args.check) {
    if (divergences.length > 0) {
      for (const d of divergences) process.stdout.write(`DIVERGE ${d}\n`);
      exit(1);
    }
    process.stdout.write(`OK: ${TREES.join(', ')} match\n`);
    exit(0);
  }

  process.stdout.write(
    divergences.length > 0
      ? `WROTE: ${divergences.length} divergence(s) resolved\n`
      : `WROTE: no divergence found\n`
  );
  exit(0);
}

runMain(() => main(process.argv.slice(2)), {
  onError(err) {
    process.stderr.write(`publish-home-skills: unexpected error: ${err && err.stack ? err.stack : err}\n`);
    process.exitCode = 2;
  },
});
