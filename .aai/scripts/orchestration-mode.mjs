#!/usr/bin/env node
// Orchestration-mode selector CLI (RFC-0005 / SPEC-0005) — automatic, fail-closed
// detection of when a loop tick may safely run parallel.
//
// This is a PURE, DETERMINISTIC decision function over a normalized JSON input
// (D1): no STATE/spec parsing, no clock, no concurrency, no filesystem writes.
// Reading STATE.yaml + specs to BUILD the input is the orchestrator's job
// (SKILL_LOOP "RUN ORCHESTRATION"); this helper trusts its caller and FAILS
// CLOSED on anything it cannot prove safe — overlapping or undeclared paths are
// NEVER co-scheduled (the safety core, SPEC-0004's enforcement floor relies on
// it). It only consumes the `locks_available` boolean its caller computed from
// docs-lock.mjs presence; it never touches locks itself.
//
// Input (D2) — one JSON object on stdin or via `--input <file>`:
//   {
//     "orchestration_mode": "auto",   // auto | single | parallel  (default auto)
//     "k_max": 2,                      // integer >= 1 (default 2)
//     "max_k_budget": null,            // optional int budget ceiling; null = unbounded
//     "locks_available": true,         // false when docs-lock.mjs is absent
//     "scopes": [                      // actionable scopes, already in PRIORITY order
//       {
//         "id": "SPEC-A",
//         "role_kind": "write",        // read = validation|code_review ; write = implementation|tdd|remediation
//         "review_scope_paths": ["apps/web/dashboard/"],
//         "isolation": "inline",       // inline | worktree (relevant for write scopes)
//         "parent": null,
//         "children": []
//       }
//     ]
//   }
//
// Output (D3) — one JSON object on stdout, exit 0:
//   { "mode": "single|parallel", "k": <int>, "groups": [ {kind, scopes[]} ], "reasons": { id: "why deferred" } }
//   At most ONE `parallel` group (co-scheduled THIS tick); every other actionable
//   scope is its own `sequential` singleton. mode=single => no parallel group.
//
// Exit codes:
//   0  success (decision printed to stdout)
//   2  usage error (missing/empty input, malformed JSON, unknown flag)

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(msg, code = 2) {
  console.error(`orchestration-mode: ${msg}`);
  process.exit(code);
}

function usage() {
  console.error(
    'Usage: orchestration-mode [--input <file>]   (default: read JSON from stdin)\n' +
    '  Reads the D2 selector input JSON and prints the D3 decision\n' +
    '  {mode,k,groups,reasons} to stdout (exit 0). Bad input/flag -> exit 2.',
  );
}

// --- Pure decision helpers (D4) ---------------------------------------------

// Normalize a declared path to its canonical, literal, glob-free prefix for
// overlap tests. Returns null when the path reduces to the WHOLE REPO or an
// EMPTY/unparseable prefix — the caller treats null as "uncertain" (fail-closed),
// so a non-literal spelling can never defeat the overlap check (review E1).
// Canonicalization: case-fold (safe: over-sequential at worst, never unsafe),
// strip "." segments, collapse "//", resolve ".." (a path escaping its root is
// unparseable -> null), and stop at the first glob segment.
//   normalizePath("apps/api/")        -> "apps/api"
//   normalizePath("./apps//api/")     -> "apps/api"
//   normalizePath("apps/web/../api")  -> "apps/api"
//   normalizePath("Apps/Api")         -> "apps/api"   (case-folded)
//   normalizePath("apps/web/**")      -> "apps/web"
//   normalizePath(".") / "" / "*" / "**" / "*.md" / "/x" -> null  (uncertain)
function normalizePath(p) {
  if (typeof p !== 'string') return null;
  let s = p.trim();
  if (s === '') return null;
  // An absolute path can't be compared to repo-relative declared scopes -> null.
  if (s.startsWith('/')) return null;
  s = s.toLowerCase();
  const out = [];
  for (const seg of s.split('/')) {
    if (seg === '' || seg === '.') continue;     // collapse "//", "./", trailing "/"
    if (seg === '..') {
      if (out.length === 0) return null;          // escapes the declared root -> fail-closed
      out.pop();
      continue;
    }
    if (seg.includes('*')) break;                 // literal prefix up to the first glob
    out.push(seg);
  }
  if (out.length === 0) return null;              // ".", whole-repo, or bare/leading glob
  return out.join('/');
}

