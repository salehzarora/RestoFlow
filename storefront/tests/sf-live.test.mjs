// STOREFRONT-READ-001 - the live read path, unit level: the decoder's trust
// boundary (T-S5 contract half), the adapter's mapping rules (packet §3), the
// source switch, and the server-only client (T-S6 / T-S8 unit halves). The
// network is never touched: the client is exercised through an injected
// `fetch` and every envelope is synthetic (tests/support/envelope.mjs).
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { NOT_FOUND_ENVELOPE, PAYLOAD_LIMIT_ENVELOPE, SYNTH_IDS, SYNTH_MEDIA_PATH, syntheticEnvelope } from './support/envelope.mjs';

const { decodeStorefrontMenu, EnvelopeError, CAPS } = await import('../src/source/live/decode.ts');
const { adaptStorefront, liveStorefrontSource, mediaUrl, nextOpenParts } = await import('../src/source/live/adapter.ts');
const { liveConfig, storefrontMenuRequest, fetchStorefrontMenu } = await import('../src/source/live/client.ts');
const { CATEGORY_ICON_KEYS, iconPathFor, DEFAULT_ICON_KEY } = await import('../src/source/live/icons.ts');
const { sourceMode, isLiveMode, isProviderContext, fixtureStorefrontSource, storefrontSource } = await import('../src/source/storefront.ts');
const { buildQuote } = await import('../src/money/quote.ts');
const { summarise, addLine } = await import('../src/cart/cartModel.ts');

const ORIGIN = 'https://example-project.supabase.co';
const CONFIG = { url: ORIGIN, anonKey: 'sb_publishable_SYNTHETIC_not_a_real_key_0000' };

// ------------------------------------------------------------------ decoder

test('a contract-shaped envelope decodes, and every key set is checked by EQUALITY', () => {
  const ok = decodeStorefrontMenu(syntheticEnvelope());
  assert.equal(ok.ok, true);
  assert.equal(ok.restaurant.slug, 'sf-synth-a');
  assert.equal(ok.tax.rate_bp, 1800);
  // an EXTRA key anywhere rejects the whole envelope
  for (const mutate of [
    (e) => ({ ...e, extra: 1 }),
    (e) => ({ ...e, restaurant: { ...e.restaurant, organization_id: 'x' } }),
    (e) => ({ ...e, items: [{ ...e.items[0], sku: 'SECRET' }, ...e.items.slice(1)] }),
    (e) => ({ ...e, items: [{ ...e.items[0], image_path: 'private/key.jpg' }, ...e.items.slice(1)] }),
    (e) => ({ ...e, modifiers: [{ ...e.modifiers[0], allow_quantity: true }, ...e.modifiers.slice(1)] }),
    (e) => ({ ...e, modifier_options: [{ ...e.modifier_options[0], kitchen_meat: null }, ...e.modifier_options.slice(1)] }),
  ]) {
    assert.throws(() => decodeStorefrontMenu(mutate(syntheticEnvelope())), EnvelopeError);
  }
  // a MISSING key rejects too
  const missing = syntheticEnvelope();
  delete missing.hours;
  assert.throws(() => decodeStorefrontMenu(missing), EnvelopeError);
});

test('money and rates must be SAFE INTEGERS; a negative delta or a float is a contract break', () => {
  for (const mutate of [
    (e) => ({ ...e, items: [{ ...e.items[0], base_price_minor: 40.5 }, ...e.items.slice(1)] }),
    (e) => ({ ...e, items: [{ ...e.items[0], base_price_minor: '4000' }, ...e.items.slice(1)] }),
    (e) => ({ ...e, items: [{ ...e.items[0], base_price_minor: -1 }, ...e.items.slice(1)] }),
    (e) => ({ ...e, modifier_options: [{ ...e.modifier_options[0], price_delta_minor: -200 }, ...e.modifier_options.slice(1)] }),
    (e) => ({ ...e, tax: { ...e.tax, rate_bp: 0.18 } }),
    (e) => ({ ...e, tax: { ...e.tax, rate_bp: 10001 } }),
    (e) => ({ ...e, tax: { enabled: true, rate_bp: 1800, mode: 'inclusive' } }),
  ]) {
    assert.throws(() => decodeStorefrontMenu(mutate(syntheticEnvelope())), EnvelopeError);
  }
});

