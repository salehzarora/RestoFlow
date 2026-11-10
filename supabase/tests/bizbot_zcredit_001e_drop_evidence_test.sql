-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (DECISION D-062): the adapter's dropped-field evidence on
-- app.card_attempt_finish (gap G1). Rollback-only synthetic fixtures, real SQL roles, a disposable local or CI
-- database. The evidence is {field, rule} tokens only, so no provider value is written here; the lane also runs
-- with terse error output (a statement error that reaches psql prints its message only, never a DETAIL line).
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
-- G1 harness (rollback-only). The owner role reads the private tables; the
-- service-only finish runs under SET LOCAL ROLE service_role inside g1_fin
-- (reset right after). Every tenant audit row and private event is attributed
-- to the call that wrote it (g1_snap), so each finish is asserted exactly.
-- ===========================================================================
create temp table _g1_seen (kind text, id uuid, primary key (kind, id));
create temp table _g1_aud (k text, id uuid, action text, new_values jsonb);
create temp table _g1_evt (k text, id uuid, attempt_row_id uuid, organization_id uuid, restaurant_id uuid,
                           branch_id uuid, mode text, action text, actor_kind text, actor_reference text,
                           device_id uuid, detail jsonb, retention_until timestamptz, created_at timestamptz);
create temp table _g1_call (k text primary key, c text, before_row jsonb, after_row jsonb, answer jsonb);

create function pg_temp.g1_snap(p_k text) returns integer language plpgsql as $$
declare
  v_a integer;
  v_e integer;
begin
  insert into _g1_aud (k, id, action, new_values)
  select p_k, ae.id, ae.action, ae.new_values
    from public.audit_events ae
   where ae.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))
     and ae.action like 'card_attempt.%'
     and not exists (select 1 from _g1_seen s where s.kind = 'a' and s.id = ae.id);
  get diagnostics v_a = row_count;
  insert into _g1_seen select 'a', x.id from _g1_aud x where x.k = p_k on conflict do nothing;
  insert into _g1_evt (k, id, attempt_row_id, organization_id, restaurant_id, branch_id, mode, action, actor_kind,
                       actor_reference, device_id, detail, retention_until, created_at)
  select p_k, e.id, e.attempt_row_id, e.organization_id, e.restaurant_id, e.branch_id, e.mode, e.action,
         e.actor_kind, e.actor_reference, e.device_id, e.detail, e.retention_until, e.created_at
    from app.card_provider_private_events e
   where not exists (select 1 from _g1_seen s where s.kind = 'e' and s.id = e.id);
  get diagnostics v_e = row_count;
  insert into _g1_seen select 'e', x.id from _g1_evt x where x.k = p_k on conflict do nothing;
  return v_a + v_e;
end $$;

create function pg_temp.g1_rid(p_c text) returns uuid language sql stable as $$
  select (r ->> 'attempt_row_id')::uuid from _zc_r where label = p_c $$;
create function pg_temp.g1_row(p_c text) returns jsonb language sql stable as $$
  select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.g1_rid(p_c) $$;

-- One scope-bound finish as the adapter (service_role): the row before and after, the answer, and the audit /
-- event delta of exactly this call. A finish that raises (it never should) is caught and answered as
-- {ok:false, error:'raised:<SQLSTATE>'} - the subtransaction undoes its writes and its SET LOCAL ROLE - so the
-- assertion that made the call fails by name instead of aborting the file (review SQL-5); no message is printed.
create function pg_temp.g1_fin(p_k text, p_c text, p_source text, p_outcome text,
                               p_fields jsonb default '{}'::jsonb, p_poll text default null,
                               p_claim jsonb default null)
returns jsonb language plpgsql as $$
declare
  v_claim jsonb := coalesce(p_claim, (select r from _zc_r where label = p_c));
  v_before jsonb;
  v jsonb;
begin
  perform pg_temp.g1_snap('pre:' || p_k);
  v_before := pg_temp.g1_row(p_c);
  begin
    execute 'set local role service_role';
    v := pg_temp.zc_finish(v_claim, p_source, p_outcome, p_fields, p_poll);
    execute 'reset role';
  exception when others then
    v := jsonb_build_object('ok', false, 'error', 'raised:' || sqlstate);
  end;
  insert into _zc_r values (p_k, v);
  insert into _g1_call values (p_k, p_c, v_before, pg_temp.g1_row(p_c), v);
  perform pg_temp.g1_snap(p_k);
  return v;
end $$;

-- The exact signature of one call: the answer (envelope or error[/detail]), the row after it, the envelope
-- classification, and exactly the tenant audit actions and private events it wrote (a field drop as
-- field/rule/source).
create function pg_temp.g1_sig(p_k text) returns text language sql stable as $$
  select concat_ws(' | ',
    'answer=' || case when (c.answer ->> 'ok')::boolean then 'envelope'
                      else coalesce(c.answer ->> 'error', '-') || coalesce('/' || (c.answer ->> 'detail'), '') end,
    'state=' || coalesce(c.after_row ->> 'state', '-'),
    'class=' || coalesce(c.answer ->> 'classification', '-'),
    'anomaly=' || coalesce(c.after_row ->> 'provider_anomaly_code', '-'),
    'charge=' || coalesce(c.after_row ->> 'charge_may_exist', '-'),
    'refusal=' || coalesce(c.after_row ->> 'refusal_code', '-'),
    'audit=' || coalesce((select string_agg(x.action, ',' order by x.action) from _g1_aud x where x.k = p_k), '-'),
    'events=' || coalesce((select string_agg(t.s, ',' order by t.s) from (
        select case when e.action = 'security.card_provider_field_dropped'
                    then concat_ws('/', e.detail ->> 'field', e.detail ->> 'rule', e.detail ->> 'source')
                    else e.action end as s
          from _g1_evt e where e.k = p_k) t), '-'))
  from _g1_call c where c.k = p_k $$;
create function pg_temp.g1_do(p_k text, p_c text, p_source text, p_outcome text,
                              p_fields jsonb default '{}'::jsonb, p_poll text default null,
                              p_claim jsonb default null)
returns text language plpgsql as $$
begin
  perform pg_temp.g1_fin(p_k, p_c, p_source, p_outcome, p_fields, p_poll, p_claim);
  return pg_temp.g1_sig(p_k);
end $$;

-- dropped_fields of the given (field, rule) pairs, in order.
create function pg_temp.g1_drop(variadic p_pairs text[]) returns jsonb language sql immutable as $$
  select jsonb_build_object('dropped_fields', coalesce((
    select jsonb_agg(jsonb_build_object('field', p_pairs[i], 'rule', p_pairs[i + 1]) order by i)
      from generate_series(1, coalesce(array_length(p_pairs, 1), 0), 2) i), '[]'::jsonb)) $$;

-- One malformed-evidence call: its answer, the answer's keys, whether the row changed, and the audit and
-- events it wrote; echo = whether the answer repeats the probe token placed in the malformed input.
create function pg_temp.g1_bad(p_k text, p_fields jsonb, p_c text default 'l_bad', p_claim jsonb default null,
                               p_source text default 'lookup', p_outcome text default 'not_found')
