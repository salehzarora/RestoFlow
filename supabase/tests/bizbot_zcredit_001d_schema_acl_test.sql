-- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: schema / ACL / N28 catalog lane (T-023; DEPLOYMENT 18.2 POST). Rollback-only synthetic fixtures, real SQL roles.
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
-- SA lane: the catalog half of T-023 and the DEPLOYMENT 18.2 POST list
-- (tables, RLS, privileges, the family EXECUTE matrix of packet 3.2, function
-- attributes, the REPORT-123 guard, the re-created functions, N28, keys,
-- indexes and triggers), plus runtime privilege probes run AS the real anon /
-- authenticated / service_role roles. Every probe call is undone inside its
-- own sub-transaction and the whole file rolls back.
-- ===========================================================================

-- The five private tables (DOMAIN_MODEL 8.4-8.7).
create temp table _sa_tables (t text primary key);
insert into _sa_tables values ('card_attempt_identity_tombstones'), ('card_payments_pilot_revisions'),
  ('card_provider_attempts'), ('card_provider_private_events'), ('payment_terminals');

-- The expected family matrix: every function the 001D migration creates, with
-- the EXECUTE grant packet 3.2 fixes for anon (x_anon), authenticated (x_auth)
-- and service_role (x_svc). caller = caller-authority pair (authenticated on
-- both layers); service = service-only set (service_role on both layers);
-- guard / operator / lock / helper / trigger = granted to none of the three.
create temp table _sa_fn (
  ord      integer primary key,
  nsp      text not null,
  name     text not null,
  args     text not null,
  family   text not null,
  x_anon   boolean not null,
  x_auth   boolean not null,
  x_svc    boolean not null,
  sig      text,
  fn       oid,
  call_sql text
);
insert into _sa_fn (ord, nsp, name, args, family, x_anon, x_auth, x_svc) values
  ( 1, 'app',    'card_attempt_context',                'uuid,uuid,text,uuid,text',                     'caller',   false, true,  false),
  ( 2, 'public', 'card_attempt_context',                'uuid,uuid,text,uuid,text',                     'caller',   false, true,  false),
  ( 3, 'app',    'owner_card_attempts',                 'uuid,uuid,uuid,timestamptz,timestamptz,text',  'caller',   false, true,  false),
  ( 4, 'public', 'owner_card_attempts',                 'uuid,uuid,uuid,timestamptz,timestamptz,text',  'caller',   false, true,  false),
  -- C2 (D-060 point 2): the five session-proving service-only pairs (rows 5-8 and 11-16) carry the final
  -- required parameter p_caller_auth_user_id uuid on both layers (no default, no overload); finish is unchanged.
  ( 5, 'app',    'card_attempt_claim',
       'uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid',                    'service',  false, false, true),
  ( 6, 'public', 'card_attempt_claim',
       'uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid',                    'service',  false, false, true),
  ( 7, 'app',    'card_attempt_adapter_read',           'uuid,uuid,text,text,text,jsonb,jsonb,uuid',    'service',  false, false, true),
  ( 8, 'public', 'card_attempt_adapter_read',           'uuid,uuid,text,text,text,jsonb,jsonb,uuid',    'service',  false, false, true),
  ( 9, 'app',    'card_attempt_finish',        'uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text', 'service',  false, false, true),
  (10, 'public', 'card_attempt_finish',        'uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text', 'service',  false, false, true),
  (11, 'app',    'card_attempt_mark_release_requested', 'uuid,uuid,text,text,uuid',                     'service',  false, false, true),
  (12, 'public', 'card_attempt_mark_release_requested', 'uuid,uuid,text,text,uuid',                     'service',  false, false, true),
  (13, 'app',    'card_attempt_mark_recording_result',  'uuid,uuid,text,text,text,uuid',                'service',  false, false, true),
  (14, 'public', 'card_attempt_mark_recording_result',  'uuid,uuid,text,text,text,uuid',                'service',  false, false, true),
  (15, 'app',    'card_attempt_free_order',             'uuid,uuid,text,text,text,text,text,uuid',      'service',  false, false, true),
  (16, 'public', 'card_attempt_free_order',             'uuid,uuid,text,text,text,text,text,uuid',      'service',  false, false, true),
  (17, 'app',    'card_claim_guard',                    'uuid,uuid,uuid,text,text,text,uuid',           'guard',    false, false, false),
  (18, 'app',    'card_recording_resume_guard',  'uuid,uuid,uuid,integer,text,uuid,timestamptz,jsonb',  'guard',    false, false, false),
  (19, 'app',    'set_card_payments_pilot',     'boolean,text,timestamptz,bigint,bigint,text,text,uuid', 'operator', false, false, false),
  (20, 'app',    'set_payment_terminal',               'uuid,text,text,text,text,text,text,text,uuid',  'operator', false, false, false),
  (21, 'app',    'card_attempt_resolve_orphan',         'uuid,text,text,text,text,uuid',                'operator', false, false, false),
  (22, 'app',    'card_attempt_set_incident_hold',      'text,uuid,boolean,text,text,text,uuid',        'operator', false, false, false),
  -- C1-3 (D-059 point 3): the purge gained p_max_devices integer DEFAULT NULL, replaced in place (no function added).
  (23, 'app',    'purge_expired_test_card_attempts',    'text,text,uuid,integer',                       'operator', false, false, false),
  (24, 'app',    'card_identity_lock',                  'uuid,uuid,text',                               'lock',     false, false, false),
  (25, 'app',    'card_terminal_lock',                  'uuid,uuid',                                    'lock',     false, false, false),
  (26, 'app',    'card_safe_text_ok',                   'text,text',                                    'helper',   false, false, false),
  (27, 'app',    'card_safe_text_failure',              'text,text',                                    'helper',   false, false, false),
  (28, 'app',    'card_text_canonical',                 'text',                                         'helper',   false, false, false),
  (29, 'app',    'card_identity_digest',                'text,uuid,uuid,text',                          'helper',   false, false, false),
  (30, 'app',    'card_provider_key',                   'bytea,text',                                   'helper',   false, false, false),
  (31, 'app',    'card_event_detail_ok',                'text,jsonb',                                   'helper',   false, false, false),
  (32, 'app',    'card_pilot_revision_current',         '',                                             'helper',   false, false, false),
  (33, 'app',    'card_attested_approver_ok',           'uuid',                                         'helper',   false, false, false),
  (34, 'app',    'card_attempt_proof',                  'uuid,uuid,text,boolean',                       'helper',   false, false, false),
  (35, 'app',    'card_attempt_payment_id',             'app.card_provider_attempts',                   'helper',   false, false, false),
  (36, 'app',    'card_attempt_derive',                 'app.card_provider_attempts',                   'helper',   false, false, false),
  (37, 'app',    'card_attempt_envelope',               'app.card_provider_attempts',                   'helper',   false, false, false),
  (38, 'app',    'card_order_claim_active',             'uuid,uuid',                                    'helper',   false, false, false),
  (39, 'app',    'card_shift_close_blocked',            'uuid,uuid',                                    'helper',   false, false, false),
  (40, 'app',    'card_active_manager_denial',          'uuid,uuid',                                    'helper',   false, false, false),
  (41, 'app',    'card_dispatch_certain_deny',          'uuid,uuid,text,uuid',                          'helper',   false, false, false),
  (42, 'app',    'card_private_event_write',
       'uuid,uuid,uuid,uuid,text,text,text,text,uuid,text,uuid,uuid,text,jsonb',                          'helper',   false, false, false),
  (43, 'app',    'card_audit_write',                    'uuid,uuid,uuid,uuid,uuid,text,jsonb',          'helper',   false, false, false),
  (44, 'app',    'card_denial_evidence',                'text,uuid,uuid,uuid,uuid,uuid,uuid,text,text', 'helper',   false, false, false),
  (45, 'app',    'card_attempt_resolve',                'jsonb,text',                                   'helper',   false, false, false),
  (46, 'app',    'card_config_mismatch',                'text,uuid,text,text,text,jsonb,jsonb',         'helper',   false, false, false),
  (47, 'app',    'card_terminal_posture',               'uuid,uuid,uuid',                               'helper',   false, false, false),
  (48, 'app',    'card_append_only_guard',              '',                                             'trigger',  false, false, false),
  (49, 'app',    'payment_terminals_guard',             '',                                             'trigger',  false, false, false),
  (50, 'app',    'card_attempts_insert_guard',          '',                                             'trigger',  false, false, false),
  (51, 'app',    'card_attempts_guard',                 '',                                             'trigger',  false, false, false),
  (52, 'app',    'card_events_guard',                   '',                                             'trigger',  false, false, false),
  -- Review fixes 14 and 2 (packet 3.2): two internal helpers, granted to none of the three roles.
  (53, 'app',    'card_text_absent',                    'text',                                         'helper',   false, false, false),
  (54, 'app',    'card_proof_denial_evidence',          'jsonb,uuid,text,text',                         'helper',   false, false, false),
  -- C2 (D-060 point 2): the original-caller check of the five session-proving operations, granted to none of the three.
  (55, 'app',    'card_caller_binding_denial',          'uuid',                                         'helper',   false, false, false);
update _sa_fn set sig = nsp || '.' || name || '(' || args || ')',
                  fn = to_regprocedure(nsp || '.' || name || '(' || args || ')')::oid;
-- A typed all-NULL call per function, used only by the runtime privilege probes.
-- Each NULL is a scalar sub-select, not a constant: the planner folds a STRICT
-- function over a constant NULL to NULL without ever reaching the EXECUTE
-- check (app.card_text_canonical is STRICT), which would mask the ACL.
update _sa_fn f set call_sql = format('select %s.%s(%s)', f.nsp, f.name,
    coalesce((select string_agg('(select null::' || format_type(a.t, null) || ')', ', ' order by a.n)
                from pg_proc p cross join lateral unnest(p.proargtypes::oid[]) with ordinality a(t, n)
               where p.oid = f.fn), ''))
 where f.fn is not null;

-- Direct statements against the five tables and the revision sequence.
create temp table _sa_stmt as
select t.t as target, s.kind, format(s.tmpl, t.t) as sql
  from _sa_tables t
  cross join (values ('select',   'select 1 from app.%I limit 1'),
                     ('insert',   'insert into app.%I default values'),
                     ('update',   'update app.%I set organization_id = organization_id'),
                     ('delete',   'delete from app.%I'),
                     ('truncate', 'truncate app.%I')) s(kind, tmpl)
union all
select 'card_payments_pilot_revisions_revision_seq', 'nextval',
       'select nextval(''app.card_payments_pilot_revisions_revision_seq'')'
union all
select 'card_payments_pilot_revisions_revision_seq', 'read',
       'select last_value from app.card_payments_pilot_revisions_revision_seq';

-- Runtime probe: runs one statement AS the current role inside its own
-- sub-transaction and always undoes it. 'denied' = refused by the privilege
-- layer (42501 permission denied for ...); 'passed' = the privilege layer let
-- it through (it ran, or raised something else afterwards); 'unresolved:*' =
-- the object could not be resolved at all.
create function pg_temp.sa_probe(p_sql text) returns text language plpgsql as $$
begin
  if p_sql is null then
    return 'unresolved:no-call';
  end if;
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = 'sa-probe-undo';
  exception when others then
    if sqlstate = 'P0001' and sqlerrm = 'sa-probe-undo' then
      return 'passed';
    elsif sqlstate = '42501' and sqlerrm like 'permission denied for %' then
      return 'denied';
    elsif sqlstate in ('42883', '42P01', '42704', '3F000', '42601') then
      return 'unresolved:' || sqlstate;
    end if;
    return 'passed';
  end;
end $$;
-- Evaluates one jsonb expression AS the current role; an error becomes data.
create function pg_temp.sa_eval(p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  execute p_sql into v;
  return v;
exception when others then
  return jsonb_build_object('sa_error', sqlstate, 'message', sqlerrm);
end $$;
-- Comment-stripped function sources of every non-system schema.
create temp view _sa_src as
select p.oid, n.nspname::text as nsp, p.proname::text as name,
       regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_(temp|toast)';

create temp table _sa_r (label text primary key, r jsonb);
grant select on _sa_tables, _sa_fn, _sa_stmt to anon, authenticated, service_role;
grant all on _sa_r to anon, authenticated, service_role;

-- ===========================================================================
-- 0. Dark by default (DEPLOYMENT 18.2 POST: no row exists in the five tables).
-- ===========================================================================
select is(
  format('revisions=%s terminals=%s attempts=%s events=%s tombstones=%s',
    (select count(*) from app.card_payments_pilot_revisions), (select count(*) from app.payment_terminals),
    (select count(*) from app.card_provider_attempts), (select count(*) from app.card_provider_private_events),
    (select count(*) from app.card_attempt_identity_tombstones)),
  'revisions=0 terminals=0 attempts=0 events=0 tombstones=0',
  'SA-001 dark by default: no pilot revision, terminal binding, attempt, private event or tombstone row exists (no revision row = pilot OFF)');

-- ===========================================================================
-- 1. The five tables: existence, forced RLS, deny_client, zero privileges.
-- ===========================================================================
select is(
  (select string_agg(c.relname::text || ':' || c.relkind::text || ':' || pg_get_userbyid(c.relowner)::text, ','
                     order by c.relname::text collate "C")
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'app' and c.relname::text in (select t from _sa_tables)),
  'card_attempt_identity_tombstones:r:postgres,card_payments_pilot_revisions:r:postgres,card_provider_attempts:r:postgres,'
  || 'card_provider_private_events:r:postgres,payment_terminals:r:postgres',
  'SA-002 the five private tables exist in schema app as ordinary tables owned by postgres');

select is(
  (select coalesce(string_agg(n.nspname::text || '.' || c.relname::text, ',' order by n.nspname::text, c.relname::text), '')
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relname::text in (select t from _sa_tables) and n.nspname <> 'app'),
  '',
  'SA-003 no relation with any of the five names exists outside schema app (nothing in the Data-API public schema)');

select is(
  (select string_agg(c.relname::text || ':' || c.relrowsecurity::text || '/' || c.relforcerowsecurity::text, ','
                     order by c.relname::text collate "C")
     from pg_class c where c.oid in (select to_regclass('app.' || t) from _sa_tables)),
  'card_attempt_identity_tombstones:true/true,card_payments_pilot_revisions:true/true,card_provider_attempts:true/true,'
  || 'card_provider_private_events:true/true,payment_terminals:true/true',
  'SA-004 row level security is enabled AND forced on each of the five tables');

select set_eq(
  $$select tablename::text, policyname::text, permissive::text, array_to_string(roles, ','), cmd::text, qual::text,
           with_check::text
      from pg_policies where schemaname = 'app' and tablename::text in (select t from _sa_tables)$$,
  $$select t, 'deny_client'::text as policyname, 'PERMISSIVE'::text as permissive, 'authenticated'::text as roles,
           'ALL'::text as cmd, 'false'::text as qual, 'false'::text as with_check
      from _sa_tables$$,
  'SA-005 each table carries exactly one policy: deny_client, PERMISSIVE, FOR ALL TO authenticated USING (false) WITH CHECK (false)');

create temp table _sa_tpriv as
select r.role, t.t, p.priv
  from (values ('anon'), ('authenticated'), ('service_role')) r(role)
  cross join _sa_tables t
  cross join unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']
                    || case when current_setting('server_version_num')::integer >= 170000
                            then array['MAINTAIN'] else array[]::text[] end) p(priv);

select is(
  (select format('%s checks; held: %s', count(*), coalesce(string_agg(t || ':' || priv, ',' order by t, priv)
            filter (where has_table_privilege(role, to_regclass('app.' || t), priv) is distinct from false), ''))
     from _sa_tpriv where role = 'anon'),
  format('%s checks; held: ', (select count(*) from _sa_tpriv where role = 'anon')),
  'SA-006 anon holds no SELECT / INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER (/ MAINTAIN) privilege on any of the five tables');

select is(
  (select format('%s checks; held: %s', count(*), coalesce(string_agg(t || ':' || priv, ',' order by t, priv)
            filter (where has_table_privilege(role, to_regclass('app.' || t), priv) is distinct from false), ''))
     from _sa_tpriv where role = 'authenticated'),
  format('%s checks; held: ', (select count(*) from _sa_tpriv where role = 'authenticated')),
  'SA-007 authenticated holds no SELECT / INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER (/ MAINTAIN) privilege on any of the five tables');

select is(
  (select format('%s checks; held: %s', count(*), coalesce(string_agg(t || ':' || priv, ',' order by t, priv)
            filter (where has_table_privilege(role, to_regclass('app.' || t), priv) is distinct from false), ''))
     from _sa_tpriv where role = 'service_role'),
  format('%s checks; held: ', (select count(*) from _sa_tpriv where role = 'service_role')),
  'SA-008 service_role holds no SELECT / INSERT / UPDATE / DELETE / TRUNCATE / REFERENCES / TRIGGER (/ MAINTAIN) privilege on any of the five tables');

select is(
  (select coalesce(string_agg(r.role || ':' || t.t, ',' order by r.role, t.t), '')
     from (values ('anon'), ('authenticated'), ('service_role')) r(role) cross join _sa_tables t
    where has_any_column_privilege(r.role, to_regclass('app.' || t.t), 'SELECT, INSERT, UPDATE, REFERENCES')
            is distinct from false
       or exists (select 1 from pg_attribute a where a.attrelid = to_regclass('app.' || t.t) and a.attacl is not null)),
  '',
  'SA-009 no column-level privilege either: no column ACL exists and no app role holds SELECT / INSERT / UPDATE / REFERENCES on any column');

select is(
  (select coalesce(string_agg(c.relname::text || ':' || case when a.grantee = 0 then 'PUBLIC'
                                                             else pg_get_userbyid(a.grantee)::text end
                              || '=' || a.privilege_type, ',' order by c.relname::text, a.grantee, a.privilege_type), '')
     from pg_class c
     cross join lateral aclexplode(coalesce(c.relacl, acldefault(case c.relkind when 'S' then 's' else 'r' end::"char",
                                                                 c.relowner))) a
    where c.oid in (select to_regclass('app.' || t) from _sa_tables
                    union all select to_regclass('app.card_payments_pilot_revisions_revision_seq'))
      and a.grantee <> c.relowner),
  '',
  'SA-010 the ACL of the five tables and of the revision sequence grants nothing to PUBLIC or to any role other than the owner');

select is(
  (select coalesce(string_agg(r.role || ':' || p.priv, ',' order by r.role, p.priv), '')
     from (values ('anon'), ('authenticated'), ('service_role')) r(role)
     cross join (values ('USAGE'), ('SELECT'), ('UPDATE')) p(priv)
    where has_sequence_privilege(r.role, to_regclass('app.card_payments_pilot_revisions_revision_seq'), p.priv)
            is distinct from false),
  '',
  'SA-011 no privilege on app.card_payments_pilot_revisions_revision_seq (USAGE / SELECT / UPDATE) for anon, authenticated or service_role');

select is(
  (select coalesce(string_agg(pubname::text || ':' || tablename::text, ',' order by pubname::text, tablename::text), '')
     from pg_publication_tables where schemaname = 'app' and tablename::text in (select t from _sa_tables)),
  '',
  'SA-012 none of the five tables belongs to any publication (no Realtime / logical-replication stream of private rows)');

