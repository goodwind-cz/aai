#!/usr/bin/env bash
set -euo pipefail

# Generate project-local AAI dynamic skills from evidence in the target repo.
#
# Usage:
#   ./.aai/scripts/aai-bootstrap.sh [target-root] [--dry-run] [--force]
#
# Safety model:
# - Creates or updates only known dynamic skill files and local discovery indexes.
# - Refuses to overwrite a skill file that does not contain the AAI dynamic marker.
# - --dry-run prints planned writes without changing files.
# - --force is the explicit confirmation for replacing unmarked dynamic skill paths.

DRY_RUN=0
FORCE=0
TARGET=""
GENERATOR=".aai/scripts/aai-bootstrap.sh"
SKILL_MARKER="AAI-DYNAMIC-SKILL:START"
FILE_MARKER="AAI-DYNAMIC-FILE:START"

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$arg"
      else
        echo "ERROR: unexpected argument: $arg" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

ROOT="$(cd "${TARGET:-$(pwd)}" && pwd)"
cd "$ROOT"

NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

declare -a DETECTED_LANGUAGES=()
declare -a DETECTED_PACKAGE_MANAGERS=()
declare -a DETECTED_TEST_TOOLS=()
declare -a DETECTED_BUILD_TOOLS=()
declare -a DETECTED_LINT_TOOLS=()
declare -a DETECTED_CI=()
declare -a DETECTED_DEPLOY=()
declare -a SKILL_NAMES=()
declare -a SKILL_DESCRIPTIONS=()
declare -a SKILL_COMMANDS=()
declare -a SKILL_EXTRA=()
declare -a SKIPPED=()
declare -a CONFLICTS=()
declare -a WRITTEN=()
declare -a UNCHANGED=()

PACKAGE_MANAGER=""
AUTH_DETECTED=0
AUTH_CREDENTIALS_REF=""
AUTH_SESSION_REF=""

log() {
  echo "$*"
}

add_unique() {
  local value="$1"
  local array_name="$2"
  local existing
  local current=()
  eval "current=(\"\${${array_name}[@]}\")"
  for existing in "${current[@]}"; do
    [[ "$existing" == "$value" ]] && return 0
  done
  eval "${array_name}+=(\"\$value\")"
}

has_glob() {
  local pattern="$1"
  compgen -G "$pattern" >/dev/null
}

first_glob() {
  local pattern="$1"
  local match
  for match in $pattern; do
    [[ -e "$match" ]] && {
      printf '%s\n' "$match"
      return 0
    }
  done
  return 1
}

json_has_package_script() {
  local script_name="$1"
  [[ -f package.json ]] || return 1
  if command -v node >/dev/null 2>&1; then
    node -e '
const fs = require("fs");
const script = process.argv[1];
try {
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  process.exit(pkg.scripts && Object.prototype.hasOwnProperty.call(pkg.scripts, script) ? 0 : 1);
} catch (e) {
  process.exit(1);
}
' "$script_name" 2>/dev/null
  else
    grep -Eq "\"$script_name\"[[:space:]]*:" package.json
  fi
}

json_has_package_dep() {
  local dep_name="$1"
  [[ -f package.json ]] || return 1
  if command -v node >/dev/null 2>&1; then
    node -e '
const fs = require("fs");
const dep = process.argv[1];
try {
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  const buckets = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];
  process.exit(buckets.some((name) => pkg[name] && Object.prototype.hasOwnProperty.call(pkg[name], dep)) ? 0 : 1);
} catch (e) {
  process.exit(1);
}
' "$dep_name" 2>/dev/null
  else
    grep -Eq "\"$dep_name\"[[:space:]]*:" package.json
  fi
}

json_has_package_key() {
  local key_name="$1"
  [[ -f package.json ]] || return 1
  if command -v node >/dev/null 2>&1; then
    node -e '
const fs = require("fs");
const key = process.argv[1];
try {
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  process.exit(Object.prototype.hasOwnProperty.call(pkg, key) ? 0 : 1);
} catch (e) {
  process.exit(1);
}
' "$key_name" 2>/dev/null
  else
    grep -Eq "\"$key_name\"[[:space:]]*:" package.json
  fi
}

