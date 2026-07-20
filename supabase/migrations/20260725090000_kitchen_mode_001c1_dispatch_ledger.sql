-- ============================================================================
-- KITCHEN-MODE-001C1 — DORMANT kitchen print dispatch ledger + readiness
-- foundation for the printer-only kitchen workflow. ADDITIVE ONLY.
--
-- DEPLOY-AHEAD SAFE BY CONSTRUCTION:
--   * every dispatch-creating path is gated on branches.kitchen_workflow_mode
--     = 'printer_only' — a mode that NO production branch has, that NO setter
--     can produce (none exists; 001C3 ships the owner setter), and that no
--     app role can write directly (001A write-protection unchanged);
--   * the claim/pull RPC additionally requires a FRESH device readiness
--     report carrying capability 'kitchen_printer_only_v1' — which NO
--     deployed client reports — so production claims are impossible even if
--     a branch were privileged-flipped;
--   * kds-mode behavior of submit_order / add_order_items / void_order is
--     byte-identical (faithful re-creations; the dispatch tails are
--     mode-gated no-ops).
--
-- THE GUARANTEE THIS FOUNDATION EXISTS FOR: server acceptance and POS-local
-- durable persistence cannot share one transaction, so every accepted
-- printer-only kitchen event (initial order / service-round delta / void)
-- writes ONE durable, idempotent, MONEY-FREE dispatch row IN THE SAME
-- TRANSACTION as the acceptance itself. The POS later pulls-and-claims
-- atomically, imports into its (001C2) encrypted local spool, prints, and
-- acknowledges. A POS crash at any point recovers by re-pulling; local data
-- loss recovers from this ledger. Claimed/completed/client-status semantics
-- only — there is deliberately NO 'printed' boolean: transport acceptance is
-- never a physical-paper claim.
--
-- AUDIT NOTE (D-013): audit_events REQUIRES a human actor
-- (audit_events_actor_present). Dispatch creation runs inside PIN-session
-- RPCs and is audited (kitchen.dispatch_created / kitchen.dispatch_void_
-- created). The device-token RPCs (readiness / pull / ack) have NO human
-- actor and therefore CANNOT write audit rows — their observability lives in
-- the tables themselves (reported_at, claimed_at/claimed_by, completed_at,
-- last_client_status), surfaced by the inspection RPC.
--
-- Contents:
--   1.  branches.kitchen_workflow_mode_revision (consumed by the 001C3
--       setter; NOT bumped here — no setter exists).
--   2.  kitchen_printer_readiness_reports (one current report per device;
--       10-minute validity; fingerprint digest only — never an endpoint).
--   3.  app.kitchen_payload_offending_key — recursive money-free/PII guard.
--   4.  kitchen_print_dispatches + guard trigger + indexes + forced RLS.
--   5.  INTERNAL payload builders (initial / round-delta / void) — server
--       snapshots from authoritative rows, money-free by construction.
--   6.  INTERNAL app.create_kitchen_dispatch (idempotent; audits; supersedes
--       unclaimed priors on void).
--   7.  app.submit_order — faithful re-creation of 20260723090000:375-850
--       with the dormant initial-dispatch tail.
--   8.  app.add_order_items — faithful re-creation of 20260722090000:243-692
--       with the dormant round-dispatch tail.
--   9.  app.void_order — faithful re-creation of 20260722090000:1373-1642
--       (the NEWEST body: PSC-001D provenance + the PSC-001C round sweep)
--       with the dormant void-dispatch tail.
--   10. app.report_kitchen_printer_readiness (+wrapper) — device-token RPC.
--   11. app.pull_kitchen_print_dispatches (+wrapper) — atomic claim-and-pull.
--   12. app.acknowledge_kitchen_print_dispatch (+wrapper).
--   13. app.get_kitchen_workflow_transition_readiness (+wrapper) — read-only
--       member inspection of every mode-switch blocker.
--   14. Audit trio faithful re-creations (kitchen.% family).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Branch mode revision (001C3 setter consumes it; nothing bumps it yet).
-- ----------------------------------------------------------------------------
alter table public.branches
  add column kitchen_workflow_mode_revision integer not null default 1
    constraint branches_kitchen_workflow_mode_revision_check
    check (kitchen_workflow_mode_revision > 0);

comment on column public.branches.kitchen_workflow_mode_revision is
  'KITCHEN-MODE-001C1: monotonic revision of kitchen_workflow_mode, bumped ONLY by the future owner setter (001C3) so stale mode-change requests and stale client caches can be rejected. No setter exists yet; direct app-role writes stay blocked by the 001A branches write-protection.';

-- ----------------------------------------------------------------------------
-- 2. Device readiness reports (ONE current row per device, upserted; a report
--    is authoritative only while unexpired — reported_at + 10 minutes).
-- ----------------------------------------------------------------------------
create table public.kitchen_printer_readiness_reports (
  id                     uuid        not null default gen_random_uuid(),
  organization_id        uuid        not null references public.organizations (id) on delete restrict,
  restaurant_id          uuid        not null,
  branch_id              uuid        not null,
  device_id              uuid        not null,
  capability             text        not null check (capability = 'kitchen_printer_only_v1'),
  app_build              text        not null check (length(btrim(app_build)) between 1 and 64),
  printer_purpose        text        not null check (printer_purpose = 'kitchen_ticket'),
  transport_kind         text        not null check (transport_kind in ('network', 'bluetooth')),
  paper_width            text        not null check (paper_width in ('58mm', '80mm')),
  -- a NON-SECRET digest of the locally-selected endpoint identity: never a
  -- host, port, Bluetooth address, connection_config or credential.
  printer_fingerprint    text        not null check (printer_fingerprint ~ '^[0-9a-f]{16,128}$'),
  secure_spool_available boolean     not null,
  unresolved_local_jobs  integer     not null check (unresolved_local_jobs >= 0),
  mode_revision          integer     not null check (mode_revision > 0),
  reported_at            timestamptz not null default now(),
  expires_at             timestamptz not null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (id),
  unique (organization_id, device_id),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict
);

comment on table public.kitchen_printer_readiness_reports is
  'KITCHEN-MODE-001C1: the POS''s device-session-proven kitchen-printing readiness report (capability kitchen_printer_only_v1, purpose kitchen_ticket, transport/paper facts, a NON-SECRET endpoint digest, local secure-spool availability and unresolved-job count). ONE current row per device (upsert); authoritative ONLY while unexpired (reported_at + 10 min — the RF-118 read-side-expiry house style). Readiness means "the transport accepted test bytes and the device reported its local state" — NEVER a physical-paper claim. Written only by app.report_kitchen_printer_readiness; no direct app-role access.';

alter table public.kitchen_printer_readiness_reports enable row level security;
alter table public.kitchen_printer_readiness_reports force row level security;
revoke all on table public.kitchen_printer_readiness_reports from public;
revoke all on table public.kitchen_printer_readiness_reports from anon;
revoke all on table public.kitchen_printer_readiness_reports from authenticated;
-- Explicit default-DENY policies (the sync_operations house pattern): access
-- is RPC-only; the grant revoke above already blocks direct reads (42501),
-- and these keep >=1 explicit policy per verb on the table (the RF-019
-- detector + RF-059 AC1 no-FOR-ALL-gap contract) and document the intent.
create policy kitchen_printer_readiness_reports_sel_deny on public.kitchen_printer_readiness_reports for select to authenticated using (false);
create policy kitchen_printer_readiness_reports_ins_deny on public.kitchen_printer_readiness_reports for insert to authenticated with check (false);
create policy kitchen_printer_readiness_reports_upd_deny on public.kitchen_printer_readiness_reports for update to authenticated using (false) with check (false);
create policy kitchen_printer_readiness_reports_del_deny on public.kitchen_printer_readiness_reports for delete to authenticated using (false);

-- ----------------------------------------------------------------------------
-- 3. Recursive MONEY-FREE / PII guard. Returns the FIRST offending key (a key
--    name is never sensitive) or NULL when the payload is clean. Values are
--    never inspected or returned; only keys are judged, so ordinary numeric
--    quantities always pass.
-- ----------------------------------------------------------------------------
create or replace function app.kitchen_payload_offending_key(p_value jsonb)
  returns text
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_key      text;
  v_norm     text;
  v_child    jsonb;
  v_found    text;
begin
  if p_value is null then
    return null;
  end if;
  if jsonb_typeof(p_value) = 'object' then
    for v_key, v_child in select * from jsonb_each(p_value) loop
      v_norm := lower(btrim(v_key));
      if v_norm like '%\_minor' escape '\'
         or v_norm in (
           'price', 'unit_price', 'prices', 'subtotal', 'sub_total', 'total',
           'grand_total', 'paid', 'amount', 'amount_due', 'change',
           'change_due', 'currency', 'currency_code', 'payment',
           'payment_method', 'payments', 'tender', 'tendered', 'tax',
           'tax_rate', 'discount', 'discounts', 'tip', 'tips', 'fee', 'fees',
           'phone', 'phone_number', 'address', 'email',
           'connection_config', 'host', 'port', 'bluetooth_address',
           'token', 'tokens', 'credential', 'credentials', 'secret',
           'secrets', 'password', 'api_key')
         or v_norm like '%price%'
         or v_norm like '%payment%'
         or v_norm like '%currency%'
         or v_norm like '%tender%'
      then
        return v_key;
      end if;
      v_found := app.kitchen_payload_offending_key(v_child);
      if v_found is not null then
        return v_found;
      end if;
    end loop;
    return null;
  elsif jsonb_typeof(p_value) = 'array' then
    for v_child in select * from jsonb_array_elements(p_value) loop
      v_found := app.kitchen_payload_offending_key(v_child);
      if v_found is not null then
        return v_found;
      end if;
    end loop;
    return null;
  end if;
  return null;
end;
$$;

comment on function app.kitchen_payload_offending_key(jsonb) is
  'KITCHEN-MODE-001C1: recursive KEY-ONLY inspection of a kitchen dispatch payload at every nesting level (objects and arrays). Returns the first hostile key (money/financial/PII/endpoint/credential vocabulary, case-insensitive, incl. any *_minor suffix) or NULL when clean. Values are never judged, so numeric quantities always pass. INTERNAL — enforced by the kitchen_print_dispatches trigger.';

revoke all on function app.kitchen_payload_offending_key(jsonb) from public;
revoke all on function app.kitchen_payload_offending_key(jsonb) from anon;
revoke all on function app.kitchen_payload_offending_key(jsonb) from authenticated;

-- ----------------------------------------------------------------------------
-- 4. The dispatch ledger.
-- ----------------------------------------------------------------------------
create table public.kitchen_print_dispatches (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null references public.organizations (id) on delete restrict,
  restaurant_id             uuid        not null,
  branch_id                 uuid        not null,
  order_id                  uuid        not null,
  service_round_id          uuid,
  dispatch_type             text        not null check (dispatch_type in ('initial_order', 'service_round', 'void')),
  payload_version           integer     not null default 1 check (payload_version > 0),
  money_free_payload        jsonb       not null check (jsonb_typeof(money_free_payload) = 'object'),
  target_purpose            text        not null default 'kitchen_ticket' check (target_purpose = 'kitchen_ticket'),
  idempotency_key           text        not null,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  claimed_at                timestamptz,
  claimed_by_device_id      uuid,
  claim_expires_at          timestamptz,
  completed_at              timestamptz,
  last_client_status        text        check (last_client_status is null or last_client_status in
                                               ('imported', 'transport_accepted', 'possibly_printed',
                                                'failed_retryable', 'blocked_configuration')),
  last_error_code           text        check (last_error_code is null or last_error_code ~ '^[a-z0-9_.\-]{1,64}$'),
  superseded_by_dispatch_id uuid,
  primary key (id),
  unique (organization_id, idempotency_key),
  constraint kitchen_print_dispatches_round_type check (
    (dispatch_type = 'service_round') = (service_round_id is not null)),
  constraint kitchen_print_dispatches_claim_shape check (
    (claimed_at is null) = (claimed_by_device_id is null)),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, order_id)
    references public.orders (organization_id, id) on delete restrict
);