-- ===========================================================================
-- 1b. Direct table writes AS the real roles (scope item 10).
-- ===========================================================================
set local role authenticated;
select throws_ok($$insert into app.card_payments_pilot_revisions default values$$, '42501',
  'permission denied for table card_payments_pilot_revisions',
  'SA-013 AS authenticated an INSERT into app.card_payments_pilot_revisions raises 42501 permission denied for table');
select throws_ok($$insert into app.payment_terminals default values$$, '42501',
  'permission denied for table payment_terminals',
  'SA-014 AS authenticated an INSERT into app.payment_terminals raises 42501 permission denied for table');
select throws_ok($$insert into app.card_provider_attempts default values$$, '42501',
  'permission denied for table card_provider_attempts',
  'SA-015 AS authenticated an INSERT into app.card_provider_attempts raises 42501 permission denied for table');
select throws_ok($$insert into app.card_provider_private_events default values$$, '42501',
  'permission denied for table card_provider_private_events',
  'SA-016 AS authenticated an INSERT into app.card_provider_private_events raises 42501 permission denied for table');
select throws_ok($$insert into app.card_attempt_identity_tombstones default values$$, '42501',
  'permission denied for table card_attempt_identity_tombstones',
  'SA-017 AS authenticated an INSERT into app.card_attempt_identity_tombstones raises 42501 permission denied for table');
reset role;

set local role service_role;
select throws_ok($$insert into app.card_payments_pilot_revisions default values$$, '42501',
  'permission denied for table card_payments_pilot_revisions',
  'SA-018 AS service_role an INSERT into app.card_payments_pilot_revisions raises 42501 permission denied for table');
select throws_ok($$insert into app.payment_terminals default values$$, '42501',
  'permission denied for table payment_terminals',
  'SA-019 AS service_role an INSERT into app.payment_terminals raises 42501 permission denied for table');
select throws_ok($$insert into app.card_provider_attempts default values$$, '42501',
  'permission denied for table card_provider_attempts',
  'SA-020 AS service_role an INSERT into app.card_provider_attempts raises 42501 permission denied for table');
select throws_ok($$insert into app.card_provider_private_events default values$$, '42501',
  'permission denied for table card_provider_private_events',
  'SA-021 AS service_role an INSERT into app.card_provider_private_events raises 42501 permission denied for table');
select throws_ok($$insert into app.card_attempt_identity_tombstones default values$$, '42501',
  'permission denied for table card_attempt_identity_tombstones',
  'SA-022 AS service_role an INSERT into app.card_attempt_identity_tombstones raises 42501 permission denied for table');
reset role;

-- Every direct statement (select / insert / update / delete / truncate on each
-- table; nextval / read on the sequence) AS each role.
set local role anon;
insert into _sa_r select 'stmt-anon', jsonb_object_agg(target || ':' || kind, pg_temp.sa_probe(sql)) from _sa_stmt;
reset role;
set local role authenticated;
insert into _sa_r select 'stmt-authenticated', jsonb_object_agg(target || ':' || kind, pg_temp.sa_probe(sql)) from _sa_stmt;
reset role;
set local role service_role;
insert into _sa_r select 'stmt-service_role', jsonb_object_agg(target || ':' || kind, pg_temp.sa_probe(sql)) from _sa_stmt;
reset role;

select is(
  (select format('%s probes; not denied: %s', count(*), coalesce(string_agg(e.key || '=' || e.value, ',' order by e.key)
            filter (where e.value <> 'denied'), ''))
     from _sa_r r cross join lateral jsonb_each_text(r.r) e where r.label = 'stmt-anon'),
  '27 probes; not denied: ',
  'SA-023 AS anon every SELECT / INSERT / UPDATE / DELETE / TRUNCATE on the five tables and nextval / read of the revision sequence is refused 42501 (27 probes)');
select is(
  (select format('%s probes; not denied: %s', count(*), coalesce(string_agg(e.key || '=' || e.value, ',' order by e.key)
            filter (where e.value <> 'denied'), ''))
     from _sa_r r cross join lateral jsonb_each_text(r.r) e where r.label = 'stmt-authenticated'),
  '27 probes; not denied: ',
  'SA-024 AS authenticated every SELECT / INSERT / UPDATE / DELETE / TRUNCATE on the five tables and nextval / read of the revision sequence is refused 42501 (27 probes)');
select is(
  (select format('%s probes; not denied: %s', count(*), coalesce(string_agg(e.key || '=' || e.value, ',' order by e.key)
            filter (where e.value <> 'denied'), ''))
     from _sa_r r cross join lateral jsonb_each_text(r.r) e where r.label = 'stmt-service_role'),
  '27 probes; not denied: ',
  'SA-025 AS service_role (which bypasses RLS) every SELECT / INSERT / UPDATE / DELETE / TRUNCATE on the five tables and nextval / read of the revision sequence is refused 42501 (27 probes)');

-- ===========================================================================
-- 2. Column sets (DOMAIN_MODEL 8.4-8.7) and the no-free-text rule.
-- ===========================================================================
select is(
  (select array_agg(column_name::text order by column_name::text collate "C") from information_schema.columns
    where table_schema = 'app' and table_name = 'card_provider_attempts'),
  (select array_agg(c order by c collate "C") from unnest(array[
     'id', 'organization_id', 'restaurant_id', 'branch_id', 'device_id', 'local_operation_id', 'order_id',
     'shift_id', 'cash_drawer_session_id', 'initiated_by_employee_profile_id', 'initiated_by_membership_id',
     'mode', 'state', 'amount_minor', 'currency_code', 'expected_revision', 'terminal_ref', 'credential_ref',
     'provider_status_digest', 'provider_duplicate_digest', 'provider_key_format_version', 'provider_query_key',
     'provider_duplicate_key', 'provider_reference', 'approval_number', 'voucher_number', 'card_last4',
     'card_brand_code', 'approval_type', 'provider_return_code', 'provider_return_class', 'provider_anomaly_code',
     'charge_may_exist', 'pan_entry_mode', 'payment_method_code', 'provider_status_code', 'deposit_id',
     'provider_saved_at', 'provider_approved_at', 'refusal_code', 'recording_refused_at', 'recording_resume_count',
     'recording_refusal_history', 'recording_resume_history', 'release_requested_at', 'released_at',
     'last_lookup_at', 'auto_poll_count', 'order_freed_at', 'order_freed_reason', 'confirmation_source',
     'confirmation_reference', 'order_freed_note', 'resolution', 'resolution_reference', 'resolved_at',
     'retention_until', 'incident_hold_at', 'incident_hold_reference', 'start_deadline_at', 'started_at',
     'finished_at', 'created_at', 'updated_at', 'claim_signal_at']) c),
  'SA-026 app.card_provider_attempts has EXACTLY the DOMAIN 8.4 column list (65 columns, sorted; C1-1 added claim_signal_at, the durable claim signal of the snapshot watermark): no deleted_at, no provider message / raw column');

select is(
  (select array_agg(column_name::text order by column_name::text collate "C") from information_schema.columns
    where table_schema = 'app' and table_name = 'payment_terminals'),
  (select array_agg(c order by c collate "C") from unnest(array[
     'id', 'organization_id', 'restaurant_id', 'branch_id', 'device_id', 'terminal_ref', 'credential_ref', 'mode',
     'lifecycle', 'lifecycle_changed_at', 'created_at', 'updated_at', 'deleted_at']) c),
  'SA-027 app.payment_terminals has exactly the DOMAIN 8.5 column list (13 columns; opaque references only, no credential column)');

select is(
  (select array_agg(column_name::text order by column_name::text collate "C") from information_schema.columns
    where table_schema = 'app' and table_name = 'card_provider_private_events'),
  (select array_agg(c order by c collate "C") from unnest(array[
     'id', 'organization_id', 'restaurant_id', 'branch_id', 'attempt_row_id', 'mode', 'action', 'actor_kind',
     'actor_reference', 'actor_app_user_id', 'executor_principal', 'actor_employee_profile_id', 'device_id',
     'reason', 'detail', 'retention_until', 'incident_hold_at', 'incident_hold_reference', 'created_at']) c),
  'SA-028 app.card_provider_private_events has exactly the DOMAIN 8.6 column list (19 columns)');

select is(
  (select array_agg(column_name::text order by column_name::text collate "C") from information_schema.columns
    where table_schema = 'app' and table_name = 'card_payments_pilot_revisions'),
  (select array_agg(c order by c collate "C") from unnest(array[
     'revision', 'organization_id', 'restaurant_id', 'branch_id', 'enabled', 'mode', 'window_until',
     'max_test_amount_minor', 'max_live_amount_minor', 'reason', 'operator_reference', 'actor_app_user_id',
     'executor_principal', 'recorded_at']) c),
  'SA-029 app.card_payments_pilot_revisions has exactly the DOMAIN 8.7 column list (14 columns)');

select is(
  (select array_agg(column_name::text order by column_name::text collate "C") from information_schema.columns
    where table_schema = 'app' and table_name = 'card_attempt_identity_tombstones'),
  (select array_agg(c order by c collate "C") from unnest(array[
     'organization_id', 'device_id', 'local_operation_id', 'provider_status_digest', 'provider_duplicate_digest',
     'provider_key_format_version', 'provider_query_key', 'provider_duplicate_key', 'purged_at']) c),
  'SA-030 app.card_attempt_identity_tombstones has exactly the DOMAIN 8.4 / D-058 point 7 column list (9 columns: identifiers, digests, keys only)');

select is(
  (select coalesce(string_agg(table_name::text || '.' || column_name::text, ',' order by table_name::text, column_name::text), '')
     from information_schema.columns
    where table_schema = 'app' and table_name::text in (select t from _sa_tables)
      and column_name::text ~ '(^|_)(message|msg|text|description|raw|payload|response|request|body|receipt|memo|comment|token|expiry|expiration|cvv|track|bin|masked|card_number)(_|$)'),
  '',
  'SA-031 no column of the five tables is a provider free-text / raw / card-data column (message, text, description, raw, payload, response, body, receipt, token, expiry, BIN, masked number)');

select is(
  (select string_agg(table_name::text || '.' || column_name::text || ':' || data_type::text, ','
                     order by table_name::text collate "C", column_name::text collate "C")
     from information_schema.columns
    where table_schema = 'app' and table_name::text in (select t from _sa_tables)
      and (column_name::text in ('local_operation_id', 'provider_status_digest', 'provider_duplicate_digest')
           or column_name::text like '%\_minor')),
  'card_attempt_identity_tombstones.local_operation_id:text,card_attempt_identity_tombstones.provider_duplicate_digest:bytea,'
  || 'card_attempt_identity_tombstones.provider_status_digest:bytea,card_payments_pilot_revisions.max_live_amount_minor:bigint,'
  || 'card_payments_pilot_revisions.max_test_amount_minor:bigint,card_provider_attempts.amount_minor:bigint,'
  || 'card_provider_attempts.local_operation_id:text,card_provider_attempts.provider_duplicate_digest:bytea,'
  || 'card_provider_attempts.provider_status_digest:bytea',
  'SA-032 identity and money types: local_operation_id is text (never uuid, D-056 point 9), both digests are bytea (D-058 point 2), every *_minor column is bigint (D-007)');

select is(
  (select coalesce(string_agg(table_name::text || '.' || column_name::text || ':' || data_type::text, ','
                              order by table_name::text, column_name::text), '')
     from information_schema.columns
    where table_schema = 'app' and table_name::text in (select t from _sa_tables)
      and data_type::text in ('real', 'double precision', 'numeric', 'money')),
  '',
  'SA-033 no column of the five tables is real / double precision / numeric / money (money is integer minor units only, D-007)');

select is(
  (select string_agg(table_name::text || '.' || column_name::text || ':' || is_nullable::text, ','
                     order by table_name::text collate "C", column_name::text collate "C")
     from information_schema.columns
    where table_schema = 'app'
      and (table_name::text, column_name::text) in (values
            ('payment_terminals', 'device_id'),
            ('card_provider_attempts', 'initiated_by_employee_profile_id'),
            ('card_provider_attempts', 'initiated_by_membership_id'),
            ('card_provider_private_events', 'actor_reference'),
            ('card_provider_private_events', 'branch_id'))),
  'card_provider_attempts.initiated_by_employee_profile_id:NO,card_provider_attempts.initiated_by_membership_id:NO,'
  || 'card_provider_private_events.actor_reference:NO,card_provider_private_events.branch_id:NO,payment_terminals.device_id:NO',
  'SA-034 NOT NULL where DOMAIN requires it: payment_terminals.device_id (no branch default), the frozen initiator ids (both modes), the event actor_reference and scope');

-- ===========================================================================
-- 3. The family EXECUTE matrix (packet 3.2) for anon / authenticated /
--    service_role on both layers, PUBLIC, exact ACLs, runtime probes.
-- ===========================================================================
select is(
  (select format('%s expected; unresolved: %s', count(*), coalesce(string_agg(sig, ', ' order by ord) filter (where fn is null), ''))
     from _sa_fn),
  '55 expected; unresolved: ',
  'SA-035 every one of the 55 functions the migration creates (8 caller / service pairs on both layers, 2 internal guards, 5 operator RPCs, 2 lock helpers, 25 helpers - card_text_absent and card_proof_denial_evidence added by review fixes 14 and 2, card_caller_binding_denial by C2 - and 5 trigger functions) resolves at its exact identity signature (C1-3: the purge at its 4-argument identity (text,text,uuid,integer); C2: the five session-proving service-only pairs at their identities with the trailing uuid, and the helper at (uuid): the family is 55)');

select is(
  (select coalesce(string_agg(n.nspname::text || '.' || p.proname::text || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                              ', ' order by n.nspname::text, p.proname::text), '')
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and (p.proname like 'card\_%' or p.proname in ('owner_card_attempts', 'set_card_payments_pilot', 'set_payment_terminal',
                                                    'purge_expired_test_card_attempts', 'payment_terminals_guard'))
      and p.oid not in (select fn from _sa_fn where fn is not null)),
  '',
  'SA-036 no unlisted function or overload of the card family exists in app or public (the matrix below is complete, including app.card_text_absent(text) and app.card_proof_denial_evidence(jsonb,uuid,text,text) of review fixes 14 and 2; C1-3: the purge has the single 4-argument overload, the 3-argument identity is gone; C2: the five changed pairs exist only at their identities with the trailing uuid, and app.card_caller_binding_denial(uuid) is listed)');

select is(
  (select coalesce(string_agg(f.sig || ' ' || r.role || ' have=' || coalesce(has_function_privilege(r.role, f.fn, 'EXECUTE')::text, 'null'),
                              '; ' order by f.ord, r.role)
            filter (where has_function_privilege(r.role, f.fn, 'EXECUTE') is distinct from r.expected), '')
     from _sa_fn f
     cross join lateral (values ('anon', f.x_anon), ('authenticated', f.x_auth), ('service_role', f.x_svc)) r(role, expected)),
  '',
  'SA-037 the EXECUTE matrix of all 55 functions x {anon, authenticated, service_role} (165 cells) equals packet 3.2 / 13.3 exactly (review fixes 14 and 2: the two new helpers are granted to none; C1-3: the purge row at (text,text,uuid,integer), still granted to none; C2: the five changed pairs at their new identities stay service_role only, the helper is granted to none)');

select is(
  (select coalesce(string_agg(f.sig, ', ' order by f.ord), '') from _sa_fn f
    where has_function_privilege('authenticated', f.fn, 'EXECUTE')),
  'app.card_attempt_context(uuid,uuid,text,uuid,text), public.card_attempt_context(uuid,uuid,text,uuid,text), '
  || 'app.owner_card_attempts(uuid,uuid,uuid,timestamptz,timestamptz,text), public.owner_card_attempts(uuid,uuid,uuid,timestamptz,timestamptz,text)',
  'SA-038 authenticated executes exactly the caller-authority pair on both layers (card_attempt_context, owner_card_attempts) and no service-only, internal, operator or lock function');

select is(
  (select coalesce(string_agg(f.sig, ', ' order by f.ord), '') from _sa_fn f
    where has_function_privilege('service_role', f.fn, 'EXECUTE')),
  'app.card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid), '
  || 'public.card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid), '
  || 'app.card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid), public.card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid), '
  || 'app.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text), '
  || 'public.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text), '
  || 'app.card_attempt_mark_release_requested(uuid,uuid,text,text,uuid), public.card_attempt_mark_release_requested(uuid,uuid,text,text,uuid), '
  || 'app.card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid), public.card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid), '
  || 'app.card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid), public.card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid)',
  'SA-039 service_role executes exactly the six service-only pairs on both layers (claim, adapter_read, finish, mark_release_requested, mark_recording_result, free_order) and nothing else of the family (C2: five of the pairs at their identities with the trailing uuid; finish unchanged; the helper not granted)');

select is(
  (select coalesce(string_agg(f.sig, ', ' order by f.ord), '') from _sa_fn f
    where has_function_privilege('anon', f.fn, 'EXECUTE')),
  '',
  'SA-040 anon executes none of the 55 functions (the two helpers of review fixes 14 and 2 and the C2 helper card_caller_binding_denial included)');

select is(
  (select coalesce(string_agg(f.sig, ', ' order by f.ord), '') from _sa_fn f join pg_proc p on p.oid = f.fn
    where exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                   where a.grantee = 0 and a.privilege_type = 'EXECUTE')),
  '',
  'SA-041 PUBLIC (grantee 0 of aclexplode(coalesce(proacl, acldefault(f, owner)))) holds EXECUTE on none of the 55 functions (the two helpers of review fixes 14 and 2 and the C2 helper card_caller_binding_denial included)');

select is(
  (select coalesce(string_agg(f.sig || ' acl=' || coalesce(p.proacl::text, 'NULL'), '; ' order by f.ord)
            filter (where p.proacl::text is distinct from
                    '{postgres=X/postgres' || case when f.x_auth then ',authenticated=X/postgres' else '' end
                    || case when f.x_svc then ',service_role=X/postgres' else '' end || '}'), '')
     from _sa_fn f join pg_proc p on p.oid = f.fn),
  '',
  'SA-042 every family ACL is exactly {postgres=X/postgres} plus the single packet grant (authenticated or service_role): no other grantee of any kind');

set local role anon;
insert into _sa_r select 'fn-anon', jsonb_object_agg(sig, pg_temp.sa_probe(call_sql)) from _sa_fn;
reset role;
set local role authenticated;
insert into _sa_r select 'fn-authenticated', jsonb_object_agg(sig, pg_temp.sa_probe(call_sql)) from _sa_fn;
reset role;
set local role service_role;
insert into _sa_r select 'fn-service_role', jsonb_object_agg(sig, pg_temp.sa_probe(call_sql)) from _sa_fn;
reset role;

select is(
  (select format('%s probed; mismatches: %s', count(*), coalesce(string_agg(f.sig || '=' || coalesce(r.r ->> f.sig, 'missing'), ', ' order by f.ord)
            filter (where (r.r ->> f.sig) is distinct from case when f.x_anon then 'passed' else 'denied' end), ''))
     from _sa_fn f cross join (select r from _sa_r where label = 'fn-anon') r),
  '55 probed; mismatches: ',
  'SA-043 runtime AS anon: calling any of the 55 functions (the two helpers of review fixes 14 and 2 and the C2 helper included) is refused 42501 by the privilege layer (none executes; C1-3: the purge probed at its 4-argument identity; C2: the five changed pairs probed at their identities with the trailing uuid)');
