-- RF-110 -- menu image storage: storage.objects RLS behavior (DECISION D-032;
-- API_CONTRACT 4.24; SECURITY T-014; D-026; T-003/T-013). Exercises the policies
-- under the REAL storage context: identity resolves from the JWT (auth.uid() ->
-- app_users.auth_user_id) and the app ORGANIZATION GUC IS LEFT UNSET -- exactly as
-- Supabase Storage API requests behave. This proves the path-derived helpers gate
-- access correctly WITHOUT the org GUC (and, in dedicated tests, while the org GUC
-- holds the WRONG org -- which would defeat the legacy has_role_in_scope helper).
--
-- Coverage: read visibility across the role/scope matrix (org / restaurant / branch
-- members, sibling-branch isolation, cross-restaurant, cross-org, kitchen exclusion,
-- platform-admin-only, non-member, anon); the can_read / can_write helper matrix
-- (role gates + menu_item existence + scope + org-GUC independence); and end-to-end
-- INSERT / UPDATE / DELETE (allow + deny, path-move denial, wrong bucket).
-- Fixtures are seeded by the BYPASSRLS connection; assertions run as authenticated.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(55);

-- ===================== fixtures (connection role / BYPASSRLS) =====================
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0001', 'rf110-owner-a@ex.test'),
  ('00000000-0000-0000-0000-0000000a0002', 'rf110-restowner-a1@ex.test'),
  ('00000000-0000-0000-0000-0000000a0003', 'rf110-mgr-a1a@ex.test'),
  ('00000000-0000-0000-0000-0000000a0004', 'rf110-cashier-a1a@ex.test'),
  ('00000000-0000-0000-0000-0000000a0005', 'rf110-kitchen-a1a@ex.test'),
  ('00000000-0000-0000-0000-0000000a0006', 'rf110-acct-a@ex.test'),
  ('00000000-0000-0000-0000-0000000a0007', 'rf110-cashier-b@ex.test'),
  ('00000000-0000-0000-0000-0000000a0008', 'rf110-platadmin@ex.test'),
  ('00000000-0000-0000-0000-0000000a0009', 'rf110-nobody@ex.test');

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf110rls-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf110rls-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1b'),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1a');

insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf110-owner-a@ex.test',      '00000000-0000-0000-0000-0000000a0001'),
  ('00000000-0000-0000-0000-00000000ee02', 'rf110-restowner-a1@ex.test', '00000000-0000-0000-0000-0000000a0002'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf110-mgr-a1a@ex.test',      '00000000-0000-0000-0000-0000000a0003'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf110-cashier-a1a@ex.test',  '00000000-0000-0000-0000-0000000a0004'),
  ('00000000-0000-0000-0000-00000000ee05', 'rf110-kitchen-a1a@ex.test',  '00000000-0000-0000-0000-0000000a0005'),
  ('00000000-0000-0000-0000-00000000ee06', 'rf110-acct-a@ex.test',       '00000000-0000-0000-0000-0000000a0006'),
  ('00000000-0000-0000-0000-00000000ee07', 'rf110-cashier-b@ex.test',    '00000000-0000-0000-0000-0000000a0007'),
  ('00000000-0000-0000-0000-00000000ee08', 'rf110-platadmin@ex.test',    '00000000-0000-0000-0000-0000000a0008'),
  ('00000000-0000-0000-0000-00000000ee09', 'rf110-nobody@ex.test',       '00000000-0000-0000-0000-0000000a0009');

