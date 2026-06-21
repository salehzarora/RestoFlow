-- ============================================================================
-- RF-050 — pgTAP: MFA-assurance guard denies privileged ops without aal2
-- ============================================================================
-- AC#1: a privileged-role session that has NOT completed MFA (assurance < aal2)
-- is DENIED privileged operations. This tests the GUARD
-- (app.require_mfa_for_privileged), NOT a business RPC (none exists; RF-052+).
-- The privileged role set is the INTERIM ASSUMPTION / Q-008 set
-- (org_owner, restaurant_owner, manager); the final method/mapping is pending
-- Q-008 (D-006) and is intentionally NOT frozen here.
--
-- Coverage:
--   * ALL THREE privileged roles (org_owner, restaurant_owner, manager) are
--     DENIED at aal1 and ALLOWED at aal2;
--   * a non-privileged role (cashier) always passes;
--   * FAIL-CLOSED when no org is selected: a privileged principal is still denied;
--   * org-SCOPING: a multi-org principal privileged in Org A but a cashier in
--     Org B passes when acting in B and is denied when acting in A;
--   * the interim GUC identity path is FAIL-CLOSED for MFA (a privileged GUC-only
--     principal cannot reach aal2 without a real Supabase Auth JWT).
--
-- The principal is established the REAL way: an auth.users row + a linked
-- app_users.auth_user_id + a JWT (request.jwt.claim.sub + request.jwt.claims,
-- carrying sub + aal). Fixtures are inserted as the BYPASSRLS connection role;
-- every assertion runs under `set local role authenticated`.
-- 42501 = insufficient_privilege (same SQLSTATE as RLS WITH CHECK denials).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(21);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000a0001', 'owner-mfa@example.test'),
  ('00000000-0000-0000-0000-0000000a0002', 'cashier-mfa@example.test'),
  ('00000000-0000-0000-0000-0000000a0003', 'resto-owner-mfa@example.test'),
  ('00000000-0000-0000-0000-0000000a0004', 'manager-mfa@example.test'),
  ('00000000-0000-0000-0000-0000000a0005', 'multi-mfa@example.test');

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'mfa-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'mfa-org-b', 'EUR');

insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1'),
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B1');

insert into app_users (id, email, auth_user_id) values
  ('00000000-0000-0000-0000-00000000ee01', 'owner-mfa@example.test',       '00000000-0000-0000-0000-0000000a0001'),
  ('00000000-0000-0000-0000-00000000ee02', 'cashier-mfa@example.test',     '00000000-0000-0000-0000-0000000a0002'),
  ('00000000-0000-0000-0000-00000000ee03', 'resto-owner-mfa@example.test', '00000000-0000-0000-0000-0000000a0003'),
  ('00000000-0000-0000-0000-00000000ee04', 'manager-mfa@example.test',     '00000000-0000-0000-0000-0000000a0004'),
  ('00000000-0000-0000-0000-00000000ee05', 'multi-mfa@example.test',       '00000000-0000-0000-0000-0000000a0005');
-- guc-only privileged principal: NO auth principal (PIN-only/local).
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee06', 'guc-owner-mfa@example.test');

