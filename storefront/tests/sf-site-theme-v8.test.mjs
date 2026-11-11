import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';
import { SYNTH_MEDIA_PATH } from './support/envelope.mjs';
const { EnvelopeError } = await import('../src/source/live/decode.ts');
const { decodeStorefrontMenuV5, decodeStorefrontMenuV6, decodeStorefrontMenuV7, decodeStorefrontMenuV8 } = await import('../src/source/live/decodeContentV1.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { fetchStorefrontMenu } = await import('../src/source/live/client.ts');

const config = { url: 'https://oqmevrndtivqxgyvcmwy.supabase.co', anonKey: 'synthetic-publishable-key' };
function menu(theme, included = true) {
  const raw = syntheticV4Envelope();
  raw.restaurant.visual_preset = 'light';
  raw.restaurant.primary_color = '#292929';
  raw.restaurant.accent_color = '#ff8000';
  raw.content_v1.appearance = {
    text_color: '#ffffff', button_text_color: '#000000', font_family: 'alexandria',
    scene_preset: 'reference_dark', menu_background_url: SYNTH_MEDIA_PATH, menu_background_dim: 37,
    ...(included ? { site_theme: theme } : {}),
  };
  raw.menu_background_images_v1 = { base_url: SYNTH_MEDIA_PATH, variants: [{ url: SYNTH_MEDIA_PATH, width: 720, height: 960 }] };
  return raw;
}
const missing = (version, pg = false) => pg
  ? { code: '42883', message: `function public.storefront_menu_v${version}(text) does not exist` }
  : { code: 'PGRST202', message: `Could not find the function public.storefront_menu_v${version}(p_slug) in the schema cache` };

test('v8 absent/null/light/dark is explicit and old strict decoder boundaries are unchanged', () => {
  const legacy = menu(undefined, false);
  assert.deepEqual(decodeStorefrontMenuV8(legacy), decodeStorefrontMenuV7(legacy));
  const failed = { ok: false, error: 'not_found', entity: 'storefront_menu' };
  assert.deepEqual(decodeStorefrontMenuV8(failed), failed);
  for (const theme of [null, 'light', 'dark']) {
    const raw = menu(theme); const input = structuredClone(raw);
    const decoded = decodeStorefrontMenuV8(raw);
    assert.deepEqual(raw, input, 'decoder does not mutate a shared response');
    assert.equal(decoded.content_v1.appearance.site_theme, theme);
    const { site_theme, ...appearance } = decoded.content_v1.appearance;
    assert.deepEqual({ ...decoded, content_v1: { ...decoded.content_v1, appearance } }, decodeStorefrontMenuV7(legacy));
    assert.throws(() => decodeStorefrontMenuV7(raw), EnvelopeError);
    const { menu_background_images_v1, ...v6 } = raw;
    assert.throws(() => decodeStorefrontMenuV6(v6), EnvelopeError);
    delete v6.content_v1.appearance.scene_preset;
    assert.throws(() => decodeStorefrontMenuV5(v6), EnvelopeError);
  }
});

test('v8 rejects malformed choices and unknown data without normalizing or falling back', () => {
  for (const theme of [undefined, false, true, 0, 1, [], {}, 'auto', 'Light', 'light ', 'false', '']) {
    assert.throws(() => decodeStorefrontMenuV8(menu(theme)), EnvelopeError, JSON.stringify(theme));
  }
  for (const mutate of [
    r => { r.content_v1.appearance.other_theme = 'light'; },
    r => { delete r.content_v1.appearance.text_color; },
    r => { r.content_v1.appearance.site_theme = { value: 'light' }; },
    r => { r.content_v1.appearance.scene_preset = 'dark'; },
    r => { r.menu_background_images_v1.variants[0].width = 10000; },
    r => { r.content_v1.appearance.menu_background_url = 'https://private.example/original.jpg'; },
    r => { r.unknown = {}; },
  ]) {
    const raw = menu('light'); mutate(raw);
    assert.throws(() => decodeStorefrontMenuV8(raw), EnvelopeError);
  }
  assert.throws(() => decodeStorefrontMenuV8({ ok: false, error: 'not_found', entity: 'storefront_menu', content_v1: menu('dark').content_v1 }), EnvelopeError);
});

test('adapter carries optional site choice without retuning legacy preset/colors/font/media/dim', () => {
  const old = adaptStorefront(decodeStorefrontMenuV7(menu(undefined, false)), config.url);
  assert.equal(Object.hasOwn(old.view.tenant, 'siteTheme'), false);
  for (const theme of [null, 'light', 'dark']) {
    const current = adaptStorefront(decodeStorefrontMenuV8(menu(theme)), config.url);
    const { siteTheme, ...rest } = current.view.tenant;
    assert.equal(siteTheme, theme);
    assert.deepEqual(rest, old.view.tenant);
    assert.equal(current.preset, 'light');
    assert.deepEqual(current.view.items, old.view.items);
    assert.equal(current.menuVersion, old.menuVersion);
    assert.equal(current.view.tenant.menuBackgroundDim, 37);
  }
});

test('v8 client accepts only exact missing requested signatures, sharing one deadline/auth/body for v7/v6', async () => {
  const original = globalThis.fetch;
  const attempts = [];
  const responses = (...entries) => {
    attempts.length = 0;
    globalThis.fetch = async (url, init) => {
      attempts.push({ url, init });
      assert.ok(entries.length, 'unexpected additional fallback');
      const [status, body] = entries.shift();
      return new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });
    };
  };
  const read = () => fetchStorefrontMenu('sf-synth-a', config);
  const legacy = menu(undefined, false);
  const { menu_background_images_v1, ...v6 } = legacy;
  try {
    responses([200, menu('dark')]);
    assert.equal((await read()).content_v1.appearance.site_theme, 'dark');
    assert.equal(attempts.length, 1);
    for (const pg of [false, true]) {
      responses([404, missing(8, pg)], [200, legacy]);
      assert.deepEqual(await read(), decodeStorefrontMenuV7(legacy));
      assert.deepEqual(attempts.map(a => a.url), [8, 7].map(v => `${config.url}/rest/v1/rpc/storefront_menu_v${v}`));
      assert.equal(attempts[0].init, attempts[1].init);
      responses([404, missing(8, pg)], [404, missing(7, pg)], [200, v6]);
      assert.deepEqual(await read(), decodeStorefrontMenuV6(v6));
      assert.deepEqual(attempts.map(a => a.url), [8, 7, 6].map(v => `${config.url}/rest/v1/rpc/storefront_menu_v${v}`));
      assert.ok(attempts.every(a => a.init === attempts[0].init));
    }
    for (const [status, body] of [
      [404, missing(7)], [404, '<html>not found</html>'], [403, missing(8)], [500, missing(8)],
      [404, { ...missing(8), code: '42501' }],
      [404, { ...missing(8), message: missing(8).message.replace('public.', 'app.') }],
      [200, menu('auto')], [200, { ...menu('light'), extra: true }],
    ]) {
      responses([status, body]); await assert.rejects(read); assert.equal(attempts.length, 1);
    }
    for (const [status, body] of [[200, menu('dark')], [404, missing(8)], [403, missing(7)], [500, missing(7)]]) {
      responses([404, missing(8)], [status, body]); await assert.rejects(read); assert.equal(attempts.length, 2);
    }
    responses([404, missing(8)], [404, missing(7)], [200, menu('dark')]);
    await assert.rejects(read, EnvelopeError); assert.equal(attempts.length, 3);
  } finally { globalThis.fetch = original; }
});
