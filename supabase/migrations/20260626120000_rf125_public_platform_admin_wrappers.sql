-- ============================================================================
-- RF-125 — public.platform_admin_*: NARROW, authenticated-only public wrappers
-- over the RF-091 platform-admin read-only panel RPCs
-- (API_CONTRACT §4.16/§4.18, PROPOSED DECISION D-035, T-007/T-008, RISK R-003).
-- ============================================================================
-- RF-091 implemented three READ-ONLY platform-admin RPCs in the `app` schema:
--   app.platform_admin_organization_overview(p_reason text)
--   app.platform_admin_get_organization(p_organization_id uuid, p_reason text)
--   app.platform_admin_recent_audit(p_reason text, p_limit integer default 50)
-- Each is SECURITY DEFINER, granted to `authenticated`, and self-gated by
-- app.platform_admin_guard (authenticated principal + ACTIVE platform_admin_grant
-- [D-026, NOT a tenant membership] + MFA aal2 [RF-050] + non-empty reason), and
-- each writes a reason-tagged platform_admin_audit_events row (the read is itself
-- audited). BUT the `app` schema is deliberately NOT exposed to the Data API —
-- supabase/config.toml [api].schemas = ["public","graphql_public"] only — so a
-- Flutter client (anon key + authenticated JWT, PostgREST) has NO entry point to
-- call them today. The grant is necessary but not sufficient: with no exposed
-- schema route, PostgREST never builds an RPC endpoint for app.platform_admin_*.
--
-- RF-125 adds THREE thin public.* SECURITY INVOKER pass-throughs — exactly the
-- pattern already shipped for RF-064 (public.sync_pull), RF-123
-- (public.start_pin_session), RF-124 (public.get_my_context), and RF-109
-- (public.menu_*). Because each wrapper is SECURITY INVOKER, it runs as the
-- authenticated caller, who already holds EXECUTE on the app.* function (RF-091
-- grant reused) — so it needs NO new grant on app.* and adds NO privilege. It
-- adds NO authorization logic and NO transformation: the ENTIRE guard (active
-- grant + aal2 + non-empty reason), the audited reads, the cross-tenant scoping,
-- and the read-only / no-impersonation posture all remain inside the UNCHANGED
-- app.* bodies. Only these three wrappers are added to the already-exposed
-- `public` schema (revoke all from public; grant execute to authenticated —
-- mirroring the app.* posture exactly); the `app` schema is NOT added to
-- [api].schemas, so NO other app RPC becomes reachable.
--
-- READ-ONLY (DECISION D-026): platform admin remains read-only — none of the
-- three mutate tenant data, impersonate, run a generic cross-tenant `select *`,
-- or grant/revoke; each only inserts its own row into the separate
-- platform_admin_audit_events plane, which is unreadable/unwritable by the tenant
-- `authenticated` path (RF-059 RLS forced, no policy, no grant). The wrappers are
-- left VOLATILE (no STABLE/IMMUTABLE marker) so PostgREST routes them as POST and
-- the audit INSERT inside the delegate executes in a writable context.
--
-- Additive and FORWARD-ONLY: adds three functions in `public`; ALTERs nothing,
-- creates no table, changes no grant on any app.* function. The `supabase db
-- reset` replay of the prior migrations is the no-regression gate. Manual
-- teardown at foot.
--
-- GOVERNANCE: new client-facing public surface over the frozen API contract —
-- change-controlled per the architecture-change procedure (AGENT_WORKFLOW §9):
-- own ticket (PROPOSED RF-125), PROPOSED DECISION D-035 recorded before code,
-- pgTAP coverage (rf125_public_platform_admin_wrapper_test), independent Codex
-- review, human approval by Saleh, and the RF-060 isolation suite green before
-- merge (RISK R-003). NOT yet ratified/merged.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. public.platform_admin_organization_overview(p_reason text)
--    Thin pass-through to app.platform_admin_organization_overview (§4.18).
-- ----------------------------------------------------------------------------
create or replace function public.platform_admin_organization_overview(p_reason text)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.platform_admin_organization_overview(p_reason);
$$;

comment on function public.platform_admin_organization_overview(text) is
  'RF-125 (API_CONTRACT §4.18, PROPOSED DECISION D-035): NARROW Data-API-reachable wrapper that delegates verbatim to app.platform_admin_organization_overview (the source of truth, RF-091). SECURITY INVOKER — runs as the authenticated caller (who already holds EXECUTE on the app function per RF-091); adds NO authorization logic, NO transformation, NO richer return. The entire gate (active platform_admin_grant + aal2 MFA + non-empty reason — D-026/T-008) and the reason-tagged platform_admin_audit_events write stay inside the unchanged app.* body. Read-only (D-026). RF-125 exposes ONLY these three platform_admin_* wrappers: the `app` schema stays UNEXPOSED (not added to [api].schemas) and NO other app RPC is wrapped.';

revoke all on function public.platform_admin_organization_overview(text) from public;
grant execute on function public.platform_admin_organization_overview(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. public.platform_admin_get_organization(p_organization_id uuid, p_reason text)
--    Thin pass-through to app.platform_admin_get_organization (§4.18).
-- ----------------------------------------------------------------------------
create or replace function public.platform_admin_get_organization(p_organization_id uuid, p_reason text)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.platform_admin_get_organization(p_organization_id, p_reason);
$$;

comment on function public.platform_admin_get_organization(uuid, text) is
  'RF-125 (API_CONTRACT §4.18, PROPOSED DECISION D-035): NARROW Data-API-reachable wrapper that delegates verbatim to app.platform_admin_get_organization (RF-091). SECURITY INVOKER — runs as the authenticated caller (already holds EXECUTE on the app function); adds NO authorization logic and NO transformation. The active-grant + aal2 + non-empty-reason gate, the audited read (platform.organization.read with target_organization_id), the not-found 42501, and the read-only posture all stay inside the unchanged app.* body. Read-only (D-026). The `app` schema stays UNEXPOSED; no other app RPC is wrapped.';

revoke all on function public.platform_admin_get_organization(uuid, text) from public;
grant execute on function public.platform_admin_get_organization(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. public.platform_admin_recent_audit(p_reason text, p_limit integer default 50)
--    Thin pass-through to app.platform_admin_recent_audit (§4.18). The default 50
--    mirrors the app RPC; the [1,200] clamp stays server-side in the app body.
-- ----------------------------------------------------------------------------
create or replace function public.platform_admin_recent_audit(p_reason text, p_limit integer default 50)
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.platform_admin_recent_audit(p_reason, p_limit);
$$;

comment on function public.platform_admin_recent_audit(text, integer) is
  'RF-125 (API_CONTRACT §4.18, PROPOSED DECISION D-035): NARROW Data-API-reachable wrapper that delegates verbatim to app.platform_admin_recent_audit (RF-091). SECURITY INVOKER — runs as the authenticated caller (already holds EXECUTE on the app function); adds NO authorization logic and NO transformation. Same params/types/order including p_limit integer default 50; the [1,200] clamp and the audited read (platform.audit.read) stay inside the unchanged app.* body. Read-only (D-026). The `app` schema stays UNEXPOSED; no other app RPC is wrapped.';

revoke all on function public.platform_admin_recent_audit(text, integer) from public;
grant execute on function public.platform_admin_recent_audit(text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse:
-- ----------------------------------------------------------------------------
-- drop function if exists public.platform_admin_recent_audit(text, integer);
-- drop function if exists public.platform_admin_get_organization(uuid, text);
-- drop function if exists public.platform_admin_organization_overview(text);
-- ============================================================================
