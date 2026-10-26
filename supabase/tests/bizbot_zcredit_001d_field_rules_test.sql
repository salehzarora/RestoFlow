-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: field rules (M1-M5, M7), finish semantics and the owner read. Rollback-only synthetic fixtures, real SQL roles.
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
-- FR harness (rollback-only). The owner role reads the private tables. The
-- service-only RPCs run under SET LOCAL ROLE service_role and the owner reads
-- under SET LOCAL ROLE authenticated (inside fr_fin / fr_as, reset right after).
-- Every write of an audit row or private event is attributed to the label of
-- the call that produced it (fr_snap), so each finish is asserted exactly.
-- ===========================================================================
create temp table _fr_seen (kind text, id uuid, primary key (kind, id));
create temp table _fr_aud (k text, id uuid, action text, new_values jsonb, actor_employee_profile_id uuid,
                           device_id uuid, reason text);
create temp table _fr_evt (k text, id uuid, attempt_row_id uuid, organization_id uuid, restaurant_id uuid,
                           branch_id uuid, mode text, action text, actor_kind text, actor_reference text,
                           device_id uuid, detail jsonb, retention_until timestamptz);
create temp table _fr_call (k text primary key, c text, source text, outcome text, poll text,
                            before_row jsonb, after_row jsonb);

create function pg_temp.fr_snap(p_k text) returns integer language plpgsql as $$
declare
  v_a integer;
  v_e integer;
begin
  insert into _fr_aud (k, id, action, new_values, actor_employee_profile_id, device_id, reason)
  select p_k, ae.id, ae.action, ae.new_values, ae.actor_employee_profile_id, ae.device_id, ae.reason
    from public.audit_events ae
   where ae.organization_id in (pg_temp.zc_org(), pg_temp.zc_id('org_b'))
     and ae.action like 'card_attempt.%'
     and not exists (select 1 from _fr_seen s where s.kind = 'a' and s.id = ae.id);
  get diagnostics v_a = row_count;
  insert into _fr_seen select 'a', x.id from _fr_aud x where x.k = p_k on conflict do nothing;
  insert into _fr_evt (k, id, attempt_row_id, organization_id, restaurant_id, branch_id, mode, action, actor_kind,
                       actor_reference, device_id, detail, retention_until)
  select p_k, e.id, e.attempt_row_id, e.organization_id, e.restaurant_id, e.branch_id, e.mode, e.action,
         e.actor_kind, e.actor_reference, e.device_id, e.detail, e.retention_until
    from app.card_provider_private_events e
   where not exists (select 1 from _fr_seen s where s.kind = 'e' and s.id = e.id);
  get diagnostics v_e = row_count;
  insert into _fr_seen select 'e', x.id from _fr_evt x where x.k = p_k on conflict do nothing;
  return v_a + v_e;
end $$;

create function pg_temp.fr_rid(p_c text) returns uuid language sql stable as $$
  select (r ->> 'attempt_row_id')::uuid from _zc_r where label = p_c $$;
create function pg_temp.fr_row(p_c text) returns jsonb language sql stable as $$
  select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.fr_rid(p_c) $$;
create function pg_temp.fr_hex(p_v text) returns text language sql immutable as $$
  select string_agg(upper(to_hex(ascii(c))), ' ') from regexp_split_to_table(p_v, '') c $$;

-- One scope-bound finish as the adapter (service_role), with the row before and
-- after and the audit / event delta of exactly this call.
create function pg_temp.fr_fin(p_k text, p_c text, p_source text, p_outcome text,
                               p_fields jsonb default '{}'::jsonb, p_poll text default null,
                               p_claim jsonb default null)
returns jsonb language plpgsql as $$
declare
  v_claim jsonb := coalesce(p_claim, (select r from _zc_r where label = p_c));
  v_before jsonb;
  v jsonb;
begin
  perform pg_temp.fr_snap('pre:' || p_k);
  v_before := pg_temp.fr_row(p_c);
  execute 'set local role service_role';
  v := pg_temp.zc_finish(v_claim, p_source, p_outcome, p_fields, p_poll);
  execute 'reset role';
  insert into _zc_r values (p_k, v);
  insert into _fr_call values (p_k, p_c, p_source, p_outcome, p_poll, v_before, pg_temp.fr_row(p_c));
  perform pg_temp.fr_snap(p_k);
  return v;
end $$;

-- The exact outcome signature of one call: the row's state / anomaly / charge
-- after it, the envelope classification, and exactly the tenant audit actions
-- and private events that call wrote (field drops as field/rule/source).
create function pg_temp.fr_sig(p_k text) returns text language sql stable as $$
  select concat_ws(' | ',
    'state=' || coalesce(c.after_row ->> 'state', '-'),
    'class=' || coalesce((select r ->> 'classification' from _zc_r where label = p_k), '-'),
    'anomaly=' || coalesce(c.after_row ->> 'provider_anomaly_code', '-'),
    'charge=' || coalesce(c.after_row ->> 'charge_may_exist', '-'),
    'audit=' || coalesce((select string_agg(x.action, ',' order by x.action) from _fr_aud x where x.k = p_k), '-'),
    'events=' || coalesce((select string_agg(t.s, ',' order by t.s) from (
        select case when e.action = 'security.card_provider_field_dropped'
                    then concat_ws('/', e.detail ->> 'field', e.detail ->> 'rule', e.detail ->> 'source')
                    else e.action end as s
          from _fr_evt e where e.k = p_k) t), '-'))
  from _fr_call c where c.k = p_k $$;
create function pg_temp.fr_do(p_k text, p_c text, p_source text, p_outcome text,
                              p_fields jsonb default '{}'::jsonb, p_poll text default null,
                              p_claim jsonb default null)
returns text language plpgsql as $$
begin
  perform pg_temp.fr_fin(p_k, p_c, p_source, p_outcome, p_fields, p_poll, p_claim);
  return pg_temp.fr_sig(p_k);
end $$;

-- A one-off service-only call (service_role) with its audit / event delta.
create function pg_temp.fr_svc(p_k text, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.fr_snap('pre:' || p_k);
  execute 'set local role service_role';
  execute p_sql into v;
  execute 'reset role';
  insert into _zc_r values (p_k, v);
  perform pg_temp.fr_snap(p_k);
  return v;
end $$;

-- LIVE claims on d1 by the cashier (staff 1): one synthetic 1234 ILS order each.
create function pg_temp.fr_live(p_labels text[]) returns integer language plpgsql as $$
declare
  l text;
  n integer := 0;
  v jsonb;
begin
  foreach l in array p_labels loop
    perform pg_temp.zc_order('fr-' || l, 1234, 1);
  end loop;
  execute 'set local role service_role';
  foreach l in array p_labels loop
    v := pg_temp.zc_claim(1, pg_temp.zc_lop('fr-' || l), 'live', 1234, pg_temp.zc_id('order-fr-' || l), 1);
    insert into _zc_r values (l, v);
    if coalesce((v ->> 'claim_created')::boolean, false) then
      n := n + 1;
    end if;
  end loop;
  execute 'reset role';
  return n;
end $$;

-- A JWT caller (authenticated) linked to staff n's app user.
create function pg_temp.fr_as(p_n integer, p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
  v_sub text := current_setting('request.jwt.claim.sub', true);
begin
  perform set_config('request.jwt.claim.sub', pg_temp.zc_id('fr-auth-' || p_n)::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', v_sub, true);
  return v;
end $$;
create function pg_temp.fr_oca(p_n integer, p_mode text default 'default',
                               p_from interval default interval '1 day', p_to interval default interval '1 day')
returns jsonb language sql as $$
  select pg_temp.fr_as(p_n, format(
    'select public.owner_card_attempts(%L::uuid, %L::uuid, %L::uuid, now() - %L::interval, now() + %L::interval%s)',
    pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), p_from, p_to,
    case when p_mode = 'default' then '' else format(', %L::text', p_mode) end)) $$;
create function pg_temp.fr_oae(p_n integer, p_sensitive boolean, p_action text default null)
returns jsonb language sql as $$
  select pg_temp.fr_as(p_n, format(
    'select public.owner_audit_events(%L::uuid, %L::uuid, %L::uuid, %L, null, %L, %L::boolean, null, null, 100, null)',
    pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), 'today', p_action, p_sensitive)) $$;

-- The lookup reply that matches a 1234 ILS attempt exactly.
create function pg_temp.fr_ex() returns jsonb language sql immutable as $$
  select jsonb_build_object('provider_status_code', 'ok1', 'provider_amount', '12.34', 'provider_currency', 'ILS') $$;

-- Rows already in the database before this file (none expected) are not attributed to any call.
select pg_temp.fr_snap('init');

-- ===========================================================================
-- 1. Field rules: app.card_safe_text_failure / card_safe_text_ok vectors
--    (packet sec. 4.5; D-058 point 10; M4 / M5). Each vector names the exact token.
-- ===========================================================================
create temp table _fr_v (k serial primary key, grp text not null, field text not null, val text not null, want text);
insert into _fr_v (grp, field, val, want) values
  -- A1: provider_reference / deposit_id = [A-Za-z0-9-], 1..32
  ('A1', 'provider_reference', 'A', null),
  ('A1', 'provider_reference', 'ZC-REF-0001', null),
  ('A1', 'provider_reference', repeat('A', 32), null),
  ('A1', 'provider_reference', repeat('A', 33), 'length'),
  ('A1', 'provider_reference', 'REF_1', 'charset'),
  ('A1', 'provider_reference', 'REF 1', 'charset'),
  ('A1', 'provider_reference', 'REF.1', 'charset'),
  ('A1', 'provider_reference', U&'\00C4BC', 'charset'),
  ('A1', 'provider_reference', U&'AB\00A0CD', 'charset'),
  ('A1', 'provider_reference', U&'\00A0ZC-REF-0002\3000', null),
  ('A1', 'deposit_id', 'DEP-77', null),
  ('A1', 'deposit_id', repeat('D', 32), null),
  ('A1', 'deposit_id', repeat('D', 33), 'length'),
  ('A1', 'deposit_id', 'DEP#1', 'charset'),
  ('A1', 'deposit_id', 'DEP/1', 'charset'),
  -- A2: approval_number / voucher_number = [A-Za-z0-9], 1..16
  ('A2', 'approval_number', '7', null),
  ('A2', 'approval_number', 'APPR77', null),
  ('A2', 'approval_number', repeat('A', 16), null),
  ('A2', 'approval_number', repeat('A', 17), 'length'),
  ('A2', 'approval_number', 'AB-12', 'charset'),
  ('A2', 'approval_number', 'AB_12', 'charset'),
  ('A2', 'voucher_number', 'VCH77', null),
  ('A2', 'voucher_number', repeat('V', 16), null),
  ('A2', 'voucher_number', repeat('V', 17), 'length'),
  ('A2', 'voucher_number', 'V 1', 'charset'),
  -- A3: card_last4 = exactly four ASCII digits after NFKC
  ('A3', 'card_last4', '4242', null),
  ('A3', 'card_last4', U&'\FF14\FF12\FF14\FF12', null),
  ('A3', 'card_last4', U&'\2074\00B2\2074\00B2', null),
  ('A3', 'card_last4', '424', 'length'),
  ('A3', 'card_last4', '42424', 'length'),
  ('A3', 'card_last4', '42a2', 'charset'),
  ('A3', 'card_last4', '4 24', 'charset'),
  ('A3', 'card_last4', U&'\0664\0662\0664\0662', 'charset'),
  -- A4: card_brand_code / approval_type / pan_entry_mode / payment_method_code / provider_status_code = [A-Za-z0-9_-], 1..16
  ('A4', 'card_brand_code', 'VISA_CREDIT-01', null),
  ('A4', 'card_brand_code', repeat('B', 16), null),
  ('A4', 'card_brand_code', repeat('B', 17), 'length'),
  ('A4', 'card_brand_code', 'VISA.X', 'charset'),
  ('A4', 'card_brand_code', 'VISA CARD', 'charset'),
  ('A4', 'approval_type', 'approved', null),
  ('A4', 'approval_type', 'approved!', 'charset'),
  ('A4', 'pan_entry_mode', 'CHIP', null),
  ('A4', 'pan_entry_mode', repeat('C', 17), 'length'),
  ('A4', 'payment_method_code', 'CREDIT', null),
  ('A4', 'payment_method_code', 'CRED/IT', 'charset'),
  ('A4', 'provider_status_code', 'ok1', null),
  ('A4', 'provider_status_code', 'ok 1', 'charset'),
  -- A5: provider_query_key / provider_duplicate_key = [a-p], 1..64
  ('A5', 'provider_query_key', 'abcdefghijklmnop', null),
  ('A5', 'provider_query_key', repeat('p', 64), null),
  ('A5', 'provider_query_key', repeat('p', 65), 'length'),
  ('A5', 'provider_query_key', 'abcq', 'charset'),
  ('A5', 'provider_query_key', 'ABC', 'charset'),
  ('A5', 'provider_query_key', 'abc1', 'charset'),
  ('A5', 'provider_duplicate_key', 'ponmlkjihgfedcba', null),
  ('A5', 'provider_duplicate_key', 'abc-d', 'charset'),
  -- A6: terminal_ref / credential_ref = [a-z0-9_-], 1..64 (lowercase)
  ('A6', 'terminal_ref', 'zc-term_1', null),
  ('A6', 'terminal_ref', repeat('t', 64), null),
  ('A6', 'terminal_ref', repeat('t', 65), 'length'),
  ('A6', 'terminal_ref', 'ZC-TERM', 'charset'),
  ('A6', 'terminal_ref', 'zc.term', 'charset'),
  ('A6', 'credential_ref', 'zc-cred_1', null),
  ('A6', 'credential_ref', 'zc cred', 'charset'),
  ('A6', 'credential_ref', 'zc:cred', 'charset'),
  -- A8: reason / order_freed_note = printable allowlist, 1..200 code points (after NFKC)
  ('A8', 'reason', 'ZC001D synthetic reason', null),
  ('A8', 'reason', repeat('a', 200), null),
  ('A8', 'reason', repeat('a', 201), 'length'),
  ('A8', 'reason', repeat(U&'\FB00', 100), null),
  ('A8', 'reason', repeat(U&'\FB00', 101), 'length'),
  ('A8', 'reason', repeat(U&'e\0301', 200), null),
  ('A8', 'reason', repeat(U&'e\0301', 201), 'length'),
  ('A8', 'order_freed_note', 'ok', null),
  ('A8', 'order_freed_note', repeat(U&'\0628', 200), null),
  ('A8', 'order_freed_note', repeat(U&'\0628', 201), 'length'),
  -- A9: Cc / Zl / Zp / every other Cf -> control_character (never trimmed)
  ('A9', 'reason', 'abc' || chr(9) || 'def', 'control_character'),
  ('A9', 'reason', 'abc' || chr(10) || 'def', 'control_character'),
  ('A9', 'reason', 'abc' || chr(13), 'control_character'),
  ('A9', 'reason', U&'abc\007F', 'control_character'),
  ('A9', 'reason', U&'abc\0085', 'control_character'),
  ('A9', 'reason', U&'abc\2028def', 'control_character'),
  ('A9', 'reason', U&'abc\2029def', 'control_character'),
  ('A9', 'reason', U&'abc\202Adef', 'control_character'),
  ('A9', 'reason', U&'abc\202Bdef', 'control_character'),
  ('A9', 'reason', U&'abc\202Cdef', 'control_character'),
  ('A9', 'reason', U&'abc\202Ddef', 'control_character'),
  ('A9', 'reason', U&'abc\202Edef', 'control_character'),
  ('A9', 'reason', U&'abc\2066def', 'control_character'),
  ('A9', 'reason', U&'abc\2067def', 'control_character'),
  ('A9', 'reason', U&'abc\2068def', 'control_character'),
  ('A9', 'reason', U&'abc\2069def', 'control_character'),
  ('A9', 'reason', U&'abc\200Bdef', 'control_character'),
  ('A9', 'reason', U&'abc\2060def', 'control_character'),
  ('A9', 'reason', U&'abc\FEFFdef', 'control_character'),
  ('A9', 'reason', U&'abc\00ADdef', 'control_character'),
  ('A9', 'reason', U&'\FEFFabc', 'control_character'),
  ('A9', 'reason', U&'abc\2062def', 'control_character'),
  ('A9', 'reason', U&'abc\+0E0041def', 'control_character'),
  ('A9', 'reason', U&'abc\0600def', 'control_character'),
  ('A9', 'reason', U&'abc\180Edef', 'control_character'),
  ('A9', 'order_freed_note', 'abc' || chr(10), 'control_character'),
  ('A9', 'provider_reference', 'AB' || chr(9) || 'CD', 'control_character'),
  ('A9', 'card_brand_code', U&'VI\200BSA', 'control_character'),
  -- A10: Arabic / Hebrew reasons with U+061C, U+200E, U+200F, U+200C, U+200D and combining marks pass
  ('A10', 'reason', U&'\0625\0644\063A\0627\0621 \061C\0627\0644\0637\0644\0628', null),
  ('A10', 'reason', U&'\05D1\05D9\05D8\05D5\05DC\200F \05D4\05D6\05DE\05E0\05D4\200E', null),
  ('A10', 'reason', U&'\0645\06CC\200C\062E\0648\0627\0647\0645', null),
  ('A10', 'reason', U&'\0644\200D\0627', null),
  ('A10', 'reason', U&'\05E9\05C1\05B8\05DC\05D5\05B9\05DD', null),
  ('A10', 'order_freed_note', U&'\0645\064E\0631\0652\062D\064E\0628\064B\0627', null),
  ('A10', 'order_freed_note', U&'\05D4\05D5\05D7\05D6\05E8 \200F\0661\0662\0663\0664\0665\0666\0667\0668\0669\0660\0661', null),
  -- A11: private-use (Co) and unassigned (Cn in UCD 15.1) -> charset
  ('A11', 'reason', U&'abc\E000', 'charset'),
  ('A11', 'reason', U&'abc\F8FF', 'charset'),
  ('A11', 'reason', U&'abc\+0F0000', 'charset'),
  ('A11', 'reason', U&'abc\+10FFFD', 'charset'),
  ('A11', 'reason', U&'abc\0378', 'charset'),
  ('A11', 'reason', U&'abc\FFFF', 'charset'),
  ('A11', 'reason', U&'abc\+01FAE9', 'charset'),
  -- A12: 12+ digit-like characters of any script -> digit_run (C1-4: anywhere in the value; the circled one..twelve
  -- vector holds the Numeric_Type=Numeric circled ten..twelve and answers charset first)
  ('A12', 'reason', '123456789012', 'digit_run'),
  ('A12', 'reason', 'Order 123456789012 ok', 'digit_run'),
  ('A12', 'reason', U&'\0661\0662\0663\0664\0665\0666\0667\0668\0669\0660\0661\0662', 'digit_run'),
  ('A12', 'reason', U&'\06F1\06F2\06F3\06F4\06F5\06F6\06F7\06F8\06F9\06F0\06F1\06F2', 'digit_run'),
  ('A12', 'reason', U&'\0967\0968\0969\096A\096B\096C\096D\096E\096F\0966\0967\0968', 'digit_run'),
  ('A12', 'reason', U&'\FF11\FF12\FF13\FF14\FF15\FF16\FF17\FF18\FF19\FF10\FF11\FF12', 'digit_run'),
  ('A12', 'reason', U&'\00B9\00B2\00B3\2074\2075\2076\2077\2078\2079\2070\00B9\00B2', 'digit_run'),
  ('A12', 'reason', U&'\2460\2461\2462\2463\2464\2465\2466\2467\2468\2469\246A\246B', 'charset'),
  ('A12', 'reason', U&'123456\0667\0668\0669\0660\0661\0662', 'digit_run'),
  ('A12', 'reason', '1234 5678 9012', 'digit_run'),
  ('A12', 'reason', '1234-5678-9012', 'digit_run'),
  ('A12', 'reason', U&'1234\00A05678\00A09012', 'digit_run'),
  ('A12', 'reason', U&'1234\200D5678\200D9012', 'digit_run'),
  ('A12', 'reason', U&'1234\03015678\03019012', 'digit_run'),
  ('A12', 'reason', U&'1234\20135678\20139012', 'digit_run'),
  ('A12', 'provider_reference', repeat('7351', 4), 'digit_run'),
  ('A12', 'provider_reference', rtrim(repeat('7351-', 4), '-'), 'digit_run'),
  ('A12', 'voucher_number', '123456789012', 'digit_run'),
  ('A12', 'payment_method_code', '000000000000', 'digit_run'),
  -- A13: 11 digits pass; (C1-4) a letter of any script no longer resets the count: 12 digits around it -> digit_run
  ('A13', 'reason', '12345678901', null),
  ('A13', 'reason', '1234 5678 901', null),
  ('A13', 'reason', U&'\0661\0662\0663\0664\0665\0666\0667\0668\0669\0660\0661', null),
  ('A13', 'reason', U&'\00B9\00B2\00B3\2074\2075\2076\2077\2078\2079\2070\00B9', null),
  ('A13', 'reason', '123456a789012', 'digit_run'),
  ('A13', 'reason', U&'123456\0628789012', 'digit_run'),
  ('A13', 'reason', U&'123456\05D0789012', 'digit_run'),
  ('A13', 'reason', U&'123456\0640789012', 'digit_run'),
  ('A13', 'provider_reference', left(repeat('7351', 4), 11), null),
  -- A14: M4 raw and canonical forms: U+2122 between digit groups is refused raw; (C1-4) the letters TM no longer
  -- reset the count either -> digit_run
  ('A14', 'reason', U&'1234\21225678\21229012', 'digit_run'),
  ('A14', 'reason', '1234TM5678TM9012', 'digit_run'),
  -- A15 (fixed part): realistic masked numbers and the structured fields
  ('A15', 'reason', U&'\2022\2022\2022\2022 \2022\2022\2022\2022 \2022\2022\2022\2022 4242', 'masked_pattern'),
  ('A15', 'reason', 'Card **** **** **** 4242', 'masked_pattern'),
  ('A15', 'reason', 'XXXX-XXXX-XXXX-1234', 'masked_pattern'),
  ('A15', 'reason', '7351 ' || repeat('*', 4) || ' ' || repeat('*', 4) || ' 1234', 'masked_pattern'),
  ('A15', 'reason', U&'\00B9\00B2\00B3\2074\2022\2075\2076\2077\2078', 'masked_pattern'),
  ('A15', 'provider_reference', 'AB1234XX5678', 'masked_pattern'),
  ('A15', 'approval_number', '1234X5678', 'masked_pattern'),
  ('A15', 'voucher_number', 'XXX1234', 'masked_pattern'),
  ('A15', 'deposit_id', '1234-XXXX-5678', 'masked_pattern'),
  ('A15', 'pan_entry_mode', '1234x5678', 'masked_pattern'),
  ('A15', 'reason', U&'\0661\0662\0663\0664\2022\0665\0666\0667\0668', 'masked_pattern'),
  ('A15', 'reason', U&'\0967\0968\0969\096A**\096B\096C\096D\096E', 'masked_pattern'),
  ('A15', 'reason', U&'\FF11\FF12\FF13\FF14\FF0A\FF15\FF16\FF17\FF18', 'masked_pattern'),
  ('A15', 'reason', U&'\06F1\06F2\06F3\06F4###', 'masked_pattern'),
  ('A15', 'reason', 'ab 1234 / * / 5678 cd', 'masked_pattern'),
  -- (C1-4) 12 digit-like characters with one x between them: digit_run (rule 6) precedes masked_pattern
  ('A15', 'reason', '123456x789012', 'digit_run'),
  ('A15', 'reason', U&'1234\0301\2022\05B85678', 'masked_pattern'),
  ('A16', 'reason', '1234a*5678', null),
  ('A16', 'reason', 'Table 12 * 3 guests', null);
-- A7: the five references = [A-Za-z0-9._:/-], 1..64
insert into _fr_v (grp, field, val, want)
select 'A7', f, v.val, v.want
  from unnest(array['confirmation_reference', 'resolution_reference', 'incident_hold_reference',
                    'operator_reference', 'actor_reference']) f
 cross join (values ('zc001d-op/ref.1:a', null), ('ZC_REF_1', null), ('Z', null), (repeat('r', 64), null),
                    (repeat('r', 65), 'length'), ('ref#1', 'charset'), ('ref 1', 'charset'), ('ref+1', 'charset'),
                    ('ref@1', 'charset')) v(val, want);
-- A15 / A16: each of the 39 mask code points of packet sec. 4.5 (review fix 12 added
-- U+204C, U+204D, U+25D8, U+29BE, U+29BF, U+2619, U+2765, U+2767: every UCD 15.1
-- code point named BULLET except U+1F685).
create temp table _fr_mask (cp text primary key);
insert into _fr_mask values
  (U&'\0023'), (U&'\002A'), (U&'\0058'), (U&'\0078'), (U&'\00B7'), (U&'\00D7'), (U&'\0425'), (U&'\0445'),
  (U&'\066D'), (U&'\2022'), (U&'\2023'), (U&'\2027'), (U&'\2043'), (U&'\204C'), (U&'\204D'), (U&'\204E'),
  (U&'\2217'), (U&'\2219'), (U&'\22C5'), (U&'\25CF'), (U&'\25D8'), (U&'\25E6'), (U&'\2619'), (U&'\2715'),
  (U&'\2716'), (U&'\2731'), (U&'\2765'), (U&'\2767'), (U&'\29BE'), (U&'\29BF'), (U&'\2A2F'), (U&'\30FB'),
  (U&'\FE5F'), (U&'\FE61'), (U&'\FF03'), (U&'\FF0A'), (U&'\FF38'), (U&'\FF58'), (U&'\FF65');
insert into _fr_v (grp, field, val, want)
select 'A15', 'reason', s.val, 'masked_pattern'
  from _fr_mask m cross join lateral (values
    ('1234' || m.cp || '5678'), ('1234' || m.cp || m.cp || '5678'), (m.cp || m.cp || m.cp || '1234'),
    ('1234' || m.cp || m.cp || m.cp), ('1234 - ' || m.cp || ' - 5678')) s(val);
insert into _fr_v (grp, field, val, want)
select 'A16', 'reason', s.val, null
  from _fr_mask m cross join lateral (values
    (m.cp || m.cp || '1234'), ('123' || m.cp || '5678'), ('1234' || m.cp || m.cp)) s(val);

-- C1 brief B.3: a failing vector is named by its number (#k) and tokens only, never printed (no value, no hex dump).
create function pg_temp.fr_bad(p_grp text) returns setof text language sql stable as $$
  select format('#%s %s want=%s got=%s', v.k, v.field, coalesce(v.want, 'NULL'),
                coalesce(app.card_safe_text_failure(v.val, v.field), 'NULL'))
    from _fr_v v
   where v.grp = p_grp and app.card_safe_text_failure(v.val, v.field) is distinct from v.want
   order by v.k $$;

select is_empty($$ select * from pg_temp.fr_bad('A1') $$,
  'FR-01 provider_reference / deposit_id: [A-Za-z0-9-] 1..32 (1 and 32 pass, 33 -> length), _ . space A-umlaut and interior NBSP (NFKC space) -> charset, edge NBSP / U+3000 trimmed -> pass');
select is_empty($$ select * from pg_temp.fr_bad('A2') $$,
  'FR-02 approval_number / voucher_number: [A-Za-z0-9] 1..16 (16 pass, 17 -> length), hyphen / underscore / space -> charset');
select is_empty($$ select * from pg_temp.fr_bad('A3') $$,
  'FR-03 card_last4: exactly 4 ASCII digits after NFKC (fullwidth and superscript digits pass), 3 or 5 digits -> length, letter / space / Arabic-Indic digits -> charset');
select is_empty($$ select * from pg_temp.fr_bad('A4') $$,
  'FR-04 card_brand_code family (approval_type, pan_entry_mode, payment_method_code, provider_status_code): [A-Za-z0-9_-] 1..16, 17 -> length, . / space ! -> charset');
select is_empty($$ select * from pg_temp.fr_bad('A5') $$,
  'FR-05 provider_query_key / provider_duplicate_key: [a-p] 1..64, 65 -> length, q / uppercase / digit / hyphen -> charset');
select is_empty($$ select * from pg_temp.fr_bad('A6') $$,
  'FR-06 terminal_ref / credential_ref: lowercase [a-z0-9_-] 1..64, 65 -> length, uppercase . space : -> charset');
select is_empty($$ select * from pg_temp.fr_bad('A7') $$,
  'FR-07 the five references (confirmation / resolution / incident_hold / operator / actor): [A-Za-z0-9._:/-] 1..64 (dot, underscore, colon, slash, hyphen pass), 65 -> length, # space + @ -> charset');
select is_empty($$ select * from pg_temp.fr_bad('A8') $$,
  'FR-08 reason / order_freed_note: 1..200 code points counted after NFKC (200 pass, 201 -> length; 101 x U+FB00 = 202 after NFKC -> length; 200 x e+U+0301 = 400 raw / 200 composed passes, 201 -> length)');
select is_empty($$ select * from pg_temp.fr_bad('A9') $$,
  'FR-09 tab / LF / CR / DEL / NEL, U+2028 Zl, U+2029 Zp, U+202A..U+202E, U+2066..U+2069, U+200B, U+2060, U+FEFF, U+00AD, U+2062, tag U+E0041, U+0600, U+180E -> control_character');
select is_empty($$ select * from pg_temp.fr_bad('A10') $$,
  'FR-10 Arabic and Hebrew reasons with U+061C, U+200E, U+200F, U+200C, U+200D and combining marks (niqqud, harakat) pass');
select is_empty($$ select * from pg_temp.fr_bad('A11') $$,
  'FR-11 private-use (U+E000, U+F8FF, U+F0000, U+10FFFD) and unassigned in UCD 15.1 (U+0378, U+FFFF, U+1FAE9) -> charset');
select is_empty($$ select * from pg_temp.fr_bad('A12') $$,
  'FR-12 12+ digit-like -> digit_run: ASCII, Arabic-Indic, Extended Arabic-Indic, Devanagari, fullwidth and superscript digits, mixed scripts, across spaces / hyphens / NBSP / ZWJ / U+0301 / en dash; circled one..twelve (U+2460..U+246B) -> charset (C1-4: circled ten..twelve are Numeric_Type=Numeric, refused raw before the digit count)');
select is_empty($$ select * from pg_temp.fr_bad('A13') $$,
  'FR-13 11 digits pass (ASCII, spaced, Arabic-Indic, superscript); 12 digits around a Latin, Arabic, Hebrew or modifier letter (U+0640 tatweel, Lm) -> digit_run (C1-4: 12 digit-like characters anywhere; a letter no longer resets the count)');
select is_empty($$ select * from pg_temp.fr_bad('A14') $$,
  'FR-14 M4: U+2122 between digit groups is refused on the RAW form (digit_run); the same text with the letters TM -> digit_run too (C1-4: letters no longer reset the count)');
select is(app.card_text_canonical(U&'1234\21225678\21229012'), '1234TM5678TM9012',
  'FR-15 M4: NFKC turns U+2122 into the letters TM in the canonical form (C1-4: both forms hold 12 digit-like characters and are refused, FR-14)');
select is((select count(*) from _fr_mask), 39::bigint,
  'FR-16 the mask set under test holds exactly the 39 code points of packet sec. 4.5 (review fix 12: the 31 + U+204C, U+204D, U+25D8, U+29BE, U+29BF, U+2619, U+2765, U+2767)');
select is_empty($$ select * from pg_temp.fr_bad('A15') $$,
  'FR-17 masked_pattern for EACH of the 39 mask code points (review fix 12): 4d+mask+4d, 4d+mask+mask+4d, mask x3 + 4d, 4d + mask x3, separators ignored; plus bullets / asterisks / X runs, superscript digits via NFKC and structured fields; the 12-digit vector with one x between digit groups -> digit_run (C1-4: rule 6, 12 digit-like characters anywhere, precedes masked_pattern)');
select is_empty($$ select * from pg_temp.fr_bad('A16') $$,
  'FR-18 two masks before 4 digits, 3 digits + mask + 4 digits and 4 digits + two masks pass for each of the 39 mask code points (review fix 12)');
select is((select count(*) from _fr_v where grp = 'A15'), (39 * 5 + 17)::bigint,
  'FR-19 harness: 195 generated (39 x 5, review fix 12) + 17 fixed masked vectors present');
select is_empty($$ select v.k from _fr_v v where app.card_safe_text_ok(v.val, v.field) is distinct from (v.want is null) $$,
  'FR-20 app.card_safe_text_ok is exactly (app.card_safe_text_failure IS NULL) over every vector (C1-4: with the updated A12 / A13 / A14 / A15 expectations)');
select ok(app.card_safe_text_ok(null, 'reason') is null and app.card_safe_text_failure(null, 'reason') is null
          and app.card_safe_text_ok('abc', 'no_such_field') is false,
  'FR-21 NULL in = NULL out (a NULL column passes its CHECK); an unknown field fails closed');
select is_empty($$ select v.k from _fr_v v where app.card_text_canonical(app.card_text_canonical(v.val)) is distinct from app.card_text_canonical(v.val) $$,
  'FR-22 M4: app.card_text_canonical is idempotent over every vector');
select is_empty($$ select v.k from _fr_v v where v.want is null and (app.card_text_canonical(v.val) is null or app.card_safe_text_failure(app.card_text_canonical(v.val), v.field) is not null) $$,
  'FR-23 every accepted value also passes in its canonical (stored) form (C1-4: the letter-separated 12-digit vectors of A13 / A14 are no longer accepted)');
select is_empty($$ select pg_temp.fr_hex(z) from unnest(array[U&'\0020', U&'\00A0', U&'\1680', U&'\2000', U&'\2001', U&'\2002', U&'\2003', U&'\2004', U&'\2005', U&'\2006', U&'\2007', U&'\2008', U&'\2009', U&'\200A', U&'\202F', U&'\205F', U&'\3000']) z where app.card_text_canonical(z || z || 'ZC 1' || z) is distinct from 'ZC 1' $$,
  'FR-24 M4: each of the 17 Space_Separator code points of Unicode 15.1 is trimmed at both ends (interior space kept)');
select is_empty($$ select pg_temp.fr_hex(v) from unnest(array[chr(9) || 'abc', U&'\200Babc', U&'\180Eabc', U&'abc\FEFF', U&'\0085abc', U&'abc\2028']) v where app.card_text_canonical(v) is distinct from v $$,
  'FR-25 M4: the trim set is exactly Zs: tab, U+200B, U+180E, U+FEFF, U+0085 and U+2028 are not trimmed');
select is(app.card_text_canonical(U&'\00A0\3000 ZC-REF-0002 \3000\00A0'), 'ZC-REF-0002',
  'FR-26 M4: NBSP / U+3000 / space at both ends are trimmed');
select ok(app.card_text_canonical(U&'\FF34\FF25\FF33\FF34') = 'TEST' and app.card_text_canonical(U&'\FB00') = 'ff'
          and app.card_text_canonical(U&'\2074\00B2') = '42',
  'FR-27 M4: the canonical form is NFKC (fullwidth letters, ligature and superscripts fold to ASCII)');
select ok(app.card_text_canonical('') is null and app.card_text_canonical('   ') is null
          and app.card_text_canonical(U&'\3000\00A0\2007') is null and app.card_text_canonical(null) is null,
  'FR-28 M4: empty or Zs-only text is absent (NULL) after the canonical trim');
select is_empty($$ select f || ':' || pg_temp.fr_hex(v) from unnest(array['provider_reference', 'deposit_id', 'approval_number', 'voucher_number', 'card_last4', 'card_brand_code', 'approval_type', 'pan_entry_mode', 'payment_method_code', 'provider_status_code', 'provider_query_key', 'provider_duplicate_key', 'terminal_ref', 'credential_ref', 'confirmation_reference', 'resolution_reference', 'incident_hold_reference', 'operator_reference', 'actor_reference', 'order_freed_note', 'reason']) f cross join unnest(array['', '   ', U&'\00A0\3000\2007']) v where app.card_safe_text_failure(v, f) is distinct from 'length' $$,
  'FR-29 empty after the canonical trim -> length, for all 21 fields');
select is((select count(distinct grp) from _fr_v), 16::bigint, 'FR-30 harness: all 16 vector groups are populated');

-- ===========================================================================
-- 2. M7: the closed formatter set over 5000 identities per version.
-- ===========================================================================
create temp table _fr_m7 as
select v.ver, v.len, i, sd, dd,
       app.card_provider_key(sd, v.ver) as qk, app.card_provider_key(dd, v.ver) as dk
  from (values ('alpha16-l20-v1', 20), ('alpha16-l24-v1', 24), ('alpha16-l32-v1', 32)) v(ver, len)
 cross join lateral (
   select i,
          app.card_identity_digest('card-status-key/v1',
            case when i % 2 = 0 then pg_temp.zc_org() else pg_temp.zc_id('org_b') end,
            pg_temp.zc_id('device-' || (1 + i % 5)), pg_temp.zc_lop('fr-m7-' || i)) as sd,
          app.card_identity_digest('card-duplicate-key/v1',
            case when i % 2 = 0 then pg_temp.zc_org() else pg_temp.zc_id('org_b') end,
            pg_temp.zc_id('device-' || (1 + i % 5)), pg_temp.zc_lop('fr-m7-' || i)) as dd
     from generate_series(1, 5000) i) g;
select results_eq($$ select ver, count(*)::integer from _fr_m7 group by ver order by ver $$,
  $$ values ('alpha16-l20-v1', 5000), ('alpha16-l24-v1', 5000), ('alpha16-l32-v1', 5000) $$,
  'FR-31 M7: 5000 distinct identities per formatter version');
select is_empty($$ select ver, i from _fr_m7 where qk is null or dk is null or qk !~ ('^[a-p]{' || len || '}$') or dk !~ ('^[a-p]{' || len || '}$') $$,
  'FR-32 M7: every status and duplicate key of l20 / l24 / l32 matches ^[a-p]{N}$ with the version length');
select is_empty($$ select ver, i from _fr_m7 where app.card_safe_text_ok(qk, 'provider_query_key') is not true or app.card_safe_text_ok(dk, 'provider_duplicate_key') is not true $$,
  'FR-33 M7: every key passes app.card_safe_text_ok as provider_query_key / provider_duplicate_key (no digit run or mask by construction)');
select is_empty($$ select ver, i from _fr_m7 where qk <> translate(left(encode(sd, 'hex'), len), '0123456789abcdef', 'abcdefghijklmnop') or dk <> translate(left(encode(dd, 'hex'), len), '0123456789abcdef', 'abcdefghijklmnop') $$,
  'FR-34 M7: each key is the first N hex nibbles of its SHA-256 digest mapped 0..f -> a..p');
select results_eq($$ select ver, count(distinct qk)::integer, count(distinct dk)::integer from _fr_m7 group by ver order by ver $$,
  $$ values ('alpha16-l20-v1', 5000, 5000), ('alpha16-l24-v1', 5000, 5000), ('alpha16-l32-v1', 5000, 5000) $$,
  'FR-35 M7: no key collision among the 5000 identities of any version');
select ok(app.card_provider_key((select sd from _fr_m7 limit 1), 'alpha16-l28-v1') is null
          and app.card_provider_key((select sd from _fr_m7 limit 1), 'ALPHA16-L32-V1') is null
          and app.card_provider_key((select sd from _fr_m7 limit 1), '') is null
          and app.card_provider_key((select sd from _fr_m7 limit 1), null) is null,
  'FR-36 M7: an unknown, differently cased, empty or NULL version -> NULL');
select ok(app.card_provider_key(substring((select sd from _fr_m7 limit 1) from 1 for 31), 'alpha16-l32-v1') is null
          and app.card_provider_key(null, 'alpha16-l32-v1') is null,
  'FR-37 M7: a digest that is not exactly 32 bytes (or NULL) -> NULL');

-- ===========================================================================
-- TEST rows first (d2), so the owner read has TEST rows to filter, then the
-- TEST binding is drained and retired and the LIVE pilot runs on d1 (only one
-- binding of the pilot organization may be enabled / draining at a time).
-- ===========================================================================
select is(pg_temp.zc_pilot('test') ->> 'mode', 'test', 'FR-38 setup: an enabled TEST revision is recorded');
select is(pg_temp.zc_bind(2, 'test') ->> 'new_lifecycle', 'enabled', 'FR-39 setup: the TEST binding of d2 is enabled');
select pg_temp.fr_snap('setup-test');
set local role service_role;
insert into _zc_r select 't1', pg_temp.zc_claim(8, pg_temp.zc_lop('fr-t1'), 'test', 1234, null, null, 'alpha16-l32-v1', 2);
-- A canonical UUID v4 identity made only of digits (32 Nd).
insert into _zc_r select 't2', pg_temp.zc_claim(8, '31415926-5358-4979-8323-846264338327', 'test', 1234, null, null, 'alpha16-l24-v1', 2);
insert into _zc_r select 't3', pg_temp.zc_claim(8, pg_temp.zc_lop('fr-t3'), 'test', 1234, null, null, 'alpha16-l20-v1', 2);
reset role;
select pg_temp.fr_snap('claims-test');
select is((select count(*) from _zc_r where label in ('t1', 't2', 't3') and (r ->> 'claim_created')::boolean), 3::bigint,
  'FR-40 setup: three TEST claims created on d2');
select ok((select r ->> 'claim_created' from _zc_r where label = 't2') = 'true'
          and exists (select 1 from app.card_provider_attempts a where a.id = pg_temp.fr_rid('t2')
                        and a.local_operation_id = '31415926-5358-4979-8323-846264338327')
          and app.card_safe_text_failure('31415926-5358-4979-8323-846264338327', 'reason') = 'digit_run',
  'FR-41 a canonical UUID identity of 32 digits (which the digit rule would refuse as text) is accepted by the ledger: the UUID never meets the digit rule');
-- Scope binding on a TEST row: the event takes mode / scope from the row and keeps the TEST retention.
select is(pg_temp.fr_do('t1-sm', 't1', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 't1') || jsonb_build_object('amount_minor', 1)),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=security.card_finish_scope_mismatch',
  'FR-42 TEST row: an amount mismatch refuses the finish (no ledger change) and writes one scope-mismatch event');
select ok((select e.mode = 'test' and e.retention_until is not null and e.organization_id = pg_temp.zc_org()
                  and e.detail = '{"organization_id": false, "device_id": false, "local_operation_id": false, "mode": false, "amount_minor": true, "currency_code": false}'::jsonb
             from _fr_evt e where e.k = 't1-sm'),
  'FR-43 TEST scope-mismatch event: mode test with its 90-day retention, only amount_minor flagged');
select is(pg_temp.fr_do('t1-c', 't1', 'commit', 'approved',
                        pg_temp.zc_approved_fields() || jsonb_build_object('card_last4', '4242', 'provider_reference', repeat('7351', 4),
                                                                            'approval_number', 'TAPPR1', 'deposit_id', 'TDEP-1')),
  'state=approved | class=test_approved | anomaly=- | charge=false | audit=- | events=-',
  'FR-44 TEST commit approved -> test_approved, no tenant audit, card / reference fields discarded unread (no field-drop event even for a 16-digit reference)');
select ok((select a.card_last4 is null and a.provider_reference is null and a.approval_number is null and a.deposit_id is null
                  and a.provider_approved_at is not null from app.card_provider_attempts a where a.id = pg_temp.fr_rid('t1')),
  'FR-45 TEST approved row keeps no card or provider-reference field');
select is(pg_temp.fr_do('t2-c', 't2', 'commit', 'declined', jsonb_build_object('approval_type', 'declined')),
  'state=declined | class=test_declined | anomaly=- | charge=false | audit=- | events=-',
  'FR-46 TEST commit declined -> test_declined, no tenant audit');
select is(pg_temp.fr_do('t3-c', 't3', 'commit', 'unknown'),
  'state=unknown | class=test_unknown | anomaly=- | charge=false | audit=- | events=-',
  'FR-47 TEST commit unknown -> test_unknown, no tenant audit');
select is(app.card_attempt_resolve_orphan(pg_temp.fr_rid('t3'), 'test_closed', 'zc-tres/ref-88', 'ZC001D synthetic TEST closure',
                                          'zc001d-op/ref-5', pg_temp.zc_owner()) ->> 'resolution', 'test_closed',
  'FR-48 setup: the unknown TEST attempt is closed (test_closed, resolution reference stored)');
select is(app.card_attempt_set_incident_hold('attempt', pg_temp.fr_rid('t1'), true, 'zc-hold/ref-66', 'ZC001D synthetic hold',
                                             'zc001d-op/ref-4', pg_temp.zc_owner()) ->> 'ok', 'true',
  'FR-49 setup: an incident hold is set on the approved TEST attempt');
select pg_temp.fr_snap('test-operator');
select is((select count(*) from _fr_aud where k in ('setup-test', 'claims-test', 't1-sm', 't1-c', 't2-c', 't3-c', 'test-operator')),
  0::bigint, 'FR-50 TEST claims, finishes and operator steps write zero tenant audit rows');
select is(app.set_payment_terminal(pg_temp.zc_id('device-2'), 'test', 'zc-term-test-2', 'zc-cred-test-2', 'draining', 'test_end',
                                   'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner()) ->> 'new_lifecycle', 'draining',
  'FR-51 setup: the TEST binding of d2 drains');
select is(app.set_payment_terminal(pg_temp.zc_id('device-2'), 'test', 'zc-term-test-2', 'zc-cred-test-2', 'retired', 'test_end',
                                   'ZC001D synthetic binding', 'zc001d-op/ref-2', pg_temp.zc_owner()) ->> 'new_lifecycle', 'retired',
  'FR-52 setup: the TEST binding of d2 retires (no unresolved TEST attempt left)');

-- ===========================================================================
-- LIVE pilot on d1: 53 claims of 1234 ILS, each on its own order, plus five
-- sent rows already past their start deadline (inserted directly by the owner:
-- the fixture's zc_age_attempt needs session_replication_role, which the local
-- postgres role may not set, and the frozen-fact trigger forbids moving the
-- deadline of an existing row).
-- ===========================================================================
select is(pg_temp.zc_pilot('live') ->> 'mode', 'live', 'FR-53 setup: an enabled LIVE revision is recorded');
select is(pg_temp.zc_bind(1, 'live') ->> 'new_lifecycle', 'enabled', 'FR-54 setup: the LIVE binding of d1 is enabled');
select pg_temp.fr_snap('setup-live');
create temp table _fr_labels (l text primary key);
insert into _fr_labels values
  ('sc'), ('c_ok'), ('c_noerr'), ('c_errtrue'), ('c_norc'), ('c_rc33'), ('c_noat'), ('c_phone'), ('c_tip1'), ('c_tipbad'),
  ('c_eflag'), ('c_atbad'), ('c_rcbad'), ('c_phbad'), ('c_scbad'), ('c_amtbad'), ('c_curbad'), ('c_dec'), ('c_decnoat'),
  ('c_unk'), ('c_amt'), ('c_cur'), ('c_atempty'), ('c_anx'), ('l_efbad'), ('l_phbad'), ('l_decbad'), ('l_nf'), ('l_pend'),
  ('l_fail'), ('s_nf'), ('a_x'), ('a_v'), ('a_none'), ('r_ok'), ('r_fail'), ('r_unk'),
  ('m1a'), ('m1b'), ('m3a'), ('m3b'), ('n_drop'), ('n_absent'), ('fo'), ('ro'), ('c_dectip'), ('a_vbad'),
  ('m_a1'), ('m_a2'), ('m_a3'), ('m_a4'), ('m_a5'), ('l_rc');
select is(pg_temp.fr_live((select array_agg(l order by l) from _fr_labels)), 53,
  'FR-55 setup: 53 LIVE claims created on d1 (claim_created = true)');
select pg_temp.fr_snap('claims-live');
select ok((select count(*) = 53 and bool_and(action = 'card_attempt.started')
                  and bool_and(new_values = '{"attempt_state": "sent", "mode": "live", "amount_minor": 1234, "currency_code": "ILS"}'::jsonb)
             from _fr_aud where k = 'claims-live'),
  'FR-56 each LIVE claim wrote exactly one card_attempt.started with attempt_state / mode / amount_minor / currency_code');
-- A LIVE sent row whose start deadline has already passed, inserted by the owner
-- through the ledger's insert guard and CHECKs (frozen d1 shift / drawer, the
-- cashier as initiator, the enabled binding's references, real digests and keys).
create function pg_temp.fr_aged(p_l text) returns uuid language plpgsql as $$
declare
  v_org uuid := pg_temp.zc_org();
  v_dev uuid := pg_temp.zc_id('device-1');
  v_lop text := pg_temp.zc_lop('fr-' || p_l);
  v_order uuid := pg_temp.zc_order('fr-' || p_l, 1234, 1);
  v_sd bytea := app.card_identity_digest('card-status-key/v1', pg_temp.zc_org(), pg_temp.zc_id('device-1'), pg_temp.zc_lop('fr-' || p_l));
  v_dd bytea := app.card_identity_digest('card-duplicate-key/v1', pg_temp.zc_org(), pg_temp.zc_id('device-1'), pg_temp.zc_lop('fr-' || p_l));
  a app.card_provider_attempts;
begin
  insert into app.card_provider_attempts (organization_id, restaurant_id, branch_id, device_id, local_operation_id, order_id,
      shift_id, cash_drawer_session_id, initiated_by_employee_profile_id, initiated_by_membership_id, mode, state,
      amount_minor, currency_code, expected_revision, terminal_ref, credential_ref, provider_status_digest,
      provider_duplicate_digest, provider_key_format_version, provider_query_key, provider_duplicate_key, start_deadline_at)
  values (v_org, pg_temp.zc_rest(), pg_temp.zc_branch(), v_dev, v_lop, v_order, pg_temp.zc_id('shift-1'),
      pg_temp.zc_id('drawer-' || v_dev::text), pg_temp.zc_id('employee-1'), pg_temp.zc_id('membership-1'), 'live', 'sent',
      1234, 'ILS', 1, 'zc-term-live-1', 'zc-cred-live-1', v_sd, v_dd, 'alpha16-l32-v1',
      app.card_provider_key(v_sd, 'alpha16-l32-v1'), app.card_provider_key(v_dd, 'alpha16-l32-v1'),
      clock_timestamp() - interval '1 second')
  returning * into a;
  insert into _zc_r values (p_l, jsonb_build_object('attempt_row_id', a.id, 'organization_id', a.organization_id,
    'device_id', a.device_id, 'local_operation_id', a.local_operation_id, 'mode', a.mode,
    'amount_minor', a.amount_minor, 'currency_code', a.currency_code));
  return a.id;
end $$;
select is((select count(pg_temp.fr_aged(l)) from unnest(array['g_pend', 'g_fail', 'g_nf', 'g_rel', 'g_rf']) l), 5::bigint,
  'FR-57 setup: five LIVE sent rows already past their start deadline');
select ok((select count(*) = 5 and bool_and(a.state = 'sent' and a.start_deadline_at < clock_timestamp())
             from app.card_provider_attempts a where a.local_operation_id in
               (select pg_temp.zc_lop('fr-' || l) from unnest(array['g_pend', 'g_fail', 'g_nf', 'g_rel', 'g_rf']) l)),
  'FR-58 setup: ... each is sent with start_deadline_at in the past');
select pg_temp.fr_snap('aged');
-- A LIVE precondition refusal (the cap) is denial evidence: card_attempt.denied.
select pg_temp.zc_order('fr-deny', 2000000, 1);
set local role service_role;
insert into _zc_r select 'deny', pg_temp.zc_claim(1, pg_temp.zc_lop('fr-deny'), 'live', 2000000, pg_temp.zc_id('order-fr-deny'), 1);
reset role;
select pg_temp.fr_snap('deny');
select ok((select (r - 'server_ts') = '{"ok": false, "error": "precondition_failed", "detail": "max_live_amount_exceeded"}'::jsonb
             from _zc_r where label = 'deny')
          and (select count(*) = 1 and bool_and(action = 'card_attempt.denied')
                      and bool_and(new_values = '{"denied_reason": "max_live_amount_exceeded"}'::jsonb)
                 from _fr_aud where k = 'deny'),
  'FR-59 setup: a LIVE claim over the cap is refused (precondition_failed / max_live_amount_exceeded) with one card_attempt.denied');

-- ===========================================================================
-- 3. card_attempt_finish scope binding (D-056 point 4).
-- ===========================================================================
select is(pg_temp.fr_do('sc-org', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 'sc') || jsonb_build_object('organization_id', pg_temp.zc_id('org_b'))),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=security.card_finish_scope_mismatch',
  'FR-60 scope: a foreign organization_id -> refused, sent row untouched, one scope-mismatch event, no audit');
select is(pg_temp.fr_do('sc-dev', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 'sc') || jsonb_build_object('device_id', pg_temp.zc_id('device-2'))),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=security.card_finish_scope_mismatch',
  'FR-61 scope: another device_id -> refused with one scope-mismatch event');
