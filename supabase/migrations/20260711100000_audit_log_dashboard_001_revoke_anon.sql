-- ============================================================================
-- AUDIT-LOG-DASHBOARD-001 (corrective) — restore the intended AUTHENTICATED-ONLY
-- ACL on the read-only audit-timeline wrapper.
--
-- WHY: on the hosted Supabase project, a schema-`public` platform default
-- (`ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON FUNCTIONS TO anon`, applied by
-- the migration-running role — NOT present on the local Docker stack) gave the
-- freshly-created `public.owner_audit_events` wrapper a SEPARATE, explicit
-- `anon` EXECUTE grant at creation time. The prior migration
-- (20260711090000) did `REVOKE ALL ... FROM PUBLIC` + `GRANT ... TO authenticated`
-- (the local ACL is therefore already correct: `{postgres, authenticated}`), but
-- a `REVOKE ... FROM PUBLIC` does NOT remove a grant recorded specifically to the
-- `anon` role, so hosted `anon` retained EXECUTE on the wrapper.
--
-- No data was exposed: the wrapper is `SECURITY INVOKER` over the GUC-free
-- `SECURITY DEFINER` `app.owner_audit_events`, whose FIRST action is
-- `app.current_app_user_id()` (null for an anonymous caller) -> raise `42501`.
-- The grant is nonetheless unnecessary and is removed here for ACL hygiene (the
-- audit log is a management-only surface; D-011).
--
-- SCOPE: this migration changes ONLY grants. It does NOT edit the already-applied
-- 20260711090000 migration, touch any function body, RLS policy, audit row,
-- table, or index. Forward-only, additive, idempotent (Supabase replays on
-- `db reset`). NOT applied to the hosted DB by this file.
-- ============================================================================

-- 1. The public wrapper — the PostgREST-reachable surface. Close both the PUBLIC
--    path and the inherited explicit `anon` grant; keep `authenticated` EXECUTE.
--    (`REVOKE ... FROM PUBLIC` and the re-GRANT are idempotent no-ops locally.)
revoke all    on function public.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) from public;
revoke all    on function public.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) from anon;
grant  execute on function public.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) to authenticated;

-- 2. Defense in depth on the underlying `app` functions (the `app` schema is not
--    Data-API-exposed, so these had no anon grant, but make it EXPLICIT that
--    `anon` may never execute them; `authenticated` grants are left intact).
revoke all on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) from anon;
revoke all on function app.audit_safe_detail(text, jsonb)     from anon;
revoke all on function app.audit_action_has_detail(text)      from anon;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   -- restoring the anon grant is deliberately NOT provided (it is the defect).
--   grant execute on function public.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) to authenticated;
-- ============================================================================
