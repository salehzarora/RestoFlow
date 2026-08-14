-- ============================================================================
-- TABLE-FLOOR-MAP-POLISH-027 — visual-only floor FIXTURES (walls, doors,
-- windows, cashier stands, plants) on the section canvases.
--
-- Owner decision (027 §4): fixture kinds are EXACTLY wall/door/window/cashier/
-- plant; labels exist only for cashier + door. Fixtures are pure decoration —
-- they carry NO occupancy, NO orders, NO money, and no client may ever treat
-- one as a table. ADDITIVE-ONLY:
--
--   * `table_floor_elements` — a section-scoped catalog of fixtures. Same
--     normalized coordinate space as `tables.layout_x/layout_y` (0..10000 per
--     axis, PHYSICAL room, never mirrored for RTL) plus a normalized footprint
--     (width_norm/height_norm, same units) and a quarter-turn orientation.
--   * `app.upsert_floor_element` / `app.delete_floor_element` — manager+ RPCs
--     on the RF-112 management template (ledger idempotency, committed
--     *_denied audits, target-row-first authorization).
--   * `app.pos_tables` / `app.list_tables` — re-emitted FAITHFULLY (forward-
--     only; shipped migrations untouched) with ONE new top-level envelope key,
--     `floor_elements` (a catalog array, NOT per-table-row keys — the per-row
--     shape is pinned by older suites and stays byte-identical). Old clients
--     ignore unknown envelope keys.
--   * `app.soft_delete_table_section` — re-emitted to ALSO tombstone the
--     section's fixtures (tables are still only DETACHED, never deleted).
--
-- No sync-pull changes: fixtures reach devices through the pos_tables read
-- (V1 owner decision — a fresh read accompanies every floor render).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. table_floor_elements — the section-scoped fixture catalog (the
--    `table_sections` shape: composite same-branch FK, tombstones, RLS-denied
--    direct writes).
-- ----------------------------------------------------------------------------
create table table_floor_elements (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null references organizations (id) on delete restrict,
  restaurant_id   uuid        not null,
  branch_id       uuid        not null,
  section_id      uuid        not null,
  kind            text        not null check (kind in ('wall', 'door', 'window', 'cashier', 'plant')),
  layout_x        integer     not null check (layout_x >= 0 and layout_x <= 10000),
  layout_y        integer     not null check (layout_y >= 0 and layout_y <= 10000),
  width_norm      integer     not null check (width_norm  >= 100 and width_norm  <= 10000),
  height_norm     integer     not null check (height_norm >= 100 and height_norm <= 10000),
  orientation_quarter_turns integer not null default 0
    check (orientation_quarter_turns >= 0 and orientation_quarter_turns <= 3),
  label           text        check (label is null or (kind in ('cashier', 'door') and length(btrim(label)) > 0)),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  -- a fixture's section is STRUCTURALLY same-org/restaurant/branch (D-012 layer 4).
  foreign key (organization_id, restaurant_id, branch_id, section_id)
    references table_sections (organization_id, restaurant_id, branch_id, id)
    on delete restrict
);

comment on table table_floor_elements is
  'TABLE-FLOOR-MAP-POLISH-027: a VISUAL-ONLY floor fixture (wall/door/window/cashier/plant) on a section canvas. Shares the tables.layout_x/layout_y normalized 0..10000 coordinate space (physical room; never RTL-mirrored) plus a normalized footprint and quarter-turn orientation. Labels only on cashier/door (owner decision 4). NO occupancy, NO orders, NO money (D-007 vacuously safe). Writes are manager+ RPCs only (D-011); direct DML is RLS-denied + unGRANTed; deleted_at = sync tombstone (D-020). Deleting a section tombstones its fixtures (tables are merely detached).';
comment on column table_floor_elements.width_norm is
  'Normalized footprint width in canvas x-units (0..10000 = full canvas width), BEFORE orientation is applied. Bounds are structural; per-kind fixed sizes are RPC policy.';
comment on column table_floor_elements.orientation_quarter_turns is
  'Clockwise quarter turns (0..3) applied at render time; width/height stay stored unrotated.';

create index table_floor_elements_scope_idx
  on table_floor_elements (organization_id, restaurant_id, branch_id)
  where deleted_at is null;

create index table_floor_elements_section_idx
  on table_floor_elements (organization_id, section_id)
  where deleted_at is null;

