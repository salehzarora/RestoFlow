-- ============================================================================
-- PSC-001C — Authoritative service rounds, order additions, POS order detail,
--            and the durable ready-feed backend.
--
-- One forward-only migration. DOMAIN_MODEL §orders; DECISIONS D-001/2/3 (tenant
-- columns), D-007 (integer minor units), D-008 (order-time snapshots), D-010/
-- D-022 (outbox + idempotency), D-011/D-012 (RPC + four layers), D-013 (audit),
-- D-017 (naming), D-020 (tombstones), D-025 (payment gate); RISK R-003.
--
-- WHAT THIS DELIVERS
--   * `order_service_rounds` — the authoritative model for items ADDED to an
--     existing unpaid dine-in order. The PARENT stays ONE order and ONE bill
--     (payments/discounts/receipts/totals remain parent-order concerns; a round
--     row carries NO money). The original submitted order remains the FIRST
--     kitchen work unit on orders.status; the first addition is ROUND 2.
--   * `order_items.service_round_id` — added items belong to exactly one round;
--     original items keep NULL. The composite FK proves the round belongs to
--     the SAME parent order (never a sibling order's round).
--   * `orders.ready_at` + `order_service_rounds.ready_at` — WRITE-ONCE durable
--     "this work unit became ready" timestamps: the ready-feed source PSC-001A
--     will consume. Never erased when the unit later serves/voids.
--   * app.add_order_items  (sync op 14: order.items_add,   POS-device only)
--   * app.update_round_status (sync op 15: order.round_status, KDS-first matrix)
--   * app.pos_order_detail — the authoritative POS order read (items+modifiers+
--     rounds+payment) for open/add/refresh/payment/receipt on ANY branch POS.
--   * app.pos_ready_feed — the durable derived ready feed (keyset cursor).
--   * Faithful re-creations wiring rounds into completion, void, sync push/pull
--     and the audit classifiers. Owners identified per function below.
--
-- COMPLETION RULE (PSC-001C): an order completes ONLY when the parent initial
-- work is `served` AND the order is fully settled (app.order_is_fully_settled,
-- unchanged) AND NO additional service round has status <> 'served' AND the
-- parent is not voided/cancelled. A voided round is NOT completion-eligible —
-- it only ever exists on a voided parent, which can never complete.
--
-- NOT TOUCHED: app.submit_order, app.record_payment, app.apply_discount,
-- app.update_order_status, app.owner_complete_order, app.order_is_fully_settled,
-- public.sync_push, public.sync_pull, app.audit_category, every shipped
-- migration. GRANT-HYGIENE-001 (anon EXECUTE on public.sync_push) is a known
-- separate follow-up and is deliberately not changed here.
--
-- Forward-only, additive, DB-first backward compatible: old POS/KDS clients
-- never send the two new operations and never request the new entity; historical
-- orders carry zero rounds and complete exactly as before. NOT applied to
-- hosted by this migration.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. orders.ready_at — the durable WRITE-ONCE "initial work unit became ready"
--    stamp (owner of orders DDL deltas before this: 20260721090000). Historical
--    rows are NOT backfilled: a NULL ready_at on a served/completed row is the
--    honest "predates the feed" state and never surfaces in pos_ready_feed.
--    The CHECK is deliberately one-directional (backward compatible): a
--    non-NULL stamp is only legal on a state that has REACHED or PASSED ready
--    (ready/served/completed) or left the ladder afterwards (voided/cancelled);
--    it never requires historical ready+ rows to carry one.
-- ----------------------------------------------------------------------------
alter table public.orders
  add column ready_at timestamptz;

alter table public.orders add constraint orders_ready_at_check
  check (ready_at is null
         or status in ('ready', 'served', 'completed', 'voided', 'cancelled'));

comment on column public.orders.ready_at is
  'PSC-001C: WRITE-ONCE server stamp of the moment the INITIAL kitchen work unit reached `ready` (set inside app.apply_order_status_transition; never cleared when the order later serves/completes/voids). NULL on every historical row that predates the feed — such rows never appear in app.pos_ready_feed. The durable ready-feed source (with order_service_rounds.ready_at) that PSC-001A consumes.';

-- ----------------------------------------------------------------------------
-- 2. order_service_rounds — the authoritative additional-kitchen-work model.
--    Template: the `tables` DDL pattern (20260703120000): FORCE RLS, scoped
--    SELECT, explicit deny-writes, SELECT-only grant, composite same-scope FKs,
--    app.set_updated_at trigger, tombstone column.
--    NO money columns (locked): payments/discounts/totals live on the parent.
-- ----------------------------------------------------------------------------
create table public.order_service_rounds (
  id                             uuid not null default gen_random_uuid(),
  organization_id                uuid not null references public.organizations (id) on delete restrict,
  restaurant_id                  uuid not null,
  branch_id                      uuid not null,
  order_id                       uuid not null,
  -- Round 1 is the ORIGINAL submitted order (it has no row here); the first
  -- addition is ROUND 2. Numbers are allocated as max(round_number)+1 across
  -- ALL rows of the parent (voided/deleted included) so a number is NEVER
  -- reused, and the per-order unique below is the D-012 layer-4 backstop.
  round_number                   integer not null check (round_number >= 2),
  status                         text not null default 'submitted'
    check (status in ('submitted', 'accepted', 'preparing', 'ready', 'served', 'voided')),
  -- WRITE-ONCE durable ready stamp (the round-side ready-feed source). The
  -- null-safe CHECK: pre-ready states carry NO stamp; ready/served REQUIRE it;
  -- a voided round MAY carry one (voided after ready) or not (voided before).
  ready_at                       timestamptz,
  void_reason                    text,
  device_id                      uuid not null,
  opened_by_employee_profile_id  uuid not null,
  local_operation_id             text,
  revision                       integer not null default 1,
  client_created_at              timestamptz,
  created_at                     timestamptz not null default now(),
  updated_at                     timestamptz not null default now(),
  deleted_at                     timestamptz,
  primary key (id),
  unique (organization_id, id),
  -- The composite-FK target proving SAME-PARENT round membership for
  -- order_items.service_round_id (see §3).
  unique (organization_id, order_id, id),
  unique (organization_id, order_id, round_number),
  constraint order_service_rounds_ready_at_check
    check (case
             when status in ('submitted', 'accepted', 'preparing') then ready_at is null
             when status in ('ready', 'served')                    then ready_at is not null
             else true  -- voided: either (voided before or after ready)
           end),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, order_id)
    references public.orders (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, opened_by_employee_profile_id)
    references public.employee_profiles (organization_id, id) on delete restrict
);

comment on table public.order_service_rounds is
  'PSC-001C: an ADDITIONAL kitchen work unit ("Addition" / "Round N", N >= 2) on an existing unpaid dine-in order. The parent stays ONE order and ONE payable bill; a round carries NO money (D-007 scope: money lives on orders/order_items). Lifecycle submitted -> accepted -> preparing -> ready -> served (single-step, app.update_round_status); `voided` only via the whole-order void cascade — there is NO independent round-void feature. ready_at is the WRITE-ONCE durable ready-feed stamp. Written ONLY by SECURITY DEFINER RPCs (app.add_order_items / app.update_round_status / app.void_order); clients read it via sync_pull (KDS) — never write it.';

-- Idempotency backstop for app.add_order_items direct-replay (mirrors the
-- orders (device_id, local_operation_id) unique of RF-052).
create unique index order_service_rounds_device_op_uidx
  on public.order_service_rounds (organization_id, device_id, local_operation_id)
  where local_operation_id is not null;

create trigger order_service_rounds_set_updated_at
  before update on public.order_service_rounds
  for each row execute function app.set_updated_at();

alter table public.order_service_rounds enable row level security;
alter table public.order_service_rounds force  row level security;

create policy order_service_rounds_sel on public.order_service_rounds
  for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_scope(organization_id, restaurant_id, branch_id));
create policy order_service_rounds_ins_deny on public.order_service_rounds
  for insert to authenticated with check (false);
create policy order_service_rounds_upd_deny on public.order_service_rounds
  for update to authenticated using (false) with check (false);
create policy order_service_rounds_del_deny on public.order_service_rounds
  for delete to authenticated using (false);

grant select on public.order_service_rounds to authenticated;

-- ----------------------------------------------------------------------------
-- 3. order_items.service_round_id — round membership (owner of order_items DDL
--    deltas before this: 20260708090000). ORIGINAL items keep NULL; added items
--    carry exactly one round. The SEMANTIC composite FK includes order_id, so a
--    round of a DIFFERENT order (even same-org) is structurally impossible.
-- ----------------------------------------------------------------------------
alter table public.order_items
  add column service_round_id uuid;

alter table public.order_items add constraint order_items_service_round_fkey
  foreign key (organization_id, order_id, service_round_id)
  references public.order_service_rounds (organization_id, order_id, id)
  on delete restrict;

comment on column public.order_items.service_round_id is
  'PSC-001C: NULL for the ORIGINAL submitted items (kitchen work unit 1); the owning service round for items ADDED later via app.add_order_items. The (organization_id, order_id, service_round_id) composite FK proves the round belongs to this SAME parent order. KDS maps NULL-round items to the original ticket and per-round items to separate "Addition / Round N" tickets.';

-- ----------------------------------------------------------------------------
-- 4. app.order_rounds_all_served — the ONE canonical "no additional service
--    round is still owed to the kitchen" predicate, used by BOTH completion
--    paths (app.try_auto_complete_order and the manual served->completed gate
--    in app.apply_order_status_transition). Historical orders with ZERO rounds
--    pass trivially. A VOIDED round is NOT completion-eligible (locked: only
--    `served` counts) — it blocks this predicate, and it only ever exists on a
--    voided parent, which can never complete anyway.
-- ----------------------------------------------------------------------------
create or replace function app.order_rounds_all_served(
  p_organization_id uuid,
  p_order_id        uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select not exists (
    select 1
    from public.order_service_rounds r
    where r.organization_id = p_organization_id
      and r.order_id        = p_order_id
      and r.deleted_at is null
      and r.status <> 'served'
  );
$$;

comment on function app.order_rounds_all_served(uuid, uuid) is
  'PSC-001C: the ONE canonical completion predicate for additional kitchen work — TRUE iff NO live service round of the order has a status other than `served`. Zero rounds (every historical order) passes trivially. A voided round is NOT completion-eligible (locked decision: `served` only — never "served OR voided"); it blocks this predicate and only ever exists on a voided parent, which is terminal anyway. Consulted by app.try_auto_complete_order and by the manual served->completed gate in app.apply_order_status_transition. INTERNAL: granted to no client role.';

revoke all on function app.order_rounds_all_served(uuid, uuid) from public;
revoke all on function app.order_rounds_all_served(uuid, uuid) from anon;
revoke all on function app.order_rounds_all_served(uuid, uuid) from authenticated;

-- ----------------------------------------------------------------------------
-- 5. app.add_order_items — sync op 14 `order.items_add`: add items to an
--    existing ELIGIBLE unpaid dine-in order as ONE new authoritative service
--    round. POS-DEVICE-ONLY; cashier/manager/restaurant_owner/org_owner (no new
--    capability — adding items is ordinary cashier work, exactly like submit).
--
--    PRICING (D-008, submit_order parity — owner 20260719100000): order-time
--    CLIENT SNAPSHOTS per line, SERVER arithmetic recompute, SERVER sellability
--    + availability validation under ascending-id FOR UPDATE menu locks. The
--    per-line validation/insert loop below deliberately REPLICATES the
--    app.submit_order loop (there is no shared helper; extracting one would
--    force a faithful re-creation of submit_order — a larger regression surface
--    than this bounded, comment-bound duplication). NO order-level client total
--    is accepted at all: subtotal/grand deltas are computed HERE. A nonzero
--    line_discount_minor on an ADDED line is REJECTED (typed invalid_item_payload)
--    — the safest contract: additions never carry hidden price cuts, and the
--    parent's absolute discount_total_minor stays EXACTLY as it was (locked:
--    a prior discount never silently expands over added items).
--
--    ELIGIBILITY (all RETURN-refusals audited order.items_add_denied):
--    dine_in only; parent status submitted..served; NO live completed payment
--    (mirrors the apply_discount payment freeze — a frozen payment must keep
--    covering the bill, and record_payment allows at most ONE completed payment,
--    so a post-payment addition could never be settled). A zero-total/full-comp
--    order with NO completed payment stays eligible while still open (it simply
--    becomes chargeable again). Draft orders keep the existing cart path.
--
--    CONCURRENCY: the parent orders row FOR UPDATE is the FIRST lock (the same
--    first lock payment/void/status/discount take -> no new deadlock cycle);
--    menu_items locks follow in ascending id order (submit_order parity — and
--    submit_order never holds an orders row lock, so no cycle there either).
--    Round numbers allocate as max(round_number)+1 across ALL rows of the
--    parent under that lock: monotonic, never reused, no counter table.
--
--    ANTI-ORACLE (R-003, the PSC-001D F1 pattern): ONE scoped lookup; a
--    nonexistent order and a foreign-tenant order raise the SAME structural
--    42501 and are externally indistinguishable.
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

  -- (m) audit order.items_added (D-013): safe scalars only.
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_added', null,
          jsonb_build_object('order_id', p_order_id, 'revision', v_o_rev,
                             'subtotal_minor', v_o_sub),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'round_number', v_round_no, 'added_item_count', v_item_count,
                             'order_status', v_o_status, 'role', v_role,
                             'revision', v_new_rev, 'subtotal_minor', v_new_sub,
                             'grand_total_minor', v_new_grand,
                             'local_operation_id', p_local_operation_id,
                             'resolved_membership_id', v_membership));

  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id, 'round_id', v_round_id, 'round_number', v_round_no,
    'added_item_count', v_item_count, 'revision', v_new_rev,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) is
  'PSC-001C (D-007/D-008/D-011, RISK R-003): SECURITY DEFINER RPC adding items to an existing ELIGIBLE unpaid dine-in order as ONE new authoritative service round (round_number = max+1 across ALL rows, never reused; first addition = Round 2). Reached ONLY via app.sync_push (order.items_add); no public wrapper. POS-DEVICE-ONLY (a KDS device is refused regardless of role) + cashier/manager/restaurant_owner/org_owner — NO new capability. PRICING is submit_order parity (owner 20260719100000, loop replicated by design — see header): order-time client snapshots, server arithmetic recompute, server sellability+availability under ascending-id menu_items FOR UPDATE locks (same uniform item_unavailable refusal); NO order-level client total is accepted (deltas computed server-side); a nonzero addition-line discount is the typed invalid_item_payload refusal, and the parent''s ABSOLUTE discount_total_minor stays exactly as it was. ELIGIBILITY (typed audited RETURNs): dine_in only; parent status submitted..served; NO live completed payment (the apply_discount payment-freeze precedent — a frozen payment must keep covering the bill). Parent orders row FOR UPDATE is the FIRST lock (no new lock order); concurrent additions serialize on it. Idempotency: (org, device, local_operation_id) unique on the round — an exact replay returns the SAME round with no duplicate items; the key on a different order is a 40001 conflict. Anti-oracle: one scoped lookup; nonexistent and foreign orders raise the SAME structural 42501. Audits order.items_added / order.items_add_denied (safe scalars only). The parent status NEVER moves.';

