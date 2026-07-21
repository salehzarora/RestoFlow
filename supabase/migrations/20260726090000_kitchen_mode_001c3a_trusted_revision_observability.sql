-- ============================================================================
-- KITCHEN-MODE-001C3A — trusted workflow revision + safe kitchen observability.
--
-- ADDITIVE ONLY. No new table, no new column, no destructive DDL, and NO
-- workflow-mode setter of any kind (the guarded owner setter is 001C3B and
-- its production activation is gated even later — see the phase contract).
--
--   1. app.get_device_kitchen_workflow_mode — faithful re-creation of the
--      NEWEST body (20260723090000 lines 112-170; verified: never redefined
--      since) with ONE additive envelope key: `mode_revision`, read from
--      branches.kitchen_workflow_mode_revision in the SAME liveness-proven
--      select. Old clients parse only {ok, kitchen_workflow_mode} and are
--      unaffected. Grants gain the explicit anon revoke the 001A pair
--      predates (001C1-era hygiene).
--   2. app.list_kitchen_print_dispatches — NEW bounded member READ over the
--      dispatch ledger (safe scalar fields only; never the payload, never a
--      device/printer identifier, never an endpoint). Foundation for the
--      001C3C possiblyPrinted review panel. No mutation of any kind.
--   3. app.audit_action_has_detail + app.audit_safe_detail — faithful
--      re-creations of the NEWEST bodies (20260725090000 lines 2834-2999)
--      adding the KITCHEN-MODE-001C3+ safe scalar keys
--      (kitchen_workflow_mode / kitchen_workflow_mode_revision / resolution /
--      reason_code). Nothing writes the new actions yet — this migration
--      only prepares the safe projection so the 001C3B setter and hold
--      resolution can be rendered without a second audit-surface change.
--
-- AUDIT NOTE (Option B, approved): the RF-017 human-actor constraint
-- (audit_events_actor_present) is deliberately UNTOUCHED. Device-token
-- paths remain unaudited by design; their observability is the ledger
-- itself, now member-readable through the bounded inspection RPC.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.get_device_kitchen_workflow_mode — additive mode_revision.
-- ----------------------------------------------------------------------------
create or replace function app.get_device_kitchen_workflow_mode(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_hash text;
  v_mode text;
  v_rev  integer;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_workflow_mode');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- FULL device-liveness contract (review finding HIGH-2): the RF-118
  -- restore_device_session token proof (active + non-revoked + NON-EXPIRED
  -- session on an active pairing for THIS device, live device, live
  -- branch/restaurant tombstones) EXTENDED with the tenant-suspension gates
  -- (branch/restaurant/organization status = 'active') and explicit same-scope
  -- pins between session, pairing and device (defence in depth — the
  -- device_sessions composite FKs already make a cross-branch session row
  -- structurally impossible). Read the mode from the device's OWN branch only —
  -- the caller can never choose a branch.
  -- KITCHEN-MODE-001C3A: the SAME proven row now also yields the branch's
  -- kitchen_workflow_mode_revision (server-authoritative, CHECK > 0) so a
  -- POS can file a readiness report while the branch is still kds. No other
  -- behavior changes.
  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_mode, v_rev
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
      and (ds.expires_at is null or ds.expires_at > now())  -- RF-118: reject an expired session
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_mode is null then
    -- typed failure — NEVER a silent 'kds': the POS client must be able
    -- to fail closed (block submission) when the mode cannot be read.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_workflow_mode');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'kitchen_workflow_mode',
                            'kitchen_workflow_mode', v_mode,
                            'mode_revision', v_rev,
                            'server_ts', now());
end;
$$;

comment on function app.get_device_kitchen_workflow_mode(uuid, text) is
  'KITCHEN-MODE-001A + 001C3A: TOKEN-PROVEN device read of its OWN branch''s kitchen_workflow_mode, now WITH the additive server-authoritative mode_revision (branches.kitchen_workflow_mode_revision, CHECK > 0 — never fabricated). FULL liveness contract preserved byte-for-byte (RF-118 expiry, tenant suspension, same-scope pins); EVERY failure remains the SAME typed {ok:false, error:invalid_session} — fail closed, no scope leak, NEVER a fabricated ''kds''. Old clients that parse only {ok, kitchen_workflow_mode} are unaffected. READ-ONLY — no setter exists in this phase.';

