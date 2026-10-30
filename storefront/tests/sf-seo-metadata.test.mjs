import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, mkdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';
import { auditOutput, withoutMenuCanonicalHref } from '../scripts/audit-output.mjs';

const { menuMetadata } = await import('../src/seo/menu.ts');
const { decodeStorefrontMenuV4 } = await import('../src/source/live/decodeContentV1.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { fixtureStorefrontSource } = await import('../src/source/storefront.ts');
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const SLUG = 'sf-seo-unit-alpha';
const MENU_PAGES = ['(root)', 'ar', 'he', 'en'].map(root => `app/${root}/s/[slug]/menu/page.tsx`);
const read = file => readFileSync(path.join(ROOT, file), 'utf8');
const resolution = (name = 'Synthetic Alpha', tagline = 'Synthetic merchant description', over = {}) => ({
  source: 'live', view: { tenant: { slug: SLUG, displayName: name, tagline, ...over } },
});
const walk = dir => readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
  const file = path.join(dir, entry.name);
  return entry.isDirectory() ? walk(file) : [file];
});

test('metadata describes only the matching tenant at the fixed public Arabic menu canonical', () => {
  const metadata = menuMetadata(SLUG, resolution());
  assert.equal(metadata.title, 'Synthetic Alpha');
  assert.equal(metadata.description, 'Synthetic merchant description');
  assert.deepEqual(metadata.alternates, { canonical: `https://menu.bizbot.systems/s/${SLUG}/menu` });
  assert.deepEqual(metadata.robots, { index: false, follow: false });
  assert.equal(metadata.alternates.languages, undefined);
  assert.equal(metadata.openGraph, undefined, 'no unverified social/locale claims are added');
});

test('empty tagline falls back to this tenant name without invented merchant claims', () => {
  for (const value of ['', ' \t\n ', null, undefined, 42]) {
    assert.equal(menuMetadata(SLUG, resolution('Synthetic Beta', '', { tagline: value })).description, 'Synthetic Beta');
  }
  assert.equal(menuMetadata(SLUG, resolution('  ', '')).title, 'BIZBOT');
});

test('metadata text collapses controls and whitespace and bounds Unicode scalar length', () => {
  const metadata = menuMetadata(SLUG, resolution('  Name\u0000\n  Café  ', '\t Own\r\n merchant\u007f description  '));
  assert.equal(metadata.title, 'Name Café');
  assert.equal(metadata.description, 'Own merchant description');
  const bounded = menuMetadata(SLUG, resolution('🍔'.repeat(170), '🍕'.repeat(330)));
  assert.equal(Array.from(bounded.title).length, 160);
  assert.equal(Array.from(bounded.description).length, 320);
  assert.equal(bounded.title, '🍔'.repeat(160));
  assert.equal(bounded.description, '🍕'.repeat(320));
});

test('hostile text remains data; metadata does not mutate the supplied resolution', () => {
  const hostile = '</title><script>alert("synthetic")</script> & Café';
  const supplied = resolution(hostile, '<img src=x onerror=alert(1)>');
  const before = structuredClone(supplied);
  const metadata = menuMetadata(SLUG, supplied);
  assert.equal(metadata.title, hostile);
  assert.equal(metadata.description, supplied.view.tenant.tagline);
  assert.deepEqual(supplied, before);
  assert.equal(metadata.alternates.canonical.includes(hostile), false);
});

test('invalid slug and another tenant resolution fail before emitting canonical or tenant metadata', () => {
  for (const slug of ['../other', 'two/slugs', '//example.invalid', 'UPPER', 'valid-slug\n', '']) {
    assert.throws(() => menuMetadata(slug, resolution()), /scope mismatch/);
  }
  assert.throws(() => menuMetadata(SLUG, resolution('Other tenant', 'Other description', { slug: 'sf-seo-unit-beta' })), /scope mismatch/);
});

