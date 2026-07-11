-- ============================================================================
-- AUDIT-COVERAGE-002 — pgTAP: app.audit_category classifies EVERY emitted action
-- family explicitly (settings.* -> 'settings', never 'other'); settings changes
-- now carry a SAFE before/after detail (timezone/name/status/receipt_prefix only,
-- internal ids/address/timestamps dropped); and owner_audit_events surfaces the
-- timezone change under the 'settings' category + filter. printer.* and truly
-- unknown/legacy actions still fall back to 'other' (safe, intentional).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(39);

-- ===== app.audit_category — EVERY emitted family has an explicit category =====
select is(app.audit_category('order.submitted'),          'orders',       'order.submitted -> orders');
select is(app.audit_category('order.voided'),             'voids',        'order.voided -> voids');
select is(app.audit_category('order.void_denied'),        'voids',        'order.void_denied -> voids');
select is(app.audit_category('order.discount_applied'),   'discounts',    'order.discount_applied -> discounts');
select is(app.audit_category('order.status_updated'),     'orders',       'order.status_updated -> orders');
select is(app.audit_category('payment.recorded'),         'payments',     'payment.recorded -> payments');
select is(app.audit_category('receipt_number.assigned'),  'payments',     'receipt_number.assigned -> payments');
select is(app.audit_category('shift.closed'),             'shifts',       'shift.closed -> shifts');
select is(app.audit_category('cash_drawer.closed'),       'shifts',       'cash_drawer.closed -> shifts');
select is(app.audit_category('staff.created'),            'staff',        'staff.created -> staff');
select is(app.audit_category('staff.capabilities_updated'),'staff',       'staff.capabilities_updated -> staff');
select is(app.audit_category('membership.granted'),       'access',       'membership.granted -> access');
select is(app.audit_category('employee.revoked'),         'access',       'employee.revoked -> access');
select is(app.audit_category('pin_session.failed'),       'access',       'pin_session.failed -> access');
select is(app.audit_category('device.created'),           'devices',      'device.created -> devices');
select is(app.audit_category('menu.menu_item.updated'),   'menu',         'menu.menu_item.updated -> menu');
select is(app.audit_category('table.created'),            'tables',       'table.created -> tables');
select is(app.audit_category('organization.created'),     'organization', 'organization.created -> organization');
select is(app.audit_category('sync.operation_conflict'),  'sync',         'sync.operation_conflict -> sync');
-- the FIX: settings/config changes classify as 'settings', not 'other'.
select is(app.audit_category('settings.branch.updated'),       'settings', 'settings.branch.updated -> settings (FIX)');
select is(app.audit_category('settings.restaurant.updated'),   'settings', 'settings.restaurant.updated -> settings');
select is(app.audit_category('settings.organization.updated'), 'settings', 'settings.organization.updated -> settings');
select is(app.audit_category('settings.branch.update_denied'), 'settings', 'settings.branch.update_denied -> settings');
-- printer.* config is DEFERRED to a future printer-domain ticket (printer scope
-- excluded here) -> intentional 'other'. A truly unknown/legacy action is safe.
select is(app.audit_category('printer.printer_device.updated'), 'other', 'printer.* stays other (intentional deferral)');
select is(app.audit_category('some.brand_new_unknown'),        'other', 'an unknown/legacy action falls back to other (safe)');
select is(app.audit_category(null),                            'other', 'a null action is other (never throws)');

-- ===== settings detail projection (safe before/after; internal fields dropped) =
select is(app.audit_action_has_detail('settings.branch.updated'), true, 'settings.* now carries a payload projection');
-- keeps ONLY the safe scalars; drops id/organization_id/address/timestamps.
select is(
  app.audit_safe_detail('settings.branch.updated',
    '{"id":"b1","organization_id":"o1","restaurant_id":"r1","name":"Main","address":"1 King St","timezone":"Asia/Jerusalem","receipt_prefix":"A1","status":"active","created_at":"2026-01-01","deleted_at":null}'::jsonb),
  '{"name":"Main","status":"active","timezone":"Asia/Jerusalem","receipt_prefix":"A1"}'::jsonb,
  'settings detail keeps timezone/name/status/receipt_prefix; drops ids/address/timestamps');