create or replace function public.get_device_kitchen_workflow_mode(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_device_kitchen_workflow_mode(p_device_id, p_session_token); $$;

revoke all on function app.get_device_kitchen_workflow_mode(uuid, text)    from public;
revoke all on function app.get_device_kitchen_workflow_mode(uuid, text)    from anon;
grant execute on function app.get_device_kitchen_workflow_mode(uuid, text) to authenticated;
revoke all on function public.get_device_kitchen_workflow_mode(uuid, text)    from public;
revoke all on function public.get_device_kitchen_workflow_mode(uuid, text)    from anon;
grant execute on function public.get_device_kitchen_workflow_mode(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.list_kitchen_print_dispatches — bounded member inspection (READ ONLY).
-- ----------------------------------------------------------------------------
create or replace function app.list_kitchen_print_dispatches(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_status_filter     text default null,
  p_limit             integer default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id         uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid;
  v_filter text;
  v_limit  integer;
  v_page   jsonb;
  v_rows   jsonb;
  v_more   boolean;
  v_last   jsonb;
begin
  -- Membership authorization mirrors get_kitchen_workflow_transition_readiness:
  -- an unauthenticated caller is a hard 42501; an out-of-scope caller gets the
  -- scope-leak-free {error: not_found, entity: branch}.
  v_actor := app.current_app_user_id();
  if v_actor is null then
    raise exception 'list_kitchen_print_dispatches: not authenticated'
      using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  if not exists (
    select 1
      from public.branches b
      join public.restaurants r on r.id = b.restaurant_id
       and r.organization_id = b.organization_id and r.deleted_at is null
      join public.organizations o on o.id = b.organization_id and o.deleted_at is null
     where b.id = p_branch_id
       and b.organization_id = p_organization_id
       and b.restaurant_id = p_restaurant_id
       and b.deleted_at is null
  ) then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  if app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id) < 1 then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  -- Closed vocabularies; defaults are the operationally useful ones.
  v_filter := coalesce(p_status_filter, 'unresolved');
  if v_filter not in ('unresolved', 'possibly_printed', 'completed', 'superseded', 'all') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status_filter',
                              'entity', 'kitchen_print_dispatches_inspection');
  end if;
  v_limit := coalesce(p_limit, 20);
  if v_limit < 1 or v_limit > 50 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit',
                              'entity', 'kitchen_print_dispatches_inspection');
  end if;
  -- Keyset cursor is all-or-nothing.
  if (p_cursor_created_at is null) <> (p_cursor_id is null) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor',
                              'entity', 'kitchen_print_dispatches_inspection');
  end if;

  -- SAFE SCALAR projection ONLY: never money_free_payload, never the
  -- idempotency key, never claimed_by_device_id / claim internals, never an
  -- endpoint or fingerprint (none exist on this table by design). Newest
  -- first (observability ordering), deterministic (created_at, id) keyset.
  select coalesce(jsonb_agg(s.j order by s.created_at desc, s.id desc), '[]'::jsonb)
    into v_page
    from (
      select d.created_at, d.id,
             jsonb_build_object(
               'dispatch_id',        d.id,
               'dispatch_type',      d.dispatch_type,
               'order_id',           d.order_id,
               'created_at',         d.created_at,
               'claimed',            d.claimed_at is not null,
               'last_client_status', d.last_client_status,
               'last_error_code',    d.last_error_code,
               'completed_at',       d.completed_at,
               'possibly_printed',   (coalesce(d.last_client_status, '') = 'possibly_printed'
                                      and d.completed_at is null
                                      and d.superseded_by_dispatch_id is null),
               'superseded',         d.superseded_by_dispatch_id is not null
             ) as j
        from public.kitchen_print_dispatches d
       where d.organization_id = p_organization_id
         and d.restaurant_id   = p_restaurant_id
         and d.branch_id       = p_branch_id
         and case v_filter
               when 'unresolved'       then d.completed_at is null
                                         and d.superseded_by_dispatch_id is null
               when 'possibly_printed' then d.completed_at is null
                                         and d.superseded_by_dispatch_id is null
                                         and coalesce(d.last_client_status, '') = 'possibly_printed'
               when 'completed'        then d.completed_at is not null
               when 'superseded'       then d.superseded_by_dispatch_id is not null
               else true
             end
         and (p_cursor_created_at is null
              or (d.created_at, d.id) < (p_cursor_created_at, p_cursor_id))
       order by d.created_at desc, d.id desc
       limit v_limit + 1
    ) s;

  v_more := jsonb_array_length(v_page) > v_limit;
  if v_more then
    select coalesce(jsonb_agg(t.e order by t.ord), '[]'::jsonb)
      into v_rows
      from jsonb_array_elements(v_page) with ordinality as t(e, ord)
     where t.ord <= v_limit;
  else
    v_rows := v_page;
  end if;
  v_last := case when jsonb_array_length(v_rows) > 0 then v_rows -> -1 else null end;

  return jsonb_build_object(
    'ok', true,
    'entity', 'kitchen_print_dispatches_inspection',
    'dispatches', v_rows,
    'has_more', v_more,
    'next_cursor', case when v_more then jsonb_build_object(
                     'created_at', v_last -> 'created_at',
                     'id',         v_last -> 'dispatch_id')
                   else null end,
    'server_ts', now());
