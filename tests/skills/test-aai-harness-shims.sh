#!/usr/bin/env bash
#
# Test: the six root instruction shims are GENERATED from one registry
# (SPEC spec-provider-adapter-registry-slice, RFC-0017 phase 4; TEST-3001..3014).
#
#   - the `shims:` section of .aai/system/HARNESS_SKILLS.yaml plus the fragment
#     file .aai/system/HARNESS_SHIMS.md render CLAUDE.md, AGENTS.md, CODEX.md,
#     GEMINI.md, .github/copilot-instructions.md and .cursor/rules/aai.mdc
#     through .aai/scripts/lib/harness-shims.mjs, driven by
#     .aai/scripts/sync-harness-skills.mjs --check / --write;
#   - .aai/system/COPILOT_SHIM_SHIPPED.list records every shipped Copilot shim
#     so aai-sync (bash and PowerShell) replaces an unmodified older shim
#     instead of keeping it as a fake "Project Overrides" block;
#   - aai-sync installs the root AGENTS.md instead of deleting it;
#   - the six #501 contract amendments read signed and their trackers done.
#
# NO NETWORK: the real generator and the real aai-sync twins run into
# throwaway directories under TMPDIR. Single-row dispatch for mutation-run.mjs:
#   bash tests/skills/test-aai-harness-shims.sh --test TEST-3004
#   bash tests/skills/test-aai-harness-shims.sh test_3004_write_restores_and_is_idempotent
#
# Exit codes: 0 all passed, 1 failed, 42 skipped (missing dependencies).

set -euo pipefail

TEST_NAME="aai-harness-shims"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/pipe-safe.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GEN="$PROJECT_ROOT/.aai/scripts/sync-harness-skills.mjs"
SYNC_SH="$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
SYNC_PS1="$PROJECT_ROOT/.aai/scripts/aai-sync.ps1"
SELECT="$PROJECT_ROOT/.aai/scripts/select-suites.mjs"
SPEC_AMEND="$PROJECT_ROOT/.aai/scripts/spec-amend.mjs"
FOLLOW_UPS="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"
LEDGER="$PROJECT_ROOT/docs/ai/decisions.jsonl"
BASE_REF="ff32ec2e"
COPILOT_REL=".github/copilot-instructions.md"
SHIMS=(CLAUDE.md AGENTS.md CODEX.md GEMINI.md .github/copilot-instructions.md .cursor/rules/aai.mdc)

TMP_ROOT=""
PWSH_ARM_SKIPPED=0

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixtures under $TMP_ROOT"
    return 0
  fi
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then rm -rf "$TMP_ROOT"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-harness-shims.XXXXXX")"
  write_helper
}

# --- test-side helper (not shipped): fragment/registry/hash readers ------------
write_helper() {
  cat > "$TMP_ROOT/helper.mjs" <<'HELPER'
import fs from 'node:fs';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
const [, , cmd, ...a] = process.argv;
const nhash = (t) => crypto.createHash('sha256').update(t.replace(/\r/g, '').replace(/\n+$/, '')).digest('hex');
function fragments(file) {
  const out = []; let cur = null;
  for (const piece of fs.readFileSync(file, 'utf8').split(/(?<=\n)/)) {
    const m = piece.replace(/\n$/, '').match(/^<!-- fragment: ([a-z0-9-]+) -->$/);
    if (m) { cur = { id: m[1], text: '' }; out.push(cur); } else if (cur) cur.text += piece;
  }
  return out;
}
if (cmd === 'rows') {
  let on = false;
  for (const l of fs.readFileSync(a[0], 'utf8').split(/\r?\n/)) {
    if (/^shims:\s*$/.test(l)) { on = true; continue; }
    if (/^[a-z_]+:/.test(l)) on = false;
    const m = on && l.match(/^ {2}- (.*)$/);
    if (m) console.log(m[1]);
  }
} else if (cmd === 'frag-by-prefix') {
  const hit = fragments(a[0]).filter((f) => f.text.startsWith(a[1]));
  if (hit.length !== 1) { console.error(`want exactly one fragment starting ${a[1]}, got ${hit.length}`); process.exit(3); }
  process.stdout.write(hit[0].text);
} else if (cmd === 'nhash') {
  process.stdout.write(nhash(fs.readFileSync(a[0], 'utf8')));
} else if (cmd === 'hist') {
  const [repo, rel, rev] = a;
  const shas = execFileSync('git', ['-C', repo, 'log', '--format=%H', rev, '--', rel], { encoding: 'utf8' }).split('\n').filter(Boolean);
  const blobs = new Set(shas.map((c) => execFileSync('git', ['-C', repo, 'rev-parse', `${c}:${rel}`], { encoding: 'utf8' }).trim()));
  const hashes = [...blobs].map((b) => nhash(execFileSync('git', ['-C', repo, 'cat-file', 'blob', b], { encoding: 'utf8' })));
  console.log([...new Set(hashes)].sort().join('\n'));
} else {
  console.error('unknown helper command'); process.exit(2);
}
HELPER
}

H() { node "$TMP_ROOT/helper.mjs" "$@"; }

sha_file() {
  node -e 'const c=require("crypto"),fs=require("fs");process.stdout.write(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$1"
}

