// bootstrap-reference.mjs - the frozen bash bootstrap reference and the scratch-safety helpers
// (docs/specs/SPEC-0306-spec-bootstrap-on-node.md, D-REF and D-SAFETY).
//
// The reference is a byte copy of blob b41a0c02 of .aai/scripts/aai-bootstrap.sh, kept outside .aai/
// so it is never vendored. materializeBootstrapReference puts it into a scratch tree beside a copy of
// the .aai tree, so the reference finds the siblings it found in place.
//
// Removal is allowed only for a directory this module created: createOwnScratch makes it with the
// own prefix and a marker file holding the creating process id; removeOwnScratch refuses everything
// else and re-reads the marker right before the removal.

import { createHash } from 'node:crypto';
import {
  chmodSync, cpSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const REFERENCE_PATH = 'tests/fixtures/aai-bootstrap-reference/aai-bootstrap.sh';
export const REFERENCE_SHA256 = '19055401a8854ead8233d75a8b788851a5535d4d95fd7aff31fa14b56bf661c0';
export const REFERENCE_BLOB = 'b41a0c02';
export const REFERENCE_COMMIT = '34fad51b';
export const GITIGNORE_LIB_REFERENCE_PATH = 'tests/fixtures/sync-reference/gitignore-block.sh';
export const GITIGNORE_LIB_REFERENCE_SHA256 = '5544c8395b5b8ae956a8ffcedafb4bf7e93d1e6171540f0c1a82f81ecee3e7d1';
export const OWN_MARKER_FILE = '.aai-bs-owned';
const OWN_SCRATCH_PREFIX = 'aai-bs-';

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
  // Re-read right before the removal: the marker must still be there.
  if (!/^[0-9]+$/.test(markerPid(real))) throw refusal(dir, `${OWN_MARKER_FILE} marker vanished`);
  rmSync(real, { recursive: true, force: true });
}

// removeOwnScratchAll(dirs): an empty list is a hard failure, not a no-op.
export function removeOwnScratchAll(dirs) {
  if (!Array.isArray(dirs) || dirs.length === 0) throw new Error('removeOwnScratchAll refused: empty list of paths to remove');
  for (const dir of dirs) removeOwnScratch(dir);
}

// materializeBootstrapReference(fromRoot, intoRoot): verifies the reference, copies <fromRoot>/.aai to
// <intoRoot>/.aai, then writes the reference over <intoRoot>/.aai/scripts/aai-bootstrap.sh with mode 0755.
export function materializeBootstrapReference(fromRoot, intoRoot) {
  const src = path.join(fromRoot, REFERENCE_PATH);
  const got = sha256File(src);
  if (got !== REFERENCE_SHA256) {
    throw new Error(`${src} hashes to ${got}, expected ${REFERENCE_SHA256} (the frozen bootstrap reference was edited)`);
  }
  mkdirSync(intoRoot, { recursive: true });
  cpSync(path.join(fromRoot, '.aai'), path.join(intoRoot, '.aai'), { recursive: true });
  const dest = path.join(intoRoot, '.aai', 'scripts', 'aai-bootstrap.sh');
  mkdirSync(path.dirname(dest), { recursive: true });
  writeFileSync(dest, readFileSync(src));
  chmodSync(dest, 0o755);
  // The shipped bash library is gone (sync-on-node run 6): the reference sources the frozen copy of it, which this
  // writes beside the reference, verified against the sync reference's pin.
  const lib = path.join(fromRoot, GITIGNORE_LIB_REFERENCE_PATH);
  const libGot = sha256File(lib);
  if (libGot !== GITIGNORE_LIB_REFERENCE_SHA256) {
    throw new Error(`${lib} hashes to ${libGot}, expected ${GITIGNORE_LIB_REFERENCE_SHA256} (the frozen library was edited)`);
  }
  const libDest = path.join(intoRoot, '.aai', 'scripts', 'lib', 'gitignore-block.sh');
  mkdirSync(path.dirname(libDest), { recursive: true });
  writeFileSync(libDest, readFileSync(lib));
  chmodSync(libDest, 0o644);
  return dest;
}
