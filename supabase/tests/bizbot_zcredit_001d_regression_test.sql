-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: default-OFF regression lane (legacy behaviour and unchanged surfaces). Rollback-only synthetic fixtures, real SQL roles.
-- Terse error output (correction C1 review): a statement error that reaches psql prints its message only,
-- never a DETAIL line that could echo a generated card-shaped value from a failing row. pgTAP lives_ok
-- prints DETAIL itself, so no write carrying such a value is wrapped in lives_ok (throws_ok or a helper that
-- returns only the SQLSTATE is used instead).
\set VERBOSITY terse
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';
select no_plan();
-- ZC001D shared synthetic fixture (copied verbatim into each 001D pgTAP file).
-- This scoped pilot pins the Maps Burger scope UUIDs (D-051 point 1; the
-- in-repo constants of 20261017004438). Every row below is a synthetic fixture
-- in a disposable local / CI database, never hosted restaurant operations.
create function pg_temp.zc_id(label text) returns uuid language sql immutable as
$$ select md5('bizbot-zcredit-001d-synthetic-' || label)::uuid $$;
create function pg_temp.zc_org() returns uuid language sql immutable as
$$ select '20605c2b-3145-4803-a990-bbec3d9c1096'::uuid $$;
create function pg_temp.zc_rest() returns uuid language sql immutable as
$$ select 'de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid $$;
create function pg_temp.zc_branch() returns uuid language sql immutable as
$$ select '2847c0be-3e31-45a5-957c-508729f1971e'::uuid $$;
-- A canonical lowercase UUID v4 text identity per label.
create function pg_temp.zc_lop(label text) returns text language sql immutable as
$$ select substr(h, 1, 8) || '-' || substr(h, 9, 4) || '-4' || substr(h, 14, 3) || '-8' || substr(h, 18, 3)
          || '-' || substr(h, 21, 12)
     from (select md5('bizbot-zcredit-001d-lop-' || label) as h) s $$;

insert into organizations (id, name, slug, default_currency) values
  (pg_temp.zc_org(), 'ZC001D Pilot (synthetic)', 'zc001d-pilot-synthetic', 'ILS'),
  (pg_temp.zc_id('org_b'), 'ZC001D Foreign (synthetic)', 'zc001d-foreign-synthetic', 'ILS');
insert into restaurants (id, organization_id, name, timezone) values
  (pg_temp.zc_rest(), pg_temp.zc_org(), 'ZC001D Pilot Restaurant', 'UTC'),
  (pg_temp.zc_id('rest_b'), pg_temp.zc_id('org_b'), 'ZC001D Foreign Restaurant', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  (pg_temp.zc_branch(), pg_temp.zc_org(), pg_temp.zc_rest(), 'ZC001D Pilot Branch', 'UTC'),
  (pg_temp.zc_id('branch_sib'), pg_temp.zc_org(), pg_temp.zc_rest(), 'ZC001D Sibling Branch', 'UTC'),
  (pg_temp.zc_id('branch_b'), pg_temp.zc_id('org_b'), pg_temp.zc_id('rest_b'), 'ZC001D Foreign Branch', 'UTC');

-- Devices: d1 / d2 pilot POS tills, d3 a pilot KDS, d4 a foreign POS, d5 a sibling-branch POS.
create temp table _zc_device as
select d, org, rest, branch, dtype from (values
  (1, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), 'pos'),
  (2, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), 'pos'),
  (3, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), 'kds'),
  (4, pg_temp.zc_id('org_b'), pg_temp.zc_id('rest_b'), pg_temp.zc_id('branch_b'), 'pos'),
  (5, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_id('branch_sib'), 'pos')) v(d, org, rest, branch, dtype);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type)
select pg_temp.zc_id('device-' || d), org, rest, branch, dtype from _zc_device;
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
select pg_temp.zc_id('pairing-' || d), org, rest, branch, pg_temp.zc_id('device-' || d), 'active' from _zc_device;
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                             session_token_ref, expires_at)
select pg_temp.zc_id('dsession-' || d), org, rest, branch, pg_temp.zc_id('device-' || d),
       pg_temp.zc_id('pairing-' || d), app.hash_provisioning_secret('zc-token-' || d), now() + interval '30 days'
  from _zc_device;

-- Staff: n, role, PIN device. 1 cashier@d1, 2 manager@d1, 3 manager@d2, 4 kitchen_staff@d1,
-- 5 accountant@d1, 6 cashier@d3 (KDS), 7 cashier@d4 (foreign), 8 cashier@d2,
-- 9 org_owner (attested approver; PIN on d1), 10 cashier@d5 (sibling branch).
create temp table _zc_staff as
select n, role, d from (values
  (1, 'cashier', 1), (2, 'manager', 1), (3, 'manager', 2), (4, 'kitchen_staff', 1), (5, 'accountant', 1),
  (6, 'cashier', 3), (7, 'cashier', 4), (8, 'cashier', 2), (9, 'org_owner', 1), (10, 'cashier', 5)) v(n, role, d);
insert into app_users (id, email)
select pg_temp.zc_id('user-' || n), 'zc001d-staff-' || n || '@example.test' from _zc_staff;
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role)
select pg_temp.zc_id('membership-' || s.n), pg_temp.zc_id('user-' || s.n), dv.org,
       case when s.role = 'org_owner' then null else dv.rest end,
       case when s.role = 'org_owner' then null else dv.branch end, s.role
  from _zc_staff s join _zc_device dv on dv.d = s.d;
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name)
select pg_temp.zc_id('employee-' || s.n), dv.org, dv.rest, dv.branch, pg_temp.zc_id('user-' || s.n),
       pg_temp.zc_id('membership-' || s.n), 'ZC001D Staff ' || s.n
  from _zc_staff s join _zc_device dv on dv.d = s.d;
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id,
                          resolved_membership_id, expires_at)
select pg_temp.zc_id('pin-' || s.n), dv.org, dv.rest, dv.branch, pg_temp.zc_id('dsession-' || s.d),
       pg_temp.zc_id('employee-' || s.n), pg_temp.zc_id('membership-' || s.n), now() + interval '6 hours'
  from _zc_staff s join _zc_device dv on dv.d = s.d;

-- An OPEN shift with an ACTIVE drawer on tills d1, d2, d4 and d5.
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id,
                    resolved_membership_id, local_operation_id, status)
select pg_temp.zc_id('shift-' || dv.d), dv.org, dv.rest, dv.branch, pg_temp.zc_id('device-' || dv.d),
       pg_temp.zc_id('employee-' || s.n), pg_temp.zc_id('membership-' || s.n), 'zc001d-shift-' || dv.d, 'open'
  from _zc_device dv join _zc_staff s on s.n = case dv.d when 1 then 1 when 2 then 8 when 4 then 7 when 5 then 10 end
 where dv.d in (1, 2, 4, 5);
insert into cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id,
                                  opened_by_employee_profile_id, opening_float_minor, local_operation_id)
select pg_temp.zc_id('drawer-' || s.device_id), s.organization_id, s.restaurant_id, s.branch_id, s.device_id, s.id,
       s.opened_by_employee_profile_id, 0, 'zc001d-drawer-' || s.local_operation_id
  from shifts s where s.id in (select pg_temp.zc_id('shift-' || d) from generate_series(1, 5) d);

-- An unpaid synthetic order of the given device's branch.
create function pg_temp.zc_order(label text, total bigint default 1234, d integer default 1,
                                 status text default 'submitted', currency text default 'ILS')
returns uuid language sql volatile security definer set search_path = '' as $$
  insert into public.orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
      opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor,
      discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision)
  select pg_temp.zc_id('order-' || zc_order.label), dv.organization_id, dv.restaurant_id, dv.branch_id, dv.id,
         pg_temp.zc_id('pin-' || st.n), pg_temp.zc_id('employee-' || st.n), pg_temp.zc_id('membership-' || st.n),
         'takeaway', zc_order.status, zc_order.currency, zc_order.total, 0, 0, zc_order.total,
         'zc001d-order-' || zc_order.label, 1
    from public.devices dv
    cross join (select case zc_order.d when 2 then 8 when 4 then 7 when 5 then 10 else 1 end as n) st
   where dv.id = pg_temp.zc_id('device-' || zc_order.d)
  returning id;
$$;

-- Operator helpers (run as the migration owner, like an operator SQL session).
create function pg_temp.zc_owner() returns uuid language sql immutable as $$ select pg_temp.zc_id('user-9') $$;
-- D-060 point 2: the native POS transport principal - an auth.users row with no app user (the JWT subject of every
-- POS request below) - and the original-caller binding the service-only calls pass for it.
insert into auth.users (id, email) values (pg_temp.zc_id('transport-principal'), 'zc001d-transport@example.test');
create function pg_temp.zc_caller() returns uuid language sql immutable as $$ select pg_temp.zc_id('transport-principal') $$;
create function pg_temp.zc_pilot(mode text, enabled boolean default true, test_cap bigint default 100000,
                                 live_cap bigint default 1000000, window_until timestamptz default null)
returns jsonb language sql volatile as $$
  select app.set_card_payments_pilot(enabled, mode, window_until, test_cap, live_cap,
    'ZC001D synthetic revision', 'zc001d-op/ref-1', pg_temp.zc_owner());
$$;
create function pg_temp.zc_bind(d integer, mode text, lifecycle text default 'enabled', term text default null,
                                cred text default null, reason_code text default null)
returns jsonb language plpgsql volatile as $$
declare
  v_term text := coalesce(term, 'zc-term-' || mode || '-' || d);
  v_cred text := coalesce(cred, 'zc-cred-' || mode || '-' || d);
  v_rc text := coalesce(reason_code, case mode when 'test' then 'test_setup' else 'live_activation' end);
  r jsonb;
begin
  r := app.set_payment_terminal(pg_temp.zc_id('device-' || d), mode, v_term, v_cred, 'configured', v_rc,
         'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner());
  if lifecycle <> 'configured' and coalesce((r ->> 'ok')::boolean, false) then
    r := app.set_payment_terminal(pg_temp.zc_id('device-' || d), mode, v_term, v_cred, lifecycle, v_rc,
           'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner());
  end if;
  return r;
end $$;
-- The adapter's configuration maps for device d (references, tokens and ids only).
create function pg_temp.zc_terminals(d integer, mode text) returns jsonb language sql immutable as $$
  select jsonb_build_object('zc-term-' || mode || '-' || d, 'zc-cred-' || mode || '-' || d) $$;
create function pg_temp.zc_credentials(d integer, mode text) returns jsonb language sql immutable as $$
  select jsonb_build_object('zc-cred-' || mode || '-' || d,
    case mode when 'live' then jsonb_build_object('mode', 'live', 'scope', 'merchant', 'restaurant_id', pg_temp.zc_rest())
              else jsonb_build_object('mode', 'test', 'scope', 'development') end) $$;
-- The service-only claim as the adapter makes it (call under SET LOCAL ROLE service_role).
create function pg_temp.zc_staff_device(n integer) returns integer language sql immutable as $$
  select case n when 3 then 2 when 6 then 3 when 7 then 4 when 8 then 2 when 10 then 5 else 1 end $$;
create function pg_temp.zc_claim(n integer, lop text, mode text, amount bigint default 1234,
                                 order_id uuid default null, expected_revision integer default null,
                                 version text default 'alpha16-l32-v1', d integer default null)
returns jsonb language sql volatile as $$
  select public.card_attempt_claim(pg_temp.zc_id('pin-' || zc_claim.n),
    pg_temp.zc_id('device-' || coalesce(zc_claim.d, pg_temp.zc_staff_device(zc_claim.n))),
    'zc-token-' || coalesce(zc_claim.d, pg_temp.zc_staff_device(zc_claim.n)), zc_claim.lop, zc_claim.mode,
    zc_claim.amount, 'ILS', zc_claim.order_id, zc_claim.expected_revision,
    case zc_claim.mode when 'live' then 'production' else 'test' end,
    pg_temp.zc_terminals(coalesce(zc_claim.d, pg_temp.zc_staff_device(zc_claim.n)), zc_claim.mode),
    pg_temp.zc_credentials(coalesce(zc_claim.d, pg_temp.zc_staff_device(zc_claim.n)), zc_claim.mode),
    zc_claim.version, pg_temp.zc_caller());
$$;
-- The scope-bound finish with the claim / adapter-read facts (call as service_role).
create function pg_temp.zc_finish(c jsonb, source text, outcome text, fields jsonb default '{}'::jsonb,
                                  poll text default null)
returns jsonb language sql volatile as $$
  select public.card_attempt_finish((c ->> 'attempt_row_id')::uuid, (c ->> 'organization_id')::uuid,
    (c ->> 'device_id')::uuid, c ->> 'local_operation_id', c ->> 'mode', (c ->> 'amount_minor')::bigint,
    c ->> 'currency_code', source, outcome, fields, poll);
$$;
-- A commit reply that approves (the essential approval inputs present and valid).
create function pg_temp.zc_approved_fields() returns jsonb language sql immutable as $$
  select jsonb_build_object('error_flag', false, 'provider_return_code', 0, 'approval_type', 'approved',
                            'provider_status_code', 'ok1', 'provider_return_class', 'approved') $$;
-- One payment.create operation (the canonical recording leg shape by default).
create function pg_temp.zc_pay_op(lop text, order_id uuid, tender text default 'card', amount bigint default 1234,
                                  extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('local_operation_id', lop, 'operation_type', 'payment.create',
    'target_entity', 'order', 'target_id', order_id, 'client_created_at', '2026-10-24T00:00:00Z',
    'payload', jsonb_build_object('order_id', order_id, 'tender_type', tender, 'amount_tendered_minor', amount))
    || extra $$;
-- app.sync_push through the public wrapper as the POS (call under SET LOCAL ROLE authenticated).
create function pg_temp.zc_push(n integer, ops jsonb, d integer default null) returns jsonb
language sql volatile as $$
  select public.sync_push(pg_temp.zc_id('pin-' || zc_push.n),
    pg_temp.zc_id('device-' || coalesce(zc_push.d, pg_temp.zc_staff_device(zc_push.n))), zc_push.ops);
$$;
-- Test-only time travel (rolled back with the file): the frozen-fact triggers
-- forbid moving start_deadline_at / retention_until, so these owner-only helpers
-- disable the one guard trigger for a single UPDATE (the table lock it takes is
-- held until the file's ROLLBACK).
create function pg_temp.zc_age_attempt(attempt_row_id uuid, deadline_past boolean default true,
                                       retention_past boolean default false)
returns void language plpgsql as $$
begin
  alter table app.card_provider_attempts disable trigger card_attempts_guard;
  update app.card_provider_attempts a
     set start_deadline_at = case when zc_age_attempt.deadline_past then now() - interval '1 second'
                                  else a.start_deadline_at end,
         retention_until = case when zc_age_attempt.retention_past and a.mode = 'test'
                                then now() - interval '1 second' else a.retention_until end
   where a.id = zc_age_attempt.attempt_row_id;
  alter table app.card_provider_attempts enable trigger card_attempts_guard;
end $$;
create function pg_temp.zc_age_event(event_id uuid) returns void language plpgsql as $$
begin
  alter table app.card_provider_private_events disable trigger card_events_guard;
  update app.card_provider_private_events e set retention_until = now() - interval '1 second'
   where e.id = zc_age_event.event_id and e.mode = 'test';
  alter table app.card_provider_private_events enable trigger card_events_guard;
end $$;
-- Results captured across role switches.
create temp table _zc_r (label text primary key, r jsonb);
grant all on _zc_r to authenticated, service_role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
-- ZC001D FIXTURE END: the concurrency runner commits only the prefix above.

-- ===========================================================================
-- RG helpers (pg_temp; rolled back with the file).
-- ===========================================================================
-- The keys of a JSON object, sorted bytewise (anything that is not an object = no key).
create function pg_temp.rg_keys(j jsonb) returns text[] language sql immutable as $$
  select coalesce(array_agg(k collate "C" order by k collate "C"), '{}'::text[])
    from jsonb_object_keys(case when jsonb_typeof(j) = 'object' then j else '{}'::jsonb end) k $$;
create function pg_temp.rg_sorted(a text[]) returns text[] language sql immutable as $$
  select coalesce(array_agg(x collate "C" order by x collate "C"), '{}'::text[]) from unnest(a) x $$;
-- Every object key / every string value at any depth of a JSON document.
create function pg_temp.rg_all_keys(j jsonb) returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct k), '{}'::text[])
    from jsonb_path_query(j, 'strict $.**') v
    cross join lateral jsonb_object_keys(case when jsonb_typeof(v) = 'object' then v else '{}'::jsonb end) k $$;
create function pg_temp.rg_all_strings(j jsonb) returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct v #>> '{}'), '{}'::text[])
    from jsonb_path_query(j, 'strict $.**') v
   where jsonb_typeof(v) = 'string' $$;
-- Captured results.
create function pg_temp.rg_get(p_label text) returns jsonb language sql stable as $$
  select z.r from _zc_r z where z.label = p_label $$;
create function pg_temp.rg_res(p_label text, p_i integer default 0) returns jsonb language sql stable as $$
  select z.r -> 'results' -> p_i from _zc_r z where z.label = p_label $$;
-- One order row of a captured pos_order_snapshots answer.
create function pg_temp.rg_row(p_label text, p_order_label text) returns jsonb language sql stable as $$
  select o from _zc_r z cross join lateral jsonb_array_elements(z.r -> 'orders') o
   where z.label = p_label and o ->> 'order_id' = pg_temp.zc_id('order-' || p_order_label)::text $$;
-- The 18 row keys of app.pos_order_snapshots before 001D (order_edit_001b_pos_order_snapshots test 05).
create function pg_temp.rg_snap_keys() returns text[] language sql immutable as $$
  select pg_temp.rg_sorted(array['order_id', 'order_code', 'revision', 'status', 'order_type', 'table_label',
    'currency_code', 'created_at', 'updated_at', 'sync_at', 'subtotal_minor', 'discount_total_minor',
    'tax_total_minor', 'grand_total_minor', 'payment_status', 'edit_count', 'kitchen_edit_ack_pending',
    'has_active_round']) $$;
-- The 17 keys of an applied payment.create answer today (record_payment's result + the sync_push merge).
create function pg_temp.rg_pay_keys() returns text[] language sql immutable as $$
  select pg_temp.rg_sorted(array['ok', 'payment_id', 'order_id', 'method', 'receipt_number', 'change_due_minor',
    'shift_id', 'cash_drawer_session_id', 'payment_revision', 'order_revision', 'auto_completed', 'order_status',
    'server_ts', 'idempotency_replay', 'local_operation_id', 'operation_type', 'status']) $$;
-- The expected applied payment.create answer minus its volatile keys (payment_id, receipt_number, server_ts).
create function pg_temp.rg_paid(p_order_label text, p_lop text, p_method text, p_change bigint,
                                p_order_status text default 'submitted', p_auto boolean default false,
                                p_order_revision integer default 2, p_d integer default 1)
returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', true, 'method', p_method, 'status', 'applied',
    'order_id', pg_temp.zc_id('order-' || p_order_label), 'shift_id', pg_temp.zc_id('shift-' || p_d),
    'order_status', p_order_status, 'auto_completed', p_auto, 'operation_type', 'payment.create',
    'order_revision', p_order_revision, 'change_due_minor', p_change, 'payment_revision', 1,
    'idempotency_replay', false, 'local_operation_id', p_lop,
    'cash_drawer_session_id', pg_temp.zc_id('drawer-' || pg_temp.zc_id('device-' || p_d))) $$;
-- The payments row of an order (owner read) and its expected shape.
create function pg_temp.rg_payment(p_order_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('id', p.id, 'method', p.method, 'status', p.status, 'amount_minor', p.amount_minor,
    'tendered_minor', p.tendered_minor, 'change_minor', p.change_minor, 'currency_code', p.currency_code,
    'device_id', p.device_id, 'shift_id', p.shift_id, 'cash_drawer_session_id', p.cash_drawer_session_id,
    'local_operation_id', p.local_operation_id, 'receipt_number', p.receipt_number)
    from public.payments p where p.order_id = pg_temp.zc_id('order-' || p_order_label) $$;
create function pg_temp.rg_payment_expect(p_method text, p_amount bigint, p_tendered bigint, p_change bigint,
                                          p_lop text, p_answer jsonb, p_d integer default 1)
returns jsonb language sql immutable as $$
  select jsonb_build_object('id', p_answer ->> 'payment_id', 'method', p_method, 'status', 'completed',
    'amount_minor', p_amount, 'tendered_minor', p_tendered, 'change_minor', p_change, 'currency_code', 'ILS',
    'device_id', pg_temp.zc_id('device-' || p_d), 'shift_id', pg_temp.zc_id('shift-' || p_d),
    'cash_drawer_session_id', pg_temp.zc_id('drawer-' || pg_temp.zc_id('device-' || p_d)),
    'local_operation_id', p_lop, 'receipt_number', p_answer ->> 'receipt_number') $$;
-- Counters for the "nothing card-related was written" checks (owner role).
create function pg_temp.rg_counts() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'audit', (select count(*) from public.audit_events a
               where a.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'card_audit', (select count(*) from public.audit_events a where a.action like 'card_attempt.%'),
    'events', (select count(*) from app.card_provider_private_events),
    'attempts', (select count(*) from app.card_provider_attempts),
    'payments', (select count(*) from public.payments p
                  where p.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b')))) $$;
-- One statement under the current role; a raise becomes {raised:true, sqlstate}.
create function pg_temp.rg_try(q text) returns jsonb language plpgsql volatile as $$
declare
  v jsonb;
begin
  execute q into v;
  return jsonb_build_object('raised', false, 'result', v);
exception when others then
  return jsonb_build_object('raised', true, 'sqlstate', sqlstate);
end $$;
-- Money-free / void operations in the canonical envelope.
create function pg_temp.rg_status_op(p_lop text, p_order_id uuid, p_new_status text) returns jsonb
language sql immutable as $$
  select jsonb_build_object('local_operation_id', p_lop, 'operation_type', 'order.status', 'target_entity', 'order',
    'target_id', p_order_id, 'client_created_at', '2026-10-24T00:00:00Z',
    'payload', jsonb_build_object('order_id', p_order_id, 'new_status', p_new_status)) $$;
create function pg_temp.rg_void_op(p_lop text, p_order_id uuid) returns jsonb language sql immutable as $$
  select jsonb_build_object('local_operation_id', p_lop, 'operation_type', 'order.void', 'target_entity', 'order',
    'target_id', p_order_id, 'client_created_at', '2026-10-24T00:00:00Z',
    'payload', jsonb_build_object('order_id', p_order_id, 'reason', 'Wrong order')) $$;
-- The generic rejection a dispatched RPC's raise becomes (minus the identity key).
create function pg_temp.rg_generic(p_operation_type text) returns jsonb language sql immutable as $$
  select jsonb_build_object('operation_type', p_operation_type, 'ok', false, 'error', 'rejected',
    'sqlstate', '42501', 'detail', null, 'status', 'rejected', 'idempotency_replay', false) $$;

-- ---------------------------------------------------------------------------
-- Pre-001D Activity-log oracle: the LIVE bodies before 20261023225657, copied
-- verbatim with comments stripped (app.audit_action_has_detail and
-- app.audit_safe_detail from 20261008170200 L1334-1388 / L1401-1536,
-- app.audit_category from 20260725090000 L2797-2824, and the p_sensitive_only
-- predicate of app.owner_audit_events from 20261008170200 L2198-2214).
-- ---------------------------------------------------------------------------
create function pg_temp.rg_pre_keys() returns text[] language sql immutable as $$
  select array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    'dispatch_mode',
    'completion_mode','completion_trigger',
    'denied_reason',
    'resulting_charge_state',
    'availability','availability_reason','item_name',
    'table_label','from_table_label','to_table_label',
    'from_status','to_status','group_label',
    'voided_from_status','device_type','kitchen_ack_required',
    'round_number','added_item_count',
    'display_name','paper_width','is_enabled','connection_type',
    'dispatch_type',
    'kitchen_workflow_mode','kitchen_workflow_mode_revision','resolution','reason_code',
    'recorded_offline',
    'edit_number','up_to_edit_number','removed_item_count','modified_item_count',
    'acknowledged_count','kitchen_channel',
    'order_edit_enabled','order_edit_finished_food_manager_only'] $$;
create function pg_temp.rg_pre_has_detail(p_action text) returns boolean language sql immutable as $$
  select coalesce(p_action, '') like 'order.void%'
      or p_action like 'order.discount%'
      or p_action like 'order.status%'
      or p_action =    'order.submitted'
      or p_action like 'order.table_mov%'
      or p_action like 'staff.capabilities%'
      or p_action =    'staff.created'
      or p_action like 'membership.%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%'
      or p_action like 'settings.%'
      or p_action like 'menu.%.availability%'
      or p_action like 'table.status%'
      or p_action like 'table.tables_%'
      or p_action like 'table.link%'
      or p_action like 'table.unlink%'
      or p_action like 'order.items_add%'
      or p_action like 'order.round_status%'
      or p_action like 'order.edit%'
      or p_action like 'printer.%'
      or p_action like 'kitchen.%'
      or p_action =    'pin_session.failed' $$;
create function pg_temp.rg_pre_safe_detail(p_action text, p_values jsonb) returns jsonb
language plpgsql immutable as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  if not pg_temp.rg_pre_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;
  foreach v_key in array pg_temp.rg_pre_keys() loop
    if (p_action like 'order.items_add%' or p_action like 'order.round_status%'
        or p_action like 'printer.%'
        or p_action like 'kitchen.%')
       and v_key like '%\_minor' escape '\' then
      continue;
    end if;
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations','open_cash_drawer']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;
  return v_out;
end $$;
create function pg_temp.rg_pre_category(p_action text) returns text language sql immutable as $$
  select case
    when p_action like 'order.discount%'                               then 'discounts'
    when p_action like 'order.void%'                                   then 'voids'
    when p_action like 'order.%'                                       then 'orders'
    when p_action like 'payment.%' or p_action like 'receipt_number.%' then 'payments'
    when p_action like 'shift.%'   or p_action like 'cash_drawer.%'    then 'shifts'
    when p_action like 'staff.%'                                       then 'staff'
    when p_action like 'membership.%' or p_action like 'employee.%'
         or p_action like 'pin_session.%'                             then 'access'
    when p_action like 'device.%'                                     then 'devices'
    when p_action like 'settings.%'                                   then 'settings'
    when p_action like 'printer.%'                                    then 'settings'
    when p_action like 'kitchen.%'                                    then 'orders'
    when p_action like 'menu.%'                                       then 'menu'
    when p_action like 'table.%'                                      then 'tables'
    when p_action like 'organization.%'                               then 'organization'
    when p_action like 'sync.%'                                       then 'sync'
    else 'other'
  end $$;
create function pg_temp.rg_pre_sensitive(p_action text) returns boolean language sql immutable as $$
  select p_action like '%denied'
      or p_action like 'order.void%'
      or p_action like 'order.discount%'
      or p_action =    'order.edited'
      or p_action like 'staff.capabilities%'
      or p_action =    'staff.pin_set'
      or p_action like 'membership.%'
      or p_action like 'employee.revok%'
      or p_action like 'device.revok%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%' $$;
-- Non-card actions of the sweep (every family the Activity log knows, plus unknown / NULL / a
-- bare "card_attempt" without the family suffix).
create function pg_temp.rg_actions() returns setof text language sql immutable as $$
  select unnest(array['payment.recorded', 'payment.denied', 'receipt_number.assigned', 'order.submitted',
    'order.status_updated', 'order.status_update_denied', 'order.void', 'order.voided', 'order.void_denied',
    'order.void_acknowledged', 'order.discount_applied', 'order.discount_denied', 'order.table_moved',
    'order.table_move_denied', 'order.items_added', 'order.items_add_denied', 'order.round_status_updated',
    'order.edited', 'order.edit_denied', 'order.edit_acknowledged', 'shift.opened', 'shift.closed',
    'shift.close_denied', 'shift.reconciled', 'cash_drawer.opened', 'cash_drawer.no_sale_opened',
    'staff.capabilities_updated', 'staff.created', 'staff.pin_set', 'membership.revoked', 'employee.revoked',
    'device.revoked', 'settings.branch.updated', 'menu.item.availability_set', 'menu.item.created',
    'table.status_set', 'table.tables_linked', 'table.link_denied', 'table.unlink', 'printer.created',
    'kitchen.dispatch_created', 'organization.updated', 'sync.operation_rejected', 'sync.operation_conflict',
    'pin_session.failed', 'pin_session.started', 'kiosk.order.submitted', 'unknown.action', 'card_attempt',
    null]::text[]) $$;
-- A hostile payload: every global allowlisted key (typed), the card-family keys, references,
-- card data, nested values and a capabilities object with unknown members.
create function pg_temp.rg_hostile() returns jsonb language sql immutable as $$
  select (select jsonb_object_agg(k, case when k like '%\_minor' escape '\' then to_jsonb(1234)
                                         when k like '%count' or k like '%number' or k like '%revision'
                                           then to_jsonb(3)
                                         when k in ('locked', 'is_enabled', 'kitchen_ack_required', 'recorded_offline',
                                                    'order_edit_enabled', 'order_edit_finished_food_manager_only')
                                           then to_jsonb(true)
                                         else to_jsonb('v-' || k) end)
            from unnest(pg_temp.rg_pre_keys()) k)
      || jsonb_build_object('currency_code', 'ILS', 'attempt_state', 'approved', 'mode', 'live',
           'refusal_code', 'conflict', 'anomaly_code', 'amount_mismatch', 'release_requested', true,
           'confirmation_source', 'provider_report', 'prior_refusal_code', 'precondition_failed',
           'resume_count', 1, 'outcome', 'dispatched', 'local_operation_id', 'legacy-op-1',
           'payment_id', 'p-1', 'order_id', 'o-1', 'method', 'card', 'receipt_number', '7',
           'terminal_ref', 'zc-term-live-1', 'credential_ref', 'zc-cred-live-1', 'provider_reference', 'REF123',
           'card_last4', '4242', 'nested', jsonb_build_object('status', 'x'), 'list', jsonb_build_array(1, 'a'),
           'capabilities', jsonb_build_object('apply_discount', true, 'void_order', false, 'close_shift', 'x',
             'apply_full_comp', 1, 'manage_menu_availability', true, 'manage_table_operations', false,
             'open_cash_drawer', true, 'unknown_cap', true, 'nested_cap', jsonb_build_object('a', 1))) $$;
-- The order.submitted audit shape written by the LIVE app.submit_order (20260809090000 L1003-1019).
create function pg_temp.rg_order_submitted_values() returns jsonb language sql immutable as $$
  select jsonb_build_object('order_id', pg_temp.zc_id('order-cash1'), 'status', 'submitted', 'revision', 1,
    'currency_code', 'ILS', 'subtotal_minor', 1234, 'discount_total_minor', 0, 'tax_total_minor', 0,
    'grand_total_minor', 1234, 'device_id', pg_temp.zc_id('device-1'), 'local_operation_id', 'zc001d-order-cash1',
    'order_type', 'takeaway', 'table_id', null, 'shift_id', null,
    'resolved_membership_id', pg_temp.zc_id('membership-1'), 'item_count', 2, 'modifier_count', 0) $$;

-- ===========================================================================
-- 1. Default OFF after the fixture: the five card tables are empty and the
--    capability probe carries exactly the existing branch_features keys.
-- ===========================================================================
select is((select count(*) from app.card_payments_pilot_revisions), 0::bigint,
  'RG-01 default OFF: app.card_payments_pilot_revisions holds no row after the fixture (no operator revision = pilot OFF)');
select is((select count(*) from app.payment_terminals), 0::bigint,
  'RG-02 default OFF: app.payment_terminals holds no row after the fixture (no device binding)');
select is((select count(*) from app.card_provider_attempts), 0::bigint,
  'RG-03 default OFF: app.card_provider_attempts holds no row after the fixture');
select is((select count(*) from app.card_provider_private_events), 0::bigint,
  'RG-04 default OFF: app.card_provider_private_events holds no row after the fixture');
select is((select count(*) from app.card_attempt_identity_tombstones), 0::bigint,
  'RG-05 default OFF: app.card_attempt_identity_tombstones holds no row after the fixture');

set local role authenticated;
insert into _zc_r select 'caps_cashier_d1', public.pin_session_capabilities(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'));
insert into _zc_r select 'caps_manager_d1', public.pin_session_capabilities(pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'));
insert into _zc_r select 'ctx_off', public.card_attempt_context(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', null, null);
reset role;
select is(pg_temp.rg_keys(pg_temp.rg_get('caps_cashier_d1') -> 'branch_features'),
  pg_temp.rg_sorted(array['order_edit_enabled', 'order_edit_finished_food_manager_only']),
  'RG-06 capabilities (cashier on d1, no binding): branch_features has exactly the existing keys {order_edit_enabled, order_edit_finished_food_manager_only}');
select is(pg_temp.rg_get('caps_cashier_d1') -> 'branch_features',
  '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": false}'::jsonb,
  'RG-07 capabilities (cashier on d1, no binding): branch_features values unchanged - no card_terminal_enabled / card_terminal_mode key');
select is(pg_temp.rg_keys(pg_temp.rg_get('caps_cashier_d1')),
  pg_temp.rg_sorted(array['ok', 'entity', 'role', 'capabilities', 'branch_features']),
  'RG-08 capabilities (cashier on d1, no binding): the envelope keeps exactly its five top-level keys');
select is(pg_temp.rg_get('caps_manager_d1') -> 'branch_features',
  '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": false}'::jsonb,
  'RG-09 capabilities (manager on d1, no binding): branch_features unchanged');

-- ===========================================================================
-- 2. Cash and hand-recorded card payments keep the existing behaviour with no
--    binding, with only a TEST binding and after that binding is retired.
-- ===========================================================================
do $$ begin
  perform pg_temp.zc_order('cash1', 1234);
  perform pg_temp.zc_order('card1', 1500);
end $$;
set local role authenticated;
insert into _zc_r select 'cash1', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('cash1'), pg_temp.zc_id('order-cash1'), 'cash', 2000)));
insert into _zc_r select 'card1', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('card1'), pg_temp.zc_id('order-card1'), 'card', 1500)));
reset role;

select is(pg_temp.rg_keys(pg_temp.rg_get('cash1')), pg_temp.rg_sorted(array['ok', 'results', 'server_ts']),
  'RG-10 cash payment.create (d1, no binding): the push envelope keeps exactly {ok, results, server_ts}');
select is(pg_temp.rg_res('cash1') - 'payment_id' - 'receipt_number' - 'server_ts',
  pg_temp.rg_paid('cash1', pg_temp.zc_lop('cash1'), 'cash', 766),
  'RG-11 cash payment.create (d1, no binding): applied exactly as before (method cash, change_due_minor 766, the open shift / active drawer of d1, order_revision 2, no auto-completion)');
select is(pg_temp.rg_keys(pg_temp.rg_res('cash1')), pg_temp.rg_pay_keys(),
  'RG-12 cash payment.create (d1, no binding): the sync answer carries exactly the existing 17 keys');
select is(pg_temp.rg_payment('cash1'),
  pg_temp.rg_payment_expect('cash', 1234, 2000, 766, pg_temp.zc_lop('cash1'), pg_temp.rg_res('cash1')),
  'RG-13 cash payment.create (d1, no binding): one completed cash payments row (amount 1234, tendered 2000, change 766, ILS, the answered payment id and receipt number)');
select ok((pg_temp.rg_res('cash1') ->> 'receipt_number') ~ '^[1-9][0-9]*$'
          and (select o.receipt_number from public.orders o where o.id = pg_temp.zc_id('order-cash1'))
              = pg_temp.rg_res('cash1') ->> 'receipt_number',
  'RG-14 cash payment.create (d1, no binding): a server-assigned branch receipt number is stamped on the order');
select is((select jsonb_build_object('status', so.status, 'result', so.result) from public.sync_operations so
            where so.device_id = pg_temp.zc_id('device-1') and so.local_operation_id = pg_temp.zc_lop('cash1')),
  jsonb_build_object('status', 'applied',
    'result', pg_temp.rg_res('cash1') - 'local_operation_id' - 'operation_type' - 'status'),
  'RG-15 cash payment.create (d1, no binding): the sync ledger row is applied and memoizes record_payment''s own result');
select is((select count(*) from public.audit_events a
            where a.organization_id = pg_temp.zc_org() and a.action in ('payment.recorded', 'receipt_number.assigned')
              and a.new_values ->> 'order_id' = pg_temp.zc_id('order-cash1')::text), 2::bigint,
  'RG-16 cash payment.create (d1, no binding): payment.recorded and receipt_number.assigned audited as before');
select is(pg_temp.rg_res('card1') - 'payment_id' - 'receipt_number' - 'server_ts',
  pg_temp.rg_paid('card1', pg_temp.zc_lop('card1'), 'card', 0),
  'RG-17 hand-recorded card payment.create (d1, no binding): applied exactly as before (method card, change 0)');
select is(pg_temp.rg_keys(pg_temp.rg_res('card1')), pg_temp.rg_pay_keys(),
  'RG-18 hand-recorded card payment.create (d1, no binding): the sync answer carries exactly the existing 17 keys');
select is(pg_temp.rg_payment('card1'),
  pg_temp.rg_payment_expect('card', 1500, 1500, 0, pg_temp.zc_lop('card1'), pg_temp.rg_res('card1')),
  'RG-19 hand-recorded card payment.create (d1, no binding): one completed card payments row (tendered = amount = 1500, change 0)');
select is(pg_temp.rg_counts() - 'audit' - 'payments', '{"card_audit": 0, "events": 0, "attempts": 0}'::jsonb,
  'RG-20 no binding: the cash and hand-recorded card payments wrote no attempt, no private event and no card_attempt.* audit row');

-- ---------------------------------------------------------------------------
-- 3a. pos_order_snapshots under default OFF: exactly the 18 pre-001D row keys.
-- ---------------------------------------------------------------------------
set local role authenticated;
insert into _zc_r select 'snap_off', public.pos_order_snapshots(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'));
reset role;
select is(jsonb_array_length(pg_temp.rg_get('snap_off') -> 'orders'), 2,
  'RG-21 snapshot (default OFF): the read returns the two orders of the pilot branch');
select is((select count(*) from jsonb_array_elements(pg_temp.rg_get('snap_off') -> 'orders') o
            where pg_temp.rg_keys(o) <> pg_temp.rg_snap_keys()), 0::bigint,
  'RG-22 snapshot (default OFF): every row carries exactly the 18 pre-001D keys (no card_attempt_in_progress)');
select is(pg_temp.rg_keys(pg_temp.rg_get('snap_off')),
  pg_temp.rg_sorted(array['ok', 'entity', 'server_ts', 'window_start', 'orders', 'has_more', 'next_cursor']),
  'RG-23 snapshot (default OFF): the envelope keeps exactly its seven keys');

-- ---------------------------------------------------------------------------
-- 2b. Only a TEST binding on d1, then retired: the legacy card tender records.
-- ---------------------------------------------------------------------------
insert into _zc_r select 'bind_test', pg_temp.zc_bind(1, 'test');
select is((select jsonb_agg(jsonb_build_object('device', t.device_id, 'mode', t.mode, 'lifecycle', t.lifecycle))
             from app.payment_terminals t),
  jsonb_build_array(jsonb_build_object('device', pg_temp.zc_id('device-1'), 'mode', 'test', 'lifecycle', 'enabled')),
  'RG-24 setup: the only binding of the pilot is an enabled TEST binding of d1');
do $$ begin perform pg_temp.zc_order('card2', 1600); end $$;
set local role authenticated;
insert into _zc_r select 'card2', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('card2'), pg_temp.zc_id('order-card2'), 'card', 1600)));
reset role;
select is(pg_temp.rg_res('card2') - 'payment_id' - 'receipt_number' - 'server_ts',
  pg_temp.rg_paid('card2', pg_temp.zc_lop('card2'), 'card', 0),
  'RG-25 hand-recorded card payment.create (d1, only an enabled TEST binding): applied exactly as before - the TEST phase leaves the legacy card tender unchanged (no card_terminal_required)');
