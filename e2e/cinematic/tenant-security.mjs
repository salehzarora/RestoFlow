// Real Auth + Storage + PostgREST + Edge acceptance. Never service_role.
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFixture, ownerSession, request, rpc, scope, storagePath, readContent, readInvariants, assertDenied, assertRpcDenied } from './service.mjs';
import { fixture as mediaFixture } from '../../supabase/functions/storefront-media-publish/test/fixtures.mjs';

const results = [];
const fixture = readFixture();
const output = process.env.CINEMATIC_ARTIFACT_DIR;
assert.ok(output, 'Sanitized artifact directory is required');
const image = readFileSync(fileURLToPath(new URL('../../supabase/functions/storefront-media-publish/test/fixtures/base_420_900x450.jpg', import.meta.url)));
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
async function check(name, operation) {
  try { await operation(); results.push({ name, result: 'PASS' }); }
  catch { results.push({ name, result: 'FAIL' }); throw new Error(`Real-service acceptance failed: ${name}`); }
}

// Independent security positive controls. These synthetic items are created
// after the UI journey, so a UI failure cannot turn missing IDs into a false
// isolation pass. They are not evidence of saving through the Dashboard.
async function productFixture(owner, token) {
  async function successful(name, params) {
    const result = await rpc(fixture, token, name, { ...scope(owner), ...params });
    assert.equal(result.status, 200, name);
    assert.equal(result.data?.ok, true, name);
    return result.data;
  }
  const category = await successful('menu_upsert_category', { p_name: 'PRODUCT SECURITY TEST' });
  const fields = { p_menu_category_id: category.id, p_name: 'PRODUCT SECURITY TEST',
    p_base_price_minor: 1000, p_currency_code: 'ILS', p_is_active: true };
  const item = await successful('menu_upsert_item', fields);
  assert.match(item.id, /^[0-9a-f-]{36}$/);
  const prefix = `${owner.orgId}/${owner.restaurantId}/global/menu_item/${item.id}`;
  const originalKey = `${prefix}/${randomUUID()}.jpg`, candidateKey = `${prefix}/${randomUUID()}.png`;
  const candidate = await mediaFixture('logo_alpha_2000x1000');
  for (const [key, bytes, contentType] of [[originalKey, image, 'image/jpeg'], [candidateKey, candidate, 'image/png']]) {
    const upload = await request(fixture, token, `/storage/v1/object/menu-images/${storagePath(key)}`, { method: 'POST', bytes, contentType });
    assert.equal(upload.status, 200, 'Owner uploads its synthetic private product input');
  }
  await successful('menu_upsert_item', { ...fields, p_id: item.id, p_image_path: originalKey });
  const original = await successful('get_storefront_product_original_v1', { p_item_id: item.id });
  const registration = { p_client_request_id: randomUUID(), p_item_id: item.id,
    p_original_key: originalKey, p_original_snapshot: original.source_snapshot,
    p_candidate_key: candidateKey, p_treatment: 'cutout', p_expected_selection_version: original.selection_version };
  const registered = await successful('register_storefront_product_derivative_v1', registration);
  const derivativeId = registered.derivative_id;
  const source = await successful('get_storefront_product_source_v1', { p_derivative_id: derivativeId });
  assert.equal(source.source_key, candidateKey);
  const media = [];
  for (const variant of ['w480', 'w960']) {
    const published = await request(fixture, token, '/functions/v1/storefront-media-publish', { method: 'POST', body: {
      request_id: randomUUID(), organization_id: owner.orgId, restaurant_id: owner.restaurantId,
      slot: 'product', variant, source_bucket: 'menu-images', source_key: candidateKey,
      product_derivative_id: derivativeId, rung: 0,
    } });
    assert.equal(published.status, 200, 'Product slot must really publish before negative controls');
    assert.equal(published.data?.status, 'published');
    media.push(published.data.media);
  }
  const selected = await successful('select_storefront_product_derivative_v1', {
    p_client_request_id: randomUUID(), p_derivative_id: derivativeId,
  });
  const current = await successful('get_storefront_product_original_v1', { p_item_id: item.id });
  assert.equal(current.selected_derivative_id, derivativeId);
  assert.equal(current.selection_version, selected.selection_version);
  return { itemId: item.id, originalKey, candidateKey, original, source, derivativeId, media, registration, current,
    originalHash: hash(image), candidateHash: hash(candidate) };
}