revoke all on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) from public;
revoke all on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) from anon;
grant execute on function app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. app.update_round_status — sync op 15 `order.round_status`: the additional
--    kitchen work unit's own single-step lifecycle. The LOCKED device/role
--    matrix is enforced SERVER-SIDE (stricter than the legacy order.status arm,
--    which is deliberately NOT changed):
--      submitted->accepted / accepted->preparing / preparing->ready :
--        KDS device only; kitchen_staff|manager|restaurant_owner|org_owner
--      ready->served :
--        KDS (kitchen_staff|manager|restaurant_owner|org_owner)
--        or POS (cashier|manager|restaurant_owner|org_owner)
--
--    LOCK ORDER (never round-first): (1) resolve scope WITHOUT locking the
--    round — one scoped anti-oracle SELECT (nonexistent and foreign rounds
--    raise the SAME structural 42501); (2) lock the PARENT orders row FOR
--    UPDATE (the same first lock every mutating path takes — serializes with
--    add/payment/void/status); (3) re-read + lock the round FOR UPDATE.
--
--    ITEM SEMANTICS: identical to the initial-order transition — which mutates
--    NO order_items row (app.apply_order_status_transition writes orders only;
--    items keep their submit-time 'pending' status until a void cascade). This
--    function therefore touches ONLY the round row: never the original items,
--    never another round's items, never its own items.
--
--    ready_at stamps WRITE-ONCE on entering `ready` (the durable ready-feed
--    record); it is never cleared by served/voided. Entering `served` chains
--    the canonical completion decision under the HELD parent lock (trigger
--    'round_served'): completion fires exactly once, only when the parent is
--    served + fully settled + every round served.
-- ----------------------------------------------------------------------------
create or replace function app.update_round_status(
  p_pin_session_id     uuid,
  p_round_id           uuid,
  p_device_id          uuid,
  p_new_status         text,
  p_local_operation_id text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_emp         uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_device_type text;
  v_order_id    uuid;
  v_o_status    text;
  v_r_status    text;
  v_r_rev       integer;
  v_round_no    integer;
  v_ready_at    timestamptz;
  v_legal       boolean;
  v_new_rev     integer;
  v_auto        jsonb;
  v_dev_ok      boolean;
  v_role_ok     boolean;
  v_order_code  text;
begin
  -- (a) THE CANONICAL PIN PREAMBLE (structural raises, 42501).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'update_round_status: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'update_round_status: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'update_round_status: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'update_round_status: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'update_round_status: resolved membership is not active' using errcode = '42501';
  end if;
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;

  -- (b) ANTI-ORACLE SCOPE RESOLVE, WITHOUT locking the round (R-003): one
  --     scoped statement; a nonexistent round and a foreign-tenant round raise
  --     the SAME structural 42501 and are externally indistinguishable.
  select r.order_id into v_order_id
    from public.order_service_rounds r
    where r.id = p_round_id
      and r.organization_id = v_org
      and r.restaurant_id   = v_rest
      and r.branch_id       = v_branch
      and r.deleted_at is null;
  if not found then
    raise exception 'update_round_status: round_not_found_or_not_accessible' using errcode = '42501';
  end if;
  v_order_code := '#' || upper(right(replace(v_order_id::text, '-', ''), 6));

  -- (c) LOCK ORDER: parent orders row FIRST (the global first lock), THEN the
  --     round. Never round-first.
  select o.status into v_o_status
    from public.orders o
    where o.id = v_order_id and o.organization_id = v_org
    for update;
  select r.status, r.revision, r.round_number, r.ready_at
    into v_r_status, v_r_rev, v_round_no, v_ready_at
    from public.order_service_rounds r
    where r.id = p_round_id and r.organization_id = v_org
    for update;

  -- (d) PARENT GUARDS (typed audited RETURNs): a voided/cancelled parent has
  --     already swept its rounds — no later round transition may exist; a
  --     completed parent is terminal.
  if v_o_status in ('voided', 'cancelled') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.round_status_denied', null, null,
            jsonb_build_object('attempted_action', 'update_round_status', 'order_id', v_order_id,
                               'order_code', v_order_code, 'round_number', v_round_no,
                               'role', v_role, 'device_type', v_device_type,
                               'from_status', v_r_status, 'to_status', p_new_status,
                               'denied_reason', 'parent_order_voided'));
    return jsonb_build_object('ok', false, 'error', 'parent_order_voided', 'round_id', p_round_id,
                              'order_id', v_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;
  if v_o_status = 'completed' then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.round_status_denied', null, null,
            jsonb_build_object('attempted_action', 'update_round_status', 'order_id', v_order_id,
                               'order_code', v_order_code, 'round_number', v_round_no,
                               'role', v_role, 'device_type', v_device_type,
                               'from_status', v_r_status, 'to_status', p_new_status,
                               'denied_reason', 'parent_order_completed'));
    return jsonb_build_object('ok', false, 'error', 'parent_order_completed', 'round_id', p_round_id,
                              'order_id', v_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (e) TRANSITION LEGALITY: single-step forward only (the orders matrix minus
  --     the settlement step — a round has no completed state).
  v_legal := case
    when v_r_status = 'submitted' and p_new_status = 'accepted'  then true
    when v_r_status = 'accepted'  and p_new_status = 'preparing' then true
    when v_r_status = 'preparing' and p_new_status = 'ready'     then true
    when v_r_status = 'ready'     and p_new_status = 'served'    then true
    else false end;
  if not v_legal then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.round_status_denied', null, null,
            jsonb_build_object('attempted_action', 'update_round_status', 'order_id', v_order_id,
                               'order_code', v_order_code, 'round_number', v_round_no,
                               'role', v_role, 'device_type', v_device_type,
                               'from_status', v_r_status, 'to_status', p_new_status,
                               'denied_reason', 'invalid_transition'));
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'from', v_r_status, 'to', p_new_status, 'round_id', p_round_id,
                              'order_id', v_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (f) THE LOCKED DEVICE/ROLE MATRIX (server-authoritative; the UI is never
  --     trusted). Production steps are KDS-only; the hand-over step
  --     (ready->served) is KDS kitchen set or POS cashier set.
  if p_new_status in ('accepted', 'preparing', 'ready') then
    v_dev_ok  := (v_device_type = 'kds');
    v_role_ok := v_role in ('kitchen_staff', 'manager', 'restaurant_owner', 'org_owner');
  else  -- 'served'
    v_dev_ok  := (v_device_type in ('kds', 'pos'));
    v_role_ok := case v_device_type
                   when 'kds' then v_role in ('kitchen_staff', 'manager', 'restaurant_owner', 'org_owner')
                   when 'pos' then v_role in ('cashier', 'manager', 'restaurant_owner', 'org_owner')
                   else false
                 end;
  end if;
  if not v_dev_ok then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.round_status_denied', null, null,
            jsonb_build_object('attempted_action', 'update_round_status', 'order_id', v_order_id,
                               'order_code', v_order_code, 'round_number', v_round_no,
                               'role', v_role, 'device_type', coalesce(v_device_type, 'unknown'),
                               'from_status', v_r_status, 'to_status', p_new_status,
                               'denied_reason', 'invalid_device_type'));
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'round_id', p_round_id,
                              'order_id', v_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;
  if not v_role_ok then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.round_status_denied', null, null,
            jsonb_build_object('attempted_action', 'update_round_status', 'order_id', v_order_id,
                               'order_code', v_order_code, 'round_number', v_round_no,
                               'role', v_role, 'device_type', v_device_type,
                               'from_status', v_r_status, 'to_status', p_new_status,
                               'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'round_id', p_round_id,
                              'order_id', v_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g) MUTATE: the ROUND row only (see the item-semantics header note).
  --     ready_at is WRITE-ONCE — stamped on entering `ready`, never cleared,
  --     never re-stamped (the single-step matrix makes `ready` reachable once,
  --     and the case-guard makes the stamp idempotent under any replayed SQL).
  v_new_rev := v_r_rev + 1;
  update public.order_service_rounds
    set status   = p_new_status,
        revision = v_new_rev,
        ready_at = case when p_new_status = 'ready' and ready_at is null then now() else ready_at end
    where id = p_round_id;

  -- (h) audit order.round_status_updated (D-013): safe scalars only, money-free.
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.round_status_updated', null,
          jsonb_build_object('round_id', p_round_id, 'status', v_r_status, 'revision', v_r_rev),
          jsonb_build_object('order_id', v_order_id, 'order_code', v_order_code,
                             'round_number', v_round_no,
                             'from_status', v_r_status, 'to_status', p_new_status,
                             'role', v_role, 'device_type', v_device_type,
                             'revision', v_new_rev,
                             'local_operation_id', p_local_operation_id,
                             'resolved_membership_id', v_membership));

  -- (i) ENTERING SERVED: chain the canonical completion decision under the
  --     HELD parent lock (trigger 'round_served'). The helper is fail-soft,
  --     idempotent, single-shot; it completes ONLY when the parent is served +
  --     fully settled + every round served (app.order_rounds_all_served).
  if p_new_status = 'served' then
    v_auto := app.try_auto_complete_order(
      v_org, v_rest, v_branch, v_order_id,
      'round_served',
      null, v_emp, v_membership, v_role, p_device_id, p_local_operation_id);
    if (v_auto ->> 'completed')::boolean then
      return jsonb_build_object('ok', true, 'entity', 'order_service_round',
                                'round_id', p_round_id, 'order_id', v_order_id,
                                'order_code', v_order_code, 'round_number', v_round_no,
                                'from', v_r_status, 'to', p_new_status, 'revision', v_new_rev,
                                'auto_completed', true, 'order_status', 'completed',
                                'completion_trigger', 'round_served',
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'entity', 'order_service_round',
                            'round_id', p_round_id, 'order_id', v_order_id,
                            'order_code', v_order_code, 'round_number', v_round_no,
                            'from', v_r_status, 'to', p_new_status, 'revision', v_new_rev,
                            'auto_completed', false,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.update_round_status(uuid, uuid, uuid, text, text) is
  'PSC-001C (D-011/D-013/D-018, RISK R-003): SECURITY DEFINER single-step lifecycle of an ADDITIONAL service round (submitted->accepted->preparing->ready->served). Reached ONLY via app.sync_push (order.round_status); no public wrapper. LOCKED server-enforced device/role matrix: production steps (->accepted/->preparing/->ready) are KDS-DEVICE-ONLY for kitchen_staff/manager/restaurant_owner/org_owner; the hand-over (ready->served) allows KDS (kitchen set) or POS (cashier/manager/restaurant_owner/org_owner) — deliberately STRICTER than the legacy order.status arm, which is unchanged. LOCK ORDER: anti-oracle scoped resolve WITHOUT a round lock (nonexistent and foreign rounds raise the SAME structural 42501), then the PARENT orders row FOR UPDATE (the global first lock), then the round FOR UPDATE — never round-first. Parent guards: voided/cancelled -> parent_order_voided; completed -> parent_order_completed. ITEM SEMANTICS = the initial-order transition exactly: NO order_items row is mutated (items keep their submit-time status; only the void cascade moves them) — never the original items, never another round''s. ready_at stamps WRITE-ONCE on entering ready (the durable ready-feed record) and is never cleared. Entering served chains app.try_auto_complete_order under the HELD parent lock (trigger round_served): completion fires exactly once, only when parent served + fully settled + every round served. All denials are flat typed audited RETURNs (order.round_status_denied): parent_order_voided | parent_order_completed | invalid_transition | invalid_device_type | permission_denied. Money-free.';

revoke all on function app.update_round_status(uuid, uuid, uuid, text, text) from public;
revoke all on function app.update_round_status(uuid, uuid, uuid, text, text) from anon;
grant execute on function app.update_round_status(uuid, uuid, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. COMPLETION MACHINERY — faithful re-creations from the LATEST owner
--    20260714090000_order_auto_completion_001_served_paid.sql, each with a
--    surgical PSC-001C delta (marked inline):
--      * app.try_auto_complete_order — the automatic decision ADDITIONALLY
--        requires app.order_rounds_all_served (new honest fail-soft reason
--        'rounds_active'); the new trigger tag 'round_served' arrives via the
--        existing free-text p_trigger.
--      * app.apply_order_status_transition — the manual served->completed gate
--        ADDITIONALLY requires the same predicate (typed rounds_not_served,
--        RETURNED like order_not_paid), and the mutate stamps orders.ready_at
--        WRITE-ONCE when a transition lands on `ready`.
--    app.order_is_fully_settled, app.record_payment, app.update_order_status
--    and app.owner_complete_order are NOT touched (record_payment's existing
--    tail call picks the rounds predicate up through the helper).
-- ----------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 2. app.try_auto_complete_order — the ONE automatic decision, shared by both
--    trigger directions.
--
--    CONTRACT (read this before changing it):
--      * The caller MUST already hold the order row lock (both callers take
--        `select ... for update` on orders as their FIRST lock). This helper adds
--        NO new lock, so it cannot introduce a lock-order inversion or a deadlock.
--      * It NEVER RAISES. A failure here must never turn a SUCCESSFUL payment into a
--        client-side failure — the POS payment parser is fail-closed and treats any
--        non-`applied` result as a failed payment. Auto-completion is a consequence
--        of the operation, never a precondition of it.
--      * It does NOT re-run the role gate: authorization already passed on the
--        triggering operation (see the header).
--      * It is IDEMPOTENT and single-shot: it only fires on a `served` order that is
--        fully settled, and the very first thing it does is re-read the status under
--        the held lock. An order that is already `completed` (a retry, a replay, or
--        the loser of a race) is left alone and reports completed=false, so no second
--        transition and no duplicate audit event can ever occur.
-- ---------------------------------------------------------------------------
create or replace function app.try_auto_complete_order(
  p_organization_id           uuid,
  p_restaurant_id             uuid,
  p_branch_id                 uuid,
  p_order_id                  uuid,
  p_trigger                   text,   -- 'order_served' | 'payment_recorded'
  p_actor_app_user_id         uuid,   -- the REAL initiating actor (JWT path)
  p_actor_employee_profile_id uuid,   -- the REAL initiating actor (PIN path)
  p_actor_membership_id       uuid,
  p_actor_role                text,
  p_device_id                 uuid,
  p_local_operation_id        text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_status     text;
  v_rev        integer;
  v_new_rev    integer;
  v_total      bigint;  -- the order's CURRENT total: decides chargeable vs not
  v_err_state  text;    -- fail-soft diagnostics (see the exception handler)
  v_err_msg    text;
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- The order row is ALREADY locked by the caller; this re-read is a no-op
  -- re-acquire in the same transaction and gives us the CURRENT committed state.
  select o.status, o.revision, o.grand_total_minor
    into v_status, v_rev, v_total
    from public.orders o
    where o.id              = p_order_id
      and o.organization_id = p_organization_id
      and o.deleted_at is null
    for update;

  -- Not our case: not served (submitted/accepted/preparing/ready stay put), already
  -- terminal (completed/cancelled/voided are NEVER revived), or gone.
  if not found or v_status <> 'served' then
    return jsonb_build_object('completed', false, 'reason', 'not_eligible');
  end if;

  -- PSC-001C: EVERY additional service round must itself be `served` before the
  -- parent may complete (app.order_rounds_all_served — zero rounds passes
  -- trivially; a voided round is NOT completion-eligible). An order whose final
  -- round is still with the kitchen stays OPEN even when fully paid; the round's
  -- own served transition re-runs this decision under the same parent lock.
  if not app.order_rounds_all_served(p_organization_id, p_order_id) then
    return jsonb_build_object('completed', false, 'reason', 'rounds_active');
  end if;

  -- The authoritative SETTLEMENT test. An unpaid served order stays served and
  -- stays visible in Awaiting close — that is the point.
  if not app.order_is_fully_settled(p_organization_id, p_order_id) then
    return jsonb_build_object('completed', false, 'reason', 'not_fully_paid');
  end if;

  -- The ONLY mutation: status + revision. No payment is created or touched, no
  -- total is recomputed, no table/shift/receipt is affected.
  v_new_rev := v_rev + 1;
  update public.orders
    set status = 'completed', revision = v_new_rev
    where id = p_order_id;

  -- ONE canonical audit event, naming the REAL initiating actor and device, and
  -- proving this was automatic and why. Money-free (T-003).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    p_organization_id, p_restaurant_id, p_branch_id,
    p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
    'order.status_updated', null,
    jsonb_build_object('order_id', p_order_id, 'status', 'served', 'revision', v_rev),
    jsonb_build_object(
      'order_id',              p_order_id,
      'order_code',            v_order_code,
      'status',                'completed',
      'revision',              v_new_rev,
      'resolved_membership_id', p_actor_membership_id,
      'role',                  p_actor_role,
      'local_operation_id',    p_local_operation_id,
      -- THE AUDIT MUST NOT LIE (D-013, invariant 8 — this trail is append-only and
      -- can never be corrected). A ZERO-TOTAL order settles with NO payment row, so
      -- writing 'paid' here would assert a payment that was never taken — and the
      -- owner would see the SAME order as `unpaid` in the Orders list, which derives
      -- its payment_status from the existence of a payments row. Say what is true:
      -- there was nothing to pay.
      'payment_status',        case when v_total = 0 then 'not_chargeable' else 'paid' end,
      'completion_mode',       'automatic',
      'completion_trigger',    p_trigger));

  return jsonb_build_object(
    'completed', true, 'revision', v_new_rev, 'trigger', p_trigger,
    'order_code', v_order_code);
exception
  -- FAIL SOFT, ALWAYS — BUT NEVER SILENTLY.
  --
  --  * FAIL SOFT: a successful payment (or a successful `served` transition) must
  --    never be turned into a client-visible failure by its own SIDE EFFECT. The POS
  --    payment parser is fail-closed and treats any non-`applied` result as a FAILED
  --    payment, so re-raising here would tell a cashier the money was not taken when
  --    it was. We therefore swallow the error instead of propagating it.
  --  * NEVER SILENTLY: an unexpected error here is a real defect, so it is RAISEd as
  --    a WARNING carrying the SQLSTATE and the message. That reaches the PostgreSQL
  --    server log at the default log_min_messages, giving an operator something
  --    diagnosable to find; a WARNING cannot abort the transaction, so the payment
  --    still commits. The SQLSTATE (never the message) is also returned to the caller
  --    in `error_code`.
  --  * NOTHING PARTIAL, NO FAKE SUCCESS: the `update orders` and the audit `insert`
  --    above both run inside THIS block's implicit savepoint, so if either one fails
  --    BOTH are rolled back. The order stays `served`, NO audit row exists, and we
  --    report completed=false. There is no path that can write a SUCCESS audit event
  --    for a completion that did not actually happen.
  when others then
    get stacked diagnostics
      v_err_state = returned_sqlstate,
      v_err_msg   = message_text;
    raise warning
      'ORDER-AUTO-COMPLETION-001 app.try_auto_complete_order FAILED (fail-soft): order_id=% trigger=% sqlstate=% message=%',
      p_order_id, p_trigger, v_err_state, v_err_msg;
    return jsonb_build_object(
      'completed',  false,
      'reason',     'auto_completion_failed',
      'error_code', v_err_state);
end;
$$;

comment on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) is
  'ORDER-AUTO-COMPLETION-001: the ONE automatic served -> completed decision, shared by both trigger directions (chained at the tail of app.apply_order_status_transition when a transition lands on `served`, and at the tail of app.record_payment when an order becomes fully paid). PRECONDITION: the caller already holds the order row lock (both do), so this adds NO lock and cannot deadlock. It fires ONLY on a `served` order that app.order_is_fully_settled reports as settled (integer minor units); an unpaid served order is left active. It does NOT re-run the role gate — authorization already passed on the triggering operation, and the automatic step is a system-rule consequence, not a second human decision (the manual fronts keep the frozen role gate untouched). IDEMPOTENT: it re-reads the status under the held lock, so an already-completed order (retry, replay, or the loser of a race) is left alone -> no duplicate transition, no duplicate audit event. It NEVER RAISES (fail-soft), because a failure here must never turn a successful payment into a failed one. Writes orders.status + revision and ONE money-free order.status_updated audit carrying completion_mode=automatic + completion_trigger + the safe order_code. PSC-001C: the decision ADDITIONALLY requires app.order_rounds_all_served (every additional service round served; zero rounds passes; a voided round blocks — honest fail-soft reason rounds_active) and accepts the new trigger tag round_served from app.update_round_status, which re-runs the decision under the same held parent lock when the final round serves. Faithful re-creation of the 20260714090000 body. INTERNAL: granted to no client role.';

-- ---------------------------------------------------------------------------
-- 3. app.apply_order_status_transition — the SHARED state-machine core, faithfully
--    re-created from ORDER-COMPLETION-001 with exactly THREE surgical changes:
--      (i)   the D-025 gate now uses app.order_is_fully_settled (a SETTLEMENT test
--            instead of a marker test) — this hardens the MANUAL path too;
--      (ii)  TRIGGER DIRECTION A: when a transition lands on `served`, the automatic
--            completion is chained under the SAME order row lock already held;
--      (iii) the envelope reports `auto_completed` and the FINAL status.
--    The legality CASE, the role gate, the locking and the audit shape are UNCHANGED.
--    No new transition edge is added: direction A chains a SECOND, already-legal
--    single-step transition (served -> completed); it does not widen the table.
-- ---------------------------------------------------------------------------
create or replace function app.apply_order_status_transition(
  p_order_id                  uuid,
  p_new_status                text,
  p_actor_org                 uuid,
  p_actor_restaurant          uuid,
  p_actor_branch              uuid,
  p_actor_role                text,
  p_actor_app_user_id         uuid,      -- JWT actor  (null on the device path)
  p_actor_employee_profile_id uuid,      -- PIN actor  (null on the JWT path)
  p_actor_membership_id       uuid,
  p_device_id                 uuid,      -- null on the JWT path
  p_local_operation_id        text,      -- null on the JWT path
  p_expected_revision         integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_o_org      uuid;
  v_o_branch   uuid;
  v_o_status   text;
  v_o_rev      integer;
  v_legal      boolean;
  v_new_rev    integer;
  v_paid       boolean;
  v_o_total    bigint;   -- the order's CURRENT total: chargeable vs not_chargeable
  v_auto       jsonb;
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) load the order FOR UPDATE (serializes concurrent status pushes); it MUST
  --     be in the actor's organization AND branch. Cross-tenant -> fail-closed
  --     raise, no write.
  select o.organization_id, o.branch_id, o.status, o.revision, o.grand_total_minor
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_o_total
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'update_order_status: order not found' using errcode = '42501';
  end if;
  if v_o_org <> p_actor_org or v_o_branch <> p_actor_branch then
    raise exception 'update_order_status: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (b) OPTIMISTIC CONCURRENCY (opt-in; the PIN front passes null, preserving its
  --     exact behaviour). A stale client that read revision N cannot overwrite a
  --     newer state: it gets the documented `revision_mismatch` with the server's
  --     revision so it can re-read. (API_CONTRACT §2 error model.)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    return jsonb_build_object('ok', false, 'error', 'revision_mismatch',
                              'order_id', p_order_id, 'status', v_o_status,
                              'server_revision', v_o_rev,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) transition legality: SINGLE-STEP forward only over the FROZEN states
  --     (D-018, STATE_MACHINES §1.1). Skips, backwards, terminal sources
  --     (completed/cancelled/voided), unknown targets, and from==to are all
  --     invalid_transition (returned, not raised — a permanent per-op rejection
  --     through sync_push; no state change). The client can NEVER choose an
  --     arbitrary next status: only these five (from, to) pairs exist.
  v_legal := case
    when v_o_status = 'submitted' and p_new_status = 'accepted'  then true
    when v_o_status = 'accepted'  and p_new_status = 'preparing' then true
    when v_o_status = 'preparing' and p_new_status = 'ready'     then true
    when v_o_status = 'ready'     and p_new_status = 'served'    then true
    when v_o_status = 'served'    and p_new_status = 'completed' then true
    else false end;
  if not v_legal then
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'from', v_o_status, 'to', p_new_status, 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) role authorization: the production + service steps (->accepted/->preparing/
  --     ->ready/->served — the last is the KDS "bump") allow kitchen_staff + cashier
  --     + manager + restaurant_owner + org_owner; the settlement step (->completed)
  --     EXCLUDES kitchen_staff. A denial is audited (order.status_update_denied —
  --     NO money fields) and RETURNED (no raise, so the audit persists), with NO
  --     state change.
  if p_actor_role not in ('kitchen_staff', 'cashier', 'manager', 'restaurant_owner', 'org_owner')
     or (p_actor_role = 'kitchen_staff' and p_new_status = 'completed') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
            'order.status_update_denied', null, null,
            jsonb_build_object('attempted_action', 'update_order_status', 'order_id', p_order_id,
                               'order_code', v_order_code,
                               'role', p_actor_role, 'from', v_o_status, 'to', p_new_status,
                               'local_operation_id', p_local_operation_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (e) D-025 PAYMENT GATE (ORDER-COMPLETION-001) — an order reaches `completed`
  --     only when payment is `completed`. Derived, never fabricated: "paid" is the
  --     existence of a completed, live payments row (the SAME derivation the
  --     reports and owner_active_orders use). This creates NO payment and changes
  --     NO payments row. A business rejection, NOT an authorization denial, so —
  --     like invalid_transition — it is RETURNED and deliberately NOT audited (the
  --     denied-attempt audit is reserved for authorization failures).
  if p_new_status = 'completed' then
    -- ORDER-AUTO-COMPLETION-001: the ONE authoritative settlement test (integer
    -- minor units). Replaces the bare exists()-a-completed-payment MARKER test:
    -- app.apply_discount can re-base grand_total_minor after a payment is taken, so
    -- a marker could report a partially-settled order as paid. Identical to the old
    -- test in every normal case (the stored amount IS the order total).
    v_paid := app.order_is_fully_settled(v_o_org, p_order_id);
    if not v_paid then
      return jsonb_build_object('ok', false, 'error', 'order_not_paid',
                                'order_id', p_order_id, 'from', v_o_status, 'to', p_new_status,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    -- PSC-001C: the MANUAL completion gate additionally requires EVERY
    -- additional service round to be served (app.order_rounds_all_served —
    -- zero rounds passes trivially). A business rejection like order_not_paid:
    -- RETURNED, deliberately not audited (the denied-attempt audit is reserved
    -- for authorization failures).
    if not app.order_rounds_all_served(v_o_org, p_order_id) then
      return jsonb_build_object('ok', false, 'error', 'rounds_not_served',
                                'order_id', p_order_id, 'from', v_o_status, 'to', p_new_status,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  -- (f) mutate: status forward one step; bump revision (updated_at bumps via the
  --     RF-052 set_updated_at trigger, feeding the sync_pull change cursor).
  --     orders.status + orders.revision are the ONLY columns written. No payment,
  --     no shift, no table, no receipt, no total is touched.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status   = p_new_status,
        revision = v_new_rev,
        -- PSC-001C: the WRITE-ONCE durable ready stamp for the INITIAL kitchen
        -- work unit (the ready-feed source). Stamped exactly when a transition
        -- lands on `ready`; never cleared or re-stamped afterwards (the
        -- single-step matrix makes `ready` reachable once, and the case-guard
        -- keeps the stamp idempotent regardless).
        ready_at = case when p_new_status = 'ready' and ready_at is null then now() else ready_at end
    where id = p_order_id;

  -- (g) audit order.status_updated (D-013) — old/new STATUS + revision + actor
  --     linkage + the SAFE order_code, plus the derived payment_status on a
  --     completion. Deliberately NO money fields: a kitchen actor drives the
  --     production steps of this path and must never put a money figure on the
  --     wire or in its audit (T-003).
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
          'order.status_updated', null,
          jsonb_build_object('order_id', p_order_id, 'status', v_o_status, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'status', p_new_status, 'revision', v_new_rev,
                             'resolved_membership_id', p_actor_membership_id, 'role', p_actor_role,
                             'local_operation_id', p_local_operation_id)
          -- THE AUDIT MUST NOT LIE (D-013): a ZERO-TOTAL order is completed WITHOUT a
          -- payment row, so 'paid' would assert a payment that was never taken. State
          -- the truth — there was nothing to pay.
          || case when p_new_status = 'completed'
                  then jsonb_build_object('payment_status',
                                          case when v_o_total = 0 then 'not_chargeable'
                                               else 'paid' end,
                                          'completion_mode', 'manual')
                  else '{}'::jsonb end);

  -- (h) TRIGGER DIRECTION A (ORDER-AUTO-COMPLETION-001): the order just reached
  --     `served`. If it is ALREADY fully paid, complete it now — in this same
  --     transaction, under the order row lock we already hold. The `served`
  --     transition above stands on its own and is NEVER failed by this: an unpaid
  --     order simply stays served (and stays visible in Awaiting close). The helper
  --     never raises, and it does not re-run the role gate — the kitchen actor was
  --     already authorized to make THIS transition, and the completion is a
  --     system-rule consequence of it, not a second human decision.
  if p_new_status = 'served' then
    v_auto := app.try_auto_complete_order(
      p_actor_org, p_actor_restaurant, p_actor_branch, p_order_id,
      'order_served',
      p_actor_app_user_id, p_actor_employee_profile_id, p_actor_membership_id,
      p_actor_role, p_device_id, p_local_operation_id);
    if (v_auto ->> 'completed')::boolean then
      -- Report the FINAL state, so the caller (and the sync ledger) never records a
      -- status the order is no longer in.
      return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                                'order_code', v_order_code,
                                'status', 'completed',
                                'revision', (v_auto ->> 'revision')::integer,
                                'auto_completed', true,
                                'completion_trigger', 'order_served',
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                            'order_code', v_order_code,
                            'status', p_new_status, 'revision', v_new_rev,
                            'auto_completed', false,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) is
  'ORDER-COMPLETION-001 + ORDER-AUTO-COMPLETION-001: the ACTOR-AGNOSTIC CORE of the order state machine (D-018, STATE_MACHINES §1.1) — the SINGLE implementation of scope re-check, single-step transition legality, role authorization, the D-025 payment gate, the write and the audit. The D-025 gate is now app.order_is_fully_settled (integer minor units: a live completed payment whose amount covers the CURRENT grand_total_minor) — a SETTLEMENT test, not a marker test. AUTO-COMPLETION (direction A): when a transition lands on `served` and the order is already fully paid, app.try_auto_complete_order completes it in the SAME transaction under the SAME order row lock, and the envelope reports auto_completed + the FINAL status; an unpaid order simply stays served. It resolves NO actor and trusts NO client: the caller (app.update_order_status for a PIN/device principal, app.owner_complete_order for a JWT principal) must already have authenticated the actor and established scope coverage. PSC-001C: the manual served->completed gate ADDITIONALLY requires app.order_rounds_all_served (typed rounds_not_served refusal, returned like order_not_paid), and the mutate stamps orders.ready_at WRITE-ONCE when a transition lands on `ready` (the durable ready-feed source; never cleared afterwards). Faithful re-creation of the 20260714090000 body. INTERNAL: not granted to any client role.';

-- ACL parity for the two re-created completion functions (INTERNAL: no client
-- role may execute either; the SECURITY DEFINER callers reach them as owner).
revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from public;
revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from anon;
revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from authenticated;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from public;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from anon;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from authenticated;

-- ----------------------------------------------------------------------------
-- 8. app.void_order — faithful re-creation from the LATEST owner
--    20260721090000_psc_001d_kds_void_ack.sql with ONE surgical PSC-001C delta
--    (marked inline): the whole-order void cascade ADDITIONALLY marks every
--    live service round of the parent `voided` (round void_reason stamped,
--    ready_at PRESERVED, snapshots + round membership untouched). Every
--    PSC-001D behavior — provenance stamping, kitchen_ack_required, the four
--    CHECKs, all refusal shapes, the item cascade, idempotency, audits — is
--    preserved byte-for-behavior.
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
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.void_order(uuid, uuid, uuid, text, text, integer) is
  'RF-053 + RF-062 + STAFF-CASHIER-PERMISSIONS-001 + MONEY-SETTLEMENT-CONSISTENCY-001 + PSC-001D (API_CONTRACT §4.6, D-011/D-024): SECURITY DEFINER RPC voiding a WRONG, UNPAID order with a MANDATORY reason. PIN-session auth; manager/restaurant_owner/org_owner, or a cashier with an explicit void_order capability. ELIGIBILITY IS UNCHANGED: legal source states are exactly submitted/accepted/preparing/ready/served — `completed` is TERMINAL (D-024) and there is NO completed -> void path, for a zero-total order or any other. A LIVE COMPLETED payment blocks the void (RF-062; no refund flow, D-023). Order row locked FOR UPDATE (serializes with record_payment). ALL THREE refusals are RETURNED, never raised (a raise would roll back the audit row) and are audited order.void_denied with a safe denied_reason: permission_denied (role), permission_denied + detail=order_has_completed_payment (paid), and invalid_transition + detail=order_not_voidable + order_status (terminal / illegal source state). Returning rather than raising is what lets app.sync_push propagate the domain code to the client verbatim — a RAISE is flattened to a generic ''rejected'', which previously left the POS unable to tell an already-closed order apart from a dropped network. Order-bound idempotency (D-022). Success cascades items -> voided and writes order.voided (D-013). PSC-001D: the success mutate ALSO stamps voided_at + voided_from_status and computes kitchen_ack_required (TRUE for an ACTIVE kitchen source submitted|accepted|preparing|ready; FALSE from served) so the KDS keeps the cancellation visible until app.kitchen_ack_void; the success audit carries the two safe provenance scalars. PSC-001C: the success mutate ALSO sweeps every live ADDITIONAL service round to voided (void_reason stamped; ready_at and snapshots preserved) so no later round transition exists and completion stays impossible; there is NO independent round-void feature. Faithful re-creation of the 20260721090000 body. MONEY-FREE: creates/deletes NO payment and recomputes NO total.';

-- ACL parity for the UNCHANGED signature (CREATE OR REPLACE preserves grants;
-- re-issued explicitly per the submit_order recreation convention).
revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from public;
revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from anon;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. Transport op-type CHECK — 15 canonical operations (+order.items_add = 14,
--    +order.round_status = 15). Additive widening: every prior value survives.
-- ----------------------------------------------------------------------------
alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status'));

-- ----------------------------------------------------------------------------
-- 10. app.sync_push — faithful re-creation from the LATEST owner
--     20260721090000_psc_001d_kds_void_ack.sql with the PSC-001C deltas
--     (marked inline): TWO new dispatch arms (order.items_add ->
--     app.add_order_items; order.round_status -> app.update_round_status),
--     both op allowlists extended to 15, and the FULL PSC-001D identity
--     hardening (protected target parse, pre-fingerprint identity validation,
--     target-bound fingerprint, both device paths) extended to BOTH new
--     operations (order.round_status binds payload.round_id). All 13 prior
--     operations preserved byte-for-behavior. public.sync_push is untouched.
-- ----------------------------------------------------------------------------
create or replace function app.sync_push(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_operations     jsonb
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
  v_op           jsonb;
  v_local_op     text;
  v_op_type      text;
  v_payload      jsonb;
  v_depends      jsonb;
  v_target_ent   text;
  v_target_id    uuid;
  v_client_ts    timestamptz;
  v_fingerprint  text;
  v_dep          text;
  v_dep_ok       boolean;
  v_ex_status    text;
  v_ex_result    jsonb;
  v_ex_optype    text;
  v_ex_fp        text;
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
  v_device_revoked boolean := false;
  v_customer_name text;
  v_ack_order    uuid;
  v_ack_ok       boolean;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests — keeps a push transaction bounded).
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'sync_push: p_operations must be a JSON array' using errcode = '42501';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'sync_push: batch too large (max 100 operations, got %)', jsonb_array_length(p_operations) using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing. Scope is derived here. The PIN
  --     session must exist + be valid (offline-window bounded, Q-009); a missing session
  --     or expired PIN still raises (cannot key/record safely without a session/window).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_push: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_push: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found then
    raise exception 'sync_push: backing device session not found' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_push: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- RF061-A1: a REVOKED / inactive device session or pairing no longer fails the whole
  -- batch with a silent raise. Instead each pushed op is RECORDED as rejected
  -- (revoked_device) and surfaced, so the offline-queued operations are not lost (R-007;
  -- AC1). Authorization is INGEST-TIME (the device is revoked NOW); client timestamps are
  -- never trusted. A previously-APPLIED op still replays its stored result (idempotency).
  if not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    v_device_revoked := true;
    for v_op in select * from jsonb_array_elements(p_operations)
    loop
      v_local_op   := v_op ->> 'local_operation_id';
      v_op_type    := v_op ->> 'operation_type';
      v_payload    := v_op -> 'payload';
      v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
      v_target_ent := v_op ->> 'target_entity';
      -- PSC-001D correction (F3) + PSC-001C: for the three IDENTITY-HARDENED
      -- operations (order.void_ack, order.items_add, order.round_status) the
      -- target id is parsed inside a PROTECTED boundary — a malformed uuid
      -- must reject only ITS operation, never abort the whole batch. The 12
      -- prior operations keep their exact existing parse semantics.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        begin
          v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
        exception when others then
          v_target_id := null;
        end;
      else
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      end if;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      -- PSC-001D correction (final pass) + PSC-001C: the SAME canonical
      -- identity contract as the valid path for ALL THREE hardened operations,
      -- enforced BEFORE the fingerprint, the terminal-replay lookup, the
      -- idempotency-conflict comparison and the ledger write. A revoked device
      -- must not gain permission to submit ambiguous or contradictory
      -- operation identity: a missing, malformed or CONTRADICTORY
      -- target/payload-identity pair (payload.order_id for order.void_ack and
      -- order.items_add; payload.round_id for order.round_status) is a hostile
      -- or malformed envelope — rejected with NO ledger row (the malformed-
      -- envelope convention), the batch continues. Only that op is affected.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_ack_ok := v_target_id is not null;
        begin
          v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
        exception when others then
          v_ack_order := null;
        end;
        if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
            'ok', false, 'error', 'invalid_payload',
            'detail', v_op_type || ' requires matching uuid target_id and payload.'
                      || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
            'status', 'rejected', 'idempotency_replay', false);
          continue;
        end if;
      end if;

      -- PSC-001D correction (F2 + final pass) + PSC-001C: the SAME target-
      -- bound fingerprint SHAPE as the valid path for all three hardened
      -- operations — the target component is the PARSED uuid's text
      -- (guaranteed non-null and equal to the parsed payload identity by the
      -- check above), so a legitimately-applied op still replays its stored
      -- result after a revocation (identical identity -> identical
      -- fingerprint), while the 12 prior operations are unchanged.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
      else
        v_fingerprint := md5(v_op_type || '|' || v_payload::text);
      end if;

      -- dedup/replay: a stored op with the SAME identity that is TERMINAL replays its
      -- result (a legitimately-APPLIED op before revocation is NOT re-rejected); a
      -- different identity is a conflict; otherwise record the op as rejected (revoked_device).
      select so.status, so.result, so.operation_type, so.payload_fingerprint
        into v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
        from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op;
      if found then
        if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
          insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
          values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                  jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                     'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
            'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
          continue;
        end if;
        if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
          v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
            || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
          continue;
        end if;
      end if;

      -- record the op as rejected (revoked_device); NO business mutation, NO dispatch.
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, rejection_reason,
        result, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'rejected',
              'revoked_device', 'permanent', 'revoked_device',
              jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'), v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do update
        set status = 'rejected', last_error_code = 'revoked_device', last_error_class = 'permanent',
            rejection_reason = 'revoked_device',
            result = jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'),
            retry_count = so.retry_count + 1, updated_at = now();
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'revoked_device', null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'reason', 'revoked_device'));
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'rejected', 'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false);
    end loop;
    return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now(), 'device_revoked', true);
  end if;

  -- (b) per-operation loop (ordered) — VALID device path (unchanged from RF-056)
  for v_op in select * from jsonb_array_elements(p_operations)
  loop
    v_caught_state := null;
    v_caught_msg   := null;
    v_dispatch     := null;
    v_dispatch_ok  := null;
    v_so_id        := null;

    v_local_op   := v_op ->> 'local_operation_id';
    v_op_type    := v_op ->> 'operation_type';
    v_payload    := v_op -> 'payload';
    v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
    v_target_ent := v_op ->> 'target_entity';
    -- PSC-001D correction (F3) + PSC-001C: protected parse for the three
    -- identity-hardened operations — a malformed target uuid rejects only ITS
    -- operation (below), never the batch. The 12 prior operations keep their
    -- exact existing semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      begin
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      exception when others then
        v_target_id := null;
      end;
    else
      v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
    end if;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
        'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if jsonb_typeof(v_depends) <> 'array' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_depends_on', 'detail', 'depends_on must be a JSON array', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;

    -- (b1+) PSC-001D correction (F2/F3) + PSC-001C: CANONICAL TARGET IDENTITY
    -- for the three hardened operations, enforced BEFORE the fingerprint, the
    -- terminal-replay lookup and the dispatch. The envelope MUST carry a
    -- parseable target_id AND a parseable payload identity (payload.order_id
    -- for order.void_ack and order.items_add; payload.round_id for
    -- order.round_status) and they MUST be the same uuid — a missing,
    -- malformed or CONTRADICTORY pair is a hostile/malformed envelope:
    -- rejected with NO ledger row (the malformed-envelope convention), so a
    -- replayed local_operation_id with a swapped target can never reach the
    -- stored terminal result, mutate anything, or learn anything about
    -- another order or round. Only that operation is affected.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_ack_ok := v_target_id is not null;
      begin
        v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
      exception when others then
        v_ack_order := null;
      end;
      if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload',
          'detail', v_op_type || ' requires matching uuid target_id and payload.'
                    || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
          'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
    end if;

    -- PSC-001D correction (F2) + PSC-001C: the fingerprint of every hardened
    -- operation BINDS the canonical target identity, so a terminal replay is
    -- valid only for the same local_operation_id + operation + payload +
    -- TARGET. The 12 prior operations keep their exact existing fingerprint
    -- semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
    else
      v_fingerprint := md5(v_op_type || '|' || v_payload::text);
    end if;

    -- (b2) dedup / replay (transport identity = org + device + local_operation_id).
    select so.status, so.result, so.operation_type, so.payload_fingerprint
      into v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
      from public.sync_operations so
      where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op;
    if found then
      if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                   'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
        continue;
      end if;
      if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
        v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
          || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
        continue;
      end if;
    end if;

    -- (b3) dependency guard.
    v_dep_ok := true;
    for v_dep in select jsonb_array_elements_text(v_depends)
    loop
      if not exists (
        select 1 from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id
          and so.local_operation_id = v_dep and so.status = 'applied'
      ) then
        v_dep_ok := false;
        exit;
      end if;
    end loop;

    if not v_dep_ok then
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'pending',
              'dependency_not_ready', 'transient', v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do update
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + 1, updated_at = now();
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) mark in_flight (insert new, or bump a re-attempt)
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do update
      set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
    returning so.id into v_so_id;

    -- (b5) dispatch to the matching business RPC inside a per-op EXCEPTION subtransaction.
    begin
      case v_op_type
        when 'shift.open' then
          v_dispatch := app.open_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            (v_payload ->> 'cash_drawer_session_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'opening_float_minor')::bigint);
        when 'order.submit' then
          v_dispatch := app.submit_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'order_type',
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'shift_id', '')::uuid,
            v_payload ->> 'currency_code',
            v_payload ->> 'notes',
            v_payload -> 'order_items',
            (v_payload ->> 'subtotal_minor')::bigint,
            (v_payload ->> 'discount_total_minor')::bigint,
            (v_payload ->> 'tax_total_minor')::bigint,
            (v_payload ->> 'grand_total_minor')::bigint,
            v_client_ts);
          -- ORDER-CUSTOMER-001: stamp the OPTIONAL customer display name on the
          -- order app.submit_order just created. Kept OUT of submit_order so its
          -- validated INSERT stays byte-unchanged. Money-free display text: trim
          -- + empty->null + 80-char cap. Tenant-scoped by v_org; the
          -- `customer_name is null` guard makes it idempotent (a replay returns
          -- the same order_id, already stamped) and never overwrites.
          v_customer_name := left(btrim(coalesce(v_payload ->> 'customer_name', '')), 80);
          if v_customer_name <> '' then
            update public.orders
              set customer_name = v_customer_name
              where id = (v_dispatch ->> 'order_id')::uuid
                and organization_id = v_org
                and customer_name is null;
          end if;
        when 'order.discount' then
          v_dispatch := app.apply_discount(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'scope',
            nullif(v_payload ->> 'order_item_id', '')::uuid,
            v_payload ->> 'discount_type',
            (v_payload ->> 'value')::bigint,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'payment.create' then
          v_dispatch := app.record_payment(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'tender_type',
            (v_payload ->> 'amount_tendered_minor')::bigint,
            nullif(v_payload ->> 'provisional_receipt_number', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'shift.close' then
          v_dispatch := app.close_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'counted_amount_minor')::bigint,
            nullif(v_payload ->> 'reason', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        -- MVP addition: KDS/POS order-status updates ride the SAME outbox/ledger
        -- (D-010/D-022). Scope/actor come from the pin session + device passed
        -- through (A8); the payload contributes ONLY {order_id, new_status}.
        when 'order.status' then
          v_dispatch := app.update_order_status(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'order_id')::uuid,
            v_payload ->> 'new_status',
            v_local_op);
        when 'order.void' then
          -- MONEY-VOID-001: role-gated void of a wrong UNPAID order. Mirrors the
          -- order.discount branch - actor/org/branch come from the PIN session
          -- (never the payload) and the op's local_operation_id threads
          -- app.void_order's own idempotency (D-022). app.void_order (RF-053,
          -- hardened by RF-062) enforces manager/restaurant_owner/org_owner (or a
          -- cashier with permissions.void_order='true'), a mandatory reason, legal
          -- source states (submitted/accepted/preparing/ready/served), and the
          -- completed-payment block (an order with a live completed payment
          -- returns permission_denied) - so paid orders are refused server-side.
          -- Money-free: it only sets orders.status='voided' + void_reason +
          -- revision and cascades items -> voided; no payment/total is touched.
          v_dispatch := app.void_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'order.table_move' then
          -- RESTAURANT-OPERATIONS-V1-001: atomic dine-in table move. Mirrors the
          -- order.void branch — actor/org/branch come from the PIN session
          -- (never the payload); the op's local_operation_id threads
          -- app.move_order_table's ORDER-BOUND idempotency (D-022); the payload
          -- contributes ONLY {order_id, table_id[, expected_revision]}. Typed
          -- refusals (table_not_allowed / invalid_transition+order_not_movable /
          -- table_not_available / permission_denied) RETURN through verbatim;
          -- a revision conflict raises 40001 -> the per-op 'conflict' status.
          -- Money-free: only orders.table_id + revision move.
          v_dispatch := app.move_order_table(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'menu.availability_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: a cashier (default-ON
          -- manage_menu_availability) or manager+ sets a menu item's per-branch
          -- availability from the POS. Actor/org/branch derive from the PIN
          -- session (NEVER the payload); the capability is enforced inside. The
          -- payload contributes ONLY {menu_item_id, availability, reason}. The
          -- setter is naturally idempotent (no-change re-applies the same state
          -- with no audit) and transport dedup (sync_operations) guards replay.
          -- Typed RETURN refusals (permission_denied / not_found) survive
          -- verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_item_availability(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'menu_item_id')::uuid,
            v_payload ->> 'availability',
            nullif(v_payload ->> 'reason', ''));
        when 'table.status_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: manual table floor-state from the
          -- POS (manage_table_operations). Scope/actor from the session; payload
          -- {table_id, status}. Typed refusals survive verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_table_status(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid,
            v_payload ->> 'status');
        when 'table.link' then
          -- Link two same-branch tables into an operational group (no order/bill
          -- merge). Payload {table_id_a, table_id_b}. Deterministic lock order.
          v_dispatch := app.pos_link_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id_a')::uuid,
            (v_payload ->> 'table_id_b')::uuid);
        when 'table.unlink' then
          -- Dissolve the group a table belongs to (orders untouched). Payload
          -- {table_id}.
          v_dispatch := app.pos_unlink_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid);
        when 'order.void_ack' then
          -- PSC-001D: the kitchen's cancellation acknowledgement. Mirrors the
          -- order.status branch — actor/org/branch come from the PIN session
          -- (never the payload); the payload contributes ONLY {order_id}.
          -- app.kitchen_ack_void enforces the KDS-class device, the kitchen
          -- role set, the voided + ack-required state, and the idempotent
          -- already-acknowledged replay; its flat typed refusals
          -- (invalid_device_type / permission_denied / order_not_voided /
          -- acknowledgement_not_required) RETURN through verbatim. TARGET-ID
          -- CONSISTENCY is enforced at (b1+) BEFORE the fingerprint and the
          -- terminal replay — by the time this arm runs, target_id and
          -- payload.order_id are guaranteed present, valid and equal. The
          -- check below is pure defence-in-depth and unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.void_ack target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.kitchen_ack_void(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op);
        when 'order.items_add' then
          -- PSC-001C: add items to an existing eligible dine-in order as ONE
          -- new authoritative service round. Actor/org/branch come from the
          -- PIN session; the payload contributes {order_id, order_items}.
          -- app.add_order_items enforces the POS-class device, the cashier+
          -- role set, eligibility (dine_in, open status, no completed
          -- payment), submit_order-parity pricing/sellability, and round-level
          -- idempotency; its flat typed refusals (invalid_device_type /
          -- permission_denied / order_not_dine_in / order_not_eligible /
          -- order_already_settled / item_unavailable / invalid_item_payload)
          -- RETURN through verbatim. TARGET-ID CONSISTENCY is enforced at
          -- (b1+) BEFORE the fingerprint and the terminal replay — the check
          -- below is pure defence-in-depth and unreachable.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.items_add target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.add_order_items(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload -> 'order_items',
            v_client_ts);
        when 'order.round_status' then
          -- PSC-001C: the additional service round's own single-step
          -- lifecycle. Actor/org/branch come from the PIN session; the
          -- payload contributes {round_id, new_status}. app.update_round_status
          -- enforces the LOCKED device/role matrix (production steps KDS-only;
          -- ready->served KDS kitchen set or POS cashier set), the parent
          -- guards, single-step legality, the WRITE-ONCE ready_at stamp and
          -- the completion chain; its flat typed refusals RETURN through
          -- verbatim. TARGET-ID CONSISTENCY (against payload.round_id) is
          -- enforced at (b1+) — the check below is pure defence-in-depth and
          -- unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'round_id')::uuid then
            raise exception 'sync_push: order.round_status target_id does not match payload.round_id' using errcode = '42501';
          end if;
          v_dispatch := app.update_round_status(
            p_pin_session_id,
            (v_payload ->> 'round_id')::uuid,
            p_device_id,
            v_payload ->> 'new_status',
            v_local_op);
      end case;
      v_dispatch_ok := coalesce((v_dispatch ->> 'ok')::boolean, false);
    exception
      when others then
        v_caught_state := SQLSTATE;
        v_caught_msg   := SQLERRM;
    end;

    -- (b6) finalize the operation outcome
    if v_caught_state is not null then
      if v_caught_state = '40001' then
        update public.sync_operations
          set status = 'conflict', last_error_code = v_caught_state, last_error_class = 'conflict',
              conflict_info = jsonb_build_object('sqlstate', v_caught_state, 'message', v_caught_msg),
              result = jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', v_caught_state), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', v_caught_msg, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'sqlstate', v_caught_state, 'status', 'conflict', 'idempotency_replay', false);
      else
        -- validation / state / business-rule failure -> permanent rejected. RF-061: a
        -- revoked-MEMBERSHIP op fails membership-active in the dispatched RPC; classify its
        -- rejection reason as 'revoked_employee' so the offline-revoked-employee case is clear.
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
                         'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected',
                case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state,
          'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end,
          'status', 'rejected', 'idempotency_replay', false);
      end if;
    elsif v_dispatch_ok then
      update public.sync_operations
        set status = 'applied', result = v_dispatch, applied_at = now(),
            target_id = coalesce(v_target_id, nullif(v_dispatch ->> 'order_id', '')::uuid, nullif(v_dispatch ->> 'shift_id', '')::uuid, nullif(v_dispatch ->> 'payment_id', '')::uuid),
            updated_at = now()
        where id = v_so_id;
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'applied', 'idempotency_replay', false));
    else
      update public.sync_operations
        set status = 'rejected', last_error_code = coalesce(v_dispatch ->> 'error', 'rejected'), last_error_class = 'permanent',
            rejection_reason = coalesce(v_dispatch ->> 'error', 'rejected'), result = v_dispatch, updated_at = now()
        where id = v_so_id;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', coalesce(v_dispatch ->> 'error', 'rejected'), null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', coalesce(v_dispatch ->> 'error', 'rejected')));
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'rejected', 'idempotency_replay', false));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now());
end;
$$;

