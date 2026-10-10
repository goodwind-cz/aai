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
fields='number,state,isDraft,headRefOid,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url'
if [ "$#" -eq 5 ] && [ "$1" = pr ] && [ "$2" = view ] && [ "$4" = --json ] && [ "$5" = "$fields" ]; then
  case "$3" in ''|*[!0-9]*) echo "STUB-DENY: pr number $3" >&2; exit 1 ;; esac
  if [ -f "$dir/pr-$3.json" ]; then cat "$dir/pr-$3.json"; exit 0; fi
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
  run mkdir -p "$ORIGIN/docs/ai"
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
  run git -C "$ORIGIN" commit -qm baseline
  run git -C "$ORIGIN" push -q origin main
  run git -C "$ORIGIN" fetch -q origin
  if [[ -n "${DOWNSTREAM:-}" ]]; then install_core_layer; fi
  run mkdir -p "$ORIGIN/docs/issues" "$ORIGIN/docs/specs"
  draft_issue_v1 > "$ORIGIN/$DRAFT_ISSUE"
  draft_spec_v1 > "$ORIGIN/$DRAFT_SPEC"
  run git -C "$ORIGIN" worktree add -q -b "$BRANCH" "$RIDE" main
  run git -C "$RIDE" config user.name 'AAI Fixture'
  run git -C "$RIDE" config user.email 'fixture@example.invalid'
  if [[ -n "${DOWNSTREAM:-}" ]]; then run node "$ORIGIN/.aai/scripts/worktree-seed.mjs" --source "$ORIGIN" --target "$RIDE" >/dev/null; fi
  run mkdir -p "$RIDE/docs/issues" "$RIDE/docs/specs"
  run cp "$ORIGIN/$DRAFT_ISSUE" "$RIDE/$DRAFT_ISSUE"
  run cp "$ORIGIN/$DRAFT_SPEC" "$RIDE/$DRAFT_SPEC"
  run git -C "$RIDE" add "$DRAFT_ISSUE" "$DRAFT_SPEC"
  run git -C "$RIDE" commit -qm 'docs: drafts'
  run git -C "$RIDE" mv "$DRAFT_ISSUE" "$NUM_ISSUE"
  run git -C "$RIDE" mv "$DRAFT_SPEC" "$NUM_SPEC"
  numbered_issue > "$RIDE/$NUM_ISSUE"
  numbered_spec > "$RIDE/$NUM_SPEC"
  printf '{"v":1,"ts":"2026-10-10T00:00:00Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n{"v":1,"ts":"2026-10-10T00:00:01Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n' "$ISSUE_ID" "$SPEC_ID" >> "$RIDE/docs/ai/EVENTS.jsonl"
  printf 'delivered by the ride\n' >> "$RIDE/README.md"
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

draft_issue_v1() { printf -- '---\nid: %s\ntype: issue\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Issue foo\n\nDraft body.\n' "$ISSUE_ID"; }
draft_spec_v1() { printf -- '---\nid: %s\ntype: spec\nnumber: null\nstatus: implementing\nlinks:\n  requirement: %s\n  pr: []\n  commits: []\n---\n\n# Spec foo\n\nDraft spec body.\n' "$SPEC_ID" "$ISSUE_ID"; }
numbered_issue() { printf -- '---\nid: %s\ntype: issue\nnumber: 1\nstatus: %s\nlinks:\n  pr:\n    - %s\n  commits: []\n---\n\n# Issue foo\n\nDraft body.\n\nDelivered.\n' "$ISSUE_ID" "${ISSUE_STATUS:-done}" "${ISSUE_LINK_PR:-$PR}"; }
other_item_doc() { printf -- '---\nid: other-item\ntype: issue\nnumber: 2\nstatus: implementing\nlinks:\n  pr: []\n  commits: []\n---\n\n# Other item\n\nStill in flight.\n'; }
numbered_spec() { printf -- '---\nid: %s\ntype: spec\nnumber: 1\nstatus: done\nlinks:\n  requirement: %s\n  pr:\n    - %s\n  commits: []\n---\n\n# Spec foo\n\nDraft spec body.\n\nDelivered.\n\n## Acceptance Criteria Status\n\n| Spec-AC | Description | Status | Evidence | Review-By | Notes |\n|---|---|---|---|---|---|\n| Spec-AC-01 | The fixture spec is delivered. | done | docs/ai/tdd/foo-green.log | tdd | fixture |\n' "$SPEC_ID" "$ISSUE_ID" "$PR"; }

