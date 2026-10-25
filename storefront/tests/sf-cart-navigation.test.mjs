import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
const { cartNavigationHref } = await import('../src/routes/cart-navigation.ts');

test('direct cart and menu links retain an explicit Arabic root and tenant', () => {
  assert.equal(cartNavigationHref('/s/alpha/cart', '/ar/s/alpha/menu'), '/ar/s/alpha/cart');
  assert.equal(cartNavigationHref('/s/alpha/menu', '/ar/s/alpha/cart'), '/ar/s/alpha/menu');
});

test('canonical, non-Arabic and unrelated destinations are not rewritten', () => {
  for (const [href, current] of [
    ['/s/alpha/cart', '/s/alpha/menu'], ['/he/s/alpha/cart', '/he/s/alpha/menu'],
    ['/en/s/alpha/cart', '/en/s/alpha/menu'], ['/s/bravo/cart', '/ar/s/alpha/menu'],
    ['/he/s/alpha/cart', '/ar/s/alpha/menu'], ['/s/alpha/checkout', '/ar/s/alpha/cart'],
    ['/s/alpha/cart', '/ar/s/alpha/unknown'], ['/s/alpha/cart', null],
    ['/s/alpha/cart', '/ar/s/alpha/checkout'], ['/s/alpha/cart', '/ar/s/alpha/search'],
    ['https://example.invalid/s/alpha/cart', '/ar/s/alpha/menu'],
    ['//example.invalid/s/alpha/cart', '/ar/s/alpha/menu'],
    ['/s/alpha/cart?x=1', '/ar/s/alpha/menu'], ['/s/alpha/cart#x', '/ar/s/alpha/menu'],
    ['/s/alpha/cart/', '/ar/s/alpha/menu'], ['/s/alpha/cart', '/ar//s/alpha/menu'],
  ]) assert.equal(cartNavigationHref(href, current), href, `${current} -> ${href}`);
});