-- a secret-ish key in a settings payload is still dropped (privacy allowlist).
select is(
  (app.audit_safe_detail('settings.branch.updated', '{"timezone":"UTC","api_key":"leak"}'::jsonb) ? 'api_key'),
  false, 'a secret-looking key in a settings payload is never projected');

-- ===== end-to-end via owner_audit_events =====================================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000c0000', 'Org S', 'ac-s', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c0000', 'Rest S1', 'Asia/Jerusalem');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000c1a00', '00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', 'Downtown', 'Asia/Jerusalem');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000fc01', 'ac-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000c0a01', '00000000-0000-0000-0000-00000000fc01', '00000000-0000-0000-0000-0000000c0000', null, null, 'org_owner');
-- a settings.branch.updated row (as the RF-112 writer records it: whole-row
-- to_jsonb snapshots) changing UTC -> Asia/Jerusalem, at Jerusalem-local today.
insert into audit_events
  (id, organization_id, restaurant_id, branch_id, actor_app_user_id, action, old_values, new_values, occurred_at) values
  ('00000000-0000-0000-0000-0000000cae01', '00000000-0000-0000-0000-0000000c0000', '00000000-0000-0000-0000-0000000c1000', '00000000-0000-0000-0000-0000000c1a00', '00000000-0000-0000-0000-00000000fc01', 'settings.branch.updated',
   '{"id":"00000000-0000-0000-0000-0000000c1a00","organization_id":"00000000-0000-0000-0000-0000000c0000","name":"Downtown","address":"1 King St","timezone":"UTC","status":"active"}'::jsonb,
   '{"id":"00000000-0000-0000-0000-0000000c1a00","organization_id":"00000000-0000-0000-0000-0000000c0000","name":"Downtown","address":"1 King St","timezone":"Asia/Jerusalem","status":"active"}'::jsonb,
   (((now() at time zone 'Asia/Jerusalem')::date + time '10:00') at time zone 'Asia/Jerusalem'));

set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000fc01';
create temp table t_all as select app.owner_audit_events('00000000-0000-0000-0000-0000000c0000', null, null, 'today') as res;
create temp table t_settings as select app.owner_audit_events('00000000-0000-0000-0000-0000000c0000', null, null, 'today', 'settings') as res;
reset role;

-- the settings event classifies as 'settings' (NOT other), and is filterable.
select is((select res->'events'->0->>'category' from t_all), 'settings', 'RPC: the timezone/settings change is category settings (not other)');
select is((select (res->'count')::int from t_settings), 1, 'RPC: category=settings filter returns the settings event');
-- previous + new timezone are shown (from the recorded snapshots).
select is((select res->'events'->0->'old_values'->>'timezone' from t_all), 'UTC', 'RPC: previous timezone (UTC) is shown');
select is((select res->'events'->0->'new_values'->>'timezone' from t_all), 'Asia/Jerusalem', 'RPC: new timezone (Asia/Jerusalem) is shown');
-- internal/PII fields never leave the server.
select is((select res->'events'->0->'new_values' ? 'address' from t_all), false, 'RPC: the branch address is not exposed');
select is((select res->'events'->0->'new_values' ? 'id' from t_all), false, 'RPC: the internal branch id is not in the payload');
select is((select res->'events'->0->'new_values' ? 'organization_id' from t_all), false, 'RPC: the organization_id is not in the payload');
-- actor / scope / time preserved (occurred_at displayed in branch-local tz).
select is((select res->'events'->0->>'actor_name' from t_all), null, 'RPC: actor resolves (no employee profile for this app_user -> null, never an id/email)');
select is((select res->'events'->0->>'branch_id' from t_all), '00000000-0000-0000-0000-0000000c1a00', 'RPC: branch scope is preserved');
select is((select right(res->'events'->0->>'occurred_at', 5) from t_all), '10:00', 'RPC: occurred_at shows the Jerusalem-local time (10:00)');

select * from finish();
rollback;
