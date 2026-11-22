// sync-reference.mjs - the frozen layer sync references and the scratch-safety helpers
// (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, D-REF and D-SAFETY).
//
// The three references are byte copies of .aai/scripts/aai-sync.sh (blob f42b62ca), .aai/scripts/aai-sync.ps1
// (blob d7ab810f) and .aai/scripts/lib/gitignore-block.sh (blob 8402ac80) at commit 077ee649, kept outside .aai/
// so they are never vendored. Both twins take their source from their own location, so
// materializeSyncReference writes them (and the bash library) into a scratch source tree and removes the
// module-side engine files there.
//
// Removal is allowed only for a directory this module created: createOwnScratch makes it with the
// own prefix and a marker file holding the creating process id; removeOwnScratch refuses everything
// else and re-reads the marker right before the removal (the SPEC-0306 D-SAFETY rules).

import { createHash } from 'node:crypto';
import {
  chmodSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REFERENCE_SH = 'tests/fixtures/sync-reference/aai-sync.sh';
export const REFERENCE_PS1 = 'tests/fixtures/sync-reference/aai-sync.ps1';
export const REFERENCE_LIB = 'tests/fixtures/sync-reference/gitignore-block.sh';
export const REFERENCE_SH_SHA256 = '00aac687f306439cec14ef50a2a48ea0511fb95d9b0c6590ca1c7afc1eea4c06';
export const REFERENCE_PS1_SHA256 = '038a640a45142866505669266cb42b05652cc59bb0279a0c7479f729df4c3acd';
export const REFERENCE_LIB_SHA256 = '5544c8395b5b8ae956a8ffcedafb4bf7e93d1e6171540f0c1a82f81ecee3e7d1';
export const REFERENCE_COMMIT = '077ee649';
// The files the frozen twins consist of, as target-relative .aai paths, and the files of the module side.
export const ENGINE_FILES_REFERENCE = [
  '.aai/scripts/aai-sync.sh',
  '.aai/scripts/aai-sync.ps1',
  '.aai/scripts/lib/gitignore-block.sh',
];
export const ENGINE_FILES_MODULE = [
  '.aai/scripts/aai-sync.sh',
  '.aai/scripts/aai-sync.ps1',
  '.aai/scripts/aai-sync.mjs',
  '.aai/scripts/lib/resolve-base.mjs',
  '.aai/scripts/lib/gitignore-block.mjs',
];
export const OWN_MARKER_FILE = '.aai-sy-owned';
const OWN_SCRATCH_PREFIX = 'aai-sy-';
const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

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

// materializeSyncReference(sourceRoot): verifies the three references, then writes the two twins over
// <sourceRoot>/.aai/scripts/aai-sync.{sh,ps1} (modes 0755 and 0644) and the library at
// <sourceRoot>/.aai/scripts/lib/gitignore-block.sh, and removes the module-side engine files of that tree (the
// module and the two shared libs). sourceRoot must be an absolute path other than this checkout, because a
// removal happens there. Returns the three written paths.
export function materializeSyncReference(sourceRoot) {
  if (typeof sourceRoot !== 'string' || !path.isAbsolute(sourceRoot)) throw new Error(`materializeSyncReference refused ${JSON.stringify(sourceRoot)}: not an absolute path`);
  if (path.resolve(sourceRoot) === REPO_ROOT || realpathSync(sourceRoot) === realpathSync(REPO_ROOT)) throw new Error('materializeSyncReference refused: the source root is this checkout');
  const parts = [
    [REFERENCE_SH, REFERENCE_SH_SHA256, 0o755, ENGINE_FILES_REFERENCE[0]],
    [REFERENCE_PS1, REFERENCE_PS1_SHA256, 0o644, ENGINE_FILES_REFERENCE[1]],
    [REFERENCE_LIB, REFERENCE_LIB_SHA256, 0o644, ENGINE_FILES_REFERENCE[2]],
  ];
  for (const [rel, want] of parts) {
    const src = path.join(REPO_ROOT, rel);
    const got = sha256File(src);
    if (got !== want) throw new Error(`${src} hashes to ${got}, expected ${want} (the frozen sync reference was edited)`);
  }
  for (const rel of ENGINE_FILES_MODULE) {
    const file = path.join(sourceRoot, rel);
    let st = null;
    try {
      st = lstatSync(file);
    } catch {
      st = null;
    }
    if (st && !st.isDirectory()) rmSync(file, { force: true });
  }
  const dests = [];
  for (const [rel, , mode, into] of parts) {
    const dest = path.join(sourceRoot, into);
    mkdirSync(path.dirname(dest), { recursive: true });
    writeFileSync(dest, readFileSync(path.join(REPO_ROOT, rel)));
    chmodSync(dest, mode);
    dests.push(dest);
  }
  return { sh: dests[0], ps1: dests[1], lib: dests[2] };
}
