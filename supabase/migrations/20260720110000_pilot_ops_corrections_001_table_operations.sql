-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 (3/4) -- operational table system: manual
-- floor control from the POS + linked-table groups + honest EFFECTIVE state
-- ============================================================================
-- Tables must behave like real restaurant resources. The four manual states
-- (available/reserved/occupied/out_of_service) ALREADY EXIST as public.tables.status
-- (writable today ONLY via the Dashboard app.set_table_status). Derived DINE-IN
-- occupancy ALREADY EXISTS as active_order_count in app.pos_tables/app.list_tables.
-- What this migration adds:
--
--   * app.table_effective_state(manual, active_count) -- the ONE honest fusion of
--     MANUAL floor state + DERIVED occupancy. Precedence: out_of_service (manual,
--     can't be seated) > active dine-in occupancy > reserved (manual) > occupied
--     (manual, held after payment) > available. pos_tables/list_tables now return
--     BOTH the raw status/active_order_count AND this effective_state.
--   * table_groups + table_group_members -- a normalized LINK model (greenfield).
--     A group has >= 2 member tables, same org/restaurant/branch; a table is in AT
--     MOST ONE group (unique(org,table_id)). Linking NEVER merges orders or bills:
--     each order keeps its own orders.table_id; the group is an operational read
--     overlay. Unlink dissolves the group (cascade) and touches NO order.
--   * app.pos_set_table_status / app.pos_link_tables / app.pos_unlink_tables --
--     the POS PIN-session write paths, gated by the DEFAULT-ON manage_table_operations
--     capability (migration 1), scope derived from the session, deterministic row
--     locking, typed refusals, audited. Reached ONLY via public.sync_push (op types
--     table.status_set / table.link / table.unlink). No public wrappers.
--   * app.clear_table_reservation_on_seat -- a trigger that clears a table's manual
--     'reserved' the instant a live dine-in order lands on it (submit OR move), so a
--     reserved table that receives a real order reads Occupied (derived), never
--     misleadingly Reserved. Avoids re-creating the large app.submit_order body.
--   * app.pos_tables / app.list_tables -- +effective_state +group_id (faithful
--     re-creations of the RESTAURANT-OPERATIONS-V1-001 bodies).
--   * app.sync_push -- +3 dispatch branches (faithful re-creation of the migration-2
--     body). app.audit_action_has_detail / app.audit_safe_detail -- +table.status/
--     link/unlink families and their safe scalar keys (from_status/to_status/group_label).
--
-- SECURITY: out_of_service tables cannot be linked and cannot receive orders
-- (app.submit_order + app.move_order_table already block out_of_service targets).
-- Marking a table out_of_service while a live dine-in order sits on it is REFUSED
-- (table_in_use) -- no contradictory occupied+out_of_service state. Cross-branch /
-- foreign / tombstoned tables collapse to ONE typed refusal (R-003).
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema -- table_groups + table_group_members. Operational state (like
--    menu_item_branch_availability): NOT a synced entity (no deleted_at; not in
--    sync_pull), read through pos_tables/list_tables. Unlink HARD-deletes (the
--    audit_event is the durable record). Composite same-org FKs (D-012 layer 4).
-- ----------------------------------------------------------------------------
create table table_groups (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id),
  restaurant_id   uuid not null,
  branch_id       uuid not null,
  created_by_employee_profile_id uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, id),
  -- B2 (PILOT-OPERATIONS-CORRECTIONS-001): the FK TARGET for a member's
  -- (organization_id, restaurant_id, branch_id, group_id) composite reference, so a
  -- member row's scope must match its group's EXACT (org, restaurant, branch) — the
  -- schema defends itself against a privileged/internal write that mixes scopes.
  unique (organization_id, restaurant_id, branch_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id),
  foreign key (organization_id, created_by_employee_profile_id)
    references employee_profiles (organization_id, id)
);

