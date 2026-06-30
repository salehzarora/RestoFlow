-- ============================================================================
-- RF-150 — Printer configuration management RPCs + thin public wrappers.
--          PRINTERS_AND_HARDWARE_SPEC §6; DECISIONS D-011/D-013/D-026/D-028/D-031.
-- ============================================================================
-- Owner/manager-only writes for the RF-150 printer_devices / printer_routes config
-- (the RF-059 deny-policies forbid direct client INSERT/UPDATE/DELETE). These run
-- as SECURITY DEFINER (table owner), search_path locked, granted to authenticated;
-- thin public.* SECURITY INVOKER wrappers make them Data-API-reachable without
-- exposing the `app` schema (the RF-109 menu-management pattern).
--
-- Authorization (membership-based, like RF-090/RF-109):
--   - structural failures (unauthenticated, no active membership in the target org,
--     caller scope does not cover the target, cross-org id, bad input) RAISE 42501
--     -> rolled back, no audit (RF-053 convention).
--   - role denial (caller IS an active member covering the scope but lacks a WRITE
--     role) writes a committed `printer.<entity>.<action>_denied` audit row and
--     RETURNS {ok:false, error:'permission_denied'} (RF-053 return-not-raise so the
--     audit persists). Write roles: org_owner / restaurant_owner / manager only
--     (D-028; cashier/kitchen_staff/accountant denied). platform_admin is NEVER a
--     tenant write path (D-026): no app.is_platform_admin() reference.
-- Money: NONE — printer config has no money columns (D-007/T-003 spirit).
-- Soft delete (D-020): sets deleted_at=now(); never physical. Deleting a printer
--   also soft-deletes its live routes (a removed printer must not stay routed).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Internal helpers (revoked from public; called only inside the DEFINER RPCs).
-- ---------------------------------------------------------------------------

-- Structural gate + write-role check. Raises 42501 for non-member / wrong-org /
-- scope-miss; returns TRUE when the caller has a write role (org_owner/
-- restaurant_owner/manager) in scope, FALSE when the caller covers the scope but
-- lacks a write role (role-denied path). Mirrors app.menu_guard (RF-109).
create or replace function app.printer_guard(p_org uuid, p_restaurant uuid, p_branch uuid)
  returns boolean
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if app.current_app_user_id() is null then
    raise exception 'printer: authentication required' using errcode = '42501';
  end if;
  if app.current_org_id() is null or app.current_org_id() <> p_org then
    raise exception 'printer: no active membership in the target organization' using errcode = '42501';
  end if;
  if not app.has_scope(p_org, p_restaurant, p_branch) then
    raise exception 'printer: caller scope does not cover the target' using errcode = '42501';
  end if;
  return app.has_role_in_scope(p_org, p_restaurant, p_branch,
           'org_owner', 'restaurant_owner', 'manager');
end;
$$;

-- Append-only audit writer for printer-config mutations (actor = resolved app_user;
-- no device — this is an owner/manager dashboard action). Mirrors app.menu_audit.
create or replace function app.printer_audit(
  p_org uuid, p_restaurant uuid, p_branch uuid, p_action text, p_old jsonb, p_new jsonb)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
  values
    (p_org, p_restaurant, p_branch, app.current_app_user_id(), null, p_action, null, p_old, p_new);
end;
$$;

revoke all on function app.printer_guard(uuid, uuid, uuid) from public;
revoke all on function app.printer_audit(uuid, uuid, uuid, text, jsonb, jsonb) from public;