comment on function app.sync_push(uuid, uuid, jsonb) is
  'RF-056/RF-061 + ... + PSC-001D + PSC-001C (D-010/D-022) SECURITY DEFINER batch push. Faithful re-creation of the 20260721090000 body + TWO added dispatch branches: order.items_add -> app.add_order_items (POS-class device + cashier+ role set + eligibility + submit_order-parity pricing enforced inside; payload carries order_id + order_items) and order.round_status -> app.update_round_status (LOCKED device/role matrix + parent guards + single-step legality enforced inside; payload carries round_id + new_status) — 15 canonical operations. IDENTITY HARDENING (the PSC-001D contract, now covering order.void_ack + order.items_add + order.round_status): the target uuid is parsed inside a PROTECTED per-operation boundary (a malformed target rejects only its own operation, never the batch); the envelope must carry a matching uuid target_id + payload identity (payload.order_id, or payload.round_id for order.round_status; a missing/malformed/contradictory pair is a malformed envelope — rejected with NO ledger row, BEFORE the fingerprint and the terminal-replay lookup); and each hardened operation''s fingerprint BINDS the canonical target identity, so a terminal replay is valid only for the same local_operation_id + type + payload + target. The identity contract is enforced identically in BOTH the valid-device and the revoked-device paths (a revoked device gains no permission to submit ambiguous identity). The 12 pre-PSC operations keep their exact parse/fingerprint semantics. All prior behaviour verbatim (batch cap, revoked-device recording, dedup/replay, dependency guard, per-op subtransactions, finalization, customer_name stamp). Authorization INGEST-TIME; scope from the session, never the payload.';

