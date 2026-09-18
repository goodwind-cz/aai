#!/usr/bin/env bash
#
# Test: hook-enforced gates overlay (RFC-0010 / spec-hook-enforced-gates)
# Verifies the opt-in Claude Code hooks template
# (.aai/templates/hooks/settings-hooks.json), the thin adapter
# (.aai/scripts/claude-hook-gate.sh — zero gate logic, routes to EXISTING
# script gates, fail-open on its own errors), the aai-bootstrap
# --with-claude-hooks opt-in merge, and the SKILL_PR AAI_OPERATOR_MERGE
# marker documentation (constitution article 7, strict).
#
# Covers TEST-001..015 from docs/specs/SPEC-0029-spec-hook-enforced-gates.md.
#
# NOTE: this repo itself keeps the overlay UNINSTALLED (opt-in means opt-in);
# these tests exercise the template and adapter directly in fixtures
# (TEST-013 asserts the uninstalled invariant).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-hooks-overlay"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

TEMPLATE=".aai/templates/hooks/settings-hooks.json"
ADAPTER=".aai/scripts/claude-hook-gate.sh"
BOOTSTRAP=".aai/scripts/aai-bootstrap.sh"
SKILL_PR=".aai/SKILL_PR.prompt.md"

FAILED=0
FIXTURES=()

cleanup() {
  local d
  for d in "${FIXTURES[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

new_fixture() {
  local d
  d="$(mktemp -d /tmp/aai-test-hooks-XXXXXX)"
  FIXTURES+=("$d")
  printf '%s\n' "$d"
}

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -d .aai ]] || log_skip ".aai directory not found"
}

# Build a PreToolUse-shaped payload for a Bash command.
payload_for() {
  node -e 'process.stdout.write(JSON.stringify({
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    tool_input: { command: process.argv[1] }
  }))' "$1"
}

# Run the adapter for a gate with a given Bash-command payload inside a dir.
# Usage: run_gate <dir> <gate> <command-text>; echoes exit code.
run_gate() {
  local dir="$1" gate="$2" cmdtext="$3" rc=0
  payload_for "$cmdtext" | (cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash "$PROJECT_ROOT/$ADAPTER" "$gate" >/dev/null 2>&1) || rc=$?
  printf '%s\n' "$rc"
}

# TEST-001 — template exists and parses as JSON
test_001_template_valid_json() {
  if [[ ! -f "$TEMPLATE" ]]; then
    log_fail "TEST-001 $TEMPLATE does not exist"
    return
  fi
  if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$TEMPLATE" 2>/dev/null; then
    log_pass "TEST-001 $TEMPLATE is valid JSON"
  else
    log_fail "TEST-001 $TEMPLATE is not valid JSON"
  fi
}

# TEST-002 — structure: 3 PreToolUse command hooks under a Bash matcher
# (commit, merge, state-dump) + 1 matcherless Stop hook (stop-nudge)
test_002_template_structure() {
  [[ -f "$TEMPLATE" ]] || { log_fail "TEST-002 $TEMPLATE does not exist"; return; }
  local out
  if out=$(node -e '
    const t = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const h = t.hooks || {};
    const pre = h.PreToolUse || [];
    const stop = h.Stop || [];
    const bash = pre.filter(m => m.matcher === "Bash");
    if (bash.length !== 1) throw new Error("expected exactly one PreToolUse matcher entry with matcher \"Bash\", got " + bash.length);
    const cmds = (bash[0].hooks || []);
    if (cmds.length !== 3) throw new Error("expected 3 PreToolUse command hooks, got " + cmds.length);
    for (const gate of ["commit", "merge", "state-dump"]) {
      if (!cmds.some(c => c.type === "command" && String(c.command).includes("claude-hook-gate.sh") && String(c.command).includes(gate)))
        throw new Error("missing PreToolUse command hook for gate: " + gate);
    }
    if (stop.length !== 1) throw new Error("expected exactly one Stop entry, got " + stop.length);
    if (stop[0].matcher !== undefined) throw new Error("Stop entry must be matcherless");
    const sh = stop[0].hooks || [];
    if (sh.length !== 1 || sh[0].type !== "command" || !String(sh[0].command).includes("stop-nudge"))
      throw new Error("Stop entry must carry exactly one stop-nudge command hook");
    const all = [...cmds, ...sh];
    if (!all.every(c => c.type === "command")) throw new Error("every hook must be type command");
    console.log("ok");
  ' "$TEMPLATE" 2>&1); then
    log_pass "TEST-002 template structure: 3 PreToolUse(Bash) gates + 1 Stop nudge, all command hooks"
  else
    log_fail "TEST-002 template structure: $out"
  fi
}

# TEST-003 — conformance: hooks only reference existing scripts; the adapter
# routes to pre-commit-checks.sh and points at state.mjs (never reimplements)
test_003_script_conformance() {
  local ok=1 f
  [[ -f "$TEMPLATE" ]] || { log_fail "TEST-003 $TEMPLATE does not exist"; return; }
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-003 $ADAPTER does not exist"; return; }
  # Every .aai/scripts path mentioned in the template or the adapter must exist.
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ ! -f "$f" ]]; then
      log_info "TEST-003: referenced script missing: $f"
      ok=0
    fi
  done < <(grep -hoE '\.aai/scripts/[A-Za-z0-9._-]+' "$TEMPLATE" "$ADAPTER" | sort -u)
  grep -qF "pre-commit-checks.sh" "$ADAPTER" \
    || { log_info "TEST-003: adapter does not route the commit gate to pre-commit-checks.sh"; ok=0; }
  grep -qF "state.mjs" "$ADAPTER" \
    || { log_info "TEST-003: adapter state-dump message does not point at state.mjs"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-003 all referenced .aai/scripts exist; adapter routes to existing gates" \
                  || log_fail "TEST-003 script conformance"
}

