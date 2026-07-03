-- ============================================================================
-- MVP staff + PIN provisioning -- pgTAP: create_staff_member / set_employee_pin
-- / list_staff / list_device_staff + the PRODUCTION bcrypt verifier end-to-end.
-- ============================================================================
-- Covers (D-004/D-006/D-011/D-013, SECURITY §9, RF-112 authorization pattern):
--   * org_owner creates staff (synthetic RFC-2606 .invalid identifier email +
--     active membership + profile, NO pin yet); manager creates a cashier;
--     manager CANNOT create a manager (strict outrank, audited denial);
--     cashier denied; cross-org 42501; non-operator role 42501.
--   * set_employee_pin stores a SERVER-SIDE bcrypt ref (never the raw pin);
--     invalid format -> invalid_pin; cashier denied (audited); cross-org 42501.
--   * end-to-end on a paired device: the CORRECT typed pin opens a pin_session;
--     a WRONG pin returns null + increments pin_attempt_states; a LEGACY
--     plaintext (non-bcrypt) ref NO LONGER verifies (interim seam is dead);
--     rotating the pin deletes the attempt/lockout rows and the NEW pin works.
--   * list_staff: has_pin boolean only (never the ref); scope filter; cashier
--     permission_denied; cross-org 42501.
--   * list_device_staff: token-proven (RF-161 pattern); names+roles ONLY (no
--     email / employee_number / pin keys); branch coverage; wrong token ->
--     invalid_session.
--   * idempotent replays of create_staff_member/set_employee_pin return the
--     stored result WITHOUT duplicating/re-mutating; the ledger + audit rows
--     carry NO pin material.
-- Fixtures inserted as the BYPASSRLS connection role (rf112/rf161 harness);
-- management RPCs run as `authenticated` + the app.current_app_user_id GUC
-- (GUC-free org resolution: app.current_organization_id is NEVER set); the
-- device list runs as an ANONYMOUS authenticated principal (GUC '').
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(49);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-00000005aa00', 'Org A', 'mvpstaff-a', 'USD'),
  ('00000000-0000-0000-0000-00000005ab00', 'Org B', 'mvpstaff-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa00', 'Rest A1'),
  ('00000000-0000-0000-0000-00000005ab11', '00000000-0000-0000-0000-00000005ab00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000005aa1a', '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', 'Branch A1a'),
  ('00000000-0000-0000-0000-00000005aa1b', '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', 'Branch A1b'),
  ('00000000-0000-0000-0000-00000005ab1a', '00000000-0000-0000-0000-00000005ab00', '00000000-0000-0000-0000-00000005ab11', 'Branch B1a');
-- actors: org_owner A (org-wide), manager A (@A1/A1a), cashier A (@A1/A1a), org_owner B
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000005ae01', 'mvpstaff-owner-a@example.test'),
  ('00000000-0000-0000-0000-00000005ae02', 'mvpstaff-manager-a@example.test'),
  ('00000000-0000-0000-0000-00000005ae03', 'mvpstaff-cashier-a@example.test'),
  ('00000000-0000-0000-0000-00000005ae0b', 'mvpstaff-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000005af01', '00000000-0000-0000-0000-00000005ae01', '00000000-0000-0000-0000-00000005aa00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00000005af02', '00000000-0000-0000-0000-00000005ae02', '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a', 'manager'),
  ('00000000-0000-0000-0000-00000005af03', '00000000-0000-0000-0000-00000005ae03', '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a', 'cashier'),
  ('00000000-0000-0000-0000-00000005af0b', '00000000-0000-0000-0000-00000005ae0b', '00000000-0000-0000-0000-00000005ab00', null, null, 'org_owner');
-- paired device with a LIVE token-proven session at Branch A1a (RF-161 shape):
-- active pairing + active session; session_token_ref = sha256 of the raw token.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('00000000-0000-0000-0000-00000005ad01', '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a', 'pos', 'Front POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000005ad11', '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a', '00000000-0000-0000-0000-00000005ad01', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active) values
  ('00000000-0000-0000-0000-00000005ad51', '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a', '00000000-0000-0000-0000-00000005ad01', '00000000-0000-0000-0000-00000005ad11', app.hash_provisioning_secret('tok-mvp-staff'), true);

