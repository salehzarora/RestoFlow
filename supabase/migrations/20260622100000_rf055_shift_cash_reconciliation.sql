-- ============================================================================
-- RF-055 — shifts / cash_drawer_sessions / shift_operations + open/close/
--          reconcile shift RPCs + record_payment open-shift linkage
-- ============================================================================
-- The server-side shift + cash-drawer lifecycle and cash reconciliation. Builds
-- on RF-014 (org/restaurant/branch core + app.current_org_id/has_scope/
-- set_updated_at), RF-015 (memberships/employee_profiles + roles), RF-016/051
-- (devices/device_sessions/pin_sessions + app.is_pin_session_valid), RF-017
-- (append-only audit_events), RF-054 (payments + app.record_payment). Mirrors the
-- RF-037 LOCAL Dart shift/drawer model (states + variance math). Additive and
-- FORWARD-ONLY: it NEVER edits a prior migration.
--
-- WHAT THIS DOES (API_CONTRACT §4.8 open_shift, §4.9.1 close_shift, §4.9.2
-- reconcile_shift; DOMAIN_MODEL §8.2/§8.3; STATE_MACHINES §6/§7/§11; MONEY §14)
--   1. shifts — an operational work period at a branch on a device (the cash/sales
--      rollup boundary). One non-terminal shift per (organization_id, branch_id,
--      device_id) (A1). States opening -> open -> closing -> closed -> reconciled.
--   2. cash_drawer_sessions — a cash-drawer accounting session bound 1:1 to a shift.
--      Carries the opening float and the counted/expected/variance at close. States
--      opened -> active -> counting -> closed -> reconciled.
--   3. shift_operations — a shift-bound idempotency ledger (D-022). Separate from
--      the order-bound order_operations (A5).
--   4. payments FK linkage (A3): payments.shift_id / cash_drawer_session_id become
--      nullable composite same-org FKs to the new tables.
--   5. app.open_shift / app.close_shift / app.reconcile_shift — SECURITY DEFINER
--      RPCs enforcing authorization (D-028 separation of duties), the state
--      machines (D-018), integer-_minor variance math (MONEY §14), append-only
--      audit (D-013), and shift-bound idempotency (D-022).
--   6. app.record_payment CREATE OR REPLACE (A2): now REQUIRES an open shift + an
--      active bound cash drawer for the (org, branch, device) and STAMPS
--      payments.shift_id / cash_drawer_session_id. All other RF-054 behavior is
--      preserved verbatim (auth, order-bound idempotency, receipt numbering,
--      duplicate-payment prevention, no order-status auto-advance, the two audits).
--
-- DECISIONS
--   * D-007 integer minor money; NO float/numeric/double/money types for money.
--   * D-011 sensitive mutations only via SECURITY DEFINER RPC; clients never write
--     tenant rows directly; no service-role in clients.
--   * D-012 four layers; composite same-org FKs (layer 4).
--   * D-013 append-only audit (success + denial). D-018 state enumerations.
--   * D-022 idempotency key = device_id + local_operation_id (+ action here).
--   * D-028 accountant strictly read-only; close/count (close_shift) is SEPARATE
--     from reconciliation (reconcile_shift) — one RPC must not do both (separation
--     of duties: the party that counts must not approve its own variance).
--
-- APPROVED INTERIM DECISIONS (RF-055; human-approved A1..A9)
--   * A1: shifts carry device_id; one non-terminal shift per (org, branch, device)
--     (multi-register branches allowed — NOT per-branch-only).
--   * A2: record_payment now requires an open shift + active drawer and stamps the
--     linkage; the RF-054 pgTAP fixtures are updated to open a shift first.
--   * A3: payments.shift_id / cash_drawer_session_id are nullable composite same-org
--     FKs (existing NULL rows remain valid).
--   * A4: columns follow DOMAIN_MODEL (expected_total_minor / counted_total_minor /
--     variance_minor / opening_float_minor); the close RPC input param is
--     p_counted_amount_minor (API naming). Mapping is documented inline + in tests.
--   * A5: separate shift_operations ledger (not order_operations — shift-bound).
--   * A6: NO cash_movements/pay-in/pay-out table. MVP expected cash =
--     opening_float_minor + completed cash payments.amount_minor for the drawer.
--     Refunds/pay-ins/pay-outs/tips/service-charge are out of scope (0 in MVP).
--   * A7: no threshold constant. close_shift requires a non-empty reason when
--     variance_minor <> 0; reconcile_shift requires a non-empty note when
--     variance_minor <> 0; both optional when variance is 0.
--   * A8: NO manager reopen of a closed shift in RF-055. Per-RPC role gates only;
--     the same manager is NOT hard-blocked from closing then reconciling.
--   * A9: NO currency column on shifts/drawers; currency derives from
--     branch/order/payment context. All money stays bigint _minor.
--
-- OUT OF SCOPE: RF-056/057 sync/outbox; reports; printing/receipt rendering;
--   card/online payments; refunds; void_payment; accounting exports; cash
--   pay-in/pay-out + a cash_movements table; tips (Q-011); service charge (Q-012);
--   cash rounding (Q-001/Q-002); manager reopen (A8); variance threshold constant
--   (A7); frontend/admin UI; route_to_kitchen + kitchen tables; any Dart/apps/
--   packages/config/remote/secrets/service-role.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. shifts — an operational work period at a branch on a device. Tenant+branch
--    scoped; cross-org/branch/device refs are structurally impossible via composite
--    same-org FKs (D-012 layer 4). Money columns are integer _minor (D-007),
--    nullable until close. Written ONLY by the RF-055 RPCs; authenticated SELECT-only.
-- ----------------------------------------------------------------------------
create table shifts (
  id                              uuid        not null default gen_random_uuid(),
  organization_id                 uuid        not null references organizations (id) on delete restrict,
  restaurant_id                   uuid        not null,
  branch_id                       uuid        not null,
  device_id                       uuid        not null,                  -- the POS station the shift runs on (A1)
  opened_by_employee_profile_id   uuid        not null,
  resolved_membership_id          uuid        not null,
  closed_by_employee_profile_id   uuid,                                  -- soft ref, set server-side at close
  reconciled_by_employee_profile_id uuid,                               -- soft ref, set server-side at reconcile
  status                          text        not null default 'open'
                                    check (status in ('opening','open','closing','closed','reconciled')),
  expected_total_minor            bigint      check (expected_total_minor is null or expected_total_minor >= 0),
  counted_total_minor             bigint      check (counted_total_minor  is null or counted_total_minor  >= 0),
  variance_minor                  bigint,                                -- signed: counted - expected (negative = shortage)
  close_reason                    text,
  reconcile_note                  text,
  opened_at                       timestamptz not null default now(),
  closed_at                       timestamptz,
  reconciled_at                   timestamptz,
  local_operation_id              text        not null,
  revision                        integer     not null default 1,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  deleted_at                      timestamptz,
  primary key (id),
  unique (organization_id, id),                                          -- same-org composite-FK target (payments/drawers/ledger)
  unique (device_id, local_operation_id),                               -- idempotency race backstop (D-022)
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, opened_by_employee_profile_id)
    references employee_profiles (organization_id, id) on delete restrict,
  foreign key (organization_id, resolved_membership_id)
    references memberships (organization_id, id) on delete restrict
);