# TEST-004 — fail-open shape: every template command guards adapter absence
# and exits 0 when run in an empty directory (no .aai layer at all)
test_004_fail_open_shape() {
  [[ -f "$TEMPLATE" ]] || { log_fail "TEST-004 $TEMPLATE does not exist"; return; }
  local ok=1 d i n cmd rc
  d="$(new_fixture)"
  n=$(node -e '
    const t = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const cmds = [];
    for (const arr of Object.values(t.hooks || {}))
      for (const m of arr) for (const h of (m.hooks || [])) cmds.push(h.command);
    console.log(cmds.length);
    require("fs").writeFileSync(process.argv[2] + "/cmds.txt", cmds.join("\n") + "\n");
  ' "$TEMPLATE" "$d" 2>/dev/null || echo 0)
  if [[ "$n" -ne 4 ]]; then
    log_fail "TEST-004 expected 4 command strings in template, got $n"
    return
  fi
  # round 8 / Copilot: an UNQUOTED `case $cmd in *$1*)` glob match on a
  # variable-supplied needle would treat glob metacharacters in the needle
  # (e.g. the literal `[` in the 'if [ -f ' needle below) as pattern syntax
  # rather than literal text. The shipped needle was already double-quoted
  # (`*"$1"*`), which bash treats as a literal match — that quoted form was
  # never actually at risk (round 8's finding did not reproduce against the
  # code as shipped) — but quoting discipline surviving every future edit is
  # not something to rely on, so `_cmd_has` below removes the risk class
  # entirely: `grep -qF` on a here-string is a literal, non-glob substring
  # test, structurally immune to this class of bug regardless of what the
  # needle contains or whether a future edit drops the quotes around `$1`.
  _cmd_has() { grep -qF -- "$1" <<<"$cmd"; }
  # Positive control (round 8): prove _cmd_has treats a `[...]`-shaped needle
  # as LITERAL text, not a glob bracket-expression — a cmd string that
  # contains none of the individual bracketed characters, only text a GLOB
  # bracket-expression would wrongly match, must NOT match.
  if (cmd='axc' _cmd_has 'a[xy]c'); then
    log_fail "TEST-004: _cmd_has treats '[...]' as a glob bracket-expression (matched 'axc' against needle 'a[xy]c' with no literal substring present)"
  fi
  if ! (cmd='a[xy]c' _cmd_has 'a[xy]c'); then
    log_fail "TEST-004: _cmd_has must still match when the literal bracketed substring IS present"
  fi
  i=0
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    i=$((i+1))
    # Guard shape: the adapter path is named, and its existence is tested
    # with `if [ -f ... ]` before any invocation (absence degrades to exit 0).
    if ! _cmd_has 'claude-hook-gate.sh' \
       || ! _cmd_has 'if [ -f '; then
      log_info "TEST-004: command $i lacks the adapter-absence guard: $cmd"
      ok=0
    fi
    rc=0
    printf '{}' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" sh -c "$cmd" >/dev/null 2>&1) || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      log_info "TEST-004: command $i exits $rc (not 0) with the adapter absent"
      ok=0
    fi
  done < "$d/cmds.txt"
  [[ $ok -eq 1 ]] && log_pass "TEST-004 all 4 commands guard adapter absence and exit 0 without the .aai layer" \
                  || log_fail "TEST-004 fail-open shape"
}

# TEST-005 — commit gate routing (mirrors pre-commit-checks.sh, never reimplements)
test_005_commit_gate() {
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-005 $ADAPTER does not exist"; return; }
  local ok=1 d rc
  # Non-commit command: allow.
  d="$(new_fixture)"
  rc=$(run_gate "$d" commit "ls -la")
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005: non-commit command exited $rc (want 0)"; ok=0; }
  # Commit with NO checks script in the project: fail-open allow.
  rc=$(run_gate "$d" commit "git commit -m 'x'")
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005: commit w/o checks script exited $rc (want 0, fail-open)"; ok=0; }
  # Commit with a PASSING checks script: allow.
  mkdir -p "$d/.aai/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/.aai/scripts/pre-commit-checks.sh"
  rc=$(run_gate "$d" commit "git commit -m 'x'")
  [[ "$rc" -eq 0 ]] || { log_info "TEST-005: commit w/ passing checks exited $rc (want 0)"; ok=0; }
  # Commit with a FAILING checks script: block (2) with the reason on stderr.
  printf '#!/usr/bin/env bash\necho "secret detected" >&2\nexit 1\n' > "$d/.aai/scripts/pre-commit-checks.sh"
  local err
  err=$(payload_for "git commit -m 'x'" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" bash "$PROJECT_ROOT/$ADAPTER" commit 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-005: commit w/ failing checks exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "pre-commit" "TEST-005: block reason does not name the pre-commit gate: $err" || ok=0
  # git commit embedded after && also matches.
  rc=$(run_gate "$d" commit "git add x && git commit -m 'x'")
  [[ "$rc" -eq 2 ]] || { log_info "TEST-005: compound commit exited $rc (want 2)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-005 commit gate routes to pre-commit-checks.sh (0/0/0/2 as designed)" \
                  || log_fail "TEST-005 commit gate"
}

# TEST-006 — merge gate: article-7 deny unless AAI_OPERATOR_MERGE=1
test_006_merge_gate() {
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-006 $ADAPTER does not exist"; return; }
  local ok=1 d rc err
  d="$(new_fixture)"
  err=$(payload_for "git merge feature-x" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" env -u AAI_OPERATOR_MERGE bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-006: git merge exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "AAI_OPERATOR_MERGE" "TEST-006: deny message does not name the AAI_OPERATOR_MERGE escape" || ok=0
  local _nc_save; _nc_save="$(shopt -p nocasematch 2>/dev/null || printf 'shopt -u nocasematch')"
  shopt -s nocasematch
  case "$err" in
    *"article 7"*|*"operator-only"*) eval "$_nc_save" ;;
    *) eval "$_nc_save"; log_info "TEST-006: deny message does not cite article 7 / operator-only"; ok=0 ;;
  esac
  payload_for "gh pr merge 42 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" env -u AAI_OPERATOR_MERGE bash "$PROJECT_ROOT/$ADAPTER" merge >/dev/null 2>&1); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-006: gh pr merge exited $rc (want 2)"; ok=0; }
  payload_for "git merge feature-x" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge >/dev/null 2>&1); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-006: merge with marker exited $rc (want 0)"; ok=0; }
  rc=$(run_gate "$d" merge "git merge-base main HEAD")
  [[ "$rc" -eq 0 ]] || { log_info "TEST-006: git merge-base exited $rc (want 0)"; ok=0; }
  rc=$(run_gate "$d" merge "gh pr view 42")
  [[ "$rc" -eq 0 ]] || { log_info "TEST-006: gh pr view exited $rc (want 0)"; ok=0; }
  # Review NB-2 regression: dash options WITH arguments must not bypass the deny.
  payload_for "git -C ../some-worktree merge feat-x" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" env -u AAI_OPERATOR_MERGE bash "$PROJECT_ROOT/$ADAPTER" merge >/dev/null 2>&1); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-006: 'git -C <path> merge' exited $rc (want 2 — NB-2)"; ok=0; }
  payload_for "git -C ../some-worktree merge feat-x" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge >/dev/null 2>&1); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-006: '-C merge' with marker exited $rc (want 0)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-006 merge gate denies (article 7) unless AAI_OPERATOR_MERGE=1; merge-base ignored" \
                  || log_fail "TEST-006 merge gate"
}