returns text language plpgsql as $$
declare
  v jsonb;
begin
  v := pg_temp.g1_fin(p_k, p_c, p_source, p_outcome, p_fields, 'auto', p_claim);
  return concat_ws(' | ',
    'answer=' || coalesce(v ->> 'error', 'envelope'),
    'keys=' || (select string_agg(k, ',' order by k) from jsonb_object_keys(v) k),
    'row_changed=' || (select (before_row is distinct from after_row)::text from _g1_call where k = p_k),
    'audit=' || coalesce((select string_agg(x.action, ',') from _g1_aud x where x.k = p_k), '-'),
    'events=' || coalesce((select string_agg(e.action, ',') from _g1_evt e where e.k = p_k), '-'),
    'echo=' || (v::text ~ 'zz-echo-probe')::text);
end $$;

-- A statement run AS a role; an error becomes its SQLSTATE.
create function pg_temp.g1_try(p_role text, p_sql text) returns text language plpgsql as $$
declare
  v text := 'passed';
begin
  execute format('set local role %I', p_role);
  begin
    execute p_sql;
  exception when others then
    v := sqlstate;
  end;
  execute 'reset role';
  return v;
end $$;

-- The lookup reply that matches a 1234 ILS attempt exactly.
create function pg_temp.g1_ex() returns jsonb language sql immutable as $$
  select jsonb_build_object('provider_status_code', 'ok1', 'provider_amount', '12.34', 'provider_currency', 'ILS') $$;

-- LIVE claims on d1 by the cashier (staff 1): one synthetic 1234 ILS order each.
create function pg_temp.g1_live(p_labels text[]) returns integer language plpgsql as $$
declare
  l text;
  n integer := 0;
  v jsonb;
begin
  foreach l in array p_labels loop
    perform pg_temp.zc_order('g1-' || l, 1234, 1);
  end loop;
  execute 'set local role service_role';
  foreach l in array p_labels loop
    v := pg_temp.zc_claim(1, pg_temp.zc_lop('g1-' || l), 'live', 1234, pg_temp.zc_id('order-g1-' || l), 1);
    insert into _zc_r values (l, v);
    if coalesce((v ->> 'claim_created')::boolean, false) then
      n := n + 1;
    end if;
  end loop;
  execute 'reset role';
  return n;
end $$;

-- The three D-062 blocks exactly as the migration inserts them (CR-normalized; source of truth: the migration).
create temp table _g1_blocks (name text primary key, block text not null);
insert into _g1_blocks values
  ('A', replace($g1a$  -- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (D-062): the adapter's dropped-field tokens.
  v_drop jsonb;
  v_drop_field text;
  v_drop_rule text;
  v_drop_seen text[] := array[]::text[];
  v_drop_i integer;
$g1a$, chr(13), '')),
  ('B', replace($g1b$  -- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (D-062): the optional dropped_fields key is the
  -- adapter's evidence of a provider field it dropped. The whole key is checked here, before the row lookup,
  -- any lock and any write: an array of at most 17 objects of exactly {field, rule}, closed tokens compared
  -- exactly, one entry per field, a non-text field only with 'format', and no field that is also a key of
  -- p_provider_fields (a declared failure is never overridden by a surviving value). Anything else is the
  -- malformed-argument refusal above, never echoed; an absent key changes nothing. Each test that guards a
  -- function raising on another JSON type is its own IF (SQL fixes no evaluation order inside one expression).
  if v_f ? 'dropped_fields' then
    if jsonb_typeof(v_f -> 'dropped_fields') is distinct from 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
    end if;
    if jsonb_array_length(v_f -> 'dropped_fields') > 17 then
      return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
    end if;
    for v_drop_i in 0 .. jsonb_array_length(v_f -> 'dropped_fields') - 1 loop
      v_drop := v_f -> 'dropped_fields' -> v_drop_i;
      if jsonb_typeof(v_drop) is distinct from 'object' then
        return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
      end if;
      v_drop_field := case when jsonb_typeof(v_drop -> 'field') = 'string' then v_drop ->> 'field' end;
      v_drop_rule := case when jsonb_typeof(v_drop -> 'rule') = 'string' then v_drop ->> 'rule' end;
      if v_drop_field is null or v_drop_rule is null or v_drop - 'field' - 'rule' <> '{}'::jsonb
         or v_drop_field <> all (array['provider_reference', 'approval_number', 'voucher_number', 'deposit_id',
                                       'card_last4', 'card_brand_code', 'pan_entry_mode', 'payment_method_code',
                                       'approval_type', 'provider_status_code', 'provider_return_code',
                                       'provider_saved_at', 'error_flag', 'phone_authorization', 'tip_amount',
                                       'provider_amount', 'provider_currency'])
         or v_drop_rule <> all (array['charset', 'length', 'control_character', 'digit_run', 'masked_pattern',
                                      'format'])
         or (v_drop_field in ('error_flag', 'phone_authorization', 'provider_return_code', 'provider_amount',
                              'tip_amount', 'provider_currency', 'provider_saved_at') and v_drop_rule <> 'format')
         or v_f ? v_drop_field or v_drop_field = any (v_drop_seen) then
        return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());
      end if;
      v_drop_seen := v_drop_seen || v_drop_field;
    end loop;
  end if;
$g1b$, chr(13), '')),
  ('C', replace($g1c$  -- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001 (D-062): each field the adapter dropped (checked
  -- above) writes the same deduplicated event with this call's source and sets the same M2 flag as a field
  -- failing here; a TEST attempt's card and provider-reference fields stay unread (no event, no flag).
  for v_drop_i in 0 .. coalesce(jsonb_array_length(v_f -> 'dropped_fields'), 0) - 1 loop
    v_drop_field := v_f -> 'dropped_fields' -> v_drop_i ->> 'field';
    v_drop_rule := v_f -> 'dropped_fields' -> v_drop_i ->> 'rule';
    if a.mode = 'test' and v_drop_field = any (v_test_discard) then
      continue;
    end if;
    perform app.card_private_event_write(a.organization_id, a.restaurant_id, a.branch_id, a.id, a.mode,
      'security.card_provider_field_dropped', 'adapter', 'card_adapter', null, null, null, a.device_id, null,
      jsonb_build_object('field', v_drop_field, 'rule', v_drop_rule, 'source', p_source));
    if v_drop_field in ('error_flag', 'provider_return_code', 'approval_type', 'phone_authorization',
                        'provider_status_code', 'provider_amount', 'provider_currency') then
      v_essential_failed := true;
    elsif v_drop_field = 'tip_amount' then
      v_tip_failed := true;
    end if;
  end loop;
$g1c$, chr(13), ''));
create temp table _g1_def as
select replace(pg_get_functiondef('app.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)'::regprocedure),
               chr(13), '') as def;

-- Rows already in the database before this file (none expected) are not attributed to any call.
select pg_temp.g1_snap('init');

