// Route shapes. The approved strategy is static slugs under each existing
// locale root, `/s/:slug` and `/r/:ref`, with the UNPREFIXED path owned by the
// default locale. No rewrites, so every path a builder returns must be a path
// the export actually emits.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const r = await import('../src/routes/routes.ts');
const { LOCALES, DEFAULT_LOCALE } = await import('../src/i18n/locales.ts');

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
