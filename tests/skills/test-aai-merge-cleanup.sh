#!/usr/bin/env bash
# /aai-merge engine tests (spec-directed-merge-and-post-merge-cleanup).
# Every fixture lives under ONE private absolute scratch root; every git call
# in a fixture carries its own identity; gh is a deny-by-default stub.
# B1: TEST-005 (apply read-back gate), TEST-006/007 (drafts).
# B2: TEST-008/009 (base sync), TEST-010/011 (worktree and branch cleanup).
# B3: TEST-012 (focus, index, report), TEST-013/014 (idempotence and resume).
# B4a: TEST-003/004 (open-PR preflight), TEST-015 (downstream installed layout).
# B4b: TEST-001/002 (prompt, wrappers, executed block), TEST-017 (companion wiring).
# spec-merge-direction-signs-amendments A: TEST-018/020/021 (the sign-amendments step).
# spec-merge-direction-signs-amendments B: TEST-022 (trackers, idempotence, resume), TEST-023 (preflight), TEST-019 (downstream).
# spec-merge-direction-signs-amendments C: TEST-025 (sign-merged backlog), TEST-024 (canon), TEST-026 (live ledger, RED until V3).
# spec-merge-direction-signs-amendments PFA-8: TEST-027 (the signature cites the current direction).
# spec-merge-cleanup-submodule-worktree B: TEST-031 (ignored content), TEST-032 (late dirt), TEST-033 (preflight), TEST-034 (canon).
# spec-merge-cleanup-delete-remote-branch: TEST-036..042 (delete-remote-branch step; TEST-002/010/012/013/014 amended).
# spec-merge-cleanup-ride-leftovers: TEST-045/046 (ride roadmap entry), TEST-047/048 (ride ledger appends), TEST-049/050 (engine reload), TEST-051/052 (tail resume key, re-exec child exit).
# spec-git-platform-detected-at-bootstrap C: TEST-068, TEST-070, TEST-072, TEST-073, TEST-074 (merge-cleanup on the platform adapter).
# spec-merge-cleanup-submodule-worktree A: TEST-028 (removal after the proof), TEST-029 (dirty refused), TEST-030 (unpushed, stash, no remote, stray module refused).
set -euo pipefail

case "$0" in /*) HERE="${0%/*}" ;; */*) HERE="$PWD/${0%/*}" ;; *) HERE="$PWD" ;; esac
ROOT="$HERE/../.."
ENGINE="$ROOT/.aai/scripts/merge-cleanup.mjs"
DOCS_AUDIT="$ROOT/.aai/scripts/docs-audit.mjs"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/aai-merge-cleanup.XXXXXX")"
[[ -n "$SCRATCH" && "$SCRATCH" = /* && -d "$SCRATCH" ]] || { echo 'FAIL: SETUP scratch root not absolute' >&2; exit 1; }

SCRATCH="$(node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' "$SCRATCH")" || { echo 'FAIL: SETUP scratch root not resolvable' >&2; exit 1; }

SELECTED=""
if [[ $# -ne 0 ]]; then
  if [[ $# -eq 2 && "$1" == "--test" ]]; then SELECTED="$2"
  elif [[ $# -eq 1 && ( "$1" == test_* || "$1" == TEST-* ) ]]; then SELECTED="$1"
  else echo 'Usage: test-aai-merge-cleanup.sh [--test TEST-xxx]' >&2; exit 2
  fi
fi

# Private git identity and no user/system config: a fixture never inherits the
# runner's identity, hooks or ref-guard settings.
export GIT_AUTHOR_NAME='AAI Fixture' GIT_AUTHOR_EMAIL='fixture@example.invalid'
export GIT_COMMITTER_NAME='AAI Fixture' GIT_COMMITTER_EMAIL='fixture@example.invalid'
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

HELPER_PIDS=()
stop_helper() { kill "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; }
cleanup() {
  local p
  for p in "${HELPER_PIDS[@]:-}"; do if [[ -n "$p" ]]; then stop_helper "$p"; fi; done
  [[ -n "${KEEP_TEST_DIR:-}" ]] || rm -rf "$SCRATCH"
}
trap cleanup EXIT

fail() { echo "FAIL: $1 $2" >&2; exit 1; }
run() { "$@" || fail SETUP "command failed: $*"; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
want() { has "$2" "$3" || fail "$1" "missing '$3' in: $2"; }
unwanted() { if has "$2" "$3"; then fail "$1" "unexpected '$3' in: $2"; fi; }

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}
sha_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1
  fi
}
json_get() { printf '%s' "$1" | node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));const v=eval(process.argv[1]);console.log(typeof v==="string"?v:JSON.stringify(v))' "$2"; }

# gh stub: deny-by-default. The ONLY accepted call is the engine's fixed read
# (`pr view <n> --json <exact field list>`) for a PR that has a fixture file;
# every call is logged, everything else prints STUB-DENY and exits 1.
write_gh_stub() {
  local d="$1"
  run mkdir -p "$d/bin"
  cat > "$d/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
dir="${GH_STUB_DIR:-}"
[ -n "$dir" ] && [ -d "$dir" ] || { echo 'STUB-DENY: GH_STUB_DIR unset' >&2; exit 1; }
printf '%s\n' "$*" >> "$dir/gh-argv.log"
fields='number,state,isDraft,headRefOid,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url,isCrossRepository'
if [ "$#" -eq 5 ] && [ "$1" = pr ] && [ "$2" = view ] && [ "$4" = --json ] && [ "$5" = "$fields" ]; then
  case "$3" in ''|*[!0-9]*) echo "STUB-DENY: pr number $3" >&2; exit 1 ;; esac
  if [ -f "$dir/pr-$3.json" ]; then cat "$dir/pr-$3.json"; exit 0; fi
fi
if [ "$#" -eq 10 ] && [ "$1" = pr ] && [ "$2" = list ] && [ "$3" = --state ] && [ "$4" = open ] && [ "$5" = --base ] && [ "$7" = --json ] && [ "$8" = number ] && [ "$9" = --limit ] && [ "${10}" = 100 ]; then
  [ -f "$dir/deps-fail" ] && { echo 'STUB: pr list failed' >&2; exit 1; }
  key="${6//\//_}"
  if [ -f "$dir/deps-$key.json" ]; then cat "$dir/deps-$key.json"; else echo '[]'; fi
  exit 0
fi
if [ "$#" -eq 10 ] && [ "$1" = pr ] && [ "$2" = list ] && [ "$3" = --state ] && [ "$4" = open ] && [ "$5" = --head ] && [ "$7" = --json ] && [ "$8" = number ] && [ "$9" = --limit ] && [ "${10}" = 100 ]; then
  [ -f "$dir/heads-fail" ] && { echo 'STUB: pr list --head failed' >&2; exit 1; }
  key="${6//\//_}"
  if [ -f "$dir/heads-$key.json" ]; then cat "$dir/heads-$key.json"; else echo '[]'; fi
  exit 0
fi
if [ "$1" = api ]; then
  [ -f "$dir/api-fail" ] && { echo 'STUB: api failed' >&2; exit 1; }
  if [ -f "$dir/review-threads.json" ]; then cat "$dir/review-threads.json"; exit 0; fi
  echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
  exit 0
fi
printf 'STUB-DENY: unexpected argv: %s\n' "$*" >&2
exit 1
GHSTUB
  run chmod +x "$d/bin/gh"
}

ISSUE_ID='foo'
SPEC_ID='spec-foo'
DRAFT_ISSUE='docs/issues/ISSUE-DRAFT-foo.md'
DRAFT_SPEC='docs/specs/SPEC-DRAFT-spec-foo.md'
NUM_ISSUE='docs/issues/ISSUE-0001-foo.md'
NUM_SPEC='docs/specs/SPEC-0001-spec-foo.md'

# install_core_layer: a downstream installation in ORIGIN. aai-sync.sh core
# puts .aai/ and the skill trees under .gitignore; everything else it writes is
# committed so the origin starts clean.
install_core_layer() {
  [[ -n "$ORIGIN" && "$ORIGIN" = /* && -d "$ORIGIN" ]] || fail SETUP 'install target'
  run bash "$ROOT/.aai/scripts/aai-sync.sh" "$ORIGIN" --profile core >"$W/sync.out" 2>&1
  run git -C "$ORIGIN" add -A
  run git -C "$ORIGIN" commit -qm 'install aai core'
  run git -C "$ORIGIN" push -q origin main
  run git -C "$ORIGIN" fetch -q origin
}

# build_world <name>: bare origin, origin checkout with untracked DRAFT copies,
# a ride worktree whose branch history holds the drafts and then the numbered
# docs, a squash commit on the bare main, and a MERGED PR fixture for gh.
build_world() {
  local name="$1" tree main0
  W="$SCRATCH/$name"
  [[ -n "$W" && "$W" = /* ]] || fail SETUP "world path not absolute: $W"
  ORIGIN="$W/origin"; BARE="$W/origin.git"; RIDE="$W/ride"; GHD="$W/gh"
  PR=433; BRANCH='ride/foo'
  run mkdir -p "$W"
  write_gh_stub "$GHD"
  : > "$GHD/gh-argv.log"
  run git init -q --bare -b main "$BARE"
  run git -C "$BARE" symbolic-ref HEAD refs/heads/main
  run git init -q -b main "$ORIGIN"
  run git -C "$ORIGIN" config user.name 'AAI Fixture'
  run git -C "$ORIGIN" config user.email 'fixture@example.invalid'
  run git -C "$ORIGIN" remote add origin "$BARE"
  printf 'fixture\n' > "$ORIGIN/README.md"
  printf 'unrelated\n' > "$ORIGIN/UNRELATED.txt"
  printf 'docs/ai/archive/**\ndocs/ai/reports/**\ndocs/ai/tdd/**\ndocs/ai/validation/**\ndocs/ai/reviews/**\ndocs/ai/evidence/**\ndocs/ai/STATE.yaml\n' > "$ORIGIN/.gitignore"
  run mkdir -p "$ORIGIN/docs/ai" "$ORIGIN/docs/issues" "$ORIGIN/docs/specs"
  printf '{"v":1,"ts":"2026-10-09T00:00:00Z","actor":"fixture","event":"seed","ref":"seed","payload":{}}\n' > "$ORIGIN/docs/ai/EVENTS.jsonl"
  printf '# Docs Index \xe2\x80\x94 auto-generated, DO NOT EDIT\n' > "$ORIGIN/docs/INDEX.md"
  run git -C "$ORIGIN" add README.md UNRELATED.txt .gitignore docs/ai/EVENTS.jsonl docs/INDEX.md
  # AMEND_WORLD: the decision ledger is tracked from the baseline on, as in a live repo
  if [[ -n "${AMEND_WORLD:-}" ]]; then
    : > "$ORIGIN/docs/ai/decisions.jsonl"
    run git -C "$ORIGIN" add docs/ai/decisions.jsonl
  fi
  if [[ -n "${EXTRA_OTHER:-}" ]]; then
    run mkdir -p "$ORIGIN/docs/issues"
    other_item_doc > "$ORIGIN/docs/issues/ISSUE-0002-other-item.md"
    run git -C "$ORIGIN" add docs/issues/ISSUE-0002-other-item.md
  fi
  # ROADMAP_WORLD / LEDGER_WORLD (spec-merge-cleanup-ride-leftovers): tracked roadmap and test-runs ledger
  if [[ -n "${ROADMAP_WORLD:-}" ]]; then
    roadmap_base > "$ORIGIN/docs/ai/roadmap.yaml"
    run git -C "$ORIGIN" add docs/ai/roadmap.yaml
  fi
  if [[ -n "${LEDGER_WORLD:-}" ]]; then
    run mkdir -p "$ORIGIN/docs/ai/tests"
    printf '{"v":1,"ts":"2026-10-09T00:00:00Z","actor":"fixture","event":"seed-run"}\n' > "$ORIGIN/docs/ai/tests/test-runs.jsonl"
    run git -C "$ORIGIN" add docs/ai/tests/test-runs.jsonl
  fi
  # BASELINE_SEED: a function that adds more tracked content (submodules) before the baseline commit
  if [[ -n "${BASELINE_SEED:-}" ]]; then "$BASELINE_SEED"; fi
  run git -C "$ORIGIN" commit -qm baseline
  run git -C "$ORIGIN" push -q origin main
  run git -C "$ORIGIN" fetch -q origin
  if [[ -n "${DOWNSTREAM:-}" ]]; then install_core_layer; fi
  # ENGINE_WORLD: the installed engine is tracked in the origin, so the merge can replace the very file the apply process runs from
  if [[ -n "${ENGINE_WORLD:-}" ]]; then
    run cp "$ENGINE" "$ORIGIN/.aai/scripts/merge-cleanup.mjs"
    run git -C "$ORIGIN" add -f .aai/scripts/merge-cleanup.mjs
    run git -C "$ORIGIN" commit -qm 'track the engine'
    run git -C "$ORIGIN" push -q origin main
    run git -C "$ORIGIN" fetch -q origin
  fi
  run git -C "$ORIGIN" worktree add -q -b "$BRANCH" "$RIDE" main
  run git -C "$RIDE" config user.name 'AAI Fixture'
  run git -C "$RIDE" config user.email 'fixture@example.invalid'
  if [[ -n "${DOWNSTREAM:-}" ]]; then run node "$ORIGIN/.aai/scripts/worktree-seed.mjs" --source "$ORIGIN" --target "$RIDE" >/dev/null; fi
  # RIDE_BOOT: a function that prepares the fresh ride checkout (initializes its submodules)
  if [[ -n "${RIDE_BOOT:-}" ]]; then "$RIDE_BOOT"; fi
  run mkdir -p "$RIDE/docs/issues" "$RIDE/docs/specs" "$RIDE/docs/ai"
  printf 'current_focus:\n  ref_id: foo\n' > "$RIDE/docs/ai/STATE.yaml"
  draft_issue_v1 > "$RIDE/$DRAFT_ISSUE"
  draft_spec_v1 > "$RIDE/$DRAFT_SPEC"
  run git -C "$RIDE" add "$DRAFT_ISSUE" "$DRAFT_SPEC"
  run git -C "$RIDE" commit -qm 'docs: drafts'
  run git -C "$RIDE" mv "$DRAFT_ISSUE" "$NUM_ISSUE"
  run git -C "$RIDE" mv "$DRAFT_SPEC" "$NUM_SPEC"
  numbered_issue > "$RIDE/$NUM_ISSUE"
  numbered_spec > "$RIDE/$NUM_SPEC"
  printf '{"v":1,"ts":"2026-10-10T00:00:00Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n{"v":1,"ts":"2026-10-10T00:00:01Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n' "$ISSUE_ID" "$SPEC_ID" >> "$RIDE/docs/ai/EVENTS.jsonl"
  printf 'delivered by the ride\n' >> "$RIDE/README.md"
  if [[ -n "${ROADMAP_WORLD:-}" ]]; then
    roadmap_ride > "$RIDE/docs/ai/roadmap.yaml"
    run git -C "$RIDE" add docs/ai/roadmap.yaml
  fi
  if [[ -n "${ENGINE_VARIANT:-}" ]]; then
    run cp "$ENGINE_VARIANT" "$RIDE/.aai/scripts/merge-cleanup.mjs"
    run git -C "$RIDE" add -f .aai/scripts/merge-cleanup.mjs
  fi
  run git -C "$RIDE" add "$NUM_ISSUE" "$NUM_SPEC" docs/ai/EVENTS.jsonl README.md
  if [[ -n "${EXTRA_OTHER:-}" ]]; then
    printf '\nCross-link to foo.\n' >> "$RIDE/docs/issues/ISSUE-0002-other-item.md"
    run git -C "$RIDE" add docs/issues/ISSUE-0002-other-item.md
  fi
  # RIDE_SEED: a function that records the ride's own amendments before it closes
  if [[ -n "${RIDE_SEED:-}" ]]; then "$RIDE_SEED"; fi
  run git -C "$RIDE" commit -qm 'docs: number and close'
  run git -C "$RIDE" push -q origin "$BRANCH"
  run git -C "$RIDE" push -q origin "HEAD:refs/pull/$PR/head"
  HEAD_OID="$(git -C "$RIDE" rev-parse HEAD)" || fail SETUP 'ride head'
  tree="$(git -C "$RIDE" rev-parse 'HEAD^{tree}')" || fail SETUP 'ride tree'
  main0="$(git -C "$BARE" rev-parse refs/heads/main)" || fail SETUP 'bare main'
  MC="$(git -C "$BARE" commit-tree "$tree" -p "$main0" -m "foo (#$PR)")" || fail SETUP 'squash commit'
  run git -C "$BARE" update-ref refs/heads/main "$MC"
  write_pr_json MERGED "$MC"
}

# roadmap_base: the baseline roadmap (foo is deferred in wave_2); roadmap_ride: what the merged PR leaves
# (the pair as close-work-item's advance leaves it, or, with RIDE_ROADMAP=elsewhere, an edit elsewhere with no foo block).
roadmap_base() { printf 'pairs:\n  - capability: other-item\n    status: done\nwave_2:\n  - foo\n  - later\n'; }
roadmap_ride() {
  case "${RIDE_ROADMAP:-done}" in
    elsewhere) printf 'pairs:\n  - capability: other-item\n    status: active\nwave_2:\n  - foo\n  - later\n' ;;
    pr485) printf 'pairs:\n  - capability: other-item\n    status: done\n  - capability: parent-cap\n    status: active\n  - capability: foo\n    status: done\nwave_2:\n  - later\n' ;;
    pr485paused) printf 'pairs:\n  - capability: other-item\n    status: done\n  - capability: parent-cap\n    status: paused\n  - capability: foo\n    status: done\nwave_2:\n  - later\n' ;;
    qux) printf 'pairs:\n  - capability: other-item\n    status: done\n  - capability: qux\n    status: done\nwave_2:\n  - foo\n  - later\n' ;;
    *) printf 'pairs:\n  - capability: other-item\n    status: done\n  - capability: foo\n    status: done\nwave_2:\n  - later\n' ;;
  esac
}
draft_issue_v1() { printf -- '---\nid: %s\ntype: issue\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Issue foo\n\nDraft body.\n' "$ISSUE_ID"; }
draft_spec_v1() { printf -- '---\nid: %s\ntype: spec\nnumber: null\nstatus: implementing\nlinks:\n  requirement: %s\n  pr: []\n  commits: []\n---\n\n# Spec foo\n\nDraft spec body.\n' "$SPEC_ID" "$ISSUE_ID"; }
# numbered_issue: the ride's numbered intake. NUMBERED_ISSUE_FILE names bytes the real allocator made; ISSUE_NO_PR omits
# links.pr and ISSUE_PR_EMPTY writes an empty list (the merged doc was not stamped with the PR).
numbered_issue() {
  if [[ -n "${NUMBERED_ISSUE_FILE:-}" ]]; then cat "$NUMBERED_ISSUE_FILE"; return; fi
  local pr
  if [[ -n "${ISSUE_NO_PR:-}" ]]; then pr='';
  elif [[ -n "${ISSUE_PR_EMPTY:-}" ]]; then pr='  pr: []\n';
  else pr="  pr:\n    - ${ISSUE_LINK_PR:-$PR}\n"; fi
  printf -- "---\nid: %s\ntype: issue\nnumber: 1\nstatus: %s\nlinks:\n${pr}  commits: []\n---\n\n# Issue foo\n\nDraft body.\n\nDelivered.\n" "$ISSUE_ID" "${ISSUE_STATUS:-done}"
}
other_item_doc() { printf -- '---\nid: other-item\ntype: issue\nnumber: 2\nstatus: implementing\nlinks:\n  pr: []\n  commits: []\n---\n\n# Other item\n\nStill in flight.\n'; }
numbered_spec() { printf -- '---\nid: %s\ntype: spec\nnumber: 1\nstatus: done\nlinks:\n  requirement: %s\n  pr:\n    - %s\n  commits: []\n---\n\n# Spec foo\n\nDraft spec body.\n\nDelivered.\n\n## Acceptance Criteria Status\n\n| Spec-AC | Description | Status | Evidence | Review-By | Notes |\n|---|---|---|---|---|---|\n| Spec-AC-01 | The fixture spec is delivered. | done | docs/ai/tdd/foo-green.log | tdd | fixture |\n' "$SPEC_ID" "$ISSUE_ID" "$PR"; }

# write_pr_json <state> <merge-commit-oid|null>
# PR_CROSS=true|absent and PR_HEAD_NAME=<name> override the head repository flag / head branch name.
write_pr_json() {
  local state="$1" mc="$2" mcjson='null' cross='"isCrossRepository":false,'
  if [[ "$mc" != null ]]; then mcjson="{\"oid\":\"$mc\"}"; fi
  case "${PR_CROSS:-}" in true) cross='"isCrossRepository":true,' ;; absent) cross='' ;; esac
  printf '{"number":%s,"state":"%s","isDraft":false,"headRefOid":"%s","headRefName":"%s","baseRefName":"main","mergeStateStatus":"UNKNOWN","statusCheckRollup":[],"mergeCommit":%s,%s"url":"https://github.com/example/repo/pull/%s"}\n' \
    "$PR" "$state" "$HEAD_OID" "${PR_HEAD_NAME:-$BRANCH}" "$mcjson" "$cross" "$PR" > "$GHD/pr-$PR.json"
}

# world_digest: one hash over the origin and ride trees (all files, .git
# excluded), git status, worktree list, local branches of both repos.
world_digest() {
  [[ -n "$W" && "$W" = /* ]] || fail SETUP 'digest root'
  {
    git -C "$ORIGIN" rev-parse HEAD
    git -C "$ORIGIN" reflog
    git -C "$ORIGIN" status --porcelain=v1 -uall
    git -C "$ORIGIN" worktree list --porcelain
    git -C "$ORIGIN" for-each-ref --format='%(refname) %(objectname)' refs/heads
    git -C "$BARE" for-each-ref --format='%(refname) %(objectname)' refs/heads
    git -C "$ORIGIN" stash list
    { find "$ORIGIN" -path '*/.git' -prune -o -type f -print
      if [[ -d "$RIDE" ]]; then find "$RIDE" -path '*/.git' -prune -o -type f -print; fi
    } | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s %s\n' "$f" "$(sha_of "$f")"
    done
  } | sha_stdin
}

# run_engine <args...>: runs the engine from the origin checkout with the gh
# stub first on PATH. Sets ENG_OUT (stdout), ENG_ERR (stderr), ENG_RC.
run_engine() {
  ENG_RC=0
  local cwd="${ENG_CWD:-$ORIGIN}"
  [[ -n "$cwd" && "$cwd" = /* ]] || fail SETUP 'engine cwd'
  ( cd "$cwd" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" node "$ENGINE" "$@" >"$W/engine.out" 2>"$W/engine.err" ) || ENG_RC=$?
  ENG_OUT="$(cat "$W/engine.out")"
  ENG_ERR="$(cat "$W/engine.err")"
}

audit_verdict() {
  [[ -n "$ORIGIN" && "$ORIGIN" = /* ]] || fail SETUP 'audit cwd'
  ( cd "$ORIGIN" && node "$DOCS_AUDIT" --check --strict --no-event >"$W/audit.out" 2>&1 ) || true
  cat "$W/audit.out"
}

assert_no_merge_call() {
  if grep -Eq 'pr merge|--admin|--auto' "$GHD/gh-argv.log"; then fail "$1" "gh log shows a merge-class call: $(cat "$GHD/gh-argv.log")"; fi
}

# ---------------------------------------------------------------------------
test_005_apply_readback_gate() {
  build_world gate
  local before after
  # usage errors exit 2 and write nothing
  before="$(world_digest)"
  run_engine apply --pr "$PR"
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-005 "apply without --pid exited $ENG_RC, want 2"
  run_engine apply --pid 4242
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-005 "apply without --pr exited $ENG_RC, want 2"
  run_engine bogus --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-005 "unknown mode exited $ENG_RC, want 2"
  run_engine apply --pr 0 --pid 4242
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-005 "--pr 0 exited $ENG_RC, want 2"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-005 'usage errors changed the fixture'

  # arm: state/merge-commit shapes that must refuse before any mutation
  local arm state mcval reason
  for arm in "OPEN|null|not_merged" "CLOSED|null|not_merged" "MERGED|null|not_merged" \
             "MERGED|HEAD|merge_commit_not_on_base" "MERGED|deadbeefdeadbeefdeadbeefdeadbeefdeadbeef|merge_commit_not_on_base"; do
    state="${arm%%|*}"; mcval="${arm#*|}"; reason="${mcval#*|}"; mcval="${mcval%%|*}"
    if [[ "$mcval" == HEAD ]]; then mcval="$HEAD_OID"; fi
    write_pr_json "$state" "$mcval"
    : > "$GHD/gh-argv.log"
    before="$(world_digest)"
    run_engine apply --pr "$PR" --pid 4242
    [[ "$ENG_RC" -eq 3 ]] || fail TEST-005 "arm $state/$reason exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
    want TEST-005 "$ENG_OUT" "REFUSE $reason"
    after="$(world_digest)"
    [[ "$after" == "$before" ]] || fail TEST-005 "arm $state/$reason changed files, worktrees, branches or STATE"
    # positive control: the gate really read the PR (a vacuous refusal would not)
    want TEST-005 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"
    assert_no_merge_call TEST-005
    [[ -f "$ORIGIN/README.md" ]] || fail TEST-005 "arm $state/$reason changed README"
    [[ ! -e "$ORIGIN/docs/ai/archive" ]] || fail TEST-005 "arm $state/$reason created an archive"
  done

  # negative control: the same fixture with a truly merged PR passes the gate
  write_pr_json MERGED "$MC"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-005 "merged control exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"

  # repo_mismatch: the PR's repository differs from the origin remote's (NB-4).
  # The refusal precedes every write; a matching slug (case-insensitive, through
  # an insteadOf rewrite so no network is touched) passes the same gate.
  build_world repo_mismatch
  run git -C "$ORIGIN" remote set-url origin https://github.com/other/repo.git
  refuse_arm TEST-005 repo_mismatch 'PR example/repo'
  run git -C "$ORIGIN" remote set-url origin https://github.com/Example/Repo.git
  run git -C "$ORIGIN" config "url.$BARE.insteadOf" https://github.com/Example/Repo.git
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-005 "matching repository slug exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"

  # test seams are inert in production (F5): AAI_MERGE_CLEANUP_GH_NODE replaces gh,
  # STOP_AFTER and CRASH_AT stop the run - each only when the TEST_SEAMS guard is set
  build_world seams
  printf 'require("fs").writeFileSync(process.env.SEAM_MARK, "ran");\nprocess.stdout.write(require("fs").readFileSync(process.env.SEAM_PR));\n' > "$W/gh-seam.js"
  local mark="$W/seam.mark"
  rm -f "$mark"
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" SEAM_MARK="$mark" SEAM_PR="$GHD/pr-$PR.json" AAI_MERGE_CLEANUP_GH_NODE="$W/gh-seam.js" AAI_MERGE_CLEANUP_STOP_AFTER=resolve AAI_MERGE_CLEANUP_CRASH_AT=sync-after-ff node "$ENGINE" plan --pr "$PR" >"$W/engine.out" 2>"$W/engine.err" ) || fail TEST-005 "plan with unguarded seams exited non-zero: $(cat "$W/engine.err")"
  [[ ! -e "$mark" ]] || fail TEST-005 'AAI_MERGE_CLEANUP_GH_NODE was honoured without the TEST_SEAMS guard'
  want TEST-005 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_STOP_AFTER=resolve AAI_MERGE_CLEANUP_CRASH_AT=sync-after-ff node "$ENGINE" apply --pr "$PR" --pid 4242 >"$W/engine.out" 2>"$W/engine.err" ) || fail TEST-005 "apply with unguarded STOP_AFTER/CRASH_AT exited non-zero: $(cat "$W/engine.out") $(cat "$W/engine.err")"
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-005 'unguarded STOP_AFTER/CRASH_AT stopped the run'
  # positive control: with the guard the gh seam really runs
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" SEAM_MARK="$mark" SEAM_PR="$GHD/pr-$PR.json" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_GH_NODE="$W/gh-seam.js" node "$ENGINE" plan --pr "$PR" >"$W/engine.out" 2>"$W/engine.err" ) || fail TEST-005 "guarded seam plan exited non-zero: $(cat "$W/engine.err")"
  [[ -e "$mark" ]] || fail TEST-005 'guarded AAI_MERGE_CLEANUP_GH_NODE seam did not run (positive control)'
  echo 'PASS: TEST-005 apply read-back gate'
}

# ---------------------------------------------------------------------------
# Batch B2: base sync (TEST-008/009), worktree and branch cleanup (TEST-010/011)

EV='docs/ai/EVENTS.jsonl'
LOCAL_LINE_A='{"v":1,"ts":"2026-10-10T01:00:00Z","actor":"local","event":"local_note","ref":"localtail-a","payload":{}}'
LOCAL_LINE_B='{"v":1,"ts":"2026-10-10T01:00:01Z","actor":"local","event":"local_note","ref":"localtail-b","payload":{}}'

count_line() { /usr/bin/grep -cxF -- "$2" "$1" || true; }
kf() { printf '%s/keep-%s' "$W" "$(printf '%s' "$1" | tr '/' '_')"; }

test_008_base_sync_preserves_work() {
  build_world sync
  local arch rep head_now target before_sha n_in n_out
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  # dirty unrelated tracked file, untracked note, local ledger tail, dirty INDEX
  printf 'local edit\n' >> "$ORIGIN/UNRELATED.txt"
  printf 'my private note\n' > "$ORIGIN/NOTE.txt"
  printf '%s\n%s\n' "$LOCAL_LINE_A" "$LOCAL_LINE_B" >> "$ORIGIN/$EV"
  printf 'hand-edited index line\n' >> "$ORIGIN/docs/INDEX.md"
  run cp "$ORIGIN/UNRELATED.txt" "$W/unrelated.keep"
  run cp "$ORIGIN/NOTE.txt" "$W/note.keep"
  before_sha="$(sha_of "$ORIGIN/$EV")"
  git -C "$BARE" show "refs/heads/main:$EV" > "$W/incoming-events.jsonl" || fail SETUP 'incoming ledger blob'
  [[ -s "$W/incoming-events.jsonl" ]] || fail SETUP 'incoming ledger blob empty'

  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-008 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  cmp "$W/unrelated.keep" "$ORIGIN/UNRELATED.txt" || fail TEST-008 'dirty unrelated tracked file changed'
  cmp "$W/note.keep" "$ORIGIN/NOTE.txt" || fail TEST-008 'untracked note changed'
  # the incoming blob is a byte-exact prefix of the working ledger
  n_in="$(wc -c < "$W/incoming-events.jsonl" | tr -d ' ')"
  head -c "$n_in" "$ORIGIN/$EV" > "$W/result-prefix.jsonl" || fail TEST-008 'cannot read the result prefix'
  cmp "$W/incoming-events.jsonl" "$W/result-prefix.jsonl" || fail TEST-008 'incoming ledger blob is not a byte prefix of the result'
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 ]] || fail TEST-008 'local ledger line A not exactly once'
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-008 'local ledger line B not exactly once'
  n_out="$(wc -l < "$ORIGIN/$EV" | tr -d ' ')"
  [[ "$n_out" == "$(( $(wc -l < "$W/incoming-events.jsonl" | tr -d ' ') + 2 ))" ]] || fail TEST-008 "ledger has $n_out lines, want incoming + 2"
  # the pre-sync dirty ledger bytes are archived and sha-recorded
  [[ "$(sha_of "$arch/sync/$EV")" == "$before_sha" ]] || fail TEST-008 'archived local ledger bytes differ from the pre-run working file'
  want TEST-008 "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$before_sha\""
  # INDEX regenerated, the hand edit archived
  unwanted TEST-008 "$(cat "$ORIGIN/docs/INDEX.md")" 'hand-edited index line'
  want TEST-008 "$(cat "$ORIGIN/docs/INDEX.md")" 'SPEC-0001'
  want TEST-008 "$(cat "$arch/sync/docs/INDEX.md")" 'hand-edited index line'
  # HEAD == refs/heads/main == origin/main == the squash commit
  head_now="$(git -C "$ORIGIN" rev-parse HEAD)"; target="$(git -C "$ORIGIN" rev-parse refs/heads/main)"
  [[ "$head_now" == "$target" && "$head_now" == "$MC" ]] || fail TEST-008 "HEAD $head_now, main $target, want $MC"
  [[ "$(git -C "$ORIGIN" rev-parse refs/remotes/origin/main)" == "$MC" ]] || fail TEST-008 'origin/main is not the merge commit'
  [[ -z "$(git -C "$ORIGIN" stash list)" ]] || fail TEST-008 'a stash entry exists'
  [[ "$(json_get "$rep" 'j.steps.find(s=>s.id==="sync-base").status')" == done ]] || fail TEST-008 'sync-base not reported done'

  # fully-covered case: a rerun finds HEAD at the target and is a named no-op
  before_sha="$(sha_of "$ORIGIN/$EV")"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-008 "rerun exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(json_get "$ENG_OUT" 'j.steps.find(s=>s.id==="sync-base").status')" == noop ]] || fail TEST-008 'rerun sync-base was not a no-op'
  [[ "$(sha_of "$ORIGIN/$EV")" == "$before_sha" ]] || fail TEST-008 'rerun changed the ledger'
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 ]] || fail TEST-008 'rerun duplicated a local ledger line'
  assert_no_merge_call TEST-008

  # degenerate / negative control: nothing dirty at all still fast-forwards
  build_world cleansync
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-008 "clean-origin apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-008 'clean origin did not reach the merge commit'
  echo 'PASS: TEST-008 base sync preserves work and ledgers'
}

# refuse_arm <test-id> <reason> <detail>: the world was prepared by the caller;
# apply must exit 3 with the named reason and change nothing.
refuse_arm() {
  local tid="$1" reason="$2" detail="$3" before after stash_before reflog_before
  : > "$GHD/gh-argv.log"
  before="$(world_digest)"; stash_before="$(git -C "$ORIGIN" stash list)"; reflog_before="$(git -C "$ORIGIN" reflog | wc -l | tr -d ' ')"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 3 ]] || fail "$tid" "arm $reason exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want "$tid" "$ENG_OUT" "REFUSE $reason $detail"
  after="$(world_digest)"
  [[ "$after" == "$before" ]] || fail "$tid" "arm $reason changed HEAD, refs, files, worktrees or branches"
  [[ "$(git -C "$ORIGIN" stash list)" == "$stash_before" ]] || fail "$tid" "arm $reason changed the stash list"
  [[ "$(git -C "$ORIGIN" reflog | wc -l | tr -d ' ')" == "$reflog_before" ]] || fail "$tid" "arm $reason added a reflog entry"
  unwanted "$tid" "$(git -C "$ORIGIN" reflog)" 'reset'
  want "$tid" "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"   # positive control: the gate ran
  [[ ! -e "$ORIGIN/docs/ai/archive" ]] || fail "$tid" "arm $reason created an archive before refusing"
  assert_no_merge_call "$tid"
}

# keep_arm <test-id> <reason> <detail> [step]: the world was prepared by the caller. A protected object is kept
# (spec-merge-cleanup-resolves-framework-friction D6): exit 0, the OUTCOME line is class auto and resolved, a Kept:
# line and the retained step are reported, and with sync-base the main checkout's HEAD and status are unchanged.
keep_arm() {
  local tid="$1" reason="$2" detail="$3" step="${4:-sync-base}" head_b status_b
  : > "$GHD/gh-argv.log"
  head_b="$(git -C "$ORIGIN" rev-parse HEAD)"; status_b="$(git -C "$ORIGIN" status --porcelain=v1 -uall)"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail "$tid" "arm $reason exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want "$tid" "$ENG_OUT" "\"reason\":\"$reason\""
  want "$tid" "$ENG_OUT" "$detail"
  want "$tid" "$ENG_OUT" 'Kept: '
  want "$tid" "$ENG_OUT" "  $step: retained"
  unwanted "$tid" "$ENG_OUT" 'REFUSE'
  if [[ "$step" == sync-base ]]; then
    [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$head_b" ]] || fail "$tid" "arm $reason moved the main checkout HEAD"
    [[ "$(git -C "$ORIGIN" status --porcelain=v1 -uall)" == "$status_b" ]] || fail "$tid" "arm $reason changed the main checkout status"
  fi
  want "$tid" "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"   # positive control: the gate ran
  assert_no_merge_call "$tid"
}

# decide_arm <test-id> <reason> <detail>: apply reaches the end with one pending decide item (exit 6), the main checkout is unchanged.
decide_arm() {
  local tid="$1" reason="$2" detail="$3" head_b status_b
  head_b="$(git -C "$ORIGIN" rev-parse HEAD)"; status_b="$(git -C "$ORIGIN" status --porcelain=v1 -uall)"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 6 ]] || fail "$tid" "arm $reason exited $ENG_RC, want 6 (out: $ENG_OUT $ENG_ERR)"
  want "$tid" "$ENG_OUT" "\"reason\":\"$reason\""
  want "$tid" "$ENG_OUT" '"class":"decide"'
  want "$tid" "$ENG_OUT" "$detail"
  want "$tid" "$ENG_OUT" 'Decision: '
  want "$tid" "$ENG_OUT" 'Cleanup: waiting for your decision on 1 item(s)'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$head_b" ]] || fail "$tid" "arm $reason moved the main checkout HEAD"
  [[ "$(git -C "$ORIGIN" status --porcelain=v1 -uall)" == "$status_b" ]] || fail "$tid" "arm $reason changed the main checkout status"
  assert_no_merge_call "$tid"
}

test_009_base_sync_refusals() {
  local before
  build_world origin_not_on_base
  run git -C "$ORIGIN" checkout -q -b elsewhere
  keep_arm TEST-009 origin_not_on_base elsewhere

  build_world base_diverged
  printf 'local commit\n' > "$ORIGIN/local-commit.txt"
  run git -C "$ORIGIN" add local-commit.txt
  run git -C "$ORIGIN" commit -qm 'local commit not on origin'
  keep_arm TEST-009 base_diverged main
  [[ -f "$ORIGIN/local-commit.txt" ]] || fail TEST-009 'base_diverged arm lost the local commit file'

  build_world overlap
  printf 'dirty and also changed by the PR\n' >> "$ORIGIN/README.md"
  decide_arm TEST-009 overlap README.md
  [[ "$(tail -n 1 "$ORIGIN/README.md")" == 'dirty and also changed by the PR' ]] || fail TEST-009 'overlap arm changed the local README'

  build_world untracked_collision
  printf 'my own different file\n' > "$ORIGIN/$NUM_ISSUE"
  decide_arm TEST-009 untracked_collision "$NUM_ISSUE"
  [[ "$(cat "$ORIGIN/$NUM_ISSUE")" == 'my own different file' ]] || fail TEST-009 'collision arm changed the untracked file'

  build_world ledger_rewritten
  printf '{"v":1,"ts":"2026-10-09T00:00:00Z","actor":"fixture","event":"seed","ref":"REWRITTEN","payload":{}}\n' > "$ORIGIN/$EV"
  keep_arm TEST-009 ledger_rewritten "$EV"
  [[ "$(sed -n 's/.*"ref":"\([A-Z]*\)".*/\1/p' "$ORIGIN/$EV")" == REWRITTEN ]] || fail TEST-009 'ledger_rewritten arm changed the rewritten ledger'

  # control: an untracked file whose bytes EQUAL the incoming blob is no collision
  build_world collision_equal
  numbered_issue > "$ORIGIN/$NUM_ISSUE"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-009 "equal-bytes untracked file exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-009 'equal-bytes control did not reach the merge commit'

  # mid-operation failure: the fast-forward fails after the ledger and INDEX were
  # set aside; their working bytes must be written back and HEAD must not move
  build_world ff_fails
  printf '%s\n' "$LOCAL_LINE_A" >> "$ORIGIN/$EV"
  printf 'hand-edited index line\n' >> "$ORIGIN/docs/INDEX.md"
  run cp "$ORIGIN/$EV" "$W/events.keep"
  run cp "$ORIGIN/docs/INDEX.md" "$W/index.keep"
  before="$(git -C "$ORIGIN" rev-parse HEAD)"
  : > "$ORIGIN/.git/index.lock"
  run_engine apply --pr "$PR" --pid 4242
  rm -f "$ORIGIN/.git/index.lock"
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-009 "failed fast-forward exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-009 "$ENG_OUT" 'sync_failed'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$before" ]] || fail TEST-009 'HEAD moved although the fast-forward failed'
  cmp "$W/events.keep" "$ORIGIN/$EV" || fail TEST-009 'local ledger bytes were not written back'
  cmp "$W/index.keep" "$ORIGIN/docs/INDEX.md" || fail TEST-009 'local INDEX bytes were not written back'
  [[ -z "$(git -C "$ORIGIN" stash list)" ]] || fail TEST-009 'a stash entry exists'
  echo 'PASS: TEST-009 base sync refusals and write-back'
}

