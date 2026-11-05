-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: TEST-mode isolation (T-023 TI lane). Rollback-only synthetic fixtures, real SQL roles.
-- Proves: a TEST claim / status / finish writes no tenant audit and keeps no order / shift / drawer / card data;
-- TEST classification (test_<state>, never recorded / recoverable / provider_anomaly); the TEST shape CHECK; TEST
-- denials as private test.card_attempt_denied only; the pre-ledger TEST refusal of app.sync_push (no ledger row, one
-- private event, repeat silent, tombstone silent, permission_denied shape); the revoked-device carve-out; TEST never
-- blocks shift.close and is read only through the owner read's TEST filter; TEST / LIVE mode separation at the claim.
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
-- TI helpers (this file only; owner role, read after RESET ROLE).
-- ===========================================================================
-- The ledger row of an identity label (pilot organization; device d).
create function pg_temp.ti_attempt(p_lop_label text, p_d integer default 1) returns app.card_provider_attempts
language sql stable as $$
  select a.* from app.card_provider_attempts a
   where a.organization_id = pg_temp.zc_org() and a.device_id = pg_temp.zc_id('device-' || p_d)
     and a.local_operation_id = pg_temp.zc_lop(p_lop_label) $$;
create function pg_temp.ti_attempt_n(p_lop_label text) returns bigint language sql stable as $$
  select count(*) from app.card_provider_attempts a
   where a.organization_id = pg_temp.zc_org() and a.local_operation_id = pg_temp.zc_lop(p_lop_label) $$;
create function pg_temp.ti_row_id(p_label text) returns uuid language sql stable as $$
  select (r ->> 'attempt_row_id')::uuid from _zc_r where label = p_label $$;
create function pg_temp.ti_sync_n(p_lop_label text, p_d integer default 1) returns bigint language sql stable as $$
  select count(*) from public.sync_operations so
   where so.organization_id = pg_temp.zc_org() and so.device_id = pg_temp.zc_id('device-' || p_d)
     and so.local_operation_id = pg_temp.zc_lop(p_lop_label) $$;
create function pg_temp.ti_payment_n(p_lop_label text) returns bigint language sql stable as $$
  select count(*) from public.payments p where p.local_operation_id = pg_temp.zc_lop(p_lop_label) $$;
create function pg_temp.ti_order_payment_n(p_order_label text) returns bigint language sql stable as $$
  select count(*) from public.payments p where p.order_id = pg_temp.zc_id('order-' || p_order_label) $$;
-- Sorted key set of a JSON object.
create function pg_temp.ti_keys(j jsonb) returns text[] language sql immutable as $$
  select coalesce(array_agg(k order by k), '{}'::text[]) from jsonb_object_keys(j) k $$;
create function pg_temp.ti_sorted(a text[]) returns text[] language sql immutable as $$
  select coalesce(array_agg(x order by x), '{}'::text[]) from unnest(a) x $$;
-- Marks: the pilot organization's audit / private-event ids seen at a point, so each step's NEW rows are exact.
create temp table _ti_seen (label text not null, kind text not null, id uuid not null, primary key (label, kind, id));
create function pg_temp.ti_mark(p_label text) returns void language sql volatile as $$
  delete from _ti_seen s where s.label = p_label;
  insert into _ti_seen select p_label, 'audit', e.id from public.audit_events e where e.organization_id = pg_temp.zc_org();
  insert into _ti_seen select p_label, 'event', e.id from app.card_provider_private_events e
   where e.organization_id = pg_temp.zc_org();
$$;
create function pg_temp.ti_new_audit(p_label text) returns setof public.audit_events language sql stable as $$
  select e.* from public.audit_events e
   where e.organization_id = pg_temp.zc_org()
     and not exists (select 1 from _ti_seen s where s.label = p_label and s.kind = 'audit' and s.id = e.id) $$;
create function pg_temp.ti_new_events(p_label text) returns setof app.card_provider_private_events
language sql stable as $$
  select e.* from app.card_provider_private_events e
   where e.organization_id = pg_temp.zc_org()
     and not exists (select 1 from _ti_seen s where s.label = p_label and s.kind = 'event' and s.id = e.id) $$;
-- The comparable facts of one private event.
create function pg_temp.ti_ev(e app.card_provider_private_events) returns jsonb language sql stable as $$
  select jsonb_build_object('action', e.action, 'mode', e.mode, 'detail', e.detail, 'attempt_row_id', e.attempt_row_id,
    'actor_kind', e.actor_kind, 'actor_reference', e.actor_reference, 'actor_app_user_id', e.actor_app_user_id,
    'executor_principal', e.executor_principal, 'actor_employee_profile_id', e.actor_employee_profile_id,
    'device_id', e.device_id, 'reason', e.reason, 'organization_id', e.organization_id,
    'restaurant_id', e.restaurant_id, 'branch_id', e.branch_id,
    'retention_is_created_plus_90d', e.retention_until = e.created_at + interval '90 days',
    'incident_hold_at', e.incident_hold_at) $$;
-- The expected comparable facts of an employee / adapter TEST event in the pilot scope.
create function pg_temp.ti_ev_expect(p_action text, p_detail jsonb, p_attempt_row_id uuid, p_actor_kind text,
                                     p_actor_reference text, p_employee uuid, p_device uuid) returns jsonb
language sql immutable as $$
  select jsonb_build_object('action', p_action, 'mode', 'test', 'detail', p_detail, 'attempt_row_id', p_attempt_row_id,
    'actor_kind', p_actor_kind, 'actor_reference', p_actor_reference, 'actor_app_user_id', null,
    'executor_principal', null, 'actor_employee_profile_id', p_employee, 'device_id', p_device, 'reason', null,
    'organization_id', pg_temp.zc_org(), 'restaurant_id', pg_temp.zc_rest(), 'branch_id', pg_temp.zc_branch(),
    'retention_is_created_plus_90d', true, 'incident_hold_at', null) $$;
-- Card-like and provider-reference values for every field a TEST attempt discards (each would be
-- stored, or refused by its field rule with an event, on a LIVE attempt).
create function pg_temp.ti_card_fields() returns jsonb language sql immutable as $$
  select jsonb_build_object('card_last4', '4242', 'provider_reference', repeat('7351', 4),
    'approval_number', rtrim(repeat('7351-', 4), '-'), 'voucher_number', repeat('2468', 4),
    'deposit_id', rtrim(repeat('2468 ', 4)), 'card_brand_code', 'VISA', 'pan_entry_mode', left(repeat('9135', 4), 15),
    'payment_method_code', '****1111') $$;
create function pg_temp.ti_card_columns(a app.card_provider_attempts) returns jsonb language sql immutable as $$
  select jsonb_build_object('card_last4', a.card_last4, 'provider_reference', a.provider_reference,
    'approval_number', a.approval_number, 'voucher_number', a.voucher_number, 'deposit_id', a.deposit_id,
    'card_brand_code', a.card_brand_code, 'pan_entry_mode', a.pan_entry_mode,
    'payment_method_code', a.payment_method_code) $$;
create function pg_temp.ti_card_nulls() returns jsonb language sql immutable as $$
  select jsonb_build_object('card_last4', null, 'provider_reference', null, 'approval_number', null,
    'voucher_number', null, 'deposit_id', null, 'card_brand_code', null, 'pan_entry_mode', null,
    'payment_method_code', null) $$;
-- The exact pre-ledger TEST refusal key set (API §4.55.3 / packet §6 change 6).
create function pg_temp.ti_refusal_keys() returns text[] language sql immutable as $$
  select pg_temp.ti_sorted(array['local_operation_id', 'operation_type', 'ok', 'error', 'status', 'idempotency_replay',
                                 'server_ts', 'order_id']) $$;
create function pg_temp.ti_refusal(p_lop_label text, p_error text, p_order_label text) returns jsonb
language sql immutable as $$
  select jsonb_build_object('local_operation_id', pg_temp.zc_lop(p_lop_label), 'operation_type', 'payment.create',
    'ok', false, 'error', p_error, 'status', 'rejected', 'idempotency_replay', false,
    'order_id', pg_temp.zc_id('order-' || p_order_label)) $$;
-- A captured result, and the first operation result of a captured sync_push call.
create function pg_temp.ti_r(p_label text) returns jsonb language sql stable as $$
  select r from _zc_r where label = p_label $$;
create function pg_temp.ti_res(p_label text) returns jsonb language sql stable as $$
  select r -> 'results' -> 0 from _zc_r where label = p_label $$;
-- An expected TEST §4.55.4 envelope (server_ts removed by the caller).
create function pg_temp.ti_env(p_lop_label text, p_state text, p_amount bigint, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop(p_lop_label), 'state', p_state,
    'classification', 'test_' || p_state, 'recorded', false, 'amount_minor', p_amount, 'currency_code', 'ILS')
    || p_extra $$;

-- Synthetic orders of d1 (the recording-leg payloads name them; no TEST attempt references an order).
select pg_temp.zc_order('ti-o1', 1234, 1) as order_ti_o1;
select pg_temp.zc_order('ti-o2', 5000, 1) as order_ti_o2;

-- ===========================================================================
-- S0. LIVE context for the mode separation and the owner read: a LIVE revision,
--     an enabled LIVE binding on d2 and one LIVE attempt of d2 finished declined.
--     Its tenant audit rows precede every TEST mark below.
-- ===========================================================================
insert into _zc_r select 'rev_live_1', pg_temp.zc_pilot('live');
insert into _zc_r select 'bind_live_2', pg_temp.zc_bind(2, 'live');
select pg_temp.zc_order('ti-live', 1234, 2) as order_ti_live;
set local role service_role;
insert into _zc_r select 'live_claim', pg_temp.zc_claim(8, pg_temp.zc_lop('ti-live'), 'live', 1234,
  pg_temp.zc_id('order-ti-live'), 1);
reset role;
set local role service_role;
insert into _zc_r select 'live_finish', pg_temp.zc_finish((select r from _zc_r where label = 'live_claim'), 'commit',
  'declined', jsonb_build_object('approval_type', 'declined'));
reset role;
select is((select jsonb_build_object('rev', r -> 'ok', 'bind', (select r -> 'new_lifecycle' from _zc_r where label = 'bind_live_2'),
                                     'claim', (select r -> 'claim_created' from _zc_r where label = 'live_claim'),
                                     'finish', (select r -> 'state' from _zc_r where label = 'live_finish'))
             from _zc_r where label = 'rev_live_1'),
          '{"rev": true, "bind": "enabled", "claim": true, "finish": "declined"}'::jsonb,
          'TI-01 setup: LIVE revision, enabled LIVE binding on d2, one LIVE attempt of d2 claimed and finished declined');
select pg_temp.ti_mark('test_phase');

-- ===========================================================================
-- 9. TEST / LIVE separation at the claim (API §4.55.4 step (3), the symmetric mode rule).
-- ===========================================================================
-- 9a. The TEST revision is current, but d2's binding is LIVE (a mapping row of another mode).
insert into _zc_r select 'rev_test_1', pg_temp.zc_pilot('test');
select pg_temp.ti_mark('sep_binding');
set local role service_role;
insert into _zc_r select 'sep_binding', pg_temp.zc_claim(8, pg_temp.zc_lop('ti-sep-binding'), 'test', 1234);
reset role;
select is(pg_temp.ti_r('sep_binding') - 'server_ts', '{"ok": false, "error": "card_payments_disabled"}'::jsonb,
          'TI-02 9: a TEST claim under a LIVE binding (TEST revision current, d2 mapped LIVE) is refused card_payments_disabled');
