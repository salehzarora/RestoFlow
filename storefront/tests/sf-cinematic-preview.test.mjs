import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const { CINEMATIC_PREVIEW_SLUG, cinematicPreviewAllowed, cinematicPreviewScreen } = await import('../src/preview/cinematic/access.ts');
const { cinematicPreviewResolution } = await import('../src/preview/cinematic/resolution.ts');
const { headlineParts } = await import('../src/ui/storefront/contentPresentation.ts');
const read = (file) => JSON.parse(readFileSync(new URL(`../src/preview/cinematic/${file}`, import.meta.url), 'utf8'));
const catalog = read('catalog.snapshot.json');
const runtime = read('runtime.snapshot.json');
const previewEnv = { VERCEL: '1', VERCEL_ENV: 'preview', STOREFRONT_SOURCE: 'live' };

test('the cinematic sample is closed in Production and every other provider context', () => {
  for (const env of [
    { VERCEL: '1', VERCEL_ENV: 'production' },
    { VERCEL_ENV: 'production', STOREFRONT_SOURCE: 'fixture', SF_DESIGN_PREVIEW: '1' },
    { VERCEL: '1', STOREFRONT_SOURCE: 'fixture', SF_DESIGN_PREVIEW: '1' },
    { VERCEL_ENV: 'development', STOREFRONT_SOURCE: 'fixture', SF_DESIGN_PREVIEW: '1' },
    { VERCEL: '0', STOREFRONT_SOURCE: 'fixture', SF_DESIGN_PREVIEW: '1' },
  ]) {
    assert.equal(cinematicPreviewAllowed(env), false);
    assert.equal(cinematicPreviewResolution(env), null);
  }
  assert.equal(cinematicPreviewAllowed(previewEnv), true);
});

test('local preview requires both explicit fixture mode and its own opt-in', () => {
  for (const env of [{}, { STOREFRONT_SOURCE: 'fixture' }, { SF_DESIGN_PREVIEW: '1' },
    { STOREFRONT_SOURCE: 'live', SF_DESIGN_PREVIEW: '1' },
    { STOREFRONT_SOURCE: 'fixture', SF_DESIGN_PREVIEW: 'true' }]) {
    assert.equal(cinematicPreviewAllowed(env), false);
  }
  assert.equal(cinematicPreviewAllowed({ STOREFRONT_SOURCE: 'fixture', SF_DESIGN_PREVIEW: '1' }), true);
});

test('the preview route only exposes intro, menu, search and cart', () => {
  assert.equal(cinematicPreviewScreen(undefined), 'intro');
  assert.equal(cinematicPreviewScreen([]), 'intro');
  for (const screen of ['menu', 'search', 'cart']) assert.equal(cinematicPreviewScreen([screen]), screen);
  for (const segments of [['checkout'], ['payment'], ['review'], ['request'], ['menu', 'cart'], [''], ['..'], ['menu/checkout']]) {
    assert.equal(cinematicPreviewScreen(segments), null);
  }
});

test('captured catalog content and options survive the presentation profile without fabricated products', () => {
  const resolved = cinematicPreviewResolution(previewEnv);
  const contentOnly = ({ image, imageFit, cardLayout, ...content }) => content;
  assert.equal(resolved.view.items.length, 20);
  assert.equal(resolved.view.categories.length, 4);
  assert.deepEqual(resolved.view.items.map(contentOnly), runtime.items.map(contentOnly));
  assert.deepEqual(resolved.view.categories, catalog.categories);
  assert.deepEqual(resolved.groups, runtime.groups);
  assert.deepEqual(resolved.zones, runtime.zones);
  assert.equal(resolved.taxRateBp, runtime.taxRateBp);
  assert.deepEqual(resolved.view.tenant.hours, catalog.tenant.hours);
  assert.deepEqual(resolved.view.tenant.service, { ...catalog.tenant.service, orderingEnabled: false });
  for (const field of ['displayName', 'tagline', 'address', 'city', 'phone']) {
    assert.equal(resolved.view.tenant[field], catalog.tenant[field]);
  }
  for (const item of resolved.view.items) assert.equal(item.image, `/cinematic-preview/${item.id}.webp`);
});

test('the sample is browse-only, uses a separate cart namespace and contains no order gateway origin', () => {
  const resolved = cinematicPreviewResolution(previewEnv);
  assert.equal(resolved.source, 'fixture');
  assert.equal(resolved.view.tenant.slug, CINEMATIC_PREVIEW_SLUG);
  assert.notEqual(resolved.view.tenant.slug, catalog.tenant.slug);
  assert.equal(resolved.view.tenant.service.orderingEnabled, false);
  assert.equal(Object.hasOwn(resolved, 'orderEndpointOrigin'), false);
  assert.deepEqual(resolved.view.cart.lines, []);
  assert.match(resolved.menuVersion, /^cinematic-preview-/);
});

test('headline formatting highlights the approved word and retains its exact Unicode text', () => {
  const { campaign } = cinematicPreviewResolution(previewEnv).view.modules;
  const parts = headlineParts(campaign.title, campaign.hero.format);
  assert.equal(parts.map(part => part.text).join(''), campaign.title);
  assert.equal(parts.filter(part => part.highlight).map(part => part.text).join(''), 'وجهة');
  assert.equal(campaign.hero.format.break_before, 6);
});

test('all four preview roots remain dynamic, noindex and behind the shared server guard', () => {
  const source = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
  for (const root of ['(root)', 'ar', 'he', 'en']) {
    const route = `app/${root}/s/sf-design-preview`;
    const layout = source(`${route}/layout.tsx`);
    assert.match(layout, /dynamic = 'force-dynamic'/);
    assert.match(layout, /robots: \{ index: false, follow: false \}/);
    assert.match(layout, /<CinematicPreviewLayout\b/);
    assert.match(source(`${route}/[[...screen]]/page.tsx`), /dynamic = 'force-dynamic'/);
  }
  const layout = source('src/preview/cinematic/PreviewLayout.tsx');
  assert.match(layout, /if \(!cinematicPreviewAllowed\(\)\) notFound\(\)/);
  assert.match(layout, /<CheckoutEntry source="fixture" slug=\{CINEMATIC_PREVIEW_SLUG\}/);
  assert.match(source('src/preview/cinematic/PreviewPage.tsx'), /if \(screen === null \|\| resolution === null\) notFound\(\)/);
});