comment on table public.kitchen_print_dispatches is
  'KITCHEN-MODE-001C1: the durable server ledger guaranteeing every ACCEPTED printer-only kitchen event (initial order / service-round delta / void) has an idempotent MONEY-FREE dispatch created IN THE SAME TRANSACTION as the acceptance. The POS pulls-and-claims atomically (10-min claim expiry; stale claims reclaimable), imports into its encrypted local spool (001C2), prints, and acknowledges. claimed/completed/last_client_status semantics ONLY — deliberately NO printed boolean (transport acceptance is never a paper claim). Dispatch state is INDEPENDENT of order state. Completed rows stay readable for 30 days (read-side window; no physical cleanup in this phase). DORMANT: rows can only exist for printer_only branches (none exist; no setter until 001C3).';

create index kitchen_print_dispatches_pull_idx
  on public.kitchen_print_dispatches (organization_id, branch_id, created_at, id)
  where completed_at is null and superseded_by_dispatch_id is null;
create index kitchen_print_dispatches_order_idx
  on public.kitchen_print_dispatches (organization_id, order_id);

alter table public.kitchen_print_dispatches enable row level security;
alter table public.kitchen_print_dispatches force row level security;
revoke all on table public.kitchen_print_dispatches from public;
revoke all on table public.kitchen_print_dispatches from anon;
revoke all on table public.kitchen_print_dispatches from authenticated;
-- Explicit default-DENY policies (the sync_operations house pattern): access
-- is RPC-only; the grant revoke above already blocks direct reads (42501),
-- and these keep >=1 explicit policy per verb on the table (the RF-019
-- detector + RF-059 AC1 no-FOR-ALL-gap contract) and document the intent.
create policy kitchen_print_dispatches_sel_deny on public.kitchen_print_dispatches for select to authenticated using (false);
create policy kitchen_print_dispatches_ins_deny on public.kitchen_print_dispatches for insert to authenticated with check (false);
create policy kitchen_print_dispatches_upd_deny on public.kitchen_print_dispatches for update to authenticated using (false) with check (false);
create policy kitchen_print_dispatches_del_deny on public.kitchen_print_dispatches for delete to authenticated using (false);

create or replace function app.kitchen_print_dispatches_guard()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
declare
  v_bad  text;
begin
  v_bad := app.kitchen_payload_offending_key(new.money_free_payload);
  if v_bad is not null then
    raise exception 'kitchen_print_dispatches: hostile payload key % rejected (money/PII/endpoint vocabulary is forbidden at every nesting level)', v_bad
      using errcode = '23514';
  end if;
  if pg_column_size(new.money_free_payload) > 32768 then
    raise exception 'kitchen_print_dispatches: payload exceeds the 32KB limit'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function app.kitchen_print_dispatches_guard() is
  'KITCHEN-MODE-001C1: BEFORE INSERT/UPDATE guard — recursive money-free/PII key enforcement + ~32KB payload size cap. Fail-closed: a hostile payload aborts the surrounding mutation (an accepted printer-only event must be dispatchable or must not be accepted).';

revoke all on function app.kitchen_print_dispatches_guard() from public;
revoke all on function app.kitchen_print_dispatches_guard() from anon;
revoke all on function app.kitchen_print_dispatches_guard() from authenticated;

create trigger kitchen_print_dispatches_guard_trg
  before insert or update on public.kitchen_print_dispatches
  for each row execute function app.kitchen_print_dispatches_guard();

-- ----------------------------------------------------------------------------
-- 5. INTERNAL payload builders — server snapshots from AUTHORITATIVE rows in
--    the same transaction. Money-free BY CONSTRUCTION (no money column is
--    ever read); the trigger then re-proves it structurally.
-- ----------------------------------------------------------------------------
create or replace function app.kitchen_dispatch_payload_initial(
  p_organization_id uuid,
  p_order_id        uuid
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'initial_order',
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'customer_display_name', nullif(left(btrim(coalesce(o.customer_name, '')), 80), ''),
    'created_at', o.created_at,
    'items', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'qty', oi.quantity,
               'name', oi.menu_item_name_snapshot,
               'note', nullif(btrim(coalesce(oi.notes, '')), ''),
               'prep', oi.prep_snapshot,
               'modifiers', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot)
                        order by om.created_at, om.id), '[]'::jsonb)
                 from public.order_item_modifiers om
                 where om.organization_id = oi.organization_id
                   and om.order_item_id = oi.id
                   and om.deleted_at is null)))
             order by oi.created_at, oi.id), '[]'::jsonb)
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id
        and oi.service_round_id is null
        and oi.deleted_at is null)))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

create or replace function app.kitchen_dispatch_payload_round(
  p_organization_id uuid,
  p_order_id        uuid,
  p_round_id        uuid
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'service_round',
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'round_id', r.id,
    'round_number', r.round_number,
    'created_at', r.created_at,
    'items', (
      select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
               'qty', oi.quantity,
               'name', oi.menu_item_name_snapshot,
               'note', nullif(btrim(coalesce(oi.notes, '')), ''),
               'prep', oi.prep_snapshot,
               'modifiers', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'qty', om.quantity,
                          'name', om.option_name_snapshot)
                        order by om.created_at, om.id), '[]'::jsonb)
                 from public.order_item_modifiers om
                 where om.organization_id = oi.organization_id
                   and om.order_item_id = oi.id
                   and om.deleted_at is null)))
             order by oi.created_at, oi.id), '[]'::jsonb)
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id
        and oi.service_round_id = r.id
        and oi.deleted_at is null)))
  from public.orders o
  join public.order_service_rounds r
    on r.organization_id = o.organization_id and r.id = p_round_id and r.order_id = o.id
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

create or replace function app.kitchen_dispatch_payload_void(
  p_organization_id uuid,
  p_order_id        uuid,
  p_reason          text
)
  returns jsonb
  language sql
  stable
  set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'kind', 'void',
    'void', true,
    'order_code', '#' || upper(right(replace(o.id::text, '-', ''), 6)),
    'order_type', o.order_type,
    'table_label', tbl.label,
    'reason', nullif(left(btrim(coalesce(p_reason, '')), 200), ''),
    'voided_at', now(),
    'affected_item_count', (
      select count(*)::int from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id = o.id and oi.deleted_at is null)))
  from public.orders o
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id
  where o.organization_id = p_organization_id and o.id = p_order_id;
$$;

