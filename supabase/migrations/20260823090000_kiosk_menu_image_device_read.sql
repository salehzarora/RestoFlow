-- ============================================================================
-- KIOSK-001-PREREQ-MEDIA-READ-POLICY-083 — kiosk devices may READ menu images.
--
-- Phase 2 deliberately kept the private `menu-images` bucket's device read
-- gate POS-only; the Phase-3 kiosk therefore renders the approved no-photo
-- fallback ("KIOSK MEDIA READ POLICY REQUIRED BEFORE FINAL VISUAL
-- ACCEPTANCE"). This migration clears that blocker with the SMALLEST possible
-- server delta: app.device_can_read_menu_image is re-emitted with its device
-- type allowlist widened from `= 'pos'` to `in ('pos', 'kiosk')`.
--
-- EVERYTHING else is byte-identical to the shipped 20260704090000 body:
--   * auth.uid() required; the anonymous device principal must be BOUND to a
--     live device_sessions row (auth_user_id, recorded at redeem and re-bound
--     on every successful restore — device-type-agnostic since RF-161/MVP);
--   * session is_active + unrevoked; pairing active/unrevoked/undeleted;
--     device is_active/undeleted;
--   * KDS remains EXCLUDED (T-014);
--   * tenant isolation: the path scope's org + restaurant must equal the
--     session's, and the path branch must be 'global'/null or the session
--     branch (app.menu_image_scope: a malformed key parses to no row => deny);
--   * SECURITY DEFINER, stable, locked search_path, authenticated-only.
--
-- The bucket stays PRIVATE. No anon grant, no public bucket, no new bucket,
-- no write policy of any kind for devices (the four RF-110 membership write/
-- read policies and the receipt-logo gate are untouched). The existing
-- `menu_images_device_select` storage policy keeps delegating to this helper
-- and inherits the narrower POS+KIOSK allowlist automatically — it is NOT
-- recreated.
--
-- KNOWN LIMITATION (recorded, deliberately NOT changed here — the approved
-- delta for this phase is the device-type line only): this gate mirrors the
-- PRE-RF-118 restore liveness chain. RF-118 later added
-- `device_sessions.expires_at` to the authoritative session contract, but
-- this helper (like the receipt-logo gate) does not check it — an EXPIRED
-- but unrevoked session whose principal binding is still current could sign
-- menu-image URLs until revocation/rebind. Pre-existing POS behavior,
-- unchanged; flagged for an explicit owner decision as its own follow-up.
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
  'DEVICE read gate for the private RF-110 menu-images bucket. Path-derived via app.menu_image_scope (malformed => no row => deny); allows ONLY an ACTIVE unrevoked device_sessions row bound to auth.uid() (recorded at redeem, re-bound on every successful restore) on an ACTIVE pairing, device is_active AND device_type IN (pos, kiosk) — KIOSK-001-PREREQ-083 widened the POS-only gate; KDS stays EXCLUDED (T-014) — org+restaurant equal to the path scope, branch: path global/null OR equal to the session branch. Read-only; never referenced by a write policy; authenticated-only. KNOWN LIMITATION: no expires_at check (pre-RF-118 mirror; see the 20260823090000 header) — flagged for its own follow-up.';

-- Re-issue the exact intended ACL posture (CREATE OR REPLACE preserves it,
-- but the gate is SECURITY DEFINER — be explicit, never implicit).
revoke all on function app.device_can_read_menu_image(text)    from public;
grant execute on function app.device_can_read_menu_image(text) to authenticated;