test('the browse-only contract is ASSERTED by the decoder: ordering or delivery on is rejected', () => {
  assert.throws(() => decodeStorefrontMenu(syntheticEnvelope({ service: { ordering_enabled: true } })), EnvelopeError);
  assert.throws(() => decodeStorefrontMenu(syntheticEnvelope({ service: { delivery_enabled: true } })), EnvelopeError);
});

test('closed enums, uuid ids, HH:MM hours and the tag vocabulary are enforced', () => {
  for (const mutate of [
    (e) => ({ ...e, restaurant: { ...e.restaurant, currency_code: 'EUR' } }),
    (e) => ({ ...e, restaurant: { ...e.restaurant, visual_preset: 'neon' } }),
    (e) => ({ ...e, restaurant: { ...e.restaurant, primary_color: 'red' } }),
    (e) => ({ ...e, service: { ...e.service, state: 'busy' } }),
    (e) => ({ ...e, hours: { ...e.hours, opens: '9:00' } }),
    (e) => ({ ...e, items: [{ ...e.items[0], id: 'not-a-uuid' }, ...e.items.slice(1)] }),
    (e) => ({ ...e, items: [{ ...e.items[0], tags: ['internal-x'] }, ...e.items.slice(1)] }),
    (e) => ({ ...e, items: [{ ...e.items[0], availability: 'maybe' }, ...e.items.slice(1)] }),
    (e) => ({ ...e, menu_version: 'mb-1' }),
  ]) {
    assert.throws(() => decodeStorefrontMenu(mutate(syntheticEnvelope())), EnvelopeError);
  }
});

test('the failure envelopes decode as failures; anything that is not an object is rejected', () => {
  assert.deepEqual(decodeStorefrontMenu(NOT_FOUND_ENVELOPE), { ok: false, error: 'not_found', entity: 'storefront_menu' });
  assert.deepEqual(decodeStorefrontMenu(PAYLOAD_LIMIT_ENVELOPE), { ok: false, error: 'payload_limit', entity: 'storefront_menu' });
  for (const bad of [null, undefined, 'x', 42, [], { ok: false }, { ok: 'true' }]) {
    assert.throws(() => decodeStorefrontMenu(bad), EnvelopeError, `must reject ${JSON.stringify(bad)}`);
  }
});

test('the decoder mirrors the RPC caps', () => {
  assert.deepEqual(CAPS, { categories: 100, items: 500, modifiers: 2000, options: 8000 });
  const many = syntheticEnvelope();
  many.items = Array.from({ length: 501 }, (_, i) => ({ ...many.items[1], id: `00000000-0000-0000-0000-${String(i).padStart(12, '0')}` }));
  assert.throws(() => decodeStorefrontMenu(many), EnvelopeError);
});

test('text caps count CODE POINTS like the server: an astral character at the cap is one UTF-16 unit longer and still decodes', () => {
  const atCap = 'x'.repeat(599) + '\u{1F600}'; // 600 code points = what left(description, 600) can serve; 601 UTF-16 units
  assert.equal(atCap.length, 601);
  const e = syntheticEnvelope();
  e.items[0].description = atCap;
  assert.equal(decodeStorefrontMenu(e).items[0].description, atCap);
  e.items[0].description = 'x'.repeat(601); // 601 code points: the server never serves it, the decoder refuses it
  assert.throws(() => decodeStorefrontMenu(e), EnvelopeError);
  const name = syntheticEnvelope();
  name.restaurant.display_name = 'y'.repeat(59) + '\u{1F354}'; // 60 code points, the display_name CHECK cap
  assert.equal(decodeStorefrontMenu(name).restaurant.display_name, name.restaurant.display_name);
});