end;
$$;

comment on function app.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid) is
  'KITCHEN-MODE-001C3A: bounded member READ over the kitchen dispatch ledger (any active membership covering the branch, rank > 0; out-of-scope callers get the scope-leak-free not_found). SAFE SCALARS ONLY — dispatch id/type/order id/timestamps/claimed-boolean/last_client_status/CHECK-constrained last_error_code/possibly_printed/superseded; NEVER the money_free_payload, idempotency key, claim internals, device ids, endpoints, or fingerprints. Closed status filter (unresolved | possibly_printed | completed | superseded | all), limit 1..50 (default 20), deterministic newest-first (created_at, id) keyset pagination with truthful has_more. READ-ONLY: no mutation, no resolution — the operator-facing hold resolution is 001C3B.';

create or replace function public.list_kitchen_print_dispatches(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_status_filter text default null, p_limit integer default 20,
  p_cursor_created_at timestamptz default null, p_cursor_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_kitchen_print_dispatches(p_organization_id, p_restaurant_id, p_branch_id, p_status_filter, p_limit, p_cursor_created_at, p_cursor_id); $$;

revoke all on function app.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid)    from public;
revoke all on function app.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid)    from anon;
grant execute on function app.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid) to authenticated;
revoke all on function public.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid)    from public;
revoke all on function public.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid)    from anon;
grant execute on function public.list_kitchen_print_dispatches(uuid, uuid, uuid, text, integer, timestamptz, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 3a. app.audit_action_has_detail — faithful re-creation of the NEWEST body
--     (20260725090000 lines 2834-2881). VERIFIED for 001C3A: every action of
--     the upcoming kitchen-mode family already passes through the existing
--     prefixes (settings.% covers settings.branch.kitchen_mode_updated /
--     _update_denied; kitchen.% covers kitchen.dispatch_created /
--     _void_created / _hold_resolved) — the body is intentionally UNCHANGED.
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
      -- KITCHEN-MODE-001B: printer configuration actions carry a safe scalar
      -- projection (display_name / role / paper_width / is_enabled /
      -- connection_type). connection_config stays a nested object, so the
      -- scalar-only allowlist can never surface host/port/addresses.
      or p_action like 'printer.%'
      -- KITCHEN-MODE-001C1: kitchen dispatch events carry safe scalars only
      -- (order_code / dispatch_type / membership) — never the payload.
      -- KITCHEN-MODE-001C3A: the same prefix covers the upcoming
      -- kitchen.dispatch_hold_resolved (001C3B) — no new pattern needed.
      or p_action like 'kitchen.%'
      or p_action =    'pin_session.failed';
$$;

comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 .. KITCHEN-MODE-001C1 + 001C3A: faithful re-creation; VERIFIED that the 001C3 kitchen-mode action family (settings.branch.kitchen_mode_updated/_update_denied via settings.%, kitchen.dispatch_created/_void_created/_hold_resolved via kitchen.%) needs no new pattern. Gates app.audit_safe_detail.';

revoke all on function app.audit_action_has_detail(text) from public;
revoke all on function app.audit_action_has_detail(text) from anon;

-- ----------------------------------------------------------------------------
-- 3b. app.audit_safe_detail — faithful re-creation of the NEWEST body
--     (20260725090000 lines 2888-2999) with the KITCHEN-MODE-001C3A safe
--     scalar keys appended to the canonical allowlist.
-- ----------------------------------------------------------------------------
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
    'dispatch_type',
    -- KITCHEN-MODE-001C3A: the kitchen-mode family scalars. kitchen_workflow_mode
    -- is the closed kds|printer_only enum; kitchen_workflow_mode_revision is a
    -- small positive integer (never money, never an identifier — T-003 holds);
    -- resolution / reason_code are CLOSED safe state tokens written only by the
    -- future 001C3B owner setter + hold resolution (human-actor paths). NOTE:
    -- settings.branch.updated projects full branch-row snapshots, so the mode
    -- and revision now also surface there — both are safe display state, the
    -- timezone/name class.
    'kitchen_workflow_mode','kitchen_workflow_mode_revision','resolution','reason_code'
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
  'ALLOWLIST projection of one audit payload to canonical safe fields (see 20260724090000 + 20260725090000) + KITCHEN-MODE-001C3A kitchen_workflow_mode / kitchen_workflow_mode_revision / resolution / reason_code (closed safe state scalars for the 001C3B setter + hold resolution). kitchen.% keeps the MONEY-FREE hostile-key hardening. Faithful re-creation otherwise; every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

revoke all on function app.audit_safe_detail(text, jsonb) from public;
revoke all on function app.audit_safe_detail(text, jsonb) from anon;
