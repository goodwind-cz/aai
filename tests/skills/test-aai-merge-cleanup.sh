#!/usr/bin/env bash
# /aai-merge engine tests (spec-directed-merge-and-post-merge-cleanup).
# Every fixture lives under ONE private absolute scratch root; every git call
# in a fixture carries its own identity; gh is a deny-by-default stub.
# B1: TEST-005 (apply read-back gate), TEST-006/007 (drafts).
# B2: TEST-008/009 (base sync), TEST-010/011 (worktree and branch cleanup).
# B3: TEST-012 (focus, index, report), TEST-013/014 (idempotence and resume).
# B4a: TEST-003/004 (open-PR preflight), TEST-015 (downstream installed layout).
# B4b: TEST-001/002 (prompt, wrappers, executed block), TEST-017 (companion wiring).
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
ALL_STEPS='resolve plan archive-runtime archive-drafts sync-base state index-audit remove-worktree delete-branch report'

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
  [[ "$(json_get "$second" 'j.noops.length')" == 8 ]] || fail TEST-013 "second run lists $(json_get "$second" 'j.noops.length') no-ops, want 8"
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
  *) fail SELECTOR "unknown test $SELECTED" ;;
esac