test('min_select / max_select accept the STORAGE domain (0 .. int4 max), not a magic ceiling; the relation is bounded by the adapter', () => {
  const withBounds = (min, max) => {
    const e = syntheticEnvelope();
    e.modifiers[1] = { ...e.modifiers[1], min_select: min, max_select: max };
    return e;
  };
  for (const [min, max] of [[0, null], [0, 0], [1, 1], [1000, 1000], [1001, 1001], [0, 2147483647], [2147483647, null]]) {
    const ok = decodeStorefrontMenu(withBounds(min, max));
    assert.equal(ok.modifiers[1].min_select, min);
    assert.equal(ok.modifiers[1].max_select, max);
  }
  // outside the storage domain: negative, non-integer, above int4, string
  for (const [min, max] of [[-1, null], [0, -1], [1.5, null], [0, 2147483648], [2147483648, null], ['1', null], [0, '2']]) {
    assert.throws(() => decodeStorefrontMenu(withBounds(min, max)), EnvelopeError, `${min}/${max}`);
  }
  // a legally stored large maximum keeps the storefront up and reaches the group as its max
  const big = adaptStorefront(decodeStorefrontMenu(withBounds(0, 5000)), ORIGIN);
  assert.equal(big.groups.find((g) => g.id === SYNTH_IDS.extras).max, 5000);
  // an unsatisfiable pair (min above a bounded max) drops THAT group only - bounded, never the whole storefront
  const impossible = adaptStorefront(decodeStorefrontMenu(withBounds(3, 2)), ORIGIN);
  assert.equal(impossible.groups.some((g) => g.id === SYNTH_IDS.extras), false, 'the impossible group is dropped');
  assert.equal(impossible.view.items.length, 3, 'the items still render');
  assert.deepEqual(impossible.view.items[0].groupIds, [SYNTH_IDS.weight], 'the burger keeps its satisfiable group');
  // min <= max (min 2, max 3) is a normal multi group; single ignores any max
  const normal = adaptStorefront(decodeStorefrontMenu(withBounds(2, 3)), ORIGIN);
  assert.deepEqual([normal.groups.find((g) => g.id === SYNTH_IDS.extras).max, normal.groups.find((g) => g.id === SYNTH_IDS.extras).required], [3, true]);
  const singleEnvelope = syntheticEnvelope();
  singleEnvelope.modifiers[0] = { ...singleEnvelope.modifiers[0], max_select: 5000, min_select: 7 };
  const single = adaptStorefront(decodeStorefrontMenu(singleEnvelope), ORIGIN).groups.find((g) => g.id === SYNTH_IDS.weight);
  assert.equal(single.single, true);
  assert.equal(Object.hasOwn(single, 'max'), false, 'a single-choice group never carries a max');
});

test('nextOpenParts expresses the next opening instant on the restaurant wall clock, or null when it cannot', () => {
  assert.deepEqual(nextOpenParts('2026-09-27T07:00:00+00:00', 'Asia/Jerusalem'), { weekday: 0, time: '10:00' }, 'Sunday 10:00 IDT');
  assert.deepEqual(nextOpenParts('2026-09-30T15:00:00Z', 'Asia/Jerusalem'), { weekday: 3, time: '18:00' }, 'Wednesday 18:00 IDT');
  assert.deepEqual(nextOpenParts('2026-12-31T22:00:00Z', 'Asia/Jerusalem'), { weekday: 5, time: '00:00' }, 'midnight local (Friday 2027-01-01) renders 00:00, never 24:00');
  assert.equal(nextOpenParts(null, 'Asia/Jerusalem'), null);
  assert.equal(nextOpenParts('not-a-date', 'Asia/Jerusalem'), null);
  assert.equal(nextOpenParts('2026-09-27T07:00:00+00:00', 'Not/AZone'), null, 'an unknown zone yields null, never a fabricated time');
});

// ------------------------------------------------------------------ adapter