# write_pr_json <state> <merge-commit-oid|null>
write_pr_json() {
  local state="$1" mc="$2" mcjson='null'
  if [[ "$mc" != null ]]; then mcjson="{\"oid\":\"$mc\"}"; fi
  printf '{"number":%s,"state":"%s","isDraft":false,"headRefOid":"%s","headRefName":"%s","baseRefName":"main","mergeStateStatus":"UNKNOWN","statusCheckRollup":[],"mergeCommit":%s,"url":"https://github.com/example/repo/pull/%s"}\n' \
    "$PR" "$state" "$HEAD_OID" "$BRANCH" "$mcjson" "$PR" > "$GHD/pr-$PR.json"
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
    [[ -f "$ORIGIN/$DRAFT_ISSUE" && -f "$ORIGIN/$DRAFT_SPEC" ]] || fail TEST-005 "arm $state/$reason lost a draft"
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

test_006_superseded_drafts() {
  build_world drafts
  local issue_sha spec_sha arch lines after_audit
  issue_sha="$(sha_of "$ORIGIN/$DRAFT_ISSUE")"
  spec_sha="$(sha_of "$ORIGIN/$DRAFT_SPEC")"
  run cp "$ORIGIN/$DRAFT_ISSUE" "$W/orig-issue.md"
  run cp "$ORIGIN/$DRAFT_SPEC" "$W/orig-spec.md"
  # the numbered docs reach the origin checkout through the engine's own
  # sync-base step; positive control: they are absent before apply
  [[ ! -e "$ORIGIN/$NUM_ISSUE" && ! -e "$ORIGIN/$NUM_SPEC" ]] || fail TEST-006 'numbered docs already in the origin before apply'

  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-006 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" && ! -e "$ORIGIN/$DRAFT_SPEC" ]] || fail TEST-006 'superseded draft still in the origin tree'
  cmp "$W/orig-issue.md" "$arch/files/$DRAFT_ISSUE" || fail TEST-006 'archived issue draft bytes differ'
  cmp "$W/orig-spec.md" "$arch/files/$DRAFT_SPEC" || fail TEST-006 'archived spec draft bytes differ'
  [[ -f "$ORIGIN/$NUM_ISSUE" && -f "$ORIGIN/$NUM_SPEC" ]] || fail TEST-006 'numbered docs missing from the origin'
  lines="$(wc -l < "$arch/manifest.jsonl" | tr -d ' ')"
  [[ "$lines" == 2 ]] || fail TEST-006 "manifest has $lines lines, want 2"
  want TEST-006 "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$issue_sha\""
  want TEST-006 "$(cat "$arch/manifest.jsonl")" "\"sha256\":\"$spec_sha\""
  want TEST-006 "$(cat "$arch/manifest.jsonl")" "\"original\":\"$DRAFT_ISSUE\""
  want TEST-006 "$(cat "$arch/manifest.jsonl")" '"reason":"superseded"'
  want TEST-006 "$(cat "$arch/manifest.jsonl")" '"step":"archive-drafts"'
  [[ "$(json_get "$ENG_OUT" 'j.archived.length')" == 2 ]] || fail TEST-006 'JSON report archived count'
  [[ "$(json_get "$ENG_OUT" 'j.retained.length')" == 0 ]] || fail TEST-006 'nothing should be retained'
  after_audit="$(audit_verdict)"
  want TEST-006 "$after_audit" 'Verdict: CLEAN'
  assert_no_merge_call TEST-006
  echo 'PASS: TEST-006 superseded drafts archived by identity'
}

test_007_retained_and_decisions() {
  build_world retain
  local arch before after rep other="docs/issues/ISSUE-DRAFT-other.md"
  # unrelated id: not delivered by the PR
  printf -- '---\nid: other\ntype: issue\nnumber: null\nstatus: draft\nlinks:\n  pr: []\n  commits: []\n---\n\n# Other\n' > "$ORIGIN/$other"
  # same id as the delivered spec but different bytes (CRLF-converted copy)
  draft_spec_v1 | sed 's/$/\r/' > "$W/divergent-spec.md"
  run cp "$W/divergent-spec.md" "$ORIGIN/$DRAFT_SPEC"
  # the issue draft stays byte-identical to history (superseded)
  arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"

  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-007 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  [[ -f "$ORIGIN/$other" ]] || fail TEST-007 'unrelated draft was removed'
  [[ -f "$ORIGIN/$DRAFT_SPEC" ]] || fail TEST-007 'divergent draft was removed'
  cmp "$W/divergent-spec.md" "$ORIGIN/$DRAFT_SPEC" || fail TEST-007 'divergent draft bytes changed'
  [[ ! -e "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-007 'identical issue draft was not archived (positive control)'
  want TEST-007 "$rep" '"reason":"unrelated_id"'
  want TEST-007 "$rep" '"reason":"divergent_content"'
  want TEST-007 "$(json_get "$rep" 'j.remaining')" "$DRAFT_SPEC"
  [[ "$(json_get "$rep" 'j.archived.length')" == 1 ]] || fail TEST-007 'only the identical draft may be archived'
  [[ ! -e "$arch/files/$DRAFT_SPEC" && ! -e "$arch/files/$other" ]] || fail TEST-007 'retained draft leaked into the archive'

  # --archive-divergent naming a draft that is NOT divergent is refused untouched
  before="$(world_digest)"
  run_engine apply --pr "$PR" --pid 4242 --archive-divergent "$other"
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-007 "unrelated --archive-divergent exited $ENG_RC, want 3"
  want TEST-007 "$ENG_OUT" 'REFUSE archive_divergent_not_candidate'
  [[ "$(world_digest)" == "$before" ]] || fail TEST-007 'refused --archive-divergent changed the fixture'

  # the explicit decision archives the divergent copy; a differing file already
  # occupying the archive path is never overwritten (numeric suffix instead)
  run mkdir -p "$arch/files/docs/specs"
  printf 'squatter\n' > "$arch/files/$DRAFT_SPEC"
  run_engine apply --pr "$PR" --pid 4242 --json --archive-divergent "$DRAFT_SPEC"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-007 "decision run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$ORIGIN/$DRAFT_SPEC" ]] || fail TEST-007 'named divergent draft still in the origin'
  [[ "$(cat "$arch/files/$DRAFT_SPEC")" == squatter ]] || fail TEST-007 'archive squatter was overwritten'
  after="$(json_get "$ENG_OUT" "j.archived.find(a=>a.path===\"$DRAFT_SPEC\").archive")"
  [[ -f "$ORIGIN/$after" ]] || fail TEST-007 "archive path from report missing: $after"
  cmp "$W/divergent-spec.md" "$ORIGIN/$after" || fail TEST-007 'archived divergent bytes differ from the original'
  [[ "$after" != "docs/ai/archive/merge-cleanup/pr-$PR/files/$DRAFT_SPEC" ]] || fail TEST-007 'archive path was not suffixed'
  [[ -f "$ORIGIN/$other" ]] || fail TEST-007 'unrelated draft vanished during the decision run'
  want TEST-007 "$ENG_OUT" '"reason":"unrelated_id"'
  want TEST-007 "$(cat "$arch/manifest.jsonl")" '"reason":"divergent_archived_by_decision"'

  # bot sweep P2-1: a draft edited by another session after it was classified (or after it was
  # archived, before the unlink) is never deleted; the working copy stays, the run reports
  # divergent_after_plan, and the archive copy stays recoverable. The other draft is the control.
  local point
  for point in before-archive before-unlink; do
    build_world "race_$point"
    ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_EDIT_DRAFT="$point:$DRAFT_ISSUE" node "$ENGINE" apply --pr "$PR" --pid 4242 --json >"$W/engine.out" 2>"$W/engine.err" ) || fail TEST-007 "race arm $point exited non-zero: $(cat "$W/engine.out") $(cat "$W/engine.err")"
    rep="$(cat "$W/engine.out")"
    [[ -f "$ORIGIN/$DRAFT_ISSUE" ]] || fail TEST-007 "race arm $point: the edited draft was deleted"
    has "$(cat "$ORIGIN/$DRAFT_ISSUE")" 'edited by another session' || fail TEST-007 "race arm $point: the working copy lost the other session's edit"
    [[ ! -e "$ORIGIN/$DRAFT_SPEC" ]] || fail TEST-007 "race arm $point: the untouched draft was not archived (positive control)"
    want TEST-007 "$rep" '"reason":"divergent_after_plan"'
    want TEST-007 "$(json_get "$rep" 'j.remaining')" "$DRAFT_ISSUE"
    want TEST-007 "$(json_get "$rep" 'j.remaining')" 'divergent_after_plan'
    arch="$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR"
    [[ "$(json_get "$rep" 'j.archived.length')" -ge 1 ]] || fail TEST-007 "race arm $point: nothing archived"
    # The manifest records an edited draft as superseded only when its archived bytes are the
    # PR's: edited before the copy -> no record for it; edited after the copy -> one record.
    local recs
    recs="$(node -e 'const fs=require("fs");const [m,p]=process.argv.slice(1);const t=fs.existsSync(m)?fs.readFileSync(m,"utf8"):"";console.log(t.split("\n").filter(Boolean).map(JSON.parse).filter(r=>r.original===p).length)' "$arch/manifest.jsonl" "$DRAFT_ISSUE")"
    if [[ "$point" == before-archive ]]; then
      [[ "$recs" == 0 ]] || fail TEST-007 "race arm $point: the edited draft was recorded in the manifest ($recs record(s)) although its bytes were never in the PR"
    else
      [[ "$recs" == 1 ]] || fail TEST-007 "race arm $point: want one manifest record of the PR bytes, got $recs"
    fi
  done

  # degenerate: no drafts at all -> clean no-op, no archive directory created
  build_world empty
  run rm "$ORIGIN/$DRAFT_ISSUE" "$ORIGIN/$DRAFT_SPEC"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-007 "empty-world apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ ! -e "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/files" && ! -e "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/manifest.jsonl" ]] || fail TEST-007 'empty-world apply archived a draft'
  [[ "$(json_get "$ENG_OUT" 'j.archived.length')" == 0 ]] || fail TEST-007 'empty-world archived count'
  echo 'PASS: TEST-007 retained drafts and explicit decisions'
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

test_009_base_sync_refusals() {
  local before
  build_world origin_not_on_base
  run git -C "$ORIGIN" checkout -q -b elsewhere
  refuse_arm TEST-009 origin_not_on_base elsewhere

  build_world base_diverged
  printf 'local commit\n' > "$ORIGIN/local-commit.txt"
  run git -C "$ORIGIN" add local-commit.txt
  run git -C "$ORIGIN" commit -qm 'local commit not on origin'
  refuse_arm TEST-009 base_diverged main

  build_world overlap
  printf 'dirty and also changed by the PR\n' >> "$ORIGIN/README.md"
  refuse_arm TEST-009 overlap README.md

  build_world untracked_collision
  printf 'my own different file\n' > "$ORIGIN/$NUM_ISSUE"
  refuse_arm TEST-009 untracked_collision "$NUM_ISSUE"

  build_world ledger_rewritten
  printf '{"v":1,"ts":"2026-10-09T00:00:00Z","actor":"fixture","event":"seed","ref":"REWRITTEN","payload":{}}\n' > "$ORIGIN/$EV"
  refuse_arm TEST-009 ledger_rewritten "$EV"

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
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="archive-drafts").targets')" "$DRAFT_ISSUE"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="archive-drafts").targets')" "docs/ai/archive/merge-cleanup/pr-$PR/files/$DRAFT_ISSUE"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="archive-runtime").targets')" "worktree:docs/ai/STATE.yaml"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="archive-runtime").targets')" "docs/ai/archive/merge-cleanup/pr-$PR/worktree/docs/ai/STATE.yaml"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="sync-base").targets')" "$(git -C "$ORIGIN" rev-parse --short=12 HEAD)..$(git -C "$ORIGIN" rev-parse --short=12 "$MC")"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="remove-worktree").targets')" "$RIDE"
  want TEST-010 "$(json_get "$rep" 'j.steps.find(s=>s.id==="delete-branch").targets')" "$BRANCH"
  [[ "$(json_get "$rep" 'j.steps.find(s=>s.id==="delete-branch").status')" == planned ]] || fail TEST-010 'plan step status is not planned'

  run_engine apply --pr "$PR" --pid "$pid" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-010 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  # bot sweep P2-2: the report lists every archived file (runtime STATE and ignored evidence
  # included) with its recovery path
  for f in $RUNTIME_FILES; do
    want TEST-010 "$(json_get "$rep" 'j.archived.map(a=>a.path+" "+a.archive)')" "worktree:$f docs/ai/archive/merge-cleanup/pr-$PR/worktree/$f"
  done
  # archived bytes are sha-equal to the pre-removal bytes
  for f in $RUNTIME_FILES; do
    [[ "$(sha_of "$arch/worktree/$f")" == "$(sha_of "$(kf "$f")")" ]] || fail TEST-010 "archived $f differs from the pre-removal bytes"
    want TEST-010 "$(cat "$arch/manifest.jsonl")" "\"original\":\"worktree:$f\""
  done
  want TEST-010 "$(cat "$arch/manifest.jsonl")" '"step":"archive-runtime"'
  # evidence copied into the origin only where absent
  cmp "$(kf docs/ai/tdd/only-ride.log)" "$ORIGIN/docs/ai/tdd/only-ride.log" || fail TEST-010 'absent evidence was not copied into the origin'
  [[ "$(cat "$ORIGIN/docs/ai/tdd/shared.log")" == 'origin version' ]] || fail TEST-010 'a differing origin evidence file was overwritten'
  # worktree removed, branch deleted although it is not an ancestor
  [[ ! -e "$RIDE" ]] || fail TEST-010 'ride worktree directory still exists'
  unwanted TEST-010 "$(git -C "$ORIGIN" worktree list --porcelain)" "$RIDE"
  if git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then fail TEST-010 'ride branch still exists'; fi
  # everything else is intact
  [[ -d "$other" ]] || fail TEST-010 'the other worktree was removed'
  git -C "$ORIGIN" rev-parse -q --verify refs/heads/ride/other >/dev/null || fail TEST-010 'the other worktree branch was deleted'
  git -C "$ORIGIN" rev-parse -q --verify refs/heads/misc >/dev/null || fail TEST-010 'an unrelated branch was deleted'
  git -C "$BARE" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-010 'the remote branch was deleted'
  git -C "$BARE" rev-parse -q --verify refs/heads/misc-remote >/dev/null || fail TEST-010 'an unrelated remote branch was deleted'
  want TEST-010 "$(json_get "$rep" 'j.remaining')" "origin/$BRANCH"
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
  refuse_arm TEST-011 worktree_dirty "$RIDE"
  [[ -d "$RIDE" ]] && git -C "$ORIGIN" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || fail TEST-011 'dirty arm lost the worktree or branch'

  build_world tip
  printf 'after the merge\n' > "$RIDE/after.txt"
  run git -C "$RIDE" add after.txt
  run git -C "$RIDE" commit -qm 'work after the merge'
  refuse_arm TEST-011 tip_mismatch "$BRANCH"
  [[ -d "$RIDE" ]] || fail TEST-011 'tip arm lost the worktree'

  build_world locked
  sleep 600 & pid=$!
  HELPER_PIDS+=("$pid")
  ( cd "$RIDE" && node "$ROOT/.aai/scripts/lib/session-lock.mjs" acquire --pid "$pid" >/dev/null ) || fail SETUP 'lock acquire'
  refuse_arm TEST-011 session_locked "$pid"
  stop_helper "$pid"
  [[ -d "$RIDE" ]] || fail TEST-011 'locked arm lost the worktree'

  build_world cwd
  ENG_CWD="$RIDE"
  refuse_arm TEST-011 cwd_inside_target "$RIDE"
  ENG_CWD=''
  [[ -d "$RIDE" ]] || fail TEST-011 'cwd arm lost the worktree'

  # a registered worktree whose directory is gone is named worktree_missing (never
  # worktree_dirty), is never pruned, and its branch is left alone (NB-4)
  build_world missing
  [[ -n "$RIDE" && "$RIDE" = /* && -d "$RIDE" ]] || fail SETUP 'missing-arm ride path'
  run rm -rf "$RIDE"
  refuse_arm TEST-011 worktree_missing "$RIDE"
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
ACTION_STEPS='archive-runtime archive-drafts sync-base state index-audit remove-worktree delete-branch report'
ALL_STEPS='resolve plan archive-runtime archive-drafts sync-base sign-amendments state index-audit remove-worktree delete-branch report'

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

test_012_state_index_report() {
  local rep before arm name focus reason rpt n idx
  # focus names the merged ref: the real state.mjs clears it
  build_world focus_hit
  seed_state foo
  before="$(sha_of "$ORIGIN/$STATE_REL")"
  run cp "$ORIGIN/$STATE_REL" "$W/state.pre"
  want TEST-012 "$(state_block "$ORIGIN/$STATE_REL" current_focus)" 'ref_id: foo'   # positive control
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
  [[ "$(sha_of "$ORIGIN/$STATE_REL")" != "$before" ]] || fail TEST-012 'STATE was not changed although the focus named the merged ref'
  want TEST-012 "$(state_block "$ORIGIN/$STATE_REL" current_focus)" 'ref_id: null'
  want TEST-012 "$(state_block "$ORIGIN/$STATE_REL" current_focus)" 'type: none'
  want TEST-012 "$(state_block "$ORIGIN/$STATE_REL" active_work_items)" 'status: done'
  want TEST-012 "$(state_block "$ORIGIN/$STATE_REL" active_work_items)" 'phase: closed'
  [[ "$(step_status "$rep" state)" == done ]] || fail TEST-012 "state step reported $(step_status "$rep" state), want done"
  # the gitignored origin STATE is archived byte-for-byte before the irreversible clear-focus
  cmp "$W/state.pre" "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/origin/$STATE_REL" || fail TEST-012 'origin STATE was not archived before clear-focus'
  want TEST-012 "$(cat "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/manifest.jsonl")" "\"original\":\"origin:$STATE_REL\""
  # no direction given: no directed_merge record and no direction line
  [[ ! -e "$ORIGIN/docs/ai/decisions.jsonl" ]] || fail TEST-012 'a decisions record was written without --direction'

  # index: numbered rows present, no DRAFT row for the delivered ids
  idx="$(cat "$ORIGIN/docs/INDEX.md")"
  want TEST-012 "$idx" 'ISSUE-0001'
  want TEST-012 "$idx" 'SPEC-0001'
  unwanted TEST-012 "$idx" 'ISSUE-DRAFT-foo'
  unwanted TEST-012 "$idx" 'SPEC-DRAFT-spec-foo'
  [[ "$(step_status "$rep" index-audit)" == done ]] || fail TEST-012 "index-audit step reported $(step_status "$rep" index-audit), want done"

  # report: JSON object carries every spec field ...
  [[ "$(json_get "$rep" 'j.base')" == main ]] || fail TEST-012 'report base'
  [[ "$(json_get "$rep" 'j.head')" == "$MC" ]] || fail TEST-012 "report head $(json_get "$rep" 'j.head'), want $MC"
  [[ "$(json_get "$rep" 'j.mergeCommit')" == "$MC" ]] || fail TEST-012 'report merge commit'
  [[ "$(json_get "$rep" 'Array.isArray(j.archived)&&Array.isArray(j.retained)&&Array.isArray(j.noops)&&Array.isArray(j.remaining)')" == true ]] || fail TEST-012 'report lacks an archived/retained/noops/remaining array'
  want TEST-012 "$(json_get "$rep" 'j.archived.map(a=>a.path)')" "$DRAFT_ISSUE"
  want TEST-012 "$(json_get "$rep" 'j.archived.map(a=>a.path)')" "$DRAFT_SPEC"
  want TEST-012 "$(json_get "$rep" 'j.archived.map(a=>a.path)')" "origin:docs/ai/STATE.yaml"
  want TEST-012 "$(json_get "$rep" 'j.audit')" 'Verdict: CLEAN'
  want TEST-012 "$(json_get "$rep" 'j.remaining')" "origin/$BRANCH"
  # ... and is saved under docs/ai/reports with the same fields
  n="$(saved_reports | wc -l | tr -d ' ')"
  [[ "$n" == 1 ]] || fail TEST-012 "$n saved reports, want 1"
  rpt="$(cat "$(saved_reports)")"
  want TEST-012 "$rpt" "- pr: $PR"
  want TEST-012 "$rpt" "- merge commit: $MC"
  want TEST-012 "$rpt" '- base: main'
  want TEST-012 "$rpt" "- final HEAD: $MC"
  want TEST-012 "$rpt" 'Verdict: CLEAN'
  want TEST-012 "$rpt" '## Archived'
  want TEST-012 "$rpt" "$DRAFT_ISSUE"
  want TEST-012 "$rpt" '## Retained'
  want TEST-012 "$rpt" '## No-ops'
  want TEST-012 "$rpt" '## Remaining'
  want TEST-012 "$rpt" "origin/$BRANCH"
  case "$(basename "$(saved_reports)")" in merge-cleanup-pr"$PR"-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z.md) ;; *) fail TEST-012 "report file name shape: $(saved_reports)" ;; esac
  assert_no_merge_call TEST-012

  # negative controls: no focus, another ref in focus, and no STATE at all leave
  # STATE byte-identical and report a named no-op
  for arm in "none||focus_not_this_ref" "other|other-ref|focus_not_this_ref" "nostate|-|no_state"; do
    name="${arm%%|*}"; focus="${arm#*|}"; reason="${focus#*|}"; focus="${focus%%|*}"
    build_world "focus_$name"
    if [[ "$focus" != - ]]; then seed_state "$focus"; fi
    if [[ -f "$ORIGIN/$STATE_REL" ]]; then run cp "$ORIGIN/$STATE_REL" "$W/state.keep"; fi
    run_engine apply --pr "$PR" --pid 4242 --json
    [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "arm $name exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
    [[ "$(step_status "$ENG_OUT" state)" == noop ]] || fail TEST-012 "arm $name state step reported $(step_status "$ENG_OUT" state), want noop"
    want TEST-012 "$(json_get "$ENG_OUT" 'j.noops')" "noop:state:$reason"
    if [[ -f "$W/state.keep" ]]; then
      cmp "$W/state.keep" "$ORIGIN/$STATE_REL" || fail TEST-012 "arm $name changed the STATE bytes"
    else
      [[ ! -e "$ORIGIN/$STATE_REL" ]] || fail TEST-012 "arm $name created a STATE file"
    fi
    if [[ "$name" == other ]]; then want TEST-012 "$(state_block "$ORIGIN/$STATE_REL" current_focus)" 'ref_id: other-ref'; fi
  done
  # the merged ref is the intake THIS PR delivered (status done, links.pr names the PR).
  # Negative arms, each with the origin focus on a ref the branch tail ALSO names (foo) or
  # on a doc the PR merely touches: the focus and STATE bytes stay, with a named no-op.
  # (a) the PR only edits another in-flight item's doc
  EXTRA_OTHER=1 build_world focus_other_doc
  seed_state other-item
  run cp "$ORIGIN/$STATE_REL" "$W/state.keep"
  want TEST-012 "$(git -C "$BARE" diff --name-only "$MC^1" "$MC")" 'ISSUE-0002-other-item.md'   # the PR really touches it
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "other-doc arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" state)" == noop ]] || fail TEST-012 "other-doc arm state step reported $(step_status "$ENG_OUT" state), want noop"
  want TEST-012 "$(json_get "$ENG_OUT" 'j.noops')" 'noop:state:focus_not_this_ref'
  cmp "$W/state.keep" "$ORIGIN/$STATE_REL" || fail TEST-012 'other-doc arm changed the STATE bytes'
  want TEST-012 "$(state_block "$ORIGIN/$STATE_REL" current_focus)" 'ref_id: other-item'
  unwanted TEST-012 "$(state_block "$ORIGIN/$STATE_REL" active_work_items)" 'status: done'
  [[ ! -e "$ORIGIN/docs/ai/archive/merge-cleanup/pr-$PR/origin" ]] || fail TEST-012 'other-doc arm archived a STATE it did not touch'
  # (b) the PR files the item in focus only as a DRAFT intake (status not done)
  ISSUE_STATUS=draft build_world focus_draft_only
  seed_state foo
  run cp "$ORIGIN/$STATE_REL" "$W/state.keep"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "draft-only arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" state)" == noop ]] || fail TEST-012 "draft-only arm state step reported $(step_status "$ENG_OUT" state), want noop"
  want TEST-012 "$(json_get "$ENG_OUT" 'j.noops')" 'noop:state:focus_not_this_ref'
  cmp "$W/state.keep" "$ORIGIN/$STATE_REL" || fail TEST-012 'draft-only arm changed the STATE bytes'
  # (c) done, but its links.pr names a different PR
  ISSUE_LINK_PR=999 build_world focus_other_pr
  seed_state foo
  run cp "$ORIGIN/$STATE_REL" "$W/state.keep"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "other-pr arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" state)" == noop ]] || fail TEST-012 "other-pr arm state step reported $(step_status "$ENG_OUT" state), want noop"
  cmp "$W/state.keep" "$ORIGIN/$STATE_REL" || fail TEST-012 'other-pr arm changed the STATE bytes'

  # (d) links.pr is read strictly (NB-r2-3): a URL for ANOTHER repository whose owner name carries
  # the digits of this PR (u433/r/pull/77) names no work of this PR, and a bare digit scrape would clear it
  ISSUE_LINK_PR='https://github.com/u433/r/pull/77' build_world focus_url_digits
  seed_state foo
  run cp "$ORIGIN/$STATE_REL" "$W/state.keep"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "url-digits arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" state)" == noop ]] || fail TEST-012 "url-digits arm state step reported $(step_status "$ENG_OUT" state), want noop"
  cmp "$W/state.keep" "$ORIGIN/$STATE_REL" || fail TEST-012 'url-digits arm changed the STATE bytes'
  # positive controls: the accepted shapes still clear (a '#N' entry is quoted, an unquoted # starts a YAML comment)
  n=0
  for arm in '"#433"' 'https://github.com/example/repo/pull/433'; do
    n=$((n + 1))
    ISSUE_LINK_PR="$arm" build_world "focus_link_shape_$n"
    seed_state foo
    run_engine apply --pr "$PR" --pid 4242 --json
    [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "link shape $arm exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
    [[ "$(step_status "$ENG_OUT" state)" == done ]] || fail TEST-012 "link shape $arm: state step reported $(step_status "$ENG_OUT" state), want done"
  done

  # the owner's verbatim direction and the merged head are recorded durably (D3/D9):
  # report, saved report and one directed_merge decision, once even when re-run
  build_world direction
  seed_state foo
  run_engine apply --pr "$PR" --pid 4242 --json --direction 'merge 433 please, the sweep is in'
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "direction apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(json_get "$ENG_OUT" 'j.direction')" == 'merge 433 please, the sweep is in' ]] || fail TEST-012 'JSON report lacks the verbatim direction'
  [[ "$(json_get "$ENG_OUT" 'j.mergedHead')" == "$HEAD_OID" ]] || fail TEST-012 'JSON report lacks the merged head'
  rpt="$(cat "$(saved_reports)")"
  want TEST-012 "$rpt" '- direction: merge 433 please, the sweep is in'
  want TEST-012 "$rpt" "- merged head: $HEAD_OID"
  idx="$ORIGIN/docs/ai/decisions.jsonl"
  [[ -f "$idx" ]] || fail TEST-012 'no decisions.jsonl record for the directed merge'
  [[ "$(wc -l < "$idx" | tr -d ' ')" == 1 ]] || fail TEST-012 'decisions.jsonl must hold exactly one record'
  [[ "$(json_get "$(cat "$idx")" 'j.type')" == directed_merge ]] || fail TEST-012 'decision record type'
  [[ "$(json_get "$(cat "$idx")" 'j.answer')" == 'merge 433 please, the sweep is in' ]] || fail TEST-012 'decision record answer is not the verbatim direction'
  [[ "$(json_get "$(cat "$idx")" 'j.pr')" == "$PR" ]] || fail TEST-012 'decision record pr'
  [[ "$(json_get "$(cat "$idx")" 'j.head')" == "$HEAD_OID" ]] || fail TEST-012 'decision record head'
  [[ "$(json_get "$(cat "$idx")" 'j.by')" == human ]] || fail TEST-012 'decision record by'
  before="$(sha_of "$idx")"
  run_engine apply --pr "$PR" --pid 4242 --json --direction 'merge 433 please, the sweep is in'
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "direction rerun exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$idx")" == "$before" ]] || fail TEST-012 'a repeat run duplicated the directed_merge record'
  [[ "$(saved_reports | wc -l | tr -d ' ')" == 1 ]] || fail TEST-012 'a repeat run wrote another report'

  # a non-CLEAN audit verdict is reported under remaining, never auto-remediated
  build_world audit_dirty
  printf -- '---\nid: stray\ntype: issue\nnumber: 50\nstatus: done\nlinks:\n  pr: []\n  commits: []\n---\n\n# Stray\n' > "$ORIGIN/docs/issues/ISSUE-0050-stray.md"
  run cp "$ORIGIN/docs/issues/ISSUE-0050-stray.md" "$W/stray.keep"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-012 "dirty-audit apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  unwanted TEST-012 "$(json_get "$ENG_OUT" 'j.audit')" 'Verdict: CLEAN'
  want TEST-012 "$(json_get "$ENG_OUT" 'j.audit')" 'NEEDS-TRIAGE'
  want TEST-012 "$(json_get "$ENG_OUT" 'j.remaining')" 'docs-audit'
  cmp "$W/stray.keep" "$ORIGIN/docs/issues/ISSUE-0050-stray.md" || fail TEST-012 'the audit finding was auto-remediated'
  echo 'PASS: TEST-012 focus, index and report'
}

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
  for f in UNRELATED.txt NOTE.txt "$EV" "$other" "$DRAFT_ISSUE" "$DRAFT_SPEC"; do
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
      case "$f" in ./docs/ai/reports/merge-cleanup-pr*|*/journal.jsonl) continue ;; esac
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
  # sign-amendments has no owner direction in this world: a named no-op on both runs
  want TEST-013 "$(json_get "$second" 'j.noops')" 'noop:sign-amendments:no_human_direction'
  [[ "$(json_get "$second" 'j.noops.length')" == 9 ]] || fail TEST-013 "second run lists $(json_get "$second" 'j.noops.length') no-ops, want 9"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-013 'second apply changed files, refs, worktrees or the reflog'
  [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 && "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-013 'second run duplicated a ledger line'
  [[ "$(LC_ALL=C sort "$ORIGIN/$EV" | uniq -d | wc -l | tr -d ' ')" == 0 ]] || fail TEST-013 'the ledger holds a duplicate line'
  [[ "$(saved_reports | wc -l | tr -d ' ')" == 1 ]] || fail TEST-013 'second run wrote another report'
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
    # bot sweep P2-2: drafts archived by the interrupted run are still in the final report
    want TEST-014 "$(json_get "$second" 'j.archived.map(a=>a.path)')" "$DRAFT_ISSUE"
    sig="$(tree_sig)"
    [[ "$sig" == "$control_sig" ]] || fail TEST-014 "resume after $id differs from the uninterrupted run: $(diff <(printf '%s\n' "$control_sig") <(printf '%s\n' "$sig") | awk 'NR <= 6' | tr '\n' ' ')"
    assert_nothing_lost TEST-014
    [[ "$(LC_ALL=C sort "$ORIGIN/$EV" | uniq -d | wc -l | tr -d ' ')" == 0 ]] || fail TEST-014 "resume after $id left a duplicate ledger line"
    [[ "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_A")" == 1 && "$(count_line "$ORIGIN/$EV" "$LOCAL_LINE_B")" == 1 ]] || fail TEST-014 "resume after $id: local ledger line not exactly once"
    [[ "$(saved_reports | wc -l | tr -d ' ')" == 1 ]] || fail TEST-014 "resume after $id left $(saved_reports | wc -l | tr -d ' ') reports, want 1"
    [[ "$(journal_dups)" == 0 ]] || fail TEST-014 "resume after $id: journal holds a duplicate step line"
    [[ "$(git -C "$ORIGIN" rev-parse HEAD)" == "$MC" ]] || fail TEST-014 "resume after $id: HEAD is not the merge commit"
    # a step completed before the interruption is reported as a named no-op on resume
    case " $ACTION_STEPS " in
      *" $id "*) [[ "$(step_status "$second" "$id")" == noop ]] || fail TEST-014 "resume after $id: step $id reported $(step_status "$second" "$id"), want noop"
                 want TEST-014 "$(json_get "$second" 'j.noops')" "noop:$id:" ;;
    esac
    assert_no_merge_call TEST-014
  done
  [[ "$(step_status "$control_state" state)" == done ]] || fail TEST-014 'control run did not clear the focus (positive control)'

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
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-014 "diverged arm: resume exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want TEST-014 "$ENG_OUT" 'REFUSE ledger_rewritten'
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
    expect_refusal TEST-003 checks_failing pf
  done
  for arm in BLOCKED BEHIND DIRTY UNSTABLE UNKNOWN HAS_HOOKS; do
    write_open_pr OPEN false "$HEAD_OID" "$arm" "$ROLLUP_OK"
    expect_refusal TEST-003 not_mergeable pf
  done
  # sweep_missing through the REAL lane-gate: no record, then a contradictory one
  write_open_pr OPEN false "$HEAD_OID" CLEAN "$ROLLUP_OK"
  run cp "$RIDE/docs/ai/EVENTS.jsonl" "$W/events.with-sweep"
  { /usr/bin/grep -v '"pr_sweep"' "$W/events.with-sweep" || true; } > "$RIDE/docs/ai/EVENTS.jsonl"
  expect_refusal TEST-003 sweep_missing pf
  want TEST-003 "$ENG_OUT" 'SWEEP-CHECK denied'
  { /usr/bin/grep -v '"pr_sweep"' "$W/events.with-sweep" || true; } > "$RIDE/docs/ai/EVENTS.jsonl"
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
  # positive controls: the PR read and the real sweep check both ran
  want TEST-004 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"
  want TEST-004 "$ENG_OUT" 'SWEEP-CHECK allowed'
  # NB-r2-2: the owner's direction is recorded BEFORE the printed merge runs, and only that:
  # one directed_merge decision in the origin ledger, nothing else in the fixture changed
  dec="$ORIGIN/docs/ai/decisions.jsonl"
  [[ -f "$dec" && "$(wc -l < "$dec" | tr -d ' ')" == 1 ]] || fail TEST-004 'preflight did not record exactly one decision'
  [[ "$(json_get "$(cat "$dec")" 'j.type')" == directed_merge ]] || fail TEST-004 'recorded decision type'
  [[ "$(json_get "$(cat "$dec")" 'j.answer')" == 'merge 433 please' ]] || fail TEST-004 'recorded decision is not the verbatim direction'
  [[ "$(json_get "$(cat "$dec")" 'j.head')" == "$HEAD_OID" ]] || fail TEST-004 'recorded decision head'
  [[ "$(json_get "$(cat "$dec")" 'j.pr')" == "$PR" ]] || fail TEST-004 'recorded decision pr'
  rm -f "$dec"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-004 'preflight changed the fixture beyond the decision record'
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-004 "second ready exited $ENG_RC"
  after="$(sha_of "$dec")"
  pf
  [[ "$(sha_of "$dec")" == "$after" && "$(wc -l < "$dec" | tr -d ' ')" == 1 ]] || fail TEST-004 'a repeat preflight duplicated the decision record'
  # the merge happens, then apply refuses (the ride is dirty): the direction is already durable
  write_pr_json MERGED "$MC"
  run_engine apply --pr "$PR" --pid 4242 --direction 'merge 433 please'
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-004 "apply on the dirty ride exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  [[ "$(wc -l < "$dec" | tr -d ' ')" == 1 && "$(sha_of "$dec")" == "$after" ]] || fail TEST-004 'a refused apply lost or duplicated the recorded direction'
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
  [[ "$ENG_RC" -eq 3 ]] || fail TEST-015 "apply with a dirty worktree exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
  want TEST-015 "$ENG_OUT" 'REFUSE worktree_dirty'
  [[ -d "$RIDE" ]] || fail TEST-015 'dirty worktree was removed'
  git -C "$ORIGIN" show-ref --verify -q "refs/heads/$BRANCH" || fail TEST-015 'branch of a dirty worktree was deleted'
  # positive cleanup once the edit is undone (rewritten from the committed blob, never a restore command)
  git -C "$RIDE" show "HEAD:README.md" > "$W/readme.ride" || fail SETUP 'ride README blob'
  run cp "$W/readme.ride" "$RIDE/README.md"
  ENGINE="$ORIGIN/.aai/scripts/merge-cleanup.mjs"
  run_engine apply --pr "$PR" --pid 4242 --json
  ENGINE="$saved_engine"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-015 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" archive-drafts)" == done ]] || fail TEST-015 'drafts were not archived'
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
  local pre keys k n ov line rows
  AMEND_WORLD=1 RIDE_SEED=seed_ride_018 open_world sign_018
  pre="$(amend_rows "$RIDE")"
  keys="$(unsigned_contract_keys "$pre")"
  [[ "$(printf '%s\n' $keys | wc -l | tr -d ' ')" == 2 ]] || fail TEST-018 "the ride holds '$keys', want two unsigned contract records (positive control)"
  # the owner's direction through preflight: it lands in the origin ledger, nobody hand-writes it
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-018 "preflight exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  want TEST-018 "$(cat "$ORIGIN/$DEC")" '"type":"directed_merge"'
  # the sweep line was the ride's only uncommitted edit; put the committed bytes back
  git -C "$RIDE" show "HEAD:docs/ai/EVENTS.jsonl" > "$W/events.ride" || fail SETUP 'ride EVENTS blob'
  run cp "$W/events.ride" "$RIDE/docs/ai/EVENTS.jsonl"
  write_pr_json MERGED "$MC"
  [[ "$(overlays "$ORIGIN/$DEC" | wc -l | tr -d ' ')" == 0 ]] || fail TEST-018 'an overlay exists before apply'
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-018 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" sign-amendments)" == done ]] || fail TEST-018 "step sign-amendments reported $(step_status "$ENG_OUT" sign-amendments), want done"
  rows="$(amend_rows "$ORIGIN")"
  for k in $keys; do
    [[ "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$k\")?.bucket")" == signed ]] || fail TEST-018 "record $k does not fold signed: $(row_of "$rows" "$k")"
  done
  # positive control: exactly two new record-addressed overlays, each citing the PR, the head and the words
  ov="$(overlays "$ORIGIN/$DEC")"
  n="$(printf '%s\n' "$ov" | /usr/bin/grep -c . || true)"
  [[ "$n" == 2 ]] || fail TEST-018 "$n overlays appended, want 2: $ov"
  while IFS= read -r line; do
    has " $keys " " $(json_get "$line" 'j.classifies_record') " || fail TEST-018 "overlay classifies a record outside the ride: $line"
    [[ "$(json_get "$line" 'j.owner_signoff')" == true ]] || fail TEST-018 "overlay is not an owner signature: $line"
    want TEST-018 "$(json_get "$line" 'j.source')" "#$PR"
    want TEST-018 "$(json_get "$line" 'j.source')" "$HEAD_OID"
    want TEST-018 "$(json_get "$line" 'j.source')" "$ANSWER"
  done <<< "$ov"
  assert_no_merge_call TEST-018
  echo 'PASS: TEST-018 the merge direction signs the ride amendments'
}

