-- ============================================================================
-- RF-052 — orders / order_items / order_item_modifiers + app.submit_order RPC
-- ============================================================================
-- The core order WRITE path. Builds on RF-014 (org/restaurant/branch core +
-- resolver/scope helpers), RF-015 (memberships/employee_profiles), RF-016
-- (devices/device_sessions/pin_sessions), RF-050/RF-051 (auth + PIN session +
-- app.is_pin_session_valid). Additive and FORWARD-ONLY: never edits a prior
-- migration.
--
-- WHAT THIS DOES (API_CONTRACT §4.1)
--   1. Creates orders / order_items / order_item_modifiers (tenant+branch scoped,
--      integer _minor money only, client-captured PRICE SNAPSHOTS — D-008).
--   2. app.submit_order(...) SECURITY DEFINER RPC: authorizes the caller via a
--      VALID PIN SESSION (actor + scope derived server-side, never trusted from
--      the client), recomputes/validates totals FROM THE SUBMITTED SNAPSHOTS
--      (never the live menu), persists the order at status 'submitted' with items
--      'pending', and is idempotent on (device_id, local_operation_id).
--   3. Direct INSERT/UPDATE/DELETE on the three tables is REVOKED from
--      authenticated — the SECURITY DEFINER RPC is the only writer (D-011).
--
-- DECISIONS
--   * D-001/D-002/D-012 tenant isolation + four layers; composite same-org FKs.
--   * D-007 integer minor money; NO float/numeric/double/money types for money.
--   * D-008 capture price/modifier snapshots at order time; NEVER recompute from
--     the live menu. (The server recompute below is from the SUBMITTED snapshots
--     only — an anti-tamper check per MONEY_AND_TAX_SPEC §26, not a live lookup.)
--   * D-011 sensitive mutations only via SECURITY DEFINER RPC; clients never write
--     tenant rows directly.
--   * D-022 idempotency key = device_id + local_operation_id.
--   * RF051-B1 lesson: idempotency replay happens ONLY after full validation.
--
-- APPROVED INTERIM DECISIONS (RF-052)
--   * A1/A5: menu_item_id / modifier_option_id / item_size / item_variant /
--     table_id / shift_id reference entities with NO backend table yet (menu,
--     tables, shifts are local-only). They are stored as NON-FK uuid reference
--     ids + snapshots. We do NOT create backend menu/table/shift/kitchen tables.
--   * A2: submit_order requires a valid PIN session (owner/manager email-only
--     submit is out of scope).
--   * A3: order_items start status 'pending' (route_to_kitchen — a separate RPC —
--     owns 'queued'/kitchen routing). submit_order does NOT route to kitchen.
--   * A4: totals validated by recompute from submitted snapshots only; discount/
--     tax persisted as submitted snapshots (authoritative discount/tax = RF-053/
--     RF-054). receipt_number stays NULL (numbering = RF-054).
--   * A6: order-level totals persisted now as integer *_minor columns.
--
-- OUT OF SCOPE: route_to_kitchen + kitchen tables; RF-053 discount/void; RF-054
--   payment/receipt numbering; RF-055 shift reconciliation; RF-056/057 sync;
--   RF-059 full write/role matrix beyond this direct-write closure; RF-060/061;
--   any UI / Dart / config / remote / secrets / service-role.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. orders — a submitted order, tenant+branch scoped. All money is integer
--    _minor (bigint). Idempotency key (device_id, local_operation_id). Composite
--    same-org FKs to the backend tables that exist; menu/table/shift refs are
--    NON-FK uuids (no backend table; D-008 snapshots carry the authoritative data).
-- ----------------------------------------------------------------------------
create table orders (
  id                            uuid        not null default gen_random_uuid(),
  organization_id               uuid        not null references organizations (id) on delete restrict,
  restaurant_id                 uuid        not null,
  branch_id                     uuid        not null,
  device_id                     uuid        not null,
  pin_session_id                uuid        not null,
  opened_by_employee_profile_id uuid        not null,
  resolved_membership_id        uuid        not null,
  table_id                      uuid,                          -- non-FK reference (no backend tables table; A1/A5)
  shift_id                      uuid,                          -- non-FK reference (no backend shifts table; A1/A5)
  order_type                    text        not null check (order_type in ('dine_in', 'takeaway')),
  status                        text        not null default 'submitted'
                                  check (status in ('draft','submitted','accepted','preparing','ready','served','completed','cancelled','voided')),
  currency_code                 text        not null check (currency_code ~ '^[A-Z]{3}$'),
  subtotal_minor                bigint      not null check (subtotal_minor       >= 0),
  discount_total_minor          bigint      not null default 0 check (discount_total_minor >= 0),
  tax_total_minor               bigint      not null default 0 check (tax_total_minor      >= 0),
  grand_total_minor             bigint      not null check (grand_total_minor    >= 0),
  notes                         text,
  receipt_number                text,                          -- stays NULL here; numbering = RF-054
  receipt_provisional_id        text,
  local_operation_id            text        not null,
  revision                      integer     not null default 1,
  client_created_at             timestamptz,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  deleted_at                    timestamptz,
  primary key (id),
  unique (organization_id, id),                                -- same-org composite-FK target for children
  unique (device_id, local_operation_id),                      -- idempotency (D-022) race backstop
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, pin_session_id)
    references pin_sessions (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, opened_by_employee_profile_id)
    references employee_profiles (organization_id, id) on delete restrict,
  foreign key (organization_id, resolved_membership_id)
    references memberships (organization_id, id) on delete restrict
);

