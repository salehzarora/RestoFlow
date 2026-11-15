// Fixture creation only. No privileged client is used by owner acceptance.
// SQL is limited to synthetic catalogue/profile prerequisites in the CI-local DB.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { API_URL, assertAnonKey, assertEphemeralEnvironment, fixturePath, request, rpc, scope, storagePath, readInvariants } from './service.mjs';
import { createPublisherDiagnostics, waitForAuthenticatedPublisher } from './publisher-diagnostics.mjs';
import { createBootstrapDiagnostics } from './bootstrap-diagnostics.mjs';
import { png, photoRgb } from '../../supabase/functions/storefront-media-publish/test/fixtures.mjs';

assertEphemeralEnvironment();
const target = fixturePath();
assert.ok(process.env.CINEMATIC_STATUS_FILE, 'Private local CLI status file is required');
const status = JSON.parse(readFileSync(process.env.CINEMATIC_STATUS_FILE, 'utf8'));
assert.equal(status.API_URL, API_URL, 'CLI must identify the ephemeral loopback gateway');
const fixture = { apiUrl: API_URL, anonKey: assertAnonKey(status.ANON_KEY) };
const diagnostics = createPublisherDiagnostics(process.env.CINEMATIC_ARTIFACT_DIR);
const bootstrapDiagnostics = createBootstrapDiagnostics(process.env.CINEMATIC_ARTIFACT_DIR);
// Monitoring leaves Node's original uncaught error and nonzero exit unchanged.
process.on('uncaughtExceptionMonitor', error => { try { bootstrapDiagnostics.fail(error); } catch { /* never mask the original failure */ } });
const repo = fileURLToPath(new URL('../../', import.meta.url));
const stamp = randomUUID().slice(0, 8);

async function principal(label) {
  bootstrapDiagnostics.advance(`${label}_signup`);
  const person = { email: `cinematic-${label}-${stamp}@example.test`, password: `${randomBytes(24).toString('base64url')}aA1!` };
  const signup = await request(fixture, null, '/auth/v1/signup', { method: 'POST', body: person });
  bootstrapDiagnostics.response(signup);
  assert.equal(signup.status, 200, `Synthetic ${label} signup must succeed`);
  assert.equal(typeof signup.data?.access_token, 'string', 'Local signup must return a real Auth session');
  assert.match(signup.data?.user?.id || '', /^[0-9a-f-]{36}$/);
  person.authUserId = signup.data.user.id;
  return { person, token: signup.data.access_token };
}

async function owner(label) {
  const account = await principal(label);
  bootstrapDiagnostics.advance(`${label}_organization`);
  const slug = `cinematic-test-${label}-${stamp}`;
  const created = await rpc(fixture, account.token, 'create_organization', {
    p_client_request_id: randomUUID(), p_organization_name: `CINEMATIC TEST ${label.toUpperCase()}`,
    p_organization_slug: slug, p_restaurant_name: `بيانات اختبار ${label.toUpperCase()}`,
    p_branch_name: `TEST ${label.toUpperCase()}`, p_currency_code: 'ILS', p_timezone: 'UTC',
    p_default_station_name: null,
  });
  bootstrapDiagnostics.response(created);
  assert.equal(created.status, 200, 'Real owner onboarding RPC must succeed');
  assert.equal(created.data?.ok, true);
  for (const field of ['organization_id', 'restaurant_id', 'branch_id']) assert.match(created.data[field], /^[0-9a-f-]{36}$/);
  return { ...account, person: { ...account.person, orgId: created.data.organization_id, restaurantId: created.data.restaurant_id, branchId: created.data.branch_id, slug } };
}

const a = await owner('a');
const b = await owner('b');
const outsider = await principal('outsider');
assert.equal(new Set([a.person.authUserId, b.person.authUserId, outsider.person.authUserId]).size, 3);
assert.notEqual(a.person.orgId, b.person.orgId);
assert.notEqual(a.person.restaurantId, b.person.restaurantId);
fixture.ownerA = a.person;
fixture.ownerB = b.person;
fixture.outsider = outsider.person;
// A gateway401 is only the negative JWT control. This real-user POST is
// deliberately invalid before media/engine work and proves handler readiness.
bootstrapDiagnostics.advance('authenticated_publisher_readiness');
await waitForAuthenticatedPublisher(fixture, a.token, { observe: async (stage, operation) => {
  const result = await diagnostics.observe(stage, operation); bootstrapDiagnostics.response(result, true); return result;
} });