-- memberships: org-scoped owner/accountant; restaurant-scoped restaurant_owner;
-- branch-scoped manager/cashier/kitchen; org-scoped cashier in Org B.
insert into memberships (app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null,                                   'restaurant_owner'),
  ('00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'manager'),
  ('00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'cashier'),
  ('00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-00000000ee06', '00000000-0000-0000-0000-0000000000a0', null,                                   null,                                   'accountant'),
  ('00000000-0000-0000-0000-00000000ee07', '00000000-0000-0000-0000-0000000000b0', null,                                   null,                                   'cashier');

-- platform-admin-only principal (NO tenant membership) -- D-026
insert into platform_admin_grants (app_user_id, granted_by) values
  ('00000000-0000-0000-0000-00000000ee08', '00000000-0000-0000-0000-00000000ee08');

insert into menu_categories (id, organization_id, restaurant_id, branch_id, name) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', 'Cat A'),
  ('00000000-0000-0000-0000-00000000cb01', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', 'Cat B');
-- items: A1a (branch), A1b (sibling branch), restaurant-scoped (branch null), A2, B1.
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code) values
  ('00000000-0000-0000-0000-00000000da01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000ca01', 'Item A1a',  1500, 'USD'),
  ('00000000-0000-0000-0000-00000000db01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-00000000ca01', 'Item A1b',  1600, 'USD'),
  ('00000000-0000-0000-0000-00000000dab1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null,                                   '00000000-0000-0000-0000-00000000ca01', 'Item Rest', 1700, 'USD'),
  ('00000000-0000-0000-0000-00000000da21', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a2', null,                                   '00000000-0000-0000-0000-00000000ca01', 'Item A2',   1800, 'USD'),
  ('00000000-0000-0000-0000-00000000d0b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000cb01', 'Item B1',   2000, 'EUR');

-- a second bucket to prove the menu-images policies do not leak to other buckets.
insert into storage.buckets (id, name) values ('rf110-other', 'rf110-other') on conflict do nothing;

-- seed objects (BYPASSRLS) used by the read / update / delete tests.
insert into storage.objects (bucket_id, name) values
  ('menu-images', '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png'), -- objA1a
  ('menu-images', '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/global/menu_item/00000000-0000-0000-0000-00000000dab1/00000000-0000-0000-0000-000000000f02.png'),                                  -- objRest
  ('menu-images', '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1b00/menu_item/00000000-0000-0000-0000-00000000db01/00000000-0000-0000-0000-000000000f03.png'), -- objA1b
  ('menu-images', '00000000-0000-0000-0000-0000000000b0/00000000-0000-0000-0000-0000000000b1/00000000-0000-0000-0000-0000000b1a00/menu_item/00000000-0000-0000-0000-00000000d0b1/00000000-0000-0000-0000-000000000f04.png'), -- objB1
  ('menu-images', '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fb1.png'), -- objUA (update-allowed)
  ('menu-images', '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fb3.png'), -- objUA2 (cross-org move denial)
  ('menu-images', '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fb4.png'), -- objUA3 (sibling move denial)
  ('menu-images', '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fc1.png'); -- objDA (delete-allowed)

set local role authenticated;
set local app.current_app_user_id = '';          -- identity must come from the JWT only
set local app.current_organization_id = '';       -- org GUC ABSENT, exactly like the storage context
-- NOTE: the JWTs below carry "aal":"aal2" only for realism. D-032 intentionally gates
-- storage writes on ROLE + SCOPE + menu_item existence ONLY -- NOT on MFA assurance
-- (assurance stays the concern of the privileged RPC layer, as in RF-109). aal2 here
-- is therefore not load-bearing; an aal1 writer in the same scope would be allowed too.

-- ============================ A. READ VISIBILITY (23) ============================
-- org_owner (org-wide): sees every Org A image; never Org B.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 1, 'org_owner CAN read branch-A1a image');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000db01/00000000-0000-0000-0000-000000000f03.png')::int, 1, 'org_owner CAN read branch-A1b image (org-wide)');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000dab1/00000000-0000-0000-0000-000000000f02.png')::int, 1, 'org_owner CAN read restaurant-scoped (global) image');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000d0b1/00000000-0000-0000-0000-000000000f04.png')::int, 0, 'org_owner of Org A sees ZERO Org B images (cross-org)');

-- restaurant_owner (restaurant A1): every branch within A1 + global; never Org B.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0002","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 1, 'restaurant_owner CAN read branch-A1a image');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000db01/00000000-0000-0000-0000-000000000f03.png')::int, 1, 'restaurant_owner CAN read branch-A1b image (restaurant-wide)');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000dab1/00000000-0000-0000-0000-000000000f02.png')::int, 1, 'restaurant_owner CAN read restaurant-scoped (global) image');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000d0b1/00000000-0000-0000-0000-000000000f04.png')::int, 0, 'restaurant_owner sees ZERO Org B images');