detect_package_manager() {
  [[ -f package.json ]] || return 0
  if [[ -f pnpm-lock.yaml ]]; then
    PACKAGE_MANAGER="pnpm"
  elif [[ -f yarn.lock ]]; then
    PACKAGE_MANAGER="yarn"
  elif [[ -f bun.lock || -f bun.lockb ]]; then
    PACKAGE_MANAGER="bun"
  else
    PACKAGE_MANAGER="npm"
  fi
  add_unique "$PACKAGE_MANAGER (package.json)" DETECTED_PACKAGE_MANAGERS
}

pkg_run_command() {
  local script_name="$1"
  case "$PACKAGE_MANAGER" in
    npm)
      if [[ "$script_name" == "test" ]]; then
        printf 'npm test\n'
      else
        printf 'npm run %s\n' "$script_name"
      fi
      ;;
    pnpm)
      printf 'pnpm run %s\n' "$script_name"
      ;;
    yarn)
      printf 'yarn run %s\n' "$script_name"
      ;;
    bun)
      printf 'bun run %s\n' "$script_name"
      ;;
    *)
      printf 'npm run %s\n' "$script_name"
      ;;
  esac
}

pkg_exec_command() {
  local tool="$1"
  shift || true
  local rest="$*"
  case "$PACKAGE_MANAGER" in
    pnpm)
      printf 'pnpm exec %s' "$tool"
      ;;
    yarn)
      printf 'yarn exec %s' "$tool"
      ;;
    bun)
      printf 'bunx %s' "$tool"
      ;;
    *)
      printf 'npx %s' "$tool"
      ;;
  esac
  [[ -n "$rest" ]] && printf ' %s' "$rest"
  printf '\n'
}

find_package_script_command() {
  local script_name
  for script_name in "$@"; do
    if json_has_package_script "$script_name"; then
      pkg_run_command "$script_name"
      return 0
    fi
  done
  return 1
}

justfile_path() {
  if [[ -f justfile ]]; then
    printf 'justfile\n'
  elif [[ -f Justfile ]]; then
    printf 'Justfile\n'
  else
    return 1
  fi
}

makefile_path() {
  if [[ -f Makefile ]]; then
    printf 'Makefile\n'
  elif [[ -f makefile ]]; then
    printf 'makefile\n'
  else
    return 1
  fi
}

target_exists_in_justfile() {
  local target="$1"
  local file
  file="$(justfile_path 2>/dev/null)" || return 1
  grep -Eq "^[[:space:]]*$target([[:space:]].*)?:" "$file"
}

target_exists_in_makefile() {
  local target="$1"
  local file
  file="$(makefile_path 2>/dev/null)" || return 1
  grep -Eq "^[[:space:]]*$target[[:space:]]*:" "$file"
}

find_task_runner_command() {
  local target
  for target in "$@"; do
    if target_exists_in_justfile "$target"; then
      printf 'just %s\n' "$target"
      return 0
    fi
    if target_exists_in_makefile "$target"; then
      printf 'make %s\n' "$target"
      return 0
    fi
  done
  return 1
}