comment on table table_groups is
  'PILOT-OPERATIONS-CORRECTIONS-001: an operational LINK group of >= 2 dining tables at ONE branch (e.g. "Table 4 + Table 5"). Orders are NEVER merged -- each order keeps its own orders.table_id; the group is a read-model overlay for occupancy/reservation display and the POS picker. Operational state, not a synced entity (no tombstone; not in sync_pull) -- the POS receives group_id through app.pos_tables. Written only via app.pos_link_tables / app.pos_unlink_tables (manage_table_operations, D-011); direct DML is RLS-denied + unGRANTed.';

-- B2: the composite FK TARGET on the (shipped) tables table so a member's
-- (organization_id, restaurant_id, branch_id, table_id) reference proves the member's
-- scope matches the TABLE's EXACT (org, restaurant, branch). `id` is already the PK
-- (unique), so this composite unique adds a structural FK target without changing any
-- existing constraint. Added in THIS unshipped phase migration (never editing the
-- shipped tables migration).
alter table public.tables
  add constraint tables_org_rest_branch_id_key
  unique (organization_id, restaurant_id, branch_id, id);

create table table_group_members (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations (id),
  restaurant_id   uuid not null,
  branch_id       uuid not null,
  group_id        uuid not null,
  table_id        uuid not null,
  created_at      timestamptz not null default now(),
  unique (organization_id, id),
  -- a table belongs to AT MOST ONE group (there is no soft-deleted group row, so
  -- this is the "at most one ACTIVE group" invariant, D-012 layer 4).
  unique (organization_id, table_id),
  -- B2 (PILOT-OPERATIONS-CORRECTIONS-001): COMPOSITE structural FKs prove the member's
  -- (org, restaurant, branch) matches BOTH its group AND its table exactly -- so a
  -- privileged/internal write can never place a member under a group or a table from a
  -- sibling restaurant/branch. The group FK keeps ON DELETE CASCADE (unlink deletes the
  -- group -> its members go atomically).
  foreign key (organization_id, restaurant_id, branch_id, group_id)
    references table_groups (organization_id, restaurant_id, branch_id, id) on delete cascade,
  foreign key (organization_id, restaurant_id, branch_id, table_id)
    references tables (organization_id, restaurant_id, branch_id, id),
  -- Retained (explicit defence): the member's scope is a real branch. Transitively
  -- implied by the composite group FK, kept for clarity.
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id)
);

comment on table table_group_members is
  'PILOT-OPERATIONS-CORRECTIONS-001: membership of a dining table in exactly one table_groups row. unique(organization_id, table_id) enforces "a table is in at most one group". B2: COMPOSITE FKs on (organization_id, restaurant_id, branch_id, group_id) -> table_groups and (organization_id, restaurant_id, branch_id, table_id) -> tables prove the member''s restaurant/branch match BOTH its group AND its table exactly (D-012 layer 4 -- the schema defends itself against a privileged/internal cross-scope write). ON DELETE CASCADE from table_groups so unlink (delete the group) removes its members atomically. Written only by app.pos_link_tables / app.pos_unlink_tables.';

create index table_group_members_group_idx on table_group_members (organization_id, group_id);
create index table_groups_branch_idx on table_groups (organization_id, restaurant_id, branch_id);

-- RLS (tables mirror): SELECT for every member role; all DML denied-by-policy AND
-- revoked -- writes go through the SECURITY DEFINER RPCs (D-011/D-012).
alter table table_groups enable row level security;
alter table table_groups force  row level security;
create policy table_groups_sel on table_groups for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'kitchen_staff', 'accountant'));
create policy table_groups_ins_deny on table_groups for insert to authenticated with check (false);
create policy table_groups_upd_deny on table_groups for update to authenticated using (false) with check (false);
create policy table_groups_del_deny on table_groups for delete to authenticated using (false);

alter table table_group_members enable row level security;
alter table table_group_members force  row level security;
create policy table_group_members_sel on table_group_members for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'kitchen_staff', 'accountant'));
create policy table_group_members_ins_deny on table_group_members for insert to authenticated with check (false);
create policy table_group_members_upd_deny on table_group_members for update to authenticated using (false) with check (false);
create policy table_group_members_del_deny on table_group_members for delete to authenticated using (false);