test('the adapter maps the envelope onto the fixture shape with the packet §3 rules', () => {
  const r = adaptStorefront(decodeStorefrontMenu(syntheticEnvelope()), ORIGIN);
  const { tenant, categories, items, modules } = r.view;
  assert.equal(tenant.slug, 'sf-synth-a');
  assert.equal(tenant.displayName, 'Synth Alpha <script>alert(1)</script>', 'tenant text is DATA; React escapes it at render');
  assert.equal(tenant.service.orderingEnabled, false);
  assert.equal(tenant.service.deliveryEnabled, false);
  assert.equal(tenant.service.deliveryFromMinor, 0);
  assert.equal(tenant.heroImage, null, 'no hero published -> null (D11)');
  assert.equal(tenant.brand.logo, null);
  assert.equal(tenant.currency, 'ILS');
  assert.deepEqual(tenant.hours, { opens: '00:00', closes: '00:00', nextOpen: null, nextOpenAt: null, timezone: 'Asia/Jerusalem' });
  assert.equal(r.source, 'live');
  // closed with no window today: opens/closes empty, the next opening instant carried as the only forward pointer,
  // ALSO expressed on the restaurant's own wall clock (Sunday 2026-09-27 10:00 Asia/Jerusalem) for the UI copy
  const closed = adaptStorefront(decodeStorefrontMenu(syntheticEnvelope({ hours: { opens: null, closes: null, open_now: false, next_open: '2026-09-27T07:00:00+00:00' }, service: { state: 'closed' } })), ORIGIN);
  assert.deepEqual(closed.view.tenant.hours, { opens: '', closes: '', nextOpen: '2026-09-27T07:00:00+00:00', nextOpenAt: { weekday: 0, time: '10:00' }, timezone: 'Asia/Jerusalem' });
  assert.equal(r.preset, 'dark');
  assert.equal(r.taxRateBp, 1800);
  assert.equal(r.menuVersion, '3.1758600000');
  assert.deepEqual(r.zones, [], 'no zone storage exists: delivery is off and the city list is empty');
  // categories: only populated ones, icon from the registry, empty category dropped
  assert.deepEqual(categories.map((c) => c.id), [SYNTH_IDS.catFood]);
  assert.equal(categories[0].iconPath, iconPathFor('burger'));
  assert.equal(categories[0].image, null);
  assert.equal(categories[0].blurb, null);
  // items: the orphan (unknown category) dropped; tags -> signature / badge; sold out mapped
  assert.deepEqual(items.map((i) => i.name), ['Synth Burger', 'Synth Cola', 'Synth Sold Out']);
  const burger = items[0];
  assert.equal(burger.signature, true);
  assert.equal(burger.badge, 'new');
  assert.equal(burger.featured, false, 'featured has no storage and is never claimed');
  assert.equal(burger.soldOut, false);
  assert.equal(burger.image, `${ORIGIN}${SYNTH_MEDIA_PATH}`);
  assert.equal(items[2].soldOut, true);
  assert.equal(items[1].badge, null);
  // groups: the empty group dropped, so the burger offers two; max omitted at 0
  assert.deepEqual(burger.groupIds, [SYNTH_IDS.weight, SYNTH_IDS.extras]);
  assert.equal(burger.hasOptions, true);
  assert.equal(items[1].hasOptions, false);
  assert.deepEqual(r.groups.map((g) => g.id), [SYNTH_IDS.weight, SYNTH_IDS.extras]);
  const weight = r.groups[0];
  assert.equal(weight.required, true);
  assert.equal(weight.single, true);
  assert.equal(weight.max, undefined);
  const extras = r.groups[1];
  assert.equal(extras.single, false);
  assert.equal(extras.required, false);
  assert.equal(Object.hasOwn(extras, 'max'), false, 'max_select 0 -> no max (the sheet would refuse every selection)');
  assert.equal(extras.removal, undefined);
  assert.deepEqual(weight.options.map((o) => [o.name, o.priceDeltaMinor]), [['Synth Classic', 0], ['Synth Double', 1500]]);
  // modules: campaign falls back to the tagline with an EMPTY subline; everything else off
  assert.deepEqual(modules.campaign, { title: 'SYNTH TAGLINE', subline: '' });
  assert.equal(modules.announcement, null);
  assert.equal(modules.promo, null);
  assert.equal(modules.story, null);
  assert.deepEqual(modules.popular, { enabled: true, ready: false }, 'a popular item exists, but no rank is ever claimed');
  // the presentational cart carries nothing
  assert.deepEqual(r.view.cart, { lines: [], itemCount: 0, subtotalMinor: 0, taxMinor: 0, totalMinor: 0, taxRateBp: 1800 });
});

