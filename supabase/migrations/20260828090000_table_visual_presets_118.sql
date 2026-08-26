-- ============================================================================
-- TABLE-VISUAL-LAYOUT-118 — table visual presets + section floor presets
-- (D-001/D-011/D-012/D-013/D-017; RISK R-003)
--
-- WHAT. The saved floor layout (021/027) gains two ADDITIVE, nullable,
-- presentation-only keys:
--   * tables.visual_preset          — how ONE table is drawn (the client-owned
--                                     registry: classic_rect_table |
--                                     round_table | table_with_barrels |
--                                     booth_table; NULL = classic);
--   * table_sections.floor_preset   — how ONE section's floor is painted
--                                     (plain_light | wood_dark | tile_modern |
--                                     stone_neutral; NULL = plain light).
-- Both are validated STRUCTURALLY only (the `menu_categories.icon_key`
-- precedent: `^[a-z][a-z0-9_]{0,39}$`); the MEANING of a key is a client
-- registry so a newer client can add a look without a migration, and an
-- older client decodes an unknown key to its default.
--
-- A preset NEVER changes a table's footprint or its saved placement: every
-- shape is drawn inside the fixed 1500x2400 room-unit rect, so switching
-- presets never moves, re-scales or re-interprets layout_x/layout_y.
--
-- WRITES. Two DEDICATED setters mirroring app.set_table_layout_position
-- (target-row-first authorization, rank >= manager, RF-112 ledger
-- idempotency with the preset in the fingerprint, no-change = idempotent
-- success without audit, audited *_set / *_denied). app.upsert_table and
-- app.upsert_table_section stay UNTOUCHED (a stale full-replace client can
-- never erase a preset — the same reason the placement lives outside upsert).
--
-- READS (all additive; every existing key/meaning unchanged):
--   * app.list_tables   rows  += visual_preset; `sections` rows += floor_preset
--   * app.pos_tables    rows  += visual_preset, section_floor_preset
--   * app.kiosk_tables  rows  += layout_x, layout_y, visual_preset,
--                               section_floor_preset;
--                       envelope += floor_elements (the pos_tables fixture
--                               catalog, same nine keys)
--   The kiosk CONTRACT CHANGE is deliberate (owner request 118): the customer
--   floor renders the SAME room map as the POS/Dashboard, so it needs the
--   placement + fixtures. Still NOT served to the customer: the raw manual
--   status, order counts, link groups (kiosk_001 C6 keeps pinning those).
--
-- `tables` is a sync_pull entity (to_jsonb(t)); the new column rides along —
-- clients that do not know it ignore it. Sections/elements are pull-only via
-- the read RPCs above (unchanged posture). No realtime.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Columns (nullable, no backfill, no default — NULL means "the default
--    look" so a legacy row is byte-identical to today).
-- ----------------------------------------------------------------------------
alter table public.tables
  add column if not exists visual_preset text;
alter table public.tables
  drop constraint if exists tables_visual_preset_key_check;
alter table public.tables
  add constraint tables_visual_preset_key_check
  check (visual_preset is null or visual_preset ~ '^[a-z][a-z0-9_]{0,39}$');
comment on column public.tables.visual_preset is
  'TABLE-VISUAL-LAYOUT-118: presentation-only table shape key (client registry: classic_rect_table | round_table | table_with_barrels | booth_table). NULL = classic. Structurally validated only; never changes the footprint or placement.';

alter table public.table_sections
  add column if not exists floor_preset text;
alter table public.table_sections
  drop constraint if exists table_sections_floor_preset_key_check;
alter table public.table_sections
  add constraint table_sections_floor_preset_key_check
  check (floor_preset is null or floor_preset ~ '^[a-z][a-z0-9_]{0,39}$');
comment on column public.table_sections.floor_preset is
  'TABLE-VISUAL-LAYOUT-118: presentation-only floor style key of the section canvas (client registry: plain_light | wood_dark | tile_modern | stone_neutral). NULL = plain light. Structurally validated only.';

-- ----------------------------------------------------------------------------
-- 2. app.set_table_visual_preset — the ONLY writer of tables.visual_preset.
-- ----------------------------------------------------------------------------
create or replace function app.set_table_visual_preset(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_table_id          uuid,
  p_visual_preset     text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_preset  text := nullif(btrim(coalesce(p_visual_preset, '')), '');
  v_org     uuid;
  v_rest    uuid;
  v_branch  uuid;
  v_current text;
  v_rank    integer;
  v_fp      text;
  v_replay  jsonb;
  v_result  jsonb;
  v_old     jsonb;
  v_new     jsonb;
begin
  if v_actor is null then
    raise exception 'set_table_visual_preset: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_table_visual_preset: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_table_id is null then
    raise exception 'set_table_visual_preset: organization_id and table_id are required' using errcode = '42501';
  end if;
  -- the key contract, structurally mirrored by the CHECK constraint:
  if v_preset is not null and v_preset !~ '^[a-z][a-z0-9_]{0,39}$' then
    raise exception 'set_table_visual_preset: visual_preset must match ^[a-z][a-z0-9_]{0,39}$' using errcode = '42501';
  end if;

  select organization_id, restaurant_id, branch_id, visual_preset
    into v_org, v_rest, v_branch, v_current
    from public.tables where id = p_table_id and deleted_at is null;
  if v_org is null then
    raise exception 'set_table_visual_preset: table not found (or deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'set_table_visual_preset: table belongs to another organization' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', v_org, 'table', p_table_id,
              'visual_preset', v_preset)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_table_visual_preset', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'set_table_visual_preset: caller has no active membership covering the table scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'table.visual_preset_denied', null,
      jsonb_build_object('entity', 'table', 'id', p_table_id, 'visual_preset', v_preset));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table',
                'id', p_table_id, 'action', 'visual_preset_set',
                'visual_preset', v_preset);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_table_visual_preset', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- no-change is an idempotent success WITHOUT audit.
  if v_current is not distinct from v_preset then
    return v_result;
  end if;

  select to_jsonb(t) into v_old from public.tables t where t.id = p_table_id;
  update public.tables
     set visual_preset = v_preset
   where id = p_table_id;
  select to_jsonb(t) into v_new from public.tables t where t.id = p_table_id;
  perform app.management_audit(v_org, v_rest, v_branch, 'table.visual_preset_set', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_table_visual_preset(uuid, uuid, uuid, text) is
  'TABLE-VISUAL-LAYOUT-118: set (or clear with NULL/blank) a live table''s presentation-only visual_preset key (^[a-z][a-z0-9_]{0,39}$; the meaning is a client registry). Target-row-first authorization (rank >= manager); RF-112 ledger idempotency (preset in the fingerprint); no-change = idempotent success without audit; audits table.visual_preset_set (+_denied). Never touches placement or footprint.';

-- ----------------------------------------------------------------------------
-- 3. app.set_table_section_floor_preset — the ONLY writer of
--    table_sections.floor_preset.
-- ----------------------------------------------------------------------------
create or replace function app.set_table_section_floor_preset(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_section_id        uuid,
  p_floor_preset      text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_preset  text := nullif(btrim(coalesce(p_floor_preset, '')), '');
  v_org     uuid;
  v_rest    uuid;
  v_branch  uuid;
  v_current text;
  v_rank    integer;
  v_fp      text;
  v_replay  jsonb;
  v_result  jsonb;
  v_old     jsonb;
  v_new     jsonb;
begin
  if v_actor is null then
    raise exception 'set_table_section_floor_preset: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_table_section_floor_preset: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_section_id is null then
    raise exception 'set_table_section_floor_preset: organization_id and section_id are required' using errcode = '42501';
  end if;
  if v_preset is not null and v_preset !~ '^[a-z][a-z0-9_]{0,39}$' then
    raise exception 'set_table_section_floor_preset: floor_preset must match ^[a-z][a-z0-9_]{0,39}$' using errcode = '42501';
  end if;

  select organization_id, restaurant_id, branch_id, floor_preset
    into v_org, v_rest, v_branch, v_current
    from public.table_sections where id = p_section_id and deleted_at is null;
  if v_org is null then
    raise exception 'set_table_section_floor_preset: section not found (or deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'set_table_section_floor_preset: section belongs to another organization' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', v_org, 'section', p_section_id,
              'floor_preset', v_preset)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_table_section_floor_preset', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'set_table_section_floor_preset: caller has no active membership covering the section scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'table_section.floor_preset_denied', null,
      jsonb_build_object('entity', 'table_section', 'id', p_section_id, 'floor_preset', v_preset));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table_section');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table_section',
                'id', p_section_id, 'action', 'floor_preset_set',
                'floor_preset', v_preset);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_table_section_floor_preset', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_current is not distinct from v_preset then
    return v_result;
  end if;

  select to_jsonb(s) into v_old from public.table_sections s where s.id = p_section_id;
  update public.table_sections
     set floor_preset = v_preset, updated_at = now()
   where id = p_section_id;
  select to_jsonb(s) into v_new from public.table_sections s where s.id = p_section_id;
  perform app.management_audit(v_org, v_rest, v_branch, 'table_section.floor_preset_set', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_table_section_floor_preset(uuid, uuid, uuid, text) is
  'TABLE-VISUAL-LAYOUT-118: set (or clear with NULL/blank) a live section''s presentation-only floor_preset key (^[a-z][a-z0-9_]{0,39}$; the meaning is a client registry). Target-row-first authorization (rank >= manager); RF-112 ledger idempotency; no-change = idempotent success without audit; audits table_section.floor_preset_set (+_denied).';

-- ----------------------------------------------------------------------------
-- 4. app.list_tables — byte-faithful re-emit of the 20260815090000 (027) body
--    + `visual_preset` on rows + `floor_preset` on the sections catalog.
-- ----------------------------------------------------------------------------
create or replace function app.list_tables(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
  v_sections jsonb;
  v_elements jsonb;
begin
  if v_actor is null then
    raise exception 'list_tables: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'list_tables: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_tables: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area,
           'status', t.status, 'is_active', t.is_active, 'branch_id', t.branch_id,
           'active_order_count', coalesce(oc.n, 0),
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)),
           'group_id', gm.group_id,
           'section_id', t.section_id,
           'section_name', s.name,
           'section_display_order', s.display_order,
           'layout_x', t.layout_x,
           'layout_y', t.layout_y,
           -- 118: presentation-only shape key (NULL = classic).
           'visual_preset', t.visual_preset)
           order by t.label, t.id), '[]'::jsonb)
    into v_items
    from public.tables t
    left join public.table_group_members gm
      on gm.organization_id = t.organization_id and gm.table_id = t.id
    left join public.table_sections s
      on s.id = t.section_id and s.organization_id = t.organization_id
     and s.deleted_at is null
    left join (
      select o.branch_id, o.table_id, count(*)::int as n
        from public.orders o
        where o.organization_id = p_organization_id
          and (p_branch_id is null or o.branch_id = p_branch_id)
          -- REVIEW CORRECTION (B1): dine-in only — see pos_tables.
          and o.order_type      = 'dine_in'
          and o.table_id is not null
          and o.deleted_at is null
          and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')
        group by o.branch_id, o.table_id
    ) oc on oc.table_id = t.id and oc.branch_id = t.branch_id
    where t.organization_id = p_organization_id
      and t.restaurant_id   = p_restaurant_id
      and (p_branch_id is null or t.branch_id = p_branch_id)
      and t.deleted_at is null;

  -- TABLE-FLOOR-LAYOUT-021: the SECTION CATALOG rides along for the dashboard
  -- (empty sections must render as empty canvases; a per-row join cannot list
  -- them). 118: + floor_preset (NULL = plain light).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'name', s.name, 'display_order', s.display_order,
           'is_active', s.is_active, 'branch_id', s.branch_id,
           'floor_preset', s.floor_preset)
           order by s.display_order, s.name, s.id), '[]'::jsonb)
    into v_sections
    from public.table_sections s
    where s.organization_id = p_organization_id
      and s.restaurant_id   = p_restaurant_id
      and (p_branch_id is null or s.branch_id = p_branch_id)
      and s.deleted_at is null;

  -- TABLE-FLOOR-MAP-POLISH-027: the FIXTURE CATALOG rides along the same way
  -- (visual-only; the dashboard editor draws + edits them per section).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'section_id', e.section_id, 'kind', e.kind,
           'layout_x', e.layout_x, 'layout_y', e.layout_y,
           'width_norm', e.width_norm, 'height_norm', e.height_norm,
           'orientation_quarter_turns', e.orientation_quarter_turns,
           'label', e.label)
           order by e.created_at, e.id), '[]'::jsonb)
    into v_elements
    from public.table_floor_elements e
    join public.table_sections s
      on s.id = e.section_id and s.organization_id = e.organization_id
     and s.deleted_at is null
    where e.organization_id = p_organization_id
      and e.restaurant_id   = p_restaurant_id
      and (p_branch_id is null or e.branch_id = p_branch_id)
      and e.deleted_at is null;

  return jsonb_build_object('ok', true, 'entity', 'table', 'tables', v_items,
                            'sections', v_sections, 'floor_elements', v_elements);
