#!/usr/bin/env bash
# Platform record and adapter tests (spec-git-platform-detected-at-bootstrap).
# Batch A: TEST-062 (record matrix), TEST-063 (never overwrites), TEST-064 (auth report).
# Batch B: TEST-066 (adapter shapes), TEST-067 (generic skips), TEST-069 (az Windows spawn),
#          TEST-075 (no direct platform calls).
# Batch D: TEST-071 (Azure merge executor), TEST-076 (canon and governance).
# Every fixture lives under ONE private absolute scratch root; gh and az are
# deny-by-default stubs that log every call; PATH holds only stubs plus node and git.
# Usage: test-aai-platform-adapter.sh [test_xxx | TEST-xxx]
set -euo pipefail

case "$0" in /*) HERE="${0%/*}" ;; */*) HERE="$PWD/${0%/*}" ;; *) HERE="$PWD" ;; esac
ROOT="$HERE/../.."
PLATFORM_CLI="$ROOT/.aai/scripts/platform.mjs"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/aai-platform-adapter.XXXXXX")"
[[ -n "$SCRATCH" && "$SCRATCH" = /* && -d "$SCRATCH" ]] || { echo 'FAIL: SETUP scratch root not absolute' >&2; exit 1; }

# A fixture never inherits the runner's identity, hooks or git config.
export GIT_AUTHOR_NAME='AAI Fixture' GIT_AUTHOR_EMAIL='fixture@example.invalid'
export GIT_COMMITTER_NAME='AAI Fixture' GIT_COMMITTER_EMAIL='fixture@example.invalid'
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

cleanup() { [[ -n "${KEEP_TEST_DIR:-}" ]] || rm -rf "$SCRATCH"; }
trap cleanup EXIT

fail() { echo "FAIL: $1 $2" >&2; exit 1; }

NODE_BIN="$(command -v node)"
GIT_BIN="$(command -v git)"
[[ -n "$NODE_BIN" && -n "$GIT_BIN" ]] || { echo 'SKIP: node and git are required' >&2; exit 42; }

# --- stubs ------------------------------------------------------------------
# make_bin <dir> <with_gh 0|1> <with_az 0|1>: a PATH directory holding node,
# git and, on request, the gh and az stubs. The stubs allow exactly the argv
# of D3 (anything else is logged and answered STUB-DENY), log every call to
# GH_LOG / AZ_LOG, and take their exit codes from the environment.
make_bin() {
  local dir="$1" with_gh="$2" with_az="$3"
  [[ -n "$dir" && "$dir" = /* ]] || fail SETUP "make_bin dir not absolute"
  mkdir -p "$dir"
  ln -sf "$NODE_BIN" "$dir/node"
  ln -sf "$GIT_BIN" "$dir/git"
  if [[ "$with_gh" == 1 ]]; then
    cat > "$dir/gh" <<'STUB'
#!/bin/sh
echo "$*" >> "$GH_LOG"
if [ "$*" = "auth status" ]; then exit "${GH_RC:-0}"; fi
echo "STUB-DENY: gh $*" >&2
exit 1
STUB
    chmod +x "$dir/gh"
  fi
  if [[ "$with_az" == 1 ]]; then
    cat > "$dir/az" <<'STUB'
#!/bin/sh
echo "$*" >> "$AZ_LOG"
case "$*" in
  "account show --output json") exit "${AZ_ACCOUNT_RC:-0}" ;;
  "extension show --name azure-devops --output json") exit "${AZ_EXT_RC:-0}" ;;
esac
echo "STUB-DENY: az $*" >&2
exit 1
STUB
    chmod +x "$dir/az"
  fi
}

BIN_BOTH="$SCRATCH/bin-both"; make_bin "$BIN_BOTH" 1 1
BIN_NONE="$SCRATCH/bin-none"; make_bin "$BIN_NONE" 0 0
export GH_LOG="$SCRATCH/gh.log" AZ_LOG="$SCRATCH/az.log"
: > "$GH_LOG"; : > "$AZ_LOG"
reset_logs() { : > "$GH_LOG"; : > "$AZ_LOG"; }

# --- fixtures ---------------------------------------------------------------
FIXTURE_N=0
# mk_repo <origin-url or ''>: sets REPO to a fresh git repo (no command
# substitution: the counter must survive in this shell).
REPO=""
mk_repo() {
  local url="$1" dir
  FIXTURE_N=$((FIXTURE_N + 1))
  dir="$SCRATCH/repo-$FIXTURE_N"
  [[ -n "$dir" && "$dir" = /* ]] || fail SETUP "fixture path not absolute"
  mkdir -p "$dir"
  git -C "$dir" init -q
  if [[ -n "$url" ]]; then git -C "$dir" remote add origin "$url"; fi
  REPO="$dir"
}

# rec <bin-dir> <repo> [record flags...]: runs record, sets REC_OUT and REC_RC.
REC_OUT=""; REC_RC=0
rec() {
  local bin="$1" repo="$2"
  shift 2
  REC_RC=0
  REC_OUT="$(env PATH="$bin" "$NODE_BIN" "$PLATFORM_CLI" record --repo-root "$repo" "$@" 2>&1)" || REC_RC=$?
}

cfg_of() { printf '%s/docs/ai/pr-config.yaml' "$1"; }
seed_cfg() { mkdir -p "$1/docs/ai"; printf '%b' "$2" > "$(cfg_of "$1")"; }
snapshot() { cp "$(cfg_of "$1")" "$SCRATCH/snap.$FIXTURE_N"; }
unchanged() { cmp -s "$(cfg_of "$1")" "$SCRATCH/snap.$FIXTURE_N"; }
count_lines() { local n; n="$(grep -c "$1" "$2" || true)"; printf '%s' "$n"; }

SEED='# keep this comment\nreviewer_bots: expected\n'

test_062_record_matrix() {
  local urls=(
    'https://github.com/acme/foo.git'
    'git@github.com:acme/foo.git'
    'https://dev.azure.com/acme/Proj/_git/foo'
    'git@ssh.dev.azure.com:v3/acme/Proj/foo'
    'https://acme.visualstudio.com/Proj/_git/foo'
    'https://gitlab.com/acme/foo.git'
    ''
  )
  local want=(github github azure azure azure unknown none)
  local i repo cfg
  for i in "${!urls[@]}"; do
    mk_repo "${urls[$i]}"; repo="$REPO"
    cfg="$(cfg_of "$repo")"
    if [[ -n "${urls[$i]}" ]]; then seed_cfg "$repo" "$SEED"; fi
    # dry-run first: nothing is written, WOULD-RECORD is printed
    if [[ -f "$cfg" ]]; then snapshot "$repo"; fi
    rec "$BIN_NONE" "$repo" --dry-run
    [[ "$REC_RC" -eq 0 ]] || fail TEST-062 "dry-run exit $REC_RC for ${urls[$i]:-no-origin}: $REC_OUT"
    case "$REC_OUT" in *"WOULD-RECORD platform=${want[$i]}"*) ;; *) fail TEST-062 "dry-run output lacks WOULD-RECORD platform=${want[$i]}: $REC_OUT" ;; esac
    if [[ -f "$SCRATCH/snap.$FIXTURE_N" && -f "$cfg" ]]; then
      unchanged "$repo" || fail TEST-062 "dry-run changed the file for ${urls[$i]:-no-origin}"
    elif [[ -n "${urls[$i]}" ]]; then
      fail TEST-062 "seeded file vanished under dry-run"
    else
      [[ ! -e "$cfg" ]] || fail TEST-062 "dry-run created $cfg"
    fi
    # the real run
    rec "$BIN_NONE" "$repo"
    [[ "$REC_RC" -eq 0 ]] || fail TEST-062 "record exit $REC_RC for ${urls[$i]:-no-origin}: $REC_OUT"
    [[ "$(count_lines '^platform:' "$cfg")" == 1 ]] || fail TEST-062 "want exactly one platform line in $cfg"
    grep -qx "platform: ${want[$i]}" "$cfg" || fail TEST-062 "want platform: ${want[$i]} for ${urls[$i]:-no-origin}, got: $(cat "$cfg")"
    case "$REC_OUT" in *"RECORDED platform=${want[$i]}"*) ;; *) fail TEST-062 "output lacks RECORDED platform=${want[$i]}: $REC_OUT" ;; esac
    if [[ -n "${urls[$i]}" ]]; then
      # every pre-existing byte survives: the seed is a byte prefix of the result
      printf '%b' "$SEED" > "$SCRATCH/expect"
      printf 'platform: %s\n' "${want[$i]}" >> "$SCRATCH/expect"
      cmp -s "$cfg" "$SCRATCH/expect" || fail TEST-062 "seed bytes not preserved for ${urls[$i]}"
    fi
  done
  echo "PASS: TEST-062 record matrix (Spec-AC-01)"
}

test_063_record_never_overwrites() {
  local repo cfg
  # recorded azure, github origin: MISMATCH, exit 6, byte-identical
  mk_repo 'https://github.com/acme/foo.git'; repo="$REPO"; cfg="$(cfg_of "$repo")"
  seed_cfg "$repo" "$SEED"'platform: azure\n'; snapshot "$repo"
  rec "$BIN_NONE" "$repo"
  [[ "$REC_RC" -eq 6 ]] || fail TEST-063 "mismatch exit want 6 got $REC_RC: $REC_OUT"
  case "$REC_OUT" in *"MISMATCH recorded=azure detected=github"*"record --force"*) ;; *) fail TEST-063 "MISMATCH line wrong: $REC_OUT" ;; esac
  unchanged "$repo" || fail TEST-063 "mismatch changed the file"
  # recorded github, github origin: UNCHANGED
  mk_repo 'https://github.com/acme/foo.git'; repo="$REPO"; seed_cfg "$repo" 'platform: github\n'; snapshot "$repo"
  rec "$BIN_NONE" "$repo"
  [[ "$REC_RC" -eq 0 ]] || fail TEST-063 "equal exit $REC_RC: $REC_OUT"
  case "$REC_OUT" in *"UNCHANGED platform=github"*) ;; *) fail TEST-063 "want UNCHANGED: $REC_OUT" ;; esac
  unchanged "$repo" || fail TEST-063 "equal run changed the file"
  # recorded github, gitlab origin (detected unknown): UNCHANGED
  mk_repo 'https://gitlab.com/acme/foo.git'; repo="$REPO"; seed_cfg "$repo" 'platform: github\n'; snapshot "$repo"
  rec "$BIN_NONE" "$repo"
  [[ "$REC_RC" -eq 0 ]] || fail TEST-063 "unknown exit $REC_RC: $REC_OUT"
  case "$REC_OUT" in *"UNCHANGED platform=github"*) ;; *) fail TEST-063 "want UNCHANGED for unknown: $REC_OUT" ;; esac
  unchanged "$repo" || fail TEST-063 "unknown run changed the file"
  # recorded azure, no origin (detected none): MISMATCH
  mk_repo ''; repo="$REPO"; seed_cfg "$repo" 'platform: azure\n'; snapshot "$repo"
  rec "$BIN_NONE" "$repo"
  [[ "$REC_RC" -eq 6 ]] || fail TEST-063 "none mismatch exit want 6 got $REC_RC: $REC_OUT"
  unchanged "$repo" || fail TEST-063 "none mismatch changed the file"
  # invalid value: MISMATCH, even against an unknown origin
  local origin
  for origin in 'https://github.com/acme/foo.git' 'https://gitlab.com/acme/foo.git'; do
    mk_repo "$origin"; repo="$REPO"; seed_cfg "$repo" 'platform: bogus\n'; snapshot "$repo"
    rec "$BIN_NONE" "$repo"
    [[ "$REC_RC" -eq 6 ]] || fail TEST-063 "invalid exit want 6 got $REC_RC: $REC_OUT"
    case "$REC_OUT" in *"MISMATCH recorded=invalid"*) ;; *) fail TEST-063 "want MISMATCH recorded=invalid: $REC_OUT" ;; esac
    unchanged "$repo" || fail TEST-063 "invalid run changed the file"
  done
  # trailing spaces are trimmed and still valid
  mk_repo 'https://github.com/acme/foo.git'; repo="$REPO"; seed_cfg "$repo" 'platform: github  \n'; snapshot "$repo"
  rec "$BIN_NONE" "$repo"
  [[ "$REC_RC" -eq 0 ]] || fail TEST-063 "trimmed exit $REC_RC: $REC_OUT"
  unchanged "$repo" || fail TEST-063 "trimmed run changed the file"
  # dry-run on a mismatch: same MISMATCH, exit 6, nothing written; with --force: WOULD-RECORD
  mk_repo 'https://github.com/acme/foo.git'; repo="$REPO"; seed_cfg "$repo" 'platform: azure\n'; snapshot "$repo"
  rec "$BIN_NONE" "$repo" --dry-run
  [[ "$REC_RC" -eq 6 ]] || fail TEST-063 "dry-run mismatch exit want 6 got $REC_RC"
  rec "$BIN_NONE" "$repo" --dry-run --force
  [[ "$REC_RC" -eq 0 ]] || fail TEST-063 "dry-run force exit $REC_RC"
  case "$REC_OUT" in *"WOULD-RECORD platform=github"*) ;; *) fail TEST-063 "want WOULD-RECORD: $REC_OUT" ;; esac
  unchanged "$repo" || fail TEST-063 "dry-run force changed the file"
  # --force rewrites only the platform line
  mk_repo 'https://github.com/acme/foo.git'; repo="$REPO"; cfg="$(cfg_of "$repo")"
  seed_cfg "$repo" '# c\nreviewer_bots: expected\nplatform: azure\nother: x\n'
  rec "$BIN_NONE" "$repo" --force
  [[ "$REC_RC" -eq 0 ]] || fail TEST-063 "force exit $REC_RC: $REC_OUT"
  case "$REC_OUT" in *"RECORDED platform=github (was azure)"*) ;; *) fail TEST-063 "want RECORDED (was azure): $REC_OUT" ;; esac
  printf '%b' '# c\nreviewer_bots: expected\nplatform: github\nother: x\n' > "$SCRATCH/expect"
  cmp -s "$cfg" "$SCRATCH/expect" || fail TEST-063 "force changed more than the platform line: $(cat "$cfg")"
  # CRLF file: the force rewrite keeps the line ending
  mk_repo 'https://github.com/acme/foo.git'; repo="$REPO"; cfg="$(cfg_of "$repo")"
  seed_cfg "$repo" 'reviewer_bots: none\r\nplatform: azure\r\nother: x\r\n'
  rec "$BIN_NONE" "$repo" --force
  [[ "$REC_RC" -eq 0 ]] || fail TEST-063 "crlf force exit $REC_RC: $REC_OUT"
  printf '%b' 'reviewer_bots: none\r\nplatform: github\r\nother: x\r\n' > "$SCRATCH/expect"
  cmp -s "$cfg" "$SCRATCH/expect" || fail TEST-063 "crlf line ending lost"
  echo "PASS: TEST-063 record never overwrites silently (Spec-AC-02)"
}

# arm <label> <origin> <bin-dir> <env assignments...>: one fresh repo, one record run.
# Sets ARM_RC, ARM_OUT, ARM_CFG_SUM.
ARM_RC=0; ARM_OUT=""; ARM_CFG_SUM=""
arm() {
  local origin="$1" bin="$2" repo
  shift 2
  mk_repo "$origin"; repo="$REPO"
  reset_logs
  ARM_RC=0
  ARM_OUT="$(env PATH="$bin" "$@" "$NODE_BIN" "$PLATFORM_CLI" record --repo-root "$repo" 2>&1)" || ARM_RC=$?
  ARM_CFG_SUM="$(cksum < "$(cfg_of "$repo")")"
}

auth_line() {
  local n
  n="$(printf '%s\n' "$ARM_OUT" | grep -c '^AUTH ' || true)"
  [[ "$n" == 1 ]] || fail TEST-064 "want exactly one AUTH line, got $n: $ARM_OUT"
  printf '%s\n' "$ARM_OUT" | grep '^AUTH '
}

test_064_auth_report() {
  local gh_origin='https://github.com/acme/foo.git' az_origin='https://dev.azure.com/acme/Proj/_git/foo'
  local ok_rc ok_sum
  # github: ok, exact argv
  arm "$gh_origin" "$BIN_BOTH"
  [[ "$(auth_line)" == "AUTH github ok" ]] || fail TEST-064 "github ok: $ARM_OUT"
  [[ "$(cat "$GH_LOG")" == "auth status" ]] || fail TEST-064 "gh log want exactly 'auth status': $(cat "$GH_LOG")"
  [[ ! -s "$AZ_LOG" ]] || fail TEST-064 "github arm spawned az"
  ok_rc="$ARM_RC"; ok_sum="$ARM_CFG_SUM"
  # github: unauthenticated, same exit code and file
  arm "$gh_origin" "$BIN_BOTH" GH_RC=1
  [[ "$(auth_line)" == "AUTH github unauthenticated" ]] || fail TEST-064 "github unauthenticated: $ARM_OUT"
  [[ "$ARM_RC" == "$ok_rc" && "$ARM_CFG_SUM" == "$ok_sum" ]] || fail TEST-064 "github unauthenticated changed exit code or file"
  # github: binary missing
  arm "$gh_origin" "$BIN_NONE"
  [[ "$(auth_line)" == "AUTH github cli_missing" ]] || fail TEST-064 "github cli_missing: $ARM_OUT"
  [[ "$ARM_RC" == "$ok_rc" && "$ARM_CFG_SUM" == "$ok_sum" ]] || fail TEST-064 "github cli_missing changed exit code or file"
  # azure: ok, exact argv and order
  arm "$az_origin" "$BIN_BOTH"
  [[ "$(auth_line)" == "AUTH azure ok" ]] || fail TEST-064 "azure ok: $ARM_OUT"
  [[ "$(cat "$AZ_LOG")" == "$(printf 'account show --output json\nextension show --name azure-devops --output json')" ]] \
    || fail TEST-064 "az log wrong: $(cat "$AZ_LOG")"
  [[ ! -s "$GH_LOG" ]] || fail TEST-064 "azure arm spawned gh"
  ok_rc="$ARM_RC"; ok_sum="$ARM_CFG_SUM"
  # azure: account read fails -> unauthenticated, extension never read
  arm "$az_origin" "$BIN_BOTH" AZ_ACCOUNT_RC=1
  [[ "$(auth_line)" == "AUTH azure unauthenticated" ]] || fail TEST-064 "azure unauthenticated: $ARM_OUT"
  [[ "$(cat "$AZ_LOG")" == "account show --output json" ]] || fail TEST-064 "az log after failed account read: $(cat "$AZ_LOG")"
  [[ "$ARM_RC" == "$ok_rc" && "$ARM_CFG_SUM" == "$ok_sum" ]] || fail TEST-064 "azure unauthenticated changed exit code or file"
  # azure: extension read fails -> extension_missing
  arm "$az_origin" "$BIN_BOTH" AZ_EXT_RC=1
  [[ "$(auth_line)" == "AUTH azure extension_missing" ]] || fail TEST-064 "azure extension_missing: $ARM_OUT"
  [[ "$ARM_RC" == "$ok_rc" && "$ARM_CFG_SUM" == "$ok_sum" ]] || fail TEST-064 "azure extension_missing changed exit code or file"
  # azure: binary missing
  arm "$az_origin" "$BIN_NONE"
  [[ "$(auth_line)" == "AUTH azure cli_missing" ]] || fail TEST-064 "azure cli_missing: $ARM_OUT"
  [[ "$ARM_RC" == "$ok_rc" && "$ARM_CFG_SUM" == "$ok_sum" ]] || fail TEST-064 "azure cli_missing changed exit code or file"
  # unknown and none: nothing spawned, skipped
  arm 'https://gitlab.com/acme/foo.git' "$BIN_BOTH"
  [[ "$(auth_line)" == "AUTH unknown skipped" ]] || fail TEST-064 "unknown: $ARM_OUT"
  [[ ! -s "$GH_LOG" && ! -s "$AZ_LOG" ]] || fail TEST-064 "unknown arm spawned a CLI"
  arm '' "$BIN_BOTH"
  [[ "$(auth_line)" == "AUTH none skipped" ]] || fail TEST-064 "none: $ARM_OUT"
  [[ ! -s "$GH_LOG" && ! -s "$AZ_LOG" ]] || fail TEST-064 "none arm spawned a CLI"
  echo "PASS: TEST-064 auth report (Spec-AC-03)"
}

# --- batch B: table stubs and node harnesses ---------------------------------
# make_table_bin <dir>: node, git and gh/az stubs that answer ONLY the exact argv
# listed in $GH_TABLE / $AZ_TABLE (lines: argv<TAB>stdout-file or -<TAB>rc), log every
# call to GH_LOG / AZ_LOG and deny everything else. Builtins only, so the PATH
# can stay stubs-plus-node.
make_table_bin() {
  local dir="$1" tool up
  [[ -n "$dir" && "$dir" = /* ]] || fail SETUP "make_table_bin dir not absolute"
  mkdir -p "$dir"
  ln -sf "$NODE_BIN" "$dir/node"
  ln -sf "$GIT_BIN" "$dir/git"
  for tool in gh az; do
    up="$(printf '%s' "$tool" | tr 'a-z' 'A-Z')"
    cat > "$dir/$tool" <<STUB
#!/bin/sh
echo "\$*" >> "\$${up}_LOG"
while IFS="	" read -r key file rc; do
  if [ "\$key" = "\$*" ]; then
    if [ "\$file" != "-" ]; then while IFS= read -r l || [ -n "\$l" ]; do printf '%s\\n' "\$l"; done < "\$file"; fi
    exit "\${rc:-0}"
  fi
done < "\$${up}_TABLE"
echo "STUB-DENY: $tool \$*" >&2
exit 1
STUB
    chmod +x "$dir/$tool"
  done
}
BIN_TABLE="$SCRATCH/bin-table"; make_table_bin "$BIN_TABLE"
export GH_TABLE="$SCRATCH/gh.table" AZ_TABLE="$SCRATCH/az.table"
: > "$GH_TABLE"; : > "$AZ_TABLE"

# run_harness <test-id> <file>: runs a node harness with the stub PATH; the
# harness asserts on its own and prints HARNESS-OK.
run_harness() {
  local id="$1" file="$2" out rc=0
  [[ -n "$file" && "$file" = /* && -f "$file" ]] || fail "$id" "harness missing"
  out="$(env PATH="$BIN_TABLE" GH_LOG="$GH_LOG" AZ_LOG="$AZ_LOG" GH_TABLE="$GH_TABLE" AZ_TABLE="$AZ_TABLE" \
    "$NODE_BIN" "$file" "$ROOT" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail "$id" "harness exit $rc: $out"
  case "$out" in *"HARNESS-OK"*) ;; *) fail "$id" "harness did not finish: $out" ;; esac
}

write_stubkit() {
  cat > "$SCRATCH/stubkit.mjs" <<'KIT'
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
export { assert };
export const ROOT = path.resolve(process.argv[2]);
export const adapterUrl = 'file://' + path.join(ROOT, '.aai/scripts/lib/platform-adapter.mjs');
const TMP = path.dirname(process.env.GH_TABLE);
let seq = 0;
// stub('gh'|'az', [[argvArray, stdout (string|object|null), rc]...]): replaces the table, clears the log.
export function stub(tool, entries) {
  const lines = entries.map(([argv, out, rc]) => {
    let file = '-';
    if (out !== null && out !== undefined) {
      file = path.join(TMP, `fx-${++seq}.json`);
      fs.writeFileSync(file, typeof out === 'string' ? out : JSON.stringify(out));
    }
    return `${argv.join(' ')}\t${file}\t${rc ?? 0}`;
  });
  fs.writeFileSync(process.env[`${tool.toUpperCase()}_TABLE`], lines.join('\n') + (lines.length ? '\n' : ''));
  fs.writeFileSync(process.env[`${tool.toUpperCase()}_LOG`], '');
}
export const log = (tool) => fs.readFileSync(process.env[`${tool.toUpperCase()}_LOG`], 'utf8').split('\n').filter(Boolean);
KIT
}

write_harness_066() {
  cat > "$SCRATCH/harness-066.mjs" <<'H066'
import { stub, log, assert, adapterUrl } from './stubkit.mjs';
const { createAdapter, PR_FIELDS } = await import(adapterUrl);
const SHA = 'a'.repeat(40), MC = 'b'.repeat(40);

// ---- GitHub: argv byte-identical to today's engine (F3/D7)
const gh = createAdapter('github', { cwd: process.cwd() });
const VIEW = ['pr', 'view', '7', '--json', PR_FIELDS];
const ghPr = { number: 7, state: 'OPEN', isDraft: false, headRefOid: SHA, headRefName: 'ride/foo', baseRefName: 'main', mergeCommit: null, url: 'https://github.com/acme/foo/pull/7', isCrossRepository: false };
stub('gh', [[VIEW, ghPr]]);
assert.deepEqual(gh.prView(7), { ok: true, value: ghPr });
assert.deepEqual(log('gh'), [VIEW.join(' ')]);
stub('gh', [[VIEW, null, 1]]);
assert.deepEqual(gh.prView(7), { ok: false, reason: 'read_failed', detail: 'gh pr view 7' });
stub('gh', [[VIEW, 'not json']]);
assert.deepEqual(gh.prView(7), { ok: false, reason: 'read_invalid', detail: 'gh pr view printed no JSON' });
const LB = ['pr', 'list', '--state', 'open', '--base', 'ride/foo', '--json', 'number', '--limit', '100'];
const LH = ['pr', 'list', '--state', 'open', '--head', 'ride/foo', '--json', 'number', '--limit', '100'];
stub('gh', [[LB, [{ number: 3 }, { number: 4 }]], [LH, []]]);
assert.deepEqual(gh.listDependents('ride/foo', 'base'), { ok: true, value: [3, 4] });
assert.deepEqual(gh.listDependents('ride/foo', 'head'), { ok: true, value: [] });
assert.deepEqual(log('gh'), [LB.join(' '), LH.join(' ')]);
stub('gh', [[LB, [{ number: 'x' }]]]);
assert.equal(gh.listDependents('ride/foo', 'base').reason, 'read_invalid');
stub('gh', [[LB, null, 1]]);
assert.equal(gh.listDependents('ride/foo', 'base').reason, 'read_failed');
const QUERY = 'query($owner: String!, $repo: String!, $pr: Int!, $endCursor: String) { repository(owner: $owner, name: $repo) { pullRequest(number: $pr) { reviewThreads(first: 100, after: $endCursor) { pageInfo { hasNextPage endCursor } nodes { isResolved isOutdated comments(first: 10) { nodes { body author { login } path line } } } } } } }';
const API = ['api', 'graphql', '--paginate', '--slurp', '--hostname', 'github.com', '-F', 'owner=acme', '-F', 'repo=foo', '-F', 'pr=7', '-f', `query=${QUERY}`];
const pages = [{ data: { repository: { pullRequest: { reviewThreads: { nodes: [
  { isResolved: true, comments: { nodes: [{ body: 'ok', author: { login: 'a' } }] } },
  { isResolved: false, comments: { nodes: [{ body: 'fix this', author: { login: 'bot' }, path: 'x.js', line: 3 }] } },
] } } } } }];
stub('gh', [[API, pages]]);
let t = gh.reviewThreads(7, ghPr);
assert.equal(t.ok, true); assert.equal(t.value.unresolvedCount, 1); assert.match(t.value.details, /bot \(x\.js:3\): fix this/);
assert.deepEqual(log('gh'), [API.join(' ')]);
stub('gh', [[API, null, 1]]);
assert.deepEqual(gh.reviewThreads(7, ghPr), { ok: false, reason: 'read_failed', detail: 'gh api review-threads 7' });
assert.equal(gh.mergeCommand(7, SHA, '/x'), `AAI_OPERATOR_MERGE=1 gh pr merge 7 --squash --match-head-commit ${SHA}`);
assert.equal(gh.repoMatches('https://github.com/Acme/Foo.git', ghPr).ok, true);
assert.equal(gh.repoMatches('https://github.com/other/foo.git', ghPr).reason, 'repo_mismatch');
assert.equal(gh.repoMatches('/local/path', ghPr).ok, true);

// ---- Azure: exactly the A1 to A4 argv of D8
stub('gh', []);
const az = createAdapter('azure', { cwd: process.cwd() });
const A1 = ['repos', 'pr', 'show', '--id', '9', '--detect', 'true', '--output', 'json'];
const repo = { id: 'repo-guid', url: 'https://dev.azure.com/Acme/proj-guid/_apis/git/repositories/repo-guid', webUrl: 'https://dev.azure.com/Acme/My%20Proj/_git/Foo', project: { id: 'proj-guid' } };
const azPr = (o) => ({ pullRequestId: 9, status: 'active', isDraft: false, sourceRefName: 'refs/heads/ride/foo', targetRefName: 'refs/heads/main', lastMergeSourceCommit: { commitId: SHA }, lastMergeCommit: { commitId: MC }, repository: repo, ...o });
const view = (o) => { stub('az', [[A1, azPr(o)]]); const r = az.prView(9); assert.deepEqual(log('az'), [A1.join(' ')]); return r; };
let r = view({});
assert.equal(r.ok, true);
assert.deepEqual({ ...r.value, azure: undefined }, { number: 9, state: 'OPEN', isDraft: false, headRefOid: SHA, headRefName: 'ride/foo', baseRefName: 'main', mergeCommit: null, url: 'https://dev.azure.com/Acme/My%20Proj/_git/Foo/pullrequest/9', isCrossRepository: false, azure: undefined });
assert.deepEqual(r.value.azure, { orgUrl: 'https://dev.azure.com/Acme', projectId: 'proj-guid', repositoryId: 'repo-guid' });
r = view({ status: 'completed' });
assert.equal(r.value.state, 'MERGED'); assert.deepEqual(r.value.mergeCommit, { oid: MC });
r = view({ status: 'abandoned' }); assert.equal(r.value.state, 'CLOSED'); assert.equal(r.value.mergeCommit, null);
r = view({ status: 'mystery' }); assert.equal(r.value.state, 'CLOSED');
r = view({ status: 'active', lastMergeCommit: { commitId: MC } }); assert.equal(r.value.mergeCommit, null);
r = view({ isDraft: true }); assert.equal(r.value.isDraft, true);
r = view({ forkSource: { repository: { id: 'x' } } }); assert.equal(r.value.isCrossRepository, true);
r = view({ sourceRefName: 'feature', targetRefName: 'refs/heads/refs/heads/x' });
assert.equal(r.value.headRefName, 'feature'); assert.equal(r.value.baseRefName, 'refs/heads/x');
r = view({ lastMergeSourceCommit: { commitId: 'c'.repeat(40) }, lastMergeCommit: { commitId: 'd'.repeat(40) } });
assert.equal(r.value.headRefOid, 'c'.repeat(40));
stub('az', [[A1, '{broken']]); assert.deepEqual(az.prView(9), { ok: false, reason: 'read_invalid', detail: 'az repos pr show printed no JSON' });
stub('az', [[A1, '[]']]); assert.equal(az.prView(9).reason, 'read_invalid');
stub('az', [[A1, null, 1]]); assert.deepEqual(az.prView(9), { ok: false, reason: 'read_failed', detail: 'az repos pr show 9' });
assert.deepEqual(log('gh'), [], 'azure never spawns gh');

const A2 = ['repos', 'pr', 'list', '--status', 'active', '--target-branch', 'ride/foo', '--top', '100', '--detect', 'true', '--output', 'json'];
const A3 = ['repos', 'pr', 'list', '--status', 'active', '--source-branch', 'ride/foo', '--top', '100', '--detect', 'true', '--output', 'json'];
stub('az', [[A2, [{ pullRequestId: 11 }, { pullRequestId: 12 }]], [A3, []]]);
assert.deepEqual(az.listDependents('ride/foo', 'base'), { ok: true, value: [11, 12] });
assert.deepEqual(az.listDependents('ride/foo', 'head'), { ok: true, value: [] });
assert.deepEqual(log('az'), [A2.join(' '), A3.join(' ')]);
stub('az', [[A2, [{ pullRequestId: 'x' }]]]); assert.equal(az.listDependents('ride/foo', 'base').reason, 'read_invalid');
stub('az', [[A2, null, 1]]); assert.equal(az.listDependents('ride/foo', 'base').reason, 'read_failed');

const A4 = ['devops', 'invoke', '--area', 'git', '--resource', 'pullRequestThreads', '--route-parameters', 'project=proj-guid', 'repositoryId=repo-guid', 'pullRequestId=9', '--org', 'https://dev.azure.com/Acme', '--api-version', '7.1', '--http-method', 'GET', '--output', 'json'];
const prv = view({}).value;
const th = (status, extra = {}) => ({ status, comments: [{ content: `c-${status}`, author: { displayName: 'rev' } }], ...extra });
stub('az', [[A4, { value: [th('active'), th('pending'), th('closed'), th('fixed'), th('wontFix'), th('byDesign'), { comments: [{ content: 'system' }] }, th('active', { isDeleted: true })] }]]);
t = az.reviewThreads(9, prv);
assert.equal(t.ok, true); assert.equal(t.value.unresolvedCount, 2);
assert.match(t.value.details, /c-active/); assert.match(t.value.details, /c-pending/); assert.doesNotMatch(t.value.details, /c-closed/);
assert.deepEqual(log('az'), [A4.join(' ')]);
stub('az', [[A4, { count: 0 }]]); assert.equal(az.reviewThreads(9, prv).reason, 'read_invalid');
stub('az', [[A4, 'nope']]); assert.equal(az.reviewThreads(9, prv).reason, 'read_invalid');
stub('az', [[A4, null, 1]]); assert.equal(az.reviewThreads(9, prv).reason, 'read_failed');
assert.equal(az.mergeCommand(9, SHA, '/opt/aai/.aai/scripts'), `AAI_OPERATOR_MERGE=1 node "/opt/aai/.aai/scripts/platform.mjs" merge --pr 9 --expect-head ${SHA}`);
for (const o of ['https://dev.azure.com/acme/My%20Proj/_git/foo', 'https://acme@dev.azure.com/Acme/My%20Proj/_git/Foo', 'git@ssh.dev.azure.com:v3/Acme/My%20Proj/Foo', 'https://acme.visualstudio.com/DefaultCollection/My%20Proj/_git/foo']) {
  assert.equal(az.repoMatches(o, prv).ok, true, o);
}
assert.equal(az.repoMatches('https://dev.azure.com/acme/other/_git/foo', prv).reason, 'repo_mismatch');
assert.equal(az.repoMatches('/local/bare', prv).ok, true);
console.log('HARNESS-OK 066');
H066
}

test_066_adapter_shapes() {
  write_stubkit; write_harness_066
  reset_logs
  run_harness TEST-066 "$SCRATCH/harness-066.mjs"
  echo "PASS: TEST-066 adapter shapes (Spec-AC-05)"
}

write_harness_067() {
  cat > "$SCRATCH/harness-067.mjs" <<'H067'
import { stub, log, assert, adapterUrl } from './stubkit.mjs';
const { createAdapter, PR_FIELDS } = await import(adapterUrl);
const calls = (a) => [
  ['prView', () => a.prView(7)],
  ['listDependents', () => a.listDependents('ride/foo', 'base')],
  ['reviewThreads', () => a.reviewThreads(7, { url: 'https://github.com/acme/foo/pull/7' })],
  ['repoMatches', () => a.repoMatches('https://github.com/acme/foo', { url: 'https://github.com/acme/foo/pull/7' })],
  ['mergeCommand', () => a.mergeCommand(7, 'a'.repeat(40), '/x')],
];
for (const platform of ['unknown', 'none']) {
  stub('gh', [[['pr', 'view', '7', '--json', PR_FIELDS], { number: 7 }]]);
  stub('az', []);
  const a = createAdapter(platform, { cwd: process.cwd() });
  for (const [op, fn] of calls(a)) {
    const r = fn();
    assert.equal(r.skip, true, `${platform} ${op} skips`);
    assert.equal(r.reason, 'platform_generic');
    assert.equal(r.op, op);
    assert.equal(typeof r.manual, 'string'); assert.ok(r.manual.length > 10, 'manual text non-empty');
    assert.equal('ok' in r, false);
  }
  assert.equal(a.authStatus(), 'skipped');
  assert.deepEqual(log('gh'), [], `${platform} spawned gh`);
  assert.deepEqual(log('az'), [], `${platform} spawned az`);
}
// positive control: the same harness on github spawns exactly one call
stub('gh', [[['pr', 'view', '7', '--json', PR_FIELDS], { number: 7 }]]);
const g = createAdapter('github', { cwd: process.cwd() });
assert.equal(g.prView(7).ok, true);
assert.equal(log('gh').length, 1);
console.log('HARNESS-OK 067');
H067
}

test_067_generic_named_skips() {
  write_stubkit; write_harness_067
  reset_logs
  run_harness TEST-067 "$SCRATCH/harness-067.mjs"
  echo "PASS: TEST-067 generic named skips (Spec-AC-06, adapter arm)"
}

write_harness_069() {
  cat > "$SCRATCH/harness-069.mjs" <<'H069'
import { stub, log, assert, adapterUrl } from './stubkit.mjs';
const { azSpawnSpec, authStatus, createAdapter } = await import(adapterUrl);
const args = ['repos', 'pr', 'show', '--id', '9', '--org', 'https://dev.azure.com/Acme', '--route-parameters', 'project=a-b_c.d', 'refs/heads/ride/foo@x'];
for (const p of ['darwin', 'linux']) assert.deepEqual(azSpawnSpec(args, p), { cmd: 'az', args });
const savedComSpec = process.env.ComSpec;
process.env.ComSpec = 'C:\\Windows\\System32\\cmd.exe';
const { env: winEnv, ...winSpec } = azSpawnSpec(args, 'win32');
assert.deepEqual(winSpec, { cmd: 'C:\\Windows\\System32\\cmd.exe', args: ['/d', '/s', '/c', 'az', ...args] });
// NB-3: cmd.exe would resolve az from the current directory before PATH; the spec's env switches that off
assert.equal(winEnv.NoDefaultCurrentDirectoryInExePath, '1');
assert.equal(winEnv.PATH ?? winEnv.Path, process.env.PATH ?? process.env.Path, 'win32 env must keep the parent environment');
delete process.env.ComSpec;
const { env: winEnv2, ...winSpec2 } = azSpawnSpec(['account', 'show'], 'win32');
assert.deepEqual(winSpec2, { cmd: 'cmd.exe', args: ['/d', '/s', '/c', 'az', 'account', 'show'] });
assert.equal(winEnv2.NoDefaultCurrentDirectoryInExePath, '1');
if (savedComSpec !== undefined) process.env.ComSpec = savedComSpec;
for (const unsafe of ['a b', 'say"hi', 'a&b', '100%', 'a^b', 'x|y', 'a;b', '$(x)', '']) {
  const r = azSpawnSpec(['repos', unsafe], 'win32');
  assert.equal(r.refused, 'az_arg_unsafe', JSON.stringify(unsafe));
  assert.equal(r.cmd, undefined);
}
// off Windows no shell is involved, so the same argument passes through unchanged
assert.deepEqual(azSpawnSpec(['repos', 'a b'], 'linux'), { cmd: 'az', args: ['repos', 'a b'] });

// routing: the auth probe and the adapter reads spawn through the spec, and a refused arg never spawns
const seen = [];
const opts = [];
const runner = (cmd, a, o) => { seen.push([cmd, a]); opts.push(o); return { status: 0, stdout: '[]' }; };
assert.equal(authStatus('azure', { runner, hostPlatform: 'win32' }), 'ok');
assert.equal(seen.length, 2);
for (const o of opts) assert.equal(o.env?.NoDefaultCurrentDirectoryInExePath, '1', 'auth probe spawned without the cwd-lookup guard');
for (const [cmd, a] of seen) { assert.equal(cmd, process.env.ComSpec || 'cmd.exe'); assert.deepEqual(a.slice(0, 4), ['/d', '/s', '/c', 'az']); }
seen.length = 0; opts.length = 0;
assert.equal(authStatus('azure', { runner, hostPlatform: 'linux' }), 'ok');
assert.deepEqual(seen.map(([c]) => c), ['az', 'az']);
for (const o of opts) assert.equal(o.env, undefined, 'off Windows the spawn env is the inherited one');
seen.length = 0;
authStatus('github', { runner, hostPlatform: 'win32' });
assert.deepEqual(seen, [['gh', ['auth', 'status']]]);
seen.length = 0;
const win = createAdapter('azure', { cwd: process.cwd(), runner, hostPlatform: 'win32' });
const refused = win.listDependents('bad branch', 'base');
assert.equal(refused.ok, false); assert.equal(refused.reason, 'az_arg_unsafe');
assert.equal(seen.length, 0, 'unsafe argument spawned');
opts.length = 0;
win.listDependents('ride/foo', 'base');
assert.equal(seen.length, 1); assert.equal(seen[0][1][3], 'az');
assert.equal(opts[0].env?.NoDefaultCurrentDirectoryInExePath, '1', 'adapter read spawned without the cwd-lookup guard');
stub('az', []); stub('gh', []);
assert.deepEqual(log('az'), []);
console.log('HARNESS-OK 069');
H069
}

test_069_az_windows_spawn_spec() {
  write_stubkit; write_harness_069
  reset_logs
  run_harness TEST-069 "$SCRATCH/harness-069.mjs"
  echo "PASS: TEST-069 az windows spawn spec (Spec-AC-07)"
}

test_075_no_direct_platform_calls() {
  local chk="$ROOT/tests/skills/lib/platform-direct-calls.mjs" mc="$ROOT/.aai/scripts/merge-cleanup.mjs"
  local out rc n base
  [[ -f "$chk" && -f "$mc" ]] || fail TEST-075 "checker or merge-cleanup.mjs missing"
  # a clean synthetic consumer: comments that mention the commands must be skipped
  local clean="$SCRATCH/consumer-clean.mjs"
  cat > "$clean" <<'EOF'
// talks about gh pr merge and az repos in a comment only
import { createAdapter } from './adapter.mjs';
/* a block comment naming gh api
   and az devops over two lines */
const adapter = createAdapter('github', {});
export const read = (n) => adapter.prView(n);
EOF
  rc=0; out="$("$NODE_BIN" "$chk" "$clean" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-075 "clean consumer exit $rc: $out"
  case "$out" in *"PLATFORM-CALLS clean 1 files"*) ;; *) fail TEST-075 "clean consumer output: $out" ;; esac
  # positive control: four injected direct calls are all listed, nothing else is
  base="$(wc -l < "$clean")"; base=$((base + 0))
  local inj="$SCRATCH/consumer-injected.mjs"
  cp "$clean" "$inj"
  cat >> "$inj" <<'EOF'
