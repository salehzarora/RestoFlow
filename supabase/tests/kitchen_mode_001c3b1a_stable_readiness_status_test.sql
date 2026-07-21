-- ============================================================================
-- KITCHEN-MODE-001C3B1A — pgTAP: stable readiness assignment identity + a
-- configuration-independent POS spool/status report.
--
--   * additive nullable printer_assignment_id + composite FK (ON DELETE SET
--     NULL); old NULL-assignment reports accepted but NON-QUALIFYING;
--   * the canonical qualifying predicate (assignment binding matrix:
--     valid / null / wrong-branch / disabled / deleted / receipt / 58mm /
--     transport-mismatch);
--   * the readiness RPC 11-arg (legacy) + 12-arg (assignment-aware) overloads,
--     exact overload count, grants, invalid_printer_assignment rejection;
--   * qualifying consumers: transition-readiness gains the
--     kitchen_printer_assignment_required blocker; pull's claim gate requires
--     an assignment-aware qualifying report;
--   * kitchen_pos_status_reports + report RPC (config-independent, closed
--     vocab, no printer/endpoint/money columns, RLS forced, deny policies);
--   * dormancy: no setter/writer/resolver; branches remain kds/rev 1.
-- Session pinned to UTC; hex-only UUIDs; GUC conventions per house style.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(68);

