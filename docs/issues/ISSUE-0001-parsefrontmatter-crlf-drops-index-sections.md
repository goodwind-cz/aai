---
id: ISSUE-0001
type: issue
status: done
links:
  pr: []
  commits: []
---

# Issue: parseFrontmatter is LF-only — CRLF checkouts route every doc to Legacy and corrupt docs/INDEX.md

## Summary
On a CRLF checkout (Windows, or any repo with `core.autocrlf=true` / `*text=auto`),
`parseFrontmatter()` returns `null` for EVERY document, so `generate-docs-index.mjs`
buckets all docs as `legacy`. The result is a corrupted `docs/INDEX.md`: every
meaningful section (Active / Done / Drafts / Deferred / Blocked / Rejected-Superseded)
renders `(0)` / `_None._` and the entire corpus dumps into "## Legacy (no frontmatter)".

## Type
- bug

## Impact
- Who/what is affected? Any Windows / `core.autocrlf=true` contributor who regenerates
  the docs index. The whole `docs/INDEX.md` is silently corrupted and, if committed,
  poisons the shared index for everyone (operator reported 464 docs in Legacy, 0 in
  every real section, backslash paths, and git merge-conflict markers around the
  `Generated:` line).
- Severity/priority: **High** — silent data loss in a committed, shared artifact; no
  error, no non-zero exit. The generator logic itself is correct; only the line-ending
  assumption is wrong (the same generator on macOS/LF produces the correct index:
  Active 6, Done 439, Drafts 12, Deferred 5, Blocked 4, Rejected/Superseded 11, Legacy 1).

## Current Behavior
- `.aai/scripts/lib/docs-model.mjs:145-146`:
  ```js
  export function parseFrontmatter(content) {
    if (!content.startsWith('---\n')) return null;   // CRLF doc starts with '---\r\n'
  ```
  hard-codes LF. On CRLF every doc starts with `'---\r\n'`, so `startsWith('---\n')`
  is false → returns `null`. The frontmatter block split on `'\n'` also leaves a
  trailing `\r` on every value.
- `.aai/scripts/generate-docs-index.mjs:102,108`: a `null` frontmatter routes the doc
  to the Legacy bucket (`status: 'legacy', legacy: true`), and `rel` is taken straight
  from `path.relative(ROOT, filePath)` — which yields backslash paths on win32, making
  the artifact OS-dependent and merge-conflict-prone.

## Expected Behavior
- `parseFrontmatter()` parses frontmatter identically for LF, CRLF, and lone-CR inputs,
  so the index buckets docs by their real status regardless of checkout line endings.
- `docs/INDEX.md` is byte-identical across OSes: forward-slash (POSIX) paths only, no
  OS-specific separators.

## Steps to Reproduce (if applicable)
1) ```js
   import { parseFrontmatter } from './.aai/scripts/lib/docs-model.mjs';
   const lf   = "---\nid: X\nstatus: done\n---\n# t\n";
   const crlf = lf.replace(/\n/g, "\r\n");
   parseFrontmatter(lf);    // => { id:'X', status:'done' }
   parseFrontmatter(crlf);  // => null   <-- BUG
   ```
2) On a CRLF checkout, run `node .aai/scripts/generate-docs-index.mjs` → `docs/INDEX.md`
   shows all sections empty and the whole corpus under "Legacy (no frontmatter)".

## Verification
- Unit: `parseFrontmatter` returns the same parsed object for the LF, CRLF, and lone-CR
  variants of an identical doc (RED before fix on the CRLF/CR variants, GREEN after).
- Generator: a fixture corpus written with CRLF produces the SAME `docs/INDEX.md`
  (modulo the `Generated:` line) as the LF corpus — correct section counts, ≤1 Legacy,
  POSIX paths only, no backslashes.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0 CLEAN; index
  idempotent.

## Constraints / Risks
- Normalize line endings at parser entry only (do not mutate files on disk).
- Apply the same normalization consistently across `parseFrontmatter`, `parseAcTable`,
  `parseReviewBy`, and `extractReferences` (or normalize once before handing content to
  any parser) so AC tables / Review-By / references don't carry trailing `\r`.
- POSIX-path normalization must not break existing LF/macOS output (paths already use
  `/` there) — `split(path.sep).join('/')` is a no-op on POSIX.

## Notes
Proposed fix (from the operator report):

- **FIX 1 (primary, required)** — CRLF-tolerant parse. Normalize once at entry:
  ```js
  export function parseFrontmatter(content) {
    content = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n'); // CRLF + lone-CR
    if (!content.startsWith('---\n')) return null;
    ...
  }
  ```
  Mirror the normalization in `parseAcTable` / `parseReviewBy` / `extractReferences`.
- **FIX 2 (secondary)** — emit OS-independent paths. Wherever a path is pushed into a
  record/table row in `generate-docs-index.mjs`:
  ```js
  const rel = path.relative(ROOT, filePath).split(path.sep).join('/');
  ```

Guardrails:
1. Unit test for `parseFrontmatter` with CRLF and lone-CR fixtures (a single assertion
   would have caught this).
2. Extend `.gitattributes` — it currently covers `*.sh/*.bash/*.ps1` (eol=lf) and
   `*.bat/*.cmd` (eol=crlf) but NOT the docs corpus or the scripts that read it. Add:
   ```
   docs/**/*.md text eol=lf
   *.mjs        text eol=lf
   ```
   so the corpus is LF regardless of `autocrlf`. Recommend the same in target repos /
   the vendored AAI payload.
3. Optional defense-in-depth: have `generate-docs-index.mjs` warn loudly (and/or exit
   non-zero) when the Legacy bucket exceeds ~50% of scanned docs — an all-legacy index
   is almost always a parser failure, not a real corpus state, and must not be committed
   silently. Pairs naturally with SPEC-0006's zero-section coverage invariant.

Related: SPEC-0006 / DEBT-0001 (docs index integrity & coverage invariants).
