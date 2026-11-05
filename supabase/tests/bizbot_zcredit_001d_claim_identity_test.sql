-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: context proof, service-only claim, replay, identity, keys, adapter read and denial evidence (CI lane). Rollback-only synthetic fixtures, real SQL roles.
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
-- CI lane (claim_identity). Everything below runs as the migration owner
-- unless a block switches role; every switch is reset before its assertions.
-- ===========================================================================

-- d6: a pilot POS with no shift, no drawer and no binding; staff 11: a manager
-- whose PIN session is on d6 (a manager on neither originating till).
insert into devices (id, organization_id, restaurant_id, branch_id, device_type)
values (pg_temp.zc_id('device-6'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
values (pg_temp.zc_id('pairing-6'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
        pg_temp.zc_id('device-6'), 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                             session_token_ref, expires_at)
values (pg_temp.zc_id('dsession-6'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
        pg_temp.zc_id('device-6'), pg_temp.zc_id('pairing-6'), app.hash_provisioning_secret('zc-token-6'),
        now() + interval '30 days');
insert into app_users (id, email) values (pg_temp.zc_id('user-11'), 'zc001d-staff-11@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role)
values (pg_temp.zc_id('membership-11'), pg_temp.zc_id('user-11'), pg_temp.zc_org(), pg_temp.zc_rest(),
        pg_temp.zc_branch(), 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name)
values (pg_temp.zc_id('employee-11'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
        pg_temp.zc_id('user-11'), pg_temp.zc_id('membership-11'), 'ZC001D Staff 11');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id,
                          resolved_membership_id, expires_at)
values (pg_temp.zc_id('pin-11'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
        pg_temp.zc_id('dsession-6'), pg_temp.zc_id('employee-11'), pg_temp.zc_id('membership-11'),
        now() + interval '6 hours');

-- Setup guard: a refused operator / setup step aborts the file (never a silent misconfiguration).
create function pg_temp.ci_ok(r jsonb) returns jsonb language plpgsql as $$
begin
  if coalesce((r ->> 'ok')::boolean, false) is not true then
    raise exception 'CI setup step refused: %', r;
  end if;
  return r;
end $$;
create function pg_temp.ci_r(text) returns jsonb language sql stable as $$
  select r from _zc_r where label = $1 $$;

-- Row-set marks: "rows written by this call" is exact (ids unseen at the last mark).
create temp table _ci_seen (kind text not null, id uuid not null, primary key (kind, id));
create function pg_temp.ci_mark() returns void language sql volatile as $$
  insert into _ci_seen (kind, id) select 'ledger', a.id from app.card_provider_attempts a on conflict do nothing;
  insert into _ci_seen (kind, id) select 'event', e.id from app.card_provider_private_events e on conflict do nothing;
  insert into _ci_seen (kind, id) select 'audit', x.id from public.audit_events x
   where x.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b')) on conflict do nothing;
$$;
create function pg_temp.ci_new_ledger() returns setof app.card_provider_attempts language sql stable as $$
  select a.* from app.card_provider_attempts a
   where not exists (select 1 from _ci_seen s where s.kind = 'ledger' and s.id = a.id) $$;
create function pg_temp.ci_new_events() returns setof app.card_provider_private_events language sql stable as $$
  select e.* from app.card_provider_private_events e
   where not exists (select 1 from _ci_seen s where s.kind = 'event' and s.id = e.id) $$;
create function pg_temp.ci_new_audit() returns setof public.audit_events language sql stable as $$
  select x.* from public.audit_events x
   where x.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))
     and not exists (select 1 from _ci_seen s where s.kind = 'audit' and s.id = x.id) $$;
create function pg_temp.ci_new() returns jsonb language sql stable as $$
  select jsonb_build_object('ledger', (select count(*) from pg_temp.ci_new_ledger()),
                            'events', (select count(*) from pg_temp.ci_new_events()),
                            'audit', (select count(*) from pg_temp.ci_new_audit())) $$;
create function pg_temp.ci_none() returns jsonb language sql immutable as $$
  select '{"ledger": 0, "events": 0, "audit": 0}'::jsonb $$;
-- {answer (server_ts removed), written counts} of one captured call, and its expectation.
create function pg_temp.ci_outcome(p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('answer', pg_temp.ci_r(p_label) - 'server_ts', 'written', pg_temp.ci_new()) $$;
create function pg_temp.ci_expect(p_answer jsonb, p_ledger integer, p_events integer, p_audit integer)
returns jsonb language sql immutable as $$
  select jsonb_build_object('answer', p_answer, 'written',
    jsonb_build_object('ledger', p_ledger, 'events', p_events, 'audit', p_audit)) $$;
create function pg_temp.ci_refusal(p_error text, p_detail text default null) returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'error', p_error)
         || case when p_detail is null then '{}'::jsonb else jsonb_build_object('detail', p_detail) end $$;
-- The adapter-facing answers (claim, replay, adapter read): exactly the expected keys' values
-- (a missing key reads as JSON null), so a contract key absent or wrong fails.
create function pg_temp.ci_project(p_r jsonb, p_expected jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, coalesce(p_r -> k, 'null'::jsonb)), '{}'::jsonb)
    from jsonb_object_keys(p_expected) k $$;

-- Projections of the private events / tenant audit rows written since the last mark.
create function pg_temp.ci_event_proj(e app.card_provider_private_events) returns jsonb language sql stable as $$
  select jsonb_build_object('organization_id', e.organization_id, 'restaurant_id', e.restaurant_id,
    'branch_id', e.branch_id, 'attempt_row_id', e.attempt_row_id, 'mode', e.mode, 'action', e.action,
    'actor_kind', e.actor_kind, 'actor_reference', e.actor_reference, 'actor_app_user_id', e.actor_app_user_id,
    'executor_principal', e.executor_principal, 'actor_employee_profile_id', e.actor_employee_profile_id,
    'device_id', e.device_id, 'reason', e.reason, 'detail', e.detail,
    'retention', case when e.retention_until is null then 'none'
                      when e.retention_until = e.created_at + interval '90 days' then '90 days' else 'other' end,
    'held', e.incident_hold_at is not null or e.incident_hold_reference is not null) $$;
create function pg_temp.ci_new_events_proj() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(pg_temp.ci_event_proj(e) order by e.created_at, e.id), '[]'::jsonb)
    from pg_temp.ci_new_events() e $$;
-- The expected event: the proven scope of device p_d, actor employee p_emp (NULL = the device).
create function pg_temp.ci_event(p_action text, p_mode text, p_detail jsonb, p_emp integer, p_d integer,
                                 p_attempt uuid default null) returns jsonb language sql stable as $$
  select jsonb_build_object('organization_id', dv.organization_id, 'restaurant_id', dv.restaurant_id,
    'branch_id', dv.branch_id, 'attempt_row_id', p_attempt, 'mode', p_mode, 'action', p_action,
    'actor_kind', case when p_emp is null then 'device' else 'employee' end,
    'actor_reference', case when p_emp is null then 'device' else 'employee' end,
    'actor_app_user_id', null, 'executor_principal', null,
    'actor_employee_profile_id', case when p_emp is not null then pg_temp.zc_id('employee-' || p_emp) end,
    'device_id', dv.id, 'reason', null, 'detail', p_detail,
    'retention', case when p_mode = 'test' then '90 days' else 'none' end, 'held', false)
  from public.devices dv where dv.id = pg_temp.zc_id('device-' || p_d) $$;
create function pg_temp.ci_audit_proj(x public.audit_events) returns jsonb language sql stable as $$
  select jsonb_build_object('organization_id', x.organization_id, 'restaurant_id', x.restaurant_id,
    'branch_id', x.branch_id, 'actor_app_user_id', x.actor_app_user_id,
    'actor_employee_profile_id', x.actor_employee_profile_id, 'device_id', x.device_id, 'action', x.action,
    'reason', x.reason, 'old_values', x.old_values, 'new_values', x.new_values) $$;
create function pg_temp.ci_new_audit_proj() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(pg_temp.ci_audit_proj(x) order by x.action, x.id), '[]'::jsonb)
    from pg_temp.ci_new_audit() x $$;
create function pg_temp.ci_audit(p_action text, p_values jsonb, p_emp integer, p_d integer) returns jsonb
language sql stable as $$
  select jsonb_build_object('organization_id', dv.organization_id, 'restaurant_id', dv.restaurant_id,
    'branch_id', dv.branch_id, 'actor_app_user_id', null,
    'actor_employee_profile_id', case when p_emp is not null then pg_temp.zc_id('employee-' || p_emp) end,
    'device_id', dv.id, 'action', p_action, 'reason', null, 'old_values', null, 'new_values', p_values)
  from public.devices dv where dv.id = pg_temp.zc_id('device-' || p_d) $$;

-- The three §4.55 entry points with every argument overridable (staff n on its own device by default).
create function pg_temp.ci_claim(p_n integer, p_lop text, p_mode text, p_amount bigint default 1234,
    p_currency text default 'ILS', p_order uuid default null, p_rev integer default null, p_env text default null,
    p_terms jsonb default null, p_creds jsonb default null, p_version text default 'alpha16-l32-v1',
    p_d integer default null, p_token text default null)
returns jsonb language sql volatile as $$
  select public.card_attempt_claim(pg_temp.zc_id('pin-' || p_n),
    pg_temp.zc_id('device-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))),
    coalesce(p_token, 'zc-token-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))),
    p_lop, p_mode, p_amount, p_currency, p_order, p_rev,
    coalesce(p_env, case p_mode when 'live' then 'production' else 'test' end),
    coalesce(p_terms, pg_temp.zc_terminals(coalesce(p_d, pg_temp.zc_staff_device(p_n)), p_mode)),
    coalesce(p_creds, pg_temp.zc_credentials(coalesce(p_d, pg_temp.zc_staff_device(p_n)), p_mode)),
    p_version, pg_temp.zc_caller()) $$;
create function pg_temp.ci_ctx(p_n integer, p_order uuid default null, p_attempt text default null,
    p_d integer default null, p_token text default null)
returns jsonb language sql volatile as $$
  select public.card_attempt_context(pg_temp.zc_id('pin-' || p_n),
    pg_temp.zc_id('device-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))),
    coalesce(p_token, 'zc-token-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))), p_order, p_attempt) $$;
create function pg_temp.ci_read(p_n integer, p_attempt text, p_mode text default 'live', p_map_d integer default 1,
    p_env text default null, p_terms jsonb default null, p_creds jsonb default null,
    p_d integer default null, p_token text default null)
returns jsonb language sql volatile as $$
  select public.card_attempt_adapter_read(pg_temp.zc_id('pin-' || p_n),
    pg_temp.zc_id('device-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))),
    coalesce(p_token, 'zc-token-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))), p_attempt,
    coalesce(p_env, case p_mode when 'live' then 'production' else 'test' end),
    coalesce(p_terms, pg_temp.zc_terminals(p_map_d, p_mode)),
    coalesce(p_creds, pg_temp.zc_credentials(p_map_d, p_mode)), pg_temp.zc_caller()) $$;

-- Ledger row of (device p_d, identity p_lop), and independent digest / key computations.
create function pg_temp.ci_row(p_d integer, p_lop text) returns app.card_provider_attempts language sql stable as $$
  select a.* from app.card_provider_attempts a
   where a.device_id = pg_temp.zc_id('device-' || p_d) and a.local_operation_id = p_lop $$;
create function pg_temp.ci_rowj(p_d integer, p_lop text) returns jsonb language sql stable as $$
  select to_jsonb(a) from app.card_provider_attempts a
   where a.device_id = pg_temp.zc_id('device-' || p_d) and a.local_operation_id = p_lop $$;
create function pg_temp.ci_digest(p_purpose text, p_d integer, p_lop text) returns bytea language sql stable as $$
  select sha256(convert_to(p_purpose || '|' || dv.organization_id::text || '|' || dv.id::text || '|' || p_lop, 'UTF8'))
    from public.devices dv where dv.id = pg_temp.zc_id('device-' || p_d) $$;
create function pg_temp.ci_vlen(p_version text) returns integer language sql immutable as $$
  select case p_version when 'alpha16-l20-v1' then 20 when 'alpha16-l24-v1' then 24
                        when 'alpha16-l32-v1' then 32 end $$;
create function pg_temp.ci_key(p_digest bytea, p_version text) returns text language sql immutable as $$
  select translate(left(encode(p_digest, 'hex'), pg_temp.ci_vlen(p_version)), '0123456789abcdef', 'abcdefghijklmnop') $$;

-- Operator / owner setup helpers.
create function pg_temp.ci_lifecycle(p_d integer, p_mode text, p_lifecycle text, p_reason_code text default 'incident')
returns jsonb language sql volatile as $$
  select app.set_payment_terminal(pg_temp.zc_id('device-' || p_d), p_mode, 'zc-term-' || p_mode || '-' || p_d,
    'zc-cred-' || p_mode || '-' || p_d, p_lifecycle, p_reason_code, 'ZC001D synthetic binding', 'zc001d-op/ref-2',
    pg_temp.zc_owner()) $$;
-- Test setup only: retire every pilot binding through the lifecycle trigger directly
-- (the operator retirement gate is the lifecycle lane's subject, not this one's).
create function pg_temp.ci_retire_all() returns bigint language plpgsql volatile as $$
declare v bigint;
begin
  update app.payment_terminals set lifecycle = 'draining'
   where organization_id = pg_temp.zc_org() and lifecycle = 'enabled';
  update app.payment_terminals set lifecycle = 'retired'
   where organization_id = pg_temp.zc_org() and lifecycle in ('configured', 'draining');
  select count(*) into v from app.payment_terminals
   where organization_id = pg_temp.zc_org() and lifecycle <> 'retired';
  return v;
end $$;
create function pg_temp.ci_revision(p_enabled boolean, p_mode text, p_window timestamptz, p_test_cap bigint,
                                    p_live_cap bigint) returns bigint language sql volatile as $$
  insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode,
      window_until, max_test_amount_minor, max_live_amount_minor, reason, operator_reference,
      actor_app_user_id, executor_principal)
  values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), p_enabled, p_mode, p_window, p_test_cap,
      p_live_cap, 'ZC001D synthetic direct revision', 'zc001d-op/ref-ci', pg_temp.zc_owner(), 'postgres')
  returning revision $$;
create function pg_temp.ci_payment(p_order uuid, p_lop text, p_status text default 'completed') returns uuid
language sql volatile as $$
  insert into public.payments (organization_id, restaurant_id, branch_id, order_id, device_id,
      taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id, method, status,
      amount_minor, tendered_minor, change_minor, currency_code, local_operation_id)
  select dv.organization_id, dv.restaurant_id, dv.branch_id, p_order, dv.id, pg_temp.zc_id('employee-1'),
      pg_temp.zc_id('membership-1'), pg_temp.zc_id('shift-1'), pg_temp.zc_id('drawer-' || dv.id), 'cash', p_status,
      1234, 1234, 0, 'ILS', p_lop
    from public.devices dv where dv.id = pg_temp.zc_id('device-1')
  returning id $$;
create function pg_temp.ci_sync_row(p_lop text) returns uuid language sql volatile as $$
  insert into public.sync_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
      operation_type, payload, payload_fingerprint, status)
  select dv.organization_id, dv.restaurant_id, dv.branch_id, dv.id, p_lop, 'order.status', '{}'::jsonb,
      'zc001d-ci-synthetic', 'rejected'
    from public.devices dv where dv.id = pg_temp.zc_id('device-1')
  returning id $$;
create function pg_temp.ci_tombstone(p_d integer, p_lop text, p_version text default 'alpha16-l32-v1',
                                     p_query_key text default null) returns void language sql volatile as $$
  insert into app.card_attempt_identity_tombstones (organization_id, device_id, local_operation_id,
      provider_status_digest, provider_duplicate_digest, provider_key_format_version, provider_query_key,
      provider_duplicate_key)
  select dv.organization_id, dv.id, p_lop, pg_temp.ci_digest('card-status-key/v1', p_d, p_lop),
      pg_temp.ci_digest('card-duplicate-key/v1', p_d, p_lop), p_version,
      coalesce(p_query_key, pg_temp.ci_key(pg_temp.ci_digest('card-status-key/v1', p_d, p_lop), p_version)),
      pg_temp.ci_key(pg_temp.ci_digest('card-duplicate-key/v1', p_d, p_lop), p_version)
    from public.devices dv where dv.id = pg_temp.zc_id('device-' || p_d) $$;
-- A TEST ledger row planted directly by the owner (staff p_n's employee / membership as initiator);
-- its digests / keys default to its own identity's real values and can be overridden.
create function pg_temp.ci_plant(p_d integer, p_lop text, p_n integer, p_status_digest bytea default null,
    p_dup_digest bytea default null, p_query_key text default null, p_dup_key text default null)
returns uuid language sql volatile as $$
  insert into app.card_provider_attempts (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
      initiated_by_employee_profile_id, initiated_by_membership_id, mode, state, amount_minor, currency_code,
      terminal_ref, credential_ref, provider_status_digest, provider_duplicate_digest, provider_key_format_version,
      provider_query_key, provider_duplicate_key, retention_until, start_deadline_at)
  select dv.organization_id, dv.restaurant_id, dv.branch_id, dv.id, p_lop,
      pg_temp.zc_id('employee-' || p_n), pg_temp.zc_id('membership-' || p_n), 'test', 'sent', 1234, 'ILS',
      'zc-term-test-' || p_d, 'zc-cred-test-' || p_d,
      coalesce(p_status_digest, pg_temp.ci_digest('card-status-key/v1', p_d, p_lop)),
      coalesce(p_dup_digest, pg_temp.ci_digest('card-duplicate-key/v1', p_d, p_lop)), 'alpha16-l32-v1',
      coalesce(p_query_key, pg_temp.ci_key(pg_temp.ci_digest('card-status-key/v1', p_d, p_lop), 'alpha16-l32-v1')),
      coalesce(p_dup_key, pg_temp.ci_key(pg_temp.ci_digest('card-duplicate-key/v1', p_d, p_lop), 'alpha16-l32-v1')),
      now() + interval '90 days', now() + interval '120 seconds'
    from public.devices dv where dv.id = pg_temp.zc_id('device-' || p_d)
  returning id $$;

-- ===========================================================================
-- 1. card_attempt_context — refusals (caller JWT, request shape, SQL proof).
-- ===========================================================================
select pg_temp.zc_order('ci-ctx', 1234) is not null as ci_order_ctx;
select pg_temp.ci_mark();

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
insert into _zc_r values ('ctx_no_jwt', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-ctx')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
select is(pg_temp.ci_r('ctx_no_jwt') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-001 context: no caller JWT principal (request.jwt.claim.sub empty, auth.uid() NULL) -> {ok:false, error:invalid_session}, no proven scope');

set local role authenticated;
insert into _zc_r values
  ('ctx_bad_id_text', pg_temp.ci_ctx(1, p_attempt => 'not-a-uuid')),
  ('ctx_bad_id_upper', pg_temp.ci_ctx(1, p_attempt => 'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D')),
  ('ctx_bad_id_v1', pg_temp.ci_ctx(1, p_attempt => '6ba7b810-9dad-11d1-80b4-00c04fd430c8')),
  ('ctx_bad_id_braced', pg_temp.ci_ctx(1, p_attempt => '{' || pg_temp.zc_lop('ci-ctx-braced') || '}')),
  ('ctx_bad_id_empty', pg_temp.ci_ctx(1, p_attempt => '')),
  ('ctx_bad_id_forged', pg_temp.ci_ctx(1, p_attempt => 'not-a-uuid', p_token => 'zc-token-forged'));
reset role;
select is(pg_temp.ci_r('ctx_bad_id_text') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-002 context: a non-UUID attempt id -> invalid_request');
select is(pg_temp.ci_r('ctx_bad_id_upper') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-003 context: an upper-case UUID attempt id (not canonical lowercase) -> invalid_request');
select is(pg_temp.ci_r('ctx_bad_id_v1') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-004 context: a version-1 UUID attempt id (not UUID v4) -> invalid_request');
select is(pg_temp.ci_r('ctx_bad_id_braced') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-005 context: a braced UUID attempt id -> invalid_request');
select is(pg_temp.ci_r('ctx_bad_id_empty') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-006 context: an empty attempt id -> invalid_request');
select is(pg_temp.ci_r('ctx_bad_id_forged') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-007 context: the attempt-id shape is refused before the session proof (malformed id + forged token -> invalid_request)');

set local role authenticated;
insert into _zc_r values
  ('ctx_forged_token', pg_temp.ci_ctx(1, p_token => 'zc-token-forged')),
  ('ctx_other_device_token', pg_temp.ci_ctx(1, p_token => 'zc-token-2')),
  ('ctx_pin_wrong_device', pg_temp.ci_ctx(1, p_d => 2)),
  ('ctx_foreign_pin', pg_temp.ci_ctx(7, p_d => 1)),
  ('ctx_kitchen', pg_temp.ci_ctx(4)),
  ('ctx_kds', pg_temp.ci_ctx(6)),
  ('ctx_accountant', pg_temp.ci_ctx(5));
reset role;
update device_pairings set status = 'revoked', revoked_at = now() where id = pg_temp.zc_id('pairing-1');
set local role authenticated;
insert into _zc_r values ('ctx_revoked_pairing', pg_temp.ci_ctx(1));
reset role;
update device_pairings set status = 'active', revoked_at = null where id = pg_temp.zc_id('pairing-1');
update device_sessions set revoked_at = now() where id = pg_temp.zc_id('dsession-1');
set local role authenticated;
insert into _zc_r values ('ctx_revoked_session', pg_temp.ci_ctx(1));
reset role;
update device_sessions set revoked_at = null where id = pg_temp.zc_id('dsession-1');
update pin_sessions set expires_at = now() - interval '1 minute' where id = pg_temp.zc_id('pin-1');
set local role authenticated;
insert into _zc_r values ('ctx_expired_pin', pg_temp.ci_ctx(1));
reset role;
update pin_sessions set expires_at = now() + interval '6 hours' where id = pg_temp.zc_id('pin-1');
update memberships set status = 'revoked', deleted_at = now() where id = pg_temp.zc_id('membership-1');
set local role authenticated;
insert into _zc_r values ('ctx_revoked_membership', pg_temp.ci_ctx(1));
reset role;
update memberships set status = 'active', deleted_at = null where id = pg_temp.zc_id('membership-1');
update employee_profiles set employment_status = 'suspended' where id = pg_temp.zc_id('employee-1');
set local role authenticated;
insert into _zc_r values ('ctx_suspended_employee', pg_temp.ci_ctx(1));
reset role;
update employee_profiles set employment_status = 'active' where id = pg_temp.zc_id('employee-1');
update devices set is_active = false where id = pg_temp.zc_id('device-1');
set local role authenticated;
insert into _zc_r values ('ctx_inactive_device', pg_temp.ci_ctx(1));
reset role;
update devices set is_active = true where id = pg_temp.zc_id('device-1');

select is(pg_temp.ci_r('ctx_forged_token') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-008 context: a forged device-session token -> invalid_session');
select is(pg_temp.ci_r('ctx_other_device_token') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-009 context: d1 presented with the token of d2 -> invalid_session');
select is(pg_temp.ci_r('ctx_pin_wrong_device') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-010 context: the PIN session of d1 presented on d2 (wrong device for the PIN) -> invalid_session');
select is(pg_temp.ci_r('ctx_foreign_pin') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-011 context: a foreign-organization PIN (staff 7) presented on pilot d1 -> invalid_session');
select is(pg_temp.ci_r('ctx_revoked_pairing') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-012 context: a revoked device pairing -> invalid_session');
select is(pg_temp.ci_r('ctx_revoked_session') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-013 context: a revoked device session -> invalid_session');
select is(pg_temp.ci_r('ctx_expired_pin') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-014 context: an expired PIN session -> invalid_session');
select is(pg_temp.ci_r('ctx_revoked_membership') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-015 context: a revoked membership (status revoked + deleted_at) -> invalid_session');
select is(pg_temp.ci_r('ctx_suspended_employee') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-016 context: an inactive (suspended) employee profile -> invalid_session');
select is(pg_temp.ci_r('ctx_inactive_device') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-017 context: an inactive device -> invalid_session');
select is(pg_temp.ci_r('ctx_kitchen') - 'server_ts', pg_temp.ci_refusal('permission_denied'),
  'CI-018 context: a kitchen_staff PIN on the POS (staff 4) -> {ok:false, error:permission_denied}, no proven scope disclosed');
select is(pg_temp.ci_r('ctx_kds') - 'server_ts', pg_temp.ci_refusal('permission_denied'),
  'CI-019 context: a PIN on the KDS device d3 (staff 6, device type kds) -> {ok:false, error:permission_denied}, no proven scope disclosed');
select is(pg_temp.ci_r('ctx_accountant') - 'server_ts', pg_temp.ci_refusal('permission_denied'),
  'CI-020 context: an accountant PIN (staff 5) -> permission_denied');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-021 context: none of the refusals above wrote a ledger, private-event or tenant audit row');

-- ===========================================================================
-- 2. card_attempt_context — success (no revision, no binding yet).
-- ===========================================================================
select pg_temp.zc_order('ci-ctx-zero', 0) is not null as zero,
       pg_temp.zc_order('ci-ctx-sib', 1234, 5) is not null as sibling,
       pg_temp.zc_order('ci-ctx-foreign', 1234, 4) is not null as foreign_org;
select pg_temp.ci_mark();
set local role authenticated;
insert into _zc_r values
  ('ctx_ok', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-ctx'))),
  ('ctx_ok_zero', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-ctx-zero'))),
  ('ctx_ok_sibling_order', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-ctx-sib'))),
  ('ctx_ok_foreign_order', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-ctx-foreign'))),
  ('ctx_ok_unknown_attempt', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-ctx-none'))),
  ('ctx_ok_manager', pg_temp.ci_ctx(2)),
  ('ctx_ok_owner', pg_temp.ci_ctx(9));
reset role;
select is((select array_agg(k order by k) from jsonb_object_keys(pg_temp.ci_r('ctx_ok')) k),
  array['attempt', 'branch_id', 'caller_auth_user_id', 'card_terminal_enabled', 'device_id', 'employee_profile_id',
        'membership_id', 'ok', 'order', 'organization_id', 'restaurant_id', 'role', 'server_ts', 'terminal'],
  'CI-022 context success: the answer carries exactly scope ids, role, employee / membership, order, attempt, terminal posture, server_ts and (C2: + caller_auth_user_id) the original-caller binding');
select is(pg_temp.ci_r('ctx_ok') - 'server_ts' - 'order', jsonb_build_object('ok', true,
    'caller_auth_user_id', pg_temp.zc_id('transport-principal'),
    'organization_id', pg_temp.zc_org(), 'restaurant_id', pg_temp.zc_rest(), 'branch_id', pg_temp.zc_branch(),
    'device_id', pg_temp.zc_id('device-1'), 'role', 'cashier', 'employee_profile_id', pg_temp.zc_id('employee-1'),
    'membership_id', pg_temp.zc_id('membership-1'), 'attempt', null, 'terminal', null, 'card_terminal_enabled', false),
  'CI-023 context success: the proven scope ids, role cashier, the employee / membership of staff 1; attempt null; no mapping -> terminal hidden, starts not enabled (C2: + caller_auth_user_id = auth.uid(), the transport principal of the fixture JWT)');
select is(pg_temp.ci_r('ctx_ok') -> 'order', jsonb_build_object('order_id', pg_temp.zc_id('order-ci-ctx'),
    'status', 'submitted', 'grand_total_minor', 1234, 'currency_code', 'ILS', 'revision', 1,
    'active_claim', false, 'settled', false),
  'CI-024 context success: the order facts (status, total, currency, revision, active_claim false, settled false)');
select is(pg_temp.ci_r('ctx_ok_zero') -> 'order' -> 'settled', 'true'::jsonb,
  'CI-025 context: a zero-total order is reported settled');
select is(pg_temp.ci_r('ctx_ok_sibling_order') -> 'order', 'null'::jsonb,
  'CI-026 context: an order of the sibling branch is outside the proven branch (order null)');
select is(pg_temp.ci_r('ctx_ok_foreign_order') -> 'order', 'null'::jsonb,
  'CI-027 context: an order of a foreign organization is not projected (order null)');
select ok(pg_temp.ci_r('ctx_ok_unknown_attempt') ->> 'ok' = 'true'
          and pg_temp.ci_r('ctx_ok_unknown_attempt') -> 'attempt' = 'null'::jsonb,
  'CI-028 context: an unknown (well-formed) attempt id on the own till answers ok with attempt null');
select is(pg_temp.ci_r('ctx_ok_manager') ->> 'role', 'manager', 'CI-029 context: a manager PIN is admitted (role manager)');
select is(pg_temp.ci_r('ctx_ok_owner') ->> 'role', 'org_owner', 'CI-030 context: an org_owner PIN is admitted (role org_owner)');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-031 context success: no ledger, private-event or tenant audit row written');

-- ===========================================================================
-- 3. card_attempt_claim — request shape, unknown device, no revision (no config).
-- ===========================================================================
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cl_shape_text_id', pg_temp.ci_claim(1, 'not-a-uuid', 'live', p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_upper_id', pg_temp.ci_claim(1, 'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D', 'live',
                                         p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_null_id', pg_temp.ci_claim(1, null, 'live', p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_mode', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'other', p_order => pg_temp.zc_id('order-ci-ctx'),
                                     p_rev => 1)),
  ('cl_shape_null_mode', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), null, p_order => pg_temp.zc_id('order-ci-ctx'),
                                          p_rev => 1, p_terms => '{}'::jsonb, p_creds => '{}'::jsonb)),
  ('cl_shape_test_order', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'test', p_order => pg_temp.zc_id('order-ci-ctx'))),
  ('cl_shape_test_rev', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'test', p_rev => 1)),
  ('cl_shape_live_no_order', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', p_rev => 1)),
  ('cl_shape_live_no_rev', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', p_order => pg_temp.zc_id('order-ci-ctx'))),
  ('cl_shape_amount_zero', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', 0,
                                            p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_amount_negative', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', -5,
                                                p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_amount_huge', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', 100000000000,
                                            p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_amount_null', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', null,
                                            p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_currency_lower', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', p_currency => 'ils',
                                               p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_currency_long', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', p_currency => 'ILSX',
                                              p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_shape_currency_null', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', p_currency => null,
                                              p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1)),
  ('cl_order_shape_first', pg_temp.ci_claim(1, 'not-a-uuid', 'live', p_order => pg_temp.zc_id('order-ci-ctx'),
                                            p_rev => 1, p_version => 'alpha16-l40-v1')),
  ('cl_order_version_first', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live',
                                              p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1, p_version => null,
                                              p_token => 'zc-token-forged')),
  ('cl_unknown_device', public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-unknown'),
      'zc-token-1', pg_temp.zc_lop('ci-shape'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-ctx'), 1, 'production',
      pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller())),
  ('cl_no_revision', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-shape'), 'live', p_order => pg_temp.zc_id('order-ci-ctx'),
                                      p_rev => 1));
reset role;
select is(pg_temp.ci_r('cl_shape_text_id') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-032 claim shape: a non-UUID attempt id -> invalid_request');
select is(pg_temp.ci_r('cl_shape_upper_id') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-033 claim shape: an upper-case UUID attempt id -> invalid_request');
select is(pg_temp.ci_r('cl_shape_null_id') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-034 claim shape: a NULL attempt id -> invalid_request');
select is(pg_temp.ci_r('cl_shape_mode') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-035 claim shape: a mode outside test / live -> invalid_request');
select is(pg_temp.ci_r('cl_shape_null_mode') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-036 claim shape: a NULL mode -> invalid_request');
select is(pg_temp.ci_r('cl_shape_test_order') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-037 claim shape: TEST with an order_id -> invalid_request');
select is(pg_temp.ci_r('cl_shape_test_rev') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-038 claim shape: TEST with an expected_revision -> invalid_request');
select is(pg_temp.ci_r('cl_shape_live_no_order') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-039 claim shape: LIVE without an order_id -> invalid_request');
select is(pg_temp.ci_r('cl_shape_live_no_rev') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-040 claim shape: LIVE without an expected_revision -> invalid_request');
select is(pg_temp.ci_r('cl_shape_amount_zero') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-041 claim shape: amount 0 -> invalid_request');
select is(pg_temp.ci_r('cl_shape_amount_negative') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-042 claim shape: a negative amount -> invalid_request');
select is(pg_temp.ci_r('cl_shape_amount_huge') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-043 claim shape: an amount above 99 999 999 999 minor units -> invalid_request');
select is(pg_temp.ci_r('cl_shape_amount_null') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-044 claim shape: a NULL amount -> invalid_request');
select is(pg_temp.ci_r('cl_shape_currency_lower') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-045 claim shape: a lower-case currency -> invalid_request');
select is(pg_temp.ci_r('cl_shape_currency_long') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-046 claim shape: a four-letter currency -> invalid_request');
select is(pg_temp.ci_r('cl_shape_currency_null') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-047 claim shape: a NULL currency -> invalid_request');
select is(pg_temp.ci_r('cl_order_shape_first') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-048 claim order: the request shape is refused before the key-format check (bad id + unknown version -> invalid_request)');
select is(pg_temp.ci_r('cl_order_version_first') - 'server_ts', pg_temp.ci_refusal('provider_unavailable'),
  'CI-049 claim order: the key-format version is refused before any proof (NULL version + forged token -> provider_unavailable)');
select is(pg_temp.ci_r('cl_unknown_device') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-050 claim: an unknown device id -> invalid_session');
select is(pg_temp.ci_r('cl_no_revision') - 'server_ts', pg_temp.ci_refusal('card_payments_disabled'),
  'CI-051 claim: no operator revision (the default-OFF pilot) -> card_payments_disabled');
select is((select count(*) from _zc_r where starts_with(label, 'cl_') and jsonb_typeof(r -> 'server_ts') is distinct from 'string'),
  0::bigint, 'CI-052 claim: every refusal above carries a server_ts');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-053 claim: no shape, version, unknown-device or no-revision refusal wrote a ledger, private-event or audit row');

-- ===========================================================================
-- 4. Service-only re-proof at write time (no JWT gate, no renewal) and the
--    denial evidence of a proven permission_denied.
-- ===========================================================================
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('rp_forged', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'live', p_order => pg_temp.zc_id('order-ci-ctx'),
                                 p_rev => 1, p_token => 'zc-token-forged')),
  ('rp_forged_test', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'test', p_token => 'zc-token-forged')),
  ('rp_pin_wrong_device', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'live', p_order => pg_temp.zc_id('order-ci-ctx'),
                                           p_rev => 1, p_d => 2)),
  ('rp_foreign_pin', pg_temp.ci_claim(7, pg_temp.zc_lop('ci-rp'), 'live', p_order => pg_temp.zc_id('order-ci-ctx'),
                                      p_rev => 1, p_d => 1));
reset role;
update memberships set status = 'revoked', deleted_at = now() where id = pg_temp.zc_id('membership-1');
set local role service_role;
insert into _zc_r values ('rp_revoked_membership', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
update memberships set status = 'active', deleted_at = null where id = pg_temp.zc_id('membership-1');
update pin_sessions set expires_at = now() - interval '1 minute' where id = pg_temp.zc_id('pin-1');
set local role service_role;
insert into _zc_r values ('rp_expired_pin', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
update pin_sessions set expires_at = now() + interval '6 hours' where id = pg_temp.zc_id('pin-1');
update device_sessions set revoked_at = now() where id = pg_temp.zc_id('dsession-1');
set local role service_role;
insert into _zc_r values ('rp_revoked_session', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
update device_sessions set revoked_at = null where id = pg_temp.zc_id('dsession-1');
update device_pairings set status = 'revoked', revoked_at = now() where id = pg_temp.zc_id('pairing-1');
set local role service_role;
insert into _zc_r values ('rp_revoked_pairing', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
update device_pairings set status = 'active', revoked_at = null where id = pg_temp.zc_id('pairing-1');
update employee_profiles set employment_status = 'suspended' where id = pg_temp.zc_id('employee-1');
set local role service_role;
insert into _zc_r values ('rp_suspended_employee', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rp'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
update employee_profiles set employment_status = 'active' where id = pg_temp.zc_id('employee-1');
select is(pg_temp.ci_r('rp_forged') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-054 re-proof: a forged device-session token at write time -> invalid_session');
select is(pg_temp.ci_r('rp_forged_test') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-055 re-proof: a forged token on a TEST claim -> invalid_session');
select is(pg_temp.ci_r('rp_pin_wrong_device') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-056 re-proof: the PIN of d1 presented with d2 and its token -> invalid_session');
select is(pg_temp.ci_r('rp_foreign_pin') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-057 re-proof: a foreign-organization PIN presented with d1 -> invalid_session');
select is(pg_temp.ci_r('rp_revoked_membership') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-058 re-proof: a membership revoked after the context proof (status revoked + deleted_at) -> invalid_session');
select is(pg_temp.ci_r('rp_expired_pin') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-059 re-proof: a PIN session expired at write time -> invalid_session');
select is(pg_temp.ci_r('rp_revoked_session') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-060 re-proof: a revoked device session -> invalid_session');
select is(pg_temp.ci_r('rp_revoked_pairing') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-061 re-proof: a revoked device pairing -> invalid_session');
select is(pg_temp.ci_r('rp_suspended_employee') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-062 re-proof: a suspended employee -> invalid_session');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-063 re-proof: an invalid_session carries no proven scope and writes no evidence (no ledger, event or audit row)');

select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('rp_kitchen_live', pg_temp.ci_claim(4, pg_temp.zc_lop('ci-rp-kitchen'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('rp_kitchen_live'), pg_temp.ci_expect(pg_temp.ci_refusal('permission_denied'), 0, 0, 1),
  'CI-064 re-proof: a kitchen_staff PIN (staff 4) on d1 for a LIVE claim -> permission_denied, no ledger row, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "permission_denied"}'::jsonb, 4, 1)),
  'CI-065 re-proof: that row is exactly card_attempt.denied {denied_reason: permission_denied} by employee 4 on d1, reason NULL');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('rp_kitchen_test', pg_temp.ci_claim(4, pg_temp.zc_lop('ci-rp-kitchen-t'), 'test'));
reset role;
select is(pg_temp.ci_outcome('rp_kitchen_test'), pg_temp.ci_expect(pg_temp.ci_refusal('permission_denied'), 0, 1, 0),
  'CI-066 re-proof: the kitchen PIN on a TEST claim -> permission_denied with one private event and no tenant audit');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('test.card_attempt_denied', 'test',
    '{"rpc": "claim", "denied_reason": "permission_denied"}'::jsonb, 4, 1)),
  'CI-067 re-proof: that event is test.card_attempt_denied {rpc: claim, denied_reason: permission_denied}, actor employee 4, 90-day retention');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('rp_kds_live', pg_temp.ci_claim(6, pg_temp.zc_lop('ci-rp-kds'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('rp_kds_live'), pg_temp.ci_expect(pg_temp.ci_refusal('permission_denied'), 0, 0, 1),
  'CI-068 re-proof: the KDS device d3 (staff 6) on a LIVE claim -> permission_denied, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "permission_denied"}'::jsonb, null, 3)),
  'CI-069 re-proof: the KDS denial evidence names the device (actor employee NULL, device d3)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('rp_kds_test', pg_temp.ci_claim(6, pg_temp.zc_lop('ci-rp-kds-t'), 'test'));
reset role;
select is(pg_temp.ci_outcome('rp_kds_test'), pg_temp.ci_expect(pg_temp.ci_refusal('permission_denied'), 0, 1, 0),
  'CI-070 re-proof: the KDS device on a TEST claim -> permission_denied, one private event, no audit');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('test.card_attempt_denied', 'test',
    '{"rpc": "claim", "denied_reason": "permission_denied"}'::jsonb, null, 3)),
  'CI-071 re-proof: the TEST KDS denial event carries actor_kind / actor_reference device and device d3');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('rp_accountant_live', pg_temp.ci_claim(5, pg_temp.zc_lop('ci-rp-acct'), 'live',
  p_order => pg_temp.zc_id('order-ci-ctx'), p_rev => 1));
reset role;
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "permission_denied"}'::jsonb, 5, 1)),
  'CI-072 re-proof: an accountant PIN (staff 5) on a LIVE claim -> permission_denied audited card_attempt.denied for employee 5');

-- ===========================================================================
-- 5. Configuration refusals that write no event (§4.55.4 step (3)). Each state
--    is isolated (everything else admissible) and is tried with valid maps AND
--    with an empty terminal map: an absent / OFF / closed / mode-mismatched
--    revision and a binding that is absent or not enabled are decided before any
--    map is read, so neither variant writes an event.
-- ===========================================================================
create function pg_temp.ci_pair(p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('valid_maps', pg_temp.ci_r(p_label) - 'server_ts',
                            'bad_maps', pg_temp.ci_r(p_label || '_bad_maps') - 'server_ts',
                            'written', pg_temp.ci_new()) $$;
create function pg_temp.ci_pair_disabled() returns jsonb language sql immutable as $$
  select jsonb_build_object('valid_maps', pg_temp.ci_refusal('card_payments_disabled'),
                            'bad_maps', pg_temp.ci_refusal('card_payments_disabled'), 'written', pg_temp.ci_none()) $$;
select pg_temp.zc_order('ci-cfg', 1234) is not null as ci_order_cfg;
select pg_temp.ci_ok(pg_temp.zc_bind(1, 'live')) ->> 'new_lifecycle' as binding_enabled_before_any_revision;
set local role authenticated;
insert into _zc_r values ('ctx_posture_no_revision', pg_temp.ci_ctx(1)), ('ctx_posture_d2', pg_temp.ci_ctx(8));
reset role;
select is(jsonb_build_object('terminal', pg_temp.ci_r('ctx_posture_no_revision') -> 'terminal',
    'enabled', pg_temp.ci_r('ctx_posture_no_revision') -> 'card_terminal_enabled'),
  '{"terminal": {"lifecycle": "enabled", "mode": "live"}, "enabled": false}'::jsonb,
  'CI-073 context posture: an enabled LIVE binding with no revision is projected {enabled, live} with starts NOT enabled');
select is(jsonb_build_object('terminal', pg_temp.ci_r('ctx_posture_d2') -> 'terminal',
    'enabled', pg_temp.ci_r('ctx_posture_d2') -> 'card_terminal_enabled'),
  '{"terminal": null, "enabled": false}'::jsonb,
  'CI-074 context posture: the exact device only — d2 (no binding) sees terminal null, starts not enabled');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cfg_no_revision', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                       p_rev => 1)),
  ('cfg_no_revision_bad_maps', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live',
                                                p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1,
                                                p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_pair('cfg_no_revision'), pg_temp.ci_pair_disabled(),
  'CI-075 claim config: no revision at all (binding enabled; maps valid or empty) -> card_payments_disabled, no row, no event, no audit');
select pg_temp.ci_ok(pg_temp.zc_pilot('live', false)) ->> 'enabled' as revision_off;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cfg_off', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1)),
  ('cfg_off_bad_maps', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                        p_rev => 1, p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_pair('cfg_off'), pg_temp.ci_pair_disabled(),
  'CI-076 claim config: the current revision is OFF (binding enabled; maps valid or empty) -> card_payments_disabled, nothing written');
select pg_temp.ci_revision(true, 'live', now() - interval '1 minute', 100000, 1000000) is not null as closed_window;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cfg_window', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                  p_rev => 1)),
  ('cfg_window_bad_maps', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                           p_rev => 1, p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_pair('cfg_window'), pg_temp.ci_pair_disabled(),
  'CI-077 claim config: an enabled LIVE revision (owner-inserted) whose window has closed -> card_payments_disabled, nothing written');
select pg_temp.ci_ok(pg_temp.zc_pilot('test')) ->> 'mode' as revision_test;
set local role authenticated;
insert into _zc_r values ('ctx_posture_revision_test', pg_temp.ci_ctx(1));
reset role;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cfg_mode', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1)),
  ('cfg_mode_bad_maps', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                         p_rev => 1, p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_pair('cfg_mode'), pg_temp.ci_pair_disabled(),
  'CI-078 claim config: a LIVE request on a LIVE binding under a TEST revision (the request mode differs only from the revision) -> card_payments_disabled, NO event');
select is(jsonb_build_object('terminal', pg_temp.ci_r('ctx_posture_revision_test') -> 'terminal',
    'enabled', pg_temp.ci_r('ctx_posture_revision_test') -> 'card_terminal_enabled'),
  '{"terminal": {"lifecycle": "enabled", "mode": "live"}, "enabled": false}'::jsonb,
  'CI-079 context posture: an enabled LIVE binding under a TEST revision is projected with starts not enabled');
select pg_temp.ci_ok(pg_temp.zc_pilot('live')) ->> 'mode' as revision_live;
set local role authenticated;
insert into _zc_r values ('ctx_posture_enabled', pg_temp.ci_ctx(1));
reset role;
select is(jsonb_build_object('terminal', pg_temp.ci_r('ctx_posture_enabled') -> 'terminal',
    'enabled', pg_temp.ci_r('ctx_posture_enabled') -> 'card_terminal_enabled'),
  '{"terminal": {"lifecycle": "enabled", "mode": "live"}, "enabled": true}'::jsonb,
  'CI-080 context posture: an enabled LIVE binding under an ON LIVE revision is projected {enabled, live}, starts enabled');
select pg_temp.ci_ok(pg_temp.ci_lifecycle(1, 'live', 'draining')) ->> 'new_lifecycle' as binding_draining;
set local role authenticated;
insert into _zc_r values ('ctx_posture_draining', pg_temp.ci_ctx(1));
reset role;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cfg_draining', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                    p_rev => 1)),
  ('cfg_draining_bad_maps', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                             p_rev => 1, p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_pair('cfg_draining'), pg_temp.ci_pair_disabled(),
  'CI-081 claim config: a draining binding under an ON LIVE revision -> card_payments_disabled, nothing written');
select is(jsonb_build_object('terminal', pg_temp.ci_r('ctx_posture_draining') -> 'terminal',
    'enabled', pg_temp.ci_r('ctx_posture_draining') -> 'card_terminal_enabled'),
  '{"terminal": {"lifecycle": "draining", "mode": "live"}, "enabled": false}'::jsonb,
  'CI-082 context posture: a draining binding is projected {draining, live} with starts not enabled');
select pg_temp.ci_ok(pg_temp.ci_lifecycle(1, 'live', 'retired', 'end_of_pilot')) ->> 'new_lifecycle' as binding_retired;
set local role authenticated;
insert into _zc_r values ('ctx_posture_retired', pg_temp.ci_ctx(1));
reset role;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cfg_no_binding', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                      p_rev => 1)),
  ('cfg_no_binding_bad_maps', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live',
                                               p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1,
                                               p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_pair('cfg_no_binding'), pg_temp.ci_pair_disabled(),
  'CI-083 claim config: an ON LIVE revision but no current binding on the device (only a retired one) -> card_payments_disabled, nothing written');
select is(pg_temp.ci_r('ctx_posture_retired') -> 'terminal', 'null'::jsonb,
  'CI-084 context posture: a retired binding is hidden (terminal null)');
select pg_temp.ci_ok(pg_temp.zc_bind(1, 'live', 'configured')) ->> 'new_lifecycle' as binding_configured;
set local role authenticated;
insert into _zc_r values ('ctx_posture_configured', pg_temp.ci_ctx(1));
reset role;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('cfg_configured', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live', p_order => pg_temp.zc_id('order-ci-cfg'),
                                      p_rev => 1)),
  ('cfg_configured_bad_maps', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live',
                                               p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1,
                                               p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_pair('cfg_configured'), pg_temp.ci_pair_disabled(),
  'CI-085 claim config: a binding still configured (not enabled) under an ON LIVE revision -> card_payments_disabled, nothing written');
select is(jsonb_build_object('terminal', pg_temp.ci_r('ctx_posture_configured') -> 'terminal',
    'enabled', pg_temp.ci_r('ctx_posture_configured') -> 'card_terminal_enabled'),
  '{"terminal": {"lifecycle": "configured", "mode": "live"}, "enabled": false}'::jsonb,
  'CI-086 context posture: a configured LIVE binding is projected {configured, live} with starts not enabled');
select pg_temp.ci_ok(pg_temp.ci_lifecycle(1, 'live', 'enabled', 'live_activation')) ->> 'new_lifecycle' as binding_enabled;
select pg_temp.ci_ok(pg_temp.zc_pilot('live', true, 100000, null)) -> 'max_live_amount_minor' as live_cap_absent;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('cfg_no_live_cap', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-cfg'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('cfg_no_live_cap'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 0, 0),
  'CI-087 claim config: an ON LIVE revision without max_live_amount_minor (binding enabled, maps valid) -> card_payments_disabled, nothing written');
select pg_temp.ci_ok(pg_temp.zc_pilot('live')) ->> 'max_live_amount_minor' as live_ready;

-- ===========================================================================
-- 6. Key-format version under a ready LIVE configuration (M7).
-- ===========================================================================
select pg_temp.zc_order('ci-ver', 1234) is not null as ci_order_ver;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('ver_unknown', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-ver'), 'live', p_order => pg_temp.zc_id('order-ci-ver'),
                                   p_rev => 1, p_version => 'alpha16-l40-v1')),
  ('ver_null', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-ver'), 'live', p_order => pg_temp.zc_id('order-ci-ver'),
                                p_rev => 1, p_version => null)),
  ('ver_empty', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-ver'), 'live', p_order => pg_temp.zc_id('order-ci-ver'),
                                 p_rev => 1, p_version => '')),
  ('ver_case', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-ver'), 'live', p_order => pg_temp.zc_id('order-ci-ver'),
                                p_rev => 1, p_version => 'ALPHA16-L32-V1'));
reset role;
select is(pg_temp.ci_outcome('ver_unknown'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable'), 0, 0, 0),
  'CI-088 key format: an unknown version (alpha16-l40-v1) on an otherwise admissible LIVE claim -> provider_unavailable, no row, no event');
select is(pg_temp.ci_outcome('ver_null'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable'), 0, 0, 0),
  'CI-089 key format: a NULL version -> provider_unavailable, no row, no event');
select is(pg_temp.ci_outcome('ver_empty'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable'), 0, 0, 0),
  'CI-090 key format: an empty version -> provider_unavailable, no row, no event');
select is(pg_temp.ci_outcome('ver_case'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable'), 0, 0, 0),
  'CI-091 key format: a case variant of a closed token (ALPHA16-L32-V1) -> provider_unavailable, nothing written');
set local role service_role;
insert into _zc_r values ('ver_control', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-ver'), 'live',
  p_order => pg_temp.zc_id('order-ci-ver'), p_rev => 1));
reset role;
select is(pg_temp.ci_r('ver_control') ->> 'claim_created', 'true',
  'CI-092 key format: the same claim with a closed-set version is admitted (the refusals above were the version alone)');

-- ===========================================================================
-- 7. Credential / mapping mismatches: card_payments_disabled WITH one
--    security.card_credential_mismatch private event (source claim).
-- ===========================================================================
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_env', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_env => 'test'));
reset role;
select is(pg_temp.ci_outcome('mm_env'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-093 mismatch: configuration environment test for a LIVE claim -> card_payments_disabled, one private event, no row, no audit');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "environment_mode", "source": "claim"}'::jsonb, 1, 1)),
  'CI-094 mismatch: the event is security.card_credential_mismatch {check: environment_mode, source: claim}, LIVE (no retention), actor employee 1 on d1');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_terminal_empty', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_outcome('mm_terminal_empty'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-095 mismatch: the terminal map lacks the binding''s terminal_ref -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "terminal_absent", "source": "claim"}'::jsonb, 1, 1)),
  'CI-096 mismatch: the event carries check terminal_absent');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_terminal_null', public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('ci-mm'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-cfg'), 1, 'production', null,
  pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller()));
reset role;
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "terminal_absent", "source": "claim"}'::jsonb, 1, 1)),
  'CI-097 mismatch: a NULL terminal map -> card_payments_disabled with one terminal_absent event');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_terminal_other_cred', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_terms => '{"zc-term-live-1": "zc-cred-live-9"}'::jsonb));
reset role;
select is(pg_temp.ci_outcome('mm_terminal_other_cred'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-098 mismatch: the terminal map names another credential_ref -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "terminal_credential", "source": "claim"}'::jsonb, 1, 1)),
  'CI-099 mismatch: the event carries check terminal_credential');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_credential_empty', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_creds => '{}'::jsonb));
reset role;
select is(pg_temp.ci_outcome('mm_credential_empty'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-100 mismatch: the credential record is missing -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "credential_absent", "source": "claim"}'::jsonb, 1, 1)),
  'CI-101 mismatch: the event carries check credential_absent');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_credential_mode', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_creds => jsonb_build_object('zc-cred-live-1',
    jsonb_build_object('mode', 'test', 'scope', 'merchant', 'restaurant_id', pg_temp.zc_rest()))));
reset role;
select is(pg_temp.ci_outcome('mm_credential_mode'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-102 mismatch: the credential record''s mode differs from the request -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "credential_mode", "source": "claim"}'::jsonb, 1, 1)),
  'CI-103 mismatch: the event carries check credential_mode');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_live_scope', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_creds => jsonb_build_object('zc-cred-live-1',
    jsonb_build_object('mode', 'live', 'scope', 'development', 'restaurant_id', pg_temp.zc_rest()))));
reset role;
select is(pg_temp.ci_outcome('mm_live_scope'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-104 mismatch: a LIVE credential record whose scope is not merchant -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "credential_scope", "source": "claim"}'::jsonb, 1, 1)),
  'CI-105 mismatch: the event carries check credential_scope');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_live_restaurant', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_creds => jsonb_build_object('zc-cred-live-1',
    jsonb_build_object('mode', 'live', 'scope', 'merchant', 'restaurant_id', pg_temp.zc_id('rest_b')))));
reset role;
select is(pg_temp.ci_outcome('mm_live_restaurant'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-106 mismatch: a LIVE credential record of another restaurant -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "credential_restaurant", "source": "claim"}'::jsonb, 1, 1)),
  'CI-107 mismatch: the event carries check credential_restaurant');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_live_no_restaurant', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm'), 'live',
  p_order => pg_temp.zc_id('order-ci-cfg'), p_rev => 1, p_creds => jsonb_build_object('zc-cred-live-1',
    jsonb_build_object('mode', 'live', 'scope', 'merchant'))));
reset role;
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "credential_restaurant", "source": "claim"}'::jsonb, 1, 1)),
  'CI-108 mismatch: a LIVE merchant record naming no restaurant -> one credential_restaurant event');
-- The binding's mode differs from the request: reachable only when the revision mode = the request mode.
select pg_temp.ci_ok(pg_temp.zc_pilot('test')) ->> 'mode' as revision_test_binding_live;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('mm_mapping_mode', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-mm-t'), 'test'));
reset role;
select is(pg_temp.ci_outcome('mm_mapping_mode'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-109 mismatch: a TEST request under a TEST revision on a LIVE binding (binding mode differs from the request) -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'test',
    '{"check": "mapping_mode", "source": "claim"}'::jsonb, 1, 1)),
  'CI-110 mismatch: the event carries check mapping_mode, mode test and the 90-day retention');
select pg_temp.ci_ok(pg_temp.zc_pilot('live')) ->> 'mode' as revision_live_again;

-- ===========================================================================
-- 8. Claim success (LIVE): row, frozen context, digests, keys per version, audit.
-- ===========================================================================
select pg_temp.zc_order('ci-k32', 1234) is not null as k32, pg_temp.zc_order('ci-k20', 1234) is not null as k20,
       pg_temp.zc_order('ci-k24', 1234) is not null as k24;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('claim_k32', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live',
  p_order => pg_temp.zc_id('order-ci-k32'), p_rev => 1));
reset role;
select is(pg_temp.ci_new(), '{"ledger": 1, "events": 0, "audit": 1}'::jsonb,
  'CI-111 claim success: exactly one ledger row and one tenant audit row, no private event');
select is(pg_temp.ci_project(x.r, x.e), x.e,
  'CI-112 claim success: the fresh answer — envelope (sent, in_progress, not recorded), claim_created true, replayed false, the adapter projection and the version')
  from (select pg_temp.ci_r('claim_k32') as r, jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-k32'),
    'state', 'sent', 'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
    'claim_created', true, 'replayed', false, 'organization_id', pg_temp.zc_org(), 'restaurant_id', pg_temp.zc_rest(),
    'device_id', pg_temp.zc_id('device-1'), 'local_operation_id', pg_temp.zc_lop('ci-k32'), 'mode', 'live',
    'terminal_ref', 'zc-term-live-1', 'credential_ref', 'zc-cred-live-1',
    'provider_key_format_version', 'alpha16-l32-v1') as e) x;
select is((select jsonb_build_object('attempt_row_id', a.id, 'start_deadline_at', a.start_deadline_at,
      'provider_key_format_version', a.provider_key_format_version, 'provider_query_key', a.provider_query_key,
      'provider_duplicate_key', a.provider_duplicate_key)
    from pg_temp.ci_new_ledger() a),
  jsonb_build_object('attempt_row_id', pg_temp.ci_r('claim_k32') -> 'attempt_row_id',
      'start_deadline_at', pg_temp.ci_r('claim_k32') -> 'start_deadline_at',
      'provider_key_format_version', pg_temp.ci_r('claim_k32') -> 'provider_key_format_version',
      'provider_query_key', pg_temp.ci_r('claim_k32') -> 'provider_query_key',
      'provider_duplicate_key', pg_temp.ci_r('claim_k32') -> 'provider_duplicate_key'),
  'CI-113 claim success: the answer''s row id, deadline, version and both keys are exactly the stored ones');
select is((select jsonb_build_object('organization_id', a.organization_id, 'restaurant_id', a.restaurant_id,
      'branch_id', a.branch_id, 'device_id', a.device_id, 'local_operation_id', a.local_operation_id,
      'order_id', a.order_id, 'expected_revision', a.expected_revision, 'mode', a.mode, 'state', a.state,
      'amount_minor', a.amount_minor, 'currency_code', a.currency_code, 'terminal_ref', a.terminal_ref,
      'credential_ref', a.credential_ref, 'retention_until', a.retention_until)
    from pg_temp.ci_new_ledger() a),
  jsonb_build_object('organization_id', pg_temp.zc_org(), 'restaurant_id', pg_temp.zc_rest(),
      'branch_id', pg_temp.zc_branch(), 'device_id', pg_temp.zc_id('device-1'),
      'local_operation_id', pg_temp.zc_lop('ci-k32'), 'order_id', pg_temp.zc_id('order-ci-k32'),
      'expected_revision', 1, 'mode', 'live', 'state', 'sent', 'amount_minor', 1234, 'currency_code', 'ILS',
      'terminal_ref', 'zc-term-live-1', 'credential_ref', 'zc-cred-live-1', 'retention_until', null),
  'CI-114 claim success: the row''s organization / restaurant / branch / device come from the proof; order, expected revision, amount and the binding references frozen; LIVE keeps no retention');
select is((select jsonb_build_object('shift_id', a.shift_id, 'cash_drawer_session_id', a.cash_drawer_session_id)
    from pg_temp.ci_new_ledger() a),
  (select jsonb_build_object('shift_id', s.id, 'cash_drawer_session_id', c.id)
     from public.shifts s join public.cash_drawer_sessions c on c.shift_id = s.id and c.status = 'active'
    where s.device_id = pg_temp.zc_id('device-1') and s.status = 'open'),
  'CI-115 claim success: the frozen shift_id / cash_drawer_session_id are the device''s OPEN shift and its ACTIVE drawer');
select is((select jsonb_build_object('employee', a.initiated_by_employee_profile_id, 'membership', a.initiated_by_membership_id)
    from pg_temp.ci_new_ledger() a),
  jsonb_build_object('employee', pg_temp.zc_id('employee-1'), 'membership', pg_temp.zc_id('membership-1')),
  'CI-116 claim success: initiated_by_employee_profile_id / initiated_by_membership_id are the proven employee / membership');
select is((select jsonb_build_object('charge_may_exist', a.charge_may_exist, 'refusal_code', a.refusal_code,
      'resolution', a.resolution, 'order_freed_at', a.order_freed_at, 'finished_at', a.finished_at,
      'auto_poll_count', a.auto_poll_count, 'recording_resume_count', a.recording_resume_count,
      'provider_reference', a.provider_reference, 'card_last4', a.card_last4, 'provider_return_code', a.provider_return_code)
    from pg_temp.ci_new_ledger() a),
  '{"charge_may_exist": false, "refusal_code": null, "resolution": null, "order_freed_at": null, "finished_at": null,
    "auto_poll_count": 0, "recording_resume_count": 0, "provider_reference": null, "card_last4": null,
    "provider_return_code": null}'::jsonb,
  'CI-117 claim success: the fresh row is an unresolved, unfreed sent claim with no provider fact');
select ok((select abs(extract(epoch from (a.start_deadline_at - a.started_at)) - 120) < 1 from pg_temp.ci_new_ledger() a),
  'CI-118 claim success: start_deadline_at = claim time + 120 s');
select is((pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).provider_status_digest,
  sha256(convert_to('card-status-key/v1|' || pg_temp.zc_org()::text || '|' || pg_temp.zc_id('device-1')::text || '|'
                    || pg_temp.zc_lop('ci-k32'), 'UTF8')),
  'CI-119 claim success: provider_status_digest = sha256(convert_to(''card-status-key/v1|''||org||''|''||device||''|''||lop, ''UTF8''))');
select is((pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).provider_duplicate_digest,
  sha256(convert_to('card-duplicate-key/v1|' || pg_temp.zc_org()::text || '|' || pg_temp.zc_id('device-1')::text || '|'
                    || pg_temp.zc_lop('ci-k32'), 'UTF8')),
  'CI-120 claim success: provider_duplicate_digest = sha256(convert_to(''card-duplicate-key/v1|''||org||''|''||device||''|''||lop, ''UTF8''))');
select is((select jsonb_build_object('query', a.provider_query_key, 'duplicate', a.provider_duplicate_key)
    from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32')) a),
  (select jsonb_build_object('query', translate(left(encode(a.provider_status_digest, 'hex'), 32), '0123456789abcdef', 'abcdefghijklmnop'),
                             'duplicate', translate(left(encode(a.provider_duplicate_digest, 'hex'), 32), '0123456789abcdef', 'abcdefghijklmnop'))
     from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32')) a),
  'CI-121 claim success (alpha16-l32-v1): each key is the first 32 hex nibbles of its own digest mapped 0..f -> a..p');
select ok((select a.provider_query_key = app.card_provider_key(a.provider_status_digest, a.provider_key_format_version)
              and a.provider_duplicate_key = app.card_provider_key(a.provider_duplicate_digest, a.provider_key_format_version)
              and length(a.provider_query_key) = 32 and length(a.provider_duplicate_key) = 32
              and a.provider_query_key ~ '^[a-p]{32}$' and a.provider_duplicate_key ~ '^[a-p]{32}$'
              and a.provider_query_key <> a.provider_duplicate_key
             from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32')) a),
  'CI-122 claim success (alpha16-l32-v1): keys = app.card_provider_key(digest, version), length 32, alphabet a..p, the two keys distinct');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.started',
    '{"attempt_state": "sent", "mode": "live", "amount_minor": 1234, "currency_code": "ILS"}'::jsonb, 1, 1)),
  'CI-123 claim success: one card_attempt.started audit row with new_values exactly {attempt_state, mode, amount_minor, currency_code}, actor employee 1, device d1, reason NULL');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('claim_k20', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k20'), 'live',
  p_order => pg_temp.zc_id('order-ci-k20'), p_rev => 1, p_version => 'alpha16-l20-v1'));
insert into _zc_r values ('claim_k24', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k24'), 'live',
  p_order => pg_temp.zc_id('order-ci-k24'), p_rev => 1, p_version => 'alpha16-l24-v1'));
reset role;
select is((select jsonb_build_object('version', a.provider_key_format_version, 'query', a.provider_query_key,
      'duplicate', a.provider_duplicate_key) from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k20')) a),
  jsonb_build_object('version', 'alpha16-l20-v1',
    'query', pg_temp.ci_key(pg_temp.ci_digest('card-status-key/v1', 1, pg_temp.zc_lop('ci-k20')), 'alpha16-l20-v1'),
    'duplicate', pg_temp.ci_key(pg_temp.ci_digest('card-duplicate-key/v1', 1, pg_temp.zc_lop('ci-k20')), 'alpha16-l20-v1')),
  'CI-124 claim success (alpha16-l20-v1): the stored keys are the first 20 nibbles of the identity digests mapped to a..p');
select ok((select a.provider_query_key = app.card_provider_key(a.provider_status_digest, 'alpha16-l20-v1')
              and a.provider_duplicate_key = app.card_provider_key(a.provider_duplicate_digest, 'alpha16-l20-v1')
              and length(a.provider_query_key) = 20 and length(a.provider_duplicate_key) = 20
              and a.provider_query_key ~ '^[a-p]{20}$' and a.provider_duplicate_key ~ '^[a-p]{20}$'
             from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k20')) a),
  'CI-125 claim success (alpha16-l20-v1): keys = app.card_provider_key(digest, version), length 20, alphabet a..p');
select is(jsonb_build_object('version', pg_temp.ci_r('claim_k20') -> 'provider_key_format_version',
    'query', pg_temp.ci_r('claim_k20') -> 'provider_query_key', 'duplicate', pg_temp.ci_r('claim_k20') -> 'provider_duplicate_key'),
  (select jsonb_build_object('version', a.provider_key_format_version, 'query', a.provider_query_key,
      'duplicate', a.provider_duplicate_key) from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k20')) a),
  'CI-126 claim success (alpha16-l20-v1): the fresh answer carries the version and both keys exactly as stored');
select is((select jsonb_build_object('version', a.provider_key_format_version, 'query', a.provider_query_key,
      'duplicate', a.provider_duplicate_key) from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24')) a),
  jsonb_build_object('version', 'alpha16-l24-v1',
    'query', pg_temp.ci_key(pg_temp.ci_digest('card-status-key/v1', 1, pg_temp.zc_lop('ci-k24')), 'alpha16-l24-v1'),
    'duplicate', pg_temp.ci_key(pg_temp.ci_digest('card-duplicate-key/v1', 1, pg_temp.zc_lop('ci-k24')), 'alpha16-l24-v1')),
  'CI-127 claim success (alpha16-l24-v1): the stored keys are the first 24 nibbles of the identity digests mapped to a..p');
select ok((select a.provider_query_key = app.card_provider_key(a.provider_status_digest, 'alpha16-l24-v1')
              and a.provider_duplicate_key = app.card_provider_key(a.provider_duplicate_digest, 'alpha16-l24-v1')
              and length(a.provider_query_key) = 24 and length(a.provider_duplicate_key) = 24
              and a.provider_query_key ~ '^[a-p]{24}$' and a.provider_duplicate_key ~ '^[a-p]{24}$'
             from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24')) a),
  'CI-128 claim success (alpha16-l24-v1): keys = app.card_provider_key(digest, version), length 24, alphabet a..p');
select is(jsonb_build_object('version', pg_temp.ci_r('claim_k24') -> 'provider_key_format_version',
    'query', pg_temp.ci_r('claim_k24') -> 'provider_query_key', 'duplicate', pg_temp.ci_r('claim_k24') -> 'provider_duplicate_key'),
  (select jsonb_build_object('version', a.provider_key_format_version, 'query', a.provider_query_key,
      'duplicate', a.provider_duplicate_key) from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24')) a),
  'CI-129 claim success (alpha16-l24-v1): the fresh answer carries the version and both keys exactly as stored');
select is(pg_temp.ci_new(), '{"ledger": 2, "events": 0, "audit": 2}'::jsonb,
  'CI-130 claim success: the l20 and l24 claims wrote one row and one started audit each, no private event');

set local role authenticated;
insert into _zc_r values ('ctx_k32', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-k32'), pg_temp.zc_lop('ci-k32')));
reset role;
select is(pg_temp.ci_r('ctx_k32') -> 'attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k32'),
    'state', 'sent', 'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234,
    'currency_code', 'ILS', 'mode', 'live', 'own_device', true),
  'CI-131 context: the attempt projection of an existing own-till attempt is exactly the client-safe envelope + mode + own_device');
select is(pg_temp.ci_r('ctx_k32') -> 'order' -> 'active_claim', 'true'::jsonb,
  'CI-132 context: the claimed order reports active_claim true');
select is((select array_agg(s order by s) from unnest(array['zc-term-live-1', 'zc-cred-live-1',
      (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).provider_query_key,
      (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).provider_duplicate_key, 'alpha16-l32-v1', 'terminal_ref',
      'credential_ref', 'provider_query_key', 'provider_duplicate_key', 'provider_key_format_version']) s
    where strpos(coalesce(pg_temp.ci_r('ctx_k32')::text, s), coalesce(s, '')) > 0), null::text[],
  'CI-133 context: no terminal / credential reference, provider key or key version appears anywhere in the JSON of a sent attempt (text search)');

-- ===========================================================================
-- 9. Replay and conflict of an existing identity.
-- ===========================================================================
insert into _zc_r values ('row_k32_before', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-k32')));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('replay_k32', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live', p_order => pg_temp.zc_id('order-ci-k32'), p_rev => 1)),
  ('replay_k32_rev', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live', p_order => pg_temp.zc_id('order-ci-k32'),
                                      p_rev => 7)),
  ('replay_k32_version', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live', p_order => pg_temp.zc_id('order-ci-k32'),
                                          p_rev => 1, p_version => 'alpha16-l20-v1')),
  ('replay_k32_manager', pg_temp.ci_claim(2, pg_temp.zc_lop('ci-k32'), 'live', p_order => pg_temp.zc_id('order-ci-k32'),
                                          p_rev => 1)),
  ('conflict_k32_amount', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live', 999,
                                           p_order => pg_temp.zc_id('order-ci-k32'), p_rev => 1)),
  ('conflict_k32_order', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live', p_order => pg_temp.zc_id('order-ci-k20'),
                                          p_rev => 1)),
  ('conflict_k32_currency', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live', p_currency => 'USD',
                                             p_order => pg_temp.zc_id('order-ci-k32'), p_rev => 1));
reset role;
select is(pg_temp.ci_project(x.r, x.e), x.e,
  'CI-134 replay: identical frozen fields -> claim_created false, replayed true, the existing attempt''s state and projection (row id, scope, frozen references)')
  from (select pg_temp.ci_r('replay_k32') as r, jsonb_build_object('ok', true,
    'attempt_id', pg_temp.zc_lop('ci-k32'), 'state', 'sent', 'classification', 'in_progress', 'recorded', false,
    'amount_minor', 1234, 'currency_code', 'ILS', 'claim_created', false, 'replayed', true,
    'attempt_row_id', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).id, 'organization_id', pg_temp.zc_org(),
    'restaurant_id', pg_temp.zc_rest(), 'device_id', pg_temp.zc_id('device-1'),
    'local_operation_id', pg_temp.zc_lop('ci-k32'), 'mode', 'live', 'terminal_ref', 'zc-term-live-1',
    'credential_ref', 'zc-cred-live-1',
    'start_deadline_at', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).start_deadline_at) as e) x;
select ok(not (pg_temp.ci_r('replay_k32') ?| array['provider_key_format_version', 'provider_query_key', 'provider_duplicate_key'])
          and strpos(pg_temp.ci_r('replay_k32')::text, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).provider_query_key) = 0
          and strpos(pg_temp.ci_r('replay_k32')::text, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).provider_duplicate_key) = 0,
  'CI-135 replay: neither outbound key appears anywhere in the replay answer (no second commit can be keyed from it)');
select is(jsonb_build_object('created', pg_temp.ci_r('replay_k32_rev') -> 'claim_created',
    'replayed', pg_temp.ci_r('replay_k32_rev') -> 'replayed', 'state', pg_temp.ci_r('replay_k32_rev') -> 'state'),
  '{"created": false, "replayed": true, "state": "sent"}'::jsonb,
  'CI-136 replay: a different expected_revision is not a frozen replay field — the replay precedes the stale-revision check');
select ok((pg_temp.ci_r('replay_k32_version') ->> 'replayed')::boolean
          and not (pg_temp.ci_r('replay_k32_version') ? 'provider_query_key'),
  'CI-137 replay: a resend with another closed-set key version answers the existing attempt as a replay, returning no key');
select ok((pg_temp.ci_r('replay_k32_manager') ->> 'replayed')::boolean
          and pg_temp.ci_r('replay_k32_manager') ->> 'attempt_row_id' = (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k32'))).id::text,
  'CI-138 replay: the same identity resent under another PIN session of the same device is the same attempt (replayed)');
select is(pg_temp.ci_r('conflict_k32_amount') - 'server_ts', pg_temp.ci_refusal('conflict')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k32'), 'attempt_state', 'sent'),
  'CI-139 replay conflict: a different amount -> conflict with attempt_id / attempt_state siblings');
select is(pg_temp.ci_r('conflict_k32_order') - 'server_ts', pg_temp.ci_refusal('conflict')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k32'), 'attempt_state', 'sent'),
  'CI-140 replay conflict: a different order -> conflict with attempt_id / attempt_state siblings');
select is(pg_temp.ci_r('conflict_k32_currency') - 'server_ts', pg_temp.ci_refusal('conflict')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k32'), 'attempt_state', 'sent'),
  'CI-141 replay conflict: a different currency -> conflict with attempt_id / attempt_state siblings');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-142 replay / conflict: no new ledger row, no new audit row, no private event');
select is(coalesce(pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-k32')), '"row missing"'::jsonb), pg_temp.ci_r('row_k32_before'),
  'CI-143 replay / conflict: the existing attempt row is unchanged (every column, updated_at included)');

-- ===========================================================================
-- 10. LIVE preconditions under the orders lock, in the contract order.
-- ===========================================================================
select pg_temp.zc_order('ci-p-foreign', 1234, 4) is not null as p_foreign,
       pg_temp.zc_order('ci-p-sibling', 1234, 5) is not null as p_sibling,
       pg_temp.zc_order('ci-p-zero', 0) is not null as p_zero,
       pg_temp.zc_order('ci-p-settled', 1234) is not null as p_settled,
       pg_temp.zc_order('ci-p-voided', 1234, 1, 'voided') is not null as p_voided,
       pg_temp.zc_order('ci-p-cancelled', 1234, 1, 'cancelled') is not null as p_cancelled,
       pg_temp.zc_order('ci-p-stale', 1234) is not null as p_stale,
       pg_temp.zc_order('ci-p-amount', 1234) is not null as p_amount,
       pg_temp.zc_order('ci-p-currency', 1234, 1, 'submitted', 'USD') is not null as p_currency,
       pg_temp.zc_order('ci-p-cap', 1234) is not null as p_cap,
       pg_temp.zc_order('ci-p-noshift', 1234) is not null as p_noshift,
       pg_temp.zc_order('ci-p-nodrawer', 1234) is not null as p_nodrawer,
       pg_temp.zc_order('ci-o-zero-voided', 0, 1, 'voided') is not null as o_zero_voided,
       pg_temp.zc_order('ci-o-settled-voided', 1234, 1, 'voided') is not null as o_settled_voided,
       pg_temp.zc_order('ci-o-claimed', 1234) is not null as o_claimed,
       pg_temp.zc_order('ci-o-voided-stale', 1234, 1, 'voided') is not null as o_voided_stale,
       pg_temp.zc_order('ci-o-stale-amount', 1234) is not null as o_stale_amount,
       pg_temp.zc_order('ci-o-amount-cap', 1234) is not null as o_amount_cap,
       pg_temp.zc_order('ci-o-cap-shift', 1234) is not null as o_cap_shift,
       pg_temp.zc_order('ci-o-replay', 1234) is not null as o_replay;
select pg_temp.ci_payment(pg_temp.zc_id('order-ci-p-settled'), 'zc001d-ci-settled-payment') is not null as settled_payment,
       pg_temp.ci_payment(pg_temp.zc_id('order-ci-o-settled-voided'), 'zc001d-ci-settled-voided-payment') is not null
         as settled_voided_payment;

select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_missing', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-missing'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-missing'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_missing'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'ineligible_order_state'), 0, 0, 1),
  'CI-144 precondition: a missing order -> precondition_failed / ineligible_order_state, no row, no event, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "ineligible_order_state"}'::jsonb, 1, 1)),
  'CI-145 precondition: the missing-order audit row is exactly card_attempt.denied {denied_reason: ineligible_order_state}');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_foreign', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-foreign'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-foreign'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_foreign'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'ineligible_order_state'), 0, 0, 1),
  'CI-146 precondition: an order of the foreign organization -> precondition_failed / ineligible_order_state, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "ineligible_order_state"}'::jsonb, 1, 1)),
  'CI-147 precondition: the foreign-order denial is audited in the claimer''s proven scope only');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_sibling', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-sibling'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-sibling'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_sibling'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'ineligible_order_state'), 0, 0, 1),
  'CI-148 precondition: an order of the sibling branch -> precondition_failed / ineligible_order_state, one audit row');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_zero', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-zero'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-zero'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_zero'), pg_temp.ci_expect(pg_temp.ci_refusal('order_not_chargeable'), 0, 0, 0),
  'CI-149 precondition: a zero-total order -> order_not_chargeable, no row, no event, no audit');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_settled', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-settled'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-settled'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_settled'), pg_temp.ci_expect(pg_temp.ci_refusal('order_already_settled'), 0, 0, 0),
  'CI-150 precondition: an order carrying a completed payment -> order_already_settled, nothing written');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_in_progress', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-in-progress'), 'live',
  p_order => pg_temp.zc_id('order-ci-k32'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_in_progress'), pg_temp.ci_expect(pg_temp.ci_refusal('payment_in_progress'), 0, 0, 0),
  'CI-151 precondition: an order whose claim is held by another attempt -> payment_in_progress, nothing written');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_voided', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-voided'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-voided'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_voided'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'ineligible_order_state'), 0, 0, 1),
  'CI-152 precondition: a voided order -> precondition_failed / ineligible_order_state, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "ineligible_order_state"}'::jsonb, 1, 1)),
  'CI-153 precondition: the voided-order audit row is exactly card_attempt.denied {denied_reason: ineligible_order_state}');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_cancelled', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-cancelled'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-cancelled'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_cancelled'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'ineligible_order_state'), 0, 0, 1),
  'CI-154 precondition: a cancelled order -> precondition_failed / ineligible_order_state, one audit row');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_stale', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-stale'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-stale'), p_rev => 2));
reset role;
select is(pg_temp.ci_outcome('pre_stale'), pg_temp.ci_expect(pg_temp.ci_refusal('conflict'), 0, 0, 0),
  'CI-155 precondition: a stale expected_revision -> conflict (no detail), nothing written');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_amount', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-amount'), 'live', 1000,
  p_order => pg_temp.zc_id('order-ci-p-amount'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_amount'), pg_temp.ci_expect(pg_temp.ci_refusal('amount_mismatch'), 0, 0, 0),
  'CI-156 precondition: an amount different from the order total -> amount_mismatch, nothing written');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_currency', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-currency'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-currency'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_currency'), pg_temp.ci_expect(pg_temp.ci_refusal('amount_mismatch'), 0, 0, 0),
  'CI-157 precondition: a currency different from the order currency (ILS vs USD) -> amount_mismatch, nothing written');
select pg_temp.ci_ok(pg_temp.zc_pilot('live', true, 100000, 1000)) ->> 'max_live_amount_minor' as live_cap_1000;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_cap', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-cap'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-cap'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('pre_cap'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'max_live_amount_exceeded'), 0, 0, 1),
  'CI-158 precondition: an amount above the revision''s max_live_amount_minor -> precondition_failed / max_live_amount_exceeded, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "max_live_amount_exceeded"}'::jsonb, 1, 1)),
  'CI-159 precondition: that audit row is exactly card_attempt.denied {denied_reason: max_live_amount_exceeded}');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ord_amount_before_cap', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-amount-cap'), 'live', 2000,
  p_order => pg_temp.zc_id('order-ci-o-amount-cap'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('ord_amount_before_cap'), pg_temp.ci_expect(pg_temp.ci_refusal('amount_mismatch'), 0, 0, 0),
  'CI-160 refusal order: amount_mismatch precedes max_live_amount_exceeded (2000 vs a 1234 order under a 1000 cap)');
update shifts set status = 'closed' where id = pg_temp.zc_id('shift-1');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ord_cap_before_shift', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-cap-shift'), 'live',
  p_order => pg_temp.zc_id('order-ci-o-cap-shift'), p_rev => 1));
reset role;
update shifts set status = 'open' where id = pg_temp.zc_id('shift-1');
select is(pg_temp.ci_outcome('ord_cap_before_shift'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'max_live_amount_exceeded'), 0, 0, 1),
  'CI-161 refusal order: max_live_amount_exceeded precedes no_open_shift');
select pg_temp.ci_ok(pg_temp.zc_pilot('live')) ->> 'max_live_amount_minor' as live_cap_restored;
update shifts set status = 'closed' where id = pg_temp.zc_id('shift-1');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_noshift', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-noshift'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-noshift'), p_rev => 1));
reset role;
update shifts set status = 'open' where id = pg_temp.zc_id('shift-1');
select is(pg_temp.ci_outcome('pre_noshift'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'no_open_shift'), 0, 0, 1),
  'CI-162 precondition: no OPEN shift on the device -> precondition_failed / no_open_shift, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "no_open_shift"}'::jsonb, 1, 1)),
  'CI-163 precondition: that audit row is exactly card_attempt.denied {denied_reason: no_open_shift}');
update cash_drawer_sessions set status = 'closed' where id = pg_temp.zc_id('drawer-' || pg_temp.zc_id('device-1'));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pre_nodrawer', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-p-nodrawer'), 'live',
  p_order => pg_temp.zc_id('order-ci-p-nodrawer'), p_rev => 1));
reset role;
update cash_drawer_sessions set status = 'active' where id = pg_temp.zc_id('drawer-' || pg_temp.zc_id('device-1'));
select is(pg_temp.ci_outcome('pre_nodrawer'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'no_active_drawer'), 0, 0, 1),
  'CI-164 precondition: an OPEN shift without an ACTIVE drawer -> precondition_failed / no_active_drawer, one audit row');
select is(pg_temp.ci_new_audit_proj(), jsonb_build_array(pg_temp.ci_audit('card_attempt.denied',
    '{"denied_reason": "no_active_drawer"}'::jsonb, 1, 1)),
  'CI-165 precondition: that audit row is exactly card_attempt.denied {denied_reason: no_active_drawer}');
-- The refusal order on orders failing several preconditions at once.
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('ord_zero_voided', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-zero-voided'), 'live',
                                       p_order => pg_temp.zc_id('order-ci-o-zero-voided'), p_rev => 1)),
  ('ord_settled_voided_stale', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-settled-voided'), 'live',
                                                p_order => pg_temp.zc_id('order-ci-o-settled-voided'), p_rev => 9)),
  ('ord_stale_amount', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-stale-amount'), 'live', 999,
                                        p_order => pg_temp.zc_id('order-ci-o-stale-amount'), p_rev => 9));
reset role;
select is(pg_temp.ci_r('ord_zero_voided') - 'server_ts', pg_temp.ci_refusal('order_not_chargeable'),
  'CI-166 refusal order: order_not_chargeable precedes the state check (a zero-total voided order)');
select is(pg_temp.ci_r('ord_settled_voided_stale') - 'server_ts', pg_temp.ci_refusal('order_already_settled'),
  'CI-167 refusal order: order_already_settled holds whatever the order status or expected_revision (paid + voided + stale)');
select is(pg_temp.ci_r('ord_stale_amount') - 'server_ts', pg_temp.ci_refusal('conflict'),
  'CI-168 refusal order: a stale expected_revision (conflict) precedes amount_mismatch');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-169 refusal order: those three refusals wrote nothing (none is precondition_failed)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ord_voided_stale_amount', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-voided-stale'), 'live', 999,
  p_order => pg_temp.zc_id('order-ci-o-voided-stale'), p_rev => 9));
reset role;
select is(pg_temp.ci_outcome('ord_voided_stale_amount'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'ineligible_order_state'), 0, 0, 1),
  'CI-170 refusal order: ineligible_order_state precedes the stale revision and the amount (voided + stale + amount)');
set local role service_role;
insert into _zc_r values ('ord_claimed_first', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-claimed-1'), 'live',
  p_order => pg_temp.zc_id('order-ci-o-claimed'), p_rev => 1));
reset role;
update orders set status = 'voided' where id = pg_temp.zc_id('order-ci-o-claimed');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ord_claimed_voided_stale', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-claimed-2'), 'live',
  p_order => pg_temp.zc_id('order-ci-o-claimed'), p_rev => 9));
reset role;
select is(pg_temp.ci_outcome('ord_claimed_voided_stale'), pg_temp.ci_expect(pg_temp.ci_refusal('payment_in_progress'), 0, 0, 0),
  'CI-171 refusal order: payment_in_progress precedes ineligible_order_state and the stale revision (claimed, then voided)');
set local role service_role;
insert into _zc_r values ('ord_replay_first', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-replay'), 'live',
  p_order => pg_temp.zc_id('order-ci-o-replay'), p_rev => 1));
reset role;
update orders set status = 'voided' where id = pg_temp.zc_id('order-ci-o-replay');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ord_replay_voided', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-o-replay'), 'live',
  p_order => pg_temp.zc_id('order-ci-o-replay'), p_rev => 1));
reset role;
select is(jsonb_build_object('replayed', pg_temp.ci_r('ord_replay_voided') -> 'replayed',
    'state', pg_temp.ci_r('ord_replay_voided') -> 'state', 'written', pg_temp.ci_new()),
  '{"replayed": true, "state": "sent", "written": {"ledger": 0, "events": 0, "audit": 0}}'::jsonb,
  'CI-172 refusal order: the idempotent replay precedes every live precondition (a voided order still replays its attempt)');

-- ===========================================================================
-- 11. identity_in_use: the identity is used by another operation, a payment,
--     a tombstone or another attempt's keys (before any orders lock).
-- ===========================================================================
select pg_temp.zc_order('ci-j-cash', 1234) is not null as j_cash, pg_temp.zc_order('ci-j-fresh1', 1234) is not null as f1,
       pg_temp.zc_order('ci-j-fresh2', 1234) is not null as f2, pg_temp.zc_order('ci-j-fresh3', 1234) is not null as f3,
       pg_temp.zc_order('ci-j-fresh4', 1234) is not null as f4, pg_temp.zc_order('ci-j-fresh5', 1234) is not null as f5,
       pg_temp.zc_order('ci-j-zero', 0) is not null as j_zero, pg_temp.zc_order('ci-j-payonly', 1234) is not null as j_payonly,
       pg_temp.zc_order('ci-j-d2', 1234, 2) is not null as j_d2;
set local role authenticated;
insert into _zc_r values ('j_push', pg_temp.zc_push(1, jsonb_build_array(pg_temp.zc_pay_op(pg_temp.zc_lop('ci-j-push'),
  pg_temp.zc_id('order-ci-j-cash'), 'cash', 2000))));
reset role;
select is(jsonb_build_object('status', pg_temp.ci_r('j_push') -> 'results' -> 0 ->> 'status',
    'sync_rows', (select count(*) from public.sync_operations so where so.device_id = pg_temp.zc_id('device-1')
                   and so.local_operation_id = pg_temp.zc_lop('ci-j-push')),
    'payment_rows', (select count(*) from public.payments p where p.device_id = pg_temp.zc_id('device-1')
                      and p.local_operation_id = pg_temp.zc_lop('ci-j-push'))),
  '{"status": "applied", "sync_rows": 1, "payment_rows": 1}'::jsonb,
  'CI-173 identity setup: a cash payment.create pushed with the identity is applied (one sync_operations row, one payments row)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('j_after_push', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-j-push'), 'live',
  p_order => pg_temp.zc_id('order-ci-j-fresh1'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('j_after_push'), pg_temp.ci_expect(pg_temp.ci_refusal('conflict', 'identity_in_use'), 0, 0, 0),
  'CI-174 identity_in_use: an identity already pushed as a cash payment.create -> conflict / identity_in_use, no row, no event, no audit');
select pg_temp.ci_sync_row(pg_temp.zc_lop('ci-j-sync')) is not null as sync_only;
select is((select count(*) from public.payments p where p.local_operation_id = pg_temp.zc_lop('ci-j-sync')), 0::bigint,
  'CI-175 identity setup: the sync-only identity has a sync_operations row and no payments row');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('j_sync_only', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-j-sync'), 'live',
  p_order => pg_temp.zc_id('order-ci-j-fresh2'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('j_sync_only'), pg_temp.ci_expect(pg_temp.ci_refusal('conflict', 'identity_in_use'), 0, 0, 0),
  'CI-176 identity_in_use: a sync_operations row of the identity alone (any operation type) -> conflict / identity_in_use, nothing written');
select pg_temp.ci_payment(pg_temp.zc_id('order-ci-j-payonly'), pg_temp.zc_lop('ci-j-pay'), 'voided') is not null as pay_only;
select is((select count(*) from public.sync_operations so where so.local_operation_id = pg_temp.zc_lop('ci-j-pay')), 0::bigint,
  'CI-177 identity setup: the payment-only identity has a payments row and no sync_operations row');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('j_payment_only', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-j-pay'), 'live',
  p_order => pg_temp.zc_id('order-ci-j-fresh3'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('j_payment_only'), pg_temp.ci_expect(pg_temp.ci_refusal('conflict', 'identity_in_use'), 0, 0, 0),
  'CI-178 identity_in_use: a payments row with the device + local_operation_id alone -> conflict / identity_in_use, nothing written');
select pg_temp.ci_tombstone(1, pg_temp.zc_lop('ci-j-tomb'));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('j_tombstone', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-j-tomb'), 'live',
  p_order => pg_temp.zc_id('order-ci-j-fresh4'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('j_tombstone'), pg_temp.ci_expect(pg_temp.ci_refusal('conflict', 'identity_in_use'), 0, 0, 0),
  'CI-179 identity_in_use: an identity tombstone (owner-inserted with the identity''s real digests and keys) -> conflict / identity_in_use, nothing written');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('j_before_order', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-j-pay'), 'live',
  p_order => pg_temp.zc_id('order-ci-j-zero'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('j_before_order'), pg_temp.ci_expect(pg_temp.ci_refusal('conflict', 'identity_in_use'), 0, 0, 0),
  'CI-180 refusal order: identity_in_use precedes every order precondition (a used identity on a zero-total order)');
set local role authenticated;
insert into _zc_r values ('j_push_d2', pg_temp.zc_push(8, jsonb_build_array(pg_temp.zc_pay_op(pg_temp.zc_lop('ci-j-d2'),
  pg_temp.zc_id('order-ci-j-d2'), 'cash', 1234))));
reset role;
set local role service_role;
insert into _zc_r values ('j_other_device', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-j-d2'), 'live',
  p_order => pg_temp.zc_id('order-ci-j-fresh5'), p_rev => 1));
reset role;
select is(jsonb_build_object('push', pg_temp.ci_r('j_push_d2') -> 'results' -> 0 ->> 'status',
    'claim_created', pg_temp.ci_r('j_other_device') -> 'claim_created'),
  '{"push": "applied", "claim_created": true}'::jsonb,
  'CI-181 identity scope: the same local_operation_id pushed by ANOTHER device (d2) does not block a d1 claim — the identity is (organization, device, id)');

-- ===========================================================================
-- 12. Cross-tenant and scope: every scope comes from the proof.
-- ===========================================================================
select pg_temp.zc_order('ci-x-b', 1234, 4) is not null as x_b, pg_temp.zc_order('ci-x-sib', 1234, 5) is not null as x_sib;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('x_foreign_live', pg_temp.ci_claim(7, pg_temp.zc_lop('ci-x-b'), 'live', p_order => pg_temp.zc_id('order-ci-x-b'),
                                      p_rev => 1)),
  ('x_foreign_test', pg_temp.ci_claim(7, pg_temp.zc_lop('ci-x-b-t'), 'test')),
  ('x_sibling_live', pg_temp.ci_claim(10, pg_temp.zc_lop('ci-x-sib'), 'live', p_order => pg_temp.zc_id('order-ci-x-sib'),
                                      p_rev => 1)),
  ('x_sibling_test', pg_temp.ci_claim(10, pg_temp.zc_lop('ci-x-sib-t'), 'test'));
reset role;
select is(pg_temp.ci_r('x_foreign_live') - 'server_ts', pg_temp.ci_refusal('card_payments_disabled'),
  'CI-182 cross-tenant: the foreign POS d4 (staff 7, organization B) on a LIVE claim -> card_payments_disabled (no revision covers organization B)');
select is(pg_temp.ci_r('x_foreign_test') - 'server_ts', pg_temp.ci_refusal('card_payments_disabled'),
  'CI-183 cross-tenant: the foreign POS d4 on a TEST claim -> card_payments_disabled');
select is(pg_temp.ci_r('x_sibling_live') - 'server_ts', pg_temp.ci_refusal('card_payments_disabled'),
  'CI-184 scope: the sibling-branch POS d5 (staff 10) on a LIVE claim -> card_payments_disabled (the revision is pinned to the pilot branch)');
select is(pg_temp.ci_r('x_sibling_test') - 'server_ts', pg_temp.ci_refusal('card_payments_disabled'),
  'CI-185 scope: the sibling-branch POS d5 on a TEST claim -> card_payments_disabled');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-186 cross-tenant / sibling: no ledger row, no private event, no audit row');
select is(pg_get_function_identity_arguments('public.card_attempt_claim'::regproc),
  'p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_attempt_id text, p_mode text, p_amount_minor bigint, p_currency_code text, p_order_id uuid, p_expected_revision integer, p_environment text, p_terminals jsonb, p_credentials jsonb, p_key_format_version text, p_caller_auth_user_id uuid',
  'CI-187 scope: the claim wrapper takes no organization / restaurant / branch argument — every scope is derived from the proof');
select is(pg_get_function_identity_arguments('app.card_attempt_claim'::regproc),
  pg_get_function_identity_arguments('public.card_attempt_claim'::regproc),
  'CI-188 scope: the claim body has the same proof-only signature');

-- ===========================================================================
-- 13. Grants: anon and authenticated cannot reach the service-only claim.
-- ===========================================================================
select pg_temp.zc_order('ci-g', 1234) is not null as ci_order_grant;
select pg_temp.ci_mark();
set local role anon;
select throws_ok($$ select public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1',
    pg_temp.zc_lop('ci-g'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-g'), 1, 'production',
    pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller()) $$,
  '42501', 'permission denied for function card_attempt_claim',
  'CI-189 grants: anon calling public.card_attempt_claim raises 42501');
reset role;
set local role authenticated;
select throws_ok($$ select public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1',
    pg_temp.zc_lop('ci-g'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-g'), 1, 'production',
    pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller()) $$,
  '42501', 'permission denied for function card_attempt_claim',
  'CI-190 grants: authenticated (the POS JWT) calling public.card_attempt_claim raises 42501');
select throws_ok($$ select public.card_attempt_adapter_read(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1',
    pg_temp.zc_lop('ci-k32'), 'production', pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), pg_temp.zc_caller()) $$,
  '42501', 'permission denied for function card_attempt_adapter_read',
  'CI-191 grants: authenticated calling public.card_attempt_adapter_read raises 42501');
reset role;
select is(pg_temp.ci_new(), pg_temp.ci_none(), 'CI-192 grants: the refused calls wrote no ledger, event or audit row');
set local role service_role;
insert into _zc_r values ('g_service', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-g'), 'live',
  p_order => pg_temp.zc_id('order-ci-g'), p_rev => 1));
reset role;
select is(pg_temp.ci_r('g_service') ->> 'claim_created', 'true',
  'CI-193 grants: the identical call as service_role creates the claim (the 42501 above was the grant, not the request)');

-- ===========================================================================
-- 14. card_attempt_adapter_read.
-- ===========================================================================
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ar_k24', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24')));
reset role;
select is(pg_temp.ci_project(x.r, x.e), x.e,
  'CI-194 adapter read (sent, valid maps): envelope + frozen scope / references + the STORED version and both keys + deadline + poll counter')
  from (select pg_temp.ci_r('ar_k24') as r, jsonb_build_object('ok', true, 'attempt_id', a.local_operation_id,
      'state', 'sent', 'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
      'attempt_row_id', a.id, 'organization_id', a.organization_id, 'restaurant_id', a.restaurant_id,
      'device_id', a.device_id, 'local_operation_id', a.local_operation_id, 'mode', 'live',
      'terminal_ref', 'zc-term-live-1', 'credential_ref', 'zc-cred-live-1',
      'provider_key_format_version', 'alpha16-l24-v1', 'provider_query_key', a.provider_query_key,
      'provider_duplicate_key', a.provider_duplicate_key, 'start_deadline_at', a.start_deadline_at,
      'start_deadline_passed', false, 'auto_poll_count', 0, 'last_lookup_at', null, 'release_requested_at', null) as e
    from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24')) a) x;
select is(pg_temp.ci_new(), pg_temp.ci_none(), 'CI-195 adapter read: a successful re-validated read writes nothing');
set local role service_role;
insert into _zc_r values ('fin_k24_poll', pg_temp.zc_finish(pg_temp.ci_r('claim_k24'), 'lookup', 'pending', '{}'::jsonb, 'auto'));
insert into _zc_r values ('ar_k24_polled', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24')));
reset role;
select is(jsonb_build_object('auto_poll_count', pg_temp.ci_r('ar_k24_polled') -> 'auto_poll_count',
    'last_lookup_at', pg_temp.ci_r('ar_k24_polled') -> 'last_lookup_at', 'state', pg_temp.ci_r('ar_k24_polled') -> 'state'),
  (select jsonb_build_object('auto_poll_count', 1, 'last_lookup_at', a.last_lookup_at, 'state', 'sent')
     from pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24')) a where a.last_lookup_at is not null),
  'CI-196 adapter read: auto_poll_count and last_lookup_at reflect an automatic lookup (1, the stored stamp)');
insert into _zc_r values ('row_k24_before', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-k24')));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ar_k24_no_terminal', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24'), p_terms => '{}'::jsonb));
reset role;
select is(pg_temp.ci_outcome('ar_k24_no_terminal'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k24'), 'attempt_state', 'sent'), 0, 1, 0),
  'CI-197 adapter read (sent): a terminal map without the frozen terminal_ref -> provider_unavailable with attempt_id / attempt_state, one event, no audit');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "terminal_absent", "source": "adapter_read"}'::jsonb, 1, 1, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24'))).id)),
  'CI-198 adapter read (sent): the event is security.card_credential_mismatch {check: terminal_absent, source: adapter_read} on the attempt row');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ar_k24_env', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24'), p_env => 'test'));
reset role;
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "environment_mode", "source": "adapter_read"}'::jsonb, 1, 1, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24'))).id)),
  'CI-199 adapter read (sent): a test environment for a LIVE attempt -> provider_unavailable with one environment_mode event');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ar_k24_restaurant', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24'),
  p_creds => jsonb_build_object('zc-cred-live-1', jsonb_build_object('mode', 'live', 'scope', 'merchant',
    'restaurant_id', pg_temp.zc_id('rest_b')))));
reset role;
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "credential_restaurant", "source": "adapter_read"}'::jsonb, 1, 1, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24'))).id)),
  'CI-200 adapter read (sent): a credential record of another restaurant -> one credential_restaurant event');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ar_k24_manager_d2_maps', pg_temp.ci_read(3, pg_temp.zc_lop('ci-k24'), p_map_d => 2));
reset role;
select is(pg_temp.ci_outcome('ar_k24_manager_d2_maps'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k24'), 'attempt_state', 'sent'), 0, 1, 0),
  'CI-201 adapter read: a manager on d2 presenting d2''s maps for d1''s attempt -> provider_unavailable (only the FROZEN references count)');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "terminal_absent", "source": "adapter_read"}'::jsonb, 3, 2, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24'))).id)),
  'CI-202 adapter read: that event records the proven reader (employee 3, device d2) on the attempt row');
select is(coalesce(pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-k24')), '"row missing"'::jsonb), pg_temp.ci_r('row_k24_before'),
  'CI-203 adapter read: the refused re-validations left the attempt row unchanged (no state, lookup stamp or poll change)');

select pg_temp.zc_order('ci-rel', 1234) is not null as o_rel, pg_temp.zc_order('ci-appr', 1234) is not null as o_appr,
       pg_temp.zc_order('ci-decl', 1234) is not null as o_decl, pg_temp.zc_order('ci-anom', 1234) is not null as o_anom,
       pg_temp.zc_order('ci-dup', 1234) is not null as o_dup;
set local role service_role;
insert into _zc_r values
  ('claim_rel', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-rel'), 'live', p_order => pg_temp.zc_id('order-ci-rel'), p_rev => 1)),
  ('claim_appr', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-appr'), 'live', p_order => pg_temp.zc_id('order-ci-appr'), p_rev => 1)),
  ('claim_decl', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-decl'), 'live', p_order => pg_temp.zc_id('order-ci-decl'), p_rev => 1)),
  ('claim_anom', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-anom'), 'live', p_order => pg_temp.zc_id('order-ci-anom'), p_rev => 1)),
  ('claim_dup', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-dup'), 'live', p_order => pg_temp.zc_id('order-ci-dup'), p_rev => 1));
insert into _zc_r values
  ('fin_k20_unknown', pg_temp.zc_finish(pg_temp.ci_r('claim_k20'), 'commit', 'unknown')),
  ('fin_rel', pg_temp.zc_finish(pg_temp.ci_r('claim_rel'), 'release', 'released')),
  ('fin_appr', pg_temp.zc_finish(pg_temp.ci_r('claim_appr'), 'commit', 'approved', pg_temp.zc_approved_fields()
      || jsonb_build_object('provider_reference', 'ZC-PROVREF-01', 'approval_number', 'ZCAPPROVAL01',
                            'voucher_number', 'ZCVOUCHER01', 'deposit_id', 'ZC-DEPOSIT-01', 'card_last4', '4242',
                            'card_brand_code', 'visa'))),
  ('fin_decl', pg_temp.zc_finish(pg_temp.ci_r('claim_decl'), 'commit', 'declined', '{"approval_type": "declined"}'::jsonb)),
  ('fin_anom', pg_temp.zc_finish(pg_temp.ci_r('claim_anom'), 'commit', 'anomaly', '{"anomaly_code": "voided"}'::jsonb));
reset role;
select pg_temp.ci_ok(app.card_attempt_resolve_orphan((pg_temp.ci_row(1, pg_temp.zc_lop('ci-anom'))).id, 'provider_voided',
  'zc-res/ref-1', 'ZC001D synthetic orphan resolution', 'zc001d-op/ref-3', pg_temp.zc_owner())) ->> 'resolution' as resolved;
select is(jsonb_build_object('unknown', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k20'))).state,
    'released', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-rel'))).state,
    'approved', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-appr'))).state,
    'approved_reference', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-appr'))).provider_reference,
    'approved_approval_number', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-appr'))).approval_number,
    'declined', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-decl'))).state,
    'resolved', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-anom'))).resolution),
  '{"unknown": "unknown", "released": "released", "approved": "approved", "approved_reference": "ZC-PROVREF-01",
    "approved_approval_number": "ZCAPPROVAL01", "declined": "declined", "resolved": "provider_voided"}'::jsonb,
  'CI-204 adapter read setup: attempts in unknown / released / approved (provider fields stored) / declined / resolved states');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ar_unknown_empty', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k20'), p_terms => '{}'::jsonb,
  p_creds => '{}'::jsonb));
reset role;
select is(pg_temp.ci_outcome('ar_unknown_empty'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k20'), 'attempt_state', 'unknown'), 0, 1, 0),
  'CI-205 adapter read (unknown): empty configuration maps -> provider_unavailable, one event, no ledger change');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "terminal_absent", "source": "adapter_read"}'::jsonb, 1, 1, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k20'))).id)),
  'CI-206 adapter read (unknown): the re-validation event names the unknown attempt');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('ar_released_mode', pg_temp.ci_read(1, pg_temp.zc_lop('ci-rel'),
  p_creds => jsonb_build_object('zc-cred-live-1', jsonb_build_object('mode', 'test', 'scope', 'merchant',
    'restaurant_id', pg_temp.zc_rest()))));
reset role;
select is(pg_temp.ci_outcome('ar_released_mode'), pg_temp.ci_expect(pg_temp.ci_refusal('provider_unavailable')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-rel'), 'attempt_state', 'released'), 0, 1, 0),
  'CI-207 adapter read (released): a credential record of another mode -> provider_unavailable, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "credential_mode", "source": "adapter_read"}'::jsonb, 1, 1, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-rel'))).id)),
  'CI-208 adapter read (released): the event carries check credential_mode');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('ar_unknown_valid', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k20'))),
  ('ar_approved_empty', pg_temp.ci_read(1, pg_temp.zc_lop('ci-appr'), p_env => 'test', p_terms => '{}'::jsonb,
                                        p_creds => '{}'::jsonb)),
  ('ar_declined_empty', pg_temp.ci_read(1, pg_temp.zc_lop('ci-decl'), p_env => 'test', p_terms => '{}'::jsonb,
                                        p_creds => '{}'::jsonb)),
  ('ar_resolved_empty', pg_temp.ci_read(1, pg_temp.zc_lop('ci-anom'), p_env => 'test', p_terms => '{}'::jsonb,
                                        p_creds => '{}'::jsonb));
reset role;
select is(jsonb_build_object('ok', pg_temp.ci_r('ar_unknown_valid') -> 'ok', 'state', pg_temp.ci_r('ar_unknown_valid') -> 'state'),
  '{"ok": true, "state": "unknown"}'::jsonb,
  'CI-209 adapter read (unknown): the restored valid maps re-validate and the attempt is read');
select is(jsonb_build_object('ok', pg_temp.ci_r('ar_approved_empty') -> 'ok', 'state', pg_temp.ci_r('ar_approved_empty') -> 'state',
    'query_key', pg_temp.ci_r('ar_approved_empty') -> 'provider_query_key'),
  jsonb_build_object('ok', true, 'state', 'approved', 'query_key', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-appr'))).provider_query_key),
  'CI-210 adapter read (approved): read WITHOUT re-validation — empty maps and a wrong environment still succeed, stored key returned');
select is(jsonb_build_object('ok', pg_temp.ci_r('ar_declined_empty') -> 'ok', 'state', pg_temp.ci_r('ar_declined_empty') -> 'state'),
  '{"ok": true, "state": "declined"}'::jsonb,
  'CI-211 adapter read (declined): read without re-validation — empty maps still succeed');
select is(jsonb_build_object('ok', pg_temp.ci_r('ar_resolved_empty') -> 'ok', 'state', pg_temp.ci_r('ar_resolved_empty') -> 'state',
    'resolution', pg_temp.ci_r('ar_resolved_empty') -> 'resolution'),
  '{"ok": true, "state": "unknown", "resolution": "provider_voided"}'::jsonb,
  'CI-212 adapter read (resolved): an unknown attempt carrying a resolution is final and read without re-validation');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-213 adapter read: the approved / declined / resolved reads and the valid unknown read wrote no event, no audit, no row');

select pg_temp.ci_plant(2, pg_temp.zc_lop('ci-dup'), 8) is not null as planted_dup_d2;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('ar_cashier_d2', pg_temp.ci_read(8, pg_temp.zc_lop('ci-k24'))),
  ('ar_manager_d2', pg_temp.ci_read(3, pg_temp.zc_lop('ci-k24'))),
  ('ar_dup_manager_d6', pg_temp.ci_read(11, pg_temp.zc_lop('ci-dup'), p_d => 6)),
  ('ar_dup_manager_d2', pg_temp.ci_read(3, pg_temp.zc_lop('ci-dup'), 'test', p_map_d => 2)),
  ('ar_dup_cashier_d1', pg_temp.ci_read(1, pg_temp.zc_lop('ci-dup'))),
  ('ar_bad_id', pg_temp.ci_read(1, 'not-a-uuid')),
  ('ar_forged', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24'), p_token => 'zc-token-forged')),
  ('ar_kitchen', pg_temp.ci_read(4, pg_temp.zc_lop('ci-k24'))),
  ('ar_kds', pg_temp.ci_read(6, pg_temp.zc_lop('ci-k24')));
reset role;
set local role authenticated;
insert into _zc_r values ('ctx_dup_manager_d6', pg_temp.ci_ctx(11, p_attempt => pg_temp.zc_lop('ci-dup'), p_d => 6));
reset role;
select is(pg_temp.ci_r('ar_cashier_d2') - 'server_ts', pg_temp.ci_refusal('attempt_not_found'),
  'CI-214 adapter read: a cashier on d2 (staff 8) addressing d1''s attempt -> attempt_not_found');
select is(jsonb_build_object('ok', pg_temp.ci_r('ar_manager_d2') -> 'ok', 'device_id', pg_temp.ci_r('ar_manager_d2') -> 'device_id',
    'attempt_row_id', pg_temp.ci_r('ar_manager_d2') -> 'attempt_row_id'),
  jsonb_build_object('ok', true, 'device_id', pg_temp.zc_id('device-1'),
    'attempt_row_id', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24'))).id),
  'CI-215 adapter read: a manager on d2 (staff 3) finds d1''s attempt by (organization, branch, attempt_id)');
select is(pg_temp.ci_r('ar_dup_manager_d6') - 'server_ts', pg_temp.ci_refusal('conflict'),
  'CI-216 adapter read: the same attempt id on d1 and d2, read by a manager on neither (staff 11 on d6) -> conflict');
select is(pg_temp.ci_r('ctx_dup_manager_d6') - 'server_ts', pg_temp.ci_refusal('conflict'),
  'CI-217 context: the same ambiguous attempt id asked by the manager on d6 -> conflict');
select is(pg_temp.ci_r('ar_dup_manager_d2') - 'server_ts', pg_temp.ci_refusal('conflict'),
  'CI-218 adapter read: a manager on d2 (staff 3) asking for an id held by attempts of d1 AND d2 -> conflict; a manager+ resolves by (organization, branch, attempt_id) with no own-device preference (review fix 5)');
select is(jsonb_build_object('device_id', pg_temp.ci_r('ar_dup_cashier_d1') -> 'device_id',
    'mode', pg_temp.ci_r('ar_dup_cashier_d1') -> 'mode'),
  jsonb_build_object('device_id', pg_temp.zc_id('device-1'), 'mode', 'live'),
  'CI-219 adapter read: the originating cashier on d1 gets d1''s attempt for the same id');
select is(pg_temp.ci_r('ar_bad_id') - 'server_ts', pg_temp.ci_refusal('invalid_request'),
  'CI-220 adapter read: a malformed attempt id -> invalid_request');
select is(pg_temp.ci_r('ar_forged') - 'server_ts', pg_temp.ci_refusal('invalid_session'),
  'CI-221 adapter read: a forged token -> invalid_session');
select is(pg_temp.ci_r('ar_kitchen') - 'server_ts', pg_temp.ci_refusal('permission_denied'),
  'CI-222 adapter read: a kitchen_staff PIN -> permission_denied');
select is(pg_temp.ci_r('ar_kds') - 'server_ts', pg_temp.ci_refusal('permission_denied'),
  'CI-223 adapter read: the KDS device -> permission_denied');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-224 adapter read / context: none of these reads or refusals wrote denial evidence, an event or a row');

-- ===========================================================================
-- 15. card_attempt_context with attempts (approved, other devices, settled, resolved).
-- ===========================================================================
select pg_temp.ci_mark();
set local role authenticated;
insert into _zc_r values
  ('ctx_appr', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-appr'), pg_temp.zc_lop('ci-appr'))),
  ('ctx_appr_cashier_d2', pg_temp.ci_ctx(8, p_attempt => pg_temp.zc_lop('ci-appr'))),
  ('ctx_appr_manager_d2', pg_temp.ci_ctx(3, p_attempt => pg_temp.zc_lop('ci-appr'))),
  ('ctx_settled', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-p-settled'))),
  ('ctx_resolved', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-anom')));
reset role;
select is(pg_temp.ci_r('ctx_appr') -> 'attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-appr'),
    'state', 'approved', 'classification', 'approved_unrecorded', 'recorded', false, 'amount_minor', 1234,
    'currency_code', 'ILS', 'provider_return_code', 0, 'recoverable', false, 'resume_count', 0,
    'mode', 'live', 'own_device', true),
  'CI-225 context: the projection of an approved-unrecorded attempt (classification, recorded, provider_return_code, recoverable, resume_count)');
select is(pg_temp.ci_r('ctx_appr') -> 'order', jsonb_build_object('order_id', pg_temp.zc_id('order-ci-appr'),
    'status', 'submitted', 'grand_total_minor', 1234, 'currency_code', 'ILS', 'revision', 1,
    'active_claim', true, 'settled', false),
  'CI-226 context: an approved-but-unrecorded attempt keeps the order''s active claim (active_claim true, settled false)');
select is((select array_agg(s order by s) from unnest(array['zc-term-live-1', 'zc-cred-live-1',
      (pg_temp.ci_row(1, pg_temp.zc_lop('ci-appr'))).provider_query_key,
      (pg_temp.ci_row(1, pg_temp.zc_lop('ci-appr'))).provider_duplicate_key, 'alpha16-l32-v1',
      'ZC-PROVREF-01', 'ZCAPPROVAL01', 'ZCVOUCHER01', 'ZC-DEPOSIT-01', 'terminal_ref', 'credential_ref',
      'provider_query_key', 'provider_duplicate_key', 'provider_key_format_version', 'provider_reference',
      'approval_number', 'voucher_number', 'deposit_id', 'card_last4', 'card_brand_code']) s
    where strpos(coalesce(pg_temp.ci_r('ctx_appr')::text, s), coalesce(s, '')) > 0), null::text[],
  'CI-227 context: NEVER a terminal / credential reference, provider key, key version, provider reference, approval / voucher / deposit number or card field anywhere in the JSON (text search, approved attempt with stored provider fields)');
select ok(pg_temp.ci_r('ctx_appr_cashier_d2') ->> 'ok' = 'true' and pg_temp.ci_r('ctx_appr_cashier_d2') -> 'attempt' = 'null'::jsonb,
  'CI-228 context: a cashier on d2 asking for d1''s attempt gets ok with attempt null');
select is(jsonb_build_object('attempt_id', pg_temp.ci_r('ctx_appr_manager_d2') -> 'attempt' -> 'attempt_id',
    'own_device', pg_temp.ci_r('ctx_appr_manager_d2') -> 'attempt' -> 'own_device',
    'role', pg_temp.ci_r('ctx_appr_manager_d2') -> 'role'),
  jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-appr'), 'own_device', false, 'role', 'manager'),
  'CI-229 context: a manager on d2 (staff 3) sees d1''s attempt of the same branch (own_device false)');
select is(jsonb_build_object('settled', pg_temp.ci_r('ctx_settled') -> 'order' -> 'settled',
    'active_claim', pg_temp.ci_r('ctx_settled') -> 'order' -> 'active_claim'),
  '{"settled": true, "active_claim": false}'::jsonb,
  'CI-230 context: an order with a completed payment reports settled true, active_claim false');
select is(jsonb_build_object('resolution', pg_temp.ci_r('ctx_resolved') -> 'attempt' -> 'resolution',
    'classification', pg_temp.ci_r('ctx_resolved') -> 'attempt' -> 'classification'),
  '{"resolution": "provider_voided", "classification": "resolved"}'::jsonb,
  'CI-231 context: a resolved attempt is projected with its resolution and classification resolved');
select is(pg_temp.ci_new(), pg_temp.ci_none(),
  'CI-232 context: reads with attempts write no ledger, private-event or tenant audit row');

-- ===========================================================================
-- 16. TEST mode on d1 (the LIVE binding retired; a TEST binding enabled).
-- ===========================================================================
select is(pg_temp.ci_retire_all(), 0::bigint,
  'CI-233 TEST setup: every pilot binding retired (owner, through the lifecycle trigger; the operator gate is the lifecycle lane''s)');
select pg_temp.ci_ok(pg_temp.zc_bind(1, 'test')) ->> 'new_lifecycle' as test_binding_enabled;
select pg_temp.ci_ok(pg_temp.zc_pilot('test')) ->> 'mode' as revision_test_ready;
set local role authenticated;
insert into _zc_r values ('ctx_posture_test', pg_temp.ci_ctx(1));
reset role;
select is(jsonb_build_object('terminal', pg_temp.ci_r('ctx_posture_test') -> 'terminal',
    'enabled', pg_temp.ci_r('ctx_posture_test') -> 'card_terminal_enabled'),
  '{"terminal": {"lifecycle": "enabled", "mode": "test"}, "enabled": true}'::jsonb,
  'CI-234 context posture: an enabled TEST binding under an ON TEST revision is projected {enabled, test}, starts enabled');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_live_resend_k32', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'live',
  p_order => pg_temp.zc_id('order-ci-k32'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('t_live_resend_k32'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 0, 0),
  'CI-235 refusal order: an identical LIVE resend of an existing identity after the revision turned TEST is refused by the configuration check before the replay (nothing written)');
-- A TEST revision without max_test_amount_minor (inserted directly by the owner).
select pg_temp.ci_revision(true, 'test', now() + interval '1 hour', null, 1000000) is not null as test_cap_absent;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_no_cap', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-cap'), 'test'));
reset role;
select is(pg_temp.ci_outcome('t_no_cap'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 0, 0),
  'CI-236 TEST claim: a TEST revision row with NULL max_test_amount_minor -> card_payments_disabled, no row, no event');
select pg_temp.ci_ok(pg_temp.zc_pilot('test')) ->> 'max_test_amount_minor' as test_cap_restored;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_mm_scope', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-mm'), 'test',
  p_creds => '{"zc-cred-test-1": {"mode": "test", "scope": "merchant"}}'::jsonb));
reset role;
select is(pg_temp.ci_outcome('t_mm_scope'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-237 TEST mismatch: a TEST credential record whose scope is not development -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'test',
    '{"check": "credential_scope", "source": "claim"}'::jsonb, 1, 1)),
  'CI-238 TEST mismatch: the event carries check credential_scope, mode test, 90-day retention');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_mm_restaurant', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-mm'), 'test',
  p_creds => jsonb_build_object('zc-cred-test-1', jsonb_build_object('mode', 'test', 'scope', 'development',
    'restaurant_id', pg_temp.zc_rest()))));
reset role;
select is(pg_temp.ci_outcome('t_mm_restaurant'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-239 TEST mismatch: a TEST credential record carrying a restaurant -> card_payments_disabled, one event');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'test',
    '{"check": "credential_restaurant", "source": "claim"}'::jsonb, 1, 1)),
  'CI-240 TEST mismatch: the event carries check credential_restaurant');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_mm_env', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-mm'), 'test', p_env => 'production'));
reset role;
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'test',
    '{"check": "environment_mode", "source": "claim"}'::jsonb, 1, 1)),
  'CI-241 TEST mismatch: a production environment for a TEST claim -> card_payments_disabled with one environment_mode event');
select pg_temp.ci_ok(pg_temp.zc_pilot('live')) ->> 'mode' as revision_live_binding_test;
select pg_temp.zc_order('ci-t-live', 1234) is not null as o_t_live;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_only_revision', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-mm'), 'test'));
reset role;
select is(pg_temp.ci_outcome('t_only_revision'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 0, 0),
  'CI-242 TEST mismatch: a TEST request with a TEST binding under a LIVE revision (differs only from the revision) -> card_payments_disabled, NO event');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_mapping_mode_live', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-live'), 'live',
  p_order => pg_temp.zc_id('order-ci-t-live'), p_rev => 1));
reset role;
select is(pg_temp.ci_outcome('t_mapping_mode_live'), pg_temp.ci_expect(pg_temp.ci_refusal('card_payments_disabled'), 0, 1, 0),
  'CI-243 mismatch: a LIVE request under a LIVE revision on a TEST binding -> card_payments_disabled, one event, no audit');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('security.card_credential_mismatch', 'live',
    '{"check": "mapping_mode", "source": "claim"}'::jsonb, 1, 1)),
  'CI-244 mismatch: that event carries check mapping_mode and mode live (no retention)');
select pg_temp.ci_ok(pg_temp.zc_pilot('test')) ->> 'mode' as revision_test_again;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_currency', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-cur'), 'test', p_currency => 'USD'));
reset role;
select is(pg_temp.ci_outcome('t_currency'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'currency_not_supported'), 0, 1, 0),
  'CI-245 TEST claim: a currency other than the tenant''s (USD vs ILS) -> precondition_failed / currency_not_supported, one private event, ZERO audit');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('test.card_attempt_denied', 'test',
    '{"rpc": "claim", "denied_reason": "currency_not_supported"}'::jsonb, 1, 1)),
  'CI-246 TEST claim: the event is test.card_attempt_denied {rpc: claim, denied_reason: currency_not_supported}, 90-day retention');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_over_cap', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-cap-over'), 'test', 100001));
reset role;
select is(pg_temp.ci_outcome('t_over_cap'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'max_test_amount_exceeded'), 0, 1, 0),
  'CI-247 TEST claim: an amount above max_test_amount_minor -> precondition_failed / max_test_amount_exceeded, one private event, ZERO audit');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(pg_temp.ci_event('test.card_attempt_denied', 'test',
    '{"rpc": "claim", "denied_reason": "max_test_amount_exceeded"}'::jsonb, 1, 1)),
  'CI-248 TEST claim: the event is test.card_attempt_denied {rpc: claim, denied_reason: max_test_amount_exceeded}');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_currency_first', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-cap-over'), 'test', 100001,
  p_currency => 'USD'));
reset role;
select is(pg_temp.ci_r('t_currency_first') - 'server_ts', pg_temp.ci_refusal('precondition_failed', 'currency_not_supported'),
  'CI-249 TEST claim order: currency_not_supported precedes max_test_amount_exceeded');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_claim', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t1'), 'test'));
reset role;
select is(pg_temp.ci_new(), '{"ledger": 1, "events": 0, "audit": 0}'::jsonb,
  'CI-250 TEST claim success: one ledger row, no private event and NO tenant audit row');
select is(pg_temp.ci_project(x.r, x.e), x.e,
  'CI-251 TEST claim success: the fresh answer (test_sent, claim_created true) with the TEST binding''s references and the version')
  from (select pg_temp.ci_r('t_claim') as r, jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-t1'),
    'state', 'sent', 'classification', 'test_sent', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
    'claim_created', true, 'replayed', false, 'organization_id', pg_temp.zc_org(), 'restaurant_id', pg_temp.zc_rest(),
    'device_id', pg_temp.zc_id('device-1'), 'local_operation_id', pg_temp.zc_lop('ci-t1'), 'mode', 'test',
    'terminal_ref', 'zc-term-test-1', 'credential_ref', 'zc-cred-test-1',
    'provider_key_format_version', 'alpha16-l32-v1') as e) x;
select is((select jsonb_build_object('order_id', a.order_id, 'shift_id', a.shift_id,
      'cash_drawer_session_id', a.cash_drawer_session_id, 'expected_revision', a.expected_revision,
      'employee', a.initiated_by_employee_profile_id, 'membership', a.initiated_by_membership_id,
      'query', a.provider_query_key, 'duplicate', a.provider_duplicate_key)
    from pg_temp.ci_row(1, pg_temp.zc_lop('ci-t1')) a),
  jsonb_build_object('order_id', null, 'shift_id', null, 'cash_drawer_session_id', null, 'expected_revision', null,
    'employee', pg_temp.zc_id('employee-1'), 'membership', pg_temp.zc_id('membership-1'),
    'query', pg_temp.ci_r('t_claim') ->> 'provider_query_key', 'duplicate', pg_temp.ci_r('t_claim') ->> 'provider_duplicate_key'),
  'CI-252 TEST claim success: no order / shift / drawer / expected revision, the initiator frozen, the answered keys as stored');
select ok((select a.retention_until > now() + interval '89 days' and a.retention_until < now() + interval '91 days'
              and a.provider_status_digest = pg_temp.ci_digest('card-status-key/v1', 1, pg_temp.zc_lop('ci-t1'))
              and a.provider_duplicate_digest = pg_temp.ci_digest('card-duplicate-key/v1', 1, pg_temp.zc_lop('ci-t1'))
             from pg_temp.ci_row(1, pg_temp.zc_lop('ci-t1')) a),
  'CI-253 TEST claim success: retention_until ~ claim + 90 days and the same identity digests as LIVE');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('t_replay', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t1'), 'test')),
  ('t_mode_conflict', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-k32'), 'test'));
reset role;
select is(jsonb_build_object('created', pg_temp.ci_r('t_replay') -> 'claim_created', 'replayed', pg_temp.ci_r('t_replay') -> 'replayed',
    'has_keys', pg_temp.ci_r('t_replay') ?| array['provider_key_format_version', 'provider_query_key', 'provider_duplicate_key']),
  '{"created": false, "replayed": true, "has_keys": false}'::jsonb,
  'CI-254 TEST replay: identical frozen fields -> replayed, no version and no key in the answer');
select is(pg_temp.ci_r('t_mode_conflict') - 'server_ts', pg_temp.ci_refusal('conflict')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k32'), 'attempt_state', 'sent'),
  'CI-255 replay conflict: a TEST claim of an existing LIVE identity (different mode) -> conflict with attempt_id / attempt_state siblings');
select is(pg_temp.ci_new(), pg_temp.ci_none(), 'CI-256 TEST replay / mode conflict: nothing written');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_replay_usd', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t1'), 'test', p_currency => 'USD'));
reset role;
select is(pg_temp.ci_outcome('t_replay_usd'), pg_temp.ci_expect(pg_temp.ci_refusal('precondition_failed', 'currency_not_supported'), 0, 1, 0),
  'CI-257 TEST refusal order: the TEST currency check precedes the replay (a USD resend of an existing TEST identity -> currency_not_supported with its event, not conflict)');
select is(coalesce(pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-k32')), '"row missing"'::jsonb), pg_temp.ci_r('row_k32_before'),
  'CI-258 replay conflict: the LIVE attempt is unchanged by the TEST resend of its identity');
select pg_temp.ci_tombstone(1, pg_temp.zc_lop('ci-t-tomb'));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_tombstone', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t-tomb'), 'test'));
reset role;
select is(pg_temp.ci_outcome('t_tombstone'), pg_temp.ci_expect(pg_temp.ci_refusal('conflict', 'identity_in_use'), 0, 0, 0),
  'CI-259 TEST claim: a tombstoned identity -> conflict / identity_in_use (a TEST claim runs the same identity check)');
set local role service_role;
insert into _zc_r values ('t_claim2', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-t2'), 'test'));
insert into _zc_r values ('t_fin2', pg_temp.zc_finish(pg_temp.ci_r('t_claim2'), 'commit', 'unknown'));
reset role;
select pg_temp.ci_ok(app.card_attempt_resolve_orphan((pg_temp.ci_row(1, pg_temp.zc_lop('ci-t2'))).id, 'test_closed',
  'zc-res/ref-2', 'ZC001D synthetic TEST closure', 'zc001d-op/ref-4', pg_temp.zc_owner())) ->> 'resolution' as test_closed;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('t_read', pg_temp.ci_read(1, pg_temp.zc_lop('ci-t1'), 'test')),
  ('t_read_resolved', pg_temp.ci_read(1, pg_temp.zc_lop('ci-t2'), 'test', p_terms => '{}'::jsonb, p_creds => '{}'::jsonb)),
  ('t_read_frozen_live', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24')));
reset role;
set local role authenticated;
insert into _zc_r values ('ctx_t1', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-t1')));
reset role;
select is(jsonb_build_object('ok', pg_temp.ci_r('t_read') -> 'ok', 'mode', pg_temp.ci_r('t_read') -> 'mode',
    'classification', pg_temp.ci_r('t_read') -> 'classification',
    'query', pg_temp.ci_r('t_read') -> 'provider_query_key', 'duplicate', pg_temp.ci_r('t_read') -> 'provider_duplicate_key'),
  jsonb_build_object('ok', true, 'mode', 'test', 'classification', 'test_sent',
    'query', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-t1'))).provider_query_key,
    'duplicate', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-t1'))).provider_duplicate_key),
  'CI-260 adapter read (TEST sent): valid TEST maps re-validate; the stored keys are returned');
select is(jsonb_build_object('ok', pg_temp.ci_r('t_read_resolved') -> 'ok', 'state', pg_temp.ci_r('t_read_resolved') -> 'state',
    'resolution', pg_temp.ci_r('t_read_resolved') -> 'resolution'),
  '{"ok": true, "state": "unknown", "resolution": "test_closed"}'::jsonb,
  'CI-261 adapter read (TEST resolved): a test_closed attempt is read without re-validation (empty maps succeed)');
select is(jsonb_build_object('ok', pg_temp.ci_r('t_read_frozen_live') -> 'ok',
    'terminal_ref', pg_temp.ci_r('t_read_frozen_live') -> 'terminal_ref'),
  '{"ok": true, "terminal_ref": "zc-term-live-1"}'::jsonb,
  'CI-262 adapter read: a LIVE attempt is re-validated against its FROZEN references, not the device''s current (TEST) mapping or revision');
select is(pg_temp.ci_new(), pg_temp.ci_none(), 'CI-263 adapter read (TEST): the successful reads wrote nothing');
select is(pg_temp.ci_r('ctx_t1') -> 'attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-t1'), 'state', 'sent',
    'classification', 'test_sent', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS', 'mode', 'test',
    'own_device', true),
  'CI-264 context: the projection of a TEST attempt (test_sent, mode test)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('t_read_mismatch', pg_temp.ci_read(1, pg_temp.zc_lop('ci-t1'), 'test',
  p_creds => '{"zc-cred-test-1": {"mode": "test", "scope": "merchant"}}'::jsonb));
insert into _zc_r values ('t_read_current_mapping', pg_temp.ci_read(1, pg_temp.zc_lop('ci-k24'),
  p_terms => pg_temp.zc_terminals(1, 'test'), p_creds => pg_temp.zc_credentials(1, 'test')));
reset role;
select is(pg_temp.ci_r('t_read_mismatch') - 'server_ts', pg_temp.ci_refusal('provider_unavailable')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-t1'), 'attempt_state', 'sent'),
  'CI-265 adapter read (TEST sent): a TEST credential record of the wrong scope -> provider_unavailable');
select is(pg_temp.ci_r('t_read_current_mapping') - 'server_ts', pg_temp.ci_refusal('provider_unavailable')
    || jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-k24'), 'attempt_state', 'sent'),
  'CI-266 adapter read: the device''s CURRENT mapping maps do not validate a LIVE attempt frozen to other references');
select is(pg_temp.ci_new_events_proj(), jsonb_build_array(
    pg_temp.ci_event('security.card_credential_mismatch', 'test', '{"check": "credential_scope", "source": "adapter_read"}'::jsonb,
                     1, 1, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-t1'))).id),
    pg_temp.ci_event('security.card_credential_mismatch', 'live', '{"check": "terminal_absent", "source": "adapter_read"}'::jsonb,
                     1, 1, (pg_temp.ci_row(1, pg_temp.zc_lop('ci-k24'))).id)),
  'CI-267 adapter read: exactly two adapter_read mismatch events — TEST (mode test, 90-day retention) and LIVE (no retention)');
select is((select count(*) from pg_temp.ci_new_audit()), 0::bigint,
  'CI-268 adapter read: the TEST and LIVE re-validation refusals wrote no tenant audit row');

-- ===========================================================================
-- 17. identity_in_use by a digest / key collision with ANOTHER attempt or
--     tombstone. The CHECKs binding digests / keys to their own identity are
--     dropped inside this rolled-back transaction only, to plant the collisions.
-- ===========================================================================
alter table app.card_provider_attempts drop constraint card_attempts_digests;
alter table app.card_provider_attempts drop constraint card_attempts_keys;
alter table app.card_attempt_identity_tombstones drop constraint card_tombstones_digests;
alter table app.card_attempt_identity_tombstones drop constraint card_tombstones_keys;
select pg_temp.ci_plant(2, pg_temp.zc_lop('ci-c-plant-1'), 8,
         p_status_digest => pg_temp.ci_digest('card-status-key/v1', 1, pg_temp.zc_lop('ci-c-1'))) is not null as p1,
       pg_temp.ci_plant(2, pg_temp.zc_lop('ci-c-plant-2'), 8,
         p_dup_digest => pg_temp.ci_digest('card-duplicate-key/v1', 1, pg_temp.zc_lop('ci-c-2'))) is not null as p2,
       pg_temp.ci_plant(2, pg_temp.zc_lop('ci-c-plant-3'), 8,
         p_query_key => pg_temp.ci_key(pg_temp.ci_digest('card-status-key/v1', 1, pg_temp.zc_lop('ci-c-3')), 'alpha16-l32-v1')) is not null as p3,
       pg_temp.ci_plant(2, pg_temp.zc_lop('ci-c-plant-4'), 8,
         p_dup_key => pg_temp.ci_key(pg_temp.ci_digest('card-duplicate-key/v1', 1, pg_temp.zc_lop('ci-c-4')), 'alpha16-l32-v1')) is not null as p4,
       pg_temp.ci_plant(2, pg_temp.zc_lop('ci-c-plant-5'), 8,
         p_dup_digest => pg_temp.ci_digest('card-status-key/v1', 1, pg_temp.zc_lop('ci-c-5'))) is not null as p5;
select pg_temp.ci_tombstone(2, pg_temp.zc_lop('ci-c-plant-6'), 'alpha16-l32-v1',
  pg_temp.ci_key(pg_temp.ci_digest('card-status-key/v1', 1, pg_temp.zc_lop('ci-c-6')), 'alpha16-l32-v1'));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('c_status_digest', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c-1'), 'test')),
  ('c_duplicate_digest', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c-2'), 'test')),
  ('c_query_key', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c-3'), 'test')),
  ('c_duplicate_key', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c-4'), 'test')),
  ('c_cross_column', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c-5'), 'test')),
  ('c_tombstone_key', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c-6'), 'test'));
reset role;
select is(pg_temp.ci_r('c_status_digest') - 'server_ts', pg_temp.ci_refusal('conflict', 'identity_in_use'),
  'CI-269 collision: another identity''s attempt (d2) holding this identity''s status digest -> conflict / identity_in_use');
select is(pg_temp.ci_r('c_duplicate_digest') - 'server_ts', pg_temp.ci_refusal('conflict', 'identity_in_use'),
  'CI-270 collision: another attempt holding this identity''s duplicate digest -> conflict / identity_in_use');
select is(pg_temp.ci_r('c_query_key') - 'server_ts', pg_temp.ci_refusal('conflict', 'identity_in_use'),
  'CI-271 collision: another attempt holding this identity''s would-be query key -> conflict / identity_in_use');
select is(pg_temp.ci_r('c_duplicate_key') - 'server_ts', pg_temp.ci_refusal('conflict', 'identity_in_use'),
  'CI-272 collision: another attempt holding this identity''s would-be duplicate key -> conflict / identity_in_use');
select is(pg_temp.ci_r('c_cross_column') - 'server_ts', pg_temp.ci_refusal('conflict', 'identity_in_use'),
  'CI-273 collision: another attempt whose DUPLICATE digest equals this identity''s STATUS digest (cross-column) -> conflict / identity_in_use');
select is(pg_temp.ci_r('c_tombstone_key') - 'server_ts', pg_temp.ci_refusal('conflict', 'identity_in_use'),
  'CI-274 collision: a tombstone of another identity holding this identity''s would-be query key -> conflict / identity_in_use');
select is(pg_temp.ci_new(), pg_temp.ci_none(), 'CI-275 collision: no colliding claim wrote a row, an event or an audit row');
set local role service_role;
insert into _zc_r values ('c_control', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c-0'), 'test'));
reset role;
select is(pg_temp.ci_r('c_control') ->> 'claim_created', 'true',
  'CI-276 collision control: a fresh identity is still claimed with the CHECKs dropped (the refusals above were the collisions)');

-- ===========================================================================
-- 18. Review-fix sections 19–22: fresh attempts (setup only; the attempts of
--     the sections above are left as they are). The pilot is TEST here
--     (section 16): one TEST attempt is claimed on d1, then LIVE is admitted on
--     d2 (one claim) and on d1 (every other claim).
-- ===========================================================================
-- Test setup only: an admitting binding of device p_d. Every pilot binding is
-- retired (ci_retire_all), the new one is created configured by the operator
-- RPC and then enabled through the lifecycle trigger directly: the operator's
-- LIVE activation gate (attempt_unresolved) refuses while the device holds this
-- file's unresolved attempts, and that gate is the lifecycle lane's subject.
create function pg_temp.ci_admit(p_d integer, p_mode text) returns text language plpgsql volatile as $$
declare v text;
begin
  if pg_temp.ci_retire_all() <> 0 then
    raise exception 'CI setup step refused: a pilot binding is still current';
  end if;
  perform pg_temp.ci_ok(pg_temp.zc_bind(p_d, p_mode, 'configured'));
  update app.payment_terminals t set lifecycle = 'enabled'
   where t.organization_id = pg_temp.zc_org() and t.device_id = pg_temp.zc_id('device-' || p_d)
     and t.lifecycle = 'configured'
  returning t.lifecycle into v;
  if v is distinct from 'enabled' then
    raise exception 'CI setup step refused: the binding of d% is not enabled', p_d;
  end if;
  return v;
end $$;
-- The canonical recording leg of d1's attempt p_lop as an owner-inserted sync row
-- (payment.create, the attempt's order / card / amount payload and its
-- fingerprint), so card_attempt_mark_recording_result has a refusal to record.
create function pg_temp.ci_leg(p_lop text, p_status text, p_reason text) returns uuid language sql volatile as $$
  insert into public.sync_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
      operation_type, target_entity, target_id, payload, payload_fingerprint, status, rejection_reason)
  select a.organization_id, a.restaurant_id, a.branch_id, a.device_id, a.local_operation_id, 'payment.create',
      'order', a.order_id, c.p, md5('payment.create' || '|' || c.p::text), p_status, p_reason
    from app.card_provider_attempts a
    cross join lateral (select jsonb_build_object('order_id', a.order_id::text, 'tender_type', 'card',
                                                  'amount_tendered_minor', a.amount_minor) as p) c
   where a.device_id = pg_temp.zc_id('device-1') and a.local_operation_id = p_lop
  returning id $$;
-- The two service-only marks and free_order with every authority argument overridable
-- (staff p_n on its own device and token by default).
create function pg_temp.ci_mk(p_rpc text, p_n integer, p_lop text, p_d integer default null, p_token text default null)
returns jsonb language sql volatile as $$
  select case p_rpc
    when 'mark_release_requested' then public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-' || p_n),
      pg_temp.zc_id('device-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))),
      coalesce(p_token, 'zc-token-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))), p_lop, pg_temp.zc_caller())
    when 'mark_recording_result' then public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-' || p_n),
      pg_temp.zc_id('device-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))),
      coalesce(p_token, 'zc-token-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))), p_lop, 'permission_denied', pg_temp.zc_caller())
  end $$;
create function pg_temp.ci_free(p_n integer, p_lop text, p_source text default 'provider_report',
    p_reference text default 'zc-report-w', p_d integer default null, p_token text default null)
returns jsonb language sql volatile as $$
  select public.card_attempt_free_order(pg_temp.zc_id('pin-' || p_n),
    pg_temp.zc_id('device-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))),
    coalesce(p_token, 'zc-token-' || coalesce(p_d, pg_temp.zc_staff_device(p_n))), p_lop,
    'ZC001D synthetic manager free', p_source, p_reference, pg_temp.zc_caller()) $$;

select pg_temp.zc_order('ci-w-amb-d2', 1234, 2) is not null as w_amb_d2,
       pg_temp.zc_order('ci-w-read', 1234) is not null as w_read, pg_temp.zc_order('ci-w-rel', 1234) is not null as w_rel,
       pg_temp.zc_order('ci-w-rec', 1234) is not null as w_rec, pg_temp.zc_order('ci-w-free', 1234) is not null as w_free,
       pg_temp.zc_order('ci-w-dn', 1234) is not null as w_dn, pg_temp.zc_order('ci-w-x-rel', 1234) is not null as w_x_rel,
       pg_temp.zc_order('ci-w-x-rec', 1234) is not null as w_x_rec,
       pg_temp.zc_order('ci-w-x-free', 1234) is not null as w_x_free,
       pg_temp.zc_order('ci-w-amb', 1234) is not null as w_amb, pg_temp.zc_order('ci-w-sup', 1234) is not null as w_sup;
set local role service_role;
insert into _zc_r values ('w_t', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-t'), 'test'));
reset role;
select pg_temp.ci_ok(pg_temp.ci_r('w_t')) ->> 'claim_created' as w_t_claimed;
select pg_temp.ci_admit(2, 'live') as d2_live_admitting;
select pg_temp.ci_ok(pg_temp.zc_pilot('live')) ->> 'mode' as revision_live_w;
set local role service_role;
insert into _zc_r values ('w_amb_d2', pg_temp.ci_claim(8, pg_temp.zc_lop('ci-w-amb'), 'live',
  p_order => pg_temp.zc_id('order-ci-w-amb-d2'), p_rev => 1));
reset role;
select pg_temp.ci_ok(pg_temp.ci_r('w_amb_d2')) ->> 'claim_created' as w_amb_d2_claimed;
select pg_temp.ci_admit(1, 'live') as d1_live_admitting;
set local role service_role;
insert into _zc_r values
  ('w_read', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-read'), 'live', p_order => pg_temp.zc_id('order-ci-w-read'), p_rev => 1)),
  ('w_rel', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-rel'), 'live', p_order => pg_temp.zc_id('order-ci-w-rel'), p_rev => 1)),
  ('w_rec', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-rec'), 'live', p_order => pg_temp.zc_id('order-ci-w-rec'), p_rev => 1)),
  ('w_free', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-free'), 'live', p_order => pg_temp.zc_id('order-ci-w-free'), p_rev => 1)),
  ('w_dn', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-dn'), 'live', p_order => pg_temp.zc_id('order-ci-w-dn'), p_rev => 1)),
  ('w_x_rel', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-x-rel'), 'live', p_order => pg_temp.zc_id('order-ci-w-x-rel'),
                               p_rev => 1)),
  ('w_x_rec', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-x-rec'), 'live', p_order => pg_temp.zc_id('order-ci-w-x-rec'),
                               p_rev => 1)),
  ('w_x_free', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-x-free'), 'live', p_order => pg_temp.zc_id('order-ci-w-x-free'),
                                p_rev => 1)),
  ('w_amb_d1', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-amb'), 'live', p_order => pg_temp.zc_id('order-ci-w-amb'),
                                p_rev => 1));
insert into _zc_r values
  ('w_rec_fin', pg_temp.zc_finish(pg_temp.ci_r('w_rec'), 'commit', 'approved', pg_temp.zc_approved_fields())),
  ('w_x_rec_fin', pg_temp.zc_finish(pg_temp.ci_r('w_x_rec'), 'commit', 'approved', pg_temp.zc_approved_fields())),
  ('w_free_fin', pg_temp.zc_finish(pg_temp.ci_r('w_free'), 'commit', 'unknown')),
  ('w_x_free_fin', pg_temp.zc_finish(pg_temp.ci_r('w_x_free'), 'commit', 'unknown'));
insert into _zc_r values
  ('w_free_look', pg_temp.zc_finish(pg_temp.ci_r('w_free'), 'lookup', 'pending', '{}'::jsonb, 'operator')),
  ('w_x_free_look', pg_temp.zc_finish(pg_temp.ci_r('w_x_free'), 'lookup', 'pending', '{}'::jsonb, 'operator'));
reset role;
select count(pg_temp.ci_ok(pg_temp.ci_r(l))) as w_setup_calls_ok
  from unnest(array['w_read', 'w_rel', 'w_rec', 'w_free', 'w_dn', 'w_x_rel', 'w_x_rec', 'w_x_free', 'w_amb_d1',
                    'w_rec_fin', 'w_x_rec_fin', 'w_free_fin', 'w_x_free_fin', 'w_free_look', 'w_x_free_look']) l;
select pg_temp.ci_leg(pg_temp.zc_lop('ci-w-rec'), 'rejected', 'permission_denied') is not null as leg_w_rec,
       pg_temp.ci_leg(pg_temp.zc_lop('ci-w-x-rec'), 'rejected', 'permission_denied') is not null as leg_w_x_rec;
select is((select jsonb_object_agg(x.label || '@d' || x.d,
      a.mode || ' ' || a.state || case when a.last_lookup_at is not null then ' looked_up' else '' end
      || coalesce(' leg ' || (select so.status || ':' || so.rejection_reason from public.sync_operations so
                               where so.organization_id = a.organization_id and so.device_id = a.device_id
                                 and so.local_operation_id = a.local_operation_id), '')
      || case when a.resolution is null and a.order_freed_at is null and a.refusal_code is null
                   and a.release_requested_at is null and not a.charge_may_exist then '' else ' NOT FRESH' end)
    from (values ('ci-w-t', 1), ('ci-w-read', 1), ('ci-w-rel', 1), ('ci-w-rec', 1), ('ci-w-free', 1), ('ci-w-dn', 1),
                 ('ci-w-x-rel', 1), ('ci-w-x-rec', 1), ('ci-w-x-free', 1), ('ci-w-amb', 1), ('ci-w-amb', 2)) x(label, d)
    join app.card_provider_attempts a on a.device_id = pg_temp.zc_id('device-' || x.d)
                                     and a.local_operation_id = pg_temp.zc_lop(x.label)),
  '{"ci-w-t@d1": "test sent", "ci-w-read@d1": "live sent", "ci-w-rel@d1": "live sent",
    "ci-w-rec@d1": "live approved leg rejected:permission_denied", "ci-w-free@d1": "live unknown looked_up",
    "ci-w-dn@d1": "live sent", "ci-w-x-rel@d1": "live sent", "ci-w-x-rec@d1": "live approved leg rejected:permission_denied",
    "ci-w-x-free@d1": "live unknown looked_up", "ci-w-amb@d1": "live sent", "ci-w-amb@d2": "live sent"}'::jsonb,
  'CI-277 review-fix setup: fresh attempts — TEST sent on d1; LIVE sent / approved (own canonical leg rejected permission_denied) / unknown (looked up) on d1; the same id ci-w-amb claimed LIVE on d1 AND d2; none resolved, freed, refused or release-marked');

-- ===========================================================================
-- 19. Write-time re-proof matrix (T-023; TESTING_STRATEGY "every service-only
--     body except card_attempt_finish re-runs the proof at write time and
--     refuses forged, revoked, expired and cross-scope authority"). Four bodies
--     on d1's LIVE attempts, each in a state the body acts on: adapter_read
--     (sent, valid maps), mark_release_requested (sent), mark_recording_result
--     (approved, its own leg rejected) — cashier staff 1 — and free_order
--     (unknown, looked up, documented evidence) — manager staff 2. Each fault
--     is applied, the four calls are made, then the fault is undone.
-- ===========================================================================
create function pg_temp.ci_w4(p_cashier integer, p_manager integer, p_token text default 'zc-token-1')
returns jsonb language sql volatile as $$
  select jsonb_build_object(
    'adapter_read', public.card_attempt_adapter_read(pg_temp.zc_id('pin-' || p_cashier), pg_temp.zc_id('device-1'),
        p_token, pg_temp.zc_lop('ci-w-read'), 'production', pg_temp.zc_terminals(1, 'live'),
        pg_temp.zc_credentials(1, 'live'), pg_temp.zc_caller()) - 'server_ts',
    'mark_release_requested', pg_temp.ci_mk('mark_release_requested', p_cashier, pg_temp.zc_lop('ci-w-rel'), 1,
        p_token) - 'server_ts',
    'mark_recording_result', pg_temp.ci_mk('mark_recording_result', p_cashier, pg_temp.zc_lop('ci-w-rec'), 1,
        p_token) - 'server_ts',
    'free_order', pg_temp.ci_free(p_manager, pg_temp.zc_lop('ci-w-free'), 'provider_report', 'zc-report-w1', 1,
        p_token) - 'server_ts') $$;
create function pg_temp.ci_w4_invalid() returns jsonb language sql immutable as $$
  select jsonb_build_object('adapter_read', pg_temp.ci_refusal('invalid_session'),
    'mark_release_requested', pg_temp.ci_refusal('invalid_session'),
    'mark_recording_result', pg_temp.ci_refusal('invalid_session'),
    'free_order', pg_temp.ci_refusal('invalid_session')) $$;
-- The four matrix attempt rows and the recording leg (every column).
create function pg_temp.ci_w_rows() returns jsonb language sql stable as $$
  select jsonb_build_object('read', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-read')),
    'rel', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-rel')), 'rec', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-rec')),
    'free', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-free')),
    'rec_leg', (select to_jsonb(so) from public.sync_operations so
                 where so.device_id = pg_temp.zc_id('device-1') and so.local_operation_id = pg_temp.zc_lop('ci-w-rec'))) $$;
create function pg_temp.ci_w_unchanged() returns jsonb language sql stable as $$
  select jsonb_build_object('written', pg_temp.ci_new(), 'rows', pg_temp.ci_w_rows()) $$;
create function pg_temp.ci_w_unchanged_expected() returns jsonb language sql stable as $$
  select jsonb_build_object('written', pg_temp.ci_none(), 'rows', pg_temp.ci_r('w_rows_before')) $$;
insert into _zc_r values ('w_rows_before', pg_temp.ci_w_rows());

select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('w_forged', pg_temp.ci_w4(1, 2, 'zc-token-forged'));
reset role;
select is(pg_temp.ci_r('w_forged'), pg_temp.ci_w4_invalid(),
  'CI-278 re-proof matrix (a forged device-session token): adapter_read, mark_release_requested, mark_recording_result (cashier staff 1) and free_order (manager staff 2) on d1''s LIVE attempts each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-279 re-proof matrix (forged token): no ledger row, private event or tenant audit row written; the four attempt rows and the recording leg identical (every column)');

select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('w_other_device_pin', pg_temp.ci_w4(8, 3));
reset role;
select is(pg_temp.ci_r('w_other_device_pin'), pg_temp.ci_w4_invalid(),
  'CI-280 re-proof matrix (the PIN session of another device: cashier staff 8 / manager staff 3, both of d2, presented with d1 and its token): the four bodies each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-281 re-proof matrix (another device''s PIN): nothing written; the four attempt rows and the leg identical');

select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('w_foreign_pin', pg_temp.ci_w4(7, 7));
reset role;
select is(pg_temp.ci_r('w_foreign_pin'), pg_temp.ci_w4_invalid(),
  'CI-282 re-proof matrix (a foreign-organization PIN: staff 7 of organization B / d4, presented with d1 and its token): the four bodies each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-283 re-proof matrix (foreign PIN): nothing written; the four attempt rows and the leg identical');

select pg_temp.ci_mark();
update memberships set status = 'revoked' where id in (pg_temp.zc_id('membership-1'), pg_temp.zc_id('membership-2'));
set local role service_role;
insert into _zc_r values ('w_revoked_membership', pg_temp.ci_w4(1, 2));
reset role;
update memberships set status = 'active' where id in (pg_temp.zc_id('membership-1'), pg_temp.zc_id('membership-2'));
select is(pg_temp.ci_r('w_revoked_membership'), pg_temp.ci_w4_invalid(),
  'CI-284 re-proof matrix (the PIN''s membership revoked after the PIN session opened: status revoked for staff 1 and staff 2): the four bodies each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-285 re-proof matrix (revoked membership): nothing written; the four attempt rows and the leg identical');

select pg_temp.ci_mark();
update pin_sessions set expires_at = now() - interval '1 minute' where id in (pg_temp.zc_id('pin-1'), pg_temp.zc_id('pin-2'));
set local role service_role;
insert into _zc_r values ('w_expired_pin', pg_temp.ci_w4(1, 2));
reset role;
update pin_sessions set expires_at = now() + interval '6 hours' where id in (pg_temp.zc_id('pin-1'), pg_temp.zc_id('pin-2'));
select is(pg_temp.ci_r('w_expired_pin'), pg_temp.ci_w4_invalid(),
  'CI-286 re-proof matrix (an expired PIN session: expires_at in the past for staff 1 and staff 2): the four bodies each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-287 re-proof matrix (expired PIN): nothing written; the four attempt rows and the leg identical');

select pg_temp.ci_mark();
update device_sessions set revoked_at = now() where id = pg_temp.zc_id('dsession-1');
set local role service_role;
insert into _zc_r values ('w_revoked_session', pg_temp.ci_w4(1, 2));
reset role;
update device_sessions set revoked_at = null where id = pg_temp.zc_id('dsession-1');
select is(pg_temp.ci_r('w_revoked_session'), pg_temp.ci_w4_invalid(),
  'CI-288 re-proof matrix (d1''s device session revoked): the four bodies each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-289 re-proof matrix (revoked device session): nothing written; the four attempt rows and the leg identical');

select pg_temp.ci_mark();
update device_pairings set status = 'revoked', revoked_at = now() where id = pg_temp.zc_id('pairing-1');
set local role service_role;
insert into _zc_r values ('w_revoked_pairing', pg_temp.ci_w4(1, 2));
reset role;
update device_pairings set status = 'active', revoked_at = null where id = pg_temp.zc_id('pairing-1');
select is(pg_temp.ci_r('w_revoked_pairing'), pg_temp.ci_w4_invalid(),
  'CI-290 re-proof matrix (d1''s device pairing revoked): the four bodies each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-291 re-proof matrix (revoked pairing): nothing written; the four attempt rows and the leg identical');

select pg_temp.ci_mark();
update employee_profiles set employment_status = 'suspended'
 where id in (pg_temp.zc_id('employee-1'), pg_temp.zc_id('employee-2'));
set local role service_role;
insert into _zc_r values ('w_suspended_employee', pg_temp.ci_w4(1, 2));
reset role;
update employee_profiles set employment_status = 'active'
 where id in (pg_temp.zc_id('employee-1'), pg_temp.zc_id('employee-2'));
select is(pg_temp.ci_r('w_suspended_employee'), pg_temp.ci_w4_invalid(),
  'CI-292 re-proof matrix (the employee suspended: staff 1 and staff 2): the four bodies each answer exactly {ok:false, error:invalid_session}');
select is(pg_temp.ci_w_unchanged(), pg_temp.ci_w_unchanged_expected(),
  'CI-293 re-proof matrix (suspended employee): nothing written; the four attempt rows and the leg identical');

-- Control: the same four calls with every fault undone act on the attempts.
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('w_control', pg_temp.ci_w4(1, 2));
reset role;
select is(pg_temp.ci_project(pg_temp.ci_r('w_control') -> 'adapter_read', x.e), x.e,
  'CI-294 re-proof control: the same adapter_read with no fault re-validates and reads the attempt (ok, row id, frozen references, stored keys)')
  from (select jsonb_build_object('ok', true, 'attempt_id', a.local_operation_id, 'state', 'sent',
          'attempt_row_id', a.id, 'device_id', a.device_id, 'terminal_ref', 'zc-term-live-1',
          'credential_ref', 'zc-cred-live-1', 'provider_query_key', a.provider_query_key,
          'provider_duplicate_key', a.provider_duplicate_key) as e
          from pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-read')) a) x;
select is(pg_temp.ci_r('w_control') - 'adapter_read', jsonb_build_object(
    'mark_release_requested', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-rel'), 'state', 'sent',
      'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS'),
    'mark_recording_result', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-rec'), 'state', 'approved',
      'classification', 'approved_unrecorded', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
      'provider_return_code', 0, 'refusal_code', 'permission_denied', 'recoverable', true, 'resume_count', 0),
    'free_order', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-free'), 'state', 'unknown',
      'classification', 'freed', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS')),
  'CI-295 re-proof control: with no fault the writing bodies act — the release mark answers the sent envelope, the recording mark stores refusal_code permission_denied (recoverable, resume_count 0), free_order frees the order (classification freed)');
select is(jsonb_build_object('written', pg_temp.ci_new(), 'audit', pg_temp.ci_new_audit_proj(),
    'release_requested', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-rel'))).release_requested_at is not null,
    'refused', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-rec'))).recording_refused_at is not null,
    'freed', (select jsonb_build_object('reason', a.order_freed_reason, 'source', a.confirmation_source,
                'reference', a.confirmation_reference, 'note', a.order_freed_note, 'state', a.state)
                from pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-free')) a where a.order_freed_at is not null)),
  jsonb_build_object('written', jsonb_build_object('ledger', 0, 'events', 0, 'audit', 3),
    'audit', jsonb_build_array(
      pg_temp.ci_audit('card_attempt.order_freed', '{"attempt_state": "unknown", "confirmation_source": "provider_report"}'::jsonb, 2, 1),
      pg_temp.ci_audit('card_attempt.recording_refused', '{"refusal_code": "permission_denied"}'::jsonb, 1, 1),
      pg_temp.ci_audit('card_attempt.release_requested', '{"attempt_state": "sent"}'::jsonb, 1, 1)),
    'release_requested', true, 'refused', true,
    'freed', jsonb_build_object('reason', 'manager_confirmed', 'source', 'provider_report', 'reference', 'zc-report-w1',
      'note', 'ZC001D synthetic manager free', 'state', 'unknown')),
  'CI-296 re-proof control: the faults alone blocked the writes — stamp, stored refusal and manager free now present, with exactly three LIVE audit rows (order_freed by manager 2, recording_refused and release_requested by cashier 1, all on d1) and no private event');

-- ===========================================================================
-- 20. Proof-level denial evidence of the two marks (review fix 2; packet §11
--     item 13). app.card_attempt_proof answers permission_denied WITH a proven
--     scope in exactly two places: (1) the device session proves a device whose
--     type is not pos (employee NULL; the PIN is not examined), (2) a full PIN
--     proof whose membership role is not cashier / manager / restaurant_owner /
--     org_owner (kitchen_staff, accountant). The evidence is written for the
--     attempt (proof organization, p_device_id, attempt id) when it exists, in
--     the attempt's mode; invalid_session and an unknown id write none.
-- ===========================================================================
create function pg_temp.ci_ev(p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('answer', pg_temp.ci_r(p_label) - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_new_audit_proj(), 'events', pg_temp.ci_new_events_proj(),
    'safe_detail', (select coalesce(jsonb_agg(app.audit_safe_detail(x.action, x.new_values) order by x.action, x.id),
                                    '[]'::jsonb) from pg_temp.ci_new_audit() x)) $$;
create function pg_temp.ci_ev_expect(p_answer jsonb, p_audit jsonb, p_events jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('answer', p_answer,
    'written', jsonb_build_object('ledger', 0, 'events', jsonb_array_length(p_events), 'audit', jsonb_array_length(p_audit)),
    'audit', p_audit, 'events', p_events,
    'safe_detail', case when jsonb_array_length(p_audit) = 0 then '[]'::jsonb
                        else '[{"denied_reason": "permission_denied"}]'::jsonb end) $$;
create function pg_temp.ci_dn_live(p_emp integer) returns jsonb language sql stable as $$
  select pg_temp.ci_ev_expect(pg_temp.ci_refusal('permission_denied'),
    jsonb_build_array(pg_temp.ci_audit('card_attempt.denied', '{"denied_reason": "permission_denied"}'::jsonb, p_emp, 1)),
    '[]'::jsonb) $$;
create function pg_temp.ci_dn_test(p_rpc text, p_emp integer) returns jsonb language sql stable as $$
  select pg_temp.ci_ev_expect(pg_temp.ci_refusal('permission_denied'), '[]'::jsonb,
    jsonb_build_array(pg_temp.ci_event('test.card_attempt_denied', 'test',
      jsonb_build_object('rpc', p_rpc, 'denied_reason', 'permission_denied'), p_emp, 1,
      (pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-t'))).id))) $$;
insert into _zc_r values ('dn_rows_before', jsonb_build_object('live', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-dn')),
  'test', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-t'))));

select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rel_kitchen_live', pg_temp.ci_mk('mark_release_requested', 4, pg_temp.zc_lop('ci-w-dn')));
reset role;
select is(pg_temp.ci_ev('dn_rel_kitchen_live'), pg_temp.ci_dn_live(4),
  'CI-297 proof-level evidence (review fix 2): mark_release_requested by a kitchen_staff PIN (staff 4) on d1 for d1''s LIVE attempt -> permission_denied and exactly one tenant audit card_attempt.denied {denied_reason: permission_denied} (employee 4, device d1, the attempt''s scope, reason NULL; §4.7 safe detail {denied_reason}), no private event, no ledger write');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rel_kitchen_test', pg_temp.ci_mk('mark_release_requested', 4, pg_temp.zc_lop('ci-w-t')));
reset role;
select is(pg_temp.ci_ev('dn_rel_kitchen_test'), pg_temp.ci_dn_test('mark_release_requested', 4),
  'CI-298 proof-level evidence (review fix 2): the same kitchen PIN on d1''s TEST attempt -> permission_denied and exactly one private event test.card_attempt_denied {rpc: mark_release_requested, denied_reason: permission_denied} on that attempt row (employee 4, d1, 90-day retention), no tenant audit');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rec_kitchen_live', pg_temp.ci_mk('mark_recording_result', 4, pg_temp.zc_lop('ci-w-dn')));
reset role;
select is(pg_temp.ci_ev('dn_rec_kitchen_live'), pg_temp.ci_dn_live(4),
  'CI-299 proof-level evidence (review fix 2): mark_recording_result by the kitchen PIN on d1''s LIVE attempt -> permission_denied and exactly one card_attempt.denied {denied_reason: permission_denied} audit row (employee 4, d1), no private event, no ledger write');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rec_kitchen_test', pg_temp.ci_mk('mark_recording_result', 4, pg_temp.zc_lop('ci-w-t')));
reset role;
select is(pg_temp.ci_ev('dn_rec_kitchen_test'), pg_temp.ci_dn_test('mark_recording_result', 4),
  'CI-300 proof-level evidence (review fix 2): mark_recording_result by the kitchen PIN on d1''s TEST attempt -> permission_denied and exactly one test.card_attempt_denied {rpc: mark_recording_result, denied_reason: permission_denied} on that attempt row, no tenant audit');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rel_accountant_live', pg_temp.ci_mk('mark_release_requested', 5, pg_temp.zc_lop('ci-w-dn')));
reset role;
select is(pg_temp.ci_ev('dn_rel_accountant_live'), pg_temp.ci_dn_live(5),
  'CI-301 proof-level evidence (review fix 2): an accountant PIN (staff 5) on d1 -> mark_release_requested on the LIVE attempt answers permission_denied with exactly one card_attempt.denied audit row for employee 5');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rec_accountant_test', pg_temp.ci_mk('mark_recording_result', 5, pg_temp.zc_lop('ci-w-t')));
reset role;
select is(pg_temp.ci_ev('dn_rec_accountant_test'), pg_temp.ci_dn_test('mark_recording_result', 5),
  'CI-302 proof-level evidence (review fix 2): the accountant PIN -> mark_recording_result on the TEST attempt answers permission_denied with exactly one test.card_attempt_denied {rpc: mark_recording_result} event for employee 5');
-- The device-type outcome: d1 re-typed kds (a till that is no longer a POS), staff 1's PIN.
update devices set device_type = 'kds' where id = pg_temp.zc_id('device-1');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rel_kds_live', pg_temp.ci_mk('mark_release_requested', 1, pg_temp.zc_lop('ci-w-dn')));
reset role;
select is(pg_temp.ci_ev('dn_rel_kds_live'), pg_temp.ci_dn_live(null),
  'CI-303 proof-level evidence (review fix 2): with d1 re-typed kds, mark_release_requested on d1''s LIVE attempt -> permission_denied and exactly one card_attempt.denied audit row naming the device (actor employee NULL, device d1)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rel_kds_test', pg_temp.ci_mk('mark_release_requested', 1, pg_temp.zc_lop('ci-w-t')));
reset role;
select is(pg_temp.ci_ev('dn_rel_kds_test'), pg_temp.ci_dn_test('mark_release_requested', null),
  'CI-304 proof-level evidence (review fix 2): with d1 re-typed kds, mark_release_requested on the TEST attempt -> exactly one test.card_attempt_denied {rpc: mark_release_requested} event with actor_kind / actor_reference device');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rec_kds_live', pg_temp.ci_mk('mark_recording_result', 1, pg_temp.zc_lop('ci-w-dn')));
reset role;
select is(pg_temp.ci_ev('dn_rec_kds_live'), pg_temp.ci_dn_live(null),
  'CI-305 proof-level evidence (review fix 2): with d1 re-typed kds, mark_recording_result on the LIVE attempt -> exactly one card_attempt.denied audit row naming the device');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_rec_kds_test', pg_temp.ci_mk('mark_recording_result', 1, pg_temp.zc_lop('ci-w-t')));
reset role;
update devices set device_type = 'pos' where id = pg_temp.zc_id('device-1');
select is(pg_temp.ci_ev('dn_rec_kds_test'), pg_temp.ci_dn_test('mark_recording_result', null),
  'CI-306 proof-level evidence (review fix 2): with d1 re-typed kds, mark_recording_result on the TEST attempt -> exactly one test.card_attempt_denied {rpc: mark_recording_result} event naming the device');
-- No evidence: no attempt of the id on the ORIGINATING device, or no proven scope.
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_none_kds_d3', jsonb_build_object(
  'release_live', pg_temp.ci_mk('mark_release_requested', 6, pg_temp.zc_lop('ci-w-dn')) - 'server_ts',
  'release_test', pg_temp.ci_mk('mark_release_requested', 6, pg_temp.zc_lop('ci-w-t')) - 'server_ts',
  'recording_live', pg_temp.ci_mk('mark_recording_result', 6, pg_temp.zc_lop('ci-w-dn')) - 'server_ts',
  'recording_test', pg_temp.ci_mk('mark_recording_result', 6, pg_temp.zc_lop('ci-w-t')) - 'server_ts'));
reset role;
select is(jsonb_build_object('answers', pg_temp.ci_r('dn_none_kds_d3'), 'written', pg_temp.ci_new()),
  jsonb_build_object('answers', jsonb_build_object('release_live', pg_temp.ci_refusal('permission_denied'),
      'release_test', pg_temp.ci_refusal('permission_denied'), 'recording_live', pg_temp.ci_refusal('permission_denied'),
      'recording_test', pg_temp.ci_refusal('permission_denied')), 'written', pg_temp.ci_none()),
  'CI-307 proof-level evidence: the KDS device d3 (staff 6) naming d1''s LIVE and TEST attempt ids through both marks -> permission_denied each and NO evidence (the attempt is looked up on the originating device d3, which holds none)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_none_unknown_id', jsonb_build_object(
  'release_unknown', pg_temp.ci_mk('mark_release_requested', 4, pg_temp.zc_lop('ci-w-none')) - 'server_ts',
  'recording_unknown', pg_temp.ci_mk('mark_recording_result', 4, pg_temp.zc_lop('ci-w-none')) - 'server_ts',
  'release_d2_only', pg_temp.ci_mk('mark_release_requested', 4, pg_temp.zc_lop('ci-c-plant-1')) - 'server_ts',
  'recording_d2_only', pg_temp.ci_mk('mark_recording_result', 4, pg_temp.zc_lop('ci-c-plant-1')) - 'server_ts'));
reset role;
select is(jsonb_build_object('answers', pg_temp.ci_r('dn_none_unknown_id'), 'written', pg_temp.ci_new()),
  jsonb_build_object('answers', jsonb_build_object('release_unknown', pg_temp.ci_refusal('permission_denied'),
      'recording_unknown', pg_temp.ci_refusal('permission_denied'),
      'release_d2_only', pg_temp.ci_refusal('permission_denied'),
      'recording_d2_only', pg_temp.ci_refusal('permission_denied')), 'written', pg_temp.ci_none()),
  'CI-308 proof-level evidence: the kitchen PIN on d1 naming an unknown attempt id, or an id held only by a d2 attempt, through both marks -> permission_denied each and NO evidence, no event, no row');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('dn_none_invalid', jsonb_build_object(
  'release_test_forged', pg_temp.ci_mk('mark_release_requested', 1, pg_temp.zc_lop('ci-w-t'), 1, 'zc-token-forged') - 'server_ts',
  'recording_test_forged', pg_temp.ci_mk('mark_recording_result', 1, pg_temp.zc_lop('ci-w-t'), 1, 'zc-token-forged') - 'server_ts',
  'release_live_kitchen_forged', pg_temp.ci_mk('mark_release_requested', 4, pg_temp.zc_lop('ci-w-dn'), 1,
                                               'zc-token-forged') - 'server_ts',
  'recording_live_kitchen_forged', pg_temp.ci_mk('mark_recording_result', 4, pg_temp.zc_lop('ci-w-dn'), 1,
                                                 'zc-token-forged') - 'server_ts'));
reset role;
select is(jsonb_build_object('answers', pg_temp.ci_r('dn_none_invalid'), 'written', pg_temp.ci_new()),
  jsonb_build_object('answers', jsonb_build_object('release_test_forged', pg_temp.ci_refusal('invalid_session'),
      'recording_test_forged', pg_temp.ci_refusal('invalid_session'),
      'release_live_kitchen_forged', pg_temp.ci_refusal('invalid_session'),
      'recording_live_kitchen_forged', pg_temp.ci_refusal('invalid_session')), 'written', pg_temp.ci_none()),
  'CI-309 proof-level evidence: a forged token (no proven scope) on the TEST attempt (staff 1) and on the LIVE attempt with the kitchen PIN, through both marks -> invalid_session each and NO evidence');
select is(jsonb_build_object('live', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-dn')), 'test', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-t'))),
  pg_temp.ci_r('dn_rows_before'),
  'CI-310 proof-level evidence: no proof-level refusal changed the LIVE or the TEST attempt row (every column; no stamp, no refusal)');

-- ===========================================================================
-- 21. Resolution scope (review fix 5; §4.55.2; packet §11 item 20): a manager+
--     resolves by (organization, branch, attempt_id) — attempt_not_found on no
--     match, conflict on more than one; every other role resolves only its own
--     device. Exercised through the writing bodies.
-- ===========================================================================
insert into _zc_r values ('x_rows_before', jsonb_build_object('rel', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-x-rel')),
  'rec', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-x-rec'))));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('x_cashier_d2', jsonb_build_object(
  'mark_release_requested', pg_temp.ci_mk('mark_release_requested', 8, pg_temp.zc_lop('ci-w-x-rel')) - 'server_ts',
  'mark_recording_result', pg_temp.ci_mk('mark_recording_result', 8, pg_temp.zc_lop('ci-w-x-rec')) - 'server_ts'));
reset role;
select is(jsonb_build_object('answers', pg_temp.ci_r('x_cashier_d2'), 'written', pg_temp.ci_new(),
    'rows', jsonb_build_object('rel', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-x-rel')),
                               'rec', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-x-rec')))),
  jsonb_build_object('answers', jsonb_build_object('mark_release_requested', pg_temp.ci_refusal('attempt_not_found'),
      'mark_recording_result', pg_temp.ci_refusal('attempt_not_found')),
    'written', pg_temp.ci_none(), 'rows', pg_temp.ci_r('x_rows_before')),
  'CI-311 resolution (review fix 5): a cashier on d2 (staff 8) addressing d1''s attempts through mark_release_requested / mark_recording_result -> attempt_not_found each (a cashier resolves only its own device); nothing written, both d1 rows identical');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('x_manager_d2_rel', pg_temp.ci_mk('mark_release_requested', 3, pg_temp.zc_lop('ci-w-x-rel')));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('x_manager_d2_rel') - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_new_audit_proj(),
    'stamped', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-x-rel'))).release_requested_at is not null),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-x-rel'), 'state', 'sent',
      'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS'),
    'written', jsonb_build_object('ledger', 0, 'events', 0, 'audit', 1),
    'audit', jsonb_build_array(pg_temp.ci_audit('card_attempt.release_requested', '{"attempt_state": "sent"}'::jsonb, 3, 2)),
    'stamped', true),
  'CI-312 resolution (review fix 5): a manager on d2 (staff 3) resolves d1''s attempt by attempt_id through mark_release_requested — d1''s row stamped, exactly its sent envelope answered, one card_attempt.release_requested {attempt_state: sent} audited for employee 3 on d2');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('x_manager_d2_rec', pg_temp.ci_mk('mark_recording_result', 3, pg_temp.zc_lop('ci-w-x-rec')));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('x_manager_d2_rec') - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_new_audit_proj(), 'refusal_code', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-x-rec'))).refusal_code),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-x-rec'),
      'state', 'approved', 'classification', 'approved_unrecorded', 'recorded', false, 'amount_minor', 1234,
      'currency_code', 'ILS', 'provider_return_code', 0, 'refusal_code', 'permission_denied', 'recoverable', true,
      'resume_count', 0),
    'written', jsonb_build_object('ledger', 0, 'events', 0, 'audit', 1),
    'audit', jsonb_build_array(pg_temp.ci_audit('card_attempt.recording_refused', '{"refusal_code": "permission_denied"}'::jsonb, 3, 2)),
    'refusal_code', 'permission_denied'),
  'CI-313 resolution (review fix 5): a manager on d2 resolves d1''s approved attempt through mark_recording_result — refusal_code permission_denied stored on d1''s row, one card_attempt.recording_refused audited for employee 3 on d2');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('x_manager_d2_free', pg_temp.ci_free(3, pg_temp.zc_lop('ci-w-x-free'), 'provider_back_office',
  'zc-report-x1'));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('x_manager_d2_free') - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_new_audit_proj(),
    'freed', (select jsonb_build_object('reason', a.order_freed_reason, 'source', a.confirmation_source,
                'reference', a.confirmation_reference) from pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-x-free')) a
               where a.order_freed_at is not null)),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-x-free'),
      'state', 'unknown', 'classification', 'freed', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS'),
    'written', jsonb_build_object('ledger', 0, 'events', 0, 'audit', 1),
    'audit', jsonb_build_array(pg_temp.ci_audit('card_attempt.order_freed',
      '{"attempt_state": "unknown", "confirmation_source": "provider_back_office"}'::jsonb, 3, 2)),
    'freed', jsonb_build_object('reason', 'manager_confirmed', 'source', 'provider_back_office', 'reference', 'zc-report-x1')),
  'CI-314 resolution (review fix 5): a manager on d2 frees d1''s looked-up unknown attempt through free_order (any POS of the branch, by attempt_id) — d1''s row freed manager_confirmed, one card_attempt.order_freed audited for employee 3 on d2');
-- The same local_operation_id on d1 AND d2 (two LIVE sent attempts).
insert into _zc_r values ('amb_rows_before', jsonb_build_object('d1', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-amb')),
  'd2', pg_temp.ci_rowj(2, pg_temp.zc_lop('ci-w-amb'))));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('amb_managers', jsonb_build_object(
  'release_manager_d2', pg_temp.ci_mk('mark_release_requested', 3, pg_temp.zc_lop('ci-w-amb')) - 'server_ts',
  'release_manager_d1', pg_temp.ci_mk('mark_release_requested', 2, pg_temp.zc_lop('ci-w-amb')) - 'server_ts',
  'release_manager_d6', pg_temp.ci_mk('mark_release_requested', 11, pg_temp.zc_lop('ci-w-amb'), 6) - 'server_ts',
  'release_org_owner_d1', pg_temp.ci_mk('mark_release_requested', 9, pg_temp.zc_lop('ci-w-amb')) - 'server_ts',
  'recording_manager_d2', pg_temp.ci_mk('mark_recording_result', 3, pg_temp.zc_lop('ci-w-amb')) - 'server_ts',
  'free_manager_d2', pg_temp.ci_free(3, pg_temp.zc_lop('ci-w-amb')) - 'server_ts',
  'free_manager_d1', pg_temp.ci_free(2, pg_temp.zc_lop('ci-w-amb')) - 'server_ts',
  'adapter_read_manager_d1', pg_temp.ci_read(2, pg_temp.zc_lop('ci-w-amb')) - 'server_ts'));
reset role;
set local role authenticated;
insert into _zc_r values ('amb_ctx_manager_d1', pg_temp.ci_ctx(2, p_attempt => pg_temp.zc_lop('ci-w-amb')));
reset role;
select is(pg_temp.ci_r('amb_managers') || jsonb_build_object('context_manager_d1', pg_temp.ci_r('amb_ctx_manager_d1') - 'server_ts'),
  (select jsonb_object_agg(k, pg_temp.ci_refusal('conflict')) from unnest(array['release_manager_d2', 'release_manager_d1',
     'release_manager_d6', 'release_org_owner_d1', 'recording_manager_d2', 'free_manager_d2', 'free_manager_d1',
     'adapter_read_manager_d1', 'context_manager_d1']) k),
  'CI-315 resolution (review fix 5): an id held by LIVE attempts of d1 AND d2 -> exactly {ok:false, error:conflict} for every manager+: mark_release_requested by managers on d2, d1 (its own device holds one) and d6 and by the org_owner on d1, mark_recording_result and free_order by managers on d2 / d1, adapter_read and context by the manager on d1');
select is(jsonb_build_object('written', pg_temp.ci_new(), 'rows', jsonb_build_object(
    'd1', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-amb')), 'd2', pg_temp.ci_rowj(2, pg_temp.zc_lop('ci-w-amb')))),
  jsonb_build_object('written', pg_temp.ci_none(), 'rows', pg_temp.ci_r('amb_rows_before')),
  'CI-316 resolution (review fix 5): those conflicts wrote nothing — no ledger write, no private event, no audit (no denial evidence), and both attempts identical (every column)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('amb_cashier_d1', pg_temp.ci_mk('mark_release_requested', 1, pg_temp.zc_lop('ci-w-amb')));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('amb_cashier_d1') - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_new_audit_proj(),
    'd1_stamped', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-amb'))).release_requested_at is not null,
    'd2_row', pg_temp.ci_rowj(2, pg_temp.zc_lop('ci-w-amb'))),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-amb'), 'state', 'sent',
      'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS'),
    'written', jsonb_build_object('ledger', 0, 'events', 0, 'audit', 1),
    'audit', jsonb_build_array(pg_temp.ci_audit('card_attempt.release_requested', '{"attempt_state": "sent"}'::jsonb, 1, 1)),
    'd1_stamped', true, 'd2_row', pg_temp.ci_r('amb_rows_before') -> 'd2'),
  'CI-317 resolution (review fix 5): the cashier on d1 (staff 1) resolves its OWN attempt although d2 holds the same id — d1''s row stamped, d2''s row identical, one release_requested audit for employee 1 on d1');
insert into _zc_r values ('amb_d1_after_cashier', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-amb')));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('amb_cashier_d2', pg_temp.ci_mk('mark_release_requested', 8, pg_temp.zc_lop('ci-w-amb')));
reset role;
select is(jsonb_build_object('written', pg_temp.ci_new(), 'audit', pg_temp.ci_new_audit_proj(),
    'd2_stamped', (pg_temp.ci_row(2, pg_temp.zc_lop('ci-w-amb'))).release_requested_at is not null,
    'd1_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-amb'))),
  jsonb_build_object('written', jsonb_build_object('ledger', 0, 'events', 0, 'audit', 1),
    'audit', jsonb_build_array(pg_temp.ci_audit('card_attempt.release_requested', '{"attempt_state": "sent"}'::jsonb, 8, 2)),
    'd2_stamped', true, 'd1_row', pg_temp.ci_r('amb_d1_after_cashier')),
  'CI-318 resolution (review fix 5): the cashier on d2 (staff 8) resolves d2''s own attempt of the same id — d2''s row stamped, d1''s row identical, one release_requested audit for employee 8 on d2');

-- ===========================================================================
-- 22. A platform support session cannot pass (§4.55.2; C1-5: an ACTIVE support
--     session is refused before any proof; a grant alone is no gate, section 23).
--     Setup follows the reviewer probe r6_tests/p5_body.sql (+ an active grant).
-- ===========================================================================
insert into auth.users (id, email) values (pg_temp.zc_id('ci-support-auth'), 'zc001d-ci-support@example.test');
insert into app_users (id, email, auth_user_id)
values (pg_temp.zc_id('ci-support-user'), 'zc001d-ci-support@example.test', pg_temp.zc_id('ci-support-auth'));
insert into public.platform_admin_grants (app_user_id, status, granted_by)
values (pg_temp.zc_id('ci-support-user'), 'active', pg_temp.zc_id('ci-support-user'));
insert into public.platform_support_sessions (platform_admin_app_user_id, target_organization_id, reason, status,
    expires_at, token_hash, token_consumed_at)
values (pg_temp.zc_id('ci-support-user'), pg_temp.zc_org(), 'ZC001D synthetic CI support session', 'active',
        now() + interval '10 minutes', 'zc001d-ci-support-token-hash', now());
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-support-auth')::text, true);
select is(jsonb_build_object('app_user', app.current_app_user_id(), 'support_session_live', app.current_support_session() is not null,
    'platform_admin', app.is_platform_admin(),
    'pilot_memberships', (select count(*) from public.memberships m
                           where m.app_user_id = pg_temp.zc_id('ci-support-user') and m.organization_id = pg_temp.zc_org())),
  jsonb_build_object('app_user', pg_temp.zc_id('ci-support-user'), 'support_session_live', true, 'platform_admin', true,
    'pilot_memberships', 0),
  'CI-319 support setup: under the platform admin''s JWT (auth.uid() linked to its app user) an active platform-admin grant and a live support session on the pilot organization exist; the admin holds no membership there');
select pg_temp.ci_mark();
set local role authenticated;
insert into _zc_r values
  ('sup_ctx_unknown_pin', public.card_attempt_context(pg_temp.zc_id('ci-support-no-pin'), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-dn'))),
  ('sup_ctx_null_pin', public.card_attempt_context(null, pg_temp.zc_id('device-1'), 'zc-token-1',
     pg_temp.zc_id('order-ci-w-sup'), null));
reset role;
select is(jsonb_build_object('unknown_pin', pg_temp.ci_r('sup_ctx_unknown_pin') - 'server_ts',
    'null_pin', pg_temp.ci_r('sup_ctx_null_pin') - 'server_ts', 'written', pg_temp.ci_new()),
  jsonb_build_object('unknown_pin', pg_temp.ci_refusal('permission_denied'), 'null_pin', pg_temp.ci_refusal('permission_denied'),
    'written', pg_temp.ci_none()),
  'CI-320 support (C1-5): public.card_attempt_context as authenticated with the support-session JWT, d1 and its valid token but no valid PIN session (an unknown PIN id with an order and an attempt id; a NULL PIN) -> exactly {ok:false, error:permission_denied} each (the active support session is refused before any proof), no order / attempt fact, nothing written');
set local role authenticated;
select throws_ok($$ select public.card_attempt_claim(pg_temp.zc_id('ci-support-no-pin'), pg_temp.zc_id('device-1'),
    'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-w-sup'), 1, 'production',
    pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller()) $$,
  '42501', 'permission denied for function card_attempt_claim',
  'CI-321 support: the support-session JWT calling public.card_attempt_claim directly as authenticated raises 42501');
reset role;
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('sup_claim_unknown_pin', public.card_attempt_claim(pg_temp.zc_id('ci-support-no-pin'), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-w-sup'), 1, 'production',
     pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller())),
  ('sup_claim_null_pin', public.card_attempt_claim(null, pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-w-sup'), 1, 'production',
     pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller()));
reset role;
select is(jsonb_build_object('unknown_pin', pg_temp.ci_r('sup_claim_unknown_pin') - 'server_ts',
    'null_pin', pg_temp.ci_r('sup_claim_null_pin') - 'server_ts', 'written', pg_temp.ci_new()),
  jsonb_build_object('unknown_pin', pg_temp.ci_refusal('invalid_session'), 'null_pin', pg_temp.ci_refusal('invalid_session'),
    'written', pg_temp.ci_none()),
  'CI-322 support: the service-only claim made under the support-session JWT with no valid PIN session (unknown id; NULL) on an otherwise admissible LIVE request -> invalid_session each, no ledger row, no private event, no audit');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
set local role service_role;
insert into _zc_r values ('sup_claim_control', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-w-sup'), 'live',
  p_order => pg_temp.zc_id('order-ci-w-sup'), p_rev => 1));
reset role;
select is(jsonb_build_object('claim_created', pg_temp.ci_r('sup_claim_control') -> 'claim_created', 'written', pg_temp.ci_new()),
  '{"claim_created": true, "written": {"ledger": 1, "events": 0, "audit": 1}}'::jsonb,
  'CI-323 support control: the same LIVE claim with cashier staff 1''s PIN session (transport JWT restored) is created (one row, one started audit) — the refusals above were the missing PIN session');

-- ===========================================================================
-- 23. Support context (correction C1-5; §4.55.2). public.card_attempt_context
--     as authenticated: a caller whose verified JWT resolves an ACTIVE platform
--     support session (app.current_support_session(): status active, token
--     consumed, not expired, keyed by app.current_app_user_id()) answers
--     {ok:false, error:permission_denied} before any proof, renewal or read,
--     whatever PIN / device inputs it carries; an expired, ended or
--     un-exchanged session and a platform-admin grant without a session change
--     nothing (the normal PIN / device proof decides). Every case records, as
--     labels, the caller (JWT sub -> app user), its support-session resolution
--     and its own sessions, the PIN's employee / membership and the device
--     relationship. d1's device session is armed before each case (expires_at
--     now() + 1 day, devices.last_seen_at NULL): a proof that runs renews it
--     (now() + 30 days, last_seen_at now()); a refusal before the proof leaves
--     both rows exactly as armed.
-- ===========================================================================
create temp table _ci_lbl (id uuid primary key, label text not null);
insert into _ci_lbl
select pg_temp.zc_id(l), l from unnest(array['transport-principal', 'ci-support-auth', 'ci-support-user',
    'user-1', 'user-2', 'employee-1', 'employee-2', 'membership-1', 'membership-2', 'device-1', 'device-2',
    'ci-dual-auth', 'ci-dual-session']) l
union all select pg_temp.zc_org(), 'pilot-org'
union all select pg_temp.zc_id('org_b'), 'org_b'
union all select s.id, 'ci-support-session' from public.platform_support_sessions s
           where s.platform_admin_app_user_id = pg_temp.zc_id('ci-support-user');
create function pg_temp.ci_lbl(p_id uuid) returns text language sql stable as $$
  select case when p_id is null then null
              else coalesce((select l.label from _ci_lbl l where l.id = p_id), 'unlabelled') end $$;
-- One support session of app user p_user (owner-inserted; the 126 lifecycle columns set directly).
create function pg_temp.ci_sup_session(p_user uuid, p_label text, p_target uuid, p_status text, p_consumed boolean,
    p_expires interval) returns boolean language plpgsql volatile as $$
begin
  insert into public.platform_support_sessions (id, platform_admin_app_user_id, target_organization_id, reason, status,
      expires_at, created_at, ended_at, token_hash, token_consumed_at)
  values (pg_temp.zc_id(p_label), p_user, p_target, 'ZC001D synthetic CI support session ' || p_label, p_status,
      now() + p_expires, now() - interval '20 minutes', case when p_status = 'ended' then now() end,
      'zc001d-' || p_label || '-token-hash', case when p_consumed then now() - interval '5 minutes' end);
  insert into _ci_lbl values (pg_temp.zc_id(p_label), p_label) on conflict (id) do nothing;
  return true;
end $$;
-- A synthetic platform admin 'ci-sup-<key>' (JWT principal + linked app user, no membership), its grant
-- in status p_grant (NULL = none) and at most one support session (p_status NULL = none).
create function pg_temp.ci_sup_admin(p_key text, p_grant text, p_status text default null,
    p_target uuid default null, p_consumed boolean default true, p_expires interval default interval '10 minutes')
returns boolean language plpgsql volatile as $$
begin
  insert into auth.users (id, email)
  values (pg_temp.zc_id('ci-sup-' || p_key || '-auth'), 'zc001d-ci-sup-' || p_key || '@example.test');
  insert into public.app_users (id, email, auth_user_id)
  values (pg_temp.zc_id('ci-sup-' || p_key || '-user'), 'zc001d-ci-sup-' || p_key || '@example.test',
          pg_temp.zc_id('ci-sup-' || p_key || '-auth'));
  insert into _ci_lbl values (pg_temp.zc_id('ci-sup-' || p_key || '-auth'), 'ci-sup-' || p_key || '-auth'),
    (pg_temp.zc_id('ci-sup-' || p_key || '-user'), 'ci-sup-' || p_key || '-user');
  if p_grant is not null then
    insert into public.platform_admin_grants (app_user_id, status, granted_by, revoked_by, revoked_at)
    values (pg_temp.zc_id('ci-sup-' || p_key || '-user'), p_grant, pg_temp.zc_id('ci-support-user'),
            case when p_grant = 'revoked' then pg_temp.zc_id('ci-support-user') end,
            case when p_grant = 'revoked' then now() end);
  end if;
  if p_status is not null then
    perform pg_temp.ci_sup_session(pg_temp.zc_id('ci-sup-' || p_key || '-user'), 'ci-sup-' || p_key || '-session',
      p_target, p_status, p_consumed, p_expires);
  end if;
  return true;
end $$;
-- The recorded facts of one case (owner role, under the case's JWT): the caller, its support-session
-- resolution and own sessions, the PIN's employee / membership / liveness / device, the presented
-- device and the device whose session the presented token proves.
create function pg_temp.ci_sup_facts(p_pin uuid, p_d integer, p_token text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'jwt_sub', pg_temp.ci_lbl(auth.uid()),
    'app_user', pg_temp.ci_lbl(app.current_app_user_id()),
    'support_session', pg_temp.ci_lbl(app.current_support_session()),
    'support_target', pg_temp.ci_lbl((select s.target_organization_id from public.platform_support_sessions s
                                       where s.id = app.current_support_session())),
    'own_sessions', (select coalesce(jsonb_agg(jsonb_build_object('status', s.status,
                         'token_consumed', s.token_consumed_at is not null, 'unexpired', s.expires_at > now(),
                         'target', pg_temp.ci_lbl(s.target_organization_id)) order by s.created_at, s.id), '[]'::jsonb)
                       from public.platform_support_sessions s
                      where s.platform_admin_app_user_id = app.current_app_user_id()),
    'platform_admin', app.is_platform_admin(),
    'pin_employee', pg_temp.ci_lbl(ps.employee_profile_id),
    'pin_membership', pg_temp.ci_lbl(ps.resolved_membership_id),
    'membership', (select m.role || '/' || m.status from public.memberships m where m.id = ps.resolved_membership_id),
    'pin_live', ps.is_active and ps.ended_at is null and ps.expires_at > now(),
    'pin_device', pg_temp.ci_lbl(ds.device_id),
    'presented_device', pg_temp.ci_lbl(pg_temp.zc_id('device-' || p_d)),
    'token_proves', case when p_token is not null then pg_temp.ci_lbl((select t.device_id from public.device_sessions t
                      where t.device_id = pg_temp.zc_id('device-' || p_d)
                        and t.session_token_ref = app.hash_provisioning_secret(btrim(p_token)) limit 1)) end)
  from (select 1) one
  left join public.pin_sessions ps on ps.id = p_pin
  left join public.device_sessions ds on ds.id = ps.device_session_id $$;
-- The expected caller part and the expected staff part (staff p_n's PIN on d1 with d1's token).
create function pg_temp.ci_sup_caller(p_sub text, p_user text, p_session text, p_target text, p_admin boolean,
    p_sessions jsonb default '[]'::jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('jwt_sub', p_sub, 'app_user', p_user, 'support_session', p_session,
    'support_target', p_target, 'own_sessions', p_sessions, 'platform_admin', p_admin) $$;
create function pg_temp.ci_sup_sess(p_status text, p_consumed boolean, p_unexpired boolean, p_target text)
returns jsonb language sql immutable as $$
  select jsonb_build_object('status', p_status, 'token_consumed', p_consumed, 'unexpired', p_unexpired,
                            'target', p_target) $$;
create function pg_temp.ci_sup_staff(p_n integer) returns jsonb language sql immutable as $$
  select jsonb_build_object('pin_employee', 'employee-' || p_n, 'pin_membership', 'membership-' || p_n,
    'membership', case p_n when 1 then 'cashier/active' when 2 then 'manager/active' end, 'pin_live', true,
    'pin_device', 'device-1', 'presented_device', 'device-1', 'token_proves', 'device-1') $$;
create function pg_temp.ci_sup_nostaff() returns jsonb language sql immutable as $$
  select '{"pin_employee": null, "pin_membership": null, "membership": null, "pin_live": null, "pin_device": null,
           "presented_device": null, "token_proves": null}'::jsonb $$;
-- d1's device session and device rows; arming; the observed renewal state.
create function pg_temp.ci_sup_dev() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'device_session', (select to_jsonb(ds) from public.device_sessions ds where ds.id = pg_temp.zc_id('dsession-1')),
    'device', (select to_jsonb(d) from public.devices d where d.id = pg_temp.zc_id('device-1'))) $$;
create function pg_temp.ci_sup_arm() returns boolean language plpgsql volatile as $$
begin
  update public.device_sessions set expires_at = now() + interval '1 day' where id = pg_temp.zc_id('dsession-1');
  update public.devices set last_seen_at = null where id = pg_temp.zc_id('device-1');
  insert into _zc_r values ('sup_armed', pg_temp.ci_sup_dev()) on conflict (label) do update set r = excluded.r;
  return true;
end $$;
create function pg_temp.ci_sup_devstate() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'session_expiry', case when ds.expires_at = now() + interval '1 day' then 'armed'
                           when ds.expires_at = now() + interval '30 days' then 'renewed' else 'other' end,
    'last_seen', case when d.last_seen_at is null then 'null' when d.last_seen_at = now() then 'now' else 'other' end,
    'rows_as_armed', pg_temp.ci_sup_dev() = pg_temp.ci_r('sup_armed'))
  from public.device_sessions ds, public.devices d
  where ds.id = pg_temp.zc_id('dsession-1') and d.id = pg_temp.zc_id('device-1') $$;
create function pg_temp.ci_sup_armed() returns jsonb language sql immutable as $$
  select '{"session_expiry": "armed", "last_seen": "null", "rows_as_armed": true}'::jsonb $$;
create function pg_temp.ci_sup_renewed() returns jsonb language sql immutable as $$
  select '{"session_expiry": "renewed", "last_seen": "now", "rows_as_armed": false}'::jsonb $$;
-- One case's observation ('supf_<key>' facts, 'sup_<key>' answer) and its expectation.
create function pg_temp.ci_sup_outcome(p_key text) returns jsonb language sql stable as $$
  select jsonb_build_object('facts', pg_temp.ci_r('supf_' || p_key), 'answer', pg_temp.ci_r('sup_' || p_key) - 'server_ts',
    'written', pg_temp.ci_new(), 'device', pg_temp.ci_sup_devstate()) $$;
create function pg_temp.ci_sup_expect(p_facts jsonb, p_answer jsonb, p_device jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('facts', p_facts, 'answer', p_answer, 'written', pg_temp.ci_none(), 'device', p_device) $$;
-- C2 (D-060 point 2): an ok context answer carries caller_auth_user_id = auth.uid(), so an ok case is compared
-- with its transport-JWT control WITHOUT that key, and each binding is pinned separately (as a label) to its own
-- call's JWT subject: this case's to p_jwt_sub, the control's to the transport principal.
create function pg_temp.ci_sup_outcome_ok(p_key text, p_control text) returns jsonb language sql stable as $$
  select jsonb_build_object('facts', pg_temp.ci_r('supf_' || p_key),
    'answer', pg_temp.ci_r('sup_' || p_key) - 'server_ts' - 'caller_auth_user_id',
    'caller', pg_temp.ci_lbl((pg_temp.ci_r('sup_' || p_key) ->> 'caller_auth_user_id')::uuid),
    'control_caller', pg_temp.ci_lbl((pg_temp.ci_r(p_control) ->> 'caller_auth_user_id')::uuid),
    'written', pg_temp.ci_new(), 'device', pg_temp.ci_sup_devstate()) $$;
create function pg_temp.ci_sup_expect_ok(p_facts jsonb, p_control text, p_jwt_sub text) returns jsonb
language sql stable as $$
  select jsonb_build_object('facts', p_facts, 'answer', pg_temp.ci_r(p_control) - 'server_ts' - 'caller_auth_user_id',
    'caller', p_jwt_sub, 'control_caller', 'transport-principal', 'written', pg_temp.ci_none(),
    'device', pg_temp.ci_sup_renewed()) $$;
-- Counts of the rows this section must never write: the ledger, private events and tenant audit of both
-- fixture organizations, and the platform-admin audit naming them or any labelled identity.
create function pg_temp.ci_sup_counts() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'ledger', (select count(*) from app.card_provider_attempts
                where organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'events', (select count(*) from app.card_provider_private_events
                where organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'audit', (select count(*) from public.audit_events
               where organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'platform_audit', (select count(*) from public.platform_admin_audit_events x
                        where x.target_organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))
                           or x.actor_app_user_id in (select l.id from _ci_lbl l))) $$;

-- The identities: the CI-319 admin (an active session on the pilot organization) plus one admin per
-- session state; staff 2 (the manager of d1) is also a platform admin (the dual role, no session).
select pg_temp.ci_sup_admin('other', 'active', 'active', pg_temp.zc_id('org_b')) as other_org_session,
       pg_temp.ci_sup_admin('revoked-grant', 'revoked', 'active', pg_temp.zc_org()) as revoked_grant_session,
       pg_temp.ci_sup_admin('expired', 'active', 'active', pg_temp.zc_org(), true, interval '-5 minutes') as expired,
       pg_temp.ci_sup_admin('ended', 'active', 'ended', pg_temp.zc_org()) as ended,
       pg_temp.ci_sup_admin('pending', 'active', 'pending', pg_temp.zc_org(), false) as unexchanged,
       pg_temp.ci_sup_admin('unconsumed', 'active', 'active', pg_temp.zc_org(), false) as active_unconsumed,
       pg_temp.ci_sup_admin('grant', 'active') as grant_only;
insert into auth.users (id, email) values (pg_temp.zc_id('ci-dual-auth'), 'zc001d-ci-dual@example.test');
update public.app_users set auth_user_id = pg_temp.zc_id('ci-dual-auth') where id = pg_temp.zc_id('user-2');
insert into public.platform_admin_grants (app_user_id, status, granted_by)
values (pg_temp.zc_id('user-2'), 'active', pg_temp.zc_id('ci-support-user'));
insert into _zc_r values ('sup_counts_before', pg_temp.ci_sup_counts());
-- The resolution of each caller's JWT (the GUC is restored after each).
create function pg_temp.ci_sup_resolve(p_auth text) returns jsonb language plpgsql volatile as $$
declare
  v_prev text := current_setting('request.jwt.claim.sub', true);
  r jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.zc_id(p_auth)::text, true);
  r := jsonb_build_object('app_user', pg_temp.ci_lbl(app.current_app_user_id()),
         'support_session', pg_temp.ci_lbl(app.current_support_session()), 'platform_admin', app.is_platform_admin());
  perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
  return r;
end $$;
select is((select jsonb_object_agg(a, pg_temp.ci_sup_resolve(a)) from unnest(array['transport-principal',
      'ci-support-auth', 'ci-sup-other-auth', 'ci-sup-revoked-grant-auth', 'ci-sup-expired-auth', 'ci-sup-ended-auth',
      'ci-sup-pending-auth', 'ci-sup-unconsumed-auth', 'ci-sup-grant-auth', 'ci-dual-auth']) a),
  jsonb_build_object(
    'transport-principal', jsonb_build_object('app_user', null, 'support_session', null, 'platform_admin', false),
    'ci-support-auth', jsonb_build_object('app_user', 'ci-support-user', 'support_session', 'ci-support-session',
      'platform_admin', true),
    'ci-sup-other-auth', jsonb_build_object('app_user', 'ci-sup-other-user', 'support_session', 'ci-sup-other-session',
      'platform_admin', true),
    'ci-sup-revoked-grant-auth', jsonb_build_object('app_user', 'ci-sup-revoked-grant-user',
      'support_session', 'ci-sup-revoked-grant-session', 'platform_admin', false),
    'ci-sup-expired-auth', jsonb_build_object('app_user', 'ci-sup-expired-user', 'support_session', null,
      'platform_admin', true),
    'ci-sup-ended-auth', jsonb_build_object('app_user', 'ci-sup-ended-user', 'support_session', null,
      'platform_admin', true),
    'ci-sup-pending-auth', jsonb_build_object('app_user', 'ci-sup-pending-user', 'support_session', null,
      'platform_admin', true),
    'ci-sup-unconsumed-auth', jsonb_build_object('app_user', 'ci-sup-unconsumed-user', 'support_session', null,
      'platform_admin', true),
    'ci-sup-grant-auth', jsonb_build_object('app_user', 'ci-sup-grant-user', 'support_session', null,
      'platform_admin', true),
    'ci-dual-auth', jsonb_build_object('app_user', 'user-2', 'support_session', null, 'platform_admin', true)),
  'CI-324 support setup (C1-5): each JWT resolves its app user and app.current_support_session() — the transport principal no app user and no session; the CI-319 admin, an admin whose session targets organization B and an admin whose grant is revoked resolve an ACTIVE session; expired, ended, un-exchanged (pending) and active-status-but-unconsumed sessions, the grant-only admin and staff 2 as a dual-role admin resolve none');

-- Positive controls: the native transport JWT (no app user) with the cashier and the manager of d1.
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_ctl_cashier', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_ctl_cashier', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('ctl_cashier'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('transport-principal', null, null, null, false) || pg_temp.ci_sup_staff(1),
    jsonb_build_object('ok', true, 'caller_auth_user_id', pg_temp.zc_id('transport-principal'),
      'organization_id', pg_temp.zc_org(), 'restaurant_id', pg_temp.zc_rest(),
      'branch_id', pg_temp.zc_branch(), 'device_id', pg_temp.zc_id('device-1'), 'role', 'cashier',
      'employee_profile_id', pg_temp.zc_id('employee-1'), 'membership_id', pg_temp.zc_id('membership-1'),
      'order', jsonb_build_object('order_id', pg_temp.zc_id('order-ci-w-sup'), 'status', 'submitted',
        'grand_total_minor', 1234, 'currency_code', 'ILS', 'revision', 1, 'active_claim', true, 'settled', false),
      'attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-w-sup'), 'state', 'sent',
        'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
        'mode', 'live', 'own_device', true),
      'terminal', jsonb_build_object('lifecycle', 'enabled', 'mode', 'live'), 'card_terminal_enabled', true),
    pg_temp.ci_sup_renewed()),
  'CI-325 support positive control (C1-5): the native transport JWT (no app user, no support session) with cashier staff 1''s PIN on d1 and d1''s token, naming the CI-323 order and attempt -> ok with the proven scope, role cashier, the order facts (active claim), the attempt envelope (sent, own device) and the enabled LIVE terminal; d1''s device session renewed; no ledger, event or audit row (C2: + caller_auth_user_id = the transport principal, the call''s JWT subject)');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_ctl_manager', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-2'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_ctl_manager', pg_temp.ci_ctx(2, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('ctl_manager'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('transport-principal', null, null, null, false) || pg_temp.ci_sup_staff(2),
    (pg_temp.ci_r('sup_ctl_cashier') - 'server_ts') || jsonb_build_object('role', 'manager',
      'employee_profile_id', pg_temp.zc_id('employee-2'), 'membership_id', pg_temp.zc_id('membership-2')),
    pg_temp.ci_sup_renewed()),
  'CI-326 support positive control (C1-5): the transport JWT with manager staff 2''s PIN on d1 -> ok, the same answer as the cashier''s but role manager and employee / membership 2 (the manager resolves the attempt by branch, own device); renewed; nothing written');

-- An ACTIVE support session: refused before any proof, renewal or read.
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-support-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_a_cashier', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_a_cashier', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('a_cashier'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-support-auth', 'ci-support-user', 'ci-support-session', 'pilot-org', true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org'))) || pg_temp.ci_sup_staff(1),
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-327 support (C1-5): the CI-319 admin''s JWT (an ACTIVE session on the pilot organization) with cashier staff 1''s VALID PIN on d1 and d1''s token, naming the order and the attempt -> exactly {ok:false, error:permission_denied}: no scope, order or attempt fact; no ledger, event or audit row; d1''s device session NOT renewed (both rows exactly as armed)');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_a_manager', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-2'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_a_manager', pg_temp.ci_ctx(2, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('a_manager'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-support-auth', 'ci-support-user', 'ci-support-session', 'pilot-org', true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org'))) || pg_temp.ci_sup_staff(2),
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-328 support (C1-5): the same active session with manager staff 2''s VALID PIN on d1 and d1''s token -> exactly permission_denied; nothing written; not renewed');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_a_none', pg_temp.ci_sup_facts(null, null, null)),
  ('supf_a_unknown_pin', pg_temp.ci_sup_facts(pg_temp.zc_id('ci-support-no-pin'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values
  ('sup_a_none', public.card_attempt_context(null, null, null, null, null)),
  ('sup_a_null_pin', public.card_attempt_context(null, pg_temp.zc_id('device-1'), 'zc-token-1',
     pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup'))),
  ('sup_a_unknown_pin', public.card_attempt_context(pg_temp.zc_id('ci-support-no-pin'), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(jsonb_build_object(
    'facts', jsonb_build_object('no_inputs', pg_temp.ci_r('supf_a_none'), 'unknown_pin', pg_temp.ci_r('supf_a_unknown_pin')),
    'answers', jsonb_build_object('no_inputs', pg_temp.ci_r('sup_a_none') - 'server_ts',
      'null_pin', pg_temp.ci_r('sup_a_null_pin') - 'server_ts', 'unknown_pin', pg_temp.ci_r('sup_a_unknown_pin') - 'server_ts'),
    'written', pg_temp.ci_new(), 'device', pg_temp.ci_sup_devstate()),
  jsonb_build_object(
    'facts', jsonb_build_object(
      'no_inputs', pg_temp.ci_sup_caller('ci-support-auth', 'ci-support-user', 'ci-support-session', 'pilot-org', true,
        jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org'))) || pg_temp.ci_sup_nostaff(),
      'unknown_pin', pg_temp.ci_sup_caller('ci-support-auth', 'ci-support-user', 'ci-support-session', 'pilot-org', true,
        jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org'))) || pg_temp.ci_sup_nostaff()
        || '{"presented_device": "device-1", "token_proves": "device-1"}'::jsonb),
    'answers', jsonb_build_object('no_inputs', pg_temp.ci_refusal('permission_denied'),
      'null_pin', pg_temp.ci_refusal('permission_denied'), 'unknown_pin', pg_temp.ci_refusal('permission_denied')),
    'written', pg_temp.ci_none(), 'device', pg_temp.ci_sup_armed()),
  'CI-329 support (C1-5): the active session support-only (no staff PIN session) — no inputs at all, a NULL PIN and an unknown PIN id each with d1 and its VALID token, the order and the attempt -> exactly permission_denied each (not invalid_session); nothing written; d1''s device session NOT renewed although its token is valid (both rows exactly as armed)');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_a_bad_id', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_a_bad_id', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), 'not-a-uuid'));
reset role;
select is(pg_temp.ci_sup_outcome('a_bad_id'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-support-auth', 'ci-support-user', 'ci-support-session', 'pilot-org', true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org'))) || pg_temp.ci_sup_staff(1),
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-330 support (C1-5): the active session with the cashier''s valid inputs and a malformed attempt id -> permission_denied, not invalid_request (the support gate precedes the request-shape check); nothing written; not renewed');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_a_forged', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-forged'));
set local role authenticated;
insert into _zc_r values ('sup_a_forged', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup'),
  p_token => 'zc-token-forged'));
reset role;
select is(pg_temp.ci_sup_outcome('a_forged'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-support-auth', 'ci-support-user', 'ci-support-session', 'pilot-org', true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org')))
    || pg_temp.ci_sup_staff(1) || '{"token_proves": null}'::jsonb,
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-331 support (C1-5): the active session with the cashier''s PIN and a forged device token -> permission_denied, not invalid_session (refused before the device proof); nothing written; not renewed');

-- An ACTIVE support session targeting ANOTHER organization (organization B).
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-other-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_b_cashier', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_b_cashier', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('b_cashier'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-sup-other-auth', 'ci-sup-other-user', 'ci-sup-other-session', 'org_b', true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'org_b'))) || pg_temp.ci_sup_staff(1),
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-332 support (C1-5): an admin whose ACTIVE session targets organization B, with pilot cashier staff 1''s valid PIN on d1 and d1''s token -> exactly permission_denied (any active session, whatever its target); nothing written; not renewed');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_b_manager', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-2'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_b_manager', pg_temp.ci_ctx(2, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('b_manager'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-sup-other-auth', 'ci-sup-other-user', 'ci-sup-other-session', 'org_b', true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'org_b'))) || pg_temp.ci_sup_staff(2),
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-333 support (C1-5): the organization-B session with pilot manager staff 2''s valid PIN on d1 -> exactly permission_denied; nothing written; not renewed');

-- The session alone decides: an active session whose platform-admin grant is revoked.
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-revoked-grant-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_h_cashier', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_h_cashier', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('h_cashier'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-sup-revoked-grant-auth', 'ci-sup-revoked-grant-user', 'ci-sup-revoked-grant-session',
      'pilot-org', false, jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org')))
    || pg_temp.ci_sup_staff(1),
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-334 support (C1-5): an ACTIVE session whose admin''s platform-admin grant is revoked (is_platform_admin false), with the cashier''s valid inputs -> permission_denied (the active session alone decides); nothing written; not renewed');

-- Sessions that are not active: the normal proof decides (the transport-JWT answer, renewed).
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-expired-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_c_expired', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_c_expired', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('c_expired', 'sup_ctl_cashier'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-sup-expired-auth', 'ci-sup-expired-user', null, null, true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, false, 'pilot-org'))) || pg_temp.ci_sup_staff(1),
    'sup_ctl_cashier', 'ci-sup-expired-auth'),
  'CI-335 support (C1-5): an EXPIRED session (status active, token consumed, expires_at past) is not active -> the normal proof decides: the cashier''s valid inputs answer ok, exactly the transport-JWT answer (CI-325) (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-sup-expired-auth, the control''s = the transport principal); renewed; nothing written');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-ended-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_d_ended', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_d_ended', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('d_ended', 'sup_ctl_cashier'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-sup-ended-auth', 'ci-sup-ended-user', null, null, true,
      jsonb_build_array(pg_temp.ci_sup_sess('ended', true, true, 'pilot-org'))) || pg_temp.ci_sup_staff(1),
    'sup_ctl_cashier', 'ci-sup-ended-auth'),
  'CI-336 support (C1-5): an ENDED session (status ended, token consumed, not yet past expires_at) is not active -> the cashier''s valid inputs answer ok, exactly the transport-JWT answer (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-sup-ended-auth, the control''s = the transport principal); renewed; nothing written');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-pending-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_e_pending', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_e_pending', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('e_pending', 'sup_ctl_cashier'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-sup-pending-auth', 'ci-sup-pending-user', null, null, true,
      jsonb_build_array(pg_temp.ci_sup_sess('pending', false, true, 'pilot-org'))) || pg_temp.ci_sup_staff(1),
    'sup_ctl_cashier', 'ci-sup-pending-auth'),
  'CI-337 support (C1-5): an UN-EXCHANGED session (status pending, token never consumed) is not active -> the cashier''s valid inputs answer ok, exactly the transport-JWT answer (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-sup-pending-auth, the control''s = the transport principal); renewed; nothing written');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-unconsumed-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_f_unconsumed', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_f_unconsumed', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('f_unconsumed', 'sup_ctl_cashier'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-sup-unconsumed-auth', 'ci-sup-unconsumed-user', null, null, true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', false, true, 'pilot-org'))) || pg_temp.ci_sup_staff(1),
    'sup_ctl_cashier', 'ci-sup-unconsumed-auth'),
  'CI-338 support (C1-5): a session with status active whose token was never consumed is not active (the token term) -> the cashier''s valid inputs answer ok, exactly the transport-JWT answer (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-sup-unconsumed-auth, the control''s = the transport principal); renewed; nothing written');

-- A platform-admin grant with NO support session: no gate (the dual role is not banned).
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-grant-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_g_cashier', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_g_cashier', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('g_cashier', 'sup_ctl_cashier'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-sup-grant-auth', 'ci-sup-grant-user', null, null, true) || pg_temp.ci_sup_staff(1),
    'sup_ctl_cashier', 'ci-sup-grant-auth'),
  'CI-339 support (C1-5): a platform-admin grant with NO support session, with the cashier''s valid PIN on d1 and d1''s token -> ok, exactly the transport-JWT answer (a grant alone changes nothing) (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-sup-grant-auth, the control''s = the transport principal); renewed; nothing written');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_g_manager', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-2'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_g_manager', pg_temp.ci_ctx(2, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('g_manager', 'sup_ctl_manager'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-sup-grant-auth', 'ci-sup-grant-user', null, null, true) || pg_temp.ci_sup_staff(2),
    'sup_ctl_manager', 'ci-sup-grant-auth'),
  'CI-340 support (C1-5): the grant-only admin with manager staff 2''s valid PIN on d1 -> ok, exactly the transport-JWT manager answer (CI-326) (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-sup-grant-auth, the control''s = the transport principal); renewed; nothing written');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_g_none', pg_temp.ci_sup_facts(null, null, null));
set local role authenticated;
insert into _zc_r values
  ('sup_g_none', public.card_attempt_context(null, null, null, null, null)),
  ('sup_g_null_pin', public.card_attempt_context(null, pg_temp.zc_id('device-1'), 'zc-token-1',
     pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(jsonb_build_object('facts', pg_temp.ci_r('supf_g_none'), 'answers', jsonb_build_object(
      'no_inputs', pg_temp.ci_r('sup_g_none') - 'server_ts', 'null_pin', pg_temp.ci_r('sup_g_null_pin') - 'server_ts'),
    'written', pg_temp.ci_new(), 'device', pg_temp.ci_sup_devstate()),
  jsonb_build_object('facts', pg_temp.ci_sup_caller('ci-sup-grant-auth', 'ci-sup-grant-user', null, null, true)
      || pg_temp.ci_sup_nostaff(),
    'answers', jsonb_build_object('no_inputs', pg_temp.ci_refusal('invalid_session'),
      'null_pin', pg_temp.ci_refusal('invalid_session')),
    'written', pg_temp.ci_none(), 'device', pg_temp.ci_sup_armed()),
  'CI-341 support (C1-5): the grant-only admin WITHOUT staff inputs — no inputs at all, and a NULL PIN with d1, its valid token, the order and the attempt -> exactly {ok:false, error:invalid_session} each (the normal proof decides; no scope, order or attempt fact); nothing written; d1''s session untouched (refused before the device proof)');
select pg_temp.ci_mark();
set local role authenticated;
insert into _zc_r values ('sup_g_unknown_pin', public.card_attempt_context(pg_temp.zc_id('ci-support-no-pin'),
  pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('sup_g_unknown_pin') - 'server_ts', 'written', pg_temp.ci_new()),
  jsonb_build_object('answer', pg_temp.ci_refusal('invalid_session'), 'written', pg_temp.ci_none()),
  'CI-342 support (C1-5): the grant-only admin with an unknown PIN id on d1 with its valid token (no staff PIN session) -> exactly invalid_session, no order / attempt fact, no ledger, event or audit row');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_g_bad_id', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-1'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_g_bad_id', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-w-sup'), 'not-a-uuid'));
reset role;
select is(pg_temp.ci_sup_outcome('g_bad_id'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-sup-grant-auth', 'ci-sup-grant-user', null, null, true) || pg_temp.ci_sup_staff(1),
    pg_temp.ci_refusal('invalid_request'), pg_temp.ci_sup_armed()),
  'CI-343 support (C1-5): the grant-only admin with the cashier''s valid inputs and a malformed attempt id -> invalid_request, the normal refusal order (contrast CI-330: only an active session answers permission_denied); nothing written; not renewed');

-- The dual role: staff 2 (manager of d1) is also a platform admin, on its own JWT and PIN.
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-dual-auth')::text, true);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_dual_grant', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-2'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_dual_grant', pg_temp.ci_ctx(2, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('dual_grant', 'sup_ctl_manager'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-dual-auth', 'user-2', null, null, true) || pg_temp.ci_sup_staff(2),
    'sup_ctl_manager', 'ci-dual-auth'),
  'CI-344 support (C1-5): the dual role — staff 2''s own JWT (app user 2, an active platform-admin grant, no support session) with its own manager PIN on d1 -> ok, exactly the transport-JWT manager answer (the dual role is not banned) (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-dual-auth, the control''s = the transport principal); renewed; nothing written');
select pg_temp.ci_sup_session(pg_temp.zc_id('user-2'), 'ci-dual-session', pg_temp.zc_org(), 'active', true,
                              interval '10 minutes') as dual_session_active;
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_dual_active', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-2'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_dual_active', pg_temp.ci_ctx(2, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome('dual_active'), pg_temp.ci_sup_expect(
    pg_temp.ci_sup_caller('ci-dual-auth', 'user-2', 'ci-dual-session', 'pilot-org', true,
      jsonb_build_array(pg_temp.ci_sup_sess('active', true, true, 'pilot-org'))) || pg_temp.ci_sup_staff(2),
    pg_temp.ci_refusal('permission_denied'), pg_temp.ci_sup_armed()),
  'CI-345 support (C1-5): the same dual-role person once an ACTIVE support session of its own exists on the pilot organization -> its own valid manager PIN on d1 answers exactly permission_denied; nothing written; not renewed');
update public.platform_support_sessions set status = 'ended', ended_at = now()
 where id = pg_temp.zc_id('ci-dual-session');
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
insert into _zc_r values ('supf_dual_ended', pg_temp.ci_sup_facts(pg_temp.zc_id('pin-2'), 1, 'zc-token-1'));
set local role authenticated;
insert into _zc_r values ('sup_dual_ended', pg_temp.ci_ctx(2, pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup')));
reset role;
select is(pg_temp.ci_sup_outcome_ok('dual_ended', 'sup_ctl_manager'), pg_temp.ci_sup_expect_ok(
    pg_temp.ci_sup_caller('ci-dual-auth', 'user-2', null, null, true,
      jsonb_build_array(pg_temp.ci_sup_sess('ended', true, true, 'pilot-org'))) || pg_temp.ci_sup_staff(2),
    'sup_ctl_manager', 'ci-dual-auth'),
  'CI-346 support (C1-5): after that session is ended the dual-role person''s own PIN answers ok again, exactly the transport-JWT manager answer (C2: compared without caller_auth_user_id; this answer''s caller_auth_user_id = its own JWT subject ci-dual-auth, the control''s = the transport principal); renewed; nothing written');
select is(pg_temp.ci_sup_counts(), pg_temp.ci_r('sup_counts_before'),
  'CI-347 support (C1-5): across every support case above no ledger row, private event or tenant audit row of either fixture organization and no platform-admin audit row naming them or any labelled identity was written (counts unchanged)');

-- ===========================================================================
-- 24. Direct grants under the support context (C1-5): authenticated (the
--     support JWT) cannot execute any service-only body on either layer;
--     service_role cannot execute card_attempt_context on either layer. Every
--     call carries otherwise admissible inputs, so a missing grant would act.
-- ===========================================================================
select pg_temp.zc_order('ci-sup-g', 1234) is not null as sup_g_order;
create function pg_temp.ci_try(p_sql text) returns text language plpgsql volatile as $$
begin
  execute p_sql;
  return 'executed';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end $$;
create temp table _ci_svc_calls (fn text primary key, q text not null);
grant select on _ci_svc_calls to authenticated, service_role;
insert into _ci_svc_calls values
  ('public.card_attempt_claim', $q$select public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_lop('ci-sup-g'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-sup-g'), 1, 'production',
     pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller())$q$),
  ('app.card_attempt_claim', $q$select app.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_lop('ci-sup-g'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-sup-g'), 1, 'production',
     pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1', pg_temp.zc_caller())$q$),
  ('public.card_attempt_adapter_read', $q$select public.card_attempt_adapter_read(pg_temp.zc_id('pin-1'),
     pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'production', pg_temp.zc_terminals(1, 'live'),
     pg_temp.zc_credentials(1, 'live'), pg_temp.zc_caller())$q$),
  ('app.card_attempt_adapter_read', $q$select app.card_attempt_adapter_read(pg_temp.zc_id('pin-1'),
     pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'production', pg_temp.zc_terminals(1, 'live'),
     pg_temp.zc_credentials(1, 'live'), pg_temp.zc_caller())$q$),
  ('public.card_attempt_finish', $q$select pg_temp.zc_finish(pg_temp.ci_r('sup_claim_control'), 'commit', 'approved',
     pg_temp.zc_approved_fields())$q$),
  ('app.card_attempt_finish', $q$select app.card_attempt_finish((c ->> 'attempt_row_id')::uuid,
     (c ->> 'organization_id')::uuid, (c ->> 'device_id')::uuid, c ->> 'local_operation_id', c ->> 'mode',
     (c ->> 'amount_minor')::bigint, c ->> 'currency_code', 'commit', 'approved', pg_temp.zc_approved_fields(), null)
     from (select pg_temp.ci_r('sup_claim_control') as c) x$q$),
  ('public.card_attempt_mark_release_requested', $q$select public.card_attempt_mark_release_requested(
     pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), pg_temp.zc_caller())$q$),
  ('app.card_attempt_mark_release_requested', $q$select app.card_attempt_mark_release_requested(
     pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), pg_temp.zc_caller())$q$),
  ('public.card_attempt_mark_recording_result', $q$select public.card_attempt_mark_recording_result(
     pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'permission_denied', pg_temp.zc_caller())$q$),
  ('app.card_attempt_mark_recording_result', $q$select app.card_attempt_mark_recording_result(
     pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'permission_denied', pg_temp.zc_caller())$q$),
  ('public.card_attempt_free_order', $q$select public.card_attempt_free_order(pg_temp.zc_id('pin-2'),
     pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'ZC001D synthetic manager free',
     'provider_report', 'zc-report-g', pg_temp.zc_caller())$q$),
  ('app.card_attempt_free_order', $q$select app.card_attempt_free_order(pg_temp.zc_id('pin-2'),
     pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('ci-w-sup'), 'ZC001D synthetic manager free',
     'provider_report', 'zc-report-g', pg_temp.zc_caller())$q$),
  ('public.card_attempt_context', $q$select public.card_attempt_context(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup'))$q$),
  ('app.card_attempt_context', $q$select app.card_attempt_context(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_id('order-ci-w-sup'), pg_temp.zc_lop('ci-w-sup'))$q$);
select pg_temp.ci_sup_arm() as armed;
select pg_temp.ci_mark();
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-support-auth')::text, true);
set local role authenticated;
insert into _zc_r select 'grant_auth', jsonb_object_agg(c.fn, pg_temp.ci_try(c.q)) from _ci_svc_calls c
 where c.fn not like '%card_attempt_context';
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
set local role service_role;
insert into _zc_r select 'grant_service', jsonb_object_agg(c.fn, pg_temp.ci_try(c.q)) from _ci_svc_calls c
 where c.fn like '%card_attempt_context';
reset role;
select is(pg_temp.ci_r('grant_auth'),
  (select jsonb_object_agg(c.fn, '42501 permission denied for function ' || split_part(c.fn, '.', 2))
     from _ci_svc_calls c where c.fn not like '%card_attempt_context'),
  'CI-348 grants (C1-5): authenticated under the support-session JWT raises 42501 permission denied on every service-only function of both layers — claim, adapter_read, finish, mark_release_requested, mark_recording_result and free_order, public wrapper and app body (12 calls with otherwise admissible inputs)');
select is(pg_temp.ci_r('grant_service'),
  '{"app.card_attempt_context": "42501 permission denied for function card_attempt_context",
    "public.card_attempt_context": "42501 permission denied for function card_attempt_context"}'::jsonb,
  'CI-349 grants (C1-5): service_role raises 42501 permission denied on card_attempt_context, public wrapper and app body (the caller-authority proof is authenticated-only), with the cashier''s valid inputs under the transport JWT');
select is((select jsonb_object_agg(c.fn, (select jsonb_build_object('overloads', count(*),
        'anon', bool_or(has_function_privilege('anon', pp.oid, 'execute')),
        'authenticated', bool_or(has_function_privilege('authenticated', pp.oid, 'execute')),
        'service_role', bool_or(has_function_privilege('service_role', pp.oid, 'execute')))
      from pg_proc pp join pg_namespace n on n.oid = pp.pronamespace
     where n.nspname = split_part(c.fn, '.', 1) and pp.proname = split_part(c.fn, '.', 2)))
     from _ci_svc_calls c),
  (select jsonb_object_agg(c.fn, jsonb_build_object('overloads', 1, 'anon', false,
      'authenticated', c.fn like '%card_attempt_context', 'service_role', c.fn not like '%card_attempt_context'))
     from _ci_svc_calls c),
  'CI-350 grants (C1-5): the catalog agrees — each of the 14 names has one signature; EXECUTE on the 12 service-only functions for service_role only, on both card_attempt_context layers for authenticated only, never for anon');
select is(jsonb_build_object('written', pg_temp.ci_new(), 'device', pg_temp.ci_sup_devstate(),
    'claim_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-sup-g')) is not null),
  jsonb_build_object('written', pg_temp.ci_none(), 'device', pg_temp.ci_sup_armed(), 'claim_row', false),
  'CI-351 grants (C1-5): the refused calls wrote no ledger, event or audit row, created no claim row and did not renew d1''s device session');

-- ===========================================================================
-- 25. Revocation between the context proof and the interactive mutation
--     (C1-5; T-023): the context answers ok, then the PIN's membership is
--     revoked, then the service-only claim, a mark and free_order each re-prove
--     at write time and answer invalid_session with nothing written; restored,
--     the same calls act.
-- ===========================================================================
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
select pg_temp.zc_order('ci-sup-rv', 1234) is not null as sup_rv,
       pg_temp.zc_order('ci-sup-rv-free', 1234) is not null as sup_rv_free;
set local role service_role;
insert into _zc_r values ('rv_free_claim', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-sup-rv-free'), 'live',
  p_order => pg_temp.zc_id('order-ci-sup-rv-free'), p_rev => 1));
insert into _zc_r values ('rv_free_fin', pg_temp.zc_finish(pg_temp.ci_r('rv_free_claim'), 'commit', 'unknown'));
insert into _zc_r values ('rv_free_look', pg_temp.zc_finish(pg_temp.ci_r('rv_free_claim'), 'lookup', 'pending',
  '{}'::jsonb, 'operator'));
reset role;
select count(pg_temp.ci_ok(pg_temp.ci_r(l))) as rv_setup_calls_ok
  from unnest(array['rv_free_claim', 'rv_free_fin', 'rv_free_look']) l;
select pg_temp.ci_mark();
set local role authenticated;
insert into _zc_r values
  ('rv_ctx_claim', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-sup-rv'))),
  ('rv_ctx_mark', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-w-sup'))),
  ('rv_ctx_free', pg_temp.ci_ctx(2, p_attempt => pg_temp.zc_lop('ci-sup-rv-free')));
reset role;
select is(jsonb_build_object(
    'claim', jsonb_build_object('ok', pg_temp.ci_r('rv_ctx_claim') -> 'ok', 'role', pg_temp.ci_r('rv_ctx_claim') -> 'role',
      'order', pg_temp.ci_r('rv_ctx_claim') -> 'order',
      'card_terminal_enabled', pg_temp.ci_r('rv_ctx_claim') -> 'card_terminal_enabled'),
    'mark', jsonb_build_object('ok', pg_temp.ci_r('rv_ctx_mark') -> 'ok', 'role', pg_temp.ci_r('rv_ctx_mark') -> 'role',
      'attempt', pg_temp.ci_r('rv_ctx_mark') -> 'attempt'),
    'free', jsonb_build_object('ok', pg_temp.ci_r('rv_ctx_free') -> 'ok', 'role', pg_temp.ci_r('rv_ctx_free') -> 'role',
      'attempt', pg_temp.ci_r('rv_ctx_free') -> 'attempt'),
    'written', pg_temp.ci_new()),
  jsonb_build_object(
    'claim', jsonb_build_object('ok', true, 'role', 'cashier',
      'order', jsonb_build_object('order_id', pg_temp.zc_id('order-ci-sup-rv'), 'status', 'submitted',
        'grand_total_minor', 1234, 'currency_code', 'ILS', 'revision', 1, 'active_claim', false, 'settled', false),
      'card_terminal_enabled', true),
    'mark', jsonb_build_object('ok', true, 'role', 'cashier',
      'attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-w-sup'), 'state', 'sent',
        'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
        'mode', 'live', 'own_device', true)),
    'free', jsonb_build_object('ok', true, 'role', 'manager',
      'attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('ci-sup-rv-free'), 'state', 'unknown',
        'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
        'mode', 'live', 'own_device', true)),
    'written', pg_temp.ci_none()),
  'CI-352 revocation (C1-5): the context proofs first answer ok under the transport JWT — cashier staff 1 for the claim''s fresh order (no active claim, starts enabled) and for the sent attempt ci-w-sup, manager staff 2 for the looked-up unknown attempt ci-sup-rv-free; nothing written');
insert into _zc_r values ('rv_before', jsonb_build_object(
  'claim_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-sup-rv')),
  'claim_order', (select to_jsonb(o) from public.orders o where o.id = pg_temp.zc_id('order-ci-sup-rv')),
  'mark_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-sup')),
  'free_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-sup-rv-free')),
  'free_order', (select to_jsonb(o) from public.orders o where o.id = pg_temp.zc_id('order-ci-sup-rv-free'))));
update memberships set status = 'revoked', deleted_at = now()
 where id in (pg_temp.zc_id('membership-1'), pg_temp.zc_id('membership-2'));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('rv_after', jsonb_build_object(
  'claim', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-sup-rv'), 'live', p_order => pg_temp.zc_id('order-ci-sup-rv'),
                            p_rev => 1) - 'server_ts',
  'mark_release_requested', pg_temp.ci_mk('mark_release_requested', 1, pg_temp.zc_lop('ci-w-sup')) - 'server_ts',
  'free_order', pg_temp.ci_free(2, pg_temp.zc_lop('ci-sup-rv-free'), 'provider_report', 'zc-report-rv') - 'server_ts'));
reset role;
set local role authenticated;
insert into _zc_r values ('rv_ctx_after', jsonb_build_object(
  'cashier', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-sup-rv')) - 'server_ts',
  'manager', pg_temp.ci_ctx(2, p_attempt => pg_temp.zc_lop('ci-sup-rv-free')) - 'server_ts'));
reset role;
update memberships set status = 'active', deleted_at = null
 where id in (pg_temp.zc_id('membership-1'), pg_temp.zc_id('membership-2'));
select is(pg_temp.ci_r('rv_after'), jsonb_build_object('claim', pg_temp.ci_refusal('invalid_session'),
    'mark_release_requested', pg_temp.ci_refusal('invalid_session'), 'free_order', pg_temp.ci_refusal('invalid_session')),
  'CI-353 revocation (C1-5): with both memberships revoked after those proofs (status revoked + deleted_at), the service-only claim (staff 1, the proven order), mark_release_requested (staff 1, ci-w-sup) and free_order (staff 2, ci-sup-rv-free) each re-prove at write time and answer exactly {ok:false, error:invalid_session}');
select is(jsonb_build_object('written', pg_temp.ci_new(), 'rows', jsonb_build_object(
    'claim_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-sup-rv')),
    'claim_order', (select to_jsonb(o) from public.orders o where o.id = pg_temp.zc_id('order-ci-sup-rv')),
    'mark_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-w-sup')),
    'free_row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-sup-rv-free')),
    'free_order', (select to_jsonb(o) from public.orders o where o.id = pg_temp.zc_id('order-ci-sup-rv-free')))),
  jsonb_build_object('written', pg_temp.ci_none(), 'rows', pg_temp.ci_r('rv_before')),
  'CI-354 revocation (C1-5): those three refusals and the two context refusals of CI-355 wrote nothing — no claim row, no ledger change, no private event, no audit (no denial evidence for an invalid session); both attempt rows and both order rows identical (every column)');
select is(pg_temp.ci_r('rv_ctx_after'), jsonb_build_object('cashier', pg_temp.ci_refusal('invalid_session'),
    'manager', pg_temp.ci_refusal('invalid_session')),
  'CI-355 revocation (C1-5): while revoked the context proof itself answers exactly invalid_session for both staff (the revocation reaches every proof)');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values
  ('rv_ctl_claim', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-sup-rv'), 'live', p_order => pg_temp.zc_id('order-ci-sup-rv'),
                                    p_rev => 1)),
  ('rv_ctl_mark', pg_temp.ci_mk('mark_release_requested', 1, pg_temp.zc_lop('ci-w-sup'))),
  ('rv_ctl_free', pg_temp.ci_free(2, pg_temp.zc_lop('ci-sup-rv-free'), 'provider_report', 'zc-report-rv'));
reset role;
select is(jsonb_build_object('claim_created', pg_temp.ci_r('rv_ctl_claim') -> 'claim_created',
    'mark', pg_temp.ci_r('rv_ctl_mark') - 'server_ts', 'free', pg_temp.ci_r('rv_ctl_free') - 'server_ts',
    'written', pg_temp.ci_new(), 'audit', pg_temp.ci_new_audit_proj(),
    'mark_stamped', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-w-sup'))).release_requested_at is not null,
    'freed', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-sup-rv-free'))).order_freed_reason),
  jsonb_build_object('claim_created', true,
    'mark', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-w-sup'), 'state', 'sent',
      'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS'),
    'free', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-sup-rv-free'), 'state', 'unknown',
      'classification', 'freed', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS'),
    'written', jsonb_build_object('ledger', 1, 'events', 0, 'audit', 3),
    'audit', jsonb_build_array(
      pg_temp.ci_audit('card_attempt.order_freed', '{"attempt_state": "unknown", "confirmation_source": "provider_report"}'::jsonb, 2, 1),
      pg_temp.ci_audit('card_attempt.release_requested', '{"attempt_state": "sent"}'::jsonb, 1, 1),
      pg_temp.ci_audit('card_attempt.started', '{"attempt_state": "sent", "mode": "live", "amount_minor": 1234, "currency_code": "ILS"}'::jsonb, 1, 1)),
    'mark_stamped', true, 'freed', 'manager_confirmed'),
  'CI-356 revocation control (C1-5): memberships restored, the same three calls act — the claim is created, the release mark stamps ci-w-sup (sent envelope), free_order frees ci-sup-rv-free (classification freed, manager_confirmed) — with exactly one ledger row and three audit rows (order_freed by employee 2, release_requested and started by employee 1, all on d1) and no private event');

-- ===========================================================================
-- 26. A provider fact after the PIN session expired (C1-5): card_attempt_finish
--     is scope-bound (no PIN, device-session or JWT authority), so it still
--     records the provider fact under its unchanged rules, while the
--     interactive proof of that PIN answers invalid_session.
-- ===========================================================================
update pin_sessions set expires_at = now() - interval '1 minute' where id = pg_temp.zc_id('pin-1');
select pg_temp.ci_mark();
set local role authenticated;
insert into _zc_r values ('pe_ctx', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-sup-rv'), pg_temp.zc_lop('ci-sup-rv')));
reset role;
select is(jsonb_build_object('pin_live', (select ps.expires_at > now() from public.pin_sessions ps
                                            where ps.id = pg_temp.zc_id('pin-1')),
    'context', pg_temp.ci_r('pe_ctx') - 'server_ts', 'written', pg_temp.ci_new()),
  jsonb_build_object('pin_live', false, 'context', pg_temp.ci_refusal('invalid_session'), 'written', pg_temp.ci_none()),
  'CI-357 PIN expiry (C1-5): with cashier staff 1''s PIN session expired (expires_at past), its context proof for the claimed order and attempt answers exactly invalid_session; nothing written');
insert into _zc_r values ('pe_row_before', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-sup-rv')));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pe_mismatch', public.card_attempt_finish(
  (pg_temp.ci_r('rv_ctl_claim') ->> 'attempt_row_id')::uuid, pg_temp.zc_org(), pg_temp.zc_id('device-1'),
  pg_temp.zc_lop('ci-sup-rv'), 'live', 1235, 'ILS', 'commit', 'approved', pg_temp.zc_approved_fields(), null));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('pe_mismatch') - 'server_ts', 'written', pg_temp.ci_new(),
    'events', pg_temp.ci_new_events_proj(), 'row', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-sup-rv'))),
  jsonb_build_object('answer', pg_temp.ci_refusal('conflict', 'attempt_scope_mismatch'),
    'written', jsonb_build_object('ledger', 0, 'events', 1, 'audit', 0),
    'events', jsonb_build_array(pg_temp.ci_event('security.card_finish_scope_mismatch', 'live',
        '{"organization_id": false, "device_id": false, "local_operation_id": false, "mode": false,
          "amount_minor": true, "currency_code": false}'::jsonb, null, 1,
        (pg_temp.ci_r('rv_ctl_claim') ->> 'attempt_row_id')::uuid)
      || '{"actor_kind": "adapter", "actor_reference": "card_adapter"}'::jsonb),
    'row', pg_temp.ci_r('pe_row_before')),
  'CI-358 PIN expiry (C1-5): the finish stays scope-bound — a commit reply naming the claim with a different amount answers conflict / attempt_scope_mismatch with exactly one security.card_finish_scope_mismatch event (amount_minor only), no audit, the attempt row unchanged');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('pe_finish', pg_temp.zc_finish(pg_temp.ci_r('rv_ctl_claim'), 'commit', 'approved',
  pg_temp.zc_approved_fields()));
reset role;
update pin_sessions set expires_at = now() + interval '6 hours' where id = pg_temp.zc_id('pin-1');
select is(jsonb_build_object('answer', pg_temp.ci_r('pe_finish') - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_new_audit_proj(),
    'row', (select jsonb_build_object('state', a.state, 'charge_may_exist', a.charge_may_exist,
              'provider_return_code', a.provider_return_code, 'approval_type', a.approval_type,
              'provider_status_code', a.provider_status_code, 'provider_return_class', a.provider_return_class,
              'provider_approved_at', a.provider_approved_at is not null, 'finished_at', a.finished_at is not null)
              from pg_temp.ci_row(1, pg_temp.zc_lop('ci-sup-rv')) a)),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-sup-rv'),
      'state', 'approved', 'classification', 'approved_unrecorded', 'recorded', false, 'amount_minor', 1234,
      'currency_code', 'ILS', 'provider_return_code', 0, 'recoverable', false, 'resume_count', 0),
    'written', jsonb_build_object('ledger', 0, 'events', 0, 'audit', 1),
    'audit', jsonb_build_array(pg_temp.ci_audit('card_attempt.approved',
      '{"attempt_state": "approved", "release_requested": false}'::jsonb, 1, 1)),
    'row', jsonb_build_object('state', 'approved', 'charge_may_exist', false, 'provider_return_code', 0,
      'approval_type', 'approved', 'provider_status_code', 'ok1', 'provider_return_class', 'approved',
      'provider_approved_at', true, 'finished_at', true)),
  'CI-359 PIN expiry (C1-5): the exact commit reply after the PIN session expired still records the provider fact — approved_unrecorded envelope (return code 0, not recoverable, resume_count 0), the row approved with its sanitized provider facts, exactly one card_attempt.approved audit row for the initiating employee 1 on d1, no private event');

-- ===========================================================================
-- 27. Correction C2 (D-060 point 2; packet §13.2, §13.5 CI): the required
--     original-caller binding. The five session-proving service-only
--     operations (claim, adapter_read, mark_release_requested,
--     mark_recording_result, free_order) take a final p_caller_auth_user_id
--     (the auth.users id the same request's context proof returned as
--     caller_auth_user_id), checked early and again at the final point:
--     NULL -> invalid_request; no / a deleted / a currently banned auth user
--     -> invalid_session; the mapped app user holding an ACTIVE support
--     session -> permission_denied. A refusal answers exactly {ok, error,
--     server_ts} and writes nothing. The binding confers no membership, never
--     rescues a failed proof and is never read from the JWT or a GUC.
--     card_attempt_finish keeps its rules (the provider-fact exception).
--     Every service-only call below is made as service_role through the
--     public wrappers.
-- ===========================================================================
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_set;
-- Bindings: no auth user (ci-c2-unknown-auth is never inserted), a deleted one, a currently banned one and one whose
-- ban lapsed (none has an app user); the org owner (staff 9) linked to an auth user; an app user with no membership
-- and no grant; one admin per operation whose support session is still pending (exchanged after its context proof)
-- and the original caller of the provider-fact exception (pending at claim time, exchanged before the finishes).
insert into auth.users (id, email, deleted_at, banned_until) values
  (pg_temp.zc_id('ci-c2-deleted-auth'), 'zc001d-ci-c2-deleted@example.test', now() - interval '1 day', null),
  (pg_temp.zc_id('ci-c2-banned-auth'), 'zc001d-ci-c2-banned@example.test', null, now() + interval '1 day'),
  (pg_temp.zc_id('ci-c2-bannedpast-auth'), 'zc001d-ci-c2-bannedpast@example.test', null, now() - interval '1 day'),
  (pg_temp.zc_id('ci-c2-owner-auth'), 'zc001d-ci-c2-owner@example.test', null, null);
update public.app_users set auth_user_id = pg_temp.zc_id('ci-c2-owner-auth') where id = pg_temp.zc_id('user-9');
insert into _ci_lbl
select pg_temp.zc_id(l), l from unnest(array['ci-c2-unknown-auth', 'ci-c2-deleted-auth', 'ci-c2-banned-auth',
    'ci-c2-bannedpast-auth', 'ci-c2-owner-auth', 'user-9', 'employee-4', 'employee-9']) l
union all select pg_temp.zc_rest(), 'pilot-restaurant'
union all select pg_temp.zc_branch(), 'pilot-branch'
on conflict (id) do nothing;
select pg_temp.ci_sup_admin('c2-nomember', null) as no_membership_user,
       pg_temp.ci_sup_admin('c2act-claim', 'active', 'pending', pg_temp.zc_org(), false) as act_claim,
       pg_temp.ci_sup_admin('c2act-read', 'active', 'pending', pg_temp.zc_org(), false) as act_read,
       pg_temp.ci_sup_admin('c2act-rel', 'active', 'pending', pg_temp.zc_org(), false) as act_rel,
       pg_temp.ci_sup_admin('c2act-rec', 'active', 'pending', pg_temp.zc_org(), false) as act_rec,
       pg_temp.ci_sup_admin('c2act-free', 'active', 'pending', pg_temp.zc_org(), false) as act_free,
       pg_temp.ci_sup_admin('c2fin', 'active', 'pending', pg_temp.zc_org(), false) as finish_caller;

-- Target sets (d1, LIVE, every setup claim made with the transport binding): per set s an order ci-c2-<s>-cl for a
-- claim and four claimed attempts, each on its own order — rd and rl sent, rc approved with its own canonical
-- recording leg rejected permission_denied, fr unknown and looked up. Set t is the target of every refusal below
-- (and acts last, with the transport binding); every other set is acted on once, by one admitted binding.
create temp table _ci_c2_sets (s text primary key);
insert into _ci_c2_sets values ('t'), ('bannedpast'), ('expired'), ('ended'), ('pending'), ('unconsumed'),
  ('spoofjwt'), ('spoofguc'), ('grant'), ('nomember');
grant select on _ci_c2_sets to service_role;
select count(pg_temp.zc_order('ci-c2-' || s.s || '-' || k, 1234)) as c2_orders
  from _ci_c2_sets s cross join unnest(array['cl', 'rd', 'rl', 'rc', 'fr']) k;
select pg_temp.zc_order('ci-c2-f1', 1234) is not null as f1, pg_temp.zc_order('ci-c2-f2', 1234) is not null as f2,
       pg_temp.zc_order('ci-c2-f3', 1234) is not null as f3;
set local role service_role;
insert into _zc_r
select 'c2_' || s.s || '_' || k, pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c2-' || s.s || '-' || k), 'live',
         p_order => pg_temp.zc_id('order-ci-c2-' || s.s || '-' || k), p_rev => 1)
  from _ci_c2_sets s cross join unnest(array['rd', 'rl', 'rc', 'fr']) k;
-- The provider-fact exception: F1 and F3 claimed by cashier staff 1 with the binding of the admin c2fin (its
-- support session still pending, so admitted), F2 with the transport binding.
insert into _zc_r values
  ('c2_f1', public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1',
     pg_temp.zc_lop('ci-c2-f1'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-c2-f1'), 1, 'production',
     pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1',
     pg_temp.zc_id('ci-sup-c2fin-auth'))),
  ('c2_f3', public.card_attempt_claim(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1',
     pg_temp.zc_lop('ci-c2-f3'), 'live', 1234, 'ILS', pg_temp.zc_id('order-ci-c2-f3'), 1, 'production',
     pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), 'alpha16-l32-v1',
     pg_temp.zc_id('ci-sup-c2fin-auth'))),
  ('c2_f2', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c2-f2'), 'live', p_order => pg_temp.zc_id('order-ci-c2-f2'),
                             p_rev => 1));
insert into _zc_r
select 'c2_' || s.s || '_rc_fin', pg_temp.zc_finish(pg_temp.ci_r('c2_' || s.s || '_rc'), 'commit', 'approved',
         pg_temp.zc_approved_fields())
  from _ci_c2_sets s
union all
select 'c2_' || s.s || '_fr_fin', pg_temp.zc_finish(pg_temp.ci_r('c2_' || s.s || '_fr'), 'commit', 'unknown')
  from _ci_c2_sets s
union all
select 'c2_f3_anomaly', pg_temp.zc_finish(pg_temp.ci_r('c2_f3'), 'commit', 'anomaly',
         '{"anomaly_code": "voided"}'::jsonb);
insert into _zc_r
select 'c2_' || s.s || '_fr_look', pg_temp.zc_finish(pg_temp.ci_r('c2_' || s.s || '_fr'), 'lookup', 'pending',
         '{}'::jsonb, 'operator')
  from _ci_c2_sets s;
reset role;
select count(pg_temp.ci_ok(r)) as c2_setup_calls_ok from _zc_r where label ~ '^c2_';
select pg_temp.ci_ok(app.card_attempt_resolve_orphan((pg_temp.ci_r('c2_f3') ->> 'attempt_row_id')::uuid,
  'provider_voided', 'zc-res/ref-c2', 'ZC001D synthetic orphan resolution', 'zc001d-op/ref-c2',
  pg_temp.zc_owner())) ->> 'resolution' as f3_resolved;
select count(pg_temp.ci_leg(pg_temp.zc_lop('ci-c2-' || s.s || '-rc'), 'rejected', 'permission_denied')) as c2_legs
  from _ci_c2_sets s;
insert into _ci_lbl
select a.id, 'att-' || x.label
  from (select 'ci-c2-' || s.s || '-' || k as label from _ci_c2_sets s cross join unnest(array['rd', 'rl', 'rc', 'fr']) k
        union all select unnest(array['ci-c2-f1', 'ci-c2-f2', 'ci-c2-f3'])) x
  join app.card_provider_attempts a on a.device_id = pg_temp.zc_id('device-1')
                                   and a.local_operation_id = pg_temp.zc_lop(x.label)
on conflict (id) do nothing;

-- C2 helpers. One service-only operation on set p_set as the adapter calls it — cashier staff 1 for the claim, the
-- read and the two marks, manager staff 2 for free_order, d1 and d1's token — with the explicit binding p_binding.
create function pg_temp.ci_c2_op(p_op text, p_set text, p_binding uuid, p_pin uuid default null,
    p_token text default 'zc-token-1', p_lop text default null, p_version text default 'alpha16-l32-v1')
returns jsonb language sql volatile as $$
  select case p_op
    when 'claim' then public.card_attempt_claim(coalesce(p_pin, pg_temp.zc_id('pin-1')), pg_temp.zc_id('device-1'),
      p_token, coalesce(p_lop, pg_temp.zc_lop('ci-c2-' || p_set || '-cl')), 'live', 1234, 'ILS',
      pg_temp.zc_id('order-ci-c2-' || p_set || '-cl'), 1, 'production', pg_temp.zc_terminals(1, 'live'),
      pg_temp.zc_credentials(1, 'live'), p_version, p_binding)
    when 'adapter_read' then public.card_attempt_adapter_read(coalesce(p_pin, pg_temp.zc_id('pin-1')),
      pg_temp.zc_id('device-1'), p_token, coalesce(p_lop, pg_temp.zc_lop('ci-c2-' || p_set || '-rd')), 'production',
      pg_temp.zc_terminals(1, 'live'), pg_temp.zc_credentials(1, 'live'), p_binding)
    when 'mark_release_requested' then public.card_attempt_mark_release_requested(
      coalesce(p_pin, pg_temp.zc_id('pin-1')), pg_temp.zc_id('device-1'), p_token,
      coalesce(p_lop, pg_temp.zc_lop('ci-c2-' || p_set || '-rl')), p_binding)
    when 'mark_recording_result' then public.card_attempt_mark_recording_result(
      coalesce(p_pin, pg_temp.zc_id('pin-1')), pg_temp.zc_id('device-1'), p_token,
      coalesce(p_lop, pg_temp.zc_lop('ci-c2-' || p_set || '-rc')), 'permission_denied', p_binding)
    when 'free_order' then public.card_attempt_free_order(coalesce(p_pin, pg_temp.zc_id('pin-2')),
      pg_temp.zc_id('device-1'), p_token, coalesce(p_lop, pg_temp.zc_lop('ci-c2-' || p_set || '-fr')),
      'ZC001D synthetic manager free', 'provider_report', 'zc-report-c2', p_binding)
  end $$;
-- The five operations on set p_set with one binding (p_pin replaces the cashier PIN, p_free_pin the manager PIN).
create function pg_temp.ci_c2_five(p_set text, p_binding uuid, p_pin uuid default null, p_free_pin uuid default null,
    p_token text default 'zc-token-1', p_lop text default null) returns jsonb language sql volatile as $$
  select jsonb_build_object(
    'claim', pg_temp.ci_c2_op('claim', p_set, p_binding, p_pin, p_token, p_lop),
    'adapter_read', pg_temp.ci_c2_op('adapter_read', p_set, p_binding, p_pin, p_token, p_lop),
    'mark_release_requested', pg_temp.ci_c2_op('mark_release_requested', p_set, p_binding, p_pin, p_token, p_lop),
    'mark_recording_result', pg_temp.ci_c2_op('mark_recording_result', p_set, p_binding, p_pin, p_token, p_lop),
    'free_order', pg_temp.ci_c2_op('free_order', p_set, p_binding, coalesce(p_free_pin, p_pin), p_token, p_lop)) $$;
-- An answer's shape (ok, error and its exact key set — a refusal carries no attempt fact), per operation, per case.
create function pg_temp.ci_c2_ans(p jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', p -> 'ok', 'error', p -> 'error',
    'keys', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from jsonb_object_keys(p) k)) $$;
create function pg_temp.ci_c2_proj(p jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(e.key, pg_temp.ci_c2_ans(e.value)), '{}'::jsonb) from jsonb_each(p) e $$;
create function pg_temp.ci_c2_projn(p jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(e.key, pg_temp.ci_c2_proj(e.value)), '{}'::jsonb) from jsonb_each(p) e $$;
create function pg_temp.ci_c2_refused(p_error text, p_ops text[] default array['claim', 'adapter_read',
    'mark_release_requested', 'mark_recording_result', 'free_order']) returns jsonb language sql immutable as $$
  select jsonb_object_agg(k, jsonb_build_object('ok', false, 'error', p_error,
    'keys', '["error", "ok", "server_ts"]'::jsonb)) from unnest(p_ops) k $$;
-- "Writes nothing": a digest of every row a refusal could touch — the ledger (each row's full content), private
-- events and tenant audit of both fixture organizations, the platform-admin audit naming them or any labelled
-- identity, orders, payments and sync rows of both organizations, the labelled identities' support sessions and
-- d1's device session / device rows — taken after arming d1 (ci_sup_arm) and compared as booleans afterwards.
create function pg_temp.ci_c2_snap() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'ledger', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), ''))
                 from app.card_provider_attempts a where a.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'private_events', (select md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), ''))
                         from app.card_provider_private_events e
                        where e.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'audit_events', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.id), ''))
                       from public.audit_events x where x.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'platform_admin_audit', (select md5(coalesce(string_agg(to_jsonb(x)::text, '|' order by x.id), ''))
                               from public.platform_admin_audit_events x
                              where x.target_organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))
                                 or x.actor_app_user_id in (select l.id from _ci_lbl l)),
    'orders', (select md5(coalesce(string_agg(to_jsonb(o)::text, '|' order by o.id), ''))
                 from public.orders o where o.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'payments', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.id), ''))
                   from public.payments p where p.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'sync_operations', (select md5(coalesce(string_agg(to_jsonb(so)::text, '|' order by so.id), ''))
                          from public.sync_operations so
                         where so.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))),
    'support_sessions', (select md5(coalesce(string_agg(to_jsonb(s)::text, '|' order by s.id), ''))
                           from public.platform_support_sessions s
                          where s.platform_admin_app_user_id in (select l.id from _ci_lbl l)),
    'd1_device_session', (select md5(to_jsonb(ds)::text) from public.device_sessions ds
                           where ds.id = pg_temp.zc_id('dsession-1')),
    'd1_device', (select md5(to_jsonb(d)::text) from public.devices d where d.id = pg_temp.zc_id('device-1'))) $$;
create function pg_temp.ci_c2_begin(p_label text) returns boolean language plpgsql volatile as $$
begin
  perform pg_temp.ci_sup_arm();
  perform pg_temp.ci_mark();
  insert into _zc_r values (p_label, pg_temp.ci_c2_snap()) on conflict (label) do update set r = excluded.r;
  return true;
end $$;
create function pg_temp.ci_c2_effect(p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'unchanged', (select jsonb_object_agg(s.key, s.value = (pg_temp.ci_r(p_label) -> s.key))
                    from jsonb_each(pg_temp.ci_c2_snap()) s),
    'written', pg_temp.ci_new(), 'd1_device', pg_temp.ci_sup_devstate()) $$;
create function pg_temp.ci_c2_none() returns jsonb language sql immutable as $$
  select jsonb_build_object('unchanged', jsonb_build_object('ledger', true, 'private_events', true, 'audit_events', true,
      'platform_admin_audit', true, 'orders', true, 'payments', true, 'sync_operations', true, 'support_sessions', true,
      'd1_device_session', true, 'd1_device', true),
    'written', pg_temp.ci_none(), 'd1_device', pg_temp.ci_sup_armed()) $$;
-- Tenant audit / private events written since the last mark, as labels (no raw ids), sorted by content.
create function pg_temp.ci_c2_audit() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(p order by p::text), '[]'::jsonb)
    from (select jsonb_build_object('action', x.action, 'org', pg_temp.ci_lbl(x.organization_id),
            'restaurant', pg_temp.ci_lbl(x.restaurant_id), 'branch', pg_temp.ci_lbl(x.branch_id),
            'actor_app_user', pg_temp.ci_lbl(x.actor_app_user_id), 'employee', pg_temp.ci_lbl(x.actor_employee_profile_id),
            'device', pg_temp.ci_lbl(x.device_id), 'reason', x.reason, 'old_values', x.old_values,
            'new_values', x.new_values) as p
            from pg_temp.ci_new_audit() x) y $$;
create function pg_temp.ci_c2_audit_row(p_action text, p_emp text, p_values jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('action', p_action, 'org', 'pilot-org', 'restaurant', 'pilot-restaurant',
    'branch', 'pilot-branch', 'actor_app_user', null, 'employee', p_emp, 'device', 'device-1', 'reason', null,
    'old_values', null, 'new_values', p_values) $$;
create function pg_temp.ci_c2_sorted(p jsonb) returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(x order by x::text), '[]'::jsonb) from jsonb_array_elements(p) x $$;
create function pg_temp.ci_c2_events() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(p order by p::text), '[]'::jsonb)
    from (select jsonb_build_object('action', e.action, 'attempt', pg_temp.ci_lbl(e.attempt_row_id),
            'org', pg_temp.ci_lbl(e.organization_id), 'device', pg_temp.ci_lbl(e.device_id), 'mode', e.mode,
            'actor_kind', e.actor_kind, 'actor_reference', e.actor_reference,
            'employee', pg_temp.ci_lbl(e.actor_employee_profile_id), 'reason', e.reason, 'detail', e.detail,
            'retention', case when e.retention_until is null then 'none' else 'set' end) as p
            from pg_temp.ci_new_events() e) y $$;
-- An admitted call of the five on a fresh set: the claim created (its row), the read answers the sent attempt, the
-- release mark stamps, the recording mark stores refusal_code permission_denied, free_order frees (manager).
create function pg_temp.ci_c2_acted(p_set text, p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'claim', jsonb_build_object('ok', r -> 'claim' -> 'ok', 'claim_created', r -> 'claim' -> 'claim_created',
      'state', r -> 'claim' -> 'state', 'mode', r -> 'claim' -> 'mode',
      'row', coalesce((r -> 'claim' ->> 'attempt_row_id')::uuid
                      = (pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-' || p_set || '-cl'))).id, false)),
    'adapter_read', jsonb_build_object('ok', r -> 'adapter_read' -> 'ok', 'state', r -> 'adapter_read' -> 'state',
      'row', coalesce((r -> 'adapter_read' ->> 'attempt_row_id')::uuid
                      = (pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-' || p_set || '-rd'))).id, false)),
    'mark_release_requested', jsonb_build_object('ok', r -> 'mark_release_requested' -> 'ok',
      'state', r -> 'mark_release_requested' -> 'state',
      'classification', r -> 'mark_release_requested' -> 'classification',
      'stamped', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-' || p_set || '-rl'))).release_requested_at is not null),
    'mark_recording_result', jsonb_build_object('ok', r -> 'mark_recording_result' -> 'ok',
      'state', r -> 'mark_recording_result' -> 'state',
      'classification', r -> 'mark_recording_result' -> 'classification',
      'refusal_code', r -> 'mark_recording_result' -> 'refusal_code',
      'stored', to_jsonb((pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-' || p_set || '-rc'))).refusal_code)),
    'free_order', jsonb_build_object('ok', r -> 'free_order' -> 'ok', 'state', r -> 'free_order' -> 'state',
      'classification', r -> 'free_order' -> 'classification',
      'freed', to_jsonb((pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-' || p_set || '-fr'))).order_freed_reason)))
  from (select pg_temp.ci_r(p_label) as r) x $$;
create function pg_temp.ci_c2_acted_outcome(p_set text, p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('acted', pg_temp.ci_c2_acted(p_set, p_label), 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_c2_audit()) $$;
create function pg_temp.ci_c2_acted_expect() returns jsonb language sql immutable as $$
  select jsonb_build_object('acted', '{
      "claim": {"ok": true, "claim_created": true, "state": "sent", "mode": "live", "row": true},
      "adapter_read": {"ok": true, "state": "sent", "row": true},
      "mark_release_requested": {"ok": true, "state": "sent", "classification": "in_progress", "stamped": true},
      "mark_recording_result": {"ok": true, "state": "approved", "classification": "approved_unrecorded",
                                "refusal_code": "permission_denied", "stored": "permission_denied"},
      "free_order": {"ok": true, "state": "unknown", "classification": "freed", "freed": "manager_confirmed"}}'::jsonb,
    'written', '{"ledger": 1, "events": 0, "audit": 4}'::jsonb,
    'audit', pg_temp.ci_c2_sorted(jsonb_build_array(
      pg_temp.ci_c2_audit_row('card_attempt.order_freed', 'employee-2',
        '{"attempt_state": "unknown", "confirmation_source": "provider_report"}'),
      pg_temp.ci_c2_audit_row('card_attempt.recording_refused', 'employee-1', '{"refusal_code": "permission_denied"}'),
      pg_temp.ci_c2_audit_row('card_attempt.release_requested', 'employee-1', '{"attempt_state": "sent"}'),
      pg_temp.ci_c2_audit_row('card_attempt.started', 'employee-1',
        '{"attempt_state": "sent", "mode": "live", "amount_minor": 1234, "currency_code": "ILS"}')))) $$;
-- A set's rows (its attempts, orders and recording leg; every column).
create function pg_temp.ci_c2_set_rows(p_set text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'attempts', (select jsonb_object_agg(k, pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-c2-' || p_set || '-' || k)))
                   from unnest(array['cl', 'rd', 'rl', 'rc', 'fr']) k),
    'orders', (select jsonb_object_agg(k, (select to_jsonb(o) from public.orders o
                                             where o.id = pg_temp.zc_id('order-ci-c2-' || p_set || '-' || k)))
                 from unnest(array['cl', 'rd', 'rl', 'rc', 'fr']) k),
    'leg', (select to_jsonb(so) from public.sync_operations so
             where so.device_id = pg_temp.zc_id('device-1')
               and so.local_operation_id = pg_temp.zc_lop('ci-c2-' || p_set || '-rc'))) $$;
-- Who a binding names (no JWT is consulted for the auth row; the support resolution is the canonical
-- app.current_support_session() under that subject, restored afterwards).
create function pg_temp.ci_c2_who(p_auth text) returns jsonb language sql volatile as $$
  select pg_temp.ci_sup_resolve(p_auth) || jsonb_build_object(
    'auth_row', case when u.id is null then 'none' when u.deleted_at is not null then 'deleted'
                     when u.banned_until > now() then 'banned' when u.banned_until is not null then 'ban_lapsed'
                     else 'live' end,
    'pilot_memberships', (select count(*) from public.memberships m join public.app_users au on au.id = m.app_user_id
                           where au.auth_user_id = pg_temp.zc_id(p_auth) and m.organization_id = pg_temp.zc_org()
                             and m.status = 'active' and m.deleted_at is null))
  from (select 1) one left join auth.users u on u.id = pg_temp.zc_id(p_auth) $$;
create function pg_temp.ci_c2_activate(p_key text) returns boolean language sql volatile as $$
  update public.platform_support_sessions set status = 'active', token_consumed_at = now()
   where id = pg_temp.zc_id('ci-sup-' || p_key || '-session') and status = 'pending'
  returning true $$;
-- A context answer as labels: ok, error, the binding it carries (caller_auth_user_id), role and its exact key set.
create function pg_temp.ci_c2_ctxp(p jsonb) returns jsonb language sql stable as $$
  select jsonb_build_object('ok', p -> 'ok', 'error', p -> 'error',
    'caller', pg_temp.ci_lbl((p ->> 'caller_auth_user_id')::uuid), 'role', p -> 'role',
    'keys', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb) from jsonb_object_keys(p) k)) $$;
insert into _zc_r values ('c2_t_rows_setup', pg_temp.ci_c2_set_rows('t'));

select is((select jsonb_object_agg(a, pg_temp.ci_c2_who(a)) from unnest(array['transport-principal',
      'ci-c2-unknown-auth', 'ci-c2-deleted-auth', 'ci-c2-banned-auth', 'ci-c2-bannedpast-auth',
      'ci-sup-c2-nomember-auth', 'ci-c2-owner-auth', 'ci-sup-grant-auth', 'ci-support-auth', 'ci-sup-other-auth',
      'ci-sup-revoked-grant-auth', 'ci-dual-auth', 'ci-sup-expired-auth', 'ci-sup-ended-auth', 'ci-sup-pending-auth',
      'ci-sup-unconsumed-auth', 'ci-sup-c2act-claim-auth', 'ci-sup-c2act-read-auth', 'ci-sup-c2act-rel-auth',
      'ci-sup-c2act-rec-auth', 'ci-sup-c2act-free-auth', 'ci-sup-c2fin-auth']) a),
  (select jsonb_object_agg(v.a, jsonb_build_object('app_user', v.app_user, 'support_session', v.support_session,
       'platform_admin', v.platform_admin, 'auth_row', v.auth_row, 'pilot_memberships', v.pm))
     from (values
       ('transport-principal', null, null, false, 'live', 0),
       ('ci-c2-unknown-auth', null, null, false, 'none', 0),
       ('ci-c2-deleted-auth', null, null, false, 'deleted', 0),
       ('ci-c2-banned-auth', null, null, false, 'banned', 0),
       ('ci-c2-bannedpast-auth', null, null, false, 'ban_lapsed', 0),
       ('ci-sup-c2-nomember-auth', 'ci-sup-c2-nomember-user', null, false, 'live', 0),
       ('ci-c2-owner-auth', 'user-9', null, false, 'live', 1),
       ('ci-sup-grant-auth', 'ci-sup-grant-user', null, true, 'live', 0),
       ('ci-support-auth', 'ci-support-user', 'ci-support-session', true, 'live', 0),
       ('ci-sup-other-auth', 'ci-sup-other-user', 'ci-sup-other-session', true, 'live', 0),
       ('ci-sup-revoked-grant-auth', 'ci-sup-revoked-grant-user', 'ci-sup-revoked-grant-session', false, 'live', 0),
       ('ci-dual-auth', 'user-2', null, true, 'live', 1),
       ('ci-sup-expired-auth', 'ci-sup-expired-user', null, true, 'live', 0),
       ('ci-sup-ended-auth', 'ci-sup-ended-user', null, true, 'live', 0),
       ('ci-sup-pending-auth', 'ci-sup-pending-user', null, true, 'live', 0),
       ('ci-sup-unconsumed-auth', 'ci-sup-unconsumed-user', null, true, 'live', 0),
       ('ci-sup-c2act-claim-auth', 'ci-sup-c2act-claim-user', null, true, 'live', 0),
       ('ci-sup-c2act-read-auth', 'ci-sup-c2act-read-user', null, true, 'live', 0),
       ('ci-sup-c2act-rel-auth', 'ci-sup-c2act-rel-user', null, true, 'live', 0),
       ('ci-sup-c2act-rec-auth', 'ci-sup-c2act-rec-user', null, true, 'live', 0),
       ('ci-sup-c2act-free-auth', 'ci-sup-c2act-free-user', null, true, 'live', 0),
       ('ci-sup-c2fin-auth', 'ci-sup-c2fin-user', null, true, 'live', 0)) v(a, app_user, support_session, platform_admin, auth_row, pm)),
  'CI-360 C2 setup: each binding used below names what it should — the transport principal (auth row, no app user), no auth row, a deleted one, a currently banned one, one whose ban lapsed (no app user each); an app user with no membership or grant; the org owner (staff 9, one pilot membership); the grant-only admin; three admins whose support session is ACTIVE (pilot, organization B, revoked grant); staff 2 as a dual-role admin (no active session yet); the expired / ended / pending / unconsumed admins and the six pending-session admins of the activation and finish cases resolve no active session');
select is((select jsonb_object_agg(s.s || ':' || k, case when k = 'cl' then
      (select count(*) from app.card_provider_attempts a
        where a.organization_id = pg_temp.zc_org() and a.order_id = pg_temp.zc_id('order-ci-c2-' || s.s || '-cl'))::text
      || ' attempts, order ' || (select o.status || ' rev ' || o.revision from public.orders o
                                  where o.id = pg_temp.zc_id('order-ci-c2-' || s.s || '-cl'))
    else (select a.mode || ' ' || a.state || case when a.last_lookup_at is not null then ' looked_up' else '' end
      || coalesce(' leg ' || (select so.status || ':' || so.rejection_reason from public.sync_operations so
                               where so.organization_id = a.organization_id and so.device_id = a.device_id
                                 and so.local_operation_id = a.local_operation_id), '')
      || case when a.resolution is null and a.order_freed_at is null and a.refusal_code is null
                   and a.release_requested_at is null and not a.charge_may_exist then '' else ' NOT FRESH' end
      from app.card_provider_attempts a
     where a.device_id = pg_temp.zc_id('device-1') and a.local_operation_id = pg_temp.zc_lop('ci-c2-' || s.s || '-' || k))
    end) from _ci_c2_sets s cross join unnest(array['cl', 'rd', 'rl', 'rc', 'fr']) k),
  (select jsonb_object_agg(s.s || ':' || k, case k when 'cl' then '0 attempts, order submitted rev 1'
      when 'rd' then 'live sent' when 'rl' then 'live sent' when 'rc' then 'live approved leg rejected:permission_denied'
      when 'fr' then 'live unknown looked_up' end)
     from _ci_c2_sets s cross join unnest(array['cl', 'rd', 'rl', 'rc', 'fr']) k),
  'CI-361 C2 setup: ten fresh target sets on d1 (LIVE) — per set an unclaimed submitted order for the claim, two sent attempts (read, release mark), an approved attempt whose own canonical leg was rejected permission_denied (recording mark) and an unknown looked-up attempt (free_order); none resolved, freed, refused or release-marked');

-- (h) The context answer carries the binding: caller_auth_user_id = auth.uid() on ok, none on a refusal.
select pg_temp.ci_mark();
insert into _zc_r values ('c2_h_jwt_transport', to_jsonb(pg_temp.ci_lbl(auth.uid())));
set local role authenticated;
insert into _zc_r values ('c2_h_transport', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-c2-t-cl')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-grant-auth')::text, true) is not null as jwt_set;
insert into _zc_r values ('c2_h_jwt_grant', to_jsonb(pg_temp.ci_lbl(auth.uid())));
set local role authenticated;
insert into _zc_r values ('c2_h_grant', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-c2-t-rd')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-dual-auth')::text, true) is not null as jwt_set;
insert into _zc_r values ('c2_h_jwt_dual', to_jsonb(pg_temp.ci_lbl(auth.uid())));
set local role authenticated;
insert into _zc_r values ('c2_h_dual', pg_temp.ci_ctx(2, p_attempt => pg_temp.zc_lop('ci-c2-t-fr')));
reset role;
-- The verified subject carried only in request.jwt.claims (claim.sub empty): auth.uid() reads it from there.
select set_config('request.jwt.claim.sub', '', true) as sub_cleared,
       set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.zc_id('ci-sup-grant-auth'),
                  'role', 'authenticated')::text, true) is not null as claims_set;
insert into _zc_r values ('c2_h_jwt_claims', to_jsonb(pg_temp.ci_lbl(auth.uid())));
set local role authenticated;
insert into _zc_r values ('c2_h_claims', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-c2-t-cl')));
reset role;
select set_config('request.jwt.claims', '', true) as claims_cleared;
set local role authenticated;
insert into _zc_r values ('c2_h_no_jwt', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-c2-t-cl')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-support-auth')::text, true) is not null as jwt_set;
set local role authenticated;
insert into _zc_r values ('c2_h_support', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-c2-t-cl')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_set;
set local role authenticated;
insert into _zc_r values
  ('c2_h_forged', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-c2-t-cl'), p_token => 'zc-token-forged')),
  ('c2_h_bad_id', pg_temp.ci_ctx(1, p_attempt => 'not-a-uuid')),
  ('c2_h_kitchen', pg_temp.ci_ctx(4, pg_temp.zc_id('order-ci-c2-t-cl')));
reset role;
select is((select jsonb_object_agg(c, jsonb_build_object('jwt_sub', pg_temp.ci_r('c2_h_jwt_' || c),
      'answer', pg_temp.ci_c2_ctxp(pg_temp.ci_r('c2_h_' || c)))) from unnest(array['transport', 'grant', 'dual', 'claims']) c),
  (select jsonb_object_agg(v.c, jsonb_build_object('jwt_sub', v.j, 'answer', jsonb_build_object('ok', true,
      'error', null, 'caller', v.j, 'role', v.r, 'keys', '["attempt", "branch_id", "caller_auth_user_id",
      "card_terminal_enabled", "device_id", "employee_profile_id", "membership_id", "ok", "order", "organization_id",
      "restaurant_id", "role", "server_ts", "terminal"]'::jsonb)))
     from (values ('transport', 'transport-principal', 'cashier'), ('grant', 'ci-sup-grant-auth', 'cashier'),
                  ('dual', 'ci-dual-auth', 'manager'), ('claims', 'ci-sup-grant-auth', 'cashier')) v(c, j, r)),
  'CI-362 C2 context binding: an ok card_attempt_context answer carries caller_auth_user_id = auth.uid(), the verified JWT subject — the transport principal (cashier staff 1, the order of set t), the grant-only admin (cashier staff 1, an attempt), the dual-role person on its own manager PIN (staff 2) and the grant-only admin presented only through request.jwt.claims (claim.sub empty) — with exactly the 14 answer keys');
select is(jsonb_build_object('answers', (select jsonb_object_agg(c, pg_temp.ci_c2_ctxp(pg_temp.ci_r('c2_h_' || c)))
      from unnest(array['no_jwt', 'support', 'forged', 'bad_id', 'kitchen']) c), 'written', pg_temp.ci_new()),
  jsonb_build_object('answers', (select jsonb_object_agg(v.c, jsonb_build_object('ok', false, 'error', v.e,
      'caller', null, 'role', null, 'keys', '["error", "ok"]'::jsonb))
     from (values ('no_jwt', 'invalid_session'), ('support', 'permission_denied'), ('forged', 'invalid_session'),
                  ('bad_id', 'invalid_request'), ('kitchen', 'permission_denied')) v(c, e)),
    'written', pg_temp.ci_none()),
  'CI-363 C2 context binding: a refused card_attempt_context answer carries no binding — no JWT principal at all (invalid_session), an ACTIVE support session (permission_denied), a forged device token (invalid_session), a malformed attempt id (invalid_request) and a kitchen PIN (permission_denied) answer exactly {ok:false, error} with no caller_auth_user_id; nothing written');

-- (a) The binding's identity: NULL, no / a deleted / a currently banned auth user; a lapsed ban is no refusal.
select pg_temp.ci_c2_begin('c2_snap_a_null');
set local role service_role;
insert into _zc_r values ('c2_a_null', pg_temp.ci_c2_five('t', null));
reset role;
select is(pg_temp.ci_c2_proj(pg_temp.ci_r('c2_a_null')), pg_temp.ci_c2_refused('invalid_request'),
  'CI-364 C2 binding NULL: claim, adapter_read, mark_release_requested, mark_recording_result (cashier staff 1) and free_order (manager staff 2) with valid PINs, d1 and its token on set t''s admissible targets each answer exactly {ok:false, error:invalid_request, server_ts} — no attempt fact');
select is(pg_temp.ci_c2_effect('c2_snap_a_null'), pg_temp.ci_c2_none(),
  'CI-365 C2 binding NULL: those refusals wrote nothing — ledger rows (full-content digest), private events, tenant audit, platform-admin audit, orders, payments, sync rows and support sessions unchanged; no new ledger / event / audit row; d1''s device session and device rows exactly as armed (expires_at, last_seen_at)');
select pg_temp.ci_c2_begin('c2_snap_a_invalid');
set local role service_role;
insert into _zc_r values ('c2_a_invalid', jsonb_build_object(
  'no_auth_user', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-c2-unknown-auth')),
  'deleted_auth_user', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-c2-deleted-auth')),
  'banned_auth_user', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-c2-banned-auth'))));
reset role;
select is(pg_temp.ci_c2_projn(pg_temp.ci_r('c2_a_invalid')), jsonb_build_object(
    'no_auth_user', pg_temp.ci_c2_refused('invalid_session'), 'deleted_auth_user', pg_temp.ci_c2_refused('invalid_session'),
    'banned_auth_user', pg_temp.ci_c2_refused('invalid_session')),
  'CI-366 C2 binding identity: an unknown uuid (no auth.users row), an auth user with deleted_at set and one with banned_until in the future each answer exactly {ok:false, error:invalid_session, server_ts} on all five operations (valid staff PINs, d1 and its token; set t)');
select is(pg_temp.ci_c2_effect('c2_snap_a_invalid'), pg_temp.ci_c2_none(),
  'CI-367 C2 binding identity: those 15 refusals wrote nothing (every digest unchanged, no new row, d1 not renewed)');
select pg_temp.ci_c2_begin('c2_snap_a_bannedpast');
set local role service_role;
insert into _zc_r values ('c2_a_bannedpast', pg_temp.ci_c2_five('bannedpast', pg_temp.zc_id('ci-c2-bannedpast-auth')));
reset role;
select is(pg_temp.ci_c2_acted_outcome('bannedpast', 'c2_a_bannedpast'), pg_temp.ci_c2_acted_expect(),
  'CI-368 C2 binding identity: an auth user whose banned_until is in the past is not refused for it — the five operations act on a fresh set: the claim created (its row), the read answers the sent attempt, the release mark stamps, the recording mark stores refusal_code permission_denied, free_order frees (manager_confirmed); exactly one ledger row and four audit rows (started, release_requested, recording_refused by employee 1, order_freed by employee 2, all on d1)');

-- (b) An ACTIVE support session of the binding's app user refuses, whatever valid PIN / device the request carries.
select pg_temp.ci_sup_session(pg_temp.zc_id('user-2'), 'ci-c2-dual-session', pg_temp.zc_org(), 'active', true,
                              interval '10 minutes') as c2_dual_session_active;
select pg_temp.ci_c2_begin('c2_snap_b_support');
set local role service_role;
insert into _zc_r values ('c2_b_support', jsonb_build_object(
  'pilot_session_cashier_pins', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-support-auth')),
  'pilot_session_manager_pin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-support-auth'), pg_temp.zc_id('pin-2')),
  'org_b_session_cashier_pins', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-other-auth')),
  'org_b_session_manager_pin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-other-auth'), pg_temp.zc_id('pin-2')),
  'revoked_grant_session_cashier_pins', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-revoked-grant-auth')),
  'revoked_grant_session_manager_pin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-revoked-grant-auth'),
                                                          pg_temp.zc_id('pin-2')),
  'dual_role_cashier_pins', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-dual-auth')),
  'dual_role_own_manager_pin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-dual-auth'), pg_temp.zc_id('pin-2'))));
reset role;
select is(jsonb_build_object(
    'support_session', (select jsonb_object_agg(a, pg_temp.ci_sup_resolve(a) -> 'support_session')
                          from unnest(array['ci-support-auth', 'ci-sup-other-auth', 'ci-sup-revoked-grant-auth',
                                            'ci-dual-auth']) a),
    'answers', pg_temp.ci_c2_projn(pg_temp.ci_r('c2_b_support'))),
  jsonb_build_object('support_session', '{"ci-support-auth": "ci-support-session",
      "ci-sup-other-auth": "ci-sup-other-session", "ci-sup-revoked-grant-auth": "ci-sup-revoked-grant-session",
      "ci-dual-auth": "ci-c2-dual-session"}'::jsonb,
    'answers', (select jsonb_object_agg(k, pg_temp.ci_c2_refused('permission_denied')) from unnest(array[
      'pilot_session_cashier_pins', 'pilot_session_manager_pin', 'org_b_session_cashier_pins', 'org_b_session_manager_pin',
      'revoked_grant_session_cashier_pins', 'revoked_grant_session_manager_pin', 'dual_role_cashier_pins',
      'dual_role_own_manager_pin']) k)),
  'CI-369 C2 binding support: the binding of a caller whose app user holds an ACTIVE support session — the pilot admin, an admin whose session targets organization B, an admin whose grant is revoked, and staff 2 as a dual-role admin once its own session is active — answers exactly {ok:false, error:permission_denied, server_ts} on all five operations, with cashier staff 1''s / manager staff 2''s valid PINs and with manager staff 2''s PIN for all five (for the dual role its own PIN), d1 and its token');
select is(pg_temp.ci_c2_effect('c2_snap_b_support'), pg_temp.ci_c2_none(),
  'CI-370 C2 binding support: those 40 refusals wrote nothing (ledger digest, events, audit, platform-admin audit, orders, payments, sync rows, support sessions unchanged; no new row; d1 not renewed)');
select pg_temp.ci_c2_begin('c2_snap_b_order');
set local role service_role;
insert into _zc_r values ('c2_b_order', jsonb_build_object(
  'support_binding_malformed_id', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-support-auth'), p_lop => 'not-a-uuid'),
  'unknown_binding_malformed_id', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-c2-unknown-auth'), p_lop => 'not-a-uuid'),
  'support_binding_forged_token', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-support-auth'), p_token => 'zc-token-forged'),
  'null_binding_forged_token', pg_temp.ci_c2_five('t', null, p_token => 'zc-token-forged'),
  'support_binding_unknown_key_format', jsonb_build_object('claim',
    pg_temp.ci_c2_op('claim', 't', pg_temp.zc_id('ci-support-auth'), p_version => 'alpha16-l99-v1'))));
reset role;
select is(pg_temp.ci_c2_projn(pg_temp.ci_r('c2_b_order')), jsonb_build_object(
    'support_binding_malformed_id', pg_temp.ci_c2_refused('invalid_request'),
    'unknown_binding_malformed_id', pg_temp.ci_c2_refused('invalid_request'),
    'support_binding_forged_token', pg_temp.ci_c2_refused('permission_denied'),
    'null_binding_forged_token', pg_temp.ci_c2_refused('invalid_request'),
    'support_binding_unknown_key_format', pg_temp.ci_c2_refused('permission_denied', array['claim'])),
  'CI-371 C2 binding order (early check): the attempt-id / request-shape check comes first (a malformed attempt id answers invalid_request with a support-active or an unknown binding), the binding next — before the proof (a forged token answers permission_denied with a support-active binding and invalid_request with a NULL binding, never invalid_session) and before the claim''s key-format check (alpha16-l99-v1 answers permission_denied, not provider_unavailable)');
select is(pg_temp.ci_c2_effect('c2_snap_b_order'), pg_temp.ci_c2_none(),
  'CI-372 C2 binding order: those 21 refusals wrote nothing (every digest unchanged, no new row, d1 not renewed)');
select pg_temp.ci_c2_begin('c2_snap_b_kitchen');
set local role service_role;
insert into _zc_r values ('c2_b_kitchen_support', jsonb_build_object(
  'mark_release_requested', pg_temp.ci_c2_op('mark_release_requested', 't', pg_temp.zc_id('ci-support-auth'),
                                             pg_temp.zc_id('pin-4')),
  'mark_recording_result', pg_temp.ci_c2_op('mark_recording_result', 't', pg_temp.zc_id('ci-support-auth'),
                                            pg_temp.zc_id('pin-4'))));
reset role;
insert into _zc_r values ('c2_b_kitchen_support_evidence', jsonb_build_object('written', pg_temp.ci_new(),
  'audit', pg_temp.ci_c2_audit(), 'events', pg_temp.ci_c2_events()));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_b_kitchen_transport', jsonb_build_object(
  'mark_release_requested', pg_temp.ci_c2_op('mark_release_requested', 't', pg_temp.zc_caller(), pg_temp.zc_id('pin-4')),
  'mark_recording_result', pg_temp.ci_c2_op('mark_recording_result', 't', pg_temp.zc_caller(), pg_temp.zc_id('pin-4'))));
reset role;
select is(jsonb_build_object(
    'support_bound', jsonb_build_object('answers', pg_temp.ci_c2_proj(pg_temp.ci_r('c2_b_kitchen_support')),
      'evidence', pg_temp.ci_r('c2_b_kitchen_support_evidence')),
    'transport_bound', jsonb_build_object('answers', pg_temp.ci_c2_proj(pg_temp.ci_r('c2_b_kitchen_transport')),
      'evidence', jsonb_build_object('written', pg_temp.ci_new(), 'audit', pg_temp.ci_c2_audit(),
                                     'events', pg_temp.ci_c2_events()))),
  jsonb_build_object(
    'support_bound', jsonb_build_object(
      'answers', pg_temp.ci_c2_refused('permission_denied', array['mark_release_requested', 'mark_recording_result']),
      'evidence', jsonb_build_object('written', pg_temp.ci_none(), 'audit', '[]'::jsonb, 'events', '[]'::jsonb)),
    'transport_bound', jsonb_build_object(
      'answers', pg_temp.ci_c2_refused('permission_denied', array['mark_release_requested', 'mark_recording_result']),
      'evidence', jsonb_build_object('written', '{"ledger": 0, "events": 0, "audit": 2}'::jsonb,
        'audit', pg_temp.ci_c2_sorted(jsonb_build_array(
          pg_temp.ci_c2_audit_row('card_attempt.denied', 'employee-4', '{"denied_reason": "permission_denied"}'),
          pg_temp.ci_c2_audit_row('card_attempt.denied', 'employee-4', '{"denied_reason": "permission_denied"}'))),
        'events', '[]'::jsonb))),
  'CI-373 C2 binding order (no evidence): a kitchen_staff PIN (staff 4) on d1 through both marks on set t''s LIVE attempts with a support-active binding answers permission_denied and writes NO proof-level denial evidence (the binding refusal precedes the proof), while the same calls with the transport binding answer permission_denied WITH the unchanged evidence — one card_attempt.denied {denied_reason: permission_denied} audit row per mark for employee 4 on d1');
select pg_temp.ci_c2_begin('c2_snap_b_expired');
set local role service_role;
insert into _zc_r values ('c2_b_expired', pg_temp.ci_c2_five('expired', pg_temp.zc_id('ci-sup-expired-auth')));
reset role;
select is(pg_temp.ci_c2_acted_outcome('expired', 'c2_b_expired'), pg_temp.ci_c2_acted_expect(),
  'CI-374 C2 binding support: an EXPIRED session (status active, token consumed, expires_at past) does not refuse — with the expired admin''s binding the normal proof decides and the five operations act on a fresh set (claim created, read, release stamped, refusal stored, order freed; one ledger row, four audit rows)');
select pg_temp.ci_c2_begin('c2_snap_b_ended');
set local role service_role;
insert into _zc_r values ('c2_b_ended', pg_temp.ci_c2_five('ended', pg_temp.zc_id('ci-sup-ended-auth')));
reset role;
select is(pg_temp.ci_c2_acted_outcome('ended', 'c2_b_ended'), pg_temp.ci_c2_acted_expect(),
  'CI-375 C2 binding support: an ENDED session does not refuse — the ended admin''s binding: the five operations act on a fresh set (one ledger row, four audit rows)');
select pg_temp.ci_c2_begin('c2_snap_b_pending');
set local role service_role;
insert into _zc_r values ('c2_b_pending', pg_temp.ci_c2_five('pending', pg_temp.zc_id('ci-sup-pending-auth')));
reset role;
select is(pg_temp.ci_c2_acted_outcome('pending', 'c2_b_pending'), pg_temp.ci_c2_acted_expect(),
  'CI-376 C2 binding support: an UN-EXCHANGED (pending) session does not refuse — the pending admin''s binding: the five operations act on a fresh set (one ledger row, four audit rows)');
select pg_temp.ci_c2_begin('c2_snap_b_unconsumed');
set local role service_role;
insert into _zc_r values ('c2_b_unconsumed', pg_temp.ci_c2_five('unconsumed', pg_temp.zc_id('ci-sup-unconsumed-auth')));
reset role;
select is(pg_temp.ci_c2_acted_outcome('unconsumed', 'c2_b_unconsumed'), pg_temp.ci_c2_acted_expect(),
  'CI-377 C2 binding support: a session with status active whose token was never consumed does not refuse — the five operations act on a fresh set (one ledger row, four audit rows)');
update public.platform_support_sessions set status = 'ended', ended_at = now()
 where id = pg_temp.zc_id('ci-c2-dual-session');

-- (d) Support activated AFTER a successful context proof (same transaction): the service operation is refused.
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-c2act-claim-auth')::text, true) is not null as jwt_set;
set local role authenticated;
insert into _zc_r values ('c2_d_ctx_claim', pg_temp.ci_ctx(1, pg_temp.zc_id('order-ci-c2-t-cl')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-c2act-read-auth')::text, true) is not null as jwt_set;
set local role authenticated;
insert into _zc_r values ('c2_d_ctx_read', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-c2-t-rd')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-c2act-rel-auth')::text, true) is not null as jwt_set;
set local role authenticated;
insert into _zc_r values ('c2_d_ctx_rel', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-c2-t-rl')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-c2act-rec-auth')::text, true) is not null as jwt_set;
set local role authenticated;
insert into _zc_r values ('c2_d_ctx_rec', pg_temp.ci_ctx(1, p_attempt => pg_temp.zc_lop('ci-c2-t-rc')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-c2act-free-auth')::text, true) is not null as jwt_set;
set local role authenticated;
insert into _zc_r values ('c2_d_ctx_free', pg_temp.ci_ctx(2, p_attempt => pg_temp.zc_lop('ci-c2-t-fr')));
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_set;
select is((select jsonb_object_agg(v.op, jsonb_build_object('ok', pg_temp.ci_r('c2_d_ctx_' || v.k) -> 'ok',
      'caller', pg_temp.ci_lbl((pg_temp.ci_r('c2_d_ctx_' || v.k) ->> 'caller_auth_user_id')::uuid),
      'role', pg_temp.ci_r('c2_d_ctx_' || v.k) -> 'role',
      'target', coalesce(pg_temp.ci_r('c2_d_ctx_' || v.k) -> 'attempt' -> 'state',
                         pg_temp.ci_r('c2_d_ctx_' || v.k) -> 'order' -> 'status'),
      'support_session_then', pg_temp.ci_sup_resolve('ci-sup-c2act-' || v.k || '-auth') -> 'support_session'))
     from (values ('claim', 'claim'), ('adapter_read', 'read'), ('mark_release_requested', 'rel'),
                  ('mark_recording_result', 'rec'), ('free_order', 'free')) v(op, k)),
  (select jsonb_object_agg(v.op, jsonb_build_object('ok', true, 'caller', 'ci-sup-c2act-' || v.k || '-auth',
      'role', v.r, 'target', v.t, 'support_session_then', null))
     from (values ('claim', 'claim', 'cashier', 'submitted'), ('adapter_read', 'read', 'cashier', 'sent'),
                  ('mark_release_requested', 'rel', 'cashier', 'sent'), ('mark_recording_result', 'rec', 'cashier', 'approved'),
                  ('free_order', 'free', 'manager', 'unknown')) v(op, k, r, t)),
  'CI-378 C2 activation after the proof: five admins whose support sessions are still pending each pass card_attempt_context under their own JWT for one operation''s target of set t (cashier staff 1 for the order and three attempts, manager staff 2 for the unknown attempt) — ok, caller_auth_user_id = that admin''s auth id, no active session yet');
select count(pg_temp.ci_c2_activate(k)) as c2_sessions_activated
  from unnest(array['c2act-claim', 'c2act-read', 'c2act-rel', 'c2act-rec', 'c2act-free']) k;
select pg_temp.ci_c2_begin('c2_snap_d');
set local role service_role;
insert into _zc_r values ('c2_d_ops', jsonb_build_object(
  'claim', pg_temp.ci_c2_op('claim', 't', (pg_temp.ci_r('c2_d_ctx_claim') ->> 'caller_auth_user_id')::uuid),
  'adapter_read', pg_temp.ci_c2_op('adapter_read', 't', (pg_temp.ci_r('c2_d_ctx_read') ->> 'caller_auth_user_id')::uuid),
  'mark_release_requested', pg_temp.ci_c2_op('mark_release_requested', 't',
    (pg_temp.ci_r('c2_d_ctx_rel') ->> 'caller_auth_user_id')::uuid),
  'mark_recording_result', pg_temp.ci_c2_op('mark_recording_result', 't',
    (pg_temp.ci_r('c2_d_ctx_rec') ->> 'caller_auth_user_id')::uuid),
  'free_order', pg_temp.ci_c2_op('free_order', 't', (pg_temp.ci_r('c2_d_ctx_free') ->> 'caller_auth_user_id')::uuid)));
reset role;
select is(jsonb_build_object(
    'support_session_now', (select jsonb_object_agg(k, pg_temp.ci_sup_resolve('ci-sup-c2act-' || k || '-auth')
                                                       -> 'support_session')
                              from unnest(array['claim', 'read', 'rel', 'rec', 'free']) k),
    'answers', pg_temp.ci_c2_proj(pg_temp.ci_r('c2_d_ops'))),
  jsonb_build_object('support_session_now', (select jsonb_object_agg(k, 'ci-sup-c2act-' || k || '-session')
                                               from unnest(array['claim', 'read', 'rel', 'rec', 'free']) k),
    'answers', pg_temp.ci_c2_refused('permission_denied')),
  'CI-379 C2 activation after the proof: each admin''s session is then exchanged (status active, token consumed) in the same transaction, and the service operation called with the binding its own context proof returned — claim, adapter_read, mark_release_requested, mark_recording_result (cashier staff 1), free_order (manager staff 2), same PINs, d1 and its token — answers exactly {ok:false, error:permission_denied, server_ts}');
select is(pg_temp.ci_c2_effect('c2_snap_d'), pg_temp.ci_c2_none(),
  'CI-380 C2 activation after the proof: those five refusals wrote nothing (every digest unchanged, no new row, d1 not renewed)');

-- (f) A valid binding never rescues a failed proof; it confers no membership.
select pg_temp.ci_c2_begin('c2_snap_f');
set local role service_role;
insert into _zc_r values ('c2_f_faults', jsonb_build_object(
  'unknown_pin_transport', pg_temp.ci_c2_five('t', pg_temp.zc_caller(), pg_temp.zc_id('ci-c2-no-pin'),
                                              pg_temp.zc_id('ci-c2-no-pin')),
  'unknown_pin_grant_admin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-grant-auth'), pg_temp.zc_id('ci-c2-no-pin'),
                                                pg_temp.zc_id('ci-c2-no-pin')),
  'other_device_token_transport', pg_temp.ci_c2_five('t', pg_temp.zc_caller(), p_token => 'zc-token-2'),
  'other_device_token_grant_admin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-grant-auth'), p_token => 'zc-token-2'),
  'foreign_pin_transport', pg_temp.ci_c2_five('t', pg_temp.zc_caller(), pg_temp.zc_id('pin-7'), pg_temp.zc_id('pin-7')),
  'foreign_pin_grant_admin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-grant-auth'), pg_temp.zc_id('pin-7'),
                                                pg_temp.zc_id('pin-7'))));
reset role;
update memberships set status = 'revoked', deleted_at = now()
 where id in (pg_temp.zc_id('membership-1'), pg_temp.zc_id('membership-2'));
set local role service_role;
insert into _zc_r values ('c2_f_revoked', jsonb_build_object(
  'revoked_membership_transport', pg_temp.ci_c2_five('t', pg_temp.zc_caller()),
  'revoked_membership_grant_admin', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-sup-grant-auth'))));
reset role;
update memberships set status = 'active', deleted_at = null
 where id in (pg_temp.zc_id('membership-1'), pg_temp.zc_id('membership-2'));
select is(pg_temp.ci_c2_projn(pg_temp.ci_r('c2_f_faults') || pg_temp.ci_r('c2_f_revoked')),
  (select jsonb_object_agg(k, pg_temp.ci_c2_refused('invalid_session')) from unnest(array['unknown_pin_transport',
     'unknown_pin_grant_admin', 'other_device_token_transport', 'other_device_token_grant_admin', 'foreign_pin_transport',
     'foreign_pin_grant_admin', 'revoked_membership_transport', 'revoked_membership_grant_admin']) k),
  'CI-381 C2 no rescue: a valid binding (the transport principal; the grant-only admin) never rescues a failed proof — an unknown PIN session, d2''s token presented for d1, a foreign-organization PIN (staff 7) and the PIN''s membership revoked (staff 1 and 2) each answer exactly the existing {ok:false, error:invalid_session, server_ts} on all five operations');
select is(pg_temp.ci_c2_effect('c2_snap_f'), pg_temp.ci_c2_none(),
  'CI-382 C2 no rescue: those 40 refusals wrote nothing (every digest unchanged, no new row, d1 not renewed)');
select pg_temp.ci_c2_begin('c2_snap_f_owner');
set local role service_role;
insert into _zc_r values ('c2_f_owner_kitchen', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-c2-owner-auth'),
  pg_temp.zc_id('pin-4'), pg_temp.zc_id('pin-4')));
reset role;
select is(jsonb_build_object('answers', pg_temp.ci_c2_proj(pg_temp.ci_r('c2_f_owner_kitchen')),
    'written', pg_temp.ci_new(), 'audit', pg_temp.ci_c2_audit(),
    'unchanged', (pg_temp.ci_c2_effect('c2_snap_f_owner') -> 'unchanged') - 'audit_events'),
  jsonb_build_object('answers', pg_temp.ci_c2_refused('permission_denied'),
    'written', '{"ledger": 0, "events": 0, "audit": 3}'::jsonb,
    'audit', pg_temp.ci_c2_sorted(jsonb_build_array(
      pg_temp.ci_c2_audit_row('card_attempt.denied', 'employee-4', '{"denied_reason": "permission_denied"}'),
      pg_temp.ci_c2_audit_row('card_attempt.denied', 'employee-4', '{"denied_reason": "permission_denied"}'),
      pg_temp.ci_c2_audit_row('card_attempt.denied', 'employee-4', '{"denied_reason": "permission_denied"}'))),
    'unchanged', (pg_temp.ci_c2_none() -> 'unchanged') - 'audit_events'),
  'CI-383 C2 no membership conferred: the org owner''s own auth id (staff 9, active org_owner membership) as the binding with a kitchen_staff PIN (staff 4) on d1 — the five operations answer exactly the existing permission_denied, with the unchanged proof-level evidence only (one card_attempt.denied audit row each for the claim and the two marks, employee 4, d1) and no other write: the binding confers no authority');

-- (g) JWT / GUC spoofing changes nothing: the explicit binding decides.
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-support-auth')::text, true) is not null as sub_spoofed,
       set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.zc_id('ci-support-auth'),
                  'role', 'authenticated')::text, true) is not null as claims_spoofed,
       set_config('app.current_app_user_id', pg_temp.zc_id('ci-support-user')::text, true) is not null as guc_spoofed;
insert into _zc_r values ('c2_g_jwt_facts', jsonb_build_object('jwt_sub', pg_temp.ci_lbl(auth.uid()),
  'app_user', pg_temp.ci_lbl(app.current_app_user_id()), 'support_session', pg_temp.ci_lbl(app.current_support_session())));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_g_jwt', pg_temp.ci_c2_five('spoofjwt', pg_temp.zc_caller()));
reset role;
select is(jsonb_build_object('facts', pg_temp.ci_r('c2_g_jwt_facts')) || pg_temp.ci_c2_acted_outcome('spoofjwt', 'c2_g_jwt'),
  jsonb_build_object('facts', '{"jwt_sub": "ci-support-auth", "app_user": "ci-support-user",
      "support_session": "ci-support-session"}'::jsonb) || pg_temp.ci_c2_acted_expect(),
  'CI-384 C2 spoofing: as service_role with request.jwt.claim.sub, request.jwt.claims and app.current_app_user_id all naming the support-active admin (auth.uid() and app.current_support_session() resolve its ACTIVE session) and the binding = the transport principal, the five operations act on a fresh set (one ledger row, four audit rows) — the JWT is not read');
select set_config('request.jwt.claim.sub', '', true) is not null as sub_cleared,
       set_config('request.jwt.claims', '', true) is not null as claims_cleared;
insert into _zc_r values ('c2_g_guc_facts', jsonb_build_object('jwt_sub', pg_temp.ci_lbl(auth.uid()),
  'app_user', pg_temp.ci_lbl(app.current_app_user_id()), 'support_session', pg_temp.ci_lbl(app.current_support_session())));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_g_guc', pg_temp.ci_c2_five('spoofguc', pg_temp.zc_caller()));
reset role;
select is(jsonb_build_object('facts', pg_temp.ci_r('c2_g_guc_facts')) || pg_temp.ci_c2_acted_outcome('spoofguc', 'c2_g_guc'),
  jsonb_build_object('facts', '{"jwt_sub": null, "app_user": "ci-support-user",
      "support_session": "ci-support-session"}'::jsonb) || pg_temp.ci_c2_acted_expect(),
  'CI-385 C2 spoofing: with no JWT principal and the interim GUC app.current_app_user_id naming the support-active admin''s app user (app.current_support_session() resolves its ACTIVE session through the GUC path) and the binding = the transport principal, the five operations act on a fresh set — no GUC is read');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as sub_restored,
       set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.zc_id('transport-principal'),
                  'role', 'authenticated')::text, true) is not null as claims_transport,
       set_config('app.current_app_user_id', '', true) is not null as guc_cleared;
insert into _zc_r values ('c2_g_rev_facts', jsonb_build_object('jwt_sub', pg_temp.ci_lbl(auth.uid()),
  'app_user', pg_temp.ci_lbl(app.current_app_user_id()), 'support_session', pg_temp.ci_lbl(app.current_support_session())));
select pg_temp.ci_c2_begin('c2_snap_g_rev');
set local role service_role;
insert into _zc_r values ('c2_g_rev', pg_temp.ci_c2_five('t', pg_temp.zc_id('ci-support-auth')));
reset role;
select set_config('request.jwt.claims', '', true) is not null as claims_cleared_again;
select is(jsonb_build_object('facts', pg_temp.ci_r('c2_g_rev_facts'), 'answers', pg_temp.ci_c2_proj(pg_temp.ci_r('c2_g_rev')),
    'effect', pg_temp.ci_c2_effect('c2_snap_g_rev')),
  jsonb_build_object('facts', '{"jwt_sub": "transport-principal", "app_user": null, "support_session": null}'::jsonb,
    'answers', pg_temp.ci_c2_refused('permission_denied'), 'effect', pg_temp.ci_c2_none()),
  'CI-386 C2 spoofing: the reverse — request.jwt.claim.sub and request.jwt.claims naming the transport principal (no app user, no support session) and the binding = the support-active admin: the five operations answer exactly {ok:false, error:permission_denied, server_ts} and write nothing (every digest unchanged, d1 not renewed)');

-- (e) Positive controls: the transport principal acts on the very targets every refusal above addressed; a binding
-- that differs from the PIN employee (the grant-only admin; an app user with no membership) is admitted.
select pg_temp.ci_c2_begin('c2_snap_e_t');
insert into _zc_r values ('c2_t_rows_before_control', pg_temp.ci_c2_set_rows('t'));
set local role service_role;
insert into _zc_r values ('c2_e_t', pg_temp.ci_c2_five('t', pg_temp.zc_caller()));
reset role;
select is(jsonb_build_object('t_rows_as_set_up', pg_temp.ci_r('c2_t_rows_before_control') = pg_temp.ci_r('c2_t_rows_setup'))
    || pg_temp.ci_c2_acted_outcome('t', 'c2_e_t'),
  jsonb_build_object('t_rows_as_set_up', true) || pg_temp.ci_c2_acted_expect(),
  'CI-387 C2 positive control: set t''s attempts, orders and recording leg are exactly as set up (every column) after every refusal above, and the transport principal''s binding (the native POS caller) with the same PINs, d1 and its token makes the five operations act on them — claim created, read, release stamped, refusal stored, order freed; one ledger row, four audit rows: the refusals were the binding alone');
select pg_temp.ci_c2_begin('c2_snap_e_grant');
set local role service_role;
insert into _zc_r values ('c2_e_grant', pg_temp.ci_c2_five('grant', pg_temp.zc_id('ci-sup-grant-auth')));
reset role;
select is(pg_temp.ci_c2_acted_outcome('grant', 'c2_e_grant'), pg_temp.ci_c2_acted_expect(),
  'CI-388 C2 positive control: the grant-only platform admin outside any support session (no membership, not the PIN employee) as the binding with cashier staff 1''s (manager staff 2''s for free_order) valid PIN — the five operations act on a fresh set (one ledger row, four audit rows)');
select pg_temp.ci_c2_begin('c2_snap_e_nomember');
set local role service_role;
insert into _zc_r values ('c2_e_nomember', pg_temp.ci_c2_five('nomember', pg_temp.zc_id('ci-sup-c2-nomember-auth')));
reset role;
select is(pg_temp.ci_c2_acted_outcome('nomember', 'c2_e_nomember'), pg_temp.ci_c2_acted_expect(),
  'CI-389 C2 positive control: an app user with no membership and no grant as the binding with cashier staff 1''s (manager staff 2''s for free_order) valid PIN — the five operations act on a fresh set: the binding need not equal the PIN employee and confers nothing, the PIN proof decides');

-- (i) The provider-fact exception: card_attempt_finish keeps its scope-bound rules after the original caller's
-- support session became ACTIVE and after the initiating PIN session expired.
select is(jsonb_build_object(
    'f1', (select a.mode || ' ' || a.state from pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-f1')) a),
    'f2', (select a.mode || ' ' || a.state from pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-f2')) a),
    'f3', (select a.mode || ' ' || a.state || ' ' || a.resolution from pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-f3')) a),
    'finish_caller', pg_temp.ci_sup_resolve('ci-sup-c2fin-auth') -> 'support_session'),
  '{"f1": "live sent", "f2": "live sent", "f3": "live unknown provider_voided", "finish_caller": null}'::jsonb,
  'CI-390 C2 provider fact setup: F1 and F3 were claimed by cashier staff 1 with the binding of the admin c2fin while its session was pending (admitted); F1 is sent, F3 unknown and resolved provider_voided (anomaly, orphan resolution); F2 (transport binding) is sent; c2fin has no active session yet');
select pg_temp.ci_c2_activate('c2fin') as c2fin_session_active;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-c2fin-auth')::text, true) is not null as jwt_set;
insert into _zc_r values ('c2_i_facts', jsonb_build_object('jwt_sub', pg_temp.ci_lbl(auth.uid()),
  'support_session', pg_temp.ci_lbl(app.current_support_session())));
create function pg_temp.ci_c2_fin6(p_claim jsonb) returns jsonb language sql volatile as $$
  select jsonb_build_object(
    'organization_id', public.card_attempt_finish((p_claim ->> 'attempt_row_id')::uuid, pg_temp.zc_id('org_b'),
      (p_claim ->> 'device_id')::uuid, p_claim ->> 'local_operation_id', 'live', 1234, 'ILS', 'commit', 'approved',
      pg_temp.zc_approved_fields(), null) - 'server_ts',
    'device_id', public.card_attempt_finish((p_claim ->> 'attempt_row_id')::uuid, (p_claim ->> 'organization_id')::uuid,
      pg_temp.zc_id('device-2'), p_claim ->> 'local_operation_id', 'live', 1234, 'ILS', 'commit', 'approved',
      pg_temp.zc_approved_fields(), null) - 'server_ts',
    'local_operation_id', public.card_attempt_finish((p_claim ->> 'attempt_row_id')::uuid,
      (p_claim ->> 'organization_id')::uuid, (p_claim ->> 'device_id')::uuid, pg_temp.zc_lop('ci-c2-other-identity'),
      'live', 1234, 'ILS', 'commit', 'approved', pg_temp.zc_approved_fields(), null) - 'server_ts',
    'mode', public.card_attempt_finish((p_claim ->> 'attempt_row_id')::uuid, (p_claim ->> 'organization_id')::uuid,
      (p_claim ->> 'device_id')::uuid, p_claim ->> 'local_operation_id', 'test', 1234, 'ILS', 'commit', 'approved',
      pg_temp.zc_approved_fields(), null) - 'server_ts',
    'amount_minor', public.card_attempt_finish((p_claim ->> 'attempt_row_id')::uuid, (p_claim ->> 'organization_id')::uuid,
      (p_claim ->> 'device_id')::uuid, p_claim ->> 'local_operation_id', 'live', 1235, 'ILS', 'commit', 'approved',
      pg_temp.zc_approved_fields(), null) - 'server_ts',
    'currency_code', public.card_attempt_finish((p_claim ->> 'attempt_row_id')::uuid,
      (p_claim ->> 'organization_id')::uuid, (p_claim ->> 'device_id')::uuid, p_claim ->> 'local_operation_id', 'live',
      1234, 'USD', 'commit', 'approved', pg_temp.zc_approved_fields(), null) - 'server_ts') $$;
-- The six scope-mismatch events of attempt p_att (one flag each), sorted like ci_c2_events.
create function pg_temp.ci_c2_mismatch_events(p_att text) returns jsonb language sql immutable as $$
  select pg_temp.ci_c2_sorted(jsonb_agg(jsonb_build_object('action', 'security.card_finish_scope_mismatch',
      'attempt', p_att, 'org', 'pilot-org', 'device', 'device-1', 'mode', 'live', 'actor_kind', 'adapter',
      'actor_reference', 'card_adapter', 'employee', null, 'reason', null, 'retention', 'none',
      'detail', (select jsonb_object_agg(f, f = k) from unnest(array['organization_id', 'device_id', 'local_operation_id',
                   'mode', 'amount_minor', 'currency_code']) f))))
  from unnest(array['organization_id', 'device_id', 'local_operation_id', 'mode', 'amount_minor', 'currency_code']) k $$;
create function pg_temp.ci_c2_mismatch_answers() returns jsonb language sql immutable as $$
  select jsonb_object_agg(k, '{"ok": false, "error": "conflict", "detail": "attempt_scope_mismatch"}'::jsonb)
    from unnest(array['organization_id', 'device_id', 'local_operation_id', 'mode', 'amount_minor', 'currency_code']) k $$;
create function pg_temp.ci_c2_approved(p_lop text) returns jsonb language sql stable as $$
  select jsonb_build_object('state', a.state, 'charge_may_exist', a.charge_may_exist,
    'provider_return_code', a.provider_return_code, 'approval_type', a.approval_type,
    'provider_status_code', a.provider_status_code, 'provider_return_class', a.provider_return_class,
    'provider_approved_at', a.provider_approved_at is not null, 'finished_at', a.finished_at is not null,
    'order_freed_at', a.order_freed_at is not null, 'resolution', a.resolution)
  from pg_temp.ci_row(1, p_lop) a $$;
insert into _zc_r values ('c2_i_f1_before', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-c2-f1')));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_i_f1_mismatch', pg_temp.ci_c2_fin6(pg_temp.ci_r('c2_f1')));
reset role;
select is(jsonb_build_object('facts', pg_temp.ci_r('c2_i_facts'), 'answers', pg_temp.ci_r('c2_i_f1_mismatch'),
    'written', pg_temp.ci_new(), 'events', pg_temp.ci_c2_events(),
    'row_unchanged', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-c2-f1')) = pg_temp.ci_r('c2_i_f1_before'),
    'state', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-f1'))).state),
  jsonb_build_object('facts', '{"jwt_sub": "ci-sup-c2fin-auth", "support_session": "ci-sup-c2fin-session"}'::jsonb,
    'answers', pg_temp.ci_c2_mismatch_answers(), 'written', '{"ledger": 0, "events": 6, "audit": 0}'::jsonb,
    'events', pg_temp.ci_c2_mismatch_events('att-ci-c2-f1'), 'row_unchanged', true, 'state', 'sent'),
  'CI-391 C2 provider fact (support active): with F1''s original caller c2fin now holding an ACTIVE support session (and its subject even set as the JWT), a commit approved reply naming F1 with a different organization, device, identity, mode, amount or currency each answers exactly conflict / attempt_scope_mismatch with one security.card_finish_scope_mismatch event flagging that field only (adapter actor, d1, LIVE); F1 never approved — its row unchanged (every column), still sent');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_i_f1_exact', pg_temp.zc_finish(pg_temp.ci_r('c2_f1'), 'commit', 'approved',
  pg_temp.zc_approved_fields()));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('c2_i_f1_exact') - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_c2_audit(), 'row', pg_temp.ci_c2_approved(pg_temp.zc_lop('ci-c2-f1'))),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-c2-f1'), 'state', 'approved',
      'classification', 'approved_unrecorded', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
      'provider_return_code', 0, 'recoverable', false, 'resume_count', 0),
    'written', '{"ledger": 0, "events": 0, "audit": 1}'::jsonb,
    'audit', jsonb_build_array(pg_temp.ci_c2_audit_row('card_attempt.approved', 'employee-1',
      '{"attempt_state": "approved", "release_requested": false}')),
    'row', '{"state": "approved", "charge_may_exist": false, "provider_return_code": 0, "approval_type": "approved",
      "provider_status_code": "ok1", "provider_return_class": "approved", "provider_approved_at": true,
      "finished_at": true, "order_freed_at": false, "resolution": null}'::jsonb),
  'CI-392 C2 provider fact (support active): the exact commit approved reply for F1 still records the provider fact — approved_unrecorded envelope (return code 0, not recoverable, resume_count 0), the row approved with its sanitized provider facts and unfreed, exactly one card_attempt.approved audit row for the initiating employee 1 on d1, no private event (card_attempt_finish takes no binding and no support check)');
insert into _zc_r values ('c2_i_f3_before', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-c2-f3')));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_i_f3', pg_temp.zc_finish(pg_temp.ci_r('c2_f3'), 'commit', 'approved',
  pg_temp.zc_approved_fields()));
reset role;
select is(jsonb_build_object('answer', pg_temp.ci_r('c2_i_f3') - 'server_ts', 'written', pg_temp.ci_new(),
    'events', pg_temp.ci_c2_events(),
    'row_unchanged', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-c2-f3')) = pg_temp.ci_r('c2_i_f3_before')),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-c2-f3'), 'state', 'unknown',
      'classification', 'resolved', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
      'resolution', 'provider_voided'),
    'written', '{"ledger": 0, "events": 1, "audit": 0}'::jsonb,
    'events', jsonb_build_array(jsonb_build_object('action', 'security.card_resolution_contradicted',
      'attempt', 'att-ci-c2-f3', 'org', 'pilot-org', 'device', 'device-1', 'mode', 'live', 'actor_kind', 'adapter',
      'actor_reference', 'card_adapter', 'employee', null, 'reason', null, 'retention', 'none',
      'detail', '{"source": "commit", "outcome": "approved"}'::jsonb)),
    'row_unchanged', true),
  'CI-393 C2 provider fact (support active): a commit approved reply reaching the resolved F3 changes nothing — the resolution stays final: the answer is F3''s own envelope (unknown, classification resolved, provider_voided), its row unchanged (every column), only the evidence event security.card_resolution_contradicted {source: commit, outcome: approved}, no audit');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_set;
update pin_sessions set expires_at = now() - interval '1 minute' where id = pg_temp.zc_id('pin-1');
insert into _zc_r values ('c2_i_f2_before', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-c2-f2')));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_i_f2_mismatch', pg_temp.ci_c2_fin6(pg_temp.ci_r('c2_f2')));
reset role;
select is(jsonb_build_object('pin_live', (select ps.expires_at > now() from public.pin_sessions ps
                                            where ps.id = pg_temp.zc_id('pin-1')),
    'answers', pg_temp.ci_r('c2_i_f2_mismatch'), 'written', pg_temp.ci_new(), 'events', pg_temp.ci_c2_events(),
    'row_unchanged', pg_temp.ci_rowj(1, pg_temp.zc_lop('ci-c2-f2')) = pg_temp.ci_r('c2_i_f2_before'),
    'state', (pg_temp.ci_row(1, pg_temp.zc_lop('ci-c2-f2'))).state),
  jsonb_build_object('pin_live', false, 'answers', pg_temp.ci_c2_mismatch_answers(),
    'written', '{"ledger": 0, "events": 6, "audit": 0}'::jsonb,
    'events', pg_temp.ci_c2_mismatch_events('att-ci-c2-f2'), 'row_unchanged', true, 'state', 'sent'),
  'CI-394 C2 provider fact (PIN expired): with the initiating cashier staff 1''s PIN session expired, the same six mismatched commit approved replies naming F2 each answer conflict / attempt_scope_mismatch with one scope-mismatch event flagging that field; F2 never approved — row unchanged, still sent');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_i_f2_exact', pg_temp.zc_finish(pg_temp.ci_r('c2_f2'), 'commit', 'approved',
  pg_temp.zc_approved_fields()));
reset role;
update pin_sessions set expires_at = now() + interval '6 hours' where id = pg_temp.zc_id('pin-1');
select is(jsonb_build_object('answer', pg_temp.ci_r('c2_i_f2_exact') - 'server_ts', 'written', pg_temp.ci_new(),
    'audit', pg_temp.ci_c2_audit(), 'row', pg_temp.ci_c2_approved(pg_temp.zc_lop('ci-c2-f2'))),
  jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ci-c2-f2'), 'state', 'approved',
      'classification', 'approved_unrecorded', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
      'provider_return_code', 0, 'recoverable', false, 'resume_count', 0),
    'written', '{"ledger": 0, "events": 0, "audit": 1}'::jsonb,
    'audit', jsonb_build_array(pg_temp.ci_c2_audit_row('card_attempt.approved', 'employee-1',
      '{"attempt_state": "approved", "release_requested": false}')),
    'row', '{"state": "approved", "charge_may_exist": false, "provider_return_code": 0, "approval_type": "approved",
      "provider_status_code": "ok1", "provider_return_class": "approved", "provider_approved_at": true,
      "finished_at": true, "order_freed_at": false, "resolution": null}'::jsonb),
  'CI-395 C2 provider fact (PIN expired): the exact commit approved reply for F2 after the initiating PIN session expired still records the provider fact — approved_unrecorded envelope, the row approved with its provider facts and unfreed, one card_attempt.approved audit row for employee 1 on d1, no private event');

-- (i, continued; C2 review fix TESTS-02) An out-of-contract approved reply never approves - with c2fin's support
-- session ACTIVE for the JWT subject of the finish call and with the initiating PIN session expired. F4 and F5 are
-- fresh LIVE claims of cashier staff 1 bound to the transport principal (card_attempt_finish stores and reads no
-- binding, SA-135); each gets a commit 'approved' reply with an
-- unreadable tip (the M2 essential rule of FR-84): the out_of_contract provider anomaly, never approved.
select pg_temp.zc_order('ci-c2-f4', 1234) is not null as f4, pg_temp.zc_order('ci-c2-f5', 1234) is not null as f5;
set local role service_role;
insert into _zc_r values
  ('c2_f4', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c2-f4'), 'live', p_order => pg_temp.zc_id('order-ci-c2-f4'),
                             p_rev => 1)),
  ('c2_f5', pg_temp.ci_claim(1, pg_temp.zc_lop('ci-c2-f5'), 'live', p_order => pg_temp.zc_id('order-ci-c2-f5'),
                             p_rev => 1));
reset role;
select pg_temp.ci_ok(pg_temp.ci_r('c2_f4')) ->> 'state' as f4_state, pg_temp.ci_ok(pg_temp.ci_r('c2_f5')) ->> 'state' as f5_state;
create function pg_temp.ci_c2_ooc(p_label text, p_lop text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'answer', jsonb_build_object('state', pg_temp.ci_r(p_label) ->> 'state',
                                 'classification', pg_temp.ci_r(p_label) ->> 'classification'),
    'row', (select jsonb_build_object('state', a.state, 'anomaly', a.provider_anomaly_code,
                                      'charge_may_exist', a.charge_may_exist,
                                      'provider_approved_at', a.provider_approved_at is not null)
              from pg_temp.ci_row(1, p_lop) a),
    'audit', (select coalesce(jsonb_agg(e ->> 'action' order by e ->> 'action'), '[]'::jsonb)
                from jsonb_array_elements(pg_temp.ci_c2_audit()) e),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('action', e ->> 'action', 'detail', e -> 'detail')
                                         order by e ->> 'action'), '[]'::jsonb)
                 from jsonb_array_elements(pg_temp.ci_c2_events()) e),
    'written', pg_temp.ci_new()) $$;
create function pg_temp.ci_c2_ooc_expected() returns jsonb language sql immutable as $$
  select '{"answer": {"state": "unknown", "classification": "provider_anomaly"},
           "row": {"state": "unknown", "anomaly": "out_of_contract", "charge_may_exist": true,
                   "provider_approved_at": false},
           "audit": ["card_attempt.provider_anomaly", "card_attempt.unknown"],
           "events": [{"action": "security.card_provider_field_dropped",
                       "detail": {"field": "tip_amount", "rule": "format", "source": "commit"}}],
           "written": {"ledger": 0, "events": 1, "audit": 2}}'::jsonb $$;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('ci-sup-c2fin-auth')::text, true) is not null as jwt_set;
insert into _zc_r values ('c2_i_f4_facts', jsonb_build_object('support_session', pg_temp.ci_lbl(app.current_support_session())));
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_i_f4_ooc', pg_temp.zc_finish(pg_temp.ci_r('c2_f4'), 'commit', 'approved',
  pg_temp.zc_approved_fields() || '{"tip_amount": "1.5"}'::jsonb));
reset role;
select is(pg_temp.ci_c2_ooc('c2_i_f4_ooc', pg_temp.zc_lop('ci-c2-f4')) || jsonb_build_object('facts', pg_temp.ci_r('c2_i_f4_facts')),
  pg_temp.ci_c2_ooc_expected() || '{"facts": {"support_session": "ci-sup-c2fin-session"}}'::jsonb,
  'CI-396 C2 provider fact (support active; review fix TESTS-02): with c2fin''s support session ACTIVE and its subject set as the JWT, a commit approved reply for F4 whose tip is unreadable is the out_of_contract provider anomaly - unknown, charge_may_exist, never approved (no provider_approved_at, no card_attempt.approved audit; the provider_anomaly and unknown audits and the field-drop event only)');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true) is not null as jwt_set;
update pin_sessions set expires_at = now() - interval '1 minute' where id = pg_temp.zc_id('pin-1');
select pg_temp.ci_mark();
set local role service_role;
insert into _zc_r values ('c2_i_f5_ooc', pg_temp.zc_finish(pg_temp.ci_r('c2_f5'), 'commit', 'approved',
  pg_temp.zc_approved_fields() || '{"tip_amount": "1.5"}'::jsonb));
reset role;
insert into _zc_r values ('c2_i_f5_facts', jsonb_build_object('pin_live', (select ps.expires_at > now()
  from public.pin_sessions ps where ps.id = pg_temp.zc_id('pin-1'))));
update pin_sessions set expires_at = now() + interval '6 hours' where id = pg_temp.zc_id('pin-1');
select is(pg_temp.ci_c2_ooc('c2_i_f5_ooc', pg_temp.zc_lop('ci-c2-f5')) || jsonb_build_object('facts', pg_temp.ci_r('c2_i_f5_facts')),
  pg_temp.ci_c2_ooc_expected() || '{"facts": {"pin_live": false}}'::jsonb,
  'CI-397 C2 provider fact (PIN expired; review fix TESTS-02): with the initiating cashier staff 1''s PIN session expired, the same out-of-contract commit approved reply for F5 is the out_of_contract provider anomaly - unknown, charge_may_exist, never approved');

select * from finish();
rollback;
