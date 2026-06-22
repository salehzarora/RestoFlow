-- ============================================================================
-- RF-064 — public.sync_pull: a NARROW, safe PostgREST-reachable wrapper
-- ============================================================================
-- RF-063 wired a client that calls `app.sync_pull` over PostgREST, but the `app`
-- schema is deliberately NOT exposed to PostgREST (ARCHITECTURE §3: helpers and
-- sensitive RPCs live in `app` so they are never HTTP-reachable). Exposing the
-- whole `app` schema would make ALL ~20 authenticated-granted app RPCs callable
-- over HTTP — every mutating RPC (submit_order / record_payment / void_order /
-- apply_discount / open|close|reconcile_shift / revoke_device|employee /
-- start_pin_session / sync_push) AND app.platform_admin_list_organizations —
-- which is far too broad and premature (RISK R-003).
--
-- Instead, RF-064 adds ONE narrow wrapper in the already-exposed `public` schema:
--   * public.sync_pull delegates verbatim to app.sync_pull — the SOURCE OF TRUTH.
--   * It is SECURITY INVOKER (approved decision A1): it runs as the authenticated
--     caller, who already holds EXECUTE on app.sync_pull (RF-057 grant, unchanged),
--     so the delegate call needs NO privilege change and NO new grant on app.*.
--   * It adds NO authorization logic and NO data transformation — all auth,
--     the 42501 on revoked-device / expired-PIN, and the kitchen money redaction
--     stay inside the UNCHANGED app.sync_pull (RF-057 / RF-059 / RF-061).
--   * `app` is NOT added to [api].schemas — only public.sync_pull is exposed.
--   * NO other app RPC is wrapped or exposed.
--
-- Additive and FORWARD-ONLY: adds one function in `public`; ALTERs nothing,
-- creates no table, changes no grant on any app.* function. The `supabase db reset`
-- replay of the prior migrations is the no-regression gate. Manual teardown at foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.sync_pull — thin pass-through to app.sync_pull (API_CONTRACT §4.15).
--   SECURITY INVOKER + search_path='' + fully-qualified delegate => no privilege
--   change, no search_path hijack, no logic of its own.
-- ----------------------------------------------------------------------------
create or replace function public.sync_pull(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_entities       text[]  default null,
  p_cursors        jsonb   default '{}'::jsonb,
  p_limit          integer default 500
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.sync_pull(
    p_pin_session_id,
    p_device_id,
    p_entities,
    p_cursors,
    p_limit
  );
$$;

comment on function public.sync_pull(uuid, uuid, text[], jsonb, integer) is
  'RF-064: a NARROW PostgREST-reachable wrapper that delegates verbatim to app.sync_pull (the source of truth). SECURITY INVOKER — runs as the authenticated caller (who already has EXECUTE on app.sync_pull per RF-057); adds NO authorization logic and NO transformation. RF-064 exposes ONLY sync_pull: the `app` schema stays UNEXPOSED (not added to [api].schemas) and NO other app RPC is wrapped. All auth, the 42501 on revoked-device/expired-PIN, and kitchen money redaction remain inside app.sync_pull (RF-057/RF-059/RF-061), unchanged.';

-- PostgREST exposes `public` functions that are granted to a request role. Mirror
-- app.sync_pull''s posture exactly: deny PUBLIC (so anon cannot call), allow
-- authenticated. app.sync_pull''s own grants are NOT touched (approved decision A1).
revoke all on function public.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function public.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse:
-- ----------------------------------------------------------------------------
-- drop function if exists public.sync_pull(uuid, uuid, text[], jsonb, integer);
-- ============================================================================