select is(pg_temp.ti_keys(pg_temp.ti_r('sep_binding')), array['error', 'ok', 'server_ts'],
          'TI-03 9: the LIVE-binding refusal carries exactly {ok, error, server_ts}');
select is(pg_temp.ti_attempt_n('ti-sep-binding'), 0::bigint, 'TI-04 9: the LIVE-binding refusal creates no ledger row');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('sep_binding') e),
          jsonb_build_array(pg_temp.ti_ev_expect('security.card_credential_mismatch',
            '{"check": "mapping_mode", "source": "claim"}'::jsonb, null, 'employee', 'employee',
            pg_temp.zc_id('employee-8'), pg_temp.zc_id('device-2'))),
          'TI-05 9: the LIVE-binding refusal writes exactly one security.card_credential_mismatch {check: mapping_mode, source: claim} (mode test, 90-day retention, employee actor, no attempt)');
select is((select count(*) from pg_temp.ti_new_audit('sep_binding')), 0::bigint,
          'TI-06 9: the LIVE-binding refusal writes no tenant audit row');

-- Retire d2's LIVE binding (one admitting binding per organization), then a LIVE
-- revision with an enabled TEST binding on d1.
insert into _zc_r select 'drain_live_2', app.set_payment_terminal(pg_temp.zc_id('device-2'), 'live', 'zc-term-live-2',
  'zc-cred-live-2', 'draining', 'end_of_pilot', 'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner());
insert into _zc_r select 'retire_live_2', app.set_payment_terminal(pg_temp.zc_id('device-2'), 'live', 'zc-term-live-2',
  'zc-cred-live-2', 'retired', 'end_of_pilot', 'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner());
insert into _zc_r select 'rev_live_2', pg_temp.zc_pilot('live');
insert into _zc_r select 'bind_test_1', pg_temp.zc_bind(1, 'test');
select is((select jsonb_build_object('drain', (select r -> 'new_lifecycle' from _zc_r where label = 'drain_live_2'),
                                     'retire', (select r -> 'new_lifecycle' from _zc_r where label = 'retire_live_2'),
                                     'rev', (select r -> 'mode' from _zc_r where label = 'rev_live_2'),
                                     'bind', r -> 'new_lifecycle', 'bind_mode', r -> 'binding_mode')
             from _zc_r where label = 'bind_test_1'),
          '{"drain": "draining", "retire": "retired", "rev": "live", "bind": "enabled", "bind_mode": "test"}'::jsonb,
          'TI-07 setup: d2''s LIVE binding retired; a LIVE revision current; d1''s TEST binding enabled');

-- 9b. The LIVE revision is current and d1 is mapped TEST: a mode differing only from the revision's.
select pg_temp.ti_mark('sep_revision');
set local role service_role;
insert into _zc_r select 'sep_revision', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-sep-revision'), 'test', 1234);
reset role;
select is(pg_temp.ti_r('sep_revision') - 'server_ts', '{"ok": false, "error": "card_payments_disabled"}'::jsonb,
          'TI-08 9: a TEST claim under a LIVE revision (d1 mapped TEST) is refused card_payments_disabled');
select is(pg_temp.ti_attempt_n('ti-sep-revision'), 0::bigint, 'TI-09 9: the LIVE-revision refusal creates no ledger row');
select is((select count(*) from pg_temp.ti_new_events('sep_revision')), 0::bigint,
          'TI-10 9: the LIVE-revision refusal writes no private event (a mode differing only from the revision''s writes none)');
select is((select count(*) from pg_temp.ti_new_audit('sep_revision')), 0::bigint,
          'TI-11 9: the LIVE-revision refusal writes no tenant audit row');

-- The TEST revision is current from here on (TEST cap 100000).
insert into _zc_r select 'rev_test_2', pg_temp.zc_pilot('test');
select is((select jsonb_build_object('ok', r -> 'ok', 'mode', r -> 'mode', 'enabled', r -> 'enabled',
                                     'max_test_amount_minor', r -> 'max_test_amount_minor')
             from _zc_r where label = 'rev_test_2'),
          '{"ok": true, "mode": "test", "enabled": true, "max_test_amount_minor": 100000}'::jsonb,
          'TI-12 setup: the TEST revision (cap 100000) is current');

-- 9c. The configuration environment 'production' with a TEST request.
select pg_temp.ti_mark('sep_env');
set local role service_role;
insert into _zc_r select 'sep_env', public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('ti-sep-env'), 'test', 1234, 'ILS', null, null, 'production',
  pg_temp.zc_terminals(1, 'test'), pg_temp.zc_credentials(1, 'test'), 'alpha16-l32-v1', pg_temp.zc_caller());
reset role;
select is(pg_temp.ti_r('sep_env') - 'server_ts', '{"ok": false, "error": "card_payments_disabled"}'::jsonb,
          'TI-13 9: a TEST claim with the configuration environment ''production'' is refused card_payments_disabled');
select is(pg_temp.ti_attempt_n('ti-sep-env'), 0::bigint,
          'TI-14 9: the production-environment refusal creates no ledger row');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('sep_env') e),
          jsonb_build_array(pg_temp.ti_ev_expect('security.card_credential_mismatch',
            '{"check": "environment_mode", "source": "claim"}'::jsonb, null, 'employee', 'employee',
            pg_temp.zc_id('employee-1'), pg_temp.zc_id('device-1'))),
          'TI-15 9: the production-environment refusal writes exactly one security.card_credential_mismatch {check: environment_mode, source: claim} (mode test, 90-day retention)');
select is((select count(*) from pg_temp.ti_new_audit('sep_env')), 0::bigint,
          'TI-16 9: the production-environment refusal writes no tenant audit row');

-- ===========================================================================
-- 1. A TEST claim (zc_pilot('test') + zc_bind(1, 'test') current): no order,
--    shift, drawer or revision; 90-day retention; sent / test_sent; no tenant
--    audit; card_attempt.started never written.
-- ===========================================================================
select pg_temp.ti_mark('claim_a');
set local role service_role;
insert into _zc_r select 'claim_a', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-a'), 'test', 1234);
reset role;
select is(pg_temp.ti_r('claim_a') - 'server_ts' - 'attempt_row_id' - 'start_deadline_at' - 'provider_query_key'
            - 'provider_duplicate_key',
          pg_temp.ti_env('ti-a', 'sent', 1234, jsonb_build_object('claim_created', true, 'replayed', false,
            'organization_id', pg_temp.zc_org(), 'restaurant_id', pg_temp.zc_rest(),
            'device_id', pg_temp.zc_id('device-1'), 'local_operation_id', pg_temp.zc_lop('ti-a'), 'mode', 'test',
            'terminal_ref', 'zc-term-test-1', 'credential_ref', 'zc-cred-test-1',
            'provider_key_format_version', 'alpha16-l32-v1')),
          'TI-17 1: the TEST claim answers ok, state sent, classification test_sent, recorded false, claim_created true');
select is(pg_temp.ti_keys(pg_temp.ti_r('claim_a')),
          pg_temp.ti_sorted(array['ok', 'attempt_id', 'state', 'classification', 'recorded', 'amount_minor',
            'currency_code', 'server_ts', 'claim_created', 'replayed', 'attempt_row_id', 'organization_id',
            'restaurant_id', 'device_id', 'local_operation_id', 'mode', 'terminal_ref', 'credential_ref',
            'start_deadline_at', 'provider_key_format_version', 'provider_query_key', 'provider_duplicate_key']),
          'TI-18 1: the TEST claim envelope has exactly the adapter claim keys (no recoverable / resume_count / payment_id / anomaly_code)');
select is((select jsonb_build_object('order_id', a.order_id, 'shift_id', a.shift_id,
                                     'cash_drawer_session_id', a.cash_drawer_session_id,
                                     'expected_revision', a.expected_revision, 'mode', a.mode, 'state', a.state,
                                     'resolution', a.resolution, 'charge_may_exist', a.charge_may_exist,
                                     'initiated_by_employee_profile_id', a.initiated_by_employee_profile_id,
                                     'initiated_by_membership_id', a.initiated_by_membership_id)
             from pg_temp.ti_attempt('ti-a') a),
          jsonb_build_object('order_id', null, 'shift_id', null, 'cash_drawer_session_id', null,
                             'expected_revision', null, 'mode', 'test', 'state', 'sent', 'resolution', null,
                             'charge_may_exist', false,
                             'initiated_by_employee_profile_id', pg_temp.zc_id('employee-1'),
                             'initiated_by_membership_id', pg_temp.zc_id('membership-1')),
          'TI-19 1: the TEST row has order_id / shift_id / cash_drawer_session_id / expected_revision NULL, state sent, the initiator frozen');
select is((select a.id from pg_temp.ti_attempt('ti-a') a), pg_temp.ti_row_id('claim_a'),
          'TI-20 1: the claim''s attempt_row_id is the ledger row of the identity');
select is((select a.retention_until from pg_temp.ti_attempt('ti-a') a),
          (select a.created_at + interval '90 days' from pg_temp.ti_attempt('ti-a') a),
          'TI-21 1: retention_until = created_at + 90 days (exact; DOMAIN §8.4, API §4.55.8)');
select ok((select a.retention_until is not null
                  and abs(extract(epoch from a.retention_until - (a.created_at + interval '90 days'))) < 1
             from pg_temp.ti_attempt('ti-a') a),
          'TI-22 1: retention_until is set and lies within one second of created_at + 90 days');
select is((select app.card_attempt_derive(a) ->> 'classification' from pg_temp.ti_attempt('ti-a') a), 'test_sent',
          'TI-23 1: the derived classification of the sent TEST row is test_sent');
select is((select count(*) from pg_temp.ti_new_audit('claim_a')), 0::bigint,
          'TI-24 1: the TEST claim writes no tenant audit_events row (pilot organization count before = after)');
select is((select count(*) from public.audit_events e
            where e.organization_id = pg_temp.zc_org() and e.action = 'card_attempt.started'),
          1::bigint,
          'TI-25 1: card_attempt.started is NOT written for the TEST claim (the only one is the LIVE d2 claim''s)');
select is((select count(*) from pg_temp.ti_new_events('claim_a')), 0::bigint,
          'TI-26 1: the TEST claim writes no private event');

