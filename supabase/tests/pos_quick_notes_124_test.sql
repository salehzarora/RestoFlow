-- ============================================================================
-- POS-QUICK-NOTES-124 — pgTAP: Dashboard-managed reusable POS quick notes
-- (D-001/D-011/D-012/D-013/D-017/D-020; RISK R-003)
-- ============================================================================
-- Quick notes are an INPUT-CONVENIENCE layer over the EXISTING per-item note
-- field. Nothing here touches order semantics: a preset never reaches an order
-- row, an order payload, a kitchen ticket or a receipt — the POS pastes its
-- text into the same controller the cashier types into, so `order_items.notes`
-- stays byte-identical to a hand-typed note.
--
-- The backend surface under test:
--   * `quick_note_presets` — restaurant-wide (NO branch_id in v1), soft-delete,
--     owner-ordered, live-label unique, RLS enabled + FORCED, reads only.
--   * three manager+ RPCs (upsert / soft delete / reorder) on the RF-112
--     template: ledger idempotency, denial audits, success audits, and 42501
--     for every cross-tenant reach.
--   * one ADDITIVE `app.pos_menu` key, `quick_note_presets`, shaped
--     {id, label, display_order} — live + active + this restaurant only.
--   * REPORT-123 is binding: each public SECURITY INVOKER wrapper is pinned
--     TOGETHER WITH its inner app.* implementation, statically AND dynamically,
--     executed as the authenticated ROLE — not merely under the identity GUC.
--     A suite that only sets the GUC runs as superuser and proves nothing
--     about EXECUTE, which is exactly how REPORT-123 reached production.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(107);