select is(pg_temp.rg_keys(pg_temp.rg_res('card2')), pg_temp.rg_pay_keys(),
  'RG-26 hand-recorded card payment.create (d1, only a TEST binding): the sync answer carries exactly the existing 17 keys');
select is(pg_temp.rg_payment('card2'),
  pg_temp.rg_payment_expect('card', 1600, 1600, 0, pg_temp.zc_lop('card2'), pg_temp.rg_res('card2')),
  'RG-27 hand-recorded card payment.create (d1, only a TEST binding): one completed card payments row');
insert into _zc_r select 'drain_test', app.set_payment_terminal(pg_temp.zc_id('device-1'), 'test', 'zc-term-test-1',
  'zc-cred-test-1', 'draining', 'test_end', 'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner());
insert into _zc_r select 'retire_test', app.set_payment_terminal(pg_temp.zc_id('device-1'), 'test', 'zc-term-test-1',
  'zc-cred-test-1', 'retired', 'test_end', 'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner());
select is(jsonb_build_array(pg_temp.rg_get('drain_test') ->> 'new_lifecycle', pg_temp.rg_get('retire_test') ->> 'new_lifecycle'),
  '["draining", "retired"]'::jsonb,
  'RG-28 setup: the TEST binding of d1 is drained, then retired');
do $$ begin perform pg_temp.zc_order('card3', 1700); end $$;
set local role authenticated;
insert into _zc_r select 'card3', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('card3'), pg_temp.zc_id('order-card3'), 'card', 1700)));
reset role;
select is(pg_temp.rg_res('card3') - 'payment_id' - 'receipt_number' - 'server_ts',
  pg_temp.rg_paid('card3', pg_temp.zc_lop('card3'), 'card', 0),
  'RG-29 hand-recorded card payment.create (d1, retired TEST binding): applied exactly as before');
select is(jsonb_build_object('attempts', (select count(*) from app.card_provider_attempts),
    'card_audit', (select count(*) from public.audit_events a where a.action like 'card_attempt.%'),
    'non_operator_events', (select count(*) from app.card_provider_private_events e
                             where e.action <> 'operator.payment_terminal_updated')),
  '{"attempts": 0, "card_audit": 0, "non_operator_events": 0}'::jsonb,
  'RG-30 TEST binding phase: the hand-recorded card payments created no attempt, no card_attempt.* audit and no private event beyond the operator binding events');

-- ===========================================================================
-- 4. Activity-log projections unchanged for non-card actions (oracle = the
--    pre-001D bodies above, fed the same inputs).
-- ===========================================================================
create temp table _rg_payloads (name text primary key, payload jsonb);
insert into _rg_payloads values
  ('hostile', pg_temp.rg_hostile()),
  ('payment_recorded', (select a.new_values from public.audit_events a
                         where a.action = 'payment.recorded'
                           and a.new_values ->> 'order_id' = pg_temp.zc_id('order-cash1')::text)),
  ('order_submitted', pg_temp.rg_order_submitted_values()),
  ('card_keys_only', jsonb_build_object('attempt_state', 'sent', 'mode', 'live', 'amount_minor', 1234,
                                        'currency_code', 'ILS', 'refusal_code', 'conflict', 'outcome', 'refused')),
  ('empty', '{}'::jsonb), ('array', '[1, "a"]'::jsonb), ('scalar', '"x"'::jsonb), ('sql_null', null);
select is(app.audit_safe_detail('payment.recorded', (select p.payload from _rg_payloads p where p.name = 'payment_recorded')),
  jsonb_build_object('status', 'completed', 'amount_minor', 1234, 'tendered_minor', 2000, 'change_minor', 766),
  'RG-31 Activity log: payment.recorded (the cash payment''s own audit row) projects exactly {status, amount_minor, tendered_minor, change_minor} as before - currency_code still not projected');
select is(app.audit_safe_detail('payment.recorded', (select p.payload from _rg_payloads p where p.name = 'payment_recorded')),
  pg_temp.rg_pre_safe_detail('payment.recorded', (select p.payload from _rg_payloads p where p.name = 'payment_recorded')),
  'RG-32 Activity log: payment.recorded projection equals the pre-001D projection of the same values');
select is(app.audit_safe_detail('order.submitted', pg_temp.rg_order_submitted_values()),
  jsonb_build_object('status', 'submitted', 'order_type', 'takeaway', 'subtotal_minor', 1234,
                     'discount_total_minor', 0, 'grand_total_minor', 1234),
  'RG-33 Activity log: order.submitted (the submit_order audit shape) projects exactly {status, order_type, subtotal_minor, discount_total_minor, grand_total_minor} as before');
select is(app.audit_safe_detail('order.submitted', pg_temp.rg_order_submitted_values()),
  pg_temp.rg_pre_safe_detail('order.submitted', pg_temp.rg_order_submitted_values()),
  'RG-34 Activity log: order.submitted projection equals the pre-001D projection of the same values');
select ok(not (app.audit_safe_detail('payment.recorded', pg_temp.rg_hostile())
               ?| array['currency_code', 'attempt_state', 'mode', 'refusal_code', 'anomaly_code', 'release_requested',
                        'confirmation_source', 'prior_refusal_code', 'resume_count', 'outcome'])
          and app.audit_safe_detail('payment.recorded', pg_temp.rg_hostile())
              ?& array['amount_minor', 'tendered_minor', 'change_minor', 'status'],
  'RG-35 Activity log: no card-family key became a global key (a hostile payment.recorded payload keeps its money keys and gains none of the ten card keys)');
select is(jsonb_build_array(app.audit_category('payment.recorded'), app.audit_category('shift.closed'),
                            app.audit_category('order.void')),
  '["payments", "shifts", "voids"]'::jsonb,
  'RG-36 Activity log: app.audit_category unchanged for payment.recorded (payments), shift.closed (shifts) and order.void (voids)');
select is((select count(*) from pg_temp.rg_actions() a cross join _rg_payloads p
            where app.audit_safe_detail(a, p.payload) is distinct from pg_temp.rg_pre_safe_detail(a, p.payload)),
  0::bigint,
  'RG-37 Activity log: app.audit_safe_detail equals the pre-001D projection for every non-card action x payload of the sweep (50 actions incl. NULL; hostile, real payment.recorded, order.submitted, card-keys-only, empty, array, scalar, NULL payloads)');
select is((select count(*) from pg_temp.rg_actions() a
            where app.audit_category(a) is distinct from pg_temp.rg_pre_category(a)), 0::bigint,
  'RG-38 Activity log: app.audit_category equals the pre-001D category for every non-card action of the sweep');
select is((select count(*) from pg_temp.rg_actions() a
            where app.audit_action_has_detail(a) is distinct from pg_temp.rg_pre_has_detail(a)), 0::bigint,
  'RG-39 Activity log: app.audit_action_has_detail equals the pre-001D predicate for every non-card action of the sweep');

-- ===========================================================================
-- LIVE pilot setup for the remaining lanes: operator revision ON (live) and an
-- enabled LIVE binding of d1.
-- ===========================================================================
insert into _zc_r select 'pilot_live', pg_temp.zc_pilot('live');
insert into _zc_r select 'bind_live', pg_temp.zc_bind(1, 'live');
select is(jsonb_build_array(pg_temp.rg_get('pilot_live') ->> 'ok', pg_temp.rg_get('pilot_live') ->> 'mode',
                            pg_temp.rg_get('bind_live') ->> 'binding_mode', pg_temp.rg_get('bind_live') ->> 'new_lifecycle'),
  '["true", "live", "live", "enabled"]'::jsonb,
  'RG-40 setup: LIVE operator revision ON and an enabled LIVE binding of d1');

-- ===========================================================================
-- 3b. pos_order_snapshots with LIVE claims: the key appears only while the
--     claim is active, the stamp follows the ledger, then the key disappears.
-- ===========================================================================
do $$ begin
  perform pg_temp.zc_order('snap_free', 1234);
  perform pg_temp.zc_order('snap_decl', 1300);
  perform pg_temp.zc_order('snap_plain', 1400);
end $$;
set local role service_role;
insert into _zc_r select 'claim_free', pg_temp.zc_claim(1, pg_temp.zc_lop('snap_free'), 'live', 1234,
  pg_temp.zc_id('order-snap_free'), 1);
insert into _zc_r select 'claim_decl', pg_temp.zc_claim(1, pg_temp.zc_lop('snap_decl'), 'live', 1300,
  pg_temp.zc_id('order-snap_decl'), 1);
reset role;
select is(jsonb_build_array(pg_temp.rg_get('claim_free') ->> 'claim_created', pg_temp.rg_get('claim_free') ->> 'state',
                            pg_temp.rg_get('claim_decl') ->> 'claim_created', pg_temp.rg_get('claim_decl') ->> 'state'),
  '["true", "sent", "true", "sent"]'::jsonb,
  'RG-41 setup: LIVE claims (sent) on the orders snap_free and snap_decl');
