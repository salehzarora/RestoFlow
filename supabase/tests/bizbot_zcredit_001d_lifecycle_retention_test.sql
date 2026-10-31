-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: operator lifecycle and TEST retention (T-023 LR lane). Rollback-only synthetic fixtures, real SQL roles.
-- Proves: the operator revision (attested approver, executor, append-only, NULL window default, M6 caps, latest row
-- current); the pin_session_capabilities card_terminal_* keys; the terminal binding (creation, lifecycle steps and
-- their single events, rotation, one admitting binding per organization, one current binding per device, the
-- payment_create_pending / attempt_unresolved gates, device scope, immutability and credential-reference ownership);
-- the orphan resolution and the TEST closure; TEST incident holds; the TEST purge with identity tombstones; and the
-- immutability of private events and tombstones. Operator RPCs run as the migration owner, the adapter calls as
-- service_role. Time travel: the owner-only aging helpers below (the fixture's session_replication_role helpers are
-- tried first and fall back to disabling the one guard trigger for one UPDATE when this role may not set that GUC).
-- Review-fix sections 10-14: the operator reference / attested approver order of the five operator RPCs (fix 7),
-- the contract-literal inactive / deleted device (item 9), the LIVE free_order refusal matrix with its denial
-- evidence, the ledger trigger rules (fix 10) and the executor principal of the operator RPCs.
-- Fix-batch sections 15-16: a refused set_card_payments_pilot holds no pilot-revision advisory lock (change 24; its
-- probes are captured just before section 1, while this transaction holds no advisory lock yet) and the TEST purge
-- keeps the events of an attempt that still exists on a device whose terminal lock it did not take (change 25).
-- Correction C1 (sections 7, 10, 11 and 16 amended, 17-18 new): C1-2 the inactive-device shutdown (an inactive,
-- deleted or management-revoked pilot POS device still drains and retires under every unchanged gate; configured /
-- enabled need an active device) and C1-3 the bounded-batch TEST purge (p_max_devices, deferred counts, devices
-- locked, the device-set-bound deletes, rollback on failure, the card_events_test_device CHECK).
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

-- =============================================================================
-- LR helpers (migration-owner session; every row is synthetic and rolled back).
-- =============================================================================
-- Private-event snapshots: lr_new_events() = the events written since the last lr_snap().
create temp table _lr_seen (id uuid primary key);
create function pg_temp.lr_snap() returns void language sql volatile as $$
  insert into _lr_seen select e.id from app.card_provider_private_events e on conflict do nothing;
$$;
create function pg_temp.lr_new_events() returns setof app.card_provider_private_events language sql stable as $$
  select e.* from app.card_provider_private_events e
   where not exists (select 1 from _lr_seen s where s.id = e.id)
   order by e.created_at, e.id;
$$;
create function pg_temp.lr_keys(p_j jsonb) returns text[] language sql immutable as $$
  select coalesce(array_agg(k order by k), '{}'::text[]) from jsonb_object_keys(p_j) k;
$$;
create function pg_temp.lr_refusal(p_error text, p_detail text default null) returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'error', p_error)
         || case when p_detail is null then '{}'::jsonb else jsonb_build_object('detail', p_detail) end;
$$;
-- A captured result without its server_ts (the 4.35 item 4 refusal shape is {ok:false, error, detail?};
-- server_ts is neither required nor forbidden here, every other key is compared exactly).
create function pg_temp.lr_r(p_label text) returns jsonb language sql stable as $$
  select case when jsonb_typeof(r) = 'object' then r - 'server_ts' else r end from _zc_r where label = p_label;
$$;
create function pg_temp.lr_aid(p_label text) returns uuid language sql stable as $$
  select (r ->> 'attempt_row_id')::uuid from _zc_r where label = p_label;
$$;
create function pg_temp.lr_rev_count() returns bigint language sql stable as $$
  select count(*) from app.card_payments_pilot_revisions;
$$;
-- The database executor as text with the default collation (session_user is a C-collated name; a
-- record comparison in results_eq cannot mix the two collations).
create function pg_temp.lr_exec() returns text language sql stable as $$
  select session_user::text collate "default";
$$;
create function pg_temp.lr_audit_count() returns bigint language sql stable as $$
  select count(*) from public.audit_events where organization_id = pg_temp.zc_org();
$$;
-- The operator revision with LR defaults (the attested approver = staff 9, org_owner).
create function pg_temp.lr_pilot(p_enabled boolean, p_mode text, p_window timestamptz default null,
                                 p_test_cap bigint default 5000, p_live_cap bigint default 1000000,
                                 p_reason text default 'ZC001D LR revision', p_ref text default 'zc001d-lr/rev-1',
                                 p_actor uuid default pg_temp.zc_id('user-9'))
returns jsonb language sql volatile as $$
  select app.set_card_payments_pilot(p_enabled, p_mode, p_window, p_test_cap, p_live_cap, p_reason, p_ref, p_actor);
$$;
-- The terminal binding call with LR defaults.
create function pg_temp.lr_term(p_d integer, p_mode text, p_lifecycle text, p_term text, p_cred text,
                                p_reason_code text default 'test_setup', p_actor uuid default pg_temp.zc_id('user-9'),
                                p_reason text default 'ZC001D LR binding', p_ref text default 'zc001d-lr/bind-1')
returns jsonb language sql volatile as $$
  select app.set_payment_terminal(pg_temp.zc_id('device-' || p_d), p_mode, p_term, p_cred, p_lifecycle,
                                  p_reason_code, p_reason, p_ref, p_actor);
$$;
create function pg_temp.lr_current(p_d integer) returns setof app.payment_terminals language sql stable as $$
  select t.* from app.payment_terminals t
   where t.device_id = pg_temp.zc_id('device-' || p_d) and t.deleted_at is null and t.lifecycle <> 'retired';
$$;
-- Expected set_payment_terminal success result / private event.
create function pg_temp.lr_tres(p_mode text, p_prior text, p_new text, p_changed boolean default true)
returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', true, 'changed', p_changed, 'binding_mode', p_mode,
                            'prior_lifecycle', p_prior, 'new_lifecycle', p_new);
$$;
create function pg_temp.lr_tev(p_mode text, p_prior text, p_new text, p_admitted boolean, p_reason_code text)
returns jsonb language sql immutable as $$
  select jsonb_build_object('action', 'operator.payment_terminal_updated',
    'detail', jsonb_build_object('binding_mode', p_mode, 'prior_lifecycle', p_prior, 'new_lifecycle', p_new,
                                 'starts_admitted', p_admitted, 'reason_code', p_reason_code));
$$;
-- A step = the captured result + the (action, detail) of every event written since the last snapshot.
create function pg_temp.lr_step(p_label text) returns jsonb language sql stable as $$
  select jsonb_build_object('result', pg_temp.lr_r(p_label),
    'events', coalesce((select jsonb_agg(jsonb_build_object('action', e.action, 'detail', e.detail)
                                         order by e.created_at, e.id)
                          from pg_temp.lr_new_events() e), '[]'::jsonb));
$$;
-- pin_session_capabilities of staff n on device d; its card_terminal_* subset; the rest of it.
create function pg_temp.lr_caps(p_n integer, p_d integer) returns jsonb language sql stable as $$
  select app.pin_session_capabilities(pg_temp.zc_id('pin-' || p_n), pg_temp.zc_id('device-' || p_d));
$$;
create function pg_temp.lr_card_keys(p_n integer, p_d integer) returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
    from jsonb_each(pg_temp.lr_caps(p_n, p_d) -> 'branch_features') e
   where e.key like 'card\_terminal\_%';
$$;
create function pg_temp.lr_caps_rest(p_n integer, p_d integer) returns jsonb language sql stable as $$
  select (c - 'branch_features')
         || jsonb_build_object('branch_features',
                               (c -> 'branch_features') - 'card_terminal_enabled' - 'card_terminal_mode')
    from (select pg_temp.lr_caps(p_n, p_d) as c) s;
$$;
-- A claim through the service wrapper with explicit references (call under SET LOCAL ROLE service_role).
create function pg_temp.lr_claim(p_n integer, p_lop text, p_mode text, p_amount bigint, p_order uuid,
                                 p_expected_revision integer, p_term text, p_cred text)
returns jsonb language sql volatile as $$
  select public.card_attempt_claim(pg_temp.zc_id('pin-' || p_n),
    pg_temp.zc_id('device-' || pg_temp.zc_staff_device(p_n)), 'zc-token-' || pg_temp.zc_staff_device(p_n),
    p_lop, p_mode, p_amount, 'ILS', p_order, p_expected_revision,
    case p_mode when 'live' then 'production' else 'test' end,
    jsonb_build_object(p_term, p_cred),
    jsonb_build_object(p_cred, case p_mode
      when 'live' then jsonb_build_object('mode', 'live', 'scope', 'merchant', 'restaurant_id', pg_temp.zc_rest())
      else jsonb_build_object('mode', 'test', 'scope', 'development') end),
    'alpha16-l32-v1', pg_temp.zc_caller());
$$;
-- Owner-only time travel (rolled back with the file): the fixture helper first; when this role may
-- not set session_replication_role, the one guard trigger is disabled for exactly one UPDATE.
create function pg_temp.lr_age_attempt(p_id uuid, p_deadline_past boolean default true,
                                       p_retention_past boolean default false)
returns void language plpgsql volatile as $$
begin
  begin
    perform pg_temp.zc_age_attempt(p_id, p_deadline_past, p_retention_past);
    return;
  exception when insufficient_privilege then
    null;
  end;
  alter table app.card_provider_attempts disable trigger card_attempts_guard;
  update app.card_provider_attempts a
     set start_deadline_at = case when p_deadline_past then now() - interval '1 second' else a.start_deadline_at end,
         retention_until = case when p_retention_past and a.mode = 'test' then now() - interval '1 second'
                                else a.retention_until end
   where a.id = p_id;
  alter table app.card_provider_attempts enable trigger card_attempts_guard;
end $$;
create function pg_temp.lr_age_event(p_id uuid) returns void language plpgsql volatile as $$
begin
  begin
    perform pg_temp.zc_age_event(p_id);
    return;
  exception when insufficient_privilege then
    null;
  end;
  alter table app.card_provider_private_events disable trigger card_events_guard;
  update app.card_provider_private_events e set retention_until = now() - interval '1 second'
   where e.id = p_id and e.mode = 'test';
  alter table app.card_provider_private_events enable trigger card_events_guard;
end $$;
-- A TEST attempt row inserted directly as the owner (every CHECK and the insert guard still apply):
-- used only where the binding gates make the state unreachable through the RPCs.
create function pg_temp.lr_insert_test_attempt(p_d integer, p_label text) returns uuid language sql volatile as $$
  insert into app.card_provider_attempts (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
      initiated_by_employee_profile_id, initiated_by_membership_id, mode, amount_minor, currency_code,
      terminal_ref, credential_ref, provider_status_digest, provider_duplicate_digest, provider_key_format_version,
      provider_query_key, provider_duplicate_key, retention_until, start_deadline_at)
  select dv.organization_id, dv.restaurant_id, dv.branch_id, dv.id, k.lop, pg_temp.zc_id('employee-1'),
         pg_temp.zc_id('membership-1'), 'test', 500, 'ILS', 'lr-term-direct', 'lr-cred-direct', k.sd, k.dd,
         'alpha16-l32-v1', app.card_provider_key(k.sd, 'alpha16-l32-v1'), app.card_provider_key(k.dd, 'alpha16-l32-v1'),
         clock_timestamp() + interval '90 days', clock_timestamp() + interval '120 seconds'
    from public.devices dv
    cross join lateral (select pg_temp.zc_lop(p_label) as lop) l
    cross join lateral (select l.lop,
                               app.card_identity_digest('card-status-key/v1', dv.organization_id, dv.id, l.lop) as sd,
                               app.card_identity_digest('card-duplicate-key/v1', dv.organization_id, dv.id, l.lop) as dd) k
   where dv.id = pg_temp.zc_id('device-' || p_d)
  returning id;
$$;
create function pg_temp.lr_void(p_order uuid) returns void language sql volatile as $$
  update public.orders set status = 'voided', voided_at = now(), voided_from_status = status where id = p_order;
$$;
-- Run one statement; answer its SQLSTATE (or 'no_error'). Used to probe trigger-guarded columns.
create function pg_temp.lr_try(p_sql text) returns text language plpgsql volatile as $$
begin
  execute p_sql;
  return 'no_error';
exception when others then
  return sqlstate;
end $$;
create function pg_temp.lr_purge_counts() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'live_attempts', (select count(*) from app.card_provider_attempts a where a.mode = 'live'),
    'test_attempts', (select count(*) from app.card_provider_attempts a where a.mode = 'test'),
    'operator_events', (select count(*) from app.card_provider_private_events e where e.action like 'operator.%'),
    'live_events', (select count(*) from app.card_provider_private_events e where e.mode = 'live'),
    'test_events', (select count(*) from app.card_provider_private_events e where e.mode = 'test'),
    'tombstones', (select count(*) from app.card_attempt_identity_tombstones));
$$;
-- Extra synthetic approvers / non-approvers of the attested-approver check.
insert into app_users (id, email) values
  (pg_temp.zc_id('user-lr-ro'), 'zc001d-lr-ro@example.test'),
  (pg_temp.zc_id('user-lr-fo'), 'zc001d-lr-fo@example.test'),
  (pg_temp.zc_id('user-lr-rv'), 'zc001d-lr-rv@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status) values
  (pg_temp.zc_id('membership-lr-ro'), pg_temp.zc_id('user-lr-ro'), pg_temp.zc_org(), pg_temp.zc_rest(), null,
   'restaurant_owner', 'active'),
  (pg_temp.zc_id('membership-lr-fo'), pg_temp.zc_id('user-lr-fo'), pg_temp.zc_id('org_b'), null, null,
   'org_owner', 'active'),
  (pg_temp.zc_id('membership-lr-rv'), pg_temp.zc_id('user-lr-rv'), pg_temp.zc_org(), null, null,
   'org_owner', 'revoked');

-- =============================================================================
-- 0. Baseline: no revision and no binding exist yet.
-- =============================================================================
insert into _zc_r select 'caps_base_1', pg_temp.lr_caps(1, 1);
insert into _zc_r select 'caps_base_8', pg_temp.lr_caps(8, 2);
select is(jsonb_build_object('ok', pg_temp.lr_r('caps_base_1') -> 'ok',
                             'branch_feature_keys', to_jsonb(pg_temp.lr_keys(pg_temp.lr_r('caps_base_1') -> 'branch_features')),
                             'd2_card_keys', pg_temp.lr_card_keys(8, 2)),
  jsonb_build_object('ok', true,
                     'branch_feature_keys', jsonb_build_array('order_edit_enabled', 'order_edit_finished_food_manager_only'),
                     'd2_card_keys', '{}'::jsonb),
  'LR-01 capabilities with no binding: a valid response whose branch_features carry no card_terminal_* key (d1 and d2)');

-- =============================================================================
-- Capture for section 15 (fix batch 6, change 24; asserted at the end of the file as LR-183 .. LR-189). The
-- pilot-revision lock is a transaction-level advisory lock that only this file's ROLLBACK releases, and every
-- accepted set_card_payments_pilot takes it, so the probes run here, before this transaction draws its first
-- revision: each call below is followed by its own read of pg_locks for the current backend. Nothing is asserted
-- here; the seven refusals write nothing (LR-188) and the one accepted call appends an OFF TEST revision by the
-- attested approver (staff 9) that no later section reads (each reads the revision it appends, or the latest one).
-- =============================================================================
-- The current backend's advisory locks on hashtextextended('card-pilot-revision/v1:<pilot org>:<pilot branch>', 0)
-- (a bigint key: classid = its high 32 bits, objid = its low 32 bits, objsubid 1) and its advisory locks in all.
create function pg_temp.lr_pilot_lock() returns jsonb language sql volatile as $$
  select jsonb_build_object(
    'pilot_revision_key', coalesce((select jsonb_agg(jsonb_build_object('mode', l.mode, 'granted', l.granted)
                                                     order by l.mode, l.granted)
                                      from pg_locks l
                                     where l.locktype = 'advisory' and l.pid = pg_backend_pid()
                                       and l.database = (select d.oid from pg_database d
                                                          where d.datname = current_database())
                                       and l.classid::bigint = (k.k >> 32) & 4294967295
                                       and l.objid::bigint = k.k & 4294967295 and l.objsubid = 1), '[]'::jsonb),
    'advisory_locks', (select count(*) from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid()))
    from (select hashtextextended('card-pilot-revision/v1:' || pg_temp.zc_org()::text || ':'
                                  || pg_temp.zc_branch()::text, 0) as k) k;
$$;
-- Everything a set_card_payments_pilot call could write: revision rows, private events, the pilot tenant audit.
create function pg_temp.lr_pilot_writes() returns jsonb language sql stable as $$
  select jsonb_build_object('revision_rows', pg_temp.lr_rev_count(),
                            'event_rows', (select count(*) from app.card_provider_private_events),
                            'audit_rows', pg_temp.lr_audit_count());
$$;
insert into _zc_r select 'lk_start', jsonb_build_object('locks', pg_temp.lr_pilot_lock(), 'writes', pg_temp.lr_pilot_writes());
insert into _zc_r select 'lk_invalid', pg_temp.lr_pilot(null, 'test', p_ref => 'zc001d-lr/lock-1');
insert into _zc_r select 'lk_invalid_locks', pg_temp.lr_pilot_lock();
insert into _zc_r select 'lk_actor', pg_temp.lr_pilot(true, 'test', p_ref => 'zc001d-lr/lock-1',
                                                      p_actor => pg_temp.zc_id('user-2'));
insert into _zc_r select 'lk_actor_locks', pg_temp.lr_pilot_lock();
insert into _zc_r select 'lk_absent_ref', pg_temp.lr_pilot(true, 'test', p_ref => null);
insert into _zc_r select 'lk_absent_ref_locks', pg_temp.lr_pilot_lock();
insert into _zc_r select 'lk_reason', pg_temp.lr_pilot(true, 'test', p_reason => null, p_ref => 'zc001d-lr/lock-1');
insert into _zc_r select 'lk_reason_locks', pg_temp.lr_pilot_lock();
insert into _zc_r select 'lk_window', pg_temp.lr_pilot(true, 'test', now() - interval '1 minute',
                                                       p_ref => 'zc001d-lr/lock-1');
insert into _zc_r select 'lk_window_locks', pg_temp.lr_pilot_lock();
insert into _zc_r select 'lk_test_cap', pg_temp.lr_pilot(true, 'test', null, null, 1000000, p_ref => 'zc001d-lr/lock-1');
insert into _zc_r select 'lk_test_cap_locks', pg_temp.lr_pilot_lock();
insert into _zc_r select 'lk_live_cap', pg_temp.lr_pilot(true, 'test', null, 5000, -1, p_ref => 'zc001d-lr/lock-1');
insert into _zc_r select 'lk_live_cap_locks', pg_temp.lr_pilot_lock();
insert into _zc_r select 'lk_writes', pg_temp.lr_pilot_writes();
insert into _zc_r select 'lk_ok', pg_temp.lr_pilot(false, 'test', p_ref => 'zc001d-lr/lock-ok');
insert into _zc_r select 'lk_ok_locks', pg_temp.lr_pilot_lock();

-- =============================================================================
-- 1. app.set_card_payments_pilot: the operator revision (D-057 points 6 / 8, M6).
-- =============================================================================
select pg_temp.lr_snap();
insert into _zc_r select 'rev_n0', to_jsonb(pg_temp.lr_rev_count());
insert into _zc_r select 'rev_a', app.set_card_payments_pilot(true, 'test', now() + interval '1 day', 5000, null,
  U&'\00A0\FF3A\FF23001D LR revision one ', U&' zc001d-lr/rev-1\3000', pg_temp.zc_id('user-9'));
select is(pg_temp.lr_r('rev_a') - 'revision',
  jsonb_build_object('ok', true, 'enabled', true, 'mode', 'test', 'window_until', now() + interval '1 day',
                     'max_test_amount_minor', 5000, 'max_live_amount_minor', null),
  'LR-02 set_card_payments_pilot by the attested approver (staff 9, org_owner): ok, echoing enabled / mode / window / caps');
select is(pg_temp.lr_rev_count() - (pg_temp.lr_r('rev_n0') #>> '{}')::bigint, 1::bigint,
  'LR-03 one call appends exactly one revision row');
select results_eq(
  $$ select p.revision, p.organization_id, p.restaurant_id, p.branch_id, p.enabled, p.mode, p.window_until,
            p.max_test_amount_minor, p.max_live_amount_minor, p.reason, p.operator_reference, p.actor_app_user_id,
            p.executor_principal
       from app.card_payments_pilot_revisions p order by p.revision desc limit 1 $$,
  $$ select (pg_temp.lr_r('rev_a') ->> 'revision')::bigint, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
            true, 'test'::text, now() + interval '1 day', 5000::bigint, null::bigint, 'ZC001D LR revision one'::text,
            'zc001d-lr/rev-1'::text, pg_temp.zc_id('user-9'), pg_temp.lr_exec() $$,
  'LR-04 the appended row is the latest (current) revision: pinned pilot scope, window, caps, NFKC + Zs-trimmed reason and operator reference, actor = staff 9, executor_principal = session_user');
select results_eq(
  $$ select e.action, e.actor_kind, e.actor_reference, e.actor_app_user_id, e.executor_principal, e.mode,
            e.retention_until, e.attempt_row_id, e.device_id, e.actor_employee_profile_id, e.reason,
            e.organization_id, e.restaurant_id, e.branch_id, e.incident_hold_at
       from pg_temp.lr_new_events() e $$,
  $$ values ('operator.card_payments_pilot_updated'::text, 'attested_owner_approver'::text, 'zc001d-lr/rev-1'::text,
             pg_temp.zc_id('user-9'), pg_temp.lr_exec(), null::text, null::timestamptz, null::uuid, null::uuid,
             null::uuid, 'ZC001D LR revision one'::text, pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
             null::timestamptz) $$,
  'LR-05 exactly one private event operator.card_payments_pilot_updated: attested_owner_approver, actor_reference = the canonical operator reference, executor_principal = session_user, mode NULL, no retention');
select is((select e.detail from pg_temp.lr_new_events() e),
  jsonb_build_object('enabled', true, 'mode', 'test', 'window_until', now() + interval '1 day',
                     'max_test_amount_minor', 5000, 'max_live_amount_minor', null),
  'LR-06 the revision event detail is exactly {enabled, mode, window_until, max_test_amount_minor, max_live_amount_minor}');

-- 1.1 The attested-approver check.
select pg_temp.lr_snap();
insert into _zc_r select 'rev_n1', to_jsonb(pg_temp.lr_rev_count());
insert into _zc_r select 'pd_staff2', pg_temp.lr_pilot(true, 'test', p_actor => pg_temp.zc_id('user-2'));
insert into _zc_r select 'pd_foreign_owner', pg_temp.lr_pilot(true, 'test', p_actor => pg_temp.zc_id('user-lr-fo'));
insert into _zc_r select 'pd_revoked_owner', pg_temp.lr_pilot(true, 'test', p_actor => pg_temp.zc_id('user-lr-rv'));
insert into _zc_r select 'pd_unknown', pg_temp.lr_pilot(true, 'test', p_actor => pg_temp.zc_id('user-lr-nobody'));
insert into _zc_r select 'pd_null', pg_temp.lr_pilot(true, 'test', p_actor => null);
select is((select jsonb_object_agg(label, r) from _zc_r
            where label in ('pd_staff2', 'pd_foreign_owner', 'pd_revoked_owner', 'pd_unknown', 'pd_null')),
  jsonb_build_object('pd_staff2', pg_temp.lr_refusal('permission_denied'),
                     'pd_foreign_owner', pg_temp.lr_refusal('permission_denied'),
                     'pd_revoked_owner', pg_temp.lr_refusal('permission_denied'),
                     'pd_unknown', pg_temp.lr_refusal('permission_denied'),
                     'pd_null', pg_temp.lr_refusal('permission_denied')),
  'LR-07 a non-owner actor (staff 2, manager), an org_owner of another organization, a revoked pilot org_owner, an unknown or NULL actor -> permission_denied');
select is(jsonb_build_object('revisions_added', pg_temp.lr_rev_count() - (pg_temp.lr_r('rev_n1') #>> '{}')::bigint,
                             'events', (select count(*) from pg_temp.lr_new_events())),
  '{"revisions_added": 0, "events": 0}'::jsonb,
  'LR-08 permission_denied writes nothing: no revision row, no private event');
insert into _zc_r select 'rev_ro', pg_temp.lr_pilot(true, 'test', p_ref => 'zc001d-lr/rev-ro',
                                                    p_actor => pg_temp.zc_id('user-lr-ro'));
select results_eq(
  $$ select (x.r ->> 'ok')::boolean, p.actor_app_user_id, e.action, e.actor_app_user_id, e.actor_reference
       from _zc_r x join app.card_payments_pilot_revisions p on p.revision = (x.r ->> 'revision')::bigint
       cross join pg_temp.lr_new_events() e where x.label = 'rev_ro' $$,
  $$ values (true, pg_temp.zc_id('user-lr-ro'), 'operator.card_payments_pilot_updated'::text,
             pg_temp.zc_id('user-lr-ro'), 'zc001d-lr/rev-ro'::text) $$,
  'LR-09 an active restaurant_owner of the pilot restaurant is an attested approver: one revision row and one event naming that actor');

-- 1.2 The window default.
insert into _zc_r select 'rev_c', pg_temp.lr_pilot(true, 'test', null);
select results_eq(
  $$ select (x.r ->> 'window_until')::timestamptz, p.window_until from _zc_r x
       join app.card_payments_pilot_revisions p on p.revision = (x.r ->> 'revision')::bigint where x.label = 'rev_c' $$,
  $$ values (now() + interval '12 hours', now() + interval '12 hours') $$,
  'LR-10 p_window_until NULL -> the fixed server default now() + 12 hours (result and stored row)');

-- 1.3 Refusals that write nothing.
select pg_temp.lr_snap();
insert into _zc_r select 'rev_n2', to_jsonb(pg_temp.lr_rev_count());
insert into _zc_r select 'oc_past', pg_temp.lr_pilot(true, 'test', now() - interval '1 minute');
insert into _zc_r select 'oc_now', pg_temp.lr_pilot(true, 'live', now());
insert into _zc_r select 'oc_card_reason', pg_temp.lr_pilot(true, 'test', p_reason => 'Refund for card ' || rtrim(repeat('7351 ', 4)));
insert into _zc_r select 'oc_masked_ref', pg_temp.lr_pilot(true, 'test', p_ref => 'zc001d/7351' || repeat('X', 4) || '9012');
insert into _zc_r select 'oc_null_reason', pg_temp.lr_pilot(true, 'test', p_reason => null);
insert into _zc_r select 'oc_blank_ref', pg_temp.lr_pilot(true, 'test', p_ref => U&'\00A0 ');
insert into _zc_r select 'oc_live_cap', pg_temp.lr_pilot(true, 'test', null, 5000, -1);
insert into _zc_r select 'ir_null_enabled', pg_temp.lr_pilot(null, 'test');
insert into _zc_r select 'ir_mode', pg_temp.lr_pilot(true, 'demo');
insert into _zc_r select 'mt_absent', pg_temp.lr_pilot(true, 'test', null, null, 1000);
insert into _zc_r select 'mt_zero', pg_temp.lr_pilot(true, 'test', null, 0, null);
insert into _zc_r select 'mt_negative', pg_temp.lr_pilot(true, 'test', null, -5, null);
insert into _zc_r select 'mt_over', pg_temp.lr_pilot(true, 'test', null, 100000000000, null);
select is(jsonb_build_array(pg_temp.lr_r('oc_past'), pg_temp.lr_r('oc_now')),
  jsonb_build_array(pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                    pg_temp.lr_refusal('precondition_failed', 'out_of_contract')),
  'LR-11 enabling with a past window, or a window equal to now(), -> precondition_failed / out_of_contract');
select is(pg_temp.lr_r('oc_card_reason'), pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
  'LR-12 a reason carrying a card number (16 digits in one separated run) -> precondition_failed / out_of_contract');
select is(jsonb_build_array(pg_temp.lr_r('oc_masked_ref'), pg_temp.lr_r('oc_null_reason'), pg_temp.lr_r('oc_blank_ref')),
  jsonb_build_array(pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                    pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                    pg_temp.lr_refusal('permission_denied')),
  'LR-13 an operator reference with a masked card pattern and a NULL reason -> out_of_contract; an operator reference of Space_Separators only (U+00A0 + space, blank after the canonical trim) is absent -> permission_denied (review fix 7)');
select is(pg_temp.lr_r('oc_live_cap'), pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
  'LR-14 enabling with an out-of-bound live cap (-1) beside a valid test cap -> out_of_contract');
select is(jsonb_build_array(pg_temp.lr_r('ir_null_enabled'), pg_temp.lr_r('ir_mode')),
  jsonb_build_array(pg_temp.lr_refusal('invalid_request'), pg_temp.lr_refusal('invalid_request')),
  'LR-15 p_enabled NULL or an unknown mode token -> invalid_request');
select is(jsonb_build_array(pg_temp.lr_r('mt_absent'), pg_temp.lr_r('mt_zero'), pg_temp.lr_r('mt_negative'),
                            pg_temp.lr_r('mt_over')),
  jsonb_build_array(pg_temp.lr_refusal('precondition_failed', 'max_test_amount_missing'),
                    pg_temp.lr_refusal('precondition_failed', 'max_test_amount_missing'),
                    pg_temp.lr_refusal('precondition_failed', 'max_test_amount_missing'),
                    pg_temp.lr_refusal('precondition_failed', 'max_test_amount_missing')),
  'LR-16 M6: ON TEST with an absent, zero, negative or out-of-bound test cap -> precondition_failed / max_test_amount_missing');
select is(jsonb_build_object('revisions_added', pg_temp.lr_rev_count() - (pg_temp.lr_r('rev_n2') #>> '{}')::bigint,
                             'events', (select count(*) from pg_temp.lr_new_events())),
  '{"revisions_added": 0, "events": 0}'::jsonb,
  'LR-17 none of those refusals appends a revision row or writes a private event');

-- 1.4 M6: an authorized OFF revision is always recordable; its invalid caps are stored NULL.
select pg_temp.lr_snap();
insert into _zc_r select 'off_absent', pg_temp.lr_pilot(false, 'test', null, null, null);
insert into _zc_r select 'off_zero', pg_temp.lr_pilot(false, 'test', null, 0, 0);
insert into _zc_r select 'off_negative', pg_temp.lr_pilot(false, 'live', null, -1, -500);
insert into _zc_r select 'off_past', pg_temp.lr_pilot(false, 'test', now() - interval '1 hour', 100000000000, null);
select results_eq(
  $$ select x.label, (x.r ->> 'ok')::boolean, p.enabled, p.mode, p.max_test_amount_minor, p.max_live_amount_minor,
            x.r -> 'max_test_amount_minor', x.r -> 'max_live_amount_minor'
       from _zc_r x join app.card_payments_pilot_revisions p on p.revision = (x.r ->> 'revision')::bigint
      where x.label in ('off_absent', 'off_zero', 'off_negative', 'off_past') order by p.revision $$,
  $$ values ('off_absent'::text, true, false, 'test'::text, null::bigint, null::bigint, 'null'::jsonb, 'null'::jsonb),
            ('off_zero', true, false, 'test', null, null, 'null', 'null'),
            ('off_negative', true, false, 'live', null, null, 'null', 'null'),
            ('off_past', true, false, 'test', null, null, 'null', 'null') $$,
  'LR-18 M6: OFF revisions with absent, zero, negative or out-of-bound caps are accepted and store both caps NULL');
select is((select p.window_until from _zc_r x join app.card_payments_pilot_revisions p
             on p.revision = (x.r ->> 'revision')::bigint where x.label = 'off_past'),
  now() - interval '1 hour',
  'LR-19 M6: an OFF revision with a past window is still recordable (window stored as given)');
select results_eq(
  $$ select e.action, e.detail -> 'enabled', e.detail -> 'max_test_amount_minor', e.detail -> 'max_live_amount_minor'
       from pg_temp.lr_new_events() e $$,
  $$ values ('operator.card_payments_pilot_updated'::text, 'false'::jsonb, 'null'::jsonb, 'null'::jsonb),
            ('operator.card_payments_pilot_updated', 'false', 'null', 'null'),
            ('operator.card_payments_pilot_updated', 'false', 'null', 'null'),
            ('operator.card_payments_pilot_updated', 'false', 'null', 'null') $$,
  'LR-20 M6: each OFF revision writes its own operator.card_payments_pilot_updated (enabled false, caps NULL)');

-- 1.5 M6: ON LIVE without a live cap is accepted; a LIVE claim under it is card_payments_disabled.
insert into _zc_r select 'rev_live_nocap', pg_temp.lr_pilot(true, 'live', null, null, null);
select is(pg_temp.lr_r('rev_live_nocap') - 'revision' - 'window_until',
  '{"ok": true, "enabled": true, "mode": "live", "max_test_amount_minor": null, "max_live_amount_minor": null}'::jsonb,
  'LR-21 M6: ON LIVE without a live cap is accepted by the setter (stored cap NULL)');
insert into _zc_r select 'bind_l_cfg', pg_temp.lr_term(1, 'live', 'configured', 'zc-term-live-1', 'zc-cred-live-1',
                                                       'live_activation');
select is(jsonb_build_object('bind', pg_temp.lr_r('bind_l_cfg') -> 'new_lifecycle', 'keys', pg_temp.lr_card_keys(1, 1)),
  '{"bind": "configured", "keys": {"card_terminal_enabled": false, "card_terminal_mode": "live"}}'::jsonb,
  'LR-22 capabilities: a configured binding of the exact device -> card_terminal_mode present, card_terminal_enabled false');
insert into _zc_r select 'bind_l_en', pg_temp.lr_term(1, 'live', 'enabled', 'zc-term-live-1', 'zc-cred-live-1',
                                                      'live_activation');
select pg_temp.zc_order('lr-r1', 1234);
set local role service_role;
insert into _zc_r select 'claim_nocap', pg_temp.zc_claim(1, pg_temp.zc_lop('lr-r1'), 'live', 1234,
                                                         pg_temp.zc_id('order-lr-r1'), 1);
reset role;
select is(jsonb_build_object('bind', pg_temp.lr_r('bind_l_en') -> 'new_lifecycle',
                             'claim', pg_temp.lr_r('claim_nocap') - 'server_ts',
                             'ledger_rows', (select count(*) from app.card_provider_attempts a
                                              where a.local_operation_id = pg_temp.zc_lop('lr-r1'))),
  jsonb_build_object('bind', 'enabled', 'claim', pg_temp.lr_refusal('card_payments_disabled'), 'ledger_rows', 0),
  'LR-23 M6: under the cap-less ON LIVE revision a LIVE claim (enabled binding) is card_payments_disabled, no ledger row');

-- 1.6 The latest row is current.
insert into _zc_r select 'rev_live_on', pg_temp.lr_pilot(true, 'live', null, null, 1000000);
set local role service_role;
insert into _zc_r select 'claim_r1', pg_temp.zc_claim(1, pg_temp.zc_lop('lr-r1'), 'live', 1234,
                                                      pg_temp.zc_id('order-lr-r1'), 1);
reset role;
insert into _zc_r select 'rev_live_off', pg_temp.lr_pilot(false, 'live', null, null, 1000000);
select pg_temp.zc_order('lr-r2', 1234);
set local role service_role;
insert into _zc_r select 'claim_r2', pg_temp.zc_claim(1, pg_temp.zc_lop('lr-r2'), 'live', 1234,
                                                      pg_temp.zc_id('order-lr-r2'), 1);
reset role;
select is(jsonb_build_object('on_claim_created', pg_temp.lr_r('claim_r1') -> 'claim_created',
                             'off_claim', pg_temp.lr_r('claim_r2') - 'server_ts',
                             'off_rows', (select count(*) from app.card_provider_attempts a
                                           where a.local_operation_id = pg_temp.zc_lop('lr-r2'))),
  jsonb_build_object('on_claim_created', true, 'off_claim', pg_temp.lr_refusal('card_payments_disabled'), 'off_rows', 0),
  'LR-24 the latest revision row is current: ON LIVE with a cap admits the claim; the next (OFF) row makes the next claim card_payments_disabled, no ledger row');
-- settle the admitted attempt (declined) so that d1 holds no unresolved attempt
set local role service_role;
insert into _zc_r select 'fin_r1', pg_temp.zc_finish(pg_temp.lr_r('claim_r1'), 'commit', 'declined',
  '{"approval_type": "declined", "error_flag": false, "provider_return_code": 5}'::jsonb);
reset role;

-- 1.7 Append-only.
select throws_ok($$ update app.card_payments_pilot_revisions set enabled = true
                     where revision = (select max(revision) from app.card_payments_pilot_revisions) $$,
  '42501', null, 'LR-25 revisions are append-only: an UPDATE of the current row raises 42501');
select throws_ok($$ delete from app.card_payments_pilot_revisions
                     where revision = (select max(revision) from app.card_payments_pilot_revisions) $$,
  '42501', null, 'LR-26 revisions are append-only: a DELETE raises 42501');

-- =============================================================================
-- 2. pin_session_capabilities: card_terminal_enabled / card_terminal_mode (4.30b, 4.55.9).
--    d1 holds an enabled LIVE binding; the current revision is OFF (LIVE).
-- =============================================================================
select is(pg_temp.lr_card_keys(1, 1), '{"card_terminal_enabled": false, "card_terminal_mode": "live"}'::jsonb,
  'LR-27 capabilities: enabled LIVE binding + revision OFF -> card_terminal_enabled false, card_terminal_mode live');
select pg_temp.lr_pilot(true, 'live', null, null, 1000000);
select is(jsonb_build_object('cashier', pg_temp.lr_card_keys(1, 1), 'manager', pg_temp.lr_card_keys(2, 1)),
  '{"cashier": {"card_terminal_enabled": true, "card_terminal_mode": "live"},
    "manager": {"card_terminal_enabled": true, "card_terminal_mode": "live"}}'::jsonb,
  'LR-28 capabilities: enabled binding + revision ON within its window in the same mode -> card_terminal_enabled true for every session of the exact device (cashier staff 1, manager staff 2)');
select is(pg_temp.lr_card_keys(8, 2), '{}'::jsonb,
  'LR-29 capabilities: another device of the branch (d2, no binding) -> no card_terminal_* key while d1 is bound');
select is(jsonb_build_array(pg_temp.lr_caps_rest(1, 1), pg_temp.lr_caps_rest(8, 2)),
  jsonb_build_array(pg_temp.lr_r('caps_base_1'), pg_temp.lr_r('caps_base_8')),
  'LR-30 capabilities: apart from the two card keys the d1 and d2 responses equal the no-binding baseline');
select pg_temp.lr_pilot(true, 'test', null, 5000, null);
select is(pg_temp.lr_card_keys(1, 1), '{"card_terminal_enabled": false, "card_terminal_mode": "live"}'::jsonb,
  'LR-31 capabilities: revision ON in the other mode (TEST) -> card_terminal_enabled false');
-- An ON LIVE revision whose window has elapsed. The setter refuses a past window when enabling, so the
-- row is appended directly by the owner (the append-only store accepts inserts) to model elapsed time.
insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode, window_until,
    max_test_amount_minor, max_live_amount_minor, reason, operator_reference, actor_app_user_id, executor_principal)
  values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), true, 'live', now() - interval '1 second', null,
          1000000, 'ZC001D LR elapsed window', 'zc001d-lr/rev-elapsed', pg_temp.zc_owner(), session_user);