-- owner: org-wide org_owner (privileged). cashier: scoped to RA1 (NOT privileged).
-- resto-owner: restaurant_owner @ RA1 (privileged). manager: org-wide (privileged).
-- multi: org_owner in A AND cashier in B. guc-owner: org-wide org_owner (GUC path).
insert into memberships (app_user_id, organization_id, restaurant_id, role) values
  ('00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'cashier'),
  ('00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000a001', 'restaurant_owner'),
  ('00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', null,                                   'manager'),
  ('00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000a0', null,                                   'org_owner'),
  ('00000000-0000-0000-0000-00000000ee05', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-00000000b001', 'cashier'),
  ('00000000-0000-0000-0000-00000000ee06', '00000000-0000-0000-0000-0000000000a0', null,                                   'org_owner');

set local role authenticated;
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

-- ===== org_owner via the JWT path: sanity + deny@aal1 / allow@aal2 ==========
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal1"}';
select is(auth.uid(), '00000000-0000-0000-0000-0000000a0001'::uuid, 'owner: auth.uid() reads the JWT sub');                                    -- 1
select is(app.current_app_user_id(), '00000000-0000-0000-0000-00000000ee01'::uuid, 'owner: current_app_user_id resolves via auth_user_id');   -- 2
select is(app.current_auth_assurance_level(), 'aal1', 'owner: assurance level reads aal1 from the JWT');                                        -- 3
select is(app.current_membership_requires_mfa(), true, 'owner: org_owner is privileged (ASSUMPTION / Q-008) -> requires MFA');                  -- 4
select is(app.has_required_assurance(), false, 'owner + aal1: assurance is insufficient');                                                      -- 5
select throws_ok(
  $$ select app.require_mfa_for_privileged() $$, '42501', NULL,
  'org_owner + aal1: privileged operation is DENIED (42501) without aal2 (AC#1)');                                                              -- 6
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select is(app.has_required_assurance(), true, 'owner + aal2: assurance is sufficient');                                                         -- 7
select lives_ok(
  $$ select app.require_mfa_for_privileged() $$, 'org_owner + aal2: privileged operation is ALLOWED');                                          -- 8

-- ===== restaurant_owner: deny@aal1 / allow@aal2 =============================
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0003';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal1"}';
select throws_ok(
  $$ select app.require_mfa_for_privileged() $$, '42501', NULL,
  'restaurant_owner + aal1: privileged operation is DENIED (ASSUMPTION / Q-008)');                                                             -- 9
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0003","aal":"aal2"}';
select lives_ok(
  $$ select app.require_mfa_for_privileged() $$, 'restaurant_owner + aal2: privileged operation is ALLOWED');                                   -- 10

-- ===== manager: deny@aal1 / allow@aal2 ======================================
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0004';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0004","aal":"aal1"}';
select throws_ok(
  $$ select app.require_mfa_for_privileged() $$, '42501', NULL,
  'manager + aal1: privileged operation is DENIED (ASSUMPTION / Q-008)');                                                                      -- 11
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0004","aal":"aal2"}';
select lives_ok(
  $$ select app.require_mfa_for_privileged() $$, 'manager + aal2: privileged operation is ALLOWED');                                            -- 12

-- ===== Non-privileged principal (cashier) is never MFA-gated ================
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0002';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0002","aal":"aal1"}';
select is(app.current_membership_requires_mfa(), false, 'cashier: not a privileged role -> no MFA required (ASSUMPTION / Q-008)');              -- 13
select lives_ok(
  $$ select app.require_mfa_for_privileged() $$, 'cashier + aal1: privileged guard passes for a non-privileged role');                          -- 14

-- ===== FAIL-CLOSED: privileged principal with NO org selected ===============
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0001';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal1"}';
set local app.current_organization_id = '';
select throws_ok(
  $$ select app.require_mfa_for_privileged() $$, '42501', NULL,
  'org_owner + NO org selected + aal1: FAIL-CLOSED, privileged op DENIED');                                                                    -- 15
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0001","aal":"aal2"}';
select lives_ok(
  $$ select app.require_mfa_for_privileged() $$, 'org_owner + NO org selected + aal2: allowed');                                                -- 16

-- ===== org-SCOPING: multi-org principal (org_owner in A, cashier in B) ======
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0005';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000a0005","aal":"aal1"}';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select lives_ok(
  $$ select app.require_mfa_for_privileged() $$,
  'multi @ Org B (cashier there) + aal1: NOT privileged in the current org -> passes');                                                         -- 17
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select throws_ok(
  $$ select app.require_mfa_for_privileged() $$, '42501', NULL,
  'multi @ Org A (org_owner there) + aal1: privileged in the current org -> DENIED (org-scoping)');                                            -- 18

-- ===== interim GUC identity path is FAIL-CLOSED for MFA =====================
-- A privileged GUC-only principal (no Supabase Auth JWT) cannot reach aal2:
-- assurance reads ONLY from verified request.jwt.claims, so it is denied.
set local request.jwt.claim.sub = '';
set local request.jwt.claims = '';
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee06';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select ok(auth.uid() is null, 'GUC-only: no JWT present');                                                                                      -- 19
select is(app.current_app_user_id(), '00000000-0000-0000-0000-00000000ee06'::uuid, 'GUC-only: identity via the interim GUC fallback');          -- 20
select throws_ok(
  $$ select app.require_mfa_for_privileged() $$, '42501', NULL,
  'GUC-only privileged principal cannot reach aal2 (no verified JWT) -> FAIL-CLOSED DENY');                                                    -- 21

reset role;
select * from finish();
rollback;
