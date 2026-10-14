#!/usr/bin/env node
// Shared staged-index / PR commit-range notes gate. Node stdlib only.
import { execFileSync } from 'node:child_process';
import { readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export function isShipped(path, mode = '') {
  return /^(?:\.aai|\.github|\.claude|\.codex|\.agents|\.gemini)\//.test(path) ||
    (!path.includes('/') && (mode === '100755' || /\.(?:sh|ps1|mjs|cjs|js|py|rb|bat|cmd)$/.test(path)));
}

export function hasNoNotesReason(body) {
  return typeof body === 'string' && /^no-notes:[ \t]*\S[^\r\n]*$/m.test(body);
}

function git(args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    throw new Error(`git ${args[0]} failed: ${String(error.stderr || error.message).trim()}`);
  }
}

function addedLines(patch) {
  const lines = new Set();
  let number = 0;
  let inHunk = false;
  for (const line of patch.split('\n')) {
    const hunk = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(line);
    if (hunk) { number = Number(hunk[1]); inHunk = true; continue; }
    if (!inHunk) continue;
    if (line.startsWith('+')) { lines.add(number); number++; }
    else if (line.startsWith(' ')) number++;
    else if (!line.startsWith('-') && !line.startsWith('\\')) inHunk = false;
  }
  return lines;
}

// A titled unreleased region needs meaningful newly added body text. A bare
// scaffold, an unchanged old entry, or an added heading alone cannot qualify.
export function hasAddedNotes(content, patch) {
  const added = addedLines(patch);
  const lines = content.split(/\r?\n/);
  let entry = false;
  let comment = false;
  // Inline code uses equally sized backtick runs; unmatched runs stay literal.
  // Headings are single-line blocks, so their code delimiters must close here.
  const codeSpanEnd = (line, start) => {
    let end = start;
    while (line[end] === '`') end++;
    const size = end - start;
    const runs = /`+/g;
    runs.lastIndex = end;
    let match;
    while ((match = runs.exec(line))) {
      if (match[0].length === size) return match.index + size;
    }
    return -1;
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    let visible = '';
    let offset = 0;
    // Track comments across every region before interpreting headings. A
    // hidden heading must neither activate an entry nor reset comment state.
    while (offset < line.length) {
      if (comment) {
        const end = line.indexOf('-->', offset);
        if (end < 0) break;
        offset = end + 3;
        comment = false;
      } else if (line.charCodeAt(offset) === 92 && /[!-/:-@\[-`{-~]/.test(line[offset + 1] || '')) {
        // An escaped punctuation mark cannot open an inline-code span/comment.
        visible += line.slice(offset, offset + 2);
        offset += 2;
      } else if (line[offset] === '`') {
        let end = codeSpanEnd(line, offset);
        if (end < 0) {
          // The whole unmatched run is literal; its suffix is not a new opener.
          end = offset;
          while (line[end] === '`') end++;
        }
        visible += line.slice(offset, end);
        offset = end;
      } else if (line.startsWith('<!--', offset)) {
        offset += 4;
        comment = true;
      } else {
        visible += line[offset++];
      }
    }
    if (/^## /.test(visible)) {
      entry = /^## \[unreleased\] — \S/.test(visible);
      continue;
    }
    if (!entry) continue;
    if (added.has(i + 1) && visible.trim() && !/^\s*(?:#{1,6}\s|[-*+]\s*$)/.test(visible)) return true;
  }
  return false;
}

export function checkNotes(args) {
  let staged = false; let base; let head; let bodyFile;
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (flag === '--staged' && !staged) staged = true;
    else if (['--base', '--head', '--body-file'].includes(flag) && args[i + 1] && !args[i + 1].startsWith('--')) {
      const value = args[++i];
      if (flag === '--base' && base === undefined) base = value;
      else if (flag === '--head' && head === undefined) head = value;
      else if (flag === '--body-file' && bodyFile === undefined) bodyFile = value;
      else throw new Error(`duplicate argument ${flag}`);
    } else throw new Error(`invalid argument ${flag}`);
  }
  if (!bodyFile || (staged ? base !== undefined || head !== undefined : !base || !head)) {
    throw new Error('usage: --staged --body-file PATH or --base SHA --head SHA --body-file PATH');
  }
  let body;
  try { body = readFileSync(bodyFile, 'utf8'); }
  catch (error) { throw new Error(`cannot read PR body ${bodyFile}: ${error.message}`); }
  // Resolve commits before exemptions: missing history is never a success.
  // A pull request is the patch since the merge base. Two endpoints would
  // treat a later base-only change as part of the head.
  const resolve = (ref) => git(['rev-parse', '--verify', '--end-of-options', `${ref}^{commit}`]).trim();
  const headSha = staged ? resolve('HEAD') : resolve(head);
  const range = staged
    ? ['--cached', headSha]
    : [git(['merge-base', '--end-of-options', resolve(base), headSha]).trim(), headSha];
  const raw = git(['diff', '--raw', '-z', '--no-renames', '--no-ext-diff', ...range, '--']).split('\0');
  const shipped = [];
  let changelogChanged = false;
  for (let i = 0; i < raw.length && raw[i]; i += 2) {
    const record = /^:(\d+) (\d+) \S+ \S+ \S+$/.exec(raw[i]);
    if (!record || raw[i + 1] === undefined) throw new Error('malformed Git changed-path output');
    const path = raw[i + 1];
    if (path === 'CHANGELOG.md') changelogChanged = true;
    if (isShipped(path, record[1]) || isShipped(path, record[2])) shipped.push(path);
  }
  if (!shipped.length) return 'PASS: release-notes exempt (no shipped surfaces)';
  if (hasNoNotesReason(body)) return 'PASS: release-notes explicit no-notes reason';
  if (changelogChanged) {
    // Read the index/commit, never an unstaged working-tree companion.
    const target = staged ? ':CHANGELOG.md' : `${range[1]}:CHANGELOG.md`;
    let content = '';
    // Deleted CHANGELOG cannot qualify; all other blob errors fail closed.
    const exists = git(staged ? ['ls-files', '--stage', '--', 'CHANGELOG.md'] : ['ls-tree', range[1], '--', 'CHANGELOG.md']).trim();
    if (exists) content = git(['show', target]);
    // Cosmetic line endings/right-edge whitespace must not manufacture added note content.
    const patch = git(['diff', '--no-ext-diff', '--no-textconv', '--no-renames', '--ignore-space-at-eol', '--unified=0', ...range, '--', 'CHANGELOG.md']);
    if (hasAddedNotes(content, patch)) return 'PASS: release-notes newly added unreleased entry';
  }
  throw new Error(`missing newly added nonempty unreleased notes or no-notes: reason for shipped surfaces: ${shipped.join(', ')}`);
}

function realOrResolve(p) {
  try { return realpathSync(p); } catch { return resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  try { console.log(checkNotes(process.argv.slice(2))); }
  catch (error) { console.error(`REFUSED: release-notes ${error.message}`); process.exitCode = 1; }
}
