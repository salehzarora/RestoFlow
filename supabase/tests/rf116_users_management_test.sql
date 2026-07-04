-- ============================================================================
-- RF-116 — pgTAP: app.list_members (member directory) + app.revoke_membership.
--  * list_members: manager+ lists the org; cashier/kitchen denied; non-member/
--    cross-org 42501; rows carry membership_id + email + role + is_self.
--  * revoke_membership: owner revokes a cashier (status=revoked + deleted_at +
--    employee_profile terminated); no self-revoke; cannot revoke equal/higher;
--    cashier denied; cross-tenant 42501; idempotent replay.
-- Fixtures inserted as the BYPASSRLS harness role; RPCs run as authenticated
-- with the identity GUC (app.current_app_user_id).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(15);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000123000a00', 'Org A', 'rf116-a', 'ILS'),
  ('00000000-0000-0000-0000-000123000b00', 'Org B', 'rf116-b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000123000a10', '00000000-0000-0000-0000-000123000a00', 'Rest A1'),
  ('00000000-0000-0000-0000-000123000b10', '00000000-0000-0000-0000-000123000b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000123000a1a', '00000000-0000-0000-0000-000123000a00', '00000000-0000-0000-0000-000123000a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-000123000b1a', '00000000-0000-0000-0000-000123000b00', '00000000-0000-0000-0000-000123000b10', 'Branch B1a');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-000123000e01', 'rf116-owner@example.test'),
  ('00000000-0000-0000-0000-000123000e03', 'rf116-manager@example.test'),
  ('00000000-0000-0000-0000-000123000e04', 'rf116-cashier@example.test'),
  ('00000000-0000-0000-0000-000123000e05', 'rf116-cashier2@example.test'),
  ('00000000-0000-0000-0000-000123000e06', 'rf116-manager2@example.test'),
  ('00000000-0000-0000-0000-000123000e07', 'rf116-borg-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-000123000f01', '00000000-0000-0000-0000-000123000e01', '00000000-0000-0000-0000-000123000a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-000123000f03', '00000000-0000-0000-0000-000123000e03', '00000000-0000-0000-0000-000123000a00', '00000000-0000-0000-0000-000123000a10', '00000000-0000-0000-0000-000123000a1a', 'manager'),
  ('00000000-0000-0000-0000-000123000f04', '00000000-0000-0000-0000-000123000e04', '00000000-0000-0000-0000-000123000a00', '00000000-0000-0000-0000-000123000a10', '00000000-0000-0000-0000-000123000a1a', 'cashier'),
  ('00000000-0000-0000-0000-000123000f05', '00000000-0000-0000-0000-000123000e05', '00000000-0000-0000-0000-000123000a00', '00000000-0000-0000-0000-000123000a10', '00000000-0000-0000-0000-000123000a1a', 'cashier'),
  ('00000000-0000-0000-0000-000123000f06', '00000000-0000-0000-0000-000123000e06', '00000000-0000-0000-0000-000123000a00', '00000000-0000-0000-0000-000123000a10', '00000000-0000-0000-0000-000123000a1a', 'manager'),
  ('00000000-0000-0000-0000-000123000f07', '00000000-0000-0000-0000-000123000e07', '00000000-0000-0000-0000-000123000b00', null, null, 'org_owner');
-- cashier2 has an employee_profile (to test the revoke -> terminated cascade)
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-000123000ef5', '00000000-0000-0000-0000-000123000a00', '00000000-0000-0000-0000-000123000a10', '00000000-0000-0000-0000-000123000a1a', '00000000-0000-0000-0000-000123000e05', '00000000-0000-0000-0000-000123000f05', 'hash-xyz');

set local role authenticated;

