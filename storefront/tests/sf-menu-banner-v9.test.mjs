import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';
import { SYNTH_MEDIA_PATH } from './support/envelope.mjs';
const { EnvelopeError } = await import('../src/source/live/decode.ts');
const { decodeStorefrontMenuV8, decodeStorefrontMenuV9 } = await import('../src/source/live/decodeContentV1.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { fetchStorefrontMenu } = await import('../src/source/live/client.ts');
const origin = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const config = { url: origin, anonKey: 'SYNTHETIC_NOT_A_REAL_KEY' };
const fields = ['menu_banner_url', 'menu_banner_enabled', 'menu_intro_visible', 'menu_banner_focal_x', 'menu_banner_focal_y'];
function menu(banner = {}) {
  const raw = syntheticV4Envelope();
  raw.content_v1.appearance = { text_color: null, button_text_color: null, site_theme: 'light', ...banner };
  return raw;
}
const selection = { menu_banner_url: SYNTH_MEDIA_PATH, menu_banner_enabled: true, menu_intro_visible: false, menu_banner_focal_x: 20, menu_banner_focal_y: 75 };
const missing = v => ({ code: 'PGRST202', message: `Could not find the function public.storefront_menu_v${v}(p_slug) in the schema cache` });

test('v9 keeps absence exact and negotiates explicit null/boolean/focal values without old decoder leakage', () => {
  assert.deepEqual(decodeStorefrontMenuV9(menu()), decodeStorefrontMenuV8(menu()));
  for (const banner of [selection, Object.fromEntries(fields.map(k => [k, null])), { menu_intro_visible: false }]) {
    const raw = menu(banner); const before = structuredClone(raw);
    const decoded = decodeStorefrontMenuV9(raw);
    assert.deepEqual(raw, before, 'shared input not mutated');
    assert.deepEqual(Object.fromEntries(fields.filter(k => Object.hasOwn(banner, k)).map(k => [k, decoded.content_v1.appearance[k]])), banner);
    assert.throws(() => decodeStorefrontMenuV8(raw), EnvelopeError, 'old strict boundary rejects new keys');
  }
  assert.deepEqual(decodeStorefrontMenuV9({ ok: false, entity: 'storefront_menu', error: 'not_found' }), { ok: false, entity: 'storefront_menu', error: 'not_found' });
});

test('banner types, derivative origin paths, bounds and unknown keys fail closed', () => {
  for (const key of fields) {
    const invalid = key === 'menu_banner_url' ? [undefined, false, '', 'https://private.example/original.jpg', SYNTH_MEDIA_PATH + '\n']
      : key.includes('focal') ? [undefined, false, '50', -1, 101, .5, Infinity, [], {}]
        : [undefined, 'false', 'true', 0, 1, [], {}];
    for (const value of invalid) assert.throws(() => decodeStorefrontMenuV9(menu({ ...selection, [key]: value })), EnvelopeError, `${key}=${String(value)}`);
  }
  assert.throws(() => decodeStorefrontMenuV9(menu({ ...selection, menu_banner_media_id: 'private-id' })), EnvelopeError);
  assert.throws(() => decodeStorefrontMenuV9(menu({ ...selection, arbitrary: true })), EnvelopeError);
  const bad = menu(selection); delete bad.content_v1.appearance.text_color;
  assert.throws(() => decodeStorefrontMenuV9(bad), EnvelopeError);
});

test('adapter preserves every old field and carries independent defaults without selecting a banner', () => {
  const old = adaptStorefront(decodeStorefrontMenuV8(menu()), origin);
  assert.equal(Object.hasOwn(old.view.tenant, 'menuBanner'), false);
  const after = adaptStorefront(decodeStorefrontMenuV9(menu(selection)), origin);
  const { menuBanner, ...rest } = after.view.tenant;
  assert.deepEqual(rest, old.view.tenant);
  assert.deepEqual(menuBanner, { image: origin + SYNTH_MEDIA_PATH, enabled: true, showIntro: false, focalX: 20, focalY: 75 });
  assert.deepEqual(after.view.items, old.view.items); assert.equal(after.menuVersion, old.menuVersion);
  assert.deepEqual(adaptStorefront(decodeStorefrontMenuV9(menu({ menu_banner_url: null })), origin).view.tenant.menuBanner,
    { image: null, enabled: false, showIntro: true, focalX: 50, focalY: 50 });
});

test('v9 fallback after exact missing v11 and v10 shares the original request/deadline and rejects v9 drift', async () => {
  const original = globalThis.fetch; const calls = [];
  const responses = (...entries) => {
    calls.length = 0;
    globalThis.fetch = async (url, init) => {
      calls.push({ url, init }); assert.ok(entries.length, 'no unplanned fallback');
      const [status, value] = entries.shift(); return new Response(typeof value === 'string' ? value : JSON.stringify(value), { status });
    };
  };
  try {
    responses([200, menu(selection)]);
    assert.equal((await fetchStorefrontMenu('sf-synth-a', config)).content_v1.appearance.menu_banner_enabled, true);
    assert.equal(calls.length, 1); assert.equal(calls[0].url, origin + '/rest/v1/rpc/storefront_menu_v11');
    for (const error of [missing(9), { code: '42883', message: 'function public.storefront_menu_v9(text) does not exist' }]) {
      responses([404, missing(11)], [404, missing(10)], [404, error], [200, menu()]);
      assert.deepEqual(await fetchStorefrontMenu('sf-synth-a', config), decodeStorefrontMenuV8(menu()));
      assert.deepEqual(calls.map(c => c.url), [11, 10, 9, 8].map(v => origin + '/rest/v1/rpc/storefront_menu_v' + v));
      assert.ok(calls.every(c => c.init === calls[0].init)); assert.equal(calls[0].init, calls[1].init); assert.equal(calls[1].init, calls[2].init); assert.equal(calls[0].init.body, JSON.stringify({ p_slug: 'sf-synth-a' }));
    }
    for (const [status, body] of [[404, missing(8)], [404, '<html>not found</html>'], [403, missing(9)], [500, missing(9)], [404, { ...missing(9), code: '42501' }], [200, menu({ menu_banner_enabled: 'false' })]]) {
      responses([status, body]); await assert.rejects(() => fetchStorefrontMenu('sf-synth-a', config)); assert.equal(calls.length, 1);
    }
    responses([404, missing(11)], [404, missing(10)], [404, missing(9)], [200, menu(selection)]);
    await assert.rejects(() => fetchStorefrontMenu('sf-synth-a', config), EnvelopeError, 'v8 cannot silently accept the v9 wire');
    assert.equal(calls.length, 4);
  } finally { globalThis.fetch = original; }
});