select is(pg_temp.lr_card_keys(1, 1), '{"card_terminal_enabled": false, "card_terminal_mode": "live"}'::jsonb,
  'LR-32 capabilities: revision ON in the same mode whose window has passed -> card_terminal_enabled false');
select pg_temp.lr_pilot(true, 'live', null, null, 1000000);
insert into _zc_r select 'cap_drain', pg_temp.lr_term(1, 'live', 'draining', 'zc-term-live-1', 'zc-cred-live-1', 'incident');
select is(jsonb_build_object('drain', pg_temp.lr_r('cap_drain') -> 'new_lifecycle', 'keys', pg_temp.lr_card_keys(1, 1)),
  '{"drain": "draining", "keys": {"card_terminal_enabled": false, "card_terminal_mode": "live"}}'::jsonb,
  'LR-33 capabilities: a draining binding (revision ON LIVE) -> card_terminal_enabled false, mode still reported');
insert into _zc_r select 'cap_retire', pg_temp.lr_term(1, 'live', 'retired', 'zc-term-live-1', 'zc-cred-live-1',
                                                       'end_of_pilot');
select is(jsonb_build_object('retire', pg_temp.lr_r('cap_retire') -> 'new_lifecycle', 'keys', pg_temp.lr_card_keys(1, 1),
                             'rest', pg_temp.lr_caps_rest(1, 1)),
  jsonb_build_object('retire', 'retired', 'keys', '{}'::jsonb, 'rest', pg_temp.lr_r('caps_base_1')),
  'LR-34 capabilities: a retired binding -> card_terminal_* keys absent, the response equals the no-binding baseline');

-- =============================================================================
-- 3. app.set_payment_terminal: the exact-device binding (4.55.9, D-057 point 4, D-058 point 6).
--    d1 has no current binding (its LIVE row is retired); d2 has none.
-- =============================================================================
-- 3.1 Creation.
select pg_temp.lr_snap();
insert into _zc_r select 't_create', app.set_payment_terminal(pg_temp.zc_id('device-1'), 'test', 'lr-term-a',
  'lr-cred-a', 'configured', 'test_setup', U&'\00A0ZC001D LR binding ', ' zc001d-lr/bind-1 ', pg_temp.zc_id('user-9'));
select is(pg_temp.lr_step('t_create'),
  jsonb_build_object('result', pg_temp.lr_tres('test', null, 'configured'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', null, 'configured', false, 'test_setup'))),
  'LR-35 set_payment_terminal creates a configured binding: ok, and one operator.payment_terminal_updated {test, prior NULL, configured, starts_admitted false, test_setup}');
select results_eq(
  $$ select t.organization_id, t.restaurant_id, t.branch_id, t.device_id, t.terminal_ref, t.credential_ref, t.mode,
            t.lifecycle, t.deleted_at
       from pg_temp.lr_current(1) t $$,
  $$ values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'), 'lr-term-a'::text,
             'lr-cred-a'::text, 'test'::text, 'configured'::text, null::timestamptz) $$,
  'LR-36 the binding row: the exact device and its scope, the opaque references, mode test, lifecycle configured');
select results_eq(
  $$ select e.actor_kind, e.actor_reference, e.actor_app_user_id, e.executor_principal, e.mode, e.retention_until,
            e.attempt_row_id, e.device_id, e.reason, e.organization_id, e.restaurant_id, e.branch_id
       from pg_temp.lr_new_events() e $$,
  $$ values ('attested_owner_approver'::text, 'zc001d-lr/bind-1'::text, pg_temp.zc_id('user-9'), pg_temp.lr_exec(),
             null::text, null::timestamptz, null::uuid, pg_temp.zc_id('device-1'), 'ZC001D LR binding'::text,
             pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch()) $$,
  'LR-37 the binding event: attested_owner_approver, the canonical operator reference and reason, executor = session_user, the device, mode NULL, no retention');
select pg_temp.lr_snap();
insert into _zc_r select 't_same', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-a', 'lr-cred-a');
select is(pg_temp.lr_step('t_same'),
  jsonb_build_object('result', pg_temp.lr_tres('test', 'configured', 'configured', false), 'events', '[]'::jsonb),
  'LR-38 repeating the current lifecycle is a no-op: changed false, no event');

-- 3.2 Lifecycle steps: each legal step writes exactly one event; each illegal one nothing.
select pg_temp.lr_snap();
insert into _zc_r select 't_c2d', pg_temp.lr_term(1, 'test', 'draining', 'lr-term-a', 'lr-cred-a');
select is(pg_temp.lr_step('t_c2d') || jsonb_build_object('lifecycle', (select t.lifecycle from pg_temp.lr_current(1) t)),
  jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'lifecycle_transition'), 'events', '[]'::jsonb,
                     'lifecycle', 'configured'),
  'LR-39 configured -> draining is illegal: precondition_failed / lifecycle_transition, no event, the row stays configured');
select pg_temp.lr_snap();
insert into _zc_r select 't_c2e', pg_temp.lr_term(1, 'test', 'enabled', 'lr-term-a', 'lr-cred-a');
select is(pg_temp.lr_step('t_c2e'),
  jsonb_build_object('result', pg_temp.lr_tres('test', 'configured', 'enabled'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'configured', 'enabled', true, 'test_setup'))),
  'LR-40 configured -> enabled: one event {test, configured, enabled, starts_admitted true, test_setup}');
select pg_temp.lr_snap();
insert into _zc_r select 't_e2c', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-a', 'lr-cred-a');
insert into _zc_r select 't_e2r', pg_temp.lr_term(1, 'test', 'retired', 'lr-term-a', 'lr-cred-a', 'test_end');
select is(jsonb_build_object('to_configured', pg_temp.lr_r('t_e2c'), 'to_retired', pg_temp.lr_r('t_e2r'),
                             'events', (select count(*) from pg_temp.lr_new_events()),
                             'lifecycle', (select t.lifecycle from pg_temp.lr_current(1) t)),
  jsonb_build_object('to_configured', pg_temp.lr_refusal('precondition_failed', 'lifecycle_transition'),
                     'to_retired', pg_temp.lr_refusal('precondition_failed', 'lifecycle_transition'),
                     'events', 0, 'lifecycle', 'enabled'),
  'LR-41 enabled -> configured and enabled -> retired are illegal: lifecycle_transition, no event, the row stays enabled');
select pg_temp.lr_snap();
insert into _zc_r select 't_e2d', pg_temp.lr_term(1, 'test', 'draining', 'lr-term-a', 'lr-cred-a', 'incident');
select is(pg_temp.lr_step('t_e2d'),
  jsonb_build_object('result', pg_temp.lr_tres('test', 'enabled', 'draining'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'enabled', 'draining', false, 'incident'))),
  'LR-42 enabled -> draining: one event {test, enabled, draining, starts_admitted false, incident}');
select pg_temp.lr_snap();
insert into _zc_r select 't_d2e', pg_temp.lr_term(1, 'test', 'enabled', 'lr-term-a', 'lr-cred-a');
select is(pg_temp.lr_step('t_d2e'),
  jsonb_build_object('result', pg_temp.lr_tres('test', 'draining', 'enabled'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'draining', 'enabled', true, 'test_setup'))),
  'LR-43 draining -> enabled: one event {test, draining, enabled, starts_admitted true, test_setup}');
select pg_temp.lr_term(1, 'test', 'draining', 'lr-term-a', 'lr-cred-a', 'test_end');
select pg_temp.lr_snap();
insert into _zc_r select 't_d2r', pg_temp.lr_term(1, 'test', 'retired', 'lr-term-a', 'lr-cred-a', 'test_end');
select is(pg_temp.lr_step('t_d2r') || jsonb_build_object('current_rows', (select count(*) from pg_temp.lr_current(1))),
  jsonb_build_object('result', pg_temp.lr_tres('test', 'draining', 'retired'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'draining', 'retired', false, 'test_end')),
                     'current_rows', 0),
  'LR-44 draining -> retired: one event {test, draining, retired, starts_admitted false, test_end}; the device has no current binding');
select pg_temp.lr_snap();
insert into _zc_r select 't_r_en', pg_temp.lr_term(1, 'test', 'enabled', 'lr-term-a', 'lr-cred-a');
insert into _zc_r select 't_r_dr', pg_temp.lr_term(1, 'test', 'draining', 'lr-term-a', 'lr-cred-a');
select is(jsonb_build_object('enabled', pg_temp.lr_r('t_r_en'), 'draining', pg_temp.lr_r('t_r_dr'),
                             'events', (select count(*) from pg_temp.lr_new_events())),
  jsonb_build_object('enabled', pg_temp.lr_refusal('precondition_failed', 'lifecycle_transition'),
                     'draining', pg_temp.lr_refusal('precondition_failed', 'lifecycle_transition'), 'events', 0),
  'LR-45 retired is final: after retirement a call for enabled or draining is a creation and is refused lifecycle_transition, no event');
select pg_temp.lr_snap();
insert into _zc_r select 't_r_new', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-a', 'lr-cred-a');
select is(pg_temp.lr_step('t_r_new') || jsonb_build_object('rows',
    (select jsonb_agg(t.lifecycle order by t.created_at) from app.payment_terminals t
      where t.device_id = pg_temp.zc_id('device-1') and t.terminal_ref = 'lr-term-a')),
  jsonb_build_object('result', pg_temp.lr_tres('test', null, 'configured'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', null, 'configured', false, 'test_setup')),
                     'rows', '["retired", "configured"]'::jsonb),
  'LR-46 a configured call after retirement creates a new row (prior NULL, one event); the retired row stays retired');
select pg_temp.lr_snap();
insert into _zc_r select 't_c2r', pg_temp.lr_term(1, 'test', 'retired', 'lr-term-a', 'lr-cred-a', 'test_end');
select is(pg_temp.lr_step('t_c2r'),
  jsonb_build_object('result', pg_temp.lr_tres('test', 'configured', 'retired'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'configured', 'retired', false, 'test_end'))),
  'LR-47 configured -> retired: one event {test, configured, retired, starts_admitted false, test_end}');

-- 3.3 One current binding per device: binding_exists.
insert into _zc_r select 't_b_cfg', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-b', 'lr-cred-b');
select pg_temp.lr_snap();
insert into _zc_r select 't_bx_refs', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-c', 'lr-cred-c');
insert into _zc_r select 't_bx_mode', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l1', 'lr-cred-l1', 'live_activation');
insert into _zc_r select 't_bx_en', pg_temp.lr_term(1, 'test', 'enabled', 'lr-term-c', 'lr-cred-c');
select is(jsonb_build_object('created', pg_temp.lr_r('t_b_cfg') -> 'ok', 'new_refs', pg_temp.lr_r('t_bx_refs'),
                             'other_mode', pg_temp.lr_r('t_bx_mode'), 'new_refs_enabled', pg_temp.lr_r('t_bx_en'),
                             'events', (select count(*) from pg_temp.lr_new_events()),
                             'current', (select jsonb_agg(jsonb_build_array(t.terminal_ref, t.lifecycle))
                                           from pg_temp.lr_current(1) t)),
  jsonb_build_object('created', true,
                     'new_refs', pg_temp.lr_refusal('precondition_failed', 'binding_exists'),
                     'other_mode', pg_temp.lr_refusal('precondition_failed', 'binding_exists'),
                     'new_refs_enabled', pg_temp.lr_refusal('precondition_failed', 'binding_exists'),
                     'events', 0, 'current', '[["lr-term-b", "configured"]]'::jsonb),
  'LR-48 a second binding while one exists (other references, other mode, or a non-configured call) -> binding_exists, no event, the current row unchanged');

-- 3.4 Rotation: the atomic same-mode replacement of a draining row.
select pg_temp.lr_term(1, 'test', 'enabled', 'lr-term-b', 'lr-cred-b');
select pg_temp.lr_snap();
insert into _zc_r select 't_rot_enabled', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-c', 'lr-cred-c', 'rotation');
select pg_temp.lr_term(1, 'test', 'draining', 'lr-term-b', 'lr-cred-b', 'rotation');
insert into _zc_r select 't_rot_mode', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l1', 'lr-cred-l1', 'rotation');
select is(jsonb_build_object('from_enabled', pg_temp.lr_r('t_rot_enabled'), 'other_mode', pg_temp.lr_r('t_rot_mode'),
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'detail', e.detail))
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('from_enabled', pg_temp.lr_refusal('precondition_failed', 'binding_exists'),
                     'other_mode', pg_temp.lr_refusal('precondition_failed', 'binding_exists'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'enabled', 'draining', false, 'rotation'))),
  'LR-49 a replacement is only of a draining row in the same mode: new references while the row is enabled, or references of the other mode on the draining row -> binding_exists (only the drain step writes an event)');
select pg_temp.lr_snap();
insert into _zc_r select 't_rot', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-c', 'lr-cred-c', 'rotation');
select is(pg_temp.lr_step('t_rot'),
  jsonb_build_object('result', jsonb_build_object('ok', true, 'changed', true, 'replaced', true, 'binding_mode', 'test',
                                                  'prior_lifecycle', 'draining', 'new_lifecycle', 'configured'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'draining', 'retired', false, 'rotation'),
                                                 pg_temp.lr_tev('test', null, 'configured', false, 'rotation'))),
  'LR-50 rotation: draining + configured with new references of the same mode -> replaced, exactly two events (old draining -> retired, new NULL -> configured)');
select is(jsonb_build_object('rows', (select jsonb_agg(jsonb_build_array(t.terminal_ref, t.credential_ref, t.lifecycle)
                                                       order by t.terminal_ref)
                                        from app.payment_terminals t
                                       where t.device_id = pg_temp.zc_id('device-1')
                                         and t.terminal_ref in ('lr-term-b', 'lr-term-c')),
                             'caps', pg_temp.lr_card_keys(1, 1)),
  '{"rows": [["lr-term-b", "lr-cred-b", "retired"], ["lr-term-c", "lr-cred-c", "configured"]],
    "caps": {"card_terminal_enabled": false, "card_terminal_mode": "test"}}'::jsonb,
  'LR-51 rotation: the old row is retired, the new configured row carries the new references, and the till keeps its terminal posture (card_terminal_mode still reported)');

-- 3.5 One admitting (enabled / draining) binding per organization.
select pg_temp.lr_term(1, 'test', 'enabled', 'lr-term-c', 'lr-cred-c');
insert into _zc_r select 't_d2_cfg', pg_temp.lr_term(2, 'test', 'configured', 'lr-term-d', 'lr-cred-d');
insert into _zc_r select 't_adm_1', pg_temp.lr_term(2, 'test', 'enabled', 'lr-term-d', 'lr-cred-d');
select pg_temp.lr_term(1, 'test', 'draining', 'lr-term-c', 'lr-cred-c', 'test_end');
insert into _zc_r select 't_adm_2', pg_temp.lr_term(2, 'test', 'enabled', 'lr-term-d', 'lr-cred-d');
select is(jsonb_build_object('d2_created', pg_temp.lr_r('t_d2_cfg') -> 'ok',
                             'while_d1_enabled', pg_temp.lr_r('t_adm_1'), 'while_d1_draining', pg_temp.lr_r('t_adm_2'),
                             'd2_events', (select count(*) from app.card_provider_private_events e
                                            where e.action = 'operator.payment_terminal_updated'
                                              and e.device_id = pg_temp.zc_id('device-2')),
                             'd2_lifecycle', (select t.lifecycle from pg_temp.lr_current(2) t)),
  jsonb_build_object('d2_created', true,
                     'while_d1_enabled', pg_temp.lr_refusal('precondition_failed', 'admitting_binding_exists'),
                     'while_d1_draining', pg_temp.lr_refusal('precondition_failed', 'admitting_binding_exists'),
                     'd2_events', 1, 'd2_lifecycle', 'configured'),
  'LR-52 two devices enabled in the organization: enabling d2 while d1 is enabled or draining -> admitting_binding_exists (d2 keeps only its creation event, stays configured)');
select pg_temp.lr_term(1, 'test', 'retired', 'lr-term-c', 'lr-cred-c', 'test_end');
select pg_temp.lr_snap();
insert into _zc_r select 't_adm_ok', pg_temp.lr_term(2, 'test', 'enabled', 'lr-term-d', 'lr-cred-d');
select is(pg_temp.lr_step('t_adm_ok'),
  jsonb_build_object('result', pg_temp.lr_tres('test', 'configured', 'enabled'),
                     'events', jsonb_build_array(pg_temp.lr_tev('test', 'configured', 'enabled', true, 'test_setup'))),
  'LR-53 once the first device''s binding is retired the second device may be enabled');
select pg_temp.lr_term(2, 'test', 'draining', 'lr-term-d', 'lr-cred-d', 'test_end');
select pg_temp.lr_term(2, 'test', 'retired', 'lr-term-d', 'lr-cred-d', 'test_end');

-- 3.6 Device scope, tokens, actor and text refusals (nothing written).
select pg_temp.lr_snap();
update public.devices set is_active = false where id = pg_temp.zc_id('device-2');
insert into _zc_r select 'ir_inactive', pg_temp.lr_term(2, 'test', 'configured', 'lr-term-x', 'lr-cred-x');
update public.devices set is_active = true where id = pg_temp.zc_id('device-2');
update public.devices set deleted_at = now() where id = pg_temp.zc_id('device-2');
insert into _zc_r select 'ir_deleted', pg_temp.lr_term(2, 'test', 'configured', 'lr-term-x', 'lr-cred-x');
update public.devices set deleted_at = null where id = pg_temp.zc_id('device-2');
insert into _zc_r select 'ir_kds', pg_temp.lr_term(3, 'test', 'configured', 'lr-term-x', 'lr-cred-x');
insert into _zc_r select 'ir_foreign', pg_temp.lr_term(4, 'test', 'configured', 'lr-term-x', 'lr-cred-x');
insert into _zc_r select 'ir_sibling', pg_temp.lr_term(5, 'test', 'configured', 'lr-term-x', 'lr-cred-x');
insert into _zc_r select 'ir_unknown', app.set_payment_terminal(pg_temp.zc_id('device-lr-unknown'), 'test', 'lr-term-x',
  'lr-cred-x', 'configured', 'test_setup', 'ZC001D LR binding', 'zc001d-lr/bind-1', pg_temp.zc_owner());
insert into _zc_r select 'ir_tokens', jsonb_build_array(
  pg_temp.lr_term(2, 'demo', 'configured', 'lr-term-x', 'lr-cred-x'),
  pg_temp.lr_term(2, 'test', 'paused', 'lr-term-x', 'lr-cred-x'),
  pg_temp.lr_term(2, 'test', 'configured', 'lr-term-x', 'lr-cred-x', 'cleanup'));
insert into _zc_r select 'pd_term', pg_temp.lr_term(2, 'test', 'configured', 'lr-term-x', 'lr-cred-x',
                                                    p_actor => pg_temp.zc_id('user-2'));
insert into _zc_r select 'oc_term', jsonb_build_array(
  pg_temp.lr_term(2, 'test', 'configured', 'LR-TERM-X', 'lr-cred-x'),
  pg_temp.lr_term(2, 'test', 'configured', 'lr-same-ref', 'lr-same-ref'),
  pg_temp.lr_term(2, 'test', 'configured', 'lr-term-x', 'lr-cred-x', p_reason => 'Card ' || rtrim(repeat('7351 ', 4)) || ' on the till'),
  pg_temp.lr_term(2, 'test', 'configured', 'lr-term-x', 'lr-cred-x', p_ref => ''));
select is(jsonb_build_object('inactive', pg_temp.lr_r('ir_inactive'), 'deleted', pg_temp.lr_r('ir_deleted'),
                             'kds', pg_temp.lr_r('ir_kds'), 'foreign', pg_temp.lr_r('ir_foreign'),
                             'sibling', pg_temp.lr_r('ir_sibling'), 'unknown', pg_temp.lr_r('ir_unknown')),
  jsonb_build_object('inactive', pg_temp.lr_refusal('invalid_request'), 'deleted', pg_temp.lr_refusal('invalid_request'),
                     'kds', pg_temp.lr_refusal('invalid_request'), 'foreign', pg_temp.lr_refusal('invalid_request'),
                     'sibling', pg_temp.lr_refusal('invalid_request'), 'unknown', pg_temp.lr_refusal('invalid_request')),
  'LR-54 an inactive or deleted device, a KDS device, a device outside the pilot scope (foreign organization, sibling branch) or an unknown device -> invalid_request');
select is(pg_temp.lr_r('ir_tokens'),
  jsonb_build_array(pg_temp.lr_refusal('invalid_request'), pg_temp.lr_refusal('invalid_request'),
                    pg_temp.lr_refusal('invalid_request')),
  'LR-55 an unknown mode, lifecycle or reason_code token -> invalid_request');
select is(pg_temp.lr_r('pd_term'), pg_temp.lr_refusal('permission_denied'),
  'LR-56 set_payment_terminal by a non-owner actor (staff 2, manager) -> permission_denied');
select is(pg_temp.lr_r('oc_term'),
  jsonb_build_array(pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                    pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                    pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                    pg_temp.lr_refusal('permission_denied')),
  'LR-57 a reference outside its grammar (uppercase), equal terminal and credential references, a reason with a card number -> out_of_contract; an empty operator reference is absent -> permission_denied (review fix 7)');
select is(jsonb_build_object('rows', (select count(*) from app.payment_terminals t
                                       where t.terminal_ref in ('lr-term-x', 'LR-TERM-X', 'lr-same-ref')),
                             'events', (select count(*) from pg_temp.lr_new_events())),
  '{"rows": 0, "events": 0}'::jsonb,
  'LR-58 those refusals create no binding row and write no event');

-- 3.7 payment_create_pending: a pending / in-flight payment.create of the device (a sync row inserted by the owner).
insert into public.sync_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
    operation_type, payload, payload_fingerprint, status)
  values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
          pg_temp.zc_lop('lr-backlog-1'), 'payment.create', '{}'::jsonb, 'zc001d-lr-fp-1', 'pending');
select pg_temp.lr_snap();
insert into _zc_r select 'pcp_pending', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l1', 'lr-cred-l1', 'live_activation');
update public.sync_operations set status = 'in_flight' where local_operation_id = pg_temp.zc_lop('lr-backlog-1');
insert into _zc_r select 'pcp_in_flight', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l1', 'lr-cred-l1', 'live_activation');
select is(jsonb_build_object('pending', pg_temp.lr_r('pcp_pending'), 'in_flight', pg_temp.lr_r('pcp_in_flight'),
                             'rows', (select count(*) from app.payment_terminals t where t.terminal_ref = 'lr-term-l1'),
                             'events', (select count(*) from pg_temp.lr_new_events())),
  jsonb_build_object('pending', pg_temp.lr_refusal('precondition_failed', 'payment_create_pending'),
                     'in_flight', pg_temp.lr_refusal('precondition_failed', 'payment_create_pending'),
                     'rows', 0, 'events', 0),
  'LR-59 creating a LIVE binding while a payment.create of the device is pending or in flight -> payment_create_pending, no row, no event');
insert into _zc_r select 'pcp_test_create', pg_temp.lr_term(1, 'test', 'configured', 'lr-term-e', 'lr-cred-e');
insert into _zc_r select 'pcp_retire', pg_temp.lr_term(1, 'test', 'retired', 'lr-term-e', 'lr-cred-e', 'test_end');
select is(jsonb_build_object('test_create', pg_temp.lr_r('pcp_test_create'), 'retire', pg_temp.lr_r('pcp_retire'),
                             'lifecycle', (select t.lifecycle from pg_temp.lr_current(1) t)),
  jsonb_build_object('test_create', pg_temp.lr_tres('test', null, 'configured'),
                     'retire', pg_temp.lr_refusal('precondition_failed', 'payment_create_pending'),
                     'lifecycle', 'configured'),
  'LR-60 with an in-flight payment.create a TEST binding may still be created (the creation gate is LIVE-only), but its retirement -> payment_create_pending');
update public.sync_operations set status = 'applied' where local_operation_id = pg_temp.zc_lop('lr-backlog-1');
insert into public.sync_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
    operation_type, payload, payload_fingerprint, status)
  values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
          pg_temp.zc_lop('lr-backlog-2'), 'order.submit', '{}'::jsonb, 'zc001d-lr-fp-2', 'pending');
insert into _zc_r select 'pcp_retire_ok', pg_temp.lr_term(1, 'test', 'retired', 'lr-term-e', 'lr-cred-e', 'test_end');
insert into _zc_r select 'pcp_live_ok', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l1', 'lr-cred-l1', 'live_activation');
select is(jsonb_build_object('retire', pg_temp.lr_r('pcp_retire_ok'), 'live_create', pg_temp.lr_r('pcp_live_ok')),
  jsonb_build_object('retire', pg_temp.lr_tres('test', 'configured', 'retired'),
                     'live_create', pg_temp.lr_tres('live', null, 'configured')),
  'LR-61 an applied payment.create and a pending order.submit are no backlog: the retirement and the LIVE creation pass');
update public.sync_operations set status = 'pending' where local_operation_id = pg_temp.zc_lop('lr-backlog-1');
select pg_temp.lr_snap();
insert into _zc_r select 'pcp_enable', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l1', 'lr-cred-l1', 'live_activation');
insert into _zc_r select 'pcp_retire_live', pg_temp.lr_term(1, 'live', 'retired', 'lr-term-l1', 'lr-cred-l1', 'end_of_pilot');
select is(jsonb_build_object('enable', pg_temp.lr_r('pcp_enable'), 'retire', pg_temp.lr_r('pcp_retire_live'),
                             'events', (select count(*) from pg_temp.lr_new_events()),
                             'lifecycle', (select t.lifecycle from pg_temp.lr_current(1) t)),
  jsonb_build_object('enable', pg_temp.lr_refusal('precondition_failed', 'payment_create_pending'),
                     'retire', pg_temp.lr_refusal('precondition_failed', 'payment_create_pending'),
                     'events', 0, 'lifecycle', 'configured'),
  'LR-62 LIVE activation and retirement with a pending payment.create of the device -> payment_create_pending, no event');
update public.sync_operations set status = 'rejected' where local_operation_id = pg_temp.zc_lop('lr-backlog-1');
select pg_temp.lr_pilot(true, 'live', null, null, 1000000);
insert into _zc_r select 'pcp_enable_ok', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l1', 'lr-cred-l1', 'live_activation');
select is(pg_temp.lr_r('pcp_enable_ok'), pg_temp.lr_tres('live', 'configured', 'enabled'),
  'LR-63 once that payment.create is terminal (rejected) the LIVE activation passes');

-- 3.8 attempt_unresolved: the LIVE activation and retirement gates.
select pg_temp.zc_order('lr-t1', 1234);
set local role service_role;
insert into _zc_r select 'claim_t1', pg_temp.lr_claim(1, pg_temp.zc_lop('lr-t1'), 'live', 1234,
                                                      pg_temp.zc_id('order-lr-t1'), 1, 'lr-term-l1', 'lr-cred-l1');
reset role;
select pg_temp.lr_snap();
insert into _zc_r select 'au_drain', pg_temp.lr_term(1, 'live', 'draining', 'lr-term-l1', 'lr-cred-l1', 'incident');
insert into _zc_r select 'au_reenable', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l1', 'lr-cred-l1', 'live_activation');
insert into _zc_r select 'au_retire', pg_temp.lr_term(1, 'live', 'retired', 'lr-term-l1', 'lr-cred-l1', 'end_of_pilot');
select is(jsonb_build_object('claim_state', pg_temp.lr_r('claim_t1') -> 'state',
                             'drain', pg_temp.lr_r('au_drain'), 'reenable', pg_temp.lr_r('au_reenable'),
                             'retire', pg_temp.lr_r('au_retire'),
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'detail', e.detail))
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('claim_state', 'sent', 'drain', pg_temp.lr_tres('live', 'enabled', 'draining'),
                     'reenable', pg_temp.lr_refusal('precondition_failed', 'attempt_unresolved'),
                     'retire', pg_temp.lr_refusal('precondition_failed', 'attempt_unresolved'),
                     'events', jsonb_build_array(pg_temp.lr_tev('live', 'enabled', 'draining', false, 'incident'))),
  'LR-64 with an unresolved (sent) LIVE attempt of the device: enabled -> draining passes; draining -> enabled (LIVE activation) and draining -> retired -> attempt_unresolved');
select pg_temp.lr_snap();
-- the device's payment.create is pending again during the rotation (neither gate applies to a replacement)
update public.sync_operations set status = 'pending' where local_operation_id = pg_temp.zc_lop('lr-backlog-1');
insert into _zc_r select 'au_rotate', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l2', 'lr-cred-l2', 'rotation');
insert into _zc_r select 'au_rot_enable', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l2', 'lr-cred-l2', 'live_activation');
insert into _zc_r select 'au_rot_retire', pg_temp.lr_term(1, 'live', 'retired', 'lr-term-l2', 'lr-cred-l2', 'end_of_pilot');
update public.sync_operations set status = 'rejected' where local_operation_id = pg_temp.zc_lop('lr-backlog-1');
select is(jsonb_build_object('rotate', pg_temp.lr_r('au_rotate'), 'enable', pg_temp.lr_r('au_rot_enable'),
                             'retire', pg_temp.lr_r('au_rot_retire'),
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'detail', e.detail)
                                                         order by e.created_at, e.id) from pg_temp.lr_new_events() e)),
  jsonb_build_object('rotate', jsonb_build_object('ok', true, 'changed', true, 'replaced', true, 'binding_mode', 'live',
                                                  'prior_lifecycle', 'draining', 'new_lifecycle', 'configured'),
                     'enable', pg_temp.lr_refusal('precondition_failed', 'attempt_unresolved'),
                     'retire', pg_temp.lr_refusal('precondition_failed', 'attempt_unresolved'),
                     'events', jsonb_build_array(pg_temp.lr_tev('live', 'draining', 'retired', false, 'rotation'),
                                                 pg_temp.lr_tev('live', null, 'configured', false, 'rotation'))),
  'LR-65 a LIVE rotation needs neither the retirement nor the creation gate (replaced, two events, while an attempt is unresolved and a payment.create is pending), but the new row cannot be enabled or retired while the attempt is unresolved');
set local role service_role;
insert into _zc_r select 'fin_t1', pg_temp.zc_finish(pg_temp.lr_r('claim_t1'), 'commit', 'declined',
                                                     '{"approval_type": "declined"}'::jsonb);
reset role;
insert into _zc_r select 'direct_t2', jsonb_build_object('attempt_row_id', pg_temp.lr_insert_test_attempt(1, 'lr-t2'));
select pg_temp.lr_snap();
insert into _zc_r select 'au_test_blocks', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l2', 'lr-cred-l2', 'live_activation');
select is(jsonb_build_object('live_attempt', pg_temp.lr_r('fin_t1') -> 'state',
                             'test_attempt', (select jsonb_build_array(a.mode, a.state, a.resolution)
                                                from app.card_provider_attempts a where a.id = pg_temp.lr_aid('direct_t2')),
                             'enable', pg_temp.lr_r('au_test_blocks'),
                             'events', (select count(*) from pg_temp.lr_new_events())),
  jsonb_build_object('live_attempt', 'declined', 'test_attempt', '["test", "sent", null]'::jsonb,
                     'enable', pg_temp.lr_refusal('precondition_failed', 'attempt_unresolved'), 'events', 0),
  'LR-66 LIVE activation with an unresolved TEST attempt of the device (row inserted directly: the binding gates make it unreachable through the RPCs) -> attempt_unresolved');
select pg_temp.lr_age_attempt(pg_temp.lr_aid('direct_t2'), true, false);
insert into _zc_r select 'au_test_close', app.card_attempt_resolve_orphan(pg_temp.lr_aid('direct_t2'), 'test_closed',
  'lr-test-ref-t2', 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-t2', pg_temp.zc_owner());
insert into _zc_r select 'au_enable_ok', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l2', 'lr-cred-l2', 'live_activation');
select is(jsonb_build_object('test_closed', pg_temp.lr_r('au_test_close') -> 'resolution',
                             'enable', pg_temp.lr_r('au_enable_ok')),
  jsonb_build_object('test_closed', 'test_closed', 'enable', pg_temp.lr_tres('live', 'configured', 'enabled')),
  'LR-67 once the TEST attempt is test_closed (the LIVE one declined) the LIVE activation passes');

-- 3.9 Immutability (trigger): mode, references, scope, deletion, creation lifecycle.
insert into _zc_r select 'trg_cols', (select jsonb_object_agg(x.c, pg_temp.lr_try(format(
    'update app.payment_terminals set %I = %s where id = %L', x.c, x.v,
    (select t.id from pg_temp.lr_current(1) t))))
  from (values ('mode', '''test'''), ('terminal_ref', '''lr-term-zz'''), ('credential_ref', '''lr-cred-zz'''),
               ('device_id', quote_literal(pg_temp.zc_id('device-2'))),
               ('organization_id', quote_literal(pg_temp.zc_id('org_b'))),
               ('restaurant_id', quote_literal(pg_temp.zc_id('rest_b'))),
               ('branch_id', quote_literal(pg_temp.zc_id('branch_sib'))), ('id', 'gen_random_uuid()'),
               ('created_at', 'created_at - interval ''1 day'''), ('deleted_at', 'clock_timestamp()'),
               ('lifecycle', '''configured'''), ('updated_at', 'updated_at')) x(c, v));
select is(pg_temp.lr_r('trg_cols'),
  '{"mode": "23514", "terminal_ref": "23514", "credential_ref": "23514", "device_id": "23514", "organization_id": "23514",
    "restaurant_id": "23514", "branch_id": "23514", "id": "23514", "created_at": "23514", "deleted_at": "23514",
    "lifecycle": "23514", "updated_at": "no_error"}'::jsonb,
  'LR-68 a direct UPDATE of a binding''s mode, references, scope, id, created_at or deleted_at, or an illegal lifecycle step (enabled -> configured), raises 23514 (trigger); control: the same probe on updated_at passes');
select is((select jsonb_build_array(t.mode, t.terminal_ref, t.credential_ref, t.lifecycle) from pg_temp.lr_current(1) t),
  '["live", "lr-term-l2", "lr-cred-l2", "enabled"]'::jsonb,
  'LR-69 after those refused updates the binding row is unchanged');
select throws_ok($$ update app.payment_terminals set lifecycle = 'enabled'
                     where device_id = pg_temp.zc_id('device-1') and terminal_ref = 'lr-term-a' $$,
  '23514', null, 'LR-70 retired is final: a direct UPDATE of a retired row back to enabled raises 23514');
select throws_ok($$ delete from app.payment_terminals where device_id = pg_temp.zc_id('device-1') $$,
  '42501', null, 'LR-71 binding rows are never deleted: a direct DELETE raises 42501');
select throws_ok($$ insert into app.payment_terminals (organization_id, restaurant_id, branch_id, device_id,
                        terminal_ref, credential_ref, mode, lifecycle)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-2'),
                            'lr-term-y', 'lr-cred-y', 'test', 'enabled') $$,
  '23514', null, 'LR-72 a binding row is created configured: a direct INSERT as enabled raises 23514');