-- branch manager (A1a): own branch + global; NOT the sibling branch; NOT Org B.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 1, 'branch-A1a manager CAN read own-branch image');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000dab1/00000000-0000-0000-0000-000000000f02.png')::int, 1, 'branch-A1a manager CAN read restaurant-scoped (global) image');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000db01/00000000-0000-0000-0000-000000000f03.png')::int, 0, 'branch-A1a manager CANNOT read sibling-branch (A1b) image');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000d0b1/00000000-0000-0000-0000-000000000f04.png')::int, 0, 'branch-A1a manager sees ZERO Org B images');

-- branch cashier (A1a): a price-capable reader; own branch yes, sibling no.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 1, 'branch-A1a cashier CAN read own-branch image (price-capable)');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000db01/00000000-0000-0000-0000-000000000f03.png')::int, 0, 'branch-A1a cashier CANNOT read sibling-branch image');

-- accountant (org): a price-capable reader.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 1, 'accountant CAN read menu image (price-capable role)');

-- kitchen_staff: EXCLUDED from every menu image (T-003/T-014).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 0, 'kitchen_staff CANNOT read own-branch menu image (T-014)');
select is((select count(*) from storage.objects where bucket_id = 'menu-images')::int, 0, 'kitchen_staff sees ZERO menu images total (kitchen exclusion)');

-- platform-admin-only principal: NOT a tenant bypass (D-026).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0008","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 0, 'platform-admin-only principal sees ZERO menu images (D-026)');

-- non-member: deny-by-default.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0009","aal":"aal2"}';
select is((select count(*) from storage.objects where bucket_id = 'menu-images')::int, 0, 'non-member principal sees ZERO menu images');

-- Org B cashier: own-org image visible; Org A invisible.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0007","aal":"aal2"}';
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 0, 'Org B cashier sees ZERO Org A images (cross-org)');
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000d0b1/00000000-0000-0000-0000-000000000f04.png')::int, 1, 'Org B cashier CAN read own-org image (control)');

-- anon: no anon policy => denied.
set local role anon;
select is((select count(*) from storage.objects where bucket_id = 'menu-images')::int, 0, 'anon sees ZERO menu images (no anon policy; no public read)');
set local role authenticated;

-- org-GUC INDEPENDENCE: org_owner with the WRONG org in the GUC still reads correctly
-- (path-derived). The legacy org-GUC helper would deny here -- proven in the matrix.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';  -- WRONG org
select is((select count(*) from storage.objects where name like '%/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f01.png')::int, 1, 'org_owner reads correctly even with the WRONG org GUC (path-derived, not GUC-pinned)');
set local app.current_organization_id = '';

-- ========================= B. HELPER MATRIX (17) =========================
-- can_write role gate on the in-scope item A1a.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select ok(app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'org_owner CAN write in scope');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0002","aal":"aal2"}';
select ok(app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'restaurant_owner CAN write in scope');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select ok(app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'manager CAN write in scope');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'cashier CANNOT write');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'kitchen_staff CANNOT write');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'accountant CANNOT write (read-only)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0008","aal":"aal2"}';
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'platform-admin-only CANNOT write (D-026)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0009","aal":"aal2"}';
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da01'), 'non-member CANNOT write');

-- can_write scope + menu_item existence.
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','00000000-0000-0000-0000-00000000da99'), 'org_owner CANNOT write a non-existent menu_item (existence gate)');
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000b0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000b1a00','00000000-0000-0000-0000-00000000d0b1'), 'Org A org_owner CANNOT write into Org B scope (cross-org)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a2',null,'00000000-0000-0000-0000-00000000da21'), 'branch manager CANNOT write a different restaurant (A2)');
select ok(not app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1b00','00000000-0000-0000-0000-00000000db01'), 'branch-A1a manager CANNOT write the sibling branch (A1b)');
select ok(app.can_write_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1',null,'00000000-0000-0000-0000-00000000dab1'), 'branch-A1a manager CAN write a restaurant-scoped (global) item');

-- can_read role gate (kitchen excluded; accountant allowed).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select ok(not app.can_read_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'), 'kitchen_staff CANNOT read (T-014)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0006","aal":"aal2"}';
select ok(app.can_read_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'), 'accountant CAN read (price-capable)');

-- org-GUC independence, helper level: the path-derived helper passes while the
-- legacy org-GUC helper FAILS (the exact reason D-032 mandates new helpers).
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';  -- WRONG org
select ok(app.can_read_menu_image('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00'), 'path-derived can_read_menu_image PASSES with a wrong/foreign org GUC');
select ok(not app.has_role_in_scope('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000a1a00','org_owner'), 'legacy has_role_in_scope FAILS in the same context (why D-032 needs path-derived helpers)');
set local app.current_organization_id = '';

-- ========================= C. INSERT end-to-end (10) =========================
-- allowed writers
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f05.png') $$,
  'org_owner CAN INSERT an in-scope menu image');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000f06.png') $$,
  'branch manager CAN INSERT an in-scope (own-branch) menu image');
-- denied writers
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fa1.png') $$,
  '42501', NULL, 'cashier INSERT is denied (write role)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0005","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fa2.png') $$,
  '42501', NULL, 'kitchen_staff INSERT is denied');