comment on table orders is
  'RF-052: a submitted order (API_CONTRACT §4.1). Tenant+branch scoped; all money integer _minor (D-007). Written ONLY by app.submit_order (SECURITY DEFINER; D-011). status starts submitted (the draft pre-state is local-only, RF-032). menu/table/shift refs are non-FK uuids (A1/A5). receipt_number = RF-054.';

create index orders_branch_idx        on orders (organization_id, restaurant_id, branch_id);
create index orders_device_idx        on orders (organization_id, restaurant_id, branch_id, device_id);
create index orders_pin_session_idx   on orders (organization_id, restaurant_id, branch_id, pin_session_id);
create index orders_employee_idx      on orders (organization_id, opened_by_employee_profile_id);
create index orders_membership_idx    on orders (organization_id, resolved_membership_id);

-- ----------------------------------------------------------------------------
-- 2. order_items — line items with captured price snapshots (D-008).
-- ----------------------------------------------------------------------------
create table order_items (
  id                        uuid        not null default gen_random_uuid(),
  organization_id           uuid        not null references organizations (id) on delete restrict,
  restaurant_id             uuid        not null,
  branch_id                 uuid        not null,
  order_id                  uuid        not null,
  menu_item_id              uuid        not null,                 -- non-FK reference (no backend menu table; A1)
  station_id                uuid,                                 -- non-FK reference; routing = RF-033/route_to_kitchen
  status                    text        not null default 'pending'
                              check (status in ('pending','queued','preparing','ready','served','voided','cancelled')),
  quantity                  integer     not null check (quantity > 0),
  menu_item_name_snapshot   text        not null,
  unit_price_minor_snapshot bigint      not null check (unit_price_minor_snapshot >= 0),
  item_size_snapshot        jsonb,
  item_variant_snapshot     jsonb,
  line_discount_minor       bigint      not null default 0 check (line_discount_minor >= 0),
  line_total_minor          bigint      not null check (line_total_minor >= 0),
  notes                     text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  deleted_at                timestamptz,
  primary key (id),
  unique (organization_id, id),                                   -- same-org composite-FK target for modifiers
  foreign key (organization_id, order_id)
    references orders (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table order_items is
  'RF-052: an order line with PRICE SNAPSHOTS captured at order time (D-008; never recomputed from the live menu). menu_item_id/station_id are non-FK reference uuids. status starts pending (queued = route_to_kitchen). All money integer _minor.';

create index order_items_order_idx  on order_items (organization_id, order_id);
create index order_items_branch_idx on order_items (organization_id, restaurant_id, branch_id);

-- ----------------------------------------------------------------------------
-- 3. order_item_modifiers — captured modifier snapshots (D-008).
-- ----------------------------------------------------------------------------
create table order_item_modifiers (
  id                     uuid        not null default gen_random_uuid(),
  organization_id        uuid        not null references organizations (id) on delete restrict,
  restaurant_id          uuid        not null,
  branch_id              uuid        not null,
  order_item_id          uuid        not null,
  modifier_option_id     uuid        not null,                    -- non-FK reference (no backend modifier table; A1)
  modifier_name_snapshot text,
  option_name_snapshot   text        not null,
  price_minor_snapshot   bigint      not null check (price_minor_snapshot >= 0),
  quantity               integer     not null default 1 check (quantity > 0),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz,
  primary key (id),
  foreign key (organization_id, order_item_id)
    references order_items (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table order_item_modifiers is
  'RF-052: a captured modifier snapshot on an order line (D-008). modifier_option_id is a non-FK reference uuid. price_minor_snapshot is integer _minor.';

create index order_item_modifiers_item_idx   on order_item_modifiers (organization_id, order_item_id);
create index order_item_modifiers_branch_idx on order_item_modifiers (organization_id, restaurant_id, branch_id);

-- ----------------------------------------------------------------------------
-- 4. updated_at triggers (reuse RF-014 app.set_updated_at()).
-- ----------------------------------------------------------------------------
create trigger orders_set_updated_at               before update on orders               for each row execute function app.set_updated_at();
create trigger order_items_set_updated_at          before update on order_items          for each row execute function app.set_updated_at();
create trigger order_item_modifiers_set_updated_at before update on order_item_modifiers for each row execute function app.set_updated_at();

-- ----------------------------------------------------------------------------
-- 5. RLS: enable + force, deny-by-default, membership/branch scoped (reuse the
--    RF-014/RF-015 resolver + scope helpers UNCHANGED). Satisfies the RF-019
--    default-deny presence detector. authenticated may SELECT in scope; ALL
--    direct writes are revoked (the SECURITY DEFINER RPC is the only writer).
-- ----------------------------------------------------------------------------
alter table orders               enable row level security;
alter table orders               force  row level security;
alter table order_items          enable row level security;
alter table order_items          force  row level security;
alter table order_item_modifiers enable row level security;
alter table order_item_modifiers force  row level security;

create policy orders_scoped on orders
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

create policy order_items_scoped on order_items
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

create policy order_item_modifiers_scoped on order_item_modifiers
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

-- ----------------------------------------------------------------------------
-- 6. Direct-write prevention (D-011). authenticated may SELECT in scope only;
--    INSERT/UPDATE/DELETE are revoked so a client CANNOT bypass app.submit_order.
--    The SECURITY DEFINER RPC (owned by the migration runner) writes. The full
--    per-command/role matrix is RF-059.
-- ----------------------------------------------------------------------------
grant select on orders               to authenticated;
grant select on order_items          to authenticated;
grant select on order_item_modifiers to authenticated;
revoke insert, update, delete on orders               from authenticated;
revoke insert, update, delete on order_items          from authenticated;
revoke insert, update, delete on order_item_modifiers from authenticated;

-- ----------------------------------------------------------------------------
-- 7. Money parse helper: read a jsonb money field as a NON-NEGATIVE INTEGER in
--    minor units, rejecting null/absent/non-number/non-integer/negative (42501).
--    No float ever enters the system. IMMUTABLE; GUC-free; no SECURITY DEFINER.
-- ----------------------------------------------------------------------------
create or replace function app.order_parse_minor(p_value jsonb, p_field text)
  returns bigint
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_txt text;
begin
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    raise exception 'submit_order: % is required', p_field using errcode = '42501';
  end if;
  if jsonb_typeof(p_value) <> 'number' then
    raise exception 'submit_order: % must be a number (integer minor units)', p_field using errcode = '42501';
  end if;
  v_txt := p_value::text;                 -- canonical jsonb number text, e.g. '1250' or '12.5'
  if v_txt !~ '^[0-9]+$' then             -- non-negative integer ONLY (no decimal/float/negative)
    raise exception 'submit_order: % must be a non-negative integer in minor units (got %)', p_field, v_txt using errcode = '42501';
  end if;
  return v_txt::bigint;
end;
$$;

comment on function app.order_parse_minor(jsonb, text) is
  'RF-052: reads a jsonb money field as a non-negative integer in minor units; rejects null/non-number/non-integer/negative (42501). Enforces D-007 (no float money) at the RPC boundary.';

revoke all on function app.order_parse_minor(jsonb, text) from public;

-- ----------------------------------------------------------------------------
-- 8. app.submit_order — the API_CONTRACT §4.1 SECURITY DEFINER RPC.
--    Validation order (RF051-B1): PIN session -> backing device session/pairing
--    -> device match -> membership active/role/scope -> payload -> money recompute
--    -> ONLY THEN idempotency replay -> insert. Actor + scope are derived from the
--    PIN session, never trusted from the client.
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
  select o.id, o.revision into v_existing_id, v_existing_rev
    from public.orders o
    where o.organization_id = v_org
      and o.device_id = p_device_id
      and o.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    return jsonb_build_object(
      'ok', true, 'order_id', v_existing_id, 'revision', v_existing_rev,
      'server_ts', now(), 'idempotency_replay', true);
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
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor, notes)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', v_line_disc, v_line_total,
      v_item ->> 'notes')
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
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int);
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

  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id, 'revision', 1,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'RF-052 (API_CONTRACT §4.1, D-011) SECURITY DEFINER RPC: persists a submitted order + items + modifiers. Authorizes via a VALID PIN session (actor + org/restaurant/branch derived server-side; cross-tenant impossible). Recomputes/validates totals from SUBMITTED SNAPSHOTS only (never the live menu; D-008); rejects mismatch/non-integer/negative money (D-007). Idempotent on (device_id, local_operation_id) with replay AFTER full validation (RF051-B1); a replay writes NO second audit row. Writes one append-only audit_events order.submitted row in the same transaction (D-013). order=submitted, items=pending; does NOT route to kitchen. receipt_number=RF-054.';

revoke all on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) from public;
grant execute on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz);
-- drop function if exists app.order_parse_minor(jsonb, text);
-- drop table if exists order_item_modifiers;
-- drop table if exists order_items;
-- drop table if exists orders;
-- ============================================================================