select throws_ok($$ insert into app.payment_terminals (organization_id, restaurant_id, branch_id, device_id,
                        terminal_ref, credential_ref, mode)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), null,
                            'lr-term-n', 'lr-cred-n', 'test') $$,
  '23502', null, 'LR-73 device_id is NOT NULL: a branch-level binding without a device raises 23502');
select throws_ok($$ insert into app.payment_terminals (organization_id, restaurant_id, branch_id, device_id,
                        terminal_ref, credential_ref, mode)
                    values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
                            'lr-term-u', 'lr-cred-u', 'test') $$,
  '23505', null, 'LR-74 one current binding per device is a database guarantee: a direct INSERT of a second non-retired row for d1 raises 23505');
insert into _zc_r select 't_u2', pg_temp.lr_term(2, 'test', 'configured', 'lr-term-u2', 'lr-cred-u2');
select throws_ok($$ update app.payment_terminals set lifecycle = 'enabled'
                     where device_id = pg_temp.zc_id('device-2') and terminal_ref = 'lr-term-u2' $$,
  '23505', null, 'LR-75 one admitting binding per organization is a database guarantee: a direct UPDATE enabling d2 while d1 is enabled raises 23505');
insert into _zc_r select 't_u2_retire', pg_temp.lr_term(2, 'test', 'retired', 'lr-term-u2', 'lr-cred-u2', 'test_end');

-- 3.10 Credential-reference ownership (trigger).
select throws_ok($$ insert into app.payment_terminals (organization_id, restaurant_id, branch_id, device_id,
                        terminal_ref, credential_ref, mode)
                    values (pg_temp.zc_id('org_b'), pg_temp.zc_id('rest_b'), pg_temp.zc_id('branch_b'),
                            pg_temp.zc_id('device-4'), 'lr-term-b4', 'lr-cred-l1', 'live') $$,
  '23514', null, 'LR-76 a LIVE credential reference of the pilot restaurant reused by a LIVE binding of another restaurant raises 23514 (trigger)');
select throws_ok($$ select pg_temp.lr_term(2, 'test', 'configured', 'lr-term-y2', 'lr-cred-l2') $$,
  '23514', null, 'LR-77 a reference never spans modes: a TEST binding naming a LIVE credential reference raises 23514 through set_payment_terminal');
select lives_ok($$ insert into app.payment_terminals (organization_id, restaurant_id, branch_id, device_id,
                       terminal_ref, credential_ref, mode)
                   values (pg_temp.zc_id('org_b'), pg_temp.zc_id('rest_b'), pg_temp.zc_id('branch_b'),
                           pg_temp.zc_id('device-4'), 'lr-term-b4', 'lr-cred-a', 'test') $$,
  'LR-78 contrast: a TEST credential reference (development-scoped, owned by no restaurant) may be reused by another restaurant''s TEST binding');
insert into _zc_r select 'same_rest_live', pg_temp.lr_term(2, 'live', 'configured', 'lr-term-l3', 'lr-cred-l1', 'live_activation');
select is(pg_temp.lr_r('same_rest_live'), pg_temp.lr_tres('live', null, 'configured'),
  'LR-79 contrast: the same LIVE credential reference on another device of the same restaurant is accepted');
select pg_temp.lr_term(2, 'live', 'retired', 'lr-term-l3', 'lr-cred-l1', 'end_of_pilot');

-- 3.11 Every binding event of this file has the documented shape.
select is((select jsonb_build_object('total', count(*),
                                     'misshaped', count(*) filter (where not (
                                        pg_temp.lr_keys(e.detail) = array['binding_mode', 'new_lifecycle', 'prior_lifecycle',
                                                                          'reason_code', 'starts_admitted']
                                        and (e.detail -> 'starts_admitted') = to_jsonb(e.detail ->> 'new_lifecycle' = 'enabled')
                                        and e.actor_kind = 'attested_owner_approver' and e.executor_principal = pg_temp.lr_exec()
                                        and e.actor_app_user_id = pg_temp.zc_owner() and e.mode is null
                                        and e.retention_until is null and e.attempt_row_id is null and e.device_id is not null)))
             from app.card_provider_private_events e where e.action = 'operator.payment_terminal_updated' and e.created_at >= now()),
  '{"total": 36, "misshaped": 0}'::jsonb,
  'LR-80 every operator.payment_terminal_updated so far (36, one per row change, two per rotation): detail exactly the five keys, starts_admitted = (new_lifecycle = enabled), attested approver, executor, the device, mode NULL, no retention');

-- =============================================================================
-- 4. app.card_attempt_resolve_orphan, LIVE (4.55.7 orphan policy). d1: LIVE binding enabled
--    (lr-term-l2); the current revision is ON LIVE with a cap.
-- =============================================================================
select pg_temp.zc_order('lr-o' || n, 1234) from generate_series(1, 5) n;
set local role service_role;
insert into _zc_r select 'claim_o' || n, pg_temp.lr_claim(1, pg_temp.zc_lop('lr-o' || n), 'live', 1234,
                                                          pg_temp.zc_id('order-lr-o' || n), 1, 'lr-term-l2', 'lr-cred-l2')
  from generate_series(1, 5) n;
insert into _zc_r select 'fin_o1', pg_temp.zc_finish(pg_temp.lr_r('claim_o1'), 'commit', 'approved', pg_temp.zc_approved_fields());
insert into _zc_r select 'fin_o2', pg_temp.zc_finish(pg_temp.lr_r('claim_o2'), 'commit', 'anomaly',
                                                     '{"anomaly_code": "refunded"}'::jsonb);
insert into _zc_r select 'fin_o4', pg_temp.zc_finish(pg_temp.lr_r('claim_o4'), 'commit', 'declined',
                                                     '{"approval_type": "declined"}'::jsonb);
insert into _zc_r select 'fin_o5', pg_temp.zc_finish(pg_temp.lr_r('claim_o5'), 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
select results_eq(
  $$ select n, a.state, x.d ->> 'classification', x.d ->> 'reason'
       from generate_series(1, 5) n
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid('claim_o' || n)
       cross join lateral (select app.card_attempt_derive(a) as d) x
      order by n $$,
  $$ values (1, 'approved'::text, 'approved_unrecorded'::text, 'pending_recording'::text),
            (2, 'unknown', 'provider_anomaly', null), (3, 'sent', 'in_progress', null),
            (4, 'declined', 'declined', null), (5, 'approved', 'approved_unrecorded', 'pending_recording') $$,
  'LR-81 setup: five LIVE attempts on d1 - approved pending_recording, provider_anomaly (refunded), sent, declined, approved pending_recording');

-- 4.1 Not resolvable: approved pending_recording, sent, declined.
select pg_temp.lr_snap();
insert into _zc_r select 'ro_pending', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o1'), 'provider_voided',
  'lr-void-ref-1', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-1', pg_temp.zc_owner());
insert into _zc_r select 'ro_sent', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o3'), 'provider_voided',
  'lr-void-ref-3', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-3', pg_temp.zc_owner());
insert into _zc_r select 'ro_declined', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o4'), 'provider_refunded',
  'lr-void-ref-4', 'ZC001D LR provider refund confirmed', 'zc001d-lr/orphan-4', pg_temp.zc_owner());
select is(jsonb_build_object('approved_pending_recording', pg_temp.lr_r('ro_pending'), 'sent', pg_temp.lr_r('ro_sent'),
                             'declined', pg_temp.lr_r('ro_declined'),
                             'events', (select count(*) from pg_temp.lr_new_events()),
                             'resolved_rows', (select count(*) from app.card_provider_attempts a
                                                where a.mode = 'live' and a.resolution is not null and a.created_at >= now())),
  jsonb_build_object('approved_pending_recording', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'sent', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'declined', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'events', 0, 'resolved_rows', 0),
  'LR-82 resolve_orphan refuses a LIVE attempt that is approved pending_recording, sent or declined: attempt_not_resolvable, nothing written');

-- 4.2 The orphan: approve, then the order is voided (by the owner) -> orphan_approved / order_terminal.
select pg_temp.lr_void(pg_temp.zc_id('order-lr-o1'));
select pg_temp.lr_void(pg_temp.zc_id('order-lr-o5'));
select is((select jsonb_build_object('classification', x.d ->> 'classification', 'reason', x.d ->> 'reason',
                                     'claim_active', app.card_order_claim_active(a.organization_id, a.order_id))
             from app.card_provider_attempts a cross join lateral (select app.card_attempt_derive(a) as d) x
            where a.id = pg_temp.lr_aid('claim_o1')),
  '{"classification": "orphan_approved", "reason": "order_terminal", "claim_active": true}'::jsonb,
  'LR-83 setup: voiding the order of an approved unrecorded attempt makes it orphan_approved / order_terminal (the claim stays active)');
select pg_temp.lr_snap();
insert into _zc_r select 'ro_staff2', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o5'), 'provider_voided',
  'lr-void-ref-5', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-5', pg_temp.zc_id('user-2'));
insert into _zc_r select 'ro_test_closed_live', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o5'), 'test_closed',
  'lr-void-ref-5', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-5', pg_temp.zc_owner());
insert into _zc_r select 'ro_bad_token', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o5'), 'manual_refund',
  'lr-void-ref-5', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-5', pg_temp.zc_owner());
insert into _zc_r select 'ro_unknown', app.card_attempt_resolve_orphan(pg_temp.zc_id('attempt-lr-none'), 'provider_voided',
  'lr-void-ref-5', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-5', pg_temp.zc_owner());
insert into _zc_r select 'ro_card_ref', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o5'), 'provider_voided',
  repeat('7351', 4), 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-5', pg_temp.zc_owner());
select is(jsonb_build_object('staff2', pg_temp.lr_r('ro_staff2'), 'test_closed_on_live', pg_temp.lr_r('ro_test_closed_live'),
                             'bad_token', pg_temp.lr_r('ro_bad_token'), 'unknown_row', pg_temp.lr_r('ro_unknown'),
                             'card_number_reference', pg_temp.lr_r('ro_card_ref'),
                             'events', (select count(*) from pg_temp.lr_new_events()),
                             'o5_resolution', (select a.resolution from app.card_provider_attempts a
                                                where a.id = pg_temp.lr_aid('claim_o5'))),
  jsonb_build_object('staff2', pg_temp.lr_refusal('permission_denied'),
                     'test_closed_on_live', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'bad_token', pg_temp.lr_refusal('invalid_request'),
                     'unknown_row', pg_temp.lr_refusal('attempt_not_found'),
                     'card_number_reference', pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                     'events', 0, 'o5_resolution', null),
  'LR-84 resolve_orphan refusals write nothing: non-owner -> permission_denied; test_closed on a LIVE orphan -> attempt_not_resolvable; unknown token -> invalid_request; unknown row -> attempt_not_found; a card number as resolution_reference -> out_of_contract');

-- 4.3 orphan_approved -> provider_voided.
select pg_temp.lr_snap();
insert into _zc_r select 'audit_n_o1', to_jsonb(pg_temp.lr_audit_count());
insert into _zc_r select 'ro_o1', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o1'), 'provider_voided',
  ' lr-void-ref-1 ', U&'ZC001D LR provider void confirmed\00A0', 'zc001d-lr/orphan-1', pg_temp.zc_owner());
select is(pg_temp.lr_r('ro_o1') - 'server_ts',
  jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('lr-o1'), 'state', 'approved', 'classification', 'resolved',
                     'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS', 'provider_return_code', 0,
                     'resolution', 'provider_voided', 'attempt_row_id', pg_temp.lr_aid('claim_o1')),
  'LR-85 LIVE orphan_approved -> provider_voided: the 4.55.4 envelope (state approved, classification resolved, resolution) plus attempt_row_id');
select results_eq(
  $$ select a.resolution, a.resolution_reference, a.resolved_at is not null, a.order_freed_at is not null,
            a.order_freed_reason, a.state, app.card_order_claim_active(a.organization_id, a.order_id)
       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_o1') $$,
  $$ values ('provider_voided'::text, 'lr-void-ref-1'::text, true, true, 'orphan_resolved'::text, 'approved'::text, false) $$,
  'LR-86 the row carries resolution, the canonical resolution_reference, resolved_at, order_freed_at and order_freed_reason orphan_resolved; the claim is released');
select results_eq(
  $$ select e.action, e.attempt_row_id, e.device_id, e.mode, e.retention_until, e.actor_kind, e.actor_reference,
            e.actor_app_user_id, e.executor_principal, e.reason, e.detail
       from pg_temp.lr_new_events() e $$,
  $$ values ('operator.card_attempt_orphan_resolved'::text, pg_temp.lr_aid('claim_o1'), pg_temp.zc_id('device-1'), null::text,
             null::timestamptz, 'attested_owner_approver'::text, 'zc001d-lr/orphan-1'::text, pg_temp.zc_owner(),
             pg_temp.lr_exec(), 'ZC001D LR provider void confirmed'::text,
             '{"resolution": "provider_voided", "attempt_state": "approved"}'::jsonb) $$,
  'LR-87 exactly one private event operator.card_attempt_orphan_resolved: detail {resolution, attempt_state}, the attempt row and device, attested approver, executor, mode NULL');
select is(pg_temp.lr_audit_count() - (pg_temp.lr_r('audit_n_o1') #>> '{}')::bigint, 0::bigint,
  'LR-88 the orphan resolution writes no tenant audit_events row');
select pg_temp.lr_snap();
insert into _zc_r select 'ro_o1_again', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o1'), 'provider_refunded',
  'lr-void-ref-1b', 'ZC001D LR again', 'zc001d-lr/orphan-1b', pg_temp.zc_owner());
select is(jsonb_build_object('result', pg_temp.lr_r('ro_o1_again'), 'events', (select count(*) from pg_temp.lr_new_events()),
                             'row', (select jsonb_build_array(a.resolution, a.resolution_reference)
                                       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_o1'))),
  jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'), 'events', 0,
                     'row', '["provider_voided", "lr-void-ref-1"]'::jsonb),
  'LR-89 an already-resolved attempt is not resolvable again: attempt_not_resolvable, resolution unchanged, no event');

-- 4.4 A finish after the resolution: evidence only.
insert into _zc_r select 'row_o1_before', (select to_jsonb(a) from app.card_provider_attempts a
                                            where a.id = pg_temp.lr_aid('claim_o1'));
select pg_temp.lr_snap();
set local role service_role;
insert into _zc_r select 'fin_o1_late', pg_temp.zc_finish(pg_temp.lr_r('claim_o1'), 'lookup', 'declined',
                                                          '{"approval_type": "declined"}'::jsonb);
reset role;
select is(jsonb_build_object('envelope', pg_temp.lr_r('fin_o1_late') - 'server_ts',
                             'row_unchanged', (select to_jsonb(a) from app.card_provider_attempts a
                                                where a.id = pg_temp.lr_aid('claim_o1')) = pg_temp.lr_r('row_o1_before')),
  jsonb_build_object('envelope', pg_temp.lr_r('ro_o1') - 'server_ts' - 'attempt_row_id', 'row_unchanged', true),
  'LR-90 a finish reaching the resolved LIVE attempt answers its resolved envelope and changes nothing in the row');
select results_eq(
  $$ select e.action, e.actor_kind, e.actor_reference, e.mode, e.retention_until, e.attempt_row_id, e.detail
       from pg_temp.lr_new_events() e $$,
  $$ values ('security.card_resolution_contradicted'::text, 'adapter'::text, 'card_adapter'::text, 'live'::text,
             null::timestamptz, pg_temp.lr_aid('claim_o1'), '{"source": "lookup", "outcome": "declined"}'::jsonb) $$,
  'LR-91 ... and writes exactly one security.card_resolution_contradicted (adapter, mode live, detail {source, outcome})');

-- 4.5 A LIVE provider_anomaly -> provider_refunded.
select pg_temp.lr_snap();
insert into _zc_r select 'audit_n_o2', to_jsonb(pg_temp.lr_audit_count());
insert into _zc_r select 'claim_active_o2', to_jsonb(app.card_order_claim_active(pg_temp.zc_org(), pg_temp.zc_id('order-lr-o2')));
insert into _zc_r select 'ro_o2', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o2'), 'provider_refunded',
  'lr-refund-ref-2', 'ZC001D LR provider refund confirmed', 'zc001d-lr/orphan-2', pg_temp.zc_owner());
select is(pg_temp.lr_r('ro_o2') - 'server_ts',
  jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('lr-o2'), 'state', 'unknown', 'classification', 'resolved',
                     'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS',
                     'resolution', 'provider_refunded', 'attempt_row_id', pg_temp.lr_aid('claim_o2')),
  'LR-92 a LIVE provider_anomaly -> provider_refunded: envelope state unknown, classification resolved, resolution provider_refunded');
select results_eq(
  $$ select (pg_temp.lr_r('claim_active_o2') #>> '{}')::boolean, a.resolution, a.resolution_reference,
            a.resolved_at is not null, a.order_freed_at is not null, a.order_freed_reason,
            app.card_order_claim_active(a.organization_id, a.order_id)
       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_o2') $$,
  $$ values (true, 'provider_refunded'::text, 'lr-refund-ref-2'::text, true, true, 'orphan_resolved'::text, false) $$,
  'LR-93 the anomaly held the order claim; resolved, its order is freed (orphan_resolved) and the claim is released');
select is(jsonb_build_object('events', (select jsonb_agg(jsonb_build_object('action', e.action, 'detail', e.detail))
                                          from pg_temp.lr_new_events() e),
                             'audit_added', pg_temp.lr_audit_count() - (pg_temp.lr_r('audit_n_o2') #>> '{}')::bigint),
  jsonb_build_object('events', jsonb_build_array(jsonb_build_object('action', 'operator.card_attempt_orphan_resolved',
                       'detail', jsonb_build_object('resolution', 'provider_refunded', 'attempt_state', 'unknown'))),
                     'audit_added', 0),
  'LR-94 ... one operator.card_attempt_orphan_resolved {provider_refunded, unknown} and no tenant audit row');

-- 4.6 An order_freed orphan: the manager free (provider evidence) stamps first, a late exact approval
--     follows; the operator resolution keeps the earlier free stamp.
select pg_temp.zc_order('lr-o6', 1234);
set local role service_role;
insert into _zc_r select 'claim_o6', pg_temp.lr_claim(1, pg_temp.zc_lop('lr-o6'), 'live', 1234,
                                                      pg_temp.zc_id('order-lr-o6'), 1, 'lr-term-l2', 'lr-cred-l2');
insert into _zc_r select 'fin_o6_unknown', pg_temp.zc_finish(pg_temp.lr_r('claim_o6'), 'commit', 'unknown');
insert into _zc_r select 'fin_o6_lookup', pg_temp.zc_finish(pg_temp.lr_r('claim_o6'), 'lookup', 'not_found',
                                                            '{}'::jsonb, 'operator');
insert into _zc_r select 'free_o6', public.card_attempt_free_order(pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'),
  'zc-token-1', pg_temp.zc_lop('lr-o6'), 'ZC001D LR provider report shows no charge', 'provider_report', 'lr-conf-6', pg_temp.zc_caller());
insert into _zc_r select 'fin_o6_late', pg_temp.zc_finish(pg_temp.lr_r('claim_o6'), 'lookup', 'approved',
  pg_temp.zc_approved_fields() || '{"provider_amount": "12.34", "provider_currency": "ILS"}'::jsonb);
reset role;
insert into _zc_r select 'o6_before', (select jsonb_build_object('freed_at', a.order_freed_at, 'reason', a.order_freed_reason,
                                                                 'state', a.state,
                                                                 'classification', x.d ->> 'classification',
                                                                 'why', x.d ->> 'reason')
                                         from app.card_provider_attempts a
                                         cross join lateral (select app.card_attempt_derive(a) as d) x
                                        where a.id = pg_temp.lr_aid('claim_o6'));
select is(pg_temp.lr_r('o6_before') - 'freed_at',
  '{"reason": "manager_confirmed", "state": "approved", "classification": "orphan_approved", "why": "order_freed"}'::jsonb,
  'LR-95 setup: a manager free on provider evidence, then a late exact approval -> orphan_approved / order_freed');
select pg_temp.lr_snap();
insert into _zc_r select 'ro_o6', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o6'), 'provider_voided',
  'lr-void-ref-6', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-6', pg_temp.zc_owner());
select results_eq(
  $$ select a.resolution, a.order_freed_at = (pg_temp.lr_r('o6_before') ->> 'freed_at')::timestamptz,
            a.order_freed_reason, a.confirmation_source, a.confirmation_reference,
            (select count(*) from pg_temp.lr_new_events() e where e.action = 'operator.card_attempt_orphan_resolved')
       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_o6') $$,
  $$ values ('provider_voided'::text, true, 'manager_confirmed'::text, 'provider_report'::text, 'lr-conf-6'::text, 1::bigint) $$,
  'LR-96 resolving an order_freed orphan keeps the earlier manager free stamp (order_freed_at unchanged, order_freed_reason manager_confirmed) and writes one orphan_resolved event');

-- Settle d1's remaining LIVE attempts (o3 declined; o5 provider_voided) so its binding can retire.
set local role service_role;
insert into _zc_r select 'fin_o3', pg_temp.zc_finish(pg_temp.lr_r('claim_o3'), 'commit', 'declined',
                                                     '{"approval_type": "declined"}'::jsonb);
reset role;
insert into _zc_r select 'ro_o5', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_o5'), 'provider_voided',
  'lr-void-ref-5', 'ZC001D LR provider void confirmed', 'zc001d-lr/orphan-5', pg_temp.zc_owner());

-- =============================================================================
-- 5. TEST: the cap-less start (M6), the TEST closure (test_closed), the TEST binding gates.
-- =============================================================================
select pg_temp.lr_term(1, 'live', 'draining', 'lr-term-l2', 'lr-cred-l2', 'end_of_pilot');
insert into _zc_r select 'live_retired', pg_temp.lr_term(1, 'live', 'retired', 'lr-term-l2', 'lr-cred-l2', 'end_of_pilot');
-- An ON TEST revision without a test cap: the setter refuses it (max_test_amount_missing), so the row is
-- appended directly by the owner to prove the claim's own guard (D-057 point 8).
insert into app.card_payments_pilot_revisions (organization_id, restaurant_id, branch_id, enabled, mode, window_until,
    max_test_amount_minor, max_live_amount_minor, reason, operator_reference, actor_app_user_id, executor_principal)
  values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), true, 'test', now() + interval '1 hour', null, null,
          'ZC001D LR cap-less TEST revision', 'zc001d-lr/rev-capless', pg_temp.zc_owner(), session_user);
insert into _zc_r select 'bind_d2_test', pg_temp.zc_bind(2, 'test');
set local role service_role;
insert into _zc_r select 'claim_capless', pg_temp.zc_claim(8, pg_temp.zc_lop('lr-capless'), 'test', 500);
reset role;
select is(jsonb_build_object('d1_live_retired', pg_temp.lr_r('live_retired') -> 'new_lifecycle',
                             'd2_test_binding', pg_temp.lr_r('bind_d2_test') -> 'new_lifecycle',
                             'claim', pg_temp.lr_r('claim_capless') - 'server_ts',
                             'ledger_rows', (select count(*) from app.card_provider_attempts a
                                              where a.local_operation_id = pg_temp.zc_lop('lr-capless'))),
  jsonb_build_object('d1_live_retired', 'retired', 'd2_test_binding', 'enabled',
                     'claim', pg_temp.lr_refusal('card_payments_disabled'), 'ledger_rows', 0),
  'LR-97 M6: a TEST claim under an ON TEST revision without a test cap (enabled TEST binding) is card_payments_disabled, no ledger row');
select pg_temp.lr_pilot(true, 'test', null, 5000, null);
select is(jsonb_build_object('d2', pg_temp.lr_card_keys(8, 2), 'd1', pg_temp.lr_card_keys(1, 1)),
  '{"d2": {"card_terminal_enabled": true, "card_terminal_mode": "test"}, "d1": {}}'::jsonb,
  'LR-98 capabilities in TEST mode: enabled TEST binding + revision ON TEST -> true / test on d2; d1 (its LIVE row retired) carries no card key');
set local role service_role;
insert into _zc_r select 'claim_' || l, pg_temp.zc_claim(8, pg_temp.zc_lop('lr-' || l), 'test', 500)
  from unnest(array['ta', 'tb', 'tc', 'td', 'te', 'tf', 'tg']) l;
insert into _zc_r select 'fin_tb', pg_temp.zc_finish(pg_temp.lr_r('claim_tb'), 'commit', 'unknown');
insert into _zc_r select 'fin_tc', pg_temp.zc_finish(pg_temp.lr_r('claim_tc'), 'release', 'released');
insert into _zc_r select 'fin_td', pg_temp.zc_finish(pg_temp.lr_r('claim_td'), 'commit', 'declined',
                                                     '{"approval_type": "declined"}'::jsonb);
insert into _zc_r select 'fin_tf', pg_temp.zc_finish(pg_temp.lr_r('claim_tf'), 'commit', 'unknown');
insert into _zc_r select 'fin_tg', pg_temp.zc_finish(pg_temp.lr_r('claim_tg'), 'commit', 'approved', pg_temp.zc_approved_fields());
reset role;
select results_eq(
  $$ select u.l, a.mode, a.state, a.resolution
       from unnest(array['ta', 'tb', 'tc', 'td', 'te', 'tf', 'tg']) with ordinality u(l, n)
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid('claim_' || u.l) order by u.n $$,
  $$ values ('ta'::text, 'test'::text, 'sent'::text, null::text), ('tb', 'test', 'unknown', null),
            ('tc', 'test', 'released', null), ('td', 'test', 'declined', null), ('te', 'test', 'sent', null),
            ('tf', 'test', 'unknown', null), ('tg', 'test', 'approved', null) $$,
  'LR-99 setup: seven TEST attempts on d2 (sent, unknown, released, declined, sent, unknown, approved)');

-- 5.1 TEST closure refusals.
select pg_temp.lr_snap();
insert into _zc_r select 'tc_early', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_ta'), 'test_closed',
  'lr-test-ref-a', 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-a', pg_temp.zc_owner());
insert into _zc_r select 'tc_declined', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_td'), 'test_closed',
  'lr-test-ref-d', 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-d', pg_temp.zc_owner());
insert into _zc_r select 'tc_live_token', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_tf'), 'provider_voided',
  'lr-test-ref-f', 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-f', pg_temp.zc_owner());
insert into _zc_r select 'tc_approved', app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_tg'), 'test_closed',
  'lr-test-ref-g', 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-g', pg_temp.zc_owner());
select is(jsonb_build_object('sent_before_deadline', pg_temp.lr_r('tc_early'), 'declined', pg_temp.lr_r('tc_declined'),
                             'approved', pg_temp.lr_r('tc_approved'), 'live_token_on_test', pg_temp.lr_r('tc_live_token'),
                             'events', (select count(*) from pg_temp.lr_new_events()),
                             'resolved_test_rows', (select count(*) from app.card_provider_attempts a
                                                     where a.mode = 'test' and a.device_id = pg_temp.zc_id('device-2')
                                                       and a.resolution is not null and a.created_at >= now())),
  jsonb_build_object('sent_before_deadline', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'declined', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'approved', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'live_token_on_test', pg_temp.lr_refusal('precondition_failed', 'attempt_not_resolvable'),
                     'events', 0, 'resolved_test_rows', 0),
  'LR-100 test_closed is refused for a TEST attempt still sent before its start deadline, a declined and an approved one, and provider_voided is refused on a TEST attempt: attempt_not_resolvable, nothing written');

-- 5.2 test_closed: sent past its deadline, unknown, released.
select pg_temp.lr_age_attempt(pg_temp.lr_aid('claim_ta'), true, false);
select pg_temp.lr_snap();
insert into _zc_r select 'audit_n_t', to_jsonb(pg_temp.lr_audit_count());
insert into _zc_r select 'tc_' || l, app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_t' || l), 'test_closed',
  'lr-test-ref-' || l, 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-' || l, pg_temp.zc_owner())
  from unnest(array['a', 'b', 'c']) l;
select is(jsonb_build_array(pg_temp.lr_r('tc_a') - 'server_ts', pg_temp.lr_r('tc_b') - 'server_ts',
                            pg_temp.lr_r('tc_c') - 'server_ts'),
  jsonb_build_array(
    jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('lr-ta'), 'state', 'sent', 'classification', 'test_sent',
                       'recorded', false, 'amount_minor', 500, 'currency_code', 'ILS', 'resolution', 'test_closed',
                       'attempt_row_id', pg_temp.lr_aid('claim_ta')),
    jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('lr-tb'), 'state', 'unknown', 'classification', 'test_unknown',
                       'recorded', false, 'amount_minor', 500, 'currency_code', 'ILS', 'resolution', 'test_closed',
                       'attempt_row_id', pg_temp.lr_aid('claim_tb')),
    jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('lr-tc'), 'state', 'released', 'classification', 'test_released',
                       'recorded', false, 'amount_minor', 500, 'currency_code', 'ILS', 'resolution', 'test_closed',
                       'attempt_row_id', pg_temp.lr_aid('claim_tc'))),
  'LR-101 test_closed is allowed for a TEST attempt sent past its start deadline, unknown, or released: envelope test_<state> with resolution test_closed');
select results_eq(
  $$ select u.l, a.resolution, a.resolution_reference, a.resolved_at is not null, a.order_freed_at, a.order_freed_reason,
            (app.card_attempt_derive(a) ->> 'unresolved')::boolean
       from unnest(array['a', 'b', 'c']) with ordinality u(l, n)
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid('claim_t' || u.l) order by u.n $$,
  $$ values ('a'::text, 'test_closed'::text, 'lr-test-ref-a'::text, true, null::timestamptz, null::text, false),
            ('b', 'test_closed', 'lr-test-ref-b', true, null, null, false),
            ('c', 'test_closed', 'lr-test-ref-c', true, null, null, false) $$,
  'LR-102 the closed TEST rows carry resolution test_closed, the resolution_reference and resolved_at, no order free, and leave the unresolved set');
select is(jsonb_build_object('events', (select jsonb_agg(jsonb_build_object('action', e.action, 'attempt', e.attempt_row_id,
                                                                            'mode', e.mode, 'actor_kind', e.actor_kind,
                                                                            'executor', e.executor_principal,
                                                                            'reference', e.actor_reference, 'detail', e.detail)
                                                         order by e.created_at, e.id) from pg_temp.lr_new_events() e),
                             'audit_added', pg_temp.lr_audit_count() - (pg_temp.lr_r('audit_n_t') #>> '{}')::bigint),
  jsonb_build_object('events', jsonb_build_array(
      jsonb_build_object('action', 'operator.card_attempt_test_closed', 'attempt', pg_temp.lr_aid('claim_ta'), 'mode', null,
                         'actor_kind', 'attested_owner_approver', 'executor', pg_temp.lr_exec(),
                         'reference', 'zc001d-lr/test-close-a',
                         'detail', jsonb_build_object('resolution', 'test_closed', 'attempt_state', 'sent')),
      jsonb_build_object('action', 'operator.card_attempt_test_closed', 'attempt', pg_temp.lr_aid('claim_tb'), 'mode', null,
                         'actor_kind', 'attested_owner_approver', 'executor', pg_temp.lr_exec(),
                         'reference', 'zc001d-lr/test-close-b',
                         'detail', jsonb_build_object('resolution', 'test_closed', 'attempt_state', 'unknown')),
      jsonb_build_object('action', 'operator.card_attempt_test_closed', 'attempt', pg_temp.lr_aid('claim_tc'), 'mode', null,
                         'actor_kind', 'attested_owner_approver', 'executor', pg_temp.lr_exec(),
                         'reference', 'zc001d-lr/test-close-c',
                         'detail', jsonb_build_object('resolution', 'test_closed', 'attempt_state', 'released'))),
    'audit_added', 0),
  'LR-103 each TEST closure writes one operator.card_attempt_test_closed {resolution, attempt_state} (mode NULL, attested approver, executor) and no tenant audit row');

-- 5.3 A provider fact reaching a closed TEST attempt.
insert into _zc_r select 'row_tb_before', (select to_jsonb(a) from app.card_provider_attempts a
                                            where a.id = pg_temp.lr_aid('claim_tb'));
select pg_temp.lr_snap();
set local role service_role;
insert into _zc_r select 'fin_tb_late', pg_temp.zc_finish(pg_temp.lr_r('claim_tb'), 'lookup', 'approved',
  pg_temp.zc_approved_fields() || '{"provider_amount": "5.00", "provider_currency": "ILS"}'::jsonb);
reset role;
select is(jsonb_build_object('envelope', pg_temp.lr_r('fin_tb_late') - 'server_ts',
                             'row_unchanged', (select to_jsonb(a) from app.card_provider_attempts a
                                                where a.id = pg_temp.lr_aid('claim_tb')) = pg_temp.lr_r('row_tb_before')),
  jsonb_build_object('envelope', pg_temp.lr_r('tc_b') - 'server_ts' - 'attempt_row_id', 'row_unchanged', true),
  'LR-104 a lookup approval reaching a test_closed attempt answers its envelope and changes nothing in the row');
select results_eq(
  $$ select e.action, e.mode, e.retention_until = e.created_at + interval '90 days', e.actor_kind, e.actor_reference,
            e.attempt_row_id, e.detail
       from pg_temp.lr_new_events() e $$,
  $$ values ('security.card_resolution_contradicted'::text, 'test'::text, true, 'adapter'::text, 'card_adapter'::text,
             pg_temp.lr_aid('claim_tb'), '{"source": "lookup", "outcome": "approved"}'::jsonb) $$,
  'LR-105 ... and writes exactly one security.card_resolution_contradicted (mode test, 90-day retention, detail {source, outcome})');

-- 5.4 The TEST binding gates: no activation gate for TEST; the retirement gate applies.
select pg_temp.lr_snap();
insert into _zc_r select 'tg_drain', pg_temp.lr_term(2, 'test', 'draining', 'zc-term-test-2', 'zc-cred-test-2', 'incident');
insert into _zc_r select 'tg_reenable', pg_temp.lr_term(2, 'test', 'enabled', 'zc-term-test-2', 'zc-cred-test-2', 'test_setup');
select pg_temp.lr_term(2, 'test', 'draining', 'zc-term-test-2', 'zc-cred-test-2', 'test_end');
insert into _zc_r select 'tg_retire', pg_temp.lr_term(2, 'test', 'retired', 'zc-term-test-2', 'zc-cred-test-2', 'test_end');
select is(jsonb_build_object('drain', pg_temp.lr_r('tg_drain'), 'reenable', pg_temp.lr_r('tg_reenable'),
                             'retire', pg_temp.lr_r('tg_retire'),
                             'lifecycle', (select t.lifecycle from pg_temp.lr_current(2) t)),
  jsonb_build_object('drain', pg_temp.lr_tres('test', 'enabled', 'draining'),
                     'reenable', pg_temp.lr_tres('test', 'draining', 'enabled'),
                     'retire', pg_temp.lr_refusal('precondition_failed', 'attempt_unresolved'), 'lifecycle', 'draining'),
  'LR-106 TEST binding with unresolved TEST attempts (te sent, tf unknown): draining and re-enabling pass (the activation gate is LIVE-only); retirement -> attempt_unresolved');
select pg_temp.lr_term(2, 'test', 'enabled', 'zc-term-test-2', 'zc-cred-test-2', 'test_setup');

-- =============================================================================
-- 6. app.card_attempt_set_incident_hold (D-057 point 8).
-- =============================================================================
select pg_temp.lr_snap();
insert into _zc_r select 'hold_te', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_te'), true,
  ' lr-hold-ref-1 ', 'ZC001D LR incident hold', 'zc001d-lr/hold-1', pg_temp.zc_owner());
select is(jsonb_build_object('result', pg_temp.lr_r('hold_te'),
                             'row', (select jsonb_build_object('held', a.incident_hold_at is not null,
                                                               'reference', a.incident_hold_reference, 'state', a.state)
                                       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_te')),
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'attempt', e.attempt_row_id,
                                                                            'device', e.device_id, 'mode', e.mode,
                                                                            'reference', e.actor_reference,
                                                                            'executor', e.executor_principal,
                                                                            'detail', e.detail))
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('result', '{"ok": true, "target_kind": "attempt", "hold": true}'::jsonb,
                     'row', '{"held": true, "reference": "lr-hold-ref-1", "state": "sent"}'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempt_hold_updated',
                       'attempt', pg_temp.lr_aid('claim_te'), 'device', pg_temp.zc_id('device-2'), 'mode', null,
                       'reference', 'zc001d-lr/hold-1', 'executor', pg_temp.lr_exec(),
                       'detail', '{"target_kind": "attempt", "hold": true}'::jsonb))),
  'LR-107 set_incident_hold on a TEST attempt: sets incident_hold_at and the canonical reference; one operator.card_test_attempt_hold_updated {target_kind attempt, hold true}');
select pg_temp.lr_snap();
insert into _zc_r select 'unhold_te', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_te'), false,
  null, 'ZC001D LR incident closed', 'zc001d-lr/hold-1', pg_temp.zc_owner());
select is(jsonb_build_object('result', pg_temp.lr_r('unhold_te'),
                             'row', (select jsonb_build_array(a.incident_hold_at, a.incident_hold_reference)
                                       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_te')),
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'detail', e.detail))
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('result', '{"ok": true, "target_kind": "attempt", "hold": false}'::jsonb,
                     'row', '[null, null]'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempt_hold_updated',
                       'detail', '{"target_kind": "attempt", "hold": false}'::jsonb))),
  'LR-108 clearing the TEST attempt hold: both hold columns NULL; one event {target_kind attempt, hold false}');