test_020_no_human_direction_signs_nothing() {
  local arm rec sha pre post rows k keys
  for arm in none orchestrator other_head other_pr human; do
    AMEND_WORLD=1 RIDE_SEED=seed_ride_018 build_world "nodir_$arm"
    case "$arm" in
      none) rec='' ;;
      orchestrator) rec="{\"v\":1,\"ts\":\"2026-10-10T03:00:00Z\",\"actor\":\"orchestrator\",\"type\":\"directed_merge\",\"ref_id\":\"foo\",\"pr\":$PR,\"by\":\"orchestrator\",\"answer\":\"$ANSWER\",\"head\":\"$HEAD_OID\"}" ;;
      other_head) rec="{\"v\":1,\"ts\":\"2026-10-10T03:00:00Z\",\"actor\":\"merge-cleanup\",\"type\":\"directed_merge\",\"ref_id\":\"foo\",\"pr\":$PR,\"by\":\"human\",\"answer\":\"$ANSWER\",\"head\":\"0123456789012345678901234567890123456789\"}" ;;
      other_pr) rec="{\"v\":1,\"ts\":\"2026-10-10T03:00:00Z\",\"actor\":\"merge-cleanup\",\"type\":\"directed_merge\",\"ref_id\":\"foo\",\"pr\":434,\"by\":\"human\",\"answer\":\"$ANSWER\",\"head\":\"$HEAD_OID\"}" ;;
      human) rec="{\"v\":1,\"ts\":\"2026-10-10T03:00:00Z\",\"actor\":\"merge-cleanup\",\"type\":\"directed_merge\",\"ref_id\":\"foo\",\"pr\":$PR,\"by\":\"human\",\"answer\":\"$ANSWER\",\"head\":\"$HEAD_OID\"}" ;;
    esac
    if [[ -n "$rec" ]]; then printf '%s\n' "$rec" >> "$ORIGIN/$DEC"; fi
    apply_stop_after_sync TEST-020
    sha="$(sha_of "$ORIGIN/$DEC")"
    pre="$(amend_rows "$ORIGIN")"
    keys="$(unsigned_contract_keys "$pre")"
    [[ "$(printf '%s\n' $keys | wc -l | tr -d ' ')" == 2 ]] || fail TEST-020 "arm $arm: the synced ledger holds '$keys', want two unsigned ride records (positive control)"
    run_engine apply --pr "$PR" --pid 4242 --json
    [[ "$ENG_RC" -eq 0 ]] || fail TEST-020 "arm $arm: apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
    rows="$(amend_rows "$ORIGIN")"
    if [[ "$arm" == human ]]; then
      # positive control: the matching human record signs both ride records
      [[ "$(step_status "$ENG_OUT" sign-amendments)" == done ]] || fail TEST-020 "human arm: step reported $(step_status "$ENG_OUT" sign-amendments), want done"
      for k in $keys; do
        [[ "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$k\")?.bucket")" == signed ]] || fail TEST-020 "human arm: record $k does not fold signed"
      done
      continue
    fi
    [[ "$(step_status "$ENG_OUT" sign-amendments)" == noop ]] || fail TEST-020 "arm $arm: step reported $(step_status "$ENG_OUT" sign-amendments), want noop"
    want TEST-020 "$(json_get "$ENG_OUT" 'j.noops')" 'noop:sign-amendments:no_human_direction'
    [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha" ]] || fail TEST-020 "arm $arm: decisions.jsonl changed after sync-base"
    [[ "$(json_get "$rows" 'JSON.stringify(j.items)')" == "$(json_get "$pre" 'JSON.stringify(j.items)')" ]] || fail TEST-020 "arm $arm: list --json rows changed"
    [[ "$(type_count "$ORIGIN/$DEC" follow_up_status)" == 0 ]] || fail TEST-020 "arm $arm: a follow_up_status line was written"
    [[ "$(overlays "$ORIGIN/$DEC" | wc -l | tr -d ' ')" == 0 ]] || fail TEST-020 "arm $arm: an overlay was written"
  done
  echo 'PASS: TEST-020 no human direction signs nothing'
}

# The ride's ledger: a measurement record, an owner-signed contract record and one unsigned
# contract record keyed on the numbered display id; plus an unsigned contract record of another ref.
seed_ride_021() {
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'measured differently' --why 'cell did not redden' --signoff none --class measurement
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$SPEC_ID" --what 'already signed' --why 'owner agreed' --signoff owner --authority 'owner said yes in chat'
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref 'ISSUE-0001' --what 'ride contract by display id' --why 'scope grew' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref 'other-ref' --what 'another ride contract' --why 'not this PR' --signoff none
  run git -C "$RIDE" add "$DEC"
}

test_021_signs_only_unsigned_contract_of_the_ride() {
  local pre rows target others k n ov
  AMEND_WORLD=1 RIDE_SEED=seed_ride_021 build_world sign_021
  pre="$(amend_rows "$RIDE")"
  target="$(json_get "$pre" 'j.items.filter(i=>i.ref_id==="ISSUE-0001").map(i=>i.record_key).join(" ")')"
  others="$(json_get "$pre" 'j.items.filter(i=>i.ref_id!=="ISSUE-0001").map(i=>i.record_key).join(" ")')"
  [[ -n "$target" && "$(printf '%s\n' $others | wc -l | tr -d ' ')" == 3 ]] || fail TEST-021 "fixture rows: target '$target', others '$others' (positive control)"
  [[ "$(json_get "$pre" 'j.items.map(i=>i.bucket).sort().join(",")')" == 'measurement,signed,unsigned-tracked,unsigned-tracked' ]] || fail TEST-021 "fixture buckets: $(json_get "$pre" 'j.items.map(i=>i.bucket)')"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-021 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" sign-amendments)" == done ]] || fail TEST-021 "step reported $(step_status "$ENG_OUT" sign-amendments), want done"
  rows="$(amend_rows "$ORIGIN")"
  for k in $others; do
    [[ "$(row_of "$rows" "$k")" == "$(row_of "$pre" "$k")" ]] || fail TEST-021 "record $k changed: before $(row_of "$pre" "$k") after $(row_of "$rows" "$k")"
  done
  [[ "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$target\")?.bucket")" == signed ]] || fail TEST-021 "the ride's unsigned contract record $target does not fold signed"
  # positive control: one new overlay per unsigned contract record of the ride, here exactly one
  ov="$(overlays "$ORIGIN/$DEC")"
  n="$(printf '%s\n' "$ov" | /usr/bin/grep -c . || true)"
  [[ "$n" == 1 ]] || fail TEST-021 "$n overlays appended, want 1: $ov"
  [[ "$(json_get "$ov" 'j.classifies_record')" == "$target" ]] || fail TEST-021 "the overlay classifies $(json_get "$ov" 'j.classifies_record'), want $target"
  echo 'PASS: TEST-021 only the unsigned contract records of the ride are signed'
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
  local pre fu rows control_proj control_fu sha n rc dup report
  AMEND_WORLD=1 RIDE_SEED=seed_ride_022 build_world sign_022
  fu="$(fu_rows "$RIDE")"
  [[ "$(amend_trackers "$fu")" == 'fu-amend-spec-bar:open fu-amend-spec-foo:open' ]] || fail TEST-022 "fixture trackers: '$(amend_trackers "$fu")' (positive control)"
  pre="$(amend_rows "$RIDE")"
  [[ "$(unsigned_contract_keys "$pre" | wc -w | tr -d ' ')" == 4 ]] || fail TEST-022 'fixture: want four unsigned contract records (positive control)'
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-022 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" sign-amendments)" == done ]] || fail TEST-022 "step reported $(step_status "$ENG_OUT" sign-amendments), want done"
  want TEST-022 "$(json_get "$ENG_OUT" 'j.steps.find(s=>s.id==="sign-amendments").detail')" '3 signed, 1 closed'
  [[ "$(json_get "$ENG_OUT" 'j.signed.length')" == 3 ]] || fail TEST-022 "report lists $(json_get "$ENG_OUT" 'j.signed.length') signed keys, want 3"
  [[ "$(json_get "$ENG_OUT" 'j.closed.join(" ")')" == fu-amend-spec-foo ]] || fail TEST-022 "report closed: $(json_get "$ENG_OUT" 'j.closed')"
  report="$(cat "$ORIGIN/$(json_get "$ENG_OUT" 'j.report')")" || fail TEST-022 'saved report unreadable'
  want TEST-022 "$report" '## Trackers closed'
  want TEST-022 "$report" '- fu-amend-spec-foo'
  # seam S2: through the real follow-ups and spec-amend folds
  fu="$(fu_rows "$ORIGIN")"
  [[ "$(fu_status "$fu" fu-amend-spec-foo)" == done ]] || fail TEST-022 "tracker A is $(fu_status "$fu" fu-amend-spec-foo), want done"
  [[ "$(fu_status "$fu" fu-amend-spec-bar)" == open ]] || fail TEST-022 "tracker B is $(fu_status "$fu" fu-amend-spec-bar), want open (one unsigned contract record left)"
  rows="$(amend_rows "$ORIGIN")"
  [[ "$(json_get "$rows" 'j.items.find(i=>i.ref_id==="bar").bucket')" == unsigned-tracked ]] || fail TEST-022 "the unmerged record folds $(json_get "$rows" 'j.items.find(i=>i.ref_id==="bar").bucket'), want unsigned-tracked"
  [[ "$(strict_rc "$ORIGIN")" == 0 ]] || fail TEST-022 'spec-amend list --strict is not 0 after apply'
  control_proj="$(amend_projection "$rows")"
  control_fu="$(amend_trackers "$fu")"
  # a second apply signs nothing, closes nothing, appends nothing
  sha="$(sha_of "$ORIGIN/$DEC")"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-022 "second apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha" ]] || fail TEST-022 'second apply appended to decisions.jsonl'
  [[ "$(step_status "$ENG_OUT" sign-amendments)" == noop ]] || fail TEST-022 "second apply: step reported $(step_status "$ENG_OUT" sign-amendments), want noop"
  want TEST-022 "$(json_get "$ENG_OUT" 'j.noops')" 'noop:sign-amendments:nothing_to_sign'
  [[ "$(json_get "$ENG_OUT" 'j.signed.length + j.closed.length')" == 0 ]] || fail TEST-022 'second apply reports signed or closed work'

  # killed after its first classify: the re-run ends where the uninterrupted run ended
  AMEND_WORLD=1 RIDE_SEED=seed_ride_022 build_world sign_022_crash
  rc=0
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" AAI_MERGE_CLEANUP_TEST_SEAMS=1 AAI_MERGE_CLEANUP_CRASH_AT=sign-after-classify node "$ENGINE" apply --pr "$PR" --pid 4242 --json --direction "$ANSWER" >"$W/engine.out" 2>"$W/engine.err" ) || rc=$?
  [[ "$rc" -eq 137 ]] || fail TEST-022 "crash at sign-after-classify exited $rc, want 137 ($(cat "$W/engine.out") $(cat "$W/engine.err"))"
  [[ "$(overlays "$ORIGIN/$DEC" | wc -l | tr -d ' ')" == 1 ]] || fail TEST-022 'crash: want exactly one overlay before the re-run (positive control)'
  [[ "$(fu_status "$(fu_rows "$ORIGIN")" fu-amend-spec-foo)" == open ]] || fail TEST-022 'crash: tracker A already closed before the re-run (positive control)'
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-022 "re-run after the crash exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(amend_projection "$(amend_rows "$ORIGIN")")" == "$control_proj" ]] || fail TEST-022 "re-run fold differs from the uninterrupted run: $(amend_projection "$(amend_rows "$ORIGIN")")"
  [[ "$(amend_trackers "$(fu_rows "$ORIGIN")")" == "$control_fu" ]] || fail TEST-022 "re-run trackers '$(amend_trackers "$(fu_rows "$ORIGIN")")', want '$control_fu'"
  n="$(overlays "$ORIGIN/$DEC" | wc -l | tr -d ' ')"
  [[ "$n" == 3 ]] || fail TEST-022 "re-run left $n overlays, want 3"
  dup="$(overlays "$ORIGIN/$DEC" | node -e 'const k=require("fs").readFileSync(0,"utf8").split("\n").filter(Boolean).map(l=>JSON.parse(l).classifies_record);console.log(k.length-new Set(k).size)')"
  [[ "$dup" == 0 ]] || fail TEST-022 "re-run left $dup duplicate overlay(s)"
  [[ "$(strict_rc "$ORIGIN")" == 0 ]] || fail TEST-022 'spec-amend list --strict is not 0 after the re-run'
  assert_no_merge_call TEST-022
  echo 'PASS: TEST-022 trackers close, a second run is a no-op, a killed run resumes'
}

