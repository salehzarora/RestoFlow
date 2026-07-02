-- ============================================================================
-- MVP (product-rescue) — app.revoke_device_management: JWT/dashboard device
-- revocation. DECISIONS D-001/D-005/D-006/D-011/D-012/D-013/D-033;
-- RISK R-003 (CRITICAL) / R-007 (offline authorization staleness).
-- ============================================================================
-- The only revocation path today is RF-061 app.revoke_device, whose ACTOR is a
-- PIN session on a paired device. The owner/manager dashboard signs in with a
-- JWT (RF-151/RF-152) and holds NO PIN session, so it can LIST devices (RF-160)
-- but cannot revoke one. This additive, forward-only migration adds the
-- JWT-management analogue: app.revoke_device_management + a thin public
-- SECURITY INVOKER wrapper. No table/column/policy changes.
--
-- GUC-FREE authorization (RF-112 D-033 + the RF-150 hardening lesson):
--   * identity = auth.uid() -> app.current_app_user_id();
--   * the TARGET DEVICE is loaded FIRST and authority is resolved against the
--     device's ACTUAL (org, restaurant, branch) via app.actor_rank_in_scope —
--     never against a caller-supplied scope (RF-150 BLOCKER 1: a branch-A
--     manager can never reach a sibling-branch device by mislabelling a scope);
--   * rank >= app.role_rank('manager') (2) may revoke; an in-scope member below
--     manager gets a COMMITTED device.revoke_management_denied audit +
--     {ok:false, error:'permission_denied'} (return-not-raise so the audit
--     persists, D-013); no covering membership (non-member / cross-org /
--     out-of-scope / anon) raises 42501 (fail closed).
--   NEVER app.current_org_id()/has_scope()/has_role_in_scope(); NEVER
--   app.is_platform_admin() (D-026). No anon / service_role path (D-011).
--
-- EFFECTS mirror app.revoke_device's device-target branch (RF-061 (f)) with the
-- addition of the device flag itself:
--   * devices.is_active = false (the device identity is switched off);
--   * every live pairing (deleted_at IS NULL, status NOT IN
--     ('revoked','code_expired','rejected')) -> status='revoked', revoked_at=now();
--   * every live device session (is_active OR revoked_at IS NULL) ->
--     is_active=false, revoked_at=now().
--   pin_sessions are NOT ended here — app.revoke_device does not end them
--   either: a PIN session is invalidated at USE time (the backing device
--   session/pairing checks in start/validate/sync_push reject a revoked device,
--   and RF-061 records its queued offline ops as rejected 'revoked_device' on
--   reconnect — R-007).
--
-- IDEMPOTENCY (D-033): the RF-112 management_request_results ledger, keyed on
--   (actor_app_user_id, client_request_id), fingerprint over (device org,
--   device id, reason). Replay returns the STORED result (idempotent_replay=
--   true) with no second mutation and no second audit; conflicting reuse of the
--   same key raises 42501; the claim happens BEFORE the mutation (race-safe).
--
-- AUDIT (D-013, append-only): success writes device.revoked_management with the
--   reason + revoked counts (NO secret — no hash / token ref ever appears).
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real
-- tenant data (AGENTS.md).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.revoke_device_management — revoke a device as a JWT dashboard manager+.
-- ---------------------------------------------------------------------------
create or replace function app.revoke_device_management(
  p_client_request_id uuid,
  p_device_id         uuid,
  p_reason            text default null
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
  v_was_active boolean;
  v_reason     text := nullif(btrim(coalesce(p_reason, '')), '');
  v_rank       integer;
  v_fp         text;
  v_replay     jsonb;
  v_pairings   integer;
  v_sessions   integer;
  v_result     jsonb;
begin
  -- (a) authentication + required input (structural -> 42501, rolled back, no audit)
  if v_actor is null then
    raise exception 'revoke_device_management: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'revoke_device_management: client_request_id is required' using errcode = '42501';
  end if;
  if p_device_id is null then
    raise exception 'revoke_device_management: device_id is required' using errcode = '42501';
  end if;

  -- (b) load the TARGET first; authorization is against its ACTUAL scope, never a
  --     caller-supplied one (the RF-150 hardening / RF-112 update_role pattern).
  select d.organization_id, d.restaurant_id, d.branch_id, d.is_active
    into v_org, v_rest, v_branch, v_was_active
    from public.devices d
    where d.id = p_device_id and d.deleted_at is null;
  if v_org is null then
    raise exception 'revoke_device_management: device not found (or deleted)' using errcode = '42501';
  end if;

  -- (c) committed idempotent replay (before authorization -> true idempotency,
  --     the RF-112 convention). The fingerprint embeds the device's org so a key
  --     can never be replayed across organizations; conflicting reuse raises 42501.
  v_fp := md5(jsonb_build_object('org', v_org, 'device', p_device_id, 'reason', v_reason)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'revoke_device_management', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (d) authorization over the device's OWN scope (GUC-free, D-033). 0 => the
  --     caller covers nothing here (non-member / cross-org / sibling branch) => 42501.
  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'revoke_device_management: caller has no active membership covering the device scope' using errcode = '42501';
  end if;
  -- an in-scope member below manager is role-denied: committed audit + {ok:false}.
  if v_rank < app.role_rank('manager') then
    insert into public.audit_events
      (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
    values
      (v_org, v_rest, v_branch, v_actor, null, 'device.revoke_management_denied', v_reason, null,
       jsonb_build_object('attempted_action', 'revoke_device_management', 'device_id', p_device_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device');
  end if;

  -- (e) count what WILL be revoked (the exact live predicates of RF-061
  --     app.revoke_device (e)/(f)); the counts go into the stored idempotency
  --     result + the audit row.
  select count(*) into v_pairings
    from public.device_pairings dp
    where dp.organization_id = v_org and dp.device_id = p_device_id
      and dp.deleted_at is null and dp.status not in ('revoked', 'code_expired', 'rejected');
  select count(*) into v_sessions
    from public.device_sessions ds
    where ds.organization_id = v_org and ds.device_id = p_device_id
      and (ds.is_active or ds.revoked_at is null);

  -- (f) claim idempotency BEFORE mutating (race-safe: a concurrent duplicate is
  --     blocked at the unique key and returns the stored result, never revokes twice).
  v_result := jsonb_build_object(
    'ok', true, 'idempotent_replay', false, 'entity', 'device', 'device_id', p_device_id,
    'pairings_revoked', v_pairings, 'sessions_revoked', v_sessions);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'revoke_device_management', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (g) revoke: device off; live pairings -> revoked; live sessions -> inactive+revoked
  --     (mirrors app.revoke_device (f), plus devices.is_active=false).
  update public.devices set is_active = false
    where id = p_device_id and is_active;
  update public.device_pairings set status = 'revoked', revoked_at = now()
    where organization_id = v_org and device_id = p_device_id
      and deleted_at is null and status not in ('revoked', 'code_expired', 'rejected');
  update public.device_sessions set is_active = false, revoked_at = now()
    where organization_id = v_org and device_id = p_device_id
      and (is_active or revoked_at is null);
  -- pin_sessions are deliberately NOT ended (mirrors app.revoke_device): they are
  -- invalidated at use time by the backing device-session/pairing checks (R-007).

  -- (h) append-only audit (D-013) with reason + counts; no secret ever appears.
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
  values
    (v_org, v_rest, v_branch, v_actor, null, 'device.revoked_management', v_reason,
     jsonb_build_object('device_id', p_device_id, 'is_active', v_was_active,
                        'live_pairings', v_pairings, 'live_sessions', v_sessions),
     jsonb_build_object('device_id', p_device_id, 'is_active', false,
                        'pairings_revoked', v_pairings, 'sessions_revoked', v_sessions));

  return v_result;
end;
$$;

comment on function app.revoke_device_management(uuid, uuid, text) is
  'MVP (D-011/D-013/D-033): JWT/dashboard analogue of RF-061 app.revoke_device. Loads the target device FIRST and authorizes the caller (app.current_app_user_id()) as rank >= manager against the device''s ACTUAL (org, restaurant, branch) via app.actor_rank_in_scope (GUC-free; no covering membership -> 42501; in-scope below manager -> committed device.revoke_management_denied audit + permission_denied). Sets devices.is_active=false, revokes all live device_pairings (status=revoked, revoked_at) and live device_sessions (is_active=false, revoked_at); pin_sessions are invalidated at use time (mirrors RF-061; R-007). Idempotent via the RF-112 management_request_results ledger (per-actor client_request_id; replay returns the stored result, no double-revoke/audit). Audits device.revoked_management with reason + counts; never returns a secret.';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-064 / RF-109 pattern). VOLATILE
--    (default) so PostgREST POST-routes the write; no new privilege.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_device_management(
  p_client_request_id uuid, p_device_id uuid, p_reason text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.revoke_device_management(p_client_request_id, p_device_id, p_reason); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.revoke_device_management(uuid, uuid, text)    from public;
grant execute on function app.revoke_device_management(uuid, uuid, text) to authenticated;
revoke all on function public.revoke_device_management(uuid, uuid, text)    from public;
grant execute on function public.revoke_device_management(uuid, uuid, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.revoke_device_management(uuid, uuid, text);
--   drop function if exists app.revoke_device_management(uuid, uuid, text);
-- ============================================================================