-- ---------------------------------------------------------------------------
-- 1. app.upsert_printer_device — create/update a printer at a branch.
-- ---------------------------------------------------------------------------
create or replace function app.upsert_printer_device(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_id                uuid    default null,
  p_display_name      text    default null,
  p_connection_type   text    default null,
  p_role              text    default null,
  p_paper_width       text    default '80mm',
  p_connection_config jsonb   default '{}'::jsonb,
  p_is_enabled        boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_found_org    uuid;
  v_found_rest   uuid;
  v_found_branch uuid;
  v_id           uuid;
  v_action       text;
  v_old          jsonb;
  v_new          jsonb;
  v_config       jsonb := coalesce(p_connection_config, '{}'::jsonb);
  v_width        text  := coalesce(p_paper_width, '80mm');
begin
  if not app.printer_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'printer.printer_device.upsert_denied', null,
      jsonb_build_object('entity', 'printer_device', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'printer_device');
  end if;

  -- input validation (no money; integer-free).
  if p_display_name is null or length(btrim(p_display_name)) = 0 then
    raise exception 'upsert_printer_device: display_name is required' using errcode = '42501';
  end if;
  if p_connection_type is null or p_connection_type not in ('network', 'usb', 'bluetooth') then
    raise exception 'upsert_printer_device: connection_type must be network|usb|bluetooth' using errcode = '42501';
  end if;
  if p_role is null or p_role not in ('receipt', 'kitchen') then
    raise exception 'upsert_printer_device: role must be receipt|kitchen' using errcode = '42501';
  end if;
  if v_width not in ('58mm', '80mm') then
    raise exception 'upsert_printer_device: paper_width must be 58mm|80mm' using errcode = '42501';
  end if;
  if jsonb_typeof(v_config) <> 'object' then
    raise exception 'upsert_printer_device: connection_config must be a JSON object' using errcode = '42501';
  end if;

  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.printer_devices where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'upsert_printer_device: id belongs to another organization' using errcode = '42501';
      end if;
      -- org/restaurant/branch are IMMUTABLE on update (no scope move / hijack).
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'upsert_printer_device: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.printer_devices
      (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role,
       paper_width, connection_config, is_enabled)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, btrim(p_display_name), p_connection_type, p_role,
       v_width, v_config, coalesce(p_is_enabled, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.printer_devices t where t.id = p_id;
    update public.printer_devices set
      display_name = btrim(p_display_name), connection_type = p_connection_type, role = p_role,
      paper_width = v_width, connection_config = v_config, is_enabled = coalesce(p_is_enabled, true),
      revision = revision + 1
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.printer_devices t where t.id = v_id;
  perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'printer.printer_device.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'printer_device', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. app.set_printer_route — create/update a station -> printer route (idempotent
--    on the live (station, printer) edge).
-- ---------------------------------------------------------------------------
create or replace function app.set_printer_route(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_station_id        uuid,
  p_printer_device_id uuid,
  p_is_enabled        boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_id     uuid;
  v_action text;
  v_old    jsonb;
  v_new    jsonb;
begin
  if not app.printer_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'printer.printer_route.set_denied', null,
      jsonb_build_object('entity', 'printer_route', 'station_id', p_station_id, 'printer_device_id', p_printer_device_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'printer_route');
  end if;

  if p_station_id is null or p_printer_device_id is null then
    raise exception 'set_printer_route: station_id and printer_device_id are required' using errcode = '42501';
  end if;
  -- pre-validate same-branch membership for a clean 42501 (the composite FKs would
  -- otherwise raise a foreign_key_violation). Live (not soft-deleted) only.
  if not exists (
    select 1 from public.stations s
    where s.id = p_station_id and s.organization_id = p_organization_id
      and s.restaurant_id = p_restaurant_id and s.branch_id = p_branch_id and s.deleted_at is null) then
    raise exception 'set_printer_route: station is not in the target branch' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.printer_devices d
    where d.id = p_printer_device_id and d.organization_id = p_organization_id
      and d.restaurant_id = p_restaurant_id and d.branch_id = p_branch_id and d.deleted_at is null) then
    raise exception 'set_printer_route: printer_device is not in the target branch' using errcode = '42501';
  end if;

  -- idempotent on the LIVE (station, printer) edge: update if present, else insert.
  select id into v_id from public.printer_routes
    where organization_id = p_organization_id and restaurant_id = p_restaurant_id
      and branch_id = p_branch_id and station_id = p_station_id
      and printer_device_id = p_printer_device_id and deleted_at is null;

  if v_id is null then
    v_id := gen_random_uuid();
    insert into public.printer_routes
      (id, organization_id, restaurant_id, branch_id, station_id, printer_device_id, is_enabled)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_station_id, p_printer_device_id, coalesce(p_is_enabled, true));
    v_action := 'created';
  else
    select to_jsonb(t) into v_old from public.printer_routes t where t.id = v_id;
    update public.printer_routes set is_enabled = coalesce(p_is_enabled, true) where id = v_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.printer_routes t where t.id = v_id;
  perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'printer.printer_route.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'printer_route', 'id', v_id, 'action', v_action);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. app.soft_delete_printer_device — tombstone a printer + its live routes.