-- The idempotent replay and the status read of the TEST attempt: still no tenant audit.
select pg_temp.ti_mark('status_a');
set local role service_role;
insert into _zc_r select 'claim_a_replay', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-a'), 'test', 1234);
insert into _zc_r select 'read_a', public.card_attempt_adapter_read(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('ti-a'), 'test', pg_temp.zc_terminals(1, 'test'), pg_temp.zc_credentials(1, 'test'), pg_temp.zc_caller());
reset role;
set local role authenticated;
insert into _zc_r select 'ctx_a', public.card_attempt_context(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', null, pg_temp.zc_lop('ti-a'));
reset role;
select is((select jsonb_build_object('claim_created', r -> 'claim_created', 'replayed', r -> 'replayed',
                                     'state', r -> 'state', 'classification', r -> 'classification',
                                     'attempt_row_id', r -> 'attempt_row_id',
                                     'has_keys', r ? 'provider_query_key' or r ? 'provider_duplicate_key')
             from _zc_r where label = 'claim_a_replay'),
          jsonb_build_object('claim_created', false, 'replayed', true, 'state', 'sent', 'classification', 'test_sent',
                             'attempt_row_id', pg_temp.ti_row_id('claim_a'), 'has_keys', false),
          'TI-27 1: a replayed TEST claim answers the same row (replayed, no new keys)');
select is((select jsonb_build_object('state', r -> 'state', 'classification', r -> 'classification',
                                     'recorded', r -> 'recorded', 'mode', r -> 'mode')
             from _zc_r where label = 'read_a'),
          '{"state": "sent", "classification": "test_sent", "recorded": false, "mode": "test"}'::jsonb,
          'TI-28 1: the adapter status read of the TEST attempt answers test_sent, recorded false');
select is(pg_temp.ti_r('ctx_a') -> 'attempt',
          pg_temp.ti_env('ti-a', 'sent', 1234, '{"mode": "test", "own_device": true}'::jsonb) - 'ok',
          'TI-29 1: the context proof projects the TEST attempt as exactly {attempt_id, state, classification test_sent, recorded false, amounts, mode, own_device}');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('status_a')),
                                     'events', (select count(*) from pg_temp.ti_new_events('status_a')))),
          '{"audit": 0, "events": 0}'::jsonb,
          'TI-30 1: the replay, the status read and the context proof write no tenant audit and no private event');

-- ===========================================================================
-- 4a. TEST denials RETURNED by the claim: one private test.card_attempt_denied
--     each, zero audit_events, no ledger row.
-- ===========================================================================
select pg_temp.ti_mark('deny_currency');
set local role service_role;
insert into _zc_r select 'deny_currency', public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('ti-usd'), 'test', 1234, 'USD', null, null, 'test',
  pg_temp.zc_terminals(1, 'test'), pg_temp.zc_credentials(1, 'test'), 'alpha16-l32-v1', pg_temp.zc_caller());
reset role;
select is(pg_temp.ti_r('deny_currency') - 'server_ts',
          '{"ok": false, "error": "precondition_failed", "detail": "currency_not_supported"}'::jsonb,
          'TI-31 4: a TEST claim in a currency other than the tenant''s is refused precondition_failed/currency_not_supported');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('deny_currency') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_attempt_denied',
            '{"rpc": "claim", "denied_reason": "currency_not_supported"}'::jsonb, null, 'employee', 'employee',
            pg_temp.zc_id('employee-1'), pg_temp.zc_id('device-1'))),
          'TI-32 4: the currency refusal writes exactly one private test.card_attempt_denied {rpc: claim, denied_reason: currency_not_supported}');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('deny_currency')),
                                     'rows', pg_temp.ti_attempt_n('ti-usd'))),
          '{"audit": 0, "rows": 0}'::jsonb,
          'TI-33 4: the currency refusal writes zero audit_events and no ledger row');

select pg_temp.ti_mark('deny_cap');
set local role service_role;
insert into _zc_r select 'deny_cap', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-cap'), 'test', 100001);
reset role;
select is(pg_temp.ti_r('deny_cap') - 'server_ts',
          '{"ok": false, "error": "precondition_failed", "detail": "max_test_amount_exceeded"}'::jsonb,
          'TI-34 4: a TEST claim above the TEST cap (100001 > 100000) is refused precondition_failed/max_test_amount_exceeded');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('deny_cap') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_attempt_denied',
            '{"rpc": "claim", "denied_reason": "max_test_amount_exceeded"}'::jsonb, null, 'employee', 'employee',
            pg_temp.zc_id('employee-1'), pg_temp.zc_id('device-1'))),
          'TI-35 4: the cap refusal writes exactly one private test.card_attempt_denied {rpc: claim, denied_reason: max_test_amount_exceeded}');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('deny_cap')),
                                     'rows', pg_temp.ti_attempt_n('ti-cap'))),
          '{"audit": 0, "rows": 0}'::jsonb,
          'TI-36 4: the cap refusal writes zero audit_events and no ledger row');

-- The cap itself is admitted (boundary), still without audit.
select pg_temp.ti_mark('cap_eq');
set local role service_role;
insert into _zc_r select 'cap_eq', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-cap-eq'), 'test', 100000);
reset role;
select is((select jsonb_build_object('ok', r -> 'ok', 'classification', r -> 'classification',
                                     'audit', (select count(*) from pg_temp.ti_new_audit('cap_eq')),
                                     'events', (select count(*) from pg_temp.ti_new_events('cap_eq')))
             from _zc_r where label = 'cap_eq'),
          '{"ok": true, "classification": "test_sent", "audit": 0, "events": 0}'::jsonb,
          'TI-37 4: a TEST claim of exactly the cap is admitted (test_sent) with no audit and no private event');

-- A kitchen PIN at the claim: the proof's permission_denied is evidenced in the requested (TEST) mode.
select pg_temp.ti_mark('deny_kitchen');
set local role service_role;
insert into _zc_r select 'deny_kitchen', pg_temp.zc_claim(4, pg_temp.zc_lop('ti-kitchen'), 'test', 1234);
reset role;
select is(pg_temp.ti_r('deny_kitchen') - 'server_ts', '{"ok": false, "error": "permission_denied"}'::jsonb,
          'TI-38 4: a TEST claim by a kitchen PIN (staff 4) is refused permission_denied');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('deny_kitchen') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_attempt_denied',
            '{"rpc": "claim", "denied_reason": "permission_denied"}'::jsonb, null, 'employee', 'employee',
            pg_temp.zc_id('employee-4'), pg_temp.zc_id('device-1'))),
          'TI-39 4: the kitchen claim refusal writes exactly one private test.card_attempt_denied {rpc: claim, denied_reason: permission_denied}');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('deny_kitchen')),
                                     'rows', pg_temp.ti_attempt_n('ti-kitchen'))),
          '{"audit": 0, "rows": 0}'::jsonb,
          'TI-40 4: the kitchen claim refusal writes zero audit_events and no ledger row');

-- ===========================================================================
-- 2. TEST finish: approved / declined / unknown / released / anomaly; card and
--    provider-reference fields discarded unread; provider_saved_at still checked;
--    zero tenant audit throughout.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'claim_d', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-d'), 'test', 2000);
insert into _zc_r select 'claim_u', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-u'), 'test', 3000);
insert into _zc_r select 'claim_r', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-r'), 'test', 4000);
insert into _zc_r select 'claim_x', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-x'), 'test', 5000);
reset role;
select is((select jsonb_agg(r -> 'classification' order by label) from _zc_r
            where label in ('claim_d', 'claim_u', 'claim_r', 'claim_x')),
          '["test_sent", "test_sent", "test_sent", "test_sent"]'::jsonb,
          'TI-41 setup: four more TEST attempts claimed on d1 (2000 / 3000 / 4000 / 5000)');

-- 2a. approved (commit) carrying card-like data in every discarded field and a bad provider_saved_at.
select pg_temp.ti_mark('fin_a');
set local role service_role;
insert into _zc_r select 'fin_a', pg_temp.zc_finish(pg_temp.ti_r('claim_a'), 'commit', 'approved',
  pg_temp.zc_approved_fields() || pg_temp.ti_card_fields() || jsonb_build_object('provider_saved_at', 'not-a-timestamp'));
reset role;
select is(pg_temp.ti_r('fin_a') - 'server_ts', pg_temp.ti_env('ti-a', 'approved', 1234, '{"provider_return_code": 0}'::jsonb),
          'TI-42 2: an approving commit finishes the TEST attempt approved / test_approved with recorded false (no recoverable, resume_count, payment_id or anomaly_code key)');
select is((select app.card_attempt_derive(a) from pg_temp.ti_attempt('ti-a') a),
          '{"recorded": false, "payment_id": null, "classification": "test_approved", "reason": null, "recoverable": false, "claim_active": false, "blocks_close": false, "unresolved": false}'::jsonb,
          'TI-43 2: the approved TEST attempt derives test_approved, never recorded, never recoverable, no active claim, never blocks a close');
select is((select pg_temp.ti_card_columns(a) from pg_temp.ti_attempt('ti-a') a), pg_temp.ti_card_nulls(),
          'TI-44 2: card_last4, provider_reference, approval_number, voucher_number, deposit_id, card_brand_code, pan_entry_mode and payment_method_code stay NULL on the approved TEST row');
select is((select jsonb_build_object('approval_type', a.approval_type, 'provider_status_code', a.provider_status_code,
                                     'provider_return_code', a.provider_return_code,
                                     'provider_return_class', a.provider_return_class,
                                     'approved_at_set', a.provider_approved_at is not null,
                                     'finished_at_set', a.finished_at is not null,
                                     'provider_saved_at', a.provider_saved_at,
                                     'provider_anomaly_code', a.provider_anomaly_code,
                                     'charge_may_exist', a.charge_may_exist)
             from pg_temp.ti_attempt('ti-a') a),
          '{"approval_type": "approved", "provider_status_code": "ok1", "provider_return_code": 0, "provider_return_class": "approved", "approved_at_set": true, "finished_at_set": true, "provider_saved_at": null, "provider_anomaly_code": null, "charge_may_exist": false}'::jsonb,
          'TI-45 2: the approved TEST row keeps the approval type, status code, return code / class and time metadata; the bad provider_saved_at is dropped');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('fin_a') e),
          jsonb_build_array(pg_temp.ti_ev_expect('security.card_provider_field_dropped',
            '{"field": "provider_saved_at", "rule": "format", "source": "commit"}'::jsonb,
            pg_temp.ti_row_id('claim_a'), 'adapter', 'card_adapter', null, pg_temp.zc_id('device-1'))),
          'TI-46 2: the approving commit writes exactly one private event: security.card_provider_field_dropped {provider_saved_at, format, commit} (mode test, 90-day retention) - none for the eight card / reference fields');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('fin_a')),
                                     'payments', pg_temp.ti_payment_n('ti-a'))),
          '{"audit": 0, "payments": 0}'::jsonb,
          'TI-47 2: the TEST approval writes no tenant audit row and no payment');

-- 2b. declined (commit) with the card fields again and a valid provider_saved_at (kept).
select pg_temp.ti_mark('fin_d');
set local role service_role;
insert into _zc_r select 'fin_d', pg_temp.zc_finish(pg_temp.ti_r('claim_d'), 'commit', 'declined',
  jsonb_build_object('approval_type', 'declined', 'provider_return_code', 51, 'provider_return_class', 'declined',
                     'provider_saved_at', '2026-10-24T01:02:03Z') || pg_temp.ti_card_fields());
reset role;
select is(pg_temp.ti_r('fin_d') - 'server_ts', pg_temp.ti_env('ti-d', 'declined', 2000, '{"provider_return_code": 51}'::jsonb),
          'TI-48 2: a declining commit finishes the TEST attempt declined / test_declined, recorded false');
select is((select pg_temp.ti_card_columns(a) || jsonb_build_object('provider_saved_at', a.provider_saved_at)
             from pg_temp.ti_attempt('ti-d') a),
          pg_temp.ti_card_nulls() || jsonb_build_object('provider_saved_at', '2026-10-24T01:02:03Z'::timestamptz),
          'TI-49 2: the declined TEST row discards every card / reference field and keeps the valid provider_saved_at');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('fin_d')),
                                     'events', (select count(*) from pg_temp.ti_new_events('fin_d')))),
          '{"audit": 0, "events": 0}'::jsonb,
          'TI-50 2: the TEST decline writes no tenant audit and no private event (card-like data discarded unread, no field_dropped)');