comment on table shifts is
  'RF-055: an operational work period at a branch on a device (DOMAIN_MODEL §8.2). Tenant+branch scoped; all money integer _minor (D-007). Written ONLY by the RF-055 SECURITY DEFINER RPCs (D-011). States opening->open->closing->closed->reconciled (D-018); reconciled is terminal. One non-terminal shift per (org, branch, device) (A1). variance_minor = counted - expected (signed; MONEY §14).';

create index shifts_branch_idx        on shifts (organization_id, restaurant_id, branch_id);
create index shifts_device_idx        on shifts (organization_id, restaurant_id, branch_id, device_id);
create index shifts_employee_idx      on shifts (organization_id, opened_by_employee_profile_id);
create index shifts_membership_idx    on shifts (organization_id, resolved_membership_id);
-- one non-terminal (active) shift per (org, branch, device) (A1; STATE_MACHINES §6.2)
create unique index shifts_one_active_per_device_uidx
  on shifts (organization_id, branch_id, device_id)
  where status in ('opening','open','closing');

-- ----------------------------------------------------------------------------
-- 2. cash_drawer_sessions — a cash-drawer accounting session bound 1:1 to a shift
--    (DOMAIN_MODEL §8.3). Carries the opening float and the counted/expected/
--    variance recorded at close. Integer _minor money. Written ONLY by the RPCs.
-- ----------------------------------------------------------------------------
create table cash_drawer_sessions (
  id                            uuid        not null default gen_random_uuid(),
  organization_id               uuid        not null references organizations (id) on delete restrict,
  restaurant_id                 uuid        not null,
  branch_id                     uuid        not null,
  device_id                     uuid        not null,
  shift_id                      uuid        not null,                    -- bound 1:1 to its shift (NOT NULL)
  opened_by_employee_profile_id uuid        not null,
  opening_float_minor           bigint      not null check (opening_float_minor >= 0),
  status                        text        not null default 'active'
                                  check (status in ('opened','active','counting','closed','reconciled')),
  expected_total_minor          bigint      check (expected_total_minor is null or expected_total_minor >= 0),
  counted_total_minor           bigint      check (counted_total_minor  is null or counted_total_minor  >= 0),
  variance_minor                bigint,                                  -- signed: counted - expected
  opened_at                     timestamptz not null default now(),
  closed_at                     timestamptz,
  reconciled_at                 timestamptz,
  local_operation_id            text        not null,
  revision                      integer     not null default 1,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  deleted_at                    timestamptz,
  primary key (id),
  unique (organization_id, id),                                          -- same-org composite-FK target (payments)
  unique (organization_id, shift_id),                                    -- one cash drawer session per shift (MVP)
  foreign key (organization_id, shift_id)
    references shifts (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, opened_by_employee_profile_id)
    references employee_profiles (organization_id, id) on delete restrict
);

comment on table cash_drawer_sessions is
  'RF-055: a cash-drawer accounting session bound 1:1 to a shift (DOMAIN_MODEL §8.3). All money integer _minor (D-007). Written ONLY by the RF-055 RPCs. States opened->active->counting->closed->reconciled (D-018); reconciled is terminal. opening_float_minor >= 0; variance_minor = counted - expected (signed; MONEY §14). expected_total_minor = opening_float_minor + completed cash payments for this drawer (A6; no refunds/pay-ins/pay-outs in MVP).';

create index cash_drawer_sessions_shift_idx    on cash_drawer_sessions (organization_id, shift_id);
create index cash_drawer_sessions_branch_idx   on cash_drawer_sessions (organization_id, restaurant_id, branch_id);
create index cash_drawer_sessions_device_idx   on cash_drawer_sessions (organization_id, restaurant_id, branch_id, device_id);
create index cash_drawer_sessions_employee_idx on cash_drawer_sessions (organization_id, opened_by_employee_profile_id);

