// gitignore-block.mjs - the .gitignore reconcile of the layer sync, in one place
// (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, D-GITIGNORE; DR-11, DR-12, DR-14).
//
// Ported from the bash twin of the layer sync and from lib/gitignore-block.sh byte for byte: the managed blocks are
// appended in the bash order, a second run changes nothing, and the self-heal collapses the duplicates that older
// syncs left behind. Stdlib only, no child process and no shell: the early-closing-reader hazard of the bash twin (a
// grep -q closing its pipe under pipefail and a real match read as a miss, so a pattern near the top of a large file
// was appended again on every run) cannot occur, because every match here is a string search over text read once.
//
// The file is read and written as latin1 (one byte per character) so that bytes this module does not own are
// written back unchanged. Importing the module has no side effect.

import fs from 'node:fs';
import path from 'node:path';

// The prefix every runtime-sidecar marker line starts with. The bootstrap marker and the sync marker below carry the
// same prefix; tests/skills/test-aai-sync-seed.sh TEST-020 pins the copies.
export const AAI_GITIGNORE_MARKER_PREFIX = '# AAI runtime sidecars';
export const SYNC_RUNTIME_MARKER = `${AAI_GITIGNORE_MARKER_PREFIX} (seeded from .aai/system/RUNTIME_IGNORE.list; per-dev, never commit)`;

const REPORT_HEADER = '# AAI runtime reports (ephemeral; not project-owned docs)';
const REPORT_PATTERNS = ['docs/ai/reports/**', '!docs/ai/reports/', '!docs/ai/reports/.gitkeep'];
const AGENT_SKILL_HEADER = '# AAI agent skill sync artifacts (managed by sync)';
const AGENT_SKILL_PATTERNS = ['.agents/skills/', '.claude/skills/', '.codex/skills/', '.codex/skills.local/', '.gemini/skills/', '.gemini/skills.local/'];
const RUNTIME_STATE_HEADER = '# AAI per-dev runtime state (RFC-0001: never committed)';
const RUNTIME_STATE_PATTERNS = ['docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl'];
const CACHE_HEADER = '# Expert subagent cache (fetched on-demand from VoltAgent registry)';
const INFRA_HEADER = '# AAI infrastructure (vendored, not committed)';

// The lines the self-heal keeps once each (the AAI-owned set of the bash twin).
const MANAGED_LINES = new Set([
  INFRA_HEADER, CACHE_HEADER, REPORT_HEADER, AGENT_SKILL_HEADER, RUNTIME_STATE_HEADER,
  '.aai/', '.aai/cache/', ...REPORT_PATTERNS, ...AGENT_SKILL_PATTERNS, ...RUNTIME_STATE_PATTERNS,
  '.cloudflare-publish*', '.wrangler/',
]);

// readRaw(file): the file as latin1 text, or '' when it does not exist; any other failure is thrown.
function readRaw(file) {
  try {
    return fs.readFileSync(file, 'latin1');
  } catch (e) {
    if (e.code === 'ENOENT') return '';
    throw e;
  }
}

const append = (file, text) => fs.appendFileSync(file, text, 'latin1');
const stripCr = (s) => s.replace(/\r/g, '');
const hasLine = (text, wanted) => text.split('\n').includes(wanted);
const hasLineStartingWith = (text, prefix) => text.split('\n').some((l) => l.startsWith(prefix));

// seedRuntimeGitignore(file, listPath, markerText): appends every non-blank, non-comment line of the list that is not
// already a line of the file, the marker once and only when no line of the file starts with the marker prefix. The list
// and the file are read with every CR removed. Returns the one note line to print (no indent, no newline): the summary
// `<file> add <n> AAI runtime sidecar pattern(s)`, the missing-list note, or '' when there is nothing to add.
export function seedRuntimeGitignore(file, listPath, markerText) {
  let listText;
  try {
    if (!fs.statSync(listPath).isFile()) throw new Error('not a file');
    listText = fs.readFileSync(listPath, 'latin1');
  } catch {
    return `skipped runtime-sidecar gitignore seed: ${listPath} missing`;
  }
  const raw = readRaw(file);
  const present = new Set(stripCr(raw).split('\n'));
  const missing = [];
  for (const line of stripCr(listText).split('\n')) {
    if (line === '' || line.startsWith('#')) continue;
    if (!present.has(line)) missing.push(line);
  }
  if (missing.length === 0) return '';
  const marker = hasLineStartingWith(raw, AAI_GITIGNORE_MARKER_PREFIX) ? '' : `${markerText}\n`;
  append(file, `\n${marker}${missing.map((l) => `${l}\n`).join('')}`);
  return `${file} add ${missing.length} AAI runtime sidecar pattern(s)`;
}

