-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: app.sync_push card guard, identity-first recording gate, recording result, D-054 Resume, batching and transient classification (RR lane). Rollback-only synthetic fixtures, real SQL roles.
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
-- RR helpers (test-only; rolled back with the file).
-- ===========================================================================
-- Lookups.
create function pg_temp.rr_ord(label text) returns uuid language sql immutable as
$$ select pg_temp.zc_id('order-' || label) $$;
create function pg_temp.rr_r(label text) returns jsonb language sql stable as
$$ select z.r from _zc_r z where z.label = rr_r.label $$;
create function pg_temp.rr_res(label text, i integer default 0) returns jsonb language sql stable as
$$ select z.r -> 'results' -> rr_res.i from _zc_r z where z.label = rr_res.label $$;
-- An envelope with server_ts replaced by a presence flag, so everything else compares exactly.
create function pg_temp.rr_ts(j jsonb) returns jsonb language sql immutable as
$$ select (j - 'server_ts') || jsonb_build_object('server_ts?', coalesce(jsonb_typeof(j -> 'server_ts') = 'string', false)) $$;
create function pg_temp.rr_att(label text) returns app.card_provider_attempts language sql stable as
$$ select a from app.card_provider_attempts a
    where a.organization_id = pg_temp.zc_org() and a.device_id = pg_temp.zc_id('device-1')
      and a.local_operation_id = pg_temp.zc_lop(rr_att.label) $$;
create function pg_temp.rr_derive(label text) returns jsonb language sql stable as
$$ select app.card_attempt_derive(pg_temp.rr_att(rr_derive.label)) $$;
create function pg_temp.rr_so(label text, d integer default 1) returns public.sync_operations language sql stable as
$$ select so from public.sync_operations so
    where so.organization_id = pg_temp.zc_org() and so.device_id = pg_temp.zc_id('device-' || rr_so.d)
      and so.local_operation_id = pg_temp.zc_lop(rr_so.label) $$;
create function pg_temp.rr_so_state(label text, d integer default 1) returns jsonb language sql stable as
$$ select jsonb_build_object('status', so.status, 'class', so.last_error_class, 'code', so.last_error_code,
                             'retry_count', so.retry_count, 'result', so.result, 'reason', so.rejection_reason)
     from pg_temp.rr_so(rr_so_state.label, rr_so_state.d) so $$;
create function pg_temp.rr_so_n(labels text[], d integer default 1) returns bigint language sql stable as
$$ select count(*) from public.sync_operations so
    where so.organization_id = pg_temp.zc_org() and so.device_id = pg_temp.zc_id('device-' || rr_so_n.d)
      and so.local_operation_id in (select pg_temp.zc_lop(l) from unnest(rr_so_n.labels) l) $$;
create function pg_temp.rr_pay_n(label text) returns bigint language sql stable as
$$ select count(*) from public.payments p
    where p.device_id = pg_temp.zc_id('device-1') and p.local_operation_id = pg_temp.zc_lop(rr_pay_n.label) $$;
create function pg_temp.rr_order_pay_n(ord text) returns bigint language sql stable as
$$ select count(*) from public.payments p
    where p.organization_id = pg_temp.zc_org() and p.order_id = pg_temp.rr_ord(rr_order_pay_n.ord) $$;
create function pg_temp.rr_rej_audits(label text, d integer default 1) returns bigint language sql stable as
$$ select count(*) from public.audit_events e
    where e.organization_id = pg_temp.zc_org() and e.device_id = pg_temp.zc_id('device-' || rr_rej_audits.d)
      and e.action = 'sync.operation_rejected'
      and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop(rr_rej_audits.label) $$;
create function pg_temp.rr_resume_audits(label text, outcome text, denied text default null) returns bigint
language sql stable as
$$ select count(*) from public.audit_events e
    where e.organization_id = pg_temp.zc_org() and e.action = 'card_attempt.recording_resume_requested'
      and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop(rr_resume_audits.label)
      and e.new_values ->> 'outcome' = rr_resume_audits.outcome
      and (rr_resume_audits.denied is null or e.new_values ->> 'denied_reason' = rr_resume_audits.denied) $$;
-- The D-054 bookkeeping of one attempt and its sync row.
create function pg_temp.rr_resume_state(label text) returns jsonb language sql stable as
$$ select jsonb_build_object('so', so.status, 'retry_count', so.retry_count, 'resume_count', a.recording_resume_count,
                             'resume_history', jsonb_array_length(a.recording_resume_history),
                             'refusal_history', jsonb_array_length(a.recording_refusal_history),
                             'payments', pg_temp.rr_pay_n(rr_resume_state.label))
     from pg_temp.rr_so(rr_resume_state.label) so cross join pg_temp.rr_att(rr_resume_state.label) a $$;
-- Audit snapshot / delta over the pilot organization (every action, or those matching a pattern).
create function pg_temp.rr_audit_counts() returns jsonb language sql stable as
$$ select coalesce(jsonb_object_agg(s.action, s.n), '{}'::jsonb)
     from (select e.action, count(*) as n from public.audit_events e
            where e.organization_id = pg_temp.zc_org() group by e.action) s $$;
create function pg_temp.rr_snap(label text) returns void language sql volatile as
$$ insert into _zc_r (label, r) values ('snap-' || rr_snap.label, pg_temp.rr_audit_counts()) $$;
create function pg_temp.rr_delta(label text, pattern text default '%') returns jsonb language sql stable as
$$ select coalesce(jsonb_object_agg(c.key, (c.value #>> '{}')::bigint - coalesce((s.r ->> c.key)::bigint, 0))
                     filter (where (c.value #>> '{}')::bigint <> coalesce((s.r ->> c.key)::bigint, 0)
                               and c.key like rr_delta.pattern), '{}'::jsonb)
     from jsonb_each(pg_temp.rr_audit_counts()) c
     left join _zc_r s on s.label = 'snap-' || rr_delta.label $$;
-- Expected envelopes (the contract shapes).
create function pg_temp.rr_refusal(lop_label text, ord text, err text, det text default null) returns jsonb
language sql immutable as
$$ select jsonb_build_object('ok', false, 'error', err, 'order_id', pg_temp.rr_ord(ord),
                             'local_operation_id', pg_temp.zc_lop(lop_label), 'operation_type', 'payment.create',
                             'status', 'rejected', 'idempotency_replay', false, 'server_ts?', true)
          || case when det is null then '{}'::jsonb else jsonb_build_object('detail', det) end $$;
create function pg_temp.rr_close_refusal(lop_label text, shift_label text) returns jsonb language sql immutable as
$$ select jsonb_build_object('ok', false, 'error', 'card_payment_in_progress',
                             'shift_id', pg_temp.zc_id('rr-shift-' || shift_label),
                             'local_operation_id', pg_temp.zc_lop(lop_label), 'operation_type', 'shift.close',
                             'status', 'rejected', 'idempotency_replay', false, 'server_ts?', true) $$;
-- The stored permission_denied leg replayed (D-054 refusals), with or without resume_denied.
create function pg_temp.rr_denied(lop_label text, ord text, token text) returns jsonb language sql immutable as
$$ select jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', pg_temp.rr_ord(ord),
                             'local_operation_id', pg_temp.zc_lop(lop_label), 'operation_type', 'payment.create',
                             'status', 'rejected', 'idempotency_replay', true, 'server_ts?', true)
          || case when token is null then '{}'::jsonb else jsonb_build_object('resume_denied', token) end $$;
-- The retryable pending shape (transient_failure / single_operation_required / resume_authority_required).
create function pg_temp.rr_pending(lop_label text, op_type text, err text) returns jsonb language sql immutable as
$$ select jsonb_build_object('local_operation_id', pg_temp.zc_lop(lop_label), 'operation_type', op_type, 'ok', false,
                             'error', err, 'retryable', true, 'status', 'pending', 'idempotency_replay', false) $$;
create function pg_temp.rr_bad_resume(lop_label text, op_type text) returns jsonb language sql immutable as
$$ select jsonb_build_object('local_operation_id', pg_temp.zc_lop(lop_label), 'operation_type', op_type, 'ok', false,
                             'error', 'invalid_payload', 'detail', 'recording_resume', 'status', 'rejected',
                             'idempotency_replay', false) $$;
-- Operation builders (envelopes as the POS sends them).
create function pg_temp.rr_leg(label text, ord text default null, extra jsonb default '{}'::jsonb) returns jsonb
language sql immutable as
$$ select pg_temp.zc_pay_op(pg_temp.zc_lop(label), pg_temp.rr_ord(coalesce(ord, label)), 'card', 1234, extra) $$;
create function pg_temp.rr_cash(label text, ord text, extra jsonb default '{}'::jsonb) returns jsonb
language sql immutable as
$$ select pg_temp.zc_pay_op(pg_temp.zc_lop(label), pg_temp.rr_ord(ord), 'cash', 2000, extra) $$;
create function pg_temp.rr_op(label text, op_type text, ord text, payload jsonb) returns jsonb language sql immutable as
$$ select jsonb_build_object('local_operation_id', pg_temp.zc_lop(label), 'operation_type', op_type,
                             'target_entity', 'order', 'target_id', pg_temp.rr_ord(ord),
                             'client_created_at', '2026-10-24T00:00:00Z',
                             'payload', jsonb_build_object('order_id', pg_temp.rr_ord(ord)) || payload) $$;
create function pg_temp.rr_status_op(label text, ord text, extra jsonb default '{}'::jsonb) returns jsonb
language sql immutable as
$$ select pg_temp.rr_op(label, 'order.status', ord, jsonb_build_object('new_status', 'accepted')) || extra $$;
create function pg_temp.rr_close_op(label text, shift uuid) returns jsonb language sql immutable as
$$ select jsonb_build_object('local_operation_id', pg_temp.zc_lop(label), 'operation_type', 'shift.close',
                             'target_entity', 'shift', 'target_id', shift, 'client_created_at', '2026-10-24T00:00:00Z',
                             'payload', jsonb_build_object('shift_id', shift, 'counted_amount_minor', 0,
                                                           'reason', 'ZC001D synthetic close')) $$;
-- Service-only calls as the adapter makes them (call under SET LOCAL ROLE service_role).
create function pg_temp.rr_claim(label text, ord text) returns jsonb language sql volatile as
$$ select pg_temp.zc_claim(1, pg_temp.zc_lop(label), 'live', 1234, pg_temp.rr_ord(ord), 1) $$;
create function pg_temp.rr_fin(label text, source text, outcome text, fields jsonb default '{}'::jsonb,
                               poll text default null) returns jsonb language sql volatile as
$$ select pg_temp.zc_finish(pg_temp.rr_r('c-' || label), source, outcome, fields, poll) $$;
create function pg_temp.rr_free(label text) returns jsonb language sql volatile as
$$ select public.card_attempt_free_order(pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'), 'zc-token-1',
     pg_temp.zc_lop(label), 'ZC001D synthetic evidence free', 'provider_report', 'zc-free-' || label, pg_temp.zc_caller()) $$;
create function pg_temp.rr_markrec(label text, n integer default 1, hint text default 'permission_denied')
returns jsonb language sql volatile as
$$ select public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-' || n), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_lop(label), hint, pg_temp.zc_caller()) $$;
-- Operator calls (owner role).
create function pg_temp.rr_bind_step(mode text, lifecycle text, reason_code text) returns jsonb language sql volatile as
$$ select app.set_payment_terminal(pg_temp.zc_id('device-1'), mode, 'zc-term-' || mode || '-1',
     'zc-cred-' || mode || '-1', lifecycle, reason_code, 'ZC001D synthetic binding', 'zc001d-op/ref-2',
     pg_temp.zc_owner()) $$;
create function pg_temp.rr_resolve(label text, resolution text) returns jsonb language sql volatile as
$$ select app.card_attempt_resolve_orphan((pg_temp.rr_att(label)).id, resolution, 'zc-res-' || label,
     'ZC001D synthetic resolution', 'zc001d-op/ref-3', pg_temp.zc_owner()) $$;
-- Test-only: retire d1's open shift / drawer (direct update) and open a fresh shift + active drawer.
create function pg_temp.rr_new_shift(label text) returns uuid language plpgsql volatile as $$
declare
  v_shift uuid := pg_temp.zc_id('rr-shift-' || label);
begin
  update public.cash_drawer_sessions c set status = 'closed', closed_at = now()
   where c.organization_id = pg_temp.zc_org() and c.device_id = pg_temp.zc_id('device-1')
     and c.status in ('opened', 'active', 'counting');
  update public.shifts s set status = 'closed', closed_at = now()
   where s.organization_id = pg_temp.zc_org() and s.device_id = pg_temp.zc_id('device-1')
     and s.status in ('opening', 'open', 'closing');
  insert into public.shifts (id, organization_id, restaurant_id, branch_id, device_id,
      opened_by_employee_profile_id, resolved_membership_id, local_operation_id, status)
  values (v_shift, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
      pg_temp.zc_id('employee-1'), pg_temp.zc_id('membership-1'), 'rr-shift-' || label, 'open');
  insert into public.cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id,
      opened_by_employee_profile_id, opening_float_minor, local_operation_id)
  values (pg_temp.zc_id('rr-drawer-' || label), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
      pg_temp.zc_id('device-1'), v_shift, pg_temp.zc_id('employee-1'), 0, 'rr-drawer-' || label);
  return v_shift;
end $$;
-- app.sync_push as the POS (call under SET LOCAL ROLE authenticated). A raise (57014 included) is
-- captured with the whole call rolled back, never aborting the file.
create function pg_temp.rr_push(label text, n integer, ops jsonb, d integer default null) returns void
language plpgsql volatile as $$
begin
  insert into _zc_r (label, r) values (label, pg_temp.zc_push(n, ops, d));
exception
  when query_canceled then
    insert into _zc_r (label, r) values (label, jsonb_build_object('__error__', sqlstate, 'message', sqlerrm));
  when others then
    insert into _zc_r (label, r) values (label, jsonb_build_object('__error__', sqlstate, 'message', sqlerrm));
end $$;
-- Forced faults (item 10): a BEFORE trigger raising the SQLSTATE configured in a transaction GUC.
create function pg_temp.rr_fault() returns trigger language plpgsql as $$
declare
  v_state text := nullif(current_setting('rr.fault_state', true), '');
  v_table text := nullif(current_setting('rr.fault_table', true), '');
  v_msg text := coalesce(nullif(current_setting('rr.fault_msg', true), ''), 'rr forced fault');
begin
  if v_state is not null and v_table = tg_table_name then
    raise exception '%', v_msg using errcode = v_state;
  end if;
  return new;
end $$;
create trigger rr_fault_payments before insert on public.payments
  for each row execute function pg_temp.rr_fault();
create trigger rr_fault_shifts before update on public.shifts
  for each row execute function pg_temp.rr_fault();
create function pg_temp.rr_set_fault(tbl text, state text, msg text default null) returns void
language plpgsql volatile as $$
begin
  perform set_config('rr.fault_table', coalesce(tbl, ''), true);
  perform set_config('rr.fault_state', coalesce(state, ''), true);
  perform set_config('rr.fault_msg', coalesce(msg, ''), true);
end $$;
create function pg_temp.rr_push_fault(label text, n integer, ops jsonb, tbl text, state text,
                                      msg text default null, d integer default null) returns void
language plpgsql volatile as $$
begin
  perform pg_temp.rr_set_fault(tbl, state, msg);
  perform pg_temp.rr_push(label, n, ops, d);
  perform pg_temp.rr_set_fault(null, null, null);
end $$;
select pg_temp.rr_set_fault(null, null, null);

-- Every synthetic order of this file (d1 unless noted; total 1234 ILS, revision 1, submitted).
insert into _zc_r select 'orders-d1', jsonb_agg(pg_temp.zc_order(l)) from unnest(array[
  'a2', 'b2', 'b3', 'b4', 'b5', 'b6', 'g1',
  'n1', 'n1b', 'n1bx', 'n2', 'n3', 'n4', 'n5', 'n5b', 'n5x', 'n6', 'n7', 'n7x', 'n8', 'n8c', 'n9', 'n10', 'n11',
  'r1', 'r2', 'r3', 'r4', 'r5', 'r6',
  'fa1', 'fb1', 'fc1', 'fd1', 'fe1', 'ff1', 'ff2',
  'rs1', 'rs2', 'rs3', 'rs4', 'rs5', 'rs6', 'rs7', 'rs8', 'rs9', 'rs10', 'rs11', 'rs12', 'rs12x', 'rs13', 'rs14',
  'hx', 'h8', 'k2p', 'k4a', 'k4b', 'i1', 'i8', 'i8b', 'i9', 'i57', 'i7c', 'i6f',
  'j2p', 'jx', 'jst', 'j4a', 'j4b', 'k12', 'l1', 'l2']) l;
insert into _zc_r select 'orders-d2', jsonb_agg(pg_temp.zc_order(l, 1234, 2)) from unnest(array['b7']) l;

-- ===========================================================================
-- A. d1 with only a TEST binding: the hand-recorded card tender records
--    normally (item 4); an unresolved TEST attempt never blocks shift.close
--    (item 5).
-- ===========================================================================
insert into _zc_r select 'setup-a-pilot', pg_temp.zc_pilot('test');
insert into _zc_r select 'setup-a-bind', pg_temp.zc_bind(1, 'test');
select is(jsonb_build_object('pilot', pg_temp.rr_r('setup-a-pilot') -> 'ok',
                             'bind', pg_temp.rr_r('setup-a-bind') -> 'ok',
                             'lifecycle', pg_temp.rr_r('setup-a-bind') ->> 'new_lifecycle',
                             'mode', pg_temp.rr_r('setup-a-bind') ->> 'binding_mode'),
          jsonb_build_object('pilot', true, 'bind', true, 'lifecycle', 'enabled', 'mode', 'test'),
          'RR-001 setup: a TEST revision is ON and d1 holds an enabled TEST terminal binding');

set local role authenticated;
select pg_temp.rr_push('p-a2', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('a2-card'), pg_temp.rr_ord('a2'), 'card', 1234)));
reset role;
select is(jsonb_build_object('ok', pg_temp.rr_res('p-a2') -> 'ok', 'status', pg_temp.rr_res('p-a2') ->> 'status',
                             'method', pg_temp.rr_res('p-a2') ->> 'method',
                             'payments', pg_temp.rr_order_pay_n('a2'),
                             'payment', (select jsonb_build_object('method', p.method, 'status', p.status, 'amount', p.amount_minor)
                                           from public.payments p where p.order_id = pg_temp.rr_ord('a2'))),
          jsonb_build_object('ok', true, 'status', 'applied', 'method', 'card', 'payments', 1,
                             'payment', jsonb_build_object('method', 'card', 'status', 'completed', 'amount', 1234)),
          'RR-002 item 4: a hand-recorded card payment.create from d1 while d1 holds only a TEST binding records normally (applied, one completed card payment)');

set local role service_role;
insert into _zc_r select 'c-t1', pg_temp.zc_claim(1, pg_temp.zc_lop('t1'), 'test', 500);
reset role;
select is(jsonb_build_object('created', pg_temp.rr_r('c-t1') -> 'claim_created', 'state', pg_temp.rr_r('c-t1') ->> 'state',
                             'mode', (pg_temp.rr_att('t1')).mode, 'shift_id', (pg_temp.rr_att('t1')).shift_id),
          jsonb_build_object('created', true, 'state', 'sent', 'mode', 'test', 'shift_id', null::uuid),
          'RR-003 setup: a TEST attempt of d1 is claimed (sent) and carries no frozen shift');

select pg_temp.rr_snap('a4');
set local role authenticated;
select pg_temp.rr_push('p-a4', 2, jsonb_build_array(pg_temp.rr_close_op('a4-close', pg_temp.zc_id('shift-1'))));
reset role;
select is(jsonb_build_object('ok', pg_temp.rr_res('p-a4') -> 'ok', 'status', pg_temp.rr_res('p-a4') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('shift-1')),
                             'test_state', (pg_temp.rr_att('t1')).state,
                             'test_unresolved', pg_temp.rr_derive('t1') -> 'unresolved',
                             'card_or_sync_audit', pg_temp.rr_delta('a4', 'card_attempt.%') || pg_temp.rr_delta('a4', 'sync.%')),
          jsonb_build_object('ok', true, 'status', 'applied', 'shift', 'closed', 'test_state', 'sent',
                             'test_unresolved', true, 'card_or_sync_audit', '{}'::jsonb),
          'RR-004 item 5: shift.close of d1''s shift is applied (normal close path) while a TEST attempt of d1 is still sent and unresolved: a TEST attempt never blocks');

set local role service_role;
insert into _zc_r select 'f-t1', pg_temp.zc_finish(pg_temp.rr_r('c-t1'), 'commit', 'unknown');
reset role;
insert into _zc_r select 'res-t1', app.card_attempt_resolve_orphan((pg_temp.rr_att('t1')).id, 'test_closed',
  'zc-res-t1', 'ZC001D synthetic TEST closure', 'zc001d-op/ref-3', pg_temp.zc_owner());
insert into _zc_r select 'bind-a-drain', pg_temp.rr_bind_step('test', 'draining', 'test_end');
insert into _zc_r select 'bind-a-retire', pg_temp.rr_bind_step('test', 'retired', 'test_end');
insert into _zc_r select 'shift-s1', to_jsonb(pg_temp.rr_new_shift('s1'));
select is(jsonb_build_object('resolution', (pg_temp.rr_att('t1')).resolution,
                             'drain', pg_temp.rr_r('bind-a-drain') ->> 'new_lifecycle',
                             'retire', pg_temp.rr_r('bind-a-retire') ->> 'new_lifecycle',
                             'open_shift', (select s.id from public.shifts s
                                             where s.device_id = pg_temp.zc_id('device-1') and s.status = 'open')),
          jsonb_build_object('resolution', 'test_closed', 'drain', 'draining', 'retire', 'retired',
                             'open_shift', pg_temp.zc_id('rr-shift-s1')),
          'RR-005 setup: the TEST attempt is closed test_closed, d1''s TEST binding is retired and d1 has a fresh open shift');

-- ===========================================================================
-- B. card_terminal_required by binding lifecycle (item 4).
-- ===========================================================================
insert into _zc_r select 'setup-b-pilot', pg_temp.zc_pilot('live');
insert into _zc_r select 'setup-b-bind', pg_temp.zc_bind(1, 'live', 'configured');
select is(jsonb_build_object('pilot', pg_temp.rr_r('setup-b-pilot') -> 'ok', 'mode', pg_temp.rr_r('setup-b-pilot') ->> 'mode',
                             'bind', pg_temp.rr_r('setup-b-bind') ->> 'new_lifecycle',
                             'bind_mode', pg_temp.rr_r('setup-b-bind') ->> 'binding_mode'),
          jsonb_build_object('pilot', true, 'mode', 'live', 'bind', 'configured', 'bind_mode', 'live'),
          'RR-006 setup: a LIVE revision is ON and d1 holds a configured LIVE terminal binding');

select pg_temp.rr_snap('b2');
set local role authenticated;
select pg_temp.rr_push('p-b2', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('b2-card'), pg_temp.rr_ord('b2'), 'card', 1234)));
reset role;
select is(pg_temp.rr_ts(pg_temp.rr_res('p-b2')), pg_temp.rr_refusal('b2-card', 'b2', 'card_terminal_required'),
          'RR-007 item 4: a hand-recorded card payment.create (fresh identity) from d1 is refused card_terminal_required while d1''s LIVE binding is configured (error, server_ts, order_id only)');
select is(jsonb_build_object('payments', pg_temp.rr_order_pay_n('b2'), 'so', (pg_temp.rr_so('b2-card')).status,
                             'reason', (pg_temp.rr_so('b2-card')).rejection_reason, 'audit', pg_temp.rr_delta('b2')),
          jsonb_build_object('payments', 0, 'so', 'rejected', 'reason', 'card_terminal_required',
                             'audit', jsonb_build_object('sync.operation_rejected', 1)),
          'RR-008 item 4: that refusal writes no payment; the sync row is rejected card_terminal_required with exactly one sync.operation_rejected audit');

insert into _zc_r select 'bind-b-enable', pg_temp.rr_bind_step('live', 'enabled', 'live_activation');
set local role authenticated;
select pg_temp.rr_push('p-b3', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('b3-card'), pg_temp.rr_ord('b3'), 'card', 1234)));
reset role;
select is(jsonb_build_object('binding', pg_temp.rr_r('bind-b-enable') ->> 'new_lifecycle',
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-b3')), 'payments', pg_temp.rr_order_pay_n('b3')),
          jsonb_build_object('binding', 'enabled',
                             'result', pg_temp.rr_refusal('b3-card', 'b3', 'card_terminal_required'), 'payments', 0),
          'RR-009 item 4: the same hand-recorded card tender is refused card_terminal_required while the LIVE binding is enabled (no payment)');

insert into _zc_r select 'setup-b-off', pg_temp.zc_pilot('live', false);
set local role authenticated;
select pg_temp.rr_push('p-b4', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('b4-card'), pg_temp.rr_ord('b4'), 'card', 1234)));
reset role;
select is(jsonb_build_object('revision_enabled', (app.card_pilot_revision_current()).enabled,
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-b4')), 'payments', pg_temp.rr_order_pay_n('b4')),
          jsonb_build_object('revision_enabled', false,
                             'result', pg_temp.rr_refusal('b4-card', 'b4', 'card_terminal_required'), 'payments', 0),
          'RR-010 item 4: with the operator revision OFF (binding still enabled) the hand-recorded card tender is still refused card_terminal_required');
insert into _zc_r select 'setup-b-on', pg_temp.zc_pilot('live');

insert into _zc_r select 'bind-b-drain', pg_temp.rr_bind_step('live', 'draining', 'incident');
set local role authenticated;
select pg_temp.rr_push('p-b5', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('b5-card'), pg_temp.rr_ord('b5'), 'card', 1234)));
reset role;
select is(jsonb_build_object('binding', pg_temp.rr_r('bind-b-drain') ->> 'new_lifecycle',
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-b5')), 'payments', pg_temp.rr_order_pay_n('b5')),
          jsonb_build_object('binding', 'draining',
                             'result', pg_temp.rr_refusal('b5-card', 'b5', 'card_terminal_required'), 'payments', 0),
          'RR-011 item 4: the hand-recorded card tender is refused card_terminal_required while the LIVE binding is draining');

insert into _zc_r select 'bind-b-retire', pg_temp.rr_bind_step('live', 'retired', 'end_of_pilot');
set local role authenticated;
select pg_temp.rr_push('p-b6', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('b6-card'), pg_temp.rr_ord('b6'), 'card', 1234)));
select pg_temp.rr_push('p-b7', 8, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('b7-card'), pg_temp.rr_ord('b7'), 'card', 1234)));
reset role;
select is(jsonb_build_object('binding', pg_temp.rr_r('bind-b-retire') ->> 'new_lifecycle',
                             'status', pg_temp.rr_res('p-b6') ->> 'status', 'method', pg_temp.rr_res('p-b6') ->> 'method',
                             'payments', pg_temp.rr_order_pay_n('b6')),
          jsonb_build_object('binding', 'retired', 'status', 'applied', 'method', 'card', 'payments', 1),
          'RR-012 item 4: once d1''s LIVE binding is retired the hand-recorded card tender records normally (applied, one card payment)');
select is(jsonb_build_object('status', pg_temp.rr_res('p-b7') ->> 'status', 'method', pg_temp.rr_res('p-b7') ->> 'method',
                             'payments', pg_temp.rr_order_pay_n('b7')),
          jsonb_build_object('status', 'applied', 'method', 'card', 'payments', 1),
          'RR-013 item 4: a hand-recorded card tender from d2 (no binding) records normally');

insert into _zc_r select 'setup-b-rebind', pg_temp.zc_bind(1, 'live');
select is(jsonb_build_object('ok', pg_temp.rr_r('setup-b-rebind') -> 'ok',
                             'lifecycle', pg_temp.rr_r('setup-b-rebind') ->> 'new_lifecycle',
                             'revision', (app.card_pilot_revision_current()).enabled),
          jsonb_build_object('ok', true, 'lifecycle', 'enabled', 'revision', true),
          'RR-014 setup: a new LIVE binding of d1 is enabled and the LIVE revision is ON for the rest of the file');

-- ===========================================================================
-- C. Item 1: the guard refuses every competing operation on a claimed order.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-g1', pg_temp.rr_claim('g1', 'g1');
reset role;
select is(jsonb_build_object('created', pg_temp.rr_r('c-g1') -> 'claim_created', 'state', (pg_temp.rr_att('g1')).state,
                             'shift', (pg_temp.rr_att('g1')).shift_id, 'drawer', (pg_temp.rr_att('g1')).cash_drawer_session_id,
                             'claim_active', app.card_order_claim_active(pg_temp.zc_org(), pg_temp.rr_ord('g1'))),
          jsonb_build_object('created', true, 'state', 'sent', 'shift', pg_temp.zc_id('rr-shift-s1'),
                             'drawer', pg_temp.zc_id('rr-drawer-s1'), 'claim_active', true),
          'RR-015 setup: a LIVE attempt claims order g1 (sent), frozen to d1''s open shift and active drawer; the order has an active claim');

select pg_temp.rr_snap('g1');
set local role authenticated;
select pg_temp.rr_push('p-g1', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('g1-cash'), pg_temp.rr_ord('g1'), 'cash', 2000),
  pg_temp.zc_pay_op(pg_temp.zc_lop('g1-card'), pg_temp.rr_ord('g1'), 'card', 1234),
  pg_temp.zc_pay_op(pg_temp.zc_lop('g1-bit'), pg_temp.rr_ord('g1'), 'bit', 1234),
  pg_temp.zc_pay_op(pg_temp.zc_lop('g1-ext'), pg_temp.rr_ord('g1'), 'external', 1234),
  pg_temp.rr_op('g1-disc', 'order.discount', 'g1', jsonb_build_object('scope', 'order', 'discount_type', 'amount',
                                                                      'value', 100, 'reason', 'ZC001D synthetic discount')),
  pg_temp.rr_op('g1-void', 'order.void', 'g1', jsonb_build_object('reason', 'ZC001D synthetic void')),
  pg_temp.rr_op('g1-add', 'order.items_add', 'g1', jsonb_build_object('order_items', jsonb_build_array(
    jsonb_build_object('menu_item_id', pg_temp.zc_id('menu-x'), 'quantity', 1)))),
  pg_temp.rr_op('g1-edit', 'order.edit', 'g1', jsonb_build_object('expected', jsonb_build_object('revision', 1),
    'changes', jsonb_build_array(jsonb_build_object('kind', 'remove', 'order_item_id', pg_temp.zc_id('item-x')))))));
reset role;
select results_eq(
  $$ select pg_temp.rr_ts(t.e) from jsonb_array_elements(pg_temp.rr_r('p-g1') -> 'results') with ordinality t(e, n)
      where t.n <= 4 order by t.n $$,
  $$ select pg_temp.rr_refusal(v.l, 'g1', 'payment_in_progress', 'card_attempt_active')
       from (values (1, 'g1-cash'), (2, 'g1-card'), (3, 'g1-bit'), (4, 'g1-ext')) v(n, l) order by v.n $$,
  'RR-016 item 1: payment.create of cash, card, bit and external (fresh non-provider identities) on the claimed order are each answered rejected payment_in_progress / card_attempt_active with only server_ts and order_id (no attempt fact)');
select results_eq(
  $$ select pg_temp.rr_ts(t.e) from jsonb_array_elements(pg_temp.rr_r('p-g1') -> 'results') with ordinality t(e, n)
      where t.n > 4 order by t.n $$,
  $$ select pg_temp.rr_refusal(v.l, 'g1', 'payment_in_progress', 'card_attempt_active') || jsonb_build_object('operation_type', v.t)
       from (values (5, 'g1-disc', 'order.discount'), (6, 'g1-void', 'order.void'),
                    (7, 'g1-add', 'order.items_add'), (8, 'g1-edit', 'order.edit')) v(n, l, t) order by v.n $$,
  'RR-017 item 1: order.discount, order.void, order.items_add and order.edit (valid target_id = payload.order_id envelopes) on the claimed order are each answered rejected payment_in_progress / card_attempt_active (no attempt fact)');
select results_eq(
  $$ select so.operation_type, so.status, so.rejection_reason, so.last_error_class, pg_temp.rr_ts(so.result)
       from public.sync_operations so
      where so.organization_id = pg_temp.zc_org() and so.device_id = pg_temp.zc_id('device-1')
        and so.local_operation_id in (select pg_temp.zc_lop(l) from unnest(array['g1-cash', 'g1-card', 'g1-bit',
              'g1-ext', 'g1-disc', 'g1-void', 'g1-add', 'g1-edit']) l)
      order by so.local_operation_id $$,
  $$ select v.t, 'rejected'::text, 'payment_in_progress'::text, 'permanent'::text,
            jsonb_build_object('ok', false, 'error', 'payment_in_progress', 'detail', 'card_attempt_active',
                               'order_id', pg_temp.rr_ord('g1'), 'server_ts?', true)
       from (values ('g1-cash', 'payment.create'), ('g1-card', 'payment.create'), ('g1-bit', 'payment.create'),
                    ('g1-ext', 'payment.create'), ('g1-disc', 'order.discount'), ('g1-void', 'order.void'),
                    ('g1-add', 'order.items_add'), ('g1-edit', 'order.edit')) v(l, t)
      order by pg_temp.zc_lop(v.l) $$,
  'RR-018 item 1: each of the eight operations is memoized as a rejected sync row whose stored result is exactly {ok, error, detail, server_ts, order_id}');
select is(jsonb_build_object('delta', pg_temp.rr_delta('g1'),
                             'per_op', (select jsonb_agg(pg_temp.rr_rej_audits(l)) from unnest(array['g1-cash', 'g1-card',
                                         'g1-bit', 'g1-ext', 'g1-disc', 'g1-void', 'g1-add', 'g1-edit']) l)),
          jsonb_build_object('delta', jsonb_build_object('sync.operation_rejected', 8),
                             'per_op', '[1, 1, 1, 1, 1, 1, 1, 1]'::jsonb),
          'RR-019 item 1: the eight refusals wrote exactly one sync.operation_rejected audit each and nothing else (no card_attempt.*, payment, discount or void audit)');
select is((select jsonb_build_object('status', o.status, 'revision', o.revision, 'grand', o.grand_total_minor,
                                     'discount', o.discount_total_minor, 'voided_at', o.voided_at, 'edit_count', o.edit_count)
             from public.orders o where o.id = pg_temp.rr_ord('g1'))
          || jsonb_build_object('payments', pg_temp.rr_order_pay_n('g1'),
               'items', (select count(*) from public.order_items x where x.order_id = pg_temp.rr_ord('g1')),
               'rounds', (select count(*) from public.order_service_rounds x where x.order_id = pg_temp.rr_ord('g1')),
               'edits', (select count(*) from public.order_edits x where x.order_id = pg_temp.rr_ord('g1')),
               'order_ops', (select count(*) from public.order_operations x where x.order_id = pg_temp.rr_ord('g1')),
               'attempt_state', (pg_temp.rr_att('g1')).state,
               'claim_active', app.card_order_claim_active(pg_temp.zc_org(), pg_temp.rr_ord('g1'))),
          jsonb_build_object('status', 'submitted', 'revision', 1, 'grand', 1234, 'discount', 0,
                             'voided_at', null::timestamptz, 'edit_count', 0, 'payments', 0, 'items', 0, 'rounds', 0,
                             'edits', 0, 'order_ops', 0, 'attempt_state', 'sent', 'claim_active', true),
          'RR-020 item 1: no payment, discount, void, item, round, edit or order-operation write reached order g1; the attempt is untouched (sent, claim still active)');
-- A non-UUID text identity is compared as text by the guard (never cast): it meets the same exclusion.
set local role authenticated;
select pg_temp.rr_push('p-g1-text', 1, jsonb_build_array(
  pg_temp.zc_pay_op('zc001d-rr-non-uuid-op-1', pg_temp.rr_ord('g1'), 'cash', 2000)));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-g1-text')),
                             'so', (select so.status from public.sync_operations so
                                     where so.organization_id = pg_temp.zc_org() and so.device_id = pg_temp.zc_id('device-1')
                                       and so.local_operation_id = 'zc001d-rr-non-uuid-op-1')),
          jsonb_build_object('result', jsonb_build_object('ok', false, 'error', 'payment_in_progress',
                                         'detail', 'card_attempt_active', 'order_id', pg_temp.rr_ord('g1'),
                                         'local_operation_id', 'zc001d-rr-non-uuid-op-1', 'operation_type', 'payment.create',
                                         'status', 'rejected', 'idempotency_replay', false, 'server_ts?', true),
                             'so', 'rejected'),
          'RR-021 item 1: a non-UUID text local_operation_id passes the guard untouched (no cast error) and meets the same payment_in_progress exclusion');
-- Authorization first: an inactive employee profile with an active membership is admitted by
-- record_payment, so it still meets the claim exclusion; a certainly-denied session gets the RPC's own refusal.
update public.employee_profiles ep set employment_status = 'suspended' where ep.id = pg_temp.zc_id('employee-1');
set local role authenticated;
select pg_temp.rr_push('p-g1-inactive', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('g1-inactive'), pg_temp.rr_ord('g1'), 'cash', 2000)));
reset role;
update public.employee_profiles ep set employment_status = 'active' where ep.id = pg_temp.zc_id('employee-1');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-g1-inactive')),
          pg_temp.rr_refusal('g1-inactive', 'g1', 'payment_in_progress', 'card_attempt_active'),
          'RR-022 item 1 (authorization first): a cashier whose employee profile is suspended but whose membership is active is still refused payment_in_progress on the claimed order (no deferral on a check the RPC does not make)');
update public.memberships m set permissions = '{"void_order": "false"}'::jsonb where m.id = pg_temp.zc_id('membership-1');
select pg_temp.rr_snap('g1-defer');
set local role authenticated;
select pg_temp.rr_push('p-g1-kitchen', 4, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('g1-kitchen'), pg_temp.rr_ord('g1'), 'cash', 2000)));
select pg_temp.rr_push('p-g1-novoid', 1, jsonb_build_array(
  pg_temp.rr_op('g1-novoid', 'order.void', 'g1', jsonb_build_object('reason', 'ZC001D synthetic void'))));
reset role;
update public.memberships m set permissions = '{}'::jsonb where m.id = pg_temp.zc_id('membership-1');
select is(jsonb_build_object('kitchen', pg_temp.rr_ts(pg_temp.rr_res('p-g1-kitchen')),
                             'no_void_capability', pg_temp.rr_ts(pg_temp.rr_res('p-g1-novoid')),
                             'audit', pg_temp.rr_delta('g1-defer'), 'payments', pg_temp.rr_order_pay_n('g1'),
                             'order_status', (select o.status from public.orders o where o.id = pg_temp.rr_ord('g1'))),
          jsonb_build_object('kitchen', pg_temp.rr_refusal('g1-kitchen', 'g1', 'permission_denied'),
                             'no_void_capability', pg_temp.rr_refusal('g1-novoid', 'g1', 'permission_denied')
                                                   || jsonb_build_object('operation_type', 'order.void'),
                             'audit', jsonb_build_object('payment.denied', 1, 'order.void_denied', 1,
                                                         'sync.operation_rejected', 2),
                             'payments', 0, 'order_status', 'submitted'),
          'RR-023 item 1 (authorization first): a session the dispatched RPC is certain to deny (kitchen role; cashier without void capability) gets that RPC''s own permission_denied, never payment_in_progress, and no business write');

-- ===========================================================================
-- D. Item 2: the identity-first gate for LIVE attempt identities.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l)
  from unnest(array['n1', 'n1b', 'n2', 'n3', 'n4', 'n5', 'n5b', 'n6', 'n7', 'n8', 'n8c', 'n9', 'n10', 'n11']) l;
insert into _zc_r select 'f-n2', pg_temp.rr_fin('n2', 'commit', 'anomaly', '{"anomaly_code": "amount_mismatch"}');
insert into _zc_r select 'f-n3-u', pg_temp.rr_fin('n3', 'commit', 'unknown');
insert into _zc_r select 'f-n3-l', pg_temp.rr_fin('n3', 'lookup', 'failed', '{}', 'operator');
insert into _zc_r select 'free-n3', pg_temp.rr_free('n3');
insert into _zc_r select 'f-n4', pg_temp.rr_fin('n4', 'commit', 'anomaly', '{"anomaly_code": "voided"}');
insert into _zc_r select 'f-' || l, pg_temp.rr_fin(l, 'commit', 'approved', pg_temp.zc_approved_fields())
  from unnest(array['n5', 'n5b', 'n6', 'n7', 'n8', 'n8c', 'n9', 'n10', 'n11']) l;
reset role;
insert into _zc_r select 'res-n2', pg_temp.rr_resolve('n2', 'provider_voided');
-- A payments row under n7's identity (another order, another tender): the strict join does not match.
insert into public.payments (organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id, method, status,
    amount_minor, tendered_minor, change_minor, currency_code, local_operation_id)
values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.rr_ord('n7x'), pg_temp.zc_id('device-1'),
    pg_temp.zc_id('employee-1'), pg_temp.zc_id('membership-1'), pg_temp.zc_id('rr-shift-s1'),
    pg_temp.zc_id('rr-drawer-s1'), 'cash', 'completed', 1234, 1234, 0, 'ILS', pg_temp.zc_lop('n7'));
update public.orders o set grand_total_minor = 1500, subtotal_minor = 1500
 where o.id in (pg_temp.rr_ord('n8'), pg_temp.rr_ord('n11'));
update public.orders o set currency_code = 'USD' where o.id = pg_temp.rr_ord('n8c');
select is((select jsonb_object_agg(l, jsonb_build_object('state', (pg_temp.rr_att(l)).state,
                                                         'cme', (pg_temp.rr_att(l)).charge_may_exist,
                                                         'freed', (pg_temp.rr_att(l)).order_freed_at is not null,
                                                         'resolution', (pg_temp.rr_att(l)).resolution))
             from unnest(array['n1', 'n2', 'n3', 'n4', 'n5', 'n7']) l),
          jsonb_build_object(
            'n1', jsonb_build_object('state', 'sent', 'cme', false, 'freed', false, 'resolution', null::text),
            'n2', jsonb_build_object('state', 'unknown', 'cme', true, 'freed', true, 'resolution', 'provider_voided'),
            'n3', jsonb_build_object('state', 'unknown', 'cme', false, 'freed', true, 'resolution', null::text),
            'n4', jsonb_build_object('state', 'unknown', 'cme', true, 'freed', false, 'resolution', null::text),
            'n5', jsonb_build_object('state', 'approved', 'cme', false, 'freed', false, 'resolution', null::text),
            'n7', jsonb_build_object('state', 'approved', 'cme', false, 'freed', false, 'resolution', null::text)),
          'RR-024 setup: gate attempts in place (sent; anomalous + voided resolution; evidence-freed unknown; anomalous; approved)');

select pg_temp.rr_snap('d');
set local role authenticated;
select pg_temp.rr_push('p-n1', 1, jsonb_build_array(pg_temp.rr_leg('n1')));
select pg_temp.rr_push('p-n1b', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('n1b'), pg_temp.rr_ord('n1bx'), 'cash', 1234)));
select pg_temp.rr_push('p-n2', 1, jsonb_build_array(pg_temp.rr_leg('n2')));
select pg_temp.rr_push('p-n3', 1, jsonb_build_array(pg_temp.rr_leg('n3')));
select pg_temp.rr_push('p-n4', 1, jsonb_build_array(pg_temp.rr_leg('n4')));
select pg_temp.rr_push('p-n5', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('n5'), pg_temp.rr_ord('n5x'), 'card', 1234)));
select pg_temp.rr_push('p-n5b', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('n5b'), pg_temp.rr_ord('n5x'), 'cash', 1234)));
select pg_temp.rr_push('p-n6', 1, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('n6'), pg_temp.rr_ord('n6'), 'cash', 1234)));
select pg_temp.rr_push('p-n7', 1, jsonb_build_array(pg_temp.rr_leg('n7')));
select pg_temp.rr_push('p-n8', 1, jsonb_build_array(pg_temp.rr_leg('n8')));
select pg_temp.rr_push('p-n8c', 1, jsonb_build_array(pg_temp.rr_leg('n8c')));
reset role;
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n1')),
          pg_temp.rr_refusal('n1', 'n1', 'provider_recording_refused', 'attempt_not_approved'),
          'RR-025 item 2: the canonical leg of a sent LIVE attempt is refused provider_recording_refused / attempt_not_approved');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n1b')),
          pg_temp.rr_refusal('n1b', 'n1bx', 'provider_recording_refused', 'attempt_not_approved'),
          'RR-026 item 2 (order): a sent attempt''s identity pushed with another order and a cash tender is still attempt_not_approved (precedes order_mismatch / tender_mismatch)');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n2')),
          pg_temp.rr_refusal('n2', 'n2', 'provider_recording_refused', 'attempt_resolved'),
          'RR-027 item 2: a resolved attempt (provider_voided; also freed and anomalous) is refused attempt_resolved (precedes attempt_freed / provider_anomaly / attempt_not_approved)');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n3')),
          pg_temp.rr_refusal('n3', 'n3', 'provider_recording_refused', 'attempt_freed'),
          'RR-028 item 2: an evidence-freed attempt is refused attempt_freed (precedes attempt_not_approved)');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n4')),
          pg_temp.rr_refusal('n4', 'n4', 'provider_recording_refused', 'provider_anomaly'),
          'RR-029 item 2: an anomalous attempt (charge_may_exist) is refused provider_anomaly (precedes attempt_not_approved)');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n5')),
          pg_temp.rr_refusal('n5', 'n5x', 'provider_recording_refused', 'order_mismatch'),
          'RR-030 item 2: an approved attempt''s identity whose payload names another order is refused order_mismatch (order_id echoed is the payload''s own)');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n5b')),
          pg_temp.rr_refusal('n5b', 'n5x', 'provider_recording_refused', 'order_mismatch'),
          'RR-031 item 2 (order): another order with a cash tender is order_mismatch (precedes tender_mismatch)');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n6')),
          pg_temp.rr_refusal('n6', 'n6', 'provider_recording_refused', 'tender_mismatch'),
          'RR-032 item 2: an approved attempt''s identity pushed as a cash tender is refused tender_mismatch');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n7')),
          pg_temp.rr_refusal('n7', 'n7', 'provider_recording_refused', 'payment_exists'),
          'RR-033 item 2: an approved attempt whose identity already carries a payments row (not its strict join) is refused payment_exists');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n8')), pg_temp.rr_refusal('n8', 'n8', 'amount_mismatch'),
          'RR-034 item 2: the canonical leg after the order total changed (owner update) is refused amount_mismatch (no detail)');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n8c')), pg_temp.rr_refusal('n8c', 'n8c', 'amount_mismatch'),
          'RR-035 item 2: the canonical leg after the order currency changed (owner update) is refused amount_mismatch');
select is((select jsonb_object_agg(l, jsonb_build_object('so', (pg_temp.rr_so(l)).status,
                                                         'reason', (pg_temp.rr_so(l)).rejection_reason,
                                                         'payments', pg_temp.rr_pay_n(l),
                                                         'rejected_audits', pg_temp.rr_rej_audits(l)))
             from unnest(array['n1', 'n1b', 'n2', 'n3', 'n4', 'n5', 'n5b', 'n6', 'n7', 'n8', 'n8c']) l),
          jsonb_build_object(
            'n1', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n1b', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n2', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n3', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n4', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n5', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n5b', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n6', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'rejected_audits', 1),
            'n7', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 1, 'rejected_audits', 1),
            'n8', jsonb_build_object('so', 'rejected', 'reason', 'amount_mismatch', 'payments', 0, 'rejected_audits', 1),
            'n8c', jsonb_build_object('so', 'rejected', 'reason', 'amount_mismatch', 'payments', 0, 'rejected_audits', 1)),
          'RR-036 item 2: every gate refusal is a rejected sync row (rejection_reason = its error) with one sync.operation_rejected audit and records no payment (n7 keeps only its pre-existing row)');
select is(jsonb_build_object('n7_order_payments', pg_temp.rr_order_pay_n('n7'),
                             'n8_order_payments', pg_temp.rr_order_pay_n('n8'),
                             'states', (select jsonb_agg((pg_temp.rr_att(l)).state order by l)
                                          from unnest(array['n5', 'n6', 'n7', 'n8', 'n8c']) l)),
          jsonb_build_object('n7_order_payments', 0, 'n8_order_payments', 0,
                             'states', '["approved", "approved", "approved", "approved", "approved"]'::jsonb),
          'RR-037 item 2: the refused approvals stay approved and unrecorded (no payment on their orders)');

-- The frozen context (n9 drawer closed, n10 shift closed, n11 total changed + drawer closed).
update public.cash_drawer_sessions c set status = 'closed', closed_at = now() where c.id = pg_temp.zc_id('rr-drawer-s1');
set local role authenticated;
select pg_temp.rr_push('p-n9', 1, jsonb_build_array(pg_temp.rr_leg('n9')));
select pg_temp.rr_push('p-n11', 1, jsonb_build_array(pg_temp.rr_leg('n11')));
reset role;
update public.cash_drawer_sessions c set status = 'active', closed_at = null where c.id = pg_temp.zc_id('rr-drawer-s1');
update public.shifts s set status = 'closed', closed_at = now() where s.id = pg_temp.zc_id('rr-shift-s1');
set local role authenticated;
select pg_temp.rr_push('p-n10', 1, jsonb_build_array(pg_temp.rr_leg('n10')));
reset role;
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n9')), pg_temp.rr_refusal('n9', 'n9', 'card_context_lost'),
          'RR-038 item 2: the canonical leg after the frozen drawer session closed (owner update; shift still open) is refused card_context_lost');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n10')), pg_temp.rr_refusal('n10', 'n10', 'card_context_lost'),
          'RR-039 item 2: the canonical leg after the frozen shift closed (owner update; drawer active) is refused card_context_lost');
select is(pg_temp.rr_ts(pg_temp.rr_res('p-n11')), pg_temp.rr_refusal('n11', 'n11', 'amount_mismatch'),
          'RR-040 item 2 (order): total changed AND drawer closed answers amount_mismatch (precedes card_context_lost)');
select is(jsonb_build_object('payments', (select jsonb_agg(pg_temp.rr_pay_n(l)) from unnest(array['n9', 'n10', 'n11']) l),
                             'reasons', (select jsonb_agg((pg_temp.rr_so(l)).rejection_reason) from unnest(array['n9', 'n10', 'n11']) l),
                             'audit', pg_temp.rr_delta('d')),
          jsonb_build_object('payments', '[0, 0, 0]'::jsonb,
                             'reasons', '["card_context_lost", "card_context_lost", "amount_mismatch"]'::jsonb,
                             'audit', jsonb_build_object('sync.operation_rejected', 14)),
          'RR-041 item 2: the context refusals record no payment; the fourteen gate refusals wrote exactly fourteen sync.operation_rejected audits and no other audit row');

-- ===========================================================================
-- E. Item 3: the admissible LIVE leg records exactly once (+ item 6 cases).
-- ===========================================================================
insert into _zc_r select 'shift-s2', to_jsonb(pg_temp.rr_new_shift('s2'));
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['r1', 'r2', 'r3', 'r4', 'r5', 'r6']) l;
insert into _zc_r select 'f-' || l, pg_temp.rr_fin(l, 'commit', 'approved', pg_temp.zc_approved_fields())
  from unnest(array['r1', 'r2', 'r3', 'r4', 'r5', 'r6']) l;
reset role;
select pg_temp.rr_snap('r1');
set local role authenticated;
select pg_temp.rr_push('p-r1', 1, jsonb_build_array(pg_temp.rr_leg('r1')));
reset role;
select is(jsonb_build_object('ok', pg_temp.rr_res('p-r1') -> 'ok', 'status', pg_temp.rr_res('p-r1') ->> 'status',
                             'replay', pg_temp.rr_res('p-r1') -> 'idempotency_replay',
                             'method', pg_temp.rr_res('p-r1') ->> 'method',
                             'shift', pg_temp.rr_res('p-r1') ->> 'shift_id',
                             'drawer', pg_temp.rr_res('p-r1') ->> 'cash_drawer_session_id',
                             'change', pg_temp.rr_res('p-r1') -> 'change_due_minor'),
          jsonb_build_object('ok', true, 'status', 'applied', 'replay', false, 'method', 'card',
                             'shift', pg_temp.zc_id('rr-shift-s2')::text, 'drawer', pg_temp.zc_id('rr-drawer-s2')::text,
                             'change', 0),
          'RR-042 item 3: the canonical leg (no expected_revision) of an approved LIVE attempt is applied in the frozen shift / drawer');
select is((select jsonb_build_object('n', count(*), 'method', min(p.method), 'status', min(p.status),
                                     'amount', min(p.amount_minor), 'tendered', min(p.tendered_minor),
                                     'change', min(p.change_minor), 'currency', min(p.currency_code),
                                     'order', min(p.order_id::text), 'shift', min(p.shift_id::text),
                                     'drawer', min(p.cash_drawer_session_id::text))
             from public.payments p where p.device_id = pg_temp.zc_id('device-1')
                                      and p.local_operation_id = pg_temp.zc_lop('r1')),
          jsonb_build_object('n', 1, 'method', 'card', 'status', 'completed', 'amount', 1234, 'tendered', 1234,
                             'change', 0, 'currency', 'ILS', 'order', pg_temp.rr_ord('r1')::text,
                             'shift', (pg_temp.rr_att('r1')).shift_id::text,
                             'drawer', (pg_temp.rr_att('r1')).cash_drawer_session_id::text),
          'RR-043 item 3: exactly one completed card payment with the attempt''s amount, currency, order, frozen shift and frozen drawer');
select is(jsonb_build_object('recorded', pg_temp.rr_derive('r1') -> 'recorded',
                             'classification', pg_temp.rr_derive('r1') ->> 'classification',
                             'payment_id_matches', (pg_temp.rr_derive('r1') ->> 'payment_id') = (pg_temp.rr_res('p-r1') ->> 'payment_id'),
                             'claim_active', app.card_order_claim_active(pg_temp.zc_org(), pg_temp.rr_ord('r1')),
                             'card_sync_audit', pg_temp.rr_delta('r1', 'card_attempt.%') || pg_temp.rr_delta('r1', 'sync.%')),
          jsonb_build_object('recorded', true, 'classification', 'recorded', 'payment_id_matches', true,
                             'claim_active', false, 'card_sync_audit', '{}'::jsonb),
          'RR-044 item 3: the attempt derives recorded with that payment_id (strict join) and its claim ends; no sync / card_attempt audit');
set local role authenticated;
select pg_temp.rr_push('p-r1-again', 1, jsonb_build_array(pg_temp.rr_leg('r1')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-r1-again') ->> 'status',
                             'replay', pg_temp.rr_res('p-r1-again') -> 'idempotency_replay',
                             'same_payment', (pg_temp.rr_res('p-r1-again') ->> 'payment_id') = (pg_temp.rr_res('p-r1') ->> 'payment_id'),
                             'payments', pg_temp.rr_pay_n('r1')),
          jsonb_build_object('status', 'applied', 'replay', true, 'same_payment', true, 'payments', 1),
          'RR-045 item 3: a resend of the same leg replays applied (idempotency_replay true) with no second payment');

update public.orders o set revision = o.revision + 1 where o.id in (pg_temp.rr_ord('r2'), pg_temp.rr_ord('r3'));
insert into _zc_r select 'op-r3', pg_temp.zc_pay_op(pg_temp.zc_lop('r3'), pg_temp.rr_ord('r3'), 'card', 1234,
  jsonb_build_object('payload', jsonb_build_object('order_id', pg_temp.rr_ord('r3'), 'tender_type', 'card',
                                                   'amount_tendered_minor', 1234, 'expected_revision', 1)));
select pg_temp.rr_snap('r23');
set local role authenticated;
select pg_temp.rr_push('p-r2', 1, jsonb_build_array(pg_temp.rr_leg('r2')));
select pg_temp.rr_push('p-r3', 1, jsonb_build_array(pg_temp.rr_r('op-r3')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-r2') ->> 'status', 'payments', pg_temp.rr_pay_n('r2'),
                             'recorded', pg_temp.rr_derive('r2') -> 'recorded',
                             'order_revision', (select o.revision from public.orders o where o.id = pg_temp.rr_ord('r2'))),
          jsonb_build_object('status', 'applied', 'payments', 1, 'recorded', true, 'order_revision', 3),
          'RR-046 item 3: the canonical leg still records after orders.revision moved (owner bump 1 -> 2; the leg omits expected_revision)');
select is(jsonb_build_object('result', pg_temp.rr_res('p-r3'), 'so', pg_temp.rr_so_state('r3') - 'retry_count',
                             'payments', pg_temp.rr_pay_n('r3'), 'state', (pg_temp.rr_att('r3')).state,
                             'recorded', pg_temp.rr_derive('r3') -> 'recorded'),
          jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('r3'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'conflict',
                                         'sqlstate', '40001', 'status', 'conflict', 'idempotency_replay', false),
                             'so', jsonb_build_object('status', 'conflict', 'class', 'conflict', 'code', '40001',
                                     'result', jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', '40001'),
                                     'reason', null::text),
                             'payments', 0, 'state', 'approved', 'recorded', false),
          'RR-047 item 3: a leg carrying a stale expected_revision is memoized conflict (record_payment''s own 40001, not transient) and records nothing');
select pg_temp.rr_snap('r3r');
set local role authenticated;
select pg_temp.rr_push('p-r3-resume', 2, jsonb_build_array(pg_temp.rr_r('op-r3') || '{"recording_resume": 0}'::jsonb));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-r3-resume'), 'state', pg_temp.rr_resume_state('r3'),
                             'audit', pg_temp.rr_delta('r3r')),
          jsonb_build_object('result', jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', '40001',
                                         'local_operation_id', pg_temp.zc_lop('r3'), 'operation_type', 'payment.create',
                                         'status', 'conflict', 'idempotency_replay', true),
                             'state', jsonb_build_object('so', 'conflict', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', '{}'::jsonb),
          'RR-048 item 3: that conflict row is never reopened: a manager resend with recording_resume 0 replays the stored conflict (no resume_denied, count 0, no audit, no payment)');

-- Item 6 on the same shift: foreign row, no sync row, raw message, recorded.
select pg_temp.rr_snap('r3m');
set local role service_role;
insert into _zc_r select 'm-r3', pg_temp.rr_markrec('r3', 1, 'conflict');
reset role;
select is(jsonb_build_object('stored', (pg_temp.rr_att('r3')).refusal_code,
                             'refused_at', (pg_temp.rr_att('r3')).recording_refused_at is not null,
                             'envelope', pg_temp.rr_r('m-r3') ->> 'refusal_code',
                             'classification', pg_temp.rr_r('m-r3') ->> 'classification',
                             'recoverable', pg_temp.rr_r('m-r3') -> 'recoverable', 'audit', pg_temp.rr_delta('r3m')),
          jsonb_build_object('stored', 'nonrecoverable_refusal', 'refused_at', true, 'envelope', 'nonrecoverable_refusal',
                             'classification', 'orphan_approved', 'recoverable', false,
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-049 item 6: card_attempt_mark_recording_result on a foreign row (the leg carried an extra expected_revision key) stores nonrecoverable_refusal (the client hint conflict is not stored), orphan_approved, one recording_refused audit');
select pg_temp.rr_snap('r4m');
set local role service_role;
insert into _zc_r select 'm-r4', pg_temp.rr_markrec('r4', 1, 'permission_denied');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_r('m-r4')), 'stored', (pg_temp.rr_att('r4')).refusal_code,
                             'refused_at', (pg_temp.rr_att('r4')).recording_refused_at, 'audit', pg_temp.rr_delta('r4m'),
                             'denied_detail', (select jsonb_agg(e.new_values) from public.audit_events e
                                                where e.organization_id = pg_temp.zc_org() and e.action = 'card_attempt.denied')),
          jsonb_build_object('result', jsonb_build_object('ok', false, 'error', 'precondition_failed',
                                         'detail', 'no_recording_attempt', 'attempt_id', pg_temp.zc_lop('r4'),
                                         'attempt_state', 'approved', 'server_ts?', true),
                             'stored', null::text, 'refused_at', null::timestamptz,
                             'audit', jsonb_build_object('card_attempt.denied', 1),
                             'denied_detail', '[{"denied_reason": "no_recording_attempt"}]'::jsonb),
          'RR-050 item 6: with no sync row for the identity it answers precondition_failed / no_recording_attempt, stores nothing and writes one card_attempt.denied audit (no recording_refused)');
update public.orders o set status = 'cancelled' where o.id = pg_temp.rr_ord('r5');
set local role authenticated;
select pg_temp.rr_push('p-r5', 1, jsonb_build_array(pg_temp.rr_leg('r5')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-r5'),
                             'raw_reason', (pg_temp.rr_so('r5')).rejection_reason like 'record_payment: order status cancelled%'),
          jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('r5'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                         'sqlstate', '42501', 'detail', null::text, 'status', 'rejected',
                                         'idempotency_replay', false),
                             'raw_reason', true),
          'RR-051 setup: the canonical leg on a cancelled order is memoized rejected with record_payment''s raw message as rejection_reason (42501, not transient)');
select pg_temp.rr_snap('r5m');
set local role service_role;
insert into _zc_r select 'm-r5', pg_temp.rr_markrec('r5', 1, 'order_not_chargeable');
reset role;
select is(jsonb_build_object('stored', (pg_temp.rr_att('r5')).refusal_code, 'envelope', pg_temp.rr_r('m-r5') ->> 'refusal_code',
                             'audit', pg_temp.rr_delta('r5m')),
          jsonb_build_object('stored', 'nonrecoverable_refusal', 'envelope', 'nonrecoverable_refusal',
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-052 item 6: a raw-message rejection_reason of the own canonical leg normalizes to nonrecoverable_refusal (the hint order_not_chargeable is not stored)');
select pg_temp.rr_snap('r1m');
set local role service_role;
insert into _zc_r select 'm-r1', pg_temp.rr_markrec('r1', 1, 'conflict');
reset role;
select is(jsonb_build_object('classification', pg_temp.rr_r('m-r1') ->> 'classification',
                             'recorded', pg_temp.rr_r('m-r1') -> 'recorded',
                             'payment_id', pg_temp.rr_r('m-r1') ->> 'payment_id',
                             'stored', (pg_temp.rr_att('r1')).refusal_code,
                             'refused_at', (pg_temp.rr_att('r1')).recording_refused_at, 'audit', pg_temp.rr_delta('r1m')),
          jsonb_build_object('classification', 'recorded', 'recorded', true,
                             'payment_id', pg_temp.rr_res('p-r1') ->> 'payment_id', 'stored', null::text,
                             'refused_at', null::timestamptz, 'audit', '{}'::jsonb),
          'RR-053 item 6: on a recorded attempt it answers the recorded envelope (payment_id) with no write and no audit');
set local role authenticated;
select pg_temp.rr_push('p-r6-k', 4, jsonb_build_array(pg_temp.rr_leg('r6')));
reset role;
update public.sync_operations so set status = 'dead' where so.id = (pg_temp.rr_so('r6')).id;
select pg_temp.rr_snap('r6m');
set local role service_role;
insert into _zc_r select 'm-r6', pg_temp.rr_markrec('r6', 1, 'permission_denied');
reset role;
select is(jsonb_build_object('stored', (pg_temp.rr_att('r6')).refusal_code, 'classification', pg_temp.rr_r('m-r6') ->> 'classification',
                             'audit', pg_temp.rr_delta('r6m')),
          jsonb_build_object('stored', 'nonrecoverable_refusal', 'classification', 'orphan_approved',
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-054 item 6: an own-leg row in status dead (seeded as owner) stores nonrecoverable_refusal, never its rejection_reason');

-- ===========================================================================
-- F. Item 5: shift.close of the frozen shift, refused and allowed.
-- ===========================================================================
-- F-a: sent, unknown (refused) -> evidence free of the unknown attempt (allowed).
insert into _zc_r select 'shift-s3', to_jsonb(pg_temp.rr_new_shift('s3'));
set local role service_role;
insert into _zc_r select 'c-fa1', pg_temp.rr_claim('fa1', 'fa1');
reset role;
select pg_temp.rr_snap('fa');
set local role authenticated;
select pg_temp.rr_push('p-fa-sent', 2, jsonb_build_array(pg_temp.rr_close_op('fa-c1', pg_temp.zc_id('rr-shift-s3'))));
select pg_temp.rr_push('p-fa-d2', 3, jsonb_build_array(pg_temp.rr_close_op('fa-c2', pg_temp.zc_id('rr-shift-s3'))));
reset role;
select is(pg_temp.rr_ts(pg_temp.rr_res('p-fa-sent')), pg_temp.rr_close_refusal('fa-c1', 's3'),
          'RR-055 item 5: shift.close (single op) of d1''s shift is refused card_payment_in_progress (error, server_ts, shift_id only; no attempt fact) while a LIVE attempt frozen to it is sent');
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-fa-d2')), 'so_d2', (pg_temp.rr_so('fa-c2', 2)).status),
          jsonb_build_object('result', pg_temp.rr_close_refusal('fa-c2', 's3'), 'so_d2', 'rejected'),
          'RR-056 item 5: the same close pushed from d2 by its manager is refused too (the predicate keys on the frozen shift, whatever device pushes)');
select is(jsonb_build_object('shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s3')),
                             'so', (pg_temp.rr_so('fa-c1')).status, 'reason', (pg_temp.rr_so('fa-c1')).rejection_reason,
                             'audit', pg_temp.rr_delta('fa')),
          jsonb_build_object('shift', 'open', 'so', 'rejected', 'reason', 'card_payment_in_progress',
                             'audit', jsonb_build_object('sync.operation_rejected', 2)),
          'RR-057 item 5: a refused close changes nothing (shift still open); each refusal is a rejected sync row with one sync.operation_rejected audit');
set local role service_role;
insert into _zc_r select 'f-fa1-u', pg_temp.rr_fin('fa1', 'commit', 'unknown');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-fa-unknown', 2, jsonb_build_array(pg_temp.rr_close_op('fa-c3', pg_temp.zc_id('rr-shift-s3'))));
reset role;
select is(jsonb_build_object('state', (pg_temp.rr_att('fa1')).state, 'result', pg_temp.rr_ts(pg_temp.rr_res('p-fa-unknown'))),
          jsonb_build_object('state', 'unknown', 'result', pg_temp.rr_close_refusal('fa-c3', 's3')),
          'RR-058 item 5: refused card_payment_in_progress while the frozen attempt is unknown');
set local role service_role;
insert into _zc_r select 'f-fa1-l', pg_temp.rr_fin('fa1', 'lookup', 'failed', '{}', 'operator');
insert into _zc_r select 'free-fa1', pg_temp.rr_free('fa1');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-fa-freed', 2, jsonb_build_array(pg_temp.rr_close_op('fa-c4', pg_temp.zc_id('rr-shift-s3'))));
reset role;
select is(jsonb_build_object('attempt', jsonb_build_object('state', (pg_temp.rr_att('fa1')).state,
                                          'freed', (pg_temp.rr_att('fa1')).order_freed_at is not null,
                                          'cme', (pg_temp.rr_att('fa1')).charge_may_exist),
                             'ok', pg_temp.rr_res('p-fa-freed') -> 'ok', 'status', pg_temp.rr_res('p-fa-freed') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s3'))),
          jsonb_build_object('attempt', jsonb_build_object('state', 'unknown', 'freed', true, 'cme', false),
                             'ok', true, 'status', 'applied', 'shift', 'closed'),
          'RR-059 item 5: after an evidence free of the unknown attempt without anomaly the close is allowed (applied, shift closed)');

-- F-b: released (refused) -> declined (allowed).
insert into _zc_r select 'shift-s4', to_jsonb(pg_temp.rr_new_shift('s4'));
set local role service_role;
insert into _zc_r select 'c-fb1', pg_temp.rr_claim('fb1', 'fb1');
insert into _zc_r select 'f-fb1-rel', pg_temp.rr_fin('fb1', 'release', 'released');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-fb-rel', 2, jsonb_build_array(pg_temp.rr_close_op('fb-c1', pg_temp.zc_id('rr-shift-s4'))));
reset role;
select is(jsonb_build_object('state', (pg_temp.rr_att('fb1')).state, 'result', pg_temp.rr_ts(pg_temp.rr_res('p-fb-rel'))),
          jsonb_build_object('state', 'released', 'result', pg_temp.rr_close_refusal('fb-c1', 's4')),
          'RR-060 item 5: refused card_payment_in_progress while the frozen attempt is released');
set local role service_role;
insert into _zc_r select 'f-fb1-dec', pg_temp.rr_fin('fb1', 'lookup', 'declined', '{"approval_type": "declined"}', 'operator');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-fb-dec', 2, jsonb_build_array(pg_temp.rr_close_op('fb-c2', pg_temp.zc_id('rr-shift-s4'))));
reset role;
select is(jsonb_build_object('state', (pg_temp.rr_att('fb1')).state, 'status', pg_temp.rr_res('p-fb-dec') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s4'))),
          jsonb_build_object('state', 'declined', 'status', 'applied', 'shift', 'closed'),
          'RR-061 item 5: after the attempt is declined the close is allowed (applied, shift closed)');

-- F-c: anomalous (refused) -> provider_voided resolution (allowed).
insert into _zc_r select 'shift-s5', to_jsonb(pg_temp.rr_new_shift('s5'));
set local role service_role;
insert into _zc_r select 'c-fc1', pg_temp.rr_claim('fc1', 'fc1');
insert into _zc_r select 'f-fc1-an', pg_temp.rr_fin('fc1', 'commit', 'anomaly', '{"anomaly_code": "partial_refund"}');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-fc-an', 2, jsonb_build_array(pg_temp.rr_close_op('fc-c1', pg_temp.zc_id('rr-shift-s5'))));
reset role;
select is(jsonb_build_object('cme', (pg_temp.rr_att('fc1')).charge_may_exist, 'result', pg_temp.rr_ts(pg_temp.rr_res('p-fc-an'))),
          jsonb_build_object('cme', true, 'result', pg_temp.rr_close_refusal('fc-c1', 's5')),
          'RR-062 item 5: refused card_payment_in_progress while the frozen attempt is an unresolved provider anomaly');
insert into _zc_r select 'res-fc1', pg_temp.rr_resolve('fc1', 'provider_voided');
set local role authenticated;
select pg_temp.rr_push('p-fc-res', 2, jsonb_build_array(pg_temp.rr_close_op('fc-c2', pg_temp.zc_id('rr-shift-s5'))));
reset role;
select is(jsonb_build_object('resolution', (pg_temp.rr_att('fc1')).resolution, 'status', pg_temp.rr_res('p-fc-res') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s5'))),
          jsonb_build_object('resolution', 'provider_voided', 'status', 'applied', 'shift', 'closed'),
          'RR-063 item 5: after a provider_voided resolution the close is allowed (applied, shift closed)');

-- F-d: approved-unrecorded (refused) -> recorded (allowed).
insert into _zc_r select 'shift-s6', to_jsonb(pg_temp.rr_new_shift('s6'));
set local role service_role;
insert into _zc_r select 'c-fd1', pg_temp.rr_claim('fd1', 'fd1');
insert into _zc_r select 'f-fd1', pg_temp.rr_fin('fd1', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
set local role authenticated;
select pg_temp.rr_push('p-fd-ap', 2, jsonb_build_array(pg_temp.rr_close_op('fd-c1', pg_temp.zc_id('rr-shift-s6'))));
reset role;
select is(jsonb_build_object('classification', pg_temp.rr_derive('fd1') ->> 'classification',
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-fd-ap'))),
          jsonb_build_object('classification', 'approved_unrecorded', 'result', pg_temp.rr_close_refusal('fd-c1', 's6')),
          'RR-064 item 5: refused card_payment_in_progress while the frozen attempt is approved and unrecorded');
set local role authenticated;
select pg_temp.rr_push('p-fd-leg', 1, jsonb_build_array(pg_temp.rr_leg('fd1')));
select pg_temp.rr_push('p-fd-rec', 2, jsonb_build_array(pg_temp.rr_close_op('fd-c2', pg_temp.zc_id('rr-shift-s6'))));
reset role;
select is(jsonb_build_object('leg', pg_temp.rr_res('p-fd-leg') ->> 'status', 'classification', pg_temp.rr_derive('fd1') ->> 'classification',
                             'status', pg_temp.rr_res('p-fd-rec') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s6'))),
          jsonb_build_object('leg', 'applied', 'classification', 'recorded', 'status', 'applied', 'shift', 'closed'),
          'RR-065 item 5: once the approval is recorded the close is allowed (applied, shift closed)');

-- F-e: orphan_approved (refused) -> provider_refunded resolution (allowed).
insert into _zc_r select 'shift-s7', to_jsonb(pg_temp.rr_new_shift('s7'));
set local role service_role;
insert into _zc_r select 'c-fe1', pg_temp.rr_claim('fe1', 'fe1');
insert into _zc_r select 'f-fe1', pg_temp.rr_fin('fe1', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
update public.orders o set grand_total_minor = 1500, subtotal_minor = 1500 where o.id = pg_temp.rr_ord('fe1');
set local role authenticated;
select pg_temp.rr_push('p-fe-orph', 2, jsonb_build_array(pg_temp.rr_close_op('fe-c1', pg_temp.zc_id('rr-shift-s7'))));
reset role;
select is(jsonb_build_object('classification', pg_temp.rr_derive('fe1') ->> 'classification', 'reason', pg_temp.rr_derive('fe1') ->> 'reason',
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-fe-orph'))),
          jsonb_build_object('classification', 'orphan_approved', 'reason', 'amount_mismatch',
                             'result', pg_temp.rr_close_refusal('fe-c1', 's7')),
          'RR-066 item 5: refused card_payment_in_progress while the frozen attempt is orphan_approved (amount_mismatch)');
insert into _zc_r select 'res-fe1', pg_temp.rr_resolve('fe1', 'provider_refunded');
set local role authenticated;
select pg_temp.rr_push('p-fe-res', 2, jsonb_build_array(pg_temp.rr_close_op('fe-c2', pg_temp.zc_id('rr-shift-s7'))));
reset role;
select is(jsonb_build_object('resolution', (pg_temp.rr_att('fe1')).resolution, 'status', pg_temp.rr_res('p-fe-res') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s7'))),
          jsonb_build_object('resolution', 'provider_refunded', 'status', 'applied', 'shift', 'closed'),
          'RR-067 item 5: after a provider_refunded resolution the close is allowed (applied, shift closed)');

-- F-f: an order_freed orphan and an anomaly found after a free (refused) -> resolved (allowed).
insert into _zc_r select 'shift-s8', to_jsonb(pg_temp.rr_new_shift('s8'));
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['ff1', 'ff2']) l;
insert into _zc_r select 'f-' || l || '-u', pg_temp.rr_fin(l, 'commit', 'unknown') from unnest(array['ff1', 'ff2']) l;
insert into _zc_r select 'f-' || l || '-l', pg_temp.rr_fin(l, 'lookup', 'failed', '{}', 'operator') from unnest(array['ff1', 'ff2']) l;
insert into _zc_r select 'free-' || l, pg_temp.rr_free(l) from unnest(array['ff1', 'ff2']) l;
insert into _zc_r select 'f-ff1-ap', pg_temp.rr_fin('ff1', 'lookup', 'approved',
  '{"provider_status_code": "ok1", "provider_amount": "12.34", "provider_currency": "ILS", "error_flag": false}', 'operator');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-ff-orph', 2, jsonb_build_array(pg_temp.rr_close_op('ff-c1', pg_temp.zc_id('rr-shift-s8'))));
reset role;
select is(jsonb_build_object('ff1', jsonb_build_object('state', (pg_temp.rr_att('ff1')).state,
                                      'classification', pg_temp.rr_derive('ff1') ->> 'classification',
                                      'reason', pg_temp.rr_derive('ff1') ->> 'reason'),
                             'ff2_freed_no_anomaly', jsonb_build_object('state', (pg_temp.rr_att('ff2')).state,
                                      'freed', (pg_temp.rr_att('ff2')).order_freed_at is not null,
                                      'cme', (pg_temp.rr_att('ff2')).charge_may_exist),
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-ff-orph'))),
          jsonb_build_object('ff1', jsonb_build_object('state', 'approved', 'classification', 'orphan_approved',
                                                      'reason', 'order_freed'),
                             'ff2_freed_no_anomaly', jsonb_build_object('state', 'unknown', 'freed', true, 'cme', false),
                             'result', pg_temp.rr_close_refusal('ff-c1', 's8')),
          'RR-068 item 5: refused card_payment_in_progress while the frozen attempt is an order_freed orphan (approval found after the evidence free)');
insert into _zc_r select 'res-ff1', pg_temp.rr_resolve('ff1', 'provider_voided');
set local role service_role;
insert into _zc_r select 'f-ff2-an', pg_temp.rr_fin('ff2', 'lookup', 'anomaly', '{"anomaly_code": "refunded"}', 'operator');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-ff-anom', 2, jsonb_build_array(pg_temp.rr_close_op('ff-c2', pg_temp.zc_id('rr-shift-s8'))));
reset role;
select is(jsonb_build_object('ff1_resolution', (pg_temp.rr_att('ff1')).resolution, 'ff2_cme', (pg_temp.rr_att('ff2')).charge_may_exist,
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-ff-anom'))),
          jsonb_build_object('ff1_resolution', 'provider_voided', 'ff2_cme', true,
                             'result', pg_temp.rr_close_refusal('ff-c2', 's8')),
          'RR-069 item 5: an anomaly found after an evidence free blocks the frozen shift''s close (refused card_payment_in_progress)');
insert into _zc_r select 'res-ff2', pg_temp.rr_resolve('ff2', 'provider_refunded');
set local role authenticated;
select pg_temp.rr_push('p-ff-res', 2, jsonb_build_array(pg_temp.rr_close_op('ff-c3', pg_temp.zc_id('rr-shift-s8'))));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-ff-res') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s8'))),
          jsonb_build_object('status', 'applied', 'shift', 'closed'),
          'RR-070 item 5: once both are resolved (provider_voided / provider_refunded) the close is allowed (applied, shift closed)');

-- ===========================================================================
-- G. Items 6 and 7: the recording result and the D-054 Resume.
-- ===========================================================================
insert into _zc_r select 'shift-s9', to_jsonb(pg_temp.rr_new_shift('s9'));
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l)
  from unnest(array['rs1', 'rs2', 'rs3', 'rs4', 'rs5', 'rs7', 'rs8', 'rs9', 'rs11', 'rs12', 'rs13', 'rs14']) l;
insert into _zc_r select 'f-' || l, pg_temp.rr_fin(l, 'commit', 'approved', pg_temp.zc_approved_fields())
  from unnest(array['rs1', 'rs2', 'rs3', 'rs4', 'rs5', 'rs7', 'rs8', 'rs9', 'rs11', 'rs12', 'rs13', 'rs14']) l;
reset role;
-- RS1: the own canonical leg under the kitchen PIN (staff 4) -> permission_denied, then mark, then Resume.
select pg_temp.rr_snap('rs1k');
set local role authenticated;
select pg_temp.rr_push('p-rs1-k', 4, jsonb_build_array(pg_temp.rr_leg('rs1')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs1-k')), 'so', (pg_temp.rr_so('rs1')).status,
                             'reason', (pg_temp.rr_so('rs1')).rejection_reason, 'audit', pg_temp.rr_delta('rs1k')),
          jsonb_build_object('result', pg_temp.rr_refusal('rs1', 'rs1', 'permission_denied'), 'so', 'rejected',
                             'reason', 'permission_denied',
                             'audit', jsonb_build_object('payment.denied', 1, 'sync.operation_rejected', 1)),
          'RR-071 item 6: the own canonical leg pushed under the kitchen PIN (staff 4) is answered by record_payment''s permission_denied (the guard defers a certainly-denied role) and memoized rejected');
select pg_temp.rr_snap('rs1m');
set local role service_role;
insert into _zc_r select 'm-rs1', pg_temp.rr_markrec('rs1', 1, 'conflict');
reset role;
select is(pg_temp.rr_ts(pg_temp.rr_r('m-rs1')),
          jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('rs1'), 'state', 'approved',
                             'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                             'refusal_code', 'permission_denied', 'recoverable', true, 'resume_count', 0,
                             'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
          'RR-072 item 6: card_attempt_mark_recording_result derives permission_denied from the sync row (not the client hint conflict): approved_unrecorded, recoverable, resume_count 0');
select is(jsonb_build_object('stored', (pg_temp.rr_att('rs1')).refusal_code,
                             'refused_at', (pg_temp.rr_att('rs1')).recording_refused_at is not null,
                             'reason', pg_temp.rr_derive('rs1') ->> 'reason', 'audit', pg_temp.rr_delta('rs1m'),
                             'audit_detail', (select e.new_values from public.audit_events e
                                               where e.organization_id = pg_temp.zc_org()
                                                 and e.action = 'card_attempt.recording_refused'
                                                 and e.new_values ->> 'refusal_code' = 'permission_denied')),
          jsonb_build_object('stored', 'permission_denied', 'refused_at', true, 'reason', 'recording_refused',
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1),
                             'audit_detail', jsonb_build_object('refusal_code', 'permission_denied')),
          'RR-073 item 6: it stores refusal_code permission_denied + recording_refused_at and writes exactly one card_attempt.recording_refused audit');
insert into _zc_r select 'so-rs1-before', jsonb_build_object('id', (pg_temp.rr_so('rs1')).id,
                                                              'retry_count', (pg_temp.rr_so('rs1')).retry_count);
insert into _zc_r select 'att-rs1-before', jsonb_build_object('refusal_code', (pg_temp.rr_att('rs1')).refusal_code,
                                                               'refused_at', (pg_temp.rr_att('rs1')).recording_refused_at);
select pg_temp.rr_snap('rs1r');
set local role authenticated;
select pg_temp.rr_push('p-rs1-r', 2, jsonb_build_array(pg_temp.rr_leg('rs1', 'rs1', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('ok', pg_temp.rr_res('p-rs1-r') -> 'ok', 'status', pg_temp.rr_res('p-rs1-r') ->> 'status',
                             'replay', pg_temp.rr_res('p-rs1-r') -> 'idempotency_replay',
                             'same_row', (pg_temp.rr_so('rs1')).id = (pg_temp.rr_r('so-rs1-before') ->> 'id')::uuid,
                             'so', (pg_temp.rr_so('rs1')).status,
                             'cleared', jsonb_build_object('reason', (pg_temp.rr_so('rs1')).rejection_reason,
                                                           'code', (pg_temp.rr_so('rs1')).last_error_code,
                                                           'class', (pg_temp.rr_so('rs1')).last_error_class)),
          jsonb_build_object('ok', true, 'status', 'applied', 'replay', false, 'same_row', true, 'so', 'applied',
                             'cleared', jsonb_build_object('reason', null::text, 'code', null::text, 'class', null::text)),
          'RR-074 item 7: a manager (staff 2 on d1) resending the SAME leg with top-level recording_resume = 0 re-dispatches the same sync row once and it is applied (stored rejection fields cleared)');
select is((pg_temp.rr_so('rs1')).retry_count, (pg_temp.rr_r('so-rs1-before') ->> 'retry_count')::integer + 1,
          'RR-075 item 7 (packet section 11 item 11): the authorized reopen is dispatched through the existing adopt path, which bumps the sync row''s retry_count by exactly one');
select is((select jsonb_build_object('n', count(*), 'taken_by', min(p.taken_by_employee_profile_id::text),
                                     'membership', min(p.resolved_membership_id::text), 'method', min(p.method),
                                     'amount', min(p.amount_minor), 'shift', min(p.shift_id::text),
                                     'drawer', min(p.cash_drawer_session_id::text))
             from public.payments p where p.device_id = pg_temp.zc_id('device-1')
                                      and p.local_operation_id = pg_temp.zc_lop('rs1')),
          jsonb_build_object('n', 1, 'taken_by', pg_temp.zc_id('employee-2')::text,
                             'membership', pg_temp.zc_id('membership-2')::text, 'method', 'card', 'amount', 1234,
                             'shift', pg_temp.zc_id('rr-shift-s9')::text, 'drawer', pg_temp.zc_id('rr-drawer-s9')::text),
          'RR-076 item 7: exactly one card payment is recorded in the frozen shift / drawer, the manager becoming the payments actor');
select is(jsonb_build_object('resume_count', (pg_temp.rr_att('rs1')).recording_resume_count,
                             'refusal_history', (select jsonb_agg(h - 'refused_at') from jsonb_array_elements((pg_temp.rr_att('rs1')).recording_refusal_history) h),
                             'refusal_history_ts', (select bool_and(h ? 'refused_at' and h -> 'refused_at' <> 'null'::jsonb)
                                                      from jsonb_array_elements((pg_temp.rr_att('rs1')).recording_refusal_history) h),
                             'resume_history', (select jsonb_agg(h - 'at') from jsonb_array_elements((pg_temp.rr_att('rs1')).recording_resume_history) h),
                             'resume_history_ts', (select bool_and(h ? 'at' and h -> 'at' <> 'null'::jsonb)
                                                     from jsonb_array_elements((pg_temp.rr_att('rs1')).recording_resume_history) h),
                             'initiator', (pg_temp.rr_att('rs1')).initiated_by_employee_profile_id,
                             'refusal_code', (pg_temp.rr_att('rs1')).refusal_code,
                             'refused_at_kept', (pg_temp.rr_att('rs1')).recording_refused_at
                                                = (pg_temp.rr_r('att-rs1-before') ->> 'refused_at')::timestamptz,
                             'recorded', pg_temp.rr_derive('rs1') -> 'recorded'),
          jsonb_build_object('resume_count', 1,
                             'refusal_history', jsonb_build_array(jsonb_build_object('refusal_code', 'permission_denied')),
                             'refusal_history_ts', true,
                             'resume_history', jsonb_build_array(jsonb_build_object(
                                 'employee_profile_id', pg_temp.zc_id('employee-2'),
                                 'membership_id', pg_temp.zc_id('membership-2'), 'resume_count', 0)),
                             'resume_history_ts', true,
                             'initiator', pg_temp.zc_id('employee-1'), 'refusal_code', 'permission_denied',
                             'refused_at_kept', true, 'recorded', true),
          'RR-077 item 7 (review fix 6): recording_resume_count 1, one recording_refusal_history entry (permission_denied) and one recording_resume_history entry (the manager, count acted on 0); the initiator is kept; the Resume guard no longer clears the attempt''s refusal: refusal_code stays permission_denied and recording_refused_at keeps its pre-Resume value; the attempt is recorded');
select is(jsonb_build_object('card_sync_audit', pg_temp.rr_delta('rs1r', 'card_attempt.%') || pg_temp.rr_delta('rs1r', 'sync.%'),
                             'detail', (select jsonb_build_object('attempt_state', e.new_values ->> 'attempt_state',
                                                 'prior_refusal_code', e.new_values ->> 'prior_refusal_code',
                                                 'resume_count', e.new_values -> 'resume_count',
                                                 'outcome', e.new_values ->> 'outcome',
                                                 'denied_reason', e.new_values -> 'denied_reason')
                                          from public.audit_events e
                                         where e.organization_id = pg_temp.zc_org()
                                           and e.action = 'card_attempt.recording_resume_requested'
                                           and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('rs1'))),
          jsonb_build_object('card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1),
                             'detail', jsonb_build_object('attempt_state', 'approved', 'prior_refusal_code', 'permission_denied',
                                         'resume_count', 0, 'outcome', 'dispatched', 'denied_reason', null)),
          'RR-078 item 7: the authorized dispatch writes exactly one card_attempt.recording_resume_requested audit (outcome dispatched, prior permission_denied, count 0) and no sync.* audit');

-- RS2: one recoverable, reported refusal shared by the D-054 refusal cases.
set local role authenticated;
select pg_temp.rr_push('p-rs2-k', 4, jsonb_build_array(pg_temp.rr_leg('rs2')));
reset role;
set local role service_role;
insert into _zc_r select 'm-rs2', pg_temp.rr_markrec('rs2');
reset role;
select is(jsonb_build_object('so', (pg_temp.rr_so('rs2')).status, 'stored', (pg_temp.rr_att('rs2')).refusal_code,
                             'recoverable', pg_temp.rr_derive('rs2') -> 'recoverable'),
          jsonb_build_object('so', 'rejected', 'stored', 'permission_denied', 'recoverable', true),
          'RR-079 setup: a second approved attempt holds a reported, recoverable permission_denied leg');
select pg_temp.rr_snap('rs2a');
set local role authenticated;
select pg_temp.rr_push('p-rs2-cashier', 1, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-cashier')), 'after', pg_temp.rr_resume_state('rs2'),
                             'audit', pg_temp.rr_delta('rs2a')),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', 'not_manager'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', '{}'::jsonb),
          'RR-080 item 7: a cashier''s Resume replays the stored rejection (idempotency_replay true) with resume_denied not_manager; nothing dispatched, count unchanged, no audit');
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-2');
select pg_temp.rr_snap('rs2b');
set local role authenticated;
select pg_temp.rr_push('p-rs2-revoked', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2', '{"recording_resume": 0}')));
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-2');
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-revoked')), 'after', pg_temp.rr_resume_state('rs2'),
                             'audit', pg_temp.rr_delta('rs2b')),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', 'actor_not_active'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', '{}'::jsonb),
          'RR-081 item 7: a manager whose membership is revoked gets resume_denied actor_not_active; nothing dispatched, no audit');
update public.employee_profiles ep set employment_status = 'suspended' where ep.id = pg_temp.zc_id('employee-2');
select pg_temp.rr_snap('rs2e');
set local role authenticated;
select pg_temp.rr_push('p-rs2-inactive', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2', '{"recording_resume": 0}')));
reset role;
update public.employee_profiles ep set employment_status = 'active' where ep.id = pg_temp.zc_id('employee-2');
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-inactive')), 'audit', pg_temp.rr_delta('rs2e'),
                             'resume_count', (pg_temp.rr_att('rs2')).recording_resume_count),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', 'actor_not_active'), 'audit', '{}'::jsonb,
                             'resume_count', 0),
          'RR-082 item 7: a manager with an inactive (suspended) employee profile gets actor_not_active; no audit');
update public.devices d set is_active = false where d.id = pg_temp.zc_id('device-1');
select pg_temp.rr_snap('rs2d');
set local role authenticated;
select pg_temp.rr_push('p-rs2-device', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2', '{"recording_resume": 0}')));
reset role;
update public.devices d set is_active = true where d.id = pg_temp.zc_id('device-1');
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-device')), 'after', pg_temp.rr_resume_state('rs2'),
                             'audit', pg_temp.rr_delta('rs2d'),
                             'audited', pg_temp.rr_resume_audits('rs2', 'refused', 'device_not_active')),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', 'device_not_active'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1), 'audited', 1),
          'RR-083 item 7: an active manager on a management-inactive device record gets device_not_active, audited once (refused)');
select pg_temp.rr_snap('rs2s');
set local role authenticated;
select pg_temp.rr_push('p-rs2-stale', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2', '{"recording_resume": 1}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-stale')), 'after', pg_temp.rr_resume_state('rs2'),
                             'audit', pg_temp.rr_delta('rs2s'),
                             'detail', (select jsonb_build_object('outcome', e.new_values ->> 'outcome',
                                                 'denied_reason', e.new_values ->> 'denied_reason',
                                                 'resume_count', e.new_values -> 'resume_count',
                                                 'prior_refusal_code', e.new_values ->> 'prior_refusal_code',
                                                 'attempt_state', e.new_values ->> 'attempt_state')
                                          from public.audit_events e
                                         where e.organization_id = pg_temp.zc_org()
                                           and e.action = 'card_attempt.recording_resume_requested'
                                           and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('rs2')
                                           and e.new_values ->> 'denied_reason' = 'resume_stale')),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', 'resume_stale'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1),
                             'detail', jsonb_build_object('outcome', 'refused', 'denied_reason', 'resume_stale',
                                         'resume_count', 0, 'prior_refusal_code', 'permission_denied',
                                         'attempt_state', 'approved')),
          'RR-084 item 7: recording_resume 1 against count 0 is resume_stale, audited once (outcome refused, denied_reason resume_stale); count unchanged');
select pg_temp.rr_snap('rs2s2');
set local role authenticated;
select pg_temp.rr_push('p-rs2-stale2', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2', '{"recording_resume": 1}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-stale2')), 'audit', pg_temp.rr_delta('rs2s2'),
                             'audited', pg_temp.rr_resume_audits('rs2', 'refused', 'resume_stale')),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', 'resume_stale'), 'audit', '{}'::jsonb, 'audited', 1),
          'RR-085 item 7: an identical repeat of the stale Resume answers the same and writes nothing new');
select pg_temp.rr_snap('rs2t');
set local role authenticated;
select pg_temp.rr_push('p-rs2-target', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2',
  jsonb_build_object('recording_resume', 0, 'target_id', pg_temp.zc_id('rr-other-target')))));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-target')), 'after', pg_temp.rr_resume_state('rs2'),
                             'audit', pg_temp.rr_delta('rs2t')),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', 'operation_mismatch'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-086 item 7 (M10): a resent target_id that differs from the stored one (value vs other value) is operation_mismatch, audited once');
select pg_temp.rr_snap('rs2c');
set local role authenticated;
select pg_temp.rr_push('p-rs2-ts', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2',
  '{"recording_resume": 0, "client_created_at": "2026-10-24T00:00:01Z"}')));
select pg_temp.rr_push('p-rs2-entity', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2',
  '{"recording_resume": 0, "target_entity": "payment"}')));
reset role;
select is(jsonb_build_object('ts', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-ts')), 'entity', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-entity')),
                             'after', pg_temp.rr_resume_state('rs2'), 'audit', pg_temp.rr_delta('rs2c'),
                             'audited', pg_temp.rr_resume_audits('rs2', 'refused', 'operation_mismatch')),
          jsonb_build_object('ts', pg_temp.rr_denied('rs2', 'rs2', 'operation_mismatch'),
                             'entity', pg_temp.rr_denied('rs2', 'rs2', 'operation_mismatch'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', '{}'::jsonb, 'audited', 1),
          'RR-087 item 7 (M10): a different client_created_at (and a different target_entity) is operation_mismatch; the same (attempt, count, reason) writes no second audit');
select pg_temp.rr_snap('rs2p');
set local role authenticated;
select pg_temp.rr_push('p-rs2-payload', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2',
  jsonb_build_object('recording_resume', 0, 'payload', jsonb_build_object('order_id', pg_temp.rr_ord('rs2'),
                     'tender_type', 'card', 'amount_tendered_minor', 1235)))));
select pg_temp.rr_push('p-rs2-plain', 2, jsonb_build_array(pg_temp.rr_leg('rs2')));
reset role;
select is(jsonb_build_object('payload', pg_temp.rr_res('p-rs2-payload'), 'plain', pg_temp.rr_ts(pg_temp.rr_res('p-rs2-plain')),
                             'after', pg_temp.rr_resume_state('rs2'), 'audit', pg_temp.rr_delta('rs2p')),
          jsonb_build_object('payload', jsonb_build_object('local_operation_id', pg_temp.zc_lop('rs2'),
                                          'operation_type', 'payment.create', 'ok', false, 'error', 'conflict',
                                          'detail', 'idempotency key already used for a different operation/payload',
                                          'status', 'conflict', 'idempotency_replay', false),
                             'plain', pg_temp.rr_denied('rs2', 'rs2', null),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('sync.operation_conflict', 1)),
          'RR-088 item 7: a payload change is the preamble''s conflict (sync.operation_conflict, no Resume evidence); a resend without recording_resume is the plain permanent replay');
select pg_temp.rr_snap('rsn');
set local role authenticated;
select pg_temp.rr_push('p-b2-resume', 2, jsonb_build_array(
  pg_temp.zc_pay_op(pg_temp.zc_lop('b2-card'), pg_temp.rr_ord('b2'), 'card', 1234, '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-b2-resume')), 'audit', pg_temp.rr_delta('rsn')),
          jsonb_build_object('result', pg_temp.rr_refusal('b2-card', 'b2', 'card_terminal_required')
                                         || '{"idempotency_replay": true}'::jsonb,
                             'audit', '{}'::jsonb),
          'RR-089 item 7: a rejected payment.create with no live attempt under its identity (the manual-card refusal) resent with recording_resume is replayed unchanged, no resume_denied, no audit');

-- RS3 (M10 null target): stored target_id NULL; null vs value refused, null vs null resumes.
set local role authenticated;
select pg_temp.rr_push('p-rs3-k', 4, jsonb_build_array(pg_temp.rr_leg('rs3') - 'target_id'));
reset role;
set local role service_role;
insert into _zc_r select 'm-rs3', pg_temp.rr_markrec('rs3');
reset role;
select pg_temp.rr_snap('rs3a');
set local role authenticated;
select pg_temp.rr_push('p-rs3-value', 2, jsonb_build_array(pg_temp.rr_leg('rs3', 'rs3', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('stored_target', (pg_temp.rr_so('rs3')).target_id, 'stored', (pg_temp.rr_att('rs3')).refusal_code,
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-rs3-value')), 'audit', pg_temp.rr_delta('rs3a')),
          jsonb_build_object('stored_target', null::uuid, 'stored', 'permission_denied',
                             'result', pg_temp.rr_denied('rs3', 'rs3', 'operation_mismatch'),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-090 item 7 (M10): stored target_id NULL vs a resent value is operation_mismatch (audited once)');
set local role authenticated;
select pg_temp.rr_push('p-rs3-null', 2, jsonb_build_array(pg_temp.rr_leg('rs3', 'rs3', '{"recording_resume": 0}') - 'target_id'));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-rs3-null') ->> 'status', 'payments', pg_temp.rr_pay_n('rs3'),
                             'resume_count', (pg_temp.rr_att('rs3')).recording_resume_count,
                             'recorded', pg_temp.rr_derive('rs3') -> 'recorded'),
          jsonb_build_object('status', 'applied', 'payments', 1, 'resume_count', 1, 'recorded', true),
          'RR-091 item 7 (M10): stored NULL and resent NULL target pass (IS NOT DISTINCT FROM): the Resume dispatches once and records');

-- RS4: the Resume limit (count seeded to 3 as owner).
set local role authenticated;
select pg_temp.rr_push('p-rs4-k', 4, jsonb_build_array(pg_temp.rr_leg('rs4')));
reset role;
set local role service_role;
insert into _zc_r select 'm-rs4', pg_temp.rr_markrec('rs4');
reset role;
update app.card_provider_attempts a set recording_resume_count = 3 where a.id = (pg_temp.rr_att('rs4')).id;
select pg_temp.rr_snap('rs4');
set local role authenticated;
select pg_temp.rr_push('p-rs4-3', 2, jsonb_build_array(pg_temp.rr_leg('rs4', 'rs4', '{"recording_resume": 3}')));
select pg_temp.rr_push('p-rs4-0', 2, jsonb_build_array(pg_temp.rr_leg('rs4', 'rs4', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('at3', pg_temp.rr_ts(pg_temp.rr_res('p-rs4-3')), 'at0', pg_temp.rr_ts(pg_temp.rr_res('p-rs4-0')),
                             'resume_count', (pg_temp.rr_att('rs4')).recording_resume_count,
                             'so', (pg_temp.rr_so('rs4')).status, 'payments', pg_temp.rr_pay_n('rs4'),
                             'audit', pg_temp.rr_delta('rs4'),
                             'audited', pg_temp.rr_resume_audits('rs4', 'refused', 'resume_limit')),
          jsonb_build_object('at3', pg_temp.rr_denied('rs4', 'rs4', 'resume_limit'),
                             'at0', pg_temp.rr_denied('rs4', 'rs4', 'resume_limit'),
                             'resume_count', 3, 'so', 'rejected', 'payments', 0,
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1), 'audited', 1),
          'RR-092 item 7: with the count already 3 (seeded) a Resume is resume_limit, also with a stale value (limit precedes resume_stale); audited once, nothing dispatched');
select is(jsonb_build_object('classification', pg_temp.rr_derive('rs4') ->> 'classification', 'reason', pg_temp.rr_derive('rs4') ->> 'reason',
                             'recoverable', pg_temp.rr_derive('rs4') -> 'recoverable'),
          jsonb_build_object('classification', 'orphan_approved', 'reason', 'resume_limit', 'recoverable', false),
          'RR-093 item 7: that attempt derives orphan_approved with reason resume_limit (not recoverable)');

-- RS5: the refusal not yet reported.
set local role authenticated;
select pg_temp.rr_push('p-rs5-k', 4, jsonb_build_array(pg_temp.rr_leg('rs5')));
reset role;
select pg_temp.rr_snap('rs5');
set local role authenticated;
select pg_temp.rr_push('p-rs5-r', 2, jsonb_build_array(pg_temp.rr_leg('rs5', 'rs5', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs5-r')), 'after', pg_temp.rr_resume_state('rs5'),
                             'stored', (pg_temp.rr_att('rs5')).refusal_code, 'audit', pg_temp.rr_delta('rs5')),
          jsonb_build_object('result', pg_temp.rr_denied('rs5', 'rs5', 'refusal_not_recorded'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'stored', null::text,
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-094 item 7: a Resume before the refusal was reported through card_attempt_mark_recording_result is refusal_not_recorded (audited once)');

-- RS7: a seeded memoized precondition_failed token with the frozen context intact resumes once.
set local role authenticated;
select pg_temp.rr_push('p-rs7-k', 4, jsonb_build_array(pg_temp.rr_leg('rs7')));
reset role;
update public.sync_operations so
   set rejection_reason = 'precondition_failed', last_error_code = '42501',
       result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', '42501', 'detail', 'precondition_failed')
 where so.id = (pg_temp.rr_so('rs7')).id;
set local role service_role;
insert into _zc_r select 'm-rs7', pg_temp.rr_markrec('rs7', 1, 'permission_denied');
reset role;
select pg_temp.rr_snap('rs7');
set local role authenticated;
select pg_temp.rr_push('p-rs7-r', 2, jsonb_build_array(pg_temp.rr_leg('rs7', 'rs7', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('stored_before', pg_temp.rr_r('m-rs7') ->> 'refusal_code',
                             'recoverable_before', pg_temp.rr_r('m-rs7') -> 'recoverable',
                             'status', pg_temp.rr_res('p-rs7-r') ->> 'status', 'payments', pg_temp.rr_pay_n('rs7'),
                             'resume_count', (pg_temp.rr_att('rs7')).recording_resume_count,
                             'refusal_history', (select jsonb_agg(h ->> 'refusal_code') from jsonb_array_elements((pg_temp.rr_att('rs7')).recording_refusal_history) h),
                             'dispatched', pg_temp.rr_resume_audits('rs7', 'dispatched')),
          jsonb_build_object('stored_before', 'precondition_failed', 'recoverable_before', true, 'status', 'applied',
                             'payments', 1, 'resume_count', 1, 'refusal_history', '["precondition_failed"]'::jsonb,
                             'dispatched', 1),
          'RR-095 item 7: a seeded memoized precondition_failed token (sync row rejection_reason / result detail, owner update) with the frozen shift and drawer intact is stored, then resumed once and recorded once');

-- RS9: the order total changed after the refusal.
set local role authenticated;
select pg_temp.rr_push('p-rs9-k', 4, jsonb_build_array(pg_temp.rr_leg('rs9')));
reset role;
set local role service_role;
insert into _zc_r select 'm-rs9', pg_temp.rr_markrec('rs9');
reset role;
update public.orders o set grand_total_minor = 1500, subtotal_minor = 1500 where o.id = pg_temp.rr_ord('rs9');
select pg_temp.rr_snap('rs9');
set local role authenticated;
select pg_temp.rr_push('p-rs9-r', 2, jsonb_build_array(pg_temp.rr_leg('rs9', 'rs9', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs9-r')), 'after', pg_temp.rr_resume_state('rs9'),
                             'audit', pg_temp.rr_delta('rs9')),
          jsonb_build_object('result', pg_temp.rr_denied('rs9', 'rs9', 'amount_mismatch'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-096 item 7: a Resume after the order total changed is amount_mismatch (audited once, nothing dispatched)');

-- RS11: a revoked_employee rejection (the cashier's membership revoked while the leg is pushed) resumes once.
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-1');
set local role authenticated;
select pg_temp.rr_push('p-rs11-k', 1, jsonb_build_array(pg_temp.rr_leg('rs11')));
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-1');
set local role service_role;
insert into _zc_r select 'm-rs11', pg_temp.rr_markrec('rs11', 1, 'rejected');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-rs11-k'), 'reason', (pg_temp.rr_so('rs11')).rejection_reason,
                             'stored', (pg_temp.rr_att('rs11')).refusal_code, 'recoverable', pg_temp.rr_r('m-rs11') -> 'recoverable'),
          jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('rs11'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                         'sqlstate', '42501', 'detail', 'revoked_employee', 'status', 'rejected',
                                         'idempotency_replay', false),
                             'reason', 'revoked_employee', 'stored', 'revoked_employee', 'recoverable', true),
          'RR-097 item 6: the own leg pushed while the cashier''s membership was revoked is memoized revoked_employee (the guard defers to record_payment''s raise) and the mark stores revoked_employee (recoverable)');
set local role authenticated;
select pg_temp.rr_push('p-rs11-r', 2, jsonb_build_array(pg_temp.rr_leg('rs11', 'rs11', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-rs11-r') ->> 'status', 'payments', pg_temp.rr_pay_n('rs11'),
                             'resume_count', (pg_temp.rr_att('rs11')).recording_resume_count,
                             'refusal_history', (select jsonb_agg(h ->> 'refusal_code') from jsonb_array_elements((pg_temp.rr_att('rs11')).recording_refusal_history) h),
                             'recorded', pg_temp.rr_derive('rs11') -> 'recorded'),
          jsonb_build_object('status', 'applied', 'payments', 1, 'resume_count', 1,
                             'refusal_history', '["revoked_employee"]'::jsonb, 'recorded', true),
          'RR-098 item 7: a revoked_employee rejection is resumed once by a manager and recorded once');

-- RS12-14: the other D-054 conditions, each after a reported recoverable refusal.
set local role authenticated;
select pg_temp.rr_push('p-' || l || '-k', 4, jsonb_build_array(pg_temp.rr_leg(l))) from unnest(array['rs12', 'rs13', 'rs14']) l;
reset role;
set local role service_role;
insert into _zc_r select 'm-' || l, pg_temp.rr_markrec(l) from unnest(array['rs12', 'rs13', 'rs14']) l;
reset role;
insert into public.payments (organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id, method, status,
    amount_minor, tendered_minor, change_minor, currency_code, local_operation_id)
values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.rr_ord('rs12x'), pg_temp.zc_id('device-1'),
    pg_temp.zc_id('employee-1'), pg_temp.zc_id('membership-1'), pg_temp.zc_id('rr-shift-s9'),
    pg_temp.zc_id('rr-drawer-s9'), 'cash', 'completed', 1234, 1234, 0, 'ILS', pg_temp.zc_lop('rs12'));
update public.orders o set status = 'cancelled' where o.id = pg_temp.rr_ord('rs13');
update public.orders o set grand_total_minor = 1500, subtotal_minor = 1500 where o.id = pg_temp.rr_ord('rs14');
insert into _zc_r select 'res-rs14', pg_temp.rr_resolve('rs14', 'provider_voided');
select pg_temp.rr_snap('rs1214');
set local role authenticated;
select pg_temp.rr_push('p-' || l || '-r', 2, jsonb_build_array(pg_temp.rr_leg(l, l, '{"recording_resume": 0}')))
  from unnest(array['rs12', 'rs13', 'rs14']) l;
reset role;
select is(jsonb_build_object('payment_exists', pg_temp.rr_ts(pg_temp.rr_res('p-rs12-r')),
                             'order_not_chargeable', pg_temp.rr_ts(pg_temp.rr_res('p-rs13-r')),
                             'claim_inactive', pg_temp.rr_ts(pg_temp.rr_res('p-rs14-r')),
                             'counts', (select jsonb_agg((pg_temp.rr_att(l)).recording_resume_count) from unnest(array['rs12', 'rs13', 'rs14']) l),
                             'audit', pg_temp.rr_delta('rs1214')),
          jsonb_build_object('payment_exists', pg_temp.rr_denied('rs12', 'rs12', 'payment_exists'),
                             'order_not_chargeable', pg_temp.rr_denied('rs13', 'rs13', 'order_not_chargeable'),
                             'claim_inactive', pg_temp.rr_denied('rs14', 'rs14', 'claim_inactive'),
                             'counts', '[0, 0, 0]'::jsonb,
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 3)),
          'RR-099 item 7: a Resume is refused payment_exists (a payments row under the identity), order_not_chargeable (order cancelled) and claim_inactive (orphan resolved provider_voided), each audited once, nothing dispatched');

-- RS8: the frozen shift closed after the refusal (last on this shift).
set local role authenticated;
select pg_temp.rr_push('p-rs8-k', 4, jsonb_build_array(pg_temp.rr_leg('rs8')));
reset role;
set local role service_role;
insert into _zc_r select 'm-rs8', pg_temp.rr_markrec('rs8');
reset role;
update public.shifts s set status = 'closed', closed_at = now() where s.id = pg_temp.zc_id('rr-shift-s9');
select pg_temp.rr_snap('rs8');
set local role authenticated;
select pg_temp.rr_push('p-rs8-r', 2, jsonb_build_array(pg_temp.rr_leg('rs8', 'rs8', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-rs8-r')), 'after', pg_temp.rr_resume_state('rs8'),
                             'audit', pg_temp.rr_delta('rs8')),
          jsonb_build_object('result', pg_temp.rr_denied('rs8', 'rs8', 'context_lost'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-100 item 7: a Resume after the frozen shift closed is context_lost (a Resume never switches financial context)');

-- ===========================================================================
-- G2. Item 8: resume_authority_required for a reopened row back at pending.
-- ===========================================================================
insert into _zc_r select 'shift-s10', to_jsonb(pg_temp.rr_new_shift('s10'));
set local role service_role;
insert into _zc_r select 'c-rs10', pg_temp.rr_claim('rs10', 'rs10');
insert into _zc_r select 'f-rs10', pg_temp.rr_fin('rs10', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
set local role authenticated;
select pg_temp.rr_push('p-rs10-k', 4, jsonb_build_array(pg_temp.rr_leg('rs10')));
reset role;
set local role service_role;
insert into _zc_r select 'm-rs10', pg_temp.rr_markrec('rs10');
reset role;
select pg_temp.rr_snap('rs10r');
insert into _zc_r select 'row-rs10-before', to_jsonb(pg_temp.rr_att('rs10'));
set local role authenticated;
select pg_temp.rr_push_fault('p-rs10-r', 2, jsonb_build_array(pg_temp.rr_leg('rs10', 'rs10', '{"recording_resume": 0}')),
                             'payments', '40P01');
reset role;
select is(pg_temp.rr_res('p-rs10-r'), pg_temp.rr_pending('rs10', 'payment.create', 'transient_failure'),
          'RR-101 item 8: a manager Resume whose re-dispatch fails transiently (forced 40P01) answers transient_failure (retryable, pending)');
select is(jsonb_build_object('so', pg_temp.rr_so_state('rs10') - 'retry_count', 'resume', pg_temp.rr_resume_state('rs10') - 'retry_count',
                             'card_sync_audit', pg_temp.rr_delta('rs10r', 'card_attempt.%') || pg_temp.rr_delta('rs10r', 'sync.%')),
          jsonb_build_object('so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '40P01',
                                     'result', null::jsonb, 'reason', null::text),
                             'resume', jsonb_build_object('so', 'pending', 'resume_count', 1,
                                         'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-102 item 8: the reopened row is back at pending (transient, 40P01, stored result cleared and untouched), the Resume counted once (dispatched audit), no payment and no sync.* audit');
insert into _zc_r select 'row-rs10-after', to_jsonb(pg_temp.rr_att('rs10'));
insert into _zc_r select 'so-rs10-retry', to_jsonb((pg_temp.rr_so('rs10')).retry_count);
select pg_temp.rr_snap('rs10c');
set local role authenticated;
select pg_temp.rr_push('p-rs10-c1', 1, jsonb_build_array(pg_temp.rr_leg('rs10', 'rs10', '{"recording_resume": 0}')));
select pg_temp.rr_push('p-rs10-c2', 1, jsonb_build_array(pg_temp.rr_leg('rs10')));
reset role;
select is(jsonb_build_object('with_key', pg_temp.rr_res('p-rs10-c1'), 'without_key', pg_temp.rr_res('p-rs10-c2')),
          jsonb_build_object('with_key', pg_temp.rr_pending('rs10', 'payment.create', 'resume_authority_required'),
                             'without_key', pg_temp.rr_pending('rs10', 'payment.create', 'resume_authority_required')),
          'RR-103 item 8: a cashier resend (with or without recording_resume) is answered exactly {ok:false, error:resume_authority_required, retryable:true, status:pending}');
select is(jsonb_build_object('resume', pg_temp.rr_resume_state('rs10') - 'retry_count', 'audit', pg_temp.rr_delta('rs10c'),
                             'not_adopted', (pg_temp.rr_so('rs10')).retry_count = (pg_temp.rr_r('so-rs10-retry') #>> '{}')::integer),
          jsonb_build_object('resume', jsonb_build_object('so', 'pending', 'resume_count', 1,
                                         'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'audit', '{}'::jsonb, 'not_adopted', true),
          'RR-104 item 8: the row stays pending (not adopted: retry_count unchanged, no rejection), nothing dispatched, no audit');
set local role authenticated;
select pg_temp.rr_push('p-rs10-m', 2, jsonb_build_array(pg_temp.rr_leg('rs10', 'rs10', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-rs10-m') ->> 'status', 'resume', pg_temp.rr_resume_state('rs10') - 'retry_count',
                             'adopted_once', (pg_temp.rr_so('rs10')).retry_count = (pg_temp.rr_r('so-rs10-retry') #>> '{}')::integer + 1,
                             'recorded', pg_temp.rr_derive('rs10') -> 'recorded',
                             'taken_by', (select p.taken_by_employee_profile_id from public.payments p
                                           where p.device_id = pg_temp.zc_id('device-1')
                                             and p.local_operation_id = pg_temp.zc_lop('rs10'))),
          jsonb_build_object('status', 'applied',
                             'resume', jsonb_build_object('so', 'applied', 'resume_count', 1,
                                         'resume_history', 1, 'refusal_history', 1, 'payments', 1),
                             'adopted_once', true, 'recorded', true, 'taken_by', pg_temp.zc_id('employee-2')),
          'RR-105 item 8: a manager resend adopts the pending row once and records it; the retry consumes no further Resume (count stays 1)');

-- ===========================================================================
-- H. Item 9: the protected recording_resume parse (both paths) + item 11 on
--    the revoked-device path.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['rs6', 'k2p']) l;
insert into _zc_r select 'f-' || l, pg_temp.rr_fin(l, 'commit', 'approved', pg_temp.zc_approved_fields())
  from unnest(array['rs6', 'k2p']) l;
reset role;
select pg_temp.rr_snap('h');
set local role authenticated;
select pg_temp.rr_push('p-h1', 1, jsonb_build_array(pg_temp.rr_status_op('h1', 'hx', '{"recording_resume": 0}')));
select pg_temp.rr_push('p-h2', 1, jsonb_build_array(pg_temp.rr_cash('h2', 'hx', '{"recording_resume": "1"}')));
select pg_temp.rr_push('p-h3', 1, jsonb_build_array(pg_temp.rr_cash('h3', 'hx', '{"recording_resume": null}')));
select pg_temp.rr_push('p-h4', 1, jsonb_build_array(pg_temp.rr_cash('h4', 'hx', '{"recording_resume": -1}')));
select pg_temp.rr_push('p-h5', 1, jsonb_build_array(pg_temp.rr_cash('h5', 'hx', '{"recording_resume": 4}')));
select pg_temp.rr_push('p-h6', 1, jsonb_build_array(pg_temp.rr_cash('h6', 'hx', '{"recording_resume": 1.5}')));
select pg_temp.rr_push('p-h6b', 1, jsonb_build_array(pg_temp.rr_cash('h6b', 'hx', '{"recording_resume": 1.0}')));
select pg_temp.rr_push('p-h6c', 1, jsonb_build_array(pg_temp.rr_cash('h6c', 'hx', '{"recording_resume": 4294967296}')));
select pg_temp.rr_push('p-h7', 1, jsonb_build_array(pg_temp.rr_cash('h7', 'hx',
  jsonb_build_object('recording_resume', 0, 'depends_on', jsonb_build_array(pg_temp.zc_lop('h-dep'))))));
select pg_temp.rr_push('p-h7b', 1, jsonb_build_array(pg_temp.rr_cash('h7b', 'hx',
  '{"recording_resume": 0, "depends_on": "not-an-array"}')));
reset role;
select is(pg_temp.rr_res('p-h1'), pg_temp.rr_bad_resume('h1', 'order.status'),
          'RR-106 item 9: recording_resume on order.status (single-operation call) is refused invalid_payload / detail recording_resume');
select results_eq(
  $$ select pg_temp.rr_res('p-' || l) from unnest(array['h2', 'h3', 'h4', 'h5', 'h6']) with ordinality t(l, n) order by n $$,
  $$ select pg_temp.rr_bad_resume(l, 'payment.create') from unnest(array['h2', 'h3', 'h4', 'h5', 'h6']) with ordinality t(l, n) order by n $$,
  'RR-107 item 9: recording_resume as the string "1", JSON null, -1, 4 and 1.5 on payment.create is each refused invalid_payload / recording_resume');
select is(jsonb_build_object('fraction_1_0', pg_temp.rr_res('p-h6b'), 'overflow', pg_temp.rr_res('p-h6c')),
          jsonb_build_object('fraction_1_0', pg_temp.rr_bad_resume('h6b', 'payment.create'),
                             'overflow', pg_temp.rr_bad_resume('h6c', 'payment.create')),
          'RR-108 item 9: the fraction form 1.0 and an overflow (4294967296) are refused invalid_payload too');
select is(pg_temp.rr_res('p-h7'), pg_temp.rr_bad_resume('h7', 'payment.create'),
          'RR-109 item 9: recording_resume beside a non-empty depends_on is refused invalid_payload / recording_resume');
select is(jsonb_build_object('ok', pg_temp.rr_res('p-h7b') -> 'ok', 'status', pg_temp.rr_res('p-h7b') ->> 'status',
                             'replay', pg_temp.rr_res('p-h7b') -> 'idempotency_replay',
                             'ledger_rows', pg_temp.rr_so_n(array['h7b'])),
          jsonb_build_object('ok', false, 'status', 'rejected', 'replay', false, 'ledger_rows', 0),
          'RR-110 item 9: beside a non-array depends_on the valid path refuses the operation per operation with no ledger row (the unchanged envelope check answers first)');
select is(jsonb_build_object('ledger_rows', pg_temp.rr_so_n(array['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'h6b', 'h6c', 'h7']),
                             'audit', pg_temp.rr_delta('h')),
          jsonb_build_object('ledger_rows', 0, 'audit', '{}'::jsonb),
          'RR-111 item 9: none of those refusals wrote a sync_operations row or any audit row');
set local role authenticated;
select pg_temp.rr_push('p-h8', 1, jsonb_build_array(pg_temp.rr_cash('h8', 'h8', '{"recording_resume": 1e0}')));
reset role;
select is(jsonb_build_object('parsed', ('{"recording_resume": 1e0}'::jsonb) -> 'recording_resume',
                             'status', pg_temp.rr_res('p-h8') ->> 'status', 'ledger_rows', pg_temp.rr_so_n(array['h8'])),
          jsonb_build_object('parsed', '1'::jsonb, 'status', 'applied', 'ledger_rows', 1),
          'RR-112 item 9 (documented, packet 11 item 8): the exponent form 1e0 arrives as jsonb normalized to 1 and is accepted (a fresh cash payment.create carrying it is applied)');

-- The revoked-device path (d1's device session revoked).
update public.device_sessions ds set revoked_at = now() where ds.id = pg_temp.zc_id('dsession-1');
select pg_temp.rr_snap('hr');
set local role authenticated;
select pg_temp.rr_push('p-hr1', 1, jsonb_build_array(pg_temp.rr_status_op('hr1', 'hx', '{"recording_resume": 0}')));
select pg_temp.rr_push('p-hr2', 1, jsonb_build_array(pg_temp.rr_cash('hr2', 'hx', '{"recording_resume": "1"}')));
select pg_temp.rr_push('p-hr3', 1, jsonb_build_array(pg_temp.rr_cash('hr3', 'hx', '{"recording_resume": null}')));
select pg_temp.rr_push('p-hr4', 1, jsonb_build_array(pg_temp.rr_cash('hr4', 'hx', '{"recording_resume": -1}')));
select pg_temp.rr_push('p-hr5', 1, jsonb_build_array(pg_temp.rr_cash('hr5', 'hx', '{"recording_resume": 4}')));
select pg_temp.rr_push('p-hr6', 1, jsonb_build_array(pg_temp.rr_cash('hr6', 'hx', '{"recording_resume": 1.5}')));
select pg_temp.rr_push('p-hr7', 1, jsonb_build_array(pg_temp.rr_cash('hr7', 'hx',
  jsonb_build_object('recording_resume', 0, 'depends_on', jsonb_build_array(pg_temp.zc_lop('h-dep'))))));
select pg_temp.rr_push('p-hr7b', 1, jsonb_build_array(pg_temp.rr_cash('hr7b', 'hx',
  '{"recording_resume": 0, "depends_on": "not-an-array"}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-hr1'), 'device_revoked', pg_temp.rr_r('p-hr1') -> 'device_revoked'),
          jsonb_build_object('result', pg_temp.rr_bad_resume('hr1', 'order.status'), 'device_revoked', true),
          'RR-113 item 9: on the revoked-device path recording_resume on order.status is refused invalid_payload / recording_resume (device_revoked true)');
select results_eq(
  $$ select pg_temp.rr_res('p-' || l) from unnest(array['hr2', 'hr3', 'hr4', 'hr5', 'hr6', 'hr7', 'hr7b']) with ordinality t(l, n) order by n $$,
  $$ select pg_temp.rr_bad_resume(l, 'payment.create') from unnest(array['hr2', 'hr3', 'hr4', 'hr5', 'hr6', 'hr7', 'hr7b']) with ordinality t(l, n) order by n $$,
  'RR-114 item 9: on the revoked-device path "1", null, -1, 4, 1.5, a non-empty depends_on and a non-array depends_on beside recording_resume are each refused invalid_payload / recording_resume');
select is(jsonb_build_object('ledger_rows', pg_temp.rr_so_n(array['hr1', 'hr2', 'hr3', 'hr4', 'hr5', 'hr6', 'hr7', 'hr7b']),
                             'audit', pg_temp.rr_delta('hr')),
          jsonb_build_object('ledger_rows', 0, 'audit', '{}'::jsonb),
          'RR-115 item 9: those revoked-path refusals wrote no ledger row and no audit (malformed control data is never recorded revoked_device)');
select pg_temp.rr_snap('hr-ok');
set local role authenticated;
select pg_temp.rr_push('p-hr-ok', 1, jsonb_build_array(pg_temp.rr_leg('rs6', 'rs6', '{"recording_resume": 0}')));
select pg_temp.rr_push('p-hr-replay', 2, jsonb_build_array(pg_temp.rr_leg('rs2', 'rs2', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-hr-ok'), 'device_revoked', pg_temp.rr_r('p-hr-ok') -> 'device_revoked',
                             'so', pg_temp.rr_so_state('rs6') - 'retry_count', 'audit', pg_temp.rr_delta('hr-ok', 'sync.%')),
          jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('rs6'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                         'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false),
                             'device_revoked', true,
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', 'revoked_device',
                                     'reason', 'revoked_device',
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device')),
                             'audit', jsonb_build_object('sync.operation_rejected', 1)),
          'RR-116 item 9: a well-formed push on the revoked-device path (a provider leg carrying recording_resume 0) is still recorded revoked_device');
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-hr-replay')), 'after', pg_temp.rr_resume_state('rs2'),
                             'card_audit', pg_temp.rr_delta('hr-ok', 'card_attempt.%')),
          jsonb_build_object('result', pg_temp.rr_denied('rs2', 'rs2', null),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'card_audit', '{}'::jsonb),
          'RR-117 item 9: the revoked-device path never reopens: a manager Resume of a recoverable rejected leg replays it unchanged (no resume_denied, no Resume evidence)');

-- Item 11 on the revoked-device path.
select pg_temp.rr_snap('k-r');
set local role authenticated;
select pg_temp.rr_push('p-k1r', 2, jsonb_build_array(pg_temp.rr_close_op('k1r-close', pg_temp.zc_id('rr-shift-s10')),
                                                     pg_temp.rr_status_op('k1r-st', 'jst')));
select pg_temp.rr_push('p-k2r', 1, jsonb_build_array(pg_temp.rr_leg('k2p'), pg_temp.rr_cash('k2r-cash', 'jx')));
select pg_temp.rr_push('p-k3r', 1, jsonb_build_array(pg_temp.rr_cash('k3r-cash', 'jx', '{"recording_resume": 0}'),
                                                     pg_temp.rr_status_op('k3r-st', 'jst')));
reset role;
select is(jsonb_build_object('k1', pg_temp.rr_r('p-k1r') - 'server_ts', 'k2', pg_temp.rr_r('p-k2r') - 'server_ts',
                             'k3', pg_temp.rr_r('p-k3r') - 'server_ts'),
          jsonb_build_object(
            'k1', jsonb_build_object('ok', true, 'device_revoked', true, 'results', jsonb_build_array(
                    pg_temp.rr_pending('k1r-close', 'shift.close', 'single_operation_required'),
                    pg_temp.rr_pending('k1r-st', 'order.status', 'single_operation_required'))),
            'k2', jsonb_build_object('ok', true, 'device_revoked', true, 'results', jsonb_build_array(
                    pg_temp.rr_pending('k2p', 'payment.create', 'single_operation_required'),
                    pg_temp.rr_pending('k2r-cash', 'payment.create', 'single_operation_required'))),
            'k3', jsonb_build_object('ok', true, 'device_revoked', true, 'results', jsonb_build_array(
                    pg_temp.rr_pending('k3r-cash', 'payment.create', 'single_operation_required'),
                    pg_temp.rr_pending('k3r-st', 'order.status', 'single_operation_required')))),
          'RR-118 item 11: on the revoked-device path [shift.close, order.status], [provider-identity payment.create, cash] and [payment.create carrying recording_resume, order.status] answer single_operation_required for every element (device_revoked true)');
select is(jsonb_build_object('ledger_rows', pg_temp.rr_so_n(array['k1r-close', 'k1r-st', 'k2p', 'k2r-cash', 'k3r-cash', 'k3r-st']),
                             'audit', pg_temp.rr_delta('k-r')),
          jsonb_build_object('ledger_rows', 0, 'audit', '{}'::jsonb),
          'RR-119 item 11: those revoked-path batches wrote no sync row (not even revoked_device) and no audit');
select pg_temp.rr_snap('k4r');
set local role authenticated;
select pg_temp.rr_push('p-k4r', 1, jsonb_build_array(pg_temp.rr_cash('k4r-a', 'k4a'), pg_temp.rr_cash('k4r-b', 'k4b')));
reset role;
select is(jsonb_build_object('errors', (select jsonb_agg(e ->> 'detail') from jsonb_array_elements(pg_temp.rr_r('p-k4r') -> 'results') e),
                             'ledger_rows', pg_temp.rr_so_n(array['k4r-a', 'k4r-b']), 'audit', pg_temp.rr_delta('k4r')),
          jsonb_build_object('errors', '["revoked_device", "revoked_device"]'::jsonb, 'ledger_rows', 2,
                             'audit', jsonb_build_object('sync.operation_rejected', 2)),
          'RR-120 item 11: a two-operation revoked-path call without card-sensitive operations behaves as before (each recorded revoked_device)');
update public.device_sessions ds set revoked_at = null where ds.id = pg_temp.zc_id('dsession-1');

-- RS6: the stored revoked_device token is never resumable.
select pg_temp.rr_snap('rs6m');
set local role service_role;
insert into _zc_r select 'm-rs6', pg_temp.rr_markrec('rs6', 1, 'permission_denied');
reset role;
select is(jsonb_build_object('stored', (pg_temp.rr_att('rs6')).refusal_code, 'classification', pg_temp.rr_r('m-rs6') ->> 'classification',
                             'reason', pg_temp.rr_derive('rs6') ->> 'reason', 'recoverable', pg_temp.rr_r('m-rs6') -> 'recoverable',
                             'audit', pg_temp.rr_delta('rs6m')),
          jsonb_build_object('stored', 'revoked_device', 'classification', 'orphan_approved',
                             'reason', 'nonrecoverable_refusal', 'recoverable', false,
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-121 item 6: the own leg memoized revoked_device stores revoked_device (orphan_approved, nonrecoverable_refusal, not recoverable)');
select pg_temp.rr_snap('rs6r');
set local role authenticated;
select pg_temp.rr_push('p-rs6-r', 2, jsonb_build_array(pg_temp.rr_leg('rs6', 'rs6', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-rs6-r'), 'after', pg_temp.rr_resume_state('rs6'),
                             'audit', pg_temp.rr_delta('rs6r')),
          jsonb_build_object('result', jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device',
                                         'local_operation_id', pg_temp.zc_lop('rs6'), 'operation_type', 'payment.create',
                                         'status', 'rejected', 'idempotency_replay', true,
                                         'resume_denied', 'not_recoverable'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-122 item 7: a manager Resume of a stored revoked_device token is not_recoverable (audited once, nothing dispatched)');

-- ===========================================================================
-- I. Item 10: transient classification.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['i1', 'i8', 'i8b', 'i57', 'i6f']) l;
insert into _zc_r select 'f-' || l, pg_temp.rr_fin(l, 'commit', 'approved', pg_temp.zc_approved_fields())
  from unnest(array['i1', 'i8', 'i8b', 'i57', 'i6f']) l;
reset role;
select pg_temp.rr_snap('i1');
set local role authenticated;
select pg_temp.rr_push_fault('p-i1-40P01', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', '40P01');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i1-40P01'), 'so', pg_temp.rr_so_state('i1'),
                             'payments', pg_temp.rr_pay_n('i1')),
          jsonb_build_object('answer', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '40P01',
                                     'retry_count', 0, 'result', null::jsonb, 'reason', null::text),
                             'payments', 0),
          'RR-123 item 10: a forced 40P01 inside the provider-identity leg''s dispatch leaves the row pending (transient, 40P01, result untouched) and answers transient_failure (retryable); no payment');
select pg_temp.rr_snap('i1m');
set local role service_role;
insert into _zc_r select 'm-i1', pg_temp.rr_markrec('i1');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_r('m-i1')), 'stored', (pg_temp.rr_att('i1')).refusal_code,
                             'audit', pg_temp.rr_delta('i1m')),
          jsonb_build_object('result', jsonb_build_object('ok', false, 'error', 'precondition_failed',
                                         'detail', 'no_recording_attempt', 'attempt_id', pg_temp.zc_lop('i1'),
                                         'attempt_state', 'approved', 'server_ts?', true),
                             'stored', null::text, 'audit', jsonb_build_object('card_attempt.denied', 1)),
          'RR-124 item 6: with the own leg still pending card_attempt_mark_recording_result answers no_recording_attempt (stores nothing; one card_attempt.denied audit)');
set local role authenticated;
select pg_temp.rr_push_fault('p-i1-08006', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', '08006');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i1-08006'), 'so', pg_temp.rr_so_state('i1')),
          jsonb_build_object('answer', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '08006',
                                     'retry_count', 1, 'result', null::jsonb, 'reason', null::text)),
          'RR-125 item 10: a forced 08006 (connection class) on the resend is transient too: pending, last_error_code 08006');
set local role authenticated;
select pg_temp.rr_push_fault('p-i1-53100', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', '53100');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i1-53100'), 'so', pg_temp.rr_so_state('i1')),
          jsonb_build_object('answer', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '53100',
                                     'retry_count', 2, 'result', null::jsonb, 'reason', null::text)),
          'RR-126 item 10: a forced 53100 (insufficient resources) is transient: pending, last_error_code 53100');
set local role authenticated;
select pg_temp.rr_push_fault('p-i1-55P03', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', '55P03');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i1-55P03'), 'so', pg_temp.rr_so_state('i1')),
          jsonb_build_object('answer', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '55P03',
                                     'retry_count', 3, 'result', null::jsonb, 'reason', null::text)),
          'RR-127 item 10: a forced 55P03 (lock not available) is transient: pending, last_error_code 55P03');
set local role authenticated;
select pg_temp.rr_push_fault('p-i1-58030', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', '58030');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i1-58030'), 'so', pg_temp.rr_so_state('i1')),
          jsonb_build_object('answer', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '58030',
                                     'retry_count', 4, 'result', null::jsonb, 'reason', null::text)),
          'RR-128 item 10: a forced 58030 (system I/O error) is transient: pending, last_error_code 58030');
set local role authenticated;
select pg_temp.rr_push_fault('p-i1-XX000', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', 'XX000');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i1-XX000'), 'so', pg_temp.rr_so_state('i1')),
          jsonb_build_object('answer', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', 'XX000',
                                     'retry_count', 5, 'result', null::jsonb, 'reason', null::text)),
          'RR-129 item 10: a forced XX000 (internal error) is transient: pending, last_error_code XX000');
set local role authenticated;
select pg_temp.rr_push_fault('p-i1-57P03', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', '57P03');
select pg_temp.rr_push_fault('p-i1-40001', 1, jsonb_build_array(pg_temp.rr_leg('i1')), 'payments', '40001',
                             'could not serialize access (synthetic, no RPC prefix)');
reset role;
select is(jsonb_build_object('answer_57', pg_temp.rr_res('p-i1-57P03'), 'answer_40001', pg_temp.rr_res('p-i1-40001'),
                             'so', pg_temp.rr_so_state('i1')),
          jsonb_build_object('answer_57', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'answer_40001', pg_temp.rr_pending('i1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '40001',
                                     'retry_count', 7, 'result', null::jsonb, 'reason', null::text)),
          'RR-130 item 10: class 57 (57P03) and a 40001 without an RPC prefix are transient as well');
select is(jsonb_build_object('audit', pg_temp.rr_delta('i1') - 'card_attempt.denied', 'payments', pg_temp.rr_pay_n('i1')),
          jsonb_build_object('audit', '{}'::jsonb, 'payments', 0),
          'RR-131 item 10: the eight transient answers wrote no audit row (no sync.operation_rejected / conflict) and no payment');
set local role authenticated;
select pg_temp.rr_push('p-i1-ok', 1, jsonb_build_array(pg_temp.rr_leg('i1')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-i1-ok') ->> 'status', 'so', (pg_temp.rr_so('i1')).status,
                             'retry_count', (pg_temp.rr_so('i1')).retry_count, 'payments', pg_temp.rr_pay_n('i1'),
                             'recorded', pg_temp.rr_derive('i1') -> 'recorded'),
          jsonb_build_object('status', 'applied', 'so', 'applied', 'retry_count', 8, 'payments', 1, 'recorded', true),
          'RR-132 item 10: with the fault removed the resend dispatches the same pending row and records exactly once');
select pg_temp.rr_snap('i8');
set local role authenticated;
select pg_temp.rr_push_fault('p-i8', 1, jsonb_build_array(pg_temp.rr_leg('i8')), 'payments', '40001',
                             'record_payment: forced serialization conflict (zc)');
select pg_temp.rr_push_fault('p-i8b', 1, jsonb_build_array(pg_temp.rr_leg('i8b')), 'payments', 'XX000',
                             'record_payment: forced internal error (zc)');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i8'), 'so', pg_temp.rr_so_state('i8') - 'retry_count',
                             'payments', pg_temp.rr_pay_n('i8')),
          jsonb_build_object('answer', jsonb_build_object('local_operation_id', pg_temp.zc_lop('i8'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'conflict',
                                         'sqlstate', '40001', 'status', 'conflict', 'idempotency_replay', false),
                             'so', jsonb_build_object('status', 'conflict', 'class', 'conflict', 'code', '40001',
                                     'result', jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', '40001'),
                                     'reason', null::text),
                             'payments', 0),
          'RR-133 item 10: a raise whose message starts with record_payment: and SQLSTATE 40001 stays terminal conflict (never transient)');
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i8b'), 'status', (pg_temp.rr_so('i8b')).status,
                             'class', (pg_temp.rr_so('i8b')).last_error_class, 'audit', pg_temp.rr_delta('i8')),
          jsonb_build_object('answer', jsonb_build_object('local_operation_id', pg_temp.zc_lop('i8b'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                         'sqlstate', 'XX000', 'detail', null::text, 'status', 'rejected',
                                         'idempotency_replay', false),
                             'status', 'rejected', 'class', 'permanent',
                             'audit', jsonb_build_object('sync.operation_conflict', 1, 'sync.operation_rejected', 1)),
          'RR-134 item 10: a record_payment:-prefixed raise of a transient class (XX000) stays terminal (rejected, permanent) — the prefix allowlist wins whatever the class');
select pg_temp.rr_snap('i9');
set local role authenticated;
select pg_temp.rr_push_fault('p-i9', 1, jsonb_build_array(pg_temp.rr_cash('i9-cash', 'i9')), 'payments', '40P01');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i9'), 'so', pg_temp.rr_so_state('i9-cash') - 'retry_count',
                             'audit', pg_temp.rr_delta('i9')),
          jsonb_build_object('answer', jsonb_build_object('local_operation_id', pg_temp.zc_lop('i9-cash'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                         'sqlstate', '40P01', 'detail', null::text, 'status', 'rejected',
                                         'idempotency_replay', false),
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', '40P01',
                                     'reason', 'rr forced fault',
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', '40P01',
                                                                  'detail', null::text)),
                             'audit', jsonb_build_object('sync.operation_rejected', 1)),
          'RR-135 item 10: a non-provider cash payment.create with a forced 40P01 keeps today''s handling (permanent rejected, raw message, one sync.operation_rejected)');
-- The own canonical leg memoized conflict (i8): the mark stores conflict; a Resume never reopens it.
select pg_temp.rr_snap('i8m');
set local role service_role;
insert into _zc_r select 'm-i8', pg_temp.rr_markrec('i8', 1, 'permission_denied');
reset role;
set local role authenticated;
select pg_temp.rr_push('p-i8-resume', 2, jsonb_build_array(pg_temp.rr_leg('i8', 'i8', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('stored', (pg_temp.rr_att('i8')).refusal_code, 'classification', pg_temp.rr_r('m-i8') ->> 'classification',
                             'reason', pg_temp.rr_derive('i8') ->> 'reason',
                             'resume', pg_temp.rr_res('p-i8-resume'), 'resume_count', (pg_temp.rr_att('i8')).recording_resume_count,
                             'audit', pg_temp.rr_delta('i8m')),
          jsonb_build_object('stored', 'conflict', 'classification', 'orphan_approved', 'reason', 'nonrecoverable_refusal',
                             'resume', jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', '40001',
                                         'local_operation_id', pg_temp.zc_lop('i8'), 'operation_type', 'payment.create',
                                         'status', 'conflict', 'idempotency_replay', true),
                             'resume_count', 0, 'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-136 item 6: an own canonical leg memoized conflict yields the stored token conflict (orphan_approved, nonrecoverable_refusal); a manager Resume of it replays the conflict, never reopened');
-- A cash payment.create carrying recording_resume is card-sensitive by the key (transient handling).
set local role authenticated;
select pg_temp.rr_push_fault('p-i7c', 1, jsonb_build_array(pg_temp.rr_cash('i7c-cash', 'i7c', '{"recording_resume": 0}')),
                             'payments', '40P01');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i7c'), 'so', pg_temp.rr_so_state('i7c-cash') - 'retry_count',
                             'payments', pg_temp.rr_order_pay_n('i7c')),
          jsonb_build_object('answer', pg_temp.rr_pending('i7c-cash', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '40P01',
                                     'result', null::jsonb, 'reason', null::text),
                             'payments', 0),
          'RR-137 item 10: a non-provider payment.create carrying recording_resume is card-sensitive by the key: a forced 40P01 leaves it pending (transient_failure)');
-- A foreign row of the identity still pending (a leg with an extra expected_revision key, failed transiently).
set local role authenticated;
select pg_temp.rr_push_fault('p-i6f', 1, jsonb_build_array(pg_temp.zc_pay_op(pg_temp.zc_lop('i6f'), pg_temp.rr_ord('i6f'),
  'card', 1234, jsonb_build_object('payload', jsonb_build_object('order_id', pg_temp.rr_ord('i6f'), 'tender_type', 'card',
                                                                 'amount_tendered_minor', 1234, 'expected_revision', 1)))),
  'payments', '40P01');
reset role;
select pg_temp.rr_snap('i6fm');
set local role service_role;
insert into _zc_r select 'm-i6f', pg_temp.rr_markrec('i6f', 1, 'permission_denied');
reset role;
select is(jsonb_build_object('so', (pg_temp.rr_so('i6f')).status, 'stored', (pg_temp.rr_att('i6f')).refusal_code,
                             'audit', pg_temp.rr_delta('i6fm')),
          jsonb_build_object('so', 'pending', 'stored', 'nonrecoverable_refusal',
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-138 item 6: a foreign row of the identity that is still pending stores nonrecoverable_refusal (not no_recording_attempt: only the own leg pending is unreported)');
-- 57014 aborts the whole call and memoizes nothing.
set local role authenticated;
select pg_temp.rr_push_fault('p-i57', 1, jsonb_build_array(pg_temp.rr_leg('i57')), 'payments', '57014');
reset role;
select is(jsonb_build_object('raised', pg_temp.rr_r('p-i57') ->> '__error__', 'ledger_rows', pg_temp.rr_so_n(array['i57']),
                             'payments', pg_temp.rr_pay_n('i57'), 'state', (pg_temp.rr_att('i57')).state),
          jsonb_build_object('raised', '57014', 'ledger_rows', 0, 'payments', 0, 'state', 'approved'),
          'RR-139 item 10: a 57014 inside a card-sensitive dispatch aborts the whole call (raised to the caller) and memoizes nothing');
select pg_temp.rr_snap('i10');
set local role authenticated;
select pg_temp.rr_push_fault('p-i10', 3, jsonb_build_array(pg_temp.rr_close_op('i10-close', pg_temp.zc_id('shift-2'))),
                             'shifts', '40P01');
reset role;
select is(jsonb_build_object('answer', pg_temp.rr_res('p-i10'), 'so', pg_temp.rr_so_state('i10-close', 2),
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('shift-2')),
                             'audit', pg_temp.rr_delta('i10')),
          jsonb_build_object('answer', pg_temp.rr_pending('i10-close', 'shift.close', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '40P01',
                                     'retry_count', 0, 'result', null::jsonb, 'reason', null::text),
                             'shift', 'open', 'audit', '{}'::jsonb),
          'RR-140 item 10: a shift.close with a forced transient (40P01 from a trigger on shifts) is left pending (transient_failure), the shift still open, no audit');
set local role authenticated;
select pg_temp.rr_push_fault('p-i10b', 3, jsonb_build_array(pg_temp.rr_close_op('i10b-close', pg_temp.zc_id('shift-2'))),
                             'shifts', 'XX000', 'close_shift: forced internal error (zc)');
select pg_temp.rr_push('p-i10-ok', 3, jsonb_build_array(pg_temp.rr_close_op('i10-close', pg_temp.zc_id('shift-2'))));
reset role;
select is(jsonb_build_object('prefixed', jsonb_build_object('status', (pg_temp.rr_so('i10b-close', 2)).status,
                                                           'class', (pg_temp.rr_so('i10b-close', 2)).last_error_class),
                             'resend', pg_temp.rr_res('p-i10-ok') ->> 'status',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('shift-2'))),
          jsonb_build_object('prefixed', jsonb_build_object('status', 'rejected', 'class', 'permanent'),
                             'resend', 'applied', 'shift', 'closed'),
          'RR-141 item 10: a close_shift:-prefixed raise stays terminal (rejected); the pending close resent without a fault is applied once');

-- ===========================================================================
-- J. Item 11: single_operation_required on the valid-device path.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-j2p', pg_temp.rr_claim('j2p', 'j2p');
insert into _zc_r select 'f-j2p', pg_temp.rr_fin('j2p', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
select pg_temp.rr_snap('j');
set local role authenticated;
select pg_temp.rr_push('p-j1', 2, jsonb_build_array(pg_temp.rr_close_op('j1-close', pg_temp.zc_id('rr-shift-s10')),
                                                    pg_temp.rr_status_op('j1-st', 'jst')));
select pg_temp.rr_push('p-j2', 1, jsonb_build_array(pg_temp.rr_leg('j2p'), pg_temp.rr_cash('j2-cash', 'jx')));
select pg_temp.rr_push('p-j3', 1, jsonb_build_array(pg_temp.rr_cash('j3-cash', 'jx', '{"recording_resume": 0}'),
                                                    pg_temp.rr_status_op('j3-st', 'jst')));
reset role;
select is(pg_temp.rr_r('p-j1') - 'server_ts',
          jsonb_build_object('ok', true, 'results', jsonb_build_array(
            pg_temp.rr_pending('j1-close', 'shift.close', 'single_operation_required'),
            pg_temp.rr_pending('j1-st', 'order.status', 'single_operation_required'))),
          'RR-142 item 11: [shift.close, order.status] is answered single_operation_required for every element (identity keys echoed, retryable, pending, idempotency_replay false; no device_revoked)');
select is(pg_temp.rr_r('p-j2') - 'server_ts',
          jsonb_build_object('ok', true, 'results', jsonb_build_array(
            pg_temp.rr_pending('j2p', 'payment.create', 'single_operation_required'),
            pg_temp.rr_pending('j2-cash', 'payment.create', 'single_operation_required'))),
          'RR-143 item 11: [provider-identity payment.create, cash payment.create] is answered single_operation_required for both');
select is(pg_temp.rr_r('p-j3') - 'server_ts',
          jsonb_build_object('ok', true, 'results', jsonb_build_array(
            pg_temp.rr_pending('j3-cash', 'payment.create', 'single_operation_required'),
            pg_temp.rr_pending('j3-st', 'order.status', 'single_operation_required'))),
          'RR-144 item 11: [payment.create carrying recording_resume, order.status] is answered single_operation_required for both');
select is(jsonb_build_object('ledger_rows', pg_temp.rr_so_n(array['j1-close', 'j1-st', 'j2p', 'j2-cash', 'j3-cash', 'j3-st']),
                             'audit', pg_temp.rr_delta('j'), 'payments', pg_temp.rr_pay_n('j2p') + pg_temp.rr_pay_n('j2-cash'),
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s10'))),
          jsonb_build_object('ledger_rows', 0, 'audit', '{}'::jsonb, 'payments', 0, 'shift', 'open'),
          'RR-145 item 11: those batches wrote no sync row, no audit and no business mutation');
select pg_temp.rr_snap('j4');
set local role authenticated;
select pg_temp.rr_push('p-j4', 1, jsonb_build_array(pg_temp.rr_cash('j4-a', 'j4a'), pg_temp.rr_cash('j4-b', 'j4b')));
select pg_temp.rr_push('p-j5', 1, jsonb_build_array(pg_temp.rr_leg('j2p')));
reset role;
select is(jsonb_build_object('statuses', (select jsonb_agg(e ->> 'status') from jsonb_array_elements(pg_temp.rr_r('p-j4') -> 'results') e),
                             'ledger_rows', pg_temp.rr_so_n(array['j4-a', 'j4-b']),
                             'payments', pg_temp.rr_order_pay_n('j4a') + pg_temp.rr_order_pay_n('j4b')),
          jsonb_build_object('statuses', '["applied", "applied"]'::jsonb, 'ledger_rows', 2, 'payments', 2),
          'RR-146 item 11: a two-operation call without card-sensitive operations behaves as before (both applied)');
select is(jsonb_build_object('status', pg_temp.rr_res('p-j5') ->> 'status', 'recorded', pg_temp.rr_derive('j2p') -> 'recorded'),
          jsonb_build_object('status', 'applied', 'recorded', true),
          'RR-147 item 11: the provider leg resent alone afterwards records (the batching refusal memoized nothing)');

-- ===========================================================================
-- K. Item 12: lock order sanity (one transaction).
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-k12', pg_temp.rr_claim('k12', 'k12');
insert into _zc_r select 'f-k12', pg_temp.rr_fin('k12', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
-- Hold app.edit_order's lock set on the order in this transaction: orders FOR UPDATE, its rounds and items
-- FOR UPDATE, the branch FOR SHARE (the branch share lock edit_order takes).
do $$
begin
  perform 1 from public.orders o where o.organization_id = pg_temp.zc_org() and o.id = pg_temp.rr_ord('k12') for update;
  perform 1 from public.order_service_rounds r
    where r.organization_id = pg_temp.zc_org() and r.order_id = pg_temp.rr_ord('k12') order by r.id for update;
  perform 1 from public.order_items i
    where i.organization_id = pg_temp.zc_org() and i.order_id = pg_temp.rr_ord('k12') order by i.id for update;
  perform 1 from public.branches b
    where b.organization_id = pg_temp.zc_org() and b.id = pg_temp.zc_branch() for share;
end $$;
set local role authenticated;
select pg_temp.rr_push('p-k12', 1, jsonb_build_array(pg_temp.rr_leg('k12')));
reset role;
select is(jsonb_build_object('error', pg_temp.rr_r('p-k12') ? '__error__', 'status', pg_temp.rr_res('p-k12') ->> 'status',
                             'payments', pg_temp.rr_pay_n('k12'), 'recorded', pg_temp.rr_derive('k12') -> 'recorded'),
          jsonb_build_object('error', false, 'status', 'applied', 'payments', 1, 'recorded', true),
          'RR-148 item 12 (same-transaction re-entrancy check only; the two-session lock-order proof against app.edit_order is the concurrency runner''s): a LIVE leg on an order whose edit_order lock set (order, rounds, items FOR UPDATE; branch FOR SHARE) this same transaction already holds records without error or self-wait');

-- ===========================================================================
-- L. The identity-first gate holds whatever the binding lifecycle / revision
--    (last: a draining binding cannot be re-enabled while attempts are unresolved).
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['l1', 'l2']) l;
insert into _zc_r select 'f-l1', pg_temp.rr_fin('l1', 'commit', 'approved', pg_temp.zc_approved_fields());
insert into _zc_r select 'f-l2-u', pg_temp.rr_fin('l2', 'commit', 'unknown');
insert into _zc_r select 'f-l2-l', pg_temp.rr_fin('l2', 'lookup', 'failed', '{}', 'operator');
insert into _zc_r select 'free-l2', pg_temp.rr_free('l2');
insert into _zc_r select 'f-l2-ap', pg_temp.rr_fin('l2', 'lookup', 'approved',
  '{"provider_status_code": "ok1", "provider_amount": "12.34", "provider_currency": "ILS", "error_flag": false}', 'operator');
reset role;
insert into _zc_r select 'bind-l-drain', pg_temp.rr_bind_step('live', 'draining', 'incident');
insert into _zc_r select 'setup-l-off', pg_temp.zc_pilot('live', false);
set local role authenticated;
select pg_temp.rr_push('p-l2', 1, jsonb_build_array(pg_temp.rr_leg('l2')));
select pg_temp.rr_push('p-l1', 1, jsonb_build_array(pg_temp.rr_leg('l1')));
reset role;
select is(jsonb_build_object('binding', pg_temp.rr_r('bind-l-drain') ->> 'new_lifecycle',
                             'revision_enabled', (app.card_pilot_revision_current()).enabled,
                             'freed_then_approved', pg_temp.rr_ts(pg_temp.rr_res('p-l2')),
                             'freed_payments', pg_temp.rr_pay_n('l2')),
          jsonb_build_object('binding', 'draining', 'revision_enabled', false,
                             'freed_then_approved', pg_temp.rr_refusal('l2', 'l2', 'provider_recording_refused', 'attempt_freed'),
                             'freed_payments', 0),
          'RR-149 item 2: with the binding draining and the revision OFF a freed-then-approved identity is still refused attempt_freed (zero payments)');
select is(jsonb_build_object('status', pg_temp.rr_res('p-l1') ->> 'status', 'payments', pg_temp.rr_pay_n('l1'),
                             'recorded', pg_temp.rr_derive('l1') -> 'recorded'),
          jsonb_build_object('status', 'applied', 'payments', 1, 'recorded', true),
          'RR-150 item 3: an admissible leg still records exactly once with the binding draining and the revision OFF (the revision and the lifecycle gate start only)');

-- ===========================================================================
-- M. Review-fix pass (TEST_BRIEF_2, lane RR): re-admit LIVE claims on d1 for
--    sections N-T. A fresh LIVE revision ON; the operator RPC still refuses to
--    re-enable d1's draining binding while d1 holds unresolved attempts (section
--    L), so a test-only owner update re-enables it (the payment_terminals guard
--    trigger allows draining -> enabled). d1's open shift stays rr-shift-s10.
-- ===========================================================================
insert into _zc_r select 'setup-m-on', pg_temp.zc_pilot('live');
insert into _zc_r select 'setup-m-rpc', pg_temp.rr_bind_step('live', 'enabled', 'live_activation');
update app.payment_terminals t set lifecycle = 'enabled'
 where t.organization_id = pg_temp.zc_org() and t.device_id = pg_temp.zc_id('device-1') and t.lifecycle = 'draining';
insert into _zc_r select 'orders-m', jsonb_agg(pg_temp.zc_order(l)) from unnest(array[
  'vtr3', 'vol', 'vos', 'vfa', 'vfb', 'vcs', 'vrm', 'vls', 'vlu', 'vla', 'vld', 'vlr',
  'vgf', 'vgd', 'vgu', 'vgr', 'vdv']) l;
select is(jsonb_build_object('revision', pg_temp.rr_r('setup-m-on') -> 'ok', 'rpc', pg_temp.rr_r('setup-m-rpc'),
                             'posture', app.card_terminal_posture(pg_temp.zc_org(), pg_temp.zc_branch(), pg_temp.zc_id('device-1')),
                             'open_shift', (select s.id from public.shifts s
                                             where s.device_id = pg_temp.zc_id('device-1') and s.status = 'open')),
          jsonb_build_object('revision', true,
                             'rpc', jsonb_build_object('ok', false, 'error', 'precondition_failed', 'detail', 'attempt_unresolved'),
                             'posture', jsonb_build_object('lifecycle', 'enabled', 'mode', 'live', 'enabled', true),
                             'open_shift', pg_temp.zc_id('rr-shift-s10')),
          'RR-151 setup (review-fix pass): a LIVE revision is ON again; the operator RPC still refuses to re-enable d1''s draining binding (attempt_unresolved), so a test-only owner update re-enables it (posture enabled / live, starts admitted); d1''s open shift is rr-shift-s10');

-- ===========================================================================
-- N. The third Resume's transient (TESTING_STRATEGY:173; SECURITY:325; DOMAIN
--    8.4 resume_limit): a forced 40P01 on the third Resume's dispatch leaves the
--    attempt pending_recording, never resume_limit; the resend records once.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-vtr3', pg_temp.rr_claim('vtr3', 'vtr3');
insert into _zc_r select 'f-vtr3', pg_temp.rr_fin('vtr3', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
set local role authenticated;
select pg_temp.rr_push('p-vtr3-k', 4, jsonb_build_array(pg_temp.rr_leg('vtr3')));
reset role;
set local role service_role;
insert into _zc_r select 'm-vtr3', pg_temp.rr_markrec('vtr3');
reset role;
-- Two earlier authorized Resumes, seeded as owner (count 2, two entries in each history); the
-- permission_denied refusal stays reported.
update app.card_provider_attempts a
   set recording_resume_count = 2,
       recording_refusal_history = jsonb_build_array(
         jsonb_build_object('refusal_code', 'permission_denied', 'refused_at', a.recording_refused_at),
         jsonb_build_object('refusal_code', 'permission_denied', 'refused_at', a.recording_refused_at)),
       recording_resume_history = jsonb_build_array(
         jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-2'), 'membership_id', pg_temp.zc_id('membership-2'),
                            'at', a.recording_refused_at, 'resume_count', 0),
         jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-2'), 'membership_id', pg_temp.zc_id('membership-2'),
                            'at', a.recording_refused_at, 'resume_count', 1))
 where a.id = (pg_temp.rr_att('vtr3')).id;
select is(jsonb_build_object('so', (pg_temp.rr_so('vtr3')).status, 'reason', (pg_temp.rr_so('vtr3')).rejection_reason,
                             'stored', (pg_temp.rr_att('vtr3')).refusal_code,
                             'resume_count', (pg_temp.rr_att('vtr3')).recording_resume_count,
                             'derive', pg_temp.rr_derive('vtr3')),
          jsonb_build_object('so', 'rejected', 'reason', 'permission_denied', 'stored', 'permission_denied', 'resume_count', 2,
                             'derive', jsonb_build_object('recorded', false, 'payment_id', null,
                                         'classification', 'approved_unrecorded', 'reason', 'recording_refused',
                                         'recoverable', true, 'claim_active', true, 'blocks_close', true, 'unresolved', true)),
          'RR-152 setup (item 1): an approved attempt holds a reported permission_denied leg (kitchen PIN) and two earlier Resumes seeded as owner (count 2); it derives approved_unrecorded / recording_refused, recoverable');
select pg_temp.rr_snap('vtr3r');
set local role authenticated;
select pg_temp.rr_push_fault('p-vtr3-r', 2, jsonb_build_array(pg_temp.rr_leg('vtr3', 'vtr3', '{"recording_resume": 2}')),
                             'payments', '40P01');
reset role;
select is(pg_temp.rr_res('p-vtr3-r'), pg_temp.rr_pending('vtr3', 'payment.create', 'transient_failure'),
          'RR-153 item 1: the third Resume (manager staff 2, recording_resume 2) whose re-dispatch meets a forced 40P01 on the payments insert answers exactly {ok:false, error:transient_failure, retryable:true, status:pending, idempotency_replay:false}');
select is(jsonb_build_object('so', pg_temp.rr_so_state('vtr3'), 'resume', pg_temp.rr_resume_state('vtr3'),
                             'new_refusal_entry', ((pg_temp.rr_att('vtr3')).recording_refusal_history -> 2) - 'refused_at',
                             'new_resume_entry', ((pg_temp.rr_att('vtr3')).recording_resume_history -> 2) - 'at',
                             'card_sync_audit', pg_temp.rr_delta('vtr3r', 'card_attempt.%') || pg_temp.rr_delta('vtr3r', 'sync.%'),
                             'audit_detail', (select jsonb_agg(e.new_values - 'local_operation_id') from public.audit_events e
                                               where e.organization_id = pg_temp.zc_org()
                                                 and e.action = 'card_attempt.recording_resume_requested'
                                                 and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('vtr3'))),
          jsonb_build_object('so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '40P01',
                                     'retry_count', 1, 'result', null::jsonb, 'reason', null::text),
                             'resume', jsonb_build_object('so', 'pending', 'retry_count', 1, 'resume_count', 3,
                                         'resume_history', 3, 'refusal_history', 3, 'payments', 0),
                             'new_refusal_entry', jsonb_build_object('refusal_code', 'permission_denied'),
                             'new_resume_entry', jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-2'),
                                                   'membership_id', pg_temp.zc_id('membership-2'), 'resume_count', 2),
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1),
                             'audit_detail', jsonb_build_array(jsonb_build_object('attempt_state', 'approved',
                                               'prior_refusal_code', 'permission_denied', 'resume_count', 2,
                                               'outcome', 'dispatched'))),
          'RR-154 item 1: that Resume was counted (count 3; a third entry in each history: the reported permission_denied and the manager acting on count 2) with one dispatched card_attempt.recording_resume_requested; the reopened row is back at pending (transient, 40P01, result and rejection reason cleared, retry_count 1 from the adopt path); no payment, no sync.* audit');
select is(pg_temp.rr_derive('vtr3'),
          jsonb_build_object('recorded', false, 'payment_id', null, 'classification', 'approved_unrecorded',
                             'reason', 'pending_recording', 'recoverable', false, 'claim_active', true,
                             'blocks_close', true, 'unresolved', true),
          'RR-155 item 1 (TESTING_STRATEGY:173 / SECURITY:325 "a forced deadlock on the third Resume''s dispatch leaving the attempt pending_recording"; DOMAIN 8.4 "a row back to pending after a transient failure stays pending_recording until it is dispatched"): after the transient third Resume (count 3, the row pending, the earlier report kept per review fix 6) app.card_attempt_derive reports approved_unrecorded / pending_recording, not recoverable');
select is(jsonb_build_object('classification', pg_temp.rr_derive('vtr3') ->> 'classification',
                             'resume_limit', (pg_temp.rr_derive('vtr3') ->> 'reason') = 'resume_limit',
                             'envelope', app.card_attempt_envelope(pg_temp.rr_att('vtr3')) - 'server_ts'),
          jsonb_build_object('classification', 'approved_unrecorded', 'resume_limit', false,
                             'envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vtr3'), 'state', 'approved',
                                           'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                           'refusal_code', 'permission_denied', 'recoverable', false, 'resume_count', 3,
                                           'amount_minor', 1234, 'currency_code', 'ILS')),
          'RR-156 item 1: that pending third Resume is never resume_limit: the attempt stays approved_unrecorded (not orphan_approved) and its envelope answers recoverable false with resume_count 3');
select pg_temp.rr_snap('vtr3m');
set local role authenticated;
select pg_temp.rr_push('p-vtr3-m', 2, jsonb_build_array(pg_temp.rr_leg('vtr3')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-vtr3-m') ->> 'status', 'resume', pg_temp.rr_resume_state('vtr3'),
                             'recorded', pg_temp.rr_derive('vtr3') -> 'recorded',
                             'taken_by', (select p.taken_by_employee_profile_id from public.payments p
                                           where p.device_id = pg_temp.zc_id('device-1')
                                             and p.local_operation_id = pg_temp.zc_lop('vtr3')),
                             'card_sync_audit', pg_temp.rr_delta('vtr3m', 'card_attempt.%') || pg_temp.rr_delta('vtr3m', 'sync.%')),
          jsonb_build_object('status', 'applied',
                             'resume', jsonb_build_object('so', 'applied', 'retry_count', 2, 'resume_count', 3,
                                         'resume_history', 3, 'refusal_history', 3, 'payments', 1),
                             'recorded', true, 'taken_by', pg_temp.zc_id('employee-2'), 'card_sync_audit', '{}'::jsonb),
          'RR-157 item 1: a manager resend of the plain leg adopts the pending row once and records exactly one card payment (the manager its actor); no further Resume is consumed (count 3, histories 3) and no card_attempt / sync audit is written');

-- ===========================================================================
-- O. Resume check order and refusal freshness (review fix 6): resume_limit and
--    resume_stale precede refusal_not_recorded; a re-dispatch refused again
--    leaves the earlier report stored and must itself be reported before the
--    next Resume; context_lost also for a soft-deleted frozen shift / drawer.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['vol', 'vos', 'vfa', 'vfb', 'vcs']) l;
insert into _zc_r select 'f-' || l, pg_temp.rr_fin(l, 'commit', 'approved', pg_temp.zc_approved_fields())
  from unnest(array['vol', 'vos', 'vfa', 'vfb', 'vcs']) l;
reset role;
set local role authenticated;
select pg_temp.rr_push('p-' || l || '-k', 4, jsonb_build_array(pg_temp.rr_leg(l))) from unnest(array['vol', 'vos', 'vfa', 'vcs']) l;
reset role;
-- vfb: its own leg pushed while the cashier's membership was revoked (memoized revoked_employee, as RS11).
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-1');
set local role authenticated;
select pg_temp.rr_push('p-vfb-k', 1, jsonb_build_array(pg_temp.rr_leg('vfb')));
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-1');
update app.card_provider_attempts a set recording_resume_count = 3 where a.id = (pg_temp.rr_att('vol')).id;
select is((select jsonb_object_agg(l, jsonb_build_object('so', (pg_temp.rr_so(l)).status,
                                                         'reason', (pg_temp.rr_so(l)).rejection_reason,
                                                         'stored', (pg_temp.rr_att(l)).refusal_code,
                                                         'resume_count', (pg_temp.rr_att(l)).recording_resume_count))
             from unnest(array['vol', 'vos', 'vfa', 'vfb', 'vcs']) l),
          jsonb_build_object(
            'vol', jsonb_build_object('so', 'rejected', 'reason', 'permission_denied', 'stored', null::text, 'resume_count', 3),
            'vos', jsonb_build_object('so', 'rejected', 'reason', 'permission_denied', 'stored', null::text, 'resume_count', 0),
            'vfa', jsonb_build_object('so', 'rejected', 'reason', 'permission_denied', 'stored', null::text, 'resume_count', 0),
            'vfb', jsonb_build_object('so', 'rejected', 'reason', 'revoked_employee', 'stored', null::text, 'resume_count', 0),
            'vcs', jsonb_build_object('so', 'rejected', 'reason', 'permission_denied', 'stored', null::text, 'resume_count', 0)),
          'RR-158 setup (item 5): five approved attempts each hold a memoized recoverable refusal not yet reported (permission_denied under the kitchen PIN; revoked_employee for vfb); vol''s count is seeded to 3 as owner');
select pg_temp.rr_snap('vol');
set local role authenticated;
select pg_temp.rr_push('p-vol-r', 2, jsonb_build_array(pg_temp.rr_leg('vol', 'vol', '{"recording_resume": 3}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-vol-r')), 'after', pg_temp.rr_resume_state('vol'),
                             'stored', (pg_temp.rr_att('vol')).refusal_code, 'audit', pg_temp.rr_delta('vol'),
                             'audited', pg_temp.rr_resume_audits('vol', 'refused', 'resume_limit')),
          jsonb_build_object('result', pg_temp.rr_denied('vol', 'vol', 'resume_limit'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 3,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'stored', null::text,
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1), 'audited', 1),
          'RR-159 item 5 (review fix 6 order): with the count at 3 and the refusal never reported, a Resume (recording_resume 3) answers resume_limit, not refusal_not_recorded; audited once (refused, resume_limit), nothing dispatched');
select pg_temp.rr_snap('vos');
set local role authenticated;
select pg_temp.rr_push('p-vos-stale', 2, jsonb_build_array(pg_temp.rr_leg('vos', 'vos', '{"recording_resume": 1}')));
select pg_temp.rr_push('p-vos-cur', 2, jsonb_build_array(pg_temp.rr_leg('vos', 'vos', '{"recording_resume": 0}')));
reset role;
select is(jsonb_build_object('stale', pg_temp.rr_ts(pg_temp.rr_res('p-vos-stale')), 'current', pg_temp.rr_ts(pg_temp.rr_res('p-vos-cur')),
                             'after', pg_temp.rr_resume_state('vos'), 'audit', pg_temp.rr_delta('vos'),
                             'audited', jsonb_build_array(pg_temp.rr_resume_audits('vos', 'refused', 'resume_stale'),
                                                          pg_temp.rr_resume_audits('vos', 'refused', 'refusal_not_recorded'))),
          jsonb_build_object('stale', pg_temp.rr_denied('vos', 'vos', 'resume_stale'),
                             'current', pg_temp.rr_denied('vos', 'vos', 'refusal_not_recorded'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 2),
                             'audited', '[1, 1]'::jsonb),
          'RR-160 item 5 (review fix 6 order): with the refusal never reported, a stale recording_resume (1 against count 0) answers resume_stale, not refusal_not_recorded, and the current value 0 then answers refusal_not_recorded; each audited once, nothing dispatched');

-- vfa: a re-dispatch refused again with ANOTHER recoverable token.
set local role service_role;
insert into _zc_r select 'm-vfa', pg_temp.rr_markrec('vfa');
reset role;
insert into _zc_r select 'att-vfa-1', jsonb_build_object('refusal_code', (pg_temp.rr_att('vfa')).refusal_code,
                                                          'refused_at', (pg_temp.rr_att('vfa')).recording_refused_at);
select pg_temp.rr_snap('vfa1');
-- The authorized Resume's re-dispatch is refused by a forced permanent raise on the payments insert
-- carrying record_payment's revoked-membership message (P0001): memoized revoked_employee.
set local role authenticated;
select pg_temp.rr_push_fault('p-vfa-r1', 2, jsonb_build_array(pg_temp.rr_leg('vfa', 'vfa', '{"recording_resume": 0}')),
                             'payments', 'P0001', 'zc synthetic: resolved membership is not active');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-vfa-r1'), 'so', pg_temp.rr_so_state('vfa'), 'audit', pg_temp.rr_delta('vfa1')),
          jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('vfa'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                         'sqlstate', 'P0001', 'detail', 'revoked_employee', 'status', 'rejected',
                                         'idempotency_replay', false),
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', 'P0001',
                                     'retry_count', 1, 'reason', 'revoked_employee',
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', 'P0001',
                                                                  'detail', 'revoked_employee')),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1,
                                                         'sync.operation_rejected', 1)),
          'RR-161 item 5: an authorized Resume of a reported permission_denied leg (recording_resume 0) is dispatched once and its re-dispatch is refused again (forced P0001 revoked-membership raise on the payments insert): the same row is memoized rejected revoked_employee, with one dispatched Resume audit and one sync.operation_rejected');
select is(jsonb_build_object('stored', (pg_temp.rr_att('vfa')).refusal_code,
                             'refused_at_kept', (pg_temp.rr_att('vfa')).recording_refused_at
                                                = (pg_temp.rr_r('att-vfa-1') ->> 'refused_at')::timestamptz,
                             'resume_count', (pg_temp.rr_att('vfa')).recording_resume_count,
                             'refusal_history', (pg_temp.rr_att('vfa')).recording_refusal_history,
                             'resume_counts', (select jsonb_agg(h -> 'resume_count')
                                                 from jsonb_array_elements((pg_temp.rr_att('vfa')).recording_resume_history) h),
                             'payments', pg_temp.rr_pay_n('vfa')),
          jsonb_build_object('stored', 'permission_denied', 'refused_at_kept', true, 'resume_count', 1,
                             'refusal_history', jsonb_build_array(jsonb_build_object('refusal_code', 'permission_denied',
                                                  'refused_at', pg_temp.rr_r('att-vfa-1') -> 'refused_at')),
                             'resume_counts', '[0]'::jsonb, 'payments', 0),
          'RR-162 item 5 (review fix 6): after the re-dispatch is refused again the attempt still stores its earlier report (refusal_code permission_denied, recording_refused_at unchanged); only the count (1) and the two histories moved (the refusal history holding that report); no payment');
select pg_temp.rr_snap('vfa2');
set local role authenticated;
select pg_temp.rr_push('p-vfa-r2', 2, jsonb_build_array(pg_temp.rr_leg('vfa', 'vfa', '{"recording_resume": 1}')));
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-vfa-r2'), 'after', pg_temp.rr_resume_state('vfa'),
                             'audit', pg_temp.rr_delta('vfa2'),
                             'detail', (select jsonb_agg(jsonb_build_object('resume_count', e.new_values -> 'resume_count',
                                                 'prior_refusal_code', e.new_values ->> 'prior_refusal_code'))
                                          from public.audit_events e
                                         where e.organization_id = pg_temp.zc_org()
                                           and e.action = 'card_attempt.recording_resume_requested'
                                           and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('vfa')
                                           and e.new_values ->> 'denied_reason' = 'refusal_not_recorded')),
          jsonb_build_object('result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', 'P0001',
                                         'detail', 'revoked_employee', 'local_operation_id', pg_temp.zc_lop('vfa'),
                                         'operation_type', 'payment.create', 'status', 'rejected',
                                         'idempotency_replay', true, 'resume_denied', 'refusal_not_recorded'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 1, 'resume_count', 1,
                                        'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1),
                             'detail', jsonb_build_array(jsonb_build_object('resume_count', 1,
                                                                            'prior_refusal_code', 'permission_denied'))),
          'RR-163 item 5 (review fix 6): the next Resume (recording_resume 1) before the new refusal is reported answers refusal_not_recorded (the stored report permission_denied is not the row''s revoked_employee) and replays the new stored result; audited once at count 1, nothing dispatched');
select pg_temp.rr_snap('vfa3');
set local role service_role;
insert into _zc_r select 'm-vfa-2', pg_temp.rr_markrec('vfa', 1, 'permission_denied');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_r('m-vfa-2')),
                             'restamped', (pg_temp.rr_att('vfa')).recording_refused_at
                                          > (pg_temp.rr_r('att-vfa-1') ->> 'refused_at')::timestamptz,
                             'audit', pg_temp.rr_delta('vfa3')),
          jsonb_build_object('result', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vfa'), 'state', 'approved',
                                         'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                         'refusal_code', 'revoked_employee', 'recoverable', true, 'resume_count', 1,
                                         'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'restamped', true,
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-164 item 5 (review fix 6): card_attempt_mark_recording_result then reports the new refusal (derived from the row, not the hint): refusal_code revoked_employee with a later recording_refused_at and one card_attempt.recording_refused audit; still recoverable at count 1');
select pg_temp.rr_snap('vfa4');
set local role authenticated;
select pg_temp.rr_push('p-vfa-r3', 2, jsonb_build_array(pg_temp.rr_leg('vfa', 'vfa', '{"recording_resume": 1}')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-vfa-r3') ->> 'status', 'resume', pg_temp.rr_resume_state('vfa'),
                             'refusal_codes', (select jsonb_agg(h -> 'refusal_code')
                                                 from jsonb_array_elements((pg_temp.rr_att('vfa')).recording_refusal_history) h),
                             'resume_counts', (select jsonb_agg(h -> 'resume_count')
                                                 from jsonb_array_elements((pg_temp.rr_att('vfa')).recording_resume_history) h),
                             'recorded', pg_temp.rr_derive('vfa') -> 'recorded',
                             'taken_by', (select p.taken_by_employee_profile_id from public.payments p
                                           where p.device_id = pg_temp.zc_id('device-1')
                                             and p.local_operation_id = pg_temp.zc_lop('vfa')),
                             'card_sync_audit', pg_temp.rr_delta('vfa4', 'card_attempt.%') || pg_temp.rr_delta('vfa4', 'sync.%')),
          jsonb_build_object('status', 'applied',
                             'resume', jsonb_build_object('so', 'applied', 'retry_count', 2, 'resume_count', 2,
                                         'resume_history', 2, 'refusal_history', 2, 'payments', 1),
                             'refusal_codes', '["permission_denied", "revoked_employee"]'::jsonb,
                             'resume_counts', '[0, 1]'::jsonb, 'recorded', true, 'taken_by', pg_temp.zc_id('employee-2'),
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-165 item 5 (review fix 6): after that report the next Resume (recording_resume 1) is authorized: dispatched once and recorded once (the manager its actor), count 2, the histories holding both reported refusals and both Resumes');

-- vfb: a re-dispatch refused again with the SAME token (only the freshness clause can tell).
set local role service_role;
insert into _zc_r select 'm-vfb', pg_temp.rr_markrec('vfb', 1, 'rejected');
reset role;
insert into _zc_r select 'att-vfb-1', jsonb_build_object('refusal_code', (pg_temp.rr_att('vfb')).refusal_code,
                                                          'refused_at', (pg_temp.rr_att('vfb')).recording_refused_at);
select pg_temp.rr_snap('vfb1');
set local role authenticated;
select pg_temp.rr_push_fault('p-vfb-r1', 2, jsonb_build_array(pg_temp.rr_leg('vfb', 'vfb', '{"recording_resume": 0}')),
                             'payments', 'P0001', 'zc synthetic: resolved membership is not active');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-vfb-r1'), 'so_reason', (pg_temp.rr_so('vfb')).rejection_reason,
                             'stored', (pg_temp.rr_att('vfb')).refusal_code,
                             'refused_at_kept', (pg_temp.rr_att('vfb')).recording_refused_at
                                                = (pg_temp.rr_r('att-vfb-1') ->> 'refused_at')::timestamptz,
                             'resume_count', (pg_temp.rr_att('vfb')).recording_resume_count,
                             'audit', pg_temp.rr_delta('vfb1'),
                             'row_stamp_before_report', (pg_temp.rr_so('vfb')).updated_at < (pg_temp.rr_att('vfb')).recording_refused_at),
          jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('vfb'),
                                         'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                         'sqlstate', 'P0001', 'detail', 'revoked_employee', 'status', 'rejected',
                                         'idempotency_replay', false),
                             'so_reason', 'revoked_employee', 'stored', 'revoked_employee', 'refused_at_kept', true,
                             'resume_count', 1,
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1,
                                                         'sync.operation_rejected', 1),
                             'row_stamp_before_report', true),
          'RR-166 item 5 (review fix 6): a reported revoked_employee refusal (vfb, membership revoked at push time) is resumed once and its re-dispatch is refused again with the same token (forced P0001 revoked-membership raise): refusal_code and recording_refused_at are unchanged; in this single transaction the row''s rejection stamp (sync_operations_set_updated_at: now(), the transaction start) still precedes the report');
-- Test-only owner update reproducing the cross-transaction order the freshness rule compares: a later
-- push transaction stamps its rejection after the report it follows (now() = that transaction's start),
-- so the report is moved before this transaction's start, i.e. before the row's latest rejection.
update app.card_provider_attempts a set recording_refused_at = now() - interval '1 second'
 where a.id = (pg_temp.rr_att('vfb')).id;
select pg_temp.rr_snap('vfb2');
set local role authenticated;
select pg_temp.rr_push('p-vfb-r2', 2, jsonb_build_array(pg_temp.rr_leg('vfb', 'vfb', '{"recording_resume": 1}')));
reset role;
select is(jsonb_build_object('same_token', (pg_temp.rr_att('vfb')).refusal_code = (pg_temp.rr_so('vfb')).rejection_reason,
                             'report_predates_rejection', (pg_temp.rr_att('vfb')).recording_refused_at < (pg_temp.rr_so('vfb')).updated_at,
                             'result', pg_temp.rr_res('p-vfb-r2'), 'after', pg_temp.rr_resume_state('vfb'),
                             'audit', pg_temp.rr_delta('vfb2'),
                             'audited', pg_temp.rr_resume_audits('vfb', 'refused', 'refusal_not_recorded')),
          jsonb_build_object('same_token', true, 'report_predates_rejection', true,
                             'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', 'P0001',
                                         'detail', 'revoked_employee', 'local_operation_id', pg_temp.zc_lop('vfb'),
                                         'operation_type', 'payment.create', 'status', 'rejected',
                                         'idempotency_replay', true, 'resume_denied', 'refusal_not_recorded'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 1, 'resume_count', 1,
                                        'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1), 'audited', 1),
          'RR-167 item 5 (review fix 6 freshness): with the same token stored and reported, a report older than the row''s latest rejection (recording_refused_at < sync_operations.updated_at) is stale: the next Resume (recording_resume 1) answers refusal_not_recorded; audited once, nothing dispatched');
select pg_temp.rr_snap('vfb3');
set local role service_role;
insert into _zc_r select 'm-vfb-2', pg_temp.rr_markrec('vfb', 1, 'rejected');
reset role;
select is(jsonb_build_object('stored', (pg_temp.rr_att('vfb')).refusal_code,
                             'report_after_rejection', (pg_temp.rr_att('vfb')).recording_refused_at > (pg_temp.rr_so('vfb')).updated_at,
                             'envelope', pg_temp.rr_ts(pg_temp.rr_r('m-vfb-2')),
                             'audit', pg_temp.rr_delta('vfb3')),
          jsonb_build_object('stored', 'revoked_employee', 'report_after_rejection', true,
                             'envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vfb'), 'state', 'approved',
                                           'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                           'refusal_code', 'revoked_employee', 'recoverable', true, 'resume_count', 1,
                                           'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-168 item 5 (review fix 6 freshness): reporting it again (the same token) re-stamps recording_refused_at after the row''s rejection and writes one card_attempt.recording_refused audit');
select pg_temp.rr_snap('vfb4');
set local role authenticated;
select pg_temp.rr_push('p-vfb-r3', 2, jsonb_build_array(pg_temp.rr_leg('vfb', 'vfb', '{"recording_resume": 1}')));
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-vfb-r3') ->> 'status', 'resume', pg_temp.rr_resume_state('vfb'),
                             'refusal_codes', (select jsonb_agg(h -> 'refusal_code')
                                                 from jsonb_array_elements((pg_temp.rr_att('vfb')).recording_refusal_history) h),
                             'recorded', pg_temp.rr_derive('vfb') -> 'recorded',
                             'card_sync_audit', pg_temp.rr_delta('vfb4', 'card_attempt.%') || pg_temp.rr_delta('vfb4', 'sync.%')),
          jsonb_build_object('status', 'applied',
                             'resume', jsonb_build_object('so', 'applied', 'retry_count', 2, 'resume_count', 2,
                                         'resume_history', 2, 'refusal_history', 2, 'payments', 1),
                             'refusal_codes', '["revoked_employee", "revoked_employee"]'::jsonb, 'recorded', true,
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-169 item 5 (review fix 6 freshness): after the fresh report the next Resume (recording_resume 1) is authorized and records once (count 2)');

-- vcs: context_lost for a soft-deleted frozen shift, then a soft-deleted frozen drawer.
set local role service_role;
insert into _zc_r select 'm-vcs', pg_temp.rr_markrec('vcs');
reset role;
update public.shifts s set deleted_at = now() where s.id = pg_temp.zc_id('rr-shift-s10');
insert into _zc_r select 'vcs-shift', jsonb_build_object('status', s.status, 'deleted', s.deleted_at is not null)
  from public.shifts s where s.id = pg_temp.zc_id('rr-shift-s10');
select pg_temp.rr_snap('vcs1');
set local role authenticated;
select pg_temp.rr_push('p-vcs-1', 2, jsonb_build_array(pg_temp.rr_leg('vcs', 'vcs', '{"recording_resume": 0}')));
reset role;
update public.shifts s set deleted_at = null where s.id = pg_temp.zc_id('rr-shift-s10');
select is(jsonb_build_object('frozen_shift', pg_temp.rr_r('vcs-shift'), 'stored', (pg_temp.rr_att('vcs')).refusal_code,
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-vcs-1')), 'after', pg_temp.rr_resume_state('vcs'),
                             'audit', pg_temp.rr_delta('vcs1'), 'audited', pg_temp.rr_resume_audits('vcs', 'refused', 'context_lost')),
          jsonb_build_object('frozen_shift', jsonb_build_object('status', 'open', 'deleted', true), 'stored', 'permission_denied',
                             'result', pg_temp.rr_denied('vcs', 'vcs', 'context_lost'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1), 'audited', 1),
          'RR-170 item 5 (review fix 6): a Resume of a reported permission_denied leg whose frozen shift row is soft-deleted (deleted_at set, status still open) answers context_lost; audited once, nothing dispatched');
update public.cash_drawer_sessions c set deleted_at = now() where c.id = pg_temp.zc_id('rr-drawer-s10');
insert into _zc_r select 'vcs-drawer', jsonb_build_object('status', c.status, 'deleted', c.deleted_at is not null)
  from public.cash_drawer_sessions c where c.id = pg_temp.zc_id('rr-drawer-s10');
select pg_temp.rr_snap('vcs2');
set local role authenticated;
select pg_temp.rr_push('p-vcs-2', 2, jsonb_build_array(pg_temp.rr_leg('vcs', 'vcs', '{"recording_resume": 0}')));
reset role;
update public.cash_drawer_sessions c set deleted_at = null where c.id = pg_temp.zc_id('rr-drawer-s10');
select is(jsonb_build_object('frozen_drawer', pg_temp.rr_r('vcs-drawer'), 'result', pg_temp.rr_ts(pg_temp.rr_res('p-vcs-2')),
                             'after', pg_temp.rr_resume_state('vcs'), 'audit', pg_temp.rr_delta('vcs2'),
                             'audited', pg_temp.rr_resume_audits('vcs', 'refused', 'context_lost')),
          jsonb_build_object('frozen_drawer', jsonb_build_object('status', 'active', 'deleted', true),
                             'result', pg_temp.rr_denied('vcs', 'vcs', 'context_lost'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                        'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'audit', '{}'::jsonb, 'audited', 1),
          'RR-171 item 5 (review fix 6): with the shift restored and the frozen drawer row soft-deleted (status still active) the Resume answers context_lost again; the identical (attempt, count, reason) writes no second audit, nothing dispatched');

-- ===========================================================================
-- P. A resolved attempt is final for the recording result (review fix 1).
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-vrm', pg_temp.rr_claim('vrm', 'vrm');
insert into _zc_r select 'f-vrm', pg_temp.rr_fin('vrm', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
set local role authenticated;
select pg_temp.rr_push('p-vrm-k', 4, jsonb_build_array(pg_temp.rr_leg('vrm')));
reset role;
update public.orders o set grand_total_minor = 1500, subtotal_minor = 1500 where o.id = pg_temp.rr_ord('vrm');
insert into _zc_r select 'res-vrm', pg_temp.rr_resolve('vrm', 'provider_voided');
insert into _zc_r select 'row-vrm', to_jsonb(pg_temp.rr_att('vrm'));
insert into _zc_r select 'ev-vrm', to_jsonb((select count(*) from app.card_provider_private_events e
                                              where e.attempt_row_id = (pg_temp.rr_att('vrm')).id));
select is(jsonb_build_object('so', (pg_temp.rr_so('vrm')).status, 'reason', (pg_temp.rr_so('vrm')).rejection_reason,
                             'state', (pg_temp.rr_att('vrm')).state, 'resolution', (pg_temp.rr_att('vrm')).resolution,
                             'stored', (pg_temp.rr_att('vrm')).refusal_code,
                             'refused_at', (pg_temp.rr_att('vrm')).recording_refused_at,
                             'recorded', pg_temp.rr_derive('vrm') -> 'recorded'),
          jsonb_build_object('so', 'rejected', 'reason', 'permission_denied', 'state', 'approved', 'resolution', 'provider_voided',
                             'stored', null::text, 'refused_at', null::timestamptz, 'recorded', false),
          'RR-172 setup (item 6): an approved, unrecorded attempt whose own leg is memoized permission_denied (never reported) is orphaned (order total changed) and resolved provider_voided by the operator');
select pg_temp.rr_snap('vrm');
set local role service_role;
insert into _zc_r select 'm-vrm', pg_temp.rr_markrec('vrm', 1, 'permission_denied');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_r('m-vrm')),
                             'row_unchanged', to_jsonb(pg_temp.rr_att('vrm')) = pg_temp.rr_r('row-vrm'),
                             'audit', pg_temp.rr_delta('vrm'),
                             'events', (select count(*) from app.card_provider_private_events e
                                         where e.attempt_row_id = (pg_temp.rr_att('vrm')).id)
                                       - (pg_temp.rr_r('ev-vrm') #>> '{}')::bigint),
          jsonb_build_object('result', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vrm'), 'state', 'approved',
                                         'classification', 'resolved', 'recorded', false, 'provider_return_code', 0,
                                         'resolution', 'provider_voided', 'amount_minor', 1234, 'currency_code', 'ILS',
                                         'server_ts?', true),
                             'row_unchanged', true, 'audit', '{}'::jsonb, 'events', 0),
          'RR-173 item 6 (review fix 1): card_attempt_mark_recording_result on that resolved attempt answers its envelope (classification resolved, resolution provider_voided) and writes nothing: the attempt row is identical (refusal_code / recording_refused_at stay NULL although its own leg is rejected permission_denied), no card_attempt.recording_refused / card_attempt.denied audit, no private event');

-- ===========================================================================
-- Q. The LIVE release mark (review fix 3): every release request of a sent /
--    unknown attempt without a resolution stamps release_requested_at and
--    writes card_attempt.release_requested; approved, declined and resolved
--    attempts answer the envelope with no stamp and no audit.
-- ===========================================================================
create function pg_temp.rr_markrel(label text, n integer default 1) returns jsonb language sql volatile as
$$ select public.card_attempt_mark_release_requested(pg_temp.zc_id('pin-' || n), pg_temp.zc_id('device-1'),
     'zc-token-1', pg_temp.zc_lop(label), pg_temp.zc_caller()) $$;
create function pg_temp.rr_release_rows() returns jsonb language sql stable as
$$ select coalesce(jsonb_agg(e.new_values order by e.new_values ->> 'attempt_state'), '[]'::jsonb)
     from public.audit_events e
    where e.organization_id = pg_temp.zc_org() and e.action = 'card_attempt.release_requested' $$;
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['vls', 'vlu', 'vla', 'vld', 'vlr']) l;
insert into _zc_r select 'f-vlu', pg_temp.rr_fin('vlu', 'commit', 'unknown');
insert into _zc_r select 'f-vla', pg_temp.rr_fin('vla', 'commit', 'approved', pg_temp.zc_approved_fields());
insert into _zc_r select 'f-vld', pg_temp.rr_fin('vld', 'commit', 'declined', '{"approval_type": "declined", "provider_return_code": 33}');
insert into _zc_r select 'f-vlr', pg_temp.rr_fin('vlr', 'commit', 'anomaly', '{"anomaly_code": "voided"}');
reset role;
insert into _zc_r select 'res-vlr', pg_temp.rr_resolve('vlr', 'provider_voided');
insert into _zc_r select 'row-vl', (select jsonb_object_agg(l, to_jsonb(pg_temp.rr_att(l))) from unnest(array['vla', 'vld', 'vlr']) l);
select is((select jsonb_object_agg(l, jsonb_build_object('state', (pg_temp.rr_att(l)).state,
                                                         'resolution', (pg_temp.rr_att(l)).resolution,
                                                         'release_requested_at', (pg_temp.rr_att(l)).release_requested_at))
             from unnest(array['vls', 'vlu', 'vla', 'vld', 'vlr']) l)
          || jsonb_build_object('release_rows', pg_temp.rr_release_rows()),
          jsonb_build_object(
            'vls', jsonb_build_object('state', 'sent', 'resolution', null::text, 'release_requested_at', null::timestamptz),
            'vlu', jsonb_build_object('state', 'unknown', 'resolution', null::text, 'release_requested_at', null::timestamptz),
            'vla', jsonb_build_object('state', 'approved', 'resolution', null::text, 'release_requested_at', null::timestamptz),
            'vld', jsonb_build_object('state', 'declined', 'resolution', null::text, 'release_requested_at', null::timestamptz),
            'vlr', jsonb_build_object('state', 'unknown', 'resolution', 'provider_voided', 'release_requested_at', null::timestamptz),
            'release_rows', '[]'::jsonb),
          'RR-174 setup (item 4): LIVE attempts of d1 in state sent, unknown, approved, declined and unknown-resolved (a voided anomaly resolved provider_voided), none release-requested yet (no card_attempt.release_requested row in the organization)');
select pg_temp.rr_snap('vl1');
set local role service_role;
insert into _zc_r select 'mrel-vls-1', pg_temp.rr_markrel('vls');
reset role;
insert into _zc_r select 'ts-vls-1', to_jsonb((pg_temp.rr_att('vls')).release_requested_at);
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_r('mrel-vls-1')),
                             'stamped', (pg_temp.rr_att('vls')).release_requested_at is not null,
                             'audit', pg_temp.rr_delta('vl1'), 'rows', pg_temp.rr_release_rows()),
          jsonb_build_object('result', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vls'), 'state', 'sent',
                                         'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234,
                                         'currency_code', 'ILS', 'server_ts?', true),
                             'stamped', true, 'audit', jsonb_build_object('card_attempt.release_requested', 1),
                             'rows', '[{"attempt_state": "sent"}]'::jsonb),
          'RR-175 item 4 (review fix 3): a first release request of a sent LIVE attempt (cashier on d1) answers its envelope, stamps release_requested_at and writes one card_attempt.release_requested {attempt_state:sent}');
select pg_sleep(0.002);
select pg_temp.rr_snap('vl2');
set local role service_role;
insert into _zc_r select 'mrel-vls-2', pg_temp.rr_markrel('vls');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_r('mrel-vls-2')),
                             'restamped_later', (pg_temp.rr_att('vls')).release_requested_at
                                                > (pg_temp.rr_r('ts-vls-1') #>> '{}')::timestamptz,
                             'audit', pg_temp.rr_delta('vl2'), 'rows', pg_temp.rr_release_rows()),
          jsonb_build_object('result', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vls'), 'state', 'sent',
                                         'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234,
                                         'currency_code', 'ILS', 'server_ts?', true),
                             'restamped_later', true, 'audit', jsonb_build_object('card_attempt.release_requested', 1),
                             'rows', '[{"attempt_state": "sent"}, {"attempt_state": "sent"}]'::jsonb),
          'RR-176 item 4 (review fix 3): a second release request of the same sent attempt (2 ms later) stamps release_requested_at again, later than the first, and writes a second card_attempt.release_requested {attempt_state:sent}: exactly two rows for the two requests');
select pg_temp.rr_snap('vl3');
set local role service_role;
insert into _zc_r select 'mrel-vlu', pg_temp.rr_markrel('vlu');
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_r('mrel-vlu')),
                             'stamped', (pg_temp.rr_att('vlu')).release_requested_at is not null,
                             'audit', pg_temp.rr_delta('vl3'), 'rows', pg_temp.rr_release_rows()),
          jsonb_build_object('result', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vlu'), 'state', 'unknown',
                                         'classification', 'in_progress', 'recorded', false, 'amount_minor', 1234,
                                         'currency_code', 'ILS', 'server_ts?', true),
                             'stamped', true, 'audit', jsonb_build_object('card_attempt.release_requested', 1),
                             'rows', '[{"attempt_state": "sent"}, {"attempt_state": "sent"}, {"attempt_state": "unknown"}]'::jsonb),
          'RR-177 item 4 (review fix 3): a release request of an unknown LIVE attempt without a resolution stamps it and writes one card_attempt.release_requested {attempt_state:unknown}');
select pg_temp.rr_snap('vl4');
insert into _zc_r select 'ev-vl', to_jsonb((select count(*) from app.card_provider_private_events e
                                             where e.attempt_row_id in (select (pg_temp.rr_att(l)).id
                                                                          from unnest(array['vla', 'vld', 'vlr']) l)));
set local role service_role;
insert into _zc_r select 'mrel-' || l, pg_temp.rr_markrel(l) from unnest(array['vla', 'vld', 'vlr']) l;
reset role;
select is(jsonb_build_object('approved', pg_temp.rr_ts(pg_temp.rr_r('mrel-vla')),
                             'declined', pg_temp.rr_ts(pg_temp.rr_r('mrel-vld')),
                             'resolved', pg_temp.rr_ts(pg_temp.rr_r('mrel-vlr')),
                             'rows_unchanged', (select jsonb_object_agg(l, to_jsonb(pg_temp.rr_att(l)))
                                                  from unnest(array['vla', 'vld', 'vlr']) l) = pg_temp.rr_r('row-vl'),
                             'audit', pg_temp.rr_delta('vl4'),
                             'events', (select count(*) from app.card_provider_private_events e
                                         where e.attempt_row_id in (select (pg_temp.rr_att(l)).id
                                                                      from unnest(array['vla', 'vld', 'vlr']) l))
                                       - (pg_temp.rr_r('ev-vl') #>> '{}')::bigint),
          jsonb_build_object('approved', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vla'), 'state', 'approved',
                                           'classification', 'approved_unrecorded', 'recorded', false,
                                           'provider_return_code', 0, 'recoverable', false, 'resume_count', 0,
                                           'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'declined', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vld'), 'state', 'declined',
                                           'classification', 'declined', 'recorded', false, 'provider_return_code', 33,
                                           'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'resolved', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vlr'), 'state', 'unknown',
                                           'classification', 'resolved', 'recorded', false, 'resolution', 'provider_voided',
                                           'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'rows_unchanged', true, 'audit', '{}'::jsonb, 'events', 0),
          'RR-178 item 4 (review fix 3): a release request of an approved, a declined and a resolved (unknown, provider_voided) LIVE attempt answers each envelope with no stamp (release_requested_at stays NULL, the three rows identical), no audit and no private event');

-- ===========================================================================
-- R. The transient-classification prefixes (review fix 18).
-- ===========================================================================
select is(jsonb_build_object(
            'starts_with_record_payment', strpos(pg_get_functiondef('app.sync_push(uuid, uuid, jsonb)'::regprocedure),
                                                 $q$starts_with(v_caught_msg, 'record_payment:')$q$) > 0,
            'starts_with_close_shift', strpos(pg_get_functiondef('app.sync_push(uuid, uuid, jsonb)'::regprocedure),
                                              $q$starts_with(v_caught_msg, 'close_shift:')$q$) > 0,
            'like_record_payment', pg_get_functiondef('app.sync_push(uuid, uuid, jsonb)'::regprocedure)
                                   ~* $q$like\s+'record_payment:%'$q$,
            'like_close_shift', pg_get_functiondef('app.sync_push(uuid, uuid, jsonb)'::regprocedure)
                                ~* $q$like\s+'close_shift:%'$q$),
          jsonb_build_object('starts_with_record_payment', true, 'starts_with_close_shift', true,
                             'like_record_payment', false, 'like_close_shift', false),
          'RR-179 item 7 (review fix 18): pg_get_functiondef(app.sync_push) contains starts_with(v_caught_msg, ''record_payment:'') and starts_with(v_caught_msg, ''close_shift:'') and no LIKE ''record_payment:%'' / ''close_shift:%'' pattern (an underscore is no longer a wildcard)');

-- ===========================================================================
-- S. The identity-first gate with the binding retired and with no binding row
--    (SECURITY:325): a freed-then-approved, a declined, an unknown and a
--    released identity are each refused with their token and record nothing.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim(l, l) from unnest(array['vgf', 'vgd', 'vgu', 'vgr', 'vdv']) l;
insert into _zc_r select 'f-vgd', pg_temp.rr_fin('vgd', 'commit', 'declined', '{"approval_type": "declined"}');
insert into _zc_r select 'f-vgu', pg_temp.rr_fin('vgu', 'commit', 'unknown');
insert into _zc_r select 'f-vgr', pg_temp.rr_fin('vgr', 'release', 'released');
insert into _zc_r select 'f-vgf-u', pg_temp.rr_fin('vgf', 'commit', 'unknown');
insert into _zc_r select 'f-vgf-l', pg_temp.rr_fin('vgf', 'lookup', 'failed', '{}', 'operator');
insert into _zc_r select 'free-vgf', pg_temp.rr_free('vgf');
insert into _zc_r select 'f-vgf-ap', pg_temp.rr_fin('vgf', 'lookup', 'approved',
  '{"provider_status_code": "ok1", "provider_amount": "12.34", "provider_currency": "ILS", "error_flag": false}', 'operator');
-- vdv is section T's attempt, claimed and approved here while d1 still admits claims.
insert into _zc_r select 'f-vdv', pg_temp.rr_fin('vdv', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
-- The RPC drains d1's binding but refuses its retirement while attempts are unresolved, so the
-- retirement is a test-only owner update (the guard trigger allows draining -> retired).
insert into _zc_r select 'bind-s-drain', pg_temp.rr_bind_step('live', 'draining', 'end_of_pilot');
insert into _zc_r select 'bind-s-retire', pg_temp.rr_bind_step('live', 'retired', 'end_of_pilot');
update app.payment_terminals t set lifecycle = 'retired'
 where t.organization_id = pg_temp.zc_org() and t.device_id = pg_temp.zc_id('device-1') and t.lifecycle = 'draining';
select is(jsonb_build_object(
            'attempts', (select jsonb_object_agg(l, jsonb_build_object('state', (pg_temp.rr_att(l)).state,
                                                    'freed', (pg_temp.rr_att(l)).order_freed_at is not null,
                                                    'resolution', (pg_temp.rr_att(l)).resolution))
                           from unnest(array['vgf', 'vgd', 'vgu', 'vgr']) l),
            'drain', pg_temp.rr_r('bind-s-drain') ->> 'new_lifecycle', 'retire_rpc', pg_temp.rr_r('bind-s-retire'),
            'd1_bindings', (select jsonb_agg(t.lifecycle order by t.created_at) from app.payment_terminals t
                             where t.organization_id = pg_temp.zc_org() and t.device_id = pg_temp.zc_id('device-1')),
            'posture', app.card_terminal_posture(pg_temp.zc_org(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'))),
          jsonb_build_object(
            'attempts', jsonb_build_object(
              'vgf', jsonb_build_object('state', 'approved', 'freed', true, 'resolution', null::text),
              'vgd', jsonb_build_object('state', 'declined', 'freed', false, 'resolution', null::text),
              'vgu', jsonb_build_object('state', 'unknown', 'freed', false, 'resolution', null::text),
              'vgr', jsonb_build_object('state', 'released', 'freed', false, 'resolution', null::text)),
            'drain', 'draining',
            'retire_rpc', jsonb_build_object('ok', false, 'error', 'precondition_failed', 'detail', 'attempt_unresolved'),
            'd1_bindings', '["retired", "retired", "retired"]'::jsonb, 'posture', null::jsonb),
          'RR-180 setup (item 2): d1 attempts freed-then-approved (evidence free, then a late exact approval), declined, unknown and released; d1''s LIVE binding is drained by the RPC (whose retirement is refused attempt_unresolved) and retired by a test-only owner update: every d1 binding row is retired, posture NULL');
select pg_temp.rr_snap('vg');
set local role authenticated;
select pg_temp.rr_push('p-' || l, 1, jsonb_build_array(pg_temp.rr_leg(l))) from unnest(array['vgf', 'vgd', 'vgu', 'vgr']) l;
reset role;
select is(jsonb_build_object('freed_then_approved', pg_temp.rr_ts(pg_temp.rr_res('p-vgf')),
                             'declined', pg_temp.rr_ts(pg_temp.rr_res('p-vgd')),
                             'unknown', pg_temp.rr_ts(pg_temp.rr_res('p-vgu')),
                             'released', pg_temp.rr_ts(pg_temp.rr_res('p-vgr'))),
          jsonb_build_object('freed_then_approved', pg_temp.rr_refusal('vgf', 'vgf', 'provider_recording_refused', 'attempt_freed'),
                             'declined', pg_temp.rr_refusal('vgd', 'vgd', 'provider_recording_refused', 'attempt_not_approved'),
                             'unknown', pg_temp.rr_refusal('vgu', 'vgu', 'provider_recording_refused', 'attempt_not_approved'),
                             'released', pg_temp.rr_refusal('vgr', 'vgr', 'provider_recording_refused', 'attempt_not_approved')),
          'RR-181 item 2 (SECURITY:325, binding retired): the canonical card legs of the freed-then-approved, declined, unknown and released identities pushed by d1''s cashier are refused provider_recording_refused / attempt_freed, attempt_not_approved, attempt_not_approved, attempt_not_approved (error, detail, server_ts, order_id only)');
select is(jsonb_build_object('rows', (select jsonb_object_agg(l, jsonb_build_object('so', (pg_temp.rr_so(l)).status,
                                                   'reason', (pg_temp.rr_so(l)).rejection_reason, 'payments', pg_temp.rr_pay_n(l),
                                                   'order_payments', pg_temp.rr_order_pay_n(l)))
                                       from unnest(array['vgf', 'vgd', 'vgu', 'vgr']) l),
                             'audit', pg_temp.rr_delta('vg')),
          jsonb_build_object('rows', jsonb_build_object(
                               'vgf', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0),
                               'vgd', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0),
                               'vgu', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0),
                               'vgr', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0)),
                             'audit', jsonb_build_object('sync.operation_rejected', 4)),
          'RR-182 item 2 (binding retired): those four refusals record zero payments (none under the identities, none on their orders); each is a rejected sync row with one sync.operation_rejected audit and nothing else');

-- No binding row: d2 has never held a payment_terminals row. A claim always runs under an enabled
-- binding and binding rows are never deleted, so these four LIVE attempt rows of d2 are seeded as owner
-- (the insert guard's fresh sent row with the exact digests and keys, frozen to a fresh open shift and
-- active drawer of d2); their facts then move through the scope-bound finish and a d2 manager's
-- evidence free exactly as a claimed row's would.
insert into public.shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id,
    resolved_membership_id, local_operation_id, status)
values (pg_temp.zc_id('rr-shift-d2'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-2'),
    pg_temp.zc_id('employee-8'), pg_temp.zc_id('membership-8'), 'rr-shift-d2', 'open');
insert into public.cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id,
    opened_by_employee_profile_id, opening_float_minor, local_operation_id)
values (pg_temp.zc_id('rr-drawer-d2'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-2'),
    pg_temp.zc_id('rr-shift-d2'), pg_temp.zc_id('employee-8'), 0, 'rr-drawer-d2');
insert into _zc_r select 'orders-d2-v', jsonb_agg(pg_temp.zc_order(l, 1234, 2)) from unnest(array['vnf', 'vnd', 'vnu', 'vnr']) l;
insert into app.card_provider_attempts (organization_id, restaurant_id, branch_id, device_id, local_operation_id, order_id,
    shift_id, cash_drawer_session_id, initiated_by_employee_profile_id, initiated_by_membership_id, mode, amount_minor,
    currency_code, expected_revision, terminal_ref, credential_ref, provider_status_digest, provider_duplicate_digest,
    provider_key_format_version, provider_query_key, provider_duplicate_key, start_deadline_at)
select pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-2'), pg_temp.zc_lop(l),
       pg_temp.rr_ord(l), pg_temp.zc_id('rr-shift-d2'), pg_temp.zc_id('rr-drawer-d2'), pg_temp.zc_id('employee-8'),
       pg_temp.zc_id('membership-8'), 'live', 1234, 'ILS', 1, 'zc-term-live-2', 'zc-cred-live-2', k.sd, k.dd,
       'alpha16-l32-v1', app.card_provider_key(k.sd, 'alpha16-l32-v1'), app.card_provider_key(k.dd, 'alpha16-l32-v1'),
       clock_timestamp() + interval '120 seconds'
  from unnest(array['vnf', 'vnd', 'vnu', 'vnr']) l
  cross join lateral (select app.card_identity_digest('card-status-key/v1', pg_temp.zc_org(), pg_temp.zc_id('device-2'),
                                                      pg_temp.zc_lop(l)) as sd,
                             app.card_identity_digest('card-duplicate-key/v1', pg_temp.zc_org(), pg_temp.zc_id('device-2'),
                                                      pg_temp.zc_lop(l)) as dd) k;
create function pg_temp.rr_att2(label text) returns app.card_provider_attempts language sql stable as
$$ select a from app.card_provider_attempts a
    where a.organization_id = pg_temp.zc_org() and a.device_id = pg_temp.zc_id('device-2')
      and a.local_operation_id = pg_temp.zc_lop(rr_att2.label) $$;
-- The claim-shaped facts the scope-bound finish takes (read as owner: service_role cannot read app.*).
insert into _zc_r select 'c-' || l, jsonb_build_object('attempt_row_id', a.id, 'organization_id', a.organization_id,
    'device_id', a.device_id, 'local_operation_id', a.local_operation_id, 'mode', a.mode,
    'amount_minor', a.amount_minor, 'currency_code', a.currency_code)
  from unnest(array['vnf', 'vnd', 'vnu', 'vnr']) l cross join lateral pg_temp.rr_att2(l) a;
set local role service_role;
insert into _zc_r select 'f-vnd', pg_temp.rr_fin('vnd', 'commit', 'declined', '{"approval_type": "declined"}');
insert into _zc_r select 'f-vnu', pg_temp.rr_fin('vnu', 'commit', 'unknown');
insert into _zc_r select 'f-vnr', pg_temp.rr_fin('vnr', 'release', 'released');
insert into _zc_r select 'f-vnf-u', pg_temp.rr_fin('vnf', 'commit', 'unknown');
insert into _zc_r select 'f-vnf-l', pg_temp.rr_fin('vnf', 'lookup', 'failed', '{}', 'operator');
insert into _zc_r select 'free-vnf', public.card_attempt_free_order(pg_temp.zc_id('pin-3'), pg_temp.zc_id('device-2'),
  'zc-token-2', pg_temp.zc_lop('vnf'), 'ZC001D synthetic evidence free', 'provider_report', 'zc-free-vnf', pg_temp.zc_caller());
insert into _zc_r select 'f-vnf-ap', pg_temp.rr_fin('vnf', 'lookup', 'approved',
  '{"provider_status_code": "ok1", "provider_amount": "12.34", "provider_currency": "ILS", "error_flag": false}', 'operator');
reset role;
select is(jsonb_build_object('d2_binding_rows', (select count(*) from app.payment_terminals t
                                                  where t.device_id = pg_temp.zc_id('device-2')),
                             'free', pg_temp.rr_r('free-vnf') ->> 'classification',
                             'attempts', (select jsonb_object_agg(l, jsonb_build_object('state', (pg_temp.rr_att2(l)).state,
                                                    'freed', (pg_temp.rr_att2(l)).order_freed_at is not null))
                                            from unnest(array['vnf', 'vnd', 'vnu', 'vnr']) l)),
          jsonb_build_object('d2_binding_rows', 0, 'free', 'freed',
                             'attempts', jsonb_build_object(
                               'vnf', jsonb_build_object('state', 'approved', 'freed', true),
                               'vnd', jsonb_build_object('state', 'declined', 'freed', false),
                               'vnu', jsonb_build_object('state', 'unknown', 'freed', false),
                               'vnr', jsonb_build_object('state', 'released', 'freed', false))),
          'RR-183 setup (item 2): d2 holds no payment_terminals row; its four owner-seeded LIVE attempts moved through the scope-bound finish and a d2 manager''s evidence free to freed-then-approved, declined, unknown and released');
select pg_temp.rr_snap('vn');
set local role authenticated;
select pg_temp.rr_push('p-' || l, 8, jsonb_build_array(pg_temp.rr_leg(l)), 2) from unnest(array['vnf', 'vnd', 'vnu', 'vnr']) l;
reset role;
select is(jsonb_build_object('freed_then_approved', pg_temp.rr_ts(pg_temp.rr_res('p-vnf')),
                             'declined', pg_temp.rr_ts(pg_temp.rr_res('p-vnd')),
                             'unknown', pg_temp.rr_ts(pg_temp.rr_res('p-vnu')),
                             'released', pg_temp.rr_ts(pg_temp.rr_res('p-vnr'))),
          jsonb_build_object('freed_then_approved', pg_temp.rr_refusal('vnf', 'vnf', 'provider_recording_refused', 'attempt_freed'),
                             'declined', pg_temp.rr_refusal('vnd', 'vnd', 'provider_recording_refused', 'attempt_not_approved'),
                             'unknown', pg_temp.rr_refusal('vnu', 'vnu', 'provider_recording_refused', 'attempt_not_approved'),
                             'released', pg_temp.rr_refusal('vnr', 'vnr', 'provider_recording_refused', 'attempt_not_approved')),
          'RR-184 item 2 (SECURITY:325, no binding row): the canonical card legs pushed by d2''s cashier (staff 8) for the freed-then-approved, declined, unknown and released identities are refused provider_recording_refused / attempt_freed, attempt_not_approved, attempt_not_approved, attempt_not_approved');
select is(jsonb_build_object('rows', (select jsonb_object_agg(l, jsonb_build_object('so', (pg_temp.rr_so(l, 2)).status,
                                                   'reason', (pg_temp.rr_so(l, 2)).rejection_reason,
                                                   'payments', (select count(*) from public.payments p
                                                                 where p.device_id = pg_temp.zc_id('device-2')
                                                                   and p.local_operation_id = pg_temp.zc_lop(l)),
                                                   'order_payments', pg_temp.rr_order_pay_n(l)))
                                       from unnest(array['vnf', 'vnd', 'vnu', 'vnr']) l),
                             'audit', pg_temp.rr_delta('vn')),
          jsonb_build_object('rows', jsonb_build_object(
                               'vnf', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0),
                               'vnd', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0),
                               'vnu', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0),
                               'vnr', jsonb_build_object('so', 'rejected', 'reason', 'provider_recording_refused', 'payments', 0, 'order_payments', 0)),
                             'audit', jsonb_build_object('sync.operation_rejected', 4)),
          'RR-185 item 2 (no binding row): those four refusals record zero payments; each is a rejected sync row of d2 with one sync.operation_rejected audit and nothing else');

-- ===========================================================================
-- T. Device-revocation derivations (DOMAIN 8.4 device_revoked /
--    device_session_unavailable; D-057 point 7). Last: d1 is revoked here.
-- ===========================================================================
select is(pg_temp.rr_derive('vdv'),
          jsonb_build_object('recorded', false, 'payment_id', null, 'classification', 'approved_unrecorded',
                             'reason', 'pending_recording', 'recoverable', false, 'claim_active', true,
                             'blocks_close', true, 'unresolved', true),
          'RR-186 setup (item 3): an approved LIVE attempt of d1 whose leg was never pushed (vdv) derives approved_unrecorded / pending_recording while d1 holds its active pairing and session');
update public.device_pairings dp set status = 'suspended' where dp.id = pg_temp.zc_id('pairing-1');
set local role authenticated;
insert into _zc_r select 'ctx-vdv-susp', public.card_attempt_context(pg_temp.zc_id('pin-3'), pg_temp.zc_id('device-2'),
  'zc-token-2', null, pg_temp.zc_lop('vdv'));
reset role;
select is(jsonb_build_object('derive', pg_temp.rr_derive('vdv'),
                             'envelope', app.card_attempt_envelope(pg_temp.rr_att('vdv')) - 'server_ts',
                             'context_attempt', pg_temp.rr_r('ctx-vdv-susp') -> 'attempt'),
          jsonb_build_object('derive', jsonb_build_object('recorded', false, 'payment_id', null,
                                         'classification', 'approved_unrecorded', 'reason', 'device_session_unavailable',
                                         'recoverable', false, 'claim_active', true, 'blocks_close', true, 'unresolved', true),
                             'envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vdv'), 'state', 'approved',
                                         'classification', 'approved_unrecorded', 'recorded', false,
                                         'provider_return_code', 0, 'recoverable', false, 'resume_count', 0,
                                         'amount_minor', 1234, 'currency_code', 'ILS'),
                             'context_attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('vdv'), 'state', 'approved',
                                         'classification', 'approved_unrecorded', 'recorded', false,
                                         'provider_return_code', 0, 'recoverable', false, 'resume_count', 0,
                                         'amount_minor', 1234, 'currency_code', 'ILS', 'mode', 'live', 'own_device', false)),
          'RR-187 item 3: with d1''s pairing suspended (the device record still active) the attempt derives device_session_unavailable: approved_unrecorded (not an orphan reason), not recoverable; the envelope and the d2 manager''s context read (own_device false) report approved_unrecorded / recoverable false');
update public.device_pairings dp set status = 'active' where dp.id = pg_temp.zc_id('pairing-1');
-- A replaced pairing: d1's pairing and its session revoked, a new pairing still code_issued (no session yet).
update public.device_pairings dp set status = 'revoked', revoked_at = now() where dp.id = pg_temp.zc_id('pairing-1');
update public.device_sessions ds set is_active = false, revoked_at = now() where ds.id = pg_temp.zc_id('dsession-1');
insert into public.device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, code_expires_at)
values (pg_temp.zc_id('pairing-1-r'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
        'code_issued', now() + interval '10 minutes');
select is(pg_temp.rr_derive('vdv'),
          jsonb_build_object('recorded', false, 'payment_id', null, 'classification', 'approved_unrecorded',
                             'reason', 'device_session_unavailable', 'recoverable', false, 'claim_active', true,
                             'blocks_close', true, 'unresolved', true),
          'RR-188 item 3: with d1''s pairing replaced (the old pairing and its session revoked, the new pairing still code_issued with no session) the attempt derives device_session_unavailable (approved_unrecorded, not recoverable)');
update public.device_pairings dp set status = 'active', paired_at = now() where dp.id = pg_temp.zc_id('pairing-1-r');
insert into public.device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                                    session_token_ref, expires_at)
values (pg_temp.zc_id('dsession-1-r'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
        pg_temp.zc_id('pairing-1-r'), app.hash_provisioning_secret('zc-token-1-r'), now() + interval '30 days');
select is(pg_temp.rr_derive('vdv'),
          jsonb_build_object('recorded', false, 'payment_id', null, 'classification', 'approved_unrecorded',
                             'reason', 'pending_recording', 'recoverable', false, 'claim_active', true,
                             'blocks_close', true, 'unresolved', true),
          'RR-189 item 3: once d1 is re-paired (the new pairing active with an active device session) the reason is pending_recording again: device_session_unavailable is not sticky');
-- app.revoke_device_management by d1's manager (staff 2) through a JWT principal linked to that app user.
insert into auth.users (id, email) values (pg_temp.zc_id('rr-auth-manager'), 'zc001d-rr-manager@example.test');
update public.app_users u set auth_user_id = pg_temp.zc_id('rr-auth-manager') where u.id = pg_temp.zc_id('user-2');
select pg_temp.rr_snap('vdv-rev');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('rr-auth-manager')::text, true);
set local role authenticated;
insert into _zc_r select 'revoke-d1', public.revoke_device_management(pg_temp.zc_id('rr-revoke-request'),
  pg_temp.zc_id('device-1'), 'ZC001D synthetic dead till');
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
set local role authenticated;
insert into _zc_r select 'ctx-vdv-rev', public.card_attempt_context(pg_temp.zc_id('pin-3'), pg_temp.zc_id('device-2'),
  'zc-token-2', null, pg_temp.zc_lop('vdv'));
reset role;
select is(jsonb_build_object('revoke', pg_temp.rr_r('revoke-d1'),
                             'device_active', (select d.is_active from public.devices d where d.id = pg_temp.zc_id('device-1')),
                             'audit', pg_temp.rr_delta('vdv-rev'),
                             'derive', pg_temp.rr_derive('vdv'),
                             'envelope', app.card_attempt_envelope(pg_temp.rr_att('vdv')) - 'server_ts',
                             'context_attempt', pg_temp.rr_r('ctx-vdv-rev') -> 'attempt'),
          jsonb_build_object('revoke', jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device',
                                         'device_id', pg_temp.zc_id('device-1'), 'pairings_revoked', 1, 'sessions_revoked', 1),
                             'device_active', false,
                             'audit', jsonb_build_object('device.revoked_management', 1),
                             'derive', jsonb_build_object('recorded', false, 'payment_id', null,
                                         'classification', 'orphan_approved', 'reason', 'device_revoked',
                                         'recoverable', false, 'claim_active', true, 'blocks_close', true, 'unresolved', true),
                             'envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('vdv'), 'state', 'approved',
                                         'classification', 'orphan_approved', 'recorded', false,
                                         'provider_return_code', 0, 'recoverable', false, 'resume_count', 0,
                                         'amount_minor', 1234, 'currency_code', 'ILS'),
                             'context_attempt', jsonb_build_object('attempt_id', pg_temp.zc_lop('vdv'), 'state', 'approved',
                                         'classification', 'orphan_approved', 'recorded', false,
                                         'provider_return_code', 0, 'recoverable', false, 'resume_count', 0,
                                         'amount_minor', 1234, 'currency_code', 'ILS', 'mode', 'live', 'own_device', false)),
          'RR-190 item 3: after app.revoke_device_management on d1 (a manager''s JWT: the device record set inactive, its live pairing and session revoked, one device.revoked_management audit) the attempt derives device_revoked: orphan_approved, not recoverable (device_revoked precedes device_session_unavailable); the envelope and the d2 manager''s context read report orphan_approved / recoverable false');
insert into public.device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at)
values (pg_temp.zc_id('pairing-1-s'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
        'active', now());
insert into public.device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                                    session_token_ref, expires_at)
values (pg_temp.zc_id('dsession-1-s'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
        pg_temp.zc_id('pairing-1-s'), app.hash_provisioning_secret('zc-token-1-s'), now() + interval '30 days');
select is(jsonb_build_object('derive', pg_temp.rr_derive('vdv'),
                             'device_active', (select d.is_active from public.devices d where d.id = pg_temp.zc_id('device-1'))),
          jsonb_build_object('derive', jsonb_build_object('recorded', false, 'payment_id', null,
                                         'classification', 'orphan_approved', 'reason', 'device_revoked',
                                         'recoverable', false, 'claim_active', true, 'blocks_close', true, 'unresolved', true),
                             'device_active', false),
          'RR-191 item 3: device_revoked is sticky: an active pairing with an active device session added afterwards (owner insert) leaves the reason device_revoked while the device record stays inactive');

-- ===========================================================================
-- U. Batch 5 setup (TEST_BRIEF_3, lane RR-B5). d1 is management-revoked since
--    section T (device_revoked is sticky; no phase-1 path re-activates it), so
--    sections V-W run on d2: its cashier (staff 8) claims and reports, its
--    manager (staff 3) resumes, and its only open shift / active drawer is
--    rr-shift-d2 / rr-drawer-d2 (section S). The operator RPC configures d2's
--    LIVE binding but refuses to enable it while section S's seeded d2 attempts
--    are unresolved, so a test-only owner update enables it (as section M did for
--    d1; the payment_terminals guard trigger allows configured -> enabled). The
--    only owner writes in U-W are that enable and the revoke / restore of the
--    d2 cashier's membership that produces each refusal (as RS11 / vfb): no owner
--    update touches an attempt, a sync row, a report or a Resume timestamp.
-- ===========================================================================
insert into _zc_r select 'bind-u-cfg', pg_temp.zc_bind(2, 'live', 'configured');
insert into _zc_r select 'bind-u-en', app.set_payment_terminal(pg_temp.zc_id('device-2'), 'live', 'zc-term-live-2',
  'zc-cred-live-2', 'enabled', 'live_activation', 'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner());
update app.payment_terminals t set lifecycle = 'enabled'
 where t.organization_id = pg_temp.zc_org() and t.device_id = pg_temp.zc_id('device-2') and t.lifecycle = 'configured';
insert into _zc_r select 'orders-u', jsonb_agg(pg_temp.zc_order(l, 1234, 2)) from unnest(array['xt1', 'xf2']) l;
-- d2 lookups (rr_att2 is section S's) and the d2 service-only calls as the adapter makes them.
create function pg_temp.rr_derive2(label text) returns jsonb language sql stable as
$$ select app.card_attempt_derive(pg_temp.rr_att2(rr_derive2.label)) $$;
create function pg_temp.rr_pay2_n(label text) returns bigint language sql stable as
$$ select count(*) from public.payments p
    where p.device_id = pg_temp.zc_id('device-2') and p.local_operation_id = pg_temp.zc_lop(rr_pay2_n.label) $$;
create function pg_temp.rr_resume_state2(label text) returns jsonb language sql stable as
$$ select jsonb_build_object('so', so.status, 'retry_count', so.retry_count, 'resume_count', a.recording_resume_count,
                             'resume_history', jsonb_array_length(a.recording_resume_history),
                             'refusal_history', jsonb_array_length(a.recording_refusal_history),
                             'payments', pg_temp.rr_pay2_n(rr_resume_state2.label))
     from pg_temp.rr_so(rr_resume_state2.label, 2) so cross join pg_temp.rr_att2(rr_resume_state2.label) a $$;
create function pg_temp.rr_ev2_n(label text) returns bigint language sql stable as
$$ select count(*) from app.card_provider_private_events e where e.attempt_row_id = (pg_temp.rr_att2(rr_ev2_n.label)).id $$;
create function pg_temp.rr_claim2(label text) returns jsonb language sql volatile as
$$ select pg_temp.zc_claim(8, pg_temp.zc_lop(label), 'live', 1234, pg_temp.rr_ord(label), 1) $$;
create function pg_temp.rr_markrec2(label text, n integer default 8, hint text default 'rejected') returns jsonb
language sql volatile as
$$ select public.card_attempt_mark_recording_result(pg_temp.zc_id('pin-' || n), pg_temp.zc_id('device-2'),
     'zc-token-2', pg_temp.zc_lop(label), hint, pg_temp.zc_caller()) $$;
select is(jsonb_build_object('configured', pg_temp.rr_r('bind-u-cfg'), 'enable_rpc', pg_temp.rr_r('bind-u-en'),
                             'd2_bindings', (select jsonb_agg(jsonb_build_object('mode', t.mode, 'lifecycle', t.lifecycle,
                                                                                 'terminal_ref', t.terminal_ref))
                                               from app.payment_terminals t where t.device_id = pg_temp.zc_id('device-2')),
                             'posture', app.card_terminal_posture(pg_temp.zc_org(), pg_temp.zc_branch(), pg_temp.zc_id('device-2')),
                             'open_shift', (select jsonb_agg(s.id) from public.shifts s
                                             where s.organization_id = pg_temp.zc_org() and s.device_id = pg_temp.zc_id('device-2')
                                               and s.status in ('opening', 'open', 'closing')),
                             'active_drawer', (select jsonb_agg(c.id) from public.cash_drawer_sessions c
                                                where c.organization_id = pg_temp.zc_org() and c.device_id = pg_temp.zc_id('device-2')
                                                  and c.status = 'active'),
                             'd1_active', (select d.is_active from public.devices d where d.id = pg_temp.zc_id('device-1'))),
          jsonb_build_object('configured', jsonb_build_object('ok', true, 'changed', true, 'binding_mode', 'live',
                                             'prior_lifecycle', null, 'new_lifecycle', 'configured'),
                             'enable_rpc', jsonb_build_object('ok', false, 'error', 'precondition_failed', 'detail', 'attempt_unresolved'),
                             'd2_bindings', jsonb_build_array(jsonb_build_object('mode', 'live', 'lifecycle', 'enabled',
                                                                                 'terminal_ref', 'zc-term-live-2')),
                             'posture', jsonb_build_object('lifecycle', 'enabled', 'mode', 'live', 'enabled', true),
                             'open_shift', jsonb_build_array(pg_temp.zc_id('rr-shift-d2')),
                             'active_drawer', jsonb_build_array(pg_temp.zc_id('rr-drawer-d2')),
                             'd1_active', false),
          'RR-192 setup (batch 5, TEST_BRIEF_3 lane RR-B5): d1 stays revoked (section T), so batch 5 runs on d2: the operator RPC configures d2''s LIVE binding and refuses its enable (attempt_unresolved: section S''s seeded d2 attempts), a test-only owner update enables it (posture enabled / live, starts admitted); d2''s only open shift and active drawer are rr-shift-d2 / rr-drawer-d2');

-- ===========================================================================
-- V. Batch 5 item 1 (change 19): the FIRST Resume's forced 40P01 leaves the
--    reopened leg pending, so the attempt derives approved_unrecorded /
--    pending_recording, recoverable false, its stored refusal kept (before batch
--    5 it derived recording_refused, recoverable true); a manager resend then
--    records once. With item 3 on a fresh report: a second mark of the same
--    token, with no Resume between, neither re-stamps nor audits.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-xt1', pg_temp.rr_claim2('xt1');
insert into _zc_r select 'f-xt1', pg_temp.rr_fin('xt1', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
-- The own leg pushed by the cashier (staff 8) while that membership is revoked: record_payment's raise,
-- memoized revoked_employee (as RS11 / vfb); the membership restored right after.
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-8');
set local role authenticated;
select pg_temp.rr_push('p-xt1-k', 8, jsonb_build_array(pg_temp.rr_leg('xt1')), 2);
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-8');
select pg_temp.rr_snap('xt1m1');
set local role service_role;
insert into _zc_r select 'm-xt1-1', pg_temp.rr_markrec2('xt1');
reset role;
insert into _zc_r select 'row-xt1-1', to_jsonb(pg_temp.rr_att2('xt1'));
insert into _zc_r select 'ev-xt1-1', to_jsonb(pg_temp.rr_ev2_n('xt1'));
select is(jsonb_build_object('claim_created', pg_temp.rr_r('c-xt1') -> 'claim_created',
                             'frozen', jsonb_build_object('device', (pg_temp.rr_att2('xt1')).device_id,
                                         'shift', (pg_temp.rr_att2('xt1')).shift_id,
                                         'drawer', (pg_temp.rr_att2('xt1')).cash_drawer_session_id,
                                         'initiator', (pg_temp.rr_att2('xt1')).initiated_by_employee_profile_id),
                             'state', (pg_temp.rr_att2('xt1')).state,
                             'push', pg_temp.rr_res('p-xt1-k'), 'so', pg_temp.rr_so_state('xt1', 2),
                             'mark', pg_temp.rr_ts(pg_temp.rr_r('m-xt1-1')),
                             'stored', (pg_temp.rr_att2('xt1')).refusal_code,
                             'stamped', (pg_temp.rr_att2('xt1')).recording_refused_at is not null,
                             'audit', pg_temp.rr_delta('xt1m1')),
          jsonb_build_object('claim_created', true,
                             'frozen', jsonb_build_object('device', pg_temp.zc_id('device-2'), 'shift', pg_temp.zc_id('rr-shift-d2'),
                                         'drawer', pg_temp.zc_id('rr-drawer-d2'), 'initiator', pg_temp.zc_id('employee-8')),
                             'state', 'approved',
                             'push', jsonb_build_object('local_operation_id', pg_temp.zc_lop('xt1'), 'operation_type', 'payment.create',
                                       'ok', false, 'error', 'rejected', 'sqlstate', '42501', 'detail', 'revoked_employee',
                                       'status', 'rejected', 'idempotency_replay', false),
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', '42501', 'retry_count', 0,
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', '42501',
                                                                  'detail', 'revoked_employee'),
                                     'reason', 'revoked_employee'),
                             'mark', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('xt1'), 'state', 'approved',
                                       'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                       'refusal_code', 'revoked_employee', 'recoverable', true, 'resume_count', 0,
                                       'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'stored', 'revoked_employee', 'stamped', true,
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1)),
          'RR-193 setup (batch 5 item 1): a LIVE attempt claimed by d2''s cashier (frozen to rr-shift-d2 / rr-drawer-d2) and approved; its own leg pushed while that cashier''s membership was revoked is memoized rejected revoked_employee (42501); card_attempt_mark_recording_result reports it: refusal_code revoked_employee + recording_refused_at, recoverable at count 0, exactly one card_attempt.recording_refused audit');
select pg_temp.rr_snap('xt1m2');
set local role service_role;
insert into _zc_r select 'm-xt1-2', pg_temp.rr_markrec2('xt1');
reset role;
select is(jsonb_build_object('envelope', pg_temp.rr_ts(pg_temp.rr_r('m-xt1-2')),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('xt1')) = pg_temp.rr_r('row-xt1-1'),
                             'audit', pg_temp.rr_delta('xt1m2'),
                             'events', pg_temp.rr_ev2_n('xt1') - (pg_temp.rr_r('ev-xt1-1') #>> '{}')::bigint),
          jsonb_build_object('envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('xt1'), 'state', 'approved',
                                           'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                           'refusal_code', 'revoked_employee', 'recoverable', true, 'resume_count', 0,
                                           'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'row_unchanged', true, 'audit', '{}'::jsonb, 'events', 0),
          'RR-194 item 3 (batch 5, fresh report; change 20 freshness not met): a second card_attempt_mark_recording_result of the same token with no Resume between answers the same envelope and neither re-stamps nor audits: the attempt row is identical (recording_refused_at kept), no audit row, no private event');
select pg_temp.rr_snap('xt1r');
set local role authenticated;
select pg_temp.rr_push_fault('p-xt1-r', 3, jsonb_build_array(pg_temp.rr_leg('xt1', 'xt1', '{"recording_resume": 0}')),
                             'payments', '40P01', null, 2);
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-xt1-r'), 'so', pg_temp.rr_so_state('xt1', 2),
                             'resume', pg_temp.rr_resume_state2('xt1'),
                             'resume_entry', ((pg_temp.rr_att2('xt1')).recording_resume_history -> 0) - 'at',
                             'refusal_entry', (pg_temp.rr_att2('xt1')).recording_refusal_history -> 0,
                             'audit', pg_temp.rr_delta('xt1r')),
          jsonb_build_object('result', pg_temp.rr_pending('xt1', 'payment.create', 'transient_failure'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', '40P01', 'retry_count', 1,
                                     'result', null::jsonb, 'reason', null::text),
                             'resume', jsonb_build_object('so', 'pending', 'retry_count', 1, 'resume_count', 1,
                                         'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'resume_entry', jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-3'),
                                               'membership_id', pg_temp.zc_id('membership-3'), 'resume_count', 0),
                             'refusal_entry', jsonb_build_object('refusal_code', 'revoked_employee',
                                                'refused_at', pg_temp.rr_r('row-xt1-1') -> 'recording_refused_at'),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-195 setup (batch 5 item 1): the FIRST Resume (d2''s manager, staff 3, recording_resume 0) is authorized and its re-dispatch meets a forced 40P01 on the payments insert: exactly {ok:false, error:transient_failure, retryable:true, status:pending}; the reopened row is back at pending (transient, 40P01, result and rejection reason cleared, retry_count 1 from the adopt path); count 1 with one entry in each history; no payment; the only audit row is the dispatched card_attempt.recording_resume_requested');
select is(pg_temp.rr_derive2('xt1'),
          jsonb_build_object('recorded', false, 'payment_id', null, 'classification', 'approved_unrecorded',
                             'reason', 'pending_recording', 'recoverable', false, 'claim_active', true,
                             'blocks_close', true, 'unresolved', true),
          'RR-196 item 1 (change 19; DOMAIN 8.4 "a row back to pending after a transient failure stays pending_recording until it is dispatched"): after the first Resume''s forced 40P01 app.card_attempt_derive is exactly approved_unrecorded / pending_recording, recoverable false: the stored revoked_employee refusal is not the current reason while the identity''s sync row is pending (it derived recording_refused, recoverable true, before batch 5)');
select is(jsonb_build_object('envelope', app.card_attempt_envelope(pg_temp.rr_att2('xt1')) - 'server_ts',
                             'refusal_code', (pg_temp.rr_att2('xt1')).refusal_code,
                             'refused_at_kept', (pg_temp.rr_att2('xt1')).recording_refused_at
                                                = (pg_temp.rr_r('row-xt1-1') ->> 'recording_refused_at')::timestamptz),
          jsonb_build_object('envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('xt1'), 'state', 'approved',
                                           'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                           'refusal_code', 'revoked_employee', 'recoverable', false, 'resume_count', 1,
                                           'amount_minor', 1234, 'currency_code', 'ILS'),
                             'refusal_code', 'revoked_employee', 'refused_at_kept', true),
          'RR-197 item 1 (change 19): the envelope is exact: approved_unrecorded, recorded false, recoverable false, resume_count 1, and refusal_code still the stored revoked_employee (review fix 6: the Resume guard never clears the report; recording_refused_at keeps its pre-Resume value)');
select pg_temp.rr_snap('xt1m');
set local role authenticated;
select pg_temp.rr_push('p-xt1-m', 3, jsonb_build_array(pg_temp.rr_leg('xt1')), 2);
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-xt1-m') ->> 'status', 'resume', pg_temp.rr_resume_state2('xt1'),
                             'derive', pg_temp.rr_derive2('xt1') - 'payment_id',
                             'strict_join', (pg_temp.rr_derive2('xt1') ->> 'payment_id')::uuid
                                            = (select p.id from public.payments p where p.device_id = pg_temp.zc_id('device-2')
                                                  and p.local_operation_id = pg_temp.zc_lop('xt1')),
                             'taken_by', (select p.taken_by_employee_profile_id from public.payments p
                                           where p.device_id = pg_temp.zc_id('device-2')
                                             and p.local_operation_id = pg_temp.zc_lop('xt1')),
                             'card_sync_audit', pg_temp.rr_delta('xt1m', 'card_attempt.%') || pg_temp.rr_delta('xt1m', 'sync.%')),
          jsonb_build_object('status', 'applied',
                             'resume', jsonb_build_object('so', 'applied', 'retry_count', 2, 'resume_count', 1,
                                         'resume_history', 1, 'refusal_history', 1, 'payments', 1),
                             'derive', jsonb_build_object('recorded', true, 'classification', 'recorded', 'reason', null,
                                         'recoverable', false, 'claim_active', false, 'blocks_close', false, 'unresolved', false),
                             'strict_join', true, 'taken_by', pg_temp.zc_id('employee-3'), 'card_sync_audit', '{}'::jsonb),
          'RR-198 item 1: a manager resend of the plain leg adopts the pending row once and records exactly one card payment in the frozen shift / drawer (the strict join; the manager its actor); no further Resume is consumed (count 1) and no card_attempt / sync audit is written');

-- ===========================================================================
-- W. Batch 5 item 2 (change 20): last-Resume freshness WITHOUT any owner
--    timestamp manipulation. A reported revoked_employee refusal; an authorized
--    Resume whose re-dispatch is refused again with the SAME token (the forced
--    P0001 revoked-membership raise on the payments insert). In this single
--    transaction the row's rejection stamp (sync_operations_set_updated_at:
--    now(), the transaction start) never postdates the report, so only the last
--    authorized Resume's at (the guard's clock_timestamp()) shows the report is
--    stale. With item 3 after a Resume and a re-stamp: a second mark of the same
--    token neither re-stamps nor audits.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-xf2', pg_temp.rr_claim2('xf2');
insert into _zc_r select 'f-xf2', pg_temp.rr_fin('xf2', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-8');
set local role authenticated;
select pg_temp.rr_push('p-xf2-k', 8, jsonb_build_array(pg_temp.rr_leg('xf2')), 2);
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-8');
set local role service_role;
insert into _zc_r select 'm-xf2-1', pg_temp.rr_markrec2('xf2');
reset role;
insert into _zc_r select 'att-xf2-1', jsonb_build_object('refusal_code', (pg_temp.rr_att2('xf2')).refusal_code,
                                                          'refused_at', (pg_temp.rr_att2('xf2')).recording_refused_at);
select pg_temp.rr_snap('xf2r1');
set local role authenticated;
select pg_temp.rr_push_fault('p-xf2-r1', 3, jsonb_build_array(pg_temp.rr_leg('xf2', 'xf2', '{"recording_resume": 0}')),
                             'payments', 'P0001', 'zc synthetic: resolved membership is not active', 2);
reset role;
select is(jsonb_build_object('mark', pg_temp.rr_ts(pg_temp.rr_r('m-xf2-1')),
                             'result', pg_temp.rr_res('p-xf2-r1'), 'so', pg_temp.rr_so_state('xf2', 2),
                             'after', pg_temp.rr_resume_state2('xf2'), 'audit', pg_temp.rr_delta('xf2r1'),
                             'dispatched_detail', (select jsonb_agg(e.new_values - 'local_operation_id') from public.audit_events e
                                                    where e.organization_id = pg_temp.zc_org()
                                                      and e.action = 'card_attempt.recording_resume_requested'
                                                      and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('xf2'))),
          jsonb_build_object('mark', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('xf2'), 'state', 'approved',
                                       'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                       'refusal_code', 'revoked_employee', 'recoverable', true, 'resume_count', 0,
                                       'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('xf2'), 'operation_type', 'payment.create',
                                         'ok', false, 'error', 'rejected', 'sqlstate', 'P0001', 'detail', 'revoked_employee',
                                         'status', 'rejected', 'idempotency_replay', false),
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', 'P0001', 'retry_count', 1,
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', 'P0001',
                                                                  'detail', 'revoked_employee'),
                                     'reason', 'revoked_employee'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 1, 'resume_count', 1,
                                        'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1, 'sync.operation_rejected', 1),
                             'dispatched_detail', jsonb_build_array(jsonb_build_object('attempt_state', 'approved',
                                                    'prior_refusal_code', 'revoked_employee', 'resume_count', 0,
                                                    'outcome', 'dispatched'))),
          'RR-199 setup (batch 5 item 2): a reported revoked_employee refusal of d2''s cashier (recoverable, count 0) is resumed by d2''s manager (recording_resume 0) and dispatched once; the re-dispatch is refused again with the SAME token (forced P0001 revoked-membership raise on the payments insert): the same row memoized rejected revoked_employee (retry_count 1), count 1, one dispatched card_attempt.recording_resume_requested and one sync.operation_rejected, no payment');
select is(jsonb_build_object('stored', (pg_temp.rr_att2('xf2')).refusal_code,
                             'same_token', (pg_temp.rr_att2('xf2')).refusal_code = (pg_temp.rr_so('xf2', 2)).rejection_reason,
                             'refused_at_kept', (pg_temp.rr_att2('xf2')).recording_refused_at
                                                = (pg_temp.rr_r('att-xf2-1') ->> 'refused_at')::timestamptz,
                             'report_predates_row_stamp', (pg_temp.rr_att2('xf2')).recording_refused_at
                                                          < (pg_temp.rr_so('xf2', 2)).updated_at,
                             'report_predates_last_resume', (pg_temp.rr_att2('xf2')).recording_refused_at
                                                            < ((pg_temp.rr_att2('xf2')).recording_resume_history -> -1 ->> 'at')::timestamptz,
                             'last_resume', ((pg_temp.rr_att2('xf2')).recording_resume_history -> -1) - 'at',
                             'refusal_history', (pg_temp.rr_att2('xf2')).recording_refusal_history),
          jsonb_build_object('stored', 'revoked_employee', 'same_token', true, 'refused_at_kept', true,
                             'report_predates_row_stamp', false, 'report_predates_last_resume', true,
                             'last_resume', jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-3'),
                                              'membership_id', pg_temp.zc_id('membership-3'), 'resume_count', 0),
                             'refusal_history', jsonb_build_array(jsonb_build_object('refusal_code', 'revoked_employee',
                                                  'refused_at', pg_temp.rr_r('att-xf2-1') -> 'refused_at'))),
          'RR-200 item 2 (change 20, no owner timestamp update): the stored report is unchanged (refusal_code revoked_employee, the same token as the row, recording_refused_at kept); it does NOT predate the row''s rejection stamp (sync_operations.updated_at = now(), the transaction start), but it predates the last authorized Resume''s at (recording_resume_history -> -1, the manager acting on count 0): only the last-Resume clause makes it stale');
insert into _zc_r select 'row-xf2-2', to_jsonb(pg_temp.rr_att2('xf2'));
select pg_temp.rr_snap('xf2r2');
set local role authenticated;
select pg_temp.rr_push('p-xf2-r2', 3, jsonb_build_array(pg_temp.rr_leg('xf2', 'xf2', '{"recording_resume": 1}')), 2);
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-xf2-r2'), 'after', pg_temp.rr_resume_state2('xf2'),
                             'so', pg_temp.rr_so_state('xf2', 2),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('xf2')) = pg_temp.rr_r('row-xf2-2'),
                             'audit', pg_temp.rr_delta('xf2r2'),
                             'refused_detail', (select jsonb_agg(e.new_values - 'local_operation_id') from public.audit_events e
                                                 where e.organization_id = pg_temp.zc_org()
                                                   and e.action = 'card_attempt.recording_resume_requested'
                                                   and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('xf2')
                                                   and e.new_values ->> 'outcome' = 'refused')),
          jsonb_build_object('result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', 'P0001',
                                         'detail', 'revoked_employee', 'local_operation_id', pg_temp.zc_lop('xf2'),
                                         'operation_type', 'payment.create', 'status', 'rejected',
                                         'idempotency_replay', true, 'resume_denied', 'refusal_not_recorded'),
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 1, 'resume_count', 1,
                                        'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', 'P0001', 'retry_count', 1,
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', 'P0001',
                                                                  'detail', 'revoked_employee'),
                                     'reason', 'revoked_employee'),
                             'row_unchanged', true,
                             'audit', jsonb_build_object('card_attempt.recording_resume_requested', 1),
                             'refused_detail', jsonb_build_array(jsonb_build_object('attempt_state', 'approved',
                                                 'prior_refusal_code', 'revoked_employee', 'resume_count', 1,
                                                 'outcome', 'refused', 'denied_reason', 'refusal_not_recorded'))),
          'RR-201 item 2 (change 20): the next Resume (recording_resume 1) answers refusal_not_recorded (the report predates the last authorized Resume) and replays the stored rejection; nothing is dispatched (the sync row still rejected revoked_employee / P0001 with retry_count 1, count 1, histories 1, no payment, the attempt row identical) and its bounded audit is exactly one card_attempt.recording_resume_requested {outcome refused, denied_reason refusal_not_recorded, resume_count 1, prior revoked_employee}');
select pg_temp.rr_snap('xf2r2b');
set local role authenticated;
select pg_temp.rr_push('p-xf2-r2b', 3, jsonb_build_array(pg_temp.rr_leg('xf2', 'xf2', '{"recording_resume": 1}')), 2);
reset role;
select is(jsonb_build_object('same_answer', pg_temp.rr_res('p-xf2-r2b') = pg_temp.rr_res('p-xf2-r2'),
                             'resume_denied', pg_temp.rr_res('p-xf2-r2b') ->> 'resume_denied',
                             'after', pg_temp.rr_resume_state2('xf2'),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('xf2')) = pg_temp.rr_r('row-xf2-2'),
                             'audit', pg_temp.rr_delta('xf2r2b'),
                             'audited', pg_temp.rr_resume_audits('xf2', 'refused', 'refusal_not_recorded')),
          jsonb_build_object('same_answer', true, 'resume_denied', 'refusal_not_recorded',
                             'after', jsonb_build_object('so', 'rejected', 'retry_count', 1, 'resume_count', 1,
                                        'resume_history', 1, 'refusal_history', 1, 'payments', 0),
                             'row_unchanged', true, 'audit', '{}'::jsonb, 'audited', 1),
          'RR-202 item 2 (bounded evidence): an identical repeat of that Resume answers the same refusal_not_recorded replay and writes nothing (one audit per attempt, count and reason; nothing dispatched)');
select pg_temp.rr_snap('xf2m2');
set local role service_role;
insert into _zc_r select 'm-xf2-2', pg_temp.rr_markrec2('xf2');
reset role;
insert into _zc_r select 'row-xf2-3', to_jsonb(pg_temp.rr_att2('xf2'));
insert into _zc_r select 'ev-xf2-3', to_jsonb(pg_temp.rr_ev2_n('xf2'));
select is(jsonb_build_object('envelope', pg_temp.rr_ts(pg_temp.rr_r('m-xf2-2')),
                             'stored', (pg_temp.rr_att2('xf2')).refusal_code,
                             'restamped_later', (pg_temp.rr_att2('xf2')).recording_refused_at
                                                > (pg_temp.rr_r('att-xf2-1') ->> 'refused_at')::timestamptz,
                             'after_last_resume', (pg_temp.rr_att2('xf2')).recording_refused_at
                                                  > ((pg_temp.rr_att2('xf2')).recording_resume_history -> -1 ->> 'at')::timestamptz,
                             'only_report_moved', (to_jsonb(pg_temp.rr_att2('xf2')) - 'recording_refused_at' - 'updated_at')
                                                  = (pg_temp.rr_r('row-xf2-2') - 'recording_refused_at' - 'updated_at'),
                             'audit', pg_temp.rr_delta('xf2m2'),
                             'd2_refused_details', (select jsonb_agg(distinct e.new_values) from public.audit_events e
                                                     where e.organization_id = pg_temp.zc_org()
                                                       and e.device_id = pg_temp.zc_id('device-2')
                                                       and e.action = 'card_attempt.recording_refused')),
          jsonb_build_object('envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('xf2'), 'state', 'approved',
                                           'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                           'refusal_code', 'revoked_employee', 'recoverable', true, 'resume_count', 1,
                                           'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'stored', 'revoked_employee', 'restamped_later', true, 'after_last_resume', true,
                             'only_report_moved', true,
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1),
                             'd2_refused_details', '[{"refusal_code": "revoked_employee"}]'::jsonb),
          'RR-203 item 2 (change 20): card_attempt_mark_recording_result of the same token (revoked_employee) re-stamps the stale report: recording_refused_at later than the first report and than the last authorized Resume, nothing else of the attempt changed, exactly one more card_attempt.recording_refused {refusal_code: revoked_employee}; the envelope stays recoverable at count 1');
select pg_temp.rr_snap('xf2m3');
set local role service_role;
insert into _zc_r select 'm-xf2-3', pg_temp.rr_markrec2('xf2');
reset role;
select is(jsonb_build_object('envelope', pg_temp.rr_ts(pg_temp.rr_r('m-xf2-3')),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('xf2')) = pg_temp.rr_r('row-xf2-3'),
                             'audit', pg_temp.rr_delta('xf2m3'),
                             'events', pg_temp.rr_ev2_n('xf2') - (pg_temp.rr_r('ev-xf2-3') #>> '{}')::bigint),
          jsonb_build_object('envelope', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('xf2'), 'state', 'approved',
                                           'classification', 'approved_unrecorded', 'recorded', false, 'provider_return_code', 0,
                                           'refusal_code', 'revoked_employee', 'recoverable', true, 'resume_count', 1,
                                           'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true),
                             'row_unchanged', true, 'audit', '{}'::jsonb, 'events', 0),
          'RR-204 item 3 (batch 5, after a Resume and a re-stamp): a second mark of the same token with no Resume between answers the same envelope and neither re-stamps nor audits: the attempt row is identical (recording_refused_at kept), no audit row, no private event');
select pg_temp.rr_snap('xf2r3');
set local role authenticated;
select pg_temp.rr_push('p-xf2-r3', 3, jsonb_build_array(pg_temp.rr_leg('xf2', 'xf2', '{"recording_resume": 1}')), 2);
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-xf2-r3') ->> 'status', 'resume', pg_temp.rr_resume_state2('xf2'),
                             'refusal_history', (pg_temp.rr_att2('xf2')).recording_refusal_history,
                             'resume_entries', (select jsonb_agg(h - 'at' order by n)
                                                  from jsonb_array_elements((pg_temp.rr_att2('xf2')).recording_resume_history)
                                                       with ordinality as x(h, n)),
                             'recorded', pg_temp.rr_derive2('xf2') -> 'recorded',
                             'taken_by', (select p.taken_by_employee_profile_id from public.payments p
                                           where p.device_id = pg_temp.zc_id('device-2')
                                             and p.local_operation_id = pg_temp.zc_lop('xf2')),
                             'card_sync_audit', pg_temp.rr_delta('xf2r3', 'card_attempt.%') || pg_temp.rr_delta('xf2r3', 'sync.%'),
                             'dispatched', pg_temp.rr_resume_audits('xf2', 'dispatched')),
          jsonb_build_object('status', 'applied',
                             'resume', jsonb_build_object('so', 'applied', 'retry_count', 2, 'resume_count', 2,
                                         'resume_history', 2, 'refusal_history', 2, 'payments', 1),
                             'refusal_history', jsonb_build_array(
                                 jsonb_build_object('refusal_code', 'revoked_employee', 'refused_at', pg_temp.rr_r('att-xf2-1') -> 'refused_at'),
                                 jsonb_build_object('refusal_code', 'revoked_employee', 'refused_at', pg_temp.rr_r('row-xf2-3') -> 'recording_refused_at')),
                             'resume_entries', jsonb_build_array(
                                 jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-3'),
                                                    'membership_id', pg_temp.zc_id('membership-3'), 'resume_count', 0),
                                 jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-3'),
                                                    'membership_id', pg_temp.zc_id('membership-3'), 'resume_count', 1)),
                             'recorded', true, 'taken_by', pg_temp.zc_id('employee-3'),
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1),
                             'dispatched', 2),
          'RR-205 item 2 (change 20): after the fresh report the next Resume (recording_resume 1) is authorized: dispatched once and recorded exactly once (the manager its actor), count 2; the refusal history holds both reports (the first and the re-stamped one) and the Resume history both authorized dispatches (counts 0 and 1)');

-- ===========================================================================
-- X. Batch 7 setup (TEST_BRIEF_4, lane RR-B7). d1 stays management-revoked
--    (section T), so sections Y-Z run on d2 like sections V-W: its cashier
--    (staff 8) claims, pushes and reports, its manager (staff 3) resumes and
--    closes. Each section freezes its attempts to a fresh d2 shift + active
--    drawer (a test-only direct update retires d2's open shift / drawer, as
--    rr_new_shift does for d1), so section Y's close predicate reads only its
--    own attempt. The owner writes of X-Z: that shift rotation, the revoke /
--    restore of the d2 cashier's membership that produces each recoverable
--    refusal (as V-W), and two marked test-only report moves (before RR-212
--    and RR-225) reproducing the cross-transaction order the freshness rules
--    compare (as RR-167's setup).
-- ===========================================================================
create function pg_temp.rr_new_shift2(label text) returns uuid language plpgsql volatile as $$
declare
  v_shift uuid := pg_temp.zc_id('rr-shift-' || label);
begin
  update public.cash_drawer_sessions c set status = 'closed', closed_at = now()
   where c.organization_id = pg_temp.zc_org() and c.device_id = pg_temp.zc_id('device-2')
     and c.status in ('opened', 'active', 'counting');
  update public.shifts s set status = 'closed', closed_at = now()
   where s.organization_id = pg_temp.zc_org() and s.device_id = pg_temp.zc_id('device-2')
     and s.status in ('opening', 'open', 'closing');
  insert into public.shifts (id, organization_id, restaurant_id, branch_id, device_id,
      opened_by_employee_profile_id, resolved_membership_id, local_operation_id, status)
  values (v_shift, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-2'),
      pg_temp.zc_id('employee-8'), pg_temp.zc_id('membership-8'), 'rr-shift-' || label, 'open');
  insert into public.cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id,
      opened_by_employee_profile_id, opening_float_minor, local_operation_id)
  values (pg_temp.zc_id('rr-drawer-' || label), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
      pg_temp.zc_id('device-2'), v_shift, pg_temp.zc_id('employee-8'), 0, 'rr-drawer-' || label);
  return v_shift;
end $$;
-- A FOREIGN payment.create of an attempt identity: a cash tender of the same order whose depends_on names an
-- operation that is never applied, so the valid-device path parks it pending / dependency_not_ready.
create function pg_temp.rr_foreign(label text) returns jsonb language sql immutable as
$$ select pg_temp.zc_pay_op(pg_temp.zc_lop(label), pg_temp.rr_ord(label), 'cash', 1234,
     jsonb_build_object('depends_on', jsonb_build_array(pg_temp.zc_lop(label || '-never-applied')))) $$;
create function pg_temp.rr_resolve2(label text, resolution text) returns jsonb language sql volatile as
$$ select app.card_attempt_resolve_orphan((pg_temp.rr_att2(label)).id, resolution, 'zc-res-' || label,
     'ZC001D synthetic resolution', 'zc001d-op/ref-3', pg_temp.zc_owner()) $$;
-- Expected shapes: the 4.55.4 envelope of an approved, unrecorded LIVE attempt (server_ts as the presence
-- flag of rr_ts) and the derived facts of an unresolved, unrecorded one.
create function pg_temp.rr_env_exp(label text, cls text, refusal text, recoverable boolean, resume_count integer)
returns jsonb language sql immutable as
$$ select jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop(label), 'state', 'approved',
                             'classification', cls, 'recorded', false, 'provider_return_code', 0,
                             'recoverable', recoverable, 'resume_count', resume_count,
                             'amount_minor', 1234, 'currency_code', 'ILS', 'server_ts?', true)
          || case when refusal is null then '{}'::jsonb else jsonb_build_object('refusal_code', refusal) end $$;
create function pg_temp.rr_derive_exp(cls text, reason text, recoverable boolean) returns jsonb
language sql immutable as
$$ select jsonb_build_object('recorded', false, 'payment_id', null, 'classification', cls, 'reason', reason,
                             'recoverable', recoverable, 'claim_active', true, 'blocks_close', true, 'unresolved', true) $$;
-- The card_attempt.recording_refused audit rows of d2 carrying exactly {refusal_code: code}.
create function pg_temp.rr_refused_rows(code text) returns jsonb language sql stable as
$$ select coalesce(jsonb_agg(jsonb_build_object('actor', e.actor_employee_profile_id, 'reason', e.reason)), '[]'::jsonb)
     from public.audit_events e
    where e.organization_id = pg_temp.zc_org() and e.device_id = pg_temp.zc_id('device-2')
      and e.action = 'card_attempt.recording_refused' and e.new_values = jsonb_build_object('refusal_code', code) $$;
insert into _zc_r select 'orders-x', jsonb_agg(pg_temp.zc_order(l, 1234, 2)) from unnest(array['ya1', 'yb1', 'yb2', 'yb3']) l;
insert into _zc_r select 'shift-y1', to_jsonb(pg_temp.rr_new_shift2('y1'));
select is(jsonb_build_object('open_shift', (select jsonb_agg(s.id) from public.shifts s
                                             where s.organization_id = pg_temp.zc_org() and s.device_id = pg_temp.zc_id('device-2')
                                               and s.status in ('opening', 'open', 'closing')),
                             'active_drawer', (select jsonb_agg(c.id) from public.cash_drawer_sessions c
                                                where c.organization_id = pg_temp.zc_org() and c.device_id = pg_temp.zc_id('device-2')
                                                  and c.status = 'active'),
                             'posture', app.card_terminal_posture(pg_temp.zc_org(), pg_temp.zc_branch(), pg_temp.zc_id('device-2')),
                             'close_blocked', app.card_shift_close_blocked(pg_temp.zc_org(), pg_temp.zc_id('rr-shift-y1')),
                             'd1_active', (select d.is_active from public.devices d where d.id = pg_temp.zc_id('device-1'))),
          jsonb_build_object('open_shift', jsonb_build_array(pg_temp.zc_id('rr-shift-y1')),
                             'active_drawer', jsonb_build_array(pg_temp.zc_id('rr-drawer-y1')),
                             'posture', jsonb_build_object('lifecycle', 'enabled', 'mode', 'live', 'enabled', true),
                             'close_blocked', false, 'd1_active', false),
          'RR-206 setup (batch 7, TEST_BRIEF_4 lane RR-B7): d1 stays revoked (section T), so batch 7 runs on d2 (its LIVE binding enabled since section U); a test-only direct update retires d2''s open shift / drawer and opens rr-shift-y1 / rr-drawer-y1, d2''s only open shift and active drawer, whose close predicate starts unblocked');

-- ===========================================================================
-- Y. Batch 7 items 1 and 3 (changes 21 and 22; API 4.55.7 "a row of the
--    identity, of any status, that is not that leg ... stores
--    nonrecoverable_refusal ... orphan_approved for the operator resolution";
--    review probe rr2_correctness/pA_foreign_pending.sql). A foreign cash
--    payment.create parked pending under an approved attempt's identity; the
--    canonical leg meets the identity conflict; the mark stores
--    nonrecoverable_refusal, which stays the current reason whatever the
--    row's status (change 21) and is never re-stamped once stored (change
--    22); the operator's provider_voided resolution frees the order and the
--    close predicate stops blocking.
-- ===========================================================================
set local role service_role;
insert into _zc_r select 'c-ya1', pg_temp.rr_claim2('ya1');
insert into _zc_r select 'f-ya1', pg_temp.rr_fin('ya1', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
select is(jsonb_build_object('claim_created', pg_temp.rr_r('c-ya1') -> 'claim_created',
                             'frozen', jsonb_build_object('device', (pg_temp.rr_att2('ya1')).device_id,
                                         'shift', (pg_temp.rr_att2('ya1')).shift_id,
                                         'drawer', (pg_temp.rr_att2('ya1')).cash_drawer_session_id,
                                         'initiator', (pg_temp.rr_att2('ya1')).initiated_by_employee_profile_id),
                             'finish', pg_temp.rr_ts(pg_temp.rr_r('f-ya1')),
                             'sync_rows', pg_temp.rr_so_n(array['ya1'], 2),
                             'derive', pg_temp.rr_derive2('ya1')),
          jsonb_build_object('claim_created', true,
                             'frozen', jsonb_build_object('device', pg_temp.zc_id('device-2'), 'shift', pg_temp.zc_id('rr-shift-y1'),
                                         'drawer', pg_temp.zc_id('rr-drawer-y1'), 'initiator', pg_temp.zc_id('employee-8')),
                             'finish', pg_temp.rr_env_exp('ya1', 'approved_unrecorded', null, false, 0),
                             'sync_rows', 0,
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'pending_recording', false)),
          'RR-207 setup (item 1): a LIVE attempt claimed by d2''s cashier (frozen to rr-shift-y1 / rr-drawer-y1) and approved by the scope-bound finish; with no sync row under its identity it derives approved_unrecorded / pending_recording, not recoverable');
select pg_temp.rr_snap('ya1p');
set local role authenticated;
select pg_temp.rr_push('p-ya1-foreign', 8, jsonb_build_array(pg_temp.rr_foreign('ya1')), 2);
reset role;
insert into _zc_r select 'so-ya1-1', to_jsonb(pg_temp.rr_so('ya1', 2));
select is(jsonb_build_object('result', pg_temp.rr_res('p-ya1-foreign'), 'so', pg_temp.rr_so_state('ya1', 2),
                             'foreign', jsonb_build_object('payload', (pg_temp.rr_so('ya1', 2)).payload,
                                          'depends_on', (pg_temp.rr_so('ya1', 2)).depends_on),
                             'payments', pg_temp.rr_pay2_n('ya1'), 'order_payments', pg_temp.rr_order_pay_n('ya1'),
                             'audit', pg_temp.rr_delta('ya1p')),
          jsonb_build_object('result', pg_temp.rr_pending('ya1', 'payment.create', 'dependency_not_ready'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', 'dependency_not_ready',
                                     'retry_count', 0, 'result', null::jsonb, 'reason', null::text),
                             'foreign', jsonb_build_object('payload', jsonb_build_object('order_id', pg_temp.rr_ord('ya1'),
                                                                   'tender_type', 'cash', 'amount_tendered_minor', 1234),
                                          'depends_on', jsonb_build_array(pg_temp.zc_lop('ya1-never-applied'))),
                             'payments', 0, 'order_payments', 0, 'audit', '{}'::jsonb),
          'RR-208 item 1: a FOREIGN payment.create (a cash tender of the same order) pushed under the attempt''s identity with a depends_on that is never applied is parked exactly {ok:false, error:dependency_not_ready, retryable:true, status:pending}: the identity''s sync row is that cash row (pending, transient dependency_not_ready, retry_count 0); no payment, no audit row');
select pg_temp.rr_snap('ya1l');
set local role authenticated;
select pg_temp.rr_push('p-ya1-leg', 8, jsonb_build_array(pg_temp.rr_leg('ya1')), 2);
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-ya1-leg'),
                             'row_unchanged', to_jsonb(pg_temp.rr_so('ya1', 2)) = pg_temp.rr_r('so-ya1-1'),
                             'order_payments', pg_temp.rr_order_pay_n('ya1'),
                             'audit', pg_temp.rr_delta('ya1l'),
                             'conflict_audit', (select jsonb_agg(jsonb_build_object('actor', e.actor_employee_profile_id,
                                                    'reason', e.reason, 'detail', e.new_values))
                                                  from public.audit_events e
                                                 where e.organization_id = pg_temp.zc_org() and e.device_id = pg_temp.zc_id('device-2')
                                                   and e.action = 'sync.operation_conflict'
                                                   and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('ya1'))),
          jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop('ya1'), 'operation_type', 'payment.create',
                                         'ok', false, 'error', 'conflict',
                                         'detail', 'idempotency key already used for a different operation/payload',
                                         'status', 'conflict', 'idempotency_replay', false),
                             'row_unchanged', true, 'order_payments', 0,
                             'audit', jsonb_build_object('sync.operation_conflict', 1),
                             'conflict_audit', jsonb_build_array(jsonb_build_object('actor', pg_temp.zc_id('employee-8'), 'reason', null,
                                                 'detail', jsonb_build_object('local_operation_id', pg_temp.zc_lop('ya1'),
                                                     'stored_operation_type', 'payment.create', 'pushed_operation_type', 'payment.create',
                                                     'stored_status', 'pending',
                                                     'reason', 'idempotency_key_reused_with_different_operation_or_payload')))),
          'RR-209 item 1: the canonical card leg of that identity then meets the identity conflict exactly ({ok:false, error:conflict, status:conflict}, nothing memoized): the foreign pending row is byte-identical, no payment, and the only audit row is one sync.operation_conflict {stored_status pending}');
select pg_temp.rr_snap('ya1m1');
insert into _zc_r select 'ev-ya1-1', to_jsonb(pg_temp.rr_ev2_n('ya1'));
set local role service_role;
insert into _zc_r select 'm-ya1-1', pg_temp.rr_markrec2('ya1', 8, 'conflict');
reset role;
select is(jsonb_build_object('mark', pg_temp.rr_ts(pg_temp.rr_r('m-ya1-1')),
                             'stored', (pg_temp.rr_att2('ya1')).refusal_code,
                             'stamped', (pg_temp.rr_att2('ya1')).recording_refused_at is not null,
                             'row_unchanged', to_jsonb(pg_temp.rr_so('ya1', 2)) = pg_temp.rr_r('so-ya1-1'),
                             'audit', pg_temp.rr_delta('ya1m1'),
                             'refused_rows', pg_temp.rr_refused_rows('nonrecoverable_refusal'),
                             'events', pg_temp.rr_ev2_n('ya1') - (pg_temp.rr_r('ev-ya1-1') #>> '{}')::bigint),
          jsonb_build_object('mark', pg_temp.rr_env_exp('ya1', 'orphan_approved', 'nonrecoverable_refusal', false, 0),
                             'stored', 'nonrecoverable_refusal', 'stamped', true, 'row_unchanged', true,
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1),
                             'refused_rows', jsonb_build_array(jsonb_build_object('actor', pg_temp.zc_id('employee-8'), 'reason', null)),
                             'events', 0),
          'RR-210 item 1 (API 4.55.7): card_attempt_mark_recording_result (d2''s cashier) reports the foreign row: refusal_code nonrecoverable_refusal + recording_refused_at stored, the envelope exactly orphan_approved / recoverable false at count 0, exactly one card_attempt.recording_refused {refusal_code: nonrecoverable_refusal} (the cashier its actor), the foreign row untouched, no private event');
select is(jsonb_build_object('so', (pg_temp.rr_so('ya1', 2)).status,
                             'own_leg', (pg_temp.rr_so('ya1', 2)).payload ->> 'tender_type' = 'card',
                             'derive', pg_temp.rr_derive2('ya1'),
                             'envelope', pg_temp.rr_ts(app.card_attempt_envelope(pg_temp.rr_att2('ya1')))),
          jsonb_build_object('so', 'pending', 'own_leg', false,
                             'derive', pg_temp.rr_derive_exp('orphan_approved', 'nonrecoverable_refusal', false),
                             'envelope', pg_temp.rr_env_exp('ya1', 'orphan_approved', 'nonrecoverable_refusal', false, 0)),
          'RR-211 item 1 (change 21): a NON-recoverable stored token is sticky: while the identity''s row is the foreign cash row parked pending, app.card_attempt_derive is exactly orphan_approved / nonrecoverable_refusal, not recoverable (claim active, blocks the close, unresolved) and the envelope agrees (batch 5 read the pending row as approved_unrecorded / pending_recording)');
-- Item 3 setup. Test-only owner update reproducing the cross-transaction order (as RR-167's setup): the
-- report committed before the push transaction that re-parks the foreign row (its stamp is now(), that
-- transaction's start), so recording_refused_at is moved before this transaction's start.
update app.card_provider_attempts a set recording_refused_at = now() - interval '1 second'
 where a.id = (pg_temp.rr_att2('ya1')).id;
insert into _zc_r select 'row-ya1-2', to_jsonb(pg_temp.rr_att2('ya1'));
select pg_temp.rr_snap('ya1rp');
set local role authenticated;
select pg_temp.rr_push('p-ya1-foreign2', 8, jsonb_build_array(pg_temp.rr_foreign('ya1')), 2);
reset role;
select is(jsonb_build_object('result', pg_temp.rr_res('p-ya1-foreign2'), 'so', pg_temp.rr_so_state('ya1', 2),
                             'report_predates_row_stamp', (pg_temp.rr_att2('ya1')).recording_refused_at
                                                          < (pg_temp.rr_so('ya1', 2)).updated_at,
                             'attempt_unchanged', to_jsonb(pg_temp.rr_att2('ya1')) = pg_temp.rr_r('row-ya1-2'),
                             'order_payments', pg_temp.rr_order_pay_n('ya1'), 'audit', pg_temp.rr_delta('ya1rp')),
          jsonb_build_object('result', pg_temp.rr_pending('ya1', 'payment.create', 'dependency_not_ready'),
                             'so', jsonb_build_object('status', 'pending', 'class', 'transient', 'code', 'dependency_not_ready',
                                     'retry_count', 1, 'result', null::jsonb, 'reason', null::text),
                             'report_predates_row_stamp', true, 'attempt_unchanged', true,
                             'order_payments', 0, 'audit', '{}'::jsonb),
          'RR-212 setup (item 3): with the report moved before this transaction''s start (test-only owner update, as RR-167), a resend of the foreign cash row re-parks it (the adopted re-attempt: dependency_not_ready again, retry_count 1, row stamp now()), so the identity row''s updated_at is later than the stored report; nothing else written');
select is(jsonb_build_object('derive', pg_temp.rr_derive2('ya1'),
                             'envelope', pg_temp.rr_ts(app.card_attempt_envelope(pg_temp.rr_att2('ya1')))),
          jsonb_build_object('derive', pg_temp.rr_derive_exp('orphan_approved', 'nonrecoverable_refusal', false),
                             'envelope', pg_temp.rr_env_exp('ya1', 'orphan_approved', 'nonrecoverable_refusal', false, 0)),
          'RR-213 item 3 (change 21): the non-recoverable token stays the current reason after the foreign row was re-parked and although the report is older than the row''s stamp (the freshness clauses bind recoverable tokens only): still exactly orphan_approved / nonrecoverable_refusal, not recoverable');
select pg_temp.rr_snap('ya1m2');
insert into _zc_r select 'ev-ya1-2', to_jsonb(pg_temp.rr_ev2_n('ya1'));
set local role service_role;
insert into _zc_r select 'm-ya1-2', pg_temp.rr_markrec2('ya1', 8, 'conflict');
reset role;
select is(jsonb_build_object('envelope', pg_temp.rr_ts(pg_temp.rr_r('m-ya1-2')),
                             'attempt_unchanged', to_jsonb(pg_temp.rr_att2('ya1')) = pg_temp.rr_r('row-ya1-2'),
                             'report_still_predates_row_stamp', (pg_temp.rr_att2('ya1')).recording_refused_at
                                                                < (pg_temp.rr_so('ya1', 2)).updated_at,
                             'audit', pg_temp.rr_delta('ya1m2'),
                             'refused_rows', jsonb_array_length(pg_temp.rr_refused_rows('nonrecoverable_refusal')),
                             'events', pg_temp.rr_ev2_n('ya1') - (pg_temp.rr_r('ev-ya1-2') #>> '{}')::bigint),
          jsonb_build_object('envelope', pg_temp.rr_env_exp('ya1', 'orphan_approved', 'nonrecoverable_refusal', false, 0),
                             'attempt_unchanged', true, 'report_still_predates_row_stamp', true,
                             'audit', '{}'::jsonb, 'refused_rows', 1, 'events', 0),
          'RR-214 item 3 (change 22): a second card_attempt_mark_recording_result of the same non-recoverable token after the identity row''s updated_at moved past the report answers the same orphan_approved envelope and neither re-stamps nor audits: the attempt row is identical (recording_refused_at still older than the row stamp), no audit row (one nonrecoverable_refusal report in all), no private event');
select pg_temp.rr_snap('ya1c1');
set local role authenticated;
select pg_temp.rr_push('p-ya1-close1', 3, jsonb_build_array(pg_temp.rr_close_op('ya1-c1', pg_temp.zc_id('rr-shift-y1'))), 2);
reset role;
select is(jsonb_build_object('result', pg_temp.rr_ts(pg_temp.rr_res('p-ya1-close1')),
                             'close_blocked', app.card_shift_close_blocked(pg_temp.zc_org(), pg_temp.zc_id('rr-shift-y1')),
                             'claim_active', app.card_order_claim_active(pg_temp.zc_org(), pg_temp.rr_ord('ya1')),
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-y1')),
                             'attempt_unchanged', to_jsonb(pg_temp.rr_att2('ya1')) = pg_temp.rr_r('row-ya1-2'),
                             'audit', pg_temp.rr_delta('ya1c1')),
          jsonb_build_object('result', pg_temp.rr_close_refusal('ya1-c1', 'y1'), 'close_blocked', true, 'claim_active', true,
                             'shift', 'open', 'attempt_unchanged', true,
                             'audit', jsonb_build_object('sync.operation_rejected', 1)),
          'RR-215 item 1: before the resolution the orphan blocks: shift.close of rr-shift-y1 by d2''s manager answers exactly card_payment_in_progress (app.card_shift_close_blocked true, the order claim active), the shift stays open, the attempt is untouched and the only audit row is the sync.operation_rejected');
select pg_temp.rr_snap('ya1res');
insert into _zc_r select 'ev-ya1-3', to_jsonb(pg_temp.rr_ev2_n('ya1'));
insert into _zc_r select 'res-ya1', pg_temp.rr_resolve2('ya1', 'provider_voided');
select is(jsonb_build_object('answer', pg_temp.rr_ts(pg_temp.rr_r('res-ya1')),
                             'attempt', (select jsonb_build_object('state', a.state, 'resolution', a.resolution,
                                            'resolution_reference', a.resolution_reference, 'resolved', a.resolved_at is not null,
                                            'freed', a.order_freed_at is not null, 'freed_reason', a.order_freed_reason,
                                            'refusal_code', a.refusal_code)
                                          from pg_temp.rr_att2('ya1') a),
                             'events', pg_temp.rr_ev2_n('ya1') - (pg_temp.rr_r('ev-ya1-3') #>> '{}')::bigint,
                             'operator_event', (select jsonb_agg(jsonb_build_object('action', e.action, 'mode', e.mode,
                                                    'device', e.device_id, 'actor_kind', e.actor_kind,
                                                    'actor_reference', e.actor_reference, 'actor', e.actor_app_user_id,
                                                    'executor', e.executor_principal, 'reason', e.reason, 'detail', e.detail,
                                                    'retention_until', e.retention_until))
                                                  from app.card_provider_private_events e
                                                 where e.attempt_row_id = (pg_temp.rr_att2('ya1')).id and e.action like 'operator.%'),
                             'audit', pg_temp.rr_delta('ya1res')),
          jsonb_build_object('answer', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('ya1'), 'state', 'approved',
                                         'classification', 'resolved', 'recorded', false, 'provider_return_code', 0,
                                         'refusal_code', 'nonrecoverable_refusal', 'resolution', 'provider_voided',
                                         'amount_minor', 1234, 'currency_code', 'ILS',
                                         'attempt_row_id', (pg_temp.rr_att2('ya1')).id, 'server_ts?', true),
                             'attempt', jsonb_build_object('state', 'approved', 'resolution', 'provider_voided',
                                         'resolution_reference', 'zc-res-ya1', 'resolved', true, 'freed', true,
                                         'freed_reason', 'orphan_resolved', 'refusal_code', 'nonrecoverable_refusal'),
                             'events', 1,
                             'operator_event', jsonb_build_array(jsonb_build_object('action', 'operator.card_attempt_orphan_resolved',
                                                 'mode', null, 'device', pg_temp.zc_id('device-2'),
                                                 'actor_kind', 'attested_owner_approver', 'actor_reference', 'zc001d-op/ref-3',
                                                 'actor', pg_temp.zc_owner(), 'executor', session_user,
                                                 'reason', 'ZC001D synthetic resolution',
                                                 'detail', jsonb_build_object('resolution', 'provider_voided', 'attempt_state', 'approved'),
                                                 'retention_until', null)),
                             'audit', '{}'::jsonb),
          'RR-216 item 1: app.card_attempt_resolve_orphan(provider_voided) by the attested owner approver succeeds on that orphan: exactly the 4.55.4 envelope (classification resolved, resolution provider_voided, refusal_code kept) + attempt_row_id; the row carries the resolution, resolved_at and order_freed_at / order_freed_reason orphan_resolved; exactly one private event operator.card_attempt_orphan_resolved {resolution, attempt_state} (mode NULL, executor session_user); no tenant audit');
select is(jsonb_build_object('derive', pg_temp.rr_derive2('ya1'),
                             'claim_active', app.card_order_claim_active(pg_temp.zc_org(), pg_temp.rr_ord('ya1')),
                             'close_blocked', app.card_shift_close_blocked(pg_temp.zc_org(), pg_temp.zc_id('rr-shift-y1'))),
          jsonb_build_object('derive', jsonb_build_object('recorded', false, 'payment_id', null, 'classification', 'resolved',
                                         'reason', null, 'recoverable', false, 'claim_active', false, 'blocks_close', false,
                                         'unresolved', false),
                             'claim_active', false, 'close_blocked', false),
          'RR-217 item 1: the resolution frees the order and the shift-close predicate no longer blocks: derive exactly resolved (claim_active, blocks_close and unresolved false), app.card_order_claim_active false, app.card_shift_close_blocked(rr-shift-y1) false');
select pg_temp.rr_snap('ya1c2');
set local role authenticated;
select pg_temp.rr_push('p-ya1-close2', 3, jsonb_build_array(pg_temp.rr_close_op('ya1-c2', pg_temp.zc_id('rr-shift-y1'))), 2);
reset role;
select is(jsonb_build_object('ok', pg_temp.rr_res('p-ya1-close2') -> 'ok', 'status', pg_temp.rr_res('p-ya1-close2') ->> 'status',
                             'shift_id', pg_temp.rr_res('p-ya1-close2') ->> 'shift_id',
                             'shift', (select s.status from public.shifts s where s.id = pg_temp.zc_id('rr-shift-y1')),
                             'foreign_row', (pg_temp.rr_so('ya1', 2)).status, 'order_payments', pg_temp.rr_order_pay_n('ya1'),
                             'card_audit', pg_temp.rr_delta('ya1c2', 'card_attempt.%')),
          jsonb_build_object('ok', true, 'status', 'applied', 'shift_id', pg_temp.zc_id('rr-shift-y1')::text, 'shift', 'closed',
                             'foreign_row', 'pending', 'order_payments', 0, 'card_audit', '{}'::jsonb),
          'RR-218 item 1: the same close is then admitted (applied, rr-shift-y1 closed) although the foreign cash row is still parked pending; no payment on the order, no card_attempt audit');

-- ===========================================================================
-- Z. Batch 7 item 2 (change 21): a RECOVERABLE stored token is the current
--    reason only while it reports the leg's latest refusal. After an
--    authorized Resume whose re-dispatch is refused again - with the SAME
--    token (yb1) or ANOTHER recoverable token (yb2) - and not yet reported,
--    the attempt reads approved_unrecorded / pending_recording, recoverable
--    false; once the mark reports it, recording_refused, recoverable true, and
--    the next Resume records once. yb3 isolates the row-stamp clause: a
--    report older than the row's latest stamp, with no Resume at all.
-- ===========================================================================
insert into _zc_r select 'shift-y2', to_jsonb(pg_temp.rr_new_shift2('y2'));
set local role service_role;
insert into _zc_r select 'c-' || l, pg_temp.rr_claim2(l) from unnest(array['yb1', 'yb2', 'yb3']) l;
insert into _zc_r select 'f-' || l, pg_temp.rr_fin(l, 'commit', 'approved', pg_temp.zc_approved_fields())
  from unnest(array['yb1', 'yb2', 'yb3']) l;
reset role;
-- Each own leg pushed by the cashier (staff 8) while that membership is revoked: record_payment's raise,
-- memoized revoked_employee (as RS11 / V / W); the membership restored right after.
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-8');
set local role authenticated;
select pg_temp.rr_push('p-' || l || '-k', 8, jsonb_build_array(pg_temp.rr_leg(l)), 2) from unnest(array['yb1', 'yb2', 'yb3']) l;
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-8');
set local role service_role;
insert into _zc_r select 'm-' || l || '-1', pg_temp.rr_markrec2(l) from unnest(array['yb1', 'yb2', 'yb3']) l;
reset role;
insert into _zc_r select 'att-' || l || '-1', jsonb_build_object('refusal_code', (pg_temp.rr_att2(l)).refusal_code,
                                                                 'refused_at', (pg_temp.rr_att2(l)).recording_refused_at)
  from unnest(array['yb1', 'yb2', 'yb3']) l;
select is((select jsonb_object_agg(l, jsonb_build_object('frozen_shift', (pg_temp.rr_att2(l)).shift_id,
                                          'push', pg_temp.rr_res('p-' || l || '-k'), 'so', pg_temp.rr_so_state(l, 2),
                                          'mark', pg_temp.rr_ts(pg_temp.rr_r('m-' || l || '-1')),
                                          'derive', pg_temp.rr_derive2(l)))
             from unnest(array['yb1', 'yb2', 'yb3']) l),
          (select jsonb_object_agg(l, jsonb_build_object('frozen_shift', pg_temp.zc_id('rr-shift-y2'),
                                          'push', jsonb_build_object('local_operation_id', pg_temp.zc_lop(l),
                                                    'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                                    'sqlstate', '42501', 'detail', 'revoked_employee', 'status', 'rejected',
                                                    'idempotency_replay', false),
                                          'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', '42501',
                                                  'retry_count', 0,
                                                  'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', '42501',
                                                                               'detail', 'revoked_employee'),
                                                  'reason', 'revoked_employee'),
                                          'mark', pg_temp.rr_env_exp(l, 'approved_unrecorded', 'revoked_employee', true, 0),
                                          'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true)))
             from unnest(array['yb1', 'yb2', 'yb3']) l),
          'RR-219 setup (item 2): three LIVE attempts of d2 (frozen to the fresh rr-shift-y2) approved; each own leg pushed while the cashier''s membership was revoked is memoized rejected revoked_employee (42501) and reported by the mark (fresh: recording_refused, recoverable at count 0)');
select pg_temp.rr_snap('ybr1');
set local role authenticated;
select pg_temp.rr_push_fault('p-yb1-r1', 3, jsonb_build_array(pg_temp.rr_leg('yb1', 'yb1', '{"recording_resume": 0}')),
                             'payments', 'P0001', 'zc synthetic: resolved membership is not active', 2);
select pg_temp.rr_push_fault('p-yb2-r1', 3, jsonb_build_array(pg_temp.rr_leg('yb2', 'yb2', '{"recording_resume": 0}')),
                             'payments', 'P0001', 'zc synthetic: no open shift on the paying device (precondition_failed)', 2);
reset role;
select is((select jsonb_object_agg(l, jsonb_build_object('result', pg_temp.rr_res('p-' || l || '-r1'),
                                          'so', pg_temp.rr_so_state(l, 2), 'after', pg_temp.rr_resume_state2(l)))
             from unnest(array['yb1', 'yb2']) l)
          || jsonb_build_object('audit', pg_temp.rr_delta('ybr1')),
          (select jsonb_object_agg(l, jsonb_build_object('result', jsonb_build_object('local_operation_id', pg_temp.zc_lop(l),
                                                    'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                                    'sqlstate', 'P0001', 'detail', t, 'status', 'rejected',
                                                    'idempotency_replay', false),
                                          'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', 'P0001',
                                                  'retry_count', 1,
                                                  'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', 'P0001',
                                                                               'detail', t),
                                                  'reason', t),
                                          'after', jsonb_build_object('so', 'rejected', 'retry_count', 1, 'resume_count', 1,
                                                     'resume_history', 1, 'refusal_history', 1, 'payments', 0)))
             from (values ('yb1', 'revoked_employee'), ('yb2', 'precondition_failed')) v(l, t))
          || jsonb_build_object('audit', jsonb_build_object('card_attempt.recording_resume_requested', 2,
                                                            'sync.operation_rejected', 2)),
          'RR-220 setup (item 2): d2''s manager (staff 3) resumes both (recording_resume 0); each Resume is authorized and dispatched once, and each re-dispatch is refused again by a forced P0001 raise on the payments insert: yb1 with the SAME token (revoked_employee), yb2 with ANOTHER recoverable token (precondition_failed); each row memoized rejected (retry_count 1), count 1, no payment; two dispatched card_attempt.recording_resume_requested and two sync.operation_rejected');
select is((select jsonb_object_agg(l, jsonb_build_object('stored', (pg_temp.rr_att2(l)).refusal_code,
                                          'refused_at_kept', (pg_temp.rr_att2(l)).recording_refused_at
                                                             = (pg_temp.rr_r('att-' || l || '-1') ->> 'refused_at')::timestamptz,
                                          'report_predates_last_resume', (pg_temp.rr_att2(l)).recording_refused_at
                                              < ((pg_temp.rr_att2(l)).recording_resume_history -> -1 ->> 'at')::timestamptz,
                                          'derive', pg_temp.rr_derive2(l),
                                          'envelope', pg_temp.rr_ts(app.card_attempt_envelope(pg_temp.rr_att2(l)))))
             from unnest(array['yb1', 'yb2']) l),
          (select jsonb_object_agg(l, jsonb_build_object('stored', 'revoked_employee', 'refused_at_kept', true,
                                          'report_predates_last_resume', true,
                                          'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'pending_recording', false),
                                          'envelope', pg_temp.rr_env_exp(l, 'approved_unrecorded', 'revoked_employee', false, 1)))
             from unnest(array['yb1', 'yb2']) l),
          'RR-221 item 2 (change 21): until the refused re-dispatch is reported, the stored revoked_employee report (kept, older than the last authorized Resume''s at) is not the current reason: app.card_attempt_derive is exactly approved_unrecorded / pending_recording, recoverable false, for the same-token and the other-token re-dispatch alike, and the envelope reads recoverable false at count 1 with the stored refusal_code (batch 5 read recording_refused, recoverable true)');
select pg_temp.rr_snap('ybm2');
insert into _zc_r select 'refused-ybm2', jsonb_build_object(
  'revoked_employee', jsonb_array_length(pg_temp.rr_refused_rows('revoked_employee')),
  'precondition_failed', jsonb_array_length(pg_temp.rr_refused_rows('precondition_failed')));
set local role service_role;
insert into _zc_r select 'm-' || l || '-2', pg_temp.rr_markrec2(l) from unnest(array['yb1', 'yb2']) l;
reset role;
select is((select jsonb_object_agg(l, jsonb_build_object('mark', pg_temp.rr_ts(pg_temp.rr_r('m-' || l || '-2')),
                                          'stored', (pg_temp.rr_att2(l)).refusal_code,
                                          'restamped_after_last_resume', (pg_temp.rr_att2(l)).recording_refused_at
                                              > ((pg_temp.rr_att2(l)).recording_resume_history -> -1 ->> 'at')::timestamptz))
             from unnest(array['yb1', 'yb2']) l)
          || jsonb_build_object('audit', pg_temp.rr_delta('ybm2'),
                                'new_report_rows', jsonb_build_object(
                                  'revoked_employee', jsonb_array_length(pg_temp.rr_refused_rows('revoked_employee'))
                                                      - (pg_temp.rr_r('refused-ybm2') ->> 'revoked_employee')::integer,
                                  'precondition_failed', jsonb_array_length(pg_temp.rr_refused_rows('precondition_failed'))
                                                         - (pg_temp.rr_r('refused-ybm2') ->> 'precondition_failed')::integer)),
          jsonb_build_object('yb1', jsonb_build_object('mark', pg_temp.rr_env_exp('yb1', 'approved_unrecorded', 'revoked_employee', true, 1),
                                        'stored', 'revoked_employee', 'restamped_after_last_resume', true),
                             'yb2', jsonb_build_object('mark', pg_temp.rr_env_exp('yb2', 'approved_unrecorded', 'precondition_failed', true, 1),
                                        'stored', 'precondition_failed', 'restamped_after_last_resume', true),
                             'audit', jsonb_build_object('card_attempt.recording_refused', 2),
                             'new_report_rows', jsonb_build_object('revoked_employee', 1, 'precondition_failed', 1)),
          'RR-222 item 2 (changes 21 and 22): card_attempt_mark_recording_result then reports each re-dispatch refusal: yb1''s same recoverable token is stale and re-stamped, yb2''s new token precondition_failed is stored; each recording_refused_at is later than the last authorized Resume, each envelope recoverable at count 1, exactly one card_attempt.recording_refused per attempt ({revoked_employee} and {precondition_failed})');
select is((select jsonb_object_agg(l, jsonb_build_object('derive', pg_temp.rr_derive2(l),
                                          'envelope', pg_temp.rr_ts(app.card_attempt_envelope(pg_temp.rr_att2(l)))))
             from unnest(array['yb1', 'yb2']) l),
          jsonb_build_object('yb1', jsonb_build_object('derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true),
                                        'envelope', pg_temp.rr_env_exp('yb1', 'approved_unrecorded', 'revoked_employee', true, 1)),
                             'yb2', jsonb_build_object('derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true),
                                        'envelope', pg_temp.rr_env_exp('yb2', 'approved_unrecorded', 'precondition_failed', true, 1))),
          'RR-223 item 2 (change 21): once reported, the stored token is the leg''s latest refusal again: app.card_attempt_derive is exactly approved_unrecorded / recording_refused, recoverable true, and the envelope recoverable true at count 1 (refusal_code revoked_employee for yb1, precondition_failed for yb2)');
select pg_temp.rr_snap('ybr2');
set local role authenticated;
select pg_temp.rr_push('p-' || l || '-r2', 3, jsonb_build_array(pg_temp.rr_leg(l, l, '{"recording_resume": 1}')), 2)
  from unnest(array['yb1', 'yb2']) l;
reset role;
select is((select jsonb_object_agg(l, jsonb_build_object('status', pg_temp.rr_res('p-' || l || '-r2') ->> 'status',
                                          'resume', pg_temp.rr_resume_state2(l),
                                          'refusal_codes', (select jsonb_agg(h -> 'refusal_code' order by n)
                                                              from jsonb_array_elements((pg_temp.rr_att2(l)).recording_refusal_history)
                                                                   with ordinality as x(h, n)),
                                          'recorded', pg_temp.rr_derive2(l) -> 'recorded',
                                          'taken_by', (select p.taken_by_employee_profile_id from public.payments p
                                                        where p.device_id = pg_temp.zc_id('device-2')
                                                          and p.local_operation_id = pg_temp.zc_lop(l))))
             from unnest(array['yb1', 'yb2']) l)
          || jsonb_build_object('card_sync_audit', pg_temp.rr_delta('ybr2', 'card_attempt.%') || pg_temp.rr_delta('ybr2', 'sync.%')),
          jsonb_build_object('yb1', jsonb_build_object('status', 'applied',
                                        'resume', jsonb_build_object('so', 'applied', 'retry_count', 2, 'resume_count', 2,
                                                    'resume_history', 2, 'refusal_history', 2, 'payments', 1),
                                        'refusal_codes', '["revoked_employee", "revoked_employee"]'::jsonb,
                                        'recorded', true, 'taken_by', pg_temp.zc_id('employee-3')),
                             'yb2', jsonb_build_object('status', 'applied',
                                        'resume', jsonb_build_object('so', 'applied', 'retry_count', 2, 'resume_count', 2,
                                                    'resume_history', 2, 'refusal_history', 2, 'payments', 1),
                                        'refusal_codes', '["revoked_employee", "precondition_failed"]'::jsonb,
                                        'recorded', true, 'taken_by', pg_temp.zc_id('employee-3')),
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 2)),
          'RR-224 item 2: after the reports the next Resume (recording_resume 1) of each is authorized and records exactly once (the manager its actor), count 2, the refusal history holding both reports; only the two dispatched card_attempt.recording_resume_requested are written (no sync.* audit)');
-- yb3: a test-only owner update reproducing the cross-transaction order (as RR-167's setup) moves its fresh
-- report before this transaction's start, i.e. before the row's latest stamp (sync_operations.updated_at =
-- now()); with no Resume history only the row-stamp clause can make it stale.
update app.card_provider_attempts a set recording_refused_at = now() - interval '1 second'
 where a.id = (pg_temp.rr_att2('yb3')).id;
insert into _zc_r select 'row-yb3-2', to_jsonb(pg_temp.rr_att2('yb3'));
select is(jsonb_build_object('so', (pg_temp.rr_so('yb3', 2)).status,
                             'resume_history', (pg_temp.rr_att2('yb3')).recording_resume_history,
                             'report_predates_row_stamp', (pg_temp.rr_att2('yb3')).recording_refused_at
                                                          < (pg_temp.rr_so('yb3', 2)).updated_at,
                             'derive', pg_temp.rr_derive2('yb3'),
                             'envelope', pg_temp.rr_ts(app.card_attempt_envelope(pg_temp.rr_att2('yb3')))),
          jsonb_build_object('so', 'rejected', 'resume_history', '[]'::jsonb, 'report_predates_row_stamp', true,
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'pending_recording', false),
                             'envelope', pg_temp.rr_env_exp('yb3', 'approved_unrecorded', 'revoked_employee', false, 0)),
          'RR-225 item 2 (change 21, the row-stamp clause alone): a recoverable report older than the identity row''s updated_at (moved before this transaction''s start, test-only owner update as RR-167; the row rejected, no Resume history) is not the leg''s latest refusal: derive exactly approved_unrecorded / pending_recording, recoverable false; envelope recoverable false at count 0');
select pg_temp.rr_snap('yb3m');
set local role service_role;
insert into _zc_r select 'm-yb3-2', pg_temp.rr_markrec2('yb3');
reset role;
select is(jsonb_build_object('mark', pg_temp.rr_ts(pg_temp.rr_r('m-yb3-2')),
                             'restamped_after_row_stamp', (pg_temp.rr_att2('yb3')).recording_refused_at
                                                          > (pg_temp.rr_so('yb3', 2)).updated_at,
                             'only_report_moved', (to_jsonb(pg_temp.rr_att2('yb3')) - 'recording_refused_at' - 'updated_at')
                                                  = (pg_temp.rr_r('row-yb3-2') - 'recording_refused_at' - 'updated_at'),
                             'audit', pg_temp.rr_delta('yb3m'),
                             'derive', pg_temp.rr_derive2('yb3')),
          jsonb_build_object('mark', pg_temp.rr_env_exp('yb3', 'approved_unrecorded', 'revoked_employee', true, 0),
                             'restamped_after_row_stamp', true, 'only_report_moved', true,
                             'audit', jsonb_build_object('card_attempt.recording_refused', 1),
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true)),
          'RR-226 item 2 (changes 21 and 22): a mark of the same recoverable token re-stamps that stale report (recording_refused_at now later than the row stamp, nothing else of the attempt changed, exactly one card_attempt.recording_refused) and the attempt derives approved_unrecorded / recording_refused, recoverable true again');

-- ===========================================================================
-- AA. Correction C1 (TEST_BRIEF_C1 lane RR): the M10 direct operation-type
--    test (packet section 5, M10: operation type / fingerprint mismatches stay
--    the preamble's conflict; API 4.55.7: "a type or fingerprint mismatch is
--    already answered conflict by the dispatcher's preamble" and "a preamble
--    conflict ... never reach[es] the guard and write[s] no Resume evidence";
--    API 4.14: recording_resume on any other operation type is refused
--    invalid_payload per operation, no ledger mutation). A fresh LIVE attempt
--    of d2 (zm1, frozen to a fresh rr-shift-zm) is approved; its own
--    payment.create leg is memoized rejected revoked_employee (recoverable)
--    and reported (as sections V-Z). Then d2's manager (staff 3, who holds the
--    Resume authority for that leg) pushes OTHER operation types under the
--    SAME local_operation_id: order.void for the same order without
--    recording_resume, with the top-level control key and with the key inside
--    its payload (AA.1); every other operation type of the dispatcher, plain
--    and with the control key (AA.2); and the same three order.void pushes on
--    the revoked-device path (AA.3). Nothing reopens, dispatches or pays; the
--    attempt row (its stored refusal included) and the sync row stay
--    byte-identical; the only audit rows are the preamble's
--    sync.operation_conflict, one per conflict push. The genuine Resume then
--    records once (AA.4, positive control). Last, the reverse direction
--    (AA.5, zm2): an order.void stored first under an attempt identity makes
--    the attempt's own leg and a Resume-carrying leg the preamble's conflict
--    too. The owner writes of AA: the d2 shift rotation (rr_new_shift2), the
--    revoke / restore of the d2 cashier's membership that produces the
--    refusal (as V-Z) and the suspend / restore of d2's pairing in AA.3 (as
--    section T did for d1); no owner update touches an attempt, a sync row, a
--    report or an audit row.
-- ===========================================================================
-- The dispatcher's operation types other than payment.create (its envelope allowlist), in a fixed order.
create function pg_temp.rr_m10_types() returns text[] language sql immutable as
$$ select array['shift.open', 'order.submit', 'order.discount', 'shift.close', 'order.status', 'order.void',
                'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink',
                'order.void_ack', 'order.items_add', 'order.round_status', 'cash_drawer.no_sale_open', 'order.edit',
                'order.edit_ack'] $$;
-- One operation of op_type under label's identity targeting label's order; target_id equals the payload's
-- identity key (order_id, or round_id for order.round_status), so the identity-hardened types pass their
-- pre-ledger check. payload is merged into the payload, extra into the operation object (top level).
create function pg_temp.rr_m10_op(label text, op_type text, payload jsonb default '{}'::jsonb,
                                  extra jsonb default '{}'::jsonb) returns jsonb language sql immutable as
$$ select pg_temp.rr_op(rr_m10_op.label, rr_m10_op.op_type, rr_m10_op.label,
            case rr_m10_op.op_type when 'order.void' then jsonb_build_object('reason', 'ZC001D synthetic void')
                                   when 'order.round_status' then jsonb_build_object('round_id', pg_temp.rr_ord(rr_m10_op.label))
                                   else '{}'::jsonb end || rr_m10_op.payload) || rr_m10_op.extra $$;
-- The preamble's conflict result of one pushed operation.
create function pg_temp.rr_m10_conflict(label text, op_type text) returns jsonb language sql immutable as
$$ select jsonb_build_object('local_operation_id', pg_temp.zc_lop(label), 'operation_type', op_type, 'ok', false,
                             'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload',
                             'status', 'conflict', 'idempotency_replay', false) $$;
-- A whole sync_push response holding one result (server_ts as rr_ts's presence flag).
create function pg_temp.rr_m10_resp(result jsonb, revoked boolean default false) returns jsonb language sql immutable as
$$ select jsonb_build_object('ok', true, 'results', jsonb_build_array(result), 'server_ts?', true)
          || case when revoked then jsonb_build_object('device_revoked', true) else '{}'::jsonb end $$;
-- One sync.operation_conflict row as written by the preamble (every column but id and the timestamps).
create function pg_temp.rr_m10_audit_one(label text, n integer, stored_type text, pushed_type text) returns jsonb
language sql immutable as
$$ select jsonb_build_object('restaurant', pg_temp.zc_rest(), 'branch', pg_temp.zc_branch(), 'actor_user', null,
                             'actor', pg_temp.zc_id('employee-' || n), 'device', pg_temp.zc_id('device-2'),
                             'reason', null, 'old', null,
                             'new', jsonb_build_object('local_operation_id', pg_temp.zc_lop(label),
                                      'stored_operation_type', stored_type, 'pushed_operation_type', pushed_type,
                                      'stored_status', 'rejected',
                                      'reason', 'idempotency_key_reused_with_different_operation_or_payload')) $$;
-- Every sync.operation_conflict row of label's identity in the pilot organization, as a sorted multiset.
create function pg_temp.rr_m10_audit_rows(label text) returns jsonb language sql stable as
$$ select coalesce(jsonb_agg(x order by x), '[]'::jsonb)
     from (select jsonb_build_object('restaurant', e.restaurant_id, 'branch', e.branch_id,
                                     'actor_user', e.actor_app_user_id, 'actor', e.actor_employee_profile_id,
                                     'device', e.device_id, 'reason', e.reason, 'old', e.old_values,
                                     'new', e.new_values) x
             from public.audit_events e
            where e.organization_id = pg_temp.zc_org() and e.action = 'sync.operation_conflict'
              and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop(rr_m10_audit_rows.label)) s $$;
-- Row counts of the pilot organization that any dispatch, payment, ledger or attempt write would change,
-- a snapshot of them, and the non-zero differences since that snapshot ('{}' = nothing added or removed).
create function pg_temp.rr_m10_world() returns jsonb language sql stable as
$$ select jsonb_build_object(
     'orders', (select count(*) from public.orders o where o.organization_id = pg_temp.zc_org()),
     'shifts', (select count(*) from public.shifts s where s.organization_id = pg_temp.zc_org()),
     'drawers', (select count(*) from public.cash_drawer_sessions c where c.organization_id = pg_temp.zc_org()),
     'payments', (select count(*) from public.payments p where p.organization_id = pg_temp.zc_org()),
     'sync_rows', (select count(*) from public.sync_operations so where so.organization_id = pg_temp.zc_org()),
     'attempts', (select count(*) from app.card_provider_attempts a where a.organization_id = pg_temp.zc_org()),
     'private_events', (select count(*) from app.card_provider_private_events e
                         where e.organization_id = pg_temp.zc_org())) $$;
create function pg_temp.rr_m10_world_snap(label text) returns void language sql volatile as
$$ insert into _zc_r (label, r) values ('world-' || rr_m10_world_snap.label, pg_temp.rr_m10_world()) $$;
create function pg_temp.rr_m10_world_delta(label text) returns jsonb language sql stable as
$$ select coalesce(jsonb_object_agg(c.key, (c.value #>> '{}')::bigint - (s.r ->> c.key)::bigint)
                     filter (where (c.value #>> '{}')::bigint <> (s.r ->> c.key)::bigint), '{}'::jsonb)
     from jsonb_each(pg_temp.rr_m10_world()) c
     join _zc_r s on s.label = 'world-' || rr_m10_world_delta.label $$;
-- The order, the frozen shift and drawer rows of label's attempt (whole rows).
create function pg_temp.rr_m10_ctx(label text) returns jsonb language sql stable as
$$ select jsonb_build_object(
     'order', (select to_jsonb(o) from public.orders o where o.id = pg_temp.rr_ord(rr_m10_ctx.label)),
     'shift', (select to_jsonb(s) from public.shifts s where s.id = (pg_temp.rr_att2(rr_m10_ctx.label)).shift_id),
     'drawer', (select to_jsonb(c) from public.cash_drawer_sessions c
                 where c.id = (pg_temp.rr_att2(rr_m10_ctx.label)).cash_drawer_session_id)) $$;

insert into _zc_r select 'orders-aa', jsonb_agg(pg_temp.zc_order(l, 1234, 2)) from unnest(array['zm1', 'zm2']) l;
insert into _zc_r select 'shift-zm', to_jsonb(pg_temp.rr_new_shift2('zm'));
set local role service_role;
insert into _zc_r select 'c-zm1', pg_temp.rr_claim2('zm1');
insert into _zc_r select 'f-zm1', pg_temp.rr_fin('zm1', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
-- The own leg pushed by the cashier (staff 8) while that membership is revoked: record_payment's raise,
-- memoized revoked_employee (as RS11 / V-Z); the membership restored right after; the mark reports it.
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-8');
set local role authenticated;
select pg_temp.rr_push('p-zm1-k', 8, jsonb_build_array(pg_temp.rr_leg('zm1')), 2);
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-8');
set local role service_role;
insert into _zc_r select 'm-zm1-1', pg_temp.rr_markrec2('zm1');
reset role;
select is(jsonb_build_object('claim_created', pg_temp.rr_r('c-zm1') -> 'claim_created',
                             'frozen', jsonb_build_object('device', (pg_temp.rr_att2('zm1')).device_id,
                                         'shift', (pg_temp.rr_att2('zm1')).shift_id,
                                         'drawer', (pg_temp.rr_att2('zm1')).cash_drawer_session_id,
                                         'initiator', (pg_temp.rr_att2('zm1')).initiated_by_employee_profile_id),
                             'state', (pg_temp.rr_att2('zm1')).state,
                             'push', pg_temp.rr_res('p-zm1-k'),
                             'so', pg_temp.rr_so_state('zm1', 2) || jsonb_build_object('operation_type', (pg_temp.rr_so('zm1', 2)).operation_type),
                             'mark', pg_temp.rr_ts(pg_temp.rr_r('m-zm1-1')),
                             'resume', pg_temp.rr_resume_state2('zm1'),
                             'derive', pg_temp.rr_derive2('zm1')),
          jsonb_build_object('claim_created', true,
                             'frozen', jsonb_build_object('device', pg_temp.zc_id('device-2'), 'shift', pg_temp.zc_id('rr-shift-zm'),
                                         'drawer', pg_temp.zc_id('rr-drawer-zm'), 'initiator', pg_temp.zc_id('employee-8')),
                             'state', 'approved',
                             'push', jsonb_build_object('local_operation_id', pg_temp.zc_lop('zm1'), 'operation_type', 'payment.create',
                                       'ok', false, 'error', 'rejected', 'sqlstate', '42501', 'detail', 'revoked_employee',
                                       'status', 'rejected', 'idempotency_replay', false),
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', '42501', 'retry_count', 0,
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', '42501',
                                                                  'detail', 'revoked_employee'),
                                     'reason', 'revoked_employee', 'operation_type', 'payment.create'),
                             'mark', pg_temp.rr_env_exp('zm1', 'approved_unrecorded', 'revoked_employee', true, 0),
                             'resume', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                         'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true)),
          'RR-227 setup (C1 lane RR, packet section 5 M10): a LIVE attempt claimed by d2''s cashier (frozen to a fresh rr-shift-zm / rr-drawer-zm) and approved; its own payment.create leg, pushed while that cashier''s membership was revoked, is memoized rejected revoked_employee (42501, retry_count 0) and reported by the mark: approved_unrecorded / recording_refused, recoverable true, resume_count 0, both histories empty, no payment');
-- The state every later assertion compares against (read as owner).
insert into _zc_r select 'row-zm1-0', to_jsonb(pg_temp.rr_att2('zm1'));
insert into _zc_r select 'so-zm1-0', to_jsonb(pg_temp.rr_so('zm1', 2));
insert into _zc_r select 'ctx-zm1-0', pg_temp.rr_m10_ctx('zm1');
insert into _zc_r select 'ev-zm1-0', to_jsonb(pg_temp.rr_ev2_n('zm1'));
select pg_temp.rr_m10_world_snap('zm1-0');
select pg_temp.rr_snap('zm1t');

-- AA.1 order.void for the same order, by the manager, on the valid-device path.
select pg_temp.rr_snap('zm1-void');
set local role authenticated;
select pg_temp.rr_push('p-zm1-void', 3, jsonb_build_array(pg_temp.rr_m10_op('zm1', 'order.void')), 2);
reset role;
select is(jsonb_build_object('response', pg_temp.rr_ts(pg_temp.rr_r('p-zm1-void')),
                             'audit', pg_temp.rr_delta('zm1-void'),
                             'conflict_rows', pg_temp.rr_m10_audit_rows('zm1'),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm1')) = pg_temp.rr_r('row-zm1-0'),
                             'so_unchanged', to_jsonb(pg_temp.rr_so('zm1', 2)) = pg_temp.rr_r('so-zm1-0'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0')),
          jsonb_build_object('response', pg_temp.rr_m10_resp(pg_temp.rr_m10_conflict('zm1', 'order.void')),
                             'audit', jsonb_build_object('sync.operation_conflict', 1),
                             'conflict_rows', jsonb_build_array(pg_temp.rr_m10_audit_one('zm1', 3, 'payment.create', 'order.void')),
                             'row_unchanged', true, 'so_unchanged', true, 'world_delta', '{}'::jsonb),
          'RR-228 M10 (API 4.55.7): d2''s manager pushes order.void for the same order under the attempt''s local_operation_id WITHOUT recording_resume: the whole response is exactly {ok:true, results:[{ok:false, error:conflict, detail:idempotency key already used for a different operation/payload, status:conflict, idempotency_replay:false}]} (valid-device path, no device_revoked key); the only audit row is one sync.operation_conflict, exactly: the manager''s profile as actor, no app user, d2, reason and old values null, detail {stored_operation_type payment.create, pushed_operation_type order.void, stored_status rejected, reason idempotency_key_reused_with_different_operation_or_payload}; the attempt row and the sync row byte-identical, no row added anywhere');
select pg_temp.rr_snap('zm1-top');
set local role authenticated;
select pg_temp.rr_push('p-zm1-void-top', 3,
  jsonb_build_array(pg_temp.rr_m10_op('zm1', 'order.void', '{}'::jsonb, '{"recording_resume": 0}'::jsonb)), 2);
reset role;
select is(jsonb_build_object('response', pg_temp.rr_ts(pg_temp.rr_r('p-zm1-void-top')),
                             'audit', pg_temp.rr_delta('zm1-top'),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm1')) = pg_temp.rr_r('row-zm1-0'),
                             'so_unchanged', to_jsonb(pg_temp.rr_so('zm1', 2)) = pg_temp.rr_r('so-zm1-0'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0')),
          jsonb_build_object('response', pg_temp.rr_m10_resp(pg_temp.rr_bad_resume('zm1', 'order.void')),
                             'audit', '{}'::jsonb, 'row_unchanged', true, 'so_unchanged', true, 'world_delta', '{}'::jsonb),
          'RR-229 M10 (API 4.14, the protected recording_resume parse): the same order.void WITH the top-level recording_resume 0 is refused per operation exactly {ok:false, error:invalid_payload, detail:recording_resume, status:rejected, idempotency_replay:false} before the fingerprint and ledger steps: no audit row at all, the attempt row and the sync row byte-identical, no row added anywhere (orders, shifts, drawers, payments, sync rows, attempts, private events)');
select pg_temp.rr_snap('zm1-inpl');
set local role authenticated;
select pg_temp.rr_push('p-zm1-void-inpl', 3,
  jsonb_build_array(pg_temp.rr_m10_op('zm1', 'order.void', '{"recording_resume": 0}'::jsonb)), 2);
reset role;
select is(jsonb_build_object('payload_key', (pg_temp.rr_m10_op('zm1', 'order.void', '{"recording_resume": 0}'::jsonb) -> 'payload')
                                            ? 'recording_resume',
                             'top_level_key', pg_temp.rr_m10_op('zm1', 'order.void', '{"recording_resume": 0}'::jsonb) ? 'recording_resume',
                             'response', pg_temp.rr_ts(pg_temp.rr_r('p-zm1-void-inpl')),
                             'audit', pg_temp.rr_delta('zm1-inpl'),
                             'conflict_rows', pg_temp.rr_m10_audit_rows('zm1'),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm1')) = pg_temp.rr_r('row-zm1-0'),
                             'so_unchanged', to_jsonb(pg_temp.rr_so('zm1', 2)) = pg_temp.rr_r('so-zm1-0'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0')),
          jsonb_build_object('payload_key', true, 'top_level_key', false,
                             'response', pg_temp.rr_m10_resp(pg_temp.rr_m10_conflict('zm1', 'order.void')),
                             'audit', jsonb_build_object('sync.operation_conflict', 1),
                             'conflict_rows', jsonb_build_array(pg_temp.rr_m10_audit_one('zm1', 3, 'payment.create', 'order.void'),
                                                                pg_temp.rr_m10_audit_one('zm1', 3, 'payment.create', 'order.void')),
                             'row_unchanged', true, 'so_unchanged', true, 'world_delta', '{}'::jsonb),
          'RR-230 M10: the same order.void with recording_resume 0 INSIDE its payload (payload data under the fingerprint, not the top-level control key) takes the preamble''s conflict exactly as RR-228: the same conflict response and exactly one more identical sync.operation_conflict row (two in all for the identity), nothing else audited; the attempt row and the sync row byte-identical, no row added anywhere');

-- AA.2 Every other operation type of the dispatcher, plain and with the top-level control key.
select pg_temp.rr_snap('zm1-matrix');
set local role authenticated;
select pg_temp.rr_push('p-zm1-plain-' || t, 3, jsonb_build_array(pg_temp.rr_m10_op('zm1', t)), 2)
  from unnest(pg_temp.rr_m10_types()) t where t <> 'order.void';
select pg_temp.rr_push('p-zm1-top-' || t, 3,
         jsonb_build_array(pg_temp.rr_m10_op('zm1', t, '{}'::jsonb, '{"recording_resume": 0}'::jsonb)), 2)
  from unnest(pg_temp.rr_m10_types()) t where t <> 'order.void';
reset role;
select is(jsonb_build_object('types', (select count(*) from unnest(pg_temp.rr_m10_types()) t where t <> 'order.void'),
                             'plain', (select jsonb_object_agg(t, pg_temp.rr_ts(pg_temp.rr_r('p-zm1-plain-' || t)))
                                         from unnest(pg_temp.rr_m10_types()) t where t <> 'order.void'),
                             'top', (select jsonb_object_agg(t, pg_temp.rr_ts(pg_temp.rr_r('p-zm1-top-' || t)))
                                       from unnest(pg_temp.rr_m10_types()) t where t <> 'order.void'),
                             'audit', pg_temp.rr_delta('zm1-matrix'),
                             'conflict_rows', pg_temp.rr_m10_audit_rows('zm1'),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm1')) = pg_temp.rr_r('row-zm1-0'),
                             'so_unchanged', to_jsonb(pg_temp.rr_so('zm1', 2)) = pg_temp.rr_r('so-zm1-0'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0')),
          jsonb_build_object('types', 16,
                             'plain', (select jsonb_object_agg(t, pg_temp.rr_m10_resp(pg_temp.rr_m10_conflict('zm1', t)))
                                         from unnest(pg_temp.rr_m10_types()) t where t <> 'order.void'),
                             'top', (select jsonb_object_agg(t, pg_temp.rr_m10_resp(pg_temp.rr_bad_resume('zm1', t)))
                                       from unnest(pg_temp.rr_m10_types()) t where t <> 'order.void'),
                             'audit', jsonb_build_object('sync.operation_conflict', 16),
                             'conflict_rows', (select jsonb_agg(x order by x)
                                                 from (select pg_temp.rr_m10_audit_one('zm1', 3, 'payment.create', t) x
                                                         from unnest(pg_temp.rr_m10_types() || array['order.void']) t) s),
                             'row_unchanged', true, 'so_unchanged', true, 'world_delta', '{}'::jsonb),
          'RR-231 M10 (the type change, every type): each of the dispatcher''s 16 other operation types (shift.open, order.submit, order.discount, shift.close, order.status, order.table_move, menu.availability_set, table.status_set, table.link, table.unlink, order.void_ack, order.items_add, order.round_status, cash_drawer.no_sale_open, order.edit, order.edit_ack), pushed alone by the manager under the attempt''s local_operation_id, is exactly the preamble''s conflict response with exactly one sync.operation_conflict row each (stored payment.create / rejected, pushed that type; 18 rows in all for the identity); each with the top-level recording_resume 0 is exactly invalid_payload / recording_resume and writes no audit row; the attempt row and the sync row byte-identical, no row added anywhere');
select is(jsonb_build_object('resume', pg_temp.rr_resume_state2('zm1'),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm1')) = pg_temp.rr_r('row-zm1-0'),
                             'stored_refusal', jsonb_build_object('refusal_code', (pg_temp.rr_att2('zm1')).refusal_code,
                                                 'refused_at_kept', (pg_temp.rr_att2('zm1')).recording_refused_at
                                                                    = (pg_temp.rr_r('row-zm1-0') ->> 'recording_refused_at')::timestamptz),
                             'histories', jsonb_build_object('resume', (pg_temp.rr_att2('zm1')).recording_resume_history,
                                                             'refusal', (pg_temp.rr_att2('zm1')).recording_refusal_history),
                             'resume_evidence', pg_temp.rr_resume_audits('zm1', 'refused') + pg_temp.rr_resume_audits('zm1', 'dispatched'),
                             'private_events', pg_temp.rr_ev2_n('zm1') - (pg_temp.rr_r('ev-zm1-0') #>> '{}')::bigint,
                             'derive', pg_temp.rr_derive2('zm1'),
                             'envelope', pg_temp.rr_ts(app.card_attempt_envelope(pg_temp.rr_att2('zm1')))),
          jsonb_build_object('resume', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                         'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                             'row_unchanged', true,
                             'stored_refusal', jsonb_build_object('refusal_code', 'revoked_employee', 'refused_at_kept', true),
                             'histories', jsonb_build_object('resume', '[]'::jsonb, 'refusal', '[]'::jsonb),
                             'resume_evidence', 0, 'private_events', 0,
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true),
                             'envelope', pg_temp.rr_env_exp('zm1', 'approved_unrecorded', 'revoked_employee', true, 0)),
          'RR-232 M10 no reopen: after the 35 type-changed pushes of RR-228..RR-231 the attempt row is byte-identical: recording_resume_count 0, recording_resume_history and recording_refusal_history still empty, the stored refusal kept (refusal_code revoked_employee, recording_refused_at unchanged); no card_attempt.recording_resume_requested row (refused or dispatched) and no private event; it still derives approved_unrecorded / recording_refused, recoverable true, and its envelope is unchanged');
select is(jsonb_build_object('so_unchanged', to_jsonb(pg_temp.rr_so('zm1', 2)) = pg_temp.rr_r('so-zm1-0'),
                             'so', pg_temp.rr_so_state('zm1', 2) || jsonb_build_object('operation_type', (pg_temp.rr_so('zm1', 2)).operation_type),
                             'identity_rows', pg_temp.rr_so_n(array['zm1'], 2),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0')),
          jsonb_build_object('so_unchanged', true,
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', '42501', 'retry_count', 0,
                                     'result', jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', '42501',
                                                                  'detail', 'revoked_employee'),
                                     'reason', 'revoked_employee', 'operation_type', 'payment.create'),
                             'identity_rows', 1, 'world_delta', '{}'::jsonb),
          'RR-233 M10: the identity''s sync row is byte-identical (payment.create, rejected / permanent / 42501, retry_count 0, the stored revoked_employee result and reason, updated_at unchanged), still the only row of that identity, and none of the 35 pushes added a ledger row in the pilot organization (the protected-parse refusals and the conflicts write none)');
select is(jsonb_build_object('ctx_unchanged', pg_temp.rr_m10_ctx('zm1') = pg_temp.rr_r('ctx-zm1-0'),
                             'order', (select jsonb_build_object('status', o.status, 'revision', o.revision)
                                         from public.orders o where o.id = pg_temp.rr_ord('zm1')),
                             'order_payments', pg_temp.rr_order_pay_n('zm1'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0'),
                             'audit', pg_temp.rr_delta('zm1t')),
          jsonb_build_object('ctx_unchanged', true,
                             'order', jsonb_build_object('status', 'submitted', 'revision', 1),
                             'order_payments', 0, 'world_delta', '{}'::jsonb,
                             'audit', jsonb_build_object('sync.operation_conflict', 18)),
          'RR-234 M10 no dispatch, no payment: the order row (still submitted, revision 1, never voided), the frozen shift and drawer rows are byte-identical, the order has no payment, no row was added to orders, shifts, drawers, payments, sync rows, attempts or private events, and the whole pilot-organization audit since RR-227 is exactly 18 sync.operation_conflict rows (no dispatched RPC''s audit, no sync.operation_rejected, no card_attempt row)');

-- AA.3 The same order.void pushes on the revoked-device path: d2's pairing suspended (test-only owner update,
--    as section T did for d1) so the push reaches that path; restored right after.
update public.device_pairings dp set status = 'suspended' where dp.id = pg_temp.zc_id('pairing-2');
select pg_temp.rr_snap('zm1-rv');
set local role authenticated;
select pg_temp.rr_push('p-zm1-rv-void', 3, jsonb_build_array(pg_temp.rr_m10_op('zm1', 'order.void')), 2);
select pg_temp.rr_push('p-zm1-rv-top', 3,
  jsonb_build_array(pg_temp.rr_m10_op('zm1', 'order.void', '{}'::jsonb, '{"recording_resume": 0}'::jsonb)), 2);
select pg_temp.rr_push('p-zm1-rv-inpl', 3,
  jsonb_build_array(pg_temp.rr_m10_op('zm1', 'order.void', '{"recording_resume": 0}'::jsonb)), 2);
reset role;
update public.device_pairings dp set status = 'active' where dp.id = pg_temp.zc_id('pairing-2');
select is(jsonb_build_object('void', pg_temp.rr_ts(pg_temp.rr_r('p-zm1-rv-void')),
                             'top', pg_temp.rr_ts(pg_temp.rr_r('p-zm1-rv-top')),
                             'inpl', pg_temp.rr_ts(pg_temp.rr_r('p-zm1-rv-inpl')),
                             'audit', pg_temp.rr_delta('zm1-rv'),
                             'order_void_conflict_rows', (select count(*) from jsonb_array_elements(pg_temp.rr_m10_audit_rows('zm1')) x
                                                           where x = pg_temp.rr_m10_audit_one('zm1', 3, 'payment.create', 'order.void')),
                             'conflict_rows', jsonb_array_length(pg_temp.rr_m10_audit_rows('zm1')),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm1')) = pg_temp.rr_r('row-zm1-0'),
                             'so_unchanged', to_jsonb(pg_temp.rr_so('zm1', 2)) = pg_temp.rr_r('so-zm1-0'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0')),
          jsonb_build_object('void', pg_temp.rr_m10_resp(pg_temp.rr_m10_conflict('zm1', 'order.void'), true),
                             'top', pg_temp.rr_m10_resp(pg_temp.rr_bad_resume('zm1', 'order.void'), true),
                             'inpl', pg_temp.rr_m10_resp(pg_temp.rr_m10_conflict('zm1', 'order.void'), true),
                             'audit', jsonb_build_object('sync.operation_conflict', 2),
                             'order_void_conflict_rows', 4, 'conflict_rows', 20,
                             'row_unchanged', true, 'so_unchanged', true, 'world_delta', '{}'::jsonb),
          'RR-235 M10 on the revoked-device path (d2''s pairing suspended): the plain order.void and the order.void with recording_resume inside its payload are each exactly the preamble''s conflict (response device_revoked true) with one more identical sync.operation_conflict row each (20 rows in all for the identity), the order.void with the top-level recording_resume 0 is exactly invalid_payload / recording_resume with no audit row; that path never reopens: the attempt row and the sync row byte-identical, no row added anywhere');

-- AA.4 Positive control: the manager's genuine Resume of that leg (payment.create, recording_resume 0) now.
select pg_temp.rr_snap('zm1-r');
set local role authenticated;
select pg_temp.rr_push('p-zm1-r', 3, jsonb_build_array(pg_temp.rr_leg('zm1', 'zm1', '{"recording_resume": 0}')), 2);
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-zm1-r') ->> 'status',
                             'resume', pg_temp.rr_resume_state2('zm1'),
                             'refusal_entry', (pg_temp.rr_att2('zm1')).recording_refusal_history -> 0,
                             'resume_entry', ((pg_temp.rr_att2('zm1')).recording_resume_history -> 0) - 'at',
                             'recorded', pg_temp.rr_derive2('zm1') -> 'recorded',
                             'taken_by', (select p.taken_by_employee_profile_id from public.payments p
                                           where p.device_id = pg_temp.zc_id('device-2')
                                             and p.local_operation_id = pg_temp.zc_lop('zm1')),
                             'world_delta', pg_temp.rr_m10_world_delta('zm1-0'),
                             'card_sync_audit', pg_temp.rr_delta('zm1-r', 'card_attempt.%') || pg_temp.rr_delta('zm1-r', 'sync.%')),
          jsonb_build_object('status', 'applied',
                             'resume', jsonb_build_object('so', 'applied', 'retry_count', 1, 'resume_count', 1,
                                         'resume_history', 1, 'refusal_history', 1, 'payments', 1),
                             'refusal_entry', jsonb_build_object('refusal_code', 'revoked_employee',
                                                'refused_at', pg_temp.rr_r('row-zm1-0') -> 'recording_refused_at'),
                             'resume_entry', jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-3'),
                                               'membership_id', pg_temp.zc_id('membership-3'), 'resume_count', 0),
                             'recorded', true, 'taken_by', pg_temp.zc_id('employee-3'),
                             'world_delta', jsonb_build_object('payments', 1),
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-236 M10 positive control: after the 38 type-changed pushes the manager''s genuine Resume of the leg (payment.create, recording_resume 0) is authorized and records exactly once (applied, the manager its actor, count 1, retry_count 1, both histories one entry; exactly one payment added, no other row added since RR-227); the refusal it appends is exactly the stored report the type-changed pushes left untouched (revoked_employee at the original recording_refused_at); the only card / sync audit row is that one card_attempt.recording_resume_requested');

-- AA.5 The reverse direction: an order.void stored first under an attempt identity (zm2, no leg pushed yet).
set local role service_role;
insert into _zc_r select 'c-zm2', pg_temp.rr_claim2('zm2');
insert into _zc_r select 'f-zm2', pg_temp.rr_fin('zm2', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
insert into _zc_r select 'row-zm2-pre', to_jsonb(pg_temp.rr_att2('zm2'));
insert into _zc_r select 'ctx-zm2-pre', pg_temp.rr_m10_ctx('zm2');
select pg_temp.rr_m10_world_snap('zm2-pre');
select pg_temp.rr_snap('zm2v');
set local role authenticated;
select pg_temp.rr_push('p-zm2-void', 3, jsonb_build_array(pg_temp.rr_m10_op('zm2', 'order.void')), 2);
reset role;
select is(jsonb_build_object('claim_created', pg_temp.rr_r('c-zm2') -> 'claim_created',
                             'state', (pg_temp.rr_att2('zm2')).state,
                             'result', pg_temp.rr_ts(pg_temp.rr_res('p-zm2-void')),
                             'so', jsonb_build_object('operation_type', (pg_temp.rr_so('zm2', 2)).operation_type,
                                     'status', (pg_temp.rr_so('zm2', 2)).status, 'class', (pg_temp.rr_so('zm2', 2)).last_error_class,
                                     'code', (pg_temp.rr_so('zm2', 2)).last_error_code, 'reason', (pg_temp.rr_so('zm2', 2)).rejection_reason,
                                     'retry_count', (pg_temp.rr_so('zm2', 2)).retry_count,
                                     'result', pg_temp.rr_ts((pg_temp.rr_so('zm2', 2)).result)),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm2')) = pg_temp.rr_r('row-zm2-pre'),
                             'ctx_unchanged', pg_temp.rr_m10_ctx('zm2') = pg_temp.rr_r('ctx-zm2-pre'),
                             'order_payments', pg_temp.rr_order_pay_n('zm2'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm2-pre'),
                             'audit', pg_temp.rr_delta('zm2v'),
                             'derive', pg_temp.rr_derive2('zm2')),
          jsonb_build_object('claim_created', true, 'state', 'approved',
                             'result', jsonb_build_object('ok', false, 'error', 'payment_in_progress', 'detail', 'card_attempt_active',
                                         'order_id', pg_temp.rr_ord('zm2'), 'server_ts?', true,
                                         'local_operation_id', pg_temp.zc_lop('zm2'), 'operation_type', 'order.void',
                                         'status', 'rejected', 'idempotency_replay', false),
                             'so', jsonb_build_object('operation_type', 'order.void', 'status', 'rejected', 'class', 'permanent',
                                     'code', 'payment_in_progress', 'reason', 'payment_in_progress', 'retry_count', 0,
                                     'result', jsonb_build_object('ok', false, 'error', 'payment_in_progress',
                                                 'detail', 'card_attempt_active', 'order_id', pg_temp.rr_ord('zm2'),
                                                 'server_ts?', true)),
                             'row_unchanged', true, 'ctx_unchanged', true, 'order_payments', 0,
                             'world_delta', jsonb_build_object('sync_rows', 1),
                             'audit', jsonb_build_object('sync.operation_rejected', 1),
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'pending_recording', false)),
          'RR-237 setup (M10, the reverse direction): a second LIVE attempt of d2 (zm2) approved with no leg pushed; d2''s manager pushes order.void for that order under the attempt''s local_operation_id first: the claim guard refuses it exactly {ok:false, error:payment_in_progress, detail:card_attempt_active}, stored as an order.void row rejected / permanent / payment_in_progress (the only row added) with one sync.operation_rejected; the order, its frozen shift / drawer and the attempt row are byte-identical (not voided, no payment) and the attempt still derives approved_unrecorded / pending_recording');
insert into _zc_r select 'row-zm2-0', to_jsonb(pg_temp.rr_att2('zm2'));
insert into _zc_r select 'so-zm2-0', to_jsonb(pg_temp.rr_so('zm2', 2));
select pg_temp.rr_m10_world_snap('zm2-0');
select pg_temp.rr_snap('zm2c');
set local role authenticated;
select pg_temp.rr_push('p-zm2-leg', 8, jsonb_build_array(pg_temp.rr_leg('zm2')), 2);
select pg_temp.rr_push('p-zm2-resume', 3, jsonb_build_array(pg_temp.rr_leg('zm2', 'zm2', '{"recording_resume": 0}')), 2);
reset role;
select is(jsonb_build_object('leg', pg_temp.rr_ts(pg_temp.rr_r('p-zm2-leg')),
                             'resume', pg_temp.rr_ts(pg_temp.rr_r('p-zm2-resume')),
                             'audit', pg_temp.rr_delta('zm2c'),
                             'conflict_rows', pg_temp.rr_m10_audit_rows('zm2'),
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('zm2')) = pg_temp.rr_r('row-zm2-0'),
                             'resume_count', (pg_temp.rr_att2('zm2')).recording_resume_count,
                             'so_unchanged', to_jsonb(pg_temp.rr_so('zm2', 2)) = pg_temp.rr_r('so-zm2-0'),
                             'world_delta', pg_temp.rr_m10_world_delta('zm2-0'),
                             'order_payments', pg_temp.rr_order_pay_n('zm2')),
          jsonb_build_object('leg', pg_temp.rr_m10_resp(pg_temp.rr_m10_conflict('zm2', 'payment.create')),
                             'resume', pg_temp.rr_m10_resp(pg_temp.rr_m10_conflict('zm2', 'payment.create')),
                             'audit', jsonb_build_object('sync.operation_conflict', 2),
                             'conflict_rows', (select jsonb_agg(x order by x)
                                                 from (select pg_temp.rr_m10_audit_one('zm2', n, 'order.void', 'payment.create') x
                                                         from unnest(array[8, 3]) n) s),
                             'row_unchanged', true, 'resume_count', 0, 'so_unchanged', true, 'world_delta', '{}'::jsonb,
                             'order_payments', 0),
          'RR-238 M10 (the reverse direction): under that identity the attempt''s own canonical leg (the cashier) and the same leg carrying recording_resume 0 (the manager) are each exactly the preamble''s conflict: one sync.operation_conflict each (stored order.void / rejected, pushed payment.create; actors the cashier and the manager), no Resume evidence or reopen (resume_count 0, the attempt row and the stored order.void row byte-identical), no payment, no row added anywhere');

-- ===========================================================================
-- C1 delta review: the D-054 Resume guard's own write never advances the snapshot claim signal (D-059 point 1).
-- ===========================================================================
select is(jsonb_build_object(
            'signal_present', (pg_temp.rr_r('row-rs10-before') ->> 'claim_signal_at') is not null,
            'resume_count_delta', (pg_temp.rr_r('row-rs10-after') ->> 'recording_resume_count')::int
                                  - (pg_temp.rr_r('row-rs10-before') ->> 'recording_resume_count')::int,
            'histories_grown', jsonb_array_length(pg_temp.rr_r('row-rs10-after') -> 'recording_resume_history')
                               - jsonb_array_length(pg_temp.rr_r('row-rs10-before') -> 'recording_resume_history'),
            'state', pg_temp.rr_r('row-rs10-after') ->> 'state',
            'freed_or_resolved', (pg_temp.rr_r('row-rs10-after') ->> 'order_freed_at') is not null
                                 or (pg_temp.rr_r('row-rs10-after') ->> 'resolution') is not null,
            'signal_kept', pg_temp.rr_r('row-rs10-after') -> 'claim_signal_at'
                           = pg_temp.rr_r('row-rs10-before') -> 'claim_signal_at'),
          '{"signal_present": true, "resume_count_delta": 1, "histories_grown": 1, "state": "approved", "freed_or_resolved": false, "signal_kept": true}'::jsonb,
          'RR-239 C1-1 (delta review): the manager Resume of RR-101 / RR-102 - the D-054 guard''s own write of recording_resume_count and its two histories, whose re-dispatch then failed transiently - leaves the attempt approved, unfreed and unresolved with its claim_signal_at unchanged (a Resume counter never advances the snapshot claim signal)');

-- ===========================================================================
-- AB. Correction C2 (D-060 point 1; packet section 13.1 and the section 13.5
--     RR plan; TEST_BRIEF_C2 lane RR): change 7 of app.sync_push - the
--     support-context admission guard - through public.sync_push as
--     authenticated. A request whose verified JWT caller holds an ACTIVE
--     platform support session (app.current_support_session(): status active,
--     token consumed, not expired) is refused first, with this entrypoint's
--     request-level refusal (a raised SQLSTATE 42501 'sync_push: permission
--     denied (active support session)'; no JSON result, no per-operation
--     result, no partial batch): before the batch-shape checks, the PIN /
--     device proof, the terminal lock, the single-operation check and both
--     paths, so before any ledger claim, replay, Resume or dispatch. It writes
--     nothing and discloses nothing. d1 is management-revoked since section T
--     (sticky: staff 1 / staff 2 hold no valid till any more), so - as sections
--     U-AA - the valid cashier is d2's (staff 8) and the valid manager d2's
--     (staff 3); d2 holds the organization's only enabled LIVE binding (a
--     hand-recorded card tender there is card_terminal_required, section B),
--     so the hand-recorded card tender runs on d5, cashier staff 10's
--     sibling-branch till, which holds no binding. The support admin is a
--     fresh auth user linked to a fresh app user (no membership) with an
--     active platform-admin grant and an ACTIVE support session on the pilot
--     organization (the claim_identity CI-319 / CI-324 inserts);
--     request.jwt.claim.sub names it for the support calls and is restored to
--     the transport principal after them. Outside support - the transport
--     principal, a dual-role owner (staff 9, the org_owner, linked to its own
--     auth user with an active platform-admin grant and no support session,
--     pushing with its own valid PIN on d2) and ended / expired / un-exchanged
--     (pending) / unconsumed sessions - pushes behave as before. The owner
--     writes of AB: the synthetic identities and support sessions, staff 9's
--     auth link, grant and fresh PIN session on d2, the revoke / restore of the
--     d2 cashier's membership that produces the recoverable refusal the Resume
--     needs (as V-AA) and the suspend / restore of d2's pairing (as AA.3); no
--     owner update touches an attempt, a sync row, a payment, a receipt
--     counter or an audit row.
-- ===========================================================================
-- Labels of the AB identities (owner-side lookups only, so no assertion ever prints an id).
create temp table _rr_c2_lbl (id uuid primary key, label text not null);
insert into _rr_c2_lbl
select pg_temp.zc_id(l), l from unnest(array['transport-principal', 'rr-c2-dual-auth', 'user-9', 'device-1', 'device-2',
                                             'device-5']) l
union all select pg_temp.zc_id('employee-' || n), 'employee-' || n from generate_series(1, 10) n;
create function pg_temp.rr_c2_lbl(p_id uuid) returns text language sql stable as
$$ select case when p_id is null then null
               else coalesce((select l.label from _rr_c2_lbl l where l.id = rr_c2_lbl.p_id), 'unlabelled') end $$;
-- A synthetic platform admin 'rr-c2-<key>': a JWT principal (auth user) linked to a fresh app user with no
-- membership, an active platform-admin grant and at most one support session of the pilot organization in
-- the given lifecycle (owner-inserted; the 126 lifecycle columns set directly, as claim_identity CI-324).
create function pg_temp.rr_c2_admin(p_key text, p_status text, p_consumed boolean, p_expires interval)
returns boolean language plpgsql volatile as $$
declare
  v_auth uuid := pg_temp.zc_id('rr-c2-' || p_key || '-auth');
  v_user uuid := pg_temp.zc_id('rr-c2-' || p_key || '-user');
begin
  insert into auth.users (id, email) values (v_auth, 'zc001d-rr-c2-' || p_key || '@example.test');
  insert into public.app_users (id, email, auth_user_id)
  values (v_user, 'zc001d-rr-c2-' || p_key || '@example.test', v_auth);
  insert into public.platform_admin_grants (app_user_id, status, granted_by) values (v_user, 'active', v_user);
  insert into _rr_c2_lbl values (v_auth, 'rr-c2-' || p_key || '-auth'), (v_user, 'rr-c2-' || p_key || '-user');
  if p_status is not null then
    insert into public.platform_support_sessions (id, platform_admin_app_user_id, target_organization_id, reason,
        status, expires_at, created_at, ended_at, token_hash, token_consumed_at)
    values (pg_temp.zc_id('rr-c2-' || p_key || '-session'), v_user, pg_temp.zc_org(),
        'ZC001D synthetic RR support session ' || p_key, p_status, now() + p_expires, now() - interval '20 minutes',
        case when p_status = 'ended' then now() end, 'zc001d-rr-c2-' || p_key || '-token-hash',
        case when p_consumed then now() - interval '5 minutes' end);
    insert into _rr_c2_lbl values (pg_temp.zc_id('rr-c2-' || p_key || '-session'), 'rr-c2-' || p_key || '-session');
  end if;
  return true;
end $$;
-- The verified JWT caller of the next calls (request.jwt.claim.sub, transaction-local); prints true only.
create function pg_temp.rr_c2_as(label text) returns boolean language sql volatile as
$$ select set_config('request.jwt.claim.sub', pg_temp.zc_id(rr_c2_as.label)::text, true) is not null $$;
-- What the JWT of auth user 'label' resolves to (the GUC restored after): its app user, the support predicate
-- app.current_support_session() and the platform-admin flag.
create function pg_temp.rr_c2_resolve(label text) returns jsonb language plpgsql volatile as $$
declare
  v_prev text := current_setting('request.jwt.claim.sub', true);
  r jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.zc_id(rr_c2_resolve.label)::text, true);
  r := jsonb_build_object('app_user', pg_temp.rr_c2_lbl(app.current_app_user_id()),
         'support_session', pg_temp.rr_c2_lbl(app.current_support_session()), 'platform_admin', app.is_platform_admin());
  perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
  return r;
end $$;
-- Content digests (every column plus the tuple's ctid, so even an update writing identical values shows) of
-- every row a push could write or touch in both fixture organizations - payments, receipt counters, orders,
-- shifts, drawers, sync rows, tenant audit, attempts, private events, device sessions, devices, PIN sessions,
-- the support sessions and the platform-admin audit - a snapshot of them, and the keys whose digest changed
-- since the snapshot ('[]' = nothing written or touched). Read as owner.
create function pg_temp.rr_c2_world() returns jsonb language sql stable as $$
  with o(id) as (select unnest(array[pg_temp.zc_org(), pg_temp.zc_id('org_b')]))
  select jsonb_build_object(
    'payments', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                   from public.payments t where t.organization_id in (select id from o)),
    'receipt_counters', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                           from public.branch_receipt_counters t where t.organization_id in (select id from o)),
    'orders', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                 from public.orders t where t.organization_id in (select id from o)),
    'shifts', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                 from public.shifts t where t.organization_id in (select id from o)),
    'cash_drawer_sessions', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                               from public.cash_drawer_sessions t where t.organization_id in (select id from o)),
    'sync_operations', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                          from public.sync_operations t where t.organization_id in (select id from o)),
    'audit_events', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                       from public.audit_events t where t.organization_id in (select id from o)),
    'card_provider_attempts', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                                 from app.card_provider_attempts t where t.organization_id in (select id from o)),
    'card_provider_private_events', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                                       from app.card_provider_private_events t where t.organization_id in (select id from o)),
    'device_sessions', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                          from public.device_sessions t where t.organization_id in (select id from o)),
    'devices', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                  from public.devices t where t.organization_id in (select id from o)),
    'pin_sessions', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                       from public.pin_sessions t where t.organization_id in (select id from o)),
    'platform_support_sessions', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                                    from public.platform_support_sessions t
                                   where t.target_organization_id in (select id from o)),
    'platform_admin_audit_events', (select md5(coalesce(string_agg(t.ctid::text || to_jsonb(t)::text, '|' order by t.id), ''))
                                      from public.platform_admin_audit_events t
                                     where t.target_organization_id in (select id from o)
                                        or t.actor_app_user_id in (select l.id from _rr_c2_lbl l))) $$;
create function pg_temp.rr_c2_snap(label text) returns boolean language sql volatile as
$$ insert into _zc_r (label, r) values ('c2w-' || rr_c2_snap.label, pg_temp.rr_c2_world()) returning true $$;
create function pg_temp.rr_c2_changed(label text) returns jsonb language sql stable as
$$ select coalesce(jsonb_agg(c.key order by c.key), '[]'::jsonb)
     from jsonb_each(pg_temp.rr_c2_world()) c
     join _zc_r s on s.label = 'c2w-' || rr_c2_changed.label
    where s.r -> c.key is distinct from c.value $$;
-- One public.sync_push call as the current role (authenticated) with an explicit PIN id and operations: its
-- JSON result, or the raised SQLSTATE, message, DETAIL and HINT (the call's writes rolled back with it).
create function pg_temp.rr_c2_try(label text, pin uuid, d integer, ops jsonb) returns boolean
language plpgsql volatile as $$
declare
  v_state text;
  v_msg text;
  v_detail text;
  v_hint text;
begin
  insert into _zc_r (label, r)
  values (rr_c2_try.label, public.sync_push(rr_c2_try.pin, pg_temp.zc_id('device-' || rr_c2_try.d), rr_c2_try.ops));
  return true;
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text, v_detail = pg_exception_detail,
                          v_hint = pg_exception_hint;
  insert into _zc_r (label, r)
  values (rr_c2_try.label, jsonb_build_object('__error__', v_state, 'message', v_msg, 'detail', v_detail, 'hint', v_hint));
  return false;
end $$;
-- An expected request-level refusal: SQLSTATE 42501 with exactly this message and no DETAIL / HINT.
create function pg_temp.rr_c2_err(msg text) returns jsonb language sql immutable as
$$ select jsonb_build_object('__error__', '42501', 'message', msg, 'detail', '', 'hint', '') $$;
create function pg_temp.rr_c2_sup_err() returns jsonb language sql immutable as
$$ select pg_temp.rr_c2_err('sync_push: permission denied (active support session)') $$;
-- Status / revision of the orders of the given labels.
create function pg_temp.rr_c2_orders(labels text[]) returns jsonb language sql stable as
$$ select coalesce(jsonb_object_agg(l, jsonb_build_object('status', o.status, 'revision', o.revision)), '{}'::jsonb)
     from unnest(rr_c2_orders.labels) l join public.orders o on o.id = pg_temp.rr_ord(l) $$;
-- The payments of label's identity on device d (count and facts; the taker as a label).
create function pg_temp.rr_c2_pay(label text, d integer) returns jsonb language sql stable as
$$ select jsonb_build_object('n', count(*), 'method', min(p.method), 'status', min(p.status),
                             'amount', min(p.amount_minor), 'tendered', min(p.tendered_minor), 'change', min(p.change_minor),
                             'order_matches', bool_and(p.order_id = pg_temp.rr_ord(rr_c2_pay.label)),
                             'taken_by', min(pg_temp.rr_c2_lbl(p.taken_by_employee_profile_id)))
     from public.payments p where p.device_id = pg_temp.zc_id('device-' || rr_c2_pay.d)
                              and p.local_operation_id = pg_temp.zc_lop(rr_c2_pay.label) $$;
-- The summary of one applied payment.create response (the whole response held in _zc_r under label).
create function pg_temp.rr_c2_applied(label text) returns jsonb language sql stable as
$$ select jsonb_build_object('ok', z.r -> 'ok', 'n_results', jsonb_array_length(z.r -> 'results'),
                             'result_ok', z.r -> 'results' -> 0 -> 'ok', 'status', z.r -> 'results' -> 0 ->> 'status',
                             'method', z.r -> 'results' -> 0 ->> 'method',
                             'replay', z.r -> 'results' -> 0 -> 'idempotency_replay')
     from _zc_r z where z.label = rr_c2_applied.label $$;
create function pg_temp.rr_c2_applied_exp(method text) returns jsonb language sql immutable as
$$ select jsonb_build_object('ok', true, 'n_results', 1, 'result_ok', true, 'status', 'applied', 'method', method,
                             'replay', false) $$;
-- The receipt counter of a branch of the pilot organization (0 before its first receipt).
create function pg_temp.rr_c2_counter(branch uuid) returns bigint language sql stable as
$$ select coalesce((select c.last_issued_value from public.branch_receipt_counters c
                     where c.organization_id = pg_temp.zc_org() and c.branch_id = rr_c2_counter.branch), 0) $$;
-- The envelopes of AB (label = identity = order unless noted): the hand-recorded card tender of d5.
create function pg_temp.rr_c2_card5() returns jsonb language sql immutable as
$$ select pg_temp.zc_pay_op(pg_temp.zc_lop('c2b5'), pg_temp.rr_ord('c2b5'), 'card', 1234) $$;

-- The identities: the support admin (ACTIVE session) and one admin per non-refusing session state; staff 9
-- (the org_owner) becomes a dual-role owner: its own auth user, an active platform-admin grant, no support
-- session, and a fresh own PIN session on d2 (staff 9's fixture PIN sits on revoked d1).
select pg_temp.rr_c2_admin('sup', 'active', true, interval '10 minutes') as support_admin,
       pg_temp.rr_c2_admin('ended', 'ended', true, interval '10 minutes') as ended,
       pg_temp.rr_c2_admin('expired', 'active', true, interval '-5 minutes') as expired,
       pg_temp.rr_c2_admin('pending', 'pending', false, interval '10 minutes') as unexchanged,
       pg_temp.rr_c2_admin('unconsumed', 'active', false, interval '10 minutes') as active_unconsumed;
insert into auth.users (id, email) values (pg_temp.zc_id('rr-c2-dual-auth'), 'zc001d-rr-c2-dual@example.test');
update public.app_users u set auth_user_id = pg_temp.zc_id('rr-c2-dual-auth') where u.id = pg_temp.zc_id('user-9');
insert into public.platform_admin_grants (app_user_id, status, granted_by)
values (pg_temp.zc_id('user-9'), 'active', pg_temp.zc_id('rr-c2-sup-user'));
insert into public.pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id,
                                 resolved_membership_id, expires_at)
values (pg_temp.zc_id('rr-c2-pin-9'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('dsession-2'),
        pg_temp.zc_id('employee-9'), pg_temp.zc_id('membership-9'), now() + interval '6 hours');
select is(jsonb_build_object(
            'resolve', (select jsonb_object_agg(a, pg_temp.rr_c2_resolve(a)) from unnest(array['transport-principal',
                          'rr-c2-sup-auth', 'rr-c2-dual-auth', 'rr-c2-ended-auth', 'rr-c2-expired-auth', 'rr-c2-pending-auth',
                          'rr-c2-unconsumed-auth']) a),
            'sessions', (select jsonb_object_agg(pg_temp.rr_c2_lbl(s.id), jsonb_build_object('status', s.status,
                            'token_consumed', s.token_consumed_at is not null, 'unexpired', s.expires_at > now(),
                            'ended', s.ended_at is not null, 'pilot_target', s.target_organization_id = pg_temp.zc_org()))
                           from public.platform_support_sessions s
                          where s.platform_admin_app_user_id in (select l.id from _rr_c2_lbl l)),
            'admin_memberships', (select count(*) from public.memberships m
                                   where m.app_user_id in (select l.id from _rr_c2_lbl l where l.label like 'rr-c2-%-user')),
            'dual_pin', (select jsonb_build_object('valid', app.is_pin_session_valid(ps.id),
                                  'device', pg_temp.rr_c2_lbl(ds.device_id), 'employee', pg_temp.rr_c2_lbl(ps.employee_profile_id),
                                  'membership', (select m.role || '/' || m.status from public.memberships m
                                                  where m.id = ps.resolved_membership_id))
                           from public.pin_sessions ps join public.device_sessions ds on ds.id = ps.device_session_id
                          where ps.id = pg_temp.zc_id('rr-c2-pin-9'))),
          jsonb_build_object(
            'resolve', jsonb_build_object(
              'transport-principal', jsonb_build_object('app_user', null, 'support_session', null, 'platform_admin', false),
              'rr-c2-sup-auth', jsonb_build_object('app_user', 'rr-c2-sup-user', 'support_session', 'rr-c2-sup-session',
                                                   'platform_admin', true),
              'rr-c2-dual-auth', jsonb_build_object('app_user', 'user-9', 'support_session', null, 'platform_admin', true),
              'rr-c2-ended-auth', jsonb_build_object('app_user', 'rr-c2-ended-user', 'support_session', null,
                                                     'platform_admin', true),
              'rr-c2-expired-auth', jsonb_build_object('app_user', 'rr-c2-expired-user', 'support_session', null,
                                                       'platform_admin', true),
              'rr-c2-pending-auth', jsonb_build_object('app_user', 'rr-c2-pending-user', 'support_session', null,
                                                       'platform_admin', true),
              'rr-c2-unconsumed-auth', jsonb_build_object('app_user', 'rr-c2-unconsumed-user', 'support_session', null,
                                                          'platform_admin', true)),
            'sessions', jsonb_build_object(
              'rr-c2-sup-session', jsonb_build_object('status', 'active', 'token_consumed', true, 'unexpired', true,
                                                      'ended', false, 'pilot_target', true),
              'rr-c2-ended-session', jsonb_build_object('status', 'ended', 'token_consumed', true, 'unexpired', true,
                                                        'ended', true, 'pilot_target', true),
              'rr-c2-expired-session', jsonb_build_object('status', 'active', 'token_consumed', true, 'unexpired', false,
                                                          'ended', false, 'pilot_target', true),
              'rr-c2-pending-session', jsonb_build_object('status', 'pending', 'token_consumed', false, 'unexpired', true,
                                                          'ended', false, 'pilot_target', true),
              'rr-c2-unconsumed-session', jsonb_build_object('status', 'active', 'token_consumed', false, 'unexpired', true,
                                                             'ended', false, 'pilot_target', true)),
            'admin_memberships', 0,
            'dual_pin', jsonb_build_object('valid', true, 'device', 'device-2', 'employee', 'employee-9',
                                           'membership', 'org_owner/active')),
          'RR-240 setup (C2 lane RR, packet 13.5): each JWT resolves exactly - the transport principal no app user, no support session, no platform admin; the support admin (fresh auth user -> fresh app user, no membership in either organization, active platform-admin grant) app.current_support_session() = its ACTIVE session (status active, token consumed, unexpired, pilot target); the dual-role owner (staff 9, the org_owner, linked to its own auth user, active grant, no session) and the ended, expired, un-exchanged (pending) and unconsumed (active, token not consumed) admins resolve their app user and platform-admin grant but NO active support session; staff 9''s fresh own PIN session on d2 is valid (org_owner / active)');

-- Two LIVE attempts of d2 frozen to its open rr-shift-zm / rr-drawer-zm: c2r1 approved with no leg pushed, and
-- c2m1 approved whose own leg, pushed while the cashier's membership was revoked, is memoized rejected
-- revoked_employee (as RS11 / V-AA), the membership restored right after and the refusal reported by the mark.
insert into _zc_r select 'orders-ab', jsonb_agg(pg_temp.zc_order(l, 1234, 2)) from unnest(array['c2b1', 'c2r1', 'c2m1',
  'c2e1', 'c2e2', 'c2e3', 'c2f1', 'c2g1', 'c2g2', 'c2h9', 'c2i1', 'c2i2', 'c2i3', 'c2i4']) l;
insert into _zc_r select 'orders-ab5', jsonb_agg(pg_temp.zc_order(l, 1234, 5)) from unnest(array['c2b5']) l;
set local role service_role;
insert into _zc_r select 'c-c2r1', pg_temp.rr_claim2('c2r1');
insert into _zc_r select 'f-c2r1', pg_temp.rr_fin('c2r1', 'commit', 'approved', pg_temp.zc_approved_fields());
insert into _zc_r select 'c-c2m1', pg_temp.rr_claim2('c2m1');
insert into _zc_r select 'f-c2m1', pg_temp.rr_fin('c2m1', 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
update public.memberships m set status = 'revoked' where m.id = pg_temp.zc_id('membership-8');
set local role authenticated;
select pg_temp.rr_push('p-c2m1-k', 8, jsonb_build_array(pg_temp.rr_leg('c2m1')), 2);
reset role;
update public.memberships m set status = 'active' where m.id = pg_temp.zc_id('membership-8');
set local role service_role;
insert into _zc_r select 'm-c2m1', pg_temp.rr_markrec2('c2m1');
reset role;
select is(jsonb_build_object(
            'tills', jsonb_build_object(
              'd1_active', (select d.is_active from public.devices d where d.id = pg_temp.zc_id('device-1')),
              'd2_posture', app.card_terminal_posture(pg_temp.zc_org(), pg_temp.zc_branch(), pg_temp.zc_id('device-2')),
              'd2_open_shift_is_zm', (select array_agg(s.id) from public.shifts s
                                       where s.organization_id = pg_temp.zc_org() and s.device_id = pg_temp.zc_id('device-2')
                                         and s.status in ('opening', 'open', 'closing')) = array[pg_temp.zc_id('rr-shift-zm')],
              'd5_bindings', (select count(*) from app.payment_terminals t where t.device_id = pg_temp.zc_id('device-5')),
              'd5_shift_open', (select s.status from public.shifts s where s.id = pg_temp.zc_id('shift-5')),
              'd5_drawers_active', (select count(*) from public.cash_drawer_sessions c
                                     where c.device_id = pg_temp.zc_id('device-5') and c.status = 'active')),
            'c2r1', jsonb_build_object('claim_created', pg_temp.rr_r('c-c2r1') -> 'claim_created',
                                       'state', (pg_temp.rr_att2('c2r1')).state,
                                       'frozen_zm', (pg_temp.rr_att2('c2r1')).shift_id = pg_temp.zc_id('rr-shift-zm')
                                                    and (pg_temp.rr_att2('c2r1')).cash_drawer_session_id = pg_temp.zc_id('rr-drawer-zm'),
                                       'sync_rows', pg_temp.rr_so_n(array['c2r1'], 2),
                                       'derive', pg_temp.rr_derive2('c2r1')),
            'c2m1', jsonb_build_object('claim_created', pg_temp.rr_r('c-c2m1') -> 'claim_created',
                                       'push', pg_temp.rr_res('p-c2m1-k'),
                                       'mark', pg_temp.rr_ts(pg_temp.rr_r('m-c2m1')),
                                       'resume', pg_temp.rr_resume_state2('c2m1'),
                                       'derive', pg_temp.rr_derive2('c2m1'))),
          jsonb_build_object(
            'tills', jsonb_build_object('d1_active', false,
                                        'd2_posture', jsonb_build_object('lifecycle', 'enabled', 'mode', 'live', 'enabled', true),
                                        'd2_open_shift_is_zm', true, 'd5_bindings', 0, 'd5_shift_open', 'open',
                                        'd5_drawers_active', 1),
            'c2r1', jsonb_build_object('claim_created', true, 'state', 'approved', 'frozen_zm', true, 'sync_rows', 0,
                                       'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'pending_recording', false)),
            'c2m1', jsonb_build_object('claim_created', true,
                                       'push', jsonb_build_object('local_operation_id', pg_temp.zc_lop('c2m1'),
                                                 'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                                 'sqlstate', '42501', 'detail', 'revoked_employee', 'status', 'rejected',
                                                 'idempotency_replay', false),
                                       'mark', pg_temp.rr_env_exp('c2m1', 'approved_unrecorded', 'revoked_employee', true, 0),
                                       'resume', jsonb_build_object('so', 'rejected', 'retry_count', 0, 'resume_count', 0,
                                                   'resume_history', 0, 'refusal_history', 0, 'payments', 0),
                                       'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true))),
          'RR-241 setup (C2 lane RR): the tills - d1 inactive (management-revoked, section T), d2 LIVE posture enabled with rr-shift-zm its only open shift, d5 (sibling branch) with no binding row, an open shift and one active drawer; c2r1 is a LIVE attempt of d2''s cashier frozen to rr-shift-zm / rr-drawer-zm, approved, no sync row, deriving approved_unrecorded / pending_recording; c2m1 is approved, its own leg memoized rejected revoked_employee (42501) and reported (envelope approved_unrecorded / refusal revoked_employee, recoverable true, resume_count 0, both histories empty, no payment), deriving recording_refused, recoverable true');
insert into _zc_r select 'row-c2r1-0', to_jsonb(pg_temp.rr_att2('c2r1'));
insert into _zc_r select 'row-c2m1-0', to_jsonb(pg_temp.rr_att2('c2m1'));
insert into _zc_r select 'so-c2m1-0', to_jsonb(pg_temp.rr_so('c2m1', 2));

-- AB.1 (13.5 RR) ACTIVE support + the cashier's valid PIN and device: cash, hand-recorded card, provider leg.
select pg_temp.rr_c2_snap('b') as world_snap;
select pg_temp.rr_snap('c2b');
select pg_temp.rr_c2_as('rr-c2-sup-auth') as support_jwt;
set local role authenticated;
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_cash('c2b1', 'c2b1')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-242 C2 change 7: under an ACTIVE support session (the support admin''s JWT) a cash payment.create carrying d2 cashier staff 8''s VALID PIN session and d2 (an otherwise admissible request: section AB.6 applies it) raises exactly SQLSTATE 42501 ''sync_push: permission denied (active support session)'' - the request-level refusal, no JSON result');
select throws_ok($$ select pg_temp.zc_push(10, jsonb_build_array(pg_temp.rr_c2_card5()), 5) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-243 C2 change 7: under the ACTIVE support session a hand-recorded card payment.create from a till without a LIVE binding (d5, cashier staff 10''s VALID PIN session; admissible without support, AB.6) raises exactly the same 42501 refusal');
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_leg('c2r1')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-244 C2 change 7: under the ACTIVE support session the provider recording leg of the approved, unrecorded LIVE attempt c2r1 (its canonical payment.create, the cashier''s VALID PIN on d2; recordable without support, AB.7) raises exactly the same 42501 refusal');
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;
select is(jsonb_build_object('written', pg_temp.rr_c2_changed('b'), 'audit', pg_temp.rr_delta('c2b'),
                             'sync_rows', pg_temp.rr_so_n(array['c2b1', 'c2r1'], 2) + pg_temp.rr_so_n(array['c2b5'], 5),
                             'payments', pg_temp.rr_order_pay_n('c2b1') + pg_temp.rr_order_pay_n('c2b5')
                                         + pg_temp.rr_order_pay_n('c2r1'),
                             'orders', pg_temp.rr_c2_orders(array['c2b1', 'c2b5', 'c2r1'])),
          jsonb_build_object('written', '[]'::jsonb, 'audit', '{}'::jsonb, 'sync_rows', 0, 'payments', 0,
                             'orders', jsonb_build_object('c2b1', jsonb_build_object('status', 'submitted', 'revision', 1),
                                                          'c2b5', jsonb_build_object('status', 'submitted', 'revision', 1),
                                                          'c2r1', jsonb_build_object('status', 'submitted', 'revision', 1))),
          'RR-245 C2 change 7 (no net write): the three refused requests of RR-242..RR-244 changed NOTHING - the content digests (every column + the tuple ctid) of payments, branch_receipt_counters, orders (tuple / revision / updated_at), shifts, cash_drawer_sessions, sync_operations, audit_events, app.card_provider_attempts, app.card_provider_private_events, device_sessions, devices, pin_sessions, the support sessions and the platform-admin audit of both organizations are identical; no audit row of any action; no sync row and no payment under the three identities; the three orders still submitted, revision 1');
select is(jsonb_build_object('row_unchanged', to_jsonb(pg_temp.rr_att2('c2r1')) = pg_temp.rr_r('row-c2r1-0'),
                             'state', (pg_temp.rr_att2('c2r1')).state,
                             'order_freed_at', (pg_temp.rr_att2('c2r1')).order_freed_at,
                             'resume_count', (pg_temp.rr_att2('c2r1')).recording_resume_count,
                             'histories', jsonb_build_array((pg_temp.rr_att2('c2r1')).recording_resume_history,
                                                            (pg_temp.rr_att2('c2r1')).recording_refusal_history),
                             'refusal_code', (pg_temp.rr_att2('c2r1')).refusal_code,
                             'payments', pg_temp.rr_pay2_n('c2r1'),
                             'claim_active', app.card_order_claim_active(pg_temp.zc_org(), pg_temp.rr_ord('c2r1')),
                             'derive', pg_temp.rr_derive2('c2r1'),
                             'envelope', pg_temp.rr_ts(app.card_attempt_envelope(pg_temp.rr_att2('c2r1')))),
          jsonb_build_object('row_unchanged', true, 'state', 'approved', 'order_freed_at', null, 'resume_count', 0,
                             'histories', '[[], []]'::jsonb, 'refusal_code', null, 'payments', 0, 'claim_active', true,
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'pending_recording', false),
                             'envelope', pg_temp.rr_env_exp('c2r1', 'approved_unrecorded', null, false, 0)),
          'RR-246 C2 (packet 13.4): the support-refused recording leg leaves the attempt exactly as it was - row byte-identical, still approved, order_freed_at NULL, recording_resume_count 0, both histories empty, no refusal stored, no payment, its order claim still active; it derives approved_unrecorded / pending_recording (recoverable false) and the envelope reads approved_unrecorded, resume_count 0 (no charge created, no Resume budget consumed)');

-- AB.2 ACTIVE support + the manager's valid PIN: the D-054 Resume.
select pg_temp.rr_c2_snap('c') as world_snap;
select pg_temp.rr_snap('c2c');
select pg_temp.rr_c2_as('rr-c2-sup-auth') as support_jwt;
set local role authenticated;
select throws_ok($$ select pg_temp.zc_push(3, jsonb_build_array(pg_temp.rr_leg('c2m1', 'c2m1', '{"recording_resume": 0}')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-247 C2 change 7: under the ACTIVE support session the D-054 Resume of c2m1 (payment.create carrying recording_resume 0) with d2 manager staff 3''s VALID PIN session - a Resume authorized without support (AB.6) - raises exactly the same 42501 refusal');
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;
select is(jsonb_build_object('resume_count', (pg_temp.rr_att2('c2m1')).recording_resume_count,
                             'resume_history', (pg_temp.rr_att2('c2m1')).recording_resume_history,
                             'refusal_history', (pg_temp.rr_att2('c2m1')).recording_refusal_history,
                             'row_unchanged', to_jsonb(pg_temp.rr_att2('c2m1')) = pg_temp.rr_r('row-c2m1-0'),
                             'so_unchanged', to_jsonb(pg_temp.rr_so('c2m1', 2)) = pg_temp.rr_r('so-c2m1-0'),
                             'payments', pg_temp.rr_pay2_n('c2m1'),
                             'derive', pg_temp.rr_derive2('c2m1'),
                             'audit', pg_temp.rr_delta('c2c'), 'written', pg_temp.rr_c2_changed('c')),
          jsonb_build_object('resume_count', 0, 'resume_history', '[]'::jsonb, 'refusal_history', '[]'::jsonb,
                             'row_unchanged', true, 'so_unchanged', true, 'payments', 0,
                             'derive', pg_temp.rr_derive_exp('approved_unrecorded', 'recording_refused', true),
                             'audit', '{}'::jsonb, 'written', '[]'::jsonb),
          'RR-248 C2 change 7 (no net Resume write; the placement is SA-131 and the C41 push leg): the refused Resume left recording_resume_count 0, recording_resume_history and recording_refusal_history empty, the attempt row and its rejected sync row byte-identical, no payment, no card_attempt.recording_resume_requested or any other audit row and nothing else written (every digest identical); the stored refusal stays reported (recording_refused, recoverable true)');

-- AB.3 ACTIVE support: a mixed batch, a card-sensitive batch and a lone non-payment operation.
select pg_temp.rr_c2_snap('e') as world_snap;
select pg_temp.rr_snap('c2e');
select pg_temp.rr_c2_as('rr-c2-sup-auth') as support_jwt;
set local role authenticated;
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_status_op('c2e1', 'c2e1'),
                                                               pg_temp.rr_cash('c2e2', 'c2e2')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-249 C2 change 7: under the ACTIVE support session a mixed batch (order.status of c2e1 + a cash payment.create of c2e2; the cashier''s VALID PIN on d2; applied without support, AB.6) raises exactly the same 42501 refusal');
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_leg('c2r1'), pg_temp.rr_status_op('c2e3', 'c2e3')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-250 C2 change 7 (before the single-operation check): under the ACTIVE support session a card-sensitive batch (c2r1''s recording leg + an order.status of c2e3), which without support is answered single_operation_required (RR-261), raises exactly the same 42501 refusal');
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_status_op('c2e3', 'c2e3')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-251 C2 change 7 (whatever the request carries): under the ACTIVE support session a lone order.status of c2e3 (no payment.create, so no terminal lock or card check is involved) raises exactly the same 42501 refusal');
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;
select is(jsonb_build_object('orders', pg_temp.rr_c2_orders(array['c2e1', 'c2e2', 'c2e3']),
                             'sync_rows', pg_temp.rr_so_n(array['c2e1', 'c2e2', 'c2e3', 'c2r1'], 2),
                             'payments', pg_temp.rr_order_pay_n('c2e1') + pg_temp.rr_order_pay_n('c2e2')
                                         + pg_temp.rr_order_pay_n('c2e3') + pg_temp.rr_order_pay_n('c2r1'),
                             'audit', pg_temp.rr_delta('c2e'), 'written', pg_temp.rr_c2_changed('e')),
          jsonb_build_object('orders', jsonb_build_object('c2e1', jsonb_build_object('status', 'submitted', 'revision', 1),
                                                          'c2e2', jsonb_build_object('status', 'submitted', 'revision', 1),
                                                          'c2e3', jsonb_build_object('status', 'submitted', 'revision', 1)),
                             'sync_rows', 0, 'payments', 0, 'audit', '{}'::jsonb, 'written', '[]'::jsonb),
          'RR-252 C2 change 7 (no net effect of any batch): after RR-249..RR-251 no operation of any batch left a trace - c2e1 / c2e2 / c2e3 still submitted, revision 1, no sync row and no payment under any of the four identities, no audit row, every digest identical (no partial batch)');

-- AB.4 ACTIVE support with NO valid PIN session; the batch-shape checks; the same requests outside support.
select pg_temp.rr_c2_snap('f') as world_snap;
select pg_temp.rr_snap('c2f');
select pg_temp.rr_c2_as('rr-c2-sup-auth') as support_jwt;
set local role authenticated;
select throws_ok($$ select public.sync_push(pg_temp.zc_id('rr-c2-no-pin'), pg_temp.zc_id('device-2'),
                                            jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1'))) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-253 C2 change 7 (before the PIN check): under the ACTIVE support session a push naming an UNKNOWN PIN session id (d2, a cash payment.create of c2f1) raises exactly the support refusal, not the PIN check''s ''sync_push: PIN session not found''');
select throws_ok($$ select public.sync_push(null, pg_temp.zc_id('device-2'), jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1'))) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-254 C2 change 7 (before the PIN check): under the ACTIVE support session a push with a NULL PIN session id raises exactly the support refusal');
select pg_temp.rr_c2_try('c2f-sup-unknown', pg_temp.zc_id('rr-c2-no-pin'), 2, jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1')));
select pg_temp.rr_c2_try('c2f-sup-null', null, 2, jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1')));
select pg_temp.rr_c2_try('c2f-sup-object', pg_temp.zc_id('pin-8'), 2, jsonb_build_object('op', pg_temp.rr_cash('c2f1', 'c2f1')));
select pg_temp.rr_c2_try('c2f-sup-nullops', pg_temp.zc_id('pin-8'), 2, null);
select pg_temp.rr_c2_try('c2f-sup-101', pg_temp.zc_id('pin-8'), 2,
  (select jsonb_agg(pg_temp.rr_cash('c2f1', 'c2f1')) from generate_series(1, 101)));
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;
set local role authenticated;
select pg_temp.rr_c2_try('c2f-nat-unknown', pg_temp.zc_id('rr-c2-no-pin'), 2, jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1')));
select pg_temp.rr_c2_try('c2f-nat-null', null, 2, jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1')));
select pg_temp.rr_c2_try('c2f-nat-object', pg_temp.zc_id('pin-8'), 2, jsonb_build_object('op', pg_temp.rr_cash('c2f1', 'c2f1')));
select pg_temp.rr_c2_try('c2f-nat-nullops', pg_temp.zc_id('pin-8'), 2, null);
select pg_temp.rr_c2_try('c2f-nat-101', pg_temp.zc_id('pin-8'), 2,
  (select jsonb_agg(pg_temp.rr_cash('c2f1', 'c2f1')) from generate_series(1, 101)));
reset role;
select is(jsonb_build_object('support', jsonb_build_object('unknown_pin', pg_temp.rr_r('c2f-sup-unknown'),
                                           'null_pin', pg_temp.rr_r('c2f-sup-null'),
                                           'object_ops', pg_temp.rr_r('c2f-sup-object'),
                                           'null_ops', pg_temp.rr_r('c2f-sup-nullops'),
                                           'ops_101', pg_temp.rr_r('c2f-sup-101')),
                             'transport', jsonb_build_object('unknown_pin', pg_temp.rr_r('c2f-nat-unknown'),
                                           'null_pin', pg_temp.rr_r('c2f-nat-null'),
                                           'object_ops', pg_temp.rr_r('c2f-nat-object'),
                                           'null_ops', pg_temp.rr_r('c2f-nat-nullops'),
                                           'ops_101', pg_temp.rr_r('c2f-nat-101')),
                             'sync_rows', pg_temp.rr_so_n(array['c2f1'], 2), 'payments', pg_temp.rr_order_pay_n('c2f1'),
                             'audit', pg_temp.rr_delta('c2f'), 'written', pg_temp.rr_c2_changed('f')),
          jsonb_build_object('support', jsonb_build_object('unknown_pin', pg_temp.rr_c2_sup_err(),
                                           'null_pin', pg_temp.rr_c2_sup_err(), 'object_ops', pg_temp.rr_c2_sup_err(),
                                           'null_ops', pg_temp.rr_c2_sup_err(), 'ops_101', pg_temp.rr_c2_sup_err()),
                             'transport', jsonb_build_object(
                                           'unknown_pin', pg_temp.rr_c2_err('sync_push: PIN session not found'),
                                           'null_pin', pg_temp.rr_c2_err('sync_push: PIN session not found'),
                                           'object_ops', pg_temp.rr_c2_err('sync_push: p_operations must be a JSON array'),
                                           'null_ops', pg_temp.rr_c2_err('sync_push: p_operations must be a JSON array'),
                                           'ops_101', pg_temp.rr_c2_err('sync_push: batch too large (max 100 operations, got 101)')),
                             'sync_rows', 0, 'payments', 0, 'audit', '{}'::jsonb, 'written', '[]'::jsonb),
          'RR-255 C2 change 7 is the FIRST statement: under the ACTIVE support session an unknown PIN id, a NULL PIN id, a non-array p_operations (a JSON object), a NULL p_operations and a 101-operation batch (the cashier''s valid PIN) each raise exactly 42501 ''sync_push: permission denied (active support session)'' with no DETAIL / HINT; the very same requests under the transport JWT raise their existing refusals (''sync_push: PIN session not found'' twice, ''sync_push: p_operations must be a JSON array'' twice, ''sync_push: batch too large (max 100 operations, got 101)''), so the guard precedes the batch-shape and PIN checks; none wrote anything (no sync row, payment or audit; every digest identical)');

-- AB.5 The revoked-device path: d2's pairing suspended (test-only owner update, as AA.3); restored after.
update public.device_pairings dp set status = 'suspended' where dp.id = pg_temp.zc_id('pairing-2');
select pg_temp.rr_snap('c2g-base');
set local role authenticated;
select pg_temp.rr_push('p-c2g1', 8, jsonb_build_array(pg_temp.rr_cash('c2g1', 'c2g1')), 2);
reset role;
select is(jsonb_build_object('response', pg_temp.rr_ts(pg_temp.rr_r('p-c2g1')),
                             'so', pg_temp.rr_so_state('c2g1', 2)
                                   || jsonb_build_object('operation_type', (pg_temp.rr_so('c2g1', 2)).operation_type),
                             'payments', pg_temp.rr_order_pay_n('c2g1'),
                             'audit', pg_temp.rr_delta('c2g-base'),
                             'rejected_rows', (select jsonb_agg(jsonb_build_object('actor', pg_temp.rr_c2_lbl(e.actor_employee_profile_id),
                                                                  'device', pg_temp.rr_c2_lbl(e.device_id), 'new', e.new_values))
                                                 from public.audit_events e
                                                where e.organization_id = pg_temp.zc_org() and e.action = 'sync.operation_rejected'
                                                  and e.new_values ->> 'local_operation_id' = pg_temp.zc_lop('c2g1'))),
          jsonb_build_object('response', pg_temp.rr_m10_resp(jsonb_build_object('local_operation_id', pg_temp.zc_lop('c2g1'),
                                           'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                           'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false), true),
                             'so', jsonb_build_object('status', 'rejected', 'class', 'permanent', 'code', 'revoked_device',
                                     'retry_count', 0, 'result', jsonb_build_object('ok', false, 'error', 'rejected',
                                                                                    'detail', 'revoked_device'),
                                     'reason', 'revoked_device', 'operation_type', 'payment.create'),
                             'payments', 0, 'audit', jsonb_build_object('sync.operation_rejected', 1),
                             'rejected_rows', jsonb_build_array(jsonb_build_object('actor', 'employee-8', 'device', 'device-2',
                                                'new', jsonb_build_object('local_operation_id', pg_temp.zc_lop('c2g1'),
                                                         'operation_type', 'payment.create', 'reason', 'revoked_device')))),
          'RR-256 C2 baseline control (RF061-A1, unchanged): with d2''s pairing suspended and NO support session (the transport JWT) the cashier''s cash payment.create of c2g1 takes the revoked-device path exactly - {ok:true, device_revoked:true, results:[{ok:false, error:rejected, detail:revoked_device, status:rejected, idempotency_replay:false}]}, stored rejected / permanent / revoked_device (retry_count 0) with exactly one sync.operation_rejected (the cashier, d2), no payment');
select pg_temp.rr_c2_snap('g') as world_snap;
select pg_temp.rr_snap('c2g');
insert into _zc_r select 'so-c2g1-0', to_jsonb(pg_temp.rr_so('c2g1', 2));
select pg_temp.rr_c2_as('rr-c2-sup-auth') as support_jwt;
set local role authenticated;
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_cash('c2g2', 'c2g2')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-257 C2 change 7 (both paths): with d2''s pairing suspended, under the ACTIVE support session a fresh cash payment.create of c2g2 (the cashier''s valid PIN) raises exactly the same 42501 refusal instead of entering the revoked-device path');
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_cash('c2g1', 'c2g1')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-258 C2 change 7 (both paths, replay): with d2''s pairing suspended, under the ACTIVE support session a resend of the stored revoked_device operation c2g1 raises exactly the same 42501 refusal (its stored rejection is not replayed)');
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;
insert into _zc_r select 'c2g-nowrite', jsonb_build_object('written', pg_temp.rr_c2_changed('g'), 'audit', pg_temp.rr_delta('c2g'),
  'c2g2_sync_rows', pg_temp.rr_so_n(array['c2g2'], 2),
  'c2g1_so_unchanged', to_jsonb(pg_temp.rr_so('c2g1', 2)) = pg_temp.rr_r('so-c2g1-0'),
  'payments', pg_temp.rr_order_pay_n('c2g1') + pg_temp.rr_order_pay_n('c2g2'));
select pg_temp.rr_snap('c2g-after');
set local role authenticated;
select pg_temp.rr_push('p-c2g2', 8, jsonb_build_array(pg_temp.rr_cash('c2g2', 'c2g2')), 2);
reset role;
update public.device_pairings dp set status = 'active' where dp.id = pg_temp.zc_id('pairing-2');
select is(jsonb_build_object('no_write', pg_temp.rr_r('c2g-nowrite'),
                             'native_after', jsonb_build_object('response', pg_temp.rr_ts(pg_temp.rr_r('p-c2g2')),
                                               'so', pg_temp.rr_so_state('c2g2', 2), 'payments', pg_temp.rr_order_pay_n('c2g2'),
                                               'audit', pg_temp.rr_delta('c2g-after')),
                             'pairing_restored', (select dp.status from public.device_pairings dp
                                                   where dp.id = pg_temp.zc_id('pairing-2'))),
          jsonb_build_object('no_write', jsonb_build_object('written', '[]'::jsonb, 'audit', '{}'::jsonb, 'c2g2_sync_rows', 0,
                                                            'c2g1_so_unchanged', true, 'payments', 0),
                             'native_after', jsonb_build_object(
                                               'response', pg_temp.rr_m10_resp(jsonb_build_object('local_operation_id', pg_temp.zc_lop('c2g2'),
                                                             'operation_type', 'payment.create', 'ok', false, 'error', 'rejected',
                                                             'detail', 'revoked_device', 'status', 'rejected',
                                                             'idempotency_replay', false), true),
                                               'so', jsonb_build_object('status', 'rejected', 'class', 'permanent',
                                                       'code', 'revoked_device', 'retry_count', 0,
                                                       'result', jsonb_build_object('ok', false, 'error', 'rejected',
                                                                                    'detail', 'revoked_device'),
                                                       'reason', 'revoked_device'),
                                               'payments', 0, 'audit', jsonb_build_object('sync.operation_rejected', 1)),
                             'pairing_restored', 'active'),
          'RR-259 C2 change 7 (revoked path, no write; baseline kept): RR-257 / RR-258 recorded nothing - no revoked_device row for c2g2, c2g1''s stored row byte-identical, no sync.operation_rejected or any audit row, no payment, every digest identical; then, still suspended and outside support (the transport JWT), the very request RR-257 refused takes the revoked-device path as a FIRST ingestion - exactly the RR-256 baseline for c2g2 (device_revoked response, rejected / permanent / revoked_device row, retry_count 0, one sync.operation_rejected, no payment); d2''s pairing is then restored (active)');

-- AB.6 Outside support, existing behaviour: the native cashier, d5's cashier and the manager (transport JWT)
--      push the very requests refused above - the refusals left no ledger row, so each is a first application -
--      and the dual-role owner pushes with its own JWT and its own valid PIN.
insert into _zc_r select 'ctr-h-0', jsonb_build_object('pilot', pg_temp.rr_c2_counter(pg_temp.zc_branch()),
                                                       'sib', pg_temp.rr_c2_counter(pg_temp.zc_id('branch_sib')));
select pg_temp.rr_snap('c2h');
set local role authenticated;
select pg_temp.rr_push('p-c2b1', 8, jsonb_build_array(pg_temp.rr_cash('c2b1', 'c2b1')), 2);
select pg_temp.rr_push('p-c2b5', 10, jsonb_build_array(pg_temp.rr_c2_card5()), 5);
reset role;
select is(jsonb_build_object('cash', pg_temp.rr_c2_applied('p-c2b1'),
                             'cash_change', pg_temp.rr_res('p-c2b1') -> 'change_due_minor',
                             'cash_receipt_is_next', (pg_temp.rr_res('p-c2b1') ->> 'receipt_number')::bigint
                                                     = (pg_temp.rr_r('ctr-h-0') ->> 'pilot')::bigint + 1,
                             'cash_payment', pg_temp.rr_c2_pay('c2b1', 2),
                             'card', pg_temp.rr_c2_applied('p-c2b5'),
                             'card_receipt_is_next', (pg_temp.rr_res('p-c2b5') ->> 'receipt_number')::bigint
                                                     = (pg_temp.rr_r('ctr-h-0') ->> 'sib')::bigint + 1,
                             'card_payment', pg_temp.rr_c2_pay('c2b5', 5),
                             'counters_advanced', jsonb_build_object(
                                 'pilot', pg_temp.rr_c2_counter(pg_temp.zc_branch()) - (pg_temp.rr_r('ctr-h-0') ->> 'pilot')::bigint,
                                 'sib', pg_temp.rr_c2_counter(pg_temp.zc_id('branch_sib')) - (pg_temp.rr_r('ctr-h-0') ->> 'sib')::bigint),
                             'sync', jsonb_build_object('c2b1', (pg_temp.rr_so('c2b1', 2)).status,
                                                        'c2b5', (pg_temp.rr_so('c2b5', 5)).status),
                             'sync_audit', pg_temp.rr_delta('c2h', 'sync.%')),
          jsonb_build_object('cash', pg_temp.rr_c2_applied_exp('cash'), 'cash_change', 766, 'cash_receipt_is_next', true,
                             'cash_payment', jsonb_build_object('n', 1, 'method', 'cash', 'status', 'completed', 'amount', 1234,
                                               'tendered', 2000, 'change', 766, 'order_matches', true, 'taken_by', 'employee-8'),
                             'card', pg_temp.rr_c2_applied_exp('card'), 'card_receipt_is_next', true,
                             'card_payment', jsonb_build_object('n', 1, 'method', 'card', 'status', 'completed', 'amount', 1234,
                                               'tendered', 1234, 'change', 0, 'order_matches', true, 'taken_by', 'employee-10'),
                             'counters_advanced', jsonb_build_object('pilot', 1, 'sib', 1),
                             'sync', jsonb_build_object('c2b1', 'applied', 'c2b5', 'applied'), 'sync_audit', '{}'::jsonb),
          'RR-260 C2 outside support (existing behaviour): the native transport JWT (no app user) pushes the very requests RR-242 / RR-243 refused - d2''s cashier''s cash payment.create of c2b1 and d5''s cashier''s hand-recorded card payment.create of c2b5 - and each is applied as a FIRST application (idempotency_replay false): exactly one completed payment each (cash 1234 / tendered 2000 / change 766 taken by staff 8; card 1234 taken by staff 10), each branch''s receipt counter advanced by exactly one to the receipt the response carries, the sync rows applied');
select pg_temp.rr_snap('c2e-native');
set local role authenticated;
select pg_temp.rr_push('p-c2e', 8, jsonb_build_array(pg_temp.rr_status_op('c2e1', 'c2e1'), pg_temp.rr_cash('c2e2', 'c2e2')), 2);
select pg_temp.rr_push('p-c2e-sens', 8, jsonb_build_array(pg_temp.rr_leg('c2r1'), pg_temp.rr_status_op('c2e3', 'c2e3')), 2);
reset role;
select is(jsonb_build_object('results', (select jsonb_agg(jsonb_build_object('type', x ->> 'operation_type', 'ok', x -> 'ok',
                                                          'status', x ->> 'status', 'replay', x -> 'idempotency_replay') order by n)
                                           from jsonb_array_elements(pg_temp.rr_r('p-c2e') -> 'results') with ordinality t(x, n)),
                             'orders', pg_temp.rr_c2_orders(array['c2e1', 'c2e2', 'c2e3']),
                             'payments', jsonb_build_object('c2e1', pg_temp.rr_order_pay_n('c2e1'),
                                                            'c2e2', pg_temp.rr_order_pay_n('c2e2')),
                             'sync', jsonb_build_object('c2e1', (pg_temp.rr_so('c2e1', 2)).status,
                                                        'c2e2', (pg_temp.rr_so('c2e2', 2)).status),
                             'card_sensitive', pg_temp.rr_ts(pg_temp.rr_r('p-c2e-sens')),
                             'card_sensitive_rows', pg_temp.rr_so_n(array['c2r1', 'c2e3'], 2)),
          jsonb_build_object('results', jsonb_build_array(
                               jsonb_build_object('type', 'order.status', 'ok', true, 'status', 'applied', 'replay', false),
                               jsonb_build_object('type', 'payment.create', 'ok', true, 'status', 'applied', 'replay', false)),
                             'orders', jsonb_build_object('c2e1', jsonb_build_object('status', 'accepted', 'revision', 2),
                                                          'c2e2', jsonb_build_object('status', 'submitted', 'revision', 2),
                                                          'c2e3', jsonb_build_object('status', 'submitted', 'revision', 1)),
                             'payments', jsonb_build_object('c2e1', 0, 'c2e2', 1),
                             'sync', jsonb_build_object('c2e1', 'applied', 'c2e2', 'applied'),
                             'card_sensitive', jsonb_build_object('ok', true, 'server_ts?', true, 'results', jsonb_build_array(
                                                 pg_temp.rr_pending('c2r1', 'payment.create', 'single_operation_required'),
                                                 pg_temp.rr_pending('c2e3', 'order.status', 'single_operation_required'))),
                             'card_sensitive_rows', 0),
          'RR-261 C2 outside support: the native cashier pushes the very mixed batch RR-249 refused and both operations are applied as first applications (order.status: c2e1 accepted, revision 2; payment.create: one payment on c2e2, revision 2), both sync rows applied; the very card-sensitive batch RR-250 refused is answered as before (change 3): single_operation_required for both operations (retryable, pending), no ledger row under either identity, c2e3 untouched (submitted, revision 1)');
select pg_temp.rr_snap('c2m-native');
set local role authenticated;
select pg_temp.rr_push('p-c2m1-r', 3, jsonb_build_array(pg_temp.rr_leg('c2m1', 'c2m1', '{"recording_resume": 0}')), 2);
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-c2m1-r') ->> 'status',
                             'replay', pg_temp.rr_res('p-c2m1-r') -> 'idempotency_replay',
                             'resume', pg_temp.rr_resume_state2('c2m1'),
                             'refusal_entry', (pg_temp.rr_att2('c2m1')).recording_refusal_history -> 0,
                             'resume_entry', ((pg_temp.rr_att2('c2m1')).recording_resume_history -> 0) - 'at',
                             'recorded', pg_temp.rr_derive2('c2m1') -> 'recorded',
                             'taken_by', (select pg_temp.rr_c2_lbl(p.taken_by_employee_profile_id) from public.payments p
                                           where p.device_id = pg_temp.zc_id('device-2')
                                             and p.local_operation_id = pg_temp.zc_lop('c2m1')),
                             'card_sync_audit', pg_temp.rr_delta('c2m-native', 'card_attempt.%')
                                                || pg_temp.rr_delta('c2m-native', 'sync.%')),
          jsonb_build_object('status', 'applied', 'replay', false,
                             'resume', jsonb_build_object('so', 'applied', 'retry_count', 1, 'resume_count', 1,
                                         'resume_history', 1, 'refusal_history', 1, 'payments', 1),
                             'refusal_entry', jsonb_build_object('refusal_code', 'revoked_employee',
                                                'refused_at', pg_temp.rr_r('row-c2m1-0') -> 'recording_refused_at'),
                             'resume_entry', jsonb_build_object('employee_profile_id', pg_temp.zc_id('employee-3'),
                                               'membership_id', pg_temp.zc_id('membership-3'), 'resume_count', 0),
                             'recorded', true, 'taken_by', 'employee-3',
                             'card_sync_audit', jsonb_build_object('card_attempt.recording_resume_requested', 1)),
          'RR-262 C2 outside support: the native manager (transport JWT) pushes the very Resume RR-247 refused and it is authorized as the FIRST Resume of c2m1 - applied once (the manager its actor), resume_count 1, retry_count 1, one entry in each history (the refusal entry is the stored revoked_employee report the refused Resume left untouched), exactly one payment, one card_attempt.recording_resume_requested and no other card / sync audit');
select pg_temp.rr_snap('c2h9');
select pg_temp.rr_c2_as('rr-c2-dual-auth') as dual_role_jwt;
set local role authenticated;
select pg_temp.rr_c2_try('p-c2h9', pg_temp.zc_id('rr-c2-pin-9'), 2, jsonb_build_array(pg_temp.rr_cash('c2h9', 'c2h9')));
reset role;
select is(jsonb_build_object('caller', jsonb_build_object('app_user', pg_temp.rr_c2_lbl(app.current_app_user_id()),
                                         'support_session', app.current_support_session(), 'platform_admin', app.is_platform_admin()),
                             'result', pg_temp.rr_c2_applied('p-c2h9'),
                             'payment', pg_temp.rr_c2_pay('c2h9', 2),
                             'sync', (pg_temp.rr_so('c2h9', 2)).status,
                             'sync_audit', pg_temp.rr_delta('c2h9', 'sync.%')),
          jsonb_build_object('caller', jsonb_build_object('app_user', 'user-9', 'support_session', null, 'platform_admin', true),
                             'result', pg_temp.rr_c2_applied_exp('cash'),
                             'payment', jsonb_build_object('n', 1, 'method', 'cash', 'status', 'completed', 'amount', 1234,
                                          'tendered', 2000, 'change', 766, 'order_matches', true, 'taken_by', 'employee-9'),
                             'sync', 'applied', 'sync_audit', '{}'::jsonb),
          'RR-263 C2 outside support (dual-role owner, packet 13.1): under its OWN JWT - staff 9 (the org_owner) linked to its auth user, an active platform-admin grant and NO support session - the owner''s own valid PIN on d2 pushes a cash payment.create of c2h9: applied as before (first application, one completed payment taken by staff 9, the sync row applied); a platform-admin grant alone is no support session');
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;

-- AB.7 (packet 13.4) The support-refused recording leg, pushed by the native cashier (transport JWT, no support).
select pg_temp.rr_snap('c2r1-native');
set local role authenticated;
select pg_temp.rr_push('p-c2r1', 8, jsonb_build_array(pg_temp.rr_leg('c2r1')), 2);
reset role;
select is(jsonb_build_object('result', jsonb_build_object('ok', pg_temp.rr_res('p-c2r1') -> 'ok',
                                         'status', pg_temp.rr_res('p-c2r1') ->> 'status',
                                         'replay', pg_temp.rr_res('p-c2r1') -> 'idempotency_replay',
                                         'method', pg_temp.rr_res('p-c2r1') ->> 'method',
                                         'frozen_shift', (pg_temp.rr_res('p-c2r1') ->> 'shift_id')::uuid
                                                         = (pg_temp.rr_att2('c2r1')).shift_id,
                                         'frozen_drawer', (pg_temp.rr_res('p-c2r1') ->> 'cash_drawer_session_id')::uuid
                                                          = (pg_temp.rr_att2('c2r1')).cash_drawer_session_id),
                             'payment', pg_temp.rr_c2_pay('c2r1', 2),
                             'state', (pg_temp.rr_att2('c2r1')).state,
                             'order_freed_at', (pg_temp.rr_att2('c2r1')).order_freed_at,
                             'resume_count', (pg_temp.rr_att2('c2r1')).recording_resume_count,
                             'derive', pg_temp.rr_derive2('c2r1') - 'payment_id',
                             'strict_join', (pg_temp.rr_derive2('c2r1') ->> 'payment_id') = (pg_temp.rr_res('p-c2r1') ->> 'payment_id'),
                             'card_sync_audit', pg_temp.rr_delta('c2r1-native', 'card_attempt.%')
                                                || pg_temp.rr_delta('c2r1-native', 'sync.%')),
          jsonb_build_object('result', jsonb_build_object('ok', true, 'status', 'applied', 'replay', false, 'method', 'card',
                                                          'frozen_shift', true, 'frozen_drawer', true),
                             'payment', jsonb_build_object('n', 1, 'method', 'card', 'status', 'completed', 'amount', 1234,
                                          'tendered', 1234, 'change', 0, 'order_matches', true, 'taken_by', 'employee-8'),
                             'state', 'approved', 'order_freed_at', null, 'resume_count', 0,
                             'derive', jsonb_build_object('recorded', true, 'classification', 'recorded', 'reason', null,
                                         'recoverable', false, 'claim_active', false, 'blocks_close', false, 'unresolved', false),
                             'strict_join', true, 'card_sync_audit', '{}'::jsonb),
          'RR-264 C2 (packet 13.4, a later legitimate non-support push): the very leg RR-244 refused, pushed by the native cashier (transport JWT), records exactly once as a FIRST application (applied, idempotency_replay false) - exactly one completed card payment of 1234 in the frozen shift / drawer taken by staff 8 - and the attempt reads recorded (the strict join to that payment; claim ended, nothing blocks close), still approved, order_freed_at NULL, resume_count 0, no card / sync audit');

-- AB.8 Replay under ACTIVE support of operations the native cashier applied (AB.6 / AB.7).
select pg_temp.rr_c2_snap('d') as world_snap;
select pg_temp.rr_snap('c2d');
insert into _zc_r select 'so-c2b1-1', to_jsonb(pg_temp.rr_so('c2b1', 2));
insert into _zc_r select 'so-c2r1-1', to_jsonb(pg_temp.rr_so('c2r1', 2));
select pg_temp.rr_c2_as('rr-c2-sup-auth') as support_jwt;
set local role authenticated;
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_cash('c2b1', 'c2b1')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-265 C2 change 7 (replay): under the ACTIVE support session a resend of the cash payment.create of c2b1 that the native cashier applied (RR-260) raises exactly the same 42501 refusal - the stored applied result is not replayed');
select throws_ok($$ select pg_temp.zc_push(8, jsonb_build_array(pg_temp.rr_leg('c2r1')), 2) $$,
  '42501', 'sync_push: permission denied (active support session)',
  'RR-266 C2 change 7 (replay): under the ACTIVE support session a resend of the recorded provider leg of c2r1 (RR-264) raises exactly the same 42501 refusal');
select pg_temp.rr_c2_try('c2d-cash', pg_temp.zc_id('pin-8'), 2, jsonb_build_array(pg_temp.rr_cash('c2b1', 'c2b1')));
select pg_temp.rr_c2_try('c2d-leg', pg_temp.zc_id('pin-8'), 2, jsonb_build_array(pg_temp.rr_leg('c2r1')));
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;
select is(jsonb_build_object('cash_replay', pg_temp.rr_r('c2d-cash'), 'leg_replay', pg_temp.rr_r('c2d-leg'),
                             'cash_so_unchanged', to_jsonb(pg_temp.rr_so('c2b1', 2)) = pg_temp.rr_r('so-c2b1-1'),
                             'leg_so_unchanged', to_jsonb(pg_temp.rr_so('c2r1', 2)) = pg_temp.rr_r('so-c2r1-1'),
                             'payments', jsonb_build_object('c2b1', pg_temp.rr_c2_pay('c2b1', 2) -> 'n',
                                                            'c2r1', pg_temp.rr_c2_pay('c2r1', 2) -> 'n'),
                             'audit', pg_temp.rr_delta('c2d'), 'written', pg_temp.rr_c2_changed('d')),
          jsonb_build_object('cash_replay', pg_temp.rr_c2_sup_err(), 'leg_replay', pg_temp.rr_c2_sup_err(),
                             'cash_so_unchanged', true, 'leg_so_unchanged', true,
                             'payments', jsonb_build_object('c2b1', 1, 'c2r1', 1), 'audit', '{}'::jsonb, 'written', '[]'::jsonb),
          'RR-267 C2 change 7 (a replay discloses nothing): each support-session replay answers ONLY {SQLSTATE 42501, message ''sync_push: permission denied (active support session)'', no DETAIL, no HINT} - no stored result, payment, receipt, order or attempt identifier - and writes nothing: both stored sync rows byte-identical (retry_count unchanged), still one payment each, no audit row, every digest identical');
select pg_temp.rr_snap('c2d-native');
set local role authenticated;
select pg_temp.rr_push('p-c2b1-again', 8, jsonb_build_array(pg_temp.rr_cash('c2b1', 'c2b1')), 2);
reset role;
select is(jsonb_build_object('status', pg_temp.rr_res('p-c2b1-again') ->> 'status',
                             'replay', pg_temp.rr_res('p-c2b1-again') -> 'idempotency_replay',
                             'same_payment', (pg_temp.rr_res('p-c2b1-again') ->> 'payment_id') = (pg_temp.rr_res('p-c2b1') ->> 'payment_id'),
                             'same_receipt', (pg_temp.rr_res('p-c2b1-again') ->> 'receipt_number')
                                             = (pg_temp.rr_res('p-c2b1') ->> 'receipt_number'),
                             'payments', pg_temp.rr_c2_pay('c2b1', 2) -> 'n', 'audit', pg_temp.rr_delta('c2d-native')),
          jsonb_build_object('status', 'applied', 'replay', true, 'same_payment', true, 'same_receipt', true, 'payments', 1,
                             'audit', '{}'::jsonb),
          'RR-268 C2 outside support (idempotency as before): the same resend of c2b1 under the transport JWT replays its stored applied result (idempotency_replay true, the same payment and receipt) with no second payment and no audit row - exactly what the support-session replay of RR-265 / RR-267 withheld');

-- AB.9 Ended, expired, un-exchanged (pending) and unconsumed support sessions do not refuse.
select pg_temp.rr_snap('c2i');
set local role authenticated;
select pg_temp.rr_c2_as('rr-c2-ended-auth') as ended_jwt;
select pg_temp.rr_c2_try('p-c2i1', pg_temp.zc_id('pin-8'), 2, jsonb_build_array(pg_temp.rr_cash('c2i1', 'c2i1')));
select pg_temp.rr_c2_as('rr-c2-expired-auth') as expired_jwt;
select pg_temp.rr_c2_try('p-c2i2', pg_temp.zc_id('pin-8'), 2, jsonb_build_array(pg_temp.rr_cash('c2i2', 'c2i2')));
select pg_temp.rr_c2_as('rr-c2-pending-auth') as pending_jwt;
select pg_temp.rr_c2_try('p-c2i3', pg_temp.zc_id('pin-8'), 2, jsonb_build_array(pg_temp.rr_cash('c2i3', 'c2i3')));
select pg_temp.rr_c2_as('rr-c2-unconsumed-auth') as unconsumed_jwt;
select pg_temp.rr_c2_try('p-c2i4', pg_temp.zc_id('pin-8'), 2, jsonb_build_array(pg_temp.rr_cash('c2i4', 'c2i4')));
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;
select is(jsonb_build_object('ended', pg_temp.rr_c2_applied('p-c2i1') || jsonb_build_object('payment', pg_temp.rr_c2_pay('c2i1', 2)),
                             'expired', pg_temp.rr_c2_applied('p-c2i2') || jsonb_build_object('payment', pg_temp.rr_c2_pay('c2i2', 2)),
                             'pending', pg_temp.rr_c2_applied('p-c2i3') || jsonb_build_object('payment', pg_temp.rr_c2_pay('c2i3', 2)),
                             'unconsumed', pg_temp.rr_c2_applied('p-c2i4') || jsonb_build_object('payment', pg_temp.rr_c2_pay('c2i4', 2)),
                             'sync_audit', pg_temp.rr_delta('c2i', 'sync.%')),
          (select jsonb_object_agg(k, pg_temp.rr_c2_applied_exp('cash') || jsonb_build_object('payment',
                    jsonb_build_object('n', 1, 'method', 'cash', 'status', 'completed', 'amount', 1234, 'tendered', 2000,
                                       'change', 766, 'order_matches', true, 'taken_by', 'employee-8')))
             from unnest(array['ended', 'expired', 'pending', 'unconsumed']) k)
          || jsonb_build_object('sync_audit', '{}'::jsonb),
          'RR-269 C2 outside an ACTIVE session (packet 13.1): under the JWT of an admin whose support session is ended, expired, un-exchanged (pending) or unconsumed (active, token not consumed) - each resolving no active session - the cashier''s valid PIN cash payment.create is applied as before: first application, exactly one completed payment each taken by staff 8, no sync audit');
set local role authenticated;
select pg_temp.rr_c2_as('rr-c2-ended-auth') as ended_jwt;
select throws_ok($$ select public.sync_push(pg_temp.zc_id('rr-c2-no-pin'), pg_temp.zc_id('device-2'),
                                            jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1'))) $$,
  '42501', 'sync_push: PIN session not found',
  'RR-270 C2 outside an ACTIVE session: under the ENDED support session''s JWT an unknown PIN id meets the normal PIN check - exactly the existing 42501 ''sync_push: PIN session not found'' (not the support refusal)');
select pg_temp.rr_c2_as('rr-c2-expired-auth') as expired_jwt;
select throws_ok($$ select public.sync_push(pg_temp.zc_id('rr-c2-no-pin'), pg_temp.zc_id('device-2'),
                                            jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1'))) $$,
  '42501', 'sync_push: PIN session not found',
  'RR-271 C2 outside an ACTIVE session: under the EXPIRED support session''s JWT an unknown PIN id raises exactly the existing ''sync_push: PIN session not found''');
select pg_temp.rr_c2_as('rr-c2-pending-auth') as pending_jwt;
select throws_ok($$ select public.sync_push(pg_temp.zc_id('rr-c2-no-pin'), pg_temp.zc_id('device-2'),
                                            jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1'))) $$,
  '42501', 'sync_push: PIN session not found',
  'RR-272 C2 outside an ACTIVE session: under the UN-EXCHANGED (pending) support session''s JWT an unknown PIN id raises exactly the existing ''sync_push: PIN session not found''');
select pg_temp.rr_c2_as('rr-c2-unconsumed-auth') as unconsumed_jwt;
select throws_ok($$ select public.sync_push(pg_temp.zc_id('rr-c2-no-pin'), pg_temp.zc_id('device-2'),
                                            jsonb_build_array(pg_temp.rr_cash('c2f1', 'c2f1'))) $$,
  '42501', 'sync_push: PIN session not found',
  'RR-273 C2 outside an ACTIVE session: under the UNCONSUMED (active, token not consumed) support session''s JWT an unknown PIN id raises exactly the existing ''sync_push: PIN session not found''');
reset role;
select pg_temp.rr_c2_as('transport-principal') as transport_jwt;

select * from finish();
rollback;