function isWorktreeWrite(scope) {
  return scope.role_kind === 'write' && scope.isolation === 'worktree';
}

// A write scope isolated in a worktree (D4) has guaranteed-disjoint writes; its
// effective paths are EMPTY for collision purposes and it is NOT uncertain.
function effectivePaths(scope) {
  if (isWorktreeWrite(scope)) return [];
  const paths = Array.isArray(scope.review_scope_paths) ? scope.review_scope_paths : [];
  return paths.map(normalizePath).filter((x) => x !== null);
}

// Uncertain iff: no declared paths, OR any path is empty/whitespace, OR any path
// reduces to an empty literal prefix (bare/leading glob). A worktree write is
// never uncertain on the path axis.
function isUncertain(scope) {
  if (isWorktreeWrite(scope)) return false;
  const paths = Array.isArray(scope.review_scope_paths) ? scope.review_scope_paths : [];
  if (paths.length === 0) return true;
  for (const p of paths) {
    if (normalizePath(p) === null) return true;
  }
  return false;
}

// Two normalized paths overlap iff equal OR one is a path-boundary prefix of the
// other (`b === a` or `b.startsWith(a + "/")`).
function pathsOverlap(a, b) {
  if (a === b) return true;
  return b.startsWith(`${a}/`) || a.startsWith(`${b}/`);
}

function isLinkedParentChild(s1, s2) {
  if (s1.parent != null && s1.parent === s2.id) return true;
  if (s2.parent != null && s2.parent === s1.id) return true;
  if (Array.isArray(s1.children) && s1.children.includes(s2.id)) return true;
  if (Array.isArray(s2.children) && s2.children.includes(s1.id)) return true;
  return false;
}

// conflict(S1,S2): true iff ANY of (1) either uncertain, (2) parent/child link,
// (3) effective paths overlap. Path overlap is a conflict for ANY role_kind
// (reads on shared paths cost throughput, never safety — keeps the rule one line).
function conflict(s1, s2) {
  if (isUncertain(s1) || isUncertain(s2)) return true;
  if (isLinkedParentChild(s1, s2)) return true;
  const p1 = effectivePaths(s1);
  const p2 = effectivePaths(s2);
  for (const a of p1) {
    for (const b of p2) {
      if (pathsOverlap(a, b)) return true;
    }
  }
  return false;
}

// --- Param coercion (D6 edge cases) -----------------------------------------

function coerceKMax(raw) {
  if (raw === undefined || raw === null) return 2; // default 2 (D8)
  const n = Number(raw);
  return Number.isInteger(n) && n >= 1 ? n : 1; // k_max<1 / non-integer -> 1 (single)
}

function coerceBudget(raw) {
  if (raw === undefined || raw === null) return Infinity; // unbounded
  const n = Number(raw);
  if (!Number.isFinite(n)) return Infinity;
  return Math.max(1, Math.floor(n));
}

function describeUncertain(scope, idCounts) {
  if (idCounts[scope.id] > 1) return 'uncertain: duplicate scope id (fail-closed)';
  if (scope.parent != null && scope.parent === scope.id) {
    return 'uncertain: scope lists itself as parent (fail-closed)';
  }
  const paths = Array.isArray(scope.review_scope_paths) ? scope.review_scope_paths : [];
  if (paths.length === 0) return 'uncertain: no declared review-scope paths (fail-closed)';
  return 'uncertain: unparseable or empty review-scope path (fail-closed)';
}

// --- Core selector (D6) ------------------------------------------------------