# seed_runtime: ignored runtime and evidence files in the ride worktree plus a
# differing counterpart in the origin.
seed_runtime() {
  run mkdir -p "$RIDE/docs/ai/tdd" "$RIDE/docs/ai/reports" "$RIDE/docs/ai/validation" "$ORIGIN/docs/ai/tdd"
  printf 'current_focus:\n  ref_id: foo\n' > "$RIDE/docs/ai/STATE.yaml"
  printf 'ride only evidence\n' > "$RIDE/docs/ai/tdd/only-ride.log"
  printf 'ride version\n' > "$RIDE/docs/ai/tdd/shared.log"
  printf 'origin version\n' > "$ORIGIN/docs/ai/tdd/shared.log"
  printf 'report body\n' > "$RIDE/docs/ai/reports/report.md"
  printf 'validation body\n' > "$RIDE/docs/ai/validation/v.md"
}
RUNTIME_FILES='docs/ai/STATE.yaml docs/ai/tdd/only-ride.log docs/ai/tdd/shared.log docs/ai/reports/report.md docs/ai/validation/v.md'

test_010_worktree_and_branch_cleanup() {
  build_world cleanup
  local arch other pid rep f
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"; other="$W/other-ride"
  seed_runtime
  run git -C "$ORIGIN" worktree add -q -b ride/other "$other" main
  run git -C "$ORIGIN" branch misc main
  run git -C "$BARE" update-ref refs/heads/misc-remote "$(git -C "$BARE" rev-parse refs/heads/main)"
  # a session lock held by --pid itself does not block the cleanup
  sleep 600 & pid=$!
  HELPER_PIDS+=("$pid")
  ( cd "$RIDE" && node "$ROOT/.aai/scripts/lib/session-lock.mjs" acquire --pid "$pid" --ref foo >/dev/null ) || fail SETUP 'lock acquire'
  [[ "$(git -C "$ORIGIN" rev-parse "refs/heads/$BRANCH")" == "$HEAD_OID" ]] || fail SETUP 'branch tip'
  if git -C "$ORIGIN" merge-base --is-ancestor "$HEAD_OID" refs/heads/main 2>/dev/null; then fail SETUP 'fixture is not a squash merge'; fi
  for f in $RUNTIME_FILES; do run cp "$RIDE/$f" "$(kf "$f")"; done

  # bot sweep P2-3: plan names the concrete targets of every action step and writes nothing
  local pdig
  pdig="$(world_digest)"
  run_engine plan --pr "$PR" --pid "$pid" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-010 "plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(world_digest)" == "$pdig" ]] || fail TEST-010 'plan changed the fixture'
  [[ ! -e "$arch" ]] || fail TEST-010 'plan created the archive'
  rep="$ENG_OUT"
  want TEST-010 "$(json_get "$rep" 'j.steps.map(s=>s.id)')" "archive-drafts"
  unwanted TEST-010 "$(json_get "$rep" 'j.steps.map(s=>s.id)')" "state"
  unwanted TEST-010 "$(json_get "$rep" 'j.steps.map(s=>s.id)')" "index-audit"
  unwanted TEST-010 "$(json_get "$rep" 'j.steps.map(s=>s.id)')" "delete-remote-branch"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="archive-runtime").targets')" "worktree:docs/ai/STATE.yaml"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="sync-base").targets')" "$(git -C "$ORIGIN" rev-parse --short=12 HEAD)..$(git -C "$ORIGIN" rev-parse --short=12 "$MC")"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="remove-worktree").targets')" "$RIDE"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="delete-branch").targets')" "$BRANCH"
  [[ "$(json_get "$rep" 'j.steps.find(s=>s.id==="delete-branch").status')" == planned ]] || fail TEST-010 'plan step status is not planned'

  run_engine apply --pr "$PR" --pid "$pid" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-010 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  # archive-runtime archives only the ride STATE.yaml
  local state_pre
  state_pre="$(kf docs/ai/STATE.yaml)"
  [[ "$(sha_of "$arch/worktree/docs/ai/STATE.yaml")" == "$(sha_of "$state_pre")" ]] || fail TEST-010 "archived STATE.yaml differs from the pre-removal bytes"
  want TEST-010 "$(cat "$arch/manifest.jsonl")" "\"original\":\"worktree:docs/ai/STATE.yaml\""
  want TEST-010 "$(cat "$arch/manifest.jsonl")" '"step":"archive-runtime"'
  # worktree removed, branch deleted although it is not an ancestor
  [[ ! -e "$RIDE" ]] || fail TEST-010 'ride worktree directory still exists'
  unwanted TEST-010 "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE"
  if git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then fail TEST-010 'ride branch still exists'; fi
  # everything else is intact
  [[ -d "$other" ]] || fail TEST-010 'the other worktree was removed'
  git -C "$ORIGIN" rev-parse -q --verify refs/heads/ride/other >/dev/null || fail TEST-010 'the other worktree branch was deleted'
  git -C "$ORIGIN" rev-parse -q --verify refs/heads/misc >/dev/null || fail TEST-010 'an unrelated branch was deleted'
  # spec-merge-cleanup-delete-remote-branch D9 supersedes SPEC-0218 D10: the merged remote branch is deleted by lease
  if git -C "$BARE" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then fail TEST-010 'the merged remote branch still exists'; fi
  git -C "$BARE" rev-parse -q --verify refs/heads/misc-remote >/dev/null || fail TEST-010 'an unrelated remote branch was deleted'
  unwanted TEST-010 "$(json_get "$rep" 'j.remaining')" "origin/$BRANCH"
  [[ "$(json_get "$rep" 'j.steps.find(s=>s.id==="remove-worktree").status')" == done ]] || fail TEST-010 'remove-worktree not done'
  [[ "$(json_get "$rep" 'j.steps.find(s=>s.id==="delete-branch").status')" == done ]] || fail TEST-010 'delete-branch not done'

  # rerun: both steps are named no-ops
  run_engine apply --pr "$PR" --pid "$pid" --json
  stop_helper "$pid"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-010 "rerun exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(json_get "$ENG_OUT" 'j.steps.find(s=>s.id==="remove-worktree").status')" == noop ]] || fail TEST-010 'rerun remove-worktree not a no-op'
  [[ "$(json_get "$ENG_OUT" 'j.steps.find(s=>s.id==="delete-branch").status')" == noop ]] || fail TEST-010 'rerun delete-branch not a no-op'
  assert_no_merge_call TEST-010

  # bot sweep P2-4: a failed git ls-remote is remote_unknown under remaining, never "no remote
  # action"; an absent remote branch stays distinct (nothing remaining); a present one is named
  local shim="$W/shim" real_git
  real_git="$(command -v git)"
  build_world remote_unknown
  run mkdir -p "$shim"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do if [ "$a" = ls-remote ]; then echo "fatal: unable to access" >&2; exit 128; fi; done\nexec "%s" "$@"\n' "$real_git" > "$shim/git"
  run chmod +x "$shim/git"
  PATH="$shim:$PATH" run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-010 "remote_unknown arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-010 "$(json_get "$ENG_OUT" 'j.remaining')" "remote_unknown"
  want TEST-010 "$(json_get "$ENG_OUT" 'j.remaining')" "origin/$BRANCH"
  build_world remote_absent
  run git -C "$BARE" update-ref -d "refs/heads/$BRANCH"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-010 "remote_absent arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-010 "$(json_get "$ENG_OUT" 'j.remaining')" "remote_unknown"
  unwanted TEST-010 "$(json_get "$ENG_OUT" 'j.remaining')" "origin/$BRANCH"
  echo 'PASS: TEST-010 worktree archived, removed, branch compare-and-swap deleted'
}

test_011_worktree_refusals() {
  local pid dead
  build_world dirty
  printf 'uncommitted\n' > "$RIDE/stray.txt"
  keep_arm TEST-011 worktree_dirty "$RIDE" remove-worktree
  [[ -d "$RIDE" && "$(cat "$RIDE/stray.txt")" == uncommitted ]] && git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-011 'dirty arm lost the worktree, its file or its branch'
  want TEST-011 "$ENG_OUT" '  sync-base: done'
  want TEST-011 "$ENG_OUT" 'kept_with_worktree'

  build_world tip
  printf 'after the merge\n' > "$RIDE/after.txt"
  run git -C "$RIDE" add after.txt
  run git -C "$RIDE" commit -qm 'work after the merge'
  keep_arm TEST-011 tip_mismatch "$BRANCH" remove-worktree
  [[ -d "$RIDE" && "$(git -C "$RIDE" rev-parse HEAD)" != "$HEAD_OID" ]] || fail TEST-011 'tip arm lost the worktree or its commit'

  build_world locked
  sleep 600 & pid=$!
  HELPER_PIDS+=("$pid")
  ( cd "$RIDE" && node "$ROOT/.aai/scripts/lib/session-lock.mjs" acquire --pid "$pid" >/dev/null ) || fail SETUP 'lock acquire'
  keep_arm TEST-011 session_locked "$pid" remove-worktree
  [[ -d "$RIDE" && -f "$RIDE/.git" ]] || fail TEST-011 'locked arm lost the worktree'
  stop_helper "$pid"

  build_world cwd
  ENG_CWD="$RIDE"
  keep_arm TEST-011 cwd_inside_target "$RIDE" remove-worktree
  ENG_CWD=''
  [[ -d "$RIDE" ]] || fail TEST-011 'cwd arm lost the worktree'

  # a registered worktree whose directory is gone is named worktree_missing (never
  # worktree_dirty), is never pruned, and its branch is left alone (NB-4)
  build_world missing
  [[ -n "$RIDE" && "$RIDE" = /* && -d "$RIDE" ]] || fail SETUP 'missing-arm ride path'
  run rm -rf "$RIDE"
  keep_arm TEST-011 worktree_missing "$RIDE" remove-worktree
  want TEST-011 "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE"
  git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-011 'missing arm deleted the branch'

  # negative control: a lock held by a DEAD pid does not block
  build_world deadlock
  ( exit 0 ) & dead=$!
  wait "$dead" || true
  ( cd "$RIDE" && node "$ROOT/.aai/scripts/lib/session-lock.mjs" acquire --pid "$dead" >/dev/null ) || fail SETUP 'dead lock acquire'
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-011 "dead-lock control exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-011 'dead-lock control left the worktree'
  echo 'PASS: TEST-011 worktree refusals'
}

# ---------------------------------------------------------------------------
# Batch B3: focus, index and report (TEST-012), idempotence and resume (TEST-013/014)

STATE_REL='docs/ai/STATE.yaml'
ACTION_STEPS='archive-runtime sync-base reconcile-origin remove-worktree delete-branch report'
ALL_STEPS='resolve plan archive-drafts archive-runtime sync-base reconcile-origin remove-worktree delete-branch report'

# seed_state [ref]: the real check-state.mjs creates the origin STATE; with a
# ref the real state.mjs puts that ref in focus with an in-progress work item.
seed_state() {
  local ref="${1:-}"
  [[ -n "$ORIGIN" && "$ORIGIN" = /* ]] || fail SETUP 'seed_state origin'
  ( cd "$ORIGIN" && env -u AAI_ROLE node "$ROOT/.aai/scripts/check-state.mjs" --repair >/dev/null ) || fail SETUP 'state repair'
  if [[ -n "$ref" ]]; then
    ( cd "$ORIGIN" \
      && env -u AAI_ROLE node "$ROOT/.aai/scripts/state.mjs" set-focus --type intake_change --ref "$ref" --path "$DRAFT_ISSUE" >/dev/null \
      && env -u AAI_ROLE node "$ROOT/.aai/scripts/state.mjs" set-phase --ref "$ref" --phase implementation --status in_progress >/dev/null ) \
      || fail SETUP "state focus $ref"
  fi
}

# state_block <file> <top-level key>: the indented body of one STATE block.
state_block() { awk -v k="$2:" '$0 == k {f=1; next} f && /^[^ #]/ {f=0} f' "$1"; }

step_status() { json_get "$1" "j.steps.find(s=>s.id===\"$2\").status"; }

saved_reports() { find "$ORIGIN/docs/ai/reports" -maxdepth 1 -type f -name "merge-cleanup-pr$PR-*.md" 2>/dev/null | LC_ALL=C sort || true; }

# build_rich_world <name>: a world in which every action step has work to do.
PRE_LIST=''
build_rich_world() {
  build_world "$1"
  local other='docs/issues/ISSUE-DRAFT-other.md' f
  seed_runtime
  seed_state foo
  printf 'local edit\n' >> "$ORIGIN/UNRELATED.txt"
  printf 'my private note\n' > "$ORIGIN/NOTE.txt"
  printf '%s\n%s\n' "$LOCAL_LINE_A" "$LOCAL_LINE_B" >> "$ORIGIN/$EV"
  printf -- '---\nid: other\ntype: issue\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Other\n' > "$ORIGIN/$other"
  PRE_LIST="$W/pre.list"
  : > "$PRE_LIST"
  for f in UNRELATED.txt NOTE.txt "$EV" "$other"; do
    printf '%s %s\n' "$f" "$(sha_of "$ORIGIN/$f")" >> "$PRE_LIST"
  done
}

# every pre-run dirty or untracked file is still in the origin or archived
# byte-for-byte (same sha256) in the per-PR archive
assert_nothing_lost() {
  local tid="$1" f s p found arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  while IFS=' ' read -r f s; do
    if [[ -f "$ORIGIN/$f" && "$(sha_of "$ORIGIN/$f")" == "$s" ]]; then continue; fi
    found=''
    if [[ -d "$arch" ]]; then
      while IFS= read -r p; do
        if [[ "$(sha_of "$p")" == "$s" ]]; then found=yes; break; fi
      done < <(find "$arch" -type f ! -name manifest.jsonl ! -name journal.jsonl)
    fi
    [[ -n "$found" ]] || fail "$tid" "pre-run file $f (sha $s) is neither in the origin nor archived"
    want "$tid" "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$s\""
  done < "$PRE_LIST"
}

norm_sha() {
  case "$1" in
    */INDEX*.md) sed -e '/^Generated: /d' "$1" | sha_stdin ;;
    */choices.jsonl) sed -e 's/"timestamp":"[^"]*"//' "$1" | sha_stdin ;;
    */manifest.jsonl) sed -e 's/"timestamp":"[^"]*"//' -e '/"original":"origin:docs\/ai\/STATE.yaml"/s/"sha256":"[^"]*"//' "$1" | sha_stdin ;;
    */STATE.yaml) sed -e '/updated_at_utc:/d' "$1" | sha_stdin ;;
    *) sha_of "$1" ;;
  esac
}

