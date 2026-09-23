const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const path = require('node:path');
const { status } = require('../src/status.js');

assert.deepEqual(JSON.parse(status(['--json'])), { status: 'ok' });
const cli = execFileSync(process.execPath, [path.join(__dirname, '../src/status.js'), '--json'], { encoding: 'utf8' });
assert.deepEqual(JSON.parse(cli), { status: 'ok' });
process.stdout.write('status --json test: PASS\n');
