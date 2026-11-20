#!/usr/bin/env node
// aai-bootstrap.mjs - project bootstrap as one Node module behind thin launchers
// (docs/specs/SPEC-DRAFT-bootstrap-on-node.md; RFC-0017 phase 5).
//
// Usage: node .aai/scripts/aai-bootstrap.mjs [target-root] [--dry-run] [--force] [--with-claude-hooks]
//
// The module holds the bootstrap policy: arguments, root resolution, detection, command choice, the
// skill plan, rendering, writes and the exit code. Importing it has no side effect; the main guard
// runs it only as the entry point. It never reads standard input.

import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, realpathSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const GENERATOR = '.aai/scripts/aai-bootstrap.sh';
const SKILL_MARKER = 'AAI-DYNAMIC-SKILL:START';
const FILE_MARKER = 'AAI-DYNAMIC-FILE:START';
const RUNTIME_MARKER_PREFIX = '# AAI runtime sidecars';
const RUNTIME_MARKER = '# AAI runtime sidecars (seeded by aai-bootstrap; per-dev, never commit)';
const CACHE_PATTERNS = ['.claude/skills/.cache', '.codex/skills.local/.cache', '.gemini/skills.local/.cache'];
const LOCKFILES = [['pnpm-lock.yaml', 'pnpm'], ['yarn.lock', 'yarn'], ['bun.lock', 'bun'], ['bun.lockb', 'bun']];
const AUTH_SKIP_DIRS = ['node_modules', '.git', 'dist', 'build'];
const HOOKS_UNCHANGED = '0 hook(s) added, 0 updated';
const PLATFORM_MISMATCH = 6;
const EXIT_HOOKS_REFUSED = 3;
const EXIT_CONFLICT = 1;
const EXIT_USAGE = 2;

