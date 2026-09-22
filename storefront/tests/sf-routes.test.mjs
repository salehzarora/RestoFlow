// Route shapes. The approved strategy is static slugs under each existing
// locale root, `/s/:slug` and `/r/:ref`, with the UNPREFIXED path owned by the
// default locale. No rewrites, so every path a builder returns must be a path
// the export actually emits.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const r = await import('../src/routes/routes.ts');
const { LOCALES, DEFAULT_LOCALE } = await import('../src/i18n/locales.ts');
const { ROUTES, REQUIRED_HTML } = await import('../scripts/budgets.mjs');

test('the default locale owns the unprefixed path', () => {
  assert.equal(DEFAULT_LOCALE, 'ar');
  assert.equal(r.localePrefix('ar'), '');
  assert.equal(r.storefrontPath('ar', 'maps-burger'), '/s/maps-burger');
  assert.equal(r.localeHomePath('ar'), '/');
});

test('non-default locales are explicitly prefixed', () => {
  assert.equal(r.storefrontPath('en', 'maps-burger'), '/en/s/maps-burger');
  assert.equal(r.storefrontPath('he', 'maps-burger'), '/he/s/maps-burger');
  assert.equal(r.requestPath('he', 'MB-2487'), '/he/r/MB-2487');
  assert.equal(r.localeHomePath('en'), '/en');
});

test('no builder emits a trailing slash or a double slash', () => {
  const paths = [];
  for (const locale of LOCALES) {
    paths.push(r.storefrontPath(locale, 'maps-burger'), r.requestPath(locale, 'MB-2487'), r.localeHomePath(locale));
  }
  for (const p of paths) {
    assert.ok(p.startsWith('/'), `${p} must be root-relative`);
    assert.ok(!p.includes('//'), `${p} has a double slash`);
    assert.ok(p === '/' || !p.endsWith('/'), `${p} has a trailing slash`);
  }
});

test('parseRoute round-trips every builder output', () => {
  for (const locale of LOCALES) {
    const sp = r.storefrontPath(locale, 'maps-burger');
    assert.deepEqual(r.parseRoute(sp), { locale, kind: 'storefront', slug: 'maps-burger' });
    const rp = r.requestPath(locale, 'MB-2487');
    assert.deepEqual(r.parseRoute(rp), { locale, kind: 'request', ref: 'MB-2487' });
    assert.deepEqual(r.parseRoute(r.localeHomePath(locale)), { locale, kind: 'localeHome' });
  }
});

test('an invalid slug or ref parses as unknown rather than as a route', () => {
  for (const p of ['/s/Bad Slug', '/s/../etc', '/r/lower-case', '/s/', '/s/a/b/c', '/nope']) {
    assert.equal(r.parseRoute(p).kind, 'unknown', `${p} must not parse as a route`);
  }
});

test('language switching keeps the same screen', () => {
  assert.equal(r.switchLocalePath('/s/maps-burger', 'en'), '/en/s/maps-burger');
  assert.equal(r.switchLocalePath('/he/s/maps-burger', 'ar'), '/s/maps-burger');
  assert.equal(r.switchLocalePath('/en/r/MB-2487', 'he'), '/he/r/MB-2487');
  assert.equal(r.switchLocalePath('/', 'he'), '/he');
  assert.equal(r.switchLocalePath('/en', 'ar'), '/');
});

test('switching on a path we do not own returns null, never a guess', () => {
  for (const p of ['/nope', '/s/Bad Slug', '/_next/static/x.js']) {
    assert.equal(r.switchLocalePath(p, 'en'), null, `${p} must not produce a route`);
  }
});

test('switching is an involution across every locale pair', () => {
  for (const from of LOCALES) {
    const start = r.storefrontPath(from, 'maps-burger');
    for (const to of LOCALES) {
      const moved = r.switchLocalePath(start, to);
      assert.equal(moved, r.storefrontPath(to, 'maps-burger'));
      assert.equal(r.switchLocalePath(moved, from), start, `${from} -> ${to} -> ${from}`);
    }
  }
});

test('alternates name every locale exactly once', () => {
  const alt = r.storefrontAlternates('maps-burger');
  assert.deepEqual(Object.keys(alt).sort(), [...LOCALES].sort());
  assert.equal(new Set(Object.values(alt)).size, LOCALES.length, 'alternates must be distinct');
});

// ------------------------------------------------ the deeper storefront screens

test('menu and search have builders, and they compose off storefrontPath', () => {
  for (const locale of LOCALES) {
    const base = r.storefrontPath(locale, 'maps-burger');
    assert.equal(r.menuPath(locale, 'maps-burger'), `${base}/menu`);
    assert.equal(r.searchPath(locale, 'maps-burger'), `${base}/search`);
  }
  assert.equal(r.searchPath('ar', 'maps-burger'), '/s/maps-burger/search');
  assert.equal(r.searchPath('en', 'maps-burger'), '/en/s/maps-burger/search');
});

test('a 3-segment storefront path parses, so the language switcher does not silently fail', () => {
  // Before Phase C these returned `unknown`, which makes switchLocalePath
  // return null - the switcher would quietly refuse to move between locales on
  // the menu and search screens.
  for (const locale of LOCALES) {
    assert.deepEqual(r.parseRoute(r.menuPath(locale, 'maps-burger')),
      { locale, kind: 'menu', slug: 'maps-burger' });
    assert.deepEqual(r.parseRoute(r.searchPath(locale, 'maps-burger')),
      { locale, kind: 'search', slug: 'maps-burger' });
  }
});