-- 2c. unknown (commit).
select pg_temp.ti_mark('fin_u');
set local role service_role;
insert into _zc_r select 'fin_u', pg_temp.zc_finish(pg_temp.ti_r('claim_u'), 'commit', 'unknown', '{}'::jsonb);
reset role;
select is(pg_temp.ti_r('fin_u') - 'server_ts', pg_temp.ti_env('ti-u', 'unknown', 3000),
          'TI-51 2: an unknown commit finishes the TEST attempt unknown / test_unknown, recorded false');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('fin_u')),
                                     'events', (select count(*) from pg_temp.ti_new_events('fin_u')))),
          '{"audit": 0, "events": 0}'::jsonb,
          'TI-52 2: the TEST unknown writes no tenant audit and no private event');

-- 2d. release requested, then released.
select pg_temp.ti_mark('fin_r');
set local role service_role;
insert into _zc_r select 'relreq_r', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-1'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-r'), pg_temp.zc_caller());
insert into _zc_r select 'fin_r', pg_temp.zc_finish(pg_temp.ti_r('claim_r'), 'release', 'released', '{}'::jsonb);
reset role;
select is((select jsonb_build_object('relreq', (select r - 'server_ts' from _zc_r where label = 'relreq_r'),
                                     'release_requested_at_set', a.release_requested_at is not null)
             from pg_temp.ti_attempt('ti-r') a),
          jsonb_build_object('relreq', pg_temp.ti_env('ti-r', 'sent', 4000), 'release_requested_at_set', true),
          'TI-53 2: the TEST release request stamps release_requested_at and answers the test_sent envelope');
select is(pg_temp.ti_r('fin_r') - 'server_ts', pg_temp.ti_env('ti-r', 'released', 4000),
          'TI-54 2: a release finishes the TEST attempt released / test_released, recorded false');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('fin_r')),
                                     'events', (select count(*) from pg_temp.ti_new_events('fin_r')))),
          '{"audit": 0, "events": 0}'::jsonb,
          'TI-55 2: the TEST release request and release write no tenant audit (no card_attempt.release_requested) and no private event');

-- 2e. anomaly: the code is kept as evidence; the classification stays test_<state>; no anomaly_code in the envelope.
select pg_temp.ti_mark('fin_x');
set local role service_role;
insert into _zc_r select 'fin_x', pg_temp.zc_finish(pg_temp.ti_r('claim_x'), 'commit', 'anomaly',
  '{"anomaly_code": "amount_mismatch"}'::jsonb);
reset role;
select is(pg_temp.ti_r('fin_x') - 'server_ts', pg_temp.ti_env('ti-x', 'unknown', 5000),
          'TI-56 2: an anomalous commit leaves the TEST attempt unknown / test_unknown and the envelope carries no anomaly_code');
select is((select jsonb_build_object('provider_anomaly_code', a.provider_anomaly_code,
                                     'charge_may_exist', a.charge_may_exist,
                                     'derive', app.card_attempt_derive(a) - 'payment_id' - 'reason' - 'claim_active'
                                                - 'blocks_close')
             from pg_temp.ti_attempt('ti-x') a),
          '{"provider_anomaly_code": "amount_mismatch", "charge_may_exist": true, "derive": {"recorded": false, "classification": "test_unknown", "recoverable": false, "unresolved": true}}'::jsonb,
          'TI-57 2: the TEST anomaly keeps provider_anomaly_code and charge_may_exist as evidence; classification test_unknown (never provider_anomaly), never recoverable');
-- A later anomaly on the released TEST attempt: classification stays test_released.
set local role service_role;
insert into _zc_r select 'fin_r_anomaly', pg_temp.zc_finish(pg_temp.ti_r('claim_r'), 'lookup', 'anomaly',
  '{"anomaly_code": "refunded"}'::jsonb, 'operator');
reset role;
select is((select jsonb_build_object('envelope', (select r - 'server_ts' from _zc_r where label = 'fin_r_anomaly'),
                                     'provider_anomaly_code', a.provider_anomaly_code,
                                     'charge_may_exist', a.charge_may_exist)
             from pg_temp.ti_attempt('ti-r') a),
          jsonb_build_object('envelope', pg_temp.ti_env('ti-r', 'released', 4000), 'provider_anomaly_code', 'refunded',
                             'charge_may_exist', true),
          'TI-58 2: an anomalous lookup on the released TEST attempt keeps state released / test_released (no anomaly_code in the envelope) and stores the code');
-- A later exact approving lookup clears the charge risk but keeps the anomaly code as history.
set local role service_role;
insert into _zc_r select 'fin_x_lookup', pg_temp.zc_finish(pg_temp.ti_r('claim_x'), 'lookup', 'approved',
  '{"provider_status_code": "ok1", "provider_amount": "50.00", "provider_currency": "ILS", "error_flag": false}'::jsonb,
  'operator');
reset role;
select is((select jsonb_build_object('envelope', (select r - 'server_ts' from _zc_r where label = 'fin_x_lookup'),
                                     'provider_anomaly_code', a.provider_anomaly_code,
                                     'charge_may_exist', a.charge_may_exist)
             from pg_temp.ti_attempt('ti-x') a),
          jsonb_build_object('envelope', pg_temp.ti_env('ti-x', 'approved', 5000), 'provider_anomaly_code', 'amount_mismatch',
                             'charge_may_exist', false),
          'TI-59 2: an exact approving lookup on the anomalous TEST attempt answers test_approved, recorded false, and keeps the anomaly code as history');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('fin_x')),
                                     'events', (select count(*) from pg_temp.ti_new_events('fin_x')))),
          '{"audit": 0, "events": 0}'::jsonb,
          'TI-60 2: the TEST anomaly / lookup transitions write no tenant audit (no card_attempt.provider_anomaly) and no private event');
select is((select count(*) from pg_temp.ti_new_audit('test_phase') e where e.action like 'card_attempt.%'), 0::bigint,
          'TI-61 2: zero card_attempt.* tenant audit rows across every TEST claim, status, release and finish so far');
select is((select count(*) from pg_temp.ti_new_audit('test_phase')), 0::bigint,
          'TI-62 2: zero tenant audit_events rows of any action in the pilot organization since the TEST phase began');

-- ===========================================================================
-- 3. The TEST shape CHECK: a direct owner UPDATE putting card data on a TEST row.
-- ===========================================================================
select throws_ok($$update app.card_provider_attempts set card_last4 = '4242' where id = pg_temp.ti_row_id('claim_a')$$,
                 '23514', 'new row for relation "card_provider_attempts" violates check constraint "card_attempts_test_shape"',
                 'TI-63 3: a direct owner UPDATE setting card_last4 on the (unresolved, approved) TEST row is refused 23514 by card_attempts_test_shape');
select throws_ok($$update app.card_provider_attempts set provider_reference = 'ZC1234' where id = pg_temp.ti_row_id('claim_u')$$,
                 '23514', 'new row for relation "card_provider_attempts" violates check constraint "card_attempts_test_shape"',
                 'TI-64 3: a direct owner UPDATE setting provider_reference on the unknown TEST row is refused 23514 by card_attempts_test_shape');
select is((select pg_temp.ti_card_columns(a) from pg_temp.ti_attempt('ti-a') a), pg_temp.ti_card_nulls(),
          'TI-65 3: the TEST row still carries no card or provider-reference data after the refused UPDATEs');

-- ===========================================================================
-- 4b. free_order on a TEST attempt: refused attempt_not_freeable with one private
--     test.card_attempt_denied; a cashier's role refusal writes nothing.
-- ===========================================================================
select pg_temp.ti_mark('free_mgr');
set local role service_role;
insert into _zc_r select 'free_mgr', public.card_attempt_free_order(pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('ti-u'), 'ZC001D synthetic free reason', 'provider_report', 'zc001d-free/ref-1', pg_temp.zc_caller());
reset role;
select is(pg_temp.ti_r('free_mgr') - 'server_ts',
          jsonb_build_object('ok', false, 'error', 'precondition_failed', 'detail', 'attempt_not_freeable',
                             'attempt_id', pg_temp.zc_lop('ti-u'), 'attempt_state', 'unknown'),
          'TI-66 4: free_order by a manager (staff 2) on the unknown TEST attempt is refused precondition_failed/attempt_not_freeable');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('free_mgr') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_attempt_denied',
            '{"rpc": "free_order", "denied_reason": "attempt_not_freeable"}'::jsonb, pg_temp.ti_row_id('claim_u'),
            'employee', 'employee', pg_temp.zc_id('employee-2'), pg_temp.zc_id('device-1'))),
          'TI-67 4: the TEST free_order refusal writes exactly one private test.card_attempt_denied {rpc: free_order, denied_reason: attempt_not_freeable} on the attempt');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('free_mgr')),
                                     'order_freed_at', a.order_freed_at, 'state', a.state)
             from pg_temp.ti_attempt('ti-u') a),
          '{"audit": 0, "order_freed_at": null, "state": "unknown"}'::jsonb,
          'TI-68 4: the TEST free_order refusal writes zero audit_events and leaves the attempt unfreed');
select pg_temp.ti_mark('free_cashier');
set local role service_role;
insert into _zc_r select 'free_cashier', public.card_attempt_free_order(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('ti-u'), 'ZC001D synthetic free reason', 'provider_report', 'zc001d-free/ref-1', pg_temp.zc_caller());
reset role;
select is((select jsonb_build_object('r', r - 'server_ts',
                                     'audit', (select count(*) from pg_temp.ti_new_audit('free_cashier')),
                                     'events', (select count(*) from pg_temp.ti_new_events('free_cashier')))
             from _zc_r where label = 'free_cashier'),
          '{"r": {"ok": false, "error": "permission_denied"}, "audit": 0, "events": 0}'::jsonb,
          'TI-69 4: a cashier''s free_order (role refusal before any attempt lookup) answers permission_denied and writes nothing');

-- ===========================================================================
-- 5. The pre-ledger TEST refusal of app.sync_push (valid device): exact answer
--    shape, no sync_operations row, no audit_events row, no payment, exactly one
--    private test.card_recording_refused per attempt; repeat silent; a kitchen
--    PIN answered permission_denied in the same shape.
-- ===========================================================================
select pg_temp.ti_mark('push_a1');
set local role authenticated;
insert into _zc_r select 'push_a1', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ti-a'), pg_temp.zc_id('order-ti-o1'))));
reset role;
select is(pg_temp.ti_keys(pg_temp.ti_res('push_a1')), pg_temp.ti_refusal_keys(),
          'TI-70 5: the refusal carries exactly {local_operation_id, operation_type, ok, error, status, idempotency_replay, server_ts, order_id}');
select is(pg_temp.ti_res('push_a1') - 'server_ts', pg_temp.ti_refusal('ti-a', 'test_attempt_not_recordable', 'ti-o1'),
          'TI-71 5: a valid-device payment.create carrying the TEST attempt''s identity is answered ok:false, test_attempt_not_recordable, status rejected, idempotency_replay false, with its own identity keys and order_id');