test('required is is_required OR min_select >= 1; a group without options is dropped; the campaign falls back to the name', () => {
  const r = adaptStorefront(decodeStorefrontMenu(syntheticEnvelope({
    restaurant: { tagline: null },
    modifiers: [
      { id: SYNTH_IDS.weight, item_id: SYNTH_IDS.burger, name: 'Min1', selection_type: 'multiple', min_select: 1, max_select: 3, is_required: false, display_order: 0 },
    ],
    modifier_options: [
      { id: SYNTH_IDS.classic, modifier_id: SYNTH_IDS.weight, name: 'A', price_delta_minor: 0, display_order: 0 },
    ],
  })), ORIGIN);
  assert.equal(r.groups.length, 1);
  assert.equal(r.groups[0].required, true);
  assert.equal(r.groups[0].max, 3);
  assert.deepEqual(r.view.modules.campaign, { title: 'Synth Alpha <script>alert(1)</script>', subline: '' });
});

test('the live menu prices a cart on ITS groups and ITS rate (integer minor units end to end)', () => {
  const r = adaptStorefront(decodeStorefrontMenu(syntheticEnvelope({ tax: { rate_bp: 1700 } })), ORIGIN);
  const cart = addLine({ schema: 1, slug: 'sf-synth-a', menuVersion: r.menuVersion, lines: [] },
    { itemId: SYNTH_IDS.burger, qty: 2, selections: { [SYNTH_IDS.weight]: [SYNTH_IDS.double], [SYNTH_IDS.extras]: [SYNTH_IDS.cheese] }, note: '' });
  const summary = summarise(cart, r.view.items, r.groups);
  assert.equal(summary.lines[0].unitMinor, 4000 + 1500 + 600);
  assert.equal(summary.subtotalMinor, 12200);
  assert.deepEqual(summary.lines[0].optionNames, ['Synth Double', 'Synth Cheese']);
  const q = buildQuote({ cart, items: r.view.items, groups: r.groups, service: 'pickup', zone: null, taxRateBp: r.taxRateBp });
  assert.equal(q.taxRateBp, 1700);
  assert.equal(q.taxMinor, Math.round((12200 * 1700) / 10000));
  assert.equal(q.taxMinor, 2074);
  assert.equal(q.totalMinor, 14274);
  for (const v of [q.subtotalMinor, q.taxMinor, q.totalMinor]) assert.ok(Number.isInteger(v));
});

test('a tenant with tax off prices with rate 0 and no tax', () => {
  const r = adaptStorefront(decodeStorefrontMenu(syntheticEnvelope({ tax: { enabled: false, rate_bp: 1800, mode: 'exclusive' } })), ORIGIN);
  assert.equal(r.taxRateBp, 0, 'a disabled tax is rate 0 whatever the stored bp says');
  const cart = addLine({ schema: 1, slug: 'sf-synth-a', menuVersion: r.menuVersion, lines: [] }, { itemId: SYNTH_IDS.cola, qty: 1, selections: {}, note: '' });
  const q = buildQuote({ cart, items: r.view.items, groups: r.groups, service: 'pickup', zone: null, taxRateBp: r.taxRateBp });
  assert.equal(q.taxMinor, 0);
  assert.equal(q.totalMinor, 1000);
});

test('media URLs are accepted ONLY as public derivative paths under the configured origin', () => {
  assert.equal(mediaUrl(SYNTH_MEDIA_PATH, ORIGIN), `${ORIGIN}${SYNTH_MEDIA_PATH}`);
  for (const bad of [
    null,
    'https://evil.example/x.webp',
    '/storage/v1/object/public/menu-images/orgA/x.jpg',
    '/storage/v1/object/sign/storefront-media/0123456789abcdef0123456789abcdef/' + 'a'.repeat(64) + '.webp?token=1',
    '/storage/v1/object/public/storefront-media/../x.webp',
    '/storage/v1/object/public/storefront-media/0123456789abcdef0123456789abcdef/' + 'a'.repeat(64) + '.png',
    'javascript:alert(1)',
  ]) {
    assert.equal(mediaUrl(bad, ORIGIN), null, `must reject ${bad}`);
  }
});

