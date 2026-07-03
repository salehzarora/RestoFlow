-- ============================================================================
-- RF-139 — pgTAP: PIN session audit events (started + rate-limited failed-attempt)
-- ============================================================================
-- Verifies the RF-139 audit writes added to app.start_pin_session (resolving M7
-- contract drift D3; API_CONTRACT §4.13/§4.21; DECISION D-013):
--   * a SUCCESSFUL start writes exactly one append-only `pin_session.started`
--     event carrying the new session id, scope, actor, and idempotent_replay=false;
--   * an idempotent REPLAY returns the same session id and does NOT double-audit;
--   * a WRONG verifier writes one `pin_session.failed` event (returns NULL, no
--     session) carrying the attempt count + lock state;
--   * the failed-attempt audit is rate-limited by the lockout (<= max rows);
--   * the capping (5th) failure is audited as locked with a locked_until;
--   * a LOCKED/raised attempt (42501) writes NO audit row (rolled back);
--   * the PIN credential VERIFIER is NEVER recorded in any audit row.
-- Fixtures inserted as the BYPASSRLS connection role (so audit_events is readable
-- directly); the RETURN CONTRACT (NULL / 42501 / uuid) is unchanged from RF-051.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(18);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-000000013900', 'Org RF139', 'rf139-org', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-000000013901', '00000000-0000-0000-0000-000000013900', 'Restaurant RF139');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-000000013902', '00000000-0000-0000-0000-000000013900', '00000000-0000-0000-0000-000000013901', 'Branch RF139');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0000000139d1', '00000000-0000-0000-0000-000000013900', '00000000-0000-0000-0000-000000013901', '00000000-0000-0000-0000-000000013902', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0000000139f1', '00000000-0000-0000-0000-000000013900', '00000000-0000-0000-0000-000000013901', '00000000-0000-0000-0000-000000013902', '00000000-0000-0000-0000-0000000139d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000139d5', '00000000-0000-0000-0000-000000013900', '00000000-0000-0000-0000-000000013901', '00000000-0000-0000-0000-000000013902', '00000000-0000-0000-0000-0000000139d1', '00000000-0000-0000-0000-0000000139f1');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0000000139e0', 'rf139-user@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000013ab01', '00000000-0000-0000-0000-0000000139e0', '00000000-0000-0000-0000-000000013900', 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, pin_credential_ref) values
  ('00000000-0000-0000-0000-0000000139ef', '00000000-0000-0000-0000-000000013900', '00000000-0000-0000-0000-000000013901', '00000000-0000-0000-0000-000000013902', '00000000-0000-0000-0000-0000000139e0', '00000000-0000-0000-0000-00000013ab01', extensions.crypt('ref:test-correct', extensions.gen_salt('bf')));

-- Capture returned session ids for cross-checks.
create temporary table rf139_run (label text primary key, sid uuid);

-- ---- A. SUCCESS writes exactly one pin_session.started --------------------- 1-6
insert into rf139_run (label, sid) values
  ('first', app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:test-correct','op-1'));

select is((select count(*) from audit_events where action = 'pin_session.started')::int, 1,
  'a successful start writes exactly one pin_session.started audit event');
select is((select new_values->>'pin_session_id' from audit_events where action = 'pin_session.started'),
          (select sid::text from rf139_run where label = 'first'),
  'the started event references the newly created pin_session id');
select is((select actor_employee_profile_id from audit_events where action = 'pin_session.started'),
          '00000000-0000-0000-0000-0000000139ef'::uuid,
  'the started event records the employee profile as the actor');
select ok((select organization_id = '00000000-0000-0000-0000-000000013900'::uuid
                  and branch_id = '00000000-0000-0000-0000-000000013902'::uuid
                  and device_id = '00000000-0000-0000-0000-0000000139d1'::uuid
             from audit_events where action = 'pin_session.started'),
  'the started event is scoped to the correct org / branch / device');
select is((select new_values->>'idempotent_replay' from audit_events where action = 'pin_session.started'), 'false',
  'the started event is flagged idempotent_replay=false');
select is((select new_values->>'resolved_membership_id' from audit_events where action = 'pin_session.started'),
          '00000000-0000-0000-0000-00000013ab01',
  'the started event records the resolved membership');

-- ---- B. Idempotent replay returns same id and does NOT double-audit -------- 7-8
insert into rf139_run (label, sid) values
  ('replay', app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:test-correct','op-1'));

select is((select sid from rf139_run where label = 'replay'),
          (select sid from rf139_run where label = 'first'),
  'an idempotent replay (same local_operation_id) returns the same session id');
select is((select count(*) from audit_events where action = 'pin_session.started')::int, 1,
  'an idempotent replay does NOT write a second pin_session.started event');

-- ---- C. A wrong verifier writes one pin_session.failed --------------------- 9-11
select app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:WRONG', null);

select is((select count(*) from audit_events where action = 'pin_session.failed')::int, 1,
  'a wrong verifier writes one pin_session.failed audit event');
select is((select new_values->>'failed_attempt_count' from audit_events where action = 'pin_session.failed'), '1',
  'the failed event records failed_attempt_count = 1');
select is((select new_values->>'locked' from audit_events where action = 'pin_session.failed'), 'false',
  'a single failure is audited as not locked');

-- ---- D. Reaching the cap is rate-limited and audited as locked ------------- 12-14
select app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:WRONG', null);
select app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:WRONG', null);
select app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:WRONG', null);
select app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:WRONG', null);

select is((select count(*) from audit_events where action = 'pin_session.failed')::int, 5,
  'five wrong attempts write exactly five pin_session.failed events (rate-limited by the cap)');
select is((select new_values->>'locked' from audit_events
            where action = 'pin_session.failed' and new_values->>'failed_attempt_count' = '5'), 'true',
  'the capping (5th) failure is audited as locked=true');
select ok((select new_values->>'locked_until' is not null from audit_events
            where action = 'pin_session.failed' and new_values->>'failed_attempt_count' = '5'),
  'the capping failure records a locked_until timestamp');

-- ---- E. A locked/raised attempt (42501) is NOT audited (rolled back) ------- 15-17
select throws_ok(
  $$ select app.start_pin_session('00000000-0000-0000-0000-0000000139d5','00000000-0000-0000-0000-0000000139ef','ref:test-correct', null) $$,
  '42501', NULL,
  'a locked (employee, device) raises 42501 even with the correct verifier');
select is((select count(*) from audit_events where action = 'pin_session.failed')::int, 5,
  'the raised (locked) attempt writes NO additional pin_session.failed event');
select is((select count(*) from audit_events where action = 'pin_session.started')::int, 1,
  'the raised (locked) attempt writes NO pin_session.started event');

-- ---- F. The PIN verifier is never recorded in any audit row --------------- 18
select is((select count(*) from audit_events
            where coalesce(new_values::text, '') like '%ref:%'
               or coalesce(reason, '') like '%ref:%')::int, 0,
  'the PIN credential verifier never appears in any audit_events row');

select * from finish();
rollback;
