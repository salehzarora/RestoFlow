-- ============================================================================
-- RF-051 — pgTAP: membership resolution at session time (DOMAIN_MODEL §1.2)
-- ============================================================================
-- Through app.start_pin_session, the resolved membership follows the precedence:
--   (1) authoritative: employee_profiles.membership_id when set (even if the
--       app_user has multiple memberships — the direct link wins);
--   (2) fallback: via app_user -> membership ONLY when exactly one active
--       membership exists in the org;
--   refused (42501) when the fallback is ambiguous (>1) or empty (0 / no app_user).
-- The resolved membership is stored on the pin_session. Fixtures inserted as the
-- BYPASSRLS connection role. All memberships are org-wide (cover any branch).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(5);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'r51m-org-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');

-- users: A (membership_id set + 2 app_user memberships), B (1 membership), C (2 ambiguous)
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000000aa', 'r51m-a@example.test'),
  ('00000000-0000-0000-0000-0000000000bb', 'r51m-b@example.test'),
  ('00000000-0000-0000-0000-0000000000cc', 'r51m-c@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-0000000ab0a1', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a0', 'cashier'),       -- A authoritative target
  ('00000000-0000-0000-0000-0000000ab0a2', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a0', 'kitchen_staff'), -- A: 2nd membership (would make fallback ambiguous)
  ('00000000-0000-0000-0000-0000000ab0b1', '00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-0000000000a0', 'cashier'),       -- B: single
  ('00000000-0000-0000-0000-0000000ab0c1', '00000000-0000-0000-0000-0000000000cc', '00000000-0000-0000-0000-0000000000a0', 'cashier'),       -- C: ambiguous #1
  ('00000000-0000-0000-0000-0000000ab0c2', '00000000-0000-0000-0000-0000000000cc', '00000000-0000-0000-0000-0000000000a0', 'kitchen_staff'); -- C: ambiguous #2
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef0a0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000ab0a1', 'ref:A'),  -- authoritative
  ('00000000-0000-0000-0000-0000000ef0b0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000bb', null, 'ref:B'),                                       -- fallback (unambiguous)
  ('00000000-0000-0000-0000-0000000ef0c0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000cc', null, 'ref:C'),                                       -- fallback (ambiguous)
  ('00000000-0000-0000-0000-0000000ef0d0', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', null, null, 'ref:D');                                                                        -- empty (no app_user, no membership_id)

-- (1) authoritative membership_id is used, even though the app_user is ambiguous  1
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0a0','ref:A','opA');
select is((select resolved_membership_id from pin_sessions where local_operation_id='opA'), '00000000-0000-0000-0000-0000000ab0a1'::uuid,
  'authoritative: employee_profiles.membership_id wins (ignores ambiguous app_user fallback)');

-- (2) unambiguous fallback via app_user resolves ----------------------------- 2
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0b0','ref:B','opB');
select is((select resolved_membership_id from pin_sessions where local_operation_id='opB'), '00000000-0000-0000-0000-0000000ab0b1'::uuid,
  'fallback: a single active app_user membership resolves');

-- (3) ambiguous fallback is refused ------------------------------------------ 3
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0c0','ref:C','opC') $$, '42501', NULL,
  'ambiguous fallback (>1 active membership) is refused');

-- (4) empty resolution is refused -------------------------------------------- 4
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef0d0','ref:D','opD') $$, '42501', NULL,
  'empty resolution (no membership_id, no app_user) is refused');

-- (5) resolved_membership_id is stored on the successfully created sessions -- 5
select is((select count(*) from pin_sessions where local_operation_id in ('opA','opB') and resolved_membership_id is not null)::int, 2,
  'resolved_membership_id is stored on each created PIN session');

select * from finish();
rollback;
