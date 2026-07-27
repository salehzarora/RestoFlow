-- ============================================================================
-- PRINT-BRANDING-LOGO-001 — pgTAP: storage.objects RLS for the restaurant-logos
-- bucket under the REAL storage context (identity from the JWT; org GUC ABSENT).
-- Read/write role matrix (org_owner/restaurant_owner/manager write; cashier/
-- kitchen/accountant/cross-tenant/anon denied), branch-member read-but-not-write,
-- INSERT/UPDATE/DELETE end-to-end, and the POS device read gate (KDS excluded).
-- Fixtures seeded by the BYPASSRLS connection; assertions run as authenticated.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(44);

-- ===================== fixtures (connection role / BYPASSRLS) ================
insert into auth.users (id, email) values
  ('b2000000-0000-0000-0000-0000000a0001', 'pbl-owner-a@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0002', 'pbl-restowner-a1@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0003', 'pbl-mgr-rest@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0004', 'pbl-mgr-branch@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0005', 'pbl-cashier@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0006', 'pbl-kitchen@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0007', 'pbl-acct@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0008', 'pbl-ownerb@ex.test'),
  ('b2000000-0000-0000-0000-0000000a0009', 'pbl-nobody@ex.test'),
  -- device principals (anonymous auth users bound to device sessions)
  ('b2000000-0000-0000-0000-0000000d0001', 'pbl-dev-pos-a@ex.test'),
  ('b2000000-0000-0000-0000-0000000d0002', 'pbl-dev-kds-a@ex.test'),
  ('b2000000-0000-0000-0000-0000000d0003', 'pbl-dev-pos-b@ex.test'),
  ('b2000000-0000-0000-0000-0000000d0004', 'pbl-dev-pos-revoked@ex.test');