const quote = (value) => `'${String(value).replaceAll("'", "''")}'`;
// Use editor-valid hours: closing at midnight would touch the next day's
// opening and correctly block an unrelated profile edit (Q-038). The brief
// closed minute is harmless: this journey neither orders nor requires open_now.
const hours = JSON.parse(readFileSync(new URL('./profile-hours.json', import.meta.url), 'utf8'));
const statements = ['begin;'];
bootstrapDiagnostics.advance('seed_catalogue');
for (const person of [a.person, b.person]) {
  for (const [index, name] of ['وجبات اختبار', 'مقبلات اختبار', 'كاسات اختبار', 'مشروبات اختبار'].entries()) {
    const categoryId = randomUUID();
    statements.push(`insert into public.menu_categories(id,organization_id,restaurant_id,name,display_order,is_active) values
      (${quote(categoryId)},${quote(person.orgId)},${quote(person.restaurantId)},${quote(name)},${index},true);`);
    // Dashboard resolves this org-owner to its sole branch. Existing item scope
    // is immutable, so a global fixture cannot be saved by that branch editor.
    // The global category is valid for a branch item (RF-109 parent reuse).
    statements.push(`insert into public.menu_items(id,organization_id,restaurant_id,branch_id,menu_category_id,name,base_price_minor,currency_code,is_active) values
      (${quote(randomUUID())},${quote(person.orgId)},${quote(person.restaurantId)},${quote(person.branchId)},${quote(categoryId)},${quote(`TEST ${index + 1}`)},1000,'ILS',true);`);
    // DESKTOP-BANNER-FIT-001: one additional synthetic item in the existing
    // first category makes the real swipe/arrow regression check meaningful.
    if (index === 0) statements.push(`insert into public.menu_items(id,organization_id,restaurant_id,branch_id,menu_category_id,name,base_price_minor,currency_code,is_active) values
      (${quote(randomUUID())},${quote(person.orgId)},${quote(person.restaurantId)},${quote(person.branchId)},${quote(categoryId)},'TEST SWIPE',1000,'ILS',true);`);
  }
  statements.push(`update public.branches set tax_enabled=false,tax_mode='exclusive' where id=${quote(person.branchId)} and organization_id=${quote(person.orgId)};`);
  statements.push(`insert into public.restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,tagline,public_city,public_phone,primary_color,accent_color,visual_preset,locale_default,card_mode,motion,pickup_enabled,opening_hours,is_published,version,hero_headline,hero_subline)
    values (${quote(person.restaurantId)},${quote(person.orgId)},${quote(person.branchId)},${quote(person.slug)},'بيانات اختبار — CINEMATIC','بيانات اختبار فقط','TEST','0520000001','#16120e','#ffb172','dark','ar','list','full',true,${quote(JSON.stringify(hours))}::jsonb,true,1,'بيانات اختبار','اختبار الخدمات المحلية فقط');`);
}
statements.push('commit;');
// Fixed container and socket, no connection URL/env password and no hosted target.
const seeded = spawnSync('docker', ['exec', '-i', 'supabase_db_RestoFlow', 'psql', '-X', '--no-password', '-h', '/var/run/postgresql', '-p', '5432', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=sqlstate'], {
  input: statements.join('\n'), encoding: 'utf8', timeout: 30_000,
});
bootstrapDiagnostics.process(seeded);
assert.equal(seeded.status, 0, 'Synthetic catalogue/profile bootstrap failed (SQL output withheld)');

// Verify the actual owner-visible rows, not just the SQL text. A global or
// foreign-branch fixture must fail setup before an unrelated uploader journey.
for (const account of [a, b]) {
  bootstrapDiagnostics.advance(account === a ? 'a_owner_list' : 'b_owner_list');
  const menu = await rpc(fixture, account.token, 'list_menu', {
    ...scope(account.person), p_branch_id: account.person.branchId,
  });
  bootstrapDiagnostics.response(menu);
  assert.equal(menu.status, 200, 'Owner must read the seeded UI catalogue');
  assert.equal(menu.data?.ok, true, 'Owner must receive the real menu envelope');
  const items = menu.data.items;
  assert.ok(Array.isArray(items) && items.length === 5
    && new Set(items.map(item => item.name)).size === 5
    && ['TEST 1', 'TEST SWIPE', 'TEST 2', 'TEST 3', 'TEST 4'].every(name => items.some(item => item.name === name))
    && items.every(item => /^(?:TEST [1-4]|TEST SWIPE)$/.test(item.name)
      && item.organization_id === account.person.orgId
      && item.restaurant_id === account.person.restaurantId
      && item.branch_id === account.person.branchId),
  'All five explicit UI items must match the owner Dashboard branch scope');
}