# tree_sig: location-independent signature of the origin tree (journal and the
# time-stamped report are compared separately).
tree_sig() {
  [[ -n "$ORIGIN" && "$ORIGIN" = /* ]] || fail SETUP 'tree_sig origin'
  ( cd "$ORIGIN" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
      case "$f" in ./docs/ai/reports/merge-cleanup-pr*|*/journal.jsonl|./docs/ai/archive/handoffs/*) continue ;; esac
      printf '%s %s\n' "$f" "$(norm_sha "$f")"
    done )
}

journal_dups() { sed 's/,"timestamp":"[^"]*"//' "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/journal.jsonl" 2>/dev/null | LC_ALL=C sort | uniq -d | wc -l | tr -d ' ' || true; }

test_013_second_apply_is_noop() {
  build_rich_world idem
  local first second before s sig_before
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-013 "first apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  first="$ENG_OUT"
  # positive control: the first run really did every action
  for s in $ACTION_STEPS; do
    [[ "$(step_status "$first" "$s")" == done ]] || fail TEST-013 "first run: step $s reported $(step_status "$first" "$s"), want done"
  done
  before="$(world_digest)"
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 ]] || fail TEST-013 'first run: local ledger line A not exactly once'
  : > "$GHD/gh-argv.log"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-013 "second apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  second="$ENG_OUT"
  for s in $ACTION_STEPS; do
    [[ "$(step_status "$second" "$s")" == noop ]] || fail TEST-013 "second run: step $s reported $(step_status "$second" "$s"), want noop"
    want TEST-013 "$(json_get "$second" 'j.noops')" "noop:$s:"
  done
  unwanted TEST-013 "$(json_get "$second" 'j.noops')" 'sign-amendments'
  [[ "$(json_get "$second" 'j.noops.length')" == 7 ]] || fail TEST-013 "second run lists $(json_get "$second" 'j.noops.length') no-ops, want 7 (the six action steps and archive-drafts)"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-013 'second apply changed files, refs, worktrees or the reflog'
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 && "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-013 'second run duplicated a ledger line'
  [[ "$(LC_ALL=C sort "$ORIGIN/$EV" | uniq -d | wc -l | tr -d ' ')" == 0 ]] || fail TEST-013 'the ledger holds a duplicate line'
  [[ "$(saved_reports | wc -l | tr -d ' ')" == 0 ]] || fail TEST-013 'second run wrote a report file'
  [[ "$(journal_dups)" == 0 ]] || fail TEST-013 'journal holds a duplicate step line'
  want TEST-013 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"   # positive control: the gate ran
  assert_no_merge_call TEST-013
  assert_nothing_lost TEST-013
  echo 'PASS: TEST-013 second apply is a named no-op'
}

test_014_interrupted_run_converges() {
  local control_sig control_state id sig first second rc
  build_rich_world control
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-014 "control apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  control_state="$ENG_OUT"
  control_sig="$(tree_sig)"
  [[ -n "$control_sig" ]] || fail TEST-014 'control tree signature is empty'
  for id in $ALL_STEPS; do
    build_rich_world "stop_$id"
    rc=0
    ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_STOP_AFTER="$id" node "$ENGINE" apply --pr "$PR" --pid 4242 --json >"$W/engine.out" 2>"$W/engine.err" ) || rc=$?
    [[ "$rc" -eq 4 ]] || fail TEST-014 "stop after $id exited $rc, want 4 ($(cat "$W/engine.out") $(cat "$W/engine.err"))"
    want TEST-014 "$(cat "$W/engine.out")" "STOPPED after $id"
    assert_nothing_lost TEST-014
    run_engine apply --pr "$PR" --pid 4242 --json
    [[ "$ENG_RC" -eq 0 ]] || fail TEST-014 "resume after $id exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
    second="$ENG_OUT"
    # runtime STATE archived by the interrupted run is still in the final report
    want TEST-014 "$(json_get "$second" 'j.archived.map(a=>a.path)')" "worktree:docs/ai/STATE.yaml"
    sig="$(tree_sig)"
    [[ "$sig" == "$control_sig" ]] || fail TEST-014 "resume after $id differs from the uninterrupted run: $(diff <(printf '%s\n' "$control_sig") <(printf '%s\n' "$sig") | awk 'NR <= 6' | tr '\n' ' ')"
    assert_nothing_lost TEST-014
    [[ "$(LC_ALL=C sort "$ORIGIN/$EV" | uniq -d | wc -l | tr -d ' ')" == 0 ]] || fail TEST-014 "resume after $id left a duplicate ledger line"
    [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 && "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-014 "resume after $id: local ledger line not exactly once"
    [[ "$(saved_reports | wc -l | tr -d ' ')" == 0 ]] || fail TEST-014 "resume after $id left $(saved_reports | wc -l | tr -d ' ') reports, want 0"
    [[ "$(journal_dups)" == 0 ]] || fail TEST-014 "resume after $id: journal holds a duplicate step line"
    [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-014 "resume after $id: HEAD is not the merge commit"
    # a step completed before the interruption is reported as a named no-op on resume
    case " $ACTION_STEPS " in
      *" $id "*) [[ "$(step_status "$second" "$id")" == noop ]] || fail TEST-014 "resume after $id: step $id reported $(step_status "$second" "$id"), want noop"
                 want TEST-014 "$(json_get "$second" 'j.noops')" "noop:$id:" ;;
    esac
    assert_no_merge_call TEST-014
  done
  [[ "$(step_status "$control_state" sync-base)" == done ]] || fail TEST-014 'control run sync-base is not done'

  # a hard kill INSIDE sync-base (NB-2): after the dirty ledgers were rewritten to the HEAD
  # blob, and after the fast-forward but before the local tail was re-appended. The resume
  # re-appends from the archive: the final bytes equal the control run's, nothing is lost.
  local point
  for point in sync-after-rewrite sync-after-ff; do
    build_rich_world "crash_$point"
    rc=0
    ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT="$point" node "$ENGINE" apply --pr "$PR" --pid 4242 --json >"$W/engine.out" 2>"$W/engine.err" ) || rc=$?
    [[ "$rc" -eq 137 ]] || fail TEST-014 "crash at $point exited $rc, want 137 (killed) ($(cat "$W/engine.out") $(cat "$W/engine.err"))"
    if [[ "$point" == sync-after-ff ]]; then
      [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-014 'crash after the fast-forward: HEAD is not the merge commit (positive control)'
      [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 0 ]] || fail TEST-014 'crash after the fast-forward: the local tail is already back (positive control)'
    fi
    assert_nothing_lost TEST-014
    run_engine apply --pr "$PR" --pid 4242 --json
    [[ "$ENG_RC" -eq 0 ]] || fail TEST-014 "resume after crash at $point exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
    sig="$(tree_sig)"
    [[ "$sig" == "$control_sig" ]] || fail TEST-014 "resume after crash at $point differs from the uninterrupted run: $(diff <(printf '%s\n' "$control_sig") <(printf '%s\n' "$sig") | awk 'NR <= 6' | tr '\n' ' ')"
    assert_nothing_lost TEST-014
    [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 && "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-014 "resume after crash at $point: local ledger line not exactly once"
    [[ "$(LC_ALL=C sort "$ORIGIN/$EV" | uniq -d | wc -l | tr -d ' ')" == 0 ]] || fail TEST-014 "resume after crash at $point left a duplicate ledger line"
    [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-014 "resume after crash at $point: HEAD is not the merge commit"
    [[ "$(step_status "$ENG_OUT" sync-base)" == done ]] || fail TEST-014 "resume after crash at $point: sync-base reported $(step_status "$ENG_OUT" sync-base), want done (the re-append is work, not a no-op)"
    assert_no_merge_call TEST-014
  done

  # NB-r2-1: a kill at sync-after-rewrite, then ANOTHER session appends to the shared ledger before
  # the re-run. The local tail must come back after the concurrent line, nothing lost or doubled.
  local concurrent='{"v":1,"ts":"2026-10-10T02:00:00Z","actor":"other","event":"concurrent_note","ref":"concurrent","payload":{}}'
  build_rich_world crash_concurrent
  rc=0
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=sync-after-rewrite node "$ENGINE" apply --pr "$PR" --pid 4242 --json >"$W/engine.out" 2>"$W/engine.err" ) || rc=$?
  [[ "$rc" -eq 137 ]] || fail TEST-014 "concurrent arm: crash exited $rc, want 137"
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 0 ]] || fail TEST-014 'concurrent arm: the local tail is still live before the append (positive control)'
  printf '%s\n' "$concurrent" >> "$ORIGIN/$EV"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-014 "concurrent arm: resume exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 && "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-014 'concurrent arm: the local tail is not exactly once in the live ledger'
  [[ "$(count_line "$ORIGIN/$EV" "$concurrent")" == 1 ]] || fail TEST-014 'concurrent arm: the concurrent line is not exactly once'
  [[ "$(LC_ALL=C sort "$ORIGIN/$EV" | uniq -d | wc -l | tr -d ' ')" == 0 ]] || fail TEST-014 'concurrent arm: a duplicate ledger line'
  [[ ! -e "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/pending.json" ]] || fail TEST-014 'concurrent arm: the pending journal survived a clean resume'

  # a live ledger that no longer starts with the HEAD blob cannot be proven safe: refuse with a
  # named reason, keep the journal and the archived tail, overwrite nothing
  build_rich_world crash_diverged
  rc=0
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=sync-after-rewrite node "$ENGINE" apply --pr "$PR" --pid 4242 --json >"$W/engine.out" 2>"$W/engine.err" ) || rc=$?
  [[ "$rc" -eq 137 ]] || fail TEST-014 "diverged arm: crash exited $rc, want 137"
  printf 'someone rewrote the ledger\n' > "$ORIGIN/$EV"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-014 "diverged arm: resume exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-014 "$ENG_OUT" 'pending_diverged'
  [[ "$(step_status "$ENG_OUT" sync-base)" == retained ]] || fail TEST-014 'diverged arm: sync-base is not retained'
  [[ "$(step_status "$ENG_OUT" delete-branch)" != retained ]] || fail TEST-014 'diverged arm: the other steps did not finish'
  [[ -f "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/pending.json" ]] || fail TEST-014 'diverged arm: the pending journal was deleted'
  [[ "$(cat "$ORIGIN/$EV")" == 'someone rewrote the ledger' ]] || fail TEST-014 'diverged arm: the live ledger was overwritten'
  assert_nothing_lost TEST-014

  # NB-r2-4: the journal is found by ANY later apply, not only the same PR's. PR 433 is killed
  # mid-sync; the owner then merges and cleans PR 434. Its apply puts PR 433's tail back first.
  build_rich_world crash_foreign
  rc=0
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=sync-after-rewrite node "$ENGINE" apply --pr "$PR" --pid 4242 --json >"$W/engine.out" 2>"$W/engine.err" ) || rc=$?
  [[ "$rc" -eq 137 ]] || fail TEST-014 "foreign arm: crash exited $rc, want 137"
  sed -e 's/"number":433/"number":434/' -e 's#/pull/433#/pull/434#' "$GHD/pr-$PR.json" > "$GHD/pr-434.json"
  run_engine apply --pr 434 --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-014 "foreign arm: apply for another PR exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 && "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-014 'foreign arm: the other PR tail was not put back exactly once'
  [[ ! -e "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/pending.json" ]] || fail TEST-014 'foreign arm: the other PR journal survived'
  [[ "$(LC_ALL=C sort "$ORIGIN/$EV" | uniq -d | wc -l | tr -d ' ')" == 0 ]] || fail TEST-014 'foreign arm: a duplicate ledger line'
  assert_no_merge_call TEST-014
  echo 'PASS: TEST-014 interrupted run converges to the uninterrupted bytes'
}

# ---------------------------------------------------------------------------
# B4a: open-PR preflight (TEST-003/004) and the downstream layout (TEST-015).
# write_open_pr <state> <isDraft> <head> <mergeStateStatus> <rollup-json>
write_open_pr() {
  printf '{"number":%s,"state":"%s","isDraft":%s,"headRefOid":"%s","headRefName":"%s","baseRefName":"main","mergeStateStatus":"%s","statusCheckRollup":%s,"mergeCommit":null,"url":"https://github.com/example/repo/pull/%s"}\n' \
    "$PR" "$1" "$2" "$3" "$BRANCH" "$4" "$5" "$PR" > "$GHD/pr-$PR.json"
}
ROLLUP_OK='[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"b","status":"COMPLETED","conclusion":"NEUTRAL"},{"__typename":"CheckRun","name":"c","status":"COMPLETED","conclusion":"SKIPPED"},{"__typename":"StatusContext","context":"d","state":"SUCCESS"}]'
SWEEP_OK='{"v":1,"ts":"2026-10-10T01:00:00Z","actor":"fixture","event":"pr_sweep","ref":"foo","payload":{"pr":433,"lane":"heavy","threads_seen":1,"threads_unresolved":0,"reviewer_bots":"expected","outcome":"swept"}}'

# open_world <name>: a ride worktree on the PR head with a consistent sweep
# record (uncommitted) and an OPEN, clean, green PR. The sweep is judged in RIDE.
open_world() {
  build_world "$1"
  printf '%s\n' "$SWEEP_OK" >> "$RIDE/docs/ai/EVENTS.jsonl"
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  : > "$GHD/gh-argv.log"
}

# pf: the full, valid preflight argument list; arms append an override.
pf() { run_engine preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by human --direction 'merge 433 please' --origin "$RIDE" "$@"; }

# expect_refusal <test id> <reason> <command...>: exit 3, named reason, the
# fixture digest unchanged, and no merge-class gh call.
expect_refusal() {
  local tid="$1" reason="$2" before
  shift 2
  before="$(world_digest)"
  : > "$GHD/gh-argv.log"
  "$@"
  [[ "$ENG_RC" -eq 3 ]] || fail "$tid" "arm $reason exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want "$tid" "$ENG_OUT" "REFUSE $reason"
  [[ "$(world_digest)" == "$before" ]] || fail "$tid" "arm $reason changed the fixture"
  assert_no_merge_call "$tid"
}

test_003_preflight_refusals() {
  open_world pf_refuse
  local arm first
  # no_direction: three shapes
  expect_refusal TEST-003 no_direction run_engine preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by human --origin "$RIDE"
  expect_refusal TEST-003 no_direction run_engine preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by human --direction '   ' --origin "$RIDE"
  expect_refusal TEST-003 no_direction run_engine preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by agent --direction 'merge it' --origin "$RIDE"
  # a missing expected head is a usage error, not a refusal
  run_engine preflight --pr "$PR" --directed-by human --direction 'x' --origin "$RIDE"
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-003 "missing --expect-head exited $ENG_RC, want 2"

  write_open_pr CLOSED false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  expect_refusal TEST-003 not_open pf
  want TEST-003 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"   # positive control: the read ran
  write_open_pr OPEN true "$HEAD_OID" CLEAN "$ROLLUP_OK"
  expect_refusal TEST-003 draft pf
  # a draft that is also blocked reports the first reason in the documented order
  write_open_pr OPEN true "$HEAD_OID" BLOCKED '[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE"}]'
  expect_refusal TEST-003 draft pf
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  expect_refusal TEST-003 head_changed run_engine preflight --pr "$PR" --expect-head 0123456789012345678901234567890123456789 --directed-by human --direction 'merge 433 please' --origin "$RIDE"
  for arm in '[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"FAILURE"}]' \
             '[{"__typename":"CheckRun","name":"a","status":"IN_PROGRESS","conclusion":""}]' \
             '[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"d","state":"PENDING"}]' \
             '[{"__typename":"StatusContext","context":"d","state":"FAILURE"}]' \
             '[{"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"CANCELLED"}]'; do
    write_open_pr OPEN false "$HEAD_OID" CLEAN "$arm"
    pf
    [[ "$ENG_RC" -eq 10 ]] || fail TEST-003 "checks_failing arm exited $ENG_RC, want 10"
  done
  for arm in BLOCKED BEHIND DIRTY UNSTABLE UNKNOWN HAS_HOOKS; do
    write_open_pr OPEN false "$HEAD_OID" "$arm" "$ROLLUP_OK"
    pf
    [[ "$ENG_RC" -eq 10 ]] || fail TEST-003 "not_mergeable arm exited $ENG_RC, want 10"
  done
  rm -f "$ORIGIN/docs/ai/decisions.jsonl"
  # SPEC-0227: live review check at preflight (Spec-AC-03) & lane-gate drops missing-sweep requirement (Spec-AC-04)
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  run cp "$RIDE/docs/ai/EVENTS.jsonl" "$W/events.with-sweep"
  { /usr/bin/grep -v '"pr_sweep"' "$W/events.with-sweep" || true; } > "$RIDE/docs/ai/EVENTS.jsonl"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-003 "missing pr_sweep event must not block preflight (Spec-AC-04), got $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-003 "$ENG_OUT" 'SWEEP-CHECK allowed'
  # Live unresolved review threads block preflight (Spec-AC-03):
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer"},"body":"Must fix this bug","path":"test.js","line":42}]}}]}}}}}\n' > "$GHD/review-threads.json"
  expect_refusal TEST-003 review_unresolved pf
  want TEST-003 "$ENG_OUT" 'unresolved review thread'
  want TEST-003 "$ENG_OUT" 'copilot'
  rm -f "$GHD/review-threads.json"
  # Contradictory record in EVENTS.jsonl is still caught:
  printf '%s\n' "${SWEEP_OK/\"threads_unresolved\":0/\"threads_unresolved\":3}" >> "$RIDE/docs/ai/EVENTS.jsonl"
  expect_refusal TEST-003 sweep_missing pf
  want TEST-003 "$ENG_OUT" 'contradictory-record'

  [[ ! -e "$ORIGIN/docs/ai/decisions.jsonl" ]] || fail TEST-003 'a refusal arm left a directed_merge record'
  # negative controls: a merged PR points at apply (exit 0), and the all-good
  # fixture is ready (exit 10) - the refusals above are not vacuous
  run cp "$W/events.with-sweep" "$RIDE/docs/ai/EVENTS.jsonl"
  write_pr_json MERGED "$MC"
  pf
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-003 "merged PR exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-003 "$ENG_OUT" already_merged
  want TEST-003 "$ENG_OUT" apply
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-003 "all-good control exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"

  # repo_mismatch: the PR belongs to another repository than the origin remote (NB-4)
  run git -C "$ORIGIN" remote set-url origin https://github.com/other/repo.git
  expect_refusal TEST-003 repo_mismatch pf
  want TEST-003 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"   # positive control: the read ran
  run git -C "$ORIGIN" remote set-url origin "$BARE"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-003 "repo_mismatch control exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"

  # the printed --match-head-commit and the sweep verdict bind to ONE commit (NB-1):
  # a local HEAD that is not the PR head is refused before the sweep is judged
  open_world pf_localhead
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-003 "local-head control exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  printf 'pushed from elsewhere\n' > "$RIDE/later.txt"
  run git -C "$RIDE" add later.txt
  run git -C "$RIDE" commit -qm 'a later local commit'
  expect_refusal TEST-003 head_changed pf
  want TEST-003 "$ENG_OUT" 'local'
  # and a sweep record that names an older head with real code changes since is denied by the real lane-gate
  open_world pf_stale
  first="$(git -C "$RIDE" rev-parse HEAD~1)" || fail SETUP 'older ride commit'
  { /usr/bin/grep -v '"pr_sweep"' "$RIDE/docs/ai/EVENTS.jsonl" || true; } > "$W/events.nosweep"
  run cp "$W/events.nosweep" "$RIDE/docs/ai/EVENTS.jsonl"
  printf '%s\n' "${SWEEP_OK/\"outcome\":\"swept\"/\"outcome\":\"swept\",\"head_sha\":\"$first\"}" >> "$RIDE/docs/ai/EVENTS.jsonl"
  expect_refusal TEST-003 sweep_missing pf
  want TEST-003 "$ENG_OUT" 'stale-head'
  echo 'PASS: TEST-003 preflight refusals'
}

test_004_preflight_ready() {
  open_world pf_ready
  local before cmd n dec after
  before="$(world_digest)"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-004 "ready exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  cmd="AAI_OPERATOR_MERGE=1 gh pr merge $PR --squash --match-head-commit $HEAD_OID"
  n="$(printf '%s\n' "$ENG_OUT" | { /usr/bin/grep -c 'gh pr merge' || true; })"
  [[ "$n" == 1 ]] || fail TEST-004 "output carries $n merge commands, want exactly 1: $ENG_OUT"
  [[ "$(printf '%s\n' "$ENG_OUT" | /usr/bin/grep 'gh pr merge')" == "$cmd" ]] || fail TEST-004 "printed command is not the pinned one: $ENG_OUT"
  unwanted TEST-004 "$ENG_OUT" '--admin'
  unwanted TEST-004 "$ENG_OUT" '--auto'
  unwanted TEST-004 "$ENG_OUT" '--delete-branch'
  # positive controls: the PR read, live review check, and the real sweep check all ran
  want TEST-004 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"
  want TEST-004 "$(cat "$GHD/gh-argv.log")" "api graphql"
  want TEST-004 "$ENG_OUT" 'SWEEP-CHECK allowed'
  # SPEC-0226: preflight writes nothing to decisions.jsonl; the fixture is completely unchanged
  dec="$ORIGIN/docs/ai/decisions.jsonl"
  [[ ! -f "$dec" ]] || fail TEST-004 'preflight created decisions.jsonl, want zero ledger writes'
  [[ "$(world_digest)" == "$before" ]] || fail TEST-004 'preflight changed the fixture'
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-004 "second ready exited $ENG_RC"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-004 'second preflight changed the fixture'
  # the merge happens, then apply keeps the dirty ride (spec-merge-cleanup-resolves-framework-friction D6)
  write_pr_json MERGED "$MC"
  # the appended sweep line alone is a movable ledger tail (spec-merge-cleanup-ride-leftovers); a stray edit makes the ride dirty
  printf 'stray edit\n' >> "$RIDE/README.md"
  run_engine apply --pr "$PR" --pid 4242 --direction 'merge 433 please'
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-004 "apply on the dirty ride exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-004 "$ENG_OUT" 'Kept: the worktree'
  [[ "$(tail -n 1 "$RIDE/README.md")" == 'stray edit' ]] || fail TEST-004 'the kept ride lost its stray edit'
  [[ ! -f "$dec" ]] || fail TEST-004 'apply on the dirty ride wrote to decisions.jsonl'
  git -C "$RIDE" show HEAD:README.md > "$W/readme.ride" || fail SETUP 'ride README blob'
  run cp "$W/readme.ride" "$RIDE/README.md"
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  assert_no_merge_call TEST-004
  # --json carries the same single command and the judged head
  pf --json
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-004 "json ready exited $ENG_RC"
  [[ "$(json_get "$ENG_OUT" 'j.command')" == "$cmd" ]] || fail TEST-004 'json command differs'
  [[ "$(json_get "$ENG_OUT" 'j.head')" == "$HEAD_OID" ]] || fail TEST-004 'json head differs'
  assert_no_merge_call TEST-004
  # plan on a merged PR never prints or runs a merge either
  write_pr_json MERGED "$MC"
  run_engine plan --pr "$PR" --origin "$ORIGIN"
  unwanted TEST-004 "$ENG_OUT" 'gh pr merge'
  assert_no_merge_call TEST-004
  echo 'PASS: TEST-004 preflight ready prints one pinned command'
}

test_015_downstream_layout() {
  local saved_engine="$ENGINE" tracked
  DOWNSTREAM=1 build_world "down stream"
  # installed layout: .aai and the skill trees exist on disk, are ignored, nothing under them is tracked
  [[ -f "$ORIGIN/.aai/scripts/merge-cleanup.mjs" ]] || fail TEST-015 'core install omitted the engine'
  [[ -f "$RIDE/.aai/scripts/merge-cleanup.mjs" ]] || fail TEST-015 'seed omitted the engine'
  tracked="$(git -C "$ORIGIN" ls-files -- .aai .claude/skills .agents/skills .codex/skills .gemini/skills | wc -l | tr -d ' ')"
  [[ "$tracked" == 0 ]] || fail TEST-015 "git ls-files lists $tracked path(s) under .aai or a skill tree"
  git -C "$ORIGIN" check-ignore -q .aai/scripts/merge-cleanup.mjs || fail TEST-015 '.aai is not ignored in the origin'
  git -C "$ORIGIN" check-ignore -q .claude/skills/x || fail TEST-015 'the Claude skill tree is not ignored in the origin'
  # dirty-worktree refusal from the installed engine
  printf 'edit\n' >> "$RIDE/README.md"
  ENGINE="$ORIGIN/.aai/scripts/merge-cleanup.mjs"
  run_engine apply --pr "$PR" --pid 4242 --json
  ENGINE="$saved_engine"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-015 "apply with a dirty worktree exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-015 "$ENG_OUT" '"reason":"worktree_dirty"'
  want TEST-015 "$(json_get "$ENG_OUT" 'j.remaining')" 'the worktree'
  [[ "$(step_status "$ENG_OUT" sync-base)" == done ]] || fail TEST-015 'the base sync did not finish beside the kept worktree'
  [[ "$(tail -n 1 "$RIDE/README.md")" == edit ]] || fail TEST-015 'the dirty worktree file changed'
  [[ -d "$RIDE" ]] || fail TEST-015 'dirty worktree was removed'
  git -C "$ORIGIN" show-ref --verify -q "refs/heads/$BRANCH" || fail TEST-015 'branch of a dirty worktree was deleted'
  # positive cleanup once the edit is undone (rewritten from the committed blob, never a restore command)
  git -C "$RIDE" show "HEAD:README.md" > "$W/readme.ride" || fail SETUP 'ride README blob'
  run cp "$W/readme.ride" "$RIDE/README.md"
  ENGINE="$ORIGIN/.aai/scripts/merge-cleanup.mjs"
  run_engine apply --pr "$PR" --pid 4242 --json
  ENGINE="$saved_engine"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-015 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ -f "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/worktree/docs/ai/STATE.yaml" ]] || fail TEST-015 'runtime was not archived'
  [[ "$(saved_reports | wc -l | tr -d ' ')" == 0 ]] || fail TEST-015 'report was saved to disk'
  [[ "$(step_status "$ENG_OUT" remove-worktree)" == done ]] || fail TEST-015 "worktree step reported $(step_status "$ENG_OUT" remove-worktree)"
  [[ "$(step_status "$ENG_OUT" delete-branch)" == done ]] || fail TEST-015 "branch step reported $(step_status "$ENG_OUT" delete-branch)"
  [[ ! -e "$RIDE" ]] || fail TEST-015 'worktree still present'
  if git -C "$ORIGIN" show-ref --verify -q "refs/heads/$BRANCH"; then fail TEST-015 'branch still present'; fi
  [[ -f "$ORIGIN/$NUM_ISSUE" && -f "$ORIGIN/$NUM_SPEC" ]] || fail TEST-015 'numbered docs missing from the origin'
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" && ! -e "$ORIGIN/$DRAFT_SPEC" ]] || fail TEST-015 'superseded draft still in the origin'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-015 'origin HEAD is not the merge commit'
  tracked="$(git -C "$ORIGIN" ls-files -- .aai | wc -l | tr -d ' ')"
  [[ "$tracked" == 0 ]] || fail TEST-015 "git ls-files lists $tracked path(s) under .aai after apply"
  assert_no_merge_call TEST-015
  echo 'PASS: TEST-015 downstream installed layout'
}

# ---------------------------------------------------------------------------
# spec-merge-direction-signs-amendments, batch A: the sign-amendments apply step
# (TEST-018), its authority guard (TEST-020) and its record filter (TEST-021).
# Records are seeded through the real spec-amend.mjs add and read back through
# the real spec-amend.mjs list --json, never by reading overlay text (seam S1).
SPEC_AMEND="$ROOT/.aai/scripts/spec-amend.mjs"
DEC='docs/ai/decisions.jsonl'
ANSWER='merge 433 please'

# amend_add <checkout> <spec-amend add args...>: the real writer, ledger in that checkout.
amend_add() {
  local d="$1"
  shift
  [[ -n "$d" && "$d" = /* ]] || fail SETUP 'amend_add checkout'
  ( cd "$d" && env -u AAI_ROLE node "$SPEC_AMEND" add --ledger "$d/$DEC" "$@" >/dev/null 2>&1 ) || fail SETUP "spec-amend add $*"
}
# amend_rows <checkout>: list --json of that checkout's ledger.
amend_rows() {
  [[ -n "$1" && "$1" = /* ]] || fail SETUP 'amend_rows checkout'
  ( cd "$1" && env -u AAI_ROLE node "$SPEC_AMEND" list --json --ledger "$1/$DEC" ) || fail SETUP "spec-amend list --json in $1"
}
# row_of <rows json> <record key>: that record's list --json row, serialised.
row_of() { json_get "$1" "JSON.stringify(j.items.find(i=>i.record_key===\"$2\")??null)"; }
# unsigned_contract_keys <rows json>: record keys of unsigned contract rows, space-separated.
unsigned_contract_keys() { json_get "$1" 'j.items.filter(i=>i.amendment_class==="contract"&&i.bucket!=="signed").map(i=>i.record_key).join(" ")'; }
# overlays <ledger>: the record-addressed classification overlays, one JSON per line.
overlays() { node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");for(const l of t.split("\n").filter(Boolean)){let r;try{r=JSON.parse(l)}catch{continue}if(r.type==="spec_amendment_classification"&&r.classifies_record)console.log(JSON.stringify(r))}' "$1"; }
type_count() { node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8");let n=0;for(const l of t.split("\n").filter(Boolean)){try{if(JSON.parse(l).type===process.argv[2])n++}catch{}}console.log(n)' "$1" "$2"; }

# The ride's two contract amendments: one keyed on the issue id, one on the spec id.
seed_ride_018() {
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'ride contract a' --why 'scope grew a' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$SPEC_ID" --what 'ride contract b' --why 'scope grew b' --signoff none
  run git -C "$RIDE" add "$DEC"
}

# apply_stop_after_sync <test id>: apply under the test-seam guard, stopped right after sync-base.
apply_stop_after_sync() {
  local rc=0
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_STOP_AFTER=sync-base node "$ENGINE" apply --pr "$PR" --pid 4242 --json >"$W/engine.out" 2>"$W/engine.err" ) || rc=$?
  [[ "$rc" -eq 4 ]] || fail "$1" "stop after sync-base exited $rc, want 4 ($(cat "$W/engine.out") $(cat "$W/engine.err"))"
}

test_018_direction_signs_ride_amendments() {
  local eng_content out rc=0
  eng_content="$(cat "$ENGINE")"
  unwanted TEST-018 "$eng_content" "SIGN_STEP_ID"
  unwanted TEST-018 "$eng_content" "'sign-amendments'"
  unwanted TEST-018 "$eng_content" "signAmendments"
  unwanted TEST-018 "$eng_content" "runSignMerged"
  unwanted TEST-018 "$eng_content" "preflightSigns"
  unwanted TEST-018 "$eng_content" "appendDirectedMerge"
  out="$(node "$ENGINE" sign-merged 2>&1)" || rc=$?
  [[ "$rc" -eq 2 ]] || fail TEST-018 "sign-merged must exit 2 as unknown command, got $rc: $out"
  echo 'PASS: TEST-018 sign-amendments step and sign-merged helpers removed from merge-cleanup'
}

test_020_no_human_direction_signs_nothing() {
  local sha_pre sha_post
  AMEND_WORLD=1 RIDE_SEED=seed_ride_018 build_world "zero_writes_020"
  write_pr_json MERGED "$MC"
  apply_stop_after_sync TEST-020
  sha_pre="$(sha_of "$ORIGIN/$DEC")"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-020 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  sha_post="$(sha_of "$ORIGIN/$DEC")"
  [[ "$sha_pre" == "$sha_post" ]] || fail TEST-020 "decisions.jsonl was modified after sync-base: before $sha_pre after $sha_post"
  [[ "$(overlays "$ORIGIN/$DEC" | wc -l | tr -d ' ')" == 0 ]] || fail TEST-020 "an overlay was written to decisions.jsonl"
  [[ -z "$(git -C "$ORIGIN" status --porcelain "$DEC")" ]] || fail TEST-020 "decisions.jsonl is dirty in git status after apply"
  echo 'PASS: TEST-020 apply leaves decisions.jsonl untouched'
}

test_027_signature_cites_the_current_direction() {
  local sha_pre sha_post
  AMEND_WORLD=1 RIDE_SEED=seed_ride_018 build_world dir027_test
  write_pr_json MERGED "$MC"
  apply_stop_after_sync TEST-027
  sha_pre="$(sha_of "$ORIGIN/$DEC")"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "test direction"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-027 "apply exited $ENG_RC"
  sha_post="$(sha_of "$ORIGIN/$DEC")"
  [[ "$sha_pre" == "$sha_post" ]] || fail TEST-027 "decisions.jsonl was modified after sync-base"
  [[ -z "$(git -C "$ORIGIN" status --porcelain "$DEC")" ]] || fail TEST-027 "decisions.jsonl is dirty in git status after apply"
  echo 'PASS: TEST-027 apply with direction makes zero ledger writes'
}

seed_ride_021() {
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'measured differently' --why 'cell did not redden' --signoff none --class measurement
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$SPEC_ID" --what 'already signed' --why 'owner agreed' --signoff owner --authority 'owner said yes in chat'
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref 'ISSUE-0001' --what 'ride contract by display id' --why 'scope grew' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref 'other-ref' --what 'another ride contract' --why 'not this PR' --signoff none
  run git -C "$RIDE" add "$DEC"
}

test_021_signs_only_unsigned_contract_of_the_ride() {
  local sha_pre sha_post
  AMEND_WORLD=1 RIDE_SEED=seed_ride_021 build_world sign_021
  run_engine plan --pr "$PR" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-021 "plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-021 "$ENG_OUT" '"id":"sign-amendments"'
  write_pr_json MERGED "$MC"
  apply_stop_after_sync TEST-021
  sha_pre="$(sha_of "$ORIGIN/$DEC")"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-021 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-021 "$ENG_OUT" '"id":"sign-amendments"'
  sha_post="$(sha_of "$ORIGIN/$DEC")"
  [[ "$sha_pre" == "$sha_post" ]] || fail TEST-021 "apply modified decisions.jsonl"
  [[ -z "$(git -C "$ORIGIN" status --porcelain "$DEC")" ]] || fail TEST-021 "decisions.jsonl is dirty in git status after apply"
  echo 'PASS: TEST-021 sign-amendments step absent in plan and apply'
}

# ---------------------------------------------------------------------------
# spec-merge-direction-signs-amendments, batch B: trackers close, a second run is a
# no-op, a killed run resumes (TEST-022); preflight lists what the merge signs
# (TEST-023); the installed downstream engine signs too (TEST-019).
FOLLOW_UPS="$ROOT/.aai/scripts/follow-ups.mjs"

# fu_rows <checkout>: follow-ups list --json (every status) of that checkout's ledger.
fu_rows() {
  [[ -n "$1" && "$1" = /* ]] || fail SETUP 'fu_rows checkout'
  ( cd "$1" && env -u AAI_ROLE node "$FOLLOW_UPS" list --status all --json --ledger "$1/$DEC" ) || fail SETUP "follow-ups list --json in $1"
}
# fu_status <fu rows json> <id>: that item's status, or empty.
fu_status() { json_get "$1" "j.items.find(i=>i.id===\"$2\")?.status??\"\""; }
# amend_trackers <fu rows json>: the fu-amend-* items as id:status, sorted.
amend_trackers() { json_get "$1" 'j.items.filter(i=>i.id.startsWith("fu-amend-")).map(i=>i.id+":"+i.status).sort().join(" ")'; }
# amend_projection <rows json>: every record as ref|what|bucket|signoff, sorted (record keys
# carry the record ts, so two worlds are compared by content, not by key).
amend_projection() { json_get "$1" 'j.items.map(i=>[i.ref_id,i.what,i.bucket,i.owner_signoff].join("|")).sort().join(";")'; }
# strict_rc <checkout>: exit code of spec-amend list --strict over that checkout's ledger.
strict_rc() {
  local rc=0
  [[ -n "$1" && "$1" = /* ]] || fail SETUP 'strict_rc checkout'
  ( cd "$1" && env -u AAI_ROLE node "$SPEC_AMEND" list --strict --ledger "$1/$DEC" >/dev/null 2>&1 ) || rc=$?
  echo "$rc"
}

# Tracker A (spec foo) holds two records of the ride; tracker B (spec bar) holds one record
# of the ride and one of the unmerged ref `bar`.
seed_ride_022() {
  printf -- '---\nid: spec-bar\ntype: spec\nnumber: null\nstatus: implementing\nlinks:\n  requirement: bar\n  pr: []\n  commits: []\n---\n\n# Spec bar\n' > "$W/bar-spec.md"
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'tracker a one' --why 'scope grew a1' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$SPEC_ID" --what 'tracker a two' --why 'scope grew a2' --signoff none
  amend_add "$RIDE" --spec "$W/bar-spec.md" --ref "$ISSUE_ID" --what 'tracker b ride' --why 'scope grew b1' --signoff none
  amend_add "$RIDE" --spec "$W/bar-spec.md" --ref 'bar' --what 'tracker b unmerged' --why 'scope grew b2' --signoff none
  run git -C "$RIDE" add "$DEC"
}

test_022_trackers_close_idempotent_resumable() {
  local sha1 sha2
  AMEND_WORLD=1 RIDE_SEED=seed_ride_022 build_world sign_022
  write_pr_json MERGED "$MC"
  apply_stop_after_sync TEST-022
  sha1="$(sha_of "$ORIGIN/$DEC")"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-022 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  sha2="$(sha_of "$ORIGIN/$DEC")"
  [[ "$sha1" == "$sha2" ]] || fail TEST-022 "decisions.jsonl changed during first apply"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-022 "second apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha2" ]] || fail TEST-022 "decisions.jsonl changed during second apply"
  [[ -z "$(git -C "$ORIGIN" status --porcelain "$DEC")" ]] || fail TEST-022 "decisions.jsonl is dirty in git status after apply"
  echo 'PASS: TEST-022 apply is idempotent with zero ledger writes'
}

# The ride: two unsigned contract records and one measurement record.
seed_ride_023() {
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'preflight contract a' --why 'scope grew a' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$SPEC_ID" --what 'preflight contract b' --why 'scope grew b' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'preflight measurement' --why 'cell did not redden' --signoff none --class measurement
  run git -C "$RIDE" add "$DEC"
}

test_023_preflight_lists_signs_on_merge() {
  local sha_pre sha_post
  AMEND_WORLD=1 RIDE_SEED=seed_ride_023 open_world pf_sign_023
  sha_pre="$(sha_of "$ORIGIN/$DEC")"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-023 "preflight exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-023 "$ENG_OUT" 'signs on merge:'
  sha_post="$(sha_of "$ORIGIN/$DEC")"
  [[ "$sha_pre" == "$sha_post" ]] || fail TEST-023 "preflight wrote to decisions.jsonl"
  pf --json
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-023 "json preflight exited $ENG_RC"
  unwanted TEST-023 "$ENG_OUT" 'signs_on_merge'
  echo 'PASS: TEST-023 preflight excludes signs on merge and makes zero ledger writes'
}

seed_ride_019() {
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'downstream contract' --why 'scope grew' --signoff none
  run git -C "$RIDE" add "$DEC"
}

test_019_downstream_signs() {
  local saved_engine="$ENGINE" sha_pre sha_post
  AMEND_WORLD=1 DOWNSTREAM=1 RIDE_SEED=seed_ride_019 build_world "down stream test"
  ENGINE="$ORIGIN/.aai/scripts/merge-cleanup.mjs"
  write_pr_json MERGED "$MC"
  apply_stop_after_sync TEST-019
  sha_pre="$(sha_of "$ORIGIN/$DEC")"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  ENGINE="$saved_engine"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-019 "downstream apply exited $ENG_RC"
  sha_post="$(sha_of "$ORIGIN/$DEC")"
  [[ "$sha_pre" == "$sha_post" ]] || fail TEST-019 "downstream apply modified decisions.jsonl"
  [[ -z "$(git -C "$ORIGIN" status --porcelain "$DEC")" ]] || fail TEST-019 "decisions.jsonl is dirty in git status after apply"
  echo 'PASS: TEST-019 downstream engine makes zero ledger writes'
}

# ---------------------------------------------------------------------------
# spec-merge-direction-signs-amendments, batch C: the backlog command (TEST-025),
# the canon (TEST-024) and the live-ledger contract (TEST-026).

# Ride X is foo (merged by the squash commit); ride Y is other-item (in flight on main).
# T1 holds two X records (issue id, spec id); T2 one X record (display id) and one Y record;
# T3 one X record and is excluded. A measurement record of X is never signed.
seed_ride_025() {
  local t
  for t in t1 t2 t3; do
    printf -- '---\nid: spec-%s\ntype: spec\nnumber: null\nstatus: implementing\nlinks:\n  requirement: %s\n  pr: []\n  commits: []\n---\n\n# Spec %s\n' "$t" "$t" "$t" > "$W/$t-spec.md"
  done
  amend_add "$RIDE" --spec "$W/t1-spec.md" --ref "$ISSUE_ID" --what 'backlog x one' --why 'scope grew x1' --signoff none
  amend_add "$RIDE" --spec "$W/t1-spec.md" --ref "$SPEC_ID" --what 'backlog x two' --why 'scope grew x2' --signoff none
  amend_add "$RIDE" --spec "$W/t2-spec.md" --ref 'ISSUE-0001' --what 'backlog x three' --why 'scope grew x3' --signoff none
  amend_add "$RIDE" --spec "$W/t2-spec.md" --ref 'other-item' --what 'backlog y one' --why 'scope grew y1' --signoff none
  amend_add "$RIDE" --spec "$W/t3-spec.md" --ref "$ISSUE_ID" --what 'backlog x excluded' --why 'scope grew x4' --signoff none
  amend_add "$RIDE" --spec "$W/t1-spec.md" --ref "$ISSUE_ID" --what 'backlog x measured' --why 'cell did not redden' --signoff none --class measurement
  run git -C "$RIDE" add "$DEC"
}

AUTH_TS='2026-10-10T05:00:00Z'
AUTH_ANSWER='Merge = podpis + backlog (Recommended)'

# sm <args...>: sign-merged from the origin checkout (no gh call is made or allowed).
sm() { run_engine sign-merged --exclude fu-amend-spec-t3 "$@"; }

test_025_sign_merged_backlog() {
  local out rc=0
  out="$(node "$ENGINE" sign-merged 2>&1)" || rc=$?
  [[ "$rc" -eq 2 ]] || fail TEST-025 "sign-merged exited $rc, want 2 (out: $out)"
  want TEST-025 "$out" 'unknown or missing mode: sign-merged'
  out="$(node "$ENGINE" --help 2>&1)" || true
  unwanted TEST-025 "$out" 'sign-merged'
  echo 'PASS: TEST-025 sign-merged subcommand is removed and exits 2'
}

# TEST-024: prompts are free of dead signing instructions
test_024_canon_merge_direction_signs() {
  local f text credit n=0
  for f in .aai/ROLE_COMMON.md .aai/SKILL_MERGE.prompt.md .aai/SKILL_SHIP.prompt.md .aai/SKILL_PR.prompt.md .aai/system/AUTONOMOUS_LOOP.md; do
    [[ -s "$ROOT/$f" ]] || fail TEST-024 "canon file missing: $f"
    text="$(cat "$ROOT/$f")"
    unwanted TEST-024 "$text" 'owed sign-offs'
    n=$((n + 1))
  done
  [[ "$n" == 5 ]] || fail TEST-024 "read $n canon files, want 5 (positive control)"
  unwanted TEST-024 "$(cat "$ROOT/.aai/SKILL_MERGE.prompt.md")" 'signs on merge:'
  unwanted TEST-024 "$(cat "$ROOT/.aai/SKILL_MERGE.prompt.md")" 'sign-amendments'
  unwanted TEST-024 "$(cat "$ROOT/.aai/SKILL_PR.prompt.md")" 'Signs on merge'
  unwanted TEST-024 "$(cat "$ROOT/.aai/SKILL_PR.prompt.md")" 'signs on merge:'
  credit="$(/usr/bin/grep -F 'JUSTIFIED_ADDITIONS+=( "' "$ROOT/tests/skills/lib/prompt-diet-ledger.sh" | sed -n 's/^JUSTIFIED_ADDITIONS+=( "\([0-9][0-9]*\) merge-direction-signs-amendments .*/\1/p' | awk 'NR == 1')"
  [[ -n "$credit" && "$credit" -gt 0 ]] || fail TEST-024 'the prompt-diet ledger carries no positive entry keyed merge-direction-signs-amendments'
  echo 'PASS: TEST-024 prompts are free of dead signing instructions'
}

test_026_backlog_signed_on_live_ledger() {
  # Execute this tests actual live verdict against real Git/object fixtures.
  # A >=300 signed backlog must not conceal one merged-but-unsigned record.
  AAI_PREDICATE_SUITE="$ROOT/tests/skills/test-aai-merge-cleanup.sh" AAI_PREDICATE_MODEL="$ROOT/.aai/scripts/lib/docs-model.mjs" AAI_PREDICATE_SCRATCH="${AAI_PREDICATE_SCRATCH:-$SCRATCH}" node <<'JS' || fail TEST-026 'merged predicate fixture assertions failed'
const fs = require("fs");
const path = require("path");
const {execFileSync, spawnSync} = require("child_process");
const scratch = process.env.AAI_PREDICATE_SCRATCH;
if (!scratch || !path.isAbsolute(scratch)) throw Error("absolute predicate scratch required");
fs.mkdirSync(scratch, {recursive:true});
const fixture = fs.mkdtempSync(path.join(scratch, "merged-predicate."));
try {
  const source = fs.readFileSync(process.env.AAI_PREDICATE_SUITE, "utf8");
  const start = source.indexOf("import fs from \"node:fs\";\nimport {execFileSync} from \"node:child_process\";");
  const end = source.indexOf("\n' \"$d/live-rows.json\"", start);
  if (start < 0 || end < 0) throw Error("live verdict extraction failed");
  const program = source.slice(start, end);
  const git = (...args) => execFileSync("git", args, {cwd:fixture, encoding:"utf8"}).trim();
  git("init", "-q", "-b", "main"); git("config", "user.name", "predicate-fixture");
  git("config", "user.email", "predicate@example.invalid"); git("config", "core.hooksPath", "/dev/null");
  fs.mkdirSync(path.join(fixture,"docs"));
  // Corpus-shaped frontmatter is committed and consumed by the actual verdict.
  const cases = [
    ["merged-inline", "done", "  pr: [465]\n  commits: []\n", "", true],
    ["merged-block", "done", "  pr:\n    - 465\n  commits: []\n", "", true],
    ["empty-inline", "done", "  pr: []\n  commits: []\n", "", false],
    ["empty-inline-spaced", "done", "  pr: [ ]\n  commits: []\n", "", false],
    ["empty-inline-quoted", "done", "  pr: [\" \"]\n  commits: []\n", "", false],
    ["empty-block-quoted", "done", "  pr:\n    - \" \"\n  commits: []\n", "", false],
    ["empty-block", "done", "  pr:\n  commits: []\n", "", false],
    ["null-inline", "done", "  pr: null\n  commits: []\n", "", false],
    ["tilde-inline", "done", "  pr: ~\n  commits: []\n", "", false],
    ["missing-pr", "done", "  commits: []\n", "", false],
    ["sibling-list", "done", "  pr:\n  commits:\n    - abcdef\n", "", false],
    ["other-key", "done", "  other_pr: [465]\n  commits: []\n", "", false],
    ["body-decoy", "done", "  commits: []\n", "\nExample only:\n  pr: [465]\n", false],
    ["nondone-inline", "implementing", "  pr: [465]\n  commits: []\n", "", false],
    ["nondone-block", "implementing", "  pr:\n    - 465\n  commits: []\n", "", false],
    ["empty-block-item", "done", "  pr:\n    - \n  commits: []\n", "", false],
  ];
  for (const [ref, status, links, body] of cases) {
    fs.writeFileSync(path.join(fixture,"docs",ref+".md"),`---\nid: ${ref}\ntype: issue\nstatus: ${status}\nlinks:\n${links}---\n# Fixture\n${body}`);
  }
  // Deliberate import closure: copied model has only node: stdlib imports.
  const model = path.join(fixture,".aai/scripts/lib/docs-model.mjs");
  fs.mkdirSync(path.dirname(model), {recursive:true});
  fs.copyFileSync(process.env.AAI_PREDICATE_MODEL, model);
  git("add", "--", "docs"); git("commit", "-qm", "fixture docs");
  git("update-ref", "refs/remotes/origin/main", "HEAD");
  const signed = Array.from({length:300}, (_,i) => ({amendment_class:"contract",ref_id:"signed-"+i,bucket:"signed",record_key:"signed-"+i}));
  const unmerged = {amendment_class:"contract",ref_id:"routing-tables-have-an-owner-and-a-seam",bucket:"unsigned-tracked",record_key:"unmerged"};
  fs.writeFileSync(path.join(fixture,"fu.json"), JSON.stringify({items:[]}));
  let failures = 0;
  function check(label, extra, wanted, message) {
    fs.writeFileSync(path.join(fixture,"rows.json"), JSON.stringify({items:[...signed, unmerged, ...extra]}));
    const result = spawnSync(process.execPath,["--input-type=module","-e",program,path.join(fixture,"rows.json"),path.join(fixture,"fu.json")],{cwd:fixture,encoding:"utf8",env:{...process.env,AAI_MERGED_DOC_MODEL:model}});
    const output = (result.stdout || "") + (result.stderr || "");
    const ok = result.status === wanted && output.includes(message);
    console.log(`TEST-026 ${ok ? "PASS" : "FAIL"} ${label} expected=${wanted} exit=${result.status}\n${output.trim()}`);
    if (!ok) failures++;
  }
  const unsigned = ref => ({amendment_class:"contract",ref_id:ref,bucket:"unsigned-tracked",record_key:ref});
  check("signed backlog positive control",[],0,"OK 300 merged contract records");
  for (const [ref, , , , merged] of cases) {
    check((merged ? "TEST-005 merged " : "TEST-006 negative ")+ref,[unsigned(ref)],merged ? 1 : 0,merged ? "merged contract amendments not signed" : "OK 300 merged contract records");
  }
  check("TEST-006 absent doc is valid unmerged",[unsigned("absent-doc")],0,"OK 300 merged contract records");
  git("update-ref", "-d", "refs/remotes/origin/main");
  check("TEST-006 unreadable base cannot attest unmerged",[unsigned("missing-pr")],1,"cannot determine merge status");
  git("update-ref", "refs/remotes/origin/main", "HEAD");
  const blob=git("rev-parse", "origin/main:docs/merged-block.md");
  fs.unlinkSync(path.join(fixture,".git/objects",blob.slice(0,2),blob.slice(2)));
  check("TEST-006 unreadable actual blob cannot attest unmerged",[unsigned("merged-block")],1,"cannot determine merge status");
  console.log(`merged predicate assertions=${cases.length + 4} failures=${failures} fixture=${fixture}`);
  process.exitCode = failures ? 1 : 0;
} finally { fs.rmSync(fixture,{recursive:true,force:true}); }
JS
  local d="$SCRATCH/live_026" live="$ROOT/docs/ai/decisions.jsonl" verdict rc=0
  run mkdir -p "$d"
  [[ -s "$live" ]] || fail TEST-026 "the live ledger is missing: $live"
  ( cd "$ROOT" && env -u AAI_ROLE node "$SPEC_AMEND" list --json --ledger "$live" ) > "$d/live-rows.json" || fail TEST-026 'spec-amend list --json over the live ledger failed'
  ( cd "$ROOT" && env -u AAI_ROLE node "$FOLLOW_UPS" list --status all --json --ledger "$live" ) > "$d/live-fu.json" || fail TEST-026 'follow-ups list --json over the live ledger failed'
  verdict="$(AAI_MERGED_DOC_MODEL="$ROOT/.aai/scripts/lib/docs-model.mjs" node --input-type=module -e '
import fs from "node:fs";
import {execFileSync} from "node:child_process";
import {pathToFileURL} from "node:url";
const {parseFrontmatter} = await import(pathToFileURL(process.env.AAI_MERGED_DOC_MODEL).href);
const rows = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).items;
const fu = JSON.parse(fs.readFileSync(process.argv[2], "utf8")).items;
const unmergedRef = "routing-tables-have-an-owner-and-a-seam";
const mergedCache = new Map();
function rideMerged(ref) {
  if (mergedCache.has(ref)) return mergedCache.get(ref);
  let yes = false;
  try {
    let listed;
    try {
      listed = execFileSync("git", ["grep", "-l", `id: ${ref}`, "origin/main", "--", "docs"], {encoding:"utf8"}).split("\n").filter(Boolean);
    } catch (error) {
      if (error.status === 1 && !String(error.stderr || "").trim()) listed = []; // Only a diagnostic-free no-match is a valid negative.
      else throw error;
    }
    for (const path of listed) {
      const text = execFileSync("git", ["show", path], {encoding:"utf8"});
      const fm = parseFrontmatter(text);
      const raw = fm?.links?.pr;
      // The existing model returns nested inline lists as strings, and block
      // lists as arrays. Normalize only this observed list representation.
      const values = Array.isArray(raw) ? raw : typeof raw === "string" && /^\[.*\]$/.test(raw) ? raw.slice(1,-1).split(",") : [];
      const prItems = values.some(value => !["", "null", "~"].includes(String(value).trim().replace(/^["\x27]|["\x27]$/g, "").trim()));
      if (fm?.id === ref && fm.status === "done" && prItems) yes = true;
    }
  } catch (error) { throw new Error(`cannot determine merge status for ${ref}: ${error.message}`); }
  mergedCache.set(ref, yes);
  return yes;
}
const mergedContract = rows.filter(r => r.amendment_class === "contract" && r.ref_id !== unmergedRef && (r.bucket === "signed" || rideMerged(r.ref_id)));
const unsignedMerged = rows.filter(r => r.amendment_class === "contract" && r.ref_id !== unmergedRef && r.bucket !== "signed" && rideMerged(r.ref_id));
if (unsignedMerged.length > 0) {
  console.log(`FAIL ${unsignedMerged.length} merged contract amendments not signed: ${unsignedMerged.map(u => u.record_key).slice(0, 5).join(", ")}`);
  process.exit(1);
}
if (mergedContract.length < 300) {
  console.log(`FAIL only ${mergedContract.length} merged contract amendments found, want >= 300`);
  process.exit(1);
}
const unmerged = rows.filter(r => r.ref_id === unmergedRef && r.amendment_class === "contract");
if (unmerged.length === 0 || !unmerged.every(r => r.bucket === "unsigned-tracked")) {
  console.log(`FAIL unmerged ref ${unmergedRef} must remain unsigned-tracked`);
  process.exit(1);
}
console.log(`OK ${mergedContract.length} merged contract records fold to signed, unmerged preserved`);
' "$d/live-rows.json" "$d/live-fu.json")" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-026 "$verdict"
  ( cd "$ROOT" && env -u AAI_ROLE node "$SPEC_AMEND" list --strict --ledger "$live" >/dev/null 2>&1 ) || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-026 "spec-amend list --strict over the live ledger exited $rc"
  echo "PASS: TEST-026 the merged-ride backlog is signed on the live ledger ($verdict)"
}

# ---------------------------------------------------------------------------
# B4b: the prompt and its wrappers (TEST-001), the executed bash block
# (TEST-002), and the companion wiring (TEST-017).
PROMPT="$ROOT/.aai/SKILL_MERGE.prompt.md"

# block_of <begin-marker> <end-marker> <file>: the lines strictly between two marker lines.
block_of() {
  awk -v b="# $1" -v e="# $2" '
    { line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t\r]+$/, "", line) }
    line == b { f = 1; next }
    line == e { f = 0; next }
    f' "$3"
}
# section_of <start-regex> <stop-regex> <file>: from the first start line up to (not including) the next stop line.
section_of() { awk -v s="$1" -v e="$2" '$0 ~ s { f = 1; print; next } f && $0 ~ e { exit } f' "$3"; }

test_001_wrappers_and_pointers() {
  local tree sect out rc=0
  for tree in .claude .agents .codex .gemini; do
    [[ -f "$ROOT/$tree/skills/aai-merge/SKILL.md" ]] || fail TEST-001 "wrapper missing in $tree/skills/aai-merge"
    want TEST-001 "$(cat "$ROOT/$tree/skills/aai-merge/SKILL.md")" '.aai/SKILL_MERGE.prompt.md'
  done
  [[ -f "$PROMPT" ]] || fail TEST-001 'the core prompt .aai/SKILL_MERGE.prompt.md is missing'
  out="$(node "$ROOT/.aai/scripts/sync-harness-skills.mjs" --check 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-001 "sync-harness-skills --check exited $rc: $out"
  # the three completion pointers, each inside its own section
  sect="$(section_of '^6\. MERGE BOUNDARY' '^7\. ' "$ROOT/.aai/SKILL_PR.prompt.md")"
  [[ -n "$sect" ]] || fail TEST-001 'SKILL_PR step 6 section not found (positive control)'
  want TEST-001 "$sect" '/aai-merge'
  sect="$(section_of '^6\. MERGE CHECKPOINT' '^7\. ' "$ROOT/.aai/SKILL_SHIP.prompt.md")"
  [[ -n "$sect" ]] || fail TEST-001 'SKILL_SHIP step 6 section not found (positive control)'
  want TEST-001 "$sect" '/aai-merge'
  sect="$(section_of '^### Command: Cleanup Worktree' '^### ' "$ROOT/.aai/SKILL_WORKTREE.prompt.md")"
  [[ -n "$sect" ]] || fail TEST-001 'SKILL_WORKTREE cleanup section not found (positive control)'
  want TEST-001 "$sect" '/aai-merge'
  # the engine's own help lists the three modes
  out="$(node "$ENGINE" --help 2>&1)" || fail TEST-001 'engine --help failed'
  want TEST-001 "$out" 'preflight'; want TEST-001 "$out" 'plan'; want TEST-001 "$out" 'apply'
  # the prompt carries both marked blocks, and neither block can merge
  [[ -n "$(block_of AAI_MERGE_BEGIN AAI_MERGE_END "$PROMPT")" ]] || fail TEST-001 'AAI_MERGE bash block missing from the prompt'
  [[ -n "$(block_of AAI_MERGE_PS_BEGIN AAI_MERGE_PS_END "$PROMPT")" ]] || fail TEST-001 'AAI_MERGE_PS block missing from the prompt'
  for sect in "$(block_of AAI_MERGE_BEGIN AAI_MERGE_END "$PROMPT")" "$(block_of AAI_MERGE_PS_BEGIN AAI_MERGE_PS_END "$PROMPT")"; do
    unwanted TEST-001 "$sect" 'pr merge'
    unwanted TEST-001 "$sect" '--admin'
    unwanted TEST-001 "$sect" '--auto'
    unwanted TEST-001 "$sect" '--force'
  done
  echo 'PASS: TEST-001 wrappers and completion pointers'
}

