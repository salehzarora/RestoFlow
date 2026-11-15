import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { syntheticV4Envelope } from './support/content-envelope.mjs';
import { SYNTH_MEDIA_PATH } from './support/envelope.mjs';
const { EnvelopeError } = await import('../src/source/live/decode.ts');
const { decodeStorefrontMenuV6, decodeStorefrontMenuV7 } = await import('../src/source/live/decodeContentV1.ts');
const { adaptStorefront, liveStorefrontSource } = await import('../src/source/live/adapter.ts');
const { menuBackground } = await import('../src/ui/storefront/home/menuBackground.ts');

const config = { url: 'https://oqmevrndtivqxgyvcmwy.supabase.co', anonKey: 'synthetic-publishable-key' };
const highUrl = '/storage/v1/object/public/storefront-media/' + '3'.repeat(32) + '/' + 'b'.repeat(64) + '.webp';
const field = 'menu_background_images_v1';
function menu() {
  const raw = syntheticV4Envelope();
  raw.content_v1.appearance = { text_color: null, button_text_color: null, menu_background_url: SYNTH_MEDIA_PATH, menu_background_dim: 0 };
  raw[field] = { base_url: SYNTH_MEDIA_PATH, variants: [
    { url: SYNTH_MEDIA_PATH, width: 720, height: 960 },
    { url: highUrl, width: 1920, height: 2560 },
  ] };
  return raw;
}

test('v7 adds only the selected background manifest; unextended success and failure remain v6 exact', () => {
  const raw = menu();
  const { [field]: manifest, ...v6 } = raw;
  assert.deepEqual(decodeStorefrontMenuV7(v6), decodeStorefrontMenuV6(v6));
  assert.deepEqual(decodeStorefrontMenuV7(raw), { ...decodeStorefrontMenuV6(v6), [field]: manifest });
  assert.throws(() => decodeStorefrontMenuV6(raw), EnvelopeError);
  const denied = { ok: false, error: 'not_found', entity: 'storefront_menu' };
  assert.deepEqual(decodeStorefrontMenuV7(denied), denied);
  assert.throws(() => decodeStorefrontMenuV7({ ...denied, [field]: manifest }), EnvelopeError);
  assert.throws(() => decodeStorefrontMenuV7({ ...raw, unknown: {} }), EnvelopeError);
  assert.throws(() => decodeStorefrontMenuV7({ ...raw, product_images_v1: [{}] }), EnvelopeError);
});

test('manifest strictly binds the selected public base, closed shape, actual dimensions, and candidate order', () => {
  for (const change of [
    (m, raw) => { raw[field] = null; },
    (m, raw) => { delete raw.content_v1.appearance.menu_background_url; },
    (m, raw) => { raw.content_v1.appearance.menu_background_url = null; },
    m => { m.base_url = highUrl; },
    m => { m.source_key = 'private-original'; },
    m => { m.variants = []; },
    m => { m.variants.push(m.variants[1]); },
    m => { m.variants.reverse(); },
    m => { m.variants[0].width = 961; },
    m => { m.variants[1].width = 720; },
    m => { m.variants[1].height = 959; },
    m => { m.variants[1].width = 0; },
    m => { m.variants[1].height = 2561; },
    m => { m.variants[1].width = 1900.5; },
    m => { m.variants[1].width = 1800; },
    m => { m.variants[1].url = SYNTH_MEDIA_PATH; },
    m => { m.variants[1].url = highUrl + '?download=1'; },
    m => { m.variants[1].url = highUrl + '\n'; },
    m => { m.variants[1].url = config.url + highUrl; },
    m => { m.variants[1].url = highUrl.replace('/public/', '/sign/'); },
    m => { m.variants[1].source_generation = 'private'; },
  ]) {
    const raw = menu(); change(raw[field], raw);
    assert.throws(() => decodeStorefrontMenuV7(raw), EnvelopeError);
  }
  const rounded = menu(); rounded[field].variants[1].width--;
  assert.doesNotThrow(() => decodeStorefrontMenuV7(rounded));
});