create trigger table_floor_elements_set_updated_at before update on table_floor_elements
  for each row execute function app.set_updated_at();

alter table table_floor_elements enable row level security;
alter table table_floor_elements force  row level security;

create policy table_floor_elements_sel on table_floor_elements for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy table_floor_elements_ins_deny on table_floor_elements for insert to authenticated with check (false);
create policy table_floor_elements_upd_deny on table_floor_elements for update to authenticated using (false) with check (false);
create policy table_floor_elements_del_deny on table_floor_elements for delete to authenticated using (false);

grant select on table_floor_elements to authenticated;   -- reads only; writes are NEVER granted

-- ----------------------------------------------------------------------------
-- 2. app.upsert_floor_element — create/edit a fixture (manager+; idempotent;
--    audited). Per-kind geometry POLICY lives here (bounds are table CHECKs):
--      * defaults when unspecified: wall 3000x150, window 2000x150,
--        door 900x150, cashier 900x900, plant 900x900;
--      * wall/window are freely resizable within bounds;
--      * door/cashier/plant are FIXED-SIZE (owner decision 4) — a differing
--        explicit size is refused, never silently corrected;
--      * labels only on cashier/door; blank trims to null.
--    kind / section / org / restaurant / branch are IMMUTABLE on update: a
--    fixture is deleted + recreated to change them (keeps audits honest).
-- ----------------------------------------------------------------------------
create or replace function app.upsert_floor_element(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_section_id        uuid,
  p_kind              text,
  p_id                uuid    default null,
  p_layout_x          integer default null,
  p_layout_y          integer default null,
  p_width_norm        integer default null,
  p_height_norm       integer default null,
  p_orientation_quarter_turns integer default 0,
  p_label             text    default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid := app.current_app_user_id();
  v_label        text := nullif(btrim(coalesce(p_label, '')), '');
  v_orient       integer := coalesce(p_orientation_quarter_turns, 0);
  v_def_w        integer;
  v_def_h        integer;
  v_w            integer;
  v_h            integer;
  v_found_org    uuid;
  v_found_sect   uuid;
  v_found_kind   text;
  v_id           uuid;
  v_action       text;
  v_rank         integer;
  v_fp           text;
  v_replay       jsonb;
  v_result       jsonb;
  v_old          jsonb;
  v_new          jsonb;
begin
  if v_actor is null then
    raise exception 'upsert_floor_element: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'upsert_floor_element: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null or p_section_id is null then
    raise exception 'upsert_floor_element: organization_id, restaurant_id, branch_id and section_id are required' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('wall', 'door', 'window', 'cashier', 'plant') then
    raise exception 'upsert_floor_element: kind must be one of wall/door/window/cashier/plant' using errcode = '42501';
  end if;
  if p_layout_x is null or p_layout_y is null
     or p_layout_x < 0 or p_layout_x > 10000 or p_layout_y < 0 or p_layout_y > 10000 then
    raise exception 'upsert_floor_element: layout_x and layout_y are required in 0..10000' using errcode = '42501';
  end if;
  if v_orient < 0 or v_orient > 3 then
    raise exception 'upsert_floor_element: orientation_quarter_turns must be 0..3' using errcode = '42501';
  end if;
  if v_label is not null and p_kind not in ('cashier', 'door') then
    raise exception 'upsert_floor_element: labels exist only on cashier/door fixtures' using errcode = '42501';
  end if;

  -- per-kind geometry policy (defaults + who may resize).
  select case p_kind when 'wall' then 3000 when 'window' then 2000 else 900 end,
         case p_kind when 'cashier' then 900 when 'plant' then 900 else 150 end
    into v_def_w, v_def_h;
  v_w := coalesce(p_width_norm,  v_def_w);
  v_h := coalesce(p_height_norm, v_def_h);
  if p_kind in ('wall', 'window') then
    if v_w < 100 or v_w > 10000 or v_h < 100 or v_h > 10000 then
      raise exception 'upsert_floor_element: width/height must be 100..10000' using errcode = '42501';
    end if;
  elsif v_w <> v_def_w or v_h <> v_def_h then
    raise exception 'upsert_floor_element: % fixtures are fixed-size (%x%)', p_kind, v_def_w, v_def_h
      using errcode = '42501';
  end if;

  -- the target SECTION first: it anchors org/restaurant/branch structurally.
  if not exists (
       select 1 from public.table_sections s
       where s.id = p_section_id and s.organization_id = p_organization_id
         and s.restaurant_id = p_restaurant_id and s.branch_id = p_branch_id
         and s.deleted_at is null) then
    raise exception 'upsert_floor_element: section not found in organization/restaurant/branch or is soft-deleted' using errcode = '42501';
  end if;

  if p_id is not null then
    select organization_id, section_id, kind into v_found_org, v_found_sect, v_found_kind
      from public.table_floor_elements where id = p_id and deleted_at is null;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'upsert_floor_element: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_sect is distinct from p_section_id then
        raise exception 'upsert_floor_element: section is immutable on update (delete + recreate to move sections)' using errcode = '42501';
      end if;
      if v_found_kind is distinct from p_kind then
        raise exception 'upsert_floor_element: kind is immutable on update (delete + recreate to change kind)' using errcode = '42501';
      end if;
    end if;
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'section', p_section_id, 'id', p_id, 'kind', p_kind,
              'x', p_layout_x, 'y', p_layout_y, 'w', v_w, 'h', v_h,
              'orient', v_orient, 'label', v_label)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'upsert_floor_element', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'upsert_floor_element: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'floor_element.upsert_denied', null,
      jsonb_build_object('entity', 'floor_element', 'id', p_id, 'kind', p_kind, 'section_id', p_section_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'floor_element');
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    v_action := 'created';
  else
    v_id := p_id;
    v_action := 'updated';
  end if;
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'floor_element',
                'id', v_id, 'action', v_action);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'upsert_floor_element', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_action = 'created' then
    insert into public.table_floor_elements
      (id, organization_id, restaurant_id, branch_id, section_id, kind,
       layout_x, layout_y, width_norm, height_norm, orientation_quarter_turns, label)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_section_id, p_kind,
       p_layout_x, p_layout_y, v_w, v_h, v_orient, v_label);
  else
    select to_jsonb(e) into v_old from public.table_floor_elements e where e.id = v_id;
    update public.table_floor_elements set
      layout_x = p_layout_x, layout_y = p_layout_y,
      width_norm = v_w, height_norm = v_h,
      orientation_quarter_turns = v_orient, label = v_label
    where id = v_id;
  end if;

  select to_jsonb(e) into v_new from public.table_floor_elements e where e.id = v_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'floor_element.' || v_action, v_old, v_new);
  return v_result;