test('the icon registry mirrors the 49 Dashboard keys and falls back to the menu outline', () => {
  assert.equal(CATEGORY_ICON_KEYS.length, 49);
  assert.equal(DEFAULT_ICON_KEY, 'menu');
  assert.equal(iconPathFor(null), iconPathFor('menu'));
  assert.equal(iconPathFor(undefined), iconPathFor('menu'));
  assert.equal(iconPathFor('not-a-key'), iconPathFor('menu'));
  assert.equal(iconPathFor('__proto__'), iconPathFor('menu'), 'a prototype key is not a registry key');
  assert.equal(iconPathFor('constructor'), iconPathFor('menu'));
  assert.notEqual(iconPathFor('burger'), iconPathFor('menu'));
  for (const key of CATEGORY_ICON_KEYS) assert.match(iconPathFor(key), /^M[MmLlHhVvCcSsQqTtAaZz0-9 .,-]+$/);
});

// ------------------------------------------------------------- source switch

test('the source switch: explicit fixture / live everywhere; the fixture default exists OUTSIDE a provider context only', () => {
  // non-provider (a developer machine): absent / empty -> fixture; explicit values honoured; anything else refused
  assert.equal(isProviderContext({}), false);
  assert.equal(sourceMode({}), 'fixture');
  assert.equal(sourceMode({ STOREFRONT_SOURCE: '' }), 'fixture');
  assert.equal(sourceMode({ STOREFRONT_SOURCE: 'fixture' }), 'fixture');
  assert.equal(sourceMode({ STOREFRONT_SOURCE: 'live' }), 'live');
  assert.equal(isLiveMode({ STOREFRONT_SOURCE: 'live' }), true);
  assert.throws(() => sourceMode({ STOREFRONT_SOURCE: 'demo' }), /must be exactly "fixture" or "live"/);
  assert.throws(() => sourceMode({ STOREFRONT_SOURCE: ' ' }), /must be exactly/);
  assert.throws(() => sourceMode({ STOREFRONT_SOURCE: 'Live' }), /must be exactly/);
  assert.equal(storefrontSource({}).kind, 'fixture');
  assert.equal(storefrontSource({ STOREFRONT_SOURCE: 'live' }).kind, 'live');
  assert.deepEqual(storefrontSource({ STOREFRONT_SOURCE: 'live' }).staticSlugs(), [], 'nothing is pre-rendered live');
  // NODE_ENV alone never makes a provider context (it is production for every next build)
  assert.equal(isProviderContext({ NODE_ENV: 'production' }), false);
  assert.equal(sourceMode({ NODE_ENV: 'production' }), 'fixture');
});