# run_block <file> <cwd> [shell]: executes an extracted prompt block with the gh stub first on PATH.
run_block() {
  ENG_RC=0
  [[ -n "$2" && "$2" = /* ]] || fail SETUP 'block cwd'
  ( cd "$2" && AAI_PR="$PR" PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" "${3:-bash}" "$1" >"$W/block.out" 2>"$W/block.err" ) || ENG_RC=$?
  ENG_OUT="$(cat "$W/block.out")"
  ENG_ERR="$(cat "$W/block.err")"
}

# block_case <shell> <world name>: the extracted bash block, run by that shell.
block_case() {
  local sh="$1"
  [[ -f "$PROMPT" ]] || fail TEST-002 "the core prompt is missing: $PROMPT"
  DOWNSTREAM=1 build_world "$2"
  block_of AAI_MERGE_BEGIN AAI_MERGE_END "$PROMPT" > "$W/merge.block.sh"
  [[ -s "$W/merge.block.sh" ]] || fail TEST-002 'AAI_MERGE bash block is empty or missing'
  local before
  # negative control: no PR number is a usage failure that writes nothing
  before="$(world_digest)"
  ( cd "$RIDE" && env -u AAI_PR PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" "$sh" "$W/merge.block.sh" >"$W/block.out" 2>"$W/block.err" ) && ENG_RC=0 || ENG_RC=$?
  [[ "$ENG_RC" -ne 0 ]] || fail TEST-002 "the $sh block ran without AAI_PR"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-002 'the block without AAI_PR changed the fixture'
  # positive: run from INSIDE the ride worktree, the block resolves the origin itself
  AAI_DIRECTION='merge 433 now, owner said so' run_block "$W/merge.block.sh" "$RIDE" "$sh"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-002 "$sh block exited $ENG_RC (out: $ENG_OUT err: $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-002 'the ride worktree still exists'
  if git -C "$ORIGIN" show-ref --verify -q "refs/heads/$BRANCH"; then fail TEST-002 'the ride branch still exists'; fi
  [[ -f "$ORIGIN/$NUM_ISSUE" && -f "$ORIGIN/$NUM_SPEC" ]] || fail TEST-002 'numbered docs missing from the origin'
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" && ! -e "$ORIGIN/$DRAFT_SPEC" ]] || fail TEST-002 'superseded drafts still in the origin'
  [[ -s "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/manifest.jsonl" ]] || fail TEST-002 'no archive manifest'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-002 'origin HEAD is not the merge commit'
  # SPEC-0226: zero writes to decisions.jsonl during merge-cleanup
  [[ ! -e "$ORIGIN/docs/ai/decisions.jsonl" ]] || fail TEST-002 'prompt block wrote to decisions.jsonl'
  # spec-merge-cleanup-delete-remote-branch D9: the block also deleted the merged remote branch
  if git -C "$BARE" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then fail TEST-002 'the merged remote branch still exists on the bare origin'; fi
  assert_no_merge_call TEST-002
}

test_002_prompt_block_runs_cleanup() {
  block_case bash 'prompt block'
  # D3/D9: the owner's direction is one word per flag in zsh too (the Claude Code Bash tool
  # runs zsh on macOS). The skip is by name, and only when zsh is genuinely absent.
  if command -v zsh >/dev/null 2>&1; then block_case zsh 'prompt block zsh'
  else echo 'SKIP: TEST-002 zsh arm (zsh not installed)'
  fi
  echo 'PASS: TEST-002 the prompt block runs cleanup'
}

test_017_companion_wiring() {
  local profiles map yml sect
  profiles="$(section_of '^core:' '^[a-z_]+:' "$ROOT/.aai/system/PROFILES.yaml")"
  [[ -n "$profiles" ]] || fail TEST-017 'PROFILES core section not found (positive control)'
  want TEST-017 "$profiles" '- .aai/SKILL_MERGE.prompt.md'
  want TEST-017 "$profiles" '- .aai/scripts/merge-cleanup.mjs'
  map="$(section_of '^  aai-merge-cleanup:' '^  [a-zA-Z]' "$ROOT/tests/skills/suite-map.yaml")"
  [[ -n "$map" ]] || fail TEST-017 'suite-map.yaml has no aai-merge-cleanup row'
  want TEST-017 "$map" '.aai/scripts/merge-cleanup.mjs'
  want TEST-017 "$map" '.aai/SKILL_MERGE.prompt.md'
  want TEST-017 "$map" 'tests/skills/test-aai-merge-cleanup.sh'
  want TEST-017 "$map" 'tests/skills/aai-merge-cleanup.Tests.ps1'
  yml="$ROOT/.github/workflows/ps1-quality.yml"
  [[ "$(/usr/bin/grep -cF -- "- '.aai/scripts/merge-cleanup.mjs'" "$yml" || true)" == 2 ]] || fail TEST-017 'ps1-quality must list the engine in both the push and pull_request filters'
  [[ "$(/usr/bin/grep -cF -- "- '.aai/SKILL_MERGE.prompt.md'" "$yml" || true)" == 2 ]] || fail TEST-017 'ps1-quality must list the prompt in both the push and pull_request filters'
  # the diet ledger names this scope with a positive integer credit
  sect="$(/usr/bin/grep -F 'directed-merge-and-post-merge-cleanup' "$ROOT/tests/skills/lib/prompt-diet-ledger.sh" || true)"
  [[ -n "$sect" ]] || fail TEST-017 'the prompt-diet ledger carries no entry for this scope'
  echo 'PASS: TEST-017 companion wiring'
}

# TEST-016: the Pester parity suite, run under the local pwsh. Explicit selection
# only (the default run and CI's skill-suite leg leave it to the ps1-quality
# jobs, which run the same file under Windows PowerShell 5.1 and pwsh 7); this
# selector exists so the engine mutations that redden TEST-015 can be measured
# against the PowerShell half too. A macOS/Linux pwsh run is pre-PR evidence only.
test_016_powershell_parity() {
  local rc=0 out
  command -v pwsh >/dev/null 2>&1 || fail TEST-016 'pwsh is not installed; the Pester parity cannot be measured here'
  [[ -f "$ROOT/tests/skills/aai-merge-cleanup.Tests.ps1" ]] || fail TEST-016 'tests/skills/aai-merge-cleanup.Tests.ps1 is missing'
  out="$(AAI_ROOT_DIR="$ROOT" pwsh -NoProfile -Command 'Set-Location -LiteralPath $env:AAI_ROOT_DIR; Invoke-Pester -Path tests/skills/aai-merge-cleanup.Tests.ps1 -EnableExit' 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-016 "Pester exited $rc: $(printf '%s\n' "$out" | /usr/bin/grep -E 'RuntimeException|Expected|REFUSE|STOPPED|\[-\]' | awk 'NR <= 6' | tr '\n' ' ')"
  want TEST-016 "$out" 'Passed: 3'
  echo 'PASS: TEST-016 PowerShell parity (local pwsh)'
}

# ---------------------------------------------------------------------------
# spec-merge-cleanup-submodule-worktree A: submodule fixture, TEST-028/029/030

# Every submodule git call carries protocol.file.allow (the suite runs with
# GIT_CONFIG_GLOBAL=/dev/null) and every setup command goes through `run`.
SUB_BASELINE_SEED=''
subgit() { git -c protocol.file.allow=always "$@"; }

# mk_sub_origin <dir>: a bare origin whose HEAD names main (a bare repo created
# without it points at the machine's init.defaultBranch, which CI does not share).
mk_bare_origin() {
  [[ -n "$1" && "$1" = /* ]] || fail SETUP "bare origin path not absolute: $1"
  run git init -q --bare -b main "$1"
  run git -C "$1" symbolic-ref HEAD refs/heads/main
}

# seed_sub_baseline: bare nested.git and sub.git origins (sub holds the nested
# submodule `nest`), then `sub` added to the origin checkout, initialized
# recursively there. Runs inside build_world before the baseline commit.
seed_sub_baseline() {
  local nw="$W/nested-work" sw="$W/sub-work"
  SUBS="$W/subs"; NESTED="$SUBS/nested.git"; SUBR="$SUBS/sub.git"
  run mkdir -p "$SUBS"
  mk_bare_origin "$NESTED"; mk_bare_origin "$SUBR"
  run git clone -q "$NESTED" "$nw"
  run git -C "$nw" config user.name 'AAI Fixture'; run git -C "$nw" config user.email 'fixture@example.invalid'
  printf 'nest tracked\n' > "$nw/nest.txt"
  run git -C "$nw" add nest.txt
  run git -C "$nw" commit -qm 'nested baseline'
  run git -C "$nw" push -q origin HEAD:refs/heads/main
  run git clone -q "$SUBR" "$sw"
  run git -C "$sw" config user.name 'AAI Fixture'; run git -C "$sw" config user.email 'fixture@example.invalid'
  printf 'sub tracked\n' > "$sw/sub.txt"
  run git -C "$sw" add sub.txt
  run subgit -C "$sw" submodule add -q "$NESTED" nest
  run git -C "$sw" commit -qm 'sub baseline'
  run git -C "$sw" push -q origin HEAD:refs/heads/main
  run subgit -C "$ORIGIN" submodule add -q "$SUBR" sub
  run subgit -C "$ORIGIN" submodule update -q --init --recursive
  # the squash commit may record a gitlink whose commit lives in no remote (the unpushed arms);
  # an on-demand submodule fetch would fail the base fetch before the worktree gate is reached
  run git -C "$ORIGIN" config fetch.recurseSubmodules false
  if [[ -n "${SUB_IGNORE_ALL:-}" ]]; then
    run git -C "$ORIGIN" config -f .gitmodules submodule.sub.ignore all
    run git -C "$ORIGIN" add .gitmodules
  fi
}

# boot_sub_ride: the ride checkout initializes its own submodules (their git
# dirs land under the ride's admin dir, which is what git refuses to remove).
boot_sub_ride() {
  run subgit -C "$RIDE" submodule update -q --init --recursive
  local d
  for d in sub sub/nest; do
    run git -C "$RIDE/$d" config user.name 'AAI Fixture'
    run git -C "$RIDE/$d" config user.email 'fixture@example.invalid'
  done
}

# build_sub_world <name>: build_world plus the submodule fixture. SUB_RIDE_UNINIT=1
# leaves the ride's submodules uninitialized; SUB_IGNORE_ALL=1 writes
# `ignore = all` into .gitmodules; RIDE_SEED works as in build_world.
build_sub_world() {
  BASELINE_SEED=seed_sub_baseline
  if [[ -n "${SUB_RIDE_UNINIT:-}" ]]; then RIDE_BOOT=''; else RIDE_BOOT=boot_sub_ride; fi
  build_world "$1"
  BASELINE_SEED=''; RIDE_BOOT=''
}

# seed_unpushed_sub: a ride commit in sub, on no remote, recorded as the gitlink.
seed_unpushed_sub() {
  printf 'unpushed\n' > "$RIDE/sub/unpushed.txt"
  run git -C "$RIDE/sub" add unpushed.txt
  run git -C "$RIDE/sub" commit -qm 'unpushed in sub'
  UNPUSHED_SHA="$(git -C "$RIDE/sub" rev-parse HEAD)" || fail SETUP 'unpushed sha'
  run git -C "$RIDE" add sub
}

# seed_unpushed_nest: the same one level down (sub's gitlink moves too).
seed_unpushed_nest() {
  printf 'unpushed\n' > "$RIDE/sub/nest/unpushed.txt"
  run git -C "$RIDE/sub/nest" add unpushed.txt
  run git -C "$RIDE/sub/nest" commit -qm 'unpushed in nest'
  UNPUSHED_SHA="$(git -C "$RIDE/sub/nest" rev-parse HEAD)" || fail SETUP 'unpushed nest sha'
  run git -C "$RIDE/sub" add nest
  run git -C "$RIDE/sub" commit -qm 'move nest'
  run git -C "$RIDE" add sub
}

# origin_sub_state: what the main checkout's submodule registration looks like.
origin_sub_state() {
  git -C "$ORIGIN" config --get-regexp '^submodule\.' || true
  git -C "$ORIGIN" submodule status --recursive || true
}

# plan_keeps <tid> <reason> <detail>: plan exits 0 and names the worktree it would keep, writing nothing.
plan_keeps() {
  local tid="$1" reason="$2" detail="$3" before
  before="$(world_digest)"
  run_engine plan --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail "$tid" "plan exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want "$tid" "$ENG_OUT" "keep $RIDE ($reason $detail"
  [[ "$(world_digest)" == "$before" ]] || fail "$tid" "plan arm $reason changed the fixture"
}

test_028_submodule_worktree_removed_after_proof() {
  local before after
  build_sub_world sub_clean
  [[ -e "$RIDE/sub/nest/nest.txt" ]] || fail SETUP 'ride nested submodule is not initialized'
  [[ -e "$ORIGIN/sub/nest/nest.txt" ]] || fail SETUP 'origin nested submodule is not initialized'
  has "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE" || fail SETUP 'ride is not registered'
  before="$(origin_sub_state)"
  has "$before" 'submodule.sub.url' || fail SETUP "origin submodule config missing: $before"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-028 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-028 'ride worktree directory still exists'
  unwanted TEST-028 "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE"
  if git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then fail TEST-028 'ride branch still exists'; fi
  after="$(origin_sub_state)"
  [[ "$after" == "$before" ]] || fail TEST-028 "the main checkout's submodule registration changed: before [$before] after [$after]"
  [[ -e "$ORIGIN/sub/nest/nest.txt" ]] || fail TEST-028 'the main checkout lost its nested submodule'

  # arm 2: a ride whose submodules were never initialized is removed as before
  SUB_RIDE_UNINIT=1 build_sub_world sub_uninit
  [[ ! -e "$RIDE/sub/sub.txt" ]] || fail SETUP 'uninitialized arm has initialized submodule'
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-028 "uninitialized arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-028 'uninitialized arm left the worktree'
  if git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then fail TEST-028 'uninitialized arm left the branch'; fi
  echo 'PASS: TEST-028 submodule worktree removed after the proof, main checkout untouched'
}

test_029_dirty_submodule_kept() {
  local arm path want_path sha_before dirty
  for arm in "tracked|sub|sub" "untracked|sub|sub" "nested|sub/nest|sub/nest" "ignore_all|sub|sub"; do
    path="${arm#*|}"; want_path="${path#*|}"; path="${path%%|*}"
    if [[ "${arm%%|*}" == ignore_all ]]; then SUB_IGNORE_ALL=1 build_sub_world "sub_dirty_${arm%%|*}"; else build_sub_world "sub_dirty_${arm%%|*}"; fi
    case "${arm%%|*}" in
      tracked|ignore_all) dirty="$RIDE/$path/sub.txt"; printf 'edited\n' >> "$dirty" ;;
      untracked) dirty="$RIDE/$path/stray.txt"; printf 'stray\n' > "$dirty" ;;
      nested) dirty="$RIDE/$path/nest.txt"; printf 'edited\n' >> "$dirty" ;;
    esac
    sha_before="$(sha_of "$dirty")"
    plan_keeps TEST-029 submodule_dirty "$want_path (dirty:"
    keep_arm TEST-029 submodule_dirty "$want_path (dirty:" remove-worktree
    [[ "$(sha_of "$dirty")" == "$sha_before" ]] || fail TEST-029 "arm ${arm%%|*}: the dirty file changed"
    has "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE" || fail TEST-029 "arm ${arm%%|*}: the ride left the worktree list"
    git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-029 "arm ${arm%%|*}: the ride branch is gone"
    # the nested arm names the nested path, not its parent
    if [[ "${arm%%|*}" == nested ]]; then unwanted TEST-029 "$ENG_OUT" 'sub (dirty'; fi
  done
  echo 'PASS: TEST-029 a dirty submodule keeps the worktree and finishes the other steps'
}

test_030_unpushed_submodule_kept() {
  local arm reason path before adm
  for arm in "gitlink|submodule_unpushed|sub" "nested_gitlink|submodule_unpushed|sub (unpushed: 1 commit not on any remote-tracking ref); sub/nest" "branch_ahead|submodule_unpushed|sub" "tag_only|submodule_unpushed|sub" \
             "stash|submodule_stash|sub" "no_remote|submodule_no_remote|sub" "stray_module|submodule_unverifiable|stray" \
             "ignored_ls_fails|submodule_unverifiable|sub"; do
    reason="${arm#*|}"; path="${reason#*|}"; reason="${reason%%|*}"
    UNPUSHED_SHA=''
    case "${arm%%|*}" in
      gitlink) RIDE_SEED=seed_unpushed_sub build_sub_world "sub_${arm%%|*}" ;;
      nested_gitlink) RIDE_SEED=seed_unpushed_nest build_sub_world "sub_${arm%%|*}" ;;
      *) build_sub_world "sub_${arm%%|*}" ;;
    esac
    case "${arm%%|*}" in
      branch_ahead)
        run git -C "$RIDE/sub" checkout -q -b ahead
        printf 'ahead\n' > "$RIDE/sub/ahead.txt"
        run git -C "$RIDE/sub" add ahead.txt
        run git -C "$RIDE/sub" commit -qm 'ahead on a branch'
        UNPUSHED_SHA="$(git -C "$RIDE/sub" rev-parse HEAD)" || fail SETUP 'ahead sha'
        run git -C "$RIDE/sub" checkout -q --detach "$(git -C "$RIDE" rev-parse HEAD:sub)" ;;
      tag_only)
        printf 'tagged\n' > "$RIDE/sub/tagged.txt"
        run git -C "$RIDE/sub" add tagged.txt
        run git -C "$RIDE/sub" commit -qm 'reachable only from a local tag'
        UNPUSHED_SHA="$(git -C "$RIDE/sub" rev-parse HEAD)" || fail SETUP 'tag sha'
        run git -C "$RIDE/sub" tag only-local-tag
        run git -C "$RIDE/sub" checkout -q --detach "$(git -C "$RIDE" rev-parse HEAD:sub)" ;;
      stash)
        printf 'stashed\n' >> "$RIDE/sub/sub.txt"
        run git -C "$RIDE/sub" stash -q ;;
      no_remote) run git -C "$RIDE/sub" remote remove origin ;;
      ignored_ls_fails)
        # the ignored listing of sub fails (test seam): --force would delete ignored files unarchived and unnamed
        ignore_in_sub
        export AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_FAIL_IGNORED_LS=sub ;;
      stray_module)
        adm="$(git -C "$RIDE" rev-parse --absolute-git-dir)" || fail SETUP 'ride admin dir'
        [[ -n "$adm" && "$adm" = /* ]] || fail SETUP 'ride admin dir not absolute'
        run git init -q --bare "$adm/modules/stray" ;;
    esac
    before="$(git -C "$RIDE" status --porcelain --ignore-submodules=dirty)"
    [[ -z "$before" ]] || fail SETUP "arm ${arm%%|*}: superproject not clean: $before"
    plan_keeps TEST-030 "$reason" "$path ("
    keep_arm TEST-030 "$reason" "$path (" remove-worktree
    has "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE" || fail TEST-030 "arm ${arm%%|*}: the ride left the worktree list"
    git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-030 "arm ${arm%%|*}: the ride branch is gone"
    if [[ "${arm%%|*}" == ignored_ls_fails ]]; then
      unset AAI_MERGE_CLEANUP_TEST_SEAMS AAI_MERGE_CLEANUP_FAIL_IGNORED_LS
      [[ -f "$RIDE/sub/x.local" && -f "$RIDE/sub/ign/out.bin" ]] || fail TEST-030 "arm ${arm%%|*}: the ignored files were deleted"
    fi
    if [[ -n "$UNPUSHED_SHA" ]]; then
      if [[ "${arm%%|*}" == nested_gitlink ]]; then
        git -C "$RIDE/sub/nest" cat-file -e "$UNPUSHED_SHA^{commit}" || fail TEST-030 "arm ${arm%%|*}: the unpushed commit is gone"
      else
        git -C "$RIDE/sub" cat-file -e "$UNPUSHED_SHA^{commit}" || fail TEST-030 "arm ${arm%%|*}: the unpushed commit is gone"
      fi
    fi
  done
  echo 'PASS: TEST-030 unpushed, stashed, remoteless and unverifiable submodules keep the worktree'
}

# ---------------------------------------------------------------------------
# spec-merge-cleanup-submodule-worktree B: TEST-031 (ignored content), TEST-032 (late dirt), TEST-033 (preflight), TEST-034 (canon).

# ignore_in_sub: x.local and the directory ign/ are ignored inside the ride's `sub`
# (through the submodule's own info/exclude, which keeps its tree clean).
ignore_in_sub() {
  local gd
  gd="$(git -C "$RIDE/sub" rev-parse --absolute-git-dir)" || fail SETUP 'sub git dir'
  [[ -n "$gd" && "$gd" = /* ]] || fail SETUP 'sub git dir not absolute'
  run mkdir -p "$gd/info"
  printf 'x.local\nign/\n' >> "$gd/info/exclude"
  printf 'local secret\n' > "$RIDE/sub/x.local"
  run mkdir -p "$RIDE/sub/ign"
  printf 'generated\n' > "$RIDE/sub/ign/out.bin"
  [[ -z "$(git -C "$RIDE/sub" status --porcelain --untracked-files=normal)" ]] || fail SETUP 'ignored content made sub dirty'
}

# lines_of <file> <fixed string>: how many lines of the file contain it (0 when the file is absent).
lines_of() {
  local n=0
  if [[ -f "$1" ]]; then n="$( { /usr/bin/grep -cF -- "$2" "$1" || true; } )"; fi
  printf '%s' "$n"
}

test_031_submodule_ignored_archived_or_named() {
  local arch pre rep man removed saved f
  build_sub_world sub_ignored
  ignore_in_sub
  pre="$(sha_of "$RIDE/sub/x.local")"
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  run_engine plan --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-031 "plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-031 "$ENG_OUT" "archive worktree:sub/x.local -> docs/ai/archive/merge-cleanup/pr-$PR/worktree-submodules/sub/x.local"
  want TEST-031 "$ENG_OUT" 'remove (ignored, not archived) sub/ign/'
  [[ ! -e "$arch" ]] || fail TEST-031 'plan wrote an archive'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-031 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  [[ ! -e "$RIDE" ]] || fail TEST-031 'the ride worktree is still there'
  [[ "$(sha_of "$arch/worktree-submodules/sub/x.local")" == "$pre" ]] || fail TEST-031 'the archived copy differs from the ignored file'
  [[ ! -e "$arch/worktree-submodules/sub/ign" ]] || fail TEST-031 'a fully ignored directory was archived'
  man="$arch/manifest.jsonl"
  [[ "$(lines_of "$man" 'worktree:sub/x.local')" == 1 ]] || fail TEST-031 "manifest lines for x.local: $(lines_of "$man" 'worktree:sub/x.local'), want 1"
  want TEST-031 "$(cat "$man")" "\"sha256\":\"$pre\""
  want TEST-031 "$(cat "$man")" '"reason":"submodule_ignored"'
  removed="$arch/removed.jsonl"
  [[ "$(lines_of "$removed" 'sub/ign/')" == 1 && "$(/usr/bin/grep -c . "$removed" || true)" == 1 ]] || fail TEST-031 "removed.jsonl: $(cat "$removed" 2>/dev/null)"
  want TEST-031 "$(cat "$removed")" 'submodule_ignored_not_archived'
  [[ "$(json_get "$rep" 'j.removed_unarchived.join(",")')" == 'sub/ign/' ]] || fail TEST-031 "removed_unarchived: $(json_get "$rep" 'j.removed_unarchived')"
  # a second apply appends no manifest and no removed.jsonl line
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-031 "second apply exited $ENG_RC"
  [[ "$(lines_of "$man" 'worktree:sub/x.local')" == 1 && "$(/usr/bin/grep -c . "$removed" || true)" == 1 ]] || fail TEST-031 'second apply appended a line'

  # an interrupted run re-archives the same content: still one line each (the archive itself is idempotent)
  build_sub_world sub_ignored_resume
  ignore_in_sub
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"; man="$arch/manifest.jsonl"; removed="$arch/removed.jsonl"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_TOUCH_AT='before-remove-verify:sub/late.txt' run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-031 "resume arm: first apply exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(lines_of "$man" 'worktree:sub/x.local')" == 1 ]] || fail TEST-031 'resume arm: first run did not archive x.local once'
  run rm "$RIDE/sub/late.txt"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-031 "resume arm: second apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(lines_of "$man" 'worktree:sub/x.local')" == 1 && "$(/usr/bin/grep -c . "$removed" || true)" == 1 ]] || fail TEST-031 'resume arm: the second pass appended a line'
  echo 'PASS: TEST-031 ignored submodule files archived, ignored directories named, repeat appends nothing'
}

test_032_late_dirt_stops_then_resumes() {
  local before_branch
  build_sub_world sub_late
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_TOUCH_AT='before-remove-verify:sub/late.txt' run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-032 "apply exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-032 "$ENG_OUT" 'STOPPED submodule_dirty sub (dirty:'
  [[ -d "$RIDE" ]] || fail TEST-032 'the ride worktree was removed'
  [[ -s "$RIDE/sub/late.txt" ]] || fail TEST-032 'the late file did not survive'
  has "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE" || fail TEST-032 'the ride left the worktree list'
  git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-032 'the ride branch is gone'
  want TEST-032 "$(cat "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/journal.jsonl")" '"step":"sync-base"'
  unwanted TEST-032 "$(cat "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/journal.jsonl")" '"step":"remove-worktree"'
  run rm "$RIDE/sub/late.txt"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-032 "re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-032 'the re-run left the ride worktree'
  if git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then fail TEST-032 'the re-run left the ride branch'; fi
  # arm 2: the ignored listing fails only at the archive step (a one-off git failure after
  # the proof passed): the removal stops, nothing ignored is lost, and a re-run finishes.
  build_sub_world sub_late_ls
  ignore_in_sub
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_FAIL_IGNORED_LS=sub AAI_MERGE_CLEANUP_FAIL_IGNORED_LS_AT=archive run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-032 "archive-listing arm: apply exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-032 "$ENG_OUT" 'STOPPED submodule_unverifiable sub'
  [[ -d "$RIDE" ]] || fail TEST-032 'archive-listing arm: the ride worktree was removed'
  [[ -f "$RIDE/sub/x.local" && -f "$RIDE/sub/ign/out.bin" ]] || fail TEST-032 'archive-listing arm: the ignored files were deleted'
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-032 "archive-listing arm: re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-032 'archive-listing arm: the re-run left the ride worktree'
  echo 'PASS: TEST-032 late dirt stops the removal and a re-run finishes it'
}

test_033_preflight_names_cleanup_blocker() {
  local merge_at block_at lines
  # arm dirty
  open_sub_world pf_sub_dirty
  printf 'edited\n' >> "$RIDE/sub/sub.txt"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-033 "dirty arm: preflight exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  lines="$(printf '%s\n' "$ENG_OUT" | { /usr/bin/grep '^cleanup blocked: ' || true; })"
  [[ "$(printf '%s\n' "$lines" | /usr/bin/grep -c . || true)" == 1 ]] || fail TEST-033 "want exactly one cleanup blocked line: $ENG_OUT"
  want TEST-033 "$lines" 'cleanup blocked: submodule_dirty sub (dirty:'
  merge_at="$(printf '%s\n' "$ENG_OUT" | /usr/bin/grep -n 'gh pr merge' | cut -d: -f1)"
  block_at="$(printf '%s\n' "$ENG_OUT" | /usr/bin/grep -n '^cleanup blocked: ' | cut -d: -f1)"
  [[ -n "$merge_at" && -n "$block_at" && "$block_at" -lt "$merge_at" ]] || fail TEST-033 "the cleanup blocked line does not precede the merge command: $ENG_OUT"
  pf --json
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-033 "dirty arm json: exit $ENG_RC"
  [[ "$(json_get "$ENG_OUT" 'j.cleanup_blockers.length')" == 1 ]] || fail TEST-033 "cleanup_blockers: $(json_get "$ENG_OUT" 'j.cleanup_blockers')"
  [[ "$(json_get "$ENG_OUT" 'j.cleanup_blockers[0].reason')" == submodule_dirty ]] || fail TEST-033 'json reason is not submodule_dirty'
  want TEST-033 "$(json_get "$ENG_OUT" 'j.cleanup_blockers[0].detail')" 'sub (dirty:'
  # arm unpushed (committed gitlink)
  RIDE_SEED=seed_unpushed_sub open_sub_world pf_sub_unpushed
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-033 "unpushed arm: preflight exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-033 "$ENG_OUT" 'cleanup blocked: submodule_unpushed sub (unpushed:'
  # clean arm: no line, and the key is computed (an empty array, not an absent key)
  open_sub_world pf_sub_clean
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-033 "clean arm: preflight exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-033 "$ENG_OUT" 'cleanup blocked:'
  pf --json
  [[ "$(json_get "$ENG_OUT" 'j.cleanup_blockers')" == '[]' ]] || fail TEST-033 "clean arm: cleanup_blockers is $(json_get "$ENG_OUT" 'j.cleanup_blockers'), want []"
  # a ride without submodules is untouched by the new key
  open_world pf_nosub
  pf --json
  [[ "$(json_get "$ENG_OUT" 'j.cleanup_blockers')" == '[]' ]] || fail TEST-033 'no-submodule arm: cleanup_blockers is not []'
  assert_no_merge_call TEST-033
  echo 'PASS: TEST-033 preflight names the cleanup blocker before the merge command'
}

# open_sub_world <name>: open_world with the submodule fixture.
open_sub_world() {
  build_sub_world "$1"
  printf '%s\n' "$SWEEP_OK" >> "$RIDE/docs/ai/EVENTS.jsonl"
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  : > "$GHD/gh-argv.log"
}

test_034_canon_stop_and_relay() {
  local text step23 hard credit
  text="$(cat "$ROOT/.aai/SKILL_MERGE.prompt.md")"
  want TEST-034 "$text" 'cleanup blocked:'
  step23="$(awk '/^2\. / { f = 1 } f' "$ROOT/.aai/SKILL_MERGE.prompt.md")"
  [[ -n "$step23" ]] || fail TEST-034 'SKILL_MERGE step 2 not found (positive control)'
  want TEST-034 "$step23" 'relay'
  want TEST-034 "$step23" 'verbatim'
  want TEST-034 "$text" 'never finish a step by hand'
  want TEST-034 "$(printf '%s\n' "$text" | /usr/bin/grep -F 'never finish a step by hand' || true)" 'git worktree remove --force'
  hard="$(printf '%s\n' "$text" | /usr/bin/grep -i 'hard rules' -A12 || true)"
  want TEST-034 "$hard" 'worktree remove --force'
  credit="$(/usr/bin/grep -F 'JUSTIFIED_ADDITIONS+=( "' "$ROOT/tests/skills/lib/prompt-diet-ledger.sh" | sed -n 's/^JUSTIFIED_ADDITIONS+=( "\([0-9][0-9]*\) merge-cleanup-submodule-worktree .*/\1/p' | awk 'NR == 1')"
  [[ -n "$credit" && "$credit" -gt 0 && "$credit" -le 700 ]] || fail TEST-034 "the prompt-diet ledger credit for merge-cleanup-submodule-worktree is '$credit', want 1..700"
  echo 'PASS: TEST-034 the canon tells the agent to relay the refusal and never finish by hand'
}

# spec-merge-cleanup-submodule-worktree D (bot round): TEST-035 (submodule tags archived).
# A local-only tag on an already-pushed commit passes the commit-reachability proof, and --force
# deletes the submodule git dir: the tag names (and an annotated tag's own object) are archived first.
test_035_submodule_tags_archived() {
  local arch man tdir want_obj got_obj tagoid lw ann n1
  build_sub_world sub_tags
  run git -C "$RIDE/sub" tag lw-local
  run git -C "$RIDE/sub" tag -a -m 'annotated message' ann-local
  tagoid="$(git -C "$RIDE/sub" rev-parse refs/tags/ann-local)" || fail SETUP 'annotated tag oid'
  lw="$(git -C "$RIDE/sub" rev-parse refs/tags/lw-local)" || fail SETUP 'lightweight tag oid'
  want_obj="$(git -C "$RIDE/sub" cat-file tag "$tagoid" | node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(0)).digest("hex"))')" || fail SETUP 'annotated tag object'
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"; man="$arch/manifest.jsonl"
  tdir="$arch/worktree-submodules/sub/.aai-submodule-tags"
  run_engine plan --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-035 "plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-035 "$ENG_OUT" 'archive 2 tags of sub -> docs/ai/archive/merge-cleanup/pr-'
  [[ ! -e "$arch" ]] || fail TEST-035 'plan wrote an archive'
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-035 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-035 'the ride worktree is still there'
  [[ -f "$tdir/tags.txt" ]] || fail TEST-035 'no tags file archived'
  want TEST-035 "$(cat "$tdir/tags.txt")" "refs/tags/lw-local $lw commit"
  want TEST-035 "$(cat "$tdir/tags.txt")" "refs/tags/ann-local $tagoid tag"
  [[ -f "$tdir/objects/$tagoid.tag" ]] || fail TEST-035 'the annotated tag object was not archived'
  got_obj="$(sha_of "$tdir/objects/$tagoid.tag")"
  [[ "$got_obj" == "$want_obj" ]] || fail TEST-035 "archived tag object differs from git cat-file output: $got_obj vs $want_obj"
  [[ ! -e "$tdir/objects/$lw.tag" ]] || fail TEST-035 'a lightweight tag got an object file'
  want TEST-035 "$(cat "$man")" '"reason":"submodule_tags"'
  n1="$(/usr/bin/grep -c '"reason":"submodule_tags"' "$man" || true)"
  [[ "$n1" == 2 ]] || fail TEST-035 "submodule_tags manifest lines: $n1, want 2 (tags file and one tag object)"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-035 "second apply exited $ENG_RC"
  [[ "$(/usr/bin/grep -c '"reason":"submodule_tags"' "$man" || true)" == "$n1" ]] || fail TEST-035 'second apply appended a manifest line'

  # an unpushed commit still blocks (the tag archive does not replace the commit proof)
  build_sub_world sub_tags_unpushed
  printf 'tagged\n' > "$RIDE/sub/tagged.txt"
  run git -C "$RIDE/sub" add tagged.txt
  run git -C "$RIDE/sub" commit -qm 'reachable only from a local tag'
  run git -C "$RIDE/sub" tag only-local-tag
  run git -C "$RIDE/sub" checkout -q --detach "$(git -C "$RIDE" rev-parse HEAD:sub)"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-035 "unpushed-tag arm: apply exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-035 "$ENG_OUT" '"reason":"submodule_unpushed"'
  [[ -d "$RIDE" ]] || fail TEST-035 'unpushed-tag arm: the ride was removed'
  echo 'PASS: TEST-035 submodule tags archived before the forced removal, repeat appends nothing'
}

# ---------------------------------------------------------------------------
# spec-merge-cleanup-delete-remote-branch: TEST-036..042 (the delete-remote-branch step).
# Every assertion about the remote reads the bare origin itself, never the report alone.

bare_has() { git -C "$BARE" rev-parse -q --verify "refs/heads/$1" >/dev/null 2>&1; }
rstep() { json_get "$1" "j.steps.find(s=>s.id===\"delete-branch\")?.$2"; }

# make_shim <dir> <git subcommand that triggers it> <shell action run before the real git>
make_shim() {
  local d="$1" trig="$2" act="$3" real
  real="$(command -v git)" || fail SETUP 'git not found'
  run mkdir -p "$d"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'for a in "$@"; do\n  if [ "$a" = %s ]; then\n    %s\n    break\n  fi\ndone\n' "$trig" "$act"
    printf 'exec "%s" "$@"\n' "$real"
  } > "$d/git"
  run chmod +x "$d/git"
}

# advance_bare_oid: a commit on top of the PR head, created in the bare WITHOUT moving any ref.
advance_bare_oid() {
  ADV_OID="$(git -C "$BARE" commit-tree "$HEAD_OID^{tree}" -p "$HEAD_OID" -m 'advanced after the merge')" || fail SETUP 'advance commit'
}

# retained_arm <tid> <reason> <label>: the common post-conditions of a retained remote branch.
retained_arm() {
  local tid="$1" reason="$2" label="$3"
  [[ "$ENG_RC" -eq 0 ]] || fail "$tid" "$label exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want "$tid" "$(json_get "$ENG_OUT" 'j.remaining')" "origin/$BRANCH"
  want "$tid" "$(json_get "$ENG_OUT" 'j.remaining')" "$reason"
  [[ "$(step_status "$ENG_OUT" remove-worktree)" == done ]] || fail "$tid" "$label: remove-worktree is not done"
  [[ "$(step_status "$ENG_OUT" delete-branch)" == done ]] || fail "$tid" "$label: delete-branch is not done"
  [[ "$(step_status "$ENG_OUT" report)" == done ]] || fail "$tid" "$label: report step is not done"
  want "$tid" "$ENG_OUT" "origin/$BRANCH"
}

test_036_remote_branch_deleted_by_lease() {
  build_world remote_delete
  local pdig tgt
  run git -C "$BARE" update-ref refs/heads/misc-remote "$MC"
  bare_has "$BRANCH" || fail SETUP 'the bare has no ride branch (positive control)'
  pdig="$(world_digest)"
  run_engine plan --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-036 "plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(world_digest)" == "$pdig" ]] || fail TEST-036 'plan changed the fixture'
  tgt="$(rstep "$ENG_OUT" targets)"
  want TEST-036 "$tgt" "origin/$BRANCH"
  want TEST-036 "$tgt" "${HEAD_OID:0:12}"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-036 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  if bare_has "$BRANCH"; then fail TEST-036 'the remote branch still exists on the bare origin'; fi
  [[ "$(rstep "$ENG_OUT" status)" == done ]] || fail TEST-036 "step is '$(rstep "$ENG_OUT" status)', want done (out: $ENG_OUT)"
  [[ "$(rstep "$ENG_OUT" detail)" == "$BRANCH" ]] || fail TEST-036 "step detail '$(rstep "$ENG_OUT" detail)', want $BRANCH"
  unwanted TEST-036 "$(json_get "$ENG_OUT" 'j.remaining')" "origin/$BRANCH"
  [[ "$(git -C "$BARE" rev-parse refs/heads/main)" == "$MC" ]] || fail TEST-036 'the bare main moved'
  [[ "$(git -C "$BARE" rev-parse refs/heads/misc-remote)" == "$MC" ]] || fail TEST-036 'an unrelated remote branch moved or was deleted'
  assert_no_merge_call TEST-036
  # the text report of a fresh world prints the step
  build_world remote_delete_text
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-036 "text apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-036 "$ENG_OUT" "delete-branch: done ($BRANCH)"
  unwanted TEST-036 "$ENG_OUT" "remaining: origin/$BRANCH"
  echo 'PASS: TEST-036 the merged remote branch is deleted by lease'
}