test('adapter and cover sizes use actual width, keep menu-only scope, and preserve zero dim and legacy Hero', () => {
  const raw = menu();
  const { [field]: _, ...v6 } = raw;
  const before = adaptStorefront(decodeStorefrontMenuV6(v6), config.url);
  const after = adaptStorefront(decodeStorefrontMenuV7(raw), config.url);
  const { menuBackgroundVariants, ...tenant } = after.view.tenant;
  assert.deepEqual(tenant, before.view.tenant);
  assert.deepEqual(after.view.items, before.view.items);
  assert.deepEqual(menuBackgroundVariants, raw[field].variants.map(v => ({ ...v, url: config.url + v.url })));
  for (const preset of [null, 'reference_dark']) {
    const scene = menuBackground(after.view.tenant, preset);
    assert.equal(scene.image, config.url + SYNTH_MEDIA_PATH);
    assert.equal(scene.dim, 0);
    assert.equal(scene.srcSet, config.url + SYNTH_MEDIA_PATH + ' 720w, ' + config.url + highUrl + ' 1920w');
    assert.equal(scene.sizes, 'max(100vw, 75svh)');
    const cleared = menuBackground({ ...after.view.tenant, menuBackgroundImage: null }, preset);
    assert.equal(cleared.kind, 'legacy'); assert.equal(cleared.image, tenant.heroImage);
    assert.equal(cleared.srcSet, undefined);
  }
  raw[field].variants.pop();
  assert.equal(menuBackground(adaptStorefront(decodeStorefrontMenuV7(raw), config.url).view.tenant).srcSet, undefined);
  assert.equal(menuBackground({ ...after.view.tenant, menuBackgroundImage: config.url + highUrl }).srcSet, undefined);
});

test('after exact missing v11 through v8, the live source retries only missing v7 and decodes v6 strictly', async () => {
  const pgrst = { code: 'PGRST202', message: 'Could not find the function public.storefront_menu_v7(p_slug) in the schema cache' };
  const pg = { code: '42883', message: 'function public.storefront_menu_v7(text) does not exist' };
  const raw = menu(); const { [field]: _, ...v6 } = raw;
  const original = globalThis.fetch;
  const source = liveStorefrontSource(config);
  const attempts = [];
  const responses = (...entries) => {
    entries.unshift([404, { code: 'PGRST202', message: 'Could not find the function public.storefront_menu_v8(p_slug) in the schema cache' }]);
    entries.unshift([404, { code: 'PGRST202', message: 'Could not find the function public.storefront_menu_v9(p_slug) in the schema cache' }]);
    entries.unshift([404, { code: 'PGRST202', message: 'Could not find the function public.storefront_menu_v10(p_slug) in the schema cache' }]);
    entries.unshift([404, { code: 'PGRST202', message: 'Could not find the function public.storefront_menu_v11(p_slug) in the schema cache' }]);
    attempts.length = 0;
    globalThis.fetch = async (url, init) => {
      attempts.push({ url, init });
      const [status, body] = entries.shift();
      return new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });
    };
  };
  const read = () => source.getStorefront('sf-synth-a');
  try {
    responses([200, raw]); assert.equal((await read()).view.tenant.menuBackgroundVariants.length, 2);
    assert.equal(attempts.length, 5);
    for (const error of [pgrst, pg]) {
      responses([404, error], [200, v6]); assert.equal((await read()).view.tenant.menuBackgroundVariants, undefined);
      assert.deepEqual(attempts.map(a => a.url), [11, 10, 9, 8, 7, 6].map(version => config.url + '/rest/v1/rpc/storefront_menu_v' + version));
      assert.equal(attempts[0].init, attempts[1].init, 'one deadline, slug and public auth');
      assert.ok(attempts.every(attempt => attempt.init === attempts[0].init), 'Every fallback retains that exact original deadline, slug and public auth');
    }
    for (const [status, body] of [
      [404, '<html>not found</html>'], [403, pgrst], [500, pgrst], [404, { ...pgrst, code:'42501' }],
      [404, { ...pgrst, message:pgrst.message.replace('_v7','_v5') }],
      [404, { ...pg, message:'function app.internal_helper(text) does not exist' }],
      [200, { ...raw, extra:true }],
    ]) {
      responses([status, body]); await assert.rejects(read); assert.equal(attempts.length, 5);
    }
    responses([404, pgrst], [200, raw]); await assert.rejects(read, EnvelopeError); assert.equal(attempts.length, 6);
    responses([404, pgrst], [500, {}]); await assert.rejects(read, /HTTP 500/); assert.equal(attempts.length, 6);
  } finally { globalThis.fetch = original; }
});