insert into _zc_r select 'row_ta_before', (select to_jsonb(a) - 'incident_hold_at' - 'incident_hold_reference' - 'updated_at'
                                             from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_ta'));
select pg_temp.lr_snap();
insert into _zc_r select 'hold_ta', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_ta'), true,
  'lr-hold-ref-ta', 'ZC001D LR incident hold', 'zc001d-lr/hold-ta', pg_temp.zc_owner());
insert into _zc_r select 'held_ta', (select jsonb_build_array(a.incident_hold_at is not null, a.incident_hold_reference)
                                       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_ta'));
insert into _zc_r select 'unhold_ta', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_ta'), false,
  null, 'ZC001D LR incident closed', 'zc001d-lr/hold-ta', pg_temp.zc_owner());
select is(jsonb_build_object('hold', pg_temp.lr_r('hold_ta'), 'held', pg_temp.lr_r('held_ta'),
                             'unhold', pg_temp.lr_r('unhold_ta'),
                             'facts_unchanged', (select to_jsonb(a) - 'incident_hold_at' - 'incident_hold_reference' - 'updated_at'
                                                   from app.card_provider_attempts a
                                                  where a.id = pg_temp.lr_aid('claim_ta')) = pg_temp.lr_r('row_ta_before'),
                             'events', (select count(*) from pg_temp.lr_new_events())),
  jsonb_build_object('hold', '{"ok": true, "target_kind": "attempt", "hold": true}'::jsonb,
                     'held', '[true, "lr-hold-ref-ta"]'::jsonb,
                     'unhold', '{"ok": true, "target_kind": "attempt", "hold": false}'::jsonb,
                     'facts_unchanged', true, 'events', 2),
  'LR-109 a resolved (test_closed) TEST attempt still takes and releases a hold (its only mutable metadata); every other column unchanged, one event each');
select pg_temp.lr_snap();
set local role service_role;
insert into _zc_r select 'claim_deny_hold', pg_temp.zc_claim(8, pg_temp.zc_lop('lr-deny-hold'), 'test', 6000);
reset role;
insert into _zc_r select 'ev_deny_hold', (select to_jsonb(e) from pg_temp.lr_new_events() e order by e.created_at limit 1);
select is(jsonb_build_object('claim', pg_temp.lr_r('claim_deny_hold') - 'server_ts',
                             'events', (select count(*) from pg_temp.lr_new_events()),
                             'action', pg_temp.lr_r('ev_deny_hold') -> 'action', 'mode', pg_temp.lr_r('ev_deny_hold') -> 'mode',
                             'attempt', pg_temp.lr_r('ev_deny_hold') -> 'attempt_row_id'),
  jsonb_build_object('claim', pg_temp.lr_refusal('precondition_failed', 'max_test_amount_exceeded'), 'events', 1,
                     'action', 'test.card_attempt_denied', 'mode', 'test', 'attempt', null),
  'LR-110 setup: a TEST claim above the cap writes one attempt-less test.card_attempt_denied (mode test)');
select pg_temp.lr_snap();
insert into _zc_r select 'hold_ev', app.card_attempt_set_incident_hold('event', (pg_temp.lr_r('ev_deny_hold') ->> 'id')::uuid,
  true, 'lr-hold-ref-2', 'ZC001D LR incident hold', 'zc001d-lr/hold-2', pg_temp.zc_owner());
select is(jsonb_build_object('result', pg_temp.lr_r('hold_ev'),
                             'row', (select jsonb_build_object('held', e.incident_hold_at is not null,
                                                               'reference', e.incident_hold_reference)
                                       from app.card_provider_private_events e
                                      where e.id = (pg_temp.lr_r('ev_deny_hold') ->> 'id')::uuid),
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'attempt', e.attempt_row_id,
                                                                            'device', e.device_id, 'mode', e.mode,
                                                                            'detail', e.detail))
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('result', '{"ok": true, "target_kind": "event", "hold": true}'::jsonb,
                     'row', '{"held": true, "reference": "lr-hold-ref-2"}'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempt_hold_updated',
                       'attempt', null, 'device', pg_temp.zc_id('device-2'), 'mode', null,
                       'detail', '{"target_kind": "event", "hold": true}'::jsonb))),
  'LR-111 set_incident_hold on a TEST event: sets its hold columns; one event {target_kind event, hold true}');
select pg_temp.lr_snap();
insert into _zc_r select 'unhold_ev', app.card_attempt_set_incident_hold('event', (pg_temp.lr_r('ev_deny_hold') ->> 'id')::uuid,
  false, null, 'ZC001D LR incident closed', 'zc001d-lr/hold-2', pg_temp.zc_owner());
select is(jsonb_build_object('result', pg_temp.lr_r('unhold_ev'),
                             'row', (select jsonb_build_array(e.incident_hold_at, e.incident_hold_reference)
                                       from app.card_provider_private_events e
                                      where e.id = (pg_temp.lr_r('ev_deny_hold') ->> 'id')::uuid),
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'detail', e.detail))
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('result', '{"ok": true, "target_kind": "event", "hold": false}'::jsonb, 'row', '[null, null]'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempt_hold_updated',
                       'detail', '{"target_kind": "event", "hold": false}'::jsonb))),
  'LR-112 clearing the TEST event hold: both hold columns NULL; one event {target_kind event, hold false}');
select pg_temp.lr_snap();
insert into _zc_r select 'h_live', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_o1'), true,
  'lr-hold-ref-3', 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
insert into _zc_r select 'h_op_event', app.card_attempt_set_incident_hold('event',
  (select e.id from app.card_provider_private_events e where e.action = 'operator.card_payments_pilot_updated'
    order by e.created_at limit 1),
  true, 'lr-hold-ref-3', 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
insert into _zc_r select 'h_live_event', app.card_attempt_set_incident_hold('event',
  (select e.id from app.card_provider_private_events e where e.action = 'security.card_resolution_contradicted'
      and e.mode = 'live' order by e.created_at limit 1),
  true, 'lr-hold-ref-3', 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
select is(jsonb_build_object('live_attempt', pg_temp.lr_r('h_live'), 'operator_event', pg_temp.lr_r('h_op_event'),
                             'live_security_event', pg_temp.lr_r('h_live_event')),
  jsonb_build_object('live_attempt', pg_temp.lr_refusal('precondition_failed', 'attempt_not_test'),
                     'operator_event', pg_temp.lr_refusal('precondition_failed', 'event_not_test'),
                     'live_security_event', pg_temp.lr_refusal('precondition_failed', 'event_not_test')),
  'LR-113 set_incident_hold refuses a LIVE attempt (attempt_not_test), an operator.* event and a LIVE security event (event_not_test)');
insert into _zc_r select 'h_no_ref', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_te'), true, null,
  'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
insert into _zc_r select 'h_card_ref', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_te'), true,
  repeat('7351', 4), 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
insert into _zc_r select 'h_unknown_attempt', app.card_attempt_set_incident_hold('attempt', pg_temp.zc_id('attempt-lr-none'),
  true, 'lr-hold-ref-3', 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
insert into _zc_r select 'h_unknown_event', app.card_attempt_set_incident_hold('event', pg_temp.zc_id('event-lr-none'),
  true, 'lr-hold-ref-3', 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
insert into _zc_r select 'h_staff2', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_te'), true,
  'lr-hold-ref-3', 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_id('user-2'));
insert into _zc_r select 'h_kind', app.card_attempt_set_incident_hold('order', pg_temp.lr_aid('claim_te'), true,
  'lr-hold-ref-3', 'ZC001D LR incident hold', 'zc001d-lr/hold-3', pg_temp.zc_owner());
select is(jsonb_build_object('missing_reference', pg_temp.lr_r('h_no_ref'), 'card_number_reference', pg_temp.lr_r('h_card_ref'),
                             'unknown_attempt', pg_temp.lr_r('h_unknown_attempt'),
                             'unknown_event', pg_temp.lr_r('h_unknown_event'), 'staff2', pg_temp.lr_r('h_staff2'),
                             'bad_kind', pg_temp.lr_r('h_kind')),
  jsonb_build_object('missing_reference', pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                     'card_number_reference', pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                     'unknown_attempt', pg_temp.lr_refusal('attempt_not_found'),
                     'unknown_event', pg_temp.lr_refusal('event_not_found'),
                     'staff2', pg_temp.lr_refusal('permission_denied'),
                     'bad_kind', pg_temp.lr_refusal('invalid_request')),
  'LR-114 set_incident_hold refusals: a hold without (or with a card-number) reference -> out_of_contract; unknown attempt / event -> attempt_not_found / event_not_found; non-owner -> permission_denied; unknown target kind -> invalid_request');
select is(jsonb_build_object('events', (select count(*) from pg_temp.lr_new_events()),
                             'held_rows', (select count(*) from app.card_provider_attempts a where a.incident_hold_at is not null and a.created_at >= now()),
                             'held_events', (select count(*) from app.card_provider_private_events e
                                              where e.incident_hold_at is not null and e.created_at >= now())),
  '{"events": 0, "held_rows": 0, "held_events": 0}'::jsonb,
  'LR-115 those hold refusals write no event and set no hold anywhere');

-- =============================================================================
-- 7. app.purge_expired_test_card_attempts and the identity tombstones (D-053 point 4, D-058 point 7).
-- =============================================================================
set local role service_role;
insert into _zc_r select 'claim_' || l, pg_temp.zc_claim(8, pg_temp.zc_lop('lr-' || l), 'test', 500)
  from unnest(array['pa1', 'pa2', 'pa3', 'pa4']) l;
insert into _zc_r select 'fin_pa1', pg_temp.zc_finish(pg_temp.lr_r('claim_pa1'), 'commit', 'unknown',
                                                      '{"provider_saved_at": "not-a-timestamp"}'::jsonb);
insert into _zc_r select 'fin_pa1b', pg_temp.zc_finish(pg_temp.lr_r('claim_pa1'), 'lookup', 'not_found',
                                                       '{"provider_return_code": "x1"}'::jsonb);
insert into _zc_r select 'fin_pa2', pg_temp.zc_finish(pg_temp.lr_r('claim_pa2'), 'commit', 'unknown',
                                                      '{"provider_saved_at": "not-a-timestamp"}'::jsonb);
insert into _zc_r select 'fin_pa3', pg_temp.zc_finish(pg_temp.lr_r('claim_pa3'), 'commit', 'unknown',
                                                      '{"provider_saved_at": "not-a-timestamp"}'::jsonb);
reset role;
insert into _zc_r select 'ev_pa1', (select to_jsonb(e) from app.card_provider_private_events e
  where e.attempt_row_id = pg_temp.lr_aid('claim_pa1') and e.action = 'security.card_provider_field_dropped'
    and e.detail ->> 'field' = 'provider_saved_at');
insert into _zc_r select 'ev_pa1_own', (select to_jsonb(e) from app.card_provider_private_events e
  where e.attempt_row_id = pg_temp.lr_aid('claim_pa1') and e.action = 'security.card_provider_field_dropped'
    and e.detail ->> 'field' = 'provider_return_code');
insert into _zc_r select 'ev_pa2', (select to_jsonb(e) from app.card_provider_private_events e
  where e.attempt_row_id = pg_temp.lr_aid('claim_pa2') and e.action = 'security.card_provider_field_dropped');
insert into _zc_r select 'ev_pa3', (select to_jsonb(e) from app.card_provider_private_events e
  where e.attempt_row_id = pg_temp.lr_aid('claim_pa3') and e.action = 'security.card_provider_field_dropped');
select pg_temp.lr_snap();
set local role service_role;
insert into _zc_r select 'claim_deny_old', pg_temp.zc_claim(8, pg_temp.zc_lop('lr-deny-old'), 'test', 6000);
reset role;
insert into _zc_r select 'ev_deny_old', (select to_jsonb(e) from pg_temp.lr_new_events() e order by e.created_at limit 1);
select pg_temp.lr_snap();
set local role service_role;
insert into _zc_r select 'claim_deny_new', pg_temp.zc_claim(8, pg_temp.zc_lop('lr-deny-new'), 'test', 6000);
reset role;
insert into _zc_r select 'ev_deny_new', (select to_jsonb(e) from pg_temp.lr_new_events() e order by e.created_at limit 1);
-- Holds: the attempt pa2; the event of pa1 for provider_return_code (its own hold).
insert into _zc_r select 'hold_pa2', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_pa2'), true,
  'lr-hold-ref-p2', 'ZC001D LR keep the evidence', 'zc001d-lr/hold-p2', pg_temp.zc_owner());
insert into _zc_r select 'hold_pa1_own', app.card_attempt_set_incident_hold('event', (pg_temp.lr_r('ev_pa1_own') ->> 'id')::uuid,
  true, 'lr-hold-ref-e1', 'ZC001D LR keep the evidence', 'zc001d-lr/hold-e1', pg_temp.zc_owner());
-- Expire: attempts pa1, pa2, pa4; events of pa1 (both), pa2, pa3 and the old denial.
select pg_temp.lr_age_attempt(pg_temp.lr_aid('claim_' || l), false, true) from unnest(array['pa1', 'pa2', 'pa4']) l;
select pg_temp.lr_age_event((pg_temp.lr_r('ev_' || l) ->> 'id')::uuid)
  from unnest(array['pa1', 'pa1_own', 'pa2', 'pa3', 'deny_old']) l;
create temp table _lr_doomed as
  select a.* from app.card_provider_attempts a where a.id in (pg_temp.lr_aid('claim_pa1'), pg_temp.lr_aid('claim_pa4'));
select results_eq(
  $$ select u.l, a.mode, a.retention_until <= clock_timestamp(), a.incident_hold_at is not null
       from unnest(array['pa1', 'pa2', 'pa3', 'pa4']) with ordinality u(l, n)
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid('claim_' || u.l) order by u.n $$,
  $$ values ('pa1'::text, 'test'::text, true, false), ('pa2', 'test', true, true), ('pa3', 'test', false, false),
            ('pa4', 'test', true, false) $$,
  'LR-116 purge setup: TEST attempts pa1 / pa4 expired and unheld, pa2 expired but held, pa3 not expired');
select results_eq(
  $$ select u.l, e.mode, e.action, e.retention_until <= clock_timestamp(), e.incident_hold_at is not null
       from unnest(array['pa1', 'pa1_own', 'pa2', 'pa3', 'deny_old', 'deny_new']) with ordinality u(l, n)
       join app.card_provider_private_events e on e.id = (pg_temp.lr_r('ev_' || u.l) ->> 'id')::uuid order by u.n $$,
  $$ values ('pa1'::text, 'test'::text, 'security.card_provider_field_dropped'::text, true, false),
            ('pa1_own', 'test', 'security.card_provider_field_dropped', true, true),
            ('pa2', 'test', 'security.card_provider_field_dropped', true, false),
            ('pa3', 'test', 'security.card_provider_field_dropped', true, false),
            ('deny_old', 'test', 'test.card_attempt_denied', true, false),
            ('deny_new', 'test', 'test.card_attempt_denied', false, false) $$,
  'LR-117 purge setup: TEST events of pa1 (one with its own hold), pa2 (held attempt), pa3 and an old attempt-less denial expired; a new denial not expired');
insert into _zc_r select 'pre_purge', pg_temp.lr_purge_counts();
select pg_temp.lr_snap();
insert into _zc_r select 'purge_staff2', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/purge-1', pg_temp.zc_id('user-2'));
select is(jsonb_build_object('result', pg_temp.lr_r('purge_staff2'), 'counts', pg_temp.lr_purge_counts(),
                             'events', (select count(*) from pg_temp.lr_new_events())),
  jsonb_build_object('result', pg_temp.lr_refusal('permission_denied'), 'counts', pg_temp.lr_r('pre_purge'), 'events', 0),
  'LR-118 purge by a non-owner actor (staff 2) -> permission_denied: nothing deleted, no tombstone, no event');
select pg_temp.lr_snap();
insert into _zc_r select 'purge', app.purge_expired_test_card_attempts(U&'ZC001D LR TEST evidence purge\3000',
  'zc001d-lr/purge-1', pg_temp.zc_owner());
select is(pg_temp.lr_r('purge') - 'cutoff',
  '{"ok": true, "attempts_purged": 2, "events_purged": 3, "attempts_deferred": 0, "events_deferred": 0,
    "devices_locked": 1}'::jsonb,
  'LR-119 (C1-3) purge: ok with exact counts (2 expired unheld TEST attempts, 3 expired unheld TEST events), nothing deferred, one device locked (d2, the only device holding expired TEST rows)');
select results_eq(
  $$ select u.l, exists (select 1 from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_' || u.l))
       from unnest(array['pa1', 'pa2', 'pa3', 'pa4']) with ordinality u(l, n) order by u.n $$,
  $$ values ('pa1'::text, false), ('pa2', true), ('pa3', true), ('pa4', false) $$,
  'LR-120 purge deletes only the expired, unheld TEST attempts (pa1, pa4); the held (pa2) and the unexpired (pa3) stay');
select bag_eq(
  $$ select t.organization_id, t.device_id, t.local_operation_id, t.provider_status_digest, t.provider_duplicate_digest,
            t.provider_key_format_version, t.provider_query_key, t.provider_duplicate_key, t.purged_at is not null
       from app.card_attempt_identity_tombstones t $$,
  $$ select d.organization_id, d.device_id, d.local_operation_id, d.provider_status_digest, d.provider_duplicate_digest,
            d.provider_key_format_version, d.provider_query_key, d.provider_duplicate_key, true
       from _lr_doomed d $$,
  'LR-121 one tombstone per deleted attempt: the identity tuple, both digests, the formatter version and both outbound keys equal the deleted row');
select results_eq(
  $$ select u.l, exists (select 1 from app.card_provider_private_events e where e.id = (pg_temp.lr_r('ev_' || u.l) ->> 'id')::uuid)
       from unnest(array['pa1', 'pa1_own', 'pa2', 'pa3', 'deny_old', 'deny_new']) with ordinality u(l, n) order by u.n $$,
  $$ values ('pa1'::text, false), ('pa1_own', true), ('pa2', true), ('pa3', false), ('deny_old', false), ('deny_new', true) $$,
  'LR-122 purge deletes the expired mode=test events without an own hold whose attempt is unheld (pa1, pa3, the attempt-less denial); keeps the event-held one, the held attempt''s event and the unexpired denial');
select is(pg_temp.lr_purge_counts(),
  pg_temp.lr_r('pre_purge') || jsonb_build_object(
    'test_attempts', (pg_temp.lr_r('pre_purge') ->> 'test_attempts')::int - 2,
    'test_events', (pg_temp.lr_r('pre_purge') ->> 'test_events')::int - 3,
    'operator_events', (pg_temp.lr_r('pre_purge') ->> 'operator_events')::int + 1,
    'tombstones', (pg_temp.lr_r('pre_purge') ->> 'tombstones')::int + 2),
  'LR-123 after the purge: every LIVE attempt and LIVE event kept, operator.* events + 1 (the purge event only), TEST attempts - 2, TEST events - 3, tombstones + 2');
select results_eq(
  $$ select e.action, e.mode, e.retention_until, e.attempt_row_id, e.device_id, e.actor_kind, e.actor_reference,
            e.actor_app_user_id, e.executor_principal, e.reason, e.detail
       from pg_temp.lr_new_events() e $$,
  $$ select 'operator.card_test_attempts_purged'::text, null::text, null::timestamptz, null::uuid, null::uuid,
            'attested_owner_approver'::text, 'zc001d-lr/purge-1'::text, pg_temp.zc_owner(), pg_temp.lr_exec(),
            'ZC001D LR TEST evidence purge'::text,
            jsonb_build_object('attempts_purged', 2, 'events_purged', 3, 'attempts_deferred', 0, 'events_deferred', 0,
                               'devices_locked', 1, 'cutoff', pg_temp.lr_r('purge') -> 'cutoff') $$,
  'LR-124 (C1-3) purge writes exactly one operator.card_test_attempts_purged: detail exactly {attempts_purged, events_purged, attempts_deferred, events_deferred, devices_locked, cutoff} with the result''s counts, attested approver, executor, mode NULL');
select is((select jsonb_agg(e.action order by e.created_at, e.id) from app.card_provider_private_events e
            where e.attempt_row_id = pg_temp.lr_aid('claim_pa1')),
  '["security.card_provider_field_dropped", "operator.card_test_attempt_hold_updated"]'::jsonb,
  'LR-125 about the purged attempt pa1 only its own-held TEST event and the operator.* hold event remain (operator events about a purged attempt stay)');
set local role service_role;
insert into _zc_r select 'reclaim_pa1', pg_temp.zc_claim(8, pg_temp.zc_lop('lr-pa1'), 'test', 500);
reset role;
select is(jsonb_build_object('claim', pg_temp.lr_r('reclaim_pa1') - 'server_ts',
                             'rows', (select count(*) from app.card_provider_attempts a
                                       where a.local_operation_id = pg_temp.zc_lop('lr-pa1'))),
  jsonb_build_object('claim', pg_temp.lr_refusal('conflict', 'identity_in_use'), 'rows', 0),
  'LR-126 a purged TEST identity stays refused: re-claiming it -> conflict / identity_in_use (tombstone), no ledger row');
insert into _zc_r select 'purge2', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/purge-2', pg_temp.zc_owner());
select is(pg_temp.lr_r('purge2') - 'cutoff',
  '{"ok": true, "attempts_purged": 0, "events_purged": 0, "attempts_deferred": 0, "events_deferred": 0,
    "devices_locked": 0}'::jsonb,
  'LR-127 (C1-3) a second purge finds nothing left to delete (0 / 0), defers nothing and locks no device (pa2''s expired event carries no hold of its own, but its attempt is held, so it selects nothing - C1 fix 2)');

-- =============================================================================
-- 8. Private-event and tombstone immutability (DOMAIN 8.6 / D-058 point 12).
-- =============================================================================
insert into _zc_r select 'ev_fact_updates', (select jsonb_object_agg(x.c, pg_temp.lr_try(format(
    'update app.card_provider_private_events set %I = %s where id = %L', x.c, x.v,
    (pg_temp.lr_r('ev_deny_new') ->> 'id')::uuid)))
  from (values ('id', 'gen_random_uuid()'), ('organization_id', quote_literal(pg_temp.zc_id('org_b'))),
               ('restaurant_id', quote_literal(pg_temp.zc_id('rest_b'))),
               ('branch_id', quote_literal(pg_temp.zc_id('branch_sib'))), ('attempt_row_id', 'gen_random_uuid()'),
               ('mode', '''live'''), ('action', '''test.card_recording_refused'''), ('actor_kind', '''device'''),
               ('actor_reference', '''device'''), ('actor_app_user_id', quote_literal(pg_temp.zc_owner())),
               ('executor_principal', '''lr_tamper'''),
               ('actor_employee_profile_id', quote_literal(pg_temp.zc_id('employee-2'))),
               ('device_id', quote_literal(pg_temp.zc_id('device-1'))), ('reason', '''ZC001D LR tamper'''),
               ('detail', '''{"rpc": "claim", "denied_reason": "tampered"}'''),
               ('retention_until', 'retention_until + interval ''1 day'''),
               ('created_at', 'created_at - interval ''1 day'''), ('incident_hold_at', 'incident_hold_at')) x(c, v));
select is(pg_temp.lr_r('ev_fact_updates'),
  '{"id": "42501", "organization_id": "42501", "restaurant_id": "42501", "branch_id": "42501", "attempt_row_id": "42501",
    "mode": "42501", "action": "42501", "actor_kind": "42501", "actor_reference": "42501", "actor_app_user_id": "42501",
    "executor_principal": "42501", "actor_employee_profile_id": "42501", "device_id": "42501", "reason": "42501",
    "detail": "42501", "retention_until": "42501", "created_at": "42501", "incident_hold_at": "no_error"}'::jsonb,
  'LR-128 private-event facts are immutable: a direct UPDATE of each of the 17 fact columns of a mode=test event (retention_until included) raises 42501; control: the same probe on the hold column passes');
select is((select to_jsonb(e) from app.card_provider_private_events e where e.id = (pg_temp.lr_r('ev_deny_new') ->> 'id')::uuid),
  pg_temp.lr_r('ev_deny_new'),
  'LR-129 after those refused updates the event row is unchanged');
select lives_ok($$ update app.card_provider_private_events
                      set incident_hold_at = clock_timestamp(), incident_hold_reference = 'lr-hold-direct'
                    where id = (pg_temp.lr_r('ev_deny_new') ->> 'id')::uuid $$,
  'LR-130 only the hold metadata of a mode=test event may change: a direct UPDATE of incident_hold_at / incident_hold_reference passes');
select is((select jsonb_build_array(e.incident_hold_at is not null, e.incident_hold_reference)
             from app.card_provider_private_events e where e.id = (pg_temp.lr_r('ev_deny_new') ->> 'id')::uuid),
  '[true, "lr-hold-direct"]'::jsonb,
  'LR-131 ... and is stored on the event');
select lives_ok($$ update app.card_provider_private_events set incident_hold_at = null, incident_hold_reference = null
                    where id = (pg_temp.lr_r('ev_deny_new') ->> 'id')::uuid $$,
  'LR-132 ... and may be cleared again');
select throws_ok($$ update app.card_provider_private_events
                       set incident_hold_at = clock_timestamp(), incident_hold_reference = 'lr-hold-op'
                     where id = (select e.id from app.card_provider_private_events e
                                  where e.action = 'operator.card_test_attempts_purged' order by e.created_at limit 1) $$,
  '42501', null, 'LR-133 an operator.* event (mode NULL) has no mutable hold: a hold UPDATE raises 42501');
select throws_ok($$ delete from app.card_provider_private_events where id = (pg_temp.lr_r('ev_deny_new') ->> 'id')::uuid $$,
  '42501', null, 'LR-134 DELETE of a non-expired TEST event raises 42501');
select throws_ok($$ delete from app.card_provider_private_events where id = (pg_temp.lr_r('ev_pa1_own') ->> 'id')::uuid $$,
  '42501', null, 'LR-135 DELETE of an expired TEST event carrying its own hold raises 42501');
select throws_ok($$ delete from app.card_provider_private_events where id = (pg_temp.lr_r('ev_pa2') ->> 'id')::uuid $$,
  '42501', null, 'LR-136 DELETE of an expired TEST event whose attempt is held raises 42501');
select throws_ok($$ delete from app.card_provider_private_events where action = 'operator.card_payments_pilot_updated' $$,
  '42501', null, 'LR-137 DELETE of an operator.* event raises 42501');
select throws_ok($$ delete from app.card_provider_private_events
                     where mode = 'live' and action = 'security.card_resolution_contradicted' $$,
  '42501', null, 'LR-138 DELETE of a LIVE security event raises 42501');
select pg_temp.lr_snap();
set local role service_role;
insert into _zc_r select 'claim_deny_x', pg_temp.zc_claim(8, pg_temp.zc_lop('lr-deny-x'), 'test', 6000);
reset role;
insert into _zc_r select 'ev_deny_x', (select to_jsonb(e) from pg_temp.lr_new_events() e order by e.created_at limit 1);
select pg_temp.lr_age_event((pg_temp.lr_r('ev_deny_x') ->> 'id')::uuid);
select lives_ok($$ delete from app.card_provider_private_events where id = (pg_temp.lr_r('ev_deny_x') ->> 'id')::uuid $$,
  'LR-139 the trigger admits the DELETE of an expired attempt-less TEST event without a hold (the purge path)');
select is((select count(*) from app.card_provider_private_events e where e.id = (pg_temp.lr_r('ev_deny_x') ->> 'id')::uuid),
  0::bigint, 'LR-140 ... and that event is gone');
select throws_ok($$ update app.card_attempt_identity_tombstones set purged_at = purged_at - interval '1 day' $$,
  '42501', null, 'LR-141 tombstones are append-only: UPDATE raises 42501');
select throws_ok($$ delete from app.card_attempt_identity_tombstones $$,
  '42501', null, 'LR-142 tombstones are append-only: DELETE raises 42501');
select throws_ok($$ delete from app.card_provider_attempts where id = pg_temp.lr_aid('claim_o1') $$,
  '42501', null, 'LR-143 DELETE of a LIVE attempt raises 42501');
select throws_ok($$ delete from app.card_provider_attempts where id = pg_temp.lr_aid('claim_pa3') $$,
  '42501', null, 'LR-144 DELETE of an unexpired TEST attempt raises 42501');
select throws_ok($$ delete from app.card_provider_attempts where id = pg_temp.lr_aid('claim_pa2') $$,
  '42501', null, 'LR-145 DELETE of an expired but held TEST attempt raises 42501');

-- =============================================================================
-- 9. A failed TEST run never blocks the TEST row (4.55.9): once every unresolved TEST attempt of d2
--    (te sent past its deadline, tf / pa2 / pa3 unknown) is test_closed, the TEST binding retires.
-- =============================================================================
select pg_temp.lr_age_attempt(pg_temp.lr_aid('claim_te'), true, false);
insert into _zc_r select 'close_' || l, app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_' || l), 'test_closed',
  'lr-test-ref-' || l, 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-' || l, pg_temp.zc_owner())
  from unnest(array['te', 'tf', 'pa2', 'pa3']) l;
select pg_temp.lr_term(2, 'test', 'draining', 'zc-term-test-2', 'zc-cred-test-2', 'test_end');
insert into _zc_r select 'tg_retire_ok', pg_temp.lr_term(2, 'test', 'retired', 'zc-term-test-2', 'zc-cred-test-2', 'test_end');
select is(jsonb_build_object(
    'closed', (select jsonb_agg(pg_temp.lr_r('close_' || u.l) -> 'resolution' order by u.n)
                 from unnest(array['te', 'tf', 'pa2', 'pa3']) with ordinality u(l, n)),
    'unresolved_left', (select count(*) from app.card_provider_attempts a
                         where a.device_id = pg_temp.zc_id('device-2')
                           and (app.card_attempt_derive(a) ->> 'unresolved')::boolean),
    'retire', pg_temp.lr_r('tg_retire_ok')),
  jsonb_build_object('closed', '["test_closed", "test_closed", "test_closed", "test_closed"]'::jsonb, 'unresolved_left', 0,
                     'retire', pg_temp.lr_tres('test', 'draining', 'retired')),
  'LR-146 a failed TEST run never blocks the TEST row: after test_closed of every unresolved TEST attempt (a held one included) the retirement passes');

-- Every operator.* event written in this file names an attested approver and the executor.
select is((select jsonb_build_object('total', count(*), 'misshaped', count(*) filter (where not (
             e.actor_kind = 'attested_owner_approver' and e.executor_principal = pg_temp.lr_exec()
             and e.actor_app_user_id in (pg_temp.zc_owner(), pg_temp.zc_id('user-lr-ro'))
             and e.mode is null and e.retention_until is null and e.incident_hold_at is null
             and e.actor_reference ~ '^[A-Za-z0-9._:/-]{1,64}$')))
             from app.card_provider_private_events e where e.action like 'operator.%' and e.created_at >= now()) ->> 'misshaped',
  '0',
  'LR-147 every operator.* event of this file: attested approver (staff 9 or the restaurant owner), executor = session_user, a reference-grammar actor_reference, mode NULL, no retention, no hold');

-- =============================================================================
-- Review-fix helpers (sections 10-14; migration-owner session, every row synthetic and rolled back).
-- =============================================================================
-- Everything an operator RPC could write: the row count and a content digest of each private store, the
-- pilot organization's tenant audit rows and the tombstones ("writes nothing" = this object is unchanged).
create function pg_temp.lr_world() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'revision_rows', (select count(*) from app.card_payments_pilot_revisions),
    'binding_rows', (select count(*) from app.payment_terminals),
    'binding_digest', (select md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id), ''))
                         from app.payment_terminals t),
    'attempt_rows', (select count(*) from app.card_provider_attempts),
    'attempt_digest', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), ''))
                         from app.card_provider_attempts a),
    'event_rows', (select count(*) from app.card_provider_private_events),
    'event_digest', (select md5(coalesce(string_agg(to_jsonb(e)::text, '|' order by e.id), ''))
                       from app.card_provider_private_events e),
    'audit_rows', pg_temp.lr_audit_count(),
    'tombstone_rows', (select count(*) from app.card_attempt_identity_tombstones));
$$;
-- The five operator RPCs with the operator reference first; the actor (default: the attested approver, staff 9)
-- and one argument are overridable. Every default call is valid, so only the overridden input decides.
create function pg_temp.lr_or_pilot(p_ref text, p_actor uuid default pg_temp.zc_id('user-9'),
                                    p_enabled boolean default true, p_reason text default 'ZC001D LR operator check')
returns jsonb language sql volatile as $$
  select app.set_card_payments_pilot(p_enabled, 'live', null, 5000, 1000000, p_reason, p_ref, p_actor);
$$;
create function pg_temp.lr_or_term(p_ref text, p_actor uuid default pg_temp.zc_id('user-9'),
                                   p_lifecycle text default 'configured', p_reason text default 'ZC001D LR operator check')
returns jsonb language sql volatile as $$
  select app.set_payment_terminal(pg_temp.zc_id('device-1'), 'live', 'lr-term-l4', 'lr-cred-l4', p_lifecycle,
                                  'live_activation', p_reason, p_ref, p_actor);
$$;
create function pg_temp.lr_or_orphan(p_ref text, p_actor uuid default pg_temp.zc_id('user-9'),
                                     p_resolution text default 'test_closed',
                                     p_reason text default 'ZC001D LR operator check')
returns jsonb language sql volatile as $$
  select app.card_attempt_resolve_orphan(pg_temp.lr_aid('or_t1'), p_resolution, 'lr-test-ref-or', p_reason, p_ref,
                                         p_actor);
$$;
create function pg_temp.lr_or_hold(p_ref text, p_actor uuid default pg_temp.zc_id('user-9'),
                                   p_kind text default 'attempt', p_reason text default 'ZC001D LR operator check')
returns jsonb language sql volatile as $$
  select app.card_attempt_set_incident_hold(p_kind, pg_temp.lr_aid('or_t1'), true, 'lr-hold-ref-or', p_reason, p_ref,
                                            p_actor);
$$;
create function pg_temp.lr_or_purge(p_ref text, p_actor uuid default pg_temp.zc_id('user-9'),
                                    p_reason text default 'ZC001D LR operator check')
returns jsonb language sql volatile as $$
  select app.purge_expired_test_card_attempts(p_reason, p_ref, p_actor);
$$;
-- The expected matrix: each named RPC answers p_n times exactly p_each.
create function pg_temp.lr_or_expect(p_each jsonb, p_n integer, p_rpcs text[] default array['set_card_payments_pilot',
    'set_payment_terminal', 'card_attempt_resolve_orphan', 'card_attempt_set_incident_hold',
    'purge_expired_test_card_attempts'])
returns jsonb language sql immutable as $$
  select jsonb_object_agg(r.rpc, (select jsonb_agg(p_each) from generate_series(1, p_n)))
    from unnest(p_rpcs) r(rpc);
$$;

