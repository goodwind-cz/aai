// Node preload (admission gate, suite-reuse.mjs lint --admit; also the manifest honesty guard): logs every fs
// read/stat/readdir/exists call as one line "R<TAB>absolute path<TAB>function" and every spawned command as
// "C<TAB>command" to $AAI_TRACE_OUT. Silent in a process whose entry script is suite-reuse.mjs, so the helper's
// own reads never count as the suite's.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const out = process.env.AAI_TRACE_OUT;
const silent = /suite-reuse\.mjs$/.test(process.argv[1] || '') || !out;
if (!silent) {
  const log = (kind, p, fn) => { try { fs.appendFileSync(out, `${kind}\t${kind === 'R' ? path.resolve(String(p)) : String(p)}${fn ? `\t${fn}` : ''}\n`); } catch {} };
  const wrap = (obj, n, label) => {
    const orig = obj[n];
    if (typeof orig !== 'function') return;
    obj[n] = function (p, ...rest) {
      if (typeof p === 'string' || p instanceof URL || Buffer.isBuffer(p)) log('R', p instanceof URL ? p.pathname : p, label);
      return orig.call(this, p, ...rest);
    };
  };
  for (const n of ['readFileSync', 'readdirSync', 'statSync', 'lstatSync', 'existsSync', 'openSync', 'readFile', 'readdir', 'stat', 'lstat', 'opendirSync', 'accessSync', 'createReadStream', 'realpathSync']) wrap(fs, n, n);
  wrap(fs.promises, 'readFile', 'promises.readFile');
  for (const n of ['spawnSync', 'execFileSync', 'execSync', 'spawn', 'execFile', 'exec']) {
    const orig = cp[n];
    cp[n] = function (cmd, args, ...rest) { log('C', [cmd, ...(Array.isArray(args) ? args : [])].join(' ')); return orig.call(this, cmd, args, ...rest); };
  }
}