select is(
  (select format('%s probed; mismatches: %s', count(*), coalesce(string_agg(f.sig || '=' || coalesce(r.r ->> f.sig, 'missing'), ', ' order by f.ord)
            filter (where (r.r ->> f.sig) is distinct from case when f.x_auth then 'passed' else 'denied' end), ''))
     from _sa_fn f cross join (select r from _sa_r where label = 'fn-authenticated') r),
  '55 probed; mismatches: ',
  'SA-044 runtime AS authenticated: only the 4 caller-authority functions pass the privilege layer (each public wrapper reaches its app body); the 51 others, every service-only pair, the two helpers of review fixes 14 and 2 and the C2 helper included, are refused 42501 (C1-3: the purge probed at its 4-argument identity; C2: the five changed pairs probed at their identities with the trailing uuid)');
select is(
  (select format('%s probed; mismatches: %s', count(*), coalesce(string_agg(f.sig || '=' || coalesce(r.r ->> f.sig, 'missing'), ', ' order by f.ord)
            filter (where (r.r ->> f.sig) is distinct from case when f.x_svc then 'passed' else 'denied' end), ''))
     from _sa_fn f cross join (select r from _sa_r where label = 'fn-service_role') r),
  '55 probed; mismatches: ',
  'SA-045 runtime AS service_role: only the 12 service-only functions pass the privilege layer (each public wrapper reaches its app body); the 43 others (caller pair, guards, operator RPCs, lock helpers, helpers - the two of review fixes 14 and 2 and the C2 helper included - triggers) are refused 42501 (C1-3: the purge probed at its 4-argument identity; C2: the five changed pairs probed at their identities with the trailing uuid)');

-- ===========================================================================
-- 4. Attributes: DEFINER / INVOKER, search_path, owner, volatility, overloads,
--    no wrapper for any internal / operator function.
-- ===========================================================================
select is(
  (select coalesce(string_agg(f.sig, ', ' order by f.ord)
            filter (where not (p.prosecdef and p.proconfig = array['search_path=""']
                               and pg_get_userbyid(p.proowner) = 'postgres')), '') || ' / ' || count(*)::text
     from _sa_fn f join pg_proc p on p.oid = f.fn
    where f.nsp = 'app' and f.family in ('caller', 'service', 'guard', 'operator')),
  ' / 15',
  'SA-046 the 15 app.* RPC bodies (8 caller / service bodies, 2 internal guards, 5 operator RPCs) are SECURITY DEFINER, proconfig {search_path=""}, owner postgres (C1-3: the purge body at its 4-argument identity; C2: the five changed service bodies at their identities with the trailing uuid)');

select is(
  (select coalesce(string_agg(f.sig, ', ' order by f.ord)
            filter (where p.proconfig is distinct from array['search_path=""']
                       or pg_get_userbyid(p.proowner) <> 'postgres'), '') || ' / ' || count(*)::text
     from _sa_fn f join pg_proc p on p.oid = f.fn),
  ' / 55',
  'SA-047 all 55 family functions (the two helpers of review fixes 14 and 2 and the C2 helper included) pin search_path to the empty string and are owned by postgres (C1-3: the purge at its 4-argument identity; C2: the five changed pairs at their identities with the trailing uuid)');

select is(
  (select coalesce(string_agg(w.sig || ' secdef=' || pw.prosecdef::text || ' lang=' || l.lanname::text
                              || ' cfg=' || coalesce(pw.proconfig::text, 'null') || ' vol=' || pw.provolatile::text
                              || '/' || pb.provolatile::text, '; ' order by w.ord)
            filter (where pw.prosecdef or l.lanname <> 'sql' or pw.proconfig is distinct from array['search_path=""']
                       or pw.provolatile <> pb.provolatile), '') || ' / ' || count(*)::text
     from _sa_fn w
     join _sa_fn b on b.nsp = 'app' and b.name = w.name
     join pg_proc pw on pw.oid = w.fn
     join pg_proc pb on pb.oid = b.fn
     join pg_language l on l.oid = pw.prolang
    where w.nsp = 'public'),
  ' / 8',
  'SA-048 the 8 public wrappers are LANGUAGE sql, SECURITY INVOKER, search_path pinned, and each has exactly its app body''s volatility (C2: the five changed wrappers and bodies at their identities with the trailing uuid)');

select is(
  (select coalesce(string_agg(w.sig, ', ' order by w.ord)
            filter (where pg_get_function_identity_arguments(w.fn) <> pg_get_function_identity_arguments(b.fn)
                       or pg_get_function_result(w.fn) <> pg_get_function_result(b.fn)
                       or (select array_agg(m[1]) from regexp_matches(regexp_replace(pw.prosrc, '--[^\n]*', '', 'g'),
                                                                       'app\.([a-z0-9_]+)\s*\(', 'g') m)
                          is distinct from array[w.name]), '') || ' / ' || count(*)::text
     from _sa_fn w
     join _sa_fn b on b.nsp = 'app' and b.name = w.name
     join pg_proc pw on pw.oid = w.fn
    where w.nsp = 'public'),
  ' / 8',
  'SA-049 each public wrapper has its body''s identity arguments and result type and delegates to exactly one function: its own app.* body (C2: the five changed wrappers and bodies share the identity with the trailing p_caller_auth_user_id uuid)');

select is(
  (select coalesce(string_agg(x.nsp || '.' || x.name || ' x' || x.n::text, ', ' order by x.ord) filter (where x.n <> 1), '')
          || ' / ' || count(*)::text
     from (select f.ord, f.nsp, f.name,
                  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = f.nsp and p.proname = f.name) as n
             from _sa_fn f) x),
  ' / 55',
  'SA-050 exactly one overload exists for each of the 55 family function names (per schema; the two helpers of review fixes 14 and 2 and the C2 helper included; C2: the five changed names have no overload left at the old identity)');

select is(
  (select coalesce(string_agg(p.proname::text, ', ' order by p.proname::text), '') from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('card_claim_guard', 'card_recording_resume_guard', 'set_card_payments_pilot', 'set_payment_terminal',
                        'card_attempt_resolve_orphan', 'card_attempt_set_incident_hold', 'purge_expired_test_card_attempts',
                        'card_identity_lock', 'card_terminal_lock', 'card_safe_text_ok')),
  '',
  'SA-051 no public.* function exists for any internal guard, operator RPC, lock helper or card_safe_text_ok (the ten named functions)');

select set_eq(
  $$select p.proname::text from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname::text in (select name from _sa_fn)$$,
  array['card_attempt_context', 'owner_card_attempts', 'card_attempt_claim', 'card_attempt_adapter_read', 'card_attempt_finish',
        'card_attempt_mark_release_requested', 'card_attempt_mark_recording_result', 'card_attempt_free_order'],
  'SA-052 the only public.* names of the family are the 8 wrappers: no public function for any of the 39 internal / operator / lock / helper / trigger functions (review fixes 14 and 2 added two helpers; C2 added card_caller_binding_denial)');

select set_eq(
  $$select n.nspname::text || '.' || p.proname::text, pg_get_function_arguments(p.oid)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname::text || '.' || p.proname::text = any (array[
       'public.card_attempt_context', 'public.card_attempt_claim', 'public.card_attempt_adapter_read',
       'public.card_attempt_finish', 'public.card_attempt_mark_release_requested',
       'public.card_attempt_mark_recording_result', 'public.card_attempt_free_order', 'public.owner_card_attempts',
       'app.card_claim_guard', 'app.card_recording_resume_guard', 'app.set_card_payments_pilot',
       'app.set_payment_terminal', 'app.card_attempt_resolve_orphan', 'app.purge_expired_test_card_attempts',
       'app.card_attempt_set_incident_hold', 'app.card_safe_text_ok', 'app.card_identity_lock', 'app.card_terminal_lock'])$$,
  $$values
    ('public.card_attempt_context', 'p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_order_id uuid, p_attempt_id text'),
    ('public.card_attempt_claim', 'p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_attempt_id text, p_mode text, p_amount_minor bigint, p_currency_code text, p_order_id uuid, p_expected_revision integer, p_environment text, p_terminals jsonb, p_credentials jsonb, p_key_format_version text, p_caller_auth_user_id uuid'),
    ('public.card_attempt_adapter_read', 'p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_attempt_id text, p_environment text, p_terminals jsonb, p_credentials jsonb, p_caller_auth_user_id uuid'),
    ('public.card_attempt_finish', 'p_attempt_row_id uuid, p_organization_id uuid, p_device_id uuid, p_local_operation_id text, p_mode text, p_amount_minor bigint, p_currency_code text, p_source text, p_outcome text, p_provider_fields jsonb, p_poll_source text'),
    ('public.card_attempt_mark_release_requested', 'p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_attempt_id text, p_caller_auth_user_id uuid'),
    ('public.card_attempt_mark_recording_result', 'p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_attempt_id text, p_refusal_code text, p_caller_auth_user_id uuid'),
    ('public.card_attempt_free_order', 'p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_attempt_id text, p_reason text, p_confirmation_source text, p_confirmation_reference text, p_caller_auth_user_id uuid'),
    ('public.owner_card_attempts', 'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_mode text DEFAULT ''live''::text'),
    ('app.card_claim_guard', 'p_pin_session_id uuid, p_device_id uuid, p_order_id uuid, p_local_operation_id text, p_operation_type text, p_tender_type text, p_shift_id uuid'),
    ('app.card_recording_resume_guard', 'p_pin_session_id uuid, p_device_id uuid, p_sync_operation_id uuid, p_recording_resume integer, p_target_entity text, p_target_id uuid, p_client_created_at timestamp with time zone, p_payload jsonb'),
    ('app.set_card_payments_pilot', 'p_enabled boolean, p_mode text, p_window_until timestamp with time zone, p_max_test_amount_minor bigint, p_max_live_amount_minor bigint, p_reason text, p_operator_reference text, p_actor_app_user_id uuid'),
    ('app.set_payment_terminal', 'p_device_id uuid, p_mode text, p_terminal_ref text, p_credential_ref text, p_lifecycle text, p_reason_code text, p_reason text, p_operator_reference text, p_actor_app_user_id uuid'),
    ('app.card_attempt_resolve_orphan', 'p_attempt_row_id uuid, p_resolution text, p_resolution_reference text, p_reason text, p_operator_reference text, p_actor_app_user_id uuid'),
    ('app.purge_expired_test_card_attempts', 'p_reason text, p_operator_reference text, p_actor_app_user_id uuid, p_max_devices integer DEFAULT NULL::integer'),
    ('app.card_attempt_set_incident_hold', 'p_target_kind text, p_target_id uuid, p_hold boolean, p_hold_reference text, p_reason text, p_operator_reference text, p_actor_app_user_id uuid'),
    ('app.card_safe_text_ok', 'p_value text, p_field text'),
    ('app.card_identity_lock', 'p_organization_id uuid, p_device_id uuid, p_local_operation_id text'),
    ('app.card_terminal_lock', 'p_organization_id uuid, p_device_id uuid')$$,
  'SA-053 the 18 functions API 4.55.10 names expose exactly its parameter names, types and order (8 wrappers, p_mode DEFAULT ''live'' on owner_card_attempts; guards, operator RPCs, card_safe_text_ok, lock helpers; card_recording_resume_guard with the 4 resent-envelope parameters of packet 11 item 7 appended; C1-3: the purge with p_max_devices integer DEFAULT NULL appended)');

select is(
  (select string_agg(x.sig || '=' || coalesce(p.provolatile::text, '?'), ', ' order by x.ord)
     from (values (1, 'app.card_attempt_context(uuid,uuid,text,uuid,text)'),
                  (2, 'app.owner_card_attempts(uuid,uuid,uuid,timestamptz,timestamptz,text)'),
                  (3, 'app.card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)'),
                  (4, 'app.card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)'),
                  (5, 'app.card_safe_text_ok(text,text)'), (6, 'app.card_safe_text_failure(text,text)'),
                  (7, 'app.card_text_canonical(text)'), (8, 'app.card_provider_key(bytea,text)'),
                  (9, 'app.card_event_detail_ok(text,jsonb)'), (10, 'app.card_attempt_derive(app.card_provider_attempts)'),
                  (11, 'app.card_attempt_envelope(app.card_provider_attempts)'), (12, 'app.card_order_claim_active(uuid,uuid)'),
                  (13, 'app.card_shift_close_blocked(uuid,uuid)'), (14, 'app.card_active_manager_denial(uuid,uuid)'),
                  (15, 'app.card_pilot_revision_current()'), (16, 'app.card_attested_approver_ok(uuid)')) x(ord, sig)
     left join pg_proc p on p.oid = to_regprocedure(x.sig)),
  'app.card_attempt_context(uuid,uuid,text,uuid,text)=v, app.owner_card_attempts(uuid,uuid,uuid,timestamptz,timestamptz,text)=s, '
  || 'app.card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)=v, '
  || 'app.card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)=v, app.card_safe_text_ok(text,text)=i, '
  || 'app.card_safe_text_failure(text,text)=i, app.card_text_canonical(text)=i, app.card_provider_key(bytea,text)=i, '
  || 'app.card_event_detail_ok(text,jsonb)=i, app.card_attempt_derive(app.card_provider_attempts)=s, '
  || 'app.card_attempt_envelope(app.card_provider_attempts)=s, app.card_order_claim_active(uuid,uuid)=s, '
  || 'app.card_shift_close_blocked(uuid,uuid)=s, app.card_active_manager_denial(uuid,uuid)=s, '
  || 'app.card_pilot_revision_current()=s, app.card_attested_approver_ok(uuid)=s',
  'SA-054 the packet 3.2 volatility annotations hold (context / claim / adapter_read VOLATILE; owner read and the derivation helpers STABLE; text, key and detail helpers IMMUTABLE)');

-- ===========================================================================
-- 5. REPORT-123 family guard; anon cannot use schema app.
-- ===========================================================================
select is(
  (select coalesce(string_agg(w.proname::text, ', ' order by w.proname::text), '')
     from pg_proc w join pg_namespace wn on wn.oid = w.pronamespace
     join pg_proc a on a.proname = w.proname join pg_namespace an on an.oid = a.pronamespace
    where wn.nspname = 'public' and an.nspname = 'app' and w.proname like 'owner\_%' and not w.prosecdef
      and has_function_privilege('authenticated', w.oid, 'EXECUTE')
      and not has_function_privilege('authenticated', a.oid, 'EXECUTE')),
  '',
  'SA-055 REPORT-123 owner_* family guard: no public.owner_* INVOKER wrapper is granted to authenticated while its app.* body is not');

select is(
  (select format('wrapper_invoker=%s wrapper_auth=%s body_auth=%s',
                 (not w.prosecdef)::text, has_function_privilege('authenticated', w.oid, 'EXECUTE')::text,
                 has_function_privilege('authenticated', a.oid, 'EXECUTE')::text)
     from pg_proc w, pg_proc a
    where w.oid = to_regprocedure('public.owner_card_attempts(uuid,uuid,uuid,timestamptz,timestamptz,text)')
      and a.oid = to_regprocedure('app.owner_card_attempts(uuid,uuid,uuid,timestamptz,timestamptz,text)')),
  'wrapper_invoker=true wrapper_auth=true body_auth=true',
  'SA-056 the guard covers public.owner_card_attempts (non-vacuous): an INVOKER wrapper granted to authenticated whose app body is granted to authenticated too');

select is(
  (select coalesce(string_agg(w.oid::regprocedure::text, ', ' order by w.oid::regprocedure::text), '')
     from pg_proc w join pg_namespace wn on wn.oid = w.pronamespace
    where wn.nspname = 'public' and not w.prosecdef and has_function_privilege('authenticated', w.oid, 'EXECUTE')
      and exists (select 1 from pg_proc a join pg_namespace an on an.oid = a.pronamespace
                   where an.nspname = 'app' and a.proname = w.proname
                     and not has_function_privilege('authenticated', a.oid, 'EXECUTE'))),
  '',
  'SA-057 REPORT-123 guard over the whole public schema (DEPLOYMENT 18.2 POST): no public INVOKER wrapper is granted to authenticated while a same-name app.* function is not');

select is(
  (select coalesce(string_agg(w.name || ':' || r.role, ', ' order by w.ord, r.role)
            filter (where has_function_privilege(r.role, w.fn, 'EXECUTE') is distinct from has_function_privilege(r.role, b.fn, 'EXECUTE')), '')
          || ' / ' || count(*)::text
     from _sa_fn w join _sa_fn b on b.nsp = 'app' and b.name = w.name
     cross join (values ('anon'), ('authenticated'), ('service_role')) r(role)
    where w.nsp = 'public'),
  ' / 24',
  'SA-058 D-035 / D-036 pairing: for each of the 8 card wrappers and each of anon / authenticated / service_role, the wrapper''s EXECUTE equals its app body''s (24 pairs)');

insert into auth.users (id, email) values (pg_temp.zc_id('sa-owner-auth'), 'zc001d-sa-owner@example.test');
update public.app_users set auth_user_id = pg_temp.zc_id('sa-owner-auth') where id = pg_temp.zc_id('user-9');
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.zc_id('sa-owner-auth')::text, true); end $$;
set local role authenticated;
insert into _sa_r select 'owner-read', pg_temp.sa_eval(
  'select public.owner_card_attempts(pg_temp.zc_org(), pg_temp.zc_rest(), pg_temp.zc_branch(), '
  || 'now() - interval ''1 day'', now() + interval ''1 hour'')');
reset role;
do $$ begin perform set_config('request.jwt.claim.sub', pg_temp.zc_id('transport-principal')::text, true); end $$;
select is(
  (select r from _sa_r where label = 'owner-read'),
  jsonb_build_object('ok', true, 'entity', 'owner_card_attempts', 'mode', 'live', 'rows', '[]'::jsonb, 'count', 0),
  'SA-059 REPORT-123 runtime proof: AS authenticated, a linked org_owner JWT principal reads public.owner_card_attempts end to end (no 42501 from the wrapper / body pair) and gets the empty LIVE envelope');

select is(
  format('usage=%s create=%s', has_schema_privilege('anon', 'app', 'USAGE')::text,
         has_schema_privilege('anon', 'app', 'CREATE')::text),
  'usage=false create=false',
  'SA-060 anon has no USAGE (and no CREATE) on schema app');

-- ===========================================================================
-- 6. The re-created live functions keep their signatures, ACLs, attributes,
--    and their public wrappers stay untouched INVOKER functions.
-- ===========================================================================
create temp table _sa_recreated (ord integer primary key, sig text not null, pre_acl text not null, pre_attr text not null);
insert into _sa_recreated values
  (1, 'app.sync_push(uuid,uuid,jsonb)',                                                '{postgres=X/postgres,authenticated=X/postgres}', 'definer:v'),
  (2, 'app.pin_session_capabilities(uuid,uuid)',                                       '{postgres=X/postgres,authenticated=X/postgres}', 'definer:s'),
  (3, 'app.pos_order_snapshots(uuid,uuid,timestamptz,uuid,timestamptz,uuid,uuid[],integer,integer)',
                                                                                       '{postgres=X/postgres,authenticated=X/postgres}', 'definer:s'),
  (4, 'app.audit_action_has_detail(text)',                                             '{postgres=X/postgres,authenticated=X/postgres}', 'invoker:i'),
  (5, 'app.audit_safe_detail(text,jsonb)',                                             '{postgres=X/postgres,authenticated=X/postgres}', 'invoker:i'),
  (6, 'app.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,integer,text)',
                                                                                       '{postgres=X/postgres,authenticated=X/postgres}', 'definer:s'),
  (7, 'app.audit_category(text)',                                                      '{postgres=X/postgres}',                          'invoker:i');

