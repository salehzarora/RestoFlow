-- ============================================================================
-- POS-OPEN-ORDERS-REALTIME-GATE-013 — POS device RECEIVE authorization for the
-- RF-058 branch invalidation hints (additive; owner-gated hosted apply).
-- ============================================================================
-- RF-058 (20260622170000) already emits a MINIMAL money-free invalidation hint
-- {organization_id, branch_id, entity, entity_id, revision, updated_at,
-- server_ts} to the private broadcast topic `kds:branch:{branch_id}` on every
-- orders/order_items INSERT/UPDATE, and authorizes RECEIVE for ACTIVE-MEMBER
-- principals only. The POS device is an ANONYMOUS, membership-less principal
-- (DECISION D-011), so it fails that policy closed and the open-orders strip
-- cannot hear "something changed" events (POS-OPEN-ORDERS-REALTIME-GATE-012
-- audit).
--
-- This migration adds, with the SMALLEST possible surface, ONE additional
-- narrow RECEIVE path: a currently-VALID POS device session — the SAME
-- anonymous-principal binding the device storage policies use
-- (device_sessions.auth_user_id, re-bound on every launch by
-- app.restore_device_session) — may receive hints for ITS OWN branch topic
-- only. The validity chain is the FULL app.restore_device_session predicate
-- (RF-118), deliberately INCLUDING the expires_at check the older storage
-- helpers omit: session active + unrevoked + unexpired, pairing active +
-- unrevoked + undeleted, device active + undeleted + type 'pos' (KDS
-- enablement is a separate ticket), live branch + restaurant, and an EXACT
-- topic ⇄ session-branch equality.
--
-- THREAT MODEL (T-014/R-003): the topic is reused (`kds:branch:%` — the
-- emitter is untouched; authorization is per-principal, so this policy widens
-- nothing for anyone else); a hint grants NO data — the client must still
-- call the fully-gated snapshot/sync RPCs, which refuse a revoked device with
-- 42501 regardless; clients hold NO SEND/INSERT right on realtime.messages
-- (no such policy exists); every other topic remains default-deny.
--
-- Additive and FORWARD-ONLY: one SECURITY DEFINER STABLE helper + one SELECT
-- policy. ALTERs no table, adds no index (device_sessions_auth_user_id_idx
-- already covers the probe), changes no trigger/payload/publication, touches
-- no existing policy, and enrolls nothing in postgres_changes. Manual
-- teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.device_can_receive_branch_hints — TRUE iff the calling principal is
--    bound to a currently-valid POS device session whose branch matches the
--    topic EXACTLY. SECURITY DEFINER (device_sessions is RLS-forced and
--    membership-scoped; the anonymous principal reads zero rows directly),
--    STABLE, empty search_path, no dynamic SQL.
-- ----------------------------------------------------------------------------
create or replace function app.device_can_receive_branch_hints(p_topic text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    join public.devices d on d.id = ds.device_id
    join public.branches b
      on b.organization_id = ds.organization_id
     and b.restaurant_id   = ds.restaurant_id
     and b.id              = ds.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = ds.organization_id
     and r.id              = ds.restaurant_id
     and r.deleted_at is null
    where ds.auth_user_id = (select auth.uid())
      and ds.is_active
      and ds.revoked_at is null
      -- RF-118: an expired session loses hints at the same moment restore
      -- would refuse it (stricter than the storage gates — deliberate).
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active'
      and dp.revoked_at is null
      and dp.deleted_at is null
      and d.is_active
      and d.deleted_at is null
      and d.device_type = 'pos'   -- THIS gate is POS-only (KDS = own ticket)
      and p_topic = 'kds:branch:' || ds.branch_id::text
  );
$$;

comment on function app.device_can_receive_branch_hints(text) is
  'POS-OPEN-ORDERS-REALTIME-GATE-013: TRUE iff auth.uid() is bound (device_sessions.auth_user_id — re-bound each launch by app.restore_device_session) to a currently-VALID POS device session (active + unrevoked + unexpired session, active pairing, active device, live branch/restaurant) whose branch matches the given kds:branch:{branch_id} topic EXACTLY. Consumed by the rf058_pos_device_branch_hint_receive RECEIVE policy on realtime.messages. Hints carry no data; the authoritative refresh RPCs stay fully gated.';

revoke all on function app.device_can_receive_branch_hints(text) from public;
grant execute on function app.device_can_receive_branch_hints(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. The ADDITIVE RECEIVE policy. The existing membership policy
--    (rf058_kds_branch_hint_receive) is untouched; policies OR, and each
--    admits only its own legitimate branch-scoped reader.
-- ----------------------------------------------------------------------------
create policy rf058_pos_device_branch_hint_receive
  on realtime.messages
  for select
  to authenticated
  using (
    extension = 'broadcast'
    and realtime.topic() like 'kds:branch:%'
    and app.device_can_receive_branch_hints(realtime.topic())
  );

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop policy if exists rf058_pos_device_branch_hint_receive on realtime.messages;
-- drop function if exists app.device_can_receive_branch_hints(text);
-- ============================================================================
