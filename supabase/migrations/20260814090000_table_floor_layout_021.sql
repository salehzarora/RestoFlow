-- ============================================================================
-- TABLE-FLOOR-LAYOUT-021 — first-class dining SECTIONS + freeform table layout.
--
-- The POS floor map today groups tables by the free-text `tables.area` column:
-- no owner-controlled naming, ordering, or placement. This migration makes the
-- floor REAL and ADDITIVE-ONLY:
--
--   * `table_sections`  — a branch-scoped catalog of dining sections (Main
--     hall / Terrace / Second floor ...), owner-named and owner-ordered.
--   * `tables.section_id`             — which section a table sits in (nullable;
--     null = legacy/unsectioned, the client keeps today's area-text fallback).
--   * `tables.layout_x` / `layout_y`  — the table's NORMALIZED position inside
--     its section canvas: integers 0..10000 on each axis (never viewport
--     pixels). Both null or both set; meaningful only with a section. The
--     coordinates describe the PHYSICAL room — clients must NOT mirror them
--     for RTL locales (text localizes, the room does not flip).
--
-- `tables.area` is untouched and stays the legacy fallback. No backfill is
-- performed (owner decision: sections start empty and are assigned by hand).
--
-- WRITE PATHS: five new manager+ RPCs following the RF-112 management template
-- (ledger idempotency where a client_request_id travels, committed *_denied
-- audits, target-row-first authorization). `app.upsert_table` is DELIBERATELY
-- not extended: its full-replace semantics would let a stale client erase
-- layout metadata, so layout has its own dedicated setters instead (the same
-- reasoning that keeps `status` out of upsert).
--
-- READ PATHS: app.pos_tables / app.list_tables are re-emitted FAITHFULLY (this
-- file, forward-only; shipped migrations untouched) with five new named keys —
-- section_id, section_name, section_display_order, layout_x, layout_y (plus
-- section_is_active on the management read) — and every existing key/meaning
-- preserved byte-for-byte for old clients. Devices additionally receive the new
-- columns through sync_pull automatically (full-row jsonb; additive).
--
-- Section soft-delete NEVER deletes tables: affected tables are DETACHED
-- (section_id + layout cleared) so they fall back to the legacy zone.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. table_sections — the branch-scoped section catalog (the `tables` shape:
--    composite same-org FK to branches, live-name uniqueness, tombstones).
-- ----------------------------------------------------------------------------
create table table_sections (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null references organizations (id) on delete restrict,
  restaurant_id   uuid        not null,
  branch_id       uuid        not null,
  name            text        not null check (length(btrim(name)) > 0),
  display_order   integer     not null default 0,
  is_active       boolean     not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  primary key (id),
  unique (organization_id, id),
  -- the composite key `tables.section_id` FKs against below: a section
  -- reference is STRUCTURALLY same-org/restaurant/branch (D-012 layer 4).
  unique (organization_id, restaurant_id, branch_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table table_sections is
  'TABLE-FLOOR-LAYOUT-021 (DOMAIN_MODEL §5.1 adjunct): a dining section / floor area at a branch (Main hall, Terrace, ...). Owner-named + owner-ordered (display_order); is_active = configuration switch; deleted_at = sync tombstone (D-020). One LIVE name per branch (case-insensitive). NO money columns. Writes are manager+ RPCs only (D-011); direct DML is RLS-denied + unGRANTed. Tables reference a section via tables.section_id; deleting a section DETACHES its tables (never deletes them).';
comment on column table_sections.display_order is
  'Owner-controlled vertical order of the section blocks on every floor map (0-based, reorder_table_sections).';

create unique index table_sections_branch_live_name_key
  on table_sections (organization_id, restaurant_id, branch_id, lower(name))
  where deleted_at is null;

create index table_sections_org_rest_branch_idx
  on table_sections (organization_id, restaurant_id, branch_id);

create trigger table_sections_set_updated_at before update on table_sections
  for each row execute function app.set_updated_at();

alter table table_sections enable row level security;
alter table table_sections force  row level security;

create policy table_sections_sel on table_sections for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy table_sections_ins_deny on table_sections for insert to authenticated with check (false);
create policy table_sections_upd_deny on table_sections for update to authenticated using (false) with check (false);
create policy table_sections_del_deny on table_sections for delete to authenticated using (false);

grant select on table_sections to authenticated;   -- reads only; writes are NEVER granted

-- ----------------------------------------------------------------------------
-- 2. tables — additive layout columns. Old rows stay valid (all nullable);
--    the coordinate contract is enforced structurally (D-012 layer 4):
--      * both coordinates together or neither,
--      * each in 0..10000,
--      * coordinates only WITH a section,
--      * the section is the SAME org/restaurant/branch (composite FK).
-- ----------------------------------------------------------------------------
alter table tables
  add column section_id uuid,
  add column layout_x   integer,
  add column layout_y   integer;

comment on column tables.section_id is
  'TABLE-FLOOR-LAYOUT-021: the dining section this table sits in (null = legacy/unsectioned; clients fall back to the free-text `area` zone). Same-branch enforced by composite FK.';
comment on column tables.layout_x is
  'Normalized horizontal position inside the section canvas: integer 0..10000 (never pixels). Physical — NOT mirrored for RTL. Null = not placed yet.';
comment on column tables.layout_y is
  'Normalized vertical position inside the section canvas: integer 0..10000. See layout_x.';

alter table tables
  add constraint tables_section_same_branch_fk
    foreign key (organization_id, restaurant_id, branch_id, section_id)
    references table_sections (organization_id, restaurant_id, branch_id, id)
    on delete restrict,
  add constraint tables_layout_xy_together
    check ((layout_x is null) = (layout_y is null)),
  add constraint tables_layout_x_range
    check (layout_x is null or (layout_x >= 0 and layout_x <= 10000)),
  add constraint tables_layout_y_range
    check (layout_y is null or (layout_y >= 0 and layout_y <= 10000)),
  add constraint tables_layout_requires_section
    check (layout_x is null or section_id is not null);

create index tables_section_idx
  on tables (organization_id, section_id)
  where deleted_at is null and section_id is not null;

-- ----------------------------------------------------------------------------
-- 3. app.upsert_table_section — create/rename/toggle a section (manager+;
--    idempotent; audited). The upsert_table template minus floor fields.
--    display_order: a CREATE appends after the current live maximum; an UPDATE
--    never touches it (reorder_table_sections owns ordering).
-- ----------------------------------------------------------------------------
create or replace function app.upsert_table_section(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_id                uuid    default null,
  p_name              text    default null,
  p_is_active         boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid := app.current_app_user_id();
  v_name         text := btrim(coalesce(p_name, ''));
  v_found_org    uuid;
  v_found_rest   uuid;
  v_found_branch uuid;
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
    raise exception 'upsert_table_section: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'upsert_table_section: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'upsert_table_section: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;
  if length(v_name) = 0 then
    raise exception 'upsert_table_section: name is required' using errcode = '42501';
  end if;
  if not exists (
       select 1 from public.branches b
       where b.id = p_branch_id and b.organization_id = p_organization_id
         and b.restaurant_id = p_restaurant_id and b.deleted_at is null) then
    raise exception 'upsert_table_section: branch not found in organization/restaurant or is soft-deleted' using errcode = '42501';
  end if;

  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.table_sections where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'upsert_table_section: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'upsert_table_section: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'id', p_id, 'name', v_name,
              'active', coalesce(p_is_active, true))::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'upsert_table_section', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'upsert_table_section: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'table_section.upsert_denied', null, jsonb_build_object('entity', 'table_section', 'id', p_id, 'name', v_name));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table_section');
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    v_action := 'created';
  else
    v_id := p_id;
    v_action := 'updated';
  end if;
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table_section',
                'id', v_id, 'action', v_action);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'upsert_table_section', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_action = 'created' then
    insert into public.table_sections (id, organization_id, restaurant_id, branch_id, name, display_order, is_active)
    values (v_id, p_organization_id, p_restaurant_id, p_branch_id, v_name,
            -- append after the current live siblings; never reuses a slot.
            coalesce((select max(s.display_order) + 1 from public.table_sections s
                       where s.organization_id = p_organization_id
                         and s.restaurant_id   = p_restaurant_id
                         and s.branch_id       = p_branch_id
                         and s.deleted_at is null), 0),
            coalesce(p_is_active, true));
  else
    select to_jsonb(s) into v_old from public.table_sections s where s.id = v_id;
    update public.table_sections set
      name = v_name, is_active = coalesce(p_is_active, true)
    where id = v_id;
  end if;

  select to_jsonb(s) into v_new from public.table_sections s where s.id = v_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'table_section.' || v_action, v_old, v_new);
  return v_result;
