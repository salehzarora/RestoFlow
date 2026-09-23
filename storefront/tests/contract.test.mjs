// The storefront must satisfy the MERGED deployment-filter contract. These
// assertions duplicate the engine's rules deliberately: a local failure here is
// cheaper than a hosted guard failure that BUILDs on every run.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => JSON.parse(readFileSync(path.join(ROOT, rel), 'utf8'));

const SCRIPT_KEYS = ['build', 'dev', 'start', 'lint', 'typecheck', 'test'];
const PUBLIC_TYPES = ['.svg', '.ico', '.txt', '.json', '.webmanifest', '.png', '.webp'];

test('vercel.json uses only allowed keys with the exact required values', () => {
  const v = read('vercel.json');
  const allowed = ['$schema', 'framework', 'installCommand', 'buildCommand',
    'ignoreCommand', 'trailingSlash', 'cleanUrls', 'headers', 'redirects', 'rewrites'];
  for (const key of Object.keys(v)) assert.ok(allowed.includes(key), `unexpected vercel.json key: ${key}`);
  assert.equal(v.framework, 'nextjs');
  assert.equal(v.installCommand, 'npm ci');
  assert.equal(v.buildCommand, 'npm run build');
  // HOST-FIX-001: no outputDirectory. The Next.js preset locates .next itself and
  // serves the out/ export; an explicit value overrides that lookup for the
  // deployment ('out' failed hosted with NEXT_NO_ROUTES_MANIFEST). The export
  // still lands in out/ - next.config.mjs, not this file, decides that.
  assert.equal(Object.hasOwn(v, 'outputDirectory'), false, 'vercel.json must not declare outputDirectory');
  assert.equal(v.ignoreCommand, 'if node ../tools/vercel/ignore-build.mjs storefront; then exit 0; else exit 1; fi');
  assert.equal(v.functions, undefined, 'a static export has no functions');
  for (const key of ['rewrites', 'redirects']) {
    if (v[key] != null) assert.equal(v[key].length, 0, `${key} must be absent or empty`);
  }
  assert.equal(v.cleanUrls, true, 'cleanUrls is what makes /ar resolve to ar.html');
  assert.equal(v.trailingSlash, false);
});

test('package.json fits the manifest contract', () => {
  const p = read('package.json');
  const allowed = ['name', 'version', 'private', 'description', 'engines', 'scripts', 'dependencies', 'devDependencies'];
  for (const key of Object.keys(p)) assert.ok(allowed.includes(key), `unexpected package.json key: ${key}`);
  assert.equal(p.private, true);
  assert.equal(p.scripts.build, 'next build');
  for (const key of Object.keys(p.scripts)) {
    assert.ok(SCRIPT_KEYS.includes(key), `script key outside the allowlist: ${key}`);
    assert.ok(!/^(?:pre|post)/.test(key) && key !== 'prepare', `npm lifecycle hook: ${key}`);
  }
  for (const name of Object.keys(p.dependencies)) {
    assert.ok(['next', 'react', 'react-dom'].includes(name), `runtime dependency outside the allowlist: ${name}`);
  }
  for (const group of [p.dependencies, p.devDependencies]) {
    for (const [name, value] of Object.entries(group ?? {})) {
      assert.match(value, /^\d+\.\d+\.\d+$/, `${name} must be an exact version, got ${value}`);
    }
  }
  assert.ok(p.engines && Object.keys(p.engines).length === 1 && typeof p.engines.node === 'string');
});

test('tsconfig include stays inside storefront/ and avoids the support roots', () => {
  const t = read('tsconfig.json');
  for (const key of Object.keys(t)) {
    assert.ok(['$schema', 'compilerOptions', 'include', 'exclude'].includes(key), `unexpected tsconfig key: ${key}`);
  }
  for (const key of ['types', 'typeRoots', 'rootDirs']) {
    assert.equal(t.compilerOptions[key], undefined, `${key} pulls in ambient declarations`);
  }
  assert.deepEqual(t.compilerOptions.paths, { '@/*': ['./src/*'] });
  assert.equal(t.compilerOptions.baseUrl, '.');
  assert.ok(Array.isArray(t.include) && t.include.length > 0, 'include is required');
  // Both .next globs must be present or next build rewrites the file.
  assert.ok(t.include.includes('.next/types/**/*.ts'));
  assert.ok(t.include.includes('.next/dev/types/**/*.ts'));
  const LOCAL = ['tests', 'docs', 'review', 'scripts'];
  for (const entry of t.include) {
    assert.ok(!entry.startsWith('..'), `include escapes storefront/: ${entry}`);
    const head = entry.split('/')[0];
    assert.ok(!LOCAL.includes(head), `include overlaps a support root: ${entry}`);
    assert.ok(head !== '.' && head !== '**', `include is too broad: ${entry}`);
  }
});

test('application source imports nothing outside the allowlist', () => {
  const ALLOWED = ['react', 'react-dom', 'next'];
  const walk = (dir) => existsSync(dir)
    ? readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
        e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)])
    : [];
  const files = ['app', 'src'].flatMap((d) => walk(path.join(ROOT, d)))
    .filter((f) => /\.(?:ts|tsx|mts|cts|js|jsx|mjs|cjs)$/.test(f));
  assert.ok(files.length > 0, 'expected application source files');
  for (const file of files) {
    const source = readFileSync(file, 'utf8');
    const where = path.relative(ROOT, file);
    assert.ok(!/\b(?:import|require)\s*\(/.test(source), `${where}: dynamic import()/require()`);
    assert.ok(!/\bprocess\s*(?:\?\.|\.|\[\s*["'])\s*(?:getBuiltinModule|mainModule|binding|_linkedBinding)\b/.test(source),
      `${where}: direct Node built-in handle`);
    for (const m of source.matchAll(/(?:\bfrom\s*|\bimport\s*)["']([^"']+)["']/g)) {
      const uri = m[1];
      if (uri.startsWith('.') || uri.startsWith('@/')) continue;
      assert.ok(!uri.startsWith('node:'), `${where}: Node built-in import ${uri}`);
      assert.ok(ALLOWED.includes(uri) || uri.startsWith('next/'), `${where}: bare import ${uri}`);
    }
  }
});

test('public/ fits the engine type allowlist and size cap', () => {
  const dir = path.join(ROOT, 'public');
  for (const name of readdirSync(dir)) {
    assert.ok(PUBLIC_TYPES.includes(path.extname(name).toLowerCase()), `public/${name}: type not allowed`);
    assert.ok(statSync(path.join(dir, name)).size <= 256 * 1024, `public/${name}: over 256 KB`);
  }
});

test('no forbidden request-time entrypoint exists', () => {
  for (const forbidden of ['app/layout.tsx', 'app/api', 'api', 'middleware.ts', 'proxy.ts',
    'instrumentation.ts', '.vercelignore', '.npmrc']) {
    assert.equal(existsSync(path.join(ROOT, forbidden)), false, `forbidden: ${forbidden}`);
  }
});
