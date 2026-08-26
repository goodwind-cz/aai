#!/usr/bin/env node
//
// sync-harness-skills.mjs — project .claude/skills/*/SKILL.md into the three
// declared mirror trees under ONE transform table
// (CHANGE harness-surfaces-drift-unguarded / SPEC-0154-spec-harness-surfaces-drift-unguarded D1).
//
// PURPOSE
//   .claude/skills is the only hand-authored skill tree. .agents/skills,
//   .codex/skills and .gemini/skills used to be hand-authored copies that
//   drifted (stale descriptions, missing <SUBAGENT-STOP> blocks, a
//   capitalized `.Codex/` path substituted into a wrapper's runtime-file
//   reference where the real path is lowercase `.claude/`, two README
//   indexes stuck at 22 of 39 skills). This script makes them GENERATED:
//   body, `name` and `description` are carried verbatim into every tree; the
//   frontmatter `model:` key is carried only where the manifest says `carry` (dropped
//   elsewhere, matching what those trees already did before this script
//   existed — neither Codex nor Gemini documents the key). The manifest
//   (.aai/system/HARNESS_SKILLS.yaml) is the single declared source of that
//   transform; an undeclared or malformed tree row is refused, never
//   defaulted (Article 4: degrade and report, never guess).
//
// USAGE
//   node .aai/scripts/sync-harness-skills.mjs --check [--manifest <path>] [--root <dir>]
//   node .aai/scripts/sync-harness-skills.mjs --write [--manifest <path>] [--root <dir>]
//
//   --root overrides the project root (default: this script's own repo,
//   i.e. two directories up). Tests use it to point the generator at a
//   throwaway fixture tree instead of the live checkout.
//   --manifest overrides the manifest path (default: <root>/.aai/system/HARNESS_SKILLS.yaml).
//
// EXIT CONTRACT
//   0  --check found no divergence, or --write completed
//   1  --check found at least one divergence (one `DIVERGE ...` line each,
//      printed to stdout before exit)
//   2  manifest/tree structural error: an undeclared required tree, an
//      invalid model/readme value, a stale or reason-less exclusion, or a
//      usage error — always with a message on stderr naming the offender
//
// Node stdlib only, zero network, no LLM (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SELF_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_REPO_ROOT = path.resolve(SELF_DIR, '..', '..');

const SOURCE_TREE = '.claude/skills';
const REQUIRED_MIRROR_TREES = ['.agents/skills', '.codex/skills', '.gemini/skills'];

// --- exit discipline (cli-output-survives-a-pipe: throw, never process.exit
// directly, so queued stdout drains before the process ends) -----------------

class ExitSignal extends Error {
  constructor(code) {
    super(`exit ${code}`);
    this.name = 'ExitSignal';
    this.code = code;
  }
}

function exit(code) {
  throw new ExitSignal(code);
}

function installPipeGuard(stream) {
  stream.on('error', (err) => {
    const code = err && err.code;
    if (code === 'EPIPE' || code === 'ERR_STREAM_DESTROYED') {
      process.exit(typeof process.exitCode === 'number' ? process.exitCode : 0);
    }
    throw err;
  });
}

class ManifestError extends Error {}

function fail(code, message) {
  process.stderr.write(`sync-harness-skills: ${message}\n`);
  exit(code);
}

// --- manifest parsing (line-based, PROFILES.yaml discipline) ----------------