test('existing fixture evidence alias inherits the noindex shell without inventing a public tenant identity', async () => {
  const original = process.env.SF_EVIDENCE_ROUTES;
  try {
    process.env.SF_EVIDENCE_ROUTES = '1';
    const resolved = await fixtureStorefrontSource.getStorefront('demo-closed');
    assert.ok(resolved);
    assert.equal(resolved.source, 'fixture');
    assert.notEqual(resolved.view.tenant.slug, 'demo-closed');
    assert.deepEqual(menuMetadata('demo-closed', resolved), { robots: { index: false, follow: false } });
    assert.throws(() => menuMetadata('demo-closed', { ...resolved, source: 'live' }), /scope mismatch/);
  } finally {
    if (original === undefined) delete process.env.SF_EVIDENCE_ROUTES;
    else process.env.SF_EVIDENCE_ROUTES = original;
  }
});

test('closed/paused and sold-out state do not fabricate publication or ordering promises in metadata', () => {
  for (const state of ['closed', 'paused', 'open']) {
    const supplied = resolution('Synthetic Alpha', 'Own description', { service: { state, orderingEnabled: false } });
    assert.equal(menuMetadata(SLUG, supplied).description, 'Own description');
    assert.deepEqual(menuMetadata(SLUG, supplied).robots, { index: false, follow: false });
  }
});