test_037_moved_remote_retained() {
  local shim moved
  # arm pre-moved: the remote branch advanced after the merge, before apply starts
  build_world remote_premoved
  advance_bare_oid
  moved="$ADV_OID"
  run git -C "$BARE" update-ref "refs/heads/$BRANCH" "$moved"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-037 remote_moved 'pre-moved arm'
  [[ "$(git -C "$BARE" rev-parse "refs/heads/$BRANCH")" == "$moved" ]] || fail TEST-037 'pre-moved arm: the remote branch is not at the new commit'
  # arm race: the remote advances right between the ls-remote proof and the push
  build_world remote_race
  advance_bare_oid
  moved="$ADV_OID"
  shim="$W/shim"
  make_shim "$shim" push "\"$(command -v git)\" -C \"$BARE\" update-ref \"refs/heads/$BRANCH\" \"$moved\""
  bare_has "$BRANCH" || fail SETUP 'race arm: no remote branch before the run'
  PATH="$shim:$PATH" run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-037 remote_moved 'race arm'
  [[ "$(git -C "$BARE" rev-parse "refs/heads/$BRANCH")" == "$moved" ]] || fail TEST-037 'race arm: the moved remote branch was deleted or reset'
  echo 'PASS: TEST-037 a moved remote branch is retained by the lease'
}

test_038_absent_noop_and_idempotent() {
  local shim before n
  # arm absent
  build_world remote_absent_pre
  run git -C "$BARE" update-ref -d "refs/heads/$BRANCH"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-038 "absent arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(rstep "$ENG_OUT" status)" == done ]] || fail TEST-038 "absent arm: step is '$(rstep "$ENG_OUT" status)', want done"
  unwanted TEST-038 "$(json_get "$ENG_OUT" 'j.remaining')" "origin/$BRANCH"
  # arm race-absent: the branch vanishes between the proof and the push
  build_world remote_race_absent
  shim="$W/shim"
  make_shim "$shim" push "\"$(command -v git)\" -C \"$BARE\" update-ref -d \"refs/heads/$BRANCH\""
  PATH="$shim:$PATH" run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-038 "race-absent arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(rstep "$ENG_OUT" status)" == done ]] || fail TEST-038 "race-absent arm: step is '$(rstep "$ENG_OUT" status)', want done"
  unwanted TEST-038 "$(json_get "$ENG_OUT" 'j.remaining')" "origin/$BRANCH"
  # arm rerun: a second apply after a successful first one is a full no-op
  build_world remote_rerun
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-038 "first apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(rstep "$ENG_OUT" status)" == done ]] || fail TEST-038 'first apply did not delete the remote branch (positive control)'
  n="$(saved_reports | wc -l | tr -d ' ')"
  before="$(world_digest)"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-038 "second apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(rstep "$ENG_OUT" status)" == noop ]] || fail TEST-038 "second apply: step is '$(rstep "$ENG_OUT" status)', want noop"
  [[ "$(step_status "$ENG_OUT" delete-branch)" == noop && "$(step_status "$ENG_OUT" remove-worktree)" == noop ]] || fail TEST-038 'second apply: an earlier action step did work'
  [[ "$(saved_reports | wc -l | tr -d ' ')" == "$n" ]] || fail TEST-038 'second apply saved another report'
  [[ "$(world_digest)" == "$before" ]] || fail TEST-038 'second apply changed the world'
  echo 'PASS: TEST-038 an absent remote branch is a named no-op and a rerun is idempotent'
}

test_039_fork_and_unknown_origin_retained() {
  PR_CROSS=true build_world remote_fork
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-039 remote_fork 'fork arm'
  bare_has "$BRANCH" || fail TEST-039 'fork arm: the remote branch was deleted'
  PR_CROSS=absent build_world remote_field_absent
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-039 remote_unknown 'field-absent arm'
  bare_has "$BRANCH" || fail TEST-039 'field-absent arm: the remote branch was deleted'
  echo 'PASS: TEST-039 a fork head or an unknown head repository is retained'
}

test_040_base_default_and_bad_name_retained() {
  # default: the bare HEAD names the ride branch
  build_world remote_default
  run git -C "$BARE" symbolic-ref HEAD "refs/heads/$BRANCH"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-040 remote_is_base 'default arm'
  bare_has "$BRANCH" || fail TEST-040 'default arm: the default branch was deleted'
  # base: the PR head branch is the base branch
  PR_HEAD_NAME=main build_world remote_base
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-040 "base arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(rstep "$ENG_OUT" status)" == retained ]] || fail TEST-040 "base arm: step is '$(rstep "$ENG_OUT" status)', want retained"
  want TEST-040 "$(rstep "$ENG_OUT" detail)" remote_is_base
  [[ "$(git -C "$BARE" rev-parse refs/heads/main)" == "$MC" ]] || fail TEST-040 'base arm: the bare main moved'
  # bad name: passes the bad_head_name refusal, fails git check-ref-format
  PR_HEAD_NAME='ride..foo' build_world remote_bad_name
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-040 "bad-name arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(rstep "$ENG_OUT" status)" == retained ]] || fail TEST-040 "bad-name arm: step is '$(rstep "$ENG_OUT" status)', want retained"
  want TEST-040 "$(rstep "$ENG_OUT" detail)" remote_bad_name
  bare_has "$BRANCH" || fail TEST-040 'bad-name arm: a remote branch was deleted'
  echo 'PASS: TEST-040 the base, the default branch and a bad name are retained'
}

test_041_rejected_and_unreadable_never_stop() {
  local shim
  # rejected: a pre-receive hook on the bare refuses the deletion
  build_world remote_rejected
  run mkdir -p "$BARE/hooks"
  printf '#!/bin/sh\necho "protected branch" >&2\nexit 1\n' > "$BARE/hooks/pre-receive"
  run chmod +x "$BARE/hooks/pre-receive"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-041 remote_delete_rejected 'rejected arm'
  want TEST-041 "$(rstep "$ENG_OUT" detail)" 'protected branch'
  want TEST-041 "$(rstep "$ENG_OUT" detail)" 'pre-receive hook declined'
  bare_has "$BRANCH" || fail TEST-041 'rejected arm: the remote branch is gone'
  # unreadable: git ls-remote fails
  build_world remote_unreadable
  shim="$W/shim"
  make_shim "$shim" ls-remote 'echo "fatal: unable to access" >&2; exit 128'
  PATH="$shim:$PATH" run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-041 remote_unknown 'unreadable arm'
  want TEST-041 "$(rstep "$ENG_OUT" detail)" 'unable to access'
  bare_has "$BRANCH" || fail TEST-041 'unreadable arm: the remote branch is gone'
  echo 'PASS: TEST-041 a rejected or unreadable remote never stops the run'
}

test_043_dependents_retain_remote_branch() {
  # arm dependents: one open PR is based on the head branch
  build_world remote_dependents
  printf '[{"number":512}]\n' > "$GHD/deps-${BRANCH//\//_}.json"
  run_engine plan --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-043 "plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-043 "$ENG_OUT" 'retain origin/ride/foo (remote_has_dependents)'
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-043 remote_has_dependents 'dependents arm'
  want TEST-043 "$(rstep "$ENG_OUT" detail)" '#512'
  want TEST-043 "$(cat "$GHD/gh-argv.log")" "pr list --state open --base $BRANCH --json number --limit 100"
  bare_has "$BRANCH" || fail TEST-043 'dependents arm: the remote branch was deleted'
  # arm unlisted: the dependents query fails, fail closed
  build_world remote_dependents_unknown
  : > "$GHD/deps-fail"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-043 remote_unknown 'unlisted arm'
  bare_has "$BRANCH" || fail TEST-043 'unlisted arm: the remote branch was deleted'
  # arm head-of: an open PR is opened FROM the head branch (into another base)
  build_world remote_head_of_open_pr
  printf '[{"number":611}]\n' > "$GHD/heads-${BRANCH//\//_}.json"
  run_engine plan --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-043 "head-of plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-043 "$ENG_OUT" 'retain origin/ride/foo (remote_has_dependents)'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-043 "head-of apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  retained_arm TEST-043 remote_has_dependents 'head-of arm'
  want TEST-043 "$(rstep "$ENG_OUT" detail)" '#611'
  want TEST-043 "$(rstep "$ENG_OUT" detail)" 'opened from'
  want TEST-043 "$(cat "$GHD/gh-argv.log")" "pr list --state open --head $BRANCH --json number --limit 100"
  bare_has "$BRANCH" || fail TEST-043 'head-of arm: the remote branch was deleted'
  # arm head-unlisted: the head query fails, fail closed
  build_world remote_head_unknown
  : > "$GHD/heads-fail"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-043 remote_unknown 'head-unlisted arm'
  bare_has "$BRANCH" || fail TEST-043 'head-unlisted arm: the remote branch was deleted'
  echo 'PASS: TEST-043 a branch with open dependent pull requests is never deleted'
}

test_044_push_url_must_equal_fetch_url() {
  local other pdig
  # arm pushurl: remote.origin.pushurl names a second bare that also holds the branch at the merged head
  build_world remote_pushurl
  other="$W/other/origin.git"
  run mkdir -p "$W/other"
  run git init -q --bare -b main "$other"
  run git -C "$ORIGIN" push -q "$other" "$HEAD_OID:refs/heads/$BRANCH"
  run git -C "$ORIGIN" config remote.origin.pushurl "$other"
  pdig="$(world_digest)"
  run_engine plan --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-044 "plan exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-044 "$ENG_OUT" 'retain origin/ride/foo (remote_unknown)'
  [[ "$(world_digest)" == "$pdig" ]] || fail TEST-044 'plan changed the fixture'
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-044 remote_unknown 'pushurl arm'
  want TEST-044 "$(rstep "$ENG_OUT" detail)" 'push URL'
  bare_has "$BRANCH" || fail TEST-044 'pushurl arm: the fetch-side remote branch was deleted'
  git -C "$other" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 || fail TEST-044 'pushurl arm: the push-side remote branch was deleted'
  # arm pushInsteadOf: a url.<base>.pushInsteadOf rewrite moves only the push side
  build_world remote_push_instead_of
  other="$W/other/origin.git"
  run mkdir -p "$W/other"
  run git init -q --bare -b main "$other"
  run git -C "$ORIGIN" push -q "$other" "$HEAD_OID:refs/heads/$BRANCH"
  run git -C "$ORIGIN" config "url.$W/other/.pushInsteadOf" "$W/"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-044 remote_unknown 'pushInsteadOf arm'
  bare_has "$BRANCH" || fail TEST-044 'pushInsteadOf arm: the fetch-side remote branch was deleted'
  git -C "$other" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 || fail TEST-044 'pushInsteadOf arm: the push-side remote branch was deleted'
  # arm two pushurls: the first equals the fetch URL, the second names a bare no proof reads
  build_world remote_two_pushurls
  other="$W/other/origin.git"
  run mkdir -p "$W/other"
  run git init -q --bare -b main "$other"
  run git -C "$ORIGIN" push -q "$other" "$HEAD_OID:refs/heads/$BRANCH"
  local fetch_url
  fetch_url="$(git -C "$ORIGIN" remote get-url origin)" || fail TEST-044 'two-pushurls arm: cannot read the fetch URL'
  run git -C "$ORIGIN" config --add remote.origin.pushurl "$fetch_url"
  run git -C "$ORIGIN" config --add remote.origin.pushurl "$other"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-044 remote_unknown 'two-pushurls arm'
  bare_has "$BRANCH" || fail TEST-044 'two-pushurls arm: the fetch-side remote branch was deleted'
  git -C "$other" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 || fail TEST-044 'two-pushurls arm: the second push URL branch was deleted'
  echo 'PASS: TEST-044 a push URL that differs from the fetch URL is never pushed to'
}

test_042_canon_runs_block_unwrapped() {
  local text flat rest step3 sh_block ps_block credit
  text="$(cat "$PROMPT")"
  flat="$(printf '%s' "$text" | tr '\n' ' ' | tr -s ' ')"
  want TEST-042 "$flat" 'as the command itself, never through'
  rest="${flat#*as the command itself, never through}"
  rest="${rest:0:60}"
  want TEST-042 "$rest" 'bash -c'
  want TEST-042 "$rest" 'sh -c'
  want TEST-042 "$rest" 'eval'
  step3="$(awk '/^3\. / { f = 1 } /^Hard rules/ { f = 0 } f' "$PROMPT" | tr '\n' ' ' | tr -s ' ')"
  [[ -n "$step3" ]] || fail TEST-042 'SKILL_MERGE step 3 not found (positive control)'
  unwanted TEST-042 "$step3" 'remote branch deletion'
  want TEST-042 "$step3" 'retained'
  want TEST-042 "$step3" 'never delete'
  sh_block="$(block_of AAI_MERGE_BEGIN AAI_MERGE_END "$PROMPT")"
  ps_block="$(block_of AAI_MERGE_PS_BEGIN AAI_MERGE_PS_END "$PROMPT")"
  [[ -n "$sh_block" && -n "$ps_block" ]] || fail TEST-042 'a merge block is missing (positive control)'
  local blk rm_word='(^|[[:space:];&|(`])rm([[:space:]]|$)'
  for blk in "$sh_block" "$ps_block"; do
    if [[ "$blk" =~ $rm_word ]]; then fail TEST-042 'a block contains rm as a command word'; fi
    unwanted TEST-042 "$blk" 'Remove-Item'
    unwanted TEST-042 "$blk" '--force'
  done
  want TEST-042 "$ps_block" '$env:AAI_GIT_WRITE = $null'
  credit="$(/usr/bin/grep -F 'JUSTIFIED_ADDITIONS+=( "' "$ROOT/tests/skills/lib/prompt-diet-ledger.sh" | sed -n 's/^JUSTIFIED_ADDITIONS+=( "\([0-9][0-9]*\) merge-cleanup-delete-remote-branch .*/\1/p' | awk 'NR == 1')"
  [[ -n "$credit" && "$credit" -gt 0 && "$credit" -le 600 ]] || fail TEST-042 "the prompt-diet ledger credit for merge-cleanup-delete-remote-branch is '$credit', want 1..600"
  echo 'PASS: TEST-042 the canon runs the block unwrapped and the block is clean'
}

# ---------------------------------------------------------------------------
# spec-merge-cleanup-ride-leftovers: the ride's own roadmap entry (TEST-045/046), the ride
# worktree's appended ledger lines (TEST-047/048) and the engine replaced by the merge (TEST-049/050).
ROADMAP_ENGINE="$ROOT/.aai/scripts/roadmap-edit.mjs"
RM='docs/ai/roadmap.yaml'
TR='docs/ai/tests/test-runs.jsonl'

# ship_append_foo: the REAL roadmap-edit ship-append (seam S1) on the origin's tracked roadmap,
# backed by scratch docs (a change-typed intake for foo, a doc for every other pair).
ship_append_foo() {
  local d="$W/rmdocs"
  run mkdir -p "$d/issues"
  other_item_doc > "$d/issues/ISSUE-0002-other-item.md"
  printf -- '---\nid: parent-cap\ntype: rfc\nnumber: 3\nstatus: implementing\nlinks:\n  pr: []\n  commits: []\n---\n\n# Parent\n' > "$d/issues/RFC-0003-parent-cap.md"
  printf -- '---\nid: foo\ntype: change\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Change foo\n' > "$d/issues/CHANGE-DRAFT-foo.md"
  node "$ROADMAP_ENGINE" ship-append --ref foo --intake "$d/issues/CHANGE-DRAFT-foo.md" --roadmap "$ORIGIN/$RM" --docs "$d" >"$W/ship-append.out" 2>&1 || fail SETUP "ship-append failed: $(cat "$W/ship-append.out")"
  want SETUP "$(cat "$ORIGIN/$RM")" '  - capability: foo'
}

test_045_ride_roadmap_entry_taken_from_incoming() {
  local before arch
  ROADMAP_WORLD=1 build_world rmap
  ship_append_foo
  run cp "$ORIGIN/$RM" "$W/roadmap.local"
  git -C "$BARE" show "$MC:$RM" > "$W/roadmap.incoming" || fail SETUP 'incoming roadmap blob'
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  before="$(world_digest)"
  run_engine plan --pr "$PR"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-045 "plan exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-045 "$ENG_OUT" "take incoming $RM (archive the local bytes first)"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-045 'plan changed the world'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-045 "apply exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  cmp "$W/roadmap.incoming" "$ORIGIN/$RM" || fail TEST-045 'roadmap.yaml is not the merge commit blob'
  want TEST-045 "$(cat "$arch/manifest.jsonl")" "\"original\":\"$RM\""
  want TEST-045 "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$(sha_of "$W/roadmap.local")\",\"reason\":\"pre_sync_local_state\""
  cmp "$W/roadmap.local" "$arch/sync/$RM" || fail TEST-045 'the archived roadmap differs from the pre-apply local file'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-045 'origin HEAD is not the merge commit'

  # arm crash: killed right after the roadmap was rewritten to the HEAD blob, a re-run converges
  ROADMAP_WORLD=1 build_world rmap_crash
  ship_append_foo
  run cp "$ORIGIN/$RM" "$W/roadmap.local"
  git -C "$BARE" show "$MC:$RM" > "$W/roadmap.incoming" || fail SETUP 'incoming roadmap blob'
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=sync-after-rewrite run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-045 "crash arm exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-045 "crash arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  cmp "$W/roadmap.incoming" "$ORIGIN/$RM" || fail TEST-045 'crash arm: roadmap.yaml is not the merge commit blob'
  cmp "$W/roadmap.local" "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/$RM" || fail TEST-045 'crash arm: the archived roadmap differs from the pre-apply local file'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-045 'crash arm: origin HEAD is not the merge commit'
  assert_no_merge_call TEST-045
  echo 'PASS: TEST-045 the ride roadmap entry is archived and the incoming roadmap taken'
}

test_046_foreign_roadmap_hunk_refuses_overlap() {
  ROADMAP_WORLD=1 build_world rmap_foreign
  roadmap_base | sed 's/status: done/status: active/' > "$ORIGIN/$RM"
  decide_arm TEST-046 overlap "$RM"

  ROADMAP_WORLD=1 build_world rmap_mixed
  ship_append_foo
  sed 's/status: done/status: active/' "$ORIGIN/$RM" > "$W/mixed.yaml"
  run cp "$W/mixed.yaml" "$ORIGIN/$RM"
  decide_arm TEST-046 overlap "$RM"

  ROADMAP_WORLD=1 build_world rmap_staged
  ship_append_foo
  run git -C "$ORIGIN" add "$RM"
  decide_arm TEST-046 overlap "$RM"

  RIDE_ROADMAP=elsewhere ROADMAP_WORLD=1 build_world rmap_lacks
  ship_append_foo
  decide_arm TEST-046 overlap "$RM"

  # positive control: the ride-only world is not refused
  ROADMAP_WORLD=1 build_world rmap_control
  ship_append_foo
  run_engine plan --pr "$PR"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-046 "control: plan exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  echo 'PASS: TEST-046 a foreign, mixed, staged or unmatched roadmap change gives the overlap decide outcome'
}

LEDGER_RT='{"v":1,"ts":"2026-10-11T00:00:00Z","actor":"ride","event":"tail-run-1"}'
LEDGER_EV1='{"v":1,"ts":"2026-10-11T00:00:01Z","actor":"ride","event":"tail-event-1","ref":"foo","payload":{}}'
LEDGER_EV2='{"v":1,"ts":"2026-10-11T00:00:02Z","actor":"ride","event":"tail-event-2","ref":"foo","payload":{}}'

# seed_ledger_tails: lines appended in the ride worktree after its last commit (one in test-runs, two in EVENTS)
seed_ledger_tails() {
  printf '%s\n' "$LEDGER_RT" >> "$RIDE/$TR"
  printf '%s\n%s\n' "$LEDGER_EV1" "$LEDGER_EV2" >> "$RIDE/docs/ai/EVENTS.jsonl"
  printf '%s\n' "$LEDGER_RT" > "$W/tail-rt"
  printf '%s\n%s\n' "$LEDGER_EV1" "$LEDGER_EV2" > "$W/tail-ev"
}

tail_matches() {
  local tid="$1" ledger="$2" tailf="$3" n
  n="$(wc -c < "$tailf" | tr -d ' ')"
  tail -c "$n" "$ORIGIN/$ledger" > "$W/got-tail" || fail "$tid" "cannot read the end of $ledger"
  cmp "$tailf" "$W/got-tail" || fail "$tid" "the main checkout's $ledger does not end with the appended bytes"
}

test_047_ride_ledger_appends_moved() {
  local before arch rep reports
  LEDGER_WORLD=1 build_world ledg
  seed_ledger_tails
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  before="$(world_digest)"
  run_engine plan --pr "$PR"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-047 "plan exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-047 "$ENG_OUT" 'move 2 line(s) worktree:docs/ai/EVENTS.jsonl -> docs/ai/EVENTS.jsonl'
  want TEST-047 "$ENG_OUT" "move 1 line(s) worktree:$TR -> $TR"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-047 'plan changed the world'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-047 "apply exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  [[ "$(step_status "$rep" remove-worktree)" == done ]] || fail TEST-047 "remove-worktree reported $(step_status "$rep" remove-worktree)"
  [[ ! -e "$RIDE" ]] || fail TEST-047 'the ride worktree is still there'
  tail_matches TEST-047 docs/ai/EVENTS.jsonl "$W/tail-ev"
  tail_matches TEST-047 "$TR" "$W/tail-rt"
  [[ "$(/usr/bin/grep -c '"reason":"ride_ledger_tail"' "$arch/manifest.jsonl" || true)" == 2 ]] || fail TEST-047 'the manifest does not hold two ride_ledger_tail entries'
  cmp "$W/tail-ev" "$arch/worktree-ledger-tails/docs/ai/EVENTS.jsonl" || fail TEST-047 'the archived EVENTS tail differs from the appended bytes'
  cmp "$W/tail-rt" "$arch/worktree-ledger-tails/$TR" || fail TEST-047 'the archived test-runs tail differs from the appended bytes'
  [[ "$(json_get "$rep" 'j.moved.map(m=>m.ledger+":"+m.lines).join(",")')" == "docs/ai/EVENTS.jsonl:2,$TR:1" ]] || fail TEST-047 "JSON moved list is $(json_get "$rep" 'JSON.stringify(j.moved)')"
  [[ "$(json_get "$rep" 'j.moved[0].sha256')" == "$(sha_of "$W/tail-ev")" ]] || fail TEST-047 'JSON moved sha256 is not the tail digest'
  # the text run of a fresh world and the saved report
  LEDGER_WORLD=1 build_world ledg_text
  seed_ledger_tails
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-047 "text apply exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-047 "$ENG_OUT" '  moved 2 line(s) worktree:docs/ai/EVENTS.jsonl -> docs/ai/EVENTS.jsonl'
  want TEST-047 "$ENG_OUT" "  moved 1 line(s) worktree:$TR -> $TR"
  [[ "$(saved_reports | wc -l | tr -d ' ')" == 0 ]] || fail TEST-047 'report was saved to disk'

  # arm crash: killed after the first ledger tail was appended, a re-run appends nothing twice
  LEDGER_WORLD=1 build_world ledg_crash
  seed_ledger_tails
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-047 "crash arm exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-047 "crash arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-047 'crash arm: the ride worktree is still there'
  [[ "$(count_line "$ORIGIN/docs/ai/EVENTS.jsonl" "$LEDGER_EV1")" == 1 ]] || fail TEST-047 'crash arm: event line 1 is not exactly once'
  [[ "$(count_line "$ORIGIN/docs/ai/EVENTS.jsonl" "$LEDGER_EV2")" == 1 ]] || fail TEST-047 'crash arm: event line 2 is not exactly once'
  [[ "$(count_line "$ORIGIN/$TR" "$LEDGER_RT")" == 1 ]] || fail TEST-047 'crash arm: the test-runs line is not exactly once'
  assert_no_merge_call TEST-047
  echo 'PASS: TEST-047 the ride worktree ledger appends are moved to the main checkout'
}

test_048_non_append_ledger_change_refused() {
  local arm
  for arm in rewrite partial staged plus-file plus-untracked; do
    LEDGER_WORLD=1 build_world "ledg_$arm"
    case "$arm" in
      rewrite) sed '1s/.*/{"v":1,"rewritten":true}/' "$RIDE/docs/ai/EVENTS.jsonl" > "$W/rewritten.jsonl"
               run cp "$W/rewritten.jsonl" "$RIDE/docs/ai/EVENTS.jsonl"
               printf '%s\n' "$LEDGER_EV1" >> "$RIDE/docs/ai/EVENTS.jsonl" ;;
      partial) printf '%s' "$LEDGER_EV1" >> "$RIDE/docs/ai/EVENTS.jsonl" ;;
      staged) printf '%s\n' "$LEDGER_EV1" >> "$RIDE/docs/ai/EVENTS.jsonl"
              run git -C "$RIDE" add docs/ai/EVENTS.jsonl ;;
      plus-file) printf '%s\n' "$LEDGER_EV1" >> "$RIDE/docs/ai/EVENTS.jsonl"
                 printf 'edit\n' >> "$RIDE/README.md" ;;
      plus-untracked) printf '%s\n' "$LEDGER_EV1" >> "$RIDE/docs/ai/EVENTS.jsonl"
                      printf 'stray\n' > "$RIDE/stray.txt" ;;
    esac
    keep_arm TEST-048 worktree_dirty "$RIDE" remove-worktree
    [[ -d "$RIDE" ]] || fail TEST-048 "arm $arm: the worktree is gone"
    git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-048 "arm $arm: the branch is gone"
  done

  # arm late: a line lands in a ride ledger after the move and before the late re-verify
  LEDGER_WORLD=1 build_world ledg_late
  printf '%s\n' "$LEDGER_EV1" >> "$RIDE/docs/ai/EVENTS.jsonl"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_TOUCH_AT="before-remove-verify:$TR" run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-048 "late arm exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-048 "$ENG_OUT" 'STOPPED worktree_dirty'
  [[ -d "$RIDE" ]] || fail TEST-048 'late arm: the worktree is gone'
  [[ "$(count_line "$RIDE/$TR" 'written by another session')" == 1 ]] || fail TEST-048 'late arm: the worktree does not hold the late line'
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-048 "late arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$RIDE" ]] || fail TEST-048 'late arm: the re-run left the worktree'
  [[ "$(count_line "$ORIGIN/$TR" 'written by another session')" == 1 ]] || fail TEST-048 'late arm: the late line is not exactly once in the main ledger'
  [[ "$(count_line "$ORIGIN/docs/ai/EVENTS.jsonl" "$LEDGER_EV1")" == 1 ]] || fail TEST-048 'late arm: the first move is not exactly once'
  echo 'PASS: TEST-048 a non-append ledger change keeps the worktree and a late append stops the removal'
}

# the SEED line the ledger world already holds in the main test-runs.jsonl, appended again in the ride
RIDE_DUP='{"v":1,"ts":"2026-10-09T00:00:00Z","actor":"fixture","event":"seed-run"}'

LATE_LINE='{"v":1,"event":"late-after-crash"}'
moved_lines() { json_get "$1" "j.moved.filter(m=>m.ledger===\"$2\").map(m=>m.lines).join(\",\")"; }

test_051_ledger_tail_resume_key_and_count() {
  local rep
  # arm dup: a tail line byte-identical to one already in the main ledger is appended, not skipped
  LEDGER_WORLD=1 build_world dup
  printf '%s\n' "$RIDE_DUP" >> "$RIDE/$TR"
  printf '%s\n' "$RIDE_DUP" > "$W/tail-rt"
  [[ "$(count_line "$ORIGIN/$TR" "$RIDE_DUP")" == 1 ]] || fail SETUP 'the main test-runs ledger does not hold the seed line once'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-051 "dup arm exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  [[ "$(count_line "$ORIGIN/$TR" "$RIDE_DUP")" == 2 ]] || fail TEST-051 'dup arm: the duplicate line was not appended'
  tail_matches TEST-051 "$TR" "$W/tail-rt"
  [[ "$(moved_lines "$rep" "$TR")" == 1 ]] || fail TEST-051 "dup arm: moved lines is [$(moved_lines "$rep" "$TR")], want 1"

  # arm late: crash after the append, a line lands in the ride, the re-run counts what was appended
  LEDGER_WORLD=1 build_world late
  seed_ledger_tails
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-051 "late arm crash exited $ENG_RC, want 137"
  printf '%s\n' "$LATE_LINE" >> "$RIDE/docs/ai/EVENTS.jsonl"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-051 "late arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  [[ "$(count_line "$ORIGIN/docs/ai/EVENTS.jsonl" "$LEDGER_EV1")" == 1 && "$(count_line "$ORIGIN/docs/ai/EVENTS.jsonl" "$LEDGER_EV2")" == 1 ]] || fail TEST-051 'late arm: an event line is not exactly once'
  [[ "$(count_line "$ORIGIN/docs/ai/EVENTS.jsonl" "$LATE_LINE")" == 1 ]] || fail TEST-051 'late arm: the late line is not exactly once'
  [[ "$(moved_lines "$rep" docs/ai/EVENTS.jsonl)" == 3 ]] || fail TEST-051 "late arm: EVENTS moved is [$(moved_lines "$rep" docs/ai/EVENTS.jsonl)], want one entry of 3"

  # arm intent: crash between the append intent and the append; a duplicate of an existing line is still appended once
  LEDGER_WORLD=1 build_world intent
  printf '%s\n' "$RIDE_DUP" >> "$RIDE/$TR"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-intent run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-051 "intent arm crash exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$TR" "$RIDE_DUP")" == 1 ]] || fail TEST-051 'intent arm: the crash was not before the append'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-051 "intent arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$TR" "$RIDE_DUP")" == 2 ]] || fail TEST-051 'intent arm: the re-run did not append the duplicate exactly once'
  [[ "$(moved_lines "$ENG_OUT" "$TR")" == 1 ]] || fail TEST-051 "intent arm: moved lines is [$(moved_lines "$ENG_OUT" "$TR")], want 1"

  # arm after: crash after the append of a duplicate line; the re-run appends nothing more and still counts it
  LEDGER_WORLD=1 build_world after
  printf '%s\n' "$RIDE_DUP" >> "$RIDE/$TR"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-051 "after arm crash exited $ENG_RC, want 137"
  [[ "$(count_line "$ORIGIN/$TR" "$RIDE_DUP")" == 2 ]] || fail TEST-051 'after arm: the append did not happen before the crash'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-051 "after arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$TR" "$RIDE_DUP")" == 2 ]] || fail TEST-051 'after arm: the re-run appended the duplicate again'
  [[ "$(moved_lines "$ENG_OUT" "$TR")" == 1 ]] || fail TEST-051 "after arm: moved lines is [$(moved_lines "$ENG_OUT" "$TR")], want 1"
  assert_no_merge_call TEST-051
  echo 'PASS: TEST-051 a first run appends the whole tail and the moved count is what was appended'
}

test_053_reset_ride_ledger_is_not_a_resume_candidate() {
  local journal late='written by another session' dones
  # arm identical: a later ride tail byte-identical to one already moved (and the ride reset) is appended, not skipped
  LEDGER_WORLD=1 build_world ident
  printf '%s\n' "$late" >> "$RIDE/$TR"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_TOUCH_AT="before-remove-verify:$TR" run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-053 "ident arm stop exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$RIDE/$TR" "$late")" == 1 && "$(count_line "$ORIGIN/$TR" "$late")" == 1 ]] || fail TEST-053 'ident arm: the stop did not leave one line in the ride and one in main'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-053 "ident arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$TR" "$late")" == 2 ]] || fail TEST-053 "ident arm: main holds the identical later line $(count_line "$ORIGIN/$TR" "$late") times, want 2 (once per write)"
  [[ "$(moved_lines "$ENG_OUT" "$TR")" == 2 ]] || fail TEST-053 "ident arm: moved lines is [$(moved_lines "$ENG_OUT" "$TR")], want 2"

  # arm double-intent: three intents for one archive, one append; the journal holds exactly one done record
  LEDGER_WORLD=1 build_world dint
  printf '%s\n' "$RIDE_DUP" >> "$RIDE/$TR"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-intent run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-053 "dint arm first crash exited $ENG_RC, want 137"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-intent run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-053 "dint arm second crash exited $ENG_RC, want 137"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-053 "dint arm third crash exited $ENG_RC, want 137"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-053 "dint arm re-run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$TR" "$RIDE_DUP")" == 2 ]] || fail TEST-053 'dint arm: the duplicate line is not appended exactly once'
  journal="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/journal.jsonl"
  dones="$(/usr/bin/grep -c '"step":"ledger-append","status":"done"' "$journal" || true)"
  [[ "$dones" == 1 ]] || fail TEST-053 "dint arm: the journal holds $dones done records for one append, want 1"
  [[ "$(moved_lines "$ENG_OUT" "$TR")" == 1 ]] || fail TEST-053 "dint arm: moved lines is [$(moved_lines "$ENG_OUT" "$TR")], want 1"
  echo 'PASS: TEST-053 a reset ride ledger is no resume candidate and every append has exactly one done record'
}

test_054_resume_matches_the_appended_segment() {
  local ev=docs/ai/EVENTS.jsonl
  # arm crash-crash: crash after the append of a two-line tail, a late line lands, the recovery appends it and
  # crashes again; the last run must not append the late line a second time
  LEDGER_WORLD=1 build_world segcc
  seed_ledger_tails
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-054 "segcc first crash exited $ENG_RC, want 137"
  printf '%s\n' "$LATE_LINE" >> "$RIDE/$ev"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-054 "segcc second crash exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$ev" "$LATE_LINE")" == 1 ]] || fail TEST-054 'segcc: the recovery did not append the late line once before the crash'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-054 "segcc final run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$ev" "$LEDGER_EV1")" == 1 && "$(count_line "$ORIGIN/$ev" "$LEDGER_EV2")" == 1 ]] || fail TEST-054 'segcc: an original event line is not exactly once'
  [[ "$(count_line "$ORIGIN/$ev" "$LATE_LINE")" == 1 ]] || fail TEST-054 "segcc: the late line is in main $(count_line "$ORIGIN/$ev" "$LATE_LINE") times, want 1"
  [[ "$(moved_lines "$ENG_OUT" "$ev")" == 3 ]] || fail TEST-054 "segcc: EVENTS moved is [$(moved_lines "$ENG_OUT" "$ev")], want one entry of 3"

  # arm touch: crash after the append, a late line lands, the recovery moves it and a TOUCH_AT line stops the run,
  # a crash during the next recovery loses its done record; the final run keeps every line once
  LEDGER_WORLD=1 build_world segtc
  seed_ledger_tails
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-054 "segtc first crash exited $ENG_RC, want 137"
  printf '%s\n' "$LATE_LINE" >> "$RIDE/$ev"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_TOUCH_AT="before-remove-verify:$ev" run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-054 "segtc touch stop exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-054 "segtc second crash exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-054 "segtc final run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$ev" "$LEDGER_EV1")" == 1 && "$(count_line "$ORIGIN/$ev" "$LEDGER_EV2")" == 1 ]] || fail TEST-054 'segtc: an original event line is not exactly once'
  [[ "$(count_line "$ORIGIN/$ev" "$LATE_LINE")" == 1 ]] || fail TEST-054 "segtc: the late line is in main $(count_line "$ORIGIN/$ev" "$LATE_LINE") times, want 1"
  [[ "$(count_line "$ORIGIN/$ev" 'written by another session')" == 1 ]] || fail TEST-054 'segtc: the touched line is not exactly once'
  [[ "$(moved_lines "$ENG_OUT" "$ev")" == 4 ]] || fail TEST-054 "segtc: EVENTS moved is [$(moved_lines "$ENG_OUT" "$ev")], want one entry of 4"
  assert_no_merge_call TEST-054
  echo 'PASS: TEST-054 a resume matches the segment an intent appended, never the whole archived tail'
}

test_055_unappended_intent_is_not_counted() {
  local ev=docs/ai/EVENTS.jsonl late2='{"v":1,"event":"late-after-crash-two"}'
  # arm ovc: crash after the intent (nothing appended), a late line lands, crash after the append of the larger
  # tail; the never-appended first intent must not get a done record, so moved is the 3 lines appended
  LEDGER_WORLD=1 build_world ovc
  seed_ledger_tails
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-intent run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-055 "ovc first crash exited $ENG_RC, want 137"
  printf '%s\n' "$LATE_LINE" >> "$RIDE/$ev"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-055 "ovc second crash exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-055 "ovc final run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$ev" "$LEDGER_EV1")" == 1 && "$(count_line "$ORIGIN/$ev" "$LEDGER_EV2")" == 1 ]] || fail TEST-055 'ovc: an original event line is not exactly once'
  [[ "$(count_line "$ORIGIN/$ev" "$LATE_LINE")" == 1 ]] || fail TEST-055 "ovc: the late line is in main $(count_line "$ORIGIN/$ev" "$LATE_LINE") times, want 1"
  [[ "$(moved_lines "$ENG_OUT" "$ev")" == 3 ]] || fail TEST-055 "ovc: EVENTS moved is [$(moved_lines "$ENG_OUT" "$ev")], want one entry of 3"

  # arm itc: crash after the intent, late line, a second crash after the intent, a second late line, crash after
  # the append; the two earlier intents appended nothing and must not be counted (moved is 4, not 9)
  LEDGER_WORLD=1 build_world itc
  seed_ledger_tails
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-intent run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-055 "itc first crash exited $ENG_RC, want 137"
  printf '%s\n' "$LATE_LINE" >> "$RIDE/$ev"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-intent run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-055 "itc second crash exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  printf '%s\n' "$late2" >> "$RIDE/$ev"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=ledger-move-after-append run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-055 "itc third crash exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-055 "itc final run exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(count_line "$ORIGIN/$ev" "$LEDGER_EV1")" == 1 && "$(count_line "$ORIGIN/$ev" "$LEDGER_EV2")" == 1 ]] || fail TEST-055 'itc: an original event line is not exactly once'
  [[ "$(count_line "$ORIGIN/$ev" "$LATE_LINE")" == 1 && "$(count_line "$ORIGIN/$ev" "$late2")" == 1 ]] || fail TEST-055 'itc: a late line is not exactly once'
  [[ "$(moved_lines "$ENG_OUT" "$ev")" == 4 ]] || fail TEST-055 "itc: EVENTS moved is [$(moved_lines "$ENG_OUT" "$ev")], want one entry of 4"
  assert_no_merge_call TEST-055
  echo 'PASS: TEST-055 an intent whose append a later run judged missing is never counted as moved'
}