end;
$$;

comment on function app.upsert_floor_element(uuid, uuid, uuid, uuid, uuid, text, uuid, integer, integer, integer, integer, integer, text) is
  'TABLE-FLOOR-MAP-POLISH-027: create/edit a visual-only floor fixture as a dashboard manager+. The upsert_table_section template: GUC-free rank over the PASSED scope; 42501 structural failures; in-scope rank-1 -> committed floor_element.upsert_denied + permission_denied; RF-112 ledger idempotency. Per-kind geometry policy (wall/window resizable; door/cashier/plant fixed-size; labels only cashier/door). kind + section immutable on update. Audits floor_element.created/updated.';

-- ----------------------------------------------------------------------------
-- 3. app.delete_floor_element — tombstone a fixture (manager+; idempotent;
--    audited; target-row-first).
-- ----------------------------------------------------------------------------
create or replace function app.delete_floor_element(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_element_id        uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_org    uuid;
  v_rest   uuid;
  v_branch uuid;
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
begin
  if v_actor is null then
    raise exception 'delete_floor_element: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'delete_floor_element: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_element_id is null then
    raise exception 'delete_floor_element: organization_id and element_id are required' using errcode = '42501';
  end if;

  -- Ledger FIRST (unlike the section delete): the fingerprint needs only the
  -- passed identifiers, so a replay AFTER the tombstone still returns the
  -- stored result instead of tripping the target-row-first 42501.
  v_fp := md5(jsonb_build_object('org', p_organization_id, 'element', p_element_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'delete_floor_element', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  select organization_id, restaurant_id, branch_id into v_org, v_rest, v_branch
    from public.table_floor_elements where id = p_element_id and deleted_at is null;
  if v_org is null then
    raise exception 'delete_floor_element: element not found (or already deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'delete_floor_element: element belongs to another organization' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'delete_floor_element: caller has no active membership covering the element scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'floor_element.delete_denied', null, jsonb_build_object('entity', 'floor_element', 'id', p_element_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'floor_element');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'floor_element',
                'id', p_element_id, 'action', 'deleted');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'delete_floor_element', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(e) into v_old from public.table_floor_elements e where e.id = p_element_id;
  update public.table_floor_elements set deleted_at = now() where id = p_element_id;

  perform app.management_audit(v_org, v_rest, v_branch, 'floor_element.deleted', v_old,
    jsonb_build_object('id', p_element_id, 'deleted', true));
  return v_result;
end;
$$;

comment on function app.delete_floor_element(uuid, uuid, uuid) is
  'TABLE-FLOOR-MAP-POLISH-027: tombstone a visual-only floor fixture as a dashboard manager+ (soft_delete_table_section template: target-row-first 42501; in-scope rank-1 -> committed floor_element.delete_denied + permission_denied; RF-112 ledger idempotency). Audits floor_element.deleted.';

-- ----------------------------------------------------------------------------
-- 4. app.soft_delete_table_section — CREATE OR REPLACE (keep ACLs). The 021
--    body VERBATIM plus ONE addition: the section's live fixtures are
--    tombstoned (tables are still only DETACHED). The result envelope is
--    unchanged (replay-safe); the audit payload gains elements_removed.
-- ----------------------------------------------------------------------------
create or replace function app.soft_delete_table_section(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_section_id        uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor    uuid := app.current_app_user_id();
  v_org      uuid;
  v_rest     uuid;
  v_branch   uuid;
  v_rank     integer;
  v_fp       text;
  v_replay   jsonb;
  v_result   jsonb;
  v_old      jsonb;
  v_detached integer;
  v_elements integer;
begin
  if v_actor is null then
    raise exception 'soft_delete_table_section: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'soft_delete_table_section: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_section_id is null then
    raise exception 'soft_delete_table_section: organization_id and section_id are required' using errcode = '42501';
  end if;

  select organization_id, restaurant_id, branch_id into v_org, v_rest, v_branch
    from public.table_sections where id = p_section_id and deleted_at is null;
  if v_org is null then
    raise exception 'soft_delete_table_section: section not found (or already deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'soft_delete_table_section: section belongs to another organization' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', v_org, 'section', p_section_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'soft_delete_table_section', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'soft_delete_table_section: caller has no active membership covering the section scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'table_section.delete_denied', null, jsonb_build_object('entity', 'table_section', 'id', p_section_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table_section');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table_section',
                'id', p_section_id, 'action', 'deleted');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'soft_delete_table_section', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(s) into v_old from public.table_sections s where s.id = p_section_id;

  -- DETACH FIRST (order matters for the composite FK): the tables stay live,
  -- losing only their section + placement, then the section is tombstoned.
  update public.tables
     set section_id = null, layout_x = null, layout_y = null
   where organization_id = v_org and section_id = p_section_id and deleted_at is null;
  get diagnostics v_detached = row_count;

  -- TABLE-FLOOR-MAP-POLISH-027: fixtures are section-owned decoration — a
  -- deleted section takes its fixtures with it (tombstoned, never orphaned).
  update public.table_floor_elements
     set deleted_at = now()
   where organization_id = v_org and section_id = p_section_id and deleted_at is null;
  get diagnostics v_elements = row_count;

  update public.table_sections set deleted_at = now() where id = p_section_id;

  perform app.management_audit(v_org, v_rest, v_branch, 'table_section.deleted', v_old,
    jsonb_build_object('id', p_section_id, 'deleted', true, 'tables_detached', v_detached,
                       'elements_removed', v_elements));
  return v_result;
end;
$$;

comment on function app.soft_delete_table_section(uuid, uuid, uuid) is
  'TABLE-FLOOR-LAYOUT-021 (D-033): tombstone a dining section as a dashboard manager+ and DETACH its tables (section_id + layout cleared; tables are never deleted). TABLE-FLOOR-MAP-POLISH-027: the section''s visual fixtures are additionally tombstoned (elements_removed in the audit payload). RF-112 ledger idempotency; committed table_section.delete_denied on in-scope rank-1; 42501 structural failures.';

-- ----------------------------------------------------------------------------
-- 5. app.pos_tables — CREATE OR REPLACE (keep ACLs). The 021 body VERBATIM
--    plus ONE new top-level envelope key, `floor_elements` (a catalog array;
--    per-table-row keys are UNCHANGED — older suites pin that shape).
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
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area, 'status', t.status,
           'active_order_count', coalesce(oc.n, 0),
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)),
           'group_id', gm.group_id,
           'section_id', t.section_id,
           'section_name', s.name,
           'section_display_order', s.display_order,
           'layout_x', t.layout_x,
           'layout_y', t.layout_y)
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
  'POS/KDS device table read (session-derived scope, 42501 fail-closed) + PILOT-OPERATIONS-CORRECTIONS-001 (effective_state, group_id) + TABLE-FLOOR-LAYOUT-021 (section/layout keys) + TABLE-FLOOR-MAP-POLISH-027: the envelope gains a `floor_elements` catalog array (live visual fixtures of the session branch). Every prior key AND the per-table row shape unchanged. Money-free; all PIN roles.';