-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly).
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
revoke all on function app.sync_push(uuid, uuid, jsonb) from anon;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- 11. app.sync_pull_changes + app.sync_pull — faithful re-creations from the
--     LATEST owner 20260703140000_mvp_sync_pull_tables.sql with ONE additive
--     delta each (marked inline): `order_service_rounds` becomes a pull-allowed
--     STRICT-BRANCH entity for kitchen_staff AND the business roles. A round
--     row is MONEY-FREE by schema, so T-003 is not implicated (the kitchen
--     redact_money backstop passes over it as a no-op). order_items'
--     service_round_id rides the existing generic to_jsonb row projection with
--     NO pull change. public.sync_pull (RF-064) is untouched.
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- 1. app.sync_pull_changes — RF-109 body + 'tables' in the allow-list. 'tables'
--    is NOT a menu entity, so it falls through to the strict-branch operational
--    pager (branch_id = device branch), which is exactly right for a floor row.
-- ----------------------------------------------------------------------------
create or replace function app.sync_pull_changes(
  p_table            text,
  p_org              uuid,
  p_branch           uuid,
  p_since_updated_at timestamptz,
  p_since_id         uuid,
  p_limit            integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_rows    jsonb;
  v_count   integer;
  v_last    jsonb;
  v_is_menu boolean;
begin
  -- defence in depth: only the six approved operational tables + the six RF-109
  -- menu tables + the MVP `tables` floor entity are pageable here (unknown
  -- entity validation is preserved).
  if p_table not in ('orders', 'order_items', 'order_item_modifiers', 'payments', 'shifts', 'cash_drawer_sessions',
                     'menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options',
                     'tables', 'order_service_rounds') then
    raise exception 'sync_pull_changes: % is not a pull-allowed entity', p_table using errcode = '42501';
  end if;

  v_is_menu := p_table in ('menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options');

  if v_is_menu then
    -- RF-109 menu scope: branch-specific rows for the device branch PLUS restaurant-scoped rows
    -- (branch_id null) of the device's own restaurant (derived from the device branch so other
    -- restaurants' restaurant-scoped menu never leaks). Same (updated_at,id) cursor + lookahead +
    -- tombstones (deleted_at) as the operational pager.
    execute format($q$
      with look as (
        select t.id as _id, t.updated_at as _uat, to_jsonb(t) as _row,
               row_number() over (order by t.updated_at asc, t.id asc) as _rn
        from public.%I t
        where t.organization_id = $1
          and (t.branch_id = $2
               or (t.branch_id is null
                   and t.restaurant_id = (select b.restaurant_id from public.branches b where b.id = $2)))
          and ($3 is null or t.updated_at > $3 or (t.updated_at = $3 and t.id > $4))
        order by t.updated_at asc, t.id asc
        limit $5 + 1
      ),
      page as (
        select _id, _uat, _row from look where _rn <= $5
      )
      select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
             (select count(*) from look)::int,
             (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      from page
    $q$, p_table)
    into v_rows, v_count, v_last
    using p_org, p_branch, p_since_updated_at, p_since_id, p_limit;
  else
    -- existing RF-057 operational-table pager, UNCHANGED (strict branch_id = device
    -- branch). The MVP `tables` entity pages HERE: tables.branch_id is NOT NULL.
    execute format($q$
      with look as (
        select t.id as _id, t.updated_at as _uat, to_jsonb(t) as _row,
               row_number() over (order by t.updated_at asc, t.id asc) as _rn
        from public.%I t
        where t.organization_id = $1
          and t.branch_id = $2
          and ($3 is null or t.updated_at > $3 or (t.updated_at = $3 and t.id > $4))
        order by t.updated_at asc, t.id asc
        limit $5 + 1
      ),
      page as (
        select _id, _uat, _row from look where _rn <= $5
      )
      select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
             (select count(*) from look)::int,
             (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      from page
    $q$, p_table)
    into v_rows, v_count, v_last
    using p_org, p_branch, p_since_updated_at, p_since_id, p_limit;
  end if;

  return jsonb_build_object(
    'rows',        v_rows,
    'next_cursor', case when v_count > 0 then v_last else null end,
    'has_more',    (v_count > p_limit));
end;
$$;

comment on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) is
  'RF-057 internal helper for app.sync_pull, extended by RF-109 (menu) and the MVP `tables` floor entity: pages ONE allow-listed table by (updated_at, id). Operational tables (orders/order_items/order_item_modifiers/payments/shifts/cash_drawer_sessions) AND `tables` page within (organization_id, branch_id) — a dining table is strictly branch-scoped (branch_id NOT NULL), letting the KDS map orders.table_id -> a human label offline. The six RF-109 menu tables page within organization_id and (branch_id = device branch OR branch_id null AND restaurant_id = device restaurant). Returns {rows (incl. tombstones via deleted_at), next_cursor, has_more}. PSC-001C: order_service_rounds joins the STRICT-BRANCH operational set (branch_id NOT NULL; money-free rows). Faithful re-creation of the 20260703140000 body. NOT client-facing (no authenticated grant); table name is allow-listed (no injection).';

revoke all on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) from public;

-- ----------------------------------------------------------------------------
-- 2. app.sync_pull — RF-109 body + 'tables' allowed for BOTH the kitchen_staff
--    allow-list (money-free rows; redact_money backstop preserved and harmless)
--    and the price-capable business set.
-- ----------------------------------------------------------------------------
create or replace function app.sync_pull(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_entities       text[]  default null,
  p_cursors        jsonb   default '{}'::jsonb,
  p_limit          integer default 500
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_emp         uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_limit       integer;
  v_allowed     text[];
  v_requested   text[];
  v_include_ops boolean;
  v_entity      text;
  v_cur         jsonb;
  v_c_uat       timestamptz;
  v_c_id        uuid;
  v_changes     jsonb := '{}'::jsonb;
  v_op_rows     jsonb;
  v_op_count    integer;
  v_op_last     jsonb;
  v_op_statuses jsonb;
  c_financial   constant text[] := array['payments', 'shifts', 'cash_drawer_sessions'];
  c_business    constant text[] := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'payments', 'shifts', 'cash_drawer_sessions'];
  -- RF-109: the six menu reference entities. Price-capable roles only (menu rows carry money, T-003).
  c_menu        constant text[] := array['menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options'];
  -- MVP: the money-free floor entity — EVERY device role may pull it (the KDS
  -- maps orders.table_id -> a human table label through this feed).
  c_floor       constant text[] := array['tables'];
begin
  -- (0) limit validation (A7): default 500, reject <=0 or >1000 (validation-error style).
  v_limit := coalesce(p_limit, 500);
  if v_limit <= 0 or v_limit > 1000 then
    raise exception 'sync_pull: p_limit must be between 1 and 1000 (got %)', v_limit using errcode = '42501';
  end if;
  if p_cursors is null or jsonb_typeof(p_cursors) <> 'object' then
    raise exception 'sync_pull: p_cursors must be a JSON object' using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_pull: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_pull: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'sync_pull: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_pull: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'sync_pull: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) role-permitted entities (A5): kitchen_staff -> non-financial operational
  --     + the money-free `tables` floor entity (NO menu -- menu rows carry money,
  --     T-003). Price-capable roles -> operational business + RF-109 menu + tables.
  if v_role = 'kitchen_staff' then
    -- PSC-001C: order_service_rounds is MONEY-FREE by schema — the kitchen
    -- needs it to render Addition/Round N tickets with the round's own status.
    v_allowed := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds'] || c_floor;
  elsif v_role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant') then
    v_allowed := c_business || c_menu || c_floor;
  else
    v_allowed := array[]::text[];
  end if;

  -- (c) resolve the requested set. null -> all role-permitted + operation_statuses.
  --     Otherwise validate each name: unknown -> reject; not-permitted-for-role -> reject.
  if p_entities is null then
    v_requested   := v_allowed;
    v_include_ops := true;
  else
    v_requested   := array[]::text[];
    v_include_ops := false;
    foreach v_entity in array p_entities loop
      if v_entity = 'operation_statuses' then
        v_include_ops := true;
      elsif v_entity = any(c_business) or v_entity = any(c_menu) or v_entity = any(c_floor) then
        if not (v_entity = any(v_allowed)) then
          raise exception 'sync_pull: entity % is not permitted for role %', v_entity, v_role using errcode = '42501';
        end if;
        if not (v_entity = any(v_requested)) then
          v_requested := array_append(v_requested, v_entity);
        end if;
      else
        raise exception 'sync_pull: unknown entity %', v_entity using errcode = '42501';
      end if;
    end loop;
  end if;

  -- (d) page each requested entity by its per-entity (updated_at, id) cursor.
  foreach v_entity in array v_requested loop
    v_cur   := p_cursors -> v_entity;
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    v_changes := v_changes || jsonb_build_object(
      v_entity, app.sync_pull_changes(v_entity, v_org, v_branch, v_c_uat, v_c_id, v_limit));
  end loop;

  -- (d2) KITCHEN MONEY REDACTION (RF-059, A3/T-003): kitchen_staff must receive NO money figure.
  --      Preserved verbatim. (Kitchen never reaches the paging loop for a menu entity -- a menu
  --      request is rejected in (c) -- so this strips money only from the operational rows kitchen
  --      legitimately receives; it remains a defence-in-depth backstop for any *_minor key.
  --      `tables` rows are money-free, so redact_money is a harmless no-op on them.)
  if v_role = 'kitchen_staff' then
    select coalesce(
             jsonb_object_agg(
               ent,
               case when jsonb_typeof(val -> 'rows') = 'array'
                 then jsonb_set(val, '{rows}',
                        coalesce((select jsonb_agg(app.redact_money(r))
                                  from jsonb_array_elements(val -> 'rows') as r), '[]'::jsonb))
                 else val end),
             '{}'::jsonb)
      into v_changes
      from jsonb_each(v_changes) as ec(ent, val);
  end if;

  -- (e) current-device operation-status feed (A4): sync_operations for THIS org + THIS device
  --     only. Projects status/conflict fields; excludes raw payload. Empty when not requested.
  if v_include_ops then
    v_cur   := p_cursors -> 'operation_statuses';
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    with look as (
      select so.id as _id, so.updated_at as _uat,
             jsonb_build_object(
               'id',                 so.id,
               'local_operation_id', so.local_operation_id,
               'operation_type',     so.operation_type,
               'target_entity',      so.target_entity,
               'target_id',          so.target_id,
               'status',             so.status,
               'result',             so.result,
               'last_error_code',    so.last_error_code,
               'last_error_class',   so.last_error_class,
               'conflict_info',      so.conflict_info,
               'rejection_reason',   so.rejection_reason,
               'retry_count',        so.retry_count,
               'updated_at',         so.updated_at,
               'applied_at',         so.applied_at,
               'server_received_at', so.server_received_at) as _row,
             row_number() over (order by so.updated_at asc, so.id asc) as _rn
      from public.sync_operations so
      where so.organization_id = v_org
        and so.device_id = p_device_id
        and (v_c_uat is null or so.updated_at > v_c_uat or (so.updated_at = v_c_uat and so.id > v_c_id))
      order by so.updated_at asc, so.id asc
      limit v_limit + 1
    ),
    page as (
      select _id, _uat, _row from look where _rn <= v_limit
    )
    select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
           (select count(*) from look)::int,
           (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      into v_op_rows, v_op_count, v_op_last
      from page;
    v_op_statuses := jsonb_build_object(
      'rows', v_op_rows,
      'next_cursor', case when v_op_count > 0 then v_op_last else null end,
      'has_more', (v_op_count > v_limit));
  else
    v_op_statuses := jsonb_build_object('rows', '[]'::jsonb, 'next_cursor', null, 'has_more', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'server_ts', now(),
    'changes', v_changes,
    'operation_statuses', v_op_statuses);
end;
$$;

comment on function app.sync_pull(uuid, uuid, text[], jsonb, integer) is
  'RF-057 pull RPC, hardened by RF-059 (A3/T-003), extended by RF-109 (menu) and the MVP `tables` floor entity. Session/device validation (A8), role-permitted entity set (A5), per-entity (updated_at,id) cursor (A1), tombstones inline (A9), limit default 500/cap 1000, current-device operation_statuses feed (A4), RF057-B1 lookahead, and kitchen money redaction are preserved verbatim. RF-109: the six menu entities stay price-capable-roles-only (kitchen 42501 -- menu rows carry money, T-003). MVP: `tables` is pull-allowed for EVERY device role INCLUDING kitchen_staff -- a dining-table row is money-free (label/seats/area/status) and the KDS maps orders.table_id -> a human label through it; the redact_money backstop still passes over kitchen `tables` rows (harmless no-op). Strict branch scope for `tables` (branch_id = device branch). PSC-001C: `order_service_rounds` is pull-allowed for kitchen_staff AND the business roles (a round row is MONEY-FREE by schema — no *_minor column exists — so T-003 is not implicated; the kitchen redact_money backstop passes over it as a no-op); order_items.service_round_id rides the existing generic row projection with no pull change; old clients that never request the entity are unaffected. Faithful re-creation of the 20260703140000 body. Read-only; no audit. Org+branch (and, for menu, restaurant-scoped) filter is the isolation boundary (R-003).';

revoke all on function app.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function app.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 12. Activity Log classifiers — faithful re-creations, additive deltas only:
--     * app.audit_action_has_detail (LATEST owner 20260720110000): the
--       order.items_add% and order.round_status% families become
--       detail-enabled.
--     * app.audit_safe_detail (LATEST owner 20260721090000): TWO new safe
--       scalar keys — round_number, added_item_count. Never money beyond the
--       already-allowlisted *_minor keys, never identifiers (T-003 holds).
--     app.audit_category is NOT touched: `order.%` already classifies every
--     new action into `orders`.
-- ----------------------------------------------------------------------------
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
      or p_action =    'pin_session.failed';
$$;

comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 .. PILOT-OPERATIONS-CORRECTIONS-001 + PSC-001C: is p_action a SUPPORTED action that may carry a safe payload projection? PSC-001C adds the order.items_add% and order.round_status% families (round_number / added_item_count / from_status / to_status safe scalars). Faithful re-creation of the 20260720110000 body. Gates app.audit_safe_detail.';

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
    'round_number','added_item_count'
  ] loop
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
  'ALLOWLIST projection of one audit payload to canonical safe fields + PSC-001D (voided_from_status / device_type / kitchen_ack_required) + PSC-001C (round_number / added_item_count — a position and a line count, never money, never identifiers; T-003 holds). Faithful re-creation of the 20260721090000 body. Every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