-- =============================================================================
-- 10. Review fix 7 (packet 11 item 21; API 4.55.10 "a call failing the check RETURNS permission_denied and
--     writes nothing"): right after its invalid_request argument checks, each of the five operator RPCs answers
--     permission_denied for an absent operator reference (NULL, empty or Space_Separator-only) or a non-attested
--     actor, writing nothing; only a present reference failing its field rule is out_of_contract.
-- =============================================================================
-- Targets, inserted directly by the owner (no TEST binding is current here): or_t1, a TEST attempt of d2 still
-- sent past its start deadline (closable with test_closed, holdable); or_t2, a TEST attempt of d2 whose
-- retention has expired (purgeable).
insert into _zc_r select 'or_t1', jsonb_build_object('attempt_row_id', pg_temp.lr_insert_test_attempt(2, 'lr-or-t1'));
insert into _zc_r select 'or_t2', jsonb_build_object('attempt_row_id', pg_temp.lr_insert_test_attempt(2, 'lr-or-t2'));
select pg_temp.lr_age_attempt(pg_temp.lr_aid('or_t1'), true, false);
select pg_temp.lr_age_attempt(pg_temp.lr_aid('or_t2'), false, true);
select results_eq(
  $$ select u.l, a.mode, a.state, a.start_deadline_at <= clock_timestamp(), a.retention_until <= clock_timestamp(),
            a.resolution, a.incident_hold_at
       from unnest(array['or_t1', 'or_t2']) with ordinality u(l, n)
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid(u.l) order by u.n $$,
  $$ values ('or_t1'::text, 'test'::text, 'sent'::text, true, false, null::text, null::timestamptz),
            ('or_t2', 'test', 'sent', false, true, null, null) $$,
  'LR-148 setup (review fix 7): two direct TEST attempts of d2 - or_t1 sent past its start deadline (closable, holdable), or_t2 with an expired retention (purgeable); neither resolved nor held');
insert into _zc_r select 'or_world0', pg_temp.lr_world();
insert into _zc_r select 'or_absent', jsonb_build_object(
  'set_card_payments_pilot', jsonb_build_array(pg_temp.lr_or_pilot(null), pg_temp.lr_or_pilot(''),
                                               pg_temp.lr_or_pilot(U&'\3000\0020')),
  'set_payment_terminal', jsonb_build_array(pg_temp.lr_or_term(null), pg_temp.lr_or_term(''),
                                            pg_temp.lr_or_term(U&'\3000\0020')),
  'card_attempt_resolve_orphan', jsonb_build_array(pg_temp.lr_or_orphan(null), pg_temp.lr_or_orphan(''),
                                                   pg_temp.lr_or_orphan(U&'\3000\0020')),
  'card_attempt_set_incident_hold', jsonb_build_array(pg_temp.lr_or_hold(null), pg_temp.lr_or_hold(''),
                                                      pg_temp.lr_or_hold(U&'\3000\0020')),
  'purge_expired_test_card_attempts', jsonb_build_array(pg_temp.lr_or_purge(null), pg_temp.lr_or_purge(''),
                                                        pg_temp.lr_or_purge(U&'\3000\0020')));
select is(pg_temp.lr_r('or_absent'), pg_temp.lr_or_expect(pg_temp.lr_refusal('permission_denied'), 3),
  'LR-149 (review fix 7) the attested approver (staff 9) with an absent operator reference - NULL, an empty string or only Space_Separators (U+3000 U+0020) - gets exactly {ok:false, error:permission_denied} from each of set_card_payments_pilot, set_payment_terminal, card_attempt_resolve_orphan, card_attempt_set_incident_hold and purge_expired_test_card_attempts');
insert into _zc_r select 'or_field', jsonb_build_object(
  'set_card_payments_pilot', jsonb_build_array(pg_temp.lr_or_pilot('ref with space'), pg_temp.lr_or_pilot('123456789012')),
  'set_payment_terminal', jsonb_build_array(pg_temp.lr_or_term('ref with space'), pg_temp.lr_or_term('123456789012')),
  'card_attempt_resolve_orphan', jsonb_build_array(pg_temp.lr_or_orphan('ref with space'),
                                                   pg_temp.lr_or_orphan('123456789012')),
  'card_attempt_set_incident_hold', jsonb_build_array(pg_temp.lr_or_hold('ref with space'),
                                                      pg_temp.lr_or_hold('123456789012')),
  'purge_expired_test_card_attempts', jsonb_build_array(pg_temp.lr_or_purge('ref with space'),
                                                        pg_temp.lr_or_purge('123456789012')));
select is(pg_temp.lr_r('or_field'), pg_temp.lr_or_expect(pg_temp.lr_refusal('precondition_failed', 'out_of_contract'), 2),
  'LR-150 (review fix 7) a present operator reference failing its field rule - ''ref with space'' (charset) or a reference of twelve consecutive digits (a digit run; the literal is kept out of this description) - with the attested approver -> precondition_failed / out_of_contract from all five operator RPCs');
insert into _zc_r select 'or_actor', jsonb_build_object(
  'set_card_payments_pilot', jsonb_build_array(pg_temp.lr_or_pilot('zc001d-lr/or-1', pg_temp.zc_id('user-lr-rv'))),
  'set_payment_terminal', jsonb_build_array(pg_temp.lr_or_term('zc001d-lr/or-1', pg_temp.zc_id('user-lr-rv'))),
  'card_attempt_resolve_orphan', jsonb_build_array(pg_temp.lr_or_orphan('zc001d-lr/or-1', pg_temp.zc_id('user-lr-rv'))),
  'card_attempt_set_incident_hold', jsonb_build_array(pg_temp.lr_or_hold('zc001d-lr/or-1', pg_temp.zc_id('user-lr-rv'))),
  'purge_expired_test_card_attempts', jsonb_build_array(pg_temp.lr_or_purge('zc001d-lr/or-1',
                                                                            pg_temp.zc_id('user-lr-rv'))));
select is(pg_temp.lr_r('or_actor'), pg_temp.lr_or_expect(pg_temp.lr_refusal('permission_denied'), 1),
  'LR-151 (review fix 7) a non-attested actor (user-lr-rv, a revoked org_owner of the pilot organization) with a valid operator reference -> permission_denied from all five operator RPCs');
insert into _zc_r select 'or_order', jsonb_build_object(
  'set_card_payments_pilot', jsonb_build_array(
    pg_temp.lr_or_pilot(null, p_reason => 'Refund for card ' || rtrim(repeat('7351 ', 4))),
    pg_temp.lr_or_pilot('ref with space', pg_temp.zc_id('user-lr-rv'))),
  'set_payment_terminal', jsonb_build_array(
    pg_temp.lr_or_term(null, p_reason => 'Refund for card ' || rtrim(repeat('7351 ', 4))),
    pg_temp.lr_or_term('ref with space', pg_temp.zc_id('user-lr-rv'))),
  'card_attempt_resolve_orphan', jsonb_build_array(
    pg_temp.lr_or_orphan(null, p_reason => 'Refund for card ' || rtrim(repeat('7351 ', 4))),
    pg_temp.lr_or_orphan('ref with space', pg_temp.zc_id('user-lr-rv'))),
  'card_attempt_set_incident_hold', jsonb_build_array(
    pg_temp.lr_or_hold(null, p_reason => 'Refund for card ' || rtrim(repeat('7351 ', 4))),
    pg_temp.lr_or_hold('ref with space', pg_temp.zc_id('user-lr-rv'))),
  'purge_expired_test_card_attempts', jsonb_build_array(
    pg_temp.lr_or_purge(null, p_reason => 'Refund for card ' || rtrim(repeat('7351 ', 4))),
    pg_temp.lr_or_purge('ref with space', pg_temp.zc_id('user-lr-rv'))));
select is(pg_temp.lr_r('or_order'), pg_temp.lr_or_expect(pg_temp.lr_refusal('permission_denied'), 2),
  'LR-152 (review fix 7) authority before field rules: a NULL operator reference beside a reason carrying a card number, and a non-attested actor beside a reference failing its rule (''ref with space''), each answer permission_denied (never out_of_contract) from all five operator RPCs');
insert into _zc_r select 'or_invalid', jsonb_build_object(
  'set_card_payments_pilot', jsonb_build_array(pg_temp.lr_or_pilot(null, p_enabled => null)),
  'set_payment_terminal', jsonb_build_array(pg_temp.lr_or_term(null, p_lifecycle => 'paused')),
  'card_attempt_resolve_orphan', jsonb_build_array(pg_temp.lr_or_orphan(null, p_resolution => 'manual_refund')),
  'card_attempt_set_incident_hold', jsonb_build_array(pg_temp.lr_or_hold(null, p_kind => 'order')));
select is(pg_temp.lr_r('or_invalid'),
  pg_temp.lr_or_expect(pg_temp.lr_refusal('invalid_request'), 1, array['set_card_payments_pilot',
    'set_payment_terminal', 'card_attempt_resolve_orphan', 'card_attempt_set_incident_hold']),
  'LR-153 (review fix 7) an invalid_request argument fault still wins over a NULL operator reference: p_enabled NULL (set_card_payments_pilot), lifecycle ''paused'' (set_payment_terminal), resolution ''manual_refund'' (card_attempt_resolve_orphan), target kind ''order'' (card_attempt_set_incident_hold) -> invalid_request (purge_expired_test_card_attempts has no argument check)');
select is(pg_temp.lr_world(), pg_temp.lr_r('or_world0'),
  'LR-154 (review fix 7) those 44 refusals wrote nothing: revision, binding, attempt (or_t1 still unresolved and unheld, or_t2 not purged), private-event, tenant-audit and tombstone rows identical (counts and content digests)');
select pg_temp.lr_snap();
insert into _zc_r select 'or_ok_pilot', pg_temp.lr_or_pilot('zc001d-lr/or-pilot');
insert into _zc_r select 'or_ok_term', pg_temp.lr_or_term('zc001d-lr/or-term');
insert into _zc_r select 'or_ok_orphan', pg_temp.lr_or_orphan('zc001d-lr/or-orphan');
insert into _zc_r select 'or_ok_hold', pg_temp.lr_or_hold('zc001d-lr/or-hold');
insert into _zc_r select 'or_ok_purge', pg_temp.lr_or_purge('zc001d-lr/or-purge');
select is(jsonb_build_object(
    'set_card_payments_pilot', pg_temp.lr_r('or_ok_pilot') - 'revision',
    'set_payment_terminal', pg_temp.lr_r('or_ok_term'),
    'card_attempt_resolve_orphan', pg_temp.lr_r('or_ok_orphan'),
    'card_attempt_set_incident_hold', pg_temp.lr_r('or_ok_hold'),
    'purge_expired_test_card_attempts', pg_temp.lr_r('or_ok_purge') - 'cutoff',
    'or_t1', (select jsonb_build_array(a.resolution, a.resolution_reference, a.incident_hold_reference)
                from app.card_provider_attempts a where a.id = pg_temp.lr_aid('or_t1')),
    'or_t2_rows', (select count(*) from app.card_provider_attempts a where a.id = pg_temp.lr_aid('or_t2')),
    'or_t2_tombstones', (select count(*) from app.card_attempt_identity_tombstones t
                          where t.device_id = pg_temp.zc_id('device-2')
                            and t.local_operation_id = pg_temp.zc_lop('lr-or-t2'))),
  jsonb_build_object(
    'set_card_payments_pilot', jsonb_build_object('ok', true, 'enabled', true, 'mode', 'live',
                                                  'window_until', now() + interval '12 hours',
                                                  'max_test_amount_minor', 5000, 'max_live_amount_minor', 1000000),
    'set_payment_terminal', pg_temp.lr_tres('live', null, 'configured'),
    'card_attempt_resolve_orphan', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('lr-or-t1'),
                                                      'state', 'sent', 'classification', 'test_sent', 'recorded', false,
                                                      'amount_minor', 500, 'currency_code', 'ILS',
                                                      'resolution', 'test_closed',
                                                      'attempt_row_id', pg_temp.lr_aid('or_t1')),
    'card_attempt_set_incident_hold', '{"ok": true, "target_kind": "attempt", "hold": true}'::jsonb,
    'purge_expired_test_card_attempts', '{"ok": true, "attempts_purged": 1, "events_purged": 0, "attempts_deferred": 0,
                                          "events_deferred": 0, "devices_locked": 1}'::jsonb,
    'or_t1', '["test_closed", "lr-test-ref-or", "lr-hold-ref-or"]'::jsonb, 'or_t2_rows', 0, 'or_t2_tombstones', 1),
  'LR-155 control (review fix 7): the same five calls with a valid operator reference succeed - an ON LIVE revision, a configured LIVE binding of d1 (lr-term-l4), or_t1 test_closed then held, or_t2 purged with its tombstone (1 attempt, 0 events; C1-3: nothing deferred, one device locked)');
select results_eq(
  $$ select e.action, e.actor_reference, e.actor_kind, e.actor_app_user_id, e.executor_principal, e.attempt_row_id,
            e.device_id, e.mode
       from pg_temp.lr_new_events() e $$,
  $$ values ('operator.card_payments_pilot_updated'::text, 'zc001d-lr/or-pilot'::text, 'attested_owner_approver'::text,
             pg_temp.zc_owner(), pg_temp.lr_exec(), null::uuid, null::uuid, null::text),
            ('operator.payment_terminal_updated', 'zc001d-lr/or-term', 'attested_owner_approver', pg_temp.zc_owner(),
             pg_temp.lr_exec(), null, pg_temp.zc_id('device-1'), null),
            ('operator.card_attempt_test_closed', 'zc001d-lr/or-orphan', 'attested_owner_approver', pg_temp.zc_owner(),
             pg_temp.lr_exec(), pg_temp.lr_aid('or_t1'), pg_temp.zc_id('device-2'), null),
            ('operator.card_test_attempt_hold_updated', 'zc001d-lr/or-hold', 'attested_owner_approver', pg_temp.zc_owner(),
             pg_temp.lr_exec(), pg_temp.lr_aid('or_t1'), pg_temp.zc_id('device-2'), null),
            ('operator.card_test_attempts_purged', 'zc001d-lr/or-purge', 'attested_owner_approver', pg_temp.zc_owner(),
             pg_temp.lr_exec(), null, null, null) $$,
  'LR-156 control: exactly five private events, one per successful call, each naming its own operator reference, the attested approver (staff 9) and executor_principal = session_user, mode NULL');

-- =============================================================================
-- 11. Contract-literal (review item 9; packet 11 item 24) as amended by correction C1-2 (D-059 point 2):
--     set_payment_terminal validates the exact pilot POS device for EVERY call but requires an ACTIVE device record
--     (is_active, deleted_at NULL) only for configured (creation / rotation) and enabled (activation / re-enable) -
--     stopping a till never depends on it being active. With an enabled binding on d1, an inactive (is_active =
--     false) or a deleted (deleted_at set) d1 still drains (one event), while configured and enabled answer
--     invalid_request and write nothing. Each phase restores the device record and re-enables the binding, so
--     section 12 starts from d1's enabled LIVE binding lr-term-l4 exactly as before.
-- =============================================================================
insert into _zc_r select 'ia_enable', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l4', 'lr-cred-l4', 'live_activation');
select is(jsonb_build_object('enable', pg_temp.lr_r('ia_enable'),
                             'current', (select jsonb_build_array(t.mode, t.terminal_ref, t.credential_ref, t.lifecycle)
                                           from pg_temp.lr_current(1) t)),
  jsonb_build_object('enable', pg_temp.lr_tres('live', 'configured', 'enabled'),
                     'current', '["live", "lr-term-l4", "lr-cred-l4", "enabled"]'::jsonb),
  'LR-157 setup (item 9): d1 holds an enabled LIVE binding (lr-term-l4 / lr-cred-l4)');
-- The three steps an inactive / deleted device refuses, on d1 with its binding's references: configured with the
-- binding's own references (from enabled or draining an illegal step), enabled with them (from enabled a no-op
-- repeat, from draining the re-enable) and configured with new references of the same mode (from enabled
-- binding_exists, from draining the rotation). On an active device the draining-phase calls would re-enable / rotate.
create function pg_temp.lr_ia_refused() returns jsonb language sql volatile as $$
  select jsonb_build_object(
    'configured_own', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l4', 'lr-cred-l4', 'live_activation'),
    'enabled_own', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l4', 'lr-cred-l4', 'live_activation'),
    'configured_new_refs', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l5', 'lr-cred-l5', 'rotation'));
$$;
create function pg_temp.lr_ia_refusals() returns jsonb language sql immutable as $$
  select jsonb_build_object('configured_own', pg_temp.lr_refusal('invalid_request'),
                            'enabled_own', pg_temp.lr_refusal('invalid_request'),
                            'configured_new_refs', pg_temp.lr_refusal('invalid_request'));
$$;
-- The events written since the last lr_snap(), with every column the C1-2 assertions name.
create function pg_temp.lr_new_event_rows() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('action', e.action, 'actor_kind', e.actor_kind,
                                               'actor_reference', e.actor_reference,
                                               'actor_app_user_id', e.actor_app_user_id,
                                               'executor_principal', e.executor_principal, 'device_id', e.device_id,
                                               'attempt_row_id', e.attempt_row_id, 'mode', e.mode,
                                               'retention_until', e.retention_until, 'reason', e.reason,
                                               'detail', e.detail) order by e.created_at, e.id), '[]'::jsonb)
    from pg_temp.lr_new_events() e;
$$;
-- The expected event row of one set_payment_terminal step made through lr_term (its default reason and reference):
-- the attested approver (staff 9), executor_principal = session_user, the device, mode NULL, no retention.
create function pg_temp.lr_tev_row(p_d integer, p_mode text, p_prior text, p_new text, p_admitted boolean,
                                   p_reason_code text, p_ref text default 'zc001d-lr/bind-1')
returns jsonb language sql stable as $$
  select jsonb_build_object('action', 'operator.payment_terminal_updated', 'actor_kind', 'attested_owner_approver',
    'actor_reference', p_ref, 'actor_app_user_id', pg_temp.zc_owner(), 'executor_principal', pg_temp.lr_exec(),
    'device_id', pg_temp.zc_id('device-' || p_d), 'attempt_row_id', null, 'mode', null, 'retention_until', null,
    'reason', 'ZC001D LR binding',
    'detail', pg_temp.lr_tev(p_mode, p_prior, p_new, p_admitted, p_reason_code) -> 'detail');
$$;
-- Phase 1: d1 inactive (is_active = false).
insert into _zc_r select 'ia_world0', pg_temp.lr_world();
update public.devices set is_active = false where id = pg_temp.zc_id('device-1');
insert into _zc_r select 'ia_inactive_enabled', pg_temp.lr_ia_refused();
insert into _zc_r select 'ia_world1', pg_temp.lr_world();
select pg_temp.lr_snap();
insert into _zc_r select 'ia_inactive_drain', pg_temp.lr_term(1, 'live', 'draining', 'lr-term-l4', 'lr-cred-l4', 'incident');
insert into _zc_r select 'ia_inactive_drain_events', pg_temp.lr_new_event_rows();
insert into _zc_r select 'ia_world2', pg_temp.lr_world();
insert into _zc_r select 'ia_inactive_draining', pg_temp.lr_ia_refused();
insert into _zc_r select 'ia_world3', pg_temp.lr_world();
update public.devices set is_active = true where id = pg_temp.zc_id('device-1');
select pg_temp.lr_snap();
insert into _zc_r select 'ia_active_reenable', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l4', 'lr-cred-l4',
                                                               'live_activation');
insert into _zc_r select 'ia_active_reenable_events', pg_temp.lr_new_event_rows();
-- Phase 2: d1 deleted (deleted_at set, is_active true).
insert into _zc_r select 'ia_world4', pg_temp.lr_world();
update public.devices set deleted_at = now() where id = pg_temp.zc_id('device-1');
insert into _zc_r select 'ia_deleted_enabled', pg_temp.lr_ia_refused();
insert into _zc_r select 'ia_world5', pg_temp.lr_world();
select pg_temp.lr_snap();
insert into _zc_r select 'ia_deleted_drain', pg_temp.lr_term(1, 'live', 'draining', 'lr-term-l4', 'lr-cred-l4', 'incident');
insert into _zc_r select 'ia_deleted_drain_events', pg_temp.lr_new_event_rows();
insert into _zc_r select 'ia_world6', pg_temp.lr_world();
insert into _zc_r select 'ia_deleted_draining', pg_temp.lr_ia_refused();
insert into _zc_r select 'ia_world7', pg_temp.lr_world();
update public.devices set deleted_at = null where id = pg_temp.zc_id('device-1');
select pg_temp.lr_snap();
insert into _zc_r select 'ia_undeleted_reenable', pg_temp.lr_term(1, 'live', 'enabled', 'lr-term-l4', 'lr-cred-l4',
                                                                  'live_activation');
insert into _zc_r select 'ia_undeleted_reenable_events', pg_temp.lr_new_event_rows();
select is(jsonb_build_object('refused', pg_temp.lr_r('ia_inactive_enabled'),
                             'wrote_nothing', pg_temp.lr_r('ia_world1') = pg_temp.lr_r('ia_world0')),
  jsonb_build_object('refused', pg_temp.lr_ia_refusals(), 'wrote_nothing', true),
  'LR-158 (item 9; C1-2) d1 inactive (is_active = false) with its LIVE binding enabled: configured with the binding''s own references, enabled with them and configured with new references of the same mode each answer invalid_request (configured / enabled need an active device record), and write nothing - binding, attempt, private-event, revision, tenant-audit and tombstone rows identical');
select is(jsonb_build_object('result', pg_temp.lr_r('ia_inactive_drain'),
                             'events', pg_temp.lr_r('ia_inactive_drain_events')),
  jsonb_build_object('result', pg_temp.lr_tres('live', 'enabled', 'draining'),
                     'events', jsonb_build_array(pg_temp.lr_tev_row(1, 'live', 'enabled', 'draining', false, 'incident'))),
  'LR-159 (item 9; C1-2) the inactive d1''s enabled LIVE binding drains (stopping a till never depends on it being active): ok {changed, live, enabled -> draining} and exactly one operator.payment_terminal_updated {live, enabled, draining, starts_admitted false, incident} naming the attested approver (staff 9), the canonical operator reference and reason, executor_principal = session_user, the device, mode NULL, no retention');
select is(jsonb_build_object('refused', pg_temp.lr_r('ia_inactive_draining'),
                             'wrote_nothing', pg_temp.lr_r('ia_world3') = pg_temp.lr_r('ia_world2'),
                             'reactivated_reenable', pg_temp.lr_r('ia_active_reenable'),
                             'reactivated_events', pg_temp.lr_r('ia_active_reenable_events')),
  jsonb_build_object('refused', pg_temp.lr_ia_refusals(), 'wrote_nothing', true,
                     'reactivated_reenable', pg_temp.lr_tres('live', 'draining', 'enabled'),
                     'reactivated_events', jsonb_build_array(
                       pg_temp.lr_tev_row(1, 'live', 'draining', 'enabled', true, 'live_activation'))),
  'LR-160 (item 9; C1-2) d1 still inactive with its binding draining: the re-enable, configured with the own references and the rotation (configured, new references, same mode) each answer invalid_request and write nothing; once the device record is active again the same re-enable passes with exactly one event (draining -> enabled), so those refusals came from the device record alone');
select is(jsonb_build_object('refused', pg_temp.lr_r('ia_deleted_enabled'),
                             'wrote_nothing', pg_temp.lr_r('ia_world5') = pg_temp.lr_r('ia_world4'),
                             'drain', pg_temp.lr_r('ia_deleted_drain'),
                             'drain_events', pg_temp.lr_r('ia_deleted_drain_events')),
  jsonb_build_object('refused', pg_temp.lr_ia_refusals(), 'wrote_nothing', true,
                     'drain', pg_temp.lr_tres('live', 'enabled', 'draining'),
                     'drain_events', jsonb_build_array(
                       pg_temp.lr_tev_row(1, 'live', 'enabled', 'draining', false, 'incident'))),
  'LR-161 (item 9; C1-2) d1 deleted (deleted_at set, is_active true) with its LIVE binding enabled: the same three configured / enabled steps answer invalid_request and write nothing, while draining passes with exactly one event (attested approver, executor_principal = session_user)');
select is(jsonb_build_object('refused', pg_temp.lr_r('ia_deleted_draining'),
                             'wrote_nothing', pg_temp.lr_r('ia_world7') = pg_temp.lr_r('ia_world6'),
                             'undeleted_reenable', pg_temp.lr_r('ia_undeleted_reenable'),
                             'undeleted_events', pg_temp.lr_r('ia_undeleted_reenable_events'),
                             'current', (select jsonb_build_array(t.mode, t.terminal_ref, t.credential_ref, t.lifecycle)
                                           from pg_temp.lr_current(1) t)),
  jsonb_build_object('refused', pg_temp.lr_ia_refusals(), 'wrote_nothing', true,
                     'undeleted_reenable', pg_temp.lr_tres('live', 'draining', 'enabled'),
                     'undeleted_events', jsonb_build_array(
                       pg_temp.lr_tev_row(1, 'live', 'draining', 'enabled', true, 'live_activation')),
                     'current', '["live", "lr-term-l4", "lr-cred-l4", "enabled"]'::jsonb),
  'LR-162 (item 9; C1-2) control: d1 still deleted with its binding draining, the re-enable, configured and the rotation answer invalid_request and write nothing; once undeleted the re-enable passes with exactly one event, and d1 holds its enabled LIVE binding lr-term-l4 again (section 12 claims on it)');

-- =============================================================================
-- 12. The LIVE free_order refusal matrix (TESTING_STRATEGY:173; SECURITY T-023; API 4.55.6), manager PIN
--     (staff 2) on d1 through the service-only wrapper. Each call is bracketed by lr_mark() / lr_delta(): the
--     tenant audit rows it wrote, its private events and the number of attempt rows it changed.
--     d1: LIVE binding lr-term-l4 enabled; the current revision is ON LIVE with a cap (section 10).
-- =============================================================================
create temp table _lr_aseen (id uuid primary key);
create temp table _lr_rows (id uuid primary key, r jsonb);
-- Snapshot (definer: callable under service_role): the private events, the tenant audit rows, every attempt row.
create function pg_temp.lr_mark() returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  insert into pg_temp._lr_seen select e.id from app.card_provider_private_events e on conflict do nothing;
  insert into pg_temp._lr_aseen select x.id from public.audit_events x on conflict do nothing;
  delete from pg_temp._lr_rows;
  insert into pg_temp._lr_rows select a.id, to_jsonb(a) from app.card_provider_attempts a;
end $$;
-- What was written since lr_mark(): the new tenant audit rows (every column but id / timestamps), the number of
-- new private events and the number of attempt rows inserted, deleted or changed.
create function pg_temp.lr_delta() returns jsonb language sql volatile security definer set search_path = '' as $$
  select jsonb_build_object(
    'audit', coalesce((select jsonb_agg(jsonb_build_object('organization_id', x.organization_id,
                          'restaurant_id', x.restaurant_id, 'branch_id', x.branch_id,
                          'actor_app_user_id', x.actor_app_user_id,
                          'actor_employee_profile_id', x.actor_employee_profile_id, 'device_id', x.device_id,
                          'action', x.action, 'reason', x.reason, 'old_values', x.old_values,
                          'new_values', x.new_values) order by x.created_at, x.id)
                         from public.audit_events x
                        where not exists (select 1 from pg_temp._lr_aseen s where s.id = x.id)), '[]'::jsonb),
    'events', (select count(*) from app.card_provider_private_events e
                where not exists (select 1 from pg_temp._lr_seen s where s.id = e.id)),
    'attempts_changed', (select count(*) from app.card_provider_attempts a
                           full join pg_temp._lr_rows s on s.id = a.id
                          where a.id is null or s.id is null or to_jsonb(a) is distinct from s.r));
$$;
-- One free_order call by the manager (staff 2 PIN on d1, its device token) with full provider evidence by
-- default: {result: the answer without server_ts, delta}. Call under SET LOCAL ROLE service_role.
create function pg_temp.lr_fo(p_label text, p_source text default 'provider_report',
                              p_reference text default 'lr-conf-ok',
                              p_reason text default 'ZC001D LR provider report shows no charge')
returns jsonb language plpgsql volatile as $$
declare
  v jsonb;
begin
  perform pg_temp.lr_mark();
  v := public.card_attempt_free_order(pg_temp.zc_id('pin-2'), pg_temp.zc_id('device-1'), 'zc-token-1',
                                      pg_temp.zc_lop(p_label), p_reason, p_source, p_reference, pg_temp.zc_caller());
  return jsonb_build_object('result', v - 'server_ts', 'delta', pg_temp.lr_delta());
end $$;
-- Expected: a refusal decided after the resolution (exactly one card_attempt.denied {denied_reason} by the manager
-- on d1, no private event, no attempt row changed) / an answer that writes nothing at all.
create function pg_temp.lr_fo_refused(p_detail text, p_label text, p_state text) returns jsonb language sql stable as $$
  select jsonb_build_object(
    'result', jsonb_build_object('ok', false, 'error', 'precondition_failed', 'detail', p_detail,
                                 'attempt_id', pg_temp.zc_lop(p_label), 'attempt_state', p_state),
    'delta', jsonb_build_object(
      'audit', jsonb_build_array(jsonb_build_object('organization_id', pg_temp.zc_org(),
                 'restaurant_id', pg_temp.zc_rest(), 'branch_id', pg_temp.zc_branch(), 'actor_app_user_id', null,
                 'actor_employee_profile_id', pg_temp.zc_id('employee-2'), 'device_id', pg_temp.zc_id('device-1'),
                 'action', 'card_attempt.denied', 'reason', null, 'old_values', null,
                 'new_values', jsonb_build_object('denied_reason', p_detail))),
      'events', 0, 'attempts_changed', 0));
