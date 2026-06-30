-- ============================================================================
-- RF-150 (review fix) — Harden printer-config authorization. Codex CHANGES
-- REQUESTED, two blockers. Additive + FORWARD-ONLY: create-or-replace two
-- existing app.* functions (signatures + grants unchanged; the public.* wrappers
-- are untouched and keep delegating to these same names). RLS is NOT changed; no
-- new grant; no anon access; the functions stay SECURITY DEFINER with a locked
-- search_path (their existing, intended posture).
--
-- BLOCKER 1 — privilege escalation in app.soft_delete_printer_device. The original
-- authorized against the CALLER-SUPPLIED (org, restaurant, branch) and only checked
-- the target printer's organization_id, so a branch-A-scoped manager could pass
-- branch A as the scope and delete a same-org branch-B printer. FIX: load the target
-- printer FIRST and authorize against its ACTUAL (org, restaurant, branch) — the
-- RF-112 app.update_role pattern (authority over the loaded row's OWN scope). A
-- branch-scoped manager can no longer reach a sibling-branch printer; org-/restaurant-
-- level members still cover it (downward-only coverage). Routes are tombstoned ONLY
-- after authorization succeeds.
--
-- BLOCKER 2 — the printer RPCs authorized via app.current_org_id() / app.has_scope() /
-- app.has_role_in_scope(), which depend on the app.current_organization_id GUC that
-- real Data API (JWT) callers never set (RF-059 A5: "Real client org-selection remains
-- a follow-up"), so the public printer wrappers failed closed for production clients.
-- FIX: authorize via the RF-112 (D-033) GUC-FREE resolver app.actor_rank_in_scope(org,
-- restaurant, branch) + app.role_rank('manager'). Identity comes from
-- app.current_app_user_id() (which resolves from auth.uid() for a JWT principal,
-- RF-050), and the org boundary is the PASSED org validated directly against
-- memberships — no current-organization GUC. Same role model: org_owner(4) /
-- restaurant_owner(3) / manager(2) may write; cashier/kitchen_staff/accountant(1) and
-- platform_admin/non-members(0) cannot. Semantics preserved: structural failures
-- (no covering membership / cross-org / out-of-scope) RAISE 42501; an in-scope member
-- below manager is role-denied with a committed *_denied audit + {ok:false}.
--
-- The two write RPCs that call app.printer_guard (upsert_printer_device,
-- set_printer_route) are fixed transitively by the guard swap; their bodies are
-- unchanged (the create-path/update-immutability authorizes against the scope the row
-- lives in, which the caller must cover). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.printer_guard — GUC-FREE owner/manager write gate (BLOCKER 2).
--    Raises 42501 for unauthenticated / no-covering-membership (structural); returns
--    TRUE for a manager-or-higher rank in scope, FALSE for an in-scope member below
--    manager (role-denied path). Uses app.actor_rank_in_scope (RF-112 D-033) — NOT
--    app.current_org_id()/has_scope()/has_role_in_scope() — so it works for real JWT
--    Data API callers with no app.current_organization_id GUC.
-- ----------------------------------------------------------------------------
create or replace function app.printer_guard(p_org uuid, p_restaurant uuid, p_branch uuid)
  returns boolean
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_rank integer;
begin
  if app.current_app_user_id() is null then
    raise exception 'printer: authentication required' using errcode = '42501';
  end if;
  v_rank := app.actor_rank_in_scope(p_org, p_restaurant, p_branch);
  if v_rank = 0 then
    raise exception 'printer: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  return v_rank >= app.role_rank('manager');  -- org_owner/restaurant_owner/manager may write
end;
$$;

comment on function app.printer_guard(uuid, uuid, uuid) is
  'RF-150 (review fix, BLOCKER 2): GUC-free owner/manager write gate for printer config. Identity = app.current_app_user_id() (auth.uid() for JWT clients, RF-050); authority = app.actor_rank_in_scope(p_org, p_restaurant, p_branch) (RF-112 D-033, GUC-free — the org boundary is the PASSED p_org, NOT app.current_organization_id). Raises 42501 for unauthenticated / no-covering-membership; TRUE for rank >= manager(2); FALSE for an in-scope member below manager (role-denied). Replaces the prior app.current_org_id()/has_scope()/has_role_in_scope() gate that failed closed for real Data API callers.';

-- ----------------------------------------------------------------------------
-- 2. app.soft_delete_printer_device — authorize against the TARGET's ACTUAL scope
--    (BLOCKER 1). Same signature + grants as before (the public wrapper is unchanged);
--    the caller-supplied org/restaurant/branch are now ADVISORY — authorization and
--    auditing use the loaded printer's real scope, so a branch-scoped manager cannot
--    delete a sibling-branch printer by mislabelling the scope. Routes are tombstoned
--    ONLY after authorization.
-- ----------------------------------------------------------------------------
create or replace function app.soft_delete_printer_device(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_id              uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org    uuid;
  v_rest   uuid;
  v_branch uuid;
  v_old    jsonb;
  v_routes integer := 0;
begin
  if app.current_app_user_id() is null then
    raise exception 'soft_delete_printer_device: authentication required' using errcode = '42501';
  end if;
  if p_id is null then
    raise exception 'soft_delete_printer_device: id is required' using errcode = '42501';
  end if;

  -- load the TARGET first; authorization is against its ACTUAL scope, never the
  -- caller-supplied one (the RF-112 update_role pattern).
  select organization_id, restaurant_id, branch_id into v_org, v_rest, v_branch
    from public.printer_devices where id = p_id and deleted_at is null;
  if v_org is null then
    raise exception 'soft_delete_printer_device: printer not found (or already deleted)' using errcode = '42501';
  end if;

  -- authorize against the printer's OWN scope: a branch-A manager targeting a branch-B
  -- printer resolves rank 0 here (no covering membership) and is rejected with 42501;
  -- org-/restaurant-wide members still cover it. An in-scope member below manager is
  -- role-denied (committed audit + {ok:false}).
  if not app.printer_guard(v_org, v_rest, v_branch) then
    perform app.printer_audit(v_org, v_rest, v_branch,
      'printer.printer_device.delete_denied', null,
      jsonb_build_object('entity', 'printer_device', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'printer_device');
  end if;

  -- only AFTER authorization: a removed printer must not stay routed.
  select to_jsonb(t) into v_old from public.printer_devices t where t.id = p_id;
  update public.printer_routes set deleted_at = now()
    where printer_device_id = p_id and deleted_at is null;
  get diagnostics v_routes = row_count;
  update public.printer_devices set deleted_at = now() where id = p_id;

  perform app.printer_audit(v_org, v_rest, v_branch,
    'printer.printer_device.deleted', v_old,
    jsonb_build_object('id', p_id, 'routes_removed', v_routes));
  return jsonb_build_object('ok', true, 'entity', 'printer_device', 'id', p_id, 'action', 'deleted', 'routes_removed', v_routes);
end;
$$;

comment on function app.soft_delete_printer_device(uuid, uuid, uuid, uuid) is
  'RF-150 (review fix, BLOCKER 1): soft-delete a printer + its live routes. Loads the target FIRST and authorizes against its ACTUAL (org, restaurant, branch) via app.printer_guard (RF-112 actor_rank_in_scope) — the caller-supplied scope is advisory. A branch-scoped manager cannot delete a sibling-branch printer; org-/restaurant-level members still can (downward coverage). Routes are tombstoned only after authorization. Idempotent re-call on an already-deleted id raises not-found 42501.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   restore the RF-150 rpcs-migration bodies of app.printer_guard (current_org_id/
--   has_scope/has_role_in_scope gate) and app.soft_delete_printer_device (caller-scope
--   authorization). No grant/signature change to undo.
-- ============================================================================
