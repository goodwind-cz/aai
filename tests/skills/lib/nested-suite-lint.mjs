#!/usr/bin/env node
// tests/skills/lib/nested-suite-lint.mjs
//
// Hygiene ratchet for nested-suite-reruns-duplicate-sweep-time (D7): refuses a
// suite that runs ANOTHER WHOLE suite. A nested run pays the companion's cost a
// second time in every sweep; the companion is declared in
// tests/skills/suite-map.yaml (`companions:`) and pinned with
// assert_companions (tests/skills/lib/companion-assert.sh) instead.
//
// WHAT IT REPORTS
//   An invocation by `bash`, `sh`, or aai-run-tests.sh (literal path or a
//   variable holding it), whose suite argument resolves to an on-disk
//   test-aai-*.sh in the scanned directory, and which is followed by no further
//   positional argument before a redirection, a pipe, a closing parenthesis,
//   `;`, `&&`, `||` or the end of the line. The suite argument resolves through
//     1. a literal containing test-aai-<name>.sh;
//     2. $VAR / ${VAR} whose assignment in the same file ends in
//        test-aai-<name>.sh (resolveVarSuite);
//     3. a token holding the loop variable of an enclosing `for <v> in <list>`
//        whose list names test-aai-* files or tests/skills/test-aai-* paths;
//     4. the suite's own path by $0, ${BASH_SOURCE[0]} or a *_SELF variable.
//   Comment lines and heredoc bodies are skipped. A name that is not an on-disk
//   suite (a fixture such as test-aai-wsuite.sh) is never reported. A
//   selector-form call (a positional argument after the suite) is never
//   reported: it is cheap and pins one contract (Residual risk RR-3).
//
// USAGE
//   node nested-suite-lint.mjs [--allowlist <tsv>] <dir-holding-test-aai-*.sh>
//   output   <file>:<line>: <function>: nested whole-suite run of <suite file>
//            then (with --allowlist) ALLOWLISTED: <k> and one
//            `STALE allowlist row: ...` per row that matches nothing, then
//            TOTAL: <n>  (findings left after the allowlist)
//   exit     with --allowlist: 0 clean; 1 findings left or a stale row.
//            without: 0 (report only, the caller judges). 2 plumbing failure.
//
// Allowlist TSV: `<outer file>\t<function>\t<nested suite file>\t<reason>`,
// '#' comments and blank lines ignored. The allowlist only shrinks: a row that
// matches no finding is stale and fails the run.

import fs from "node:fs";
import path from "node:path";

const SUITE_RE = /test-aai-([a-z0-9-]+)\.sh/;