-- ----------------------------------------------------------------------------
-- 13. app.pos_order_detail + public.pos_order_detail — the AUTHORITATIVE POS
--     order read: header + every active customer-visible item (with modifiers
--     and round membership) + the round list + the completed payment. The
--     single source for opening an existing order, entering Add items,
--     refreshing after an addition, payment, and the combined itemized receipt
--     — on ANY authorized POS device of the branch (not just the device that
--     placed the order). Wrapper follows the exact pos_order_snapshots
--     convention: SECURITY INVOKER sql pass-through, authenticated-only.
-- ----------------------------------------------------------------------------
create or replace function app.pos_order_detail(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_order_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_device_type text;
  v_order       jsonb;
  v_items       jsonb;
  v_rounds      jsonb;
  v_payment     jsonb;
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (pos_order_snapshots parity):
  --     every structural failure collapses to ONE indistinguishable envelope.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;

  -- (b) POS-class device + price-capable POS role (this read carries money).
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'entity', 'order_detail');
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'order_detail');
  end if;

  -- (c) the order — SESSION org+branch scope only. A nonexistent and a
  --     foreign-scope order collapse to the SAME envelope (no oracle, R-003).
  select jsonb_build_object(
           'order_id',             o.id,
           'order_code',           '#' || upper(right(replace(o.id::text, '-', ''), 6)),
           'order_type',           o.order_type,
           'status',               o.status,
           'revision',             o.revision,
           'table_label',          tbl.label,
           'customer_name',        o.customer_name,
           'currency_code',        o.currency_code,
           'subtotal_minor',       o.subtotal_minor,
           'discount_total_minor', o.discount_total_minor,
           'tax_total_minor',      o.tax_total_minor,
           'grand_total_minor',    o.grand_total_minor,
           'receipt_number',       o.receipt_number,
           'created_at',           o.created_at,
           'updated_at',           o.updated_at)
    into v_order
    from public.orders o
    left join public.tables tbl
      on  tbl.organization_id = o.organization_id
      and tbl.id              = o.table_id
    where o.id              = p_order_id
      and o.organization_id = v_org
      and o.branch_id       = v_branch
      and o.deleted_at is null;
  if v_order is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found', 'entity', 'order_detail');
  end if;

  -- (d) every ACTIVE customer-visible item, with modifiers and round
  --     membership (NULL service_round_id = the original submission).
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_item_id',             oi.id,
           'menu_item_id',              oi.menu_item_id,
           'menu_item_name_snapshot',   oi.menu_item_name_snapshot,
           'quantity',                  oi.quantity,
           'unit_price_minor_snapshot', oi.unit_price_minor_snapshot,
           'line_discount_minor',       oi.line_discount_minor,
           'line_total_minor',          oi.line_total_minor,
           'status',                    oi.status,
           'notes',                     oi.notes,
           'item_size_snapshot',        oi.item_size_snapshot,
           'item_variant_snapshot',     oi.item_variant_snapshot,
           'service_round_id',          oi.service_round_id,
           'round_number',              r.round_number,
           'modifiers',                 coalesce(mods.list, '[]'::jsonb)
         ) order by oi.created_at asc, oi.id asc), '[]'::jsonb)
    into v_items
    from public.order_items oi
    left join public.order_service_rounds r
      on  r.organization_id = oi.organization_id
      and r.id              = oi.service_round_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'modifier_name_snapshot', m.modifier_name_snapshot,
               'option_name_snapshot',   m.option_name_snapshot,
               'price_minor_snapshot',   m.price_minor_snapshot,
               'quantity',               m.quantity
             ) order by m.created_at asc, m.id asc) as list
        from public.order_item_modifiers m
        where m.organization_id = oi.organization_id
          and m.order_item_id   = oi.id
          and m.deleted_at is null
    ) mods on true
    where oi.organization_id = v_org
      and oi.order_id        = p_order_id
      and oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled');

  -- (e) the round list (voided rounds included — status says so).
  select coalesce(jsonb_agg(jsonb_build_object(
           'round_id',     r.id,
           'round_number', r.round_number,
           'status',       r.status,
           'ready_at',     r.ready_at,
           'created_at',   r.created_at
         ) order by r.round_number asc), '[]'::jsonb)
    into v_rounds
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.order_id        = p_order_id
      and r.deleted_at is null;

  -- (f) the (at most one) completed payment — enough for a faithful reprint.
  select jsonb_build_object(
           'method',         p.method,
           'amount_minor',   p.amount_minor,
           'tendered_minor', p.tendered_minor,
           'change_minor',   p.change_minor,
           'receipt_number', p.receipt_number,
           'created_at',     p.created_at)
    into v_payment
    from public.payments p
    where p.organization_id = v_org
      and p.order_id        = p_order_id
      and p.status          = 'completed'
      and p.deleted_at is null
    limit 1;

  return jsonb_build_object(
    'ok', true, 'entity', 'order_detail', 'server_ts', now(),
    'order',   v_order,
    'items',   v_items,
    'rounds',  v_rounds,
    'payment', v_payment);
