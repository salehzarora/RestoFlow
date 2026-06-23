-- ============================================================================
-- RF-075 — pgTAP: per-shift reconciliation lines (open vs closed)
-- ============================================================================
-- An OPEN shift is provisional with a null variance; after close_shift (RF-055)
-- the same shift line exposes authoritative expected/counted/variance and is no
-- longer provisional. The report only EXPOSES RF-055's stored values; it never
-- computes variance.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf075sh-a', 'USD');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1', 'UTC');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf075sh-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);

-- ===== OPEN shift: provisional, null variance =====
set local role authenticated;
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select is_provisional from public.daily_branch_shift_lines where shift_id='00000000-0000-0000-0000-00000000a5f1'), true, 'open shift is provisional');
select ok((select variance_minor is null from public.daily_branch_shift_lines where shift_id='00000000-0000-0000-0000-00000000a5f1'), 'open shift has null variance (never computed here)');
select is((select opening_float_minor from public.daily_branch_shift_lines where shift_id='00000000-0000-0000-0000-00000000a5f1')::bigint, 5000::bigint, 'opening float exposed from the drawer');

-- ===== close the shift (RF-055), zero variance (no cash sales) =====
reset role;
select app.close_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000da11','op-close',5000,null,null);

-- ===== CLOSED shift: authoritative expected/counted/variance, not provisional =====
set local role authenticated;
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select is_provisional from public.daily_branch_shift_lines where shift_id='00000000-0000-0000-0000-00000000a5f1'), false, 'closed shift is not provisional');
select ok((select expected_total_minor is not null from public.daily_branch_shift_lines where shift_id='00000000-0000-0000-0000-00000000a5f1'), 'closed shift exposes expected_total_minor');
select ok((select variance_minor is not null from public.daily_branch_shift_lines where shift_id='00000000-0000-0000-0000-00000000a5f1'), 'closed shift exposes authoritative variance_minor');

select * from finish();
rollback;