detect_architecture() {
  detect_package_manager

  if [[ -f package.json ]]; then
    add_unique "JavaScript/TypeScript" DETECTED_LANGUAGES
    json_has_package_key "workspaces" && add_unique "package.json workspaces" DETECTED_BUILD_TOOLS
  fi
  if [[ -f pyproject.toml || -f requirements.txt || -f poetry.lock || -f uv.lock || -f setup.cfg || -f setup.py ]]; then
    add_unique "Python" DETECTED_LANGUAGES
    if [[ -f poetry.lock ]]; then
      add_unique "poetry (poetry.lock)" DETECTED_PACKAGE_MANAGERS
    elif [[ -f uv.lock ]]; then
      add_unique "uv (uv.lock)" DETECTED_PACKAGE_MANAGERS
    else
      add_unique "pip/python (python manifest)" DETECTED_PACKAGE_MANAGERS
    fi
  fi
  if [[ -f go.mod ]]; then
    add_unique "Go" DETECTED_LANGUAGES
    add_unique "go modules (go.mod)" DETECTED_PACKAGE_MANAGERS
  fi
  if [[ -f Cargo.toml ]]; then
    add_unique "Rust" DETECTED_LANGUAGES
    add_unique "cargo (Cargo.toml)" DETECTED_PACKAGE_MANAGERS
  fi
  if [[ -f pom.xml ]]; then
    add_unique "Java" DETECTED_LANGUAGES
    add_unique "maven (pom.xml)" DETECTED_PACKAGE_MANAGERS
  fi
  if [[ -f build.gradle || -f build.gradle.kts || -f gradlew ]]; then
    add_unique "Java/Kotlin" DETECTED_LANGUAGES
    add_unique "gradle" DETECTED_PACKAGE_MANAGERS
  fi

  has_glob "playwright.config.*" && add_unique "Playwright" DETECTED_TEST_TOOLS
  has_glob "cypress.config.*" && add_unique "Cypress" DETECTED_TEST_TOOLS
  has_glob "jest.config.*" && add_unique "Jest" DETECTED_TEST_TOOLS
  has_glob "vitest.config.*" && add_unique "Vitest" DETECTED_TEST_TOOLS
  [[ -f pytest.ini || -f tox.ini ]] && add_unique "pytest" DETECTED_TEST_TOOLS
  [[ -d tests || -d test ]] && add_unique "test directory" DETECTED_TEST_TOOLS

  has_glob "vite.config.*" && add_unique "Vite" DETECTED_BUILD_TOOLS
  has_glob "webpack.config.*" && add_unique "Webpack" DETECTED_BUILD_TOOLS
  [[ -f tsconfig.json ]] && add_unique "TypeScript (tsconfig.json)" DETECTED_BUILD_TOOLS
  [[ -f Dockerfile ]] && add_unique "Dockerfile" DETECTED_BUILD_TOOLS
  [[ -f docker-compose.yml || -f compose.yml ]] && add_unique "Docker Compose" DETECTED_BUILD_TOOLS
  makefile_path >/dev/null 2>&1 && add_unique "Makefile" DETECTED_BUILD_TOOLS
  justfile_path >/dev/null 2>&1 && add_unique "justfile" DETECTED_BUILD_TOOLS

  has_glob ".eslintrc*" && add_unique "ESLint config" DETECTED_LINT_TOOLS
  [[ -f eslint.config.js || -f eslint.config.mjs || -f eslint.config.cjs ]] && add_unique "ESLint config" DETECTED_LINT_TOOLS
  [[ -f biome.json || -f biome.jsonc ]] && add_unique "Biome" DETECTED_LINT_TOOLS
  [[ -f ruff.toml ]] && add_unique "Ruff" DETECTED_LINT_TOOLS
  if [[ -f pyproject.toml ]] && grep -Eq '\[tool\.ruff\]|\[tool\.flake8\]|\[tool\.black\]' pyproject.toml; then
    add_unique "Python lint config (pyproject.toml)" DETECTED_LINT_TOOLS
  fi

  [[ -d .github/workflows ]] && add_unique ".github/workflows" DETECTED_CI
  [[ -f wrangler.toml ]] && add_unique "Cloudflare Wrangler" DETECTED_DEPLOY
  [[ -f vercel.json ]] && add_unique "Vercel" DETECTED_DEPLOY
  [[ -f netlify.toml ]] && add_unique "Netlify" DETECTED_DEPLOY

  return 0
}

choose_unit_command() {
  find_task_runner_command test-unit unit test && return 0
  find_package_script_command test:unit unit test && return 0

  if has_glob "vitest.config.*" || json_has_package_dep "vitest"; then
    pkg_exec_command vitest run
    return 0
  fi
  if has_glob "jest.config.*" || json_has_package_dep "jest"; then
    pkg_exec_command jest
    return 0
  fi
  if [[ -f pytest.ini ]] || grep -Rqs "pytest" pyproject.toml requirements.txt setup.cfg tox.ini 2>/dev/null; then
    printf 'pytest\n'
    return 0
  fi
  if [[ -f go.mod ]]; then
    printf 'go test ./...\n'
    return 0
  fi
  if [[ -f Cargo.toml ]]; then
    printf 'cargo test\n'
    return 0
  fi
  if [[ -f pom.xml ]]; then
    printf 'mvn test\n'
    return 0
  fi
  if [[ -f gradlew ]]; then
    printf './gradlew test\n'
    return 0
  fi
  if [[ -f build.gradle || -f build.gradle.kts ]]; then
    printf 'gradle test\n'
    return 0
  fi
  return 1
}

