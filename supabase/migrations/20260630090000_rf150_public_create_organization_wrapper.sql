-- ============================================================================
-- RF-150 — public.create_organization: the Data-API-reachable self-serve
-- ONBOARDING contract (a faithful wrapper over app.create_organization, RF-090;
-- API_CONTRACT §4; DECISIONS D-003/D-004/D-026).
-- ============================================================================
-- RF-090 implemented self-serve organization onboarding as a SECURITY DEFINER RPC
-- in the `app` schema:
--   app.create_organization(client_request_id, organization_name, organization_slug,
--     restaurant_name, branch_name, currency_code, timezone, default_station_name)
-- It derives the caller from auth.uid() ONLY (never input), bootstraps the app_user,
-- and atomically creates organization + first restaurant + branch (+ optional default
-- station) + the first org_owner MEMBERSHIP + an organization.created audit event,
-- idempotent per (caller, client_request_id). No shared accounts (D-004); never grants
-- platform_admin (D-026); membership role, never a global role.
--
-- BUT the `app` schema is deliberately NOT exposed to the Data API
-- (supabase/config.toml [api].schemas = ["public","graphql_public"] only), so a Flutter
-- client (anon key + authenticated JWT, PostgREST) has NO entry point to call
-- app.create_organization today — the self-serve signup path is CLOSED to clients. This
-- is the same situation app.sync_pull was in before RF-064, app.sync_push before RF-126,
-- app.start_pin_session before RF-123, app.get_my_context before RF-124, app.menu_*
-- before RF-109, and app.platform_admin_* before RF-125.
--
-- RF-150 adds ONE thin public.create_organization SECURITY INVOKER pass-through —
-- exactly the proven RF-064/123/124/109/125/126 wrapper pattern. Because the wrapper is
-- SECURITY INVOKER it runs as the authenticated caller, who already holds EXECUTE on
-- app.create_organization (RF-090 grant reused) — so it needs NO new grant on app.* and
-- adds NO privilege. It adds NO authorization logic and NO transformation: the ENTIRE
-- gate (auth.uid() identity derivation, app_user bootstrap, idempotency, org_owner
-- membership, audit, the structural impossibility of granting platform_admin) stays
-- inside the UNCHANGED app.create_organization body. The `app` schema is NOT added to
-- [api].schemas, so no other app RPC (and not the internal app.create_organization_replay
-- helper) becomes Data-API-reachable.
--
-- WRITE SURFACE: app.create_organization MUTATES, so the wrapper is left VOLATILE (the
-- `language sql` default — no STABLE/IMMUTABLE marker) so PostgREST routes it as POST and
-- the delegate's INSERTs run in a writable context (the RF-125/126 reasoning). RF-150
-- introduces NO new SECURITY DEFINER: app.create_organization's DEFINER posture is
-- existing, justified architecture (onboarding must write where the RLS deny-policies
-- forbid direct client INSERT, RF-059); the wrapper itself is INVOKER and grants no new
-- authority.
--
-- Additive and FORWARD-ONLY: adds one function in `public`; ALTERs nothing, creates no
-- table, changes no grant on app.create_organization, reimplements no logic. The
-- `supabase db reset` replay of the prior migrations is the no-regression gate. Manual
-- teardown at the foot.
--
-- GOVERNANCE (PROPOSED): a new client-facing public WRITE surface over the frozen API
-- contract — change-controlled per AGENT_WORKFLOW §9 (own ticket RF-150, pgTAP coverage
-- rf150_public_create_organization_wrapper_test, independent review, human approval by
-- Saleh, RF-019 isolation green before merge, RISK R-003). The self-serve signup
-- BEHAVIOUR itself is RF-090 / API_CONTRACT §4 (already ratified); this wrapper only makes
-- that ratified RPC Data-API-reachable. The onboarding SCREEN remains a deferred frontend
-- ticket.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- public.create_organization — thin pass-through to app.create_organization.
--   SECURITY INVOKER + search_path='' + fully-qualified delegate => no privilege
--   change, no search_path hijack, no logic of its own. Left VOLATILE (default) so
--   PostgREST POST-routes it and the delegate's atomic creation runs in a writable
--   context.
-- ----------------------------------------------------------------------------
create or replace function public.create_organization(
  p_client_request_id    uuid,
  p_organization_name    text,
  p_organization_slug    text,
  p_restaurant_name      text,
  p_branch_name          text,
  p_currency_code        text,
  p_timezone             text,
  p_default_station_name text default null
)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.create_organization(
    p_client_request_id,
    p_organization_name,
    p_organization_slug,
    p_restaurant_name,
    p_branch_name,
    p_currency_code,
    p_timezone,
    p_default_station_name
  );
$$;

comment on function public.create_organization(uuid, text, text, text, text, text, text, text) is
  'RF-150 (API_CONTRACT §4, RF-090): NARROW Data-API-reachable self-serve onboarding contract that delegates verbatim to app.create_organization (the source of truth, RF-090). SECURITY INVOKER — runs as the authenticated caller (who already holds EXECUTE on app.create_organization per RF-090); adds NO authorization logic, NO transformation. The caller derivation from auth.uid() ONLY, app_user bootstrap, atomic organization + first restaurant + branch (+ optional default station) + first org_owner MEMBERSHIP + organization.created audit creation, and idempotency per (caller, client_request_id) all stay inside the unchanged app.create_organization body. Left VOLATILE so PostgREST POST-routes it and the delegate writes execute in a writable context. No shared accounts (D-004); never grants platform_admin (D-026).';

-- PostgREST exposes `public` functions granted to a request role. Mirror
-- app.create_organization's posture exactly: deny PUBLIC (so anon cannot call),
-- allow authenticated. app.create_organization's own grants are NOT touched.
revoke all on function public.create_organization(uuid, text, text, text, text, text, text, text) from public;
grant execute on function public.create_organization(uuid, text, text, text, text, text, text, text) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse:
-- ----------------------------------------------------------------------------
-- drop function if exists public.create_organization(uuid, text, text, text, text, text, text, text);
-- ============================================================================