-- ===== fixtures ==============================================================
-- Org A: two restaurants (A1 under test, A2 proves restaurant isolation) and
-- one branch. Org B proves cross-ORG isolation.
insert into organizations (id, name, slug, default_currency) values
  ('7a000000-0000-0000-0000-0000000000a0', 'QN Org A', 'qn-a', 'ILS'),
  ('7a000000-0000-0000-0000-0000000000b0', 'QN Org B', 'qn-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000a0', 'Rest A1'),
  ('7a000000-0000-0000-0000-0000000000a2', '7a000000-0000-0000-0000-0000000000a0', 'Rest A2'),
  ('7a000000-0000-0000-0000-0000000000b1', '7a000000-0000-0000-0000-0000000000b0', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', 'Branch A1a'),
  ('7a000000-0000-0000-0000-00000000b1b1', '7a000000-0000-0000-0000-0000000000b0', '7a000000-0000-0000-0000-0000000000b1', 'Branch B1a');
insert into app_users (id, email) values
  ('7a000000-0000-0000-0000-00000000ee01', 'qn-owner-a@example.test'),
  ('7a000000-0000-0000-0000-00000000ee02', 'qn-cashier-a@example.test'),
  ('7a000000-0000-0000-0000-00000000ee03', 'qn-manager-a2@example.test'),
  ('7a000000-0000-0000-0000-00000000ee04', 'qn-cashier-rest-a1@example.test'),
  ('7a000000-0000-0000-0000-00000000ee0b', 'qn-owner-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('7a000000-0000-0000-0000-00000000ab01', '7a000000-0000-0000-0000-00000000ee01', '7a000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('7a000000-0000-0000-0000-00000000ab02', '7a000000-0000-0000-0000-00000000ee02', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('7a000000-0000-0000-0000-00000000ab03', '7a000000-0000-0000-0000-00000000ee03', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a2', null, 'manager'),
  -- covers the restaurant-wide scope, but ranks BELOW manager: the principal
  -- that separates "no authority at all" (42501) from "authority, wrong rank".
  ('7a000000-0000-0000-0000-00000000ab04', '7a000000-0000-0000-0000-00000000ee04', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', null, 'cashier'),
  ('7a000000-0000-0000-0000-00000000ab0b', '7a000000-0000-0000-0000-00000000ee0b', '7a000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type, label) values
  ('7a000000-0000-0000-0000-00000000da11', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', 'pos', 'Front POS');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('7a000000-0000-0000-0000-00000000fa11', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('7a000000-0000-0000-0000-0000000005a1', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-00000000da11', '7a000000-0000-0000-0000-00000000fa11');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('7a000000-0000-0000-0000-0000000ef002', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-00000000ee02', '7a000000-0000-0000-0000-00000000ab02');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('7a000000-0000-0000-0000-00000000c501', '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-00000000a1b1', '7a000000-0000-0000-0000-0000000005a1', '7a000000-0000-0000-0000-0000000ef002', '7a000000-0000-0000-0000-00000000ab02', now() + interval '1 hour');

-- ===========================================================================
-- A. SCHEMA (25)
-- ===========================================================================
select has_table('public', 'quick_note_presets', 'A1. quick_note_presets exists');

select columns_are('public', 'quick_note_presets',
  array['id', 'organization_id', 'restaurant_id', 'label', 'display_order',
        'is_active', 'created_at', 'updated_at', 'deleted_at'],
  'A2. exact column set — nothing extra sneaked in');

-- v1 is deliberately restaurant-wide: every POS device of the restaurant shows
-- the SAME chips. A branch override, if ever wanted, is a separate feature.
select hasnt_column('public', 'quick_note_presets', 'branch_id',
  'A3. NO branch_id — v1 scope is organization + restaurant only');

select col_type_is('public', 'quick_note_presets', 'id', 'uuid', 'A4. id is uuid');
select col_type_is('public', 'quick_note_presets', 'label', 'text', 'A5. label is text');
select col_type_is('public', 'quick_note_presets', 'display_order', 'integer', 'A6. display_order is integer');
select col_type_is('public', 'quick_note_presets', 'is_active', 'boolean', 'A7. is_active is boolean');
select col_type_is('public', 'quick_note_presets', 'deleted_at', 'timestamp with time zone', 'A8. deleted_at is timestamptz');

select is(
  (select coalesce(string_agg(a.attname, ',' order by a.attname), '')
     from pg_attribute a
    where a.attrelid = 'public.quick_note_presets'::regclass
      and a.attnum > 0 and not a.attisdropped and not a.attnotnull),
  'deleted_at',
  'A9. deleted_at is the ONLY nullable column (tombstone; D-020)');

select is(
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'quick_note_presets' and column_name = 'display_order'),
  '0', 'A10. display_order defaults to 0');
select is(
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'quick_note_presets' and column_name = 'is_active'),
  'true', 'A11. is_active defaults to true');

select has_index('public', 'quick_note_presets', 'quick_note_presets_live_label_key',
  'A12. the live-label uniqueness index exists');
select ok(
  (select i.indisunique and i.indpred is not null
     from pg_index i where i.indexrelid = 'public.quick_note_presets_live_label_key'::regclass),
  'A13. it is UNIQUE and PARTIAL — a tombstoned label may be recreated');
select has_index('public', 'quick_note_presets', 'quick_note_presets_org_rest_idx',
  'A14. the tenant lookup index exists');

select ok(
  (select c.relrowsecurity and c.relforcerowsecurity
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'quick_note_presets'),
  'A15. RLS is ENABLED and FORCED (D-012 layer 1)');

-- Layer 4: the constraint still holds if every RPC were bypassed.
select throws_ok(
  $$ insert into quick_note_presets (organization_id, restaurant_id, label)
     values ('7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', '   ') $$,
  '23514', NULL, 'A16. a whitespace-only label violates the CHECK');
select throws_ok(
  $$ insert into quick_note_presets (organization_id, restaurant_id, label)
     values ('7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', repeat('x', 61)) $$,
  '23514', NULL, 'A17. a 61-character label violates the CHECK (60 is the contract)');

select has_function('app', 'upsert_quick_note_preset', array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'boolean'],
  'A18. app.upsert_quick_note_preset exists');
select has_function('app', 'soft_delete_quick_note_preset', array['uuid', 'uuid', 'uuid'],
  'A19. app.soft_delete_quick_note_preset exists');
select has_function('app', 'reorder_quick_note_presets', array['uuid', 'uuid', 'uuid[]'],
  'A20. app.reorder_quick_note_presets exists');
select has_function('public', 'upsert_quick_note_preset', array['uuid', 'uuid', 'uuid', 'uuid', 'text', 'boolean'],
  'A21. the upsert wrapper exists');
select has_function('public', 'soft_delete_quick_note_preset', array['uuid', 'uuid', 'uuid'],
  'A22. the delete wrapper exists');
select has_function('public', 'reorder_quick_note_presets', array['uuid', 'uuid', 'uuid[]'],
  'A23. the reorder wrapper exists');
select has_function('app', 'list_quick_note_presets', array['uuid', 'uuid'],
  'A24. app.list_quick_note_presets exists');
select has_function('public', 'list_quick_note_presets', array['uuid', 'uuid'],
  'A25. the list wrapper exists');

-- ===========================================================================
-- B. CREATE / VALIDATE / DUPLICATE — as the org owner, as the REAL role (23)
-- ===========================================================================
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';

create temp table b1 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c001', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f1',
  'No onions', true) as res;
create temp table b2 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c002', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f2',
  'Extra crispy', true) as res;
create temp table b3 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c003', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f3',
  'Well done', true) as res;
-- exactly 60 characters: the boundary the Dashboard field and the POS chip
-- contract both quote.
create temp table b4 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c004', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f4',
  repeat('x', 60), true) as res;
