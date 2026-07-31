-- ============================================================================
-- MONEY-PRICING-FORMULA-002A - configured-unit line totals + pricing-epoch-safe
--                              discount base.
-- ============================================================================
-- Corrects Codex Blocker 1. A cart line is N identical FULLY CONFIGURED items,
-- so a modifier surcharge belongs to the PER-UNIT price and must be charged
-- once per item unit:
--
--     line_total = quantity * (unit_price_minor + SUM(delta * modifier_qty))
--                  - line_discount_minor
--
-- This is the authoritative contract in docs/MONEY_AND_TAX_SPEC.md Â§9:157,
-- whose worked example Â§9.1:179 reads "Line A per-unit = 4500 + 700 = 5200;
-- x 2 = 10400", and Â§9:155 requires the server RPC and every offline client to
-- follow it IDENTICALLY. The shipped functions computed
-- `quantity * unit + SUM(...)` - the surcharge added once per LINE - which
-- under-charged every additional unit while the kitchen already multiplied meat
-- and prep by the item quantity, cooking N upgraded meals for one upgrade's
-- money. The two rules agree at quantity 1, which is why it survived.
--
-- THREE functions are re-emitted, byte-faithfully except for the arithmetic:
--   1. app.submit_order     (latest body: 20260725090000_kitchen_mode_001c1_dispatch_ledger.sql)
--   2. app.add_order_items  (latest body: 20260804090000_deferred_order_amendments_001_takeaway_and_mode_close.sql)
--   3. app.apply_discount   (latest body: 20260717090000_full_comp_permission_001_staff_capability.sql)
--
-- HISTORICAL MONEY IS NOT TOUCHED. This migration performs NO backfill, NO
-- UPDATE of existing rows and NO re-derivation of stored totals. Orders already
-- stored under the old rule keep their stored line totals and subtotal forever;
-- the new rule applies only to lines inserted by a submission or an amendment
-- AFTER this migration is applied. A pre-existing order that later receives a
-- new round is therefore legitimately MIXED - its old lines keep the old
-- amounts and only the new round uses the corrected rule - because
-- add_order_items adds a DELTA to the order's stored subtotal
-- (v_new_sub := v_o_sub + v_delta) and never recomputes existing lines.
--
-- WHY app.apply_discount IS HERE. Its item-level branch was the ONLY other place
-- that re-derived a stored line total from its components
-- (`v_base := v_qty * v_unit + v_mod_sum`) and wrote the result back to
-- order_items.line_total_minor. Left alone it would have silently destroyed the
-- per-unit surcharge on every newly-priced line the moment a cashier applied an
-- item discount or a full comp; taught the new rule it would instead have
-- repriced historical lines upward. It now recovers the pre-discount base from
-- the stored authoritative row - line_total_minor + line_discount_minor - which
-- is correct for EITHER pricing epoch and needs no epoch marker. No column was
-- added and no row was rewritten.
--
-- Everything else is preserved verbatim: signatures, argument names/defaults,
-- return types, language, SECURITY DEFINER, `set search_path = ''`, grants and
-- revokes (untouched - CREATE OR REPLACE preserves ACLs), locking, ownership and
-- membership checks, staff capability + full-comp gates, discount clamps,
-- negative-total refusals, the client subtotal-mismatch error, idempotency and
-- operation identity, audit writes, sync/outbox semantics, modifier snapshots,
-- amendment round behaviour, terminal-state rules and KDS/printer dispatch.
-- Existing COMMENT ON FUNCTION text is intentionally left in place: CREATE OR
-- REPLACE preserves it, and re-typing several-thousand-character comments would
-- risk transcription drift for no behavioural gain.
--
-- No catalogue re-pricing is introduced. Submitted price snapshots remain
-- trusted under D-008.
-- ============================================================================
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

    v_line_total := v_qty * (v_unit + v_mod_sum) - v_line_disc;
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
    v_line_total := v_qty * (v_unit + v_mod_sum) - v_line_disc;

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
  -- KITCHEN-MODE-001C1: the ONE mode read for the whole tail (hoisted above
  -- the zero-total gate so the dispatch block below can share it).
  -- CORRECTION-001: FAIL CLOSED — the session liveness chain already proved
  -- this branch live at ingest, so a missing/tombstoned branch row HERE is a
  -- state inconsistency inside the very transaction that just wrote the
  -- order; silently treating it as kds-mode could accept a printer-only
  -- order WITHOUT its kitchen ticket. Raise and roll everything back.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id              = v_branch
      and b.organization_id = v_org
      and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'submit_order: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;

  -- KITCHEN-MODE-001C1 (DORMANT): EVERY accepted printer-only order gets its
  -- durable, idempotent, money-free kitchen dispatch IN THIS SAME TRANSACTION.
  -- A dispatch failure fails the submit (an accepted printer-only order may
  -- never silently miss its kitchen ticket) and a rolled-back submit leaves
  -- no dispatch. kds branches create NOTHING — byte-identical behavior.
  if v_kitchen_mode = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'initial_order',
      app.kitchen_dispatch_payload_initial(v_org, p_order_id),
      v_emp, v_membership, p_device_id);
  end if;

  if v_grand = 0 then
    if v_kitchen_mode = 'printer_only' then
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

    v_line_total := v_qty * (v_unit + v_mod_sum);
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
  if v_o_type not in ('dine_in', 'takeaway') then
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
    v_line_total := v_qty * (v_unit + v_mod_sum);

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
  -- CORRECTION-001: a missing branch row here is a state inconsistency (the
  -- liveness chain proved it live at ingest) — never a silent kds fallback.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'add_order_items: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;
  if v_kitchen_mode = 'printer_only' then
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

