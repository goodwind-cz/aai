#!/usr/bin/env bash
# /aai-merge engine tests (spec-directed-merge-and-post-merge-cleanup).
# Every fixture lives under ONE private absolute scratch root; every git call
# in a fixture carries its own identity; gh is a deny-by-default stub.
# B1: TEST-005 (apply read-back gate), TEST-006/007 (drafts).
# B2: TEST-008/009 (base sync), TEST-010/011 (worktree and branch cleanup).
set -euo pipefail

case "$0" in /*) HERE="${0%/*}" ;; */*) HERE="$PWD/${0%/*}" ;; *) HERE="$PWD" ;; esac
ROOT="$HERE/../.."
ENGINE="$ROOT/.aai/scripts/merge-cleanup.mjs"
DOCS_AUDIT="$ROOT/.aai/scripts/docs-audit.mjs"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/aai-merge-cleanup.XXXXXX")"
[[ -n "$SCRATCH" && "$SCRATCH" = /* && -d "$SCRATCH" ]] || { echo 'FAIL: SETUP scratch root not absolute' >&2; exit 1; }

SCRATCH="$(cd "$SCRATCH" && pwd -P)" || { echo 'FAIL: SETUP scratch root not resolvable' >&2; exit 1; }

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
  printf '{"v":1,"ts":"2026-10-10T00:00:00Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n{"v":1,"ts":"2026-10-10T00:00:01Z","actor":"fixture","event":"work_item_closed","ref":"%s","payload":{"validation":"pass","code_review":"pass"}}\n' "$ISSUE_ID" "$SPEC_ID" >> "$RIDE/docs/ai/EVENTS.jsonl"
  printf 'delivered by the ride\n' >> "$RIDE/README.md"
  run git -C "$RIDE" add "$NUM_ISSUE" "$NUM_SPEC" docs/ai/EVENTS.jsonl README.md
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
  if git -C "$ORIGIN" merge-base --is-ancestor "$HEAD_OID" main 2>/dev/null; then fail SETUP 'fixture is not a squash merge'; fi
  for f in $RUNTIME_FILES; do run cp "$RIDE/$f" "$(kf "$f")"; done

  run_engine apply --pr "$PR" --pid "$pid" --json
  [[ "$ENG_RC" -eq 0 ]] || fail TEST-010 "apply exited $ENG_RC (out: $ENG_OUT $ENG_ERR)"
  rep="$ENG_OUT"
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

case "$SELECTED" in
  '') test_005_apply_readback_gate; test_006_superseded_drafts; test_007_retained_and_decisions
     test_008_base_sync_preserves_work; test_009_base_sync_refusals; test_010_worktree_and_branch_cleanup; test_011_worktree_refusals ;;
  TEST-005|test_005_apply_readback_gate) test_005_apply_readback_gate ;;
  TEST-006|test_006_superseded_drafts) test_006_superseded_drafts ;;
  TEST-007|test_007_retained_and_decisions) test_007_retained_and_decisions ;;
  TEST-008|test_008_base_sync_preserves_work) test_008_base_sync_preserves_work ;;
  TEST-009|test_009_base_sync_refusals) test_009_base_sync_refusals ;;
  TEST-010|test_010_worktree_and_branch_cleanup) test_010_worktree_and_branch_cleanup ;;
  TEST-011|test_011_worktree_refusals) test_011_worktree_refusals ;;
  *) fail SELECTOR "unknown test $SELECTED" ;;
esac
