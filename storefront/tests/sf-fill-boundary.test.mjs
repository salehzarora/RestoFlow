import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';
const { fill, storefrontMessages } = await import('../src/i18n/storefront.ts');
const { fill: pure } = await import('../src/i18n/fill.ts');

test('pure formatter keeps the existing exported identity and every locale/placeholder value', () => {
  assert.equal(pure, fill);
  for (const locale of ['ar', 'he', 'en']) for (const value of Object.values(storefrontMessages(locale))) {
    if (typeof value === 'string') assert.equal(pure(value, { n: '3', group: 'وجبة', time: '13:00' }), fill(value, { n: '3', group: 'وجبة', time: '13:00' }));
  }
  assert.equal(pure('{n} {unknown} {constructor}', { n: '3' }), '3 {unknown} {constructor}');
  const values = Object.assign(Object.create(null), { n: 'שלום' });
  assert.equal(pure('{n} {n}', values), 'שלום שלום');
});

test('menu client presentation receives the current dictionary without importing the dictionary selector', () => {
  for (const name of ['home/HomeChrome.tsx', 'StorefrontRuntime.tsx', 'cart/CartRuntime.tsx', 'search/SearchScreen.tsx']) {
    const source = readFileSync(new URL('../src/ui/storefront/' + name, import.meta.url), 'utf8');
    assert.doesNotMatch(source, /storefrontMessages/);
    assert.match(source, /m: StorefrontMessages/);
  }
  assert.doesNotMatch(readFileSync(new URL('../src/i18n/fill.ts', import.meta.url), 'utf8'), /import|messages|fetch\(/);
});

test('fixture and live checkout dependency graphs cannot pull the storefront dictionaries into the client', () => {
  const src = fileURLToPath(new URL('../src/', import.meta.url));
  const resolveLocal = (from, value) => {
    const base = value.startsWith('@/') ? path.join(src, value.slice(2))
      : value.startsWith('.') ? path.resolve(path.dirname(from), value) : null;
    if (!base) return null;
    return [base, ...['.ts', '.tsx', '.json', '/index.ts', '/index.tsx'].map(ext => base + ext)].find(file => existsSync(file) && /\.(ts|tsx|json)$/.test(file)) ?? null;
  };
  const valueBinding = clause => !clause?.isTypeOnly && (!clause || clause.name || !ts.isNamedImports(clause.namedBindings) || clause.namedBindings.elements.some(item => !item.isTypeOnly));
  for (const entry of ['checkout/FlowRuntime.tsx', 'checkout/LiveFlowRuntime.tsx']) {
    const seen = new Set();
    const visit = file => {
      if (seen.has(file)) return;
      seen.add(file);
      if (file.endsWith('.json')) return;
      const tree = ts.createSourceFile(file, readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
      const edge = specifier => { const target = resolveLocal(file, specifier); if (target) visit(target); };
      const walk = node => {
        if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier) && valueBinding(node.importClause)) edge(node.moduleSpecifier.text);
        if (ts.isExportDeclaration(node) && !node.isTypeOnly && node.moduleSpecifier && ts.isStringLiteral(node.moduleSpecifier)
          && (!node.exportClause || !ts.isNamedExports(node.exportClause) || node.exportClause.elements.some(item => !item.isTypeOnly))) edge(node.moduleSpecifier.text);
        if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword && ts.isStringLiteral(node.arguments[0])) edge(node.arguments[0].text);
        ts.forEachChild(node, walk);
      };
      walk(tree);
    };
    visit(path.join(src, 'ui/storefront', entry));
    assert.ok(seen.size > 20, 'The actual transitive application graph is inspected');
    assert.deepEqual([...seen].filter(file => /i18n[\\/]storefront\.ts$|storefront\.(ar|he|en)\.json$/.test(file)), [], entry + ': only supplied public text belongs in the client graph');
    assert.ok(seen.has(path.join(src, 'i18n/fill.ts')), 'Existing formatter remains in use');
  }
});

const { packStorefrontMessages, unpackStorefrontMessages } = await import('../src/i18n/storefrontValues.ts');

test('public current-locale values preserve every dictionary key, value and formatter without another request', () => {
  for (const locale of ['ar', 'he', 'en']) {
    const original = storefrontMessages(locale);
    const values = packStorefrontMessages(original);
    const restored = unpackStorefrontMessages(JSON.parse(JSON.stringify(values)));
    assert.deepEqual(restored, original);
    assert.equal(values.length, Object.keys(original).length, 'No omitted or duplicate keys');
    assert.ok(Buffer.byteLength(JSON.stringify(values)) < Buffer.byteLength(JSON.stringify(original)) - 2000);
    for (const key of Object.keys(original)) if (typeof original[key] === 'string') {
      assert.equal(pure(restored[key], { n: '3', time: '13:00' }), fill(original[key], { n: '3', time: '13:00' }));
    }
    assert.throws(() => unpackStorefrontMessages(values.slice(1)), /incomplete/);
    assert.throws(() => unpackStorefrontMessages([...values, 'extra']), /incomplete/);
  }
  const boundary = readFileSync(new URL('../src/i18n/storefrontValues.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(boundary, /fetch\(|messages\/|storefront\.(?:ar|en|he)\.json/);
});
