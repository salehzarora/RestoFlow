import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';

const { decodeStorefrontMenuV4 } = await import('../src/source/live/decodeContentV1.ts');
const { EnvelopeError } = await import('../src/source/live/decode.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { buildCinematicTheme } = await import('../src/theme/buildCinematicTheme.ts');
const { buildTheme, AA, AA_LARGE } = await import('../src/theme/buildTheme.ts');
const { contrast, inkOn } = await import('../src/theme/contrast.ts');

// Public identity for the existing origin guard. No network calls are made.
const ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const withAppearance = appearance => {
  const envelope = syntheticV4Envelope();
  envelope.content_v1.appearance = appearance;
  return envelope;
};

test('old v4 content remains exact and optional appearance never changes catalog or order data', () => {
  const old = decodeStorefrontMenuV4(syntheticV4Envelope());
  assert.equal(Object.hasOwn(old.content_v1, 'appearance'), false);
  const before = adaptStorefront(old, ORIGIN);
  assert.equal(Object.hasOwn(before.view.tenant.brand, 'text'), false);
  const decoded = decodeStorefrontMenuV4(withAppearance({ text_color: '#AbC123', button_text_color: '#000000' }));
  assert.deepEqual(decoded.content_v1.appearance, { text_color: '#abc123', button_text_color: '#000000' });
  const after = adaptStorefront(decoded, ORIGIN);
  const { text, buttonText, ...oldBrand } = after.view.tenant.brand;
  assert.equal(text, '#abc123');
  assert.equal(buttonText, '#000000');
  assert.deepEqual(oldBrand, before.view.tenant.brand);
  assert.deepEqual({ ...after, view: { ...after.view, tenant: before.view.tenant } }, before);
  const cleared = adaptStorefront(decodeStorefrontMenuV4(withAppearance({ text_color: null, button_text_color: null })), ORIGIN);
  assert.equal(cleared.view.tenant.brand.text, null);
  assert.equal(cleared.view.tenant.brand.buttonText, null);
});

test('appearance is a closed pair of nullable full HEX colours and rejects CSS or malformed payloads', () => {
  for (const value of [null, [], false, {}, { text_color: '#ffffff' }, { text_color: null, button_text_color: null, css: 'color:red' }]) {
    assert.throws(() => decodeStorefrontMenuV4(withAppearance(value)), EnvelopeError);
  }
  for (const value of ['#abc', '#abcdef\n', ' #abcdef', '#abcdef00', 'white', 'var(--tx)', 'url(https://example.invalid)', 123, undefined]) {
    for (const key of ['text_color', 'button_text_color']) {
      assert.throws(() => decodeStorefrontMenuV4(withAppearance({ text_color: null, button_text_color: null, [key]: value })), EnvelopeError);
    }
  }
  for (const value of ['#000000', '#FFFFFF', '#f0aB76']) {
    assert.equal(decodeStorefrontMenuV4(withAppearance({ text_color: value, button_text_color: value })).content_v1.appearance.text_color, value.toLowerCase());
  }
  const unknown = withAppearance({ text_color: null, button_text_color: null });
  unknown.content_v1.extra = null;
  assert.throws(() => decodeStorefrontMenuV4(unknown), EnvelopeError);
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
  for (const key of ['tx', 'tx2', 'tx3', 'onhero', 'onhero2', 'onDock2']) assert.equal(custom[key], '#123abc');
  assert.equal(custom.onacc, '#112233');
  assert.deepEqual(buildCinematicTheme({ ...brand, text: 'var(--fake)', buttonText: '#fff\n' }), baseline);
});