select is(
  (select coalesce(string_agg(x.sig || ' resolved=' || (to_regprocedure(x.sig) is not null)::text || ' overloads='
                              || (select count(*) from pg_proc p where p.pronamespace = 'app'::regnamespace
                                     and p.proname = split_part(substr(x.sig, 5), '(', 1))::text, '; ' order by x.ord)
            filter (where to_regprocedure(x.sig) is null
                       or (select count(*) from pg_proc p where p.pronamespace = 'app'::regnamespace
                              and p.proname = split_part(substr(x.sig, 5), '(', 1)) <> 1), '') || ' / ' || count(*)::text
     from _sa_recreated x),
  ' / 7',
  'SA-061 the 7 re-created functions (sync_push, pin_session_capabilities, pos_order_snapshots, audit_action_has_detail, audit_safe_detail, owner_audit_events, audit_category) keep their exact signatures with one overload each');

select is(
  (select coalesce(string_agg(x.sig || ' acl=' || coalesce(p.proacl::text, 'NULL'), '; ' order by x.ord)
            filter (where p.proacl::text is distinct from x.pre_acl), '') || ' / ' || count(*)::text
     from _sa_recreated x left join pg_proc p on p.oid = to_regprocedure(x.sig)),
  ' / 7',
  'SA-062 their ACLs are exactly the PRE strings: six {postgres=X/postgres,authenticated=X/postgres}, app.audit_category {postgres=X/postgres}');

select is(
  (select coalesce(string_agg(x.sig || ' attr=' || case when p.prosecdef then 'definer' else 'invoker' end || ':'
                              || p.provolatile::text || ' cfg=' || coalesce(p.proconfig::text, 'null')
                              || ' owner=' || pg_get_userbyid(p.proowner)::text, '; ' order by x.ord)
            filter (where (case when p.prosecdef then 'definer' else 'invoker' end || ':' || p.provolatile::text) is distinct from x.pre_attr
                       or p.proconfig is distinct from array['search_path=""'] or pg_get_userbyid(p.proowner) <> 'postgres'), '')
          || ' / ' || count(*)::text
     from _sa_recreated x left join pg_proc p on p.oid = to_regprocedure(x.sig)),
  ' / 7',
  'SA-063 their PRE attributes are kept: DEFINER sync_push (VOLATILE), pin_session_capabilities / pos_order_snapshots / owner_audit_events (STABLE); INVOKER IMMUTABLE audit helpers; search_path pinned; owner postgres');

create temp table _sa_wrappers (ord integer primary key, sig text not null, pre_md5 text not null);
insert into _sa_wrappers values
  (1, 'public.sync_push(uuid,uuid,jsonb)', '68fcb0b3006e998b447861db6126f2c4'),
  (2, 'public.pin_session_capabilities(uuid,uuid)', '1fc46e8042a948a8ef804729f1b9ab36'),
  (3, 'public.pos_order_snapshots(uuid,uuid,timestamptz,uuid,timestamptz,uuid,uuid[],integer,integer)', '86c9ecf75aa474be5522074365c01ba1'),
  (4, 'public.owner_audit_events(uuid,uuid,uuid,text,text,text,boolean,uuid,uuid,integer,text)', '4979d1a0e0f629fb0dc1eb430be80068');

select is(
  (select coalesce(string_agg(x.sig || ' secdef=' || coalesce(p.prosecdef::text, 'missing') || ' acl=' || coalesce(p.proacl::text, 'NULL'), '; ' order by x.ord)
            filter (where p.prosecdef is distinct from false
                       or p.proacl::text is distinct from '{postgres=X/postgres,authenticated=X/postgres}'
                       or (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace
                              and q.proname = split_part(substr(x.sig, 8), '(', 1)) <> 1), '') || ' / ' || count(*)::text
     from _sa_wrappers x left join pg_proc p on p.oid = to_regprocedure(x.sig)),
  ' / 4',
  'SA-064 the public wrappers of the re-created functions (sync_push, pin_session_capabilities, pos_order_snapshots, owner_audit_events) stay SECURITY INVOKER, one overload each, ACL {postgres=X/postgres,authenticated=X/postgres}');

select is(
  (select coalesce(string_agg(x.sig || ' md5=' || coalesce(md5(replace(pg_get_functiondef(to_regprocedure(x.sig)), E'\r', '')), 'missing'),
                              '; ' order by x.ord)
            filter (where md5(replace(pg_get_functiondef(to_regprocedure(x.sig)), E'\r', '')) is distinct from x.pre_md5), '')
          || ' / ' || count(*)::text
     from _sa_wrappers x),
  ' / 4',
  'SA-065 the four public wrappers are untouched: their CR-normalized pg_get_functiondef md5 equals the PRE capture');

-- ===========================================================================
-- 7. N28: app.record_payment unchanged; app.sync_push is the only entry to
--    record_payment / close_shift; no other payments / shift-close writer.
-- ===========================================================================
select is(
  md5(replace(pg_get_functiondef(to_regprocedure('app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)')), E'\r', '')),
  'aa5d8e02311d8607bc88faf9bc27913b',
  'SA-066 N28: app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer) definition is byte-identical to PRE (CR-normalized md5 aa5d8e02311d8607bc88faf9bc27913b)');

select is(
  (select format('acl=%s secdef=%s overloads=%s', p.proacl::text, p.prosecdef::text,
                 (select count(*) from pg_proc q where q.pronamespace = 'app'::regnamespace and q.proname = 'record_payment'))
     from pg_proc p where p.oid = to_regprocedure('app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)')),
  'acl={postgres=X/postgres,authenticated=X/postgres} secdef=true overloads=1',
  'SA-067 N28: app.record_payment keeps its existing ACL {postgres=X/postgres,authenticated=X/postgres} (preserved and disclosed, not broadened), stays SECURITY DEFINER, one overload');

select is(
  (select coalesce(string_agg(p.proname::text, ', ' order by p.proname::text), '') from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('record_payment', 'close_shift', 'reconcile_shift')),
  '',
  'SA-068 N28: no public function named record_payment, close_shift or reconcile_shift exists');

select is(
  (select coalesce(string_agg(p.proname::text, ', ' order by p.proname::text), '') from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname in ('apply_discount', 'edit_order', 'add_order_items', 'void_order')),
  '',
  'SA-069 T-023: no public wrapper exists for the other guarded money arms either (apply_discount, edit_order, add_order_items, void_order)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name, ', ' order by s.nsp, s.name), '') from _sa_src s
    where s.src ~ 'app\.record_payment\s*\('
      and s.oid <> coalesce(to_regprocedure('app.record_payment(uuid,uuid,uuid,text,text,bigint,text,integer)')::oid, 0)),
  'app.sync_push',
  'SA-070 N28: the only function (any non-system schema) whose comment-stripped prosrc calls app.record_payment( is app.sync_push');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name, ', ' order by s.nsp, s.name), '') from _sa_src s
    where s.src ~ 'app\.close_shift\s*\('
      and s.oid <> coalesce(to_regprocedure('app.close_shift(uuid,uuid,uuid,text,bigint,text,integer)')::oid, 0)),
  'app.sync_push',
  'SA-071 N28: the only function (any non-system schema) whose comment-stripped prosrc calls app.close_shift( is app.sync_push');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name, ', ' order by s.nsp, s.name), '') from _sa_src s
    where s.src ~ 'app\.reconcile_shift\s*\('
      and s.oid <> coalesce(to_regprocedure('app.reconcile_shift(uuid,uuid,uuid,text,text,integer)')::oid, 0)),
  '',
  'SA-072 N28: no function (any non-system schema) calls app.reconcile_shift( in its comment-stripped prosrc (no wrapper, no other caller)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name, ', ' order by s.nsp, s.name), '') from _sa_src s
    where s.src ~* 'update\s+(only\s+)?(public\.)?shifts\M[^;]*\mstatus\s*=\s*''closed'''),
  'app.close_shift',
  'SA-073 N28: the only function (any non-system schema) whose comment-stripped prosrc updates public.shifts to status ''closed'' is app.close_shift');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name, ', ' order by s.nsp, s.name), '') from _sa_src s
    where s.src ~* '\m(insert\s+into|update|delete\s+from|merge\s+into|truncate(\s+table)?)\s+(only\s+)?(public\.)?payments\M'),
  'app.record_payment',
  'SA-074 N28: the only function (any non-system schema) that writes public.payments (insert / update / delete / merge / truncate) is app.record_payment');

select is(
  (select string_agg(x.sig || ' md5=' || coalesce(md5(replace(pg_get_functiondef(to_regprocedure(x.sig)), E'\r', '')), 'missing')
                     || ' acl=' || coalesce((select p.proacl::text from pg_proc p where p.oid = to_regprocedure(x.sig)), 'NULL'), '; ' order by x.ord)
     from (values (1, 'app.close_shift(uuid,uuid,uuid,text,bigint,text,integer)'),
                  (2, 'app.reconcile_shift(uuid,uuid,uuid,text,text,integer)')) x(ord, sig)),
  'app.close_shift(uuid,uuid,uuid,text,bigint,text,integer) md5=6b5f7226047d0214ae753b3b362857a8 acl={postgres=X/postgres,authenticated=X/postgres}; '
  || 'app.reconcile_shift(uuid,uuid,uuid,text,text,integer) md5=d4243c576175c9875762316d7c32a297 acl={postgres=X/postgres,authenticated=X/postgres}',
  'SA-075 app.close_shift and app.reconcile_shift are not re-created: definitions (CR-normalized md5) and ACLs equal the PRE capture');

-- ===========================================================================
-- 7b. Internal-only reachability (API 4.55.10): who calls the guards, the
--     lock helpers and the session proof.
-- ===========================================================================
select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name || ' x' || (select count(*) from regexp_matches(s.src, 'app\.card_claim_guard\s*\(', 'g'))::text,
                              ', ' order by s.nsp, s.name), '')
     from _sa_src s where s.src ~ 'app\.card_claim_guard\s*\('),
  'app.sync_push x6',
  'SA-076 app.card_claim_guard is called only by app.sync_push, at six call sites (the six guarded arms of packet 6 change 1)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name || ' x' || (select count(*) from regexp_matches(s.src, 'app\.card_recording_resume_guard\s*\(', 'g'))::text,
                              ', ' order by s.nsp, s.name), '')
     from _sa_src s where s.src ~ 'app\.card_recording_resume_guard\s*\('),
  'app.sync_push x1',
  'SA-077 app.card_recording_resume_guard is called only by app.sync_push (one call site, the valid-path terminal replay)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name || ' x' || (select count(*) from regexp_matches(s.src, 'app\.card_identity_lock\s*\(', 'g'))::text,
                              ', ' order by s.nsp collate "C", s.name collate "C"), '')
     from _sa_src s where s.src ~ 'app\.card_identity_lock\s*\('),
  'app.card_attempt_claim x1, app.sync_push x2',
  'SA-078 app.card_identity_lock is called only by app.card_attempt_claim and app.sync_push (both sync_push paths: two call sites)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name || ' x' || (select count(*) from regexp_matches(s.src, 'app\.card_terminal_lock\s*\(', 'g'))::text,
                              ', ' order by s.nsp collate "C", s.name collate "C"), '')
     from _sa_src s where s.src ~ 'app\.card_terminal_lock\s*\('),
  'app.card_attempt_claim x1, app.purge_expired_test_card_attempts x1, app.set_payment_terminal x1, app.sync_push x1',
  'SA-079 app.card_terminal_lock is called only by app.card_attempt_claim, app.purge_expired_test_card_attempts, app.set_payment_terminal and app.sync_push (one call site each)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name, ', ' order by s.nsp collate "C", s.name collate "C"), '')
     from _sa_src s where s.src ~ 'app\.card_attempt_proof\s*\('),
  'app.card_attempt_adapter_read, app.card_attempt_claim, app.card_attempt_context, app.card_attempt_free_order, '
  || 'app.card_attempt_mark_recording_result, app.card_attempt_mark_release_requested',
  'SA-080 the PIN-session / device proof app.card_attempt_proof is re-run by the context proof and every service-only body except the scope-bound card_attempt_finish');

-- ===========================================================================
-- 8. Keys, partial unique indexes, CHECKs, FKs and triggers by name.
-- ===========================================================================
select set_eq(
  $$select conname::text, contype::text, pg_get_constraintdef(oid) from pg_constraint
     where conrelid = to_regclass('app.card_provider_attempts') and contype in ('p', 'u')$$,
  $$values ('card_provider_attempts_pkey', 'p', 'PRIMARY KEY (id)'),
           ('card_attempts_identity', 'u', 'UNIQUE (organization_id, device_id, local_operation_id)'),
           ('card_attempts_status_digest_key', 'u', 'UNIQUE (provider_status_digest)'),
           ('card_attempts_duplicate_digest_key', 'u', 'UNIQUE (provider_duplicate_digest)'),
           ('card_attempts_query_key_key', 'u', 'UNIQUE (provider_query_key)'),
           ('card_attempts_duplicate_key_key', 'u', 'UNIQUE (provider_duplicate_key)')$$,
  'SA-081 card_provider_attempts keys: PK (id); card_attempts_identity UNIQUE (organization_id, device_id, local_operation_id); ledger-wide UNIQUE status / duplicate digests and query / duplicate keys');

select set_eq(
  $$select conrelid::regclass::text, conname::text, pg_get_constraintdef(oid) from pg_constraint
     where conname in ('card_attempts_local_operation_id', 'card_tombstones_local_operation_id')$$,
  $$values ('app.card_provider_attempts', 'card_attempts_local_operation_id',
            'CHECK ((local_operation_id ~ ''^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$''::text))'),
           ('app.card_attempt_identity_tombstones', 'card_tombstones_local_operation_id',
            'CHECK ((local_operation_id ~ ''^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$''::text))')$$,
  'SA-082 card_attempts_local_operation_id and card_tombstones_local_operation_id CHECK the canonical lowercase UUID v4 text form');

select is(
  pg_get_indexdef(to_regclass('app.card_attempts_one_claim_per_order')),
  $q$CREATE UNIQUE INDEX card_attempts_one_claim_per_order ON app.card_provider_attempts USING btree (organization_id, order_id) WHERE ((order_freed_at IS NULL) AND (state = ANY (ARRAY['sent'::text, 'unknown'::text, 'released'::text, 'approved'::text])))$q$,
  'SA-083 card_attempts_one_claim_per_order is a partial UNIQUE (organization_id, order_id) WHERE order_freed_at IS NULL AND state IN (sent, unknown, released, approved)');

select is(
  pg_get_indexdef(to_regclass('app.payment_terminals_one_current_per_device')),
  $q$CREATE UNIQUE INDEX payment_terminals_one_current_per_device ON app.payment_terminals USING btree (organization_id, device_id) WHERE ((deleted_at IS NULL) AND (lifecycle <> 'retired'::text))$q$,
  'SA-084 payment_terminals_one_current_per_device is a partial UNIQUE (organization_id, device_id) WHERE deleted_at IS NULL AND lifecycle <> retired');

select is(
  pg_get_indexdef(to_regclass('app.payment_terminals_one_admitting_per_org')),
  $q$CREATE UNIQUE INDEX payment_terminals_one_admitting_per_org ON app.payment_terminals USING btree (organization_id) WHERE (lifecycle = ANY (ARRAY['enabled'::text, 'draining'::text]))$q$,
  'SA-085 payment_terminals_one_admitting_per_org is a partial UNIQUE (organization_id) WHERE lifecycle IN (enabled, draining)');

select is(
  pg_get_indexdef(to_regclass('app.card_events_one_test_recording_refusal')),
  $q$CREATE UNIQUE INDEX card_events_one_test_recording_refusal ON app.card_provider_private_events USING btree (attempt_row_id) WHERE (action = 'test.card_recording_refused'::text)$q$,
  'SA-086 card_events_one_test_recording_refusal is a partial UNIQUE (attempt_row_id) WHERE action = test.card_recording_refused');

select is(
  pg_get_indexdef(to_regclass('app.card_events_one_field_drop')),
  $q$CREATE UNIQUE INDEX card_events_one_field_drop ON app.card_provider_private_events USING btree (attempt_row_id, ((detail ->> 'field'::text)), ((detail ->> 'rule'::text))) WHERE (action = 'security.card_provider_field_dropped'::text)$q$,
  'SA-087 card_events_one_field_drop is a partial UNIQUE (attempt_row_id, detail->>field, detail->>rule) WHERE action = security.card_provider_field_dropped');

select set_eq(
  $$select conname::text, contype::text, pg_get_constraintdef(oid) from pg_constraint
     where conrelid = to_regclass('app.card_attempt_identity_tombstones') and contype in ('p', 'u')$$,
  $$values ('card_attempt_identity_tombstones_pkey', 'p', 'PRIMARY KEY (organization_id, device_id, local_operation_id)'),
           ('card_tombstones_status_digest_key', 'u', 'UNIQUE (provider_status_digest)'),
           ('card_tombstones_duplicate_digest_key', 'u', 'UNIQUE (provider_duplicate_digest)'),
           ('card_tombstones_query_key_key', 'u', 'UNIQUE (provider_query_key)'),
           ('card_tombstones_duplicate_key_key', 'u', 'UNIQUE (provider_duplicate_key)')$$,
  'SA-088 card_attempt_identity_tombstones keys: PK (organization_id, device_id, local_operation_id) and the card_tombstones_* UNIQUE digests and outbound keys');

