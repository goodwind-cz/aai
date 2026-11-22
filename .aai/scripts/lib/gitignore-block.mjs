// gitignore-block.mjs - the .gitignore reconcile of the layer sync
// (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, D-GITIGNORE).
//
// SKELETON (run 1 of the ride): the marker prefix constant and the export the sync module imports exist so the
// module loads; the reconcile itself is ported in run 2 (TEST-4005). Until then it refuses instead of guessing.

export const AAI_GITIGNORE_MARKER_PREFIX = '# AAI runtime sidecars';

export function reconcileGitignore() {
  throw new Error('reconcileGitignore is not implemented yet (run 2 of the ride)');
}