grant select, insert, update, delete on table_groups        to authenticated;
revoke insert, update, delete       on table_groups        from authenticated;
grant select, insert, update, delete on table_group_members to authenticated;
revoke insert, update, delete       on table_group_members from authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.table_effective_state -- the single, pure precedence rule. Immutable so
--    it may be used in pos_tables/list_tables and asserted directly in tests.
-- ----------------------------------------------------------------------------
create function app.table_effective_state(p_manual_status text, p_active_order_count integer)
  returns text
  language sql
  immutable
  set search_path = ''
as $$
  select case
    -- out_of_service (manual) wins: a broken table can never be seated, even if a
    -- stale order row still references it.
    when p_manual_status = 'out_of_service' then 'out_of_service'
    -- a live dine-in order occupies the table -- derived occupancy overrides a
    -- stale manual 'reserved'/'available' (B3.A/B3.D).
    when coalesce(p_active_order_count, 0) > 0 then 'occupied'
    -- manual reservation, no order yet.
    when p_manual_status = 'reserved' then 'reserved'
    -- manual occupied held after settlement (B3.B: customer still sitting).
    when p_manual_status = 'occupied' then 'occupied'
    else 'available'
  end;
$$;

comment on function app.table_effective_state(text, integer) is
  'PILOT-OPERATIONS-CORRECTIONS-001: pure precedence fusion of MANUAL floor status + DERIVED dine-in occupancy into ONE honest effective state. out_of_service (manual) > active dine-in occupancy (occupied) > reserved (manual) > occupied (manual, held after payment) > available. Immutable; the single source of truth used by app.pos_tables / app.list_tables and asserted in tests.';

revoke all on function app.table_effective_state(text, integer) from public;
grant execute on function app.table_effective_state(text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.clear_table_reservation_on_seat (+ trigger) -- when a LIVE dine-in order
--    lands on a table (submit OR table move), clear that table's manual 'reserved'
--    so the reservation is consumed and derived occupancy reads Occupied, never a
--    misleading Reserved (B3.D). A conditional UPDATE (no-op unless the table is
--    reserved); never touches 'occupied'/'out_of_service'/'available'. Runs in the
--    order's own transaction (atomic with acceptance). SECURITY DEFINER so it can
--    write public.tables regardless of the caller's RLS (the write is a narrow,
--    same-org, reserved-only clear).
-- ----------------------------------------------------------------------------
create function app.clear_table_reservation_on_seat()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if new.order_type = 'dine_in'
     and new.table_id is not null
     and new.status in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    update public.tables
       set status = 'available'
     where organization_id = new.organization_id
       and id              = new.table_id
       and status          = 'reserved';
  end if;
  return new;
end;
$$;

comment on function app.clear_table_reservation_on_seat() is
  'PILOT-OPERATIONS-CORRECTIONS-001: AFTER INSERT/UPDATE(table_id,status) trigger on public.orders. When a live dine-in order occupies a table, clears that table''s manual reserved status to available (reservation consumed -> derived occupancy shows Occupied, never a stale Reserved). Conditional (no-op unless the target table is reserved); never alters occupied/out_of_service/available. Same-org scoped. SECURITY DEFINER (narrow reserved-only clear).';

create trigger orders_clear_reservation_on_seat
  after insert or update of table_id, status on public.orders
  for each row execute function app.clear_table_reservation_on_seat();

-- ----------------------------------------------------------------------------
-- 4. app.pos_set_table_status -- POS manual floor-state change (PIN + capability).
--    Reached only via public.sync_push (table.status_set). No public wrapper.
-- ----------------------------------------------------------------------------
create function app.pos_set_table_status(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_table_id       uuid,
  p_status         text
)
  returns jsonb
  language plpgsql
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
  v_m_perms    jsonb;
  v_t_branch   uuid;
  v_t_status   text;
  v_label      text;
  v_active     integer;