-- ===== A. list_members =====
set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e01';  -- org_owner
select is((app.list_members('00000000-0000-0000-0000-000123000a00') ->> 'ok'), 'true', 'org_owner may list members');                                    -- 1
select is(jsonb_array_length(app.list_members('00000000-0000-0000-0000-000123000a00') -> 'members'), 5, 'the org has 5 live members');                     -- 2
select is(
  (select count(*)::int from jsonb_array_elements(app.list_members('00000000-0000-0000-0000-000123000a00') -> 'members') e
     where e ->> 'email' = 'rf116-owner@example.test' and (e ->> 'is_self')::boolean and e ->> 'role' = 'org_owner'
       and (e ->> 'membership_id') is not null),
  1, 'the owner row carries email + role + membership_id + is_self=true');                                                                                 -- 3
select is(
  (select (e ->> 'has_pin') from jsonb_array_elements(app.list_members('00000000-0000-0000-0000-000123000a00') -> 'members') e
     where e ->> 'email' = 'rf116-cashier2@example.test'),
  'true', 'a member with an employee PIN shows has_pin=true');                                                                                             -- 4

set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e03';  -- manager
select is((app.list_members('00000000-0000-0000-0000-000123000a00') ->> 'ok'), 'true', 'a manager may also list members');                                -- 5
set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e04';  -- cashier
select is((app.list_members('00000000-0000-0000-0000-000123000a00') ->> 'error'), 'permission_denied', 'a cashier cannot list members (permission_denied)'); -- 6
select throws_ok($$ select app.list_members('00000000-0000-0000-0000-000123000b00') $$, '42501', NULL, 'a cashier of Org A cannot list Org B members (non-member; 42501)'); -- 7

-- ===== B. revoke_membership =====
set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e01';  -- org_owner
select is((app.revoke_membership('00000000-0000-0000-0000-000123000c01','00000000-0000-0000-0000-000123000f05','left the team') ->> 'ok'),
  'true', 'org_owner revokes a cashier');                                                                                                                  -- 8

-- self-revoke denied
select is((app.revoke_membership('00000000-0000-0000-0000-000123000c02','00000000-0000-0000-0000-000123000f01','x') ->> 'error'),
  'permission_denied', 'no self-revoke (owner cannot revoke their own membership)');                                                                       -- 9

set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e03';  -- manager
select is((app.revoke_membership('00000000-0000-0000-0000-000123000c03','00000000-0000-0000-0000-000123000f06','x') ->> 'error'),
  'permission_denied', 'a manager cannot revoke an equal-rank manager');                                                                                   -- 10
set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e04';  -- cashier
select is((app.revoke_membership('00000000-0000-0000-0000-000123000c04','00000000-0000-0000-0000-000123000f06','x') ->> 'error'),
  'permission_denied', 'a cashier cannot revoke anyone (rank < manager)');                                                                                 -- 11
set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e07';  -- org_owner of Org B
select throws_ok($$ select app.revoke_membership('00000000-0000-0000-0000-000123000c05','00000000-0000-0000-0000-000123000f03','x') $$,
  '42501', NULL, 'org_owner of Org B cannot revoke an Org A membership (cross-tenant; 42501)');                                                            -- 12

-- ===== C. DB state + cascade + idempotency (as the BYPASSRLS owner) =====
reset role;
select is((select (status, deleted_at is not null)::text from memberships where id = '00000000-0000-0000-0000-000123000f05'),
  ('revoked', true)::text, 'the revoked cashier membership is status=revoked + soft-deleted');                                                             -- 13
select is((select employment_status from employee_profiles where id = '00000000-0000-0000-0000-000123000ef5'),
  'terminated', 'the revoked member''s employee profile is terminated (no working PIN)');                                                                  -- 14
-- idempotent replay: same client_request_id returns the stored result, membership stays revoked once
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-000123000e01';
select is((app.revoke_membership('00000000-0000-0000-0000-000123000c01','00000000-0000-0000-0000-000123000f05','left the team') ->> 'ok'),
  'true', 'a replay of the same revoke request returns ok (idempotent, no error on the already-revoked row)');                                             -- 15

select * from finish();
rollback;