select set_eq(
  $$select tgname::text, pg_get_triggerdef(oid) from pg_trigger
     where tgrelid in (select to_regclass('app.' || t) from _sa_tables) and not tgisinternal$$,
  $$values
    ('card_attempts_guard', 'CREATE TRIGGER card_attempts_guard BEFORE DELETE OR UPDATE ON app.card_provider_attempts FOR EACH ROW EXECUTE FUNCTION app.card_attempts_guard()'),
    ('card_attempts_insert_guard', 'CREATE TRIGGER card_attempts_insert_guard BEFORE INSERT ON app.card_provider_attempts FOR EACH ROW EXECUTE FUNCTION app.card_attempts_insert_guard()'),
    ('card_attempts_no_truncate', 'CREATE TRIGGER card_attempts_no_truncate BEFORE TRUNCATE ON app.card_provider_attempts FOR EACH STATEMENT EXECUTE FUNCTION app.card_append_only_guard()'),
    ('card_events_guard', 'CREATE TRIGGER card_events_guard BEFORE DELETE OR UPDATE ON app.card_provider_private_events FOR EACH ROW EXECUTE FUNCTION app.card_events_guard()'),
    ('card_events_no_truncate', 'CREATE TRIGGER card_events_no_truncate BEFORE TRUNCATE ON app.card_provider_private_events FOR EACH STATEMENT EXECUTE FUNCTION app.card_append_only_guard()'),
    ('card_pilot_revisions_append_only', 'CREATE TRIGGER card_pilot_revisions_append_only BEFORE DELETE OR UPDATE ON app.card_payments_pilot_revisions FOR EACH ROW EXECUTE FUNCTION app.card_append_only_guard()'),
    ('card_pilot_revisions_no_truncate', 'CREATE TRIGGER card_pilot_revisions_no_truncate BEFORE TRUNCATE ON app.card_payments_pilot_revisions FOR EACH STATEMENT EXECUTE FUNCTION app.card_append_only_guard()'),
    ('card_tombstones_append_only', 'CREATE TRIGGER card_tombstones_append_only BEFORE DELETE OR UPDATE ON app.card_attempt_identity_tombstones FOR EACH ROW EXECUTE FUNCTION app.card_append_only_guard()'),
    ('card_tombstones_no_truncate', 'CREATE TRIGGER card_tombstones_no_truncate BEFORE TRUNCATE ON app.card_attempt_identity_tombstones FOR EACH STATEMENT EXECUTE FUNCTION app.card_append_only_guard()'),
    ('payment_terminals_guard', 'CREATE TRIGGER payment_terminals_guard BEFORE INSERT OR DELETE OR UPDATE ON app.payment_terminals FOR EACH ROW EXECUTE FUNCTION app.payment_terminals_guard()'),
    ('payment_terminals_no_truncate', 'CREATE TRIGGER payment_terminals_no_truncate BEFORE TRUNCATE ON app.payment_terminals FOR EACH STATEMENT EXECUTE FUNCTION app.card_append_only_guard()')$$,
  'SA-089 the triggers of the five tables are exactly card_attempts_guard, card_attempts_insert_guard, payment_terminals_guard, card_events_guard and the append-only / no-truncate set (timing, events, level, function pinned)');

select is(
  (select coalesce(string_agg(tgname::text || ':' || tgenabled::text, ',' order by tgname::text) filter (where tgenabled not in ('O', 'A')), '')
          || ' / ' || count(*)::text
     from pg_trigger where tgrelid in (select to_regclass('app.' || t) from _sa_tables) and not tgisinternal),
  ' / 11',
  'SA-090 all 11 triggers are enabled (fire in ordinary sessions)');

select set_eq(
  $$select conname::text, pg_get_constraintdef(oid) from pg_constraint
     where conrelid in (select to_regclass('app.' || t) from _sa_tables)
       and conname in ('card_pilot_revisions_pilot_scope', 'card_pilot_revisions_mode', 'payment_terminals_lifecycle',
                       'payment_terminals_mode', 'card_attempts_mode', 'card_attempts_state')$$,
  $$values
    ('card_pilot_revisions_pilot_scope', 'CHECK (((organization_id = ''20605c2b-3145-4803-a990-bbec3d9c1096''::uuid) AND (restaurant_id = ''de3bbc64-edad-4ff4-bccd-c2ef217c1d56''::uuid) AND (branch_id = ''2847c0be-3e31-45a5-957c-508729f1971e''::uuid)))'),
    ('card_pilot_revisions_mode', 'CHECK ((mode = ANY (ARRAY[''test''::text, ''live''::text])))'),
    ('payment_terminals_lifecycle', 'CHECK ((lifecycle = ANY (ARRAY[''configured''::text, ''enabled''::text, ''draining''::text, ''retired''::text])))'),
    ('payment_terminals_mode', 'CHECK ((mode = ANY (ARRAY[''test''::text, ''live''::text])))'),
    ('card_attempts_mode', 'CHECK ((mode = ANY (ARRAY[''test''::text, ''live''::text])))'),
    ('card_attempts_state', 'CHECK ((state = ANY (ARRAY[''sent''::text, ''approved''::text, ''declined''::text, ''unknown''::text, ''released''::text])))')$$,
  'SA-091 contract token CHECKs: the revision store pinned to the Maps Burger pilot scope; lifecycle configured / enabled / draining / retired; modes test / live; states sent / approved / declined / unknown / released');

select set_eq(
  $$select conrelid::regclass::text, conname::text from pg_constraint
     where conrelid in (select to_regclass('app.' || t) from _sa_tables) and contype = 'c'$$,
  $$values
    ('app.card_provider_attempts', 'card_attempts_amount'), ('app.card_provider_attempts', 'card_attempts_anomaly'),
    ('app.card_provider_attempts', 'card_attempts_charge_may_exist'), ('app.card_provider_attempts', 'card_attempts_confirmation'),
    ('app.card_provider_attempts', 'card_attempts_confirmation_text'), ('app.card_provider_attempts', 'card_attempts_currency'),
    ('app.card_provider_attempts', 'card_attempts_digests'), ('app.card_provider_attempts', 'card_attempts_freed'),
    ('app.card_provider_attempts', 'card_attempts_hold'), ('app.card_provider_attempts', 'card_attempts_key_version'),
    ('app.card_provider_attempts', 'card_attempts_keys'), ('app.card_provider_attempts', 'card_attempts_live_shape'),
    ('app.card_provider_attempts', 'card_attempts_local_operation_id'), ('app.card_provider_attempts', 'card_attempts_mode'),
    ('app.card_provider_attempts', 'card_attempts_poll'), ('app.card_provider_attempts', 'card_attempts_provider_fields'),
    ('app.card_provider_attempts', 'card_attempts_refs'), ('app.card_provider_attempts', 'card_attempts_refusal_code'),
    ('app.card_provider_attempts', 'card_attempts_resolution'), ('app.card_provider_attempts', 'card_attempts_resolution_text'),
    ('app.card_provider_attempts', 'card_attempts_resume'), ('app.card_provider_attempts', 'card_attempts_return_class'),
    ('app.card_provider_attempts', 'card_attempts_state'), ('app.card_provider_attempts', 'card_attempts_test_shape'),
    ('app.card_provider_private_events', 'card_events_action'), ('app.card_provider_private_events', 'card_events_actor_kind'),
    ('app.card_provider_private_events', 'card_events_actor_reference'), ('app.card_provider_private_events', 'card_events_adapter'),
    ('app.card_provider_private_events', 'card_events_detail'), ('app.card_provider_private_events', 'card_events_hold'),
    ('app.card_provider_private_events', 'card_events_mode'), ('app.card_provider_private_events', 'card_events_operator'),
    ('app.card_provider_private_events', 'card_events_reason'), ('app.card_provider_private_events', 'card_events_retention'),
    ('app.card_provider_private_events', 'card_events_test_device'),
    ('app.card_payments_pilot_revisions', 'card_pilot_revisions_executor'), ('app.card_payments_pilot_revisions', 'card_pilot_revisions_live_cap'),
    ('app.card_payments_pilot_revisions', 'card_pilot_revisions_mode'), ('app.card_payments_pilot_revisions', 'card_pilot_revisions_operator_reference'),
    ('app.card_payments_pilot_revisions', 'card_pilot_revisions_pilot_scope'), ('app.card_payments_pilot_revisions', 'card_pilot_revisions_reason'),
    ('app.card_payments_pilot_revisions', 'card_pilot_revisions_test_cap'),
    ('app.card_attempt_identity_tombstones', 'card_tombstones_digests'), ('app.card_attempt_identity_tombstones', 'card_tombstones_key_version'),
    ('app.card_attempt_identity_tombstones', 'card_tombstones_keys'), ('app.card_attempt_identity_tombstones', 'card_tombstones_local_operation_id'),
    ('app.payment_terminals', 'payment_terminals_credential_ref'), ('app.payment_terminals', 'payment_terminals_lifecycle'),
    ('app.payment_terminals', 'payment_terminals_mode'), ('app.payment_terminals', 'payment_terminals_refs_distinct'),
    ('app.payment_terminals', 'payment_terminals_terminal_ref')$$,
  'SA-092 the CHECK constraint set of the five tables is exactly the 51 named DOMAIN rules (TEST / LIVE shape, digests, keys, formatter version, field rules, tokens, scope, caps, event rules; C1-3 added card_events_test_device)');

select set_eq(
  $$select conrelid::regclass::text, pg_get_constraintdef(oid) from pg_constraint
     where conrelid in (select to_regclass('app.' || t) from _sa_tables) and contype = 'f'$$,
  $$values
    ('app.card_payments_pilot_revisions', 'FOREIGN KEY (organization_id, restaurant_id, branch_id) REFERENCES branches(organization_id, restaurant_id, id) ON DELETE RESTRICT'),
    ('app.payment_terminals', 'FOREIGN KEY (organization_id, restaurant_id, branch_id) REFERENCES branches(organization_id, restaurant_id, id) ON DELETE RESTRICT'),
    ('app.payment_terminals', 'FOREIGN KEY (organization_id, restaurant_id, branch_id, device_id) REFERENCES devices(organization_id, restaurant_id, branch_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_attempts', 'FOREIGN KEY (organization_id, restaurant_id, branch_id) REFERENCES branches(organization_id, restaurant_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_attempts', 'FOREIGN KEY (organization_id, restaurant_id, branch_id, device_id) REFERENCES devices(organization_id, restaurant_id, branch_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_attempts', 'FOREIGN KEY (organization_id, order_id) REFERENCES orders(organization_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_attempts', 'FOREIGN KEY (organization_id, shift_id) REFERENCES shifts(organization_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_attempts', 'FOREIGN KEY (organization_id, cash_drawer_session_id) REFERENCES cash_drawer_sessions(organization_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_attempts', 'FOREIGN KEY (organization_id, initiated_by_employee_profile_id) REFERENCES employee_profiles(organization_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_attempts', 'FOREIGN KEY (organization_id, initiated_by_membership_id) REFERENCES memberships(organization_id, id) ON DELETE RESTRICT'),
    ('app.card_provider_private_events', 'FOREIGN KEY (organization_id, restaurant_id, branch_id) REFERENCES branches(organization_id, restaurant_id, id) ON DELETE RESTRICT')$$,
  'SA-093 composite same-organization FKs exactly as DOMAIN: ledger to branches / devices / orders / shifts / drawers / employee / membership; binding to branches / devices; events and revisions to branches only (no FK on attempt_row_id); tombstones none');

-- ===========================================================================
-- 9. card_safe_text_ok attributes; the lock helpers refuse an incomplete key.
-- ===========================================================================
select is(
  (select string_agg(x.sig || '=' || coalesce(p.provolatile::text || case when p.prosecdef then ':definer' else ':invoker' end, 'missing'),
                     ', ' order by x.ord)
     from (values (1, 'app.card_safe_text_ok(text,text)'), (2, 'app.card_safe_text_failure(text,text)'),
                  (3, 'app.card_text_canonical(text)')) x(ord, sig)
     left join pg_proc p on p.oid = to_regprocedure(x.sig)),
  'app.card_safe_text_ok(text,text)=i:invoker, app.card_safe_text_failure(text,text)=i:invoker, app.card_text_canonical(text)=i:invoker',
  'SA-094 app.card_safe_text_ok is IMMUTABLE and SECURITY INVOKER (so are its rule helper card_safe_text_failure and card_text_canonical, packet 3.2)');

select throws_ok(
  $$select app.card_identity_lock(null, pg_temp.zc_id('sa-lock-device'), pg_temp.zc_lop('sa-lock'))$$, '22004', null,
  'SA-095 app.card_identity_lock raises 22004 when organization_id is NULL (never a silent no-lock)');
select throws_ok(
  $$select app.card_identity_lock(pg_temp.zc_id('sa-lock-org'), null, pg_temp.zc_lop('sa-lock'))$$, '22004', null,
  'SA-096 app.card_identity_lock raises 22004 when device_id is NULL');
select throws_ok(
  $$select app.card_identity_lock(pg_temp.zc_id('sa-lock-org'), pg_temp.zc_id('sa-lock-device'), null)$$, '22004', null,
  'SA-097 app.card_identity_lock raises 22004 when local_operation_id is NULL');
select throws_ok(
  $$select app.card_terminal_lock(null, pg_temp.zc_id('sa-lock-device'))$$, '22004', null,
  'SA-098 app.card_terminal_lock raises 22004 when organization_id is NULL');
select throws_ok(
  $$select app.card_terminal_lock(pg_temp.zc_id('sa-lock-org'), null)$$, '22004', null,
  'SA-099 app.card_terminal_lock raises 22004 when device_id is NULL');

select lives_ok(
  $$select app.card_identity_lock(pg_temp.zc_id('sa-lock-org'), pg_temp.zc_id('sa-lock-device'), pg_temp.zc_lop('sa-lock')),
           app.card_terminal_lock(pg_temp.zc_id('sa-lock-org'), pg_temp.zc_id('sa-lock-device'))$$,
  'SA-100 with a complete key both lock helpers succeed (owner session)');

select is(
  (select coalesce(string_agg(k.label, ',' order by k.label), '')
     from (values
       ('identity', hashtextextended('card-identity/v1:' || pg_temp.zc_id('sa-lock-org')::text || ':'
                                     || pg_temp.zc_id('sa-lock-device')::text || ':' || pg_temp.zc_lop('sa-lock'), 0)),
       ('terminal', hashtextextended('card-terminal/v1:' || pg_temp.zc_id('sa-lock-org')::text || ':'
                                     || pg_temp.zc_id('sa-lock-device')::text, 0))) k(label, key)
    where exists (select 1 from pg_locks l
                   where l.pid = pg_backend_pid() and l.locktype = 'advisory' and l.mode = 'ExclusiveLock' and l.granted
                     and l.objsubid = 1 and l.classid::bigint = ((k.key >> 32) & 4294967295)
                     and l.objid::bigint = (k.key & 4294967295))),
  'identity,terminal',
  'SA-101 the helpers hold transaction-scoped EXCLUSIVE advisory locks on exactly the documented card-identity/v1:org:device:id and card-terminal/v1:org:device keys');

-- ===========================================================================
-- 10. Review fixes 14 and 2 (packet 3.2): the two new internal helpers.
--     app.card_text_absent(text) is the linear M4 absent test (IMMUTABLE,
--     SECURITY INVOKER); app.card_proof_denial_evidence(jsonb, uuid, text,
--     text) writes a mark's proof-level denial evidence (SECURITY DEFINER).
--     Neither is granted to any app role or exposed on the public layer; each
--     is called exactly where its review fix says.
-- ===========================================================================
select is(
  (select format('overloads=%s vol=%s secdef=%s search_path_empty=%s owner=%s returns=%s',
                 (select count(*) from pg_proc q where q.pronamespace = 'app'::regnamespace
                     and q.proname = 'card_text_absent'),
                 p.provolatile, p.prosecdef::text, (p.proconfig = array['search_path=""'])::text,
                 pg_get_userbyid(p.proowner), pg_get_function_result(p.oid))
     from pg_proc p where p.oid = to_regprocedure('app.card_text_absent(text)')),
  'overloads=1 vol=i secdef=false search_path_empty=true owner=postgres returns=boolean',
  'SA-102 review fix 14: app.card_text_absent(text) exists once in app, IMMUTABLE, SECURITY INVOKER, proconfig {search_path=""}, owner postgres, returns boolean');

select is(
  (select format('acl=%s public_execute=%s anon=%s authenticated=%s service_role=%s public_layer=%s',
                 coalesce(p.proacl::text, 'NULL'),
                 (exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text,
                 has_function_privilege('anon', p.oid, 'EXECUTE')::text,
                 has_function_privilege('authenticated', p.oid, 'EXECUTE')::text,
                 has_function_privilege('service_role', p.oid, 'EXECUTE')::text,
                 (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace
                     and q.proname = 'card_text_absent'))
     from pg_proc p where p.oid = to_regprocedure('app.card_text_absent(text)')),
  'acl={postgres=X/postgres} public_execute=false anon=false authenticated=false service_role=false public_layer=0',
  'SA-103 review fix 14: app.card_text_absent is executable by no app role on either layer: ACL exactly {postgres=X/postgres} (no EXECUTE for PUBLIC, anon, authenticated or service_role) and no public.card_text_absent of any signature exists');

set local role anon;
insert into _sa_r select 'absent-anon', jsonb_build_object(
  'app', pg_temp.sa_probe('select app.card_text_absent((select null::text))'),
  'public', pg_temp.sa_probe('select public.card_text_absent((select null::text))'));
reset role;
set local role authenticated;
insert into _sa_r select 'absent-authenticated', jsonb_build_object(
  'app', pg_temp.sa_probe('select app.card_text_absent((select null::text))'),
  'public', pg_temp.sa_probe('select public.card_text_absent((select null::text))'));
reset role;
set local role service_role;
insert into _sa_r select 'absent-service_role', jsonb_build_object(
  'app', pg_temp.sa_probe('select app.card_text_absent((select null::text))'),
  'public', pg_temp.sa_probe('select public.card_text_absent((select null::text))'));
reset role;
insert into _sa_r select 'absent-owner', jsonb_build_object(
  'app', pg_temp.sa_probe('select app.card_text_absent((select null::text))'));
select is(
  (select jsonb_object_agg(label, r) from _sa_r where label like 'absent-%'),
  jsonb_build_object(
    'absent-anon', jsonb_build_object('app', 'denied', 'public', 'unresolved:42883'),
    'absent-authenticated', jsonb_build_object('app', 'denied', 'public', 'unresolved:42883'),
    'absent-service_role', jsonb_build_object('app', 'denied', 'public', 'unresolved:42883'),
    'absent-owner', jsonb_build_object('app', 'passed')),
  'SA-104 review fix 14: at runtime AS anon, authenticated and service_role a call of app.card_text_absent(text) is refused 42501 by the privilege layer and public.card_text_absent(text) does not resolve (42883); the identical call of the owner session passes (non-vacuous probe)');

select is(
  (select format('overloads=%s vol=%s secdef=%s search_path_empty=%s owner=%s returns=%s',
                 (select count(*) from pg_proc q where q.pronamespace = 'app'::regnamespace
                     and q.proname = 'card_proof_denial_evidence'),
                 p.provolatile, p.prosecdef::text, (p.proconfig = array['search_path=""'])::text,
                 pg_get_userbyid(p.proowner), pg_get_function_result(p.oid))
     from pg_proc p where p.oid = to_regprocedure('app.card_proof_denial_evidence(jsonb,uuid,text,text)')),
  'overloads=1 vol=v secdef=true search_path_empty=true owner=postgres returns=void',
  'SA-105 review fix 2: app.card_proof_denial_evidence(jsonb, uuid, text, text) exists once in app, SECURITY DEFINER, VOLATILE (it writes the denial evidence), proconfig {search_path=""}, owner postgres, returns void');

select is(
  (select format('acl=%s public_execute=%s anon=%s authenticated=%s service_role=%s public_layer=%s',
                 coalesce(p.proacl::text, 'NULL'),
                 (exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text,
                 has_function_privilege('anon', p.oid, 'EXECUTE')::text,
                 has_function_privilege('authenticated', p.oid, 'EXECUTE')::text,
                 has_function_privilege('service_role', p.oid, 'EXECUTE')::text,
                 (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace
                     and q.proname = 'card_proof_denial_evidence'))
     from pg_proc p where p.oid = to_regprocedure('app.card_proof_denial_evidence(jsonb,uuid,text,text)')),
  'acl={postgres=X/postgres} public_execute=false anon=false authenticated=false service_role=false public_layer=0',
  'SA-106 review fix 2: app.card_proof_denial_evidence has no grant: ACL exactly {postgres=X/postgres} (no EXECUTE for PUBLIC, anon, authenticated or service_role) and no public.card_proof_denial_evidence of any signature exists');

-- The typed all-NULL call of the denial-evidence helper (each NULL a scalar sub-select, as in _sa_fn.call_sql).
create temp table _sa_pde (app_call text, public_call text);
insert into _sa_pde values (
  'select app.card_proof_denial_evidence((select null::jsonb), (select null::uuid), (select null::text), (select null::text))',
  'select public.card_proof_denial_evidence((select null::jsonb), (select null::uuid), (select null::text), (select null::text))');
grant select on _sa_pde to anon, authenticated, service_role;
set local role anon;
insert into _sa_r select 'proof-evidence-anon', jsonb_build_object(
  'app', pg_temp.sa_probe(app_call), 'public', pg_temp.sa_probe(public_call)) from _sa_pde;
reset role;
set local role authenticated;
insert into _sa_r select 'proof-evidence-authenticated', jsonb_build_object(
  'app', pg_temp.sa_probe(app_call), 'public', pg_temp.sa_probe(public_call)) from _sa_pde;
reset role;
set local role service_role;
insert into _sa_r select 'proof-evidence-service_role', jsonb_build_object(
  'app', pg_temp.sa_probe(app_call), 'public', pg_temp.sa_probe(public_call)) from _sa_pde;
reset role;
insert into _sa_r select 'proof-evidence-owner', jsonb_build_object('app', pg_temp.sa_probe(app_call)) from _sa_pde;
select is(
  (select jsonb_object_agg(label, r) from _sa_r where label like 'proof-evidence-%'),
  jsonb_build_object(
    'proof-evidence-anon', jsonb_build_object('app', 'denied', 'public', 'unresolved:42883'),
    'proof-evidence-authenticated', jsonb_build_object('app', 'denied', 'public', 'unresolved:42883'),
    'proof-evidence-service_role', jsonb_build_object('app', 'denied', 'public', 'unresolved:42883'),
    'proof-evidence-owner', jsonb_build_object('app', 'passed')),
  'SA-107 review fix 2: at runtime AS anon, authenticated and service_role a call of app.card_proof_denial_evidence is refused 42501 by the privilege layer and public.card_proof_denial_evidence does not resolve (42883); the identical call of the owner session passes (non-vacuous probe)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name || ' x' || (select count(*) from regexp_matches(s.src, 'app\.card_proof_denial_evidence\s*\(', 'g'))::text,
                              ', ' order by s.nsp collate "C", s.name collate "C"), '')
     from _sa_src s where s.src ~ 'app\.card_proof_denial_evidence\s*\('),
  'app.card_attempt_mark_recording_result x1, app.card_attempt_mark_release_requested x1',
  'SA-108 review fix 2: app.card_proof_denial_evidence is called only by the two marks (card_attempt_mark_recording_result and card_attempt_mark_release_requested), one call site each');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name || ' x' || (select count(*) from regexp_matches(s.src, 'app\.card_text_absent\s*\(', 'g'))::text,
                              ', ' order by s.nsp collate "C", s.name collate "C"), '')
     from _sa_src s where s.src ~ 'app\.card_text_absent\s*\('),
  'app.card_attempt_finish x2, app.card_attempt_free_order x2, app.card_attempt_resolve_orphan x1, '
  || 'app.card_attempt_set_incident_hold x1, app.purge_expired_test_card_attempts x1, app.set_card_payments_pilot x1, '
  || 'app.set_payment_terminal x1',
  'SA-109 review fix 14: app.card_text_absent is called exactly by card_attempt_finish (the provider-field loop and provider_return_class: 2 sites), card_attempt_free_order (reason and confirmation_reference: 2 sites) and the five operator RPCs (operator_reference: 1 site each), and by no other function');