-- outer whitespace is trimmed; INTERNAL spacing is tenant content and survives.
create temp table b5 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c005', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f5',
  '  Spicy   sauce  ', true) as res;
create temp table b6 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c001', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f1',
  'No onions', true) as res;
-- case-insensitive live duplicate inside the SAME restaurant
create temp table b10 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c010', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f6',
  'no onions', true) as res;
-- the same label in ANOTHER restaurant of the same org is legitimate
create temp table b11 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c011', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a2', '7a000000-0000-0000-0000-0000000000e2',
  'No onions', true) as res;
create temp table b12 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c012', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f3',
  'Well done please', true) as res;
-- a no-op edit must NOT manufacture an audit trail entry that claims a change
create temp table b13 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c013', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f3',
  '  Well done please  ', true) as res;

select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c001', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f1',
       'Something else', true) $$,
  '42501', NULL, 'B1. a client_request_id reused with DIFFERENT input raises 42501');
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c008', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', null, '   ', true) $$,
  '42501', NULL, 'B2. a whitespace-only label is rejected by the RPC');
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c009', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', null, repeat('x', 61), true) $$,
  '42501', NULL, 'B3. a 61-character label is rejected by the RPC (strict, never truncated)');
reset role;

select is((select (res->>'ok')::boolean from b1), true, 'B4. the owner creates a preset');
select is((select res->>'action' from b1), 'created', 'B5. action = created');
select is((select res->>'entity' from b1), 'quick_note_preset', 'B6. entity = quick_note_preset');
select is(
  (select array_agg(display_order order by display_order) from quick_note_presets
    where restaurant_id = '7a000000-0000-0000-0000-0000000000a1'),
  array[0, 1, 2, 3, 4],
  'B7. creates APPEND — 0,1,2,3,4, no reused slot');
select is(
  (select label from quick_note_presets where id = '7a000000-0000-0000-0000-0000000000f5'),
  'Spicy   sauce',
  'B8. outer whitespace trimmed, internal spacing preserved exactly');
select is((select (res->>'idempotent_replay')::boolean from b6), true,
  'B9. the same client_request_id replays instead of creating twice');
select is((select (res->>'ok')::boolean from b4), true, 'B10. exactly 60 characters is accepted');
select is((select (res->>'ok')::boolean from b10), false, 'B11. a live duplicate label is refused');
select is((select res->>'error' from b10), 'duplicate_label',
  'B12. and it is refused with a SPECIFIC reason the Dashboard can render');
select is(
  (select count(*)::int from quick_note_presets where id = '7a000000-0000-0000-0000-0000000000f6'),
  0, 'B13. the refused duplicate created no row');
select is((select (res->>'ok')::boolean from b11), true,
  'B14. the SAME label in another restaurant is allowed');
