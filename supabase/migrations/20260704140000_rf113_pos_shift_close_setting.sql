-- ============================================================================
-- RF-113 — per-branch "shift reconciliation" policy: branches.pos_shift_close_enabled
-- + owner-write / member-read / device-read RPCs (DECISION D-011/D-012/D-033).
-- ============================================================================
-- The VISIBLE POS "Close shift & count cash" workflow (RF-113) is optional per
-- restaurant BRANCH, controlled by the owner from the Dashboard. This is a POLICY
-- flag only: the server's internal shift requirement for payments (RF-055) is
-- UNCHANGED — this merely toggles whether the POS shows the reconciliation UI.
--
-- ADDITIVE + FORWARD-ONLY: adds ONE column + THREE small SECURITY DEFINER RPCs.
-- It NEVER edits a prior migration or an existing function (so the RF-112 settings
-- + RF-055 shift + device-read RPCs and their pgTAP are untouched).
--
--   1. branches.pos_shift_close_enabled boolean not null default true
--      (default TRUE so existing demo branches keep RF-113 visible; owner can
--      disable). No money, no float; a plain boolean policy flag.
--   2. app.set_branch_pos_shift_close_enabled(client_request_id, org, restaurant,
--      branch, enabled) — the OWNER write. Reuses the RF-112 settings machinery
--      VERBATIM: actor from app.current_app_user_id(), per-actor idempotency
--      (management_idem_check/claim_request), same-tenant branch-live check, the
--      SAME rank gate as app.update_branch_settings (rank >= restaurant_owner;
--      managers/cashiers/kitchen DENIED -> settings.branch.update_denied audit +
--      permission_denied, no raise), append-only audit (settings.branch.updated).
--   3. app.get_branch_pos_shift_close_enabled(org, restaurant, branch) — the
--      Dashboard READ. Any active member covering the branch may read the flag
--      (rank > 0); cross-tenant returns not_found. So the toggle shows the real
--      persisted state (never a fabricated default in real mode).
--   4. app.get_device_pos_shift_close_enabled(device_id, session_token) — the POS
--      READ. TOKEN-PROVEN exactly like app.get_device_printer_assignments (hash
--      match on a live ACTIVE session/pairing, live device/branch/restaurant);
--      any failure => {ok:false, error:'invalid_session'} (fail closed, no scope
--      leak). Returns ONLY {ok, pos_shift_close_enabled} — no secrets, no money.
--
-- DECISIONS: D-011 (RPC-only sensitive mutation; anon-key clients; no service
-- role), D-012 (rank gate + same-tenant), D-013 (append-only audit), D-033
-- (GUC-free membership/settings). RISK R-003 human RLS/security sign-off pending
-- before serving real tenant data (AGENTS.md).
-- FORWARD-ONLY (Supabase replays on db reset). Manual DOWN at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. the policy column (default TRUE).
-- ----------------------------------------------------------------------------
alter table public.branches
  add column pos_shift_close_enabled boolean not null default true;

comment on column public.branches.pos_shift_close_enabled is
  'RF-113: owner/manager policy — whether the POS shows the "Close shift & count cash" reconciliation UI for this branch. Default true. A POLICY flag only; the server''s internal shift requirement for payments (RF-055) is independent. Written only by app.set_branch_pos_shift_close_enabled (D-011).';