-- ===========================================================================
-- 11. Correction C1 catalog facts (D-059): the snapshot watermark column
--     claim_signal_at (C1-1), the TEST-event device CHECK and the bounded
--     purge signature (C1-3). No function is added and no grant or public
--     wrapper changes (pre-C1 capture = candidate 2e011ea5).
-- ===========================================================================
select is(
  (select format('type=%s not_null=%s default=%s column_acl=%s', c.data_type, c.is_nullable, c.column_default,
                 coalesce((select a.attacl::text from pg_attribute a
                            where a.attrelid = 'app.card_provider_attempts'::regclass and a.attname = 'claim_signal_at'),
                          'NULL'))
     from information_schema.columns c
    where c.table_schema = 'app' and c.table_name = 'card_provider_attempts' and c.column_name = 'claim_signal_at'),
  'type=timestamp with time zone not_null=NO default=clock_timestamp() column_acl=NULL',
  'SA-110 C1-1: app.card_provider_attempts.claim_signal_at is timestamptz NOT NULL DEFAULT clock_timestamp() and carries no column-level ACL');

select is(
  (select coalesce(string_agg(r.role || ':' || p.priv, ', ' order by r.role, p.priv)
            filter (where has_column_privilege(r.role, a.attrelid, a.attnum, p.priv)), '')
          || ' / ' || count(*)::text
     from pg_attribute a
     cross join (values ('public'), ('anon'), ('authenticated'), ('service_role')) r(role)
     cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('REFERENCES')) p(priv)
    where a.attrelid = 'app.card_provider_attempts'::regclass and a.attname = 'claim_signal_at' and not a.attisdropped),
  ' / 16',
  'SA-111 C1-1: no grant reaches the new column - PUBLIC, anon, authenticated and service_role hold no SELECT / INSERT / UPDATE / REFERENCES on claim_signal_at (16 checks)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name, ', ' order by s.nsp collate "C", s.name collate "C"), '')
     from _sa_src s where s.src ~ 'claim_signal_at'),
  'app.card_attempts_guard, app.card_attempts_insert_guard, app.pos_order_snapshots',
  'SA-112 C1-1: claim_signal_at is named (comment-stripped source, any non-system schema) only by the two ledger guard triggers (the insert stamp; keep or advance on update) and by its one reader app.pos_order_snapshots - no RPC body writes it');

select is(
  (select format('max_claim_signal=%s max_updated_at=%s same_branch=%s',
                 (s.src ~ 'max\(ca\.claim_signal_at\)')::text, (s.src ~ 'max\(ca\.updated_at\)')::text,
                 (s.src ~ 'ca\.branch_id\s*=\s*o\.branch_id')::text)
     from _sa_src s
    where s.oid = to_regprocedure('app.pos_order_snapshots(uuid,uuid,timestamptz,uuid,timestamptz,uuid,uuid[],integer,integer)')),
  'max_claim_signal=true max_updated_at=false same_branch=true',
  'SA-113 C1-1: app.pos_order_snapshots joins max(claim_signal_at) of the order''s LIVE attempts of the same branch into sync_at (its comment-stripped source no longer aggregates the attempts'' updated_at)');

select is(
  (select format('%s %s validated=%s no_inherit=%s', c.conrelid::regclass::text, pg_get_constraintdef(c.oid),
                 c.convalidated::text, c.connoinherit::text)
     from pg_constraint c where c.conname = 'card_events_test_device'),
  'app.card_provider_private_events CHECK (((mode IS DISTINCT FROM ''test''::text) OR (device_id IS NOT NULL))) validated=true no_inherit=false',
  'SA-114 C1-3: CHECK card_events_test_device on app.card_provider_private_events is exactly (mode IS DISTINCT FROM test OR device_id IS NOT NULL), validated');

select is(
  (select format('identity=(%s) args=(%s) nargs=%s ndefaults=%s returns=%s vol=%s secdef=%s search_path_empty=%s owner=%s overloads=%s old_identity_resolves=%s',
                 pg_get_function_identity_arguments(p.oid), pg_get_function_arguments(p.oid), p.pronargs::text,
                 p.pronargdefaults::text, pg_get_function_result(p.oid), p.provolatile::text, p.prosecdef::text,
                 (p.proconfig = array['search_path=""'])::text, pg_get_userbyid(p.proowner),
                 (select count(*) from pg_proc q where q.pronamespace = 'app'::regnamespace
                     and q.proname = 'purge_expired_test_card_attempts')::text,
                 (to_regprocedure('app.purge_expired_test_card_attempts(text,text,uuid)') is not null)::text)
     from pg_proc p where p.oid = to_regprocedure('app.purge_expired_test_card_attempts(text,text,uuid,integer)')),
  'identity=(p_reason text, p_operator_reference text, p_actor_app_user_id uuid, p_max_devices integer) '
  || 'args=(p_reason text, p_operator_reference text, p_actor_app_user_id uuid, p_max_devices integer DEFAULT NULL::integer) '
  || 'nargs=4 ndefaults=1 returns=jsonb vol=v secdef=true search_path_empty=true owner=postgres overloads=1 old_identity_resolves=false',
  'SA-115 C1-3: app.purge_expired_test_card_attempts is (p_reason text, p_operator_reference text, p_actor_app_user_id uuid, p_max_devices integer DEFAULT NULL) - one overload, the 3-argument identity gone - VOLATILE, SECURITY DEFINER, search_path pinned, owner postgres, returns jsonb');

select is(
  (select format('acl=%s public_execute=%s anon=%s authenticated=%s service_role=%s public_layer=%s',
                 coalesce(p.proacl::text, 'NULL'),
                 (exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text,
                 has_function_privilege('anon', p.oid, 'EXECUTE')::text,
                 has_function_privilege('authenticated', p.oid, 'EXECUTE')::text,
                 has_function_privilege('service_role', p.oid, 'EXECUTE')::text,
                 (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace
                     and q.proname = 'purge_expired_test_card_attempts')::text)
     from pg_proc p where p.oid = to_regprocedure('app.purge_expired_test_card_attempts(text,text,uuid,integer)')),
  'acl={postgres=X/postgres} public_execute=false anon=false authenticated=false service_role=false public_layer=0',
  'SA-116 C1-3: the 4-argument purge keeps the operator posture - ACL exactly {postgres=X/postgres} (no EXECUTE for PUBLIC, anon, authenticated or service_role) and no public wrapper of any signature');

-- Typed calls of the purge in both call forms (each argument a scalar sub-select, as in _sa_fn.call_sql).
create temp table _sa_purge (call4 text, call3 text);
insert into _sa_purge values (
  'select app.purge_expired_test_card_attempts((select null::text), (select null::text), (select null::uuid), (select 0::integer))',
  'select app.purge_expired_test_card_attempts((select null::text), (select null::text), (select null::uuid))');
grant select on _sa_purge to anon, authenticated, service_role;
set local role anon;
insert into _sa_r select 'purge-anon', jsonb_build_object('call4', pg_temp.sa_probe(call4), 'call3', pg_temp.sa_probe(call3))
  from _sa_purge;
reset role;
set local role authenticated;
insert into _sa_r select 'purge-authenticated', jsonb_build_object('call4', pg_temp.sa_probe(call4), 'call3', pg_temp.sa_probe(call3))
  from _sa_purge;
reset role;
set local role service_role;
insert into _sa_r select 'purge-service_role', jsonb_build_object('call4', pg_temp.sa_probe(call4), 'call3', pg_temp.sa_probe(call3))
  from _sa_purge;
reset role;
insert into _sa_r select 'purge-owner', jsonb_build_object('call4', pg_temp.sa_eval(call4), 'call3', pg_temp.sa_eval(call3))
  from _sa_purge;
select is(
  (select jsonb_object_agg(label, r) from _sa_r where label like 'purge-%'),
  jsonb_build_object(
    'purge-anon', jsonb_build_object('call4', 'denied', 'call3', 'denied'),
    'purge-authenticated', jsonb_build_object('call4', 'denied', 'call3', 'denied'),
    'purge-service_role', jsonb_build_object('call4', 'denied', 'call3', 'denied'),
    'purge-owner', jsonb_build_object('call4', '{"ok": false, "error": "invalid_request"}'::jsonb,
                                      'call3', '{"ok": false, "error": "permission_denied"}'::jsonb)),
  'SA-117 C1-3: AS anon, authenticated and service_role the purge is refused 42501 by the privilege layer in both call forms (4 arguments; 3 arguments completed by the DEFAULT); the owner''s identical calls reach the body (p_max_devices 0 answers invalid_request, checked first; the 3-argument form resolves to the same function and answers permission_denied)');
select is(
  (select jsonb_build_object('attempts', (select count(*) from app.card_provider_attempts),
                             'events', (select count(*) from app.card_provider_private_events),
                             'tombstones', (select count(*) from app.card_attempt_identity_tombstones))),
  '{"attempts": 0, "events": 0, "tombstones": 0}'::jsonb,
  'SA-118 C1-3: the refused and early-answered purge calls wrote nothing (no attempt, private event or tombstone exists)');

-- The 8 public card wrappers against the C1 build (C2, D-060 point 2). c1_md5 is the CR-normalized
-- pg_get_functiondef md5 captured on the pre-C2 clone holding the C1 migration (SHA-256 a8a0f73c...; equal to
-- the pre-C1 candidate 2e011ea5 capture), c2_md5 the capture of this build. context, owner_card_attempts and
-- finish are unchanged (no binding); each of the five session-proving wrappers is its C1 definition plus exactly
-- the trailing parameter p_caller_auth_user_id uuid and its pass-through argument (2 occurrences; the c1 form
-- removes both).
create temp table _sa_c1_wrappers (ord integer primary key, sig text not null, c2_md5 text not null, c1_md5 text not null);
insert into _sa_c1_wrappers values
  (1, 'public.card_attempt_context(uuid,uuid,text,uuid,text)', '0da3d78e94147a7d455eb8028e07b999', '0da3d78e94147a7d455eb8028e07b999'),
  (2, 'public.owner_card_attempts(uuid,uuid,uuid,timestamptz,timestamptz,text)', '678b913122a52c57457f90684ade9090', '678b913122a52c57457f90684ade9090'),
  (3, 'public.card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)', '2bd136f2d08876ad26a5a56a2a79a0a3', '0c44ce396e9e4b6fc8e1012c8a94b620'),
  (4, 'public.card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)', 'f4c59a2e03919202218a9432d12e2600', '30fe7e00b5abdb3be292757049ed7e73'),
  (5, 'public.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)', 'f87c0fc5231d6418f437879f45a0b1bb', 'f87c0fc5231d6418f437879f45a0b1bb'),
  (6, 'public.card_attempt_mark_release_requested(uuid,uuid,text,text,uuid)', '54d85f5fc98594ffd51e42fbba4d6c33', '673e8828b786309ec0ee4d8eff3b89d3'),
  (7, 'public.card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid)', '7e61ea105dbb0df9a2d5c92aae02b88d', '8776d1e8251180c46673f6581758fb34'),
  (8, 'public.card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid)', '963146bff5aa0024578fa3c885bda4bc', '254f62415f949a9f1f68052b16fd85d1');
select is(
  (select coalesce(string_agg(x.sig || ' md5=' || coalesce(md5(d.def), 'missing') || ' binding=' || d.n::text
                              || ' c1_form_md5=' || coalesce(md5(d.c1_form), 'missing'), '; ' order by x.ord)
            filter (where md5(d.def) is distinct from x.c2_md5 or md5(d.c1_form) is distinct from x.c1_md5
                       or d.n <> case when x.c2_md5 = x.c1_md5 then 0 else 2 end), '') || ' / ' || count(*)::text
     from _sa_c1_wrappers x
     cross join lateral (select replace(pg_get_functiondef(to_regprocedure(x.sig)), E'\r', '') as def) d0
     cross join lateral (select d0.def, (select count(*) from regexp_matches(d0.def, 'p_caller_auth_user_id', 'g')) as n,
                                regexp_replace(d0.def, ',\s*p_caller_auth_user_id( uuid)?\)', ')', 'g') as c1_form) d),
  ' / 8',
  'SA-119 C2 (D-060 point 2; restated from the pre-C1 check): context, owner_card_attempts and finish are byte-identical to their C1 definitions (CR-normalized pg_get_functiondef md5 = the C1 capture, no binding), and each of the five session-proving wrappers has its pinned C2 definition, which differs from its C1 definition exactly by the trailing parameter p_caller_auth_user_id uuid and its pass-through argument (2 occurrences; removing both restores the C1 md5)');

select is(
  (select format('functions=%s acl_md5=%s without_helper_md5=%s identity_acl_md5=%s', count(*)::text,
                 md5(string_agg(n.nspname || '.' || p.proname || '=' || coalesce(p.proacl::text, 'NULL'), ';'
                                order by n.nspname, p.proname)),
                 md5(string_agg(n.nspname || '.' || p.proname || '=' || coalesce(p.proacl::text, 'NULL'), ';'
                                order by n.nspname, p.proname) filter (where p.proname <> 'card_caller_binding_denial')),
                 md5(string_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')='
                                || coalesce(p.proacl::text, 'NULL'), ';' order by n.nspname, p.proname)))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and (p.proname like 'card\_%' or p.proname in ('owner_card_attempts', 'set_card_payments_pilot', 'set_payment_terminal',
                                                    'purge_expired_test_card_attempts', 'payment_terminals_guard'))),
  'functions=55 acl_md5=2d4b1a354a242624965e94bf2bbc0ff4 without_helper_md5=d871bd81dad4afc259cc5c4e4cf900b7 '
  || 'identity_acl_md5=3c2a83484c4e86d7a3a2728c7a5d684d',
  'SA-120 C2 (D-060; restated from the pre-C1 check): the card family is exactly 55 functions; its ordered (schema.name = ACL) list hashes to the C2 capture 2d4b1a35..., and the same list without app.card_caller_binding_denial to the C1 capture d871bd81... (the helper, granted to none, is the only function added; no grant changed); the ordered list of identities with their ACLs is pinned to the C2 capture 3c2a8348...');

-- ===========================================================================
-- 12. Correction C2 (D-060): the support boundary (packet 13.3; 13.5 SA).
--     The five session-proving service-only operations gained the final
--     required parameter p_caller_auth_user_id uuid on both layers (the 10
--     changed functions); the internal helper app.card_caller_binding_denial
--     (uuid) was added with no grant; app.card_attempt_context gained the
--     caller_auth_user_id answer key; app.sync_push gained change 7 (the
--     support-context admission guard). C1 captures were computed on the
--     pre-C2 clone holding the C1 migration (SHA-256 a8a0f73c...), C2 ones on
--     this build. Signatures are composed from separate name / argument
--     columns.
-- ===========================================================================
create temp table _sa_c2 (
  ord         integer primary key,
  nsp         text not null,
  name        text not null,
  args        text not null,
  layer       text not null,
  c1_args     text,
  sig         text,
  c1_sig      text,
  fn          oid,
  call_sql    text,
  c1_call_sql text
);
insert into _sa_c2 (ord, nsp, name, args, layer) values
  ( 1, 'app',    'card_attempt_claim',                  'uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid', 'body'),
  ( 2, 'public', 'card_attempt_claim',                  'uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid', 'wrapper'),
  ( 3, 'app',    'card_attempt_adapter_read',           'uuid,uuid,text,text,text,jsonb,jsonb,uuid', 'body'),
  ( 4, 'public', 'card_attempt_adapter_read',           'uuid,uuid,text,text,text,jsonb,jsonb,uuid', 'wrapper'),
  ( 5, 'app',    'card_attempt_mark_release_requested', 'uuid,uuid,text,text,uuid',                  'body'),
  ( 6, 'public', 'card_attempt_mark_release_requested', 'uuid,uuid,text,text,uuid',                  'wrapper'),
  ( 7, 'app',    'card_attempt_mark_recording_result',  'uuid,uuid,text,text,text,uuid',             'body'),
  ( 8, 'public', 'card_attempt_mark_recording_result',  'uuid,uuid,text,text,text,uuid',             'wrapper'),
  ( 9, 'app',    'card_attempt_free_order',             'uuid,uuid,text,text,text,text,text,uuid',   'body'),
  (10, 'public', 'card_attempt_free_order',             'uuid,uuid,text,text,text,text,text,uuid',   'wrapper'),
  (11, 'app',    'card_caller_binding_denial',          'uuid',                                      'helper');