function parseManifest(raw) {
  // Fail closed: every non-comment line must match the declared grammar;
  // silently skipped content can erase an exclusion or transform.
  const lines = raw.split(/\r?\n/);
  const trees = [];
  const exclusions = [];
  let section = null;
  for (const line of lines) {
    if (/^\s*$/.test(line) || /^\s*#/.test(line)) continue;
    if (/^trees:\s*$/.test(line)) { section = 'trees'; continue; }
    if (/^exclusions:\s*$/.test(line)) { section = 'exclusions'; continue; }
    const m = line.match(/^ {2}- (.*)$/);
    if (!m || section === null) {
      throw new ManifestError(`unparsed manifest content: ${line}`);
    }
    const rest = m[1];
    if (section === 'trees') {
      const parts = rest.split('|');
      if (parts.length !== 3) {
        throw new ManifestError(`malformed trees row (want tree|model|readme): ${line}`);
      }
      trees.push({ tree: parts[0].trim(), model: parts[1].trim(), readme: parts[2].trim() });
    } else if (section === 'exclusions') {
      const first = rest.indexOf('|');
      const second = first === -1 ? -1 : rest.indexOf('|', first + 1);
      if (first === -1 || second === -1) {
        throw new ManifestError(`malformed exclusions row (want tree|skill|reason): ${line}`);
      }
      exclusions.push({
        tree: rest.slice(0, first).trim(),
        skill: rest.slice(first + 1, second).trim(),
        reason: rest.slice(second + 1).trim(),
      });
    }
  }
  return { trees, exclusions };
}

function validateManifest(manifest, sourceSkills) {
  const seenTrees = new Set();
  for (const row of manifest.trees) {
    if (seenTrees.has(row.tree)) fail(2, `duplicate tree row in manifest: ${row.tree}`);
    seenTrees.add(row.tree);
  }
  const byTree = new Map(manifest.trees.map((t) => [t.tree, t]));
  for (const required of REQUIRED_MIRROR_TREES) {
    const row = byTree.get(required);
    if (!row) fail(2, `tree not declared in manifest: ${required}`);
    if (row.model !== 'carry' && row.model !== 'drop') {
      fail(2, `tree ${required} has an invalid model value (want carry|drop): ${row.model}`);
    }
    if (row.readme !== 'yes' && row.readme !== 'no') {
      fail(2, `tree ${required} has an invalid readme value (want yes|no): ${row.readme}`);
    }
  }
  for (const row of manifest.trees) {
    if (!REQUIRED_MIRROR_TREES.includes(row.tree)) {
      fail(2, `manifest declares a tree this generator does not mirror: ${row.tree} `
            + `(the mirror tree list is fixed in sync-harness-skills.mjs REQUIRED_MIRROR_TREES)`);
    }
  }
  const sourceSet = new Set(sourceSkills);
  for (const ex of manifest.exclusions) {
    if (!byTree.has(ex.tree)) fail(2, `exclusion names an undeclared tree: ${ex.tree}`);
    if (!ex.skill) fail(2, 'exclusion has an empty skill name');
    if (!ex.reason) fail(2, `exclusion ${ex.tree}|${ex.skill} has an empty reason`);
    if (!sourceSet.has(ex.skill)) {
      fail(2, `stale exclusion: ${ex.tree}|${ex.skill} names a skill absent from ${SOURCE_TREE}`);
    }
  }
  return byTree;
}

// --- skill tree reading -------------------------------------------------------

function listSkills(skillsDir) {
  let entries;
  try {
    entries = fs.readdirSync(skillsDir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((e) => e.isDirectory() && fs.existsSync(path.join(skillsDir, e.name, 'SKILL.md')))
    .map((e) => e.name)
    .sort();
}

// parseSkillFile: split a SKILL.md into its frontmatter lines and its exact
// verbatim body (everything after the closing `---` line, byte-for-byte,
// including leading blank lines). Reconstructing with buildTargetContent and
// the SAME frontLines reproduces the original file byte-for-byte — this is
// what makes an .agents (model: carry) copy of an already-modelless source a
// pure verbatim clone, not an approximation.
function parseSkillFile(raw, label) {
  if (!raw.startsWith('---\n')) {
    throw new ManifestError(`source skill file missing opening frontmatter fence: ${label}`);
  }
  const closeMatch = /\n---(?:\n|$)/.exec(raw.slice(4));
  if (!closeMatch) {
    throw new ManifestError(`source skill file missing closing frontmatter fence: ${label}`);
  }
  const closeIdx = 4 + closeMatch.index;
  const frontBlock = raw.slice(4, closeIdx);
  const body = raw.slice(closeIdx + closeMatch[0].length);
  const frontLines = frontBlock.length ? frontBlock.split('\n') : [''];
  return { frontLines, body };
}

function buildTargetContent(frontLines, body, { dropModel }) {
  const filtered = dropModel ? frontLines.filter((l) => !/^model:\s*/.test(l)) : frontLines;
  return `---\n${filtered.join('\n')}\n---\n${body}`;
}

function extractDescription(frontLines) {
  const line = frontLines.find((l) => /^description:\s*/.test(l));
  if (!line) return '';
  let val = line.replace(/^description:\s*/, '');
  if (val.length >= 2) {
    const first = val[0];
    const last = val[val.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      val = val.slice(1, -1);
    }
  }
  return val;
}

function treeTitle(tree) {
  const seg = tree.split('/')[0].replace(/^\./, '');
  return seg.charAt(0).toUpperCase() + seg.slice(1);
}

function buildReadme(tree, skillDescriptions) {
  const title = treeTitle(tree);
  const lines = [
    `# ${title} Skill Index`,
    '',
    'These are the canonical AAI-prefixed skills available after AAI sync.',
    'Generated from `.claude/skills/` by `.aai/scripts/sync-harness-skills.mjs` — do not hand-edit.',
    '',
    '## Universal skills',
  ];
  for (const [name, desc] of skillDescriptions) {
    lines.push(`- \`/${name}\` — ${desc}`);
  }
  lines.push('');
  lines.push('## Project-specific skills');
  lines.push('- Generated by `/aai-bootstrap` into `.claude/skills/`');
  lines.push(
    '- Must use `aai-` prefix (for example `/aai-test-e2e`, `/aai-test-unit`, `/aai-build`, `/aai-lint`, `/aai-deploy`)'
  );
  return `${lines.join('\n')}\n`;
}

function firstDiffHint(actual, expected) {
  const a = actual.split('\n');
  const e = expected.split('\n');
  const n = Math.max(a.length, e.length);
  const clip = (s) => {
    if (s === undefined) return '<absent>';
    return s.length > 140 ? `${s.slice(0, 140)}…` : s;
  };
  for (let i = 0; i < n; i++) {
    if (a[i] !== e[i]) {
      return `line ${i + 1}: actual=${JSON.stringify(clip(a[i]))} expected=${JSON.stringify(clip(e[i]))}`;
    }
  }
  return '(content differs, no line-level difference found)';
}

// --- CLI ----------------------------------------------------------------------

function parseArgs(argv) {
  const opts = { check: false, write: false, manifest: null, root: null };
  const valueAfter = (index, flag) => {
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) fail(2, `${flag} requires a value`);
    return value;
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') opts.check = true;
    else if (a === '--write') opts.write = true;
    else if (a === '--manifest') opts.manifest = valueAfter(i++, a);
    else if (a === '--root') opts.root = valueAfter(i++, a);
    else fail(2, `unrecognized argument: ${a}`);
  }
  if (opts.check === opts.write) {
    fail(2, 'exactly one of --check or --write is required');
  }
  return opts;
}

function main(argv) {
  const opts = parseArgs(argv);
  const root = opts.root ? path.resolve(opts.root) : DEFAULT_REPO_ROOT;
  const manifestPath = opts.manifest
    ? path.resolve(opts.manifest)
    : path.join(root, '.aai/system/HARNESS_SKILLS.yaml');

  let manifestRaw;
  try {
    manifestRaw = fs.readFileSync(manifestPath, 'utf8');
  } catch (err) {
    fail(2, `cannot read manifest ${manifestPath}: ${err && err.message}`);
  }

  let manifest;
  try {
    manifest = parseManifest(manifestRaw);
  } catch (err) {
    if (err instanceof ManifestError) fail(2, err.message);
    throw err;
  }

  const sourceDir = path.join(root, SOURCE_TREE);
  const sourceSkills = listSkills(sourceDir);
  if (sourceSkills.length === 0) {
    fail(2, `no skills found under source tree ${SOURCE_TREE} (root=${root})`);
  }

  let byTree;
  try {
    byTree = validateManifest(manifest, sourceSkills);
  } catch (err) {
    if (err instanceof ManifestError) fail(2, err.message);
    throw err;
  }

  const divergences = [];

  for (const required of REQUIRED_MIRROR_TREES) {
    const row = byTree.get(required);
    const treeSkillsDir = path.join(root, required);
    const excludedForTree = new Set(
      manifest.exclusions.filter((e) => e.tree === required).map((e) => e.skill)
    );
    const expected = sourceSkills.filter((s) => !excludedForTree.has(s));
    const expectedSet = new Set(expected);
    const actualSkills = listSkills(treeSkillsDir);
    const actualSet = new Set(actualSkills);

    for (const s of expected) {
      if (!actualSet.has(s)) divergences.push(`missing ${required}/${s}`);
    }
    for (const s of actualSkills) {
      if (!expectedSet.has(s)) divergences.push(`extra ${required}/${s}`);
    }

    const skillDescriptions = [];
    for (const s of expected) {
      const srcPath = path.join(sourceDir, s, 'SKILL.md');
      const srcRaw = fs.readFileSync(srcPath, 'utf8');
      const { frontLines, body } = parseSkillFile(srcRaw, srcPath);
      skillDescriptions.push([s, extractDescription(frontLines)]);

      const expectedContent = buildTargetContent(frontLines, body, { dropModel: row.model === 'drop' });
      const targetPath = path.join(treeSkillsDir, s, 'SKILL.md');
      let actualContent = null;
      let readError = null;
      try {
        actualContent = fs.readFileSync(targetPath, 'utf8');
      } catch (err) {
        readError = err;
      }
      if (readError && actualSet.has(s)) {
        // The skill directory exists (so this is NOT the "missing" case
        // already reported above) but its SKILL.md could not be read —
        // e.g. a directory sits where the file should be. Fail-open guard
        // hole: report it by name rather than silently treating it as OK.
        divergences.push(`unreadable ${required}/${s}/SKILL.md: ${readError.code || readError.message}`);
      }
      if (actualContent !== expectedContent) {
        if (actualContent !== null) {
          divergences.push(`content ${required}/${s}/SKILL.md ${firstDiffHint(actualContent, expectedContent)}`);
        }
        if (opts.write) {
          fs.mkdirSync(path.dirname(targetPath), { recursive: true });
          fs.writeFileSync(targetPath, expectedContent);
        }
      }
    }

    if (opts.write) {
      for (const s of actualSkills) {
        if (!expectedSet.has(s)) {
          fs.rmSync(path.join(treeSkillsDir, s), { recursive: true, force: true });
        }
      }
    }

    if (row.readme === 'yes') {
      const expectedReadme = buildReadme(required, skillDescriptions);
      const readmePath = path.join(treeSkillsDir, 'README.md');
      let actualReadme = null;
      try {
        actualReadme = fs.readFileSync(readmePath, 'utf8');
      } catch {
        actualReadme = null;
      }
      if (actualReadme !== expectedReadme) {
        divergences.push(`readme ${required}/README.md differs`);
        if (opts.write) {
          fs.mkdirSync(treeSkillsDir, { recursive: true });
          fs.writeFileSync(readmePath, expectedReadme);
        }
      }
    }
  }

  if (opts.check) {
    if (divergences.length > 0) {
      for (const d of divergences) process.stdout.write(`DIVERGE ${d}\n`);
      exit(1);
    }
    process.stdout.write(`OK: ${REQUIRED_MIRROR_TREES.join(', ')} match the declared transform\n`);
    exit(0);
  }

  // --write
  process.stdout.write(
    divergences.length > 0
      ? `WROTE: ${divergences.length} divergence(s) resolved across ${REQUIRED_MIRROR_TREES.join(', ')}\n`
      : `WROTE: no divergence found, ${REQUIRED_MIRROR_TREES.join(', ')} already match\n`
  );
  exit(0);
}

function runMain() {
  installPipeGuard(process.stdout);
  installPipeGuard(process.stderr);
  try {
    main(process.argv.slice(2));
  } catch (err) {
    if (err instanceof ExitSignal) {
      process.exitCode = err.code;
      return;
    }
    process.stderr.write(`sync-harness-skills: unexpected error: ${err && err.stack ? err.stack : err}\n`);
    process.exitCode = 2;
  }
}

runMain();