choose_e2e_command() {
  has_glob "playwright.config.*" || has_glob "cypress.config.*" || json_has_package_script "test:e2e" || json_has_package_script "e2e" || return 1

  find_task_runner_command test-e2e e2e test_e2e && return 0
  find_package_script_command test:e2e e2e playwright cypress:run cy:run && return 0

  if has_glob "playwright.config.*" || json_has_package_dep "@playwright/test" || json_has_package_dep "playwright"; then
    pkg_exec_command playwright test
    return 0
  fi
  if has_glob "cypress.config.*" || json_has_package_dep "cypress"; then
    pkg_exec_command cypress run
    return 0
  fi
  return 1
}

choose_build_command() {
  find_task_runner_command build compile && return 0
  find_package_script_command build compile && return 0

  if has_glob "vite.config.*" || json_has_package_dep "vite"; then
    pkg_exec_command vite build
    return 0
  fi
  if has_glob "webpack.config.*" || json_has_package_dep "webpack"; then
    pkg_exec_command webpack
    return 0
  fi
  if [[ -f tsconfig.json ]] && json_has_package_dep "typescript"; then
    pkg_exec_command tsc --noEmit
    return 0
  fi
  if [[ -f go.mod ]]; then
    printf 'go build ./...\n'
    return 0
  fi
  if [[ -f Cargo.toml ]]; then
    printf 'cargo build\n'
    return 0
  fi
  if [[ -f pom.xml ]]; then
    printf 'mvn package\n'
    return 0
  fi
  if [[ -f gradlew ]]; then
    printf './gradlew build\n'
    return 0
  fi
  if [[ -f build.gradle || -f build.gradle.kts ]]; then
    printf 'gradle build\n'
    return 0
  fi
  if [[ -f Dockerfile ]]; then
    printf 'docker build -t %s .\n' "$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_.-' '-')"
    return 0
  fi
  return 1
}

choose_lint_command() {
  find_task_runner_command lint check lint-check && return 0
  find_package_script_command lint check typecheck && return 0

  if [[ -f eslint.config.js || -f eslint.config.mjs || -f eslint.config.cjs ]] || has_glob ".eslintrc*" || json_has_package_dep "eslint"; then
    pkg_exec_command eslint .
    return 0
  fi
  if [[ -f biome.json || -f biome.jsonc ]] || json_has_package_dep "@biomejs/biome"; then
    pkg_exec_command biome check .
    return 0
  fi
  if [[ -f ruff.toml ]] || grep -Rqs "ruff" pyproject.toml requirements.txt 2>/dev/null; then
    printf 'ruff check .\n'
    return 0
  fi
  if grep -Rqs "flake8" pyproject.toml requirements.txt setup.cfg tox.ini 2>/dev/null; then
    printf 'flake8\n'
    return 0
  fi
  if [[ -f go.mod ]]; then
    printf 'go vet ./...\n'
    return 0
  fi
  if [[ -f Cargo.toml ]]; then
    printf 'cargo clippy --all-targets --all-features\n'
    return 0
  fi
  return 1
}

is_python_project() {
  [[ -f pyproject.toml || -f requirements.txt || -f poetry.lock || -f uv.lock || -f setup.cfg || -f setup.py ]] && return 0
  return 1
}

choose_monty_command() {
  is_python_project || return 1
  printf 'python -c "import pydantic_monty; print('\''pydantic-monty available'\'')"\n'
}