-- ----------------------------------------------------------------------------
-- 2. OWNER write (mirrors app.update_branch_settings' auth/idempotency/audit).
-- ----------------------------------------------------------------------------
create or replace function app.set_branch_pos_shift_close_enabled(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_enabled           boolean
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
  v_new    jsonb;
begin
  if v_actor is null then
    raise exception 'set_branch_pos_shift_close_enabled: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_branch_pos_shift_close_enabled: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'set_branch_pos_shift_close_enabled: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'set_branch_pos_shift_close_enabled: enabled is required' using errcode = '42501';
  end if;

  -- the branch AND its parent restaurant must be LIVE (not soft-deleted).
  if not exists (select 1 from public.branches b
                 join public.restaurants r
                   on r.id = b.restaurant_id and r.organization_id = b.organization_id
                 where b.id = p_branch_id and b.organization_id = p_organization_id
                   and b.restaurant_id = p_restaurant_id
                   and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'set_branch_pos_shift_close_enabled: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'enabled', p_enabled)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_branch_pos_shift_close_enabled', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- SAME rank gate as app.update_branch_settings: rank >= restaurant_owner (3).
  -- managers/cashiers/kitchen are DENIED (conservative branch-settings policy).
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'set_branch_pos_shift_close_enabled: caller has no active membership covering the branch' using errcode = '42501';
  end if;
  if v_rank < 3 then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'settings.branch.update_denied', null,
      jsonb_build_object('branch_id', p_branch_id, 'setting', 'pos_shift_close_enabled'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'branch');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'branch',
                'branch_id', p_branch_id, 'pos_shift_close_enabled', p_enabled);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_branch_pos_shift_close_enabled', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.branches t where t.id = p_branch_id;
  update public.branches set pos_shift_close_enabled = p_enabled where id = p_branch_id;
  select to_jsonb(t) into v_new from public.branches t where t.id = p_branch_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'settings.branch.updated', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_branch_pos_shift_close_enabled(uuid, uuid, uuid, uuid, boolean) is
  'RF-113 (D-011/D-012/D-033): OWNER write of branches.pos_shift_close_enabled. Same auth/idempotency/audit/rank gate as app.update_branch_settings — rank >= restaurant_owner; managers/cashiers/kitchen DENIED (settings.branch.update_denied audit + permission_denied, no raise). Per-actor idempotent; append-only settings.branch.updated audit. Policy flag only (no money, no float).';

create or replace function public.set_branch_pos_shift_close_enabled(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_enabled boolean)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_branch_pos_shift_close_enabled(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_enabled); $$;

revoke all on function app.set_branch_pos_shift_close_enabled(uuid, uuid, uuid, uuid, boolean)    from public;
grant execute on function app.set_branch_pos_shift_close_enabled(uuid, uuid, uuid, uuid, boolean) to authenticated;
revoke all on function public.set_branch_pos_shift_close_enabled(uuid, uuid, uuid, uuid, boolean)    from public;
grant execute on function public.set_branch_pos_shift_close_enabled(uuid, uuid, uuid, uuid, boolean) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Dashboard READ (any active member covering the branch may read the flag).
-- ----------------------------------------------------------------------------
create or replace function app.get_branch_pos_shift_close_enabled(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_rank    integer;
  v_enabled boolean;
begin
  if v_actor is null then
    raise exception 'get_branch_pos_shift_close_enabled: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    -- no membership covering this scope (incl. cross-tenant): reveal nothing.
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  select b.pos_shift_close_enabled into v_enabled
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if v_enabled is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                            'pos_shift_close_enabled', v_enabled);
end;
$$;

comment on function app.get_branch_pos_shift_close_enabled(uuid, uuid, uuid) is
  'RF-113: Dashboard READ of branches.pos_shift_close_enabled. Any active membership covering the branch (rank > 0) may read; no membership / cross-tenant => not_found (no scope leak). Used to initialise the owner toggle to the real persisted state.';

create or replace function public.get_branch_pos_shift_close_enabled(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_branch_pos_shift_close_enabled(p_organization_id, p_restaurant_id, p_branch_id); $$;

revoke all on function app.get_branch_pos_shift_close_enabled(uuid, uuid, uuid)    from public;
grant execute on function app.get_branch_pos_shift_close_enabled(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_branch_pos_shift_close_enabled(uuid, uuid, uuid)    from public;
grant execute on function public.get_branch_pos_shift_close_enabled(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. POS device READ (token-proven, mirrors app.get_device_printer_assignments).
-- ----------------------------------------------------------------------------
create or replace function app.get_device_pos_shift_close_enabled(
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
  v_hash    text;
  v_enabled boolean;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pos_shift_close_enabled');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- token proof EXACTLY like app.get_device_printer_assignments: a live ACTIVE
  -- session on an ACTIVE pairing for THIS device, on a live device + live
  -- branch/restaurant. Read the flag from the device's OWN branch only.
  select b.pos_shift_close_enabled into v_enabled
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    join public.devices d on d.id = ds.device_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id and b.deleted_at is null
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_enabled is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pos_shift_close_enabled');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'pos_shift_close_enabled',
                            'pos_shift_close_enabled', v_enabled, 'server_ts', now());
end;
$$;

comment on function app.get_device_pos_shift_close_enabled(uuid, text) is
  'RF-113: TOKEN-PROVEN POS device read of its OWN branch''s pos_shift_close_enabled (auth mirrors app.get_device_printer_assignments; any failure => invalid_session, fail closed, no scope leak). Returns only {ok, pos_shift_close_enabled} — no secrets, no money. Callable by anonymous authenticated devices (authorization is the token, not membership).';

create or replace function public.get_device_pos_shift_close_enabled(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_device_pos_shift_close_enabled(p_device_id, p_session_token); $$;

revoke all on function app.get_device_pos_shift_close_enabled(uuid, text)    from public;
grant execute on function app.get_device_pos_shift_close_enabled(uuid, text) to authenticated;
revoke all on function public.get_device_pos_shift_close_enabled(uuid, text)    from public;
grant execute on function public.get_device_pos_shift_close_enabled(uuid, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.get_device_pos_shift_close_enabled(uuid, text);
--   drop function if exists app.get_device_pos_shift_close_enabled(uuid, text);
--   drop function if exists public.get_branch_pos_shift_close_enabled(uuid, uuid, uuid);
--   drop function if exists app.get_branch_pos_shift_close_enabled(uuid, uuid, uuid);
--   drop function if exists public.set_branch_pos_shift_close_enabled(uuid, uuid, uuid, uuid, boolean);
--   drop function if exists app.set_branch_pos_shift_close_enabled(uuid, uuid, uuid, uuid, boolean);
--   alter table public.branches drop column if exists pos_shift_close_enabled;
-- ============================================================================