begin
  -- (a) canonical PIN-session preamble
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then raise exception 'pos_set_table_status: PIN session not found' using errcode='42501'; end if;
  if not app.is_pin_session_valid(p_pin_session_id) then raise exception 'pos_set_table_status: PIN session is not valid' using errcode='42501'; end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_set_table_status: backing device session/pairing is not active' using errcode='42501'; end if;
  if v_ds_device <> p_device_id then raise exception 'pos_set_table_status: device_id does not match the PIN session device' using errcode='42501'; end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_set_table_status: resolved membership is not active' using errcode='42501'; end if;

  -- (b) capability BEFORE any table lookup (no existence oracle, R-003).
  if not ((v_role in ('manager','restaurant_owner','org_owner'))
          or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_table_operations')) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.status_denied', null, null,
            jsonb_build_object('entity','table','id',p_table_id,'role',v_role,'to_status',p_status,'denied_reason','permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  -- (c) shape
  if p_status is null or p_status not in ('available','occupied','reserved','out_of_service') then
    raise exception 'pos_set_table_status: status must be available|occupied|reserved|out_of_service' using errcode='42501'; end if;

  -- (d) load + LOCK the target; must be a live table of the SESSION branch.
  select t.branch_id, t.status, t.label into v_t_branch, v_t_status, v_label
    from public.tables t
    where t.id = p_table_id and t.organization_id = v_org and t.deleted_at is null and t.is_active
    for update;
  if not found or v_t_branch <> v_branch then
    return jsonb_build_object('ok', false, 'error', 'table_not_found', 'entity', 'table');
  end if;

  -- (e) contradiction guard: refuse out_of_service while a live dine-in order sits
  --     here (a broken table cannot also be seated). Typed + audited.
  if p_status = 'out_of_service' then
    select count(*) into v_active from public.orders o
      where o.organization_id = v_org and o.branch_id = v_branch and o.order_type = 'dine_in'
        and o.table_id = p_table_id and o.deleted_at is null
        and o.status in ('submitted','accepted','preparing','ready','served');
    if v_active > 0 then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.status_denied', null, null,
              jsonb_build_object('entity','table','id',p_table_id,'table_label',v_label,'role',v_role,'to_status',p_status,'denied_reason','table_in_use'));
      return jsonb_build_object('ok', false, 'error', 'table_in_use', 'entity', 'table', 'table_id', p_table_id);
    end if;
  end if;

  -- (f) no-change: idempotent success, no audit.
  if v_t_status = p_status then
    return jsonb_build_object('ok', true, 'entity', 'table', 'table_id', p_table_id,
                              'status', p_status, 'table_label', v_label, 'no_change', true);
  end if;

  update public.tables set status = p_status where id = p_table_id;

  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.status_set', null,
          jsonb_build_object('status', v_t_status),
          jsonb_build_object('status', p_status, 'from_status', v_t_status, 'to_status', p_status,
                             'table_label', v_label, 'resolved_membership_id', v_membership));

  return jsonb_build_object('ok', true, 'entity', 'table', 'table_id', p_table_id,
                            'status', p_status, 'table_label', v_label);
end;
$$;

comment on function app.pos_set_table_status(uuid, uuid, uuid, text) is
  'PILOT-OPERATIONS-CORRECTIONS-001 (D-011): POS PIN-session manual table floor-state change. manager+ by role OR a cashier with the DEFAULT-ON manage_table_operations capability (checked BEFORE any lookup -- no existence oracle, R-003); denial audits table.status_denied + returns permission_denied. Target must be a live table of the SESSION branch (foreign/tombstoned/inactive collapse to table_not_found). Refuses out_of_service while a live dine-in order sits on the table (table_in_use -- no occupied+out_of_service contradiction). Any other transition is allowed (available/occupied/reserved). No-change is idempotent (no audit). Audits table.status_set with before/after status. Reached ONLY via public.sync_push (table.status_set). MONEY-FREE.';

