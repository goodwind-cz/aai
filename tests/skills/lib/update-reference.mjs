// update-reference.mjs - the frozen updater references and the scratch-safety helpers
// (docs/specs/SPEC-0307-spec-update-on-node.md, D-REF and D-SAFETY).
//
// The two references are byte copies of .aai/scripts/aai-update.sh (blob 6922cbbf) and
// .aai/scripts/aai-update.ps1 (blob 3d4134e9) at commit 30c983ef, kept outside .aai/ so they are never
// vendored. Neither twin sources a sibling file, so materializeUpdateReference writes only the two files.
//
// Removal is allowed only for a directory this module created: createOwnScratch makes it with the
// own prefix and a marker file holding the creating process id; removeOwnScratch refuses everything
// else and re-reads the marker right before the removal.

import { createHash } from 'node:crypto';
import {
  chmodSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const REFERENCE_SH = 'tests/fixtures/aai-update-reference/aai-update.sh';
export const REFERENCE_PS1 = 'tests/fixtures/aai-update-reference/aai-update.ps1';
export const REFERENCE_SH_SHA256 = '5f5cb9eedd6b1453d57afc0a2b8d09c7804ce7d7086b9b754a6d13d5c21110d5';
export const REFERENCE_PS1_SHA256 = '136c3d35a6f35385ad4d9b6b00989d37a557622e8a4b5a925b1b7b17867e9dd4';
export const REFERENCE_COMMIT = '30c983ef';
export const OWN_MARKER_FILE = '.aai-up-owned';
const OWN_SCRATCH_PREFIX = 'aai-up-';

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

// materializeUpdateReference(fromRoot, intoRoot): verifies both references, then writes them to
// <intoRoot>/.aai/scripts/ (aai-update.sh with mode 0755, aai-update.ps1 with 0644). Returns both paths.
export function materializeUpdateReference(fromRoot, intoRoot) {
  const pairs = [[REFERENCE_SH, REFERENCE_SH_SHA256, 0o755], [REFERENCE_PS1, REFERENCE_PS1_SHA256, 0o644]];
  for (const [rel, want] of pairs) {
    const src = path.join(fromRoot, rel);
    const got = sha256File(src);
    if (got !== want) throw new Error(`${src} hashes to ${got}, expected ${want} (the frozen updater reference was edited)`);
  }
  const dir = path.join(intoRoot, '.aai', 'scripts');
  mkdirSync(dir, { recursive: true });
  const dests = {};
  for (const [rel, , mode] of pairs) {
    const dest = path.join(dir, path.basename(rel));
    writeFileSync(dest, readFileSync(path.join(fromRoot, rel)));
    chmodSync(dest, mode);
    dests[path.extname(rel) === '.sh' ? 'sh' : 'ps1'] = dest;
  }
  return dests;
}