end;
$$;

comment on function app.pos_order_detail(uuid, uuid, uuid) is
  'PSC-001C: the AUTHORITATIVE branch-scoped POS order read — header (safe #XXXXXX code, type, status, table label, revision, integer-minor totals, receipt number, customer name) + every ACTIVE customer-visible item with modifiers, snapshots and ROUND membership (NULL service_round_id = the original submission) + the round list + the at-most-one completed payment. The single source for opening an existing order, entering Add items, the post-addition refresh, payment, and the combined itemized receipt — including a DIFFERENT authorized POS device of the same branch (cross-device reprint). SCOPE: the PIN session''s OWN org+branch (no parameter names another scope); a nonexistent and a foreign-scope order collapse to the SAME order_not_found envelope (R-003). Requires an active POS-class device (invalid_device_type otherwise) and cashier/manager/restaurant_owner/org_owner (permission_denied otherwise — this read carries money, so kitchen_staff is refused; T-003). NO PINs, tokens, raw payloads, internal staff UUIDs or foreign-branch data. READ-ONLY: mutates nothing, writes no audit.';

create or replace function public.pos_order_detail(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_order_id       uuid
)
  returns jsonb
  language sql
  volatile
  security invoker
  set search_path = ''
as $$
  select app.pos_order_detail(p_pin_session_id, p_device_id, p_order_id);
