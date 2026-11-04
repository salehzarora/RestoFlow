import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';

const { decodeStorefrontMenuV4, decodeStorefrontMenuV5 } = await import('../src/source/live/decodeContentV1.ts');
const { EnvelopeError } = await import('../src/source/live/decode.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { buildCinematicTheme } = await import('../src/theme/buildCinematicTheme.ts');
const { buildTheme, AA, AA_LARGE } = await import('../src/theme/buildTheme.ts');
const { contrast, inkOn } = await import('../src/theme/contrast.ts');
const { storefrontFont } = await import('../src/theme/fonts.ts');
const { menuBackground } = await import('../src/ui/storefront/home/menuBackground.ts');

// Public identity for the existing origin guard. No network calls are made.
const ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const withAppearance = appearance => {
  const envelope = syntheticV4Envelope();
  envelope.content_v1.appearance = appearance;
  return envelope;
};

test('v5 accepts legacy content and optional appearance never changes catalog or order data', () => {
  const old = decodeStorefrontMenuV5(syntheticV4Envelope());
  assert.equal(Object.hasOwn(old.content_v1, 'appearance'), false);
  const before = adaptStorefront(old, ORIGIN);
  assert.equal(Object.hasOwn(before.view.tenant.brand, 'text'), false);
  const decoded = decodeStorefrontMenuV5(withAppearance({ text_color: '#AbC123', button_text_color: '#000000' }));
  assert.deepEqual(decoded.content_v1.appearance, { text_color: '#abc123', button_text_color: '#000000' });
  const after = adaptStorefront(decoded, ORIGIN);
  const { text, buttonText, ...oldBrand } = after.view.tenant.brand;
  assert.equal(text, '#abc123');
  assert.equal(buttonText, '#000000');
  assert.deepEqual(oldBrand, before.view.tenant.brand);
  assert.deepEqual({ ...after, view: { ...after.view, tenant: before.view.tenant } }, before);
  const cleared = adaptStorefront(decodeStorefrontMenuV5(withAppearance({ text_color: null, button_text_color: null })), ORIGIN);
  assert.equal(cleared.view.tenant.brand.text, null);
  assert.equal(cleared.view.tenant.brand.buttonText, null);
});

test('strict legacy v4 rejects every appearance extension while v5 accepts only its contract', () => {
  const baseline = syntheticV4Envelope();
  assert.deepEqual(decodeStorefrontMenuV4(baseline), decodeStorefrontMenuV5(baseline));
  for (const appearance of [
    { text_color: '#ffffff', button_text_color: '#121212', font_family: 'rubik' },
    { text_color: null, button_text_color: null },
    { text_color: null, button_text_color: null, menu_background_url: null, menu_background_dim: null },
  ]) {
    const raw = withAppearance(appearance);
    assert.throws(() => decodeStorefrontMenuV4(raw), EnvelopeError);
    assert.deepEqual(decodeStorefrontMenuV5(raw).content_v1.appearance, appearance);
    delete raw.content_v1.appearance;
    assert.deepEqual(decodeStorefrontMenuV4(raw), decodeStorefrontMenuV4(baseline));
  }
});

test('appearance is a closed pair of nullable full HEX colours and rejects CSS or malformed payloads', () => {
  for (const value of [null, [], false, {}, { text_color: '#ffffff' }, { text_color: null, button_text_color: null, css: 'color:red' }]) {
    assert.throws(() => decodeStorefrontMenuV5(withAppearance(value)), EnvelopeError);
  }
  for (const value of ['#abc', '#abcdef\n', ' #abcdef', '#abcdef00', 'white', 'var(--tx)', 'url(https://example.invalid)', 123, undefined]) {
    for (const key of ['text_color', 'button_text_color']) {
      assert.throws(() => decodeStorefrontMenuV5(withAppearance({ text_color: null, button_text_color: null, [key]: value })), EnvelopeError);
    }
  }
  for (const value of ['#000000', '#FFFFFF', '#f0aB76']) {
    assert.equal(decodeStorefrontMenuV5(withAppearance({ text_color: value, button_text_color: value })).content_v1.appearance.text_color, value.toLowerCase());
  }
  const unknown = withAppearance({ text_color: null, button_text_color: null });
  unknown.content_v1.extra = null;
  assert.throws(() => decodeStorefrontMenuV5(unknown), EnvelopeError);
});

test('cinematic defaults retain all valid brand colours and automatic control contrast', () => {
  for (const primary of ['#ffffff', '#ffef00', '#3454ff', '#111111', '#151513', '#777777', '#747474']) {
    for (const accent of ['#000000', '#ffffff', '#e4ad83', '#ff00ff']) {
      const theme = buildCinematicTheme({ primary, accent });
      assert.equal(theme.hero, primary);
      assert.equal(theme.bg, primary, 'dashboard background colour must control the page canvas');
      assert.equal(theme.acc, accent);
      assert.equal(theme.cta, accent);
      assert.equal(theme.onacc, inkOn(accent));
      assert.ok(contrast(theme.tx, theme.bg) >= AA);
      for (const surface of [theme.bg, theme.sf, theme.sf2]) for (const key of ['tx', 'tx2', 'tx3']) assert.ok(contrast(theme[key], surface) >= AA);
      assert.ok(contrast(theme.acct, theme.sf) >= AA);
      assert.ok(contrast(theme.accOnSelection, theme.accs) >= AA);
      for (const surface of [theme.bg, theme.sf, theme.sf2, theme.accs]) assert.ok(contrast(theme.ring, surface) >= AA_LARGE);
      const baseline = buildTheme('dark', { primary, accent });
      for (const key of ['ok', 'okbg', 'warn', 'warnbg', 'bad', 'badbg', 'badText', 'onBad', 'info', 'infobg']) assert.equal(theme[key], baseline[key]);
    }
  }
  const fallback = buildCinematicTheme({ primary: 'not-a-colour', accent: '#e4ad83' });
  assert.equal(fallback.bg, '#151513');
  assert.equal(fallback.tx, '#f7f2ea');
});

test('explicit appearance remains exact, including owner-chosen low-contrast colours; null restores defaults', () => {
  const brand = { primary: '#ffffff', accent: '#112233' };
  const baseline = buildCinematicTheme(brand);
  assert.deepEqual(buildCinematicTheme({ ...brand, text: null, buttonText: null }), baseline);
  const custom = buildCinematicTheme({ ...brand, text: '#123AbC', buttonText: '#112233' });
  for (const key of ['tx', 'tx2', 'tx3', 'onhero2', 'onDock2']) assert.equal(custom[key], '#123abc');
  assert.equal(custom.onacc, '#112233');
  assert.equal(custom.onhero, '#112233');
  assert.deepEqual(buildCinematicTheme({ ...brand, text: 'var(--fake)', buttonText: '#fff\n' }), baseline);
});

test('font selection is optional, allowlisted and travels through the public adapter without changing menu authority', () => {
  const colours = { text_color: '#fff4e6', button_text_color: null };
  const baseline = adaptStorefront(decodeStorefrontMenuV5(withAppearance(colours)), ORIGIN);
  assert.equal(Object.hasOwn(baseline.view.tenant.brand, 'fontFamily'), false);
  for (const font of ['rubik', 'alexandria', 'system', null]) {
    const decoded = decodeStorefrontMenuV5(withAppearance({ ...colours, font_family: font }));
    assert.equal(decoded.content_v1.appearance.font_family, font);
    const resolution = adaptStorefront(decoded, ORIGIN);
    assert.equal(resolution.view.tenant.brand.fontFamily, font);
    assert.deepEqual({ ...resolution, view: { ...resolution.view, tenant: baseline.view.tenant } }, baseline);
    assert.equal(buildCinematicTheme(resolution.view.tenant.brand).font, storefrontFont(font));
  }
  for (const font of ['', 'Arial', 'Alexandria', 'rubik ', 'url(https://example.invalid/font)', 'var(--unsafe)', 1, true, [], {}, undefined]) {
    assert.throws(() => decodeStorefrontMenuV5(withAppearance({ ...colours, font_family: font })), EnvelopeError);
  }
});

test('all font tokens use fixed local stacks and missing or null choice restores Rubik', () => {
  const brand = { primary: '#151513', accent: '#f2ad79' };
  const original = buildCinematicTheme(brand);
  assert.deepEqual(buildCinematicTheme({ ...brand, fontFamily: null }), original);
  assert.deepEqual(buildCinematicTheme({ ...brand, fontFamily: 'rubik' }), original);
  assert.match(buildCinematicTheme({ ...brand, fontFamily: 'alexandria' }).font, /^"SF Alexandria", var\(--sf-font-latin/);
  assert.match(buildTheme('dark', { ...brand, fontFamily: 'system' }).font, /^system-ui,/);
  assert.equal(storefrontFont('untrusted; background: url(https://example.invalid)'), original.font);
});

test('independent menu background selects, replaces and clears without changing hero or catalog', () => {
  const path = hash => '/storage/v1/object/public/storefront-media/' + 'a'.repeat(32) + '/' + hash.repeat(64) + '.webp';
  const envelope = syntheticV4Envelope();
  envelope.restaurant.hero_url = path('b');
  const original = adaptStorefront(decodeStorefrontMenuV5(envelope), ORIGIN);
  assert.deepEqual(menuBackground(original.view.tenant), { kind: 'legacy', image: ORIGIN + path('b'), dim: null });
  for (const [image, dim, expectedDim] of [[path('c'), 0, 0], [path('d'), 80, 80], [path('c'), null, 15], [null, 55, null]]) {
    const next = structuredClone(envelope);
    next.content_v1.appearance = { text_color: '#fff4e6', button_text_color: '#131313', font_family: 'alexandria', menu_background_url: image, menu_background_dim: dim };
    const resolved = adaptStorefront(decodeStorefrontMenuV5(next), ORIGIN);
    assert.equal(resolved.view.tenant.heroImage, original.view.tenant.heroImage);
    assert.deepEqual(resolved.view.items, original.view.items);
    assert.deepEqual(resolved.groups, original.groups);
    assert.deepEqual(resolved.view.tenant.service, original.view.tenant.service);
    assert.deepEqual(menuBackground(resolved.view.tenant), { kind: image ? 'custom' : 'legacy', image: image ? ORIGIN + image : original.view.tenant.heroImage, dim: expectedDim });
    assert.equal(buildCinematicTheme(resolved.view.tenant.brand).tx, '#fff4e6');
    assert.equal(buildCinematicTheme(resolved.view.tenant.brand).onacc, '#131313');
  }
  assert.equal(Object.hasOwn(original.view.tenant, 'menuBackgroundImage'), false);
  assert.equal(Object.hasOwn(original.view.tenant, 'menuBackgroundDim'), false);
});

test('menu background wire fields reject arbitrary URLs, private IDs and invalid dim values', () => {
  const colours = { text_color: null, button_text_color: null };
  for (const image of ['', 'https://example.com/a.webp', 'javascript:alert(1)', '/cinematic-preview/menu-background.webp', 1, false, {}]) {
    assert.throws(() => decodeStorefrontMenuV5(withAppearance({ ...colours, menu_background_url: image })), EnvelopeError);
  }
  assert.throws(() => decodeStorefrontMenuV5(withAppearance({ ...colours, menu_background_media_id: null })), EnvelopeError);
  for (const dim of [-1, 81, 15.5, '15', false, [], {}, undefined, Infinity]) {
    assert.throws(() => decodeStorefrontMenuV5(withAppearance({ ...colours, menu_background_dim: dim })), EnvelopeError);
  }
  for (const dim of [0, 15, 80, null]) {
    assert.equal(decodeStorefrontMenuV5(withAppearance({ ...colours, menu_background_dim: dim })).content_v1.appearance.menu_background_dim, dim);
  }
});