# TEST-007 — state-dump gate: whole-file YAML serialization of STATE.yaml denied
test_007_state_dump_gate() {
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-007 $ADAPTER does not exist"; return; }
  local ok=1 d rc err
  d="$(new_fixture)"
  err=$(payload_for "python3 -c 'import yaml; yaml.dump(d, open(\"docs/ai/STATE.yaml\",\"w\"))'" \
    | (cd "$d" && CLAUDE_PROJECT_DIR="$d" bash "$PROJECT_ROOT/$ADAPTER" state-dump 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-007: yaml.dump on STATE.yaml exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "state.mjs" "TEST-007: deny message does not point at state.mjs" || ok=0
  rc=$(run_gate "$d" state-dump "python3 -c 'import yaml; yaml.safe_dump(d, open(\"docs/ai/STATE.yaml\",\"w\"))'")
  [[ "$rc" -eq 2 ]] || { log_info "TEST-007: safe_dump on STATE.yaml exited $rc (want 2)"; ok=0; }
  rc=$(run_gate "$d" state-dump "python3 -c 'import yaml; yaml.dump(d, open(\"other.yaml\",\"w\"))'")
  [[ "$rc" -eq 0 ]] || { log_info "TEST-007: yaml.dump on other file exited $rc (want 0)"; ok=0; }
  rc=$(run_gate "$d" state-dump "cat docs/ai/STATE.yaml")
  [[ "$rc" -eq 0 ]] || { log_info "TEST-007: read of STATE.yaml exited $rc (want 0)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-007 state-dump gate denies dump-writes to STATE.yaml with state.mjs pointer" \
                  || log_fail "TEST-007 state-dump gate"
}

# TEST-008 — fail-open on adapter's own errors (malformed stdin, broken node)
test_008_fail_open_errors() {
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-008 $ADAPTER does not exist"; return; }
  local ok=1 d rc gate
  d="$(new_fixture)"
  for gate in commit merge state-dump stop-nudge; do
    printf 'this is not json' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" bash "$PROJECT_ROOT/$ADAPTER" "$gate" >/dev/null 2>&1); rc=$?
    [[ "$rc" -eq 0 ]] || { log_info "TEST-008: gate $gate exited $rc on malformed JSON (want 0)"; ok=0; }
  done
  # Broken node in PATH: command -v node succeeds but node fails — still 0.
  mkdir -p "$d/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$d/bin/node"
  chmod +x "$d/bin/node"
  payload_for "git merge x" > "$d/payload.json"
  (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" bash "$PROJECT_ROOT/$ADAPTER" merge < "$d/payload.json" >/dev/null 2>&1); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-008: merge gate with broken node exited $rc (want 0)"; ok=0; }
  # Unknown gate argument: 0.
  printf '{}' | (cd "$d" && bash "$PROJECT_ROOT/$ADAPTER" no-such-gate >/dev/null 2>&1); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-008: unknown gate exited $rc (want 0)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-008 adapter fail-open: malformed stdin, broken node, unknown gate all exit 0" \
                  || log_fail "TEST-008 fail-open"
}

# TEST-009 — stop-nudge: never blocks; nudges only when warranted
test_009_stop_nudge() {
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-009 $ADAPTER does not exist"; return; }
  local ok=1 d rc out
  # No STATE at all: silent allow.
  d="$(new_fixture)"
  out=$(printf '{}' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" bash "$PROJECT_ROOT/$ADAPTER" stop-nudge 2>/dev/null)); rc=$?
  [[ "$rc" -eq 0 && -z "$out" ]] || { log_info "TEST-009: no-STATE case rc=$rc out='$out' (want 0, silent)"; ok=0; }
  # STATE with in_progress and no ticks file: nudge on stdout, exit 0.
  mkdir -p "$d/docs/ai"
  printf 'active_work_items:\n  - ref_id: X-1\n    status: in_progress\n' > "$d/docs/ai/STATE.yaml"
  out=$(printf '{}' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" bash "$PROJECT_ROOT/$ADAPTER" stop-nudge 2>/dev/null)); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-009: in_progress case exited $rc (want 0 — NEVER block)"; ok=0; }
  [[ -n "$out" ]] || { log_info "TEST-009: in_progress + no ticks produced no nudge"; ok=0; }
  # Ticks newer than STATE: silent.
  sleep 1
  printf '{"tick":1}\n' > "$d/docs/ai/LOOP_TICKS.jsonl"
  out=$(printf '{}' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" bash "$PROJECT_ROOT/$ADAPTER" stop-nudge 2>/dev/null)); rc=$?
  [[ "$rc" -eq 0 && -z "$out" ]] || { log_info "TEST-009: fresh-ticks case rc=$rc out='$out' (want 0, silent)"; ok=0; }
  # Done-only STATE: silent.
  printf 'active_work_items:\n  - ref_id: X-1\n    status: done\n' > "$d/docs/ai/STATE.yaml"
  rm -f "$d/docs/ai/LOOP_TICKS.jsonl"
  out=$(printf '{}' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" bash "$PROJECT_ROOT/$ADAPTER" stop-nudge 2>/dev/null)); rc=$?
  [[ "$rc" -eq 0 && -z "$out" ]] || { log_info "TEST-009: done-only case rc=$rc out='$out' (want 0, silent)"; ok=0; }
  # The adapter's stop-nudge branch must have no exit-2 path at all.
  if awk '/^  stop-nudge\)/,/^  ;;/' "$PROJECT_ROOT/$ADAPTER" | qgrep -q "exit 2"; then
    log_info "TEST-009: stop-nudge branch contains an exit 2 path"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-009 stop-nudge never blocks; nudges exactly when in_progress with stale/absent ticks" \
                  || log_fail "TEST-009 stop-nudge"
}

# TEST-010 — bootstrap opt-in wiring (grep)
test_010_bootstrap_wiring() {
  local ok=1
  grep -q -- '--with-claude-hooks' "$BOOTSTRAP" \
    || { log_info "TEST-010: --with-claude-hooks flag not parsed in $BOOTSTRAP"; ok=0; }
  grep -qF ".aai/templates/hooks/settings-hooks.json" "$BOOTSTRAP" \
    || { log_info "TEST-010: bootstrap does not reference the hooks template path"; ok=0; }
  # The flag must be documented in the header usage() prints.
  sed -n '1,25p' "$BOOTSTRAP" | qgrep -q -- '--with-claude-hooks' \
    || { log_info "TEST-010: --with-claude-hooks missing from the usage header"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-010 bootstrap --with-claude-hooks wired and documented" \
                  || log_fail "TEST-010 bootstrap wiring"
}

# TEST-011 — bootstrap behavior: opt-in only, merge, idempotent, never-silent-overwrite
test_011_bootstrap_behavior() {
  [[ -f "$TEMPLATE" ]] || { log_fail "TEST-011 $TEMPLATE does not exist"; return; }
  local ok=1 d rc
  # Review NB-1 regression: pre-existing non-object "hooks" key refuses loud,
  # file untouched (was: silent false success dropping all merged entries).
  local nb1; nb1="$(new_fixture)"
  mkdir -p "$nb1/.aai/templates/hooks" "$nb1/.aai/scripts" "$nb1/.claude"
  cp "$TEMPLATE" "$nb1/.aai/templates/hooks/settings-hooks.json"
  printf '{"hooks": []}' > "$nb1/.claude/settings.json"
  (cd "$nb1" && bash "$PROJECT_ROOT/$BOOTSTRAP" --with-claude-hooks >/dev/null 2>&1); rc=$?
  [[ "$rc" -ne 0 ]] || { log_info "TEST-011: hooks:[] must refuse loud (got exit 0 — NB-1)"; ok=0; }
  [[ "$(cat "$nb1/.claude/settings.json")" == '{"hooks": []}' ]] \
    || { log_info "TEST-011: refused settings.json must stay byte-untouched (NB-1)"; ok=0; }
  d="$(new_fixture)"
  mkdir -p "$d/.aai/templates/hooks" "$d/.aai/scripts"
  cp "$TEMPLATE" "$d/.aai/templates/hooks/settings-hooks.json"
  # 1) Default run: no hooks install, no settings.json.
  (cd "$d" && bash "$PROJECT_ROOT/$BOOTSTRAP" >/dev/null 2>&1) || true
  if [[ -f "$d/.claude/settings.json" ]]; then
    log_info "TEST-011: default bootstrap run created .claude/settings.json"
    ok=0
  fi
  # 2) Opt-in run: hooks merged into a fresh settings.json.
  (cd "$d" && bash "$PROJECT_ROOT/$BOOTSTRAP" --with-claude-hooks >/dev/null 2>&1); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-011: opt-in bootstrap run exited $rc"; ok=0; }
  if [[ ! -f "$d/.claude/settings.json" ]]; then
    log_fail "TEST-011 opt-in run did not create .claude/settings.json"
    return
  fi
  node -e '
    const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const cmds = [];
    for (const arr of Object.values(s.hooks || {}))
      for (const m of arr) for (const h of (m.hooks || [])) cmds.push(String(h.command));
    if (cmds.length !== 4) throw new Error("expected 4 merged hook commands, got " + cmds.length);
    if (!cmds.every(c => c.includes("claude-hook-gate.sh"))) throw new Error("merged command missing adapter reference");
  ' "$d/.claude/settings.json" 2>/dev/null \
    || { log_info "TEST-011: merged settings.json does not carry the 4 overlay hooks"; ok=0; }
  # 3) Re-run: idempotent (byte-identical).
  local before after
  before=$(cat "$d/.claude/settings.json")
  (cd "$d" && bash "$PROJECT_ROOT/$BOOTSTRAP" --with-claude-hooks >/dev/null 2>&1) || true
  after=$(cat "$d/.claude/settings.json")
  [[ "$before" == "$after" ]] \
    || { log_info "TEST-011: second opt-in run changed settings.json (not idempotent)"; ok=0; }
  # 4) Foreign keys and foreign hooks survive the merge.
  local d2
  d2="$(new_fixture)"
  mkdir -p "$d2/.aai/templates/hooks" "$d2/.claude"
  cp "$TEMPLATE" "$d2/.aai/templates/hooks/settings-hooks.json"
  printf '{\n  "permissions": {"allow": ["Bash(ls:*)"]},\n  "hooks": {"SessionStart": [{"matcher": "startup", "hooks": [{"type": "command", "command": "echo hi"}]}]}\n}\n' \
    > "$d2/.claude/settings.json"
  (cd "$d2" && bash "$PROJECT_ROOT/$BOOTSTRAP" --with-claude-hooks >/dev/null 2>&1) || true
  node -e '
    const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    if (!s.permissions || !s.permissions.allow || s.permissions.allow[0] !== "Bash(ls:*)")
      throw new Error("foreign permissions key lost");
    if (!s.hooks.SessionStart || s.hooks.SessionStart[0].hooks[0].command !== "echo hi")
      throw new Error("foreign SessionStart hook lost");
    if (!s.hooks.PreToolUse || !s.hooks.Stop) throw new Error("overlay hooks not merged");
  ' "$d2/.claude/settings.json" 2>/dev/null \
    || { log_info "TEST-011: merge did not preserve foreign settings content"; ok=0; }
  # 5) Unparseable existing settings.json: refused, untouched, instruction printed.
  local d3 out3
  d3="$(new_fixture)"
  mkdir -p "$d3/.aai/templates/hooks" "$d3/.claude"
  cp "$TEMPLATE" "$d3/.aai/templates/hooks/settings-hooks.json"
  printf 'NOT JSON {' > "$d3/.claude/settings.json"
  out3=$( (cd "$d3" && bash "$PROJECT_ROOT/$BOOTSTRAP" --with-claude-hooks 2>&1) ) || true
  [[ "$(cat "$d3/.claude/settings.json")" == "NOT JSON {" ]] \
    || { log_info "TEST-011: invalid settings.json was modified (silent overwrite)"; ok=0; }
  local _nc_save3; _nc_save3="$(shopt -p nocasematch 2>/dev/null || printf 'shopt -u nocasematch')"
  shopt -s nocasematch
  local _manual_found=0 _ml
  while IFS= read -r _ml; do
    if [[ "$_ml" =~ merge.*manually|manual ]]; then _manual_found=1; break; fi
  done <<EOF
$out3
EOF
  eval "$_nc_save3"
  [[ "$_manual_found" -eq 1 ]] || { log_info "TEST-011: refusal did not instruct a manual merge"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-011 bootstrap opt-in: default-off, 4-hook merge, idempotent, foreign content preserved, invalid JSON refused" \
                  || log_fail "TEST-011 bootstrap behavior"
}

# TEST-012 — SKILL_PR documents the marker, honestly, with the boundary intact
test_012_skill_pr_marker() {
  local ok=1
  grep -qF "AAI_OPERATOR_MERGE" "$SKILL_PR" \
    || { log_info "TEST-012: AAI_OPERATOR_MERGE not documented in SKILL_PR"; ok=0; }
  grep -qi "guardrail" "$SKILL_PR" \
    || { log_info "TEST-012: guardrail framing missing"; ok=0; }
  grep -qi "not a security boundary" "$SKILL_PR" \
    || { log_info "TEST-012: not-a-security-boundary honesty missing"; ok=0; }
  grep -qF "NEVER merge" "$SKILL_PR" \
    || { log_info "TEST-012: the NEVER-merge boundary text no longer survives"; ok=0; }
  grep -qi "operator" "$SKILL_PR" \
    || { log_info "TEST-012: operator wording missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-012 SKILL_PR documents AAI_OPERATOR_MERGE as an operator guardrail; merge boundary intact" \
                  || log_fail "TEST-012 SKILL_PR marker documentation"
}

# TEST-013 — this repo stays UNINSTALLED (opt-in means opt-in)
test_013_repo_uninstalled() {
  if [[ ! -f ".claude/settings.json" ]]; then
    log_pass "TEST-013 repo has no .claude/settings.json — overlay uninstalled"
    return
  fi
  if grep -q "claude-hook-gate" ".claude/settings.json"; then
    log_fail "TEST-013 the overlay is installed into this repo's .claude/settings.json (must stay template-only)"
  else
    log_pass "TEST-013 repo .claude/settings.json exists but carries no overlay hooks"
  fi
}

# TEST-014 — prompt-diet byte floor survives the SKILL_PR addition
test_014_prompt_diet_floor() {
  if bash tests/skills/test-aai-prompt-diet.sh >/dev/null 2>&1; then
    log_pass "TEST-014 prompt-diet suite green (byte floor holds)"
  else
    log_fail "TEST-014 prompt-diet suite failed after SKILL_PR addition"
  fi
}

# TEST-015 — repo-wide strict docs audit stays CLEAN with the new docs
test_015_strict_audit() {
  if node .aai/scripts/docs-audit.mjs --check --strict --no-event >/dev/null 2>&1; then
    log_pass "TEST-015 repo-wide strict docs audit clean"
  else
    log_fail "TEST-015 repo-wide strict docs audit failed"
  fi
}

# TEST-574 (Spec-AC-34, close-ceremony-sweep): the merge gate CALLS
# lane-gate.mjs --sweep-check --pr <N> rather than restating its predicate
# (issue 338 mechanization).
test_016_merge_gate_sweep_check() {
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-574 $ADAPTER does not exist"; return; }
  local ok=1 d rc err

  d="$(new_fixture)"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/ai" "$d/bin"
  cp "$PROJECT_ROOT/.aai/scripts/lane-gate.mjs" "$d/.aai/scripts/lane-gate.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/cli-pipe-guard.mjs" "$d/.aai/scripts/lib/cli-pipe-guard.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/pr-sweep.mjs" "$d/.aai/scripts/lib/pr-sweep.mjs"
  : > "$d/docs/ai/EVENTS.jsonl"

  # No pr_sweep record at all for PR 42: denied, naming the absent record.
  err=$(payload_for "gh pr merge 42 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: no-record merge exited $rc (want 2): $err"; ok=0; }
  assert_payload_contains "$err" "pr_sweep" "TEST-574: deny message does not name the absent pr_sweep record: $err" || ok=0
  assert_payload_contains "$err" "42" "TEST-574: deny message does not name PR 42: $err" || ok=0

  # A consistent record for PR 42 (heavy lane, internal_substituted outcome —
  # this fixture carries no spec/STATE, so lane-gate computes heavy by
  # default): merge is allowed.
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/append-event.mjs" --event pr_sweep --ref t574-ride \
     --pr 42 --lane heavy --reviewer-bots none --threads-seen 0 --threads-unresolved 0 \
     --outcome internal_substituted >/dev/null)
  err=$(payload_for "gh pr merge 42 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-574: consistent-record merge exited $rc (want 0): $err"; ok=0; }

  # A fast-lane record against the (computed-heavy) branch: denied again.
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/append-event.mjs" --event pr_sweep --ref t574-ride \
     --pr 43 --lane fast --reviewer-bots none --threads-seen 0 --threads-unresolved 0 \
     --outcome skipped_fast_lane >/dev/null)
  err=$(payload_for "gh pr merge 43 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: fast-lane-record-on-heavy-branch merge exited $rc (want 2): $err"; ok=0; }
  assert_payload_contains "$err" "43" "TEST-574: lane-mismatch deny message does not name PR 43: $err" || ok=0

  # An unreadable EVENTS.jsonl (a directory in its place, permission-
  # independent) must fail OPEN — never a false deny.
  rm -f "$d/docs/ai/EVENTS.jsonl"
  mkdir -p "$d/docs/ai/EVENTS.jsonl"
  err=$(payload_for "gh pr merge 44 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-574: unreadable EVENTS.jsonl must fail OPEN (allow), got $rc: $err"; ok=0; }
  rmdir "$d/docs/ai/EVENTS.jsonl" 2>/dev/null || true

  # B2 (validation-round1): the PR number is NOT always positional right
  # after `merge` -- prove the three other forms the old positional-only
  # regex missed each still get judged against the real record (not allowed
  # by a parse miss). No record for PR 45/46: denied naming it.
  err=$(payload_for "gh pr merge --squash 45" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: 'gh pr merge --squash 45' (number after flags) exited $rc (want 2): $err"; ok=0; }
  assert_payload_contains "$err" "45" "TEST-574: 'gh pr merge --squash 45' deny message does not name PR 45: $err" || ok=0

  err=$(payload_for "gh pr merge --squash --delete-branch 46" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: 'gh pr merge --squash --delete-branch 46' exited $rc (want 2): $err"; ok=0; }
  assert_payload_contains "$err" "46" "TEST-574: 'gh pr merge --squash --delete-branch 46' deny message does not name PR 46: $err" || ok=0

  # A consistent record for PR 45 (the positional-after-flags form): allowed.
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/append-event.mjs" --event pr_sweep --ref t574-ride \
     --pr 45 --lane heavy --reviewer-bots none --threads-seen 0 --threads-unresolved 0 \
     --outcome internal_substituted >/dev/null)
  err=$(payload_for "gh pr merge --squash 45" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-574: 'gh pr merge --squash 45' with a consistent record exited $rc (want 0): $err"; ok=0; }

  # Bare `gh pr merge` (no positional PR number at all -- the numberless form
  # .aai/SKILL_PR.prompt.md:488 itself documents) resolves the PR from the
  # branch via `gh pr view`. Fake `gh` on PATH so the test never touches the
  # network: pr view -> "47".
  cat > "$d/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  echo "47"
  exit 0
fi
exit 1
GHSTUB
  chmod +x "$d/bin/gh"
  err=$(payload_for "gh pr merge" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: bare 'gh pr merge' (resolved to 47, no record) exited $rc (want 2): $err"; ok=0; }
  assert_payload_contains "$err" "47" "TEST-574: bare 'gh pr merge' deny message does not name the resolved PR 47: $err" || ok=0

  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/append-event.mjs" --event pr_sweep --ref t574-ride \
     --pr 47 --lane heavy --reviewer-bots none --threads-seen 0 --threads-unresolved 0 \
     --outcome internal_substituted >/dev/null)
  err=$(payload_for "gh pr merge" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-574: bare 'gh pr merge' resolved to 47 with a consistent record exited $rc (want 0): $err"; ok=0; }

  # Bare `gh pr merge` when resolution ITSELF fails (fake gh returns nothing
  # usable): denied, naming that neither a positional number nor `gh pr view`
  # identified a PR -- never allowed by default on an unresolvable target.
  cat > "$d/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
exit 1
GHSTUB
  chmod +x "$d/bin/gh"
  err=$(payload_for "gh pr merge" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: bare 'gh pr merge' with unresolvable PR exited $rc (want 2, never allow-by-default)"; ok=0; }
  assert_payload_contains "$err" "could not determine" "TEST-574: unresolvable-PR deny message does not explain why: $err" || ok=0
  rm -f "$d/bin/gh"

  # T3 (validation-round1): a hand-appended record whose OWN lane already
  # matches the branch's computed lane (so the lane-mismatch check above
  # never fires) but whose outcome is illegal for that lane must still be
  # denied -- this is the one property the old outcomeLegalOnLane guarded and
  # no test ever reached (every prior arm was caught one check earlier).
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00.000Z","actor":"t","event":"pr_sweep","ref":"t574-ride","payload":{"pr":48,"lane":"heavy","reviewer_bots":"none","threads_seen":0,"threads_unresolved":0,"outcome":"skipped_fast_lane"}}' >> "$d/docs/ai/EVENTS.jsonl"
  err=$(payload_for "gh pr merge 48 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: lane-matched but outcome-illegal record (PR 48) exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "48" "TEST-574: outcome-illegal deny message does not name PR 48: $err" || ok=0

  # NB-2 (validation-round1): the read side must re-validate the WHOLE
  # record, not just the lane -- a hand-appended line whose lane matches but
  # carries threads_unresolved > 0 alongside outcome: swept must be denied
  # too (before this fix, --sweep-check only ever looked at lane + the one
  # skipped_fast_lane/lane pairing).
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00.000Z","actor":"t","event":"pr_sweep","ref":"t574-ride","payload":{"pr":49,"lane":"heavy","reviewer_bots":"expected","threads_seen":2,"threads_unresolved":7,"outcome":"swept"}}' >> "$d/docs/ai/EVENTS.jsonl"
  err=$(payload_for "gh pr merge 49 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: lane-matched but self-contradictory record (PR 49, threads_unresolved=7 + swept) exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "49" "TEST-574: self-contradictory-record deny message does not name PR 49: $err" || ok=0

  # BLOCKING-1 (code review 20260918T172546Z): a hand-appended record whose
  # outcome is OUTSIDE PR_SWEEP_OUTCOMES must be denied exactly like the
  # writer would refuse it -- reproduces the reviewer's own repro verbatim
  # (a record append-event.mjs would never write used to read SWEEP-CHECK
  # allowed, rc=0, because sweepContradictions had no rule for an unknown
  # outcome and every per-outcome branch fell through as "consistent").
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00.000Z","actor":"t","event":"pr_sweep","ref":"t574-ride","payload":{"pr":50,"lane":"heavy","reviewer_bots":"expected","threads_seen":3,"threads_unresolved":0,"outcome":"totally_fine"}}' >> "$d/docs/ai/EVENTS.jsonl"
  err=$(payload_for "gh pr merge 50 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: unknown-outcome record (PR 50, outcome=totally_fine) exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "50" "TEST-574: unknown-outcome deny message does not name PR 50: $err" || ok=0

  # Same divergence class, the COUNT fields: a hand-appended threads_seen
  # that is not the integer parseSweepCount would ever have written (here a
  # bare string) makes every sweepContradictions numeric comparison coerce
  # to false, the identical NaN-shaped gap B3/validation-round1 closed on
  # the WRITE side -- the read side must refuse it the same way.
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00.000Z","actor":"t","event":"pr_sweep","ref":"t574-ride","payload":{"pr":51,"lane":"heavy","reviewer_bots":"expected","threads_seen":"abc","threads_unresolved":0,"outcome":"swept"}}' >> "$d/docs/ai/EVENTS.jsonl"
  err=$(payload_for "gh pr merge 51 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: non-integer threads_seen record (PR 51) exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "51" "TEST-574: non-integer-threads_seen deny message does not name PR 51: $err" || ok=0

  # And the `pr` field ITSELF: readPrSweepRecords matches records by
  # `Number(payload.pr) === pr`, so a STRING "52" still finds the record
  # (Number("52") === 52) -- sweepContradictions must judge the field's
  # TYPE, not just the numeric value the filter already matched on.
  printf '%s\n' '{"v":1,"ts":"2026-01-01T00:00:00.000Z","actor":"t","event":"pr_sweep","ref":"t574-ride","payload":{"pr":"52","lane":"heavy","reviewer_bots":"expected","threads_seen":3,"threads_unresolved":0,"outcome":"swept"}}' >> "$d/docs/ai/EVENTS.jsonl"
  err=$(payload_for "gh pr merge 52 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-574: string-typed pr field record (PR 52) exited $rc (want 2)"; ok=0; }
  assert_payload_contains "$err" "52" "TEST-574: string-pr deny message does not name PR 52: $err" || ok=0

  # `lane` cannot be reached with an illegal value through this hook path at
  # all (the lane-mismatch check ahead of sweepContradictions already denies
  # anything other than the two values computeLaneVerdict can itself
  # produce) -- but lane-gate.mjs's own header promises ONE predicate for
  # both read and write, so sweepContradictions must judge it directly too,
  # for any future caller that invokes the predicate without that earlier
  # gate. Pinned at the predicate level, not through the hook.
  lane_check=$(cd "$d" && node --input-type=module -e '
    import { sweepContradictions } from "./.aai/scripts/lib/pr-sweep.mjs";
    const bad = sweepContradictions({ pr: 1, lane: "orbit", reviewer_bots: "expected", threads_seen: 1, threads_unresolved: 0, outcome: "swept" });
    process.stdout.write(bad.length > 0 ? "BAD" : "CLEAN");
  ' 2>&1)
  [[ "$lane_check" == "BAD" ]] || { log_info "TEST-574: sweepContradictions does not reject an illegal lane value directly, got: $lane_check"; ok=0; }

  # The hook must call lane-gate.mjs's --sweep-check mode, never restate its
  # predicate (this file's own "never reimplement a predicate here" rule).
  grep -qF "lane-gate.mjs" "$ADAPTER" || { log_info "TEST-574: merge gate does not call lane-gate.mjs"; ok=0; }
  grep -qF -- "--sweep-check" "$ADAPTER" || { log_info "TEST-574: merge gate does not invoke --sweep-check"; ok=0; }
  grep -qE 'ceremony_level|implementation_strategy' "$ADAPTER" \
    && { log_info "TEST-574: the hook appears to restate a lane-gate predicate"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-574 merge gate calls lane-gate.mjs --sweep-check: denies absent/mismatched records, allows a consistent one, fails open on an unreadable EVENTS.jsonl; the PR number is taken from any positional argument or resolved from the branch, never allowed by default when unresolvable; the read side re-validates the whole record" \
                  || log_fail "TEST-574 merge gate sweep-check"
}

# TEST-587 (Spec-AC-34, validation-round2 NB-2): a QUOTED positional PR
# number must be judged against ITSELF, never fall through to branch
# resolution and get judged against a different PR's record.
test_017_merge_gate_quoted_pr_number() {
  [[ -f "$ADAPTER" ]] || { log_fail "TEST-587 $ADAPTER does not exist"; return; }
  local ok=1 d rc err

  d="$(new_fixture)"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/ai" "$d/bin"
  cp "$PROJECT_ROOT/.aai/scripts/lane-gate.mjs" "$d/.aai/scripts/lane-gate.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/cli-pipe-guard.mjs" "$d/.aai/scripts/lib/cli-pipe-guard.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/pr-sweep.mjs" "$d/.aai/scripts/lib/pr-sweep.mjs"
  : > "$d/docs/ai/EVENTS.jsonl"

  # A consistent record exists ONLY for PR 777 (standing in for "whatever PR
  # the current branch would resolve to"), never for PR 385.
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/append-event.mjs" --event pr_sweep --ref t587-ride \
     --pr 777 --lane heavy --reviewer-bots none --threads-seen 0 --threads-unresolved 0 \
     --outcome internal_substituted >/dev/null)
  cat > "$d/bin/gh" <<'GHSTUB'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  echo "777"
  exit 0
fi
exit 1
GHSTUB
  chmod +x "$d/bin/gh"

  # NB-2: a double-quoted bare PR number must be parsed as PR 385, not fall
  # through to branch resolution (which would find 777's consistent record
  # and wrongly ALLOW a merge of PR 385).
  err=$(payload_for 'gh pr merge "385" --squash' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-587: quoted 'gh pr merge \"385\"' exited $rc (want 2, denied against PR 385's own absent record): $err"; ok=0; }
  assert_payload_contains "$err" "385" "TEST-587: the quoted-PR deny message does not name PR 385: $err" || ok=0

  # Same for a single-quoted number.
  err=$(payload_for "gh pr merge '385' --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-587: single-quoted 'gh pr merge '\''385'\''' exited $rc (want 2): $err"; ok=0; }
  assert_payload_contains "$err" "385" "TEST-587: the single-quoted-PR deny message does not name PR 385: $err" || ok=0

  # Control: the UNQUOTED form still works (regression guard for the fix).
  err=$(payload_for "gh pr merge 385 --squash" | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-587: control unquoted 'gh pr merge 385' exited $rc (want 2): $err"; ok=0; }
  assert_payload_contains "$err" "385" "TEST-587: the unquoted-PR control deny message does not name PR 385: $err" || ok=0

  # A quoted PHRASE containing a digit must NOT be taken as the PR number
  # (validation-round1 B2's own control, must survive this fix): quoting
  # digits-only must not widen into quoting-any-token.
  err=$(payload_for 'gh pr merge --subject "fix 123" --squash 385' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 2 ]] || { log_info "TEST-587: '--subject \"fix 123\" --squash 385' exited $rc (want 2, judged against 385 not 123): $err"; ok=0; }
  assert_payload_contains "$err" "385" "TEST-587: a digit inside a quoted PHRASE was taken instead of the real PR 385: $err" || ok=0

  # Now record a consistent record for PR 385: the quoted form allows.
  (cd "$d" && node "$PROJECT_ROOT/.aai/scripts/append-event.mjs" --event pr_sweep --ref t587-ride \
     --pr 385 --lane heavy --reviewer-bots none --threads-seen 0 --threads-unresolved 0 \
     --outcome internal_substituted >/dev/null)
  err=$(payload_for 'gh pr merge "385" --squash' | (cd "$d" && CLAUDE_PROJECT_DIR="$d" PATH="$d/bin:$PATH" AAI_OPERATOR_MERGE=1 bash "$PROJECT_ROOT/$ADAPTER" merge 2>&1 >/dev/null)); rc=$?
  [[ "$rc" -eq 0 ]] || { log_info "TEST-587: quoted 'gh pr merge \"385\"' with a consistent PR-385 record exited $rc (want 0): $err"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-587 (Spec-AC-34, NB-2) a quoted positional PR number is judged against ITSELF, never a different PR resolved from the branch" \
                  || log_fail "TEST-587 merge gate quoted PR number"
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  test_001_template_valid_json
  test_002_template_structure
  test_003_script_conformance
  test_004_fail_open_shape
  test_005_commit_gate
  test_006_merge_gate
  test_007_state_dump_gate
  test_008_fail_open_errors
  test_009_stop_nudge
  test_010_bootstrap_wiring
  test_011_bootstrap_behavior
  test_012_skill_pr_marker
  test_013_repo_uninstalled
  test_014_prompt_diet_floor
  test_015_strict_audit
  test_016_merge_gate_sweep_check
  test_017_merge_gate_quoted_pr_number

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

main "$@"