end;
$$;

comment on function app.upsert_table_section(uuid, uuid, uuid, uuid, uuid, text, boolean) is
  'TABLE-FLOOR-LAYOUT-021 (D-033): create/rename/toggle a dining section as a dashboard manager+. The upsert_table template: GUC-free rank over the PASSED scope; 42501 structural failures; in-scope rank-1 -> committed table_section.upsert_denied + permission_denied; RF-112 ledger idempotency. Name unique per branch among LIVE rows (case-insensitive). display_order is append-on-create and NOT writable here (reorder_table_sections). Audits table_section.created/updated.';

-- ----------------------------------------------------------------------------
-- 4. app.soft_delete_table_section — tombstone a section AND detach its tables
--    (section_id + layout cleared; the tables themselves are NEVER deleted —
--    they fall back to the legacy/unsectioned zone on every client).
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

  update public.table_sections set deleted_at = now() where id = p_section_id;

  perform app.management_audit(v_org, v_rest, v_branch, 'table_section.deleted', v_old,
    jsonb_build_object('id', p_section_id, 'deleted', true, 'tables_detached', v_detached));
  return v_result;
end;
$$;

comment on function app.soft_delete_table_section(uuid, uuid, uuid) is
  'TABLE-FLOOR-LAYOUT-021 (D-020/D-033): tombstone a section (deleted_at = now(); never physical) after DETACHING every live table in it (section_id + layout_x/y cleared -> the tables fall back to the legacy zone; tables are NEVER deleted). Target-row-first authorization (rank >= manager against the section''s ACTUAL scope); RF-112 ledger idempotency; audits table_section.deleted with tables_detached count. The name slot is reusable afterwards (partial unique index).';

