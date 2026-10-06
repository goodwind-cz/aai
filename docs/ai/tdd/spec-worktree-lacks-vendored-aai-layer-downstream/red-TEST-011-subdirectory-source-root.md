# RED — TEST-011 subdirectory source root

- Finding: PR #433 inline review comment `4199660652`
- Command: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-worktree-seed.sh --test TEST-011`
- Exit: `1`
- Observed: `FAIL: TEST-011 Bash setup from a subdirectory resolved source as .../installed source/nested/setup-directory`
- Expected: both documented shell forms resolve the installed source from `git rev-parse --show-toplevel`, independent of the caller's current repository subdirectory.
- Run at: 2026-10-06T20:05:44Z

The isolated wrapper reported both `AAI-ISOLATION: isolated` and
`AAI-SEEDING: seeded`; the failure occurred against the current shipping-tree
overlay before the production prompt was changed.