select is((select res->>'action' from b12), 'updated', 'B15. an edit reports updated');
select is(
  (select label from quick_note_presets where id = '7a000000-0000-0000-0000-0000000000f3'),
  'Well done please', 'B16. the edit is stored');
select is(
  (select display_order from quick_note_presets where id = '7a000000-0000-0000-0000-0000000000f3'),
  2, 'B17. an edit never touches display_order — reorder owns ordering');
select is((select (res->>'ok')::boolean from b13), true, 'B18. a no-op edit is an idempotent success');
select is((select res->>'action' from b13), 'unchanged', 'B19. and it says so — action = unchanged');
select is(
  (select count(*)::int from audit_events where action = 'quick_note_preset.updated'),
  1, 'B20. the no-op edit wrote NO second audit event');
select is(
  (select count(*)::int from audit_events where action = 'quick_note_preset.created'),
  6, 'B21. every real create is audited (D-013)');

set local role authenticated;
create temp table b14 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c014', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f4',
  repeat('x', 60), false) as res;
reset role;
select is((select res->>'action' from b14), 'updated', 'B22. disabling is an update');
select is(
  (select is_active from quick_note_presets where id = '7a000000-0000-0000-0000-0000000000f4'),
  false, 'B23. the preset is disabled but NOT deleted');

-- ===========================================================================
-- C. AUTHORIZATION + TENANT ISOLATION (12)
-- ===========================================================================
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee0b';
create temp table c_b1 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c019', '7a000000-0000-0000-0000-0000000000b0',
  '7a000000-0000-0000-0000-0000000000b1', '7a000000-0000-0000-0000-0000000000e9',
  'No onions', true) as res;
-- org B's owner reaching into org A (R-003)
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c021', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', null, 'Cross org', true) $$,
  '42501', NULL, 'C1. a foreign organization owner is refused (R-003)');
reset role;
select is((select (res->>'ok')::boolean from c_b1), true,
  'C2. the same label in another ORGANIZATION is allowed');

-- A cashier who DOES cover the restaurant-wide scope: covered, but outranked.
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee04';
create temp table c_cash as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c020', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', null, 'Cashier note', true) as res;
create temp table c_cash_del as select app.soft_delete_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c026', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000f2') as res;
create temp table c_cash_reo as select app.reorder_quick_note_presets(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  array['7a000000-0000-0000-0000-0000000000f1', '7a000000-0000-0000-0000-0000000000f2',
        '7a000000-0000-0000-0000-0000000000f3', '7a000000-0000-0000-0000-0000000000f4',
        '7a000000-0000-0000-0000-0000000000f5']::uuid[]) as res;
reset role;
select is((select res->>'error' from c_cash), 'permission_denied',
  'C3. a cashier may not create a preset');
select is((select res->>'error' from c_cash_del), 'permission_denied',
  'C4. a cashier may not delete a preset');
select is((select res->>'error' from c_cash_reo), 'permission_denied',
  'C5. a cashier may not reorder presets');
select cmp_ok(
  (select count(*)::int from audit_events where action like 'quick\_note\_preset.%\_denied'),
  '>=', 3, 'C6. every refusal is audited (D-013) — a denial is evidence, not silence');
select is(
  (select count(*)::int from quick_note_presets where label = 'Cashier note'),
  0, 'C7. the refused cashier create wrote no row');

-- A BRANCH-scoped principal does not cover a RESTAURANT-WIDE setting at all.
-- That is the established menu-family rule (app.menu_guard): downward-only
-- coverage, so branch authority never reaches restaurant configuration.
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee02';
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c027', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', null, 'Branch scoped', true) $$,
  '42501', NULL, 'C8. a BRANCH-scoped principal has no authority over restaurant-wide config');
reset role;

-- a manager scoped to restaurant A2 has no authority over A1
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee03';
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c022', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', null, 'Cross restaurant', true) $$,
  '42501', NULL, 'C9. a manager of a SIBLING restaurant is refused');
reset role;

