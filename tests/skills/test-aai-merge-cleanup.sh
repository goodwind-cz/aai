#!/usr/bin/env bash
# /aai-merge engine tests (spec-directed-merge-and-post-merge-cleanup).
# Every fixture lives under ONE private absolute scratch root; every git call
# in a fixture carries its own identity; gh is a deny-by-default stub.
# Batch B1 covers TEST-005 (apply read-back gate), TEST-006/007 (drafts).
set -euo pipefail

case "$0" in /*) HERE="${0%/*}" ;; */*) HERE="$PWD/${0%/*}" ;; *) HERE="$PWD" ;; esac
ROOT="$HERE/../.."
ENGINE="$ROOT/.aai/scripts/merge-cleanup.mjs"
DOCS_AUDIT="$ROOT/.aai/scripts/docs-audit.mjs"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/aai-merge-cleanup.XXXXXX")"
[[ -n "$SCRATCH" && "$SCRATCH" = /* && -d "$SCRATCH" ]] || { echo 'FAIL: SETUP scratch root not absolute' >&2; exit 1; }

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

cleanup() { [[ -n "${KEEP_TEST_DIR:-}" ]] || rm -rf "$SCRATCH"; }
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
  printf 'docs/ai/archive/**\ndocs/ai/reports/**\n' > "$ORIGIN/.gitignore"
  run git -C "$ORIGIN" add README.md .gitignore
  run git -C "$ORIGIN" commit -qm baseline
  run git -C "$ORIGIN" push -q origin main
  run git -C "$ORIGIN" fetch -q origin
  run mkdir -p "$ORIGIN/docs/issues" "$ORIGIN/docs/specs"
  draft_issue_v1 > "$ORIGIN/$DRAFT_ISSUE"
  draft_spec_v1 > "$ORIGIN/$DRAFT_SPEC"
  run git -C "$ORIGIN" worktree add -q -b "$BRANCH" "$RIDE" main
  run git -C "$RIDE" config user.name 'AAI Fixture'
  run git -C "$RIDE" config user.email 'fixture@example.invalid'
  run mkdir -p "$RIDE/docs/issues" "$RIDE/docs/specs"
  run cp "$ORIGIN/$DRAFT_ISSUE" "$RIDE/$DRAFT_ISSUE"
  run cp "$ORIGIN/$DRAFT_SPEC" "$RIDE/$DRAFT_SPEC"
  run git -C "$RIDE" add "$DRAFT_ISSUE" "$DRAFT_SPEC"
  run git -C "$RIDE" commit -qm 'docs: drafts'
  run git -C "$RIDE" mv "$DRAFT_ISSUE" "$NUM_ISSUE"
  run git -C "$RIDE" mv "$DRAFT_SPEC" "$NUM_SPEC"
  numbered_issue > "$RIDE/$NUM_ISSUE"
  numbered_spec > "$RIDE/$NUM_SPEC"
  run mkdir -p "$RIDE/docs/ai"
  printf '{"v":1,"ts":"2026-10-10T00:00:00Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n{"v":1,"ts":"2026-10-10T00:00:01Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n' "$ISSUE_ID" "$SPEC_ID" > "$RIDE/docs/ai/EVENTS.jsonl"
  run git -C "$RIDE" add "$NUM_ISSUE" "$NUM_SPEC" docs/ai/EVENTS.jsonl
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
numbered_issue() { printf -- '---\nid: %s\ntype: issue\nnumber: 1\nstatus: done\nlinks:\n  pr:\n    - %s\n  commits: []\n---\n\n# Issue foo\n\nDraft body.\n\nDelivered.\n' "$ISSUE_ID" "$PR"; }
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
    git -C "$ORIGIN" status --porcelain=v1 -uall
    git -C "$ORIGIN" worktree list --porcelain
    git -C "$ORIGIN" for-each-ref --format='%(refname) %(objectname)' refs/heads
    git -C "$BARE" for-each-ref --format='%(refname) %(objectname)' refs/heads
    git -C "$ORIGIN" stash list
    find "$ORIGIN" "$RIDE" -path '*/.git' -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s %s\n' "$f" "$(sha_of "$f")"
    done
  } | sha_stdin
}