function selectGroups(input) {
  const modeIn = input.orchestration_mode == null ? 'auto' : input.orchestration_mode;
  const kMax = coerceKMax(input.k_max);
  const budget = coerceBudget(input.max_k_budget);
  const locksAvailable = input.locks_available !== false; // default true unless explicitly false
  const locksCap = locksAvailable ? Infinity : 1;
  const effectiveCap = Math.min(kMax, budget, locksCap);

  const scopes = Array.isArray(input.scopes) ? input.scopes : [];

  // Empty actionable set -> single / k=1 / no groups (orchestrator handles no-op).
  if (scopes.length === 0) {
    return { mode: 'single', k: 1, groups: [], reasons: {} };
  }

  // Duplicate ids (fail-closed) — mark every scope that shares an id.
  const idCounts = {};
  for (const s of scopes) idCounts[s.id] = (idCounts[s.id] || 0) + 1;
  const augUncertain = (s) =>
    idCounts[s.id] > 1 ||
    (s.parent != null && s.parent === s.id) ||
    isUncertain(s);

  // Override `single` ALWAYS wins (D6) — highest-priority scope runs; the rest
  // are deferred sequential singletons.
  if (modeIn === 'single') {
    const reasons = {};
    for (let i = 1; i < scopes.length; i += 1) {
      reasons[scopes[i].id] = 'deferred: override orchestration_mode=single';
    }
    return {
      mode: 'single',
      k: 1,
      groups: scopes.map((s) => ({ kind: 'sequential', scopes: [s.id] })),
      reasons,
    };
  }

  // Greedy parallel-group build in priority order (auto and parallel both
  // safety-gated; `parallel` is an opt-in signal, never a safety override).
  const reasons = {};
  const groupIds = [];
  const groupScopes = [];

  const capReasonText = () => {
    if (!locksAvailable) return 'deferred: locks_unavailable (docs-lock.mjs absent -> K=1)';
    if (budget < kMax && budget === effectiveCap) {
      return `deferred: max_k_budget reached (budget=${budget})`;
    }
    return `deferred: k_cap reached (k_max=${kMax})`;
  };

  for (const s of scopes) {
    if (augUncertain(s)) {
      reasons[s.id] = describeUncertain(s, idCounts);
      continue;
    }
    if (groupIds.length >= effectiveCap) {
      reasons[s.id] = capReasonText();
      continue;
    }
    let conflictsWith = null;
    for (const m of groupScopes) {
      if (conflict(s, m)) {
        conflictsWith = m.id;
        break;
      }
    }
    if (conflictsWith !== null) {
      reasons[s.id] = `deferred: conflicts-with ${conflictsWith}`;
      continue;
    }
    groupIds.push(s.id);
    groupScopes.push(s);
  }

  if (groupIds.length >= 2) {
    const groups = [{ kind: 'parallel', scopes: groupIds }];
    for (const s of scopes) {
      if (!groupIds.includes(s.id)) groups.push({ kind: 'sequential', scopes: [s.id] });
    }
    return { mode: 'parallel', k: groupIds.length, groups, reasons };
  }

  // Single: one scope, all-conflicting scopes, or a cap forcing < 2.
  return {
    mode: 'single',
    k: 1,
    groups: scopes.map((s) => ({ kind: 'sequential', scopes: [s.id] })),
    reasons,
  };
}

// --- CLI --------------------------------------------------------------------

function parseArgs(argv) {
  let inputFile = null;
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--input') {
      inputFile = argv[i + 1];
      i += 1;
      if (!inputFile) {
        usage();
        fail('--input requires a file path', 2);
      }
    } else if (tok === '-h' || tok === '--help') {
      usage();
      process.exit(2);
    } else if (tok.startsWith('--')) {
      usage();
      fail(`unknown flag "${tok}"`, 2);
    } else {
      usage();
      fail(`unexpected argument "${tok}"`, 2);
    }
  }
  return { inputFile };
}

function readInput(inputFile) {
  let raw;
  if (inputFile) {
    try {
      raw = fs.readFileSync(inputFile, 'utf8');
    } catch {
      fail(`cannot read input file: ${inputFile}`, 2);
    }
  } else {
    try {
      raw = fs.readFileSync(0, 'utf8'); // stdin
    } catch {
      raw = '';
    }
  }
  if (!raw || raw.trim() === '') {
    usage();
    fail('no input provided (stdin or --input <file>)', 2);
  }
  let obj;
  try {
    obj = JSON.parse(raw);
  } catch {
    fail('malformed JSON input', 2);
  }
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
    fail('input must be a JSON object', 2);
  }
  return obj;
}

function main() {
  const { inputFile } = parseArgs(process.argv);
  const input = readInput(inputFile);
  const out = selectGroups(input);
  console.log(JSON.stringify(out));
  process.exit(0);
}

// Run as CLI only when invoked directly; importable for unit tests.
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) main();

export {
  normalizePath,
  isUncertain,
  effectivePaths,
  pathsOverlap,
  conflict,
  selectGroups,
};