test('all four menu routes share the same request cache for metadata/page and retain ISR/not-found behavior', () => {
  for (const file of MENU_PAGES) {
    const source = read(file);
    assert.match(source, /import\s*\{\s*getMenuResolution,\s*menuMetadata\s*\}\s*from\s*['"]@\/seo\/menu['"]/);
    assert.equal((source.match(/await getMenuResolution\(slug\)/g) ?? []).length, 2, `${file}: metadata and page share one exported cache`);
    assert.match(source, /export async function generateMetadata/);
    assert.match(source, /export const revalidate = 60/);
    assert.match(source, /export const dynamicParams = true/);
    assert.equal((source.match(/if \(resolved === null\) notFound\(\)/g) ?? []).length, 2);
    assert.doesNotMatch(source, /\bcatch\b|unstable_cache|force-dynamic/);
  }
  const source = read('src/seo/menu.ts');
  assert.match(source, /export const getMenuResolution = cache\(/);
  assert.doesNotMatch(source, /\bfetch\s*\(|new Map\(|unstable_cache|revalidateTag|revalidatePath|process\.env|headers\(|cookies\(/);
  assert.match(read('next.config.mjs'), /expireTime:\s*360/);
});

test('private/request routes do not import tenant menu metadata or change their existing source boundaries', () => {
  const menuSet = new Set(MENU_PAGES);
  for (const file of walk(path.join(ROOT, 'app')).filter(file => file.endsWith('page.tsx'))) {
    const relative = path.relative(ROOT, file).split(path.sep).join('/');
    if (menuSet.has(relative)) continue;
    const source = readFileSync(file, 'utf8');
    assert.doesNotMatch(source, /@\/seo\/menu|menuMetadata|getMenuResolution|generateMetadata/, relative);
  }
});

test('all indexing barriers remain: root metadata, robots.txt and production X-Robots-Tag', () => {
  for (const root of ['(root)', 'ar', 'he', 'en']) {
    assert.match(read(`app/${root}/layout.tsx`), /robots:\s*\{\s*index:\s*false,\s*follow:\s*false\s*\}/);
  }
  assert.match(read('public/robots.txt'), /^Disallow:\s*\/$/m);
  const config = JSON.parse(read('vercel.json'));
  const wildcard = config.headers.find(rule => rule.source === '/(.*)');
  assert.equal(wildcard.headers.find(header => header.key.toLowerCase() === 'x-robots-tag')?.value, 'noindex, nofollow');
  assert.equal(config.headers.some(rule => /menu/.test(rule.source)), false, 'no indexing exception is introduced for menu routes');
});

test('public v4 remains strict and supplies no evidence of genuine language variants to the presentation model', () => {
  const wire = syntheticV4Envelope();
  wire.restaurant.locale_default = 'he';
  const result = adaptStorefront(decodeStorefrontMenuV4(wire), ORIGIN);
  assert.equal(Object.hasOwn(result.view.tenant, 'locale_default'), false);
  assert.equal(Object.hasOwn(result.view.tenant, 'translations'), false);
  assert.equal(menuMetadata(wire.restaurant.slug, result).alternates.languages, undefined);
  for (const extra of [{ seo: {} }, { translations: { he: 'Synthetic' } }]) {
    assert.throws(() => decodeStorefrontMenuV4({ ...wire, ...extra }));
  }
  assert.throws(() => decodeStorefrontMenuV4({ ...wire, restaurant: { ...wire.restaurant, seo_title: 'Not an approved field' } }));
});

test('output audit exempts only the matching non-loading canonical and retains off-origin negative controls', () => {
  const temporaryRoot = path.resolve(tmpdir());
  const dir = mkdtempSync(path.join(temporaryRoot, 'sf-seo-audit-'));
  const relative = `s/${SLUG}/menu.html`;
  const file = path.join(dir, relative);
  const canonical = `https://menu.bizbot.systems/s/${SLUG}/menu`;
  mkdirSync(path.dirname(file), { recursive: true });
  const auditResource = tag => {
    writeFileSync(file, `<!doctype html><html lang="ar" dir="rtl"><head>${tag}</head><body></body></html>`);
    return auditOutput(dir).problems.filter(problem => problem.includes('loads off-origin resource:'));
  };
  try {
    assert.deepEqual(auditResource(`<link rel="canonical" href="${canonical}"/>`), []);
    for (const prefix of ['', 'ar/', 'he/', 'en/']) {
      assert.equal(withoutMenuCanonicalHref(`<link href="${canonical}" rel="canonical"/>`, `${prefix}${relative}`).includes(canonical), false);
    }
    const negatives = [
      ['script', `<script src="${canonical}"></script>`],
      ['image', `<img src="${canonical}"/>`],
      ['form', `<form action="${canonical}"></form>`],
      ['preload', `<link rel="preload" href="${canonical}" as="script"/>`],
      ['mixed relation', `<link rel="canonical preload" href="${canonical}"/>`],
      ['duplicate relation', `<link rel="canonical" rel="preload" href="${canonical}"/>`],
      ['single-quoted prior relation', `<link rel='stylesheet' rel="canonical" href="${canonical}"/>`],
      ['unquoted prior relation', `<link rel=stylesheet rel="canonical" href="${canonical}"/>`],
      ['spaced prior relation', `<link rel = "stylesheet" rel="canonical" href="${canonical}"/>`],
      ['another tenant', '<link rel="canonical" href="https://menu.bizbot.systems/s/sf-seo-unit-beta/menu"/>'],
      ['another origin', `<link rel="canonical" href="https://example.invalid/s/${SLUG}/menu"/>`],
      ['query', `<link rel="canonical" href="${canonical}?fx=anything"/>`],
      ['fragment', `<link rel="canonical" href="${canonical}#menu"/>`],
      ['localized duplicate', `<link rel="canonical" href="https://menu.bizbot.systems/he/s/${SLUG}/menu"/>`],
      ['other attribute retained', `<link rel="canonical" href="${canonical}" src="https://example.invalid/load"/>`],
      ['another href retained', `<link rel="canonical" href="${canonical}" href="https://example.invalid/load"/>`],
    ];
    for (const [label, tag] of negatives) assert.ok(auditResource(tag).length > 0, `${label}: must remain an off-origin resource error`);
    assert.equal(withoutMenuCanonicalHref(`<link rel="canonical" href="${canonical}"/>`, `s/${SLUG}/cart.html`).includes(canonical), true, 'no canonical exception on private flow documents');
    assert.equal(withoutMenuCanonicalHref(`<link rel="canonical" href="${canonical}"/>`, 'index.html').includes(canonical), true, 'no canonical exception on root shell');
  } finally {
    assert.equal(path.dirname(path.resolve(dir)), temporaryRoot);
    assert.ok(path.basename(dir).startsWith('sf-seo-audit-'));
    rmSync(dir, { recursive: true }); // Only this test's checked, freshly-created temporary directory.
  }
});