comment on function app.kitchen_dispatch_payload_initial(uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL: the money-free initial-order kitchen snapshot (initial items only — service_round_id IS NULL). No money column is read; customer_display_name is optional, trimmed to 80 chars; phone/address/payment data never exist here.';
comment on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL: the money-free service-round DELTA snapshot (only that round''s items).';
comment on function app.kitchen_dispatch_payload_void(uuid, uuid, text) is
  'KITCHEN-MODE-001C1 INTERNAL: the money-free VOID slip snapshot (marker + safe reason + counts; no items priced, no payment data).';

revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_initial(uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from public;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from anon;
revoke all on function app.kitchen_dispatch_payload_round(uuid, uuid, uuid) from authenticated;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from public;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from anon;
revoke all on function app.kitchen_dispatch_payload_void(uuid, uuid, text) from authenticated;

-- ----------------------------------------------------------------------------
-- 6. INTERNAL creator — idempotent (ON CONFLICT DO NOTHING on the logical
--    key), audits with the PIN-session actor (D-013), and on VOID supersedes
--    the order's UNCLAIMED prior dispatches.
-- ----------------------------------------------------------------------------
create or replace function app.create_kitchen_dispatch(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_order_id        uuid,
  p_round_id        uuid,
  p_dispatch_type   text,
  p_payload         jsonb,
  p_actor_employee_profile_id uuid,
  p_actor_membership_id       uuid,
  p_device_id       uuid
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_key   text;
  v_id    uuid;
  v_code  text;
begin
  v_key := case p_dispatch_type
             when 'initial_order' then 'initial:' || p_order_id::text
             when 'service_round' then 'round:' || p_round_id::text
             else 'void:' || p_order_id::text
           end;

  insert into public.kitchen_print_dispatches
    (organization_id, restaurant_id, branch_id, order_id, service_round_id,
     dispatch_type, money_free_payload, idempotency_key)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, p_order_id, p_round_id,
     p_dispatch_type, p_payload, v_key)
  on conflict (organization_id, idempotency_key) do nothing
  returning id into v_id;

  -- Idempotent retry: the logical dispatch already exists — reuse it, never
  -- duplicate, never audit twice.
  if v_id is null then
    select d.id into v_id from public.kitchen_print_dispatches d
      where d.organization_id = p_organization_id and d.idempotency_key = v_key;
    return v_id;
  end if;

  if p_dispatch_type = 'void' then
    -- The kitchen never saw an UNCLAIMED dispatch — the void supersedes it so
    -- the pull feed skips it. Claimed/completed dispatches stay: the kitchen
    -- may physically hold their paper, and the VOID slip corrects them.
    update public.kitchen_print_dispatches d
      set superseded_by_dispatch_id = v_id, updated_at = now()
      where d.organization_id = p_organization_id
        and d.order_id = p_order_id
        and d.id <> v_id
        and d.completed_at is null
        and d.claimed_at is null
        and d.superseded_by_dispatch_id is null;
  end if;

  v_code := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id,
     actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values
    (p_organization_id, p_restaurant_id, p_branch_id, null,
     p_actor_employee_profile_id, p_device_id,
     case when p_dispatch_type = 'void'
          then 'kitchen.dispatch_void_created' else 'kitchen.dispatch_created' end,
     null, null,
     jsonb_build_object(
       'order_code', v_code,
       'dispatch_type', p_dispatch_type,
       'resolved_membership_id', p_actor_membership_id));

  return v_id;
end;
$$;

comment on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1 INTERNAL: creates ONE logical kitchen dispatch per authoritative event (idempotency key initial:<order>/round:<round>/void:<order>; ON CONFLICT DO NOTHING => retries reuse the same row and never re-audit). On void, supersedes the order''s UNCLAIMED prior dispatches. Audits kitchen.dispatch_created/_void_created with the PIN-session actor (D-013). Runs INSIDE the caller''s transaction — a failure aborts the mutation (fail closed); a rollback leaves nothing. NEVER granted to client roles.';

revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from public;
revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from anon;
revoke all on function app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid) from authenticated;

-- ----------------------------------------------------------------------------
-- 7. app.submit_order — faithful re-creation of 20260723090000 lines 375-850
--    with the dormant initial-dispatch tail (see header). Signature UNCHANGED.
-- ----------------------------------------------------------------------------

create or replace function app.submit_order(
  p_pin_session_id              uuid,
  p_order_id                    uuid,
  p_device_id                   uuid,
  p_local_operation_id          text,
  p_order_type                  text,
  p_table_id                    uuid,
  p_shift_id                    uuid,
  p_currency_code               text,
  p_notes                       text,
  p_order_items                 jsonb,
  p_client_subtotal_minor       bigint,
  p_client_discount_total_minor bigint,
  p_client_tax_total_minor      bigint,
  p_client_grand_total_minor    bigint,
  p_client_created_at           timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing_stat  text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_m_rest        uuid;
  v_m_branch      uuid;
  v_existing_id   uuid;
  v_existing_rev  integer;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_line_disc     bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_subtotal      bigint := 0;
  v_grand         bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
  v_unavailable   jsonb;
  v_item_ids      uuid[];
  -- KITCHEN-MODE-001A (all three used ONLY by the additive tail/replay below):
  v_kitchen_mode  text;
  v_auto          jsonb;
  v_existing_status text;
begin
  -- (1-5) PIN session: exists, valid (active/not-ended/not-expired), backing
  -- device session active + not revoked, pairing active. Scope + actor derived here.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found then
    raise exception 'submit_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'submit_order: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;

  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing_stat
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing_stat = 'active') then
    raise exception 'submit_order: backing device session/pairing is not active' using errcode = '42501';
  end if;

  -- (6) the caller's claimed device must be the device behind the PIN session
  if v_ds_device <> p_device_id then
    raise exception 'submit_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;

  -- (9-14) membership: active, role permitted, scope covers the derived branch
  select m.role, m.status, m.deleted_at, m.restaurant_id, m.branch_id
    into v_role, v_m_status, v_m_deleted, v_m_rest, v_m_branch
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'submit_order: resolved membership is not active' using errcode = '42501';
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    raise exception 'submit_order: role % may not submit orders', v_role using errcode = '42501';
  end if;
  if not (v_m_rest is null or v_m_rest = v_rest) or not (v_m_branch is null or v_m_branch = v_branch) then
    raise exception 'submit_order: membership scope does not cover the order branch' using errcode = '42501';
  end if;
  -- NOTE: org/restaurant/branch are taken from the PIN session (v_org/v_rest/v_branch),
  -- NEVER from client input, so a cross-tenant submit is structurally impossible.

  -- (payload) basic shape + currency + order_type
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'submit_order: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;
  if p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'submit_order: invalid order_type %', p_order_type using errcode = '42501';
  end if;
  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'submit_order: currency_code must be a 3-letter ISO code' using errcode = '42501';
  end if;
  if p_client_discount_total_minor < 0 or p_client_tax_total_minor < 0
     or p_client_subtotal_minor < 0 or p_client_grand_total_minor < 0 then
    raise exception 'submit_order: order totals must be non-negative integers (minor units)' using errcode = '42501';
  end if;

  -- (payload+) RESTAURANT-OPERATIONS-V1-001 order-type table SHAPE rules —
  -- payload-stable, so they sit with the shape checks (before the replay
  -- lookup). RETURN-refusals, not raises: sync_push merges them VERBATIM so
  -- the POS can name the rule that fired (§4.35 error contract).
  if p_order_type = 'takeaway' and p_table_id is not null then
    -- takeaway never carries a table; a contradictory payload is refused, not
    -- silently "fixed" (the client's draft state is wrong and must say so).
    return jsonb_build_object('ok', false, 'error', 'table_not_allowed', 'entity', 'order');
  end if;
  if p_order_type = 'dine_in' and p_table_id is null then
    -- NEW dine-in orders require a table. Historical tableless dine-in rows
    -- remain valid (this rule binds acceptance, not stored data).
    return jsonb_build_object('ok', false, 'error', 'table_required', 'entity', 'order');
  end if;

  -- (money recompute) from the SUBMITTED SNAPSHOTS ONLY (never the live menu).
  -- Validate the per-line and order totals; reject any client/snapshot mismatch.
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    -- bound to the integer column range so an absurd quantity yields a clean 42501
    -- rather than a raw 22003 on the ::int insert (and limits qty*price overflow risk).
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'submit_order: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    if (v_item ->> 'menu_item_id') is null then
      raise exception 'submit_order: order_items[].menu_item_id is required' using errcode = '42501';
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      raise exception 'submit_order: order_items[].menu_item_name_snapshot is required' using errcode = '42501';
    end if;

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'submit_order: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;

    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;
    if v_line_total < 0 then
      raise exception 'submit_order: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if p_client_subtotal_minor <> v_subtotal then
    raise exception 'submit_order: client subtotal_minor (%) does not match snapshot recompute (%)',
      p_client_subtotal_minor, v_subtotal using errcode = '42501';
  end if;
  v_grand := v_subtotal - p_client_discount_total_minor + p_client_tax_total_minor;
  if v_grand < 0 then
    raise exception 'submit_order: computed grand_total_minor is negative' using errcode = '42501';
  end if;
  if p_client_grand_total_minor <> v_grand then
    raise exception 'submit_order: client grand_total_minor (%) does not match snapshot recompute (%)',
      p_client_grand_total_minor, v_grand using errcode = '42501';
  end if;

  -- (idempotency) ONLY AFTER full validation: replay scoped to the validated
  -- (org, device, local_operation_id). Returns the same order; never re-inserts;
  -- never bypasses validation; never crosses tenants (org is session-derived).
  select o.id, o.revision, o.status into v_existing_id, v_existing_rev, v_existing_status
    from public.orders o
    where o.organization_id = v_org
      and o.device_id = p_device_id
      and o.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    -- KITCHEN-MODE-001A (ADDITIVE keys only; existing keys byte-identical): the
    -- replay reports the CURRENT authoritative status, so a replayed zero-total
    -- printer-only submit consistently reads back `completed`. `auto_completed`
    -- on the replay path means "this order is completed NOW" — clients that
    -- predate the key ignore it.
    return jsonb_build_object(
      'ok', true, 'order_id', v_existing_id, 'revision', v_existing_rev,
      'server_ts', now(), 'idempotency_replay', true,
      'auto_completed', (v_existing_status = 'completed'),
      'order_status', v_existing_status);
  end if;

  -- (accept) RESTAURANT-OPERATIONS-V1-001 TIME-VARYING acceptance checks —
  -- deliberately AFTER the replay lookup (an already-accepted order must keep
  -- replaying even if its table or an item's availability changed since) and
  -- BEFORE any insert (a refusal never leaves a partial order).
  --
  -- (accept-1) the dine-in table must be a LIVE, ACTIVE, IN-SERVICE table of
  -- the SESSION branch. A foreign-branch, tombstoned, deactivated,
  -- out-of-service, or unknown table is the SAME refusal — the device learns
  -- nothing about other branches (R-003). STABILIZATION: out_of_service is a
  -- HARD manual floor state (a broken table); under a stale client list the
  -- picker's block is not enough, so the server refuses it too. reserved/
  -- occupied remain seatable (the reserving party arriving IS the seating).
  if p_order_type = 'dine_in' and not exists (
       select 1 from public.tables t
       where t.id              = p_table_id
         and t.organization_id = v_org
         and t.restaurant_id   = v_rest
         and t.branch_id       = v_branch
         and t.is_active
         and t.status <> 'out_of_service'
         and t.deleted_at is null) then
    return jsonb_build_object('ok', false, 'error', 'table_not_available', 'entity', 'order');
  end if;

  -- (accept-2) REVIEW CORRECTION (A1 + A2): every line item must be a REAL,
  -- SELLABLE item of the session menu — proven, not presumed — and AVAILABLE
  -- in the session branch, evaluated under a SHARED LOCK so an availability
  -- flip can never race past acceptance.
  --
  -- A1 — the CANONICAL sellability predicate, identical to what app.pos_menu
  -- serves the POS (order_items.menu_item_id is deliberately non-FK, so a
  -- stale or manipulated cart could previously submit an unknown, deleted,
  -- inactive, sibling-branch or foreign-scope id and still create an order):
  --   item:     exists in v_org + v_rest, is_active, deleted_at IS NULL,
  --             branch-visible (branch_id IS NULL OR = v_branch);
  --   category: parent exists, is_active, deleted_at IS NULL, branch-visible;
  --   effective availability: no 'unavailable' override for (v_branch, item).
  -- Absence of an override means available ONLY once the item is proven
  -- sellable. ALL non-sellable cases fail closed as ONE indistinguishable
  -- refusal (error item_unavailable, reason 'unavailable') so nothing —
  -- sibling-branch pins included — becomes an existence oracle (R-003).
  -- Explicit overrides keep their structured reason (sold_out|paused). The
  -- name echoed back is the CLIENT'S OWN payload snapshot, never DB data.
  -- D-008 is untouched: nothing here reprices from the live menu.
  --
  -- A2 — the TOCTOU serialization point: lock the CANONICAL menu_items rows
  -- (the same rows app.menu_set_item_availability locks) BEFORE evaluating.
  -- Locking the override row would not work — it may not exist yet. Locks are
  -- taken in one statement in DETERMINISTIC ascending id order, so two carts
  -- sharing items can never deadlock (and the setter locks exactly one row).
  -- Unknown/foreign ids match no row and take no lock — they fail the
  -- sellability check regardless, and there is nothing to serialize with.
  -- If the setter committed 'unavailable' first, this read (under lock) sees
  -- it and refuses; if this submit locked first, the setter WAITS until the
  -- accepted order commits and its change applies to later orders only.
  select array_agg(distinct (e ->> 'menu_item_id')::uuid)
    into v_item_ids
    from jsonb_array_elements(p_order_items) e;
  perform 1
    from public.menu_items i
    where i.organization_id = v_org
      and i.id = any (v_item_ids)
    order by i.id
    for update;

  select jsonb_agg(jsonb_build_object(
           'menu_item_id', blocked.menu_item_id,
           'name',         blocked.name,
           'reason',       blocked.reason)
           order by blocked.menu_item_id)
    into v_unavailable
    from (
      select li.menu_item_id,
             li.name,
             coalesce(a.reason, 'unavailable') as reason
        from (
          select (e ->> 'menu_item_id')::uuid as menu_item_id,
                 min(e ->> 'menu_item_name_snapshot') as name
            from jsonb_array_elements(p_order_items) e
            group by 1
        ) li
        left join public.menu_items i
          on i.id = li.menu_item_id
         and i.organization_id = v_org
         and i.restaurant_id   = v_rest
         and i.is_active
         and i.deleted_at is null
         and (i.branch_id is null or i.branch_id = v_branch)
        left join public.menu_categories c
          on c.id = i.menu_category_id
         -- REVIEW DELTA (HIGH): the category must belong to the EXACT session
         -- scope — org AND restaurant. The schema permits an item of
         -- restaurant A referencing a category of restaurant B in the same
         -- org; without the restaurant predicate such a hybrid item passed as
         -- sellable here while pos_menu's category list is restaurant-scoped.
         and c.organization_id = v_org
         and c.restaurant_id   = v_rest
         and c.is_active
         and c.deleted_at is null
         and (c.branch_id is null or c.branch_id = v_branch)
        left join public.menu_item_branch_availability a
          on a.organization_id = v_org
         and a.branch_id       = v_branch
         and a.menu_item_id    = li.menu_item_id
         and a.availability    = 'unavailable'
        where i.id is null            -- unknown / foreign / inactive / deleted / pinned elsewhere
           or c.id is null            -- category missing / inactive / deleted / not visible here
           or a.menu_item_id is not null  -- explicitly unavailable in this branch
    ) blocked;
  if v_unavailable is not null then
    return jsonb_build_object('ok', false, 'error', 'item_unavailable',
                              'entity', 'order', 'items', v_unavailable);
  end if;

  -- (insert) order header at status 'submitted'
  insert into public.orders (
    id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, table_id, shift_id,
    order_type, status, currency_code,
    subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor,
    notes, local_operation_id, revision, client_created_at)
  values (
    p_order_id, v_org, v_rest, v_branch, p_device_id, p_pin_session_id,
    v_emp, v_membership, p_table_id, p_shift_id,
    p_order_type, 'submitted', p_currency_code,
    v_subtotal, p_client_discount_total_minor, p_client_tax_total_minor, v_grand,
    p_notes, p_local_operation_id, 1, p_client_created_at);

  -- (insert) items at status 'pending' + their modifiers, recomputing line_total
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;

    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor, notes, prep_snapshot)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', v_line_disc, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot')
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          raise exception 'submit_order: modifiers[].modifier_option_id is required' using errcode = '42501';
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          raise exception 'submit_order: modifiers[].option_name_snapshot is required' using errcode = '42501';
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int, v_modifier -> 'meat_snapshot');
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (audit) append-only order.submitted event (D-013, API_CONTRACT §4.1) in the
  -- SAME transaction. This SECURITY DEFINER RPC writes it as the audit_events
  -- table owner (RF-017 grants app roles NO insert; the append-only trigger
  -- blocks only UPDATE/DELETE/TRUNCATE). The idempotency-replay path returns
  -- earlier, so a replay NEVER writes a second audit row. actor =
  -- employee_profile (RF-017 requires app_user OR employee_profile present).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch,
    null, v_emp, p_device_id,
    'order.submitted', null, null,
    jsonb_build_object(
      'order_id',               p_order_id,
      'status',                 'submitted',
      'revision',               1,
      'currency_code',          p_currency_code,
      'subtotal_minor',         v_subtotal,
      'discount_total_minor',   p_client_discount_total_minor,
      'tax_total_minor',        p_client_tax_total_minor,
      'grand_total_minor',      v_grand,
      'device_id',              p_device_id,
      'local_operation_id',     p_local_operation_id,
      'order_type',             p_order_type,
      'table_id',               p_table_id,
      'shift_id',               p_shift_id,
      'resolved_membership_id', v_membership,
      'item_count',             v_item_count,
      'modifier_count',         v_mod_count));

  -- ---------------------------------------------------------------------------
  -- KITCHEN-MODE-001A (DORMANT, additive tail): a ZERO-TOTAL order submitted in
  -- a `printer_only` branch settles with NOTHING to pay (app.order_is_fully_settled
  -- returns true for grand_total_minor = 0 with NO payment row) and has no
  -- payment.create event to trigger completion — so the SAME auto-completion
  -- helper runs here, at the authoritative tail: grand total is known and
  -- validated, the order + items + audit are durably written, and this
  -- transaction still holds the exclusive lock on the freshly-inserted order
  -- row (satisfying the helper's caller-holds-the-lock contract). The helper
  -- alone decides eligibility: in the default `kds` mode it returns
  -- not_eligible for a `submitted` order, so kds-branch behavior — including
  -- kds zero-total behavior — is byte-identical to before. NO payment row and
  -- NO tender is ever fabricated; the helper is fail-soft, so a completion
  -- side-effect failure can never turn a successful submit into an error.
  -- ---------------------------------------------------------------------------
  -- KITCHEN-MODE-001C1: the ONE mode read for the whole tail (the same
  -- fail-closed coalesce-to-kds semantics as before; the read simply moved
  -- above the zero-total gate so the dispatch block below can share it).
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id              = v_branch
      and b.organization_id = v_org
      and b.deleted_at is null;

  -- KITCHEN-MODE-001C1 (DORMANT): EVERY accepted printer-only order gets its
  -- durable, idempotent, money-free kitchen dispatch IN THIS SAME TRANSACTION.
  -- A dispatch failure fails the submit (an accepted printer-only order may
  -- never silently miss its kitchen ticket) and a rolled-back submit leaves
  -- no dispatch. kds branches create NOTHING — byte-identical behavior.
  if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'initial_order',
      app.kitchen_dispatch_payload_initial(v_org, p_order_id),
      v_emp, v_membership, p_device_id);
  end if;

  if v_grand = 0 then
    if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
      v_auto := app.try_auto_complete_order(
        v_org, v_rest, v_branch, p_order_id,
        'order_submitted',
        null,          -- no JWT actor on the PIN path
        v_emp, v_membership, v_role,
        p_device_id, p_local_operation_id);
    end if;
  end if;

  -- KITCHEN-MODE-001A: ADDITIVE keys only — `ok`/`order_id`/`server_ts`/
  -- `idempotency_replay` are byte-identical; `revision` still reports the
  -- order's CURRENT revision (1, or 2 when the dormant zero-total completion
  -- just bumped it — reporting 1 for a revision-2 row would poison client
  -- reconciliation). Clients that predate the new keys ignore them.
  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id,
    'revision', coalesce((v_auto ->> 'revision')::integer, 1),
    'server_ts', now(), 'idempotency_replay', false,
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status', case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else 'submitted' end);
end;
$$;