set local role authenticated;
insert into _zc_r select 'snap_b1', public.pos_order_snapshots(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'));
reset role;
select is(pg_temp.rg_row('snap_b1', 'snap_free') -> 'card_attempt_in_progress', 'true'::jsonb,
  'RG-42 snapshot: an order with an active LIVE claim (sent) carries card_attempt_in_progress = true');
select is(pg_temp.rg_keys(pg_temp.rg_row('snap_b1', 'snap_free')),
  pg_temp.rg_sorted(pg_temp.rg_snap_keys() || 'card_attempt_in_progress'::text),
  'RG-43 snapshot: the claimed row carries exactly the 18 pre-001D keys plus card_attempt_in_progress');
select ok((pg_temp.rg_row('snap_b1', 'snap_free') ->> 'sync_at')::timestamptz
          >= (select a.updated_at from app.card_provider_attempts a
               where a.id = (pg_temp.rg_get('claim_free') ->> 'attempt_row_id')::uuid),
  'RG-44 snapshot: the claimed row''s sync_at is >= the attempt''s updated_at (the claim reaches the incremental cursor)');
select is((select count(*) from jsonb_array_elements(pg_temp.rg_get('snap_b1') -> 'orders') o
            where o ->> 'order_id' not in (pg_temp.zc_id('order-snap_free')::text, pg_temp.zc_id('order-snap_decl')::text)
              and pg_temp.rg_keys(o) <> pg_temp.rg_snap_keys()), 0::bigint,
  'RG-45 snapshot: every order without an attempt keeps exactly the 18 pre-001D keys while other orders are claimed');
select is((select count(*) from jsonb_array_elements(pg_temp.rg_get('snap_b1') -> 'orders') o
             join public.orders ord on ord.id = (o ->> 'order_id')::uuid
             left join public.payments p on p.order_id = ord.id and p.status = 'completed' and p.deleted_at is null
            where not exists (select 1 from app.card_provider_attempts a where a.order_id = ord.id)
              and (o ->> 'sync_at')::timestamptz
                  is distinct from greatest(ord.updated_at, coalesce(p.updated_at, ord.updated_at))), 0::bigint,
  'RG-46 snapshot: every order without an attempt keeps the pre-001D sync_at stamp (greatest of the order and its completed payment updated_at; no round or edit exists)');

set local role service_role;
insert into _zc_r select 'free_unknown', pg_temp.zc_finish(pg_temp.rg_get('claim_free'), 'commit', 'unknown');
insert into _zc_r select 'free_lookup', pg_temp.zc_finish(pg_temp.rg_get('claim_free'), 'lookup', 'not_found',
  '{}'::jsonb, 'auto');
reset role;
set local role authenticated;
insert into _zc_r select 'snap_b2', public.pos_order_snapshots(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'));
reset role;
select is(jsonb_build_array(pg_temp.rg_get('free_lookup') ->> 'state',
                            pg_temp.rg_row('snap_b2', 'snap_free') -> 'card_attempt_in_progress'),
  '["unknown", true]'::jsonb,
  'RG-47 snapshot: an unknown, unfreed, unresolved LIVE attempt still carries card_attempt_in_progress = true');

-- ===========================================================================
-- 9. free_order is role-first: a cashier gets permission_denied before any
--    attempt lookup, with no audit and no private event.
-- ===========================================================================
insert into _zc_r select 'free_attempt_before', to_jsonb(a) from app.card_provider_attempts a
 where a.id = (pg_temp.rg_get('claim_free') ->> 'attempt_row_id')::uuid;
insert into _zc_r select 'free_counts_before', pg_temp.rg_counts();
set local role service_role;
insert into _zc_r select 'free_cashier_missing', public.card_attempt_free_order(pg_temp.zc_id('pin-1'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('never-claimed'), 'Provider report shows no charge',
  'provider_report', 'rpt-001', pg_temp.zc_caller());
insert into _zc_r select 'free_cashier_real', public.card_attempt_free_order(pg_temp.zc_id('pin-1'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('snap_free'), 'Provider report shows no charge',
  'provider_report', 'rpt-001', pg_temp.zc_caller());
reset role;
insert into _zc_r select 'free_counts_after', pg_temp.rg_counts();
select is(pg_temp.rg_get('free_cashier_missing') - 'server_ts', '{"ok": false, "error": "permission_denied"}'::jsonb,
  'RG-48 free_order role-first: a cashier naming a NONEXISTENT attempt id is answered permission_denied (never attempt_not_found - decided before any attempt lookup)');
select is(pg_temp.rg_keys(pg_temp.rg_get('free_cashier_missing')), pg_temp.rg_sorted(array['ok', 'error', 'server_ts']),
  'RG-49 free_order role-first: the refusal is exactly {ok, error, server_ts} - no attempt detail');
select is(pg_temp.rg_get('free_cashier_real') - 'server_ts', pg_temp.rg_get('free_cashier_missing') - 'server_ts',
  'RG-50 free_order role-first: a cashier naming a freeable LIVE attempt gets the identical permission_denied (no attempt_id / attempt_state)');
select is(pg_temp.rg_get('free_counts_after'), pg_temp.rg_get('free_counts_before'),
  'RG-51 free_order role-first: the two cashier refusals wrote no tenant audit (no card_attempt.denied), no private event, no attempt and no payment');
select is((select to_jsonb(a) from app.card_provider_attempts a
            where a.id = (pg_temp.rg_get('claim_free') ->> 'attempt_row_id')::uuid),
  pg_temp.rg_get('free_attempt_before'),
  'RG-52 free_order role-first: the attempt row is byte-identical after the cashier refusals (not freed, not touched)');

-- The manager free (provider evidence) and a provider decline end the two claims.
set local role service_role;
insert into _zc_r select 'free_manager', public.card_attempt_free_order(pg_temp.zc_id('pin-2'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('snap_free'), 'Provider report shows no charge',
  'provider_report', 'rpt-001', pg_temp.zc_caller());
insert into _zc_r select 'decline', pg_temp.zc_finish(pg_temp.rg_get('claim_decl'), 'commit', 'declined',
  jsonb_build_object('error_flag', true, 'provider_return_code', 33, 'approval_type', 'declined',
                     'provider_return_class', 'declined'));
reset role;
select is(jsonb_build_array(pg_temp.rg_get('free_manager') ->> 'classification', pg_temp.rg_get('decline') ->> 'state'),
  '["freed", "declined"]'::jsonb,
  'RG-53 setup: the manager free (provider_report evidence) freed snap_free and a provider decline finished snap_decl');
set local role authenticated;
insert into _zc_r select 'snap_b3', public.pos_order_snapshots(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'));
insert into _zc_r select 'snap_inc', public.pos_order_snapshots(
  p_pin_session_id => pg_temp.zc_id('pin-1'), p_device_id => pg_temp.zc_id('device-1'),
  p_since_at => (pg_temp.rg_row('snap_b2', 'snap_free') ->> 'sync_at')::timestamptz,
  p_since_id => pg_temp.zc_id('order-snap_free'));
reset role;
select is(pg_temp.rg_keys(pg_temp.rg_row('snap_b3', 'snap_free')), pg_temp.rg_snap_keys(),
  'RG-54 snapshot: after the manager free the row is back to exactly the 18 pre-001D keys (card_attempt_in_progress absent)');
select ok((pg_temp.rg_row('snap_b3', 'snap_free') ->> 'sync_at')::timestamptz
          > (pg_temp.rg_row('snap_b2', 'snap_free') ->> 'sync_at')::timestamptz,
  'RG-55 snapshot: the free moved the row''s sync_at forward');
select is(pg_temp.rg_keys(pg_temp.rg_row('snap_inc', 'snap_free')), pg_temp.rg_snap_keys(),
  'RG-56 snapshot: an incremental read from the pre-free cursor re-delivers the freed order, without card_attempt_in_progress');
select is(pg_temp.rg_keys(pg_temp.rg_row('snap_b3', 'snap_decl')), pg_temp.rg_snap_keys(),
  'RG-57 snapshot: after a provider decline the row is back to exactly the 18 pre-001D keys');
select ok((pg_temp.rg_row('snap_b3', 'snap_decl') ->> 'sync_at')::timestamptz
          > (pg_temp.rg_row('snap_b1', 'snap_decl') ->> 'sync_at')::timestamptz,
  'RG-58 snapshot: the decline moved the row''s sync_at forward');

-- ===========================================================================
-- 7. Two-organization anti-oracle: a non-provider payment.create naming a
--    foreign / out-of-scope order is answered by record_payment's own refusal,
--    never payment_in_progress, identical to a nonexistent order.
-- ===========================================================================
do $$ begin
  perform pg_temp.zc_order('claimed', 1234);
  perform pg_temp.zc_order('foreign1', 1234, 4);
end $$;
set local role service_role;
insert into _zc_r select 'claim_claimed', pg_temp.zc_claim(1, pg_temp.zc_lop('claimed'), 'live', 1234,
  pg_temp.zc_id('order-claimed'), 1);
reset role;
select is(jsonb_build_array(pg_temp.rg_get('claim_claimed') ->> 'claim_created',
                            app.card_order_claim_active(pg_temp.zc_org(), pg_temp.zc_id('order-claimed'))),
  '["true", true]'::jsonb,
  'RG-59 setup: an active LIVE claim on the pilot order "claimed"');
insert into _zc_r select 'ao_attempt_before', to_jsonb(a) from app.card_provider_attempts a
 where a.id = (pg_temp.rg_get('claim_claimed') ->> 'attempt_row_id')::uuid;
insert into _zc_r select 'ao_counts_before', pg_temp.rg_counts();
set local role authenticated;
insert into _zc_r select 'ao_own', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-own'), pg_temp.zc_id('order-claimed'), 'cash', 2000)));
insert into _zc_r select 'ao_d1_foreign', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-d1-foreign'), pg_temp.zc_id('order-foreign1'), 'cash', 2000)));
insert into _zc_r select 'ao_d1_missing', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-d1-missing'), pg_temp.zc_id('order-nonexistent'), 'cash', 2000)));
insert into _zc_r select 'ao_d4_claimed', pg_temp.zc_push(7, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-d4-claimed'), pg_temp.zc_id('order-claimed'), 'card', 1234)));
insert into _zc_r select 'ao_d4_unclaimed', pg_temp.zc_push(7, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-d4-unclaimed'), pg_temp.zc_id('order-snap_plain'), 'card', 1400)));
insert into _zc_r select 'ao_d4_missing', pg_temp.zc_push(7, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-d4-missing'), pg_temp.zc_id('order-nonexistent'), 'card', 1234)));
insert into _zc_r select 'ao_d5_claimed', pg_temp.zc_push(10, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-d5-claimed'), pg_temp.zc_id('order-claimed'), 'cash', 2000)));
insert into _zc_r select 'ao_d5_unclaimed', pg_temp.zc_push(10, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ao-d5-unclaimed'), pg_temp.zc_id('order-snap_plain'), 'cash', 2000)));
insert into _zc_r select 'ao_d4_void_claimed', pg_temp.zc_push(7, jsonb_build_array(
  pg_temp.rg_void_op(pg_temp.zc_lop('ao-d4-void-claimed'), pg_temp.zc_id('order-claimed'))));
insert into _zc_r select 'ao_d4_void_missing', pg_temp.zc_push(7, jsonb_build_array(
  pg_temp.rg_void_op(pg_temp.zc_lop('ao-d4-void-missing'), pg_temp.zc_id('order-nonexistent'))));
reset role;
insert into _zc_r select 'ao_counts_after', pg_temp.rg_counts();
select is(pg_temp.rg_res('ao_own') ->> 'error', 'payment_in_progress',
  'RG-60 anti-oracle contrast: in the claim''s own scope (d1) the guard answers payment_in_progress');
select is(pg_temp.rg_res('ao_d1_foreign') - 'local_operation_id', pg_temp.rg_generic('payment.create'),
  'RG-61 anti-oracle: payment.create from d1 naming the FOREIGN organization''s order (order of d4) is the generic rejection (rejected / 42501, detail null), never payment_in_progress');
select is(pg_temp.rg_res('ao_d1_foreign') - 'local_operation_id', pg_temp.rg_res('ao_d1_missing') - 'local_operation_id',
  'RG-62 anti-oracle: the answer for the foreign order equals the answer for a nonexistent order (d1)');
select is((select jsonb_build_object('status', so.status, 'rejection_reason', so.rejection_reason)
             from public.sync_operations so
            where so.device_id = pg_temp.zc_id('device-1') and so.local_operation_id = pg_temp.zc_lop('ao-d1-foreign')),
  '{"status": "rejected", "rejection_reason": "record_payment: order is not in the caller scope"}'::jsonb,
  'RG-63 anti-oracle: the guard deferred - record_payment''s own scope refusal answered the foreign order');
select is(pg_temp.rg_res('ao_d4_claimed') - 'local_operation_id', pg_temp.rg_generic('payment.create'),
  'RG-64 anti-oracle: payment.create from the foreign device d4 naming the CLAIMED pilot order is the generic rejection, never payment_in_progress');
select is(pg_temp.rg_res('ao_d4_claimed') - 'local_operation_id', pg_temp.rg_res('ao_d4_missing') - 'local_operation_id',
  'RG-65 anti-oracle: d4''s answer for the claimed pilot order equals its answer for a nonexistent order');
select is((select jsonb_agg(jsonb_build_object('org', so.organization_id, 'status', so.status,
                    'rejection_reason', so.rejection_reason, 'result', so.result) order by so.local_operation_id = pg_temp.zc_lop('ao-d4-claimed'))
             from public.sync_operations so
            where so.device_id = pg_temp.zc_id('device-4')
              and so.local_operation_id in (pg_temp.zc_lop('ao-d4-claimed'), pg_temp.zc_lop('ao-d4-unclaimed'))),
  jsonb_build_array(
    jsonb_build_object('org', pg_temp.zc_id('org_b'), 'status', 'rejected',
      'rejection_reason', 'record_payment: order is not in the caller scope',
      'result', '{"ok": false, "error": "rejected", "detail": null, "sqlstate": "42501"}'::jsonb),
    jsonb_build_object('org', pg_temp.zc_id('org_b'), 'status', 'rejected',
      'rejection_reason', 'record_payment: order is not in the caller scope',
      'result', '{"ok": false, "error": "rejected", "detail": null, "sqlstate": "42501"}'::jsonb)),
  'RG-66 anti-oracle: d4''s ledger rows for the claimed and for an unclaimed pilot order are identical (record_payment''s own refusal) - the claim is not observable from another organization');
select is(jsonb_build_array(pg_temp.rg_res('ao_d5_claimed') - 'local_operation_id',
                            pg_temp.rg_res('ao_d5_unclaimed') - 'local_operation_id'),
  jsonb_build_array(pg_temp.rg_generic('payment.create'), pg_temp.rg_generic('payment.create')),
  'RG-67 anti-oracle: a sibling-branch device (d5) naming the claimed order gets the same generic rejection as for an unclaimed order of that branch, never payment_in_progress');
select is(jsonb_build_array(pg_temp.rg_res('ao_d4_void_claimed') - 'local_operation_id',
                            pg_temp.rg_res('ao_d4_void_missing') - 'local_operation_id'),
  jsonb_build_array(pg_temp.rg_generic('order.void'), pg_temp.rg_generic('order.void')),
  'RG-68 anti-oracle: order.void from d4 naming the claimed pilot order equals the nonexistent-order answer (void_order''s own refusal, never payment_in_progress)');
select is(pg_temp.rg_get('ao_counts_after') - 'audit' - 'payments', pg_temp.rg_get('ao_counts_before') - 'audit' - 'payments',
  'RG-69 anti-oracle: the pushes wrote no attempt, no private event and no card_attempt.* audit row');
select is((pg_temp.rg_get('ao_counts_after') ->> 'payments')::bigint, (pg_temp.rg_get('ao_counts_before') ->> 'payments')::bigint,
  'RG-70 anti-oracle: no payment was recorded by any of the refused pushes');
select is((select to_jsonb(a) from app.card_provider_attempts a
            where a.id = (pg_temp.rg_get('claim_claimed') ->> 'attempt_row_id')::uuid),
  pg_temp.rg_get('ao_attempt_before'),
  'RG-71 anti-oracle: the claimed attempt row is byte-identical after the foreign / sibling pushes');

-- ===========================================================================
-- 8. Money-free arms are unaffected and the kitchen / KDS pull exposes no
--    card table.
-- ===========================================================================
set local role authenticated;
insert into _zc_r select 'kds_status', pg_temp.zc_push(6, jsonb_build_array(
  pg_temp.rg_status_op(pg_temp.zc_lop('kds-accept'), pg_temp.zc_id('order-claimed'), 'accepted')));
insert into _zc_r select 'kitchen_status', pg_temp.zc_push(4, jsonb_build_array(
  pg_temp.rg_status_op(pg_temp.zc_lop('kitchen-prepare'), pg_temp.zc_id('order-claimed'), 'preparing')));
reset role;
select is(pg_temp.rg_res('kds_status') - 'server_ts',
  jsonb_build_object('ok', true, 'entity', 'order', 'status', 'applied', 'order_id', pg_temp.zc_id('order-claimed'),
    'revision', 2, 'order_code', '#' || upper(right(replace(pg_temp.zc_id('order-claimed')::text, '-', ''), 6)),
    'auto_completed', false, 'operation_type', 'order.status', 'idempotency_replay', false,
    'local_operation_id', pg_temp.zc_lop('kds-accept')),
  'RG-72 money-free arm: order.status from the KDS device (submitted -> accepted) on a CLAIMED order is applied with the existing answer');
select is(pg_temp.rg_res('kitchen_status') ->> 'status', 'applied',
  'RG-73 money-free arm: a kitchen_staff order.status (accepted -> preparing) on the claimed order is applied');
select is((select jsonb_build_object('status', o.status, 'revision', o.revision) from public.orders o
            where o.id = pg_temp.zc_id('order-claimed')),
  '{"status": "preparing", "revision": 3}'::jsonb,
  'RG-74 money-free arm: the claimed order moved through the kitchen states');
select is(jsonb_build_array(app.card_order_claim_active(pg_temp.zc_org(), pg_temp.zc_id('order-claimed')),
                            (select to_jsonb(a) = pg_temp.rg_get('ao_attempt_before') from app.card_provider_attempts a
                              where a.id = (pg_temp.rg_get('claim_claimed') ->> 'attempt_row_id')::uuid)),
  '[true, true]'::jsonb,
  'RG-75 money-free arm: the status moves neither touch the attempt row nor end the claim');

set local role authenticated;
insert into _zc_r select 'pull_kds', public.sync_pull(pg_temp.zc_id('pin-6'), pg_temp.zc_id('device-3'));
insert into _zc_r select 'pull_kitchen', public.sync_pull(pg_temp.zc_id('pin-4'), pg_temp.zc_id('device-1'));
insert into _zc_r select 'pull_card_entity', pg_temp.rg_try(format(
  'select public.sync_pull(%L::uuid, %L::uuid, array[%L, %L])', pg_temp.zc_id('pin-6'), pg_temp.zc_id('device-3'),
  'orders', 'card_provider_attempts'));
insert into _zc_r select 'pull_terminal_entity', pg_temp.rg_try(format(
  'select public.sync_pull(%L::uuid, %L::uuid, array[%L])', pg_temp.zc_id('pin-4'), pg_temp.zc_id('device-1'),
  'payment_terminals'));
reset role;
select is(pg_temp.rg_keys(pg_temp.rg_get('pull_kds') -> 'changes'),
  pg_temp.rg_sorted(array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'order_edits',
    'payments', 'shifts', 'cash_drawer_sessions', 'menu_categories', 'menu_items', 'item_sizes', 'item_variants',
    'modifiers', 'modifier_options', 'tables']),
  'RG-76 KDS sync_pull (cashier session on the KDS device): exactly the existing 15 entities - no card table is a sync entity');
select is(pg_temp.rg_keys(pg_temp.rg_get('pull_kitchen') -> 'changes'),
  pg_temp.rg_sorted(array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'order_edits', 'tables']),
  'RG-77 kitchen sync_pull (kitchen_staff session): exactly the existing six kitchen entities');
select ok(exists (select 1 from jsonb_array_elements(pg_temp.rg_get('pull_kds') -> 'changes' -> 'orders' -> 'rows') r
                   where r ->> 'id' = pg_temp.zc_id('order-claimed')::text)
          and exists (select 1 from jsonb_array_elements(pg_temp.rg_get('pull_kitchen') -> 'changes' -> 'orders' -> 'rows') r
                       where r ->> 'id' = pg_temp.zc_id('order-claimed')::text),
  'RG-78 kitchen / KDS sync_pull: the claimed order is pulled as a plain order');
select is((select count(*) from unnest(pg_temp.rg_all_keys(pg_temp.rg_get('pull_kds'))
                                       || pg_temp.rg_all_keys(pg_temp.rg_get('pull_kitchen'))) k
            where k ~ '^(card|provider_)' or k in ('terminal_ref', 'credential_ref', 'attempt_id', 'attempt_state',
                                                   'charge_may_exist', 'start_deadline_at')),
  0::bigint,
  'RG-79 kitchen / KDS sync_pull: no key at any depth exposes a card ledger, binding or attempt field');
select is((select count(*) from unnest(pg_temp.rg_all_strings(pg_temp.rg_get('pull_kds'))
                                       || pg_temp.rg_all_strings(pg_temp.rg_get('pull_kitchen'))) s
            where s in ('zc-term-live-1', 'zc-cred-live-1', 'zc-term-test-1', 'zc-cred-test-1',
                        pg_temp.rg_get('claim_claimed') ->> 'provider_query_key',
                        pg_temp.rg_get('claim_claimed') ->> 'provider_duplicate_key')),
  0::bigint,
  'RG-80 kitchen / KDS sync_pull: no terminal / credential reference or provider key value appears');
select is(jsonb_build_array(pg_temp.rg_get('pull_card_entity'), pg_temp.rg_get('pull_terminal_entity')),
  '[{"raised": true, "sqlstate": "42501"}, {"raised": true, "sqlstate": "42501"}]'::jsonb,
  'RG-81 sync_pull refuses an explicit card_provider_attempts / payment_terminals entity (42501 unknown entity) - neither is pullable');
select throws_ok($$ select app.sync_pull_changes('card_provider_attempts', pg_temp.zc_org(), pg_temp.zc_branch(),
                                                 null, null, 10) $$,
  '42501', null,
  'RG-82 app.sync_pull_changes refuses card_provider_attempts (not a pull-allowed entity)');

-- ===========================================================================
-- 6. Non-UUID text identities pass through payment.create / order.status
--    untouched (no cast error, normal outcomes) while d1 holds a LIVE binding.
-- ===========================================================================
do $$ begin
  perform pg_temp.zc_order('legacy1', 1111);
  perform pg_temp.zc_order('legacy2', 2222);
end $$;
insert into _zc_r select 'legacy_before', pg_temp.rg_counts();
set local role authenticated;
insert into _zc_r select 'legacy_pay', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op('legacy-op-1', pg_temp.zc_id('order-legacy1'), 'cash', 1200)));
insert into _zc_r select 'legacy_pay_replay', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op('legacy-op-1', pg_temp.zc_id('order-legacy1'), 'cash', 1200)));
insert into _zc_r select 'legacy_status', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.rg_status_op('X', pg_temp.zc_id('order-legacy1'), 'accepted')));
insert into _zc_r select 'legacy_batch', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.rg_status_op('Y', pg_temp.zc_id('order-legacy2'), 'accepted'),
  pg_temp.zc_pay_op('legacy-op-2', pg_temp.zc_id('order-legacy2'), 'cash', 2222)));
insert into _zc_r select 'legacy_claimed', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op('legacy-op-3', pg_temp.zc_id('order-claimed'), 'cash', 2000)));
reset role;
select is(pg_temp.rg_res('legacy_pay') - 'payment_id' - 'receipt_number' - 'server_ts',
  pg_temp.rg_paid('legacy1', 'legacy-op-1', 'cash', 89),
  'RG-83 non-UUID identity ''legacy-op-1'': payment.create (cash) on d1 with an enabled LIVE binding is applied normally - no cast error in the admission locks, the single-operation check, the TEST lookup or the guard');
select is(pg_temp.rg_payment('legacy1') ->> 'local_operation_id', 'legacy-op-1',
  'RG-84 non-UUID identity: the payments row carries the text identity verbatim');
select is(pg_temp.rg_res('legacy_pay_replay') - 'server_ts',
  (pg_temp.rg_res('legacy_pay') - 'server_ts') || '{"idempotency_replay": true}'::jsonb,
  'RG-85 non-UUID identity: the resend replays the memoized result (idempotency_replay true, same payment)');
select is(pg_temp.rg_res('legacy_status') - 'server_ts',
  jsonb_build_object('ok', true, 'entity', 'order', 'status', 'applied', 'order_id', pg_temp.zc_id('order-legacy1'),
    'revision', 3, 'order_code', '#' || upper(right(replace(pg_temp.zc_id('order-legacy1')::text, '-', ''), 6)),
    'auto_completed', false, 'operation_type', 'order.status', 'idempotency_replay', false,
    'local_operation_id', 'X'),
  'RG-86 non-UUID identity ''X'': order.status is applied normally');
select is((select jsonb_agg(jsonb_build_object('local_operation_id', t.e ->> 'local_operation_id',
                                               'operation_type', t.e ->> 'operation_type',
                                               'ok', t.e -> 'ok', 'status', t.e ->> 'status') order by t.n)
             from jsonb_array_elements(pg_temp.rg_get('legacy_batch') -> 'results') with ordinality t(e, n)),
  '[{"local_operation_id": "Y", "operation_type": "order.status", "ok": true, "status": "applied"},
    {"local_operation_id": "legacy-op-2", "operation_type": "payment.create", "ok": true, "status": "applied"}]'::jsonb,
  'RG-87 non-UUID identities in one batch (order.status ''Y'' + payment.create ''legacy-op-2''): both applied in order - no single_operation_required for non-provider identities');
select is(pg_temp.rg_res('legacy_claimed') - 'server_ts',
  jsonb_build_object('ok', false, 'error', 'payment_in_progress', 'detail', 'card_attempt_active',
    'order_id', pg_temp.zc_id('order-claimed'), 'status', 'rejected', 'operation_type', 'payment.create',
    'idempotency_replay', false, 'local_operation_id', 'legacy-op-3'),
  'RG-88 non-UUID identity ''legacy-op-3'' naming the claimed order passes the guard''s text identity lookup without a cast error and meets the ordinary claim exclusion (payment_in_progress)');