revoke all on function app.pos_set_table_status(uuid, uuid, uuid, text) from public;
revoke all on function app.pos_set_table_status(uuid, uuid, uuid, text) from anon;
grant execute on function app.pos_set_table_status(uuid, uuid, uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. app.pos_link_tables -- link two same-branch tables into one operational group
--    (no order/bill merge). Deterministic lock order (ascending id) so concurrent
--    links can never deadlock. If one table is already grouped, the other JOINS
--    that group (grows it to >= 3); both in the same group -> no_change; both in
--    DIFFERENT groups -> refused (no group merge in V1).
-- ----------------------------------------------------------------------------
create function app.pos_link_tables(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_table_id_a     uuid,
  p_table_id_b     uuid
)
  returns jsonb
  language plpgsql
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
  v_m_perms    jsonb;
  v_valid      integer;
  v_label_a    text;
  v_label_b    text;
  v_grp_a      uuid;
  v_grp_b      uuid;
  v_group      uuid;
  v_group_label text;
begin
  -- (a) canonical PIN-session preamble
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then raise exception 'pos_link_tables: PIN session not found' using errcode='42501'; end if;
  if not app.is_pin_session_valid(p_pin_session_id) then raise exception 'pos_link_tables: PIN session is not valid' using errcode='42501'; end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_link_tables: backing device session/pairing is not active' using errcode='42501'; end if;
  if v_ds_device <> p_device_id then raise exception 'pos_link_tables: device_id does not match the PIN session device' using errcode='42501'; end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_link_tables: resolved membership is not active' using errcode='42501'; end if;

  -- (b) capability (no oracle).
  if not ((v_role in ('manager','restaurant_owner','org_owner'))
          or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_table_operations')) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.link_denied', null, null,
            jsonb_build_object('role',v_role,'denied_reason','permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table_group');
  end if;

  -- (c) shape: two DISTINCT tables required.
  if p_table_id_a is null or p_table_id_b is null then
    raise exception 'pos_link_tables: two table ids are required' using errcode='42501'; end if;
  if p_table_id_a = p_table_id_b then
    return jsonb_build_object('ok', false, 'error', 'invalid_link', 'detail', 'same_table', 'entity', 'table_group');
  end if;

  -- (d) DETERMINISTIC lock order: lock both table rows ascending by id (a concurrent
  --     link that shares a table locks in the SAME order -> no deadlock).
  perform 1 from public.tables t
    where t.organization_id = v_org and t.id in (p_table_id_a, p_table_id_b)
    order by t.id
    for update;

  -- (e) BOTH tables must be live, in-service, session-branch (out_of_service cannot
  --     be linked, B8). Count the valid ones; anything else = table_not_available.
  select count(*), max(case when t.id = p_table_id_a then t.label end),
                   max(case when t.id = p_table_id_b then t.label end)
    into v_valid, v_label_a, v_label_b
    from public.tables t
    where t.organization_id = v_org and t.restaurant_id = v_rest and t.branch_id = v_branch
      and t.id in (p_table_id_a, p_table_id_b)
      and t.is_active and t.deleted_at is null and t.status <> 'out_of_service';
  if v_valid <> 2 then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.link_denied', null, null,
            jsonb_build_object('role',v_role,'denied_reason','table_not_available'));
    return jsonb_build_object('ok', false, 'error', 'table_not_available', 'entity', 'table_group');
  end if;

  -- (f) existing group membership of each (the unique(org,table_id) constraint is
  --     the race backstop; the rows we read are stable under the table locks held).
  select gm.group_id into v_grp_a from public.table_group_members gm
    where gm.organization_id = v_org and gm.table_id = p_table_id_a;
  select gm.group_id into v_grp_b from public.table_group_members gm
    where gm.organization_id = v_org and gm.table_id = p_table_id_b;

  if v_grp_a is not null and v_grp_a = v_grp_b then
    -- already in the same group.
    v_group := v_grp_a;
    select string_agg(t.label, ' + ' order by t.label) into v_group_label
      from public.table_group_members gm join public.tables t
        on t.organization_id = gm.organization_id and t.id = gm.table_id
      where gm.organization_id = v_org and gm.group_id = v_group;
    return jsonb_build_object('ok', true, 'entity', 'table_group', 'group_id', v_group,
                              'group_label', v_group_label, 'no_change', true);
  elsif v_grp_a is not null and v_grp_b is not null then
    -- both grouped, different groups -> no merge in V1.
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.link_denied', null, null,
            jsonb_build_object('role',v_role,'denied_reason','tables_in_different_groups'));
    return jsonb_build_object('ok', false, 'error', 'invalid_link', 'detail', 'tables_in_different_groups', 'entity', 'table_group');
  elsif v_grp_a is not null then
    v_group := v_grp_a;
    insert into public.table_group_members (organization_id, restaurant_id, branch_id, group_id, table_id)
      values (v_org, v_rest, v_branch, v_group, p_table_id_b);
  elsif v_grp_b is not null then
    v_group := v_grp_b;
    insert into public.table_group_members (organization_id, restaurant_id, branch_id, group_id, table_id)
      values (v_org, v_rest, v_branch, v_group, p_table_id_a);
  else
    -- neither grouped -> new group with both.
    insert into public.table_groups (organization_id, restaurant_id, branch_id, created_by_employee_profile_id)
      values (v_org, v_rest, v_branch, v_emp) returning id into v_group;
    insert into public.table_group_members (organization_id, restaurant_id, branch_id, group_id, table_id)
      values (v_org, v_rest, v_branch, v_group, p_table_id_a),
             (v_org, v_rest, v_branch, v_group, p_table_id_b);
  end if;

  select string_agg(t.label, ' + ' order by t.label) into v_group_label
    from public.table_group_members gm join public.tables t
      on t.organization_id = gm.organization_id and t.id = gm.table_id
    where gm.organization_id = v_org and gm.group_id = v_group;

  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.tables_linked', null, null,
          jsonb_build_object('group_id', v_group, 'group_label', v_group_label,
                             'table_label', v_label_a, 'to_table_label', v_label_b,
                             'resolved_membership_id', v_membership));

  return jsonb_build_object('ok', true, 'entity', 'table_group', 'group_id', v_group, 'group_label', v_group_label);
