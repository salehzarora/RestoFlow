-- ============================================================================
-- MONEY-SERVER-MODIFIER-SCOPE-003D — modifier option identity + ownership
-- ============================================================================
-- Forward-only. Re-creates app.submit_order and app.add_order_items from their
-- 20260805090000 (MONEY-PRICING-FORMULA-002A) bodies, byte-faithful except for
-- ONE added validation block in each. app.apply_discount is NOT re-emitted.
--
-- THE DEFECT. `public.order_item_modifiers.modifier_option_id` is a deliberately
-- NON-FK column ("no backend modifier table; A1", RF-052). Both RPCs validated
-- the arithmetic and the snapshot shape but never checked that the named option
-- exists, belongs to this organization, or belongs to the item it was submitted
-- under. A modified authenticated client could submit a structurally valid,
-- arithmetically consistent modifier snapshot for an option belonging to another
-- item or another tenant -- declaring its own price for it.
--
-- THE FIX IS IDENTITY AND OWNERSHIP ONLY. For each submitted modifier the chain
--     modifier_options.id -> modifiers.id -> modifiers.menu_item_id
-- must resolve to the SAME menu_item_id the line was submitted under, within the
-- session-derived organization. Nothing is repriced, renamed, or re-validated
-- against the live catalogue.
--
-- SOFT-DELETED AND INACTIVE ROWS STILL VALIDATE, deliberately. The predicate
-- touches only id / organization_id / modifier_id / menu_item_id -- never
-- is_active, never deleted_at, never price_delta_minor. `app.menu_soft_delete`
-- tombstones exactly one row without cascading, and `app.pos_menu` ships only
-- fully-live options, so an offline cart can legitimately name an option that
-- has since been deactivated or tombstoned (or whose group or item has). D-008
-- offline snapshot trust is preserved intact; a legitimate integer zero delta
-- remains legitimate.
--
-- ATOMIC BY CONSTRUCTION. The check sits with the existing item_unavailable
-- gate, BEFORE any insert, and returns the same typed {ok:false} shape. A
-- refusal therefore leaves no order, no order_items, no order_item_modifiers, no
-- service round, no kitchen dispatch and no partial subtotal.
--
-- ONE uniform code, `modifier_option_not_in_scope`, covers nonexistent,
-- foreign-organization, wrong-item and broken-chain alike, so the refusal cannot
-- be used as an existence oracle for another tenant's ids (R-003). The echoed
-- detail is the client's own payload snapshot, never database content.
--
-- UNCHANGED: signatures, defaults, return types, SECURITY DEFINER, search_path
-- ='' , grants/revokes (preserved by CREATE OR REPLACE), authorization, scope
-- and state checks, row locking, idempotency and fingerprints, subtotal/grand
-- total validation, MONEY-PRICING-FORMULA-002A formula B, snapshot trust, audit
-- behaviour, service rounds, kitchen dispatch and printer_only handling.
--
-- WIRE: unchanged. The predicate uses order_items[].menu_item_id, which the
-- payload already carries. No modifier_group_id is added, no field is added, no
-- fingerprint input changes -- queued offline payloads stay byte-compatible.
--
-- KNOWN, ACCEPTED NARROWING: app.menu_upsert_modifier may re-point a group's
-- menu_item_id and app.menu_upsert_modifier_option may re-point an option's
-- modifier_id. Re-parenting a group to a different product while an offline cart
-- holding the old pairing is still queued would refuse that order. It is a rare,
-- deliberate menu action, it fails CLOSED, and no silent mispricing results.
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
  v_bad_modifiers jsonb;   -- 003D: out-of-scope modifier options
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

  -- MONEY-SERVER-MODIFIER-SCOPE-003D — MODIFIER OPTION IDENTITY + OWNERSHIP.
  --
  -- `order_item_modifiers.modifier_option_id` is a deliberately NON-FK column
  -- (RF-052 A1), and nothing else checked it: every earlier build accepted any
  -- syntactically valid uuid. A modified authenticated client could therefore
  -- submit a structurally perfect, arithmetically consistent snapshot naming an
  -- option that belongs to a DIFFERENT item, a DIFFERENT organization, or to no
  -- row at all -- and pay whatever price it chose to declare for it.
  --
  -- This proves IDENTITY AND OWNERSHIP ONLY:
  --     option -> its modifier group -> that group's menu_item_id
  -- must resolve to the SAME line item, inside the session's own organization
  -- (v_org is derived from the PIN session, never from the payload).
  --
  -- IT DELIBERATELY DOES NOT FILTER is_active OR deleted_at, at any level of the
  -- chain. `app.menu_soft_delete` tombstones exactly ONE row and does not
  -- cascade, and `app.pos_menu` only ever ships fully-live options -- so a cart
  -- captured offline can legitimately name an option that has since been
  -- deactivated or tombstoned, or whose group or item has. Refusing those would
  -- destroy real orders to punish a menu edit. D-008 is untouched: nothing here
  -- reads a price, a name, or a selection rule, and nothing is repriced. A
  -- legitimate zero delta stays legitimate.
  --
  -- Placed BEFORE any insert (the same position as the item_unavailable gate
  -- above) so a refusal is atomic by construction: no order, no items, no
  -- modifiers, no round, no kitchen work, no partial subtotal.
  --
  -- ONE uniform code for all four failures -- nonexistent, foreign-org,
  -- wrong-item, broken chain -- so the refusal is not an existence oracle
  -- (R-003). The echo carries the CLIENT'S OWN payload snapshot only, never DB
  -- data: it tells the cashier which line to fix without confirming whether
  -- some other tenant's uuid is real.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'option_name_snapshot')
    into v_bad_modifiers
    from (
      select distinct jsonb_build_object(
               'menu_item_id',        e ->> 'menu_item_id',
               'option_name_snapshot', m ->> 'option_name_snapshot') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
       where (m ->> 'modifier_option_id') is not null
         and not exists (
           select 1
             from public.modifier_options mo
             join public.modifiers mg
               on  mg.organization_id = mo.organization_id
               and mg.id              = mo.modifier_id
            where mo.organization_id = v_org
              and mo.id              = (m ->> 'modifier_option_id')::uuid
              and mg.menu_item_id    = (e ->> 'menu_item_id')::uuid
         )
    ) offenders;
  if v_bad_modifiers is not null then
    return jsonb_build_object('ok', false, 'error', 'modifier_option_not_in_scope',
                              'entity', 'order', 'modifiers', v_bad_modifiers);
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
  v_bad_modifiers jsonb;   -- 003D: out-of-scope modifier options
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

  -- MONEY-SERVER-MODIFIER-SCOPE-003D — MODIFIER OPTION IDENTITY + OWNERSHIP.
  --
  -- `order_item_modifiers.modifier_option_id` is a deliberately NON-FK column
  -- (RF-052 A1), and nothing else checked it: every earlier build accepted any
  -- syntactically valid uuid. A modified authenticated client could therefore
  -- submit a structurally perfect, arithmetically consistent snapshot naming an
  -- option that belongs to a DIFFERENT item, a DIFFERENT organization, or to no
  -- row at all -- and pay whatever price it chose to declare for it.
  --
  -- This proves IDENTITY AND OWNERSHIP ONLY:
  --     option -> its modifier group -> that group's menu_item_id
  -- must resolve to the SAME line item, inside the session's own organization
  -- (v_org is derived from the PIN session, never from the payload).
  --
  -- IT DELIBERATELY DOES NOT FILTER is_active OR deleted_at, at any level of the
  -- chain. `app.menu_soft_delete` tombstones exactly ONE row and does not
  -- cascade, and `app.pos_menu` only ever ships fully-live options -- so a cart
  -- captured offline can legitimately name an option that has since been
  -- deactivated or tombstoned, or whose group or item has. Refusing those would
  -- destroy real orders to punish a menu edit. D-008 is untouched: nothing here
  -- reads a price, a name, or a selection rule, and nothing is repriced. A
  -- legitimate zero delta stays legitimate.
  --
  -- Placed BEFORE any insert (the same position as the item_unavailable gate
  -- above) so a refusal is atomic by construction: no order, no items, no
  -- modifiers, no round, no kitchen work, no partial subtotal.
  --
  -- ONE uniform code for all four failures -- nonexistent, foreign-org,
  -- wrong-item, broken chain -- so the refusal is not an existence oracle
  -- (R-003). The echo carries the CLIENT'S OWN payload snapshot only, never DB
  -- data: it tells the cashier which line to fix without confirming whether
  -- some other tenant's uuid is real.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'option_name_snapshot')
    into v_bad_modifiers
    from (
      select distinct jsonb_build_object(
               'menu_item_id',        e ->> 'menu_item_id',
               'option_name_snapshot', m ->> 'option_name_snapshot') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
       where (m ->> 'modifier_option_id') is not null
         and not exists (
           select 1
             from public.modifier_options mo
             join public.modifiers mg
               on  mg.organization_id = mo.organization_id
               and mg.id              = mo.modifier_id
            where mo.organization_id = v_org
              and mo.id              = (m ->> 'modifier_option_id')::uuid
              and mg.menu_item_id    = (e ->> 'menu_item_id')::uuid
         )
    ) offenders;
  if v_bad_modifiers is not null then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.items_add_denied', null, null,
            jsonb_build_object('attempted_action', 'add_order_items', 'order_id', p_order_id,
                               'order_code', v_order_code, 'role', v_role, 'device_type', v_device_type,
                               'order_status', v_o_status, 'denied_reason', 'modifier_option_not_in_scope'));
    return jsonb_build_object('ok', false, 'error', 'modifier_option_not_in_scope',
                              'entity', 'order', 'modifiers', v_bad_modifiers,
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