select is(jsonb_build_object('rows', (select count(*) from public.sync_operations so
                                        where so.device_id = pg_temp.zc_id('device-1')
                                          and so.local_operation_id in ('legacy-op-1', 'legacy-op-2', 'X', 'Y')
                                          and so.status = 'applied'),
                             'card', pg_temp.rg_counts() - 'audit' - 'payments'),
  jsonb_build_object('rows', 4, 'card', pg_temp.rg_get('legacy_before') - 'audit' - 'payments'),
  'RG-89 non-UUID identities: four applied ledger rows under the text identities and no attempt, private event or card_attempt.* audit row created');

-- ===========================================================================
-- 11. Printer-only branch: a full LIVE flow (claim, approve, leg) records once
--     and the order follows the existing auto-completion rule.
-- ===========================================================================
update public.branches set kitchen_workflow_mode = 'printer_only'
 where id = pg_temp.zc_branch() and organization_id = pg_temp.zc_org();
select is((select b.kitchen_workflow_mode from public.branches b where b.id = pg_temp.zc_branch()), 'printer_only',
  'RG-90 setup: the pilot branch is switched to printer_only (privileged SQL, rolled back with the file)');
do $$ begin perform pg_temp.zc_order('po1', 4321); end $$;
set local role service_role;
insert into _zc_r select 'po_claim', pg_temp.zc_claim(1, pg_temp.zc_lop('po1'), 'live', 4321,
  pg_temp.zc_id('order-po1'), 1);
insert into _zc_r select 'po_finish', pg_temp.zc_finish(pg_temp.rg_get('po_claim'), 'commit', 'approved',
  pg_temp.zc_approved_fields() || jsonb_build_object('card_last4', '4242', 'provider_reference', 'REF123',
                                                     'approval_number', 'A1B2', 'voucher_number', 'V99'));
reset role;
select is(jsonb_build_array(pg_temp.rg_get('po_claim') ->> 'claim_created', pg_temp.rg_get('po_finish') ->> 'state',
                            pg_temp.rg_get('po_finish') ->> 'classification'),
  '["true", "approved", "approved_unrecorded"]'::jsonb,
  'RG-91 printer-only: LIVE claim and provider approval of po1 (approved, approved_unrecorded)');