comment on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'RF-052 .. RESTAURANT-OPERATIONS-V1-001 .. KITCHEN-MODE-001A + KITCHEN-MODE-001C1. Signature and every kds-mode behavior UNCHANGED (faithful re-creation of the 20260723090000 body). KITCHEN-MODE-001C1 (DORMANT): a printer_only branch additionally writes ONE idempotent money-free kitchen dispatch in the SAME transaction (before the 001A zero-total completion tail, sharing its fail-closed mode read); kds branches are byte-identical. Print/dispatch state never joins order state.';

revoke all on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) from public;
grant execute on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. app.add_order_items — faithful re-creation of 20260722090000 lines
--    243-692 with the dormant round-dispatch tail. Signature UNCHANGED.
-- ----------------------------------------------------------------------------

create or replace function app.add_order_items(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_order_items        jsonb,
  p_client_created_at  timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing       text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_device_type   text;
  v_o_status      text;
  v_o_type        text;
  v_o_rev         integer;
  v_o_sub         bigint;
  v_o_disc        bigint;
  v_o_tax         bigint;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_delta         bigint := 0;
  v_new_sub       bigint;
  v_new_grand     bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
  v_unavailable   jsonb;
  v_item_ids      uuid[];
  v_round_id      uuid;
  v_kitchen_mode  text;  -- KITCHEN-MODE-001C1: branch workflow mode (dispatch gate)
  v_round_no      integer;
  v_new_rev       integer;
  v_ex_round      uuid;
  v_ex_order      uuid;
  v_ex_number     integer;
  v_ex_count      integer;
  v_shape_error   text;
  v_order_code    text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) THE CANONICAL PIN PREAMBLE (submit_order parity): session exists+valid,
  --     backing device session/pairing active, device match, membership active.
  --     Every structural failure raises 42501. Scope derived HERE, never payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'add_order_items: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'add_order_items: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'add_order_items: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'add_order_items: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'add_order_items: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) DEVICE CLASS: additions are a POS act (the mirror of kitchen_ack_void's
  --     KDS-only rule). A KDS device is refused regardless of role.
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role,
                               'device_type', coalesce(v_device_type, 'unknown'),
                               'denied_reason', 'invalid_device_type'));
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) ROLE: cashier+ may add items (submit_order parity — no new capability;
  --     kitchen_staff/accountant denied).
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) payload envelope shape (structural, submit_order parity).
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'add_order_items: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;

  -- (e) PER-LINE SHAPE + ARITHMETIC — the submit_order recompute loop (D-008),
  --     replicated (see the header). Two deliberate deltas for ADDED lines:
  --       * NO order-level client totals exist to cross-check — the deltas are
  --         computed HERE and applied to the parent (server-authoritative);
  --       * a nonzero line_discount_minor is REJECTED (typed) — an addition
  --         never carries a hidden price cut.
  --     Missing identity/name fields are the TYPED invalid_item_payload refusal
  --     (the POS names the broken line); numeric parse failures keep the
  --     structural app.order_parse_minor raise (submit parity).
  v_shape_error := null;
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    if (v_item ->> 'menu_item_id') is null then
      v_shape_error := 'menu_item_id_required';
      exit;
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      v_shape_error := 'menu_item_name_snapshot_required';
      exit;
    end if;
    if (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
       and app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor') <> 0 then
      v_shape_error := 'line_discount_not_allowed';
      exit;
    end if;
    v_qty := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'add_order_items: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          v_shape_error := 'modifier_option_id_required';
          exit;
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          v_shape_error := 'option_name_snapshot_required';
          exit;
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'add_order_items: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
      if v_shape_error is not null then
        exit;
      end if;
    end if;

    v_line_total := v_qty * v_unit + v_mod_sum;
    if v_line_total < 0 then
      raise exception 'add_order_items: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_delta := v_delta + v_line_total;
  end loop;
  if v_shape_error is not null then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'denied_reason', 'invalid_item_payload'));
    return jsonb_build_object('ok', false, 'error', 'invalid_item_payload', 'detail', v_shape_error,
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (f) IDEMPOTENCY REPLAY (submit_order parity: after full payload validation,
  --     before the time-varying checks): the SAME (org, device, local_operation_id)
  --     returns the SAME round — no duplicate round, no duplicate items — even if
  --     the parent's state has since moved on. The same key on a DIFFERENT order
  --     is a conflict (40001), mirroring record_payment.
  select r.id, r.order_id, r.round_number
    into v_ex_round, v_ex_order, v_ex_number
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.device_id = p_device_id
      and r.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    if v_ex_order <> p_order_id then
      raise exception 'add_order_items: idempotency key already used for a different order (%, not %)', v_ex_order, p_order_id using errcode = '40001';
    end if;
    select count(*)::int into v_ex_count
      from public.order_items oi
      where oi.organization_id = v_org and oi.service_round_id = v_ex_round;
    select o.revision into v_o_rev from public.orders o where o.id = p_order_id and o.organization_id = v_org;
    return jsonb_build_object(
      'ok', true, 'order_id', p_order_id, 'round_id', v_ex_round, 'round_number', v_ex_number,
      'added_item_count', v_ex_count, 'revision', v_o_rev,
      'server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (g) ONE SCOPED PARENT LOOKUP, FOR UPDATE — the FIRST lock (the same first
  --     lock payment/void/status/discount take). ANTI-ORACLE (R-003, the
  --     PSC-001D F1 pattern): a nonexistent order and a foreign-tenant order
  --     raise the SAME structural 42501.
  select o.status, o.order_type, o.revision, o.subtotal_minor, o.discount_total_minor, o.tax_total_minor
    into v_o_status, v_o_type, v_o_rev, v_o_sub, v_o_disc, v_o_tax
    from public.orders o
    where o.id = p_order_id
      and o.organization_id = v_org
      and o.restaurant_id   = v_rest
      and o.branch_id       = v_branch
      and o.deleted_at is null
    for update;
  if not found then
    raise exception 'add_order_items: order_not_found_or_not_accessible' using errcode = '42501';
  end if;

  -- (h) ELIGIBILITY (typed RETURN-refusals, each audited).
  if v_o_type <> 'dine_in' then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_type', v_o_type, 'denied_reason', 'order_not_dine_in'));
    return jsonb_build_object('ok', false, 'error', 'order_not_dine_in', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'order_not_eligible'));
    return jsonb_build_object('ok', false, 'error', 'order_not_eligible', 'order_id', p_order_id,
                              'order_status', v_o_status, 'server_ts', now(), 'idempotency_replay', false);
  end if;
  -- The PAYMENT FREEZE (apply_discount precedent): a live COMPLETED payment
  -- froze the bill it covered. record_payment allows at most ONE completed
  -- payment and always charges the CURRENT total, so a post-payment addition
  -- could never be settled — and the numbered receipt's total must stay true.
  -- (A zero-total order with NO completed payment falls through: still open,
  -- still eligible, and the addition simply makes it chargeable again.)
  if exists (
       select 1 from public.payments p
       where p.organization_id = v_org
         and p.order_id = p_order_id
         and p.status = 'completed'
         and p.deleted_at is null) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'order_already_settled'));
    return jsonb_build_object('ok', false, 'error', 'order_already_settled', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (i) SELLABILITY + AVAILABILITY under ascending-id FOR UPDATE menu locks —
  --     the submit_order accept-2 block, replicated verbatim (same predicate,
  --     same TOCTOU serialization point, same uniform refusal — R-003).
  select array_agg(distinct (e ->> 'menu_item_id')::uuid)
    into v_item_ids
    from jsonb_array_elements(p_order_items) e;
  perform 1
    from public.menu_items i
    where i.organization_id = v_org
      and i.id = any (v_item_ids)
    order by i.id
    for update;

  select jsonb_agg(jsonb_build_object(
           'menu_item_id', blocked.menu_item_id,
           'name',         blocked.name,
           'reason',       blocked.reason)
           order by blocked.menu_item_id)
    into v_unavailable
    from (
      select li.menu_item_id,
             li.name,
             coalesce(a.reason, 'unavailable') as reason
        from (
          select (e ->> 'menu_item_id')::uuid as menu_item_id,
                 min(e ->> 'menu_item_name_snapshot') as name
            from jsonb_array_elements(p_order_items) e
            group by 1
        ) li
        left join public.menu_items i
          on i.id = li.menu_item_id
         and i.organization_id = v_org
         and i.restaurant_id   = v_rest
         and i.is_active
         and i.deleted_at is null
         and (i.branch_id is null or i.branch_id = v_branch)
        left join public.menu_categories c
          on c.id = i.menu_category_id
         and c.organization_id = v_org
         and c.restaurant_id   = v_rest
         and c.is_active
         and c.deleted_at is null
         and (c.branch_id is null or c.branch_id = v_branch)
        left join public.menu_item_branch_availability a
          on a.organization_id = v_org
         and a.branch_id       = v_branch
         and a.menu_item_id    = li.menu_item_id
         and a.availability    = 'unavailable'
        where i.id is null
           or c.id is null
           or a.menu_item_id is not null
    ) blocked;
  if v_unavailable is not null then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'item_unavailable'));
    return jsonb_build_object('ok', false, 'error', 'item_unavailable',
                              'entity', 'order', 'items', v_unavailable,
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (j) ALLOCATE the round number under the held parent lock: max(round_number)
  --     across ALL rows of this order (voided/deleted INCLUDED — a number is
  --     NEVER reused), +1; the very first addition is ROUND 2 (the original
  --     order is kitchen work unit 1). Serialized by the parent lock; the
  --     per-order unique constraint is the layer-4 backstop.
  select coalesce(max(r.round_number), 1) + 1
    into v_round_no
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.order_id        = p_order_id;

  v_round_id := gen_random_uuid();
  insert into public.order_service_rounds (
    id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, local_operation_id,
    revision, client_created_at)
  values (
    v_round_id, v_org, v_rest, v_branch, p_order_id, v_round_no,
    'submitted', p_device_id, v_emp, p_local_operation_id,
    1, p_client_created_at);

  -- (k) insert the ADDED items (status 'pending', submit_order parity) with
  --     their round membership, + modifiers. line_discount_minor is FORCED 0
  --     (validated above).
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty  := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * v_unit + v_mod_sum;

    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor,
      notes, prep_snapshot, service_round_id)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', 0, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot', v_round_id)
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int, v_modifier -> 'meat_snapshot');
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (l) PARENT TOTALS (server-authoritative, D-007): subtotal grows by the
  --     recomputed delta; the ABSOLUTE prior discount and the stored tax stay
  --     EXACTLY as they were (locked: never silently re-scaled); the grand
  --     follows the ONE canonical formula. The parent status is NEVER moved.
  v_new_sub   := v_o_sub + v_delta;
  v_new_grand := v_new_sub - v_o_disc + v_o_tax;
  if v_new_grand < 0 then
    raise exception 'add_order_items: computed grand_total_minor is negative' using errcode = '42501';
  end if;
  v_new_rev := v_o_rev + 1;
  update public.orders
    set subtotal_minor = v_new_sub, grand_total_minor = v_new_grand, revision = v_new_rev
    where id = p_order_id;

  -- (m) audit order.items_added (D-013): safe scalars only — and MONEY-FREE
  -- (PSC-001C correction, Finding 6): the approved contract for the four new
  -- service-round actions carries NO monetary field. What was added and to
  -- which order is the operational record; the money moved is derivable from
  -- the order's own authoritative rows, never from this trail.
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_added', null,
          jsonb_build_object('order_id', p_order_id, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'round_number', v_round_no, 'added_item_count', v_item_count,
                             'order_status', v_o_status, 'role', v_role,
                             'device_type', v_device_type,
                             'revision', v_new_rev,
                             'local_operation_id', p_local_operation_id,
                             'resolved_membership_id', v_membership));

  -- KITCHEN-MODE-001C1 (DORMANT): a printer-only branch gets ONE durable
  -- service-round dispatch in this SAME transaction — the ROUND DELTA only,
  -- idempotent by round id, nothing for kds branches, and nothing survives a
  -- rollback. A dispatch failure fails the addition (fail closed).
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, v_round_id, 'service_round',
      app.kitchen_dispatch_payload_round(v_org, p_order_id, v_round_id),
      v_emp, v_membership, p_device_id);
  end if;

  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id, 'round_id', v_round_id, 'round_number', v_round_no,
    'added_item_count', v_item_count, 'revision', v_new_rev,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;