$$;

comment on function public.pos_order_detail(uuid, uuid, uuid) is
  'PSC-001C: PostgREST wrapper for app.pos_order_detail (the public.pos_order_snapshots pattern: anon key + PIN/device session; SECURITY INVOKER pass-through). Authenticated only.';

revoke all on function app.pos_order_detail(uuid, uuid, uuid) from public;
revoke all on function app.pos_order_detail(uuid, uuid, uuid) from anon;
grant execute on function app.pos_order_detail(uuid, uuid, uuid) to authenticated;
revoke all on function public.pos_order_detail(uuid, uuid, uuid) from public;
revoke all on function public.pos_order_detail(uuid, uuid, uuid) from anon;
grant execute on function public.pos_order_detail(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 14. app.pos_ready_feed + public.pos_ready_feed — the DURABLE DERIVED ready
--     feed (the PSC-001A source). Rows are the write-once ready_at stamps on
--     orders (initial work units) and order_service_rounds (additions) — each
--     work unit appears EXACTLY ONCE per ready occurrence by construction (the
--     stamp is write-once inside the single-shot guarded transitions), and a
--     unit that later serves or voids KEEPS its historical ready occurrence.
--     Deterministic keyset cursor (ready_at, work_unit_type, work_unit_id):
--     two units sharing a ready_at to the microsecond cannot be skipped or
--     duplicated. No cursor -> a bounded 24h first-read window (no banner
--     storms on resume). NO money. NOT audit_events. No banner/read/unread/
--     history UI exists in this phase (PSC-001A owns the client).
-- ----------------------------------------------------------------------------
create or replace function app.pos_ready_feed(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_since_ready_at timestamptz default null,
  p_since_type     text        default null,
  p_since_id       uuid        default null,
  p_limit          integer     default 100
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_device_type text;
  v_limit       integer;
  v_window      timestamptz;
  v_rows        jsonb;
  v_count       integer;
  v_last_at     timestamptz;
  v_last_type   text;
  v_last_id     uuid;
begin
  -- (a) canonical preamble (pos_order_snapshots parity).
  select ps.organization_id, ps.branch_id, ps.device_session_id, ps.resolved_membership_id
    into v_org, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'ready_feed');
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'ready_feed');
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'ready_feed');
  end if;

  -- (b) POS-class device + POS role set (the feed is a POS surface).
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'entity', 'ready_feed');
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'ready_feed');
  end if;

  -- (c) FAIL-CLOSED input validation: the cursor is all-three-or-none, its
  --     type is the closed enum, and the limit is bounded. A malformed cursor
  --     is REFUSED, never coerced into a silent full-window restart.
  if not ((p_since_ready_at is null and p_since_type is null and p_since_id is null)
          or (p_since_ready_at is not null and p_since_type is not null and p_since_id is not null)) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'ready_feed');
  end if;
  if p_since_type is not null and p_since_type not in ('initial_order', 'service_round') then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'ready_feed');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'ready_feed');
  end if;
  v_limit  := p_limit;
  -- The bounded FIRST-READ window: a device with no cursor gets the last 24h
  -- only (no storm of ancient events); with a cursor the keyset bounds it.
  v_window := case when p_since_ready_at is null then now() - interval '24 hours' else null end;

  -- (d) the DERIVED feed: initial work units (orders.ready_at) UNION additional
  --     rounds (order_service_rounds.ready_at), branch-scoped, keyset-paged on
  --     (ready_at, work_unit_type, work_unit_id) ascending. NO money column is
  --     projected anywhere.
  with feed as (
    select 'initial_order'::text as work_unit_type,
           o.id                  as work_unit_id,
           o.id                  as order_id,
           '#' || upper(right(replace(o.id::text, '-', ''), 6)) as order_code,
           null::integer         as round_number,
           o.order_type,
           tbl.label             as table_label,
           o.ready_at,
           o.status              as work_unit_status,
           o.status              as parent_order_status,
           o.revision
      from public.orders o
      left join public.tables tbl
        on  tbl.organization_id = o.organization_id
        and tbl.id              = o.table_id
      where o.organization_id = v_org
        and o.branch_id       = v_branch
        and o.deleted_at is null
        and o.ready_at is not null
    union all
    select 'service_round'::text as work_unit_type,
           r.id                  as work_unit_id,
           r.order_id,
           '#' || upper(right(replace(r.order_id::text, '-', ''), 6)) as order_code,
           r.round_number,
           o.order_type,
           tbl.label             as table_label,
           r.ready_at,
           r.status              as work_unit_status,
           o.status              as parent_order_status,
           r.revision
      from public.order_service_rounds r
      join public.orders o
        on  o.organization_id = r.organization_id
        and o.id              = r.order_id
      left join public.tables tbl
        on  tbl.organization_id = o.organization_id
        and tbl.id              = o.table_id
      where r.organization_id = v_org
        and r.branch_id       = v_branch
        and r.deleted_at is null
        and r.ready_at is not null
  ),
  page as (
    select *
      from feed f
      where (v_window is null or f.ready_at >= v_window)
        and (p_since_ready_at is null
             or (f.ready_at, f.work_unit_type, f.work_unit_id)
                > (p_since_ready_at, p_since_type, p_since_id))
      order by f.ready_at asc, f.work_unit_type asc, f.work_unit_id asc
      limit v_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'work_unit_type',      p.work_unit_type,
           'work_unit_id',        p.work_unit_id,
           'order_id',            p.order_id,
           'order_code',          p.order_code,
           'round_number',        p.round_number,
           'order_type',          p.order_type,
           'table_label',         p.table_label,
           'ready_at',            p.ready_at,
           'work_unit_status',    p.work_unit_status,
           'parent_order_status', p.parent_order_status,
           'revision',            p.revision
         ) order by p.ready_at asc, p.work_unit_type asc, p.work_unit_id asc), '[]'::jsonb),
         count(*)::integer,
         (array_agg(p.ready_at       order by p.ready_at desc, p.work_unit_type desc, p.work_unit_id desc))[1],
         (array_agg(p.work_unit_type order by p.ready_at desc, p.work_unit_type desc, p.work_unit_id desc))[1],
         (array_agg(p.work_unit_id   order by p.ready_at desc, p.work_unit_type desc, p.work_unit_id desc))[1]
    into v_rows, v_count, v_last_at, v_last_type, v_last_id
    from page p;

  return jsonb_build_object(
    'ok', true, 'entity', 'ready_feed', 'server_ts', now(),
    'ready',       v_rows,
    'has_more',    (v_count = v_limit),
    'next_cursor', case when v_count > 0
                        then jsonb_build_object('ready_at', v_last_at, 'work_unit_type', v_last_type, 'id', v_last_id)
                        else null end);
