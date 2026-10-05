#!/usr/bin/env bash
#
# gh-merge-queue-stub.sh — the ONE place that knows the exact `gh api
# graphql` argv .aai/scripts/merge-policy.mjs's getMergeQueueEnabled sends
# (B1 remediation, validation round 11, Spec-AC-16/Spec-AC-25). Sourced by
# test-aai-merge-policy.sh (which owns the argv contract) and
# test-aai-hooks-overlay.sh's three merge-queue-aware gh stub fixtures,
# which used to answer ANY `api graphql ...` call unconditionally — a
# mutation changing the query/owner/name/pr binding, or calling it twice,
# survived every one of them (round-11 report B1).
#
# MERGE_QUEUE_GRAPHQL_QUERY must stay byte-identical to the `query` constant
# built in getMergeQueueEnabled (.aai/scripts/merge-policy.mjs); it is
# single-quoted here so the literal `$owner`/`$name`/`$pr` GraphQL variable
# tokens are never touched by THIS shell.
MERGE_QUEUE_GRAPHQL_QUERY='query($owner:String!,$name:String!,$pr:Int!){repository(owner:$owner,name:$name){pullRequest(number:$pr){isMergeQueueEnabled}}}'

# merge_queue_graphql_argv <pr> — prints the single exact argv line (space-
# joined, matching how both suites log a stub invocation) the evaluator
# sends for that PR. Callers write this to a file and have the generated
# stub script re-read it at RUN time (never splice it into heredoc shell
# code directly) -- the query text's own literal `$owner`/`$name`/`$pr`
# bytes would otherwise be re-expanded as shell variables by whatever shell
# later executes the stub.
merge_queue_graphql_argv() {
  local pr="$1"
  printf 'api graphql -f query=%s -F owner={owner} -F name={repo} -F pr=%s' \
    "$MERGE_QUEUE_GRAPHQL_QUERY" "$pr"
}

# write_merge_queue_gh_stub <dir> — writes <dir>/bin/gh: `gh pr view <n>`
# serves <dir>/pr-<n>.json (pre-existing hooks-overlay fixture convention)
# and remembers <n> in <dir>/.last-pr; `gh api graphql` answers the
# merge-queue read with isMergeQueueEnabled:false ONLY when its argv is
# EXACTLY merge_queue_graphql_argv for that remembered PR, and otherwise
# denies loudly (STUB-DENY on stderr, exit 1) rather than answering any
# `api graphql` call unconditionally. Every invocation is appended to
# <dir>/gh-argv.log, matching every existing caller's log format.
write_merge_queue_gh_stub() {
  local d="$1"
  mkdir -p "$d/bin"
  printf '%s' "$MERGE_QUEUE_GRAPHQL_QUERY" > "$d/.graphql-query"
  cat > "$d/bin/gh" <<GHSTUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$d/gh-argv.log"
if [ "\${1:-}" = "pr" ] && [ "\${2:-}" = "view" ] && [ -f "$d/pr-\${3:-none}.json" ]; then
  printf '%s' "\${3}" > "$d/.last-pr"
  case "\$*" in
    *'-q .headRefOid'*)
      sed -n 's/.*"headRefOid":"\([^"]*\)".*/\1/p' "$d/pr-\${3}.json"
      exit 0
      ;;
  esac
  cat "$d/pr-\${3}.json"; exit 0
fi
if [ "\${1:-}" = "api" ] && [ "\${2:-}" = "graphql" ]; then
  __gh_mq_query="\$(cat "$d/.graphql-query" 2>/dev/null)"
  __gh_mq_last_pr="\$(cat "$d/.last-pr" 2>/dev/null)"
  __gh_mq_expected="api graphql -f query=\$__gh_mq_query -F owner={owner} -F name={repo} -F pr=\$__gh_mq_last_pr"
  if [ "\$*" = "\$__gh_mq_expected" ]; then
    echo '{"data":{"repository":{"pullRequest":{"isMergeQueueEnabled":false}}}}'
    exit 0
  fi
  printf 'STUB-DENY: unexpected graphql argv: %s\n' "\$*" >&2
  exit 1
fi
exit 1
GHSTUB
  chmod +x "$d/bin/gh"
}