-- captured RPC results (readable/writable by the authenticated harness role)
create temp table _res (label text primary key, r jsonb);
grant select, insert on _res to authenticated;

-- ============================================================================
-- A. create_staff_member -- role matrix + tenant isolation (1-11)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae01';  -- org_owner A

insert into _res values ('alice', app.create_staff_member('00000000-0000-0000-0000-00000005ac01',
  '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
  'Alice Cashier', 'cashier'));
select is((select r ->> 'ok' from _res where label = 'alice'), 'true',
  'org_owner creates a branch cashier (ok:true)');                                                              -- 1

insert into _res values ('carol', app.create_staff_member('00000000-0000-0000-0000-00000005ac02',
  '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1b',
  'Carol Kitchen', 'kitchen_staff'));
select is((select r ->> 'ok' from _res where label = 'carol'), 'true',
  'org_owner creates a kitchen_staff in a SIBLING branch (A1b)');                                               -- 2

-- non-operator role is structurally rejected (org_owner is never PIN-only staff)
select throws_ok($$
  select app.create_staff_member('00000000-0000-0000-0000-00000005ac03',
    '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
    'Oscar Owner', 'org_owner')
$$, '42501', NULL, 'org_owner is not a creatable staff role (42501)');                                          -- 3

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae02';  -- manager @ A1a
-- exercised via the PUBLIC wrapper (Data-API surface)
insert into _res values ('bob', public.create_staff_member('00000000-0000-0000-0000-00000005ac04',
  '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
  'Bob Cashier', 'cashier'));
select is((select r ->> 'ok' from _res where label = 'bob'), 'true',
  'manager creates a cashier in its own branch (via the public wrapper)');                                      -- 4
select is((app.create_staff_member('00000000-0000-0000-0000-00000005ac05',
    '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
    'Mallory Manager', 'manager') ->> 'error'), 'permission_denied',
  'manager CANNOT create a manager (strict outrank -> permission_denied)');                                     -- 5

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae03';  -- cashier @ A1a
select is((app.create_staff_member('00000000-0000-0000-0000-00000005ac06',
    '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
    'Kim Kitchen', 'kitchen_staff') ->> 'error'), 'permission_denied',
  'cashier cannot create staff (rank 1 -> permission_denied)');                                                 -- 6

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae0b';  -- org_owner of ORG B
select throws_ok($$
  select app.create_staff_member('00000000-0000-0000-0000-00000005ac07',
    '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
    'Eve Intruder', 'cashier')
$$, '42501', NULL, 'Org B owner cannot create staff in Org A (cross-org IDOR; 42501)');                         -- 7

-- ---- DB-state + audit verification (as the BYPASSRLS owner) ----------------
reset role;
select ok(
  (select au.email from app_users au
    where au.id = (select (r ->> 'app_user_id')::uuid from _res where label = 'alice'))
  like 'staff-%@pin.restoflow.invalid',
  'the PIN-only operator gets a synthetic RFC-2606 .invalid identifier email');                                 -- 8
select ok(exists (
    select 1 from memberships m
    where m.id = (select (r ->> 'membership_id')::uuid from _res where label = 'alice')
      and m.organization_id = '00000000-0000-0000-0000-00000005aa00'
      and m.restaurant_id   = '00000000-0000-0000-0000-00000005aa11'
      and m.branch_id       = '00000000-0000-0000-0000-00000005aa1a'
      and m.role = 'cashier' and m.status = 'active' and m.deleted_at is null),
  'an ACTIVE branch-scoped cashier membership was created for the operator');                                   -- 9
select ok(exists (
    select 1 from employee_profiles ep
    where ep.id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice')
      and ep.app_user_id   = (select (r ->> 'app_user_id')::uuid   from _res where label = 'alice')
      and ep.membership_id = (select (r ->> 'membership_id')::uuid from _res where label = 'alice')
      and ep.employment_status = 'active'
      and ep.pin_credential_ref is null),
  'the employee_profile was created active, linked, and with NO pin yet');                                      -- 10
select is((select count(*) from audit_events
    where action = 'staff.create_denied'
      and actor_app_user_id in ('00000000-0000-0000-0000-00000005ae02', '00000000-0000-0000-0000-00000005ae03'))::int, 2,
  'both role denials (manager->manager, cashier) were audited as staff.create_denied');                         -- 11