-- The C1 identity of each changed function is its C2 identity without the trailing uuid; the helper is new.
update _sa_c2 set c1_args = case when layer <> 'helper' then regexp_replace(args, ',uuid$', '') end;
update _sa_c2 set sig = nsp || '.' || name || '(' || args || ')',
                  c1_sig = nsp || '.' || name || '(' || c1_args || ')',
                  fn = to_regprocedure(nsp || '.' || name || '(' || args || ')')::oid;
-- Typed all-NULL calls built from the declared argument lists (each NULL a scalar sub-select, as in
-- _sa_fn.call_sql) at the C2 arity and at the C1 arity; _sa_c2_calls adds the absent public helper.
update _sa_c2 set
  call_sql = format('select %s.%s(%s)', nsp, name,
    (select string_agg('(select null::' || u.t || ')', ', ' order by u.k)
       from unnest(string_to_array(args, ',')) with ordinality u(t, k))),
  c1_call_sql = case when c1_args is not null then format('select %s.%s(%s)', nsp, name,
    (select string_agg('(select null::' || u.t || ')', ', ' order by u.k)
       from unnest(string_to_array(c1_args, ',')) with ordinality u(t, k))) end;
create temp table _sa_c2_calls as
select ord, nsp, name, call_sql from _sa_c2
union all
select 12, 'public', 'card_caller_binding_denial', 'select public.card_caller_binding_denial((select null::uuid))';
grant select on _sa_c2, _sa_c2_calls to anon, authenticated, service_role;
-- Runs one statement AS the current role inside its own sub-transaction and always undoes it: 'executed', or the
-- raised SQLSTATE and message (exact refusal evidence).
create function pg_temp.sa_call(p_sql text) returns text language plpgsql as $$
begin
  if p_sql is null then
    return 'no-call';
  end if;
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = 'sa-call-undo';
  exception when others then
    if sqlstate = 'P0001' and sqlerrm = 'sa-call-undo' then
      return 'executed';
    end if;
    return sqlstate || ' ' || sqlerrm;
  end;
end $$;
-- The exact text C2 added (CR-normalized; E'' strings with explicit newlines): change 7 of app.sync_push (its
-- comment and the guard) and the two additions to app.card_attempt_context (the comment and the answer key).
create temp table _sa_c2_blocks (name text primary key, block text not null);
insert into _sa_c2_blocks values
  ('sync_push change 7',
      E'  -- BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D change 7 (D-060 point 1): a request made in\n'
   || E'  -- an ACTIVE platform support session (app.current_support_session() of the\n'
   || E'  -- verified JWT caller) is refused before everything else - the batch checks, the\n'
   || E'  -- PIN / device proof, any lock, both paths, any ledger claim, replay, Resume or\n'
   || E'  -- dispatch - with this entrypoint''s request-level refusal (SQLSTATE 42501).\n'
   || E'  -- Support mode is read-only; requests outside an active support session are\n'
   || E'  -- unchanged.\n'
   || E'  if app.current_support_session() is not null then\n'
   || E'    raise exception ''sync_push: permission denied (active support session)'' using errcode = ''42501'';\n'
   || E'  end if;\n'),
  ('context comment',
      E'  -- D-060 point 2: the original caller''s binding for the adapter - the verified\n'
   || E'  -- JWT subject (auth.users id) - passed unchanged to every service-only call of\n'
   || E'  -- the same request.\n'),
  ('context key', E'    ''caller_auth_user_id'', auth.uid(),\n');

-- The owner session (the migration owner; no privilege in the way): both arities. Then the three app roles.
insert into _sa_r select 'c2-owner-arity', jsonb_object_agg(ord::text, jsonb_build_object(
    'c2', pg_temp.sa_call(call_sql),
    'c1', case when c1_call_sql is null then 'new' else split_part(pg_temp.sa_call(c1_call_sql), ' ', 1) end))
  from _sa_c2;
set local role anon;
insert into _sa_r select 'c2-anon', jsonb_object_agg(ord::text, pg_temp.sa_call(call_sql)) from _sa_c2_calls;
reset role;
set local role authenticated;
insert into _sa_r select 'c2-authenticated', jsonb_object_agg(ord::text, pg_temp.sa_call(call_sql)) from _sa_c2_calls;
reset role;
set local role service_role;
insert into _sa_r select 'c2-service_role', jsonb_object_agg(ord::text, pg_temp.sa_call(call_sql)) from _sa_c2_calls;
reset role;

select is(
  (select string_agg(format('%s.%s c2=%s c1=%s', f.nsp, f.name, (to_regprocedure(f.sig) is not null)::text,
                            case when f.c1_sig is null then 'new' else (to_regprocedure(f.c1_sig) is not null)::text end),
                     '; ' order by f.ord)
     from _sa_c2 f),
  'app.card_attempt_claim c2=true c1=false; public.card_attempt_claim c2=true c1=false; '
  || 'app.card_attempt_adapter_read c2=true c1=false; public.card_attempt_adapter_read c2=true c1=false; '
  || 'app.card_attempt_mark_release_requested c2=true c1=false; public.card_attempt_mark_release_requested c2=true c1=false; '
  || 'app.card_attempt_mark_recording_result c2=true c1=false; public.card_attempt_mark_recording_result c2=true c1=false; '
  || 'app.card_attempt_free_order c2=true c1=false; public.card_attempt_free_order c2=true c1=false; '
  || 'app.card_caller_binding_denial c2=true c1=new',
  'SA-121 C2 (packet 13.3): each of the 10 changed functions resolves (to_regprocedure) at its exact C2 identity ending in the uuid caller binding - claim 14 arguments, adapter_read 8, mark_release_requested 5, mark_recording_result 6, free_order 8, on both layers - and its C1 identity (the same list without the trailing uuid) no longer resolves; the new helper app.card_caller_binding_denial resolves at (uuid)');

select is(
  (select string_agg(format('%s.%s functions=%s nargs/ndefaults=%s', x.nsp, x.name, x.n, coalesce(x.shape, '-')), '; ' order by x.ord)
     from (select f.ord, f.nsp, f.name, count(p.oid) as n,
                  string_agg(p.pronargs::text || '/' || p.pronargdefaults::text, ',') as shape
             from (select ord, nsp, name from _sa_c2 union all select 12, 'public', 'card_caller_binding_denial') f
             join pg_namespace n on n.nspname = f.nsp
             left join pg_proc p on p.pronamespace = n.oid and p.proname = f.name
            group by f.ord, f.nsp, f.name) x),
  'app.card_attempt_claim functions=1 nargs/ndefaults=14/0; public.card_attempt_claim functions=1 nargs/ndefaults=14/0; '
  || 'app.card_attempt_adapter_read functions=1 nargs/ndefaults=8/0; public.card_attempt_adapter_read functions=1 nargs/ndefaults=8/0; '
  || 'app.card_attempt_mark_release_requested functions=1 nargs/ndefaults=5/0; '
  || 'public.card_attempt_mark_release_requested functions=1 nargs/ndefaults=5/0; '
  || 'app.card_attempt_mark_recording_result functions=1 nargs/ndefaults=6/0; '
  || 'public.card_attempt_mark_recording_result functions=1 nargs/ndefaults=6/0; '
  || 'app.card_attempt_free_order functions=1 nargs/ndefaults=8/0; public.card_attempt_free_order functions=1 nargs/ndefaults=8/0; '
  || 'app.card_caller_binding_denial functions=1 nargs/ndefaults=1/0; public.card_caller_binding_denial functions=0 nargs/ndefaults=-',
  'SA-122 C2: exactly one function per name for the five operations in app and in public, each at the C2 arity with no parameter DEFAULT (no overload and no defaulted alternative that a call without the binding could reach); the helper exists once in app (1 argument, no DEFAULT) and under no signature in public');

select is(
  (select string_agg(format('%s.%s c2_call=%s c1_call=%s', f.nsp, f.name, r.r -> f.ord::text ->> 'c2', r.r -> f.ord::text ->> 'c1'),
                     '; ' order by f.ord)
     from _sa_c2 f cross join (select r from _sa_r where label = 'c2-owner-arity') r),
  'app.card_attempt_claim c2_call=executed c1_call=42883; public.card_attempt_claim c2_call=executed c1_call=42883; '
  || 'app.card_attempt_adapter_read c2_call=executed c1_call=42883; public.card_attempt_adapter_read c2_call=executed c1_call=42883; '
  || 'app.card_attempt_mark_release_requested c2_call=executed c1_call=42883; '
  || 'public.card_attempt_mark_release_requested c2_call=executed c1_call=42883; '
  || 'app.card_attempt_mark_recording_result c2_call=executed c1_call=42883; '
  || 'public.card_attempt_mark_recording_result c2_call=executed c1_call=42883; '
  || 'app.card_attempt_free_order c2_call=executed c1_call=42883; public.card_attempt_free_order c2_call=executed c1_call=42883; '
  || 'app.card_caller_binding_denial c2_call=executed c1_call=new',
  'SA-123 C2: in the owner session (no privilege in the way) a typed all-NULL call at the C2 arity reaches each of the 10 changed functions and the helper, while the same call without the trailing uuid raises 42883 undefined_function on every one of the 10 - a caller that omits the binding reaches no body (no overload, no defaulted alternative)');

select is(
  (select string_agg(format('%s.%s/%s owner=%s %s lang=%s vol=%s search_path_empty=%s ndefaults=%s last=%s %s returns=%s acl=%s',
                            f.nsp, f.name, p.pronargs, pg_get_userbyid(p.proowner),
                            case when p.prosecdef then 'definer' else 'invoker' end, l.lanname, p.provolatile,
                            (p.proconfig = array['search_path=""'])::text, p.pronargdefaults,
                            p.proargnames[p.pronargs], format_type(p.proargtypes[p.pronargs - 1], null),
                            pg_get_function_result(p.oid), coalesce(p.proacl::text, 'NULL')), '; ' order by f.ord)
     from _sa_c2 f left join pg_proc p on p.oid = f.fn left join pg_language l on l.oid = p.prolang
    where f.layer = 'body'),
  'app.card_attempt_claim/14 owner=postgres definer lang=plpgsql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'app.card_attempt_adapter_read/8 owner=postgres definer lang=plpgsql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'app.card_attempt_mark_release_requested/5 owner=postgres definer lang=plpgsql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'app.card_attempt_mark_recording_result/6 owner=postgres definer lang=plpgsql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'app.card_attempt_free_order/8 owner=postgres definer lang=plpgsql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}',
  'SA-124 C2 (packet 13.3): the 5 changed app bodies (claim, adapter_read, mark_release_requested, mark_recording_result, free_order) are owned by postgres, SECURITY DEFINER, LANGUAGE plpgsql, VOLATILE, proconfig {search_path=""}, have no DEFAULT, end in p_caller_auth_user_id uuid, return jsonb and carry exactly the ACL {postgres=X/postgres,service_role=X/postgres}');

select is(
  (select string_agg(format('%s.%s/%s owner=%s %s lang=%s vol=%s search_path_empty=%s ndefaults=%s last=%s %s returns=%s acl=%s',
                            f.nsp, f.name, p.pronargs, pg_get_userbyid(p.proowner),
                            case when p.prosecdef then 'definer' else 'invoker' end, l.lanname, p.provolatile,
                            (p.proconfig = array['search_path=""'])::text, p.pronargdefaults,
                            p.proargnames[p.pronargs], format_type(p.proargtypes[p.pronargs - 1], null),
                            pg_get_function_result(p.oid), coalesce(p.proacl::text, 'NULL')), '; ' order by f.ord)
     from _sa_c2 f left join pg_proc p on p.oid = f.fn left join pg_language l on l.oid = p.prolang
    where f.layer = 'wrapper'),
  'public.card_attempt_claim/14 owner=postgres invoker lang=sql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'public.card_attempt_adapter_read/8 owner=postgres invoker lang=sql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'public.card_attempt_mark_release_requested/5 owner=postgres invoker lang=sql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'public.card_attempt_mark_recording_result/6 owner=postgres invoker lang=sql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}; '
  || 'public.card_attempt_free_order/8 owner=postgres invoker lang=sql vol=v search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=jsonb acl={postgres=X/postgres,service_role=X/postgres}',
  'SA-125 C2 (packet 13.3): the 5 changed public wrappers are owned by postgres, SECURITY INVOKER, LANGUAGE sql, VOLATILE, proconfig {search_path=""}, have no DEFAULT, end in p_caller_auth_user_id uuid, return jsonb and carry exactly the ACL {postgres=X/postgres,service_role=X/postgres} (PUBLIC, anon and authenticated revoked)');

select is(
  (select format('%s.%s/%s owner=%s %s lang=%s vol=%s search_path_empty=%s ndefaults=%s last=%s %s returns=%s acl=%s '
                 || 'execute: public=%s anon=%s authenticated=%s service_role=%s',
                 f.nsp, f.name, p.pronargs, pg_get_userbyid(p.proowner),
                 case when p.prosecdef then 'definer' else 'invoker' end, l.lanname, p.provolatile,
                 (p.proconfig = array['search_path=""'])::text, p.pronargdefaults,
                 p.proargnames[p.pronargs], format_type(p.proargtypes[p.pronargs - 1], null),
                 pg_get_function_result(p.oid), coalesce(p.proacl::text, 'NULL'),
                 (exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                           where a.grantee = 0 and a.privilege_type = 'EXECUTE'))::text,
                 has_function_privilege('anon', p.oid, 'EXECUTE')::text,
                 has_function_privilege('authenticated', p.oid, 'EXECUTE')::text,
                 has_function_privilege('service_role', p.oid, 'EXECUTE')::text)
     from _sa_c2 f left join pg_proc p on p.oid = f.fn left join pg_language l on l.oid = p.prolang
    where f.layer = 'helper'),
  'app.card_caller_binding_denial/1 owner=postgres definer lang=sql vol=s search_path_empty=true ndefaults=0 last=p_caller_auth_user_id uuid returns=text acl={postgres=X/postgres} '
  || 'execute: public=false anon=false authenticated=false service_role=false',
  'SA-126 C2 (packet 13.2 / 13.3): the helper app.card_caller_binding_denial(p_caller_auth_user_id uuid) returns text, is owned by postgres, SECURITY DEFINER, LANGUAGE sql, STABLE, proconfig {search_path=""}, has no DEFAULT, and its ACL is exactly {postgres=X/postgres}: no EXECUTE for PUBLIC, anon, authenticated or service_role');

select is(
  (select string_agg(format('%s.%s=%s', c.nsp, c.name, r.r ->> c.ord::text), '; ' order by c.ord)
     from _sa_c2_calls c cross join (select r from _sa_r where label = 'c2-anon') r),
  'app.card_attempt_claim=42501 permission denied for schema app; '
  || 'public.card_attempt_claim=42501 permission denied for function card_attempt_claim; '
  || 'app.card_attempt_adapter_read=42501 permission denied for schema app; '
  || 'public.card_attempt_adapter_read=42501 permission denied for function card_attempt_adapter_read; '
  || 'app.card_attempt_mark_release_requested=42501 permission denied for schema app; '
  || 'public.card_attempt_mark_release_requested=42501 permission denied for function card_attempt_mark_release_requested; '
  || 'app.card_attempt_mark_recording_result=42501 permission denied for schema app; '
  || 'public.card_attempt_mark_recording_result=42501 permission denied for function card_attempt_mark_recording_result; '
  || 'app.card_attempt_free_order=42501 permission denied for schema app; '
  || 'public.card_attempt_free_order=42501 permission denied for function card_attempt_free_order; '
  || 'app.card_caller_binding_denial=42501 permission denied for schema app; '
  || 'public.card_caller_binding_denial=42883 function public.card_caller_binding_denial(uuid) does not exist',
  'SA-127 C2: runtime AS anon, a typed call of each of the 10 changed signatures at the C2 arity raises 42501 - the app bodies at schema app (anon has no USAGE on it), the public wrappers at their function ACL - and so does a call of the helper; no public.card_caller_binding_denial exists (42883)');

select is(
  (select string_agg(format('%s.%s=%s', c.nsp, c.name, r.r ->> c.ord::text), '; ' order by c.ord)
     from _sa_c2_calls c cross join (select r from _sa_r where label = 'c2-authenticated') r),
  'app.card_attempt_claim=42501 permission denied for function card_attempt_claim; '
  || 'public.card_attempt_claim=42501 permission denied for function card_attempt_claim; '
  || 'app.card_attempt_adapter_read=42501 permission denied for function card_attempt_adapter_read; '
  || 'public.card_attempt_adapter_read=42501 permission denied for function card_attempt_adapter_read; '
  || 'app.card_attempt_mark_release_requested=42501 permission denied for function card_attempt_mark_release_requested; '
  || 'public.card_attempt_mark_release_requested=42501 permission denied for function card_attempt_mark_release_requested; '
  || 'app.card_attempt_mark_recording_result=42501 permission denied for function card_attempt_mark_recording_result; '
  || 'public.card_attempt_mark_recording_result=42501 permission denied for function card_attempt_mark_recording_result; '
  || 'app.card_attempt_free_order=42501 permission denied for function card_attempt_free_order; '
  || 'public.card_attempt_free_order=42501 permission denied for function card_attempt_free_order; '
  || 'app.card_caller_binding_denial=42501 permission denied for function card_caller_binding_denial; '
  || 'public.card_caller_binding_denial=42883 function public.card_caller_binding_denial(uuid) does not exist',
  'SA-128 C2: runtime AS authenticated (the POS / browser JWT role), a typed call of each of the 10 changed signatures at the C2 arity raises 42501 permission denied for function on both layers, and so does a call of the helper; no public.card_caller_binding_denial exists (42883)');

select is(
  (select string_agg(format('%s.%s=%s', c.nsp, c.name, r.r ->> c.ord::text), '; ' order by c.ord)
     from _sa_c2_calls c cross join (select r from _sa_r where label = 'c2-service_role') r),
  'app.card_attempt_claim=executed; public.card_attempt_claim=executed; '
  || 'app.card_attempt_adapter_read=executed; public.card_attempt_adapter_read=executed; '
  || 'app.card_attempt_mark_release_requested=executed; public.card_attempt_mark_release_requested=executed; '
  || 'app.card_attempt_mark_recording_result=executed; public.card_attempt_mark_recording_result=executed; '
  || 'app.card_attempt_free_order=executed; public.card_attempt_free_order=executed; '
  || 'app.card_caller_binding_denial=42501 permission denied for function card_caller_binding_denial; '
  || 'public.card_caller_binding_denial=42883 function public.card_caller_binding_denial(uuid) does not exist',
  'SA-129 C2: runtime AS service_role (the 001E adapter role), the same typed calls reach all 10 changed signatures on both layers (non-vacuous: the anon / authenticated refusals above are the ACL, not the call shape), while a call of the helper is refused 42501 at its ACL (internal: only the owner reaches it, SA-123) and no public.card_caller_binding_denial exists (42883)');