-- ===== fixture ===============================================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0003b1a00a00', 'Org A', 'kmc3b1a-a', 'ILS'),
  ('00000000-0000-0000-0000-0003b1a00b00', 'Org B', 'kmc3b1a-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a00', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0003b1a00b10', '00000000-0000-0000-0000-0003b1a00b00', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0003b1a00a1a', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', 'Branch K (kds)'),
  ('00000000-0000-0000-0000-0003b1a00a2b', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', 'Branch P (printer-only)'),
  ('00000000-0000-0000-0000-0003b1a00b1a', '00000000-0000-0000-0000-0003b1a00b00', '00000000-0000-0000-0000-0003b1a00b10', 'Branch B');
update branches set kitchen_workflow_mode = 'printer_only'
  where id = '00000000-0000-0000-0000-0003b1a00a2b';

insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0003b1a00e01', 'kmc3b1a-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0003b1a00f01', '00000000-0000-0000-0000-0003b1a00e01', '00000000-0000-0000-0000-0003b1a00a00', null, null, 'org_owner');

-- devices: pos@P d001, kds@P d002, pos@K d003.
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0003b1a0d001', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'pos'),
  ('00000000-0000-0000-0000-0003b1a0d002', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'kds'),
  ('00000000-0000-0000-0000-0003b1a0d003', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a1a', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0003b1a0c001', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', '00000000-0000-0000-0000-0003b1a0d001', 'active'),
  ('00000000-0000-0000-0000-0003b1a0c002', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', '00000000-0000-0000-0000-0003b1a0d002', 'active'),
  ('00000000-0000-0000-0000-0003b1a0c003', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a1a', '00000000-0000-0000-0000-0003b1a0d003', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, revoked_at) values
  ('00000000-0000-0000-0000-0003b1a0e001', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', '00000000-0000-0000-0000-0003b1a0d001', '00000000-0000-0000-0000-0003b1a0c001', app.hash_provisioning_secret('tok-c3b1a-posp'), true, null),
  ('00000000-0000-0000-0000-0003b1a0e002', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', '00000000-0000-0000-0000-0003b1a0d002', '00000000-0000-0000-0000-0003b1a0c002', app.hash_provisioning_secret('tok-c3b1a-kdsp'), true, null),
  ('00000000-0000-0000-0000-0003b1a0e003', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a1a', '00000000-0000-0000-0000-0003b1a0d003', '00000000-0000-0000-0000-0003b1a0c003', app.hash_provisioning_secret('tok-c3b1a-posk'), true, null);

-- printer_devices on branch P: valid kitchen 80mm network (the good one),
-- 58mm kitchen, receipt-only, disabled kitchen, bluetooth kitchen, both-role.
-- pr-good is the qualifying assignment.
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('00000000-0000-0000-0000-0003b1a0aa01', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'Kitchen 80 net', 'network', 'kitchen', '80mm', true),
  ('00000000-0000-0000-0000-0003b1a0aa58', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'Kitchen 58 net', 'network', 'kitchen', '58mm', true),
  ('00000000-0000-0000-0000-0003b1a0aa2e', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'Receipt 80 net', 'network', 'receipt', '80mm', true),
  ('00000000-0000-0000-0000-0003b1a0aad0', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'Kitchen 80 disabled', 'network', 'kitchen', '80mm', false),
  ('00000000-0000-0000-0000-0003b1a0aabb', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'Kitchen 80 BT', 'bluetooth', 'kitchen', '80mm', true),
  ('00000000-0000-0000-0000-0003b1a0aab0', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b', 'Both 80 net', 'network', 'both', '80mm', true);
-- a kitchen 80mm printer on the OTHER branch K (wrong-branch fixture).
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role, paper_width, is_enabled) values
  ('00000000-0000-0000-0000-0003b1a0aac1', '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a1a', 'Kitchen 80 branchK', 'network', 'kitchen', '80mm', true);

-- ===== A. assignment column + FK + qualifying-predicate matrix ===============
select col_is_null('public', 'kitchen_printer_readiness_reports', 'printer_assignment_id',
  'printer_assignment_id is a NULLABLE column');                                                                 -- 1
select fk_ok('public', 'kitchen_printer_readiness_reports',
  array['organization_id','restaurant_id','branch_id','printer_assignment_id'],
  'public', 'printer_devices', array['organization_id','restaurant_id','branch_id','id'],
  'assignment FK targets printer_devices on the composite scope key');                                           -- 2

-- helper to insert a readiness row with a chosen assignment (network, 80mm-ish
-- fingerprint) and return whether it qualifies at revision 1.
-- valid assignment -> qualifies.
insert into kitchen_printer_readiness_reports
  (organization_id, restaurant_id, branch_id, device_id, capability, app_build, printer_purpose,
   transport_kind, paper_width, printer_fingerprint, secure_spool_available, unresolved_local_jobs,
   mode_revision, printer_assignment_id, expires_at)
values
  ('00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10', '00000000-0000-0000-0000-0003b1a00a2b',
   '00000000-0000-0000-0000-0003b1a0d001', 'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
   'abcdef0123456789abcdef0123456789', true, 0, 1, '00000000-0000-0000-0000-0003b1a0aa01', now() + interval '10 minutes');
select ok((select app.kitchen_readiness_report_qualifies(rr, 1) from kitchen_printer_readiness_reports rr
           where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a report pinned to the valid kitchen 80mm network assignment QUALIFIES');                                     -- 3
select ok((select app.kitchen_readiness_assignment_valid(rr) from kitchen_printer_readiness_reports rr
           where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'the valid assignment is assignment_valid');                                                                   -- 4
-- both-role assignment also qualifies.
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aab0'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok((select app.kitchen_readiness_assignment_valid(rr) from kitchen_printer_readiness_reports rr
           where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a role=both 80mm network assignment is also valid');                                                          -- 5
-- NULL assignment -> never qualifies (the legacy 001C3A case).
update kitchen_printer_readiness_reports set printer_assignment_id = null
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok(not (select app.kitchen_readiness_report_qualifies(rr, 1) from kitchen_printer_readiness_reports rr
               where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a NULL-assignment (legacy 001C3A) report NEVER qualifies');                                                   -- 6
-- receipt-only -> non-qualifying.
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aa2e'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok(not (select app.kitchen_readiness_assignment_valid(rr) from kitchen_printer_readiness_reports rr
               where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a receipt-only assignment is non-qualifying');                                                                -- 7
-- 58mm -> non-qualifying.
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aa58'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok(not (select app.kitchen_readiness_assignment_valid(rr) from kitchen_printer_readiness_reports rr
               where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a 58mm kitchen assignment is non-qualifying');                                                                -- 8
-- disabled -> non-qualifying.
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aad0'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok(not (select app.kitchen_readiness_assignment_valid(rr) from kitchen_printer_readiness_reports rr
               where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a disabled kitchen assignment is non-qualifying');                                                            -- 9
-- transport mismatch (report says network, assignment is bluetooth) -> non-qualifying.
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aabb'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok(not (select app.kitchen_readiness_assignment_valid(rr) from kitchen_printer_readiness_reports rr
               where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a transport-mismatched assignment (BT vs reported network) is non-qualifying');                               -- 10
-- wrong-branch assignment is structurally impossible (composite FK) -> rejected at write.
select throws_ok(
  $$ update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aac1'
       where device_id = '00000000-0000-0000-0000-0003b1a0d001' $$,
  '23503', null, 'a cross-branch assignment id is refused by the composite FK');                                 -- 11
-- ON DELETE SET NULL: soft-delete is a tombstone; a HARD delete nulls the ref.
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aabb'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
delete from printer_devices where id = '00000000-0000-0000-0000-0003b1a0aabb';
select is((select printer_assignment_id from kitchen_printer_readiness_reports
           where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  null, 'deleting the pinned printer SETS the readiness assignment NULL (history preserved)');                   -- 12
select is((select count(*)::int from kitchen_printer_readiness_reports
           where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  1, 'the readiness row itself survives the printer deletion');                                                  -- 13
-- soft-deleted printer is non-qualifying too.
update printer_devices set deleted_at = now() where id = '00000000-0000-0000-0000-0003b1a0aa01';
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aa01'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok(not (select app.kitchen_readiness_assignment_valid(rr) from kitchen_printer_readiness_reports rr
               where rr.device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'a soft-deleted (tombstoned) kitchen assignment is non-qualifying');                                           -- 14
update printer_devices set deleted_at = null where id = '00000000-0000-0000-0000-0003b1a0aa01';
delete from kitchen_printer_readiness_reports where device_id = '00000000-0000-0000-0000-0003b1a0d001';

-- ===== B. readiness RPC overloads (11-arg legacy + 12-arg assignment-aware) ===
-- 11-arg legacy: accepted, stores NULL assignment, non-qualifying.
select is(
  (public.report_kitchen_printer_readiness('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp',
    'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
    'abcdef0123456789abcdef0123456789', true, 0, 1) ->> 'ok'),
  'true', 'the LEGACY 11-arg readiness signature still works');                                                  -- 15
select is(
  (public.report_kitchen_printer_readiness('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp',
    'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
    'abcdef0123456789abcdef0123456789', true, 0, 1) ->> 'activation_ready'),
  'false', '11-arg (NULL assignment) is never activation_ready');                                                -- 16
select is((select printer_assignment_id from kitchen_printer_readiness_reports
           where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  null, '11-arg stored a NULL assignment');                                                                      -- 17
-- 12-arg assignment-aware with the valid printer: activation_ready true.
select is(
  (public.report_kitchen_printer_readiness('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp',
    'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
    'abcdef0123456789abcdef0123456789', true, 0, 1, '00000000-0000-0000-0000-0003b1a0aa01') ->> 'activation_ready'),
  'true', '12-arg with a valid assignment IS activation_ready');                                                 -- 18
select is((select printer_assignment_id from kitchen_printer_readiness_reports
           where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  '00000000-0000-0000-0000-0003b1a0aa01', '12-arg stored the pinned assignment id');                             -- 19
-- 12-arg with a foreign/invalid assignment: typed rejection, row unchanged.
select is(
  (public.report_kitchen_printer_readiness('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp',
    'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
    'abcdef0123456789abcdef0123456789', true, 0, 1, '00000000-0000-0000-0000-0003b1a0aa2e') ->> 'error'),
  'invalid_printer_assignment', '12-arg with a receipt assignment is a typed rejection');                        -- 20
select is(
  (public.report_kitchen_printer_readiness('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp',
    'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
    'abcdef0123456789abcdef0123456789', true, 0, 1, '00000000-0000-0000-0000-0003b1a0aa58') ->> 'error'),
  'invalid_printer_assignment', '12-arg with a 58mm assignment is a typed rejection');                           -- 21
select is((select printer_assignment_id from kitchen_printer_readiness_reports
           where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  '00000000-0000-0000-0000-0003b1a0aa01', 'a rejected 12-arg call never overwrote the good stored assignment');  -- 22
-- exactly TWO overloads per schema (11 + 12), no third/stale.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'report_kitchen_printer_readiness'),
  2, 'app.report_kitchen_printer_readiness has EXACTLY two overloads');                                          -- 23
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'report_kitchen_printer_readiness'),
  2, 'public.report_kitchen_printer_readiness has EXACTLY two overloads');                                       -- 24
select ok(
  not has_function_privilege('anon', 'public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer)', 'execute')
  and has_function_privilege('authenticated', 'public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer)', 'execute'),
  'both readiness overloads: anon denied, authenticated granted');                                               -- 25
-- KDS device denied on the 12-arg path.
select is(
  (public.report_kitchen_printer_readiness('00000000-0000-0000-0000-0003b1a0d002', 'tok-c3b1a-kdsp',
    'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
    'abcdef0123456789abcdef0123456789', true, 0, 1, '00000000-0000-0000-0000-0003b1a0aa01') ->> 'error'),
  'invalid_session', 'a KDS device is denied readiness on the 12-arg path');                                     -- 26

-- ===== C. qualifying consumers ===============================================
set local app.current_app_user_id = '00000000-0000-0000-0000-0003b1a00e01';
-- With the good 12-arg report present (device d001, valid assignment), the
-- transition to_printer_only readiness blocker is satisfied.
select ok(
  not (public.get_kitchen_workflow_transition_readiness(
        '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10',
        '00000000-0000-0000-0000-0003b1a00a2b') -> 'to_printer_only' -> 'blockers' ? 'no_fresh_pos_readiness'),
  'transition: a valid assignment-aware report clears no_fresh_pos_readiness');                                  -- 27
select ok(
  not (public.get_kitchen_workflow_transition_readiness(
        '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10',
        '00000000-0000-0000-0000-0003b1a00a2b') -> 'to_printer_only' -> 'blockers' ? 'kitchen_printer_assignment_required'),
  'transition: a valid assignment clears kitchen_printer_assignment_required');                                  -- 28
-- Now downgrade the report to a NULL assignment (legacy) -> the diagnostic
-- names kitchen_printer_assignment_required and the report is non-qualifying.
update kitchen_printer_readiness_reports set printer_assignment_id = null
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select ok(
  (public.get_kitchen_workflow_transition_readiness(
        '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10',
        '00000000-0000-0000-0000-0003b1a00a2b') -> 'to_printer_only' -> 'blockers' ? 'kitchen_printer_assignment_required'),
  'transition: a NULL-assignment report NAMES kitchen_printer_assignment_required');                             -- 29
select is(
  (public.get_kitchen_workflow_transition_readiness(
        '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10',
        '00000000-0000-0000-0000-0003b1a00a2b') -> 'readiness_report' ->> 'qualifying'),
  'false', 'transition: a NULL-assignment report is reported NON-qualifying');                                   -- 30

-- F1: a 58mm client files paper_width=58mm + printer_assignment_id=NULL (the
-- corrected POS behavior). The RPC ACCEPTS it as a stored diagnostic report
-- (a NULL assignment is legal), it is never activation-ready, and the
-- transition diagnostic names the PRECISE paper_width_80mm_required blocker
-- rather than degrading to a generic no_fresh_pos_readiness.
create temp table t_c3b1a_58 as
  select public.report_kitchen_printer_readiness(
    '00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp',
    'kitchen_printer_only_v1', 'b58', 'kitchen_ticket', 'network', '58mm',
    'abcdef0123456789abcdef0123456789', true, 0, 1, null) as res;
select is((select res ->> 'ok' from t_c3b1a_58), 'true',
  'F1: a 58mm + NULL-assignment report is ACCEPTED (stored diagnostic)');                                         -- 30a
select is((select res ->> 'activation_ready' from t_c3b1a_58), 'false',
  'F1: the 58mm diagnostic report is never activation_ready');                                                    -- 30b
select is(
  (select paper_width from kitchen_printer_readiness_reports
    where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  '58mm', 'F1: the stored report keeps its truthful 58mm width');                                                 -- 30c
select is(
  (select printer_assignment_id from kitchen_printer_readiness_reports
    where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  null, 'F1: the stored 58mm report keeps a NULL assignment id');                                                 -- 30d
select ok(
  (public.get_kitchen_workflow_transition_readiness(
        '00000000-0000-0000-0000-0003b1a00a00', '00000000-0000-0000-0000-0003b1a00a10',
        '00000000-0000-0000-0000-0003b1a00a2b') -> 'to_printer_only' -> 'blockers' ? 'paper_width_80mm_required'),
  'F1: the transition names the PRECISE paper_width_80mm_required (not a '
  'generic no_fresh_pos_readiness)');                                                                             -- 30e
-- Restore d001 to the 80mm + NULL-assignment state the section began with, so
-- the pull-gate tests below are unaffected by this inserted F1 scenario
-- (readiness_required for NULL, then a valid-assignment update -> pass).
select public.report_kitchen_printer_readiness(
  '00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp',
  'kitchen_printer_only_v1', 'b1', 'kitchen_ticket', 'network', '80mm',
  'abcdef0123456789abcdef0123456789', true, 0, 1, null);
-- pull claim gate: a NULL-assignment report cannot unlock the claim.
select is(
  (public.pull_kitchen_print_dispatches('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 5) ->> 'error'),
  'readiness_required', 'pull: a NULL-assignment report yields readiness_required');                             -- 31
-- restore the valid assignment -> pull gate passes (empty page, ok true).
update kitchen_printer_readiness_reports set printer_assignment_id = '00000000-0000-0000-0000-0003b1a0aa01'
  where device_id = '00000000-0000-0000-0000-0003b1a0d001';
select is(
  (public.pull_kitchen_print_dispatches('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 5) ->> 'ok'),
  'true', 'pull: an assignment-aware qualifying report passes the claim gate');                                  -- 32
select is(
  (jsonb_array_length(public.pull_kitchen_print_dispatches(
     '00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 5) -> 'dispatches'))::int,
  0, 'pull: no dispatches exist, so the qualifying claim returns an empty page');                                -- 33

-- ===== D. POS status reports =================================================
select has_table('public', 'kitchen_pos_status_reports', 'the POS status table exists');                        -- 34
select ok(
  (select c.relrowsecurity and c.relforcerowsecurity from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'kitchen_pos_status_reports')
  and not has_table_privilege('authenticated', 'public.kitchen_pos_status_reports', 'select')
  and not has_table_privilege('authenticated', 'public.kitchen_pos_status_reports', 'insert'),
  'status table: RLS enabled+forced and NO direct authenticated access');                                        -- 35
-- the status table carries NO printer/endpoint/money columns.
select ok(
  not exists (select 1 from information_schema.columns
    where table_schema='public' and table_name='kitchen_pos_status_reports'
      and column_name in ('printer_assignment_id','printer_fingerprint','transport_kind',
                          'paper_width','connection_config','host','port','address',
                          'amount_minor','printer_purpose','capability')),
  'status table has NO printer/endpoint/money/fingerprint columns');                                             -- 36
-- valid POS status upsert (config-independent: no printer needed).
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 'b1', 1, true, 0) ->> 'ok'),
  'true', 'status: a valid POS session upserts a status report');                                                -- 37
select is((select count(*)::int from kitchen_pos_status_reports where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  1, 'status: exactly one row per device');                                                                      -- 38
-- upsert again -> still one row.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 'b2', 1, false, 3) ->> 'ok'),
  'true', 'status: re-report succeeds');                                                                         -- 39
select is((select count(*)::int from kitchen_pos_status_reports where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  1, 'status: the re-report UPSERTED (still one row per device)');                                               -- 40
select is((select unresolved_local_jobs from kitchen_pos_status_reports where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  3, 'status: the upsert replaced the unresolved count');                                                        -- 41
-- expiry is server-owned ~10 min.
select ok(
  (select expires_at > now() + interval '9 minutes' and expires_at <= now() + interval '10 minutes'
     from kitchen_pos_status_reports where device_id = '00000000-0000-0000-0000-0003b1a0d001'),
  'status: expires_at is server-owned (~10 minutes ahead)');                                                     -- 42
-- a KDS device on branch K can report status even though its branch is kds
-- (status is config-independent). Wait: KDS device is DENIED (POS-only).
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d002', 'tok-c3b1a-kdsp', 'b1', 1, true, 0) ->> 'error'),
  'invalid_session', 'status: a KDS device is denied (POS-only path)');                                          -- 43
-- a POS on the KDS-mode branch K reports status fine (config-independent).
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d003', 'tok-c3b1a-posk', 'b1', 1, true, 0) ->> 'ok'),
  'true', 'status: a POS on a KDS-mode branch reports status (config-independent, no printer)');                 -- 44
-- stale revision -> typed with authoritative revision.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 'b1', 99, true, 0) ->> 'error'),
  'stale_mode_revision', 'status: a stale revision is typed');                                                   -- 45
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 'b1', 99, true, 0) -> 'mode_revision')::text,
  '1', 'status: stale revision carries the AUTHORITATIVE current revision');                                     -- 46
-- validation matrix.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', '', 1, true, 0) ->> 'error'),
  'invalid_app_build', 'status: empty app_build rejected');                                                      -- 47
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 'b1', 1, null, 0) ->> 'error'),
  'invalid_spool_state', 'status: null spool state rejected');                                                   -- 48
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-c3b1a-posp', 'b1', 1, true, -1) ->> 'error'),
  'invalid_unresolved_count', 'status: negative unresolved count rejected');                                     -- 49
-- bad token / revoked session denied.
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d001', 'tok-wrong', 'b1', 1, true, 0) ->> 'error'),
  'invalid_session', 'status: a bad token is denied');                                                           -- 50
update device_sessions set revoked_at = now() where id = '00000000-0000-0000-0000-0003b1a0e003';
select is(
  (public.report_kitchen_pos_status('00000000-0000-0000-0000-0003b1a0d003', 'tok-c3b1a-posk', 'b1', 1, true, 0) ->> 'error'),
  'invalid_session', 'status: a revoked session is denied');                                                     -- 51
update device_sessions set revoked_at = null where id = '00000000-0000-0000-0000-0003b1a0e003';
-- scope is derived server-side: the caller supplies NO org/rest/branch.
select is(
  (select array_length(string_to_array(pg_get_function_identity_arguments(p.oid), ','), 1)
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'report_kitchen_pos_status'),
  6, 'status RPC takes exactly 6 args (device/token/build/revision/spool/count) — NO client scope ids');         -- 52
select ok(
  not has_function_privilege('anon', 'public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer)', 'execute')
  and has_function_privilege('authenticated', 'public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer)', 'execute')
  and not has_function_privilege('anon', 'app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer)', 'execute'),
  'status RPC: anon denied on both signatures; authenticated granted');                                          -- 53
select ok(
  (select count(*)::int from information_schema.role_table_grants
     where table_name='kitchen_pos_status_reports' and grantee in ('anon','authenticated')
       and privilege_type in ('SELECT','INSERT','UPDATE','DELETE')) = 0,
  'status table: ZERO direct table grants to anon/authenticated');                                               -- 54
-- deny policies exist per verb.
select is(
  (select count(*)::int from pg_policies where schemaname='public' and tablename='kitchen_pos_status_reports'),
  4, 'status table: four explicit deny policies (one per verb)');                                                -- 55

-- ===== E. dormancy ===========================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app','public')
      and p.proname in ('set_branch_kitchen_workflow_mode','set_kitchen_workflow_mode',
                        'set_branch_kitchen_workflow_mode_internal',
                        'resolve_kitchen_dispatch_ambiguous_hold','resolve_kitchen_dispatch_ambiguous_hold_internal')),
  0, 'dormancy: NO setter / writer / resolver function exists');                                                 -- 56
select ok(
  (select kitchen_workflow_mode = 'kds' and kitchen_workflow_mode_revision = 1
     from branches where id = '00000000-0000-0000-0000-0003b1a00a1a'),
  'dormancy: the kds branch remains kds at revision 1');                                                         -- 57
select is(
  (select kitchen_workflow_mode_revision from branches where id = '00000000-0000-0000-0000-0003b1a00a2b'),
  1, 'dormancy: even the printer_only fixture branch was never revision-bumped by this migration');              -- 58
-- the qualifying helpers are internal (revoked from every client role).
select ok(
  not has_function_privilege('authenticated', 'app.kitchen_readiness_report_qualifies(public.kitchen_printer_readiness_reports, integer)', 'execute')
  and not has_function_privilege('anon', 'app.kitchen_readiness_report_qualifies(public.kitchen_printer_readiness_reports, integer)', 'execute'),
  'the qualifying helper is INTERNAL (no client role may execute it)');                                          -- 59
select ok(
  not has_function_privilege('authenticated', 'app.kitchen_readiness_assignment_valid(public.kitchen_printer_readiness_reports)', 'execute'),
  'the assignment-valid helper is INTERNAL');                                                                    -- 60
-- readiness/status reports cannot mutate a branch mode.
select is((select kitchen_workflow_mode from branches where id = '00000000-0000-0000-0000-0003b1a00a2b'),
  'printer_only', 'dormancy: the fixture branch mode is unchanged by all the reports above');                    -- 61
-- audit_events human-actor constraint untouched (no kitchen-mode audit added here).
select ok(
  (select count(*)::int from pg_constraint where conname = 'audit_events_actor_present') = 1,
  'dormancy: the RF-017 human-actor audit constraint is untouched');                                             -- 62
-- pos status entity string appears only in the new status RPC (no leak into audit).
select is(
  (select count(*)::int from kitchen_pos_status_reports),
  2, 'exactly the two POS status rows filed above exist (d001 + d003), no fabrication');                         -- 63

select * from finish();
rollback;
