// aai-bootstrap-fixtures.mjs - the fixture data of the bootstrap-on-node ride (D-CORPUS cases K01 to K38 and
// the golden-render fixtures). Pure data and small builders: no process is started here.
//
// A corpus case is { id, name, repo, target, files, steps }: files is the layout (a key ending in / is a
// directory, any other key a file), name the directory name of the target, repo whether it is a git
// repository, target whether the target is passed as an argument (false: no argument, cwd is the target),
// steps the runs in order ({ args, before }); before(root) edits the target ahead of that step.

import { appendFileSync, existsSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const pkg = (o) => `${JSON.stringify(o, null, 2)}\n`;

// The fixture of tests/skills/test-aai-bootstrap.sh (K01).
export const K01_FILES = {
  'package.json': pkg({
    name: 'bootstrap-fixture',
    version: '1.0.0',
    scripts: { test: 'jest', 'test:e2e': 'playwright test', build: 'vite build', lint: 'eslint .' },
    devDependencies: { '@playwright/test': '^1.40.0', eslint: '^8.0.0', jest: '^29.0.0', vite: '^5.0.0' },
  }),
  'jest.config.js': 'module.exports = {\n  testEnvironment: "node"\n};\n',
  'playwright.config.js': 'module.exports = {\n  testDir: "./e2e",\n  use: { baseURL: "http://localhost:3000" }\n};\n',
  'vite.config.js': 'export default {};\n',
  'eslint.config.js': 'export default [];\n',
  'pyproject.toml': '[project]\nname = "bootstrap-fixture"\nversion = "1.0.0"\n\n[project.optional-dependencies]\ndev = [\n  "pydantic-monty",\n  "ruff"\n]\n\n[tool.ruff]\nline-length = 100\n',
  'app/login.ts': 'export function requireAuth() {\n  return true;\n}\n',
  '.env.e2e': 'E2E_EMAIL=user@example.test\nE2E_PASSWORD=not-real\n',
  'e2e/': '',
  'docs/knowledge/': '',
};

const c = (id, files, extra = {}) => ({ id, name: 'proj', repo: true, target: true, files, steps: [{ args: [] }], ...extra });
const withArgs = (args) => [{ args }];
const TWO = [{ args: [] }, { args: [] }];

// Generated files of a fresh run, edited between two steps by K26 and K27.
const GENERATED = ['.claude/skills/aai-test-unit/SKILL.md', '.claude/skills/AAI_DYNAMIC_SKILLS.md', '.codex/skills.local/README.md', '.gemini/skills.local/README.md'];

// Corpus cases of slice a and b (K01 to K27 and K38). Slice c adds K28 to K37.
export const K_CASES = [
  c('K01', K01_FILES),
  c('K02', K01_FILES, { steps: withArgs(['--dry-run']) }),
  c('K03', {}, { repo: false, target: false }),
  c('K04', {}, { steps: TWO }),
  c('K05', {
    'package.json': pkg({ name: 'k05', workspaces: ['packages/*'], devDependencies: { jest: '^29' } }), 'yarn.lock': '', 'webpack.config.js': 'module.exports = {};\n',
    '.eslintrc.json': '{}\n', 'netlify.toml': '[build]\n', 'tests/': '',
  }),
  c('K06', {
    'package.json': pkg({ name: 'k06', scripts: { 'test:unit': 'vitest run', deploy: 'wrangler deploy' }, devDependencies: { vitest: '^1', typescript: '^5' } }),
    'pnpm-lock.yaml': '', 'tsconfig.json': '{}\n', 'biome.json': '{}\n', 'vercel.json': '{}\n',
  }),
  c('K07', {
    'package.json': pkg({ name: 'k07', scripts: { 'cy:run': 'cypress run' }, devDependencies: { '@biomejs/biome': '^1', cypress: '^13' } }),
    'bun.lockb': '', 'cypress.config.ts': 'export default {};\n', 'app/session.ts': 'export const session = 1;\n', 'cypress/support.ts': 'const storageState = {};\n',
  }),
  c('K08', { 'package.json': pkg({ name: 'k08', scripts: { e2e: 'x', check: 'x', compile: 'x' } }), 'bun.lock': '' }),
  c('K09', { 'poetry.lock': '', 'pyproject.toml': '[tool.black]\ndev = ["pytest"]\n', 'requirements.txt': 'flake8\n' }),
  c('K10', { 'uv.lock': '', 'setup.cfg': '[tool:pytest]\n', 'ruff.toml': 'line-length = 100\n', 'tox.ini': '[tox]\n' }),
  c('K11', { 'setup.py': 'from setuptools import setup\n', 'requirements.txt': 'ruff\n' }),
  c('K12', {
    'go.mod': 'module k12\n', Makefile: 'test:\n\tgo test ./...\nbuild:\n\tgo build ./...\nlint:\n\tgo vet ./...\n', justfile: 'deploy env:\n  echo deploy\n',
    '.github/workflows/ci.yml': 'name: ci\n',
  }),
  c('K13', { 'Cargo.toml': '[package]\nname = "k13"\n', Justfile: 'test-unit:\n  cargo test\nrelease:\n  cargo build --release\n' }),
  c('K14', { 'pom.xml': '<project/>\n', Dockerfile: 'FROM scratch\n', 'docker-compose.yml': 'services: {}\n', 'wrangler.toml': 'name = "k14"\n' }, { name: 'My Proj--X' }),
  c('K15', { Dockerfile: 'FROM scratch\n', 'compose.yml': 'services: {}\n' }, { name: 'My Proj--X' }),
  c('K16', { gradlew: '#!/bin/sh\n', 'build.gradle.kts': '', 'tests/': '' }),
  c('K17', { 'build.gradle': '', 'test/': '' }),
  c('K18', {
    'docs/knowledge/FACTS.md': '# Facts\n\n## Test Credentials\n- see the vault\n', 'playwright.config.ts': 'export default { globalSetup: "./setup.ts" };\n',
    'package.json': pkg({ name: 'k18', devDependencies: { '@playwright/test': '^1' } }), 'e2e/': '',
  }),
  // K19 as the spec words it. The reference ends it with exit 1 and no output: its credential search pipes grep
  // into cut under pipefail, so an env file without a matching name kills the run (set -e). The module skips that
  // file as D-AUTH says, so the pair differs by design; K19b is the same fixture without the unmatched file.
  c('K19', {
    '.env.test': 'FOO=1\n', '.env.testing': 'TEST_USER=a\nAUTH_TOKEN=b\nOTHER=c\n', 'playwright.config.ts': 'export default {};\n', 'app/login.ts': 'export const login = 1;\n',
  }, { knownDivergence: { sh: { code: 1, stdout: '', stderr: '' }, node: { code: 0 } } }),
  c('K19b', {
    '.env.testing': 'TEST_USER=a\nAUTH_TOKEN=b\nOTHER=c\n', 'playwright.config.ts': 'export default {};\n', 'app/login.ts': 'export const login = 1;\n',
  }),
  c('K20', { 'package.json': '{not json', Makefile: 'unit:\n\techo unit\n' }),
  c('K21', { ...K01_FILES, '.claude/skills/aai-test-unit/SKILL.md': 'my own unit skill\n', '.codex/skills.local/README.md': 'my own codex index\n' }),
  c('K22', { ...K01_FILES, '.claude/skills/aai-test-unit/SKILL.md': 'my own unit skill\n', '.codex/skills.local/README.md': 'my own codex index\n' }, { steps: withArgs(['--force']) }),
  c('K23', { ...K01_FILES, '.claude/skills/aai-build/SKILL.md': 'Generated by: Xaai/scripts/aai-bootstrapYsh\n', '.gemini/skills.local/README.md': 'AAI Dynamic Skills\n' }),
  c('K24', { '.gitignore': '.claude/skills/.cache\r\ndocs/ai/STATE.yaml\r\n# AAI runtime sidecars (seeded from sync)\r\n' }),
  c('K25', { '.gitignore': 'node_modules/' }),
  c('K26', K01_FILES, {
    steps: [{ args: [] }, { args: ['--dry-run'], before: (root) => writeFileSync(path.join(root, '.gitignore'), 'node_modules/\n') }],
  }),
  c('K27', K01_FILES, {
    steps: [{ args: [] }, { args: [], before: (root) => { for (const f of GENERATED) if (existsSync(path.join(root, f))) appendFileSync(path.join(root, f), '\n\n'); } }],
  }),
  c('K38', { 'vitest.config.ts': 'export default {};\n', 'package.json': pkg({ name: 'k38' }) }),
];

// The golden-render fixtures: the reference's bytes for these are committed in aai-bootstrap-golden.json.
export const GOLDEN_FULL = {
  ...K01_FILES,
  'package.json': pkg({
    name: 'golden-full',
    scripts: { test: 'vitest run', build: 'vite build', lint: 'eslint .', deploy: 'wrangler deploy' },
    devDependencies: { '@playwright/test': '^1.40.0', eslint: '^8.0.0', vitest: '^1.0.0', vite: '^5.0.0' },
  }),
  'vitest.config.ts': 'export default {};\n',
  'wrangler.toml': 'name = "golden"\n',
  'docs/knowledge/FACTS.md': '# Facts\n\n## Test Credentials\n- see the vault\n',
};
export const GOLDEN_EMPTY = {};