-- ---------------------------------------------------------------------------
create or replace function app.soft_delete_printer_device(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_id              uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_found_org uuid;
  v_old       jsonb;
  v_routes    integer := 0;
begin
  if not app.printer_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'printer.printer_device.delete_denied', null,
      jsonb_build_object('entity', 'printer_device', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'printer_device');
  end if;
  if p_id is null then
    raise exception 'soft_delete_printer_device: id is required' using errcode = '42501';
  end if;

  select organization_id into v_found_org from public.printer_devices where id = p_id and deleted_at is null;
  if v_found_org is null then
    raise exception 'soft_delete_printer_device: printer not found (or already deleted)' using errcode = '42501';
  end if;
  if v_found_org <> p_organization_id then
    raise exception 'soft_delete_printer_device: id belongs to another organization' using errcode = '42501';
  end if;

  select to_jsonb(t) into v_old from public.printer_devices t where t.id = p_id;
  -- a removed printer must not stay routed: soft-delete its live routes too.
  update public.printer_routes set deleted_at = now()
    where printer_device_id = p_id and deleted_at is null;
  get diagnostics v_routes = row_count;
  update public.printer_devices set deleted_at = now() where id = p_id;

  perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'printer.printer_device.deleted', v_old,
    jsonb_build_object('id', p_id, 'routes_removed', v_routes));
  return jsonb_build_object('ok', true, 'entity', 'printer_device', 'id', p_id, 'action', 'deleted', 'routes_removed', v_routes);
end;
$$;

-- least privilege: authenticated only; never anon; never service_role.
revoke all on function app.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean) from public;
revoke all on function app.set_printer_route(uuid, uuid, uuid, uuid, uuid, boolean) from public;
revoke all on function app.soft_delete_printer_device(uuid, uuid, uuid, uuid) from public;
grant execute on function app.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean) to authenticated;
grant execute on function app.set_printer_route(uuid, uuid, uuid, uuid, uuid, boolean) to authenticated;
grant execute on function app.soft_delete_printer_device(uuid, uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Thin public.* SECURITY INVOKER wrappers (the RF-109/125/126 pattern): make
--    the management RPCs Data-API-reachable without exposing the `app` schema.
--    VOLATILE (default) so PostgREST POST-routes the writes; no new privilege
--    (the caller already holds EXECUTE on the app.* delegate).
-- ---------------------------------------------------------------------------
create or replace function public.upsert_printer_device(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_id                uuid    default null,
  p_display_name      text    default null,
  p_connection_type   text    default null,
  p_role              text    default null,
  p_paper_width       text    default '80mm',
  p_connection_config jsonb   default '{}'::jsonb,
  p_is_enabled        boolean default true
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.upsert_printer_device(
    p_organization_id, p_restaurant_id, p_branch_id, p_id, p_display_name,
    p_connection_type, p_role, p_paper_width, p_connection_config, p_is_enabled);
$$;

create or replace function public.set_printer_route(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_station_id        uuid,
  p_printer_device_id uuid,
  p_is_enabled        boolean default true
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.set_printer_route(
    p_organization_id, p_restaurant_id, p_branch_id, p_station_id, p_printer_device_id, p_is_enabled);
$$;

create or replace function public.soft_delete_printer_device(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_id              uuid
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.soft_delete_printer_device(p_organization_id, p_restaurant_id, p_branch_id, p_id);
$$;

revoke all on function public.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean) from public;
revoke all on function public.set_printer_route(uuid, uuid, uuid, uuid, uuid, boolean) from public;
revoke all on function public.soft_delete_printer_device(uuid, uuid, uuid, uuid) from public;
grant execute on function public.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean) to authenticated;
grant execute on function public.set_printer_route(uuid, uuid, uuid, uuid, uuid, boolean) to authenticated;
grant execute on function public.soft_delete_printer_device(uuid, uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.soft_delete_printer_device(uuid, uuid, uuid, uuid);
--   drop function if exists public.set_printer_route(uuid, uuid, uuid, uuid, uuid, boolean);
--   drop function if exists public.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean);
--   drop function if exists app.soft_delete_printer_device(uuid, uuid, uuid, uuid);
--   drop function if exists app.set_printer_route(uuid, uuid, uuid, uuid, uuid, boolean);
--   drop function if exists app.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean);
--   drop function if exists app.printer_audit(uuid, uuid, uuid, text, jsonb, jsonb);
--   drop function if exists app.printer_guard(uuid, uuid, uuid);
-- ============================================================================