const samePlace = (a, b) => a.dev === b.dev && a.ino === b.ino;
const stripTrailingNewlines = (s) => s.replace(/\n+$/, '');
const sameContent = (a, b) => stripTrailingNewlines(a) === stripTrailingNewlines(b);
const runChild = (script, args, cwd) => spawnSync(process.execPath, [script, ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

// The help text: the reference's comment block (DR-1: without its two leading source lines) with the
// PowerShell usage line right after the POSIX usage line.
const HELP_LINES = [
  'Generate project-local AAI dynamic skills from evidence in the target repo.',
  '',
  'Usage:',
  '  ./.aai/scripts/aai-bootstrap.sh [target-root] [--dry-run] [--force] [--with-claude-hooks]',
  '  powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 [target-root] [--dry-run] [--force] [--with-claude-hooks]',
  '',
  'Safety model:',
  '- Creates or updates only known dynamic skill files and local discovery indexes.',
  '- Refuses to overwrite a skill file that does not contain the AAI dynamic marker.',
  '- --dry-run prints planned writes without changing files.',
  '- --force is the explicit confirmation for replacing unmarked dynamic skill paths.',
  '- --with-claude-hooks (OPT-IN, RFC-0010): merge the AAI hook-enforced gates',
  '  overlay from .aai/templates/hooks/settings-hooks.json into .claude/settings.json',
  '  (additive merge; existing settings preserved; never overwrites silently).',
];
export const HELP_TEXT = `${HELP_LINES.join('\n')}\n`;

// The command that runs a package script; npm runs its test script without `run`, and an unknown
// manager (no package.json) reads as npm.
function scriptCommand(pm, script) {
  if (pm === 'npm' && script === 'test') return 'npm test';
  if (pm === 'pnpm' || pm === 'yarn' || pm === 'bun') return `${pm} run ${script}`;
  return `npm run ${script}`;
}

// The command that runs a locally installed tool through the package manager.
function execCommand(pm, tool, rest = '') {
  const lead = { pnpm: 'pnpm exec', yarn: 'yarn exec', bun: 'bunx' }[pm] ?? 'npx';
  return rest ? `${lead} ${tool} ${rest}` : `${lead} ${tool}`;
}

// wrapTestCommand(cmd): the two-line Windows and POSIX form that routes a test command through the
// leak-safe runner pair.
export const wrapTestCommand = (cmd) => `Windows: powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 ${cmd}\nPOSIX: bash .aai/scripts/aai-run-tests.sh ${cmd}`;

const VITEST_GUIDANCE = [
  '## Leak-safe Vitest configuration (bounds fork memory)',
  '- This project uses Vitest. A default `vitest run` sizes its fork pool to the CPU',
  '  count (~150 MB per worker), and a suite that leaves an open handle can leave the',
  '  whole tree resident. Bound a single run to ~300-400 MB by setting, in your',
  '  Vitest config:',
  '  - `pool: \'forks\'`',
  '  - `poolOptions.forks.maxForks: 2`, `poolOptions.forks.minForks: 1`',
  '  - `teardownTimeout: 10_000`',
  '- Bootstrap does NOT edit an existing Vitest config; apply this yourself.',
  '- The generated command already runs through the wrapper pair (Windows:',
  '  `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1`; POSIX:',
  '  `bash .aai/scripts/aai-run-tests.sh`), which puts the run in a killable',
  '  process group with a timeout so no fork worker can outlive the step.',
].join('\n');
const MONTY_EXTRA = [
  '## Monty Scratchpad Workflow',
  '- Use Monty only before implementation for isolated Python reasoning: pure functions, small transformations, parser checks, type-hint checks, or agent-generated code that calls explicit host functions.',
  '- Do not use Monty for project imports, third-party libraries, filesystem/network access, framework behavior, database access, or final validation evidence.',
  '- If the availability check fails, add `pydantic-monty` as a dev-only dependency with the project package manager or skip this helper; do not vendor it into production code unless requested.',
  '- Expose host functions narrowly. Never expose shell execution, unrestricted filesystem access, env variables, network access, tokens, or secrets.',
  '- After a Monty check passes, port the logic into the repo and run the generated `/aai-test-unit`, `/aai-lint`, and `/aai-build` skills when available.',
  '',
  'Example scratchpad:',
  '',
  '```bash',
  'python - <<\'PY\'',
  'import pydantic_monty',
  '',
  'code = "value.strip().lower()"',
  'stubs = "value: str = \'\'"',
  'm = pydantic_monty.Monty(code, inputs=["value"], type_check=True, type_check_stubs=stubs)',
  'print(m.run(inputs={"value": "  Example  "}))',
  'PY',
  '```',
].join('\n') + '\n';

const notYet = (name) => () => {
  throw new Error(`aai-bootstrap: ${name} is not implemented yet`);
};

// parseArgs(argv): arguments left to right as the reference reads them. outcome is 'run', 'help'
// (-h or --help seen first) or 'usage' (a second positional, named in extra).
export function parseArgs(argv) {
  const out = { dryRun: false, force: false, withClaudeHooks: false, target: '', outcome: 'run', extra: '' };
  for (const arg of argv) {
    if (arg === '--dry-run') out.dryRun = true;
    else if (arg === '--force') out.force = true;
    else if (arg === '--with-claude-hooks') out.withClaudeHooks = true;
    else if (arg === '-h' || arg === '--help') {
      out.outcome = 'help';
      return out;
    } else if (out.target === '') out.target = arg;
    else {
      out.outcome = 'usage';
      out.extra = arg;
      return out;
    }
  }
  return out;
}

const statOrNull = (p) => {
  try {
    return statSync(p);
  } catch {
    return null;
  }
};

// resolveRoot(target, env, cwd): the base is PWD when it is absolute and names the working directory
// (the rule bash trusts PWD by), else the working directory; a target resolves lexically against it.
// CDPATH is not read.
export function resolveRoot(target = '', env = process.env, cwd = process.cwd()) {
  let base = cwd;
  const pwd = env.PWD;
  if (typeof pwd === 'string' && path.isAbsolute(pwd)) {
    const a = statOrNull(pwd);
    const b = statOrNull(cwd);
    if (a && b && samePlace(a, b)) base = pwd;
  }
  return target === '' ? base : path.resolve(base, target);
}

const hasOwn = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
const isFile = (p) => statOrNull(p)?.isFile() === true;
const isDir = (p) => statOrNull(p)?.isDirectory() === true;
const readLatin1 = (p) => {
  try {
    return readFileSync(p, 'latin1');
  } catch {
    return '';
  }
};

// project(root): the cached readers one detection pass shares. Names are matched case-sensitively,
// a glob pattern is a name prefix, and the package.json queries answer false for anything that is
// not a JSON object.
function project(root) {
  let names = [];
  try {
    names = readdirSync(root);
  } catch {
    names = [];
  }
  const at = (n) => path.join(root, n);
  const file = (n) => isFile(at(n));
  let parsed;
  const pkgObject = () => {
    if (parsed === undefined) {
      parsed = null;
      if (file('package.json')) {
        try {
          parsed = JSON.parse(readFileSync(at('package.json'), 'utf8'));
        } catch {
          parsed = null;
        }
      }
    }
    return parsed;
  };
  const query = (fn) => {
    try {
      return fn(pkgObject()) === true;
    } catch {
      return false;
    }
  };
  const pc = {
    root,
    at,
    file,
    dir: (n) => isDir(at(n)),
    glob: (prefix) => names.some((n) => n.startsWith(prefix)),
    hasScript: (s) => query((p) => Boolean(p.scripts && hasOwn(p.scripts, s))),
    hasDep: (d) => query((p) => ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies'].some((b) => Boolean(p[b] && hasOwn(p[b], d)))),
    hasKey: (k) => query((p) => hasOwn(p, k)),
    justfile: () => (file('justfile') ? 'justfile' : file('Justfile') ? 'Justfile' : null),
    makefile: () => (file('Makefile') ? 'Makefile' : file('makefile') ? 'makefile' : null),
    pm: '',
  };
  if (pc.file('package.json')) {
    pc.pm = (LOCKFILES.find(([lock]) => pc.file(lock)) ?? [null, 'npm'])[1];
  }
  pc.isPython = ['pyproject.toml', 'requirements.txt', 'poetry.lock', 'uv.lock', 'setup.cfg', 'setup.py'].some(pc.file);
  return pc;
}

// containsText(pc, files, needle): the substring search of grep -R over files that may be directories.
function containsText(pc, files, needle) {
  const seen = new Set();
  const visit = (p) => {
    const st = statOrNull(p);
    if (!st) return false;
    if (st.isDirectory()) {
      let real;
      let kids;
      try {
        real = realpathSync(p);
        kids = readdirSync(p);
      } catch {
        return false;
      }
      if (seen.has(real)) return false;
      seen.add(real);
      return kids.some((k) => visit(path.join(p, k)));
    }
    return st.isFile() && readLatin1(p).includes(needle);
  };
  return files.some((f) => visit(pc.at(f)));
}

const lineMatches = (pc, name, re) => name !== null && readLatin1(pc.at(name)).split('\n').some((l) => re.test(l));
const WS = '[ \\t\\n\\v\\f\\r]';

function taskRunner(pc, targets) {
  for (const t of targets) {
    const jf = pc.justfile();
    if (jf && lineMatches(pc, jf, new RegExp(`^${WS}*${t}(${WS}[^\\n]*)?:`))) return `just ${t}`;
    const mf = pc.makefile();
    if (mf && lineMatches(pc, mf, new RegExp(`^${WS}*${t}${WS}*:`))) return `make ${t}`;
  }
  return null;
}

const packageScript = (pc, names) => {
  const hit = names.find((s) => pc.hasScript(s));
  return hit === undefined ? null : scriptCommand(pc.pm, hit);
};

// dockerTag(root): the root's basename lowered (ASCII), a newline appended as the shell pipeline does,
// every character outside a-z0-9_.- replaced by a dash and runs of dashes folded to one.
export function dockerTag(root) {
  const base = path.basename(root) || '/';
  return `${base.replace(/[A-Z]/g, (c) => c.toLowerCase())}\n`.replace(/[^a-z0-9_.-]+/g, '-').replace(/-+/g, '-');
}

// detect(root): the detected lists (first-seen order, no duplicates) and the Vitest flag.
export function detect(root) {
  const pc = project(root);
  const d = { languages: [], packageManagers: [], testTools: [], buildTools: [], lintTools: [], ci: [], deploy: [], vitest: false };
  const add = (list, v) => {
    if (!d[list].includes(v)) d[list].push(v);
  };
  if (pc.file('package.json')) add('packageManagers', `${pc.pm} (package.json)`);
  if (pc.file('package.json')) {
    add('languages', 'JavaScript/TypeScript');
    if (pc.hasKey('workspaces')) add('buildTools', 'package.json workspaces');
  }
  if (pc.isPython) {
    add('languages', 'Python');
    if (pc.file('poetry.lock')) add('packageManagers', 'poetry (poetry.lock)');
    else if (pc.file('uv.lock')) add('packageManagers', 'uv (uv.lock)');
    else add('packageManagers', 'pip/python (python manifest)');
  }
  if (pc.file('go.mod')) {
    add('languages', 'Go');
    add('packageManagers', 'go modules (go.mod)');
  }
  if (pc.file('Cargo.toml')) {
    add('languages', 'Rust');
    add('packageManagers', 'cargo (Cargo.toml)');
  }
  if (pc.file('pom.xml')) {
    add('languages', 'Java');
    add('packageManagers', 'maven (pom.xml)');
  }
  if (pc.file('build.gradle') || pc.file('build.gradle.kts') || pc.file('gradlew')) {
    add('languages', 'Java/Kotlin');
    add('packageManagers', 'gradle');
  }
  if (pc.glob('playwright.config.')) add('testTools', 'Playwright');
  if (pc.glob('cypress.config.')) add('testTools', 'Cypress');
  if (pc.glob('jest.config.')) add('testTools', 'Jest');
  if (pc.glob('vitest.config.') || pc.hasDep('vitest')) {
    d.vitest = true;
    add('testTools', 'Vitest');
  }
  if (pc.file('pytest.ini') || pc.file('tox.ini')) add('testTools', 'pytest');
  if (pc.dir('tests') || pc.dir('test')) add('testTools', 'test directory');
  if (pc.glob('vite.config.')) add('buildTools', 'Vite');
  if (pc.glob('webpack.config.')) add('buildTools', 'Webpack');
  if (pc.file('tsconfig.json')) add('buildTools', 'TypeScript (tsconfig.json)');
  if (pc.file('Dockerfile')) add('buildTools', 'Dockerfile');
  if (pc.file('docker-compose.yml') || pc.file('compose.yml')) add('buildTools', 'Docker Compose');
  if (pc.makefile()) add('buildTools', 'Makefile');
  if (pc.justfile()) add('buildTools', 'justfile');
  if (pc.glob('.eslintrc')) add('lintTools', 'ESLint config');
  if (['eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs'].some(pc.file)) add('lintTools', 'ESLint config');
  if (pc.file('biome.json') || pc.file('biome.jsonc')) add('lintTools', 'Biome');
  if (pc.file('ruff.toml')) add('lintTools', 'Ruff');
  if (pc.file('pyproject.toml') && lineMatches(pc, 'pyproject.toml', /\[tool\.ruff\]|\[tool\.flake8\]|\[tool\.black\]/)) {
    add('lintTools', 'Python lint config (pyproject.toml)');
  }
  if (pc.dir('.github/workflows')) add('ci', '.github/workflows');
  if (pc.file('wrangler.toml')) add('deploy', 'Cloudflare Wrangler');
  if (pc.file('vercel.json')) add('deploy', 'Vercel');
  if (pc.file('netlify.toml')) add('deploy', 'Netlify');
  return d;
}

function unitCommand(pc) {
  const found = taskRunner(pc, ['test-unit', 'unit', 'test']) ?? packageScript(pc, ['test:unit', 'unit', 'test']);
  if (found) return found;
  if (pc.glob('vitest.config.') || pc.hasDep('vitest')) return execCommand(pc.pm, 'vitest', 'run');
  if (pc.glob('jest.config.') || pc.hasDep('jest')) return execCommand(pc.pm, 'jest');
  if (pc.file('pytest.ini') || containsText(pc, ['pyproject.toml', 'requirements.txt', 'setup.cfg', 'tox.ini'], 'pytest')) return 'pytest';
  if (pc.file('go.mod')) return 'go test ./...';
  if (pc.file('Cargo.toml')) return 'cargo test';
  if (pc.file('pom.xml')) return 'mvn test';
  if (pc.file('gradlew')) return './gradlew test';
  if (pc.file('build.gradle') || pc.file('build.gradle.kts')) return 'gradle test';
  return null;
}

function e2eCommand(pc) {
  if (!(pc.glob('playwright.config.') || pc.glob('cypress.config.') || pc.hasScript('test:e2e') || pc.hasScript('e2e'))) return null;
  const found = taskRunner(pc, ['test-e2e', 'e2e', 'test_e2e']) ?? packageScript(pc, ['test:e2e', 'e2e', 'playwright', 'cypress:run', 'cy:run']);
  if (found) return found;
  if (pc.glob('playwright.config.') || pc.hasDep('@playwright/test') || pc.hasDep('playwright')) return execCommand(pc.pm, 'playwright', 'test');
  if (pc.glob('cypress.config.') || pc.hasDep('cypress')) return execCommand(pc.pm, 'cypress', 'run');
  return null;
}

function buildCommand(pc) {
  const found = taskRunner(pc, ['build', 'compile']) ?? packageScript(pc, ['build', 'compile']);
  if (found) return found;
  if (pc.glob('vite.config.') || pc.hasDep('vite')) return execCommand(pc.pm, 'vite', 'build');
  if (pc.glob('webpack.config.') || pc.hasDep('webpack')) return execCommand(pc.pm, 'webpack');
  if (pc.file('tsconfig.json') && pc.hasDep('typescript')) return execCommand(pc.pm, 'tsc', '--noEmit');
  if (pc.file('go.mod')) return 'go build ./...';
  if (pc.file('Cargo.toml')) return 'cargo build';
  if (pc.file('pom.xml')) return 'mvn package';
  if (pc.file('gradlew')) return './gradlew build';
  if (pc.file('build.gradle') || pc.file('build.gradle.kts')) return 'gradle build';
  if (pc.file('Dockerfile')) return `docker build -t ${dockerTag(pc.root)} .`;
  return null;
}

function lintCommand(pc) {
  const found = taskRunner(pc, ['lint', 'check', 'lint-check']) ?? packageScript(pc, ['lint', 'check', 'typecheck']);
  if (found) return found;
  if (['eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs'].some(pc.file) || pc.glob('.eslintrc') || pc.hasDep('eslint')) return execCommand(pc.pm, 'eslint', '.');
  if (pc.file('biome.json') || pc.file('biome.jsonc') || pc.hasDep('@biomejs/biome')) return execCommand(pc.pm, 'biome', 'check .');
  if (pc.file('ruff.toml') || containsText(pc, ['pyproject.toml', 'requirements.txt'], 'ruff')) return 'ruff check .';
  if (containsText(pc, ['pyproject.toml', 'requirements.txt', 'setup.cfg', 'tox.ini'], 'flake8')) return 'flake8';
  if (pc.file('go.mod')) return 'go vet ./...';
  if (pc.file('Cargo.toml')) return 'cargo clippy --all-targets --all-features';
  return null;
}

function deployCommand(pc) {
  const found = taskRunner(pc, ['deploy', 'publish', 'release']) ?? packageScript(pc, ['deploy', 'publish', 'release']);
  if (found) return found;
  if (pc.file('wrangler.toml')) return 'wrangler deploy';
  if (pc.file('vercel.json')) return 'vercel deploy';
  if (pc.file('netlify.toml')) return 'netlify deploy';
  return null;
}

// chooseCommands(root): the command of each chain, or null when no step of the chain holds.
export function chooseCommands(root) {
  const pc = project(root);
  return {
    unit: unitCommand(pc),
    e2e: e2eCommand(pc),
    build: buildCommand(pc),
    lint: lintCommand(pc),
    monty: pc.isPython ? `python -c "import pydantic_monty; print('pydantic-monty available')"` : null,
    deploy: deployCommand(pc),
  };
}

const AUTH_RE = /(login|sign-in|auth|session|jwt|passport|next-auth|clerk|requireAuth|withAuth|storageState|globalSetup)/i;
const SESSION_RE = /(globalSetup|storageState)/i;
const SESSION_FOUND = 'Existing globalSetup/storageState signal detected.';
const SESSION_NONE = 'No reusable auth session detected; create globalSetup/storageState before scaling E2E coverage.';
const ENV_FILES = ['.env.e2e', '.env.test', '.env.testing'];
const ENV_NAME_LINE = /^(TEST|E2E|PLAYWRIGHT|CYPRESS|AUTH|LOGIN)[^\n]*(_USER|_EMAIL|_PASSWORD|_PASS|_TOKEN)=/;

// anyMatch(paths, re): one walk (DR-5): regular files read as latin1, directories followed through
// symlinks once each, the AUTH_SKIP_DIRS directories skipped at any depth, hidden files searched.
function anyMatch(paths, re) {
  const seen = new Set();
  const visit = (p) => {
    const st = statOrNull(p);
    if (!st) return false;
    if (st.isDirectory()) {
      let real;
      let kids;
      try {
        real = realpathSync(p);
        kids = readdirSync(p);
      } catch {
        return false;
      }
      if (seen.has(real)) return false;
      seen.add(real);
      return kids.some((k) => !(AUTH_SKIP_DIRS.includes(k) && isDir(path.join(p, k))) && visit(path.join(p, k)));
    }
    return st.isFile() && re.test(readLatin1(p));
  };
  return paths.some(visit);
}

function credentialsRef(pc) {
  const facts = 'docs/knowledge/FACTS.md';
  if (pc.file(facts) && lineMatches(pc, facts, /^## Test Credentials/)) return 'docs/knowledge/FACTS.md, section "Test Credentials"';
  for (const env of ENV_FILES) {
    if (!pc.file(env)) continue;
    const names = readLatin1(pc.at(env)).split('\n').filter((l) => ENV_NAME_LINE.test(l)).map((l) => l.split('=')[0]).filter((n) => n.trim() !== '');
    if (names.length > 0) return `${env} variable names: ${names.join(', ')}`;
  }
  return '';
}

// detectAuth(root, commands): only with an e2e command; searches the candidate paths for the auth words.
export function detectAuth(root, commands = chooseCommands(root)) {
  const none = { detected: false, credentialsRef: '', sessionRef: '' };
  if (!commands.e2e) return none;
  const pc = project(root);
  const fixed = ['app', 'src', 'pages', 'components', 'routes', 'tests', 'e2e', 'cypress', 'package.json'];
  const named = ['middleware.ts', 'middleware.js'];
  const rels = [
    ...fixed.filter((n) => statOrNull(pc.at(n))),
    ...named.filter((n) => statOrNull(pc.at(n))),
    ...readdirSync(root).filter((n) => (n.startsWith('playwright.config.') || n.startsWith('cypress.config.')) && statOrNull(pc.at(n))).sort(),
  ];
  const paths = rels.map(pc.at);
  if (paths.length === 0 || !anyMatch(paths, AUTH_RE)) return none;
  return { detected: true, credentialsRef: credentialsRef(pc), sessionRef: anyMatch(paths, SESSION_RE) ? SESSION_FOUND : SESSION_NONE };
}

function prerequisites(auth) {
  const cred = auth.credentialsRef
    ? `- Authentication detected. Test credential reference: ${auth.credentialsRef}\n`
    : '- Authentication detected. Add non-secret test credential references to docs/knowledge/FACTS.md; keep actual values in ignored env files or a secret manager.\n';
  return `## Prerequisites\n${cred}- ${auth.sessionRef}\n`;
}

// planSkills(root): the skills in order ({ name, description, command, extra }) and the skipped messages.
export function planSkills(root) {
  const det = detect(root);
  const cmds = chooseCommands(root);
  const auth = detectAuth(root, cmds);
  const skills = [];
  const skipped = [];
  const add = (name, description, command, extra = '') => skills.push({ name, description, command, extra });
  if (cmds.unit) {
    add('aai-test-unit', 'Run project unit tests with the detected project command (routed through the leak-safe wrapper).', wrapTestCommand(cmds.unit), det.vitest ? `${VITEST_GUIDANCE}\n` : '');
  } else skipped.push('aai-test-unit: no unit test command detected');
  if (cmds.e2e) {
    add('aai-test-e2e', 'Run project E2E tests with the detected project command (routed through the leak-safe wrapper).', wrapTestCommand(cmds.e2e), auth.detected ? prerequisites(auth) : '');
  } else skipped.push('aai-test-e2e: no E2E command detected');
  if (cmds.build) add('aai-build', 'Build or type-check the project with the detected project command.', cmds.build);
  else skipped.push('aai-build: no build command detected');
  if (cmds.lint) add('aai-lint', 'Run project lint or static checks with the detected project command.', cmds.lint);
  else skipped.push('aai-lint: no lint command detected');
  if (cmds.monty) add('aai-python-monty', 'Use pydantic-monty as a safe scratchpad for small isolated Python logic before normal project validation.', cmds.monty, MONTY_EXTRA);
  else skipped.push('aai-python-monty: Python project not detected');
  if (cmds.deploy) add('aai-deploy', 'Deploy or publish the project with the detected project command.', cmds.deploy);
  return { skills, skipped };
}

export const renderSkill = notYet('renderSkill');
export const renderMarker = notYet('renderMarker');
export const renderIndex = notYet('renderIndex');
export const renderSummary = notYet('renderSummary');
export const isManagedFile = notYet('isManagedFile');
export const preflight = notYet('preflight');
export const writeOutputs = notYet('writeOutputs');
export const ensureGitignore = notYet('ensureGitignore');
export const seedRuntimeGitignore = notYet('seedRuntimeGitignore');
export const installClaudeHooks = notYet('installClaudeHooks');
export const recordGitPlatform = notYet('recordGitPlatform');

// run(argv, io): returns the exit code. io holds out, err (string sinks), now, env, cwd and spawn.
export function run(argv, io = {}) {
  const out = io.out ?? ((s) => process.stdout.write(s));
  const err = io.err ?? ((s) => process.stderr.write(s));
  const env = io.env ?? process.env;
  const cwd = io.cwd ?? process.cwd();
  const args = parseArgs(argv);
  if (args.outcome === 'help') {
    out(HELP_TEXT);
    return 0;
  }
  if (args.outcome === 'usage') {
    err(`ERROR: unexpected argument: ${args.extra}\n`);
    err(HELP_TEXT);
    return EXIT_USAGE;
  }
  const root = resolveRoot(args.target, env, cwd);
  const st = statOrNull(root);
  if (!st || !st.isDirectory()) {
    err(`aai-bootstrap: target not found: ${args.target}\n`);
    return EXIT_CONFLICT;
  }
  notYet('the bootstrap pipeline')(args, root);
  return 0;
}

export function main(argv = process.argv.slice(2)) {
  process.exitCode = run(argv);
}

const isEntryPoint = () => {
  try {
    return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
};

if (isEntryPoint()) main();
