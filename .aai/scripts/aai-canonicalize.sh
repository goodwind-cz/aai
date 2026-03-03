#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${1:-$(pwd)}"
DRY_RUN="${2:-}"

if [[ ! -d "$TARGET_ROOT" ]]; then
  echo "ERROR: target directory does not exist: $TARGET_ROOT"
  exit 1
fi

ROOT="$(cd "$TARGET_ROOT" && pwd)"
TS_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
REPORT_PATH="$ROOT/docs/ai/reports/MIGRATION_REPORT_$TS_UTC.md"
TECH_PATH="$ROOT/docs/TECHNOLOGY.md"
MIGRATED_ROOT="$ROOT/docs/ai/reports/migrated/$TS_UTC"

is_dry_run=false
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  is_dry_run=true
fi

log_dry() {
  if $is_dry_run; then
    echo "DRYRUN $*"
  fi
}

ensure_dir() {
  local p="$1"
  if [[ -d "$p" ]]; then
    return
  fi
  if $is_dry_run; then
    log_dry "create dir: $p"
    return
  fi
  mkdir -p "$p"
}

move_safely() {
  local src="$1"
  local dst="$2"
  if [[ ! -e "$src" ]]; then
    return 1
  fi
  ensure_dir "$(dirname "$dst")"
  if $is_dry_run; then
    log_dry "move: $src -> $dst"
    return 0
  fi
  mv "$src" "$dst"
  return 0
}

canonical_dirs=(
  "ai"
  "docs"
  "docs/ai"
  "docs/ai/reports"
  "docs/knowledge"
  "docs/templates"
  "docs/workflow"
  "docs/roles"
  "docs/issues"
  "docs/specs"
  "docs/requirements"
  "docs/releases"
  "docs/rfc"
  "scripts"
  ".claude/skills"
  ".codex/skills"
  ".gemini/skills"
)

for d in "${canonical_dirs[@]}"; do
  ensure_dir "$ROOT/$d"
done

declare -a actions=()

yaml_loop="$ROOT/docs/ai/LOOP_TICKS.yaml"
yaml_metrics="$ROOT/docs/ai/METRICS.yaml"
migrate_script="$ROOT$ROOT/.aai/scripts/migrate-yaml-to-jsonl.sh"
if [[ -x "$migrate_script" && ( -f "$yaml_loop" || -f "$yaml_metrics" ) ]]; then
  if $is_dry_run; then
    log_dry "migrate yaml->jsonl: $migrate_script \"$ROOT\""
  else
    "$migrate_script" "$ROOT"
  fi
  actions+=("Migrated YAML runtime files into JSONL format.")
fi

if [[ -f "$yaml_loop" ]]; then
  if $is_dry_run; then
    log_dry "remove: $yaml_loop"
  else
    rm -f "$yaml_loop"
  fi
  actions+=("Removed legacy docs/ai/LOOP_TICKS.yaml after JSONL migration.")
fi
if [[ -f "$yaml_metrics" ]]; then
  if $is_dry_run; then
    log_dry "remove: $yaml_metrics"
  else
    rm -f "$yaml_metrics"
  fi
  actions+=("Removed legacy docs/ai/METRICS.yaml after JSONL migration.")
fi

supported_docs=(ai workflow roles templates knowledge issues specs requirements releases rfc)
if [[ -d "$ROOT/docs" ]]; then
  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    keep=false
    for s in "${supported_docs[@]}"; do
      if [[ "$name" == "$s" ]]; then
        keep=true
        break
      fi
    done
    if ! $keep; then
      if move_safely "$path" "$MIGRATED_ROOT/docs/$name"; then
        actions+=("Moved unsupported directory docs/$name -> docs/ai/reports/migrated/$TS_UTC/docs/$name")
      fi
    fi
  done < <(find "$ROOT/docs" -mindepth 1 -maxdepth 1 -type d -print0)
fi

for legacy in validation evidence reports; do
  if move_safely "$ROOT/$legacy" "$MIGRATED_ROOT/legacy-root/$legacy"; then
    actions+=("Moved root-level legacy evidence directory $legacy/ -> docs/ai/reports/migrated/$TS_UTC/legacy-root/$legacy/")
  fi
done

