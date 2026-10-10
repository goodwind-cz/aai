# SKILL_MERGE — directed merge and safe post-merge cleanup (`/aai-merge <PR>`)

The engine `.aai/scripts/merge-cleanup.mjs` owns every rule; this prompt only
sequences it. Input: the PR number (ask once if absent, then stop). Exit codes:
0 complete, 2 usage, 3 refused (`REFUSE <reason>`, nothing written), 4 stopped
(re-run resumes), 10 preflight ready.

1. OPEN PR — merge only on the human's explicit `/aai-merge <n>` naming that
   PR in this session. Judged head = the sha the owner named, else the PR's
   current `headRefOid`. From the ride checkout run
   `node .aai/scripts/merge-cleanup.mjs preflight --pr <n> --expect-head <sha> --directed-by human --direction "<owner's words verbatim>" --origin "$(pwd)"`.
   Exit 10: run exactly the one `AAI_OPERATOR_MERGE=1 gh pr merge <n> --squash --match-head-commit <sha>` line it
   printed, nothing added (never `--admin`, `--auto`, `--delete-branch`).
   Exit 3: relay the `REFUSE` line and stop. Exit 0 `already_merged`: go to 2.
2. MERGED PR — cleanup only. Run the block for your shell with `AAI_PR` set to
   the PR number and, when step 1 merged it, `AAI_DIRECTION` to the owner's
   words (the engine records them with the merged head). It proves MERGED and
   the merge commit on the base first; it archives before it removes, never
   forces, never stashes:

   ```bash
   # AAI_MERGE_BEGIN
   [[ "${AAI_PR:-}" =~ ^[1-9][0-9]*$ ]] || { echo "AAI_PR must be the PR number" >&2; exit 2; }
   AAI_ORIGIN="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
   [[ -n "$AAI_ORIGIN" && "$AAI_ORIGIN" = /* && -d "$AAI_ORIGIN" ]] || { echo "origin checkout not found" >&2; exit 1; }
   cd "$AAI_ORIGIN"
   AAI_GIT_WRITE=1 node "$AAI_ORIGIN/.aai/scripts/merge-cleanup.mjs" apply --pr "$AAI_PR" --pid "$PPID" --origin "$AAI_ORIGIN" ${AAI_DIRECTION:+--direction "$AAI_DIRECTION"}
   # AAI_MERGE_END
   ```

   ```powershell
   # AAI_MERGE_PS_BEGIN
   if ($env:AAI_PR -notmatch '^[1-9][0-9]*$') { throw 'AAI_PR must be the PR number' }
   $AaiOrigin = ((& git worktree list --porcelain | Select-Object -First 1) -replace '^worktree ', '')
   if (-not $AaiOrigin -or -not (Test-Path -LiteralPath $AaiOrigin)) { throw 'origin checkout not found' }
   Set-Location -LiteralPath $AaiOrigin
   $AaiPid = $PID
   try { $p = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId; if ($p) { $AaiPid = $p } } catch { try { $p = (Get-Process -Id $PID).Parent.Id; if ($p) { $AaiPid = $p } } catch { } }
   $AaiDir = @(); if ($env:AAI_DIRECTION) { $AaiDir = @('--direction', $env:AAI_DIRECTION) }
   $env:AAI_GIT_WRITE = '1'
   & node (Join-Path $AaiOrigin '.aai/scripts/merge-cleanup.mjs') apply --pr $env:AAI_PR --pid $AaiPid --origin $AaiOrigin @AaiDir
   $AaiRc = $LASTEXITCODE
   Remove-Item Env:AAI_GIT_WRITE
   if ($AaiRc -ne 0) { throw "merge-cleanup apply exited $AaiRc" }
   # AAI_MERGE_PS_END
   ```

3. Report the engine's report: base, final HEAD, archived, retained with
   reasons, no-ops, `remaining`. Owner actions stay with the owner: remote
   branch deletion and divergent drafts (re-run `apply` with
   `--archive-divergent <path>` once the owner names the file).

Hard rules: no standing authorization — one invocation, one PR, one head.
`/aai-ship` and the loop never invoke this skill. Never `git stash`, `reset`,
`restore`, `clean`, `branch -D`, `worktree remove --force` or `worktree prune`.