test('FAIL CLOSED (review finding A): in a provider context the source must be stated exactly; nothing silently selects the fixture', () => {
  const PROVIDER = [{ VERCEL: '1' }, { VERCEL: '1', VERCEL_ENV: 'production' }, { VERCEL: '1', VERCEL_ENV: 'preview' }, { VERCEL_ENV: 'production' }];
  for (const ctx of PROVIDER) {
    assert.equal(isProviderContext(ctx), true, JSON.stringify(ctx));
    // absent, empty, whitespace-only, misspelled / wrong case
    assert.throws(() => sourceMode({ ...ctx }), /must be exactly "fixture" or "live" in a provider \(VERCEL\) build or runtime, got undefined/, 'absent ' + JSON.stringify(ctx));
    assert.throws(() => sourceMode({ ...ctx, STOREFRONT_SOURCE: '' }), /in a provider .* got ""/, 'empty');
    assert.throws(() => sourceMode({ ...ctx, STOREFRONT_SOURCE: '   ' }), /in a provider .* got "   "/, 'whitespace-only');
    assert.throws(() => sourceMode({ ...ctx, STOREFRONT_SOURCE: 'lvie' }), /in a provider .* got "lvie"/, 'misspelled');
    assert.throws(() => sourceMode({ ...ctx, STOREFRONT_SOURCE: 'Live' }), /in a provider/, 'wrong case');
    assert.throws(() => sourceMode({ ...ctx, STOREFRONT_SOURCE: ' live' }), /in a provider/, 'padded');
    assert.throws(() => storefrontSource({ ...ctx }), /in a provider/, 'the switch itself throws, so generateStaticParams and every request throw');
    // explicit values are honoured in a provider context
    assert.equal(sourceMode({ ...ctx, STOREFRONT_SOURCE: 'fixture' }), 'fixture');
    assert.equal(sourceMode({ ...ctx, STOREFRONT_SOURCE: 'live' }), 'live');
    assert.equal(storefrontSource({ ...ctx, STOREFRONT_SOURCE: 'fixture' }).kind, 'fixture');
    assert.equal(storefrontSource({ ...ctx, STOREFRONT_SOURCE: 'live' }).kind, 'live');
  }
  // and there is no live -> fixture fallback of any kind in the live source (the adapter throws; see the transport test below)
  assert.equal(typeof liveStorefrontSource, 'function');
});

test('the request-route fixture applies the SAME source rule (a provider build without a source cannot prerender the demo ref)', async () => {
  const { requestRefs } = await import('../src/source/request-fixture.ts');
  const saved = { VERCEL: process.env.VERCEL, VERCEL_ENV: process.env.VERCEL_ENV, STOREFRONT_SOURCE: process.env.STOREFRONT_SOURCE };
  try {
    delete process.env.VERCEL; delete process.env.VERCEL_ENV; delete process.env.STOREFRONT_SOURCE;
    assert.equal(requestRefs().length, 1, 'non-provider default: the one demo ref');
    process.env.STOREFRONT_SOURCE = 'live';
    assert.deepEqual(requestRefs(), [], 'live: no request route');
    delete process.env.STOREFRONT_SOURCE; process.env.VERCEL = '1';
    assert.throws(() => requestRefs(), /in a provider/, 'provider without a source: throws, never the demo ref');
    process.env.STOREFRONT_SOURCE = 'fixture';
    assert.equal(requestRefs().length, 1, 'provider with an explicit fixture: the demo ref');
  } finally {
    for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  }
});

test('the fixture source resolves the canonical tenant, keeps its groups / zones / rate, and hides demo slugs outside an evidence build', async () => {
  const saved = process.env.SF_EVIDENCE_ROUTES;
  delete process.env.SF_EVIDENCE_ROUTES;
  try {
    const canonical = await fixtureStorefrontSource.getStorefront('maps-burger');
    assert.ok(canonical);
    assert.equal(canonical.source, 'fixture', 'the fixture resolution names its source (the ?fx= tokens are honoured for it only)');
    assert.equal(canonical.view.tenant.service.orderingEnabled, true, 'the fixture demo still orders');
    assert.equal(canonical.taxRateBp, 1800);
    assert.equal(canonical.menuVersion, 'mb-1');
    assert.ok(canonical.groups.length >= 5 && canonical.zones.length >= 4);
    assert.equal(await fixtureStorefrontSource.getStorefront('demo-closed'), null, 'a demo slug is an evidence route only');
    assert.equal(await fixtureStorefrontSource.getStorefront('no-such-tenant'), null);
    assert.deepEqual([...fixtureStorefrontSource.staticSlugs()], ['maps-burger']);
    process.env.SF_EVIDENCE_ROUTES = '1';
    assert.ok(await fixtureStorefrontSource.getStorefront('demo-closed'), 'an evidence build serves the demo slugs');
  } finally {
    if (saved === undefined) delete process.env.SF_EVIDENCE_ROUTES;
    else process.env.SF_EVIDENCE_ROUTES = saved;
  }
});

// ------------------------------------------------------------------- client

