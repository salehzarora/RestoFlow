// Real Auth + Storage + PostgREST + Edge acceptance. Never service_role.
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFixture, ownerSession, request, rpc, scope, storagePath, readContent, readInvariants, assertDenied, assertRpcDenied } from './service.mjs';

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
  });

  for (const [label, token] of [['owner B', b], ['unaffiliated authenticated user', outsider]]) {
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