insert into organizations (id, name, slug, default_currency) values
  ('b2000000-0000-0000-0000-0000000000a0', 'Org A', 'pblrls-a', 'USD'),
  ('b2000000-0000-0000-0000-0000000000b0', 'Org B', 'pblrls-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('b2000000-0000-0000-0000-0000000000b1', 'b2000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('b2000000-0000-0000-0000-0000000a1a00', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('b2000000-0000-0000-0000-0000000b1a00', 'b2000000-0000-0000-0000-0000000000b0', 'b2000000-0000-0000-0000-0000000000b1', 'Branch B1a');

insert into app_users (id, email, auth_user_id) values
  ('b2000000-0000-0000-0000-00000000ee01', 'pbl-owner-a@ex.test',      'b2000000-0000-0000-0000-0000000a0001'),
  ('b2000000-0000-0000-0000-00000000ee02', 'pbl-restowner-a1@ex.test', 'b2000000-0000-0000-0000-0000000a0002'),
  ('b2000000-0000-0000-0000-00000000ee03', 'pbl-mgr-rest@ex.test',     'b2000000-0000-0000-0000-0000000a0003'),
  ('b2000000-0000-0000-0000-00000000ee04', 'pbl-mgr-branch@ex.test',   'b2000000-0000-0000-0000-0000000a0004'),
  ('b2000000-0000-0000-0000-00000000ee05', 'pbl-cashier@ex.test',      'b2000000-0000-0000-0000-0000000a0005'),
  ('b2000000-0000-0000-0000-00000000ee06', 'pbl-kitchen@ex.test',      'b2000000-0000-0000-0000-0000000a0006'),
  ('b2000000-0000-0000-0000-00000000ee07', 'pbl-acct@ex.test',         'b2000000-0000-0000-0000-0000000a0007'),
  ('b2000000-0000-0000-0000-00000000ee08', 'pbl-ownerb@ex.test',       'b2000000-0000-0000-0000-0000000a0008'),
  ('b2000000-0000-0000-0000-00000000ee09', 'pbl-nobody@ex.test',       'b2000000-0000-0000-0000-0000000a0009');

-- org_owner(A); restaurant_owner(A1); manager restaurant-scoped(A1); manager
-- branch-scoped(A1a); cashier(org A); kitchen(org A); accountant(org A); owner(B).
insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('b2000000-0000-0000-0000-00000000ee01', 'b2000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('b2000000-0000-0000-0000-00000000ee02', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', null,                                   'restaurant_owner'),
  ('b2000000-0000-0000-0000-00000000ee03', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', null,                                   'manager'),
  ('b2000000-0000-0000-0000-00000000ee04', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('b2000000-0000-0000-0000-00000000ee05', 'b2000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'cashier'),
  ('b2000000-0000-0000-0000-00000000ee06', 'b2000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'kitchen_staff'),
  ('b2000000-0000-0000-0000-00000000ee07', 'b2000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'accountant'),
  ('b2000000-0000-0000-0000-00000000ee08', 'b2000000-0000-0000-0000-0000000000b0', null,                                   null,                                   'org_owner');

-- POS + KDS devices @ A1a with bound sessions (auth_user_id => storage binding);
-- POS @ B1a; a REVOKED POS session @ A1a.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('b2000000-0000-0000-0000-0000000d1001', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'pos', 'POS A'),
  ('b2000000-0000-0000-0000-0000000d1002', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'kds', 'KDS A'),
  ('b2000000-0000-0000-0000-0000000d1003', 'b2000000-0000-0000-0000-0000000000b0', 'b2000000-0000-0000-0000-0000000000b1', 'b2000000-0000-0000-0000-0000000b1a00', 'pos', 'POS B');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b2000000-0000-0000-0000-0000000d2001', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'b2000000-0000-0000-0000-0000000d1001', 'active'),
  ('b2000000-0000-0000-0000-0000000d2002', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'b2000000-0000-0000-0000-0000000d1002', 'active'),
  ('b2000000-0000-0000-0000-0000000d2003', 'b2000000-0000-0000-0000-0000000000b0', 'b2000000-0000-0000-0000-0000000000b1', 'b2000000-0000-0000-0000-0000000b1a00', 'b2000000-0000-0000-0000-0000000d1003', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, auth_user_id, is_active, revoked_at) values
  ('b2000000-0000-0000-0000-0000000d3001', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'b2000000-0000-0000-0000-0000000d1001', 'b2000000-0000-0000-0000-0000000d2001', 'b2000000-0000-0000-0000-0000000d0001', true,  null),
  ('b2000000-0000-0000-0000-0000000d3002', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'b2000000-0000-0000-0000-0000000d1002', 'b2000000-0000-0000-0000-0000000d2002', 'b2000000-0000-0000-0000-0000000d0002', true,  null),
  ('b2000000-0000-0000-0000-0000000d3003', 'b2000000-0000-0000-0000-0000000000b0', 'b2000000-0000-0000-0000-0000000000b1', 'b2000000-0000-0000-0000-0000000b1a00', 'b2000000-0000-0000-0000-0000000d1003', 'b2000000-0000-0000-0000-0000000d2003', 'b2000000-0000-0000-0000-0000000d0003', true,  null),
  ('b2000000-0000-0000-0000-0000000d3004', 'b2000000-0000-0000-0000-0000000000a0', 'b2000000-0000-0000-0000-0000000000a1', 'b2000000-0000-0000-0000-0000000a1a00', 'b2000000-0000-0000-0000-0000000d1001', 'b2000000-0000-0000-0000-0000000d2001', 'b2000000-0000-0000-0000-0000000d0004', false, now());

-- seed objects: one Org A logo, one Org B logo, plus update/delete-target objects.
insert into storage.objects (bucket_id, name) values
  ('restaurant-logos', 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-0000000000f1.png'), -- objA
  ('restaurant-logos', 'b2000000-0000-0000-0000-0000000000b0/b2000000-0000-0000-0000-0000000000b1/logo/b2000000-0000-0000-0000-0000000000f4.png'), -- objB
  ('restaurant-logos', 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fb1.png'), -- objUA (update)
  ('restaurant-logos', 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fc1.png'); -- objDA (delete)

set local role authenticated;
set local app.current_app_user_id = '';
set local app.current_organization_id = '';

-- ============================ A. READ VISIBILITY (13) =======================
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 1, 'org_owner CAN read own-org logo');
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f4.png')::int, 0, 'org_owner of A sees ZERO Org B logos (cross-org)');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0002","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 1, 'restaurant_owner CAN read own-restaurant logo');
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f4.png')::int, 0, 'restaurant_owner sees ZERO Org B logos');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 1, 'restaurant-scoped manager CAN read logo');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 1, 'branch-scoped manager CAN read the restaurant logo (branch members read)');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 1, 'cashier CAN read the logo');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0007","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 1, 'accountant CAN read the logo');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 0, 'kitchen_staff CANNOT read the logo (excluded)');
select is((select count(*) from storage.objects where bucket_id = 'restaurant-logos')::int, 0, 'kitchen_staff sees ZERO logos total');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0008","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png')::int, 0, 'Org B owner sees ZERO Org A logos');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0009","aal":"aal2"}';
select is((select count(*) from storage.objects where bucket_id = 'restaurant-logos')::int, 0, 'non-member sees ZERO logos');
set local role anon;
select is((select count(*) from storage.objects where bucket_id = 'restaurant-logos')::int, 0, 'anon sees ZERO logos (no anon policy)');
set local role authenticated;

-- ============================ B. HELPER MATRIX (12) =========================
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select ok(app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'org_owner CAN write');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0002","aal":"aal2"}';
select ok(app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'restaurant_owner CAN write');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select ok(app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'restaurant-scoped manager CAN write');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select ok(not app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'branch-scoped manager CANNOT write restaurant-level branding');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select ok(not app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'cashier CANNOT write');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
select ok(not app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'kitchen_staff CANNOT write');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0007","aal":"aal2"}';
select ok(not app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'accountant CANNOT write');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0009","aal":"aal2"}';
select ok(not app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'non-member CANNOT write');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select ok(not app.can_write_restaurant_logo('b2000000-0000-0000-0000-0000000000b0','b2000000-0000-0000-0000-0000000000b1'), 'Org A org_owner CANNOT write Org B branding (cross-org)');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select ok(app.can_read_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'cashier CAN read (helper)');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
select ok(not app.can_read_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'kitchen_staff CANNOT read (helper)');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select ok(app.can_read_restaurant_logo('b2000000-0000-0000-0000-0000000000a0','b2000000-0000-0000-0000-0000000000a1'), 'branch-scoped manager CAN read (helper)');

-- ============================ C. INSERT end-to-end (8) ======================
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000f05.png') $$,
  'org_owner CAN INSERT an in-scope logo');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000f06.png') $$,
  'restaurant-scoped manager CAN INSERT an in-scope logo');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fa0.png') $$,
  '42501', null, 'branch-scoped manager INSERT is denied (restaurant-level write)');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fa1.png') $$,
  '42501', null, 'cashier INSERT is denied');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fa2.png') $$,
  '42501', null, 'kitchen_staff INSERT is denied');
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','b2000000-0000-0000-0000-0000000000b0/b2000000-0000-0000-0000-0000000000b1/logo/b2000000-0000-0000-0000-000000000fa4.png') $$,
  '42501', null, 'Org A org_owner INSERT into an Org B path is denied (cross-org)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','not/a/logo-key.png') $$,
  '42501', null, 'INSERT with a malformed key is denied (parse fails => deny)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fa5.png') $$,
  '42501', null, 'a restaurant-logo-shaped key in the WRONG bucket is denied (policies do not leak)');

-- ============================ D. UPDATE end-to-end (2) ======================
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select lives_ok($$ update storage.objects
    set name = 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fb2.png'
    where name = 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fb1.png' $$,
  'org_owner CAN UPDATE (rename) a logo within writable scope');
select throws_ok($$ update storage.objects
    set name = 'b2000000-0000-0000-0000-0000000000b0/b2000000-0000-0000-0000-0000000000b1/logo/b2000000-0000-0000-0000-000000000fb3.png'
    where name = 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fb2.png' $$,
  '42501', null, 'UPDATE moving a logo to a cross-org path is denied (WITH CHECK)');

-- ============================ E. DELETE end-to-end (2) ======================
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
set local storage.allow_delete_query = 'true';
select lives_ok($$ delete from storage.objects
    where name = 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fc1.png' $$,
  'org_owner CAN DELETE a logo within writable scope');
select is((select count(*) from storage.objects
    where name = 'b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fc1.png')::int,
  0, 'the deleted logo is gone');

-- ============================ F. DEVICE READ (7) ============================
set local app.current_app_user_id = '';
set local app.current_organization_id = '';
-- live bound POS device of Org A / A1a.
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000d0001"}';
select is((select count(*)::int from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png'), 1,
  'a live POS device session CAN read its own restaurant logo');
select is((select count(*)::int from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f4.png'), 0,
  'a live POS device session CANNOT read another org logo (cross-org)');
-- KDS device: excluded (device_type pos only).
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000d0002"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'a KDS device session sees ZERO logos (device_type=pos only)');
-- Org B POS device: own-org logo visible; Org A invisible.
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000d0003"}';
select is((select count(*)::int from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f4.png'), 1,
  'the Org B POS device CAN read its own org logo (control)');
select is((select count(*)::int from storage.objects where name like '%/b2000000-0000-0000-0000-0000000000f1.png'), 0,
  'the Org B POS device sees ZERO Org A logos (cross-org)');
-- revoked POS session.
set local request.jwt.claims = '{"sub":"b2000000-0000-0000-0000-0000000d0004"}';
select is((select count(*)::int from storage.objects where bucket_id = 'restaurant-logos'), 0,
  'a revoked device session sees ZERO logos (liveness gate)');
-- a device principal cannot WRITE (no membership; no device write policy).
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('restaurant-logos','b2000000-0000-0000-0000-0000000000a0/b2000000-0000-0000-0000-0000000000a1/logo/b2000000-0000-0000-0000-000000000fd0.png') $$,
  '42501', null, 'a POS device principal CANNOT INSERT a logo (read-only device access)');

reset role;
select * from finish();
rollback;