comment on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) is
  'PSC-001C service rounds + KITCHEN-MODE-001C1. Signature, locking, round numbering, validation, idempotency, audit and every kds-mode behavior UNCHANGED (faithful re-creation of the 20260722090000 body). KITCHEN-MODE-001C1 (DORMANT): a printer_only branch additionally writes ONE idempotent money-free ROUND-DELTA dispatch in the SAME transaction; kds branches are byte-identical.';

revoke all on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) from public;
grant execute on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. app.void_order — faithful re-creation of 20260722090000 lines 1373-1642
--    (the NEWEST body: PSC-001D void provenance PLUS the PSC-001C whole-order
--    round sweep) with the dormant void-dispatch tail. Signature UNCHANGED.
-- ----------------------------------------------------------------------------

create or replace function app.void_order(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_reason             text,
  p_expected_revision  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_m_perms      jsonb;
  v_o_org        uuid;
  v_o_branch     uuid;
  v_o_status     text;
  v_o_rev        integer;
  v_authorized   boolean;
  v_new_rev      integer;
  v_voided_items integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
  v_kitchen_mode text;  -- KITCHEN-MODE-001C1: branch workflow mode (dispatch gate)
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'void_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'void_order: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'void_order: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'void_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'void_order: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant).
  --     RF-062 (A4): FOR UPDATE locks the order row so void_order serializes with
  --     record_payment (which now also locks the order row) on the SAME order — a
  --     payment cannot complete between the (g2) guard and the void.
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'void_order: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'void_order: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A1): manager/restaurant_owner/org_owner, OR a cashier with an
  --     explicit memberships.permissions->>'void_order' = 'true' grant. RF053-B1:
  --     authorization runs BEFORE the idempotency replay so an unauthorized actor can
  --     never replay a prior SUCCESS result. A DENIAL is audited (order.void_denied)
  --     + RETURNED (no raise, so the audit persists) with NO state change and NO ledger
  --     write (the ledger holds only authorized successes; denials are always re-audited
  --     as probe attempts, never replayed).
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or app.cashier_capability_allowed(v_role, v_m_perms, 'void_order');

  if not v_authorized then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) reason mandatory (AC#2)
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'void_order: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + reason, BEFORE the
  --     voidable-source-state check (the order becomes 'voided' after the first
  --     success). ORDER-BOUND: the stored op MUST be for the same order; the same
  --     (org, device, local_operation_id, action) reused on a DIFFERENT order is a
  --     conflict, not a replay (never leaks the original order's result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'void_order';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'void_order: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'void_order: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (g) state legality (AC#3, D-024): only pre-completion non-terminal source states.
  --     ELIGIBILITY IS UNCHANGED — the legal set is still exactly
  --     submitted/accepted/preparing/ready/served, `completed` remains TERMINAL, and there
  --     is NO completed -> void path. Only the SHAPE of the refusal changes.
  --
  --     MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): RETURN the stable domain code
  --     instead of raising. app.sync_push REBUILDS the envelope from scratch for a RAISE
  --     (collapsing every domain code to the generic literal 'rejected'), but merges a
  --     RETURNED envelope through VERBATIM. Raising left the POS unable to tell
  --     "this order is already closed" apart from a dropped network, a malformed response
  --     or any other rejection — so it was reduced to GUESSING from the order's total, and
  --     could tell an operator an order was closed when the connection had merely failed.
  --
  --     `error` is the established coarse class for an illegal state change
  --     (`invalid_transition`, as the order state machine already uses) and `detail` is the
  --     established fine-grained safe token (as order_has_completed_payment already is).
  --     `order_status` is a STATE, never an identifier — safe to return.
  --
  --     AUDITED like the other two RETURN-based denials in this function
  --     (order.void_denied + denied_reason). A raise could not have audited at all: it
  --     would have rolled the audit row back. NO state change, NO revision bump, NO
  --     order_operations ledger row (denials are re-audited as probe attempts, never
  --     replayed).
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_not_voidable'));
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'detail', 'order_not_voidable', 'order_id', p_order_id,
                              'order_status', v_o_status,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g2) RF-062 COMPLETED-PAYMENT GUARD (D-023/D-024; STATE_MACHINES §1; API_CONTRACT
  --      §4.6): an order with a LIVE `completed` payment cannot be voided in MVP — there
  --      is no refund/reversal flow. Checked AFTER authorization, reason, the idempotency
  --      replay, expected_revision, and state legality, BEFORE any mutation, so: a prior
  --      successful void still replays at (e) (a voided order can never acquire a
  --      completed payment afterward — record_payment rejects non-eligible orders); a
  --      genuinely terminal status is still refused at (g), which now RETURNS the typed
  --      domain refusal (invalid_transition + detail=order_not_voidable + order_status)
  --      rather than raising an untyped 42501 — so the two refusals stay DISTINGUISHABLE
  --      to the client; and only a
  --      legal-source order that nonetheless carries settled money reaches here. The
  --      order row is locked FOR UPDATE (b) and record_payment also locks it, so a
  --      concurrent payment cannot slip in. A4/A5/A3 decisions: block ONLY a live
  --      `completed` payment (deleted_at IS NULL; no method filter — any completed
  --      payment blocks); org-scoped to the session-derived v_org (tenant-safe); AUDIT
  --      `order.void_denied` (denied_reason=order_has_completed_payment) + RETURN a
  --      permission_denied envelope (NO raise — a raise would roll back the audit), with
  --      NO state change to order/order_items/payment and NO order_operations ledger row
  --      (denials are re-audited as probe attempts on retry, never replayed).
  if exists (
    select 1
    from public.payments p
    where p.organization_id = v_org
      and p.order_id = p_order_id
      and p.status = 'completed'
      and p.deleted_at is null
  ) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_has_completed_payment'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'detail', 'order_has_completed_payment', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (h) mutate: order -> voided (+reason, +revision); cascade items -> voided.
  --     PSC-001D: the SAME statement stamps the void PROVENANCE — when it
  --     happened, which state it was in, and whether the kitchen must
  --     acknowledge (an ACTIVE kitchen source: submitted|accepted|preparing|
  --     ready; a served-source void is already off the board). The
  --     acknowledgement triple stays NULL until app.kitchen_ack_void.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status = 'voided', void_reason = p_reason, revision = v_new_rev,
        voided_at = now(),
        voided_from_status = v_o_status,
        kitchen_ack_required = (v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))
    where id = p_order_id;

  update public.order_items
    set status = 'voided', void_reason = p_reason
    where order_id = p_order_id and organization_id = v_org
      and status not in ('voided', 'cancelled');
  get diagnostics v_voided_items = row_count;
  -- PSC-001C: the whole-order void ALSO sweeps every live ADDITIONAL service
  -- round to `voided` (round void_reason stamped; ready_at PRESERVED — the
  -- historical ready occurrence must survive for the feed; item snapshots and
  -- round membership untouched — the items were already cascaded above). After
  -- this no round transition is possible (parent_order_voided) and the parent
  -- can never complete (voided is terminal AND a voided round blocks
  -- app.order_rounds_all_served). There is NO independent round-void feature.
  update public.order_service_rounds
    set status = 'voided', void_reason = p_reason, revision = revision + 1
    where order_id = p_order_id and organization_id = v_org
      and status <> 'voided';

  -- (i) audit (order.voided) with old/new values (D-013). PSC-001D adds the two
  --     safe provenance scalars (a closed status enum + a boolean — never money,
  --     never an identifier; T-003 holds).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'order.voided', p_reason,
    jsonb_build_object('status', v_o_status, 'revision', v_o_rev),
    jsonb_build_object('status', 'voided', 'revision', v_new_rev,
                       'void_reason', p_reason, 'voided_item_count', v_voided_items,
                       'resolved_membership_id', v_membership,
                       'voided_from_status', v_o_status,
                       'kitchen_ack_required', (v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))));

  -- (j) record ledger + return
  v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'status', 'voided', 'revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'void_order', p_order_id, v_result);

  -- KITCHEN-MODE-001C1 (DORMANT): when the branch is printer_only and the
  -- kitchen MAY HAVE SEEN this order — the SAME conservative PSC-001D
  -- predicate that drives kitchen_ack_required, OR any prior kitchen dispatch
  -- exists for the order — one durable VOID dispatch is created in this SAME
  -- transaction. Unclaimed prior dispatches are superseded by it (the kitchen
  -- never saw them); claimed/completed ones stay (the kitchen may hold their
  -- paper). kds branches create nothing; a rollback leaves nothing.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if coalesce(v_kitchen_mode, 'kds') = 'printer_only'
     and ((v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))
          or exists (select 1 from public.kitchen_print_dispatches d
                      where d.organization_id = v_org and d.order_id = p_order_id)) then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'void',
      app.kitchen_dispatch_payload_void(v_org, p_order_id, p_reason),
      v_emp, v_membership, p_device_id);
  end if;

  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;