# The ride: two unsigned contract records and one measurement record.
seed_ride_023() {
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'preflight contract a' --why 'scope grew a' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$SPEC_ID" --what 'preflight contract b' --why 'scope grew b' --signoff none
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'preflight measurement' --why 'cell did not redden' --signoff none --class measurement
  run git -C "$RIDE" add "$DEC"
}

test_023_preflight_lists_signs_on_merge() {
  local pre keys k lines merge_at sign_at ride_sha
  AMEND_WORLD=1 RIDE_SEED=seed_ride_023 open_world pf_sign_023
  pre="$(amend_rows "$RIDE")"
  keys="$(unsigned_contract_keys "$pre")"
  [[ "$(printf '%s\n' $keys | wc -l | tr -d ' ')" == 2 ]] || fail TEST-023 "fixture: unsigned contract keys '$keys', want two (positive control)"
  [[ "$(json_get "$pre" 'j.items.filter(i=>i.bucket==="measurement").length')" == 1 ]] || fail TEST-023 'fixture: want one measurement record (positive control)'
  ride_sha="$(sha_of "$RIDE/$DEC")"
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-023 "preflight exited $ENG_RC, want 10 (out: $ENG_OUT $ENG_ERR)"
  lines="$(printf '%s\n' "$ENG_OUT" | { /usr/bin/grep '^signs on merge: ' || true; })"
  [[ "$(printf '%s\n' "$lines" | /usr/bin/grep -c . || true)" == 2 ]] || fail TEST-023 "want two signs on merge lines: $ENG_OUT"
  for k in $keys; do
    want TEST-023 "$lines" "signs on merge: $k $(json_get "$pre" "j.items.find(i=>i.record_key===\"$k\").ref_id") $(json_get "$pre" "j.items.find(i=>i.record_key===\"$k\").what")"
  done
  unwanted TEST-023 "$lines" 'preflight measurement'
  merge_at="$(printf '%s\n' "$ENG_OUT" | /usr/bin/grep -n 'gh pr merge' | cut -d: -f1)"
  sign_at="$(printf '%s\n' "$ENG_OUT" | /usr/bin/grep -n '^signs on merge: ' | tail -n 1 | cut -d: -f1)"
  [[ -n "$merge_at" && -n "$sign_at" && "$sign_at" -lt "$merge_at" ]] || fail TEST-023 "the signs on merge lines do not precede the merge command: $ENG_OUT"
  pf --json
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-023 "json preflight exited $ENG_RC"
  [[ "$(json_get "$ENG_OUT" 'j.signs_on_merge.length')" == 2 ]] || fail TEST-023 "json signs_on_merge: $(json_get "$ENG_OUT" 'j.signs_on_merge')"
  [[ "$(json_get "$ENG_OUT" 'j.signs_on_merge.map(s=>s.record_key).sort().join(" ")')" == "$(printf '%s\n' $keys | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" ]] || fail TEST-023 "json record keys differ from list --json: $(json_get "$ENG_OUT" 'j.signs_on_merge')"
  # preflight signs nothing: no overlay in either ledger, the ride ledger bytes unchanged
  [[ "$(sha_of "$RIDE/$DEC")" == "$ride_sha" ]] || fail TEST-023 'preflight changed the ride ledger'
  [[ "$(overlays "$ORIGIN/$DEC" | wc -l | tr -d ' ')" == 0 ]] || fail TEST-023 'preflight appended an overlay to the origin ledger'
  # a ride with nothing to sign says so
  open_world pf_sign_023_none
  pf
  [[ "$ENG_RC" -eq 10 ]] || fail TEST-023 "none arm: preflight exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  want TEST-023 "$ENG_OUT" 'signs on merge: none'
  pf --json
  [[ "$(json_get "$ENG_OUT" 'j.signs_on_merge.length')" == 0 ]] || fail TEST-023 'none arm: json signs_on_merge is not empty'
  assert_no_merge_call TEST-023
  echo 'PASS: TEST-023 preflight lists what the merge direction signs'
}