end;
$$;

comment on function app.list_tables(uuid, uuid, uuid) is
  'GUC-free dining-table LIST for the owner/manager dashboard + PILOT-OPERATIONS-CORRECTIONS-001 (effective_state, group_id) + TABLE-FLOOR-LAYOUT-021 (section/layout keys + `sections` catalog) + TABLE-FLOOR-MAP-POLISH-027 (`floor_elements` catalog) + TABLE-VISUAL-LAYOUT-118 (rows gain `visual_preset`, sections gain `floor_preset`; both nullable presentation keys). Tombstones EXCLUDED, is_active=false INCLUDED (tables AND sections); read-only; scope-safe (R-003); money-free.';

-- ----------------------------------------------------------------------------
-- 5. app.pos_tables — byte-faithful re-emit of the 027 body + `visual_preset`
--    and `section_floor_preset` on rows (no section catalog on this wire: the
--    POS derives its sections from the rows, so the section's floor rides on
--    each of its rows).
-- ----------------------------------------------------------------------------
create or replace function app.pos_tables(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_dsid       uuid;
  v_emp        uuid;
  v_membership uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_tables     jsonb;
  v_elements   jsonb;
begin
  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'pos_tables: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'pos_tables: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_tables: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'pos_tables: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_tables: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) the SESSION branch's live, active tables. Money-free by nature — every
  --     PIN role (kitchen included) receives the same rows (no redaction).
  --     RESTAURANT-OPERATIONS-V1-001: active_order_count = DERIVED occupancy.
  --     TABLE-FLOOR-LAYOUT-021: section_id/section_name/section_display_order
  --     + layout_x/layout_y ADDED (all nullable; a legacy row simply carries
  --     nulls and the client keeps its area-text fallback zone). The joined
  --     section is live-only: a tombstoned section can no longer be referenced
  --     (delete detaches), so the join is belt-and-braces.
  --     118: visual_preset + section_floor_preset (nullable presentation keys).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area, 'status', t.status,
           'active_order_count', coalesce(oc.n, 0),
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)),
           'group_id', gm.group_id,
           'section_id', t.section_id,
           'section_name', s.name,
           'section_display_order', s.display_order,
           'layout_x', t.layout_x,
           'layout_y', t.layout_y,
           'visual_preset', t.visual_preset,
           'section_floor_preset', s.floor_preset)
           order by t.label, t.id), '[]'::jsonb)
    into v_tables
    from public.tables t
    left join public.table_group_members gm
      on gm.organization_id = t.organization_id and gm.table_id = t.id
    left join public.table_sections s
      on s.id = t.section_id and s.organization_id = t.organization_id
     and s.deleted_at is null
    left join (
      select o.table_id, count(*)::int as n
        from public.orders o
        where o.organization_id = v_org
          and o.branch_id       = v_branch
          -- REVIEW CORRECTION (B1): only DINE-IN orders occupy a table.
          -- Historical takeaway rows may carry a table_id from the pre-phase
          -- contract; they must never count toward floor occupancy.
          and o.order_type      = 'dine_in'
          and o.table_id is not null
          and o.deleted_at is null
          and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')
        group by o.table_id
    ) oc on oc.table_id = t.id
    where t.organization_id = v_org
      and t.restaurant_id   = v_rest
      and t.branch_id       = v_branch
      and t.is_active
      and t.deleted_at is null;

  -- TABLE-FLOOR-MAP-POLISH-027: the branch's live fixtures ride along as a
  -- CATALOG array (visual-only; money-free; same rows for every PIN role).
  -- Live-section join is belt-and-braces: section delete tombstones fixtures.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'section_id', e.section_id, 'kind', e.kind,
           'layout_x', e.layout_x, 'layout_y', e.layout_y,
           'width_norm', e.width_norm, 'height_norm', e.height_norm,
           'orientation_quarter_turns', e.orientation_quarter_turns,
           'label', e.label)
           order by e.created_at, e.id), '[]'::jsonb)
    into v_elements
    from public.table_floor_elements e
    join public.table_sections s
      on s.id = e.section_id and s.organization_id = e.organization_id
     and s.deleted_at is null
    where e.organization_id = v_org
      and e.restaurant_id   = v_rest
      and e.branch_id       = v_branch
      and e.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'tables',
    'tables', v_tables,
    'floor_elements', v_elements,
    'server_ts', now());