select is((select jsonb_build_object('ok', r -> 'ok', 'results', jsonb_array_length(r -> 'results'),
                                     'device_revoked', r ? 'device_revoked',
                                     'server_ts_is_text', jsonb_typeof(r -> 'results' -> 0 -> 'server_ts'))
             from _zc_r where label = 'push_a1'),
          '{"ok": true, "results": 1, "device_revoked": false, "server_ts_is_text": "string"}'::jsonb,
          'TI-72 5: the call itself answers ok with one result, a server_ts, and no device_revoked flag');
select is(pg_temp.ti_sync_n('ti-a'), 0::bigint, 'TI-73 5: the refused TEST identity has NO sync_operations row');
select is((select count(*) from pg_temp.ti_new_audit('push_a1')), 0::bigint,
          'TI-74 5: the refusal writes NO audit_events row (no sync.operation_rejected, no payment.denied)');
select is((select jsonb_build_object('identity', pg_temp.ti_payment_n('ti-a'), 'order', pg_temp.ti_order_payment_n('ti-o1'),
                                     'order_status', o.status, 'order_revision', o.revision)
             from public.orders o where o.id = pg_temp.zc_id('order-ti-o1')),
          '{"identity": 0, "order": 0, "order_status": "submitted", "order_revision": 1}'::jsonb,
          'TI-75 5: the refusal creates NO payment and leaves the named order untouched (no dispatch, no business write)');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('push_a1') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_recording_refused', '{}'::jsonb, pg_temp.ti_row_id('claim_a'),
            'employee', 'employee', pg_temp.zc_id('employee-1'), pg_temp.zc_id('device-1'))),
          'TI-76 5: the first refusal writes exactly one private test.card_recording_refused (mode test, the attempt''s scope and row, empty detail, 90-day retention)');

-- The identical repeat: the same answer, nothing new.
select pg_temp.ti_mark('push_a2');
set local role authenticated;
insert into _zc_r select 'push_a2', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ti-a'), pg_temp.zc_id('order-ti-o1'))));
reset role;
select is(pg_temp.ti_res('push_a2') - 'server_ts', pg_temp.ti_res('push_a1') - 'server_ts',
          'TI-77 5: a repeat push of the TEST identity gets the same answer');
select is((select jsonb_build_object('events', (select count(*) from pg_temp.ti_new_events('push_a2')),
                                     'audit', (select count(*) from pg_temp.ti_new_audit('push_a2')),
                                     'sync', pg_temp.ti_sync_n('ti-a'), 'payments', pg_temp.ti_payment_n('ti-a'),
                                     'refused_events', (select count(*) from app.card_provider_private_events e
                                                         where e.action = 'test.card_recording_refused'
                                                           and e.attempt_row_id = pg_temp.ti_row_id('claim_a')))),
          '{"events": 0, "audit": 0, "sync": 0, "payments": 0, "refused_events": 1}'::jsonb,
          'TI-78 5: the repeat writes no new private event (still exactly one test.card_recording_refused), no audit, no sync row, no payment');

-- Whatever the payload names (another order, the cash tender, another amount), the identity decides.
select pg_temp.ti_mark('push_a3');
set local role authenticated;
insert into _zc_r select 'push_a3', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ti-a'), pg_temp.zc_id('order-ti-o2'), 'cash', 5000)));
reset role;
select is(pg_temp.ti_res('push_a3') - 'server_ts', pg_temp.ti_refusal('ti-a', 'test_attempt_not_recordable', 'ti-o2'),
          'TI-79 5: the TEST identity is refused test_attempt_not_recordable whatever its payload names (cash tender, another order and amount)');
select is((select jsonb_build_object('events', (select count(*) from pg_temp.ti_new_events('push_a3')),
                                     'audit', (select count(*) from pg_temp.ti_new_audit('push_a3')),
                                     'sync', pg_temp.ti_sync_n('ti-a'), 'order_payments', pg_temp.ti_order_payment_n('ti-o2'))),
          '{"events": 0, "audit": 0, "sync": 0, "order_payments": 0}'::jsonb,
          'TI-80 5: the cash-tender variant writes no event, no audit, no sync row and no payment on the other order');

-- A kitchen PIN (staff 4) on the same device: permission_denied in the same shape.
select pg_temp.ti_mark('push_a_kitchen');
set local role authenticated;
insert into _zc_r select 'push_a_kitchen', pg_temp.zc_push(4, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ti-a'), pg_temp.zc_id('order-ti-o1'))));
reset role;
select is(pg_temp.ti_keys(pg_temp.ti_res('push_a_kitchen')), pg_temp.ti_refusal_keys(),
          'TI-81 5: the kitchen PIN''s answer has exactly the same key set');
select is(pg_temp.ti_res('push_a_kitchen') - 'server_ts', pg_temp.ti_refusal('ti-a', 'permission_denied', 'ti-o1'),
          'TI-82 5: a kitchen PIN (staff 4) pushing the TEST identity is answered permission_denied, status rejected, idempotency_replay false');
select is((select jsonb_build_object('events', (select count(*) from pg_temp.ti_new_events('push_a_kitchen')),
                                     'audit', (select count(*) from pg_temp.ti_new_audit('push_a_kitchen')),
                                     'sync', pg_temp.ti_sync_n('ti-a'), 'payments', pg_temp.ti_payment_n('ti-a'))),
          '{"events": 0, "audit": 0, "sync": 0, "payments": 0}'::jsonb,
          'TI-83 5: the kitchen refusal writes no audit, no sync row, no payment and no second private event');

-- A kitchen PIN as the FIRST refusal of another TEST attempt writes that attempt's single event (packet §11 item 10).
select pg_temp.ti_mark('push_d_kitchen');
set local role authenticated;
insert into _zc_r select 'push_d_kitchen', pg_temp.zc_push(4, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ti-d'), pg_temp.zc_id('order-ti-o1'))));
reset role;
select is(pg_temp.ti_res('push_d_kitchen') - 'server_ts', pg_temp.ti_refusal('ti-d', 'permission_denied', 'ti-o1'),
          'TI-84 5: a kitchen PIN pushing the declined TEST attempt''s identity is answered permission_denied in the same shape');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('push_d_kitchen') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_recording_refused', '{}'::jsonb, pg_temp.ti_row_id('claim_d'),
            'employee', 'employee', pg_temp.zc_id('employee-4'), pg_temp.zc_id('device-1'))),
          'TI-85 5: the permission_denied answer, as an attempt''s first refusal, writes its single test.card_recording_refused');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('push_d_kitchen')),
                                     'sync', pg_temp.ti_sync_n('ti-d'))),
          '{"audit": 0, "sync": 0}'::jsonb,
          'TI-86 5: the kitchen first refusal writes no audit and no sync row');

-- ===========================================================================
-- 8. A TEST attempt never blocks shift.close; never appears in the LIVE owner
--    read; appears only under p_mode 'test' with retention_until / incident_hold_at.
-- ===========================================================================
select is((select jsonb_agg(a.state order by a.state) from app.card_provider_attempts a
            where a.organization_id = pg_temp.zc_org() and a.device_id = pg_temp.zc_id('device-1')
              and a.mode = 'test' and a.state in ('sent', 'unknown', 'released') and a.resolution is null),
          '["released", "sent", "unknown"]'::jsonb,
          'TI-87 8: setup: d1 holds unresolved TEST attempts (one sent, one unknown, one released) while shift-1 is open');
select is((select jsonb_build_object('blocks_close', bool_or((app.card_attempt_derive(a) ->> 'blocks_close')::boolean),
                                     'claim_active', bool_or((app.card_attempt_derive(a) ->> 'claim_active')::boolean),
                                     'unresolved', count(*) filter (where (app.card_attempt_derive(a) ->> 'unresolved')::boolean))
             from app.card_provider_attempts a
            where a.organization_id = pg_temp.zc_org() and a.mode = 'test'),
          '{"blocks_close": false, "claim_active": false, "unresolved": 3}'::jsonb,
          'TI-88 8: every TEST attempt derives blocks_close false and claim_active false, the three unresolved ones included');
select is(app.card_shift_close_blocked(pg_temp.zc_org(), pg_temp.zc_id('shift-1')), false,
          'TI-89 8: the canonical close predicate does not block shift-1 for the unresolved TEST attempts');
select pg_temp.ti_mark('close');
set local role authenticated;
insert into _zc_r select 'close', pg_temp.zc_push(1, jsonb_build_array(jsonb_build_object(
  'local_operation_id', pg_temp.zc_lop('ti-close'), 'operation_type', 'shift.close', 'target_entity', 'shift',
  'target_id', pg_temp.zc_id('shift-1'), 'client_created_at', '2026-10-24T00:00:00Z',
  'payload', jsonb_build_object('shift_id', pg_temp.zc_id('shift-1'), 'counted_amount_minor', 0))));
reset role;
select is((select jsonb_build_object('ok', r -> 'results' -> 0 -> 'ok', 'status', r -> 'results' -> 0 -> 'status',
                                     'error', r -> 'results' -> 0 -> 'error',
                                     'shift_status', (select s.status from public.shifts s where s.id = pg_temp.zc_id('shift-1')))
             from _zc_r where label = 'close'),
          '{"ok": true, "status": "applied", "error": null, "shift_status": "closed"}'::jsonb,
          'TI-90 8: shift.close of shift-1 is applied (never card_payment_in_progress) while TEST attempts are unresolved on d1');
select is((select count(*) from pg_temp.ti_new_audit('close') e where e.action like 'card_attempt.%'), 0::bigint,
          'TI-91 8: the close writes no card_attempt.* audit row');

-- The owner read as the org_owner (staff 9) through a linked auth principal.
insert into auth.users (id, email) values (pg_temp.zc_id('ti-auth-owner'), 'zc001d-ti-owner@example.test');
update app_users set auth_user_id = pg_temp.zc_id('ti-auth-owner') where id = pg_temp.zc_id('user-9');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ti-auth-owner')::text, true);
select pg_temp.ti_mark('owner_read');
set local role authenticated;
insert into _zc_r select 'owner_live', public.owner_card_attempts(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
  now() - interval '1 day', now() + interval '1 day');
insert into _zc_r select 'owner_live_explicit', public.owner_card_attempts(pg_temp.zc_org(), pg_temp.zc_rest(),
  pg_temp.zc_branch(), now() - interval '1 day', now() + interval '1 day', 'live');
insert into _zc_r select 'owner_test', public.owner_card_attempts(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
  now() - interval '1 day', now() + interval '1 day', 'test');
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
select is((select jsonb_build_object('ok', r -> 'ok', 'mode', r -> 'mode', 'count', r -> 'count',
                                     'ids', (select jsonb_agg(e -> 'id') from jsonb_array_elements(r -> 'rows') e),
                                     'test_rows', (select count(*) from jsonb_array_elements(r -> 'rows') e
                                                    where e ->> 'mode' = 'test'))
             from _zc_r where label = 'owner_live'),
          jsonb_build_object('ok', true, 'mode', 'live', 'count', 1,
                             'ids', jsonb_build_array(pg_temp.ti_row_id('live_claim')), 'test_rows', 0),
          'TI-92 8: the default (LIVE) owner read lists only the LIVE attempt - no TEST attempt appears');
select is(pg_temp.ti_r('owner_live_explicit') -> 'rows', pg_temp.ti_r('owner_live') -> 'rows',
          'TI-93 8: p_mode ''live'' answers the same rows as the default');