test_056_historical_journal_tolerance() {
  build_world hist_journal
  local arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  run mkdir -p "$arch"
  cat > "$arch/journal.jsonl" << 'EOF'
{"step":"archive-drafts","status":"done","detail":"2 archived","timestamp":"2026-10-10T00:00:00Z"}
{"step":"state","status":"done","detail":"cleared","timestamp":"2026-10-10T00:00:01Z"}
{"step":"index-audit","status":"done","detail":"clean","timestamp":"2026-10-10T00:00:02Z"}
{"step":"reexec","status":"done","detail":"re-executed","timestamp":"2026-10-10T00:00:03Z"}
{"step":"delete-remote-branch","status":"done","detail":"ride/foo","timestamp":"2026-10-10T00:00:04Z"}
EOF
  run_engine plan --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-056 "plan exited $ENG_RC on historical journal"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-056 "apply exited $ENG_RC on historical journal"
  echo 'PASS: TEST-056 historical journal reader tolerates removed steps'
}

test_057_codebase_reduction_and_green_suite() {
  local count
  count="$(wc -l < "$ROOT/.aai/scripts/merge-cleanup.mjs" | tr -d ' ')"
  [[ "$count" -le 1722 ]] || fail TEST-057 "merge-cleanup.mjs has $count lines, want <= 1722"
  echo 'PASS: TEST-057 codebase reduction verified (line count decreased by >= 250 lines)'
}

test_058_merge_cleanup_line_ceiling() {
  local count
  count="$(wc -l < "$ROOT/.aai/scripts/merge-cleanup.mjs" | tr -d ' ')"
  [[ "$count" -le 1490 ]] || fail TEST-058 "merge-cleanup.mjs has $count lines, want <= 1490"
  echo "PASS: TEST-058 codebase reduction verified (line count $count <= 1490)"
}

test_059_lane_gate_passes_without_pr_sweep() {
  # Spec-AC-04 (TEST-004 / SPEC-0227): lane-gate.mjs passes without pr_sweep event in EVENTS.jsonl
  build_world t059_nosweep
  grep -q '"event":"pr_sweep"' "$RIDE/docs/ai/EVENTS.jsonl" && fail TEST-004 "EVENTS.jsonl must not contain pr_sweep"
  local out code=0
  out="$(node "$ROOT/.aai/scripts/lane-gate.mjs" --sweep-check --pr "$PR" --repo-root "$RIDE" 2>&1)" || code=$?
  [[ "$code" -eq 0 ]] || fail TEST-004 "lane-gate.mjs --sweep-check must exit 0 without pr_sweep event, got $code: $out"
  want TEST-004 "$out" "SWEEP-CHECK allowed"
  want TEST-004 "$out" "outcome=live"
  echo "PASS: TEST-004 lane-gate passes without pr_sweep event in EVENTS.jsonl (Spec-AC-04)"
}

test_060_skill_pr_prompt_free_of_pr_sweep() {
  # Spec-AC-02 (TEST-002 / SPEC-0227): SKILL_PR prompt free of pr_sweep commit instructions
  local pr_doc="$ROOT/.aai/SKILL_PR.prompt.md"
  if grep -qF 'append-event.mjs --event pr_sweep' "$pr_doc"; then
    fail TEST-002 "SKILL_PR.prompt.md must not contain append-event.mjs --event pr_sweep"
  fi
  if grep -qF 'links.commits' "$pr_doc"; then
    fail TEST-002 "SKILL_PR.prompt.md must not reference links.commits"
  fi
  if grep -qF -e '--stamp-pr' "$pr_doc"; then
    fail TEST-002 "SKILL_PR.prompt.md must not reference --stamp-pr"
  fi
  if grep -qF 'close-before-push-guard.mjs' "$pr_doc"; then
    fail TEST-002 "SKILL_PR.prompt.md must not reference close-before-push-guard.mjs"
  fi
  echo "PASS: TEST-002 SKILL_PR prompt free of pr_sweep and ceremony commit instructions (Spec-AC-02)"
}

test_061_prompt_diet_passes() {
  # Spec-AC-07 (TEST-007 / SPEC-0227): SKILL_PR prompt diet verified
  local out code=0
  out="$(bash "$ROOT/tests/skills/test-aai-prompt-diet.sh" test_010_audit_and_reduction 2>&1)" || code=$?
  [[ "$code" -eq 0 ]] || fail TEST-007 "test-aai-prompt-diet.sh failed ($code): $out"
  echo "PASS: TEST-007 SKILL_PR prompt diet verified (Spec-AC-07)"
}

# ---------------------------------------------------------------------------
# spec-git-platform-detected-at-bootstrap C: merge-cleanup on the platform adapter
# (TEST-068 generic refusals, TEST-070 Azure preflight, TEST-072 Azure apply,
# TEST-073 platform mismatch, TEST-074 GitHub recorded and the legacy notice).

AZ_ORG_URL='https://dev.azure.com/acme/Proj/_git/foo'
AZ_A1="repos pr show --id 433 --detect true --output json"
AZ_A4='devops invoke --area git --resource pullRequestThreads --route-parameters project=proj-id-1111 repositoryId=repo-id-2222 pullRequestId=433 --org https://dev.azure.com/acme --api-version 7.1 --http-method GET --output json'

# write_az_stub <dir>: az stub, deny-by-default. Accepted calls are exactly A1 to A4 of the spec (D8);
# every call is logged to az-argv.log in the same directory the gh stub uses.
write_az_stub() {
  local d="$1"
  run mkdir -p "$d/bin"
  cat > "$d/bin/az" <<'AZSTUB'
#!/usr/bin/env bash
dir="${GH_STUB_DIR:-}"
[ -n "$dir" ] && [ -d "$dir" ] || { echo 'STUB-DENY: GH_STUB_DIR unset' >&2; exit 1; }
printf '%s\n' "$*" >> "$dir/az-argv.log"
a4='devops invoke --area git --resource pullRequestThreads --route-parameters project=proj-id-1111 repositoryId=repo-id-2222 pullRequestId=433 --org https://dev.azure.com/acme --api-version 7.1 --http-method GET --output json'
if [ "$*" = "repos pr show --id 433 --detect true --output json" ]; then
  [ -f "$dir/az-show-fail" ] && { echo 'STUB: az repos pr show failed' >&2; exit 1; }
  [ -f "$dir/azpr-433.json" ] && { cat "$dir/azpr-433.json"; exit 0; }
fi
if [ "$#" -eq 13 ] && [ "$1 $2 $3 $4 $5 $6" = "repos pr list --status active --target-branch" ] && [ "$8 $9 ${10} ${11} ${12} ${13}" = "--top 100 --detect true --output json" ]; then
  key="${7//\//_}"
  if [ -f "$dir/az-deps-$key.json" ]; then cat "$dir/az-deps-$key.json"; else echo '[]'; fi
  exit 0
fi
if [ "$#" -eq 13 ] && [ "$1 $2 $3 $4 $5 $6" = "repos pr list --status active --source-branch" ] && [ "$8 $9 ${10} ${11} ${12} ${13}" = "--top 100 --detect true --output json" ]; then
  key="${7//\//_}"
  if [ -f "$dir/az-heads-$key.json" ]; then cat "$dir/az-heads-$key.json"; else echo '[]'; fi
  exit 0
fi
if [ "$*" = "$a4" ]; then
  [ -f "$dir/az-threads-fail" ] && { echo 'STUB: az devops invoke failed' >&2; exit 1; }
  if [ -f "$dir/az-threads.json" ]; then cat "$dir/az-threads.json"; else echo '{"value":[]}'; fi
  exit 0
fi
printf 'STUB-DENY: unexpected argv: %s\n' "$*" >&2
exit 1
AZSTUB
  run chmod +x "$d/bin/az"
  : > "$d/az-argv.log"
}

# write_az_pr <status> <isDraft> <head> [webUrl]: the A1 fixture. AZ_FORK=1 adds a forkSource.
write_az_pr() {
  local status="$1" draft="$2" head="$3" web="${4:-$AZ_ORG_URL}" fork='' mcj=''
  if [[ -n "${AZ_FORK:-}" ]]; then fork=',"forkSource":{"repository":{"id":"fork-1"}}'; fi
  if [[ "$status" == completed ]]; then mcj=",\"lastMergeCommit\":{\"commitId\":\"$MC\"}"; fi
  printf '{"pullRequestId":%s,"status":"%s","isDraft":%s,"sourceRefName":"refs/heads/%s","targetRefName":"refs/heads/main","lastMergeSourceCommit":{"commitId":"%s"}%s%s,"repository":{"id":"repo-id-2222","name":"foo","webUrl":"%s","url":"https://dev.azure.com/acme/proj-id-1111/_apis/git/repositories/repo-id-2222","project":{"id":"proj-id-1111"}}}\n' \
    "$PR" "$status" "$draft" "$BRANCH" "$head" "$mcj" "$fork" "$web" > "$GHD/azpr-$PR.json"
}