-- ============================================================================
-- B. set_employee_pin -- bcrypt storage + policy + authorization (12-19)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae02';  -- manager @ A1a

insert into _res values ('pin1', app.set_employee_pin('00000000-0000-0000-0000-00000005ac08',
  (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '90917788'));
select is(((select r ->> 'ok' from _res where label = 'pin1') || ':' ||
           (select r ->> 'pin_set' from _res where label = 'pin1')), 'true:true',
  'manager sets the operator pin (ok:true, pin_set:true)');                                                     -- 12
select is((app.set_employee_pin('00000000-0000-0000-0000-00000005ac09',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '12ab') ->> 'error'),
  'invalid_pin', 'a malformed pin (not 4-8 digits) is rejected as invalid_pin');                                -- 13

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae03';  -- cashier @ A1a
select is((app.set_employee_pin('00000000-0000-0000-0000-00000005ac0a',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '55556666') ->> 'error'),
  'permission_denied', 'cashier cannot set a pin (rank 1 -> permission_denied)');                               -- 14

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae0b';  -- Org B owner
select throws_ok($$
  select app.set_employee_pin('00000000-0000-0000-0000-00000005ac0b',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '55556666')
$$, '42501', NULL, 'a cross-org caller cannot set a pin (42501; authorized against the EMPLOYEE scope)');       -- 15

reset role;
select ok(
  (select pin_credential_ref from employee_profiles
    where id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'))
  like '$2%', 'the stored credential ref is a bcrypt hash ($2...)');                                            -- 16
select isnt(
  (select pin_credential_ref from employee_profiles
    where id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice')),
  '90917788', 'the raw pin is NEVER stored');                                                                   -- 17
select is((select count(*) from audit_events where action = 'staff.pin_set')::int, 1,
  'the successful pin set wrote one staff.pin_set audit row');                                                  -- 18
select is((select count(*) from audit_events where action = 'staff.pin_set_denied')::int, 1,
  'the cashier pin-set denial was audited as staff.pin_set_denied');                                            -- 19

-- ============================================================================
-- C. list_staff -- has_pin boolean only + scope + role gating (20-27)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae01';  -- org_owner A

insert into _res values ('lsall', app.list_staff('00000000-0000-0000-0000-00000005aa00'));
select is((select r ->> 'ok' from _res where label = 'lsall'), 'true',
  'org_owner lists staff org-wide (ok:true)');                                                                  -- 20
select is(jsonb_array_length((select r -> 'staff' from _res where label = 'lsall')), 3,
  'the org-wide list carries all three created staff');                                                         -- 21
select is(
  (select elem ->> 'has_pin' from jsonb_array_elements((select r -> 'staff' from _res where label = 'lsall')) elem
    where elem ->> 'employee_profile_id' = (select r ->> 'employee_profile_id' from _res where label = 'alice')),
  'true', 'alice shows has_pin=true after provisioning');                                                       -- 22
select is(
  (select elem ->> 'has_pin' from jsonb_array_elements((select r -> 'staff' from _res where label = 'lsall')) elem
    where elem ->> 'employee_profile_id' = (select r ->> 'employee_profile_id' from _res where label = 'bob')),
  'false', 'bob shows has_pin=false (no pin provisioned)');                                                     -- 23
select ok(
  (select bool_and(not (elem ? 'pin_credential_ref'))
     from jsonb_array_elements((select r -> 'staff' from _res where label = 'lsall')) elem)
  and position('$2' in (select (r -> 'staff')::text from _res where label = 'lsall')) = 0,
  'list_staff exposes has_pin ONLY -- never the credential ref value');                                         -- 24
select is(jsonb_array_length(app.list_staff('00000000-0000-0000-0000-00000005aa00',
    '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1b') -> 'staff'), 1,
  'the branch-filtered list returns only that branch''s staff (carol @ A1b)');                                  -- 25

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae03';  -- cashier @ A1a
select is((app.list_staff('00000000-0000-0000-0000-00000005aa00',
    '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a') ->> 'error'),
  'permission_denied', 'cashier cannot list staff (rank 1 -> permission_denied)');                              -- 26

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae0b';  -- Org B owner
select throws_ok($$
  select app.list_staff('00000000-0000-0000-0000-00000005aa00')
$$, '42501', NULL, 'a cross-org caller cannot list Org A staff (42501)');                                       -- 27

-- ============================================================================
-- D. list_device_staff -- token-proven PIN-pad list (ANONYMOUS device) (28-32)
-- ============================================================================
set local app.current_app_user_id = '';   -- anonymous authenticated device: NO app_user

insert into _res values ('devlist', public.list_device_staff('00000000-0000-0000-0000-00000005ad01', 'tok-mvp-staff'));
select is((select r ->> 'ok' from _res where label = 'devlist'), 'true',
  'the device staff list opens with the valid session token (public wrapper)');                                 -- 28
select is(jsonb_array_length((select r -> 'staff' from _res where label = 'devlist')), 2,
  'only branch-covering ACTIVE staff are listed (alice+bob; carol @ sibling branch excluded)');                 -- 29
select is(
  (select elem ->> 'role' from jsonb_array_elements((select r -> 'staff' from _res where label = 'devlist')) elem
    where elem ->> 'employee_profile_id' = (select r ->> 'employee_profile_id' from _res where label = 'alice')),
  'cashier', 'the device list carries alice with her membership role');                                         -- 30
select is(
  (select array_agg(distinct k order by k)
     from jsonb_array_elements((select r -> 'staff' from _res where label = 'devlist')) elem,
          jsonb_object_keys(elem) k)::text,
  '{display_name,employee_profile_id,role}',
  'device staff rows carry ONLY id+name+role (no email / employee_number / pin keys)');                         -- 31
select is((app.list_device_staff('00000000-0000-0000-0000-00000005ad01', 'wrong-token') ->> 'error'),
  'invalid_session', 'a wrong session token fails closed (invalid_session, no scope leak)');                    -- 32

-- ============================================================================
-- E. end-to-end PIN session on the paired device (33-35)
-- ============================================================================
reset role;
select ok(app.start_pin_session('00000000-0000-0000-0000-00000005ad51',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '90917788', 'op-mvp-e2e1') is not null,
  'the CORRECT typed pin opens a pin_session end-to-end (server-side bcrypt verify)');                          -- 33
select ok(app.start_pin_session('00000000-0000-0000-0000-00000005ad51',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '00000000', null) is null,
  'a WRONG pin returns NULL (no session)');                                                                     -- 34
select is((select failed_attempt_count from pin_attempt_states
    where employee_profile_id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice')
      and device_id = '00000000-0000-0000-0000-00000005ad01')::int, 1,
  'the wrong pin incremented pin_attempt_states (count=1)');                                                    -- 35

-- ============================================================================
-- F. the LEGACY interim plaintext ref is DEAD (36)
-- ============================================================================
-- simulate a pre-migration interim ref (plain equality would have accepted it)
update employee_profiles set pin_credential_ref = 'legacy-plain'
  where id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'bob');
select ok(app.start_pin_session('00000000-0000-0000-0000-00000005ad51',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'bob'), 'legacy-plain', null) is null,
  'a legacy plaintext (non-bcrypt) ref NO LONGER verifies (interim equality seam is dead)');                    -- 36

-- ============================================================================
-- G. rotating the pin resets the lockout and the NEW pin works (37-39)
-- ============================================================================
-- lock alice on the device (the row exists from the wrong-pin increment)
update pin_attempt_states
  set failed_attempt_count = app.pin_max_failed_attempts(), locked_until = now() + interval '1 hour'
  where employee_profile_id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice')
    and device_id = '00000000-0000-0000-0000-00000005ad01';

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae02';  -- manager @ A1a
insert into _res values ('pin2', app.set_employee_pin('00000000-0000-0000-0000-00000005ac0c',
  (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '31415926'));
select is((select r ->> 'ok' from _res where label = 'pin2'), 'true',
  'the manager rotates the pin while the operator is locked (ok:true)');                                        -- 37

reset role;
select is((select count(*) from pin_attempt_states
    where employee_profile_id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'))::int, 0,
  'setting a fresh pin DELETES the attempt/lockout rows (recovery path)');                                      -- 38
select ok(app.start_pin_session('00000000-0000-0000-0000-00000005ad51',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '31415926', 'op-mvp-e2e2') is not null,
  'after the reset the NEW pin opens a session (lockout cleared, old pin superseded)');                         -- 39

-- ============================================================================
-- H. idempotent replays: stored results, no duplication, no re-mutation (40-44)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae01';  -- org_owner A (original creator)
insert into _res values ('replayc', app.create_staff_member('00000000-0000-0000-0000-00000005ac01',
  '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
  'Alice Cashier', 'cashier'));
select is((select r ->> 'idempotent_replay' from _res where label = 'replayc'), 'true',
  'replaying create_staff_member returns the STORED result (idempotent_replay=true)');                          -- 40
select is((select r ->> 'employee_profile_id' from _res where label = 'replayc'),
          (select r ->> 'employee_profile_id' from _res where label = 'alice'),
  'the replay returns the SAME employee_profile_id');                                                           -- 41

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae02';  -- manager (original pin setter)
insert into _res values ('replayp', app.set_employee_pin('00000000-0000-0000-0000-00000005ac08',
  (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice'), '90917788'));
select is((select r ->> 'idempotent_replay' from _res where label = 'replayp'), 'true',
  'replaying set_employee_pin returns the STORED result (idempotent_replay=true)');                             -- 42

reset role;
select is((select count(*) from employee_profiles
    where organization_id = '00000000-0000-0000-0000-00000005aa00'
      and display_name = 'Alice Cashier' and deleted_at is null)::int, 1,
  'the create replay did NOT duplicate the operator');                                                          -- 43
select ok(
  extensions.crypt('31415926',
    (select pin_credential_ref from employee_profiles
      where id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice')))
  = (select pin_credential_ref from employee_profiles
      where id = (select (r ->> 'employee_profile_id')::uuid from _res where label = 'alice')),
  'the pin replay did NOT re-mutate the credential (still the rotated pin, not the replayed one)');             -- 44

-- ============================================================================
-- I. TARGET-RANK guard (review fix): rotating a PIN is an identity takeover,
--    so the caller must STRICTLY OUTRANK the target's own membership role
--    (a manager can never rotate a peer manager's PIN)               (45-47)
-- ============================================================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae01';  -- org_owner A
insert into _res values ('dana', app.create_staff_member('00000000-0000-0000-0000-00000005acd1',
  '00000000-0000-0000-0000-00000005aa00', '00000000-0000-0000-0000-00000005aa11', '00000000-0000-0000-0000-00000005aa1a',
  'Dana Manager', 'manager'));

set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae02';  -- manager @ A1a
select is((app.set_employee_pin('00000000-0000-0000-0000-00000005acd2',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'dana'), '24681357') ->> 'error'),
  'permission_denied',
  'a manager CANNOT rotate a peer manager''s pin (target-rank guard -> permission_denied)');                    -- 45
reset role;
select is((select count(*) from audit_events
    where action = 'staff.pin_set_denied'
      and new_values ->> 'reason' = 'target_rank')::int, 1,
  'the target-rank denial was audited as staff.pin_set_denied (reason target_rank)');                           -- 46
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000005ae01';  -- org_owner A
select is((app.set_employee_pin('00000000-0000-0000-0000-00000005acd3',
    (select (r ->> 'employee_profile_id')::uuid from _res where label = 'dana'), '24681357') ->> 'pin_set'),
  'true', 'the org_owner (strictly outranking a manager) CAN set the manager''s pin');                          -- 47
reset role;

-- ============================================================================
-- J. NO pin material in the ledger or the audit trail (48-49)
-- ============================================================================
select is((select count(*) from management_request_results
    where (request_fingerprint || result::text)
          like any (array['%90917788%', '%31415926%', '%55556666%', '%24681357%'])
       or result::text like '%$2%')::int, 0,
  'the idempotency ledger stores NO raw pin and NO bcrypt hash');                                               -- 48
select is((select count(*) from audit_events
    where coalesce(old_values::text, '') || coalesce(new_values::text, '')
          like any (array['%90917788%', '%31415926%', '%55556666%', '%24681357%', '%$2%'])
       or coalesce(reason, '') like any (array['%90917788%', '%31415926%', '%55556666%', '%24681357%']))::int, 0,
  'audit rows carry NO raw pin and NO bcrypt hash');                                                            -- 49

select * from finish();
rollback;