-- ----------------------------------------------------------------------------
-- 3. shift_operations — shift-bound mutation idempotency ledger (D-022; A5). One
--    row per (org, device, local_operation_id, action). Stores the result envelope
--    so a replay returns it verbatim. Written ONLY by the RF-055 RPCs.
-- ----------------------------------------------------------------------------
create table shift_operations (
  id                 uuid        not null default gen_random_uuid(),
  organization_id    uuid        not null references organizations (id) on delete restrict,
  restaurant_id      uuid        not null,
  branch_id          uuid        not null,
  device_id          uuid        not null,
  local_operation_id text        not null,
  action             text        not null check (action in ('open_shift', 'close_shift', 'reconcile_shift')),
  shift_id           uuid        not null,
  result             jsonb       not null,
  created_at         timestamptz not null default now(),
  primary key (id),
  unique (organization_id, device_id, local_operation_id, action),       -- idempotency key (D-022)
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, shift_id)
    references shifts (organization_id, id) on delete restrict
);

comment on table shift_operations is
  'RF-055: shift-bound mutation idempotency ledger (D-022; A5). One row per (organization_id, device_id, local_operation_id, action); the RPC returns the stored result on replay so an open/close/reconcile is never double-applied and no audit row is duplicated. Shift-bound (not order-bound like order_operations). Written only by the RF-055 RPCs; authenticated SELECT-only.';

create index shift_operations_branch_idx on shift_operations (organization_id, restaurant_id, branch_id);
create index shift_operations_shift_idx  on shift_operations (organization_id, shift_id);

-- ----------------------------------------------------------------------------
-- 4. updated_at triggers (reuse RF-014 app.set_updated_at()). shift_operations is
--    append-only (no updated_at).
-- ----------------------------------------------------------------------------
create trigger shifts_set_updated_at               before update on shifts               for each row execute function app.set_updated_at();
create trigger cash_drawer_sessions_set_updated_at  before update on cash_drawer_sessions  for each row execute function app.set_updated_at();

-- ----------------------------------------------------------------------------
-- 5. RLS: enable + force, deny-by-default, membership/branch scoped (reuse the
--    RF-014/RF-015 resolver + scope helpers UNCHANGED). authenticated may SELECT in
--    scope; ALL direct writes are revoked (the SECURITY DEFINER RPCs are the only writers).
-- ----------------------------------------------------------------------------
alter table shifts               enable row level security;
alter table shifts               force  row level security;
alter table cash_drawer_sessions enable row level security;
alter table cash_drawer_sessions force  row level security;
alter table shift_operations     enable row level security;
alter table shift_operations     force  row level security;

create policy shifts_scoped on shifts
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

create policy cash_drawer_sessions_scoped on cash_drawer_sessions
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

create policy shift_operations_scoped on shift_operations
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

grant select on shifts               to authenticated;
grant select on cash_drawer_sessions to authenticated;
grant select on shift_operations     to authenticated;
revoke insert, update, delete on shifts               from authenticated;
revoke insert, update, delete on cash_drawer_sessions from authenticated;
revoke insert, update, delete on shift_operations     from authenticated;

-- ----------------------------------------------------------------------------
-- 6. payments linkage (A3). Convert the RF-054 nullable non-FK shift_id /
--    cash_drawer_session_id into nullable composite same-org FKs. Existing rows
--    (NULL) remain valid (MATCH SIMPLE skips the check when the ref column is null).
--    Done via THIS migration (the RF-054 file is unchanged).
-- ----------------------------------------------------------------------------
alter table public.payments
  add constraint payments_shift_same_org
    foreign key (organization_id, shift_id)
    references shifts (organization_id, id) on delete restrict;
alter table public.payments
  add constraint payments_cash_drawer_session_same_org
    foreign key (organization_id, cash_drawer_session_id)
    references cash_drawer_sessions (organization_id, id) on delete restrict;

create index payments_shift_idx  on payments (organization_id, shift_id);
create index payments_drawer_idx on payments (organization_id, cash_drawer_session_id);

