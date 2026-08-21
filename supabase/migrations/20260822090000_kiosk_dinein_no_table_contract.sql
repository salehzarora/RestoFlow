-- ============================================================================
-- KIOSK-001-PREREQ-DINEIN-NO-TABLE-079 — the dine-in-without-a-table contract.
--
-- OWNER REQUIREMENT: the kiosk setting "Enable table selection for dine-in"
-- may be OFF — the customer skips the table picker and a valid dine-in order
-- carries NO specific table. No fake or placeholder table, ever.
--
-- Until now app.kiosk_submit_order refused dine_in + NULL table
-- ('table_required' — inherited from the POS shape rules). This migration
-- re-emits the function with EXACTLY ONE semantic change:
--
--   * takeaway + table       -> STILL refused ('table_not_allowed')
--   * dine_in  + NULL table  -> now ACCEPTED (no lock, no occupancy effect,
--                               no table row of any kind)
--   * dine_in  + table       -> the FULL Phase-2 atomic gate, byte-unchanged
--                               (FOR UPDATE, effectively-available only,
--                               'table_no_longer_available' for the loser,
--                               'table_not_available' for structural
--                               failures). A supplied table is ALWAYS fully
--                               validated — never silently ignored.
--
-- Why NULL is safe (audited, KIOSK-001-PREREQ-079):
--   * no DB constraint binds dine_in to a table (deliberate since
--     RESTAURANT-OPERATIONS-V1-001 — the rule was RPC-shape only, and
--     historical dine-in rows with NULL tables already exist);
--   * derived occupancy counts ONLY non-null table_ids, so a NULL-table
--     order can neither create nor clear floor truth;
--   * every projection that shows a table (pos_order_snapshots, both kitchen
--     dispatch payloads, owner order history, active orders, settlement
--     consistency) LEFT JOINs public.tables — NULL yields table_label null,
--     the exact shape every takeaway row already produces;
--   * payment/settlement/completion/void/audit are table-agnostic.
--
-- Server-side per-device settings DO NOT EXIST yet (no config column, no
-- device-settings table, no device-update RPC — the repo's setting pattern is
-- per-branch). Inventing one here was explicitly out of scope, so:
-- TABLE-SELECTION ON/OFF ENFORCEMENT REMAINS CLIENT-SIDE UNTIL KIOSK
-- SETTINGS ARE SERVER-PERSISTED. This is acceptable because no security or
-- financial authority depends on table presence: prices/modifiers/discounts/
-- currency/tax/idempotency/actor/audit are all enforced independently and are
-- BYTE-UNCHANGED below (HARDENING-FIX-073 preserved in full). A client that
-- omits the table gains nothing — it loses the seat claim.
--
-- POS app.submit_order is NOT touched: staff dine-in still requires a table.
-- Media/storage policies untouched. No client submit is enabled by this.
-- ============================================================================

