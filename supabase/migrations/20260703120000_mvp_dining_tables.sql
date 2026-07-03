-- ============================================================================
-- MVP (product-rescue) — dining tables: `public.tables` schema + RLS,
-- owner/manager management RPCs (upsert / set_status / soft_delete / list),
-- and the device-side app.pos_tables read. DOMAIN_MODEL §5.1 (`tables` is the
-- canonical D-017 name); DECISIONS D-001/D-002/D-011/D-012/D-013/D-017/D-020/
-- D-033; RISK R-003. NO money columns anywhere (a dining table is money-free
-- by nature; D-007 is honored vacuously — no float can sneak in).
-- ============================================================================
-- WHY: orders have carried a non-FK `table_id` since RF-052 ("no backend tables
-- table yet"), so the POS cannot offer a real table picker and the KDS cannot
-- show a human table label. This migration adds the missing floor entity:
--   * `public.tables` — org/restaurant/branch-scoped (branch REQUIRED: a dining
--     table physically exists at exactly one branch), label + seats + area +
--     a floor status (available|occupied|reserved|out_of_service), is_active,
--     timestamps + deleted_at tombstone (D-020). One LIVE label per branch
--     (case-insensitive partial unique index).
--   * Dashboard management RPCs (RF-160/RF-112 template): GUC-free
--     app.actor_rank_in_scope authorization (D-033), manager+ writes,
--     client_request_id idempotency via the RF-112 management_request_results
--     ledger, committed *_denied audits + {ok:false, error:'permission_denied'}
--     for in-scope rank-1 members, 42501 fail-closed for non-members/cross-org.
--     set_table_status / soft_delete_table load the TARGET ROW FIRST and
--     authorize against ITS actual scope (the RF-150-hardening /
--     revoke_device_management pattern) — a sibling-branch manager can never
--     reach the row by mislabelling a scope.
--   * app.pos_tables — the POS/KDS device read: EXACT pos_menu session/device
--     validation (PIN session valid + backing device session/pairing active +
--     device match, 42501 fail-closed), scope derived from the SESSION, never
--     the payload. All PIN roles allowed (kitchen included — a table label is
--     money-free, so T-003 needs no redaction here).
--
-- RLS (D-012 layer 1, RF-059 per-command shape): enabled + FORCED. SELECT
-- mirrors printer_devices (org GUC + has_scope; every member role including
-- cashier/kitchen_staff may read — no money on the row). Direct writes are
-- DENIED by policy AND never granted — all writes flow through the RPCs below.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real
-- tenant data (AGENTS.md).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. public.tables — a physical dining table (or seating spot) at a branch.
--    Composite same-org FK to branches (the printer_devices shape): a
--    cross-organization or cross-branch reference is STRUCTURALLY impossible
--    (D-012 layer 4).
-- ----------------------------------------------------------------------------
create table tables (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null references organizations (id) on delete restrict,
  restaurant_id   uuid        not null,
  branch_id       uuid        not null,
  label           text        not null check (length(btrim(label)) > 0),
  seats           integer     check (seats is null or seats > 0),
  area            text,
  status          text        not null default 'available'
                              check (status in ('available', 'occupied', 'reserved', 'out_of_service')),
  is_active       boolean     not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table tables is
  'MVP (DOMAIN_MODEL §5.1, D-017 canonical name): a physical dining table at a branch, for dine-in orders (orders.table_id references this logically; RF-052 kept it non-FK). Tenant-scoped org/restaurant/branch (branch REQUIRED — a table exists at exactly one branch) with the composite same-org FK to branches (D-012 layer 4). status = available|occupied|reserved|out_of_service (floor state); is_active = configuration switch; deleted_at = sync tombstone (D-020). One LIVE label per branch (case-insensitive). NO money columns. Writes are owner/manager RPCs only (D-011); direct DML is RLS-denied + unGRANTed.';
comment on column tables.deleted_at is
  'Soft-delete tombstone (D-020). NULL = live row.';

-- one LIVE label per branch, case-insensitive; re-creatable after a soft-delete.
create unique index tables_branch_live_label_key
  on tables (organization_id, restaurant_id, branch_id, lower(label))
  where deleted_at is null;

-- tenant filtering + composite-FK support (all rows, incl. tombstones for sync).
create index tables_org_rest_branch_idx on tables (organization_id, restaurant_id, branch_id);

create trigger tables_set_updated_at before update on tables
  for each row execute function app.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. RLS (RF-059 per-command shape; the printer_devices mirror). SELECT is org
--    + scope gated for EVERY member role (kitchen/cashier included — the row is
--    money-free); direct INSERT/UPDATE/DELETE are DENIED (writes are the
--    SECURITY DEFINER RPCs below, which run as the BYPASSRLS owner).
-- ----------------------------------------------------------------------------
alter table tables enable row level security;
alter table tables force  row level security;

create policy tables_sel on tables for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy tables_ins_deny on tables for insert to authenticated with check (false);
create policy tables_upd_deny on tables for update to authenticated using (false) with check (false);
create policy tables_del_deny on tables for delete to authenticated using (false);

grant select on tables to authenticated;   -- reads only; writes are NEVER granted

-- ----------------------------------------------------------------------------
-- 3. app.upsert_table — create/update a dining table (manager+; idempotent;
--    audited). The RF-112/RF-160 management template: structural failures RAISE
--    42501 (rolled back, no audit); an in-scope member below manager gets a
--    COMMITTED table.upsert_denied audit + {ok:false, error:'permission_denied'};
--    success mutates + audits + stores the idempotency result. org/restaurant/
--    branch are IMMUTABLE on update (no scope move). seats/area are REPLACED by
--    the passed values (null clears) — full-replace upsert semantics, like
--    upsert_printer_device. `status` is NOT writable here (set_table_status).
-- ----------------------------------------------------------------------------
create or replace function app.upsert_table(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_id                uuid    default null,
  p_label             text    default null,
  p_seats             integer default null,
  p_area              text    default null,
  p_is_active         boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid := app.current_app_user_id();
  v_label        text := btrim(coalesce(p_label, ''));
  v_area         text := nullif(btrim(coalesce(p_area, '')), '');
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
  -- (a) authentication + required input (structural -> 42501, rolled back, no audit)
  if v_actor is null then
    raise exception 'upsert_table: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'upsert_table: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'upsert_table: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;

  -- (b) structural input validation (money-free entity; nothing to round)
  if length(v_label) = 0 then
    raise exception 'upsert_table: label is required' using errcode = '42501';
  end if;
  if p_seats is not null and p_seats <= 0 then
    raise exception 'upsert_table: seats must be a positive integer' using errcode = '42501';
  end if;
  -- the target branch must exist in the SAME org/restaurant and be LIVE (never
  -- create floor config on a tombstoned scope; clean 42501 instead of an FK error).
  if not exists (
       select 1 from public.branches b
       where b.id = p_branch_id and b.organization_id = p_organization_id
         and b.restaurant_id = p_restaurant_id and b.deleted_at is null) then
    raise exception 'upsert_table: branch not found in organization/restaurant or is soft-deleted' using errcode = '42501';
  end if;

  -- (c) update-path target checks: same-org + scope immutable (printer template)
  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.tables where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'upsert_table: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'upsert_table: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  -- (d) committed idempotent replay (before authorization -> true idempotency, RF-112)
  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'id', p_id, 'label', v_label, 'seats', p_seats,
              'area', v_area, 'active', coalesce(p_is_active, true))::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'upsert_table', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (e) GUC-free authorization over the PASSED scope (D-033). 0 => not a
  --     covering member => structural 42501; rank 1 => audited permission_denied.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'upsert_table: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'table.upsert_denied', null, jsonb_build_object('entity', 'table', 'id', p_id, 'label', v_label));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  -- (f) resolve create-vs-update, claim idempotency BEFORE mutating (race-safe)
  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    v_action := 'created';
  else
    v_id := p_id;
    v_action := 'updated';
  end if;
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table',
                'id', v_id, 'action', v_action);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'upsert_table', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (g) mutate + append-only audit (D-013)
  if v_action = 'created' then
    insert into public.tables (id, organization_id, restaurant_id, branch_id, label, seats, area, is_active)
    values (v_id, p_organization_id, p_restaurant_id, p_branch_id, v_label, p_seats, v_area, coalesce(p_is_active, true));
  else
    select to_jsonb(t) into v_old from public.tables t where t.id = v_id;
    update public.tables set
      label = v_label, seats = p_seats, area = v_area, is_active = coalesce(p_is_active, true)
    where id = v_id;
  end if;

  select to_jsonb(t) into v_new from public.tables t where t.id = v_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'table.' || v_action, v_old, v_new);
  return v_result;