export function resolveVarSuite(name, vars) {
  // Follows `NAME="...test-aai-<x>.sh"` assignments, and one hop of
  // `NAME="$OTHER"` so a suite alias is not a way around the lint. A name may
  // be assigned more than once in a file (a function-local reassigned later);
  // it resolves as a suite when ANY of its assignments does, so a later
  // non-suite value cannot hide an earlier suite one.
  const seen = new Set();
  const walk = (cur, hop) => {
    if (hop >= 4 || seen.has(cur + "#" + hop)) return null;
    seen.add(cur + "#" + hop);
    const vals = vars.get(cur);
    if (vals === undefined) return null;
    for (const val of Array.isArray(vals) ? vals : [vals]) {
      const m = val.match(/test-aai-([a-z0-9-]+)\.sh["']?\s*$/);
      if (m) return m[1];
      const ref = val.match(/^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/);
      if (ref) {
        const r = walk(ref[1], hop + 1);
        if (r) return r;
      }
    }
    return null;
  };
  return walk(name, 0);
}

// Join backslash continuations; keep the first physical line number.
function logicalLines(text) {
  const phys = text.split("\n");
  const out = [];
  for (let i = 0; i < phys.length; i++) {
    let line = phys[i];
    const start = i + 1;
    while (/\\\s*$/.test(line) && i + 1 < phys.length && !/^\s*#/.test(line)) {
      i++;
      line = line.replace(/\\\s*$/, " ") + phys[i];
    }
    out.push({ n: start, text: line });
  }
  return out;
}

function stripComment(s) {
  let q = null;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (q) {
      if (c === q) q = null;
      else if (c === "\\" && q === '"') i++;
      continue;
    }
    if (c === "'" || c === '"') q = c;
    else if (c === "\\") i++;
    else if (c === "#" && (i === 0 || /\s|[;(&|]/.test(s[i - 1]))) return s.slice(0, i);
  }
  return s;
}

// Tokens: {t: text, op: bool}. Quotes are removed from words; |;&<>() split.
// A stack tracks double quotes, single quotes and `$(...)` / `(...)`, so a
// launcher inside "$(bash "$X" 2>&1)" is tokenized like a top-level one.
function tokenize(s) {
  const toks = [];
  const stack = ["top"];
  let word = "";
  let has = false;
  const flush = (i) => {
    if (has) {
      const fdRedirect = /^[0-9]+$/.test(word) && i < s.length && (s[i] === ">" || s[i] === "<");
      if (!fdRedirect) toks.push({ t: word, op: false });
    }
    word = "";
    has = false;
  };
  let i = 0;
  while (i < s.length) {
    const ctx = stack[stack.length - 1];
    const c = s[i];
    if (ctx === "sq") {
      if (c === "'") stack.pop(); else word += c;
      i++;
      continue;
    }
    if (ctx === "dq") {
      if (c === "\\") { word += s[i + 1] || ""; i += 2; continue; }
      if (c === '"') { stack.pop(); i++; continue; }
      if (c === "$" && s[i + 1] === "(") { flush(-1); toks.push({ t: "$(", op: true }); stack.push("sub"); i += 2; continue; }
      word += c; has = true; i++;
      continue;
    }
    if (/\s/.test(c)) { flush(i); i++; continue; }
    if (c === '"') { stack.push("dq"); has = true; i++; continue; }
    if (c === "'") { stack.push("sq"); has = true; i++; continue; }
    if (c === "\\") { word += s[i + 1] || ""; has = true; i += 2; continue; }
    if (c === "$" && s[i + 1] === "(") { flush(-1); toks.push({ t: "$(", op: true }); stack.push("sub"); i += 2; continue; }
    if (c === "(") { flush(i); toks.push({ t: "(", op: true }); stack.push("sub"); i++; continue; }
    if (c === ")") { flush(i); toks.push({ t: ")", op: true }); if (stack.length > 1) stack.pop(); i++; continue; }
    if (/[|;&<>]/.test(c)) {
      flush(i);
      let j = i;
      while (j < s.length && /[|;&<>]/.test(s[j])) j++;
      toks.push({ t: s.slice(i, j), op: true });
      i = j;
      continue;
    }
    word += c; has = true; i++;
  }
  flush(-1);
  return toks;
}

const LEAD_OK = new Set(["if", "then", "else", "elif", "do", "!", "{", "time", "exec", "command", "nohup", "while", "until"]);

function isCommandPosition(toks, idx) {
  // A launcher is in command position when, walking forward from the last
  // operator, only env assignments and known prefix words precede it.
  let start = 0;
  for (let k = idx - 1; k >= 0; k--) if (toks[k].op) { start = k + 1; break; }
  let j = start;
  while (j < idx) {
    const t = toks[j].t;
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t) || LEAD_OK.has(t)) { j++; continue; }
    if (t === "env") {
      j++;
      while (j < idx && /^-/.test(toks[j].t)) j += /^-[uCS]$/.test(toks[j].t) ? 2 : 1;
      continue;
    }
    if (t === "timeout") { j++; while (j < idx && /^-/.test(toks[j].t)) j++; j++; continue; }
    if (/\$$/.test(t)) { j++; continue; }
    return false;
  }
  return j === idx;
}

