# SKILL_MERGE — directed merge and safe post-merge cleanup (`/aai-merge <PR>`)

The engine `.aai/scripts/merge-cleanup.mjs` owns every rule; this prompt only
sequences it. Input: the PR number (ask once if absent, then stop). Exit codes:
0 complete (kept items included), 2 usage, 3 refused (`REFUSE <reason>`), 4 stopped
(re-run resumes), 6 a decision waits, 10 preflight ready. Each classified item also
prints one `OUTCOME <json>` line.

1. OPEN PR — merge only on the human's explicit `/aai-merge <n>` naming that
   PR in this session. Judged head = the sha the owner named, else the PR's
   current `headRefOid`. From the ride checkout run
   `node .aai/scripts/merge-cleanup.mjs preflight --pr <n> --expect-head <sha> --directed-by human --direction "<owner's words verbatim>" --origin "$(pwd)"`.
   Relay a `cleanup blocked:` line verbatim; it does not stop the merge.
   Exit 10: run exactly the one `AAI_OPERATOR_MERGE=1 gh pr merge <n> --squash --match-head-commit <sha>` line it
   printed, nothing added (never `--admin`, `--auto`, `--delete-branch`).
   On Azure DevOps that line is `node "<engineDir>/platform.mjs" merge --pr <n> --expect-head <sha> --operator-merge`;
   run it the same way. A `platform_mismatch` or `platform_generic` REFUSE is relayed with its command and the run stops. Exit 4 (completion_pending) stops: re-run `/aai-merge <n>`. Exit 5 (head_race_lost) stops: skip step 2, never treat the direction as covering a head it did not name. Other refusals print `platform: <reason>`.
   Exit 3: route its `OUTCOME` lines as in step 2; `direct_new_head` runs this preflight again with the new head
   as `--expect-head` and the owner's menu answer as `--direction`, `stop` ends the run. Exit 0 `already_merged`: go to 2.
2. MERGED PR — cleanup only. Run the block for your shell with `AAI_PR` set to
   the PR number and, when step 1 merged it, `AAI_DIRECTION` to the owner's
   words. It proves MERGED and
   the merge commit on the base first; it archives before it removes, never
   stashes, and deletes the merged remote branch only by lease against the
   merged head (else retained). Run the block
   as the command itself, never through `bash -c`, `sh -c` or `eval` (a
   wrapped script cannot be checked and is refused):

   ```bash
   # AAI_MERGE_BEGIN
   [[ "${AAI_PR:-}" =~ ^[1-9][0-9]*$ ]] || { echo "AAI_PR must be the PR number" >&2; exit 2; }
   AAI_ORIGIN="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
   [[ -n "$AAI_ORIGIN" && "$AAI_ORIGIN" = /* && -d "$AAI_ORIGIN" ]] || { echo "origin checkout not found" >&2; exit 1; }
   cd "$AAI_ORIGIN"
   set --; [[ -z "${AAI_DIRECTION:-}" ]] || set -- --direction "$AAI_DIRECTION"
   [[ -z "${AAI_DECIDE:-}" ]] || set -- "$@" --decide "$AAI_DECIDE"
   AAI_GIT_WRITE=1 node "$AAI_ORIGIN/.aai/scripts/merge-cleanup.mjs" apply --pr "$AAI_PR" --pid "$PPID" --origin "$AAI_ORIGIN" "$@"
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
   $AaiDec = @(); if ($env:AAI_DECIDE) { $AaiDec = @('--decide', $env:AAI_DECIDE) }
   $env:AAI_GIT_WRITE = '1'
   & node (Join-Path $AaiOrigin '.aai/scripts/merge-cleanup.mjs') apply --pr $env:AAI_PR --pid $AaiPid --origin $AaiOrigin @AaiDir @AaiDec
   $AaiRc = $LASTEXITCODE
   $env:AAI_GIT_WRITE = $null
   if ($AaiRc -ne 0) { throw "merge-cleanup apply exited $AaiRc" }
   # AAI_MERGE_PS_END
   ```

   Read every `OUTCOME` line and route it. State `retry`: run the same block again now, no question (the engine
   bounds the retries). Class `decide`: ask one menu for all pending items (each with its options and effects, the
   recommended first), then run the block with `AAI_DECIDE` set to the chosen `id=option` pairs. Class `external`:
   relay its `action` verbatim and stop. State `resolved`: nothing to do. While a `retry` line is present the
   menu waits, so it is asked once; never finish a step by hand (no `git worktree remove --force`, branch
   delete or `git submodule deinit`).

3. Relay the `Merge:`, `Cleanup:`, `Kept:`, `Decision:` and `Needs you:` lines verbatim. A kept (retained)
   remote branch is relayed with its reason and the agent never deletes it.

Hard rules: no standing authorization — one invocation, one PR, one head.
`/aai-ship` and the loop never invoke this skill. Never `git stash`, `reset`,
`restore`, `clean`, `branch -D`, `push --delete`, `worktree remove --force` or `worktree prune`.