spawnSync('gh', ['pr', 'view']);
spawnSync('az', ['repos', 'pr', 'show']);
execFileSync("gh", ['api']);
const cmd = `AAI_OPERATOR_MERGE=1 gh pr merge ${n}`;
EOF
  rc=0; out="$("$NODE_BIN" "$chk" "$inj" 2>&1)" || rc=$?
  [[ "$rc" -eq 1 ]] || fail TEST-075 "injected consumer exit want 1 got $rc: $out"
  for n in 1 2 3 4; do
    case "$out" in *"consumer-injected.mjs:$((base + n)):"*) ;; *) fail TEST-075 "injected line $((base + n)) not listed: $out" ;; esac
  done
  [[ "$(printf '%s\n' "$out" | grep -c 'consumer-injected.mjs:' || true)" == 4 ]] || fail TEST-075 "want exactly four listed lines: $out"
  # merge-cleanup.mjs must import the adapter and be clean (batch C): the arm is mandatory.
  grep -q 'platform-adapter' "$mc" || fail TEST-075 "merge-cleanup.mjs does not import the platform adapter"
  rc=0; out="$("$NODE_BIN" "$chk" "$mc" 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-075 "merge-cleanup.mjs still names a platform CLI: $out"
  case "$out" in *"PLATFORM-CALLS clean"*) ;; *) fail TEST-075 "merge-cleanup output: $out" ;; esac
  local mcn mcinj="$SCRATCH/merge-cleanup-injected.mjs"
  mcn="$(wc -l < "$mc")"; mcn=$((mcn + 0))
  cp "$mc" "$mcinj"
  # the copy may lack a trailing newline: the injected lines start on their own line
  printf '\n' >> "$mcinj"; mcn=$((mcn + 1))
  cat >> "$mcinj" <<'EOF'