end;
$$;

comment on function app.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean) is
  'MVP (D-033, DOMAIN_MODEL §5.1): create/update a dining table as a dashboard manager+. GUC-free (app.actor_rank_in_scope over the PASSED org/restaurant/branch); 42501 for unauthenticated/non-member/cross-org/dead-branch/immutable-scope violations; in-scope rank-1 -> committed table.upsert_denied audit + permission_denied. Idempotent via the RF-112 management ledger (per-actor client_request_id; conflicting reuse -> 42501). Label unique per branch among LIVE rows (case-insensitive; duplicate -> unique_violation). status is NOT writable here (see set_table_status). Audits table.created/table.updated. No money anywhere.';

-- ----------------------------------------------------------------------------
-- 4. app.set_table_status — floor-state change. Loads the table FIRST and
--    authorizes against ITS scope (the revoke_device_management pattern);
--    any -> any transition among the four states is allowed (floor state is
--    operational, not a guarded lifecycle).
-- ----------------------------------------------------------------------------
create or replace function app.set_table_status(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_table_id          uuid,
  p_status            text
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
  v_new    jsonb;
begin
  -- (a) authentication + required/valid input (structural -> 42501)
  if v_actor is null then
    raise exception 'set_table_status: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_table_status: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_table_id is null then
    raise exception 'set_table_status: organization_id and table_id are required' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('available', 'occupied', 'reserved', 'out_of_service') then
    raise exception 'set_table_status: status must be available|occupied|reserved|out_of_service' using errcode = '42501';
  end if;

  -- (b) load the TARGET first (live only); authorization is against its ACTUAL
  --     scope, never a caller-supplied one. The passed org is a cross-check.
  select organization_id, restaurant_id, branch_id into v_org, v_rest, v_branch
    from public.tables where id = p_table_id and deleted_at is null;
  if v_org is null then
    raise exception 'set_table_status: table not found (or deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'set_table_status: table belongs to another organization' using errcode = '42501';
  end if;

  -- (c) committed idempotent replay (fingerprint embeds the ROW org -> never crosses org)
  v_fp := md5(jsonb_build_object('org', v_org, 'table', p_table_id, 'status', p_status)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_table_status', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (d) authorization over the row's OWN scope (GUC-free, D-033). 0 => sibling
  --     branch / non-member / cross-org => 42501; rank 1 => audited denial.
  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'set_table_status: caller has no active membership covering the table scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'table.status_denied', null, jsonb_build_object('entity', 'table', 'id', p_table_id, 'to_status', p_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  -- (e) claim idempotency BEFORE mutating (race-safe), then mutate + audit.
  --     Any -> any among the four states (re-setting the same state is a no-op write).
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table',
                'id', p_table_id, 'status', p_status);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_table_status', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.tables t where t.id = p_table_id;
  update public.tables set status = p_status where id = p_table_id;
  select to_jsonb(t) into v_new from public.tables t where t.id = p_table_id;
  perform app.management_audit(v_org, v_rest, v_branch, 'table.status_set', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_table_status(uuid, uuid, uuid, text) is
  'MVP (D-033): set a dining table''s floor status (available|occupied|reserved|out_of_service; any->any allowed). Loads the target FIRST and authorizes rank >= manager against the table''s ACTUAL (org, restaurant, branch) via app.actor_rank_in_scope (the RF-150-hardening pattern) — a sibling-branch manager resolves rank 0 -> 42501; the passed organization_id is a cross-check (mismatch -> 42501). In-scope rank-1 -> committed table.status_denied audit + permission_denied. Idempotent via the RF-112 management ledger. Audits table.status_set.';

-- ----------------------------------------------------------------------------
-- 5. app.soft_delete_table — tombstone a dining table (D-020). Same row-scope
--    authorization as set_table_status.
-- ----------------------------------------------------------------------------
create or replace function app.soft_delete_table(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_table_id          uuid
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
    raise exception 'soft_delete_table: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'soft_delete_table: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_table_id is null then
    raise exception 'soft_delete_table: organization_id and table_id are required' using errcode = '42501';
  end if;

  -- load the TARGET first (live only); authorize against ITS actual scope.
  select organization_id, restaurant_id, branch_id into v_org, v_rest, v_branch
    from public.tables where id = p_table_id and deleted_at is null;
  if v_org is null then
    raise exception 'soft_delete_table: table not found (or already deleted)' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'soft_delete_table: table belongs to another organization' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', v_org, 'table', p_table_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'soft_delete_table', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'soft_delete_table: caller has no active membership covering the table scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, v_branch,
      'table.delete_denied', null, jsonb_build_object('entity', 'table', 'id', p_table_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'table',
                'id', p_table_id, 'action', 'deleted');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'soft_delete_table', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.tables t where t.id = p_table_id;
  update public.tables set deleted_at = now() where id = p_table_id;
  perform app.management_audit(v_org, v_rest, v_branch, 'table.deleted', v_old,
    jsonb_build_object('id', p_table_id, 'deleted', true));
  return v_result;
end;
$$;

comment on function app.soft_delete_table(uuid, uuid, uuid) is
  'MVP (D-020/D-033): tombstone a dining table (deleted_at = now(); never physical). Loads the target FIRST and authorizes rank >= manager against its ACTUAL scope (sibling-branch manager -> 42501; passed org mismatch -> 42501; in-scope rank-1 -> committed table.delete_denied audit + permission_denied). Idempotent via the RF-112 management ledger; a re-call on an already-deleted id raises not-found 42501. Audits table.deleted. The label slot is reusable afterwards (the live-label unique index is partial).';

-- ----------------------------------------------------------------------------
-- 6. app.list_tables — the dashboard MANAGEMENT read (manager+; the RF-160
--    list_devices template). Tombstones excluded; is_active=false INCLUDED
--    (the dashboard shows disabled tables); ordered by label.
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
           'status', t.status, 'is_active', t.is_active, 'branch_id', t.branch_id)
           order by t.label, t.id), '[]'::jsonb)
    into v_items
    from public.tables t
    where t.organization_id = p_organization_id
      and t.restaurant_id   = p_restaurant_id
      and (p_branch_id is null or t.branch_id = p_branch_id)
      and t.deleted_at is null;

  return jsonb_build_object('ok', true, 'entity', 'table', 'tables', v_items);