-- ----------------------------------------------------------------------------
-- 7. app.open_shift — opens a shift AND its bound cash-drawer session together
--    (API_CONTRACT §4.8; there is no separate open_cash_drawer RPC). Client supplies
--    the shift_id + cash_drawer_session_id (offline-provisional ids; RF-052 pattern).
--    Actor/org/restaurant/branch derived from the PIN session, never client input.
-- ----------------------------------------------------------------------------
create or replace function app.open_shift(
  p_pin_session_id         uuid,
  p_shift_id               uuid,
  p_cash_drawer_session_id uuid,
  p_device_id              uuid,
  p_local_operation_id     text,
  p_opening_float_minor    bigint
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_emp         uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_stored      jsonb;
  v_stored_shift uuid;
  v_active_cnt  integer;
  v_result      jsonb;
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'open_shift: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'open_shift: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'open_shift: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'open_shift: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'open_shift: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) authorization (A8): cashier/manager/restaurant_owner/org_owner may open a
  --     shift. kitchen_staff/accountant/other denied -> shift.open_denied audit +
  --     returned permission_denied (no raise, so the audit persists), no state change.
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'shift.open_denied', null, null,
      jsonb_build_object('attempted_action', 'open_shift', 'shift_id', p_shift_id, 'role', v_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'shift_id', p_shift_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) safe input validation
  if p_opening_float_minor is null or p_opening_float_minor < 0 then
    raise exception 'open_shift: opening_float_minor must be a non-negative integer (minor units)' using errcode = '42501';
  end if;

  -- (d) idempotency replay (RF053-B1): AFTER authorization + input validation.
  --     SHIFT-BOUND: the same (org, device, local_operation_id, action='open_shift')
  --     reused for a DIFFERENT shift_id is a conflict, not a replay.
  select so.result, so.shift_id into v_stored, v_stored_shift
    from public.shift_operations so
    where so.organization_id = v_org and so.device_id = p_device_id
      and so.local_operation_id = p_local_operation_id and so.action = 'open_shift';
  if found then
    if v_stored_shift <> p_shift_id then
      raise exception 'open_shift: idempotency key already used for a different shift (%, not %)', v_stored_shift, p_shift_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (e) one active (non-terminal) shift per (org, branch, device) (A1)
  select count(*) into v_active_cnt
    from public.shifts s
    where s.organization_id = v_org and s.branch_id = v_branch and s.device_id = p_device_id
      and s.status in ('opening', 'open', 'closing');
  if v_active_cnt > 0 then
    raise exception 'open_shift: an active shift already exists for this branch/device' using errcode = '42501';
  end if;

  -- (f) create the shift (status open) and its bound cash drawer (status active)
  insert into public.shifts (
    id, organization_id, restaurant_id, branch_id, device_id,
    opened_by_employee_profile_id, resolved_membership_id, status, opened_at, local_operation_id, revision)
  values (
    p_shift_id, v_org, v_rest, v_branch, p_device_id,
    v_emp, v_membership, 'open', now(), p_local_operation_id, 1);

  insert into public.cash_drawer_sessions (
    id, organization_id, restaurant_id, branch_id, device_id, shift_id,
    opened_by_employee_profile_id, opening_float_minor, status, opened_at, local_operation_id, revision)
  values (
    p_cash_drawer_session_id, v_org, v_rest, v_branch, p_device_id, p_shift_id,
    v_emp, p_opening_float_minor, 'active', now(), p_local_operation_id, 1);

  -- (g) audit: shift.opened + cash_drawer.opened (D-013)
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'shift.opened', null, null,
    jsonb_build_object('shift_id', p_shift_id, 'status', 'open', 'device_id', p_device_id,
                       'resolved_membership_id', v_membership));
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'cash_drawer.opened', null, null,
    jsonb_build_object('cash_drawer_session_id', p_cash_drawer_session_id, 'shift_id', p_shift_id,
                       'status', 'active', 'opening_float_minor', p_opening_float_minor, 'device_id', p_device_id));

  -- (h) record ledger + return
  v_result := jsonb_build_object(
    'ok', true, 'shift_id', p_shift_id, 'cash_drawer_session_id', p_cash_drawer_session_id,
    'status', 'open', 'drawer_status', 'active', 'opening_float_minor', p_opening_float_minor, 'revision', 1);
  insert into public.shift_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, shift_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'open_shift', p_shift_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.open_shift(uuid, uuid, uuid, uuid, text, bigint) is
  'RF-055 (API_CONTRACT §4.8, D-011) SECURITY DEFINER RPC: opens a shift + its bound cash-drawer session (no separate open_cash_drawer RPC). Actor/scope from a VALID PIN session. Authorized for cashier/manager/restaurant_owner/org_owner; kitchen_staff/accountant/other denied -> shift.open_denied audit + permission_denied (no raise). opening_float_minor >= 0. Enforces one active shift per (org, branch, device) (A1). Writes shift.opened + cash_drawer.opened (D-013). Idempotent via shift_operations (D-022, shift-bound; same key/different shift -> 40001).';