select ok(not (pg_temp.ti_r('owner_live') -> 'rows' -> 0 ? 'retention_until')
          and not (pg_temp.ti_r('owner_live') -> 'rows' -> 0 ? 'incident_hold_at'),
          'TI-94 8: a LIVE owner-read row carries no retention_until / incident_hold_at key');
select set_eq($$select (e ->> 'id')::uuid from jsonb_array_elements(pg_temp.ti_r('owner_test') -> 'rows') e$$,
              $$select a.id from app.card_provider_attempts a where a.organization_id = pg_temp.zc_org() and a.mode = 'test'$$,
              'TI-95 8: the TEST owner read (p_mode ''test'') lists exactly the TEST attempts of the pilot organization');
select is((select jsonb_build_object('ok', r -> 'ok', 'mode', r -> 'mode',
                                     'non_test', (select count(*) from jsonb_array_elements(r -> 'rows') e
                                                   where e ->> 'mode' <> 'test'))
             from _zc_r where label = 'owner_test'),
          '{"ok": true, "mode": "test", "non_test": 0}'::jsonb,
          'TI-96 8: the TEST owner read answers mode test and holds no LIVE row');
select is(jsonb_build_object(
            'test_only', pg_temp.ti_sorted(array(
               select k from jsonb_object_keys(pg_temp.ti_r('owner_test') -> 'rows' -> 0) k
               except select k from jsonb_object_keys(pg_temp.ti_r('owner_live') -> 'rows' -> 0) k)),
            'live_only', pg_temp.ti_sorted(array(
               select k from jsonb_object_keys(pg_temp.ti_r('owner_live') -> 'rows' -> 0) k
               except select k from jsonb_object_keys(pg_temp.ti_r('owner_test') -> 'rows' -> 0) k))),
          '{"test_only": ["incident_hold_at", "retention_until"], "live_only": []}'::jsonb,
          'TI-97 8: a TEST owner-read row carries exactly the LIVE row''s keys plus retention_until and incident_hold_at');
select is((select count(*) from jsonb_array_elements(pg_temp.ti_r('owner_test') -> 'rows') e
            join app.card_provider_attempts a on a.id = (e ->> 'id')::uuid
           where (e ->> 'retention_until')::timestamptz = a.retention_until
             and e ? 'incident_hold_at' and e -> 'incident_hold_at' = 'null'::jsonb
             and e -> 'card_last4' = 'null'::jsonb and e -> 'card_brand_code' = 'null'::jsonb
             and e -> 'recorded' = 'false'::jsonb and e -> 'recoverable' = 'false'::jsonb
             and e -> 'order_id' = 'null'::jsonb and e -> 'shift_id' = 'null'::jsonb
             and e ->> 'classification' = 'test_' || a.state),
          (select count(*) from app.card_provider_attempts a where a.organization_id = pg_temp.zc_org() and a.mode = 'test'),
          'TI-98 8: every TEST owner-read row projects its retention_until and incident_hold_at (null), no card data, no order / shift, recorded / recoverable false, classification test_<state>');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('owner_read')),
                                     'events', (select count(*) from pg_temp.ti_new_events('owner_read')))),
          '{"audit": 0, "events": 0}'::jsonb,
          'TI-99 8: the owner reads write no audit and no private event');

-- ===========================================================================
-- 6. The purged identity: age the approved TEST attempt, purge it as the
--    operator, then the tombstone keeps the identity, the push is refused
--    silently and a claim of the identity is identity_in_use.
-- ===========================================================================
create temp table _ti_snap as
select a.organization_id, a.device_id, a.local_operation_id, a.provider_status_digest, a.provider_duplicate_digest,
       a.provider_key_format_version, a.provider_query_key, a.provider_duplicate_key
  from pg_temp.ti_attempt('ti-a') a;
-- Time travel (owner, rolled back with the file). NOTE: the fixture's pg_temp.zc_age_attempt sets
-- session_replication_role, which this database refuses to the non-superuser owner ("permission denied
-- to set parameter"), so the owner bypasses the one frozen-fact trigger for this one UPDATE instead.
alter table app.card_provider_attempts disable trigger card_attempts_guard;
update app.card_provider_attempts a
   set start_deadline_at = now() - interval '1 second', retention_until = now() - interval '1 second'
 where a.id = pg_temp.ti_row_id('claim_a') and a.mode = 'test';
alter table app.card_provider_attempts enable trigger card_attempts_guard;
select is((select count(*) from app.card_provider_attempts a
            where a.mode = 'test' and a.retention_until <= clock_timestamp() and a.incident_hold_at is null),
          1::bigint, 'TI-100 6: setup: exactly one expired, unheld TEST attempt (the approved one) awaits the purge');
select pg_temp.ti_mark('purge');
insert into _zc_r select 'purge', app.purge_expired_test_card_attempts('ZC001D synthetic purge', 'zc001d-op/ref-3',
  pg_temp.zc_owner());
select is(pg_temp.ti_r('purge') - 'cutoff',
          '{"ok": true, "attempts_purged": 1, "events_purged": 0, "attempts_deferred": 0, "events_deferred": 0, "devices_locked": 1}'::jsonb,
          'TI-101 6: the operator purge (attested owner) purges exactly the expired TEST attempt (C1-3: the batch locks its one device, d1, and defers nothing)');
select is(pg_temp.ti_attempt_n('ti-a'), 0::bigint, 'TI-102 6: the purged TEST attempt row is gone');
select results_eq($$select t.organization_id, t.device_id, t.local_operation_id, t.provider_status_digest,
                           t.provider_duplicate_digest, t.provider_key_format_version, t.provider_query_key,
                           t.provider_duplicate_key
                      from app.card_attempt_identity_tombstones t
                     where t.organization_id = pg_temp.zc_org() and t.device_id = pg_temp.zc_id('device-1')
                       and t.local_operation_id = pg_temp.zc_lop('ti-a')$$,
                  $$select * from _ti_snap$$,
                  'TI-103 6: a tombstone holds exactly the purged identity, both digests, the formatter version and both outbound keys');
select is((select jsonb_agg(jsonb_build_object('action', e.action, 'mode', e.mode, 'attempt_row_id', e.attempt_row_id,
                                               'detail', e.detail - 'cutoff', 'actor_kind', e.actor_kind,
                                               'actor_app_user_id', e.actor_app_user_id,
                                               'executor_is_session_user', e.executor_principal = session_user))
             from pg_temp.ti_new_events('purge') e),
          jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempts_purged', 'mode', null,
            'attempt_row_id', null,
            'detail', '{"attempts_purged": 1, "events_purged": 0, "attempts_deferred": 0, "events_deferred": 0, "devices_locked": 1}'::jsonb,
            'actor_kind', 'attested_owner_approver', 'actor_app_user_id', pg_temp.zc_owner(),
            'executor_is_session_user', true)),
          'TI-104 6: the purge writes only its operator.card_test_attempts_purged private event (attested owner, executor recorded; C1-3: the detail carries attempts_deferred, events_deferred and devices_locked)');
select is((select jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('purge')),
                                     'refused_event_kept', (select count(*) from app.card_provider_private_events e
                                                             where e.action = 'test.card_recording_refused'
                                                               and e.attempt_row_id = pg_temp.ti_row_id('claim_a')))),
          '{"audit": 0, "refused_event_kept": 1}'::jsonb,
          'TI-105 6: the purge writes no tenant audit; the attempt''s unexpired test.card_recording_refused stays');

select pg_temp.ti_mark('push_purged');
set local role authenticated;
insert into _zc_r select 'push_purged', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ti-a'), pg_temp.zc_id('order-ti-o1'))));
reset role;
select is(pg_temp.ti_keys(pg_temp.ti_res('push_purged')), pg_temp.ti_refusal_keys(),
          'TI-106 6: the push of the purged identity is answered in the exact refusal key set');
select is(pg_temp.ti_res('push_purged') - 'server_ts', pg_temp.ti_refusal('ti-a', 'test_attempt_not_recordable', 'ti-o1'),
          'TI-107 6: the push of the purged (tombstoned) identity is refused test_attempt_not_recordable');
select is((select jsonb_build_object('events', (select count(*) from pg_temp.ti_new_events('push_purged')),
                                     'audit', (select count(*) from pg_temp.ti_new_audit('push_purged')),
                                     'sync', pg_temp.ti_sync_n('ti-a'), 'payments', pg_temp.ti_payment_n('ti-a'))),
          '{"events": 0, "audit": 0, "sync": 0, "payments": 0}'::jsonb,
          'TI-108 6: the tombstone refusal writes NO new private event, no audit, no sync row and no payment');

select pg_temp.ti_mark('claim_purged');
set local role service_role;
insert into _zc_r select 'claim_purged', pg_temp.zc_claim(1, pg_temp.zc_lop('ti-a'), 'test', 1234);
reset role;
select is(pg_temp.ti_r('claim_purged') - 'server_ts', '{"ok": false, "error": "conflict", "detail": "identity_in_use"}'::jsonb,
          'TI-109 6: a claim of the purged identity is refused conflict/identity_in_use');
select is((select jsonb_build_object('rows', pg_temp.ti_attempt_n('ti-a'),
                                     'events', (select count(*) from pg_temp.ti_new_events('claim_purged')),
                                     'audit', (select count(*) from pg_temp.ti_new_audit('claim_purged')))),
          '{"rows": 0, "events": 0, "audit": 0}'::jsonb,
          'TI-110 6: the identity_in_use refusal recreates no ledger row and writes no event or audit');

-- ===========================================================================
-- 7. The revoked-device carve-out: a revoked device's push of a TEST identity is
--    recorded rejected / revoked_device as today, with no TEST refusal event.
-- ===========================================================================
update device_sessions set is_active = false, revoked_at = now() where id = pg_temp.zc_id('dsession-1');
select pg_temp.ti_mark('revoked');
set local role authenticated;
insert into _zc_r select 'push_revoked', pg_temp.zc_push(1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('ti-r'), pg_temp.zc_id('order-ti-o1'))));
reset role;
select is(pg_temp.ti_r('push_revoked') -> 'device_revoked', 'true'::jsonb,
          'TI-111 7: the revoked device''s call answers device_revoked true');
select is(pg_temp.ti_res('push_revoked'),
          jsonb_build_object('local_operation_id', pg_temp.zc_lop('ti-r'), 'operation_type', 'payment.create', 'ok', false,
                             'error', 'rejected', 'detail', 'revoked_device', 'status', 'rejected',
                             'idempotency_replay', false),
          'TI-112 7: the revoked device''s push of a TEST identity is answered rejected / revoked_device (not test_attempt_not_recordable)');
select is((select jsonb_agg(jsonb_build_object('status', so.status, 'rejection_reason', so.rejection_reason,
                                               'last_error_code', so.last_error_code, 'operation_type', so.operation_type,
                                               'result', so.result))
             from public.sync_operations so
            where so.organization_id = pg_temp.zc_org() and so.device_id = pg_temp.zc_id('device-1')
              and so.local_operation_id = pg_temp.zc_lop('ti-r')),
          '[{"status": "rejected", "rejection_reason": "revoked_device", "last_error_code": "revoked_device", "operation_type": "payment.create", "result": {"ok": false, "error": "rejected", "detail": "revoked_device"}}]'::jsonb,
          'TI-113 7: the push IS recorded in sync_operations as rejected / revoked_device (today''s behaviour)');
