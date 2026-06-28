-- ============================================================================
-- RF-126 — public.sync_push: the NARROW, authenticated-only POS WRITE contract
-- (a faithful wrapper over app.sync_push — API_CONTRACT §4.14, PROPOSED DECISION
-- D-036, OFFLINE_SYNC_SPEC, RISK R-002/R-007/R-003).
-- ============================================================================
-- RF-056 implemented the server-side PUSH half of offline sync (DECISION D-010) as
-- a single SECURITY DEFINER RPC in the `app` schema:
--   app.sync_push(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb)
-- It validates the PIN session + active device/pairing (A8; a revoked device fails
-- the whole batch, R-007), derives org/restaurant/branch SERVER-SIDE (never from the
-- payload), and per ordered operation: dedups/replays via the sync_operations ledger
-- (transport identity = organization_id + device_id + local_operation_id, D-022),
-- checks dependency edges, and DISPATCHES to the matching business RPC
-- (shift.open->open_shift, order.submit->submit_order, order.discount->apply_discount,
-- payment.create->record_payment, shift.close->close_shift) inside a per-operation
-- EXCEPTION subtransaction. Money/sequences/receipt numbers stay server-authoritative
-- inside the dispatched RPCs (D-007/D-021); the sync_operations table is RLS
-- enabled+forced and written ONLY by app.sync_push (D-011/D-012).
--
-- BUT the `app` schema is deliberately NOT exposed to the Data API
-- (supabase/config.toml [api].schemas = ["public","graphql_public"] only), so a
-- Flutter client (anon key + authenticated JWT, PostgREST) has NO entry point to
-- call app.sync_push today. The grant to `authenticated` (RF-056) is necessary but
-- not sufficient: with no exposed schema route, PostgREST never builds an RPC
-- endpoint for app.sync_push. The POS real submit/order/payment/outbox path is
-- therefore CLOSED to clients — the gap surfaced (no silent scope expansion) in
-- M7_BACKEND_CONTRACT_NOTES §2.2/§5 and drift register D1. This is the same
-- situation app.sync_pull was in before RF-064, app.start_pin_session before
-- RF-123, app.get_my_context before RF-124, app.menu_* before RF-109 (D-031), and
-- app.platform_admin_* before RF-125 (D-035).
--
-- RF-126 adds ONE thin public.sync_push SECURITY INVOKER pass-through — exactly the
-- proven RF-064 / RF-123 / RF-124 / RF-109 / RF-125 wrapper pattern. Because the
-- wrapper is SECURITY INVOKER, it runs as the authenticated caller, who already
-- holds EXECUTE on app.sync_push (RF-056 grant reused) — so it needs NO new grant on
-- app.* and adds NO privilege. It adds NO authorization logic and NO transformation:
-- the ENTIRE batch gate (PIN-session validity + active device/pairing + device match
-- + server-side org/branch derivation), the idempotency ledger, the per-operation
-- dispatch + EXCEPTION isolation, the money authority (D-007/D-021), the sync /
-- business audit writes, and the sync_operations RLS all remain inside the UNCHANGED
-- app.sync_push body. Only this one wrapper is added to the already-exposed `public`
-- schema; the `app` schema is NOT added to [api].schemas, so NO other app RPC (and in
-- particular none of the dispatched mutators submit_order / record_payment /
-- apply_discount / open_shift / close_shift) becomes directly reachable — they remain
-- reachable ONLY through the dispatcher, behind its full validation.
--
-- WRITE/DISPATCH SURFACE (the one difference from the read wrappers): app.sync_push
-- MUTATES (it writes the ledger + audit and dispatches to mutating RPCs). The wrapper
-- is therefore left VOLATILE (no STABLE/IMMUTABLE marker — the `language sql` default)
-- so PostgREST routes it as POST and the delegate's INSERT/dispatch runs in a writable
-- context (the same reasoning RF-125 used for the audited-read wrappers). RF-126
-- introduces NO new SECURITY DEFINER: app.sync_push's SECURITY DEFINER posture is
-- existing, justified architecture (D-011 sensitive mutations via SECURITY DEFINER
-- RPC); the wrapper itself is INVOKER and grants no new authority.
--
-- Additive and FORWARD-ONLY: adds one function in `public`; ALTERs nothing, creates
-- no table, changes no grant on any app.* function, reimplements no business logic.
-- The `supabase db reset` replay of the prior migrations is the no-regression gate.
-- Manual teardown at the foot.
--
-- GOVERNANCE: new client-facing public WRITE surface over the frozen API contract —
-- change-controlled per the architecture-change procedure (AGENT_WORKFLOW §9): own
-- ticket (PROPOSED RF-126), PROPOSED DECISION D-036 recorded before code, pgTAP
-- coverage (rf126_public_sync_push_wrapper_test), independent Codex review, human
-- approval by Saleh, and the RF-060 isolation suite green before merge (RISK R-003).
-- NOT yet ratified/merged.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.sync_push — thin pass-through to app.sync_push (API_CONTRACT §4.14).
--   SECURITY INVOKER + search_path='' + fully-qualified delegate => no privilege
--   change, no search_path hijack, no logic of its own. Left VOLATILE (default) so
--   PostgREST POST-routes it and the delegate's ledger/audit/business writes run in
--   a writable context.
-- ----------------------------------------------------------------------------
create or replace function public.sync_push(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_operations     jsonb
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.sync_push(
    p_pin_session_id,
    p_device_id,
    p_operations
  );
$$;

comment on function public.sync_push(uuid, uuid, jsonb) is
  'RF-126 (API_CONTRACT §4.14, PROPOSED DECISION D-036): NARROW Data-API-reachable POS write contract that delegates verbatim to app.sync_push (the source of truth, RF-056). SECURITY INVOKER — runs as the authenticated caller (who already holds EXECUTE on app.sync_push per RF-056); adds NO authorization logic, NO transformation, NO richer return. The entire batch gate (valid PIN session + active device/pairing + device match + server-side org/branch derivation), the sync_operations idempotency ledger (transport identity device_id+local_operation_id, D-022), the per-operation dispatch to the business RPCs inside per-op EXCEPTION subtransactions, the money authority (D-007/D-021), and the sync/business audit writes all stay inside the unchanged app.sync_push body. Left VOLATILE so PostgREST POST-routes it and the delegate writes execute in a writable context. RF-126 exposes ONLY this one wrapper: the `app` schema stays UNEXPOSED (not added to [api].schemas) and NO other app RPC is wrapped — the dispatched mutators (submit_order/record_payment/apply_discount/open_shift/close_shift) remain reachable ONLY through the dispatcher, behind its full validation.';

-- PostgREST exposes `public` functions granted to a request role. Mirror
-- app.sync_push's posture exactly: deny PUBLIC (so anon cannot call), allow
-- authenticated. app.sync_push's own grants are NOT touched.
revoke all on function public.sync_push(uuid, uuid, jsonb) from public;
grant execute on function public.sync_push(uuid, uuid, jsonb) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse:
-- ----------------------------------------------------------------------------
-- drop function if exists public.sync_push(uuid, uuid, jsonb);
-- ============================================================================