# run_engine <args...>: runs the engine from the origin checkout with the gh
# stub first on PATH. Sets ENG_OUT (stdout), ENG_ERR (stderr), ENG_RC.
run_engine() {
  ENG_RC=0
  [[ -n "$ORIGIN" && "$ORIGIN" = /* ]] || fail SETUP 'engine cwd'
  ( cd "$ORIGIN" && PATH="$GHD/bin:$PATH" GH_STUB_DIR="$GHD" node "$ENGINE" "$@" >"$W/engine.out" 2>"$W/engine.err" ) || ENG_RC=$?
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
  echo 'PASS: TEST-005 apply read-back gate'
}

test_006_superseded_drafts() {
  build_world drafts
  local issue_sha spec_sha arch lines before_audit after_audit
  issue_sha="$(sha_of "$ORIGIN/$DRAFT_ISSUE")"
  spec_sha="$(sha_of "$ORIGIN/$DRAFT_SPEC")"
  run cp "$ORIGIN/$DRAFT_ISSUE" "$W/orig-issue.md"
  run cp "$ORIGIN/$DRAFT_SPEC" "$W/orig-spec.md"
  # the numbered docs reach the origin checkout (done by the base-sync step in
  # a later batch; plain git here so this test isolates the archive step)
  run git -C "$ORIGIN" fetch -q origin
  run git -C "$ORIGIN" merge -q --ff-only origin/main
  before_audit="$(audit_verdict)"
  unwanted TEST-006 "$before_audit" 'Verdict: CLEAN'   # control: drafts + numbered docs clash

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
  after="$(json_get "$ENG_OUT" 'j.archived[0].archive')"
  [[ -f "$ORIGIN/$after" ]] || fail TEST-007 "archive path from report missing: $after"
  cmp "$W/divergent-spec.md" "$ORIGIN/$after" || fail TEST-007 'archived divergent bytes differ from the original'
  [[ "$after" != "docs/ai/archive/merge-cleanup/pr-$PR/files/$DRAFT_SPEC" ]] || fail TEST-007 'archive path was not suffixed'
  [[ -f "$ORIGIN/$other" ]] || fail TEST-007 'unrelated draft vanished during the decision run'
  want TEST-007 "$ENG_OUT" '"reason":"unrelated_id"'
  want TEST-007 "$(cat "$arch/manifest.jsonl")" '"reason":"divergent_archived_by_decision"'

  # degenerate: no drafts at all -> clean no-op, no archive directory created
  build_world empty
  run rm "$ORIGIN/$DRAFT_ISSUE" "$ORIGIN/$DRAFT_SPEC"
  before="$(world_digest)"
  run_engine apply --pr "$PR" --pid 4242 --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-007 "empty-world apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  [[ "$(world_digest)" == "$before" ]] || fail TEST-007 'empty-world apply changed the fixture'
  [[ ! -e "$ORIGIN/docs/ai/archive" ]] || fail TEST-007 'empty-world apply created an archive directory'
  [[ "$(json_get "$ENG_OUT" 'j.archived.length')" == 0 ]] || fail TEST-007 'empty-world archived count'
  echo 'PASS: TEST-007 retained drafts and explicit decisions'
}

case "$SELECTED" in
  '') test_005_apply_readback_gate; test_006_superseded_drafts; test_007_retained_and_decisions ;;
  TEST-005|test_005_apply_readback_gate) test_005_apply_readback_gate ;;
  TEST-006|test_006_superseded_drafts) test_006_superseded_drafts ;;
  TEST-007|test_007_retained_and_decisions) test_007_retained_and_decisions ;;
  *) fail SELECTOR "unknown test $SELECTED" ;;
esac