comment on function app.void_order(uuid, uuid, uuid, text, text, integer) is
  'RF-062 .. MONEY-VOID-001 .. PSC-001D/PSC-001C + KITCHEN-MODE-001C1. Signature, paid-order restrictions, provenance stamps (voided_from_status / kitchen_ack_required), the PSC-001C whole-order round sweep, audit and every kds-mode behavior UNCHANGED (faithful re-creation of the 20260722090000 body). KITCHEN-MODE-001C1 (DORMANT): a printer_only branch whose kitchen MAY HAVE SEEN the order (the same conservative PSC-001D predicate, or any prior dispatch) additionally writes ONE idempotent money-free VOID dispatch in the SAME transaction, superseding the order''s unclaimed priors; kds branches are byte-identical.';

revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from public;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 10. Device readiness report RPC (+wrapper). Device-token authenticated with
--     the FULL 001A-corrected liveness contract; POS devices only.
-- ----------------------------------------------------------------------------
create or replace function app.report_kitchen_printer_readiness(
  p_device_id              uuid,
  p_session_token          text,
  p_capability             text,
  p_app_build              text,
  p_printer_purpose        text,
  p_transport_kind         text,
  p_paper_width            text,
  p_printer_fingerprint    text,
  p_secure_spool_available boolean,
  p_unresolved_local_jobs  integer,
  p_mode_revision          integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash    text;
  v_org     uuid;
  v_rest    uuid;
  v_branch  uuid;
  v_dtype   text;
  v_rev     integer;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- FULL device-liveness contract (the 001A-corrected template): non-expired
  -- active session, active pairing, live device, live+active branch/
  -- restaurant/organization. Scope comes EXCLUSIVELY from the proven session.
  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;
  if v_dtype <> 'pos' then
    -- KDS devices are explicitly denied — readiness is a POS capability.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;

  -- Typed validation (closed vocabularies; the CHECKs re-prove at the row).
  if p_capability is distinct from 'kitchen_printer_only_v1' then
    return jsonb_build_object('ok', false, 'error', 'unsupported_capability');
  end if;
  if p_printer_purpose is distinct from 'kitchen_ticket' then
    return jsonb_build_object('ok', false, 'error', 'unsupported_purpose');
  end if;
  if p_transport_kind is null or p_transport_kind not in ('network', 'bluetooth') then
    return jsonb_build_object('ok', false, 'error', 'unsupported_transport');
  end if;
  if p_paper_width is null or p_paper_width not in ('58mm', '80mm') then
    return jsonb_build_object('ok', false, 'error', 'unsupported_paper_width');
  end if;
  if p_app_build is null or length(btrim(p_app_build)) not between 1 and 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_app_build');
  end if;
  if p_printer_fingerprint is null or p_printer_fingerprint !~ '^[0-9a-f]{16,128}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_fingerprint');
  end if;
  if p_secure_spool_available is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_spool_state');
  end if;
  if p_unresolved_local_jobs is null or p_unresolved_local_jobs < 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_unresolved_count');
  end if;

  select b.kitchen_workflow_mode_revision into v_rev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if p_mode_revision is distinct from v_rev then
    return jsonb_build_object('ok', false, 'error', 'stale_mode_revision', 'mode_revision', v_rev);
  end if;

  -- ONE current report per device (upsert; the server owns the clock).
  insert into public.kitchen_printer_readiness_reports
    (organization_id, restaurant_id, branch_id, device_id, capability,
     app_build, printer_purpose, transport_kind, paper_width,
     printer_fingerprint, secure_spool_available, unresolved_local_jobs,
     mode_revision, reported_at, expires_at)
  values
    (v_org, v_rest, v_branch, p_device_id, p_capability,
     btrim(p_app_build), p_printer_purpose, p_transport_kind, p_paper_width,
     p_printer_fingerprint, p_secure_spool_available, p_unresolved_local_jobs,
     p_mode_revision, now(), now() + interval '10 minutes')
  on conflict (organization_id, device_id) do update set
     restaurant_id          = excluded.restaurant_id,
     branch_id              = excluded.branch_id,
     capability             = excluded.capability,
     app_build              = excluded.app_build,
     printer_purpose        = excluded.printer_purpose,
     transport_kind         = excluded.transport_kind,
     paper_width            = excluded.paper_width,
     printer_fingerprint    = excluded.printer_fingerprint,
     secure_spool_available = excluded.secure_spool_available,
     unresolved_local_jobs  = excluded.unresolved_local_jobs,
     mode_revision          = excluded.mode_revision,
     reported_at            = excluded.reported_at,
     expires_at             = excluded.expires_at,
     updated_at             = now();

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_printer_readiness',
    -- Honest contract: readiness = "transport accepted the test bytes and the
    -- device reported its local state" — NEVER a physical-paper claim.
    'meaning', 'transport_accepted_not_paper_confirmed',
    'activation_ready', (p_paper_width = '80mm' and p_secure_spool_available),
    'expires_at', now() + interval '10 minutes',
    'server_ts', now());
end;
$$;

comment on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) is
  'KITCHEN-MODE-001C1: the POS device''s kitchen-printing readiness report (device-token authenticated with the full 001A-corrected liveness contract; KDS explicitly denied; scope exclusively from the proven session). Validates the closed capability/purpose/transport/paper vocabularies, the NON-SECRET fingerprint digest shape, and the branch mode revision; upserts the device''s ONE current report with a server-owned 10-minute validity. Readiness means transport-accepted test bytes + reported local state — never physical paper. NOTE (D-013): no audit row — audit_events requires a human actor and this is a device-only path; observability lives on the report row itself. No client calls this until 001C2/001C3.';

create or replace function public.report_kitchen_printer_readiness(
  p_device_id uuid, p_session_token text, p_capability text, p_app_build text,
  p_printer_purpose text, p_transport_kind text, p_paper_width text,
  p_printer_fingerprint text, p_secure_spool_available boolean,
  p_unresolved_local_jobs integer, p_mode_revision integer)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.report_kitchen_printer_readiness(p_device_id, p_session_token, p_capability, p_app_build, p_printer_purpose, p_transport_kind, p_paper_width, p_printer_fingerprint, p_secure_spool_available, p_unresolved_local_jobs, p_mode_revision); $$;

revoke all on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from public;
grant execute on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) to authenticated;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from public;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from anon;
grant execute on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 11. Atomic claim-and-pull (+wrapper).
-- ----------------------------------------------------------------------------
create or replace function app.pull_kitchen_print_dispatches(
  p_device_id         uuid,
  p_session_token     text,
  p_limit             integer default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id         uuid default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash    text;
  v_org     uuid;
  v_rest    uuid;
  v_branch  uuid;
  v_dtype   text;
  v_mode    text;
  v_limit   integer;
  v_rows    jsonb;
  v_count   integer;
  v_last_at timestamptz;
  v_last_id uuid;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'kitchen_print_dispatches');
  end if;
  if (p_cursor_created_at is null) <> (p_cursor_id is null) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'kitchen_print_dispatches');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if v_dtype <> 'pos' then
    -- KDS is explicitly denied: printer-only dispatch payloads never reach a
    -- KDS client through any channel.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;

  select b.kitchen_workflow_mode into v_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if coalesce(v_mode, 'kds') <> 'printer_only' then
    return jsonb_build_object('ok', false, 'error', 'branch_not_printer_only', 'entity', 'kitchen_print_dispatches');
  end if;

  -- The deploy-ahead compatibility guard: only a device with a FRESH,
  -- activation-capable readiness report may claim. No deployed client reports
  -- the capability, so production claims are impossible today.
  if not exists (
    select 1 from public.kitchen_printer_readiness_reports rr
    where rr.organization_id = v_org
      and rr.device_id = p_device_id
      and rr.branch_id = v_branch
      and rr.expires_at > now()
      and rr.capability = 'kitchen_printer_only_v1'
      and rr.printer_purpose = 'kitchen_ticket'
      and rr.paper_width = '80mm'
      and rr.secure_spool_available
  ) then
    return jsonb_build_object('ok', false, 'error', 'readiness_required', 'entity', 'kitchen_print_dispatches');
  end if;

  v_limit := p_limit;

  -- ATOMIC CLAIM: the inner FOR UPDATE serializes concurrent pullers; the
  -- outer WHERE re-proves claimability AFTER the lock wait, so two devices
  -- can never claim the same row (the loser's re-check sees the fresh claim).
  -- Stale claims (expired) and this device's own claims are reclaimable.
  with candidates as (
    select d.id
      from public.kitchen_print_dispatches d
      where d.organization_id = v_org
        and d.branch_id = v_branch
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null
        and d.last_client_status is distinct from 'possibly_printed'
        and d.created_at > now() - interval '30 days'
        and (d.claimed_at is null
             or d.claim_expires_at < now()
             or d.claimed_by_device_id = p_device_id)
        and (p_cursor_created_at is null
             or (d.created_at, d.id) > (p_cursor_created_at, p_cursor_id))
      order by d.created_at,
               case d.dispatch_type when 'initial_order' then 0
                                    when 'service_round' then 1 else 2 end,
               d.id
      limit v_limit
      for update of d
  )
  update public.kitchen_print_dispatches d
    set claimed_at = now(),
        claimed_by_device_id = p_device_id,
        claim_expires_at = now() + interval '10 minutes',
        updated_at = now()
    from candidates c
    where d.id = c.id
      and d.completed_at is null
      and d.superseded_by_dispatch_id is null
      and (d.claimed_at is null
           or d.claim_expires_at < now()
           or d.claimed_by_device_id = p_device_id);

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id,
           'dispatch_type', d.dispatch_type,
           'order_id', d.order_id,
           'service_round_id', d.service_round_id,
           'payload_version', d.payload_version,
           'payload', d.money_free_payload,
           'created_at', d.created_at,
           'claim_expires_at', d.claim_expires_at)
         order by d.created_at,
                  case d.dispatch_type when 'initial_order' then 0
                                       when 'service_round' then 1 else 2 end,
                  d.id), '[]'::jsonb),
         count(*)::int,
         max(d.created_at), (array_agg(d.id order by d.created_at desc, d.id desc))[1]
    into v_rows, v_count, v_last_at, v_last_id
    from public.kitchen_print_dispatches d
    where d.organization_id = v_org
      and d.branch_id = v_branch
      and d.claimed_by_device_id = p_device_id
      and d.claim_expires_at > now()
      and d.completed_at is null
      and d.superseded_by_dispatch_id is null
      and (p_cursor_created_at is null
           or (d.created_at, d.id) > (p_cursor_created_at, p_cursor_id));

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_print_dispatches',
    'dispatches', v_rows,
    'has_more', (v_count >= v_limit),
    'next_cursor', case when v_count > 0
                        then jsonb_build_object('created_at', v_last_at, 'id', v_last_id)
                        else null end,
    'server_ts', now());