select is((select jsonb_agg(jsonb_build_object('action', e.action, 'reason', e.reason, 'device_id', e.device_id,
                                               'new_values', e.new_values))
             from pg_temp.ti_new_audit('revoked') e),
          jsonb_build_array(jsonb_build_object('action', 'sync.operation_rejected', 'reason', 'revoked_device',
            'device_id', pg_temp.zc_id('device-1'),
            'new_values', jsonb_build_object('local_operation_id', pg_temp.zc_lop('ti-r'), 'operation_type', 'payment.create',
                                             'reason', 'revoked_device'))),
          'TI-114 7: the revoked push writes exactly one sync.operation_rejected audit row (reason revoked_device)');
select is((select jsonb_build_object('new_events', (select count(*) from pg_temp.ti_new_events('revoked')),
                                     'refused_events', (select count(*) from app.card_provider_private_events e
                                                         where e.action = 'test.card_recording_refused'
                                                           and e.attempt_row_id = pg_temp.ti_row_id('claim_r')),
                                     'payments', pg_temp.ti_payment_n('ti-r'))),
          '{"new_events": 0, "refused_events": 0, "payments": 0}'::jsonb,
          'TI-115 7: the revoked path writes no test.card_recording_refused (no private event at all) and no payment');

-- ===========================================================================
-- Totals: zero TEST traces in the tenant audit or in payments.
-- ===========================================================================
select bag_eq($$select e.action from public.audit_events e
                 where e.organization_id = pg_temp.zc_org() and e.action like 'card_attempt.%'$$,
              $$values ('card_attempt.started'), ('card_attempt.declined')$$,
              'TI-116 totals: the only card_attempt.* audit rows of the pilot organization are the LIVE d2 attempt''s started / declined');
select bag_eq($$select e.action from pg_temp.ti_new_audit('test_phase') e$$,
              $$values ('shift.closed'), ('cash_drawer.closed'), ('sync.operation_rejected')$$,
              'TI-117 totals: since the TEST phase began the tenant audit holds only the shift close''s rows and the revoked-device rejection');
select is((select count(*) from public.payments p where p.organization_id = pg_temp.zc_org()), 0::bigint,
          'TI-118 totals: no payment exists in the pilot organization (no TEST attempt reached record_payment)');

-- ===========================================================================
-- Review fix 2 (supersedes packet §11 item 13 "no evidence"): a TEST attempt's
-- mark refused by its write-time proof with a proven scope (a kitchen_staff or
-- accountant PIN on the attempt's own POS) writes exactly one private
-- test.card_attempt_denied {rpc, denied_reason: permission_denied} for the
-- attempt (proof organization, p_device_id, p_attempt_id) and no tenant audit;
-- invalid_session (no proven scope), an unknown attempt id and another device's
-- call write nothing.
-- ===========================================================================
-- Every TEST attempt row before the first mark of this section: a refusal leaves each one identical.
create temp table _ti_pd_before as
select to_jsonb(a) as j from app.card_provider_attempts a
 where a.organization_id = pg_temp.zc_org() and a.mode = 'test';
create function pg_temp.ti_pd_unchanged() returns boolean language sql stable as $$
  select not exists ((select j from _ti_pd_before)
                     except all
                     (select to_jsonb(a) from app.card_provider_attempts a
                       where a.organization_id = pg_temp.zc_org() and a.mode = 'test'))
     and not exists ((select to_jsonb(a) from app.card_provider_attempts a
                       where a.organization_id = pg_temp.zc_org() and a.mode = 'test')
                     except all
                     (select j from _ti_pd_before)) $$;
select pg_temp.ti_mark('pd_section');

-- (a) d1's device session is still revoked (section 7): no proven scope, nothing written.
select pg_temp.ti_mark('pd_revoked');
set local role service_role;
insert into _zc_r select 'pd_revoked_rel', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-cap-eq'), pg_temp.zc_caller());
insert into _zc_r select 'pd_revoked_rec', public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-cap-eq'), 'permission_denied', pg_temp.zc_caller());
reset role;
select is(jsonb_build_object('release', pg_temp.ti_r('pd_revoked_rel') - 'server_ts',
                             'recording', pg_temp.ti_r('pd_revoked_rec') - 'server_ts',
                             'events', (select count(*) from pg_temp.ti_new_events('pd_revoked')),
                             'audit', (select count(*) from pg_temp.ti_new_audit('pd_revoked')),
                             'rows_unchanged', pg_temp.ti_pd_unchanged()),
          '{"release": {"ok": false, "error": "invalid_session"}, "recording": {"ok": false, "error": "invalid_session"}, "events": 0, "audit": 0, "rows_unchanged": true}'::jsonb,
          'TI-119 review fix 2: while d1''s device session is revoked (section 7) a kitchen PIN''s release and recording marks on the sent TEST attempt answer exactly {ok:false, error:invalid_session} (no proven scope) and write no private event, no tenant audit and no attempt change');

-- Restore d1's device session for the proven-scope cases (revoked again at the end of the section).
update device_sessions set is_active = true, revoked_at = null where id = pg_temp.zc_id('dsession-1');

-- (b) A kitchen PIN (staff 4) on d1: the release mark of the sent TEST attempt (which the body would stamp).
select pg_temp.ti_mark('pd_rel');
set local role service_role;
insert into _zc_r select 'pd_rel', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-cap-eq'), pg_temp.zc_caller());
reset role;
select is(pg_temp.ti_r('pd_rel') - 'server_ts', '{"ok": false, "error": "permission_denied"}'::jsonb,
          'TI-120 review fix 2: with the session restored, a kitchen PIN (staff 4) on d1 requesting release of the sent TEST attempt is refused by the write-time proof with exactly {ok:false, error:permission_denied}');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('pd_rel') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_attempt_denied',
            '{"rpc": "mark_release_requested", "denied_reason": "permission_denied"}'::jsonb, pg_temp.ti_row_id('cap_eq'),
            'employee', 'employee', pg_temp.zc_id('employee-4'), pg_temp.zc_id('device-1'))),
          'TI-121 review fix 2: that proof-level refusal writes exactly one private test.card_attempt_denied {rpc: mark_release_requested, denied_reason: permission_denied} on the attempt (mode test, kitchen employee actor, d1, pilot scope, 90-day retention, no hold)');
select is(jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('pd_rel')),
                             'rows_unchanged', pg_temp.ti_pd_unchanged()),
          '{"audit": 0, "rows_unchanged": true}'::jsonb,
          'TI-122 review fix 2: the refused TEST release request writes no tenant audit (no card_attempt.denied, no card_attempt.release_requested) and leaves every TEST attempt row identical (release_requested_at not stamped)');

-- (c) The same kitchen PIN: the recording mark of the same TEST attempt.
select pg_temp.ti_mark('pd_rec');
set local role service_role;
insert into _zc_r select 'pd_rec', public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-cap-eq'), 'permission_denied', pg_temp.zc_caller());
reset role;
select is(pg_temp.ti_r('pd_rec') - 'server_ts', '{"ok": false, "error": "permission_denied"}'::jsonb,
          'TI-123 review fix 2: the kitchen PIN''s recording mark of the sent TEST attempt is refused by the write-time proof with exactly {ok:false, error:permission_denied}');
select is((select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('pd_rec') e),
          jsonb_build_array(pg_temp.ti_ev_expect('test.card_attempt_denied',
            '{"rpc": "mark_recording_result", "denied_reason": "permission_denied"}'::jsonb, pg_temp.ti_row_id('cap_eq'),
            'employee', 'employee', pg_temp.zc_id('employee-4'), pg_temp.zc_id('device-1'))),
          'TI-124 review fix 2: that proof-level refusal writes exactly one private test.card_attempt_denied {rpc: mark_recording_result, denied_reason: permission_denied} on the attempt (mode test, kitchen employee actor, d1, pilot scope, 90-day retention, no hold)');
select is(jsonb_build_object('audit', (select count(*) from pg_temp.ti_new_audit('pd_rec')),
                             'rows_unchanged', pg_temp.ti_pd_unchanged()),
          '{"audit": 0, "rows_unchanged": true}'::jsonb,
          'TI-125 review fix 2: the refused TEST recording mark writes no tenant audit (no card_attempt.denied, no card_attempt.recording_refused) and leaves every TEST attempt row identical (no refusal_code / recording_refused_at)');

-- (d) An accountant PIN (staff 5) on d1: the release mark of the unknown TEST attempt.
select pg_temp.ti_mark('pd_acct');
set local role service_role;
insert into _zc_r select 'pd_acct', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-5'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-u'), pg_temp.zc_caller());
reset role;
select is(jsonb_build_object('r', pg_temp.ti_r('pd_acct') - 'server_ts',
                             'events', (select jsonb_agg(pg_temp.ti_ev(e)) from pg_temp.ti_new_events('pd_acct') e),
                             'audit', (select count(*) from pg_temp.ti_new_audit('pd_acct')),
                             'rows_unchanged', pg_temp.ti_pd_unchanged()),
          jsonb_build_object('r', '{"ok": false, "error": "permission_denied"}'::jsonb,
                             'events', jsonb_build_array(pg_temp.ti_ev_expect('test.card_attempt_denied',
                               '{"rpc": "mark_release_requested", "denied_reason": "permission_denied"}'::jsonb,
                               pg_temp.ti_row_id('claim_u'), 'employee', 'employee', pg_temp.zc_id('employee-5'),
                               pg_temp.zc_id('device-1'))),
                             'audit', 0, 'rows_unchanged', true),
          'TI-126 review fix 2: an accountant PIN (staff 5, also a proven-scope permission_denied) requesting release of the unknown TEST attempt answers exactly permission_denied and writes exactly one test.card_attempt_denied {rpc: mark_release_requested, denied_reason: permission_denied} on it (accountant actor), no tenant audit, no attempt change');

-- (e) A proven-scope refusal naming an attempt id with no row: nothing to evidence.
select pg_temp.ti_mark('pd_unknown');
set local role service_role;
insert into _zc_r select 'pd_unknown_rel', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-pd-unknown'), pg_temp.zc_caller());
insert into _zc_r select 'pd_unknown_rec', public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-pd-unknown'), 'permission_denied', pg_temp.zc_caller());
reset role;
select is(jsonb_build_object('release', pg_temp.ti_r('pd_unknown_rel') - 'server_ts',
                             'recording', pg_temp.ti_r('pd_unknown_rec') - 'server_ts',
                             'events', (select count(*) from pg_temp.ti_new_events('pd_unknown')),
                             'audit', (select count(*) from pg_temp.ti_new_audit('pd_unknown')),
                             'ledger_rows', pg_temp.ti_attempt_n('ti-pd-unknown'),
                             'rows_unchanged', pg_temp.ti_pd_unchanged()),
          '{"release": {"ok": false, "error": "permission_denied"}, "recording": {"ok": false, "error": "permission_denied"}, "events": 0, "audit": 0, "ledger_rows": 0, "rows_unchanged": true}'::jsonb,
          'TI-127 review fix 2: a kitchen PIN naming a canonical attempt id that has no ledger row answers permission_denied on both marks and writes nothing (no private event, no tenant audit, no ledger row, no attempt change)');

