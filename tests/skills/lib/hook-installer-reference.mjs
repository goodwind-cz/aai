// hook-installer-reference.mjs - the frozen hook installer references and the scratch-safety helpers
// (docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md, D-REF and D-SAFETY).
//
// The two references are byte copies of .aai/scripts/install-pre-commit-hook.sh (blob 2d9e1626) and
// .aai/scripts/install-pre-commit-hook.ps1 (blob c46255f4) at commit bf0148d6, kept outside .aai/ so they are
// never vendored. Both twins read their hook templates from their own location, so
// materializeHookInstallerReference also writes the four current templates beside them.
//
// Removal is allowed only for a directory this module created: createOwnScratch makes it with the
// own prefix and a marker file holding the creating process id; removeOwnScratch refuses everything
// else and re-reads the marker right before the removal.

import { createHash } from 'node:crypto';
import {
  chmodSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export const REFERENCE_SH = 'tests/fixtures/hook-installer-reference/install-pre-commit-hook.sh';
export const REFERENCE_PS1 = 'tests/fixtures/hook-installer-reference/install-pre-commit-hook.ps1';
export const REFERENCE_SH_SHA256 = '140b17eb636eff8c7ae13d04166e46be589fd7aef3e3a983b2b0fa018684d5ff';
export const REFERENCE_PS1_SHA256 = 'b8c8697a969a123277afdb21933f5a9f6c93041b1f449716c20f9a1ddbb6e28b';
export const REFERENCE_COMMIT = 'bf0148d6';
export const OWN_MARKER_FILE = '.aai-hk-owned';
const OWN_SCRATCH_PREFIX = 'aai-hk-';
const TEMPLATES_REL = path.join('.aai', 'templates', 'git-hooks');

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

// materializeHookInstallerReference(fromRoot, intoRoot): verifies both references, then writes them to
// <intoRoot>/.aai/scripts/ (install-pre-commit-hook.sh with mode 0755, the .ps1 with 0644) and the four current
// templates from <fromRoot>/.aai/templates/git-hooks/ to <intoRoot>/.aai/templates/git-hooks/. Returns both paths.
export function materializeHookInstallerReference(fromRoot, intoRoot) {
  const pairs = [[REFERENCE_SH, REFERENCE_SH_SHA256, 0o755], [REFERENCE_PS1, REFERENCE_PS1_SHA256, 0o644]];
  for (const [rel, want] of pairs) {
    const src = path.join(fromRoot, rel);
    const got = sha256File(src);
    if (got !== want) throw new Error(`${src} hashes to ${got}, expected ${want} (the frozen hook installer reference was edited)`);
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
  const tplFrom = path.join(fromRoot, TEMPLATES_REL);
  const tplInto = path.join(intoRoot, TEMPLATES_REL);
  mkdirSync(tplInto, { recursive: true });
  for (const name of readdirSync(tplFrom)) writeFileSync(path.join(tplInto, name), readFileSync(path.join(tplFrom, name)));
  return dests;
}