select is(pg_temp.fr_do('sc-lop', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 'sc') || jsonb_build_object('local_operation_id', pg_temp.zc_lop('fr-other'))),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=security.card_finish_scope_mismatch',
  'FR-62 scope: another local_operation_id -> refused with one scope-mismatch event');
select is(pg_temp.fr_do('sc-mode', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 'sc') || jsonb_build_object('mode', 'test')),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=security.card_finish_scope_mismatch',
  'FR-63 scope: mode test against a LIVE row -> refused with one scope-mismatch event');
select is(pg_temp.fr_do('sc-amt', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 'sc') || jsonb_build_object('amount_minor', 1235)),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=security.card_finish_scope_mismatch',
  'FR-64 scope: another amount_minor -> refused with one scope-mismatch event');
select is(pg_temp.fr_do('sc-cur', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 'sc') || jsonb_build_object('currency_code', 'USD')),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=security.card_finish_scope_mismatch',
  'FR-65 scope: another currency_code -> refused with one scope-mismatch event');
select is_empty($$ select label from _zc_r where label in ('sc-org', 'sc-dev', 'sc-lop', 'sc-mode', 'sc-amt', 'sc-cur')
                    and (r - 'server_ts') <> '{"ok": false, "error": "conflict", "detail": "attempt_scope_mismatch"}'::jsonb $$,
  'FR-66 scope: each of the six mismatches RETURNS exactly {ok:false, error:conflict, detail:attempt_scope_mismatch}');
create function pg_temp.fr_scope_evt(p_k text) returns text language sql stable as $$
  select string_agg(format('row_scope=%s mode=%s actor=%s/%s keys=%s bools=%s true=%s',
           (e.organization_id = a.organization_id and e.restaurant_id = a.restaurant_id and e.branch_id = a.branch_id
             and e.device_id = a.device_id and e.attempt_row_id = a.id)::text,
           e.mode, e.actor_kind, e.actor_reference,
           (select string_agg(x, ',' order by x) from jsonb_object_keys(e.detail) x),
           (select bool_and(jsonb_typeof(x.value) = 'boolean') from jsonb_each(e.detail) x)::text,
           (select string_agg(x.key, ',' order by x.key) from jsonb_each(e.detail) x where x.value = 'true'::jsonb)), ' ; ')
    from _fr_evt e join app.card_provider_attempts a on a.id = pg_temp.fr_rid('sc')
   where e.k = p_k and e.action = 'security.card_finish_scope_mismatch' $$;
select results_eq($$ select k, pg_temp.fr_scope_evt(k) from unnest(array['sc-org', 'sc-dev', 'sc-lop', 'sc-mode', 'sc-amt', 'sc-cur']) k order by k $$,
  $$ values
     ('sc-amt', 'row_scope=true mode=live actor=adapter/card_adapter keys=amount_minor,currency_code,device_id,local_operation_id,mode,organization_id bools=true true=amount_minor'),
     ('sc-cur', 'row_scope=true mode=live actor=adapter/card_adapter keys=amount_minor,currency_code,device_id,local_operation_id,mode,organization_id bools=true true=currency_code'),
     ('sc-dev', 'row_scope=true mode=live actor=adapter/card_adapter keys=amount_minor,currency_code,device_id,local_operation_id,mode,organization_id bools=true true=device_id'),
     ('sc-lop', 'row_scope=true mode=live actor=adapter/card_adapter keys=amount_minor,currency_code,device_id,local_operation_id,mode,organization_id bools=true true=local_operation_id'),
     ('sc-mode', 'row_scope=true mode=live actor=adapter/card_adapter keys=amount_minor,currency_code,device_id,local_operation_id,mode,organization_id bools=true true=mode'),
     ('sc-org', 'row_scope=true mode=live actor=adapter/card_adapter keys=amount_minor,currency_code,device_id,local_operation_id,mode,organization_id bools=true true=organization_id') $$,
  'FR-67 scope: each event carries the ROW org / restaurant / branch / device / mode (never the passed values), actor adapter/card_adapter, the six boolean flags, and flags exactly the mismatched field');
select is(pg_temp.fr_row('sc'), (select before_row from _fr_call where k = 'sc-org'),
  'FR-68 scope: after the six mismatches the ledger row is byte-identical (no ledger change)');
select is(pg_temp.fr_do('sc-nf', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                        (select r from _zc_r where label = 'sc') || jsonb_build_object('attempt_row_id', pg_temp.zc_id('fr-no-such-attempt'))),
  'state=sent | class=- | anomaly=- | charge=false | audit=- | events=-',
  'FR-69 scope: an unknown row id writes nothing (no event, no audit)');
select is((select r - 'server_ts' from _zc_r where label = 'sc-nf'), '{"ok": false, "error": "attempt_not_found"}'::jsonb,
  'FR-70 scope: an unknown row id RETURNS exactly {ok:false, error:attempt_not_found}');
select pg_temp.fr_fin('sc-i1', 'sc', 'poll', 'approved', pg_temp.zc_approved_fields());
select pg_temp.fr_fin('sc-i2', 'sc', 'commit', 'not_found');
select pg_temp.fr_fin('sc-i3', 'sc', 'lookup', 'unknown');
select pg_temp.fr_fin('sc-i4', 'sc', 'release', 'approved');
select pg_temp.fr_fin('sc-i5', 'sc', 'lookup', 'not_found', '{}'::jsonb, 'manual');
select pg_temp.fr_fin('sc-i6', 'sc', null, 'approved');
select pg_temp.fr_fin('sc-i7', 'sc', 'commit', null);
select pg_temp.fr_fin('sc-i8', 'sc', 'lookup', 'released');
select pg_temp.fr_fin('sc-i9', 'sc', 'commit', 'approved', pg_temp.zc_approved_fields(), null,
                      (select r from _zc_r where label = 'sc') - 'attempt_row_id');
select is_empty($$ select label from _zc_r where label like 'sc-i_' and (r - 'server_ts') <> '{"ok": false, "error": "invalid_request"}'::jsonb $$,
  'FR-71 scope: bad source (poll / NULL), outcome not of its source (commit not_found, lookup unknown, release approved, lookup released, NULL), bad poll_source (manual) or a NULL row id -> invalid_request');
select ok((select count(*) = 9 from _zc_r where label like 'sc-i_')
          and not exists (select 1 from _fr_aud where k like 'sc-i_') and not exists (select 1 from _fr_evt where k like 'sc-i_')
          and pg_temp.fr_row('sc') = (select before_row from _fr_call where k = 'sc-org'),
  'FR-72 scope: the nine invalid requests write no event, no audit and no ledger change');