# record_platform <dir> <value>: a recorded platform in <dir>/docs/ai/pr-config.yaml, hidden from git status.
record_platform() {
  [[ -n "$1" && "$1" = /* && -d "$1" ]] || fail SETUP "record_platform dir: $1"
  mkdir -p "$1/docs/ai" || fail SETUP 'record_platform mkdir'
  printf 'platform: %s\n' "$2" > "$1/docs/ai/pr-config.yaml"
  printf 'docs/ai/pr-config.yaml\n' >> "$ORIGIN/.git/info/exclude"
}

empty_logs() { [[ ! -s "$GHD/gh-argv.log" && ! -s "$GHD/az-argv.log" ]]; }

# generic_refusal <tid> <label> <engine args...>: exit 3, platform_generic with a manual, no gh_ reason, no CLI spawned, world unchanged.
generic_refusal() {
  local tid="$1" label="$2" before
  shift 2
  before="$(world_digest)"
  : > "$GHD/gh-argv.log"; : > "$GHD/az-argv.log"
  run_engine "$@"
  [[ "$ENG_RC" -eq 3 ]] || fail "$tid" "$label exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want "$tid" "$ENG_OUT" 'REFUSE platform_generic'
  want "$tid" "$ENG_OUT" 'manual:'
  unwanted "$tid" "$ENG_OUT" 'gh_'
  unwanted "$tid" "$ENG_ERR" 'gh_'
  empty_logs || fail "$tid" "$label spawned a platform CLI: $(cat "$GHD/gh-argv.log" "$GHD/az-argv.log")"
  [[ "$(world_digest)" == "$before" ]] || fail "$tid" "$label changed the fixture"
}

test_068_generic_refuses_with_manual() {
  local rec
  for rec in unknown none; do
    open_world "generic_$rec"
    write_az_stub "$GHD"
    write_pr_json MERGED "$MC"
    record_platform "$ORIGIN" "$rec"
    record_platform "$RIDE" "$rec"
    generic_refusal TEST-068 "$rec preflight" preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by human --direction 'merge 433 please' --origin "$RIDE"
    generic_refusal TEST-068 "$rec plan" plan --pr "$PR"
    generic_refusal TEST-068 "$rec apply" apply --pr "$PR" --pid 4242
  done
  # positive control: with no record the same world reads the PR through gh
  rm -f "$ORIGIN/docs/ai/pr-config.yaml" "$RIDE/docs/ai/pr-config.yaml"
  : > "$GHD/gh-argv.log"
  run_engine plan --pr "$PR"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-068 "unrecorded control exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-068 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"
  echo 'PASS: TEST-068 a recorded unknown or none platform refuses with the manual route'
}

# az_refusal <reason> <engine args...>: a named refusal and an empty gh log (the Azure arms never touch gh).
az_refusal() {
  local reason="$1"
  shift
  expect_refusal TEST-070 "$reason" "$@"
  [[ ! -s "$GHD/gh-argv.log" ]] || fail TEST-070 "arm $reason invoked gh: $(cat "$GHD/gh-argv.log")"
}

test_070_azure_preflight_ready_and_refusals() {
  open_world az_preflight
  write_az_stub "$GHD"
  run git -C "$ORIGIN" remote set-url origin "$AZ_ORG_URL"
  local before engdir line path want_line
  engdir="$(cd "$ROOT/.aai/scripts" && pwd -P)" || fail SETUP 'engine dir'
  [[ -n "$engdir" && "$engdir" = /* ]] || fail SETUP 'engine dir not absolute'
  want_line="node \"$engdir/platform.mjs\" merge --pr $PR --expect-head $HEAD_OID --operator-merge"
  write_az_pr active false "$HEAD_OID"
  before="$(world_digest)"
  : > "$GHD/gh-argv.log"; : > "$GHD/az-argv.log"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-070 "azure ready exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(printf '%s\n' "$ENG_OUT" | { /usr/bin/grep -c 'platform.mjs" merge --pr' || true; })" == 1 ]] || fail TEST-070 "want exactly one merge line: $ENG_OUT"
  line="$(printf '%s\n' "$ENG_OUT" | /usr/bin/grep 'platform.mjs" merge --pr')"
  [[ "$line" == "$want_line" ]] || fail TEST-070 "merge line is not the D9 form: $line"
  # the line must run in PowerShell and cmd too: no POSIX NAME=value prefix (code-review r3, Codex P1)
  [[ ! "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || fail TEST-070 "merge line starts with a POSIX env prefix PowerShell cannot run: $line"
  unwanted TEST-070 "$ENG_OUT" 'gh pr merge'
  path="${line#*node \"}"; path="${path%%\"*}"
  [[ -f "$path" ]] || fail TEST-070 "the printed engine path does not exist: $path"
  [[ ! -s "$GHD/gh-argv.log" ]] || fail TEST-070 "azure preflight invoked gh: $(cat "$GHD/gh-argv.log")"
  [[ "$(cat "$GHD/az-argv.log")" == "$AZ_A1"$'\n'"$AZ_A4" ]] || fail TEST-070 "az log is not exactly A1 and A4: $(cat "$GHD/az-argv.log")"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-070 'azure preflight changed the fixture'
  # resolved or system threads never block (only active and pending do)
  printf '{"value":[{"id":1,"status":"closed","comments":[{"content":"x"}]},{"id":2,"status":"fixed","comments":[{"content":"x"}]},{"id":3,"comments":[{"content":"system"}]},{"id":4,"status":"active","isDeleted":true,"comments":[{"content":"gone"}]}]}\n' > "$GHD/az-threads.json"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-070 "resolved-threads control exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  rm -f "$GHD/az-threads.json"

  write_az_pr active false 0123456789012345678901234567890123456789
  az_refusal head_changed pf
  write_az_pr active true "$HEAD_OID"
  az_refusal draft pf
  write_az_pr abandoned false "$HEAD_OID"
  az_refusal not_open pf
  write_az_pr active false "$HEAD_OID" 'https://dev.azure.com/acme/Proj/_git/other'
  az_refusal repo_mismatch pf
  want TEST-070 "$ENG_OUT" 'acme/proj/foo'
  write_az_pr active false "$HEAD_OID"
  printf '{"value":[{"id":7,"status":"active","comments":[{"content":"fix this","author":{"displayName":"Rev"}}]}]}\n' > "$GHD/az-threads.json"
  az_refusal review_unresolved pf
  want TEST-070 "$ENG_OUT" 'Rev'
  printf '{"value":[{"id":8,"status":"pending","comments":[{"content":"wait","author":{"displayName":"Rev"}}]}]}\n' > "$GHD/az-threads.json"
  az_refusal review_unresolved pf
  rm -f "$GHD/az-threads.json"
  : > "$GHD/az-show-fail"
  az_refusal az_read_failed pf
  rm -f "$GHD/az-show-fail"
  # completed: already_merged, exit 0, still no gh
  write_az_pr completed false "$HEAD_OID"
  : > "$GHD/gh-argv.log"
  pf
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-070 "completed PR exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-070 "$ENG_OUT" already_merged
  [[ ! -s "$GHD/gh-argv.log" ]] || fail TEST-070 "already_merged arm invoked gh"
  # control: the ready fixture is ready again after the refusal arms
  write_az_pr active false "$HEAD_OID"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-070 "ready control exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  echo 'PASS: TEST-070 azure preflight is READY with zero gh calls and refuses on each gate'
}

test_072_azure_apply_cleanup() {
  local a1 a2 a3
  build_world az_apply
  a1="$AZ_A1"
  a2="repos pr list --status active --target-branch $BRANCH --top 100 --detect true --output json"
  a3="repos pr list --status active --source-branch $BRANCH --top 100 --detect true --output json"
  write_az_stub "$GHD"
  record_platform "$ORIGIN" azure
  write_az_pr completed false "$HEAD_OID"
  bare_has "$BRANCH" || fail SETUP 'the bare has no ride branch (positive control)'
  : > "$GHD/gh-argv.log"; : > "$GHD/az-argv.log"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-072 "azure apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -d "$RIDE" ]] || fail TEST-072 'the ride worktree still exists'
  if bare_has "$BRANCH"; then fail TEST-072 'the bare still has the ride branch'; fi
  [[ "$(cat "$GHD/az-argv.log")" == "$a1"$'\n'"$a2"$'\n'"$a3" ]] || fail TEST-072 "az log is not exactly A1, A2, A3: $(cat "$GHD/az-argv.log")"
  [[ ! -s "$GHD/gh-argv.log" ]] || fail TEST-072 "azure apply invoked gh: $(cat "$GHD/gh-argv.log")"
  # fork arm: retained as remote_fork, the bare branch stays
  build_world az_apply_fork
  write_az_stub "$GHD"
  record_platform "$ORIGIN" azure
  AZ_FORK=1 write_az_pr completed false "$HEAD_OID"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-072 remote_fork 'azure fork arm'
  bare_has "$BRANCH" || fail TEST-072 'fork arm: the remote branch was deleted'
  # dependents arms: an open PR based on, then opened from, the branch (A2, A3)
  build_world az_apply_dep
  write_az_stub "$GHD"
  record_platform "$ORIGIN" azure
  write_az_pr completed false "$HEAD_OID"
  printf '[{"pullRequestId":512}]\n' > "$GHD/az-deps-${BRANCH//\//_}.json"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-072 remote_has_dependents 'azure dependents arm'
  want TEST-072 "$(rstep "$ENG_OUT" detail)" '#512'
  bare_has "$BRANCH" || fail TEST-072 'dependents arm: the remote branch was deleted'
  build_world az_apply_head
  write_az_stub "$GHD"
  record_platform "$ORIGIN" azure
  write_az_pr completed false "$HEAD_OID"
  printf '[{"pullRequestId":611}]\n' > "$GHD/az-heads-${BRANCH//\//_}.json"
  run_engine apply --pr "$PR" --pid 4242 --json
  retained_arm TEST-072 remote_has_dependents 'azure head-of arm'
  want TEST-072 "$(rstep "$ENG_OUT" detail)" '#611'
  bare_has "$BRANCH" || fail TEST-072 'head-of arm: the remote branch was deleted'
  echo 'PASS: TEST-072 azure apply cleans up through A1, A2 and A3 only'
}

test_073_platform_mismatch_refuses_before_any_read() {
  local arm rec url
  for arm in 'azure|https://github.com/example/repo.git' 'github|https://dev.azure.com/acme/Proj/_git/foo'; do
    rec="${arm%%|*}"; url="${arm#*|}"
    open_world "mismatch_$rec"
    write_az_stub "$GHD"
    write_pr_json MERGED "$MC"
    run git -C "$ORIGIN" remote set-url origin "$url"
    record_platform "$ORIGIN" "$rec"
    record_platform "$RIDE" "$rec"
    local detected='github'
    if [[ "$rec" == github ]]; then detected='azure'; fi
    local before
    before="$(world_digest)"
    : > "$GHD/gh-argv.log"; : > "$GHD/az-argv.log"
    local mode
    for mode in preflight plan apply; do
      case "$mode" in
        preflight) run_engine preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by human --direction 'merge 433 please' --origin "$RIDE" ;;
        plan) run_engine plan --pr "$PR" ;;
        apply) run_engine apply --pr "$PR" --pid 4242 ;;
      esac
      [[ "$ENG_RC" -eq 3 ]] || fail TEST-073 "$rec $mode exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
      want TEST-073 "$ENG_OUT" "REFUSE platform_mismatch recorded=$rec detected=$detected"
      want TEST-073 "$ENG_OUT" 'record --force'
      empty_logs || fail TEST-073 "$rec $mode spawned a platform CLI: $(cat "$GHD/gh-argv.log" "$GHD/az-argv.log")"
      [[ "$(world_digest)" == "$before" ]] || fail TEST-073 "$rec $mode changed the fixture"
    done
    # NB-5: the record is read at the git toplevel, so a run from a subdirectory refuses the same way
    run mkdir -p "$ORIGIN/sub/dir"
    local sub_origin="$ORIGIN/sub/dir"
    for mode in preflight plan apply; do
      case "$mode" in
        preflight) ENG_CWD="$sub_origin" run_engine preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by human --direction 'merge 433 please' ;;
        plan) ENG_CWD="$sub_origin" run_engine plan --pr "$PR" ;;
        apply) ENG_CWD="$sub_origin" run_engine apply --pr "$PR" --pid 4242 ;;
      esac
      [[ "$ENG_RC" -eq 3 ]] || fail TEST-073 "$rec $mode from a subdirectory exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
      want TEST-073 "$ENG_OUT" "REFUSE platform_mismatch recorded=$rec detected=$detected"
      empty_logs || fail TEST-073 "$rec $mode from a subdirectory spawned a platform CLI"
    done
  done
  echo 'PASS: TEST-073 a recorded platform that contradicts the origin refuses before any read'
}

test_074_github_recorded_and_legacy_unchanged() {
  local pinned out_legacy
  open_world gh_recorded
  write_az_stub "$GHD"
  pinned="AAI_OPERATOR_MERGE=1 gh pr merge $PR --squash --match-head-commit $HEAD_OID"
  record_platform "$RIDE" github
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-074 "recorded github exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(printf '%s\n' "$ENG_OUT" | /usr/bin/grep 'gh pr merge')" == "$pinned" ]] || fail TEST-074 "printed command is not the pinned one: $ENG_OUT"
  [[ -z "$ENG_ERR" ]] || fail TEST-074 "recorded github printed on stderr: $ENG_ERR"
  out_legacy="$ENG_OUT"
  [[ ! -s "$GHD/az-argv.log" ]] || fail TEST-074 'github run invoked az'
  rm -f "$RIDE/docs/ai/pr-config.yaml"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-074 "unrecorded exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  [[ "$ENG_OUT" == "$out_legacy" ]] || fail TEST-074 "unrecorded stdout differs from the recorded run"
  want TEST-074 "$ENG_ERR" 'platform not recorded'
  [[ "$(printf '%s\n' "$ENG_ERR" | wc -l | tr -d ' ')" == 1 ]] || fail TEST-074 "want exactly one stderr line: $ENG_ERR"
  echo 'PASS: TEST-074 recorded github prints the pinned line; unrecorded adds one notice only'
}

# ---------------------------------------------------------------------------
# spec-ride-state-handoff-to-worktree TEST-011 (Spec-AC-11): the reconcile-origin step.
# The origin STATE still holds the merged ride's focus, work item and a run that the merged
# METRICS ledger already carries; apply clears them through ride-handoff.mjs reconcile.
RH_RUN_ROLE='Planning'
RH_RUN_STARTED='2026-10-10T08:00:00Z'
seed_ride_075() {
  printf '{"date_utc":"2026-10-10","ref_id":"%s","title":"foo","agent_runs":[{"role":"%s","model_id":"claude-opus-5-5","started_utc":"%s","ended_utc":"2026-10-10T08:10:00Z"}]}\n' \
    "$ISSUE_ID" "$RH_RUN_ROLE" "$RH_RUN_STARTED" > "$RIDE/docs/ai/METRICS.jsonl"
  run git -C "$RIDE" add docs/ai/METRICS.jsonl
}
# origin_state_075 <run started>: an origin STATE with the stale focus and one foo run
origin_state_075() {
  printf 'project_status: active\ncurrent_focus:\n  type: intake_change\n  ref_id: foo\n  primary_path: docs/issues/ISSUE-DRAFT-foo.md\n  spec_path: null\nactive_work_items:\n  - ref_id: foo\n    status: in_progress\n    phase: planning\nmetrics:\n  work_items:\n    foo:\n      agent_runs:\n        - role: %s\n          model_id: claude-opus-5-5\n          started_utc: %s\n          ended_utc: 2026-10-10T08:10:00Z\n    other-ride:\n      agent_runs:\n        - role: Planning\n          model_id: claude-opus-5-5\n          started_utc: 2026-10-09T08:00:00Z\n          ended_utc: 2026-10-09T08:10:00Z\nupdated_at_utc: 2026-10-10T09:00:00Z\n' \
    "$RH_RUN_ROLE" "$1" > "$ORIGIN/$STATE_REL"
}

test_075_reconcile_origin_step() {
  local rep second journal steps other_before
  RIDE_SEED=seed_ride_075 build_world rh075
  origin_state_075 "$RH_RUN_STARTED"
  other_before="$(state_block "$ORIGIN/$STATE_REL" metrics | awk '/other-ride:/ {f=1} f')"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-075 "ride-handoff TEST-011 apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  steps="$(json_get "$rep" 'j.steps.map(s=>s.id).join(" ")')"
  [[ "$steps" == 'resolve plan archive-drafts archive-runtime sync-base reconcile-origin remove-worktree delete-branch report' ]] || fail TEST-075 "ride-handoff TEST-011 step list is: $steps"
  [[ "$(step_status "$rep" reconcile-origin)" == done ]] || fail TEST-075 "ride-handoff TEST-011 reconcile-origin reported $(step_status "$rep" reconcile-origin), want done"
  journal="$(cat "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/journal.jsonl")"
  want TEST-075 "$journal" '"step":"reconcile-origin"'
  unwanted TEST-075 "$(state_block "$ORIGIN/$STATE_REL" current_focus)" 'ref_id: foo'
  unwanted TEST-075 "$(cat "$ORIGIN/$STATE_REL")" 'ref_id: foo'
  unwanted TEST-075 "$(state_block "$ORIGIN/$STATE_REL" metrics)" '    foo:'
  [[ "$(state_block "$ORIGIN/$STATE_REL" metrics | awk '/other-ride:/ {f=1} f')" == "$other_before" ]] || fail TEST-075 'ride-handoff TEST-011 the foreign metrics entry changed'
  [[ "$(find "$ORIGIN/docs/ai/archive/handoffs" -name record.json | wc -l | tr -d ' ')" == 1 ]] || fail TEST-075 'ride-handoff TEST-011 want one reconcile archive'
  [[ "$(json_get "$rep" 'j.remaining.filter(r=>r.includes("reconcile")).length')" == 0 ]] || fail TEST-075 'ride-handoff TEST-011 a clean reconcile left a remaining entry'
  # a re-run reports the step as a no-op and changes nothing
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-075 "ride-handoff TEST-011 rerun exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  second="$ENG_OUT"
  [[ "$(step_status "$second" reconcile-origin)" == noop ]] || fail TEST-075 "ride-handoff TEST-011 rerun reconcile-origin reported $(step_status "$second" reconcile-origin), want noop"
  [[ "$(find "$ORIGIN/docs/ai/archive/handoffs" -name record.json | wc -l | tr -d ' ')" == 1 ]] || fail TEST-075 'ride-handoff TEST-011 the rerun wrote a second archive'

  # an unledgered run: retained, named in remaining, apply still exits 0, STATE untouched
  RIDE_SEED=seed_ride_075 build_world rh075b
  origin_state_075 '2026-10-10T08:05:00Z'
  local pre; pre="$(sha_of "$ORIGIN/$STATE_REL")"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-075 "ride-handoff TEST-011 unledgered apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" reconcile-origin)" == retained ]] || fail TEST-075 "ride-handoff TEST-011 unledgered reconcile-origin reported $(step_status "$ENG_OUT" reconcile-origin), want retained"
  want TEST-075 "$(json_get "$ENG_OUT" 'j.remaining')" 'origin_runs_not_in_ledger'
  [[ "$(sha_of "$ORIGIN/$STATE_REL")" == "$pre" ]] || fail TEST-075 'ride-handoff TEST-011 a refused reconcile changed the origin STATE'
  [[ "$(step_status "$ENG_OUT" report)" != "" ]] || fail TEST-075 'ride-handoff TEST-011 the later steps did not run'

  # a child that fails WITHOUT printing REFUSE (a STATE with a duplicate top-level key) is a failed step, not an owner decision:
  # apply stops (exit 4, resumable), reports no retained step, and removes neither worktree nor branch
  RIDE_SEED=seed_ride_075 build_world rh075c
  printf 'current_focus:\n  ref_id: foo\ncurrent_focus:\n  ref_id: foo\n' > "$ORIGIN/$STATE_REL"
  pre="$(sha_of "$ORIGIN/$STATE_REL")"
  run_engine apply --pr "$PR" --pid 4242
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-075 "ride-handoff malformed-STATE apply exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-075 "$ENG_OUT" 'STOPPED reconcile_origin_failed'
  unwanted TEST-075 "$ENG_OUT" 'retained'
  [[ -d "$RIDE" ]] || fail TEST-075 'a failed reconcile child still removed the ride worktree'
  has "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE" || fail TEST-075 'a failed reconcile child dropped the worktree from the list'
  git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-075 'a failed reconcile child still deleted the ride branch'
  [[ "$(sha_of "$ORIGIN/$STATE_REL")" == "$pre" ]] || fail TEST-075 'a failed reconcile child changed the origin STATE'
  # the owner repairs the STATE; the re-run resumes and completes
  origin_state_075 "$RH_RUN_STARTED"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-075 "ride-handoff resume after repair exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" reconcile-origin)" == done ]] || fail TEST-075 'resume after repair did not reconcile'
  echo 'PASS: TEST-075 reconcile-origin is done, journalled, a no-op on rerun, retained on an unledgered run, stopped on a failed child'
}

# ---------------------------------------------------------------------------
# spec-merge-cleanup-resolves-framework-friction: TEST-2901..TEST-2924.
# A protected object is kept, a decision is asked as a menu, a failed read is retried a bounded number of times.
LIB="$ROOT/.aai/scripts/lib/merge-outcomes.mjs"
SKILL_BLOCK="$ROOT/.aai/SKILL_MERGE.prompt.md"

# oc <stdout> <js over o>: the OUTCOME lines of a run's stdout, parsed into the array o.
oc() {
  printf '%s\n' "$1" | node -e 'const o=require("fs").readFileSync(0,"utf8").split("\n").filter(l=>l.startsWith("OUTCOME ")).map(l=>JSON.parse(l.slice(8)));const v=eval(process.argv[1]);console.log(typeof v==="string"?v:JSON.stringify(v))' "$2"
}
oc_id() { oc "$1" "(o.find(x=>x.reason===\"$2\")||{}).id||\"\""; }

# oc_check <stdout> <test id>: at least one OUTCOME line, every one with the D8 keys and invariants.
oc_check() {
  local n
  n="$(printf '%s\n' "$1" | node -e '
const o=require("fs").readFileSync(0,"utf8").split("\n").filter(l=>l.startsWith("OUTCOME ")).map(l=>JSON.parse(l.slice(8)));
const keys=["v","id","class","state","reason","subject","detail","options","recommended","question","action"];
for (const x of o) {
  for (const k of keys) if (!(k in x)) throw new Error("missing key "+k);
  if (!/^[a-z_]+@[0-9a-f]{12}$/.test(x.id)) throw new Error("bad id "+x.id);
  if (x.class==="decide" && (x.options.length<2||x.options.length>3||!x.options.some(p=>p.id===x.recommended)||!x.question||x.options.some(p=>!p.effect))) throw new Error("decide "+x.reason);
  if (x.class==="external" && (!x.action||x.options.length)) throw new Error("external "+x.reason);
  if (x.class==="auto" && x.options.length) throw new Error("auto "+x.reason);
}
console.log(o.length)')" || fail "$2" 'an OUTCOME line breaks the D8 keys or invariants'
  [[ "$n" -gt 0 ]] || fail "$2" 'no OUTCOME line was printed'
}

line_no() { printf '%s\n' "$1" | awk -v pat="$2" 'index($0, pat) == 1 { print NR; exit }'; }
count_lines_with() { printf '%s\n' "$1" | awk -v pat="$2" 'index($0, pat) == 1 { n++ } END { print n + 0 }'; }

# draft_rich: the untracked pre-allocation copy of the ride's intake (it names its own draft stem twice).
draft_rich() { printf -- '---\nid: %s\ntype: issue\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Issue foo\n\nSee docs/issues/ISSUE-DRAFT-foo.md and ISSUE-DRAFT-foo here.\n\nBody line.\n' "$ISSUE_ID"; }

# alloc_numbered: the numbered doc the REAL allocate-doc-number.mjs makes from draft_rich, in a scratch clone.
# Sets NUMBERED_ISSUE_FILE; the world's numbered_issue then writes those bytes into the ride.
alloc_numbered() {
  local d="$SCRATCH/alloc"
  [[ -n "$SCRATCH" && "$SCRATCH" = /* ]] || fail SETUP 'alloc root'
  rm -rf "$d"
  run mkdir -p "$d/w/docs/issues"
  run git init -q --bare -b main "$d/bare.git"
  run git init -q -b main "$d/w"
  run git -C "$d/w" remote add origin "$d/bare.git"
  printf 'seed\n' > "$d/w/README.md"
  run git -C "$d/w" add -A
  run git -C "$d/w" commit -qm seed
  run git -C "$d/w" push -q origin main
  run git -C "$d/w" fetch -q origin
  draft_rich > "$d/w/docs/issues/ISSUE-DRAFT-foo.md"
  ( cd "$d/w" && node "$ROOT/.aai/scripts/allocate-doc-number.mjs" --path docs/issues/ISSUE-DRAFT-foo.md --base-ref origin/main >"$d/alloc.out" 2>&1 ) || fail SETUP 'the allocator failed'
  [[ -f "$d/w/docs/issues/ISSUE-0001-foo.md" ]] || fail SETUP "the allocator produced no numbered doc: $(cat "$d/alloc.out")"
  NUMBERED_ISSUE_FILE="$d/w/docs/issues/ISSUE-0001-foo.md"
  # positive control: the allocator changed the number line and the stem, so the two files differ as raw bytes
  if cmp -s <(draft_rich) "$NUMBERED_ISSUE_FILE"; then fail SETUP 'the allocator left the draft bytes unchanged'; fi
  want SETUP "$(cat "$NUMBERED_ISSUE_FILE")" 'ISSUE-0001-foo'
}

# put_draft [extra]: the untracked draft in the origin (draft_rich, plus one body line with extra).
put_draft() {
  draft_rich > "$ORIGIN/$DRAFT_ISSUE"
  if [[ -n "${1:-}" ]]; then printf '%s\n' "$1" >> "$ORIGIN/$DRAFT_ISSUE"; fi
}

# apply_run [args]: apply for the fixture PR with the harness pinned.
apply_run() { AAI_HARNESS=claude run_engine apply --pr "$PR" --pid 4242 "$@"; }

attempts_lines() { lines_of "$ORIGIN/.git/aai-merge-cleanup/pr-$PR/attempts.jsonl" '"exit"'; }

# ---- unit tests -------------------------------------------------------------------------------------------
test_2901_outcome_table_complete() {
  cat > "$SCRATCH/t2901.mjs" <<'JS'
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
const [root] = process.argv.slice(2);
const lib = await import(pathToFileURL(`${root}/.aai/scripts/lib/merge-outcomes.mjs`).href);
const src = fs.readFileSync(`${root}/.aai/scripts/merge-cleanup.mjs`, 'utf8');
const found = new Set(['gh_read_failed', 'gh_read_invalid', 'az_read_failed', 'az_read_invalid', 'repo_mismatch', 'az_arg_unsafe', 'reconcile_refused']);
for (const m of src.matchAll(/\b(?:refuse|stop|halt|retain|raise|keepStep|keepLocalBranch)\((?:ctx, (?:'[a-z-]+', )?)?'([a-z_]+)'/g)) found.add(m[1]);
for (const m of src.matchAll(/(?:refusal|retain): \['([a-z_]+)'/g)) found.add(m[1]);
for (const m of src.matchAll(/held: \{ reason: '([a-z_]+)'/g)) found.add(m[1]);
for (const m of src.matchAll(/reason = '([a-z_]+)'/g)) found.add(m[1]);
const kinds = src.match(/const SUB_KINDS = \[([^\]]*)\]/);
if (!kinds) throw new Error('SUB_KINDS not found');
for (const k of kinds[1].match(/[a-z_]+/g)) found.add(`submodule_${k}`);
if (found.size < 40) throw new Error(`only ${found.size} reason literals scanned`);
for (const must of ['worktree_dirty', 'overlap', 'fetch_failed', 'sync_failed', 'remote_moved', 'divergent_draft', 'head_changed']) if (!found.has(must)) throw new Error(`scan missed ${must}`);
const missing = [...found].filter((r) => !(r in lib.OUTCOME_TABLE));
if (missing.length) throw new Error(`no table entry for: ${missing.join(', ')}`);
let n = 0;
for (const reason of Object.keys(lib.OUTCOME_TABLE)) {
  for (const phase of ['plan', 'step']) for (const retry of [true, false]) {
    const o = lib.classify(reason, { phase, subject: 's', detail: 'd', evidence: ['e'], retry });
    for (const k of ['v', 'id', 'class', 'state', 'reason', 'subject', 'detail', 'options', 'recommended', 'question', 'action']) if (!(k in o)) throw new Error(`${reason}: missing ${k}`);
    if (o.class === 'decide' && !(o.options.length >= 2 && o.options.length <= 3 && o.options.some((x) => x.id === o.recommended) && o.question && o.options.every((x) => x.effect))) throw new Error(`${reason}: decide invariants`);
    if (o.class === 'external' && !(o.action && o.options.length === 0)) throw new Error(`${reason}: external invariants`);
    if (o.class === 'auto' && o.options.length !== 0) throw new Error(`${reason}: auto invariants`);
    const line = lib.outcomeLine(o);
    if (!line.startsWith('OUTCOME ') || JSON.stringify(lib.parseOutcomeLine(line)) !== JSON.stringify(o)) throw new Error(`${reason}: the line does not parse back`);
    n++;
  }
}
let threw = false;
try { lib.classify('no_such_reason'); } catch { threw = true; }
if (!threw) throw new Error('an unknown reason must not classify');
if (lib.compareDraft('---\nid: a\n---\nx\n', '---\nid: b\n---\nx\n', 'T-DRAFT-x', 'T-0001-x') !== false) throw new Error('different ids must be another item');
console.log(`ok ${found.size} reasons, ${n} classifications`);
JS
  local out
  out="$(node "$SCRATCH/t2901.mjs" "$ROOT" 2>&1)" || fail TEST-2901 "$out"
  want TEST-2901 "$out" 'ok '
  echo 'PASS: TEST-2901 the outcome table holds an entry for every reason the engine emits'
}

test_2918_next_attempt() {
  cat > "$SCRATCH/t2918.mjs" <<'JS'
import { pathToFileURL } from 'node:url';
const [root] = process.argv.slice(2);
const { nextAttempt, MAX_AUTO_ATTEMPTS } = await import(pathToFileURL(`${root}/.aai/scripts/lib/merge-outcomes.mjs`).href);
const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`); };
const rec = (fp, retries = ['x@aaaaaaaaaaaa']) => ({ exit: 4, retries, fingerprint: fp });
if (MAX_AUTO_ATTEMPTS !== 3) throw new Error('budget constant');
eq(nextAttempt([], 'f1'), { retry: true }, 'no records');
eq(nextAttempt([rec('f1')], 'f2'), { retry: true }, 'one record, new fingerprint');
eq(nextAttempt([rec('f1'), rec('f2')], 'f3'), { retry: false, why: 'budget' }, 'two trailing retry records');
eq(nextAttempt([rec('f1')], 'f1'), { retry: false, why: 'no_progress' }, 'same fingerprint');
eq(nextAttempt([rec('f1'), rec('f2'), rec('f3', [])], 'f4'), { retry: true }, 'a record without a retry outcome ends the chain');
eq(nextAttempt([rec('f1'), rec('f2'), { ...rec('f3'), reset: true }], 'f4'), { retry: true }, 'a reset record ends the chain');
eq(nextAttempt([rec('f1', []), rec('f1', [])], 'f1'), { retry: true }, 'same fingerprint without a retry chain');
console.log('ok');
JS
  local out
  out="$(node "$SCRATCH/t2918.mjs" "$ROOT" 2>&1)" || fail TEST-2918 "$out"
  want TEST-2918 "$out" 'ok'
  echo 'PASS: TEST-2918 nextAttempt bounds the retry chain and reads progress from the fingerprint'
}

# ---- outcome lines from real runs, the plain summary --------------------------------------------------------
test_2902_outcome_lines_from_real_runs() {
  local before ref_at out_at
  # not_merged: external, exit 3, nothing changed, the REFUSE text first
  build_world oc_not_merged
  write_pr_json OPEN null
  before="$(world_digest)"
  apply_run
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2902 "not_merged exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2902 "$ENG_OUT" 'REFUSE not_merged'
  oc_check "$ENG_OUT" TEST-2902
  [[ "$(oc "$ENG_OUT" 'o[0].class')" == external ]] || fail TEST-2902 'not_merged is not class external'
  [[ "$(line_no "$ENG_OUT" 'REFUSE')" -lt "$(line_no "$ENG_OUT" 'OUTCOME')" ]] || fail TEST-2902 'the OUTCOME line precedes the REFUSE line'
  [[ "$(world_digest)" == "$before" ]] || fail TEST-2902 'not_merged changed the fixture'
  # fetch_failed: an unreachable origin URL is a read failure, class auto, state retry, exit 3
  build_world oc_fetch
  run git -C "$ORIGIN" remote set-url origin "$W/does-not-exist.git"
  before="$(world_digest)"
  apply_run
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2902 "fetch_failed exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2902 "$ENG_OUT" 'REFUSE fetch_failed'
  oc_check "$ENG_OUT" TEST-2902
  [[ "$(oc "$ENG_OUT" 'o[0].class+" "+o[0].state')" == 'auto retry' ]] || fail TEST-2902 "fetch_failed outcome is $(oc "$ENG_OUT" 'o[0].class+" "+o[0].state')"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-2902 'fetch_failed changed the fixture'
  # a dirty worktree: auto, resolved, exit 0
  build_world oc_dirty
  printf 'uncommitted\n' > "$RIDE/stray.txt"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2902 "dirty worktree exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  oc_check "$ENG_OUT" TEST-2902
  [[ "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="worktree_dirty").class+" "+o.find(x=>x.reason==="worktree_dirty").state')" == 'auto resolved' ]] || fail TEST-2902 'worktree_dirty is not auto resolved'
  # a divergent draft: decide, pending, exit 6
  alloc_numbered
  build_world oc_divergent
  put_draft 'one more body line'
  apply_run
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2902 "divergent draft exited $ENG_RC, want 6 (out: $ENG_OUT $ENG_ERR)"
  oc_check "$ENG_OUT" TEST-2902
  [[ "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="divergent_draft").class+" "+o.find(x=>x.reason==="divergent_draft").state')" == 'decide pending' ]] || fail TEST-2902 'divergent_draft is not decide pending'
  NUMBERED_ISSUE_FILE=''
  echo 'PASS: TEST-2902 outcome lines from real runs'
}

test_2921_plain_summary() {
  local out kept decisions merge_line
  # complete
  build_world sum_complete
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2921 "complete exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  merge_line="Merge: PR #$PR is merged as ${MC:0:12}."
  want TEST-2921 "$ENG_OUT" "$merge_line"
  want TEST-2921 "$ENG_OUT" 'Cleanup: complete.'
  [[ "$(count_lines_with "$ENG_OUT" 'Kept: ')" == 0 ]] || fail TEST-2921 'a complete run printed a Kept: line'
  # complete with kept items: a dirty worktree is kept, and so is the local branch it holds
  build_world sum_kept
  printf 'uncommitted\n' > "$RIDE/stray.txt"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2921 "kept run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  kept="$(count_lines_with "$ENG_OUT" 'Kept: ')"
  [[ "$kept" -ge 1 ]] || fail TEST-2921 'a kept worktree printed no Kept: line'
  want TEST-2921 "$ENG_OUT" "Cleanup: complete; kept $kept item(s), nothing needs you."
  apply_run --json
  [[ "$(json_get "$ENG_OUT" 'j.summary.kept')" == "$kept" ]] || fail TEST-2921 "json summary.kept is $(json_get "$ENG_OUT" 'j.summary.kept'), the text run had $kept"
  [[ "$(json_get "$ENG_OUT" 'j.summary.kind')" == complete_kept ]] || fail TEST-2921 'json summary.kind is not complete_kept'
  # a pending decision: everything else is done
  alloc_numbered
  build_world sum_decision
  put_draft 'one more body line'
  apply_run
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2921 "decision run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-2921 "$ENG_OUT" 'Cleanup: waiting for your decision on 1 item(s); everything else is done.'
  decisions="$(count_lines_with "$ENG_OUT" 'Decision: ')"
  [[ "$decisions" == 1 ]] || fail TEST-2921 "decision run printed $decisions Decision: lines, want 1"
  want TEST-2921 "$(printf '%s\n' "$ENG_OUT" | awk 'index($0, "Decision: ") == 1')" '(recommended)'
  apply_run --json
  [[ "$(json_get "$ENG_OUT" 'j.summary.decisions')" == 1 ]] || fail TEST-2921 'json summary.decisions is not 1'
  NUMBERED_ISSUE_FILE=''
  # interrupted with a retry, then interrupted with a decision (the fast-forward fails every time)
  build_world sum_interrupted
  make_shim "$W/shim" --ff-only 'echo "fatal: forced fast-forward failure" >&2; exit 128'
  PATH="$W/shim:$PATH" apply_run
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-2921 "interrupted run exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2921 "$ENG_OUT" 'Cleanup: interrupted at sync-base; retrying.'
  PATH="$W/shim:$PATH" apply_run
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-2921 "second interrupted run exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2921 "$ENG_OUT" 'Cleanup: interrupted at sync-base; waiting for your decision.'
  [[ "$(count_lines_with "$ENG_OUT" 'Decision: ')" == 1 ]] || fail TEST-2921 'the fallback decision printed no Decision: line'
  # refused: not merged
  build_world sum_refused
  write_pr_json OPEN null
  apply_run
  want TEST-2921 "$ENG_OUT" 'Merge: not done.'
  want TEST-2921 "$ENG_OUT" 'Cleanup: not started; nothing was changed.'
  [[ "$(count_lines_with "$ENG_OUT" 'Needs you: ')" == 1 ]] || fail TEST-2921 'the refusal printed no Needs you: line'
  # a preflight refusal: the head moved
  open_world sum_preflight
  write_open_pr OPEN false "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" CLEAN "$ROLLUP_OK"
  pf
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2921 "preflight head_changed exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-2921 "$ENG_OUT" 'Merge: not done.'
  [[ "$(count_lines_with "$ENG_OUT" 'Decision: ')" == 1 ]] || fail TEST-2921 'the head_changed refusal printed no Decision: line'
  echo 'PASS: TEST-2921 the plain summary lines for each terminal kind'
}

# ---- D3: drafts against their numbered counterpart ------------------------------------------------------------
test_2907_superseded_draft_archived() {
  local arch dsha
  alloc_numbered
  build_world draft_super
  put_draft
  dsha="$(sha_of "$ORIGIN/$DRAFT_ISSUE")"
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2907 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-2907 'the superseded draft is still in the main checkout'
  [[ "$(sha_of "$arch/drafts/$DRAFT_ISSUE")" == "$dsha" ]] || fail TEST-2907 'the archived draft differs from the draft bytes'
  want TEST-2907 "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$dsha\",\"reason\":\"superseded_draft\""
  unwanted TEST-2907 "$ENG_OUT" 'leftover_draft'
  unwanted TEST-2907 "$ENG_OUT" 'owner decision'
  want TEST-2907 "$ENG_OUT" 'Cleanup: complete.'
  [[ -f "$ORIGIN/$NUM_ISSUE" ]] || fail TEST-2907 'the numbered doc is missing from the main checkout'
  NUMBERED_ISSUE_FILE=''
  echo 'PASS: TEST-2907 a draft equal to its numbered counterpart is archived and removed with no question'
}

test_2908_divergent_draft_menu() {
  local id before arch
  alloc_numbered
  build_world draft_div
  put_draft 'one more body line'
  before="$(sha_of "$ORIGIN/$DRAFT_ISSUE")"
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  apply_run
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2908 "apply exited $ENG_RC, want 6 (out: $ENG_OUT $ENG_ERR)"
  oc_check "$ENG_OUT" TEST-2908
  [[ "$(oc "$ENG_OUT" 'o.filter(x=>x.reason==="divergent_draft").length')" == 1 ]] || fail TEST-2908 'want one divergent_draft outcome'
  [[ "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="divergent_draft").recommended')" == keep ]] || fail TEST-2908 'keep is not recommended'
  want TEST-2908 "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="divergent_draft").options.map(p=>p.id)')" 'archive_remove'
  [[ "$(sha_of "$ORIGIN/$DRAFT_ISSUE")" == "$before" ]] || fail TEST-2908 'the pending draft changed'
  id="$(oc_id "$ENG_OUT" divergent_draft)"
  apply_run --decide "$id=keep"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2908 "keep exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$ORIGIN/$DRAFT_ISSUE")" == "$before" ]] || fail TEST-2908 'keep changed the draft'
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2908 "a re-run after keep exited $ENG_RC, want 0: nothing is asked again (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-2908 "$ENG_OUT" 'Decision: '
  # the draft changes again: the item is offered under a new id
  printf 'edited after the choice\n' >> "$ORIGIN/$DRAFT_ISSUE"
  apply_run
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2908 "a changed draft exited $ENG_RC, want 6 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(oc_id "$ENG_OUT" divergent_draft)" != "$id" ]] || fail TEST-2908 'a changed draft kept its old id'
  # archive_remove archives, then removes
  before="$(sha_of "$ORIGIN/$DRAFT_ISSUE")"
  apply_run --decide "$(oc_id "$ENG_OUT" divergent_draft)=archive_remove"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2908 "archive_remove exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-2908 'archive_remove left the draft'
  [[ "$(sha_of "$arch/drafts/$DRAFT_ISSUE")" == "$before" ]] || fail TEST-2908 'the archive does not hold the removed draft bytes'
  NUMBERED_ISSUE_FILE=''
  echo 'PASS: TEST-2908 a divergent draft is a menu, keep is remembered, a changed draft is asked again'
}

# seed_dup_counterparts: two numbered docs with one slug in the ride, so a draft of that slug has two counterparts.
seed_dup_counterparts() {
  printf -- '---\nid: dup\ntype: issue\nnumber: 3\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Dup\n' > "$RIDE/docs/issues/ISSUE-0003-dup.md"
  printf -- '---\nid: dup\ntype: issue\nnumber: 4\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Dup\n' > "$RIDE/docs/issues/ISSUE-0004-dup.md"
  run git -C "$RIDE" add docs/issues/ISSUE-0003-dup.md docs/issues/ISSUE-0004-dup.md
}

test_2909_unproven_drafts_untouched() {
  local d1='docs/issues/ISSUE-DRAFT-foo.md' d2='docs/issues/ISSUE-DRAFT-lonely.md' d3='docs/issues/ISSUE-DRAFT-dup.md' s1 s2 s3
  alloc_numbered
  RIDE_SEED=seed_dup_counterparts build_world draft_untouched
  # another item's draft with the slug of the numbered doc (the frontmatter ids differ)
  draft_rich | sed 's/^id: foo$/id: someone-else/' > "$ORIGIN/$d1"
  printf -- '---\nid: lonely\ntype: issue\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Lonely\n' > "$ORIGIN/$d2"
  printf -- '---\nid: dup\ntype: issue\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Dup\n' > "$ORIGIN/$d3"
  s1="$(sha_of "$ORIGIN/$d1")"; s2="$(sha_of "$ORIGIN/$d2")"; s3="$(sha_of "$ORIGIN/$d3")"
  apply_run --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2909 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$ORIGIN/$d1")" == "$s1" && "$(sha_of "$ORIGIN/$d2")" == "$s2" && "$(sha_of "$ORIGIN/$d3")" == "$s3" ]] || fail TEST-2909 'an untouched draft changed'
  want TEST-2909 "$(json_get "$ENG_OUT" 'j.untouched')" "$d1"
  want TEST-2909 "$(json_get "$ENG_OUT" 'j.untouched')" "$d2"
  want TEST-2909 "$(json_get "$ENG_OUT" 'j.untouched')" "$d3"
  [[ "$(json_get "$ENG_OUT" 'j.outcomes.filter(o=>o.state==="pending").length')" == 0 ]] || fail TEST-2909 'an untouched draft produced a pending outcome'
  [[ "$(json_get "$ENG_OUT" 'j.remaining.length')" == 0 ]] || fail TEST-2909 "an untouched draft produced remaining lines: $(json_get "$ENG_OUT" 'j.remaining')"
  [[ "$(json_get "$ENG_OUT" 'j.retained.length')" == 0 ]] || fail TEST-2909 'an untouched draft was retained'
  NUMBERED_ISSUE_FILE=''
  echo 'PASS: TEST-2909 a draft with another id, no counterpart or two counterparts is left alone without a question'
}

# seed_projection_files / touch_projection_files: tracked generated pages and a guide the merge changes.
seed_projection_files() {
  run mkdir -p "$ORIGIN/docs/ai"
  printf '{"v":1}\n' > "$ORIGIN/docs/ai/overview-data.json"
  printf '<html>v1</html>\n' > "$ORIGIN/docs/ai/factory-report.html"
  printf '# Guide\n' > "$ORIGIN/docs/USER_GUIDE.md"
  run git -C "$ORIGIN" add docs/ai/overview-data.json docs/ai/factory-report.html docs/USER_GUIDE.md
}
touch_projection_files() {
  printf '{"v":2}\n' > "$RIDE/docs/ai/overview-data.json"
  printf '<html>v2</html>\n' > "$RIDE/docs/ai/factory-report.html"
  printf '# Guide\n\nDelivered by the ride.\n' > "$RIDE/docs/USER_GUIDE.md"
  run git -C "$RIDE" add docs/ai/overview-data.json docs/ai/factory-report.html docs/USER_GUIDE.md
}

test_2910_generated_projection_taken() {
  local arch
  BASELINE_SEED=seed_projection_files RIDE_SEED=touch_projection_files build_world proj_ok
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  printf '{"v":"local"}\n' > "$ORIGIN/docs/ai/overview-data.json"
  printf '<html>local</html>\n' > "$ORIGIN/docs/ai/factory-report.html"
  run cp "$ORIGIN/docs/ai/overview-data.json" "$W/overview.local"
  run cp "$ORIGIN/docs/ai/factory-report.html" "$W/report.local"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2910 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(cat "$ORIGIN/docs/ai/overview-data.json")" == '{"v":2}' ]] || fail TEST-2910 'the projection was not replaced by the incoming blob'
  [[ "$(cat "$ORIGIN/docs/ai/factory-report.html")" == '<html>v2</html>' ]] || fail TEST-2910 'the report page was not replaced by the incoming blob'
  cmp "$W/overview.local" "$arch/sync/docs/ai/overview-data.json" || fail TEST-2910 'the archived projection differs from the local bytes'
  cmp "$W/report.local" "$arch/sync/docs/ai/factory-report.html" || fail TEST-2910 'the archived report page differs from the local bytes'
  want TEST-2910 "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$(sha_of "$W/overview.local")\",\"reason\":\"pre_sync_local_state\""
  [[ "$(oc "$ENG_OUT" 'o.filter(x=>x.reason==="overlap").length')" == 0 ]] || fail TEST-2910 'a projection produced an overlap outcome'
  # a dirty guide that the merge also changed is still an overlap
  BASELINE_SEED=seed_projection_files RIDE_SEED=touch_projection_files build_world proj_guide
  printf 'my own guide edit\n' >> "$ORIGIN/docs/USER_GUIDE.md"
  decide_arm TEST-2910 overlap docs/USER_GUIDE.md
  BASELINE_SEED='' RIDE_SEED=''
  echo 'PASS: TEST-2910 a generated projection is archived and replaced, a guide edit is a decision'
}

# ---- D4/D5: the roadmap and the identity of a merged doc ---------------------------------------------------------
# seed_rfc_parent: the parent capability's RFC (implementing) in the ride, as PR 485 delivered a child under it.
seed_rfc_parent() {
  run mkdir -p "$RIDE/docs/rfc"
  printf -- '---\nid: parent-cap\ntype: rfc\nnumber: 3\nstatus: implementing\nlinks:\n  pr: []\n  commits: []\n---\n\n# Parent\n' > "$RIDE/docs/rfc/RFC-0003-parent-cap.md"
  run git -C "$RIDE" add docs/rfc/RFC-0003-parent-cap.md
}

# local_pr485: the local roadmap of the main checkout - the HEAD blob plus the parent block (active) and, from the
# REAL roadmap-edit ship-append, the child block (active), with the child's deferred wave line removed.
local_pr485() {
  awk '{ print } /^    status: done$/ && !d { print "  - capability: parent-cap"; print "    status: active"; d = 1 }' "$ORIGIN/$RM" > "$W/roadmap.parent"
  run cp "$W/roadmap.parent" "$ORIGIN/$RM"
  ship_append_foo
  want SETUP "$(cat "$ORIGIN/$RM")" '  - capability: parent-cap'
}

test_2903_pr485_parent_child_roadmap() {
  local arch before_sha
  RIDE_ROADMAP=pr485 ROADMAP_WORLD=1 ISSUE_PR_EMPTY=1 RIDE_SEED=seed_rfc_parent build_world rm485
  local_pr485
  run cp "$ORIGIN/$RM" "$W/roadmap.local"
  before_sha="$(sha_of "$W/roadmap.local")"
  git -C "$BARE" show "$MC:$RM" > "$W/roadmap.incoming" || fail SETUP 'incoming roadmap blob'
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2903 "apply exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  cmp "$W/roadmap.incoming" "$ORIGIN/$RM" || fail TEST-2903 'the roadmap is not the incoming blob'
  cmp "$W/roadmap.local" "$arch/sync/$RM" || fail TEST-2903 'the archived roadmap differs from the local bytes'
  want TEST-2903 "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$before_sha\",\"reason\":\"pre_sync_local_state\""
  unwanted TEST-2903 "$ENG_OUT" 'REFUSE overlap'
  [[ "$(oc "$ENG_OUT" 'o.filter(x=>x.state==="pending").length')" == 0 ]] || fail TEST-2903 'a pending outcome was printed'
  want TEST-2903 "$ENG_OUT" 'Cleanup: complete.'
  # crash arm: killed right after the roadmap was rewritten, a re-run gives the same bytes
  RIDE_ROADMAP=pr485 ROADMAP_WORLD=1 ISSUE_PR_EMPTY=1 RIDE_SEED=seed_rfc_parent build_world rm485_crash
  local_pr485
  git -C "$BARE" show "$MC:$RM" > "$W/roadmap.incoming" || fail SETUP 'incoming roadmap blob'
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=sync-after-rewrite apply_run
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-2903 "crash arm exited $ENG_RC, want 137 (out: $ENG_OUT $ENG_ERR)"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2903 "crash arm re-run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  cmp "$W/roadmap.incoming" "$ORIGIN/$RM" || fail TEST-2903 'crash arm: the roadmap is not the incoming blob'
  RIDE_SEED=''
  echo 'PASS: TEST-2903 the PR 485 parent and child roadmap blocks are archived and the incoming roadmap taken'
}

test_2904_unrepresented_roadmap_decides() {
  local id
  world_rm() { RIDE_ROADMAP=pr485paused ROADMAP_WORLD=1 ISSUE_PR_EMPTY=1 RIDE_SEED=seed_rfc_parent build_world "$1"; local_pr485; seed_state; }
  world_rm rm_decide
  run cp "$ORIGIN/$RM" "$W/roadmap.local"
  local head_before; head_before="$(git -C "$ORIGIN" rev-parse HEAD)"
  apply_run
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2904 "apply exited $ENG_RC, want 6 (out: $ENG_OUT $ENG_ERR)"
  oc_check "$ENG_OUT" TEST-2904
  [[ "$(oc "$ENG_OUT" 'o.filter(x=>x.reason==="overlap"&&x.class==="decide"&&x.recommended==="keep_local").length')" == 1 ]] || fail TEST-2904 'want one overlap decide outcome with keep_local recommended'
  want TEST-2904 "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="overlap").detail')" 'parent-cap'
  cmp "$W/roadmap.local" "$ORIGIN/$RM" || fail TEST-2904 'the pending roadmap changed'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$head_before" ]] || fail TEST-2904 'main HEAD moved'
  [[ ! -e "$RIDE" ]] || fail TEST-2904 'the worktree without ledger tails was not removed'
  [[ "$(step_status_text "$ENG_OUT" reconcile-origin)" == retained ]] || fail TEST-2904 'reconcile-origin is not retained'
  want TEST-2904 "$ENG_OUT" 'sync_not_done'
  id="$(oc_id "$ENG_OUT" overlap)"
  apply_run --decide "$id=keep_local"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2904 "keep_local exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status_text "$ENG_OUT" sync-base)" == retained ]] || fail TEST-2904 'keep_local did not retain sync-base'
  cmp "$W/roadmap.local" "$ORIGIN/$RM" || fail TEST-2904 'keep_local changed the roadmap'
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2904 "the second re-run asked again: exit $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-2904 "$ENG_OUT" 'Decision: '
  # a fresh, identical world answered with take_incoming: archive the local roadmap, then sync
  world_rm rm_take
  git -C "$BARE" show "$MC:$RM" > "$W/roadmap.incoming" || fail SETUP 'incoming roadmap blob'
  run cp "$ORIGIN/$RM" "$W/roadmap.local"
  apply_run --decide "$id=take_incoming"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2904 "take_incoming exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  cmp "$W/roadmap.incoming" "$ORIGIN/$RM" || fail TEST-2904 'take_incoming did not take the incoming roadmap'
  cmp "$W/roadmap.local" "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/$RM" || fail TEST-2904 'take_incoming did not archive the local roadmap'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-2904 'take_incoming did not sync main'
  RIDE_SEED=''
  echo 'PASS: TEST-2904 an unrepresented roadmap change is a decision with both answers working'
}

# step_status_text <stdout>: the status a text report prints for a step ("  <id>: <status>").
step_status_text() { printf '%s\n' "$1" | awk -v id="  $2:" 'index($0, id) == 1 { sub(/^ *[a-z-]+: /, ""); sub(/ .*/, ""); print; exit }'; }

test_2905_absent_links_pr_proven_by_merge_commit() {
  local arm blob_sha
  for arm in ISSUE_NO_PR ISSUE_PR_EMPTY; do
    export "$arm=1"
    RIDE_SEED=seed_ride_075 ROADMAP_WORLD=1 build_world "ident_$arm"
    ship_append_foo
    origin_state_075 "$RH_RUN_STARTED"
    git -C "$BARE" show "$MC:$NUM_ISSUE" > "$W/issue.blob" || fail SETUP 'merged intake blob'
    blob_sha="$(sha_of "$W/issue.blob")"
    git -C "$BARE" show "$MC:$RM" > "$W/roadmap.incoming" || fail SETUP 'incoming roadmap blob'
    if [[ "$arm" == ISSUE_NO_PR ]]; then unwanted SETUP "$(cat "$W/issue.blob")" 'pr:'; else want SETUP "$(cat "$W/issue.blob")" 'pr: []'; fi
    apply_run --json
    [[ "$ENG_RC" -eq 0 ]] || fail TEST-2905 "$arm: apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
    cmp "$W/roadmap.incoming" "$ORIGIN/$RM" || fail TEST-2905 "$arm: the ride roadmap entry was not taken from incoming"
    [[ "$(json_get "$ENG_OUT" 'j.outcomes.filter(o=>o.state==="pending").length')" == 0 ]] || fail TEST-2905 "$arm: an outcome is pending"
    [[ "$(step_status "$ENG_OUT" reconcile-origin)" == done ]] || fail TEST-2905 "$arm: reconcile-origin reported $(step_status "$ENG_OUT" reconcile-origin)"
    unwanted TEST-2905 "$(cat "$ORIGIN/$STATE_REL")" 'ref_id: foo'
    [[ "$(sha_of "$ORIGIN/$NUM_ISSUE")" == "$blob_sha" ]] || fail TEST-2905 "$arm: the merged intake file changed"
    [[ "$(git -C "$ORIGIN" show "HEAD:$NUM_ISSUE" | sha_stdin)" == "$blob_sha" ]] || fail TEST-2905 "$arm: the merged intake blob changed"
    unset "$arm"
  done
  RIDE_SEED=''
  echo 'PASS: TEST-2905 an absent or empty links.pr is proven by the merge commit and feeds the roadmap and the reconcile'
}

# seed_qux_999 / seed_quux_base / seed_quux_ride: docs the merge turns to done whose identity no proof ties to the PR.
seed_qux_999() {
  printf -- '---\nid: qux\ntype: issue\nnumber: 10\nstatus: done\nlinks:\n  pr:\n    - 999\n  commits: []\n---\n\n# Qux\n' > "$RIDE/docs/issues/ISSUE-0010-qux.md"
  run git -C "$RIDE" add docs/issues/ISSUE-0010-qux.md
}
seed_quux_base() {
  printf -- '---\nid: qux\ntype: issue\nnumber: 10\nstatus: done\nlinks:\n  pr: []\n  commits: []\n---\n\n# Qux\n' > "$ORIGIN/docs/issues/ISSUE-0010-qux.md"
  run git -C "$ORIGIN" add docs/issues/ISSUE-0010-qux.md
}
seed_quux_ride() {
  printf 'edited by the ride\n' >> "$RIDE/docs/issues/ISSUE-0010-qux.md"
  run git -C "$RIDE" add docs/issues/ISSUE-0010-qux.md
}
# local_qux: the main checkout's roadmap carries the qux pair block as active.
local_qux() {
  awk '{ print } /^    status: done$/ && !d { print "  - capability: qux"; print "    status: active"; d = 1 }' "$ORIGIN/$RM" > "$W/roadmap.qux"
  run cp "$W/roadmap.qux" "$ORIGIN/$RM"
}

test_2906_conflicting_or_old_identity_not_proven() {
  local pre qux_blob
  # (a) links.pr names only another PR; (b) the doc was already done before the merge, links.pr empty
  RIDE_ROADMAP=qux ROADMAP_WORLD=1 RIDE_SEED=seed_qux_999 build_world ident_999
  local_qux
  qux_blob="$(git -C "$BARE" show "$MC:docs/issues/ISSUE-0010-qux.md" | sha_stdin)"
  decide_arm TEST-2906 overlap 'unproven qux'
  [[ "$(git -C "$BARE" show "$MC:docs/issues/ISSUE-0010-qux.md" | sha_stdin)" == "$qux_blob" ]] || fail TEST-2906 'the merged doc blob changed'
  RIDE_ROADMAP=qux ROADMAP_WORLD=1 BASELINE_SEED=seed_quux_base RIDE_SEED=seed_quux_ride build_world ident_old
  local_qux
  decide_arm TEST-2906 overlap 'unproven qux'
  # (c) no roadmap change: the STATE trace of the unproven ref stays, the reconcile does not run for it
  RIDE_ROADMAP=qux ROADMAP_WORLD=1 RIDE_SEED=seed_qux_999 build_world ident_state
  printf 'project_status: active\ncurrent_focus:\n  type: intake_change\n  ref_id: qux\n  primary_path: docs/issues/ISSUE-DRAFT-qux.md\n  spec_path: null\nactive_work_items:\n  - ref_id: qux\n    status: in_progress\n    phase: planning\nupdated_at_utc: 2026-10-10T09:00:00Z\n' > "$ORIGIN/$STATE_REL"
  pre="$(sha_of "$ORIGIN/$STATE_REL")"
  run cp "$ORIGIN/$RM" "$W/roadmap.keep"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2906 "state arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$ORIGIN/$STATE_REL")" == "$pre" ]] || fail TEST-2906 'the reconcile cleared the trace of an unproven ref'
  [[ "$(sha_of "$ORIGIN/docs/issues/ISSUE-0010-qux.md")" == "$(git -C "$BARE" show "$MC:docs/issues/ISSUE-0010-qux.md" | sha_stdin)" ]] || fail TEST-2906 'the merged doc bytes changed'
  BASELINE_SEED='' RIDE_SEED=''
  echo 'PASS: TEST-2906 another PR or an old done status does not prove the identity of a merged doc'
}

# ---- D8: the decision channel and the router that follows the skill -------------------------------------------
test_2911_decide_channel() {
  local id before choices stale
  alloc_numbered
  build_world dch
  put_draft 'one more body line'
  choices="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/choices.jsonl"
  apply_run
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2911 "first run exited $ENG_RC, want 6 (out: $ENG_OUT $ENG_ERR)"
  id="$(oc_id "$ENG_OUT" divergent_draft)"
  [[ "$id" =~ ^divergent_draft@[0-9a-f]{12}$ ]] || fail TEST-2911 "unexpected id: $id"
  # a stale digest prints IGNORED, and the item is offered again under its real id
  stale='divergent_draft@000000000000'
  apply_run --decide "$stale=keep"
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2911 "stale pair exited $ENG_RC, want 6 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2911 "$ENG_OUT" "IGNORED $stale=keep no_longer_applies"
  [[ "$(oc_id "$ENG_OUT" divergent_draft)" == "$id" ]] || fail TEST-2911 'the item was not offered again under its id'
  # an option the item does not offer
  apply_run --decide "$id=take_incoming"
  want TEST-2911 "$ENG_OUT" "IGNORED $id=take_incoming option_not_offered"
  [[ "$ENG_RC" -eq 6 ]] || fail TEST-2911 "unoffered option exited $ENG_RC, want 6"
  [[ ! -e "$choices" ]] || fail TEST-2911 'an ignored pair was recorded'
  # a valid pair applies once and is recorded once, however often it is repeated
  before="$(sha_of "$ORIGIN/$DRAFT_ISSUE")"
  apply_run --decide "$id=archive_remove"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2911 "archive_remove exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-2911 'archive_remove left the draft'
  apply_run --decide "$id=archive_remove"
  want TEST-2911 "$ENG_OUT" "IGNORED $id=archive_remove no_longer_applies"
  [[ "$(lines_of "$choices" "\"id\":\"$id\"")" == 1 ]] || fail TEST-2911 "choices.jsonl holds $(lines_of "$choices" "\"id\":\"$id\"") lines for the id, want 1"
  # malformed pairs and plan/preflight take no --decide: usage, exit 2
  for bad in 'nonsense' "$id" "$id=" "=keep" 'Divergent_Draft@000000000000=keep' "$id=keep;rm"; do
    apply_run --decide "$bad"
    [[ "$ENG_RC" -eq 2 ]] || fail TEST-2911 "--decide '$bad' exited $ENG_RC, want 2"
  done
  run_engine plan --pr "$PR" --decide "$id=keep"
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-2911 "plan --decide exited $ENG_RC, want 2"
  run_engine preflight --pr "$PR" --expect-head "$HEAD_OID" --directed-by human --direction x --decide "$id=keep"
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-2911 "preflight --decide exited $ENG_RC, want 2"
  NUMBERED_ISSUE_FILE=''
  echo 'PASS: TEST-2911 the decide channel applies a current pair once and ignores a stale or unoffered one'
}

# route_block <world dir> <shim dir>: a test double of the agent that follows SKILL_MERGE step 2 over the REAL bash block.
# retry runs the block again, a decide menu is answered with the recommended option through AAI_DECIDE, external stops.
route_block() {
  local shim="$1" runs=0 decide='' out rc pairs
  local -a envs
  block_of AAI_MERGE_BEGIN AAI_MERGE_END "$PROMPT" > "$W/merge.block.sh"
  [[ -s "$W/merge.block.sh" ]] || fail TEST-2912 'AAI_MERGE bash block is empty or missing'
  ROUTER_RUNS=0
  while [[ "$runs" -lt 6 ]]; do
    runs=$((runs + 1))
    envs=("AAI_PR=$PR" 'AAI_HARNESS=claude' "GH_STUB_DIR=$GHD" "PATH=$shim:$GHD/bin:$PATH")
    if [[ -n "$decide" ]]; then envs+=("AAI_DECIDE=$decide"); fi
    rc=0
    ( cd "$ORIGIN" && env "${envs[@]}" bash "$W/merge.block.sh" >"$W/block.out" 2>"$W/block.err" ) || rc=$?
    out="$(cat "$W/block.out")"
    ROUTER_RUNS="$runs"; ROUTER_OUT="$out"; ROUTER_RC="$rc"
    if [[ "$rc" -eq 0 ]]; then return 0; fi
    decide=''
    if [[ "$(oc "$out" 'o.some(x=>x.state==="retry")')" == true ]]; then continue; fi
    if [[ "$(oc "$out" 'o.some(x=>x.class==="external")')" == true ]]; then return 0; fi
    pairs="$(oc "$out" 'o.filter(x=>x.class==="decide"&&x.state==="pending").map(x=>x.id+"="+x.recommended).join(",")')"
    [[ -n "$pairs" ]] || fail TEST-2912 "exit $rc with nothing to route: $out $(cat "$W/block.err")"
    decide="$pairs"
  done
}

test_2912_router_resumes_in_one_interaction() {
  alloc_numbered
  DOWNSTREAM=1 build_world router
  put_draft 'one more body line'
  # one forced sync_failed (the first fast-forward fails), one divergent draft
  make_shim "$W/shim" --ff-only 'if [ ! -e "'"$W"'/ff-once" ]; then : > "'"$W"'/ff-once"; echo "fatal: forced fast-forward failure" >&2; exit 128; fi'
  route_block "$W/shim"
  [[ "$ROUTER_RC" -eq 0 ]] || fail TEST-2912 "the router ended with exit $ROUTER_RC after $ROUTER_RUNS runs: $ROUTER_OUT"
  [[ "$ROUTER_RUNS" -le 4 ]] || fail TEST-2912 "the router needed $ROUTER_RUNS block runs, want at most 4"
  [[ "$ROUTER_RUNS" -ge 3 ]] || fail TEST-2912 "the router finished in $ROUTER_RUNS runs: the retry and the menu were not both exercised"
  [[ -e "$W/ff-once" ]] || fail TEST-2912 'the forced failure never ran (positive control)'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-2912 'main did not reach the merge commit'
  [[ -f "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-2912 'the recommended keep removed the draft'
  [[ ! -e "$RIDE" ]] || fail TEST-2912 'the worktree was not removed'
  [[ "$(lines_of "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/choices.jsonl" '"option":"keep"')" == 1 ]] || fail TEST-2912 'the recommended answer was not recorded once'
  NUMBERED_ISSUE_FILE=''
  echo 'PASS: TEST-2912 a router over the real block finishes one retry and one decision without other input'
}

# ---- D6: protected objects are kept, the other steps finish -------------------------------------------------------
wt_sig() {
  {
    git -C "$RIDE" rev-parse HEAD
    git -C "$RIDE" status --porcelain=v1 -uall
    git -C "$ORIGIN" rev-parse "refs/heads/$BRANCH"
    find "$RIDE" -path '*/.git' -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(sha_of "$f")"; done
  } | sha_stdin
}

test_2914_worktree_protections_kept() {
  local arm sig pid rsn
  for arm in dirty ahead locked submodule; do
    pid=''
    if [[ "$arm" == submodule ]]; then build_sub_world "prot_$arm"; else build_world "prot_$arm"; fi
    case "$arm" in
      dirty) printf 'uncommitted\n' > "$RIDE/stray.txt"
             [[ -n "$(git -C "$RIDE" status --porcelain)" ]] || fail SETUP 'dirty arm: the worktree is clean (positive control)' ;;
      ahead) printf 'after the merge\n' > "$RIDE/after.txt"
             run git -C "$RIDE" add after.txt
             run git -C "$RIDE" commit -qm 'work after the merge'
             [[ "$(git -C "$RIDE" rev-parse HEAD)" != "$HEAD_OID" ]] || fail SETUP 'ahead arm: HEAD did not move' ;;
      locked) sleep 600 & pid=$!
              HELPER_PIDS+=("$pid")
              ( cd "$RIDE" && node "$ROOT/.aai/scripts/lib/session-lock.mjs" acquire --pid "$pid" >/dev/null ) || fail SETUP 'lock acquire'
              kill -0 "$pid" || fail SETUP 'locked arm: the lock holder is not alive (positive control)' ;;
      submodule) printf 'edited\n' >> "$RIDE/sub/sub.txt"
                 [[ -n "$(git -C "$RIDE/sub" status --porcelain)" ]] || fail SETUP 'submodule arm: sub is clean (positive control)' ;;
    esac
    sig="$(wt_sig)"
    case "$arm" in
      dirty) rsn=worktree_dirty ;;
      ahead) rsn=tip_mismatch ;;
      locked) rsn=session_locked ;;
      submodule) rsn=submodule_dirty ;;
    esac
    keep_arm TEST-2914 "$rsn" "" remove-worktree
    [[ "$(wt_sig)" == "$sig" ]] || fail TEST-2914 "arm $arm: the worktree files, status, HEAD or branch ref changed"
    want TEST-2914 "$ENG_OUT" '  sync-base: done'
    want TEST-2914 "$ENG_OUT" '  delete-branch: retained (kept_with_worktree'
    if bare_has "$BRANCH"; then fail TEST-2914 "arm $arm: the origin branch was not deleted by lease"; fi
    [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-2914 "arm $arm: main did not reach the merge commit"
    if [[ -n "$pid" ]]; then stop_helper "$pid"; fi
  done
  echo 'PASS: TEST-2914 a dirty, ahead, locked or submodule-dirty worktree is kept while the other steps finish'
}