// appendBlock(file, header, patterns, say, line): one append of "\n", the header (when there is one) and the patterns,
// each with LF, then the one printed line. Every managed append goes through this function.
function appendBlock(file, header, patterns, say, line) {
  append(file, `\n${header === '' ? '' : `${header}\n`}${patterns.map((p) => `${p}\n`).join('')}`);
  say(`  ${line}\n`);
}

// missingExact(file, patterns): the patterns that are not an exact line of the file read now with every CR removed.
function missingExact(file, patterns) {
  const lines = new Set(stripCr(readRaw(file)).split('\n'));
  return patterns.filter((p) => !lines.has(p));
}

// healDuplicates(file, say): collapses the managed lines that occur more than once, keeping the first of each, and runs
// of blank lines, writing the file with its own line ending (CRLF when any CR exists). It rewrites only when a managed
// duplicate was removed, through a temporary sibling this run creates exclusively and renames over the file.
function healDuplicates(file, say) {
  const raw = readRaw(file);
  const crlf = raw.includes('\r');
  const records = raw.split('\n');
  if (records[records.length - 1] === '') records.pop();
  const seen = new Set();
  const keep = [];
  let removed = 0;
  for (const rec of records) {
    const l = rec.endsWith('\r') ? rec.slice(0, -1) : rec;
    if (MANAGED_LINES.has(l)) {
      if (seen.has(l)) {
        removed += 1;
        continue;
      }
      seen.add(l);
    }
    keep.push(l);
  }
  if (removed === 0) return;
  const eol = crlf ? '\r\n' : '\n';
  let prevBlank = false;
  let body = '';
  for (const l of keep) {
    const blank = /^[ \t]*$/.test(l);
    if (blank && prevBlank) continue;
    prevBlank = blank;
    body += `${l}${eol}`;
  }
  const tmp = `${file}.aai-dedup.${process.pid}`;
  fs.writeFileSync(tmp, body, { encoding: 'latin1', flag: 'wx' });
  fs.renameSync(tmp, file);
  say(`  De-duplicated ${removed} stale AAI-managed line(s) in ${file}\n`);
}

// reconcileGitignore(target, { srcList, targetList, out }): the managed blocks of <target>/.gitignore in the bash order:
// .aai/, the runtime-sidecar seed (list: srcList when it is a file, else targetList), .cloudflare-publish* and .wrangler/,
// .aai/cache/, the reports block, the agent-skill block, the runtime-state block with its pointer (DR-14), then the
// self-heal. out(text) receives every printed line with its LF and its two-space indent. Returns nothing.
export function reconcileGitignore(target, { srcList = '', targetList = '', out = () => {} } = {}) {
  if (typeof target !== 'string' || target === '') throw new Error('reconcileGitignore needs a target directory');
  const file = path.join(target, '.gitignore');
  if (!hasLineStartingWith(readRaw(file), '.aai/')) appendBlock(file, INFRA_HEADER, ['.aai/'], out, `Added .aai/ to ${file}`);
  let list = targetList;
  try {
    if (srcList !== '' && fs.statSync(srcList).isFile()) list = srcList;
  } catch {
    list = targetList;
  }
  const note = seedRuntimeGitignore(file, list, SYNC_RUNTIME_MARKER);
  if (note !== '') out(`  ${note}\n`);
  for (const pattern of ['.cloudflare-publish*', '.wrangler/']) {
    if (!readRaw(file).includes(pattern)) appendBlock(file, '', [pattern], out, `Added ${pattern} to ${file}`);
  }
  if (!readRaw(file).includes('.aai/cache/')) appendBlock(file, CACHE_HEADER, ['.aai/cache/'], out, `Added .aai/cache/ to ${file}`);
  if (!readRaw(file).includes('docs/ai/reports/**')) appendBlock(file, REPORT_HEADER, REPORT_PATTERNS, out, `Added docs/ai/reports runtime ignore rules to ${file}`);
  const skills = missingExact(file, AGENT_SKILL_PATTERNS);
  if (skills.length > 0) appendBlock(file, AGENT_SKILL_HEADER, skills, out, `Added agent skill sync patterns to ${file}`);
  const state = missingExact(file, RUNTIME_STATE_PATTERNS);
  if (state.length > 0) {
    appendBlock(file, RUNTIME_STATE_HEADER, state, out, `Added AAI per-dev runtime state patterns to ${file}`);
    out('  NOTE: If docs/ai/STATE.yaml or docs/ai/LOOP_TICKS.jsonl is still tracked,\n');
    out('        run bash .aai/scripts/migrate-state-to-local.sh (or powershell -NoProfile -File .aai/scripts/migrate-state-to-local.ps1) in the target project.\n');
  }
  healDuplicates(file, out);
}