$$;
create function pg_temp.lr_fo_silent(p_result jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('result', p_result, 'delta', '{"audit": [], "events": 0, "attempts_changed": 0}'::jsonb);
$$;
-- Eight LIVE attempts of d1 (staff 1 claims, one order each).
select pg_temp.zc_order('lr-fo-' || l, 1234)
  from unnest(array['appr', 'sent', 'decl', 'unk', 'rel', 'look', 'anom', 'free']) l;
set local role service_role;
insert into _zc_r select 'claim_fo_' || l, pg_temp.lr_claim(1, pg_temp.zc_lop('lr-fo-' || l), 'live', 1234,
                                                            pg_temp.zc_id('order-lr-fo-' || l), 1, 'lr-term-l4', 'lr-cred-l4')
  from unnest(array['appr', 'sent', 'decl', 'unk', 'rel', 'look', 'anom', 'free']) l;
insert into _zc_r select 'fo_c_' || l, pg_temp.zc_finish(pg_temp.lr_r('claim_fo_' || l), 'commit', 'unknown')
  from unnest(array['appr', 'decl', 'unk', 'look', 'free']) l;
insert into _zc_r select 'fo_c_anom', pg_temp.zc_finish(pg_temp.lr_r('claim_fo_anom'), 'commit', 'anomaly',
                                                        '{"anomaly_code": "refunded"}'::jsonb);
insert into _zc_r select 'fo_c_rel', pg_temp.zc_finish(pg_temp.lr_r('claim_fo_rel'), 'release', 'released');
insert into _zc_r select 'fo_l_appr', pg_temp.zc_finish(pg_temp.lr_r('claim_fo_appr'), 'lookup', 'approved',
  pg_temp.zc_approved_fields() || '{"provider_amount": "12.34", "provider_currency": "ILS"}'::jsonb, 'operator');
insert into _zc_r select 'fo_l_decl', pg_temp.zc_finish(pg_temp.lr_r('claim_fo_decl'), 'lookup', 'declined',
                                                        '{"approval_type": "declined"}'::jsonb, 'operator');
insert into _zc_r select 'fo_l_' || l, pg_temp.zc_finish(pg_temp.lr_r('claim_fo_' || l), 'lookup', 'not_found',
                                                         '{}'::jsonb, 'operator')
  from unnest(array['sent', 'look', 'anom', 'free']) l;
reset role;
select results_eq(
  $$ select u.l, a.mode, a.state, a.charge_may_exist, a.provider_anomaly_code, a.last_lookup_at is not null,
            a.order_freed_at, a.resolution, app.card_attempt_derive(a) ->> 'classification'
       from unnest(array['appr', 'sent', 'decl', 'unk', 'rel', 'look', 'anom', 'free']) with ordinality u(l, n)
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid('claim_fo_' || u.l) order by u.n $$,
  $$ values ('appr'::text, 'live'::text, 'approved'::text, false, null::text, true, null::timestamptz, null::text,
             'approved_unrecorded'::text),
            ('sent', 'live', 'sent', false, null, true, null, null, 'in_progress'),
            ('decl', 'live', 'declined', false, null, true, null, null, 'declined'),
            ('unk', 'live', 'unknown', false, null, false, null, null, 'in_progress'),
            ('rel', 'live', 'released', false, null, false, null, null, 'in_progress'),
            ('look', 'live', 'unknown', false, null, true, null, null, 'in_progress'),
            ('anom', 'live', 'unknown', true, 'refunded', true, null, null, 'provider_anomaly'),
            ('free', 'live', 'unknown', false, null, true, null, null, 'in_progress') $$,
  'LR-163 setup: eight LIVE attempts of d1, one order each - approved, sent and declined each after a lookup; unknown and released with no lookup; unknown after a lookup (look, free); a looked-up provider_anomaly (refunded, charge_may_exist)');
set local role service_role;
insert into _zc_r select 'fo_appr', pg_temp.lr_fo('lr-fo-appr');
insert into _zc_r select 'fo_sent', pg_temp.lr_fo('lr-fo-sent');
insert into _zc_r select 'fo_decl', pg_temp.lr_fo('lr-fo-decl');
insert into _zc_r select 'fo_unk', pg_temp.lr_fo('lr-fo-unk');
insert into _zc_r select 'fo_rel', pg_temp.lr_fo('lr-fo-rel');
insert into _zc_r select 'fo_src_null', pg_temp.lr_fo('lr-fo-look', p_source => null);
insert into _zc_r select 'fo_src_self', pg_temp.lr_fo('lr-fo-look', p_source => 'manager_says_so');
insert into _zc_r select 'fo_ref_null', pg_temp.lr_fo('lr-fo-look', p_reference => null);
insert into _zc_r select 'fo_ref_empty', pg_temp.lr_fo('lr-fo-look', p_reference => '');
insert into _zc_r select 'fo_ref_blank', pg_temp.lr_fo('lr-fo-look', p_reference => U&'\3000\00A0');
insert into _zc_r select 'fo_reason_null', pg_temp.lr_fo('lr-fo-look', p_reason => null);
insert into _zc_r select 'fo_reason_empty', pg_temp.lr_fo('lr-fo-look', p_reason => '');
insert into _zc_r select 'fo_anom', pg_temp.lr_fo('lr-fo-anom');
insert into _zc_r select 'fo_none', pg_temp.lr_fo('lr-fo-none');
insert into _zc_r select 'fo_oc_reason', pg_temp.lr_fo('lr-fo-look', p_reason => 'Card ' || rtrim(repeat('7351 ', 4)) || ' was not charged');
insert into _zc_r select 'fo_oc_reason_none', pg_temp.lr_fo('lr-fo-none',
                                                            p_reason => 'Card ' || rtrim(repeat('7351 ', 4)) || ' was not charged');
insert into _zc_r select 'fo_oc_ref', pg_temp.lr_fo('lr-fo-look', p_reference => repeat('7351', 4));
reset role;
select is(jsonb_build_object('approved', pg_temp.lr_r('fo_appr'), 'sent', pg_temp.lr_r('fo_sent'),
                             'declined', pg_temp.lr_r('fo_decl')),
  jsonb_build_object('approved', pg_temp.lr_fo_refused('attempt_not_freeable', 'lr-fo-appr', 'approved'),
                     'sent', pg_temp.lr_fo_refused('attempt_not_freeable', 'lr-fo-sent', 'sent'),
                     'declined', pg_temp.lr_fo_refused('attempt_not_freeable', 'lr-fo-decl', 'declined')),
  'LR-164 free_order on an approved, a sent and a declined LIVE attempt (each looked up, full provider evidence) -> precondition_failed / attempt_not_freeable with attempt_id and attempt_state; each writes exactly one card_attempt.denied {denied_reason: attempt_not_freeable} (actor employee 2, device d1, reason NULL), no private event, and changes no attempt row');
select is(jsonb_build_object('unknown', pg_temp.lr_r('fo_unk'), 'released', pg_temp.lr_r('fo_rel')),
  jsonb_build_object('unknown', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-unk', 'unknown'),
                     'released', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-rel', 'released')),
  'LR-165 free_order on an unknown and on a released LIVE attempt with no prior provider lookup (full provider evidence) -> confirmation_required; exactly one card_attempt.denied {confirmation_required} each, no private event, no attempt row changed');
select is(jsonb_build_object('source_null', pg_temp.lr_r('fo_src_null'), 'source_manager_says_so', pg_temp.lr_r('fo_src_self')),
  jsonb_build_object('source_null', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-look', 'unknown'),
                     'source_manager_says_so', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-look', 'unknown')),
  'LR-166 after a provider lookup, a NULL confirmation_source or the self-attestation ''manager_says_so'' -> confirmation_required; exactly one card_attempt.denied {confirmation_required} each, the attempt row unchanged');
select is(jsonb_build_object('reference_null', pg_temp.lr_r('fo_ref_null'), 'reference_empty', pg_temp.lr_r('fo_ref_empty'),
                             'reference_space_separators', pg_temp.lr_r('fo_ref_blank')),
  jsonb_build_object('reference_null', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-look', 'unknown'),
                     'reference_empty', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-look', 'unknown'),
                     'reference_space_separators', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-look', 'unknown')),
  'LR-167 after a provider lookup, a NULL, an empty or a Space_Separator-only (U+3000 U+00A0) confirmation_reference -> confirmation_required; exactly one card_attempt.denied {confirmation_required} each, the attempt row unchanged');
select is(jsonb_build_object('reason_null', pg_temp.lr_r('fo_reason_null'), 'reason_empty', pg_temp.lr_r('fo_reason_empty')),
  jsonb_build_object('reason_null', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-look', 'unknown'),
                     'reason_empty', pg_temp.lr_fo_refused('confirmation_required', 'lr-fo-look', 'unknown')),
  'LR-168 after a provider lookup, a NULL or an empty reason -> confirmation_required; exactly one card_attempt.denied {confirmation_required} each, the attempt row unchanged');
select is(pg_temp.lr_r('fo_anom'), pg_temp.lr_fo_refused('charge_may_exist', 'lr-fo-anom', 'unknown'),
  'LR-169 a looked-up provider_anomaly (charge_may_exist true, full provider evidence) -> precondition_failed / charge_may_exist; exactly one card_attempt.denied {charge_may_exist}, the attempt row unchanged');
select is(pg_temp.lr_r('fo_none'), pg_temp.lr_fo_silent(pg_temp.lr_refusal('attempt_not_found')),
  'LR-170 an unknown attempt_id -> attempt_not_found, decided by the resolution itself: no denial evidence, no private event, no attempt row changed');
select is(jsonb_build_object('reason_on_freeable', pg_temp.lr_r('fo_oc_reason'),
                             'reason_on_unknown_id', pg_temp.lr_r('fo_oc_reason_none'),
                             'reference_on_freeable', pg_temp.lr_r('fo_oc_ref')),
  jsonb_build_object('reason_on_freeable', pg_temp.lr_fo_silent(pg_temp.lr_refusal('precondition_failed', 'out_of_contract')),
                     'reason_on_unknown_id', pg_temp.lr_fo_silent(pg_temp.lr_refusal('precondition_failed', 'out_of_contract')),
                     'reference_on_freeable', pg_temp.lr_fo_silent(pg_temp.lr_refusal('precondition_failed', 'out_of_contract'))),
  'LR-171 a reason carrying a card number (on a looked-up attempt that full evidence would free, and on an unknown attempt_id) and a card-number confirmation_reference -> precondition_failed / out_of_contract before any attempt lookup (never attempt_not_found): nothing written - no denial evidence, no private event, no attempt row changed');
set local role service_role;
insert into _zc_r select 'fo_free', pg_temp.lr_fo('lr-fo-free');
insert into _zc_r select 'fo_free_again', pg_temp.lr_fo('lr-fo-free');
insert into _zc_r select 'fo_free_again_bare', pg_temp.lr_fo('lr-fo-free', p_source => null, p_reason => '');
reset role;
select is(pg_temp.lr_r('fo_free'),
  jsonb_build_object(
    'result', jsonb_build_object('ok', true, 'attempt_id', pg_temp.zc_lop('lr-fo-free'), 'state', 'unknown',
                                 'classification', 'freed', 'recorded', false, 'amount_minor', 1234, 'currency_code', 'ILS'),
    'delta', jsonb_build_object(
      'audit', jsonb_build_array(jsonb_build_object('organization_id', pg_temp.zc_org(),
                 'restaurant_id', pg_temp.zc_rest(), 'branch_id', pg_temp.zc_branch(), 'actor_app_user_id', null,
                 'actor_employee_profile_id', pg_temp.zc_id('employee-2'), 'device_id', pg_temp.zc_id('device-1'),
                 'action', 'card_attempt.order_freed', 'reason', null, 'old_values', null,
                 'new_values', '{"attempt_state": "unknown", "confirmation_source": "provider_report"}'::jsonb)),
      'events', 0, 'attempts_changed', 1)),
  'LR-172 setup: a looked-up unknown attempt with full provider evidence is freed - the envelope (classification freed), exactly one card_attempt.order_freed {attempt_state, confirmation_source}, one attempt row changed');
select results_eq(
  $$ select a.state, a.order_freed_at is not null, a.order_freed_reason, a.confirmation_source, a.confirmation_reference,
            a.order_freed_note, a.resolution
       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_fo_free') $$,
  $$ values ('unknown'::text, true, 'manager_confirmed'::text, 'provider_report'::text, 'lr-conf-ok'::text,
             'ZC001D LR provider report shows no charge'::text, null::text) $$,
  'LR-173 ... the freed row: state unchanged (unknown), order_freed_at set, order_freed_reason manager_confirmed, the source, the canonical reference and the note, no resolution');
select is(jsonb_build_object('full_evidence', pg_temp.lr_r('fo_free_again'),
                             'null_source_empty_reason', pg_temp.lr_r('fo_free_again_bare')),
  jsonb_build_object('full_evidence', pg_temp.lr_fo_silent(pg_temp.lr_r('fo_free') -> 'result'),
                     'null_source_empty_reason', pg_temp.lr_fo_silent(pg_temp.lr_r('fo_free') -> 'result')),
  'LR-174 an attempt already freed answers its current envelope with no write and no audit - with full evidence and with a NULL source and an empty reason alike (no denial evidence, no private event, no attempt row changed)');

-- =============================================================================
-- 13. Review fix 10: the ledger trigger card_attempts_guard under direct owner UPDATEs of
--     app.card_provider_attempts (row counts through GET DIAGNOSTICS; a skipped row counts 0).
-- =============================================================================
create function pg_temp.lr_rows(p_sql text) returns bigint language plpgsql volatile as $$
declare
  n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;
create function pg_temp.lr_row(p_label text) returns jsonb language sql stable as $$
  select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.lr_aid(p_label);
$$;
insert into _zc_r select 'tr_anom_0', pg_temp.lr_row('claim_fo_anom');
insert into _zc_r select 'tr_a_same', to_jsonb(pg_temp.lr_rows(format(
  'update app.card_provider_attempts set charge_may_exist = false where id = %L', pg_temp.lr_aid('claim_fo_anom'))));
select is(jsonb_build_object('rows_changed', pg_temp.lr_r('tr_a_same'),
                             'row_identical', pg_temp.lr_row('claim_fo_anom') = pg_temp.lr_r('tr_anom_0')),
  '{"rows_changed": 0, "row_identical": true}'::jsonb,
  'LR-175 (review fix 10a) clearing charge_may_exist with the state unchanged (an unknown provider_anomaly) is a silent no-op: 0 rows changed, the row identical');
insert into _zc_r select 'tr_a_exact', to_jsonb(pg_temp.lr_rows(format(
  'update app.card_provider_attempts set state = ''approved'', charge_may_exist = false where id = %L',
  pg_temp.lr_aid('claim_fo_anom'))));
select is(jsonb_build_object('rows_changed', pg_temp.lr_r('tr_a_exact'),
                             'row', (select jsonb_build_array(a.state, a.charge_may_exist, a.provider_anomaly_code)
                                       from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_fo_anom'))),
  '{"rows_changed": 1, "row": ["approved", false, "refunded"]}'::jsonb,
  'LR-176 (review fix 10a) the exact transition unknown -> approved clears it: 1 row changed - state approved, charge_may_exist false, the anomaly code kept as history');
insert into _zc_r select 'tr_b_0', jsonb_build_object('approved', pg_temp.lr_row('claim_fo_appr'),
  'declined', pg_temp.lr_row('claim_fo_decl'), 'approved_history', pg_temp.lr_row('claim_fo_anom'));
insert into _zc_r select 'tr_b', jsonb_build_object(
  'approved_set', pg_temp.lr_rows(format(
    'update app.card_provider_attempts set provider_anomaly_code = ''refunded'' where id = %L',
    pg_temp.lr_aid('claim_fo_appr'))),
  'declined_set', pg_temp.lr_rows(format(
    'update app.card_provider_attempts set provider_anomaly_code = ''voided'' where id = %L',
    pg_temp.lr_aid('claim_fo_decl'))),
  'approved_history_changed', pg_temp.lr_rows(format(
    'update app.card_provider_attempts set provider_anomaly_code = ''voided'' where id = %L',
    pg_temp.lr_aid('claim_fo_anom'))));
select is(jsonb_build_object('rows_changed', pg_temp.lr_r('tr_b'),
                             'rows', (select jsonb_agg(jsonb_build_array(u.l, a.state, a.provider_anomaly_code) order by u.n)
                                        from unnest(array['appr', 'decl', 'anom']) with ordinality u(l, n)
                                        join app.card_provider_attempts a on a.id = pg_temp.lr_aid('claim_fo_' || u.l)),
                             'rows_identical', jsonb_build_object('approved', pg_temp.lr_row('claim_fo_appr'),
                                                                  'declined', pg_temp.lr_row('claim_fo_decl'),
                                                                  'approved_history', pg_temp.lr_row('claim_fo_anom'))
                                               = pg_temp.lr_r('tr_b_0')),
  '{"rows_changed": {"approved_set": 0, "declined_set": 0, "approved_history_changed": 0},
    "rows": [["appr", "approved", null], ["decl", "declined", null], ["anom", "approved", "refunded"]],
    "rows_identical": true}'::jsonb,
  'LR-177 (review fix 10b) on an approved or declined row any change of provider_anomaly_code is a silent no-op: setting it on an approved and on a declined row (code NULL) and changing the history code of an approved row (refunded -> voided) -> 0 rows changed; the three rows keep (approved, NULL), (declined, NULL), (approved, refunded) and are identical');
insert into _zc_r select 'tr_free_0', pg_temp.lr_row('claim_fo_free');
select throws_ok(format('update app.card_provider_attempts set order_freed_reason = ''orphan_resolved'' where id = %L',
                        pg_temp.lr_aid('claim_fo_free')),
  '23514', 'card_provider_attempts: order_freed_at is never re-stamped',
  'LR-178 (review fix 10c) on a freed row (manager_confirmed, no resolution) changing order_freed_reason (-> orphan_resolved) raises 23514 "order_freed_at is never re-stamped"');
select throws_ok(format('update app.card_provider_attempts set order_freed_at = order_freed_at + interval ''1 second'' where id = %L',
                        pg_temp.lr_aid('claim_fo_free')),
  '23514', 'card_provider_attempts: order_freed_at is never re-stamped',
  'LR-179 (review fix 10c) on that freed row changing order_freed_at (one second later) raises the same 23514');
select throws_ok(format('update app.card_provider_attempts set order_freed_at = null, order_freed_reason = null where id = %L',
                        pg_temp.lr_aid('claim_fo_free')),
  '23514', 'card_provider_attempts: order_freed_at is never re-stamped',
  'LR-180 (review fix 10c) on that freed row clearing the free stamp (order_freed_at and order_freed_reason NULL) raises the same 23514');
select is(pg_temp.lr_row('claim_fo_free'), coalesce(pg_temp.lr_r('tr_free_0'), '"missing snapshot"'::jsonb),
  'LR-181 (review fix 10c) ... after those refused updates the freed row is unchanged');

-- =============================================================================
-- 14. The executor principal (API 4.55.10: "session_user, captured inside the definer body, never the definer's
--     current_user"; D-057 point 6): the definitions of the five operator RPCs.
-- =============================================================================
select results_eq(
  $$ select p.proname::text collate "default",
            position('session_user' in lower(pg_get_functiondef(p.oid))) > 0,
            position('current_user' in lower(pg_get_functiondef(p.oid))) > 0,
            position('current_role' in lower(pg_get_functiondef(p.oid))) > 0
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app'
        and p.proname in ('set_card_payments_pilot', 'set_payment_terminal', 'card_attempt_resolve_orphan',
                          'card_attempt_set_incident_hold', 'purge_expired_test_card_attempts')
      order by p.proname $$,
  $$ values ('card_attempt_resolve_orphan'::text, true, false, false),
            ('card_attempt_set_incident_hold', true, false, false),
            ('purge_expired_test_card_attempts', true, false, false),
            ('set_card_payments_pilot', true, false, false),
            ('set_payment_terminal', true, false, false) $$,
  'LR-182 executor principal: pg_get_functiondef of each of the five operator RPCs (one definition each: app.card_attempt_resolve_orphan, app.card_attempt_set_incident_hold, app.purge_expired_test_card_attempts, app.set_card_payments_pilot, app.set_payment_terminal) contains session_user and contains neither current_user nor current_role');

-- =============================================================================
-- 15. Fix batch 6, change 24 (packet lock order: set_card_payments_pilot serializes on
--     'card-pilot-revision/v1:'||org||':'||branch "right before it draws the revision (after its argument, authority
--     and field-rule checks, so a refused call holds no lock)"; API 4.55.9). The probes were captured before
--     section 1 ("Capture for section 15"), while this transaction held no advisory lock: a transaction-level advisory
--     lock is released only by ROLLBACK, so after the accepted revisions of sections 1-14 the key is held here and
--     could not show a refused call's lock.
-- =============================================================================
select is(pg_temp.lr_r('lk_start') -> 'locks', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb,
  'LR-183 (change 24) setup: before the first set_card_payments_pilot of this file the current backend holds no advisory lock at all (none on hashtextextended(''card-pilot-revision/v1:<pilot org>:<pilot branch>'', 0)), so a lock seen after a call was taken by that call');
select is(jsonb_build_object('result', pg_temp.lr_r('lk_invalid'), 'locks_after', pg_temp.lr_r('lk_invalid_locks')),
  jsonb_build_object('result', pg_temp.lr_refusal('invalid_request'),
                     'locks_after', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb),
  'LR-184 (change 24) a set_card_payments_pilot refused invalid_request (p_enabled NULL) answers exactly {ok:false, error:invalid_request}; pg_locks for the current backend then shows no advisory lock on the pilot-revision key (and no advisory lock at all)');
select is(jsonb_build_object(
    'non_attested_actor', jsonb_build_object('result', pg_temp.lr_r('lk_actor'),
                                             'locks_after', pg_temp.lr_r('lk_actor_locks')),
    'absent_operator_reference', jsonb_build_object('result', pg_temp.lr_r('lk_absent_ref'),
                                                    'locks_after', pg_temp.lr_r('lk_absent_ref_locks'))),
  jsonb_build_object(
    'non_attested_actor', jsonb_build_object('result', pg_temp.lr_refusal('permission_denied'),
                                             'locks_after', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb),
    'absent_operator_reference', jsonb_build_object('result', pg_temp.lr_refusal('permission_denied'),
                                                    'locks_after', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb)),
  'LR-185 (change 24) then two calls refused permission_denied - a non-attested actor (staff 2, manager) with a valid reference, and the attested approver with a NULL operator reference - each answer exactly {ok:false, error:permission_denied} and leave no advisory lock on the pilot-revision key (none at all)');
select is(jsonb_build_object('result', pg_temp.lr_r('lk_reason'), 'locks_after', pg_temp.lr_r('lk_reason_locks')),
  jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                     'locks_after', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb),
  'LR-186 (change 24) then a call refused out_of_contract by a field rule (NULL reason; attested approver, valid reference) answers exactly {ok:false, error:precondition_failed, detail:out_of_contract} and leaves no advisory lock on the pilot-revision key (none at all)');
select is(jsonb_build_object(
    'past_window', jsonb_build_object('result', pg_temp.lr_r('lk_window'),
                                      'locks_after', pg_temp.lr_r('lk_window_locks')),
    'test_cap_missing', jsonb_build_object('result', pg_temp.lr_r('lk_test_cap'),
                                           'locks_after', pg_temp.lr_r('lk_test_cap_locks')),
    'live_cap_out_of_bound', jsonb_build_object('result', pg_temp.lr_r('lk_live_cap'),
                                                'locks_after', pg_temp.lr_r('lk_live_cap_locks'))),
  jsonb_build_object(
    'past_window', jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                                      'locks_after', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb),
    'test_cap_missing', jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'max_test_amount_missing'),
                                           'locks_after', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb),
    'live_cap_out_of_bound', jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'out_of_contract'),
                                                'locks_after', '{"pilot_revision_key": [], "advisory_locks": 0}'::jsonb)),
  'LR-187 (change 24) then the enabling checks that run last before the lock - ON with a past window (out_of_contract), ON TEST without a test cap (max_test_amount_missing), an out-of-bound live cap -1 (out_of_contract) - each answer exactly and leave no advisory lock on the pilot-revision key (none at all)');
select is(pg_temp.lr_r('lk_writes'), pg_temp.lr_r('lk_start') -> 'writes',
  'LR-188 (change 24) those seven refusals wrote nothing: revision rows, private events and the pilot organization''s tenant audit rows unchanged');
select is(jsonb_build_object('result', pg_temp.lr_r('lk_ok') - 'revision', 'locks_after', pg_temp.lr_r('lk_ok_locks')),
  jsonb_build_object('result', jsonb_build_object('ok', true, 'enabled', false, 'mode', 'test',
                                                  'window_until', now() + interval '12 hours',
                                                  'max_test_amount_minor', 5000, 'max_live_amount_minor', 1000000),
                     'locks_after', '{"pilot_revision_key": [{"mode": "ExclusiveLock", "granted": true}], "advisory_locks": 1}'::jsonb),
  'LR-189 (change 24) control: the next call, accepted (an OFF TEST revision by the attested approver, staff 9), then holds exactly that advisory lock - one pg_locks row on the pilot-revision key, ExclusiveLock, granted - and no other advisory lock');

-- =============================================================================
-- 16. Fix batch 7, change 25 (packet 11 item 26; API 4.55.10; DOMAIN 8.6): the TEST purge takes the terminal lock
--     of each device holding an expired, unheld TEST attempt, deletes only those devices' attempts, and keeps the
--     events of an attempt that still exists on a device it did not lock (they wait for the next run, like their
--     attempt); the 8.6 eligibility - expired, no own hold, attempt unheld - is otherwise unchanged, so the events of
--     a purged, a missing or no attempt, and of an unheld attempt on a locked device, still go. Single session: the
--     TEST attempts are inserted directly by the owner (no TEST binding can be current here: d1's LIVE binding is
--     the organization's admitting one), their events are the real finish's security.card_provider_field_dropped,
--     and the owner-only helpers age them.
--     Correction C1-3 (D-059 point 3): a batch now also selects every device holding an expired TEST event without a
--     hold of its own, so an unbounded batch would lock d1 too (cp_d1's expired event). The change-25 case - the
--     events of an attempt that still exists on a device the batch did not lock wait for a later batch - is
--     therefore reproduced with a batch bounded to one device (purge 1: p_max_devices 1 takes d2, the lower device
--     id); purge 2 is unbounded. The results and the event detail carry the C1-3 counts.
-- =============================================================================
-- The purge's candidate devices (C1-3; fixture numbers in device-id order, the order a batch selects and locks
-- them): each device holding an expired, unheld TEST attempt or an expired TEST event without a hold of its own.
create function pg_temp.lr_cp_purge_devices() returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(dv.d order by dv.id), '[]'::jsonb)
    from (select g.d, pg_temp.zc_id('device-' || g.d) as id from generate_series(1, 5) g(d)) dv
   where exists (select 1 from app.card_provider_attempts a
                  where a.device_id = dv.id and a.mode = 'test' and a.retention_until <= clock_timestamp()
                    and a.incident_hold_at is null)
      or exists (select 1 from app.card_provider_private_events e
                  where e.device_id = dv.id and e.mode = 'test' and e.retention_until <= clock_timestamp()
                    and e.incident_hold_at is null);
$$;
-- Which section-16 rows (and the held leftovers of sections 7 / 9) exist, and which section-16 identities are tombstoned.
create function pg_temp.lr_cp_presence() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'attempts', (select jsonb_object_agg(l, exists (select 1 from app.card_provider_attempts a
                                                     where a.id = pg_temp.lr_aid('cp_' || l)))
                   from unnest(array['d1', 'd2', 'd2k']) l),
    'events', (select jsonb_object_agg(l, exists (select 1 from app.card_provider_private_events e
                                                   where e.id = (pg_temp.lr_r(l) ->> 'id')::uuid))
                 from unnest(array['cp_ev_d1', 'cp_ev_d2a', 'cp_ev_d2b', 'cp_ev_d2c', 'cp_ev_d2k', 'ev_deny_hold']) l),
    'held_leftovers', jsonb_build_object(
      'attempt_pa2', exists (select 1 from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_pa2')),
      'event_pa2', exists (select 1 from app.card_provider_private_events e
                            where e.id = (pg_temp.lr_r('ev_pa2') ->> 'id')::uuid),
      'event_pa1_own', exists (select 1 from app.card_provider_private_events e
                                where e.id = (pg_temp.lr_r('ev_pa1_own') ->> 'id')::uuid)),
    'tombstoned', (select coalesce(jsonb_agg(l order by l), '[]'::jsonb) from unnest(array['d1', 'd2', 'd2k']) l
                    where exists (select 1 from app.card_attempt_identity_tombstones t
                                   where t.organization_id = pg_temp.zc_org()
                                     and t.local_operation_id = pg_temp.zc_lop('lr-cp-' || l))));
$$;
-- The identity a tombstone keeps, read from a ledger / tombstone row's JSON; the tombstone of a section-16 attempt.
create function pg_temp.lr_cp_identity(p_row jsonb) returns jsonb language sql immutable as $$
  select jsonb_build_object('organization_id', p_row -> 'organization_id', 'device_id', p_row -> 'device_id',
    'local_operation_id', p_row -> 'local_operation_id', 'provider_status_digest', p_row -> 'provider_status_digest',
    'provider_duplicate_digest', p_row -> 'provider_duplicate_digest',
    'provider_key_format_version', p_row -> 'provider_key_format_version',
    'provider_query_key', p_row -> 'provider_query_key', 'provider_duplicate_key', p_row -> 'provider_duplicate_key');
$$;
create function pg_temp.lr_cp_tombstone(p_label text) returns jsonb language sql stable as $$
  select pg_temp.lr_cp_identity(to_jsonb(t)) from app.card_attempt_identity_tombstones t
   where t.organization_id = pg_temp.zc_org() and t.local_operation_id = pg_temp.zc_lop('lr-cp-' || p_label);
$$;
insert into _zc_r select 'cp_base', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/cp-purge-0', pg_temp.zc_owner());
select is(pg_temp.lr_r('cp_base') - 'cutoff',
  '{"ok": true, "attempts_purged": 0, "events_purged": 0, "attempts_deferred": 0, "events_deferred": 0,
    "devices_locked": 0}'::jsonb,
  'LR-190 (change 25; C1-3) baseline: a purge before this setup deletes and defers nothing and locks no device - every expired TEST row left by sections 7 and 9 is held (the attempt pa2 and its event, pa1''s own-held event); a held attempt''s event selects nothing (C1 fix 2)');
-- cp_d1 on d1, cp_d2 and cp_d2k on d2 (the scope the finish is called with is the inserted row's own).
insert into _zc_r select 'cp_' || v.l, jsonb_build_object(
    'attempt_row_id', pg_temp.lr_insert_test_attempt(v.d, 'lr-cp-' || v.l), 'organization_id', pg_temp.zc_org(),
    'device_id', pg_temp.zc_id('device-' || v.d), 'local_operation_id', pg_temp.zc_lop('lr-cp-' || v.l),
    'mode', 'test', 'amount_minor', 500, 'currency_code', 'ILS')
  from (values ('d1', 1), ('d2', 2), ('d2k', 2)) v(l, d);
set local role service_role;
insert into _zc_r select 'cp_fin_' || v.l, pg_temp.zc_finish(pg_temp.lr_r('cp_' || v.a), v.src, v.outcome, v.f::jsonb)
  from (values ('d1', 'd1', 'commit', 'unknown', '{"provider_saved_at": "not-a-timestamp"}'),
               ('d2a', 'd2', 'commit', 'unknown', '{"provider_saved_at": "not-a-timestamp"}'),
               ('d2b', 'd2', 'lookup', 'not_found', '{"provider_return_code": "x1"}'),
               ('d2c', 'd2', 'lookup', 'not_found', '{"provider_currency": "ils"}'),
               ('d2k', 'd2k', 'commit', 'unknown', '{"provider_saved_at": "not-a-timestamp"}')) v(l, a, src, outcome, f);
reset role;
insert into _zc_r select 'cp_ev_' || v.l, (select to_jsonb(e) from app.card_provider_private_events e
   where e.attempt_row_id = pg_temp.lr_aid('cp_' || v.a) and e.action = 'security.card_provider_field_dropped'
     and e.detail ->> 'field' = v.field)
  from (values ('d1', 'd1', 'provider_saved_at'), ('d2a', 'd2', 'provider_saved_at'),
               ('d2b', 'd2', 'provider_return_code'), ('d2c', 'd2', 'provider_currency'),
               ('d2k', 'd2k', 'provider_saved_at')) v(l, a, field);
-- Expire: the attempt cp_d2; the events of cp_d1, cp_d2 (two of three), cp_d2k and the attempt-less denial of
-- section 6 (ev_deny_hold, its hold cleared by LR-112).
select pg_temp.lr_age_attempt(pg_temp.lr_aid('cp_d2'), false, true);
select pg_temp.lr_age_event((pg_temp.lr_r('cp_ev_' || l) ->> 'id')::uuid) from unnest(array['d1', 'd2a', 'd2b', 'd2k']) l;
select pg_temp.lr_age_event((pg_temp.lr_r('ev_deny_hold') ->> 'id')::uuid);
insert into _zc_r select 'cp_rows_0', jsonb_build_object(
  'd1', (select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.lr_aid('cp_d1')),
  'd2', (select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.lr_aid('cp_d2')),
  'd2k', (select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.lr_aid('cp_d2k')),
  'ev_d1', (select to_jsonb(e) from app.card_provider_private_events e
             where e.id = (pg_temp.lr_r('cp_ev_d1') ->> 'id')::uuid),
  'ev_d2c', (select to_jsonb(e) from app.card_provider_private_events e
              where e.id = (pg_temp.lr_r('cp_ev_d2c') ->> 'id')::uuid));
select results_eq(
  $$ select u.l, dv.d, a.mode, a.state, a.retention_until <= clock_timestamp(), a.incident_hold_at is not null,
            a.resolution
       from unnest(array['d1', 'd2', 'd2k']) with ordinality u(l, n)
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid('cp_' || u.l)
       join (select g.d, pg_temp.zc_id('device-' || g.d) as id from generate_series(1, 5) g(d)) dv on dv.id = a.device_id
      order by u.n $$,
  $$ values ('d1'::text, 1, 'test'::text, 'unknown'::text, false, false, null::text),
            ('d2', 2, 'test', 'unknown', true, false, null),
            ('d2k', 2, 'test', 'unknown', false, false, null) $$,
  'LR-191 (change 25) setup: three direct TEST attempts finished unknown - cp_d1 on d1 and cp_d2k on d2 unexpired, cp_d2 on d2 aged past its retention; none held, none resolved');
select results_eq(
  $$ select u.l, e.action, dv.d, e.attempt_row_id, e.mode, e.detail ->> 'field', e.retention_until <= clock_timestamp(),
            e.incident_hold_at is not null
       from unnest(array['cp_ev_d1', 'cp_ev_d2a', 'cp_ev_d2b', 'cp_ev_d2c', 'cp_ev_d2k', 'ev_deny_hold'])
              with ordinality u(l, n)
       join app.card_provider_private_events e on e.id = (pg_temp.lr_r(u.l) ->> 'id')::uuid
       join (select g.d, pg_temp.zc_id('device-' || g.d) as id from generate_series(1, 5) g(d)) dv on dv.id = e.device_id
      order by u.n $$,
  $$ values ('cp_ev_d1'::text, 'security.card_provider_field_dropped'::text, 1, pg_temp.lr_aid('cp_d1'), 'test'::text,
             'provider_saved_at'::text, true, false),
            ('cp_ev_d2a', 'security.card_provider_field_dropped', 2, pg_temp.lr_aid('cp_d2'), 'test', 'provider_saved_at',
             true, false),
            ('cp_ev_d2b', 'security.card_provider_field_dropped', 2, pg_temp.lr_aid('cp_d2'), 'test',
             'provider_return_code', true, false),
            ('cp_ev_d2c', 'security.card_provider_field_dropped', 2, pg_temp.lr_aid('cp_d2'), 'test', 'provider_currency',
             false, false),
            ('cp_ev_d2k', 'security.card_provider_field_dropped', 2, pg_temp.lr_aid('cp_d2k'), 'test', 'provider_saved_at',
             true, false),
            ('ev_deny_hold', 'test.card_attempt_denied', 2, null::uuid, 'test', null::text, true, false) $$,
  'LR-192 (change 25) setup: TEST events - cp_d1''s on d1 (expired, unheld), cp_d2''s three on d2 (provider_saved_at and provider_return_code expired, provider_currency not), cp_d2k''s (expired) and the attempt-less denial of section 6 (expired, unheld)');
select is(pg_temp.lr_cp_purge_devices(), '[2, 1]'::jsonb,
  'LR-193 (change 25; C1-3) setup: in device-id order the purge candidates are d2 (cp_d2 expired and unheld, with its expired events) and d1 (cp_d1''s expired event carries no hold of its own, though cp_d1 itself and the test_closed direct_t2 of section 3 are unexpired), so a batch bounded to one device takes the terminal lock of d2 and not of d1');
select pg_temp.lr_snap();
insert into _zc_r select 'cp_pre1', pg_temp.lr_purge_counts();
insert into _zc_r select 'cp_purge1', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/cp-purge-1', pg_temp.zc_owner(), 1);
select is(jsonb_build_object('result', pg_temp.lr_r('cp_purge1') - 'cutoff',
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'reference', e.actor_reference,
                                                                            'detail', e.detail) order by e.created_at, e.id)
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('result', '{"ok": true, "attempts_purged": 1, "events_purged": 4, "attempts_deferred": 0,
                                 "events_deferred": 1, "devices_locked": 1}'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempts_purged',
                       'reference', 'zc001d-lr/cp-purge-1',
                       'detail', jsonb_build_object('attempts_purged', 1, 'events_purged', 4, 'attempts_deferred', 0,
                                                    'events_deferred', 1, 'devices_locked', 1,
                                                    'cutoff', pg_temp.lr_r('cp_purge1') -> 'cutoff')))),
  'LR-194 (change 25; C1-3) purge 1 (p_max_devices 1): ok with exactly 1 attempt (cp_d2) and 4 events (cp_d2''s two expired ones, cp_d2k''s on the locked d2, the attempt-less denial), 0 attempts and 1 event deferred (cp_d1''s, waiting on the unlocked d1), 1 device locked; exactly one operator.card_test_attempts_purged with those counts');
select is(pg_temp.lr_cp_presence(),
  '{"attempts": {"d1": true, "d2": false, "d2k": true},
    "events": {"cp_ev_d1": true, "cp_ev_d2a": false, "cp_ev_d2b": false, "cp_ev_d2c": true, "cp_ev_d2k": false,
               "ev_deny_hold": false},
    "held_leftovers": {"attempt_pa2": true, "event_pa2": true, "event_pa1_own": true},
    "tombstoned": ["d2"]}'::jsonb,
  'LR-195 (change 25; C1-3) after purge 1: cp_d1''s expired, unheld event is KEPT (its attempt still exists on d1, whose terminal lock the bounded batch did not take) with cp_d1 itself; cp_d2 and its two expired events, the expired event of the unexpired, unheld cp_d2k on the locked d2 and the attempt-less denial are gone; cp_d2''s unexpired event, cp_d2k and the held leftovers stay; only cp_d2 is tombstoned');
select is(jsonb_build_object(
    'cp_d1_unchanged', (select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.lr_aid('cp_d1'))
                       = pg_temp.lr_r('cp_rows_0') -> 'd1',
    'cp_d2k_unchanged', (select to_jsonb(a) from app.card_provider_attempts a where a.id = pg_temp.lr_aid('cp_d2k'))
                        = pg_temp.lr_r('cp_rows_0') -> 'd2k',
    'cp_ev_d1_unchanged', (select to_jsonb(e) from app.card_provider_private_events e
                            where e.id = (pg_temp.lr_r('cp_ev_d1') ->> 'id')::uuid) = pg_temp.lr_r('cp_rows_0') -> 'ev_d1',
    'cp_ev_d2c_unchanged', (select to_jsonb(e) from app.card_provider_private_events e
                             where e.id = (pg_temp.lr_r('cp_ev_d2c') ->> 'id')::uuid) = pg_temp.lr_r('cp_rows_0') -> 'ev_d2c',
    'tombstone_cp_d2', pg_temp.lr_cp_tombstone('d2'),
    'counts', pg_temp.lr_purge_counts()),
  jsonb_build_object('cp_d1_unchanged', true, 'cp_d2k_unchanged', true, 'cp_ev_d1_unchanged', true,
    'cp_ev_d2c_unchanged', true, 'tombstone_cp_d2', pg_temp.lr_cp_identity(pg_temp.lr_r('cp_rows_0') -> 'd2'),
    'counts', pg_temp.lr_r('cp_pre1') || jsonb_build_object(
      'test_attempts', (pg_temp.lr_r('cp_pre1') ->> 'test_attempts')::int - 1,
      'test_events', (pg_temp.lr_r('cp_pre1') ->> 'test_events')::int - 4,
      'operator_events', (pg_temp.lr_r('cp_pre1') ->> 'operator_events')::int + 1,
      'tombstones', (pg_temp.lr_r('cp_pre1') ->> 'tombstones')::int + 1)),
  'LR-196 (change 25; C1-3) purge 1 left the waiting rows byte-identical (cp_d1 and its expired event, cp_d2k, cp_d2''s unexpired event), tombstoned cp_d2''s identity (tuple, digests, formatter version, outbound keys) and changed nothing else: TEST attempts - 1, TEST events - 4, operator.* events + 1, tombstones + 1, every LIVE attempt and LIVE event kept');
select pg_temp.lr_age_attempt(pg_temp.lr_aid('cp_d1'), false, true);
select pg_temp.lr_age_event((pg_temp.lr_r('cp_ev_d2c') ->> 'id')::uuid);
select is(jsonb_build_object('purge_devices', pg_temp.lr_cp_purge_devices(),
    'cp_d1', (select jsonb_build_array(a.retention_until <= clock_timestamp(), a.incident_hold_at is not null)
                from app.card_provider_attempts a where a.id = pg_temp.lr_aid('cp_d1')),
    'cp_ev_d2c', (select jsonb_build_array(e.retention_until <= clock_timestamp(), e.incident_hold_at is not null,
                                           exists (select 1 from app.card_provider_attempts a where a.id = e.attempt_row_id))
                    from app.card_provider_private_events e where e.id = (pg_temp.lr_r('cp_ev_d2c') ->> 'id')::uuid)),
  '{"purge_devices": [2, 1], "cp_d1": [true, false], "cp_ev_d2c": [true, false, false]}'::jsonb,
  'LR-197 (change 25; C1-3) setup 2: cp_d1 itself aged past its retention (unheld) and cp_d2''s provider_currency event aged expired (unheld) while its attempt is missing (purged by purge 1) - the candidates are d2 and d1, in device-id order');
select pg_temp.lr_snap();
insert into _zc_r select 'cp_pre2', pg_temp.lr_purge_counts();
insert into _zc_r select 'cp_purge2', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/cp-purge-2', pg_temp.zc_owner());
select is(jsonb_build_object('result', pg_temp.lr_r('cp_purge2') - 'cutoff',
                             'events', (select jsonb_agg(jsonb_build_object('action', e.action, 'reference', e.actor_reference,
                                                                            'detail', e.detail) order by e.created_at, e.id)
                                          from pg_temp.lr_new_events() e)),
  jsonb_build_object('result', '{"ok": true, "attempts_purged": 1, "events_purged": 2, "attempts_deferred": 0,
                                 "events_deferred": 0, "devices_locked": 2}'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempts_purged',
                       'reference', 'zc001d-lr/cp-purge-2',
                       'detail', jsonb_build_object('attempts_purged', 1, 'events_purged', 2, 'attempts_deferred', 0,
                                                    'events_deferred', 0, 'devices_locked', 2,
                                                    'cutoff', pg_temp.lr_r('cp_purge2') -> 'cutoff')))),
  'LR-198 (change 25; C1-3) purge 2 (unbounded: d2 and d1 locked): ok with exactly 1 attempt (cp_d1) and 2 events - cp_d1''s event, kept by purge 1, now follows its purged attempt, and cp_d2''s provider_currency event follows its missing attempt - nothing deferred, 2 devices locked; exactly one operator.card_test_attempts_purged with those counts');
select is(jsonb_build_object('presence', pg_temp.lr_cp_presence(), 'tombstone_cp_d1', pg_temp.lr_cp_tombstone('d1'),
                             'counts', pg_temp.lr_purge_counts()),
  jsonb_build_object('presence', '{"attempts": {"d1": false, "d2": false, "d2k": true},
                                   "events": {"cp_ev_d1": false, "cp_ev_d2a": false, "cp_ev_d2b": false,
                                              "cp_ev_d2c": false, "cp_ev_d2k": false, "ev_deny_hold": false},
                                   "held_leftovers": {"attempt_pa2": true, "event_pa2": true, "event_pa1_own": true},
                                   "tombstoned": ["d1", "d2"]}'::jsonb,
    'tombstone_cp_d1', pg_temp.lr_cp_identity(pg_temp.lr_r('cp_rows_0') -> 'd1'),
    'counts', pg_temp.lr_r('cp_pre2') || jsonb_build_object(
      'test_attempts', (pg_temp.lr_r('cp_pre2') ->> 'test_attempts')::int - 1,
      'test_events', (pg_temp.lr_r('cp_pre2') ->> 'test_events')::int - 2,
      'operator_events', (pg_temp.lr_r('cp_pre2') ->> 'operator_events')::int + 1,
      'tombstones', (pg_temp.lr_r('cp_pre2') ->> 'tombstones')::int + 1)),
  'LR-199 (change 25; C1-3) after purge 2: cp_d1 and both events gone, cp_d1''s identity tombstoned (cp_d2''s kept); cp_d2k (unexpired) and the held leftovers (the attempt pa2, its event, pa1''s own-held event) still present; TEST attempts - 1, TEST events - 2, operator.* events + 1, tombstones + 1, nothing else changed');


-- =============================================================================
-- 17. Correction C1-2 (packet 11 item 24 as amended; D-059 point 2; API 4.55.9): the inactive-device shutdown. On an
--     inactive, deleted or management-revoked pilot POS device draining (from enabled) and retired (from configured /
--     draining) proceed with every unchanged gate - retirement: no unresolved TEST or LIVE attempt of the device and
--     no pending / in-flight payment.create; one admitting binding per organization; attested approver, operator
--     reference, reason, executor, one private event - while configured (creation / rotation) and enabled
--     (activation / re-enable) answer invalid_request. 17.1: d1 revoked through the Dashboard's
--     revoke_device_management (a manager's JWT) while section 12's LIVE attempts are unresolved, and its
--     replacement d2. 17.2: the retirement gate one unresolved attempt at a time on a deleted d2.
-- =============================================================================
-- Short names of attempt rows for lr_unresolved(): section 12's eight LIVE attempts of d1 and those added below.
create temp table _lr_names (id uuid primary key, name text not null unique);
insert into _lr_names select pg_temp.lr_aid('claim_fo_' || l), 'fo_' || l
  from unnest(array['appr', 'sent', 'decl', 'unk', 'rel', 'look', 'anom', 'free']) l;
-- The unresolved attempts of device d (the 4.55.9 gate's set): name -> [mode, state, derived classification,
-- derived reason].
create function pg_temp.lr_unresolved(p_d integer) returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(coalesce(n.name, 'unnamed:' || a.id::text),
                                   jsonb_build_array(a.mode, a.state, x.d ->> 'classification', x.d ->> 'reason')),
                  '{}'::jsonb)
    from app.card_provider_attempts a
    cross join lateral (select app.card_attempt_derive(a) as d) x
    left join _lr_names n on n.id = a.id
   where a.device_id = pg_temp.zc_id('device-' || p_d) and (x.d ->> 'unresolved')::boolean;