test_2915_sync_protections_kept() {
  local arm tails ev_before head_before branch_before rsn
  for arm in diverged elsewhere rewritten; do
    for tails in none tails; do
      LEDGER_WORLD=1 build_world "sync_${arm}_$tails"
      seed_state
      case "$arm" in
        diverged) printf 'local commit\n' > "$ORIGIN/local-commit.txt"
                  run git -C "$ORIGIN" add local-commit.txt
                  run git -C "$ORIGIN" commit -qm 'local commit not on origin'
                  [[ "$(git -C "$ORIGIN" rev-list --count 'refs/remotes/origin/main..HEAD')" -gt 0 ]] || fail SETUP 'diverged arm: no local commit (positive control)' ;;
        elsewhere) run git -C "$ORIGIN" checkout -q -b elsewhere ;;
        rewritten) printf '{"v":1,"ts":"2026-10-09T00:00:00Z","actor":"fixture","event":"seed","ref":"REWRITTEN","payload":{}}\n' > "$ORIGIN/$EV"
                   if git -C "$ORIGIN" show "HEAD:$EV" | cmp -s - "$ORIGIN/$EV"; then fail SETUP 'rewritten arm: the ledger is unchanged (positive control)'; fi ;;
      esac
      if [[ "$tails" == tails ]]; then seed_ledger_tails; fi
      ev_before="$(sha_of "$ORIGIN/$EV")"; head_before="$(git -C "$ORIGIN" rev-parse HEAD)"; branch_before="$(git -C "$ORIGIN" symbolic-ref -q --short HEAD)"
      case "$arm" in
        diverged) rsn=base_diverged ;;
        elsewhere) rsn=origin_not_on_base ;;
        rewritten) rsn=ledger_rewritten ;;
      esac
      keep_arm TEST-2915 "$rsn" "" sync-base
      [[ "$(sha_of "$ORIGIN/$EV")" == "$ev_before" ]] || fail TEST-2915 "arm $arm/$tails: the main ledger bytes changed"
      [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$head_before" ]] || fail TEST-2915 "arm $arm/$tails: main HEAD moved"
      [[ "$(git -C "$ORIGIN" symbolic-ref -q --short HEAD)" == "$branch_before" ]] || fail TEST-2915 "arm $arm/$tails: the checked-out branch changed"
      want TEST-2915 "$ENG_OUT" '  reconcile-origin: retained'
      want TEST-2915 "$ENG_OUT" 'sync_not_done'
      if [[ "$tails" == none ]]; then
        [[ ! -e "$RIDE" ]] || fail TEST-2915 "arm $arm/none: the worktree without ledger tails was not removed"
      else
        [[ -d "$RIDE" ]] || fail TEST-2915 "arm $arm/tails: the worktree with ledger tails was removed"
        want TEST-2915 "$ENG_OUT" 'ledger_tails_wait_for_sync'
        want TEST-2915 "$ENG_OUT" '  remove-worktree: retained'
        tail_in_worktree TEST-2915 docs/ai/EVENTS.jsonl "$W/tail-ev"
        tail_in_worktree TEST-2915 "$TR" "$W/tail-rt"
      fi
    done
  done
  echo 'PASS: TEST-2915 a diverged, moved or rewritten main is kept, the worktree follows the ledger tails'
}
tail_in_worktree() {
  local tid="$1" ledger="$2" tailf="$3" n
  n="$(wc -c < "$tailf" | tr -d ' ')"
  tail -c "$n" "$RIDE/$ledger" > "$W/got-tail" || fail "$tid" "cannot read the end of the worktree $ledger"
  cmp "$tailf" "$W/got-tail" || fail "$tid" "the worktree $ledger lost its appended bytes"
}

test_2916_preflight_gates_hold() {
  local before other='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  open_world gates
  # the PR head moved: head_changed is a decide outcome, no merge command is printed
  write_open_pr OPEN false "$other" CLEAN "$ROLLUP_OK"
  before="$(world_digest)"
  pf
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2916 "head_changed exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2916 "$ENG_OUT" 'REFUSE head_changed'
  oc_check "$ENG_OUT" TEST-2916
  [[ "$(oc "$ENG_OUT" 'o[0].class+" "+o[0].recommended')" == 'decide direct_new_head' ]] || fail TEST-2916 'head_changed is not a decide outcome recommending direct_new_head'
  want TEST-2916 "$(oc "$ENG_OUT" 'o[0].options.map(p=>p.id)')" 'stop'
  unwanted TEST-2916 "$ENG_OUT" 'gh pr merge'
  [[ "$(world_digest)" == "$before" ]] || fail TEST-2916 'head_changed changed the fixture'
  assert_no_merge_call TEST-2916
  # a contradictory sweep record: external
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  printf '%s\n' "${SWEEP_OK/\"threads_unresolved\":0/\"threads_unresolved\":3}" >> "$RIDE/docs/ai/EVENTS.jsonl"
  before="$(world_digest)"
  pf
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2916 "sweep_missing exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  oc_check "$ENG_OUT" TEST-2916
  [[ "$(oc "$ENG_OUT" 'o[0].reason+" "+o[0].class')" == 'sweep_missing external' ]] || fail TEST-2916 'sweep_missing is not external'
  [[ "$(world_digest)" == "$before" ]] || fail TEST-2916 'sweep_missing changed the fixture'
  assert_no_merge_call TEST-2916
  # unresolved review threads: external
  open_world gates_threads
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer"},"body":"Must fix this bug","path":"test.js","line":42}]}}]}}}}}\n' > "$GHD/review-threads.json"
  before="$(world_digest)"
  pf
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2916 "review_unresolved exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(oc "$ENG_OUT" 'o[0].reason+" "+o[0].class')" == 'review_unresolved external' ]] || fail TEST-2916 'review_unresolved is not external'
  want TEST-2916 "$ENG_OUT" 'Needs you: '
  [[ "$(world_digest)" == "$before" ]] || fail TEST-2916 'review_unresolved changed the fixture'
  assert_no_merge_call TEST-2916
  echo 'PASS: TEST-2916 the preflight gates still refuse and call no merge'
}

test_2917_archive_verification_and_no_new_primitive() {
  local dsha out
  alloc_numbered
  build_world corrupt
  put_draft
  dsha="$(sha_of "$ORIGIN/$DRAFT_ISSUE")"
  AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CORRUPT_ARCHIVE="$DRAFT_ISSUE" apply_run
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-2917 "a corrupt archive copy exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2917 "$ENG_OUT" "STOPPED archive_failed $DRAFT_ISSUE"
  [[ "$(sha_of "$ORIGIN/$DRAFT_ISSUE")" == "$dsha" ]] || fail TEST-2917 'the draft changed although its archive copy did not read back equal'
  oc_check "$ENG_OUT" TEST-2917
  # without the seam the same world converges
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2917 "the re-run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-2917 'the re-run left the draft'
  # the engine and the library hold no new destructive git call
  cat > "$SCRATCH/t2917.mjs" <<'JS'
import fs from 'node:fs';
const [root] = process.argv.slice(2);
const files = ['.aai/scripts/merge-cleanup.mjs', '.aai/scripts/lib/merge-outcomes.mjs'];
const src = files.map((f) => fs.readFileSync(`${root}/${f}`, 'utf8')).join('\n');
const count = (re) => (src.match(re) ?? []).length;
for (const [name, re] of [['worktree prune', /'worktree', 'prune'/g], ['branch -D', /'-D'/g], ['push --delete', /'--delete'/g], ['reset, stash, clean or checkout', /\[\s*'(?:reset|stash|clean|checkout)'/g], ['a leading prune', /\[\s*'prune'/g]]) {
  if (count(re) !== 0) throw new Error(`a call with ${name} occurs ${count(re)} time(s)`);
}
if (count(/'--force'/g) !== 1) throw new Error(`worktree remove --force occurs ${count(/'--force'/g)} time(s), want 1`);
console.log('ok');
JS
  out="$(node "$SCRATCH/t2917.mjs" "$ROOT" 2>&1)" || fail TEST-2917 "$out"
  NUMBERED_ISSUE_FILE=''
  echo 'PASS: TEST-2917 an archive copy that does not read back stops the step, and no new destructive git call exists'
}

# ---- D7: a bounded retry chain, and a crash at each new mutation point -------------------------------------------
test_2919_retry_chain_terminates() {
  local id before
  build_world chain
  printf 'local edit\n' >> "$ORIGIN/UNRELATED.txt"
  make_shim "$W/shim" --ff-only 'echo "fatal: forced fast-forward failure" >&2; exit 128'
  # run 1: the fast-forward fails, state retry
  PATH="$W/shim:$PATH" apply_run
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-2919 "run 1 exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2919 "$ENG_OUT" 'STOPPED sync_failed'
  want TEST-2919 "$ENG_OUT" 'forced fast-forward failure'   # positive control: the seam failed the fast-forward
  [[ "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="sync_failed").class+" "+o.find(x=>x.reason==="sync_failed").state')" == 'auto retry' ]] || fail TEST-2919 'run 1 is not auto retry'
  # run 2: no progress, the fallback class decide (retry, skip_step recommended)
  PATH="$W/shim:$PATH" apply_run
  [[ "$ENG_RC" -eq 4 ]] || fail TEST-2919 "run 2 exited $ENG_RC, want 4 (out: $ENG_OUT $ENG_ERR)"
  oc_check "$ENG_OUT" TEST-2919
  [[ "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="sync_failed").class')" == decide ]] || fail TEST-2919 'run 2 did not fall back to decide'
  [[ "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="sync_failed").recommended')" == skip_step ]] || fail TEST-2919 'skip_step is not recommended'
  want TEST-2919 "$(oc "$ENG_OUT" 'o.find(x=>x.reason==="sync_failed").options.map(p=>p.id)')" 'retry'
  want TEST-2919 "$ENG_OUT" 'Cleanup: interrupted at sync-base; waiting for your decision.'
  id="$(oc_id "$ENG_OUT" sync_failed)"
  # run 3: skip_step retains the step and finishes the rest
  PATH="$W/shim:$PATH" apply_run --decide "$id=skip_step"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2919 "skip_step exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2919 "$ENG_OUT" '  sync-base: retained'
  [[ ! -e "$RIDE" ]] || fail TEST-2919 'skip_step did not let the worktree steps finish'
  [[ "$(git -C "$ORIGIN" rev-parse HEAD)" != "$MC" ]] || fail TEST-2919 'main moved although the step was skipped'
  [[ "$(attempts_lines)" == 3 ]] || fail TEST-2919 "attempts.jsonl holds $(attempts_lines) lines, want one per run (3)"
  # an unreachable origin: retry, then external with a Needs you: line
  build_world chain_fetch
  run git -C "$ORIGIN" remote set-url origin "$W/does-not-exist.git"
  before="$(world_digest)"
  apply_run
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2919 "fetch run 1 exited $ENG_RC, want 3"
  [[ "$(oc "$ENG_OUT" 'o[0].class+" "+o[0].state')" == 'auto retry' ]] || fail TEST-2919 'fetch run 1 is not auto retry'
  apply_run
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-2919 "fetch run 2 exited $ENG_RC, want 3"
  [[ "$(oc "$ENG_OUT" 'o[0].class')" == external ]] || fail TEST-2919 'fetch run 2 is not external'
  want TEST-2919 "$ENG_OUT" 'Needs you: '
  [[ "$(world_digest)" == "$before" ]] || fail TEST-2919 'the fetch runs changed the fixture'
  [[ "$(attempts_lines)" == 2 ]] || fail TEST-2919 "fetch attempts hold $(attempts_lines) lines, want 2"
  echo 'PASS: TEST-2919 the retry chain ends in a decision or an external step'
}

crash_run() { AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT="$1" apply_run "${@:2}"; }

norm_lines() { sed 's/,"timestamp":"[^"]*"//' "$1" 2>/dev/null | LC_ALL=C sort | uniq -d | wc -l | tr -d ' ' || true; }

test_2920_interrupted_recovery_converges() {
  local twin_sig id rc
  # draft-after-archive: killed after the draft was archived and before it was removed
  alloc_numbered
  build_world rec_twin_draft
  put_draft
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2920 "draft twin exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  twin_sig="$(tree_sig)"
  build_world rec_draft
  put_draft
  crash_run draft-after-archive
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-2920 "draft crash exited $ENG_RC, want 137"
  [[ -e "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-2920 'draft crash: the draft was removed before the crash point (positive control)'
  [[ -f "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/drafts/$DRAFT_ISSUE" ]] || fail TEST-2920 'draft crash: no archive copy at the crash point (positive control)'
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2920 "draft re-run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(norm_lines "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/manifest.jsonl")" == 0 ]] || fail TEST-2920 'draft: the manifest holds a duplicate line'
  [[ "$(journal_dups)" == 0 ]] || fail TEST-2920 'draft: the journal holds a duplicate line'
  [[ "$(tree_sig)" == "$twin_sig" ]] || fail TEST-2920 'draft: the recovered tree differs from the uninterrupted twin'
  NUMBERED_ISSUE_FILE=''

  # choice-after-record: killed after the choice was recorded and before it was applied
  alloc_numbered
  build_world rec_choice_probe
  put_draft 'one more body line'
  apply_run
  id="$(oc_id "$ENG_OUT" divergent_draft)"
  build_world rec_choice_twin
  put_draft 'one more body line'
  apply_run --decide "$id=archive_remove"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2920 "choice twin exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  twin_sig="$(tree_sig)"
  build_world rec_choice
  put_draft 'one more body line'
  crash_run choice-after-record --decide "$id=archive_remove"
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-2920 "choice crash exited $ENG_RC, want 137"
  [[ "$(lines_of "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/choices.jsonl" "\"id\":\"$id\"")" == 1 ]] || fail TEST-2920 'choice crash: the choice was not recorded at the crash point (positive control)'
  [[ -e "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-2920 'choice crash: the draft was removed before the choice was applied'
  apply_run --decide "$id=archive_remove"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2920 "choice re-run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(lines_of "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/choices.jsonl" "\"id\":\"$id\"")" == 1 ]] || fail TEST-2920 'choice: the choices ledger holds a duplicate line'
  [[ "$(norm_lines "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/manifest.jsonl")" == 0 ]] || fail TEST-2920 'choice: the manifest holds a duplicate line'
  [[ "$(tree_sig)" == "$twin_sig" ]] || fail TEST-2920 'choice: the recovered tree differs from the uninterrupted twin'
  NUMBERED_ISSUE_FILE=''

  # take-incoming-after-archive: killed after the local README was archived and before the sync
  build_world rec_take_probe
  printf 'dirty and also changed by the PR\n' >> "$ORIGIN/README.md"
  apply_run
  id="$(oc_id "$ENG_OUT" overlap)"
  build_world rec_take_twin
  printf 'dirty and also changed by the PR\n' >> "$ORIGIN/README.md"
  apply_run --decide "$id=take_incoming"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2920 "take twin exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  twin_sig="$(tree_sig)"
  build_world rec_take
  printf 'dirty and also changed by the PR\n' >> "$ORIGIN/README.md"
  crash_run take-incoming-after-archive --decide "$id=take_incoming"
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-2920 "take crash exited $ENG_RC, want 137"
  [[ -f "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/README.md" ]] || fail TEST-2920 'take crash: no archive copy at the crash point (positive control)'
  apply_run --decide "$id=take_incoming"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2920 "take re-run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(norm_lines "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/manifest.jsonl")" == 0 ]] || fail TEST-2920 'take: the manifest holds a duplicate line'
  [[ "$(journal_dups)" == 0 ]] || fail TEST-2920 'take: the journal holds a duplicate line'
  [[ "$(tree_sig)" == "$twin_sig" ]] || fail TEST-2920 'take: the recovered tree differs from the uninterrupted twin'

  # a sync pending journal that no longer matches: sync-base is kept, the journal and the archive stay, the rest finishes
  build_rich_world rec_pending
  crash_run sync-after-rewrite
  [[ "$ENG_RC" -eq 137 ]] || fail TEST-2920 "pending crash exited $ENG_RC, want 137"
  printf 'someone rewrote the ledger\n' > "$ORIGIN/$EV"
  apply_run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-2920 "pending_diverged exited $ENG_RC, want 0 (out: $ENG_OUT $ENG_ERR)"
  want TEST-2920 "$ENG_OUT" '"reason":"pending_diverged"'
  want TEST-2920 "$ENG_OUT" '  sync-base: retained'
  [[ -f "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/pending.json" ]] || fail TEST-2920 'the pending journal was deleted'
  [[ -f "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/sync/$EV" ]] || fail TEST-2920 'the archived ledger tail is gone'
  [[ "$(cat "$ORIGIN/$EV")" == 'someone rewrote the ledger' ]] || fail TEST-2920 'the live ledger was overwritten'
  [[ ! -e "$RIDE" ]] || fail TEST-2920 'the rest of the cleanup did not finish'
  assert_nothing_lost TEST-2920
  echo 'PASS: TEST-2920 a crash at each new mutation point converges to the uninterrupted tree'
}

# ---- D9/D11: the skill and the governance files -----------------------------------------------------------------
test_2922_skill_and_engine_agree() {
  local text step1 step2 block_lines
  text="$(cat "$SKILL_BLOCK")"
  step1="$(awk '/^1\. / { f = 1 } /^2\. / { f = 0 } f' "$SKILL_BLOCK")"
  step2="$(awk '/^2\. / { f = 1 } /^3\. / { f = 0 } f' "$SKILL_BLOCK")"
  [[ -n "$step1" && -n "$step2" ]] || fail TEST-2922 'SKILL_MERGE step 1 or 2 not found (positive control)'
  for w in OUTCOME retry decide external AAI_DECIDE 'run the same block again'; do want TEST-2922 "$step2" "$w"; done
  unwanted TEST-2922 "$step1" 'Exit 3: relay the `REFUSE` line and stop'
  unwanted TEST-2922 "$step2" 'Exit 3 or 4: relay'
  want TEST-2922 "$step1" 'Exit 3: route its `OUTCOME` lines'
  # the pinned TEST-076 and TEST-034 sentences stay
  want TEST-2922 "$step1" 'A `platform_mismatch` or `platform_generic` REFUSE is relayed with its command and the run stops.'
  want TEST-2922 "$step1" 'Exit 4 (completion_pending) stops: re-run `/aai-merge <n>`.'
  want TEST-2922 "$step1" 'Exit 5 (head_race_lost) stops'
  want TEST-2922 "$text" 'never finish a step by hand'
  want TEST-2922 "$text" 'cleanup blocked:'
  # both blocks pass the decide flag
  block_lines="$(block_of AAI_MERGE_BEGIN AAI_MERGE_END "$SKILL_BLOCK")"
  want TEST-2922 "$block_lines" '--decide "$AAI_DECIDE"'
  want TEST-2922 "$(block_of AAI_MERGE_PS_BEGIN AAI_MERGE_PS_END "$SKILL_BLOCK")" "\$AaiDec = @('--decide', \$env:AAI_DECIDE)"
  # every option id the table offers that the engine does not execute is named in step 1 or 2
  want TEST-2922 "$step1 $step2" 'direct_new_head'
  want TEST-2922 "$step1 $step2" '`stop`'
  # the engine executes every other option id
  node --input-type=module -e '
import fs from "node:fs";
const root = process.argv[1];
const lib = await import(`file://${root}/.aai/scripts/lib/merge-outcomes.mjs`);
const src = fs.readFileSync(`${root}/.aai/scripts/merge-cleanup.mjs`, "utf8");
const ids = new Set();
for (const r of Object.keys(lib.OUTCOME_TABLE)) for (const ph of ["plan", "step"]) for (const retry of [true, false]) for (const o of lib.classify(r, { phase: ph, retry }).options) ids.add(o.id);
for (const id of ids) {
  if (["direct_new_head", "stop"].includes(id)) continue;
  if (!src.includes(`"${id}"`) && !src.includes(`\x27${id}\x27`)) throw new Error(`option ${id} is neither executed by the engine nor named for the skill`);
}
console.log("ok");' "$ROOT" >/dev/null || fail TEST-2922 'an option id is neither executed by the engine nor named for the skill'
  # none of the D10 words in the skill, the library or the engine
  for w in 'guarantee' 'always safe' 'cannot lose' 'proves ownership'; do
    for f in "$SKILL_BLOCK" "$LIB" "$ENGINE"; do
      if /usr/bin/grep -qiF -- "$w" "$f"; then fail TEST-2922 "the word '$w' occurs in ${f##*/}"; fi
    done
  done
  # AGENTS.md rule 2 carries the sentence and the contract stays within 40 lines
  want TEST-2922 "$(cat "$ROOT/.aai/AGENTS.md")" 'The framework diagnoses and recovers its own problems'
  local n
  n="$(awk '/^### Operator contract/ { f = 1; next } /^### |^## / { if (f) exit } f { n++ } END { print n + 0 }' "$ROOT/.aai/AGENTS.md")"
  [[ "$n" -le 40 && "$n" -ge 38 ]] || fail TEST-2922 "the Operator contract section is $n lines, want at most 40"
  echo 'PASS: TEST-2922 the skill routes on OUTCOME lines and agrees with the engine'
}

test_2923_governance() {
  local profiles map glob_now growth entry lead n credit want
  profiles="$(cat "$ROOT/.aai/system/PROFILES.yaml")"
  [[ "$(printf '%s\n' "$profiles" | awk 'index($0, "  - .aai/scripts/lib/merge-outcomes.mjs") == 1 { n++ } END { print n + 0 }')" == 1 ]] || fail TEST-2923 'PROFILES does not list lib/merge-outcomes.mjs exactly once'
  [[ "$(section_of '^core:' '^[a-z_]+:' "$ROOT/.aai/system/PROFILES.yaml" | awk 'index($0, "  - .aai/scripts/lib/merge-outcomes.mjs") == 1 { n++ } END { print n + 0 }')" == 1 ]] || fail TEST-2923 'lib/merge-outcomes.mjs is not in the core profile'
  map="$(section_of '^  aai-merge-cleanup:' '^  [a-z0-9-]+:' "$ROOT/tests/skills/suite-map.yaml")"
  want TEST-2923 "$map" '.aai/scripts/lib/merge-outcomes.mjs'
  entry="$(/usr/bin/grep -F 'JUSTIFIED_ADDITIONS+=( "' "$ROOT/tests/skills/lib/prompt-diet-ledger.sh" | awk 'index($0, "merge-cleanup-resolves-framework-friction") > 0' || true)"
  n="$(printf '%s\n' "$entry" | awk 'NF { n++ } END { print n + 0 }')"
  [[ "$n" == 1 ]] || fail TEST-2923 "the diet ledger holds $n merge-cleanup-resolves-framework-friction entries, want exactly 1"
  lead="$(printf '%s' "$entry" | sed -n 's/^JUSTIFIED_ADDITIONS+=( "\([0-9][0-9]*\) merge-cleanup-resolves-framework-friction .*/\1/p')"
  glob_now="$(cat "$ROOT"/.aai/*.prompt.md | wc -c | tr -d ' ')"
  growth=$(( glob_now - 371301 ))
  [[ "$lead" == "$growth" && "$lead" -ge 1 && "$lead" -le 900 ]] || fail TEST-2923 "the ledger credits '$lead' B, the glob grew $growth B over 371301 (want equal, 1..900)"
  want="$(sed -n 's/.*local want_growth=\([0-9][0-9]*\).*/\1/p' "$ROOT/tests/skills/test-aai-prompt-diet.sh")"
  [[ "$want" == "$(( 63094 + lead ))" ]] || fail TEST-2923 "the TEST-012 pin is $want, want $(( 63094 + lead ))"
  want TEST-2923 "$(cat "$ROOT/tests/skills/test-aai-pr-preflight.sh")" "+$lead/* merge-cleanup-resolves-framework-friction"
  bash "$ROOT/tests/skills/test-aai-prompt-diet.sh" test_010_audit_and_reduction >"$SCRATCH/diet.out" 2>&1 || fail TEST-2923 "TEST-010 does not pass: $(cat "$SCRATCH/diet.out")"
  [[ "$(wc -l < "$ENGINE" | tr -d ' ')" -le 1490 ]] || fail TEST-2923 'merge-cleanup.mjs is over 1490 lines'
  [[ "$(wc -l < "$LIB" | tr -d ' ')" -le 520 ]] || fail TEST-2923 'lib/merge-outcomes.mjs is over 520 lines'
  echo 'PASS: TEST-2923 the library is in the profile and the suite map, the diet credit is the measured deficit'
}

test_2924_amended_prior_arms() {
  local t out
  for t in TEST-004 TEST-009 TEST-011 TEST-014 TEST-015 TEST-029 TEST-030 TEST-034 TEST-035 TEST-046 TEST-048; do
    out="$(bash "$HERE/test-aai-merge-cleanup.sh" --test "$t" 2>&1)" || fail TEST-2924 "the amended arm $t failed: $out"
  done
  echo 'PASS: TEST-2924 the amended prior arms pass through their own selectors'
}

# ---------------------------------------------------------------------------
case "$SELECTED" in
  '') test_005_apply_readback_gate;
     test_008_base_sync_preserves_work; test_009_base_sync_refusals; test_010_worktree_and_branch_cleanup; test_011_worktree_refusals
     test_013_second_apply_is_noop; test_014_interrupted_run_converges
     test_003_preflight_refusals; test_004_preflight_ready; test_015_downstream_layout
     test_018_direction_signs_ride_amendments; test_020_no_human_direction_signs_nothing; test_027_signature_cites_the_current_direction; test_021_signs_only_unsigned_contract_of_the_ride
     test_022_trackers_close_idempotent_resumable; test_023_preflight_lists_signs_on_merge; test_019_downstream_signs
     test_025_sign_merged_backlog; test_024_canon_merge_direction_signs; test_026_backlog_signed_on_live_ledger
     test_001_wrappers_and_pointers; test_002_prompt_block_runs_cleanup; test_017_companion_wiring
     test_028_submodule_worktree_removed_after_proof; test_029_dirty_submodule_kept; test_030_unpushed_submodule_kept
     test_031_submodule_ignored_archived_or_named; test_032_late_dirt_stops_then_resumes; test_033_preflight_names_cleanup_blocker; test_034_canon_stop_and_relay
     test_035_submodule_tags_archived
     test_036_remote_branch_deleted_by_lease; test_037_moved_remote_retained; test_038_absent_noop_and_idempotent
     test_039_fork_and_unknown_origin_retained; test_040_base_default_and_bad_name_retained; test_041_rejected_and_unreadable_never_stop
     test_042_canon_runs_block_unwrapped; test_043_dependents_retain_remote_branch
     test_044_push_url_must_equal_fetch_url
     test_045_ride_roadmap_entry_taken_from_incoming; test_046_foreign_roadmap_hunk_refuses_overlap
     test_047_ride_ledger_appends_moved; test_048_non_append_ledger_change_refused
     test_051_ledger_tail_resume_key_and_count; test_053_reset_ride_ledger_is_not_a_resume_candidate
     test_054_resume_matches_the_appended_segment; test_055_unappended_intent_is_not_counted
     test_056_historical_journal_tolerance; test_057_codebase_reduction_and_green_suite; test_058_merge_cleanup_line_ceiling; test_059_lane_gate_passes_without_pr_sweep; test_060_skill_pr_prompt_free_of_pr_sweep; test_061_prompt_diet_passes
     test_068_generic_refuses_with_manual; test_070_azure_preflight_ready_and_refusals; test_072_azure_apply_cleanup
     test_073_platform_mismatch_refuses_before_any_read; test_074_github_recorded_and_legacy_unchanged
     test_075_reconcile_origin_step
     test_2901_outcome_table_complete; test_2902_outcome_lines_from_real_runs; test_2903_pr485_parent_child_roadmap; test_2904_unrepresented_roadmap_decides; test_2905_absent_links_pr_proven_by_merge_commit; test_2906_conflicting_or_old_identity_not_proven; test_2907_superseded_draft_archived; test_2908_divergent_draft_menu; test_2909_unproven_drafts_untouched; test_2910_generated_projection_taken; test_2911_decide_channel; test_2912_router_resumes_in_one_interaction; test_2914_worktree_protections_kept; test_2915_sync_protections_kept; test_2916_preflight_gates_hold; test_2917_archive_verification_and_no_new_primitive; test_2918_next_attempt; test_2919_retry_chain_terminates; test_2920_interrupted_recovery_converges; test_2921_plain_summary; test_2922_skill_and_engine_agree; test_2923_governance; test_2924_amended_prior_arms ;;
  TEST-059|test_059_lane_gate_passes_without_pr_sweep) test_059_lane_gate_passes_without_pr_sweep ;;
  TEST-060|test_060_skill_pr_prompt_free_of_pr_sweep) test_060_skill_pr_prompt_free_of_pr_sweep ;;
  TEST-061|test_061_prompt_diet_passes) test_061_prompt_diet_passes ;;
  TEST-001|test_001_wrappers_and_pointers) test_001_wrappers_and_pointers ;;
  TEST-002|test_002_prompt_block_runs_cleanup) test_002_prompt_block_runs_cleanup ;;
  TEST-016|test_016_powershell_parity) test_016_powershell_parity ;;
  TEST-017|test_017_companion_wiring) test_017_companion_wiring ;;
  TEST-003|test_003_preflight_refusals) test_003_preflight_refusals ;;
  TEST-004|test_004_preflight_ready) test_004_preflight_ready ;;
  TEST-015|test_015_downstream_layout) test_015_downstream_layout ;;
  TEST-005|test_005_apply_readback_gate) test_005_apply_readback_gate ;;
  TEST-008|test_008_base_sync_preserves_work) test_008_base_sync_preserves_work ;;
  TEST-009|test_009_base_sync_refusals) test_009_base_sync_refusals ;;
  TEST-010|test_010_worktree_and_branch_cleanup) test_010_worktree_and_branch_cleanup ;;
  TEST-011|test_011_worktree_refusals) test_011_worktree_refusals ;;
  TEST-013|test_013_second_apply_is_noop) test_013_second_apply_is_noop ;;
  TEST-014|test_014_interrupted_run_converges) test_014_interrupted_run_converges ;;
  TEST-018|test_018_direction_signs_ride_amendments) test_018_direction_signs_ride_amendments ;;
  TEST-020|test_020_no_human_direction_signs_nothing) test_020_no_human_direction_signs_nothing ;;
  TEST-027|test_027_signature_cites_the_current_direction) test_027_signature_cites_the_current_direction ;;
  TEST-021|test_021_signs_only_unsigned_contract_of_the_ride) test_021_signs_only_unsigned_contract_of_the_ride ;;
  TEST-022|test_022_trackers_close_idempotent_resumable) test_022_trackers_close_idempotent_resumable ;;
  TEST-023|test_023_preflight_lists_signs_on_merge) test_023_preflight_lists_signs_on_merge ;;
  TEST-019|test_019_downstream_signs) test_019_downstream_signs ;;
  TEST-025|test_025_sign_merged_backlog) test_025_sign_merged_backlog ;;
  TEST-024|test_024_canon_merge_direction_signs) test_024_canon_merge_direction_signs ;;
  TEST-026|test_026_backlog_signed_on_live_ledger) test_026_backlog_signed_on_live_ledger ;;
  TEST-028|test_028_submodule_worktree_removed_after_proof) test_028_submodule_worktree_removed_after_proof ;;
  TEST-029|test_029_dirty_submodule_kept) test_029_dirty_submodule_kept ;;
  TEST-030|test_030_unpushed_submodule_kept) test_030_unpushed_submodule_kept ;;
  TEST-031|test_031_submodule_ignored_archived_or_named) test_031_submodule_ignored_archived_or_named ;;
  TEST-032|test_032_late_dirt_stops_then_resumes) test_032_late_dirt_stops_then_resumes ;;
  TEST-033|test_033_preflight_names_cleanup_blocker) test_033_preflight_names_cleanup_blocker ;;
  TEST-034|test_034_canon_stop_and_relay) test_034_canon_stop_and_relay ;;
  TEST-035|test_035_submodule_tags_archived) test_035_submodule_tags_archived ;;
  TEST-036|test_036_remote_branch_deleted_by_lease) test_036_remote_branch_deleted_by_lease ;;
  TEST-037|test_037_moved_remote_retained) test_037_moved_remote_retained ;;
  TEST-038|test_038_absent_noop_and_idempotent) test_038_absent_noop_and_idempotent ;;
  TEST-039|test_039_fork_and_unknown_origin_retained) test_039_fork_and_unknown_origin_retained ;;
  TEST-040|test_040_base_default_and_bad_name_retained) test_040_base_default_and_bad_name_retained ;;
  TEST-041|test_041_rejected_and_unreadable_never_stop) test_041_rejected_and_unreadable_never_stop ;;
  TEST-042|test_042_canon_runs_block_unwrapped) test_042_canon_runs_block_unwrapped ;;
  TEST-043|test_043_dependents_retain_remote_branch) test_043_dependents_retain_remote_branch ;;
  TEST-044|test_044_push_url_must_equal_fetch_url) test_044_push_url_must_equal_fetch_url ;;
  TEST-045|test_045_ride_roadmap_entry_taken_from_incoming) test_045_ride_roadmap_entry_taken_from_incoming ;;
  TEST-046|test_046_foreign_roadmap_hunk_refuses_overlap) test_046_foreign_roadmap_hunk_refuses_overlap ;;
  TEST-047|test_047_ride_ledger_appends_moved) test_047_ride_ledger_appends_moved ;;
  TEST-048|test_048_non_append_ledger_change_refused) test_048_non_append_ledger_change_refused ;;
  TEST-051|test_051_ledger_tail_resume_key_and_count) test_051_ledger_tail_resume_key_and_count ;;
  TEST-053|test_053_reset_ride_ledger_is_not_a_resume_candidate) test_053_reset_ride_ledger_is_not_a_resume_candidate ;;
  TEST-054|test_054_resume_matches_the_appended_segment) test_054_resume_matches_the_appended_segment ;;
  TEST-055|test_055_unappended_intent_is_not_counted) test_055_unappended_intent_is_not_counted ;;
  TEST-056|test_056_historical_journal_tolerance) test_056_historical_journal_tolerance ;;
  TEST-057|test_057_codebase_reduction_and_green_suite) test_057_codebase_reduction_and_green_suite ;;
  TEST-058|test_058_merge_cleanup_line_ceiling) test_058_merge_cleanup_line_ceiling ;;
  TEST-068|test_068_generic_refuses_with_manual) test_068_generic_refuses_with_manual ;;
  TEST-070|test_070_azure_preflight_ready_and_refusals) test_070_azure_preflight_ready_and_refusals ;;
  TEST-072|test_072_azure_apply_cleanup) test_072_azure_apply_cleanup ;;
  TEST-073|test_073_platform_mismatch_refuses_before_any_read) test_073_platform_mismatch_refuses_before_any_read ;;
  TEST-074|test_074_github_recorded_and_legacy_unchanged) test_074_github_recorded_and_legacy_unchanged ;;
  TEST-075|test_075_reconcile_origin_step) test_075_reconcile_origin_step ;;
  TEST-2901|test_2901_outcome_table_complete) test_2901_outcome_table_complete ;;
  TEST-2902|test_2902_outcome_lines_from_real_runs) test_2902_outcome_lines_from_real_runs ;;
  TEST-2903|test_2903_pr485_parent_child_roadmap) test_2903_pr485_parent_child_roadmap ;;
  TEST-2904|test_2904_unrepresented_roadmap_decides) test_2904_unrepresented_roadmap_decides ;;
  TEST-2905|test_2905_absent_links_pr_proven_by_merge_commit) test_2905_absent_links_pr_proven_by_merge_commit ;;
  TEST-2906|test_2906_conflicting_or_old_identity_not_proven) test_2906_conflicting_or_old_identity_not_proven ;;
  TEST-2907|test_2907_superseded_draft_archived) test_2907_superseded_draft_archived ;;
  TEST-2908|test_2908_divergent_draft_menu) test_2908_divergent_draft_menu ;;
  TEST-2909|test_2909_unproven_drafts_untouched) test_2909_unproven_drafts_untouched ;;
  TEST-2910|test_2910_generated_projection_taken) test_2910_generated_projection_taken ;;
  TEST-2911|test_2911_decide_channel) test_2911_decide_channel ;;
  TEST-2912|test_2912_router_resumes_in_one_interaction) test_2912_router_resumes_in_one_interaction ;;
  TEST-2914|test_2914_worktree_protections_kept) test_2914_worktree_protections_kept ;;
  TEST-2915|test_2915_sync_protections_kept) test_2915_sync_protections_kept ;;
  TEST-2916|test_2916_preflight_gates_hold) test_2916_preflight_gates_hold ;;
  TEST-2917|test_2917_archive_verification_and_no_new_primitive) test_2917_archive_verification_and_no_new_primitive ;;
  TEST-2918|test_2918_next_attempt) test_2918_next_attempt ;;
  TEST-2919|test_2919_retry_chain_terminates) test_2919_retry_chain_terminates ;;
  TEST-2920|test_2920_interrupted_recovery_converges) test_2920_interrupted_recovery_converges ;;
  TEST-2921|test_2921_plain_summary) test_2921_plain_summary ;;
  TEST-2922|test_2922_skill_and_engine_agree) test_2922_skill_and_engine_agree ;;
  TEST-2923|test_2923_governance) test_2923_governance ;;
  TEST-2924|test_2924_amended_prior_arms) test_2924_amended_prior_arms ;;
  *) fail SELECTOR "unknown test $SELECTED" ;;
esac