test('the client builds exactly the PostgREST RPC request with the anon key on the server side only', () => {
  const { url, init } = storefrontMenuRequest(CONFIG, 'sf-synth-a');
  assert.equal(url, `${ORIGIN}/rest/v1/rpc/storefront_menu`);
  assert.equal(init.method, 'POST');
  assert.equal(init.headers.apikey, CONFIG.anonKey);
  assert.equal(init.headers.Authorization, `Bearer ${CONFIG.anonKey}`);
  assert.equal(init.body, JSON.stringify({ p_slug: 'sf-synth-a' }));
  assert.ok(init.signal instanceof AbortSignal, 'the read is bounded by a timeout');
});

test('misconfiguration throws - it never falls back to the fixture', () => {
  assert.throws(() => liveConfig({}), /STOREFRONT_SUPABASE_URL/);
  assert.throws(() => liveConfig({ STOREFRONT_SUPABASE_URL: 'not a url', STOREFRONT_SUPABASE_ANON_KEY: 'k'.repeat(30) }), /STOREFRONT_SUPABASE_URL/);
  assert.throws(() => liveConfig({ STOREFRONT_SUPABASE_URL: 'https://x.supabase.co/rest', STOREFRONT_SUPABASE_ANON_KEY: 'k'.repeat(30) }), /no path/);
  assert.throws(() => liveConfig({ STOREFRONT_SUPABASE_URL: 'https://x.supabase.co', STOREFRONT_SUPABASE_ANON_KEY: 'short' }), /ANON_KEY/);
  const cfg = liveConfig({ STOREFRONT_SUPABASE_URL: ' https://x.supabase.co ', STOREFRONT_SUPABASE_ANON_KEY: 'k'.repeat(30) });
  assert.deepEqual(cfg, { url: 'https://x.supabase.co', anonKey: 'k'.repeat(30) });
});

test('the runtime guard refuses to run where a window exists', async () => {
  globalThis.window = {};
  try {
    await assert.rejects(() => fetchStorefrontMenu('sf-synth-a', CONFIG), /server-only/);
  } finally {
    delete globalThis.window;
  }
});

test('the live source: not_found -> null, another failure -> throw, transport error -> throw, slug mismatch -> throw', async () => {
  const withFetch = async (impl, fn) => {
    const real = globalThis.fetch;
    globalThis.fetch = impl;
    try { return await fn(); } finally { globalThis.fetch = real; }
  };
  const respond = (status, body) => async () => ({ ok: status >= 200 && status < 300, status, json: async () => body });
  const source = liveStorefrontSource(CONFIG);
  assert.equal(await withFetch(respond(200, NOT_FOUND_ENVELOPE), () => source.getStorefront('sf-synth-a')), null);
  const resolved = await withFetch(respond(200, syntheticEnvelope()), () => source.getStorefront('sf-synth-a'));
  const serialised = JSON.stringify(resolved);
  assert.ok(resolved && !serialised.includes(CONFIG.anonKey) && !serialised.includes('/rest/v1'), 'the resolution (serialised into every document) never carries the key or the API path');
  await withFetch(respond(200, PAYLOAD_LIMIT_ENVELOPE), () => assert.rejects(() => source.getStorefront('sf-synth-a'), /payload_limit/));
  await withFetch(respond(500, {}), () => assert.rejects(() => source.getStorefront('sf-synth-a'), /HTTP 500/));
  await withFetch(async () => { throw new Error('ECONNRESET'); }, () => assert.rejects(() => source.getStorefront('sf-synth-a'), /ECONNRESET/));
  await withFetch(respond(200, syntheticEnvelope()), () => assert.rejects(() => source.getStorefront('sf-synth-b'), /different slug/));
  await withFetch(respond(200, { ok: true, garbage: 1 }), () => assert.rejects(() => source.getStorefront('sf-synth-a'), EnvelopeError));
  const good = await withFetch(respond(200, syntheticEnvelope()), () => source.getStorefront('sf-synth-a'));
  assert.equal(good.view.tenant.displayName, 'Synth Alpha <script>alert(1)</script>');
  // an invalid slug never reaches the network at all
  let called = 0;
  assert.equal(await withFetch(async () => { called++; }, () => source.getStorefront('Bad Slug')), null);
  assert.equal(called, 0);
});