-- ===========================================================================
-- 1. Catalog, ACL and the source-fidelity proof (the SA-135 exception).
-- ===========================================================================
select is(
  (select format('identity=(%s) returns=%s lang=%s volatile=%s secdef=%s config=%s owner=%s acl=%s overloads=%s',
                 pg_get_function_identity_arguments(p.oid), pg_get_function_result(p.oid), l.lanname, p.provolatile,
                 p.prosecdef::text, array_to_string(p.proconfig, ','), pg_get_userbyid(p.proowner), p.proacl,
                 (select count(*) from pg_proc q where q.pronamespace = p.pronamespace and q.proname = p.proname))
     from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = 'app.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)'::regprocedure),
  'identity=(p_attempt_row_id uuid, p_organization_id uuid, p_device_id uuid, p_local_operation_id text, p_mode text, '
  || 'p_amount_minor bigint, p_currency_code text, p_source text, p_outcome text, p_provider_fields jsonb, p_poll_source text) '
  || 'returns=jsonb lang=plpgsql volatile=v secdef=true config=search_path="" owner=postgres '
  || 'acl={postgres=X/postgres,service_role=X/postgres} overloads=1',
  'G1-001 app.card_attempt_finish keeps its identity, result, language, volatility, SECURITY DEFINER, empty search_path, owner, service_role-only ACL and single overload');
select is(
  (select format('md5=%s lang=%s secdef=%s acl=%s overloads=%s', md5(replace(pg_get_functiondef(p.oid), chr(13), '')),
                 l.lanname, p.prosecdef::text, p.proacl,
                 (select count(*) from pg_proc q where q.pronamespace = p.pronamespace and q.proname = p.proname))
     from pg_proc p join pg_language l on l.oid = p.prolang
    where p.oid = 'public.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)'::regprocedure),
  'md5=f87c0fc5231d6418f437879f45a0b1bb lang=sql secdef=false acl={postgres=X/postgres,service_role=X/postgres} overloads=1',
  'G1-002 the public wrapper public.card_attempt_finish is unchanged: the C2 definition (CR-normalized md5 f87c0fc5...), SECURITY INVOKER, service_role-only ACL, one overload');
select is(md5((select def from _g1_def)), 'da9dba46112091dc8dcf1b44cd5619a5',
  'G1-003 the app body is the D-062 body (CR-normalized pg_get_functiondef md5 da9dba46...; SA-135 pins the same value)');
select is((select string_agg(b.name || '=' || ((length(d.def) - length(replace(d.def, b.block, ''))) / length(b.block))::text,
                             ',' order by b.name) from _g1_blocks b cross join _g1_def d),
  'A=1,B=1,C=1',
  'G1-004 source fidelity: each of the three D-062 blocks occurs exactly once in the app definition');
select is((select md5(replace(replace(replace(d.def, (select block from _g1_blocks where name = 'A'), ''),
                                      (select block from _g1_blocks where name = 'B'), ''),
                              (select block from _g1_blocks where name = 'C'), ''))
             from _g1_def d),
  '99040d865e5bcd17f66e40ffe5f956b0',
  'G1-005 source fidelity: with exactly the three blocks removed the app definition is byte-identical to the pre-G1 C2 definition (CR-normalized md5 99040d86..., the former SA-135 pin)');
select is((select format('A=%s B=%s C=%s',
                 (strpos(d.def, $q$  v_updated integer;$q$ || chr(10) || a.block || 'begin' || chr(10)) > 0)::text,
                 (strpos(d.def, $q$    return jsonb_build_object('ok', false, 'error', 'invalid_request', 'server_ts', clock_timestamp());$q$
                                || chr(10) || '  end if;' || chr(10) || b.block
                                || $q$  select * into a from app.card_provider_attempts x where x.id = p_attempt_row_id for update;$q$) > 0)::text,
                 (strpos(d.def, '  end loop;' || chr(10) || c.block
                                || '  -- M3: the informational class; never decides anything.' || chr(10)) > 0)::text)
             from _g1_def d, _g1_blocks a, _g1_blocks b, _g1_blocks c
            where a.name = 'A' and b.name = 'B' and c.name = 'C'),
  'A=true B=true C=true',
  'G1-006 source fidelity: block A follows the last declaration, block B sits between the argument check and the row lookup, block C between the provider-field loop and the M3 step');
select is(
  (select format('proof=%s binding=%s support=%s auth=%s guc=%s raise=%s notify=%s events_table=%s',
                 (s ~ 'card_attempt_proof\s*\(')::text, (s ~ 'card_caller_binding_denial\s*\(')::text,
                 (s ~ 'current_support_session\s*\(')::text, (s ~* 'auth\.(uid|jwt|role)\s*\(')::text,
                 (s ~* '(current_setting|set_config)\s*\(|request\.jwt')::text, (s ~* '\mraise\M')::text,
                 (s ~* 'pg_notify')::text, (s ~ 'card_provider_private_events')::text)
     from (select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as s from pg_proc p
            where p.oid = 'app.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)'::regprocedure) x),
  'proof=false binding=false support=false auth=false guc=false raise=false notify=false events_table=false',
  'G1-007 the session-independent provider-fact exception holds (D-060 point 4): the comment-stripped body re-runs no session proof, reads no caller binding, support session, auth.* function, JWT claim or GUC, raises or notifies nothing (no logging) and touches the private event table only through the writer');
select is((select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where p.prosrc like '%BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-DROP-EVIDENCE-001%'),
  'app.card_attempt_finish',
  'G1-008 app.card_attempt_finish is the only routine carrying the Work ID marker (that the migration holds no other statement is a static check of test/drop_evidence.test.mjs; review SQL-2)');