# mk_root <dir> — a scratch project root carrying everything the generator reads
# or writes: the registry, the fragment file, the shipped list, the skill source
# tree, the three mirror trees and the six shims (whichever of them exist).
mk_root() {
  local dir="$1" f t
  [[ -n "$dir" && "$dir" == /* ]] || log_fail "mk_root: destination is empty or relative: [$dir]"
  rm -rf "$dir"
  mkdir -p "$dir/.aai/system"
  for f in HARNESS_SKILLS.yaml HARNESS_SHIMS.md COPILOT_SHIM_SHIPPED.list; do
    if [[ -f "$PROJECT_ROOT/.aai/system/$f" ]]; then cp "$PROJECT_ROOT/.aai/system/$f" "$dir/.aai/system/$f"; fi
  done
  for t in .claude/skills .agents/skills .codex/skills .gemini/skills; do
    mkdir -p "$dir/$t"
    cp -R "$PROJECT_ROOT/$t/." "$dir/$t/"
  done
  for f in "${SHIMS[@]}"; do
    if [[ -f "$PROJECT_ROOT/$f" ]]; then
      mkdir -p "$dir/$(dirname "$f")"
      cp "$PROJECT_ROOT/$f" "$dir/$f"
    fi
  done
}

# gen <root> <flag...> — runs the REAL generator; sets GEN_OUT (stdout+stderr) and GEN_RC.
gen() {
  local root="$1"; shift
  GEN_OUT="$(env -u AAI_ROLE node "$GEN" --root "$root" "$@" 2>&1)" && GEN_RC=0 || GEN_RC=$?
}

count_lines_starting() {  # <text> <prefix>
  local n=0 line
  while IFS= read -r line; do
    case "$line" in "$2"*) n=$((n + 1)) ;; esac
  done <<< "$1"
  echo "$n"
}

D2_CLAUDE=88b51794d66f6d318280dc3e143a5e7af4771001ae068f91f6939733a0cf378d
D2_AGENTS=97cb53da3daf45356f4a82409c2260b2c895e20de7a62ed72e227ca244d7d1bd
D2_CODEX=f2267f46ff8981fece24da469f096586fa9dfa94e83d06c23a0b2589ea645828
D2_GEMINI=4369b639ddbb3aee36ba5c8b5aef0a358bf21e1aa8c84cd3e83088672b2efc2c
D2_CURSOR=f88343f60b8d95a5675fb344a662528816308c58bf997306e30fa711ec7290ad

# --- TEST-3001 -----------------------------------------------------------------
test_3001_shims_render_from_registry() {
  log_info "TEST-3001: --write recreates the six deleted shims from the registry (D2 hashes)..."
  local root="$TMP_ROOT/t3001" f want got rows path frags name cli
  mk_root "$root"
  for f in "${SHIMS[@]}"; do rm -f "$root/$f"; done
  gen "$root" --write
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3001: --write must exit 0, got $GEN_RC: $GEN_OUT"
  local -a pairs=("CLAUDE.md:$D2_CLAUDE" "AGENTS.md:$D2_AGENTS" "CODEX.md:$D2_CODEX" "GEMINI.md:$D2_GEMINI" ".cursor/rules/aai.mdc:$D2_CURSOR")
  for f in "${pairs[@]}"; do
    [[ -f "$root/${f%%:*}" ]] || log_fail "TEST-3001: ${f%%:*} was not recreated by --write"
    got="$(sha_file "$root/${f%%:*}")"
    [[ "$got" == "${f#*:}" ]] || log_fail "TEST-3001: ${f%%:*} sha256 $got differs from the D2 value ${f#*:}"
  done
  for f in "${SHIMS[@]}"; do
    [[ -f "$root/$f" ]] || log_fail "TEST-3001: $f was not recreated by --write"
    cmp -s "$root/$f" "$PROJECT_ROOT/$f" || log_fail "TEST-3001: regenerated $f differs from the committed file"
  done
  rows="$(H rows "$PROJECT_ROOT/.aai/system/HARNESS_SKILLS.yaml")"
  [[ "$(count_lines_starting "$rows" "")" -eq 6 ]] || log_fail "TEST-3001: the shims section must hold exactly 6 rows, got: $rows"
  local claude_f="" agents_f="" codex_f="" gemini_f=""
  while IFS='|' read -r path frags name cli; do
    case "$path" in
      CLAUDE.md) claude_f="$frags" ;;
      AGENTS.md) agents_f="$frags" ;;
      CODEX.md) codex_f="$frags" ;;
      GEMINI.md) gemini_f="$frags" ;;
    esac
  done <<< "$rows"
  [[ -n "$claude_f" && -n "$agents_f" && -n "$codex_f" && -n "$gemini_f" ]] \
    || log_fail "TEST-3001: the registry lacks a row for CLAUDE.md, AGENTS.md, CODEX.md or GEMINI.md"
  [[ "${claude_f#*+}" == "${agents_f#*+}" && "$claude_f" == *+* ]] \
    || log_fail "TEST-3001: CLAUDE.md [$claude_f] and AGENTS.md [$agents_f] must name the same fragments after the first"
  [[ "${codex_f#*+}" == "${gemini_f#*+}" && "$codex_f" == *+* ]] \
    || log_fail "TEST-3001: CODEX.md [$codex_f] and GEMINI.md [$gemini_f] must name the same fragments after the first"
  log_pass "TEST-3001 the six shims render from the registry; five keep their D2 bytes"
}

# --- TEST-3002 -----------------------------------------------------------------
COPILOT_KEPT_PREFIX='# Copilot Instructions (Shim)

This repository uses a single canonical workflow and a prompt suite for consistent agent behavior.

## Canonical sources
- Agent guide: /.aai/AGENTS.md
- Playbook: /.aai/PLAYBOOK.md
- Prompts: /.aai/*.prompt.md
- Intake entrypoints: /.aai/AGENTS.md
- Workflow: /.aai/workflow/WORKFLOW.md
- Technology contract: /docs/TECHNOLOGY.md

## Rules
- Do not introduce alternative workflows or role systems.
- Do not assume frameworks or tools not documented in /docs/TECHNOLOGY.md.
- Prefer changes that preserve traceability:
  Requirement → Spec → Implementation → Evidence

## Suggested developer flow
- Use .aai/ORCHESTRATION.prompt.md to select the next role step.
- Validate with .aai/VALIDATION.prompt.md before claiming completion.

'

test_3002_copilot_lists_no_skills() {
  log_info "TEST-3002: the Copilot shim lists no skills and shares the fragment with CODEX.md and GEMINI.md..."
  local copilot="$PROJECT_ROOT/$COPILOT_REL" content frag f inline kept base
  content="$(cat "$copilot"; printf x)"; content="${content%x}"
  inline="$(count_lines_starting "$(cat "$copilot")" '  - `/aai-')"
  [[ "$inline" -eq 0 ]] || log_fail "TEST-3002: the Copilot shim still holds $inline inline skill line(s)"
  frag="$(H frag-by-prefix "$PROJECT_ROOT/.aai/system/HARNESS_SHIMS.md" '- This shim intentionally lists no skills'; printf x)" \
    || log_fail "TEST-3002: HARNESS_SHIMS.md has no single fragment starting '- This shim intentionally lists no skills'"
  frag="${frag%x}"
  for f in "$copilot" "$PROJECT_ROOT/CODEX.md" "$PROJECT_ROOT/GEMINI.md"; do
    content="$(cat "$f"; printf x)"; content="${content%x}"
    [[ "$content" == *"$frag"* ]] || log_fail "TEST-3002: ${f#"$PROJECT_ROOT"/} does not contain the shared 'lists no skills' fragment byte-identically"
  done
  content="$(cat "$copilot"; printf x)"; content="${content%x}"
  [[ "$content" == "$COPILOT_KEPT_PREFIX"* ]] \
    || log_fail "TEST-3002: the Copilot heading and the Canonical sources, Rules and Suggested developer flow sections differ from the $BASE_REF text"
  [[ "$content" == *'## Skill discovery (AAI prefix)'* ]] || log_fail "TEST-3002: the Copilot shim lacks the '## Skill discovery (AAI prefix)' section"
  [[ "$content" == *'- Project-specific generated skills are in `.claude/skills/` and use `aai-` prefix.'* ]] \
    || log_fail "TEST-3002: the Copilot shim lost its 'Project-specific generated skills' line"
  # The embedded text above is only trustworthy while it equals the base blob.
  if git -C "$PROJECT_ROOT" cat-file -e "$BASE_REF^{commit}" 2>/dev/null; then
    base="$(git -C "$PROJECT_ROOT" show "$BASE_REF:$COPILOT_REL"; printf x)"; base="${base%x}"
    kept="${base%%## AAI Skills (post-sync)*}"
    [[ "$kept" == "$COPILOT_KEPT_PREFIX" ]] \
      || log_fail "TEST-3002: the embedded expected sections no longer equal the $BASE_REF blob (suite bug)"
  fi
  log_pass "TEST-3002 the Copilot shim lists no skills and keeps its $BASE_REF sections"
}

# --- TEST-3003 -----------------------------------------------------------------
# mini_registry <root> <fragments-text> <row...> — a self-contained registry in a scratch root.
mini_registry() {
  local root="$1" frags="$2"; shift 2
  local trees
  trees="$(sed -n '/^trees:/,/^exclusions:/p' "$PROJECT_ROOT/.aai/system/HARNESS_SKILLS.yaml")"
  {
    printf '%s\n' "$trees"
    printf 'shims:\n'
    local r
    for r in "$@"; do printf '  - %s\n' "$r"; done
  } > "$root/.aai/system/HARNESS_SKILLS.yaml"
  printf '%s' "$frags" > "$root/.aai/system/HARNESS_SHIMS.md"
}

MINI_FRAGS='header ignored
<!-- fragment: a -->
alpha {{name}} {{cli}}
<!-- fragment: b -->
beta
'
mini_rows_ok() {
  printf '%s\n' 'CLAUDE.md|a+b|N|C' 'AGENTS.md|a+b|N|C' 'CODEX.md|a+b|N|C' 'GEMINI.md|a+b|N|C' \
    '.github/copilot-instructions.md|a+b|N|C' '.cursor/rules/aai.mdc|a+b|N|C'
}

expect_registry_error() {  # <label> <cause-substring> <root>
  gen "$3" --check
  [[ "$GEN_RC" -eq 2 ]] || log_fail "TEST-3003: broken registry '$1' must exit 2, got $GEN_RC: $GEN_OUT"
  [[ "$GEN_OUT" == *"$2"* ]] || log_fail "TEST-3003: broken registry '$1' must name the cause '$2', got: $GEN_OUT"
}

test_3003_check_reports_each_divergence() {
  log_info "TEST-3003: --check prints one DIVERGE shim line per differing path, exits 1/0, and refuses broken registries with 2..."
  local root="$TMP_ROOT/t3003" n
  mk_root "$root"
  gen "$root" --check
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3003: a clean root must exit 0, got $GEN_RC: $GEN_OUT"
  [[ "$GEN_OUT" == *'OK: .agents/skills, .codex/skills, .gemini/skills match the declared transform'* ]] \
    || log_fail "TEST-3003: the tree OK line must stay unchanged, got: $GEN_OUT"
  [[ "$GEN_OUT" == *'OK: 6 shim(s) match the registry'* ]] || log_fail "TEST-3003: the shim OK line is missing, got: $GEN_OUT"
  printf 'hand edit\n' >> "$root/GEMINI.md"
  gen "$root" --check
  [[ "$GEN_RC" -eq 1 ]] || log_fail "TEST-3003: one edited shim must exit 1, got $GEN_RC: $GEN_OUT"
  n="$(count_lines_starting "$GEN_OUT" 'DIVERGE shim ')"
  [[ "$n" -eq 1 && "$GEN_OUT" == *'DIVERGE shim GEMINI.md'* ]] || log_fail "TEST-3003: want exactly one 'DIVERGE shim GEMINI.md' line, got $n: $GEN_OUT"
  printf 'hand edit\n' >> "$root/.cursor/rules/aai.mdc"
  gen "$root" --check
  n="$(count_lines_starting "$GEN_OUT" 'DIVERGE shim ')"
  [[ "$GEN_RC" -eq 1 && "$n" -eq 2 ]] || log_fail "TEST-3003: two edited shims must give exactly two DIVERGE shim lines, got rc=$GEN_RC n=$n: $GEN_OUT"
  rm -f "$root/CLAUDE.md"
  gen "$root" --check
  n="$(count_lines_starting "$GEN_OUT" 'DIVERGE shim ')"
  [[ "$GEN_RC" -eq 1 && "$n" -eq 3 && "$GEN_OUT" == *'DIVERGE shim CLAUDE.md: absent'* ]] \
    || log_fail "TEST-3003: a deleted shim must give an 'absent' line (3 lines in all), got rc=$GEN_RC n=$n: $GEN_OUT"
  # negative control: an unrelated file next to the shims is not a shim and is never reported
  mk_root "$root"
  printf 'notes\n' > "$root/NOTES.md"
  gen "$root" --check
  [[ "$GEN_RC" -eq 0 && "$GEN_OUT" != *NOTES.md* ]] || log_fail "TEST-3003: an undeclared file must not be reported, got rc=$GEN_RC: $GEN_OUT"

  # eight broken registries (D1), each in a mini registry whose valid form passes
  local mini="$TMP_ROOT/t3003-mini" frags_dup frags_orphan
  mk_root "$mini"
  # shellcheck disable=SC2046
  mini_registry "$mini" "$MINI_FRAGS" $(mini_rows_ok)
  gen "$mini" --write
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3003: the valid mini registry must --write with exit 0, got $GEN_RC: $GEN_OUT"
  gen "$mini" --check
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3003: the valid mini registry must --check with exit 0, got $GEN_RC: $GEN_OUT"
  # shellcheck disable=SC2046
  mini_registry "$mini" "$MINI_FRAGS<!-- fragment: c -->
{{bogus}}
" $(mini_rows_ok)
  expect_registry_error "placeholder other than the two" "unknown placeholder" "$mini"
  mini_registry "$mini" "$MINI_FRAGS" 'CLAUDE.md|a+zzz|N|C' 'AGENTS.md|a+b|N|C' 'CODEX.md|a+b|N|C' 'GEMINI.md|a+b|N|C' \
    '.github/copilot-instructions.md|a+b|N|C' '.cursor/rules/aai.mdc|a+b|N|C'
  expect_registry_error "fragment the file does not define" "undefined fragment" "$mini"
  frags_orphan="$MINI_FRAGS<!-- fragment: orphan -->
unused
"
  # shellcheck disable=SC2046
  mini_registry "$mini" "$frags_orphan" $(mini_rows_ok)
  expect_registry_error "fragment no row names" "unused fragment" "$mini"
  frags_dup="$MINI_FRAGS<!-- fragment: a -->
again
"
  # shellcheck disable=SC2046
  mini_registry "$mini" "$frags_dup" $(mini_rows_ok)
  expect_registry_error "duplicate fragment id" "duplicate fragment" "$mini"
  mini_registry "$mini" "$MINI_FRAGS" 'CLAUDE.md|a+b|N' 'AGENTS.md|a+b|N|C' 'CODEX.md|a+b|N|C' 'GEMINI.md|a+b|N|C' \
    '.github/copilot-instructions.md|a+b|N|C' '.cursor/rules/aai.mdc|a+b|N|C'
  expect_registry_error "malformed row" "malformed shims row" "$mini"
  # shellcheck disable=SC2046
  mini_registry "$mini" "$MINI_FRAGS" $(mini_rows_ok) 'CLAUDE.md|a+b|N|C'
  expect_registry_error "duplicate path" "duplicate shims path" "$mini"
  mini_registry "$mini" "$MINI_FRAGS" 'NOTES.md|a+b|N|C' 'AGENTS.md|a+b|N|C' 'CODEX.md|a+b|N|C' 'GEMINI.md|a+b|N|C' \
    '.github/copilot-instructions.md|a+b|N|C' '.cursor/rules/aai.mdc|a+b|N|C'
  expect_registry_error "path outside the six" "not an allowed shim path" "$mini"
  mini_registry "$mini" "$MINI_FRAGS" 'AGENTS.md|a+b|N|C' 'CODEX.md|a+b|N|C' 'GEMINI.md|a+b|N|C' \
    '.github/copilot-instructions.md|a+b|N|C' '.cursor/rules/aai.mdc|a+b|N|C'
  expect_registry_error "section missing one of the six" "shims section missing" "$mini"

  # a manifest without a shims section: nothing generated, nothing checked
  local plain="$TMP_ROOT/t3003-plain"
  mk_root "$plain"
  sed -n '/^trees:/,/^exclusions:/p' "$PROJECT_ROOT/.aai/system/HARNESS_SKILLS.yaml" > "$TMP_ROOT/plain-manifest.yaml"
  rm -f "$plain/.aai/system/HARNESS_SHIMS.md" "$plain/GEMINI.md"
  gen "$plain" --manifest "$TMP_ROOT/plain-manifest.yaml" --check
  [[ "$GEN_RC" -eq 0 && "$GEN_OUT" == *'SHIMS: none declared'* ]] \
    || log_fail "TEST-3003: a manifest without a shims section must print 'SHIMS: none declared' and exit 0, got rc=$GEN_RC: $GEN_OUT"
  log_pass "TEST-3003 --check reports each divergence, exits 1/0, refuses eight broken registries with 2"
}

# --- TEST-3004 -----------------------------------------------------------------
mtimes_of() {  # <root> — "<path> <mtimeMs>" per shim
  node -e 'const fs=require("fs"),p=require("path");for(const f of process.argv.slice(2).slice(1)){console.log(f+" "+fs.statSync(p.join(process.argv[1],f)).mtimeMs)}' "$1" "${SHIMS[@]}"
}

test_3004_write_restores_and_is_idempotent() {
  log_info "TEST-3004: --write restores an edited and a deleted shim; a second --write changes nothing..."
  local root="$TMP_ROOT/t3004" f before after
  mk_root "$root"
  printf 'planted\n' >> "$root/AGENTS.md"
  rm -f "$root/.github/copilot-instructions.md"
  gen "$root" --write
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3004: --write must exit 0, got $GEN_RC: $GEN_OUT"
  for f in AGENTS.md .github/copilot-instructions.md; do
    [[ -f "$root/$f" ]] || log_fail "TEST-3004: --write did not restore $f"
    cmp -s "$root/$f" "$PROJECT_ROOT/$f" || log_fail "TEST-3004: restored $f is not byte-equal to the rendered text"
  done
  before="$(mtimes_of "$root")"
  sleep 1
  gen "$root" --write
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3004: the second --write must exit 0, got $GEN_RC: $GEN_OUT"
  after="$(mtimes_of "$root")"
  [[ "$before" == "$after" ]] || log_fail "TEST-3004: the second --write rewrote a shim (mtime changed)"
  for f in "${SHIMS[@]}"; do
    cmp -s "$root/$f" "$PROJECT_ROOT/$f" || log_fail "TEST-3004: $f changed after the second --write"
  done
  gen "$root" --check
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3004: --check after --write must exit 0, got $GEN_RC: $GEN_OUT"
  log_pass "TEST-3004 --write restores both shims and is idempotent"
}

# --- TEST-3005 -----------------------------------------------------------------
test_3005_shim_paths_select_the_gate() {
  log_info "TEST-3005: every shim path and the three new .aai files select the hygiene gate and this suite..."
  local p out
  local -a paths=("${SHIMS[@]}" .aai/system/HARNESS_SHIMS.md .aai/system/COPILOT_SHIM_SHIPPED.list)
  for p in "${paths[@]}"; do
    out="$(printf '%s\n' "$p" | node "$SELECT" --files-from - --repo-root "$PROJECT_ROOT")"
    [[ "$out" != FULL_RUN* ]] || log_fail "TEST-3005: $p is unmapped or escalates to a full run, got: $out"
    [[ "$out" == *'aai-hygiene-pack'* ]] || log_fail "TEST-3005: $p does not select aai-hygiene-pack, got: $out"
    [[ "$out" == *'SELECTED aai-harness-shims '* ]] || log_fail "TEST-3005: $p does not select aai-harness-shims, got: $out"
  done
  # the library sits under .aai/scripts/lib/**: the selector's shared-lib rule runs every suite
  out="$(printf '%s\n' .aai/scripts/lib/harness-shims.mjs | node "$SELECT" --files-from - --repo-root "$PROJECT_ROOT")"
  [[ "$out" == 'FULL_RUN reason=shared-lib '* || ( "$out" == *'aai-hygiene-pack'* && "$out" == *'aai-harness-shims'* ) ]] \
    || log_fail "TEST-3005: lib/harness-shims.mjs must run the gate, got: $out"
  # negative control: a path no shim glob names still does not select this suite
  out="$(printf '%s\n' docs/ai/reports/x.md | node "$SELECT" --files-from - --repo-root "$PROJECT_ROOT")"
  [[ "$out" != *'aai-harness-shims'* ]] || log_fail "TEST-3005: an inert report path must not select aai-harness-shims, got: $out"
  log_pass "TEST-3005 shim paths select aai-hygiene-pack and aai-harness-shims"
}

# --- TEST-3007 -----------------------------------------------------------------
test_3007_shipped_list_complete() {
  log_info "TEST-3007: COPILOT_SHIM_SHIPPED.list holds every historical Copilot shim plus the rendered one..."
  local list="$PROJECT_ROOT/.aai/system/COPILOT_SHIM_SHIPPED.list" rendered hist expected rows dup root hash
  [[ -f "$list" ]] || log_fail "TEST-3007: $list does not exist"
  rendered="$(H nhash "$PROJECT_ROOT/$COPILOT_REL")"
  rows="$(sed -e 's/\r$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$list" | LC_ALL=C sort)"
  dup="$(printf '%s\n' "$rows" | uniq -d)"
  [[ -z "$dup" ]] || log_fail "TEST-3007: duplicate row(s) in the shipped list: $dup"
  [[ "$(count_lines_starting "$rows" "")" -ge 9 ]] || log_fail "TEST-3007: want at least 9 rows, got: $rows"
  while IFS= read -r hash; do
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || log_fail "TEST-3007: row is not a lowercase 64-hex sha256: [$hash]"
  done <<< "$rows"
  hist="$(H hist "$PROJECT_ROOT" "$COPILOT_REL" HEAD)" || log_fail "TEST-3007: cannot read the Copilot shim history"
  expected="$(printf '%s\n%s\n' "$hist" "$rendered" | sed '/^$/d' | LC_ALL=C sort -u)"
  if [[ "$(git -C "$PROJECT_ROOT" rev-parse --is-shallow-repository)" == "false" ]]; then
    [[ "$rows" == "$expected" ]] || log_fail "TEST-3007: the list differs from history plus the rendered hash. want:"$'\n'"$expected"$'\n'"got:"$'\n'"$rows"
  else
    [[ "$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$rows"))" == "" ]] \
      || log_fail "TEST-3007: the list lacks a historical or rendered hash"
  fi
  # a root whose list lacks the rendered hash: --check says so, --write appends it
  root="$TMP_ROOT/t3007"
  mk_root "$root"
  grep -vxF "$rendered" "$list" > "$root/.aai/system/COPILOT_SHIM_SHIPPED.list" || true
  gen "$root" --check
  [[ "$GEN_RC" -eq 1 && "$GEN_OUT" == *"DIVERGE shim $COPILOT_REL: unrecorded $rendered"* ]] \
    || log_fail "TEST-3007: an unrecorded rendered hash must give 'DIVERGE shim $COPILOT_REL: unrecorded <hash>' and exit 1, got rc=$GEN_RC: $GEN_OUT"
  gen "$root" --write
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3007: --write must exit 0, got $GEN_RC: $GEN_OUT"
  grep -qxF "$rendered" "$root/.aai/system/COPILOT_SHIM_SHIPPED.list" || log_fail "TEST-3007: --write did not append the rendered hash"
  [[ "$(grep -cxF "$rendered" "$root/.aai/system/COPILOT_SHIM_SHIPPED.list")" -eq 1 ]] || log_fail "TEST-3007: the rendered hash is recorded more than once"
  gen "$root" --check
  [[ "$GEN_RC" -eq 0 ]] || log_fail "TEST-3007: --check after --write must exit 0, got $GEN_RC: $GEN_OUT"
  log_pass "TEST-3007 the shipped list is complete and --check/--write keep it so"
}

# --- sync cases (TEST-3008 / TEST-3009) ----------------------------------------
run_sync() {  # <engine> <dst> [PATH-prefix]
  local engine="$1" dst="$2" pre="${3:-}" rc=0
  if [[ "$engine" == "ps1" ]]; then
    env -u AAI_ROLE pwsh -NoProfile -File "$SYNC_PS1" -TargetRoot "$dst" > "$dst.sync.log" 2>&1 || rc=$?
  elif [[ -n "$pre" ]]; then
    env -u AAI_ROLE PATH="$pre:$PATH" bash "$SYNC_SH" "$dst" > "$dst.sync.log" 2>&1 || rc=$?
  else
    env -u AAI_ROLE bash "$SYNC_SH" "$dst" > "$dst.sync.log" 2>&1 || rc=$?
  fi
  [[ "$rc" -eq 0 ]] || log_fail "run_sync: the real $engine sync into $dst failed with $rc: $(tail -5 "$dst.sync.log")"
}

seed_target() {  # <dst> <copilot-text-file>
  mkdir -p "$1/.github"
  git -C "$1" init -q -b main
  cp "$2" "$1/.github/copilot-instructions.md"
}

sync_copilot_cases() {  # <id> <engine>
  local id="$1" engine="$2" base="$TMP_ROOT/$1-$2" src="$PROJECT_ROOT/$COPILOT_REL"
  local blob_a="$base-blob-a.md" blob_b="$base-blob-b.md" blob_old="$base-blob-old.md" dst
  git -C "$PROJECT_ROOT" cat-file -e "$BASE_REF^{commit}" 2>/dev/null || log_fail "$id: base commit $BASE_REF is not in this clone (fetch-depth 0 needed)"
  git -C "$PROJECT_ROOT" show "$BASE_REF:$COPILOT_REL" > "$blob_a"
  git -C "$PROJECT_ROOT" show "070a6163:$COPILOT_REL" > "$blob_b"
  git -C "$PROJECT_ROOT" show "46751324:$COPILOT_REL" > "$blob_old"
  # (a) the previous shipped shim, unmodified
  dst="$base-a"; seed_target "$dst" "$blob_a"
  run_sync "$engine" "$dst"
  cmp -s "$src" "$dst/$COPILOT_REL" || log_fail "$id (a): a target holding the shipped $BASE_REF shim must end byte-equal to the source"
  [[ ! -e "$dst/docs/ai/project-overrides/copilot-instructions.project.md" ]] || log_fail "$id (a): the override file must not be written"
  # (a2) an older shipped shim (the 46751324 text) is replaced the same way
  dst="$base-a2"; seed_target "$dst" "$blob_old"
  run_sync "$engine" "$dst"
  cmp -s "$src" "$dst/$COPILOT_REL" || log_fail "$id (a2): a target holding the older shipped 46751324 shim must end byte-equal to the source"
  # (b) source shim plus an overrides block holding a shipped blob, with a stale override file
  dst="$base-b"; seed_target "$dst" "$src"
  {
    cat "$src"
    printf '\n---\n## Project Overrides (auto-merged)\n\n<!-- AAI-PROJECT-OVERRIDES:START -->\n'
    cat "$blob_b"
    printf '<!-- AAI-PROJECT-OVERRIDES:END -->\n'
  } > "$dst/$COPILOT_REL"
  mkdir -p "$dst/docs/ai/project-overrides"
  printf 'STALE OVERRIDE FILE\n' > "$dst/docs/ai/project-overrides/copilot-instructions.project.md"
  run_sync "$engine" "$dst"
  cmp -s "$src" "$dst/$COPILOT_REL" || log_fail "$id (b): a source shim plus a shipped-blob overrides block must end byte-equal to the source"
  [[ "$(cat "$dst/docs/ai/project-overrides/copilot-instructions.project.md")" == "STALE OVERRIDE FILE" ]] \
    || log_fail "$id (b): the override file must be left untouched"
  # (c) a real project override line is kept as before
  dst="$base-c"; seed_target "$dst" "$blob_a"
  printf -- '- PROJECT RULE: always run the linter first\n' >> "$dst/$COPILOT_REL"
  run_sync "$engine" "$dst"
  [[ "$(cat "$dst/$COPILOT_REL")" == *'Project Overrides (auto-merged)'* && "$(cat "$dst/$COPILOT_REL")" == *'PROJECT RULE: always run the linter first'* ]] \
    || log_fail "$id (c): a real project override line must stay in the auto-merged block"
}

test_3008_sync_sh_recognises_shipped_copilot() {
  log_info "TEST-3008: aai-sync.sh replaces a shipped Copilot shim, keeps a real override, degrades without a hash tool..."
  sync_copilot_cases TEST-3008 sh
  # (d) case (a) with no working hash tool: the old text is kept through the existing merge
  local stubs="$TMP_ROOT/t3008-stubs" dst="$TMP_ROOT/TEST-3008-sh-d" blob="$TMP_ROOT/TEST-3008-sh-blob-a.md" t
  mkdir -p "$stubs"
  for t in sha256sum shasum; do
    printf '#!/bin/sh\nexit 1\n' > "$stubs/$t"
    chmod +x "$stubs/$t"
  done
  seed_target "$dst" "$blob"
  run_sync sh "$dst" "$stubs"
  [[ "$(cat "$dst/$COPILOT_REL")" == *'Project Overrides (auto-merged)'* && "$(cat "$dst/$COPILOT_REL")" == *'## AAI Skills (post-sync)'* ]] \
    || log_fail "TEST-3008 (d): with no working hash tool the old text must be kept through the existing merge"
  log_pass "TEST-3008 aai-sync.sh recognises shipped Copilot shims"
}

need_pwsh() {  # <id>
  if ! command -v pwsh >/dev/null 2>&1; then
    PWSH_ARM_SKIPPED=1
    log_info "$1 note: pwsh absent, PowerShell arm SKIPPED"
    return 1
  fi
  return 0
}

test_3009_sync_ps1_recognises_shipped_copilot() {
  log_info "TEST-3009: aai-sync.ps1 replaces a shipped Copilot shim and keeps a real override..."
  need_pwsh TEST-3009 || return 0
  sync_copilot_cases TEST-3009 ps1
  log_pass "TEST-3009 aai-sync.ps1 recognises shipped Copilot shims"
}

# --- TEST-3010 / TEST-3011 -----------------------------------------------------
sync_agents_cases() {  # <id> <engine>
  local id="$1" engine="$2" base="$TMP_ROOT/$1-$2" dst out f report
  dst="$base-own"
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  printf '# My project agents\nproject specific rule\n' > "$dst/AGENTS.md"
  printf '# legacy playbook\n' > "$dst/PLAYBOOK.md"
  run_sync "$engine" "$dst"
  cmp -s "$PROJECT_ROOT/AGENTS.md" "$dst/AGENTS.md" || log_fail "$id: the target's own AGENTS.md must be replaced by the source AGENTS.md"
  out="$(cat "$dst.sync.log")"
  [[ "$out" != *'MIGRATE removed legacy root: AGENTS.md'* ]] || log_fail "$id: the sync must not print 'MIGRATE removed legacy root: AGENTS.md'"
  [[ "$out" == *'MIGRATE removed legacy root: PLAYBOOK.md'* && ! -e "$dst/PLAYBOOK.md" ]] \
    || log_fail "$id: a legacy root PLAYBOOK.md must still be removed"
  report=""
  for f in "$dst"/docs/ai/reports/sync-conflicts-*.md; do [[ -f "$f" ]] && report="$f"; done
  [[ -n "$report" ]] || log_fail "$id: no sync conflict advisory was written"
  [[ "$(cat "$report")" == *'AGENTS.md'* ]] || log_fail "$id: the conflict advisory must name AGENTS.md"
  # a fresh target receives all six shims and passes the gate with its own generator
  dst="$base-fresh"
  mkdir -p "$dst"
  git -C "$dst" init -q -b main
  run_sync "$engine" "$dst"
  for f in "${SHIMS[@]}"; do
    cmp -s "$PROJECT_ROOT/$f" "$dst/$f" || log_fail "$id: a fresh target's $f must be byte-equal to the source"
  done
  out="$(env -u AAI_ROLE node "$dst/.aai/scripts/sync-harness-skills.mjs" --check --root "$dst" 2>&1)" && f=0 || f=$?
  [[ "$f" -eq 0 && "$out" == *'OK: 6 shim(s) match the registry'* ]] \
    || log_fail "$id: the target's own generator --check --root must exit 0 with the shim OK line, got rc=$f: $out"
}

test_3010_sync_sh_installs_agents_md() {
  log_info "TEST-3010: aai-sync.sh installs AGENTS.md instead of deleting it..."
  sync_agents_cases TEST-3010 sh
  log_pass "TEST-3010 aai-sync.sh installs the root AGENTS.md and a fresh target passes the gate"
}

test_3011_sync_ps1_installs_agents_md() {
  log_info "TEST-3011: aai-sync.ps1 installs AGENTS.md instead of deleting it..."
  need_pwsh TEST-3011 || return 0
  sync_agents_cases TEST-3011 ps1
  log_pass "TEST-3011 aai-sync.ps1 installs the root AGENTS.md and a fresh target passes the gate"
}

# --- TEST-3012 / TEST-3013 / TEST-3014 -----------------------------------------
test_3012_pr501_amendments_signed() {
  log_info "TEST-3012: the six #501 amendments read signed, their trackers done, the routing records untouched..."
  local keys=(98ec877de848 949419e17d08 f4fc1fe9a179 f6993ac19a97 d2d5f37e6ed6 083edab1cd4f)
  local trackers=(fu-amend-directed-merge-and-post-35bbb0 fu-amend-merge-cleanup-submodule-b2d758 fu-amend-merge-cleanup-ride-lefto-1ce832 fu-amend-merge-cleanup-ride-lefto-007e1e fu-amend-merge-cleanup-resolves-f-1abe0b)
  local out
  out="$(node "$SPEC_AMEND" list --json --status all --ledger "$LEDGER")" || log_fail "TEST-3012: spec-amend list --json failed"
  printf '%s' "$out" > "$TMP_ROOT/amend-list.json"
  local fu
  fu="$(node "$FOLLOW_UPS" list --json --status all --ledger "$LEDGER")" || log_fail "TEST-3012: follow-ups list --json failed"
  printf '%s' "$fu" > "$TMP_ROOT/fu-list.json"
  local verdict
  verdict="$(node -e '
    const fs = require("fs");
    const [amendFile, fuFile, ledger, keys, trackers] = process.argv.slice(1);
    const amend = JSON.parse(fs.readFileSync(amendFile, "utf8"));
    const fu = JSON.parse(fs.readFileSync(fuFile, "utf8"));
    const lines = fs.readFileSync(ledger, "utf8").split("\n").filter((l) => l.startsWith("{")).map((l) => JSON.parse(l));
    const problems = [];
    if (amend.items.length < 500) problems.push("positive control: only " + amend.items.length + " amendment items read");
    const byKey = new Map(amend.items.map((i) => [i.record_key, i]));
    for (const k of keys.split(",")) {
      const it = byKey.get(k);
      if (!it) { problems.push("record " + k + " not listed"); continue; }
      if (it.bucket !== "signed") problems.push("record " + k + " reads " + it.bucket);
      const ov = lines.filter((l) => l.type === "spec_amendment_classification" && l.classifies_record === k);
      if (ov.length !== 1) { problems.push("record " + k + " has " + ov.length + " overlays"); continue; }
      const src = String(ov[0].source || "");
      if (!/PR #501/.test(src)) problems.push("overlay " + k + " source lacks PR #501");
      if (ov[0].owner_signoff !== true) problems.push("overlay " + k + " is not an owner signoff");
      const m = src.match(/hitl_decision (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)/);
      if (!m) { problems.push("overlay " + k + " source names no hitl_decision ts"); continue; }
      const h = lines.filter((l) => l.type === "hitl_decision" && l.ts === m[1]);
      if (h.length !== 1 || h[0].answer !== "Mergni #501 (Recommended)") problems.push("hitl_decision " + m[1] + " does not resolve to the owner answer");
    }
    const fuItems = fu.items || fu;
    for (const t of trackers.split(",")) {
      const it = fuItems.find((i) => i.id === t);
      if (!it || it.status !== "done") problems.push("tracker " + t + " reads " + (it ? it.status : "absent"));
    }
    const routing = amend.items.filter((i) => i.ref_id === "routing-tables-have-an-owner-and-a-seam");
    if (routing.length !== 2 || routing.some((i) => i.bucket !== "unsigned-tracked")) problems.push("the two routing-tables records must stay unsigned-tracked (found " + routing.length + ")");
    process.stdout.write(problems.join("; "));
  ' "$TMP_ROOT/amend-list.json" "$TMP_ROOT/fu-list.json" "$LEDGER" "$(IFS=,; echo "${keys[*]}")" "$(IFS=,; echo "${trackers[*]}")")" \
    || log_fail "TEST-3012: the ledger reader crashed"
  [[ -z "$verdict" ]] || log_fail "TEST-3012: $verdict"
  node "$SPEC_AMEND" list --strict --ledger "$LEDGER" > "$TMP_ROOT/strict.out" 2>&1 && out=0 || out=$?
  [[ "$out" -eq 0 ]] || log_fail "TEST-3012: spec-amend list --strict must exit 0, got $out: $(tail -3 "$TMP_ROOT/strict.out")"
  log_pass "TEST-3012 the #501 amendments are signed, trackers done, routing records untouched"
}

test_3013_autonomous_loop_names_classify() {
  log_info "TEST-3013: AUTONOMOUS_LOOP.md names the classify procedure and not sign-merged..."
  local f="$PROJECT_ROOT/.aai/system/AUTONOMOUS_LOOP.md" content line hit=0
  content="$(cat "$f")"
  [[ "$content" != *'sign-merged'* ]] || log_fail "TEST-3013: AUTONOMOUS_LOOP.md still names sign-merged"
  # the sentence replacing it: one line naming spec-amend.mjs classify with --record and --signoff owner
  while IFS= read -r line; do
    if [[ "$line" == *'spec-amend.mjs classify'* && "$line" == *'--record'* && "$line" == *'--signoff owner'* ]]; then hit=$((hit + 1)); fi
  done < "$f"
  [[ "$hit" -eq 1 ]] || log_fail "TEST-3013: want exactly one line naming spec-amend.mjs classify with --record and --signoff owner, found $hit"
  log_pass "TEST-3013 AUTONOMOUS_LOOP.md names the classify procedure"
}

test_3014_profiles_caps_followups() {
  log_info "TEST-3014: PROFILES core rows, line caps, the two follow-ups..."
  local f profiles="$PROJECT_ROOT/.aai/system/PROFILES.yaml" core lines fu
  core="$(sed -n '/^core:/,/^extended:/p' "$profiles")"
  for f in .aai/scripts/lib/harness-shims.mjs .aai/system/HARNESS_SHIMS.md .aai/system/COPILOT_SHIM_SHIPPED.list; do
    [[ -f "$PROJECT_ROOT/$f" ]] || log_fail "TEST-3014: $f does not exist"
    grep -qxF "  - $f" <<< "$core" || log_fail "TEST-3014: $f is not in the core list of PROFILES.yaml"
  done
  lines="$(wc -l < "$PROJECT_ROOT/.aai/scripts/lib/harness-shims.mjs" | tr -d ' ')"
  [[ "$lines" -le 260 ]] || log_fail "TEST-3014: lib/harness-shims.mjs has $lines lines, cap 260"
  lines="$(wc -l < "$GEN" | tr -d ' ')"
  [[ "$lines" -le 590 ]] || log_fail "TEST-3014: sync-harness-skills.mjs has $lines lines, cap 590"
  fu="$(node "$FOLLOW_UPS" list --json --status open --ledger "$LEDGER")" || log_fail "TEST-3014: follow-ups list failed"
  printf '%s' "$fu" > "$TMP_ROOT/fu-open.json"
  f="$(node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); const items = j.items || j;
    const text = (i) => JSON.stringify(i);
    const p = [];
    const a = items.find((i) => i.id === "fu-skills-md-quickref-missing-rows");
    if (!a || !/37 of 42/.test(text(a))) p.push("fu-skills-md-quickref-missing-rows must be open and carry 37 of 42");
    const b = items.find((i) => i.id === "fu-shim-prompt-file-flag-unverified");
    if (!b || !/prompt-file/.test(text(b))) p.push("fu-shim-prompt-file-flag-unverified must be open and name prompt-file");
    process.stdout.write(p.join("; "));
  ' "$TMP_ROOT/fu-open.json")" || log_fail "TEST-3014: follow-up reader crashed"
  [[ -z "$f" ]] || log_fail "TEST-3014: $f"
  log_pass "TEST-3014 PROFILES rows, line caps and the two follow-ups hold"
}

# --- dispatch ------------------------------------------------------------------
finish_pwsh_check() {
  if [[ "$PWSH_ARM_SKIPPED" -eq 1 && "${AAI_ALLOW_PWSH_SKIP:-}" != "1" ]]; then
    log_fail "pwsh is absent, so a PowerShell arm did not run; install pwsh or set AAI_ALLOW_PWSH_SKIP=1 to accept the skip"
  fi
}

ALL_TESTS=(
  test_3001_shims_render_from_registry
  test_3002_copilot_lists_no_skills
  test_3003_check_reports_each_divergence
  test_3004_write_restores_and_is_idempotent
  test_3005_shim_paths_select_the_gate
  test_3007_shipped_list_complete
  test_3008_sync_sh_recognises_shipped_copilot
  test_3009_sync_ps1_recognises_shipped_copilot
  test_3010_sync_sh_installs_agents_md
  test_3011_sync_ps1_installs_agents_md
  test_3012_pr501_amendments_signed
  test_3013_autonomous_loop_names_classify
  test_3014_profiles_caps_followups
)

main() {
  echo "=== Test Suite: $TEST_NAME ==="
  check_deps
  local t fn
  if [[ "${1:-}" == "--test" ]]; then
    t="${2:-}"
    [[ "$t" =~ ^TEST-[0-9]+$ ]] || log_fail "--test wants TEST-<n>, got [$t]"
    fn="$(compgen -A function "test_${t#TEST-}_" | qhead -n1)" || fn=""
    [[ -n "$fn" ]] || log_fail "no test function for $t (TEST-3006 lives in test-aai-hygiene-pack.sh test_111)"
    "$fn"
    finish_pwsh_check
    return 0
  fi
  if [[ $# -ge 1 ]]; then
    declare -F "$1" >/dev/null 2>&1 || log_fail "unknown test function: $1"
    "$1"
    finish_pwsh_check
    return 0
  fi
  for t in "${ALL_TESTS[@]}"; do "$t"; done
  finish_pwsh_check
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