seed_ride_019() {
  amend_add "$RIDE" --spec "$NUM_SPEC" --ref "$ISSUE_ID" --what 'downstream contract' --why 'scope grew' --signoff none
  run git -C "$RIDE" add "$DEC"
}

test_019_downstream_signs() {
  local saved_engine="$ENGINE" pre key rows
  AMEND_WORLD=1 DOWNSTREAM=1 RIDE_SEED=seed_ride_019 build_world "down stream sign"
  [[ -f "$ORIGIN/.aai/scripts/spec-amend.mjs" && -f "$ORIGIN/.aai/scripts/follow-ups.mjs" ]] || fail TEST-019 'core install omitted spec-amend or follow-ups'
  pre="$(amend_rows "$RIDE")"
  key="$(unsigned_contract_keys "$pre")"
  [[ -n "$key" && "$key" != *' '* ]] || fail TEST-019 "fixture: want one unsigned contract record, got '$key' (positive control)"
  ENGINE="$ORIGIN/.aai/scripts/merge-cleanup.mjs"
  run_engine apply --pr "$PR" --pid 4242 --json --direction "$ANSWER"
  ENGINE="$saved_engine"
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-019 "installed apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" sign-amendments)" == done ]] || fail TEST-019 "step reported $(step_status "$ENG_OUT" sign-amendments), want done"
  # read back through the INSTALLED spec-amend
  ( cd "$ORIGIN" && env -u AAI_ROLE node "$ORIGIN/.aai/scripts/spec-amend.mjs" list --json --ledger "$ORIGIN/$DEC" ) > "$W/installed-rows.json" || fail TEST-019 'installed spec-amend list --json failed'
  rows="$(cat "$W/installed-rows.json")"
  [[ "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$key\")?.bucket")" == signed ]] || fail TEST-019 "record $key does not fold signed: $(row_of "$rows" "$key")"
  [[ "$(fu_status "$(fu_rows "$ORIGIN")" fu-amend-spec-foo)" == done ]] || fail TEST-019 'the installed engine did not close the tracker'
  [[ "$(git -C "$ORIGIN" ls-files -- .aai | wc -l | tr -d ' ')" == 0 ]] || fail TEST-019 'apply left a tracked path under .aai'
  assert_no_merge_call TEST-019
  echo 'PASS: TEST-019 the installed downstream engine signs the ride amendments'
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
  local pre rows fu sha key k n ov line x_keys y_key t3_key meas_key
  EXTRA_OTHER=1 AMEND_WORLD=1 RIDE_SEED=seed_ride_025 build_world backlog_025
  # a lane merge: apply without the owner's direction signs nothing (the backlog this command closes)
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-025 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(step_status "$ENG_OUT" sign-amendments)" == noop ]] || fail TEST-025 'fixture: the directionless apply signed (positive control)'
  {
    printf '{"v":1,"ts":"%s","actor":"orchestrator","type":"hitl_decision","ref_id":"backlog","by":"human","question":"Sign the merged backlog?","answer":"%s","decision":"sign it"}\n' "$AUTH_TS" "$AUTH_ANSWER"
    printf '{"v":1,"ts":"2026-10-10T05:00:01Z","actor":"orchestrator","type":"hitl_decision","ref_id":"backlog","by":"orchestrator","question":"q","answer":"yes","decision":"d"}\n'
    printf '{"v":1,"ts":"2026-10-10T05:00:02Z","actor":"orchestrator","type":"hitl_decision","ref_id":"backlog","by":"human","question":"q","answer":"  ","decision":"d"}\n'
    printf '{"v":1,"ts":"2026-10-10T05:00:03Z","actor":"orchestrator","type":"note","ref_id":"backlog","by":"human","answer":"yes"}\n'
    # the owner's words about ONE pull request: a directed_merge never authorizes the backlog (PFA-4)
    printf '{"v":1,"ts":"2026-10-10T05:00:04Z","actor":"merge-cleanup","type":"directed_merge","ref_id":"pr-%s","by":"human","pr":%s,"head":"%s","answer":"merge PR %s"}\n' "$PR" "$PR" "$HEAD_OID" "$PR"
  } >> "$ORIGIN/$DEC"
  pre="$(amend_rows "$ORIGIN")"
  [[ "$(unsigned_contract_keys "$pre" | wc -w | tr -d ' ')" == 5 ]] || fail TEST-025 "fixture: want five unsigned contract records, got '$(unsigned_contract_keys "$pre")' (positive control)"
  x_keys="$(json_get "$pre" 'j.items.filter(i=>/^backlog x (one|two|three)$/.test(i.what)).map(i=>i.record_key).sort().join(" ")')"
  y_key="$(json_get "$pre" 'j.items.find(i=>i.what==="backlog y one").record_key')"
  t3_key="$(json_get "$pre" 'j.items.find(i=>i.what==="backlog x excluded").record_key')"
  meas_key="$(json_get "$pre" 'j.items.find(i=>i.what==="backlog x measured").record_key')"
  [[ "$(printf '%s\n' $x_keys | wc -l | tr -d ' ')" == 3 ]] || fail TEST-025 "fixture: X keys '$x_keys'"
  fu="$(fu_rows "$ORIGIN")"
  [[ "$(amend_trackers "$fu")" == 'fu-amend-spec-t1:open fu-amend-spec-t2:open fu-amend-spec-t3:open' ]] || fail TEST-025 "fixture trackers: '$(amend_trackers "$fu")' (positive control)"
  sha="$(sha_of "$ORIGIN/$DEC")"
  # refusals: an orchestrator record, a missing ts, an empty answer, a non-decision type, a
  # by=human directed_merge with an answer (one PR's words); nothing written
  for k in 2026-10-10T05:00:01Z 2026-01-01T00:00:00Z 2026-10-10T05:00:02Z 2026-10-10T05:00:03Z 2026-10-10T05:00:04Z; do
    sm --authority-ts "$k"
    [[ "$ENG_RC" -eq 3 ]] || fail TEST-025 "authority $k exited $ENG_RC, want 3 (out: $ENG_OUT $ENG_ERR)"
    want TEST-025 "$ENG_OUT" 'REFUSE no_owner_decision'
    want TEST-025 "$ENG_OUT" "$DEC"
    [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha" ]] || fail TEST-025 "authority $k changed the ledger"
  done
  # positive control: the directed_merge arm's record is in the ledger, by=human, with an answer
  [[ "$(/usr/bin/grep -c '"ts":"2026-10-10T05:00:04Z","actor":"merge-cleanup","type":"directed_merge".*"by":"human".*"answer":"merge PR' "$ORIGIN/$DEC")" == 1 ]] || fail TEST-025 'fixture: the by=human directed_merge record is missing (positive control)'

  # sign-merged takes no --pr
  sm --authority-ts "$AUTH_TS" --pr "$PR"
  [[ "$ENG_RC" -eq 2 ]] || fail TEST-025 "--pr exited $ENG_RC, want 2"
  # --dry-run: the plan, nothing written
  sm --authority-ts "$AUTH_TS" --dry-run --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-025 "dry run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha" ]] || fail TEST-025 'the dry run changed the ledger'
  [[ "$(json_get "$ENG_OUT" 'j.to_sign.slice().sort().join(" ")')" == "$(printf '%s\n' $x_keys | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" ]] || fail TEST-025 "dry run to_sign: $(json_get "$ENG_OUT" 'j.to_sign')"
  [[ "$(json_get "$ENG_OUT" 'j.to_close.join(" ")')" == fu-amend-spec-t1 ]] || fail TEST-025 "dry run to_close: $(json_get "$ENG_OUT" 'j.to_close')"
  [[ "$(json_get "$ENG_OUT" 'j.plan.find(p=>p.tracker==="fu-amend-spec-t2").reason')" == 'unmerged:other-item' ]] || fail TEST-025 "dry run T2: $(json_get "$ENG_OUT" 'j.plan')"
  [[ "$(json_get "$ENG_OUT" 'j.plan.find(p=>p.tracker==="fu-amend-spec-t3").reason')" == excluded ]] || fail TEST-025 "dry run T3: $(json_get "$ENG_OUT" 'j.plan')"
  [[ "$(json_get "$ENG_OUT" 'j.signed.length + j.closed.length')" == 0 ]] || fail TEST-025 'the dry run reports signed or closed work'
  sm --authority-ts "$AUTH_TS" --dry-run
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-025 "text dry run exited $ENG_RC"
  want TEST-025 "$ENG_OUT" 'fu-amend-spec-t2: stays open (unmerged:other-item)'
  want TEST-025 "$ENG_OUT" 'fu-amend-spec-t3: stays open (excluded)'
  want TEST-025 "$ENG_OUT" 'fu-amend-spec-t1: close'
  [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha" ]] || fail TEST-025 'the text dry run changed the ledger'
  # the real run
  sm --authority-ts "$AUTH_TS" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-025 "sign-merged exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(json_get "$ENG_OUT" 'j.signed.length')" == 3 ]] || fail TEST-025 "reported $(json_get "$ENG_OUT" 'j.signed.length') signed, want 3"
  rows="$(amend_rows "$ORIGIN")"
  for k in $x_keys; do
    [[ "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$k\")?.bucket")" == signed ]] || fail TEST-025 "X record $k does not fold signed: $(row_of "$rows" "$k")"
  done
  for k in "$y_key" "$t3_key" "$meas_key"; do
    [[ "$(row_of "$rows" "$k")" == "$(row_of "$pre" "$k")" ]] || fail TEST-025 "record $k changed: before $(row_of "$pre" "$k") after $(row_of "$rows" "$k")"
  done
  # positive control: three overlays, each citing the authority, the answer, the PR and the squash commit
  ov="$(overlays "$ORIGIN/$DEC")"
  n="$(printf '%s\n' "$ov" | /usr/bin/grep -c . || true)"
  [[ "$n" == 3 ]] || fail TEST-025 "$n overlays appended, want 3: $ov"
  while IFS= read -r line; do
    has " $x_keys " " $(json_get "$line" 'j.classifies_record') " || fail TEST-025 "overlay classifies a record outside ride X: $line"
    [[ "$(json_get "$line" 'j.owner_signoff')" == true ]] || fail TEST-025 "overlay is not an owner signature: $line"
    want TEST-025 "$(json_get "$line" 'j.source')" "$AUTH_TS"
    want TEST-025 "$(json_get "$line" 'j.source')" "answer=\"$AUTH_ANSWER\""
    want TEST-025 "$(json_get "$line" 'j.source')" "PR #$PR at $MC"
  done <<< "$ov"
  fu="$(fu_rows "$ORIGIN")"
  [[ "$(amend_trackers "$fu")" == 'fu-amend-spec-t1:done fu-amend-spec-t2:open fu-amend-spec-t3:open' ]] || fail TEST-025 "trackers after: '$(amend_trackers "$fu")'"
  [[ "$(strict_rc "$ORIGIN")" == 0 ]] || fail TEST-025 'spec-amend list --strict is not 0 after sign-merged'
  # a second run signs nothing and appends nothing
  sha="$(sha_of "$ORIGIN/$DEC")"
  sm --authority-ts "$AUTH_TS" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-025 "second run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha" ]] || fail TEST-025 'the second run appended to the ledger'
  # A4 (code review r2 NB-1): an `unclassified` contract record (no owner_signoff field) of the
  # MERGED ride X is never signed by sign-merged either, exactly as apply skips it; its tracker
  # stays open and names the record. Mutation evidence: dropping the filter signs it here.
  printf -- '---\nid: spec-t4\ntype: spec\nnumber: null\nstatus: implementing\nlinks:\n  requirement: t4\n  pr: []\n  commits: []\n---\n\n# Spec t4\n' > "$W/t4-spec.md"
  amend_add "$ORIGIN" --spec "$W/t4-spec.md" --ref "$ISSUE_ID" --what 'backlog x unclassified' --why 'scope grew x5' --signoff none
  node -e 'const fs=require("fs");const f=process.argv[1];const out=fs.readFileSync(f,"utf8").split("\n").map(l=>{let r;try{r=JSON.parse(l)}catch{return l}if(r.type!=="spec_amendment"||r.what!=="backlog x unclassified")return l;delete r.owner_signoff;return JSON.stringify(r)});fs.writeFileSync(f,out.join("\n"))' "$ORIGIN/$DEC" || fail SETUP 'strip owner_signoff'
  rows="$(amend_rows "$ORIGIN")"
  key="$(json_get "$rows" 'j.items.find(i=>i.what==="backlog x unclassified")?.record_key')"
  [[ -n "$key" && "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$key\").bucket")" == unclassified ]] || fail TEST-025 "fixture: the unclassified record does not fold unclassified: $(row_of "$rows" "$key") (positive control)"
  [[ "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$key\").amendment_class")" == contract ]] || fail TEST-025 'fixture: the unclassified record is not a contract record (positive control)'
  [[ "$(json_get "$rows" "j.items.find(i=>i.record_key===\"$key\").tracked_by")" == fu-amend-spec-t4 ]] || fail TEST-025 "fixture: the unclassified record is not tracked by fu-amend-spec-t4: $(row_of "$rows" "$key") (positive control)"
  [[ "$(fu_status "$(fu_rows "$ORIGIN")" fu-amend-spec-t4)" == open ]] || fail TEST-025 'fixture: fu-amend-spec-t4 is not open (positive control)'
  sha="$(sha_of "$ORIGIN/$DEC")"
  sm --authority-ts "$AUTH_TS" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-025 "unclassified run exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(json_get "$ENG_OUT" 'j.signed.length + j.closed.length + j.to_sign.length')" == 0 ]] || fail TEST-025 "the unclassified record was signed or its tracker closed: $ENG_OUT"
  [[ "$(json_get "$ENG_OUT" 'j.plan.find(p=>p.tracker==="fu-amend-spec-t4").reason')" == "unclassified:$key" ]] || fail TEST-025 "T4 plan: $(json_get "$ENG_OUT" 'j.plan')"
  [[ "$(sha_of "$ORIGIN/$DEC")" == "$sha" ]] || fail TEST-025 'the unclassified run appended to the ledger'
  [[ "$(fu_status "$(fu_rows "$ORIGIN")" fu-amend-spec-t4)" == open ]] || fail TEST-025 'fu-amend-spec-t4 was closed over an unclassified record'
  assert_no_merge_call TEST-025
  echo 'PASS: TEST-025 sign-merged signs the merged backlog on the owner decision'
}

# TEST-024: the canon says the owner's merge direction signs the ride's contract amendments,
# no prompt still asks for owed sign-offs, and the diet ledger credits the bytes.
test_024_canon_merge_direction_signs() {
  local f text step6 credit n=0
  for f in .aai/ROLE_COMMON.md .aai/SKILL_MERGE.prompt.md .aai/SKILL_SHIP.prompt.md .aai/SKILL_PR.prompt.md .aai/system/AUTONOMOUS_LOOP.md; do
    [[ -s "$ROOT/$f" ]] || fail TEST-024 "canon file missing: $f"
    text="$(cat "$ROOT/$f")"
    want TEST-024 "$text" 'merge direction signs'
    unwanted TEST-024 "$text" 'owed sign-offs'
    n=$((n + 1))
  done
  [[ "$n" == 5 ]] || fail TEST-024 "read $n canon files, want 5 (positive control)"
  # SKILL_SHIP step 6 (the merge checkpoint) names what the merge signs
  step6="$(awk '/^6\. MERGE CHECKPOINT/ { f = 1 } f && /^7\. / { exit } f' "$ROOT/.aai/SKILL_SHIP.prompt.md")"
  [[ -n "$step6" ]] || fail TEST-024 'SKILL_SHIP step 6 not found (positive control)'
  want TEST-024 "$step6" 'signs on merge:'
  credit="$(/usr/bin/grep -F 'JUSTIFIED_ADDITIONS+=( "' "$ROOT/tests/skills/lib/prompt-diet-ledger.sh" | sed -n 's/^JUSTIFIED_ADDITIONS+=( "\([0-9][0-9]*\) merge-direction-signs-amendments .*/\1/p' | awk 'NR == 1')"
  [[ -n "$credit" && "$credit" -gt 0 ]] || fail TEST-024 'the prompt-diet ledger carries no positive entry keyed merge-direction-signs-amendments'
  echo 'PASS: TEST-024 the canon says the merge direction signs'
}

# TEST-026 (Spec-AC-08): the merged-ride backlog is signed on the LIVE ledger. RED until the
# orchestrator runs V3 (the owner decision record, then sign-merged); read only through the
# real spec-amend and follow-ups folds, never from a report. It pins what V3 WROTE (the
# overlays citing the authority ts, the closes after it), never the moving live fold, so a
# later /aai-merge that signs or closes more stays green (PFA-4).
BACKLOG_BASE=da1abba57d79c4f539ba075e6cfc90831457d8f7
BACKLOG_ANSWER='Merge = podpis + backlog (Recommended)'
BACKLOG_KEPT_OPEN='fu-amend-worktree-lacks-vendored-04c4f1 fu-amend-update-installs-ref-guar-f8caa1'
BACKLOG_UNMERGED_REF='routing-tables-have-an-owner-and-a-seam'

test_026_backlog_signed_on_live_ledger() {
  local d="$SCRATCH/live_026" live="$ROOT/docs/ai/decisions.jsonl" verdict rc=0 base_ref
  run mkdir -p "$d"
  [[ -s "$live" ]] || fail TEST-026 "the live ledger is missing: $live"
  git -C "$ROOT" cat-file -e "$BACKLOG_BASE^{commit}" 2>/dev/null || fail TEST-026 "base commit $BACKLOG_BASE is not in this clone (full history needed)"
  git -C "$ROOT" show "$BACKLOG_BASE:docs/ai/decisions.jsonl" > "$d/base.jsonl" || fail TEST-026 'cannot read the base ledger blob'
  ( cd "$ROOT" && env -u AAI_ROLE node "$SPEC_AMEND" list --json --ledger "$d/base.jsonl" ) > "$d/base-rows.json" || fail TEST-026 'spec-amend list --json over the base ledger failed'
  ( cd "$ROOT" && env -u AAI_ROLE node "$FOLLOW_UPS" list --status all --json --ledger "$d/base.jsonl" ) > "$d/base-fu.json" || fail TEST-026 'follow-ups list --json over the base ledger failed'
  ( cd "$ROOT" && env -u AAI_ROLE node "$SPEC_AMEND" list --json --ledger "$live" ) > "$d/live-rows.json" || fail TEST-026 'spec-amend list --json over the live ledger failed'
  ( cd "$ROOT" && env -u AAI_ROLE node "$FOLLOW_UPS" list --status all --json --ledger "$live" ) > "$d/live-fu.json" || fail TEST-026 'follow-ups list --json over the live ledger failed'
  base_ref=HEAD
  if git -C "$ROOT" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; then base_ref=refs/remotes/origin/main; fi
  ( cd "$ROOT" && node -e '
const fs = require("fs");
const { spawnSync } = require("child_process");
const [dir, live, answer, keptOpen, unmergedRef, baseRef] = process.argv.slice(1);
const rd = (f) => JSON.parse(fs.readFileSync(`${dir}/${f}`, "utf8")).items;
const baseRows = rd("base-rows.json"), baseFu = rd("base-fu.json"), liveRows = rd("live-rows.json"), liveFu = rd("live-fu.json");
const lines = fs.readFileSync(live, "utf8").split("\n").filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
const out = [];
const auth = lines.filter((r) => r.type === "hitl_decision" && r.by === "human" && r.ref_id === "merge-direction-signs-amendments" && r.answer === answer);
if (auth.length !== 1) { console.log(`FAIL want one owner decision record (hitl_decision by=human ref merge-direction-signs-amendments answer verbatim), found ${auth.length}`); process.exit(0); }
const ts = auth[0].ts;
const kept = new Set(keptOpen.split(" "));
const authAt = lines.indexOf(auth[0]);
const onBase = new Map();
const isOnBase = (c) => {
  if (!onBase.has(c)) onBase.set(c, spawnSync("git", ["merge-base", "--is-ancestor", c, baseRef]).status === 0);
  return onBase.get(c);
};
// Only what V3 wrote is pinned: later merges may sign or close more (the kept trackers,
// records of rides merged after da1abba5) without turning this test red.
const openAtBase = baseFu.filter((i) => i.status === "open" && i.id.startsWith("fu-amend-")).map((i) => i.id);
const toClose = openAtBase.filter((id) => !kept.has(id));
if (toClose.length !== 34) out.push(`base fold names ${toClose.length} trackers to close, want 34`);
const closes = lines.slice(authAt + 1).filter((r) => r.type === "follow_up_status" && r.actor === "merge-cleanup" && r.status === "done");
for (const id of toClose) {
  const c = closes.filter((r) => r.id === id);
  if (c.length === 0) out.push(`tracker ${id}: no merge-cleanup close after the authority record`);
  else if (!c.some((r) => /^[0-9a-f]{40}$/.test(String(r.source ?? "")) && isOnBase(r.source))) out.push(`tracker ${id}: no close cites a commit on ${baseRef}`);
}
const targets = baseRows.filter((i) => i.amendment_class === "contract" && i.bucket !== "signed"
  && i.ref_id !== unmergedRef && i.tracked_by !== "fu-amend-worktree-lacks-vendored-04c4f1").map((i) => i.record_key);
const targetSet = new Set(targets);
if (targets.length !== 202) out.push(`base fold names ${targets.length} records to sign, want 202`);
const byKey = new Map(liveRows.map((i) => [i.record_key, i]));
// the overlays V3 wrote: owner signatures whose source cites the authority ts
const mine = lines.filter((r) => r.type === "spec_amendment_classification" && r.classifies_record
  && r.owner_signoff === true && String(r.source ?? "").includes(`owner decision ${ts} `));
const signedKeys = new Set(mine.map((r) => r.classifies_record));
if (mine.length !== 202) out.push(`${mine.length} overlays cite the authority ts, want 202`);
for (const k of signedKeys) if (!targetSet.has(k)) out.push(`an authority overlay signs ${k}, which is not one of the 202 merged-ride records`);
for (const k of targets) {
  const ov = mine.filter((r) => r.classifies_record === k);
  if (ov.length === 0) { out.push(`record ${k} has no owner overlay citing the authority ts ${ts}`); continue; }
  const cited = ov.flatMap((r) => String(r.source).match(/\b[0-9a-f]{40}\b/g) ?? []);
  if (!cited.some(isOnBase)) out.push(`record ${k}: no cited commit is on ${baseRef}`);
  if (byKey.get(k)?.bucket !== "signed") out.push(`record ${k} folds ${byKey.get(k)?.bucket}, want signed`);
}
if (liveRows.length <= 380) out.push(`only ${liveRows.length} items read, want over 380 (positive control)`);
if (openAtBase.length <= 30) out.push(`only ${openAtBase.length} trackers checked, want over 30 (positive control)`);
console.log(out.length ? `FAIL ${out.length} finding(s): ${out.slice(0, 5).join("; ")}` : `OK ${targets.length} signed, ${openAtBase.length} trackers, ${liveRows.length} items`);
' "$d" "$live" "$BACKLOG_ANSWER" "$BACKLOG_KEPT_OPEN" "$BACKLOG_UNMERGED_REF" "$base_ref" ) > "$d/verdict.txt" || fail TEST-026 'the live-ledger check did not run'
  verdict="$(cat "$d/verdict.txt")"
  [[ "$verdict" == OK* ]] || fail TEST-026 "$verdict"
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
  want TEST-002 "$(cat "$GHD/gh-argv.log")" "pr view $PR --json"   # positive control: the engine really ran
  # the block forwards the owner's verbatim direction, which lands in the decision ledger
  want TEST-002 "$(cat "$ORIGIN/docs/ai/decisions.jsonl")" '"answer":"merge 433 now, owner said so"'
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
  want TEST-016 "$out" 'Passed: 2'
  echo 'PASS: TEST-016 PowerShell parity (local pwsh)'
}

case "$SELECTED" in
  '') test_005_apply_readback_gate; test_006_superseded_drafts; test_007_retained_and_decisions
     test_008_base_sync_preserves_work; test_009_base_sync_refusals; test_010_worktree_and_branch_cleanup; test_011_worktree_refusals
     test_012_state_index_report; test_013_second_apply_is_noop; test_014_interrupted_run_converges
     test_003_preflight_refusals; test_004_preflight_ready; test_015_downstream_layout
     test_018_direction_signs_ride_amendments; test_020_no_human_direction_signs_nothing; test_021_signs_only_unsigned_contract_of_the_ride
     test_022_trackers_close_idempotent_resumable; test_023_preflight_lists_signs_on_merge; test_019_downstream_signs
     test_025_sign_merged_backlog; test_024_canon_merge_direction_signs; test_026_backlog_signed_on_live_ledger
     test_001_wrappers_and_pointers; test_002_prompt_block_runs_cleanup; test_017_companion_wiring ;;
  TEST-001|test_001_wrappers_and_pointers) test_001_wrappers_and_pointers ;;
  TEST-002|test_002_prompt_block_runs_cleanup) test_002_prompt_block_runs_cleanup ;;
  TEST-016|test_016_powershell_parity) test_016_powershell_parity ;;
  TEST-017|test_017_companion_wiring) test_017_companion_wiring ;;
  TEST-003|test_003_preflight_refusals) test_003_preflight_refusals ;;
  TEST-004|test_004_preflight_ready) test_004_preflight_ready ;;
  TEST-015|test_015_downstream_layout) test_015_downstream_layout ;;
  TEST-005|test_005_apply_readback_gate) test_005_apply_readback_gate ;;
  TEST-006|test_006_superseded_drafts) test_006_superseded_drafts ;;
  TEST-007|test_007_retained_and_decisions) test_007_retained_and_decisions ;;
  TEST-008|test_008_base_sync_preserves_work) test_008_base_sync_preserves_work ;;
  TEST-009|test_009_base_sync_refusals) test_009_base_sync_refusals ;;
  TEST-010|test_010_worktree_and_branch_cleanup) test_010_worktree_and_branch_cleanup ;;
  TEST-011|test_011_worktree_refusals) test_011_worktree_refusals ;;
  TEST-012|test_012_state_index_report) test_012_state_index_report ;;
  TEST-013|test_013_second_apply_is_noop) test_013_second_apply_is_noop ;;
  TEST-014|test_014_interrupted_run_converges) test_014_interrupted_run_converges ;;
  TEST-018|test_018_direction_signs_ride_amendments) test_018_direction_signs_ride_amendments ;;
  TEST-020|test_020_no_human_direction_signs_nothing) test_020_no_human_direction_signs_nothing ;;
  TEST-021|test_021_signs_only_unsigned_contract_of_the_ride) test_021_signs_only_unsigned_contract_of_the_ride ;;
  TEST-022|test_022_trackers_close_idempotent_resumable) test_022_trackers_close_idempotent_resumable ;;
  TEST-023|test_023_preflight_lists_signs_on_merge) test_023_preflight_lists_signs_on_merge ;;
  TEST-019|test_019_downstream_signs) test_019_downstream_signs ;;
  TEST-025|test_025_sign_merged_backlog) test_025_sign_merged_backlog ;;
  TEST-024|test_024_canon_merge_direction_signs) test_024_canon_merge_direction_signs ;;
  TEST-026|test_026_backlog_signed_on_live_ledger) test_026_backlog_signed_on_live_ledger ;;
  *) fail SELECTOR "unknown test $SELECTED" ;;
esac