try {
  assert.equal(new Set([fixture.ownerA.authUserId, fixture.ownerB.authUserId, fixture.outsider.authUserId]).size, 3);
  assert.notEqual(fixture.ownerA.orgId, fixture.ownerB.orgId);
  assert.notEqual(fixture.ownerA.restaurantId, fixture.ownerB.restaurantId);
  const a = await ownerSession(fixture, fixture.ownerA);
  const b = await ownerSession(fixture, fixture.ownerB);
  const outsider = await ownerSession(fixture, fixture.outsider);
  results.push({ name: 'three distinct real GoTrue password sessions', result: 'PASS' });
  const baselineContent = await readContent(fixture, a);
  const baselineInvariants = await readInvariants(fixture, a);
  assert.deepEqual(baselineInvariants, fixture.initialInvariants, 'UI journey must preserve initial Hero and receipt logo');
  const originalPath = `/storage/v1/object/authenticated/restaurant-logos/${storagePath(fixture.heroSourceKey)}`;
  const original = await request(fixture, a, originalPath);
  assert.equal(original.status, 200, 'Owner A must be able to read its actual private original');
  const originalHash = hash(original.bytes);
  // This is the bootstrap Hero, independent of the Dashboard journey. Publishing
  // its companion cannot select it as the menu background or change Hero/receipt.
  const backgroundScope = { ...scope(fixture.ownerA), p_branch_id: fixture.branchId, p_base_media_id: fixture.heroMediaId };
  const backgroundBody = { organization_id: fixture.ownerA.orgId, restaurant_id: fixture.ownerA.restaurantId,
    branch_id: fixture.branchId, base_media_id: fixture.heroMediaId, slot: 'background', variant: 'bg2560', base_rung: 0, rung: 0 };
  let backgroundStage, backgroundFinalize, backgroundPath, backgroundHash;
  await check('owner publishes the independent bootstrap background and reads the registered public bytes', async () => {
    const originalSource = await rpc(fixture, a, 'get_storefront_background_source_v1', backgroundScope);
    assert.equal(originalSource.status, 200);
    const source = originalSource.data;
    assert.equal(source?.ok, true);
    assert.equal(source.base_media_id, fixture.heroMediaId);
    assert.equal(source.source_bucket, 'restaurant-logos');
    assert.equal(source.source_key, fixture.heroSourceKey);
    assert.equal(source.base_width, 960);
    assert.equal(source.base_height, 720);
    const base = await request(fixture, null, new URL(fixture.heroUrl).pathname);
    assert.equal(base.status, 200);
    assert.equal(hash(base.bytes), source.base_hash);
    const published = await request(fixture, a, '/functions/v1/storefront-media-publish', {
      method: 'POST', body: { ...backgroundBody, request_id: randomUUID() },
    });
    assert.equal(published.status, 200);
    assert.equal(published.data?.status, 'published');
    const media = published.data.media;
    assert.equal(media.base_media_id, fixture.heroMediaId);
    assert.equal(media.variant, 'bg2560');
    assert.equal(media.recipe, 'storefront-background-b1');
    assert.equal(media.state, 'published');
    assert.equal(media.width, 1000);
    assert.equal(media.height, 750);
    assert.match(media.variant_id, /^[0-9a-f-]{36}$/);
    assert.match(media.content_hash, /^[0-9a-f]{64}$/);
    const prefix = hash(Buffer.from('storefront-menu-background-v1:' + fixture.ownerA.restaurantId)).slice(0, 32);
    assert.equal(media.object_key, prefix + '/' + media.content_hash + '.webp');
    backgroundPath = storagePath(media.object_key);
    const high = await request(fixture, null, '/storage/v1/object/public/storefront-media/' + backgroundPath);
    assert.equal(high.status, 200);
    assert.equal(high.bytes.length, media.bytes);
    backgroundHash = hash(high.bytes);
    assert.equal(backgroundHash, media.content_hash);
    assert.notEqual(backgroundHash, source.base_hash);
    backgroundStage = { ...backgroundScope, p_source_snapshot: source.source_snapshot, p_expected_base_hash: source.base_hash,
      p_content_hash: media.content_hash, p_width: media.width, p_height: media.height, p_bytes: media.bytes };
    backgroundFinalize = { ...scope(fixture.ownerA), p_variant_id: media.variant_id };
    for (const [name, parameters] of [['stage_storefront_background_variant_v1', backgroundStage],
      ['finalize_storefront_background_variant_v1', backgroundFinalize]]) {
      const confirmation = await rpc(fixture, a, name, { ...parameters, p_client_request_id: randomUUID() });
      assert.equal(confirmation.status, 200);
      assert.equal(confirmation.data?.ok, true);
      assert.equal(confirmation.data.state, 'published');
      assert.equal(confirmation.data.variant_id, media.variant_id);
      assert.equal(confirmation.data.object_key, media.object_key);
      assert.equal(confirmation.data.content_hash, media.content_hash);
    }
  });
  await check('stale source proof and foreign base IDs cannot bind another background', async () => {
    const stale = await rpc(fixture, a, 'stage_storefront_background_variant_v1', { ...backgroundStage,
      p_client_request_id: randomUUID(), p_source_snapshot: { ...backgroundStage.p_source_snapshot, storage_object_id: randomUUID() } });
    assert.equal(stale.status, 200);
    assert.deepEqual(stale.data, { ok: false, error: 'source_stale' });
    const other = { ...scope(fixture.ownerB), p_branch_id: fixture.ownerB.branchId };
    for (const [name, params] of [['get_storefront_background_source_v1', { ...backgroundScope, ...other }],
      ['stage_storefront_background_variant_v1', { ...backgroundStage, ...other, p_client_request_id: randomUUID() }],
      ['finalize_storefront_background_variant_v1', { ...backgroundFinalize, ...scope(fixture.ownerB), p_client_request_id: randomUUID() }]]) {
      const foreign = await rpc(fixture, b, name, params);
      assert.equal(foreign.status, 200);
      assert.deepEqual(foreign.data, { ok: false, error: 'not_found' });
    }
  });
  await check('manager cannot overwrite or delete the immutable companion through real Storage', async () => {
    const base = await request(fixture, null, new URL(fixture.heroUrl).pathname);
    assert.equal(base.status, 200);
    assert.notEqual(hash(base.bytes), backgroundHash);
    assertDenied(await request(fixture, a, '/storage/v1/object/storefront-media/' + backgroundPath,
      { method: 'PUT', bytes: base.bytes, contentType: 'image/webp' }), 'owner immutable background overwrite');
    const removed = await request(fixture, a, '/storage/v1/object/storefront-media', {
      method: 'DELETE', body: { prefixes: [backgroundPath] },
    });
    if (removed.status === 200) assert.deepEqual(removed.data, [], 'Storage bulk delete cannot remove any registered companion');
    else assertDenied(removed, 'owner immutable background delete');
    const after = await request(fixture, a, '/storage/v1/object/authenticated/storefront-media/' + backgroundPath);
    assert.equal(after.status, 200);
    assert.equal(hash(after.bytes), backgroundHash);
  });

  let productA, productB;
  await check('both owners can publish and select their own complete product pairs with real Auth/Storage/Edge', async () => {
    productA = await productFixture(fixture.ownerA, a);
    productB = await productFixture(fixture.ownerB, b);
    assert.notEqual(productA.derivativeId, productB.derivativeId);
  });

  await check('owner A can read every private RPC and use real Storage read/list/sign endpoints', async () => {
    for (const name of ['get_restaurant_storefront_content_v1', 'get_restaurant_storefront_content_v2', 'get_restaurant_storefront_content_v3', 'get_restaurant_storefront_profile', 'list_storefront_content_media_v1', 'list_storefront_content_media_v2', 'list_storefront_media', 'get_restaurant_receipt_logo']) {
      const read = await rpc(fixture, a, name, scope(fixture.ownerA));
      assert.equal(read.status, 200);
      assert.equal(read.data?.ok, true);
    }
    const signed = await request(fixture, a, `/storage/v1/object/sign/restaurant-logos/${storagePath(fixture.heroSourceKey)}`, { method: 'POST', body: { expiresIn: 60 } });
    assert.equal(signed.status, 200);
    const listed = await request(fixture, a, '/storage/v1/object/list/restaurant-logos', { method: 'POST', body: { prefix: `${fixture.ownerA.orgId}/${fixture.ownerA.restaurantId}/logo`, limit: 100, offset: 0 } });
    assert.equal(listed.status, 200);
    assert.ok(Array.isArray(listed.data) && listed.data.length > 0);
  });

  await check('owner B has its independent authorized restaurant and upload scope', async () => {
    await readContent(fixture, b, fixture.ownerB);
    const key = `${fixture.ownerB.orgId}/${fixture.ownerB.restaurantId}/logo/${randomUUID()}.jpg`;
    const upload = await request(fixture, b, `/storage/v1/object/restaurant-logos/${storagePath(key)}`, { method: 'POST', bytes: image, contentType: 'image/jpeg' });
    assert.equal(upload.status, 200);
    const read = await request(fixture, b, `/storage/v1/object/authenticated/restaurant-logos/${storagePath(key)}`);
    assert.equal(read.status, 200);
    assert.equal(hash(read.bytes), hash(image));
    const overwrite = await request(fixture, b, `/storage/v1/object/restaurant-logos/${storagePath(key)}`, { method: 'PUT', bytes: image, contentType: 'image/jpeg' });
    assert.equal(overwrite.status, 200, 'Owner B positive control proves the overwrite endpoint exists');
    const removed = await request(fixture, b, '/storage/v1/object/restaurant-logos', {
      method: 'DELETE', body: { prefixes: [key] },
    });
    assert.equal(removed.status, 200, 'Owner B can use the bulk deletion endpoint on its own disposable upload');
    assert.ok(Array.isArray(removed.data) && removed.data.some(row => row.name === key));
    assertDenied(await request(fixture, b, `/storage/v1/object/authenticated/restaurant-logos/${storagePath(key)}`),
      'The disposable positive-control object must be gone');
  });

  for (const [label, token] of [['owner B', b], ['unaffiliated authenticated user', outsider]]) {
    await check(`${label}: every foreign private background RPC and its publisher slot are denied`, async () => {
      for (const [name, parameters] of [['get_storefront_background_source_v1', backgroundScope],
        ['stage_storefront_background_variant_v1', { ...backgroundStage, p_client_request_id: randomUUID() }],
        ['finalize_storefront_background_variant_v1', { ...backgroundFinalize, p_client_request_id: randomUUID() }]]) {
        assertRpcDenied(await rpc(fixture, token, name, parameters), `${label} ${name}`);
      }
      const denied = await request(fixture, token, '/functions/v1/storefront-media-publish', {
        method: 'POST', body: { ...backgroundBody, request_id: randomUUID() },
      });
      assert.equal(denied.status, 403);
      assert.deepEqual(denied.data, { ok: false, status: 'permission_denied' });
    });
    await check(`${label}: all six new product RPCs reject A scope and real A identifiers`, async () => {
      const m = productA.media[0];
      const operations = [
        ['get_storefront_product_original_v1', { p_item_id: productA.itemId }],
        ['register_storefront_product_derivative_v1', { ...productA.registration, p_client_request_id: randomUUID() }],
        ['get_storefront_product_source_v1', { p_derivative_id: productA.derivativeId }],
        ['stage_storefront_product_media_v1', { p_client_request_id: randomUUID(), p_derivative_id: productA.derivativeId,
          p_source_key: productA.candidateKey, p_source_snapshot: productA.source.source_snapshot,
          p_variant: m.variant, p_content_hash: m.content_hash, p_width: m.width, p_height: m.height, p_bytes: m.bytes }],
        ['finalize_storefront_product_media_v1', { p_client_request_id: randomUUID(), p_media_id: m.id }],
        ['select_storefront_product_derivative_v1', { p_client_request_id: randomUUID(), p_derivative_id: productA.derivativeId }],
      ];
      for (const [name, parameters] of operations) {
        assertRpcDenied(await rpc(fixture, token, name, { ...scope(fixture.ownerA), ...parameters }), `${label} ${name}`);
      }
      const published = await request(fixture, token, '/functions/v1/storefront-media-publish', { method: 'POST', body: {
        request_id: randomUUID(), organization_id: fixture.ownerA.orgId, restaurant_id: fixture.ownerA.restaurantId,
        slot: 'product', variant: 'w960', source_bucket: 'menu-images', source_key: productA.candidateKey,
        product_derivative_id: productA.derivativeId, rung: 0,
      } });
      assert.equal(published.status, 403);
      assert.deepEqual(published.data, { ok: false, status: 'permission_denied' });
    });

    await check(`${label}: private product original/candidate reads and overwrites are denied`, async () => {
      for (const key of [productA.originalKey, productA.candidateKey]) {
        assertDenied(await request(fixture, token, `/storage/v1/object/authenticated/menu-images/${storagePath(key)}`), `${label} product private read`);
        assertDenied(await request(fixture, token, `/storage/v1/object/menu-images/${storagePath(key)}`, {
          method: 'PUT', bytes: image, contentType: 'image/jpeg',
        }), `${label} product private overwrite`);
      }
    });
    await check(`${label}: A private content/profile/media/receipt reads denied`, async () => {
      for (const name of ['get_restaurant_storefront_content_v1', 'get_restaurant_storefront_content_v2', 'get_restaurant_storefront_content_v3', 'get_restaurant_storefront_profile', 'list_storefront_content_media_v1', 'list_storefront_content_media_v2', 'list_storefront_media', 'get_restaurant_receipt_logo']) {
        assertRpcDenied(await rpc(fixture, token, name, scope(fixture.ownerA)), `${label} ${name}`);
      }
      assertDenied(await request(fixture, token, originalPath), `${label} private original`);
      assertDenied(await request(fixture, token, `/storage/v1/object/sign/restaurant-logos/${storagePath(fixture.heroSourceKey)}`, { method: 'POST', body: { expiresIn: 60 } }), `${label} signed private URL`);
      const list = await request(fixture, token, '/storage/v1/object/list/restaurant-logos', { method: 'POST', body: { prefix: `${fixture.ownerA.orgId}/${fixture.ownerA.restaurantId}/logo`, limit: 100, offset: 0 } });
      if (list.status === 200) assert.deepEqual(list.data, [], 'RLS must hide A private object list');
      else assertDenied(list, `${label} private object list`);
    });

    await check(`${label}: forged private upload and overwrite denied`, async () => {
      const forgedKey = `${fixture.ownerA.orgId}/${fixture.ownerA.restaurantId}/logo/${randomUUID()}.jpg`;
      assertDenied(await request(fixture, token, `/storage/v1/object/restaurant-logos/${storagePath(forgedKey)}`, { method: 'POST', bytes: image, contentType: 'image/jpeg' }), `${label} forged upload`);
      const missing = await request(fixture, a, `/storage/v1/object/authenticated/restaurant-logos/${storagePath(forgedKey)}`);
      assertDenied(missing, 'Denied upload must leave no owner-readable object');
      assertDenied(await request(fixture, token, `/storage/v1/object/restaurant-logos/${storagePath(fixture.heroSourceKey)}`, { method: 'PUT', bytes: image, contentType: 'image/jpeg' }), `${label} forged overwrite`);
    });

    await check(`${label}: forged A media publication denied`, async () => {
      const published = await request(fixture, token, '/functions/v1/storefront-media-publish', { method: 'POST', body: {
        request_id: randomUUID(), organization_id: fixture.orgId, restaurant_id: fixture.restaurantId,
        slot: 'hero', variant: 'w960', source_bucket: 'restaurant-logos', source_key: fixture.heroSourceKey, rung: 0,
      } });
      assert.equal(published.status, 403, 'Authenticated cross-tenant publication must fail at authority preflight');
      assert.deepEqual(published.data, { ok: false, status: 'permission_denied' });
    });

    await check(`${label}: forged A content/profile/receipt writes denied`, async () => {
      const forged = structuredClone(baselineContent.document);
      forged.appearance = { ...forged.appearance, text_color: '#a1b2c3', button_text_color: '#123456' };
      assertRpcDenied(await rpc(fixture, token, 'set_restaurant_storefront_content_v1', {
        ...scope(fixture.ownerA), p_client_request_id: randomUUID(), p_expected_version: baselineContent.version,
        p_expected_storefront_branch_id: fixture.branchId, p_document: forged,
      }), `${label} content write`);
      assertRpcDenied(await rpc(fixture, token, 'set_restaurant_storefront_profile', {
        ...scope(fixture.ownerA), p_client_request_id: randomUUID(), p_expected_version: baselineContent.version,
        p_patch: { accent_color: '#a1b2c3' },
      }), `${label} profile write`);
      assertRpcDenied(await rpc(fixture, token, 'set_restaurant_receipt_logo', {
        ...scope(fixture.ownerA), p_client_request_id: randomUUID(), p_logo_path: null, p_enabled: false,
        p_expected_version: baselineInvariants.receiptLogoVersion,
      }), `${label} receipt write`);
    });
  }

  await check('authorized own scope cannot bind a foreign derivative or candidate', async () => {
    const source = await rpc(fixture, b, 'get_storefront_product_source_v1', {
      ...scope(fixture.ownerB), p_derivative_id: productA.derivativeId,
    });
    assert.equal(source.status, 200);
    assert.deepEqual(source.data, { ok: false, error: 'source_stale' });
    const register = await rpc(fixture, a, 'register_storefront_product_derivative_v1', {
      ...scope(fixture.ownerA), ...productA.registration, p_client_request_id: randomUUID(),
      p_candidate_key: productB.candidateKey, p_expected_selection_version: productA.current.selection_version,
    });
    assert.equal(register.status, 200);
    assert.deepEqual(register.data, { ok: false, error: 'source_not_found' });
  });

  await check('product originals/candidates and selected pairs survive every rejection byte-for-byte', async () => {
    for (const [owner, token, product] of [[fixture.ownerA, a, productA], [fixture.ownerB, b, productB]]) {
      const current = await rpc(fixture, token, 'get_storefront_product_original_v1', { ...scope(owner), p_item_id: product.itemId });
      assert.equal(current.status, 200);
      assert.deepEqual(current.data, product.current);
      for (const [key, expected] of [[product.originalKey, product.originalHash], [product.candidateKey, product.candidateHash]]) {
        const read = await request(fixture, token, `/storage/v1/object/authenticated/menu-images/${storagePath(key)}`);
        assert.equal(read.status, 200);
        assert.equal(hash(read.bytes), expected);
      }
    }
  });

  await check('all denied requests leave A content, Hero, receipt logo and private bytes unchanged', async () => {
    assert.deepEqual(await readContent(fixture, a), baselineContent);
    assert.deepEqual(await readInvariants(fixture, a), baselineInvariants);
    const after = await request(fixture, a, originalPath);
    assert.equal(after.status, 200);
    assert.equal(hash(after.bytes), originalHash);
  });
  await check('published media remains publicly readable without owner session', async () => {
    const publicImage = await request(fixture, null, new URL(fixture.heroUrl).pathname);
    assert.equal(publicImage.status, 200);
    assert.ok(publicImage.bytes.length > 0);
  });
  console.log(`Real Auth/Storage cross-tenant checks PASS (${results.length} checks).`);
} finally {
  mkdirSync(output, { recursive: true });
  // No credentials, request/response dumps, private object names, or user IDs.
  writeFileSync(resolve(output, 'tenant-security.json'), `${JSON.stringify({
    workId: 'BIZBOT-STOREFRONT-CINEMATIC-001B', services: 'ephemeral local Supabase',
    principals: 'real Auth-issued sessions; no service-role acceptance', results,
  }, null, 2)}\n`);
}