-- existence + scope denials (org_owner cannot escape the parsed scope)
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da99/00000000-0000-0000-0000-000000000fa3.png') $$,
  '42501', NULL, 'INSERT for a non-existent menu_item is denied (existence gate)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000b0/00000000-0000-0000-0000-0000000000b1/00000000-0000-0000-0000-0000000b1a00/menu_item/00000000-0000-0000-0000-00000000d0b1/00000000-0000-0000-0000-000000000fa4.png') $$,
  '42501', NULL, 'Org A org_owner INSERT into an Org B path is denied (cross-org)');
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a2/global/menu_item/00000000-0000-0000-0000-00000000da21/00000000-0000-0000-0000-000000000fa5.png') $$,
  '42501', NULL, 'manager INSERT into a different restaurant (A2) path is denied');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1b00/menu_item/00000000-0000-0000-0000-00000000db01/00000000-0000-0000-0000-000000000fa6.png') $$,
  '42501', NULL, 'branch-A1a manager INSERT into the sibling-branch (A1b) path is denied');
-- malformed path + wrong bucket
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('menu-images','not/a/valid/menu-image-key.png') $$,
  '42501', NULL, 'INSERT with a malformed key is denied (scope parse fails -> deny)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('rf110-other','00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fa7.png') $$,
  '42501', NULL, 'INSERT into a different bucket is denied (menu-images policies do not leak)');

-- ========================= D. UPDATE end-to-end (3) =========================
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
-- in-scope rename (same item, new image id) is allowed
select lives_ok($$ update storage.objects
    set name = '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fb2.png'
    where name = '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fb1.png' $$,
  'org_owner CAN UPDATE (rename) an image within writable scope');
-- moving to a cross-org path is denied (WITH CHECK on the new path)
select throws_ok($$ update storage.objects
    set name = '00000000-0000-0000-0000-0000000000b0/00000000-0000-0000-0000-0000000000b1/00000000-0000-0000-0000-0000000b1a00/menu_item/00000000-0000-0000-0000-00000000d0b1/00000000-0000-0000-0000-000000000fb3.png'
    where name = '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fb3.png' $$,
  '42501', NULL, 'UPDATE that moves an image to a cross-org path is denied');
-- manager moving own-branch image to the sibling branch is denied
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select throws_ok($$ update storage.objects
    set name = '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1b00/menu_item/00000000-0000-0000-0000-00000000db01/00000000-0000-0000-0000-000000000fb4.png'
    where name = '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fb4.png' $$,
  '42501', NULL, 'manager UPDATE that moves an image to the sibling branch is denied');

-- ========================= E. DELETE end-to-end (2) =========================
-- (denial is covered by the can_write matrix above, which the DELETE policy reuses)
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
set local storage.allow_delete_query = 'true';   -- pass storage.protect_delete; RLS still applies
select lives_ok($$ delete from storage.objects
    where name = '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fc1.png' $$,
  'org_owner CAN DELETE an image within writable scope');
select is((select count(*) from storage.objects
    where name = '00000000-0000-0000-0000-0000000000a0/00000000-0000-0000-0000-0000000000a1/00000000-0000-0000-0000-0000000a1a00/menu_item/00000000-0000-0000-0000-00000000da01/00000000-0000-0000-0000-000000000fc1.png')::int,
  0, 'the deleted image is gone');

reset role;
select * from finish();
rollback;
