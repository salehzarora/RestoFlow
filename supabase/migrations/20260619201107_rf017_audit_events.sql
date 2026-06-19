-- ============================================================================
-- RF-017 — Append-only audit_events + enforcement
-- ============================================================================
-- The tamper-evident audit trail (DECISION D-013): an append-only record of who
-- did what, where, when, and why. Built on RF-014/015/016. Carries the D-013
-- INVARIANT (binding) + RISK R-003 (CRITICAL: cross-tenant audit leak). Requires
-- human sign-off before merge (touches RLS).
--
-- ----------------------------------------------------------------------------
-- DESIGN (per DOMAIN_MODEL §10.2 + Codex-approved RF-017 decisions A1-A6):
--   * Tenant-scoped by organization_id (NOT NULL); restaurant/branch optional.
--   * SOFT references (A2): actor/device/hierarchy columns are plain uuids with
--     NO foreign keys, so the audit row "survives deletes" of referenced entities
--     and never blocks or is cascaded by their lifecycle (DOMAIN_MODEL §10.2).
--   * Permanent + immutable: NO updated_at, NO deleted_at — audit rows are never
--     updated and never (soft-)deleted by app roles. Append-only is enforced in
--     depth: SELECT-only grant + SELECT-only RLS policy + a BEFORE UPDATE/DELETE
--     trigger.
--   * Actor is always recorded (A3): an app_user and/or an employee_profile.
--
-- WRITE PATH (deferred, by design): audit rows are written server-side by the
-- per-action SECURITY DEFINER business RPCs (DECISION D-011, API_CONTRACT §1.1
-- step 6), which — as table-owner functions — INSERT directly. RF-017 has no
-- auditable mutations yet, so it grants NO direct INSERT to app roles and ships
-- NO generic writer RPC (A1) and NO audit triggers on other tables.
--
-- OUT OF SCOPE (other tickets): generic write helper (A1); platform-admin
-- audited path + platform-scoped/org-NULL rows + T-007..T-010 (RF-060); role-
-- gating of audit READS / full policy matrix (RF-059); reusable harness/CI
-- (RF-019); JWT/auth.uid (RF-050); retention/purge (Q-005, ops/legal). No new GUCs.
-- FORWARD-ONLY; manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. audit_events — tenant-scoped, append-only, permanent.
-- ----------------------------------------------------------------------------
create table audit_events (
  id                        uuid        primary key default gen_random_uuid(),
  organization_id           uuid        not null,                         -- tenant boundary (D-001); soft ref (no FK)
  restaurant_id             uuid,                                          -- soft ref; null => org-level event
  branch_id                 uuid,                                          -- soft ref; null => org/restaurant-level event
  actor_app_user_id         uuid,                                          -- soft ref to app_users
  actor_employee_profile_id uuid,                                          -- soft ref to employee_profiles (PIN-only staff have no app_user)
  device_id                 uuid,                                          -- soft ref to devices; null for server-side actions
  action                    text        not null check (length(btrim(action)) > 0),
  reason                    text,                                          -- nullable; per-action "reason REQUIRED" is enforced by the writing RPC/state machine
  old_values                jsonb,                                         -- pre-image; null on create events
  new_values                jsonb,                                         -- post-image; null on delete/void events
  occurred_at               timestamptz not null default now(),           -- server-authoritative event time
  created_at                timestamptz not null default now(),           -- row write time
  -- D-013: an actor is always recorded (app_user and/or employee_profile) (A3)
  constraint audit_events_actor_present
    check (actor_app_user_id is not null or actor_employee_profile_id is not null)
  -- DELIBERATELY no updated_at (never updated) and no deleted_at (never deleted) — append-only & permanent.
  -- DELIBERATELY no foreign keys (A2): soft uuid references keep audit resilient across deletes.
);

comment on table audit_events is
  'Append-only, permanent audit trail (DECISION D-013). Tenant-scoped by organization_id. Reference columns are SOFT uuids (no FK) so audit survives entity deletes. No updated_at / no deleted_at: never updated or deleted by app roles (enforced by SELECT-only grant + SELECT-only RLS + the append-only trigger). Written server-side by SECURITY DEFINER business RPCs (D-011); RF-017 adds no writer. Platform-admin audited path is RF-060.';

-- ----------------------------------------------------------------------------
-- 2. Indexes for tenant-scoped audit queries.
-- ----------------------------------------------------------------------------
create index audit_events_org_occurred_idx on audit_events (organization_id, occurred_at desc);
create index audit_events_org_scope_idx    on audit_events (organization_id, restaurant_id, branch_id);
create index audit_events_org_action_idx   on audit_events (organization_id, action);

-- ----------------------------------------------------------------------------
-- 3. Append-only trigger. NORMAL INVOKER function (NOT SECURITY DEFINER) — it
--    only RAISEs, needs no elevated privilege and reads no table. search_path is
--    locked to '' for hardening (TG_OP is a plpgsql variable; no object refs).
--    Blocks UPDATE/DELETE (row-level) AND TRUNCATE (via the companion
--    statement-level trigger below) even for the table owner / a mistakenly-
--    granted role; only a true superuser disabling triggers could bypass it
--    (out of app scope). Row-level triggers never fire on TRUNCATE, so TRUNCATE
--    needs its own BEFORE TRUNCATE statement-level trigger.
-- ----------------------------------------------------------------------------
create or replace function app.enforce_audit_append_only()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  raise exception 'audit_events is append-only: % is not permitted', TG_OP
    using errcode = '42501';
end;
$$;

comment on function app.enforce_audit_append_only() is
  'RF-017 append-only guard: rejects any UPDATE/DELETE/TRUNCATE on audit_events (SQLSTATE 42501). NORMAL invoker function (NOT SECURITY DEFINER) — it only raises; no elevated privilege or table access needed (DECISION D-013).';

-- Trigger functions fire regardless of EXECUTE grants; remove the default PUBLIC execute.
revoke all on function app.enforce_audit_append_only() from public;

-- Row-level guard: blocks UPDATE/DELETE (per-row).
create trigger audit_events_append_only
  before update or delete on audit_events
  for each row execute function app.enforce_audit_append_only();

-- Statement-level guard: TRUNCATE is destructive and DELETE-equivalent for the
-- append-only trail but does NOT fire row-level triggers — guard it separately
-- (reuses the same invoker function; TG_OP reports 'TRUNCATE').
create trigger audit_events_no_truncate
  before truncate on audit_events
  for each statement execute function app.enforce_audit_append_only();

-- ----------------------------------------------------------------------------
-- 4. RLS (DECISION D-012 L1): ENABLE + FORCE, deny-by-default. SELECT-ONLY policy
--    (org + scope narrowing, reusing the RF-015 membership-derived resolver +
--    scope predicate UNCHANGED). NO insert/update/delete policy => those commands
--    are denied for app roles (append-only). No new GUCs; no device principal.
-- ----------------------------------------------------------------------------
alter table audit_events enable row level security;
alter table audit_events force  row level security;

create policy audit_events_select on audit_events
  for select
  to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

-- ----------------------------------------------------------------------------
-- 5. Grants: least privilege — authenticated may SELECT only. NO insert/update/
--    delete (writes come from server-side SECURITY DEFINER RPCs as table owner).
--    Never anon.
-- ----------------------------------------------------------------------------
grant select on audit_events to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop table if exists audit_events;        -- drops its policy, indexes, and trigger
-- drop function if exists app.enforce_audit_append_only();
-- ============================================================================