end;
$$;

comment on function app.pos_link_tables(uuid, uuid, uuid, uuid) is
  'PILOT-OPERATIONS-CORRECTIONS-001 (D-011): link two same-branch dining tables into ONE operational group -- NO order/bill/payment merge (each order keeps its own orders.table_id). manager+/manage_table_operations cashier (denial -> table.link_denied). Both tables must be live, in-service (out_of_service cannot be linked), session-branch (else table_not_available). Deterministic lock order (ascending id) -> no deadlock with a concurrent link. If one table is already grouped the other JOINS that group; same group -> no_change; different groups -> invalid_link/tables_in_different_groups (no group merge in V1). A table is in AT MOST ONE group (unique constraint backstop). Audits table.tables_linked with the combined group label. Reached ONLY via public.sync_push (table.link). MONEY-FREE.';

revoke all on function app.pos_link_tables(uuid, uuid, uuid, uuid) from public;
revoke all on function app.pos_link_tables(uuid, uuid, uuid, uuid) from anon;
grant execute on function app.pos_link_tables(uuid, uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. app.pos_unlink_tables -- dissolve the group a table belongs to. Orders are
--    NEVER moved or deleted (each keeps its orders.table_id); occupancy simply
--    recomputes per independent table. Not grouped -> idempotent no_change.
-- ----------------------------------------------------------------------------
create function app.pos_unlink_tables(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_table_id       uuid
)
  returns jsonb
  language plpgsql
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
  v_m_perms    jsonb;
  v_group      uuid;
  v_group_label text;
begin
  -- (a) canonical PIN-session preamble
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then raise exception 'pos_unlink_tables: PIN session not found' using errcode='42501'; end if;
  if not app.is_pin_session_valid(p_pin_session_id) then raise exception 'pos_unlink_tables: PIN session is not valid' using errcode='42501'; end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_unlink_tables: backing device session/pairing is not active' using errcode='42501'; end if;
  if v_ds_device <> p_device_id then raise exception 'pos_unlink_tables: device_id does not match the PIN session device' using errcode='42501'; end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_unlink_tables: resolved membership is not active' using errcode='42501'; end if;

  -- (b) capability (no oracle).
  if not ((v_role in ('manager','restaurant_owner','org_owner'))
          or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_table_operations')) then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.unlink_denied', null, null,
            jsonb_build_object('role',v_role,'denied_reason','permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table_group');
  end if;

  if p_table_id is null then raise exception 'pos_unlink_tables: table_id is required' using errcode='42501'; end if;

  -- (c) resolve the group of a SESSION-BRANCH table (a foreign/unknown table simply
  --     has no group here -> no_change; never an oracle).
  select gm.group_id into v_group
    from public.table_group_members gm
    where gm.organization_id = v_org and gm.branch_id = v_branch and gm.table_id = p_table_id;
  if not found then
    return jsonb_build_object('ok', true, 'entity', 'table_group', 'no_change', true);
  end if;

  -- (d) lock the group row, capture the label for the audit, then delete (members
  --     cascade). Orders are untouched -- occupancy recomputes per table.
  perform 1 from public.table_groups g where g.organization_id = v_org and g.id = v_group for update;
  select string_agg(t.label, ' + ' order by t.label) into v_group_label
    from public.table_group_members gm join public.tables t
      on t.organization_id = gm.organization_id and t.id = gm.table_id
    where gm.organization_id = v_org and gm.group_id = v_group;

  delete from public.table_groups where organization_id = v_org and id = v_group;

  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'table.tables_unlinked', null,
          jsonb_build_object('group_id', v_group, 'group_label', v_group_label),
          jsonb_build_object('group_id', v_group, 'group_label', v_group_label,
                             'resolved_membership_id', v_membership));

  return jsonb_build_object('ok', true, 'entity', 'table_group', 'group_id', v_group);
end;
$$;

comment on function app.pos_unlink_tables(uuid, uuid, uuid) is
  'PILOT-OPERATIONS-CORRECTIONS-001 (D-011): dissolve the operational group a session-branch table belongs to. manager+/manage_table_operations cashier (denial -> table.unlink_denied). Orders are NEVER moved or deleted -- each keeps its orders.table_id; occupancy recomputes per independent table. A not-grouped / foreign / unknown table is an idempotent no_change (no oracle). Deletes the table_groups row (members cascade). Audits table.tables_unlinked with the former group label. Reached ONLY via public.sync_push (table.unlink). MONEY-FREE.';

revoke all on function app.pos_unlink_tables(uuid, uuid, uuid) from public;
revoke all on function app.pos_unlink_tables(uuid, uuid, uuid) from anon;
grant execute on function app.pos_unlink_tables(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. app.pos_tables / app.list_tables -- CREATE OR REPLACE (keep ACLs). Faithful
--    re-creations of the RESTAURANT-OPERATIONS-V1-001 bodies + effective_state
--    (app.table_effective_state) + group_id (LEFT JOIN table_group_members).
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
  --     RESTAURANT-OPERATIONS-V1-001: active_order_count = DERIVED occupancy
  --     (live orders in submitted..served on the table). Multiple active
  --     orders per table are valid (second rounds) — the count is honest, and
  --     the stored manual `status` (reserved/out_of_service floor state) is
  --     unchanged and returned as before.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area, 'status', t.status,
           'active_order_count', coalesce(oc.n, 0),
           -- PILOT-OPERATIONS-CORRECTIONS-001: server-authoritative EFFECTIVE
           -- state (manual status fused with derived occupancy) + the active
           -- link group id (null when the table is not grouped). The client
           -- renders a group as one unit and aggregates member effective states.
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)),
           'group_id', gm.group_id)
           order by t.label, t.id), '[]'::jsonb)
    into v_tables
    from public.tables t
    left join public.table_group_members gm
      on gm.organization_id = t.organization_id and gm.table_id = t.id
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
  'POS/KDS device table read (session-derived scope, 42501 fail-closed) + PILOT-OPERATIONS-CORRECTIONS-001: rows now also carry effective_state (app.table_effective_state -- manual status fused with derived dine-in occupancy) and group_id (the active link group, null when ungrouped). Prior fields (status, active_order_count) unchanged. Money-free; all PIN roles.';

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
           'group_id', gm.group_id)
           order by t.label, t.id), '[]'::jsonb)
    into v_items
    from public.tables t
    left join public.table_group_members gm
      on gm.organization_id = t.organization_id and gm.table_id = t.id
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

  return jsonb_build_object('ok', true, 'entity', 'table', 'tables', v_items);
