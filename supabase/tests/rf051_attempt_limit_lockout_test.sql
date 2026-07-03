-- ============================================================================
-- RF-051 — pgTAP: PIN attempt limit + lockout (AC#2)
-- ============================================================================
-- Through app.start_pin_session: a wrong verifier PERSISTS a failed-attempt
-- increment and returns NULL (no session); at the centralized max (5) the
-- (employee, device) is locked; a locked attempt is rejected (42501) even with
-- the correct verifier; after the lockout lapses a correct verifier succeeds and
-- resets the counter. No pin_session is created on any failed/locked attempt.
-- NOTE: a wrong verifier RETURNS NULL rather than raising, because raising would
-- roll back the counter increment (single-statement txn) and defeat lockout.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'r51l-org-a', 'USD');
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
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0a', 'r51l-user@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab01', extensions.crypt('ref:test-correct', extensions.gen_salt('bf')));

-- one wrong attempt: increments to 1, creates no session ---------------------- 1-2
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:WRONG', null);
select is((select failed_attempt_count from pin_attempt_states where employee_profile_id='00000000-0000-0000-0000-0000000ef001' and device_id='00000000-0000-0000-0000-00000000da11')::int, 1,
  'a wrong verifier increments failed_attempt_count to 1');
select is((select count(*) from pin_sessions)::int, 0, 'no pin_session is created on a failed attempt');

-- three more wrong attempts (total 4); still NOT locked ----------------------- 3-4
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:WRONG', null);
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:WRONG', null);
select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:WRONG', null);
select is((select failed_attempt_count from pin_attempt_states where employee_profile_id='00000000-0000-0000-0000-0000000ef001' and device_id='00000000-0000-0000-0000-00000000da11')::int, 4,
  'four failures accumulate (count=4)');
select ok((select locked_until from pin_attempt_states where employee_profile_id='00000000-0000-0000-0000-0000000ef001' and device_id='00000000-0000-0000-0000-00000000da11') is null,
  'N-1 (4) failures do NOT lock');

-- fifth wrong attempt: returns null, count=5, NOW locked ---------------------- 5-8
select ok(
  app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:WRONG', null) is null,
  'the 5th wrong verifier returns NULL (no session)');
select is((select failed_attempt_count from pin_attempt_states where employee_profile_id='00000000-0000-0000-0000-0000000ef001' and device_id='00000000-0000-0000-0000-00000000da11')::int, 5,
  'the 5th failure brings the count to the max (5)');
select ok((select locked_until from pin_attempt_states where employee_profile_id='00000000-0000-0000-0000-0000000ef001' and device_id='00000000-0000-0000-0000-00000000da11') > now(),
  'reaching the max LOCKS the (employee, device) (locked_until in the future)');
select is((select count(*) from pin_sessions)::int, 0, 'still no pin_session after 5 failures');

-- while locked, even the CORRECT verifier is rejected ------------------------- 9-10
select throws_ok($$ select app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) $$, '42501', NULL,
  'a locked (employee, device) is rejected even with the CORRECT verifier');
select is((select count(*) from pin_sessions)::int, 0, 'no pin_session is created while locked');

-- after the lockout lapses, the correct verifier succeeds and resets ---------- 11-13
update pin_attempt_states set locked_until = now() - interval '1 minute'
  where employee_profile_id='00000000-0000-0000-0000-0000000ef001' and device_id='00000000-0000-0000-0000-00000000da11';
select ok(
  app.start_pin_session('00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-0000000ef001','ref:test-correct', null) is not null,
  'after the lockout lapses, the correct verifier creates a session');
select is((select failed_attempt_count from pin_attempt_states where employee_profile_id='00000000-0000-0000-0000-0000000ef001' and device_id='00000000-0000-0000-0000-00000000da11')::int, 0,
  'a successful start resets failed_attempt_count to 0');
select is((select count(*) from pin_sessions where is_active)::int, 1, 'exactly one ACTIVE pin_session exists after the successful start');

select * from finish();
rollback;
