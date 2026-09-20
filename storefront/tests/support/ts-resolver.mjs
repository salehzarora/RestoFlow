// Test-only module resolution.
//
// The application source is written for Turbopack: extensionless relative
// specifiers and the `@/*` alias from tsconfig.json. Node's ESM resolver does
// neither. Rather than bending the source to suit the test runner — which would
// mean the tests no longer exercise the shipped files — this hook teaches Node
// the same two rules the bundler already applies.
//
// It runs ONLY under `node --test`. Nothing here is part of the build.
import { registerHooks } from 'node:module';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const STOREFRONT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const SRC = path.join(STOREFRONT, 'src');
const EXTENSIONS = ['.ts', '.tsx', '.mts', '.js', '.mjs'];

/** Resolve a bare path to a real file, trying each extension and /index. */
function locate(base) {
  if (existsSync(base) && path.extname(base) !== '') return base;
  for (const ext of EXTENSIONS) {
    if (existsSync(base + ext)) return base + ext;
  }
  for (const ext of EXTENSIONS) {
    const asIndex = path.join(base, 'index' + ext);
    if (existsSync(asIndex)) return asIndex;
  }
  return null;
}

registerHooks({
  resolve(specifier, context, next) {
    // `@/x` -> storefront/src/x, matching tsconfig paths.
    if (specifier.startsWith('@/')) {
      const found = locate(path.join(SRC, specifier.slice(2)));
      if (found) return next(pathToFileURL(found).href, context);
    }
    // Extensionless relative specifier -> add the extension Turbopack infers.
    if ((specifier.startsWith('./') || specifier.startsWith('../')) && path.extname(specifier) === '') {
      const parentPath = context.parentURL ? fileURLToPath(context.parentURL) : STOREFRONT;
      const found = locate(path.resolve(path.dirname(parentPath), specifier));
      if (found) return next(pathToFileURL(found).href, context);
    }
    return next(specifier, context);
  },
  load(url, context, next) {
    // `resolveJsonModule` lets the source import JSON without an import
    // attribute; Node requires one. Supply it on the source's behalf.
    if (url.endsWith('.json')) {
      return next(url, { ...context, importAttributes: { type: 'json' } });
    }
    return next(url, context);
  },
});