set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c024', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000e9',
       'Steal', true) $$,
  '42501', NULL, 'C10. editing an id owned by another organization raises 42501');
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c025', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000b1', null, 'Wrong restaurant', true) $$,
  '42501', NULL, 'C11. a restaurant outside the organization raises 42501');
reset role;

set local role authenticated;
set local app.current_app_user_id = '';
select throws_ok(
  $$ select app.upsert_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c023', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000a1', null, 'Anonymous', true) $$,
  '42501', NULL, 'C12. an unauthenticated caller raises 42501');
reset role;

-- ===========================================================================
-- D. SOFT DELETE (7)
-- ===========================================================================
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';
create temp table d1 as select app.soft_delete_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c030', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000f5') as res;
create temp table d2 as select app.soft_delete_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c030', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000f5') as res;
select throws_ok(
  $$ select app.soft_delete_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c031', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000f5') $$,
  '42501', NULL, 'D1. deleting an already-tombstoned preset raises 42501');
select throws_ok(
  $$ select app.soft_delete_quick_note_preset(
       '7a000000-0000-0000-0000-00000000c032', '7a000000-0000-0000-0000-0000000000a0',
       '7a000000-0000-0000-0000-0000000000e9') $$,
  '42501', NULL, 'D2. deleting another organization''s preset raises 42501 (R-003)');
-- the tombstoned label becomes available again — the partial index allows it
create temp table d3 as select app.upsert_quick_note_preset(
  '7a000000-0000-0000-0000-00000000c033', '7a000000-0000-0000-0000-0000000000a0',
  '7a000000-0000-0000-0000-0000000000a1', '7a000000-0000-0000-0000-0000000000f7',
  'Spicy   sauce', true) as res;
reset role;
select is((select res->>'action' from d1), 'deleted', 'D3. the owner soft-deletes a preset');
select ok(
  (select deleted_at is not null from quick_note_presets where id = '7a000000-0000-0000-0000-0000000000f5'),
  'D4. the row is TOMBSTONED, never physically removed (D-020)');
select is((select (res->>'idempotent_replay')::boolean from d2), true,
  'D5. the delete replays on the same client_request_id');
select is(
  (select count(*)::int from audit_events where action = 'quick_note_preset.deleted'),
  1, 'D6. the delete is audited exactly once');
select is((select (res->>'ok')::boolean from d3), true,
  'D7. a tombstoned label can be recreated');

-- ===========================================================================
-- E. REORDER (8)
-- ===========================================================================
-- live set of restaurant A1 at this point: f1, f2, f3, f4 (inactive but live),
-- f7. f5 is tombstoned and must NOT be part of a complete-set claim.
set local role authenticated;
create temp table e1 as select app.reorder_quick_note_presets(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
  array['7a000000-0000-0000-0000-0000000000f3', '7a000000-0000-0000-0000-0000000000f1',
        '7a000000-0000-0000-0000-0000000000f7', '7a000000-0000-0000-0000-0000000000f2',
        '7a000000-0000-0000-0000-0000000000f4']::uuid[]) as res;
select throws_ok(
  $$ select app.reorder_quick_note_presets(
       '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
       array['7a000000-0000-0000-0000-0000000000f3',
             '7a000000-0000-0000-0000-0000000000f1']::uuid[]) $$,
  '42501', NULL, 'E1. a PARTIAL list is refused — it would invent an order for the rest');
select throws_ok(
  $$ select app.reorder_quick_note_presets(
       '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
       array['7a000000-0000-0000-0000-0000000000f3', '7a000000-0000-0000-0000-0000000000f3',
             '7a000000-0000-0000-0000-0000000000f1', '7a000000-0000-0000-0000-0000000000f7',
             '7a000000-0000-0000-0000-0000000000f2']::uuid[]) $$,
  '42501', NULL, 'E2. duplicate ids are refused');
select throws_ok(
  $$ select app.reorder_quick_note_presets(
       '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
       array['7a000000-0000-0000-0000-0000000000f3', '7a000000-0000-0000-0000-0000000000f1',
             '7a000000-0000-0000-0000-0000000000f7', '7a000000-0000-0000-0000-0000000000f2',
             '7a000000-0000-0000-0000-0000000000e2']::uuid[]) $$,
  '42501', NULL, 'E3. a foreign id (sibling restaurant) is refused');
