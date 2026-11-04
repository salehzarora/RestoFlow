// Fixture creation only. No privileged client is used by owner acceptance.
// SQL is limited to synthetic catalogue/profile prerequisites in the CI-local DB.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { API_URL, assertAnonKey, assertEphemeralEnvironment, fixturePath, request, rpc, scope, storagePath, readInvariants } from './service.mjs';
import { createPublisherDiagnostics, waitForAuthenticatedPublisher } from './publisher-diagnostics.mjs';

assertEphemeralEnvironment();
const target = fixturePath();
assert.ok(process.env.CINEMATIC_STATUS_FILE, 'Private local CLI status file is required');
const status = JSON.parse(readFileSync(process.env.CINEMATIC_STATUS_FILE, 'utf8'));
assert.equal(status.API_URL, API_URL, 'CLI must identify the ephemeral loopback gateway');
const fixture = { apiUrl: API_URL, anonKey: assertAnonKey(status.ANON_KEY) };
const diagnostics = createPublisherDiagnostics(process.env.CINEMATIC_ARTIFACT_DIR);
const repo = fileURLToPath(new URL('../../', import.meta.url));
const stamp = randomUUID().slice(0, 8);

async function principal(label) {
  const person = { email: `cinematic-${label}-${stamp}@example.test`, password: `${randomBytes(24).toString('base64url')}aA1!` };
  const signup = await request(fixture, null, '/auth/v1/signup', { method: 'POST', body: person });
  assert.equal(signup.status, 200, `Synthetic ${label} signup must succeed`);
  assert.equal(typeof signup.data?.access_token, 'string', 'Local signup must return a real Auth session');
  assert.match(signup.data?.user?.id || '', /^[0-9a-f-]{36}$/);
  person.authUserId = signup.data.user.id;
  return { person, token: signup.data.access_token };
}

async function owner(label) {
  const account = await principal(label);
  const slug = `cinematic-test-${label}-${stamp}`;
  const created = await rpc(fixture, account.token, 'create_organization', {
    p_client_request_id: randomUUID(), p_organization_name: `CINEMATIC TEST ${label.toUpperCase()}`,
    p_organization_slug: slug, p_restaurant_name: `بيانات اختبار ${label.toUpperCase()}`,
    p_branch_name: `TEST ${label.toUpperCase()}`, p_currency_code: 'ILS', p_timezone: 'UTC',
    p_default_station_name: null,
  });
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
await waitForAuthenticatedPublisher(fixture, a.token, diagnostics);

const quote = (value) => `'${String(value).replaceAll("'", "''")}'`;
// Use editor-valid hours: closing at midnight would touch the next day's
// opening and correctly block an unrelated profile edit (Q-038). The brief
// closed minute is harmless: this journey neither orders nor requires open_now.
const hours = JSON.parse(readFileSync(new URL('./profile-hours.json', import.meta.url), 'utf8'));
const statements = ['begin;'];
for (const person of [a.person, b.person]) {
  for (const [index, name] of ['وجبات اختبار', 'مقبلات اختبار', 'كاسات اختبار', 'مشروبات اختبار'].entries()) {
    const categoryId = randomUUID();
    statements.push(`insert into public.menu_categories(id,organization_id,restaurant_id,name,display_order,is_active) values
      (${quote(categoryId)},${quote(person.orgId)},${quote(person.restaurantId)},${quote(name)},${index},true);`);
    statements.push(`insert into public.menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code,is_active) values
      (${quote(randomUUID())},${quote(person.orgId)},${quote(person.restaurantId)},${quote(categoryId)},${quote(`TEST ${index + 1}`)},1000,'ILS',true);`);
  }
  statements.push(`update public.branches set tax_enabled=false,tax_mode='exclusive' where id=${quote(person.branchId)} and organization_id=${quote(person.orgId)};`);
  statements.push(`insert into public.restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,tagline,public_city,public_phone,primary_color,accent_color,visual_preset,locale_default,card_mode,motion,pickup_enabled,opening_hours,is_published,version,hero_headline,hero_subline)
    values (${quote(person.restaurantId)},${quote(person.orgId)},${quote(person.branchId)},${quote(person.slug)},'بيانات اختبار — CINEMATIC','بيانات اختبار فقط','TEST','0520000001','#16120e','#ffb172','dark','ar','list','full',true,${quote(JSON.stringify(hours))}::jsonb,true,1,'بيانات اختبار','اختبار الخدمات المحلية فقط');`);
}
statements.push('commit;');
// Fixed container and socket, no connection URL/env password and no hosted target.
const seeded = spawnSync('docker', ['exec', '-i', 'supabase_db_RestoFlow', 'psql', '-X', '--no-password', '-h', '/var/run/postgresql', '-p', '5432', '-U', 'supabase_admin', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], {
  input: statements.join('\n'), encoding: 'utf8', timeout: 30_000,
});
assert.equal(seeded.status, 0, 'Synthetic catalogue/profile bootstrap failed (SQL output withheld)');

const sourceKey = `${a.person.orgId}/${a.person.restaurantId}/logo/${randomUUID()}.jpg`;
const image = readFileSync(resolve(repo, 'supabase/functions/storefront-media-publish/test/fixtures/gray_prog_1000x750.jpg'));
const uploaded = await request(fixture, a.token, `/storage/v1/object/restaurant-logos/${storagePath(sourceKey)}`, {
  method: 'POST', bytes: image, contentType: 'image/jpeg',
});
assert.equal(uploaded.status, 200, 'Real owner must upload the initial synthetic original');
const receipt = await rpc(fixture, a.token, 'set_restaurant_receipt_logo', {
  ...scope(a.person), p_client_request_id: randomUUID(), p_logo_path: sourceKey, p_enabled: true, p_expected_version: 0,
});
assert.equal(receipt.status, 200);
assert.equal(receipt.data?.ok, true);
const published = await diagnostics.observe('fixture_hero_publish', () => request(fixture, a.token, '/functions/v1/storefront-media-publish', {
  method: 'POST', body: { request_id: randomUUID(), organization_id: a.person.orgId, restaurant_id: a.person.restaurantId,
    slot: 'hero', variant: 'w960', source_bucket: 'restaurant-logos', source_key: sourceKey, rung: 0 },
}));
assert.equal(published.status, 200, 'Actual Edge publisher must publish the synthetic Hero');
assert.equal(published.data?.status, 'published');
assert.equal(published.data?.source_mismatch, false);
assert.equal(published.data?.media?.source_key, sourceKey);
assert.equal(published.data?.media?.variant, 'w960');
fixture.heroMediaId = published.data.media.id;
fixture.heroUrl = `${API_URL}/storage/v1/object/public/storefront-media/${published.data.media.object_key}`;
fixture.heroSourceKey = sourceKey;
fixture.receiptLogoKey = sourceKey;
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
// Sessions stay in memory and are not serialized. Only local passwords and the
// public anon key are handed privately to the real Dashboard sign-in test.
writeFileSync(target, `${JSON.stringify(fixture, null, 2)}\n`, { mode: 0o600, flag: 'wx' });
chmodSync(target, 0o600);
console.log('Synthetic fixture bootstrap PASS: real Auth users A/B/outsider; real private upload and Edge-published Hero.');