select is(pg_temp.fr_do('sc-arr', 'sc', 'commit', 'approved',
                        '[{"error_flag": false, "provider_return_code": 0, "approval_type": "approved"}]'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-73 M2 commit: provider fields that are not a JSON object carry no approval input -> unknown (never approved)');

-- ===========================================================================
-- 4. M2 commit: missing approval input never approves.
-- ===========================================================================
select is(pg_temp.fr_do('c_ok-1', 'c_ok', 'commit', 'approved',
            pg_temp.zc_approved_fields() || jsonb_build_object(
              'tip_amount', '0.00', 'phone_authorization', false, 'provider_amount', '12.34', 'provider_currency', 'ILS',
              'provider_return_class', 'declined', 'provider_reference', 'ZCREF-777', 'approval_number', 'APPR77',
              'voucher_number', 'VCH77', 'deposit_id', 'DEP-77', 'card_last4', U&'\FF14\FF12\FF14\FF12',
              'card_brand_code', U&'\00A0VISA\3000', 'pan_entry_mode', 'CHIP', 'payment_method_code', 'CREDIT',
              'provider_saved_at', '2026-10-24T00:00:00Z')),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=-',
  'FR-74 commit approved with error_flag false, return code 0, approval_type, phone false and tip 0.00 -> approved, one card_attempt.approved');
select is((select jsonb_build_object('provider_reference', a.provider_reference, 'approval_number', a.approval_number,
            'voucher_number', a.voucher_number, 'deposit_id', a.deposit_id, 'card_last4', a.card_last4,
            'card_brand_code', a.card_brand_code, 'pan_entry_mode', a.pan_entry_mode, 'payment_method_code', a.payment_method_code,
            'approval_type', a.approval_type, 'provider_status_code', a.provider_status_code,
            'provider_return_code', a.provider_return_code, 'provider_return_class', a.provider_return_class,
            'provider_saved_at', a.provider_saved_at, 'approved_stamped', a.provider_approved_at is not null,
            'finished_stamped', a.finished_at is not null)
             from app.card_provider_attempts a where a.id = pg_temp.fr_rid('c_ok')),
  jsonb_build_object('provider_reference', 'ZCREF-777', 'approval_number', 'APPR77', 'voucher_number', 'VCH77',
            'deposit_id', 'DEP-77', 'card_last4', '4242', 'card_brand_code', 'VISA', 'pan_entry_mode', 'CHIP',
            'payment_method_code', 'CREDIT', 'approval_type', 'approved', 'provider_status_code', 'ok1',
            'provider_return_code', 0, 'provider_return_class', 'declined',
            'provider_saved_at', '2026-10-24T00:00:00+00:00'::timestamptz, 'approved_stamped', true, 'finished_stamped', true),
  'FR-75 commit approved stores every field in canonical form (fullwidth last4 -> 4242, NBSP / U+3000 trimmed), stamps provider_approved_at; the informational class (declined) never decides the state (M3)');
select is(pg_temp.fr_do('c_noerr-1', 'c_noerr', 'commit', 'approved', pg_temp.zc_approved_fields() - 'error_flag'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-76 M2 commit: error_flag absent -> unknown (never approved)');
select is(pg_temp.fr_do('c_errtrue-1', 'c_errtrue', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"error_flag": true}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-77 M2 commit: error_flag true -> unknown');
select is(pg_temp.fr_do('c_norc-1', 'c_norc', 'commit', 'approved', pg_temp.zc_approved_fields() - 'provider_return_code'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-78 M2 commit: provider_return_code absent -> unknown');
select is(pg_temp.fr_do('c_rc33-1', 'c_rc33', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"provider_return_code": 33}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-79 M2 commit: a non-zero provider_return_code -> unknown');
select is((select r ->> 'provider_return_code' from _zc_r where label = 'c_rc33-1'), '33',
  'FR-80 M2 commit: the sanitized integer return code is stored and returned in the envelope');
select is(pg_temp.fr_do('c_noat-1', 'c_noat', 'commit', 'approved', pg_temp.zc_approved_fields() - 'approval_type'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-81 M2 commit: approval_type absent -> unknown');
select is(pg_temp.fr_do('c_phone-1', 'c_phone', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"phone_authorization": true}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-82 M2 commit: phone_authorization true -> unknown');
select is(pg_temp.fr_do('c_tip1-1', 'c_tip1', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"tip_amount": "1.00"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=amount_mismatch | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-83 M2 commit: a non-zero tip -> anomaly amount_mismatch with charge_may_exist (state unknown, never approved)');
select is(pg_temp.fr_do('c_tipbad-1', 'c_tipbad', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"tip_amount": "1.5"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=tip_amount/format/commit',
  'FR-84 M2 commit: an unreadable tip -> out_of_contract anomaly with charge_may_exist and its field-drop event');
select is(pg_temp.fr_do('c_eflag-1', 'c_eflag', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"error_flag": "false"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=error_flag/format/commit',
  'FR-85 M2 commit: error_flag as a string fails (format) -> unknown + its field-drop event');
select is(pg_temp.fr_do('c_atbad-1', 'c_atbad', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"approval_type": "approved!"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=approval_type/charset/commit',
  'FR-86 M2 commit: a failing approval_type (charset) -> unknown + its field-drop event');
select is(pg_temp.fr_do('c_rcbad-1', 'c_rcbad', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"provider_return_code": 1000000}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_return_code/format/commit',
  'FR-87 M2 commit: provider_return_code outside +-999999 (format) -> unknown + its field-drop event');
select is(pg_temp.fr_do('c_phbad-1', 'c_phbad', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"phone_authorization": "no"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=phone_authorization/format/commit',
  'FR-88 M2 commit: a non-boolean phone_authorization (format) -> unknown + its field-drop event');
select is(pg_temp.fr_do('c_scbad-1', 'c_scbad', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"provider_status_code": "ok 1"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_status_code/charset/commit',
  'FR-89 M2 commit: a failing provider_status_code (essential) -> unknown + its field-drop event');
select is(pg_temp.fr_do('c_amtbad-1', 'c_amtbad', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"provider_amount": "12.3"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_amount/format/commit',
  'FR-90 M2 commit: an amount lexeme outside the grammar (essential) -> unknown + its field-drop event');
select is(pg_temp.fr_do('c_curbad-1', 'c_curbad', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"provider_currency": "ils"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_currency/format/commit',
  'FR-91 M2 commit: a currency outside ^[A-Z]{3}$ (essential) -> unknown + its field-drop event');
select is(pg_temp.fr_do('c_dec-1', 'c_dec', 'commit', 'declined', '{"approval_type": "declined", "provider_return_code": 5}'::jsonb),
  'state=declined | class=declined | anomaly=- | charge=false | audit=card_attempt.declined | events=-',
  'FR-92 M2 commit: declined with a valid approval_type -> declined (approval type has precedence over a non-zero code)');
select is(pg_temp.fr_do('c_decnoat-1', 'c_decnoat', 'commit', 'declined', '{"provider_return_code": 5}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-93 M2 commit: declined without an approval_type -> unknown (never declined)');
select is(pg_temp.fr_do('c_unk-1', 'c_unk', 'commit', 'unknown'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-94 M2 commit: outcome unknown -> unknown');
select is(pg_temp.fr_do('c_amt-1', 'c_amt', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"provider_amount": "12.35"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=amount_mismatch | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-95 M2 commit: an approval whose amount differs -> amount_mismatch anomaly');
select is(pg_temp.fr_do('c_cur-1', 'c_cur', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"provider_currency": "USD"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=currency_mismatch | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-96 M2 commit: an approval in another currency -> currency_mismatch anomaly');
select is(pg_temp.fr_do('c_atempty-1', 'c_atempty', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"approval_type": "   "}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-97 M2 commit: an approval_type empty after the trim is absent (no event) -> unknown');
select is(pg_temp.fr_do('c_anx-1', 'c_anx', 'commit', 'anomaly', '{"anomaly_code": "nonsense"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-98 commit anomaly with an unknown anomaly_code -> out_of_contract');
-- A commit reply reaching a row that is no longer sent changes nothing (no field check, no event).
select is(pg_temp.fr_do('c_noerr-2', 'c_noerr', 'commit', 'approved',
                        pg_temp.zc_approved_fields() || '{"provider_reference": "REF_X", "card_last4": "42a2"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-',
  'FR-99 M2 commit: a commit for a row no longer sent (unknown) answers its envelope: no audit, no event');
select is((select after_row from _fr_call where k = 'c_noerr-2'), (select before_row from _fr_call where k = 'c_noerr-2'),
  'FR-100 M2 commit: ... and the ledger row is byte-identical');

select is(pg_temp.fr_do('c_dectip-1', 'c_dectip', 'commit', 'declined', '{"approval_type": "declined", "tip_amount": "x"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=tip_amount/format/commit',
  'FR-101 M2 commit: an unreadable tip makes even a declined reply the out_of_contract anomaly (never declined)');

-- ===========================================================================
-- 5. M2 lookup: an approval needs a valid status, amount and currency equal to
--    the attempt's; any missing / failing essential input on approved /
--    declined is the out_of_contract anomaly (never declined).
-- ===========================================================================
select is(pg_temp.fr_do('c_noerr-3', 'c_noerr', 'lookup', 'approved', pg_temp.fr_ex(), 'auto'),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=-',
  'FR-102 M2 lookup: approved with a valid status code and the exact amount and currency -> approved (unknown -> approved), one card_attempt.approved');
select ok((select (after_row ->> 'provider_approved_at') is not null and (before_row ->> 'provider_approved_at') is null
             from _fr_call where k = 'c_noerr-3'),
  'FR-103 M2 lookup: the approval stamps provider_approved_at');
select is(pg_temp.fr_do('c_errtrue-2', 'c_errtrue', 'lookup', 'approved', pg_temp.fr_ex() || '{"provider_amount": "12.35"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=amount_mismatch | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-104 M2 lookup: approved with another amount -> amount_mismatch anomaly, charge_may_exist, unknown stays unknown (one provider_anomaly audit)');
select is(pg_temp.fr_do('c_errtrue-3', 'c_errtrue', 'lookup', 'anomaly', '{"anomaly_code": "refunded"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=refunded | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-105 a different anomaly code on an anomalous row -> card_attempt.provider_anomaly again (the code changed)');
select is(pg_temp.fr_do('c_errtrue-4', 'c_errtrue', 'lookup', 'anomaly', '{"anomaly_code": "refunded"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=refunded | charge=true | audit=- | events=-',
  'FR-106 the same anomaly again changes nothing but the lookup stamp: no audit');
select is(pg_temp.fr_do('c_norc-2', 'c_norc', 'lookup', 'approved', pg_temp.fr_ex() || '{"tip_amount": "0.50"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=amount_mismatch | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-107 M2 lookup: approved with a non-zero tip -> amount_mismatch anomaly');
select is(pg_temp.fr_do('c_rc33-2', 'c_rc33', 'lookup', 'approved', pg_temp.fr_ex() || '{"provider_currency": "USD"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=currency_mismatch | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-108 M2 lookup: approved in another currency -> currency_mismatch anomaly');
select is(pg_temp.fr_do('c_noat-2', 'c_noat', 'lookup', 'approved', pg_temp.fr_ex() - 'provider_status_code'),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-109 M2 lookup: approved without provider_status_code -> out_of_contract anomaly');
select is(pg_temp.fr_do('c_phone-2', 'c_phone', 'lookup', 'approved', pg_temp.fr_ex() - 'provider_amount'),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-110 M2 lookup: approved without provider_amount -> out_of_contract anomaly');
select is(pg_temp.fr_do('c_eflag-2', 'c_eflag', 'lookup', 'approved', pg_temp.fr_ex() - 'provider_currency'),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-111 M2 lookup: approved without provider_currency -> out_of_contract anomaly');
select is(pg_temp.fr_do('c_atbad-2', 'c_atbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"provider_status_code": "ok 1"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=provider_status_code/charset/lookup',
  'FR-112 M2 lookup: approved with a failing provider_status_code -> out_of_contract anomaly + its field-drop event');
select is(pg_temp.fr_do('c_rcbad-2', 'c_rcbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"provider_amount": "1234"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=provider_amount/format/lookup',
  'FR-113 M2 lookup: approved with an amount lexeme outside the grammar -> out_of_contract anomaly + its field-drop event');
select is(pg_temp.fr_do('c_phbad-2', 'c_phbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"provider_currency": "IL"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=provider_currency/format/lookup',
  'FR-114 M2 lookup: approved with a failing currency -> out_of_contract anomaly + its field-drop event');
select is(pg_temp.fr_do('c_scbad-2', 'c_scbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"error_flag": true}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-115 M2 lookup: approved carrying error_flag true -> out_of_contract anomaly');
select is(pg_temp.fr_do('c_amtbad-2', 'c_amtbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"phone_authorization": true}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-116 M2 lookup: approved carrying phone_authorization true -> out_of_contract anomaly');
select is(pg_temp.fr_do('c_curbad-2', 'c_curbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"tip_amount": "abc"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=tip_amount/format/lookup',
  'FR-117 M2 lookup: approved with an unreadable tip -> out_of_contract anomaly + its field-drop event');
select is(pg_temp.fr_do('l_efbad-1', 'l_efbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"error_flag": "no"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=error_flag/format/lookup',
  'FR-118 M2 lookup: approved with a failing error_flag on a sent row -> out_of_contract anomaly, sent -> unknown');
select is(pg_temp.fr_do('l_phbad-1', 'l_phbad', 'lookup', 'approved', pg_temp.fr_ex() || '{"phone_authorization": 1}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=phone_authorization/format/lookup',
  'FR-119 M2 lookup: approved with a failing phone_authorization -> out_of_contract anomaly');
select is(pg_temp.fr_do('c_decnoat-2', 'c_decnoat', 'lookup', 'declined', '{"approval_type": "declined"}'::jsonb),
  'state=declined | class=declined | anomaly=- | charge=false | audit=card_attempt.declined | events=-',
  'FR-120 M2 lookup: declined with a valid approval_type -> declined (unknown -> declined)');
select is(pg_temp.fr_do('c_unk-2', 'c_unk', 'lookup', 'declined'),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=-',
  'FR-121 M2 lookup: declined without an approval_type -> out_of_contract anomaly with charge_may_exist (never declined)');
select is(pg_temp.fr_do('c_atempty-2', 'c_atempty', 'lookup', 'declined', '{"approval_type": "dec line"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly | events=approval_type/charset/lookup',
  'FR-122 M2 lookup: declined with a failing approval_type -> out_of_contract anomaly + its field-drop event');
select is(pg_temp.fr_do('l_decbad-1', 'l_decbad', 'lookup', 'declined', '{"approval_type": "declined", "provider_return_code": "zero"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_return_code/format/lookup',
  'FR-123 M2 lookup: declined with another failing essential field (return code) -> out_of_contract anomaly, never declined');
-- The inbound amount grammar ^(0|[1-9][0-9]{0,8})\.[0-9]{2}$ as a JSON string (D-052 point 4).
select results_eq($$ select x.k, pg_temp.fr_do(x.k, x.c, 'lookup', 'approved', pg_temp.fr_ex() || x.f) from (values
    ('m_a1-1', 'm_a1', '{"provider_amount": "012.34"}'::jsonb),
    ('m_a2-1', 'm_a2', '{"provider_amount": 12.34}'::jsonb),
    ('m_a3-1', 'm_a3', '{"provider_amount": "999999999.99"}'::jsonb),
    ('m_a4-1', 'm_a4', '{"provider_amount": "1234567890.00"}'::jsonb),
    ('m_a5-1', 'm_a5', '{"provider_amount": "12.34 "}'::jsonb)) x(k, c, f) order by x.k $$,
  $$ values
    ('m_a1-1', 'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_amount/format/lookup'),
    ('m_a2-1', 'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_amount/format/lookup'),
    ('m_a3-1', 'state=unknown | class=provider_anomaly | anomaly=amount_mismatch | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-'),
    ('m_a4-1', 'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_amount/format/lookup'),
    ('m_a5-1', 'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_amount/format/lookup') $$,
  'FR-124 amount grammar on an approved lookup: a leading zero, a JSON number, 10 integer digits or a trailing space -> format + out_of_contract; the 9-digit maximum is readable (amount_mismatch only)');
-- provider_return_code: a JSON integer within +-999999.
select is(pg_temp.fr_do('l_rc-1', 'l_rc', 'commit', 'unknown'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-125 setup: commit unknown for the return-code bounds');
select pg_temp.fr_fin('l_rc-2', 'l_rc', 'lookup', 'not_found', '{"provider_return_code": 999999}'::jsonb);
select pg_temp.fr_fin('l_rc-3', 'l_rc', 'lookup', 'not_found', '{"provider_return_code": -999999}'::jsonb);
select pg_temp.fr_fin('l_rc-4', 'l_rc', 'lookup', 'not_found', '{"provider_return_code": 1.5}'::jsonb);
select results_eq($$ select k, (after_row ->> 'provider_return_code')::integer, pg_temp.fr_sig(k) from _fr_call where k in ('l_rc-2', 'l_rc-3', 'l_rc-4') order by k $$,
  $$ values ('l_rc-2', 999999, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('l_rc-3', -999999, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('l_rc-4', -999999, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=provider_return_code/format/lookup') $$,
  'FR-126 provider_return_code +-999999 is stored; a non-integer (1.5) is dropped with its event and leaves the stored code');
-- not_found / pending / failed leave the state unchanged; auto_poll_count counts only poll auto.
select is(pg_temp.fr_do('l_nf-1', 'l_nf', 'commit', 'unknown', '{}'::jsonb, 'auto'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-127 setup: commit unknown (carrying poll auto, which a commit never counts)');
select pg_temp.fr_fin('l_nf-2', 'l_nf', 'lookup', 'not_found', '{}'::jsonb, 'auto');
select pg_temp.fr_fin('l_nf-3', 'l_nf', 'lookup', 'not_found', '{}'::jsonb, 'operator');
select pg_temp.fr_fin('l_nf-4', 'l_nf', 'lookup', 'not_found', '{}'::jsonb, null);
select pg_temp.fr_fin('l_nf-5', 'l_nf', 'lookup', 'not_found', '{}'::jsonb, 'auto');
select results_eq($$ select k, pg_temp.fr_sig(k), (after_row ->> 'auto_poll_count')::integer from _fr_call where k like 'l_nf-_' order by k $$,
  $$ values ('l_nf-1', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-', 0),
            ('l_nf-2', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', 1),
            ('l_nf-3', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', 1),
            ('l_nf-4', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', 1),
            ('l_nf-5', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', 2) $$,
  'FR-128 not_found on an unknown row: state unchanged, no audit (stamp-only); auto_poll_count 0 -> 1 (auto) -> 1 (operator) -> 1 (NULL) -> 2 (auto)');
select is_empty($$ select k from _fr_call where k in ('l_nf-2', 'l_nf-3', 'l_nf-4', 'l_nf-5')
                    and not ((after_row ->> 'last_lookup_at')::timestamptz > coalesce((before_row ->> 'last_lookup_at')::timestamptz, '-infinity')) $$,
  'FR-129 every not_found lookup stamps a strictly later last_lookup_at');
select is(pg_temp.fr_do('l_pend-1', 'l_pend', 'commit', 'unknown'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-130 setup: commit unknown for the pending case');
select is(pg_temp.fr_do('l_pend-2', 'l_pend', 'lookup', 'pending', '{"provider_amount": "abc"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=provider_amount/format/lookup',
  'FR-131 pending: state unchanged, no audit, but the failing field still writes its field-drop event');
select is(pg_temp.fr_do('l_fail-1', 'l_fail', 'commit', 'unknown'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-132 setup: commit unknown for the failed case');
select is(pg_temp.fr_do('l_fail-2', 'l_fail', 'lookup', 'failed'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-',
  'FR-133 failed lookup: state unchanged, no audit');
select is(pg_temp.fr_do('s_nf-1', 's_nf', 'lookup', 'not_found'),
  'state=sent | class=in_progress | anomaly=- | charge=false | audit=- | events=-',
  'FR-134 not_found on a sent row inside its start window: still sent, no audit');
select ok((select (after_row ->> 'last_lookup_at') is not null and (after_row ->> 'finished_at') is null
             from _fr_call where k = 's_nf-1'),
  'FR-135 ... the lookup stamps last_lookup_at and leaves finished_at NULL');
select is(pg_temp.fr_do('g_pend-1', 'g_pend', 'lookup', 'pending'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-136 pending on a sent row past its start deadline -> unknown (one card_attempt.unknown)');
select is(pg_temp.fr_do('g_fail-1', 'g_fail', 'lookup', 'failed'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-137 failed on a sent row past its start deadline -> unknown');
select is(pg_temp.fr_do('g_nf-1', 'g_nf', 'lookup', 'not_found'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-138 not_found on a sent row past its start deadline -> unknown');
select ok((select count(*) = 3 and bool_and((after_row ->> 'finished_at') is not null and (after_row ->> 'last_lookup_at') is not null)
             from _fr_call where k in ('g_pend-1', 'g_fail-1', 'g_nf-1')),
  'FR-139 the deadline move to unknown stamps finished_at (and the lookup stamps last_lookup_at)');
select is(pg_temp.fr_do('a_x-1', 'a_x', 'lookup', 'anomaly', '{"anomaly_code": "weird"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-140 lookup anomaly with an unknown anomaly_code -> out_of_contract (sent -> unknown)');
select is(pg_temp.fr_do('a_v-1', 'a_v', 'lookup', 'anomaly', '{"anomaly_code": "voided"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=voided | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-141 lookup anomaly with an allowlisted anomaly_code (voided) keeps that code');
select is(pg_temp.fr_do('a_none-1', 'a_none', 'lookup', 'anomaly'),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-142 lookup anomaly without an anomaly_code -> out_of_contract');
select is(pg_temp.fr_do('a_vbad-1', 'a_vbad', 'lookup', 'anomaly', '{"anomaly_code": "voided", "provider_amount": "abc"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_amount/format/lookup',
  'FR-143 packet M2: a lookup anomaly carrying a failing essential field (amount) is the out_of_contract anomaly, whatever anomaly_code it names');
select is(pg_temp.fr_do('c_tip1-2', 'c_tip1', 'lookup', 'approved', pg_temp.fr_ex()),
  'state=approved | class=approved_unrecorded | anomaly=amount_mismatch | charge=false | audit=card_attempt.approved,card_attempt.provider_anomaly | events=-',
  'FR-144 a later exact approved after an anomaly -> approved, clears charge_may_exist and keeps the anomaly code as history');
select is(pg_temp.fr_do('c_tipbad-2', 'c_tipbad', 'lookup', 'declined', '{"approval_type": "declined"}'::jsonb),
  'state=declined | class=declined | anomaly=out_of_contract | charge=false | audit=card_attempt.declined,card_attempt.provider_anomaly | events=-',
  'FR-145 a later exact declined after an anomaly -> declined, clears charge_may_exist and keeps the anomaly code');
-- approved and declined are final: a later provider fact answers the envelope and writes nothing.
select is(pg_temp.fr_do('c_ok-2', 'c_ok', 'lookup', 'declined', '{"approval_type": "declined", "card_last4": "42a2"}'::jsonb),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=- | events=-',
  'FR-146 approved is final: a later declined lookup (with a failing field) writes nothing');
select is(pg_temp.fr_do('c_noerr-4', 'c_noerr', 'lookup', 'approved', pg_temp.fr_ex(), 'auto'),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=- | events=-',
  'FR-147 idempotent: the same exact approved lookup again writes nothing (no audit, no poll count)');
select is(pg_temp.fr_do('c_dec-2', 'c_dec', 'release', 'released'),
  'state=declined | class=declined | anomaly=- | charge=false | audit=- | events=-',
  'FR-148 declined is final: a release confirmation writes nothing');
select is_empty($$ select k from _fr_call where k in ('c_ok-2', 'c_noerr-4', 'c_dec-2') and after_row is distinct from before_row $$,
  'FR-149 ... the three final rows are byte-identical (no last_lookup_at, no counter, no stamp)');

-- ===========================================================================
-- 6. Release (source release).
-- ===========================================================================
select is(pg_temp.fr_do('r_ok-1', 'r_ok', 'release', 'released'),
  'state=released | class=in_progress | anomaly=- | charge=false | audit=card_attempt.released | events=-',
  'FR-150 release confirmed inside the start window -> released (one card_attempt.released)');
select ok((select (after_row ->> 'released_at') is not null and (after_row ->> 'finished_at') is not null
             from _fr_call where k = 'r_ok-1'),
  'FR-151 ... released_at and finished_at stamped');
select is(pg_temp.fr_do('g_rel-1', 'g_rel', 'release', 'released'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-152 release confirmed after the start deadline -> unknown, never released');
select ok((select (after_row ->> 'released_at') is null from _fr_call where k = 'g_rel-1'),
  'FR-153 ... released_at stays NULL');
select is(pg_temp.fr_do('g_rf-1', 'g_rf', 'release', 'release_failed'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.release_failed,card_attempt.unknown | events=-',
  'FR-154 release_failed on a sent row past its start deadline -> unknown with refusal_code release_failed (card_attempt.unknown + card_attempt.release_failed)');
select ok((select after_row ->> 'refusal_code' = 'release_failed' from _fr_call where k = 'g_rf-1'),
  'FR-155 ... refusal_code release_failed stored');
select is(pg_temp.fr_do('r_fail-1', 'r_fail', 'release', 'release_failed'),
  'state=sent | class=in_progress | anomaly=- | charge=false | audit=card_attempt.release_failed | events=-',
  'FR-156 release_failed on a sent row: state unchanged, exactly one card_attempt.release_failed');
select ok((select after_row ->> 'refusal_code' = 'release_failed' from _fr_call where k = 'r_fail-1')
          and (select r ->> 'refusal_code' = 'release_failed' and r ->> 'state' = 'sent' from _zc_r where label = 'r_fail-1'),
  'FR-157 ... refusal_code release_failed stored and returned in the envelope');
select is(pg_temp.fr_do('r_unk-1', 'r_unk', 'commit', 'unknown'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-158 setup: commit unknown for the advisory release');
select is(pg_temp.fr_do('r_unk-2', 'r_unk', 'release', 'released'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-',
  'FR-159 from unknown the release is advisory: state stays unknown, no audit');
select ok((select (after_row ->> 'released_at') is null from _fr_call where k = 'r_unk-2'),
  'FR-160 ... no released_at on an advisory release');
select is(pg_temp.fr_do('r_unk-3', 'r_unk', 'release', 'release_failed'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.release_failed | events=-',
  'FR-161 release_failed on an unknown row: refusal_code set, state unknown, one card_attempt.release_failed');
select is(pg_temp.fr_do('r_ok-c', 'r_ok', 'commit', 'approved', pg_temp.zc_approved_fields()),
  'state=released | class=in_progress | anomaly=- | charge=false | audit=- | events=-',
  'FR-162 a commit reply reaching a released row changes nothing (only a lookup concludes it)');
select is((select after_row from _fr_call where k = 'r_ok-c'), (select before_row from _fr_call where k = 'r_ok-c'),
  'FR-163 ... the released row is byte-identical');
select is(pg_temp.fr_do('r_ok-2', 'r_ok', 'lookup', 'approved', pg_temp.fr_ex()),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=-',
  'FR-164 an approval found after a release is written as approved (released -> approved)');

-- ===========================================================================
-- 7. M1: the field-drop event is deduplicated per (attempt, field, rule) by
--    ON CONFLICT on its own partial unique index; other errors still raise.
-- ===========================================================================
select is(pg_temp.fr_do('m1a-1', 'm1a', 'commit', 'unknown', jsonb_build_object('provider_reference', repeat('7351', 4))),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_reference/digit_run/commit',
  'FR-165 M1: an UNKNOWN commit dropping provider_reference (digit_run) writes one field-drop event');
select is(pg_temp.fr_do('m1a-2', 'm1a', 'lookup', 'approved', pg_temp.fr_ex() || jsonb_build_object('provider_reference', repeat('7351', 4))),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=-',
  'FR-166 M1: the approving lookup dropping it again is written (approved) and writes no second event');
select ok((select count(*) = 1 from app.card_provider_private_events e
            where e.attempt_row_id = pg_temp.fr_rid('m1a') and e.action = 'security.card_provider_field_dropped'
              and e.detail ->> 'field' = 'provider_reference' and e.detail ->> 'rule' = 'digit_run')
          and (select a.provider_reference is null from app.card_provider_attempts a where a.id = pg_temp.fr_rid('m1a')),
  'FR-167 M1: exactly ONE event exists for (attempt, provider_reference, digit_run) and the value was never stored');
select is(pg_temp.fr_do('m1b-1', 'm1b', 'commit', 'unknown', jsonb_build_object('provider_reference', rtrim(repeat('7351-', 4), '-'))),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_reference/digit_run/commit',
  'FR-168 M1: a hyphenated 16-digit provider_reference -> digit_run event');
select is(pg_temp.fr_do('m1b-2', 'm1b', 'lookup', 'pending', '{"provider_reference": "ZC_REF"}'::jsonb),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=provider_reference/charset/lookup',
  'FR-169 M1: a different rule on the same field (charset) -> a second event');
select is((select array_agg(e.detail ->> 'rule' order by e.detail ->> 'rule') from app.card_provider_private_events e
            where e.attempt_row_id = pg_temp.fr_rid('m1b') and e.action = 'security.card_provider_field_dropped'
              and e.detail ->> 'field' = 'provider_reference'),
  array['charset', 'digit_run'],
  'FR-170 M1: provider_reference of that attempt holds exactly the two (field, rule) events');
select is(app.card_private_event_write(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.fr_rid('m1a'), 'live',
            'security.card_provider_field_dropped', 'adapter', 'card_adapter', null, null, null, pg_temp.zc_id('device-1'), null,
            '{"field": "provider_reference", "rule": "digit_run", "source": "release"}'::jsonb),
  null::uuid,
  'FR-171 M1: a direct duplicate write of the same (attempt, field, rule) is absorbed by ON CONFLICT DO NOTHING (returns NULL)');
select is(pg_temp.fr_snap('m1-direct'), 0, 'FR-172 M1: ... and no row was added');
select throws_ok($$ select app.card_private_event_write(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
                      pg_temp.fr_rid('m1a'), 'live', 'security.card_provider_field_dropped', 'adapter', 'card_adapter',
                      null, null, null, pg_temp.zc_id('device-1'), null,
                      '{"field": "not_a_field", "rule": "digit_run", "source": "commit"}'::jsonb) $$,
  '23514', null,
  'FR-173 M1: a non-dedupe error on the same writer path (detail allowlist CHECK) still raises 23514');

-- ===========================================================================
-- 8. M3: provider_return_class is a closed informational set; a vendor message
--    key is ignored and never stored.
-- ===========================================================================
select pg_temp.fr_fin('m3a-1', 'm3a', 'commit', 'unknown',
  '{"provider_return_class": "weird_class", "provider_message": "ZC001D vendor message 7351", "message": "ZC001D free text"}'::jsonb);
select pg_temp.fr_fin('m3a-2', 'm3a', 'lookup', 'not_found', '{"provider_return_class": "pending"}'::jsonb);
select pg_temp.fr_fin('m3a-3', 'm3a', 'lookup', 'not_found', '{"provider_return_class": null}'::jsonb);
select pg_temp.fr_fin('m3a-4', 'm3a', 'lookup', 'not_found', '{"provider_return_class": 42}'::jsonb);
select pg_temp.fr_fin('m3a-5', 'm3a', 'lookup', 'not_found', '{"provider_return_class": "duplicate"}'::jsonb);
select pg_temp.fr_fin('m3a-6', 'm3a', 'lookup', 'not_found', '{"provider_return_class": true}'::jsonb);
select pg_temp.fr_fin('m3b-1', 'm3b', 'commit', 'unknown',
  '{"provider_return_class": ["approved"], "provider_message": "ZC001D vendor message 7351"}'::jsonb);
select results_eq($$ select k, after_row ->> 'provider_return_class' from _fr_call where k like 'm3_-_' order by k $$,
  $$ values ('m3a-1', 'unclassified'), ('m3a-2', 'pending'), ('m3a-3', 'pending'), ('m3a-4', 'unclassified'),
            ('m3a-5', 'duplicate'), ('m3a-6', 'unclassified'), ('m3b-1', 'unclassified') $$,
  'FR-174 M3: an unknown string, a number, a boolean or an array class -> unclassified; allowlisted tokens are kept; JSON null leaves it unchanged');
select is_empty($$ select 'attempt' from app.card_provider_attempts a where to_jsonb(a)::text ~ 'ZC001D (vendor message|free text)'
                   union all select 'event' from app.card_provider_private_events e where to_jsonb(e)::text ~ 'ZC001D (vendor message|free text)'
                   union all select 'audit' from public.audit_events ae where ae.organization_id = pg_temp.zc_org()
                                                         and to_jsonb(ae)::text ~ 'ZC001D (vendor message|free text)' $$,
  'FR-175 M3: the vendor message keys (provider_message, message) are ignored: no ledger row, event or audit row holds the text');
select is_empty($$ select attname from pg_attribute where attrelid = 'app.card_provider_attempts'::regclass and attnum > 0
                    and not attisdropped and attname ~ '(^|_)(message|payload|raw|receipt|text|vendor)(_|$)' $$,
  'FR-176 M3: the ledger has no column for a provider message, payload or receipt text');

-- ===========================================================================
-- 9. Non-essential fields: a failing one is dropped (NULL, one event each) and
--    never blocks an approval; absent / JSON null / empty values write nothing.
-- ===========================================================================
select is(pg_temp.fr_do('n_drop-1', 'n_drop', 'commit', 'approved',
            pg_temp.zc_approved_fields() || jsonb_build_object(
              'provider_reference', 'REF_1', 'approval_number', 'AB-12', 'voucher_number', 'ABCDEFGHIJKLMNOPQ',
              'deposit_id', repeat('D', 33), 'card_last4', '42a2', 'card_brand_code', U&'VI\200BSA',
              'pan_entry_mode', '1234X5678', 'payment_method_code', '123456789012', 'provider_saved_at', 'not-a-timestamp')),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=approval_number/charset/commit,card_brand_code/control_character/commit,card_last4/charset/commit,deposit_id/length/commit,pan_entry_mode/masked_pattern/commit,payment_method_code/digit_run/commit,provider_reference/charset/commit,provider_saved_at/format/commit,voucher_number/length/commit',
  'FR-177 nine failing non-essential fields never block the approval: approved, one event each with its exact rule');
select ok((select a.provider_reference is null and a.approval_number is null and a.voucher_number is null and a.deposit_id is null
                  and a.card_last4 is null and a.card_brand_code is null and a.pan_entry_mode is null
                  and a.payment_method_code is null and a.provider_saved_at is null and a.approval_type = 'approved'
             from app.card_provider_attempts a where a.id = pg_temp.fr_rid('n_drop')),
  'FR-178 ... every dropped field is NULL on the ledger row');
select is(pg_temp.fr_do('n_absent-1', 'n_absent', 'commit', 'approved',
            pg_temp.zc_approved_fields() || jsonb_build_object(
              'card_last4', null, 'card_brand_code', '   ', 'pan_entry_mode', U&'\3000', 'deposit_id', '',
              'payment_method_code', U&'\00A0\2007', 'provider_reference', U&'\3000\3000', 'provider_saved_at', null)),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=-',
  'FR-179 absent, JSON null and empty-after-trim values are absent: approved, no field-drop event');
select ok((select a.provider_reference is null and a.deposit_id is null and a.card_last4 is null and a.card_brand_code is null
                  and a.pan_entry_mode is null and a.payment_method_code is null and a.provider_saved_at is null
             from app.card_provider_attempts a where a.id = pg_temp.fr_rid('n_absent')),
  'FR-180 ... and stored as NULL');

-- ===========================================================================
-- Free (manager) and operator resolution, used by the owner-read checks.
-- ===========================================================================
select is(pg_temp.fr_do('fo-1', 'fo', 'commit', 'unknown'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-',
  'FR-181 setup: commit unknown for the manager free');
select is(pg_temp.fr_do('fo-2', 'fo', 'lookup', 'not_found'),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-',
  'FR-182 setup: one lookup attempted before the free');
select is(pg_temp.fr_svc('fo-free', format('select public.card_attempt_free_order(%L::uuid, %L::uuid, %L, %L, %L, %L, %L, pg_temp.zc_caller())',
            pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('fr-fo'),
            'ZC001D manager note seventy-seven', 'provider_report', 'zc-conf/ref-77')) ->> 'classification', 'freed',
  'FR-183 setup: the manager frees the order with provider evidence (classification freed)');
select ok((select count(*) = 1 and bool_and(action = 'card_attempt.order_freed')
                  and bool_and(new_values = '{"attempt_state": "unknown", "confirmation_source": "provider_report"}'::jsonb)
                  and bool_and(actor_employee_profile_id = pg_temp.zc_id('employee-2'))
             from _fr_aud where k = 'fo-free'),
  'FR-184 the free writes one card_attempt.order_freed (attempt_state, confirmation_source; the manager as actor)');
select is(pg_temp.fr_do('ro-1', 'ro', 'commit', 'approved', pg_temp.zc_approved_fields() || '{"tip_amount": "2.00"}'::jsonb),
  'state=unknown | class=provider_anomaly | anomaly=amount_mismatch | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=-',
  'FR-185 setup: a LIVE provider anomaly to resolve');
select is(app.card_attempt_resolve_orphan(pg_temp.fr_rid('ro'), 'provider_voided', 'zc-lres/ref-99', 'ZC001D synthetic resolution',
                                          'zc001d-op/ref-6', pg_temp.zc_owner()) ->> 'resolution', 'provider_voided',
  'FR-186 setup: the operator resolves the anomaly as provider_voided');
select pg_temp.fr_snap('ro-res');
select is(pg_temp.fr_do('ro-3', 'ro', 'lookup', 'approved', pg_temp.fr_ex()),
  'state=unknown | class=resolved | anomaly=amount_mismatch | charge=true | audit=- | events=security.card_resolution_contradicted',
  'FR-187 a provider fact reaching a resolved attempt writes only security.card_resolution_contradicted (no audit)');
select ok((select after_row = before_row from _fr_call where k = 'ro-3')
          and (select detail = '{"source": "lookup", "outcome": "approved"}'::jsonb from _fr_evt where k = 'ro-3')
          and (select r ->> 'resolution' = 'provider_voided' from _zc_r where label = 'ro-3'),
  'FR-188 ... the resolved row is unchanged (no last_lookup_at stamp) and the envelope carries the resolution');

-- ===========================================================================
-- Cross-call invariants over every finish of this file.
-- ===========================================================================
select is((select count(*) from _fr_call c join _zc_r z on z.label = c.k
             where c.source = 'lookup' and z.r ->> 'ok' = 'true' and (c.before_row ->> 'state') in ('sent', 'unknown', 'released')
               and (c.before_row ->> 'resolution') is null), 54::bigint,
  'FR-189 harness: 54 lookups reached an open row (approved / declined / anomaly / not_found / pending / failed outcomes)');
select is_empty($$ select c.k from _fr_call c join _zc_r z on z.label = c.k
                    where c.source = 'lookup' and z.r ->> 'ok' = 'true' and (c.before_row ->> 'state') in ('sent', 'unknown', 'released')
                      and (c.before_row ->> 'resolution') is null
                      and not ((c.after_row ->> 'last_lookup_at')::timestamptz
                               > coalesce((c.before_row ->> 'last_lookup_at')::timestamptz, '-infinity')) $$,
  'FR-190 every lookup on an open row (any outcome: approved / declined / anomaly / not_found / pending / failed) stamps a later last_lookup_at');
select is_empty($$ select c.k from _fr_call c join _zc_r z on z.label = c.k
                    where (c.after_row ->> 'auto_poll_count')::integer - (c.before_row ->> 'auto_poll_count')::integer
                          <> case when c.source = 'lookup' and c.poll = 'auto' and z.r ->> 'ok' = 'true'
                                       and (c.before_row ->> 'state') in ('sent', 'unknown', 'released')
                                       and (c.before_row ->> 'resolution') is null then 1 else 0 end $$,
  'FR-191 auto_poll_count moves by exactly one on an open-row lookup with poll auto and never otherwise (commit / release / operator / NULL poll / refused call)');
select is_empty($$ select k from _fr_call
                    where (after_row ->> 'state') = 'approved' and (before_row ->> 'state') <> 'approved'
                      and ((after_row ->> 'provider_approved_at') is null or (before_row ->> 'provider_approved_at') is not null) $$,
  'FR-192 every transition to approved stamps provider_approved_at (and only then)');
select is_empty($$ select k from _fr_call where (after_row ->> 'state') <> 'approved' and (after_row ->> 'provider_approved_at') is not null $$,
  'FR-193 no row that is not approved carries provider_approved_at');

-- ===========================================================================
-- 10. LIVE tenant audit (card_attempt.*): writers, actor, projection, category,
--     sensitivity.
-- ===========================================================================
select is_empty($$ select k, action from _fr_aud
                    where k not in ('init') and (device_id is distinct from pg_temp.zc_id('device-1') or reason is not null
                          or actor_employee_profile_id is distinct from
                             case when action = 'card_attempt.order_freed' then pg_temp.zc_id('employee-2')
                                  else pg_temp.zc_id('employee-1') end) $$,
  'FR-194 every card_attempt.* row of the LIVE attempts names device d1, reason NULL, and the frozen initiating employee as actor (the manager for order_freed)');
create temp table _fr_allow (action text primary key, keys text[]);
insert into _fr_allow values
  ('card_attempt.started', array['amount_minor', 'attempt_state', 'currency_code', 'mode']),
  ('card_attempt.approved', array['anomaly_code', 'attempt_state', 'refusal_code', 'release_requested']),
  ('card_attempt.declined', array['anomaly_code', 'attempt_state', 'refusal_code', 'release_requested']),
  ('card_attempt.unknown', array['anomaly_code', 'attempt_state', 'refusal_code', 'release_requested']),
  ('card_attempt.released', array['anomaly_code', 'attempt_state', 'refusal_code', 'release_requested']),
  ('card_attempt.provider_anomaly', array['anomaly_code', 'attempt_state', 'refusal_code', 'release_requested']),
  ('card_attempt.release_requested', array['attempt_state']),
  ('card_attempt.release_failed', array['attempt_state']),
  ('card_attempt.recording_refused', array['refusal_code']),
  ('card_attempt.order_freed', array['attempt_state', 'confirmation_source']),
  ('card_attempt.recording_resume_requested', array['attempt_state', 'denied_reason', 'outcome', 'prior_refusal_code', 'resume_count']),
  ('card_attempt.denied', array['denied_reason']);
-- Synthetic tenant rows of the two writers this lane does not drive (recording
-- result, Resume guard), for the projection and sensitivity checks only.
insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_employee_profile_id, device_id, action, reason, new_values)
values
  (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('employee-1'), pg_temp.zc_id('device-1'),
   'card_attempt.recording_refused', null, '{"refusal_code": "precondition_failed"}'::jsonb),
  (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('employee-1'), pg_temp.zc_id('device-1'),
   'card_attempt.recording_resume_requested', null,
   '{"attempt_state": "approved", "prior_refusal_code": "precondition_failed", "resume_count": 1, "outcome": "dispatched"}'::jsonb);
select pg_temp.fr_snap('synthetic-audit');
select is_empty($$ select k, action from _fr_aud where k <> 'init' and app.audit_safe_detail(action, new_values) is distinct from new_values $$,
  'FR-195 the projection app.audit_safe_detail(action, new_values) keeps exactly what each writer stored (only allowlisted scalars are written)');
select is_empty($$ select x.k, x.action, app.audit_safe_detail(x.action, x.new_values)
                    from _fr_aud x join _fr_allow a on a.action = x.action
                   where x.k <> 'init' and not (array(select jsonb_object_keys(app.audit_safe_detail(x.action, x.new_values))) <@ a.keys)
                   union all select k, action, null from _fr_aud where k <> 'init' and action not in (select action from _fr_allow) $$,
  'FR-196 every card_attempt.* row written here is a registered action whose projected keys stay inside its per-action allowlist');
select results_eq($$ select x.action, count(*)::integer from _fr_aud x where x.k not like 'synthetic%' and x.k <> 'init' group by x.action order by x.action $$,
  $$ values ('card_attempt.approved', 7), ('card_attempt.declined', 3), ('card_attempt.denied', 1),
            ('card_attempt.order_freed', 1), ('card_attempt.provider_anomaly', 36), ('card_attempt.release_failed', 3),
            ('card_attempt.released', 1), ('card_attempt.started', 53), ('card_attempt.unknown', 51) $$,
  'FR-197 the exact count per action of the LIVE tenant audit rows written by this file (claims, finishes, free, denial)');
create temp table _fr_sink as select jsonb_build_object(
  'attempt_state', 'approved', 'mode', 'live', 'amount_minor', 1234, 'currency_code', 'ILS', 'refusal_code', 'release_failed',
  'anomaly_code', 'amount_mismatch', 'release_requested', true, 'confirmation_source', 'provider_report',
  'prior_refusal_code', 'precondition_failed', 'resume_count', 1, 'outcome', 'dispatched', 'denied_reason', 'permission_denied',
  'provider_reference', 'ZCREF-777', 'approval_number', 'APPR77', 'voucher_number', 'VCH77', 'deposit_id', 'DEP-77',
  'card_last4', '4242', 'terminal_ref', 'zc-term-live-1', 'credential_ref', 'zc-cred-live-1', 'provider_query_key', 'abcdefghijklmnopabcd',
  'reason', 'free text', 'confirmation_reference', 'zc-conf/ref-77', 'order_freed_note', 'note', 'status', 'paid',
  'resolution', 'provider_voided', 'grand_total_minor', 1234, 'tendered_minor', 1234, 'local_operation_id', 'x',
  'order_id', 'x', 'payment_status', 'x', 'name', 'x', 'value', 'x', 'role', 'manager') as v;
select is_empty($$ select a.action, (select array_agg(k order by k) from jsonb_object_keys(app.audit_safe_detail(a.action, s.v)) k) as got, a.keys
                    from _fr_allow a cross join _fr_sink s
                   where (select array_agg(k order by k) from jsonb_object_keys(app.audit_safe_detail(a.action, s.v)) k) is distinct from a.keys $$,
  'FR-198 app.audit_safe_detail projects EXACTLY the per-action keys of packet sec. 4.7 for all 12 card actions (money keys only on .started; no global key such as status / resolution / grand_total_minor / role)');
select is((select count(*) from _fr_allow), 12::bigint, 'FR-199 harness: the 12 registered card_attempt.* actions are under test');
select is(app.audit_safe_detail('card_attempt.bogus', (select v from _fr_sink)), '{}'::jsonb,
  'FR-200 an unregistered card_attempt.* action projects nothing (never the global allowlist)');
select is(app.audit_safe_detail('card_attempt.approved', '{"attempt_state": {"x": 1}, "anomaly_code": ["a"], "release_requested": true}'::jsonb),
  '{"release_requested": true}'::jsonb,
  'FR-201 a non-scalar value of an allowlisted key is dropped');
select is_empty($$ select action from _fr_allow where app.audit_category(action) <> 'payments' or not app.audit_action_has_detail(action)
                   union all select 'card_attempt.anything' where app.audit_category('card_attempt.anything') <> 'payments'
                                                               or not app.audit_action_has_detail('card_attempt.anything') $$,
  'FR-202 app.audit_category(card_attempt.*) = payments and app.audit_action_has_detail is true for the family');
-- The owner JWT actor (org_owner, staff 9) and the role matrix of the owner read.
insert into auth.users (id, email)
select pg_temp.zc_id('fr-auth-' || n), 'zc001d-fr-' || n || '@example.test' from unnest(array[1, 2, 4, 5, 7, 9]) n;
update app_users u set auth_user_id = pg_temp.zc_id('fr-auth-' || s.n)
  from unnest(array[1, 2, 4, 5, 7, 9]) s(n) where u.id = pg_temp.zc_id('user-' || s.n);
insert into _zc_r select 'oae-sens', pg_temp.fr_oae(9, true);
insert into _zc_r select 'oae-rf-all', pg_temp.fr_oae(9, false, 'card_attempt.release_failed');
insert into _zc_r select 'oae-rf-sens', pg_temp.fr_oae(9, true, 'card_attempt.release_failed');
select is((select array_agg(distinct e ->> 'action' order by e ->> 'action') from _zc_r r, jsonb_array_elements(r.r -> 'events') e
            where r.label = 'oae-sens' and e ->> 'action' like 'card_attempt.%'),
  array['card_attempt.denied', 'card_attempt.order_freed', 'card_attempt.provider_anomaly', 'card_attempt.recording_refused',
        'card_attempt.recording_resume_requested'],
  'FR-203 owner_audit_events(p_sensitive_only) as the owner JWT actor lists exactly provider_anomaly, recording_refused, order_freed, recording_resume_requested and denied of the card family');
select ok((select (r.r ->> 'ok')::boolean and not (r.r ->> 'has_more')::boolean from _zc_r r where r.label = 'oae-sens')
          and (select count(*) from _zc_r r, jsonb_array_elements(r.r -> 'events') e
                where r.label = 'oae-sens' and e ->> 'action' = 'card_attempt.provider_anomaly')
              = (select count(*) from _fr_aud where action = 'card_attempt.provider_anomaly'),
  'FR-204 ... every provider_anomaly row is listed (one page, nothing left over)');
select is_empty($$ select e ->> 'event_id' from _zc_r r, jsonb_array_elements(r.r -> 'events') e join _fr_allow a on a.action = e ->> 'action'
                    where r.label = 'oae-sens'
                      and (e ->> 'category' <> 'payments' or e -> 'reason' <> 'null'::jsonb
                           or not (array(select jsonb_object_keys(e -> 'new_values')) <@ a.keys)) $$,
  'FR-205 ... each listed card row is category payments, reason NULL, new_values inside its per-action allowlist');
select ok((select (r ->> 'count')::integer = 3 from _zc_r where label = 'oae-rf-all')
          and (select (r ->> 'count')::integer = 0 from _zc_r where label = 'oae-rf-sens'),
  'FR-206 card_attempt.release_failed is listed normally (all 3 rows) but is not sensitive (0 rows under p_sensitive_only)');

-- ===========================================================================
-- 11. owner_card_attempts: the DOMAIN 8.4 allowlist, one mode at a time.
-- ===========================================================================
create temp table _fr_hidden as
select distinct x.v from app.card_provider_attempts a,
  lateral (values (a.terminal_ref), (a.credential_ref), (a.provider_query_key), (a.provider_duplicate_key),
                  (a.provider_reference), (a.approval_number), (a.voucher_number), (a.deposit_id),
                  (a.confirmation_reference), (a.resolution_reference), (a.order_freed_note),
                  (a.incident_hold_reference)) x(v)
 where a.organization_id = pg_temp.zc_org() and x.v is not null;
select is((select count(*) from _fr_hidden where v in ('zc-term-live-1', 'zc-cred-live-1', 'zc-term-test-2', 'zc-cred-test-2',
            'ZCREF-777', 'APPR77', 'VCH77', 'DEP-77', 'zc-conf/ref-77', 'ZC001D manager note seventy-seven', 'zc-lres/ref-99',
            'zc-tres/ref-88', 'zc-hold/ref-66')), 13::bigint,
  'FR-207 harness: every hidden value class is present in the ledger (references, keys, provider reference / approval / voucher / deposit, free and resolution references, free note, hold reference)');
create temp table _fr_keys (mode text primary key, keys text[]);
insert into _fr_keys select 'live', array_agg(k order by k) from unnest(array[
  'id', 'local_operation_id', 'organization_id', 'restaurant_id', 'branch_id', 'device_id', 'order_id', 'mode', 'state',
  'classification', 'recorded', 'payment_id', 'reason', 'recoverable', 'amount_minor', 'currency_code', 'shift_id',
  'cash_drawer_session_id', 'initiated_by_employee_profile_id', 'initiated_by_membership_id', 'provider_approved_at',
  'card_last4', 'card_brand_code', 'approval_type', 'provider_return_code', 'provider_return_class', 'provider_status_code',
  'provider_anomaly_code', 'charge_may_exist', 'refusal_code', 'recording_refused_at', 'recording_resume_count',
  'recording_refusal_history', 'recording_resume_history', 'release_requested_at', 'released_at', 'last_lookup_at',
  'order_freed_at', 'order_freed_reason', 'confirmation_source', 'resolution', 'resolved_at', 'created_at', 'finished_at']) k;
insert into _fr_keys select 'test', (select array_agg(k order by k) from unnest(keys || array['retention_until', 'incident_hold_at']) k)
  from _fr_keys where mode = 'live';
insert into _zc_r select 'oca-owner', pg_temp.fr_oca(9);
insert into _zc_r select 'oca-test', pg_temp.fr_oca(9, 'test');
insert into _zc_r select 'oca-mgr', pg_temp.fr_oca(2);
insert into _zc_r select 'oca-acct', pg_temp.fr_oca(5, 'live');
insert into _zc_r select 'oca-kitchen', pg_temp.fr_oca(4);
insert into _zc_r select 'oca-cashier', pg_temp.fr_oca(1);
insert into _zc_r select 'oca-93', pg_temp.fr_oca(9, 'live', interval '93 days', interval '0 days');
select ok((select r ->> 'ok' = 'true' and r ->> 'mode' = 'live' and r ->> 'entity' = 'owner_card_attempts'
                  and (r ->> 'count')::integer = jsonb_array_length(r -> 'rows')
                  and (r ->> 'count')::integer = (select count(*) from app.card_provider_attempts a
                                                   where a.organization_id = pg_temp.zc_org() and a.mode = 'live')
                  and (select array_agg(k order by k) from jsonb_object_keys(r) k) = array['count', 'entity', 'mode', 'ok', 'rows']
             from _zc_r where label = 'oca-owner'),
  'FR-208 owner_card_attempts as org_owner (default mode) returns every LIVE attempt of the scope: {ok, entity, mode live, rows, count}');
select is_empty($$ select e ->> 'id' from _zc_r r, jsonb_array_elements(r.r -> 'rows') e where r.label = 'oca-owner' and e ->> 'mode' <> 'live' $$,
  'FR-209 ... LIVE rows only by default (no TEST row)');
select is_empty($$ select e ->> 'id' from _zc_r r, jsonb_array_elements(r.r -> 'rows') e, _fr_keys kk
                    where r.label = 'oca-owner' and kk.mode = 'live'
                      and (select array_agg(k order by k) from jsonb_object_keys(e) k) is distinct from kk.keys $$,
  'FR-210 ... every LIVE row has EXACTLY the 44 allowlist keys of DOMAIN 8.4 (no terminal / credential reference, key, provider reference, approval / voucher / deposit number, free / resolution reference or note)');
select is_empty($$ select h.v from _fr_hidden h, _zc_r r where r.label = 'oca-owner' and strpos(r.r::text, h.v) > 0 $$,
  'FR-211 ... and no hidden VALUE appears anywhere in the LIVE response text (references, keys, provider reference, approval / voucher / deposit, confirmation / resolution reference, free note)');
select ok((select r ->> 'ok' = 'true' and r ->> 'mode' = 'test'
                  and (r ->> 'count')::integer = (select count(*) from app.card_provider_attempts a
                                                   where a.organization_id = pg_temp.zc_org() and a.mode = 'test')
                  and (r ->> 'count')::integer = 3
                  and not exists (select 1 from jsonb_array_elements(r -> 'rows') e where e ->> 'mode' <> 'test')
             from _zc_r where label = 'oca-test'),
  'FR-212 p_mode test returns the TEST rows only (3)');
select is_empty($$ select e ->> 'id' from _zc_r r, jsonb_array_elements(r.r -> 'rows') e, _fr_keys kk
                    where r.label = 'oca-test' and kk.mode = 'test'
                      and (select array_agg(k order by k) from jsonb_object_keys(e) k) is distinct from kk.keys $$,
  'FR-213 ... each TEST row has EXACTLY the 44 keys plus retention_until and incident_hold_at');
select ok((select e ->> 'classification' = 'test_approved' and e ->> 'recorded' = 'false'
                  and e ->> 'incident_hold_at' is not null and e ->> 'retention_until' is not null
                  and e -> 'card_last4' = 'null'::jsonb and e -> 'order_id' = 'null'::jsonb
             from _zc_r r, jsonb_array_elements(r.r -> 'rows') e
            where r.label = 'oca-test' and e ->> 'local_operation_id' = pg_temp.zc_lop('fr-t1')),
  'FR-214 ... the held TEST approval projects test_approved, recorded false, its hold time and retention, no card field and no order');
select is_empty($$ select h.v from _fr_hidden h, _zc_r r where r.label = 'oca-test' and strpos(r.r::text, h.v) > 0 $$,
  'FR-215 ... and no hidden value (TEST references, keys, hold reference, closure reference) appears in the TEST response text');
select ok((select r ->> 'ok' = 'true' and r ->> 'count' = (select r2 ->> 'count' from _zc_r x(l2, r2) where x.l2 = 'oca-owner')
             from _zc_r where label = 'oca-mgr')
          and (select r ->> 'ok' = 'true' and r ->> 'count' = (select r2 ->> 'count' from _zc_r x(l2, r2) where x.l2 = 'oca-owner')
                 from _zc_r where label = 'oca-acct'),
  'FR-216 a branch manager and an accountant (read-only) read the same LIVE rows');
select ok((select r = '{"ok": false, "error": "permission_denied", "entity": "owner_card_attempts"}'::jsonb from _zc_r where label = 'oca-kitchen')
          and (select r = '{"ok": false, "error": "permission_denied", "entity": "owner_card_attempts"}'::jsonb from _zc_r where label = 'oca-cashier'),
  'FR-217 kitchen_staff and cashier are answered exactly {ok:false, error:permission_denied}');
select throws_ok($$ select pg_temp.fr_oca(7) $$, '42501', null, 'FR-218 a foreign-organization actor -> 42501');
select throws_ok($$ select pg_temp.fr_oca(0) $$, '42501', null, 'FR-219 an authenticated JWT with no linked app user -> 42501');
select throws_ok($$ select pg_temp.fr_oca(9, 'LIVE') $$, '22023', null, 'FR-220 p_mode LIVE (wrong case) -> 22023');
select throws_ok($$ select pg_temp.fr_oca(9, 'all') $$, '22023', null, 'FR-221 p_mode all -> 22023');
select throws_ok($$ select pg_temp.fr_oca(9, null) $$, '22023', null, 'FR-222 p_mode NULL -> 22023');
select throws_ok($$ select pg_temp.fr_oca(9, 'live', interval '94 days', interval '0 days') $$, '22023', null,
  'FR-223 a range over 93 days -> 22023');
select throws_ok($$ select pg_temp.fr_oca(9, 'live', interval '-1 day', interval '0 days') $$, '22023', null,
  'FR-224 an empty / inverted range (from >= to) -> 22023');
select is((select r ->> 'ok' from _zc_r where label = 'oca-93'), 'true', 'FR-225 exactly 93 days is accepted');
create function pg_temp.fr_oca_org(p_n integer) returns jsonb language sql as $$
  select pg_temp.fr_as(p_n, format(
    'select public.owner_card_attempts(%L::uuid, null, null, now() - interval ''1 day'', now() + interval ''1 day'')',
    pg_temp.zc_org())) $$;
insert into _zc_r select 'oca-org', pg_temp.fr_oca_org(9);
select ok((select r ->> 'ok' = 'true' and r ->> 'mode' = 'live'
                  and (r ->> 'count')::integer = (select count(*) from app.card_provider_attempts a
                                                   where a.organization_id = pg_temp.zc_org() and a.mode = 'live')
             from _zc_r where label = 'oca-org'),
  'FR-226 the org_owner may read the whole organization (NULL restaurant / branch): every LIVE row of the org');
select throws_ok($$ select pg_temp.fr_oca_org(2) $$, '42501', null,
  'FR-227 a branch manager asking for the whole organization (scope not covered) -> 42501');

-- ===========================================================================
-- 1 (end). Stored text is canonical: direct owner writes are refused by CHECK.
-- ===========================================================================
select throws_ok($$ insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode,
                      window_until, reason, operator_reference, actor_app_user_id, executor_principal)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), false, 'test', now() + interval '1 hour',
                      ' ZC001D leading space', 'zc001d-op/ref-9', pg_temp.zc_owner(), 'zc001d-fr') $$,
  '23514', 'new row for relation "card_payments_pilot_revisions" violates check constraint "card_pilot_revisions_reason"',
  'FR-228 a direct owner INSERT of a non-canonical reason (leading space) into card_payments_pilot_revisions -> CHECK 23514');
select throws_ok($$ insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode,
                      window_until, reason, operator_reference, actor_app_user_id, executor_principal)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), false, 'test', now() + interval '1 hour',
                      'ZC001D canonical reason', U&'zc001d-op/ref-9\3000', pg_temp.zc_owner(), 'zc001d-fr') $$,
  '23514', 'new row for relation "card_payments_pilot_revisions" violates check constraint "card_pilot_revisions_operator_reference"',
  'FR-229 a direct owner INSERT of a non-canonical operator_reference (trailing U+3000) -> CHECK 23514');
select throws_ok($$ update app.card_provider_attempts set provider_reference = ' ZCREF-778' where id = pg_temp.fr_rid('c_ok') $$,
  '23514', 'new row for relation "card_provider_attempts" violates check constraint "card_attempts_provider_fields"',
  'FR-230 a direct owner UPDATE writing a non-canonical provider_reference on the ledger -> CHECK 23514');
select throws_ok($$ update app.card_provider_attempts set provider_reference = repeat('7351', 4) where id = pg_temp.fr_rid('c_ok') $$,
  '23514', 'new row for relation "card_provider_attempts" violates check constraint "card_attempts_provider_fields"',
  'FR-231 a direct owner UPDATE writing a 16-digit provider_reference on the ledger -> CHECK 23514 (the rule is also the last boundary)');
select lives_ok($$ insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode,
                      window_until, reason, operator_reference, actor_app_user_id, executor_principal)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), false, 'test', now() + interval '1 hour',
                      'ZC001D canonical reason', 'zc001d-op/ref-9', pg_temp.zc_owner(), 'zc001d-fr') $$,
  'FR-232 ... the same direct INSERT in canonical form is accepted (the refusal is the canonical-form CHECK)');
-- An Arabic + Hebrew operator reason with U+061C and U+200F (and a trailing
-- ideographic space that the canonical trim removes) is stored canonical.
select is(app.set_card_payments_pilot(false, 'test', null, null, null,
            U&'\0625\0644\063A\0627\0621 \061C\0627\0644\0637\0644\0628 \05D1\05D9\05D8\05D5\05DC\200F\3000',
            'zc001d-op/ref-10', pg_temp.zc_owner()) ->> 'ok', 'true',
  'FR-233 the operator revision accepts an Arabic + Hebrew reason with U+061C / U+200F');
select is((select r.reason from app.card_payments_pilot_revisions r order by r.revision desc limit 1),
  U&'\0625\0644\063A\0627\0621 \061C\0627\0644\0637\0644\0628 \05D1\05D9\05D8\05D5\05DC\200F',
  'FR-234 ... and stores it in canonical form (U+3000 trimmed, U+061C / U+200F kept), which its CHECK accepts');
select pg_temp.fr_snap('end-operator');

select is((select count(*) from _fr_aud where k like 'pre:%') + (select count(*) from _fr_evt where k like 'pre:%'), 0::bigint,
  'FR-235 harness: every audit row and private event of this file was attributed to the call that wrote it');


-- ===========================================================================
-- 12. Review fix 12: the mask set is 39 code points (packet sec. 4.5: every
--     UCD 15.1 code point named BULLET except U+1F685, plus the ASCII tokens
--     and their compatibility / confusable forms). The 8 added code points in
--     the three shapes of a masked card number, as a reason and as an
--     order_freed_note.
-- ===========================================================================
create temp table _fr_mask8 (cp text primary key);
insert into _fr_mask8 values
  (U&'\204C'), (U&'\204D'), (U&'\25D8'), (U&'\29BE'), (U&'\29BF'), (U&'\2619'), (U&'\2765'), (U&'\2767');
create temp table _fr_m8v as
select m.cp, f.field, s.shape, s.val
  from _fr_mask8 m
 cross join (values ('reason'), ('order_freed_note')) f(field)
 cross join lateral (values ('7351 + mask x4 + 1234 (spaced)', '7351 ' || repeat(m.cp, 4) || ' 1234'),
                            ('mask x3 + 1234', repeat(m.cp, 3) || '1234'),
                            ('7351 + mask x3', '7351' || repeat(m.cp, 3))) s(shape, val);
select ok((select count(*) from _fr_m8v) = 48 and not exists (select cp from _fr_mask8 except select cp from _fr_mask),
  'FR-236 harness (review fix 12): 48 vectors = the 8 added mask code points (U+204C, U+204D, U+25D8, U+29BE, U+29BF, U+2619, U+2765, U+2767) x 3 shapes x 2 fields, and the 8 belong to the 39-point set of FR-16');
select is_empty($$ select format('%s / %s [%s] got=%s', v.field, v.shape, pg_temp.fr_hex(v.cp),
                                 coalesce(app.card_safe_text_failure(v.val, v.field), 'NULL'))
                     from _fr_m8v v where app.card_safe_text_failure(v.val, v.field) is distinct from 'masked_pattern' $$,
  'FR-237 review fix 12: each of U+204C, U+204D, U+25D8, U+29BE, U+29BF, U+2619, U+2765, U+2767 in 7351 + mask x4 + 1234 (spaced), mask x3 + 1234 and 7351 + mask x3 -> masked_pattern, as a reason AND as an order_freed_note (48 of 48)');
select is_empty($$ select format('%s / %s [%s]', v.field, v.shape, pg_temp.fr_hex(v.cp)) from _fr_m8v v
                    where app.card_safe_text_ok(v.val, v.field) is distinct from false $$,
  'FR-238 review fix 12: ... and app.card_safe_text_ok (the CHECK helper of the reason / order_freed_note columns) is false for each of the 48');
select is_empty($$ select format('%s / %s got=%s', f.field, s.shape, app.card_safe_text_failure(s.val, f.field))
                     from (values ('reason'), ('order_freed_note')) f(field)
                    cross join (values ('7351 + x4 + 1234 (spaced)', '7351 ' || repeat(U&'\+01F685', 4) || ' 1234'),
                                       ('x3 + 1234', repeat(U&'\+01F685', 3) || '1234'),
                                       ('7351 + x3', '7351' || repeat(U&'\+01F685', 3))) s(shape, val)
                    where app.card_safe_text_failure(s.val, f.field) is not null $$,
  'FR-239 packet sec. 4.5: U+1F685 (HIGH-SPEED TRAIN WITH BULLET NOSE, the one BULLET name left out) is not a mask code point: the same three shapes pass as a reason and as an order_freed_note');
select results_eq($$ select m.n::integer, strpos(m.cls[1], '-') > 0,
                            (select array_agg(t[1] collate "C" order by t[1] collate "C")
                               from regexp_matches(m.cls[1], '\\u([0-9A-F]{4})', 'g') t)
                       from regexp_matches((select p.prosrc from pg_proc p where p.oid = 'app.card_safe_text_failure(text,text)'::regprocedure),
                                           '\[(\\u0023\\u002A[^]]*)\]', 'g') with ordinality m(cls, n)
                      order by 1 $$,
                  $$ select n, false,
                            (select array_agg(upper(lpad(to_hex(ascii(cp)), 4, '0')) collate "C"
                                              order by upper(lpad(to_hex(ascii(cp)), 4, '0')) collate "C") from _fr_mask)
                       from generate_series(1, 3) n $$,
  'FR-240 review fix 12: each of the three mask classes of the masked-pattern regex in app.card_safe_text_failure (Nd4 + mask+ + Nd4 | mask3 + Nd4 | Nd4 + mask3) lists exactly the 39 code points of the set under test, with no range (no 40th mask code point)');

-- ===========================================================================
-- 13. Review fix 13: the linear length bound of app.card_safe_text_failure
--     (after the raw control_character / charset checks and before NFKC, a
--     Space_Separator-trimmed raw length above 4 x the field maximum answers
--     length; the largest canonical decomposition in UCD 15.1 is 4).
-- ===========================================================================
select is(jsonb_build_object('raw_code_points', char_length(repeat(U&'\03B1\0313\0300\0345', 200)),
                             'failure', app.card_safe_text_failure(repeat(U&'\03B1\0313\0300\0345', 200), 'reason')),
          '{"raw_code_points": 800, "failure": null}'::jsonb,
  'FR-241 review fix 13: a reason of 200 x U+03B1 U+0313 U+0300 U+0345 (800 raw code points = exactly 4 x 200) passes the bound and every rule');
select is(app.card_text_canonical(repeat(U&'\03B1\0313\0300\0345', 200)), repeat(U&'\1F82', 200),
  'FR-242 review fix 13: ... and canonicalizes to 200 x U+1F82 (200 code points)');
select is(app.card_safe_text_failure(repeat(U&'\03B1\0313\0300\0345', 200) || 'a', 'reason'), 'length',
  'FR-243 review fix 13: the same reason with one more a (801 raw code points) -> length');
select is(app.card_safe_text_failure(repeat(' ', 500) || repeat(U&'\03B1\0313\0300\0345', 200) || repeat(U&'\3000', 500), 'reason'),
          null::text,
  'FR-244 review fix 13: the bound counts the Space_Separator-TRIMMED raw length: the 800-code-point reason inside 500 spaces and 500 U+3000 (1800 raw) still passes');
select results_eq($$ select x.n, x.f, x.c, app.card_safe_text_failure(x.v, x.f) from (values
                       (1, 'approval_number', '65 raw = 4 x 16 + 1', repeat('A', 65)),
                       (2, 'approval_number', '65 trimmed inside U+3000 / space', U&'\3000' || repeat('A', 65) || ' '),
                       (3, 'approval_number', '6 trimmed inside 200 Zs (206 raw)', repeat(U&'\3000', 100) || 'APPR77' || repeat(' ', 100)),
                       (4, 'operator_reference', '257 raw = 4 x 64 + 1', repeat('r', 257)),
                       (5, 'operator_reference', '257 trimmed inside NBSP / U+2007', U&'\00A0' || repeat('r', 257) || U&'\2007'),
                       (6, 'operator_reference', '17 trimmed inside 600 Zs (617 raw)',
                        repeat(U&'\00A0', 300) || 'zc001d-op/ref.1:a' || repeat(U&'\2007', 300))) x(n, f, c, v)
                      order by x.n $$,
                  $$ values (1, 'approval_number', '65 raw = 4 x 16 + 1', 'length'),
                            (2, 'approval_number', '65 trimmed inside U+3000 / space', 'length'),
                            (3, 'approval_number', '6 trimmed inside 200 Zs (206 raw)', null::text),
                            (4, 'operator_reference', '257 raw = 4 x 64 + 1', 'length'),
                            (5, 'operator_reference', '257 trimmed inside NBSP / U+2007', 'length'),
                            (6, 'operator_reference', '17 trimmed inside 600 Zs (617 raw)', null::text) $$,
  'FR-245 review fix 13: a 16-max field (approval_number) and a 64-max field (operator_reference): exactly 4 x max + 1 trimmed raw code points -> length, also inside edge Space_Separators; edge Space_Separators never count toward the bound (a valid value inside 200 / 600 of them passes)');
-- One timed call: the clock_timestamp() delta around exactly this rule evaluation.
create function pg_temp.fr_timed(p_v text, p_field text)
returns table (failure text, raw_code_points integer, elapsed_ms numeric) language plpgsql as $$
declare
  t0 timestamptz;
  v text;
begin
  t0 := clock_timestamp();
  v := app.card_safe_text_failure(p_v, p_field);
  return query select v, char_length(p_v), (extract(epoch from clock_timestamp() - t0) * 1000)::numeric;
end $$;
create temp table _fr_timed as
select * from pg_temp.fr_timed('a' || repeat(U&'\0301', 32000) || repeat(U&'\0316', 32000), 'reason');
select is((select jsonb_build_object('failure', t.failure, 'raw_code_points', t.raw_code_points) from _fr_timed t),
          '{"failure": "length", "raw_code_points": 64001}'::jsonb,
  'FR-246 review fix 13: a reason of a + 32000 x U+0301 + 32000 x U+0316 (64001 code points, whose NFKC would reorder 32000 marks) -> length');
select cmp_ok((select t.elapsed_ms from _fr_timed t), '<', 2000::numeric,
  'FR-247 review fix 13: ... answered in under 2 s (clock_timestamp delta; about 21 s before the bound)');
select is(jsonb_build_object('raw_code_points', char_length(repeat('a', 5000) || U&'\200B' || repeat('a', 4999)),
                             'failure', app.card_safe_text_failure(repeat('a', 5000) || U&'\200B' || repeat('a', 4999), 'reason')),
          '{"raw_code_points": 10000, "failure": "control_character"}'::jsonb,
  'FR-248 review fix 13: a 10000-character reason containing U+200B -> control_character (the raw control check still precedes the bound)');
select is(jsonb_build_object('raw_code_points', char_length(repeat('a', 9999) || U&'\E000'),
                             'failure', app.card_safe_text_failure(repeat('a', 9999) || U&'\E000', 'reason')),
          '{"raw_code_points": 10000, "failure": "charset"}'::jsonb,
  'FR-249 review fix 13: a 10000-character reason ending in private-use U+E000 -> charset (the raw charset check still precedes the bound)');

-- ===========================================================================
-- 14. Review fix 14: app.card_text_absent(v) = (app.card_text_canonical(v) IS
--     NULL), at linear cost; a finish provider field holding only
--     Space_Separators is absent (stored NULL, no event).
-- ===========================================================================
create temp table _fr_abs (n integer primary key, label text not null, v text, want boolean not null);
insert into _fr_abs values (1, 'NULL', null, true), (2, 'empty string', '', true);
insert into _fr_abs
select 2 + u.o::integer, 'Zs U+' || upper(lpad(to_hex(ascii(u.z)), 4, '0')), u.z, true
  from unnest(array[U&'\0020', U&'\00A0', U&'\1680', U&'\2000', U&'\2001', U&'\2002', U&'\2003', U&'\2004', U&'\2005',
                    U&'\2006', U&'\2007', U&'\2008', U&'\2009', U&'\200A', U&'\202F', U&'\205F', U&'\3000']) with ordinality u(z, o);
insert into _fr_abs values
  (20, 'a mixed Zs run', U&'\3000\00A0\0020\1680\2007\202F\205F\2000\3000', true),
  (21, 'U+00A8 (NFKC: U+0020 U+0308)', U&'\00A8', false),
  (22, 'U+3164 (NFKC: U+1160)', U&'\3164', false),
  (23, 'U+200B (Cf, not Zs)', U&'\200B', false),
  (24, 'a', 'a', false);
select results_eq($$ select label, app.card_text_absent(v), app.card_text_canonical(v) is null from _fr_abs order by n $$,
                  $$ select label, want, want from _fr_abs order by n $$,
  'FR-250 review fix 14: app.card_text_absent(v) = (app.card_text_canonical(v) IS NULL) over 24 vectors: NULL, empty, each of the 17 Space_Separators and a mixed run of them (true); U+00A8, U+3164, U+200B and a (false)');
select is((select count(*) from _fr_abs), 24::bigint, 'FR-251 harness: the 24 absent-test vectors are present (2 + 17 + 1 + 4)');

-- ---------------------------------------------------------------------------
-- LIVE claims for sections 14-16. FR-233 left a disabled TEST revision, so a
-- new enabled LIVE revision is recorded; the LIVE binding of d1 (FR-54) is
-- still enabled.
-- ---------------------------------------------------------------------------
select is(pg_temp.zc_pilot('live') ->> 'mode', 'live', 'FR-252 setup: a new enabled LIVE revision is recorded');
select pg_temp.fr_snap('x-pilot');
select is(pg_temp.fr_live(array['xa', 'xc', 'xs01', 'xs02', 'xs03', 'xs04', 'xs05', 'xs06', 'xs07', 'xs08', 'xs09', 'xs10', 'xv']), 13,
  'FR-253 setup: 13 more LIVE claims created on d1 (claim_created = true)');
select pg_temp.fr_snap('x-claims');
select ok((select count(*) = 13 and bool_and(action = 'card_attempt.started') from _fr_aud where k = 'x-claims')
          and not exists (select 1 from _fr_evt where k = 'x-claims'),
  'FR-254 setup: ... exactly 13 card_attempt.started and no private event');

select is(pg_temp.fr_do('xa-1', 'xa', 'commit', 'approved',
            pg_temp.zc_approved_fields() || (select jsonb_object_agg(f, U&'\3000\00A0') from unnest(array[
              'provider_reference', 'approval_number', 'voucher_number', 'deposit_id', 'card_last4', 'card_brand_code',
              'pan_entry_mode', 'payment_method_code', 'provider_saved_at', 'provider_amount', 'provider_currency',
              'tip_amount']) f)),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=-',
  'FR-255 review fix 14: a commit approval whose 12 provider fields not required for a commit approval (8 card / reference fields, provider_saved_at, provider_amount, provider_currency, tip_amount) each hold only Space_Separators (U+3000 U+00A0) -> approved with no field-drop event (each field is absent)');
select is((select jsonb_build_object('provider_reference', a.provider_reference, 'approval_number', a.approval_number,
            'voucher_number', a.voucher_number, 'deposit_id', a.deposit_id, 'card_last4', a.card_last4,
            'card_brand_code', a.card_brand_code, 'pan_entry_mode', a.pan_entry_mode,
            'payment_method_code', a.payment_method_code, 'provider_saved_at', a.provider_saved_at,
            'approval_type', a.approval_type,
            'events', (select count(*) from app.card_provider_private_events e where e.attempt_row_id = a.id))
             from app.card_provider_attempts a where a.id = pg_temp.fr_rid('xa')),
  '{"provider_reference": null, "approval_number": null, "voucher_number": null, "deposit_id": null, "card_last4": null,
    "card_brand_code": null, "pan_entry_mode": null, "payment_method_code": null, "provider_saved_at": null,
    "approval_type": "approved", "events": 0}'::jsonb,
  'FR-256 review fix 14: ... the nine stored provider columns are NULL (approval_type approved) and the attempt holds no private event');

-- ===========================================================================
-- 15. Review fix 15: provider_return_class. An empty / Space_Separator-only
--     string is absent (the stored class is kept); any other non-member or
--     non-string value stores unclassified. Informational only: no event, no
--     audit, never a state change.
-- ===========================================================================
select pg_temp.fr_fin('xc-1', 'xc', 'commit', 'unknown', '{"provider_return_class": "declined"}'::jsonb);
select pg_temp.fr_fin('xc-2', 'xc', 'lookup', 'not_found', '{"provider_return_class": ""}'::jsonb);
select pg_temp.fr_fin('xc-3', 'xc', 'lookup', 'not_found', jsonb_build_object('provider_return_class', U&'\3000'));
select pg_temp.fr_fin('xc-4', 'xc', 'lookup', 'not_found', jsonb_build_object('provider_return_class', U&'\00A0\2007 \3000\205F'));
select pg_temp.fr_fin('xc-5', 'xc', 'lookup', 'not_found', '{"provider_return_class": "bogus"}'::jsonb);
select pg_temp.fr_fin('xc-6', 'xc', 'lookup', 'not_found', '{"provider_return_class": "declined"}'::jsonb);
select pg_temp.fr_fin('xc-7', 'xc', 'lookup', 'not_found', '{"provider_return_class": 5}'::jsonb);
select results_eq($$ select k, before_row ->> 'provider_return_class', after_row ->> 'provider_return_class', pg_temp.fr_sig(k)
                       from _fr_call where k like 'xc-_' order by k $$,
  $$ values ('xc-1', null::text, 'declined', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-'),
            ('xc-2', 'declined', 'declined', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xc-3', 'declined', 'declined', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xc-4', 'declined', 'declined', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xc-5', 'declined', 'unclassified', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xc-6', 'unclassified', 'declined', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xc-7', 'declined', 'unclassified', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-') $$,
  'FR-257 review fix 15: after a finish stored declined, a later finish with an empty string, U+3000 or a mixed Space_Separator run keeps declined (absent); bogus stores unclassified; declined again, then the JSON number 5 stores unclassified; no class value writes an event or audit');

-- ===========================================================================
-- 16. Review fix 16: provider_saved_at must match
--     ^YYYY-MM-DD[T ]HH:MM:SS(.f{1,6})?(Z|+-HH(:?MM)?)$ AND be a valid
--     timestamptz; otherwise it is dropped (NULL) with rule format, one
--     field-drop event per (attempt, field, rule) (M1).
-- ===========================================================================
create temp table _fr_sv (k text primary key, c text not null, val text not null);
insert into _fr_sv values
  ('xs01-1', 'xs01', 'now'), ('xs02-1', 'xs02', 'today'), ('xs03-1', 'xs03', 'tomorrow'), ('xs04-1', 'xs04', 'epoch'),
  ('xs05-1', 'xs05', 'infinity'), ('xs06-1', 'xs06', '-infinity'), ('xs07-1', 'xs07', '2026-10-24 10:00:00'),
  ('xs08-1', 'xs08', '2026-10-24'), ('xs09-1', 'xs09', '24/10/2026'), ('xs10-1', 'xs10', ' 2026-10-24T10:00:00Z');
select count(pg_temp.fr_fin(s.k, s.c, 'commit', 'unknown', jsonb_build_object('provider_saved_at', s.val))) from _fr_sv s;
select results_eq($$ select s.k, s.val, pg_temp.fr_sig(s.k), c.after_row ->> 'provider_saved_at'
                       from _fr_sv s join _fr_call c on c.k = s.k order by s.k $$,
                  $$ select k, val, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_saved_at/format/commit',
                            null::text
                       from _fr_sv order by k $$,
  'FR-258 review fix 16: provider_saved_at now, today, tomorrow, epoch, infinity, -infinity, 2026-10-24 10:00:00 (no zone), 2026-10-24 (date only), 24/10/2026 and a leading-space 2026-10-24T10:00:00Z -> stored NULL with exactly one field-drop event provider_saved_at/format/commit each');
select is_empty($$ select e.k from _fr_evt e join _fr_sv s on s.k = e.k
                    where e.action <> 'security.card_provider_field_dropped'
                       or e.detail <> '{"field": "provider_saved_at", "rule": "format", "source": "commit"}'::jsonb
                       or e.attempt_row_id is distinct from pg_temp.fr_rid(s.c) or e.mode <> 'live'
                       or e.organization_id <> pg_temp.zc_org() or e.device_id <> pg_temp.zc_id('device-1')
                       or e.actor_kind <> 'adapter' or e.actor_reference <> 'card_adapter' $$,
  'FR-259 review fix 16: ... each event is exactly security.card_provider_field_dropped {field: provider_saved_at, rule: format, source: commit} on its own LIVE attempt row (pilot organization, device d1, actor adapter / card_adapter)');
select pg_temp.fr_fin('xs01-2', 'xs01', 'lookup', 'not_found', '{"provider_saved_at": "epoch"}'::jsonb);
select pg_temp.fr_fin('xs01-3', 'xs01', 'lookup', 'pending', '{"provider_saved_at": "2026-10-24T10:00:00"}'::jsonb);
select results_eq($$ select k, pg_temp.fr_sig(k), after_row ->> 'provider_saved_at' from _fr_call where k in ('xs01-2', 'xs01-3') order by k $$,
  $$ values ('xs01-2', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', null::text),
            ('xs01-3', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', null::text) $$,
  'FR-260 review fix 16 + M1: two more format failures on an attempt that already holds its provider_saved_at/format event (lookup epoch, lookup zone-less 2026-10-24T10:00:00) write no second event and store nothing');
select results_eq($$ select s.c, count(e.id)::integer from _fr_sv s
                       left join app.card_provider_private_events e
                         on e.attempt_row_id = pg_temp.fr_rid(s.c) and e.action = 'security.card_provider_field_dropped'
                        and e.detail ->> 'field' = 'provider_saved_at' and e.detail ->> 'rule' = 'format'
                      group by s.c order by s.c $$,
                  $$ select c, 1 from _fr_sv order by c $$,
  'FR-261 review fix 16 + M1: exactly one field-drop event per (attempt, provider_saved_at, format) on each of the ten attempts');
select pg_temp.fr_fin('xv-1', 'xv', 'commit', 'unknown', '{"provider_saved_at": "2026-10-24T10:00:00Z"}'::jsonb);
select pg_temp.fr_fin('xv-2', 'xv', 'lookup', 'not_found', '{"provider_saved_at": "2026-10-24T10:00:00.123456+03:00"}'::jsonb);
select pg_temp.fr_fin('xv-3', 'xv', 'lookup', 'not_found', '{"provider_saved_at": "2026-10-24 10:00:00+0300"}'::jsonb);
select pg_temp.fr_fin('xv-4', 'xv', 'lookup', 'not_found', '{"provider_saved_at": "2026-10-24T10:00:00-05"}'::jsonb);
select pg_temp.fr_fin('xv-5', 'xv', 'lookup', 'not_found', '{"provider_saved_at": "now"}'::jsonb);
select results_eq($$ select k, (after_row ->> 'provider_saved_at')::timestamptz, pg_temp.fr_sig(k) from _fr_call where k like 'xv-_' order by k $$,
  $$ values ('xv-1', '2026-10-24T10:00:00Z'::timestamptz, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-'),
            ('xv-2', '2026-10-24T07:00:00.123456Z'::timestamptz, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xv-3', '2026-10-24T07:00:00Z'::timestamptz, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xv-4', '2026-10-24T15:00:00Z'::timestamptz, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-'),
            ('xv-5', '2026-10-24T15:00:00Z'::timestamptz, 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=provider_saved_at/format/lookup') $$,
  'FR-262 review fix 16: 2026-10-24T10:00:00Z, 2026-10-24T10:00:00.123456+03:00, 2026-10-24 10:00:00+0300 and 2026-10-24T10:00:00-05 are each stored as that instant (10:00, 07:00:00.123456, 07:00, 15:00 UTC) with no event; a later now is dropped with its format event and leaves the stored instant');

-- ===========================================================================
-- 17. Review fix 17: the card_last4 clause of the ledger CHECK also calls
--     app.card_safe_text_ok.
-- ===========================================================================
select ok((select c.convalidated
                  and strpos(pg_get_constraintdef(c.oid),
                             '((card_last4 IS NULL) OR ((card_last4 ~ ''^[0-9]{4}$''::text) AND app.card_safe_text_ok(card_last4, ''card_last4''::text)))') > 0
             from pg_constraint c
            where c.conrelid = 'app.card_provider_attempts'::regclass and c.conname = 'card_attempts_provider_fields'),
  'FR-263 review fix 17: pg_get_constraintdef(card_attempts_provider_fields) holds ((card_last4 IS NULL) OR ((card_last4 ~ ''^[0-9]{4}$''::text) AND app.card_safe_text_ok(card_last4, ''card_last4''::text))) and the CHECK is validated');

-- ===========================================================================
-- 18. API sec. 4.55.10 owner read, "platform support mode denied"
--     (TESTING_STRATEGY:173 "support mode denied"): a platform admin holding
--     an ACTIVE support session on the pilot organization (the setup of review
--     probe r6_tests/p5_body.sql) is refused in live and in test mode.
-- ===========================================================================
insert into auth.users (id, email) values (pg_temp.zc_id('fr-auth-99'), 'zc001d-fr-support-99@example.test');
insert into app_users (id, email, auth_user_id)
values (pg_temp.zc_id('fr-sup-user'), 'zc001d-fr-support-99@example.test', pg_temp.zc_id('fr-auth-99'));
insert into public.platform_admin_grants (app_user_id, status, granted_by)
values (pg_temp.zc_id('fr-sup-user'), 'active', pg_temp.zc_owner());
insert into public.platform_support_sessions (id, platform_admin_app_user_id, target_organization_id, reason, status,
                                              expires_at, token_hash, token_consumed_at)
values (pg_temp.zc_id('fr-sup-session'), pg_temp.zc_id('fr-sup-user'), pg_temp.zc_org(), 'ZC001D synthetic support read',
        'active', now() + interval '10 minutes', 'zc001d-fr-support-hash-99', now());
create function pg_temp.fr_sup_state() returns jsonb language plpgsql as $$
declare
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.zc_id('fr-auth-99')::text, true);
  v := jsonb_build_object(
    'app_user', app.current_app_user_id() is not distinct from pg_temp.zc_id('fr-sup-user'),
    'support_session', app.current_support_session() is not distinct from pg_temp.zc_id('fr-sup-session'),
    'read_rank', app.actor_read_rank_in_scope(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch()),
    'member_rank', app.actor_rank_in_scope(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch()),
    'platform_admin', exists (select 1 from public.platform_admin_grants g
                               where g.app_user_id = pg_temp.zc_id('fr-sup-user') and g.status = 'active'),
    'memberships', (select count(*) from public.memberships m where m.app_user_id = pg_temp.zc_id('fr-sup-user')));
  perform set_config('request.jwt.claim.sub', v_sub, true);
  return v;
end $$;
select is(pg_temp.fr_sup_state(),
          jsonb_build_object('app_user', true, 'support_session', true, 'read_rank', app.role_rank('org_owner'),
                             'member_rank', 0, 'platform_admin', true, 'memberships', 0),
  'FR-264 setup: the JWT resolves to a platform admin (active grant, no membership) whose ACTIVE support session on the pilot organization gives owner read rank through the support-aware app.actor_read_rank_in_scope (member rank 0)');
select pg_temp.fr_snap('x-sup-setup');
select throws_ok($$ select pg_temp.fr_oca(99) $$, '42501',
  'owner_card_attempts: caller has no active membership covering the requested scope',
  'FR-265 owner_card_attempts under platform support mode (default mode = live) -> 42501 (no membership covering the scope)');
select throws_ok($$ select pg_temp.fr_oca(99, 'live') $$, '42501',
  'owner_card_attempts: caller has no active membership covering the requested scope',
  'FR-266 owner_card_attempts under platform support mode, p_mode live -> 42501');
select throws_ok($$ select pg_temp.fr_oca(99, 'test') $$, '42501',
  'owner_card_attempts: caller has no active membership covering the requested scope',
  'FR-267 owner_card_attempts under platform support mode, p_mode test -> 42501');
select throws_ok($$ select pg_temp.fr_oca_org(99) $$, '42501',
  'owner_card_attempts: caller has no active membership covering the requested scope',
  'FR-268 owner_card_attempts under platform support mode for the whole organization (NULL restaurant / branch) -> 42501');
select is(pg_temp.fr_snap('x-sup'), 0, 'FR-269 ... the four refused reads write no audit row and no private event');

-- ===========================================================================
-- 19. Review fix 4: a finish reaching a resolved attempt. A lookup that got no
--     reply (failed) writes no security.card_resolution_contradicted; every
--     other outcome writes exactly one; the resolved row never changes.
-- ===========================================================================
create function pg_temp.fr_contra(p_k text) returns text language sql stable as $$
  select concat_ws(' | ', pg_temp.fr_sig(c.k), 'unchanged=' || (c.after_row = c.before_row)::text,
    'exact_events=' || (select count(*) from _fr_evt e
                         where e.k = c.k and e.action = 'security.card_resolution_contradicted'
                           and e.detail = jsonb_build_object('source', c.source, 'outcome', c.outcome)
                           and e.attempt_row_id = (c.before_row ->> 'id')::uuid and e.mode = (c.before_row ->> 'mode')
                           and e.organization_id = (c.before_row ->> 'organization_id')::uuid
                           and e.restaurant_id = (c.before_row ->> 'restaurant_id')::uuid
                           and e.branch_id = (c.before_row ->> 'branch_id')::uuid
                           and e.device_id = (c.before_row ->> 'device_id')::uuid
                           and e.actor_kind = 'adapter' and e.actor_reference = 'card_adapter')::text)
    from _fr_call c where c.k = p_k $$;
select pg_temp.fr_fin('ro-x01', 'ro', 'lookup', 'failed', '{}'::jsonb, 'auto');
select is(pg_temp.fr_contra('ro-x01'),
  'state=unknown | class=resolved | anomaly=amount_mismatch | charge=true | audit=- | events=- | unchanged=true | exact_events=0',
  'FR-270 review fix 4: a lookup failed (no provider reply) on the resolved LIVE attempt writes no security.card_resolution_contradicted and no audit, the row unchanged');
select ok((select (after_row -> 'last_lookup_at') = (before_row -> 'last_lookup_at')
                  and (after_row -> 'auto_poll_count') = (before_row -> 'auto_poll_count') from _fr_call where k = 'ro-x01')
          and (select (r - 'server_ts') = jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('fr-ro'), 'state', 'unknown',
                        'classification', 'resolved', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
                        'provider_return_code', 0, 'resolution', 'provider_voided')
                 from _zc_r where label = 'ro-x01'),
  'FR-271 review fix 4: ... no last_lookup_at stamp, no auto_poll_count (although poll auto), and the call returns exactly the resolved envelope');
select pg_temp.fr_fin('ro-x02', 'ro', 'lookup', 'pending');
select pg_temp.fr_fin('ro-x03', 'ro', 'lookup', 'approved', pg_temp.fr_ex(), 'auto');
select results_eq($$ select k, pg_temp.fr_contra(k) from _fr_call where k in ('ro-x02', 'ro-x03') order by k $$,
  $$ values ('ro-x02', 'state=unknown | class=resolved | anomaly=amount_mismatch | charge=true | audit=- | events=security.card_resolution_contradicted | unchanged=true | exact_events=1'),
            ('ro-x03', 'state=unknown | class=resolved | anomaly=amount_mismatch | charge=true | audit=- | events=security.card_resolution_contradicted | unchanged=true | exact_events=1') $$,
  'FR-272 review fix 4: a lookup pending and a lookup approved on the resolved LIVE attempt each write exactly one security.card_resolution_contradicted {source: lookup, outcome} (row scope and mode, actor adapter / card_adapter), no audit, the row unchanged');
select pg_temp.fr_fin('ro-x04', 'ro', 'lookup', 'not_found');
select pg_temp.fr_fin('ro-x05', 'ro', 'lookup', 'declined', '{"approval_type": "declined"}'::jsonb);
select pg_temp.fr_fin('ro-x06', 'ro', 'lookup', 'anomaly', '{"anomaly_code": "refunded"}'::jsonb);
select pg_temp.fr_fin('ro-x07', 'ro', 'commit', 'approved', pg_temp.zc_approved_fields());
select pg_temp.fr_fin('ro-x08', 'ro', 'commit', 'declined', '{"approval_type": "declined"}'::jsonb);
select pg_temp.fr_fin('ro-x09', 'ro', 'commit', 'unknown');
select pg_temp.fr_fin('ro-x10', 'ro', 'commit', 'anomaly', '{"anomaly_code": "voided"}'::jsonb);
select pg_temp.fr_fin('ro-x11', 'ro', 'release', 'released');
select pg_temp.fr_fin('ro-x12', 'ro', 'release', 'release_failed');
select results_eq($$ select k, pg_temp.fr_contra(k) from _fr_call
                      where k in ('ro-x04', 'ro-x05', 'ro-x06', 'ro-x07', 'ro-x08', 'ro-x09', 'ro-x10', 'ro-x11', 'ro-x12') order by k $$,
                  $$ select 'ro-x' || lpad(n::text, 2, '0'),
                            'state=unknown | class=resolved | anomaly=amount_mismatch | charge=true | audit=- | events=security.card_resolution_contradicted | unchanged=true | exact_events=1'
                       from generate_series(4, 12) n order by 1 $$,
  'FR-273 review fix 4: every other outcome still writes exactly one (lookup not_found / declined / anomaly; commit approved / declined / unknown / anomaly; release released / release_failed), each with its own {source, outcome}, no audit, the row unchanged');
select pg_temp.fr_fin('t3-x1', 't3', 'lookup', 'failed');
select pg_temp.fr_fin('t3-x2', 't3', 'lookup', 'pending');
select results_eq($$ select k, pg_temp.fr_contra(k) from _fr_call where k in ('t3-x1', 't3-x2') order by k $$,
  $$ values ('t3-x1', 'state=unknown | class=test_unknown | anomaly=- | charge=false | audit=- | events=- | unchanged=true | exact_events=0'),
            ('t3-x2', 'state=unknown | class=test_unknown | anomaly=- | charge=false | audit=- | events=security.card_resolution_contradicted | unchanged=true | exact_events=1') $$,
  'FR-274 review fix 4: on the resolved TEST attempt (test_closed) a lookup failed writes nothing and a lookup pending writes exactly one security.card_resolution_contradicted (mode test, row scope); no audit, the row unchanged');
select is((select count(*) from _fr_evt e where e.k = 't3-x2' and e.mode = 'test' and e.retention_until is not null), 1::bigint,
  'FR-275 review fix 4: ... the TEST contradiction event keeps a retention_until (TEST retention)');

select is((select count(*) from _fr_aud where k like 'pre:%') + (select count(*) from _fr_evt where k like 'pre:%'), 0::bigint,
  'FR-276 harness: every audit row and private event of sections 12-19 too was attributed to the call that wrote it');

-- ===========================================================================
-- 20. Review fix 23: the provider_saved_at grammar is
--     ^YYYY-MM-DD[Tt ]HH:MM:SS([.]f{1,9})?([Zz]|[+-]HH(:?MM)?)$ (up to nine
--     fraction digits, rounded to microseconds; a lowercase t / z accepted)
--     PLUS pg_input_is_valid(v, 'timestamptz'); any other value is dropped
--     (NULL) with rule format, one field-drop event per (attempt, field, rule)
--     (M1). Each vector runs on its own fresh LIVE attempt of d1.
-- ===========================================================================
select is(pg_temp.fr_live(array['yt01', 'yt02', 'yt03', 'yt04', 'yt05', 'yt06', 'yt07', 'yt08', 'yt09', 'yr1', 'yr2']), 11,
  'FR-277 setup: 11 more LIVE claims created on d1 for sections 20-21 (claim_created = true; the LIVE revision of FR-252 and the d1 LIVE binding are still enabled)');
select pg_temp.fr_snap('y-claims');
select ok((select count(*) = 11 and bool_and(action = 'card_attempt.started') from _fr_aud where k = 'y-claims')
          and not exists (select 1 from _fr_evt where k = 'y-claims'),
  'FR-278 setup: ... exactly 11 card_attempt.started and no private event');
create temp table _fr_sv7 (k text primary key, c text not null, val text not null, want timestamptz);
insert into _fr_sv7 values
  ('yt01-1', 'yt01', '2026-10-24T10:00:00.1234567+03:00', '2026-10-24T07:00:00.123457Z'),
  ('yt02-1', 'yt02', '2026-10-24T10:00:00.123456789Z', '2026-10-24T10:00:00.123457Z'),
  ('yt03-1', 'yt03', '2026-10-24t10:00:00z', '2026-10-24T10:00:00Z'),
  ('yt04-1', 'yt04', '2026-10-24T10:00:00.5z', '2026-10-24T10:00:00.5Z'),
  ('yt05-1', 'yt05', '2026-10-24T10:00:00.9999996Z', '2026-10-24T10:00:01Z'),
  ('yt06-1', 'yt06', '2026-10-24T10:00:00.1234567890Z', null),
  ('yt07-1', 'yt07', '2026-10-24T10:00:00.Z', null),
  ('yt08-1', 'yt08', '2026-02-30T10:00:00Z', null),
  ('yt09-1', 'yt09', '2026-10-24T10:00:00+16:00', null);
select count(pg_temp.fr_fin(s.k, s.c, 'commit', 'unknown', jsonb_build_object('provider_saved_at', s.val))) from _fr_sv7 s;
select results_eq($$ select s.k, s.val, pg_temp.fr_sig(s.k), c.before_row ->> 'provider_saved_at',
                            (c.after_row ->> 'provider_saved_at')::timestamptz
                       from _fr_sv7 s join _fr_call c on c.k = s.k where s.want is not null order by s.k $$,
                  $$ values
                       ('yt01-1', '2026-10-24T10:00:00.1234567+03:00', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-', null::text, '2026-10-24T07:00:00.123457Z'::timestamptz),
                       ('yt02-1', '2026-10-24T10:00:00.123456789Z', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-', null::text, '2026-10-24T10:00:00.123457Z'::timestamptz),
                       ('yt03-1', '2026-10-24t10:00:00z', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-', null::text, '2026-10-24T10:00:00Z'::timestamptz),
                       ('yt04-1', '2026-10-24T10:00:00.5z', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-', null::text, '2026-10-24T10:00:00.5Z'::timestamptz),
                       ('yt05-1', '2026-10-24T10:00:00.9999996Z', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-', null::text, '2026-10-24T10:00:01Z'::timestamptz) $$,
  'FR-279 review fix 23: provider_saved_at 2026-10-24T10:00:00.1234567+03:00 (7 fraction digits), 2026-10-24T10:00:00.123456789Z (9), 2026-10-24t10:00:00z (lowercase t and z), 2026-10-24T10:00:00.5z and 2026-10-24T10:00:00.9999996Z are each stored on a fresh attempt (NULL before) as the instant rounded to microseconds (07:00:00.123457, 10:00:00.123457, 10:00:00, 10:00:00.5 and 10:00:01 UTC) with no field-drop event');
select is_empty($$ select e.id from app.card_provider_private_events e
                    where e.attempt_row_id in (select pg_temp.fr_rid(s.c) from _fr_sv7 s where s.want is not null) $$,
  'FR-280 review fix 23: ... and those five attempts hold no private event at all');
select results_eq($$ select s.k, s.val, pg_temp.fr_sig(s.k), c.before_row ->> 'provider_saved_at', c.after_row ->> 'provider_saved_at'
                       from _fr_sv7 s join _fr_call c on c.k = s.k where s.want is null order by s.k $$,
                  $$ values
                       ('yt06-1', '2026-10-24T10:00:00.1234567890Z', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_saved_at/format/commit', null::text, null::text),
                       ('yt07-1', '2026-10-24T10:00:00.Z', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_saved_at/format/commit', null::text, null::text),
                       ('yt08-1', '2026-02-30T10:00:00Z', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_saved_at/format/commit', null::text, null::text),
                       ('yt09-1', '2026-10-24T10:00:00+16:00', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_saved_at/format/commit', null::text, null::text) $$,
  'FR-281 review fix 23: 2026-10-24T10:00:00.1234567890Z (10 fraction digits) and 2026-10-24T10:00:00.Z (a dot with no digit), both a valid timestamptz to PostgreSQL but outside the grammar, and 2026-02-30T10:00:00Z / 2026-10-24T10:00:00+16:00, inside the grammar but not a valid timestamptz, are each dropped: stored NULL with exactly one field-drop event provider_saved_at/format/commit');
select results_eq($$ select s.k, e.action, e.detail, e.attempt_row_id = pg_temp.fr_rid(s.c), e.mode,
                            e.organization_id = pg_temp.zc_org() and e.restaurant_id = pg_temp.zc_rest()
                              and e.branch_id = pg_temp.zc_branch() and e.device_id = pg_temp.zc_id('device-1'),
                            e.actor_kind, e.actor_reference
                       from _fr_sv7 s join _fr_evt e on e.k = s.k order by s.k $$,
                  $$ select k, 'security.card_provider_field_dropped',
                            '{"field": "provider_saved_at", "rule": "format", "source": "commit"}'::jsonb, true, 'live', true,
                            'adapter', 'card_adapter'
                       from _fr_sv7 where want is null order by k $$,
  'FR-282 review fix 23: the nine commits wrote exactly four private events, one per dropped value and none for a stored one: security.card_provider_field_dropped {field: provider_saved_at, rule: format, source: commit} on its own LIVE attempt row (pilot organization / restaurant / branch, device d1, actor adapter / card_adapter)');
select pg_temp.fr_fin('yt01-2', 'yt01', 'lookup', 'not_found', '{"provider_saved_at": "2026-10-24T10:00:00.1234567890Z"}'::jsonb);
select pg_temp.fr_fin('yt01-3', 'yt01', 'lookup', 'pending', '{"provider_saved_at": "2026-10-24T10:00:00.Z"}'::jsonb);
select pg_temp.fr_fin('yt06-2', 'yt06', 'lookup', 'not_found', '{"provider_saved_at": "2026-10-24T10:00:00.Z"}'::jsonb);
select pg_temp.fr_fin('yt07-2', 'yt07', 'lookup', 'pending', '{"provider_saved_at": "2026-10-24T10:00:00.1234567890Z"}'::jsonb);
select results_eq($$ select k, pg_temp.fr_sig(k), (after_row ->> 'provider_saved_at')::timestamptz
                       from _fr_call where k in ('yt01-2', 'yt01-3', 'yt06-2', 'yt07-2') order by k $$,
  $$ values ('yt01-2', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=provider_saved_at/format/lookup', '2026-10-24T07:00:00.123457Z'::timestamptz),
            ('yt01-3', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', '2026-10-24T07:00:00.123457Z'::timestamptz),
            ('yt06-2', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', null::timestamptz),
            ('yt07-2', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-', null::timestamptz) $$,
  'FR-283 review fix 23 + M1: on yt01 (holding the stored 07:00:00.123457 instant) a lookup with 10 fraction digits is dropped with its one provider_saved_at/format/lookup event and keeps the instant, and a later lookup with 2026-10-24T10:00:00.Z writes no second event; on yt06 / yt07, which already hold their format event, the other dropped value writes no second event and stores nothing');
select results_eq($$ select s.c, count(e.id)::integer from _fr_sv7 s
                       left join app.card_provider_private_events e
                         on e.attempt_row_id = pg_temp.fr_rid(s.c) and e.action = 'security.card_provider_field_dropped'
                        and e.detail ->> 'field' = 'provider_saved_at' and e.detail ->> 'rule' = 'format'
                      group by s.c order by s.c $$,
                  $$ values ('yt01', 1), ('yt02', 0), ('yt03', 0), ('yt04', 0), ('yt05', 0), ('yt06', 1), ('yt07', 1), ('yt08', 1), ('yt09', 1) $$,
  'FR-284 review fix 23 + M1: exactly one (attempt, provider_saved_at, format) event on each attempt that received a dropped value (yt01 after its stored instant, yt06 - yt09) and none on the four that only stored one (yt02 - yt05)');

-- ===========================================================================
-- 21. Review fix 26: the 4 x max length bound answers length for an over-long
--     value even where the canonical charset check would have named another
--     rule first (packet sec. 4.5 precedence: raw control_character -> raw
--     charset -> length bound -> canonical control_character -> canonical
--     charset -> length -> digit_run -> masked_pattern). Refused either way,
--     nothing stored.
-- ===========================================================================
select results_eq($$ select x.n, x.f, x.c, char_length(x.v), app.card_safe_text_failure(x.v, x.f) from (values
                       (1, 'provider_reference', '64 A + space + 65 B (4 x 32 + 2)', repeat('A', 64) || ' ' || repeat('B', 65)),
                       (2, 'provider_reference', '64 A + space + 64 B (4 x 32 + 1)', repeat('A', 64) || ' ' || repeat('B', 64)),
                       (3, 'provider_reference', '64 A + space + 63 B (4 x 32)', repeat('A', 64) || ' ' || repeat('B', 63)),
                       (4, 'provider_reference', 'the 128 inside 10 U+3000 / 10 spaces (128 trimmed)',
                        repeat(U&'\3000', 10) || repeat('A', 64) || ' ' || repeat('B', 63) || repeat(' ', 10)),
                       (5, 'approval_number', '32 A + hyphen + 32 B (4 x 16 + 1)', repeat('A', 32) || '-' || repeat('B', 32)),
                       (6, 'approval_number', '32 A + hyphen + 31 B (4 x 16)', repeat('A', 32) || '-' || repeat('B', 31)),
                       (7, 'operator_reference', '128 r + space + 128 r (4 x 64 + 1)', repeat('r', 128) || ' ' || repeat('r', 128)),
                       (8, 'operator_reference', '128 r + space + 127 r (4 x 64)', repeat('r', 128) || ' ' || repeat('r', 127))) x(n, f, c, v)
                      order by x.n $$,
                  $$ values (1, 'provider_reference', '64 A + space + 65 B (4 x 32 + 2)', 130, 'length'),
                            (2, 'provider_reference', '64 A + space + 64 B (4 x 32 + 1)', 129, 'length'),
                            (3, 'provider_reference', '64 A + space + 63 B (4 x 32)', 128, 'charset'),
                            (4, 'provider_reference', 'the 128 inside 10 U+3000 / 10 spaces (128 trimmed)', 148, 'charset'),
                            (5, 'approval_number', '32 A + hyphen + 32 B (4 x 16 + 1)', 65, 'length'),
                            (6, 'approval_number', '32 A + hyphen + 31 B (4 x 16)', 64, 'charset'),
                            (7, 'operator_reference', '128 r + space + 128 r (4 x 64 + 1)', 257, 'length'),
                            (8, 'operator_reference', '128 r + space + 127 r (4 x 64)', 256, 'charset') $$,
  'FR-285 review fix 26: provider_reference (max 32): a 130- and a 129-code-point value holding an interior space -> length (the bound answers before the canonical charset check), the 128-code-point one (at the bound) -> charset, and the 128 inside 20 edge Space_Separators (148 raw) -> charset (edge Zs never count); likewise approval_number (max 16, a hyphen) 65 -> length / 64 -> charset and operator_reference (max 64, a space) 257 -> length / 256 -> charset');
select is(pg_temp.fr_do('yr1-1', 'yr1', 'commit', 'approved',
            pg_temp.zc_approved_fields() || jsonb_build_object('provider_reference', repeat('A', 64) || ' ' || repeat('B', 65))),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=provider_reference/length/commit',
  'FR-286 review fix 26: through a commit approval, the 130-code-point provider_reference holding a space is dropped with rule length (not charset) and never blocks the approval');
select is(pg_temp.fr_do('yr2-1', 'yr2', 'commit', 'approved',
            pg_temp.zc_approved_fields() || jsonb_build_object('provider_reference', repeat('A', 64) || ' ' || repeat('B', 63))),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=provider_reference/charset/commit',
  'FR-287 review fix 26: ... while the 128-code-point one (inside the bound) is dropped with rule charset');
select results_eq($$ select c.k, e.action, e.detail, e.attempt_row_id = pg_temp.fr_rid(c.c), e.mode,
                            e.organization_id = pg_temp.zc_org() and e.restaurant_id = pg_temp.zc_rest()
                              and e.branch_id = pg_temp.zc_branch() and e.device_id = pg_temp.zc_id('device-1'),
                            e.actor_kind, e.actor_reference, c.before_row ->> 'provider_reference', c.after_row ->> 'provider_reference'
                       from _fr_call c join _fr_evt e on e.k = c.k where c.k in ('yr1-1', 'yr2-1') order by c.k $$,
                  $$ values ('yr1-1', 'security.card_provider_field_dropped', '{"field": "provider_reference", "rule": "length", "source": "commit"}'::jsonb,
                             true, 'live', true, 'adapter', 'card_adapter', null::text, null::text),
                            ('yr2-1', 'security.card_provider_field_dropped', '{"field": "provider_reference", "rule": "charset", "source": "commit"}'::jsonb,
                             true, 'live', true, 'adapter', 'card_adapter', null::text, null::text) $$,
  'FR-288 review fix 26: each approval wrote exactly one private event, security.card_provider_field_dropped {field: provider_reference, rule: length | charset, source: commit} on its own LIVE row (pilot scope, device d1, actor adapter / card_adapter), and provider_reference stays NULL on both rows (nothing stored)');
select is_empty($$ select 'attempt' from app.card_provider_attempts a where strpos(to_jsonb(a)::text, repeat('A', 64) || ' B') > 0
                   union all select 'event' from app.card_provider_private_events e where strpos(to_jsonb(e)::text, repeat('A', 64) || ' B') > 0
                   union all select 'audit' from public.audit_events ae where ae.organization_id = pg_temp.zc_org()
                                                         and strpos(to_jsonb(ae)::text, repeat('A', 64) || ' B') > 0 $$,
  'FR-289 review fix 26: ... no ledger row, private event or audit row holds any part of the two refused values');

select is((select count(*) from _fr_aud where k like 'pre:%') + (select count(*) from _fr_evt where k like 'pre:%'), 0::bigint,
  'FR-290 harness: every audit row and private event of sections 20-21 too was attributed to the call that wrote it');

-- ===========================================================================
-- 22. Correction C1-4: the closed text policy of app.card_safe_text_failure
--     (every payment metadata field). Rule order (raw R, canonical C = NFKC +
--     Zs trim): 1 R refused control (Cc / Zl / Zp / every Cf / every
--     Default_Ignorable except U+061C, U+200C..U+200F) -> control_character;
--     2 R outside the allowlist or holding a Numeric_Type=Numeric character ->
--     charset; 3 trimmed R > 4 x max -> length; 4 C absent -> length, C control
--     -> control_character, C outside allowlist / Numeric / grammar -> charset;
--     5 C length, or (reason / order_freed_note) no visible letter or digit ->
--     length; 6 12+ digit-like (Numeric_Type Decimal or Digit) anywhere in R or
--     in C -> digit_run; 7 masked pattern once everything but a non-modifier
--     letter, a digit-like character or a mask is removed -> masked_pattern.
--     The class ranges below are THIS lane's own derivation from the pinned UCD
--     15.1.0 files (UnicodeData.txt sha256 2fc713e6...fb86,
--     DerivedCoreProperties.txt sha256 f55d0db6...108b,
--     extracted/DerivedNumericType.txt sha256 0f22ca77...cddd), independent of
--     the migration's constants:
--       di_refused    Default_Ignorable_Code_Point minus U+061C, U+200C..U+200F
--       ctrl_other    Cc / Zl / Zp / Cf outside Default_Ignorable (U+0000 is not
--                     representable in text and is left out of every probe)
--       numeric       Numeric_Type=Numeric
--       digit         Numeric_Type=Decimal or Digit (digit-like)
--       lm            General_Category=Lm
--       canon_digit   allowlisted, not refused, not Numeric, not digit-like, and
--                     its NFKD holds a digit-like code point
--       canon_numeric allowlisted, not refused, not Numeric, and its NFKD holds a
--                     Numeric code point
--     Every digit sequence is generated in SQL (pg_temp.fr_c1_d); descriptions
--     and diagnostics carry only rule tokens, counts, labels and single
--     code-point labels, never a value.
-- ===========================================================================
create temp table _fr_c1cls (cls text not null, lo integer not null, hi integer not null);
insert into _fr_c1cls (cls, lo, hi) values
  ('di_refused', 173, 173), ('di_refused', 847, 847), ('di_refused', 4447, 4448), ('di_refused', 6068, 6069), ('di_refused', 6155, 6159), ('di_refused', 8203, 8203),
  ('di_refused', 8234, 8238), ('di_refused', 8288, 8303), ('di_refused', 12644, 12644), ('di_refused', 65024, 65039), ('di_refused', 65279, 65279), ('di_refused', 65440, 65440),
  ('di_refused', 65520, 65528), ('di_refused', 113824, 113827), ('di_refused', 119155, 119162), ('di_refused', 917504, 921599),
  ('ctrl_other', 0, 31), ('ctrl_other', 127, 159), ('ctrl_other', 1536, 1541), ('ctrl_other', 1757, 1757), ('ctrl_other', 1807, 1807), ('ctrl_other', 2192, 2193),
  ('ctrl_other', 2274, 2274), ('ctrl_other', 8232, 8233), ('ctrl_other', 65529, 65531), ('ctrl_other', 69821, 69821), ('ctrl_other', 69837, 69837), ('ctrl_other', 78896, 78911),
  ('numeric', 188, 190), ('numeric', 2548, 2553), ('numeric', 2930, 2935), ('numeric', 3056, 3058), ('numeric', 3192, 3198), ('numeric', 3416, 3422),
  ('numeric', 3440, 3448), ('numeric', 3882, 3891), ('numeric', 4978, 4988), ('numeric', 5870, 5872), ('numeric', 6128, 6137), ('numeric', 8528, 8578),
  ('numeric', 8581, 8585), ('numeric', 9321, 9331), ('numeric', 9341, 9351), ('numeric', 9361, 9371), ('numeric', 9451, 9460), ('numeric', 9470, 9470),
  ('numeric', 10111, 10111), ('numeric', 10121, 10121), ('numeric', 10131, 10131), ('numeric', 11517, 11517), ('numeric', 12295, 12295), ('numeric', 12321, 12329),
  ('numeric', 12344, 12346), ('numeric', 12690, 12693), ('numeric', 12832, 12841), ('numeric', 12872, 12879), ('numeric', 12881, 12895), ('numeric', 12928, 12937),
  ('numeric', 12977, 12991), ('numeric', 13317, 13317), ('numeric', 13443, 13443), ('numeric', 14378, 14378), ('numeric', 15181, 15181), ('numeric', 19968, 19968),
  ('numeric', 19971, 19971), ('numeric', 19975, 19975), ('numeric', 19977, 19977), ('numeric', 20004, 20004), ('numeric', 20061, 20061), ('numeric', 20108, 20108),
  ('numeric', 20116, 20116), ('numeric', 20118, 20118), ('numeric', 20140, 20140), ('numeric', 20159, 20160), ('numeric', 20191, 20191), ('numeric', 20200, 20200),
  ('numeric', 20237, 20237), ('numeric', 20336, 20336), ('numeric', 20457, 20457), ('numeric', 20486, 20486), ('numeric', 20740, 20740), ('numeric', 20806, 20806),
  ('numeric', 20841, 20841), ('numeric', 20843, 20843), ('numeric', 20845, 20845), ('numeric', 21313, 21313), ('numeric', 21315, 21317), ('numeric', 21324, 21324),
  ('numeric', 21441, 21444), ('numeric', 22235, 22235), ('numeric', 22769, 22769), ('numeric', 22777, 22777), ('numeric', 24186, 24186), ('numeric', 24318, 24319),
  ('numeric', 24332, 24334), ('numeric', 24336, 24336), ('numeric', 25296, 25296), ('numeric', 25342, 25342), ('numeric', 25420, 25420), ('numeric', 26578, 26578),
  ('numeric', 27934, 27934), ('numeric', 28422, 28422), ('numeric', 29590, 29590), ('numeric', 30334, 30334), ('numeric', 30357, 30357), ('numeric', 31213, 31213),
  ('numeric', 32902, 32902), ('numeric', 33836, 33836), ('numeric', 36014, 36014), ('numeric', 36019, 36019), ('numeric', 36144, 36144), ('numeric', 37390, 37390),
  ('numeric', 38057, 38057), ('numeric', 38433, 38433), ('numeric', 38470, 38470), ('numeric', 38476, 38476), ('numeric', 38520, 38520), ('numeric', 38646, 38646),
  ('numeric', 42726, 42735), ('numeric', 43056, 43061), ('numeric', 63851, 63851), ('numeric', 63859, 63859), ('numeric', 63864, 63864), ('numeric', 63922, 63922),
  ('numeric', 63953, 63953), ('numeric', 63955, 63955), ('numeric', 63997, 63997), ('numeric', 65799, 65843), ('numeric', 65856, 65912), ('numeric', 65930, 65931),
  ('numeric', 66273, 66299), ('numeric', 66336, 66339), ('numeric', 66369, 66369), ('numeric', 66378, 66378), ('numeric', 66513, 66517), ('numeric', 67672, 67679),
  ('numeric', 67705, 67711), ('numeric', 67751, 67759), ('numeric', 67835, 67839), ('numeric', 67862, 67867), ('numeric', 68028, 68029), ('numeric', 68032, 68047),
  ('numeric', 68050, 68095), ('numeric', 68164, 68168), ('numeric', 68221, 68222), ('numeric', 68253, 68255), ('numeric', 68331, 68335), ('numeric', 68440, 68447),
  ('numeric', 68472, 68479), ('numeric', 68521, 68527), ('numeric', 68858, 68863), ('numeric', 69225, 69246), ('numeric', 69405, 69414), ('numeric', 69457, 69460),
  ('numeric', 69573, 69579), ('numeric', 69723, 69733), ('numeric', 70113, 70132), ('numeric', 71482, 71483), ('numeric', 71914, 71922), ('numeric', 72794, 72812),
  ('numeric', 73664, 73684), ('numeric', 74752, 74862), ('numeric', 93019, 93025), ('numeric', 93824, 93846), ('numeric', 119488, 119507), ('numeric', 119520, 119539),
  ('numeric', 119648, 119672), ('numeric', 125127, 125135), ('numeric', 126065, 126123), ('numeric', 126125, 126127), ('numeric', 126129, 126132), ('numeric', 126209, 126253),
  ('numeric', 126255, 126269), ('numeric', 127243, 127244), ('numeric', 131073, 131073), ('numeric', 131172, 131172), ('numeric', 131298, 131298), ('numeric', 131361, 131361),
  ('numeric', 133418, 133418), ('numeric', 133507, 133507), ('numeric', 133516, 133516), ('numeric', 133532, 133532), ('numeric', 133866, 133866), ('numeric', 133885, 133885),
  ('numeric', 133913, 133913), ('numeric', 140176, 140176), ('numeric', 141720, 141720), ('numeric', 146203, 146203), ('numeric', 156269, 156269), ('numeric', 194704, 194704),
  ('digit', 48, 57), ('digit', 178, 179), ('digit', 185, 185), ('digit', 1632, 1641), ('digit', 1776, 1785), ('digit', 1984, 1993),
  ('digit', 2406, 2415), ('digit', 2534, 2543), ('digit', 2662, 2671), ('digit', 2790, 2799), ('digit', 2918, 2927), ('digit', 3046, 3055),
  ('digit', 3174, 3183), ('digit', 3302, 3311), ('digit', 3430, 3439), ('digit', 3558, 3567), ('digit', 3664, 3673), ('digit', 3792, 3801),
  ('digit', 3872, 3881), ('digit', 4160, 4169), ('digit', 4240, 4249), ('digit', 4969, 4977), ('digit', 6112, 6121), ('digit', 6160, 6169),
  ('digit', 6470, 6479), ('digit', 6608, 6618), ('digit', 6784, 6793), ('digit', 6800, 6809), ('digit', 6992, 7001), ('digit', 7088, 7097),
  ('digit', 7232, 7241), ('digit', 7248, 7257), ('digit', 8304, 8304), ('digit', 8308, 8313), ('digit', 8320, 8329), ('digit', 9312, 9320),
  ('digit', 9332, 9340), ('digit', 9352, 9360), ('digit', 9450, 9450), ('digit', 9461, 9469), ('digit', 9471, 9471), ('digit', 10102, 10110),
  ('digit', 10112, 10120), ('digit', 10122, 10130), ('digit', 42528, 42537), ('digit', 43216, 43225), ('digit', 43264, 43273), ('digit', 43472, 43481),
  ('digit', 43504, 43513), ('digit', 43600, 43609), ('digit', 44016, 44025), ('digit', 65296, 65305), ('digit', 66720, 66729), ('digit', 68160, 68163),
  ('digit', 68912, 68921), ('digit', 69216, 69224), ('digit', 69714, 69722), ('digit', 69734, 69743), ('digit', 69872, 69881), ('digit', 69942, 69951),
  ('digit', 70096, 70105), ('digit', 70384, 70393), ('digit', 70736, 70745), ('digit', 70864, 70873), ('digit', 71248, 71257), ('digit', 71360, 71369),
  ('digit', 71472, 71481), ('digit', 71904, 71913), ('digit', 72016, 72025), ('digit', 72784, 72793), ('digit', 73040, 73049), ('digit', 73120, 73129),
  ('digit', 73552, 73561), ('digit', 92768, 92777), ('digit', 92864, 92873), ('digit', 93008, 93017), ('digit', 120782, 120831), ('digit', 123200, 123209),
  ('digit', 123632, 123641), ('digit', 124144, 124153), ('digit', 125264, 125273), ('digit', 127232, 127242), ('digit', 130032, 130041),
  ('lm', 688, 705), ('lm', 710, 721), ('lm', 736, 740), ('lm', 748, 748), ('lm', 750, 750), ('lm', 884, 884),
  ('lm', 890, 890), ('lm', 1369, 1369), ('lm', 1600, 1600), ('lm', 1765, 1766), ('lm', 2036, 2037), ('lm', 2042, 2042),
  ('lm', 2074, 2074), ('lm', 2084, 2084), ('lm', 2088, 2088), ('lm', 2249, 2249), ('lm', 2417, 2417), ('lm', 3654, 3654),
  ('lm', 3782, 3782), ('lm', 4348, 4348), ('lm', 6103, 6103), ('lm', 6211, 6211), ('lm', 6823, 6823), ('lm', 7288, 7293),
  ('lm', 7468, 7530), ('lm', 7544, 7544), ('lm', 7579, 7615), ('lm', 8305, 8305), ('lm', 8319, 8319), ('lm', 8336, 8348),
  ('lm', 11388, 11389), ('lm', 11631, 11631), ('lm', 11823, 11823), ('lm', 12293, 12293), ('lm', 12337, 12341), ('lm', 12347, 12347),
  ('lm', 12445, 12446), ('lm', 12540, 12542), ('lm', 40981, 40981), ('lm', 42232, 42237), ('lm', 42508, 42508), ('lm', 42623, 42623),
  ('lm', 42652, 42653), ('lm', 42775, 42783), ('lm', 42864, 42864), ('lm', 42888, 42888), ('lm', 42994, 42996), ('lm', 43000, 43001),
  ('lm', 43471, 43471), ('lm', 43494, 43494), ('lm', 43632, 43632), ('lm', 43741, 43741), ('lm', 43763, 43764), ('lm', 43868, 43871),
  ('lm', 43881, 43881), ('lm', 65392, 65392), ('lm', 65438, 65439), ('lm', 67456, 67461), ('lm', 67463, 67504), ('lm', 67506, 67514),
  ('lm', 92992, 92995), ('lm', 94099, 94111), ('lm', 94176, 94177), ('lm', 94179, 94179), ('lm', 110576, 110579), ('lm', 110581, 110587),
  ('lm', 110589, 110590), ('lm', 122928, 122989), ('lm', 123191, 123197), ('lm', 124139, 124139), ('lm', 125259, 125259),
  ('canon_digit', 12992, 13003), ('canon_digit', 13144, 13168), ('canon_digit', 13176, 13177), ('canon_digit', 13215, 13222), ('canon_digit', 13224, 13224), ('canon_digit', 13231, 13231),
  ('canon_digit', 13280, 13310),
  ('canon_numeric', 12032, 12032), ('canon_numeric', 12038, 12038), ('canon_numeric', 12043, 12043), ('canon_numeric', 12055, 12055), ('canon_numeric', 12083, 12083), ('canon_numeric', 12086, 12086),
  ('canon_numeric', 64005, 64005), ('canon_numeric', 127508, 127508), ('canon_numeric', 127529, 127530), ('canon_numeric', 127553, 127554);
create temp table _fr_c1cp as
select c.cls, g.cp from _fr_c1cls c cross join lateral generate_series(c.lo, c.hi) g(cp) where g.cp <> 0;
create function pg_temp.fr_c1_is(p_cls text, p_cp integer) returns boolean language sql stable as $$
  select exists (select 1 from _fr_c1cls c where c.cls = p_cls and p_cp between c.lo and c.hi) $$;
create function pg_temp.fr_c1_u(p_cp integer) returns text language sql immutable as $$
  select 'U+' || case when p_cp > 65535 then upper(to_hex(p_cp)) else upper(lpad(to_hex(p_cp), 4, '0')) end $$;
-- The number of digit-like code points in a value (UCD class above).
create function pg_temp.fr_c1_dl(p_v text) returns integer language sql stable as $$
  select count(*)::integer from regexp_split_to_table(p_v, '') c where pg_temp.fr_c1_is('digit', ascii(c)) $$;
-- Digit families: the digit-like members (UCD class above) of each code-point span.
create temp table _fr_c1famr (fam text not null, ord integer not null, lo integer not null, hi integer not null);
insert into _fr_c1famr values
  ('ascii', 1, 48, 57), ('arabic_indic', 2, 1632, 1641), ('ext_arabic_indic', 3, 1776, 1785),
  ('devanagari', 4, 2406, 2415), ('fullwidth', 5, 65296, 65305), ('mathematical', 6, 120782, 120831),
  ('superscript', 7, 178, 179), ('superscript', 7, 185, 185), ('superscript', 7, 8304, 8304), ('superscript', 7, 8308, 8313),
  ('circled', 8, 9312, 9331), ('circled', 8, 9450, 9450), ('dingbat', 9, 10102, 10131),
  ('double_circled', 10, 9461, 9470), ('ethiopic', 11, 4969, 4977), ('thai', 12, 3664, 3673);
create temp table _fr_c1fam as
select r.fam, r.ord, (row_number() over (partition by r.fam order by c.cp))::integer as n, c.cp
  from _fr_c1famr r join _fr_c1cp c on c.cls = 'digit' and c.cp between r.lo and r.hi;
-- p_n digits of a family joined by p_sep, cycling through its members from member p_start (code-point order).
create function pg_temp.fr_c1_d(p_n integer, p_fam text default 'ascii', p_start integer default 2,
                                p_sep text default '') returns text language sql stable as $$
  select string_agg(chr(f.cp), p_sep order by g.i)
    from generate_series(0, p_n - 1) g(i)
    join _fr_c1fam f on f.fam = p_fam
     and f.n = (p_start - 1 + g.i) % (select count(*) from _fr_c1fam x where x.fam = p_fam) + 1 $$;
-- p_n digits, the i-th from the i-th family (12 families, cycling), joined by p_sep.
create function pg_temp.fr_c1_mixed(p_n integer, p_sep text default '') returns text language sql stable as $$
  select string_agg(chr(f.cp), p_sep order by g.i)
    from generate_series(1, p_n) g(i)
    join (select distinct x.fam, x.ord from _fr_c1fam x) o on o.ord = (g.i - 1) % 12 + 1
    join _fr_c1fam f on f.fam = o.fam and f.n = g.i % 9 + 1 $$;
create temp table _fr_c1w (k text primary key, w text not null);
insert into _fr_c1w values
  ('ar1', U&'\0627\0644\0637\0644\0628'), ('ar2', U&'\0645\0644\063A\0649'),
  ('he1', U&'\05D4\05D6\05DE\05E0\05D4'), ('he2', U&'\05D1\05D5\05D8\05DC\05D4');
create function pg_temp.fr_c1_w(p_k text) returns text language sql stable as $$ select w from _fr_c1w where k = p_k $$;
create temp table _fr_c1fill (label text primary key, f text not null);
insert into _fr_c1fill values ('U+115F', U&'\115F'), ('U+1160', U&'\1160'), ('U+3164', U&'\3164'), ('U+FFA0', U&'\FFA0');
create temp table _fr_c1mark (label text primary key, m text not null);
insert into _fr_c1mark values
  ('U+061C', U&'\061C'), ('U+200C', U&'\200C'), ('U+200D', U&'\200D'), ('U+200E', U&'\200E'), ('U+200F', U&'\200F');
create temp table _fr_c1lm5 (label text primary key, l text not null);
insert into _fr_c1lm5 values
  ('U+0640', U&'\0640'), ('U+30FC', U&'\30FC'), ('U+02CD', U&'\02CD'), ('U+02D0', U&'\02D0'), ('U+07FA', U&'\07FA');
create temp table _fr_c1sep (s_ord integer primary key, label text not null, s text not null);
insert into _fr_c1sep values
  (1, 'Latin letter a', 'a'), (2, 'Arabic letter U+0628', U&'\0628'), (3, 'Hebrew letter U+05D0', U&'\05D0'),
  (4, 'Lm U+0640 tatweel', U&'\0640'), (5, 'Lm U+30FC', U&'\30FC'), (6, 'Lm U+02CD', U&'\02CD'),
  (7, 'Lm U+02D0', U&'\02D0'), (8, 'Lm U+07FA', U&'\07FA'), (9, 'full stop', '.'), (10, 'comma', ','),
  (11, 'hyphen', '-'), (12, 'slash', '/'), (13, 'colon', ':'), (14, 'space', ' '), (15, 'NBSP', U&'\00A0'),
  (16, 'U+3000', U&'\3000'), (17, 'combining U+0301', U&'\0301'), (18, 'combining U+064B', U&'\064B'),
  (19, 'combining U+05B8', U&'\05B8'), (20, 'dollar', '$'), (21, 'plus', '+'), (22, 'U+00A9', U&'\00A9'),
  (23, 'tilde', '~'), (24, 'the word and', ' and ');

-- The C1 vectors. canon_too: the canonical form must answer the same token
-- (false only where NFKC removes the refused character, rules 1-2 on R).
create temp table _fr_c1v (k serial primary key, grp text not null, label text not null, field text not null,
                           val text not null, want text, canon_too boolean not null default true);
create function pg_temp.fr_c1_bad(p_grp text) returns setof text language sql stable as $$
  select format('#%s %s [%s] want=%s raw=%s canonical=%s', v.k, v.label, v.field, coalesce(v.want, 'NULL'),
                coalesce(app.card_safe_text_failure(v.val, v.field), 'NULL'),
                coalesce(app.card_safe_text_failure(app.card_text_canonical(v.val), v.field), 'NULL'))
    from _fr_c1v v
   where v.grp = p_grp
     and (app.card_safe_text_failure(v.val, v.field) is distinct from v.want
          or (v.canon_too and app.card_safe_text_failure(app.card_text_canonical(v.val), v.field) is distinct from v.want))
   order by v.k $$;
-- MARKS: the five allowed marks inside visible Arabic / Hebrew text, and alone.
insert into _fr_c1v (grp, label, field, val, want)
select 'MARKS', m.label || ' inside Arabic text', 'reason', pg_temp.fr_c1_w('ar1') || m.m || ' ' || pg_temp.fr_c1_w('ar2'), null from _fr_c1mark m
union all
select 'MARKS', m.label || ' inside Hebrew text', 'reason', pg_temp.fr_c1_w('he1') || m.m || ' ' || pg_temp.fr_c1_w('he2'), null from _fr_c1mark m
union all
select 'MARKS', m.label || ' around a Hebrew word', 'order_freed_note', m.m || pg_temp.fr_c1_w('he1') || m.m, null from _fr_c1mark m
union all
select 'MARKS', m.label || ' alone', 'reason', m.m, 'length' from _fr_c1mark m;
-- FILL: the four Hangul fillers between digit groups, inside / at the edges of a reason, in a note.
insert into _fr_c1v (grp, label, field, val, want)
select 'FILL', f.label || ' between three 4-digit groups', 'reason',
       pg_temp.fr_c1_d(4) || f.f || pg_temp.fr_c1_d(4, 'ascii', 6) || f.f || pg_temp.fr_c1_d(4, 'ascii', 10), 'control_character'
  from _fr_c1fill f
union all select 'FILL', f.label || ' inside an English reason', 'reason', 'Customer' || f.f || 'request', 'control_character' from _fr_c1fill f
union all select 'FILL', f.label || ' inside an Arabic reason', 'reason', pg_temp.fr_c1_w('ar1') || f.f || pg_temp.fr_c1_w('ar2'), 'control_character' from _fr_c1fill f
union all select 'FILL', f.label || ' leading', 'reason', f.f || 'Customer request', 'control_character' from _fr_c1fill f
union all select 'FILL', f.label || ' trailing', 'reason', 'Customer request' || f.f, 'control_character' from _fr_c1fill f
union all select 'FILL', f.label || ' inside an order_freed_note', 'order_freed_note', 'Freed' || f.f || 'note', 'control_character' from _fr_c1fill f;
-- NUMRAW: a Numeric character whose NFKC satisfies the field grammar is refused on R (canonical passes).
insert into _fr_c1v (grp, label, field, val, want, canon_too) values
  ('NUMRAW', 'DEP- + U+216B (NFKC DEP-XII)', 'deposit_id', 'DEP-' || U&'\216B', 'charset', false),
  ('NUMRAW', 'V + U+2160 (NFKC VI)', 'voucher_number', 'V' || U&'\2160', 'charset', false),
  ('NUMRAW', 'declined + U+216B (NFKC declinedXII)', 'approval_type', 'declined' || U&'\216B', 'charset', false),
  ('NUMRAW', 'MC + U+2169 (NFKC MCX)', 'card_brand_code', 'MC' || U&'\2169', 'charset', false),
  ('NUMRAW', 'Table + U+2167 (NFKC Table VIII)', 'reason', 'Table ' || U&'\2167', 'charset', false),
  ('NUMRAW', 'Half + U+00BD (NFKC 1 U+2044 2)', 'reason', 'Half ' || U&'\00BD', 'charset', false);
-- PREC: the rule order on R (raw-only expectations).
insert into _fr_c1v (grp, label, field, val, want, canon_too) values
  ('PREC', 'a filler + a Numeric -> rule 1 first', 'reason', 'ab' || U&'\3164\216B', 'control_character', false),
  ('PREC', '12 digits + a Numeric -> rule 2 before digit_run', 'reason', pg_temp.fr_c1_d(12) || ' ' || U&'\216B', 'charset', false),
  ('PREC', 'a Numeric in an 801-code-point value -> rule 2 before the bound', 'reason',
   repeat('a', 788) || pg_temp.fr_c1_d(12) || U&'\216B', 'charset', false),
  ('PREC', 'a filler in an 801-code-point value -> rule 1 first', 'reason',
   repeat('a', 788) || pg_temp.fr_c1_d(12) || U&'\3164', 'control_character', false),
  ('PREC', '12 digits in an 801-code-point value -> rule 3 bound before digit_run', 'reason',
   repeat('a', 789) || pg_temp.fr_c1_d(12), 'length', false),
  ('PREC', '12 digits in a 201-code-point value -> rule 5 length before digit_run', 'reason',
   repeat('a', 189) || pg_temp.fr_c1_d(12), 'length', false),
  ('PREC', '12 digits in a 200-code-point value -> digit_run', 'reason', repeat('a', 188) || pg_temp.fr_c1_d(12), 'digit_run', false),
  ('PREC', '12 digits shaped 4 + mask + 4 + space + 4 -> digit_run before masked_pattern', 'reason',
   pg_temp.fr_c1_d(4) || '*' || pg_temp.fr_c1_d(4, 'ascii', 6) || ' ' || pg_temp.fr_c1_d(4, 'ascii', 10), 'digit_run', false),
  ('PREC', 'a filler inside a masked form -> control_character', 'reason',
   pg_temp.fr_c1_d(4) || U&'\3164' || '**' || pg_temp.fr_c1_d(4, 'ascii', 6), 'control_character', false),
  ('PREC', 'a Numeric inside a masked form -> charset', 'reason',
   pg_temp.fr_c1_d(4) || '*' || U&'\2160' || pg_temp.fr_c1_d(4, 'ascii', 6), 'charset', false),
  ('PREC', 'an NFKC-only Numeric (U+2F00) + 12 digits -> rule 4 charset before digit_run', 'reason',
   U&'\2F00 ' || pg_temp.fr_c1_d(12), 'charset', false);
-- S12 / S11: 12 (11) digit-like characters of one family, one separator between each.
insert into _fr_c1v (grp, label, field, val, want)
select 'S12', f.fam || ' / ' || s.label, 'reason', pg_temp.fr_c1_d(12, f.fam, 2, s.s), 'digit_run'
  from (select distinct fam, ord from _fr_c1fam) f cross join _fr_c1sep s order by f.ord, s.s_ord;
insert into _fr_c1v (grp, label, field, val, want)
select 'S11', f.fam || ' / ' || s.label, 'reason', pg_temp.fr_c1_d(11, f.fam, 2, s.s), null
  from (select distinct fam, ord from _fr_c1fam) f cross join _fr_c1sep s order by f.ord, s.s_ord;
-- M: mixed scripts, each digit from another family.
insert into _fr_c1v (grp, label, field, val, want)
select 'M', format('%s mixed-script digits, separator %s', n.n, s.label), 'reason', pg_temp.fr_c1_mixed(n.n, s.s),
       case when n.n = 12 then 'digit_run' end
  from (values (12), (11)) n(n)
 cross join (values (1, 'none', ''), (2, 'space', ' '), (3, 'Lm U+0640', U&'\0640'), (4, 'Latin letter a', 'a'),
                    (5, 'space-slash-space', ' / ')) s(o, label, s)
 order by n.n desc, s.o;
-- LMASK: masked forms whose separators are Lm letters (C1-4 rule 7: Lm is a separator).
insert into _fr_c1v (grp, label, field, val, want)
select 'LMASK', l.label || ': 4 digits + Lm + * + Lm + 4 digits', 'reason',
       pg_temp.fr_c1_d(4) || l.l || '*' || l.l || pg_temp.fr_c1_d(4, 'ascii', 6), 'masked_pattern' from _fr_c1lm5 l
union all select 'LMASK', l.label || ': 4 digits + Lm + 4 x U+2022 + Lm + 4 digits', 'reason',
       pg_temp.fr_c1_d(4) || l.l || repeat(U&'\2022', 4) || l.l || pg_temp.fr_c1_d(4, 'ascii', 6), 'masked_pattern' from _fr_c1lm5 l
union all select 'LMASK', l.label || ': *** + Lm + 4 digits', 'reason', repeat('*', 3) || l.l || pg_temp.fr_c1_d(4), 'masked_pattern' from _fr_c1lm5 l
union all select 'LMASK', l.label || ': 4 digits + Lm + ###', 'reason', pg_temp.fr_c1_d(4) || l.l || repeat('#', 3), 'masked_pattern' from _fr_c1lm5 l
union all select 'LMASK', l.label || ': 4 Arabic-Indic digits + Lm + X + Lm + 4 Arabic-Indic digits', 'reason',
       pg_temp.fr_c1_d(4, 'arabic_indic') || l.l || 'X' || l.l || pg_temp.fr_c1_d(4, 'arabic_indic', 6), 'masked_pattern' from _fr_c1lm5 l
union all select 'LMASK', l.label || ': 4 digits + Lm + 4 digits (no mask)', 'reason',
       pg_temp.fr_c1_d(4) || l.l || pg_temp.fr_c1_d(4, 'ascii', 6), null from _fr_c1lm5 l;
-- FMASK: masked forms carrying a Hangul filler (rule 1 answers first).
insert into _fr_c1v (grp, label, field, val, want)
select 'FMASK', f.label || ': 4 digits + filler + * + filler + 4 digits', 'reason',
       pg_temp.fr_c1_d(4) || f.f || '*' || f.f || pg_temp.fr_c1_d(4, 'ascii', 6), 'control_character' from _fr_c1fill f
union all select 'FMASK', f.label || ': *** + filler + 4 digits', 'reason', repeat('*', 3) || f.f || pg_temp.fr_c1_d(4), 'control_character' from _fr_c1fill f
union all select 'FMASK', f.label || ': 4 digits + filler + ###', 'reason', pg_temp.fr_c1_d(4) || f.f || repeat('#', 3), 'control_character' from _fr_c1fill f
union all select 'FMASK', f.label || ': 4 digits + filler + 4 x U+2022 + filler + 4 digits', 'reason',
       pg_temp.fr_c1_d(4) || f.f || repeat(U&'\2022', 4) || f.f || pg_temp.fr_c1_d(4, 'ascii', 6), 'control_character' from _fr_c1fill f;
-- LEN: no visible letter or digit (rule 5) in a reason AND in an order_freed_note.
insert into _fr_c1v (grp, label, field, val, want)
select 'LEN', x.label, f.field, x.v, 'length'
  from (values (1, 'U+200E U+200F', U&'\200E\200F'), (2, 'the five allowed marks together', U&'\061C\200C\200D\200E\200F'),
               (3, '3 x U+200C', U&'\200C\200C\200C'), (4, 'U+0300', U&'\0300'), (5, '3 x U+0301', U&'\0301\0301\0301'),
               (6, 'U+064B', U&'\064B'), (7, 'U+0651 U+064E', U&'\0651\064E'), (8, 'U+05B8', U&'\05B8'),
               (9, 'U+05BC U+05B4', U&'\05BC\05B4'), (10, 'U+20DD (Me)', U&'\20DD'), (11, 'U+0903 (Mc)', U&'\0903'),
               (12, 'U+2800', U&'\2800'), (13, '3 x U+2800', U&'\2800\2800\2800'), (14, 'U+2800 space U+2800', U&'\2800 \2800'),
               (15, 'U+2800 inside edge spaces', U&' \2800\3000'), (16, 'asterisk', '*'), (17, '3 asterisks', '***'),
               (18, 'number sign', '#'), (19, 'dollar U+20AC U+00A3', U&'$\20AC\00A3'), (20, 'plus equals', '+='),
               (21, 'U+2192 U+2190', U&'\2192\2190'), (22, '3 x U+2022', U&'\2022\2022\2022'), (23, 'U+00A9', U&'\00A9'),
               (24, 'percent', '%'), (25, 'exclamation question', '!?'), (26, 'three full stops', '...'),
               (27, 'U+2014', U&'\2014'), (28, 'U+200F U+0301 asterisk U+2800', U&'\200F\0301*\2800')) x(o, label, v)
 cross join (values (1, 'reason'), (2, 'order_freed_note')) f(o, field)
 order by f.o, x.o;
-- VIS: the visible-letter rule is judged on C.
insert into _fr_c1v (grp, label, field, val, want) values
  ('VIS', 'U+FF9E alone (Lm raw, NFKC U+3099 a combining mark)', 'reason', U&'\FF9E', 'length'),
  ('VIS', 'U+FF9F alone (Lm raw, NFKC U+309A)', 'reason', U&'\FF9F', 'length'),
  ('VIS', 'U+FF9E U+FF9F', 'order_freed_note', U&'\FF9E\FF9F', 'length'),
  ('VIS', 'a + U+FF9E', 'reason', U&'a\FF9E', null),
  ('VIS', 'U+30AB + U+FF9E', 'reason', U&'\30AB\FF9E', null);
-- POS: legitimate Arabic, Hebrew and English reasons (allowed marks, combining marks on letters, <= 11 digits).
insert into _fr_c1v (grp, label, field, val, want)
select 'POS', x.label, f.field, x.v, null
  from (values
    (1, 'Arabic with a damma, U+061C and U+200F',
     U&'\0623\064F\0644\063A\064A \0627\0644\0637\0644\0628\061C \0628\0637\0644\0628 \0627\0644\0632\0628\0648\0646\200F'),
    (2, 'Hebrew with niqqud, dagesh and U+200F',
     U&'\05D4\05B7\05D6\05B0\05DE\05B8\05E0\05B8\05D4 \05D1\05BC\05D5\05BC\05D8\05B0\05DC\05B8\05D4\200F'),
    (3, 'Hebrew with U+200E around a Latin code', U&'\05D4\05D6\05DE\05E0\05D4 \200EPOS-A\200E \05D1\05D5\05D8\05DC\05D4'),
    (4, 'English', 'Customer cancelled the order at the counter'),
    (5, 'English with combining acute marks on letters', U&'Cafe\0301 order: re\0301sume\0301 later'),
    (6, 'Persian with U+200C and Arabic with U+200D', U&'\0645\06CC\200C\062E\0648\0627\0647\0645 \0644\200D\0627'),
    (7, 'Arabic + English + Hebrew with U+061C / U+200E / U+200F', U&'\0627\0644\0637\0644\0628\061C order \200E\05D4\05D6\05DE\05E0\05D4\200F'),
    (8, 'English with 11 digits across words',
     'Table ' || pg_temp.fr_c1_d(2) || ', ' || pg_temp.fr_c1_d(1, 'ascii', 4) || ' guests, order '
       || pg_temp.fr_c1_d(3, 'ascii', 5) || ', call ' || pg_temp.fr_c1_d(5, 'ascii', 8)),
    (9, 'Arabic with 11 Arabic-Indic digits across words',
     pg_temp.fr_c1_w('ar1') || ' ' || pg_temp.fr_c1_d(5, 'arabic_indic') || ' ' || pg_temp.fr_c1_w('ar2') || ' '
       || pg_temp.fr_c1_d(6, 'arabic_indic', 7))) x(o, label, v)
 cross join (values (1, 'reason'), (2, 'order_freed_note')) f(o, field)
 order by f.o, x.o;
-- SHORT: short legitimate numeric values.
insert into _fr_c1v (grp, label, field, val, want) values
  ('SHORT', 'approval number of 6 digits', 'approval_number', pg_temp.fr_c1_d(6), null),
  ('SHORT', 'approval number of 11 digits', 'approval_number', pg_temp.fr_c1_d(11), null),
  ('SHORT', 'approval number of 12 digits', 'approval_number', pg_temp.fr_c1_d(12), 'digit_run'),
  ('SHORT', 'voucher number of 6 digits + 2 letters', 'voucher_number', pg_temp.fr_c1_d(6, 'ascii', 4) || 'AB', null),
  ('SHORT', 'provider reference ZC- + 11 digits', 'provider_reference', 'ZC-' || pg_temp.fr_c1_d(11), null),
  ('SHORT', 'provider reference ZC- + 12 digits', 'provider_reference', 'ZC-' || pg_temp.fr_c1_d(12), 'digit_run'),
  ('SHORT', 'card_last4 of 4 digits', 'card_last4', pg_temp.fr_c1_d(4, 'ascii', 5), null),
  ('SHORT', 'reason with 11 digits across words', 'reason',
   'Table ' || pg_temp.fr_c1_d(2) || ', ' || pg_temp.fr_c1_d(1, 'ascii', 4) || ' guests, order '
     || pg_temp.fr_c1_d(3, 'ascii', 5) || ', call ' || pg_temp.fr_c1_d(5, 'ascii', 8), null),
  ('SHORT', 'reason with 12 digits across words', 'reason',
   'Table ' || pg_temp.fr_c1_d(2) || ', ' || pg_temp.fr_c1_d(1, 'ascii', 4) || ' guests, order '
     || pg_temp.fr_c1_d(3, 'ascii', 5) || ', call ' || pg_temp.fr_c1_d(6, 'ascii', 8), 'digit_run'),
  ('SHORT', 'reason with a date (8 digits)', 'reason', 'Refunded on ' || to_char(make_date(2026, 10, 24), 'YYYY-MM-DD'), null),
  ('SHORT', 'reason with a date and a time (12 digits)', 'reason',
   'Refunded on ' || to_char(make_timestamp(2026, 10, 24, 14, 30, 0), 'YYYY-MM-DD HH24:MI'), 'digit_run'),
  ('SHORT', 'order_freed_note with 11 digits across words', 'order_freed_note',
   'Table ' || pg_temp.fr_c1_d(2) || ', ' || pg_temp.fr_c1_d(1, 'ascii', 4) || ' guests, order '
     || pg_temp.fr_c1_d(3, 'ascii', 5) || ', call ' || pg_temp.fr_c1_d(5, 'ascii', 8), null);
-- POST: post-normalization length limits of the new rules.
insert into _fr_c1v (grp, label, field, val, want) values
  ('POST', '95 x U+FB00 + 12 digits', 'reason', repeat(U&'\FB00', 95) || pg_temp.fr_c1_d(12), 'length'),
  ('POST', '94 x U+FB00 + 12 digits', 'reason', repeat(U&'\FB00', 94) || pg_temp.fr_c1_d(12), 'digit_run'),
  ('POST', '100 x U+33E0', 'reason', repeat(U&'\33E0', 100), 'digit_run'),
  ('POST', '101 x U+33E0', 'reason', repeat(U&'\33E0', 101), 'length'),
  ('POST', '11 digits + U+33E0', 'reason', pg_temp.fr_c1_d(11) || U&'\33E0', 'digit_run'),
  ('POST', '10 digits + U+33E0', 'reason', pg_temp.fr_c1_d(10) || U&'\33E0', null),
  ('POST', '95 x U+FB00 + 12 digits (note)', 'order_freed_note', repeat(U&'\FB00', 95) || pg_temp.fr_c1_d(12), 'length'),
  ('POST', '11 digits + U+33E0 (note)', 'order_freed_note', pg_temp.fr_c1_d(11) || U&'\33E0', 'digit_run');

select results_eq($$ select cls, count(*)::integer, sum(hi - lo + 1)::integer from _fr_c1cls group by cls order by cls $$,
  $$ values ('canon_digit', 7, 80), ('canon_numeric', 10, 12), ('ctrl_other', 12, 99), ('di_refused', 16, 4169),
            ('digit', 83, 808), ('lm', 71, 397), ('numeric', 162, 1114) $$,
  'FR-291 harness (C1-4): the class table under test is this lane''s own UCD 15.1.0 derivation: refused Default_Ignorable 16 ranges / 4169 code points, other refused controls (Cc / Zl / Zp / Cf) 12 / 99, Numeric_Type=Numeric 162 / 1114, digit-like (Decimal + Digit) 83 / 808, Lm 71 / 397, NFKC-only digit producers 7 / 80, NFKC-only Numeric producers 10 / 12');
select results_eq($$ select fam, count(*)::integer from _fr_c1fam group by fam, ord order by ord $$,
  $$ values ('ascii', 10), ('arabic_indic', 10), ('ext_arabic_indic', 10), ('devanagari', 10), ('fullwidth', 10),
            ('mathematical', 50), ('superscript', 10), ('circled', 10), ('dingbat', 27), ('double_circled', 9),
            ('ethiopic', 9), ('thai', 10) $$,
  'FR-292 harness (C1-4): the 12 digit families keep only digit-like members: mathematical U+1D7CE..U+1D7FF 50, circled U+2460..U+2468 + U+24EA 10, dingbat U+2776..U+2793 27 (U+277F, U+2789, U+2793 are Numeric), double circled U+24F5..U+24FD 9 (U+24FE is Numeric), Ethiopic U+1369..U+1371 9, the others 10');
select is_empty($$ select format('%s alone=%s inside=%s', pg_temp.fr_c1_u(c.cp),
                                 coalesce(app.card_safe_text_failure(chr(c.cp), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'di_refused'
                      and (app.card_safe_text_failure(chr(c.cp), 'reason') is distinct from 'control_character'
                           or app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason') is distinct from 'control_character')
                    order by c.cp $$,
  'FR-293 C1-4 rule 1 (exhaustive, raw): each of the 4169 Default_Ignorable_Code_Point code points except the five allowed marks (U+00AD, U+034F, the Hangul fillers U+115F / U+1160 / U+3164 / U+FFA0, U+17B4 / U+17B5, U+180B..U+180F, U+200B, U+202A..U+202E, U+2060..U+206F, U+FE00..U+FE0F, U+FEFF, U+FFF0..U+FFF8, U+1BCA0..U+1BCA3, U+1D173..U+1D17A, U+E0000..U+E0FFF with U+E0100..U+E01EF) -> control_character alone and inside a visible reason');
select is_empty($$ select format('%s alone=%s inside=%s', pg_temp.fr_c1_u(c.cp),
                                 coalesce(app.card_safe_text_failure(chr(c.cp), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'ctrl_other'
                      and (app.card_safe_text_failure(chr(c.cp), 'reason') is distinct from 'control_character'
                           or app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason') is distinct from 'control_character')
                    order by c.cp $$,
  'FR-294 C1-4 rule 1 (exhaustive, raw): each of the 98 other refused controls (Cc U+0001..U+001F / U+007F..U+009F, Zl, Zp, the Cf outside Default_Ignorable: U+0600..U+0605, U+06DD, U+070F, U+0890 / U+0891, U+08E2, U+FFF9..U+FFFB, U+110BD, U+110CD, U+13430..U+1343F) -> control_character alone and inside a visible reason');
-- One sweep of the whole code space (surrogates excluded), each code point inside a visible reason.
create temp table _fr_c1sweep as
select jsonb_build_object(
         'swept', count(*),
         'control_verdicts', count(*) filter (where s.f = 'control_character'),
         'control_class', count(*) filter (where s.ctrl),
         'control_mismatch', count(*) filter (where (s.f is not distinct from 'control_character') <> s.ctrl),
         'numeric_class', count(*) filter (where s.num),
         'numeric_not_charset', count(*) filter (where s.num and s.f is distinct from 'charset'),
         'canon_numeric_class', count(*) filter (where s.cnum),
         'canon_numeric_not_charset', count(*) filter (where s.cnum and s.f is distinct from 'charset'),
         'digit_class', count(*) filter (where s.dl),
         'digit_not_null', count(*) filter (where s.dl and s.f is not null),
         'lm_class', count(*) filter (where s.lm),
         'lm_not_null', count(*) filter (where s.lm and s.f is not null),
         'marks_not_null', count(*) filter (where s.cp in (1564, 8204, 8205, 8206, 8207) and s.f is not null)) as j
  from (select g.cp, app.card_safe_text_failure('ab' || chr(g.cp) || 'cd', 'reason') as f,
               c.cp is not null as ctrl, n.cp is not null as num, cn.cp is not null as cnum,
               d.cp is not null as dl, l.cp is not null as lm
          from generate_series(1, 1114111) g(cp)
          left join (select distinct x.cp from _fr_c1cp x where x.cls in ('di_refused', 'ctrl_other')) c on c.cp = g.cp
          left join (select x.cp from _fr_c1cp x where x.cls = 'numeric') n on n.cp = g.cp
          left join (select x.cp from _fr_c1cp x where x.cls = 'canon_numeric') cn on cn.cp = g.cp
          left join (select x.cp from _fr_c1cp x where x.cls = 'digit') d on d.cp = g.cp
          left join (select x.cp from _fr_c1cp x where x.cls = 'lm') l on l.cp = g.cp
         where g.cp not between 55296 and 57343) s;
select is((select jsonb_build_object('swept', j -> 'swept', 'control_verdicts', j -> 'control_verdicts',
                                     'control_class', j -> 'control_class', 'control_mismatch', j -> 'control_mismatch')
             from _fr_c1sweep),
          '{"swept": 1112063, "control_verdicts": 4267, "control_class": 4267, "control_mismatch": 0}'::jsonb,
  'FR-295 C1-4 rule 1 two-sided over the whole code space (U+0001..U+10FFFF without surrogates, 1112063 code points, each inside a visible reason): control_character answers for exactly the 4267 refused controls of FR-293 + FR-294 and for no other code point');
select is_empty($$ select * from pg_temp.fr_c1_bad('MARKS')
                   union all
                   select 'sweep marks_not_null=' || (j ->> 'marks_not_null') from _fr_c1sweep
                    where (j ->> 'marks_not_null')::integer <> 0 $$,
  'FR-296 C1-4 rule 1: the five allowed marks U+061C, U+200C, U+200D, U+200E, U+200F are not refused: each passes inside visible Arabic text, inside visible Hebrew text, around a Hebrew word (order_freed_note) and inside the sweep; each ALONE -> length (rule 5: no visible letter)');
select is_empty($$ select * from pg_temp.fr_c1_bad('FILL') $$,
  'FR-297 C1-4 rule 1: each of the four Hangul fillers U+115F, U+1160, U+3164, U+FFA0 -> control_character between three generated 4-digit groups, inside an English and an Arabic reason, leading, trailing (never trimmed) and inside an order_freed_note; the canonical forms too');
select is_empty($$ select format('%s alone=%s inside=%s ref=%s', pg_temp.fr_c1_u(c.cp),
                                 coalesce(app.card_safe_text_failure(chr(c.cp), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure('REF-' || chr(c.cp), 'provider_reference'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'numeric'
                      and (app.card_safe_text_failure(chr(c.cp), 'reason') is distinct from 'charset'
                           or app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason') is distinct from 'charset'
                           or app.card_safe_text_failure('REF-' || chr(c.cp), 'provider_reference') is distinct from 'charset')
                   union all
                   select format('sweep numeric_class=%s numeric_not_charset=%s', j ->> 'numeric_class', j ->> 'numeric_not_charset')
                     from _fr_c1sweep where (j ->> 'numeric_class')::integer <> 1114 or (j ->> 'numeric_not_charset')::integer <> 0 $$,
  'FR-298 C1-4 rule 2 (exhaustive, raw): each of the 1114 Numeric_Type=Numeric code points (fractions, Roman numerals, circled / parenthesized ten and above, CJK numerals, Ethiopic tens ...) -> charset alone, inside a visible reason, after REF- as a provider_reference and in the sweep');
select results_eq($$ select v.label, v.field, app.card_safe_text_failure(v.val, v.field),
                            app.card_safe_text_failure(app.card_text_canonical(v.val), v.field)
                       from _fr_c1v v where v.grp = 'NUMRAW' order by v.k $$,
  $$ values ('DEP- + U+216B (NFKC DEP-XII)', 'deposit_id', 'charset', null::text),
            ('V + U+2160 (NFKC VI)', 'voucher_number', 'charset', null::text),
            ('declined + U+216B (NFKC declinedXII)', 'approval_type', 'charset', null::text),
            ('MC + U+2169 (NFKC MCX)', 'card_brand_code', 'charset', null::text),
            ('Table + U+2167 (NFKC Table VIII)', 'reason', 'charset', null::text),
            ('Half + U+00BD (NFKC 1 U+2044 2)', 'reason', 'charset', null::text) $$,
  'FR-299 C1-4 rule 2 is judged on R: a Roman numeral or vulgar fraction whose NFKC satisfies the field grammar (deposit_id, voucher_number, approval_type, card_brand_code, reason) -> charset raw, while its canonical form alone would pass');
select is_empty($$ select format('%s numeric_raw=%s inside=%s', pg_temp.fr_c1_u(c.cp), pg_temp.fr_c1_is('numeric', c.cp),
                                 coalesce(app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'canon_numeric'
                      and (pg_temp.fr_c1_is('numeric', c.cp)
                           or app.card_safe_text_failure('Ab ' || chr(c.cp) || ' cd', 'reason') is distinct from 'charset')
                   union all
                   select format('sweep canon_numeric_class=%s canon_numeric_not_charset=%s', j ->> 'canon_numeric_class',
                                 j ->> 'canon_numeric_not_charset')
                     from _fr_c1sweep
                    where (j ->> 'canon_numeric_class')::integer <> 12 or (j ->> 'canon_numeric_not_charset')::integer <> 0 $$,
  'FR-300 C1-4 rule 4 (exhaustive): each of the 12 code points that are not Numeric but whose NFKC is (U+2F00, U+2F06, U+2F0B, U+2F17, U+2F33, U+2F36, U+FA05, U+1F214, U+1F229, U+1F22A, U+1F241, U+1F242) -> charset inside a visible reason (canonical Numeric)');
select is_empty($$ select * from pg_temp.fr_c1_bad('PREC') $$,
  'FR-301 C1-4 rule order on R: filler + Numeric -> control_character; 12 digits + Numeric -> charset; Numeric / filler in an 801-code-point value -> charset / control_character (before the 4 x max bound); 12 digits in 801 code points -> length (bound) and in 201 -> length (rule 5) but in 200 -> digit_run; 12 digits shaped as a masked form -> digit_run (rule 6 before 7); filler / Numeric inside a masked form -> control_character / charset; U+2F00 + 12 digits -> charset (rule 4 before 6)');
select is_empty($$ select format('%s x12=%s/%s x11=%s/%s', pg_temp.fr_c1_u(c.cp),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 12), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(app.card_text_canonical(repeat(chr(c.cp), 12)), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 11), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(app.card_text_canonical(repeat(chr(c.cp), 11)), 'reason'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'digit'
                      and (app.card_safe_text_failure(repeat(chr(c.cp), 12), 'reason') is distinct from 'digit_run'
                           or app.card_safe_text_failure(app.card_text_canonical(repeat(chr(c.cp), 12)), 'reason') is distinct from 'digit_run'
                           or app.card_safe_text_failure(repeat(chr(c.cp), 11), 'reason') is not null
                           or app.card_safe_text_failure(app.card_text_canonical(repeat(chr(c.cp), 11)), 'reason') is not null)
                   union all
                   select format('sweep digit_class=%s digit_not_null=%s', j ->> 'digit_class', j ->> 'digit_not_null')
                     from _fr_c1sweep where (j ->> 'digit_class')::integer <> 808 or (j ->> 'digit_not_null')::integer <> 0 $$,
  'FR-302 C1-4 rule 6 (exhaustive): each of the 808 digit-like code points (Numeric_Type Decimal 680 + Digit 128) repeated 12 times -> digit_run, raw and canonical; repeated 11 times -> passes, raw and canonical; one inside a visible reason passes (sweep)');
select is_empty($$ select pg_temp.fr_c1_u(c.cp) from _fr_c1cp c
                    where c.cls = 'digit' and pg_temp.fr_c1_dl(normalize(chr(c.cp), nfkc)) <> 1 order by c.cp $$,
  'FR-303 C1-4 raw and canonical counts: the NFKC of each of the 808 digit-like code points holds exactly one digit-like code point (so no digit-like value loses digits in C)');
select results_eq($$ select pg_temp.fr_c1_dl(chr(c.cp)) as raw_digits, pg_temp.fr_c1_dl(normalize(chr(c.cp), nfkc)) as canonical_digits,
                            count(*)::integer
                       from _fr_c1cp c where c.cls = 'canon_digit' group by 1, 2 order by 1, 2 $$,
  $$ values (0, 1, 40), (0, 2, 40) $$,
  'FR-304 harness (C1-4): the 80 NFKC-only digit producers (telegraph month / hour / day symbols U+32C0..U+32CB, U+3358..U+3370, U+33E0..U+33FE, squared units U+3378, U+3379, U+339F..U+33A6, U+33A8, U+33AF) hold no digit-like code point raw; their NFKC holds one (40) or two (40)');
select is_empty($$ select format('%s x12=%s xmin=%s xmin-1=%s', pg_temp.fr_c1_u(c.cp),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 12), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 12 / pg_temp.fr_c1_dl(normalize(chr(c.cp), nfkc))), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 12 / pg_temp.fr_c1_dl(normalize(chr(c.cp), nfkc)) - 1), 'reason'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'canon_digit'
                      and (app.card_safe_text_failure(repeat(chr(c.cp), 12), 'reason') is distinct from 'digit_run'
                           or app.card_safe_text_failure(repeat(chr(c.cp), 12 / pg_temp.fr_c1_dl(normalize(chr(c.cp), nfkc))), 'reason') is distinct from 'digit_run'
                           or app.card_safe_text_failure(repeat(chr(c.cp), 12 / pg_temp.fr_c1_dl(normalize(chr(c.cp), nfkc)) - 1), 'reason') is not null)
                    order by c.cp $$,
  'FR-305 C1-4 rule 6 counts C too (exhaustive over the 80 NFKC-only producers): 12 copies -> digit_run; exactly 12 canonical digit-like characters (12 copies of a one-digit producer, 6 of a two-digit one) -> digit_run; one copy fewer (11 / 5) -> passes');
select is_empty($$ select * from pg_temp.fr_c1_bad('S12') $$,
  'FR-306 C1-4 rule 6: 12 digit-like characters of each of the 12 families (ASCII, Arabic-Indic, extended Arabic-Indic, Devanagari, fullwidth, mathematical, superscript, circled, dingbat, double circled, Ethiopic, Thai) with one separator between each (a Latin / Arabic / Hebrew letter, the Lm letters U+0640, U+30FC, U+02CD, U+02D0, U+07FA, full stop, comma, hyphen, slash, colon, space, NBSP, U+3000, combining U+0301 / U+064B / U+05B8, dollar, plus, U+00A9, tilde, a word) -> digit_run, raw and canonical (288 of 288)');
select is_empty($$ select * from pg_temp.fr_c1_bad('S11') $$,
  'FR-307 C1-4 rule 6: the same 288 family x separator shapes with 11 digit-like characters pass, raw and canonical (the count decides, not the separators)');
select is_empty($$ select * from pg_temp.fr_c1_bad('M') $$,
  'FR-308 C1-4 rule 6: 12 digit-like characters each from another family (mixed scripts) -> digit_run with no separator, spaces, U+0640, Latin letters or space-slash-space between them; 11 -> passes; raw and canonical');
select is_empty($$ select * from pg_temp.fr_c1_bad('LMASK') $$,
  'FR-309 C1-4 rule 7: with the Lm letters U+0640, U+30FC, U+02CD, U+02D0, U+07FA as separators, 4 digits + Lm + * + Lm + 4 digits, 4 digits + Lm + 4 x U+2022 + Lm + 4 digits, *** + Lm + 4 digits, 4 digits + Lm + ### and 4 Arabic-Indic digits + Lm + X + Lm + 4 Arabic-Indic digits -> masked_pattern, while 4 digits + Lm + 4 digits (no mask) passes; raw and canonical');
select is_empty($$ select format('%s masked=%s plain=%s', pg_temp.fr_c1_u(c.cp),
                                 coalesce(app.card_safe_text_failure(pg_temp.fr_c1_d(4) || chr(c.cp) || '*' || chr(c.cp)
                                                                     || pg_temp.fr_c1_d(4, 'ascii', 6), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(pg_temp.fr_c1_d(4) || chr(c.cp) || pg_temp.fr_c1_d(4, 'ascii', 6), 'reason'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'lm'
                      and (app.card_safe_text_failure(pg_temp.fr_c1_d(4) || chr(c.cp) || '*' || chr(c.cp) || pg_temp.fr_c1_d(4, 'ascii', 6), 'reason')
                             is distinct from 'masked_pattern'
                           or app.card_safe_text_failure(pg_temp.fr_c1_d(4) || chr(c.cp) || pg_temp.fr_c1_d(4, 'ascii', 6), 'reason')
                             is distinct from (case when exists (select 1 from _fr_mask m where strpos(normalize(chr(c.cp), nfkc), m.cp) > 0)
                                                    then 'masked_pattern' end))
                   union all
                   select format('sweep lm_class=%s lm_not_null=%s', j ->> 'lm_class', j ->> 'lm_not_null')
                     from _fr_c1sweep where (j ->> 'lm_class')::integer <> 397 or (j ->> 'lm_not_null')::integer <> 0 $$,
  'FR-310 C1-4 rule 7 (exhaustive over the 397 Lm code points): 4 digits + Lm + * + Lm + 4 digits -> masked_pattern for every Lm (a separator); 4 digits + Lm + 4 digits passes unless the NFKC of the Lm is a mask code point (then masked_pattern via C); an Lm inside a visible reason passes (sweep)');
select results_eq($$ select pg_temp.fr_c1_u(c.cp) from _fr_c1cp c
                      where c.cls = 'lm' and exists (select 1 from _fr_mask m where strpos(normalize(chr(c.cp), nfkc), m.cp) > 0)
                      order by c.cp $$,
  $$ values ('U+02E3'), ('U+2093'), ('U+1E043'), ('U+1E061') $$,
  'FR-311 C1-4 rule 7 harness: exactly four Lm code points canonicalize to a mask code point (U+02E3 and U+2093 to x, U+1E043 and U+1E061 to Cyrillic U+0445), the ones FR-310 expects masked between bare digit groups');
select is_empty($$ select * from pg_temp.fr_c1_bad('FMASK') $$,
  'FR-312 C1-4 rules 1 + 7: each Hangul filler inside a masked form (4 digits + filler + * + filler + 4 digits, *** + filler + 4 digits, 4 digits + filler + ###, 4 digits + filler + 4 x U+2022 + filler + 4 digits) -> control_character first; raw and canonical');
select is_empty($$ select * from pg_temp.fr_c1_bad('LEN') $$,
  'FR-313 C1-4 rule 5: a reason or an order_freed_note with no visible letter or digit -> length: invisible-only (U+200E U+200F, the five allowed marks together, 3 x U+200C), mark-only (U+0300, 3 x U+0301, U+064B, U+0651 U+064E, U+05B8, U+05BC U+05B4, U+20DD, U+0903), U+2800-only (1, 3, spaced, inside edge spaces) and symbol / punctuation-only (*, ***, #, currency signs, +=, arrows, bullets, U+00A9, %, !?, ..., U+2014, a mixed invisible + mark + symbol run); raw and canonical (56 of 56)');
select is_empty($$ select * from pg_temp.fr_c1_bad('VIS') $$,
  'FR-314 C1-4 rule 5 is judged on C: U+FF9E / U+FF9F (Lm raw, NFKC combining marks U+3099 / U+309A) alone or together -> length; after a letter (a, U+30AB) they pass');
select is_empty($$ select * from pg_temp.fr_c1_bad('POS') $$,
  'FR-315 C1-4: legitimate reasons and order_freed_notes pass, raw and canonical: Arabic with a damma, U+061C and U+200F; Hebrew with niqqud, dagesh and U+200F; Hebrew with U+200E around a Latin code; English; English with combining acute marks on letters; Persian U+200C and Arabic U+200D; mixed Arabic + English + Hebrew; English and Arabic-Indic text with 11 digits across words (18 of 18)');
select is_empty($$ select * from pg_temp.fr_c1_bad('SHORT') $$,
  'FR-316 C1-4: short legitimate numeric values pass: a 6-digit and an 11-digit approval number, a 6-digit voucher with letters, ZC- + 11 digits, a 4-digit card_last4, a reason / order_freed_note with 11 digits across words, a reason with a date (8 digits); the 12-digit counterparts -> digit_run (approval number, provider reference, a 12th digit in the words, a date with a time)');
select results_eq($$ select v.label, v.field, char_length(v.val), char_length(app.card_text_canonical(v.val)),
                            app.card_safe_text_failure(v.val, v.field), app.card_safe_text_failure(app.card_text_canonical(v.val), v.field)
                       from _fr_c1v v where v.grp = 'POST' order by v.k $$,
  $$ values ('95 x U+FB00 + 12 digits', 'reason', 107, 202, 'length', 'length'),
            ('94 x U+FB00 + 12 digits', 'reason', 106, 200, 'digit_run', 'digit_run'),
            ('100 x U+33E0', 'reason', 100, 200, 'digit_run', 'digit_run'),
            ('101 x U+33E0', 'reason', 101, 202, 'length', 'length'),
            ('11 digits + U+33E0', 'reason', 12, 13, 'digit_run', 'digit_run'),
            ('10 digits + U+33E0', 'reason', 11, 12, null::text, null::text),
            ('95 x U+FB00 + 12 digits (note)', 'order_freed_note', 107, 202, 'length', 'length'),
            ('11 digits + U+33E0 (note)', 'order_freed_note', 12, 13, 'digit_run', 'digit_run') $$,
  'FR-317 C1-4 post-normalization limits: 95 x U+FB00 + 12 digits (107 raw, 202 canonical) -> length before digit_run while 94 x (200 canonical) -> digit_run; 100 x U+33E0 (200 canonical) -> digit_run, 101 x (202) -> length; 11 digits + U+33E0 (11 digit-like raw, 12 canonical) -> digit_run, 10 + U+33E0 passes; the canonical forms answer the same token');
select is_empty($$ select format('#%s %s', v.k, v.label) from _fr_c1v v
                    where app.card_text_canonical(app.card_text_canonical(v.val)) is distinct from app.card_text_canonical(v.val)
                   union all
                   select pg_temp.fr_c1_u(c.cp) from _fr_c1cp c
                    where app.card_text_canonical(app.card_text_canonical(chr(c.cp))) is distinct from app.card_text_canonical(chr(c.cp)) $$,
  'FR-318 C1-4: app.card_text_canonical is idempotent over every C1 vector and over every code point of the class table');
select results_eq($$ select grp, count(*)::integer, min(pg_temp.fr_c1_dl(val)), max(pg_temp.fr_c1_dl(val))
                       from _fr_c1v group by grp order by min(k) $$,
  $$ values ('MARKS', 20, 0, 0), ('FILL', 24, 0, 12), ('NUMRAW', 6, 0, 0), ('PREC', 11, 0, 12), ('S12', 288, 12, 12),
            ('S11', 288, 11, 11), ('M', 10, 11, 12), ('LMASK', 30, 4, 8), ('FMASK', 16, 4, 8), ('LEN', 56, 0, 0),
            ('VIS', 5, 0, 0), ('POS', 18, 0, 11), ('SHORT', 12, 4, 12), ('POST', 8, 0, 12) $$,
  'FR-319 harness (C1-4): the C1 vector groups hold exactly the counts named by FR-296..FR-317 and the digit-like counts they were built with (every S12 vector exactly 12, every S11 exactly 11, mixed-script 12 / 11, masked forms 4..8, every legitimate POS vector at most 11)');
select is_empty($$ select format('%s 4*4=%s/%s ***4=%s 4###=%s 3*4=%s **4=%s', pg_temp.fr_c1_u(c.cp),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 4) || '*' || repeat(chr(c.cp), 4), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(app.card_text_canonical(repeat(chr(c.cp), 4) || '*' || repeat(chr(c.cp), 4)), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure('***' || repeat(chr(c.cp), 4), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 4) || '###', 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure(repeat(chr(c.cp), 3) || '*' || repeat(chr(c.cp), 4), 'reason'), 'NULL'),
                                 coalesce(app.card_safe_text_failure('**' || repeat(chr(c.cp), 4), 'reason'), 'NULL'))
                     from _fr_c1cp c
                    where c.cls = 'digit'
                      and (app.card_safe_text_failure(repeat(chr(c.cp), 4) || '*' || repeat(chr(c.cp), 4), 'reason') is distinct from 'masked_pattern'
                           or app.card_safe_text_failure(app.card_text_canonical(repeat(chr(c.cp), 4) || '*' || repeat(chr(c.cp), 4)), 'reason')
                                is distinct from 'masked_pattern'
                           or app.card_safe_text_failure('***' || repeat(chr(c.cp), 4), 'reason') is distinct from 'masked_pattern'
                           or app.card_safe_text_failure(repeat(chr(c.cp), 4) || '###', 'reason') is distinct from 'masked_pattern'
                           or app.card_safe_text_failure(repeat(chr(c.cp), 3) || '*' || repeat(chr(c.cp), 4), 'reason') is not null
                           or app.card_safe_text_failure('**' || repeat(chr(c.cp), 4), 'reason') is not null)
                    order by c.cp $$,
  'FR-320 C1-4 rule 7 digit class (exhaustive): each of the 808 digit-like code points in the shapes 4 + * + 4 (raw and canonical), *** + 4 and 4 + ### -> masked_pattern, the dingbat, double circled, Ethiopic and other digits without an NFKC decomposition included; 3 + * + 4 and ** + 4 pass');

-- ---------------------------------------------------------------------------
-- 22 (cont.). C1-4 through card_attempt_finish, free_order and the operator
-- revision: an unsafe non-essential field is dropped with a closed {field,
-- rule, source} event; an unsafe essential field never approves; a refused
-- reason writes nothing. The values are generated here and never printed.
-- ---------------------------------------------------------------------------
create temp table _fr_c1txt (k text primary key, field text, v text not null);
grant select on _fr_c1txt to service_role;
insert into _fr_c1txt values
  ('ne_ref', 'provider_reference', 'REF-' || U&'\3164' || 'A'),
  ('ne_appr', 'approval_number', pg_temp.fr_c1_d(6) || 'B' || pg_temp.fr_c1_d(6, 'ascii', 8)),
  ('ne_vch', 'voucher_number', 'V' || U&'\2160'),
  ('ne_dep', 'deposit_id', 'DEP-' || U&'\216B'),
  ('ne_brand', 'card_brand_code', 'VISA' || U&'\FE0F'),
  ('ne_pan', 'pan_entry_mode', 'CHIP' || U&'\034F'),
  ('ne_pmc', 'payment_method_code', pg_temp.fr_c1_d(4) || 'A' || pg_temp.fr_c1_d(4, 'ascii', 6) || 'B' || pg_temp.fr_c1_d(4, 'ascii', 10)),
  ('at', 'approval_type', 'approved' || U&'\3164'),
  ('sc', 'provider_status_code', pg_temp.fr_c1_d(6) || 'a' || pg_temp.fr_c1_d(6, 'ascii', 8)),
  ('lk', 'provider_status_code', 'ok' || U&'\FE0F'),
  ('ld', 'approval_type', 'declined' || U&'\216B'),
  ('nl_vch', 'voucher_number', pg_temp.fr_c1_d(6) || 'C' || pg_temp.fr_c1_d(6, 'ascii', 8)),
  ('nl_brand', 'card_brand_code', 'MC' || U&'\180B'),
  ('fo_spread', 'reason', 'Manager note ' || pg_temp.fr_c1_d(6) || ' then ' || pg_temp.fr_c1_d(6, 'ascii', 8)),
  ('fo_invisible', 'reason', U&'\200F'),
  ('fo_filler', 'reason', 'Manager' || U&'\3164' || 'note'),
  ('fo_ok', 'reason', U&'\0623\064F\0644\063A\064A \0627\0644\0637\0644\0628\061C \0628\0637\0644\0628 \0627\0644\0632\0628\0648\0646\200F\3000'),
  ('op_spread', 'reason', 'Pilot pause ' || pg_temp.fr_c1_d(4) || ' step ' || pg_temp.fr_c1_d(4, 'ascii', 6) || ' ref ' || pg_temp.fr_c1_d(4, 'ascii', 10)),
  ('op_invisible', 'reason', U&'\200E\200F'),
  ('op_filler', 'reason', 'Pilot' || U&'\115F' || 'pause'),
  ('op_numeric', 'reason', 'Pilot pause ' || U&'\216B'),
  ('op_lm_mask', 'reason', pg_temp.fr_c1_d(4) || U&'\0640' || '**' || U&'\0640' || pg_temp.fr_c1_d(4, 'ascii', 6)),
  ('op_marks', 'reason', U&'\0301\0301');
create function pg_temp.fr_c1_t(p_k text) returns text language sql stable as $$ select v from _fr_c1txt where k = p_k $$;

select is(pg_temp.fr_live(array['w_ne', 'w_at', 'w_sc', 'w_lk', 'w_ld', 'w_nl', 'w_fo']), 7,
  'FR-321 setup: 7 more LIVE claims created on d1 for the C1-4 provider-field, free and operator checks (claim_created = true)');
select pg_temp.fr_snap('w-claims');
select ok((select count(*) = 7 and bool_and(action = 'card_attempt.started') from _fr_aud where k = 'w-claims')
          and not exists (select 1 from _fr_evt where k = 'w-claims'),
  'FR-322 setup: ... exactly 7 card_attempt.started and no private event');
select is(pg_temp.fr_do('w_ne-1', 'w_ne', 'commit', 'approved',
            pg_temp.zc_approved_fields()
              || (select jsonb_object_agg(t.field, t.v) from _fr_c1txt t where t.k like 'ne\_%')
              || jsonb_build_object('card_last4', pg_temp.fr_c1_d(4, 'ascii', 5))),
  'state=approved | class=approved_unrecorded | anomaly=- | charge=false | audit=card_attempt.approved | events=approval_number/digit_run/commit,card_brand_code/control_character/commit,deposit_id/charset/commit,pan_entry_mode/control_character/commit,payment_method_code/digit_run/commit,provider_reference/control_character/commit,voucher_number/charset/commit',
  'FR-323 C1-4 non-essential: a commit approval carrying seven fields unsafe only under the new rules (provider_reference with U+3164, approval_number and payment_method_code with 12 letter-separated digits, voucher_number with U+2160 and deposit_id with U+216B whose NFKC fits the grammar, card_brand_code with U+FE0F, pan_entry_mode with U+034F) -> approved, one field-drop event each with its exact rule');
select is((select jsonb_build_object('provider_reference_null', a.provider_reference is null,
                  'approval_number_null', a.approval_number is null, 'voucher_number_null', a.voucher_number is null,
                  'deposit_id_null', a.deposit_id is null, 'card_brand_code_null', a.card_brand_code is null,
                  'pan_entry_mode_null', a.pan_entry_mode is null, 'payment_method_code_null', a.payment_method_code is null,
                  'card_last4_kept', a.card_last4 = pg_temp.fr_c1_d(4, 'ascii', 5), 'approval_type', a.approval_type,
                  'approved_stamped', a.provider_approved_at is not null)
             from app.card_provider_attempts a where a.id = pg_temp.fr_rid('w_ne')),
  '{"provider_reference_null": true, "approval_number_null": true, "voucher_number_null": true, "deposit_id_null": true,
    "card_brand_code_null": true, "pan_entry_mode_null": true, "payment_method_code_null": true, "card_last4_kept": true,
    "approval_type": "approved", "approved_stamped": true}'::jsonb,
  'FR-324 C1-4 non-essential: ... the seven dropped fields are NULL on the ledger row while the safe card_last4 is stored and the approval stands');
select is(pg_temp.fr_do('w_at-1', 'w_at', 'commit', 'approved',
            pg_temp.zc_approved_fields() || jsonb_build_object('approval_type', pg_temp.fr_c1_t('at'))),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=approval_type/control_character/commit',
  'FR-325 C1-4 essential: a commit approval whose approval_type carries U+3164 -> unknown (never approved) + its approval_type/control_character event');
select is(pg_temp.fr_do('w_sc-1', 'w_sc', 'commit', 'approved',
            pg_temp.zc_approved_fields() || jsonb_build_object('provider_status_code', pg_temp.fr_c1_t('sc'))),
  'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=provider_status_code/digit_run/commit',
  'FR-326 C1-4 essential: a commit approval whose provider_status_code holds 12 digits split by a letter -> unknown (never approved) + its provider_status_code/digit_run event');
select is((select jsonb_object_agg(x.c, jsonb_build_object('approval_type_null', a.approval_type is null,
                    'approval_type_approved', a.approval_type is not distinct from 'approved',
                    'provider_status_code_null', a.provider_status_code is null,
                    'provider_status_code_ok1', a.provider_status_code is not distinct from 'ok1',
                    'approved_stamped', a.provider_approved_at is not null, 'state', a.state))
             from unnest(array['w_at', 'w_sc']) x(c) join app.card_provider_attempts a on a.id = pg_temp.fr_rid(x.c)),
  '{"w_at": {"approval_type_null": true, "approval_type_approved": false, "provider_status_code_null": false,
             "provider_status_code_ok1": true, "approved_stamped": false, "state": "unknown"},
    "w_sc": {"approval_type_null": false, "approval_type_approved": true, "provider_status_code_null": true,
             "provider_status_code_ok1": false, "approved_stamped": false, "state": "unknown"}}'::jsonb,
  'FR-327 C1-4 essential: ... on each row the refused essential field is NULL (the valid one beside it is stored), no provider_approved_at, state unknown');
select is(pg_temp.fr_do('w_lk-1', 'w_lk', 'lookup', 'approved',
            pg_temp.fr_ex() || jsonb_build_object('provider_status_code', pg_temp.fr_c1_t('lk'))),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=provider_status_code/control_character/lookup',
  'FR-328 C1-4 essential: an exact approved lookup whose provider_status_code carries U+FE0F -> out_of_contract anomaly with charge_may_exist (sent -> unknown, never approved) + its event');
select is(pg_temp.fr_do('w_ld-1', 'w_ld', 'lookup', 'declined', jsonb_build_object('approval_type', pg_temp.fr_c1_t('ld'))),
  'state=unknown | class=provider_anomaly | anomaly=out_of_contract | charge=true | audit=card_attempt.provider_anomaly,card_attempt.unknown | events=approval_type/charset/lookup',
  'FR-329 C1-4 essential: a declined lookup whose approval_type carries U+216B (NFKC would fit the grammar) -> out_of_contract anomaly (never declined) + its approval_type/charset event');
select is((select jsonb_object_agg(x.c, jsonb_build_object('approval_type_null', a.approval_type is null,
                    'provider_status_code_null', a.provider_status_code is null, 'approved_stamped', a.provider_approved_at is not null,
                    'state', a.state, 'anomaly', a.provider_anomaly_code, 'charge_may_exist', a.charge_may_exist))
             from unnest(array['w_lk', 'w_ld']) x(c) join app.card_provider_attempts a on a.id = pg_temp.fr_rid(x.c)),
  '{"w_lk": {"approval_type_null": true, "provider_status_code_null": true, "approved_stamped": false, "state": "unknown",
             "anomaly": "out_of_contract", "charge_may_exist": true},
    "w_ld": {"approval_type_null": true, "provider_status_code_null": true, "approved_stamped": false, "state": "unknown",
             "anomaly": "out_of_contract", "charge_may_exist": true}}'::jsonb,
  'FR-330 C1-4 essential: ... neither anomalous row stores the refused field (approval_type / provider_status_code NULL) or provider_approved_at; state unknown, out_of_contract, charge_may_exist');
select pg_temp.fr_fin('w_nl-1', 'w_nl', 'commit', 'unknown');
select pg_temp.fr_fin('w_nl-2', 'w_nl', 'lookup', 'not_found',
                      jsonb_build_object('voucher_number', pg_temp.fr_c1_t('nl_vch'), 'card_brand_code', pg_temp.fr_c1_t('nl_brand')));
select results_eq($$ select k, pg_temp.fr_sig(k), (after_row ->> 'voucher_number') is null, (after_row ->> 'card_brand_code') is null
                       from _fr_call where k in ('w_nl-1', 'w_nl-2') order by k $$,
  $$ values ('w_nl-1', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-', true, true),
            ('w_nl-2', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=card_brand_code/control_character/lookup,voucher_number/digit_run/lookup', true, true) $$,
  'FR-331 C1-4 non-essential on a lookup: after a commit unknown, a not_found lookup carrying a voucher_number of 12 letter-separated digits and a card_brand_code with U+180B drops both (NULL) with their events, no audit, state unchanged');
select results_eq($$ select e.k, e.detail, e.attempt_row_id = pg_temp.fr_rid(split_part(e.k, '-', 1)), e.mode,
                            e.organization_id = pg_temp.zc_org() and e.restaurant_id = pg_temp.zc_rest()
                              and e.branch_id = pg_temp.zc_branch() and e.device_id = pg_temp.zc_id('device-1'),
                            e.actor_kind, e.actor_reference
                       from _fr_evt e where e.k like 'w\_%' order by e.k, e.detail ->> 'field' $$,
  $$ select x.k, jsonb_build_object('field', x.field, 'rule', x.rule, 'source', x.source), true, 'live', true, 'adapter', 'card_adapter'
       from (values ('w_at-1', 'approval_type', 'control_character', 'commit'),
                    ('w_ld-1', 'approval_type', 'charset', 'lookup'),
                    ('w_lk-1', 'provider_status_code', 'control_character', 'lookup'),
                    ('w_ne-1', 'approval_number', 'digit_run', 'commit'),
                    ('w_ne-1', 'card_brand_code', 'control_character', 'commit'),
                    ('w_ne-1', 'deposit_id', 'charset', 'commit'),
                    ('w_ne-1', 'pan_entry_mode', 'control_character', 'commit'),
                    ('w_ne-1', 'payment_method_code', 'digit_run', 'commit'),
                    ('w_ne-1', 'provider_reference', 'control_character', 'commit'),
                    ('w_ne-1', 'voucher_number', 'charset', 'commit'),
                    ('w_nl-2', 'card_brand_code', 'control_character', 'lookup'),
                    ('w_nl-2', 'voucher_number', 'digit_run', 'lookup'),
                    ('w_sc-1', 'provider_status_code', 'digit_run', 'commit')) x(k, field, rule, source)
      order by x.k, x.field $$,
  'FR-332 C1-4: the finishes wrote exactly 13 private events, each security.card_provider_field_dropped with the closed detail {field, rule, source} (no value), on its own LIVE attempt row (pilot organization / restaurant / branch, device d1), actor adapter / card_adapter');
select is_empty($$ select t.k || ' in ' || x.w from _fr_c1txt t
                    cross join lateral (
                      select 'attempt' as w from app.card_provider_attempts a
                       where a.organization_id = pg_temp.zc_org() and strpos(to_jsonb(a)::text, t.v) > 0
                      union all select 'event' from app.card_provider_private_events e where strpos(to_jsonb(e)::text, t.v) > 0
                      union all select 'audit' from public.audit_events ae
                       where ae.organization_id = pg_temp.zc_org() and strpos(to_jsonb(ae)::text, t.v) > 0) x
                   where t.k in ('ne_ref', 'ne_appr', 'ne_vch', 'ne_dep', 'ne_brand', 'ne_pan', 'ne_pmc', 'at', 'sc', 'lk', 'ld', 'nl_vch', 'nl_brand') $$,
  'FR-333 C1-4: no ledger row, private event or audit row holds any of the 13 refused provider values');
select pg_temp.fr_fin('w_fo-1', 'w_fo', 'commit', 'unknown');
select pg_temp.fr_fin('w_fo-2', 'w_fo', 'lookup', 'not_found');
select results_eq($$ select k, pg_temp.fr_sig(k) from _fr_call where k in ('w_fo-1', 'w_fo-2') order by k $$,
  $$ values ('w_fo-1', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=card_attempt.unknown | events=-'),
            ('w_fo-2', 'state=unknown | class=in_progress | anomaly=- | charge=false | audit=- | events=-') $$,
  'FR-334 setup: the free_order attempt is unknown after one lookup (freeable with provider evidence)');
insert into _zc_r select 'w_fo-before', pg_temp.fr_row('w_fo');
select count(pg_temp.fr_svc(x.k, format('select public.card_attempt_free_order(%L::uuid, %L::uuid, %L, %L, (select v from _fr_c1txt where k = %L), %L, %L, pg_temp.zc_caller())',
                                        pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('fr-w_fo'),
                                        x.t, 'provider_report', 'zc-conf/ref-78')))
  from (values ('w_fo-x1', 'fo_spread'), ('w_fo-x2', 'fo_invisible'), ('w_fo-x3', 'fo_filler')) x(k, t);
select results_eq($$ select label, r - 'server_ts' from _zc_r where label in ('w_fo-x1', 'w_fo-x2', 'w_fo-x3') order by label $$,
  $$ values ('w_fo-x1', '{"ok": false, "error": "precondition_failed", "detail": "out_of_contract"}'::jsonb),
            ('w_fo-x2', '{"ok": false, "error": "precondition_failed", "detail": "out_of_contract"}'::jsonb),
            ('w_fo-x3', '{"ok": false, "error": "precondition_failed", "detail": "out_of_contract"}'::jsonb) $$,
  'FR-335 C1-4 free_order: the manager''s reason with 12 digits split by words, an invisible-only reason (U+200F) and a reason with U+3164 -> each {ok:false, error:precondition_failed, detail:out_of_contract}');
select ok(not exists (select 1 from _fr_aud where k in ('w_fo-x1', 'w_fo-x2', 'w_fo-x3'))
          and not exists (select 1 from _fr_evt where k in ('w_fo-x1', 'w_fo-x2', 'w_fo-x3'))
          and pg_temp.fr_row('w_fo') = (select r from _zc_r where label = 'w_fo-before')
          and (select a.order_freed_at is null and a.order_freed_note is null from app.card_provider_attempts a where a.id = pg_temp.fr_rid('w_fo')),
  'FR-336 C1-4 free_order: ... the three refusals wrote no audit row and no private event, and the ledger row is byte-identical (order not freed, no note)');
select is(pg_temp.fr_svc('w_fo-ok', format('select public.card_attempt_free_order(%L::uuid, %L::uuid, %L, %L, (select v from _fr_c1txt where k = %L), %L, %L, pg_temp.zc_caller())',
            pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'), 'zc-token-1', pg_temp.zc_lop('fr-w_fo'), 'fo_ok',
            'provider_report', 'zc-conf/ref-78')) ->> 'classification', 'freed',
  'FR-337 C1-4 free_order: the same free with an Arabic reason carrying a damma, U+061C, U+200F and a trailing U+3000 -> freed');
select ok((select a.order_freed_note = U&'\0623\064F\0644\063A\064A \0627\0644\0637\0644\0628\061C \0628\0637\0644\0628 \0627\0644\0632\0628\0648\0646\200F'
                  and a.order_freed_note = app.card_text_canonical(pg_temp.fr_c1_t('fo_ok'))
                  and a.confirmation_reference = 'zc-conf/ref-78'
             from app.card_provider_attempts a where a.id = pg_temp.fr_rid('w_fo'))
          and (select count(*) = 1 and bool_and(action = 'card_attempt.order_freed')
                      and bool_and(actor_employee_profile_id = pg_temp.zc_id('employee-2'))
                 from _fr_aud where k = 'w_fo-ok')
          and not exists (select 1 from _fr_evt where k = 'w_fo-ok'),
  'FR-338 C1-4 free_order: ... the note is stored canonical (trailing U+3000 trimmed; the damma, U+061C and U+200F kept) with one card_attempt.order_freed by the manager and no private event');
select pg_temp.fr_snap('w-op-pre');
create temp table _fr_c1op as
select t.k, (select count(*) from app.card_payments_pilot_revisions r where r.organization_id = pg_temp.zc_org()) as before_n,
       app.set_card_payments_pilot(false, 'test', null, null, null, t.v, 'zc001d-op/ref-12', pg_temp.zc_owner()) as r
  from _fr_c1txt t where t.k like 'op\_%' order by t.k;
select results_eq($$ select k, r - 'server_ts' from _fr_c1op order by k $$,
  $$ select x.k, '{"ok": false, "error": "precondition_failed", "detail": "out_of_contract"}'::jsonb
       from unnest(array['op_filler', 'op_invisible', 'op_lm_mask', 'op_marks', 'op_numeric', 'op_spread']) x(k) order by x.k $$,
  'FR-339 C1-4 operator revision: app.set_card_payments_pilot with a reason holding U+115F, an invisible-only reason (U+200E U+200F), 8 digits around U+0640 + ** (masked), a mark-only reason, a Roman numeral, or 12 digits split by words -> each {ok:false, error:precondition_failed, detail:out_of_contract}');
select ok((select bool_and(o.before_n = (select count(*) from app.card_payments_pilot_revisions r where r.organization_id = pg_temp.zc_org()))
             from _fr_c1op o)
          and pg_temp.fr_snap('w-op') = 0,
  'FR-340 C1-4 operator revision: ... the six refusals added no revision row, no audit row and no private event');
select throws_ok($$ insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode,
                      window_until, reason, operator_reference, actor_app_user_id, executor_principal)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), false, 'test', now() + interval '1 hour',
                      (select v from _fr_c1txt where k = 'op_spread'), 'zc001d-op/ref-13', pg_temp.zc_owner(), 'zc001d-fr') $$,
  '23514', 'new row for relation "card_payments_pilot_revisions" violates check constraint "card_pilot_revisions_reason"',
  'FR-341 C1-4 last boundary: a direct owner INSERT of a canonical reason holding 12 digits split by words -> CHECK 23514 (card_pilot_revisions_reason)');
select throws_ok($$ insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode,
                      window_until, reason, operator_reference, actor_app_user_id, executor_principal)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), false, 'test', now() + interval '1 hour',
                      (select v from _fr_c1txt where k = 'op_filler'), 'zc001d-op/ref-13', pg_temp.zc_owner(), 'zc001d-fr') $$,
  '23514', 'new row for relation "card_payments_pilot_revisions" violates check constraint "card_pilot_revisions_reason"',
  'FR-342 C1-4 last boundary: a direct owner INSERT of a canonical reason holding the Hangul filler U+115F -> CHECK 23514 (card_pilot_revisions_reason)');

select is((select count(*) from _fr_aud where k like 'pre:%') + (select count(*) from _fr_evt where k like 'pre:%'), 0::bigint,
  'FR-343 harness: every audit row and private event of section 22 too was attributed to the call that wrote it');

select * from finish();
rollback;