select throws_ok(
  $$ select app.reorder_quick_note_presets(
       '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1',
       array[]::uuid[]) $$,
  '42501', NULL, 'E4. an empty list is refused');
select throws_ok(
  $$ select app.reorder_quick_note_presets(
       '7a000000-0000-0000-0000-0000000000b0', '7a000000-0000-0000-0000-0000000000a1',
       array['7a000000-0000-0000-0000-0000000000f3']::uuid[]) $$,
  '42501', NULL, 'E5. a mismatched organization/restaurant pair is refused (R-003)');
reset role;
select is((select (res->>'ok')::boolean from e1), true, 'E6. the owner reorders the complete live set');
select is(
  (select array_agg(id order by display_order) from quick_note_presets
    where restaurant_id = '7a000000-0000-0000-0000-0000000000a1' and deleted_at is null),
  array['7a000000-0000-0000-0000-0000000000f3', '7a000000-0000-0000-0000-0000000000f1',
        '7a000000-0000-0000-0000-0000000000f7', '7a000000-0000-0000-0000-0000000000f2',
        '7a000000-0000-0000-0000-0000000000f4']::uuid[],
  'E7. display_order is the exact requested sequence, 0-based and dense');
select is(
  (select count(*)::int from audit_events where action = 'quick_note_preset.reordered'),
  1, 'E8. the reorder is audited');

-- ===========================================================================
-- F. POS_MENU READ CONTRACT (8)
-- ===========================================================================
-- Live + ACTIVE presets of restaurant A1, in display order:
--   f3 'Well done please' (0), f1 'No onions' (1), f7 'Spicy   sauce' (2),
--   f2 'Extra crispy' (3).  f4 is live-but-disabled; f5 is tombstoned.
set local role authenticated;
create temp table f_menu as select app.pos_menu(
  '7a000000-0000-0000-0000-00000000c501', '7a000000-0000-0000-0000-00000000da11') as res;
reset role;
select is((select (res->>'ok')::boolean from f_menu), true, 'F1. pos_menu still succeeds');
select is(
  (select array(select jsonb_object_keys(res) order by 1) from f_menu),
  array['categories', 'currency_code', 'entity', 'items', 'modifier_options', 'modifiers',
        'ok', 'quick_note_presets', 'server_ts', 'sizes', 'variants'],
  'F2. the envelope gains quick_note_presets and loses/renames NOTHING');
select is(
  (select array(select jsonb_object_keys(res->'quick_note_presets'->0) order by 1) from f_menu),
  array['display_order', 'id', 'label'],
  'F3. each preset is exactly {id, label, display_order} — no money, no tenant metadata');
select is(
  (select array_agg(p->>'label' order by (p->>'display_order')::int)
     from f_menu, jsonb_array_elements(res->'quick_note_presets') p),
  array['Well done please', 'No onions', 'Spicy   sauce', 'Extra crispy'],
  'F4. deterministic display order, labels byte-preserved');
select is(
  (select jsonb_array_length(res->'quick_note_presets') from f_menu),
  4, 'F5. exactly the four live+active presets of THIS restaurant');
select ok(
  (select not exists (select 1 from jsonb_array_elements(res->'quick_note_presets') p
                       where p->>'id' = '7a000000-0000-0000-0000-0000000000f4') from f_menu),
  'F6. a DISABLED preset is withheld from the POS');
select ok(
  (select not exists (select 1 from jsonb_array_elements(res->'quick_note_presets') p
                       where p->>'id' = '7a000000-0000-0000-0000-0000000000f5') from f_menu),
  'F7. a TOMBSTONED preset is withheld from the POS');
-- Kiosk is explicitly out of scope: the customer-facing menu must not gain
-- staff shorthand.
select ok(
  (select position('quick_note_preset' in p.prosrc) = 0
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = 'kiosk_menu'),
  'F8. app.kiosk_menu is UNCHANGED — no quick notes on the customer surface');