const sourceKey = `${a.person.orgId}/${a.person.restaurantId}/logo/${randomUUID()}.jpg`;
const image = readFileSync(resolve(repo, 'supabase/functions/storefront-media-publish/test/fixtures/gray_prog_1000x750.jpg'));
bootstrapDiagnostics.advance('private_original_upload');
const uploaded = await request(fixture, a.token, `/storage/v1/object/restaurant-logos/${storagePath(sourceKey)}`, {
  method: 'POST', bytes: image, contentType: 'image/jpeg',
});
bootstrapDiagnostics.response(uploaded);
assert.equal(uploaded.status, 200, 'Real owner must upload the initial synthetic original');
bootstrapDiagnostics.advance('receipt_logo');
const receipt = await rpc(fixture, a.token, 'set_restaurant_receipt_logo', {
  ...scope(a.person), p_client_request_id: randomUUID(), p_logo_path: sourceKey, p_enabled: true, p_expected_version: 0,
});
bootstrapDiagnostics.response(receipt);
assert.equal(receipt.status, 200);
assert.equal(receipt.data?.ok, true);
bootstrapDiagnostics.advance('fixture_hero_publish');
const published = await diagnostics.observe('fixture_hero_publish', () => request(fixture, a.token, '/functions/v1/storefront-media-publish', {
  method: 'POST', body: { request_id: randomUUID(), organization_id: a.person.orgId, restaurant_id: a.person.restaurantId,
    slot: 'hero', variant: 'w960', source_bucket: 'restaurant-logos', source_key: sourceKey, rung: 0 },
}));
bootstrapDiagnostics.response(published);
assert.equal(published.status, 200, 'Actual Edge publisher must publish the synthetic Hero');
assert.equal(published.data?.status, 'published');
assert.equal(published.data?.source_mismatch, false);
assert.equal(published.data?.media?.source_key, sourceKey);
assert.equal(published.data?.media?.variant, 'w960');
fixture.heroMediaId = published.data.media.id;
fixture.heroUrl = `${API_URL}/storage/v1/object/public/storefront-media/${published.data.media.object_key}`;
fixture.heroSourceKey = sourceKey;
fixture.receiptLogoKey = sourceKey;
bootstrapDiagnostics.advance('post_publish_fixture_finalize');
const profileRead = await rpc(fixture, a.token, 'get_restaurant_storefront_profile', scope(a.person));
assert.equal(profileRead.data?.ok, true);
const selected = await rpc(fixture, a.token, 'set_restaurant_storefront_profile', {
  ...scope(a.person), p_client_request_id: randomUUID(), p_expected_version: profileRead.data.version,
  p_patch: { hero_media_id: fixture.heroMediaId },
});
assert.equal(selected.status, 200);
assert.equal(selected.data?.ok, true);
fixture.initialInvariants = await readInvariants(fixture, a.token);
assert.equal(fixture.initialInvariants.heroMediaId, fixture.heroMediaId);
assert.equal(fixture.initialInvariants.receiptLogoKey, fixture.receiptLogoKey);
const publicImage = await request(fixture, null, new URL(fixture.heroUrl).pathname);
assert.equal(publicImage.status, 200);
assert.ok(publicImage.bytes.length > 0);
Object.assign(fixture, { orgId: a.person.orgId, restaurantId: a.person.restaurantId, branchId: a.person.branchId, slug: a.person.slug });
// Generate input files in native Node ESM, before Playwright loads its CJS
// TypeScript tests. The shared generator uses import.meta for its own fixtures.
for (const [index, [width, height]] of [[900, 450], [1000, 750]].entries()) {
  writeFileSync(resolve(dirname(target), `ux003-banner-${index}.png`),
    png({ width, height, channels: 3, rows: photoRgb(width, height, 29 + index, 8) }),
    { mode: 0o600, flag: 'wx' });
}
// Two bounded, distinct desktop inputs for the real independent-banner UI
// lifecycle. Existing historical source files and recipe goldens are unchanged.
for (const [index, [width, height]] of [[1200, 360], [1200, 480]].entries()) {
  writeFileSync(resolve(dirname(target), `responsive-banner-${index}.png`),
    png({ width, height, channels: 3, rows: photoRgb(width, height, 61 + index, 8) }),
    { mode: 0o600, flag: 'wx' });
}
// Sessions stay in memory and are not serialized. Only local passwords and the
// public anon key are handed privately to the real Dashboard sign-in test.
writeFileSync(target, `${JSON.stringify(fixture, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
chmodSync(target, 0o600);
bootstrapDiagnostics.complete();
console.log('Synthetic fixture bootstrap PASS: real Auth users A/B/outsider; real private upload and Edge-published Hero.');