end;
$$;

comment on function app.pos_tables(uuid, uuid) is
  'POS/KDS device table read (session-derived scope, 42501 fail-closed) + PILOT-OPERATIONS-CORRECTIONS-001 (effective_state, group_id) + TABLE-FLOOR-LAYOUT-021 (section/layout keys) + TABLE-FLOOR-MAP-POLISH-027 (`floor_elements` catalog) + TABLE-VISUAL-LAYOUT-118: rows gain `visual_preset` + `section_floor_preset` (nullable presentation keys; the owning section''s floor rides on each row because this wire ships no section catalog). Every prior key unchanged. Money-free; all PIN roles.';

-- ----------------------------------------------------------------------------
-- 6. app.kiosk_tables — re-emit of the 20260821090000 body + the placement
--    (layout_x/layout_y), the presentation keys and the fixture catalog, so
--    the customer floor renders the SAME room map as the POS/Dashboard.
--    STILL withheld: raw manual status, order counts, link groups.
-- ----------------------------------------------------------------------------
create or replace function app.kiosk_tables(
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
  v_sid      uuid;
  v_org      uuid;
  v_rest     uuid;
  v_branch   uuid;
  v_tables   jsonb;
  v_elements jsonb;
begin
  select o_session, o_org, o_rest, o_branch
    into v_sid, v_org, v_rest, v_branch
    from app.kiosk_session_context(p_device_id, p_session_token);
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kiosk_tables');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area,
           'section_id', t.section_id,
           'section_name', s.name,
           'section_display_order', s.display_order,
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)),
           -- 118: the SAME saved placement + presentation keys the POS reads
           -- (physical room units; nullable — an unplaced table stays in the
           -- kiosk's list strip).
           'layout_x', t.layout_x,
           'layout_y', t.layout_y,
           'visual_preset', t.visual_preset,
           'section_floor_preset', s.floor_preset)
           order by t.label, t.id), '[]'::jsonb)
    into v_tables
    from public.tables t
    left join public.table_sections s
      on s.id = t.section_id and s.organization_id = t.organization_id
     and s.deleted_at is null
    left join (
      select o.table_id, count(*)::int as n
        from public.orders o
        where o.organization_id = v_org
          and o.branch_id       = v_branch
          and o.order_type      = 'dine_in'
          and o.table_id is not null
          and o.deleted_at is null
          and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')
        group by o.table_id
    ) oc on oc.table_id = t.id
    where t.organization_id = v_org
      and t.restaurant_id   = v_rest
      and t.branch_id       = v_branch
      and t.is_active
      and t.deleted_at is null;

  -- 118: the branch's live VISUAL fixtures (the pos_tables catalog verbatim —
  -- walls/doors/windows/cashier/plants; decoration only, never a table).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'section_id', e.section_id, 'kind', e.kind,
           'layout_x', e.layout_x, 'layout_y', e.layout_y,
           'width_norm', e.width_norm, 'height_norm', e.height_norm,
           'orientation_quarter_turns', e.orientation_quarter_turns,
           'label', e.label)
           order by e.created_at, e.id), '[]'::jsonb)
    into v_elements
    from public.table_floor_elements e
    join public.table_sections s
      on s.id = e.section_id and s.organization_id = e.organization_id
     and s.deleted_at is null
    where e.organization_id = v_org
      and e.restaurant_id   = v_rest
      and e.branch_id       = v_branch
      and e.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'kiosk_tables',
    'tables', v_tables,
    'floor_elements', v_elements,
    'server_ts', now());