end;
$$;

comment on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid) is
  'KITCHEN-MODE-001C1: the POS''s ATOMIC claim-and-pull. Device-token authenticated (full 001A-corrected liveness; KDS explicitly denied); branch must currently be printer_only; a FRESH activation-capable readiness report is required (the deploy-ahead guard — no deployed client reports it, so production claims are impossible). Claims are per-device with a 10-minute expiry; stale claims are reclaimable; two devices can never win the same row (inner FOR UPDATE + outer re-check). Deterministic order: created_at, then initial_order < service_round < void, then id — per-order initial-before-round is guaranteed by creation order, and a VOID never overtakes its own order''s unattempted original (the original is superseded instead). possibly_printed rows are NEVER re-served (a re-print without operator action could duplicate paper). Payload only to the claiming POS; completed/superseded/30-day-old rows excluded. NOTE (D-013): no audit row on this device-only path — claim observability lives on the row (claimed_at/claimed_by).';

create or replace function public.pull_kitchen_print_dispatches(
  p_device_id uuid, p_session_token text, p_limit integer default 20,
  p_cursor_created_at timestamptz default null, p_cursor_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.pull_kitchen_print_dispatches(p_device_id, p_session_token, p_limit, p_cursor_created_at, p_cursor_id); $$;

revoke all on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid) from public;
grant execute on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid) to authenticated;
revoke all on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid) from public;
revoke all on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid) from anon;
grant execute on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 12. Acknowledgement (+wrapper).
-- ----------------------------------------------------------------------------
create or replace function app.acknowledge_kitchen_print_dispatch(
  p_device_id      uuid,
  p_session_token  text,
  p_dispatch_id    uuid,
  p_client_status  text,
  p_error_code     text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash    text;
  v_org     uuid;
  v_branch  uuid;
  v_dtype   text;
  v_row     public.kitchen_print_dispatches%rowtype;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatch');
  end if;
  if p_client_status is null or p_client_status not in
     ('imported', 'transport_accepted', 'possibly_printed', 'failed_retryable', 'blocked_configuration') then
    -- NEVER a physical claim: 'printed'/'paper_printed' are not a vocabulary.
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'entity', 'kitchen_print_dispatch');
  end if;
  if p_error_code is not null and p_error_code !~ '^[a-z0-9_.\-]{1,64}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_error_code', 'entity', 'kitchen_print_dispatch');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  select ds.organization_id, ds.branch_id, d.device_type
    into v_org, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null or v_dtype <> 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatch');
  end if;

  select * into v_row from public.kitchen_print_dispatches d
    where d.id = p_dispatch_id and d.organization_id = v_org and d.branch_id = v_branch
    for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'kitchen_print_dispatch');
  end if;

  -- Idempotent replay: already completed BY THIS DEVICE.
  if v_row.completed_at is not null then
    if v_row.claimed_by_device_id = p_device_id and p_client_status = 'transport_accepted' then
      return jsonb_build_object('ok', true, 'entity', 'kitchen_print_dispatch',
        'dispatch_id', v_row.id, 'completed', true, 'idempotency_replay', true, 'server_ts', now());
    end if;
    return jsonb_build_object('ok', false, 'error', 'conflict', 'entity', 'kitchen_print_dispatch');
  end if;

  -- Claim ownership: the current claim holder while valid, PLUS the designed
  -- stale-recovery path — the device that HELD the claim may still finish its
  -- slow print after expiry, as long as nobody else claimed meanwhile.
  if v_row.claimed_by_device_id is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'not_claim_owner', 'entity', 'kitchen_print_dispatch');
  end if;

  if p_client_status = 'transport_accepted' then
    update public.kitchen_print_dispatches
      set completed_at = now(), last_client_status = p_client_status,
          last_error_code = null, updated_at = now()
      where id = v_row.id;
  elsif p_client_status = 'possibly_printed' then
    -- Permanent hold: NEVER auto-re-served (a blind retry could duplicate
    -- paper). Stays visible/unresolved until an operator acts (001C2 UX).
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          last_error_code = p_error_code,
          claim_expires_at = null, updated_at = now()
      where id = v_row.id;
  elsif p_client_status = 'imported' then
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          claim_expires_at = now() + interval '10 minutes', updated_at = now()
      where id = v_row.id;
  else
    -- failed_retryable / blocked_configuration: recorded; the claim keeps its
    -- natural expiry so the SAME or another POS can retry after it lapses.
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          last_error_code = p_error_code, updated_at = now()
      where id = v_row.id;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_print_dispatch',
    'dispatch_id', v_row.id,
    'completed', (p_client_status = 'transport_accepted'),
    'idempotency_replay', false,
    'server_ts', now());
end;
$$;

comment on function app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) is
  'KITCHEN-MODE-001C1: POS-only dispatch acknowledgement (device-token, full liveness, KDS denied). Closed NON-PHYSICAL status vocabulary — imported (extends the claim), transport_accepted (completes; idempotent replay for the same device), possibly_printed (PERMANENT hold: never auto-re-served, visible until an operator acts), failed_retryable / blocked_configuration (recorded; claim expiry keeps running so retry is possible). ''printed'' deliberately does not exist. Only the claim holder may acknowledge, with a stale-recovery path for the device that HELD the claim finishing a slow print. Error codes are allowlisted-shape, length-limited; no payload/endpoint/money is ever logged. Acknowledgement NEVER touches order state. NOTE (D-013): no audit row on this device-only path — observability lives on the row.';

create or replace function public.acknowledge_kitchen_print_dispatch(
  p_device_id uuid, p_session_token text, p_dispatch_id uuid,
  p_client_status text, p_error_code text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.acknowledge_kitchen_print_dispatch(p_device_id, p_session_token, p_dispatch_id, p_client_status, p_error_code); $$;

revoke all on function app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) from public;
grant execute on function app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) to authenticated;
revoke all on function public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) from public;
revoke all on function public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) from anon;
grant execute on function public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 13. Read-only transition-readiness inspection (+wrapper). Member-authorized
--     (any active membership covering the branch may READ; the future
--     MUTATION stays owner-only in 001C3). Typed blocker codes + safe counts
--     only — no payloads, no customer data, no money, no endpoints. NEVER
--     mutates anything.
-- ----------------------------------------------------------------------------
create or replace function app.get_kitchen_workflow_transition_readiness(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor          uuid := app.current_app_user_id();
  v_rank           integer;
  v_mode           text;
  v_rev            integer;
  v_active_orders  integer;
  v_ready_orders   integer;
  v_active_rounds  integer;
  v_pending_ops    integer;
  v_unresolved     integer;
  v_pending_voids  integer;
  v_report         public.kitchen_printer_readiness_reports%rowtype;
  v_to_po          jsonb := '[]'::jsonb;
  v_to_kds         jsonb := '[]'::jsonb;
begin
  if v_actor is null then
    raise exception 'get_kitchen_workflow_transition_readiness: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_mode, v_rev
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if v_mode is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  -- The server RECOMPUTES every server-side blocker itself; the only client
  -- input is the fresh device-session-proven readiness report row.
  select count(*)::int into v_active_orders
    from public.orders o
    where o.organization_id = p_organization_id and o.branch_id = p_branch_id
      and o.deleted_at is null
      and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served');
  select count(*)::int into v_ready_orders
    from public.orders o
    where o.organization_id = p_organization_id and o.branch_id = p_branch_id
      and o.deleted_at is null and o.status = 'ready';
  select count(*)::int into v_active_rounds
    from public.order_service_rounds r
    where r.organization_id = p_organization_id and r.branch_id = p_branch_id
      and r.deleted_at is null
      and r.status in ('submitted', 'accepted', 'preparing', 'ready');
  select count(*)::int into v_pending_ops
    from public.sync_operations so
    where so.organization_id = p_organization_id and so.branch_id = p_branch_id
      and so.status in ('created', 'pending', 'in_flight');
  select count(*)::int into v_unresolved
    from public.kitchen_print_dispatches d
    where d.organization_id = p_organization_id and d.branch_id = p_branch_id
      and d.completed_at is null and d.superseded_by_dispatch_id is null;
  select count(*)::int into v_pending_voids
    from public.kitchen_print_dispatches d
    where d.organization_id = p_organization_id and d.branch_id = p_branch_id
      and d.dispatch_type = 'void'
      and d.completed_at is null and d.superseded_by_dispatch_id is null;
  select rr.* into v_report
    from public.kitchen_printer_readiness_reports rr
    where rr.organization_id = p_organization_id and rr.branch_id = p_branch_id
      and rr.expires_at > now()
      and rr.capability = 'kitchen_printer_only_v1'
    order by rr.reported_at desc
    limit 1;

  -- kds -> printer_only blockers.
  if v_active_orders > 0 then v_to_po := v_to_po || '"active_orders"'::jsonb; end if;
  if v_active_rounds > 0 then v_to_po := v_to_po || '"active_service_rounds"'::jsonb; end if;
  if v_ready_orders > 0 then v_to_po := v_to_po || '"unresolved_ready_state"'::jsonb; end if;
  if v_pending_ops > 0 then v_to_po := v_to_po || '"unresolved_sync_operations"'::jsonb; end if;
  if v_report.id is null then
    v_to_po := v_to_po || '"no_fresh_pos_readiness"'::jsonb;
  else
    if v_report.paper_width <> '80mm' then v_to_po := v_to_po || '"paper_width_80mm_required"'::jsonb; end if;
    if not v_report.secure_spool_available then v_to_po := v_to_po || '"secure_spool_unavailable"'::jsonb; end if;
    if v_report.mode_revision <> v_rev then v_to_po := v_to_po || '"stale_mode_revision"'::jsonb; end if;
  end if;

  -- printer_only -> kds blockers.
  if v_unresolved > 0 then v_to_kds := v_to_kds || '"unresolved_dispatches"'::jsonb; end if;
  if v_pending_voids > 0 then v_to_kds := v_to_kds || '"pending_void_dispatches"'::jsonb; end if;
  if v_active_orders > 0 then v_to_kds := v_to_kds || '"active_orders"'::jsonb; end if;
  if v_active_rounds > 0 then v_to_kds := v_to_kds || '"active_service_rounds"'::jsonb; end if;
  if v_report.id is null then
    v_to_kds := v_to_kds || '"no_fresh_pos_status_report"'::jsonb;
  elsif v_report.unresolved_local_jobs > 0 then
    v_to_kds := v_to_kds || '"unresolved_local_jobs"'::jsonb;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_workflow_transition_readiness',
    'mode', v_mode,
    'mode_revision', v_rev,
    'to_printer_only', jsonb_build_object(
      'ready', (jsonb_array_length(v_to_po) = 0), 'blockers', v_to_po),
    'to_kds', jsonb_build_object(
      'ready', (jsonb_array_length(v_to_kds) = 0), 'blockers', v_to_kds),
    'counts', jsonb_build_object(
      'active_orders', v_active_orders,
      'active_service_rounds', v_active_rounds,
      'ready_orders', v_ready_orders,
      'pending_sync_operations', v_pending_ops,
      'unresolved_dispatches', v_unresolved,
      'pending_void_dispatches', v_pending_voids,
      'unresolved_local_jobs', coalesce(v_report.unresolved_local_jobs, 0)),
    'readiness_report', case when v_report.id is null then null else jsonb_build_object(
      'reported_at', v_report.reported_at,
      'expires_at', v_report.expires_at,
      'paper_width', v_report.paper_width,
      'transport_kind', v_report.transport_kind,
      'secure_spool_available', v_report.secure_spool_available,
      'app_build', v_report.app_build) end,
    'server_ts', now());
