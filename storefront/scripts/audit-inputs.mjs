#!/usr/bin/env node
// Build-input containment audit for the storefront application source.
//
// The deployment filter inspects the static import graph. This audit covers the
// classes it deliberately does NOT inspect - string-built asset paths, CSS
// @import/url(), new URL(..., import.meta.url), font src, symlinks, parent
// traversal - so an external build input cannot enter unnoticed. It is a
// review aid for trusted source, not a sandbox.
import { readFileSync, readdirSync, statSync, existsSync, lstatSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Scanned application source: what `next build` actually compiles.
const SOURCE_DIRS = ['app', 'src', 'messages', 'public'];
const CODE = /\.(?:ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;
const ALLOWED_BARE = ['react', 'react-dom', 'next'];

function collect(dir) {
  const base = path.join(ROOT, dir);
  if (!existsSync(base)) return [];
  const found = [];
  (function walk(d) {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, entry.name);
      if (entry.isSymbolicLink()) { found.push({ path: full, symlink: true }); continue; }
      if (entry.isDirectory()) walk(full);
      else found.push({ path: full, symlink: false });
    }
  })(base);
  return found;
}

export function auditInputs(root = ROOT) {
  const problems = [];
  const files = SOURCE_DIRS.flatMap(collect);
  const rel = (p) => path.relative(root, p).split(path.sep).join('/');

  for (const f of files) {
    if (f.symlink) { problems.push(`symlink in source: ${rel(f.path)}`); continue; }
    const ext = path.extname(f.path).toLowerCase();
    const isCode = CODE.test(f.path);
    const isCss = ext === '.css';
    if (!isCode && !isCss) continue;
    const text = readFileSync(f.path, 'utf8');
    const where = rel(f.path);

    if (isCode) {
      // 1. static import/export specifiers
      for (const m of text.matchAll(/(?:\bfrom\s*|\bimport\s*)["']([^"']+)["']/g)) {
        const uri = m[1];
        if (uri.startsWith('.')) {
          const target = path.resolve(path.dirname(f.path), uri);
          if (!target.startsWith(ROOT + path.sep)) problems.push(`${where}: relative import escapes storefront/ -> ${uri}`);
        } else if (uri.startsWith('@/')) {
          const target = path.resolve(ROOT, 'src', uri.slice(2));
          if (!target.startsWith(path.join(ROOT, 'src') + path.sep)) problems.push(`${where}: alias escapes src/ -> ${uri}`);
        } else if (uri.startsWith('node:')) {
          problems.push(`${where}: Node built-in import is forbidden in application source -> ${uri}`);
        } else if (!ALLOWED_BARE.includes(uri) && !uri.startsWith('next/')) {
          problems.push(`${where}: bare import outside the allowlist -> ${uri}`);
        }
      }
      // 2. dynamic import()/require()
      if (/\b(?:import|require)\s*\(/.test(text)) problems.push(`${where}: dynamic import()/require() is forbidden`);
      // 3. direct Node builtin handles
      if (/\bprocess\s*(?:\?\.|\.|\[\s*["'])\s*(?:getBuiltinModule|mainModule|binding|_linkedBinding)\b/.test(text)) {
        problems.push(`${where}: direct Node built-in acquisition via process.*`);
      }
      // 4. new URL(..., import.meta.url) - the filter never inspects this
      for (const m of text.matchAll(/new\s+URL\s*\(\s*["']([^"']+)["']\s*,\s*import\.meta\.url/g)) {
        problems.push(`${where}: new URL(${m[1]}, import.meta.url) is an uninspected asset path`);
      }
      // 5. next/font/local src
      for (const m of text.matchAll(/src\s*:\s*["']([^"']+)["']/g)) {
        if (m[1].includes('..')) problems.push(`${where}: font/asset src traverses upward -> ${m[1]}`);
      }
      // 6. string-built asset paths that leave storefront/
      for (const m of text.matchAll(/["'](\.\.\/[^"']*)["']/g)) {
        const target = path.resolve(path.dirname(f.path), m[1]);
        if (!target.startsWith(ROOT + path.sep)) problems.push(`${where}: string path escapes storefront/ -> ${m[1]}`);
      }
    }

    if (isCss) {
      // 7. CSS @import and url() - never read by the filter's module scan
      for (const m of text.matchAll(/@import\s+(?:url\()?["']?([^"')\s]+)/g)) {
        problems.push(`${where}: CSS @import is an uninspected build input -> ${m[1]}`);
      }
      for (const m of text.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)) {
        const uri = m[1].trim();
        if (uri.startsWith('data:')) continue;
        if (uri.startsWith('http://') || uri.startsWith('https://') || uri.startsWith('//')) {
          problems.push(`${where}: remote CSS url() -> ${uri}`);
        } else if (uri.includes('..')) {
          problems.push(`${where}: CSS url() traverses upward -> ${uri}`);
        }
      }
    }
  }

  // 8. inherited configuration outside storefront/ that would change the build
  for (const name of ['.npmrc', '.nvmrc', 'package.json', 'tsconfig.json', 'next.config.mjs', 'vercel.json']) {
    const own = path.join(ROOT, name);
    if (['package.json', 'tsconfig.json', 'next.config.mjs', 'vercel.json'].includes(name) && !existsSync(own)) {
      problems.push(`missing required storefront-local ${name}`);
    }
  }
  // 9. forbidden request-time entrypoints the filter passes silently
  for (const forbidden of ['app/layout.tsx', 'app/api', 'api', 'middleware.ts', 'proxy.ts', 'instrumentation.ts']) {
    if (existsSync(path.join(ROOT, forbidden))) problems.push(`forbidden entrypoint present: ${forbidden}`);
  }
  // 10. lockfile present and singular
  if (!existsSync(path.join(ROOT, 'package-lock.json'))) problems.push('missing package-lock.json');
  for (const other of ['pnpm-lock.yaml', 'yarn.lock', 'npm-shrinkwrap.json']) {
    if (existsSync(path.join(ROOT, other))) problems.push(`second lockfile present: ${other}`);
  }

  return { problems, fileCount: files.length };
}

if (process.argv[1]?.endsWith('audit-inputs.mjs')) {
  const { problems, fileCount } = auditInputs();
  console.log(`scanned ${fileCount} source files under ${SOURCE_DIRS.join(', ')}`);
  if (problems.length) {
    console.error('\nINPUT AUDIT FAILED:');
    for (const p of problems) console.error('  - ' + p);
    process.exitCode = 1;
  } else {
    console.log('INPUT AUDIT PASSED - no uninspected external build input found');
  }
}
