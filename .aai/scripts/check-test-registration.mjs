#!/usr/bin/env node
// check-test-registration — every defined test_* function in every
// tests/skills/test-*.sh must actually be invoked (CHANGE test-registration
// guard). THE INCIDENT: a regression pin (test_012, the ONLY guard for a
// fixed BLOCKING bug) was defined but never wired into main(); the suite
// stayed green and the fix shipped unprotected (caught by review, #229).
// Registered = the bare name occurs beyond its definition, OR the suite uses
// the dynamic `"test_${t}"` idiom and the name's suffix is listed in
// ALL_TESTS. Exit 0 clean; exit 1 with one line per orphan; exit 2 usage.
import fs from 'node:fs';
import path from 'node:path';
const dir = process.argv[2] || 'tests/skills';
let bad = 0;
let files;
try { files = fs.readdirSync(dir).filter(f => /^test-.*\.sh$/.test(f)).sort(); }
catch { console.error(`check-test-registration: unreadable dir ${dir}`); process.exit(2); }
for (const f of files) {
  const s = fs.readFileSync(path.join(dir, f), 'utf8');
  const defined = [...s.matchAll(/^(test_[A-Za-z0-9_]+)\(\)\s*\{/gm)].map(m => m[1]);
  const dynamic = s.includes('"test_${');
  const allTests = [...s.matchAll(/^ALL_TESTS="([^"]*)"/gm)].map(m => m[1]).join(' ');
  for (const fn of defined) {
    const esc = fn.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const occ = (s.match(new RegExp(`\\b${esc}\\b`, 'g')) || []).length;
    const defs = (s.match(new RegExp(`^${esc}\\(\\)\\s*\\{`, 'gm')) || []).length;
    if (occ > defs) continue;
    if (dynamic) {
      const tok = fn.slice('test_'.length).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      if (new RegExp(`\\b${tok}\\b`).test(allTests)) continue;
    }
    console.error(`ORPHAN TEST: ${f}: ${fn} is defined but never invoked`);
    bad += 1;
  }
}
process.exit(bad ? 1 : 0);
