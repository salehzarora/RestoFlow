-- ============================================================================
-- ADMIN-126B — pgTAP: secure, audited, READ-ONLY platform support access.
--
-- The security argument lives in four groups; everything else supports them.
--
--   V  APPROVED READS WORK. All fifteen return real tenant data to a live
--      support session, so "Open Dashboard" is not a banner over an empty page.
--   D  WITHHELD READS ARE DENIED. Staff names, member emails and the three
--      customer-bearing order surfaces stay shut, by the server.
--   W  WRITES ARE DENIED. Every mutation family the Dashboard exposes is
--      attempted BY A LIVE SUPPORT OPERATOR and refused server-side. Nothing
--      here depends on a hidden button.
--   N  THE TENANT IS UNCHANGED. A real org_owner still reads AND writes exactly
--      as before, and still cannot reach a tenant they do not belong to.
--
-- Plus X: the structural invariants the whole design rests on — no function that
-- writes a public table consults the read rank or the support guard, and the
-- four core helpers (current_org_id / has_scope / has_role_in_scope /
-- actor_rank_in_scope) do not mention support at all. If any of that stops being
-- true, this file fails, which is the only way "read-only" keeps meaning
-- something a year from now.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(88);

-- ===== fixture: one real tenant, fully furnished ============================
insert into organizations (id, name, slug, default_currency, status) values
  ('c4000000-0000-0000-0000-0000000000a0', 'Alpha Group', 'sup126b-a', 'ILS', 'active'),
  ('c4000000-0000-0000-0000-0000000000b0', 'Bravo Ltd',   'sup126b-b', 'EUR', 'active');
