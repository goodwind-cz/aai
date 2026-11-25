// seterr-lint (spec-node-first-cleanup D-SETERR): test-only, Node stdlib.
// Under errexit a function called in a condition context (left of || or &&, after if / elif / while / until / !)
// runs with errexit switched off, so a failure inside it no longer stops the script. This lint reports each such
// call of a function defined in the same file, in a script that turns errexit on at top level.
//   lintText(text, file?) -> [{ file, line, fn, context }]      lintFiles(paths) -> the findings of every path
import fs from 'node:fs';

const ERREXIT = /^set\s+(?:-[A-Za-z]*e[A-Za-z]*\b|-o\s+errexit\b)/;
const DEFINE = [/^\s*function\s+([A-Za-z_][\w:.-]*)/, /^\s*([A-Za-z_][\w:.-]*)\s*\(\)\s*\{?/];

// a line without its comment: a whole-line comment is dropped, a trailing one is cut when no quote precedes it
function code(line) {
  const t = line.trim();
  if (t.startsWith('#')) return '';
  const at = line.search(/\s#/);
  return at >= 0 && !/['"]/.test(line.slice(0, at)) ? line.slice(0, at) : line;
}

const firstWord = (segment) => {
  const m = segment.trim().replace(/^(?:(?:!|if|elif|while|until|then|do|else)\s+)+/, '').match(/^([A-Za-z_][\w:.-]*)(?=\s|;|$)/);
  return m ? m[1] : null;
};

export function lintText(text, file = '') {
  const findings = [];
  const lines = text.split('\n').map(code);
  if (!lines.some((l) => ERREXIT.test(l))) return [];
  const fns = new Set();
  for (const l of lines) for (const re of DEFINE) { const m = l.match(re); if (m && !['if', 'while', 'until', 'elif'].includes(m[1])) fns.add(m[1]); }
  lines.forEach((l, i) => {
    if (DEFINE.some((re) => re.test(l)) && /\)\s*\{?\s*$|^\s*function\s/.test(l)) return;
    const hit = (fn, context) => findings.push({ file, line: i + 1, fn, context });
    const parts = l.split(/\|\||&&/);
    // left of || or && (every segment but the last)
    parts.slice(0, -1).forEach((seg) => { const w = firstWord(seg); if (w && fns.has(w)) hit(w, 'left-of-operator'); });
    // right after if / elif / while / until / !, in the first segment of the line
    const kw = parts[0].match(/(?:^|[;{(]\s*|\bthen\s+|\bdo\s+)\s*(if|elif|while|until|!)\s+(?:!\s*)?([A-Za-z_][\w:.-]*)/);
    if (kw && fns.has(kw[2]) && !(parts.length > 1 && firstWord(parts[0]) === kw[2])) hit(kw[2], kw[1]);
  });
  return findings;
}

export function lintFiles(paths) {
  return paths.flatMap((p) => lintText(fs.readFileSync(p, 'utf8'), p));
}
