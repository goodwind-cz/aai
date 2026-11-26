---
id: azure-rejects-doc-number-reservation-push
type: product
capability: azure-rejects-doc-number-reservation-push
status: current
delivered_by:
  - azure-rejects-doc-number-reservation-push
spec: docs/specs/SPEC-DRAFT-spec-azure-rejects-doc-number-reservation-push.md
updated: 2026-11-26
---

# Doc-number reservation on Azure Repos

## What it does

Projects hosted on Azure Repos can number their documents again. The
allocator reserves each display number in `origin` before it renames a draft,
and until now it always did that with an atomic push, which Azure Repos does
not support: every doc stayed provisional and the merge guard blocked the pull
request. When the project's platform is Azure, the allocator now reserves
with plain create-only pushes, one per reserved ref, so two clones still
cannot take the same number. A refusal for any other reason now shows the
remote's own message instead of the git-lfs advisory that used to appear
first.

## How to use it

Nothing to configure for an origin on `dev.azure.com`, `ssh.dev.azure.com` or
`*.visualstudio.com`. For an Azure DevOps Server on its own hostname, record
the platform once:

```yaml
# docs/ai/pr-config.yaml
platform: azure
```

A doc already stamped `number_reserved: false` by the old failure completes
with:

```bash
node .aai/scripts/allocate-doc-number.mjs --reserve --path docs/issues/CHANGE-0042-my-topic.md
```

## Data model

None. The reservation refs keep their name, `refs/aai/docnums/<TYPE>-<NNNN>`,
and the provisional marker keeps its meaning.

## Interfaces and contracts

- `allocate-doc-number.mjs` (allocation and `--reserve`): on Azure, one
  `git push --force-with-lease=<ref>: origin <reservation-commit>:<ref>` per
  ref, in sorted ref order, without `--atomic`. Exit codes are unchanged.
- Coupled families on Azure: when a later member collides, the refs already
  claimed in that attempt are deleted with
  `git push --force-with-lease=<ref>:<reservation-commit> origin :<ref>` and
  the family retries at the next number; a failed delete is named in the
  warning.
- Warning text on Azure: the remote's lines verbatim, git-lfs locking advisory
  lines replaced by `(git-lfs locking advisory omitted: it is not the
  rejection reason)`, URL credentials masked.
- Platform choice: `docs/ai/pr-config.yaml` `platform:` first, else the origin
  URL. GitHub and every other platform keep the existing transport.

## Limits and non-goals

- Not verified against a live Azure Repos server: the tests use a local server
  that refuses atomic push the same way. That Azure accepts refs under
  `refs/aai/` and lets the pusher delete its own reservation ref is assumed;
  if it does not, the warning now shows Azure's own reason.
- A process killed between claiming and releasing a coupled member leaves one
  reservation ref behind; that number is skipped, nothing else breaks.
- Other servers without atomic push keep today's behaviour unless they record
  `platform: azure`.

## Links

- Request: docs/issues/ISSUE-DRAFT-azure-rejects-doc-number-reservation-push.md
- Spec: docs/specs/SPEC-DRAFT-spec-azure-rejects-doc-number-reservation-push.md