end;
$$;

comment on function app.kiosk_tables(uuid, text) is
  'KIOSK-001 Phase 2 + TABLE-VISUAL-LAYOUT-118: token-proven CUSTOMER table read for a kiosk device (device_type=kiosk only; scope session-derived). Serves section/zone identity + label/seats + the canonical effective_state, PLUS (118) the saved placement (layout_x/layout_y), the presentation keys (visual_preset, section_floor_preset) and the `floor_elements` fixture catalog so the customer floor is the SAME room map as the POS/Dashboard. Still NOT served: manual status, order counts, customer/order details, link groups. Display truth only; NO hold/claim happens here. invalid_session envelope on any proof failure.';

-- ----------------------------------------------------------------------------
-- 7. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 / RF-160 pattern).
-- ----------------------------------------------------------------------------
create or replace function public.set_table_visual_preset(
  p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_visual_preset text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_table_visual_preset(p_client_request_id, p_organization_id, p_table_id, p_visual_preset); $$;

create or replace function public.set_table_section_floor_preset(
  p_client_request_id uuid, p_organization_id uuid, p_section_id uuid, p_floor_preset text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_table_section_floor_preset(p_client_request_id, p_organization_id, p_section_id, p_floor_preset); $$;

comment on function public.set_table_visual_preset(uuid, uuid, uuid, text) is
  'TABLE-VISUAL-LAYOUT-118 pass-through wrapper for app.set_table_visual_preset (SECURITY INVOKER; authorization inside app.*).';
comment on function public.set_table_section_floor_preset(uuid, uuid, uuid, text) is
  'TABLE-VISUAL-LAYOUT-118 pass-through wrapper for app.set_table_section_floor_preset (SECURITY INVOKER; authorization inside app.*).';

-- ----------------------------------------------------------------------------
-- 8. Grants: authenticated only (never anon / service_role; D-011).
-- ----------------------------------------------------------------------------
revoke all on function app.set_table_visual_preset(uuid, uuid, uuid, text)         from public;
revoke all on function app.set_table_section_floor_preset(uuid, uuid, uuid, text)  from public;
grant execute on function app.set_table_visual_preset(uuid, uuid, uuid, text)         to authenticated;
grant execute on function app.set_table_section_floor_preset(uuid, uuid, uuid, text)  to authenticated;

revoke all on function public.set_table_visual_preset(uuid, uuid, uuid, text)         from public;
revoke all on function public.set_table_section_floor_preset(uuid, uuid, uuid, text)  from public;
grant execute on function public.set_table_visual_preset(uuid, uuid, uuid, text)         to authenticated;
grant execute on function public.set_table_section_floor_preset(uuid, uuid, uuid, text)  to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function public.set_table_section_floor_preset(uuid, uuid, uuid, text);
--   drop function public.set_table_visual_preset(uuid, uuid, uuid, text);
--   drop function app.set_table_section_floor_preset(uuid, uuid, uuid, text);
--   drop function app.set_table_visual_preset(uuid, uuid, uuid, text);
--   (re-emit the 20260815090000 bodies of app.list_tables / app.pos_tables and
--    the 20260821090000 body of app.kiosk_tables)
--   alter table table_sections drop column floor_preset;
--   alter table tables drop column visual_preset;
-- ============================================================================
