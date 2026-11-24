// release-reference.mjs - the frozen release launcher reference and the scratch-safety helpers
// (docs/specs/SPEC-0311-spec-node-first-phase5-closeout.md, D-RELEASE).
//
// The reference is a byte copy of .aai/scripts/aai-release.ps1 (blob 1c910b53) at commit 0ff18d63, kept outside .aai/ so it is
// never vendored. Its param block binds the PowerShell flags itself, so it is the oracle for the new thin launcher.
//
// Removal is allowed only for a directory this module created: createOwnScratch makes it with the own prefix and a marker
// file holding the creating process id; removeOwnScratch refuses everything else and re-reads the marker right before the removal.

import { createHash } from 'node:crypto';
import {
  lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const REFERENCE_PS1 = 'tests/fixtures/aai-release-reference/aai-release.ps1';
export const REFERENCE_PS1_SHA256 = '453d2ffba770460eb5a9cc231968521d19a5b55725fb50962b73d53ff9c4dfdb';
export const REFERENCE_COMMIT = '0ff18d63';
export const OWN_MARKER_FILE = '.aai-rl-owned';
const OWN_SCRATCH_PREFIX = 'aai-rl-';

export const sha256File = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');

// createOwnScratch(label): a fresh directory under the temp directory with the own prefix and the marker.
export function createOwnScratch(label = '') {
  const dir = mkdtempSync(path.join(os.tmpdir(), `${OWN_SCRATCH_PREFIX}${label}`));
  writeFileSync(path.join(dir, OWN_MARKER_FILE), `${process.pid}\n`);
  return realpathSync(dir);
}

function refusal(dir, why) {
  return new Error(`removeOwnScratch refused ${JSON.stringify(dir)}: ${why}`);
}

const markerPid = (dir) => {
  try {
    return readFileSync(path.join(dir, OWN_MARKER_FILE), 'utf8').trim();
  } catch {
    return '';
  }
};

// removeOwnScratch(dir): removes dir only when it is an own marked scratch directory under the temp directory.
export function removeOwnScratch(dir) {
  if (typeof dir !== 'string' || dir === '') throw refusal(dir, 'empty path');
  if (!path.isAbsolute(dir)) throw refusal(dir, 'relative path');
  if (!path.basename(dir).startsWith(OWN_SCRATCH_PREFIX)) throw refusal(dir, 'basename lacks the own prefix');
  let st;
  try {
    st = lstatSync(dir);
  } catch {
    throw refusal(dir, 'does not exist');
  }
  if (st.isSymbolicLink() || !st.isDirectory()) throw refusal(dir, 'not a real directory');
  const real = realpathSync(dir);
  const tmp = realpathSync(os.tmpdir());
  if (real === tmp || !real.startsWith(tmp.endsWith(path.sep) ? tmp : tmp + path.sep)) throw refusal(dir, 'outside the temp directory');
  if (!/^[0-9]+$/.test(markerPid(real))) throw refusal(dir, `no ${OWN_MARKER_FILE} marker`);
  rmSync(real, { recursive: true, force: true });
}

// removeOwnScratchAll(dirs): an empty list is a hard failure, not a no-op.
export function removeOwnScratchAll(dirs) {
  if (!Array.isArray(dirs) || dirs.length === 0) throw new Error('removeOwnScratchAll refused: empty list of paths to remove');
  for (const dir of dirs) removeOwnScratch(dir);
}

// materializeReleaseReference(fromRoot, intoDir): verifies the reference hash, then writes it to <intoDir>/aai-release.ps1.
// Returns the written path. The caller copies the current aai-release.mjs and its imports beside it.
export function materializeReleaseReference(fromRoot, intoDir) {
  const src = path.join(fromRoot, REFERENCE_PS1);
  const got = sha256File(src);
  if (got !== REFERENCE_PS1_SHA256) throw new Error(`${src} hashes to ${got}, expected ${REFERENCE_PS1_SHA256} (the frozen release launcher reference was edited)`);
  mkdirSync(intoDir, { recursive: true });
  const dest = path.join(intoDir, 'aai-release.ps1');
  writeFileSync(dest, readFileSync(src));
  return dest;
}