test('only the SIX named leaves parse; any other third segment stays unknown', () => {
  // Phase D added cart/checkout/payment/review as real segments, so they must
  // now PARSE - otherwise the language switcher falls through to `unknown` and
  // a visitor changing language mid-checkout is thrown back to the menu with a
  // full document load, losing a draft that lives only in memory.
  for (const locale of LOCALES) {
    for (const [leaf, build] of [
      ['cart', r.cartPath],
      ['checkout', r.checkoutPath],
      ['payment', r.paymentPath],
      ['review', r.reviewPath],
    ]) {
      assert.deepEqual(r.parseRoute(build(locale, 'maps-burger')),
        { locale, kind: leaf, slug: 'maps-burger' });
    }
  }
  // The whitelist is still closed: a leaf nobody declared does not parse.
  for (const p of ['/s/maps-burger/received', '/s/maps-burger/menu/extra',
                   '/s/Bad Slug/search', '/s/maps-burger/MENU', '/s/maps-burger/CART',
                   '/s/maps-burger/checkout/extra']) {
    assert.equal(r.parseRoute(p).kind, 'unknown', `${p} must not parse`);
  }
  // A trailing slash is NOT a third segment: empty segments are filtered, and
  // the committed vercel.json sets trailingSlash: false, so `/s/x/` is the same
  // resource as `/s/x` and must keep parsing as the storefront.
  assert.equal(r.parseRoute('/s/maps-burger/').kind, 'storefront');
  assert.equal(r.parseRoute('/s/maps-burger/search/').kind, 'search');
});

test('switching locale on a FLOW step keeps the SAME step', () => {
  // The four Phase D screens are where this matters most: the checkout draft is
  // application memory only, so anything that forces a full document load loses
  // the visitor's name, phone and address.
  assert.equal(r.switchLocalePath('/s/maps-burger/cart', 'en'), '/en/s/maps-burger/cart');
  assert.equal(r.switchLocalePath('/he/s/maps-burger/checkout', 'ar'), '/s/maps-burger/checkout');
  assert.equal(r.switchLocalePath('/en/s/maps-burger/payment', 'he'), '/he/s/maps-burger/payment');
  assert.equal(r.switchLocalePath('/s/maps-burger/review', 'he'), '/he/s/maps-burger/review');
  // NEGATIVE CONTROL: a leaf that is NOT declared still refuses, so the four
  // cases above prove the whitelist rather than a wildcard.
  assert.equal(r.switchLocalePath('/s/maps-burger/received', 'en'), null);
});

test('switching locale on menu and search keeps the SAME screen', () => {
  assert.equal(r.switchLocalePath('/s/maps-burger/search', 'en'), '/en/s/maps-burger/search');
  assert.equal(r.switchLocalePath('/he/s/maps-burger/menu', 'ar'), '/s/maps-burger/menu');
  assert.equal(r.switchLocalePath('/en/s/maps-burger/search', 'he'), '/he/s/maps-burger/search');
  // ...and never swaps one screen for another.
  assert.notEqual(r.switchLocalePath('/s/maps-burger/search', 'en'), '/en/s/maps-burger/menu');
});

test('switching is still an involution on the deeper screens', () => {
  for (const build of [r.menuPath, r.searchPath]) {
    for (const from of LOCALES) {
      const start = build(from, 'maps-burger');
      for (const to of LOCALES) {
        const moved = r.switchLocalePath(start, to);
        assert.equal(moved, build(to, 'maps-burger'));
        assert.equal(r.switchLocalePath(moved, from), start, `${from} -> ${to} -> ${from}`);
      }
    }
  }
});

test('the SEARCH routes are in the standard first-load measurement set', () => {
  // Phase C added four routes. Before C1 none of them was measured, so a
  // "first-load budget passed, per route" claim silently excluded the whole
  // new surface.
  const wanted = [
    '/s/maps-burger/search',
    '/ar/s/maps-burger/search',
    '/en/s/maps-burger/search',
    '/he/s/maps-burger/search',
  ];
  const measured = ROUTES.map((r) => r.route);
  for (const route of wanted) {
    assert.ok(measured.includes(route), `${route} is not in the measured route list`);
  }
  // The menu routes must still be there.
  for (const route of ['/s/maps-burger/menu', '/he/s/maps-burger/menu']) {
    assert.ok(measured.includes(route), `${route} fell out of the measured list`);
  }
  // Every measured route must name a file the export is required to emit, or
  // the measurement would silently skip it.
  for (const { route, file } of ROUTES) {
    assert.ok(typeof file === 'string' && file.endsWith('.html'), `${route}: bad file`);
  }
  for (const route of wanted) {
    const { file } = ROUTES.find((r) => r.route === route);
    assert.ok(REQUIRED_HTML.includes(file), `${file} must also be a required document`);
  }
  // PRODUCTION measurement only: no demo or evidence route may appear.
  for (const { route } of ROUTES) {
    assert.ok(!route.includes('demo-'), `${route}: a demo route must not be measured`);
  }
});