-- ===========================================================================
-- H. DASHBOARD READ CONTRACT (8)
-- ===========================================================================
-- Deliberately a DIFFERENT projection from pos_menu: the manager must see the
-- preset they switched off (f4) in order to switch it back on, while the
-- cashier above was correctly not offered it.
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';
create temp table h_list as select app.list_quick_note_presets(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1') as res;
select throws_ok(
  $$ select app.list_quick_note_presets(
       '7a000000-0000-0000-0000-0000000000b0', '7a000000-0000-0000-0000-0000000000b1') $$,
  '42501', NULL, 'H1. listing another organization raises 42501 (R-003)');
reset role;
set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee04';
create temp table h_cash as select app.list_quick_note_presets(
  '7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1') as res;
reset role;
select is((select (res->>'ok')::boolean from h_list), true, 'H2. a manager+ lists the presets');
select is(
  (select array(select jsonb_object_keys(res->'presets'->0) order by 1) from h_list),
  array['display_order', 'id', 'is_active', 'label'],
  'H3. each row is exactly {id, label, display_order, is_active}');
select is(
  (select array_agg(p->>'id' order by (p->>'display_order')::int)
     from h_list, jsonb_array_elements(res->'presets') p),
  array['7a000000-0000-0000-0000-0000000000f3', '7a000000-0000-0000-0000-0000000000f1',
        '7a000000-0000-0000-0000-0000000000f7', '7a000000-0000-0000-0000-0000000000f2',
        '7a000000-0000-0000-0000-0000000000f4'],
  'H4. display-ordered, and the DISABLED preset is INCLUDED');
select is(
  (select (p->>'is_active')::boolean from h_list, jsonb_array_elements(res->'presets') p
    where p->>'id' = '7a000000-0000-0000-0000-0000000000f4'),
  false, 'H5. and it is honestly flagged as switched off');
select ok(
  (select not exists (select 1 from jsonb_array_elements(res->'presets') p
                       where p->>'id' = '7a000000-0000-0000-0000-0000000000f5') from h_list),
  'H6. a TOMBSTONED preset is gone from the manager view too (D-020)');
select ok(
  (select not exists (select 1 from jsonb_array_elements(res->'presets') p
                       where p->>'id' = '7a000000-0000-0000-0000-0000000000e2') from h_list),
  'H7. the sibling restaurant''s preset is not in this list');
select is((select res->>'error' from h_cash), 'permission_denied',
  'H8. a covering cashier may not read the configuration list');

-- ===========================================================================
-- G. ACL POSTURE + THE REPORT-123 BLIND-SPOT GUARD (16)
-- ===========================================================================
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname in
          ('upsert_quick_note_preset', 'soft_delete_quick_note_preset',
           'reorder_quick_note_presets', 'list_quick_note_presets')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  4, 'G1. authenticated may execute ALL FOUR app.* implementations');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in
          ('upsert_quick_note_preset', 'soft_delete_quick_note_preset',
           'reorder_quick_note_presets', 'list_quick_note_presets')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  4, 'G2. authenticated may execute all four public wrappers');