-- (f) The KDS device d3 (its proof is a proven-scope permission_denied: not a POS) naming d1's TEST attempt:
--     the evidence is bound to the calling device's attempt (organization, d3, attempt_id), which does not exist.
select pg_temp.ti_mark('pd_kds');
set local role service_role;
insert into _zc_r select 'pd_kds_rel', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-6'),
  pg_temp.zc_id('device-3'), 'zc-token-3', pg_temp.zc_lop('ti-cap-eq'), pg_temp.zc_caller());
insert into _zc_r select 'pd_kds_rec', public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-6'),
  pg_temp.zc_id('device-3'), 'zc-token-3', pg_temp.zc_lop('ti-cap-eq'), 'permission_denied', pg_temp.zc_caller());
reset role;
select is(jsonb_build_object('release', pg_temp.ti_r('pd_kds_rel') - 'server_ts',
                             'recording', pg_temp.ti_r('pd_kds_rec') - 'server_ts',
                             'events', (select count(*) from pg_temp.ti_new_events('pd_kds')),
                             'audit', (select count(*) from pg_temp.ti_new_audit('pd_kds')),
                             'rows_unchanged', pg_temp.ti_pd_unchanged()),
          '{"release": {"ok": false, "error": "permission_denied"}, "recording": {"ok": false, "error": "permission_denied"}, "events": 0, "audit": 0, "rows_unchanged": true}'::jsonb,
          'TI-128 review fix 2: the KDS device d3 (staff 6 PIN) naming d1''s sent TEST attempt is refused permission_denied on both marks and writes nothing - the evidence is bound to (proof organization, p_device_id = d3, attempt_id), which has no row');

-- (g) A forged device-session token on d1 (session valid again): no proven scope, nothing written.
select pg_temp.ti_mark('pd_forged');
set local role service_role;
insert into _zc_r select 'pd_forged_rel', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-forged', pg_temp.zc_lop('ti-cap-eq'), pg_temp.zc_caller());
insert into _zc_r select 'pd_forged_rec', public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-4'),
  pg_temp.zc_id('device-1'), 'zc-token-forged', pg_temp.zc_lop('ti-cap-eq'), 'permission_denied', pg_temp.zc_caller());
reset role;
select is(jsonb_build_object('release', pg_temp.ti_r('pd_forged_rel') - 'server_ts',
                             'recording', pg_temp.ti_r('pd_forged_rec') - 'server_ts',
                             'events', (select count(*) from pg_temp.ti_new_events('pd_forged')),
                             'audit', (select count(*) from pg_temp.ti_new_audit('pd_forged')),
                             'rows_unchanged', pg_temp.ti_pd_unchanged()),
          '{"release": {"ok": false, "error": "invalid_session"}, "recording": {"ok": false, "error": "invalid_session"}, "events": 0, "audit": 0, "rows_unchanged": true}'::jsonb,
          'TI-129 review fix 2: a kitchen PIN presenting a forged device-session token for d1 answers exactly invalid_session on both marks (no proven scope) and writes no private event, no tenant audit and no attempt change');

-- (h) Control: the cashier (staff 1, a proven role) makes the same release request on the same attempt.
select pg_temp.ti_mark('pd_control');
set local role service_role;
insert into _zc_r select 'pd_control', public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-1'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ti-cap-eq'), pg_temp.zc_caller());
reset role;
select is(jsonb_build_object('r', pg_temp.ti_r('pd_control') - 'server_ts',
                             'stamped', (select a.release_requested_at is not null from pg_temp.ti_attempt('ti-cap-eq') a),
                             'events', (select count(*) from pg_temp.ti_new_events('pd_control')),
                             'audit', (select count(*) from pg_temp.ti_new_audit('pd_control'))),
          jsonb_build_object('r', pg_temp.ti_env('ti-cap-eq', 'sent', 100000), 'stamped', true, 'events', 0, 'audit', 0),
          'TI-130 review fix 2 control: the same release request by the cashier (staff 1) on the same attempt is authorized - test_sent envelope, release_requested_at stamped - so the refusals above addressed an attempt the body acts on; the authorized TEST request writes no event and no tenant audit');

-- Section totals.
select bag_eq(
  $$select e.action, e.detail, e.actor_employee_profile_id, e.attempt_row_id, e.device_id
      from pg_temp.ti_new_events('pd_section') e$$,
  $$values ('test.card_attempt_denied', '{"rpc": "mark_release_requested", "denied_reason": "permission_denied"}'::jsonb,
            pg_temp.zc_id('employee-4'), pg_temp.ti_row_id('cap_eq'), pg_temp.zc_id('device-1')),
           ('test.card_attempt_denied', '{"rpc": "mark_recording_result", "denied_reason": "permission_denied"}'::jsonb,
            pg_temp.zc_id('employee-4'), pg_temp.ti_row_id('cap_eq'), pg_temp.zc_id('device-1')),
           ('test.card_attempt_denied', '{"rpc": "mark_release_requested", "denied_reason": "permission_denied"}'::jsonb,
            pg_temp.zc_id('employee-5'), pg_temp.ti_row_id('claim_u'), pg_temp.zc_id('device-1'))$$,
  'TI-131 review fix 2 totals: across this section the only new private events are those three test.card_attempt_denied rows (the kitchen release and recording marks of the sent attempt, the accountant release of the unknown attempt)');
select is((select count(*) from pg_temp.ti_new_audit('pd_section')), 0::bigint,
          'TI-132 review fix 2 totals: zero tenant audit_events rows of any action in the pilot organization across this section (no card_attempt.denied for any TEST mark refusal)');

-- Undo: d1's device session revoked again, as section 7 left it.
update device_sessions set is_active = false, revoked_at = now() where id = pg_temp.zc_id('dsession-1');

-- ===========================================================================
-- C1. Correction C1 (D-059 point 3): the bounded purge's result / event shape,
--     and every TEST private event names its device (CHECK
--     card_events_test_device, 23514), whichever writer tries otherwise.
-- ===========================================================================
select is(
  (select jsonb_build_object(
     'result_keys', pg_temp.ti_keys(pg_temp.ti_r('purge')),
     'detail_keys', pg_temp.ti_keys(e.detail),
     'same_cutoff', (pg_temp.ti_r('purge') ->> 'cutoff')::timestamptz = (e.detail ->> 'cutoff')::timestamptz,
     'detail_is_result_minus_ok', e.detail = pg_temp.ti_r('purge') - 'ok',
     'event_mode', e.mode, 'event_device', e.device_id, 'event_attempt', e.attempt_row_id)
     from app.card_provider_private_events e
    where e.organization_id = pg_temp.zc_org() and e.action = 'operator.card_test_attempts_purged'),
  jsonb_build_object(
     'result_keys', pg_temp.ti_sorted(array['ok', 'attempts_purged', 'events_purged', 'attempts_deferred',
                                            'events_deferred', 'devices_locked', 'cutoff']),
     'detail_keys', pg_temp.ti_sorted(array['attempts_purged', 'events_purged', 'attempts_deferred', 'events_deferred',
                                            'devices_locked', 'cutoff']),
     'same_cutoff', true, 'detail_is_result_minus_ok', true,
     'event_mode', null, 'event_device', null, 'event_attempt', null),
  'TI-133 C1-3: the purge answers exactly {ok, attempts_purged, events_purged, attempts_deferred, events_deferred, devices_locked, cutoff} and its one operator.card_test_attempts_purged event carries exactly the same six facts (same cut-off) as an operator event (mode NULL, no device, no attempt)');

select is(
  (select jsonb_build_object('test_events_present', count(*) > 0, 'test_events_without_device',
                             count(*) filter (where e.device_id is null))
     from app.card_provider_private_events e where e.mode = 'test'),
  '{"test_events_present": true, "test_events_without_device": 0}'::jsonb,
  'TI-134 C1-3: every TEST private event the flows of this file wrote names its device (none would fall outside a device-locked purge batch)');

select pg_temp.ti_mark('test_device_check');
select throws_ok(
  $$insert into app.card_provider_private_events (organization_id, restaurant_id, branch_id, attempt_row_id, mode,
        action, actor_kind, actor_reference, actor_employee_profile_id, device_id, detail, retention_until)
      values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), null, 'test', 'test.card_attempt_denied',
        'employee', 'employee', pg_temp.zc_id('employee-4'), null,
        '{"rpc": "claim", "denied_reason": "permission_denied"}'::jsonb, clock_timestamp() + interval '90 days')$$,
  '23514', 'new row for relation "card_provider_private_events" violates check constraint "card_events_test_device"',
  'TI-135 C1-3: a direct owner INSERT of an otherwise valid TEST private event (test.card_attempt_denied, 90-day retention) without device_id is refused 23514 by card_events_test_device');
select throws_ok(
  $$select app.card_private_event_write(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), null, 'test',
      'test.card_attempt_denied', 'employee', 'employee', null, null, pg_temp.zc_id('employee-4'), null, null,
      '{"rpc": "claim", "denied_reason": "permission_denied"}'::jsonb)$$,
  '23514', 'new row for relation "card_provider_private_events" violates check constraint "card_events_test_device"',
  'TI-136 C1-3: the private-event writer app.card_private_event_write cannot write a TEST event without a device either (23514, card_events_test_device)');
select throws_ok(
  $$select app.card_denial_evidence('test', pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
      pg_temp.zc_id('employee-4'), null, null, 'claim', 'permission_denied')$$,
  '23514', 'new row for relation "card_provider_private_events" violates check constraint "card_events_test_device"',
  'TI-137 C1-3: TEST denial evidence (app.card_denial_evidence in TEST mode) without a device is refused the same way (23514, card_events_test_device)');
select is(
  (select jsonb_build_object('events', (select count(*) from pg_temp.ti_new_events('test_device_check')),
                             'audit', (select count(*) from pg_temp.ti_new_audit('test_device_check')))),
  '{"events": 0, "audit": 0}'::jsonb,
  'TI-138 C1-3: the three refused TEST-event writes left no private event and no tenant audit row');

select lives_ok(
  $$insert into app.card_provider_private_events (organization_id, restaurant_id, branch_id, attempt_row_id, mode,
        action, actor_kind, actor_reference, actor_employee_profile_id, device_id, detail, retention_until)
      values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), null, 'test', 'test.card_attempt_denied',
                'employee', 'employee', pg_temp.zc_id('employee-4'), pg_temp.zc_id('device-1'),
                '{"rpc": "claim", "denied_reason": "permission_denied"}'::jsonb, clock_timestamp() + interval '90 days'),
             (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), null, 'live', 'security.card_credential_mismatch',
                'employee', 'employee', pg_temp.zc_id('employee-1'), null,
                '{"check": "mapping_mode", "source": "claim"}'::jsonb, null)$$,
  'TI-139 C1-3 controls: the identical TEST event WITH its device inserts, and a LIVE security event without a device still inserts (the CHECK binds mode test only)');
select is(
  (select jsonb_agg(jsonb_build_object('mode', e.mode, 'action', e.action, 'device_id', e.device_id) order by e.mode)
     from pg_temp.ti_new_events('test_device_check') e),
  jsonb_build_array(
    jsonb_build_object('mode', 'live', 'action', 'security.card_credential_mismatch', 'device_id', null),
    jsonb_build_object('mode', 'test', 'action', 'test.card_attempt_denied', 'device_id', pg_temp.zc_id('device-1'))),
  'TI-140 C1-3 controls: exactly those two rows were written (the TEST one names d1; the LIVE one has no device)');

select * from finish();
rollback;