end;
$$;

comment on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) is
  'KITCHEN-MODE-001C1: READ-ONLY inspection of every kitchen-workflow transition blocker (typed codes + safe counts only — no payloads, customer data, money or endpoints). The server recomputes every server-side blocker; the only client-derived input is the FRESH device-session-proven readiness report (unresolved_local_jobs). Any active member covering the branch may READ (matches branch-settings read visibility); the future MUTATION (001C3 setter) is owner-only. Never changes mode; never mutates anything.';

create or replace function public.get_kitchen_workflow_transition_readiness(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_kitchen_workflow_transition_readiness(p_organization_id, p_restaurant_id, p_branch_id); $$;

revoke all on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from public;
grant execute on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from public;
revoke all on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from anon;
grant execute on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) to authenticated;


-- ----------------------------------------------------------------------------
-- 14. Audit trio — faithful re-creations (audit_category from 20260711120000
--     via the 20260724090000 printer delta; has_detail/safe_detail from
--     20260724090000) with the KITCHEN-MODE-001C1 kitchen.% additions.
-- ----------------------------------------------------------------------------

create or replace function app.audit_category(p_action text)
  returns text
  language sql
  immutable
  set search_path = ''
as $$
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
    -- KITCHEN-MODE-001B: printer configuration IS settings work.
    when p_action like 'printer.%'                                    then 'settings'
    -- KITCHEN-MODE-001C1: kitchen dispatch events are ORDER work.
    when p_action like 'kitchen.%'                                    then 'orders'
    when p_action like 'menu.%'                                       then 'menu'
    when p_action like 'table.%'                                      then 'tables'
    when p_action like 'organization.%'                               then 'organization'
    when p_action like 'sync.%'                                       then 'sync'
    else 'other'
  end;
$$;



comment on function app.audit_category(text) is
  'AUDIT-COVERAGE-002 + KITCHEN-MODE-001B + KITCHEN-MODE-001C1: the single classification source of truth. printer.% -> settings (001B); kitchen.% (dispatch events) -> orders (001C1). Faithful re-creation otherwise.';

revoke all on function app.audit_category(text) from public;


create or replace function app.audit_action_has_detail(p_action text)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  select coalesce(p_action, '') like 'order.void%'
      or p_action like 'order.discount%'
      or p_action like 'order.status%'
      or p_action =    'order.submitted'
      -- RESTAURANT-OPERATIONS-V1-001: table moves (order.table_moved +
      -- order.table_move_denied) carry before/after labels + denied reasons.
      or p_action like 'order.table_mov%'
      or p_action like 'staff.capabilities%'
      -- FULL-COMP-PERMISSION-001: staff.created was NOT projected, so the capabilities
      -- a cashier is PROVISIONED with were written to the append-only trail and then
      -- never shown. Granting "make orders free" invisibly is exactly what this ticket
      -- must not do, so the CREATE path is projected too.
      or p_action =    'staff.created'
      or p_action like 'membership.%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%'
      or p_action like 'settings.%'
      -- RESTAURANT-OPERATIONS-V1-001: branch availability changes/denials carry
      -- before/after availability + the item name (menu.* was previously
      -- metadata-only; ONLY the availability family gains detail).
      or p_action like 'menu.%.availability%'
      -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status changes/denials
      -- (before/after floor status) and link/unlink (group label) carry detail.
      or p_action like 'table.status%'
      or p_action like 'table.tables_%'
      or p_action like 'table.link%'
      or p_action like 'table.unlink%'
      -- PSC-001C: order additions (round_number/added_item_count) and round
      -- status changes (round_number/from_status/to_status) carry safe detail.
      or p_action like 'order.items_add%'
      or p_action like 'order.round_status%'
      -- KITCHEN-MODE-001B: printer configuration actions carry a safe scalar
      -- projection (display_name / role / paper_width / is_enabled /
      -- connection_type). connection_config stays a nested object, so the
      -- scalar-only allowlist can never surface host/port/addresses.
      or p_action like 'printer.%'
      -- KITCHEN-MODE-001C1: kitchen dispatch events carry safe scalars only
      -- (order_code / dispatch_type / membership) — never the payload.
      or p_action like 'kitchen.%'
      or p_action =    'pin_session.failed';
$$;


comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 .. KITCHEN-MODE-001B + KITCHEN-MODE-001C1: adds the kitchen.% dispatch family (safe scalars only — order_code / dispatch_type; the money_free_payload is never projected). Faithful re-creation of the 20260724090000 body. Gates app.audit_safe_detail.';


create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    -- ORDER-AUTO-COMPLETION-001: how, and why, an order was completed. Both are
    -- STATES ('automatic'/'manual', 'order_served'/'payment_recorded'), not money
    -- and not identifiers — T-003 still holds.
    'completion_mode','completion_trigger',
    -- MONEY-SETTLEMENT-CONSISTENCY-001: WHY a mutation was denied. order.discount_denied
    -- and order.void_denied have always carried this, but it was never allowlisted — so
    -- the Activity Log showed THAT a discount was refused and never WHY. It is a closed
    -- enum of safe STATE tokens (order_has_completed_payment | full_comp_requires_manager),
    -- never money and never an identifier (T-003 holds).
    'denied_reason',
    -- FULL-COMP-PERMISSION-001: WHAT the mutation would have left the order as. A
    -- closed enum of STATE tokens ('not_chargeable') -- never money, never an
    -- identifier (T-003 holds).
    'resulting_charge_state',
    -- RESTAURANT-OPERATIONS-V1-001: branch availability (closed enums
    -- available|unavailable / sold_out|paused) + the menu item's display name,
    -- and table-move floor labels (human table names). Names/labels are tenant
    -- display text already shown on receipts/tickets — never money, never ids.
    'availability','availability_reason','item_name',
    'table_label','from_table_label','to_table_label',
    -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status transition
    -- (closed enum available|reserved|occupied|out_of_service) + the combined
    -- group label (floor names). Never money, never identifiers (T-003 holds).
    'from_status','to_status','group_label',
    -- PSC-001D: void provenance + kitchen acknowledgement. voided_from_status
    -- is the closed order-status enum; device_type is the closed pos|kds enum;
    -- kitchen_ack_required is a boolean. Never money, never identifiers
    -- (T-003 holds).
    'voided_from_status','device_type','kitchen_ack_required',
    -- PSC-001C: service rounds. round_number and added_item_count are small
    -- integers (a position in the order and a line count) — never money,
    -- never identifiers (T-003 holds).
    'round_number','added_item_count',
    -- KITCHEN-MODE-001B: printer configuration scalars. display_name is tenant
    -- display text (the item_name/table_label class); the rest are closed
    -- enums/booleans. connection_config (host/port/addresses) is a NESTED
    -- OBJECT and is therefore structurally dropped by the scalar-only rule —
    -- endpoints never reach the Activity Log timeline.
    'display_name','paper_width','is_enabled','connection_type',
    -- KITCHEN-MODE-001C1: kitchen dispatch safe scalars (closed enum + the
    -- existing safe order_code class). The money_free_payload itself is
    -- NEVER projected into audit detail.
    'dispatch_type'
  ] loop
    -- PSC-001C correction (Finding 6): the four service-round actions are
    -- MONEY-FREE by approved contract — any *_minor key (hostile, manual, or
    -- accidental) is dropped for EXACTLY these actions, action-specifically:
    -- the approved money-carrying actions (payments / discounts / shifts /
    -- order.submitted / completion) keep their allowlisted money keys.
    if (p_action like 'order.items_add%' or p_action like 'order.round_status%'
        -- KITCHEN-MODE-001B: printer configuration is MONEY-FREE by contract —
        -- the same hostile-key hardening applies to the whole printer family.
        or p_action like 'printer.%'
        -- KITCHEN-MODE-001C1: kitchen dispatch events are MONEY-FREE too.
        or p_action like 'kitchen.%')
       and v_key like '%\_minor' escape '\' then
      continue;
    end if;
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its four
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;


comment on function app.audit_safe_detail(text, jsonb) is
  'ALLOWLIST projection of one audit payload to canonical safe fields (see 20260724090000) + KITCHEN-MODE-001C1 dispatch_type. kitchen.% joins the MONEY-FREE hostile-key hardening (every *_minor key dropped for the family). Faithful re-creation otherwise; every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   re-create app.audit_safe_detail / app.audit_action_has_detail /
--     app.audit_category from 20260724090000 (trio),
--     app.void_order from 20260722090000,
--     app.add_order_items from 20260722090000,
--     app.submit_order from 20260723090000;
--   drop function if exists public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid);
--   drop function if exists app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid);
--   drop function if exists public.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text);
--   drop function if exists app.acknowledge_kitchen_print_dispatch(uuid, text, uuid, text, text);
--   drop function if exists public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid);
--   drop function if exists app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid);
--   drop function if exists public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer);
--   drop function if exists app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer);
--   drop function if exists app.create_kitchen_dispatch(uuid, uuid, uuid, uuid, uuid, text, jsonb, uuid, uuid, uuid);
--   drop function if exists app.kitchen_dispatch_payload_void(uuid, uuid, text);
--   drop function if exists app.kitchen_dispatch_payload_round(uuid, uuid, uuid);
--   drop function if exists app.kitchen_dispatch_payload_initial(uuid, uuid);
--   drop trigger if exists kitchen_print_dispatches_guard_trg on public.kitchen_print_dispatches;
--   drop function if exists app.kitchen_print_dispatches_guard();
--   drop function if exists app.kitchen_payload_offending_key(jsonb);
--   drop table if exists public.kitchen_print_dispatches;
--   drop table if exists public.kitchen_printer_readiness_reports;
--   alter table public.branches drop column if exists kitchen_workflow_mode_revision;
-- ============================================================================