-- ----------------------------------------------------------------------------
-- 5. app.set_table_section — assign a table to a section, or clear it (null).
--    Clearing (or moving between sections) also clears the placement: a
--    coordinate is only meaningful inside the canvas it was placed on.
-- ----------------------------------------------------------------------------
create or replace function app.set_table_section(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_table_id          uuid,
  p_section_id        uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_current    uuid;
  v_s_branch   uuid;
  v_rank       integer;
  v_fp         text;
  v_replay     jsonb;
  v_result     jsonb;
  v_old        jsonb;
  v_new        jsonb;
begin
  if v_actor is null then
    raise exception 'set_table_section: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_table_section: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_table_id is null then
    raise exception 'set_table_section: organization_id and table_id are required' using errcode = '42501';
  end if;

  -- target-row-first: authorize against the TABLE's actual scope.
  select organization_id, restaurant_id, branch_id, section_id
    into v_org, v_rest, v_branch, v_current
    from public.tables where id = p_table_id and deleted_at is null;
  if v_org is null then
    raise exception 'set_table_section: table not found (or deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'set_table_section: table belongs to another organization' using errcode = '42501';
  end if;

  -- a non-null target section must be LIVE and in the SAME branch (the
  -- composite FK re-enforces this structurally; the check gives a clean 42501
  -- instead of an FK error, and refuses tombstoned sections explicitly).
  if p_section_id is not null then
    select branch_id into v_s_branch
      from public.table_sections
      where id = p_section_id and organization_id = v_org and deleted_at is null;
    if v_s_branch is null then
      raise exception 'set_table_section: section not found in organization (or deleted)' using errcode = '42501';
    end if;
    if v_s_branch <> v_branch then
      raise exception 'set_table_section: section belongs to another branch' using errcode = '42501';
    end if;
  end if;

  v_fp := md5(jsonb_build_object('org', v_org, 'table', p_table_id, 'section', p_section_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_table_section', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'set_table_section: caller has no active membership covering the table scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'table.section_set_denied', null,
      jsonb_build_object('entity', 'table', 'id', p_table_id, 'section_id', p_section_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table',
                'id', p_table_id, 'action', 'section_set', 'section_id', p_section_id);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_table_section', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- no-change is an idempotent success WITHOUT audit (pos_set_table_status rule)
  if v_current is not distinct from p_section_id then
    return v_result;
  end if;

  select to_jsonb(t) into v_old from public.tables t where t.id = p_table_id;
  -- placement is canvas-relative: leaving OR changing the section clears it.
  update public.tables
     set section_id = p_section_id, layout_x = null, layout_y = null
   where id = p_table_id;
  select to_jsonb(t) into v_new from public.tables t where t.id = p_table_id;
  perform app.management_audit(v_org, v_rest, v_branch, 'table.section_set', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_table_section(uuid, uuid, uuid, uuid) is
  'TABLE-FLOOR-LAYOUT-021 (D-033): assign a live table to a live SAME-BRANCH section, or clear it (p_section_id null). Deliberately separate from the full-replace app.upsert_table so a stale client can never erase layout. Any section change clears layout_x/y (a placement belongs to one canvas). Target-row-first authorization; no-change = idempotent success without audit; audits table.section_set (+_denied).';

-- ----------------------------------------------------------------------------
-- 6. app.set_table_layout_position — place a table inside its section canvas.
--    Normalized integers 0..10000 (both, or both null to clear). Requires a
--    section for a non-null placement.
-- ----------------------------------------------------------------------------
create or replace function app.set_table_layout_position(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_table_id          uuid,
  p_layout_x          integer,
  p_layout_y          integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_org     uuid;
  v_rest    uuid;
  v_branch  uuid;
  v_section uuid;
  v_x       integer;
  v_y       integer;
  v_rank    integer;
  v_fp      text;
  v_replay  jsonb;
  v_result  jsonb;
  v_old     jsonb;
  v_new     jsonb;
begin
  if v_actor is null then
    raise exception 'set_table_layout_position: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_table_layout_position: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_table_id is null then
    raise exception 'set_table_layout_position: organization_id and table_id are required' using errcode = '42501';
  end if;
  -- the coordinate contract, structurally mirrored by the CHECK constraints:
  if (p_layout_x is null) <> (p_layout_y is null) then
    raise exception 'set_table_layout_position: layout_x and layout_y must be provided together' using errcode = '42501';
  end if;
  if p_layout_x is not null and
     (p_layout_x < 0 or p_layout_x > 10000 or p_layout_y < 0 or p_layout_y > 10000) then
    raise exception 'set_table_layout_position: coordinates must be normalized integers in 0..10000' using errcode = '42501';
  end if;

  select organization_id, restaurant_id, branch_id, section_id, layout_x, layout_y
    into v_org, v_rest, v_branch, v_section, v_x, v_y
    from public.tables where id = p_table_id and deleted_at is null;
  if v_org is null then
    raise exception 'set_table_layout_position: table not found (or deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'set_table_layout_position: table belongs to another organization' using errcode = '42501';
  end if;
  if p_layout_x is not null and v_section is null then
    raise exception 'set_table_layout_position: table has no section (assign a section first)' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', v_org, 'table', p_table_id,
              'x', p_layout_x, 'y', p_layout_y)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_table_layout_position', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'set_table_layout_position: caller has no active membership covering the table scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'table.layout_move_denied', null,
      jsonb_build_object('entity', 'table', 'id', p_table_id, 'x', p_layout_x, 'y', p_layout_y));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table',
                'id', p_table_id, 'action', 'layout_moved',
                'layout_x', p_layout_x, 'layout_y', p_layout_y);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_table_layout_position', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- no-change is an idempotent success WITHOUT audit.
  if v_x is not distinct from p_layout_x and v_y is not distinct from p_layout_y then
    return v_result;
  end if;

  select to_jsonb(t) into v_old from public.tables t where t.id = p_table_id;
  update public.tables
     set layout_x = p_layout_x, layout_y = p_layout_y
   where id = p_table_id;
  select to_jsonb(t) into v_new from public.tables t where t.id = p_table_id;
  perform app.management_audit(v_org, v_rest, v_branch, 'table.layout_moved', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_table_layout_position(uuid, uuid, uuid, integer, integer) is
  'TABLE-FLOOR-LAYOUT-021 (D-033): place a live table inside its section canvas at NORMALIZED integer coordinates (0..10000 each; both together, both-null clears). Refuses placement on a sectionless table. Target-row-first authorization (rank >= manager); RF-112 ledger idempotency; no-change = idempotent success without audit; audits table.layout_moved (+_denied). Coordinates are physical room positions — clients never RTL-mirror them.';

-- ----------------------------------------------------------------------------
-- 7. app.reorder_table_sections — one authoritative order for the section
--    blocks (the menu_reorder shape: complete live sibling set, atomic).
-- ----------------------------------------------------------------------------
create or replace function app.reorder_table_sections(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_ids             uuid[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_n      integer;
  v_found  integer;
  v_total  integer;
begin
  if v_actor is null then
    raise exception 'reorder_table_sections: invalid request' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'reorder_table_sections: invalid request' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'reorder_table_sections: invalid request' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'table_section.reorder_denied', null, jsonb_build_object('entity', 'table_section'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table_section');
  end if;

  -- input shape: non-empty, distinct, and EXACTLY the live sibling set (a
  -- partial list would silently invent an order for the absent sections).
  v_n := coalesce(array_length(p_ids, 1), 0);
  if v_n = 0 then
    raise exception 'reorder_table_sections: invalid request' using errcode = '42501';
  end if;
  if (select count(distinct u) from unnest(p_ids) u) <> v_n then
    raise exception 'reorder_table_sections: invalid request' using errcode = '42501';
  end if;
  select count(*) into v_found
    from public.table_sections s
    where s.organization_id = p_organization_id
      and s.restaurant_id   = p_restaurant_id
      and s.branch_id       = p_branch_id
      and s.deleted_at is null
      and s.id = any(p_ids);
  select count(*) into v_total
    from public.table_sections s
    where s.organization_id = p_organization_id
      and s.restaurant_id   = p_restaurant_id
      and s.branch_id       = p_branch_id
      and s.deleted_at is null;
  if v_found <> v_n or v_total <> v_n then
    raise exception 'reorder_table_sections: invalid request' using errcode = '42501';
  end if;

  update public.table_sections s
     set display_order = ord.position - 1
    from (select u.id, u.ordinality as position
            from unnest(p_ids) with ordinality as u(id, ordinality)) ord
   where s.id = ord.id
     and s.organization_id = p_organization_id;

  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'table_section.reordered', null, jsonb_build_object('ids', to_jsonb(p_ids)));
  return jsonb_build_object('ok', true, 'entity', 'table_section', 'action', 'reordered',
                            'count', v_n);
end;
$$;

comment on function app.reorder_table_sections(uuid, uuid, uuid, uuid[]) is
  'TABLE-FLOOR-LAYOUT-021 (the menu_reorder shape): atomically re-number display_order (0-based) for the COMPLETE live section set of one branch. Manager+ over the passed scope; generic 42501 for any structural refusal (partial/duplicate/foreign ids indistinguishable); naturally idempotent (same list -> same result); audits table_section.reordered.';

-- ----------------------------------------------------------------------------
-- 8. app.pos_tables / app.list_tables — CREATE OR REPLACE (keep ACLs).
--    Faithful re-creations of the PILOT-OPERATIONS-CORRECTIONS-001 bodies with
--    the section/layout keys ADDED and every prior key unchanged.
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

  return jsonb_build_object(
    'ok', true,
    'entity', 'tables',
    'tables', v_tables,
    'server_ts', now());
end;
$$;

comment on function app.pos_tables(uuid, uuid) is
  'POS/KDS device table read (session-derived scope, 42501 fail-closed) + PILOT-OPERATIONS-CORRECTIONS-001 (effective_state, group_id) + TABLE-FLOOR-LAYOUT-021: rows now also carry section_id/section_name/section_display_order (live section join; nulls for legacy rows) and the normalized layout_x/layout_y placement. Every prior field unchanged. Money-free; all PIN roles.';

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

  return jsonb_build_object('ok', true, 'entity', 'table', 'tables', v_items,
                            'sections', v_sections);
end;
$$;

comment on function app.list_tables(uuid, uuid, uuid) is
  'GUC-free dining-table LIST for the owner/manager dashboard + PILOT-OPERATIONS-CORRECTIONS-001 (effective_state, group_id) + TABLE-FLOOR-LAYOUT-021: table rows now also carry section_id/section_name/section_display_order + layout_x/layout_y, and the envelope gains a `sections` catalog array (live sections of the scope, display-ordered) so empty sections render as canvases. Tombstones EXCLUDED, is_active=false INCLUDED (tables AND sections); read-only; scope-safe (R-003); money-free.';

-- ----------------------------------------------------------------------------
-- 9. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 / RF-160 pattern).
-- ----------------------------------------------------------------------------
create or replace function public.upsert_table_section(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_id uuid default null, p_name text default null, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.upsert_table_section(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_id, p_name, p_is_active); $$;

create or replace function public.soft_delete_table_section(
  p_client_request_id uuid, p_organization_id uuid, p_section_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.soft_delete_table_section(p_client_request_id, p_organization_id, p_section_id); $$;

create or replace function public.set_table_section(
  p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_section_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_table_section(p_client_request_id, p_organization_id, p_table_id, p_section_id); $$;

create or replace function public.set_table_layout_position(
  p_client_request_id uuid, p_organization_id uuid, p_table_id uuid,
  p_layout_x integer, p_layout_y integer)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_table_layout_position(p_client_request_id, p_organization_id, p_table_id, p_layout_x, p_layout_y); $$;

create or replace function public.reorder_table_sections(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_ids uuid[])
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.reorder_table_sections(p_organization_id, p_restaurant_id, p_branch_id, p_ids); $$;

-- ----------------------------------------------------------------------------
-- 10. Grants: authenticated only (never anon / service_role; D-011).
-- ----------------------------------------------------------------------------
revoke all on function app.upsert_table_section(uuid, uuid, uuid, uuid, uuid, text, boolean) from public;
revoke all on function app.soft_delete_table_section(uuid, uuid, uuid)                       from public;
revoke all on function app.set_table_section(uuid, uuid, uuid, uuid)                         from public;
revoke all on function app.set_table_layout_position(uuid, uuid, uuid, integer, integer)     from public;
revoke all on function app.reorder_table_sections(uuid, uuid, uuid, uuid[])                  from public;
grant execute on function app.upsert_table_section(uuid, uuid, uuid, uuid, uuid, text, boolean) to authenticated;
grant execute on function app.soft_delete_table_section(uuid, uuid, uuid)                       to authenticated;
grant execute on function app.set_table_section(uuid, uuid, uuid, uuid)                         to authenticated;
grant execute on function app.set_table_layout_position(uuid, uuid, uuid, integer, integer)     to authenticated;
grant execute on function app.reorder_table_sections(uuid, uuid, uuid, uuid[])                  to authenticated;

revoke all on function public.upsert_table_section(uuid, uuid, uuid, uuid, uuid, text, boolean) from public;
revoke all on function public.soft_delete_table_section(uuid, uuid, uuid)                       from public;
revoke all on function public.set_table_section(uuid, uuid, uuid, uuid)                         from public;
revoke all on function public.set_table_layout_position(uuid, uuid, uuid, integer, integer)     from public;
revoke all on function public.reorder_table_sections(uuid, uuid, uuid, uuid[])                  from public;
grant execute on function public.upsert_table_section(uuid, uuid, uuid, uuid, uuid, text, boolean) to authenticated;
grant execute on function public.soft_delete_table_section(uuid, uuid, uuid)                       to authenticated;
grant execute on function public.set_table_section(uuid, uuid, uuid, uuid)                         to authenticated;
grant execute on function public.set_table_layout_position(uuid, uuid, uuid, integer, integer)     to authenticated;
grant execute on function public.reorder_table_sections(uuid, uuid, uuid, uuid[])                  to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function public.reorder_table_sections(uuid, uuid, uuid, uuid[]);
--   drop function public.set_table_layout_position(uuid, uuid, uuid, integer, integer);
--   drop function public.set_table_section(uuid, uuid, uuid, uuid);
--   drop function public.soft_delete_table_section(uuid, uuid, uuid);
--   drop function public.upsert_table_section(uuid, uuid, uuid, uuid, uuid, text, boolean);
--   drop function app.reorder_table_sections(uuid, uuid, uuid, uuid[]);
--   drop function app.set_table_layout_position(uuid, uuid, uuid, integer, integer);
--   drop function app.set_table_section(uuid, uuid, uuid, uuid);
--   drop function app.soft_delete_table_section(uuid, uuid, uuid);
--   drop function app.upsert_table_section(uuid, uuid, uuid, uuid, uuid, text, boolean);
--   (re-emit the 20260720110000 bodies of app.pos_tables / app.list_tables)
--   alter table tables
--     drop constraint tables_layout_requires_section,
--     drop constraint tables_layout_y_range,
--     drop constraint tables_layout_x_range,
--     drop constraint tables_layout_xy_together,
--     drop constraint tables_section_same_branch_fk,
--     drop column layout_y, drop column layout_x, drop column section_id;
--   drop table table_sections;
-- ============================================================================