choose_deploy_command() {
  find_task_runner_command deploy publish release && return 0
  find_package_script_command deploy publish release && return 0

  if [[ -f wrangler.toml ]]; then
    printf 'wrangler deploy\n'
    return 0
  fi
  if [[ -f vercel.json ]]; then
    printf 'vercel deploy\n'
    return 0
  fi
  if [[ -f netlify.toml ]]; then
    printf 'netlify deploy\n'
    return 0
  fi
  return 1
}

detect_auth() {
  choose_e2e_command >/dev/null 2>&1 || return 0

  local auth_paths=()
  local candidate
  for candidate in app src pages components routes tests e2e cypress package.json; do
    [[ -e "$candidate" ]] && auth_paths+=("$candidate")
  done
  for candidate in middleware.ts middleware.js playwright.config.* cypress.config.*; do
    [[ -e "$candidate" ]] && auth_paths+=("$candidate")
  done
  [[ "${#auth_paths[@]}" -gt 0 ]] || return 0

  local found=1
  if command -v rg >/dev/null 2>&1; then
    rg -i --glob '!node_modules' --glob '!.git' --glob '!dist' --glob '!build' \
      '(login|sign-in|auth|session|jwt|passport|next-auth|clerk|requireAuth|withAuth|storageState|globalSetup)' \
      "${auth_paths[@]}" \
      >/dev/null 2>&1 && found=0
  else
    grep -RsiE '(login|sign-in|auth|session|jwt|passport|next-auth|clerk|requireAuth|withAuth|storageState|globalSetup)' \
      "${auth_paths[@]}" \
      >/dev/null 2>&1 && found=0
  fi

  [[ "$found" -eq 0 ]] || return 0
  AUTH_DETECTED=1

  if [[ -f docs/knowledge/FACTS.md ]] && grep -Eq '^## Test Credentials' docs/knowledge/FACTS.md; then
    AUTH_CREDENTIALS_REF='docs/knowledge/FACTS.md, section "Test Credentials"'
  else
    local env_file
    for env_file in .env.e2e .env.test .env.testing; do
      if [[ -f "$env_file" ]]; then
        local vars
        vars="$(grep -E '^(TEST|E2E|PLAYWRIGHT|CYPRESS|AUTH|LOGIN).*(_USER|_EMAIL|_PASSWORD|_PASS|_TOKEN)=' "$env_file" 2>/dev/null | cut -d= -f1 | awk 'NF { out = out ? out ", " $0 : $0 } END { print out }')"
        if [[ -n "$vars" ]]; then
          AUTH_CREDENTIALS_REF="$env_file variable names: $vars"
          break
        fi
      fi
    done
  fi

  if command -v rg >/dev/null 2>&1 && rg -i '(globalSetup|storageState)' "${auth_paths[@]}" >/dev/null 2>&1; then
    AUTH_SESSION_REF='Existing globalSetup/storageState signal detected.'
  elif ! command -v rg >/dev/null 2>&1 && grep -RsiE '(globalSetup|storageState)' "${auth_paths[@]}" >/dev/null 2>&1; then
    AUTH_SESSION_REF='Existing globalSetup/storageState signal detected.'
  else
    AUTH_SESSION_REF='No reusable auth session detected; create globalSetup/storageState before scaling E2E coverage.'
  fi
}

add_skill() {
  local name="$1"
  local description="$2"
  local command="$3"
  local extra="${4:-}"
  SKILL_NAMES+=("$name")
  SKILL_DESCRIPTIONS+=("$description")
  SKILL_COMMANDS+=("$command")
  SKILL_EXTRA+=("$extra")
}