languages=()
package_managers=()
test_tools=()
build_tools=()
ci_signals=()

if [[ -f "$ROOT/package.json" ]]; then
  languages+=("JavaScript/TypeScript")
  package_managers+=("npm/pnpm/yarn (package.json)")
fi
if [[ -f "$ROOT/pyproject.toml" || -f "$ROOT/requirements.txt" ]]; then
  languages+=("Python")
  package_managers+=("pip/poetry (python manifests)")
fi
if [[ -f "$ROOT/go.mod" ]]; then
  languages+=("Go")
  package_managers+=("go modules")
fi
if [[ -f "$ROOT/Cargo.toml" ]]; then
  languages+=("Rust")
  package_managers+=("cargo")
fi
if [[ -f "$ROOT/pom.xml" || -f "$ROOT/build.gradle" ]]; then
  languages+=("Java")
  package_managers+=("maven/gradle")
fi

for f in playwright.config.ts playwright.config.js cypress.config.ts cypress.config.js jest.config.ts jest.config.js vitest.config.ts vitest.config.js pytest.ini; do
  [[ -f "$ROOT/$f" ]] && test_tools+=("$f")
done
for f in vite.config.ts vite.config.js webpack.config.js tsconfig.json Dockerfile; do
  [[ -f "$ROOT/$f" ]] && build_tools+=("$f")
done
[[ -d "$ROOT/.github/workflows" ]] && ci_signals+=(".github/workflows")

list_or_default() {
  local default_text="$1"
  shift
  if [[ "$#" -eq 0 ]]; then
    echo "- $default_text"
    return
  fi
  for item in "$@"; do
    echo "- $item"
  done
}

tech_content="$(cat <<EOF
# Technology Contract

Generated at (UTC): $NOW_UTC
Generator: .aai/scripts/ai-os-canonicalize.sh

## Languages
$(list_or_default "Unknown (no common manifest detected)" "${languages[@]}")

## Package/Dependency Managers
$(list_or_default "Not detected" "${package_managers[@]}")

## Test Tooling (Detected by Files)
$(list_or_default "Not detected" "${test_tools[@]}")

## Build/Runtime Tooling (Detected by Files)
$(list_or_default "Not detected" "${build_tools[@]}")

## CI/CD Signals
$(list_or_default "Not detected" "${ci_signals[@]}")

## Notes
- This is an inferred summary based on repository files.
- Refine this contract with .aai/TECH_EXTRACT.prompt.md when deeper accuracy is required.
EOF
)"

if $is_dry_run; then
  log_dry "write: $TECH_PATH"
else
  printf "%s\n" "$tech_content" > "$TECH_PATH"
fi
actions+=("Updated docs/TECHNOLOGY.md from repository structure.")

if [[ "${#actions[@]}" -eq 0 ]]; then
  action_lines="- No migration actions were necessary."
else
  action_lines=""
  for a in "${actions[@]}"; do
    action_lines+="- $a"$'\n'
  done
  action_lines="${action_lines%$'\n'}"
fi

migrated_lines="- No legacy directories required migration."
if [[ "${#actions[@]}" -gt 0 ]]; then
  tmp=""
  for a in "${actions[@]}"; do
    if [[ "$a" == Moved* ]]; then
      tmp+="- $a"$'\n'
    fi
  done
  if [[ -n "$tmp" ]]; then
    migrated_lines="${tmp%$'\n'}"
  fi
fi

report_content="$(cat <<EOF
# AI-OS Canonicalization Report

- Generated at (UTC): $NOW_UTC
- Target root: $ROOT
- DryRun: $is_dry_run

## Actions
$action_lines

## Canonical Outputs
- docs/TECHNOLOGY.md
- docs/ai/METRICS.jsonl
- docs/ai/LOOP_TICKS.jsonl
- docs/ai/reports/

## Migrated Legacy Content
$migrated_lines

## Follow-up
- Run .aai/SKILL_CHECK_STATE.prompt.md to verify state invariants.
- Run .aai/ORCHESTRATION.prompt.md to continue normal workflow.
EOF
)"

if $is_dry_run; then
  log_dry "write: $REPORT_PATH"
else
  printf "%s\n" "$report_content" > "$REPORT_PATH"
fi

echo "Done."
echo "Report: $REPORT_PATH"