-- ----------------------------------------------------------------------------
-- 6. app.list_tables — CREATE OR REPLACE (keep ACLs). The 021 body VERBATIM
--    plus the same new `floor_elements` envelope key.
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
           'layout_y', t.layout_y)
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
  -- them). A NEW top-level key — every existing key/meaning is unchanged, and
  -- old clients ignore unknown keys.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'name', s.name, 'display_order', s.display_order,
           'is_active', s.is_active, 'branch_id', s.branch_id)
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
  'GUC-free dining-table LIST for the owner/manager dashboard + PILOT-OPERATIONS-CORRECTIONS-001 (effective_state, group_id) + TABLE-FLOOR-LAYOUT-021 (section/layout keys + `sections` catalog) + TABLE-FLOOR-MAP-POLISH-027: the envelope additionally gains a `floor_elements` catalog array (live visual fixtures of the scope). Tombstones EXCLUDED, is_active=false INCLUDED (tables AND sections); read-only; scope-safe (R-003); money-free.';

-- ----------------------------------------------------------------------------
-- 7. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 / RF-160 pattern).
-- ----------------------------------------------------------------------------
create or replace function public.upsert_floor_element(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_section_id uuid, p_kind text, p_id uuid default null,
  p_layout_x integer default null, p_layout_y integer default null,
  p_width_norm integer default null, p_height_norm integer default null,
  p_orientation_quarter_turns integer default 0, p_label text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.upsert_floor_element(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_section_id, p_kind, p_id, p_layout_x, p_layout_y, p_width_norm, p_height_norm, p_orientation_quarter_turns, p_label); $$;

create or replace function public.delete_floor_element(
  p_client_request_id uuid, p_organization_id uuid, p_element_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.delete_floor_element(p_client_request_id, p_organization_id, p_element_id); $$;

-- ----------------------------------------------------------------------------
-- 8. Grants: authenticated only (never anon / service_role; D-011).
-- ----------------------------------------------------------------------------
revoke all on function app.upsert_floor_element(uuid, uuid, uuid, uuid, uuid, text, uuid, integer, integer, integer, integer, integer, text) from public;
revoke all on function app.delete_floor_element(uuid, uuid, uuid)                                                                           from public;
grant execute on function app.upsert_floor_element(uuid, uuid, uuid, uuid, uuid, text, uuid, integer, integer, integer, integer, integer, text) to authenticated;
grant execute on function app.delete_floor_element(uuid, uuid, uuid)                                                                            to authenticated;

revoke all on function public.upsert_floor_element(uuid, uuid, uuid, uuid, uuid, text, uuid, integer, integer, integer, integer, integer, text) from public;
revoke all on function public.delete_floor_element(uuid, uuid, uuid)                                                                            from public;
grant execute on function public.upsert_floor_element(uuid, uuid, uuid, uuid, uuid, text, uuid, integer, integer, integer, integer, integer, text) to authenticated;
grant execute on function public.delete_floor_element(uuid, uuid, uuid)                                                                            to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function public.delete_floor_element(uuid, uuid, uuid);
--   drop function public.upsert_floor_element(uuid, uuid, uuid, uuid, uuid, text, uuid, integer, integer, integer, integer, integer, text);
--   drop function app.delete_floor_element(uuid, uuid, uuid);
--   drop function app.upsert_floor_element(uuid, uuid, uuid, uuid, uuid, text, uuid, integer, integer, integer, integer, integer, text);
--   (re-emit the 20260814090000 bodies of app.pos_tables / app.list_tables /
--    app.soft_delete_table_section)
--   drop table table_floor_elements;
-- ============================================================================