end;
$$;

comment on function app.list_tables(uuid, uuid, uuid) is
  'GUC-free dining-table LIST for the owner/manager dashboard + PILOT-OPERATIONS-CORRECTIONS-001: rows now also carry effective_state and group_id (see pos_tables). Tombstones EXCLUDED, is_active=false INCLUDED; read-only; scope-safe (R-003); money-free.';

revoke all on function app.pos_tables(uuid, uuid) from public;
grant execute on function app.pos_tables(uuid, uuid) to authenticated;
revoke all on function app.list_tables(uuid, uuid, uuid) from public;
grant execute on function app.list_tables(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. Transport op-type CHECK (+3 table ops) + app.sync_push CREATE OR REPLACE
--    (faithful re-creation of the migration-2 body + 3 dispatch branches).
-- ----------------------------------------------------------------------------
alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink'));

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
      v_target_id  := nullif(v_op ->> 'target_id', '')::uuid;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      v_fingerprint := md5(v_op_type || '|' || v_payload::text);

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
    v_target_id  := nullif(v_op ->> 'target_id', '')::uuid;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink') then
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

    v_fingerprint := md5(v_op_type || '|' || v_payload::text);

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
  'RF-056/RF-061 + ... + PILOT-OPERATIONS-CORRECTIONS-001 (D-010/D-022) SECURITY DEFINER batch push. Faithful re-creation of the migration-2 body + THREE added dispatch branches: table.status_set -> app.pos_set_table_status, table.link -> app.pos_link_tables, table.unlink -> app.pos_unlink_tables (all PIN-session + manage_table_operations, scope from the session, payloads carry only table ids + status). All prior behaviour verbatim (batch cap, revoked-device recording, dedup/replay, dependency guard, per-op subtransactions, finalization, customer_name stamp, menu.availability_set). Authorization INGEST-TIME; scope from the session, never the payload.';

-- ----------------------------------------------------------------------------
-- 9. Activity Log classification -- app.audit_action_has_detail (+table families)
--    and app.audit_safe_detail (+from_status/to_status/group_label). Faithful
--    re-creations (newest bodies) + additive delta.
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
      or p_action =    'pin_session.failed';
$$;

comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 .. RESTAURANT-OPERATIONS-V1-001 + PILOT-OPERATIONS-CORRECTIONS-001: is p_action a SUPPORTED action that may carry a safe payload projection? Now also table.status% / table.tables_% / table.link% / table.unlink% (manual floor status before/after + link/unlink group labels). Gates app.audit_safe_detail.';

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
    'from_status','to_status','group_label'
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
  'ALLOWLIST projection of one audit payload to canonical safe fields + PILOT-OPERATIONS-CORRECTIONS-001: also emits from_status / to_status (closed table-status enum) and group_label (combined floor names) -- never money, never identifiers (T-003 holds). Every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   restore app.sync_push from 20260720100000; restore app.pos_tables / app.list_tables
--     from 20260719100000; restore app.audit_action_has_detail from 20260719110000
--     and app.audit_safe_detail from 20260720090000;
--   restore sync_operations_operation_type_check without the three table ops;
--   drop trigger orders_clear_reservation_on_seat on public.orders;
--   drop function if exists app.clear_table_reservation_on_seat();
--   drop function if exists app.pos_set_table_status(uuid,uuid,uuid,text);
--   drop function if exists app.pos_link_tables(uuid,uuid,uuid,uuid);
--   drop function if exists app.pos_unlink_tables(uuid,uuid,uuid);
--   drop function if exists app.table_effective_state(text,integer);
--   drop table if exists table_group_members; drop table if exists table_groups;
--   alter table public.tables drop constraint if exists tables_org_rest_branch_id_key;  -- B2
-- ============================================================================
