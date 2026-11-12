import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
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
