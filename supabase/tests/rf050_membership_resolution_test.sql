-- ============================================================================
-- RF-050 — pgTAP: membership resolved at session time via the auth principal (AC#3)
-- ============================================================================
-- AC#3: membership is resolved at SESSION TIME, server-side, from the
-- authenticated principal — never from a client-supplied tenant identity.
-- Proves the REAL JWT path:
--   * auth.uid() -> app_users.auth_user_id -> app_users.id (current_app_user_id);
--   * the active org is derived from a validated membership (current_org_id);
--   * the principal sees ONLY its in-scope rows; out-of-scope (other org) data
--     is invisible; selecting a non-member org yields zero rows (deny-by-default).
-- Plus REGRESSIONS:
--   * NO JWT => the interim GUC fallback still drives identity/RLS, so the
--     RF-014/015/016/017/019 GUC suites remain green;
--   * RF050-B1 (the key security regression): a JWT principal that EXISTS in
--     auth.users but is UNLINKED to any app_user must resolve to NULL
--     (deny-by-default) and must NEVER fall back to the GUC, even when the GUC
--     names a valid app_user.
-- Fixtures inserted as the BYPASSRLS connection role; assertions run as
-- `authenticated`.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(14);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0001', 'owner-res@example.test'),
  -- a real auth principal that is deliberately NOT linked to any app_user (RF050-B1)
  ('00000000-0000-0000-0000-0000000a0009', 'unlinked-res@example.test');

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'res-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'res-org-b', 'EUR');

insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1'),
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B1');

-- owner: linked to the auth principal, org_owner in Org A ONLY.
insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee01', 'owner-res@example.test', '00000000-0000-0000-0000-0000000a0001');
-- guc-only user: NO auth principal; org_owner in Org A (drives the GUC regression).
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee02', 'guc-only@example.test');

insert into memberships (app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', 'org_owner'),
  ('00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', 'org_owner');

set local role authenticated;

-- ===== JWT path: membership resolved at session time from auth.uid() ========
-- The user-identity GUC is explicitly EMPTY here, so identity can ONLY come from
-- the JWT principal (auth.uid()) — proving the JWT path is functional, not merely
-- present behind a GUC crutch.
set local app.current_app_user_id = '';
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select is(auth.uid(), '00000000-0000-0000-0000-0000000a0001'::uuid, 'JWT path: auth.uid() reads the sub claim');                                  -- 1
select is(app.current_app_user_id(), '00000000-0000-0000-0000-00000000ee01'::uuid, 'JWT path: current_app_user_id resolves via auth_user_id');   -- 2
select is(app.current_org_id(), '00000000-0000-0000-0000-0000000000a0'::uuid, 'JWT path: org resolved server-side from the membership (not client-trusted)'); -- 3
select is((select count(*) from restaurants)::int, 1, 'JWT path: owner sees only Org A restaurants');                                            -- 4
select is((select count(*) from restaurants where id = '00000000-0000-0000-0000-00000000b001')::int, 0, 'JWT path: owner CANNOT see Org B (out-of-scope) data'); -- 5
select is((select count(*) from memberships where app_user_id = '00000000-0000-0000-0000-00000000ee01')::int, 1, 'JWT path: owner sees its own membership'); -- 6

-- select an org the principal is NOT a member of => deny-by-default
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from restaurants)::int, 0, 'JWT path: selecting a non-member org yields zero rows (server-side scope, never client-asserted)'); -- 7

-- ===== Regression: no JWT => interim GUC fallback still drives identity/RLS ==
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '';
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee02';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select ok(auth.uid() is null, 'GUC path: no JWT present => auth.uid() is NULL');                                                                  -- 8
select is(app.current_app_user_id(), '00000000-0000-0000-0000-00000000ee02'::uuid, 'GUC path: current_app_user_id falls back to the interim GUC'); -- 9
select is((select count(*) from restaurants)::int, 1, 'GUC path: the interim GUC still resolves membership scope (RF-014/015/016/017/019 suites stay green)'); -- 10

-- ===== RF050-B1: JWT present but UNLINKED auth user must NOT fall back to GUC =
-- A JWT whose sub EXISTS in auth.users but has NO app_users.auth_user_id link
-- must resolve to NULL (deny-by-default), even while the interim GUC names a
-- valid app_user. An authenticated-but-unlinked principal feeds tenant RLS and
-- MUST fail closed — it must NOT resolve to the GUC user while a JWT exists.
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee02';  -- a VALID app_user sits in the GUC
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0009';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0009","aal":"aal2"}';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select ok(auth.uid() is not null, 'unlinked JWT: a real auth principal IS present (auth.uid() not null)');                                          -- 11
select ok(app.current_app_user_id() is null,
  'JWT present but unlinked auth user must not fall back to GUC (resolves to NULL, not the GUC user)');                                              -- 12
select is((select count(*) from restaurants)::int, 0,
  'unlinked JWT: deny-by-default — zero tenant rows visible (does NOT see the GUC user''s org)');                                                   -- 13
select is((select count(*) from memberships)::int, 0,
  'unlinked JWT: deny-by-default — zero membership rows visible');                                                                                  -- 14

reset role;
select * from finish();
rollback;
