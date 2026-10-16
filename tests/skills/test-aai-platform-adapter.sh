#!/usr/bin/env bash
# Platform record and adapter tests (spec-git-platform-detected-at-bootstrap).
# Batch A: TEST-062 (record matrix), TEST-063 (never overwrites), TEST-064 (auth report).
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

if [[ $# -gt 1 ]]; then echo 'Usage: test-aai-platform-adapter.sh [test_xxx | TEST-xxx]' >&2; exit 2; fi
case "${1:-}" in
  TEST-062) set -- test_062_record_matrix ;;
  TEST-063) set -- test_063_record_never_overwrites ;;
  TEST-064) set -- test_064_auth_report ;;
esac
if [[ $# -gt 0 ]]; then
  declare -F "$1" >/dev/null || { echo "Unknown selector: $1" >&2; exit 2; }
  "$1"
  exit 0
fi
test_062_record_matrix
test_063_record_never_overwrites
test_064_auth_report
echo "All platform adapter tests passed"