$$;
-- The order claim of each named section-12 attempt (4.55.3 "active claim").
create function pg_temp.lr_fo_claims() returns jsonb language sql stable as $$
  select jsonb_object_agg(n.name, app.card_order_claim_active(a.organization_id, a.order_id))
    from app.card_provider_attempts a join _lr_names n on n.id = a.id where n.name like 'fo\_%';
$$;
-- One retirement call of device d's LIVE binding and whether it wrote nothing at all.
create function pg_temp.lr_retire_probe(p_d integer, p_term text, p_cred text) returns jsonb
language plpgsql volatile as $$
declare
  v_before jsonb := pg_temp.lr_world();
  v jsonb;
begin
  v := pg_temp.lr_term(p_d, 'live', 'retired', p_term, p_cred, 'end_of_pilot');
  return jsonb_build_object('result', v, 'wrote_nothing', pg_temp.lr_world() = v_before);
end $$;
create function pg_temp.lr_unresolved_refusal() returns jsonb language sql immutable as $$
  select jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'attempt_unresolved'),
                            'wrote_nothing', true);
$$;
-- A LIVE attempt row of device d inserted directly by the owner for the existing order 'order-<label>' (every CHECK and
-- the insert guard apply): used only where a drained binding makes the state unreachable through the RPCs. Returns
-- the finish scope (as a claim answers it); the row is named after the label (lr-pk-sent -> pk_sent).
create function pg_temp.lr_insert_live_attempt(p_d integer, p_label text, p_term text, p_cred text) returns jsonb
language plpgsql volatile as $$
declare
  v_id uuid;
begin
  insert into app.card_provider_attempts (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
      order_id, shift_id, cash_drawer_session_id, initiated_by_employee_profile_id, initiated_by_membership_id, mode,
      amount_minor, currency_code, expected_revision, terminal_ref, credential_ref, provider_status_digest,
      provider_duplicate_digest, provider_key_format_version, provider_query_key, provider_duplicate_key,
      start_deadline_at)
  select dv.organization_id, dv.restaurant_id, dv.branch_id, dv.id, k.lop, pg_temp.zc_id('order-' || p_label),
         pg_temp.zc_id('shift-' || p_d), pg_temp.zc_id('drawer-' || dv.id), pg_temp.zc_id('employee-' || st.n),
         pg_temp.zc_id('membership-' || st.n), 'live', 1234, 'ILS', 1, p_term, p_cred, k.sd, k.dd, 'alpha16-l32-v1',
         app.card_provider_key(k.sd, 'alpha16-l32-v1'), app.card_provider_key(k.dd, 'alpha16-l32-v1'),
         clock_timestamp() + interval '120 seconds'
    from public.devices dv
    cross join (select case p_d when 2 then 8 else 1 end as n) st
    cross join lateral (select pg_temp.zc_lop(p_label) as lop) l
    cross join lateral (select l.lop,
                               app.card_identity_digest('card-status-key/v1', dv.organization_id, dv.id, l.lop) as sd,
                               app.card_identity_digest('card-duplicate-key/v1', dv.organization_id, dv.id, l.lop) as dd) k
   where dv.id = pg_temp.zc_id('device-' || p_d)
  returning id into v_id;
  insert into _lr_names values (v_id, replace(substr(p_label, 4), '-', '_'));
  return jsonb_build_object('attempt_row_id', v_id, 'organization_id', pg_temp.zc_org(),
    'device_id', pg_temp.zc_id('device-' || p_d), 'local_operation_id', pg_temp.zc_lop(p_label), 'mode', 'live',
    'amount_minor', 1234, 'currency_code', 'ILS');
end $$;

-- 17.1 Setup: the replacement d2 (its unresolved TEST attempt cp_d2k test_closed first) gets a configured LIVE binding.
insert into _zc_r select 'sd_close_d2k', app.card_attempt_resolve_orphan(pg_temp.lr_aid('cp_d2k'), 'test_closed',
  'lr-test-ref-d2k', 'ZC001D LR TEST run closed', 'zc001d-lr/test-close-d2k', pg_temp.zc_owner());
insert into _zc_r select 'sd_r2_cfg', pg_temp.lr_term(2, 'live', 'configured', 'lr-term-r2', 'lr-cred-r2', 'live_activation');
insert into _zc_r select 'sd_r2_en_1', pg_temp.lr_term(2, 'live', 'enabled', 'lr-term-r2', 'lr-cred-r2', 'live_activation');
select is(jsonb_build_object(
    'd1_binding', (select jsonb_build_array(t.mode, t.terminal_ref, t.lifecycle) from pg_temp.lr_current(1) t),
    'd1_device', (select jsonb_build_array(d.is_active, d.deleted_at is null) from public.devices d
                   where d.id = pg_temp.zc_id('device-1')),
    'd1_unresolved', pg_temp.lr_unresolved(1),
    'cp_d2k', pg_temp.lr_r('sd_close_d2k') ->> 'resolution',
    'd2_unresolved', pg_temp.lr_unresolved(2),
    'd2_create', pg_temp.lr_r('sd_r2_cfg'),
    'd2_enable_while_d1_enabled', pg_temp.lr_r('sd_r2_en_1'),
    'd2_binding', (select jsonb_build_array(t.mode, t.terminal_ref, t.lifecycle) from pg_temp.lr_current(2) t)),
  jsonb_build_object(
    'd1_binding', '["live", "lr-term-l4", "enabled"]'::jsonb,
    'd1_device', '[true, true]'::jsonb,
    'd1_unresolved', '{"fo_appr": ["live", "approved", "approved_unrecorded", "pending_recording"],
                       "fo_sent": ["live", "sent", "in_progress", null],
                       "fo_unk": ["live", "unknown", "in_progress", null],
                       "fo_rel": ["live", "released", "in_progress", null],
                       "fo_look": ["live", "unknown", "in_progress", null],
                       "fo_anom": ["live", "approved", "approved_unrecorded", "pending_recording"]}'::jsonb,
    'cp_d2k', 'test_closed', 'd2_unresolved', '{}'::jsonb,
    'd2_create', pg_temp.lr_tres('live', null, 'configured'),
    'd2_enable_while_d1_enabled', pg_temp.lr_refusal('precondition_failed', 'admitting_binding_exists'),
    'd2_binding', '["live", "lr-term-r2", "configured"]'::jsonb),
  'LR-200 (C1-2) setup: d1 (active) holds its enabled LIVE binding lr-term-l4 with section 12''s six unresolved LIVE attempts (two approved unrecorded, one sent, two unknown, one released); the replacement d2 (its unresolved TEST attempt test_closed, nothing unresolved) gets a configured LIVE binding lr-term-r2, and enabling it while d1''s binding is enabled -> admitting_binding_exists (d2 stays configured)');

-- 17.1 The Dashboard revocation of d1: app.revoke_device_management through manager staff 2's JWT principal.
insert into auth.users (id, email) values (pg_temp.zc_id('lr-auth-manager'), 'zc001d-lr-manager@example.test');
update public.app_users set auth_user_id = pg_temp.zc_id('lr-auth-manager') where id = pg_temp.zc_id('user-2');
insert into _zc_r select 'sd_rows_0', (select jsonb_object_agg(a.id, to_jsonb(a)) from app.card_provider_attempts a
                                        where a.device_id = pg_temp.zc_id('device-1'));
insert into _zc_r select 'sd_binding_0', (select to_jsonb(t) from pg_temp.lr_current(1) t);
insert into _zc_r select 'sd_claims_0', pg_temp.lr_fo_claims();
select pg_temp.lr_mark();
select set_config('request.jwt.claim.sub', pg_temp.zc_id('lr-auth-manager')::text, true);
set local role authenticated;
insert into _zc_r select 'sd_revoke', public.revoke_device_management(pg_temp.zc_id('lr-revoke-request'),
  pg_temp.zc_id('device-1'), 'ZC001D synthetic dead till');
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
insert into _zc_r select 'sd_revoke_delta', pg_temp.lr_delta();
select is(jsonb_build_object('result', pg_temp.lr_r('sd_revoke'),
                             'device', (select jsonb_build_object('is_active', d.is_active, 'deleted', d.deleted_at is not null)
                                          from public.devices d where d.id = pg_temp.zc_id('device-1')),
                             'delta', pg_temp.lr_r('sd_revoke_delta')),
  jsonb_build_object('result', jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device',
                                                  'device_id', pg_temp.zc_id('device-1'), 'pairings_revoked', 1,
                                                  'sessions_revoked', 1),
                     'device', '{"is_active": false, "deleted": false}'::jsonb,
                     'delta', jsonb_build_object(
                       'audit', jsonb_build_array(jsonb_build_object('organization_id', pg_temp.zc_org(),
                         'restaurant_id', pg_temp.zc_rest(), 'branch_id', pg_temp.zc_branch(),
                         'actor_app_user_id', pg_temp.zc_id('user-2'), 'actor_employee_profile_id', null,
                         'device_id', null, 'action', 'device.revoked_management',
                         'reason', 'ZC001D synthetic dead till',
                         'old_values', jsonb_build_object('device_id', pg_temp.zc_id('device-1'), 'is_active', true,
                                                          'live_pairings', 1, 'live_sessions', 1),
                         'new_values', jsonb_build_object('device_id', pg_temp.zc_id('device-1'), 'is_active', false,
                                                          'pairings_revoked', 1, 'sessions_revoked', 1))),
                       'events', 0, 'attempts_changed', 0)),
  'LR-201 (C1-2) d1 revoked through the Dashboard''s revoke_device_management (manager staff 2''s JWT): ok with one pairing and one device session revoked, the device record inactive (not deleted); exactly one tenant audit device.revoked_management, no private event, no attempt row inserted, changed or deleted');
select is(jsonb_build_object(
    'rows_identical', (select jsonb_object_agg(a.id, to_jsonb(a)) from app.card_provider_attempts a
                        where a.device_id = pg_temp.zc_id('device-1')) = pg_temp.lr_r('sd_rows_0'),
    'unresolved', pg_temp.lr_unresolved(1),
    'claims_before', pg_temp.lr_r('sd_claims_0'),
    'claims_after', pg_temp.lr_fo_claims(),
    'binding_identical', (select to_jsonb(t) from pg_temp.lr_current(1) t) = pg_temp.lr_r('sd_binding_0')),
  jsonb_build_object('rows_identical', true,
    'unresolved', '{"fo_appr": ["live", "approved", "orphan_approved", "device_revoked"],
                    "fo_sent": ["live", "sent", "in_progress", null],
                    "fo_unk": ["live", "unknown", "in_progress", null],
                    "fo_rel": ["live", "released", "in_progress", null],
                    "fo_look": ["live", "unknown", "in_progress", null],
                    "fo_anom": ["live", "approved", "orphan_approved", "device_revoked"]}'::jsonb,
    'claims_before', '{"fo_appr": true, "fo_sent": true, "fo_decl": false, "fo_unk": true, "fo_rel": true,
                       "fo_look": true, "fo_anom": true, "fo_free": false}'::jsonb,
    'claims_after', '{"fo_appr": true, "fo_sent": true, "fo_decl": false, "fo_unk": true, "fo_rel": true,
                      "fo_look": true, "fo_anom": true, "fo_free": false}'::jsonb,
    'binding_identical', true),
  'LR-202 (C1-2) management revoke resolves and frees nothing: every d1 attempt row byte-identical (no resolution, no free stamp, state and claim signal kept), the same six attempts stay unresolved - the two approved ones now orphan_approved / device_revoked, the sent, unknown and released ones in_progress - every order claim stays as it was (six active), and the enabled binding row is untouched');

-- Re-pairing the revoked d1 through the product paths: a Dashboard enrollment code, and the redemption of a code
-- issued for it (inserted directly as the owner: the revocation revoked every live pairing).
insert into public.device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status,
                                    enrollment_code_hash, code_expires_at)
values (pg_temp.zc_id('pairing-1-lr-code'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
        pg_temp.zc_id('device-1'), 'code_issued', app.hash_provisioning_secret('zc001d-lr-repair-code'),
        now() + interval '10 minutes');
select set_config('request.jwt.claim.sub', pg_temp.zc_id('lr-auth-manager')::text, true);
set local role authenticated;
insert into _zc_r select 'sd_rp_issue', to_jsonb(pg_temp.lr_try(format(
  'select public.issue_device_enrollment_code(%L::uuid, %L::uuid, null::interval)',
  pg_temp.zc_id('lr-repair-request'), pg_temp.zc_id('device-1'))));
insert into _zc_r select 'sd_rp_redeem', public.redeem_device_pairing('zc001d-lr-repair-code', 'pos');
reset role;
select set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true);
select is(jsonb_build_object(
    'issue_enrollment_code', pg_temp.lr_r('sd_rp_issue'),
    'redeem', pg_temp.lr_r('sd_rp_redeem'),
    'code_pairing', (select dp.status from public.device_pairings dp where dp.id = pg_temp.zc_id('pairing-1-lr-code')),
    'live_device_sessions', (select count(*) from public.device_sessions ds
                              where ds.device_id = pg_temp.zc_id('device-1') and ds.is_active and ds.revoked_at is null),
    'device_active', (select d.is_active from public.devices d where d.id = pg_temp.zc_id('device-1')),
    'orphans', (select jsonb_object_agg(x.k, x.v) from jsonb_each(pg_temp.lr_unresolved(1)) x(k, v)
                 where x.v ->> 2 = 'orphan_approved')),
  jsonb_build_object('issue_enrollment_code', '42501',
    'redeem', '{"ok": false, "error": "invalid_code", "entity": "device_pairing"}'::jsonb,
    'code_pairing', 'code_issued', 'live_device_sessions', 0, 'device_active', false,
    'orphans', '{"fo_appr": ["live", "approved", "orphan_approved", "device_revoked"],
                 "fo_anom": ["live", "approved", "orphan_approved", "device_revoked"]}'::jsonb),
  'LR-203 (C1-2) re-pairing never clears the sticky device_revoked: the Dashboard cannot issue an enrollment code for the revoked d1 (42501) and a code issued for it is not redeemable (invalid_code: the pairing stays code_issued, no device session is minted); the device record stays inactive and both orphans keep device_revoked');
insert into public.device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status, paired_at)
values (pg_temp.zc_id('pairing-1-lr-oob'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
        pg_temp.zc_id('device-1'), 'active', now());
insert into public.device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                                    session_token_ref, expires_at)
values (pg_temp.zc_id('dsession-1-lr-oob'), pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
        pg_temp.zc_id('device-1'), pg_temp.zc_id('pairing-1-lr-oob'), app.hash_provisioning_secret('zc-token-1-lr-oob'),
        now() + interval '30 days');
select is(pg_temp.lr_unresolved(1),
  '{"fo_appr": ["live", "approved", "orphan_approved", "device_revoked"],
    "fo_sent": ["live", "sent", "in_progress", null], "fo_unk": ["live", "unknown", "in_progress", null],
    "fo_rel": ["live", "released", "in_progress", null], "fo_look": ["live", "unknown", "in_progress", null],
    "fo_anom": ["live", "approved", "orphan_approved", "device_revoked"]}'::jsonb,
  'LR-204 (C1-2) even an active pairing with a live device session inserted for the revoked d1 out of band leaves both orphans device_revoked (the reason follows the management-inactive device record, not the pairing) and the four in-progress attempts unchanged');

-- The shutdown steps keep their authority and scope gates.
insert into _zc_r select 'sd_world_g0', pg_temp.lr_world();
insert into _zc_r select 'sd_pd', jsonb_build_object(
  'staff2_drain', pg_temp.lr_term(1, 'live', 'draining', 'lr-term-l4', 'lr-cred-l4', 'incident',
                                  p_actor => pg_temp.zc_id('user-2')),
  'revoked_owner_drain', pg_temp.lr_term(1, 'live', 'draining', 'lr-term-l4', 'lr-cred-l4', 'incident',
                                         p_actor => pg_temp.zc_id('user-lr-rv')),
  'staff2_retire', pg_temp.lr_term(1, 'live', 'retired', 'lr-term-l4', 'lr-cred-l4', 'end_of_pilot',
                                   p_actor => pg_temp.zc_id('user-2')));
update public.devices set is_active = false
 where id in (pg_temp.zc_id('device-3'), pg_temp.zc_id('device-4'), pg_temp.zc_id('device-5'));
insert into _zc_r select 'sd_scope', jsonb_build_object(
  'foreign_own_binding_retire', pg_temp.lr_term(4, 'test', 'retired', 'lr-term-b4', 'lr-cred-a', 'test_end'),
  'foreign_drain', pg_temp.lr_term(4, 'test', 'draining', 'lr-term-b4', 'lr-cred-a', 'test_end'),
  'sibling_drain', pg_temp.lr_term(5, 'live', 'draining', 'lr-term-s5', 'lr-cred-s5', 'incident'),
  'sibling_retire', pg_temp.lr_term(5, 'live', 'retired', 'lr-term-s5', 'lr-cred-s5', 'end_of_pilot'),
  'kds_retire', pg_temp.lr_term(3, 'live', 'retired', 'lr-term-k3', 'lr-cred-k3', 'end_of_pilot'),
  'unknown_device_retire', app.set_payment_terminal(pg_temp.zc_id('device-lr-unknown'), 'live', 'lr-term-x',
    'lr-cred-x', 'retired', 'end_of_pilot', 'ZC001D LR binding', 'zc001d-lr/bind-1', pg_temp.zc_owner()));
update public.devices set is_active = true
 where id in (pg_temp.zc_id('device-3'), pg_temp.zc_id('device-4'), pg_temp.zc_id('device-5'));
insert into _zc_r select 'sd_world_g1', pg_temp.lr_world();
select is(jsonb_build_object('non_attested', pg_temp.lr_r('sd_pd'), 'outside_scope', pg_temp.lr_r('sd_scope'),
                             'wrote_nothing', pg_temp.lr_r('sd_world_g1') = pg_temp.lr_r('sd_world_g0'),
                             'd4_binding', (select t.lifecycle from app.payment_terminals t
                                             where t.device_id = pg_temp.zc_id('device-4') and t.terminal_ref = 'lr-term-b4')),
  jsonb_build_object('non_attested', jsonb_build_object('staff2_drain', pg_temp.lr_refusal('permission_denied'),
                                                        'revoked_owner_drain', pg_temp.lr_refusal('permission_denied'),
                                                        'staff2_retire', pg_temp.lr_refusal('permission_denied')),
                     'outside_scope', jsonb_build_object('foreign_own_binding_retire', pg_temp.lr_refusal('invalid_request'),
                                                         'foreign_drain', pg_temp.lr_refusal('invalid_request'),
                                                         'sibling_drain', pg_temp.lr_refusal('invalid_request'),
                                                         'sibling_retire', pg_temp.lr_refusal('invalid_request'),
                                                         'kds_retire', pg_temp.lr_refusal('invalid_request'),
                                                         'unknown_device_retire', pg_temp.lr_refusal('invalid_request')),
                     'wrote_nothing', true, 'd4_binding', 'configured'),
  'LR-205 (C1-2) the shutdown steps keep their authority and scope gates: on the revoked d1 a non-attested actor (staff 2, manager; a revoked pilot org_owner) gets permission_denied for draining and retired; on inactive devices outside the pilot scope - the foreign POS d4 with its own configured TEST binding, the sibling-branch POS d5, the pilot KDS d3 - and on an unknown device, draining and retired answer invalid_request; nothing written (d4''s binding stays configured)');

-- configured / enabled on the revoked d1 while its binding is enabled.
insert into _zc_r select 'sd_world_r0', pg_temp.lr_world();
insert into _zc_r select 'sd_refused_enabled', pg_temp.lr_ia_refused();
insert into _zc_r select 'sd_world_r1', pg_temp.lr_world();
select is(jsonb_build_object('refused', pg_temp.lr_r('sd_refused_enabled'),
                             'wrote_nothing', pg_temp.lr_r('sd_world_r1') = pg_temp.lr_r('sd_world_r0')),
  jsonb_build_object('refused', pg_temp.lr_ia_refusals(), 'wrote_nothing', true),
  'LR-206 (C1-2) on the revoked d1 with its binding enabled: configured with the own references, enabled with them (on an active device a no-op repeat) and configured with new references (on an active device binding_exists) each answer invalid_request and write nothing');
-- The drain of the revoked device's enabled binding.
select pg_temp.lr_snap();
insert into _zc_r select 'sd_drain', pg_temp.lr_term(1, 'live', 'draining', 'lr-term-l4', 'lr-cred-l4', 'incident');
insert into _zc_r select 'sd_drain_events', pg_temp.lr_new_event_rows();
insert into _zc_r select 'sd_r2_en_2', pg_temp.lr_term(2, 'live', 'enabled', 'lr-term-r2', 'lr-cred-r2', 'live_activation');
select is(jsonb_build_object('result', pg_temp.lr_r('sd_drain'), 'events', pg_temp.lr_r('sd_drain_events'),
                             'd1_unresolved', (select count(*) from jsonb_object_keys(pg_temp.lr_unresolved(1))),
                             'd2_enable_while_d1_draining', pg_temp.lr_r('sd_r2_en_2'),
                             'd2_lifecycle', (select t.lifecycle from pg_temp.lr_current(2) t)),
  jsonb_build_object('result', pg_temp.lr_tres('live', 'enabled', 'draining'),
                     'events', jsonb_build_array(pg_temp.lr_tev_row(1, 'live', 'enabled', 'draining', false, 'incident')),
                     'd1_unresolved', 6,
                     'd2_enable_while_d1_draining', pg_temp.lr_refusal('precondition_failed', 'admitting_binding_exists'),
                     'd2_lifecycle', 'configured'),
  'LR-207 (C1-2) the management-revoked d1''s enabled LIVE binding drains with its six attempts unresolved: ok {live, enabled -> draining} and exactly one operator.payment_terminal_updated (attested approver staff 9, executor_principal = session_user, the device, mode NULL, no retention); the replacement d2 still cannot be enabled while d1''s binding is draining -> admitting_binding_exists');
insert into _zc_r select 'sd_world_r2', pg_temp.lr_world();
insert into _zc_r select 'sd_refused_draining', pg_temp.lr_ia_refused();
insert into _zc_r select 'sd_world_r3', pg_temp.lr_world();
select is(jsonb_build_object('refused', pg_temp.lr_r('sd_refused_draining'),
                             'wrote_nothing', pg_temp.lr_r('sd_world_r3') = pg_temp.lr_r('sd_world_r2')),
  jsonb_build_object('refused', pg_temp.lr_ia_refusals(), 'wrote_nothing', true),
  'LR-208 (C1-2) with the revoked d1''s binding draining: the re-enable (enabled), configured with the own references and the rotation (configured, new references, same mode) each answer invalid_request and write nothing');
-- The retirement gate on the revoked device.
insert into _zc_r select 'sd_retire_1', pg_temp.lr_retire_probe(1, 'lr-term-l4', 'lr-cred-l4');
select is(pg_temp.lr_r('sd_retire_1'), pg_temp.lr_unresolved_refusal(),
  'LR-209 (C1-2) retirement of the revoked d1''s draining binding with its six attempts unresolved -> precondition_failed / attempt_unresolved, nothing written');
set local role service_role;
insert into _zc_r select 'sd_fin_sent', pg_temp.zc_finish(pg_temp.lr_r('claim_fo_sent'), 'commit', 'declined',
                                                          '{"approval_type": "declined"}'::jsonb);
insert into _zc_r select 'sd_fin_' || l, pg_temp.zc_finish(pg_temp.lr_r('claim_fo_' || l), 'lookup', 'declined',
                                                           '{"approval_type": "declined"}'::jsonb)
  from unnest(array['unk', 'rel', 'look']) l;
reset role;
insert into _zc_r select 'sd_retire_2', pg_temp.lr_retire_probe(1, 'lr-term-l4', 'lr-cred-l4');
select is(jsonb_build_object('finished', (select jsonb_agg(pg_temp.lr_r('sd_fin_' || u.l) ->> 'state' order by u.n)
                                            from unnest(array['sent', 'unk', 'rel', 'look']) with ordinality u(l, n)),
                             'unresolved', pg_temp.lr_unresolved(1), 'retire', pg_temp.lr_r('sd_retire_2')),
  jsonb_build_object('finished', '["declined", "declined", "declined", "declined"]'::jsonb,
                     'unresolved', '{"fo_appr": ["live", "approved", "orphan_approved", "device_revoked"],
                                     "fo_anom": ["live", "approved", "orphan_approved", "device_revoked"]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-210 (C1-2) the provider still settles the revoked till''s in-progress attempts (scope-bound finishes: a commit and three lookups declined), leaving exactly the two orphans (device_revoked) unresolved: retirement -> attempt_unresolved, nothing written');
insert into _zc_r select 'sd_ro_' || l, app.card_attempt_resolve_orphan(pg_temp.lr_aid('claim_fo_' || l), 'provider_voided',
  'lr-void-ref-sd-' || l, 'ZC001D LR provider void confirmed', 'zc001d-lr/sd-orphan-' || l, pg_temp.zc_owner())
  from unnest(array['appr', 'anom']) l;
select is(jsonb_build_object('appr', pg_temp.lr_r('sd_ro_appr') - 'server_ts' - 'attempt_row_id' - 'attempt_id',
                             'anom', pg_temp.lr_r('sd_ro_anom') - 'server_ts' - 'attempt_row_id' - 'attempt_id',
                             'unresolved', pg_temp.lr_unresolved(1)),
  jsonb_build_object('appr', '{"ok": true, "state": "approved", "classification": "resolved", "recorded": false,
                               "amount_minor": 1234, "currency_code": "ILS", "provider_return_code": 0,
                               "resolution": "provider_voided"}'::jsonb,
                     'anom', '{"ok": true, "state": "approved", "classification": "resolved", "recorded": false,
                               "amount_minor": 1234, "currency_code": "ILS", "resolution": "provider_voided"}'::jsonb,
                     'unresolved', '{}'::jsonb),
  'LR-211 (C1-2) the operator resolves both orphans of the revoked d1 (provider_voided by the attested approver): each envelope approved / resolved / provider_voided (fo_anom carries no provider return code: its approval was the direct owner transition of LR-176), and d1 holds no unresolved attempt');
insert into public.sync_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
    operation_type, payload, payload_fingerprint, status)
  values (pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('device-1'),
          pg_temp.zc_lop('lr-backlog-3'), 'payment.create', '{}'::jsonb, 'zc001d-lr-fp-3', 'pending');
insert into _zc_r select 'sd_retire_pending', pg_temp.lr_retire_probe(1, 'lr-term-l4', 'lr-cred-l4');
update public.sync_operations set status = 'in_flight' where local_operation_id = pg_temp.zc_lop('lr-backlog-3');
insert into _zc_r select 'sd_retire_in_flight', pg_temp.lr_retire_probe(1, 'lr-term-l4', 'lr-cred-l4');
update public.sync_operations set status = 'rejected' where local_operation_id = pg_temp.zc_lop('lr-backlog-3');
select is(jsonb_build_object('pending', pg_temp.lr_r('sd_retire_pending'),
                             'in_flight', pg_temp.lr_r('sd_retire_in_flight')),
  jsonb_build_object('pending', jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'payment_create_pending'),
                                                   'wrote_nothing', true),
                     'in_flight', jsonb_build_object('result', pg_temp.lr_refusal('precondition_failed', 'payment_create_pending'),
                                                     'wrote_nothing', true)),
  'LR-212 (C1-2) with nothing unresolved, a pending and then an in-flight payment.create of the revoked d1 each block the retirement -> precondition_failed / payment_create_pending, nothing written');
select pg_temp.lr_snap();
insert into _zc_r select 'sd_retire_ok', pg_temp.lr_term(1, 'live', 'retired', 'lr-term-l4', 'lr-cred-l4', 'end_of_pilot');
insert into _zc_r select 'sd_retire_ok_events', pg_temp.lr_new_event_rows();
insert into _zc_r select 'sd_world_c0', pg_temp.lr_world();
insert into _zc_r select 'sd_create_revoked', pg_temp.lr_term(1, 'live', 'configured', 'lr-term-l6', 'lr-cred-l6',
                                                              'live_activation');
insert into _zc_r select 'sd_world_c1', pg_temp.lr_world();
select is(jsonb_build_object('retire', pg_temp.lr_r('sd_retire_ok'), 'events', pg_temp.lr_r('sd_retire_ok_events'),
                             'd1_current', (select count(*) from pg_temp.lr_current(1)),
                             'create_on_revoked', pg_temp.lr_r('sd_create_revoked'),
                             'create_wrote_nothing', pg_temp.lr_r('sd_world_c1') = pg_temp.lr_r('sd_world_c0')),
  jsonb_build_object('retire', pg_temp.lr_tres('live', 'draining', 'retired'),
                     'events', jsonb_build_array(pg_temp.lr_tev_row(1, 'live', 'draining', 'retired', false, 'end_of_pilot')),
                     'd1_current', 0, 'create_on_revoked', pg_temp.lr_refusal('invalid_request'),
                     'create_wrote_nothing', true),
  'LR-213 (C1-2) genuinely clear (both orphans resolved by the operator, the payment.create terminal), the revoked d1''s binding retires: ok {live, draining -> retired} and exactly one event {live, draining, retired, starts_admitted false, end_of_pilot} (attested approver, executor_principal = session_user); d1 has no current binding, and a creation (configured) on the revoked device answers invalid_request and writes nothing');
update public.devices set is_active = false where id = pg_temp.zc_id('device-2');
insert into _zc_r select 'sd_world_a0', pg_temp.lr_world();
insert into _zc_r select 'sd_r2_en_inactive', pg_temp.lr_term(2, 'live', 'enabled', 'lr-term-r2', 'lr-cred-r2',
                                                              'live_activation');
insert into _zc_r select 'sd_world_a1', pg_temp.lr_world();
update public.devices set is_active = true where id = pg_temp.zc_id('device-2');
select pg_temp.lr_snap();
insert into _zc_r select 'sd_r2_en_ok', pg_temp.lr_term(2, 'live', 'enabled', 'lr-term-r2', 'lr-cred-r2', 'live_activation');
insert into _zc_r select 'sd_r2_en_ok_events', pg_temp.lr_new_event_rows();
select is(jsonb_build_object('activate_inactive', pg_temp.lr_r('sd_r2_en_inactive'),
                             'wrote_nothing', pg_temp.lr_r('sd_world_a1') = pg_temp.lr_r('sd_world_a0'),
                             'activate_active', pg_temp.lr_r('sd_r2_en_ok'), 'events', pg_temp.lr_r('sd_r2_en_ok_events'),
                             'd2_binding', (select jsonb_build_array(t.mode, t.terminal_ref, t.lifecycle)
                                              from pg_temp.lr_current(2) t)),
  jsonb_build_object('activate_inactive', pg_temp.lr_refusal('invalid_request'), 'wrote_nothing', true,
                     'activate_active', pg_temp.lr_tres('live', 'configured', 'enabled'),
                     'events', jsonb_build_array(pg_temp.lr_tev_row(2, 'live', 'configured', 'enabled', true,
                                                                    'live_activation')),
                     'd2_binding', '["live", "lr-term-r2", "enabled"]'::jsonb),
  'LR-214 (C1-2) the replacement after the lawful retirement: activating d2''s configured binding while d2''s device record is inactive answers invalid_request (activation needs an active device) and writes nothing; once d2 is active the activation passes - ok {live, configured -> enabled}, exactly one event {live, configured, enabled, starts_admitted true, live_activation}');

-- 17.2 The retirement gate one unresolved attempt at a time, on a deleted d2 (deleted_at set, is_active true: an
-- approved attempt derives approved_unrecorded there, not device_revoked). Each LIVE attempt is inserted directly by
-- the owner for its own order (a drained binding admits no claim), driven to its state by the real finish or an order
-- void, refused at retirement while it is the device's only unresolved attempt, then settled by its real path.
select pg_temp.zc_order('lr-pk-' || l, 1234, 2) from unnest(array['sent', 'unk', 'rel', 'anom', 'appr']) l;
update public.devices set deleted_at = now() where id = pg_temp.zc_id('device-2');
select pg_temp.lr_snap();
insert into _zc_r select 'pk_drain', pg_temp.lr_term(2, 'live', 'draining', 'lr-term-r2', 'lr-cred-r2', 'incident');
insert into _zc_r select 'pk_drain_events', pg_temp.lr_new_event_rows();
select is(jsonb_build_object('result', pg_temp.lr_r('pk_drain'), 'events', pg_temp.lr_r('pk_drain_events'),
                             'd2_unresolved', pg_temp.lr_unresolved(2)),
  jsonb_build_object('result', pg_temp.lr_tres('live', 'enabled', 'draining'),
                     'events', jsonb_build_array(pg_temp.lr_tev_row(2, 'live', 'enabled', 'draining', false, 'incident')),
                     'd2_unresolved', '{}'::jsonb),
  'LR-215 (C1-2) d2 deleted (deleted_at set) with its LIVE binding enabled and nothing unresolved: the binding drains with exactly one event (attested approver, executor_principal = session_user)');
-- (a) sent
insert into _zc_r select 'pk_sent', pg_temp.lr_insert_live_attempt(2, 'lr-pk-sent', 'lr-term-r2', 'lr-cred-r2');
insert into _zc_r select 'pk_sent_probe', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'retire', pg_temp.lr_retire_probe(2, 'lr-term-r2', 'lr-cred-r2'));
set local role service_role;
insert into _zc_r select 'pk_sent_settle', pg_temp.zc_finish(pg_temp.lr_r('pk_sent'), 'commit', 'declined',
                                                             '{"approval_type": "declined"}'::jsonb);
reset role;
select is(pg_temp.lr_r('pk_sent_probe'),
  jsonb_build_object('unresolved', '{"pk_sent": ["live", "sent", "in_progress", null]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-216 (C1-2) the deleted d2''s only unresolved attempt is a sent LIVE attempt: retirement -> attempt_unresolved, nothing written (then settled: a commit declined)');
-- (b) unknown
insert into _zc_r select 'pk_unk', pg_temp.lr_insert_live_attempt(2, 'lr-pk-unk', 'lr-term-r2', 'lr-cred-r2');
set local role service_role;
insert into _zc_r select 'pk_unk_fin', pg_temp.zc_finish(pg_temp.lr_r('pk_unk'), 'commit', 'unknown');
reset role;
insert into _zc_r select 'pk_unk_probe', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'retire', pg_temp.lr_retire_probe(2, 'lr-term-r2', 'lr-cred-r2'));
set local role service_role;
insert into _zc_r select 'pk_unk_settle', pg_temp.zc_finish(pg_temp.lr_r('pk_unk'), 'lookup', 'declined',
                                                            '{"approval_type": "declined"}'::jsonb);
reset role;
select is(pg_temp.lr_r('pk_unk_probe'),
  jsonb_build_object('unresolved', '{"pk_unk": ["live", "unknown", "in_progress", null]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-217 (C1-2) the only unresolved attempt is an unknown LIVE attempt: retirement -> attempt_unresolved, nothing written (then settled: a lookup declined)');
-- (c) released
insert into _zc_r select 'pk_rel', pg_temp.lr_insert_live_attempt(2, 'lr-pk-rel', 'lr-term-r2', 'lr-cred-r2');
set local role service_role;
insert into _zc_r select 'pk_rel_fin', pg_temp.zc_finish(pg_temp.lr_r('pk_rel'), 'release', 'released');
reset role;
insert into _zc_r select 'pk_rel_probe', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'retire', pg_temp.lr_retire_probe(2, 'lr-term-r2', 'lr-cred-r2'));
set local role service_role;
insert into _zc_r select 'pk_rel_settle', pg_temp.zc_finish(pg_temp.lr_r('pk_rel'), 'lookup', 'declined',
                                                            '{"approval_type": "declined"}'::jsonb);
reset role;
select is(pg_temp.lr_r('pk_rel_probe'),
  jsonb_build_object('unresolved', '{"pk_rel": ["live", "released", "in_progress", null]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-218 (C1-2) the only unresolved attempt is a released LIVE attempt: retirement -> attempt_unresolved, nothing written (then settled: a lookup declined)');
-- (d) provider anomaly
insert into _zc_r select 'pk_anom', pg_temp.lr_insert_live_attempt(2, 'lr-pk-anom', 'lr-term-r2', 'lr-cred-r2');
set local role service_role;
insert into _zc_r select 'pk_anom_fin', pg_temp.zc_finish(pg_temp.lr_r('pk_anom'), 'commit', 'anomaly',
                                                          '{"anomaly_code": "refunded"}'::jsonb);
reset role;
insert into _zc_r select 'pk_anom_probe', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'retire', pg_temp.lr_retire_probe(2, 'lr-term-r2', 'lr-cred-r2'));
insert into _zc_r select 'pk_anom_settle', app.card_attempt_resolve_orphan(pg_temp.lr_aid('pk_anom'), 'provider_refunded',
  'lr-refund-ref-pk', 'ZC001D LR provider refund confirmed', 'zc001d-lr/pk-anom', pg_temp.zc_owner());