function scanFile(dir, file, suites) {
  const text = fs.readFileSync(path.join(dir, file), "utf8");
  const ownSuite = (file.match(SUITE_RE) || [])[1] || null;
  const lines = logicalLines(text);
  const vars = new Map();
  for (const { text: l } of lines) {
    const m = l.match(/^\s*(?:local\s+|readonly\s+|export\s+|declare\s+(?:-[a-zA-Z]+\s+)?)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (m && !/^\s*#/.test(l)) {
      const rest = stripComment(m[2]).trim();
      const q = rest.match(/^(["'])(.*?)\1/);
      const val = q ? q[2] : rest.split(/\s+/)[0];
      if (!vars.has(m[1])) vars.set(m[1], []);
      vars.get(m[1]).push(val);
    }
  }
  const runnerVars = new Set();
  for (const [k, vs] of vars) if (vs.some((v) => /aai-run-tests\.sh$/.test(v))) runnerVars.add(k);

  const findings = [];
  let fn = "(top level)";
  let heredoc = null;
  const loops = []; // stack of {v, items}
  for (const { n, text: raw } of lines) {
    if (heredoc) {
      const body = heredoc.dash ? raw.replace(/^\t+/, "") : raw;
      if (body.trimEnd() === heredoc.tag) heredoc = null;
      continue;
    }
    if (/^\s*#/.test(raw)) continue;
    const line = stripComment(raw);
    const fm = line.match(/^(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{?/) || line.match(/^function\s+([A-Za-z_][A-Za-z0-9_]*)/);
    if (fm && !/^\s/.test(line)) fn = fm[1];
    const hd = line.match(/<<(-?)\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\2/);
    if (hd && !/<<</.test(line)) heredoc = { tag: hd[3], dash: hd[1] === "-" };
    const fl = line.match(/^\s*for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+(.*?)(?:;\s*do\b.*)?$/);
    let popAfter = 0;
    if (fl) {
      loops.push({ v: fl[1], items: (fl[2].match(/test-aai-[a-z0-9-]+(?:\.sh)?/g) || []).map((x) => x.replace(/\.sh$/, "")) });
    } else if (/^\s*(for|while|until|select)\b/.test(line)) loops.push({ v: null, items: [] });
    if (/(^|;|\s)done\b/.test(line)) popAfter = 1;
    const toks = tokenize(line);
    for (let i = 0; i < toks.length; i++) {
      const tk = toks[i];
      if (tk.op) continue;
      const base = tk.t.split("/").pop();
      let argIdx = -1;
      if ((base === "bash" || base === "sh") && isCommandPosition(toks, i)) argIdx = i + 1;
      else if ((base === "aai-run-tests.sh" || /^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/.test(tk.t) && runnerVars.has(tk.t.replace(/[${}]/g, ""))) && (isCommandPosition(toks, i) || (i > 0 && !toks[i - 1].op && /^(bash|sh)$/.test(toks[i - 1].t.split("/").pop()) && isCommandPosition(toks, i - 1)))) {
        // runner form: <runner> bash <suite>
        let j = i + 1;
        if (toks[j] && !toks[j].op && /^(bash|sh)$/.test(toks[j].t.split("/").pop())) argIdx = j + 1;
      }
      if (argIdx < 0) continue;
      // skip shell options (bash -e / -x / --norc); -n is a syntax check, not a run
      let syntaxOnly = false;
      while (toks[argIdx] && !toks[argIdx].op && /^-/.test(toks[argIdx].t)) {
        if (/^-[a-zA-Z]*n[a-zA-Z]*$/.test(toks[argIdx].t)) syntaxOnly = true;
        argIdx++;
      }
      if (syntaxOnly) continue;
      const arg = toks[argIdx];
      if (!arg || arg.op) continue;
      const after = toks[argIdx + 1];
      if (after && !after.op) continue; // selector form (positional argument)
      const resolved = resolveArg(arg.t, vars, loops, ownSuite);
      for (const s of resolved) if (suites.has(s)) findings.push({ file, n, fn, suite: s });
    }
    if (popAfter) loops.pop();
  }
  return findings;
}

function resolveArg(t, vars, loops, ownSuite) {
  const out = [];
  const lit = t.match(SUITE_RE);
  if (lit) return [lit[1]];
  if (/^\$0$|^\$\{0\}$|\$\{?BASH_SOURCE(\[0\])?\}?/.test(t) || /\$\{?[A-Za-z0-9_]*_SELF\}?$/.test(t)) {
    return ownSuite ? [ownSuite] : [];
  }
  const vm = t.match(/^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$/);
  if (vm) {
    const s = resolveVarSuite(vm[1], vars);
    return s ? [s] : [];
  }
  for (const lp of loops) {
    if (!lp.v) continue;
    if (t.includes("$" + lp.v) || t.includes("${" + lp.v + "}")) {
      for (const item of lp.items) {
        const sub = t.split("${" + lp.v + "}").join(item).split("$" + lp.v).join(item);
        const m = (/\.sh$/.test(sub) ? sub : sub + ".sh").match(SUITE_RE);
        if (m) out.push(m[1]);
      }
    }
  }
  return out;
}

function readAllowlist(p) {
  const rows = [];
  for (const [i, l] of fs.readFileSync(p, "utf8").split("\n").entries()) {
    if (!l.trim() || /^\s*#/.test(l)) continue;
    const c = l.split("\t");
    if (c.length < 4 || c.slice(0, 4).some((x) => !x.trim())) throw new Error(`allowlist ${p}:${i + 1}: need 4 tab-separated non-empty columns`);
    rows.push({ file: c[0].trim(), fn: c[1].trim(), nested: c[2].trim(), reason: c.slice(3).join("\t").trim() });
  }
  return rows;
}

function main(argv) {
  let allow = null;
  let dir = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--allowlist") allow = argv[++i];
    else dir = argv[i];
  }
  if (!dir || (argv.includes("--allowlist") && !allow)) {
    console.error("usage: nested-suite-lint.mjs [--allowlist <tsv>] <dir>");
    return 2;
  }
  let files;
  try {
    files = fs.readdirSync(dir).filter((f) => /^test-aai-[a-z0-9-]+\.sh$/.test(f)).sort();
  } catch (e) {
    console.error(`nested-suite-lint: cannot read ${dir}: ${e.message}`);
    return 2;
  }
  if (files.length === 0) {
    console.error(`nested-suite-lint: no test-aai-*.sh under ${dir}`);
    return 2;
  }
  const suites = new Set(files.map((f) => f.match(SUITE_RE)[1]));
  let rows = [];
  if (allow) {
    try { rows = readAllowlist(allow); } catch (e) { console.error(`nested-suite-lint: ${e.message}`); return 2; }
  }
  const all = [];
  for (const f of files) all.push(...scanFile(dir, f, suites));
  const used = new Set();
  const left = [];
  for (const f of all) {
    const idx = rows.findIndex((r) => r.file === f.file && r.fn === f.fn && r.nested === `test-aai-${f.suite}.sh`);
    if (idx >= 0) used.add(idx); else left.push(f);
  }
  for (const f of left) console.log(`${f.file}:${f.n}: ${f.fn}: nested whole-suite run of test-aai-${f.suite}.sh`);
  let stale = 0;
  if (allow) {
    console.log(`ALLOWLISTED: ${used.size}`);
    rows.forEach((r, i) => { if (!used.has(i)) { stale++; console.log(`STALE allowlist row: ${r.file} ${r.fn} ${r.nested}`); } });
  }
  console.log(`TOTAL: ${left.length}`);
  if (!allow) return 0; // report-only without an allowlist (the caller judges)
  return left.length > 0 || stale > 0 ? 1 : 0;
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1] && import.meta.url === new URL(`file://${path.resolve(process.argv[1])}`).href) {
  process.exit(main(process.argv.slice(2)));
}