create or replace function app.apply_discount(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_scope              text,     -- 'order' | 'order_item'
  p_order_item_id      uuid,     -- required when p_scope = 'order_item'
  p_discount_type      text,     -- 'fixed' | 'percentage'
  p_value              bigint,   -- fixed: amount_minor ; percentage: basis points (0..10000)
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
  v_subtotal     bigint;
  v_discount     bigint;
  v_tax          bigint;
  v_qty          integer;
  v_unit         bigint;
  v_mod_sum      bigint;
  v_base         bigint;
  v_disc_amount  bigint;
  v_new_subtotal bigint;
  v_new_grand    bigint;
  v_new_rev      integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
  -- FULL-COMP-PERMISSION-001
  v_may_comp     boolean;   -- the EFFECTIVE right to make an order FREE
  v_other_lines  bigint;    -- sum of the OTHER live lines (prospective rollup)
  v_old_line_disc bigint;
  v_line_total_stored bigint;   -- MONEY-PRICING-FORMULA-002A
  v_new_line_total bigint;
begin
  -- (a) PIN session + backing + actor/scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'apply_discount: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'apply_discount: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'apply_discount: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'apply_discount: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'apply_discount: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load order; it MUST be in the actor's org + branch (no cross-tenant)
  --     MONEY-SETTLEMENT-CONSISTENCY-001: FOR UPDATE. apply_discount previously took NO
  --     row lock, so the completed-payment freeze below would have raced record_payment
  --     (which could commit a payment between the guard's read and the discount's write,
  --     leaving a paid order under-covered). `orders` is the FIRST lock every mutating
  --     path takes (record_payment: orders -> shifts -> drawer -> receipt counter;
  --     void_order: orders; apply_order_status_transition: orders), and apply_discount
  --     takes no other lock — so this adds NO new lock-order edge and cannot deadlock.
  select o.organization_id, o.branch_id, o.status, o.revision,
         o.subtotal_minor, o.discount_total_minor, o.tax_total_minor
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_subtotal, v_discount, v_tax
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'apply_discount: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'apply_discount: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A6) — BEFORE the idempotency replay (RF053-B1) so an
  --     unauthorized actor can never replay a prior SUCCESS. A DENIAL is audited
  --     (order.discount_denied) + RETURNED (no raise, so the audit persists) with NO
  --     state change and NO ledger write (the ledger holds only authorized successes;
  --     denials are re-audited as probe attempts, never replayed).
  if not ((v_role in ('manager', 'restaurant_owner', 'org_owner'))
          or app.cashier_capability_allowed(v_role, v_m_perms, 'apply_discount')) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                         'role', v_role, 'scope', p_scope, 'discount_type', p_discount_type, 'value', p_value));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) input validation (operation shape; independent of mutable post-success state)
  if p_scope not in ('order', 'order_item') then
    raise exception 'apply_discount: invalid scope %', p_scope using errcode = '42501';
  end if;
  if p_discount_type not in ('fixed', 'percentage') then
    raise exception 'apply_discount: invalid discount_type %', p_discount_type using errcode = '42501';
  end if;
  if p_value is null or p_value < 0 then
    raise exception 'apply_discount: value must be a non-negative integer' using errcode = '42501';
  end if;
  if p_discount_type = 'percentage' and p_value > 10000 then
    raise exception 'apply_discount: percentage basis points must be 0..10000' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'apply_discount: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + input validation,
  --     ORDER-BOUND. Same (org, device, local_operation_id, action) on a DIFFERENT
  --     order is a conflict, not a replay (never leaks the original order's result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'apply_discount';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'apply_discount: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) order must be non-terminal; optimistic concurrency
  if v_o_status in ('voided', 'cancelled', 'completed') then
    raise exception 'apply_discount: order status % is terminal; cannot discount', v_o_status using errcode = '42501';
  end if;
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'apply_discount: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (f2) MONEY-SETTLEMENT-CONSISTENCY-001 — THE FINANCIAL SNAPSHOT FREEZES AT PAYMENT.
  --      Once an order carries a LIVE COMPLETED payment, NO discount mutation is allowed,
  --      in EITHER direction. Raising the total obviously breaks settlement (it re-bases
  --      grand_total_minor above the frozen payments.amount_minor and silently un-settles
  --      a paid order). LOWERING it is refused too, by human decision: the customer has
  --      already been charged, so a post-payment price change is a REFUND — and there is
  --      no refund flow in MVP (D-023: a completed payment is TERMINAL). Quietly shrinking
  --      the total would leave the books claiming the guest overpaid, with no money moved
  --      and no reversal recorded. The snapshot is FROZEN, not merely protected.
  --
  --      THE MARKER IS THE RIGHT TEST HERE (not app.order_is_fully_settled): the question
  --      is "has this order been CHARGED yet?", not "does it still owe money?". A
  --      NON-CHARGEABLE zero-total order carries no payment and stays freely discountable
  --      (a comp can still be corrected); an UNDER-COVERED order carries a real payment
  --      and is frozen. This is byte-for-byte the guard app.void_order already uses
  --      (RF-062), so "an order that has been paid" has ONE meaning across the tree.
  --
  --      The order row is locked FOR UPDATE above, and record_payment locks it first too,
  --      so a payment cannot commit between this check and the write below.
  --      RETURNS (never RAISES): a raise would roll back the audit row. NO state change,
  --      NO revision bump, NO order/payment/receipt write, and NO order_operations ledger
  --      entry (the ledger holds only authorized successes; a denial is re-audited as a
  --      probe attempt on every retry, never replayed).
  if exists (
    select 1
    from public.payments p
    where p.organization_id = v_org
      and p.order_id        = p_order_id
      and p.status          = 'completed'
      and p.deleted_at is null
  ) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'scope', p_scope,
                         'discount_type', p_discount_type, 'value', p_value,
                         'denied_reason', 'order_has_completed_payment'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'detail', 'order_has_completed_payment', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  v_new_rev := v_o_rev + 1;

  -- FULL-COMP-PERMISSION-001 -- THE EFFECTIVE RIGHT TO MAKE AN ORDER FREE.
  -- Resolved ONCE, from the SERVER's own membership row (v_m_perms), never from
  -- anything the client sent. Manager/restaurant_owner/org_owner hold it BY ROLE;
  -- a cashier holds it ONLY via an EXPLICIT, default-OFF grant
  -- (app.cashier_capability_granted -- presence of the canonical JSON string
  -- "true"). This NEVER bypasses the general discount permission: gate (c) above
  -- already refused any actor lacking `apply_discount`, so a cashier granted
  -- full-comp but DENIED ordinary discounts never reaches this line.
  v_may_comp := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                or app.cashier_capability_granted(v_role, v_m_perms, 'apply_full_comp');

  if p_scope = 'order' then
    -- order-level: base = current subtotal; clamp discount <= subtotal
    v_base := v_subtotal;
    if p_discount_type = 'percentage' then
      v_disc_amount := round(v_base::numeric * p_value / 10000)::bigint;   -- numeric is exact (not float); half-away-from-zero
    else
      v_disc_amount := p_value;
    end if;
    if v_disc_amount > v_base then v_disc_amount := v_base; end if;          -- clamp >= 0 (D-007/§4.4)
    v_new_grand := v_subtotal - v_disc_amount + v_tax;

    -- FULL-COMP-PERMISSION-001 -- THE GATE IS THE RESULTING AUTHORITATIVE TOTAL.
    -- A "full comp" is DEFINED as: this mutation would leave grand_total_minor
    -- EXACTLY 0. It is NOT inferred from a UI "100%" choice, from p_discount_type,
    -- or from a client flag -- the server computes the prospective total from its
    -- OWN snapshots and tests THAT. So a `fixed` discount that happens to cover the
    -- whole order is caught identically to a 10000-bp `percentage` one, and a
    -- percentage that merely zeroes the SUBTOTAL of a TAXED order (leaving
    -- grand = tax > 0) is NOT a comp -- the guest still owes money.
    -- Refusal RETURNS (never raises): a raise would roll back the audit row, and
    -- app.sync_push rebuilds a RAISEd envelope and collapses `error` to the literal
    -- 'rejected', destroying the domain code the POS needs.
    if v_new_grand < 0 then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'denied_reason', 'discount_exceeds_order_total'));
      return jsonb_build_object('ok', false, 'error', 'invalid_discount',
                                'detail', 'discount_exceeds_order_total', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    if v_new_grand = 0 and not v_may_comp then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'resulting_charge_state', 'not_chargeable',
                           'denied_reason', 'full_comp_permission_required'));
      return jsonb_build_object('ok', false, 'error', 'permission_denied',
                                'detail', 'full_comp_permission_required', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    update public.orders
      set discount_total_minor = v_disc_amount, grand_total_minor = v_new_grand, revision = v_new_rev
      where id = p_order_id;

    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_applied', p_reason,
      jsonb_build_object('scope', 'order', 'revision', v_o_rev, 'discount_total_minor', v_discount, 'grand_total_minor', v_subtotal - v_discount + v_tax),
      jsonb_build_object('scope', 'order', 'discount_type', p_discount_type, 'value', p_value, 'revision', v_new_rev,
                         'discount_total_minor', v_disc_amount, 'grand_total_minor', v_new_grand, 'resolved_membership_id', v_membership));
    v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'revision', v_new_rev,
                                   'discount_total_minor', v_disc_amount, 'grand_total_minor', v_new_grand);
  else
    -- item-level: base = qty*unit + sum(modifier price*qty); clamp; recompute order rollup
    select oi.quantity, oi.unit_price_minor_snapshot, oi.line_discount_minor, oi.line_total_minor
      into v_qty, v_unit, v_old_line_disc, v_line_total_stored
      from public.order_items oi
      where oi.id = p_order_item_id and oi.order_id = p_order_id and oi.organization_id = v_org
        and oi.status not in ('voided', 'cancelled');
    if not found then
      raise exception 'apply_discount: order_item not found in order (or already voided/cancelled)' using errcode = '42501';
    end if;
    -- MONEY-PRICING-FORMULA-002A -- FORMULA-AGNOSTIC PRE-DISCOUNT BASE.
    -- This used to recompute the base from the stored components as
    -- `v_qty * v_unit + v_mod_sum`, i.e. a SECOND copy of the line-total rule.
    -- That copy silently picked ONE pricing epoch: after submit_order/
    -- add_order_items moved to `qty * (unit + mod_sum)`, discounting a NEW line
    -- would have rewritten it back to the old, lower amount and destroyed the
    -- per-unit surcharge -- while teaching it the NEW rule would instead have
    -- repriced HISTORICAL lines upward. Both are money corruption.
    --
    -- The stored row already answers the question exactly, for either epoch:
    --     line_total_minor = <pre-discount line value> - line_discount_minor
    -- so the original pre-discount value is recoverable by adding the CURRENT
    -- stored discount back. It is read in the SAME authoritative row read above
    -- (the order row is already locked FOR UPDATE), never re-derived from
    -- modifier rows and never from the live catalogue. Do not reintroduce a
    -- component recomputation here.
    v_base := v_line_total_stored + v_old_line_disc;
    if p_discount_type = 'percentage' then
      v_disc_amount := round(v_base::numeric * p_value / 10000)::bigint;
    else
      v_disc_amount := p_value;
    end if;
    if v_disc_amount > v_base then v_disc_amount := v_base; end if;
    v_new_line_total := v_base - v_disc_amount;

    -- FULL-COMP-PERMISSION-001 -- THE PROSPECTIVE ORDER TOTAL, COMPUTED BEFORE ANY
    -- WRITE. The old code updated order_items FIRST and only then learned the new
    -- grand total, so an item-scope gate could not refuse without leaving a partial
    -- write behind (a RETURN does not unwind it -- only a RAISE would, and a RAISE
    -- would roll back the denial audit AND lose the domain code through sync_push).
    -- So the rollup is now computed from the OTHER live lines plus THIS line's
    -- prospective total, with nothing written yet.
    select coalesce(sum(oi.line_total_minor), 0) into v_other_lines
      from public.order_items oi
      where oi.order_id = p_order_id and oi.organization_id = v_org
        and oi.id <> p_order_item_id
        and oi.status not in ('voided', 'cancelled');
    v_new_subtotal := v_other_lines + v_new_line_total;
    v_new_grand    := v_new_subtotal - v_discount + v_tax;

    -- A NEGATIVE prospective total is REFUSED, never floored. The old code silently
    -- clamped it to 0 -- which MANUFACTURED A FREE ORDER that neither gate ever saw
    -- (the pre-existing order-level v_discount is not re-clamped against a shrunken
    -- subtotal). Failing closed here removes that bypass. D-007: money stays a
    -- non-negative integer.
    if v_new_grand < 0 then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id, 'order_item_id', p_order_item_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'denied_reason', 'discount_exceeds_order_total'));
      return jsonb_build_object('ok', false, 'error', 'invalid_discount',
                                'detail', 'discount_exceeds_order_total', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    -- The SAME resulting-total rule as the order scope: zeroing ONE line of a
    -- multi-line order is an ordinary discount (the order still owes money); it is a
    -- COMP only when the ORDER's grand total lands on exactly 0.
    if v_new_grand = 0 and not v_may_comp then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id, 'order_item_id', p_order_item_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'resulting_charge_state', 'not_chargeable',
                           'denied_reason', 'full_comp_permission_required'));
      return jsonb_build_object('ok', false, 'error', 'permission_denied',
                                'detail', 'full_comp_permission_required', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;

    update public.order_items
      set line_discount_minor = v_disc_amount, line_total_minor = v_new_line_total
      where id = p_order_item_id;
    update public.orders
      set subtotal_minor = v_new_subtotal, grand_total_minor = v_new_grand, revision = v_new_rev
      where id = p_order_id;

    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_applied', p_reason,
      jsonb_build_object('scope', 'order_item', 'order_item_id', p_order_item_id, 'revision', v_o_rev,
                         'line_discount_minor', v_old_line_disc, 'subtotal_minor', v_subtotal, 'grand_total_minor', v_subtotal - v_discount + v_tax),
      jsonb_build_object('scope', 'order_item', 'order_item_id', p_order_item_id, 'discount_type', p_discount_type, 'value', p_value, 'revision', v_new_rev,
                         'line_discount_minor', v_disc_amount, 'line_total_minor', v_new_line_total,
                         'subtotal_minor', v_new_subtotal, 'grand_total_minor', v_new_grand, 'resolved_membership_id', v_membership));
    v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'revision', v_new_rev,
                                   'order_item_id', p_order_item_id, 'line_discount_minor', v_disc_amount,
                                   'subtotal_minor', v_new_subtotal, 'grand_total_minor', v_new_grand);
  end if;

  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'apply_discount', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;
