-- ============================================================================
-- RF-123 — public.start_pin_session: a NARROW, authenticated-only public
-- wrapper over app.start_pin_session (API_CONTRACT §4.21, DECISION D-029).
-- ============================================================================
-- RF-051 implemented app.start_pin_session as a SECURITY DEFINER RPC in the
-- `app` schema, which is deliberately NOT exposed to the Data API (only
-- public/graphql_public are — supabase/config.toml). The RF-064 header lists
-- start_pin_session among the ~20 mutating app RPCs deliberately left unexposed.
-- RF-122/D-029 authorized a SINGLE narrow wrapper in the already-exposed
-- `public` schema so clients can reach the PIN-session establish call WITHOUT
-- exposing the whole `app` schema (which would make every mutating app RPC
-- HTTP-reachable — RISK R-003).
--
-- This migration adds ONE function: public.start_pin_session, a faithful
-- pass-through (same four args, same types and order) that delegates verbatim
-- to app.start_pin_session — the SOURCE OF TRUTH. It is SECURITY INVOKER: it
-- runs as the authenticated caller, who already holds EXECUTE on
-- app.start_pin_session (RF-051 grant, unchanged), so the delegate call needs
-- NO privilege change and NO new grant on app.*. It adds NO authorization
-- logic, NO transformation, and NO richer return (D-029): wrong PIN -> NULL;
-- structural / precondition / lockout failures -> SQLSTATE 42501; keyed
-- idempotent replay unchanged. The `app` schema is NOT added to [api].schemas;
-- only public.start_pin_session is exposed. NO other app RPC is wrapped.
--
-- Additive and FORWARD-ONLY: adds one function in `public`; ALTERs nothing,
-- creates no table, changes no grant on any app.* function. The `supabase db
-- reset` replay of the prior migrations is the no-regression gate. Manual
-- teardown at foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.start_pin_session — thin pass-through to app.start_pin_session
--   (API_CONTRACT §4.21 / §4.13). SECURITY INVOKER + search_path='' +
--   fully-qualified delegate => no privilege change, no search_path hijack,
--   no logic of its own.
-- ----------------------------------------------------------------------------
create or replace function public.start_pin_session(
  p_device_session_id   uuid,
  p_employee_profile_id uuid,
  p_pin_verifier        text,
  p_local_operation_id  text default null
)
  returns uuid
  language sql
  security invoker
  set search_path = ''
as $$
  select app.start_pin_session(
    p_device_session_id,
    p_employee_profile_id,
    p_pin_verifier,
    p_local_operation_id
  );
$$;

comment on function public.start_pin_session(uuid, uuid, text, text) is
  'RF-123 (API_CONTRACT §4.21, DECISION D-029): a NARROW Data-API-reachable wrapper that delegates verbatim to app.start_pin_session (the source of truth, RF-051 §4.13). SECURITY INVOKER — runs as the authenticated caller (who already has EXECUTE on app.start_pin_session per RF-051); adds NO authorization logic, NO transformation, and NO richer return. Same four params/types/order; returns a bare uuid. Wrong PIN => NULL (no row, no error); structural/precondition/lockout => 42501; keyed idempotent replay unchanged. RF-123 exposes ONLY start_pin_session: the `app` schema stays UNEXPOSED (not added to [api].schemas) and NO other app RPC is wrapped. All inner authorization (device session + pairing, membership resolution, lockout, verifier, revocation/offline-window) remains inside app.start_pin_session, unchanged.';

-- The Data API exposes `public` functions granted to a request role. Mirror
-- app.start_pin_session''s posture exactly: deny PUBLIC (so anon cannot call),
-- allow authenticated only — never anon/public/service_role (D-011/D-029).
-- app.start_pin_session''s own grants are NOT touched.
revoke all on function public.start_pin_session(uuid, uuid, text, text) from public;
grant execute on function public.start_pin_session(uuid, uuid, text, text) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse:
-- ----------------------------------------------------------------------------
-- drop function if exists public.start_pin_session(uuid, uuid, text, text);
-- ============================================================================