revoke all on function app.open_shift(uuid, uuid, uuid, uuid, text, bigint) from public;
grant execute on function app.open_shift(uuid, uuid, uuid, uuid, text, bigint) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. app.close_shift — the operator close/count step (API_CONTRACT §4.9.1).
--    Computes expected cash from completed cash payments bound to the drawer,
--    records counted + variance, moves shift open->closed and drawer active->closed.
--    Cashier may close OWN shift; manager+ may close on behalf (D-028). NOT
--    reconciliation (a separate RPC; D-028 — one RPC must not do both).
-- ----------------------------------------------------------------------------
create or replace function app.close_shift(
  p_pin_session_id       uuid,
  p_shift_id             uuid,
  p_device_id            uuid,
  p_local_operation_id   text,
  p_counted_amount_minor bigint,                 -- API naming; maps to counted_total_minor (A4)
  p_reason               text default null,
  p_expected_revision    integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_s_org        uuid;
  v_s_branch     uuid;
  v_s_status     text;
  v_s_rev        integer;
  v_s_opened_by  uuid;
  v_drawer_id    uuid;
  v_drawer_status text;
  v_drawer_rev   integer;
  v_opening      bigint;
  v_cash_sales   bigint;
  v_expected     bigint;
  v_counted      bigint;
  v_variance     bigint;
  v_authorized   boolean;
  v_new_rev      integer;
  v_stored       jsonb;
  v_stored_shift uuid;
  v_result       jsonb;
begin
  -- (a) PIN session + backing + actor/scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'close_shift: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'close_shift: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'close_shift: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'close_shift: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'close_shift: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the shift; it MUST be in the actor's org + branch (no cross-tenant)
  select s.organization_id, s.branch_id, s.status, s.revision, s.opened_by_employee_profile_id
    into v_s_org, v_s_branch, v_s_status, v_s_rev, v_s_opened_by
    from public.shifts s where s.id = p_shift_id;
  if not found then
    raise exception 'close_shift: shift not found' using errcode = '42501';
  end if;
  if v_s_org <> v_org or v_s_branch <> v_branch then
    raise exception 'close_shift: shift is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (D-028): manager/restaurant_owner/org_owner may close any shift;
  --     a cashier may close ONLY their OWN shift (opened_by = actor). kitchen_staff/
  --     accountant/other denied -> shift.close_denied audit + permission_denied (no raise).
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or (v_role = 'cashier' and v_s_opened_by = v_emp);
  if not v_authorized then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'shift.close_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'close_shift', 'shift_id', p_shift_id,
                         'role', v_role, 'shift_status', v_s_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'shift_id', p_shift_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) safe input validation
  if p_counted_amount_minor is null or p_counted_amount_minor < 0 then
    raise exception 'close_shift: counted amount must be a non-negative integer (minor units)' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + input validation,
  --     SHIFT-BOUND. Same key/action on a DIFFERENT shift is a conflict (40001).
  select so.result, so.shift_id into v_stored, v_stored_shift
    from public.shift_operations so
    where so.organization_id = v_org and so.device_id = p_device_id
      and so.local_operation_id = p_local_operation_id and so.action = 'close_shift';
  if found then
    if v_stored_shift <> p_shift_id then
      raise exception 'close_shift: idempotency key already used for a different shift (%, not %)', v_stored_shift, p_shift_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) ROW LOCKS (RF055-B1/B2): lock the target shift, then its bound cash drawer,
  --     with FOR UPDATE in a CONSISTENT order (shift -> drawer) shared by record_payment
  --     and reconcile_shift. State is RE-READ under the locks and validated only after
  --     they are held, so (B1) two concurrent transactions with different
  --     local_operation_ids cannot both pass the guard and double-close, and (B2) a
  --     concurrent record_payment cannot insert a cash sale between the sum and the
  --     close — it must take the same shift lock first, so it either commits before this
  --     sum (and is counted) or blocks until COMMIT and then sees a non-active drawer.
  --     Locks are released at COMMIT. The unlocked load at (b) gave the immutable
  --     opened_by for authorization; status/revision are now the authoritative locked values.
  select s.status, s.revision into v_s_status, v_s_rev
    from public.shifts s where s.id = p_shift_id for update;
  select cds.id, cds.status, cds.revision, cds.opening_float_minor
    into v_drawer_id, v_drawer_status, v_drawer_rev, v_opening
    from public.cash_drawer_sessions cds
    where cds.organization_id = v_org and cds.shift_id = p_shift_id
    for update;
  if not found then
    raise exception 'close_shift: no cash drawer session bound to the shift' using errcode = '42501';
  end if;

  -- (f2) state legality (validated UNDER the locks): shift open, drawer active
  if v_s_status <> 'open' then
    raise exception 'close_shift: shift status % is not a legal close source state (expected open)', v_s_status using errcode = '42501';
  end if;
  if v_drawer_status <> 'active' then
    raise exception 'close_shift: cash drawer status % is not a legal close source state (expected active)', v_drawer_status using errcode = '42501';
  end if;

  -- (g) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_s_rev then
    raise exception 'close_shift: revision conflict (expected %, got %)', p_expected_revision, v_s_rev using errcode = '40001';
  end if;

  -- (h) reconciliation math (MONEY §14; A6). expected = opening float + completed
  --     cash sales for this drawer. No refunds/pay-ins/pay-outs in MVP. All _minor.
  select coalesce(sum(p.amount_minor), 0) into v_cash_sales
    from public.payments p
    where p.organization_id = v_org and p.cash_drawer_session_id = v_drawer_id
      and p.method = 'cash' and p.status = 'completed';
  v_expected := v_opening + v_cash_sales;
  v_counted  := p_counted_amount_minor;
  v_variance := v_counted - v_expected;            -- signed: negative = shortage, positive = overage

  -- (i) reason mandatory when variance is non-zero (A7)
  if v_variance <> 0 and btrim(coalesce(p_reason, '')) = '' then
    raise exception 'close_shift: a non-empty reason is required when the variance is non-zero (variance=%)', v_variance using errcode = '42501';
  end if;

  -- (j) mutate: shift open->closed, drawer active->closed; persist amounts on both
  v_new_rev := v_s_rev + 1;
  update public.shifts
    set status = 'closed', expected_total_minor = v_expected, counted_total_minor = v_counted,
        variance_minor = v_variance, close_reason = nullif(btrim(coalesce(p_reason, '')), ''),
        closed_at = now(), closed_by_employee_profile_id = v_emp, revision = v_new_rev
    where id = p_shift_id;
  update public.cash_drawer_sessions
    set status = 'closed', expected_total_minor = v_expected, counted_total_minor = v_counted,
        variance_minor = v_variance, closed_at = now(), revision = v_drawer_rev + 1
    where id = v_drawer_id;

  -- (k) audit: shift.closed + cash_drawer.closed (D-013) with old/new + amounts
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'shift.closed', nullif(btrim(coalesce(p_reason, '')), ''),
    jsonb_build_object('status', 'open', 'revision', v_s_rev),
    jsonb_build_object('shift_id', p_shift_id, 'status', 'closed', 'revision', v_new_rev,
                       'opening_float_minor', v_opening, 'cash_sales_minor', v_cash_sales,
                       'expected_total_minor', v_expected, 'counted_total_minor', v_counted,
                       'variance_minor', v_variance, 'resolved_membership_id', v_membership));
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'cash_drawer.closed', nullif(btrim(coalesce(p_reason, '')), ''),
    jsonb_build_object('status', 'active', 'revision', v_drawer_rev),
    jsonb_build_object('cash_drawer_session_id', v_drawer_id, 'shift_id', p_shift_id, 'status', 'closed',
                       'opening_float_minor', v_opening, 'expected_total_minor', v_expected,
                       'counted_total_minor', v_counted, 'variance_minor', v_variance));

  -- (l) record ledger + return
  v_result := jsonb_build_object(
    'ok', true, 'shift_id', p_shift_id, 'cash_drawer_session_id', v_drawer_id, 'status', 'closed',
    'opening_float_minor', v_opening, 'cash_sales_minor', v_cash_sales,
    'expected_total_minor', v_expected, 'counted_total_minor', v_counted,
    'variance_minor', v_variance, 'revision', v_new_rev);
  insert into public.shift_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, shift_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'close_shift', p_shift_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.close_shift(uuid, uuid, uuid, text, bigint, text, integer) is
  'RF-055 (API_CONTRACT §4.9.1, D-011/D-028) SECURITY DEFINER RPC: the operator close/count step. Actor/scope from the PIN session. A cashier may close only their OWN shift; manager/restaurant_owner/org_owner may close on behalf; kitchen_staff/accountant denied -> shift.close_denied audit + permission_denied (no raise). Computes expected_total_minor = opening_float + completed cash payments for the drawer (MONEY §14; A6), counted_total_minor = p_counted_amount_minor (A4), variance_minor = counted - expected (signed). Non-empty reason REQUIRED when variance <> 0 (A7). Moves shift open->closed and drawer active->closed; persists amounts on both. Does NOT reconcile (separate RPC; D-028). Writes shift.closed + cash_drawer.closed (D-013). Idempotent via shift_operations (D-022, shift-bound).';