insert into restaurants (id, organization_id, name, timezone) values
  ('c4000000-0000-0000-0000-0000000000a1', 'c4000000-0000-0000-0000-0000000000a0', 'Alpha One', 'UTC'),
  ('c4000000-0000-0000-0000-0000000000b1', 'c4000000-0000-0000-0000-0000000000b0', 'Bravo One', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('c4000000-0000-0000-0000-0000000000c1', 'c4000000-0000-0000-0000-0000000000a0', 'c4000000-0000-0000-0000-0000000000a1', 'A1 Main', null),
  ('c4000000-0000-0000-0000-0000000000c2', 'c4000000-0000-0000-0000-0000000000b0', 'c4000000-0000-0000-0000-0000000000b1', 'B1 Main', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('c4000000-0000-0000-0000-0000000000d1', 'c4000000-0000-0000-0000-0000000000a0', 'c4000000-0000-0000-0000-0000000000a1', 'c4000000-0000-0000-0000-0000000000c1', 'pos');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('c4000000-0000-0000-0000-0000000000f1', 'c4000000-0000-0000-0000-0000000000a0', 'c4000000-0000-0000-0000-0000000000a1', 'c4000000-0000-0000-0000-0000000000c1', 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('c4000000-0000-0000-0000-0000000000f2', 'c4000000-0000-0000-0000-0000000000a0', 'c4000000-0000-0000-0000-0000000000a1', 'c4000000-0000-0000-0000-0000000000c1', 'c4000000-0000-0000-0000-0000000000f1', 'Falafel', 2500, 'ILS', 1);
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('c4000000-0000-0000-0000-0000000000f3', 'c4000000-0000-0000-0000-0000000000a0', 'c4000000-0000-0000-0000-0000000000a1', 'c4000000-0000-0000-0000-0000000000c1', 'T1');
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role) values
  ('c4000000-0000-0000-0000-0000000000f4', 'c4000000-0000-0000-0000-0000000000a0', 'c4000000-0000-0000-0000-0000000000a1', 'c4000000-0000-0000-0000-0000000000c1', 'Kitchen', 'bluetooth', 'kitchen');

insert into auth.users (id, email) values
  ('c4000000-0000-0000-0000-00000000adf0', 'sup-operator@example.test'),
  ('c4000000-0000-0000-0000-00000000adf1', 'sup-owner@example.test');
insert into app_users (id, email, auth_user_id) values
  ('c4000000-0000-0000-0000-00000000ee0f', 'sup-operator@example.test', 'c4000000-0000-0000-0000-00000000adf0'),
  ('c4000000-0000-0000-0000-00000000ee0e', 'sup-owner@example.test',    'c4000000-0000-0000-0000-00000000adf1');
insert into platform_admin_grants (id, app_user_id, status, granted_by) values
  ('c4000000-0000-0000-0000-0000000000e1', 'c4000000-0000-0000-0000-00000000ee0f', 'active',
   'c4000000-0000-0000-0000-00000000ee0f');
-- A real org_owner of Alpha with NO platform grant, for group N.
insert into memberships (id, app_user_id, organization_id, role, status) values
  ('c4000000-0000-0000-0000-0000000000e2', 'c4000000-0000-0000-0000-00000000ee0e',
   'c4000000-0000-0000-0000-0000000000a0', 'org_owner', 'active');
insert into employee_profiles (id, organization_id, app_user_id, membership_id, display_name) values
  ('c4000000-0000-0000-0000-0000000000e3', 'c4000000-0000-0000-0000-0000000000a0',
   'c4000000-0000-0000-0000-00000000ee0e', 'c4000000-0000-0000-0000-0000000000e2', 'Owner One');

-- ===========================================================================
-- S. START + EXCHANGE
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = 'c4000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c4000000-0000-0000-0000-00000000adf0","aal":"aal2"}';

create temp table started as select public.platform_admin_start_support_session(
  'c4000000-0000-0000-0000-0000000000a0', null,
  'Owner reports missing sales for today') as res;

select ok((select res ->> 'handoff_token' from started) ~ '^[0-9a-f]{64}$',
  'S1. start returns 32 CSPRNG bytes as a hex handoff token');
select ok((select (res ->> 'expires_at')::timestamptz from started) between now() + interval '10 minutes' and now() + interval '15 minutes',
  'S2. the session TTL is server-set, 10-15 minutes');
select ok((select (res ->> 'exchange_expires_at')::timestamptz from started) <= now() + interval '61 seconds',
  'S3. the EXCHANGE window is far shorter than the session');
select throws_ok(
  $$ select public.platform_admin_start_support_session('c4000000-0000-0000-0000-0000000000a0', null, '   ') $$,
  '42501', NULL, 'S4. a blank reason is refused — support access is reason-tagged');
select throws_ok(
  $$ select public.platform_admin_start_support_session('c4000000-0000-0000-0000-00000000dead', null, 'probe') $$,
  '42501', NULL, 'S5. an unknown organization is refused with the denial code');

reset role;
select is((select count(*)::int from platform_support_sessions s, started
            where s.token_hash = (started.res ->> 'handoff_token')), 0,
  'S6. the PLAINTEXT token is not stored — a database dump cannot be replayed');
select is((select count(*)::int from platform_support_sessions s, started
            where s.token_hash = encode(digest(started.res ->> 'handoff_token', 'sha256'), 'hex')), 1,
  'S7. only its SHA-256 hash is stored');
select is((select status from platform_support_sessions), 'pending',
  'S8. a started session is PENDING until the handoff is exchanged');
select is((select count(*)::int from memberships
            where app_user_id = 'c4000000-0000-0000-0000-00000000ee0f'), 0,
  'S9. NO membership row is created — not permanently and not temporarily');

set local role authenticated;
set local request.jwt.claim.sub = 'c4000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c4000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
create temp table exchanged as select public.platform_support_exchange(
  (select res ->> 'handoff_token' from started)) as res;
select is((select res ->> 'ok' from exchanged), 'true', 'S10. the handoff exchanges once');
select is((select res ->> 'read_only' from exchanged), 'true',
  'S11. and the SERVER declares the session read-only');
select is((select res -> 'organization' ->> 'name' from exchanged), 'Alpha Group',
  'S12. naming the tenant being supported');
select throws_ok(
  format($$ select public.platform_support_exchange(%L) $$,
         (select res ->> 'handoff_token' from started)),
  '42501', NULL, 'S13. REPLAY of the same handoff is refused');
select throws_ok(
  $$ select public.platform_support_exchange('deadbeef') $$,
  '42501', NULL, 'S14. an unknown token fails with the SAME error as a replay');
select throws_ok(
  $$ select public.platform_support_exchange('') $$,
  '42501', NULL, 'S15. a blank token fails identically — the failure mode leaks nothing');

-- ===========================================================================
-- V. THE APPROVED READS ACTUALLY RETURN DATA
-- ===========================================================================
select is(public.list_org_structure('c4000000-0000-0000-0000-0000000000a0') ->> 'ok', 'true',
  'V1. list_org_structure — the identity/context the Dashboard boots on');
select is(
  public.list_org_structure('c4000000-0000-0000-0000-0000000000a0') -> 'restaurants' -> 0 ->> 'name',
  'Alpha One', 'V2. ...and it is the RIGHT tenant''s structure');
select is(public.list_menu('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'V3. list_menu — the catalog');
select is(
  public.list_menu('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') -> 'items' -> 0 ->> 'name',
  'Falafel', 'V4. ...with the tenant''s real items');
select is(public.owner_report_range('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null,'today') ->> 'ok', 'true',
  'V5. owner_report_range — today''s reporting, the reason support exists');
select is(public.owner_daily_report('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null) ->> 'ok', 'true',
  'V6. owner_daily_report');
select is(public.sales_summary('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null) ->> 'ok', 'true',
  'V7. sales_summary');
select is(public.owner_sales_series('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null,'last7') ->> 'ok', 'true',
  'V8. owner_sales_series');
select is(public.owner_top_items('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null,'today') ->> 'ok', 'true',
  'V9. owner_top_items');
select is(public.owner_report_currency_breakdown('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null,current_date,current_date) ->> 'ok', 'true',
  'V10. owner_report_currency_breakdown');
select is(public.get_branch_kitchen_workflow_mode('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'V11. get_branch_kitchen_workflow_mode — settings');
select is(public.get_branch_pos_shift_close_enabled('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'V12. get_branch_pos_shift_close_enabled — settings');
select is(public.list_quick_note_presets('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1') ->> 'ok', 'true',
  'V13. list_quick_note_presets — settings');
select is(public.list_printers('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'V14. list_printers — hardware');
select is(public.list_devices('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'V15. list_devices — hardware');
select is(public.list_tables('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'V16. list_tables — layout');
select is(public.get_restaurant_receipt_logo('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1') ->> 'ok', 'true',
  'V17. get_restaurant_receipt_logo — branding');
select is(public.platform_support_current() ->> 'active', 'true',
  'V17b. the Dashboard can ask the SERVER whether it is in support mode');
select is(public.platform_support_current() ->> 'read_only', 'true',
  'V17c. ...and is told, by the server, that the session is read-only');
select is(public.get_restaurant_receipt_logo('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1') ->> 'can_manage', 'false',
  'V18. ...and the branding surface reports can_manage FALSE — the flag the '
  'client renders agrees with the write gate');

-- Cross-tenant: the session names Alpha and reaches nothing else.
select throws_ok(
  $$ select public.list_org_structure('c4000000-0000-0000-0000-0000000000b0') $$,
  '42501', NULL, 'V19. a session for Alpha cannot read BRAVO''s structure');
select throws_ok(
  $$ select public.list_menu('c4000000-0000-0000-0000-0000000000b0','c4000000-0000-0000-0000-0000000000b1',null) $$,
  '42501', NULL, 'V20. nor Bravo''s menu');
select throws_ok(
  $$ select public.owner_report_range('c4000000-0000-0000-0000-0000000000b0','c4000000-0000-0000-0000-0000000000b1',null,'today') $$,
  '42501', NULL, 'V21. nor Bravo''s revenue');

-- ===========================================================================
-- D. THE WITHHELD READS STAY SHUT
-- ===========================================================================
select throws_ok(
  $$ select public.list_staff('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') $$,
  '42501', NULL, 'D1. list_staff is DENIED — staff display names are not needed to support a tenant');
select throws_ok(
  $$ select public.list_members('c4000000-0000-0000-0000-0000000000a0') $$,
  '42501', NULL, 'D2. list_members is DENIED — member emails stay with the tenant');
select throws_ok(
  $$ select public.owner_order_history('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null) $$,
  '42501', NULL, 'D3. owner_order_history is DENIED — it carries customer_name and customer_phone');
select throws_ok(
  $$ select public.owner_active_orders('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null) $$,
  '42501', NULL, 'D4. owner_active_orders is DENIED — same customer PII');
select throws_ok(
  $$ select public.owner_audit_events('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null) $$,
  '42501', NULL, 'D5. owner_audit_events is DENIED — it names staff actors');

-- ===========================================================================
-- W. THE WRITE DENIAL MATRIX
-- ===========================================================================
reset role;
select ok(app.actor_rank_in_scope('c4000000-0000-0000-0000-0000000000a0', null, null) = 0,
  'W1. the WRITE rank of a support operator is ZERO — this is why every write below fails');
select ok(app.actor_read_rank_in_scope('c4000000-0000-0000-0000-0000000000a0', null, null) > 0,
  'W2. ...while the READ rank is not, which is the whole design in two assertions');
set local role authenticated;

select throws_ok(
  $$ select public.menu_upsert_category('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1',null,'Injected',9,true,null) $$,
  '42501', NULL, 'W3. MENU write refused');
select throws_ok(
  $$ select public.menu_set_item_availability('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1','c4000000-0000-0000-0000-0000000000f2','out_of_stock','x') $$,
  '42501', NULL, 'W4. MENU AVAILABILITY write refused');
select throws_ok(
  $$ select public.update_restaurant_settings('c4000000-0000-0000-0000-00000000aa01','c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','Renamed',null,null,null) $$,
  '42501', NULL, 'W5. RESTAURANT SETTINGS write refused');
select throws_ok(
  $$ select public.update_branch_settings('c4000000-0000-0000-0000-00000000aa02','c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1','Renamed',null,null,null,null) $$,
  '42501', NULL, 'W6. BRANCH SETTINGS write refused');
select throws_ok(
  $$ select public.grant_membership('c4000000-0000-0000-0000-00000000aa03','c4000000-0000-0000-0000-0000000000a0',null,null,'c4000000-0000-0000-0000-00000000ee0f','org_owner') $$,
  '42501', NULL, 'W7. MEMBERSHIP write refused — support cannot make itself an owner');
select throws_ok(
  $$ select public.create_staff_member('c4000000-0000-0000-0000-00000000aa04','c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1','Mallory','cashier',null) $$,
  '42501', NULL, 'W8. STAFF write refused');
select throws_ok(
  $$ select public.upsert_printer_device('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1',null,'Injected','bluetooth','kitchen',null,null,true) $$,
  '42501', NULL, 'W9. PRINTER write refused');
select throws_ok(
  $$ select public.create_device('c4000000-0000-0000-0000-00000000aa05','c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1','pos','Injected') $$,
  '42501', NULL, 'W10. DEVICE write refused');
select throws_ok(
  $$ select public.upsert_table('c4000000-0000-0000-0000-00000000aa09','c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1',null,'T99',4,null,true) $$,
  '42501', NULL, 'W11. TABLE/LAYOUT write refused');
select throws_ok(
  $$ select public.set_table_status('c4000000-0000-0000-0000-00000000aa0a','c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000f3','occupied') $$,
  '42501', NULL, 'W12. TABLE STATUS write refused');
-- This one refuses by RETURNING a closed envelope rather than raising: at rank
-- 0 it answers `not_found` on purpose, so it cannot even confirm the branch
-- exists. Refusal is refusal — assert the envelope, not an exception.
select is(
  public.set_kitchen_workflow_mode('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1','printer_only') ->> 'ok',
  'false', 'W13. WORKFLOW SETTINGS write refused');
-- Read the row OUTSIDE the role: a support session deliberately has no direct
-- table SELECT (this migration extended no RLS policy), so checking from inside
-- the role would read NULL and prove nothing.
select is(
  (select count(*)::int from public.branches where id = 'c4000000-0000-0000-0000-0000000000c1'),
  0, 'W13b. ...and support has NO direct table read either — RLS was not widened');
reset role;
select is(
  (select kitchen_workflow_mode from public.branches where id = 'c4000000-0000-0000-0000-0000000000c1'),
  'kds', 'W13c. ...and the branch setting really is unchanged');
set local role authenticated;
select throws_ok(
  $$ select public.sync_push('c4000000-0000-0000-0000-00000000aa07','c4000000-0000-0000-0000-0000000000d1','[]'::jsonb) $$,
  '42501', NULL, 'W14. ORDER/MONEY writes refused — sync_push needs a PIN session support has not got');
select throws_ok(
  $$ select public.create_organization('c4000000-0000-0000-0000-00000000aa08','New Co','new-co-126b','R','B','ILS','UTC',null) $$,
  '42501', NULL, 'W15. ONBOARDING refused — the one write not gated on a membership says no explicitly');
select throws_ok(
  $$ update public.restaurants set name = 'Renamed' $$,
  '42501', NULL, 'W16. a DIRECT table UPDATE is refused');
select throws_ok(
  $$ insert into public.branches (organization_id, restaurant_id, name) values ('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','Injected') $$,
  '42501', NULL, 'W17. a DIRECT table INSERT is refused');
-- Subscriptions/plans: no tenant write path exists at all, and support adds none.
--
-- HOW it is refused depends on the grant posture, and BOTH are refusals:
--   * on a from-migrations database `authenticated` holds no UPDATE grant, so
--     the statement raises 42501 before RLS is consulted;
--   * on a hosted-shaped one (where ALTER DEFAULT PRIVILEGES has granted it)
--     the `using (false)` deny policy filters the UPDATE to ZERO rows instead.
-- Pinning either one alone makes this assertion pass or fail on an accident of
-- grants rather than on support mode, so the property asserted is the one that
-- actually matters: NO SUBSCRIPTION ROW IS TOUCHED, however that comes about.
create temp table w18 (touched int);
do $w18$
declare v_touched int;
begin
  with attempt as (
    update public.organization_subscriptions set status = 'active' returning 1
  )
  select count(*)::int into v_touched from attempt;
  insert into w18 values (v_touched);
exception when insufficient_privilege then
  insert into w18 values (0);
end
$w18$;
select is((select touched from w18), 0,
  'W18. SUBSCRIPTION write changes nothing — refused by grant or by deny policy');

-- ===========================================================================
-- E. EXPIRY AND END FAIL CLOSED
-- ===========================================================================
reset role;
update platform_support_sessions set expires_at = now() - interval '1 second';
set local role authenticated;
set local request.jwt.claim.sub = 'c4000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c4000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select throws_ok(
  $$ select public.list_org_structure('c4000000-0000-0000-0000-0000000000a0') $$,
  '42501', NULL, 'E1. an EXPIRED session loses every approved read immediately');
select is(public.platform_support_current() ->> 'active', 'false',
  'E2. and the Dashboard is told the session is gone');

reset role;
update platform_support_sessions set expires_at = now() + interval '10 minutes';
set local role authenticated;
set local request.jwt.claim.sub = 'c4000000-0000-0000-0000-00000000adf0';
set local request.jwt.claims = '{"sub":"c4000000-0000-0000-0000-00000000adf0","aal":"aal2"}';
select is(public.list_org_structure('c4000000-0000-0000-0000-0000000000a0') ->> 'ok', 'true',
  'E3. restoring the TTL restores access — refresh works until expiry');
select is(public.platform_support_end(null) ->> 'ended', 'true', 'E4. End Support Access ends it');
select throws_ok(
  $$ select public.list_org_structure('c4000000-0000-0000-0000-0000000000a0') $$,
  '42501', NULL, 'E5. an ENDED session loses every approved read');
select is(public.platform_support_end(null) ->> 'ended', 'false',
  'E6. ending twice is a no-op, not an error');

-- ===========================================================================
-- N. THE TENANT IS UNCHANGED
-- ===========================================================================
reset role;
set local role authenticated;
set local request.jwt.claim.sub = 'c4000000-0000-0000-0000-00000000adf1';
set local request.jwt.claims = '{"sub":"c4000000-0000-0000-0000-00000000adf1","aal":"aal1"}';
select is(public.list_org_structure('c4000000-0000-0000-0000-0000000000a0') ->> 'ok', 'true',
  'N1. a real org_owner still reads their own organization');
select is(public.list_menu('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'N2. ...and their own menu');
select is(public.owner_report_range('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1',null,'today') ->> 'ok', 'true',
  'N3. ...and their own revenue');
select is(public.list_staff('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1') ->> 'ok', 'true',
  'N4. ...and the staff list support is denied');
select lives_ok(
  $$ select public.menu_upsert_category('c4000000-0000-0000-0000-0000000000a0','c4000000-0000-0000-0000-0000000000a1','c4000000-0000-0000-0000-0000000000c1',null,'Owner Category',5,true,null) $$,
  'N5. ...and can still WRITE — the tenant path is completely untouched');
select throws_ok(
  $$ select public.list_org_structure('c4000000-0000-0000-0000-0000000000b0') $$,
  '42501', NULL, 'N6. and still cannot reach a tenant they do not belong to');
reset role;

-- ===========================================================================
-- X. THE STRUCTURAL INVARIANTS
-- ===========================================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ 'actor_read_rank_in_scope|platform_support_can_read_scope'
      and pg_get_functiondef(p.oid) ~* '(insert into|update |delete from)\s*public\.'
      and p.proname <> 'create_organization'),
  0,
  'X1. NO function that writes a public table consults the read rank or the '
  'support guard — read-only is a property of the wiring, not a promise');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname in
      ('current_org_id', 'has_scope', 'has_role_in_scope', 'actor_rank_in_scope')
      and pg_get_functiondef(p.oid) ~ 'support'),
  0,
  'X2. the four CORE tenant helpers do not mention support at all — this '
  'migration changed no tenant policy');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f' and p.proname <> 'actor_read_rank_in_scope'
      and pg_get_functiondef(p.oid) ~ 'actor_read_rank_in_scope'),
  13, 'X3. exactly thirteen functions use the read rank (the other two approved '
      'reads consult the guard directly)');
select ok(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ 'actor_rank_in_scope\s*\('
      and pg_get_functiondef(p.oid) ~* '(insert into|update |delete from)\s*public\.') >= 30,
  'X4. non-vacuity: the untouched WRITE rank still gates a large write surface');

-- ===========================================================================
-- G. GRANTS + AUDIT
-- ===========================================================================
select ok(not has_function_privilege('anon', 'public.platform_admin_start_support_session(uuid,uuid,text)', 'EXECUTE'),
  'G1. anon cannot start a support session');
select ok(not has_function_privilege('anon', 'public.platform_support_exchange(text)', 'EXECUTE'),
  'G2. nor exchange a handoff');
select ok(not has_table_privilege('authenticated', 'public.platform_support_sessions', 'SELECT'),
  'G3. the tenant path cannot even read the support-session table');
select ok(not has_function_privilege('authenticated', 'app.platform_support_can_read_scope(uuid,uuid,uuid)', 'EXECUTE'),
  'G4. the support guard is internal — no client can call it directly');
select is(
  (select array_agg(distinct action order by action) from platform_admin_audit_events
    where action like 'platform.support.%'),
  array['platform.support.end', 'platform.support.exchange',
        'platform.support.read.dashboard', 'platform.support.start'],
  'G5. start, exchange, read and end are ALL audited');
select is(
  (select count(distinct actor_app_user_id)::int from platform_admin_audit_events
    where action like 'platform.support.%'),
  1, 'G6. every support event names ONE actor...');
select is(
  (select distinct actor_app_user_id from platform_admin_audit_events
    where action like 'platform.support.%'),
  'c4000000-0000-0000-0000-00000000ee0f'::uuid,
  'G7. ...and it is the PLATFORM OPERATOR, never the restaurant owner');
select ok(
  (select bool_and(coalesce(btrim(reason), '') <> '') from platform_admin_audit_events
    where action like 'platform.support.%'),
  'G8. and each carries the typed support reason');
select ok(
  (select bool_and(details::text not like '%' || (select res ->> 'handoff_token' from started) || '%')
     from platform_admin_audit_events where action like 'platform.support.%'),
  'G9. and NO audit row contains the handoff token');

select * from finish();
rollback;