spawnSync('gh', ['pr', 'view']);
spawnSync('az', ['repos', 'pr', 'show']);
execFileSync("gh", ['api']);
const injected = `AAI_OPERATOR_MERGE=1 gh pr merge ${n}`;
EOF
  rc=0; out="$("$NODE_BIN" "$chk" "$mcinj" 2>&1)" || rc=$?
  [[ "$rc" -eq 1 ]] || fail TEST-075 "injected merge-cleanup copy exit want 1 got $rc"
  for n in 1 2 3 4; do
    case "$out" in *"merge-cleanup-injected.mjs:$((mcn + n)):"*) ;; *) fail TEST-075 "injected merge-cleanup line $((mcn + n)) not listed: $out" ;; esac
  done
  echo "PASS: TEST-075 no direct platform calls (Spec-AC-13), merge-cleanup.mjs armed and clean"
}

# --- batch D: Azure merge executor (TEST-071) and canon plus governance (TEST-076) ---
SHA_A='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
SHA_B='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
SHA_M='cccccccccccccccccccccccccccccccccccccccc'
AZ_URL='https://dev.azure.com/acme/Proj/_git/foo'

# make_merge_bin <dir>: az stub that serves exactly A1 (the n-th call reads
# $AZ_STATE/a1.<n>.json) and A5 (exit AZ_A5_RC, stderr from AZ_A5_ERR); every
# other argv is logged and denied. gh is a denying stub that logs.
make_merge_bin() {
  local dir="$1"
  [[ -n "$dir" && "$dir" = /* ]] || fail SETUP "make_merge_bin dir not absolute"
  mkdir -p "$dir"
  ln -sf "$NODE_BIN" "$dir/node"
  ln -sf "$GIT_BIN" "$dir/git"
  cat > "$dir/az" <<'STUB'
#!/bin/sh
echo "$*" >> "$AZ_LOG"
case "$*" in
  "repos pr show --id 7 --detect true --output json")
    n=0; [ -f "$AZ_STATE/a1n" ] && read -r n < "$AZ_STATE/a1n"
    n=$((n + 1)); echo "$n" > "$AZ_STATE/a1n"
    if [ -f "$AZ_STATE/a1.$n.json" ]; then
      while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "$l"; done < "$AZ_STATE/a1.$n.json"; exit 0
    fi
    echo "STUB-DENY: no scripted A1 read $n" >&2; exit 1 ;;
  "repos pr update --id 7 --status completed --squash true --delete-source-branch false --detect true --output json")
    if [ "${AZ_A5_RC:-0}" != 0 ]; then echo "${AZ_A5_ERR:-update failed}" >&2; exit "$AZ_A5_RC"; fi
    echo '{}'; exit 0 ;;
esac
echo "STUB-DENY: az $*" >&2
exit 1
STUB
  chmod +x "$dir/az"
  cat > "$dir/gh" <<'STUB'
#!/bin/sh
echo "$*" >> "$GH_LOG"
echo "STUB-DENY: gh $*" >&2
exit 1
STUB
  chmod +x "$dir/gh"
}

# az_pr_json <status> <head> <mergeCommit or ''>: one A1 answer.
az_pr_json() {
  local status="$1" head="$2" mc="$3" lm=''
  if [[ -n "$mc" ]]; then lm=",\"lastMergeCommit\":{\"commitId\":\"$mc\"}"; fi
  printf '{"pullRequestId":7,"status":"%s","isDraft":false,"sourceRefName":"refs/heads/ride","targetRefName":"refs/heads/main","lastMergeSourceCommit":{"commitId":"%s"}%s,"repository":{"id":"r1","name":"foo","webUrl":"%s","url":"https://dev.azure.com/acme/p1/_apis/git/repositories/r1","project":{"id":"p1"}}}\n' \
    "$status" "$head" "$lm" "$AZ_URL"
}

# merge_arm <repo> <operator 0|1> <expect-sha> <a5-rc> <a1 json>...: sets M_OUT, M_RC.
M_OUT=""; M_RC=0
merge_arm() {
  local repo="$1" op="$2" expect="$3" a5rc="$4" i=0 j
  shift 4
  rm -rf "$SCRATCH/azstate"; mkdir -p "$SCRATCH/azstate"
  for j in "$@"; do i=$((i + 1)); printf '%s\n' "$j" > "$SCRATCH/azstate/a1.$i.json"; done
  reset_logs
  M_RC=0
  if [[ "$op" == 1 ]]; then
    M_OUT="$(env PATH="$BIN_MERGE" AZ_STATE="$SCRATCH/azstate" AZ_A5_RC="$a5rc" AZ_A5_ERR='TF401027: no permission' AAI_OPERATOR_MERGE=1 \
      "$NODE_BIN" "$PLATFORM_CLI" merge --pr 7 --expect-head "$expect" --repo-root "$repo" 2>&1)" || M_RC=$?
  else
    M_OUT="$(env PATH="$BIN_MERGE" AZ_STATE="$SCRATCH/azstate" AZ_A5_RC="$a5rc" \
      "$NODE_BIN" "$PLATFORM_CLI" merge --pr 7 --expect-head "$expect" --repo-root "$repo" 2>&1)" || M_RC=$?
  fi
}
a5_calls() { count_lines '^repos pr update' "$AZ_LOG"; }
A5_ARGV='repos pr update --id 7 --status completed --squash true --delete-source-branch false --detect true --output json'
A1_ARGV='repos pr show --id 7 --detect true --output json'

test_071_azure_merge_head_match() {
  BIN_MERGE="$SCRATCH/bin-merge"; make_merge_bin "$BIN_MERGE"
  local az_repo gh_repo none_repo open_a open_b done_a done_b
  mk_repo "$AZ_URL"; az_repo="$REPO"
  mk_repo 'https://github.com/acme/foo.git'; gh_repo="$REPO"
  mk_repo ''; none_repo="$REPO"
  open_a="$(az_pr_json active "$SHA_A" '')"; open_b="$(az_pr_json active "$SHA_B" '')"
  done_a="$(az_pr_json completed "$SHA_A" "$SHA_M")"; done_b="$(az_pr_json completed "$SHA_B" "$SHA_M")"

  # merged arm: A1, A5 exactly once, A1 again, nothing else, exit 0 MERGED
  merge_arm "$az_repo" 1 "$SHA_A" 0 "$open_a" "$done_a"
  [[ "$M_RC" -eq 0 ]] || fail TEST-071 "merged arm exit want 0 got $M_RC: $M_OUT"
  case "$M_OUT" in *"MERGED PR #7 head $SHA_A merge $SHA_M"*) ;; *) fail TEST-071 "merged arm output: $M_OUT" ;; esac
  [[ "$(a5_calls)" == 1 ]] || fail TEST-071 "merged arm want exactly one A5, got $(a5_calls)"
  [[ "$(cat "$AZ_LOG")" == "$A1_ARGV
$A5_ARGV
$A1_ARGV" ]] || fail TEST-071 "merged arm az log wrong (want A1, A5, A1): $(cat "$AZ_LOG")"
  [[ ! -s "$GH_LOG" ]] || fail TEST-071 "merged arm spawned gh"

  # refusal arms: exit 3 and zero A5
  merge_arm "$az_repo" 0 "$SHA_A" 0 "$open_a"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "no_operator_merge want 3 got $M_RC: $M_OUT"
  case "$M_OUT" in *no_operator_merge*) ;; *) fail TEST-071 "want no_operator_merge: $M_OUT" ;; esac
  [[ "$(a5_calls)" == 0 ]] || fail TEST-071 "no_operator_merge ran A5"
  merge_arm "$az_repo" 1 "$SHA_A" 0 "$open_b"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "head_changed want 3 got $M_RC: $M_OUT"
  case "$M_OUT" in *head_changed*) ;; *) fail TEST-071 "want head_changed: $M_OUT" ;; esac
  [[ "$(a5_calls)" == 0 ]] || fail TEST-071 "head_changed ran A5"
  merge_arm "$az_repo" 1 "$SHA_A" 0 "$done_a"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "not_open want 3 got $M_RC: $M_OUT"
  case "$M_OUT" in *not_open*) ;; *) fail TEST-071 "want not_open: $M_OUT" ;; esac
  [[ "$(a5_calls)" == 0 ]] || fail TEST-071 "not_open ran A5"
  merge_arm "$az_repo" 1 "not-a-sha" 0 "$open_a"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "bad sha want 3 got $M_RC: $M_OUT"
  [[ ! -s "$AZ_LOG" ]] || fail TEST-071 "bad sha reached az: $(cat "$AZ_LOG")"
  merge_arm "$gh_repo" 1 "$SHA_A" 0 "$open_a"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "github platform want 3 got $M_RC: $M_OUT"
  case "$M_OUT" in *platform_not_azure*) ;; *) fail TEST-071 "want platform_not_azure: $M_OUT" ;; esac
  [[ ! -s "$AZ_LOG" && ! -s "$GH_LOG" ]] || fail TEST-071 "github platform spawned a CLI"
  merge_arm "$none_repo" 1 "$SHA_A" 0 "$open_a"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "no origin want 3 got $M_RC: $M_OUT"
  [[ ! -s "$AZ_LOG" ]] || fail TEST-071 "no origin spawned az"
  seed_cfg "$az_repo" 'platform: github\n'
  merge_arm "$az_repo" 1 "$SHA_A" 0 "$open_a"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "mismatch want 3 got $M_RC: $M_OUT"
  case "$M_OUT" in *"REFUSE platform_mismatch recorded=github detected=azure"*) ;; *) fail TEST-071 "want a REFUSE platform_mismatch line like merge-cleanup's: $M_OUT" ;; esac
  case "$M_OUT" in *'record --force'*) ;; *) fail TEST-071 "platform_mismatch refusal lacks the record --force command: $M_OUT" ;; esac
  [[ ! -s "$AZ_LOG" ]] || fail TEST-071 "mismatch spawned az"
  rm -f "$(cfg_of "$az_repo")"

  # A5 failure: exit 3 merge_rejected with its first stderr line, one A5, no re-read
  merge_arm "$az_repo" 1 "$SHA_A" 1 "$open_a"
  [[ "$M_RC" -eq 3 ]] || fail TEST-071 "merge_rejected want 3 got $M_RC: $M_OUT"
  case "$M_OUT" in *"merge_rejected TF401027: no permission"*) ;; *) fail TEST-071 "want merge_rejected with stderr line: $M_OUT" ;; esac
  [[ "$(a5_calls)" == 1 ]] || fail TEST-071 "merge_rejected want one A5"
  [[ "$(count_lines '^repos pr show' "$AZ_LOG")" == 1 ]] || fail TEST-071 "merge_rejected re-read after a failed A5"

  # mismatch arm: the re-read shows another head merged -> exit 5 naming both shas
  merge_arm "$az_repo" 1 "$SHA_A" 0 "$open_a" "$done_b"
  [[ "$M_RC" -eq 5 ]] || fail TEST-071 "head_race_lost want 5 got $M_RC: $M_OUT"
  case "$M_OUT" in *"head_race_lost expected $SHA_A merged $SHA_B"*) ;; *) fail TEST-071 "want head_race_lost naming both shas: $M_OUT" ;; esac
  case "$M_OUT" in *MERGED*) fail TEST-071 "head_race_lost printed MERGED: $M_OUT" ;; esac
  [[ "$(a5_calls)" == 1 ]] || fail TEST-071 "head_race_lost want exactly one A5"

  # still active after A5: exit 4 completion_pending
  merge_arm "$az_repo" 1 "$SHA_A" 0 "$open_a" "$open_a"
  [[ "$M_RC" -eq 4 ]] || fail TEST-071 "completion_pending want 4 got $M_RC: $M_OUT"
  case "$M_OUT" in *completion_pending*) ;; *) fail TEST-071 "want completion_pending: $M_OUT" ;; esac
  [[ "$(a5_calls)" == 1 ]] || fail TEST-071 "completion_pending want one A5"
  echo "PASS: TEST-071 azure merge head match (Spec-AC-09)"
}

test_076_canon_and_governance() {
  local skill="$ROOT/.aai/SKILL_MERGE.prompt.md" ledger="$ROOT/tests/skills/lib/prompt-diet-ledger.sh"
  local profiles="$ROOT/.aai/system/PROFILES.yaml" cfg="$ROOT/docs/ai/pr-config.yaml" smap="$ROOT/tests/skills/suite-map.yaml"
  grep -qF '`AAI_OPERATOR_MERGE=1 gh pr merge <n> --squash --match-head-commit <sha>`' "$skill" || fail TEST-076 "SKILL_MERGE lost the GitHub merge literal"
  grep -qF 'platform.mjs" merge --pr <n> --expect-head <sha>' "$skill" || fail TEST-076 "SKILL_MERGE does not name the Azure merge form"
  grep -qF 'A `platform_mismatch` or `platform_generic` REFUSE is relayed with its command and the run stops.' "$skill" || fail TEST-076 "SKILL_MERGE lacks the REFUSE relay sentence"
  grep -qF 'Exit 4 (completion_pending)' "$skill" || fail TEST-076 "SKILL_MERGE does not name exit 4 completion_pending"
  grep -qF '5 (head_race_lost)' "$skill" || fail TEST-076 "SKILL_MERGE does not name exit 5 head_race_lost"
  grep -qF 'never treat the direction as covering a head it did not name' "$skill" || fail TEST-076 "SKILL_MERGE lacks the head_race_lost direction rule"
  grep -qF 'platform: <reason>' "$skill" || fail TEST-076 "SKILL_MERGE does not say how the other refusals print"
  local credit
  credit="$(sed -n 's/^JUSTIFIED_ADDITIONS+=( "\([0-9][0-9]*\) git-platform-detected-at-bootstrap .*/\1/p' "$ledger")"
  [[ -n "$credit" && "$(printf '%s\n' "$credit" | wc -l | tr -d ' ')" == 1 ]] || fail TEST-076 "want exactly one ledger entry for the key, got: $credit"
  [[ "$credit" -ge 1 && "$credit" -le 900 ]] || fail TEST-076 "ledger credit $credit outside 1..900"
  local f
  for f in .aai/scripts/platform.mjs .aai/scripts/lib/platform-adapter.mjs; do
    awk -v f="$f" '/^core:/ { in_core = 1; next } /^[a-z_]+:/ { in_core = 0 } in_core && $0 == "  - " f { found = 1 } END { exit found ? 0 : 1 }' "$profiles" || fail TEST-076 "PROFILES core lacks $f"
  done
  grep -qx 'platform: github' "$cfg" || fail TEST-076 "pr-config.yaml does not record platform: github"
  grep -q '^#   platform:' "$cfg" || fail TEST-076 "pr-config.yaml does not document the platform key"
  awk '/^  aai-merge-cleanup:/ { in_row = 1; next } /^  [a-z]/ { in_row = 0 } in_row { print }' "$smap" > "$SCRATCH/mc-row.txt"
  for f in .aai/scripts/platform.mjs .aai/scripts/lib/platform-adapter.mjs; do
    grep -qxF "      - $f" "$SCRATCH/mc-row.txt" || fail TEST-076 "suite-map aai-merge-cleanup row lacks $f"
  done
  local rc=0 out
  out="$(env -u AAI_ROLE bash "$ROOT/tests/skills/test-aai-prompt-diet.sh" test_010_audit_and_reduction 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-076 "prompt-diet TEST-010 exit $rc: $out"
  rc=0; out="$(env -u AAI_ROLE bash "$ROOT/tests/skills/test-aai-prompt-diet.sh" test_012_growth_sum_matches_ledger 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-076 "prompt-diet TEST-012 exit $rc: $out"
  # The whole pr-preflight and layer-profiles suites are NOT nested here (SPEC-0215 forbids a
  # nested whole-suite run, and the companion pin of test-aai-suite-select.sh is closed); V3 and
  # the end-of-ride sweep run them. The one pr-preflight function that pins the ledger sum runs
  # in selector form, and the PROFILES classification is asserted above.
  rc=0; out="$(env -u AAI_ROLE bash "$ROOT/tests/skills/test-aai-pr-preflight.sh" test_008 2>&1)" || rc=$?
  [[ "$rc" -eq 0 ]] || fail TEST-076 "pr-preflight test_008 exit $rc: $out"
  echo "PASS: TEST-076 canon and governance (Spec-AC-14)"
}

if [[ $# -gt 1 ]]; then echo 'Usage: test-aai-platform-adapter.sh [test_xxx | TEST-xxx]' >&2; exit 2; fi
case "${1:-}" in
  TEST-062) set -- test_062_record_matrix ;;
  TEST-063) set -- test_063_record_never_overwrites ;;
  TEST-064) set -- test_064_auth_report ;;
  TEST-066) set -- test_066_adapter_shapes ;;
  TEST-067) set -- test_067_generic_named_skips ;;
  TEST-069) set -- test_069_az_windows_spawn_spec ;;
  TEST-075) set -- test_075_no_direct_platform_calls ;;
  TEST-071) set -- test_071_azure_merge_head_match ;;
  TEST-076) set -- test_076_canon_and_governance ;;
esac
if [[ $# -gt 0 ]]; then
  declare -F "$1" >/dev/null || { echo "Unknown selector: $1" >&2; exit 2; }
  "$1"
  exit 0
fi
test_062_record_matrix
test_063_record_never_overwrites
test_064_auth_report
test_066_adapter_shapes
test_067_generic_named_skips
test_069_az_windows_spawn_spec
test_075_no_direct_platform_calls
test_071_azure_merge_head_match
test_076_canon_and_governance
echo "All platform adapter tests passed"