select is(pg_temp.lr_r('pk_anom_probe'),
  jsonb_build_object('unresolved', '{"pk_anom": ["live", "unknown", "provider_anomaly", null]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-219 (C1-2) the only unresolved attempt is a LIVE provider_anomaly (unknown, charge_may_exist): retirement -> attempt_unresolved, nothing written (then resolved by the operator: provider_refunded)');
-- (e) approved unrecorded, then (f) the same attempt orphaned by its order's void
insert into _zc_r select 'pk_appr', pg_temp.lr_insert_live_attempt(2, 'lr-pk-appr', 'lr-term-r2', 'lr-cred-r2');
set local role service_role;
insert into _zc_r select 'pk_appr_fin', pg_temp.zc_finish(pg_temp.lr_r('pk_appr'), 'commit', 'approved',
                                                          pg_temp.zc_approved_fields());
reset role;
insert into _zc_r select 'pk_appr_probe', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'retire', pg_temp.lr_retire_probe(2, 'lr-term-r2', 'lr-cred-r2'));
select pg_temp.lr_void(pg_temp.zc_id('order-lr-pk-appr'));
insert into _zc_r select 'pk_orphan_probe', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'retire', pg_temp.lr_retire_probe(2, 'lr-term-r2', 'lr-cred-r2'));
insert into _zc_r select 'pk_orphan_settle', app.card_attempt_resolve_orphan(pg_temp.lr_aid('pk_appr'), 'provider_voided',
  'lr-void-ref-pk', 'ZC001D LR provider void confirmed', 'zc001d-lr/pk-orphan', pg_temp.zc_owner());
select is(pg_temp.lr_r('pk_appr_probe'),
  jsonb_build_object('unresolved', '{"pk_appr": ["live", "approved", "approved_unrecorded", "pending_recording"]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-220 (C1-2) the only unresolved attempt is an approved, unrecorded LIVE attempt (pending_recording: the deleted device record is still active, its pairing and session live): retirement -> attempt_unresolved, nothing written');
select is(pg_temp.lr_r('pk_orphan_probe'),
  jsonb_build_object('unresolved', '{"pk_appr": ["live", "approved", "orphan_approved", "order_terminal"]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-221 (C1-2) once its order is voided the same attempt is the only unresolved one as an orphan (orphan_approved / order_terminal): retirement -> attempt_unresolved, nothing written (then resolved by the operator: provider_voided)');
-- (g) an unresolved TEST attempt of the device
insert into _zc_r select 'pk_test', jsonb_build_object('attempt_row_id', pg_temp.lr_insert_test_attempt(2, 'lr-pk-test'));
insert into _lr_names values (pg_temp.lr_aid('pk_test'), 'pk_test');
insert into _zc_r select 'pk_test_probe', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'retire', pg_temp.lr_retire_probe(2, 'lr-term-r2', 'lr-cred-r2'));
select pg_temp.lr_age_attempt(pg_temp.lr_aid('pk_test'), true, false);
insert into _zc_r select 'pk_test_settle', app.card_attempt_resolve_orphan(pg_temp.lr_aid('pk_test'), 'test_closed',
  'lr-test-ref-pk', 'ZC001D LR TEST run closed', 'zc001d-lr/pk-test', pg_temp.zc_owner());
select is(pg_temp.lr_r('pk_test_probe'),
  jsonb_build_object('unresolved', '{"pk_test": ["test", "sent", "test_sent", null]}'::jsonb,
                     'retire', pg_temp.lr_unresolved_refusal()),
  'LR-222 (C1-2) the only unresolved attempt is a TEST attempt of the device (sent): the LIVE binding''s retirement -> attempt_unresolved, nothing written (then test_closed past its start deadline)');
select pg_temp.lr_snap();
insert into _zc_r select 'pk_clear', jsonb_build_object('unresolved', pg_temp.lr_unresolved(2),
  'settled', jsonb_build_array(pg_temp.lr_r('pk_sent_settle') ->> 'state', pg_temp.lr_r('pk_unk_settle') ->> 'state',
                               pg_temp.lr_r('pk_rel_settle') ->> 'state', pg_temp.lr_r('pk_anom_settle') ->> 'resolution',
                               pg_temp.lr_r('pk_orphan_settle') ->> 'resolution',
                               pg_temp.lr_r('pk_test_settle') ->> 'resolution'));
insert into _zc_r select 'pk_retire_ok', pg_temp.lr_term(2, 'live', 'retired', 'lr-term-r2', 'lr-cred-r2', 'end_of_pilot');
insert into _zc_r select 'pk_retire_ok_events', pg_temp.lr_new_event_rows();
update public.devices set deleted_at = null where id = pg_temp.zc_id('device-2');
select is(jsonb_build_object('before', pg_temp.lr_r('pk_clear'), 'retire', pg_temp.lr_r('pk_retire_ok'),
                             'events', pg_temp.lr_r('pk_retire_ok_events'),
                             'admitting_bindings', (select count(*) from app.payment_terminals t
                                                     where t.organization_id = pg_temp.zc_org()
                                                       and t.lifecycle in ('enabled', 'draining'))),
  jsonb_build_object('before', '{"unresolved": {}, "settled": ["declined", "declined", "declined", "provider_refunded",
                                                              "provider_voided", "test_closed"]}'::jsonb,
                     'retire', pg_temp.lr_tres('live', 'draining', 'retired'),
                     'events', jsonb_build_array(pg_temp.lr_tev_row(2, 'live', 'draining', 'retired', false, 'end_of_pilot')),
                     'admitting_bindings', 0),
  'LR-223 (C1-2) genuinely clear (each attempt above settled by its real path - three provider declines, an operator refund, an operator void, a TEST closure - and no pending payment.create), the deleted d2''s binding retires with exactly one event; the organization holds no admitting binding');

-- retired from configured on an inactive device: a configured TEST binding of d2 (created while d2 is active) retires
-- once d2's device record is inactive.
insert into _zc_r select 'cr_cfg', pg_temp.lr_term(2, 'test', 'configured', 'lr-term-t2', 'lr-cred-t2', 'test_setup');
update public.devices set is_active = false where id = pg_temp.zc_id('device-2');
select pg_temp.lr_snap();
insert into _zc_r select 'cr_retire', pg_temp.lr_term(2, 'test', 'retired', 'lr-term-t2', 'lr-cred-t2', 'test_end');
insert into _zc_r select 'cr_retire_events', pg_temp.lr_new_event_rows();
update public.devices set is_active = true where id = pg_temp.zc_id('device-2');
select is(jsonb_build_object('create', pg_temp.lr_r('cr_cfg'), 'retire', pg_temp.lr_r('cr_retire'),
                             'events', pg_temp.lr_r('cr_retire_events'),
                             'd2_current', (select count(*) from pg_temp.lr_current(2))),
  jsonb_build_object('create', pg_temp.lr_tres('test', null, 'configured'),
                     'retire', pg_temp.lr_tres('test', 'configured', 'retired'),
                     'events', jsonb_build_array(pg_temp.lr_tev_row(2, 'test', 'configured', 'retired', false, 'test_end')),
                     'd2_current', 0),
  'LR-224 (C1-2) retired from configured on an inactive device: a configured TEST binding of d2 (created while d2 was active) retires once d2''s device record is inactive - ok {test, configured -> retired} and exactly one event (attested approver, executor_principal = session_user); d2 has no current binding');

-- =============================================================================
-- 18. Correction C1-3 (packet 11 item 26 as amended; D-059 point 3; API 4.55.10): the bounded-batch TEST purge.
--     p_max_devices outside 1..1000 is invalid_request (checked first); one batch locks at most p_max_devices
--     candidate devices in device-id order (d2 before d1), deletes only their eligible rows and reports what stays
--     eligible outside its set as deferred; held, unexpired, LIVE and operator rows and tombstones are never deleted;
--     a failure inside the purge rolls the whole batch back; a mode='test' event always names its device (CHECK
--     card_events_test_device). The TEST attempts are inserted directly by the owner (no TEST binding is current),
--     their events are the real finish's field drops and the real denial writer's attempt-less denials, and the
--     owner-only helpers age them.
-- =============================================================================
-- 18.1 The batch bound.
insert into _zc_r select 'bp_world0', pg_temp.lr_world();
insert into _zc_r select 'bp_bounds', jsonb_build_object(
  'zero', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge', 'zc001d-lr/bp-purge', pg_temp.zc_owner(), 0),
  'over', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge', 'zc001d-lr/bp-purge', pg_temp.zc_owner(),
                                               1001),
  'negative', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge', 'zc001d-lr/bp-purge',
                                                   pg_temp.zc_owner(), -1),
  'zero_non_attested_actor', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge', 'zc001d-lr/bp-purge',
                                                                  pg_temp.zc_id('user-2'), 0),
  'over_absent_reference', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge', null, pg_temp.zc_owner(),
                                                                1001),
  'zero_null_reason', app.purge_expired_test_card_attempts(null, 'zc001d-lr/bp-purge', pg_temp.zc_owner(), 0));
insert into _zc_r select 'bp_world1', pg_temp.lr_world();
select is(jsonb_build_object('results', pg_temp.lr_r('bp_bounds'),
                             'wrote_nothing', pg_temp.lr_r('bp_world1') = pg_temp.lr_r('bp_world0')),
  jsonb_build_object('results', jsonb_build_object('zero', pg_temp.lr_refusal('invalid_request'),
                                                   'over', pg_temp.lr_refusal('invalid_request'),
                                                   'negative', pg_temp.lr_refusal('invalid_request'),
                                                   'zero_non_attested_actor', pg_temp.lr_refusal('invalid_request'),
                                                   'over_absent_reference', pg_temp.lr_refusal('invalid_request'),
                                                   'zero_null_reason', pg_temp.lr_refusal('invalid_request')),
                     'wrote_nothing', true),
  'LR-225 (C1-3) p_max_devices 0, 1001 or -1 -> exactly {ok:false, error:invalid_request}, checked first: also beside a non-attested actor (staff 2), an absent operator reference or a NULL reason (otherwise permission_denied / out_of_contract); nothing written - no delete, no tombstone, no event');

-- 18.2 Eventual coverage with an incident hold below the eligible device: section 7's pa2 (expired, held, on d2 - the
-- lower device id) still has its expired TEST event, which carries no hold of its own; sv_d1 (an expired, unheld TEST
-- attempt) waits on d1.
insert into _zc_r select 'sv_d1', jsonb_build_object('attempt_row_id', pg_temp.lr_insert_test_attempt(1, 'lr-sv-d1'));
select pg_temp.lr_age_attempt(pg_temp.lr_aid('sv_d1'), false, true);
create function pg_temp.lr_sv_state() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'sv_d1_present', exists (select 1 from app.card_provider_attempts a where a.id = pg_temp.lr_aid('sv_d1')),
    'sv_d1_tombstoned', exists (select 1 from app.card_attempt_identity_tombstones t
                                 where t.organization_id = pg_temp.zc_org() and t.device_id = pg_temp.zc_id('device-1')
                                   and t.local_operation_id = pg_temp.zc_lop('lr-sv-d1')),
    'pa2_present', exists (select 1 from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_pa2')),
    'pa2_event_present', exists (select 1 from app.card_provider_private_events e
                                  where e.id = (pg_temp.lr_r('ev_pa2') ->> 'id')::uuid));
$$;
select is(jsonb_build_object(
    'sv_d1', (select jsonb_build_array(a.mode, a.retention_until <= clock_timestamp(), a.incident_hold_at is not null)
                from app.card_provider_attempts a where a.id = pg_temp.lr_aid('sv_d1')),
    'pa2', (select jsonb_build_array(a.mode, a.retention_until <= clock_timestamp(), a.incident_hold_at is not null)
              from app.card_provider_attempts a where a.id = pg_temp.lr_aid('claim_pa2')),
    'pa2_event', (select jsonb_build_array(e.mode, e.retention_until <= clock_timestamp(), e.incident_hold_at is not null)
                    from app.card_provider_private_events e where e.id = (pg_temp.lr_r('ev_pa2') ->> 'id')::uuid)),
  '{"sv_d1": ["test", true, false], "pa2": ["test", true, true], "pa2_event": ["test", true, false]}'::jsonb,
  'LR-226 (C1-3) setup: sv_d1 on d1 is an expired, unheld TEST attempt (eligible); on d2 - the lower device id - the expired TEST attempt pa2 is held and its expired event carries no hold of its own (never eligible while pa2 is held)');
insert into _zc_r select 'sv_purge_1', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/sv-purge-1', pg_temp.zc_owner(), 1);
insert into _zc_r select 'sv_purge_2', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/sv-purge-2', pg_temp.zc_owner(), 1);
select is(pg_temp.lr_sv_state(),
  '{"sv_d1_present": false, "sv_d1_tombstoned": true, "pa2_present": true, "pa2_event_present": true}'::jsonb,
  'LR-227 (C1-3, eventual coverage) two batches bounded to one device purge sv_d1 (what stays eligible outside a batch''s set waits for a later batch, never longer): sv_d1 deleted and tombstoned, the held pa2 and its event kept');
insert into _zc_r select 'sv_purge_3', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/sv-purge-3', pg_temp.zc_owner());
select is(pg_temp.lr_sv_state(),
  '{"sv_d1_present": false, "sv_d1_tombstoned": true, "pa2_present": true, "pa2_event_present": true}'::jsonb,
  'LR-228 (C1-3) contrast: after an unbounded batch (p_max_devices NULL) sv_d1 is deleted and tombstoned and the held pa2 and its event are kept - sv_d1 was eligible throughout');

-- 18.3 Two device scopes. pa2's hold is cleared (it becomes eligible with its event). On d2: cv_d2 finished unknown
-- (one field-drop event), an attempt-less denial, and a denial carrying its own hold. On d1: cv_d1 finished twice
-- (two field-drop events, the second left unexpired), an attempt-less denial, an unexpired denial, and cv_hold, an
-- expired TEST attempt carrying an attempt hold (no event).
insert into _zc_r select 'cv_unhold_pa2', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('claim_pa2'), false,
  null, 'ZC001D LR incident closed', 'zc001d-lr/hold-p2', pg_temp.zc_owner());
insert into _zc_r select 'cv_' || v.l, jsonb_build_object(
    'attempt_row_id', pg_temp.lr_insert_test_attempt(v.d, 'lr-cv-' || v.l), 'organization_id', pg_temp.zc_org(),
    'device_id', pg_temp.zc_id('device-' || v.d), 'local_operation_id', pg_temp.zc_lop('lr-cv-' || v.l),
    'mode', 'test', 'amount_minor', 500, 'currency_code', 'ILS')
  from (values ('d2', 2), ('d1', 1), ('hold', 1)) v(l, d);
set local role service_role;
insert into _zc_r select 'cv_fin_' || v.l, pg_temp.zc_finish(pg_temp.lr_r('cv_' || v.a), v.src, v.outcome, v.f::jsonb)
  from (values ('d2', 'd2', 'commit', 'unknown', '{"provider_saved_at": "not-a-timestamp"}'),
               ('d1a', 'd1', 'commit', 'unknown', '{"provider_saved_at": "not-a-timestamp"}'),
               ('d1b', 'd1', 'lookup', 'not_found', '{"provider_return_code": "x1"}')) v(l, a, src, outcome, f);
reset role;
insert into _zc_r select 'cv_ev_' || v.l, (select to_jsonb(e) from app.card_provider_private_events e
   where e.attempt_row_id = pg_temp.lr_aid('cv_' || v.a) and e.action = 'security.card_provider_field_dropped'
     and e.detail ->> 'field' = v.field)
  from (values ('d2', 'd2', 'provider_saved_at'), ('d1a', 'd1', 'provider_saved_at'),
               ('d1b', 'd1', 'provider_return_code')) v(l, a, field);
-- The attempt-less TEST denials, through the real denial writer (one call each; the employee and device of the till).
create function pg_temp.lr_cv_denial(p_d integer) returns jsonb language plpgsql volatile as $$
declare
  v jsonb;
begin
  perform pg_temp.lr_snap();
  perform app.card_denial_evidence('test', pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(),
    pg_temp.zc_id('employee-' || case p_d when 2 then 8 else 1 end), pg_temp.zc_id('device-' || p_d), null, 'claim',
    'max_test_amount_exceeded');
  select to_jsonb(e) into strict v from pg_temp.lr_new_events() e;
  return v;
end $$;
insert into _zc_r select 'cv_deny_d2', pg_temp.lr_cv_denial(2);
insert into _zc_r select 'cv_deny_hold', pg_temp.lr_cv_denial(2);
insert into _zc_r select 'cv_deny_d1', pg_temp.lr_cv_denial(1);
insert into _zc_r select 'cv_deny_fresh', pg_temp.lr_cv_denial(1);
insert into _zc_r select 'cv_hold_attempt', app.card_attempt_set_incident_hold('attempt', pg_temp.lr_aid('cv_hold'), true,
  'lr-hold-ref-cv', 'ZC001D LR keep the evidence', 'zc001d-lr/hold-cv', pg_temp.zc_owner());
insert into _zc_r select 'cv_hold_event', app.card_attempt_set_incident_hold('event',
  (pg_temp.lr_r('cv_deny_hold') ->> 'id')::uuid, true, 'lr-hold-ref-cve', 'ZC001D LR keep the evidence',
  'zc001d-lr/hold-cve', pg_temp.zc_owner());
select pg_temp.lr_age_attempt(pg_temp.lr_aid('cv_' || l), false, true) from unnest(array['d2', 'd1', 'hold']) l;
select pg_temp.lr_age_event((pg_temp.lr_r(l) ->> 'id')::uuid)
  from unnest(array['cv_ev_d2', 'cv_deny_d2', 'cv_deny_hold', 'cv_ev_d1a', 'cv_deny_d1']) l;
-- Presence of every row of this setup (and of pa1's own-held event of section 7), and the tombstoned identities.
create function pg_temp.lr_cv_presence() returns jsonb language sql stable as $$
  select jsonb_build_object(
    'attempts', (select jsonb_object_agg(l, exists (select 1 from app.card_provider_attempts a
                                                     where a.id = pg_temp.lr_aid(l)))
                   from unnest(array['cv_d2', 'claim_pa2', 'cv_d1', 'cv_hold']) l),
    'events', (select jsonb_object_agg(l, exists (select 1 from app.card_provider_private_events e
                                                   where e.id = (pg_temp.lr_r(l) ->> 'id')::uuid))
                 from unnest(array['cv_ev_d2', 'cv_deny_d2', 'cv_deny_hold', 'ev_pa2', 'cv_ev_d1a', 'cv_ev_d1b',
                                   'cv_deny_d1', 'cv_deny_fresh', 'ev_pa1_own']) l),
    'tombstoned', (select coalesce(jsonb_agg(x.l order by x.l), '[]'::jsonb)
                     from (values ('cv_d1', 'lr-cv-d1', 1), ('cv_d2', 'lr-cv-d2', 2), ('cv_hold', 'lr-cv-hold', 1),
                                  ('pa2', 'lr-pa2', 2)) x(l, lop, d)
                    where exists (select 1 from app.card_attempt_identity_tombstones t
                                   where t.organization_id = pg_temp.zc_org()
                                     and t.device_id = pg_temp.zc_id('device-' || x.d)
                                     and t.local_operation_id = pg_temp.zc_lop(x.lop))));
$$;
select results_eq(
  $$ select u.l, dv.d, a.state, a.retention_until <= clock_timestamp(), a.incident_hold_at is not null
       from unnest(array['cv_d2', 'claim_pa2', 'cv_d1', 'cv_hold']) with ordinality u(l, n)
       join app.card_provider_attempts a on a.id = pg_temp.lr_aid(u.l)
       join (select g.d, pg_temp.zc_id('device-' || g.d) as id from generate_series(1, 5) g(d)) dv on dv.id = a.device_id
      order by u.n $$,
  $$ values ('cv_d2'::text, 2, 'unknown'::text, true, false), ('claim_pa2', 2, 'unknown', true, false),
            ('cv_d1', 1, 'unknown', true, false), ('cv_hold', 1, 'sent', true, true) $$,
  'LR-229 (C1-3) setup: TEST attempts - on d2 cv_d2 and pa2 (its hold cleared) expired and unheld; on d1 cv_d1 expired and unheld, cv_hold expired with an active attempt hold');
select results_eq(
  $$ select u.l, dv.d, e.action, e.attempt_row_id is not null, e.retention_until <= clock_timestamp(),
            e.incident_hold_at is not null
       from unnest(array['cv_ev_d2', 'cv_deny_d2', 'cv_deny_hold', 'ev_pa2', 'cv_ev_d1a', 'cv_ev_d1b', 'cv_deny_d1',
                         'cv_deny_fresh', 'ev_pa1_own']) with ordinality u(l, n)
       join app.card_provider_private_events e on e.id = (pg_temp.lr_r(u.l) ->> 'id')::uuid
       join (select g.d, pg_temp.zc_id('device-' || g.d) as id from generate_series(1, 5) g(d)) dv on dv.id = e.device_id
      order by u.n $$,
  $$ values ('cv_ev_d2'::text, 2, 'security.card_provider_field_dropped'::text, true, true, false),
            ('cv_deny_d2', 2, 'test.card_attempt_denied', false, true, false),
            ('cv_deny_hold', 2, 'test.card_attempt_denied', false, true, true),
            ('ev_pa2', 2, 'security.card_provider_field_dropped', true, true, false),
            ('cv_ev_d1a', 1, 'security.card_provider_field_dropped', true, true, false),
            ('cv_ev_d1b', 1, 'security.card_provider_field_dropped', true, false, false),
            ('cv_deny_d1', 1, 'test.card_attempt_denied', false, true, false),
            ('cv_deny_fresh', 1, 'test.card_attempt_denied', false, false, false),
            ('ev_pa1_own', 2, 'security.card_provider_field_dropped', true, true, true) $$,
  'LR-230 (C1-3) setup: TEST events - on d2 cv_d2''s (expired), an attempt-less denial (expired), a denial with an active hold of its own (expired), pa2''s (expired) and pa1''s own-held one; on d1 cv_d1''s two (one expired, one unexpired), an attempt-less denial (expired) and an unexpired denial');
select is(pg_temp.lr_cp_purge_devices(), '[2, 1]'::jsonb,
  'LR-231 (C1-3) setup: the candidate devices in device-id order are d2 and d1');
-- Rows a purge never deletes: every LIVE attempt, every LIVE / operator event, every tombstone.
create temp table _lr_keep as
  select 'live_attempt'::text as kind, a.id::text as k from app.card_provider_attempts a where a.mode = 'live'
  union all
  select 'live_or_operator_event', e.id::text from app.card_provider_private_events e where e.mode is distinct from 'test'
  union all
  select 'tombstone', t.organization_id::text || '/' || t.device_id::text || '/' || t.local_operation_id
    from app.card_attempt_identity_tombstones t;
-- 18.4 A failure forced inside the purge: a test-only trigger refuses the purge's closing private event (its last
-- write, after every delete); the call aborts and the whole batch rolls back.
insert into _zc_r select 'cv_world_0', pg_temp.lr_world();
create function pg_temp.lr_fail_purge_event() returns trigger language plpgsql as $$
begin
  if new.action = 'operator.card_test_attempts_purged' then
    raise exception 'lr forced purge failure' using errcode = 'ZC001';
  end if;
  return new;
end $$;
create trigger lr_zc001d_forced_purge_failure before insert on app.card_provider_private_events
  for each row execute function pg_temp.lr_fail_purge_event();
select throws_ok($$ select app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge', 'zc001d-lr/cv-purge-fail',
                                                               pg_temp.zc_owner()) $$,
  'ZC001', 'lr forced purge failure',
  'LR-232 (C1-3) a failure forced at the purge''s last write (a test-only trigger refusing its closing operator.card_test_attempts_purged event, after every delete of an unbounded batch over d2 and d1) aborts the call with that error');
drop trigger lr_zc001d_forced_purge_failure on app.card_provider_private_events;
select is(pg_temp.lr_world(), pg_temp.lr_r('cv_world_0'),
  'LR-233 (C1-3) ... and rolls the whole batch back: attempt, private-event, tombstone, binding, revision and tenant-audit rows identical (counts and content digests) - nothing purged, nothing tombstoned, no purge event');
-- 18.5 The batches, bounded to one device.
insert into _zc_r select 'cv_pre', pg_temp.lr_purge_counts();
select pg_temp.lr_snap();
insert into _zc_r select 'cv_purge_1', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/cv-purge-1', pg_temp.zc_owner(), 1);
insert into _zc_r select 'cv_purge_1_events', pg_temp.lr_new_event_rows();
insert into _zc_r select 'cv_presence_1', pg_temp.lr_cv_presence();
select pg_temp.lr_snap();
insert into _zc_r select 'cv_purge_2', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/cv-purge-2', pg_temp.zc_owner(), 1);
insert into _zc_r select 'cv_purge_2_events', pg_temp.lr_new_event_rows();
insert into _zc_r select 'cv_presence_2', pg_temp.lr_cv_presence();
insert into _zc_r select 'cv_purge_3', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/cv-purge-3', pg_temp.zc_owner(), 1000);
select is(jsonb_build_object('result', pg_temp.lr_r('cv_purge_1') - 'cutoff', 'events', pg_temp.lr_r('cv_purge_1_events')),
  jsonb_build_object('result', '{"ok": true, "attempts_purged": 2, "events_purged": 3, "attempts_deferred": 1,
                                 "events_deferred": 2, "devices_locked": 1}'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempts_purged',
                       'actor_kind', 'attested_owner_approver', 'actor_reference', 'zc001d-lr/cv-purge-1',
                       'actor_app_user_id', pg_temp.zc_owner(), 'executor_principal', pg_temp.lr_exec(),
                       'device_id', null, 'attempt_row_id', null, 'mode', null, 'retention_until', null,
                       'reason', 'ZC001D LR TEST evidence purge',
                       'detail', jsonb_build_object('attempts_purged', 2, 'events_purged', 3, 'attempts_deferred', 1,
                                                    'events_deferred', 2, 'devices_locked', 1,
                                                    'cutoff', pg_temp.lr_r('cv_purge_1') -> 'cutoff')))),
  'LR-234 (C1-3) batch 1 (p_max_devices 1) locks only the lower device id d2: ok with exactly 2 attempts (cv_d2, pa2) and 3 events (cv_d2''s, the attempt-less denial, pa2''s) purged, 1 attempt (cv_d1) and 2 events (cv_d1''s expired one, d1''s attempt-less denial) deferred, 1 device locked; exactly one operator.card_test_attempts_purged with that detail (attested approver, executor_principal = session_user, mode NULL)');
select is(pg_temp.lr_r('cv_presence_1'),
  '{"attempts": {"cv_d2": false, "claim_pa2": false, "cv_d1": true, "cv_hold": true},
    "events": {"cv_ev_d2": false, "cv_deny_d2": false, "cv_deny_hold": true, "ev_pa2": false, "cv_ev_d1a": true,
               "cv_ev_d1b": true, "cv_deny_d1": true, "cv_deny_fresh": true, "ev_pa1_own": true},
    "tombstoned": ["cv_d2", "pa2"]}'::jsonb,
  'LR-235 (C1-3) after batch 1: d2''s eligible rows are gone (cv_d2 and pa2 tombstoned, their events and the attempt-less denial with them) while d2''s own-held denial stays; every d1 row waits untouched');
select is(jsonb_build_object('result', pg_temp.lr_r('cv_purge_2') - 'cutoff', 'events', pg_temp.lr_r('cv_purge_2_events')),
  jsonb_build_object('result', '{"ok": true, "attempts_purged": 1, "events_purged": 2, "attempts_deferred": 0,
                                 "events_deferred": 0, "devices_locked": 1}'::jsonb,
                     'events', jsonb_build_array(jsonb_build_object('action', 'operator.card_test_attempts_purged',
                       'actor_kind', 'attested_owner_approver', 'actor_reference', 'zc001d-lr/cv-purge-2',
                       'actor_app_user_id', pg_temp.zc_owner(), 'executor_principal', pg_temp.lr_exec(),
                       'device_id', null, 'attempt_row_id', null, 'mode', null, 'retention_until', null,
                       'reason', 'ZC001D LR TEST evidence purge',
                       'detail', jsonb_build_object('attempts_purged', 1, 'events_purged', 2, 'attempts_deferred', 0,
                                                    'events_deferred', 0, 'devices_locked', 1,
                                                    'cutoff', pg_temp.lr_r('cv_purge_2') -> 'cutoff')))),
  'LR-236 (C1-3) batch 2 (p_max_devices 1) reaches the other device (eventual coverage): ok with exactly 1 attempt (cv_d1) and 2 events (cv_d1''s expired one, d1''s attempt-less denial) purged, nothing deferred, 1 device locked; its single purge event carries the same counts');
select is(pg_temp.lr_r('cv_presence_2'),
  '{"attempts": {"cv_d2": false, "claim_pa2": false, "cv_d1": false, "cv_hold": true},
    "events": {"cv_ev_d2": false, "cv_deny_d2": false, "cv_deny_hold": true, "ev_pa2": false, "cv_ev_d1a": false,
               "cv_ev_d1b": true, "cv_deny_d1": false, "cv_deny_fresh": true, "ev_pa1_own": true},
    "tombstoned": ["cv_d1", "cv_d2", "pa2"]}'::jsonb,
  'LR-237 (C1-3) after batch 2: cv_d1 is tombstoned; the attempt with an active hold (cv_hold, never tombstoned), the events with an active hold of their own (d2''s denial, pa1''s), the unexpired event of the purged cv_d1 and the unexpired denial all survive');
select is(pg_temp.lr_r('cv_purge_3') - 'cutoff',
  '{"ok": true, "attempts_purged": 0, "events_purged": 0, "attempts_deferred": 0, "events_deferred": 0,
    "devices_locked": 0}'::jsonb,
  'LR-238 (C1-3) batch 3 (p_max_devices 1000, the upper bound, accepted) finds no candidate device: nothing purged, nothing deferred, no device locked');
select is(jsonb_build_object(
    'kept_rows_missing', (select count(*) from _lr_keep k
                           where not exists (select 1 from app.card_provider_attempts a
                                              where k.kind = 'live_attempt' and a.id::text = k.k)
                             and not exists (select 1 from app.card_provider_private_events e
                                              where k.kind = 'live_or_operator_event' and e.id::text = k.k)
                             and not exists (select 1 from app.card_attempt_identity_tombstones t
                                              where k.kind = 'tombstone'
                                                and t.organization_id::text || '/' || t.device_id::text || '/'
                                                    || t.local_operation_id = k.k)),
    'kept_rows', (select count(*) > 0 from _lr_keep),
    'counts', pg_temp.lr_purge_counts(),
    'holds', jsonb_build_array(
      (select a.incident_hold_at is not null from app.card_provider_attempts a where a.id = pg_temp.lr_aid('cv_hold')),
      (select e.incident_hold_at is not null from app.card_provider_private_events e
        where e.id = (pg_temp.lr_r('cv_deny_hold') ->> 'id')::uuid))),
  jsonb_build_object('kept_rows_missing', 0, 'kept_rows', true,
    'counts', pg_temp.lr_r('cv_pre') || jsonb_build_object(
      'test_attempts', (pg_temp.lr_r('cv_pre') ->> 'test_attempts')::int - 3,
      'test_events', (pg_temp.lr_r('cv_pre') ->> 'test_events')::int - 5,
      'operator_events', (pg_temp.lr_r('cv_pre') ->> 'operator_events')::int + 3,
      'tombstones', (pg_temp.lr_r('cv_pre') ->> 'tombstones')::int + 3),
    'holds', '[true, true]'::jsonb),
  'LR-239 (C1-3) across the three batches every LIVE attempt, every LIVE / operator event and every tombstone present before them is still there; TEST attempts - 3, TEST events - 5, operator events + 3 (one per batch), tombstones + 3, LIVE attempts and LIVE events unchanged, both holds still set');
-- 18.6 The lock set, observed in pg_locks. A batch takes the terminal lock of exactly its selected devices (the
-- transaction-level advisory lock on hashtextextended('card-terminal/v1:<org>:<device>', 0), held until this file's
-- ROLLBACK). Observed on d3 (the pilot KDS) and d5 (the sibling-branch POS), whose terminal locks this transaction never
-- took before - each gets one synthetic expired TEST attempt inserted directly by the owner, used only to observe the
-- purge's lock set (the purge selects by TEST row, not by device type or branch). Device-id order: d3 before d5.
create function pg_temp.lr_terminal_lock_held(p_d integer) returns boolean language sql volatile as $$
  select exists (select 1 from pg_locks l
                  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted
                    and l.database = (select d.oid from pg_database d where d.datname = current_database())
                    and l.classid::bigint = (k.k >> 32) & 4294967295 and l.objid::bigint = k.k & 4294967295
                    and l.objsubid = 1)
    from (select hashtextextended('card-terminal/v1:' || dv.organization_id::text || ':' || dv.id::text, 0) as k
            from public.devices dv where dv.id = pg_temp.zc_id('device-' || p_d)) k;
$$;
create function pg_temp.lr_ls_state() returns jsonb language sql volatile as $$
  select jsonb_build_object(
    'locks', jsonb_build_object('d3', pg_temp.lr_terminal_lock_held(3), 'd5', pg_temp.lr_terminal_lock_held(5)),
    'present', jsonb_build_object(
      'd3', exists (select 1 from app.card_provider_attempts a where a.id = pg_temp.lr_aid('ls_d3')),
      'd5', exists (select 1 from app.card_provider_attempts a where a.id = pg_temp.lr_aid('ls_d5'))));
$$;
insert into _zc_r select 'ls_' || v.l, jsonb_build_object('attempt_row_id', pg_temp.lr_insert_test_attempt(v.d, 'lr-ls-' || v.l))
  from (values ('d3', 3), ('d5', 5)) v(l, d);
select pg_temp.lr_age_attempt(pg_temp.lr_aid('ls_' || l), false, true) from unnest(array['d3', 'd5']) l;
insert into _zc_r select 'ls_before', pg_temp.lr_ls_state();
insert into _zc_r select 'ls_candidates', pg_temp.lr_cp_purge_devices();
insert into _zc_r select 'ls_purge_1', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/ls-purge-1', pg_temp.zc_owner(), 1);
insert into _zc_r select 'ls_after_1', pg_temp.lr_ls_state();
insert into _zc_r select 'ls_purge_2', app.purge_expired_test_card_attempts('ZC001D LR TEST evidence purge',
  'zc001d-lr/ls-purge-2', pg_temp.zc_owner(), 1);
insert into _zc_r select 'ls_after_2', pg_temp.lr_ls_state();
select is(jsonb_build_object('candidates', pg_temp.lr_r('ls_candidates'), 'before', pg_temp.lr_r('ls_before'),
                             'batch_1', pg_temp.lr_r('ls_purge_1') - 'cutoff', 'after_1', pg_temp.lr_r('ls_after_1')),
  '{"candidates": [3, 5],
    "before": {"locks": {"d3": false, "d5": false}, "present": {"d3": true, "d5": true}},
    "batch_1": {"ok": true, "attempts_purged": 1, "events_purged": 0, "attempts_deferred": 1, "events_deferred": 0,
                "devices_locked": 1},
    "after_1": {"locks": {"d3": true, "d5": false}, "present": {"d3": false, "d5": true}}}'::jsonb,
  'LR-240 (C1-3) the lock set: with expired TEST attempts on d3 and d5 only (no terminal lock of either held before), a batch bounded to one device takes the terminal lock of d3 - the lower device id - and not of d5, purges d3''s attempt and defers d5''s (1 / 1, one device locked)');
select is(jsonb_build_object('batch_2', pg_temp.lr_r('ls_purge_2') - 'cutoff', 'after_2', pg_temp.lr_r('ls_after_2')),
  '{"batch_2": {"ok": true, "attempts_purged": 1, "events_purged": 0, "attempts_deferred": 0, "events_deferred": 0,
                "devices_locked": 1},
    "after_2": {"locks": {"d3": true, "d5": true}, "present": {"d3": false, "d5": false}}}'::jsonb,
  'LR-241 (C1-3) ... the next bounded batch takes the terminal lock of d5 and purges its attempt (eventual coverage; nothing deferred)');
-- 18.7 Every TEST event names its device (CHECK card_events_test_device).
select throws_ok(format($f$insert into app.card_provider_private_events (organization_id, restaurant_id, branch_id, mode,
    action, actor_kind, actor_reference, detail, retention_until)
  values (%L, %L, %L, 'test', 'test.card_attempt_denied', 'device', 'device',
          '{"rpc": "claim", "denied_reason": "max_test_amount_exceeded"}', now() + interval '90 days')$f$,
    pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch()),
  '23514', 'new row for relation "card_provider_private_events" violates check constraint "card_events_test_device"',
  'LR-242 (C1-3) a mode=test event without a device is refused by the CHECK card_events_test_device (23514): a direct owner INSERT of an attempt-less test.card_attempt_denied with device_id NULL');
select throws_ok(format($f$select app.card_denial_evidence('test', %L, %L, %L, %L, null, null, 'claim',
                                                          'max_test_amount_exceeded')$f$,
    pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), pg_temp.zc_id('employee-8')),
  '23514', 'new row for relation "card_provider_private_events" violates check constraint "card_events_test_device"',
  'LR-243 (C1-3) ... the same 23514 through the internal denial writer (app.card_denial_evidence for a TEST denial with no device)');
select is((select count(*) from app.card_provider_private_events e where e.mode = 'test' and e.device_id is null),
  0::bigint,
  'LR-244 (C1-3) no mode=test event without a device exists in the store (so no TEST event is outside every device lock)');

select * from finish();
rollback;
