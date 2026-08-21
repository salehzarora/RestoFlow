-- ============================================================================
-- KIOSK-001-PREREQ-MEDIA-READ-POLICY-083 (+ EXPIRY-HARDENING-FIX-084) —
-- kiosk devices may READ menu images, under RF-118 session liveness.
--
-- Phase 2 deliberately kept the private `menu-images` bucket's device read
-- gate POS-only; the Phase-3 kiosk therefore renders the approved no-photo
-- fallback ("KIOSK MEDIA READ POLICY REQUIRED BEFORE FINAL VISUAL
-- ACCEPTANCE"). This migration clears that blocker, and — because it is the
-- migration that FIRST extends the storage capability to a new device type —
-- it also closes the storage-signing expiry gap found during Phase 083
-- instead of shipping it to kiosks.
--
-- app.device_can_read_menu_image is re-emitted with EXACTLY TWO intentional
-- semantic deltas from the shipped 20260704090000 definition:
--
--   1. TYPE WIDENING (083): the device-type allowlist grows from
--      `= 'pos'` to `in ('pos', 'kiosk')`. KDS stays EXCLUDED (T-014).
--   2. RF-118 EXPIRY PARITY (084): the session-liveness chain gains
--      `(ds.expires_at is null or ds.expires_at > now())` — the exact
--      predicate the authoritative restore path and every token-proven
--      device RPC already enforce. Storage signing authorizes purely off the
--      anonymous-principal binding (auth.uid() -> device_sessions
--      .auth_user_id), so without this predicate an EXPIRED-but-unrevoked
--      session could keep minting private image URLs after the RPC family
--      had already started refusing it. Expired (including exactly-now)
--      fails closed; a NULL expires_at remains accepted ONLY for legacy
--      pre-RF-118 compatibility, matching restore_device_session.
--
-- EVERYTHING else is preserved from the shipped body:
--   * auth.uid() required; the anonymous device principal must be BOUND to a
--     live device_sessions row (auth_user_id, recorded at redeem and re-bound
--     on every successful restore — device-type-agnostic since RF-161/MVP);
--   * session is_active + unrevoked; pairing active/unrevoked/undeleted;
--     device is_active/undeleted;
--   * tenant isolation: the path scope's org + restaurant must equal the
--     session's, and the path branch must be 'global'/null or the session
--     branch (app.menu_image_scope: a malformed key parses to no row => deny);
--   * SECURITY DEFINER, stable, locked search_path, authenticated-only.
--
-- The bucket stays PRIVATE. No anon grant, no public bucket, no new bucket,
-- no write policy of any kind for devices (the four RF-110 membership write/
-- read policies and the receipt-logo gate are untouched). The existing
-- `menu_images_device_select` storage policy keeps delegating to this helper
-- and inherits both deltas automatically — it is NOT recreated.
--
-- Bounded residual (documented, by design): this gate controls NEW signing /
-- SELECT authorization. A signed URL minted BEFORE the session expired
-- remains a bearer URL until its own short signature lifetime (~30 min,
-- unchanged here) runs out — signed-URL revocation is storage-signing
-- semantics, not session state.
--
-- FOLLOW-UP (separate ticket, deliberately NOT in this migration):
-- RECEIPT LOGO DEVICE STORAGE EXPIRY PARITY — the historical
-- app.device_can_read_restaurant_logo gate mirrors the same pre-RF-118
-- chain. It is unrelated to enabling kiosk menu images and stays out of this
-- PR's blast radius.
-- ============================================================================

create or replace function app.device_can_read_menu_image(p_object_name text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from app.menu_image_scope(p_object_name) s
    join public.device_sessions ds
      on ds.auth_user_id = auth.uid()
    join public.device_pairings dp
      on dp.id = ds.device_pairing_id
    join public.devices d
      on d.id = ds.device_id
    where ds.is_active
      and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())  -- RF-118 (084)
      and dp.status = 'active'
      and dp.revoked_at is null
      and dp.deleted_at is null
      and d.is_active
      and d.deleted_at is null
      and d.device_type in ('pos', 'kiosk')           -- KDS EXCLUDED (T-014)
      and ds.organization_id = s.organization_id     -- tenant boundary (D-001)
      and ds.restaurant_id   = s.restaurant_id
      and (s.branch_id is null or s.branch_id = ds.branch_id)
  );
$$;

comment on function app.device_can_read_menu_image(text) is
  'DEVICE read gate for the private RF-110 menu-images bucket. Path-derived via app.menu_image_scope (malformed => no row => deny); allows ONLY an ACTIVE, unrevoked, NON-EXPIRED (RF-118: expires_at null-legacy-or-future, added by KIOSK-001-PREREQ-084) device_sessions row bound to auth.uid() (recorded at redeem, re-bound on every successful restore) on an ACTIVE pairing, device is_active AND device_type IN (pos, kiosk) — KIOSK-001-PREREQ-083 widened the POS-only gate; KDS stays EXCLUDED (T-014) — org+restaurant equal to the path scope, branch: path global/null OR equal to the session branch. Read-only; never referenced by a write policy; authenticated-only.';

-- Re-issue the exact intended ACL posture (CREATE OR REPLACE preserves it,
-- but the gate is SECURITY DEFINER — be explicit, never implicit).
revoke all on function app.device_can_read_menu_image(text)    from public;
grant execute on function app.device_can_read_menu_image(text) to authenticated;