set local role authenticated;
insert into _zc_r select 'po_snap_approved', public.pos_order_snapshots(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'));
insert into _zc_r select 'po_leg', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('po1'), pg_temp.zc_id('order-po1'), 'card', 4321)));
insert into _zc_r select 'po_leg_replay', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('po1'), pg_temp.zc_id('order-po1'), 'card', 4321)));
insert into _zc_r select 'po_snap_recorded', public.pos_order_snapshots(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'));
reset role;
select is(pg_temp.rg_row('po_snap_approved', 'po1') -> 'card_attempt_in_progress', 'true'::jsonb,
  'RG-92 snapshot: an approved LIVE attempt without its strict-join payment still carries card_attempt_in_progress = true');
select is(pg_temp.rg_res('po_leg') - 'payment_id' - 'receipt_number' - 'server_ts',
  pg_temp.rg_paid('po1', pg_temp.zc_lop('po1'), 'card', 0, 'completed', true, 3),
  'RG-93 printer-only: the recording leg is applied as a card payment and the order auto-completes on settlement (auto_completed true, order_status completed, order_revision 3)');
select is((select count(*) from public.payments p where p.order_id = pg_temp.zc_id('order-po1')), 1::bigint,
  'RG-94 printer-only: exactly one payments row for the order after the leg and its resend');
select is(pg_temp.rg_payment('po1'),
  pg_temp.rg_payment_expect('card', 4321, 4321, 0, pg_temp.zc_lop('po1'), pg_temp.rg_res('po_leg')),
  'RG-95 printer-only: the payment is the attempt''s strict-join row (card, 4321 ILS, the attempt identity, the frozen shift and drawer of d1)');
select is((select jsonb_build_object('status', o.status, 'revision', o.revision) from public.orders o
            where o.id = pg_temp.zc_id('order-po1')),
  '{"status": "completed", "revision": 3}'::jsonb,
  'RG-96 printer-only: the order is completed');
select is((select jsonb_agg(a.new_values - 'order_id' - 'order_code' - 'resolved_membership_id' - 'local_operation_id')
             from public.audit_events a
            where a.action = 'order.status_updated' and a.new_values ->> 'order_id' = pg_temp.zc_id('order-po1')::text),
  '[{"role": "cashier", "status": "completed", "revision": 3, "payment_status": "paid", "completion_mode": "automatic", "completion_trigger": "payment_recorded", "kitchen_workflow_mode": "printer_only"}]'::jsonb,
  'RG-97 printer-only: exactly one automatic completion audit (completion_trigger payment_recorded, kitchen_workflow_mode printer_only) - the existing auto-completion rule');
select is((select jsonb_build_object('classification', x.d ->> 'classification', 'payment_id', x.d ->> 'payment_id',
                                     'claim_active', (x.d ->> 'claim_active')::boolean)
             from app.card_provider_attempts a cross join lateral (select app.card_attempt_derive(a) as d) x
            where a.id = (pg_temp.rg_get('po_claim') ->> 'attempt_row_id')::uuid),
  jsonb_build_object('classification', 'recorded', 'payment_id', pg_temp.rg_res('po_leg') ->> 'payment_id',
                     'claim_active', false),
  'RG-98 printer-only: the attempt is recorded through the strict join and its claim has ended');
select is(pg_temp.rg_res('po_leg_replay') - 'server_ts',
  (pg_temp.rg_res('po_leg') - 'server_ts') || '{"idempotency_replay": true}'::jsonb,
  'RG-99 printer-only: a resend of the leg replays the memoized result (recorded once)');
select is((select count(*) from public.audit_events a
            where a.action = 'payment.recorded' and a.new_values ->> 'order_id' = pg_temp.zc_id('order-po1')::text),
  1::bigint,
  'RG-100 printer-only: one payment.recorded audit row for the order');
select is(pg_temp.rg_keys(pg_temp.rg_row('po_snap_recorded', 'po1')), pg_temp.rg_snap_keys(),
  'RG-101 snapshot: once the approval is recorded the row is back to exactly the 18 pre-001D keys');

-- ===========================================================================
-- 10. card_attempt_context returns no reference / key strings; app.sync_push
--     keeps one definition and all 18 arms; the public wrapper is unchanged.
-- ===========================================================================
set local role authenticated;
insert into _zc_r select 'ctx_po', public.card_attempt_context(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_id('order-po1'), pg_temp.zc_lop('po1'));
insert into _zc_r select 'ctx_claimed', public.card_attempt_context(pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_id('order-claimed'), pg_temp.zc_lop('claimed'));
reset role;
select is((select jsonb_build_object('card_last4', a.card_last4, 'provider_reference', a.provider_reference,
                                     'approval_number', a.approval_number, 'voucher_number', a.voucher_number)
             from app.card_provider_attempts a where a.id = (pg_temp.rg_get('po_claim') ->> 'attempt_row_id')::uuid),
  '{"card_last4": "4242", "provider_reference": "REF123", "approval_number": "A1B2", "voucher_number": "V99"}'::jsonb,
  'RG-102 context precondition: the ledger row of po1 stores card and provider-reference values the context must never return');
select is(jsonb_build_array(pg_temp.rg_get('ctx_off') -> 'terminal', pg_temp.rg_get('ctx_off') -> 'card_terminal_enabled',
                            pg_temp.rg_get('ctx_off') -> 'attempt'),
  '[null, false, null]'::jsonb,
  'RG-103 card_attempt_context with no binding (default OFF): terminal null, card_terminal_enabled false, no attempt');
select is(jsonb_build_array(pg_temp.rg_keys(pg_temp.rg_get('ctx_po')), pg_temp.rg_keys(pg_temp.rg_get('ctx_claimed'))),
  jsonb_build_array(pg_temp.rg_sorted(array['ok', 'caller_auth_user_id', 'organization_id', 'restaurant_id', 'branch_id',
                      'device_id', 'role', 'employee_profile_id', 'membership_id', 'order', 'attempt', 'terminal',
                      'card_terminal_enabled', 'server_ts']),
                    pg_temp.rg_sorted(array['ok', 'caller_auth_user_id', 'organization_id', 'restaurant_id', 'branch_id',
                      'device_id', 'role', 'employee_profile_id', 'membership_id', 'order', 'attempt', 'terminal',
                      'card_terminal_enabled', 'server_ts'])),
  'RG-104 card_attempt_context: exactly the documented top-level keys (a recorded approval; a sent attempt read by a manager; C2: the original-caller binding caller_auth_user_id)');
select is((select count(*) from unnest(pg_temp.rg_all_keys(pg_temp.rg_get('ctx_po'))
                                       || pg_temp.rg_all_keys(pg_temp.rg_get('ctx_claimed'))
                                       || pg_temp.rg_all_keys(pg_temp.rg_get('ctx_off'))) k
            where k in ('terminal_ref', 'credential_ref', 'provider_query_key', 'provider_duplicate_key',
                        'provider_key_format_version', 'provider_reference', 'approval_number', 'voucher_number',
                        'deposit_id', 'card_last4', 'card_brand_code', 'attempt_row_id')),
  0::bigint,
  'RG-105 card_attempt_context: no terminal / credential reference, provider key, formatter version, provider reference, approval / voucher number or card-data key at any depth');
select is((select count(*) from unnest(pg_temp.rg_all_strings(pg_temp.rg_get('ctx_po'))
                                       || pg_temp.rg_all_strings(pg_temp.rg_get('ctx_claimed'))
                                       || pg_temp.rg_all_strings(pg_temp.rg_get('ctx_off'))) s
            where s in ('zc-term-live-1', 'zc-cred-live-1', 'zc-term-test-1', 'zc-cred-test-1', 'alpha16-l32-v1',
                        '4242', 'REF123', 'A1B2', 'V99',
                        pg_temp.rg_get('po_claim') ->> 'provider_query_key',
                        pg_temp.rg_get('po_claim') ->> 'provider_duplicate_key',
                        pg_temp.rg_get('claim_claimed') ->> 'provider_query_key',
                        pg_temp.rg_get('claim_claimed') ->> 'provider_duplicate_key')),
  0::bigint,
  'RG-106 card_attempt_context: none of the stored reference, key, formatter or card values appears as a string value');
select ok(pg_temp.rg_keys(pg_temp.rg_get('ctx_po') -> 'attempt')
            <@ array['attempt_id', 'state', 'classification', 'provider_return_code', 'refusal_code', 'anomaly_code',
                     'resolution', 'recorded', 'recoverable', 'resume_count', 'payment_id', 'amount_minor',
                     'currency_code', 'mode', 'own_device']
          and pg_temp.rg_keys(pg_temp.rg_get('ctx_claimed') -> 'attempt')
            <@ array['attempt_id', 'state', 'classification', 'provider_return_code', 'refusal_code', 'anomaly_code',
                     'resolution', 'recorded', 'recoverable', 'resume_count', 'payment_id', 'amount_minor',
                     'currency_code', 'mode', 'own_device'],
  'RG-107 card_attempt_context: the attempt projection stays within the client-safe envelope keys (+ mode, own_device)');
select is((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'app' and p.proname = 'sync_push'), 1::bigint,
  'RG-108 app.sync_push still has exactly one definition (no overload added)');
select is(pg_get_function_identity_arguments('app.sync_push(uuid,uuid,jsonb)'::regprocedure),
  'p_pin_session_id uuid, p_device_id uuid, p_operations jsonb',
  'RG-109 app.sync_push keeps its exact signature');
select is((select coalesce(array_agg(o.op order by o.op), '{}'::text[])
             from unnest(array['shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close',
                               'order.status', 'order.void', 'order.table_move', 'menu.availability_set',
                               'table.status_set', 'table.link', 'table.unlink', 'cash_drawer.no_sale_open',
                               'order.void_ack', 'order.items_add', 'order.round_status', 'order.edit',
                               'order.edit_ack']) o(op)
             cross join pg_proc p
            where p.oid = 'app.sync_push(uuid,uuid,jsonb)'::regprocedure
              and (length(p.prosrc) - length(replace(p.prosrc, 'when ''' || o.op || ''' then', '')))
                  / length('when ''' || o.op || ''' then') <> 1),
  '{}'::text[],
  'RG-110 app.sync_push still carries exactly one ''when ''<op>'' then'' dispatch arm for each of the 18 operations');
select is((select (length(p.prosrc) - length(replace(p.prosrc, x.needle, ''))) / length(x.needle)
             from pg_proc p
             cross join (select $s$v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'cash_drawer.no_sale_open', 'order.edit', 'order.edit_ack')$s$ as needle) x
            where p.oid = 'app.sync_push(uuid,uuid,jsonb)'::regprocedure),
  2,
  'RG-111 app.sync_push: both operation allowlists (revoked-device and valid path) still name exactly the 18 operations - no operation type added');
select is(md5(replace(pg_get_functiondef('public.sync_push(uuid,uuid,jsonb)'::regprocedure), E'\r', '')),
  '68fcb0b3006e998b447861db6126f2c4',
  'RG-112 public.sync_push is unchanged (CR-normalized definition hash equals the pre-001D baseline)');
select is(btrim(regexp_replace((select p.prosrc from pg_proc p where p.oid = 'public.sync_push(uuid,uuid,jsonb)'::regprocedure),
                               '\s+', ' ', 'g')),
  'select app.sync_push( p_pin_session_id, p_device_id, p_operations );',
  'RG-113 public.sync_push still delegates verbatim to app.sync_push');
select is((select jsonb_build_object('anon', has_function_privilege('anon', p.oid, 'execute'),
                                     'authenticated', has_function_privilege('authenticated', p.oid, 'execute'),
                                     'service_role', has_function_privilege('service_role', p.oid, 'execute'),
                                     'security_definer', p.prosecdef)
             from pg_proc p where p.oid = 'public.sync_push(uuid,uuid,jsonb)'::regprocedure),
  '{"anon": false, "authenticated": true, "service_role": false, "security_definer": false}'::jsonb,
  'RG-114 public.sync_push keeps its SECURITY INVOKER posture and grants (authenticated only)');
select is(jsonb_build_array(
    md5(replace(pg_get_functiondef('public.pin_session_capabilities(uuid,uuid)'::regprocedure), E'\r', '')),
    md5(replace(pg_get_functiondef('public.pos_order_snapshots(uuid,uuid,timestamptz,uuid,timestamptz,uuid,uuid[],integer,integer)'::regprocedure), E'\r', ''))),
  '["1fc46e8042a948a8ef804729f1b9ab36", "86c9ecf75aa474be5522074365c01ba1"]'::jsonb,
  'RG-115 the public.pin_session_capabilities and public.pos_order_snapshots wrappers are unchanged (pre-001D baseline hashes)');

-- ===========================================================================
-- 5. The refusal-path probe: a non-provider payment.create on d1 after its
--    shift was closed is rejected exactly as before; shift.open is unaffected.
-- ===========================================================================
update public.shifts set status = 'closed', closed_at = now(), closed_by_employee_profile_id = pg_temp.zc_id('employee-1')
 where id = pg_temp.zc_id('shift-1');
update public.cash_drawer_sessions set status = 'closed', closed_at = now()
 where id = pg_temp.zc_id('drawer-' || pg_temp.zc_id('device-1'));
do $$ begin perform pg_temp.zc_order('probe', 999); end $$;
insert into _zc_r select 'probe_before', pg_temp.rg_counts();
set local role authenticated;
insert into _zc_r select 'probe', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('probe'), pg_temp.zc_id('order-probe'), 'cash', 1000)));
insert into _zc_r select 'probe_replay', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('probe'), pg_temp.zc_id('order-probe'), 'cash', 1000)));
reset role;
select is(pg_temp.rg_res('probe'),
  jsonb_build_object('local_operation_id', pg_temp.zc_lop('probe'), 'operation_type', 'payment.create', 'ok', false,
    'error', 'rejected', 'sqlstate', '42501', 'detail', 'precondition_failed', 'status', 'rejected',
    'idempotency_replay', false),
  'RG-116 refusal probe: a non-provider payment.create on d1 after its shift closed is rejected exactly as before (rejected / 42501 / detail precondition_failed - permanent, never transient_failure)');
select is((select jsonb_build_object('status', so.status, 'rejection_reason', so.rejection_reason,
                                     'last_error_code', so.last_error_code, 'last_error_class', so.last_error_class,
                                     'result', so.result)
             from public.sync_operations so
            where so.device_id = pg_temp.zc_id('device-1') and so.local_operation_id = pg_temp.zc_lop('probe')),
  '{"status": "rejected", "rejection_reason": "precondition_failed", "last_error_code": "42501", "last_error_class": "permanent", "result": {"ok": false, "error": "rejected", "sqlstate": "42501", "detail": "precondition_failed"}}'::jsonb,
  'RG-117 refusal probe: the ledger row is the existing permanent precondition_failed rejection');
select is((select jsonb_agg(jsonb_build_object('reason', a.reason, 'new_values', a.new_values))
             from public.audit_events a
            where a.organization_id = pg_temp.zc_org() and a.action = 'sync.operation_rejected'
              and a.new_values ->> 'local_operation_id' = pg_temp.zc_lop('probe')),
  jsonb_build_array(jsonb_build_object('reason', 'precondition_failed', 'new_values',
    jsonb_build_object('local_operation_id', pg_temp.zc_lop('probe'), 'operation_type', 'payment.create',
                       'sqlstate', '42501'))),
  'RG-118 refusal probe: one sync.operation_rejected audit row with reason precondition_failed');
select is((select jsonb_build_object('payments', (select count(*) from public.payments p where p.order_id = o.id),
                                     'revision', o.revision, 'receipt_number', o.receipt_number)
             from public.orders o where o.id = pg_temp.zc_id('order-probe')),
  '{"payments": 0, "revision": 1, "receipt_number": null}'::jsonb,
  'RG-119 refusal probe: no payment, no receipt number and no order revision bump');
select is(pg_temp.rg_counts() - 'audit' - 'payments', pg_temp.rg_get('probe_before') - 'audit' - 'payments',
  'RG-120 refusal probe: no attempt, private event or card_attempt.* audit row');
select is(pg_temp.rg_res('probe_replay'), pg_temp.rg_res('probe') || '{"idempotency_replay": true}'::jsonb,
  'RG-121 refusal probe: the resend replays the stored refusal (idempotency_replay true)');

set local role authenticated;
insert into _zc_r select 'shift_open', pg_temp.zc_push(1, jsonb_build_array(jsonb_build_object(
  'local_operation_id', 'legacy-shift-open-1', 'operation_type', 'shift.open', 'target_entity', 'shift',
  'target_id', pg_temp.zc_id('shift-reopen'), 'client_created_at', '2026-10-24T00:00:00Z',
  'payload', jsonb_build_object('shift_id', pg_temp.zc_id('shift-reopen'),
                                'cash_drawer_session_id', pg_temp.zc_id('drawer-reopen'), 'opening_float_minor', 500))));
reset role;
select is(pg_temp.rg_res('shift_open') - 'server_ts',
  jsonb_build_object('ok', true, 'status', 'applied', 'revision', 1, 'shift_id', pg_temp.zc_id('shift-reopen'),
    'drawer_status', 'active', 'operation_type', 'shift.open', 'idempotency_replay', false,
    'local_operation_id', 'legacy-shift-open-1', 'opening_float_minor', 500,
    'cash_drawer_session_id', pg_temp.zc_id('drawer-reopen')),
  'RG-122 money-free arm: shift.open on d1 is applied with the existing answer while d1 holds a LIVE binding and an active claim frozen to its closed shift');
select is((select jsonb_build_object('shift', s.status, 'device', s.device_id, 'drawer', c.status)
             from public.shifts s join public.cash_drawer_sessions c on c.shift_id = s.id
            where s.id = pg_temp.zc_id('shift-reopen')),
  jsonb_build_object('shift', 'open', 'device', pg_temp.zc_id('device-1'), 'drawer', 'active'),
  'RG-123 money-free arm: the new open shift and active drawer of d1 exist');

-- ===========================================================================
-- 4b. End to end: owner_audit_events (org_owner) projects, classifies and
--     filters every non-card event exactly like the pre-001D bodies.
-- ===========================================================================
insert into auth.users (id, email) values (pg_temp.zc_id('auth-user-9'), 'zc001d-rg-owner@example.test');
update public.app_users set auth_user_id = pg_temp.zc_id('auth-user-9') where id = pg_temp.zc_id('user-9');
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.zc_id('auth-user-9')::text, true); end $$;
set local role authenticated;
insert into _zc_r select 'oae_all', public.owner_audit_events(pg_temp.zc_org(), null, null, 'today', null, null,
  false, null, null, 100, null);
insert into _zc_r select 'oae_sensitive', public.owner_audit_events(pg_temp.zc_org(), null, null, 'today', null, null,
  true, null, null, 100, null);
insert into _zc_r select 'oae_payments', public.owner_audit_events(pg_temp.zc_org(), null, null, 'today', 'payments',
  null, false, null, null, 100, null);
reset role;
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true); end $$;
select is(jsonb_build_array(pg_temp.rg_get('oae_all') ->> 'ok', pg_temp.rg_get('oae_all') -> 'has_more',
                            pg_temp.rg_get('oae_sensitive') -> 'has_more', pg_temp.rg_get('oae_payments') -> 'has_more'),
  '["true", false, false, false]'::jsonb,
  'RG-124 owner_audit_events (org_owner, today): the three listings are complete (no further page)');
select is((select count(*) from jsonb_array_elements(pg_temp.rg_get('oae_all') -> 'events') e
            where e ->> 'action' not like 'card_attempt.%'),
  (select count(*) from public.audit_events a
    where a.organization_id = pg_temp.zc_org() and a.action not like 'card_attempt.%'),
  'RG-125 owner_audit_events: every non-card audit row of the pilot organization is listed');
select is((select count(*) from jsonb_array_elements(pg_temp.rg_get('oae_all') -> 'events') e
             join public.audit_events a on a.id = (e ->> 'event_id')::uuid
            where a.action not like 'card_attempt.%'
              and (e ->> 'category' is distinct from pg_temp.rg_pre_category(a.action)
                   or e -> 'new_values' is distinct from pg_temp.rg_pre_safe_detail(a.action, a.new_values)
                   or e -> 'old_values' is distinct from pg_temp.rg_pre_safe_detail(a.action, a.old_values))),
  0::bigint,
  'RG-126 owner_audit_events: every non-card event keeps its pre-001D category and old / new safe-detail projection');
select is((select e -> 'new_values' from jsonb_array_elements(pg_temp.rg_get('oae_all') -> 'events') e
            where e ->> 'action' = 'payment.recorded'
              and e ->> 'event_id' = (select a.id::text from public.audit_events a
                                       where a.action = 'payment.recorded'
                                         and a.new_values ->> 'order_id' = pg_temp.zc_id('order-cash1')::text)),
  jsonb_build_object('status', 'completed', 'amount_minor', 1234, 'tendered_minor', 2000, 'change_minor', 766),
  'RG-127 owner_audit_events: the cash payment''s payment.recorded event shows exactly the existing money keys (no currency_code)');
select set_eq(
  $$ select (e ->> 'event_id')::uuid from _zc_r z cross join lateral jsonb_array_elements(z.r -> 'events') e
      where z.label = 'oae_sensitive' and e ->> 'action' not like 'card_attempt.%' $$,
  $$ select a.id from public.audit_events a
      where a.organization_id = pg_temp.zc_org() and a.action not like 'card_attempt.%'
        and pg_temp.rg_pre_sensitive(a.action) $$,
  'RG-128 owner_audit_events: the sensitive-only filter selects exactly the pre-001D sensitive set of non-card events');
select set_eq(
  $$ select (e ->> 'event_id')::uuid from _zc_r z cross join lateral jsonb_array_elements(z.r -> 'events') e
      where z.label = 'oae_payments' and e ->> 'action' not like 'card_attempt.%' $$,
  $$ select a.id from public.audit_events a
      where a.organization_id = pg_temp.zc_org() and a.action not like 'card_attempt.%'
        and pg_temp.rg_pre_category(a.action) = 'payments' $$,
  'RG-129 owner_audit_events: the payments category filter selects exactly the pre-001D payments-category non-card events');

-- ===========================================================================
-- 12. Correction C1-1 (D-059 point 1): the snapshot watermark. sync_at joins
--     max(claim_signal_at) of the order's LIVE attempts of the same
--     organization, branch and order. The ledger guards stamp the signal at
--     the claim and advance it only on a state change, a manager free or a
--     resolution, so the incremental feed (p_since_at / p_since_id)
--     re-delivers an order when its claim appears or ends - once - and never
--     for a poll, a lookup stamp, a release / recording mark or a hold.
--     The POS cursor lives in _rg_wm ('cursor' = the last (sync_at, order_id)
--     delivered): every feed reads ascending from it with p_limit 100, and the
--     cursor then moves to the last row delivered (an empty feed leaves it
--     where it is), so each step is judged on its own. The new column is read
--     through to_jsonb(row), so a database without it answers NULL instead of
--     aborting the file.
-- ===========================================================================
create temp table _rg_wm (k text primary key, at timestamptz, id uuid);
grant select on _rg_wm to authenticated;
insert into _rg_wm values ('cursor', '-infinity', '00000000-0000-0000-0000-000000000000');
-- The POS feed (call under SET LOCAL ROLE authenticated): ascending from cursor k, as pin-1 on d1.
create function pg_temp.rg_wm_feed(p_label text, p_k text default 'cursor') returns void language sql volatile as $$
  insert into _zc_r select p_label, public.pos_order_snapshots(
    p_pin_session_id => pg_temp.zc_id('pin-1'), p_device_id => pg_temp.zc_id('device-1'),
    p_since_at => (select w.at from _rg_wm w where w.k = p_k),
    p_since_id => (select w.id from _rg_wm w where w.k = p_k), p_limit => 100) $$;
-- A targeted read of the given orders (call under SET LOCAL ROLE authenticated), as pin-n on device d.
create function pg_temp.rg_wm_target(p_label text, p_order_labels text[], p_n integer default 1, p_d integer default 1)
returns void language sql volatile as $$
  insert into _zc_r select p_label, public.pos_order_snapshots(
    p_pin_session_id => pg_temp.zc_id('pin-' || p_n), p_device_id => pg_temp.zc_id('device-' || p_d),
    p_order_ids => (select array_agg(pg_temp.zc_id('order-' || l)) from unnest(p_order_labels) l)) $$;
-- Moves cursor k to the last row a captured feed delivered (no row: k stays where it is).
create function pg_temp.rg_wm_advance(p_label text, p_k text default 'cursor') returns void language sql volatile as $$
  update _rg_wm w set at = x.at, id = x.id
    from (select (t.o ->> 'sync_at')::timestamptz as at, (t.o ->> 'order_id')::uuid as id
            from _zc_r z cross join lateral jsonb_array_elements(z.r -> 'orders') with ordinality t(o, n)
           where z.label = p_label order by t.n desc limit 1) x
   where w.k = p_k $$;
-- The rows of a captured answer, in answer order: {order_id, card_attempt_in_progress} (null = key absent).
create function pg_temp.rg_wm_rows(p_label text) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('order_id', t.o ->> 'order_id',
                                               'card_attempt_in_progress', t.o -> 'card_attempt_in_progress')
                            order by t.n), '[]'::jsonb)
    from _zc_r z cross join lateral jsonb_array_elements(z.r -> 'orders') with ordinality t(o, n)
   where z.label = p_label $$;
create function pg_temp.rg_wm_row(p_order_label text, p_in_progress boolean default null) returns jsonb
language sql immutable as $$
  select jsonb_build_object('order_id', pg_temp.zc_id('order-' || p_order_label)::text,
                            'card_attempt_in_progress', to_jsonb(p_in_progress)) $$;
-- The page facts of a captured answer (an empty feed is {orders: [], has_more: false, next_cursor: null}).
create function pg_temp.rg_wm_page_facts(p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('orders', pg_temp.rg_wm_rows(p_label), 'has_more', z.r -> 'has_more',
                            'next_cursor', z.r -> 'next_cursor')
    from _zc_r z where z.label = p_label $$;
-- The sync_at a captured answer gave one order.
create function pg_temp.rg_wm_sync(p_label text, p_order_label text) returns timestamptz language sql stable as $$
  select (pg_temp.rg_row(p_label, p_order_label) ->> 'sync_at')::timestamptz $$;
-- The pilot-organization attempt of an order label / an attempt by id, as JSON (owner read).
create function pg_temp.rg_wm_attempt(p_order_label text) returns jsonb language sql stable as $$
  select to_jsonb(a) from app.card_provider_attempts a
   where a.organization_id = pg_temp.zc_org() and a.order_id = pg_temp.zc_id('order-' || p_order_label) $$;
create function pg_temp.rg_wm_attempt_id(p_id uuid) returns jsonb language sql stable as $$
  select to_jsonb(a) from app.card_provider_attempts a where a.id = p_id $$;
-- Signal snapshots: k -> the attempt's claim_signal_at / created_at / updated_at at that point.
create temp table _rg_wm_sig (k text primary key, attempt_id uuid not null, sig timestamptz, created timestamptz,
                              updated timestamptz);
create function pg_temp.rg_wm_save(p_k text, p_attempt_id uuid) returns void language sql volatile as $$
  insert into _rg_wm_sig
  select p_k, p_attempt_id, (s.j ->> 'claim_signal_at')::timestamptz, (s.j ->> 'created_at')::timestamptz,
         (s.j ->> 'updated_at')::timestamptz
    from (select pg_temp.rg_wm_attempt_id(p_attempt_id) as j) s $$;
create function pg_temp.rg_wm_sig(p_k text) returns timestamptz language sql stable as $$
  select s.sig from _rg_wm_sig s where s.k = p_k $$;
create function pg_temp.rg_wm_id(p_label text) returns uuid language sql stable as $$
  select (z.r ->> 'attempt_row_id')::uuid from _zc_r z where z.label = p_label $$;
-- An owner-inserted attempt row with valid digests and keys (no RPC can claim outside the pilot scope or in
-- another mode than the current revision's); a LIVE row freezes device d's fixture shift and drawer. A
-- non-NULL p_signal is written into claim_signal_at as a writer-supplied value.
create function pg_temp.rg_wm_insert(p_d integer, p_n integer, p_lop_label text, p_mode text, p_amount bigint,
                                     p_order_label text default null, p_signal timestamptz default null)
returns uuid language plpgsql volatile as $$
declare
  v_dev public.devices;
  v_lop text := pg_temp.zc_lop(p_lop_label);
  v_sd bytea;
  v_dd bytea;
  v_id uuid;
begin
  select * into v_dev from public.devices d where d.id = pg_temp.zc_id('device-' || p_d);
  v_sd := app.card_identity_digest('card-status-key/v1', v_dev.organization_id, v_dev.id, v_lop);
  v_dd := app.card_identity_digest('card-duplicate-key/v1', v_dev.organization_id, v_dev.id, v_lop);
  execute format(
    'insert into app.card_provider_attempts (organization_id, restaurant_id, branch_id, device_id, local_operation_id, '
    || 'order_id, shift_id, cash_drawer_session_id, initiated_by_employee_profile_id, initiated_by_membership_id, mode, '
    || 'amount_minor, currency_code, expected_revision, terminal_ref, credential_ref, provider_status_digest, '
    || 'provider_duplicate_digest, provider_key_format_version, provider_query_key, provider_duplicate_key, '
    || 'start_deadline_at%s) values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, ''ILS'', $13, $14, $15, $16, '
    || '$17, ''alpha16-l32-v1'', $18, $19, clock_timestamp() + interval ''120 seconds''%s) returning id',
    case when p_signal is null then '' else ', claim_signal_at' end,
    case when p_signal is null then '' else ', $20' end)
  into v_id
  using v_dev.organization_id, v_dev.restaurant_id, v_dev.branch_id, v_dev.id, v_lop,
        case when p_mode = 'live' then pg_temp.zc_id('order-' || p_order_label) end,
        case when p_mode = 'live' then pg_temp.zc_id('shift-' || p_d) end,
        case when p_mode = 'live' then pg_temp.zc_id('drawer-' || pg_temp.zc_id('device-' || p_d)) end,
        pg_temp.zc_id('employee-' || p_n), pg_temp.zc_id('membership-' || p_n), p_mode, p_amount,
        case when p_mode = 'live' then 1 end,
        'zc-term-' || p_mode || '-' || p_d, 'zc-cred-' || p_mode || '-' || p_d, v_sd, v_dd,
        app.card_provider_key(v_sd, 'alpha16-l32-v1'), app.card_provider_key(v_dd, 'alpha16-l32-v1'), p_signal;
  return v_id;
end $$;
-- An unpaid order of d1 written as if committed before this transaction (created_at = updated_at = p_at).
create function pg_temp.rg_wm_order_at(p_label text, p_total bigint, p_at timestamptz) returns uuid
language sql volatile as $$
  insert into public.orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
      opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor,
      discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, revision, created_at, updated_at)
  values (pg_temp.zc_id('order-' || p_label), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
      pg_temp.zc_id('device-1'), pg_temp.zc_id('pin-1'), pg_temp.zc_id('employee-1'), pg_temp.zc_id('membership-1'),
      'takeaway', 'submitted', 'ILS', p_total, 0, 0, p_total, 'zc001d-order-' || p_label, 1, p_at, p_at)
  returning id $$;
-- Test-only time travel (owner; rolled back with the file). A single transaction freezes now(): a payment's
-- updated_at (DEFAULT now()) can never pass a claim signal stamped by clock_timestamp() inside the same
-- transaction. The recording-leg case therefore writes its order and approved claim as if committed earlier:
-- the claim signal is moved to p_at with the guard trigger bypassed for this one UPDATE (as the fixture's
-- zc_age_attempt does for the deadline). FALSE where the column does not exist.
create function pg_temp.rg_wm_signal_back(p_attempt_id uuid, p_at timestamptz) returns boolean language plpgsql as $$
begin
  alter table app.card_provider_attempts disable trigger card_attempts_guard;
  execute 'update app.card_provider_attempts set claim_signal_at = $1 where id = $2' using p_at, p_attempt_id;
  alter table app.card_provider_attempts enable trigger card_attempts_guard;
  return true;
exception when undefined_column then
  return false;
end $$;
-- A declined commit reply (approval_type present), as RG-53.
create function pg_temp.rg_wm_declined() returns jsonb language sql immutable as $$
  select jsonb_build_object('error_flag', true, 'provider_return_code', 33, 'approval_type', 'declined',
                            'provider_return_class', 'declined') $$;

-- Section orders: seven of the pilot branch (one written as if committed 10 minutes before this
-- transaction), one of the foreign organization (d4) and two of the sibling branch (d5).
do $$ begin
  perform pg_temp.zc_order('wm_main', 2101);
  perform pg_temp.zc_order('wm_free', 2201);
  perform pg_temp.zc_order('wm_resolve', 2301);
  perform pg_temp.zc_order('wm_mark', 2501);
  perform pg_temp.zc_order('wm_plain', 2601);
  perform pg_temp.zc_order('wm_sib', 2701);
  perform pg_temp.zc_order('wm_foreign', 2801, 4);
  perform pg_temp.zc_order('wm_page_a', 2901, 5);
  perform pg_temp.zc_order('wm_page_b', 2902, 5);
  perform pg_temp.rg_wm_order_at('wm_record', 2401, now() - interval '10 minutes');
end $$;

-- Baseline: the POS reads the whole feed once; its cursor moves to the newest row.
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_base');
select pg_temp.rg_wm_target('wm_plain_start', array['wm_plain']);
reset role;
select pg_temp.rg_wm_advance('wmf_base');
-- The order rows that only the private ledger will touch (tuple, revision, stamp) before their claims.
create temp table _rg_wm_orders as
select o.id, o.ctid::text as tup, o.revision, o.updated_at from public.orders o
 where o.id in (select pg_temp.zc_id('order-' || l) from unnest(array['wm_main', 'wm_free', 'wm_resolve', 'wm_mark']) l);
select is(
  jsonb_build_object(
    'has_more', pg_temp.rg_get('wmf_base') -> 'has_more',
    'section_rows', (select coalesce(jsonb_agg(r order by r ->> 'order_id'), '[]'::jsonb)
                       from jsonb_array_elements(pg_temp.rg_wm_rows('wmf_base')) r
                      where r ->> 'order_id' in (select pg_temp.zc_id('order-' || l)::text
                                                   from unnest(array['wm_main', 'wm_free', 'wm_resolve', 'wm_mark',
                                                                     'wm_record', 'wm_plain', 'wm_sib', 'wm_foreign',
                                                                     'wm_page_a', 'wm_page_b']) l)),
    'cursor_after_tx_start', (select w.at > now() from _rg_wm w where w.k = 'cursor')),
  jsonb_build_object(
    'has_more', false,
    'section_rows', (select jsonb_agg(pg_temp.rg_wm_row(l) order by pg_temp.zc_id('order-' || l)::text)
                       from unnest(array['wm_main', 'wm_free', 'wm_resolve', 'wm_mark', 'wm_record', 'wm_plain',
                                         'wm_sib']) l),
    'cursor_after_tx_start', true),
  'RG-130 C1-1 setup: the baseline feed (from the start, one complete page) delivers the seven new pilot orders without card_attempt_in_progress and neither the foreign nor the sibling-branch orders; the cursor ends on a claim-stamped row after the transaction start');

-- (a) A LIVE claim appears.
set local role service_role;
insert into _zc_r select 'wm_claim_main', pg_temp.zc_claim(1, pg_temp.zc_lop('wm_main'), 'live', 2101,
  pg_temp.zc_id('order-wm_main'), 1);
reset role;
select pg_temp.rg_wm_save('main.claim', pg_temp.rg_wm_id('wm_claim_main'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_a');
reset role;
select pg_temp.rg_wm_advance('wmf_a');
select is(
  jsonb_build_object('claim', jsonb_build_array(pg_temp.rg_get('wm_claim_main') -> 'claim_created',
                                                pg_temp.rg_get('wm_claim_main') -> 'state'),
                     'feed', pg_temp.rg_wm_rows('wmf_a')),
  jsonb_build_object('claim', '[true, "sent"]'::jsonb,
                     'feed', jsonb_build_array(pg_temp.rg_wm_row('wm_main', true))),
  'RG-131 C1-1 (a): a LIVE claim (sent) on wm_main makes the incremental feed (p_since_at / p_since_id = the baseline cursor) re-deliver exactly that order, with card_attempt_in_progress true');
select is(
  (select jsonb_build_object('sync_is_signal', pg_temp.rg_wm_sync('wmf_a', 'wm_main') = s.sig,
                             'signal_is_created', s.sig = s.created, 'updated_is_created', s.updated = s.created)
     from _rg_wm_sig s where s.k = 'main.claim'),
  '{"sync_is_signal": true, "signal_is_created": true, "updated_is_created": true}'::jsonb,
  'RG-132 C1-1 (a)/(i): the delivered sync_at is the attempt''s claim_signal_at, which the insert guard stamped equal to created_at (and updated_at)');

-- (b) A repeat read from the new cursor, with no write in between.
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_b');
reset role;
select pg_temp.rg_wm_advance('wmf_b');
select is(pg_temp.rg_wm_page_facts('wmf_b'), '{"orders": [], "has_more": false, "next_cursor": null}'::jsonb,
  'RG-133 C1-1 (b): a repeat read from the new cursor with no write in between returns no row (orders [], has_more false, next_cursor null)');

-- (c) Writes that must not re-deliver the claimed order.
set local role service_role;
insert into _zc_r select 'wm_poll', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_main'), 'lookup', 'pending', '{}'::jsonb,
  'auto');
reset role;
insert into _zc_r select 'wma_main_poll', pg_temp.rg_wm_attempt('wm_main');
select pg_temp.rg_wm_save('main.poll', pg_temp.rg_wm_id('wm_claim_main'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_c_poll');
reset role;
select pg_temp.rg_wm_advance('wmf_c_poll');
select is(
  jsonb_build_object('feed', pg_temp.rg_wm_rows('wmf_c_poll'),
                     'state', pg_temp.rg_get('wma_main_poll') ->> 'state',
                     'auto_poll_count', pg_temp.rg_get('wma_main_poll') -> 'auto_poll_count',
                     'lookup_stamped', pg_temp.rg_get('wma_main_poll') ->> 'last_lookup_at' is not null,
                     'row_written', (pg_temp.rg_get('wma_main_poll') ->> 'updated_at')::timestamptz
                                    > (select s.created from _rg_wm_sig s where s.k = 'main.claim'),
                     'signal_kept', pg_temp.rg_wm_sig('main.poll') = pg_temp.rg_wm_sig('main.claim')),
  '{"feed": [], "state": "sent", "auto_poll_count": 1, "lookup_stamped": true, "row_written": true, "signal_kept": true}'::jsonb,
  'RG-134 C1-1 (c): an automatic poll (card_attempt_finish lookup pending, p_poll_source auto) counts and stamps the row (auto_poll_count 1, last_lookup_at) but keeps claim_signal_at - the feed from the cursor returns no row');

set local role service_role;
insert into _zc_r select 'wm_stamp', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_main'), 'lookup', 'not_found');
reset role;
insert into _zc_r select 'wma_main_stamp', pg_temp.rg_wm_attempt('wm_main');
select pg_temp.rg_wm_save('main.stamp', pg_temp.rg_wm_id('wm_claim_main'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_c_stamp');
reset role;
select pg_temp.rg_wm_advance('wmf_c_stamp');
select is(
  jsonb_build_object('feed', pg_temp.rg_wm_rows('wmf_c_stamp'),
                     'state', pg_temp.rg_get('wma_main_stamp') ->> 'state',
                     'auto_poll_count', pg_temp.rg_get('wma_main_stamp') -> 'auto_poll_count',
                     'lookup_restamped', (pg_temp.rg_get('wma_main_stamp') ->> 'last_lookup_at')::timestamptz
                                         > (pg_temp.rg_get('wma_main_poll') ->> 'last_lookup_at')::timestamptz,
                     'signal_kept', pg_temp.rg_wm_sig('main.stamp') = pg_temp.rg_wm_sig('main.claim')),
  '{"feed": [], "state": "sent", "auto_poll_count": 1, "lookup_restamped": true, "signal_kept": true}'::jsonb,
  'RG-135 C1-1 (c): a lookup stamp (lookup not_found, no poll source) moves last_lookup_at forward but not claim_signal_at - the feed returns no row');

set local role service_role;
insert into _zc_r select 'wm_release', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-1'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('wm_main'), pg_temp.zc_caller());
reset role;
insert into _zc_r select 'wma_main_release', pg_temp.rg_wm_attempt('wm_main');
select pg_temp.rg_wm_save('main.release', pg_temp.rg_wm_id('wm_claim_main'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_c_release');
reset role;
select pg_temp.rg_wm_advance('wmf_c_release');
select is(
  jsonb_build_object('mark', jsonb_build_array(pg_temp.rg_get('wm_release') -> 'ok', pg_temp.rg_get('wm_release') -> 'state'),
                     'feed', pg_temp.rg_wm_rows('wmf_c_release'),
                     'release_stamped', pg_temp.rg_get('wma_main_release') ->> 'release_requested_at' is not null,
                     'signal_kept', pg_temp.rg_wm_sig('main.release') = pg_temp.rg_wm_sig('main.claim')),
  '{"mark": [true, "sent"], "feed": [], "release_stamped": true, "signal_kept": true}'::jsonb,
  'RG-136 C1-1 (c): a release mark (card_attempt_mark_release_requested by the cashier) stamps release_requested_at on the sent attempt but keeps claim_signal_at - the feed returns no row');

insert into _zc_r select 'wma_main_before_hold', pg_temp.rg_wm_attempt('wm_main');
insert into _zc_r select 'wm_counts_before_hold', pg_temp.rg_counts();
insert into _zc_r select 'wm_hold_live', app.card_attempt_set_incident_hold('attempt', pg_temp.rg_wm_id('wm_claim_main'),
  true, 'zc001d-hold-wm', 'Incident review of the claim', 'zc001d-op/ref-wm-hold', pg_temp.zc_owner());
select pg_temp.rg_wm_save('main.hold', pg_temp.rg_wm_id('wm_claim_main'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_c_hold');
select pg_temp.rg_wm_target('wm_main_t1', array['wm_main']);
reset role;
select pg_temp.rg_wm_advance('wmf_c_hold');
select is(
  jsonb_build_object('hold', pg_temp.rg_get('wm_hold_live'),
                     'row_unchanged', pg_temp.rg_wm_attempt('wm_main') = pg_temp.rg_get('wma_main_before_hold'),
                     'nothing_written', pg_temp.rg_counts() = pg_temp.rg_get('wm_counts_before_hold'),
                     'feed', pg_temp.rg_wm_rows('wmf_c_hold')),
  '{"hold": {"ok": false, "error": "precondition_failed", "detail": "attempt_not_test"}, "row_unchanged": true, "nothing_written": true, "feed": []}'::jsonb,
  'RG-137 C1-1 (c): an incident hold never reaches a LIVE attempt (precondition_failed / attempt_not_test; the row byte-identical, no private event, audit, attempt or payment written) - the feed returns no row');
select is(
  jsonb_build_object('rows', pg_temp.rg_wm_rows('wm_main_t1'),
                     'sync_unchanged', pg_temp.rg_wm_sync('wm_main_t1', 'wm_main') = pg_temp.rg_wm_sync('wmf_a', 'wm_main'),
                     'updated_moved_past_signal', (pg_temp.rg_get('wma_main_release') ->> 'updated_at')::timestamptz
                                                  > pg_temp.rg_wm_sig('main.claim')),
  jsonb_build_object('rows', jsonb_build_array(pg_temp.rg_wm_row('wm_main', true)), 'sync_unchanged', true,
                     'updated_moved_past_signal', true),
  'RG-138 C1-1 (c): after the poll, the lookup stamp, the release mark and the refused hold a targeted read still shows wm_main in progress at the very sync_at of the claim, although the row''s updated_at moved past it');

-- (d) The claim ends: a declined finish.
set local role service_role;
insert into _zc_r select 'wm_decline', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_main'), 'commit', 'declined',
  pg_temp.rg_wm_declined());
reset role;
select pg_temp.rg_wm_save('main.decline', pg_temp.rg_wm_id('wm_claim_main'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_d_decline');
reset role;
select pg_temp.rg_wm_advance('wmf_d_decline');
select is(
  jsonb_build_object('state', pg_temp.rg_get('wm_decline') ->> 'state',
                     'feed', pg_temp.rg_wm_rows('wmf_d_decline'),
                     'sync_is_new_signal', pg_temp.rg_wm_sync('wmf_d_decline', 'wm_main') = pg_temp.rg_wm_sig('main.decline'),
                     'signal_advanced', pg_temp.rg_wm_sig('main.decline') > pg_temp.rg_wm_sig('main.claim')),
  jsonb_build_object('state', 'declined', 'feed', jsonb_build_array(pg_temp.rg_wm_row('wm_main')),
                     'sync_is_new_signal', true, 'signal_advanced', true),
  'RG-139 C1-1 (d): a declined finish ends the claim and advances claim_signal_at - the feed re-delivers exactly wm_main, without card_attempt_in_progress, at the new signal');
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_d_decline_again');
reset role;
select pg_temp.rg_wm_advance('wmf_d_decline_again');
select is(pg_temp.rg_wm_page_facts('wmf_d_decline_again'), '{"orders": [], "has_more": false, "next_cursor": null}'::jsonb,
  'RG-140 C1-1 (d): the declined order is delivered once - the next read from the moved cursor returns no row');

-- (d) The claim ends: a manager free_order (after a state change and a lookup).
set local role service_role;
insert into _zc_r select 'wm_claim_free', pg_temp.zc_claim(1, pg_temp.zc_lop('wm_free'), 'live', 2201,
  pg_temp.zc_id('order-wm_free'), 1);
reset role;
select pg_temp.rg_wm_save('free.claim', pg_temp.rg_wm_id('wm_claim_free'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_free_claim');
reset role;
select pg_temp.rg_wm_advance('wmf_free_claim');
set local role service_role;
insert into _zc_r select 'wm_free_unknown', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_free'), 'commit', 'unknown');
reset role;
select pg_temp.rg_wm_save('free.unknown', pg_temp.rg_wm_id('wm_claim_free'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_free_unknown');
reset role;
select pg_temp.rg_wm_advance('wmf_free_unknown');
select is(
  jsonb_build_object('claim_feed', pg_temp.rg_wm_rows('wmf_free_claim'),
                     'unknown_state', pg_temp.rg_get('wm_free_unknown') ->> 'state',
                     'unknown_feed', pg_temp.rg_wm_rows('wmf_free_unknown'),
                     'signal_advanced', pg_temp.rg_wm_sig('free.unknown') > pg_temp.rg_wm_sig('free.claim'),
                     'sync_is_signal', pg_temp.rg_wm_sync('wmf_free_unknown', 'wm_free') = pg_temp.rg_wm_sig('free.unknown')),
  jsonb_build_object('claim_feed', jsonb_build_array(pg_temp.rg_wm_row('wm_free', true)),
                     'unknown_state', 'unknown',
                     'unknown_feed', jsonb_build_array(pg_temp.rg_wm_row('wm_free', true)),
                     'signal_advanced', true, 'sync_is_signal', true),
  'RG-141 C1-1 (a)/(i): a second claim (wm_free) is re-delivered with the key; its state change sent -> unknown advances claim_signal_at and re-delivers it again, still in progress');
set local role service_role;
insert into _zc_r select 'wm_free_lookup', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_free'), 'lookup', 'not_found',
  '{"provider_status_code": "nf1", "provider_return_class": "not_found"}'::jsonb);
reset role;
select pg_temp.rg_wm_save('free.lookup', pg_temp.rg_wm_id('wm_claim_free'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_free_lookup');
reset role;
select pg_temp.rg_wm_advance('wmf_free_lookup');
select is(
  jsonb_build_object('feed', pg_temp.rg_wm_rows('wmf_free_lookup'),
                     'state', pg_temp.rg_wm_attempt('wm_free') ->> 'state',
                     'lookup_stamped', pg_temp.rg_wm_attempt('wm_free') ->> 'last_lookup_at' is not null,
                     'provider_fields', jsonb_build_array(pg_temp.rg_wm_attempt('wm_free') ->> 'provider_status_code',
                                                          pg_temp.rg_wm_attempt('wm_free') ->> 'provider_return_class'),
                     'signal_kept', pg_temp.rg_wm_sig('free.lookup') = pg_temp.rg_wm_sig('free.unknown')),
  '{"feed": [], "state": "unknown", "lookup_stamped": true, "provider_fields": ["nf1", "not_found"], "signal_kept": true}'::jsonb,
  'RG-142 C1-1 (c): a lookup on the unknown attempt (the free''s precondition) stamps last_lookup_at and stores provider fields (provider_status_code, provider_return_class) without a state change - claim_signal_at kept, the feed returns no row');
set local role service_role;
insert into _zc_r select 'wm_free_mgr', public.card_attempt_free_order(pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('wm_free'), 'Provider report shows no charge', 'provider_report', 'rpt-wm-free', pg_temp.zc_caller());
reset role;
select pg_temp.rg_wm_save('free.free', pg_temp.rg_wm_id('wm_claim_free'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_free_end');
reset role;
select pg_temp.rg_wm_advance('wmf_free_end');
select is(
  jsonb_build_object('classification', pg_temp.rg_get('wm_free_mgr') ->> 'classification',
                     'freed_reason', pg_temp.rg_wm_attempt('wm_free') ->> 'order_freed_reason',
                     'feed', pg_temp.rg_wm_rows('wmf_free_end'),
                     'sync_is_new_signal', pg_temp.rg_wm_sync('wmf_free_end', 'wm_free') = pg_temp.rg_wm_sig('free.free'),
                     'signal_advanced', pg_temp.rg_wm_sig('free.free') > pg_temp.rg_wm_sig('free.lookup')),
  jsonb_build_object('classification', 'freed', 'freed_reason', 'manager_confirmed',
                     'feed', jsonb_build_array(pg_temp.rg_wm_row('wm_free')),
                     'sync_is_new_signal', true, 'signal_advanced', true),
  'RG-143 C1-1 (d): the manager free_order (provider_report evidence) ends the claim and advances claim_signal_at - the feed re-delivers exactly wm_free, without the key');
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_free_again');
reset role;
select pg_temp.rg_wm_advance('wmf_free_again');
select is(pg_temp.rg_wm_page_facts('wmf_free_again'), '{"orders": [], "has_more": false, "next_cursor": null}'::jsonb,
  'RG-144 C1-1 (d): the freed order is delivered once - the next read returns no row');

-- (d) The claim ends: an operator resolution (after a provider anomaly).
set local role service_role;
insert into _zc_r select 'wm_claim_resolve', pg_temp.zc_claim(1, pg_temp.zc_lop('wm_resolve'), 'live', 2301,
  pg_temp.zc_id('order-wm_resolve'), 1);
reset role;
select pg_temp.rg_wm_save('resolve.claim', pg_temp.rg_wm_id('wm_claim_resolve'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_res_claim');
reset role;
select pg_temp.rg_wm_advance('wmf_res_claim');
set local role service_role;
insert into _zc_r select 'wm_res_anomaly', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_resolve'), 'commit', 'anomaly',
  '{"anomaly_code": "voided"}'::jsonb);
reset role;
select pg_temp.rg_wm_save('resolve.anomaly', pg_temp.rg_wm_id('wm_claim_resolve'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_res_anomaly');
reset role;
select pg_temp.rg_wm_advance('wmf_res_anomaly');
select is(
  jsonb_build_object('claim_feed', pg_temp.rg_wm_rows('wmf_res_claim'),
                     'anomaly', jsonb_build_array(pg_temp.rg_wm_attempt('wm_resolve') ->> 'state',
                                                  pg_temp.rg_wm_attempt('wm_resolve') -> 'charge_may_exist'),
                     'anomaly_feed', pg_temp.rg_wm_rows('wmf_res_anomaly'),
                     'signal_advanced', pg_temp.rg_wm_sig('resolve.anomaly') > pg_temp.rg_wm_sig('resolve.claim')),
  jsonb_build_object('claim_feed', jsonb_build_array(pg_temp.rg_wm_row('wm_resolve', true)),
                     'anomaly', '["unknown", true]'::jsonb,
                     'anomaly_feed', jsonb_build_array(pg_temp.rg_wm_row('wm_resolve', true)),
                     'signal_advanced', true),
  'RG-145 C1-1 (a)/(i): a third claim (wm_resolve) is re-delivered with the key; the provider anomaly (sent -> unknown, charge_may_exist) advances the signal and re-delivers it still in progress');
insert into _zc_r select 'wm_res_resolve', app.card_attempt_resolve_orphan(pg_temp.rg_wm_id('wm_claim_resolve'),
  'provider_voided', 'void-ref-wm', 'Provider voided the charge', 'zc001d-op/ref-wm-res', pg_temp.zc_owner());
select pg_temp.rg_wm_save('resolve.resolve', pg_temp.rg_wm_id('wm_claim_resolve'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_res_end');
reset role;
select pg_temp.rg_wm_advance('wmf_res_end');
select is(
  jsonb_build_object('resolution', pg_temp.rg_wm_attempt('wm_resolve') ->> 'resolution',
                     'freed_reason', pg_temp.rg_wm_attempt('wm_resolve') ->> 'order_freed_reason',
                     'feed', pg_temp.rg_wm_rows('wmf_res_end'),
                     'sync_is_new_signal', pg_temp.rg_wm_sync('wmf_res_end', 'wm_resolve') = pg_temp.rg_wm_sig('resolve.resolve'),
                     'signal_advanced', pg_temp.rg_wm_sig('resolve.resolve') > pg_temp.rg_wm_sig('resolve.anomaly')),
  jsonb_build_object('resolution', 'provider_voided', 'freed_reason', 'orphan_resolved',
                     'feed', jsonb_build_array(pg_temp.rg_wm_row('wm_resolve')),
                     'sync_is_new_signal', true, 'signal_advanced', true),
  'RG-146 C1-1 (d): the operator resolution (provider_voided; the order freed orphan_resolved) ends the claim and advances claim_signal_at - the feed re-delivers exactly wm_resolve, without the key');
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_res_again');
reset role;
select pg_temp.rg_wm_advance('wmf_res_again');
select is(pg_temp.rg_wm_page_facts('wmf_res_again'), '{"orders": [], "has_more": false, "next_cursor": null}'::jsonb,
  'RG-147 C1-1 (d): the resolved order is delivered once - the next read returns no row');

-- (c) A recording-result mark on an approved, unrecorded claim.
set local role service_role;
insert into _zc_r select 'wm_claim_mark', pg_temp.zc_claim(1, pg_temp.zc_lop('wm_mark'), 'live', 2501,
  pg_temp.zc_id('order-wm_mark'), 1);
reset role;
select pg_temp.rg_wm_save('mark.claim', pg_temp.rg_wm_id('wm_claim_mark'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_mark_claim');
reset role;
select pg_temp.rg_wm_advance('wmf_mark_claim');
set local role service_role;
insert into _zc_r select 'wm_mark_approve', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_mark'), 'commit', 'approved',
  pg_temp.zc_approved_fields());
reset role;
select pg_temp.rg_wm_save('mark.approved', pg_temp.rg_wm_id('wm_claim_mark'));
insert into _zc_r select 'wma_mark_approved', pg_temp.rg_wm_attempt('wm_mark');
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_mark_approved');
reset role;
select pg_temp.rg_wm_advance('wmf_mark_approved');
select is(
  jsonb_build_object('claim_feed', pg_temp.rg_wm_rows('wmf_mark_claim'),
                     'approved', jsonb_build_array(pg_temp.rg_get('wm_mark_approve') ->> 'state',
                                                   pg_temp.rg_get('wm_mark_approve') ->> 'classification'),
                     'approved_feed', pg_temp.rg_wm_rows('wmf_mark_approved'),
                     'signal_advanced', pg_temp.rg_wm_sig('mark.approved') > pg_temp.rg_wm_sig('mark.claim')),
  jsonb_build_object('claim_feed', jsonb_build_array(pg_temp.rg_wm_row('wm_mark', true)),
                     'approved', '["approved", "approved_unrecorded"]'::jsonb,
                     'approved_feed', jsonb_build_array(pg_temp.rg_wm_row('wm_mark', true)),
                     'signal_advanced', true),
  'RG-148 C1-1 (a)/(i): a fourth claim (wm_mark) is re-delivered with the key; its approval advances the signal and re-delivers it, still in progress (approved without its strict-join payment)');
set local role authenticated;
insert into _zc_r select 'wm_mark_push', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('wm_mark'), pg_temp.zc_id('order-wm_mark'), 'cash', 2501)));
reset role;
select pg_temp.rg_wm_save('mark.push', pg_temp.rg_wm_id('wm_claim_mark'));
insert into _zc_r select 'wma_mark_after_push', pg_temp.rg_wm_attempt('wm_mark');
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_mark_push');
reset role;
select pg_temp.rg_wm_advance('wmf_mark_push');
set local role service_role;
insert into _zc_r select 'wm_mark_result', public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-1'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('wm_mark'), 'provider_recording_refused', pg_temp.zc_caller());
reset role;
select pg_temp.rg_wm_save('mark.mark', pg_temp.rg_wm_id('wm_claim_mark'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_mark_mark');
select pg_temp.rg_wm_target('wm_mark_t', array['wm_mark']);
reset role;
select pg_temp.rg_wm_advance('wmf_mark_mark');
select is(
  jsonb_build_object('push', jsonb_build_array(pg_temp.rg_res('wm_mark_push') ->> 'status',
                                               pg_temp.rg_res('wm_mark_push') ->> 'error',
                                               pg_temp.rg_res('wm_mark_push') ->> 'detail'),
                     'payments', (select count(*) from public.payments p where p.order_id = pg_temp.zc_id('order-wm_mark')),
                     'attempt_unchanged', pg_temp.rg_get('wma_mark_after_push') = pg_temp.rg_get('wma_mark_approved'),
                     'feed', pg_temp.rg_wm_rows('wmf_mark_push'),
                     'signal_kept', pg_temp.rg_wm_sig('mark.push') = pg_temp.rg_wm_sig('mark.approved')),
  '{"push": ["rejected", "provider_recording_refused", "tender_mismatch"], "payments": 0, "attempt_unchanged": true, "feed": [], "signal_kept": true}'::jsonb,
  'RG-149 C1-1 (c): a payment.create under the attempt''s identity with another tender is refused (provider_recording_refused / tender_mismatch; no payment, the attempt row byte-identical) - claim_signal_at kept, the feed returns no row');
select is(
  jsonb_build_object('mark_state', pg_temp.rg_get('wm_mark_result') ->> 'state',
                     'refusal_code', pg_temp.rg_wm_attempt('wm_mark') ->> 'refusal_code',
                     'refused_stamped', pg_temp.rg_wm_attempt('wm_mark') ->> 'recording_refused_at' is not null,
                     'signal_kept', pg_temp.rg_wm_sig('mark.mark') = pg_temp.rg_wm_sig('mark.approved'),
                     'feed', pg_temp.rg_wm_rows('wmf_mark_mark'),
                     'target', pg_temp.rg_wm_rows('wm_mark_t'),
                     'sync_unchanged', pg_temp.rg_wm_sync('wm_mark_t', 'wm_mark') = pg_temp.rg_wm_sync('wmf_mark_approved', 'wm_mark')),
  jsonb_build_object('mark_state', 'approved', 'refusal_code', 'nonrecoverable_refusal', 'refused_stamped', true,
                     'signal_kept', true, 'feed', '[]'::jsonb,
                     'target', jsonb_build_array(pg_temp.rg_wm_row('wm_mark', true)), 'sync_unchanged', true),
  'RG-150 C1-1 (c): the recording-result mark persists refusal_code nonrecoverable_refusal and recording_refused_at on the approved attempt but keeps claim_signal_at - the feed returns no row and a targeted read shows wm_mark still in progress at its approval''s sync_at');

-- (d) The claim ends: the recording leg (payment). The order and its approved claim are written as if
-- committed before this transaction (the time-travel note above); the POS last read the order at that state.
set local role service_role;
insert into _zc_r select 'wm_claim_record', pg_temp.zc_claim(1, pg_temp.zc_lop('wm_record'), 'live', 2401,
  pg_temp.zc_id('order-wm_record'), 1);
reset role;
select pg_temp.rg_wm_save('record.claim', pg_temp.rg_wm_id('wm_claim_record'));
set local role service_role;
insert into _zc_r select 'wm_record_approve', pg_temp.zc_finish(pg_temp.rg_get('wm_claim_record'), 'commit', 'approved',
  pg_temp.zc_approved_fields());
reset role;
select pg_temp.rg_wm_save('record.approved', pg_temp.rg_wm_id('wm_claim_record'));
insert into _zc_r select 'wm_record_travel', to_jsonb(pg_temp.rg_wm_signal_back(pg_temp.rg_wm_id('wm_claim_record'),
  now() - interval '5 minutes'));
set local role authenticated;
select pg_temp.rg_wm_target('wm_record_t0', array['wm_record']);
reset role;
insert into _rg_wm select 'k4', pg_temp.rg_wm_sync('wm_record_t0', 'wm_record'), pg_temp.zc_id('order-wm_record');
set local role authenticated;
select pg_temp.rg_wm_feed('wmk_rec_pre', 'k4');
reset role;
select is(
  jsonb_build_object('approved', pg_temp.rg_get('wm_record_approve') ->> 'state',
                     'signal_moved', pg_temp.rg_get('wm_record_travel'),
                     'target', pg_temp.rg_wm_rows('wm_record_t0'),
                     'sync_is_moved_signal', pg_temp.rg_wm_sync('wm_record_t0', 'wm_record') = now() - interval '5 minutes',
                     'pre_leg_feed_has_it', (select count(*) from jsonb_array_elements(pg_temp.rg_wm_rows('wmk_rec_pre')) r
                                              where r ->> 'order_id' = pg_temp.zc_id('order-wm_record')::text)),
  jsonb_build_object('approved', 'approved', 'signal_moved', true,
                     'target', jsonb_build_array(pg_temp.rg_wm_row('wm_record', true)),
                     'sync_is_moved_signal', true, 'pre_leg_feed_has_it', 0),
  'RG-151 C1-1 (d) setup: wm_record is approved and unrecorded; with its order and claim written as if committed earlier its sync_at is the claim signal 5 minutes before this transaction, and a feed from the cursor of that read does not contain it');
set local role authenticated;
insert into _zc_r select 'wm_record_leg', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('wm_record'), pg_temp.zc_id('order-wm_record'), 'card', 2401)));
reset role;
select pg_temp.rg_wm_save('record.leg', pg_temp.rg_wm_id('wm_claim_record'));
set local role authenticated;
select pg_temp.rg_wm_feed('wmk_rec_post', 'k4');
reset role;
select is(
  jsonb_build_object('leg', jsonb_build_array(pg_temp.rg_res('wm_record_leg') ->> 'status',
                                              pg_temp.rg_res('wm_record_leg') -> 'ok',
                                              pg_temp.rg_res('wm_record_leg') ->> 'order_status'),
                     'payments', (select count(*) from public.payments p where p.order_id = pg_temp.zc_id('order-wm_record')),
                     'classification', (select app.card_attempt_derive(a) ->> 'classification' from app.card_provider_attempts a
                                         where a.id = pg_temp.rg_wm_id('wm_claim_record'))),
  '{"leg": ["applied", true, "completed"], "payments": 1, "classification": "recorded"}'::jsonb,
  'RG-152 C1-1 (d): the recording leg (payment.create, card, the attempt identity) is applied: one payment, the attempt recorded through the strict join, the printer-only order completed');
select is(
  jsonb_build_object(
    'delivered', (select coalesce(jsonb_agg(r), '[]'::jsonb) from jsonb_array_elements(pg_temp.rg_wm_rows('wmk_rec_post')) r
                   where r ->> 'order_id' = pg_temp.zc_id('order-wm_record')::text),
    'sync_is_payment', pg_temp.rg_wm_sync('wmk_rec_post', 'wm_record')
                       = (select p.updated_at from public.payments p where p.order_id = pg_temp.zc_id('order-wm_record')),
    'signal_untouched_by_leg', pg_temp.rg_wm_sig('record.leg') = now() - interval '5 minutes'),
  jsonb_build_object('delivered', jsonb_build_array(pg_temp.rg_wm_row('wm_record')),
                     'sync_is_payment', true, 'signal_untouched_by_leg', true),
  'RG-153 C1-1 (d): the recording leg ends the claim through the existing pay.updated_at term - the feed from the same cursor re-delivers wm_record exactly once, without the key, at its payment''s updated_at; the leg writes no claim signal');
select pg_temp.rg_wm_advance('wmk_rec_post', 'k4');
set local role authenticated;
select pg_temp.rg_wm_feed('wmk_rec_again', 'k4');
select pg_temp.rg_wm_feed('wmf_after_record');
reset role;
select pg_temp.rg_wm_advance('wmf_after_record');
select is(
  jsonb_build_object('again', pg_temp.rg_wm_page_facts('wmk_rec_again'), 'main', pg_temp.rg_wm_page_facts('wmf_after_record')),
  '{"again": {"orders": [], "has_more": false, "next_cursor": null}, "main": {"orders": [], "has_more": false, "next_cursor": null}}'::jsonb,
  'RG-154 C1-1 (d): the recorded order is delivered once - the next read from that feed''s last row returns no row, and nothing is pending on the main cursor either');

-- (f) Another organization's claim; then a same-organization row of another branch (each fed on its own).
insert into _zc_r select 'wm_foreign_ins', to_jsonb(pg_temp.rg_wm_insert(4, 7, 'wm_foreign', 'live', 2801, 'wm_foreign'));
select pg_temp.rg_wm_save('foreign.insert', (pg_temp.rg_get('wm_foreign_ins') #>> '{}')::uuid);
set local role service_role;
insert into _zc_r select 'wm_foreign_unknown', public.card_attempt_finish((pg_temp.rg_get('wm_foreign_ins') #>> '{}')::uuid,
  pg_temp.zc_id('org_b'), pg_temp.zc_id('device-4'), pg_temp.zc_lop('wm_foreign'), 'live', 2801, 'ILS', 'commit',
  'unknown', '{}'::jsonb, null);
reset role;
select pg_temp.rg_wm_save('foreign.unknown', (pg_temp.rg_get('wm_foreign_ins') #>> '{}')::uuid);
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_f_foreign');
select pg_temp.rg_wm_target('wm_foreign_t', array['wm_foreign'], 7, 4);
reset role;
select pg_temp.rg_wm_advance('wmf_f_foreign');
select is(
  jsonb_build_array(pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_foreign_ins') #>> '{}')::uuid) ->> 'organization_id',
                    pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_foreign_ins') #>> '{}')::uuid) ->> 'order_id',
                    pg_temp.rg_get('wm_foreign_unknown') ->> 'state'),
  jsonb_build_array(pg_temp.zc_id('org_b')::text, pg_temp.zc_id('order-wm_foreign')::text, 'unknown'),
  'RG-155 C1-1 (f) setup: a LIVE claim of the foreign organization on its own order (owner-inserted: the pilot scope is pinned, so no RPC can create one) moved sent -> unknown by the scope-bound finish');
select is(
  jsonb_build_object('pilot_feed', pg_temp.rg_wm_rows('wmf_f_foreign'),
                     'foreign_own_read', pg_temp.rg_wm_rows('wm_foreign_t'),
                     'foreign_sync_is_its_signal', pg_temp.rg_wm_sync('wm_foreign_t', 'wm_foreign') = pg_temp.rg_wm_sig('foreign.unknown')),
  jsonb_build_object('pilot_feed', '[]'::jsonb,
                     'foreign_own_read', jsonb_build_array(pg_temp.rg_wm_row('wm_foreign', true)),
                     'foreign_sync_is_its_signal', true),
  'RG-156 C1-1 (f): the foreign organization''s claim and its state change never reach this organization''s snapshot (the pilot feed returns no row) while its own POS (staff 7 on d4) reads its order in progress at its own signal - the stamp is organization-scoped both ways');
insert into _zc_r select 'wm_sib_ins', to_jsonb(pg_temp.rg_wm_insert(5, 10, 'wm_sib', 'live', 2701, 'wm_sib'));
select pg_temp.rg_wm_save('sib.insert', (pg_temp.rg_get('wm_sib_ins') #>> '{}')::uuid);
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_f_sib');
select pg_temp.rg_wm_target('wm_sib_t', array['wm_sib']);
reset role;
select pg_temp.rg_wm_advance('wmf_f_sib');
select is(
  jsonb_build_object('row', jsonb_build_array(pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_sib_ins') #>> '{}')::uuid) ->> 'branch_id',
                                              pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_sib_ins') #>> '{}')::uuid) ->> 'state'),
                     'feed', pg_temp.rg_wm_rows('wmf_f_sib'), 'target', pg_temp.rg_wm_rows('wm_sib_t'),
                     'sync_is_order_updated_at', pg_temp.rg_wm_sync('wm_sib_t', 'wm_sib')
                                                 = (select o.updated_at from public.orders o where o.id = pg_temp.zc_id('order-wm_sib'))),
  jsonb_build_object('row', jsonb_build_array(pg_temp.zc_id('branch_sib')::text, 'sent'),
                     'feed', '[]'::jsonb, 'target', jsonb_build_array(pg_temp.rg_wm_row('wm_sib')),
                     'sync_is_order_updated_at', true),
  'RG-157 C1-1 (f; same branch): a pilot-organization LIVE row of the sibling branch (device d5, owner-inserted) naming the pilot-branch order wm_sib contributes neither card_attempt_in_progress nor its stamp - wm_sib reads without the key at its own updated_at and is not re-delivered');

-- (g) A TEST attempt (no order by the TEST shape) through its whole life never contributes.
insert into _zc_r select 'wm_test_ins', to_jsonb(pg_temp.rg_wm_insert(1, 1, 'wm_test', 'test', 1234));
select pg_temp.rg_wm_save('test.insert', (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid);
set local role service_role;
insert into _zc_r select 'wm_test_unknown', public.card_attempt_finish((pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid,
  pg_temp.zc_org(), pg_temp.zc_id('device-1'), pg_temp.zc_lop('wm_test'), 'test', 1234, 'ILS', 'commit', 'unknown',
  '{}'::jsonb, null);
reset role;
select pg_temp.rg_wm_save('test.unknown', (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid);
insert into _zc_r select 'wm_test_hold', app.card_attempt_set_incident_hold('attempt',
  (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid, true, 'zc001d-hold-wm-test', 'Incident review of a TEST row',
  'zc001d-op/ref-wm-hold', pg_temp.zc_owner());
select pg_temp.rg_wm_save('test.hold', (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid);
insert into _zc_r select 'wm_test_unhold', app.card_attempt_set_incident_hold('attempt',
  (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid, false, null, 'Incident review closed', 'zc001d-op/ref-wm-hold',
  pg_temp.zc_owner());
select pg_temp.rg_wm_save('test.unhold', (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid);
insert into _zc_r select 'wm_test_close', app.card_attempt_resolve_orphan((pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid,
  'test_closed', 'close-ref-wm', 'TEST attempt closed', 'zc001d-op/ref-wm-close', pg_temp.zc_owner());
select pg_temp.rg_wm_save('test.close', (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid);
insert into _zc_r select 'wm_test_rehold', app.card_attempt_set_incident_hold('attempt',
  (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid, true, 'zc001d-hold-wm-test', 'Incident review reopened',
  'zc001d-op/ref-wm-hold', pg_temp.zc_owner());
select pg_temp.rg_wm_save('test.rehold', (pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid);
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_g');
reset role;
select pg_temp.rg_wm_advance('wmf_g');
select is(
  jsonb_build_object('answers', jsonb_build_array(pg_temp.rg_get('wm_test_unknown') ->> 'state',
                                                  pg_temp.rg_get('wm_test_hold') -> 'ok',
                                                  pg_temp.rg_get('wm_test_unhold') -> 'ok',
                                                  pg_temp.rg_get('wm_test_close') ->> 'state',
                                                  pg_temp.rg_get('wm_test_rehold') -> 'ok'),
                     'row', jsonb_build_array(pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid) -> 'order_id',
                                              pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid) ->> 'resolution',
                                              pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_test_ins') #>> '{}')::uuid) ->> 'incident_hold_at' is not null),
                     'feed', pg_temp.rg_wm_rows('wmf_g')),
  '{"answers": ["unknown", true, true, "unknown", true], "row": [null, "test_closed", true], "feed": []}'::jsonb,
  'RG-158 C1-1 (g): a TEST attempt of d1 (no order, by the TEST shape) moved sent -> unknown, held, released, closed test_closed and held again never re-delivers any order - the feed returns no row');

-- (i) The signal itself.
insert into _zc_r select 'wm_test2_ins', pg_temp.rg_try(format(
  'select to_jsonb(pg_temp.rg_wm_insert(1, 1, %L, %L, 1234, null, %L::timestamptz))', 'wm_test2', 'test',
  now() - interval '1 year'));
insert into _zc_r select 'wm_test2_after_insert', pg_temp.rg_wm_attempt_id((pg_temp.rg_get('wm_test2_ins') ->> 'result')::uuid);
insert into _zc_r select 'wm_test2_upd', pg_temp.rg_try(format(
  'update app.card_provider_attempts x set state = %L, claim_signal_at = %L::timestamptz where x.id = %L returning to_jsonb(x)',
  'declined', now() - interval '1 year', pg_temp.rg_get('wm_test2_ins') ->> 'result'));
select is(
  (select jsonb_build_object(
     'stamped_at_insert', bool_and(s.sig = s.created and s.updated = s.created), 'rows', count(*))
     from _rg_wm_sig s
    where s.k in ('main.claim', 'free.claim', 'resolve.claim', 'mark.claim', 'record.claim', 'foreign.insert',
                  'sib.insert', 'test.insert'))
  || jsonb_build_object(
     'supplied_value_replaced_at_insert', (pg_temp.rg_get('wm_test2_after_insert') ->> 'claim_signal_at')::timestamptz
                                          = (pg_temp.rg_get('wm_test2_after_insert') ->> 'created_at')::timestamptz),
  '{"stamped_at_insert": true, "rows": 8, "supplied_value_replaced_at_insert": true}'::jsonb,
  'RG-159 C1-1 (i): the insert guard stamps claim_signal_at = created_at = updated_at on every row of this section (five RPC claims; the owner-inserted foreign, sibling-branch and TEST rows) and replaces a writer-supplied value (a TEST row inserted with a signal a year back)');
select is(
  jsonb_build_object(
    'main_poll_kept', pg_temp.rg_wm_sig('main.poll') = pg_temp.rg_wm_sig('main.claim'),
    'main_stamp_kept', pg_temp.rg_wm_sig('main.stamp') = pg_temp.rg_wm_sig('main.claim'),
    'main_release_mark_kept', pg_temp.rg_wm_sig('main.release') = pg_temp.rg_wm_sig('main.claim'),
    'main_refused_hold_kept', pg_temp.rg_wm_sig('main.hold') = pg_temp.rg_wm_sig('main.claim'),
    'main_decline_advanced', pg_temp.rg_wm_sig('main.decline') > pg_temp.rg_wm_sig('main.hold'),
    'free_unknown_advanced', pg_temp.rg_wm_sig('free.unknown') > pg_temp.rg_wm_sig('free.claim'),
    'free_lookup_kept', pg_temp.rg_wm_sig('free.lookup') = pg_temp.rg_wm_sig('free.unknown'),
    'free_free_advanced', pg_temp.rg_wm_sig('free.free') > pg_temp.rg_wm_sig('free.lookup'),
    'resolve_anomaly_advanced', pg_temp.rg_wm_sig('resolve.anomaly') > pg_temp.rg_wm_sig('resolve.claim'),
    'resolve_resolution_advanced', pg_temp.rg_wm_sig('resolve.resolve') > pg_temp.rg_wm_sig('resolve.anomaly'),
    'mark_approval_advanced', pg_temp.rg_wm_sig('mark.approved') > pg_temp.rg_wm_sig('mark.claim'),
    'mark_refused_push_kept', pg_temp.rg_wm_sig('mark.push') = pg_temp.rg_wm_sig('mark.approved'),
    'mark_recording_mark_kept', pg_temp.rg_wm_sig('mark.mark') = pg_temp.rg_wm_sig('mark.approved'),
    'record_approval_advanced', pg_temp.rg_wm_sig('record.approved') > pg_temp.rg_wm_sig('record.claim'),
    'foreign_unknown_advanced', pg_temp.rg_wm_sig('foreign.unknown') > pg_temp.rg_wm_sig('foreign.insert')),
  '{"main_poll_kept": true, "main_stamp_kept": true, "main_release_mark_kept": true, "main_refused_hold_kept": true, "main_decline_advanced": true, "free_unknown_advanced": true, "free_lookup_kept": true, "free_free_advanced": true, "resolve_anomaly_advanced": true, "resolve_resolution_advanced": true, "mark_approval_advanced": true, "mark_refused_push_kept": true, "mark_recording_mark_kept": true, "record_approval_advanced": true, "foreign_unknown_advanced": true}'::jsonb,
  'RG-160 C1-1 (i): across the LIVE rows the signal advanced exactly at each state change (approve, decline, unknown, anomaly), the manager free and the resolution, and stayed put for the poll, the lookup stamps, the release and recording marks, the refused push and the refused hold');
select is(
  jsonb_build_object(
    'test_unknown_advanced', pg_temp.rg_wm_sig('test.unknown') > pg_temp.rg_wm_sig('test.insert'),
    'test_hold_kept', pg_temp.rg_wm_sig('test.hold') = pg_temp.rg_wm_sig('test.unknown'),
    'test_hold_clear_kept', pg_temp.rg_wm_sig('test.unhold') = pg_temp.rg_wm_sig('test.unknown'),
    'test_close_advanced', pg_temp.rg_wm_sig('test.close') > pg_temp.rg_wm_sig('test.unhold'),
    'test_hold_of_resolved_row_kept', pg_temp.rg_wm_sig('test.rehold') = pg_temp.rg_wm_sig('test.close'),
    'test2_state_change', pg_temp.rg_get('wm_test2_upd') -> 'result' ->> 'state',
    'test2_supplied_value_replaced_by_advance',
      (pg_temp.rg_get('wm_test2_upd') -> 'result' ->> 'claim_signal_at')::timestamptz
      > (pg_temp.rg_get('wm_test2_after_insert') ->> 'claim_signal_at')::timestamptz),
  '{"test_unknown_advanced": true, "test_hold_kept": true, "test_hold_clear_kept": true, "test_close_advanced": true, "test_hold_of_resolved_row_kept": true, "test2_state_change": "declined", "test2_supplied_value_replaced_by_advance": true}'::jsonb,
  'RG-161 C1-1 (i): on TEST rows the signal advances at the state change and the test_closed resolution, stays put for holds (also the hold-only update of a resolved row), and a direct owner state change that supplies its own claim_signal_at gets the guard''s advance instead');

insert into _zc_r select 'wm_mark_before_upd', pg_temp.rg_wm_attempt('wm_mark');
insert into _zc_r select 'wm_upd_other', pg_temp.rg_try(format(
  'update app.card_provider_attempts x set auto_poll_count = x.auto_poll_count + 1 where x.id = %L returning to_jsonb(x)',
  pg_temp.rg_wm_id('wm_claim_mark')));
insert into _zc_r select 'wm_upd_signal', pg_temp.rg_try(format(
  'update app.card_provider_attempts x set claim_signal_at = clock_timestamp() + interval %L where x.id = %L returning to_jsonb(x)',
  '1 day', pg_temp.rg_wm_id('wm_claim_mark')));
select is(
  jsonb_build_object(
    'other_raised', pg_temp.rg_get('wm_upd_other') -> 'raised',
    'other_counter', (pg_temp.rg_get('wm_upd_other') -> 'result' -> 'auto_poll_count')::int
                     - (pg_temp.rg_get('wm_mark_before_upd') -> 'auto_poll_count')::int,
    'other_updated_moved', (pg_temp.rg_get('wm_upd_other') -> 'result' ->> 'updated_at')::timestamptz
                           > (pg_temp.rg_get('wm_mark_before_upd') ->> 'updated_at')::timestamptz,
    'other_signal_kept', pg_temp.rg_get('wm_upd_other') -> 'result' -> 'claim_signal_at'
                         = pg_temp.rg_get('wm_mark_before_upd') -> 'claim_signal_at',
    'self_raised', pg_temp.rg_get('wm_upd_signal') -> 'raised',
    'self_updated_moved', (pg_temp.rg_get('wm_upd_signal') -> 'result' ->> 'updated_at')::timestamptz
                          > (pg_temp.rg_get('wm_upd_other') -> 'result' ->> 'updated_at')::timestamptz,
    'self_signal_kept', pg_temp.rg_get('wm_upd_signal') -> 'result' -> 'claim_signal_at'
                        = pg_temp.rg_get('wm_mark_before_upd') -> 'claim_signal_at'),
  '{"other_raised": false, "other_counter": 1, "other_updated_moved": true, "other_signal_kept": true, "self_raised": false, "self_updated_moved": true, "self_signal_kept": true}'::jsonb,
  'RG-162 C1-1 (i): on the unresolved wm_mark row a direct owner UPDATE of another column (auto_poll_count + 1) applies but keeps claim_signal_at, and a direct owner UPDATE of claim_signal_at itself (+1 day) is applied with the old signal kept by the guard');
insert into _zc_r select 'wm_res_before_upd', pg_temp.rg_wm_attempt('wm_resolve');
insert into _zc_r select 'wm_upd_resolved', pg_temp.rg_try(format(
  'update app.card_provider_attempts x set claim_signal_at = clock_timestamp() + interval %L where x.id = %L returning to_jsonb(x)',
  '1 day', pg_temp.rg_wm_id('wm_claim_resolve')));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_i');
reset role;
select pg_temp.rg_wm_advance('wmf_i');
select is(
  jsonb_build_object('answer', pg_temp.rg_get('wm_upd_resolved'),
                     'row_unchanged', pg_temp.rg_wm_attempt('wm_resolve') = pg_temp.rg_get('wm_res_before_upd'),
                     'feed', pg_temp.rg_wm_rows('wmf_i')),
  '{"answer": {"raised": false, "result": null}, "row_unchanged": true, "feed": []}'::jsonb,
  'RG-163 C1-1 (i): on the resolved wm_resolve row a direct owner UPDATE of claim_signal_at is a silent no-op (no row returned, the row byte-identical); after the direct owner UPDATEs the feed still returns no row');

-- (e) An unrelated order throughout.
set local role authenticated;
select pg_temp.rg_wm_target('wm_plain_end', array['wm_plain']);
reset role;
select is(
  jsonb_build_object(
    'start', pg_temp.rg_wm_rows('wm_plain_start'), 'end', pg_temp.rg_wm_rows('wm_plain_end'),
    'same_sync_at', pg_temp.rg_wm_sync('wm_plain_end', 'wm_plain') = pg_temp.rg_wm_sync('wm_plain_start', 'wm_plain'),
    'sync_is_order_updated_at', pg_temp.rg_wm_sync('wm_plain_end', 'wm_plain')
                                = (select o.updated_at from public.orders o where o.id = pg_temp.zc_id('order-wm_plain')),
    'in_later_feeds', (select count(*) from _zc_r z cross join lateral jsonb_array_elements(z.r -> 'orders') o
                        where z.label like 'wmf\_%' and z.label <> 'wmf_base'
                          and o ->> 'order_id' = pg_temp.zc_id('order-wm_plain')::text)),
  jsonb_build_object('start', jsonb_build_array(pg_temp.rg_wm_row('wm_plain')),
                     'end', jsonb_build_array(pg_temp.rg_wm_row('wm_plain')),
                     'same_sync_at', true, 'sync_is_order_updated_at', true, 'in_later_feeds', 0),
  'RG-164 C1-1 (e): the unrelated order wm_plain keeps its sync_at (its own updated_at) from the start of the section to its end and is never re-delivered by any later feed');

-- (h) Pagination: two orders sharing one sync_at page deterministically by id with p_limit 1.
create function pg_temp.rg_wm_page(p_label text, p_dir text, p_from_label text default null) returns void
language sql volatile as $$
  insert into _zc_r select p_label, public.pos_order_snapshots(
    p_pin_session_id => pg_temp.zc_id('pin-10'), p_device_id => pg_temp.zc_id('device-5'),
    p_since_at => case when p_dir = 'asc' then coalesce((select (z.r -> 'next_cursor' ->> 'at')::timestamptz
                                                           from _zc_r z where z.label = p_from_label), '-infinity') end,
    p_since_id => case when p_dir = 'asc' then coalesce((select (z.r -> 'next_cursor' ->> 'id')::uuid
                                                           from _zc_r z where z.label = p_from_label),
                                                         '00000000-0000-0000-0000-000000000000') end,
    p_before_at => case when p_dir = 'desc' then (select (z.r -> 'next_cursor' ->> 'at')::timestamptz
                                                    from _zc_r z where z.label = p_from_label) end,
    p_before_id => case when p_dir = 'desc' then (select (z.r -> 'next_cursor' ->> 'id')::uuid
                                                    from _zc_r z where z.label = p_from_label) end,
    p_limit => 1) $$;
create function pg_temp.rg_wm_page_ids(p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('ids', coalesce((select jsonb_agg(o ->> 'order_id') from _zc_r z
                                              cross join lateral jsonb_array_elements(z.r -> 'orders') o
                                             where z.label = p_label), '[]'::jsonb),
                            'has_more', (select z.r -> 'has_more' from _zc_r z where z.label = p_label),
                            'next_cursor', (select z.r -> 'next_cursor' from _zc_r z where z.label = p_label)) $$;
set local role authenticated;
insert into _zc_r select 'wm_pg_all', public.pos_order_snapshots(pg_temp.zc_id('pin-10'), pg_temp.zc_id('device-5'));
select pg_temp.rg_wm_page('wm_pg_d1', 'desc');
select pg_temp.rg_wm_page('wm_pg_d2', 'desc', 'wm_pg_d1');
select pg_temp.rg_wm_page('wm_pg_d3', 'desc', 'wm_pg_d2');
select pg_temp.rg_wm_page('wm_pg_a1', 'asc');
select pg_temp.rg_wm_page('wm_pg_a2', 'asc', 'wm_pg_a1');
select pg_temp.rg_wm_page('wm_pg_a3', 'asc', 'wm_pg_a2');
reset role;
create temp table _rg_wm_pg as
select (select o.updated_at from public.orders o where o.id = pg_temp.zc_id('order-wm_page_a')) as shared_at,
       least(pg_temp.zc_id('order-wm_page_a'), pg_temp.zc_id('order-wm_page_b')) as lo,
       greatest(pg_temp.zc_id('order-wm_page_a'), pg_temp.zc_id('order-wm_page_b')) as hi;
select is(
  (select jsonb_build_object('rows', jsonb_array_length(pg_temp.rg_get('wm_pg_all') -> 'orders'),
                             'distinct_sync_at', (select count(distinct (o ->> 'sync_at')::timestamptz)
                                                    from jsonb_array_elements(pg_temp.rg_get('wm_pg_all') -> 'orders') o),
                             'shared_is_order_updated_at', (select bool_and((o ->> 'sync_at')::timestamptz = g.shared_at)
                                                              from jsonb_array_elements(pg_temp.rg_get('wm_pg_all') -> 'orders') o),
                             'both_orders', (select bool_and(o ->> 'order_id' in (g.lo::text, g.hi::text))
                                               from jsonb_array_elements(pg_temp.rg_get('wm_pg_all') -> 'orders') o))
     from _rg_wm_pg g),
  '{"rows": 2, "distinct_sync_at": 1, "shared_is_order_updated_at": true, "both_orders": true}'::jsonb,
  'RG-165 C1-1 (h) setup: the sibling branch holds exactly the two orders wm_page_a / wm_page_b, sharing one sync_at (their own updated_at)');
select is(
  (select jsonb_build_array(pg_temp.rg_wm_page_ids('wm_pg_d1'), pg_temp.rg_wm_page_ids('wm_pg_d2'), pg_temp.rg_wm_page_ids('wm_pg_d3'))
     from _rg_wm_pg g),
  (select jsonb_build_array(
            jsonb_build_object('ids', jsonb_build_array(g.hi::text), 'has_more', true,
                               'next_cursor', jsonb_build_object('at', g.shared_at, 'id', g.hi)),
            jsonb_build_object('ids', jsonb_build_array(g.lo::text), 'has_more', true,
                               'next_cursor', jsonb_build_object('at', g.shared_at, 'id', g.lo)),
            jsonb_build_object('ids', '[]'::jsonb, 'has_more', false, 'next_cursor', null))
     from _rg_wm_pg g),
  'RG-166 C1-1 (h): the window (descending) with p_limit 1 pages the two tied orders by id - the higher id, then the lower, then an empty last page (has_more true, true, false; each next_cursor = the shared sync_at and that page''s id): no duplicate, no skip');
select is(
  (select jsonb_build_array(pg_temp.rg_wm_page_ids('wm_pg_a1'), pg_temp.rg_wm_page_ids('wm_pg_a2'), pg_temp.rg_wm_page_ids('wm_pg_a3'))
     from _rg_wm_pg g),
  (select jsonb_build_array(
            jsonb_build_object('ids', jsonb_build_array(g.lo::text), 'has_more', true,
                               'next_cursor', jsonb_build_object('at', g.shared_at, 'id', g.lo)),
            jsonb_build_object('ids', jsonb_build_array(g.hi::text), 'has_more', true,
                               'next_cursor', jsonb_build_object('at', g.shared_at, 'id', g.hi)),
            jsonb_build_object('ids', '[]'::jsonb, 'has_more', false, 'next_cursor', null))
     from _rg_wm_pg g),
  'RG-167 C1-1 (h): the incremental feed (ascending from the start) with p_limit 1 pages the same two tied orders by id - the lower id, then the higher, then an empty last page: no duplicate, no skip');

-- No write to orders: claims, polls, stamps, marks, frees, resolutions and declines touch only the private ledger.
select is(
  (select jsonb_build_object('orders', count(*),
                             'unchanged', bool_and(o.ctid::text = b.tup and o.revision = b.revision
                                                   and o.updated_at = b.updated_at))
     from _rg_wm_orders b join public.orders o on o.id = b.id),
  '{"orders": 4, "unchanged": true}'::jsonb,
  'RG-168 C1-1: no write to orders - the rows of wm_main, wm_free, wm_resolve and wm_mark keep their tuple (ctid), revision and updated_at from before their claims to the end of the section (claim, poll, lookup, marks, refused push, decline, free and resolution write only the private ledger)');

-- (i, C1 delta review) The D-054 Resume guard's own columns - recording_resume_count and its two histories - written
-- directly on the unresolved wm_mark row: the signal stays put and the incremental feed delivers nothing.
insert into _zc_r select 'wm_mark_before_resume', pg_temp.rg_wm_attempt('wm_mark');
insert into _zc_r select 'wm_upd_resume', pg_temp.rg_try(format(
  'update app.card_provider_attempts x set recording_resume_count = x.recording_resume_count + 1,
          recording_refusal_history = x.recording_refusal_history || jsonb_build_array(jsonb_build_object(%L, %L)),
          recording_resume_history = x.recording_resume_history || jsonb_build_array(jsonb_build_object(%L, 0))
    where x.id = %L returning to_jsonb(x)',
  'refusal_code', 'tender_mismatch', 'resume_count', pg_temp.rg_wm_id('wm_claim_mark')));
set local role authenticated;
select pg_temp.rg_wm_feed('wmf_j');
reset role;
select pg_temp.rg_wm_advance('wmf_j');
select is(
  jsonb_build_object(
    'raised', pg_temp.rg_get('wm_upd_resume') -> 'raised',
    'resume_count_delta', (pg_temp.rg_get('wm_upd_resume') -> 'result' ->> 'recording_resume_count')::int
                          - (pg_temp.rg_get('wm_mark_before_resume') ->> 'recording_resume_count')::int,
    'signal_present', (pg_temp.rg_get('wm_mark_before_resume') ->> 'claim_signal_at') is not null,
    'signal_kept', pg_temp.rg_get('wm_upd_resume') -> 'result' -> 'claim_signal_at'
                   = pg_temp.rg_get('wm_mark_before_resume') -> 'claim_signal_at',
    'feed', pg_temp.rg_wm_rows('wmf_j')),
  '{"raised": false, "resume_count_delta": 1, "signal_present": true, "signal_kept": true, "feed": []}'::jsonb,
  'RG-169 C1-1 (i; delta review): a direct owner UPDATE of the D-054 Resume guard''s own columns (recording_resume_count + 1 and one entry in each history) on the unresolved wm_mark row applies but keeps claim_signal_at, and the incremental feed from the cursor returns no row');

-- ===========================================================================
-- (j) Correction C2 review fix (CONTRACT-01): app.sync_push has one more caller than public.sync_push - the
-- web-order acceptance (app.decide_pos_web_order, reached by public.pos_accept_web_order), which submits the
-- accepted order through it. Change 7 therefore also refuses an acceptance made in an ACTIVE platform support
-- session: decide's handler re-raises the 42501, so the accept RPC raises the shared refusal (no order, the
-- request stays pending), while the same staff inputs under the native transport JWT accept as before. A
-- self-contained synthetic web-order setup (its own organization; the shape of the platform web-order tests).
-- ===========================================================================
create function pg_temp.rgw_id(label text) returns uuid language sql immutable as $$
  select md5('zc001d-rg-c2-web-synthetic-' || label)::uuid $$;
create function pg_temp.rgw_client(n integer) returns uuid language sql immutable as $$
  select ('3c200000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
insert into organizations (id, name, slug, default_currency, status)
values (pg_temp.rgw_id('org'), 'ZC001D RG web org', 'zc001d-rg-web-org', 'ILS', 'active');
insert into restaurants (id, organization_id, name, timezone)
values (pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('org'), 'ZC001D RG web restaurant', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone, kitchen_workflow_mode)
values (pg_temp.rgw_id('branch'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), 'ZC001D RG web branch', 'UTC',
        'printer_only');
insert into menu_categories (id, organization_id, restaurant_id, name)
values (pg_temp.rgw_id('category'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), 'ZC001D RG web food');
insert into menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code)
values (pg_temp.rgw_id('item'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('category'),
        'ZC001D RG web product', 1000, 'ILS');
insert into restaurant_storefront_profiles (restaurant_id, organization_id, storefront_branch_id, slug, display_name,
                                            pickup_enabled, opening_hours, is_published)
values (pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('org'), pg_temp.rgw_id('branch'), 'zc001d-rg-web',
        'ZC001D RG web', true,
        jsonb_build_object('weekly', (select jsonb_agg(jsonb_build_object('dow', d, 'open', o, 'close', c))
                                        from generate_series(0, 6) d
                                        cross join (values ('00:00', '12:00'), ('11:00', '00:00')) w(o, c)),
                           'exceptions', '[]'::jsonb), true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type)
values (pg_temp.rgw_id('device'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'), 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
values (pg_temp.rgw_id('pairing'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'),
        pg_temp.rgw_id('device'), 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                             session_token_ref, expires_at)
values (pg_temp.rgw_id('session'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'),
        pg_temp.rgw_id('device'), pg_temp.rgw_id('pairing'), app.hash_provisioning_secret('zc001d-rg-web-token'),
        now() + interval '30 days');
insert into app_users (id, email) values (pg_temp.rgw_id('staff'), 'zc001d-rg-web-staff@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role)
values (pg_temp.rgw_id('membership'), pg_temp.rgw_id('staff'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'),
        pg_temp.rgw_id('branch'), 'cashier');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name)
values (pg_temp.rgw_id('employee'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'),
        pg_temp.rgw_id('staff'), pg_temp.rgw_id('membership'), 'ZC001D RG web cashier');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id,
                          resolved_membership_id, expires_at)
values (pg_temp.rgw_id('pin'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'),
        pg_temp.rgw_id('session'), pg_temp.rgw_id('employee'), pg_temp.rgw_id('membership'), now() + interval '6 hours');
insert into shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id,
                    resolved_membership_id, local_operation_id, status)
values (pg_temp.rgw_id('shift'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'),
        pg_temp.rgw_id('device'), pg_temp.rgw_id('employee'), pg_temp.rgw_id('membership'), 'zc001d-rg-web-open', 'open');
insert into printer_devices (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role,
                             paper_width, is_enabled)
values (pg_temp.rgw_id('printer'), pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'),
        'ZC001D RG web kitchen', 'network', 'kitchen', '80mm', true);
insert into kitchen_printer_readiness_reports (organization_id, restaurant_id, branch_id, device_id, capability, app_build,
    printer_purpose, transport_kind, paper_width, printer_fingerprint, secure_spool_available, unresolved_local_jobs,
    mode_revision, printer_assignment_id, expires_at)
values (pg_temp.rgw_id('org'), pg_temp.rgw_id('restaurant'), pg_temp.rgw_id('branch'), pg_temp.rgw_id('device'),
        'kitchen_printer_only_v1', 'zc001d-rg-web', 'kitchen_ticket', 'network', '80mm', repeat('a', 64), true, 0, 1,
        pg_temp.rgw_id('printer'), clock_timestamp() + interval '10 minutes');
-- The support-capable person: an auth user linked to an app user with an active platform-admin grant and an
-- ACTIVE (token-exchanged, unexpired) support session.
insert into auth.users (id, email) values (pg_temp.rgw_id('sup-auth'), 'zc001d-rg-web-support@example.test');
insert into app_users (id, email, auth_user_id)
values (pg_temp.rgw_id('sup-user'), 'zc001d-rg-web-support@example.test', pg_temp.rgw_id('sup-auth'));
insert into public.platform_admin_grants (app_user_id, status, granted_by)
values (pg_temp.rgw_id('sup-user'), 'active', pg_temp.zc_owner());
insert into public.platform_support_sessions (id, platform_admin_app_user_id, target_organization_id, reason, status,
                                              expires_at, token_hash, token_consumed_at)
values (pg_temp.rgw_id('sup-session'), pg_temp.rgw_id('sup-user'), pg_temp.rgw_id('org'), 'ZC001D synthetic support visit',
        'active', now() + interval '15 minutes', 'zc001d-rg-web-handoff-hash', now());
create function pg_temp.rgw_request(n integer) returns uuid language sql stable security definer set search_path = '' as $$
  select r.id from public.web_order_requests r where r.client_request_id = pg_temp.rgw_client(n) $$;
-- One acceptance through the public POS entrypoint (call under SET LOCAL ROLE authenticated); a raise is caught
-- and answered as its SQLSTATE and message.
create function pg_temp.rgw_accept(n integer) returns text language plpgsql as $$
declare v_state text; v_msg text; r jsonb;
begin
  r := public.pos_accept_web_order(pg_temp.rgw_id('pin'), pg_temp.rgw_id('device'), 'zc001d-rg-web-token',
                                   pg_temp.rgw_request(n), pg_temp.rgw_client(1000 + n));
  return 'RETURNED ' || coalesce(r ->> 'ok', '') || ' ' || coalesce(r ->> 'error', r ->> 'status', '');
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return 'RAISED ' || v_state || ' | ' || v_msg;
end $$;
create temp table _rgw_r (label text primary key, r text);
grant all on _rgw_r to authenticated, service_role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_transport;
select app.set_pos_order_alerts(true, 'ZC001D synthetic notification gate', 'zc001d-rg-web') is not null as alerts_gate;
set local role service_role;
select (public.submit_web_order_platform_request('zc001d-rg-web', pg_temp.rgw_client(n), repeat('a', 64),
          jsonb_build_object('order_type', 'takeaway',
            'customer', jsonb_build_object('name', 'Synthetic Guest', 'phone', '+9725200' || lpad(n::text, 5, '0')),
            'notes', 'Synthetic note',
            'items', jsonb_build_array(jsonb_build_object('menu_item_id', pg_temp.rgw_id('item'), 'quantity', 2,
                                                          'notes', 'Synthetic item note', 'modifiers', '[]'::jsonb))))
        ->> 'ok') as submitted
  from generate_series(1, 2) n;
reset role;
select set_config('request.jwt.claim.sub', pg_temp.rgw_id('sup-auth')::text, true) is not null as jwt_support;
insert into _rgw_r values ('support_session_resolves', (app.current_support_session() is not null)::text);
set local role authenticated;
insert into _rgw_r values ('support_accept', pg_temp.rgw_accept(1));
reset role;
insert into _rgw_r values ('after_support', jsonb_build_object(
  'orders', (select count(*) from public.orders o where o.organization_id = pg_temp.rgw_id('org')),
  'request', (select r.status from public.web_order_requests r where r.id = pg_temp.rgw_request(1)))::text);
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_transport;
set local role authenticated;
insert into _rgw_r values ('transport_accept', pg_temp.rgw_accept(2));
reset role;
insert into _rgw_r values ('after_transport', jsonb_build_object(
  'orders', (select count(*) from public.orders o where o.organization_id = pg_temp.rgw_id('org')),
  'request', (select r.status from public.web_order_requests r where r.id = pg_temp.rgw_request(2)))::text);
select is(
  jsonb_build_object('support_session_resolves', (select r from _rgw_r where label = 'support_session_resolves'),
                     'answer', (select r from _rgw_r where label = 'support_accept'),
                     'after', (select r from _rgw_r where label = 'after_support')::jsonb),
  jsonb_build_object('support_session_resolves', 'true',
                     'answer', 'RAISED 42501 | sync_push: permission denied (active support session)',
                     'after', '{"orders": 0, "request": "pending"}'::jsonb),
  'RG-170 C2 (review fix CONTRACT-01): public.pos_accept_web_order called with valid cashier PIN, device and token by a JWT whose caller holds an ACTIVE platform support session raises the shared app.sync_push refusal 42501 ''sync_push: permission denied (active support session)'' (decide_pos_web_order re-raises it; not its typed web-order answer): no order is created and the request stays pending');
select is(
  jsonb_build_object('answer', (select r from _rgw_r where label = 'transport_accept'),
                     'after', (select r from _rgw_r where label = 'after_transport')::jsonb),
  jsonb_build_object('answer', 'RETURNED true accepted', 'after', '{"orders": 1, "request": "accepted"}'::jsonb),
  'RG-171 C2 (review fix CONTRACT-01; control): the same staff inputs under the native transport JWT (no app user, no support session) accept the second request exactly as before - one order, the request accepted');
select is(
  (select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text collate "C")
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and p.prosrc ~ 'app\.sync_push\s*\('
      and p.oid <> 'app.sync_push(uuid,uuid,jsonb)'::regprocedure),
  'app.decide_pos_web_order(uuid,uuid,text,uuid,uuid,text,text), sync_push(uuid,uuid,jsonb)',
  'RG-172 C2 (review fix CONTRACT-01): app.sync_push has exactly two callers - the public.sync_push wrapper and app.decide_pos_web_order (the web-order acceptance) - so change 7 reaches the POS push and the web-order accept path only');

-- (j, continued; C2 re-review fix FIXDOCS-01) Only a fresh acceptance that reaches app.sync_push raises: a
-- same-action replay of the request accepted in RG-171, made in the ACTIVE support session, keeps its typed answer.
create function pg_temp.rgw_accept_j(n integer) returns jsonb language plpgsql as $$
declare v_state text; v_msg text;
begin
  return public.pos_accept_web_order(pg_temp.rgw_id('pin'), pg_temp.rgw_id('device'), 'zc001d-rg-web-token',
                                     pg_temp.rgw_request(n), pg_temp.rgw_client(1000 + n));
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return jsonb_build_object('raised', v_state, 'message', v_msg);
end $$;
select set_config('request.jwt.claim.sub', pg_temp.rgw_id('sup-auth')::text, true) is not null as jwt_support;
set local role authenticated;
insert into _rgw_r values ('support_replay', pg_temp.rgw_accept_j(2)::text);
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_transport;
select is(
  (select jsonb_build_object('ok', j ->> 'ok', 'status', j ->> 'status', 'replayed', j ->> 'replayed',
                             'canonical_order_id_present', (j ->> 'canonical_order_id') is not null,
                             'orders', (select count(*) from public.orders o where o.organization_id = pg_temp.rgw_id('org')))
     from (select r::jsonb as j from _rgw_r where label = 'support_replay') x),
  '{"ok": "true", "status": "accepted", "replayed": "true", "canonical_order_id_present": true, "orders": 1}'::jsonb,
  'RG-173 C2 (re-review fix FIXDOCS-01): a same-action replay of the request accepted in RG-171, made by the caller in the ACTIVE support session, keeps the typed web-order answer (ok, accepted, replayed, its canonical order id; still one order) - only a fresh acceptance that reaches app.sync_push raises the shared 42501');

-- ===========================================================================
-- (k) Integration W3 (scope S7(a), after #366): the acceptance-ETA entry public.pos_accept_web_order_with_eta
-- reaches app.sync_push through app.pos_accept_web_order - for a platform request directly, for a legacy
-- (unenrolled) request through app.pos_accept_web_order_legacy_353 - and app.decide_pos_web_order. Change 7
-- therefore also refuses a fresh ETA acceptance made in an ACTIVE platform support session: decide's handler and
-- the ETA function's when-others handler both re-raise the 42501, so the whole call rolls back - no order, no ETA
-- sidecar row, no decision, ledger row, print attempt or lease - the request row stays exactly as it was (pending)
-- and the decision id stays unused. The same inputs under the native transport JWT then accept through the same
-- path and write exactly one sidecar row, bound to the winning decision. Both paths are read from the call stack
-- itself: the refusal's error context and, for the control, the context captured by a probe trigger on the order
-- insert (rollback-only, like the whole lane). Platform request 3, legacy request 4.
-- ===========================================================================
create function pg_temp.rgw_payload(n integer) returns jsonb language sql immutable as $$
  select jsonb_build_object('order_type', 'takeaway',
    'customer', jsonb_build_object('name', 'Synthetic Guest', 'phone', '+9725200' || lpad(n::text, 5, '0')),
    'notes', 'Synthetic note',
    'items', jsonb_build_array(jsonb_build_object('menu_item_id', pg_temp.rgw_id('item'), 'quantity', 2,
                                                  'notes', 'Synthetic item note', 'modifiers', '[]'::jsonb))) $$;
create function pg_temp.rgw_eta(n integer, minutes integer) returns jsonb language sql volatile as $$
  select public.pos_accept_web_order_with_eta(pg_temp.rgw_id('pin'), pg_temp.rgw_id('device'), 'zc001d-rg-web-token',
                                              pg_temp.rgw_request(n), pg_temp.rgw_client(1000 + n), minutes) $$;
-- The app./public. PL/pgSQL frames and public SQL accept wrappers of a call-stack context, innermost first, from
-- app.sync_push outward (NULL when app.sync_push is not on the stack). The helpers build that frame name by
-- concatenation, so RG-172's catalog scan for callers never counts them, wherever this section sits.
create function pg_temp.rgw_frames(ctx text) returns jsonb language sql immutable as $$
  select to_jsonb(f[array_position(f, 'app.sync_push' || '(uuid,uuid,jsonb)'):])
    from (select array_agg(coalesce(m[1], 'public.' || m[2]) order by o) f
            from regexp_matches(ctx, 'PL/pgSQL function ((?:app|public)[.][a-z0-9_]+[(][^)]*[)])'
                                     || '|SQL function "(pos_accept_web_order[a-z0-9_]*)"', 'g')
                 with ordinality t(m, o)) x $$;
-- The expected path from app.sync_push outward to the public ETA wrapper.
create function pg_temp.rgw_eta_path(legacy boolean) returns jsonb language sql immutable as $$
  select to_jsonb(array['app.sync_push' || '(uuid,uuid,jsonb)',
                        'app.decide_pos_web_order(uuid,uuid,text,uuid,uuid,text,text)']
                  || case when legacy then array['app.pos_accept_web_order_legacy_353(uuid,uuid,text,uuid,uuid)']
                          else array[]::text[] end
                  || array['app.pos_accept_web_order(uuid,uuid,text,uuid,uuid)',
                           'app.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer)',
                           'public.pos_accept_web_order_with_eta']) $$;
-- One ETA acceptance (call under SET LOCAL ROLE authenticated): a return is answered as {returned} reduced to
-- UUID-free facts (the decision id is compared, never printed); a raise as its SQLSTATE, message, whether the
-- first context frame is a RAISE in app.sync_push, and the path from app.sync_push.
create function pg_temp.rgw_eta_try(n integer, minutes integer) returns jsonb language plpgsql as $$
declare v_state text; v_msg text; v_ctx text; v_r jsonb;
begin
  v_r := pg_temp.rgw_eta(n, minutes);
  return jsonb_build_object('returned', jsonb_build_object('ok', v_r -> 'ok', 'status', v_r -> 'status',
    'error', v_r -> 'error', 'replayed', v_r -> 'replayed', 'print_blocker', v_r -> 'print_blocker',
    'same_decision_id', (v_r ->> 'decision_id') = pg_temp.rgw_client(1000 + n)::text,
    'canonical_order_id_present', v_r ? 'canonical_order_id'));
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text, v_ctx = pg_exception_context;
  return jsonb_build_object('raised', v_state, 'message', v_msg,
    'at_sync_push_raise', split_part(v_ctx, chr(10), 1)
                            ~ '^PL/pgSQL function app[.]sync_push[(]uuid,uuid,jsonb[)] line [0-9]+ at RAISE$',
    'path', pg_temp.rgw_frames(v_ctx));
end $$;
-- Request-scoped facts (the request row's summary and digest, its decisions, uses of its decision id, ETA sidecar,
-- print attempt, platform lease and sync-ledger rows) and the organization's order, item, audit and dispatch counts.
create function pg_temp.rgw_eta_facts(n integer) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'request', (select jsonb_build_object('status', w.status, 'mapped', w.canonical_order_id is not null,
                                          'decided', w.decided_at is not null, 'row_md5', md5(to_jsonb(w)::text))
                  from public.web_order_requests w where w.id = pg_temp.rgw_request(n)),
    'decisions', (select count(*) from public.web_order_decisions d where d.request_id = pg_temp.rgw_request(n)),
    'decision_id_uses', (select count(*) from public.web_order_decisions d
                          where d.decision_id = pg_temp.rgw_client(1000 + n)),
    'eta', (select count(*) from app.web_order_acceptance_estimates e where e.request_id = pg_temp.rgw_request(n)),
    'print_attempts', (select count(*) from public.web_order_print_attempts p where p.request_id = pg_temp.rgw_request(n)),
    'leases', (select count(*) from app.online_order_print_leases l where l.request_id = pg_temp.rgw_request(n)),
    'ledger', (select count(*) from public.sync_operations s
                where s.local_operation_id = 'web-accept:' || pg_temp.rgw_request(n)::text || ':'
                                             || pg_temp.rgw_client(1000 + n)::text),
    'org', jsonb_build_object(
      'orders', (select count(*) from public.orders o where o.organization_id = pg_temp.rgw_id('org')),
      'order_items', (select count(*) from public.order_items i where i.organization_id = pg_temp.rgw_id('org')),
      'audit', (select count(*) from public.audit_events a where a.organization_id = pg_temp.rgw_id('org')),
      'dispatches', (select count(*) from public.kitchen_print_dispatches k
                      where k.organization_id = pg_temp.rgw_id('org')))) $$;
-- The request's ETA sidecar row checked against its decision and request.
create function pg_temp.rgw_eta_sidecar(n integer, minutes integer) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'minutes', e.preparation_minutes, 'timezone', e.timezone,
    'scope', e.organization_id = pg_temp.rgw_id('org') and e.restaurant_id = pg_temp.rgw_id('restaurant')
             and e.branch_id = pg_temp.rgw_id('branch'),
    'winner', d.decision = 'accepted' and e.decision_id = pg_temp.rgw_client(1000 + n)
              and e.decision_id = d.decision_id and d.canonical_order_id = w.canonical_order_id,
    'accepted_at', e.accepted_at = d.decided_at and e.accepted_at = w.decided_at,
    'ready_at', e.ready_at = e.accepted_at + minutes * interval '1 minute',
    'fingerprint', e.intent_fingerprint = app.web_order_acceptance_intent_fingerprint(e.organization_id,
                     e.restaurant_id, e.branch_id, e.request_id, e.decision_id, e.preparation_minutes))
    from app.web_order_acceptance_estimates e
    join public.web_order_decisions d on d.request_id = e.request_id
    join public.web_order_requests w on w.id = e.request_id
   where e.request_id = pg_temp.rgw_request(n) $$;
-- The control's call stack, captured where the accepted order is inserted.
create temp table _rgw_stack (ctx text);
grant all on _rgw_stack to authenticated, service_role;
create function pg_temp.rgw_stack_probe() returns trigger language plpgsql as $$
declare v_ctx text;
begin
  get diagnostics v_ctx = pg_context;
  insert into pg_temp._rgw_stack values (v_ctx);
  return new;
end $$;
create trigger zc001d_rgw_stack_probe before insert on public.orders
  for each row execute function pg_temp.rgw_stack_probe();
set local role service_role;
insert into _rgw_r values ('eta_submitted_3',
  public.submit_web_order_platform_request('zc001d-rg-web', pg_temp.rgw_client(3), repeat('a', 64),
                                           pg_temp.rgw_payload(3)) ->> 'ok');
insert into _rgw_r values ('eta_submitted_4',
  public.submit_web_order_request('zc001d-rg-web', pg_temp.rgw_client(4), repeat('a', 64),
                                  pg_temp.rgw_payload(4)) ->> 'ok');
reset role;

-- (k) platform request 3: refusal in the ACTIVE support session, then the transport-JWT control.
insert into _rgw_r values ('eta_before_3', pg_temp.rgw_eta_facts(3)::text);
select set_config('request.jwt.claim.sub', pg_temp.rgw_id('sup-auth')::text, true) is not null as jwt_support;
set local role authenticated;
insert into _rgw_r values ('eta_support_3', pg_temp.rgw_eta_try(3, 15)::text);
reset role;
select is(
  jsonb_build_object(
    'submitted', (select r from _rgw_r where label = 'eta_submitted_3'),
    'enrolled', exists(select 1 from app.online_order_live_requests l where l.request_id = pg_temp.rgw_request(3)),
    'call', (select r::jsonb from _rgw_r where label = 'eta_support_3'),
    'unchanged', pg_temp.rgw_eta_facts(3) = (select r::jsonb from _rgw_r where label = 'eta_before_3'),
    'after', (pg_temp.rgw_eta_facts(3) #- '{request,row_md5}') - 'org'),
  jsonb_build_object(
    'submitted', 'true',
    'enrolled', true,
    'call', jsonb_build_object('raised', '42501', 'message', 'sync_push: permission denied (active support session)',
                               'at_sync_push_raise', true, 'path', pg_temp.rgw_eta_path(false)),
    'unchanged', true,
    'after', '{"request": {"status": "pending", "mapped": false, "decided": false}, "decisions": 0,
               "decision_id_uses": 0, "eta": 0, "print_attempts": 0, "leases": 0, "ledger": 0}'::jsonb),
  'RG-174 W3 S7(a) (acceptance-ETA entry, platform request): public.pos_accept_web_order_with_eta (15 minutes) with valid cashier PIN, device and token by a JWT whose caller holds an ACTIVE platform support session raises the shared refusal 42501 ''sync_push: permission denied (active support session)'' at the RAISE in app.sync_push, on the path app.sync_push <- app.decide_pos_web_order <- app.pos_accept_web_order <- app.pos_accept_web_order_with_eta <- the public ETA wrapper (read from the error context); the whole call rolls back: the request row is unchanged (pending, unmapped, undecided) and there is no decision, no use of the decision id, no ETA sidecar, print attempt, lease or sync-ledger row, and no new order, item, audit or dispatch row in the organization');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_transport;
delete from _rgw_stack;
set local role authenticated;
insert into _rgw_r values ('eta_transport_3', pg_temp.rgw_eta_try(3, 15)::text);
reset role;
select is(
  (select jsonb_build_object(
     'answer', jsonb_build_object('raised', t ? 'raised', 'ok', t #>> '{returned,ok}', 'status', t #>> '{returned,status}',
                                  'replayed', t #>> '{returned,replayed}',
                                  'same_decision_id', t #> '{returned,same_decision_id}',
                                  'canonical_order_id_present', t #> '{returned,canonical_order_id_present}',
                                  'print_blocker', t #> '{returned,print_blocker}'),
     'path', (select jsonb_agg(pg_temp.rgw_frames(s.ctx)) from _rgw_stack s),
     'after', (f #- '{request,row_md5}') - 'org',
     'new_orders', (f #>> '{org,orders}')::int - (b #>> '{org,orders}')::int,
     'new_order_items', (f #>> '{org,order_items}')::int - (b #>> '{org,order_items}')::int,
     'sidecar', pg_temp.rgw_eta_sidecar(3, 15))
     from (select (select r::jsonb from _rgw_r where label = 'eta_transport_3') t, pg_temp.rgw_eta_facts(3) f,
                  (select r::jsonb from _rgw_r where label = 'eta_before_3') b) x),
  jsonb_build_object(
    'answer', jsonb_build_object('raised', false, 'ok', 'true', 'status', 'accepted', 'replayed', 'false',
                                 'same_decision_id', true, 'canonical_order_id_present', true,
                                 'print_blocker', null),
    'path', jsonb_build_array(pg_temp.rgw_eta_path(false)),
    'after', '{"request": {"status": "accepted", "mapped": true, "decided": true}, "decisions": 1,
               "decision_id_uses": 1, "eta": 1, "print_attempts": 1, "leases": 1, "ledger": 1}'::jsonb,
    'new_orders', 1, 'new_order_items', 1,
    'sidecar', '{"minutes": 15, "timezone": "UTC", "scope": true, "winner": true, "accepted_at": true,
                 "ready_at": true, "fingerprint": true}'::jsonb),
  'RG-175 W3 S7(a) (acceptance-ETA entry, platform request; control): the same request, decision id and 15 minutes under the native transport JWT (no app user, no support session) accept through the same path, captured at the order insert - ok, accepted, not replayed, the same decision id, no print blocker; one decision, ledger row, print attempt and platform lease; one new order with its one item; and exactly one ETA sidecar row in the request''s scope, bound to the winning decision (accepted_at = decided_at, ready_at = accepted_at + 15 minutes, UTC, versioned fingerprint) - so the refused attempt had consumed nothing');

-- (k) legacy request 4: the same pair through app.pos_accept_web_order_legacy_353.
insert into _rgw_r values ('eta_before_4', pg_temp.rgw_eta_facts(4)::text);
select set_config('request.jwt.claim.sub', pg_temp.rgw_id('sup-auth')::text, true) is not null as jwt_support;
set local role authenticated;
insert into _rgw_r values ('eta_support_4', pg_temp.rgw_eta_try(4, 25)::text);
reset role;
select is(
  jsonb_build_object(
    'submitted', (select r from _rgw_r where label = 'eta_submitted_4'),
    'enrolled', exists(select 1 from app.online_order_live_requests l where l.request_id = pg_temp.rgw_request(4)),
    'call', (select r::jsonb from _rgw_r where label = 'eta_support_4'),
    'unchanged', pg_temp.rgw_eta_facts(4) = (select r::jsonb from _rgw_r where label = 'eta_before_4'),
    'after', (pg_temp.rgw_eta_facts(4) #- '{request,row_md5}') - 'org'),
  jsonb_build_object(
    'submitted', 'true',
    'enrolled', false,
    'call', jsonb_build_object('raised', '42501', 'message', 'sync_push: permission denied (active support session)',
                               'at_sync_push_raise', true, 'path', pg_temp.rgw_eta_path(true)),
    'unchanged', true,
    'after', '{"request": {"status": "pending", "mapped": false, "decided": false}, "decisions": 0,
               "decision_id_uses": 0, "eta": 0, "print_attempts": 0, "leases": 0, "ledger": 0}'::jsonb),
  'RG-176 W3 S7(a) (acceptance-ETA entry, legacy request): for a legacy (unenrolled) request the same ETA call (25 minutes) in the ACTIVE support session raises the same 42501 at the RAISE in app.sync_push, on the path app.sync_push <- app.decide_pos_web_order <- app.pos_accept_web_order_legacy_353 <- app.pos_accept_web_order <- app.pos_accept_web_order_with_eta <- the public ETA wrapper; the whole call rolls back: the request row is unchanged (pending) and there is no decision, no use of the decision id, no ETA sidecar, print attempt, lease or sync-ledger row, and no new order, item, audit or dispatch row');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_transport;
delete from _rgw_stack;
set local role authenticated;
insert into _rgw_r values ('eta_transport_4', pg_temp.rgw_eta_try(4, 25)::text);
reset role;
select is(
  (select jsonb_build_object(
     'answer', jsonb_build_object('raised', t ? 'raised', 'ok', t #>> '{returned,ok}', 'status', t #>> '{returned,status}',
                                  'replayed', t #>> '{returned,replayed}',
                                  'same_decision_id', t #> '{returned,same_decision_id}',
                                  'canonical_order_id_present', t #> '{returned,canonical_order_id_present}',
                                  'print_blocker', t #> '{returned,print_blocker}'),
     'path', (select jsonb_agg(pg_temp.rgw_frames(s.ctx)) from _rgw_stack s),
     'after', (f #- '{request,row_md5}') - 'org',
     'new_orders', (f #>> '{org,orders}')::int - (b #>> '{org,orders}')::int,
     'new_order_items', (f #>> '{org,order_items}')::int - (b #>> '{org,order_items}')::int,
     'sidecar', pg_temp.rgw_eta_sidecar(4, 25))
     from (select (select r::jsonb from _rgw_r where label = 'eta_transport_4') t, pg_temp.rgw_eta_facts(4) f,
                  (select r::jsonb from _rgw_r where label = 'eta_before_4') b) x),
  jsonb_build_object(
    'answer', jsonb_build_object('raised', false, 'ok', 'true', 'status', 'accepted', 'replayed', 'false',
                                 'same_decision_id', true, 'canonical_order_id_present', true,
                                 'print_blocker', null),
    'path', jsonb_build_array(pg_temp.rgw_eta_path(true)),
    'after', '{"request": {"status": "accepted", "mapped": true, "decided": true}, "decisions": 1,
               "decision_id_uses": 1, "eta": 1, "print_attempts": 1, "leases": 0, "ledger": 1}'::jsonb,
    'new_orders', 1, 'new_order_items', 1,
    'sidecar', '{"minutes": 25, "timezone": "UTC", "scope": true, "winner": true, "accepted_at": true,
                 "ready_at": true, "fingerprint": true}'::jsonb),
  'RG-177 W3 S7(a) (acceptance-ETA entry, legacy request; control): the same legacy request, decision id and 25 minutes under the native transport JWT accept through the same legacy path, captured at the order insert - ok, accepted, not replayed, the same decision id; one decision, ledger row and print attempt and no platform lease; one new order with its one item; and exactly one ETA sidecar row bound to the winning decision (ready_at = accepted_at + 25 minutes, UTC, versioned fingerprint)');
drop trigger zc001d_rgw_stack_probe on public.orders;

select * from finish();
rollback;
