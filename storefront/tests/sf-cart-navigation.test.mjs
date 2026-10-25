import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
const { cartNavigationHref } = await import('../src/routes/cart-navigation.ts');
const { menuPath, cartPath, checkoutPath, reviewPath } = await import('../src/routes/routes.ts');

test('direct cart and menu links retain an explicit Arabic root and tenant', () => {
  assert.equal(cartNavigationHref('/s/alpha/cart', '/ar/s/alpha/menu'), '/ar/s/alpha/cart');
  assert.equal(cartNavigationHref('/s/alpha/menu', '/ar/s/alpha/cart'), '/ar/s/alpha/menu');
});

test('the whole pre-submit journey preserves the explicit Arabic root, including returns', () => {
  const journey = ['menu', 'cart', 'checkout', 'review'];
  for (const current of journey) for (const target of journey) {
    assert.equal(cartNavigationHref(`/s/alpha/${target}`, `/ar/s/alpha/${current}`), `/ar/s/alpha/${target}`);
  }
  for (const target of ['cart', 'checkout', 'review']) {
    assert.equal(cartNavigationHref(`/s/alpha/${target}`, '/ar/s/alpha/payment'), `/ar/s/alpha/${target}`);
  }
  assert.equal(cartNavigationHref('/s/alpha/checkout', '/ar/s/alpha/search'), '/ar/s/alpha/checkout');
});

test('public canonical builders remain unchanged in every language', () => {
  for (const locale of ['ar', 'he', 'en']) for (const build of [menuPath, cartPath, checkoutPath, reviewPath]) {
    const href = build(locale, 'alpha');
    assert.ok(href.startsWith(locale === 'ar' ? '/s/alpha/' : `/${locale}/s/alpha/`));
    assert.equal(cartNavigationHref(href, `${locale === 'ar' ? '' : `/${locale}`}/s/alpha/cart`), href);
  }
});

test('canonical, non-Arabic and unrelated destinations are not rewritten', () => {
  for (const [href, current] of [
    ['/s/alpha/cart', '/s/alpha/menu'], ['/he/s/alpha/cart', '/he/s/alpha/menu'],
    ['/en/s/alpha/cart', '/en/s/alpha/menu'], ['/s/bravo/cart', '/ar/s/alpha/menu'],
    ['/he/s/alpha/cart', '/ar/s/alpha/menu'], ['/s/bravo/checkout', '/ar/s/alpha/cart'],
    ['/s/alpha/cart', '/ar/s/alpha/unknown'], ['/s/alpha/cart', null],
    ['/s/alpha/cart', '/ar/s/alpha/search'], ['/s/alpha/review', '/ar/s/alpha/search'],
    ['/s/alpha/payment', '/ar/s/alpha/checkout'], ['/r/abc123', '/ar/s/alpha/review'],
    ['/s/alpha/menu', '/ar/s/alpha/payment'],
    ['/s/alpha/checkout?x=1', '/ar/s/alpha/cart'], ['/s/alpha/review#x', '/ar/s/alpha/checkout'],
    ['/s/alpha/cart', '/ar/s/alpha/checkout/'], ['/s/alpha/cart', '/ar/s/alpha/review?x=1'],
    ['https://example.invalid/s/alpha/cart', '/ar/s/alpha/menu'],
    ['//example.invalid/s/alpha/cart', '/ar/s/alpha/menu'],
    ['/s/alpha/cart?x=1', '/ar/s/alpha/menu'], ['/s/alpha/cart#x', '/ar/s/alpha/menu'],
    ['/s/alpha/cart/', '/ar/s/alpha/menu'], ['/s/alpha/cart', '/ar//s/alpha/menu'],
  ]) assert.equal(cartNavigationHref(href, current), href, `${current} -> ${href}`);
});

test('live pre-submit navigation uses the root-preserving helper without changing recovery', () => {
  const aside = readFileSync(new URL('../src/ui/storefront/cart/LiveCartAside.tsx', import.meta.url), 'utf8');
  const flow = readFileSync(new URL('../src/ui/storefront/checkout/LiveFlowBody.tsx', import.meta.url), 'utf8');
  assert.match(aside, /const checkoutHref = cartNavigationHref\(canonicalCheckoutHref, pathname\)/);
  assert.match(aside, /if \(!blocked\) router\.push\(checkoutHref\)/);
  for (const kind of ['menu', 'cart', 'checkout', 'review']) {
    assert.ok(flow.includes(`${kind}: cartNavigationHref(${kind}Path(locale, slug), pathname)`));
  }
  assert.match(flow, /router\.replace\(hrefs\.cart\)/);
  assert.match(flow, /details\?\.ok \? hrefs\.review : hrefs\.checkout/);
  assert.match(flow, /screen === 'review' && !details\?\.ok\) router\.replace\(hrefs\.checkout\)/);
  assert.match(flow, /screen !== 'review'\) router\.replace\(reviewPath\(locale, slug\)\)/);
  assert.match(flow, /router\.push\(menuPath\(locale, slug\)\)/);
});