select is(
  (select coalesce(string_agg(n.nspname || '.' || p.proname, ', ' order by p.proname), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public') and p.proname like '%quick\_note%'
      and has_function_privilege('anon', p.oid, 'EXECUTE')),
  '', 'G3. anon may execute NOTHING in the quick-note family, at either layer');
select is(
  (select coalesce(string_agg(n.nspname || '.' || p.proname, ', ' order by p.proname), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public') and p.proname like '%quick\_note%'
      and has_function_privilege('public', p.oid, 'EXECUTE')),
  '', 'G4. PUBLIC is revoked on every quick-note function');

-- The REPORT-123 defect, stated as a rule: a SECURITY INVOKER wrapper runs with
-- the CALLER's privileges, so granting only the wrapper grants nothing. This is
-- dynamic on purpose — a function added later with the same mistake fails here
-- without anyone remembering to extend a list.
select is(
  (select coalesce(string_agg(w.proname, ', ' order by w.proname), '')
     from pg_proc w
     join pg_namespace wn on wn.oid = w.pronamespace
     join pg_proc a on a.proname = w.proname
     join pg_namespace an on an.oid = a.pronamespace
    where wn.nspname = 'public' and an.nspname = 'app'
      and w.proname like '%quick\_note%'
      and w.prosecdef = false
      and has_function_privilege('authenticated', w.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', a.oid, 'EXECUTE')),
  '', 'G5. no quick-note INVOKER wrapper is granted while its app.* twin is not (REPORT-123)');
select cmp_ok(
  (select count(*)::int from pg_proc w join pg_namespace wn on wn.oid = w.pronamespace
    where wn.nspname = 'public' and w.proname like '%quick\_note%'
      and w.prosecdef = false and has_function_privilege('authenticated', w.oid, 'EXECUTE')),
  '>=', 4, 'G6. the guard above is NOT vacuous — it covers all four wrappers');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname in
          ('upsert_quick_note_preset', 'soft_delete_quick_note_preset',
           'reorder_quick_note_presets', 'list_quick_note_presets')
      and p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
  4, 'G7. all four implementations are SECURITY DEFINER with a pinned search_path');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in
          ('upsert_quick_note_preset', 'soft_delete_quick_note_preset',
           'reorder_quick_note_presets', 'list_quick_note_presets')
      and not p.prosecdef),
  4, 'G8. all four wrappers are SECURITY INVOKER (D-011 pattern)');

select ok(has_table_privilege('authenticated', 'public.quick_note_presets', 'SELECT'),
  'G9. authenticated may READ the presets');
-- The DML set only. TRUNCATE/REFERENCES are granted to anon and authenticated
-- on EVERY table by the Supabase platform baseline (menu_categories and
-- table_sections carry them identically); demanding their absence here would
-- only assert that this one table diverges from the repo. What D-011 claims is
-- that no client role can write a ROW.
select is(
  (select coalesce(string_agg(pr, ', ' order by pr), '')
     from unnest(array['INSERT', 'UPDATE', 'DELETE']) pr
    where has_table_privilege('authenticated', 'public.quick_note_presets', pr)),
  '', 'G10. authenticated holds NO row-write privilege — every write is an RPC (D-011)');
select is(
  (select coalesce(string_agg(pr, ', ' order by pr), '')
     from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) pr
    where has_table_privilege('anon', 'public.quick_note_presets', pr)),
  '', 'G11. anon cannot even READ the table');

set local role authenticated;
set local app.current_app_user_id = '7a000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '7a000000-0000-0000-0000-0000000000a0';
create temp table g_own as select count(*)::int as n from public.quick_note_presets
  where organization_id = '7a000000-0000-0000-0000-0000000000a0';
create temp table g_foreign as select count(*)::int as n from public.quick_note_presets
  where organization_id = '7a000000-0000-0000-0000-0000000000b0';
-- Two boundaries agree here (D-012): the missing GRANT refuses the statement,
-- and the deny policy would refuse the row if the grant ever returned.
select throws_ok(
  $$ insert into public.quick_note_presets (organization_id, restaurant_id, label)
     values ('7a000000-0000-0000-0000-0000000000a0', '7a000000-0000-0000-0000-0000000000a1', 'Direct') $$,
  '42501', NULL, 'G12. a direct INSERT is refused even for the org owner');
select throws_ok(
  $$ update public.quick_note_presets set label = 'hacked'
      where id = '7a000000-0000-0000-0000-0000000000f1' $$,
  '42501', NULL, 'G15. a direct UPDATE is refused');
select throws_ok(
  $$ delete from public.quick_note_presets
      where id = '7a000000-0000-0000-0000-0000000000f1' $$,
  '42501', NULL, 'G16. a direct DELETE is refused');
reset role;
select cmp_ok((select n from g_own), '>', 0, 'G13. the owner READS the presets of their own organization');
select is((select n from g_foreign), 0,
  'G14. and sees ZERO rows of the other organization (R-003)');

select * from finish();
rollback;
