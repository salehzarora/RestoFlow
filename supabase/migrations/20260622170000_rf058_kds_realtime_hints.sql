-- ============================================================================
-- RF-058 — KDS realtime invalidation hints (enhancement-only, money-free)
-- ============================================================================
-- Realtime is an ENHANCEMENT ONLY over the RF-063 polling-first pull (DECISION
-- D-010): it carries NO row data and NO money — only a minimal invalidation HINT
-- that nudges the KDS client to call sync_pull (RF-064 public.sync_pull →
-- app.sync_pull), which stays the authoritative, redacted, revocation-aware
-- source of truth. This migration adds, with the SMALLEST possible surface:
--
--   1. A money-free hint EMISSION trigger on `orders` and `order_items` that
--      sends a private Supabase broadcast to topic `kds:branch:{branch_id}` via
--      realtime.send (NOT postgres_changes; tables are NOT added to any
--      publication; no raw rows are published). Financial tables
--      (payments / shifts / cash_drawer_sessions / branch_receipt_counters /
--      sync_operations) NEVER emit.
--   2. A NARROW Realtime Authorization policy on `realtime.messages` so an
--      authenticated principal may RECEIVE on `kds:branch:{id}` ONLY when they
--      hold an ACTIVE membership for that exact branch (R-003 channel isolation).
--      Auth is derived from auth.uid() → app_users.auth_user_id → memberships
--      (no new JWT claim; the same auth model as RF-050/RF-059 RLS).
--
-- Even if a hint leaked or were forged, it grants NO data: the client must call
-- sync_pull, which derives scope from the caller's PIN session and still raises
-- 42501 for a revoked device / expired PIN (RF-059/RF-061 unchanged). Emission
-- is best-effort (realtime.send is internally exception-safe AND the trigger
-- wraps it) so a failed hint can NEVER block an order/item write.
--
-- Additive and FORWARD-ONLY: one trigger function + two triggers in `app`/public
-- and one SELECT policy on realtime.messages. ALTERs no business table, changes
-- no grant, touches neither app.sync_pull nor public.sync_pull, and enrolls
-- nothing in postgres_changes / the supabase_realtime publication. Manual
-- teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.emit_kds_invalidation_hint — AFTER INSERT/UPDATE trigger on the two
--    KDS-relevant tables. Builds a MINIMAL, money-free hint and broadcasts it to
--    the per-branch private topic. SECURITY DEFINER + search_path='' so it runs
--    as the owner regardless of the writer; the whole body is exception-guarded
--    so emission can never fail the underlying write (polling is the fallback).
-- ----------------------------------------------------------------------------
create or replace function app.emit_kds_invalidation_hint()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_revision integer;
begin
  begin
    -- `orders` carries a revision column; `order_items` does not (revision -> null).
    if tg_table_name = 'orders' then
      v_revision := new.revision;
    else
      v_revision := null;
    end if;

    -- Minimal hint ONLY — no money, no raw row, no customer/private fields.
    perform realtime.send(
      jsonb_build_object(
        'organization_id', new.organization_id,
        'branch_id',       new.branch_id,
        'entity',          tg_table_name,
        'entity_id',       new.id,
        'revision',        v_revision,
        'updated_at',      new.updated_at,
        'server_ts',       now()
      ),
      'kds.invalidate',                              -- broadcast event name
      'kds:branch:' || new.branch_id::text,          -- private per-branch topic
      true                                           -- private channel
    );
  exception when others then
    -- Enhancement only: a failed hint must NEVER break the order/item write.
    null;
  end;
  return null;  -- AFTER trigger: return value ignored
end;
$$;

comment on function app.emit_kds_invalidation_hint() is
  'RF-058: AFTER INSERT/UPDATE trigger on orders/order_items. Broadcasts a MINIMAL money-free invalidation hint {organization_id, branch_id, entity, entity_id, revision, updated_at, server_ts} to the private topic kds:branch:{branch_id} via realtime.send (NOT postgres_changes; no raw rows). Best-effort (exception-guarded) so it never blocks the write. The KDS reacts by calling sync_pull (the source of truth); the hint grants no data and bypasses no auth.';

create trigger orders_emit_kds_hint
  after insert or update on orders
  for each row execute function app.emit_kds_invalidation_hint();

create trigger order_items_emit_kds_hint
  after insert or update on order_items
  for each row execute function app.emit_kds_invalidation_hint();

-- ----------------------------------------------------------------------------
-- 2. Realtime Authorization (private channel RECEIVE) on realtime.messages.
--    realtime.messages has RLS enabled with NO policies (default deny). This
--    adds ONE narrow SELECT policy: an authenticated principal may receive on a
--    `kds:branch:{id}` broadcast topic ONLY when an ACTIVE membership ties their
--    auth.uid() (-> app_users.auth_user_id) to that exact branch. Other topics
--    stay denied (this policy's USING is false for them; no other policy grants).
--    No new JWT claim; cross-org / cross-branch / revoked => denied (R-003).
-- ----------------------------------------------------------------------------
create policy rf058_kds_branch_hint_receive
  on realtime.messages
  for select
  to authenticated
  using (
    extension = 'broadcast'
    and realtime.topic() like 'kds:branch:%'
    and exists (
      select 1
      from public.memberships m
      join public.app_users au on au.id = m.app_user_id
      where au.auth_user_id = (select auth.uid())
        and m.status = 'active'
        and m.deleted_at is null
        and realtime.topic() = 'kds:branch:' || m.branch_id::text
    )
  );

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop policy if exists rf058_kds_branch_hint_receive on realtime.messages;
-- drop trigger if exists order_items_emit_kds_hint on order_items;
-- drop trigger if exists orders_emit_kds_hint on orders;
-- drop function if exists app.emit_kds_invalidation_hint();
-- ============================================================================