end;
$$;

comment on function app.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) is
  'PSC-001C: the DURABLE DERIVED ready feed — the PSC-001A backend source. Rows are the WRITE-ONCE ready_at stamps on orders (work_unit_type=initial_order) and order_service_rounds (work_unit_type=service_round), branch-scoped from the PIN session (no parameter names another scope). Each work unit appears EXACTLY ONCE per ready occurrence by construction (the stamp is write-once inside the single-shot guarded transitions — idempotent replays, repeated ready requests, racing devices and pull reconnects cannot duplicate it), and a unit that later becomes served or voided KEEPS its historical ready occurrence (current work_unit_status + parent_order_status are exposed alongside). Deterministic keyset pagination on (ready_at, work_unit_type, work_unit_id) — two units sharing a ready_at cannot be skipped or duplicated; the cursor is all-three-or-none and FAIL-CLOSED validated. No cursor -> a bounded 24h first-read window (no banner storms for old events). Limit default 100, cap 500. Requires an active POS-class device + cashier/manager/restaurant_owner/org_owner. Returns NO money field. NOT derived from audit_events. READ-ONLY: mutates nothing, writes no audit. PSC-001A consumes this via ~7s foreground polling + resume refresh and owns all local read/history state — no banner/bell/read-state/sound exists in this phase.';

create or replace function public.pos_ready_feed(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_since_ready_at timestamptz default null,
  p_since_type     text        default null,
  p_since_id       uuid        default null,
  p_limit          integer     default 100
)
  returns jsonb
  language sql
  volatile
  security invoker
  set search_path = ''
as $$
  select app.pos_ready_feed(p_pin_session_id, p_device_id, p_since_ready_at,
                            p_since_type, p_since_id, p_limit);
$$;

comment on function public.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) is
  'PSC-001C: PostgREST wrapper for app.pos_ready_feed (the public.pos_order_snapshots pattern: anon key + PIN/device session; SECURITY INVOKER pass-through). Authenticated only.';

revoke all on function app.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) from public;
revoke all on function app.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) from anon;
grant execute on function app.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) to authenticated;
revoke all on function public.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) from public;
revoke all on function public.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) from anon;
grant execute on function public.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   restore app.sync_push + app.void_order + app.audit_safe_detail from
--   20260721090000; app.try_auto_complete_order +
--   app.apply_order_status_transition from 20260714090000; app.sync_pull +
--   app.sync_pull_changes from 20260703140000; app.audit_action_has_detail
--   from 20260720110000; restore sync_operations_operation_type_check without
--   the two new operations; then:
--   drop function if exists public.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer);
--   drop function if exists app.pos_ready_feed(uuid, uuid, timestamptz, text, uuid, integer);
--   drop function if exists public.pos_order_detail(uuid, uuid, uuid);
--   drop function if exists app.pos_order_detail(uuid, uuid, uuid);
--   drop function if exists app.update_round_status(uuid, uuid, uuid, text, text);
--   drop function if exists app.add_order_items(uuid, uuid, uuid, text, jsonb, timestamptz);
--   drop function if exists app.order_rounds_all_served(uuid, uuid);
--   alter table public.order_items drop constraint order_items_service_round_fkey;
--   alter table public.order_items drop column service_round_id;
--   drop table public.order_service_rounds;
--   alter table public.orders drop constraint orders_ready_at_check;
--   alter table public.orders drop column ready_at;
-- ROLLBACK NOTE: orders completed under the round predicate STAY completed
-- (terminal, D-024); ready_at data is lost on rollback (acceptable — the feed
-- is additive and PSC-001A has not shipped).
-- ============================================================================