end;
$$;

comment on function app.list_tables(uuid, uuid, uuid) is
  'MVP (D-033, RF-160 template): GUC-free dining-table LIST for the owner/manager dashboard. app.actor_rank_in_scope over the PASSED (org, restaurant, branch?) — 0 -> 42501, < manager -> permission_denied envelope. Returns {ok, entity:table, tables:[{id,label,seats,area,status,is_active,branch_id}]} ordered by label: tombstones EXCLUDED, is_active=false INCLUDED (management view). Read-only; scope-safe (no GUC trusted; R-003). Money-free.';

-- ----------------------------------------------------------------------------
-- 7. app.pos_tables — the POS/KDS device read. Session/device validation is
--    copied VERBATIM from app.pos_menu (A8; 42501 fail-closed); scope derives
--    from the PIN session, never the payload. ACTIVE + non-tombstoned rows of
--    the SESSION branch only. All PIN roles allowed (money-free — no T-003
--    redaction needed; kitchen may map orders.table_id -> label).
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
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area, 'status', t.status)
           order by t.label, t.id), '[]'::jsonb)
    into v_tables
    from public.tables t
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
  'MVP (D-011, DOMAIN_MODEL §5.1): POS/KDS dining-table read RPC. STABLE + SECURITY DEFINER + search_path=''''. Validates the PIN session + active device session/pairing + device match EXACTLY like app.pos_menu (A8; 42501 fail-closed) and derives org/restaurant/branch from the SESSION, never the payload. Returns {ok, entity:tables, tables:[{id,label,seats,area,status}], server_ts} — ACTIVE + non-tombstoned rows of the session branch only, ordered by label. ALL PIN roles allowed (kitchen included): a dining table is money-free, so T-003 needs no redaction. Read-only; no audit; org+restaurant+branch filter is the isolation boundary (R-003).';

-- ----------------------------------------------------------------------------
-- 8. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 / RF-160 pattern).
--    Write wrappers stay VOLATILE (PostgREST POST-routes them); the pure reads
--    mirror their delegates (pos_tables STABLE like pos_menu).
-- ----------------------------------------------------------------------------
create or replace function public.upsert_table(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_id uuid default null, p_label text default null, p_seats integer default null,
  p_area text default null, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.upsert_table(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_id, p_label, p_seats, p_area, p_is_active); $$;

create or replace function public.set_table_status(
  p_client_request_id uuid, p_organization_id uuid, p_table_id uuid, p_status text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_table_status(p_client_request_id, p_organization_id, p_table_id, p_status); $$;

create or replace function public.soft_delete_table(
  p_client_request_id uuid, p_organization_id uuid, p_table_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.soft_delete_table(p_client_request_id, p_organization_id, p_table_id); $$;

create or replace function public.list_tables(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_tables(p_organization_id, p_restaurant_id, p_branch_id); $$;

create or replace function public.pos_tables(
  p_pin_session_id uuid, p_device_id uuid)
  returns jsonb language sql stable security invoker set search_path = ''
as $$ select app.pos_tables(p_pin_session_id, p_device_id); $$;

-- ----------------------------------------------------------------------------
-- 9. Grants: authenticated only (never anon / service_role; D-011).
-- ----------------------------------------------------------------------------
revoke all on function app.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean) from public;
revoke all on function app.set_table_status(uuid, uuid, uuid, text)  from public;
revoke all on function app.soft_delete_table(uuid, uuid, uuid)       from public;
revoke all on function app.list_tables(uuid, uuid, uuid)             from public;
revoke all on function app.pos_tables(uuid, uuid)                    from public;
grant execute on function app.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean) to authenticated;
grant execute on function app.set_table_status(uuid, uuid, uuid, text)  to authenticated;
grant execute on function app.soft_delete_table(uuid, uuid, uuid)       to authenticated;
grant execute on function app.list_tables(uuid, uuid, uuid)             to authenticated;
grant execute on function app.pos_tables(uuid, uuid)                    to authenticated;

revoke all on function public.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean) from public;
revoke all on function public.set_table_status(uuid, uuid, uuid, text)  from public;
revoke all on function public.soft_delete_table(uuid, uuid, uuid)       from public;
revoke all on function public.list_tables(uuid, uuid, uuid)             from public;
revoke all on function public.pos_tables(uuid, uuid)                    from public;
grant execute on function public.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean) to authenticated;
grant execute on function public.set_table_status(uuid, uuid, uuid, text)  to authenticated;
grant execute on function public.soft_delete_table(uuid, uuid, uuid)       to authenticated;
grant execute on function public.list_tables(uuid, uuid, uuid)             to authenticated;
grant execute on function public.pos_tables(uuid, uuid)                    to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.pos_tables(uuid, uuid);
--   drop function if exists public.list_tables(uuid, uuid, uuid);
--   drop function if exists public.soft_delete_table(uuid, uuid, uuid);
--   drop function if exists public.set_table_status(uuid, uuid, uuid, text);
--   drop function if exists public.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean);
--   drop function if exists app.pos_tables(uuid, uuid);
--   drop function if exists app.list_tables(uuid, uuid, uuid);
--   drop function if exists app.soft_delete_table(uuid, uuid, uuid);
--   drop function if exists app.set_table_status(uuid, uuid, uuid, text);
--   drop function if exists app.upsert_table(uuid, uuid, uuid, uuid, uuid, text, integer, text, boolean);
--   drop table if exists public.tables;
-- ============================================================================
