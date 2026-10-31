// Node preload (manifest honesty guard TEST-3193): logs every fs read/stat/readdir/exists path and every spawned command
// to $AAI_TRACE_OUT (one line each). Read by the guard and by the validation trace script.
const fs = require('node:fs');
const cp = require('node:child_process');
const out = process.env.AAI_TRACE_OUT;
const log = (kind, p) => { try { fs.appendFileSync(out, `${kind}\t${String(p)}\n`); } catch {} };
const names = ['readFileSync', 'readdirSync', 'statSync', 'lstatSync', 'existsSync', 'openSync', 'readFile', 'readdir', 'stat', 'lstat', 'opendirSync', 'accessSync', 'createReadStream', 'realpathSync'];
for (const n of names) {
  const orig = fs[n];
  if (typeof orig !== 'function') continue;
  fs[n] = function (p, ...rest) {
    if (typeof p === 'string' || p instanceof URL || Buffer.isBuffer(p)) log('R', p instanceof URL ? p.pathname : p);
    return orig.call(this, p, ...rest);
  };
}
for (const n of ['spawnSync', 'execFileSync', 'execSync', 'spawn', 'execFile', 'exec']) {
  const orig = cp[n];
  cp[n] = function (cmd, args, ...rest) { log('C', [cmd, ...(Array.isArray(args) ? args : [])].join(' ')); return orig.call(this, cmd, args, ...rest); };
}