plan_skills() {
  local cmd

  if cmd="$(choose_unit_command 2>/dev/null)"; then
    add_skill "aai-test-unit" "Run project unit tests with the detected project command." "$cmd"
  else
    SKIPPED+=("aai-test-unit: no unit test command detected")
  fi

  if cmd="$(choose_e2e_command 2>/dev/null)"; then
    local extra=""
    if [[ "$AUTH_DETECTED" -eq 1 ]]; then
      extra=$'## Prerequisites\n'
      if [[ -n "$AUTH_CREDENTIALS_REF" ]]; then
        extra+="- Authentication detected. Test credential reference: $AUTH_CREDENTIALS_REF"$'\n'
      else
        extra+="- Authentication detected. Add non-secret test credential references to docs/knowledge/FACTS.md; keep actual values in ignored env files or a secret manager."$'\n'
      fi
      extra+="- $AUTH_SESSION_REF"$'\n'
    fi
    add_skill "aai-test-e2e" "Run project E2E tests with the detected project command." "$cmd" "$extra"
  else
    SKIPPED+=("aai-test-e2e: no E2E command detected")
  fi

  if cmd="$(choose_build_command 2>/dev/null)"; then
    add_skill "aai-build" "Build or type-check the project with the detected project command." "$cmd"
  else
    SKIPPED+=("aai-build: no build command detected")
  fi

  if cmd="$(choose_lint_command 2>/dev/null)"; then
    add_skill "aai-lint" "Run project lint or static checks with the detected project command." "$cmd"
  else
    SKIPPED+=("aai-lint: no lint command detected")
  fi

  if cmd="$(choose_monty_command 2>/dev/null)"; then
    local extra=$'## Monty Scratchpad Workflow\n'
    extra+='- Use Monty only before implementation for isolated Python reasoning: pure functions, small transformations, parser checks, type-hint checks, or agent-generated code that calls explicit host functions.'$'\n'
    extra+='- Do not use Monty for project imports, third-party libraries, filesystem/network access, framework behavior, database access, or final validation evidence.'$'\n'
    extra+='- If the availability check fails, add `pydantic-monty` as a dev-only dependency with the project package manager or skip this helper; do not vendor it into production code unless requested.'$'\n'
    extra+='- Expose host functions narrowly. Never expose shell execution, unrestricted filesystem access, env variables, network access, tokens, or secrets.'$'\n'
    extra+='- After a Monty check passes, port the logic into the repo and run the generated `/aai-test-unit`, `/aai-lint`, and `/aai-build` skills when available.'$'\n'
    extra+=$'\n'
    extra+='Example scratchpad:'$'\n'
    extra+=$'\n'
    extra+='```bash'$'\n'
    extra+='python - <<'\''PY'\'''$'\n'
    extra+='import pydantic_monty'$'\n'
    extra+=$'\n'
    extra+='code = "value.strip().lower()"'$'\n'
    extra+='stubs = "value: str = '\'''\''"'$'\n'
    extra+='m = pydantic_monty.Monty(code, inputs=["value"], type_check=True, type_check_stubs=stubs)'$'\n'
    extra+='print(m.run(inputs={"value": "  Example  "}))'$'\n'
    extra+='PY'$'\n'
    extra+='```'$'\n'
    add_skill "aai-python-monty" "Use pydantic-monty as a safe scratchpad for small isolated Python logic before normal project validation." "$cmd" "$extra"
  else
    SKIPPED+=("aai-python-monty: Python project not detected")
  fi

  if cmd="$(choose_deploy_command 2>/dev/null)"; then
    add_skill "aai-deploy" "Deploy or publish the project with the detected project command." "$cmd"
  fi

  return 0
}

is_managed_file() {
  local path="$1"
  [[ ! -f "$path" ]] && return 0
  grep -q "$SKILL_MARKER\\|$FILE_MARKER\\|Generated by: $GENERATOR\\|generated by aai-bootstrap\\|AAI Dynamic Skills" "$path"
}

preflight_path() {
  local path="$1"
  if [[ -f "$path" ]] && [[ "$FORCE" -ne 1 ]] && ! is_managed_file "$path"; then
    CONFLICTS+=("$path exists and is not marked as AAI-generated; rerun with --force to replace it")
  fi
}

preflight_writes() {
  local i
  for i in "${!SKILL_NAMES[@]}"; do
    preflight_path ".claude/skills/${SKILL_NAMES[$i]}/SKILL.md"
  done
  preflight_path ".claude/skills/AAI_DYNAMIC_SKILLS.md"
  preflight_path ".codex/skills.local/README.md"
  preflight_path ".gemini/skills.local/README.md"
}

write_file() {
  local path="$1"
  local content="$2"

  if [[ -f "$path" ]]; then
    local existing
    existing="$(cat "$path")"
    if [[ "$existing" == "$content" ]]; then
      UNCHANGED+=("$path")
      return 0
    fi
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    WRITTEN+=("[dry-run] $path")
    return 0
  fi

  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
  WRITTEN+=("$path")
}

ensure_gitignore() {
  local path=".gitignore"
  local pattern
  [[ -f "$path" ]] || {
    if [[ "$DRY_RUN" -eq 1 ]]; then
      WRITTEN+=("[dry-run] $path")
      return 0
    fi
    : > "$path"
  }

  for pattern in ".claude/skills/.cache" ".codex/skills.local/.cache" ".gemini/skills.local/.cache"; do
    if ! grep -qF "$pattern" "$path" 2>/dev/null; then
      if [[ "$DRY_RUN" -eq 1 ]]; then
        WRITTEN+=("[dry-run] $path add $pattern")
      else
        {
          echo
          echo "$pattern"
        } >> "$path"
        WRITTEN+=("$path add $pattern")
      fi
    fi
  done
}

render_skill() {
  local name="$1"
  local description="$2"
  local command="$3"
  local extra="$4"

  cat <<EOF
---
name: $name
description: $description
---

# $name

<!-- $SKILL_MARKER generated-by=$GENERATOR -->

$description

Run from the repository root:

\`\`\`bash
$command
\`\`\`

$extra
## Notes
- Generated from repository evidence by $GENERATOR.
- If the command becomes stale, rerun $GENERATOR.
- Do not store secrets in this skill file.

<!-- AAI-DYNAMIC-SKILL:END -->
EOF
}

list_lines() {
  local empty="$1"
  shift
  local items=()
  local item
  for item in "$@"; do
    [[ -n "$item" ]] && items+=("$item")
  done
  if [[ "${#items[@]}" -eq 0 ]]; then
    printf -- '- %s\n' "$empty"
    return 0
  fi
  for item in "${items[@]}"; do
    printf -- '- %s\n' "$item"
  done
}

render_marker() {
  local generated_lines=""
  local i
  for i in "${!SKILL_NAMES[@]}"; do
    generated_lines+="- ${SKILL_NAMES[$i]}: \`${SKILL_COMMANDS[$i]}\`"$'\n'
  done
  [[ -n "$generated_lines" ]] || generated_lines="- None"$'\n'

  local skipped_lines=""
  if [[ "${#SKIPPED[@]}" -eq 0 ]]; then
    skipped_lines="- None"$'\n'
  else
    for i in "${!SKIPPED[@]}"; do
      skipped_lines+="- ${SKIPPED[$i]}"$'\n'
    done
  fi

  cat <<EOF
# AAI Dynamic Skills

<!-- $FILE_MARKER generated-by=$GENERATOR -->

- Generated at (UTC): $NOW_UTC
- Target root: $ROOT
- Generated by: $GENERATOR
- Ownership: project-owned dynamic skills

## Detected Stack

### Languages
$(list_lines "Not detected" "${DETECTED_LANGUAGES[@]:-}")

### Package/Dependency Managers
$(list_lines "Not detected" "${DETECTED_PACKAGE_MANAGERS[@]:-}")

### Test Tooling
$(list_lines "Not detected" "${DETECTED_TEST_TOOLS[@]:-}")

### Build Tooling
$(list_lines "Not detected" "${DETECTED_BUILD_TOOLS[@]:-}")

### Lint Tooling
$(list_lines "Not detected" "${DETECTED_LINT_TOOLS[@]:-}")

### CI/CD Signals
$(list_lines "Not detected" "${DETECTED_CI[@]:-}" "${DETECTED_DEPLOY[@]:-}")

## Generated Skills
$generated_lines
## Skipped Skills
$skipped_lines
These files are generated by aai-bootstrap and preserved by aai-sync as target-owned dynamic skills.

<!-- AAI-DYNAMIC-FILE:END -->
EOF
}

render_index() {
  local agent="$1"
  local skill_lines=""
  local i
  for i in "${!SKILL_NAMES[@]}"; do
    skill_lines+="- ${SKILL_NAMES[$i]}: .claude/skills/${SKILL_NAMES[$i]}/SKILL.md - \`${SKILL_COMMANDS[$i]}\`"$'\n'
  done
  [[ -n "$skill_lines" ]] || skill_lines="- None generated"$'\n'

  cat <<EOF
# AAI Dynamic Skills ($agent)

<!-- $FILE_MARKER generated-by=$GENERATOR -->

Generated at (UTC): $NOW_UTC

Project-owned dynamic skills live in .claude/skills/ and are discovered here for $agent.

## Skills
$skill_lines
## Source
- Marker: .claude/skills/AAI_DYNAMIC_SKILLS.md
- Generator: $GENERATOR

<!-- AAI-DYNAMIC-FILE:END -->
EOF
}

write_outputs() {
  local i
  for i in "${!SKILL_NAMES[@]}"; do
    local content
    content="$(render_skill "${SKILL_NAMES[$i]}" "${SKILL_DESCRIPTIONS[$i]}" "${SKILL_COMMANDS[$i]}" "${SKILL_EXTRA[$i]}")"
    write_file ".claude/skills/${SKILL_NAMES[$i]}/SKILL.md" "$content"
  done

  write_file ".claude/skills/AAI_DYNAMIC_SKILLS.md" "$(render_marker)"
  write_file ".codex/skills.local/README.md" "$(render_index Codex)"
  write_file ".gemini/skills.local/README.md" "$(render_index Gemini)"
  ensure_gitignore
}

print_summary() {
  echo
  echo "AAI bootstrap summary"
  echo "Target: $ROOT"
  [[ "$DRY_RUN" -eq 1 ]] && echo "Mode: dry-run"
  [[ "$FORCE" -eq 1 ]] && echo "Force: true"
  echo
  echo "Detected architecture:"
  list_lines "Not detected" "${DETECTED_LANGUAGES[@]:-}"
  list_lines "No package manager detected" "${DETECTED_PACKAGE_MANAGERS[@]:-}"
  list_lines "No test tooling detected" "${DETECTED_TEST_TOOLS[@]:-}"
  list_lines "No build tooling detected" "${DETECTED_BUILD_TOOLS[@]:-}"
  list_lines "No lint tooling detected" "${DETECTED_LINT_TOOLS[@]:-}"
  if [[ "$AUTH_DETECTED" -eq 1 ]]; then
    echo
    echo "Auth notes:"
    if [[ -n "$AUTH_CREDENTIALS_REF" ]]; then
      echo "- Authentication detected; credential reference: $AUTH_CREDENTIALS_REF"
    else
      echo "- Authentication detected; no non-secret test credential reference found"
    fi
    [[ -n "$AUTH_SESSION_REF" ]] && echo "- $AUTH_SESSION_REF"
  fi
  echo
  echo "Ready-to-use commands:"
  if [[ "${#SKILL_NAMES[@]}" -eq 0 ]]; then
    echo "- None generated"
  else
    local i
    for i in "${!SKILL_NAMES[@]}"; do
      echo "- /${SKILL_NAMES[$i]} -> ${SKILL_COMMANDS[$i]}"
    done
  fi
  echo
  echo "Generated/updated files:"
  list_lines "No file changes" "${WRITTEN[@]:-}"
  if [[ "${#UNCHANGED[@]}" -gt 0 ]]; then
    echo
    echo "Unchanged files:"
    list_lines "None" "${UNCHANGED[@]}"
  fi
  if [[ "${#SKIPPED[@]}" -gt 0 ]]; then
    echo
    echo "Skipped:"
    list_lines "None" "${SKIPPED[@]}"
  fi
}

detect_architecture
detect_auth
plan_skills
preflight_writes

if [[ "${#CONFLICTS[@]}" -gt 0 ]]; then
  echo "ERROR: bootstrap would overwrite unmarked files." >&2
  list_lines "None" "${CONFLICTS[@]}" >&2
  echo "Rerun with --force only if replacing these files is intentional." >&2
  exit 1
fi

write_outputs
print_summary