revoke all on function app.close_shift(uuid, uuid, uuid, text, bigint, text, integer) from public;
grant execute on function app.close_shift(uuid, uuid, uuid, text, bigint, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. app.reconcile_shift — the managerial sign-off step (API_CONTRACT §4.9.2).
--    SEPARATE from close (D-028). manager/restaurant_owner/org_owner only (NOT the
--    cashier who counted, NOT the read-only accountant). Moves shift closed->
--    reconciled and drawer closed->reconciled (terminal). Online-only / server-authoritative.
-- ----------------------------------------------------------------------------
create or replace function app.reconcile_shift(
  p_pin_session_id     uuid,
  p_shift_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_note               text default null,
  p_expected_revision  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_s_org        uuid;
  v_s_branch     uuid;
  v_s_status     text;
  v_s_rev        integer;
  v_s_variance   bigint;
  v_drawer_id    uuid;
  v_drawer_status text;
  v_drawer_rev   integer;
  v_new_rev      integer;
  v_stored       jsonb;
  v_stored_shift uuid;
  v_result       jsonb;
begin
  -- (a) PIN session + backing + actor/scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'reconcile_shift: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'reconcile_shift: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'reconcile_shift: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'reconcile_shift: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'reconcile_shift: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the shift; it MUST be in the actor's org + branch (no cross-tenant)
  select s.organization_id, s.branch_id, s.status, s.revision, s.variance_minor
    into v_s_org, v_s_branch, v_s_status, v_s_rev, v_s_variance
    from public.shifts s where s.id = p_shift_id;
  if not found then
    raise exception 'reconcile_shift: shift not found' using errcode = '42501';
  end if;
  if v_s_org <> v_org or v_s_branch <> v_branch then
    raise exception 'reconcile_shift: shift is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (D-028): manager/restaurant_owner/org_owner ONLY. cashier (incl.
  --     the one who counted), kitchen_staff, accountant denied -> shift.reconcile_denied
  --     audit + permission_denied (no raise). Separation of duties: the counting party
  --     must not approve its own variance.
  if v_role not in ('manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'shift.reconcile_denied', nullif(btrim(coalesce(p_note, '')), ''), null,
      jsonb_build_object('attempted_action', 'reconcile_shift', 'shift_id', p_shift_id,
                         'role', v_role, 'shift_status', v_s_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'shift_id', p_shift_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) idempotency replay (RF053-B1): AFTER authorization, SHIFT-BOUND.
  select so.result, so.shift_id into v_stored, v_stored_shift
    from public.shift_operations so
    where so.organization_id = v_org and so.device_id = p_device_id
      and so.local_operation_id = p_local_operation_id and so.action = 'reconcile_shift';
  if found then
    if v_stored_shift <> p_shift_id then
      raise exception 'reconcile_shift: idempotency key already used for a different shift (%, not %)', v_stored_shift, p_shift_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (e) ROW LOCKS (RF055-B1): lock the shift, then its bound cash drawer, FOR UPDATE in
  --     the SAME order as close_shift/record_payment. State + variance are RE-READ under
  --     the locks and validated only after they are held, so two concurrent reconciles
  --     with different local_operation_ids cannot both pass the guard and double-reconcile
  --     (no duplicate audit/ledger rows). Locks are released at COMMIT.
  select s.status, s.revision, s.variance_minor into v_s_status, v_s_rev, v_s_variance
    from public.shifts s where s.id = p_shift_id for update;
  select cds.id, cds.status, cds.revision
    into v_drawer_id, v_drawer_status, v_drawer_rev
    from public.cash_drawer_sessions cds
    where cds.organization_id = v_org and cds.shift_id = p_shift_id
    for update;
  if not found then
    raise exception 'reconcile_shift: no cash drawer session bound to the shift' using errcode = '42501';
  end if;

  -- (e2) state legality (validated UNDER the locks): shift closed, drawer closed
  if v_s_status <> 'closed' then
    raise exception 'reconcile_shift: shift status % is not a legal reconcile source state (expected closed)', v_s_status using errcode = '42501';
  end if;
  if v_drawer_status <> 'closed' then
    raise exception 'reconcile_shift: cash drawer status % is not a legal reconcile source state (expected closed)', v_drawer_status using errcode = '42501';
  end if;

  -- (f) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_s_rev then
    raise exception 'reconcile_shift: revision conflict (expected %, got %)', p_expected_revision, v_s_rev using errcode = '40001';
  end if;

  -- (g) note mandatory when variance is non-zero (A7)
  if coalesce(v_s_variance, 0) <> 0 and btrim(coalesce(p_note, '')) = '' then
    raise exception 'reconcile_shift: a non-empty note is required when the variance is non-zero (variance=%)', v_s_variance using errcode = '42501';
  end if;

  -- (h) mutate: shift closed->reconciled, drawer closed->reconciled (terminal)
  v_new_rev := v_s_rev + 1;
  update public.shifts
    set status = 'reconciled', reconcile_note = nullif(btrim(coalesce(p_note, '')), ''),
        reconciled_at = now(), reconciled_by_employee_profile_id = v_emp, revision = v_new_rev
    where id = p_shift_id;
  update public.cash_drawer_sessions
    set status = 'reconciled', reconciled_at = now(), revision = v_drawer_rev + 1
    where id = v_drawer_id;

  -- (i) audit: shift.reconciled + cash_drawer.reconciled (D-013)
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'shift.reconciled', nullif(btrim(coalesce(p_note, '')), ''),
    jsonb_build_object('status', 'closed', 'revision', v_s_rev),
    jsonb_build_object('shift_id', p_shift_id, 'status', 'reconciled', 'revision', v_new_rev,
                       'variance_minor', v_s_variance, 'resolved_membership_id', v_membership));
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'cash_drawer.reconciled', nullif(btrim(coalesce(p_note, '')), ''),
    jsonb_build_object('status', 'closed', 'revision', v_drawer_rev),
    jsonb_build_object('cash_drawer_session_id', v_drawer_id, 'shift_id', p_shift_id, 'status', 'reconciled'));

  -- (j) record ledger + return
  v_result := jsonb_build_object(
    'ok', true, 'shift_id', p_shift_id, 'cash_drawer_session_id', v_drawer_id,
    'status', 'reconciled', 'variance_minor', v_s_variance, 'revision', v_new_rev);
  insert into public.shift_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, shift_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'reconcile_shift', p_shift_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.reconcile_shift(uuid, uuid, uuid, text, text, integer) is
  'RF-055 (API_CONTRACT §4.9.2, D-011/D-028) SECURITY DEFINER RPC: the managerial reconciliation sign-off, SEPARATE from close (D-028 — one RPC must not do both). Actor/scope from the PIN session. manager/restaurant_owner/org_owner ONLY; cashier (incl. the counter), kitchen_staff, accountant denied -> shift.reconcile_denied audit + permission_denied (no raise). Requires shift+drawer at closed; moves both to reconciled (terminal). Non-empty note REQUIRED when variance <> 0 (A7). Writes shift.reconciled + cash_drawer.reconciled (D-013). Idempotent via shift_operations (D-022, shift-bound). Online-only / server-authoritative.';