select is(
  (select coalesce(string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_(temp|toast)'
      and (has_function_privilege('anon', p.oid, 'EXECUTE') or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
      and (p.prosrc ~ 'card_provider_private_events' or p.prosrc ~ 'dropped_fields')),
  '',
  'G1-009 no anon- or authenticated-executable function names the private event table or the dropped_fields key (no client projection of the evidence)');
select is(
  format('anon_public=%s anon_app=%s auth_public=%s auth_app=%s anon_events=%s auth_events=%s',
    pg_temp.g1_try('anon', $s$select public.card_attempt_finish(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'x', 'live', 1, 'ILS', 'lookup', 'not_found', '{"dropped_fields": [{"field": "deposit_id", "rule": "charset"}]}'::jsonb, null)$s$),
    pg_temp.g1_try('anon', $s$select app.card_attempt_finish(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'x', 'live', 1, 'ILS', 'lookup', 'not_found', '{"dropped_fields": [{"field": "deposit_id", "rule": "charset"}]}'::jsonb, null)$s$),
    pg_temp.g1_try('authenticated', $s$select public.card_attempt_finish(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'x', 'live', 1, 'ILS', 'lookup', 'not_found', '{"dropped_fields": [{"field": "deposit_id", "rule": "charset"}]}'::jsonb, null)$s$),
    pg_temp.g1_try('authenticated', $s$select app.card_attempt_finish(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'x', 'live', 1, 'ILS', 'lookup', 'not_found', '{"dropped_fields": [{"field": "deposit_id", "rule": "charset"}]}'::jsonb, null)$s$),
    pg_temp.g1_try('anon', 'select count(*) from app.card_provider_private_events'),
    pg_temp.g1_try('authenticated', 'select count(*) from app.card_provider_private_events')),
  'anon_public=42501 anon_app=42501 auth_public=42501 auth_app=42501 anon_events=42501 auth_events=42501',
  'G1-010 no anon or authenticated access: both finish layers (with valid evidence) and the private event table are refused 42501');

-- ===========================================================================
-- 2. TEST attempts on d2 (the TEST binding first; only one binding of the
--    organization may be enabled / draining at a time).
-- ===========================================================================
select is(pg_temp.zc_pilot('test') ->> 'mode', 'test', 'G1-020 setup: an enabled TEST revision is recorded');
select is(pg_temp.zc_bind(2, 'test') ->> 'new_lifecycle', 'enabled', 'G1-021 setup: the TEST binding of d2 is enabled');
select pg_temp.g1_snap('setup-test');
set local role service_role;
insert into _zc_r select l, pg_temp.zc_claim(8, pg_temp.zc_lop('g1-' || l), 'test', 1234, null, null, 'alpha16-l32-v1', 2)
  from unnest(array['t_disc', 't_ess', 't_ts', 't_rel', 't_res']) l;
reset role;
select pg_temp.g1_snap('claims-test');
select is((select count(*) from _zc_r where label in ('t_disc', 't_ess', 't_ts', 't_rel', 't_res')
                                         and (r ->> 'claim_created')::boolean), 5::bigint,
  'G1-022 setup: five TEST claims created on d2');
select is(pg_temp.g1_do('t_disc-c', 't_disc', 'commit', 'approved', pg_temp.zc_approved_fields()
            || pg_temp.g1_drop('provider_reference', 'masked_pattern', 'card_last4', 'charset', 'approval_number', 'digit_run',
                               'payment_method_code', 'masked_pattern', 'deposit_id', 'length', 'voucher_number', 'control_character',
                               'card_brand_code', 'format', 'pan_entry_mode', 'charset')),
  'answer=envelope | state=approved | class=test_approved | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-023 TEST discard: the eight card and provider-reference fields reported dropped stay unread - no event and no flag, the approval stands');
select is((select count(*) from app.card_provider_private_events e
            where e.attempt_row_id = pg_temp.g1_rid('t_disc') and e.action = 'security.card_provider_field_dropped'),
  0::bigint,
  'G1-024 TEST discard: no field-drop event exists for that TEST attempt at all (the row''s card and reference columns are NULL by the 001D CHECK card_attempts_test_shape, so only the event count discriminates; review SQL-1)');
select is(pg_temp.g1_do('t_ess-c', 't_ess', 'commit', 'approved', pg_temp.zc_approved_fields()
            || pg_temp.g1_drop('phone_authorization', 'format')),
  'answer=envelope | state=unknown | class=test_unknown | anomaly=- | charge=false | refusal=- | audit=- | events=phone_authorization/format/commit',
  'G1-025 TEST essential drop: SQL refuses the approval on its own (UNKNOWN), one private event, no tenant audit');
select ok((select count(*) = 1 and bool_and(e.mode = 'test' and e.retention_until between e.created_at + interval '89 days'
                                                    and e.created_at + interval '91 days'
                  and e.device_id = pg_temp.zc_id('device-2') and e.organization_id = pg_temp.zc_org()
                  and e.restaurant_id = pg_temp.zc_rest() and e.branch_id = pg_temp.zc_branch()
                  and e.attempt_row_id = pg_temp.g1_rid('t_ess') and e.actor_kind = 'adapter' and e.actor_reference = 'card_adapter'
                  and e.detail = '{"field": "phone_authorization", "rule": "format", "source": "commit"}'::jsonb)
             from _g1_evt e where e.k = 't_ess-c'),
  'G1-026 a TEST event takes its scope, mode and device from the row, keeps the 90-day TEST retention, actor adapter / card_adapter, and its detail is exactly {field, rule, source}');
select is(pg_temp.g1_do('t_ts-c', 't_ts', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=test_unknown | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-027 setup: a TEST commit with no evidence finishes unknown');
select is(pg_temp.g1_do('t_ts-l', 't_ts', 'lookup', 'not_found',
            pg_temp.g1_drop('provider_saved_at', 'format', 'provider_reference', 'digit_run'), 'auto'),
  'answer=envelope | state=unknown | class=test_unknown | anomaly=- | charge=false | refusal=- | audit=- | events=provider_saved_at/format/lookup',
  'G1-028 TEST lookup source: the provider timestamp is recorded with source lookup, the reference stays unread');
select ok((select (after_row ->> 'auto_poll_count')::integer = (before_row ->> 'auto_poll_count')::integer + 1
                  and (after_row ->> 'last_lookup_at') is not null and (before_row ->> 'last_lookup_at') is null
             from _g1_call where k = 't_ts-l'),
  'G1-029 the evidence leaves the lookup stamp and the automatic-poll counter as before (stamped and counted once)');
select is(pg_temp.g1_do('t_rel-f', 't_rel', 'release', 'release_failed',
            pg_temp.g1_drop('error_flag', 'format', 'deposit_id', 'masked_pattern')),
  'answer=envelope | state=sent | class=test_sent | anomaly=- | charge=false | refusal=release_failed | audit=- | events=error_flag/format/release',
  'G1-030 TEST release source: an unconfirmed release keeps its advisory semantics (sent, release_failed) and records the essential drop with source release');
select is(pg_temp.g1_do('t_rel-r', 't_rel', 'release', 'released', pg_temp.g1_drop('provider_return_code', 'format')),
  'answer=envelope | state=released | class=test_released | anomaly=- | charge=false | refusal=release_failed | audit=- | events=provider_return_code/format/release',
  'G1-031 TEST release confirmed: released as before (the release branch ignores the flags), the drop recorded with source release');
select is(pg_temp.g1_do('t_res-c', 't_res', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=test_unknown | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-032 setup: a TEST commit finishes unknown');
select is(app.card_attempt_resolve_orphan(pg_temp.g1_rid('t_res'), 'test_closed', 'zc-g1-tres/ref-1', 'ZC001D synthetic G1 TEST closure',
                                          'zc001d-op/ref-5', pg_temp.zc_owner()) ->> 'resolution', 'test_closed',
  'G1-033 setup: the unknown TEST attempt is closed (test_closed)');
select pg_temp.g1_snap('t_res-closed');
select is(pg_temp.g1_bad('t_res-bad', pg_temp.zc_approved_fields() || '{"dropped_fields": [{"field": "zz-echo-probe", "rule": "format"}]}'::jsonb,
                         't_res', null, 'lookup', 'approved'),
  'answer=invalid_request | keys=error,ok,server_ts | row_changed=false | audit=- | events=- | echo=false',
  'G1-034 malformed evidence on a resolved attempt is refused before the resolution branch: no resolution_contradicted event');
select is(pg_temp.g1_do('t_res-l', 't_res', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('tip_amount', 'format')),
  'answer=envelope | state=unknown | class=test_unknown | anomaly=- | charge=false | refusal=- | audit=- | events=security.card_resolution_contradicted',
  'G1-035 resolved TEST attempt: valid evidence records no field drop - only the existing resolution_contradicted event; the row is unchanged');
select ok((select before_row = after_row and answer ->> 'resolution' = 'test_closed' from _g1_call where k = 't_res-l'),
  'G1-036 the resolved row is unchanged and the answer carries its resolution');
select is((select string_agg(app.card_attempt_resolve_orphan(pg_temp.g1_rid(l), 'test_closed', 'zc-g1-tres/ref-2',
                                                              'ZC001D synthetic G1 TEST closure', 'zc001d-op/ref-5',
                                                              pg_temp.zc_owner()) ->> 'resolution', ',' order by l)
             from unnest(array['t_ess', 't_rel', 't_ts']) l),
  'test_closed,test_closed,test_closed',
  'G1-037 setup: the remaining unknown / released TEST attempts are closed');
select is(app.set_payment_terminal(pg_temp.zc_id('device-2'), 'test', 'zc-term-test-2', 'zc-cred-test-2', 'draining', 'test_end',
                                   'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner()) ->> 'new_lifecycle', 'draining',
  'G1-038 setup: the TEST binding of d2 drains');
select is(app.set_payment_terminal(pg_temp.zc_id('device-2'), 'test', 'zc-term-test-2', 'zc-cred-test-2', 'retired', 'test_end',
                                   'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner()) ->> 'new_lifecycle', 'retired',
  'G1-039 setup: the TEST binding of d2 retires');
select pg_temp.g1_snap('test-end');

-- ===========================================================================
-- 3. LIVE attempts on d1.
-- ===========================================================================
select is(pg_temp.zc_pilot('live') ->> 'mode', 'live', 'G1-040 setup: an enabled LIVE revision is recorded');
select is(pg_temp.zc_bind(1, 'live') ->> 'new_lifecycle', 'enabled', 'G1-041 setup: the LIVE binding of d1 is enabled');
select pg_temp.g1_snap('setup-live');
select is(pg_temp.g1_live(array['l_opt', 'l_ess_c', 'l_ess_c2', 'l_ess_l', 'l_ess_l2', 'l_ess_l3', 'l_tip_a', 'l_tip_b',
                                'l_tip_c', 'l_tip_l', 'l_rep', 'l_rep_ess', 'l_dup', 'l_rel_ok', 'l_rel_fail', 'l_failed', 'l_nf',
                                'l_17', 'l_empty', 'l_bad', 'l_scope', 'l_nonsent', 'l_resolved', 'l_session', 'l_mix']), 25,
  'G1-042 setup: 25 LIVE claims created on d1 (claim_created = true)');
select pg_temp.g1_snap('claims-live');

-- 3a. An optional (non-essential) drop: the outcome stands, one private event, no value.
select is(pg_temp.g1_do('l_opt-c', 'l_opt', 'commit', 'approved', pg_temp.zc_approved_fields()
            || pg_temp.g1_drop('provider_reference', 'masked_pattern')),
  'answer=envelope | state=approved | class=approved_unrecorded | anomaly=- | charge=false | refusal=- | audit=card_attempt.approved | events=provider_reference/masked_pattern/commit',
  'G1-043 optional dropped field: the approval is preserved, one card_attempt.approved, one private field-drop event');
select ok((select count(*) = 1 and bool_and(e.mode = 'live' and e.retention_until is null
                  and e.device_id = pg_temp.zc_id('device-1') and e.organization_id = pg_temp.zc_org()
                  and e.attempt_row_id = pg_temp.g1_rid('l_opt') and e.actor_kind = 'adapter' and e.actor_reference = 'card_adapter'
                  and e.detail = '{"field": "provider_reference", "rule": "masked_pattern", "source": "commit"}'::jsonb)
             from _g1_evt e where e.k = 'l_opt-c'),
  'G1-044 the LIVE event: the row''s scope and device, mode live with no retention, actor adapter / card_adapter, detail exactly {field, rule, source} (no value)');
select ok((select a.provider_reference is null and a.approval_type = 'approved' and a.provider_approved_at is not null
             from app.card_provider_attempts a where a.id = pg_temp.g1_rid('l_opt')),
  'G1-045 the dropped field stays NULL on the row; the surviving fields are stored as before');
select is(pg_temp.g1_do('l_mix-c', 'l_mix', 'commit', 'approved', pg_temp.zc_approved_fields()
            || '{"voucher_number": "V 1"}'::jsonb || pg_temp.g1_drop('deposit_id', 'masked_pattern')),
  'answer=envelope | state=approved | class=approved_unrecorded | anomaly=- | charge=false | refusal=- | audit=card_attempt.approved | events=deposit_id/masked_pattern/commit,voucher_number/charset/commit',
  'G1-046 both producers write the same event family in one call: SQL''s own rule (voucher_number) and the adapter''s evidence (deposit_id)');

-- 3b. An essential drop: SQL independently refuses an unsafe approval.
select is(pg_temp.g1_do('l_ess_c-c', 'l_ess_c', 'commit', 'approved', pg_temp.zc_approved_fields()
            || pg_temp.g1_drop('provider_amount', 'format')),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=provider_amount/format/commit',
  'G1-047 essential dropped field on a commit: SQL refuses the approval on its own (UNKNOWN, never approved)');
select is(pg_temp.g1_do('l_ess_c2-c', 'l_ess_c2', 'commit', 'approved', pg_temp.zc_approved_fields()
            || pg_temp.g1_drop('phone_authorization', 'format')),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=phone_authorization/format/commit',
  'G1-048 a dropped phone-authorization flag also refuses the commit approval (UNKNOWN)');
select is(pg_temp.g1_do('l_ess_l-c', 'l_ess_l', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-049 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_ess_l-l', 'l_ess_l', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('error_flag', 'format'), 'auto'),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | refusal=- | audit=card_attempt.provider_anomaly | events=error_flag/format/lookup',
  'G1-050 essential dropped field on a lookup: an approval whose error flag the adapter dropped is the out_of_contract anomaly with charge_may_exist, never approved');
select is(pg_temp.g1_do('l_ess_l2-c', 'l_ess_l2', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-051 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_ess_l2-l', 'l_ess_l2', 'lookup', 'approved', pg_temp.g1_ex(), 'auto'),
  'answer=envelope | state=approved | class=approved_unrecorded | anomaly=- | charge=false | refusal=- | audit=card_attempt.approved | events=-',
  'G1-052 the counterfactual: the same lookup reply without the evidence approves (an absent error flag is not a failure) - the refusal in G1-050 comes from the evidence alone');
select is(pg_temp.g1_do('l_ess_l3-c', 'l_ess_l3', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-053 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_ess_l3-l', 'l_ess_l3', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('phone_authorization', 'format')),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | refusal=- | audit=card_attempt.provider_anomaly | events=phone_authorization/format/lookup',
  'G1-054 a dropped phone-authorization flag on an approving lookup is the out_of_contract anomaly');

-- 3c. The unreadable tip keeps its anomaly precedence.
select is(pg_temp.g1_do('l_tip_a-c', 'l_tip_a', 'commit', 'approved', pg_temp.zc_approved_fields() || pg_temp.g1_drop('tip_amount', 'format')),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | refusal=- | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=tip_amount/format/commit',
  'G1-055 unreadable tip on an approving commit: the out_of_contract anomaly with charge_may_exist (the tip precedes the approval)');
select is(pg_temp.g1_do('l_tip_b-c', 'l_tip_b', 'commit', 'anomaly', '{"anomaly_code": "amount_mismatch"}'::jsonb
            || pg_temp.g1_drop('tip_amount', 'format')),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | refusal=- | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=tip_amount/format/commit',
  'G1-056 unreadable tip on an anomaly reply: out_of_contract overrides the supplied anomaly code');
select is(pg_temp.g1_do('l_tip_c-c', 'l_tip_c', 'commit', 'approved', pg_temp.zc_approved_fields()
            || pg_temp.g1_drop('provider_amount', 'format', 'tip_amount', 'format')),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | refusal=- | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_amount/format/commit,tip_amount/format/commit',
  'G1-057 unreadable tip beside another essential drop: the anomaly (tip first), not a plain UNKNOWN');
select is(pg_temp.g1_do('l_tip_l-c', 'l_tip_l', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-058 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_tip_l-l', 'l_tip_l', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('tip_amount', 'format')),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | refusal=- | audit=card_attempt.provider_anomaly | events=tip_amount/format/lookup',
  'G1-059 unreadable tip on an approving lookup: the out_of_contract anomaly');

-- 3d. UNKNOWN, then an approving lookup with the same drop; repeated evidence.
select is(pg_temp.g1_do('l_rep-c', 'l_rep', 'commit', 'unknown', pg_temp.g1_drop('voucher_number', 'charset')),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=voucher_number/charset/commit',
  'G1-060 an UNKNOWN commit records its drop');
select is(pg_temp.g1_do('l_rep-l', 'l_rep', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('voucher_number', 'charset'), 'auto'),
  'answer=envelope | state=approved | class=approved_unrecorded | anomaly=- | charge=false | refusal=- | audit=card_attempt.approved | events=-',
  'G1-061 the approving lookup with the same drop: no unique conflict, the approval lands, the repeated evidence is deduplicated');
select is((select string_agg(e.detail ->> 'source', ',') from app.card_provider_private_events e
            where e.attempt_row_id = pg_temp.g1_rid('l_rep') and e.action = 'security.card_provider_field_dropped'),
  'commit',
  'G1-062 one event per attempt, field and rule: the first source (commit) is kept');
select is(pg_temp.g1_do('l_rep_ess-c', 'l_rep_ess', 'commit', 'unknown', pg_temp.g1_drop('provider_currency', 'format')),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=provider_currency/format/commit',
  'G1-063 an UNKNOWN commit with an essential drop');
select is(pg_temp.g1_do('l_rep_ess-l', 'l_rep_ess', 'lookup', 'approved', (pg_temp.g1_ex() - 'provider_currency')
            || pg_temp.g1_drop('provider_currency', 'format')),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | refusal=- | audit=card_attempt.provider_anomaly | events=-',
  'G1-064 the same essential drop on the approving lookup: no unique conflict, the correct out_of_contract anomaly, no second event');
select is(pg_temp.g1_do('l_dup-c', 'l_dup', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-065 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_dup-1', 'l_dup', 'lookup', 'not_found', pg_temp.g1_drop('deposit_id', 'masked_pattern'), 'operator'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=- | events=deposit_id/masked_pattern/lookup',
  'G1-066 repeated evidence, first call: one event');
select is(pg_temp.g1_do('l_dup-2', 'l_dup', 'lookup', 'not_found', pg_temp.g1_drop('deposit_id', 'masked_pattern'), 'operator'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-067 repeated identical evidence: deduplicated (no second event, no error)');
select is(pg_temp.g1_do('l_dup-3', 'l_dup', 'lookup', 'not_found', pg_temp.g1_drop('deposit_id', 'charset'), 'operator'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=- | events=deposit_id/charset/lookup',
  'G1-068 another rule for the same field in a later call is its own event (the dedup key is attempt, field and rule)');

-- 3e. All three sources; a failed lookup and a not-found reply carry their evidence.
select is(pg_temp.g1_do('l_rel_ok-r', 'l_rel_ok', 'release', 'released', pg_temp.g1_drop('approval_number', 'digit_run')),
  'answer=envelope | state=released | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.released | events=approval_number/digit_run/release',
  'G1-069 release source: a confirmed release of a sent attempt is released as before, its evidence recorded with source release');
select is(pg_temp.g1_do('l_rel_fail-r', 'l_rel_fail', 'release', 'release_failed',
            pg_temp.g1_drop('provider_return_code', 'format', 'error_flag', 'format')),
  'answer=envelope | state=sent | class=in_progress | anomaly=- | charge=false | refusal=release_failed | audit=card_attempt.release_failed | events=error_flag/format/release,provider_return_code/format/release',
  'G1-070 an unconfirmed release keeps its advisory semantics (sent, release_failed, no anomaly) and records both essential drops with source release');
select is(pg_temp.g1_do('l_failed-c', 'l_failed', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-071 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_failed-l', 'l_failed', 'lookup', 'failed', pg_temp.g1_drop('error_flag', 'format'), 'auto'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=- | events=error_flag/format/lookup',
  'G1-072 a failed lookup (no provider fact) still records the reply''s dropped field; the state is unchanged');
select ok((select (after_row ->> 'auto_poll_count')::integer = 1 and (after_row ->> 'last_lookup_at') is not null
             from _g1_call where k = 'l_failed-l'),
  'G1-073 the failed lookup is stamped and counted exactly as before');
select is(pg_temp.g1_do('l_nf-c', 'l_nf', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-074 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_nf-l', 'l_nf', 'lookup', 'not_found', pg_temp.g1_drop('provider_amount', 'format')),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=- | events=provider_amount/format/lookup',
  'G1-075 a readable not-found reply with a dropped amount stays unchanged (never an anomaly or a decline) with its event written');
select is(pg_temp.g1_do('l_17-c', 'l_17', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-076 setup: a commit finishes unknown');
select is(pg_temp.g1_fin('l_17-l', 'l_17', 'lookup', 'not_found', jsonb_build_object('dropped_fields', (
            select jsonb_agg(jsonb_build_object('field', f, 'rule',
                     case when f in ('error_flag', 'phone_authorization', 'provider_return_code', 'provider_amount', 'tip_amount',
                                     'provider_currency', 'provider_saved_at') then 'format' else 'charset' end) order by o)
              from unnest(array['provider_reference', 'approval_number', 'voucher_number', 'deposit_id', 'card_last4',
                                'card_brand_code', 'pan_entry_mode', 'payment_method_code', 'approval_type',
                                'provider_status_code', 'provider_return_code', 'provider_saved_at', 'error_flag',
                                'phone_authorization', 'tip_amount', 'provider_amount', 'provider_currency'])
                   with ordinality u(f, o)))) ->> 'ok', 'true',
  'G1-077 the boundary: 17 entries, one per field, are accepted');
select is((select count(*)::text || ' events, sources=' || string_agg(distinct e.detail ->> 'source', ',') || ', fields='
                  || count(distinct e.detail ->> 'field')::text from _g1_evt e where e.k = 'l_17-l'),
  '17 events, sources=lookup, fields=17',
  'G1-078 the 17 entries write 17 events, one per field, with source lookup');
select is(pg_temp.g1_do('l_empty-l', 'l_empty', 'lookup', 'not_found', '{"dropped_fields": []}'::jsonb),
  'answer=envelope | state=sent | class=in_progress | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-079 an empty array is no evidence: accepted, nothing recorded');

-- 3f. Malformed, extra-key, oversized and contradicting evidence: refused before any read or write, never echoed.
create temp table _g1_bad (n integer primary key, label text not null, fields jsonb not null);
insert into _g1_bad values
  (1, 'null', '{"dropped_fields": null}'),
  (2, 'object', '{"dropped_fields": {}}'),
  (3, 'string', '{"dropped_fields": "provider_reference"}'),
  (4, 'number', '{"dropped_fields": 1}'),
  (5, 'boolean', '{"dropped_fields": true}'),
  (6, 'element string', '{"dropped_fields": ["provider_reference"]}'),
  (7, 'element null', '{"dropped_fields": [null]}'),
  (8, 'element array', '{"dropped_fields": [["provider_reference", "charset"]]}'),
  (9, 'missing rule', '{"dropped_fields": [{"field": "provider_reference"}]}'),
  (10, 'missing field', '{"dropped_fields": [{"rule": "charset"}]}'),
  (11, 'extra value key', '{"dropped_fields": [{"field": "provider_reference", "rule": "charset", "value": "zz-echo-probe"}]}'),
  (12, 'source override', '{"dropped_fields": [{"field": "provider_reference", "rule": "charset", "source": "commit"}]}'),
  (13, 'scope override', '{"dropped_fields": [{"field": "provider_reference", "rule": "charset", "organization_id": "zz-echo-probe"}]}'),
  (14, 'field number', '{"dropped_fields": [{"field": 1, "rule": "charset"}]}'),
  (15, 'rule null', '{"dropped_fields": [{"field": "provider_reference", "rule": null}]}'),
  (16, 'field object', '{"dropped_fields": [{"field": {"x": "zz-echo-probe"}, "rule": "charset"}]}'),
  (17, 'field array', '{"dropped_fields": [{"field": ["provider_reference"], "rule": "charset"}]}'),
  (18, 'unknown field', '{"dropped_fields": [{"field": "card_number", "rule": "digit_run"}]}'),
  (19, 'unknown rule', '{"dropped_fields": [{"field": "provider_reference", "rule": "zz-echo-probe"}]}'),
  (20, 'field case', '{"dropped_fields": [{"field": "Provider_Reference", "rule": "charset"}]}'),
  (21, 'field padded', '{"dropped_fields": [{"field": "provider_reference ", "rule": "charset"}]}'),
  (22, 'rule case', '{"dropped_fields": [{"field": "provider_reference", "rule": "FORMAT"}]}'),
  (23, 'inapplicable flag rule', '{"dropped_fields": [{"field": "error_flag", "rule": "digit_run"}]}'),
  (24, 'inapplicable tip rule', '{"dropped_fields": [{"field": "tip_amount", "rule": "masked_pattern"}]}'),
  (25, 'inapplicable timestamp rule', '{"dropped_fields": [{"field": "provider_saved_at", "rule": "charset"}]}'),
  (26, 'duplicate identical', '{"dropped_fields": [{"field": "provider_reference", "rule": "charset"}, {"field": "provider_reference", "rule": "charset"}]}'),
  (27, 'duplicate conflicting', '{"dropped_fields": [{"field": "provider_reference", "rule": "charset"}, {"field": "provider_reference", "rule": "digit_run"}]}'),
  (28, 'contradicting value', '{"provider_reference": "REF1", "dropped_fields": [{"field": "provider_reference", "rule": "charset"}]}'),
  (29, 'contradicting null', '{"provider_reference": null, "dropped_fields": [{"field": "provider_reference", "rule": "charset"}]}'),
  (30, 'contradicting empty', '{"provider_reference": "", "dropped_fields": [{"field": "provider_reference", "rule": "charset"}]}'),
  (31, 'contradicting essential', '{"error_flag": false, "dropped_fields": [{"field": "error_flag", "rule": "format"}]}'),
  (32, 'valid then malformed', '{"dropped_fields": [{"field": "deposit_id", "rule": "charset"}, {"field": "zz-echo-probe", "rule": "charset"}]}');
insert into _g1_bad
select 33, 'oversized 18', jsonb_build_object('dropped_fields', (
         select jsonb_agg(jsonb_build_object('field', f, 'rule', 'format') order by o)
           from unnest(array['provider_reference', 'approval_number', 'voucher_number', 'deposit_id', 'card_last4',
                             'card_brand_code', 'pan_entry_mode', 'payment_method_code', 'approval_type',
                             'provider_status_code', 'provider_return_code', 'provider_saved_at', 'error_flag',
                             'phone_authorization', 'tip_amount', 'provider_amount', 'provider_currency', 'deposit_id'])
                with ordinality u(f, o)))
union all
select 34, 'oversized 40', jsonb_build_object('dropped_fields', (
         select jsonb_agg(jsonb_build_object('field', 'zz-echo-probe', 'rule', 'format')) from generate_series(1, 40)));
select is(
  (select coalesce(string_agg(b.n || ' ' || b.label || ': ' || s.sig, '; ' order by b.n), '')
     from _g1_bad b
     cross join lateral (select pg_temp.g1_bad('bad-' || b.n, b.fields) as sig) s
    where s.sig <> 'answer=invalid_request | keys=error,ok,server_ts | row_changed=false | audit=- | events=- | echo=false'),
  '',
  'G1-080 34 malformed, extra-key, oversized, duplicate and contradicting evidence shapes are each refused invalid_request {ok, error, server_ts} with the row unchanged (no lookup stamp, no counter), no audit, no event and no echo of the input');
select is((select count(*) from _g1_call where k like 'bad-%'), 34::bigint, 'G1-081 all 34 malformed calls ran');
select is((select count(*) from app.card_provider_private_events e where e.attempt_row_id = pg_temp.g1_rid('l_bad')),
  0::bigint, 'G1-082 a valid entry before a malformed one is never recorded: the whole key is checked before any write');
select is(pg_temp.g1_bad('bad-unknown-row', '{"dropped_fields": [{"field": "zz-echo-probe", "rule": "format"}]}'::jsonb, 'l_bad',
                         (select r from _zc_r where label = 'l_bad') || jsonb_build_object('attempt_row_id', pg_temp.zc_id('g1-no-such-row'))),
  'answer=invalid_request | keys=error,ok,server_ts | row_changed=false | audit=- | events=- | echo=false',
  'G1-083 malformed evidence for an unknown row id is refused invalid_request, not attempt_not_found: checked before the row lookup');
select is(pg_temp.g1_bad('bad-scope', '{"dropped_fields": [{"field": "zz-echo-probe", "rule": "format"}]}'::jsonb, 'l_scope',
                         (select r from _zc_r where label = 'l_scope') || jsonb_build_object('amount_minor', 1)),
  'answer=invalid_request | keys=error,ok,server_ts | row_changed=false | audit=- | events=- | echo=false',
  'G1-084 malformed evidence with a mismatched scope is refused before the scope check: no scope-mismatch event');

-- 3g. Valid evidence where nothing may be recorded: unknown row, mismatched scope, final state, a commit for a
--     row no longer sent, a resolved attempt.
select is(pg_temp.g1_do('unk-row', 'l_bad', 'lookup', 'not_found', pg_temp.g1_drop('deposit_id', 'charset'), null,
                        (select r from _zc_r where label = 'l_bad') || jsonb_build_object('attempt_row_id', pg_temp.zc_id('g1-no-such-row'))),
  'answer=attempt_not_found | state=sent | class=- | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-085 unknown row id: attempt_not_found, no event (state shown is the untouched l_bad row)');
select is(pg_temp.g1_do('l_scope-m', 'l_scope', 'lookup', 'not_found', pg_temp.g1_drop('deposit_id', 'charset'), null,
                        (select r from _zc_r where label = 'l_scope') || jsonb_build_object('amount_minor', 1)),
  'answer=conflict/attempt_scope_mismatch | state=sent | class=- | anomaly=- | charge=false | refusal=- | audit=- | events=security.card_finish_scope_mismatch',
  'G1-086 mismatched scope: the existing refusal and scope-mismatch event only - the evidence is processed only under the authorized attempt scope');
select is(pg_temp.g1_do('l_opt-t', 'l_opt', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('voucher_number', 'charset')),
  'answer=envelope | state=approved | class=approved_unrecorded | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-087 a final (approved) attempt: the envelope, no event');
select ok((select before_row = after_row from _g1_call where k = 'l_opt-t'), 'G1-088 the final row is unchanged');
select is(pg_temp.g1_do('l_nonsent-c', 'l_nonsent', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-089 setup: a commit finishes unknown');
select is(pg_temp.g1_do('l_nonsent-c2', 'l_nonsent', 'commit', 'approved', pg_temp.zc_approved_fields()
            || pg_temp.g1_drop('voucher_number', 'charset')),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=- | events=-',
  'G1-090 a commit reply for a row no longer sent: the envelope, no event (a commit finishes only a sent row)');
select is(pg_temp.g1_do('l_resolved-c', 'l_resolved', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"tip_amount": "1.00"}'::jsonb),
  'answer=envelope | state=unknown | class=provider_anomaly | anomaly=amount_mismatch | charge=true | refusal=- | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'G1-091 setup: a non-zero tip makes a LIVE anomaly');
select is(app.card_attempt_resolve_orphan(pg_temp.g1_rid('l_resolved'), 'provider_voided', 'zc-g1-res/ref-1',
                                          'ZC001D synthetic G1 resolution', 'zc001d-op/ref-5', pg_temp.zc_owner()) ->> 'resolution',
  'provider_voided', 'G1-092 setup: the LIVE anomaly is resolved provider_voided');
select pg_temp.g1_snap('l_resolved-resolved');
select is(pg_temp.g1_bad('l_resolved-bad', pg_temp.g1_ex() || '{"dropped_fields": [{"field": "zz-echo-probe", "rule": "format"}]}'::jsonb,
                         'l_resolved', null, 'lookup', 'approved'),
  'answer=invalid_request | keys=error,ok,server_ts | row_changed=false | audit=- | events=- | echo=false',
  'G1-093 malformed evidence on a resolved LIVE attempt: refused, no resolution_contradicted event');
select is(pg_temp.g1_do('l_resolved-l', 'l_resolved', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('voucher_number', 'charset')),
  'answer=envelope | state=unknown | class=resolved | anomaly=amount_mismatch | charge=true | refusal=- | audit=- | events=security.card_resolution_contradicted',
  'G1-094 resolved LIVE attempt: valid evidence records only the existing resolution_contradicted event; the row is unchanged');
select ok((select before_row = after_row and answer ->> 'resolution' = 'provider_voided' from _g1_call where k = 'l_resolved-l'),
  'G1-095 the resolved row is unchanged and the answer carries its resolution');

-- 3h. No tenant audit or client projection of the evidence.
select is_empty($$ select k from _g1_call
                    where answer ? 'dropped_fields'
                       or answer::text ~ '(masked_pattern|digit_run|control_character|"charset"|"format"|"field"|"rule")' $$,
  'G1-096 no finish answer of this file carries the evidence (no dropped_fields key, field or rule token)');
select is_empty($$ select k || ' ' || action from _g1_aud
                    where new_values::text ~ '(dropped|"field"|"rule"|masked_pattern|digit_run|control_character|"charset"|"format")' $$,
  'G1-097 no tenant audit row written by this file names the evidence');
set local role authenticated;
insert into _zc_r select 'ctx-l_opt', public.card_attempt_context(pg_temp.zc_id('pin-1'), pg_temp.zc_id('device-1'), 'zc-token-1',
                                                                  null, pg_temp.zc_lop('g1-l_opt'));
reset role;
select ok((select r ->> 'ok' = 'true' and (r -> 'attempt') is not null and not (r -> 'attempt') ? 'dropped_fields'
                  and r::text !~ '(dropped|masked_pattern|digit_run|"rule")'
             from _zc_r where label = 'ctx-l_opt'),
  'G1-098 the POS context proof (as authenticated) of an attempt with recorded evidence projects none of it');

-- 3i. The session-independent finish: the provider fact survives an expired PIN and device session and no JWT.
select is(pg_temp.g1_do('l_session-c', 'l_session', 'commit', 'unknown'),
  'answer=envelope | state=unknown | class=in_progress | anomaly=- | charge=false | refusal=- | audit=card_attempt.unknown | events=-',
  'G1-099 setup: a commit finishes unknown');
update public.pin_sessions set expires_at = now() - interval '1 second' where id = pg_temp.zc_id('pin-1');
update public.device_sessions set expires_at = now() - interval '1 second' where id = pg_temp.zc_id('dsession-1');
select set_config('request.jwt.claim.sub', '', true);
select is(pg_temp.g1_do('l_session-l', 'l_session', 'lookup', 'approved', pg_temp.g1_ex() || pg_temp.g1_drop('voucher_number', 'charset')),
  'answer=envelope | state=approved | class=approved_unrecorded | anomaly=- | charge=false | refusal=- | audit=card_attempt.approved | events=voucher_number/charset/lookup',
  'G1-100 with the PIN and device sessions expired and no JWT subject, the finish still records the provider fact and its evidence (no session proof, D-060 point 4)');

select * from finish();
rollback;