create or replace function app.kiosk_submit_order(
  p_device_id                   uuid,
  p_session_token               text,
  p_order_id                    uuid,
  p_local_operation_id          text,
  p_order_type                  text,
  p_table_id                    uuid,
  p_currency_code               text,
  p_notes                       text,
  p_customer_name               text,
  p_customer_phone              text,
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
  v_sid           uuid;
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_payload       jsonb;
  v_fingerprint   text;
  v_so_id         uuid;
  v_ex_id         uuid;
  v_ex_status     text;
  v_ex_result     jsonb;
  v_ex_optype     text;
  v_ex_fp         text;
  v_existing_id   uuid;
  v_existing_rev  integer;
  v_existing_status text;
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
  v_bad_modifiers jsonb;
  v_stale_modifiers jsonb;
  v_item_ids      uuid[];
  v_t_status      text;
  v_customer_name text;
  v_customer_phone text;
  v_kitchen_mode  text;
  v_canon_currency  text;
  v_tax_enabled     boolean;
  v_tax_rate_bp     integer;
  v_tax_mode        text;
  v_expected_tax    bigint;
  v_price_mismatch  jsonb;
  v_invalid_mods    jsonb;
  v_canon_item_name text;
  v_canon_mod_name  text;
  v_canon_opt_name  text;
  v_canon_delta     bigint;
  v_auto          jsonb;
  v_result        jsonb;
begin
  -- (proof) kiosk device session token — the ONLY authority. Scope is derived
  -- here; nothing scope-shaped is accepted from the payload (R-003).
  select o_session, o_org, o_rest, o_branch
    into v_sid, v_org, v_rest, v_branch
    from app.kiosk_session_context(p_device_id, p_session_token);
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order');
  end if;

  -- (protocol shape) identities the ledger + business replay key on.
  if p_order_id is null then
    raise exception 'kiosk_submit_order: order_id is required' using errcode = '42501';
  end if;
  if p_local_operation_id is null or btrim(p_local_operation_id) = '' then
    raise exception 'kiosk_submit_order: local_operation_id is required' using errcode = '42501';
  end if;

  -- (customer identity) OPTIONAL name/phone, validated UP FRONT exactly like
  -- sync_push's order.submit arm: an invalid non-empty phone is a typed
  -- refusal and no order is created; both values are display data only.
  v_customer_name  := left(btrim(coalesce(p_customer_name, '')), 80);
  v_customer_phone := btrim(coalesce(p_customer_phone, ''));
  if v_customer_phone <> '' and not app.is_valid_customer_phone(v_customer_phone) then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload',
                              'entity', 'order', 'field', 'customer_phone');
  end if;

  -- (b2 mirror) ATOMIC transport-ledger claim (D-022), the sync_push contract
  -- verbatim for a single op: fingerprint EXCLUDES customer_phone (data-only —
  -- the same canonical rule as order.submit), claim is one INSERT .. ON
  -- CONFLICT DO NOTHING; a lost claim locks the committed row and either
  -- refuses a reused key (different payload), replays a TERMINAL result, or
  -- adopts a stale non-terminal row.
  v_payload := jsonb_build_object(
    'order_id', p_order_id, 'order_type', p_order_type, 'table_id', p_table_id,
    'currency_code', p_currency_code, 'notes', p_notes,
    'customer_name', nullif(v_customer_name, ''),
    'customer_phone', nullif(v_customer_phone, ''),
    'order_items', p_order_items,
    'subtotal_minor', p_client_subtotal_minor,
    'discount_total_minor', p_client_discount_total_minor,
    'tax_total_minor', p_client_tax_total_minor,
    'grand_total_minor', p_client_grand_total_minor);
  v_fingerprint := md5('kiosk.order.submit' || '|' || (v_payload - 'customer_phone')::text);

  insert into public.sync_operations as so (
    organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
    target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
  values (v_org, v_rest, v_branch, p_device_id, btrim(p_local_operation_id), 'kiosk.order.submit',
          'order', p_order_id, v_payload, v_fingerprint, '[]'::jsonb, 'in_flight', p_client_created_at)
  on conflict (organization_id, device_id, local_operation_id) do nothing
  returning so.id into v_so_id;

  if v_so_id is null then
    select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
      into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
      from public.sync_operations so
      where so.organization_id = v_org and so.device_id = p_device_id
        and so.local_operation_id = btrim(p_local_operation_id)
      for update;
    if v_ex_optype <> 'kiosk.order.submit' or v_ex_fp <> v_fingerprint then
      insert into public.audit_events (organization_id, restaurant_id, branch_id,
        actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, null, p_device_id, 'kiosk.operation_conflict', null, null,
              jsonb_build_object('actor_kind', 'kiosk_device',
                                 'local_operation_id', btrim(p_local_operation_id),
                                 'stored_operation_type', v_ex_optype,
                                 'pushed_operation_type', 'kiosk.order.submit',
                                 'stored_status', v_ex_status,
                                 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
      return jsonb_build_object('ok', false, 'error', 'conflict', 'entity', 'order',
        'detail', 'idempotency key already used for a different operation/payload');
    end if;
    if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
      return coalesce(v_ex_result, '{}'::jsonb) || jsonb_build_object('idempotency_replay', true);
    end if;
    v_so_id := v_ex_id;  -- adopt the stale non-terminal row (crashed claimant)
  end if;

  -- (payload) basic shape + currency + order_type — submit_order VERBATIM.
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'kiosk_submit_order: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;
  if p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'kiosk_submit_order: invalid order_type %', p_order_type using errcode = '42501';
  end if;
  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'kiosk_submit_order: currency_code must be a 3-letter ISO code' using errcode = '42501';
  end if;
  if p_client_discount_total_minor < 0 or p_client_tax_total_minor < 0
     or p_client_subtotal_minor < 0 or p_client_grand_total_minor < 0 then
    raise exception 'kiosk_submit_order: order totals must be non-negative integers (minor units)' using errcode = '42501';
  end if;

  -- (authority: discounts — HARDENING-FIX-073) V1 kiosk has NO customer
  -- discount authority: a customer terminal can never price its own reduction.
  -- Both the order-level total AND every per-line discount must be exactly
  -- zero. Staff POS discounts (role-gated RPCs) are untouched.
  if p_client_discount_total_minor <> 0
     or exists (
       select 1 from jsonb_array_elements(p_order_items) e
         where (e ? 'line_discount_minor')
           and jsonb_typeof(e -> 'line_discount_minor') <> 'null'
           and app.order_parse_minor(e -> 'line_discount_minor', 'order_items[].line_discount_minor') <> 0) then
    v_result := jsonb_build_object('ok', false, 'error', 'discount_not_allowed', 'entity', 'order');
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'discount_not_allowed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: currency — HARDENING-FIX-073) a syntactically valid ISO code is
  -- not enough for an untrusted terminal: the order currency must BE the tenant
  -- currency (the same coalesce(restaurants.currency_override,
  -- organizations.default_currency) kiosk_menu serves).
  select coalesce(r.currency_override, o.default_currency)
    into v_canon_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = v_rest and r.organization_id = v_org;
  if v_canon_currency is null or p_currency_code <> v_canon_currency then
    v_result := jsonb_build_object('ok', false, 'error', 'currency_mismatch', 'entity', 'order',
                                   'expected_currency', v_canon_currency);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'currency_mismatch', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (payload+) order-type table SHAPE rules (KIOSK-001-PREREQ-079): takeaway
  -- still never carries a table; dine-in MAY omit the table — the owner's
  -- "table selection OFF" flow seats no specific table, and a NULL table is
  -- the same shape every takeaway row already flows through downstream
  -- (occupancy counts only non-null tables; every projection LEFT JOINs).
  if p_order_type = 'takeaway' and p_table_id is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'table_not_allowed', 'entity', 'order');
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'table_not_allowed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (money recompute) from the SUBMITTED SNAPSHOTS ONLY — submit_order VERBATIM.
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'kiosk_submit_order: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    if (v_item ->> 'menu_item_id') is null then
      raise exception 'kiosk_submit_order: order_items[].menu_item_id is required' using errcode = '42501';
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      raise exception 'kiosk_submit_order: order_items[].menu_item_name_snapshot is required' using errcode = '42501';
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
          raise exception 'kiosk_submit_order: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;

    v_line_total := v_qty * (v_unit + v_mod_sum) - v_line_disc;
    if v_line_total < 0 then
      raise exception 'kiosk_submit_order: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if p_client_subtotal_minor <> v_subtotal then
    raise exception 'kiosk_submit_order: client subtotal_minor (%) does not match snapshot recompute (%)',
      p_client_subtotal_minor, v_subtotal using errcode = '42501';
  end if;
  -- (authority: tax — HARDENING-FIX-073) the customer terminal never prices its
  -- own tax. The RF-117 per-branch owner setting is the single authority:
  -- disabled/0-bp => tax MUST be 0; enabled => tax MUST equal the canonical
  -- integer computation — round-HALF-AWAY-FROM-ZERO on a numeric transient,
  -- byte-matching the POS tax_math (`percentMinor`) and the money engine:
  --   exclusive: round(base * rate_bp / 10000)          (added on top)
  --   inclusive: round(base * rate_bp / (10000+rate_bp)) (extracted, not added)
  -- The base is the post-discount goods total, which for a kiosk (discounts
  -- forced 0 above) is the recomputed subtotal. A mismatch is the stable
  -- refresh-required refusal (the owner may have changed the rate mid-cart).
  select b.tax_enabled, b.tax_rate_bp, b.tax_mode
    into v_tax_enabled, v_tax_rate_bp, v_tax_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if not found then
    raise exception 'kiosk_submit_order: branch row unavailable during the tax gate (state inconsistency)';
  end if;
  if coalesce(v_tax_enabled, false) and coalesce(v_tax_rate_bp, 0) > 0 then
    if v_tax_mode = 'inclusive' then
      v_expected_tax := round((v_subtotal::numeric * v_tax_rate_bp) / (10000 + v_tax_rate_bp))::bigint;
    else
      v_expected_tax := round((v_subtotal::numeric * v_tax_rate_bp) / 10000)::bigint;
    end if;
  else
    v_expected_tax := 0;
  end if;
  if p_client_tax_total_minor <> v_expected_tax then
    v_result := jsonb_build_object('ok', false, 'error', 'tax_mismatch', 'entity', 'order',
                                   'expected_tax_total_minor', v_expected_tax);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'tax_mismatch', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- discount proven 0 and tax proven canonical, so the grand total is fully
  -- server-derived: subtotal plus the tax only when the mode ADDS it.
  v_grand := v_subtotal
           + case when coalesce(v_tax_enabled, false) and coalesce(v_tax_rate_bp, 0) > 0
                       and v_tax_mode = 'exclusive'
                  then v_expected_tax else 0 end;
  if p_client_grand_total_minor <> v_grand then
    raise exception 'kiosk_submit_order: client grand_total_minor (%) does not match snapshot recompute (%)',
      p_client_grand_total_minor, v_grand using errcode = '42501';
  end if;

  -- (business replay backstop) orders UNIQUE (device_id, local_operation_id) —
  -- submit_order VERBATIM (belt under the ledger; also finalizes an adopted
  -- ledger row whose order actually committed).
  select o.id, o.revision, o.status into v_existing_id, v_existing_rev, v_existing_status
    from public.orders o
    where o.organization_id = v_org
      and o.device_id = p_device_id
      and o.local_operation_id = btrim(p_local_operation_id)
    limit 1;
  if found then
    v_result := jsonb_build_object(
      'ok', true, 'order_id', v_existing_id, 'revision', v_existing_rev,
      'server_ts', now(), 'idempotency_replay', true,
      'auto_completed', (v_existing_status = 'completed'),
      'order_status', v_existing_status);
    update public.sync_operations set status = 'applied', result = v_result,
      applied_at = coalesce(applied_at, now()), updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (accept-1 KIOSK) owner decision B — the ATOMIC no-hold table gate.
  -- The chosen table must be a LIVE, ACTIVE, IN-SERVICE table of the SESSION
  -- branch (structural refusal identical to POS: 'table_not_available' — no
  -- existence oracle), and — KIOSK-ONLY — effectively AVAILABLE under a row
  -- lock: the row is locked FOR UPDATE, then manual state + DERIVED occupancy
  -- are evaluated under that lock. Two concurrent kiosk submits serialize on
  -- the lock; the loser sees the winner's committed dine-in order and gets the
  -- stable 'table_no_longer_available' refusal. POS submits are untouched:
  -- they never lock the table row and keep seating occupied/reserved tables
  -- (merging parties stays a staff power).
  if p_order_type = 'dine_in' and p_table_id is not null then
    select t.status into v_t_status
      from public.tables t
      where t.id              = p_table_id
        and t.organization_id = v_org
        and t.restaurant_id   = v_rest
        and t.branch_id       = v_branch
        and t.is_active
        and t.deleted_at is null
      for update;
    if not found or v_t_status = 'out_of_service' then
      v_result := jsonb_build_object('ok', false, 'error', 'table_not_available', 'entity', 'order');
      update public.sync_operations set status = 'rejected', result = v_result,
        rejection_reason = 'table_not_available', updated_at = now() where id = v_so_id;
      return v_result;
    end if;
    if v_t_status in ('occupied', 'reserved')
       or exists (
         select 1 from public.orders o
           where o.organization_id = v_org
             and o.branch_id       = v_branch
             and o.order_type      = 'dine_in'
             and o.table_id        = p_table_id
             and o.deleted_at is null
             and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')) then
      v_result := jsonb_build_object('ok', false, 'error', 'table_no_longer_available', 'entity', 'order');
      update public.sync_operations set status = 'rejected', result = v_result,
        rejection_reason = 'table_no_longer_available', updated_at = now() where id = v_so_id;
      return v_result;
    end if;
  end if;

  -- (accept-2) sellability + availability under the canonical menu_items
  -- FOR UPDATE serialization — submit_order VERBATIM.
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
    v_result := jsonb_build_object('ok', false, 'error', 'item_unavailable',
                                   'entity', 'order', 'items', v_unavailable);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'item_unavailable', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: item price — HARDENING-FIX-073) the kiosk client is untrusted:
  -- its submitted unit price snapshot must EQUAL the canonical live
  -- base_price_minor, read under the SAME menu_items FOR UPDATE serialization
  -- as the sellability gate (a concurrent price edit serializes against this
  -- submit). A mismatch is the stable refresh-required refusal — the server
  -- never silently charges a different amount than the cart showed.
  select jsonb_agg(jsonb_build_object(
           'menu_item_id', bad.menu_item_id, 'name', bad.name)
           order by bad.menu_item_id)
    into v_price_mismatch
    from (
      select distinct e ->> 'menu_item_id' as menu_item_id, i.name
        from jsonb_array_elements(p_order_items) e
        join public.menu_items i
          on i.id = (e ->> 'menu_item_id')::uuid
         and i.organization_id = v_org
       where (e ->> 'unit_price_minor_snapshot')::bigint is distinct from i.base_price_minor
    ) bad;
  if v_price_mismatch is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'menu_price_changed',
                                   'entity', 'order', 'items', v_price_mismatch);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'menu_price_changed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (003D) modifier option IDENTITY + OWNERSHIP — submit_order VERBATIM.
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
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_option_not_in_scope',
                                   'entity', 'order', 'modifiers', v_bad_modifiers);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_option_not_in_scope', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: modifier liveness + price — HARDENING-FIX-073) ownership alone
  -- (003D above) is not enough for an untrusted terminal. Every selected option
  -- must be LIVE and branch-visible inside a LIVE branch-visible group (the
  -- exact kiosk_menu predicates), and its submitted price snapshot must EQUAL
  -- the canonical price_delta_minor. Dead/hidden selections are the stable
  -- selection refusal; a price drift is the stable refresh-required refusal.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'modifier_option_id')
    into v_invalid_mods
    from (
      select distinct jsonb_build_object(
               'menu_item_id',        e ->> 'menu_item_id',
               'modifier_option_id',  m ->> 'modifier_option_id',
               'reason',              'not_live') as bad
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
              and mo.restaurant_id   = v_rest
              and mo.id              = (m ->> 'modifier_option_id')::uuid
              and mo.is_active and mo.deleted_at is null
              and (mo.branch_id is null or mo.branch_id = v_branch)
              and mg.restaurant_id = v_rest
              and mg.is_active and mg.deleted_at is null
              and (mg.branch_id is null or mg.branch_id = v_branch)
         )
    ) offenders;
  if v_invalid_mods is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_selection_invalid',
                                   'entity', 'order', 'modifiers', v_invalid_mods);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_selection_invalid', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'modifier_option_id')
    into v_price_mismatch
    from (
      select distinct jsonb_build_object(
               'menu_item_id',       e ->> 'menu_item_id',
               'modifier_option_id', m ->> 'modifier_option_id') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
        join public.modifier_options mo
          on mo.organization_id = v_org
         and mo.id = (m ->> 'modifier_option_id')::uuid
       where (m ->> 'modifier_option_id') is not null
         and (m ->> 'price_minor_snapshot')::bigint is distinct from mo.price_delta_minor
    ) offenders;
  if v_price_mismatch is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'menu_price_changed',
                                   'entity', 'order', 'modifiers', v_price_mismatch);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'menu_price_changed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: modifier group RULES — HARDENING-FIX-073) the server enforces
  -- the CURRENT group contract per submitted LINE, mirroring the POS sheet's
  -- effective rules exactly:
  --   effective_min = single ? 1 : (is_required and min_select=0 ? 1 : min_select)
  --   effective_max = single ? 1 : max_select   (null = unlimited)
  -- over DISTINCT selected options, and per-option TOTAL quantity (duplicate
  -- rows are SUMMED so they can never bypass a cap) = 1 unless the group
  -- allows quantities, else capped by max_quantity (null = no cap). The group
  -- universe is the item's LIVE branch-visible groups — a dead or hidden group
  -- is never demanded and never counted.
  with lines as (
    select t.ord, t.e
      from jsonb_array_elements(p_order_items) with ordinality t(e, ord)
  ),
  sel as (
    select l.ord,
           (l.e ->> 'menu_item_id')::uuid as item_id,
           (m ->> 'modifier_option_id')::uuid as option_id,
           sum(case when (m ? 'quantity') and jsonb_typeof(m -> 'quantity') <> 'null'
                    then (m ->> 'quantity')::bigint else 1 end) as total_qty
      from lines l
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(l.e -> 'modifiers') = 'array'
             then l.e -> 'modifiers' else '[]'::jsonb end) m
     where (m ->> 'modifier_option_id') is not null
     group by 1, 2, 3
  ),
  live_groups as (
    select mg.menu_item_id as item_id, mg.id as group_id, mg.name,
           mg.selection_type, mg.min_select, mg.max_select, mg.is_required,
           mg.allow_quantity, mg.max_quantity,
           case when mg.selection_type = 'single' then 1
                when mg.is_required and mg.min_select = 0 then 1
                else mg.min_select end as effective_min,
           case when mg.selection_type = 'single' then 1
                else mg.max_select end as effective_max
      from public.modifiers mg
      where mg.organization_id = v_org
        and mg.restaurant_id   = v_rest
        and mg.menu_item_id in (select distinct (e ->> 'menu_item_id')::uuid
                                  from jsonb_array_elements(p_order_items) e)
        and mg.is_active and mg.deleted_at is null
        and (mg.branch_id is null or mg.branch_id = v_branch)
  ),
  counts as (
    select s.ord, g.group_id,
           count(distinct s.option_id) as n_opts
      from sel s
      join public.modifier_options mo
        on mo.organization_id = v_org and mo.id = s.option_id
      join live_groups g
        on g.group_id = mo.modifier_id and g.item_id = s.item_id
      group by 1, 2
  ),
  violations as (
    -- (a) cardinality per line x live group (missing required group included:
    --     the cross join covers groups with NO selection at n = 0).
    select l.ord, g.group_id, g.name, 'selection_count'::text as kind
      from lines l
      join live_groups g on g.item_id = (l.e ->> 'menu_item_id')::uuid
      left join counts c on c.ord = l.ord and c.group_id = g.group_id
      where coalesce(c.n_opts, 0) < g.effective_min
         or (g.effective_max is not null and coalesce(c.n_opts, 0) > g.effective_max)
    union all
    -- (b) per-option quantity: exactly 1 unless quantities are allowed;
    --     otherwise capped by max_quantity (null = no cap).
    select s.ord, g.group_id, g.name, 'quantity'::text as kind
      from sel s
      join public.modifier_options mo
        on mo.organization_id = v_org and mo.id = s.option_id
      join live_groups g
        on g.group_id = mo.modifier_id and g.item_id = s.item_id
      where (not g.allow_quantity and s.total_qty <> 1)
         or (g.allow_quantity and g.max_quantity is not null and s.total_qty > g.max_quantity)
  )
  select jsonb_agg(distinct jsonb_build_object(
           'line', v.ord, 'modifier_id', v.group_id, 'modifier_name', v.name, 'kind', v.kind))
    into v_invalid_mods
    from violations v;
  if v_invalid_mods is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_selection_invalid',
                                   'entity', 'order', 'modifiers', v_invalid_mods);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_selection_invalid', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (021) the frozen preparation snapshot must still match — submit_order VERBATIM.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'option_name_snapshot')
    into v_stale_modifiers
    from (
      select distinct jsonb_build_object(
               'menu_item_id',         e ->> 'menu_item_id',
               'option_name_snapshot', m ->> 'option_name_snapshot') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
       where (m ->> 'modifier_option_id') is not null
         and app.kitchen_modifier_prep_projection(m -> 'meat_snapshot')
             is distinct from
             app.trusted_modifier_prep_snapshot(
               v_org,
               (e ->> 'menu_item_id')::uuid,
               (m ->> 'modifier_option_id')::uuid,
               e -> 'modifiers')
    ) offenders;
  if v_stale_modifiers is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_prep_snapshot_stale',
                                   'entity', 'order', 'modifiers', v_stale_modifiers);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_prep_snapshot_stale', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (insert) order header at 'submitted' — the STAFF ACTOR TRIPLE IS NULL
  -- (owner decision A: the kiosk device is the actor); shift is NULL (kiosks
  -- have no cash shifts); customer name/phone are stamped in the same insert.
  insert into public.orders (
    id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, table_id, shift_id,
    order_type, status, currency_code,
    subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor,
    notes, local_operation_id, revision, client_created_at,
    customer_name, customer_phone)
  values (
    p_order_id, v_org, v_rest, v_branch, p_device_id, null,
    null, null, p_table_id, null,
    p_order_type, 'submitted', p_currency_code,
    v_subtotal, p_client_discount_total_minor, p_client_tax_total_minor, v_grand,
    p_notes, btrim(p_local_operation_id), 1, p_client_created_at,
    nullif(v_customer_name, ''), nullif(v_customer_phone, ''));

  -- (insert) items + modifiers — submit_order VERBATIM.
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

    -- (authority: canonical snapshots — HARDENING-FIX-073) the persisted
    -- receipt/kitchen snapshot is the CANONICAL validated menu row, never a
    -- client string (the client's copy stays in the request payload for wire
    -- compatibility and idempotency identity only). Kiosks sell no
    -- sizes/variants, so those legacy snapshot slots persist NULL.
    select i.name into v_canon_item_name
      from public.menu_items i
      where i.organization_id = v_org and i.id = (v_item ->> 'menu_item_id')::uuid;
    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor, notes, prep_snapshot)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_canon_item_name, v_unit,
      null, null, v_line_disc, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot')
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          raise exception 'kiosk_submit_order: modifiers[].modifier_option_id is required' using errcode = '42501';
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          raise exception 'kiosk_submit_order: modifiers[].option_name_snapshot is required' using errcode = '42501';
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        -- canonical group/option names + the canonical validated delta
        -- (HARDENING-FIX-073; the client strings were required above for wire
        -- shape but are never persisted).
        select mo.name, mg.name, mo.price_delta_minor
          into v_canon_opt_name, v_canon_mod_name, v_canon_delta
          from public.modifier_options mo
          join public.modifiers mg
            on mg.organization_id = mo.organization_id and mg.id = mo.modifier_id
          where mo.organization_id = v_org
            and mo.id = (v_modifier ->> 'modifier_option_id')::uuid;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_canon_mod_name, v_canon_opt_name, v_canon_delta, v_mod_qty::int,
          app.kitchen_modifier_prep_projection(v_modifier -> 'meat_snapshot'));
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (audit) append-only, in the SAME transaction. The kiosk DEVICE is the
  -- audited actor (owner decision A): both human actor columns NULL, device_id
  -- present (valid under the widened audit_events_actor_present), the action
  -- kiosk-namespaced and actor_kind explicit.
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch,
    null, null, p_device_id,
    'kiosk.order.submitted', null, null,
    jsonb_build_object(
      'actor_kind',             'kiosk_device',
      'order_id',               p_order_id,
      'status',                 'submitted',
      'revision',               1,
      'currency_code',          p_currency_code,
      'subtotal_minor',         v_subtotal,
      'discount_total_minor',   p_client_discount_total_minor,
      'tax_total_minor',        p_client_tax_total_minor,
      'grand_total_minor',      v_grand,
      'device_id',              p_device_id,
      'local_operation_id',     btrim(p_local_operation_id),
      'order_type',             p_order_type,
      'table_id',               p_table_id,
      'item_count',             v_item_count,
      'modifier_count',         v_mod_count));

  -- (tail) KITCHEN-MODE — submit_order VERBATIM semantics: a printer_only
  -- branch gets its durable kitchen dispatch in the SAME transaction (actor
  -- args NULL: dispatch audit rows are device-attributed, valid under the
  -- widened constraint), and a zero-total printer-only order auto-completes.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id              = v_branch
      and b.organization_id = v_org
      and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'kiosk_submit_order: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;

  if v_kitchen_mode = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'initial_order',
      app.kitchen_dispatch_payload_initial(v_org, p_order_id),
      null, null, p_device_id);
  end if;

  if v_grand = 0 then
    if v_kitchen_mode = 'printer_only' then
      v_auto := app.try_auto_complete_order(
        v_org, v_rest, v_branch, p_order_id,
        'order_submitted',
        null,          -- no JWT actor
        null, null, null,  -- no staff actor on the kiosk path (decision A)
        p_device_id, btrim(p_local_operation_id));
    end if;
  end if;

  v_result := jsonb_build_object(
    'ok', true, 'order_id', p_order_id,
    'revision', coalesce((v_auto ->> 'revision')::integer, 1),
    'server_ts', now(), 'idempotency_replay', false,
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status', case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else 'submitted' end);
  update public.sync_operations set status = 'applied', result = v_result,
    applied_at = now(), updated_at = now() where id = v_so_id;
  return v_result;
end;
$$;

comment on function app.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'KIOSK-001 Phase 2 + HARDENING-FIX-073 (see 20260821090000 for the full contract — token proof, server-authoritative prices/modifiers/discounts/currency/tax, canonical snapshots, D-022 ledger, device actor) + KIOSK-001-PREREQ-079: dine_in MAY carry a NULL table (the owner-approved table-selection-OFF flow; no lock, no occupancy effect, no placeholder table) while a SUPPLIED dine-in table still passes the full Phase-2 atomic availability gate and takeaway still never carries one. Table-selection ON/OFF enforcement remains client-side until kiosk settings are server-persisted (no per-device settings mechanism exists yet); safe because no security/financial authority depends on table presence.';