revoke all on function app.reconcile_shift(uuid, uuid, uuid, text, text, integer) from public;
grant execute on function app.reconcile_shift(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 10. app.record_payment — CREATE OR REPLACE (A2). Identical to RF-054 EXCEPT it
--     now REQUIRES an open shift + active bound cash drawer for the (org, branch,
--     device) and STAMPS payments.shift_id / cash_drawer_session_id. The
--     precondition is checked AFTER the idempotency replay (a replay after the shift
--     closed still returns the stored payment). All other RF-054 behavior is verbatim.
-- ----------------------------------------------------------------------------
create or replace function app.record_payment(
  p_pin_session_id             uuid,
  p_order_id                   uuid,
  p_device_id                  uuid,
  p_local_operation_id         text,
  p_tender_type                text,
  p_amount_tendered_minor      bigint,
  p_provisional_receipt_number text default null,
  p_expected_revision          integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing       text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_o_org         uuid;
  v_o_branch      uuid;
  v_o_status      text;
  v_o_rev         integer;
  v_grand         bigint;
  v_currency      text;
  v_o_provisional text;
  v_completed_cnt integer;
  v_payable       bigint;
  v_change        bigint;
  v_receipt_seq   bigint;
  v_receipt_no    text;
  v_payment_id    uuid;
  v_new_rev       integer;
  v_stored        jsonb;
  v_stored_order  uuid;
  v_result        jsonb;
  v_shift_id      uuid;            -- RF-055: open shift for (org, branch, device)
  v_drawer_id     uuid;            -- RF-055: its active bound cash drawer
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'record_payment: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'record_payment: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'record_payment: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'record_payment: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'record_payment: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant)
  select o.organization_id, o.branch_id, o.status, o.revision,
         o.grand_total_minor, o.currency_code, o.receipt_provisional_id
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_grand, v_currency, v_o_provisional
    from public.orders o where o.id = p_order_id;
  if not found then
    raise exception 'record_payment: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'record_payment: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A7): cashier+ may record a cash payment. kitchen_staff/
  --     accountant/other denied -> payment.denied audit + permission_denied (no raise).
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'payment.denied', null, null,
      jsonb_build_object('attempted_action', 'record_payment', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) safe input validation
  if p_tender_type is null or p_tender_type <> 'cash' then
    raise exception 'record_payment: only cash tender is supported (got %)', coalesce(p_tender_type, '<null>') using errcode = '42501';
  end if;
  if p_amount_tendered_minor is null or p_amount_tendered_minor < 0 then
    raise exception 'record_payment: amount_tendered_minor must be a non-negative integer (minor units)' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + input validation, ORDER-BOUND.
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'record_payment';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'record_payment: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) eligible order states (D-025): pay-first supported. draft/cancelled/voided/completed excluded.
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    raise exception 'record_payment: order status % is not a legal payment source state', v_o_status using errcode = '42501';
  end if;

  -- (f2) RF-055 precondition + ROW LOCKS (A2/B2): there MUST be an open shift with an
  --      active bound cash drawer for this (org, branch, device). Lock the shift, then
  --      its active drawer, with FOR UPDATE in the SAME order as close_shift, so cash
  --      cannot be recorded against a drawer that closes underneath it. If close_shift
  --      holds the shift lock, this SELECT waits and then re-qualifies status (the shift
  --      is no longer 'open' / the drawer no longer 'active') -> precondition_failed; if
  --      this payment holds the lock first, close_shift waits and its expected-cash sum
  --      includes this sale (never stale). Checked AFTER the order-bound idempotency
  --      replay, so a replay after the shift closed still returns the stored payment
  --      (the lock/precondition is never reached on replay).
  select s.id into v_shift_id
    from public.shifts s
    where s.organization_id = v_org and s.branch_id = v_branch and s.device_id = p_device_id
      and s.status = 'open'
    for update
    limit 1;
  if not found then
    raise exception 'record_payment: no open shift for this branch/device (precondition_failed)' using errcode = '42501';
  end if;
  select cds.id into v_drawer_id
    from public.cash_drawer_sessions cds
    where cds.organization_id = v_org and cds.shift_id = v_shift_id and cds.status = 'active'
    for update
    limit 1;
  if not found then
    raise exception 'record_payment: no active cash drawer for the open shift (precondition_failed)' using errcode = '42501';
  end if;

  -- (g) at most one completed payment per order (no double-charge; D-024/D-025)
  select count(*) into v_completed_cnt
    from public.payments p
    where p.organization_id = v_org and p.order_id = p_order_id and p.status = 'completed';
  if v_completed_cnt > 0 then
    raise exception 'record_payment: order % already has a completed payment', p_order_id using errcode = '42501';
  end if;

  -- (h) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'record_payment: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (i) tender + change. payable = the order grand total (never recomputed). No cash rounding (MVP).
  v_payable := v_grand;
  if p_amount_tendered_minor < v_payable then
    raise exception 'record_payment: amount_tendered_minor (%) is less than the order total (%)', p_amount_tendered_minor, v_payable using errcode = '42501';
  end if;
  v_change := p_amount_tendered_minor - v_payable;

  -- (j) allocate the authoritative per-branch receipt number (D-021) under a ROW LOCK.
  insert into public.branch_receipt_counters as brc
      (organization_id, restaurant_id, branch_id, last_issued_value)
    values (v_org, v_rest, v_branch, 1)
    on conflict (organization_id, restaurant_id, branch_id) do update
      set last_issued_value = brc.last_issued_value + 1
    returning brc.last_issued_value into v_receipt_seq;
  v_receipt_no := v_receipt_seq::text;

  -- (k) insert the completed cash payment, STAMPED with the open shift + active drawer (A2)
  insert into public.payments (
    organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id,
    method, status, amount_minor, tendered_minor, change_minor, currency_code,
    receipt_number, provisional_receipt_number, local_operation_id, revision)
  values (
    v_org, v_rest, v_branch, p_order_id, p_device_id,
    v_emp, v_membership, v_shift_id, v_drawer_id,
    'cash', 'completed', v_payable, p_amount_tendered_minor, v_change, v_currency,
    v_receipt_no, p_provisional_receipt_number, p_local_operation_id, 1)
  returning id into v_payment_id;

  -- (l) set orders.receipt_number (+ keep any client provisional) and bump revision.
  --     DOES NOT change orders.status (D-025; A6 of RF-054).
  v_new_rev := v_o_rev + 1;
  update public.orders
    set receipt_number = v_receipt_no,
        receipt_provisional_id = coalesce(v_o_provisional, p_provisional_receipt_number),
        revision = v_new_rev
    where id = p_order_id;

  -- (m) audit: payment.recorded + receipt_number.assigned (A8/D-013). Replay returns earlier.
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'payment.recorded', null, null,
    jsonb_build_object(
      'payment_id',             v_payment_id,
      'order_id',               p_order_id,
      'method',                 'cash',
      'status',                 'completed',
      'amount_minor',           v_payable,
      'tendered_minor',         p_amount_tendered_minor,
      'change_minor',           v_change,
      'currency_code',          v_currency,
      'receipt_number',         v_receipt_no,
      'shift_id',               v_shift_id,
      'cash_drawer_session_id', v_drawer_id,
      'resolved_membership_id', v_membership));

  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'receipt_number.assigned', null,
    jsonb_build_object('receipt_number', null),
    jsonb_build_object(
      'order_id',         p_order_id,
      'payment_id',       v_payment_id,
      'branch_id',        v_branch,
      'receipt_number',   v_receipt_no,
      'receipt_sequence', v_receipt_seq,
      'order_revision',   v_new_rev));

  -- (n) record the idempotency ledger result + return
  v_result := jsonb_build_object(
    'ok', true, 'payment_id', v_payment_id, 'order_id', p_order_id,
    'receipt_number', v_receipt_no, 'change_due_minor', v_change,
    'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id,
    'payment_revision', 1, 'order_revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'record_payment', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) is
  'RF-054/RF-055 (API_CONTRACT §4.7, D-011) SECURITY DEFINER RPC: records a cash payment + assigns the per-branch receipt number (D-021). RF-055 (A2): now REQUIRES an open shift + active bound cash drawer for (org, branch, device) (else precondition_failed 42501) and STAMPS payments.shift_id/cash_drawer_session_id so close_shift can reconcile cash. All RF-054 behavior preserved: PIN-session auth (cross-tenant impossible); cashier+ only (kitchen_staff/accountant denied -> payment.denied + permission_denied); cash only; change = tendered - grand_total (>=0); order-bound idempotency (replay returns same payment_id + receipt_number, no dup audit); receipt allocated under row lock; at most one completed payment per order; does NOT advance orders.status; writes payment.recorded + receipt_number.assigned (D-013).';

revoke all on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) from public;
grant execute on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- -- restore the RF-054 record_payment (without the shift precondition/stamping):
-- --   re-run the RF-054 migration's CREATE OR REPLACE app.record_payment(...) body.
-- drop function if exists app.reconcile_shift(uuid, uuid, uuid, text, text, integer);
-- drop function if exists app.close_shift(uuid, uuid, uuid, text, bigint, text, integer);
-- drop function if exists app.open_shift(uuid, uuid, uuid, uuid, text, bigint);
-- alter table public.payments drop constraint if exists payments_cash_drawer_session_same_org;
-- alter table public.payments drop constraint if exists payments_shift_same_org;
-- drop index if exists public.payments_drawer_idx;
-- drop index if exists public.payments_shift_idx;
-- drop table if exists shift_operations;
-- drop table if exists cash_drawer_sessions;
-- drop table if exists shifts;
-- ============================================================================
