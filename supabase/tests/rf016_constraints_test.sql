-- ============================================================================
-- RF-016 — pgTAP constraints / state / integrity-guard test
-- ============================================================================
-- Run as the BYPASSRLS connection role so FORCE RLS never masks a raw error.
--   * device_pairings.status accepts exactly the D-018 enum; rejects others (23514).
--   * EXPIRED enrollment code may move to code_expired but NOT to pending/paired/
--     active (both directions; 23514) — the RF-016 expiry guard.
--   * pin_session may be ACTIVE only on an active, non-revoked device session whose
--     pairing is active; rejected for inactive/revoked session or suspended/revoked
--     pairing (23514) — the RF-016 backing guard.
--   * composite same-org FKs reject cross-org references (23503); branch scope
--     columns are NOT NULL (23502).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(30);

-- ---- Fixtures (connection role / BYPASSRLS) --------------------------------
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'c16-org-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'c16-org-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Restaurant A'),
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Restaurant B');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A'),
  ('00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('00000000-0000-0000-0000-00000000db11', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', 'pos');

-- pairings on Org A device DA (status + expiry combos)
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, code_expires_at) values
  ('00000000-0000-0000-0000-00000000fa01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active',    now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000fa02', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'suspended', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000fa03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'revoked',   now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000fa04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'code_issued', now() - interval '1 hour'),  -- EXPIRED
  ('00000000-0000-0000-0000-00000000fa05', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'code_issued', now() + interval '1 hour'),  -- NOT expired
  ('00000000-0000-0000-0000-00000000fa06', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'suspended',   now() - interval '1 hour'),  -- SUSPENDED + lapsed code (re-enable regression)
  ('00000000-0000-0000-0000-00000000fa07', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active',      now() + interval '1 hour');  -- ACTIVE (code lapses via update below)

-- device sessions on Org A device DA (active / inactive / revoked / on suspended|revoked pairing)
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa01', true,  null),     -- active, pairing active
  ('00000000-0000-0000-0000-0000000005a2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa01', false, null),     -- inactive
  ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa01', true,  now()),    -- revoked session
  ('00000000-0000-0000-0000-0000000005a4', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa02', true,  null),     -- on SUSPENDED pairing
  ('00000000-0000-0000-0000-0000000005a5', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa03', true,  null);     -- on REVOKED pairing

insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee0a', 'c16-user@example.test');
insert into memberships (id, app_user_id, organization_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', 'cashier');
insert into employee_profiles (id, organization_id, display_name) values
  ('00000000-0000-0000-0000-00000000ef01', '00000000-0000-0000-0000-0000000000a0', 'Cashier One');

-- A reusable valid pin_session insert (on the ACTIVE device session) ---------
-- helper macro is not available; spelled out per assertion.

-- == D-018 status enum: all eight valid values accepted ====================== 1-8
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','code_issued', now()+interval '1 hour') $$, 'status code_issued accepted');
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','pending', now()+interval '1 hour') $$, 'status pending accepted');
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','paired', now()+interval '1 hour') $$, 'status paired accepted');
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','active', now()+interval '1 hour') $$, 'status active accepted');
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','suspended', now()+interval '1 hour') $$, 'status suspended accepted');
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','revoked', now()+interval '1 hour') $$, 'status revoked accepted');
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','code_expired', now()+interval '1 hour') $$, 'status code_expired accepted');
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','rejected', now()+interval '1 hour') $$, 'status rejected accepted');

-- == invalid status rejected ================================================= 9
select throws_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','bogus') $$, '23514', NULL, 'an out-of-D-018 status is rejected (CHECK)');

-- == EXPIRED code cannot COMPLETE pairing (both directions) ================== 10-15
-- INSERT path: a fresh pairing with an expired code cannot be born active
select throws_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','active', now()-interval '1 hour') $$, '23514', NULL, 'expired code cannot be inserted directly as active');
-- UPDATE path on the expired PX (status code_issued, code_expires_at past):
select throws_ok($$ update device_pairings set status='pending' where id='00000000-0000-0000-0000-00000000fa04' $$, '23514', NULL, 'expired code cannot move to pending');
select throws_ok($$ update device_pairings set status='paired'  where id='00000000-0000-0000-0000-00000000fa04' $$, '23514', NULL, 'expired code cannot move to paired');
select throws_ok($$ update device_pairings set status='active'  where id='00000000-0000-0000-0000-00000000fa04' $$, '23514', NULL, 'expired code cannot move to active');
-- expired code CAN move to code_expired:
select lives_ok($$ update device_pairings set status='code_expired' where id='00000000-0000-0000-0000-00000000fa04' $$, 'expired code MAY move to code_expired');
-- positive control: a NON-expired code may complete to pending:
select lives_ok($$ update device_pairings set status='pending' where id='00000000-0000-0000-0000-00000000fa05' $$, 'a non-expired code may move to pending');

-- == pin_session may exist only on an ACTIVE device session w/ ACTIVE pairing = 16-20
select lives_ok($$ insert into pin_sessions (organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a1','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab01') $$, 'pin_session on ACTIVE session + ACTIVE pairing is allowed');
select throws_ok($$ insert into pin_sessions (organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a2','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab01') $$, '23514', NULL, 'pin_session on an INACTIVE device session is rejected');
select throws_ok($$ insert into pin_sessions (organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a3','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab01') $$, '23514', NULL, 'pin_session on a REVOKED device session is rejected');
select throws_ok($$ insert into pin_sessions (organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a4','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab01') $$, '23514', NULL, 'pin_session on a session backed by a SUSPENDED pairing is rejected');
select throws_ok($$ insert into pin_sessions (organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a5','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab01') $$, '23514', NULL, 'pin_session on a session backed by a REVOKED pairing is rejected');

-- == composite same-org FKs + NOT NULL ======================================= 21-23
select throws_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000db11') $$, '23503', NULL, 'pairing referencing a device in another org is structurally rejected (composite FK)');
select throws_ok($$ insert into devices (organization_id,restaurant_id,branch_id,device_type) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-00000000b1b1','pos') $$, '23503', NULL, 'device referencing another org''s restaurant/branch is structurally rejected (composite FK)');
select throws_ok($$ insert into devices (organization_id,restaurant_id,branch_id,device_type) values ('00000000-0000-0000-0000-0000000000a0', null, '00000000-0000-0000-0000-00000000a1b1','pos') $$, '23502', NULL, 'device with a branch but NULL restaurant is rejected (NOT NULL)');

-- == expiry guard does NOT over-reach post-enrollment transitions ============ 24-26
-- suspended -> active re-enable is allowed even though the enrollment code lapsed (STATE_MACHINES §9)
select lives_ok($$ update device_pairings set status='active' where id='00000000-0000-0000-0000-00000000fa06' $$, 'suspended -> active re-enable is allowed despite a lapsed enrollment code');
-- an already-active pairing whose code later lapses is not gated (OLD status is not code_issued)
select lives_ok($$ update device_pairings set code_expires_at = now() - interval '1 hour' where id='00000000-0000-0000-0000-00000000fa07' $$, 'an active pairing may have its enrollment code lapse without the guard firing');
-- an expired code may be recorded directly as code_expired
select lives_ok($$ insert into device_pairings (organization_id,restaurant_id,branch_id,device_id,status,code_expires_at) values ('00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','code_expired', now()-interval '1 hour') $$, 'an expired code may be recorded directly as code_expired');

-- == PIN-backing guard fires on the UPDATE path too (TH-5 reactivation) ====== 27-30
-- an is_active=false pin_session may be created on a bad backing (guard is a no-op when inactive)...
select lives_ok($$ insert into pin_sessions (id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,is_active) values ('00000000-0000-0000-0000-0000000c1ad1','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a3','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab01', false) $$, 'inactive pin_session on a revoked device session is allowed (guard no-op)');
-- ...but flipping it ACTIVE on the now-revoked device session is rejected (TH-5)
select throws_ok($$ update pin_sessions set is_active=true where id='00000000-0000-0000-0000-0000000c1ad1' $$, '23514', NULL, 'reactivating a pin_session on a REVOKED device session is rejected on UPDATE (TH-5)');
select lives_ok($$ insert into pin_sessions (id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,is_active) values ('00000000-0000-0000-0000-0000000c1ad2','00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-0000000005a5','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab01', false) $$, 'inactive pin_session on a session backed by a revoked pairing is allowed (guard no-op)');
select throws_ok($$ update pin_sessions set is_active=true where id='00000000-0000-0000-0000-0000000c1ad2' $$, '23514', NULL, 'reactivating a pin_session backed by a REVOKED pairing is rejected on UPDATE (TH-5)');

select * from finish();
rollback;