select is(
  (select format('family=%s authenticated=%s service_role=%s anon=%s public=%s no_app_role=%s', count(*),
                 count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE')),
                 count(*) filter (where has_function_privilege('service_role', p.oid, 'EXECUTE')),
                 count(*) filter (where has_function_privilege('anon', p.oid, 'EXECUTE')),
                 count(*) filter (where exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                                                 where a.grantee = 0 and a.privilege_type = 'EXECUTE')),
                 count(*) filter (where not (has_function_privilege('anon', p.oid, 'EXECUTE')
                                             or has_function_privilege('authenticated', p.oid, 'EXECUTE')
                                             or has_function_privilege('service_role', p.oid, 'EXECUTE'))))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('app', 'public')
      and (p.proname like 'card\_%' or p.proname in ('owner_card_attempts', 'set_card_payments_pilot', 'set_payment_terminal',
                                                    'purge_expired_test_card_attempts', 'payment_terminals_guard'))),
  'family=55 authenticated=4 service_role=12 anon=0 public=0 no_app_role=39',
  'SA-130 C2 (packet 13.3): the EXECUTE matrix of the whole card family read from the catalog (app and public; every card_* name plus the five named operator / guard functions) counts 55 functions: authenticated executes 4 (both layers of card_attempt_context and owner_card_attempts), service_role 12 (both layers of the five changed operations and of card_attempt_finish), anon 0, PUBLIC 0, and 39 are executable by no app role');

select is(
  (select format('first=[%s] guard_before_batch_shape_comment=%s',
                 array_to_string((string_to_array(btrim(regexp_replace(regexp_replace(
                   substr(s.src, strpos(s.src, E'\nbegin\n') + 7), '--[^\n]*', '', 'g'), '\s+', ' ', 'g')), ' end if;'))[1:2],
                   ' end if;') || ' end if;',
                 (strpos(s.src, 'change 7 (D-060 point 1)') between 1 and strpos(s.src, '-- (0) batch shape'))::text)
     from (select replace(p.prosrc, E'\r', '') as src from pg_proc p where p.oid = to_regprocedure('app.sync_push(uuid,uuid,jsonb)')) s),
  'first=[if app.current_support_session() is not null then raise exception ''sync_push: permission denied (active support session)'' '
  || 'using errcode = ''42501''; end if; if p_operations is null or jsonb_typeof(p_operations) <> ''array'' then raise exception '
  || '''sync_push: p_operations must be a JSON array'' using errcode = ''42501''; end if;] guard_before_batch_shape_comment=true',
  'SA-131 C2 change 7 placement (packet 13.1): the first statement of the app.sync_push body (comment-stripped, whitespace-collapsed text after its BEGIN) is exactly the guard if app.current_support_session() is not null then raise exception ''sync_push: permission denied (active support session)'' using errcode = ''42501''; end if; - immediately followed by the C1 first statement, the (0) batch-shape check - and its change-7 comment block precedes the (0) batch shape comment');

select is(
  (select format('markers=%s change6_note=%s',
                 (select string_agg(m.n || ':' || m.c, ',' order by m.n::integer)
                    from (select x[1] as n, count(*) as c
                            from regexp_matches(s.src, 'BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D change ([0-9]+)', 'g') x
                           group by x[1]) m),
                 (select count(*) from regexp_matches(s.src, 'Change 6 \(D-058 point 7\)', 'g')))
     from (select p.prosrc as src from pg_proc p where p.oid = to_regprocedure('app.sync_push(uuid,uuid,jsonb)')) s),
  'markers=1:6,2:4,3:1,4:1,5:3,7:1 change6_note=1',
  'SA-132 C2: the seven 001D changes are documented in the app.sync_push body - the marker BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D change N occurs for N = 1 (x6), 2 (x4), 3 (x1), 4 (x1), 5 (x3) and 7 (x1, new in C2) and for no other N, and change 6 (the pre-ledger TEST refusal) is documented once as Change 6 (D-058 point 7) inside a change-5 comment, as in C1 (no literal change-6 marker since C1; reported, not a C2 change)');

select is(
  (select format('c2_md5=%s change7_blocks=%s without_change7_md5=%s', md5(d.def),
                 (length(d.def) - length(replace(d.def, b.block, ''))) / length(b.block), md5(replace(d.def, b.block, '')))
     from (select replace(pg_get_functiondef(to_regprocedure('app.sync_push(uuid,uuid,jsonb)')), E'\r', '') as def) d
     cross join _sa_c2_blocks b where b.name = 'sync_push change 7'),
  'c2_md5=dd8ec4f096b9b990725d5c02229eb8d6 change7_blocks=1 without_change7_md5=e4435ad476d9b70454ac34d35a73d6e2',
  'SA-133 C2 (packet 13.1; 13.5 SA, PRE = C1): the CR-normalized pg_get_functiondef of app.sync_push (md5 dd8ec4f0...) holds the change-7 comment-and-guard block exactly once, and with exactly that block removed it is byte-identical to the C1 definition (md5 e4435ad4..., captured on the pre-C2 clone): the six 001D changes plus exactly change 7, nothing else changed');

select is(
  (select format('identity=(%s) md5=%s acl=%s secdef=%s overloads=%s', pg_get_function_identity_arguments(p.oid),
                 md5(replace(pg_get_functiondef(p.oid), E'\r', '')), coalesce(p.proacl::text, 'NULL'), p.prosecdef::text,
                 (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'sync_push'))
     from pg_proc p where p.oid = to_regprocedure('public.sync_push(uuid,uuid,jsonb)')),
  'identity=(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb) md5=68fcb0b3006e998b447861db6126f2c4 '
  || 'acl={postgres=X/postgres,authenticated=X/postgres} secdef=false overloads=1',
  'SA-134 C2 (packet 13.1): public.sync_push keeps its C1 signature (p_pin_session_id uuid, p_device_id uuid, p_operations jsonb) with one overload, SECURITY INVOKER, its C1 ACL {postgres=X/postgres,authenticated=X/postgres} and its C1 definition (CR-normalized md5 68fcb0b3..., captured on the pre-C2 clone)');

select is(
  (select string_agg(format('%s md5=%s acl=%s overloads=%s', x.sig,
                            coalesce(md5(replace(pg_get_functiondef(to_regprocedure(x.sig)), E'\r', '')), 'missing'),
                            coalesce((select p.proacl::text from pg_proc p where p.oid = to_regprocedure(x.sig)), 'NULL'),
                            (select count(*) from pg_proc q join pg_namespace qn on qn.oid = q.pronamespace
                              where qn.nspname = split_part(x.sig, '.', 1) and q.proname = 'card_attempt_finish')), '; ' order by x.ord)
     from (values (1, 'app.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)'),
                  (2, 'public.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text)')) x(ord, sig)),
  'app.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text) md5=99040d865e5bcd17f66e40ffe5f956b0 '
  || 'acl={postgres=X/postgres,service_role=X/postgres} overloads=1; '
  || 'public.card_attempt_finish(uuid,uuid,uuid,text,text,bigint,text,text,text,jsonb,text) md5=f87c0fc5231d6418f437879f45a0b1bb '
  || 'acl={postgres=X/postgres,service_role=X/postgres} overloads=1',
  'SA-135 C2 (packet 13.4, the provider-fact exception): card_attempt_finish keeps its signature, ACL and definition on both layers - the app body and the public wrapper are byte-identical to C1 (CR-normalized md5 99040d86... / f87c0fc5..., captured on the pre-C2 clone), ACL {postgres=X/postgres,service_role=X/postgres}, one overload each: it gained no caller binding and no support check');

select is(
  (select format('identity=(%s) overloads=%s acl=%s comment_lines=%s key_line=%s c2_md5=%s without_c2_lines_md5=%s',
                 pg_get_function_identity_arguments(p.oid),
                 (select count(*) from pg_proc q where q.pronamespace = 'app'::regnamespace and q.proname = 'card_attempt_context'),
                 coalesce(p.proacl::text, 'NULL'),
                 (length(d.def) - length(replace(d.def, c.block, ''))) / length(c.block),
                 (length(d.def) - length(replace(d.def, k.block, ''))) / length(k.block),
                 md5(d.def), md5(replace(replace(d.def, c.block, ''), k.block, '')))
     from pg_proc p
     cross join lateral (select replace(pg_get_functiondef(p.oid), E'\r', '') as def) d
     cross join _sa_c2_blocks c
     cross join _sa_c2_blocks k
    where p.oid = to_regprocedure('app.card_attempt_context(uuid,uuid,text,uuid,text)')
      and c.name = 'context comment' and k.name = 'context key'),
  'identity=(p_pin_session_id uuid, p_device_id uuid, p_device_session_token text, p_order_id uuid, p_attempt_id text) overloads=1 '
  || 'acl={postgres=X/postgres,authenticated=X/postgres} comment_lines=1 key_line=1 c2_md5=c57fdbc76fff275ccd002229a3e17f81 '
  || 'without_c2_lines_md5=de88642bdf4e359f9185d141fd583904',
  'SA-136 C2 (packet 13.2): app.card_attempt_context keeps its signature (one overload) and its ACL {postgres=X/postgres,authenticated=X/postgres}; its CR-normalized definition (md5 c57fdbc7...) holds the added three-line binding comment and the added answer line ''caller_auth_user_id'', auth.uid(), exactly once each, and with exactly those lines removed it is byte-identical to the C1 definition (md5 de88642b..., captured on the pre-C2 clone)');

select is(
  (select coalesce(string_agg(s.nsp || '.' || s.name || ' x' || (select count(*) from regexp_matches(s.src, 'app\.card_caller_binding_denial\s*\(', 'g'))::text,
                              ', ' order by s.nsp collate "C", s.name collate "C"), '')
     from _sa_src s where s.src ~ 'app\.card_caller_binding_denial\s*\('),
  'app.card_attempt_adapter_read x2, app.card_attempt_claim x3, app.card_attempt_free_order x3, '
  || 'app.card_attempt_mark_recording_result x3, app.card_attempt_mark_release_requested x3',
  'SA-137 C2 (packet 13.2 / 13.4): app.card_caller_binding_denial is called (comment-stripped source, any non-system schema) only by the five session-proving app bodies, with these call counts (their order against the locks, evidence and writes is pinned by SA-139, and each check after a lock wait by the runner legs C34-C41) - the early check plus each check that follows a lock wait: claim x3 (early, after the full-identity lock, after the LIVE orders / shifts / drawers locks), adapter_read x2 (early, after the proof - its final check, the attempt read takes no lock), mark_release_requested x3 (early, after the proof, after the attempt row lock), mark_recording_result x3 (early, after the proof, after the sync_operations -> attempt locks), free_order x3 (early, after the proof, after the orders -> attempt locks) - and by no wrapper, not by card_attempt_finish (the provider-fact exception), card_attempt_context or app.sync_push');

select is(
  (select format('reads=%s ambient_identity_or_guc=%s',
                 concat_ws(',', case when s.src ~ '\mauth\.users\M' then 'auth.users' end,
                                case when s.src ~ '\mauth_user_id\s*=\s*p_caller_auth_user_id\M' then 'app_users.auth_user_id=binding' end,
                                case when s.src ~ '\mpublic\.platform_support_sessions\M' then 'public.platform_support_sessions' end),
                 coalesce((select string_agg(distinct lower(m[1]), ',')
                             from regexp_matches(s.src, '(auth\.[a-z_]+\s*\(|current_setting|set_config|request\.jwt|session_user|current_user|current_role|app\.current_[a-z_]+)', 'gi') m),
                          'none'))
     from _sa_src s where s.oid = to_regprocedure('app.card_caller_binding_denial(uuid)')),
  'reads=auth.users,app_users.auth_user_id=binding,public.platform_support_sessions ambient_identity_or_guc=none',
  'SA-138 C2 (packet 13.2): the helper decides from its explicit binding alone - its comment-stripped source reads auth.users, maps the binding through app_users.auth_user_id and reads public.platform_support_sessions, and never calls auth.uid() / auth.jwt() or any other auth.* function, current_setting / set_config, request.jwt.*, session_user / current_user / current_role or app.current_* (no ambient caller identity; no GUC read or set)');

-- SA-139 (C2 re-review fix FIXTESTS-01 / FIXDOCS-04): the textual order, in each of the five comment-stripped bodies, of
-- its binding checks against its lock waits, its proof, its evidence writes, its action-specific writes and its
-- attempt-data returns (packet 13.2) - the upper bounds the runner legs cannot reach (a check moved below a
-- configuration event, a refusal-evidence branch or an envelope return would still pass every race leg).
create function pg_temp.sa_order(p_proc regprocedure, p_pairs text[]) returns text language plpgsql stable as $$
declare
  v text := regexp_replace(replace(pg_get_functiondef(p_proc), chr(13), ''), '--[^\n]*', '', 'g');
  i integer;
begin
  for i in 1 .. array_length(p_pairs, 1) / 2 loop
    v := regexp_replace(v, p_pairs[2 * i - 1], chr(164) || p_pairs[2 * i] || chr(164), 'g');
  end loop;
  return (select string_agg(t.m[1], ' > ' order by t.ord)
            from regexp_matches(v, chr(164) || '([a-z0-9_]+)' || chr(164), 'g') with ordinality as t(m, ord));
end $$;
select is(
  jsonb_build_object(
    'claim', pg_temp.sa_order('app.card_attempt_claim(uuid,uuid,text,text,text,bigint,text,uuid,integer,text,jsonb,jsonb,text,uuid)',
      array['app\.card_caller_binding_denial\(p_caller_auth_user_id\)', 'check',
            'perform app\.card_terminal_lock\(', 'terminal_lock',
            'card-purge/v1', 'purge_barrier',
            'v_proof := app\.card_attempt_proof\(', 'proof',
            'app\.card_denial_evidence\(p_mode', 'proof_evidence',
            'perform app\.card_identity_lock\(', 'identity_lock',
            'app\.card_pilot_revision_current\(', 'config',
            'app\.card_config_mismatch\(', 'config_check',
            'security\.card_credential_mismatch', 'config_event',
            'app\.card_denial_evidence\(''test''', 'test_evidence',
            'select \* into v_existing from app\.card_provider_attempts', 'replay',
            'from public\.orders o', 'orders_lock',
            'from public\.shifts s', 'shifts_lock',
            'from public\.cash_drawer_sessions c', 'drawers_lock',
            'app\.card_denial_evidence\(''live''', 'live_evidence',
            'insert into app\.card_provider_attempts', 'insert',
            'app\.card_audit_write\(', 'audit']),
    'adapter_read', pg_temp.sa_order('app.card_attempt_adapter_read(uuid,uuid,text,text,text,jsonb,jsonb,uuid)',
      array['app\.card_caller_binding_denial\(p_caller_auth_user_id\)', 'check',
            'v_proof := app\.card_attempt_proof\(', 'proof',
            'app\.card_attempt_resolve\(', 'resolve',
            'select \* into a from app\.card_provider_attempts', 'attempt_read',
            'app\.card_config_mismatch\(', 'config_check',
            'security\.card_credential_mismatch', 'config_event',
            'app\.card_attempt_envelope\(a\)', 'envelope']),
    'mark_release_requested', pg_temp.sa_order('app.card_attempt_mark_release_requested(uuid,uuid,text,text,uuid)',
      array['app\.card_caller_binding_denial\(p_caller_auth_user_id\)', 'check',
            'v_proof := app\.card_attempt_proof\(', 'proof',
            'app\.card_proof_denial_evidence\(', 'proof_evidence',
            'app\.card_attempt_resolve\(', 'resolve',
            'select \* into a from app\.card_provider_attempts', 'attempt_lock',
            'update app\.card_provider_attempts', 'update',
            'app\.card_audit_write\(', 'audit',
            'app\.card_attempt_envelope\(a\)', 'envelope']),
    'mark_recording_result', pg_temp.sa_order('app.card_attempt_mark_recording_result(uuid,uuid,text,text,text,uuid)',
      array['app\.card_caller_binding_denial\(p_caller_auth_user_id\)', 'check',
            'v_proof := app\.card_attempt_proof\(', 'proof',
            'app\.card_proof_denial_evidence\(', 'proof_evidence',
            'app\.card_attempt_resolve\(', 'resolve',
            'select \* into a from app\.card_provider_attempts', 'attempt_read',
            'from public\.sync_operations so', 'sync_lock',
            'app\.card_denial_evidence\(', 'denial_evidence',
            'update app\.card_provider_attempts', 'update',
            'app\.card_audit_write\(', 'audit',
            'app\.card_attempt_envelope\(a\)', 'envelope']),
    'free_order', pg_temp.sa_order('app.card_attempt_free_order(uuid,uuid,text,text,text,text,text,uuid)',
      array['app\.card_caller_binding_denial\(p_caller_auth_user_id\)', 'check',
            'v_proof := app\.card_attempt_proof\(', 'proof',
            'app\.card_safe_text_ok\(', 'text_rule',
            'app\.card_attempt_resolve\(', 'resolve',
            'select \* into a from app\.card_provider_attempts', 'attempt_read',
            'from public\.orders o', 'orders_lock',
            'app\.card_denial_evidence\(', 'denial_evidence',
            'update app\.card_provider_attempts', 'update',
            'app\.card_audit_write\(', 'audit',
            'app\.card_attempt_envelope\(a\)', 'envelope'])),
  jsonb_build_object(
    'claim', 'check > terminal_lock > purge_barrier > proof > proof_evidence > identity_lock > check > config > config_check > config_event > test_evidence > replay > orders_lock > shifts_lock > drawers_lock > check > live_evidence > insert > replay > audit',
    'adapter_read', 'check > proof > check > resolve > attempt_read > config_check > config_event > envelope',
    'mark_release_requested', 'check > proof > proof_evidence > check > resolve > attempt_lock > check > update > audit > envelope',
    'mark_recording_result', 'check > proof > proof_evidence > check > resolve > attempt_read > envelope > sync_lock > attempt_read > check > envelope > denial_evidence > update > audit > envelope',
    'free_order', 'check > proof > check > text_rule > text_rule > resolve > attempt_read > orders_lock > attempt_read > check > envelope > denial_evidence > update > audit > envelope'),
  'SA-139 C2 (re-review fix FIXTESTS-01; packet 13.2): in each comment-stripped body the binding checks sit exactly where 13.2 puts them - early (before the proof and any lock); right after the proof where an attempt lookup follows (after the proof''s own refusal evidence); the claim''s after its identity lock and before its configuration checks, their event, the TEST evidence and the replay, and its last after the orders / shifts / drawers locks and before the LIVE refusal evidence and the insert; each mark''s and free_order''s last after its row locks and before its envelope, evidence and write - so no check can move below an evidence write or an attempt-data return without failing here');

select * from finish();
rollback;
