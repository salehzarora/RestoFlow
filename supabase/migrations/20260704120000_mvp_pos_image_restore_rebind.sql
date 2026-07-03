-- ============================================================================
-- MVP (POS image fix) — re-bind the device storage-read principal at restore.
--
-- PROBLEM (manual finding): uploaded product images show in the dashboard but
-- POS menu cards only ever show the fallback icons.
--
-- ROOT CAUSE: the `menu_images_device_select` storage policy (menu/media
-- sprint) admits a device via `device_sessions.auth_user_id = auth.uid()`,
-- and ONLY app.redeem_device_pairing records that binding — at pairing time.
-- But a device signs in ANONYMOUSLY with a FRESH auth principal on every app
-- launch (RF-161; the pure-Dart client persists no GoTrue session). So the
-- binding matches only during the launch in which the device was paired:
-- after ANY restart (and for every session minted before the binding column
-- existed, where auth_user_id is null) each signed-URL request is policy-
-- denied, the fail-soft resolver returns nothing, and the POS renders
-- imageless cards.
--
-- FIX: app.restore_device_session — the launch-time, TOKEN-PROVEN restore —
-- now also re-binds auth_user_id = auth.uid() on success. The caller has just
-- proven possession of the device-session token (the actual device
-- credential, D-011), so binding the read-only storage capability to its
-- current authenticated principal grants nothing new: the policy stays
-- fail-closed (active session, active pairing, live device, POS type only,
-- own org only — T-014 keeps KDS out). An invalid token exits before the
-- rebind. This also HEALS pre-binding (legacy) sessions on their next
-- restore — no re-pairing needed.
--
-- The function was `stable` (read-only); it becomes VOLATILE for the one-row
-- rebind. Same signature => CREATE OR REPLACE preserves ACLs (grants
-- re-issued below per the house pattern). The public wrapper is unchanged.
-- No policy, table, or other function changes. (RISK R-003: the device-read
-- policy itself remains as shipped, still pending the standing human RLS
-- sign-off.)
-- ============================================================================

create or replace function app.restore_device_session(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash   text;
  v_sid    uuid;
  v_org    uuid;
  v_rest   uuid;
  v_branch uuid;
  v_dtype  text;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_session');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));
  -- The branch + restaurant tombstone joins MIRROR redeem (fail closed on a dead scope):
  -- decommissioning a branch/restaurant (soft-delete) must invalidate restore, not leave the
  -- device serving a tombstoned scope (RISK R-003 / R-007). NOTE: the downstream operational
  -- gates (start_pin_session/sync_push, RF-051/056) do NOT yet re-check these tombstones -- a
  -- pre-existing gap tracked for the human sign-off (ADR RF-161 §7); this closes the redeem/
  -- restore asymmetry introduced here.
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_sid, v_org, v_rest, v_branch, v_dtype
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
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_session');
  end if;
  -- MVP (POS image fix): re-bind the storage-read principal to the CURRENT
  -- (fresh-per-launch) anonymous auth principal. Token proof succeeded above;
  -- the binding is ONLY the menu-image read-policy hook (never a credential).
  -- Skipped when there is no authenticated principal (e.g. direct DB calls).
  if auth.uid() is not null then
    update public.device_sessions
       set auth_user_id = auth.uid()
     where id = v_sid
       and auth_user_id is distinct from auth.uid();
  end if;
  return jsonb_build_object('ok', true, 'entity', 'device_session',
    'device_session_id', v_sid, 'organization_id', v_org, 'restaurant_id', v_rest,
    'branch_id', v_branch, 'device_id', p_device_id, 'device_type', v_dtype);
end;
$$;

comment on function app.restore_device_session(uuid, text) is
  'RF-161: token-proven device-session restore. Returns the live device_session_id + context iff the raw token hashes to an ACTIVE, non-revoked session on an ACTIVE pairing for the device; otherwise invalid_session (fail closed). NEVER returns a token. MVP (POS image fix): a successful restore also re-binds device_sessions.auth_user_id = auth.uid() — devices sign in anonymously with a fresh principal each launch, so the redeem-time storage-policy binding goes stale after the first restart (and is null for pre-binding sessions); the token proof authorizes the rebind, and the menu_images_device_select policy stays fail-closed.';

-- Exact-signature grants (house pattern for recreated functions; the wrapper
-- public.restore_device_session is untouched and keeps delegating).
revoke all on function app.restore_device_session(uuid, text) from public;
grant execute on function app.restore_device_session(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- DOWN (manual):
--   Recreate app.restore_device_session from
--   20260701110000_rf161_device_auth_bridge.sql (the `stable`, read-only
--   version) and re-issue the same revoke/grant pair. No schema changes to
--   undo.
-- ----------------------------------------------------------------------------
